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
