local helper = require("spec.spec_helper")

-- The BUY tab's render, exercised the way spec/soldframe_spec.lua exercises Sold's: the real
-- Core/BuyRun.lua and Core/BagStock.lua underneath, fake widgets above, and the module-local
-- row pool / header band reached through debug.getupvalue. Only the two things a headless run
-- genuinely cannot have -- the client's bag API and the market-value lookup -- are stubbed.
describe("BuyFrame", function()
  local GC, rowsOf, containerOf, bandOf

  local NAMES = { [101] = "Alpha Herb", [102] = "Bravo Ore", [103] = "Charlie Dust",
                  [104] = "Delta Vial" }

  -- Four lines: one open, one already covered by the bags, one past the free limit, one at the
  -- vendor. That is every state a row can be in, in one run.
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
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
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

  local function chip(parent)
    local c = region("Frame", parent)
    c.text = region("FontString", c)
    function c:SetLabel(text, color) self.label = text; self.text:SetText(text); self.chipColor = color end
    return c
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
      Chip = function(parent) return chip(parent) end,
      WithQuality = function(name) return name end,
    }
    GC.db = { settings = { sniper = { buyCapPct = 130 } } }
    GC.Data = { GetItemValue = function(itemID)
      return ({ [101] = { mv = 1000 }, [102] = { mv = 2000 }, [103] = { mv = 3000 } })[itemID]
    end }
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)

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
      FreeLines = function() return 2 end,
      Remove = function(code)
        for i, r in ipairs(runs) do if r.code == code then table.remove(runs, i); return true end end
        return false
      end,
      _set = function(list) runs = list end,
    }

    helper.loadModule("UI/BuyFrame.lua", GC)

    rowsOf = function()
      local i = 1
      while true do
        local name, value = debug.getupvalue(GC.Buy.RefreshIfShown, i)
        if not name then error("rows upvalue not found") end
        if name == "rows" then return value end
        i = i + 1
      end
    end
    containerOf = function()
      local i = 1
      while true do
        local name, value = debug.getupvalue(GC.Buy.Show, i)
        if not name then error("container upvalue not found") end
        if name == "container" then return value end
        i = i + 1
      end
    end
    bandOf = function()
      local i = 1
      while true do
        local name, value = debug.getupvalue(GC.Buy.RefreshIfShown, i)
        if not name then error("band upvalue not found") end
        if name == "band" then return value end
        i = i + 1
      end
    end

    local host = region("Frame")
    GC.Buy.Attach(host, { panelLeft = 88, panelRightInset = 32, top = -100,
                          bottom = 34, rowWidth = 600, rowHeight = 28 })
    GC.Buy.Show()
  end)

  after_each(function()
    _G.CreateFrame, _G.GetCoinTextureString, _G.C_Item, _G.C_Container = nil, nil, nil, nil
    _G.GameTooltip, _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil, nil
    _G.GetItemCount = nil
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

  local function shownTexts()
    local out = {}
    for _, row in ipairs(shownRows()) do
      out[#out + 1] = (row.reagent:GetText() or "") .. " | " .. (row.wide:GetText() or "")
    end
    return table.concat(out, "\n")
  end

  it("shows each line's need, have and buy counts", function()
    local alpha, bravo = rowWithText("Alpha Herb"), rowWithText("Bravo Ore")
    assert.truthy(alpha and bravo)
    assert.equal("10", alpha.cells.need:GetText())
    assert.equal("0", alpha.cells.have:GetText())
    assert.equal("10", alpha.cells.buy:GetText())
    -- Five in the bags covers the whole need: nothing left to buy, and the row says "done"
    -- rather than offering a BUY 0 button.
    assert.equal("5", bravo.cells.have:GetText())
    assert.equal("0", bravo.cells.buy:GetText())
    assert.equal("done", bravo.cells.action:GetText())
    assert.is_false(bravo.action:IsShown())
  end)

  -- HAVE is what the player owns, not what they happen to be carrying: three hundred units in
  -- the bank are three hundred units nobody has to go shopping for.
  it("counts bank stock into HAVE alongside the bags", function()
    stubItemCount({ [102] = { all = 305, carried = 5 } })
    GC.Buy.Show()
    assert.equal("305", rowWithText("Bravo Ore").cells.have:GetText())
  end)

  it("needs no shopping trip for a line the bank alone covers", function()
    stubItemCount({ [101] = { all = 12, carried = 0 } })
    GC.Buy.Show()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("12", alpha.cells.have:GetText())
    assert.equal("0", alpha.cells.buy:GetText())
    assert.equal("done", alpha.cells.action:GetText())
    assert.is_false(alpha.action:IsShown())
  end)

  it("counts only the bags when the client has no item-count API", function()
    _G.C_Item.GetItemCount, _G.GetItemCount = nil, nil
    GC.Buy.Show()
    assert.equal("0", rowWithText("Alpha Herb").cells.have:GetText())
    assert.equal("5", rowWithText("Bravo Ore").cells.have:GetText())
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
    assert.equal("105", rowWithText("Bravo Ore").cells.have:GetText())
  end)

  -- An API that throws must cost the player the bank number, never the bag number.
  it("keeps the bag count when the item-count API errors", function()
    _G.C_Item.GetItemCount = function() error("no item") end
    GC.Buy.Show()
    assert.equal("5", rowWithText("Bravo Ore").cells.have:GetText())
  end)

  -- The bank is a subtraction, and a subtraction can come out below zero the moment the two
  -- answers disagree -- which would take stock the player is carrying back off HAVE.
  it("never lets the bank number pull HAVE below the bags", function()
    stubItemCount({ [102] = { all = 2, carried = 5 } })
    GC.Buy.Show()
    assert.equal("5", rowWithText("Bravo Ore").cells.have:GetText())
  end)

  it("splits HAVE into bags and bank on the row tooltip when the bank holds any", function()
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, SetItemByID = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
      Show = function() end, Hide = function() end,
    }
    stubItemCount({ [102] = { all = 305, carried = 5 } })
    GC.Buy.Show()
    local bravo = rowWithText("Bravo Ore")
    bravo.scripts.OnEnter(bravo)
    assert.same({ "in bags 5 · in bank 300" }, tooltipLines)
  end)

  it("says nothing about the bank on the tooltip when there is none in it", function()
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, SetItemByID = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
      Show = function() end, Hide = function() end,
    }
    GC.Buy.Show()
    local bravo = rowWithText("Bravo Ore")
    bravo.scripts.OnEnter(bravo)
    assert.same({}, tooltipLines)
  end)

  -- At rest -- nothing quoted yet -- the button names the quantity and nothing else. What a
  -- click does from there, and what the label becomes, is spec/buy_purchase_spec.lua's.
  it("offers a BUY button for the quantity still missing", function()
    local alpha = rowWithText("Alpha Herb")
    assert.truthy(alpha.action:IsShown())
    assert.equal("BUY 10", alpha.action.label)
    assert.is_true(alpha.action:IsEnabled())
  end)

  it("puts the vendor line after the open ones and the finished line last", function()
    local lineRows = {}
    for _, row in ipairs(shownRows()) do
      if (row.reagent:GetText() or "") ~= "" then lineRows[#lineRows + 1] = row end
    end
    assert.equal(4, #lineRows)
    -- 101 open, 103 open (locked), 104 vendor, 102 done -- the bags already cover 102.
    assert.equal("Alpha Herb", lineRows[1].reagent:GetText())
    assert.equal("Charlie Dust", lineRows[2].reagent:GetText())
    assert.equal("Delta Vial", lineRows[3].reagent:GetText())
    assert.equal("vendor", lineRows[3].cells.action:GetText())
    assert.is_false(lineRows[3].action:IsShown())
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      lineRows[3].reagent.colorValue)
    assert.equal("Bravo Ore", lineRows[4].reagent:GetText())
    assert.equal("done", lineRows[4].cells.action:GetText())
  end)

  it("locks the lines past the free limit behind a Pro pill and says how many", function()
    local charlie = rowWithText("Charlie Dust")
    assert.truthy(charlie)
    assert.is_true(charlie.pro:IsShown())
    assert.equal("Pro", charlie.pro.label)
    assert.is_false(charlie.action:IsShown())
    -- The first two non-vendor lines are free; only the third is locked.
    assert.is_false(rowWithText("Alpha Herb").pro:IsShown())
    assert.truthy(shownTexts():find("1 more lines with Pro", 1, true))
  end)

  it("counts lines, buys and vendor stops in the header band", function()
    local band = bandOf()
    assert.equal("4 lines · 2 to buy · 1 at the vendor", band.counts:GetText())
    assert.truthy(band.spent:GetText():find("spent ", 1, true))
    assert.truthy(band.spent:GetText():find("left ~", 1, true))
    assert.equal("in bags and bank · purchases arrive by mail", band.bags:GetText())
  end)

  -- Spec rule 5: a run with nothing left to buy and nothing left to fetch says so, rather than
  -- counting three zeroes at the player.
  it("says everything is bought when the run has nothing left", function()
    GC.AppRuns._set({ run({ code = "run-d", updatedAt = 900,
      lines = { { i = 102, q = 5 }, { i = 104, q = 0, v = true } } }) })
    GC.db.settings.sniper.buyRun = "run-d"
    GC.Buy.Show()
    assert.equal("everything bought", bandOf().counts:GetText())
    assert.is_truthy(bandOf().spent:GetText():find("spent ", 1, true))
  end)

  it("still counts the lines while anything is left", function()
    assert.equal("4 lines · 2 to buy · 1 at the vendor", bandOf().counts:GetText())
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

  it("opens a menu of runs with remove for a pasted run and paste for everyone", function()
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
    assert.same({ "Runs", "   Flask run  ·  4 lines  ·  goldcap.gg", "• Potion run  ·  4 lines  ·  pasted",
      "divider", "Cap: 130%", "Archive this run", "Remove this run", "Paste a run..." }, texts)

    -- Remove drops the pasted run and lands on the one left.
    entries[7].fn()
    assert.is_nil(GC.AppRuns.Get("run-2"))
    assert.equal("run-1", GC.Buy.CurrentRun():Code())
    assert.equal("Flask run ▼", bandOf().picker.label)
  end)

  it("says an app run is removed on the site, not here", function()
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
    assert.same({ "Runs", "• Flask run  ·  4 lines  ·  goldcap.gg", "Cap: 130%",
      "Archive this run", "From goldcap.gg — remove it there", "Paste a run..." }, entries)
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
    assert.truthy(entryNamed("Paste a run..."))

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

  it("shows the empty state and hides the picker when there are no runs", function()
    GC.AppRuns._set({})
    GC.db.settings.sniper.buyRun = nil
    GC.Buy.Show()
    assert.is_nil(GC.Buy.CurrentRun())
    assert.truthy(shownTexts():find("No runs yet.", 1, true))
    assert.is_false(bandOf().picker:IsShown())
    assert.equal("", bandOf().counts:GetText())
  end)

  it("recounts what is in the bags when the bags change", function()
    assert.equal("10", rowWithText("Alpha Herb").cells.buy:GetText())
    stubBags({ [1] = { itemID = 102, qty = 5 }, [2] = { itemID = 101, qty = 4 } })
    GC.Buy.OnBagsChanged()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("4", alpha.cells.have:GetText())
    assert.equal("6", alpha.cells.buy:GetText())
    assert.equal("BUY 6", alpha.action.label)
  end)

  -- GC.BagStock.Scan drops a soulbound stack because the auction house will not POST it --
  -- a Sell rule this tab has to override. A bound reagent in the bags is still a reagent the
  -- player does not have to buy, and forwarding the flag sent them shopping for it.
  it("counts a soulbound stack toward HAVE", function()
    stubBags({ [1] = { itemID = 102, qty = 5 }, [2] = { itemID = 101, qty = 7, bound = true } })
    GC.Buy.OnBagsChanged()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("7", alpha.cells.have:GetText())
    assert.equal("3", alpha.cells.buy:GetText())
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
    assert.equal("4", rowWithText("Alpha Herb").cells.have:GetText())
  end)

  -- A run keeps its code across a companion sync while its lines change, so the code alone
  -- does not prove the built object is current -- updatedAt does.
  it("rebuilds the run when the companion resyncs the same code with newer lines", function()
    GC.AppRuns._set({ run({ updatedAt = 900, lines = { { i = 101, q = 2 } } }) })
    GC.Buy.Show()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("2", alpha.cells.need:GetText())
    assert.is_nil(rowWithText("Charlie Dust"))
  end)

  it("shows USUAL from market value and an em dash for a NOW nobody has seen yet", function()
    local alpha = rowWithText("Alpha Herb")
    assert.equal("—", alpha.cells.now:GetText())
    assert.equal("1000c", alpha.cells.usual:GetText())
    -- A line with no market value at all states neither, rather than inventing a zero.
    local delta = rowWithText("Delta Vial")
    assert.equal("—", delta.cells.usual:GetText())
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
    assert.equal("vendor", vendor.cells.action:GetText())
    assert.equal("25c", vendor.cells.now:GetText())
    assert.equal("25c", vendor.cells.usual:GetText())
    assert.equal("100c", vendor.cells.cost:GetText())   -- 5 already in bags, 4 left to buy at 25c
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      vendor.cells.cost.colorValue)
  end)

  -- Without a vendor price there is no honest number: the market value beside it is not one.
  it("leaves a vendor line with no vendor price on em dashes", function()
    GC.AppRuns._set({ run({ code = "run-v", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 9, v = true } } }) })
    GC.db.settings.sniper.buyRun = "run-v"
    GC.Buy.Show()

    local vendor = rowWithText("Bravo Ore")
    assert.equal("—", vendor.cells.now:GetText())
    assert.equal("—", vendor.cells.usual:GetText())   -- 102 has a market value; it is not the point
    assert.equal("—", vendor.cells.cost:GetText())

    -- ...while the line the player is actually here to buy still prices.
    local alpha = rowWithText("Alpha Herb")
    assert.equal("1000c", alpha.cells.usual:GetText())
    assert.equal("~1g", alpha.cells.cost:GetText())
  end)

  -- Finding 4: a vendor stop the bags already cover is `buy == 0` at a known price -- `buy * unit`
  -- is honestly zero, but "0c" reads as a real quote rather than as the nothing-left-to-do an
  -- em dash says everywhere else on this tab.
  it("shows the em dash, not 0c, for a done vendor line's cost", function()
    GC.AppRuns._set({ run({ code = "run-vd", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 5, v = true, vu = 25 } } }) })
    GC.db.settings.sniper.buyRun = "run-vd"
    GC.Buy.Show()

    local vendor = rowWithText("Bravo Ore")
    assert.equal("25c", vendor.cells.now:GetText())
    assert.equal("25c", vendor.cells.usual:GetText())
    assert.equal("—", vendor.cells.cost:GetText())
  end)

  -- Spec rule 2: the run header offers the vendor stops as a block of plain text, because the
  -- player has to read them off the screen while standing at a vendor.
  it("copies the run's vendor stops out as a list with a total", function()
    GC.AppRuns._set({ run({ code = "run-v", updatedAt = 900, lines = {
      { i = 101, q = 10 }, { i = 104, q = 5, v = true, vu = 25 },
      { i = 103, q = 2, v = true, vu = 10000 } } }) })
    GC.db.settings.sniper.buyRun = "run-v"
    GC.Buy.Show()

    local copied
    GC.UI = { ShowVendorList = function(text) copied = text end }
    local band = bandOf()
    assert.is_true(band.vendor:IsShown())
    assert.equal("Copy vendor list", band.vendor.label)
    band.vendor.scripts.OnClick(band.vendor)

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
    local copied
    GC.UI = { ShowVendorList = function(text) copied = text end }
    bandOf().vendor.scripts.OnClick(bandOf().vendor)
    assert.equal("5× Delta Vial\nTotal: 0c", copied)
  end)

  it("hides the button for a run with no vendor stop", function()
    GC.AppRuns._set({ run({ code = "run-n", updatedAt = 900, lines = { { i = 101, q = 10 } } }) })
    GC.db.settings.sniper.buyRun = "run-n"
    GC.Buy.Show()
    assert.is_false(bandOf().vendor:IsShown())
  end)

  -- The money line yields to the vendor button while the button is up, and takes the whole
  -- width back when it is not -- a shared RIGHT anchor would draw the text under the button.
  it("stops the money line at the vendor button while the button is shown", function()
    local function rightOf(fs)
      for _, p in ipairs(fs.points) do if p.point == "RIGHT" then return p end end
    end
    GC.AppRuns._set({ run() })   -- has a vendor line still to buy
    GC.Buy.SelectRun("run-1")
    GC.Buy.Show()
    local band = bandOf()
    assert.is_true(band.vendor:IsShown())
    assert.equal(band.vendor, rightOf(band.spent).relative)
    GC.AppRuns._set({ run({ code = "run-2", lines = { { i = 101, q = 10 } } }) })   -- no vendor stop
    GC.Buy.SelectRun("run-2")
    GC.Buy.Show()
    band = bandOf()
    assert.is_false(band.vendor:IsShown())
    assert.equal(band.bags, rightOf(band.spent).relative)
  end)

  -- The button hangs off the legend on the band's SECOND line, not between the picker and the
  -- counts on the first: the counts string has two opposing anchors and no width of its own, so
  -- anything parked in front of it is what the text overflows onto at a narrow docked width.
  it("hangs the vendor button off the legend, leaving line one to the picker and the counts",
    function()
      local band = bandOf()
      local anchor
      for _, p in ipairs(band.vendor.points) do if p.point == "RIGHT" then anchor = p end end
      assert.truthy(anchor)
      assert.equal(band.bags, anchor.relative)
      assert.equal("LEFT", anchor.relativePoint)
      assert.equal(-GC.Theme.pad.s, anchor.x)

      local countsLeft
      for _, p in ipairs(band.counts.points) do if p.point == "LEFT" then countsLeft = p end end
      assert.truthy(countsLeft)
      assert.equal(band.picker, countsLeft.relative)
      assert.equal("RIGHT", countsLeft.relativePoint)
    end)

  it("labels the column header row REAGENT/NEED/HAVE/BUY/NOW/USUAL/COST/ACTION", function()
    local header = bandOf().header
    assert.truthy(header and header.cells)
    assert.equal("REAGENT", header.reagentCell.label:GetText())
    assert.equal("NEED", header.cells.need.label:GetText())
    assert.equal("HAVE", header.cells.have.label:GetText())
    assert.equal("BUY", header.cells.buy.label:GetText())
    assert.equal("NOW", header.cells.now.label:GetText())
    assert.equal("USUAL", header.cells.usual.label:GetText())
    assert.equal("COST", header.cells.cost.label:GetText())
    assert.equal("ACTION", header.cells.action.label:GetText())
  end)

  it("drops USUAL first as the window narrows, then NOW, and restores both", function()
    local container = containerOf()
    container.width = 900
    GC.Buy.Show()
    local wide = rowWithText("Alpha Herb")
    assert.truthy(wide.cells.usual:IsShown())
    assert.truthy(wide.cells.now:IsShown())

    container.width = 480
    GC.Buy.Show()
    local mid = rowWithText("Alpha Herb")
    assert.is_false(mid.cells.usual:IsShown())
    assert.truthy(mid.cells.now:IsShown())

    container.width = 300
    GC.Buy.Show()
    local narrow = rowWithText("Alpha Herb")
    assert.is_false(narrow.cells.usual:IsShown())
    assert.is_false(narrow.cells.now:IsShown())

    container.width = 900
    GC.Buy.Show()
    local restored = rowWithText("Alpha Herb")
    assert.truthy(restored.cells.usual:IsShown())
    assert.truthy(restored.cells.now:IsShown())
  end)

  -- Spec rule 3: the hour the site measured is UTC; the player reads realm time. The offset is
  -- the difference between the client's own two clocks -- realm time and the same instant in UTC.
  it("says in the row's tooltip when the item is usually cheapest, in realm time", function()
    local tooltipLines
    _G.GameTooltip = {
      SetOwner = function() end,
      SetItemByID = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
      Show = function() end, Hide = function() end,
    }
    -- Realm clock says 14:00 while UTC says 12:00: a realm two hours ahead of UTC.
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 14 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 12 } end

    GC.AppRuns._set({ run({ code = "run-c", updatedAt = 900,
      lines = { { i = 101, q = 10, ch = 3, cp = -18 }, { i = 102, q = 5 } } }) })
    GC.db.settings.sniper.buyRun = "run-c"
    GC.Buy.Show()

    tooltipLines = {}
    local alpha = rowWithText("Alpha Herb")
    alpha.scripts.OnEnter(alpha)
    assert.same({ "usually cheapest around 05:00 · -18%" }, tooltipLines)   -- 3 UTC + 2

    -- A line the site could not measure says nothing at all.
    tooltipLines = {}
    local bravo = rowWithText("Bravo Ore")
    bravo.scripts.OnEnter(bravo)
    assert.same({}, tooltipLines)

    _G.GameTooltip, _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil, nil
  end)

  -- Realm behind UTC and an hour that wraps past midnight: the two `% 24`s are what keep
  -- 23:00 UTC on a realm at UTC-2 from reading as "-1:00" or "25:00".
  it("wraps the cheap hour through midnight for a realm behind UTC", function()
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, SetItemByID = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
      Show = function() end, Hide = function() end,
    }
    -- Realm clock 21:00 while UTC says 23:00: offset (21 - 23) % 24 = 22, i.e. two hours behind.
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 21 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 23 } end

    GC.AppRuns._set({ run({ code = "run-w", updatedAt = 900,
      lines = { { i = 101, q = 10, ch = 1, cp = -9 }, { i = 102, q = 5 } } }) })
    GC.db.settings.sniper.buyRun = "run-w"
    GC.Buy.Show()
    local alpha = rowWithText("Alpha Herb")
    alpha.scripts.OnEnter(alpha)
    assert.same({ "usually cheapest around 23:00 · -9%" }, tooltipLines)   -- (1 + 22) % 24

    _G.GameTooltip, _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil, nil
  end)

  -- An hour in the wrong timezone is worse than no hour, so a client that cannot answer gets
  -- nothing rather than the UTC hour dressed up as a local one.
  it("says nothing about the cheap hour when the client cannot give the offset", function()
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, SetItemByID = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
      Show = function() end, Hide = function() end,
    }
    GC.AppRuns._set({ run({ code = "run-c", updatedAt = 900,
      lines = { { i = 101, q = 10, ch = 3, cp = -18 } } }) })
    GC.db.settings.sniper.buyRun = "run-c"
    GC.Buy.Show()
    local alpha = rowWithText("Alpha Herb")
    alpha.scripts.OnEnter(alpha)
    assert.same({}, tooltipLines)
    _G.GameTooltip = nil
  end)

  -- Finding 3: a vendor sells at one fixed price, so "usually cheapest around HH:00" is noise --
  -- there is no auction house history for this line to be a footnote on.
  it("says nothing about the cheap hour on a vendor line", function()
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, SetItemByID = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
      Show = function() end, Hide = function() end,
    }
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 14 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 12 } end

    GC.AppRuns._set({ run({ code = "run-vc", updatedAt = 900,
      lines = { { i = 101, q = 10 }, { i = 102, q = 9, v = true, vu = 25, ch = 3, cp = -18 } } }) })
    GC.db.settings.sniper.buyRun = "run-vc"
    GC.Buy.Show()

    local vendor = rowWithText("Bravo Ore")
    vendor.scripts.OnEnter(vendor)
    assert.same({}, tooltipLines)

    _G.GameTooltip, _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil, nil
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
    local alpha = rowWithText("Alpha Herb")
    assert.equal("BUY 20", alpha.action.label)
    assert.is_nil(rowWithText("Bravo Ore"))
  end)

  it("draws a split line as a craft line with its reagents indented under it", function()
    showCraftRun(true)
    local parent = rowWithText("craft 4×")
    assert.truthy(parent)
    assert.equal("Alpha Herb → craft 4× (5 per craft)", parent.reagent:GetText())
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      parent.reagent.colorValue)
    assert.equal("craft", parent.cells.action:GetText())
    assert.is_false(parent.action:IsShown())
    -- Nothing here is bought at the auction house, so NOW and USUAL have nothing to say.
    assert.equal("—", parent.cells.now:GetText())
    assert.equal("—", parent.cells.usual:GetText())
    -- COST is what the reagents still cost: 15 Bravo Ore at 300 (five are in the bags) and
    -- 20 Charlie Dust at 160.
    assert.equal("~" .. tostring(15 * 300 + 20 * 160) .. "c", parent.cells.cost:GetText())

    local ore = rowWithText("Bravo Ore")
    assert.equal("↳ Bravo Ore", ore.reagent:GetText())
    assert.equal("20", ore.cells.need:GetText())
    assert.equal("15", ore.cells.buy:GetText())
    assert.equal("BUY 15", ore.action.label)
    assert.equal("↳ Charlie Dust", rowWithText("Charlie Dust").reagent:GetText())
  end)

  it("counts what is left to craft in the header band", function()
    showCraftRun(true)
    assert.equal("3 lines · 2 to buy · 1 to craft · 0 at the vendor", bandOf().counts:GetText())
  end)

  -- A run whose only open line is a craft is not a run with nothing left to do.
  it("does not call a run with a craft still to make 'everything bought'", function()
    GC.AppRuns._set({ { code = "run-cd", name = "Craft run", updatedAt = 900, origin = "app",
      lines = { { i = 101, q = 20, u = 5800, cr = { r = 900, n = 5, c = 2300, i = {
        { i = 102, q = 1, n = "Bravo Ore", u = 300 } } } } } } })
    GC.db.runSplits = { ["run-cd"] = { [101] = true } }
    GC.db.settings.sniper.buyRun = "run-cd"
    GC.Buy.Show()
    assert.is_nil(bandOf().counts:GetText():find("everything bought", 1, true))
  end)

  it("never offers a craft line to a click or to the Enter key", function()
    showCraftRun(true)
    local parent = rowWithText("craft 4×")
    assert.is_false(parent.action:IsShown())
    -- The row's own hover quotes a buyable line; a craft line is not one, so nothing is asked
    -- and no attempt is opened.
    _G.GameTooltip = { SetOwner = function() end, SetItemByID = function() end,
                       AddLine = function() end, Show = function() end, Hide = function() end }
    parent.scripts.OnEnter(parent)
    assert.is_nil(GC.Buy._attempt)
    -- ...and Enter is still pointing at nothing. Focus is taken INSIDE the hover's `buyable`
    -- guard and before any client gate, so this is the assertion that goes red the moment a
    -- craft line is allowed back into `buyable` -- the one clause standing between a craft row
    -- and the BUY button, the Enter key, the focus advance and the quote.
    assert.is_nil(GC.Buy._focus)
    _G.GameTooltip = nil
  end)

  -- A reagent is not a line of the run, so it is not one of the lines the free tier is holding
  -- back: a locked craft with two reagents under it is ONE more line with Pro, not three. The
  -- reagents carry their parent's lock (Core/BuyRun.lua) purely so they are not offered for
  -- sale under a line nobody can buy.
  it("counts a locked craft line once in the Pro notice, not once per reagent", function()
    GC.AppRuns._set({ { code = "run-lk", name = "Locked craft", updatedAt = 900, origin = "app",
      lines = {
        { i = 101, q = 10 },
        { i = 103, q = 3 },
        { i = 104, q = 20, u = 5800, cr = { r = 900, n = 5, c = 2300, i = {
          { i = 105, q = 5, n = "Echo Leaf", u = 300 },
          { i = 106, q = 5, n = "Foxtail", u = 160 } } } },
      } } })
    GC.db.runSplits = { ["run-lk"] = { [104] = true } }
    GC.db.settings.sniper.buyRun = "run-lk"
    GC.Buy.Show()
    assert.equal("1 more lines with Pro", rowWithText("more lines with Pro").wide:GetText())
  end)

  local function tooltipOn(row)
    local lines = {}
    _G.GameTooltip = {
      SetOwner = function() end, SetItemByID = function() end,
      AddLine = function(_, text, r, g, b) lines[#lines + 1] = { text = text, color = { r, g, b } } end,
      Show = function() end, Hide = function() end,
    }
    row.scripts.OnEnter(row)
    _G.GameTooltip = nil
    return lines
  end

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
    assert.same({ "craft it: 5× Bravo Ore + 5× Charlie Dust = 460c each",
                  "vs 5800c at the auction house · right-click to split" }, texts(lines))
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] },
      lines[1].color)
  end)

  it("greys the comparison when the auction house is cheaper", function()
    GC.AppRuns._set({ { code = "run-x", name = "Craft run", updatedAt = 900, origin = "app",
      lines = { { i = 101, q = 20, u = 300, cr = { r = 900, n = 5, c = 2300, i = {
        { i = 102, q = 5, n = "Bravo Ore", u = 300 } } } } } } })
    GC.db.runSplits = {}
    GC.db.settings.sniper.buyRun = "run-x"
    GC.Buy.Show()
    local lines = tooltipOn(rowWithText("Alpha Herb"))
    assert.equal("vs 300c at the auction house · right-click to split", lines[2].text)
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3] },
      lines[2].color)
  end)

  it("offers the way back on a line that is already split", function()
    showCraftRun(true)
    local lines = tooltipOn(rowWithText("craft 4×"))
    assert.equal("vs 5800c at the auction house · right-click to buy it whole", lines[2].text)
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
    assert.same({ "includes 20 for crafting Alpha Herb" }, texts(lines))
  end)

  it("splits a line from its row menu and puts it back again", function()
    showCraftRun(false)
    local entries
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      entries = {}
      generator(nil, {
        CreateTitle = function(_, text) entries[#entries + 1] = { text = text } end,
        CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
        CreateDivider = function() end,
      })
    end }

    local alpha = rowWithText("Alpha Herb")
    alpha.scripts.OnMouseUp(alpha, "RightButton")
    assert.same({ "Split into reagents (craft 4×)" }, { entries[1].text })
    entries[1].fn()
    assert.is_true(GC.db.runSplits["run-c"][101])
    assert.truthy(rowWithText("craft 4×"))

    local parent = rowWithText("craft 4×")
    parent.scripts.OnMouseUp(parent, "RightButton")
    assert.same({ "Buy it whole instead" }, { entries[1].text })
    entries[1].fn()
    assert.is_nil(GC.db.runSplits["run-c"][101])
    assert.is_nil(rowWithText("craft 4×"))
    _G.MenuUtil = nil
  end)

  it("opens no menu on a left click, on a line with no recipe, or on a reagent", function()
    showCraftRun(true)
    local opened = 0
    _G.MenuUtil = { CreateContextMenu = function() opened = opened + 1 end }
    local parent = rowWithText("craft 4×")
    parent.scripts.OnMouseUp(parent, "LeftButton")
    local ore = rowWithText("Bravo Ore")
    ore.scripts.OnMouseUp(ore, "RightButton")
    assert.equal(0, opened)
    _G.MenuUtil = nil
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
    assert.equal("0", alpha.cells.buy:GetText())
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
end)
