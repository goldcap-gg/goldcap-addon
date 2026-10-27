local helper = require("spec.spec_helper")

-- Send to alts (Core/MailGroups.lua, retail only): which stacks of a followed group go in which
-- mail to which alt. The stacks are what UI/BankRoute.lua's reader hands over, the group of an item
-- Core/GroupRules.lua's (faked as a table: the key and the name), the recipient and what this
-- character can mail are handed in as functions; the keep count is the Hoard's, so the planner
-- sits on Core/BankGroups.lua's Plan and these specs only pin what the mail adds to it.
describe("mail groups", function()
  local GC, M

  -- Herbs: 1 and 2; Ore: 3; Cloth: 4. Item 9 is in no followed group.
  local GROUP = { [1] = "Herbs", [2] = "Herbs", [3] = "Ore", [4] = "Cloth" }
  local NAMES = { [1] = "Bloom", [2] = "Bloom", [3] = "Bismuth", [4] = "Linen", [9] = "Rag" }

  local function stack(itemID, bag, slot, count, over)
    local s = { itemID = itemID, bag = bag, slot = slot, count = count, name = NAMES[itemID] }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end

  -- `to`: group key -> "Name-Realm"; `opts` overrides any planner option. This character is
  -- Me-Tarren, and can mail names on Tarren (this realm) and Kazzak (connected) only.
  local function plan(bags, to, keep, opts)
    local o = {
      groupOf = function(id) return GROUP[id], GROUP[id] end,
      keepFor = function(key) return (keep or {})[key] or 0 end,
      moving = {},
      recipientOf = function(key) return (to or {})[key] end,
      mailName = function(full)
        local name, realm = full:match("^(.-)%-(.+)$")
        if realm == "Tarren" then return name end
        if realm == "Kazzak" then return full end
        return nil
      end,
      isMe = function(full) return full == "Me-Tarren" end,
      nameOf = function(full) return full end,
    }
    for k, v in pairs(opts or {}) do o[k] = v end
    return M.Plan(bags, o)
  end

  local function row(p, key)
    for _, r in ipairs(p.rows) do if r.key == key then return r end end
  end

  local function where(stacks)
    local out = {}
    for _, s in ipairs(stacks) do out[#out + 1] = s.bag .. ":" .. s.slot end
    return out
  end

  -- n stacks of item `id` in bag 0, slots 1..n, 10 each.
  local function many(id, n, bag)
    local out = {}
    for i = 1, n do out[#out + 1] = stack(id, bag or 0, i, 10) end
    return out
  end

  local function letters(s) return select(2, s:gsub("[^\128-\191]", "")) end

  before_each(function()
    GC = helper.loadModule("Core/BankGroups.lua")
    helper.loadModule("Core/Alts.lua", GC)
    helper.loadModule("Core/MailGroups.lua", GC)
    M = GC.MailGroups
  end)

  it("sends 12 stacks a mail, 30 copper a stack, in subjects of 64 letters", function()
    assert.equal(12, M.MAX_ATTACH)
    assert.equal(30, M.POSTAGE)
    assert.equal(64, M.SUBJECT_MAX)
  end)

  describe("StaysWhy", function()
    it("names a bound or Warbound-until-equipped stack, and a refundable one", function()
      assert.equal("bound", M.StaysWhy({ bound = true }, false))
      assert.equal("bound", M.StaysWhy({ wue = true }, false))
      assert.equal("refund", M.StaysWhy({}, true))
      assert.equal("bound", M.StaysWhy({ bound = true }, true))
      assert.is_nil(M.StaysWhy({}, false))
      assert.is_nil(M.StaysWhy({}, nil))
    end)
  end)

  describe("rows", function()
    it("leaves the bags the keep count, the biggest stacks going first, as the Hoard does", function()
      local p = plan({ stack(1, 0, 1, 100), stack(1, 0, 2, 50), stack(1, 0, 3, 30) },
        { Herbs = "Mule-Tarren" }, { Herbs = 20 })
      local r = row(p, "Herbs")
      -- 180 in the bags, 20 kept: the 100 and the 50 whole, 10 split off the 30.
      assert.same({ "0:1", "0:2", "0:3" }, where(r.send))
      assert.same({ 100, 50, 10 }, { r.send[1].count, r.send[2].count, r.send[3].count })
      assert.equal(30, r.send[3].split)
      assert.equal(20, r.keep)
      assert.same({ { itemID = 1, name = "Bloom", count = 160 } }, r.items)
      assert.equal("send", r.state)
      assert.equal("Mule-Tarren", r.to)
      assert.equal("Mule", r.mailName)
    end)

    it("counts a split as one stack: one of the 12 attachments, postage once, its count in the items", function()
      local p = plan({ stack(1, 0, 1, 100), stack(1, 0, 2, 50), stack(1, 0, 3, 30) },
        { Herbs = "Mule-Tarren" }, { Herbs = 20 })
      assert.equal(3, p.stacks)
      assert.equal(3 * M.POSTAGE, p.postage)
      assert.equal(1, #p.mails)
      assert.equal(3, #p.mails[1].stacks)
      assert.equal(10, p.mails[1].stacks[3].count)
      assert.equal(30, p.mails[1].stacks[3].split)
      -- Thirteen stacks need two mails; a split is one of them like any other.
      local bags = {}
      for i = 1, 12 do bags[i] = stack(1, 0, i, 100) end
      bags[13] = stack(1, 0, 13, 7)
      p = plan(bags, { Herbs = "Mule-Tarren" }, { Herbs = 20 })
      -- 1207 in the bags, 20 kept: 11 whole 100s and the 7 go, then 80 split off the last 100.
      assert.equal(13, p.stacks)
      assert.same({ 12, 1 }, { #p.mails[1].stacks, #p.mails[2].stacks })
      assert.equal(13 * M.POSTAGE, p.postage)
    end)

    it("never sends a bound, a Warbound-until-equipped or a refundable stack, and says why it stays", function()
      local p = plan({
        stack(1, 0, 1, 10, { stays = "bound" }), stack(1, 0, 2, 10, { stays = "refund" }),
        stack(1, 0, 3, 10, { stays = "bound", wue = true }), stack(1, 0, 4, 10),
      }, { Herbs = "Mule-Tarren" })
      local r = row(p, "Herbs")
      assert.same({ "0:4" }, where(r.send))
      assert.same({ { itemID = 1, name = "Bloom", count = 20, why = "bound" },
        { itemID = 1, name = "Bloom", count = 10, why = "refund" } }, r.stays)
    end)

    it("is 'nothing' when all of a group is kept or stays, even with a recipient", function()
      local p = plan({ stack(1, 0, 1, 10), stack(3, 0, 2, 10, { stays = "bound" }) },
        { Herbs = "Mule-Tarren", Ore = "Mule-Tarren" }, { Herbs = 10 })
      assert.equal("nothing", row(p, "Herbs").state)
      assert.equal("nothing", row(p, "Ore").state)
      assert.same({}, p.mails)
      assert.equal(0, p.stacks)
      assert.equal(0, p.postage)
    end)

    it("is 'pick' with no recipient, and for one on a realm this character cannot mail", function()
      local p = plan({ stack(1, 0, 1, 10), stack(3, 0, 2, 10) }, { Ore = "Far-Draenor" })
      assert.equal("pick", row(p, "Herbs").state)
      assert.is_nil(row(p, "Herbs").to)
      local ore = row(p, "Ore")
      assert.equal("pick", ore.state)
      assert.equal("Far-Draenor", ore.to)
      assert.is_nil(ore.mailName)
      assert.same({}, p.mails)
    end)

    it("is 'self' when the recipient is this character, which never mails itself", function()
      local p = plan({ stack(1, 0, 1, 10) }, { Herbs = "Me-Tarren" })
      assert.equal("self", row(p, "Herbs").state)
      assert.same({}, p.mails)
    end)

    it("mails a connected realm's alt by the full name", function()
      local p = plan({ stack(1, 0, 1, 10) }, { Herbs = "Far-Kazzak" })
      assert.equal("Far-Kazzak", p.mails[1].to)
      assert.equal("Far-Kazzak", p.mails[1].full)
    end)

    it("skips a stack a press has sent and a locked one, and sorts rows by group name", function()
      local p = plan({ stack(1, 0, 1, 10), stack(1, 0, 2, 10, { locked = true }), stack(1, 0, 3, 10), stack(3, 0, 4, 5) },
        { Herbs = "Mule-Tarren" }, nil, { moving = { ["0:1"] = true } })
      assert.same({ "0:3" }, where(row(p, "Herbs").send))
      assert.equal("Herbs", p.rows[1].key)
      assert.equal("Ore", p.rows[2].key)
    end)
  end)

  describe("mails", function()
    it("cuts 14 stacks to one alt into two mails, of 12 and of 2", function()
      local p = plan(many(1, 14), { Herbs = "Mule-Tarren" })
      assert.equal(2, #p.mails)
      assert.equal(12, #p.mails[1].stacks)
      assert.equal(2, #p.mails[2].stacks)
      assert.equal("Mule", p.mails[1].to)
      assert.same({ "Herbs" }, p.mails[1].keys)
      assert.same({ "Herbs" }, p.mails[2].keys)
      assert.equal("GoldCap: Herbs", p.mails[2].subject)
      assert.equal(14, p.stacks)
      assert.equal(420, p.postage)
    end)

    it("shares one mail between two groups for one alt, named in the subject", function()
      local bags = many(1, 4)
      for i = 1, 3 do bags[#bags + 1] = stack(3, 1, i, 10) end
      local p = plan(bags, { Herbs = "Mule-Tarren", Ore = "Mule-Tarren" })
      assert.equal(1, #p.mails)
      assert.equal(7, #p.mails[1].stacks)
      assert.same({ "Herbs", "Ore" }, p.mails[1].keys)
      assert.equal("GoldCap: Herbs, Ore", p.mails[1].subject)
    end)

    it("starts a recipient's next mail where the last stopped, a group spanning both", function()
      local bags = many(1, 10)
      for i = 1, 4 do bags[#bags + 1] = stack(3, 1, i, 10) end
      local p = plan(bags, { Herbs = "Mule-Tarren", Ore = "Mule-Tarren" })
      assert.equal(2, #p.mails)
      assert.same({ "Herbs", "Ore" }, p.mails[1].keys)
      assert.equal(12, #p.mails[1].stacks)
      assert.same({ "Ore" }, p.mails[2].keys)
      assert.equal("GoldCap: Ore", p.mails[2].subject)
      assert.equal(2, #p.mails[2].stacks)
    end)

    it("keeps one alt's mails apart from another's, in row order", function()
      local p = plan({ stack(1, 0, 1, 10), stack(3, 0, 2, 10), stack(4, 0, 3, 10) },
        { Herbs = "Mule-Tarren", Ore = "Other-Tarren", Cloth = "Mule-Tarren" })
      assert.equal(2, #p.mails)
      assert.equal("Mule", p.mails[1].to)
      assert.same({ "Cloth", "Herbs" }, p.mails[1].keys)
      assert.equal("Other", p.mails[2].to)
    end)

    it("sums postage over all mails: 11 stacks cost 330 copper", function()
      local p = plan(many(1, 11), { Herbs = "Mule-Tarren" })
      assert.equal(11, p.stacks)
      assert.equal(330, p.postage)
    end)

    it("keeps a subject within 64 letters, ending ' and N more', never cutting a name", function()
      local group = {}
      local bags, to = {}, {}
      for i = 1, 10 do
        local id = 100 + i
        local name = "Dragonflight Herbs " .. i
        group[id] = name
        bags[#bags + 1] = { itemID = id, bag = 0, slot = i, count = 10, name = name }
        to[name] = "Mule-Tarren"
      end
      local p = plan(bags, to, nil, { groupOf = function(id) return group[id], group[id] end })
      assert.equal(1, #p.mails)
      local subject = p.mails[1].subject
      assert.is_true(letters(subject) <= 64)
      assert.truthy(subject:match(" and %d+ more$"))
      assert.is_nil(subject:find("…", 1, true))
      assert.equal("GoldCap: Dragonflight Herbs 1, Dragonflight Herbs 10 and 8 more", subject)
    end)

    -- A group's name has no cap on goldcap.gg, and a subgroup's is "Parent: Child": a name too long
    -- for the subject even alone, or with " and N more", is not cut; the subject counts the groups.
    it("counts the groups when even one name is over 64 letters", function()
      local long = ("Gloomshroom and Luredrop from the Hall of Awakening for Potions "):rep(2):sub(1, 70)
      assert.equal(70, letters(long))
      local group = { [101] = long, [102] = "Ore" }
      local function groupOf(id) return group[id], group[id] end
      local alone = plan({ stack(101, 0, 1, 10) }, { [long] = "Mule-Tarren" }, nil, { groupOf = groupOf })
      assert.equal("GoldCap: 1 group", alone.mails[1].subject)
      local two = plan({ stack(101, 0, 1, 10), stack(102, 0, 2, 10) }, { [long] = "Mule-Tarren", Ore = "Mule-Tarren" },
        nil, { groupOf = groupOf })
      assert.equal(1, #two.mails)
      assert.equal("GoldCap: 2 groups", two.mails[1].subject)
      assert.equal("GoldCap: 1 group", M.MailsFor(two, long)[1].subject)
    end)

    it("counts a subject's letters, not its bytes", function()
      local bags, to, group = {}, {}, {}
      for i = 1, 6 do
        local name = "Травы и корни " .. i
        group[100 + i] = name
        bags[#bags + 1] = { itemID = 100 + i, bag = 0, slot = i, count = 1, name = name }
        to[name] = "Mule-Tarren"
      end
      local p = plan(bags, to, nil, { groupOf = function(id) return group[id], group[id] end })
      local subject = p.mails[1].subject
      assert.is_true(letters(subject) <= 64)
      assert.equal("GoldCap: Травы и корни 1, Травы и корни 2 and 4 more", subject)
    end)
  end)

  describe("MailsFor", function()
    it("mails one group alone, cut at 12, with its own subject", function()
      local bags = many(1, 13)
      bags[#bags + 1] = stack(3, 1, 1, 10)
      local p = plan(bags, { Herbs = "Mule-Tarren", Ore = "Mule-Tarren" })
      local mails = M.MailsFor(p, "Herbs")
      assert.equal(2, #mails)
      assert.equal(12, #mails[1].stacks)
      assert.equal(1, #mails[2].stacks)
      assert.same({ "Herbs" }, mails[1].keys)
      assert.equal("GoldCap: Herbs", mails[1].subject)
      assert.equal("Mule", mails[1].to)
    end)

    it("is empty for a group that is not 'send', or not there", function()
      local p = plan({ stack(1, 0, 1, 10), stack(3, 0, 2, 10) }, { Ore = "Me-Tarren" })
      assert.same({}, M.MailsFor(p, "Herbs"))
      assert.same({}, M.MailsFor(p, "Ore"))
      assert.same({}, M.MailsFor(p, "Nope"))
    end)
  end)

  describe("recipients", function()
    it("remembers a group's recipient per home realm, lazily, and forgets on nil", function()
      local db = {}
      assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs"))
      assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", nil))
      assert.is_nil(db.mailTo)
      assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", "Mule-Tarren"))
      assert.same({ v = 1, realms = { Tarren = { Herbs = "Mule-Tarren" } }, trusted = {} }, db.mailTo)
      assert.equal("Mule-Tarren", M.RecipientOf(db, "Tarren", "Herbs"))
      assert.is_nil(M.RecipientOf(db, "Kazzak", "Herbs"))
      assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", nil))
      assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs"))
    end)

    it("trusts a character once, account-wide", function()
      local db = {}
      assert.is_false(M.Trusted(db, "Mule-Tarren"))
      assert.is_true(M.Trust(db, "Mule-Tarren"))
      assert.is_true(M.Trusted(db, "Mule-Tarren"))
      assert.is_false(M.Trusted(db, "Other-Tarren"))
    end)

    it("refuses bad input", function()
      local db = {}
      assert.is_false(M.SetRecipient(db, "Tarren", "", "Mule-Tarren"))
      assert.is_false(M.SetRecipient(db, "", "Herbs", "Mule-Tarren"))
      assert.is_false(M.SetRecipient(db, "Tarren", "Herbs", 5))
      assert.is_false(M.Trust(db, ""))
      assert.is_nil(db.mailTo)
    end)

    -- Characters of opposite factions cannot mail each other (the code review, 2026-10-27): a choice
    -- is kept for the faction that made it (mailTo.byFaction, beside the old `realms`), a recipient
    -- recorded of the other faction (Core/Alts.lua) never counts, and an old save reads only for its
    -- recipient's own faction.
    describe("by faction", function()
      local db
      local function rec(name, faction)
        GC.Alts.Record(db, { name = name, realm = "Tarren", class = "MAGE", level = 80, faction = faction }, 1)
      end
      before_each(function()
        db = {}
        rec("Mule", "Alliance")
        rec("Grunt", "Horde")
      end)

      it("keeps each faction's own choice on one realm", function()
        assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", "Mule-Tarren", "Alliance"))
        assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs", "Horde"))
        assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", "Grunt-Tarren", "Horde"))
        assert.equal("Mule-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Alliance"))
        assert.equal("Grunt-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Horde"))
        assert.is_nil(db.mailTo.realms.Tarren)
        assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", nil, "Horde"))
        assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs", "Horde"))
        assert.equal("Mule-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Alliance"))
        assert.is_nil(M.RecipientOf(db, "Kazzak", "Herbs", "Alliance"))
      end)

      it("never counts a recipient recorded of the other faction", function()
        assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", "Mule-Tarren", "Horde"))
        assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs", "Horde"))
        -- A name GoldCap never saw log in: its faction is not known, so the choice stands.
        assert.is_true(M.SetRecipient(db, "Tarren", "Ore", "Stranger-Tarren", "Horde"))
        assert.equal("Stranger-Tarren", M.RecipientOf(db, "Tarren", "Ore", "Horde"))
      end)

      it("reads an old save for its recipient's faction only, until that faction chooses again", function()
        db.mailTo = { v = 1, realms = { Tarren = { Herbs = "Mule-Tarren", Ore = "Stranger-Tarren" } }, trusted = {} }
        assert.equal("Mule-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Alliance"))
        assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs", "Horde"))
        -- Whose faction the old entry was for cannot be told: it reads for neither.
        assert.is_nil(M.RecipientOf(db, "Tarren", "Ore", "Alliance"))
        assert.is_nil(M.RecipientOf(db, "Tarren", "Ore", "Horde"))
        -- The Horde chooses: the old entry stays for the Alliance.
        assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", "Grunt-Tarren", "Horde"))
        assert.equal("Mule-Tarren", db.mailTo.realms.Tarren.Herbs)
        assert.equal("Mule-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Alliance"))
        -- The Alliance forgets: its old entry goes with it, so it never comes back.
        assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", nil, "Alliance"))
        assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs", "Alliance"))
        assert.is_nil(db.mailTo.realms.Tarren.Herbs)
        assert.equal("Grunt-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Horde"))
        assert.equal("Stranger-Tarren", db.mailTo.realms.Tarren.Ore)
      end)
    end)

    it("leaves a newer GoldCap's table as it is, read-only", function()
      local db = { mailTo = { v = 2, realms = { Tarren = { Herbs = "X-Tarren" } }, trusted = {} } }
      assert.is_false(M.Writable(db))
      assert.is_nil(M.RecipientOf(db, "Tarren", "Herbs"))
      assert.is_false(M.SetRecipient(db, "Tarren", "Herbs", "Mule-Tarren"))
      assert.is_false(M.Trust(db, "Mule-Tarren"))
      assert.is_false(M.Trusted(db, "X-Tarren"))
      assert.equal(2, db.mailTo.v)
      assert.is_true(M.Writable({}))
    end)
  end)

  -- A group set not to be sent: per home realm and faction, as the recipient is.
  describe("skipped groups", function()
    it("round trips per realm and faction, and leaves the others as they were", function()
      local db = {}
      assert.is_false(M.Skipped(db, "Tarren", "Herbs", "Alliance"))
      assert.is_nil(db.mailTo)
      assert.is_true(M.SetSkipped(db, "Tarren", "Herbs", "Alliance", true))
      assert.is_true(M.Skipped(db, "Tarren", "Herbs", "Alliance"))
      assert.is_false(M.Skipped(db, "Tarren", "Herbs", "Horde"))
      assert.is_false(M.Skipped(db, "Kazzak", "Herbs", "Alliance"))
      assert.is_false(M.Skipped(db, "Tarren", "Ore", "Alliance"))
      assert.same({ Tarren = { Alliance = { Herbs = true } } }, db.mailTo.skip)
      assert.is_true(M.SetSkipped(db, "Tarren", "Herbs", "Horde", true))
      assert.is_true(M.SetSkipped(db, "Tarren", "Herbs", "Alliance", false))
      assert.is_false(M.Skipped(db, "Tarren", "Herbs", "Alliance"))
      assert.is_true(M.Skipped(db, "Tarren", "Herbs", "Horde"))
      assert.is_true(M.SetSkipped(db, "Tarren", "Herbs", "Horde", false))
      assert.is_nil(db.mailTo.skip, "emptied tables are pruned")
    end)

    it("writes nothing for a realm, faction or group that is not a name", function()
      local db = {}
      assert.is_false(M.SetSkipped(db, "Tarren", "Herbs", nil, true))
      assert.is_false(M.SetSkipped(db, "Tarren", "Herbs", "", true))
      assert.is_false(M.SetSkipped(db, nil, "Herbs", "Alliance", true))
      assert.is_false(M.SetSkipped(db, "", "Herbs", "Alliance", true))
      assert.is_false(M.SetSkipped(db, "Tarren", "", "Alliance", true))
      assert.is_nil(db.mailTo)
      assert.is_false(M.Skipped({ mailTo = { v = 1, realms = {}, trusted = {}, skip = { Tarren = { [""] = { Herbs = true } } } } },
        "Tarren", "Herbs", ""))
    end)

    it("is forgotten when someone is chosen to sell the group, for that realm and faction only", function()
      local db = {}
      M.SetSkipped(db, "Tarren", "Herbs", "Alliance", true)
      M.SetSkipped(db, "Tarren", "Herbs", "Horde", true)
      M.SetSkipped(db, "Kazzak", "Herbs", "Alliance", true)
      M.SetSkipped(db, "Tarren", "Ore", "Alliance", true)
      assert.is_true(M.SetRecipient(db, "Tarren", "Herbs", "Mirelle-Tarren", "Alliance"))
      assert.is_false(M.Skipped(db, "Tarren", "Herbs", "Alliance"))
      assert.is_true(M.Skipped(db, "Tarren", "Herbs", "Horde"))
      assert.is_true(M.Skipped(db, "Kazzak", "Herbs", "Alliance"))
      assert.is_true(M.Skipped(db, "Tarren", "Ore", "Alliance"))
      assert.equal("Mirelle-Tarren", M.RecipientOf(db, "Tarren", "Herbs", "Alliance"))
    end)

    it("stays read-only in a newer GoldCap's save", function()
      local db = { mailTo = { v = 2, realms = {}, trusted = {}, skip = { Tarren = { Alliance = { Herbs = true } } } } }
      assert.is_false(M.SetSkipped(db, "Tarren", "Herbs", "Alliance", false))
      assert.is_false(M.SetSkipped(db, "Tarren", "Ore", "Alliance", true))
      assert.is_true(db.mailTo.skip.Tarren.Alliance.Herbs)
      assert.is_nil(db.mailTo.skip.Tarren.Alliance.Ore)
      assert.is_false(M.Skipped(db, "Tarren", "Herbs", "Alliance"))
    end)

    it("leaves a skipped group out of the mails, the stacks and the postage", function()
      local bags = { stack(1, 0, 1, 10), stack(3, 0, 2, 10), stack(4, 0, 3, 10) }
      local to = { Herbs = "Mirelle-Tarren", Ore = "Mirelle-Tarren", Cloth = "Mirelle-Tarren" }
      local p = plan(bags, to, nil, { skipped = function(key) return key == "Ore" end })
      local ore = row(p, "Ore")
      assert.equal("skipped", ore.state)
      assert.equal(1, #ore.send)
      assert.equal(1, #ore.items)
      assert.equal(1, #p.mails)
      assert.equal(2, p.stacks)
      assert.equal(2 * M.POSTAGE, p.postage)
      assert.same({ "Cloth", "Herbs" }, p.mails[1].keys)
      assert.same({}, M.MailsFor(p, "Ore"))
      assert.equal("send", row(p, "Herbs").state)
    end)

    it("is skipped whatever else holds: no one chosen, this character, nothing to send", function()
      local bags = { stack(1, 0, 1, 10), stack(3, 0, 2, 10), stack(4, 0, 3, 10) }
      local all = function() return true end
      local p = plan(bags, { Ore = "Me-Tarren" }, { Cloth = 10 }, { skipped = all })
      for _, key in ipairs({ "Herbs", "Ore", "Cloth" }) do assert.equal("skipped", row(p, key).state, key) end
      assert.same({}, p.mails)
      assert.equal(0, p.stacks)
      assert.equal(0, p.postage)
    end)
  end)
end)
