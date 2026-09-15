local helper = require("spec.spec_helper")

describe("GC.PurchaseSlot: one commodity purchase in flight, two owners", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("Core/PurchaseSlot.lua", GC)
  end)

  after_each(function() _G.GetTime = nil end)

  it("one owner at a time; a stale claim can be taken over", function()
    assert.is_true(GC.PurchaseSlot.Claim("buy", 100))
    assert.is_false(GC.PurchaseSlot.Claim("sniper", 101))
    assert.equal("buy", GC.PurchaseSlot.Owner())
    GC.PurchaseSlot.Release("sniper")            -- not yours: no-op
    assert.equal("buy", GC.PurchaseSlot.Owner())
    GC.PurchaseSlot.Release("buy")
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.is_true(GC.PurchaseSlot.Claim("buy", 200))
    assert.is_true(GC.PurchaseSlot.Claim("sniper", 231))   -- 31s later: stale, taken over
  end)

  it("the same owner re-claiming refreshes the timestamp instead of being refused", function()
    assert.is_true(GC.PurchaseSlot.Claim("sniper", 100))
    assert.is_true(GC.PurchaseSlot.Claim("sniper", 125))   -- refreshes claimedAt to 125
    -- Only 25s since the refreshed claim -- still live. Had the refresh not happened, the
    -- original claim at 100 would already be 50s stale and takeable.
    assert.is_false(GC.PurchaseSlot.Claim("buy", 150))
    assert.equal("sniper", GC.PurchaseSlot.Owner())
  end)

  it("IsBusy is false once the slot is released", function()
    assert.is_true(GC.PurchaseSlot.Claim("sniper", 100))
    assert.is_true(GC.PurchaseSlot.IsBusy(105))
    GC.PurchaseSlot.Release("sniper")
    assert.is_false(GC.PurchaseSlot.IsBusy(105))
  end)

  it("IsBusy respects the same staleness bound as Claim", function()
    assert.is_true(GC.PurchaseSlot.Claim("buy", 100))
    assert.is_true(GC.PurchaseSlot.IsBusy(130))
    assert.is_false(GC.PurchaseSlot.IsBusy(131))
  end)

  it("defaults `now` to GetTime when omitted", function()
    _G.GetTime = function() return 500 end
    assert.is_true(GC.PurchaseSlot.Claim("sniper"))
    assert.equal("sniper", GC.PurchaseSlot.Owner())
    assert.is_true(GC.PurchaseSlot.IsBusy())
  end)
end)
