local helper = require("spec.spec_helper")

describe("/gc forever self-check", function()
  local GC, printed, timers, clock, store, listener, rows, replicateCalls

  before_each(function()
    printed, timers, clock, store, rows, replicateCalls = {}, {}, 0, {}, {}, 0
    listener = nil
    GC = helper.loadModule("Core/Game.lua")
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/ForeverCheck.lua", GC)
    GC.Game.Passport = function() return { interface = 16001, build = "1.60.1.70009", regionId = 90 } end
    -- GC.Util.CoinText tries this global first; stub it distinctly from the raw copper so a
    -- line's CoinText part and its "(Nc)" part are both provably present.
    _G.GetCoinTextureString = function(c) return "$" .. tostring(c) end
  end)

  after_each(function() _G.GetCoinTextureString = nil end)

  -- rows: array of { itemID, count, buyout, hasAllInfo }; GetReplicateItemInfo is 0-based.
  local function ahApi(over)
    local api = {
      ReplicateItems = function() replicateCalls = replicateCalls + 1 end,
      GetNumReplicateItems = function() return #rows end,
      GetReplicateItemInfo = function(i)
        local r = rows[i + 1]
        if not r then return nil end
        return "name", 1, r[2], 1, true, 1, 0, 0, 0, r[3], 0, false, nil, "Seller", "Seller", 0, r[1], r[4]
      end,
      CalculateCommodityDeposit = function() return 12 end,
      SupportsCopperValues = function() return true end,
    }
    for k, v in pairs(over or {}) do api[k] = v end
    return api
  end

  local function env(over)
    local e = {
      C_AuctionHouse = ahApi(),
      AuctionHouseFrame = { IsShown = function() return true end },
      C_Timer = { After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end },
      CreateFrame = function()
        listener = { events = {} }
        function listener:RegisterEvent(name) self.events[name] = true end
        function listener:UnregisterEvent(name) self.events[name] = nil end
        function listener:SetScript(_, fn) self.onEvent = fn end
        return listener
      end,
      now = function() return 1000000 + math.floor(clock) end,
      clock = function() return clock end,
      realm = function() return "Forever-Normal" end,
      faction = function() return "Horde" end,
      portal = function() return "test" end,
      store = function() return store end,
      commodities = function() return { [2589] = true, [2592] = true } end,
      book = function() return { [2589] = { floor = 67, qty = 4060 }, [3000] = { floor = 500, qty = 2 } } end,
      lastPass = function() return { kind = "classes", items = 2, pages = 1 } end,
      print = function(msg) printed[#printed + 1] = msg end,
    }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
  end

  local function runTimers()
    local guard = 0
    while #timers > 0 do
      guard = guard + 1
      assert(guard < 1000, "runaway timers")
      table.sort(timers, function(a, b) return a.at < b.at end)
      local t = table.remove(timers, 1)
      clock = t.at
      t.fn()
    end
  end

  local function said(fragment)
    for _, line in ipairs(printed) do
      if line:find(fragment, 1, true) then return line end
    end
    return nil
  end

  it("reports the game, the data it has, the scan API, realm, faction, portal and deposit", function()
    local text = table.concat(GC.ForeverCheck.Report(env()), "\n")
    assert.truthy(text:find("WoW: Forever", 1, true))
    assert.truthy(text:find("1.60.1.70009", 1, true))
    assert.truthy(text:find("retail price snapshot: not loaded", 1, true))
    assert.truthy(text:find("ReplicateItems: present", 1, true))
    assert.truthy(text:find("realm Forever-Normal", 1, true))
    assert.truthy(text:find("faction Horde", 1, true))
    assert.truthy(text:find("portal test", 1, true))
    assert.truthy(text:find("deposit for 1 Linen Cloth (duration 1): $12 (12c)", 1, true))
    assert.truthy(text:find("copper prices: true", 1, true))
  end)

  it("says the deposit is unavailable when the client refuses it", function()
    local e = env({ C_AuctionHouse = ahApi({ CalculateCommodityDeposit = function() error("closed") end }) })
    local text = table.concat(GC.ForeverCheck.Report(e), "\n")
    assert.truthy(text:find("deposit for 1 Linen Cloth (duration 1): unavailable", 1, true))
  end)

  it("reads the whole dump at the first event, before any poll", function()
    rows = { { 2589, 20, 1340, true }, { 2589, 5, 350, false }, { 2592, 1, 0, true }, { 4000, 1, 90000, true } }
    GC.ForeverCheck.Run(env())
    assert.equal(1, replicateCalls)
    assert.is_true(listener.events.REPLICATE_ITEM_LIST_UPDATE)
    clock = 1.7
    listener.onEvent(listener, "REPLICATE_ITEM_LIST_UPDATE")
    local line = said("dump read at +1.7s (event)")
    assert.truthy(line)
    assert.truthy(line:find("4 rows, 3 with a buyout, 1 bid-only, 1 missing item data", 1, true))
    assert.truthy(line:find("3 distinct items", 1, true))
    assert.truthy(line:find("3 rows of 2 known commodities", 1, true))
    assert.truthy(line:find("Linen Cloth: 2 rows / 25 units / cheapest $67 (67c)", 1, true))
    assert.truthy(said("first row: "))
  end)

  it("reads at the first non-zero poll, records when rows vanish, and says the timeline", function()
    GC.ForeverCheck.Run(env({ C_Timer = { After = function(s, fn)
      timers[#timers + 1] = { at = clock + s, fn = function()
        -- The beta's shape: rows appear by +2 s and are gone by +10 s.
        if clock >= 2 and clock < 10 then
          if #rows == 0 then for i = 1, 1024 do rows[i] = { 2589, 1, 67, true } end end
        elseif clock >= 10 then
          rows = {}
        end
        fn()
      end }
    end } }))
    runTimers()
    assert.truthy(said("dump read at +2.0s (poll): 1024 rows"))
    local timeline = said("timeline:")
    assert.truthy(timeline:find("first rows at +2.0s (1024)", 1, true))
    assert.truthy(timeline:find("gone at +10.0s", 1, true))
    assert.truthy(timeline:find("events 0", 1, true))
    assert.is_nil(listener.events.REPLICATE_ITEM_LIST_UPDATE)
  end)

  it("stamps the request and never requests again inside fifteen minutes", function()
    GC.ForeverCheck.Run(env())
    assert.equal(1000000, store.requestedAt)
    runTimers()
    clock = 300
    GC.ForeverCheck.Run(env())
    assert.equal(1, replicateCalls)
    assert.truthy(said("skipped"))
  end)

  it("compares against the browse book this visit", function()
    GC.ForeverCheck.Run(env())
    assert.truthy(said("browse book this visit: 2 items (last pass: classes, 2 results, 1 pages)"))
  end)

  it("says so, and scans nothing, when the auction house is closed", function()
    GC.ForeverCheck.Run(env({ AuctionHouseFrame = false }))
    assert.equal(0, replicateCalls)
    assert.truthy(printed[#printed]:find("open the auction house", 1, true))
  end)

  it("never throws when the scan API is missing or errors", function()
    assert.has_no.errors(function() GC.ForeverCheck.Run(env({ C_AuctionHouse = {} })) end)
    assert.truthy(said("ReplicateItems is missing"))
    assert.has_no.errors(function()
      GC.ForeverCheck.Run(env({ C_AuctionHouse = ahApi({ ReplicateItems = function() error("boom") end }) }))
    end)
    assert.truthy(said("ReplicateItems failed"))
  end)

  it("runs no full scan on retail", function()
    GC.Game.Passport = function() return { interface = 120100, build = "12.1.0.1", regionId = 3 } end
    GC.ForeverCheck.Run(env())
    assert.equal(0, replicateCalls)
    assert.is_nil(store.requestedAt)
    assert.truthy(said("runs only in WoW: Forever"))
  end)
end)
