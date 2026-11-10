local helper = require("spec.spec_helper")

-- WoW: Forever posts by sale pace (plan 2026-11-09, Task 4): Core/ForeverPace.lua, loaded only by
-- GoldCap_Camelot.toc, reads the auction house's sale tape (GC.Data.ForeverSales, which
-- GC.SellPositions.Build keeps on `position.tape`) into the units that sell within each of
-- Forever's three durations, and picks 24 h for a slow seller. The overcut it pays for: SELL's
-- post recommendation, and only it, hears the tape's rate and median (A5).
describe("WoW: Forever's sale pace", function()
  local HOURS = { 2, 8, 24 }
  local function hoursOf(index) return HOURS[index] end

  local function pace()
    return helper.loadModule("Core/ForeverPace.lua", {}).ForeverPace
  end

  local function ctx(fields)
    local c = { hoursOf = hoursOf, settingIndex = 2, slowOn = true,
      streakFor = function() return 0, 0, nil end, recent = {} }
    for k, v in pairs(fields or {}) do c[k] = v end
    return c
  end

  local function tape(perDay) return { units = 0, sales = 0, perDay = perDay, hours = 168 } end

  it("names its constants", function()
    local P = pace()
    assert.equal(3, P.RETURN_HOLD)
    assert.equal(0.5, P.SLOW_EXPECTED)
    assert.equal(2, P.SLOW_SHORT_ROUNDS)
  end)

  describe("Target", function()
    for _, case in ipairs({ { 0, 8, 1 }, { 3, 8, 1 }, { 10, 8, 4 }, { 12, 2, 1 }, { 12.5, 2, 2 },
      { 0.2, 24, 1 }, { 48, 24, 48 } }) do
      it(("%s a day over %d h is %d"):format(tostring(case[1]), case[2], case[3]), function()
        assert.equal(case[3], pace().Target(case[1], case[2]))
      end)
    end

    -- Review of Tasks 4-5, M1: 1 is the answer for "nobody buys it", not for "no idea".
    it("is no pace when the hours or the rate are unknown", function()
      local P = pace()
      assert.is_nil(P.Target(3, nil))
      assert.is_nil(P.Target(3, 0))
      assert.is_nil(P.Target(3, 0 / 0))
      assert.is_nil(P.Target(nil, 8))
    end)
  end)

  describe("Decorate sets one target per duration", function()
    for _, case in ipairs({ { 3, { 1, 1, 3 } }, { 10, { 1, 4, 10 } }, { 0, { 1, 1, 1 } } }) do
      it(("at %d a day"):format(case[1]), function()
        local position = { itemID = 10, positionKey = "commodity:10", bagQty = 4, ownedLots = {},
          tape = tape(case[1]) }
        pace().Decorate(position, ctx({ slowOn = false }))
        assert.same(case[2], position.paceTargets)
        assert.equal(case[1], position.pacePerDay)
        assert.equal(168, position.paceHours)
      end)
    end

    it("no hours, no targets: every unit goes up", function()
      local position = { itemID = 10, positionKey = "commodity:10", bagQty = 4, ownedLots = {}, tape = tape(3) }
      pace().Decorate(position, ctx({ slowOn = false, hoursOf = function() return nil end }))
      assert.is_nil(position.paceTargets)
    end)

    it("no tape, no targets", function()
      local position = { itemID = 10, positionKey = "commodity:10", bagQty = 4, ownedLots = {} }
      pace().Decorate(position, ctx())
      assert.is_nil(position.paceTargets)
      assert.is_nil(position.pacePerDay)
      assert.is_nil(position.paceHours)
    end)

    it("keeps the item's returns from streakFor", function()
      local asked
      local position = { itemID = 10, positionKey = "commodity:10", bagQty = 4, ownedLots = {} }
      pace().Decorate(position, ctx({ slowOn = false,
        streakFor = function(itemID) asked = itemID; return 3, 1, 2 end }))
      assert.equal(10, asked)
      assert.same({ 3, 1, 2 }, { position.returnRounds, position.returnShort, position.returnShortIndex })
    end)
  end)

  -- Setting 2 (8 h), slow sellers on and four in the bags unless the case says otherwise.
  describe("the slow rule", function()
    local CASES = {
      { "nobody buys it", { perDay = 0 }, 3, "pace" },
      { "under half a sale in 8 h", { perDay = 1 }, 3, "pace" },
      { "half a sale in 8 h is not slow", { perDay = 1.5 } },
      { "came back unsold twice under 24 h", { short = 2 }, 3, "history" },
      { "once is not a run", { short = 1 } },
      { "a group's duration wins", { perDay = 0, ruleDurationIndex = 3 } },
      { "a group rule with no duration", { perDay = 0, rule = { name = "Herbs" } }, 3, "pace" },
      { "slow sellers off", { perDay = 0, slowOn = false } },
      { "the setting is already 24 h", { perDay = 0, setting = 3 } },
      { "nothing in the bags", { perDay = 0, bagQty = 0 } },
    }

    for _, case in ipairs(CASES) do
      it(case[1], function()
        local f = case[2]
        local position = { itemID = 10, positionKey = "commodity:10", ownedLots = {},
          bagQty = f.bagQty == nil and 4 or f.bagQty, rule = f.rule, ruleDurationIndex = f.ruleDurationIndex,
          tape = f.perDay ~= nil and tape(f.perDay) or nil }
        pace().Decorate(position, ctx({ settingIndex = f.setting or 2, slowOn = f.slowOn ~= false,
          streakFor = function() return f.short or 0, f.short or 0, f.short and 2 or nil end }))
        assert.equal(case[3], position.slowDurationIndex)
        assert.equal(case[4], position.slowWhy)
      end)
    end

    it("checks the pace first", function()
      local position = { itemID = 10, positionKey = "commodity:10", ownedLots = {}, bagQty = 4, tape = tape(0) }
      pace().Decorate(position, ctx({ streakFor = function() return 2, 2, 2 end }))
      assert.equal("pace", position.slowWhy)
    end)
  end)

  it("a lot posted this visit counts until the owned list holds it", function()
    local position = { itemID = 10, positionKey = "commodity:10", bagQty = 4, tape = tape(3),
      ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 100 } } }
    pace().Decorate(position, ctx({ recent = { ["commodity:10"] = {
      { auctionID = 7, quantity = 1, unitPrice = 100 }, { auctionID = 9, quantity = 2, unitPrice = 100 } } } }))
    assert.same({ { auctionID = 9, quantity = 2, unitPrice = 100 } }, position.paceRecent)
  end)

  it("variants get nothing", function()
    local position = { itemID = 10, positionKey = "item:10:0:5:0", variantKind = "suffix", bagQty = 4,
      ownedLots = {}, tape = tape(0) }
    local before = {}
    for k, v in pairs(position) do before[k] = v end
    pace().Decorate(position, ctx({ streakFor = function() return 3, 3, 1 end,
      recent = { ["item:10:0:5:0"] = { { auctionID = 9, quantity = 1, unitPrice = 100 } } } }))
    assert.same(before, position)
  end)

  -- The overcut it pays for (A5): RecommendPost climbs above the cheapest ask only with a sales
  -- rate and a ceiling, which Forever's market data does not carry. The tape gives both, to SELL's
  -- post recommendation alone.
  describe("Build", function()
    local GC, calls

    local CONTEXT = { char = "A-R", region = "eu" }

    before_each(function()
      GC = helper.loadModule("Core/Acquisitions.lua")
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      GC.db = { settings = { sniper = {} } }
      calls = {}
      local recommend = GC.Flips.RecommendPost
      GC.Flips.RecommendPost = function(paidUnit, marketUnit, mv, opts)
        local result = recommend(paidUnit, marketUnit, mv, opts)
        calls[#calls + 1] = { opts = opts or {}, result = result }
        return result
      end
    end)

    -- Twenty of commodity 10 in the bags, quoted fresh at 120.
    local function build(salesFor, stats)
      calls = {}
      return GC.SellPositions.Build({ acquisitions = {}, ownedLots = {},
        bagStock = { { positionKey = "commodity:10", itemID = 10, itemName = "Herb", quantity = 20, isCommodity = true } },
        quotes = { [10] = { unit = 120, at = 9 } }, statsByItemID = stats or {}, context = CONTEXT, now = 10,
        salesFor = salesFor })[1]
    end

    local function sales(fields)
      local t = { units = 40, sales = 5, median = 150, perDay = 4, hours = 72 }
      -- false takes the field out.
      for k, v in pairs(fields or {}) do t[k] = v ~= false and v or nil end
      return function(itemID) return itemID == 10 and t or nil end
    end

    it("A5: only the post recommendation hears the tape", function()
      local position = build(sales())
      assert.same({ units = 40, sales = 5, median = 150, perDay = 4, hours = 72 }, position.tape)
      local heard = 0
      for _, call in ipairs(calls) do
        if call.opts.sold ~= nil then
          heard = heard + 1
          assert.equal(4, call.opts.sold)
          assert.equal(150, call.opts.reachUnit)
          assert.equal(position.postRecommendation, call.result)
        end
      end
      assert.equal(1, heard)
      assert.is_true(#calls > 1)
    end)

    for _, case in ipairs({
      { "a tape under 72 h", { hours = 71 } },
      { "under five sales", { sales = 4 } },
      { "no median", { median = false } },
    }) do
      it("A5: " .. case[1] .. " is not heard", function()
        build(sales(case[2]))
        for _, call in ipairs(calls) do assert.is_nil(call.opts.sold) end
      end)
    end

    it("A5: not with overcut off", function()
      GC.db.settings.sniper.overcut = false
      build(sales())
      for _, call in ipairs(calls) do
        assert.is_nil(call.opts.sold)
        assert.is_nil(call.opts.reachUnit)
      end
    end)

    it("A5: the market's own rate and reach come first", function()
      local position = build(sales(), { [10] = { mv = 130, sold = 7, reach = 140 } })
      local matched = 0
      for _, call in ipairs(calls) do
        if call.result == position.postRecommendation then
          matched = matched + 1
          assert.equal(7, call.opts.sold)
          assert.equal(140, call.opts.reachUnit)
        end
      end
      assert.equal(1, matched)
    end)

    -- Review of Tasks 4-5, M5: a tape whose newest hour is more than TAPE_STALE_HOURS old says
    -- nothing about today's auction house: no pace from it, and no overcut.
    it("a stale tape is no tape", function()
      local function at(age)
        local t = { units = 40, sales = 5, median = 150, perDay = 4, hours = 72, at = 1000 }
        return GC.SellPositions.Build({ acquisitions = {}, ownedLots = {},
          bagStock = { { positionKey = "commodity:10", itemID = 10, itemName = "Herb", quantity = 20, isCommodity = true } },
          quotes = { [10] = { unit = 120, at = 1000 + age - 1 } }, statsByItemID = {}, context = CONTEXT,
          now = 1000 + age, salesFor = function() return t end })[1]
      end
      assert.equal(72, GC.SellPositions.TAPE_STALE_HOURS)
      assert.is_not_nil(at(72 * 3600).tape)
      calls = {}
      assert.is_nil(at(72 * 3600 + 1).tape)
      for _, call in ipairs(calls) do assert.is_nil(call.opts.sold) end
    end)

    it("retail builds no tape", function()
      local stats = { [10] = { mv = 130, sold = 7, reach = 140, p25 = 110, trend = 3 } }
      local position = build(nil, stats)
      assert.is_nil(position.tape)
      local retail = calls
      -- A tape that names nothing for the item gives the very same calls.
      build(function() return nil end, stats)
      assert.equal(#retail, #calls)
      for i, call in ipairs(calls) do assert.same(retail[i].opts, call.opts) end
      for _, call in ipairs(retail) do
        assert.equal(7, call.opts.sold)
        assert.equal(140, call.opts.reachUnit)
      end
    end)

    it("a variant's position keeps no tape", function()
      local asked = false
      local position = GC.SellPositions.Build({ acquisitions = {}, ownedLots = {},
        bagStock = { { positionKey = "item:10:0:0:3", itemID = 10, quoteKey = "item:10:0:0:3", itemName = "Cage",
          quantity = 1 } },
        quotes = {}, statsByItemID = {}, context = CONTEXT, now = 10,
        salesFor = function() asked = true; return { units = 1, sales = 1, perDay = 1, hours = 72 } end })[1]
      assert.equal("pet", position.variantKind)
      assert.is_nil(position.tape)
      assert.is_false(asked)
    end)
  end)

  -- Review of Tasks 4-5, I2: A5 prices a post one rung above a tiny cheap lot, and the repost
  -- advice, which does not hear the tape, relists at the match price. Weighed against that, our own
  -- fresh overcut post read as an undercut worth its deposit, and CANCEL offered it; POST then
  -- relisted at the same rung, and every round lost the deposit. On WoW: Forever the cancel is
  -- weighed against the price POST would relist at.
  describe("our own overcut post", function()
    local GC
    local CONTEXT = { char = "A-R", region = "eu" }
    local KEY = "commodity:42"
    -- 24 a day: the one unit under the 1g40s rung is an hour of sales, inside the two the climb
    -- allows (GC.Flips.OVERCUT_ABSORB_HOURS; 8 a day was inside the six it allowed until 0.27.3).
    local TAPE = { units = 90, sales = 36, median = 15000, perDay = 24, hours = 90 }

    before_each(function()
      GC = helper.loadModule("Core/Acquisitions.lua")
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      helper.loadModule("Core/CancelQueue.lua", GC)
      GC.db = { settings = { sniper = {} } }
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
    end)
    after_each(function() _G.C_AuctionHouse = nil end)

    -- Eight bought through Deals (so the repost advice runs), a book of 1 at 1g, 10 at 1g40s and
    -- 5 at 2g, with our own lots on it.
    local function build(owned, bagQty, forfeit)
      local levels = { { unitPrice = 10000, quantity = 1 }, { unitPrice = 14000, quantity = 10 },
        { unitPrice = 20000, quantity = 5 } }
      for _, lot in ipairs(owned) do
        local placed = false
        for _, level in ipairs(levels) do
          if level.unitPrice == lot.unitPrice then level.quantity, placed = level.quantity + lot.quantity, true end
        end
        if not placed then levels[#levels + 1] = { unitPrice = lot.unitPrice, quantity = lot.quantity } end
      end
      table.sort(levels, function(a, b) return a.unitPrice < b.unitPrice end)
      return GC.SellPositions.Build({
        acquisitions = { { id = "acq:1", source = "goldcap", itemID = 42, positionKey = KEY, remainingQty = 8,
          remainingTotal = 8 * 6000, acquiredAt = 1, character = CONTEXT.char, region = CONTEXT.region } },
        ownedLots = owned,
        bagStock = bagQty > 0 and { { positionKey = KEY, itemID = 42, itemName = "Herb", quantity = bagQty,
          isCommodity = true } } or {},
        quotes = { [42] = { unit = 10000, at = 9, levels = levels } },
        statsByItemID = { [42] = { mv = 12000, source = "scan" } }, context = CONTEXT, now = 10,
        salesFor = function() return TAPE end, cancelForfeit = function() return forfeit or 500 end,
        oneLevelPerItem = true })[1]
    end

    local function lot(unit, qty)
      return { itemID = 42, positionKey = KEY, quantity = qty, unitPrice = unit, auctionID = 901, firstSeenAt = 5 }
    end

    -- Owner's client, 2026-11-11: Linen Cloth selling 45,000 a day, 96 units at 23c, 6,700 at 24c,
    -- 5,500 at 25c. POST chose 25c behind 6,800 units, 3.6 hours of sales, for one copper more
    -- than the 24c rung with 96 units under it.
    it("climbs no further than two hours of the tape's sales", function()
      local levels = { { unitPrice = 23, quantity = 96 }, { unitPrice = 24, quantity = 6700 },
        { unitPrice = 25, quantity = 5500 }, { unitPrice = 26, quantity = 5800 }, { unitPrice = 27, quantity = 7900 } }
      local p = GC.SellPositions.Build({
        acquisitions = {}, ownedLots = {},
        bagStock = { { positionKey = KEY, itemID = 42, itemName = "Linen Cloth", quantity = 18, isCommodity = true } },
        quotes = { [42] = { unit = 23, at = 9, levels = levels } },
        statsByItemID = { [42] = { mv = 25, source = "scan" } }, context = CONTEXT, now = 10,
        salesFor = function() return { units = 195000, sales = 5000, median = 26, perDay = 45000, hours = 104 } end,
        cancelForfeit = function() return 100 end, oneLevelPerItem = true })[1]
      assert.equal(24, p.postRecommendation.unit)
    end)

    it("is not offered for cancel", function()
      local before = build({}, 8)
      assert.equal("overcut", before.postRecommendation.mode)
      assert.equal(14000, before.postRecommendation.unit)
      local after = build({ lot(14000, 3) }, 5)
      assert.equal(14000, after.postRecommendation.unit)
      assert.is_false(after.ownedLots[1].cancelWorth)
      local entries, skipped = GC.CancelQueue.Build({ after }, { undercutPct = 0 })
      assert.equal(0, #entries)
      assert.equal("deposit", skipped[1].reason)
    end)

    it("is not offered for cancel with nothing left in the bags", function()
      local after = build({ lot(14000, 3) }, 0)
      assert.is_nil(after.postRecommendation)
      assert.is_false(after.ownedLots[1].cancelWorth)
      local entries, skipped = GC.CancelQueue.Build({ after }, { undercutPct = 0 })
      assert.equal(0, #entries)
      assert.equal("deposit", skipped[1].reason)
    end)

    it("a lot above the rung POST would use is still weighed as before", function()
      local after = build({ lot(14100, 3) }, 5, 100)
      assert.equal(14000, after.postRecommendation.unit)
      assert.is_true(after.ownedLots[1].cancelWorth) -- 1s a unit over 1g40s, three units: 3s against 1s
      local entries = GC.CancelQueue.Build({ after }, { undercutPct = 0 })
      assert.equal(901, entries[1].auctionID)
      -- ...and with a forfeit over that premium it is held.
      assert.is_false(build({ lot(14100, 3) }, 5, 300).ownedLots[1].cancelWorth)
    end)
  end)
end)
