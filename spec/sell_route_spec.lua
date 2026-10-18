local helper = require("spec.spec_helper")

-- Where a flip sells best among the player's realms, mirrored from goldcap.gg's own estimate
-- (wow-auction apps/api/src/lib/whereToSell.ts): the payload carries the realms each flip sells on
-- within a week, best net first, and this picks among them.
describe("SellRoute", function()
  local GC
  local G = 10000

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/SellRoute.lua", GC)
  end)

  local function spot(realmId, gold, days, own)
    return { realmId = realmId, list = gold * G, days = days, own = own or false }
  end

  describe("Key", function()
    it("keys a realm name the way the site keys it: ASCII letters lowered, punctuation and spaces dropped", function()
      assert.equal("tarrenmill", GC.SellRoute.Key("Tarren Mill"))
      assert.equal("lightningsblade", GC.SellRoute.Key("Lightning's Blade"))
      assert.equal("azjolnerub", GC.SellRoute.Key("Azjol-Nerub"))
      assert.equal("area52", GC.SellRoute.Key("Area 52"))
    end)

    it("keeps every byte that is not ASCII as it is", function()
      assert.equal("Гордунни", GC.SellRoute.Key("Гордунни"))
      assert.equal("아즈샤라", GC.SellRoute.Key("아즈샤라"))
    end)

    it("has no key for no name", function()
      assert.is_nil(GC.SellRoute.Key(nil))
      assert.is_nil(GC.SellRoute.Key(""))
      assert.is_nil(GC.SellRoute.Key("'- "))
    end)
  end)

  describe("Net", function()
    it("takes the auction house's 5% cut, rounded half up in copper", function()
      assert.equal(9500, GC.SellRoute.Net(10000))
      assert.equal(1, GC.SellRoute.Net(1)) -- 0.95
      assert.equal(10, GC.SellRoute.Net(11)) -- 10.45
      assert.equal(11, GC.SellRoute.Net(12)) -- 11.4
    end)
  end)

  describe("Mine", function()
    local keys = { tarrenmill = 1084, kazzak = 1305, azjolnerub = 1396 }
    local function idByKey(key) return keys[key] end

    it("is every realm of this region a character of the account was seen on, and this one", function()
      local points = {
        { char = "Alt-Tarren Mill", region = "eu", copper = 1 },
        { char = "Main-Azjol-Nerub", region = "eu", copper = 1 },
        { char = "Other-Area 52", region = "us", copper = 1 },
        { char = "Ghost-Nowhere", region = "eu", copper = 1 },
        { char = "Alt-Tarren Mill", region = "eu", copper = 2 },
        { char = "Nameless", region = "eu", copper = 1 },
      }
      assert.same({ [1084] = true, [1396] = true, [1305] = true }, GC.SellRoute.Mine(points, "eu", idByKey, 1305))
    end)

    it("is this realm alone with no readings, and nothing when this realm is unknown too", function()
      assert.same({ [1305] = true }, GC.SellRoute.Mine({}, "eu", idByKey, 1305))
      assert.same({}, GC.SellRoute.Mine(nil, "eu", idByKey, nil))
    end)
  end)

  describe("Pick", function()
    local SPOTS = { spot(9, 3000, 3), spot(2, 2200, 2.4, true), spot(1, 2000, 0.6, true), spot(5, 1900, 1) }

    it("names this realm, the best of the player's realms, and no other realm when none is notably better", function()
      local pick = GC.SellRoute.Pick({ spot(2, 2200, 2.4), spot(1, 2000, 0.6) }, { [1] = true, [2] = true }, 1)
      assert.equal(1, pick.here.realmId)
      assert.equal(2, pick.best.realmId)
      assert.is_nil(pick.suggest)
    end)

    it("suggests a realm with no character when it nets a quarter more and 500 gold more than the best of them", function()
      local pick = GC.SellRoute.Pick(SPOTS, { [1] = true, [2] = true }, 1)
      assert.equal(9, pick.suggest.realmId) -- 2850 net against 2090: 36% and 760g more
    end)

    it("does not suggest one that is a quarter better but not 500 gold better", function()
      local pick = GC.SellRoute.Pick({ spot(9, 300, 3), spot(1, 200, 1) }, { [1] = true }, 1)
      assert.is_nil(pick.suggest)
    end)

    it("does not suggest one that is 500 gold better but not a quarter better", function()
      -- 5700 net against 4750: 950 gold more, but a fifth more, not a quarter
      local pick = GC.SellRoute.Pick({ spot(9, 6000, 3), spot(1, 5000, 1) }, { [1] = true }, 1)
      assert.is_nil(pick.suggest)
    end)

    it("suggests the best realm when none of the player's sells it within a week, if it nets 500 gold", function()
      local pick = GC.SellRoute.Pick({ spot(9, 600, 3) }, { [1] = true }, 1)
      assert.is_nil(pick.here)
      assert.is_nil(pick.best)
      assert.equal(9, pick.suggest.realmId)
      assert.is_nil(GC.SellRoute.Pick({ spot(9, 400, 3) }, { [1] = true }, 1).suggest)
    end)

    it("has nothing to say without spots", function()
      assert.is_nil(GC.SellRoute.Pick(nil, { [1] = true }, 1))
      assert.is_nil(GC.SellRoute.Pick({}, { [1] = true }, 1))
    end)
  end)

  describe("Target", function()
    it("is another of the player's realms when it nets a tenth more and 100 gold more than here", function()
      local pick = GC.SellRoute.Pick({ spot(2, 2200, 2), spot(1, 1990, 1) }, { [1] = true, [2] = true }, 1)
      assert.equal(2, GC.SellRoute.Target(pick).realmId)
    end)

    it("is here when the best of the player's realms is not worth the trip", function()
      -- 10% more but under 100 gold more, then 100 gold more but under 10% more
      local pick = GC.SellRoute.Pick({ spot(2, 990, 2), spot(1, 900, 1) }, { [1] = true, [2] = true }, 1)
      assert.equal(1, GC.SellRoute.Target(pick).realmId)
      pick = GC.SellRoute.Pick({ spot(2, 2100, 2), spot(1, 1990, 1) }, { [1] = true, [2] = true }, 1)
      assert.equal(1, GC.SellRoute.Target(pick).realmId)
    end)

    it("is the best of the player's realms when it does not sell here within a week", function()
      local pick = GC.SellRoute.Pick({ spot(2, 900, 6) }, { [1] = true, [2] = true }, 1)
      assert.equal(2, GC.SellRoute.Target(pick).realmId)
    end)

    it("is nothing when none of the player's realms sells it", function()
      assert.is_nil(GC.SellRoute.Target(GC.SellRoute.Pick({ spot(9, 900, 6) }, { [1] = true }, 1)))
      assert.is_nil(GC.SellRoute.Target(nil))
    end)
  end)

  -- What to move through the Warband Bank at a bank on this realm (Tarren Mill, 1): put in what
  -- sells better on another of the player's realms, take out what sells best here.
  describe("CarryPlan", function()
    local mine = { [1] = true, [2] = true }
    -- 100: sells best on Kazzak (2); 200: best here; 300: a level 639 flip, best on Kazzak; 400: no
    -- route at all.
    local SPOTS = {
      [100] = { spot(2, 2200, 2.4), spot(1, 1500, 1) },
      [200] = { spot(1, 900, 0.5), spot(2, 880, 3) },
      [300] = { spot(2, 5000, 4) },
    }
    local LEVELS = { [300] = 639 }
    local function opts()
      return {
        hereId = 1,
        routeFor = function(id) return GC.SellRoute.Pick(SPOTS[id], mine, 1) end,
        levelFor = function(id) return LEVELS[id] end,
      }
    end
    local function item(itemID, bag, slot, over)
      local e = { itemID = itemID, bag = bag, slot = slot, count = 1, name = "Item " .. itemID, icon = itemID }
      for k, v in pairs(over or {}) do e[k] = v end
      return e
    end

    it("puts in what sells better on another of the player's realms, one row an item, every slot it sits in", function()
      local plan = GC.SellRoute.CarryPlan({ item(100, 0, 1), item(100, 2, 5), item(200, 0, 2), item(400, 0, 3) }, {}, opts())
      assert.equal(1, #plan.putIn)
      local row = plan.putIn[1]
      assert.equal(100, row.itemID)
      assert.equal(2, row.count)
      assert.same({ { bag = 0, slot = 1 }, { bag = 2, slot = 5 } }, row.locations)
      assert.equal(2, row.spot.realmId)
      assert.same({}, plan.takeOut)
    end)

    it("takes out what sells best here", function()
      local plan = GC.SellRoute.CarryPlan({}, { item(200, 12, 4, { count = 3 }), item(100, 12, 5) }, opts())
      assert.equal(1, #plan.takeOut)
      assert.equal(200, plan.takeOut[1].itemID)
      assert.equal(3, plan.takeOut[1].count)
      assert.same({ { bag = 12, slot = 4 } }, plan.takeOut[1].locations)
      assert.equal(1, plan.takeOut[1].spot.realmId)
    end)

    it("leaves gear under the level its price is for where it is", function()
      local plan = GC.SellRoute.CarryPlan({ item(300, 0, 1, { ilvl = 610 }), item(300, 0, 2, { ilvl = 639 }) }, {}, opts())
      assert.equal(1, #plan.putIn)
      assert.same({ { bag = 0, slot = 2 } }, plan.putIn[1].locations)
    end)

    it("moves nothing Warbound until equipped, and says it is stuck", function()
      local plan = GC.SellRoute.CarryPlan({ item(100, 0, 1, { wue = true }) }, { item(200, 12, 1, { wue = true }) }, opts())
      assert.same({}, plan.putIn)
      assert.same({}, plan.takeOut)
      assert.equal(2, #plan.stuck)
      assert.equal(100, plan.stuck[1].itemID)
    end)

    it("lists the most valuable first", function()
      local plan = GC.SellRoute.CarryPlan({ item(100, 0, 1), item(300, 0, 2, { ilvl = 640 }) }, {}, opts())
      assert.equal(300, plan.putIn[1].itemID)
      assert.equal(100, plan.putIn[2].itemID)
    end)

    it("is empty off a realm the payload names", function()
      local o = opts()
      o.hereId = nil
      local plan = GC.SellRoute.CarryPlan({ item(100, 0, 1) }, { item(200, 12, 1) }, o)
      assert.same({ putIn = {}, takeOut = {}, stuck = {} }, plan)
    end)
  end)

  describe("IsCheap", function()
    it("is a price at or under the fifth cheapest realm, among ten realms or more", function()
      assert.is_true(GC.SellRoute.IsCheap(500, { floor5th = 500, realms = 10 }))
      assert.is_false(GC.SellRoute.IsCheap(501, { floor5th = 500, realms = 24 }))
      assert.is_false(GC.SellRoute.IsCheap(100, { floor5th = 500, realms = 9 })) -- five of nine says little
      assert.is_false(GC.SellRoute.IsCheap(100, nil))
      assert.is_false(GC.SellRoute.IsCheap(nil, { floor5th = 500, realms = 24 }))
    end)
  end)

  describe("words", function()
    local names = { [2] = "Kazzak", [9] = "Silvermoon" }
    local function nameOf(id) return names[id] end

    it("says how soon it sells the way the site does", function()
      assert.equal("sells within a day", GC.SellRoute.PaceText(0.6))
      assert.equal("sells in about 1 day", GC.SellRoute.PaceText(1.4))
      assert.equal("sells in about 3 days", GC.SellRoute.PaceText(2.5))
    end)

    it("says where to sell, at what list price and how soon", function()
      local pick = GC.SellRoute.Pick({ spot(2, 2200, 2.4), spot(1, 1900, 0.6) }, { [1] = true, [2] = true }, 1)
      local lines = GC.SellRoute.Lines(pick, nameOf)
      assert.equal(1, #lines)
      assert.equal("Sell on Kazzak for " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days", lines[1])
    end)

    it("says to sell here when here is the place", function()
      local pick = GC.SellRoute.Pick({ spot(1, 1900, 0.6) }, { [1] = true }, 1)
      assert.same({ "Sell here for " .. GC.Util.FormatMoney(1900 * G) .. ", sells within a day" },
        GC.SellRoute.Lines(pick, nameOf))
    end)

    it("names a realm with no character only when it pays notably more", function()
      local pick = GC.SellRoute.Pick({ spot(9, 3000, 3), spot(1, 2000, 0.6) }, { [1] = true }, 1)
      local lines = GC.SellRoute.Lines(pick, nameOf)
      assert.equal(2, #lines)
      assert.equal("Sell here for " .. GC.Util.FormatMoney(2000 * G) .. ", sells within a day", lines[1])
      assert.equal("Pays more on Silvermoon, where you have no character: "
        .. GC.Util.FormatMoney(3000 * G) .. ", sells in about 3 days", lines[2])
    end)

    it("says nothing without a pick, and leaves out a realm it has no name for", function()
      assert.same({}, GC.SellRoute.Lines(nil, nameOf))
      local pick = GC.SellRoute.Pick({ spot(7, 2200, 2.4), spot(1, 1900, 0.6) }, { [1] = true, [7] = true }, 1)
      assert.same({}, GC.SellRoute.Lines(pick, nameOf))
    end)

    it("says when this realm is among the five cheapest", function()
      assert.equal("Among the 5 cheapest of 24 realms", GC.SellRoute.CheapText({ floor5th = 5, realms = 24 }))
    end)

    -- The Check panel's route rows (Core/CheckVerdict.lua's sellOn, betterOn and cheapRealms), in
    -- one line beside their label: the whole of it, then shorter for a cell it does not fit.
    it("words a Check fact, shorter on each step down", function()
      local fact = { id = "sellOn", realm = "Kazzak", copper = 2200 * G, days = 2.4 }
      local money = GC.Util.FormatMoney(2200 * G)
      assert.equal("Kazzak · " .. money .. " · about 2 days", GC.SellRoute.FactText(fact, 1))
      assert.equal("Kazzak · " .. money, GC.SellRoute.FactText(fact, 2))
      assert.equal("Kazzak", GC.SellRoute.FactText(fact, 3))
      assert.is_nil(GC.SellRoute.FactText(fact, 4))
      assert.equal("this realm · " .. GC.Util.FormatMoney(1900 * G) .. " · under a day",
        GC.SellRoute.FactText({ id = "sellOn", here = true, copper = 1900 * G, days = 0.6 }, 1))
      assert.equal("about 1 day", GC.SellRoute.FactText({ id = "betterOn", realm = "X", copper = 1, days = 1.2 }, 1):match("about 1 day"))
      assert.equal("top 5 of 24", GC.SellRoute.FactText({ id = "cheapRealms", count = 24 }, 1))
      assert.is_nil(GC.SellRoute.FactText({ id = "cheapRealms", count = 24 }, 2))
    end)
  end)
end)
