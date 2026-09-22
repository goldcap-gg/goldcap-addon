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
end)
