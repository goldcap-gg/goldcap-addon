local helper = require("spec.spec_helper")

-- The two-deck split the Sell tab's chrome is built on. `Filter` (same module) keeps serving
-- the provenance and coverage cuts and is tested next door in sell_view_model_spec.lua; this
-- file is only about which deck a position lands on and what the chips do on top.
describe("Sell decks", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  local function keys(list)
    local out = {}
    for _, position in ipairs(list) do out[#out + 1] = position.positionKey end
    table.sort(out)
    return out
  end

  local function position(key, fields)
    local p = { positionKey = key, coverage = "COMPLETE" }
    for name, value in pairs(fields or {}) do p[name] = value end
    return p
  end

  it("puts bag stock on POST and live lots on LISTED", function()
    local bags = position("bags", { bagQty = 40 })
    local listed = position("listed", { listedQty = 20 })
    assert.same({ "bags" }, keys(GC.SellViewModel.Deck({ bags, listed }, "post")))
    assert.same({ "listed" }, keys(GC.SellViewModel.Deck({ bags, listed }, "listed")))
  end)

  it("shows a position with BOTH bag stock and live lots on both decks", function()
    -- Forty units to post and twenty lots to watch is two jobs about one item, not a leak.
    local both = position("both", { bagQty = 40, listedQty = 20 })
    assert.same({ "both" }, keys(GC.SellViewModel.Deck({ both }, "post")))
    assert.same({ "both" }, keys(GC.SellViewModel.Deck({ both }, "listed")))
  end)

  it("keeps a not-on-hand position on POST so Set cost stays reachable", function()
    -- Nothing in the bags and nothing listed: the stock is in the mail, the bank or on an alt.
    -- It belongs to no deck by the strict reading, and dropping it would take the only route to
    -- its cost with it.
    local ghost = position("ghost", { bagQty = 0, listedQty = 0 })
    assert.same({ "ghost" }, keys(GC.SellViewModel.Deck({ ghost }, "post")))
    assert.same({}, keys(GC.SellViewModel.Deck({ ghost }, "listed")))
  end)

  it("ranks the not-on-hand position BELOW real bag stock", function()
    local ghost = position("ghost", { bagQty = 0, listedQty = 0 })
    local bags = position("bags", { bagQty = 40, freshMarketUnit = 100 })
    local ordered = GC.SellViewModel.Deck({ ghost, bags }, "post")
    assert.equal("bags", ordered[1].positionKey)
    assert.equal("ghost", ordered[2].positionKey)
  end)

  it("READY keeps only bag stock the addon has a fresh price for", function()
    local ready = position("ready", { bagQty = 10, freshMarketUnit = 500 })
    local waiting = position("waiting", { bagQty = 10 })
    local ghost = position("ghost", { bagQty = 0, listedQty = 0 })
    assert.same({ "ready" },
      keys(GC.SellViewModel.Deck({ ready, waiting, ghost }, "post", { ready = true })))
  end)

  it("a STALE quote is not ready -- Post would refresh it before acting", function()
    -- displayMarketUnit without freshMarketUnit is exactly the stale case: there is a number on
    -- screen, but promising a click that turns into a wait is the lie this chip must not tell.
    local stale = position("stale", { bagQty = 10, displayMarketUnit = 500 })
    assert.same({}, keys(GC.SellViewModel.Deck({ stale }, "post", { ready = true })))
  end)

  it("NO COST keeps only positions whose basis is incomplete", function()
    local partial = position("partial", { bagQty = 5, coverage = "PARTIAL" })
    local unknown = position("unknown", { bagQty = 5, coverage = "UNKNOWN" })
    local complete = position("complete", { bagQty = 5, coverage = "COMPLETE" })
    assert.same({ "partial", "unknown" },
      keys(GC.SellViewModel.Deck({ partial, unknown, complete }, "post", { noCost = true })))
  end)

  it("ignores both chips on LISTED rather than silently emptying it", function()
    -- A live lot is already priced and already paid for, so neither chip asks it a question it
    -- can answer. Applying them anyway would blank the deck for no reason the player could see.
    local lot = position("lot", { listedQty = 20, coverage = "COMPLETE" })
    assert.same({ "lot" },
      keys(GC.SellViewModel.Deck({ lot }, "listed", { ready = true, noCost = true })))
  end)

  it("defaults to the POST deck and tolerates nil input", function()
    local bags = position("bags", { bagQty = 40 })
    assert.same({ "bags" }, keys(GC.SellViewModel.Deck({ bags })))
    assert.same({}, keys(GC.SellViewModel.Deck(nil, "post")))
  end)
end)
