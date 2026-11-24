local helper = require("spec.spec_helper")

-- The lowest item quality DEALS finds under the market (settings.sniper.lowestQuality, Common by
-- default). One decision, GC.DealMath.QualityAdmits, for every discovery path; the quality is read
-- without a request of any kind (GC.ForeverValue.CachedQuality), and unknown passes.
describe("the lowest item quality", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
  end)

  after_each(function() _G.C_Item = nil end)

  describe("GC.DealMath.QualityFloor", function()
    local CASES = {
      { nil, 1 }, { 0, 0 }, { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 },
      { 5, 1 }, { -1, 1 }, { 1.5, 1 }, { "2", 1 },
    }
    for _, case in ipairs(CASES) do
      it(("reads %s as %d"):format(tostring(case[1]), case[2]), function()
        assert.equal(case[2], GC.DealMath.QualityFloor({ lowestQuality = case[1] }))
      end)
    end
    it("is Common with no settings at all", function()
      assert.equal(1, GC.DealMath.QualityFloor(nil))
    end)
  end)

  describe("GC.DealMath.QualityAdmits", function()
    local ID = 4242
    -- quality the client gave (nil: unknown) x the setting x the row: each row is
    -- { quality, setting, row kind, expected for a plain row }; a cap, a followed group and a pin
    -- are always admitted, and so is a vendor row.
    local CASES = {
      { nil, 0, true }, { nil, 1, true }, { nil, 4, true },
      { 0, 0, true }, { 0, 1, false }, { 0, 2, false },
      { 1, 0, true }, { 1, 1, true }, { 1, 2, false },
      { 2, 1, true }, { 2, 2, true }, { 2, 3, false },
      { 3, 3, true }, { 3, 4, false },
      { 4, 4, true }, { 5, 4, true },
    }
    local ROWS = {
      { name = "a plain market row", deal = function() return { itemID = ID, forever = "market" } end, pins = {}, plain = true },
      { name = "a vendor row", deal = function() return { itemID = ID, forever = "vendor" } end, pins = {} },
      { name = "a cap", deal = function() return { itemID = ID, cap = 100 } end, pins = {} },
      { name = "a followed group's cap", deal = function() return { itemID = ID, capFollowed = true } end, pins = {} },
      { name = "a followed group's row", deal = function() return { itemID = ID, refSource = "group" } end, pins = {} },
      { name = "a pinned item", deal = function() return { itemID = ID } end, pins = { 7, ID } },
    }
    for _, row in ipairs(ROWS) do
      for _, case in ipairs(CASES) do
        local quality, setting, plain = case[1], case[2], case[3]
        local want = (not row.plain) or plain
        it(("%s of quality %s at setting %d: %s"):format(row.name, tostring(quality), setting,
            want and "admitted" or "left out"), function()
          assert.equal(want, GC.DealMath.QualityAdmits(row.deal(), quality,
            { lowestQuality = setting, watchPins = row.pins }))
        end)
      end
    end
  end)

  describe("GC.ForeverValue.CachedQuality", function()
    local calls
    local function client(cached, quality)
      calls = {}
      _G.C_Item = {
        IsItemDataCachedByID = function(id) calls[#calls + 1] = "cached:" .. id; return cached end,
        GetItemQualityByID = function(id) calls[#calls + 1] = "quality:" .. id; return quality end,
        RequestLoadItemDataByID = function(id) calls[#calls + 1] = "request:" .. id end,
        GetItemInfo = function(id) calls[#calls + 1] = "info:" .. id end,
      }
    end

    it("reads the kept answer first and asks the client nothing", function()
      client(true, 4)
      GC.db = { foreverItemInfo = { [5] = 120 * 8 + 0 } }
      assert.equal(0, GC.ForeverValue.CachedQuality(5))
      assert.same({}, calls)
    end)

    it("reads the client's own only while it already holds the item, and never requests it", function()
      GC.db = {}
      client(true, 3)
      assert.equal(3, GC.ForeverValue.CachedQuality(9))
      client(false, 3)
      assert.is_nil(GC.ForeverValue.CachedQuality(9))
      assert.same({ "cached:9" }, calls)
    end)

    it("writes nothing to the saved data", function()
      GC.db = {}
      client(true, 2)
      GC.ForeverValue.CachedQuality(9)
      assert.same({}, GC.db)
    end)

    it("is nil on a client without the calls", function()
      GC.db = {}
      _G.C_Item = {}
      assert.is_nil(GC.ForeverValue.CachedQuality(9))
    end)
  end)

  describe("the browse pass (GC.FullScan.Evaluate)", function()
    local cfg = { watchDiscount = 0.10, suspectDiscount = 0.90, hotDiscount = 0.40, hotProfit = 5000000,
      goodDiscount = 0.25, goodProfit = 1000000 }
    local quality = {}
    local function getValue() return { mv = 1000000 } end
    local rows = { { itemID = 10, count = 1, buyoutStack = 500000 }, { itemID = 20, count = 1, buyoutStack = 500000 },
      { itemID = 30, count = 1, buyoutStack = 500000 } }

    before_each(function()
      GC.db = {}
      quality = { [10] = 0, [20] = 1 } -- 30: not loaded
      _G.C_Item = {
        IsItemDataCachedByID = function(id) return quality[id] ~= nil end,
        GetItemQualityByID = function(id) return quality[id] end,
      }
    end)

    local function ids(deals)
      local out = {}
      for _, d in ipairs(deals) do out[#out + 1] = d.itemID end
      table.sort(out)
      return out
    end

    it("counts a grey row with the screened ones and boards the rest, unknown included", function()
      local deals, screened = GC.FullScan.Evaluate(rows, getValue, cfg, 100)
      assert.same({ 20, 30 }, ids(deals))
      assert.equal(1, screened)
    end)

    it("boards a pinned grey item, and every row at Poor", function()
      cfg.watchPins = { 10 }
      assert.same({ 10, 20, 30 }, ids(GC.FullScan.Evaluate(rows, getValue, cfg, 100)))
      cfg.watchPins = nil
      cfg.lowestQuality = 0
      assert.same({ 10, 20, 30 }, ids(GC.FullScan.Evaluate(rows, getValue, cfg, 100)))
      cfg.lowestQuality = 2
      local deals, screened = GC.FullScan.Evaluate(rows, getValue, cfg, 100)
      assert.same({ 30 }, ids(deals))
      assert.equal(2, screened)
      cfg.lowestQuality = nil
    end)
  end)
end)
