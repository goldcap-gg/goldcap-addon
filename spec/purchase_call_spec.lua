local helper = require("spec.spec_helper")

-- Core/PurchaseCall.lua: the one place a purchase click makes its protected call. The click's
-- plan runs first (through securecallfunction), then the call it answered, synchronously, in
-- the same click, then what the plan left to run after it. spec/forever_taint_flow_spec.lua runs
-- the real Deals and BUY clicks through it on a model of the client's taint rules; this pins the
-- order and the arguments, which are what retail sees.
describe("GC.PurchaseCall.Click", function()
  local GC, seen

  before_each(function()
    seen = {}
    local function record(name)
      return function(...) seen[#seen + 1] = { name, ... } end
    end
    _G.C_AuctionHouse = {
      StartCommoditiesPurchase = record("StartCommoditiesPurchase"),
      ConfirmCommoditiesPurchase = record("ConfirmCommoditiesPurchase"),
      PlaceBid = record("PlaceBid"),
    }
    GC = helper.loadModule("Core/PurchaseCall.lua", {})
  end)

  after_each(function()
    _G.C_AuctionHouse, _G.issecure = nil, nil
  end)

  local function plan(call, first, second)
    return function(...)
      seen[#seen + 1] = { "plan", ... }
      return call, first, second, function() seen[#seen + 1] = { "after" } end
    end
  end

  it("makes the call the plan answers, with its arguments, between the plan and its bookkeeping", function()
    GC.PurchaseCall.Click(plan("start", 42, 6), "button")
    GC.PurchaseCall.Click(plan("confirm", 42, 6))
    GC.PurchaseCall.Click(plan("bid", 8801, 750000))
    assert.same({
      { "plan", "button" }, { "StartCommoditiesPurchase", 42, 6 }, { "after" },
      { "plan" }, { "ConfirmCommoditiesPurchase", 42, 6 }, { "after" },
      { "plan" }, { "PlaceBid", 8801, 750000 }, { "after" },
    }, seen)
  end)

  it("makes no call, and runs nothing after, for a plan that answers none", function()
    GC.PurchaseCall.Click(function() seen[#seen + 1] = { "plan" } end)
    GC.PurchaseCall.Click(plan("cancel", 42, 6))
    assert.same({ { "plan" }, { "plan" } }, seen)
    assert.is_nil(GC.PurchaseCall.last)
  end)

  it("runs its plan through securecallfunction", function()
    local through = 0
    local real = _G.securecallfunction
    _G.securecallfunction = function(fn, ...)
      through = through + 1
      return fn(...)
    end
    GC.PurchaseCall.Click(plan("start", 42, 6))
    _G.securecallfunction = real
    assert.equal(2, through) -- the plan, and what it left to run after the call
  end)

  it("remembers whether the last purchase click began and called secure, for /gc taint", function()
    local answers = { true, false }
    _G.issecure = function() return table.remove(answers, 1) end
    GC.PurchaseCall.Click(plan("start", 42, 6))
    assert.same({ call = "start", enteredSecure = true, calledSecure = false }, GC.PurchaseCall.last)
  end)
end)
