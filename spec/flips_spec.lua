local helper = require("spec.spec_helper")

describe("Data.Flips (Sniper v2 §D)", function()
  local GC, db

  local function purchase(overrides)
    local facts = {
      itemID = 1,
      quantity = 1,
      total = 1,
      unitDisplay = 1,
      decisionVersion = 1,
      decisionStatus = "SAFE",
      decisionReasons = {},
      stressUnit = 2,
      expectedProfit = 1,
      recommendedQuantity = 1,
      sourceAt = 1,
    }
    for k, v in pairs(overrides or {}) do facts[k] = v end
    return facts
  end

  before_each(function()
    GC = helper.loadModule("Core/Data.lua")
    db = { settings = {} }
    GC.db = db
    GC.Data.Init(db)
  end)

  describe("RecordFlip", function()
    it("appends a flip with the full recorded shape", function()
      GC.Data.SetImported({ region = "eu", realm = "x", ts = 1,
        items = { [42] = { m = 100000 } }, watchlist = {} })
      local flip = GC.Data.RecordFlip({ itemID = 42 }, purchase({
        itemID = 42, quantity = 3, total = 60000, unitDisplay = 20000, stressUnit = 95000,
      }), 5000)
      assert.equal(42, flip.itemID)
      assert.equal(3, flip.qty)
      assert.equal(20000, flip.paidUnit)
      assert.equal(60000, flip.paidTotal)
      assert.equal(5000, flip.boughtAt)
      assert.equal(95000, flip.targetUnit) -- floor(100000 * 0.95)
      assert.same({ flip }, GC.Data.GetFlips(5000))
    end)

    it("records the exact purchase total and the decision stress target", function()
      local flip = GC.Data.RecordFlip({ itemID = 7 }, purchase({
        itemID = 7, quantity = 2, total = 201, unitDisplay = 100, stressUnit = 190000,
      }), 0)
      assert.equal(2, flip.qty)
      assert.equal(201, flip.paidTotal)
      assert.equal(100, flip.paidUnit)
      assert.equal(190000, flip.targetUnit)
    end)

    it("records an upstream-valid zero source timestamp without losing exact cost", function()
      local flip = GC.Data.RecordFlip({ itemID = 7 }, purchase({
        itemID = 7, quantity = 2, total = 201, unitDisplay = 100, stressUnit = 190000, sourceAt = 0,
      }), 0)
      assert.equal(201, flip.paidTotal)
      assert.same({ flip }, GC.Data.GetFlips(0))
    end)

    it("returns nil for a direct call without immutable purchase facts", function()
      assert.is_nil(GC.Data.RecordFlip({ itemID = 999, qty = 1, unitPrice = 5000 }, nil, 100))
    end)

    it("rejects incomplete purchase facts instead of creating an unaudited flip", function()
      local incomplete = purchase()
      incomplete.decisionStatus = nil
      assert.is_nil(GC.Data.RecordFlip({ itemID = 1 }, incomplete, 100))
    end)

    it("defaults `now` to the current time when omitted", function()
      local realTime = _G.time
      _G.time = function() return 42424242 end
      local flip = GC.Data.RecordFlip({ itemID = 1 }, purchase(), nil)
      _G.time = realTime
      assert.equal(42424242, flip.boughtAt)
    end)

    it("accumulates multiple flips in order", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase({ total = 10, unitDisplay = 10 }), 0)
      GC.Data.RecordFlip({ itemID = 2 }, purchase({ itemID = 2, quantity = 2, total = 40, unitDisplay = 20 }), 1)
      local flips = GC.Data.GetFlips(1)
      assert.equal(2, #flips)
      assert.equal(1, flips[1].itemID)
      assert.equal(2, flips[2].itemID)
    end)
  end)

  describe("GetFlips pruning", function()
    local FOURTEEN_DAYS = 14 * 24 * 3600

    it("keeps a flip exactly at the 14-day boundary (age == max, not yet OVER it)", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)
      assert.equal(1, #GC.Data.GetFlips(FOURTEEN_DAYS))
    end)

    it("prunes a flip one second past the 14-day boundary", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)
      assert.equal(0, #GC.Data.GetFlips(FOURTEEN_DAYS + 1))
    end)

    it("prunes a flip marked posted regardless of age", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)
      GC.Data.MarkFlipPosted(1)
      assert.equal(0, #GC.Data.GetFlips(0))
    end)

    it("leaves other flips alone when pruning one by age", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)                 -- will be pruned
      GC.Data.RecordFlip({ itemID = 2 }, purchase({ itemID = 2 }), FOURTEEN_DAYS + 1) -- still fresh at the same `now`
      local flips = GC.Data.GetFlips(FOURTEEN_DAYS + 1)
      assert.equal(1, #flips)
      assert.equal(2, flips[1].itemID)
    end)

    it("defaults `now` to the current time when omitted", function()
      local realTime = _G.time
      _G.time = function() return 0 end
      GC.Data.RecordFlip({ itemID = 1 }, purchase())
      _G.time = function() return FOURTEEN_DAYS + 1 end
      local flips = GC.Data.GetFlips()
      _G.time = realTime
      assert.equal(0, #flips)
    end)

    it("returns an empty list when nothing has ever been recorded", function()
      assert.same({}, GC.Data.GetFlips(0))
    end)
  end)

  describe("MarkFlipPosted / RemoveFlip", function()
    it("marks the entry at the given index posted (pruned on the next GetFlips)", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)
      GC.Data.RecordFlip({ itemID = 2 }, purchase({ itemID = 2 }), 0)
      GC.Data.MarkFlipPosted(1)
      local flips = GC.Data.GetFlips(0)
      assert.equal(1, #flips)
      assert.equal(2, flips[1].itemID)
    end)

    it("removes the entry at the given index immediately, without needing a prune pass", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)
      GC.Data.RecordFlip({ itemID = 2 }, purchase({ itemID = 2 }), 0)
      GC.Data.RemoveFlip(1)
      local flips = GC.Data.GetFlips(0)
      assert.equal(1, #flips)
      assert.equal(2, flips[1].itemID)
    end)

    it("is a no-op for an out-of-range index", function()
      GC.Data.RecordFlip({ itemID = 1 }, purchase(), 0)
      GC.Data.MarkFlipPosted(99)
      GC.Data.RemoveFlip(99)
      assert.equal(1, #GC.Data.GetFlips(0))
    end)
  end)

  describe("before GC.Data.Init has ever run", function()
    it("RecordFlip/GetFlips/MarkFlipPosted/RemoveFlip all tolerate a nil db without erroring", function()
      local GC2 = helper.loadModule("Core/Data.lua")
      assert.has_no.errors(function()
        assert.is_nil(GC2.Data.RecordFlip({ itemID = 1 }, purchase(), 0))
        assert.same({}, GC2.Data.GetFlips(0))
        GC2.Data.MarkFlipPosted(1)
        GC2.Data.RemoveFlip(1)
      end)
    end)
  end)
end)
