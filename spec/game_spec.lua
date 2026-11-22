local helper = require("spec.spec_helper")

describe("Client passport", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Game.lua")
  end)

  local function api(version, build, toc, region)
    return {
      GetBuildInfo = function() return version, build, "Sep 23 2026", toc end,
      GetCurrentRegion = function() return region end,
    }
  end

  it("stamps interface, full build and region id", function()
    local p = GC.Game.Passport(api("1.60.1", "69977", nil, 90))
    assert.is_nil(p) -- no interface number, no passport
    p = GC.Game.Passport(api("1.60.1", "69977", 16001, 90))
    assert.same({ interface = 16001, build = "1.60.1.69977", regionId = 90 }, p)
  end)

  it("tells retail from other games by interface number", function()
    assert.is_true(GC.Game.IsRetail(GC.Game.Passport(api("12.1.0", "69933", 120100, 3))))
    assert.is_false(GC.Game.IsRetail(GC.Game.Passport(api("1.60.1", "69977", 16001, 90))))
    assert.equal(100000, GC.Game.RETAIL_MIN_INTERFACE)
  end)

  it("leaves regionId out when the client cannot say", function()
    local p = GC.Game.Passport(api("12.1.0", "69933", 120100, nil))
    assert.equal(120100, p.interface)
    assert.is_nil(p.regionId)
  end)

  it("returns nil instead of erroring when GetBuildInfo is missing or fails", function()
    assert.is_nil(GC.Game.Passport({}))
    assert.is_nil(GC.Game.Passport({ GetBuildInfo = function() error("boom") end }))
    assert.is_nil(GC.Game.Passport({ GetBuildInfo = function() return nil end }))
  end)

  it("treats no passport as retail, as the companion does", function()
    assert.is_true(GC.Game.IsRetail(nil))
  end)

  it("recognises WoW: Forever by its interface number", function()
    assert.is_true(GC.Game.IsForever({ interface = 16001, build = "1.60.1.69977" }))
    assert.is_true(GC.Game.IsForever({ interface = 16999, build = "1.69.9.1" }))
    assert.is_false(GC.Game.IsForever({ interface = 120100, build = "12.1.0.69933" }))
    assert.is_false(GC.Game.IsForever({ interface = 11508, build = "1.15.8.1" }))
    assert.is_false(GC.Game.IsForever(nil))
  end)
end)

-- WoW: Forever 1.60.1.71037 answers GetRealmName() with "" (owner's save and a player's report,
-- 2026-11-21): scans stopped uploading and cost batches keyed "Name-Realm" stopped matching.
describe("Realm name", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Game.lua")
  end)

  local function api(live, db, guid)
    return {
      GetRealmName = function() return live end,
      GetNormalizedRealmName = function() return nil end,
      UnitGUID = function() return guid or "Player-6949-00C1ADCA" end,
      UnitName = function() return "Meolys" end,
      db = function() return db end,
    }
  end

  it("takes the live answer and remembers it for the server", function()
    local db = {}
    assert.equal("Realm 7", GC.Game.RealmName(api("Realm 7", db)))
    assert.same({ ["6949"] = "Realm 7" }, db.realmByServer)
    -- Then the client stops answering: the remembered name, on this server only.
    assert.equal("Realm 7", GC.Game.RealmName(api("", db)))
    assert.is_nil(GC.Game.RealmName(api("", db, "Player-7000-00000001")))
  end)

  it("finds the realm this character's own rows were written with", function()
    local db = { ledger = { { char = "Meolys-Realm 7" }, { char = "Meolys-" }, { char = "Other-Realm 9" } } }
    assert.equal("Realm 7", GC.Game.RealmName(api("", db)))
    assert.equal("Realm 7", db.realmByServer["6949"])
  end)

  it("says nothing when the history names two realms, or none", function()
    assert.is_nil(GC.Game.RealmName(api("", { a = { { char = "Meolys-A" }, { character = "Meolys-B" } } })))
    GC.Game._historyMissed = {}
    assert.is_nil(GC.Game.RealmName(api(nil, { a = { { char = "Meolys-" } } })))
  end)

  it("normalizes the fallback as the client does", function()
    assert.equal("CAMWOWEU5Realm7PvE", GC.Game.NormalizedRealmName(api("CAMWOW EU5 Realm 7 PvE", {})))
  end)

  it("puts realmless rows and keys back under the realm, this region only", function()
    local db = {
      ledger = { { char = "Meolys-", region = "eu" }, { char = "Meolys-", region = "us" }, { char = "Meolys-R" } },
      batches = { { character = "Meolys-", region = "eu" } },
      craft = { chars = { ["Meolys-"] = { new = 1 }, ["Meolys-R"] = { old = 1, new = 0 } } },
      buyProgress = { ["Meolys-"] = { x = 2 } },
      streaks = { ["Meolys-eu"] = { s = 1 } },
    }
    assert.equal(5, GC.Game.RepairRealmless(db, "Meolys", "R", "eu"))
    assert.equal("Meolys-R", db.ledger[1].char)
    assert.equal("Meolys-", db.ledger[2].char)               -- another region's row is someone else
    assert.equal("Meolys-R", db.batches[1].character)
    assert.same({ ["Meolys-R"] = { old = 1, new = 1 } }, db.craft.chars)   -- the realmless side wins
    assert.same({ ["Meolys-R"] = { x = 2 } }, db.buyProgress)
    assert.same({ ["Meolys-Reu"] = { s = 1 } }, db.streaks)
  end)

  it("reads the server from a player GUID", function()
    assert.equal("6949", GC.Game.ServerId("Player-6949-00C1ADCA"))
    assert.is_nil(GC.Game.ServerId("Creature-0-1"))
  end)
