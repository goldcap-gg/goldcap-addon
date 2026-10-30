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

  -- Whose side a character is on, for Send to alts: characters of opposite factions cannot mail
  -- each other.
  describe("FactionOf", function()
    it("answers a recorded character's faction, and nil for one never recorded", function()
      local saved = {}
      M.Record(saved, { name = "Orcy", realm = "Tarren", class = "SHAMAN", level = 80, faction = "Horde" }, 1)
      assert.equal("Horde", M.FactionOf(saved, "Orcy-Tarren"))
      assert.is_nil(M.FactionOf(saved, "Stranger-Tarren"))
      assert.is_nil(M.FactionOf({}, "Orcy-Tarren"))
      assert.is_nil(M.FactionOf(saved, nil))
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

    -- A save written by hand or by another tool can lack `seen`: it sorts as never seen.
    it("sorts a saved character with no seen last, as never seen", function()
      db.alts.chars["Abel-Draenor"] = { name = "Abel", realm = "Draenor", class = "MAGE", level = 70, faction = "Alliance" }
      local r = M.Recipients(db, me, nil)
      assert.are.equal(3, #r)
      assert.are.equal("Abel-Draenor", r[3].full)
    end)
  end)

  -- A character deleted or renamed long ago may have had its name taken by someone else: mail to
  -- one not seen for 30 days is asked about again.
  describe("Recent", function()
    it("is true for a character seen within 30 days, and false after, unrecorded or never seen", function()
      local now = 1000 * 86400
      M.Record(db, other("Kael", "Draenor"), now - 29 * 86400)
      M.Record(db, other("Old", "Draenor"), now - 31 * 86400)
      db.alts.chars["Bare-Draenor"] = { name = "Bare", realm = "Draenor", class = "MAGE", level = 70, faction = "Alliance" }
      assert.equal(30 * 86400, M.RECENT)
      assert.is_true(M.Recent(db, "Kael-Draenor", now))
      assert.is_false(M.Recent(db, "Old-Draenor", now))
      assert.is_false(M.Recent(db, "Bare-Draenor", now))
      assert.is_false(M.Recent(db, "Nobody-Draenor", now))
      assert.is_false(M.Recent({}, "Kael-Draenor", now))
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

  -- Lua's own upper and lower stop at ASCII: a name typed in lower case in Russian or French keeps
  -- its first letter small. The fold covers the letters of the realms GoldCap's languages play on.
  describe("Lower and UpperFirst", function()
    local PAIRS = {
      { "A", "a" }, { "Z", "z" },
      -- Latin-1 Supplement: U+00C0 to U+00DE and U+0020 above.
      { "À", "à" }, { "É", "é" }, { "Ö", "ö" }, { "Ø", "ø" }, { "Þ", "þ" },
      -- Latin Extended-A: upper even then lower odd, and from U+0139 and U+0179 the other way.
      { "Ā", "ā" }, { "Į", "į" }, { "Ĳ", "ĳ" }, { "Ķ", "ķ" }, { "Ĺ", "ĺ" }, { "Ň", "ň" }, { "Ŋ", "ŋ" },
      { "Œ", "œ" }, { "Ŷ", "ŷ" }, { "Ź", "ź" }, { "Ž", "ž" },
      -- Cyrillic: U+0410 to U+042F and U+0400 to U+040F.
      { "А", "а" }, { "Я", "я" }, { "П", "п" }, { "Р", "р" }, { "Ё", "ё" }, { "Ѐ", "ѐ" }, { "Є", "є" }, { "І", "і" },
      { "Ї", "ї" }, { "Џ", "џ" },
      -- Cyrillic Extended pairs, upper even: Ukrainian Ґ, and the rest from U+0490 to U+04BF.
      { "Ґ", "ґ" }, { "Ғ", "ғ" }, { "Ү", "ү" }, { "Ҿ", "ҿ" },
    }

    it("folds each letter's two cases into one another", function()
      for _, p in ipairs(PAIRS) do
        assert.equal(p[2], M.Lower(p[1]), p[1])
        assert.equal(p[2], M.Lower(p[2]), p[2])
        assert.equal(p[1], M.UpperFirst(p[2]), p[2])
        assert.equal(p[1], M.UpperFirst(p[1]), p[1])
      end
    end)

    it("leaves letters with no pair in these ranges, and other scripts, as they are", function()
      for _, s in ipairs({ "×", "÷", "ß", "ÿ", "İ", "ı", "ĸ", "ŉ", "ſ", "가", "金", "1" }) do
        assert.equal(s, M.Lower(s), s)
        assert.equal(s, M.UpperFirst(s), s)
      end
    end)

    it("lowers a whole name, and raises only the first letter", function()
      assert.equal("мирелла", M.Lower("МиРеЛЛа"))
      assert.equal("Мирелла", M.UpperFirst("мирелла"))
      assert.equal("Élise", M.UpperFirst("élise"))
      assert.equal("ÉLISE", M.UpperFirst("éLISE"))
      assert.equal("", M.UpperFirst(""))
    end)
  end)

  describe("Full", function()
    it("completes and normalizes a typed name", function()
      assert.are.equal("Mirelle-Draenor", M.Full(db, "mirelle", me))
      assert.are.equal("Kael-TwistingNether", M.Full(db, "Kael-Twisting Nether", me))
    end)

    it("rejects an empty or malformed name", function()
      assert.is_nil(M.Full(db, "", me))
      assert.is_nil(M.Full(db, "a b", me))
      assert.is_nil(M.Full(db, "Kael-", me))
      assert.is_nil(M.Full(db, "-Draenor", me))
      assert.is_nil(M.Full(db, nil, me))
    end)

    it("raises a first letter in any of its languages", function()
      assert.are.equal("Мирелла-Draenor", M.Full(db, "мирелла", me))
      assert.are.equal("Élise-Draenor", M.Full(db, "élise", me))
    end)

    -- Typed in whatever case, one of the player's characters is that character, as recorded.
    it("takes a recorded character's own spelling", function()
      M.Record(db, other("Mirelle", "Draenor"), 100)
      M.Record(db, other("Мирелла", "Draenor"), 100)
      M.Record(db, other("Élise", "TwistingNether"), 100)
      assert.are.equal("Mirelle-Draenor", M.Full(db, "MIRELLE", me))
      assert.are.equal("Мирелла-Draenor", M.Full(db, "мИРЕЛЛА", me))
      assert.are.equal("Élise-TwistingNether", M.Full(db, "ÉLISE-twistingnether", me, { "TwistingNether" }))
    end)

    -- The realm as the client spells it, whatever the case, spaces, hyphens or apostrophes typed.
    it("matches a typed realm to this one or a connected one, in the list's spelling", function()
      local connected = { "Draenor", "TwistingNether", "AzjolNerub", "Mal'Ganis" }
      assert.are.equal("Kael-TwistingNether", M.Full(db, "Kael-twistingnether", me, connected))
      assert.are.equal("Kael-TwistingNether", M.Full(db, "Kael-twisting nether", me, connected))
      assert.are.equal("Name-AzjolNerub", M.Full(db, "Name-Azjol-Nerub", me, connected))
      assert.are.equal("Name-AzjolNerub", M.Full(db, "Name-AzjolNerub", me, connected))
      assert.are.equal("Name-AzjolNerub", M.Full(db, "name-azjol nerub", me, connected))
      assert.are.equal("Kael-Mal'Ganis", M.Full(db, "Kael-malganis", me, connected))
      assert.are.equal("Kael-Draenor", M.Full(db, "Kael-DRAENOR", me))
      -- A realm in neither list stays as typed, without spaces, for MailName to refuse.
      assert.are.equal("Far-Silvermoon", M.Full(db, "Far-Silver moon", me, connected))
    end)
  end)
end)
