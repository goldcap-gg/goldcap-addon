local helper = require("spec.spec_helper")

-- The account's characters (Core/Alts.lua, retail only): remembered at login and on a level up,
-- and who of them this character can mail. Pure: the client reads happen in the event frame, the
-- rest takes the character and the connected realms as plain values.
describe("alts", function()
  local GC, M, db

  local me = { name = "Thora", realm = "Draenor", class = "WARRIOR", level = 80, faction = "Alliance" }

  local function other(name, realm, faction, level)
    return { name = name, realm = realm, class = "MAGE", level = level or 70, faction = faction or "Alliance" }
  end

  before_each(function()
    GC = helper.loadModule("Core/Alts.lua")
    M = GC.Alts
    db = {}
  end)

  describe("Record", function()
    it("creates the table on the first call", function()
      assert.is_nil(db.alts)
      M.Record(db, me, 100)
      assert.are.equal(1, db.alts.v)
      assert.are.same(
        { name = "Thora", realm = "Draenor", class = "WARRIOR", level = 80, faction = "Alliance", seen = 100 },
        db.alts.chars["Thora-Draenor"])
    end)

    it("updates level and seen on the next call", function()
      M.Record(db, me, 100)
      local up = other("Thora", "Draenor", "Alliance", 81)
      up.class = "WARRIOR"
      M.Record(db, up, 200)
      assert.are.equal(81, db.alts.chars["Thora-Draenor"].level)
      assert.are.equal(200, db.alts.chars["Thora-Draenor"].seen)
    end)

    it("leaves a newer table untouched", function()
      db.alts = { v = 2, chars = {} }
      M.Record(db, me, 100)
      assert.are.same({ v = 2, chars = {} }, db.alts)
    end)

    it("records nothing for an incomplete character", function()
      M.Record(db, { name = "Thora" }, 100)
      assert.is_nil(db.alts)
    end)
  end)

  describe("Recipients", function()
    before_each(function()
      M.Record(db, me, 100)
      M.Record(db, other("Kael", "Draenor"), 150)
      M.Record(db, other("Mirelle", "Draenor"), 300)
      M.Record(db, other("Orc", "Draenor", "Horde"), 400)
      M.Record(db, other("Far", "Silvermoon"), 500)
      M.Record(db, other("Near", "ArgentDawn"), 250)
    end)

    it("lists this realm's same-faction alts, newest first, never me", function()
      local r = M.Recipients(db, me, nil)
      assert.are.equal(2, #r)
      assert.are.equal("Mirelle-Draenor", r[1].full)
      assert.are.equal("Mirelle", r[1].mailName)
      assert.are.equal("Kael-Draenor", r[2].full)
    end)

    it("treats an empty connected list as this realm only", function()
      assert.are.equal(2, #M.Recipients(db, me, {}))
    end)

    it("includes a connected realm with the realm in the mail name", function()
      local r = M.Recipients(db, me, { "Draenor", "ArgentDawn" })
      assert.are.equal(3, #r)
      assert.are.equal("Mirelle-Draenor", r[1].full)
      assert.are.equal("Near-ArgentDawn", r[2].full)
      assert.are.equal("Near-ArgentDawn", r[2].mailName)
      assert.are.equal(250, r[2].seen)
    end)

    it("sorts equal seen by name", function()
      M.Record(db, other("Abel", "Draenor"), 150)
      local r = M.Recipients(db, me, nil)
      assert.are.equal("Abel-Draenor", r[2].full)
      assert.are.equal("Kael-Draenor", r[3].full)
    end)
  end)

  describe("MailName", function()
    it("answers the name to type", function()
      assert.are.equal("Kael", M.MailName("Kael-Draenor", me, nil))
      assert.are.equal("Near-ArgentDawn", M.MailName("Near-ArgentDawn", me, { "ArgentDawn" }))
    end)

    it("answers nil for me and for an unconnected realm", function()
      assert.is_nil(M.MailName("Thora-Draenor", me, nil))
      assert.is_nil(M.MailName("Far-Silvermoon", me, { "ArgentDawn" }))
    end)
  end)

  describe("IsMine", function()
    it("knows a recorded character", function()
      M.Record(db, me, 100)
      assert.is_true(M.IsMine(db, "Thora-Draenor"))
      assert.is_false(M.IsMine(db, "Kael-Draenor"))
      assert.is_false(M.IsMine({}, "Thora-Draenor"))
    end)
  end)

  describe("Full", function()
    it("completes and normalizes a typed name", function()
      assert.are.equal("Mirelle-Draenor", M.Full("mirelle", me))
      assert.are.equal("Kael-TwistingNether", M.Full("Kael-Twisting Nether", me))
    end)

    it("rejects an empty or malformed name", function()
      assert.is_nil(M.Full("", me))
      assert.is_nil(M.Full("a b", me))
      assert.is_nil(M.Full("Kael-", me))
      assert.is_nil(M.Full("-Draenor", me))
      assert.is_nil(M.Full(nil, me))
    end)
  end)
end)
