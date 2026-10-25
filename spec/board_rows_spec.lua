local helper = require("spec.spec_helper")

describe("BoardRows", function()
  local GC

  -- No locale is ever active under busted (the addon's engineering notes) -- GC.L's metatable falls back
  -- to the key itself, which IS the enUS text, so nothing here needs to load or activate a
  -- locale file; helper.loadModule's own auto-load of Locale/Core.lua (triggered by the
  -- first loadModule call below) is all GC.L needs to exist.
  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
  end)

  after_each(function() _G.GetCoinTextureString = nil end)

  describe("Bucket", function()
    -- Live price caps, addon task 6: a cap decision outranks every other bucket, including a
    -- buyable commodity cap (DecideCommodity sets BOTH `cap` and `buyable` -- `cap` must win
    -- first, or it would fall into the plain SAFE bucket it also qualifies for).
    it("is CAP when the verdict carries a cap, buyable or not", function()
      assert.equal("CAP", GC.BoardRows.Bucket({ cap = true, buyable = true }))
      assert.equal("CAP", GC.BoardRows.Bucket({ cap = true, buyable = false, status = "WATCH" }))
    end)

    it("is SAFE only when the verdict is buyable", function()
      assert.equal("SAFE", GC.BoardRows.Bucket({ buyable = true }))
    end)
    it("is WATCH for any other verdict", function()
      assert.equal("WATCH", GC.BoardRows.Bucket({ buyable = false, status = "AVOID" }))
    end)
    it("is PENDING with no verdict when something really is checking the row", function()
      assert.equal("PENDING", GC.BoardRows.Bucket(nil, true))
    end)
    it("is UNVERIFIED with no verdict and nothing checking", function()
      assert.equal("UNVERIFIED", GC.BoardRows.Bucket(nil, false))
    end)
    it("lets a verdict outrank the pending flag", function()
      assert.equal("SAFE", GC.BoardRows.Bucket({ buyable = true }, true))
      assert.equal("WATCH", GC.BoardRows.Bucket({ buyable = false }, true))
    end)
  end)

  describe("Label", function()
    it("reads YOUR PRICE for a cap verdict, ahead of SAFE's own money label", function()
      assert.equal("YOUR PRICE", GC.BoardRows.Label({ cap = true, buyable = true, stressProfit = 50000 }))
      assert.equal("YOUR PRICE", GC.BoardRows.Label({ cap = true, buyable = false, status = "WATCH" }))
    end)

    -- Followed groups (plan 2026-10-22, task 7): a cap from a group the player follows reads
    -- GROUP; the group's own name is on the row's item cell, as an alert group's is.
    it("Label says GROUP for a followed cap", function()
      assert.equal("GROUP", GC.BoardRows.Label({ cap = true, followed = true }))
      assert.equal("YOUR PRICE", GC.BoardRows.Label({ cap = true }))
      assert.equal("GROUP", GC.BoardRows.Bucket({ cap = true, followed = true }))
    end)

    -- A followed group's deal is a deal like any other (owner, 2026-10-25: the groups' rows sat
    -- over every deal at 0% and a dash): it no longer leads the board. A commodity's, whose live
    -- book was read, ranks under the buys and over the refusals; a realm lot's with the realm
    -- rows. Each by the profit it shows.
    it("ranks a followed group's deal by what it is, not over every deal", function()
      local rank = GC.BoardRows.Rank
      local commodity = { cap = true, followed = true, buyable = true }
      local realm = { cap = true, followed = true, status = "WATCH" }
      assert.is_true(rank({ cap = true }) < rank({ buyable = true })) -- the player's own price still leads
      assert.is_true(rank({ buyable = true }) < rank(commodity))
      assert.is_true(rank({ needsGold = 1000 }) < rank(commodity))
      assert.is_true(rank(commodity) < rank({ status = "WATCH" }))
      assert.equal(rank({ status = "WATCH" }), rank(realm))

      local flip = { itemID = 1, unitPrice = 100, qty = 1, estProfit = 263023 }
      local group = { itemID = 2, unitPrice = 100, qty = 1, cap = 50, estProfit = 1900 }
      assert.is_true(GC.BoardRows.Compare(flip, { status = "WATCH" }, false, group, realm, false))
      assert.is_false(GC.BoardRows.Compare(group, realm, false, flip, { status = "WATCH" }, false))
    end)

    it("reads SAFE +<money> from the verdict's stressProfit", function()
      local label = GC.BoardRows.Label({ buyable = true, stressProfit = 50000 })
      assert.equal("SAFE +5g", label)
    end)

    -- The 72px verdict cell clipped "SAFE +61g35s" -- gold only, floored, never a second unit.
    it("floors to whole gold, never gold+silver", function()
      assert.equal("SAFE +61g", GC.BoardRows.Label({ buyable = true, stressProfit = 613500 }))
    end)

    it("shows silver below 1g, never a coin-icon string", function()
      assert.equal("SAFE +64s", GC.BoardRows.Label({ buyable = true, stressProfit = 6435 }))
    end)

    -- WoW: Forever's copper economy (plan 3c, Review Focus 4): a 25c buy read "SAFE +0s".
    it("shows whole copper below 1s", function()
      assert.equal("SAFE +25c", GC.BoardRows.Label({ buyable = true, stressProfit = 25 }))
    end)

    -- The cell is one column on a row, not a place to put a sentence: the reason lives in the
    -- row tooltip and in the dialog, where there is room to read it.
    it("reads AVOID for a refused verdict whose live status is AVOID", function()
      local verdict = { buyable = false, status = "AVOID",
        reason = GC.SniperDecision.ReasonText("market_falling") }
      assert.equal("AVOID", GC.BoardRows.Label(verdict))
      assert.equal("The price is falling; buying into it is how you get stuck.",
        GC.BoardRows.Reason(verdict))
      -- The whole point of the split: the sentence is far longer than the cell.
      assert.is_true(#GC.BoardRows.Reason(verdict) > #GC.BoardRows.Label(verdict) * 4)
    end)

    -- WATCH stays the label for every other non-buyable status -- WATCH itself, "Gone", or
    -- anything else the live check can say that is not a flat AVOID. Bucket/sort are
    -- unchanged either way; only the word printed differs.
    it("reads WATCH for a refused verdict whose status is not AVOID", function()
      assert.equal("WATCH", GC.BoardRows.Label({ buyable = false, status = "WATCH" }))
      assert.equal("WATCH", GC.BoardRows.Label({ buyable = false, status = "Gone" }))
    end)

    it("reads an ellipsis while something is actually checking the row", function()
      assert.equal("…", GC.BoardRows.Label(nil, true))
    end)

    it("reads a dash when nothing is checking it", function()
      assert.equal("-", GC.BoardRows.Label(nil, false))
    end)
  end)

  describe("Reason", function()
    it("is nil with no verdict at all", function()
      assert.is_nil(GC.BoardRows.Reason(nil))
    end)
    it("is nil for a verdict that approved the buy", function()
      assert.is_nil(GC.BoardRows.Reason({ buyable = true, reason = "whatever" }))
    end)
  end)

  describe("Compare", function()
    it("ranks CAP over SAFE, regardless of profit", function()
      local rich = { estProfit = 999999 }
      local poor = { estProfit = 1 }
      assert.is_true(GC.BoardRows.Compare(poor, { cap = true, buyable = true }, false, rich, { buyable = true }, false))
    end)

    it("ranks SAFE over WATCH over pending over the rest, regardless of profit", function()
      local rich = { estProfit = 999999 }
      local poor = { estProfit = 1 }
      assert.is_true(GC.BoardRows.Compare(poor, { buyable = true }, false, rich, { buyable = false }, false))
      assert.is_true(GC.BoardRows.Compare(poor, { buyable = false }, false, rich, nil, true))
      assert.is_true(GC.BoardRows.Compare(poor, nil, true, rich, nil, false))
    end)
    it("orders by estProfit descending within the same bucket", function()
      local a = { estProfit = 100 }
      local b = { estProfit = 200 }
      assert.is_false(GC.BoardRows.Compare(a, { buyable = true }, false, b, { buyable = true }, false))
      assert.is_true(GC.BoardRows.Compare(b, { buyable = true }, false, a, { buyable = true }, false))
    end)

    -- The rows of one bucket read top to bottom by the profit they show: a checked row's is its
    -- plan's, so a huge estimate behind a one-unit Check no longer sits above a better buy.
    it("orders checked rows by the profit their Check planned, not discovery's estimate", function()
      local thin = { estProfit = 192000000 }
      local deep = { estProfit = 4000000 }
      local thinCheck = { buyable = true, quantity = 1, entryTotal = 218400, stressProfit = 225800 }
      local deepCheck = { buyable = true, quantity = 226, entryTotal = 4180000, stressProfit = 419000 }
      assert.is_true(GC.BoardRows.Compare(deep, deepCheck, false, thin, thinCheck, false))
      assert.is_false(GC.BoardRows.Compare(thin, thinCheck, false, deep, deepCheck, false))
    end)
  end)

  -- In game 2026-10-17: Glossy Stone read x85 for +2584g, and its Check bought one for +22g58s.
  describe("Figures", function()
    local floor = { itemID = 1, unitPrice = 218400, qty = 85, avail = 3639,
      profit = 25840000, estProfit = 19200000 }

    it("shows discovery's stress estimate before any Check, not the market-value profit", function()
      local qty, total, profit, checked = GC.BoardRows.Figures(floor, nil)
      assert.equal(85, qty)
      assert.equal(218400 * 85, total)
      assert.equal(19200000, profit)
      assert.is_false(checked)
    end)

    it("falls back to profit for a row that carries no estimate", function()
      local _, _, profit = GC.BoardRows.Figures({ unitPrice = 10, qty = 2, profit = 7 }, nil)
      assert.equal(7, profit)
    end)

    it("shows the Check's planned buy once there is one", function()
      local qty, total, profit, checked = GC.BoardRows.Figures(floor,
        { buyable = true, quantity = 1, entryTotal = 218400, stressProfit = 225800 })
      assert.equal(1, qty)
      assert.equal(218400, total)
      assert.equal(225800, profit)
      assert.is_true(checked)
    end)

    -- A commodity buy walks up the levels: 226 units from a 1g40s floor cost 418g, not 316g.
    it("totals what the planned units cost across the levels, not the floor times the quantity", function()
      local _, total = GC.BoardRows.Figures({ unitPrice = 14000, qty = 453, estProfit = 1 },
        { buyable = true, quantity = 226, entryTotal = 4180000, stressProfit = 419000 })
      assert.equal(4180000, total)
    end)

    it("shows a refusal's plan too, when the Check planned a buy and turned it down", function()
      local qty, _, profit, checked = GC.BoardRows.Figures(floor,
        { buyable = false, status = "AVOID", quantity = 3, entryTotal = 700000, stressProfit = 12000 })
      assert.equal(3, qty)
      assert.equal(12000, profit)
      assert.is_true(checked)
    end)

    it("keeps the estimate when the Check planned nothing", function()
      local qty, total, profit, checked = GC.BoardRows.Figures(floor,
        { buyable = false, status = "AVOID", quantity = 0 })
      assert.equal(85, qty)
      assert.equal(218400 * 85, total)
      assert.equal(19200000, profit)
      assert.is_false(checked)
    end)

    -- A realm lot's check prices the lot against the region reference and plans no stress exit.
    it("keeps the estimate for a verdict with no stress profit", function()
      local _, _, profit, checked = GC.BoardRows.Figures(floor,
        { unverified = true, status = "WATCH", quantity = 1, entryTotal = 218400 })
      assert.equal(19200000, profit)
      assert.is_false(checked)
    end)

    it("keeps a YOUR PRICE row's own figures, which its cap decision measured", function()
      local cap = { unitPrice = 100, qty = 400, capTotal = 29000000, profit = 5000, estProfit = 5000, cap = 120 }
      local qty, total, profit, checked = GC.BoardRows.Figures(cap,
        { cap = true, buyable = true, quantity = 400, entryTotal = 29000000, stressProfit = 1 })
      assert.equal(400, qty)
      assert.equal(29000000, total)
      assert.equal(5000, profit)
      assert.is_false(checked)
    end)
  end)

  describe("ProfitTone", function()
    it("is an estimate until anything has looked at the row live", function()
      assert.equal("estimate", GC.BoardRows.ProfitTone({ estProfit = 1 }, nil))
    end)

    it("is measured for a buy the check approved, one that needs gold, and a realm lot it found", function()
      assert.equal("measured", GC.BoardRows.ProfitTone({}, { buyable = true }))
      assert.equal("measured", GC.BoardRows.ProfitTone({}, { buyable = false, needsGold = 2000 }))
      assert.equal("measured", GC.BoardRows.ProfitTone({}, { buyable = false, unverified = true }))
    end)

    it("is measured for a YOUR PRICE row, checked or not", function()
      assert.equal("measured", GC.BoardRows.ProfitTone({ cap = 120 }, nil))
      assert.equal("measured", GC.BoardRows.ProfitTone({}, { cap = true }))
    end)

    it("is refused for a row the live check turned down", function()
      assert.equal("refused", GC.BoardRows.ProfitTone({}, { buyable = false, status = "AVOID" }))
    end)
  end)

  describe("Rank", function()
    it("is a plain ascending number, so a header sort can read it", function()
      assert.is_true(GC.BoardRows.Rank({ buyable = true }) < GC.BoardRows.Rank({ buyable = false }))
      assert.is_true(GC.BoardRows.Rank({ buyable = false }) < GC.BoardRows.Rank(nil, true))
      assert.is_true(GC.BoardRows.Rank(nil, true) < GC.BoardRows.Rank(nil, false))
    end)
  end)

  -- A Check the wallet limit alone refused: a deal that needs gold, not a bad one (owner report
  -- 2026-09-24 -- a character with no gold saw every row go to Hidden).
  describe("a deal that needs gold", function()
    local needs = { buyable = false, status = "AVOID", needsGold = 12345678, reason = "wallet" }

    it("is its own bucket, between a buy and a refusal", function()
      assert.equal("GOLD", GC.BoardRows.Bucket(needs))
      assert.is_true(GC.BoardRows.Rank({ buyable = true }) < GC.BoardRows.Rank(needs))
      assert.is_true(GC.BoardRows.Rank(needs) < GC.BoardRows.Rank({ buyable = false, status = "AVOID" }))
    end)

    -- The gold the character must hold, rounded up, never down: 1,234g 56s 78c is not covered by
    -- 1,234g. Eleven characters is the whole cell ("SAFE +9999g" was sized to it), so from 10,000g
    -- it counts in thousands, the way players write gold.
    it("says how much gold the character needs, rounded up, short enough for its cell", function()
      assert.equal("needs 1235g", GC.BoardRows.Label(needs))
      assert.equal("needs 1330g", GC.BoardRows.Label({ needsGold = 13300000 }))
      assert.equal("needs 5g", GC.BoardRows.Label({ needsGold = 50000 }))
      assert.equal("needs 13s", GC.BoardRows.Label({ needsGold = 1201 }))
      assert.equal("needs 5323g", GC.BoardRows.Label({ needsGold = 53224680 }))
      assert.equal("needs 400k", GC.BoardRows.Label({ needsGold = 4000000000 }))
      assert.equal("needs 11k", GC.BoardRows.Label({ needsGold = 100000001 }))
      assert.equal("needs 10k", GC.BoardRows.Label({ needsGold = 99995000 })) -- 9,999g 50s
    end)
  end)
