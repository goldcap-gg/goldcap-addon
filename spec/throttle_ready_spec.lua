local helper = require("spec.spec_helper")

describe("GC.Util.ThrottleReady: the ready flag, with an expiry", function()
  local GC, flag, clock

  before_each(function()
    GC = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    helper.loadModule("Core/Util.lua", GC)
    flag, clock = true, 100
    _G.GetTime = function() return clock end
    _G.C_AuctionHouse = { IsThrottledMessageSystemReady = function() return flag end }
  end)

  after_each(function() _G.GetTime, _G.C_AuctionHouse = nil, nil end)

  it("is the flag itself while the flag is true", function()
    assert.is_true(GC.Util.ThrottleReady())
    assert.equal(0, GC.Util.throttleStats.forced)
  end)

  it("honours a false flag for the ordinary beat after a query", function()
    flag = false
    assert.is_false(GC.Util.ThrottleReady())
    clock = 104
    assert.is_false(GC.Util.ThrottleReady())
  end)

  -- Live client, 2026-09-14: false for minutes, Blizzard's own search working, no ready event.
  it("permits a send once the flag has been false for the whole window", function()
    flag = false
    assert.is_false(GC.Util.ThrottleReady())
    clock = 105
    assert.is_true(GC.Util.ThrottleReady())
  end)

  -- Asking used to spend the permit, and every consumer in this addon asks more than once
  -- before it sends: the Sniper's ticker asked, then the pre-warm it called asked again 0
  -- seconds into the window the first read had just restarted, and was told no. Nothing the
  -- ticker drove ever sent anything.
  it("is a pure read -- asking it, however often, spends nothing", function()
    flag = false
    GC.Util.ThrottleReady()
    clock = 105
    for _ = 1, 10 do assert.is_true(GC.Util.ThrottleReady()) end
    assert.equal(0, GC.Util.throttleStats.forced)
    assert.is_true(GC.Util.ClaimThrottleSend("sniper"))
    assert.equal(1, GC.Util.throttleStats.forced)
  end)

  it("paces one consumer at one forced send per window", function()
    flag = false
    GC.Util.ThrottleReady()
    clock = 105
    assert.is_true(GC.Util.ClaimThrottleSend("sniper"))
    clock = 106
    assert.is_false(GC.Util.ClaimThrottleSend("sniper")) -- its turn is spent
    clock = 110
    assert.is_true(GC.Util.ClaimThrottleSend("sniper"))
  end)

  -- The permit was global, and the Sniper's arbiter runs immediately before the Sell tab's
  -- pricing walk on every ready event -- so the Sniper took every window and the Sell tab sat
  -- at "PRICING… 0/20" through a hundred ready events without one of them being its.
  it("gives each consumer its own turn, spaced apart", function()
    flag = false
    GC.Util.ThrottleReady()
    clock = 105
    assert.is_true(GC.Util.ClaimThrottleSend("sniper"))
    assert.is_false(GC.Util.ClaimThrottleSend("sell")) -- not in the same instant
    clock = 106.5
    assert.is_true(GC.Util.ClaimThrottleSend("sell"))  -- but its own turn is not the sniper's
    assert.equal(2, GC.Util.throttleStats.forced)
  end)

  it("claims nothing under a flag that is merely taking its usual beat", function()
    flag = false
    clock = 102
    assert.is_false(GC.Util.ClaimThrottleSend("sniper"))
    assert.equal(0, GC.Util.throttleStats.forced)
  end)

  it("is the flag, and paces nothing, while the flag is true", function()
    for _ = 1, 5 do
      assert.is_true(GC.Util.ClaimThrottleSend("sniper"))
      assert.is_true(GC.Util.ClaimThrottleSend("sell"))
    end
    assert.equal(0, GC.Util.throttleStats.forced)
  end)

  it("a true flag or a ready event clears the clock", function()
    flag = false
    GC.Util.ThrottleReady()
    clock = 103
    GC.Util.NoteThrottleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    clock = 106 -- only 3s since the event: the flag is trusted again
    assert.is_false(GC.Util.ThrottleReady())
    flag = true
    assert.is_true(GC.Util.ThrottleReady())
    flag = false
    clock = 108
    assert.is_false(GC.Util.ThrottleReady())
  end)
end)
