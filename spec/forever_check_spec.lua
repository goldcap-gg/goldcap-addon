local helper = require("spec.spec_helper")

describe("/gc forever self-check", function()
  local GC, printed, timers
  before_each(function()
    printed, timers = {}, {}
    GC = helper.loadModule("Core/Game.lua")
    helper.loadModule("Core/ForeverCheck.lua", GC)
    GC.Game.Passport = function() return { interface = 16001, build = "1.60.1.69977", regionId = 90 } end
  end)

  local function env(over)
    local e = {
      C_AuctionHouse = {
        ReplicateItems = function() end,
        GetNumReplicateItems = function() return 0 end,
      },
      AuctionHouseFrame = { IsShown = function() return true end },
      C_Timer = { After = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end },
      print = function(msg) printed[#printed + 1] = msg end,
    }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
  end

  it("reports the game, the data it has and the scan API", function()
    local lines = GC.ForeverCheck.Report(env())
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("WoW: Forever", 1, true))
    assert.truthy(text:find("1.60.1.69977", 1, true))
    assert.truthy(text:find("retail price snapshot: not loaded", 1, true))
    assert.truthy(text:find("ReplicateItems: present", 1, true))
  end)

  it("counts full-scan rows over time at an open auction house", function()
    local n = 0
    local e = env({ C_AuctionHouse = {
      ReplicateItems = function() n = 1234 end,
      GetNumReplicateItems = function() return n end,
    } })
    GC.ForeverCheck.Run(e)
    assert.equal(5, #timers)
    assert.same({ 2, 5, 10, 20, 40 }, { timers[1].s, timers[2].s, timers[3].s, timers[4].s, timers[5].s })
    timers[5].fn()
    assert.truthy(printed[#printed]:find("+40s: 1234 rows", 1, true))
  end)

  it("says so, and scans nothing, when the auction house is closed", function()
    local called = false
    GC.ForeverCheck.Run(env({
      AuctionHouseFrame = false, -- false, not nil: env() copies overrides with pairs(), which skips nil
      C_AuctionHouse = { ReplicateItems = function() called = true end, GetNumReplicateItems = function() return 0 end },
    }))
    assert.is_false(called)
    assert.truthy(printed[#printed]:find("open the auction house", 1, true))
  end)

  it("never throws when the scan API is missing or errors", function()
    assert.has_no.errors(function() GC.ForeverCheck.Run(env({ C_AuctionHouse = {} })) end)
    assert.truthy(printed[#printed]:find("ReplicateItems is missing", 1, true))
    assert.has_no.errors(function()
      GC.ForeverCheck.Run(env({ C_AuctionHouse = {
        ReplicateItems = function() error("boom") end,
        GetNumReplicateItems = function() return 0 end,
      } }))
    end)
    assert.truthy(table.concat(printed, "\n"):find("ReplicateItems failed", 1, true))
  end)

  -- Final review M1: ReplicateItems does a full server-side auction-house dump. On retail that
  -- is exactly the scan GoldCap avoids doing itself, so /gc forever must never trigger one there
  -- -- it is a WoW: Forever diagnostic, not a general-purpose scan trigger.
  it("does not scan on retail, and says the test is Forever-only", function()
    GC.Game.Passport = function() return { interface = 120100, build = "12.1.0.69933", regionId = 3 } end
    local called = false
    GC.ForeverCheck.Run(env({
      C_AuctionHouse = { ReplicateItems = function() called = true end, GetNumReplicateItems = function() return 0 end },
    }))
    assert.is_false(called)
    assert.truthy(printed[#printed]:find("the full-scan test runs only in WoW: Forever", 1, true))
  end)
end)
