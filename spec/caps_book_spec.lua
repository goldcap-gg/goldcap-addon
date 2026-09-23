local helper = require("spec.spec_helper")

-- Live price caps, addon task 4: which commodity hits the book pass (Core/BookPass.lua's own
-- book) hands to the drill queue. GC.Caps.BookHits is the pure filter UI/SniperFrame.lua folds
-- through after every completed pass -- caps order, capped commodities only (a realm item is
-- the key poll's job, see spec/caps_targets_spec.lua's "excludes a commodity cap"), and only
-- ones the book already has a floor for at or under the cap.
describe("Caps.BookHits", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
    _G.GoldCap_AppRuns = {
      v = 3, generatedAt = 1, runs = {}, groups = {},
      caps = {
        { i = 500, c = 1000 }, -- commodity, under cap
        { i = 100, c = 500 },  -- commodity, under cap
        { i = 200, c = 300 },  -- commodity, OVER cap
        { i = 300, c = 900 },  -- realm item, under cap -- not a commodity, ignored here
        { i = 600, c = 700 },  -- commodity, capped but absent from the book
      },
    }
    GC.Caps.Adopt()
  end)

  after_each(function() _G.GoldCap_AppRuns = nil end)

  local function commodityFn(ids)
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    return function(itemID) return set[itemID] == true end
  end

  it("returns capped commodities at or under the cap, in caps order", function()
    local book = {
      [500] = { floor = 800, qty = 3 },
      [100] = { floor = 480, qty = 5 },
      [200] = { floor = 350, qty = 5 }, -- over its 300 cap
      [300] = { floor = 800, qty = 2 }, -- realm item, not a commodity
    }
    local hits = GC.Caps.BookHits(book, commodityFn({ 500, 100, 200, 600 }))
    assert.same({
      { itemID = 500, floor = 800, estProfit = 200 },
      { itemID = 100, floor = 480, estProfit = 20 },
    }, hits)
  end)

  it("ignores a capped commodity absent from the book", function()
    local book = { [300] = { floor = 800, qty = 2 } }
    local hits = GC.Caps.BookHits(book, commodityFn({ 500, 100, 200, 600 }))
    assert.same({}, hits)
  end)

  -- Final review I2: the book pass folds a book that mostly does not move, and this used to
  -- re-report every capped commodity sitting under its cap on EVERY completed pass -- a hit per
  -- pass, per item, for a price nothing had happened to. The key poll's own side has always
  -- ratcheted (Core/KeyPoll.lua's Fold: a hit is a floor that is also NEWS); this is the same
  -- rule for the book-pass side. A floor that MOVED is news again, in either direction, and
  -- Forget/ForgetAll clear the memory the same way they clear the ring's.
  describe("the floor ratchet", function()
    local book

    before_each(function()
      book = { [500] = { floor = 800, qty = 3 }, [100] = { floor = 480, qty = 5 } }
    end)

    local isCommodity = function() return true end

    it("reports a floor once and stays silent on the same book", function()
      assert.equal(2, #GC.Caps.BookHits(book, isCommodity))
      assert.same({}, GC.Caps.BookHits(book, isCommodity))
    end)

    it("reports again once a floor actually moves", function()
      GC.Caps.BookHits(book, isCommodity)
      book[500].floor = 700
      local hits = GC.Caps.BookHits(book, isCommodity)
      assert.same({ { itemID = 500, floor = 700, estProfit = 300 } }, hits)
    end)

    it("reports again after Forget, at the very same floor", function()
      GC.Caps.BookHits(book, isCommodity)
      GC.Caps.Forget(500)
      local hits = GC.Caps.BookHits(book, isCommodity)
      assert.same({ { itemID = 500, floor = 800, estProfit = 200 } }, hits)
    end)

    it("reports every item again after ForgetAll", function()
      GC.Caps.BookHits(book, isCommodity)
      GC.Caps.ForgetAll()
      assert.equal(2, #GC.Caps.BookHits(book, isCommodity))
    end)

    -- Caps fixes 3f: the memory used to reset only through Forget, which the drill reaches
    -- when it comes back empty -- and a floor that climbs back above the cap is never drilled.
    -- So 480 under a 500 cap, then 600, then 480 again said nothing the second time: the
    -- ratchet still held 480, and a re-dip to the very price it remembered read as no news.
    it("forgets a floor that climbed above the cap, so a re-dip to it is news again", function()
      assert.equal(2, #GC.Caps.BookHits(book, isCommodity))
      book[100].floor = 600 -- above its 500 cap
      assert.same({}, GC.Caps.BookHits(book, isCommodity))
      book[100].floor = 480
      assert.same({ { itemID = 100, floor = 480, estProfit = 20 } }, GC.Caps.BookHits(book, isCommodity))
    end)

    it("forgets the ring's memory for it too", function()
      GC.Caps.Announce({ itemID = 100, isCommodity = true, unitPrice = 480 })
      book[100].floor = 600
      GC.Caps.BookHits(book, isCommodity)
      assert.is_true(GC.Caps.Announce({ itemID = 100, isCommodity = true, unitPrice = 480 }))
    end)

    -- Caps fixes 4b: a hit the drill queue let go of without drilling it (aged out, or pushed
    -- out of a full queue) was never reported again while its floor stood still -- the item sat
    -- under the player's price for the rest of the visit, unlooked at. Rearm re-arms the ratchet
    -- for exactly that, and nothing else: the ring has not played, so its memory stays.
    it("reports an unchanged floor again after Rearm, and only once", function()
      assert.equal(2, #GC.Caps.BookHits(book, isCommodity))
      GC.Caps.Rearm(500)
      assert.same({ { itemID = 500, floor = 800, estProfit = 200 } }, GC.Caps.BookHits(book, isCommodity))
      assert.same({}, GC.Caps.BookHits(book, isCommodity))
    end)

    it("leaves the ring's memory alone on Rearm", function()
      GC.Caps.Announce({ itemID = 500, isCommodity = true, unitPrice = 800 })
      GC.Caps.Rearm(500)
      assert.is_false(GC.Caps.Announce({ itemID = 500, isCommodity = true, unitPrice = 800 }))
    end)

    it("leaves an item that is still under its cap exactly as it was", function()
      GC.Caps.Announce({ itemID = 500, isCommodity = true, unitPrice = 800 })
      GC.Caps.BookHits(book, isCommodity)
      book[100].floor = 600
      GC.Caps.BookHits(book, isCommodity)
      assert.is_false(GC.Caps.Announce({ itemID = 500, isCommodity = true, unitPrice = 800 }))
      assert.same({}, GC.Caps.BookHits(book, isCommodity))
    end)
  end)
end)
