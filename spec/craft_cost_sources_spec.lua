local helper = require("spec.spec_helper")

-- Where a craft's cost can come from beyond "this character bought it at the auction house":
-- a merchant, the player's own earlier craft, another character of the account. Real
-- Core/Acquisitions.lua and Core/CraftCapture.lua; the client is a driver of API-shaped answers.
describe("craft cost sources", function()
  local GC, db, counts, runs, converted, driver_rows, market
  local me = { char = "Cook-Realm", region = "eu" }
  local alt = "Alt-Realm"
  local SPELL = { pork = 11, roast = 12, gem = 13, crush = 14 }

  local recipes = {
    [SPELL.pork] = { recipeID = 11, outputItemID = 500, isRecraft = false,
      candidates = { [10] = true, [11] = true }, outputs = { [500] = true } },
    [SPELL.roast] = { recipeID = 12, outputItemID = 600, isRecraft = false,
      candidates = { [20] = true, [500] = true }, outputs = { [600] = true } },
    -- a gem: a quality-tiered mat (two tiers) and a vendor vial
    [SPELL.gem] = { recipeID = 13, outputItemID = 700, isRecraft = false,
      candidates = { [30] = true, [31] = true, [21] = true }, outputs = { [700] = true, [701] = true } },
    [SPELL.crush] = { recipeID = 14, isRecraft = false, candidates = { [40] = true } },
  }

  local function driver()
    return {
      recipeFor = function(spellID) return recipes[spellID] end,
      countsFor = function(candidates)
        local out = {}
        for itemID in pairs(candidates) do out[itemID] = counts[itemID] or 0 end
        return out
      end,
      batchesFor = function(itemID)
        local out = {}
        for _, batch in ipairs(GC.Acquisitions.GetActive(me)) do
          if batch.itemID == itemID then out[#out + 1] = batch end
        end
        return out
      end,
      othersFor = function(itemID)
        local out = {}
        for _, batch in ipairs(GC.Acquisitions.GetActiveAccount(me)) do
          if batch.itemID == itemID and batch.character ~= me.char then out[#out + 1] = batch end
        end
        return out
      end,
      vendorUnit = function(itemID) return runs[itemID] end,
      marketUnit = function(itemID) return market[itemID] end,
      isConverted = function(itemID) return converted[itemID] == true end,
      noteConverted = function(itemID) converted[itemID] = true end,
      commodityKinds = function() return {} end,
      context = function() return me end,
      recordLedger = function(rows) driver_rows = rows end,
    }
  end

  local function buy(itemID, qty, total, at, extra)
    local fields = { source = "auction_house", itemID = itemID, positionKey = "commodity:" .. itemID,
      quantity = qty, total = total, acquiredAt = at, character = me.char, region = me.region }
    for k, v in pairs(extra or {}) do fields[k] = v end
    return GC.Acquisitions.Record(fields)
  end

  -- One crafting run: the mats leave the bags, the results arrive, the window goes quiet.
  local function craft(spell, results, after, at)
    GC.CraftCapture.OnCastSent(spell, at)
    for _, r in ipairs(results) do GC.CraftCapture.OnCraftResult(r, at) end
    for itemID, n in pairs(after) do counts[itemID] = n end
    GC.CraftCapture.Tick(at + 10)
  end

  local function lastOutcome() return GC.CraftCapture.RecentOutcomes()[1] end

  local function lot(itemID, source)
    for _, batch in ipairs(db.acquisitions) do
      if batch.itemID == itemID and (source == nil or batch.source == source) then return batch end
    end
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua", {})
    helper.loadModule("Core/CraftCapture.lua", GC)
    GC.L = setmetatable({}, { __index = function(_, k) return k end })
    GC.Util = { CoinText = function(c) return tostring(c) .. "c" end }
    db = { acquisitions = {} }
    GC.Acquisitions.Init(db)
    counts, runs, converted, market = {}, {}, {}, {}
    driver_rows = nil
    GC.CraftCapture.SetDriver(driver())
  end)

  it("chains an intermediate craft: Practically Pork is a lot the Royal Roast consumes", function()
    -- Pork = AH mats (10) + a vendor reagent bought at the merchant (11, 5c a unit, 2 stacks of 10).
    buy(10, 4, 400, 1)
    GC.Acquisitions.Record({ source = "vendor", itemID = 11, positionKey = "commodity:11",
      quantity = 4, total = 20, acquiredAt = 2, character = me.char, region = me.region })
    -- Roast = the vendor stuff (20) + the Pork.
    GC.Acquisitions.Record({ source = "vendor", itemID = 20, positionKey = "commodity:20",
      quantity = 2, total = 60, acquiredAt = 3, character = me.char, region = me.region })
    counts = { [10] = 4, [11] = 4, [20] = 2, [500] = 0 }

    craft(SPELL.pork, { { itemID = 500, quantity = 2 } }, { [10] = 0, [11] = 0, [500] = 2 }, 100)
    assert.is_nil(lastOutcome().reason)
    local pork = lot(500, "craft")
    assert.equal(420, pork.originalTotal)
    assert.equal(2, pork.originalQty)
    assert.is_nil(pork.positionKey)            -- crafted away from the auction house: keyless yet

    craft(SPELL.roast, { { itemID = 600, quantity = 1 } }, { [20] = 0, [500] = 1 }, 200)
    local outcome = lastOutcome()
    assert.is_nil(outcome.reason)
    -- 2 vendor mats (60) + one of the two Pork at 210 each
    assert.equal(270, outcome.total)
    assert.equal(1, lot(500, "craft").remainingQty)
  end)

  it("says the unbought reagent by name when the chain is broken", function()
    buy(10, 4, 400, 1)
    counts = { [10] = 4, [11] = 4 }
    craft(SPELL.pork, { { itemID = 500, quantity = 2 } }, { [10] = 0, [11] = 0 }, 100)
    local outcome = lastOutcome()
    assert.equal("uncosted", outcome.reason)
    assert.same({ { itemID = 11, quantity = 4, known = 0, why = "no_purchase" } }, outcome.missing)
    local lines = GC.CraftCapture.Describe(outcome, function(id) return "Item" .. id end)
    assert.same({ "Item11 ×4: no purchase of it found, here or on your other characters" }, lines)
    assert.same(lines, GC.CraftCapture.WhyUncosted(500, function(id) return "Item" .. id end))
  end)

  it("prices a vendor reagent bought before the install at the vendor's price and says so", function()
    buy(10, 4, 400, 1)
    runs[11] = 5                       -- a BUY list's vendor line: `vu`
    counts = { [10] = 4, [11] = 4 }
    craft(SPELL.pork, { { itemID = 500, quantity = 2 } }, { [10] = 0, [11] = 0 }, 100)
    local outcome = lastOutcome()
    assert.is_nil(outcome.reason)
    assert.equal(420, outcome.total)
    assert.same({ { itemID = 11, quantity = 4, vendorQty = 4, vendorUnit = 5 } }, outcome.reagents)
    assert.same({ "Item11: 4 at the vendor price, 5c each" },
      GC.CraftCapture.Describe(outcome, function(id) return "Item" .. id end))
  end)

  it("prices only the uncovered part at the vendor's price and spends only recorded lots", function()
    buy(11, 2, 14, 1)                  -- two bought for real at 7c
    runs[11] = 5
    buy(10, 4, 400, 1)
    counts = { [10] = 4, [11] = 4 }
    craft(SPELL.pork, { { itemID = 500, quantity = 2 } }, { [10] = 0, [11] = 0 }, 100)
    assert.equal(400 + 14 + 2 * 5, lastOutcome().total)
    assert.equal(0, lot(11, "auction_house").remainingQty)    -- the two real ones are spent
  end)

  it("draws on another character's lots only after this character's own, oldest first", function()
    buy(10, 2, 200, 5)                                         -- mine: 100 each
    buy(10, 2, 600, 1, { character = alt })                    -- the alt's older lot: 300 each
    buy(11, 4, 40, 1)
    counts = { [10] = 3, [11] = 4 }
    craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
    local outcome = lastOutcome()
    assert.is_nil(outcome.reason)
    assert.equal(200 + 300 + 40, outcome.total)                -- my two, then one of the alt's
    local mine, theirs = lot(10, nil), nil
    for _, b in ipairs(db.acquisitions) do
      if b.itemID == 10 and b.character == alt then theirs = b end
    end
    assert.equal(0, mine.remainingQty)
    assert.equal(1, theirs.remainingQty)
    assert.equal(300, theirs.remainingTotal)
    assert.is_true(outcome.reagents[1].otherCharacter)
    -- the site's ledger hears of the alt's units under the alt's name, mine under mine
    local byChar = {}
    for _, row in ipairs(driver_rows) do
      if row.kind == "consume" and row.itemID == 10 then byChar[row.char or me.char] = row.qty end
    end
    assert.same({ [me.char] = 2, [alt] = 1 }, byChar)
  end)

  it("never spends the same lot twice across two crafts", function()
    buy(10, 2, 200, 1, { character = alt })
    buy(11, 8, 80, 1)
    counts = { [10] = 2, [11] = 8 }
    craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 4 }, 100)
    assert.is_nil(lastOutcome().reason)
    counts[10] = 2                     -- the player holds two more, bought nowhere on record
    craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 300)
    assert.equal("uncosted", lastOutcome().reason)
    assert.equal("no_purchase", lastOutcome().missing[1].why)
  end)

  it("costs a gem whose recipe has a vendor reagent, from tiered mats and a merchant lot", function()
    -- tier 2 mat (31) bought at the AH; the recipe also lists tier 1 (30), which was not used
    buy(31, 6, 1200, 1)
    GC.Acquisitions.Record({ source = "vendor", itemID = 21, positionKey = "commodity:21",
      quantity = 2, total = 100, acquiredAt = 2, character = me.char, region = me.region })
    counts = { [30] = 0, [31] = 6, [21] = 2 }
    craft(SPELL.gem, { { itemID = 701, quantity = 2 } }, { [31] = 0, [21] = 0 }, 100)
    local outcome = lastOutcome()
    assert.is_nil(outcome.reason)
    assert.equal(1300, outcome.total)
    assert.equal(650, outcome.unitCost)
    assert.equal(2, lot(701, "craft").originalQty)
  end)

  it("costs a gem from mats collected from the mail before the auction house keyed them", function()
    GC.Acquisitions.Record({ source = "auction_house", itemID = 31, quantity = 6, total = 1200,
      acquiredAt = 1, character = me.char, region = me.region })          -- no positionKey
    runs[21] = 50
    counts = { [31] = 6, [21] = 2 }
    craft(SPELL.gem, { { itemID = 700, quantity = 1 } }, { [31] = 0, [21] = 0 }, 100)
    local outcome = lastOutcome()
    assert.is_nil(outcome.reason)
    assert.equal(1300, outcome.total)
    assert.equal(0, lot(31).remainingQty)
  end)

  it("names a conversion as the reason a reagent has no price", function()
    -- Crushing makes item 31 out of item 40: random outputs, never costed, but remembered.
    counts = { [40] = 3 }
    craft(SPELL.crush, { { itemID = 31, quantity = 2 }, { itemID = 30, quantity = 1 } }, { [40] = 0 }, 50)
    assert.equal("random-output", lastOutcome().reason)
    assert.same({ "this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed" },
      GC.CraftCapture.Describe(lastOutcome()))
    counts = { [30] = 0, [31] = 2, [21] = 0 }
    runs[21] = 50
    craft(SPELL.gem, { { itemID = 700, quantity = 1 } }, { [31] = 0 }, 100)
    local outcome = lastOutcome()
    assert.equal("uncosted", outcome.reason)
    assert.equal("conversion", outcome.missing[1].why)
    assert.same({ "Item31 ×2: made by prospecting, crushing or milling, not bought" },
      GC.CraftCapture.Describe(outcome, function(id) return "Item" .. id end))
  end)

  it("keeps vendor purchases out of the site ledger's consume rows", function()
    GC.Acquisitions.Record({ source = "vendor", itemID = 11, positionKey = "commodity:11",
      quantity = 4, total = 20, acquiredAt = 2, character = me.char, region = me.region })
    buy(10, 4, 400, 1)
    counts = { [10] = 4, [11] = 4 }
    craft(SPELL.pork, { { itemID = 500, quantity = 2 } }, { [10] = 0, [11] = 0 }, 100)
    local items = {}
    for _, row in ipairs(driver_rows) do if row.kind == "consume" then items[#items + 1] = row.itemID end end
    assert.same({ 10 }, items)
  end)

  it("says nothing about reagents when every price is this character's own purchase", function()
    buy(10, 4, 400, 1)
    buy(11, 4, 20, 1)
    counts = { [10] = 4, [11] = 4 }
    craft(SPELL.pork, { { itemID = 500, quantity = 2 } }, { [10] = 0, [11] = 0 }, 100)
    assert.same({}, GC.CraftCapture.Describe(lastOutcome()))
  end)

  local function names(id) return "Item" .. id end

  describe("the market price as the last resort", function()
    it("prices a reagent with no purchase and no vendor price at its market price and says so", function()
      buy(10, 4, 400, 1)
      market[11] = 128                 -- gathered: no lot, no vendor line
      counts = { [10] = 4, [11] = 3 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      local outcome = lastOutcome()
      assert.is_nil(outcome.reason)
      assert.equal(400 + 3 * 128, outcome.total)
      assert.same({ { itemID = 11, quantity = 3, marketQty = 3, marketUnit = 128 } }, outcome.reagents)
      assert.same({ "Item11: 3 at the market price, 128c each",
        "Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price" },
        GC.CraftCapture.Describe(outcome, names))
      assert.same(GC.CraftCapture.Describe(outcome, names), GC.CraftCapture.WhyEstimated(500, names))
    end)

    it("prefers a purchase, then the vendor's price, then the market price, unit by unit", function()
      buy(10, 4, 400, 1)
      buy(11, 2, 14, 1)                -- two bought for real at 7c
      runs[11] = 5
      market[11] = 999                 -- never reached: the vendor covers the rest
      counts = { [10] = 4, [11] = 4 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      local outcome = lastOutcome()
      assert.equal(400 + 14 + 2 * 5, outcome.total)
      assert.same({ { itemID = 11, quantity = 4, vendorQty = 2, vendorUnit = 5 } }, outcome.reagents)
    end)

    it("covers the rest of a partly bought reagent at the market price", function()
      buy(10, 4, 400, 1)
      buy(11, 2, 14, 1)
      market[11] = 50
      counts = { [10] = 4, [11] = 4 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      local outcome = lastOutcome()
      assert.equal(400 + 14 + 2 * 50, outcome.total)
      assert.same({ { itemID = 11, quantity = 4, marketQty = 2, marketUnit = 50 } }, outcome.reagents)
      assert.equal(0, lot(11, "auction_house").remainingQty)
    end)

    it("prices a conversion's output at the market price", function()
      buy(10, 4, 400, 1)
      converted[11] = true
      market[11] = 20
      counts = { [10] = 4, [11] = 4 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      assert.is_nil(lastOutcome().reason)
      assert.equal(400 + 80, lastOutcome().total)
    end)

    it("leaves a reagent with no price of any kind missing and the craft uncosted", function()
      buy(10, 4, 400, 1)
      counts = { [10] = 4, [11] = 3 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      local outcome = lastOutcome()
      assert.equal("uncosted", outcome.reason)
      assert.same({ { itemID = 11, quantity = 3, known = 0, why = "no_purchase" } }, outcome.missing)
      assert.is_nil(lot(500, "craft"))
    end)

    it("keeps market-priced units out of the site ledger's consume rows", function()
      buy(10, 4, 400, 1)
      market[11] = 128
      counts = { [10] = 4, [11] = 3 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      local items = {}
      for _, row in ipairs(driver_rows) do if row.kind == "consume" then items[#items + 1] = row.itemID end end
      assert.same({ 10 }, items)
    end)

    it("says nothing about an estimate when every reagent was bought", function()
      buy(10, 4, 400, 1)
      buy(11, 4, 20, 1)
      market[11] = 128
      counts = { [10] = 4, [11] = 4 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      assert.same({}, GC.CraftCapture.WhyEstimated(500, names))
    end)
  end)

  describe("an uncosted craft still spends the lots it knows", function()
    it("takes the covered units off their lots, once, and writes no output lot", function()
      buy(10, 4, 400, 1)               -- covered
      counts = { [10] = 4, [11] = 3 }  -- 11 has no price of any kind
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      assert.equal("uncosted", lastOutcome().reason)
      assert.equal(0, lot(10, "auction_house").remainingQty)
      assert.is_nil(lot(500, "craft"))
      local consumes = {}
      for _, row in ipairs(driver_rows) do consumes[#consumes + 1] = row.kind .. row.itemID end
      assert.same({ "consume10" }, consumes)
    end)

    it("spends the bought part of a partly bought reagent", function()
      buy(10, 4, 400, 1)
      buy(11, 2, 14, 1)
      counts = { [10] = 4, [11] = 4 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      assert.equal("uncosted", lastOutcome().reason)
      assert.equal(0, lot(11, "auction_house").remainingQty)
    end)

    it("does not spend a reagent bought as different variants", function()
      buy(10, 2, 200, 1, { positionKey = "item:10:a" })
      buy(10, 2, 200, 2, { positionKey = "item:10:b" })
      buy(11, 4, 20, 1)
      counts = { [10] = 4, [11] = 4 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      assert.equal("ambiguous-identity", lastOutcome().reason)
      assert.equal(2, lot(10, "auction_house").remainingQty)
      assert.equal(0, lot(11, "auction_house").remainingQty)
    end)

    it("spends the lots of a prospecting-like craft the recipe could not name an output for", function()
      buy(40, 5, 500, 1)
      counts = { [40] = 5 }
      craft(SPELL.crush, { { itemID = 41, quantity = 2 } }, { [40] = 0 }, 100)
      assert.equal("random-output", lastOutcome().reason)
      assert.equal(0, lot(40, "auction_house").remainingQty)
    end)

    it("never spends twice when the same session is settled again", function()
      buy(10, 8, 800, 1)
      counts = { [10] = 4, [11] = 3 }
      craft(SPELL.pork, { { itemID = 500, quantity = 1 } }, { [10] = 0, [11] = 0 }, 100)
      assert.equal(4, lot(10, "auction_house").remainingQty)
      -- the same evidence read again: the plan is rebuilt from the same lots
      local session = { recipe = recipes[SPELL.pork], before = { [10] = 4, [11] = 3 },
        after = { [10] = 0, [11] = 0 }, results = { { itemID = 500, quantity = 1 } } }
      local plan = GC.CraftCapture.Plan(session)
      local _, _, _, covered = GC.CraftCapture.Cost(plan.consumed, driver().batchesFor, {})
      local key = "craft:11:100:1"
      local first, firstSpent = GC.CraftCapture.Spend(covered, me, 100, key)
      assert.is_false(first)             -- the real run's own evidence key was this one
      assert.equal(0, #firstSpent)
      assert.equal(4, lot(10, "auction_house").remainingQty)
    end)
  end)
end)
