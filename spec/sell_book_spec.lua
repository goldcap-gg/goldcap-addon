local helper = require("spec.spec_helper")

-- The Sell tab has always priced against the live order book and never shown it. Every price
-- decision in Core/SellPositions reads `levels` -- the underprice floor, the recommendation,
-- the depth ahead of your own lot -- and the seller looking at the row could see none of it:
-- a price appeared, with nothing to say what it was standing on, who was under it, or how much
-- stock was sitting there. These cover the model the expanded row reads.
describe("Sell order book", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  local function position(over)
    local p = {
      positionKey = "commodity:42", itemID = 42, coverage = "UNKNOWN",
      batches = {}, ownedLots = {}, allocations = {}, pendingAcquisitions = {},
      sellerEvidence = {}, facts = {}, knownQty = 0, exposureQty = 0,
      levels = {
        { unitPrice = 418800, quantity = 12 },
        { unitPrice = 420500, quantity = 340 },
        { unitPrice = 426000, quantity = 90, ownerQty = 90 },
        { unitPrice = 431000, quantity = 620 },
      },
      postRecommendation = { unit = 420400 },
    }
    for k, v in pairs(over or {}) do p[k] = (v ~= "\0NONE") and v or nil end
    return p
  end

  it("is absent when the addon has no live book for the item", function()
    assert.is_nil(GC.SellViewModel.Expansion(position({ levels = "\0NONE" })).book)
    assert.is_nil(GC.SellViewModel.Expansion(position({ levels = {} })).book)
  end)

  it("reads the levels cheapest first, with a running total behind each price", function()
    local b = GC.SellViewModel.Expansion(position()).book
    assert.equal(4, #b.rows)
    assert.equal(418800, b.rows[1].unit)
    assert.equal(12, b.rows[1].cumulative)
    assert.equal(352, b.rows[2].cumulative)
    assert.equal(1062, b.rows[4].cumulative)
    assert.equal(1062, b.totalUnits)
  end)

  -- The one thing a seller cannot work out by eye: their own stock is IN the book, so the
  -- cheapest row is not necessarily somebody to undercut. A level the player shares is marked
  -- rather than dropped -- dropping it would make the queue behind the price wrong.
  it("marks the levels the player is already standing on", function()
    local b = GC.SellViewModel.Expansion(position()).book
    assert.is_false(b.rows[2].mine)
    assert.is_true(b.rows[3].mine)
    assert.equal(90, b.rows[3].ownerUnits)
    -- and the cheapest price that is NOT the player's own
    assert.equal(418800, b.cheapestCompeting)
  end)

  it("treats a level it cannot split as entirely the player's own", function()
    local b = GC.SellViewModel.Expansion(position({ levels = {
      { unitPrice = 100000, quantity = 5, ownerItem = true },
      { unitPrice = 110000, quantity = 7 },
    } })).book
    assert.is_true(b.rows[1].mine)
    assert.equal(5, b.rows[1].ownerUnits)
    assert.equal(110000, b.cheapestCompeting)
  end)

  -- Where the seller is about to land, which is the whole question the row is asking.
  it("points at the row the price GoldCap picked would join", function()
    local b = GC.SellViewModel.Expansion(position()).book
    assert.equal(420400, b.yourUnit)
    assert.equal(2, b.yourRow) -- 420400 sits just under the 420500 wall
  end)

  it("has no row to point at when the addon has no price for the bag stock", function()
    local b = GC.SellViewModel.Expansion(position({ postRecommendation = "\0NONE" })).book
    assert.is_nil(b.yourUnit)
    assert.is_nil(b.yourRow)
  end)

  -- Nobody undercuts the fortieth cheapest seller, and the book runs to a hundred levels. The
  -- rows are capped -- but the header's own totals are not, so a truncated book can never read
  -- as a thinner market than it is.
  it("caps the rows it shows without understating the market behind them", function()
    local levels = {}
    for i = 1, 30 do levels[i] = { unitPrice = 100000 + i * 100, quantity = 10 } end
    local b = GC.SellViewModel.Expansion(position({ levels = levels })).book
    assert.equal(8, #b.rows)
    assert.is_true(b.truncated)
    assert.equal(30, b.levels)
    assert.equal(300, b.totalUnits) -- all thirty, not the eight shown
  end)

  it("skips a malformed level rather than pricing a row off nil", function()
    local b = GC.SellViewModel.Expansion(position({ levels = {
      { unitPrice = 0, quantity = 99 }, "junk", { unitPrice = 100000, quantity = 4 },
    } })).book
    assert.equal(1, #b.rows)
    assert.equal(100000, b.rows[1].unit)
  end)
end)
