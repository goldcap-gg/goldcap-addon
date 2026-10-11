local helper = require("spec.spec_helper")

-- The BUY tab's render, exercised the way spec/soldframe_spec.lua exercises Sold's: the real
-- Core/BuyRun.lua and Core/BagStock.lua underneath, fake widgets above, and the row pool / header
-- band reached through GC.Buy._view. Only the two things a headless run genuinely cannot have --
-- the client's bag API and the market-value lookup -- are stubbed.
describe("BuyFrame", function()
  local GC, rowsOf, containerOf, bandOf
  local textWidth, stringHeight

  local NAMES = { [101] = "Alpha Herb", [102] = "Bravo Ore", [103] = "Charlie Dust",
                  [104] = "Delta Vial" }

  -- Four lines: two open, one already covered by the bags, one at the vendor. That is every
  -- state a row can be in, in one run.
  local function run(over)
    local r = {
      code = "run-1", name = "Flask run", updatedAt = 100, origin = "app",
      lines = {
        { i = 101, q = 10 },
        { i = 102, q = 5 },
        { i = 103, q = 3 },
        { i = 104, q = 20, v = true },
      },
    }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
  end

  local function region(kind, parent)
    -- `points`/`scripts` are bookkeeping the doubles alone define -- see ui_widget_field_spec's
    -- DOUBLE_ONLY guard, which fails the suite if production ever reads them.
    local r = { __frame = true, kind = kind, children = {}, textValue = nil, visible = true,
                enabled = true, points = {}, scripts = {} }
    function r:SetPoint(point, relative, relativePoint, x, y)
      self.points[#self.points + 1] = { point = point, relative = relative,
                                        relativePoint = relativePoint, x = x, y = y }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() self.points[#self.points + 1] = { point = "ALL" } end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetWordWrap() end
    function r:SetMaxLines(n) self.maxLines = n end
    function r:SetTextColor(...) self.colorValue = { ... } end
    function r:SetColorTexture(...) self.colorTexture = { ... } end
    function r:SetTexture(f) self.texture = f end
    function r:SetTexCoord() end
    function r:SetTextureSliceMargins(...) self.sliceMargins = { ... } end
    function r:SetVertexColor(...) self.vertexColor = { ... } end
    function r:SetSpacing(s) self.spacing = s end
    -- The client's rule: on a texture, SetAlpha writes the alpha SetVertexColor's fourth
    -- argument set -- so a wash "switched" with it repaints at full strength.
    function r:SetAlpha(a)
      self.alpha = a
      if self.kind == "Texture" and self.vertexColor then self.vertexColor[4] = a end
    end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    -- The client's own measurements, off unless a test gives them an answer (textWidth,
    -- stringHeight below): production code falls back to its least widths without them.
    function r:GetUnboundedStringWidth() return textWidth and textWidth(self.textValue or "") or nil end
    function r:GetStringHeight() return stringHeight and stringHeight(self) or 12 end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:GetParent() return parent end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:SetAutoFocus(on) self.autoFocus = on end
    function r:HasFocus() return self.focused == true end
    function r:SetFocus() self.focused = true end
    function r:ClearFocus() self.focused = false end
    function r:Insert(t) self.textValue = (self.textValue or "") .. t end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:EnableMouse() end
    function r:RegisterForClicks() end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:IsEnabled() return self.enabled end
    function r:CreateTexture() return region("Texture", self) end
    function r:CreateFontString() return region("FontString", self) end
    if parent then parent.children[#parent.children + 1] = r end
    return r
  end

  -- Theme.Button's real contract: `.label` is the caller's exact source string and `.text` is
  -- what gets drawn (UI/Theme.lua's SetLabel writes both).
  local function button(parent)
    local b = region("Button", parent)
    b.text = region("FontString", b)
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    function b:SetVariant() end
    function b:SetUppercase() end
    return b
  end

  -- One bag (0) with five Bravo Ore in it; every other bag empty. `bagWalks` counts how many
  -- times the whole six-bag walk actually ran, which is what proves a skipped scan is skipped
  -- rather than merely un-rendered.
  local bagWalks = 0
  local function stubBags(contents)
    _G.C_Container = {
      GetContainerNumSlots = function(bag)
        if bag == 0 then bagWalks = bagWalks + 1 end
        return bag == 0 and 4 or 0
      end,
      GetContainerItemInfo = function(bag, slot)
        if bag ~= 0 then return nil end
        local entry = contents[slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.qty, isBound = entry.bound == true,
                 hyperlink = "|Hitem:" .. entry.itemID .. "|h" }
      end,
      GetContainerItemLink = function() return nil end,
    }
  end

  -- The client's own count API, which is the only thing that knows what the banks hold: there is
  -- no container to walk for a bank the player has not opened. `all` is what it answers when
  -- asked to include the character bank, the reagent bank and the warband bank; `carried` what it
  -- answers for the bags alone. Two raw numbers rather than a bags/bank pair, so a spec can hand
  -- back a pair a live client really gives -- including one where the carried number is larger.
  local function stubItemCount(byItem)
    _G.C_Item.GetItemCount = function(itemID, includeBank, _, includeReagentBank, includeAccountBank)
      local entry = byItem[itemID]
      if not entry then return 0 end
      if includeBank and includeReagentBank and includeAccountBank then return entry.all end
      return entry.carried
    end
  end

  before_each(function()
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    -- The client's own name lookup, the way Core/ItemNames.lua reaches it. GetItemIconByID is
    -- deliberately absent: a headless run resolves no icons, so rows stay flush left.
    _G.C_Item = { GetItemInfo = function(id) return NAMES[id] end }
    _G.time = function() return 2000 end
    stubBags({ [1] = { itemID = 102, qty = 5 } })

    GC = helper.loadModule("Core/Util.lua")
    GC.Theme = {
      MEDIA = "",
      color = { fg = {1,1,1}, fgMuted = {0.8,0.8,0.8}, fgDim = {0.55,0.54,0.52},
                gold = {0.83,0.64,0.22}, red = {1,0,0}, green = {0,1,0}, panel = {0,0,0},
                bg = {0,0,0}, zebra = {1,1,1,0.04}, hover = {1,1,1,0.08}, border = {1,1,1,0.06} },
      tier = { SUSPECT = {1,1,0} },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      Label = function(parent, _) return region("FontString", parent) end,
      Num = function(parent, _, _) return region("FontString", parent) end,
      Button = function(parent) return button(parent) end,
      SlicedTexture = function(parent) return region("Texture", parent) end,
      WithQuality = function(name) return name end,
      -- UI/Theme.lua's own opens GameTooltip on the row, placed beside the window.
      ItemTooltipOutside = function(row) _G.GameTooltip:SetOwner(row, "ANCHOR_NONE") end,
    }
    GC.db = { settings = { sniper = { buyCapPct = 130 } } }
    GC.Data = { GetItemValue = function(itemID)
      return ({ [101] = { mv = 1000 }, [102] = { mv = 2000 }, [103] = { mv = 3000 } })[itemID]
    end }
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)
    helper.loadModule("Core/NameMatch.lua", GC)
    helper.loadModule("Core/BuyView.lua", GC)
    helper.loadModule("Core/BuyDock.lua", GC)

    local runs = { run() }
    GC.AppRuns = {
      -- The real List answers with exactly ONE group (Core/AppRuns.lua): the live runs, or the
      -- archived ones when asked for them. Nothing is archived in this double, so the archived
      -- group is empty and the run menu grows no archived section.
      List = function(opts)
        if type(opts) == "table" and opts.archived == true then return {} end
        return runs
      end,
      Get = function(code)
        for _, r in ipairs(runs) do if r.code == code then return r end end
      end,
      Remove = function(code)
        for i, r in ipairs(runs) do if r.code == code then table.remove(runs, i); return true end end
        return false
      end,
      -- What the picker and the column ask of a list (Core/AppRuns.lua's own answers for a double
      -- that keeps no favourites and no order of its own).
      IsLocal = function(r) return r.origin == "game" or r.origin == "paste" end,
      Label = function(r) return r.name or r.code end,
      IsFavourite = function() return false end,
      CanMove = function() return false end,
      _set = function(list) runs = list end,
    }

    helper.loadModule("Core/ListStrings.lua", GC)
    helper.loadModule("Core/BuyRecents.lua", GC)
    helper.loadModule("UI/BuyFrame.lua", GC)
    helper.loadModule("UI/BuyLists.lua", GC)
    helper.loadModule("UI/BuyAddBox.lua", GC)

    -- GC.Buy._view is the one seam BUY exposes for specs (set at Attach); no upvalue chains.
    rowsOf = function() return GC.Buy._view.rows end
    containerOf = function() return GC.Buy._view.container end
    bandOf = function() return GC.Buy._view.band end

    local host = region("Frame")
    GC.Buy.Attach(host, { panelLeft = 88, panelRightInset = 32, top = -100,
                          bottom = 34, rowWidth = 600, rowHeight = 28 })
    GC.Buy.Show()
  end)

  after_each(function()
    textWidth, stringHeight = nil, nil
    _G.CreateFrame, _G.GetCoinTextureString, _G.C_Item, _G.C_Container = nil, nil, nil, nil
    _G.GameTooltip, _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil, nil
    _G.GetItemCount, _G.GoldCap_AppRuns = nil, nil
  end)

  local function shownRows()
    local out = {}
    for _, row in ipairs(rowsOf()) do
      if row:IsShown() then out[#out + 1] = row end
    end
    return out
  end

  local function rowWithText(pattern)
    for _, row in ipairs(shownRows()) do
      local text = (row.reagent:GetText() or "") .. (row.wide:GetText() or "")
      if text:find(pattern, 1, true) then return row end
    end
  end

  -- BUY 2.0: no row carries a button. A left click on a row picks its line for the dock at the
  -- foot of the tab, whose one button buys it.
  local function dock() return GC.Buy._view.dock end
  -- BUY 2.0's rows show what is left to buy beside the name; need, have and buy themselves are the
  -- run's arithmetic, read off the line a row shows.
  local function lineOfRow(row)
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do if l.itemID == row.lineItemID then return l end end
  end
  local function pick(row) row.scripts.OnMouseUp(row, "LeftButton") end

  -- The client's GameTooltip, as far as a line's tooltip uses it. `lines` are its AddLine calls
  -- (text and colour), `all` every line in order, the double ones as "left | right", the game's
  -- own lines for an item as one "item:<id>".
  local function tooltipOn(row)
    local lines, all = {}, {}
    _G.GameTooltip = {
      SetOwner = function() end, IsOwned = function() return true end,
      SetText = function(_, text) all[#all + 1] = text end,
      SetItemByID = function(_, id) all[#all + 1] = "item:" .. tostring(id) end,
      AddLine = function(_, text, r, g, b)
        lines[#lines + 1] = { text = text, color = { r, g, b } }
        all[#all + 1] = text
      end,
      AddDoubleLine = function(_, left, right) all[#all + 1] = left .. " | " .. right end,
      Show = function() end, Hide = function() end,
    }
    row.scripts.OnEnter(row)
    _G.GameTooltip = nil
    return lines, all
  end
  local function lineWith(lines, text)
    for _, l in ipairs(lines) do if (l.text or ""):find(text, 1, true) then return l end end
  end

  local function shownTexts()
    local out = {}
    for _, row in ipairs(shownRows()) do
      out[#out + 1] = (row.reagent:GetText() or "") .. " | " .. (row.wide:GetText() or "")
    end
    return table.concat(out, "\n")
  end

  it("names each line with what is left to buy, and keeps its need, have and buy", function()
    local alpha, bravo = rowWithText("Alpha Herb"), rowWithText("Bravo Ore")
    assert.truthy(alpha and bravo)
    assert.equal("10", tostring(lineOfRow(alpha).need))
    assert.equal("0", tostring(lineOfRow(alpha).have))
    assert.equal("10", tostring(lineOfRow(alpha).buy))
    -- Five in the bags covers the whole need: nothing left to buy, and the row says "done"
    -- rather than offering a BUY 0 button.
    assert.equal("5", tostring(lineOfRow(bravo).have))
    assert.equal("0", tostring(lineOfRow(bravo).buy))
    assert.equal("Alpha Herb ×10", alpha.reagent:GetText())
    assert.equal("bought", bravo.status:GetText())
    pick(bravo)
    assert.is_false(dock().buy:IsShown())
  end)

  -- HAVE is what the player owns, not what they happen to be carrying: three hundred units in
  -- the bank are three hundred units nobody has to go shopping for.
  it("counts bank stock into HAVE alongside the bags", function()
    stubItemCount({ [102] = { all = 305, carried = 5 } })
    GC.Buy.Show()
    assert.equal("305", tostring(lineOfRow(rowWithText("Bravo Ore")).have))
  end)

  it("needs no shopping trip for a line the bank alone covers", function()
    stubItemCount({ [101] = { all = 12, carried = 0 } })
    GC.Buy.Show()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("12", tostring(lineOfRow(alpha).have))
    assert.equal("0", tostring(lineOfRow(alpha).buy))
    assert.equal("bought", alpha.status:GetText())
    pick(alpha)
    assert.is_false(dock().buy:IsShown())
  end)

  it("counts only the bags when the client has no item-count API", function()
    _G.C_Item.GetItemCount, _G.GetItemCount = nil, nil
    GC.Buy.Show()
    assert.equal("0", tostring(lineOfRow(rowWithText("Alpha Herb")).have))
    assert.equal("5", tostring(lineOfRow(rowWithText("Bravo Ore")).have))
  end)

  -- Older clients expose the count as a plain global instead of on C_Item; it is the same call
  -- and HAVE has to read the same either way.
  it("reads the count through the global API when C_Item has none", function()
    _G.GetItemCount = function(itemID, includeBank, _, includeReagentBank, includeAccountBank)
      if itemID ~= 102 then return 0 end
      if includeBank and includeReagentBank and includeAccountBank then return 105 end
      return 5
    end
    GC.Buy.Show()
    assert.equal("105", tostring(lineOfRow(rowWithText("Bravo Ore")).have))
  end)

  -- An API that throws must cost the player the bank number, never the bag number.
  it("keeps the bag count when the item-count API errors", function()
    _G.C_Item.GetItemCount = function() error("no item") end
    GC.Buy.Show()
    assert.equal("5", tostring(lineOfRow(rowWithText("Bravo Ore")).have))
  end)

  -- The bank is a subtraction, and a subtraction can come out below zero the moment the two
  -- answers disagree -- which would take stock the player is carrying back off HAVE.
  it("never lets the bank number pull HAVE below the bags", function()
    stubItemCount({ [102] = { all = 2, carried = 5 } })
    GC.Buy.Show()
    assert.equal("5", tostring(lineOfRow(rowWithText("Bravo Ore")).have))
  end)

  it("splits HAVE into bags and bank on the row tooltip when the bank holds any", function()
    stubItemCount({ [102] = { all = 305, carried = 5 } })
    GC.Buy.Show()
    local lines = tooltipOn(rowWithText("Bravo Ore"))
    assert.truthy(lineWith(lines, "in bags 5, in bank 300"))
  end)

  it("says nothing about the bank on the tooltip when there is none in it", function()
    GC.Buy.Show()
    local lines = tooltipOn(rowWithText("Bravo Ore"))
    assert.is_nil(lineWith(lines, "in bank"))
  end)

  it("says how many are left to buy of how many, and how many the player has", function()
    stubItemCount({ [101] = { all = 4, carried = 0 } })
    GC.Buy.Show()
    local lines, all = tooltipOn(rowWithText("Alpha Herb"))
    assert.equal("item:101", all[1])
    assert.truthy(lineWith(lines, "buy 6 of 10, have 4 in bags and bank"))
  end)

  -- At rest -- nothing quoted yet -- the button names the quantity and nothing else. What a
  -- click does from there, and what the label becomes, is spec/buy_purchase_spec.lua's.
  it("offers a BUY button for the quantity still missing", function()
    pick(rowWithText("Alpha Herb"))
    assert.truthy(dock().buy:IsShown())
    assert.equal("BUY 10", dock().buy.label)
    assert.is_true(dock().buy:IsEnabled())
  end)

  -- BUY 2.0 week 2: the vendor panel (UI/BuyVendorPanel.lua) asks the tab for its vendor lines, and
  -- books what a press bought against the list -- never as a ledger row, which is auction house money.
  it("answers the vendor panel with every line a merchant could sell, with its cap", function()
    local answer = GC.Buy.VendorLines()
    local byID = {}
    for _, line in ipairs(answer.lines) do byID[line.itemID] = line end
    -- An auction line too: a quick list has no vendor lines, and a merchant may sell any of them.
    assert.same({ itemID = 101, buy = 10, need = 10, cap = 1300, name = "Alpha Herb" }, byID[101])
    assert.equal(20, byID[104].buy)
    assert.equal(0, byID[102].buy) -- done: still listed, so a line bought here can say so
  end)

  it("never offers the vendor panel a line it crafts or one skipped for the session", function()
    GC.AppRuns._set({ run({ lines = { { i = 101, q = 10, mk = true }, { i = 103, q = 2 }, { i = 104, q = 3 } } }) })
    GC.Buy.SelectRun("run-1")
    GC.Buy._skipped["run-1"] = { [104] = true }
    local ids = {}
    for _, line in ipairs(GC.Buy.VendorLines().lines) do ids[#ids + 1] = line.itemID end
    assert.same({ 103 }, ids)
  end)

  it("books a vendor purchase against the list and writes no ledger row", function()
    local appended = 0
    GC.Ledger = { Append = function() appended = appended + 1 end }
    GC.Buy.RecordVendorPurchase(104, 20, 200, GC.Buy.CurrentRun():Code())
    local line
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do if l.itemID == 104 then line = l end end
    assert.equal(20, line.bought)
    assert.equal(200, line.spent)
    assert.is_true(line.done)
    assert.equal(0, appended)
  end)

  it("credits a vendor purchase to the list the press was for, never to another one", function()
    GC.Buy.RecordVendorPurchase(104, 20, 200, "some-other-list")
    GC.Buy.RecordVendorPurchase(104, 20, 200, nil)
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do
      if l.itemID == 104 then assert.is_true((l.bought or 0) == 0) end
    end
  end)

  it("credits a vendor purchase to its list even after another list was opened", function()
    GC.AppRuns._set({ run(), run({ code = "run-2", name = "Other run" }) })
    GC.Buy.SelectRun("run-1")
    GC.Buy.SelectRun("run-2")
    GC.Buy.RecordVendorPurchase(104, 20, 200, "run-1")
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do
      if l.itemID == 104 then assert.is_true((l.bought or 0) == 0) end
    end
    GC.Buy.SelectRun("run-1")
    local line
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do if l.itemID == 104 then line = l end end
    assert.equal(20, line.bought)
    assert.equal(200, line.spent)
  end)

  -- A gear line's bid that never got an answer may have bought its lot (delivered by mail), so the
  -- line offers what is left less one per such bid -- not its whole remaining quantity -- and is
  -- held once the bids cover what is left.
  it("offers a line's remaining quantity less its unanswered bids", function()
    local function alpha()
      for _, row in ipairs(shownRows()) do
        if (row.reagent:GetText() or ""):find("Alpha Herb", 1, true) then return row end
      end
    end
    GC.Buy._bidStranded[9001] = { itemID = 101, have = 0, at = time() }
    GC.Buy.RefreshIfShown()
    assert.equal("Alpha Herb ×9", alpha().reagent:GetText())
    GC.Buy._bidStranded[9002] = { itemID = 101, have = 0, at = time() }
    GC.Buy.RefreshIfShown()
    assert.equal("Alpha Herb ×8", alpha().reagent:GetText())
    -- another item's bid, or one the bags have since moved past, takes nothing off this line
    GC.Buy._bidStranded[9003] = { itemID = 103, have = 0, at = time() }
    GC.Buy._bidStranded[9004] = { itemID = 101, have = 7, at = time() }
    GC.Buy.RefreshIfShown()
    assert.equal("Alpha Herb ×8", alpha().reagent:GetText())
    GC.Buy._bidStranded = {}
  end)

  it("puts the vendor line after the open ones and the finished line last", function()
    local lineRows = {}
    for _, row in ipairs(shownRows()) do
      if (row.reagent:GetText() or "") ~= "" then lineRows[#lineRows + 1] = row end
    end
    assert.equal(4, #lineRows)
    -- 101 open, 103 open, 104 vendor, 102 done -- the bags already cover 102.
    assert.equal("Alpha Herb ×10", lineRows[1].reagent:GetText())
    assert.equal("Charlie Dust ×3", lineRows[2].reagent:GetText())
    assert.equal("Delta Vial ×20", lineRows[3].reagent:GetText())
    assert.equal("at a vendor", lineRows[3].status:GetText())
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      lineRows[3].reagent.colorValue)
    assert.equal("Bravo Ore ×5", lineRows[4].reagent:GetText())
    assert.equal("bought", lineRows[4].status:GetText())
  end)

  -- The tab limits nothing: every line of a run is the player's to buy. The companion still
  -- writes `plan` and `freeLines` into the runs file (the site's own contract keeps the fields),
  -- so this adopts a file that says "free, five" for real -- through Core/AppRuns.lua, not the
  -- double above -- and then counts BUY buttons. Eight lines in, eight buttons out: a run
  -- rendered with no action on a row would fail here, and so would one with a notice row.
  it("offers a BUY button on every line of a run, whatever the runs file says about a plan", function()
    local names, runLines = {}, {}
    for i = 1, 8 do
      names[200 + i] = "Line " .. i
      runLines[i] = { i = 200 + i, q = 2 }
    end
    _G.C_Item.GetItemInfo = function(id) return names[id] end
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1500, plan = "free", freeLines = 5,
      runs = { { code = "run-8", name = "Eight lines", updatedAt = 1400, lines = runLines } } }
    GC.db.runs, GC.db.runNotices = {}, {}
    helper.loadModule("Core/AppRuns.lua", GC)   -- the real one, over the double
    assert.is_true(GC.AppRuns.Adopt())
    GC.db.settings.sniper.buyRun = "run-8"
    GC.Buy.Show()

    for i = 1, 8 do
      local row = rowWithText("Line " .. i)
      assert.truthy(row, "no row for line " .. i)
      pick(row)
      assert.is_true(dock().buy:IsShown())
      assert.equal("BUY 2", dock().buy.label)
    end
    -- ...and nothing was added under them to explain a limit that no longer exists.
    assert.equal(8, #shownRows())
  end)

  it("says in the band how many of the run's lines are done", function()
    -- Bravo Ore is covered by the five in the bag; the other three are still open.
    assert.equal("1 of 4 done", bandOf().done:GetText())
  end)

  -- Spec rule 5: a run with nothing left says so -- the band counts every line done, and the
  -- dock says everything here is bought.
  it("says everything is bought when the run has nothing left", function()
    GC.AppRuns._set({ run({ code = "run-d", updatedAt = 900,
      lines = { { i = 102, q = 5 }, { i = 104, q = 0, v = true } } }) })
    GC.db.settings.sniper.buyRun = "run-d"
    GC.Buy.Show()
    assert.equal("2 of 2 done", bandOf().done:GetText())
    assert.equal("Everything here is bought", dock().title:GetText())
    assert.equal("-", bandOf().total:GetText())
  end)

  it("draws the progress bar over the done share of the run", function()
    containerOf().width = 600
    GC.Buy.RefreshIfShown()
    assert.is_true(bandOf().fill:IsShown())
    assert.equal(150, bandOf().fill.width) -- one of four done
  end)

  it("names the run on the picker and cycles to the next one, remembering the choice", function()
    GC.AppRuns._set({ run(), run({ code = "run-2", name = "Potion run" }) })
    GC.Buy.SelectRun("run-1")
    local band = bandOf()
    assert.equal("Flask run ▼", band.picker.label)

    band.picker.scripts.OnClick(band.picker)
    assert.equal("Potion run ▼", band.picker.label)
    assert.equal("run-2", GC.db.settings.sniper.buyRun)
    assert.equal("run-2", GC.Buy.CurrentRun():Code())

    -- ...and wraps back around to the first.
    band.picker.scripts.OnClick(band.picker)
    assert.equal("run-1", GC.db.settings.sniper.buyRun)
  end)

  it("opens a menu of lists with the shown list's own actions, a new list and an import", function()
    GC.AppRuns._set({ run(), run({ code = "run-2", name = "Potion run", origin = "paste" }) })
    GC.Buy.SelectRun("run-2")
    local entries
    _G.MenuUtil = {
      CreateContextMenu = function(_, generator)
        entries = {}
        local root = {
          CreateTitle = function(_, text) entries[#entries + 1] = { kind = "title", text = text } end,
          CreateButton = function(_, text, fn) entries[#entries + 1] = { kind = "button", text = text, fn = fn } end,
          CreateDivider = function() entries[#entries + 1] = { kind = "divider" } end,
        }
        generator(nil, root)
      end,
    }
    local band = bandOf()
    band.picker.scripts.OnClick(band.picker)
    _G.MenuUtil = nil
    local texts = {}
    for _, e in ipairs(entries) do texts[#texts + 1] = e.text or e.kind end
    -- A menu draws in the client's font, which on the Russian client has no "·" (it drew a box):
    -- the entries are joined with commas.
    assert.same({ "Runs", "   Flask run, 4 lines, goldcap.gg", "• Potion run, 4 lines, in game",
      "divider", "Cap: 130%", "Rename…", "Add to favourites", "Export", "Import into this list…",
      "Archive this run", "Delete this list…", "Copy vendor list", "divider", "New list", "Import a list…" },
      texts)

    -- Delete asks first, in the kit's popup, and then drops the list and lands on the one left.
    local asked
    GC.BuyCapEditor = { Open = function(anchor, opts) asked = { anchor = anchor, opts = opts } end }
    entries[11].fn()
    assert.equal(bandOf().picker, asked.anchor)
    assert.is_false(asked.opts.box)
    assert.equal("Delete Potion run? This cannot be undone.", asked.opts.title)
    assert.equal("Delete", asked.opts.setLabel)
    assert.is_not_nil(GC.AppRuns.Get("run-2"))
    asked.opts.onCommit(true)
    assert.is_nil(GC.AppRuns.Get("run-2"))
    assert.equal("run-1", GC.Buy.CurrentRun():Code())
    assert.equal("Flask run ▼", bandOf().picker.label)
  end)

  it("says a goldcap.gg list is renamed and removed on the site, not here", function()
    GC.AppRuns._set({ run() })
    GC.Buy.SelectRun("run-1")
    local entries = {}
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      generator(nil, {
        CreateTitle = function(_, text) entries[#entries + 1] = text end,
        CreateButton = function(_, text) entries[#entries + 1] = text end,
        CreateDivider = function() end,
      })
    end }
    local band = bandOf()
    band.picker.scripts.OnClick(band.picker)
    _G.MenuUtil = nil
    assert.same({ "Runs", "• Flask run, 4 lines, goldcap.gg", "Cap: 130%", "Add to favourites", "Export",
      "Archive this run", "From goldcap.gg: rename or remove it there", "Copy vendor list", "New list",
      "Import a list…" }, entries)
  end)

  -- Spec rule 6: a run can carry its own cap. The radio that reads as selected for a run with no
  -- cap of its own is the global one, because that is the cap the run is actually judged against.
  it("offers a cap submenu whose selection is the run's own cap, or the global one", function()
    GC.AppRuns._set({ run() })
    GC.Buy.SelectRun("run-1")
    local capEntries, capLabel
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      capEntries = {}
      local submenu = {
        CreateRadio = function(_, text, isSelected, setSelected, data)
          capEntries[#capEntries + 1] = { text = text, selected = isSelected(data),
                                          set = function() setSelected(data) end }
        end,
      }
      generator(nil, {
        CreateTitle = function() end,
        CreateButton = function(_, text)
          if text:find("Cap:", 1, true) then capLabel = text; return submenu end
        end,
        CreateDivider = function() end,
      })
    end }
    local band = bandOf()
    band.picker.scripts.OnClick(band.picker)
    _G.MenuUtil = nil

    assert.equal("Cap: 130%", capLabel)
    local texts, selected = {}, {}
    for _, entry in ipairs(capEntries) do
      texts[#texts + 1] = entry.text
      if entry.selected then selected[#selected + 1] = entry.text end
    end
    assert.same({ "100%", "110%", "120%", "130%", "150%", "200%", "300%" }, texts)
    assert.same({ "130%" }, selected)   -- the global setting, until this run is given its own

    -- Picking one writes it against this run alone and the lines re-cap at once.
    capEntries[5].set()
    assert.equal(150, GC.db.runCaps["run-1"])
    local capOf = function(itemID)
      for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do
        if l.itemID == itemID then return l.cap end
      end
    end
    assert.equal(1500, capOf(101))                          -- 1000 mv at 150%
    assert.equal(130, GC.db.settings.sniper.buyCapPct)      -- the global is untouched
  end)

  -- Spec rule 5: a finished run is archived from the run menu, leaves the picker, and comes back
  -- from the archived section at the bottom of that same menu.
  it("archives the run on screen and restores it from the menu", function()
    GC.db.runsArchived = {}
    local archived = {}
    GC.AppRuns.IsArchived = function(code) return archived[code] == true end
    GC.AppRuns.SetArchived = function(code, value) archived[code] = value and true or nil; return true end
    local allRuns = { run(), run({ code = "run-2", name = "Potion run" }) }
    GC.AppRuns._set(allRuns)
    GC.AppRuns.List = function(opts)
      local want = type(opts) == "table" and opts.archived == true
      local out = {}
      for _, r in ipairs(allRuns) do
        if (archived[r.code] == true) == want then out[#out + 1] = r end
      end
      return out
    end
    GC.Buy.SelectRun("run-1")

    local entries
    local function openMenu()
      entries = {}
      _G.MenuUtil = { CreateContextMenu = function(_, generator)
        generator(nil, {
          CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
          CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn }; return nil end,
          CreateDivider = function() entries[#entries + 1] = { text = "divider" } end,
        })
      end }
      local band = bandOf()
      band.picker.scripts.OnClick(band.picker)
      _G.MenuUtil = nil
    end
    local function entryNamed(text)
      for _, e in ipairs(entries) do if e.text == text then return e end end
    end

    openMenu()
    assert.truthy(entryNamed("Archive this run"))
    assert.is_nil(entryNamed("Archived"))
    entryNamed("Archive this run").fn()

    assert.is_true(archived["run-1"])
    -- The picker moves to the run that is left rather than sitting on one it no longer offers.
    assert.equal("run-2", GC.Buy.CurrentRun():Code())
    assert.equal("Potion run ▼", bandOf().picker.label)

    openMenu()
    assert.truthy(entryNamed("Archived"))
    local restore = entryNamed("Restore Flask run")
    assert.truthy(restore)
    restore.fn()
    assert.is_nil(archived["run-1"])
    assert.equal("run-1", GC.Buy.CurrentRun():Code())
  end)

  -- Finding 1: a purchase already committed to `current`. Re-pointing the cap or archiving the
  -- run before it settles would strand the gold -- `settlePurchase` books it against `current`,
  -- and this run would no longer be it (SelectRun keeps the attempt, but the archived run's own
  -- buyProgress never sees the purchase). Cap and archive drop from the menu; runs/remove/paste
  -- stay exactly as they were.
  it("keeps the run's cap and archive out of reach while a purchase is in flight", function()
    local archived = {}
    GC.AppRuns.SetArchived = function(code, value) archived[code] = value and true or nil; return true end
    local allRuns = { run(), run({ code = "run-2", name = "Potion run" }) }
    GC.AppRuns._set(allRuns)
    GC.AppRuns.List = function(opts)
      local want = type(opts) == "table" and opts.archived == true
      local out = {}
      for _, r in ipairs(allRuns) do
        if (archived[r.code] == true) == want then out[#out + 1] = r end
      end
      return out
    end
    GC.Buy.SelectRun("run-1")

    local entries
    local function openMenu()
      entries = {}
      _G.MenuUtil = { CreateContextMenu = function(_, generator)
        generator(nil, {
          CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
          CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn }; return nil end,
          CreateDivider = function() entries[#entries + 1] = { text = "divider" } end,
        })
      end }
      local band = bandOf()
      band.picker.scripts.OnClick(band.picker)
      _G.MenuUtil = nil
    end
    local function entryNamed(text)
      for _, e in ipairs(entries) do if e.text == text then return e end end
    end

    -- At rest, both are on offer -- and this is where Archive's own handler comes from.
    openMenu()
    local archiveFn = entryNamed("Archive this run").fn
    assert.truthy(entryNamed("Cap: 130%"))

    -- Drive an attempt to "started" the way buy_purchase_spec does: this is the stage a click
    -- on BUY leaves it in the instant the server has been asked, well before success or failure.
    GC.Buy._attempt = { stage = "started", itemID = 101, qty = 5, total = 5000 }
    openMenu()
    assert.is_nil(entryNamed("Cap: 130%"))
    assert.is_nil(entryNamed("Archive this run"))
    assert.truthy(entryNamed("Import a list…"))

    -- Belt and braces: the handler captured before the purchase started still refuses to act
    -- while one is in flight, even reached directly.
    archiveFn()
    assert.is_nil(archived["run-1"])
    assert.equal("run-1", GC.Buy.CurrentRun():Code())

    -- Once it settles, the same handler archives normally.
    GC.Buy._attempt = nil
    archiveFn()
    assert.is_true(archived["run-1"])
    assert.equal("run-2", GC.Buy.CurrentRun():Code())
  end)

  it("judges a run with no cap of its own by the global setting, and clamps a silly one", function()
    GC.AppRuns._set({ run() })
    GC.Buy.SelectRun("run-1")
    local capOf = function(itemID)
      for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do
        if l.itemID == itemID then return l.cap end
      end
    end
    assert.equal(1300, capOf(101))
    GC.db.runCaps = { ["run-1"] = 900 }      -- hand-edited SavedVariables
    GC.Buy.RefreshIfShown()
    assert.equal(3000, capOf(101))           -- clamped to 300%, not 900%
  end)

  it("reopens on the remembered run rather than the newest one", function()
    GC.AppRuns._set({ run({ code = "run-2", name = "Potion run" }), run() })
    GC.db.settings.sniper.buyRun = "run-1"
    GC.Buy.Show()
    assert.equal("run-1", GC.Buy.CurrentRun():Code())
    assert.equal("Flask run ▼", bandOf().picker.label)
  end)

  it("shows the first-time state with the item box, and hides the picker, when there are no runs", function()
    GC.AppRuns._set({})
    GC.db.settings.sniper.buyRun = nil
    GC.Buy.Show()
    assert.is_nil(GC.Buy.CurrentRun())
    local text = shownTexts()
    assert.truthy(text:find("Make a list once, buy it here at or under your price.", 1, true))
    assert.truthy(text:find("or plan a whole profession on goldcap.gg", 1, true))
    local add = GC.Buy._view.add
    assert.is_true(add.frame:IsShown())
    assert.equal("Item to add", add.hint:GetText())
    assert.equal("Shift-click items, type a name, or an item id with x and a count: 2589 x20.", add.note:GetText())
    -- No list, no band: the words come straight under the box.
    assert.is_false(bandOf().frame:IsShown())
    assert.is_false(bandOf().picker:IsShown())
    assert.equal("", bandOf().done:GetText())
    assert.is_false(bandOf().totalCaption:IsShown())
    assert.is_false(dock():IsShown())
  end)

  -- Where a region is anchored, top-down: the y of its `point`, and what it is anchored to.
  local function yOf(frame, point)
    for _, p in ipairs(frame.points) do
      if p.point == point then return p.y, p.relative end
    end
  end

  -- The owner (BUY 2.0): one box, at the top -- not a row under the list.
  it("puts the item box at the top of the tab, then the band, the headings and the rows", function()
    local add, band = GC.Buy._view.add, bandOf()
    local y, anchor = yOf(add.frame, "TOPLEFT")
    assert.equal(containerOf(), anchor)
    assert.equal(0, y)
    assert.is_true(add.h > 0)
    assert.equal(-add.h, (yOf(band.frame, "TOPLEFT")))
    assert.equal(-(add.h + 2), (yOf(band.picker, "TOPLEFT")))
    assert.equal(-(add.h + 4), (yOf(band.totalCaption, "TOPRIGHT")))
    assert.equal(-(add.h + band.h), (yOf(band.header, "TOPLEFT")))
    assert.equal(-(add.h + band.h + 16 + 4), (yOf(band.scroll, "TOPLEFT")))
    assert.is_true(add.frame:IsShown())
    -- No row holds a place for it any more: every row on screen is a line of the list.
    for _, row in ipairs(shownRows()) do assert.truthy(row.lineItemID) end
  end)

  -- BUY 2.0: lists the player makes in the game. The BUY 2.0 probe (2026-10-01): a shift-click into
  -- the focused box delivers the item's link in both games, and the client resolves almost no typed
  -- names (0 of 15 in retail) -- so the box takes a link or an item id.
  describe("lists made in the game", function()
    -- A link as the client writes it: coloured by quality as |cnIQ<quality>: in both games.
    local LINEN = "|cnIQ1:|Hitem:2589::::::::|h[Linen Cloth]|h|r"
    local WOOL = "|cnIQ1:|Hitem:2592::::::::|h[Wool Cloth]|h|r"
    local SILK = "|cnIQ1:|Hitem:4306::::::::|h[Silk Cloth]|h|r"
    local inserted

    before_each(function()
      helper.loadModule("Core/AppRuns.lua", GC)
      GC.db.runs, GC.db.runsArchived = {}, {}
      _G.C_Item.GetItemInfoInstant = function(id) return ({ [2589] = 2589, [2592] = 2592 })[id] end
      NAMES[2589], NAMES[2592] = "Linen Cloth", "Wool Cloth"
      inserted = nil
      _G.ChatFrameUtil = { InsertLink = function() end }
      _G.hooksecurefunc = function(target, name, fn)
        if target == _G.ChatFrameUtil and name == "InsertLink" then inserted = fn end
      end
      GC.Buy._WatchLinks()
      GC.db.settings.sniper.buyRun = nil
      GC.Buy.SelectRun(nil)
      GC.Buy.Show()
    end)

    after_each(function()
      _G.ChatFrameUtil, _G.hooksecurefunc, _G.MenuUtil = nil, nil, nil
      NAMES[2589], NAMES[2592] = nil, nil
    end)

    local function enter(text)
      local box = GC.Buy._view.add.box
      box:SetText(text)
      box.scripts.OnEnterPressed(box)
    end

    local function pickerMenu()
      local entries = {}
      _G.MenuUtil = { CreateContextMenu = function(_, generator)
        generator(nil, {
          CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
          CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
          CreateDivider = function() end,
        })
      end }
      bandOf().picker.scripts.OnClick(bandOf().picker)
      _G.MenuUtil = nil
      return function(text)
        for _, e in ipairs(entries) do if e.text == text then return e end end
      end
    end

    it("makes List 1 from the first item added, with its count", function()
      enter("20 " .. LINEN)
      local code = GC.Buy.CurrentRun():Code()
      assert.equal("game", GC.db.runs[code].origin)
      assert.equal(20, GC.Buy.CurrentRun():Lines()[1].need)
      assert.equal("Added 20× Linen Cloth to a new list, List 1.", GC.Buy._view.add.note:GetText())
      assert.equal("", GC.Buy._view.add.box:GetText())
      assert.equal("List 1 ▼", bandOf().picker.label)
    end)

    it("adds an item by its id, with an x count", function()
      enter("2592 x3")
      assert.equal(2592, GC.Buy.CurrentRun():Lines()[1].itemID)
      assert.equal(3, GC.Buy.CurrentRun():Lines()[1].need)
    end)

    it("refuses two bare numbers instead of guessing which is the item", function()
      enter("2592 3")
      assert.equal("Could not find that item. Shift-click it, or type its item id.", GC.Buy._view.add.note:GetText())
      assert.is_nil(next(GC.db.runs))
    end)

    -- A typed name is never claimed to be found: the client places almost none (the BUY 2.0 probe).
    it("says what to do when nothing it knows goes by a typed name, and makes no list", function()
      enter("Linen Cloth")
      assert.equal("Open the auction house to search what's on sale.", GC.Buy._view.add.note:GetText())
      assert.is_nil(next(GC.db.runs))
      enter("999999")
      assert.equal("Could not find that item. Shift-click it, or type its item id.", GC.Buy._view.add.note:GetText())
      assert.is_nil(next(GC.db.runs))
    end)

    -- With the auction house open it is where everything is searched (UI/BuySearch.lua, which says
    -- how that search went): the box does not point the player at it.
    it("does not send the player to the auction house while it is open", function()
      GC.Sniper = { IsAHOpen = function() return true end }
      enter("Linen Cloth")
      GC.Sniper = nil
      assert.equal("", GC.Buy._view.add.note:GetText())
    end)

    it("takes a shift-click while it has the focus, and none before", function()
      local box = GC.Buy._view.add.box
      box:SetText("5 ")
      inserted(LINEN)
      assert.equal("5 ", box:GetText())
      box:SetFocus()
      inserted(LINEN)
      assert.equal("5 " .. LINEN, box:GetText())
    end)

    -- The owner: three shift-clicks kept only the last.
    it("collects three shift-clicks, after the client moved the focus too, and Enter adds all three", function()
      _G.C_Item.GetItemInfoInstant = function(id) return ({ [2589] = 2589, [2592] = 2592, [4306] = 4306 })[id] end
      NAMES[4306] = "Silk Cloth"
      local add = GC.Buy._view.add
      add.box:SetFocus()
      add.box.scripts.OnEditFocusGained(add.box)
      inserted(LINEN)
      add.box:ClearFocus() -- a click on a bag
      inserted(WOOL)
      inserted(SILK)
      assert.equal(LINEN .. ", " .. WOOL .. ", " .. SILK, add.box:GetText())
      assert.equal("Items to add: 3 (Linen Cloth, Wool Cloth, Silk Cloth)", add.collected:GetText())
      assert.equal("Add", add.button.label)
      add.box.scripts.OnEnterPressed(add.box)
      NAMES[4306] = nil
      local ids = {}
      for i, line in ipairs(GC.Buy.CurrentRun():Lines()) do ids[i] = line.itemID end
      assert.same({ 2589, 2592, 4306 }, ids)
      assert.equal("Added 3 items to a new list, List 1.", add.note:GetText())
      assert.equal("", add.box:GetText())
      -- Enter ended the collecting: the next shift-click is somebody else's.
      inserted(LINEN)
      assert.equal("", add.box:GetText())
    end)

    it("adds what it can read and names what it cannot", function()
      local add = GC.Buy._view.add
      add.box:SetText("2589 x2, 2592 3; 999999")
      add.box.scripts.OnTextChanged(add.box, true)
      assert.equal("Items to add: 1 (Linen Cloth ×2)\nCould not read: 2592 3, 999999.", add.collected:GetText())
      add.box.scripts.OnEnterPressed(add.box)
      assert.equal("Added 2× Linen Cloth to a new list, List 1. Could not read: 2592 3, 999999.", add.note:GetText())
      assert.equal(1, #GC.Buy.CurrentRun():Lines())
    end)

    it("never takes a link bound for an open chat box, or for another box with the keyboard", function()
      local add = GC.Buy._view.add
      add.box:SetText("")
      add.box:SetFocus()
      add.box.scripts.OnEditFocusGained(add.box)
      _G.ChatFrameUtil.GetActiveWindow = function() return {} end
      inserted(LINEN)
      assert.equal("", add.box:GetText())
      _G.ChatFrameUtil.GetActiveWindow = function() return nil end
      _G.GetCurrentKeyBoardFocus = function() return {} end
      inserted(LINEN)
      assert.equal("", add.box:GetText())
      _G.GetCurrentKeyBoardFocus = function() return add.box end
      inserted(LINEN)
      _G.GetCurrentKeyBoardFocus = nil
      assert.equal(LINEN, add.box:GetText())
    end)

    it("stops collecting on Escape, on Enter in an empty box, and when the tab goes away", function()
      local add = GC.Buy._view.add
      add.box:SetFocus()
      add.box.scripts.OnEditFocusGained(add.box)
      add.box:SetText("")
      add.box.scripts.OnEnterPressed(add.box)
      assert.is_false(add.box:HasFocus())
      inserted(LINEN)
      assert.equal("", add.box:GetText())
      add.box.scripts.OnEditFocusGained(add.box)
      add.box:SetText("2589")
      add.box.scripts.OnEscapePressed(add.box)
      assert.equal("", add.box:GetText())
      inserted(LINEN)
      assert.equal("", add.box:GetText())
      add.box.scripts.OnEditFocusGained(add.box)
      add.frame.scripts.OnHide(add.frame)
      inserted(LINEN)
      assert.equal("", add.box:GetText())
    end)

    it("adds to the player's own list on screen", function()
      enter(LINEN)
      local code = GC.Buy.CurrentRun():Code()
      enter("2592 x3")
      assert.equal(code, GC.Buy.CurrentRun():Code())
      assert.equal(2, #GC.Buy.CurrentRun():Lines())
      assert.equal("Added 3× Wool Cloth to List 1.", GC.Buy._view.add.note:GetText())
    end)

    -- A goldcap.gg list is edited on goldcap.gg: the box over one makes a list in the game.
    it("shows the box over a goldcap.gg list too, whose first item makes a new list", function()
      GC.db.runs["run-1"] = run()
      GC.Buy.SelectRun("run-1")
      GC.Buy.RefreshIfShown()
      assert.is_true(GC.Buy._view.add.frame:IsShown())
      assert.is_true(bandOf().picker:IsShown())
      enter(LINEN)
      local code = GC.Buy.CurrentRun():Code()
      assert.is_true(code ~= "run-1")
      assert.equal("game", GC.db.runs[code].origin)
      assert.equal(4, #GC.db.runs["run-1"].lines)
      assert.equal("Added 1× Linen Cloth to a new list, List 1.", GC.Buy._view.add.note:GetText())
    end)

    -- Typed names: only what the client and GoldCap already know, compared in the client's language.
    it("offers the items it knows by a typed Russian name, and adds the one clicked with its count", function()
      GC.db.itemNames = { [2589] = { n = "Плотные льняные бинты" }, [2592] = { n = "Шерстяная ткань" } }
      NAMES[2589] = "Плотные льняные бинты"
      local add = GC.Buy._view.add
      add.box.scripts.OnEditFocusGained(add.box)
      add.box:SetText("20 ЛЬНЯН")
      add.box.scripts.OnTextChanged(add.box, true)
      assert.equal("Search", add.button.label)
      assert.is_true(add.matches[1]:IsShown())
      assert.equal(2589, add.matches[1].itemID)
      assert.equal("Плотные льняные бинты", add.matches[1].text:GetText())
      assert.is_nil(add.matches[2])
      add.matches[1].scripts.OnClick(add.matches[1])
      local line = GC.Buy.CurrentRun():Lines()[1]
      assert.equal(2589, line.itemID)
      assert.equal(20, line.need)
      assert.equal("Added 20× Плотные льняные бинты to a new list, List 1.", add.note:GetText())
      assert.is_false(add.matches[1]:IsShown())
    end)

    -- Where the names come from: the bank as far as the client has it (its tabs by the client's own
    -- Enum.BagIndex names, which differ between retail and WoW: Forever), the ledger, and what
    -- GoldCap recorded buying.
    it("offers what the bank, the ledger and GoldCap's own purchases know by name", function()
      local old = _G.Enum
      _G.Enum = { BagIndex = { Backpack = 0, CharacterBankTab_1 = 6, AccountBankTab_1 = 12, Keyring = -1 } }
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return (bag == 6 or bag == 12) and 1 or 0 end,
        GetContainerItemInfo = function(bag) return ({ [6] = { itemID = 4306 }, [12] = { itemID = 4338 } })[bag] end,
      }
      NAMES[4306], NAMES[4338] = "Silk Cloth", "Mageweave Cloth"
      GC.db.ledger = { { itemID = 14047, itemName = "Runecloth" } }
      GC.db.acquisitions = { { itemID = 21877, itemName = "Netherweave Cloth" } }
      local add = GC.Buy._view.add
      add.box:SetText("cloth")
      add.box.scripts.OnTextChanged(add.box, true)
      _G.Enum = old
      NAMES[4306], NAMES[4338] = nil, nil
      local ids = {}
      for i, row in ipairs(add.matches) do if row:IsShown() then ids[i] = row.itemID end end
      table.sort(ids)
      assert.same({ 4306, 4338, 14047, 21877 }, ids)
      add.box:SetText("rune")
      add.box.scripts.OnTextChanged(add.box, true)
      assert.equal(14047, add.matches[1].itemID)
    end)

    -- A purchase recorded by an English client keeps its English name; a Russian client still finds
    -- it under the name it gives the item itself.
    it("finds an item recorded under another language by the client's own name", function()
      GC.db.ledger = { { itemID = 2589, itemName = "Linen Cloth" } }
      NAMES[2589] = "Льняная ткань"
      local add = GC.Buy._view.add
      add.box:SetText("льнян")
      add.box.scripts.OnTextChanged(add.box, true)
      NAMES[2589] = nil
      assert.equal(2589, add.matches[1].itemID)
    end)

    it("walks the matches with the arrow keys, and Enter adds the one picked", function()
      GC.db.itemNames = { [2589] = { n = "Linen Cloth" }, [4306] = { n = "Linen Thread" } }
      local add = GC.Buy._view.add
      add.box:SetText("linen")
      add.box.scripts.OnTextChanged(add.box, true)
      assert.equal(2589, add.matches[1].itemID)
      assert.equal(4306, add.matches[2].itemID)
      add.box.scripts.OnArrowPressed(add.box, "DOWN")
      add.box.scripts.OnArrowPressed(add.box, "DOWN")
      assert.is_true(add.matches[2].picked:IsShown())
      assert.is_false(add.matches[1].picked:IsShown())
      assert.equal("Add", add.button.label)
      add.box.scripts.OnArrowPressed(add.box, "DOWN") -- round, to the first
      assert.is_true(add.matches[1].picked:IsShown())
      add.box.scripts.OnArrowPressed(add.box, "UP")
      assert.is_true(add.matches[2].picked:IsShown())
      add.box.scripts.OnEnterPressed(add.box)
      assert.equal(4306, GC.Buy.CurrentRun():Lines()[1].itemID)
    end)

    it("moves the list down as the box grows, so nothing sits under it", function()
      GC.db.itemNames = { [2589] = { n = "Linen Cloth" } }
      GC.db.runs["run-1"] = run()
      GC.Buy.SelectRun("run-1")
      GC.Buy.RefreshIfShown()
      local add, band = GC.Buy._view.add, bandOf()
      local before = add.h
      add.box:SetText("linen")
      add.box.scripts.OnTextChanged(add.box, true)
      assert.is_true(add.h > before)
      assert.equal(-add.h, (yOf(band.frame, "TOPLEFT")))
      assert.equal(-(add.h + band.h), (yOf(band.header, "TOPLEFT")))
    end)

    it("keeps the last searches and items as chips: an item's adds it again, a search's runs again", function()
      GC.db.itemNames = { [2592] = { n = "Wool Cloth" } }
      local add = GC.Buy._view.add
      enter("2589 x20")
      enter("wool")
      assert.same({ { s = "wool" }, { i = 2589, q = 20, n = "Linen Cloth" } }, GC.db.buyRecents)
      assert.equal("“wool”", add.chips[1].label)
      assert.equal("Linen Cloth ×20", add.chips[2].label)
      assert.is_true(add.recentCaption:IsShown())
      assert.is_true(add.clear:IsShown())
      -- The item's chip adds it again, to the list the box adds to.
      add.chips[2].scripts.OnClick(add.chips[2])
      assert.equal(40, GC.Buy.CurrentRun():Lines()[1].need)
      assert.equal("Linen Cloth ×20", add.chips[1].label)
      -- The search's chip runs it again.
      add.chips[2].scripts.OnClick(add.chips[2])
      assert.equal("wool", add.box:GetText())
      assert.equal(2592, add.matches[1].itemID)
      assert.equal("“wool”", add.chips[1].label)
      add.clear.scripts.OnClick(add.clear)
      assert.same({}, GC.db.buyRecents)
      assert.is_false(add.recentCaption:IsShown())
      assert.is_false(add.chips[1]:IsShown())
    end)

    it("takes a line off the player's list from its menu, and keeps the list", function()
      enter(LINEN)
      local code = GC.Buy.CurrentRun():Code()
      local titles
      _G.MenuUtil = { CreateContextMenu = function(_, build)
        titles = {}
        local root = {
          CreateTitle = function(_, t) titles[#titles + 1] = t end,
          CreateButton = function(_, t, fn) titles[#titles + 1] = t; if t == "Remove from the list" then titles.remove = fn end end,
          CreateDivider = function() end,
        }
        build(nil, root)
      end }
      local row = rowWithText("Linen Cloth")
      row.scripts.OnMouseUp(row, "RightButton")
      assert.is_truthy(titles.remove)
      titles.remove()
      assert.equal(0, #GC.db.runs[code].lines)
      assert.equal(code, GC.Buy.CurrentRun():Code())
      assert.is_true(GC.Buy._view.add.frame:IsShown())
    end)

    -- "+ New": the next free number, picked, with the name box over it.
    it("makes a new list from the picker's menu and asks for its name", function()
      enter(LINEN)
      local asked
      GC.BuyCapEditor = { Open = function(anchor, opts) asked = { anchor = anchor, opts = opts } end }
      pickerMenu()("New list").fn()
      assert.equal("List 2 ▼", bandOf().picker.label)
      assert.equal(bandOf().picker, asked.anchor)
      assert.is_true(asked.opts.over)
      assert.equal("List 2", asked.opts.text)
      assert.equal("Name this list", asked.opts.title)
      -- Enter keeps what was typed...
      asked.opts.onCommit("Herbs")
      assert.equal("Herbs ▼", bandOf().picker.label)
      -- ...and the default typed back is the default again.
      pickerMenu()("Rename…").fn()
      asked.opts.onCommit("List 2")
      assert.equal("List 2 ▼", bandOf().picker.label)
      assert.is_nil(GC.AppRuns.Get(GC.Buy.CurrentRun():Code()).name)
    end)

    it("pins a favourite to the top of the picker with a star, and moves lists", function()
      local one = GC.AppRuns.NewList()
      one.createdAt = 10
      local two = GC.AppRuns.NewList()
      two.createdAt = 20
      GC.Buy.SelectRun(one.code)
      GC.Buy.RefreshIfShown()
      local find = pickerMenu()
      assert.is_nil(find("Move down"))
      find("Move up").fn()
      find = pickerMenu()
      assert.truthy(find("• List 1, 0 lines, in game"))
      assert.truthy(find("Move down"))
      find("Add to favourites").fn()
      find = pickerMenu()
      assert.truthy(find("• |A:auctionhouse-icon-favorite:12:12|a List 1, 0 lines, in game"))
      assert.truthy(find("Remove from favourites"))
      assert.is_nil(find("Move down"))
      assert.equal(one.code, GC.AppRuns.List()[1].code)
    end)

    it("exports the list on screen for Auctionator and for TSM, in the copy box", function()
      enter("20 " .. LINEN)
      enter("2592 x5")
      local shown
      GC.UI = { ShowCopyText = function(text, opts) shown = { text = text, opts = opts } end }
      local exportMenu = {}
      _G.MenuUtil = { CreateContextMenu = function(_, generator)
        generator(nil, {
          CreateTitle = function() end, CreateDivider = function() end,
          CreateButton = function(_, text)
            if text == "Export" then
              return { CreateButton = function(_, t, fn) exportMenu[t] = fn end }
            end
          end,
        })
      end }
      bandOf().picker.scripts.OnClick(bandOf().picker)
      _G.MenuUtil = nil
      exportMenu["Copy for Auctionator"]()
      assert.equal('List 1^"Linen Cloth";;;;;;;;;;;#;;20^"Wool Cloth";;;;;;;;;;;#;;5', shown.text)
      assert.equal("Copy for Auctionator", shown.opts.title)
      exportMenu["Copy as a TSM item list"]()
      assert.equal("i:2589,i:2592", shown.text)
      -- An item the client has not loaded is asked for and left out, never written blank.
      local asked = {}
      NAMES[2592] = nil
      _G.C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
      exportMenu["Copy for Auctionator"]()
      assert.equal('List 1^"Linen Cloth";;;;;;;;;;;#;;20', shown.text)
      assert.same({ 2592 }, asked)
      assert.is_truthy(shown.opts.hint:find("left out: 1.", 1, true))
    end)
  end)

  it("recounts what is in the bags when the bags change", function()
    assert.equal("10", tostring(lineOfRow(rowWithText("Alpha Herb")).buy))
    stubBags({ [1] = { itemID = 102, qty = 5 }, [2] = { itemID = 101, qty = 4 } })
    GC.Buy.OnBagsChanged()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("4", tostring(lineOfRow(alpha).have))
    assert.equal("6", tostring(lineOfRow(alpha).buy))
    pick(alpha)
    assert.equal("BUY 6", dock().buy.label)
  end)

  -- GC.BagStock.Scan drops a soulbound stack because the auction house will not POST it --
  -- a Sell rule this tab has to override. A bound reagent in the bags is still a reagent the
  -- player does not have to buy, and forwarding the flag sent them shopping for it.
  it("counts a soulbound stack toward HAVE", function()
    stubBags({ [1] = { itemID = 102, qty = 5 }, [2] = { itemID = 101, qty = 7, bound = true } })
    GC.Buy.OnBagsChanged()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("7", tostring(lineOfRow(alpha).have))
    assert.equal("3", tostring(lineOfRow(alpha).buy))
  end)

  -- BAG_UPDATE_DELAYED fires all session long; a six-bag walk behind the Deals tab buys
  -- nothing. Show() rescans, so nothing goes stale by skipping it while hidden.
  it("does not walk the bags while the tab is hidden, and catches up on the next Show", function()
    GC.Buy.Hide()
    stubBags({ [1] = { itemID = 102, qty = 5 }, [2] = { itemID = 101, qty = 4 } })
    bagWalks = 0
    GC.Buy.OnBagsChanged()
    assert.equal(0, bagWalks)

    GC.Buy.Show()
    assert.equal(1, bagWalks)
    assert.equal("4", tostring(lineOfRow(rowWithText("Alpha Herb")).have))
  end)

  -- A run keeps its code across a companion sync while its lines change, so the code alone
  -- does not prove the built object is current -- updatedAt does.
  it("rebuilds the run when the companion resyncs the same code with newer lines", function()
    GC.AppRuns._set({ run({ updatedAt = 900, lines = { { i = 101, q = 2 } } }) })
    GC.Buy.Show()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("2", tostring(lineOfRow(alpha).need))
    assert.is_nil(rowWithText("Charlie Dust"))
  end)

  -- Nothing has looked at the book for a fresh run: PRICE EACH is the market value, dimmed, and
  -- COST an estimate marked as one.
  it("prices a line nothing has been seen for at its market value, dimmed, with an estimated cost", function()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("1000c", alpha.cells.price:GetText())
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      alpha.cells.price.colorValue)
    assert.equal("~1g", alpha.cells.cost:GetText())
    -- ...and the cheapest unit seen, in full colour, once there is one.
    GC.Buy.CurrentRun():SetFloor(101, 900, 2000)
    GC.Buy.RefreshIfShown()
    alpha = rowWithText("Alpha Herb")
    assert.equal("900c", alpha.cells.price:GetText())
    assert.same({ 1, 1, 1, 1 }, alpha.cells.price.colorValue)
    assert.equal("~9000c", alpha.cells.cost:GetText())
  end)

  -- A line with no price at all states none, rather than inventing a zero.
  it("leaves a line nobody can price on em dashes", function()
    GC.AppRuns._set({ run({ lines = { { i = 105, q = 2 } } }) })
    GC.Buy.SelectRun("run-1"); GC.Buy.RefreshIfShown()
    local row = rowWithText("#105")
    assert.equal("-", row.cells.price:GetText())
    assert.equal("-", row.cells.cost:GetText())
  end)

  -- WoW: Forever prices an item from the player's own last scan when nothing else knows it. One
  -- look at one auction house is not "usual" (GC.DealMath.IsOwnScan, the rule Measure applies
  -- everywhere else): BUY must neither print it as USUAL nor cap a purchase by it. The community
  -- price (the Companion's, source "scan" kind "crowd") is a market and is used.
  describe("reference price by source", function()
    local function lineOf(itemID)
      for _, line in ipairs(GC.Buy.CurrentRun():Lines()) do
        if line.itemID == itemID then return line end
      end
    end
    local function withValue(value, community)
      GC.Data.GetItemValue = function(itemID) if itemID == 101 then return value end end
      GC.Data.ForeverReference = function() return community or { source = "own" } end
      GC.Buy.RefreshIfShown()
    end

    it("does not show or cap by the player's own scan", function()
      withValue({ mv = 500, source = "scan", ts = 1 })
      assert.is_nil(lineOf(101).usual)
      assert.is_nil(lineOf(101).cap)
      assert.equal("-", rowWithText("Alpha Herb").cells.price:GetText())
    end)

    it("uses the community price when the player's own scan is the fresher look", function()
      withValue({ mv = 500, source = "scan", ts = 9 }, { value = 800, source = "crowd", scanners = 3 })
      assert.equal(800, lineOf(101).usual)
      assert.equal(1040, lineOf(101).cap) -- 130% of 800
      assert.equal("800c", rowWithText("Alpha Herb").cells.price:GetText())
    end)

    it("uses a community value as it is", function()
      withValue({ mv = 700, source = "scan", kind = "crowd", scanners = 2, ts = 1 })
      assert.equal(700, lineOf(101).usual)
      assert.equal(910, lineOf(101).cap)
    end)

    it("keeps a retail list's own price whatever the market value says", function()
      GC.AppRuns._set({ run({ lines = { { i = 101, q = 10, u = 777 } } }) })
      GC.Data.ForeverReference = function() return { source = "own" } end
      GC.Buy.SelectRun("run-1"); GC.Buy.RefreshIfShown()
      local line = GC.Buy.CurrentRun():Lines()[1]
      assert.equal(777, line.usual)
      assert.is_nil(line.usualRef)
    end)

    -- WoW: Forever: the crowd's look wins over the list's price only when it is the fresher one.
    it("takes a crowd price seen after the list was priced, and keeps whose it is", function()
      local crowd = { value = 800, source = "crowd", scanners = 3, at = 1500 }
      GC.AppRuns._set({ run({ pricedAt = 1000, lines = { { i = 101, q = 10, u = 777 } } }) })
      GC.Data.ForeverReference = function(itemID) if itemID == 101 then return crowd end return { source = "own" } end
      GC.Buy.SelectRun("run-1"); GC.Buy.RefreshIfShown()
      assert.equal(800, lineOf(101).usual)
      assert.same(crowd, lineOf(101).usualRef)
      GC.AppRuns._set({ run({ pricedAt = 1600, lines = { { i = 101, q = 10, u = 777 } } }) })
      GC.Buy.SelectRun("run-1"); GC.Buy.RefreshIfShown()
      assert.equal(777, lineOf(101).usual)
      assert.is_nil(lineOf(101).usualRef)
    end)

    it("leaves every other source (retail) exactly as it was", function()
      for _, source in ipairs({ "import", "region", "bundled" }) do
        withValue({ mv = 1000, source = source })
        assert.equal(1000, lineOf(101).usual)
        assert.equal(1300, lineOf(101).cap)
        assert.equal("1000c", rowWithText("Alpha Herb").cells.price:GetText())
      end
    end)
  end)

  -- The setting is GC.db.settings.sniper.buyCapPct (UI/SettingsFrame.lua's fieldRow writes
  -- there); the run's own cap has to move with it on the very next Refresh, not just at
  -- construction, since RefreshIfShown re-Refreshes the SAME run object rather than rebuilding
  -- it.
  it("changing the buy cap setting changes a line's cap on the next Refresh", function()
    local function capFor(itemID)
      for _, line in ipairs(GC.Buy.CurrentRun():Lines()) do
        if line.itemID == itemID then return line.cap end
      end
    end
    assert.equal(1300, capFor(101)) -- 1000 mv * 130% default
    GC.db.settings.sniper.buyCapPct = 200
    GC.Buy.RefreshIfShown()
    assert.equal(2000, capFor(101))
  end)

  -- UI/SettingsFrame.lua bounds the box on commit, which says nothing about what is ALREADY in
  -- SavedVariables: a hand-edited file, or one written before the bound existed, would have every
  -- purchase judged against a 9x cap -- and a non-number errored inside Refresh() on every render,
  -- which is the whole tab gone. The read site clamps to the same 100-300 the box uses.
  it("clamps a cap outside 100-300 in SavedVariables to the bound", function()
    local function capFor(itemID)
      for _, line in ipairs(GC.Buy.CurrentRun():Lines()) do
        if line.itemID == itemID then return line.cap end
      end
    end
    GC.db.settings.sniper.buyCapPct = 900
    GC.Buy.RefreshIfShown()
    assert.equal(3000, capFor(101)) -- 300% of the 1000 usual, not 900%

    GC.db.settings.sniper.buyCapPct = 10
    GC.Buy.RefreshIfShown()
    assert.equal(1000, capFor(101))

    GC.db.settings.sniper.buyCapPct = "nonsense"
    assert.has_no.errors(function() GC.Buy.RefreshIfShown() end)
    assert.equal(1300, capFor(101)) -- back to the default rather than down with the tab
  end)

  -- Spec rule 2: a vendor line is priced at what the VENDOR charges, in grey -- never at the
  -- auction house's market value, which is a price for a purchase this line is not.
  it("prices a vendor line at the vendor's own price", function()
    GC.AppRuns._set({ run({ code = "run-v", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 9, v = true, vu = 25 } } }) })
    GC.db.settings.sniper.buyRun = "run-v"
    GC.Buy.Show()

    local vendor = rowWithText("Bravo Ore")
    assert.truthy(vendor)
    assert.equal("Bravo Ore ×4", vendor.reagent:GetText())  -- 5 already in bags, 4 left to buy
    assert.equal("at a vendor · 25c each", vendor.status:GetText())
    assert.is_false(vendor.cells.price:IsShown())
    assert.is_false(vendor.cells.cost:IsShown())
  end)

  -- Without a vendor price there is no honest number: the market value beside it is not one.
  it("leaves a vendor line with no vendor price on em dashes", function()
    GC.AppRuns._set({ run({ code = "run-v", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 9, v = true } } }) })
    GC.db.settings.sniper.buyRun = "run-v"
    GC.Buy.Show()

    local vendor = rowWithText("Bravo Ore")
    -- 102 has a market value; it is not the point.
    assert.equal("at a vendor", vendor.status:GetText())
    assert.is_nil(vendor.status:GetText():find("c", 1, true))

    -- ...while the line the player is actually here to buy still prices.
    local alpha = rowWithText("Alpha Herb")
    assert.equal("1000c", alpha.cells.price:GetText())
    assert.equal("~1g", alpha.cells.cost:GetText())
  end)

  -- Finding 4: a vendor stop the bags already cover is `buy == 0` at a known price -- `buy * unit`
  -- is honestly zero, but "0c" reads as a real quote rather than as the nothing-left-to-do an
  -- em dash says everywhere else on this tab.
  it("says a vendor stop the bags already cover is done, not 0c", function()
    GC.AppRuns._set({ run({ code = "run-vd", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 5, v = true, vu = 25 } } }) })
    GC.db.settings.sniper.buyRun = "run-vd"
    GC.Buy.Show()

    local vendor = rowWithText("Bravo Ore")
    assert.equal("bought", vendor.status:GetText())
    assert.is_false(vendor.cells.cost:IsShown())
  end)

  -- Spec rule 2: the run menu offers the vendor stops as a block of plain text, because the
  -- player has to read them off the screen while standing at a vendor.
  local function copyVendorList()
    local copied, offered
    GC.UI = { ShowVendorList = function(text) copied = text end }
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      generator(nil, {
        CreateTitle = function() end, CreateDivider = function() end,
        CreateButton = function(_, text, fn)
          if text == "Copy vendor list" then offered = true; fn() end
          return {}
        end,
      })
    end }
    bandOf().picker.scripts.OnClick(bandOf().picker)
    _G.MenuUtil = nil
    return copied, offered
  end

  it("copies the run's vendor stops out as a list with a total", function()
    GC.AppRuns._set({ run({ code = "run-v", updatedAt = 900, lines = {
      { i = 101, q = 10 }, { i = 104, q = 5, v = true, vu = 25 },
      { i = 103, q = 2, v = true, vu = 10000 } } }) })
    GC.db.settings.sniper.buyRun = "run-v"
    GC.Buy.Show()

    local copied, offered = copyVendorList()
    assert.is_true(offered)
    -- Plain money, never GetCoinTextureString: the icon escapes copy out of the box as
    -- |TInterface\...|t, which is not something a player can read at a vendor.
    assert.equal("5× Delta Vial · 25c each · 1s25c\n"
      .. "2× Charlie Dust · 1g each · 2g\n"
      .. "Total: 2g1s25c", copied)
  end)

  it("names a vendor line with no price without inventing one", function()
    GC.AppRuns._set({ run({ code = "run-v", updatedAt = 900, lines = {
      { i = 101, q = 10 }, { i = 104, q = 5, v = true } } }) })
    GC.db.settings.sniper.buyRun = "run-v"
    GC.Buy.Show()
    assert.equal("5× Delta Vial\nTotal: 0c", (copyVendorList()))
  end)

  it("offers no vendor list for a run with no vendor stop", function()
    GC.AppRuns._set({ run({ code = "run-n", updatedAt = 900, lines = { { i = 101, q = 10 } } }) })
    GC.db.settings.sniper.buyRun = "run-n"
    GC.Buy.Show()
    local _, offered = copyVendorList()
    assert.is_nil(offered)
  end)

  it("labels the column header row ITEM/PRICE EACH/COST", function()
    local header = bandOf().header
    assert.truthy(header and header.cells)
    assert.equal("ITEM", header.reagentCell.label:GetText())
    assert.equal("PRICE EACH", header.cells.price.label:GetText())
    assert.equal("COST", header.cells.cost.label:GetText())
    local keys = {}
    for key in pairs(header.cells) do keys[#keys + 1] = key end
    table.sort(keys)
    assert.same({ "cost", "price" }, keys)
  end)

  -- The owner's rule: nothing a player reads is cut short, in any language. A column is as wide as
  -- its heading and every cell it shows, as the client measures them; the one word a row says in
  -- place of the prices widens them until it fits.
  it("widens the price columns to their heading and to the longest word a row says", function()
    textWidth = function(text) return #text * 10 end
    GC.Buy.CurrentRun():SetFloor(101, 5000, 2000) -- Alpha Herb: "over your cap · 5000c"
    GC.Buy.RefreshIfShown()
    local header = bandOf().header
    assert.is_true(header.cells.price.width >= #"PRICE EACH" * 10)
    local row = rowWithText("Alpha Herb")
    assert.is_true(row.status.width >= #row.status:GetText() * 10)
    -- ...and the item column gets what is left, not what the prices already took.
    assert.equal(600 - row.status.width - 8, row.reagent.width)
  end)

  it("gives a name too long for its column a second line and a taller row", function()
    stringHeight = function(fs) return (fs.textValue or ""):find("Alpha", 1, true) and 26 or 12 end
    GC.Buy.RefreshIfShown()
    assert.equal(36, rowWithText("Alpha Herb").height)
    assert.equal(28, rowWithText("Charlie Dust").height)
  end)

  -- Spec rule 3: the hour the site measured is UTC; the player reads realm time. The offset is
  -- the difference between the client's own two clocks -- realm time and the same instant in UTC.
  it("says in the row's tooltip when the item is usually cheapest, in realm time", function()
    -- Realm clock says 14:00 while UTC says 12:00: a realm two hours ahead of UTC.
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 14 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 12 } end

    GC.AppRuns._set({ run({ code = "run-c", updatedAt = 900,
      lines = { { i = 101, q = 10, ch = 3, cp = -18 }, { i = 102, q = 5 } } }) })
    GC.db.settings.sniper.buyRun = "run-c"
    GC.Buy.Show()

    local lines = tooltipOn(rowWithText("Alpha Herb"))
    assert.truthy(lineWith(lines, "usually cheapest around 05:00, -18%"))   -- 3 UTC + 2

    -- A line the site could not measure says nothing at all.
    assert.is_nil(lineWith(tooltipOn(rowWithText("Bravo Ore")), "usually cheapest"))

    _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil
  end)

  -- Realm behind UTC and an hour that wraps past midnight: the two `% 24`s are what keep
  -- 23:00 UTC on a realm at UTC-2 from reading as "-1:00" or "25:00".
  it("wraps the cheap hour through midnight for a realm behind UTC", function()
    -- Realm clock 21:00 while UTC says 23:00: offset (21 - 23) % 24 = 22, i.e. two hours behind.
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 21 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 23 } end

    GC.AppRuns._set({ run({ code = "run-w", updatedAt = 900,
      lines = { { i = 101, q = 10, ch = 1, cp = -9 }, { i = 102, q = 5 } } }) })
    GC.db.settings.sniper.buyRun = "run-w"
    GC.Buy.Show()
    local lines = tooltipOn(rowWithText("Alpha Herb"))
    assert.truthy(lineWith(lines, "usually cheapest around 23:00, -9%"))   -- (1 + 22) % 24

    _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil
  end)

  -- An hour in the wrong timezone is worse than no hour, so a client that cannot answer gets
  -- nothing rather than the UTC hour dressed up as a local one.
  it("says nothing about the cheap hour when the client cannot give the offset", function()
    GC.AppRuns._set({ run({ code = "run-c", updatedAt = 900,
      lines = { { i = 101, q = 10, ch = 3, cp = -18 } } }) })
    GC.db.settings.sniper.buyRun = "run-c"
    GC.Buy.Show()
    assert.is_nil(lineWith(tooltipOn(rowWithText("Alpha Herb")), "usually cheapest"))
  end)

  -- Finding 3: a vendor sells at one fixed price, so "usually cheapest around HH:00" is noise --
  -- there is no auction house history for this line to be a footnote on.
  it("says nothing about the cheap hour on a vendor line", function()
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 14 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 12 } end

    GC.AppRuns._set({ run({ code = "run-vc", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 9, v = true, vu = 25, ch = 3, cp = -18 } } }) })
    GC.db.settings.sniper.buyRun = "run-vc"
    GC.Buy.Show()

    assert.is_nil(lineWith(tooltipOn(rowWithText("Bravo Ore")), "usually cheapest"))

    _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil
  end)

  -- Spec rule 1: a line the site sent a recipe for, split, becomes a craft line with its
  -- reagents under it. The flag is written straight into the store here -- the menu that writes
  -- it for the player is spec/buy_frame_spec's own "right-click" block.
  local function craftRun()
    return { code = "run-c", name = "Craft run", updatedAt = 900, origin = "app", lines = {
      { i = 101, q = 20, u = 5800, cr = { r = 900, n = 5, c = 2300, i = {
        { i = 102, q = 5, n = "Bravo Ore", u = 300 },
        { i = 103, q = 5, n = "Charlie Dust", u = 160 },
      } } },
    } }
  end

  local function showCraftRun(split)
    GC.AppRuns._set({ craftRun() })
    GC.db.runSplits = split and { ["run-c"] = { [101] = true } } or {}
    GC.db.settings.sniper.buyRun = "run-c"
    GC.Buy.Show()
  end

  it("leaves a line the player has not split as an ordinary line", function()
    showCraftRun(false)
    pick(rowWithText("Alpha Herb"))
    assert.equal("BUY 20", dock().buy.label)
    assert.is_nil(rowWithText("Bravo Ore"))
  end)

  it("draws a split line as a craft line with its reagents indented under it", function()
    showCraftRun(true)
    local parent = rowWithText("craft 4×")
    assert.truthy(parent)
    assert.equal("Alpha Herb ×20 → craft 4× (5 per craft)", parent.reagent:GetText())
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      parent.reagent.colorValue)
    -- Nothing here is bought at the auction house: one word says what one crafted unit costs in
    -- reagents at the recipe's prices -- two prices, never a promise of savings -- green because
    -- that is under the 5800 the auction house asks.
    assert.equal("craft it · 460c each", parent.status:GetText())
    assert.same({ 0, 1, 0, 1 }, parent.status.colorValue)
    assert.is_false(parent.cells.price:IsShown())

    local ore = rowWithText("Bravo Ore")
    assert.equal("• Bravo Ore ×15", ore.reagent:GetText())
    assert.equal("20", tostring(lineOfRow(ore).need))
    assert.equal("15", tostring(lineOfRow(ore).buy))
    pick(ore)
    assert.equal("BUY 15", dock().buy.label)
    assert.equal("• Charlie Dust ×20", rowWithText("Charlie Dust").reagent:GetText())
  end)

  -- Core/BuyRun.lua's Totals counts a vendor line with no vendor price as nothing, because a
  -- floor or a market value is a number from the wrong market. The row agrees: a vendor reagent
  -- nobody priced says where it is bought, and names no auction house price.
  it("prices a vendor reagent with no vendor price nowhere", function()
    GC.AppRuns._set({ { code = "run-vc", name = "Craft run", updatedAt = 900, origin = "app",
      lines = { { i = 101, q = 20, u = 5800, cr = { r = 900, n = 5, c = 2300, i = {
        { i = 102, q = 5, n = "Bravo Ore", u = 300 },
        { i = 103, q = 5, n = "Charlie Dust", v = true },
      } } } } } })
    GC.db.runSplits = { ["run-vc"] = { [101] = true } }
    GC.db.settings.sniper.buyRun = "run-vc"
    GC.Buy.Show()
    -- Nothing for the fixings, whose price nobody knows -- not the 3000 the auction house happens
    -- to ask for them.
    assert.equal("at a vendor", rowWithText("Charlie Dust").status:GetText())
    assert.is_false(rowWithText("Charlie Dust").cells.cost:IsShown())
  end)

  -- The run's own lines: the reagents a split put under a craft line are part of it.
  it("counts a split run by its own lines", function()
    showCraftRun(true)
    assert.equal("0 of 1 done", bandOf().done:GetText())
  end)

  -- A run whose only open line is a craft is not a run with nothing left to do.
  it("does not call a run with a craft still to make done", function()
    GC.AppRuns._set({ { code = "run-cd", name = "Craft run", updatedAt = 900, origin = "app",
      lines = { { i = 101, q = 20, u = 5800, cr = { r = 900, n = 5, c = 2300, i = {
        { i = 102, q = 1, n = "Bravo Ore", u = 300 } } } } } } })
    GC.db.runSplits = { ["run-cd"] = { [101] = true } }
    GC.db.settings.sniper.buyRun = "run-cd"
    GC.Buy.Show()
    assert.equal("0 of 1 done", bandOf().done:GetText())
  end)

  it("never offers a craft line to a click or to the Enter key", function()
    showCraftRun(true)
    local parent = rowWithText("craft 4×")
    -- The dock never lands on a craft line by itself: its default is the first line to buy.
    assert.are_not.equal(101, GC.Buy._focus)
    -- Picked by hand, the dock explains the line and offers nothing to press; no quote is asked
    -- and no attempt is opened. This is the assertion that goes red the moment a craft line is
    -- allowed back into `buyable` -- the one clause standing between a craft row and the BUY
    -- button, the Enter key, the focus advance and the quote.
    pick(parent)
    assert.equal(101, dock().lineItemID)
    assert.is_false(dock().buy:IsShown())
    assert.is_nil(GC.Buy._attempt)
    local container = containerOf()
    container.IsMouseOver = function() return true end
    container.SetPropagateKeyboardInput = function(self, v) self.propagate = v end
    container.scripts.OnKeyDown(container, "ENTER")
    assert.is_true(container.propagate)
    assert.is_nil(GC.Buy._attempt)
  end)

  local function texts(lines)
    local out = {}
    for _, entry in ipairs(lines) do out[#out + 1] = entry.text end
    return out
  end

  -- Spec rule 1: 2300c of reagents for five units is 460c each, against the 5800c the site says
  -- one costs at the auction house. Green, because crafting is cheaper.
  it("compares crafting with buying on the row tooltip, in green when it is cheaper", function()
    showCraftRun(false)
    local lines = tooltipOn(rowWithText("Alpha Herb"))
    local craft = lineWith(lines, "craft it: ")
    assert.equal("craft it: 5× Bravo Ore + 5× Charlie Dust = 460c each", craft.text)
    assert.truthy(lineWith(lines, "vs 5800c at the auction house, right-click to split"))
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] },
      craft.color)
  end)

  it("greys the comparison when the auction house is cheaper", function()
    GC.AppRuns._set({ { code = "run-x", name = "Craft run", updatedAt = 900, origin = "app",
      lines = { { i = 101, q = 20, u = 300, cr = { r = 900, n = 5, c = 2300, i = {
        { i = 102, q = 5, n = "Bravo Ore", u = 300 } } } } } } })
    GC.db.runSplits = {}
    GC.db.settings.sniper.buyRun = "run-x"
    GC.Buy.Show()
    local lines = tooltipOn(rowWithText("Alpha Herb"))
    local vs = lineWith(lines, "vs 300c at the auction house, right-click to split")
    assert.truthy(vs)
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3] },
      vs.color)
  end)

  it("offers the way back on a line that is already split", function()
    showCraftRun(true)
    local lines = tooltipOn(rowWithText("craft 4×"))
    assert.truthy(lineWith(lines, "vs 5800c at the auction house, right-click to buy it whole"))
  end)

  -- A reagent the run already asked for does not get a second row; its NEED grows instead, and
  -- a NEED that grew without explanation is a number the player cannot check.
  it("says on a merged line how much of its NEED belongs to a craft", function()
    GC.AppRuns._set({ { code = "run-m", name = "Craft run", updatedAt = 900, origin = "app",
      lines = {
        { i = 101, q = 20, u = 5800, cr = { r = 900, n = 5, c = 2300, i = {
          { i = 103, q = 5, n = "Charlie Dust", u = 160 } } } },
        { i = 103, q = 7 },
      } } })
    GC.db.runSplits = { ["run-m"] = { [101] = true } }
    GC.db.settings.sniper.buyRun = "run-m"
    GC.Buy.Show()
    local lines = tooltipOn(rowWithText("Charlie Dust"))
    assert.truthy(lineWith(lines, "includes 20 for crafting Alpha Herb"))
  end)

  -- The row's right-click menu, as the client's MenuUtil would build it: every entry in order,
  -- the titles and the buttons, each button with what it does.
  local function rowMenu(row)
    local entries
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      entries = {}
      generator(nil, {
        CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
        CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
        CreateDivider = function() end,
      })
    end }
    row.scripts.OnMouseUp(row, "RightButton")
    _G.MenuUtil = nil
    return entries
  end
  local function menuTextsOf(entries)
    local out = {}
    for _, e in ipairs(entries or {}) do out[#out + 1] = e.text end
    return out
  end
  local function entryNamed(entries, text)
    for _, e in ipairs(entries or {}) do if e.text == text then return e end end
  end

  it("splits a line from its row menu and puts it back again", function()
    showCraftRun(false)
    local entries = rowMenu(rowWithText("Alpha Herb"))
    assert.same({ "Alpha Herb", "Skip for now", "Change the cap…", "Split into reagents (craft 4×)" },
      menuTextsOf(entries))
    entryNamed(entries, "Split into reagents (craft 4×)").fn()
    assert.is_true(GC.db.runSplits["run-c"][101])
    assert.truthy(rowWithText("craft 4×"))

    entries = rowMenu(rowWithText("craft 4×"))
    assert.same({ "Alpha Herb", "Skip for now", "Buy it whole instead" }, menuTextsOf(entries))
    entryNamed(entries, "Buy it whole instead").fn()
    assert.is_nil(GC.db.runSplits["run-c"][101])
    assert.is_nil(rowWithText("craft 4×"))
  end)

  it("offers a vendor line neither the comparison, the split nor a cap", function()
    GC.AppRuns._set({ { code = "run-vs", name = "Vendor run", updatedAt = 900, origin = "app",
      lines = { { i = 104, q = 20, v = true, vu = 5, u = 5800,
        cr = { r = 900, n = 5, c = 2300, i = { { i = 102, q = 5, n = "Bravo Ore", u = 300 } } } } },
    } })
    GC.db.runSplits = {}
    GC.db.settings.sniper.buyRun = "run-vs"
    GC.Buy.Show()
    local vendorRow = rowWithText("Delta Vial")
    for _, text in ipairs(texts(tooltipOn(vendorRow))) do
      assert.is_nil(text:find("craft it:", 1, true))
      assert.is_nil(text:find("right-click", 1, true))
    end
    assert.same({ "Delta Vial", "Skip for now" }, menuTextsOf(rowMenu(vendorRow)))
  end)

  it("opens no menu on a left click", function()
    showCraftRun(true)
    local opened = 0
    _G.MenuUtil = { CreateContextMenu = function() opened = opened + 1 end }
    local parent = rowWithText("craft 4×")
    parent.scripts.OnMouseUp(parent, "LeftButton")
    assert.equal(0, opened)
    _G.MenuUtil = nil
  end)

  -- BUY 2.0: every open line can be skipped for the session and have its cap set as a price.
  it("offers skip and the cap on every open line", function()
    assert.same({ "Charlie Dust", "Skip for now", "Change the cap…" },
      menuTextsOf(rowMenu(rowWithText("Charlie Dust"))))
    -- A reagent a split brought in is a line like any other.
    showCraftRun(true)
    assert.same({ "Bravo Ore", "Skip for now", "Change the cap…" },
      menuTextsOf(rowMenu(rowWithText("Bravo Ore"))))
  end)

  it("skips a line from its menu, and takes it back", function()
    local entries = rowMenu(rowWithText("Alpha Herb"))
    entryNamed(entries, "Skip for now").fn()
    assert.is_true(GC.Buy._skipped["run-1"][101])
    assert.equal("skipped for now", rowWithText("Alpha Herb").status:GetText())
    assert.are_not.equal(101, GC.Buy._focus) -- the dock moved on
    entries = rowMenu(rowWithText("Alpha Herb"))
    assert.same({ "Alpha Herb", "Don't skip", "Change the cap…" }, menuTextsOf(entries))
    entryNamed(entries, "Don't skip").fn()
    assert.is_nil(GC.Buy._skipped["run-1"][101])
  end)

  it("offers the way back to the default cap once the line has one of its own", function()
    GC.Buy._SetLineCap("run-1", 101, 1400)
    GC.Buy.RefreshIfShown()
    local entries = rowMenu(rowWithText("Alpha Herb"))
    assert.same({ "Alpha Herb", "Skip for now", "Change the cap…", "Use the default cap" }, menuTextsOf(entries))
    entryNamed(entries, "Use the default cap").fn()
    assert.is_nil(GC.db.runLineCaps["run-1"][101])
    assert.equal(1300, lineOfRow(rowWithText("Alpha Herb")).cap)
  end)

  it("offers to raise the cap of a line nothing under it can fill", function()
    GC.Buy.CurrentRun():SetFloor(101, 5000, 2000) -- NOW over the 1300 cap
    GC.Buy.RefreshIfShown()
    local entries = rowMenu(rowWithText("Alpha Herb"))
    assert.same({ "Alpha Herb", "Skip for now", "Raise cap to 5000c", "Change the cap…" }, menuTextsOf(entries))
    entryNamed(entries, "Raise cap to 5000c").fn()
    assert.equal(5000, GC.db.runLineCaps["run-1"][101])
  end)

  it("closes the price box when the tab goes out of sight", function()
    local closed = 0
    GC.BuyCapEditor = { Close = function() closed = closed + 1 end }
    local c = containerOf()
    c.scripts.OnHide(c)
    assert.equal(1, closed)
  end)

  it("opens the price box on the line's cap and stores what the player sets", function()
    local opened
    GC.BuyCapEditor = { Open = function(anchor, opts) opened = { anchor = anchor, opts = opts } end }
    local row = rowWithText("Alpha Herb")
    entryNamed(rowMenu(row), "Change the cap…").fn()
    assert.equal(row, opened.anchor)
    assert.equal("Cap for Alpha Herb", opened.opts.title)
    assert.equal(1300, opened.opts.current)
    opened.opts.onCommit(1250)
    assert.equal(1250, GC.db.runLineCaps["run-1"][101])
    assert.equal("yours", lineOfRow(rowWithText("Alpha Herb")).capFrom)
  end)

  -- An alert group's cap is its target, set on goldcap.gg.
  it("offers only skip on an alert group's line", function()
    GC.AppRuns._set({ { code = "a0000001", name = "Cheap ore", updatedAt = 900, origin = "app", k = "alert",
      lines = { { i = 101, q = 4, u = 5800, cc = 4000 } } } })
    GC.db.settings.sniper.buyRun = "a0000001"
    GC.Buy.Show()
    assert.same({ "Alpha Herb", "Skip for now" }, menuTextsOf(rowMenu(rowWithText("Alpha Herb"))))
  end)

  -- A line the bags and the bank already cover has nothing left to decide, and the tooltip on
  -- that same row already refuses to compare crafting with buying on it. "Split into reagents
  -- (craft 0x)" is not an offer: it is an entry that looks actionable on a line nobody can act on.
  it("opens no menu on a line that is already bought", function()
    stubItemCount({ [101] = { all = 20, carried = 0 } })
    showCraftRun(false)
    local opened = 0
    _G.MenuUtil = { CreateContextMenu = function() opened = opened + 1 end }
    local alpha = rowWithText("Alpha Herb")
    assert.equal("0", tostring(lineOfRow(alpha).buy))
    alpha.scripts.OnMouseUp(alpha, "RightButton")
    assert.equal(0, opened)
    _G.MenuUtil = nil
  end)

  -- Finding 1's rule again: a purchase already committed to these lines. Re-splitting the run
  -- under it would leave settlePurchase crediting a line that no longer exists.
  it("opens no menu while a purchase is in flight", function()
    showCraftRun(false)
    local opened = 0
    _G.MenuUtil = { CreateContextMenu = function() opened = opened + 1 end }
    GC.Buy._attempt = { stage = "started", itemID = 101, qty = 5, total = 5000 }
    local alpha = rowWithText("Alpha Herb")
    alpha.scripts.OnMouseUp(alpha, "RightButton")
    assert.equal(0, opened)
    GC.Buy._attempt = nil
    _G.MenuUtil = nil
  end)

  -- Spec rule 4: an alert group with live hits is a run of its own. Its cap is the alert's own
  -- target price, so the run has no cap to set; it is the site's to manage, so it has neither
  -- Archive nor Remove; and a hit bound to a realm says which, because the auction house search
  -- simply finds nothing for it anywhere else.
  local function alertRun()
    return { code = "a0000001", name = "Cheap ore", updatedAt = 900, origin = "app", k = "alert",
      lines = { { i = 101, q = 4, u = 5800, cc = 4000, rl = { id = 1305, n = "Kazzak" } },
                { i = 102, q = 2, u = 2000, cc = 1500 } } }
  end

  local function menuEntries()
    local entries = {}
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      generator(nil, {
        CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
        CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
        CreateDivider = function() entries[#entries + 1] = { text = "divider" } end,
      })
    end }
    local band = bandOf()
    band.picker.scripts.OnClick(band.picker)
    _G.MenuUtil = nil
    local out = {}
    for _, entry in ipairs(entries) do out[#out + 1] = entry.text end
    return out, entries
  end

  it("names the realm a hit is bound to, after the item", function()
    GC.AppRuns._set({ alertRun() })
    GC.db.settings.sniper.buyRun = "a0000001"
    GC.Buy.Show()
    assert.equal("Alpha Herb ×4 on Kazzak", rowWithText("Alpha Herb").reagent:GetText())
    assert.equal("Bravo Ore ×2", rowWithText("Bravo Ore").reagent:GetText())
  end)

  it("bands an alert run as a group with hits, and caps its lines at the alert's target",
    function()
      GC.AppRuns._set({ alertRun() })
      GC.db.settings.sniper.buyRun = "a0000001"
      GC.Buy.Show()
      assert.equal("alert group · 2 hits", bandOf().done:GetText())
      for _, line in ipairs(GC.Buy.CurrentRun():Lines()) do
        if line.itemID == 101 then assert.equal(4000, line.cap) end
      end
    end)

  -- Every line of an alert run is one hit the group found. A reagent the player split a hit into
  -- is not a hit of its own -- counting it said the group had found more than it had.
  it("counts an alert group's hits, not the reagents a split put under one", function()
    local alert = alertRun()
    alert.lines[1].cr = { r = 900, n = 5, c = 2300,
                          i = { { i = 103, q = 5, n = "Charlie Dust", u = 160 } } }
    GC.AppRuns._set({ alert })
    GC.db.runSplits = { ["a0000001"] = { [101] = true } }
    GC.db.settings.sniper.buyRun = "a0000001"
    GC.Buy.Show()
    assert.truthy(rowWithText("Charlie Dust"))
    assert.equal("alert group · 2 hits", bandOf().done:GetText())
  end)

  it("puts alert runs under their own divider and leaves them to the site", function()
    GC.AppRuns._set({ run(), alertRun() })
    GC.db.settings.sniper.buyRun = "a0000001"
    GC.Buy.Show()
    -- `menuTexts`, not `texts`: this describe already has a texts() helper for tooltip lines.
    local menuTexts = menuEntries()
    assert.same({ "Runs", "   Flask run, 4 lines, goldcap.gg",
                  "divider", "Alerts", "• Cheap ore, 2 lines, goldcap.gg",
                  "divider", "cap: alert target", "Export", "From goldcap.gg: manage it there",
                  "divider", "New list", "Import a list…" }, menuTexts)
  end)

  -- Spec rule 3: a followed run rides in after the player's own, marked with its owner, and
  -- Unfollow lives on goldcap.gg -- so neither Remove nor Archive is offered here either.
  it("marks a followed run with its owner and leaves it to the site", function()
    GC.AppRuns._set({ run({ code = "shr30000", name = "Guild flasks", by = "Acromion" }) })
    GC.db.settings.sniper.buyRun = "shr30000"
    GC.Buy.Show()
    assert.equal("Guild flasks ▼", bandOf().picker.label)
    assert.equal("1 of 4 done · from Acromion", bandOf().done:GetText())
    local menuTexts = menuEntries()
    assert.same({ "Runs", "• Guild flasks, 4 lines, from Acromion",
                  "divider", "Add to favourites", "Export", "From goldcap.gg: manage it there",
                  "Copy vendor list", "divider", "New list", "Import a list…" }, menuTexts)
  end)

  -- Spec rule 2: the site recomputed the plan, Core/AppRuns.lua noticed, and the band says so
  -- for a day, after how much of the run is done.
  it("says in the band that the plan was updated, and for how long", function()
    GC.AppRuns._set({ run() })
    GC.db.runNotices = { ["run-1"] = { at = 2000, added = 2, removed = 1 } }
    GC.db.settings.sniper.buyRun = "run-1"
    GC.Buy.Show()
    assert.equal("1 of 4 done · plan updated on goldcap.gg · +2 -1 lines", bandOf().done:GetText())

    -- A day old exactly: the notice goes.
    GC.db.runNotices = { ["run-1"] = { at = 2000 - 86400, added = 2, removed = 1 } }
    GC.Buy.RefreshIfShown()
    assert.equal("1 of 4 done", bandOf().done:GetText())
  end)

  it("says the plan was updated with no counts when only a quantity moved", function()
    GC.AppRuns._set({ run() })
    GC.db.runNotices = { ["run-1"] = { at = 2000, added = 0, removed = 0 } }
    GC.db.settings.sniper.buyRun = "run-1"
    GC.Buy.Show()
    assert.equal("1 of 4 done · plan updated on goldcap.gg", bandOf().done:GetText())
  end)

  -- BUY 2.0: a line's cap is a price, stored beside the run (a companion sync replaces the run
  -- wholesale) and cleared without leaving anything behind.
  it("stores a line's own cap beside the run, and a cleared one leaves nothing behind", function()
    GC.Buy._SetLineCap("run-1", 101, 140)
    assert.same({ [101] = 140 }, GC.db.runLineCaps["run-1"])
    GC.Buy.RefreshIfShown()
    local line
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do if l.itemID == 101 then line = l end end
    assert.equal(140, line.cap)
    assert.equal("yours", line.capFrom)
    GC.Buy._SetLineCap("run-1", 101, nil)
    assert.is_nil(GC.db.runLineCaps["run-1"][101])
  end)

  it("creates no per-line cap store just by being drawn", function()
    GC.Buy.RefreshIfShown()
    assert.is_nil(GC.db.runLineCaps)
  end)

  -- BUY 2.0 (week 3 contract, part A): a line the list's route crafts itself is drawn as a craft
  -- line, with no BUY button, and is no part of what the run has left to spend.
  it("draws a line the route crafts itself as a craft line, with no button, and leaves it out of the rest", function()
    GC.AppRuns._set({ run({ lines = { { i = 101, q = 10 }, { i = 103, q = 3, mk = true } } }) })
    GC.Buy.SelectRun("run-1"); GC.Buy.RefreshIfShown()
    local made = rowWithText("Charlie Dust")
    assert.equal("craft", made.status:GetText())
    -- Never the dock's next purchase, and no button when picked by hand.
    assert.equal(101, GC.Buy._focus)
    pick(made)
    assert.is_false(dock().buy:IsShown())
    assert.equal("craft it yourself", dock().sub:GetText())
    assert.equal("~1g", bandOf().total:GetText()) -- 10 Alpha Herb at 1000c only
  end)

  -- BUY 2.0's rows: ITEM (with how many are left to buy), PRICE EACH and COST, or one word in
  -- place of the two prices for a line that is not simply ready to buy.
  it("draws a ready line in three columns and a special one as a single word", function()
    GC.Buy.RefreshIfShown()
    local open = rowWithText("Alpha Herb")
    assert.equal("Alpha Herb ×10", open.reagent:GetText())
    assert.is_true(open.cells.price:IsShown())
    assert.is_true(open.cells.cost:IsShown())
    assert.is_false(open.status:IsShown())
    local done = rowWithText("Bravo Ore") -- five in the bag cover its five
    assert.equal("Bravo Ore ×5", done.reagent:GetText())
    assert.is_false(done.cells.price:IsShown())
    assert.equal("bought", done.status:GetText())
  end)

  it("says over your cap with the cheapest price when NOW is above the cap", function()
    GC.Buy.CurrentRun():SetFloor(101, 5000, 2000)
    GC.Buy.RefreshIfShown()
    assert.equal("over your cap · 5000c", rowWithText("Alpha Herb").status:GetText())
  end)

  it("says skipped for now and dims a skipped line", function()
    GC.Buy._skipped = { ["run-1"] = { [101] = true } }
    GC.Buy.RefreshIfShown()
    local row = rowWithText("Alpha Herb")
    assert.equal("skipped for now", row.status:GetText())
    assert.equal(0.5, row.alpha)
    GC.Buy._skipped = {}
    GC.Buy.RefreshIfShown()
    assert.equal(1, rowWithText("Alpha Herb").alpha)
  end)

  it("says where a vendor line is bought and what it costs there", function()
    GC.AppRuns._set({ run({ lines = { { i = 104, q = 4, v = true, vu = 25 }, { i = 102, q = 9, v = true } } }) })
    GC.Buy.SelectRun("run-1"); GC.Buy.RefreshIfShown()
    assert.equal("at a vendor · 25c each", rowWithText("Delta Vial").status:GetText())
    assert.equal("at a vendor", rowWithText("Bravo Ore").status:GetText())
  end)

  -- BUY 2.0's band: the list, how much of it is done, and what is left to buy here.
  it("totals what is ready to buy here, marked as an estimate while anything is one", function()
    GC.Buy.RefreshIfShown()
    -- 101 Alpha Herb: 10 at mv 1000; 102 Bravo Ore: covered by the bag; 103 Charlie Dust: 3 at mv
    -- 3000; 104 Delta Vial: a vendor line. Ready: 101 and 103, nothing quoted yet.
    assert.equal("TO BUY HERE", bandOf().totalCaption:GetText())
    assert.equal("~1g90s", bandOf().total:GetText())
    assert.equal("1 of 4 done", bandOf().done:GetText())
  end)

  it("puts the count of lines ready to buy on the BUY rail badge", function()
    local badge
    GC.Sniper = GC.Sniper or {}
    GC.Sniper.UpdateBuyTabLabel = function() badge = GC.Buy.ReadyCount() end
    GC.Buy.RefreshIfShown()
    assert.equal(2, badge)
    GC.Sniper.UpdateBuyTabLabel = nil
  end)

  -- BUY 2.0's filters and search. Ten lines: 101-110, two of each; 102 Bravo Ore is covered by the
  -- bag, 104 Delta Vial is at the vendor, the rest have no name the client knows ("#105"...).
  local function longRun()
    local lines = {}
    for i = 1, 10 do lines[i] = { i = 100 + i, q = 2 } end
    lines[4].v = true
    return { code = "run-long", name = "Long run", updatedAt = 100, origin = "app", lines = lines }
  end
  local function showLong()
    GC.AppRuns._set({ longRun() }); GC.Buy.SelectRun("run-long"); GC.Buy.RefreshIfShown()
  end

  it("hides the search and filter for a short list", function()
    assert.is_false(bandOf().tools.frame:IsShown())
  end)

  it("narrows a long list by name, case-blind", function()
    showLong()
    local tools = bandOf().tools
    assert.is_true(tools.frame:IsShown())
    assert.equal("All ▼", tools.filter.label)
    tools.search:SetText("alpha"); tools.search.scripts.OnTextChanged(tools.search, true)
    local names = {}
    for _, row in ipairs(shownRows()) do names[#names + 1] = row.reagent:GetText() end
    assert.equal(1, #names)
    assert.is_truthy(names[1]:find("Alpha Herb", 1, true))
    -- Escape clears the search and gives the whole list back.
    tools.search.scripts.OnEscapePressed(tools.search)
    assert.equal(10, #shownRows())
  end)

  it("keeps only the lines the filter asks for", function()
    showLong()
    GC.Buy._SetFilter("vendor")
    assert.equal(1, #shownRows())
    for _, row in ipairs(shownRows()) do assert.is_truthy((row.status:GetText() or ""):find("at a vendor", 1, true)) end
    assert.equal("At a vendor ▼", bandOf().tools.filter.label)
    GC.Buy._SetFilter("done")
    assert.equal("Bravo Ore ×2", shownRows()[1].reagent:GetText())
  end)

  it("offers every filter from its menu, the one in use marked", function()
    showLong()
    local radios = {}
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      generator(nil, { CreateRadio = function(_, text, isSelected, setSelected, data)
        radios[#radios + 1] = { text = text, selected = isSelected(data), pick = function() setSelected(data) end }
      end })
    end }
    local filter = bandOf().tools.filter
    filter.scripts.OnClick(filter)
    _G.MenuUtil = nil
    local labels = {}
    for _, r in ipairs(radios) do labels[#labels + 1] = r.text end
    assert.same({ "All", "To buy", "Over cap", "At a vendor", "To craft", "Bought", "Skipped" }, labels)
    assert.is_true(radios[1].selected)
    radios[2].pick()
    assert.equal("buy", GC.Buy._filter)
  end)

  it("says so when nothing matches", function()
    showLong()
    GC.Buy._query = "zzz"; GC.Buy.RefreshIfShown()
    assert.is_truthy(shownTexts():find("Nothing on this list matches.", 1, true))
    -- ...and keeps the search in sight, so it can be cleared.
    assert.is_true(bandOf().tools.frame:IsShown())
  end)

  -- Review Focus 2.
  it("moves the dock to the first visible line it can buy when a filter hides its line", function()
    showLong()
    GC.Buy._focus = 101
    GC.Buy._query = "charlie"; GC.Buy.RefreshIfShown()
    assert.equal(103, GC.Buy._focus)
    assert.equal(103, dock().lineItemID)
  end)

  it("puts the dock on a line the filter shows even when none of them can be bought", function()
    showLong()
    GC.Buy._SetFilter("vendor")
    assert.equal(104, dock().lineItemID)
  end)

  it("never moves the dock off a purchase in flight", function()
    showLong()
    GC.Buy._focus = 101
    GC.Buy._attempt = { itemID = 101, stage = "confirm", qty = 1, total = 1 }
    GC.Buy._query = "charlie"; GC.Buy.RefreshIfShown()
    assert.equal(101, GC.Buy._focus)
    GC.Buy._attempt = nil
  end)

  it("forgets the search and filter when another list is picked", function()
    GC.Buy._query, GC.Buy._filter = "x", "done"
    GC.Buy.SelectRun("run-1")
    assert.equal("", GC.Buy._query)
    assert.equal("all", GC.Buy._filter)
  end)

  it("shows the search while a filter is in use, even on a short list", function()
    GC.Buy._SetFilter("done")
    assert.is_true(bandOf().tools.frame:IsShown())
  end)

  -- BUY 2.0: a wide window lists the player's lists on the left.
  local function goWide(width)
    local c = containerOf()
    c.width = width or 1040
    c.scripts.OnSizeChanged(c, c.width)
    GC.Buy.Show()
  end

  it("shows your lists beside the list when the window is wide, with each one's progress", function()
    local second = { code = "run-2", name = "Alchemy restock", updatedAt = 90, origin = "app", lines = { { i = 103, q = 2 } } }
    GC.AppRuns._set({ run(), second })
    goWide()
    local lists = GC.Buy._view.lists
    assert.is_true(lists.frame:IsShown())
    assert.equal("YOUR LISTS", lists.caption:GetText())
    assert.equal("Flask run", lists.entries[1].button.label)
    assert.equal("1 of 4", lists.entries[1].meta:GetText())
    assert.equal("Alchemy restock", lists.entries[2].button.label)
    assert.equal("0 of 1", lists.entries[2].meta:GetText()) -- no Charlie Dust in the bag
    assert.equal("goldcap.gg", lists.entries[1].origin:GetText())
    assert.equal("Lists come from goldcap.gg through the companion, or make one here with + New.",
      lists.footer:GetText())
    -- The rest of the tab starts after the column.
    assert.equal(196 + 12, GC.Buy._leftInset)
    assert.equal(1040 - 208, GC.Buy._view.band.fill.width * 4) -- one of four done, across what is left
  end)

  it("picks a list from the column", function()
    local second = { code = "run-2", name = "Alchemy restock", updatedAt = 90, origin = "app", lines = { { i = 103, q = 2 } } }
    GC.AppRuns._set({ run(), second })
    goWide()
    local b = GC.Buy._view.lists.entries[2].button
    b.scripts.OnClick(b)
    assert.equal("run-2", GC.Buy.CurrentRun():Code())
  end)

  it("counts an alert group's hits in the column", function()
    GC.AppRuns._set({ run(), { code = "a0000001", name = "Cheap ore", updatedAt = 900, origin = "app", k = "alert",
      lines = { { i = 101, q = 4, u = 5800, cc = 4000 }, { i = 103, q = 2, cc = 1500 } } } })
    goWide()
    assert.equal("2 hits", GC.Buy._view.lists.entries[2].meta:GetText())
  end)

  -- Listing twenty runs must not write twenty rows of progress into SavedVariables.
  it("reads the other lists' progress without writing any", function()
    local second = { code = "run-2", name = "Alchemy restock", updatedAt = 90, origin = "app", lines = { { i = 103, q = 2 } } }
    GC.AppRuns._set({ run(), second })
    goWide()
    local stored = GC.db.buyProgress and GC.db.buyProgress["?"] or {}
    assert.is_nil(stored["run-2"])
  end)

  it("keeps the column hidden in a docked or narrow window", function()
    assert.is_false(GC.Buy._view.lists.frame:IsShown())
    assert.equal(0, GC.Buy._leftInset)
    goWide(1040)
    goWide(700)
    assert.is_false(GC.Buy._view.lists.frame:IsShown())
    assert.equal(0, GC.Buy._leftInset)
  end)

  -- The column's own controls for the player's lists: "+ New" and "Import" at its top, where each
  -- list came from, its star, and a right-click menu that is the picker's for any list.
  describe("the column with lists made in the game", function()
    before_each(function()
      helper.loadModule("Core/AppRuns.lua", GC)
      GC.db.runs, GC.db.runsArchived = { ["run-1"] = run() }, {}
      GC.db.settings.sniper.buyRun = "run-1"
      goWide()
    end)

    after_each(function() _G.MenuUtil = nil end)

    local function rightClick(i)
      local entries = {}
      _G.MenuUtil = { CreateContextMenu = function(_, generator)
        generator(nil, {
          CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
          CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
          CreateDivider = function() end,
        })
      end }
      local b = GC.Buy._view.lists.entries[i].button
      b.scripts.OnClick(b, "RightButton")
      _G.MenuUtil = nil
      local said = {}
      for _, e in ipairs(entries) do said[#said + 1] = e.text end
      return said, function(text)
        for _, e in ipairs(entries) do if e.text == text then return e end end
      end
    end

    it("offers + New and Import at the top of the column", function()
      local lists = GC.Buy._view.lists
      assert.equal("+ New", lists.new.label)
      assert.equal("Import", lists.import.label)
      local opened
      GC.UI = { ShowImportDialog = function(opts) opened = opts end }
      lists.import.scripts.OnClick(lists.import)
      assert.same({ lists = true }, opened)
      GC.BuyCapEditor = { Open = function() end }
      lists.new.scripts.OnClick(lists.new)
      local code = GC.Buy.CurrentRun():Code()
      assert.equal("game", GC.db.runs[code].origin)
      assert.equal("List 1", lists.entries[2].button.label)
      assert.equal("in game", lists.entries[2].origin:GetText())
      assert.equal("0 of 0", lists.entries[2].meta:GetText())
      -- An item added counts in the column at once.
      _G.C_Item.GetItemInfoInstant = function(id) return id end
      local box = GC.Buy._view.add.box
      box:SetText("101 x2")
      box.scripts.OnEnterPressed(box)
      assert.equal("0 of 1", lists.entries[2].meta:GetText())
    end)

    -- Too long for one row in the player's language, the two buttons go one under the other.
    it("stacks + New and Import when the two do not fit side by side", function()
      textWidth = function(text) return #text * 20 end
      goWide()
      local lists = GC.Buy._view.lists
      assert.equal("TOPLEFT", lists.import.points[1].point)
      assert.equal("BOTTOMLEFT", lists.import.points[1].relativePoint)
    end)

    it("opens a goldcap.gg list's menu on a right click, with no rename and no delete", function()
      local said = rightClick(1)
      assert.same({ "Flask run", "Add to favourites", "Export", "Archive this run",
        "From goldcap.gg: rename or remove it there" }, said)
      -- A right click picks nothing.
      assert.equal("run-1", GC.Buy.CurrentRun():Code())
    end)

    it("renames, pins, moves and deletes a list made in the game from its right click", function()
      local made = GC.AppRuns.NewList()
      GC.Buy.RefreshIfShown()
      local said, find = rightClick(2)
      assert.same({ "List 1", "Rename…", "Add to favourites", "Move up", "Import into this list…",
        "Archive this run", "Delete this list…" }, said)
      -- The name box goes over the list's own entry in the column.
      local asked
      GC.BuyCapEditor = { Open = function(anchor, opts) asked = { anchor = anchor, opts = opts } end }
      find("Rename…").fn()
      assert.equal(GC.Buy._view.lists.entries[2].button, asked.anchor)
      asked.opts.onCommit("Herbs")
      assert.equal("Herbs", GC.Buy._view.lists.entries[2].button.label)
      find = select(2, rightClick(2))
      find("Add to favourites").fn()
      local lists = GC.Buy._view.lists
      assert.equal("|A:auctionhouse-icon-favorite:12:12|a Herbs", lists.entries[1].button.label)
      assert.equal("Flask run", lists.entries[2].button.label)
      assert.is_true(GC.db.runFavourites[made.code])
      find = select(2, rightClick(1))
      find("Delete this list…").fn()
      asked.opts.onCommit(true)
      assert.is_nil(GC.db.runs[made.code])
      assert.equal("Flask run", lists.entries[1].button.label)
      assert.is_false(lists.entries[2].button:IsShown())
    end)
  end)
end)
