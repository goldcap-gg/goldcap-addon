local helper = require("spec.spec_helper")

describe("Sell positions", function()
  local GC
  local context = { char = "A-R", region = "eu" }

  local function batch(id, source, qty, total, at, char, region, itemID, positionKey)
    return { id = id, source = source, itemID = itemID or 42, positionKey = positionKey or "commodity:42",
      remainingQty = qty, remainingTotal = total, acquiredAt = at,
      character = char or context.char, region = region or context.region }
  end

  local function lot(positionKey, quantity, unitPrice, auctionID, firstSeenAt)
    return { itemID = 42, positionKey = positionKey or "commodity:42", quantity = quantity,
      unitPrice = unitPrice, auctionID = auctionID, firstSeenAt = firstSeenAt or 1 }
  end

  local function build(args)
    args = args or {}
    args.acquisitions = args.acquisitions or {}
    args.ownedLots = args.ownedLots or {}
    args.quotes = args.quotes or {}
    args.statsByItemID = args.statsByItemID or {}
    args.context = args.context or context
    args.now = args.now or 10
    return GC.SellPositions.Build(args)
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    GC = helper.loadModule("Core/Flips.lua", GC)
    GC = helper.loadModule("Core/QuoteCache.lua", GC)
    GC = helper.loadModule("Core/SellPositions.lua", GC)
  end)

  -- The wiring, not just the capability. The first attempt at this fix worked in a spec that
  -- handed Build raw batches and did nothing at all in the client, because the client's own
  -- call site filters spent batches out before Build ever sees them.
  it("[wiring] the Sell tab actually supplies identity evidence to Build", function()
    local file = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local text = file:read("*a")
    file:close()
    assert.is_truthy(text:find("GC.Acquisitions.GetIdentityEvidence(scope)", 1, true))
    assert.is_truthy(text:find("identityEvidence = identityEvidence", 1, true))
  end)

  local function activity(positionKey, itemID, itemName, at)
    return { positionKey = positionKey, itemID = itemID or 42, itemName = itemName or "Herb",
      firstSeenAt = at or 1, character = context.char, region = context.region,
      scopeKey = table.concat({ context.region, context.char, positionKey }, "\1") }
  end

  local function sale(itemName, at, pending)
    return { kind = "sale", source = "mail", char = context.char, region = context.region,
      key = "mail:" .. (itemName or "Herb") .. ":" .. tostring(at or 5),
      itemName = itemName or "Herb", at = at or 5, pending = pending, qty = 1 }
  end

  -- A paid sale is the NORMAL end of owning something, not an anomaly. The merge branch used to
  -- require `pending == true`, so every settled sale fell through to a REPAIR_SALE row with no
  -- itemID, no icon and no numbers -- and they accumulate forever, because nothing ever makes a
  -- paid sale pending again.
  it("attaches a settled sale to its position instead of filing a repair row", function()
    local positions = build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      activities = { activity("commodity:42", 42, "Herb", 1) },
      sellerEvidence = { sale("Herb", 5, false) },
    })

    assert.equal(1, #positions)
    assert.is_nil(positions[1].unresolved)
    assert.equal(1, #positions[1].sellerEvidence)
    -- ...and it must not be mislabelled as still awaiting payment.
    assert.is_not_true(positions[1].facts.soldPending)
  end)

  -- The other half of the same rule: a settled sale attaches to a position that exists for
  -- another reason, but never conjures one. With nothing bought, held or listed, a paid sale
  -- from the ledger used to leave a permanent row with a dash in every column (the third
  -- in-game pass found dozens of "items I sold long ago").
  it("does not create a position for a settled sale of stock that is no longer held", function()
    local positions = build({
      activities = { activity("commodity:42", 42, "Herb", 1) },
      sellerEvidence = { sale("Herb", 5, false) },
    })
    assert.equal(0, #positions)
  end)

  it("still creates a position for a pending sale of stock that is no longer held", function()
    local positions = build({
      activities = { activity("commodity:42", 42, "Herb", 1) },
      sellerEvidence = { sale("Herb", 5, true) },
    })
    assert.equal(1, #positions)
    assert.is_true(positions[1].facts.soldPending)
    assert.equal(1, #positions[1].sellerEvidence)
  end)

  -- The wiring again: the absorb window and spike threshold are player settings, and this is
  -- the one place they cross from GC.db into the sell-side recommendation.
  it("hands the configured absorb window and spike threshold to the post recommendation", function()
    GC.db = { settings = { sniper = { wallAbsorbHours = 4, spikeTrendPct = 55 } } }
    local seen
    GC.Flips.RecommendPost = function(_, _, _, opts) seen = opts end
    build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      activities = { activity("commodity:42", 42, "Herb", 1) },
    })
    assert.is_table(seen)
    assert.equal(4, seen.absorbHours)
    assert.equal(55, seen.spikePct)
  end)

  -- The cheap-quarter line crosses from the import (statsByItemID.p25) into the sell-side
  -- recommendation here and nowhere else, and only while the player has overcut on.
  it("hands the cheap-quarter line to the post recommendation while overcut is on", function()
    GC.db = { settings = { sniper = { overcut = true } } }
    local seen
    GC.Flips.RecommendPost = function(_, _, _, opts) seen = opts end
    build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      activities = { activity("commodity:42", 42, "Herb", 1) },
      statsByItemID = { [42] = { mv = 20000, sold = 40, p25 = 21000 } },
    })
    assert.equal(21000, seen.quarterUnit)
  end)

  it("withholds the cheap-quarter line when overcut is off", function()
    GC.db = { settings = { sniper = { overcut = false } } }
    local seen
    GC.Flips.RecommendPost = function(_, _, _, opts) seen = opts end
    build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      activities = { activity("commodity:42", 42, "Herb", 1) },
      statsByItemID = { [42] = { mv = 20000, sold = 40, p25 = 21000 } },
    })
    assert.is_nil(seen.quarterUnit)
  end)

  -- The reach line crosses the same seam, from statsByItemID.reach, and rides alongside the
  -- quarter line rather than replacing it: RecommendPost decides which one binds.
  it("hands the reach line to the post recommendation while overcut is on", function()
    GC.db = { settings = { sniper = { overcut = true } } }
    local seen
    GC.Flips.RecommendPost = function(_, _, _, opts) seen = opts end
    build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      activities = { activity("commodity:42", 42, "Herb", 1) },
      statsByItemID = { [42] = { mv = 20000, sold = 40, p25 = 21000, reach = 20500 } },
    })
    assert.equal(20500, seen.reachUnit)
    assert.equal(21000, seen.quarterUnit)
  end)

  it("withholds the reach line when overcut is off", function()
    GC.db = { settings = { sniper = { overcut = false } } }
    local seen
    GC.Flips.RecommendPost = function(_, _, _, opts) seen = opts end
    build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      activities = { activity("commodity:42", 42, "Herb", 1) },
      statsByItemID = { [42] = { mv = 20000, sold = 40, p25 = 21000, reach = 20500 } },
    })
    assert.is_nil(seen.reachUnit)
  end)

  it("hands the same cheap-quarter line to the repost advice for a listed lot", function()
    GC.db = { settings = { sniper = {} } }
    local seen
    GC.Flips.RepostAdvice = function(args) seen = args; return nil end
    build({
      acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
      ownedLots = { lot("commodity:42", 2, 20000, 1) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 10000, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 4, p25 = 16000, reach = 15500 } },
    })
    assert.equal(16000, seen.quarterUnit)
    assert.equal(15500, seen.reachUnit)
  end)

  -- The displayed recommendation and the price Post uses must be one number. The plan already
  -- raises for the queue-at-exit mode; overcut is the same asymmetry (a raise can only delay a
  -- sale, never underprice one).
  it("lists bag stock at the overcut rung, not the cheapest ask", function()
    GC.db = { settings = { sniper = {} } }
    local ladder = {
      { unitPrice = 10000, quantity = 400 }, { unitPrice = 10500, quantity = 300 },
      { unitPrice = 11000, quantity = 300 }, { unitPrice = 12000, quantity = 2000 },
    }
    local p = build({
      bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 50,
        isCommodity = true } },
      quotes = { [42] = { unit = 10000, at = 9, levels = ladder } },
      statsByItemID = { [42] = { mv = 12000, sold = 4000, reach = 11000 } },
    })[1]
    assert.equal("overcut", p.postRecommendation.mode)
    assert.equal(11000, p.postRecommendation.unit)

    local plan, reason = GC.SellPositions.BuildPostPlan(p,
      { itemID = 42, exactQty = 50, positionKey = "commodity:42" }, { unit = 10000, fresh = true })
    assert.is_nil(reason)
    assert.equal(11000, plan.unitPrice)
  end)

  -- The same wiring, checked at the OTHER call site. `recommendation` (COMPLETE, nothing listed)
  -- and `postRecommendation` (bag stock, computed independently) both build a RecommendPost
  -- options table, and both carry a queue-at-exit targetUnit here -- so both must carry the
  -- SAME spikePct, or a player who set a custom settings.sniper.spikeTrendPct would see PROFIT
  -- / UNIT and the Post price agree on ordinary positions (single call site fires) and quietly
  -- disagree the moment a position has both a live listing (recommendation goes RepostAdvice-
  -- shaped, a path that never took a spikePct) AND bag stock (postRecommendation, which used to
  -- drop it). RepostAdvice's own internal RecommendPost call fires first here and is captured
  -- by `seen` same as before it is overwritten by postRecommendation's own call -- the one this
  -- test actually verifies, since it is the last to run.
  it("hands the same spike threshold to the bag-stock post recommendation as the listed-lot branch", function()
    GC.db = { settings = { sniper = { spikeTrendPct = 55 } } }
    local seen
    GC.Flips.RecommendPost = function(_, _, _, opts) seen = opts end
    build({
      acquisitions = { batch("acq:1", "goldcap", 100, 1000000, 1) },
      ownedLots = { lot("commodity:42", 50, 15000, 1) },
      bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 50,
        isCommodity = true } },
      quotes = { [42] = { unit = 20000, at = 9 } },
    })
    assert.is_table(seen)
    assert.equal(55, seen.spikePct)
  end)

  -- Two activity rows for ONE item, differing only in commodity-vs-item form, is bookkeeping
  -- damage rather than a real question about which item was sold. When the purchase record
  -- proves which key is the item's real identity, that settles it.
  it("resolves a sale whose only ambiguity is a stale duplicate key", function()
    local positions = build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1) },
      identityEvidence = { { itemID = 42, positionKey = "commodity:42" } },
      activities = {
        activity("commodity:42", 42, "Herb", 1),
        activity("item:42:23:0:0", 42, "Herb", 1),
      },
      sellerEvidence = { sale("Herb", 5, false) },
    })

    local unresolved = 0
    for _, position in ipairs(positions) do
      if position.unresolved then unresolved = unresolved + 1 end
    end
    assert.equal(0, unresolved)
  end)

  -- But a genuine variant question stays a question. Two different item variants of one itemID
  -- are two different things to sell, and guessing between them misreports what a sale earned.
  -- Pinned on a PENDING sale, because that is the only kind that still earns a row at all --
  -- see the settled case immediately below.
  it("still refuses a sale split across two genuine variants", function()
    local positions = build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1, nil, nil, nil, "item:42:23:0:0") },
      activities = {
        activity("item:42:23:0:0", 42, "Herb", 1),
        activity("item:42:80:0:0", 42, "Herb", 1),
      },
      sellerEvidence = { sale("Herb", 5, true) },
    })

    local ambiguous = 0
    for _, position in ipairs(positions) do
      if position.unresolvedKind == "ambiguous_sale" then ambiguous = ambiguous + 1 end
    end
    assert.equal(1, ambiguous)
  end)

  -- One itemID cannot be both a commodity and a variant item, so an activity set holding
  -- `commodity:X` beside `item:X:...` is provable corruption -- a fossil from before owned lots
  -- were classified, when GetOwnedAuctions reported no isCommodity and every lot was filed
  -- under an item-style key. The purchase record settles it when there is one. When there is
  -- not -- and on a live client there was not, for an item with no purchases at all -- the
  -- client's OWN answer settles it: `commodityByItem` is what C_AuctionHouse.GetItemKeyInfo
  -- said, cached in SavedVariables, and it is a better authority on this question than an
  -- inference from what happened to have been bought.
  it("settles a commodity-versus-item contradiction from the client's own item key info", function()
    local positions = build({
      activities = {
        activity("commodity:42", 42, "Herb", 1),
        activity("item:42:80:0:0", 42, "Herb", 1),
      },
      ownedLots = { lot("commodity:42", 1, 200, 1) },
      commodityKinds = { [42] = true },
      sellerEvidence = { sale("Herb", 5, true) },
    })
    for _, position in ipairs(positions) do
      assert.not_equal("ambiguous_sale", position.unresolvedKind)
    end
    local attached
    for _, position in ipairs(positions) do
      if position.positionKey == "commodity:42" and #(position.sellerEvidence or {}) > 0 then
        attached = position
      end
    end
    assert.is_not_nil(attached)
  end)

  -- Two genuine variants of one itemID do NOT contradict each other -- they are two different
  -- things to sell -- so the cache cannot settle that one, and it stays a question.
  it("does not let item key info choose between two genuine variants", function()
    local positions = build({
      activities = {
        activity("item:42:23:0:0", 42, "Herb", 1),
        activity("item:42:80:0:0", 42, "Herb", 1),
      },
      commodityKinds = { [42] = false },
      sellerEvidence = { sale("Herb", 5, true) },
    })
    local ambiguous = 0
    for _, position in ipairs(positions) do
      if position.unresolvedKind == "ambiguous_sale" then ambiguous = ambiguous + 1 end
    end
    assert.equal(1, ambiguous)
  end)

  -- The Sell tab has to reach the SAME answer the ledger reaches, or the two disagree about
  -- which position a sale belonged to. Same signal, same shape: the price it sold at.
  it("attributes a same-name sale to the position listed at that price", function()
    local listed = activity("commodity:42", 42, "Herb", 1)
    listed.listedUnits = { [345900] = 1 }
    local other = activity("commodity:43", 43, "Herb", 1)
    other.listedUnits = { [65500] = 1 }
    local positions = build({
      activities = { listed, other },
      ownedLots = { lot("commodity:42", 1, 345900, 1) },
      sellerEvidence = { { key = "mail:priced", kind = "sale", source = "mail", itemName = "Herb",
        qty = 1, total = 345900, at = 5, char = context.char, region = context.region,
        pending = true } },
    })
    for _, position in ipairs(positions) do
      assert.not_equal("ambiguous_sale", position.unresolvedKind)
    end
    local attached
    for _, position in ipairs(positions) do
      if position.positionKey == "commodity:42" and #(position.sellerEvidence or {}) > 0 then
        attached = position
      end
    end
    assert.is_not_nil(attached)
  end)

  -- ...and a SETTLED one that cannot be attributed makes no row at all, the same way a settled
  -- one that CAN be attributed never creates a position. A live client had seven of these --
  -- four of them the same reagent, whose quality ranks share one item name -- with no itemID,
  -- no icon, a dash in every column and no action that could ever clear them. "They were sold,
  -- and they are still sitting here." The sale is not lost: Sold still says `cost unknown` on
  -- that exact invoice, which is where an unattributable sale belongs.
  it("makes no row for a settled sale it cannot attribute", function()
    local positions = build({
      acquisitions = { batch("acq:1", "auction_house", 3, 300, 1, nil, nil, nil, "item:42:23:0:0") },
      activities = {
        activity("item:42:23:0:0", 42, "Herb", 1),
        activity("item:42:80:0:0", 42, "Herb", 1),
      },
      sellerEvidence = { sale("Herb", 5, false) },
    })
    for _, position in ipairs(positions) do
      assert.not_equal("ambiguous_sale", position.unresolvedKind)
      assert.not_equal("REPAIR_SALE", position.status)
    end
  end)

  it("normalizes every owned auction into an independently priced position lot", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 2, unitPrice = 90, auctionID = 2 },
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 3, unitPrice = 120, auctionID = 3 },
    }, 77)
    assert.same({
      { positionKey = "commodity:42", itemID = 42, quantity = 2, unitPrice = 90,
        auctionID = 2, firstSeenAt = 77, isCommodity = true },
      { positionKey = "commodity:42", itemID = 42, quantity = 3, unitPrice = 120,
        auctionID = 3, firstSeenAt = 77, isCommodity = true },
    }, lots)
  end)

  it("carries expiresAt as seenAt + timeLeftSeconds when the auction reports one", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 2, unitPrice = 90,
        auctionID = 2, timeLeftSeconds = 3600 },
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 3, unitPrice = 120,
        auctionID = 3 }, -- no timeLeftSeconds reported
    }, 1000)
    assert.equal(4600, lots[1].expiresAt)
    assert.is_nil(lots[2].expiresAt)
  end)

  it("does not treat a non-positive or fractional timeLeftSeconds as an expiry", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 1, unitPrice = 90,
        auctionID = 2, timeLeftSeconds = 0 },
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 1, unitPrice = 90,
        auctionID = 3, timeLeftSeconds = -5 },
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 1, unitPrice = 90,
        auctionID = 4, timeLeftSeconds = 12.5 },
    }, 1000)
    assert.is_nil(lots[1].expiresAt)
    assert.is_nil(lots[2].expiresAt)
    assert.is_nil(lots[3].expiresAt)
  end)

  it("does not attach accounting state to a caller-owned auction lot", function()
    local ownedLot = lot("commodity:42", 1, 200, 1)
    build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) }, ownedLots = { ownedLot } })
    assert.is_nil(ownedLot.allocation)
  end)

  it("groups mixed-source batches and counts one owned lot once", function()
    local positions = build({
      acquisitions = {
        batch("acq:1", "goldcap", 100, 1000, 1),
        batch("acq:2", "auction_house", 50, 600, 2),
      },
      ownedLots = { lot("commodity:42", 120, 20, 9001) },
    })
    assert.equal(1, #positions)
    assert.same({ auction_house = 50, goldcap = 100 }, positions[1].sources)
    assert.equal(120, positions[1].listedQty)
    assert.equal(120, positions[1].knownQty)
    assert.equal(1240, positions[1].knownCost)
    assert.equal("COMPLETE", positions[1].coverage)
  end)

  it("does not double project one listing across two purchase batches", function()
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", 100, 1000, 1), batch("acq:2", "auction_house", 50, 600, 2),
    }, ownedLots = { lot("commodity:42", 120, 20, 9001) } })[1]
    assert.equal(2280, p.projectedNet)
    assert.equal(1040, p.profit)
  end)

  it("renders partial cost without fabricated profit", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 100, 1000, 1) },
      ownedLots = { lot("commodity:42", 150, 20, 9001) } })[1]
    assert.equal("PARTIAL", p.coverage)
    assert.equal(100, p.knownQty)
    assert.equal(150, p.exposureQty)
    assert.is_nil(p.profit)
  end)

  -- The live incident (2026-08-18): a position held two cost tranches -- 24 units listed on
  -- the AH, bought first at 170g88s each, and 94 units sitting in the bags, bought later at
  -- 86g08s51c each. `accountedExposure` capped the allocation at the listed 24 the instant
  -- anything was listed, so the FIFO walk only ever reached the oldest (expensive) batch and
  -- the 94 cheap units in the bags were invisible to COST/UNIT -- the row read as a loss that
  -- was not real. The fix: the allocation quantity is everything the player physically holds
  -- right now (listed + bags), not whichever slice happens to be listed.
  describe("cost covers everything the player holds, not just the listed slice", function()
    it("blends both tranches once units are both listed and in the bags", function()
      local p = build({
        acquisitions = {
          batch("acq:listed", "auction_house", 24, 41011900, 1),
          batch("acq:bags", "goldcap", 94, 80920000, 2),
        },
        ownedLots = { lot("commodity:42", 24, 1708800, 9001) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 94, isCommodity = true } },
      })[1]
      assert.equal(24, p.listedQty)
      assert.equal(94, p.bagQty)
      -- knownQty must cover EVERYTHING held (24 + 94 = 118), not just the 24 that are listed.
      assert.equal(118, p.knownQty)
      -- 41011900 (the 24 listed) + 80920000 (the 94 in bags) = 121931900, the full blended
      -- cost across both tranches -- not just the expensive listed 24.
      assert.equal(121931900, p.knownCost)
      assert.equal("COMPLETE", p.coverage)
      -- 121931900 / 118 = 1033321 remainder 22 (floor, same rounding SellFrame.lua's COST/UNIT
      -- column already applies) -- the real blended per-unit cost, nowhere near the 1708800
      -- (170g88s) the incident showed by only ever costing the listed slice.
      assert.equal(1033321, math.floor(p.knownCost / p.knownQty))
    end)

    it("costs bag-only stock against what is actually in the bags, not the full tracked total", function()
      -- trackedQty is 150 (50 + 100 bought) but only 90 remain in the bags -- the other 60 are
      -- elsewhere (sold, mailed, whatever). The cost basis must stop at what is physically
      -- held, or a position that has partly moved on reports a cost basis wider than its stock.
      local p = build({
        acquisitions = {
          batch("acq:a", "goldcap", 50, 500000, 1),
          batch("acq:b", "goldcap", 100, 1500000, 2),
        },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 90, isCommodity = true } },
      })[1]
      assert.equal(0, p.listedQty)
      assert.equal(90, p.bagQty)
      assert.equal(150, p.trackedQty)
      assert.equal(90, p.knownQty)
      -- FIFO: 50 units @ 10000/unit (500000) + 40 units @ 15000/unit (600000) = 1100000.
      assert.equal(1100000, p.knownCost)
      assert.equal("COMPLETE", p.coverage)
    end)

    it("costs listed-only stock exactly as before when nothing sits in the bags", function()
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 100, 1000, 1), batch("acq:2", "auction_house", 50, 600, 2) },
        ownedLots = { lot("commodity:42", 120, 20, 9001) },
      })[1]
      assert.equal(120, p.listedQty)
      assert.equal(0, p.bagQty)
      assert.equal(120, p.knownQty)
      assert.equal(1240, p.knownCost)
      assert.equal("COMPLETE", p.coverage)
    end)

    it("reports partial coverage when what is held exceeds what is tracked", function()
      -- 15 listed + 10 in the bags = 25 held, but only 20 units were ever tracked as bought.
      -- Held CAN exceed tracked (untracked/farmed stock sitting alongside a tracked purchase);
      -- coverage must say PARTIAL, not silently cap at whatever the batches can prove.
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 20, 200000, 1) },
        ownedLots = { lot("commodity:42", 15, 15000, 9001) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 10, isCommodity = true } },
      })[1]
      assert.equal(15, p.listedQty)
      assert.equal(10, p.bagQty)
      assert.equal(20, p.trackedQty)
      assert.equal(20, p.knownQty)
      assert.equal(200000, p.knownCost)
      assert.equal("PARTIAL", p.coverage)
      assert.is_nil(p.profit)
    end)

    -- PROFIT/UNIT must describe the same unit-set as the cost it was subtracted from: listed
    -- units project at their listed price, bag units at the row's post recommendation, and both
    -- join the SAME gross that knownCost (listed + bags) is compared against.
    it("projects bag revenue alongside listed revenue so profit is not priced against a narrower cost", function()
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
        ownedLots = { lot("commodity:42", 1, 300, 1) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 1, isCommodity = true } },
        quotes = { [42] = { unit = 100, at = 9 } },
      })[1]
      assert.equal(2, p.knownQty)
      assert.equal(200, p.knownCost)
      assert.equal("COMPLETE", p.coverage)
      -- Listed unit projects at min(300, 100) = 100 (no queue-at-exit target on this batch).
      -- Bag unit has no postRecommendation.unit here (RecommendPost needs more to fire a
      -- candidate for a paid-basis row without levels/sold), so it falls back to the fresh
      -- quote, 100, same as the listed unit. Gross = (100 + 100) * 0.95 = 190.
      assert.equal(190, p.projectedNet)
      assert.equal(-10, p.profit)
    end)

    -- The bug this batch exists to fix: PostFloor (mv * 0.75) can hold postRecommendation.unit
    -- ABOVE the live ask, and the bag-only branch above prices PROFIT/UNIT at that held price --
    -- correctly, it IS the price GoldCap would post at -- but nothing on the row said so, and a
    -- seller reading a green number assumed it was ordinary market profit. mv = 20000 pushes the
    -- floor to 15000, well above the live ask of 10000, so RecommendPost's match candidate
    -- (10000) gets overridden to the floor (15000, already whole-silver) before this position's
    -- profit is ever computed.
    it("prices bag-only profit at the held recommendation and flags it, when PostFloor holds the price above the live ask", function()
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 2, isCommodity = true } },
        quotes = { [42] = { unit = 10000, at = 9 } },
        statsByItemID = { [42] = { mv = 20000 } },
      })[1]
      assert.equal(0, p.listedQty)
      assert.equal(2, p.bagQty)
      assert.equal("COMPLETE", p.coverage)
      assert.equal(15000, p.postRecommendation.unit)
      -- Priced at the held 15000/unit, not the live 10000 ask: netFor(2, 15000) = 30000 * 0.95 = 28500.
      assert.equal(28500, p.projectedNet)
      assert.equal(8500, p.profit)
      assert.equal(15000, p.profitAtHold)
    end)

    -- Same shape, no mv: PostFloor refuses without one, so RecommendPost's own match candidate
    -- (10000, the live ask itself) stands unmodified -- the ordinary case, where the
    -- recommendation never rose above the market it is quoted against.
    it("leaves the hold flag absent when the recommendation never rises above the live ask", function()
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 2, isCommodity = true } },
        quotes = { [42] = { unit = 10000, at = 9 } },
      })[1]
      assert.equal("COMPLETE", p.coverage)
      assert.equal(10000, p.postRecommendation.unit)
      assert.is_nil(p.profitAtHold)
      assert.is_not_nil(p.profit)
    end)

    -- The mixed branch prices bag units the same way the bag-only branch does -- at
    -- postRecommendation.unit, floor raises included -- so when PostFloor holds that price
    -- above the live ask, its PROFIT rests on the same hold and needs the same flag. Same
    -- inputs as the bag-only hold spec above, split 1 listed + 1 in the bags: the listed
    -- unit projects at the 10000 ask, the bag unit at the held 15000.
    it("flags the hold on a mixed listed+bag position when PostFloor holds the bag price above the live ask", function()
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
        ownedLots = { lot("commodity:42", 1, 10000, 9001) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 1, isCommodity = true } },
        quotes = { [42] = { unit = 10000, at = 9 } },
        statsByItemID = { [42] = { mv = 20000 } },
      })[1]
      assert.equal(1, p.listedQty)
      assert.equal(1, p.bagQty)
      assert.equal("COMPLETE", p.coverage)
      assert.equal(15000, p.postRecommendation.unit)
      -- Gross = listed 10000 + bag at the held 15000 = 25000; net = 25000 * 0.95 = 23750.
      assert.equal(23750, p.projectedNet)
      assert.equal(3750, p.profit)
      assert.equal(15000, p.profitAtHold)
    end)

    -- And the mirror: same mixed split, no mv, so the recommendation (10000) matches the ask
    -- rather than rising above it, and the flag stays absent.
    it("leaves the hold flag absent on a mixed position when the recommendation stays under the ask", function()
      local p = build({
        acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
        ownedLots = { lot("commodity:42", 1, 10000, 9001) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 1, isCommodity = true } },
        quotes = { [42] = { unit = 10000, at = 9 } },
      })[1]
      assert.equal("COMPLETE", p.coverage)
      assert.equal(10000, p.postRecommendation.unit)
      assert.is_nil(p.profitAtHold)
      assert.is_not_nil(p.profit)
    end)
  end)

  it("[FINAL I2] applies the auction cut once to aggregate multi-lot gross", function()
    local tiny = build({ acquisitions = { batch("acq:1", "goldcap", 2, 1, 1) },
      ownedLots = { lot("commodity:42", 1, 1, 1), lot("commodity:42", 1, 1, 2) } })[1]
    assert.equal(1, tiny.projectedNet)

    local normal = build({ acquisitions = { batch("acq:2", "goldcap", 5, 100, 1) },
      ownedLots = { lot("commodity:42", 2, 101, 1), lot("commodity:42", 3, 202, 2) } })[1]
    assert.equal(math.floor((2 * 101 + 3 * 202) * 95 / 100), normal.projectedNet)

    local max = 9007199254740991
    local overflow = build({ acquisitions = { batch("acq:max", "goldcap", 2, 2, 1) },
      ownedLots = { lot("commodity:42", 1, max, 1), lot("commodity:42", 1, 1, 2) } })[1]
    assert.is_nil(overflow.projectedNet)
    assert.is_nil(overflow.profit)
  end)

  -- Selling out is not amnesia. `compatibleBatch` filters batches down to what is still HELD,
  -- and that same filtered set was also the only evidence pool for "what is this item's auction
  -- identity" -- two different questions. So the moment the last keyed batch reached zero, every
  -- keyless batch for that item was orphaned into its own REPAIR_IDENTITY row: one item, fourteen
  -- rows, no cost, no market, no Post. An item with a single leftover unit behaved correctly and
  -- an identical item with none did not.
  it("keeps an item's identity after every keyed batch is sold out", function()
    local spent = batch("acq:spent", "auction_house", 0, 0, 1)
    local keyless = batch("acq:keyless", "auction_house", 5, 500, 2)
    keyless.positionKey = nil
    local positions = build({ acquisitions = { spent, keyless } })

    assert.equal(1, #positions)
    assert.is_nil(positions[1].unresolved)
    assert.equal("commodity:42", positions[1].positionKey)
    assert.equal(5, positions[1].trackedQty)
  end)

  -- The real caller never hands Build a spent batch: GC.Acquisitions.GetActive drops it. So the
  -- evidence has to arrive by its own route, or the fix above is dead code in production --
  -- which is exactly what shipped the first time.
  it("adopts an identity supplied separately when the caller filtered the spent batch away", function()
    local keyless = batch("acq:keyless", "auction_house", 5, 500, 2)
    keyless.positionKey = nil
    local positions = build({
      acquisitions = { keyless },                       -- as GetActive would hand them over
      identityEvidence = { { itemID = 42, positionKey = "commodity:42" } },
    })

    assert.equal(1, #positions)
    assert.is_nil(positions[1].unresolved)
    assert.equal("commodity:42", positions[1].positionKey)
  end)

  it("still refuses to guess when supplied identities disagree", function()
    local keyless = batch("acq:keyless", "auction_house", 5, 500, 2)
    keyless.positionKey = nil
    local positions = build({
      acquisitions = { keyless },
      identityEvidence = {
        { itemID = 42, positionKey = "commodity:42" },
        { itemID = 42, positionKey = "item:42:23:0:0" },
      },
    })
    local unresolved = 0
    for _, position in ipairs(positions) do
      if position.unresolved then unresolved = unresolved + 1 end
    end
    assert.equal(1, unresolved)
  end)

  it("still refuses to guess when the sold-out batches disagree with each other", function()
    local spentA = batch("acq:a", "auction_house", 0, 0, 1)
    local spentB = batch("acq:b", "auction_house", 0, 0, 2, nil, nil, nil, "item:42:23:0:0")
    local keyless = batch("acq:keyless", "auction_house", 5, 500, 3)
    keyless.positionKey = nil
    local positions = build({ acquisitions = { spentA, spentB, keyless } })

    -- Two candidate identities and no way to choose: filing it under a guess is how one item
    -- becomes two positions, so it stays a repair row instead.
    local unresolved = 0
    for _, position in ipairs(positions) do
      if position.unresolved then unresolved = unresolved + 1 end
    end
    assert.equal(1, unresolved)
  end)

  it("[FINAL I1] keeps pending and unresolved evidence visible without inventing a position", function()
    local active = batch("acq:1", "goldcap", 1, 100, 1)
    active.itemName = "Sold Ore"
    local soldPending = build({ acquisitions = { active }, activities = {
      { scopeKey = "eu\1A-R\1commodity:42", positionKey = "commodity:42", itemID = 42,
        itemName = "Sold Ore", character = "A-R", region = "eu", firstSeenAt = 1 },
    }, sellerEvidence = {
      { key = "sale:pending", kind = "sale", source = "mail", itemName = "Sold Ore",
        qty = 1, total = 150, at = 5, char = "A-R", region = "eu", pending = true },
    } })
    assert.equal(1, #soldPending)
    assert.equal("SOLD_PENDING", soldPending[1].status)
    assert.is_true(soldPending[1].facts.soldPending)
    assert.equal(1, soldPending[1].trackedQty)

    local unassigned = batch("acq:item-only", "auction_house", 1, 75, 1, nil, nil, 77)
    unassigned.positionKey = nil
    local unresolved = build({ acquisitions = { unassigned }, pendingAcquisitions = {
      { id = "pending:1", itemID = 88, quantity = 2, completedAt = 2,
        character = "A-R", region = "eu", reason = "missing identity" },
    }, activities = {
      { scopeKey = "eu\1A-R\1item:1:0:0:0", positionKey = "item:1:0:0:0", itemID = 1,
        itemName = "Shared", character = "A-R", region = "eu", firstSeenAt = 1 },
      { scopeKey = "eu\1A-R\1item:2:0:0:0", positionKey = "item:2:0:0:0", itemID = 2,
        itemName = "Shared", character = "A-R", region = "eu", firstSeenAt = 1 },
    }, sellerEvidence = {
      -- Both pending: a settled sale makes no row at all now, attributable or not, so pinning
      -- the two unattributable SHAPES needs the one kind of sale that still earns one.
      { key = "sale:paid-unresolved", kind = "sale", source = "mail", itemName = "No Activity",
        qty = 1, total = 100, at = 5, char = "A-R", region = "eu", pending = true },
      { key = "sale:ambiguous", kind = "sale", source = "mail", itemName = "Shared",
        qty = 1, total = 100, at = 5, char = "A-R", region = "eu", pending = true },
    } })
    local kinds = {}
    for _, position in ipairs(unresolved) do
      assert.is_nil(position.positionKey)
      assert.is_true(position.unresolved)
      assert.is_false(position.protectedAction)
      kinds[position.unresolvedKind] = (kinds[position.unresolvedKind] or 0) + 1
      assert.is_nil(GC.SellPositions.BuildPostPlan(position, { itemID = position.itemID, exactQty = 1 }, 100))
      assert.is_nil(GC.SellPositions.BuildRepostPlan(position, 1, 100))
    end
    assert.equal(1, kinds.pending_purchase)
    assert.equal(1, kinds.unassigned_acquisition)
    assert.equal(1, kinds.pending_sale)
    assert.equal(1, kinds.ambiguous_sale)

    local resolvable = batch("acq:item-only", "auction_house", 1, 75, 1, nil, nil, 77)
    resolvable.positionKey = nil
    local resolved = build({ acquisitions = { resolvable }, ownedLots = {
      { itemID = 77, positionKey = "item:77:10:0:0", quantity = 1,
        unitPrice = 100, auctionID = 9, firstSeenAt = 1 },
    } })
    assert.equal(1, #resolved)
    assert.equal("item:77:10:0:0", resolved[1].positionKey)
    assert.equal(75, resolved[1].knownCost)
  end)

  it("keeps same-item variants and per-lot listing prices separate", function()
    local variants = build({ acquisitions = {
      batch("acq:1", "goldcap", 1, 100, 1, nil, nil, 42, "item:42:10:0:0"),
      batch("acq:2", "goldcap", 1, 200, 2, nil, nil, 42, "item:42:20:0:0"),
    }, ownedLots = {
      lot("item:42:10:0:0", 1, 300, 1), lot("item:42:20:0:0", 1, 400, 2),
    } })
    assert.equal(2, #variants)
    assert.equal(300, variants[1].listedValue)
    assert.equal(400, variants[2].listedValue)
  end)

  it("uses an item-only batch only when one compatible variant exists", function()
    local itemOnly = batch("acq:1", "manual", 1, 100, 1)
    itemOnly.positionKey = nil
    local one = build({ acquisitions = { itemOnly },
      ownedLots = { lot("item:42:10:0:0", 1, 200, 1) } })[1]
    assert.equal(100, one.knownCost)
    local ambiguous = batch("acq:1", "manual", 1, 100, 1)
    ambiguous.positionKey = nil
    local many = build({ acquisitions = { ambiguous },
      ownedLots = { lot("item:42:10:0:0", 1, 200, 1), lot("item:42:20:0:0", 1, 200, 2) } })
    assert.equal("UNKNOWN", many[1].coverage)
    assert.equal("UNKNOWN", many[2].coverage)
  end)

  it("uses a stale quote only for display and a fresh quote to cap each listed lot", function()
    local stale = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 200, 2) },
      quotes = { [42] = { unit = 100, at = 0 } }, now = 11 })[1]
    assert.equal(100, stale.displayMarketUnit)
    assert.is_nil(stale.freshMarketUnit)
    assert.equal(11, stale.quoteAge)
    assert.equal(475, stale.projectedNet)
    local fresh = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 200, 2) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    assert.equal(190, fresh.projectedNet)
  end)

  -- Queue-at-exit projection: the PROFIT column and the price Post uses must be one number.
  -- A lot listed at or under the position's underwritten exit (batch.targetUnit) projects at
  -- ITS price -- the addon queued it there on purpose; clamping it to the current floor showed
  -- a fresh queue post as an instant loss (in game: listed 11g19s, PROFIT read -45s off the
  -- 8g93s floor). A lot priced above the exit keeps the conservative min(list, market) clamp.
  it("projects a listed lot at its own price when it sits within the underwritten exit", function()
    local underwritten = batch("acq:1", "goldcap", 2, 200, 1)
    underwritten.targetUnit = 300
    local p = build({ acquisitions = { underwritten },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 200, 2) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    -- (300 + 200) * 0.95 = 475, not the floor-clamped 190.
    assert.equal(475, p.projectedNet)

    local overpriced = batch("acq:1", "goldcap", 2, 200, 1)
    overpriced.targetUnit = 250
    local q = build({ acquisitions = { overpriced },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 200, 2) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    -- 300 is above the 250 exit: nothing underwrites it, the clamp holds -> (100+200)*0.95.
    assert.equal(285, q.projectedNet)
  end)

  it("does not call a position undercut when its cheapest listed lot is still competitive", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 80, 2) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    assert.equal("LISTED", p.status)
  end)

  it("requires a fresh quote before projecting an unlisted position", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      quotes = { [42] = { unit = 200, at = 0 } }, now = 11 })[1]
    assert.is_nil(p.projectedNet)
    assert.is_nil(p.profit)
  end)

  -- The figures here are scaled up from the original 150-copper fixture so the item is worth
  -- an ordinary couple of silver: at the very bottom of the grid the recommendation lands on
  -- the 100-copper clamp, under this fixture's breakeven, and the whole RepostAdvice outcome
  -- flips to hold/loss for a reason that has nothing to do with what the test is for --
  -- ahead/outlook flowing through into a repost recommendation.
  it("carries measured outlook and a pure recommendation rather than a status label", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
      ownedLots = { lot("commodity:42", 2, 20000, 1) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 10000, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 4 } } })[1]
    assert.equal(3, p.ahead)
    assert.equal(4, p.soldPerDay)
    assert.equal("repost", p.recommendation.action)
    assert.equal(15000, p.recommendation.rec.unit)
    assert.equal(10527, p.recommendation.rec.breakeven)
  end)

  -- Same scaling as the test above, for the same reason.
  it("carries a direct RecommendPost decision for unlisted exact stock and no fallback without a quote", function()
    local advised = build({ acquisitions = { batch("acq:1", "goldcap", 2, 20000, 1) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 15000, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 5 } } })[1]
    assert.equal(15000, advised.recommendation.unit)
    assert.equal("match", advised.recommendation.mode)
    assert.equal(10527, advised.recommendation.breakeven)
    assert.equal(5, advised.soldPerDay)
    local noQuote = build({ acquisitions = { batch("acq:2", "goldcap", 1, 100, 1) } })[1]
    assert.is_nil(noQuote.recommendation)
  end)

  -- `position.postRecommendation` answers a narrower, always-the-same question --
  -- "what would I list the stock in my BAGS at" -- independently of what
  -- `position.recommendation` says, which sometimes answers a different question
  -- entirely (RepostAdvice's "should I cancel and relist the lot that's already
  -- up", once coverage is COMPLETE and something is already listed). GC.PostQueue
  -- reads this field, not `recommendation`, precisely so a position that is BOTH
  -- partly listed AND still holds bag stock still gets a post price for the bags.
  describe("postRecommendation", function()
    it("is absent when there is no bag stock, even when recommendation is not", function()
      local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 20000, 1) },
        ownedLots = { lot("commodity:42", 1, 20000, 1) },
        quotes = { [42] = { unit = 20000, at = 9 } } })[1]
      assert.equal(0, p.bagQty)
      assert.is_not_nil(p.recommendation) -- RepostAdvice fires; the row still has something to say
      assert.is_nil(p.postRecommendation)
    end)

    -- The two cases where a branch already answers "what would I list the bag stock at" today:
    -- COMPLETE coverage with nothing listed yet (RecommendPost, no cost-basis gate), and bag
    -- stock GoldCap never bought at all (RecommendPost with a nil paidUnit). postRecommendation
    -- must compute the identical value in both, or the row and the queue could disagree about
    -- a position neither of these two new cases even touches.
    it("equals recommendation when coverage is COMPLETE and nothing is listed yet", function()
      local p = build({ acquisitions = { batch("acq:1", "goldcap", 50, 500000, 1) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 50,
          isCommodity = true } },
        quotes = { [42] = { unit = 20000, at = 9 } } })[1]
      assert.equal("COMPLETE", p.coverage)
      assert.equal(0, p.listedQty)
      assert.equal(50, p.bagQty)
      assert.is_not_nil(p.recommendation)
      assert.same(p.recommendation, p.postRecommendation)
    end)

    it("equals recommendation for untracked bag stock GoldCap never bought", function()
      local p = build({
        bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 40,
          isCommodity = true } },
        quotes = { [42] = { unit = 20000, at = 9 } } })[1]
      assert.not_equal("COMPLETE", p.coverage)
      assert.equal(40, p.bagQty)
      assert.is_not_nil(p.recommendation)
      assert.same(p.recommendation, p.postRecommendation)
    end)

    -- The defect this field exists to fix: COMPLETE coverage, some of the stock already
    -- listed, AND some still in the bags (bought 100, posted 50, 50 left to post).
    -- `recommendation` here is RepostAdvice-shaped ({action, reason, rec}, no top-level
    -- `.unit`) -- it answers "should I cancel and relist the 50 that are already up", not
    -- "what should the other 50 in my bags list at". postRecommendation answers the second
    -- question regardless of what the first one says.
    it("still answers 'what would I post the bags at' when recommendation is RepostAdvice-shaped", function()
      local p = build({ acquisitions = { batch("acq:1", "goldcap", 100, 1000000, 1) },
        ownedLots = { lot("commodity:42", 50, 15000, 1) },
        bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 50,
          isCommodity = true } },
        quotes = { [42] = { unit = 20000, at = 9 } } })[1]
      assert.equal("COMPLETE", p.coverage)
      assert.is_true(p.listedQty > 0)
      assert.equal(50, p.bagQty)
      assert.is_nil(p.recommendation.unit) -- RepostAdvice shape: no top-level .unit to copy
      assert.is_not_nil(p.postRecommendation)
      assert.is_true(p.postRecommendation.unit > 0)
      assert.equal(0, p.postRecommendation.unit % 100)
    end)
  end)

  it("keeps every batch and owned lot alongside bounded queue facts", function()
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", 1, 100, 1), batch("acq:2", "manual", 2, 400, 2),
    }, ownedLots = { lot("commodity:42", 1, 180, 11, 1), lot("commodity:42", 2, 220, 12, 2) },
      quotes = { [42] = { unit = 150, at = 9, levels = { { unitPrice = 120, quantity = 3 }, { unitPrice = 180, quantity = 4 } } } },
      statsByItemID = { [42] = { sold = 2 } } })[1]
    assert.equal(2, #p.batches)
    assert.equal(2, #p.ownedLots)
    assert.equal(3, p.ahead)
    assert.equal(2, p.soldPerDay)
    assert.equal(3, p.outlook.days)
    assert.equal(11, p.ownedLots[1].auctionID)
    assert.equal(12, p.ownedLots[2].auctionID)
    assert.equal("hold", p.recommendation.action)
    assert.equal("loss", p.recommendation.reason)
  end)

  it("never authorizes stale display data for post or repost plans", function()
    local unlisted = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      quotes = { [42] = { unit = 200, at = 0 } }, now = 11 })[1]
    local listed = build({ acquisitions = { batch("acq:2", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) },
      quotes = { [42] = { unit = 150, at = 0 } }, now = 11 })[1]

    assert.equal(200, unlisted.displayMarketUnit)
    assert.is_nil(unlisted.freshMarketUnit)
    assert.is_nil(unlisted.projectedNet)
    assert.is_nil(GC.SellPositions.BuildPostPlan(unlisted, { itemID = 42, exactQty = 1 },
      { unit = unlisted.displayMarketUnit, at = 0 }))
    assert.equal(150, listed.displayMarketUnit)
    assert.is_nil(listed.freshMarketUnit)
    assert.equal(190, listed.projectedNet)
    assert.is_nil(GC.SellPositions.BuildRepostPlan(listed, 1,
      { unit = listed.displayMarketUnit, at = 0 }))
  end)

  it("never treats a contradictory fresh-marked stale display quote as fresh", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) },
      quotes = { [42] = { unit = 150, at = 9, fresh = true, stale = true } } })[1]
    assert.equal(150, p.displayMarketUnit)
    assert.is_nil(p.freshMarketUnit)
    assert.equal(190, p.projectedNet)
  end)

  it("makes no cost outrank an undercut listing", function()
    local p = build({ ownedLots = { lot("commodity:42", 1, 200, 1) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    assert.equal("NO_COST", p.status)
  end)

  it("scopes positions and summaries to exactly one character and region", function()
    local legacy = batch("acq:legacy", "manual", 1, 1, 3)
    legacy.character, legacy.region = nil, nil
    local acquisitions = {
      batch("acq:a", "goldcap", 1, 100, 1, "A-R", "eu"),
      batch("acq:b", "auction_house", 1, 900, 2, "B-R", "eu"),
      legacy,
    }
    local p = build({ acquisitions = acquisitions, ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    assert.same({ goldcap = 1 }, p.sources)
    assert.equal(100, p.knownCost)
    assert.equal(90, p.profit)
    local repost = GC.SellPositions.BuildRepostPlan(p, 1, 150)
    assert.equal(100, repost.cost)
    local summary = GC.SellPositions.Summary({ p })
    assert.equal(100, summary.invested)
    assert.equal(90, summary.profit)
  end)

  it("[FINAL I3] retains independently known partial cost, listed value AND profit in mixed summaries", function()
    local complete = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    local incomplete = { coverage = "PARTIAL", knownQty = 1, exposureQty = 2,
      knownCost = 10, listedValue = 50, profit = nil, projectedNet = nil }
    local summary = GC.SellPositions.Summary({ complete, incomplete })
    assert.equal(110, summary.invested)
    assert.equal(250, summary.listedValue)
    -- `projected`/the top-level all-or-nothing total still null out the moment one position is
    -- incomplete -- that stays unchanged. `profit` does not: the "complete" position individually
    -- clears both gates (COMPLETE coverage, a priced projection), so it counts on its own, exactly
    -- the fix this task exists to make -- one PARTIAL position no longer nulls a total that had a
    -- perfectly good, individually-known profit sitting right next to it.
    assert.is_nil(summary.projected)
    assert.equal(90, summary.profit)
    assert.equal(1, summary.countedCount)
    assert.equal(1, summary.excludedNoCost)
    assert.equal(0, summary.excludedNoPrice)
  end)

  it("keeps known investment while leaving an unquoted complete position's projection unknown", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) } })[1]
    local summary = GC.SellPositions.Summary({ p })
    assert.equal(100, summary.invested)
    assert.is_nil(summary.projected)
    assert.is_nil(summary.profit)
  end)

  it("keeps a complete losing position's signed profit in the summary", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 100, 1) } })[1]
    local summary = GC.SellPositions.Summary({ p })
    assert.equal(200, summary.invested)
    assert.equal(95, summary.projected)
    assert.equal(-105, summary.profit)
  end)

  it("sums multiple complete positions including losses into a signed exact profit", function()
    local summary = GC.SellPositions.Summary({
      { coverage = "COMPLETE", knownCost = 200, listedValue = 0, projectedNet = 95, profit = -105 },
      { coverage = "COMPLETE", knownCost = 30, listedValue = 0, projectedNet = 95, profit = 65 },
    })
    assert.same({ invested = 230, listedValue = 0, projected = 190, profit = -40,
      countedCount = 2, excludedNoCost = 0, excludedNoPrice = 0 }, summary)
  end)

  it("sums only the positions that individually clear both gates, reporting the rest as exclusions", function()
    local summary = GC.SellPositions.Summary({
      { coverage = "COMPLETE", knownCost = 200, listedValue = 0, projectedNet = 295 },
      { coverage = "PARTIAL", knownCost = 10, listedValue = 50, projectedNet = nil },
      { coverage = "COMPLETE", knownCost = 40, listedValue = 0, projectedNet = nil },
    })
    assert.equal(95, summary.profit)
    assert.equal(1, summary.countedCount)
    assert.equal(1, summary.excludedNoCost)
    assert.equal(1, summary.excludedNoPrice)
  end)

  it("reports profit as nil only when nothing on the list individually clears both gates", function()
    local summary = GC.SellPositions.Summary({
      { coverage = "PARTIAL", knownCost = 10, listedValue = 50, projectedNet = nil },
      { coverage = "UNKNOWN", knownCost = 0, listedValue = 0, projectedNet = nil },
      { coverage = "COMPLETE", knownCost = 40, listedValue = 0, projectedNet = nil },
    })
    assert.is_nil(summary.profit)
    assert.equal(0, summary.countedCount)
    assert.equal(2, summary.excludedNoCost)
    assert.equal(1, summary.excludedNoPrice)
  end)

  it("fails closed when batch tracked and source quantities overflow exact accounting", function()
    local max = 9007199254740991
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", max, max, 1), batch("acq:2", "goldcap", 1, 1, 2),
    }, ownedLots = { lot("commodity:42", 1, 1, 1) } })[1]
    assert.not_equal("COMPLETE", p.coverage)
    assert.is_nil(p.trackedQty)
    assert.is_nil(p.sources.goldcap)
    assert.is_nil(p.projectedNet)
    assert.is_nil(GC.SellPositions.BuildRepostPlan(p, 1, 1))
  end)

  it("fails closed when owned-lot quantities, values, or FIFO skip ranges overflow", function()
    local max = 9007199254740991
    local first = lot("commodity:42", max, 1, 1, 1)
    local second = lot("commodity:42", 1, 1, 2, nil)
    local p = build({ acquisitions = { batch("acq:1", "goldcap", max, max, 1) },
      ownedLots = { first, second } })[1]
    assert.not_equal("COMPLETE", p.coverage)
    assert.is_nil(p.listedValue)
    assert.is_nil(GC.SellPositions.BuildRepostPlan(p, 1, 1))
    assert.is_nil(GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 1 }, 1))
  end)

  it("returns an unknown summary when complete cost aggregation would overflow", function()
    local max = 9007199254740991
    local summary = GC.SellPositions.Summary({
      { coverage = "COMPLETE", knownCost = max, listedValue = max, projectedNet = max },
      { coverage = "COMPLETE", knownCost = 1, listedValue = 1, projectedNet = 1 },
    })
    assert.same({ invested = nil, listedValue = nil, projected = nil, profit = nil,
      countedCount = 2, excludedNoCost = 0, excludedNoPrice = 0 }, summary)
  end)

  it("normalizes missing lot timestamps for stable FIFO sorting without mutating input", function()
    local undated = lot("commodity:42", 1, 100, 2, nil)
    undated.firstSeenAt = nil
    local dated = lot("commodity:42", 1, 100, 1, 1)
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { dated, undated } })[1]
    assert.equal(2, p.ownedLots[1].auctionID)
    assert.equal(1, p.ownedLots[2].auctionID)
    assert.is_nil(undated.firstSeenAt)
    assert.is_nil(undated.allocation)
  end)

  it("reserves listed FIFO quantity before allocating an exact post quantity", function()
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", 2, 101, 1), batch("acq:2", "manual", 2, 400, 2),
    }, ownedLots = { lot("commodity:42", 2, 200, 9) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 1 }, 300)
    assert.equal(1, plan.quantity)
    assert.equal(200, plan.cost)
    assert.equal("acq:2", plan.allocations[1].batchID)
  end)

  -- F5 queue-at-exit: the plan must list at the same number the recommendation displayed --
  -- the raise mirrors the postFloor raise right above it in BuildPostPlan, and can only ever
  -- move the price UP, so a stale queue quote can delay a sale but never underprice one.
  it("lists at the queue price when the recommendation chose to queue at the exit", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) } })[1]
    p.postRecommendation = { mode = "queue", unit = 27300 }
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 5 }, 19800)
    assert.equal(27300, plan.unitPrice)
  end)

  it("ignores a queue recommendation that sits below the fresh quote", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) } })[1]
    p.postRecommendation = { mode = "queue", unit = 15000 }
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 5 }, 19800)
    assert.equal(19800, plan.unitPrice)
  end)

  it("leaves the plan price alone for non-queue recommendations", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) } })[1]
    p.postRecommendation = { mode = "match", unit = 27300 }
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 5 }, 19800)
    assert.equal(19800, plan.unitPrice)
  end)

  -- Posts what is in the bags, not what GoldCap has a receipt for. Listed units
  -- are on the auction house and not in the bags, so the bag count already IS
  -- "everything not yet listed" -- the old min(tracked - listed, bags) capped a
  -- real 9-unit stack at the 3 units GoldCap happened to know the price of, and
  -- refused outright for anything it had never seen bought.
  it("posts the whole bag quantity and reports how much of it is costed", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 9 }, 250)
    assert.equal(9, plan.quantity)
    -- Three of the nine are covered by the tracked purchase, so the cost of this
    -- post is not known exactly and is reported as unknown rather than guessed.
    assert.is_false(plan.costKnown)
    assert.is_nil(plan.cost)
  end)

  it("costs a post exactly when every unit of it is covered", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 3 }, 250)
    assert.equal(3, plan.quantity)
    assert.is_true(plan.costKnown)
    assert.equal(300, plan.cost)
  end)

  it("posts untracked bag stock that GoldCap never bought", function()
    local p = build({ bagStock = { { positionKey = "commodity:42", itemID = 42,
      itemName = "Ore", quantity = 40, isCommodity = true } } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 40 }, 250)
    assert.equal(40, plan.quantity)
    assert.is_false(plan.costKnown)
    -- Part 0 (silver-grid fix): BuildPostPlan now normalizes its unitPrice to whole silver via
    -- SilverUp, so the raw 250-copper freshQuote used here rounds up to 300 rather than posting
    -- at a price PostCommodity would have silently rejected.
    assert.equal(300, plan.unitPrice)
  end)

  -- Everything farmed, crafted, milled or bought before GoldCap existed. It used
  -- to be invisible here: a position existed only if GoldCap had a purchase
  -- receipt for it or the player already had it listed.
  it("builds a position out of bag stock alone and still advises a price", function()
    local p = build({
      bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 40,
        isCommodity = true } },
      quotes = { [42] = { unit = 500, at = 10 } },
      statsByItemID = { [42] = { sold = 100 } },
      now = 10,
    })[1]
    assert.equal(40, p.bagQty)
    assert.equal("Ore", p.itemName)
    assert.equal(500, p.freshMarketUnit)
    -- No cost basis means no breakeven and no below-cost warning, rather than a
    -- cost invented from the market price.
    assert.is_not_nil(p.recommendation)
    assert.is_nil(p.recommendation.breakeven)
    assert.is_false(p.recommendation.belowCost)
  end)

  it("folds bag stock into the position its purchases and listings already share", function()
    local p = build({
      acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) },
      bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 9, isCommodity = true } },
    })
    assert.equal(1, #p)
    assert.equal(9, p[1].bagQty)
    assert.equal(2, p[1].listedQty)
    assert.equal(5, p[1].trackedQty)
  end)

  it("fails closed on an ambiguous normal-item bag variant", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1, nil, nil, 42, "item:42:10:0:0") } })[1]
    local plan, reason = GC.SellPositions.BuildPostPlan(p,
      { itemID = 42, exactQty = 1, positionKey = "item:42:20:0:0" }, 200)
    assert.is_nil(plan)
    assert.equal("ambiguous_variant", reason)
  end)

  it("reposts one concrete auction and its precomputed FIFO slice", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1), batch("acq:2", "manual", 2, 500, 2) },
      ownedLots = { lot("commodity:42", 1, 200, 11, 1), lot("commodity:42", 2, 300, 12, 2) } })[1]
    local plan = GC.SellPositions.BuildRepostPlan(p, 12, 250)
    assert.equal(12, plan.auctionID)
    assert.equal(2, plan.quantity)
    assert.equal(500, plan.cost)
    assert.is_true(plan.costKnown)
    assert.equal("acq:2", plan.allocations[1].batchID)
  end)

  it("rejects an action without a fresh quote, but reposts stock it cannot cost", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan, reason = GC.SellPositions.BuildRepostPlan(p, 1, { unit = 150, stale = true })
    assert.is_nil(plan)
    assert.equal("stale_quote", reason)
    -- A repost CANCELS a live lot. What its units cost cannot make cancelling unsafe, and no
    -- caller reads plan.cost or plan.allocations for a repost at all -- so refusing on an
    -- incomplete FIFO slice guarded nothing and left Repost permanently dead on every listing
    -- GoldCap has no purchase record for: farmed, crafted, or bought before it was installed.
    -- BuildPostPlan, which spends and lists, has always returned costKnown = false instead of
    -- refusing; this is the pair being inconsistent in the more dangerous direction.
    plan = GC.SellPositions.BuildRepostPlan(p, 1, 150)
    assert.equal(1, plan.auctionID)
    assert.equal(2, plan.quantity)
    assert.equal(150, plan.unitPrice)
    assert.is_false(plan.costKnown)
    assert.is_nil(plan.cost)
    assert.same({}, plan.allocations)
  end)

  it("fails closed when an action receives a timestamped quote without fresh proof", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    local plan, reason = GC.SellPositions.BuildRepostPlan(p, 1, { unit = 150, at = 0 })
    assert.is_nil(plan)
    assert.equal("stale_quote", reason)
    plan = GC.SellPositions.BuildRepostPlan(p, 1, { unit = 150, fresh = true })
    assert.equal(150, plan.unitPrice)
  end)

  it("fails malformed post positions closed instead of matching a missing variant key", function()
    -- No position key at all. The caller proves a plan belongs to the clicked row
    -- by comparing keys, and nil == nil passes that check, so this has to fail
    -- here rather than be caught downstream.
    local plan, reason = GC.SellPositions.BuildPostPlan({ itemID = 42, trackedQty = 1,
      listedQty = 0, batches = {} }, { itemID = 42, exactQty = 1 }, 150)
    assert.is_nil(plan)
    assert.equal("missing_position_key", reason)
  end)

  -- Pricing a sale off the cheapest row in the book prices it off the player's own auction as
  -- soon as they are the cheapest, so every repost walks their own price down against nobody.
  describe("CheapestCompetingUnit", function()
    it("ignores the player's own listings and returns the cheapest real competitor", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 240, ownerQty = 240, ownerItem = true },
        { unitPrice = 60000, quantity = 100 },
        { unitPrice = 65000, quantity = 2684 },
      }))
    end)

    -- The owner's real case: 110 competitor units already sat at 5g50s and his 130 joined the
    -- same price point. Matching that price was correct -- posting above it would have queued
    -- his stock behind someone else's -- so a shared level must still count as competition.
    it("keeps a level the player shares with real competitors", function()
      assert.equal(55000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 240, ownerQty = 130, ownerItem = true },
        { unitPrice = 60000, quantity = 100 },
      }))
    end)

    it("skips a level that is entirely the player's own", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 130, ownerQty = 130, ownerItem = true },
        { unitPrice = 60000, quantity = 100 },
      }))
    end)

    -- Without a count the level cannot be split, so it is skipped: erring high costs a match,
    -- erring low restarts the undercut spiral.
    it("skips an unsplittable owner level when the API reports no count", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 300, ownerItem = true },
        { unitPrice = 60000, quantity = 10 },
      }))
    end)

    it("returns nothing when the player is the only seller", function()
      assert.is_nil(GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 240, ownerQty = 240, ownerItem = true },
      }))
      assert.is_nil(GC.SellPositions.CheapestCompetingUnit({}))
      assert.is_nil(GC.SellPositions.CheapestCompetingUnit(nil))
    end)

    it("is not fooled by an unsorted book or an invalid price", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 90000, quantity = 5 },
        { unitPrice = 0, quantity = 5 },
        { unitPrice = 60000, quantity = 5 },
      }))
    end)
  end)