end)

describe("GC.Util.FormatMoney", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
  end)

  after_each(function() _G.GetCoinTextureString = nil end)

  it("shows sub-gold amounts as a coin string", function()
    assert.equal("5000c", GC.Util.FormatMoney(5000))
  end)

  it("shows gold and silver below the compact threshold", function()
    assert.equal("1g50s", GC.Util.FormatMoney(15000))
  end)

  it("drops the silver when it is zero", function()
    assert.equal("2g", GC.Util.FormatMoney(20000))
  end)

  it("compacts to whole gold past 100g", function()
    assert.equal("150g", GC.Util.FormatMoney(150 * 10000))
  end)

  it("keeps the sign on a negative amount", function()
    assert.equal("-2g", GC.Util.FormatMoney(-20000))
  end)
end)

describe("GC.Util.FormatGoldFloor", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
  end)

  it("floors to whole gold at and above 1g", function()
    assert.equal("61g", GC.Util.FormatGoldFloor(613500))
  end)

  it("drops a fractional gold rather than rounding it up", function()
    assert.equal("1g", GC.Util.FormatGoldFloor(19999))
  end)

  it("shows whole silver below 1g", function()
    assert.equal("64s", GC.Util.FormatGoldFloor(6435))
  end)

  it("keeps the sign on a negative amount", function()
    assert.equal("-61g", GC.Util.FormatGoldFloor(-613500))
  end)

  it("shows whole copper below 1s, for WoW: Forever's copper economy", function()
    assert.equal("25c", GC.Util.FormatGoldFloor(25))
    assert.equal("99c", GC.Util.FormatGoldFloor(99))
    assert.equal("1s", GC.Util.FormatGoldFloor(100))
    assert.equal("0c", GC.Util.FormatGoldFloor(0))
  end)
