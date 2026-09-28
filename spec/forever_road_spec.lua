local helper = require("spec.spec_helper")

describe("ForeverRoad", function()
  local GC, R, db, printed, saved

  local function init(interface)
    GC.ForeverScan.Init(db, { passport = function() return { interface = interface, region = 90, realm = "Forever" } end })
  end

  before_each(function()
    saved = {}
    for _, k in ipairs({ "GetMoney", "UnitGUID", "UnitLevel", "UnitXP", "UnitXPMax", "GetCoinTextureString",
        "ChatFrame_OpenChat", "C_Timer" }) do saved[k] = _G[k] end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.GetMoney = function() return 10000 end
    _G.UnitGUID = function() return "Player-1-0000ABCD" end
    _G.UnitLevel = function() return 20 end
    _G.UnitXP = function() return 500 end
    _G.UnitXPMax = function() return 1000 end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    helper.loadModule("Core/ForeverRoad.lua", GC)
    R = GC.ForeverRoad
    GC.ForeverValue = { RealBagTotals = function() return { best = 5000, gain = 0, gainItems = 0 } end }
    printed = {}
    GC.Print = function(m) printed[#printed + 1] = m end
    db = {}
  end)

  after_each(function() for k, v in pairs(saved) do _G[k] = v end end)

  it("reads money the way players type it", function()
    assert.equal(125000, R.ParseMoney("12g 50s"))
    assert.equal(125000, R.ParseMoney(" 12G50S "))
    assert.equal(900000, R.ParseMoney("90"))
    assert.equal(5000, R.ParseMoney("0.5"))
    assert.equal(320, R.ParseMoney("3s 20c"))
    for _, bad in ipairs({ "", "abc", "12g 5g", "0", "-5g", "12x" }) do assert.is_nil(R.ParseMoney(bad), bad) end
    assert.is_nil(R.ParseMoney(nil))
  end)

  it("writes money for a chat line with no coin icons", function()
    assert.equal("12g 50s", R.Plain(125000))
    assert.equal("90g", R.Plain(900000))
    assert.equal("3s 20c", R.Plain(320))
    assert.equal("50s", R.Plain(5000))
    assert.equal("7c", R.Plain(7))
  end)

  it("counts only time logged in, and measures the pace over the samples it kept", function()
    local c = { played = 0, samples = {} }
    for k = 0, 30 do R.Tick(c, 1000 + 60 * k, 100 * k, 10 + 0.005 * k) end
    assert.equal(1800, c.played)
    assert.equal(7, #c.samples)                         -- one every SAMPLE_SECONDS of play
    local money, levels = R.Rate(c)
    assert.equal(6000, money)
    assert.is_true(math.abs(levels - 0.3) < 1e-6)
    R.Tick(c, 1000 + 1800 + 4000, 3000, 10.15)          -- a silence past GAP_SECONDS: time away, not play
    assert.equal(1800, c.played)
    R.End(c, 7000, 3000, 10.15)
    assert.is_nil(c.last)
    R.Tick(c, 7100, 3000, 10.15)                        -- the first tick of a new session counts nothing
    assert.equal(1800, c.played)
  end)

  it("has no pace before MIN_RATE_SECONDS of play, and measures from inside the window only", function()
    local c = { played = 0, samples = {} }
    for k = 0, 10 do R.Tick(c, 1000 + 60 * k, 100 * k, 10) end   -- ten minutes
    assert.is_nil(R.Rate(c))
    c = { played = 20000, samples = { "0:0:5.000", "15000:100:9.000" }, money = 400, progress = 10 }
    local money = R.Rate(c)                                        -- from 15000 (5000 s ago), not from 0
    assert.equal(216, math.floor(money))
  end)

  it("forecasts from gold, bags, the cost and the pace", function()
    local base = { money = 10000, bags = 5000, cost = 1000000, level = 20, progress = 20.5,
      moneyRate = 100000, levelRate = 1 }
    local function f(over)
      local s = {}
      for k, v in pairs(base) do s[k] = v end
      for k, v in pairs(over or {}) do s[k] = v end
      return R.Forecast(s)
    end
    assert.same({ kind = "level", level = 30 }, f())                 -- 985000 / 100000 = 9.85 h; 20.5 + 9.85
    assert.same({ kind = "short", short = 10000 }, f({ moneyRate = 50000 }))
    assert.same({ kind = "nocost" }, f({ cost = false }))
    assert.same({ kind = "ready" }, f({ cost = 15000 }))
    assert.same({ kind = "norate" }, f({ moneyRate = false }))
    assert.same({ kind = "flat" }, f({ moneyRate = 0 }))
    assert.same({ kind = "past" }, f({ level = 40, progress = 40.2 })) -- the level cap itself: still "past"
    -- A stalled level (no XP progress, gold still growing) is not a dead end: the existing math
    -- already lands on the current level once a non-positive rate stops mapping to "past" -- and
    -- a negative rate (should the client ever report one) clamps to the same answer.
    assert.same({ kind = "level", level = 20 }, f({ levelRate = 0 }))
    assert.same({ kind = "level", level = 20 }, f({ levelRate = -1 }))
  end)

  it("says it in lines: the totals, then the forecast, then what the AH adds", function()
    local s = { money = 10000, bags = 5000, cost = 1000000, level = 20, progress = 20.5, moneyRate = 100000,
      levelRate = 1, gain = 700, gainItems = 3 }
    assert.same({
      "Road to 40: 15000c of 1000000c (gold 10000c, bags 5000c).",
      "At your pace you reach it at level 30.",
      "Items in your bags that fetch more on the auction house than at a vendor: 3 (700c more).",
    }, R.Lines(s))
    s.cost = nil
    local lines = R.Lines(s)
    assert.equal("Road to 40: you have 15000c (gold 10000c, bags 5000c).", lines[1])
    assert.equal("Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect.", lines[2])
  end)

  -- V1: a level that has stopped moving must not go silent just because it cannot forecast a
  -- FUTURE level -- the honest answer is "at your current level", the same sentence a moving
  -- rate already gives.
  it("says the current level when the level has stalled but gold keeps growing", function()
    local s = { money = 10000, bags = 5000, cost = 1000000, level = 20, progress = 20.5,
      moneyRate = 100000, levelRate = 0 }
    assert.equal("At your pace you reach it at level 20.", R.Lines(s)[2])
    s.levelRate = -1
    assert.equal("At your pace you reach it at level 20.", R.Lines(s)[2])
  end)

  -- V1: level 40 reached but the mount still not paid for is the one state a Forever character
  -- eventually settles into permanently, and it used to leave the second line unset entirely.
  it("says how much is still missing once level 40 is reached without the gold", function()
    local s = { money = 10000, bags = 5000, cost = 1000000, level = 40, progress = 40.2 }
    assert.equal("Level 40 reached: 985000c to go.", R.Lines(s)[2])
  end)

  it("shares a plain line, and nothing without a cost", function()
    local s = { money = 10000, bags = 5000, cost = 1000000, level = 20, progress = 20.5, moneyRate = 100000, levelRate = 1 }
    assert.equal("Road to 40 with GoldCap: 1g 50s of 100g for my mount (1%). At your pace you reach it at level 30.",
      R.ShareText(s))
    s.cost = nil
    assert.is_nil(R.ShareText(s))
  end)

  -- V1: ShareText's own "level" branch was already right -- it just never ran for a stalled
  -- level, because Forecast used to call that "past" instead.
  it("shares the current level once the level has stalled, same as a moving one", function()
    local s = { money = 10000, bags = 5000, cost = 1000000, level = 20, progress = 20.5,
      moneyRate = 100000, levelRate = 0 }
    assert.equal("Road to 40 with GoldCap: 1g 50s of 100g for my mount (1%). At your pace you reach it at level 20.",
      R.ShareText(s))
  end)

  it("sets, refuses, shares and clears the cost with /gc mount, and prints the lines", function()
    init(16001)
    R.Slash("12g 50s")
    assert.equal(125000, db.forever.mountCost)
    assert.equal("Mount cost set to 125000c.", printed[1])
    assert.equal("Road to 40: 15000c of 125000c (gold 10000c, bags 5000c).", printed[2])
    assert.equal("Play a little longer for an estimate of your pace.", printed[3])
    R.Slash("nonsense")
    assert.equal("Could not read that amount. Type it like 12g 50s.", printed[#printed])
    assert.equal(125000, db.forever.mountCost)
    local opened
    _G.ChatFrame_OpenChat = function(text) opened = text end
    R.Slash("share")
    assert.equal("Road to 40 with GoldCap: 1g 50s of 12g 50s for my mount (12%).", opened)
    R.Slash("clear")
    assert.is_nil(db.forever.mountCost)
    assert.equal("Mount cost cleared.", printed[#printed])
  end)

  it("keeps each character's clock under its GUID; a ticker's own argument is not a time", function()
    init(16001)
    R.OnTick({ ticker = true })
    local c = db.forever.road["Player-1-0000ABCD"]
    assert.is_number(c.last)
    assert.equal(1, #c.samples)
    assert.equal(10000, c.money)
    assert.equal(20.5, c.progress)
  end)

  it("starts one ticker on entering the world, and ends the session on logout", function()
    init(16001)
    local tickers = 0
    _G.C_Timer = { NewTicker = function(_, fn) tickers = tickers + 1; return { fn = fn } end }
    R.OnEnteringWorld()
    R.OnEnteringWorld()                                   -- every loading screen: still one ticker
    assert.equal(1, tickers)
    R.OnLogout()
    assert.is_nil(db.forever.road["Player-1-0000ABCD"].last)
  end)

  -- The Sold tab UX fix (owner, Forever beta 2026-09-28): three short single-line strings, never
  -- Lines()'s own word-wrapped chat sentences -- SoldLines composes its own text now instead of
  -- concatenating lines[1]/lines[2] into one long line.
  it("gives the Sold tab three compact lines: totals, forecast, then what the AH adds", function()
    init(16001)
    db.forever = { mountCost = 125000 }
    GC.ForeverValue.RealBagTotals = function() return { best = 5000, gain = 700, gainItems = 3 } end
    assert.same({
      "15000c of 125000c — gold 10000c, bags 5000c",
      "Play a little longer for an estimate of your pace.",
      "3 bag items sell for more on the AH (+700c)",
    }, R.SoldLines())
  end)

  it("nudges toward setting the riding cost, compactly, when none is set yet", function()
    init(16001)
    assert.same({
      "You have 15000c — gold 10000c, bags 5000c",
      "Set the riding cost: /gc mount 90g",
    }, R.SoldLines())
  end)

  -- V1: the Sold tab reads Lines() through this same function, so the level-40-without-the-gold
  -- line has to show up here too, not only from a direct R.Lines() call.
  it("gives the Sold tab the level-40-reached line too", function()
    init(16001)
    db.forever = { mountCost = 1000000 }
    _G.UnitLevel = function() return 40 end
    _G.UnitXP = function() return 200 end
    _G.UnitXPMax = function() return 1000 end
    assert.same({
      "15000c of 1000000c — gold 10000c, bags 5000c",
      "Level 40 reached: 985000c to go.",
    }, R.SoldLines())
  end)

  it("does nothing on retail: no key, no line, no tick", function()
    init(120100)
    _G.C_Timer = { NewTicker = function() error("a ticker on retail") end }
    R.OnTick(); R.OnMoney(); R.OnEnteringWorld(); R.OnLogout(); R.Slash("12g")
    assert.is_nil(R.Snapshot())
    assert.is_nil(R.SoldLines())
    assert.is_nil(db.forever)
    assert.same({}, printed)
  end)
end)
