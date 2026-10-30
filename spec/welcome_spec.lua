local helper = require("spec.spec_helper")

describe("Welcome", function()
  local GC, W, C
  local NOW = 1800000000
  local HOUR, DAY = 3600, 86400

  before_each(function()
    GC = helper.loadModule("Core/Welcome.lua")
    W = GC.Welcome
    C = W.C
  end)

  describe("Prices on retail", function()
    local function retail(fields)
      fields.now = NOW
      return W.Prices(fields)
    end

    it("says the Companion's prices are fresh for a day", function()
      local s = retail({ origin = "app", importedTs = NOW - 3 * HOUR })
      assert.same({ kind = "app", tone = "good", age = 3 * HOUR }, s)
    end)

    it("says the Companion has stopped once its prices are a day old", function()
      local s = retail({ origin = "app", importedTs = NOW - C.STALE_SECONDS })
      assert.same({ kind = "app_stale", tone = "bad", age = C.STALE_SECONDS, cta = "run" }, s)
    end)

    it("asks for the Companion over a fresh paste, and warns once the paste is a day old", function()
      assert.same({ kind = "manual", tone = "warn", age = 2 * HOUR, cta = "install" },
        retail({ origin = "manual", importedTs = NOW - 2 * HOUR }))
      assert.same({ kind = "manual_stale", tone = "bad", age = 2 * DAY, cta = "install" },
        retail({ origin = "manual", importedTs = NOW - 2 * DAY }))
    end)

    it("calls the shipped snapshot bad, aged from the day it was built", function()
      local s = retail({ origin = "none", bundledTs = NOW - 12 * DAY })
      assert.same({ kind = "bundled", tone = "bad", age = 12 * DAY, cta = "install" }, s)
    end)

    it("gives a snapshot with no date no age (a local build's empty region carries ts 0)", function()
      assert.is_nil(retail({ origin = "none", bundledTs = 0 }).age)
      assert.is_nil(retail({ origin = "none" }).age)
    end)

    it("puts a Companion write the addon could not read ahead of everything, with its reason", function()
      local s = retail({ origin = "app", importedTs = NOW - HOUR, appError = { reason = "version" } })
      assert.same({ kind = "error", tone = "bad", cta = "update", reason = "version" }, s)
    end)

    it("never reports an age below zero when the clock is behind the data", function()
      assert.equal(0, retail({ origin = "app", importedTs = NOW + 600 }).age)
    end)
  end)

  describe("Prices on WoW: Forever", function()
    local function forever(fields)
      fields.now, fields.forever = NOW, true
      return W.Prices(fields)
    end

    it("is good while the Companion's payload for this auction house is under a day old", function()
      assert.same({ kind = "crowd", tone = "good", age = 40 * 60 }, forever({ crowdTs = NOW - 40 * 60 }))
    end)

    -- The payload is as old as the newest scan anyone shared here; the Companion's own stamp says
    -- whether it still runs. 16.10: a running Companion, a quiet house and "check that GoldCap
    -- Companion is running".
    it("asks nothing of a player whose Companion runs while nobody scans this auction house", function()
      assert.same({ kind = "crowd_quiet", tone = "warn", age = 41 * HOUR },
        forever({ crowdTs = NOW - 41 * HOUR, companion = true, writtenAt = NOW - 5 * 60 }))
      assert.same({ kind = "crowd_quiet", tone = "warn" },
        forever({ companion = true, writtenAt = NOW - 5 * 60 }))
    end)

    it("asks to start the Companion once its own stamp is a day old, aged from that stamp", function()
      assert.same({ kind = "crowd_stale", tone = "warn", age = 2 * DAY, cta = "run" },
        forever({ crowdTs = NOW - 3 * DAY, companion = true, writtenAt = NOW - 2 * DAY }))
      assert.same({ kind = "crowd_stale", tone = "warn", age = C.STALE_SECONDS, cta = "run" },
        forever({ companion = true, writtenAt = NOW - C.STALE_SECONDS }))
    end)

    it("goes by the payload's age when the file carries no stamp", function()
      assert.same({ kind = "crowd_stale", tone = "warn", age = 3 * DAY, cta = "run" },
        forever({ crowdTs = NOW - 3 * DAY, companion = true }))
      assert.same({ kind = "crowd_missing", tone = "warn", cta = "run" }, forever({ companion = true }))
    end)

    it("asks for the Companion when it has never written here", function()
      assert.same({ kind = "own", tone = "warn", cta = "install" }, forever({}))
    end)

    it("ignores retail's import there: WoW: Forever never takes one", function()
      assert.equal("own", forever({ origin = "app", importedTs = NOW }).kind)
    end)
  end)

  describe("OnLoad", function()
    it("marks a save created just now as a new player's", function()
      local db = {}
      W.OnLoad(db, true)
      assert.same({ firstRun = true }, db.welcome)
    end)

    it("gives a save that existed before an empty record", function()
      local db = { settings = {} }
      W.OnLoad(db, false)
      assert.same({}, db.welcome)
    end)

    it("leaves a record already there alone", function()
      local db = { welcome = { seen = true, nextAt = 5 } }
      W.OnLoad(db, true)
      assert.same({ seen = true, nextAt = 5 }, db.welcome)
    end)
  end)

  describe("Decide", function()
    local bad = { tone = "bad", cta = "run" }
    local warn = { tone = "warn", cta = "install" }
    local good = { tone = "good" }

    it("opens the whole welcome on a new player's first visit, whatever the prices", function()
      assert.equal("welcome", W.Decide({ firstRun = true }, good, NOW))
      assert.equal("welcome", W.Decide({ firstRun = true }, bad, NOW))
    end)

    it("opens only the prices part for a player who had GoldCap before, and only when needed", function()
      assert.equal("prices", W.Decide({}, bad, NOW))
      assert.equal("prices", W.Decide({}, warn, NOW))
      assert.is_nil(W.Decide({}, good, NOW))
    end)

    it("comes back once its interval is over, and not before", function()
      local w = { seen = true, nextAt = NOW + 1 }
      assert.is_nil(W.Decide(w, bad, NOW))
      assert.equal("prices", W.Decide(w, bad, NOW + 1))
    end)

    it("never comes back by itself for good prices or after Don't remind me", function()
      assert.is_nil(W.Decide({ seen = true, nextAt = 0 }, good, NOW))
      assert.is_nil(W.Decide({ seen = true, nextAt = 0, quiet = true }, bad, NOW))
    end)

    it("never opens by itself to say something the player can do nothing about", function()
      local quietHouse = { kind = "crowd_quiet", tone = "warn" }
      assert.is_nil(W.Decide({}, quietHouse, NOW))
      assert.is_nil(W.Decide({ seen = true, nextAt = 0 }, quietHouse, NOW))
      assert.equal("welcome", W.Decide({ firstRun = true }, quietHouse, NOW))
    end)

    it("answers nil for a missing record or status rather than erroring", function()
      assert.is_nil(W.Decide(nil, bad, NOW))
      assert.is_nil(W.Decide({}, nil, NOW))
    end)
  end)

  describe("SayAtLogin", function()
    it("speaks at every login while the window would ask the player to do something", function()
      assert.is_true(W.SayAtLogin({ seen = true, nextAt = NOW + 86400 }, { tone = "warn", cta = "install" }))
      assert.is_true(W.SayAtLogin({}, { tone = "bad", cta = "run" }))
      assert.is_true(W.SayAtLogin(nil, { tone = "bad", cta = "update" }))
    end)

    it("stays quiet with nothing to ask, and after Don't remind me", function()
      assert.is_false(W.SayAtLogin({}, { kind = "app", tone = "good" }))
      assert.is_false(W.SayAtLogin({}, { kind = "crowd_quiet", tone = "warn" }))
      assert.is_false(W.SayAtLogin({ quiet = true }, { tone = "bad", cta = "install" }))
      assert.is_false(W.SayAtLogin({}, nil))
    end)
  end)

  describe("marks", function()
    it("waits three days after showing bad prices and a week after warn", function()
      local w = { firstRun = true }
      W.MarkShown(w, { tone = "bad" }, NOW)
      assert.same({ seen = true, nextAt = NOW + C.REMIND_BAD_SECONDS }, w)
      assert.equal(3 * DAY, C.REMIND_BAD_SECONDS)
      W.MarkShown(w, { tone = "warn" }, NOW)
      assert.equal(NOW + C.REMIND_WARN_SECONDS, w.nextAt)
      assert.equal(7 * DAY, C.REMIND_WARN_SECONDS)
    end)

    it("leaves a running reminder clock alone when the player opens it", function()
      local w = { firstRun = true, nextAt = 42 }
      W.MarkOpened(w, { tone = "bad" }, NOW)
      assert.same({ seen = true, nextAt = 42 }, w)
    end)

    it("starts the clock when the player opens it first, so arriving at the auction house does not repeat it", function()
      local w = { firstRun = true }
      W.MarkOpened(w, { tone = "bad" }, NOW)
      assert.same({ seen = true, nextAt = NOW + C.REMIND_BAD_SECONDS }, w)
      assert.is_nil(W.Decide(w, { tone = "bad" }, NOW + 60))
    end)

    it("goes quiet for good on Don't remind me", function()
      local w = { seen = true }
      W.Quiet(w)
      assert.is_true(w.quiet)
      assert.is_nil(W.Decide(w, { tone = "bad" }, NOW + 365 * DAY))
    end)
  end)
end)
