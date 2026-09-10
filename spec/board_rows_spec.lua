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
    it("is UNVERIFIED with no verdict at all", function()
      assert.equal("UNVERIFIED", GC.BoardRows.Bucket(nil))
    end)
  end)

  describe("Label", function()
    it("reads SAFE +<money> from the verdict's stressProfit", function()
      local label = GC.BoardRows.Label({}, { buyable = true, stressProfit = 50000 })
      assert.equal("SAFE +5g", label)
    end)
    it("reads WATCH <reason> for a refused verdict", function()
      local label = GC.BoardRows.Label({}, { buyable = false, reason = "too thin" })
      assert.equal("WATCH too thin", label)
    end)
    it("reads checking… with no verdict yet", function()
      assert.equal("WATCH — checking…", GC.BoardRows.Label({}, nil))
    end)
    it("appends the falling marker when the deal is falling", function()
      local label = GC.BoardRows.Label({ falling = true }, nil)
      assert.matches("checking….*v", label)
    end)
  end)

  describe("Compare", function()
    it("ranks SAFE ahead of WATCH ahead of UNVERIFIED regardless of profit", function()
      local safe = { estProfit = 1 }
      local watch = { estProfit = 999999 }
      local unverified = { estProfit = 999999 }
      assert.is_true(GC.BoardRows.Compare(safe, { buyable = true }, watch, { buyable = false }))
      assert.is_true(GC.BoardRows.Compare(watch, { buyable = false }, unverified, nil))
    end)
    it("orders by estProfit descending within the same bucket", function()
      local a = { estProfit = 100 }
      local b = { estProfit = 200 }
      assert.is_false(GC.BoardRows.Compare(a, { buyable = true }, b, { buyable = true }))
      assert.is_true(GC.BoardRows.Compare(b, { buyable = true }, a, { buyable = true }))
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