end)

-- A seller could see the price GoldCap picked and had no way to see it, question it or change
-- it -- the one number on the Sell tab that spends real gold was the one number they could not
-- touch. The floor and queue raises below it exist to stop the ADDON underpricing on its own,
-- against a thin cheap lot it cannot tell from a real market; they were never a veto on a
-- seller who has read the book. So a chosen price REPLACES them, and the plan reports what
-- that means instead of clamping it back.
describe("a price the seller chose", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
  end)

  local function position(over)
    local p = {
      positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42", itemID = 42,
      coverage = "UNKNOWN", batches = {}, ownedLots = {}, listedQty = 0,
      knownQty = 0, knownCost = 0, postFloor = 500000,
    }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
  end
  local BAGS = { itemID = 42, exactQty = 10, positionKey = "commodity:42" }
  local QUOTE = { unit = 300000, fresh = true }

  it("raises to the underprice floor when nobody has chosen a price", function()
    local plan = GC.SellPositions.BuildPostPlan(position(), BAGS, QUOTE)
    assert.equal(500000, plan.unitPrice)
    assert.is_false(plan.chosen)
    assert.is_false(plan.belowFloor)
  end)

  it("lists at the chosen price instead, floor and all", function()
    local plan = GC.SellPositions.BuildPostPlan(position(), BAGS, QUOTE, { overrideUnit = 420000 })
    assert.equal(420000, plan.unitPrice)
    assert.is_true(plan.chosen)
    -- Reported, not refused: the caller says it out loud before the second click.
    assert.is_true(plan.belowFloor)
  end)

  it("does not report a floor breach for a chosen price above it", function()
    local plan = GC.SellPositions.BuildPostPlan(position(), BAGS, QUOTE, { overrideUnit = 900000 })
    assert.equal(900000, plan.unitPrice)
    assert.is_false(plan.belowFloor)
  end)

  -- PostCommodity/PostItem silently reject a price with a non-zero copper remainder, so a
  -- typed number has to land on the same 100-copper grid every derived one does. SilverUp,
  -- never down: rounding a chosen price DOWN would list under what the seller asked for.
  it("rounds a typed price up onto the silver grid the auction house accepts", function()
    local plan = GC.SellPositions.BuildPostPlan(position(), BAGS, QUOTE, { overrideUnit = 420001 })
    assert.equal(0, plan.unitPrice % 100)
    assert.is_true(plan.unitPrice >= 420001)
  end)

  it("says when a chosen price lists below what the stock cost", function()
    local p = position({ coverage = "COMPLETE", knownQty = 10, knownCost = 6000000 }) -- 600000/unit
    local under = GC.SellPositions.BuildPostPlan(p, BAGS, QUOTE, { overrideUnit = 550000 })
    assert.is_true(under.belowCost)
    local over = GC.SellPositions.BuildPostPlan(p, BAGS, QUOTE, { overrideUnit = 650000 })
    assert.is_false(over.belowCost)
  end)

  it("cannot be talked into a nonsense price", function()
    for _, bad in ipairs({ 0, -1, 0 / 0, math.huge }) do
      local plan = GC.SellPositions.BuildPostPlan(position(), BAGS, QUOTE, { overrideUnit = bad })
      assert.is_false(plan.chosen)
      assert.equal(500000, plan.unitPrice) -- the derived price, untouched
    end
    assert.is_false(GC.SellPositions.BuildPostPlan(position(), BAGS, QUOTE, {}).chosen)
  end)

  -- The freshness contract is untouched: a chosen price still needs a live quote behind it,
  -- because everything else about the post -- the pin, the requote check -- is built on one.
  it("still refuses without a fresh quote, chosen price or not", function()
    assert.is_nil(GC.SellPositions.BuildPostPlan(position(), BAGS, nil, { overrideUnit = 420000 }))
  end)
end)
