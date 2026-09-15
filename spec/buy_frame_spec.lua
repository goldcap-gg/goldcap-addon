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
      List = function() return runs end,
      Get = function(code)
        for _, r in ipairs(runs) do if r.code == code then return r end end
      end,
      FreeLines = function() return 2 end,
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

  -- At rest -- nothing quoted yet -- the button names the quantity and nothing else. What a
  -- click does from there, and what the label becomes, is spec/buy_purchase_spec.lua's.
  it("offers a BUY button for the quantity still missing", function()
    local alpha = rowWithText("Alpha Herb")
    assert.truthy(alpha.action:IsShown())
    assert.equal("BUY 10", alpha.action.label)
    assert.is_true(alpha.action:IsEnabled())
  end)

  it("puts the vendor line last, marks it, and greys it", function()
    local shown = shownRows()
    -- The last list row is the locked-lines notice; the vendor line is the last LINE row.
    local lineRows = {}
    for _, row in ipairs(shown) do
      if (row.reagent:GetText() or "") ~= "" then lineRows[#lineRows + 1] = row end
    end
    assert.equal(4, #lineRows)
    local last = lineRows[#lineRows]
    assert.equal("Delta Vial", last.reagent:GetText())
    assert.equal("vendor", last.cells.action:GetText())
    assert.is_false(last.action:IsShown())
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3], 1 },
      last.reagent.colorValue)
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
    assert.equal("in bags", band.bags:GetText())
  end)

  it("names the run on the picker and cycles to the next one, remembering the choice", function()
    GC.AppRuns._set({ run(), run({ code = "run-2", name = "Potion run" }) })
    GC.Buy.SelectRun("run-1")
    local band = bandOf()
    assert.equal("Flask run", band.picker.label)

    band.picker.scripts.OnClick(band.picker)
    assert.equal("Potion run", band.picker.label)
    assert.equal("run-2", GC.db.settings.sniper.buyRun)
    assert.equal("run-2", GC.Buy.CurrentRun():Code())

    -- ...and wraps back around to the first.
    band.picker.scripts.OnClick(band.picker)
    assert.equal("run-1", GC.db.settings.sniper.buyRun)
  end)

  it("reopens on the remembered run rather than the newest one", function()
    GC.AppRuns._set({ run({ code = "run-2", name = "Potion run" }), run() })
    GC.db.settings.sniper.buyRun = "run-1"
    GC.Buy.Show()
    assert.equal("run-1", GC.Buy.CurrentRun():Code())
    assert.equal("Flask run", bandOf().picker.label)
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
end)
