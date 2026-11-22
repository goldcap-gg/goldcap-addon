local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/SniperBlackwater_Camelot.lua: WoW: Forever's BLACKWATER board on DEALS (ClickUp 1an60dzy5r4).
-- The real Theme and kit, the real flip rule (Core/ForeverFlips.lua) and the real BUY lists
-- (Core/AppRuns.lua); the window's chips, rows and headings are frames built here the way
-- UI/SniperFrame.lua builds them, and GC.Sniper's board functions are doubles that remember what
-- they were asked. The payload is real rows of the 2026-11-22 16:25 UTC snapshot (117 against 111).
describe("Blackwater board", function()
  local GC, BW, restore, saved, payload, views, selected, boards, held, host
  local KEYS = { "C_Item", "C_Timer", "GameTooltip", "ITEM_QUALITY_COLORS", "time", "date" }
  local NOW = 1795371960
  local AT = 1795371900
  local ELIXIR, FISHPOLE, WRAPS = 13493, 6367, 9433

  local function plain(text) return helper.plain(text) end
  local function textOf(fs) return plain(W.state(fs).text or "") end
  local function shown(widget) return W.state(widget).shown and true or false end
  local function press(widget) W.state(widget).scripts.OnClick(widget, "LeftButton", false) end
  local function ui() return BW._ui end
  local function rowsShown()
    local out = {}
    for _, row in ipairs(ui().rows) do
      if shown(row) then out[#out + 1] = row.itemID end
    end
    return out
  end
  local function run() return GC.ForeverScan.Prefs().blackwaterList and GC.AppRuns.Get(GC.ForeverScan.Prefs().blackwaterList) end
  local function linesOf()
    local out = {}
    for _, line in ipairs(run().lines) do out[#out + 1] = { i = line.i, q = line.q, h = line.h } end
    return out
  end

  local function aPayload()
    return { blackwater = { at = AT, items = {
      [ELIXIR] = { bw = 500000, bwQty = 1, home = 1300000, homeQty = 10 },
      [WRAPS] = { bw = 25000, bwQty = 1, home = 90000, homeQty = 6 },
      [FISHPOLE] = { bw = 99998, bwQty = 4, home = 140000, homeQty = 33 },
      [1] = { bw = 80000, bwQty = 1, home = 90000, homeQty = 6 }, -- not a flip
    } } }
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    _G.C_Timer = { After = function() end }
    _G.time = function() return NOW end
    _G.date = os.date
    _G.C_Item = {
      GetItemIconByID = function(id) return 100000 + id end,
      GetItemNameByID = function(id) return ({ [ELIXIR] = "Recipe: Greater Arcane Elixir", [WRAPS] = "Forgotten Wraps",
        [FISHPOLE] = "Big Iron Fishing Pole" })[id] end,
      GetItemQualityByID = function() return 2 end,
    }
    _G.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0, hex = "|cff1eff00" } }
    _G.GameTooltip = { SetOwner = function() end, SetText = function() end, SetItemByID = function() end,
      Show = function() end, Hide = function() end }

    GC = helper.loadModule("UI/Theme.lua", {})
    GC.db = { runs = {} }
    helper.loadModule("Core/AppRuns.lua", GC)
    helper.loadModule("Core/ForeverFlips.lua", GC)
    payload = aPayload()
    GC.Data = { ForeverPayload = function() return payload end }
    local prefs = {}
    GC.ForeverScan = { Prefs = function() return prefs end }
    views, boards, held = {}, {}, {}
    GC.Buy = {
      _SetLineCap = function(code, itemID, copper)
        GC.db.runLineCaps = GC.db.runLineCaps or {}
        GC.db.runLineCaps[code] = GC.db.runLineCaps[code] or {}
        GC.db.runLineCaps[code][itemID] = copper
      end,
      SelectRun = function(code) selected = code end,
      HaveOf = function(itemID) return held[itemID] or 0 end,
    }
    -- The window's chips, as UI/SniperFrame.lua's createFrame leaves them.
    host = CreateFrame("Frame")
    host:SetSize(720, 540)
    host.boardChips = {}
    for _, id in ipairs({ "commodities", "items" }) do
      local chip = GC.Theme.Button(host, "ghost", "plaque")
      chip:SetSize(id == "commodities" and 132 or 96, 22)
      host.boardChips[id] = chip
    end
    host.scroll = CreateFrame("ScrollFrame", nil, host)
    host.headerRow = CreateFrame("Frame", nil, host)
    host.dealsChrome = { host.boardChips.commodities, host.boardChips.items }
    local board = "commodities"
    GC.Sniper = {
      ShowView = function(v) views[#views + 1] = v end,
      _SetBoard = function(id) boards[#boards + 1] = id; board = id end,
      _PaintBoardChips = function(target)
        for id, chip in pairs((target or host).boardChips) do chip:SetVariant(board == id and "active" or "ghost") end
      end,
      _LayoutBoardRow = function() end,
    }
    helper.loadModule("UI/SniperBlackwater_Camelot.lua", GC)
    BW = GC.Blackwater
    BW.Attach(host, { panelLeft = 20, panelRightInset = 20, top = -120, bottom = 12 })
    -- Which way each chip was last painted (the kit's button keeps it in its own upvalues).
    for _, chip in pairs(host.boardChips) do
      local set = chip.SetVariant
      function chip.SetVariant(self, name) self.variant = name; return set(self, name) end
    end
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  it("adds a third chip after ITEMS that counts the flips worth a line", function()
    local chip = host.boardChips.blackwater
    assert.is_truthy(chip)
    assert.equal("BLACKWATER 3", plain(chip.label))
    assert.same({ "LEFT", host.boardChips.items, "RIGHT" }, { W.state(chip).points[1][1], W.state(chip).points[1][2],
      W.state(chip).points[1][3] })
    -- setView shows and hides it with the rest of the Deals chrome.
    assert.equal(chip, host.dealsChrome[#host.dealsChrome])
  end)

  it("puts its own board over the rows while it is chosen, the best flip first", function()
    press(host.boardChips.blackwater)
    assert.is_true(BW.Active())
    assert.is_true(shown(ui().container))
    assert.is_false(shown(host.scroll))
    assert.is_false(shown(host.headerRow))
    assert.same({ ELIXIR, WRAPS, FISHPOLE }, rowsShown())
    -- One of each: 735000 + 60500 + 33002 after the cut, for 500000 + 25000 + 99998.
    assert.equal(plain("+" .. GC.Util.Money(828502)), textOf(ui().banner.big))
    local elixir = ui().rows[1]
    assert.equal(plain("+" .. GC.Util.Money(735000)), textOf(elixir.make))
    assert.equal(plain(GC.Util.Money(500000)), textOf(elixir.bw))
    assert.equal(plain(GC.Util.Money(1300000)), textOf(elixir.home))
    assert.equal("+147%", textOf(elixir.pct))
    assert.equal("1 cheap at Blackwater · 10 listed at home", textOf(elixir.sub))
    -- The other chips go dark under it, and come back as they were when it is let go.
    assert.equal("active", host.boardChips.blackwater.variant)
    assert.equal("ghost", host.boardChips.commodities.variant)
  end)

  it("gives the board back to COMMODITIES or ITEMS when one of them is chosen", function()
    press(host.boardChips.blackwater)
    GC.Sniper._SetBoard("items")
    assert.same({ "items" }, boards)
    assert.is_false(BW.Active())
    assert.is_false(shown(ui().container))
    assert.is_true(shown(host.scroll))
    assert.is_true(shown(host.headerRow))
  end)

  it("follows the rail: gone on SELL, back on DEALS while it is still chosen", function()
    press(host.boardChips.blackwater)
    BW.OnView("sell")
    assert.is_false(shown(ui().container))
    BW.OnView("deals")
    assert.is_true(shown(ui().container))
    assert.is_false(shown(host.scroll))
  end)

  it("counts only the checked rows in the dock and on the button", function()
    press(host.boardChips.blackwater)
    assert.equal("ADD 3 TO BUY", plain(ui().dock.button.label))
    press(ui().rows[2].take)
    assert.equal("ADD 2 TO BUY", plain(ui().dock.button.label))
    assert.equal("2 checked, one of each", textOf(ui().dock.title))
    assert.is_false(shown(ui().rows[2].take.fill))
    assert.same({ GC.Theme.IconCoords("plus") }, W.state(ui().rows[2].take.mark).texCoord)
    assert.same({ GC.Theme.IconCoords("check") }, W.state(ui().rows[1].take.mark).texCoord)
  end)

  it("writes the checked rows to BUY as one list, a unit each, capped where the flip ends", function()
    press(host.boardChips.blackwater)
    press(ui().rows[3].take)
    held[ELIXIR] = 2
    press(ui().dock.button)
    assert.equal("Blackwater flips", run().name)
    -- One more than the bags hold: a recipe already carried home is not this trip's.
    assert.same({ { i = ELIXIR, q = 1, h = 2 }, { i = WRAPS, q = 1, h = 0 } }, linesOf())
    assert.same({ [ELIXIR] = 1073913, [WRAPS] = GC.ForeverFlips.Cap(90000) }, GC.db.runLineCaps[run().code])
    assert.equal(run().code, selected)
    assert.same({ "buy" }, views)
  end)

  it("buys one more of each on the next press, whatever the last trip bought on the list", function()
    press(host.boardChips.blackwater)
    press(ui().dock.button)
    local code = run().code
    GC.db.buyProgress = { ["Me-"] = { [code] = { [ELIXIR] = { bought = 1, spent = 500000 } } } }
    held[ELIXIR] = 1
    press(ui().dock.button)
    assert.equal(code, run().code)
    assert.is_nil(GC.db.buyProgress["Me-"][code][ELIXIR])
    assert.same({ i = ELIXIR, q = 1, h = 1 }, linesOf()[1])
  end)

  it("says so when goldcap.gg sent no Blackwater prices, or nothing is a flip", function()
    payload = { items = {} }
    press(host.boardChips.blackwater)
    assert.equal("BLACKWATER", plain(host.boardChips.blackwater.label))
    assert.is_true(shown(ui().empty))
    assert.equal("No Blackwater prices yet. goldcap.gg sends them with the Companion's next sync.", textOf(ui().empty))
    assert.is_false(shown(ui().dock))
    payload = { blackwater = { at = AT, items = { [1] = { bw = 80000, bwQty = 1, home = 90000, homeQty = 6 } } } }
    _G.time = function() return NOW + 60 end
    BW.Paint()
    assert.equal("Nothing at Blackwater is 1g or more cheaper than at home right now.", textOf(ui().empty))
  end)

  it("shows the coin where the client has no goblin icon", function()
    assert.equal("Interface\\Icons\\Achievement_Goblinhead", W.state(ui().banner.goblin).file)
    W.missingTextures["Interface\\Icons\\Achievement_Goblinhead"] = true
    restore()
    restore = W.install()
    W.missingTextures["Interface\\Icons\\Achievement_Goblinhead"] = true
    local again = CreateFrame("Frame")
    again.boardChips = { items = GC.Theme.Button(again, "ghost", "plaque") }
    again.scroll, again.headerRow, again.dealsChrome = CreateFrame("Frame", nil, again), CreateFrame("Frame", nil, again), {}
    helper.loadModule("UI/SniperBlackwater_Camelot.lua", GC)
    GC.Blackwater.Attach(again, { panelLeft = 20, panelRightInset = 20, top = -120, bottom = 12 })
    assert.equal("Interface\\Icons\\INV_Misc_Coin_01", W.state(GC.Blackwater._ui.banner.goblin).file)
    W.missingTextures["Interface\\Icons\\Achievement_Goblinhead"] = nil
  end)

  it("says how old the prices are once they are stale", function()
    _G.time = function() return AT + 4 * 3600 end
    press(host.boardChips.blackwater)
    assert.truthy(textOf(ui().dock.note):find("These prices are", 1, true))
  end)
end)
