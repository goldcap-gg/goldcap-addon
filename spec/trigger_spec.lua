local helper = require("spec.spec_helper")

describe("Trigger", function()
  local GC
  local settings = { minimumProfitCopper = 50000, minimumRoi = 0.10 }

  before_each(function()
    GC = helper.loadModule("Core/Trigger.lua")
  end)

  it("returns nil for a nil value", function()
    assert.is_nil(GC.Trigger.For(nil, settings))
  end)

  it("returns nil when mv is missing", function()
    assert.is_nil(GC.Trigger.For({ stressUnit = 200000 }, settings))
  end)

  it("returns nil when mv is zero or negative", function()
    assert.is_nil(GC.Trigger.For({ mv = 0, stressUnit = 200000 }, settings))
    assert.is_nil(GC.Trigger.For({ mv = -100, stressUnit = 200000 }, settings))
  end)

  it("returns nil when stressUnit is missing -- no V fact", function()
    assert.is_nil(GC.Trigger.For({ mv = 250000 }, settings))
  end)

  it("returns nil when stressUnit is zero or negative", function()
    assert.is_nil(GC.Trigger.For({ mv = 250000, stressUnit = 0 }, settings))
  end)

  it("caps the exit at mv when stressUnit is above it", function()
    -- exit = min(300000, 250000) = 250000; netExit = 237500
    -- byProfit = 237500 - 50000 = 187500; byRoi = 237500 / 1.10 = 215909.09 -> trigger = 187500
    assert.equal(187500, GC.Trigger.For({ mv = 250000, stressUnit = 300000 }, settings))
  end)

  it("uses stressUnit as the exit when it is below mv", function()
    -- exit = min(200000, 250000) = 200000; netExit = 190000
    -- byProfit = 190000 - 50000 = 140000; byRoi = 190000 / 1.10 = 172727.27 -> trigger = 140000
    assert.equal(140000, GC.Trigger.For({ mv = 250000, stressUnit = 200000 }, settings))
  end)

  it("binds on the ROI floor when it is the stricter one", function()
    local trigger = GC.Trigger.For({ mv = 250000, stressUnit = 200000 },
      { minimumProfitCopper = 50000, minimumRoi = 1.0 })
    -- netExit = 190000; byRoi = 190000 / 2 = 95000, stricter than byProfit's 140000
    assert.equal(95000, trigger)
  end)

  it("returns nil when neither floor leaves a positive trigger", function()
    assert.is_nil(GC.Trigger.For({ mv = 250000, stressUnit = 200000 },
      { minimumProfitCopper = 250000, minimumRoi = 0.10 }))
  end)

  it("floors a fractional ROI-bound trigger to a whole copper", function()
    -- netExit = 190000; byProfit = 190000 (profit floor is 0); byRoi = 190000/1.10 = 172727.27...
    local trigger = GC.Trigger.For({ mv = 250000, stressUnit = 200000 },
      { minimumProfitCopper = 0, minimumRoi = 0.10 })
    assert.equal(172727, trigger)
  end)
end)

describe("Trigger.RealmReference", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Trigger.lua")
  end)

  it("is nil without a value, and without either price", function()
    assert.is_nil(GC.Trigger.RealmReference(nil))
    assert.is_nil(GC.Trigger.RealmReference({}))
    assert.is_nil(GC.Trigger.RealmReference({ mv = 0, ref = -1 }))
  end)

  -- Measured in game 2026-09-11, before the T section shipped: an item with two listings on
  -- the realm (90,000 and 5.4 million) had a "median" of 2.7 million, and the board offered
  -- the cheap one as 97% off with 2.5 million gold of profit that could never be realised.
  -- A realm median is not a reference, however lonely the item.
  it("refuses a realm median with no region reference behind it", function()
    assert.is_nil(GC.Trigger.RealmReference({ mv = 500 }))
    assert.is_nil(GC.Trigger.RealmReference({ mv = 2746440, ref = 0 }))
  end)

  it("takes the region reference on its own", function()
    assert.equal(900, GC.Trigger.RealmReference({ ref = 900 }))
  end)

  it("takes the lower of the two when both exist", function()
    assert.equal(500, GC.Trigger.RealmReference({ mv = 500, ref = 900 }))
    assert.equal(400, GC.Trigger.RealmReference({ mv = 500, ref = 400 }))
  end)
end)

describe("Trigger.ForRealm", function()
  local GC
  local settings = { minimumProfitCopper = 50000, minimumRoi = 0.10 }

  before_each(function()
    GC = helper.loadModule("Core/Trigger.lua")
  end)

  it("is nil without a usable reference", function()
    assert.is_nil(GC.Trigger.ForRealm(nil, settings))
    assert.is_nil(GC.Trigger.ForRealm(0, settings))
    assert.is_nil(GC.Trigger.ForRealm(250000, nil))
  end)

  it("binds on the minimum discount when the profit formula is looser", function()
    -- For{ mv = 250000 } = 187500 (75% of the reference), but a region reference is not
    -- precise enough for a 25% discount to count -- 250000 x 0.75 = 187500 either way here,
    -- so take a reference where the two genuinely differ: at 1,000,000 the profit floor
    -- allows 900,000 (netExit 950,000 - 50,000) while the discount floor allows 750,000.
    assert.equal(750000, GC.Trigger.ForRealm(1000000, settings))
  end)

  it("binds on the profit formula when that is the stricter one", function()
    -- netExit = 95000; byProfit = 45000, byRoi = 86363 -> 45000, below the discount floor's
    -- 75000, so the stricter profit answer stands.
    assert.equal(45000, GC.Trigger.ForRealm(100000, settings))
  end)

  it("is nil when the profit formula leaves nothing positive", function()
    assert.is_nil(GC.Trigger.ForRealm(50000, settings))
  end)

  it("never allows less than the minimum discount", function()
    for _, reference in ipairs({ 100000, 250000, 1000000, 50000000 }) do
      local trigger = GC.Trigger.ForRealm(reference, settings)
      if trigger then
        assert.is_true(trigger <= reference * (1 - GC.Trigger.REALM_MIN_DISCOUNT))
      end
    end
  end)
end)

describe("Trigger.AnyArmed", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Trigger.lua")
  end)

  it("is false for an empty candidate list", function()
    assert.is_false(GC.Trigger.AnyArmed({}, function() return nil end, {}))
  end)

  it("is false when nothing in the list has a usable value", function()
    local values = { [2] = { mv = 100000 } } -- item 2 has mv but no stressUnit; item 1 has nothing
    local getValue = function(id) return values[id] end
    assert.is_false(GC.Trigger.AnyArmed({ 1, 2 }, getValue,
      { minimumProfitCopper = 50000, minimumRoi = 0.10 }))
  end)

  it("is true as soon as one candidate has a trigger", function()
    local values = { [1] = { mv = 100000 }, [2] = { mv = 250000, stressUnit = 200000 } }
    local getValue = function(id) return values[id] end
    assert.is_true(GC.Trigger.AnyArmed({ 1, 2 }, getValue,
      { minimumProfitCopper = 50000, minimumRoi = 0.10 }))
  end)
end)
