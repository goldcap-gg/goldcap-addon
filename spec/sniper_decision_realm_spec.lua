local helper = require("spec.spec_helper")

-- Sniper phase 2: the realm-item verdict. Its whole point is what it refuses to claim -- a
-- realm item's sale speed is not measured anywhere, so the answer is never SAFE and never
-- buyable, and the candidate it hands back is a price comparison, not a promise.
describe("SniperDecision.EvaluateRealm", function()
  local GC
  local config = { minimumProfitCopper = 50000, minimumRoi = 0.10 }

  before_each(function()
    GC = helper.loadModule("Core/Trigger.lua")
    helper.loadModule("Core/SniperDecision.lua", GC)
  end)

  local function lot(auctionID, buyout, itemLevel, quantity)
    return { auctionID = auctionID, buyout = buyout, itemLevel = itemLevel, quantity = quantity or 1 }
  end

  -- reference 1,000,000 -> trigger 750,000 (the 25% floor; the profit formula allows 900,000)
  local REFERENCE = 1000000

  it("refuses malformed input rather than guessing", function()
    local result = GC.SniperDecision.EvaluateRealm(nil, REFERENCE, 0, config)
    assert.equal("AVOID", result.status)
    assert.is_false(result.buyable)
    assert.same({ "invalid_input" }, result.reasons)
    assert.equal("AVOID", GC.SniperDecision.EvaluateRealm({}, 0, 0, config).status)
    assert.equal("AVOID", GC.SniperDecision.EvaluateRealm({}, REFERENCE, 0, nil).status)
  end)

  it("watches the cheapest lot under the trigger, and never calls it safe", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(11, 900000, 0), lot(12, 500000, 0, 1), lot(13, 600000, 0) }, REFERENCE, 0, config)
    assert.equal("WATCH", result.status)
    assert.is_false(result.buyable)
    assert.same({ "realm_item_unverified" }, result.reasons)
    assert.equal(12, result.candidate.auctionID)
    assert.equal(500000, result.candidate.buyout)
    assert.equal(1, result.candidate.quantity)
    assert.equal(REFERENCE, result.reference)
    assert.equal(0.5, result.discountPct)
    -- 0.95 x 1,000,000 - 500,000
    assert.equal(450000, result.estProfit)
  end)

  -- A lot is one atomic purchase, but a stack of five is five items and the reference prices
  -- ONE. Compared whole, a stack of 5 at 100,000 each reads as 500,000 -- half a million
  -- against a million -- and the bargain is refused for looking expensive.
  it("compares a stacked lot per unit, and multiplies the profit back out", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(21, 2500000, 0, 5) }, REFERENCE, 0, config) -- 500,000 each
    assert.equal("WATCH", result.status)
    assert.equal(21, result.candidate.auctionID)
    assert.equal(2500000, result.candidate.buyout) -- what PlaceBid pays: the whole lot
    assert.equal(5, result.candidate.quantity)
    assert.equal(0.5, result.discountPct)          -- per unit, not 1 - 2,500,000/1,000,000
    assert.equal(2250000, result.estProfit)        -- (950,000 - 500,000) x 5
    assert.equal(2500000, result.entryTotal)
    assert.equal(500000, result.entryUnitDisplay)
  end)

  it("prefers the cheaper unit price, not the cheaper lot", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(21, 600000, 0, 1), lot(22, 2500000, 0, 5) }, REFERENCE, 0, config)
    assert.equal(22, result.candidate.auctionID) -- 500,000 a unit beats 600,000 for one
  end)

  it("refuses a stacked lot whose unit price does not clear the trigger", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(21, 4000000, 0, 5) }, REFERENCE, 0, config) -- 800,000 each, above the 750,000 line
    assert.equal("AVOID", result.status)
    assert.same({ "price_rose" }, result.reasons)
  end)

  it("takes the lots in price order however they arrive", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(13, 600000, 0), lot(12, 500000, 0) }, REFERENCE, 0, config)
    assert.equal(12, result.candidate.auctionID)
  end)

  it("avoids when the cheapest lot no longer clears the trigger", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(11, 800000, 0), lot(12, 900000, 0) }, REFERENCE, 0, config)
    assert.equal("AVOID", result.status)
    assert.same({ "price_rose" }, result.reasons)
    assert.is_nil(result.candidate)
  end)

  it("avoids when there are no lots at all", function()
    local result = GC.SniperDecision.EvaluateRealm({}, REFERENCE, 0, config)
    assert.equal("AVOID", result.status)
    assert.same({ "no_comparable_lot" }, result.reasons)
  end)

  it("avoids when no lot reaches the reference item level", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(11, 400000, 600), lot(12, 300000, 610) }, REFERENCE, 623, config)
    assert.equal("AVOID", result.status)
    assert.same({ "no_comparable_lot" }, result.reasons)
  end)

  it("skips the cheap under-levelled lot and buys the comparable one", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(11, 100000, 600), lot(12, 400000, 623), lot(13, 500000, 650) }, REFERENCE, 623, config)
    assert.equal("WATCH", result.status)
    assert.equal(12, result.candidate.auctionID)
    assert.equal(623, result.candidate.itemLevel)
  end)

  it("treats every lot as comparable when the reference carries no item level", function()
    local result = GC.SniperDecision.EvaluateRealm(
      { lot(11, 100000, 0) }, REFERENCE, 0, config)
    assert.equal(11, result.candidate.auctionID)
  end)

  it("ignores lots with no auction id, no buyout or no price", function()
    local result = GC.SniperDecision.EvaluateRealm({
      { buyout = 1, itemLevel = 0 },                    -- no auction id
      lot(12, 0, 0),                                    -- bid-only listing
      { auctionID = 13, itemLevel = 0 },                -- no buyout at all
      lot(14, 500000, 0),
    }, REFERENCE, 0, config)
    assert.equal(14, result.candidate.auctionID)
  end)

  it("refuses a reference the trigger cannot be computed from", function()
    -- 50,000 leaves nothing above the profit floor, so there is no price worth watching.
    local result = GC.SniperDecision.EvaluateRealm({ lot(11, 1, 0) }, 50000, 0, config)
    assert.equal("AVOID", result.status)
    assert.same({ "price_rose" }, result.reasons)
  end)

  it("explains both of its new refusals in words", function()
    for _, reason in ipairs({ "no_comparable_lot", "price_rose", "realm_item_unverified" }) do
      assert.is_true(GC.SniperDecision.REASONS[reason])
      local text = GC.SniperDecision.ReasonText(reason)
      assert.is_true(type(text) == "string" and #text > 0 and text ~= reason)
    end
  end)
end)
