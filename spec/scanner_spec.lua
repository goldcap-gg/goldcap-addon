local helper = require("spec.spec_helper")

describe("Scanner", function()
  local GC, drv, log, ready, clock, keyInfos, itemResults, commodityResults, values

  local cfg = {
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
  }

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/Scanner.lua", GC)
    log = { searches = {}, deals = {}, observations = {}, events = {}, status = {} }
    ready, clock = true, 1000
    keyInfos, itemResults, commodityResults, values = {}, {}, {}, {}
    drv = {
      isReady = function() return ready end,
      sendSearch = function(id) log.searches[#log.searches + 1] = id end,
      getKeyInfo = function(id) return keyInfos[id] end,
      itemResult = function(id) return itemResults[id] end,
      commodityResult = function(id) return commodityResults[id] end,
      getValue = function(id) return values[id] end,
      onStatus = function(s) log.status[#log.status + 1] = s end,
      now = function() return clock end,
    }
    drv.onDeal = function(deal)
      log.deals[#log.deals + 1] = deal
      log.events[#log.events + 1] = "deal"
    end
    drv.onObservation = function(itemID, deal)
      log.observations[#log.observations + 1] = { itemID = itemID, deal = deal }
      log.events[#log.events + 1] = "observation"
    end
  end)

  it("sends one search at a time and cycles the list", function()
    keyInfos[1] = { isCommodity = false }
    keyInfos[2] = { isCommodity = true }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1, 2 })
    assert.same({ 1 }, log.searches)
    s:OnItemResults(1)                -- empty result, just advances
    assert.same({ 1, 2 }, log.searches)
    s:OnCommodityResults(2)
    assert.same({ 1, 2, 1 }, log.searches) -- wrapped around
  end)

  it("evaluates item results and dedupes by auctionID", function()
    keyInfos[1] = { isCommodity = false }
    values[1] = { mv = 1000000 }
    itemResults[1] = { auctionID = 99, unitPrice = 500000, qty = 1 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    s:OnItemResults(1)
    s:OnItemResults(1) -- second cycle sees the same auction
    assert.equal(1, #log.deals)
    assert.equal("WATCH", log.deals[1].tier) -- 45g profit < 100g GOOD bar
    assert.equal(99, log.deals[1].auctionID)
    assert.equal(2, s.scanned)
  end)

  it("re-alerts a commodity only when its price drops further", function()
    keyInfos[7] = { isCommodity = true }
    values[7] = { mv = 1000000 }
    commodityResults[7] = { unitPrice = 500000, qty = 10 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 7 })
    s:OnCommodityResults(7)
    s:OnCommodityResults(7)                    -- same price: no new alert
    assert.equal(1, #log.deals)
    commodityResults[7] = { unitPrice = 400000, qty = 5 }
    s:OnCommodityResults(7)                    -- cheaper: new alert
    assert.equal(2, #log.deals)
    assert.is_true(log.deals[2].isCommodity)
  end)

  it("waits for throttle readiness before sending", function()
    ready = false
    keyInfos[1] = { isCommodity = false }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    assert.same({}, log.searches)
    ready = true
    s:OnSystemReady()
    assert.same({ 1 }, log.searches)
  end)

  it("skips uncached keys and resumes them on OnKeyInfo", function()
    keyInfos[2] = { isCommodity = false }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1, 2 })                -- 1 uncached -> waits; 2 sent
    assert.same({ 2 }, log.searches)
    s:OnItemResults(2)
    assert.same({ 2, 2 }, log.searches) -- 1 still waiting, cycles back to 2
    keyInfos[1] = { isCommodity = false }
    s:OnKeyInfo(1)                   -- pending on 2: no immediate send
    assert.same({ 2, 2 }, log.searches)
    s:OnItemResults(2)
    assert.equal(1, log.searches[#log.searches]) -- 1 finally scanned
  end)

  it("recovers a stale pending search on ready", function()
    keyInfos[1] = { isCommodity = false }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    assert.same({ 1 }, log.searches)
    clock = 1011                     -- > 10s later, response never came
    s:OnSystemReady()
    assert.same({ 1, 1 }, log.searches)
  end)

  it("ignores results for items that are not pending", function()
    keyInfos[1] = { isCommodity = false }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    s:OnItemResults(999)
    assert.same({ 1 }, log.searches)
    assert.equal(0, s.scanned)
  end)

  it("re-alerts a still-live deal after a fresh Start (dedupe resets per scan session)", function()
    keyInfos[1] = { isCommodity = false }
    values[1] = { mv = 1000000 }
    itemResults[1] = { auctionID = 99, unitPrice = 500000, qty = 1 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    s:OnItemResults(1)
    assert.equal(1, #log.deals)   -- first session alerts
    s:Start({ 1 })                -- new scan session (simulates AH reopen), same live auction
    s:OnItemResults(1)
    assert.equal(2, #log.deals)   -- must re-alert; was 1 before the fix (deduped away)
  end)

  it("publishes every consumed result while preserving lower-price-only alerts", function()
    keyInfos[7] = { isCommodity = true }
    values[7] = { mv = 1000000 }
    commodityResults[7] = { unitPrice = 500000, qty = 10 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 7 })

    s:OnCommodityResults(7)
    commodityResults[7] = { unitPrice = 600000, qty = 10 }
    s:OnCommodityResults(7)
    commodityResults[7] = nil
    s:OnCommodityResults(7)

    assert.equal(3, #log.observations)
    assert.equal(500000, log.observations[1].deal.unitPrice)
    assert.equal(600000, log.observations[2].deal.unitPrice)
    assert.is_nil(log.observations[3].deal)
    assert.equal(1, #log.deals)
    assert.same({ "deal", "observation" }, { log.events[1], log.events[2] })
  end)

  it("publishes nil when a fetched listing no longer passes deal filters", function()
    keyInfos[1] = { isCommodity = false }
    values[1] = { mv = 1000000 }
    itemResults[1] = { auctionID = 99, unitPrice = 950000, qty = 1 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    s:OnItemResults(1)

    assert.equal(1, #log.observations)
    assert.equal(1, log.observations[1].itemID)
    assert.is_nil(log.observations[1].deal)
    assert.equal(0, #log.deals)
  end)

  it("resumes the same monitor without resetting its alert dedupe", function()
    keyInfos[1] = { isCommodity = false }
    values[1] = { mv = 1000000 }
    itemResults[1] = { auctionID = 99, unitPrice = 500000, qty = 1 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    s:OnItemResults(1)
    s:Stop()
    s:Resume()
    s:OnItemResults(1)

    assert.equal(2, #log.observations)
    assert.equal(1, #log.deals)
    assert.same({ 1, 1, 1, 1 }, log.searches)
  end)

  it("stops cleanly and refuses an empty watchlist", function()
    keyInfos[1] = { isCommodity = false }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    s:Stop()
    s:OnSystemReady()
    assert.same({ 1 }, log.searches)
    local s2 = GC.Scanner.New(drv, cfg)
    s2:Start({})
    assert.equal("empty watchlist", log.status[#log.status])
  end)

  it("sends nothing while the arbiter withholds the slot", function()
    keyInfos[1] = { isCommodity = true }
    local allowed = false
    drv.mayScan = function() return allowed end
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })
    assert.same({}, log.searches)

    s:OnSystemReady()
    assert.same({}, log.searches)

    allowed = true
    s:OnSystemReady()
    assert.same({ 1 }, log.searches)
  end)

  it("does not chain a second send off its own result", function()
    keyInfos[1] = { isCommodity = true }
    keyInfos[2] = { isCommodity = true }
    local allowed = true
    drv.mayScan = function() return allowed end
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1, 2 })
    assert.same({ 1 }, log.searches)

    allowed = false
    s:OnCommodityResults(1)          -- result lands; the tail advance must not send
    assert.same({ 1 }, log.searches)

    allowed = true
    s:OnSystemReady()
    assert.same({ 1, 2 }, log.searches)
  end)

  it("reports whether it wants a slot", function()
    keyInfos[1] = { isCommodity = true }
    local allowed = false
    drv.mayScan = function() return allowed end
    local s = GC.Scanner.New(drv, cfg)
    assert.is_false(s:Wants())       -- not started

    s:Start({ 1 })
    assert.is_true(s:Wants())        -- started, nothing in flight

    allowed = true
    s:OnSystemReady()
    assert.is_false(s:Wants())       -- query in flight

    allowed = false
    s:OnCommodityResults(1)
    assert.is_true(s:Wants())        -- answered, hungry again

    s:Stop()
    assert.is_false(s:Wants())
  end)

  it("alerts again once the price has recovered to market", function()
    keyInfos[1] = { isCommodity = true }
    values[1] = { mv = 1000, soldPerDay = 50 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })

    commodityResults[1] = { unitPrice = 400, qty = 5, avail = 5 } -- 60% under market
    s:OnCommodityResults(1)
    assert.equal(1, #log.deals)

    -- The cheap lot is bought out and the book returns to market. No deal, no alert -- but
    -- this observation must clear the remembered floor.
    commodityResults[1] = { unitPrice = 1000, qty = 5, avail = 5 }
    s:OnSystemReady(); s:OnCommodityResults(1)
    assert.equal(1, #log.deals)

    -- A new cheap lot, ABOVE the old alerted floor of 400 but still a genuine deal.
    commodityResults[1] = { unitPrice = 500, qty = 5, avail = 5 }
    s:OnSystemReady(); s:OnCommodityResults(1)
    assert.equal(2, #log.deals)
  end)

  it("still refuses to re-alert the same standing lot", function()
    keyInfos[1] = { isCommodity = true }
    values[1] = { mv = 1000, soldPerDay = 50 }
    local s = GC.Scanner.New(drv, cfg)
    s:Start({ 1 })

    commodityResults[1] = { unitPrice = 400, qty = 5, avail = 5 }
    s:OnCommodityResults(1)
    s:OnSystemReady(); s:OnCommodityResults(1)
    s:OnSystemReady(); s:OnCommodityResults(1)
    assert.equal(1, #log.deals)
  end)
end)
