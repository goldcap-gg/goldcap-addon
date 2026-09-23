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

  -- The ladder's price levels, without the marker and gap rows between them.
  local function levelRows(b)
    local out = {}
    for _, row in ipairs(b.rows) do if row.kind == "level" then out[#out + 1] = row end end
    return out
  end

  it("reads the levels cheapest first, with a running total behind each price", function()
    local b = GC.SellViewModel.Expansion(position()).book
    local levels = levelRows(b)
    assert.equal(4, #levels)
    assert.equal(418800, levels[1].unit)
    assert.equal(12, levels[1].cumulative)
    assert.equal(352, levels[2].cumulative)
    assert.equal(1062, levels[4].cumulative)
    assert.equal(1062, b.totalUnits)
  end)

  -- The one thing a seller cannot work out by eye: their own stock is IN the book, so the
  -- cheapest row is not necessarily somebody to undercut. A level the player shares is marked
  -- rather than dropped -- dropping it would make the queue behind the price wrong.
  it("marks the levels the player is already standing on", function()
    local levels = levelRows(GC.SellViewModel.Expansion(position()).book)
    local b = GC.SellViewModel.Expansion(position()).book
    assert.is_false(levels[2].mine)
    assert.is_true(levels[3].mine)
    assert.equal(90, levels[3].ownerUnits)
    -- and the cheapest price that is NOT the player's own
    assert.equal(418800, b.cheapestCompeting)
  end)

  it("treats a level it cannot split as entirely the player's own", function()
    local b = GC.SellViewModel.Expansion(position({ levels = {
      { unitPrice = 100000, quantity = 5, ownerItem = true },
      { unitPrice = 110000, quantity = 7 },
    } })).book
    assert.is_true(levelRows(b)[1].mine)
    assert.equal(5, levelRows(b)[1].ownerUnits)
    assert.equal(110000, b.cheapestCompeting)
  end)

  -- Where the seller is about to land, which is the whole question the row is asking.
  it("points at the row the price GoldCap picked would join", function()
    local b = GC.SellViewModel.Expansion(position()).book
    assert.equal(420400, b.yourUnit)
    assert.equal(2, b.yourRow) -- 420400 sits just under the 420500 level
    assert.equal("yours", b.rows[2].kind)
    assert.equal(420400, b.rows[2].unit)
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
    assert.equal(8, #b.rows) -- the panel's eight lines, marker and gap included
    assert.is_true(b.truncated)
    assert.equal(30, b.levels)
    assert.equal(300, b.totalUnits) -- all thirty, not the eight shown
  end)

  it("skips a malformed level rather than pricing a row off nil", function()
    local b = GC.SellViewModel.Expansion(position({ levels = {
      { unitPrice = 0, quantity = 99 }, "junk", { unitPrice = 100000, quantity = 4 },
    } })).book
    assert.equal(1, #levelRows(b))
    assert.equal(100000, levelRows(b)[1].unit)
  end)

  -- THE BOOK around the player's price (owner, 2026-09-23: "I'd like to see the ceiling -- that
  -- at 242.9 there are a pile of items, like 42k"). What decides when a commodity sells is the
  -- stock at or under your price -- at an equal price the older listing sells first -- and the
  -- first big wall. The eight cheapest levels showed neither.
  describe("around your price", function()
    local function ladder(n, unitOf, qtyOf)
      local levels = {}
      for i = 1, n do levels[i] = { unitPrice = unitOf(i), quantity = qtyOf and qtyOf(i) or 10 } end
      return levels
    end

    local function kinds(b)
      local out = {}
      for _, row in ipairs(b.rows) do out[#out + 1] = row.kind == "level" and tostring(row.unit) or row.kind end
      return table.concat(out, " ")
    end

    it("shows the cheapest, a gap, the levels just under your price, your price, and above it", function()
      -- 20 levels at 1010..1200; your price 1155 lands between 1150 (15th) and 1160 (16th).
      local b = GC.SellViewModel.Expansion(position({ levels = ladder(20, function(i) return 1000 + i * 10 end),
        postRecommendation = { unit = 1155 } })).book
      assert.equal("1010 1020 gap 1140 1150 yours 1160 1170", kinds(b))
      assert.equal(8, #b.rows)
      assert.equal(110, b.rows[3].units)  -- 1030..1130: eleven levels of ten
      assert.equal(11, b.rows[3].prices)
      assert.equal(6, b.yourRow)
    end)

    it("needs no gap when everything under your price fits, and gives the room to the levels above", function()
      local b = GC.SellViewModel.Expansion(position({ levels = ladder(20, function(i) return 1000 + i * 10 end),
        postRecommendation = { unit = 1025 } })).book
      assert.equal("1010 1020 yours 1030 1040 1050 1060 1070", kinds(b))
    end)

    it("puts your price first when it is under the whole book", function()
      local b = GC.SellViewModel.Expansion(position({ levels = ladder(3, function(i) return 1000 + i * 10 end),
        postRecommendation = { unit = 900 } })).book
      assert.equal("yours 1010 1020 1030", kinds(b))
      assert.equal(0, b.ahead)
    end)

    it("keeps the cheapest eight when there is no price of yours", function()
      local b = GC.SellViewModel.Expansion(position({ levels = ladder(20, function(i) return 1000 + i * 10 end),
        postRecommendation = "\0NONE" })).book
      assert.equal("1010 1020 1030 1040 1050 1060 1070 1080", kinds(b))
      assert.is_nil(b.yourRow)
    end)

    it("counts the units at your exact price as ahead of you, and never your own", function()
      local levels = {
        { unitPrice = 1000, quantity = 10 },
        { unitPrice = 1100, quantity = 20, ownerQty = 5 },
        { unitPrice = 1200, quantity = 30 },
      }
      assert.equal(25, GC.SellViewModel.UnitsAhead(levels, 1100))
      assert.equal(10, GC.SellViewModel.UnitsAhead(levels, 1099))
      assert.equal(55, GC.SellViewModel.UnitsAhead(levels, 5000))
      assert.equal(0, GC.SellViewModel.UnitsAhead(levels, 999))
      assert.is_nil(GC.SellViewModel.UnitsAhead({}, 1000))
      assert.is_nil(GC.SellViewModel.UnitsAhead(levels, nil))
      local b = GC.SellViewModel.Expansion(position({ levels = levels, postRecommendation = { unit = 1100 } })).book
      assert.equal(25, b.ahead)
      assert.equal(25, b.rows[b.yourRow].ahead)
    end)

    -- A wall is a level holding a big share of the day: pricing under it sells first, at or
    -- over it waits for the whole thing. The player's own units in a level are not a wall.
    it("marks a level holding a quarter of a day's sales or more as a wall", function()
      local levels = {
        { unitPrice = 1000, quantity = 90 },
        { unitPrice = 1100, quantity = 150, ownerQty = 60 },
        { unitPrice = 1200, quantity = 120 },
        { unitPrice = 1300, quantity = 400 },
      }
      local b = GC.SellViewModel.Expansion(position({ levels = levels, soldPerDay = 400,
        postRecommendation = { unit = 1250 } })).book
      local walls = {}
      for _, row in ipairs(b.rows) do if row.kind == "level" and row.wall then walls[#walls + 1] = row.unit end end
      assert.same({ 1200, 1300 }, walls)
      -- The nearest at or under your price, and the first above it.
      assert.same({ unit = 1200, units = 120 }, b.wallBelow)
      assert.same({ unit = 1300, units = 400 }, b.wallAbove)
    end)

    it("takes the biggest level as the wall when the day's sales are unknown", function()
      local levels = {
        { unitPrice = 1000, quantity = 90 },
        { unitPrice = 1100, quantity = 150, ownerQty = 100 },
        { unitPrice = 1200, quantity = 120 },
      }
      local b = GC.SellViewModel.Expansion(position({ levels = levels, soldPerDay = "\0NONE",
        postRecommendation = { unit = 1000 } })).book
      local walls = {}
      for _, row in ipairs(b.rows) do if row.kind == "level" and row.wall then walls[#walls + 1] = row.unit end end
      assert.same({ 1200 }, walls)
      assert.is_nil(b.wallBelow)
      assert.same({ unit = 1200, units = 120 }, b.wallAbove)
    end)

    it("says how long the queue ahead takes at today's pace, and nothing without one", function()
      local levels = { { unitPrice = 1000, quantity = 250 }, { unitPrice = 1100, quantity = 50 } }
      local b = GC.SellViewModel.Expansion(position({ levels = levels, soldPerDay = 1000,
        postRecommendation = { unit = 1050 } })).book
      assert.equal(6, b.hoursToReach)
      b = GC.SellViewModel.Expansion(position({ levels = levels, soldPerDay = "\0NONE",
        postRecommendation = { unit = 1050 } })).book
      assert.is_nil(b.hoursToReach)
      b = GC.SellViewModel.Expansion(position({ levels = levels, soldPerDay = 1000,
        postRecommendation = { unit = 900 } })).book
      assert.is_nil(b.hoursToReach) -- nothing ahead: nothing to wait for
    end)

    -- The quote reads at most BOOK_READ_MAX price levels. A price past the last one read has at
    -- least everything read in front of it, and an unknown amount more: never a made-up count.
    -- "The read stopped" is the read's own flag (the quote driver sets `levels.cut` when the
    -- client held more than it read, or not its full answer) -- never a count that merely
    -- happens to equal the cap (review M5).
    it("says a price past the levels read has at least that much ahead, never a count", function()
      local read = GC.SellViewModel.BOOK_READ_MAX
      local levels = ladder(read, function(i) return 1000 + i end)
      levels.cut = true
      local b = GC.SellViewModel.Expansion(position({ soldPerDay = 1000, levels = levels,
        postRecommendation = { unit = 99999 } })).book
      assert.is_true(b.pastRead)
      assert.equal(read, b.levels)
      assert.equal(read * 10, b.totalUnits)
      assert.equal(read * 10, b.ahead)
      assert.is_nil(b.hoursToReach)
      assert.equal("yours", b.rows[#b.rows].kind)
      -- A book that ended before the cut is the whole book: the count is exact -- even one of
      -- exactly the cap's size.
      b = GC.SellViewModel.Expansion(position({ levels = ladder(read, function(i) return 1000 + i end),
        postRecommendation = { unit = 99999 } })).book
      assert.is_false(b.pastRead)
    end)

    -- A realm item's book is lots, not a queue: it keeps the view it had.
    it("keeps a realm item on the cheapest eight, pointing at the level your price joins", function()
      local b = GC.SellViewModel.Expansion(position({ positionKey = "item:42:600:0:0",
        levels = ladder(20, function(i) return 1000 + i * 10 end), postRecommendation = { unit = 1035 } })).book
      assert.equal("1010 1020 1030 1040 1050 1060 1070 1080", kinds(b))
      assert.equal(4, b.yourRow)
      assert.is_nil(b.ahead)
    end)

    -- One count, said in two places: the reason under the price and the marker in the book.
    it("gives the strategy line the marker's own count", function()
      local levels = {
        { unitPrice = 1000, quantity = 300 },
        { unitPrice = 1100, quantity = 2021 },
        { unitPrice = 1200, quantity = 42000 },
      }
      local d = GC.SellViewModel.Expansion(position({ levels = levels, coverage = "COMPLETE",
        postRecommendation = { unit = 1100, mode = "overcut", ahead = 300, capBy = "reach" } }))
      assert.equal(2321, d.book.ahead)
      assert.is_truthy(d.factsText:find("within the day's reach · 2.3k units ahead of you", 1, true), d.factsText)
    end)

    -- "~Xh to reach you" and "clears in" answer one sale: the queue ahead, then your own units
    -- after it. Both from the same sells/day and the same trend rule, so the second can never
    -- be the smaller (owner's numbers: 2,321 ahead, 9,867/day, 300 in the bags) -- review I1.
    it("times the queue ahead and your own clearing from one pace, the second never shorter", function()
      local b = GC.SellViewModel.Expansion(position({ soldPerDay = 9867, bagQty = 300, postableQty = 300,
        levels = { { unitPrice = 1000, quantity = 2321 }, { unitPrice = 1200, quantity = 42000 } },
        postRecommendation = { unit = 1100 } })).book
      assert.equal(6, math.floor(b.hoursToReach + 0.5))
      assert.equal(6, math.floor(b.clearsHours + 0.5))
      assert.is_true(b.clearsHours > b.hoursToReach)
      -- A falling market slows both the same way.
      local slow = GC.SellViewModel.Expansion(position({ soldPerDay = 9867, bagQty = 300, postableQty = 300,
        trendPct = -20, levels = { { unitPrice = 1000, quantity = 2321 } },
        postRecommendation = { unit = 1100 } })).book
      assert.is_true(slow.hoursToReach > b.hoursToReach)
      assert.is_true(slow.clearsHours > slow.hoursToReach)
    end)

    -- Your own older lots at or under the price sell before the new post: the times count them
    -- in the queue, though the marker's "N ahead" -- what competes with you -- does not. And
    -- "yours ×N" is every unit of yours the book read, not only the levels drawn (final review M6).
    it("times the queue with your own older lots in it, and counts all of yours", function()
      local levels = { { unitPrice = 1000, quantity = 2321 }, { unitPrice = 1050, quantity = 1000, ownerQty = 1000 },
        { unitPrice = 1200, quantity = 500, ownerQty = 200 } }
      for i = 1, 12 do levels[#levels + 1] = { unitPrice = 1200 + i * 10, quantity = 10 } end
      levels[#levels + 1] = { unitPrice = 5000, quantity = 30, ownerQty = 30 }
      local b = GC.SellViewModel.Expansion(position({ soldPerDay = 9867, bagQty = 300, postableQty = 300,
        levels = levels, postRecommendation = { unit = 1100 } })).book
      assert.equal(2321, b.ahead) -- what competes: the marker's
      assert.equal(8, math.floor(b.hoursToReach + 0.5)) -- 3,321 ahead of the post at 9,867/day
      assert.equal(9, math.floor(b.clearsHours + 0.5))
      assert.equal(1230, b.ownUnits) -- the 30 at 50g too, though no line draws it
    end)

    -- A price the seller chose is not GoldCap's: the reason for GoldCap's price, and its count at
    -- GoldCap's price, would stand under the box as a second "units ahead" (review I2).
    it("gives a chosen price no reason and no second count", function()
      local d = GC.SellViewModel.Expansion(position({ coverage = "COMPLETE",
        levels = { { unitPrice = 1000, quantity = 300 }, { unitPrice = 1100, quantity = 2021 },
          { unitPrice = 1200, quantity = 42000 } },
        postRecommendation = { unit = 1000, mode = "chosen" },
        recommendation = { unit = 1100, mode = "overcut", ahead = 300, capBy = "reach" } }))
      assert.equal(300, d.book.ahead)
      assert.is_nil((d.factsText or ""):find("ahead of you", 1, true))
    end)

    -- A realm item's reason line counts the way its row does: strictly under the price, less the
    -- player's own -- lots at an equal price are not a queue there (review M7).
    it("counts a realm item's reason line the way its row counts", function()
      local d = GC.SellViewModel.Expansion(position({ positionKey = "item:42:600:0:0", coverage = "COMPLETE",
        levels = { { unitPrice = 1000, quantity = 3 }, { unitPrice = 1100, quantity = 2 } },
        postRecommendation = { unit = 1100, mode = "overcut", ahead = 5, capBy = "reach" } }))
      assert.is_truthy(d.factsText:find("· 3 units ahead of you", 1, true), d.factsText)
    end)

    -- On a slow or flat book "wall" stopped meaning anything: at 4 a day every 2-unit level was
    -- one, and with sales unknown every level tied for biggest was (review M3).
    it("calls nothing a wall on a thin or flat book", function()
      local thin = GC.SellViewModel.Expansion(position({ soldPerDay = 4, postRecommendation = { unit = 1035 },
        levels = ladder(6, function(i) return 1000 + i * 10 end, function() return 2 end) })).book
      local flat = GC.SellViewModel.Expansion(position({ soldPerDay = "\0NONE", postRecommendation = { unit = 1035 },
        levels = ladder(6, function(i) return 1000 + i * 10 end, function() return 50 end) })).book
      for _, b in ipairs({ thin, flat }) do
        for _, row in ipairs(b.rows) do assert.is_falsy(row.wall) end
        assert.is_nil(b.wallBelow)
        assert.is_nil(b.wallAbove)
      end
    end)

    -- With sales unknown the single biggest level is named -- but never one of a few units: a
    -- 3-unit level over 1-unit ones is no wall (review N4).
    it("keeps the size floor for a wall when the day's sales are unknown", function()
      local levels = ladder(6, function(i) return 1000 + i * 10 end, function() return 1 end)
      levels[4].quantity = 3
      local b = GC.SellViewModel.Expansion(position({ soldPerDay = "\0NONE", postRecommendation = { unit = 1035 },
        levels = levels })).book
      for _, row in ipairs(b.rows) do assert.is_falsy(row.wall) end
    end)
  end)
end)
