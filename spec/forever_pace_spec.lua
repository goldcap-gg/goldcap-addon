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
      for _, call in ipairs(calls) do
        if call.result == position.postRecommendation then
          assert.equal(7, call.opts.sold)
          assert.equal(140, call.opts.reachUnit)
        end
      end
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
end)