end)

-- The gold a character must hold, wherever it is shown (the needs-gold cell, the check pane's
-- figure, caption and status line, the row tooltip): one figure, rounded UP, so a player holding
-- exactly what it says is never refused by the wallet limit. Whole gold from 1g; under it the
-- silver, then the copper, for WoW: Forever's copper economy. The cell alone may count it in
-- thousands -- still rounded up -- to fit its eleven characters.
describe("GC.Util.FormatGoldCeil", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
  end)

  it("rounds up to whole gold, never down", function()
    assert.equal("5323g", GC.Util.FormatGoldCeil(53224680)) -- 5,322g 46s 80c
    assert.equal("1330g", GC.Util.FormatGoldCeil(13300000))
    assert.equal("2g", GC.Util.FormatGoldCeil(10001))
    assert.equal("1g", GC.Util.FormatGoldCeil(10000))
    assert.equal("1g", GC.Util.FormatGoldCeil(9901)) -- 99s 1c
  end)

  it("under 1g rounds up to the silver, then to the copper", function()
    assert.equal("99s", GC.Util.FormatGoldCeil(9900))
    assert.equal("13s", GC.Util.FormatGoldCeil(1201))
    assert.equal("1s", GC.Util.FormatGoldCeil(100))
    assert.equal("99c", GC.Util.FormatGoldCeil(99))
    assert.equal("1c", GC.Util.FormatGoldCeil(1))
  end)

  it("counts in thousands, still rounded up, only when asked for the short form", function()
    assert.equal("400000g", GC.Util.FormatGoldCeil(4000000000))
    assert.equal("400k", GC.Util.FormatGoldCeil(4000000000, true))
    assert.equal("11k", GC.Util.FormatGoldCeil(100000001, true)) -- 10,001g
    assert.equal("10k", GC.Util.FormatGoldCeil(99995000, true)) -- 9,999g 50s
    assert.equal("5323g", GC.Util.FormatGoldCeil(53224680, true))
  end)
end)
