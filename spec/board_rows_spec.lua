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
      assert.equal("—", GC.BoardRows.Label(nil, false))
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
      assert.equal("needs 1g", GC.BoardRows.Label({ needsGold = 1201 }))
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
end)

-- The gold a character must hold, wherever it is shown (the needs-gold cell, the check pane's
-- figure, caption and status line, the row tooltip): one figure, rounded UP to whole gold, so a
-- player holding exactly what it says is never refused by the wallet limit. The cell alone may
-- count it in thousands -- still rounded up -- to fit its eleven characters.
describe("GC.Util.FormatGoldCeil", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
  end)

  it("rounds up to whole gold, never down", function()
    assert.equal("5323g", GC.Util.FormatGoldCeil(53224680)) -- 5,322g 46s 80c
    assert.equal("1330g", GC.Util.FormatGoldCeil(13300000))
    assert.equal("2g", GC.Util.FormatGoldCeil(10001))
    assert.equal("1g", GC.Util.FormatGoldCeil(1))
  end)

  it("counts in thousands, still rounded up, only when asked for the short form", function()
    assert.equal("400000g", GC.Util.FormatGoldCeil(4000000000))
    assert.equal("400k", GC.Util.FormatGoldCeil(4000000000, true))
    assert.equal("11k", GC.Util.FormatGoldCeil(100000001, true)) -- 10,001g
    assert.equal("10k", GC.Util.FormatGoldCeil(99995000, true)) -- 9,999g 50s
    assert.equal("5323g", GC.Util.FormatGoldCeil(53224680, true))
  end)
end)
