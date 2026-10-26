local helper = require("spec.spec_helper")

describe("Disenchant", function()
  local GC, D
  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    helper.loadModule("Core/VendorSelect.lua", GC)
    helper.loadModule("Core/Disenchant.lua", GC)
    D = GC.Disenchant
  end)

  local NOW = 1800000000
  local nextID = 5000
  local function gear(over)
    nextID = nextID + 1
    local s = {
      bag = 0, slot = nextID - 5000, itemID = nextID, link = "item:" .. nextID, count = 1, quality = 2,
      vendorUnit = 100, ahUnit = nil, ahSource = "import", ahAt = NOW - 60, hasNoValue = false,
      isLocked = false, isBound = true, isGear = true, isReagent = false, refundable = false,
      tradeTimer = false, inSet = false, excludedBag = false, selling = false,
      classID = 4, subclassID = 1, equipLoc = "INVTYPE_CHEST", expansion = 10,
    }
    for k, v in pairs(over or {}) do s[k] = v end
    if over and over.ahUnit == false then s.ahUnit = nil end
    return s
  end
  local function opts(over)
    local o = { db = {}, priceOf = function() return nil end, inGroup = function() return false end, now = NOW }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
  end
  local function ids(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.stack.itemID end
    return out
  end

  it("casts spell 13262", function() assert.equal(13262, D.SPELL) end)

  describe("CanDisenchant", function()
    it("takes armor, weapons and profession tools of quality 2 to 4", function()
      assert.is_true(D.CanDisenchant(gear({ quality = 2 })))
      assert.is_true(D.CanDisenchant(gear({ quality = 4, classID = 2 })))
      assert.is_true(D.CanDisenchant(gear({ quality = 3, classID = 19 })))
    end)
    it("refuses other qualities, shirts, tabards and cosmetic armor", function()
      assert.is_false(D.CanDisenchant(gear({ quality = 1 })))
      assert.is_false(D.CanDisenchant(gear({ quality = 5 })))
      assert.is_false(D.CanDisenchant(gear({ equipLoc = "INVTYPE_BODY" })))
      assert.is_false(D.CanDisenchant(gear({ equipLoc = "INVTYPE_TABARD" })))
      assert.is_false(D.CanDisenchant(gear({ subclassID = 5 })))
      assert.is_false(D.CanDisenchant(gear({ classID = 0 })))
    end)
    it("lets a weapon of subclass 5 through: only armor has a cosmetic class", function()
      assert.is_true(D.CanDisenchant(gear({ classID = 2, subclassID = 5 })))
    end)
  end)

  it("names a kind by quality and expansion", function()
    assert.equal("q3:x10", D.KindOf(gear({ quality = 3 })))
    assert.equal("q2:x?", D.KindOf(gear({ expansion = false })))
  end)

  describe("yields", function()
    it("averages the casts learned", function()
      local db = {}
      assert.is_true(D.Learn(db, "q2:x10", { [1] = 2, [2] = 1 }))
      D.Learn(db, "q2:x10", { [1] = 3 })
      local y, n = D.Yield(db, "q2:x10")
      assert.equal(2, n)
      assert.equal(2.5, y[1])
      assert.equal(0.5, y[2])
    end)
    it("has nothing for a kind never learned, and creates nothing reading", function()
      local db = {}
      local y, n = D.Yield(db, "q2:x10")
      assert.is_nil(y)
      assert.equal(0, n)
      assert.is_nil(db.deYields)
    end)
    it("keeps the average at 50 casts", function()
      local db = {}
      for _ = 1, 80 do D.Learn(db, "k", { [1] = 2 }) end
      local y, n = D.Yield(db, "k")
      assert.equal(50, n)
      assert.is_true(math.abs(y[1] - 2) < 1e-9)
      D.Learn(db, "k", { [1] = 52 })
      y = D.Yield(db, "k")
      assert.is_true(math.abs(y[1] - 3) < 1e-9)
    end)
    it("does not write to a store a newer GoldCap wrote", function()
      local db = { deYields = { v = 2, kinds = {} } }
      assert.is_false(D.Learn(db, "k", { [1] = 1 }))
      assert.same({}, db.deYields.kinds)
    end)
    it("values a cast at the prices given, nil when one is missing or nothing is learned", function()
      local db = {}
      assert.is_nil((D.MatsValue(db, "k", function() return 10 end)))
      D.Learn(db, "k", { [1] = 2, [2] = 1 })
      local v, n = D.MatsValue(db, "k", function(id) return id == 1 and 100 or 50 end)
      assert.equal(250, v)
      assert.equal(1, n)
      v, n = D.MatsValue(db, "k", function(id) return id == 1 and 100 or nil end)
      assert.is_nil(v)
      assert.equal(1, n)
      -- A material nobody can sell is priced at 0 copper: it adds nothing, and the total is known.
      v = D.MatsValue(db, "k", function(id) return id == 1 and 100 or 0 end)
      assert.equal(200, v)
    end)
  end)

  describe("keep", function()
    it("keeps and unkeeps an item", function()
      local db = {}
      assert.is_false(D.Kept(db, 7))
      assert.is_nil(db.deKeep)
      D.Keep(db, 7)
      assert.is_true(D.Kept(db, 7))
      D.Unkeep(db, 7)
      assert.is_false(D.Kept(db, 7))
    end)
    it("lists every kept item, lowest id first", function()
      local db = {}
      assert.same({}, D.KeptIDs(db))
      D.Keep(db, 30)
      D.Keep(db, 7)
      D.Keep(db, 12)
      D.Unkeep(db, 12)
      assert.same({ 7, 30 }, D.KeptIDs(db))
    end)
    it("leaves a newer store alone", function()
      local db = { deKeep = { v = 2, items = {} } }
      assert.is_false(D.Writable(db))
      D.Keep(db, 7)
      assert.is_nil(db.deKeep.items[7])
      D.MarkCant(db, 7)
      assert.is_nil(db.deKeep.cant)
    end)
    it("remembers in the same store an item the client will not disenchant, until Try again", function()
      local db = {}
      assert.is_false(D.Cant(db, 7))
      assert.is_nil(db.deKeep)
      D.MarkCant(db, 30)
      D.MarkCant(db, 7)
      assert.is_true(D.Cant(db, 7))
      assert.same({ v = D.KEEP_VERSION, cant = { [7] = true, [30] = true } }, db.deKeep)
      assert.is_false(D.Kept(db, 7))
      assert.same({}, D.KeptIDs(db))
      assert.same({ 7, 30 }, D.CantIDs(db))
      D.Uncant(db, 30)
      assert.same({ 7 }, D.CantIDs(db))
      -- Next to what the player keeps, apart from it.
      D.Keep(db, 12)
      assert.same({ 12 }, D.KeptIDs(db))
      assert.same({ 7 }, D.CantIDs(db))
    end)
  end)

  describe("Plan", function()
    local DUST, SHARD = 9001, 9002
    local prices = { [DUST] = 150, [SHARD] = 350 }
    local function learned()
      local db = {}
      for _ = 1, 2 do D.Learn(db, "q2:x10", { [DUST] = 2.5 }) end
      D.Learn(db, "q3:x10", { [SHARD] = 1 })
      return db
    end

    it("leaves a stack the auction house pays more for out of the queue, when nothing is learned", function()
      local rich = gear({ vendorUnit = 300, ahUnit = 1240 * 10000 })
      local plan = D.Plan({ rich }, opts())
      assert.same({}, plan.queue)
      assert.equal(1, #plan.left)
      assert.equal("ah", plan.left[1].best)
      assert.equal(math.floor(1240 * 10000 * 0.95), plan.left[1].ah)
    end)
    it("lists an old auction price and an unpriced stack, with no mats verdict", function()
      local old = gear({ vendorUnit = 300, ahUnit = 1240 * 10000, ahAt = NOW - 25 * 3600 })
      local none = gear({})
      local plan = D.Plan({ old, none }, opts())
      assert.equal(2, #plan.queue)
      assert.is_nil(plan.queue[1].mats)
      assert.is_nil(plan.queue[1].ah)
      assert.is_nil(plan.queue[1].best)
      assert.is_nil(plan.matsTotal)
    end)
    it("queues a blue its mats pay more for, and leaves a green a vendor pays more for out, in a list of its own", function()
      local green = gear({ quality = 2, vendorUnit = 1900 })
      local blue = gear({ quality = 3, vendorUnit = 100 })
      local plan = D.Plan({ green, blue }, opts({ db = learned(), priceOf = function(id) return prices[id] end }))
      assert.same({ blue.itemID }, ids(plan.queue))
      assert.equal("mats", plan.queue[1].best)
      assert.equal(350, plan.queue[1].mats)
      assert.same({ green.itemID }, ids(plan.leftVendor))
      assert.equal("vendor", plan.leftVendor[1].best)
      assert.equal(375, plan.leftVendor[1].mats)
      assert.equal(1900, plan.leftVendor[1].vendor)
      assert.same({}, plan.left)
      assert.equal(350, plan.matsTotal)
      assert.is_nil(plan.yields[DUST])
      assert.equal(1, plan.yields[SHARD])
    end)
    it("orders mats rows by gain, unknown ones next; the vendor's by the smallest loss first", function()
      local db = learned()
      local p = function(id) return prices[id] end
      local a = gear({ quality = 3, vendorUnit = 100 })               -- gain 250
      local b = gear({ quality = 3, vendorUnit = 300 })               -- gain 50
      local u = gear({ quality = 4 })                                 -- unknown kind
      local c = gear({ quality = 2, vendorUnit = 400 })               -- loses 25
      local d = gear({ quality = 2, vendorUnit = 900 })               -- loses 525
      local plan = D.Plan({ d, c, u, b, a }, opts({ db = db, priceOf = p }))
      assert.same({ a.itemID, b.itemID, u.itemID }, ids(plan.queue))
      assert.same({ c.itemID, d.itemID }, ids(plan.leftVendor))
    end)
    it("queues a stack with unknown mats whatever a vendor pays: that is how GoldCap learns", function()
      local dear = gear({ quality = 4, vendorUnit = 99999999 })
      local plan = D.Plan({ dear }, opts({ db = learned(), priceOf = function(id) return prices[id] end }))
      assert.same({ dear.itemID }, ids(plan.queue))
      assert.same({}, plan.leftVendor)
    end)
    it("queues a stack whose mats pay what a vendor does", function()
      local even = gear({ quality = 2, vendorUnit = 375 })
      local plan = D.Plan({ even }, opts({ db = learned(), priceOf = function(id) return prices[id] end }))
      assert.same({ even.itemID }, ids(plan.queue))
    end)
    it("moves a row a vendor pays more for into the queue when the player says anyway", function()
      local green = gear({ bag = 3, slot = 5, quality = 2, vendorUnit = 1900 })
      local plan = D.Plan({ green }, opts({ db = learned(), priceOf = function(id) return prices[id] end,
        anyway = { ["3:5"] = true } }))
      assert.same({ green.itemID }, ids(plan.queue))
      assert.same({}, plan.leftVendor)
      assert.equal("vendor", plan.queue[1].best)
    end)
    it("puts the chosen item first, from the queue or a left list, while its slot holds the item chosen", function()
      local db, p = learned(), function(id) return prices[id] end
      local a = gear({ bag = 0, slot = 1, quality = 3, vendorUnit = 100 })
      local b = gear({ bag = 0, slot = 2, quality = 3, vendorUnit = 300 })
      local v = gear({ bag = 0, slot = 3, quality = 2, vendorUnit = 1900 })
      local h = gear({ bag = 0, slot = 4, quality = 2, vendorUnit = 300, ahUnit = 1240 * 10000 })
      local function plan(first) return D.Plan({ a, b, v, h }, opts({ db = db, priceOf = p, first = first })) end
      assert.same({ b.itemID, a.itemID }, ids(plan({ slotKey = "0:2", link = b.link }).queue))
      local fromVendor = plan({ slotKey = "0:3", link = v.link })
      assert.same({ v.itemID, a.itemID, b.itemID }, ids(fromVendor.queue))
      assert.same({}, fromVendor.leftVendor)
      local fromAH = plan({ slotKey = "0:4", link = h.link })
      assert.same({ h.itemID, a.itemID, b.itemID }, ids(fromAH.queue))
      assert.same({}, fromAH.left)
      -- Another item in that slot now: the choice is not its.
      assert.same({ a.itemID, b.itemID }, ids(plan({ slotKey = "0:2", link = "item:777" }).queue))
    end)
    it("names no vendor figure for an item a vendor will not buy, and never calls it for the vendor", function()
      local db, p = learned(), function(id) return prices[id] end
      local unsold = gear({ quality = 2, vendorUnit = 0 })
      local unknown = gear({ quality = 4, vendorUnit = 0 })
      local rich = gear({ quality = 2, vendorUnit = 0, ahUnit = 1240 * 10000 })
      local plan = D.Plan({ unsold, unknown, rich }, opts({ db = db, priceOf = p }))
      assert.same({ unsold.itemID, unknown.itemID }, ids(plan.queue))
      assert.is_nil(plan.queue[1].vendor)
      assert.equal("mats", plan.queue[1].best)
      assert.is_nil(plan.queue[2].vendor)
      assert.is_nil(plan.queue[2].best)
      assert.same({ rich.itemID }, ids(plan.left))
      assert.is_nil(plan.left[1].vendor)
      assert.equal("ah", plan.left[1].best)
    end)
    it("breaks ties by bag, then slot", function()
      local a = gear({ bag = 1, slot = 2 })
      local b = gear({ bag = 0, slot = 9 })
      local c = gear({ bag = 1, slot = 1 })
      local plan = D.Plan({ a, b, c }, opts())
      assert.same({ b.itemID, c.itemID, a.itemID }, ids(plan.queue))
    end)
    it("never lists what the player or the game keeps", function()
      local db = learned()
      local kept = gear({})
      D.Keep(db, kept.itemID)
      local grouped = gear({})
      local failed = gear({})
      local skipped = gear({ bag = 2, slot = 2 })
      local all = {
        kept, grouped, failed, skipped,
        gear({ inSet = true }), gear({ refundable = true }), gear({ tradeTimer = true }),
        gear({ isLocked = true }), gear({ selling = true }), gear({ quality = 1 }),
      }
      local cant = gear({})
      D.MarkCant(db, cant.itemID)
      all[#all + 1] = cant
      local plan = D.Plan(all, opts({
        db = db,
        inGroup = function(id) return id == grouped.itemID end,
        failed = { [failed.itemID] = true },
        skipped = { ["2:2"] = true },
      }))
      assert.same({}, plan.queue)
      assert.same({}, plan.left)
      assert.same({}, plan.leftVendor)
    end)
    it("moves a left row into the queue when the player says anyway", function()
      local rich = gear({ bag = 3, slot = 4, vendorUnit = 300, ahUnit = 1240 * 10000 })
      local plan = D.Plan({ rich }, opts({ anyway = { ["3:4"] = true } }))
      assert.equal(1, #plan.queue)
      assert.same({}, plan.left)
      assert.equal("3:4", plan.queue[1].slotKey)
      assert.equal("ah", plan.queue[1].best)
    end)
    it("leaves a stack out when its fresh auction figure beats both the vendor and the learned mats", function()
      local blue = gear({ quality = 3, vendorUnit = 100, ahUnit = 1000 })
      local plan = D.Plan({ blue }, opts({ db = learned(), priceOf = function(id) return prices[id] end }))
      assert.same({}, plan.queue)
      assert.equal(1, #plan.left)
      assert.equal("ah", plan.left[1].best)
      assert.equal(350, plan.left[1].mats)
      assert.equal(950, plan.left[1].ah)
    end)
    it("keeps a stack the auction house does not beat even by its mats", function()
      local db = learned()
      local blue = gear({ quality = 3, vendorUnit = 100, ahUnit = 300 })
      local plan = D.Plan({ blue }, opts({ db = db, priceOf = function(id) return prices[id] end }))
      assert.equal(1, #plan.queue)
      assert.equal("mats", plan.queue[1].best)
    end)
  end)
end)
