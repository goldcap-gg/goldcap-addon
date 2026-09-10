local helper = require("spec.spec_helper")

describe("BoardRows", function()
  local GC

  -- No locale is ever active under busted (addon/AGENTS.md) -- GC.L's metatable falls back
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
    it("reads SAFE +<money> from the verdict's stressProfit", function()
      local label = GC.BoardRows.Label({ buyable = true, stressProfit = 50000 })
      assert.equal("SAFE +5g", label)
    end)

    -- The cell is one column on a row, not a place to put a sentence: the reason lives in the
    -- row tooltip and in the dialog, where there is room to read it.
    it("reads a bare WATCH for a refused verdict, whatever the reason says", function()
      local verdict = { buyable = false, status = "AVOID",
        reason = GC.SniperDecision.ReasonText("market_falling") }
      assert.equal("WATCH", GC.BoardRows.Label(verdict))
      assert.equal("The price is falling; buying into it is how you get stuck.",
        GC.BoardRows.Reason(verdict))
      -- The whole point of the split: the sentence is far longer than the cell.
      assert.is_true(#GC.BoardRows.Reason(verdict) > #GC.BoardRows.Label(verdict) * 4)
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