end)

-- The owner's Shellfish (2026-11-22): 12 sold on 21.11 while the realm was unnamed consumed
-- nothing, and the activity keyed "eu\1Meolys-\1..." made Acquisitions refuse every sale after.
describe("Realm repair, scope keys and the sales it left open", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Game.lua")
  end)

  it("moves a scope-keyed activity under the realm and merges it with its twin", function()
    local bare, full = "eu\1Meolys-\1commodity:1", "eu\1Meolys-R\1commodity:1"
    local db = { acquisitionActivity = {
      [bare] = { character = "Meolys-R", scopeKey = bare, firstSeenAt = 300, lastSeenAt = 900, lastPostedQty = 15 },
      [full] = { character = "Meolys-R", scopeKey = full, firstSeenAt = 100, lastSeenAt = 500, lastPostedQty = 3 },
    }, acquisitions = { { character = "Meolys-", scopeKey = bare } } }
    GC.Game.RepairRealmless(db, "Meolys", "R", "eu")
    assert.is_nil(db.acquisitionActivity[bare])
    assert.same({ character = "Meolys-R", scopeKey = full, firstSeenAt = 100, lastSeenAt = 900, lastPostedQty = 15 },
      db.acquisitionActivity[full])
    assert.same({ character = "Meolys-R", scopeKey = full }, db.acquisitions[1])
  end)

  it("offers this character's unconsumed sales since the break back, oldest first, once", function()
    local T = GC.Game.REALMLESS_SINCE
    local db = { ledger = {
      { kind = "sale", source = "mail", char = "M-R", at = T + 20, key = "b" },
      { kind = "sale", source = "mail", char = "M-R", at = T + 10, key = "a" },
      { kind = "sale", source = "mail", char = "M-R", at = T - 10, key = "old" },   -- before the break
      { kind = "sale", source = "mail", char = "M-R", at = T + 30, key = "done" },  -- already consumed
      { kind = "sale", source = "mail", char = "X-R", at = T + 40, key = "alt" },   -- another character
      { kind = "buy", source = "mail", char = "M-R", at = T + 50, key = "buy" },
    }, acquisitionConsumptionEvidence = { done = true } }
    local offered = {}
    local function reconcile(entry)
      offered[#offered + 1] = entry.key
      return { status = entry.key == "a" and "applied" or "unresolved" }
    end
    assert.equal(1, GC.Game.ReconcileRealmlessSales(db, "M-R", reconcile))
    assert.same({ "a", "b" }, offered)
    assert.equal(0, GC.Game.ReconcileRealmlessSales(db, "M-R", reconcile))
    assert.same({ "a", "b" }, offered)
  end)
end)
