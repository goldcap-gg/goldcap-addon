local helper = require("spec.spec_helper")

local function read(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

describe("WoW: Forever scan wiring", function()
  local GC, printed, timers, replicated, saved

  local function load(interface)
    saved = { GetBuildInfo = _G.GetBuildInfo, GetCurrentRegion = _G.GetCurrentRegion,
      GetRealmName = _G.GetRealmName, UnitFactionGroup = _G.UnitFactionGroup,
      C_AuctionHouse = _G.C_AuctionHouse, C_Timer = _G.C_Timer }
    printed, timers, replicated = {}, {}, 0
    _G.GetBuildInfo = function() return "1.60.1", "70009", "Sep 2026", interface end
    _G.GetCurrentRegion = function() return 90 end
    _G.GetRealmName = function() return "Forever" end
    _G.UnitFactionGroup = function() return "Horde" end
    _G.C_AuctionHouse = {
      ReplicateItems = function() replicated = replicated + 1 end,
      GetNumReplicateItems = function() return 0 end,
    }
    _G.C_Timer = { After = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    GC.Print = function(msg) printed[#printed + 1] = msg end
  end

  after_each(function()
    for k, v in pairs(saved or {}) do _G[k] = v end
    _G.GoldCap_AppData = nil
  end)

  it("with the real client driver: asks on open in Forever and says so", function()
    load(16001)
    local db = {}
    assert.is_true(GC.ForeverScan.Init(db))
    GC.ForeverScan.OnAuctionHouseShow()
    assert.equal(1, replicated)
    assert.equal("Scanning the auction house…", printed[1])
    assert.is_nil(db.foreverScan.fold)
    assert.is_number(db.foreverScan.requestedAt)
  end)

  it("on retail: no scan, no key in the save", function()
    load(120100)
    local db = {}
    assert.is_false(GC.ForeverScan.Init(db))
    GC.ForeverScan.OnAuctionHouseShow()
    assert.equal(0, replicated)
    assert.is_nil(db.foreverScan)
  end)

  it("words the result by what was read and whether the Companion shares it", function()
    load(16001)
    GC.ForeverScan._SayDone({ rows = 8412, items = 900, replicated = true }, true)
    GC.ForeverScan._SayDone({ rows = 8412, items = 900, replicated = true }, false)
    GC.ForeverScan._SayDone({ items = 300, replicated = false }, true)
    GC.ForeverScan._SayDone({ items = 300, replicated = false }, false)
    GC.ForeverScan._SayDone(nil, false)
    assert.equal("8412 lots scanned -- shared on your next /reload", printed[1])
    assert.equal("8412 lots scanned and saved", printed[2])
    assert.equal("300 items scanned -- shared on your next /reload", printed[3])
    assert.equal("300 items scanned and saved", printed[4])
    assert.equal("The scan found nothing to save", printed[5])
  end)

  describe("source wiring", function()
    local init, sniper, sell
    before_each(function()
      init = read("GoldCap/Core/Init.lua")
      sniper = read("GoldCap/UI/SniperFrame.lua")
      sell = read("GoldCap/UI/SellFrame.lua")
    end)

    it("registers the dump event and the scan command only inside a Forever gate", function()
      local reg = init:find('RegisterEvent%("REPLICATE_ITEM_LIST_UPDATE"%)')
      assert.truthy(reg)
      assert.truthy(init:sub(reg - 300, reg):find("IsForever", 1, true))
      local slash = init:find("GC.slashHandlers.scan", 1, true)
      assert.truthy(slash)
      assert.truthy(init:sub(slash - 300, slash):find("IsForever", 1, true))
    end)

    it("routes the dump event, the auction house's open and close, and the load", function()
      assert.truthy(init:find('event == "REPLICATE_ITEM_LIST_UPDATE"', 1, true))
      assert.truthy(init:find("GC.ForeverScan.OnReplicateUpdate()", 1, true))
      local show = init:find("GC.Sniper.OnAuctionHouseShow()", 1, true)
      assert.truthy(init:find("GC.ForeverScan.OnAuctionHouseShow()", show, true))
      local _, closes = init:gsub("GC%.ForeverScan%.OnAuctionHouseClosed%(%)", "")
      assert.equal(2, closes)
      assert.truthy(init:find("GC.ForeverScan.Init(GC.db)", 1, true))
    end)

    it("folds a finished browse pass and lets SCAN start the Forever scan", function()
      assert.truthy(sniper:find("GC.ForeverScan.OnBrowsePassDone(GC.Sniper._bookPass:Book())", 1, true))
      assert.truthy(sniper:find('GC.ForeverScan.Request("button")', 1, true))
      assert.truthy(sniper:find("function GC.Sniper.StartBrowsePass(kind)", 1, true))
    end)

    it("keeps scan work out of the Sell tab entirely", function()
      for _, word in ipairs({ "ForeverScan.Request", "OnReplicateUpdate", "StartBrowsePass", "ReplicateItems" }) do
        assert.is_nil(sell:find(word, 1, true), word)
      end
    end)
  end)
end)
