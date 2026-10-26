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

  -- Data/NoDisenchant.lua, generated from the game's own tables (ItemSparse Flags_0 0x8000).
  describe("the game's list of gear it will not disenchant", function()
    it("decodes every id the generated file counts, the belt the client refused among them", function()
      helper.loadModule("Data/NoDisenchant.lua", GC)
      assert.is_true(D.NoDisenchant(199762))   -- Valdrakken Guards Belt: "That item is not a valid target."
      assert.is_false(D.NoDisenchant(201759))  -- Torc of Passed Time: no flag, refused all the same
      local n = 0
      for id = 1, 400000 do
        if D.NoDisenchant(id) then n = n + 1 end
      end
      assert.equal(GC.NoDisenchant.count, n)
      assert.truthy(GC.NoDisenchant.build:match("^%d+%.%d+%.%d+%.%d+$"))
    end)
    it("loads in retail before Core/Disenchant.lua, and not in WoW: Forever", function()
      local function files(toc)
        local out = {}
        for line in io.lines(toc) do
          if not line:match("^#") and line:match("%S") then out[#out + 1] = line:gsub("%s+$", "") end
        end
        return out
      end
      local retail, at, core = files("GoldCap/GoldCap.toc"), nil, nil
      for i, f in ipairs(retail) do
        if f == "Data/NoDisenchant.lua" then at = i end
        if f == "Core/Disenchant.lua" then core = i end
      end
      assert.is_truthy(at and core and at < core)
      for _, f in ipairs(files("GoldCap/GoldCap_Camelot.toc")) do assert.not_equal("Data/NoDisenchant.lua", f) end
    end)
    -- The ids are held as one sorted array and searched by halves (the re-review's N2): every id of
    -- a run and between runs, the first and the last, and none outside them.
    it("finds each id of the runs and none between or outside them", function()
      GC.NoDisenchant = { build = "1.0.0.1", count = 5, ids = "a,5+2,z" }
      local want = { [10] = true, [15] = true, [16] = true, [17] = true, [52] = true }
      for id = 1, 60 do assert.equal(want[id] == true, D.NoDisenchant(id), tostring(id)) end
      assert.is_false(D.NoDisenchant(nil))
      assert.is_false(D.NoDisenchant("15"))
    end)
    it("knows no id without the file", function()
      assert.is_false(D.NoDisenchant(199762))
    end)
    it("never lists such gear, whatever pays more", function()
      helper.loadModule("Data/NoDisenchant.lua", GC)
      local belt = gear({ itemID = 199762, quality = 3, vendorUnit = 100 })
      assert.is_false(D.CanDisenchant(belt))
      local rich = gear({ itemID = 199762, quality = 3, ahUnit = 1240 * 10000 })
      local dear = gear({ itemID = 199762, quality = 2, vendorUnit = 999999 })
      local plan = D.Plan({ belt, rich, dear }, opts({ anyway = { [D.IdOf(dear)] = true } }))
      assert.same({}, plan.queue)
      assert.same({}, plan.left)
      assert.same({}, plan.leftVendor)
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
        anyway = { [D.IdOf(green)] = true } }))
      assert.same({ green.itemID }, ids(plan.queue))
      assert.same({}, plan.leftVendor)
      assert.equal("vendor", plan.queue[1].best)
    end)
    it("puts the chosen item first, from the queue or a left list", function()
      local db, p = learned(), function(id) return prices[id] end
      local a = gear({ bag = 0, slot = 1, quality = 3, vendorUnit = 100 })
      local b = gear({ bag = 0, slot = 2, quality = 3, vendorUnit = 300 })
      local v = gear({ bag = 0, slot = 3, quality = 2, vendorUnit = 1900 })
      local h = gear({ bag = 0, slot = 4, quality = 2, vendorUnit = 300, ahUnit = 1240 * 10000 })
      local function plan(first) return D.Plan({ a, b, v, h }, opts({ db = db, priceOf = p, first = first })) end
      assert.same({ b.itemID, a.itemID }, ids(plan(D.IdOf(b)).queue))
      local fromVendor = plan(D.IdOf(v))
      assert.same({ v.itemID, a.itemID, b.itemID }, ids(fromVendor.queue))
      assert.same({}, fromVendor.leftVendor)
      local fromAH = plan(D.IdOf(h))
      assert.same({ h.itemID, a.itemID, b.itemID }, ids(fromAH.queue))
      assert.same({}, fromAH.left)
      -- Another item in that slot now: the choice is not its.
      assert.same({ a.itemID, b.itemID }, ids(plan(D.IdOf({ bag = 0, slot = 2, link = "item:777" })).queue))
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
    it("puts the cheapest piece of an unknown kind first, so GoldCap learns the kind on it", function()
      local dear = gear({ bag = 0, slot = 1, quality = 4, vendorUnit = 610000 })
      local cheap = gear({ bag = 0, slot = 2, quality = 4, vendorUnit = 400 })
      local none = gear({ bag = 1, slot = 3, quality = 4, vendorUnit = 0 })
      local plan = D.Plan({ dear, cheap, none }, opts())
      assert.same({ none.itemID, cheap.itemID, dear.itemID }, ids(plan.queue))
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
        skipped = { [D.IdOf(skipped)] = true },
      }))
      assert.same({}, plan.queue)
      assert.same({}, plan.left)
      assert.same({}, plan.leftVendor)
    end)
    it("moves a left row into the queue when the player says anyway", function()
      local rich = gear({ bag = 3, slot = 4, vendorUnit = 300, ahUnit = 1240 * 10000 })
      local plan = D.Plan({ rich }, opts({ anyway = { [D.IdOf(rich)] = true } }))
      assert.equal(1, #plan.queue)
      assert.same({}, plan.left)
      assert.equal("3:4", plan.queue[1].slotKey)
      assert.equal("ah", plan.queue[1].best)
    end)
    -- The visit's choices (Disenchant anyway, Skip, the chosen item) hold an item by its GUID, the
    -- bag reader's `guid`, which follows it through a sort of the bags and tells apart two items with
    -- one link (the owner, 2026-10-27: Disenchant anyway on two of four identical slippers, one
    -- disenchanted, a sort, and the queue held the other three); without a GUID, by its slot and link.
    local function guids(rows)
      local out = {}
      for i, r in ipairs(rows) do out[i] = r.stack.guid end
      return out
    end
    -- Two items with one link, A at 0:5 and B at 0:6; a sort swaps them.
    local function twins(over)
      local a = gear({ bag = 0, slot = 5, guid = "Item-A" })
      local b = gear({ bag = 0, slot = 6, itemID = a.itemID, link = a.link, guid = "Item-B" })
      for k, v in pairs(over or {}) do a[k], b[k] = v, v end
      local function sorted()
        a.slot, b.slot = 6, 5
        return { b, a }
      end
      return a, b, sorted
    end
    it("holds Disenchant anyway by the item's GUID: its twin never inherits it, wherever a sort moves them", function()
      local a, b, sorted = twins({ vendorUnit = 300, ahUnit = 1240 * 10000 })
      local anyway = { [D.IdOf(a)] = true }
      assert.same({ "Item-A" }, guids(D.Plan({ a, b }, opts({ anyway = anyway })).queue))
      local plan = D.Plan(sorted(), opts({ anyway = anyway }))
      assert.same({ "Item-A" }, guids(plan.queue))
      assert.equal("0:6", plan.queue[1].slotKey)
      assert.same({ "Item-B" }, guids(plan.left))
    end)
    it("holds a skip by the item's GUID: its twin stays queued, wherever a sort moves them", function()
      local a, b, sorted = twins()
      local skipped = { [D.IdOf(a)] = true }
      assert.same({ "Item-B" }, guids(D.Plan({ a, b }, opts({ skipped = skipped })).queue))
      assert.same({ "Item-B" }, guids(D.Plan(sorted(), opts({ skipped = skipped })).queue))
    end)
    it("holds the chosen item by its GUID: first wherever a sort moves it, its twin not", function()
      local a, b, sorted = twins()
      local first = D.IdOf(b)
      assert.same({ "Item-B", "Item-A" }, guids(D.Plan({ a, b }, opts({ first = first })).queue))
      assert.same({ "Item-B", "Item-A" }, guids(D.Plan(sorted(), opts({ first = first })).queue))
    end)
    it("holds a stack without a GUID by its slot and link", function()
      local a = gear({ bag = 0, slot = 5, vendorUnit = 300, ahUnit = 1240 * 10000 })
      local key = D.IdOf(a)
      assert.same({ a.itemID }, ids(D.Plan({ a }, opts({ anyway = { [key] = true } })).queue))
      assert.same({}, D.Plan({ a }, opts({ skipped = { [key] = true } })).left)
      -- Moved to another slot: no longer the one chosen.
      a.slot = 6
      assert.same({ a.itemID }, ids(D.Plan({ a }, opts({ anyway = { [key] = true } })).left))
      -- Another item in that slot: neither chosen nor skipped.
      local other = gear({ bag = 0, slot = 5, vendorUnit = 300, ahUnit = 1240 * 10000 })
      assert.same({ other.itemID }, ids(D.Plan({ other }, opts({ anyway = { [key] = true } })).left))
      local plain = gear({ bag = 0, slot = 5 })
      assert.same({ plain.itemID }, ids(D.Plan({ plain }, opts({ skipped = { [key] = true } })).queue))
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
