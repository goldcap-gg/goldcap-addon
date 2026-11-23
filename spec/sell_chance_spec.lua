local helper = require("spec.spec_helper")

-- How often one listing of an item sells: goldcap.gg's P section, in the retail region payload
-- (GCM1) and in WoW: Forever's market payload (GCF1), `itemId=pct`, a whole percent 0..100. An item
-- P leaves out had too few listings end to say, and nothing may show it as 0%.
describe("the sell chance", function()
  local GC
  local REGION = "GCM1;eu;2000;I:190396=123000=50.0,2589=500"
  local FOREVER = "GCF1;s;90;R;Horde;2000;I:2589=68=70=69=79=7000=2=0,2592=255=269===2029=1=20"
  local BAD = "P:2589=42,x=5,7=,=9,0=50,8=101,9=4.5,10=-1,11=12=13,12=7a,2592=100,9000=0"

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC)
  end)

  describe("in the region payload (GCM1)", function()
    it("reads every token into an id-to-percent map", function()
      local p = assert(GC.ImportString.ParseRegion(REGION .. ";P:2589=42,2592=100,9000=0"))
      assert.same({ [2589] = 42, [2592] = 100, [9000] = 0 }, p.sellChance)
      assert.equal(123000, p.items[190396].m)
    end)

    it("drops a bad token alone and keeps the rest of the payload", function()
      local p = assert(GC.ImportString.ParseRegion(REGION .. ";" .. BAD .. ";M:201234=990000=4"))
      assert.same({ [2589] = 42, [2592] = 100, [9000] = 0 }, p.sellChance)
      assert.equal(2, p.counts.items)
      assert.equal(990000, p.refs[201234])
    end)

    it("has no table without the section, and an empty one fails nothing", function()
      assert.is_nil(assert(GC.ImportString.ParseRegion(REGION)).sellChance)
      assert.is_nil(assert(GC.ImportString.ParseRegion(REGION .. ";P:")).sellChance)
      assert.same({}, assert(GC.ImportString.ParseRegion(REGION .. ";P:oops")).sellChance)
    end)
  end)

  describe("in the WoW: Forever payload (GCF1)", function()
    it("reads every token into an id-to-percent map", function()
      local p = assert(GC.ImportString.ParseForever(FOREVER .. ";H:72;P:2589=42,2592=100,9000=0"))
      assert.same({ [2589] = 42, [2592] = 100, [9000] = 0 }, p.sellChance)
      assert.equal(72, p.salesHours)
      assert.equal(2, p.count)
    end)

    it("drops a bad token alone and keeps the rest of the payload", function()
      local p = assert(GC.ImportString.ParseForever(FOREVER .. ";" .. BAD))
      assert.same({ [2589] = 42, [2592] = 100, [9000] = 0 }, p.sellChance)
      assert.equal(2, p.count)
    end)

    it("has no table without the section", function()
      assert.is_nil(assert(GC.ImportString.ParseForever(FOREVER)).sellChance)
    end)
  end)

  describe("GC.Data.SellChance", function()
    local function load()
      _G.GetCVar = function(k) if k == "portal" then return "EU" end end
      helper.loadModule("Core/Data.lua", GC)
      GC.db = { settings = {} }
      GC.Data.Init(GC.db)
    end

    after_each(function() _G.GetCVar = nil end)

    it("answers from the region payload, 0 included, and nil for an item P leaves out", function()
      load()
      assert.is_truthy(GC.Data.AdoptRegionPayload(REGION .. ";P:2589=42,9000=0"))
      assert.equal(42, GC.Data.SellChance(2589))
      assert.equal(0, GC.Data.SellChance(9000))
      assert.is_nil(GC.Data.SellChance(190396))
    end)

    it("answers from WoW: Forever's payload", function()
      load()
      assert.is_truthy(GC.Data.AdoptForeverPayload(FOREVER .. ";P:2592=0,2589=71",
        { region = 90, realm = "R", faction = "Horde" }))
      assert.equal(71, GC.Data.SellChance(2589))
      assert.equal(0, GC.Data.SellChance(2592))
      assert.is_nil(GC.Data.SellChance(5))
    end)

    it("is nil with no payload, or one without the section", function()
      load()
      assert.is_nil(GC.Data.SellChance(2589))
      assert.is_truthy(GC.Data.AdoptRegionPayload(REGION))
      assert.is_nil(GC.Data.SellChance(2589))
    end)
  end)

  describe("in words", function()
    it("is shown at every whole percent from 0 to 100", function()
      assert.equal("Sells from 0% of listings", GC.Util.SellChanceText(0))
      assert.equal("Sells from 42% of listings", GC.Util.SellChanceText(42))
      assert.equal("Sells from 100% of listings", GC.Util.SellChanceText(100))
      assert.equal("0% of listings sell", GC.Util.SellChanceText(0, true))
      assert.equal("42% of listings sell", GC.Util.SellChanceText(42, true))
    end)

    it("is hidden when the figure is missing or not a whole percent", function()
      for _, pct in ipairs({ -1, 101, 42.5, 0 / 0, math.huge }) do
        assert.is_nil(GC.Util.SellChanceText(pct), tostring(pct))
        assert.is_nil(GC.Util.SellChanceText(pct, true), tostring(pct))
      end
      assert.is_nil(GC.Util.SellChanceText(nil))
      assert.is_nil(GC.Util.SellChanceText("42"))
    end)
  end)

  describe("in the tooltip", function()
    local function texts(lines)
      local out = {}
      for _, ln in ipairs(lines or {}) do out[#out + 1] = ln.left or ln.label or ln.text end
      return out
    end

    before_each(function()
      helper.loadModule("Core/Trigger.lua", GC)
      helper.loadModule("UI/Tooltip.lua", GC)
    end)

    it("follows the sales a day, at 0% too", function()
      local lines = GC.Tooltip.BuildLines({ mv = 123400, sold = 52.34, ts = 1000 }, 2000, { sellChance = 0 })
      assert.same({ "GoldCap value", "Sold per day", "Sells from 0% of listings" }, texts(lines))
      assert.equal("", lines[3].right)
    end)

    it("is shown for a realm item and for a WoW: Forever scan", function()
      local realm = GC.Tooltip.BuildLines({ ref = 190000, ts = 1000, source = "import", kind = "realm_item" },
        2000, { sellChance = 100 })
      assert.same({ "GoldCap region price", "Sells from 100% of listings" }, texts(realm))
      local scan = GC.Tooltip.BuildLines({ mv = 70, min = 68, ts = 1990, source = "scan", kind = "crowd", scanners = 2 },
        2000, { sellChance = 42 })
      assert.equal("Sells from 42% of listings", texts(scan)[2])
    end)

    it("adds nothing without a figure", function()
      assert.same({ "GoldCap value", "Sold per day" },
        texts(GC.Tooltip.BuildLines({ mv = 123400, sold = 52.34, ts = 1000 }, 2000)))
    end)
  end)
end)
