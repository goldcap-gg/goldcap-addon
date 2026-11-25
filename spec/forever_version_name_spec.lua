local helper = require("spec.spec_helper")

-- WoW: Forever: an "Under market" gear row is priced for one version of the piece (its `version`,
-- the bonus key of the lots it was measured against), and the board named it for the bare item.
-- An Aboriginal Sash row at 3s50 against a 49s median did not say which of the nine versions on the
-- browse, 3s50 to 99s99, it meant (owner, 2026-11-25). The row, the Check's header, the tooltip and
-- a shift-click now name and show that version.
describe("Forever Deals: a row priced for one version names that version", function()
  local SASH = 9859
  local NAMES = {
    ["item:9859"] = "Aboriginal Sash",
    ["item:9859::::::::::::1:12729"] = "Aboriginal Sash of Shadow Wrath",
    ["item:9859::::::::::::2:12729:12800"] = "Aboriginal Sash of Shadow Wrath",
    ["item:9859::::::::::::1:12722"] = "Aboriginal Sash of the Owl",
  }
  local answered -- item strings the client has answered for (all of NAMES unless a spec says not)

  local function linkOf(str) return "|cff1eff00|H" .. str .. "|h[" .. NAMES[str] .. "]|h|r" end

  local function loadSniper(forever)
    answered = {}
    for str in pairs(NAMES) do answered[str] = true end
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 0 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function(_, itemID)
      return {
        ContinueOnItemLoad = function(_, fn) fn() end,
        GetItemIcon = function() return 135000 + itemID end,
        GetItemQuality = function() return nil end,
        GetItemName = function() return NAMES["item:" .. itemID] end,
      }
    end }
    _G.C_Item = { GetItemInfo = function(what)
      local str = type(what) == "number" and ("item:" .. what) or what
      if not (NAMES[str] and answered[str]) then return nil end
      return NAMES[str], linkOf(str)
    end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Enum = { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 },
      AuctionHouseSortOrder = { Buyout = 4, Price = 0, Name = 1 } }
    _G.C_AuctionHouse = { IsThrottledMessageSystemReady = function() return true end }

    local GC = { db = { commodityByItem = {}, settings = { sniper = { watchPins = {} } } } }
    for _, m in ipairs({ "Core/Book.lua", "Core/SniperDecision.lua", "Core/DealMath.lua", "Core/Trigger.lua",
      "Core/FullScan.lua", "Core/BookPass.lua", "Core/DrillQueue.lua", "Core/KeyPoll.lua", "Core/WatchSet.lua",
      "Core/AutoScan.lua", "Core/Caps.lua", "Core/ForeverGear.lua" }) do
      helper.loadModule(m, GC)
    end
    GC.Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
      tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
      color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
        fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
        gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } },
      ItemTooltipOutside = function() end }
    GC.Data = {
      GetItemValue = function() return nil end,
      GetWatchlist = function() return {} end,
      TargetIds = function() return {} end,
    }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    if forever then helper.loadModule("UI/SniperFrame_Camelot.lua", GC) end
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.C_Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum = nil, nil
  end)

  -- The name and icon a board row's item cell is stamped with (GC.Sniper._StampItem).
  local function stamped(GC, deal)
    local row = { deal = deal, icon = { SetTexture = function(self, t) self.texture = t end } }
    local named
    GC.Sniper._StampItem(row, deal, function(n) named = n end)
    return named, row.icon.texture
  end

  local function marketRow(version)
    return { itemID = SASH, unitPrice = 350, qty = 1, forever = "market", item = true, version = version }
  end

  it("reads a version as the HERO tab does, and the bare item for none", function()
    local GC = loadSniper(true)
    assert.equal("item:9859::::::::::::1:12729", GC.Sniper._DealItemString(marketRow("12729")))
    assert.equal("item:9859::::::::::::2:12729:12800", GC.Sniper._DealItemString(marketRow("12729.12800")))
    for _, none in ipairs({ "0", "", "abc", 12729 }) do
      assert.is_nil(GC.Sniper._DealItemString(marketRow(none)), tostring(none))
    end
    assert.is_nil(GC.Sniper._DealItemString(marketRow(nil)))
    assert.is_nil(GC.Sniper._DealItemString(nil))
  end)

  it("names a row for its version, and each version of one item for its own", function()
    local GC = loadSniper(true)
    assert.equal("Aboriginal Sash of Shadow Wrath", (stamped(GC, marketRow("12729"))))
    assert.equal("Aboriginal Sash of the Owl", (stamped(GC, marketRow("12722"))))
    -- Again, from what the first stamps kept: still each its own.
    assert.equal("Aboriginal Sash of Shadow Wrath", (stamped(GC, marketRow("12729"))))
    assert.equal("Aboriginal Sash of the Owl", (stamped(GC, marketRow("12722"))))
    -- A row of the whole item (a vendor row) keeps the item's name, and the item's icon throughout.
    local name, icon = stamped(GC, { itemID = SASH, unitPrice = 300, qty = 1, forever = "vendor" })
    assert.equal("Aboriginal Sash", name)
    assert.equal(135000 + SASH, icon)
  end)

  it("shows the item's name until the client answers for the version, then the version's", function()
    local GC = loadSniper(true)
    answered["item:9859::::::::::::1:12729"] = nil
    local deal = marketRow("12729")
    assert.equal("Aboriginal Sash", (stamped(GC, deal)))
    assert.is_nil((GC.Sniper._DealVersion(deal))) -- the row's signature: drawn again once this moves
    answered["item:9859::::::::::::1:12729"] = true
    assert.equal("Aboriginal Sash of Shadow Wrath", (GC.Sniper._DealVersion(deal)))
    assert.equal("Aboriginal Sash of Shadow Wrath", (stamped(GC, deal)))
  end)

  it("links and shows the version a row is priced for", function()
    local GC = loadSniper(true)
    local deal = marketRow("12729")
    local versionLink = linkOf("item:9859::::::::::::1:12729")
    assert.equal(versionLink, GC.Sniper._RowItemLink(SASH, deal))
    assert.equal(linkOf("item:9859"), GC.Sniper._RowItemLink(SASH, marketRow(nil)))
    assert.equal(linkOf("item:9859"), GC.Sniper._RowItemLink(SASH))

    local calls = {}
    local saved = { _G.GameTooltip, _G.GameTooltip_SuppressAutomaticCompareItem }
    finally(function() _G.GameTooltip, _G.GameTooltip_SuppressAutomaticCompareItem = saved[1], saved[2] end)
    _G.GameTooltip = {
      SetItemByID = function(_, id) calls[#calls + 1] = "item " .. id end,
      SetHyperlink = function(_, link) calls[#calls + 1] = "link " .. link end,
    }
    GC.Sniper._ShowItemTooltip({}, SASH, nil, select(2, GC.Sniper._DealVersion(deal)))
    GC.Sniper._ShowItemTooltip({}, SASH, nil, select(2, GC.Sniper._DealVersion(marketRow(nil))))
    assert.same({ "link " .. versionLink, "item " .. SASH }, calls)
  end)

  it("on retail names every row for its item, as before", function()
    local GC = loadSniper(false)
    local deal = marketRow("12729")
    assert.is_nil(GC.Sniper._DealItemString(deal))
    assert.is_nil(GC.Sniper._DealVersion(deal))
    assert.equal("Aboriginal Sash", (stamped(GC, deal)))
    assert.equal(linkOf("item:9859"), GC.Sniper._RowItemLink(SASH, deal))
  end)

  -- The board skips a row whose signature has not moved; the version's name is in it, so another
  -- version at the same price, or the name arriving late, draws the row again.
  it("puts the version's name in a board row's signature", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    local sigAt = assert(text:find("local sig = table.concat({", 1, true))
    local sigEnd = assert(text:find('}, "|")', sigAt, true))
    assert.truthy(text:sub(sigAt, sigEnd):find("tostring((GC.Sniper._DealVersion(deal)))", 1, true))
  end)
end)
