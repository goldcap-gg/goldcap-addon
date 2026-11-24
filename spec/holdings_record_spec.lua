local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

-- What each character holds, place by place (Core/HoldingsRecord.lua): every item of a place with
-- its count, so an item missing from a full reading is none there. A reading cut short is never
-- full, and a reading replaces its place whole.
describe("the holdings record", function()
  local NOW, DAY = 1800000000, 86400
  local GC, HR, context

  -- An API-shaped double of C_Container: BAGS[bag] = { slots = n, [slot] = { itemID, stackCount } }.
  local BAGS
  local containers = {
    GetContainerNumSlots = function(bag) return BAGS[bag] and BAGS[bag].slots or 0 end,
    GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] or nil end,
  }

  local function stack(itemID, n) return { itemID = itemID, stackCount = n } end

  before_each(function()
    _G.RETRIEVING_DATA = "Retrieving data"
    BAGS = {}
    GC = helper.loadModule("Core/MailClassify.lua")
    helper.loadModule("Core/CraftQueue.lua", GC)
    helper.loadModule("Core/HoldingsRecord.lua", GC)
    HR = GC.HoldingsRecord
    GC.db = {}
    context = { char = "Bob-Argent Dawn", region = "eu" }
    GC.Ledger = { Context = function() return context end }
  end)

  after_each(function()
    _G.RETRIEVING_DATA = nil
    _G.C_Container, _G.Enum, _G.C_Bank, _G.C_Timer = nil, nil, nil, nil
  end)

  local function place(char, name) return GC.db.holdings.chars[char][name] end

  describe("Record", function()
    it("a character without a realm records nothing", function()
      assert.is_false(HR.Record("Bob", "eu", "bags", { [2589] = 3 }, true, NOW))
      assert.is_false(HR.Record("Bob-", "eu", "bags", { [2589] = 3 }, true, NOW))
      assert.is_false(HR.Record("-Argent Dawn", "eu", "bags", { [2589] = 3 }, true, NOW))
      assert.is_nil(GC.db.holdings)
    end)

    it("refuses a region outside us, eu, kr and tw, and a place it does not keep", function()
      assert.is_false(HR.Record("Bob-Argent Dawn", "cn", "bags", {}, true, NOW))
      assert.is_false(HR.Record("Bob-Argent Dawn", nil, "bags", {}, true, NOW))
      assert.is_false(HR.Record("Bob-Argent Dawn", "eu", "void", {}, true, NOW))
      assert.is_nil(GC.db.holdings)
    end)

    it("refuses a reading with a count or an id that is not a whole number of at least 1", function()
      assert.is_false(HR.Record("Bob-Argent Dawn", "eu", "bags", { [2589] = 0 }, true, NOW))
      assert.is_false(HR.Record("Bob-Argent Dawn", "eu", "bags", { [2589] = 1.5 }, true, NOW))
      assert.is_false(HR.Record("Bob-Argent Dawn", "eu", "bags", { [0] = 1 }, true, NOW))
      assert.is_false(HR.Record("Bob-Argent Dawn", "eu", "bags", { name = 1 }, true, NOW))
      assert.is_nil(GC.db.holdings)
    end)

    it("makes the store on the first write", function()
      assert.is_true(HR.Record("Bob-Argent Dawn", "eu", "bags", { [2589] = 3 }, true, NOW))
      assert.equal(1, GC.db.holdings.v)
      assert.same({ at = NOW, full = true, items = { [2589] = 3 } }, place("Bob-Argent Dawn", "bags"))
      assert.equal("eu", GC.db.holdings.chars["Bob-Argent Dawn"].region)
    end)

    it("a reading replaces the place, so an item gone from it is gone", function()
      HR.Record("Bob-Argent Dawn", "eu", "bags", { [2589] = 3, [2592] = 7 }, true, NOW)
      HR.Record("Bob-Argent Dawn", "eu", "bags", { [2592] = 5 }, true, NOW + 60)
      assert.same({ at = NOW + 60, full = true, items = { [2592] = 5 } }, place("Bob-Argent Dawn", "bags"))
    end)

    it("a v = 2 store is left untouched", function()
      local newer = { v = 2, chars = { ["Bob-Argent Dawn"] = { something = "else" } } }
      GC.db.holdings = newer
      assert.is_false(HR.Record("Bob-Argent Dawn", "eu", "bags", { [2589] = 3 }, true, NOW))
      assert.is_false(HR.RecordWarband("eu", { [2589] = 3 }, true, NOW))
      assert.is_false(HR.RecordGuildTab("Gold Hands-Argent Dawn", "eu", 1, { [2589] = 3 }, NOW))
      HR.PendingSend("Alt-Argent Dawn", { [2589] = 3 }, NOW)
      assert.is_false(HR.SendSucceeded(NOW))
      HR.Prune(NOW + 400 * DAY)
      assert.equal(newer, GC.db.holdings)
      assert.same({ v = 2, chars = { ["Bob-Argent Dawn"] = { something = "else" } } }, GC.db.holdings)
    end)
  end)

  describe("Prune", function()
    it("prune keeps 50 characters and drops 91-day-old ones", function()
      HR.Record("Old-Realm", "eu", "bags", { [1] = 1 }, true, NOW - 91 * DAY)
      HR.Record("Ninety-Realm", "eu", "bags", { [1] = 1 }, true, NOW - 90 * DAY)
      HR.Prune(NOW)
      assert.is_nil(GC.db.holdings.chars["Old-Realm"])
      assert.is_not_nil(GC.db.holdings.chars["Ninety-Realm"])

      -- A character's newest place is what counts: a fresh mail reading beside an old bags one.
      HR.Record("Mailer-Realm", "eu", "mail", { [1] = 1 }, true, NOW)
      HR.Record("Mailer-Realm", "eu", "bags", { [1] = 1 }, true, NOW - 200 * DAY)
      for i = 1, 55 do
        HR.Record("Alt" .. i .. "-Realm", "eu", "bags", { [1] = 1 }, true, NOW - 60 * DAY + i)
      end
      HR.Prune(NOW)
      local chars = GC.db.holdings.chars
      local n = 0
      for _ in pairs(chars) do n = n + 1 end
      assert.equal(50, n)
      -- The oldest read go first: the 90-day-old one and the first six alts.
      assert.is_nil(chars["Ninety-Realm"])
      assert.is_nil(chars["Alt6-Realm"])
      assert.is_not_nil(chars["Alt7-Realm"])
      assert.is_not_nil(chars["Mailer-Realm"].bags)
    end)
  end)

  describe("ReadContainers", function()
    it("bags at login with no slots yet are not full", function()
      local items, full = HR.ReadContainers(containers, { 0, 1, 2, 3, 4, 5 })
      assert.same({}, items)
      assert.is_false(full)
    end)

    it("sums every occupied slot by item, and is full when every one names its item", function()
      BAGS[0] = { slots = 3, [1] = stack(2589, 20), [3] = stack(2589, 4) }
      BAGS[1] = { slots = 2, [2] = stack(2592, 1) }
      local items, full = HR.ReadContainers(containers, { 0, 1, 2, 3, 4, 5 })
      assert.same({ [2589] = 24, [2592] = 1 }, items)
      assert.is_true(full)
    end)

    it("a slot with no item id makes the reading not full", function()
      BAGS[0] = { slots = 2, [1] = stack(2589, 20), [2] = { stackCount = 3 } }
      local items, full = HR.ReadContainers(containers, { 0, 1, 2, 3, 4, 5 })
      assert.same({ [2589] = 20 }, items)
      assert.is_false(full)
    end)

    it("a container call that raises makes the reading not full", function()
      BAGS[0] = { slots = 1, [1] = stack(2589, 20) }
      local api = { GetContainerNumSlots = containers.GetContainerNumSlots,
        GetContainerItemInfo = function() error("not yet") end }
      local _, full = HR.ReadContainers(api, { 0 })
      assert.is_false(full)
    end)
  end)

  describe("ReadMail", function()
    local function mail(items, extra)
      local row = { sender = "Alt", subject = "Stuff", items = items or {} }
      for k, v in pairs(extra or {}) do row[k] = v end
      return row
    end

    it("reads every attachment of every mail", function()
      local box = Mailbox.new({
        mail({ [1] = { itemID = 2589, count = 20 }, [16] = { itemID = 2592, count = 2 } }),
        mail({ [3] = { itemID = 2589, count = 5 } }, { cod = 100 }),
        { sender = "Auction House", subject = "Auction successful", money = 500, auction = true,
          invoice = { invoiceType = "seller", itemName = "Linen Cloth" } },
      })
      local items, full = HR.ReadMail(box.api, false)
      assert.same({ [2589] = 25, [2592] = 2 }, items)
      assert.is_true(full)
    end)

    it("an inbox showing 50 of 70 mails is not full", function()
      local shown, hidden = {}, {}
      for i = 1, 50 do shown[i] = mail({ [1] = { itemID = 2589, count = 1 } }) end
      for i = 1, 20 do hidden[i] = mail({ [1] = { itemID = 2589, count = 1 } }) end
      local items, full = HR.ReadMail(Mailbox.new(shown, { hidden = hidden }).api, false)
      assert.same({ [2589] = 50 }, items)
      assert.is_false(full)
    end)

    it("the opening pass's empty inbox is not full, the next pass's is", function()
      local api = Mailbox.new({}).api
      local items, full = HR.ReadMail(api, true)
      assert.same({}, items)
      assert.is_false(full)
      items, full = HR.ReadMail(api, false)
      assert.same({}, items)
      assert.is_true(full)
    end)

    it("a row still loading makes the pass not full", function()
      local box = Mailbox.new({ mail({ [1] = { itemID = 2589, count = 1 } }), mail({}, { subject = "Retrieving data..." }) })
      local _, full = HR.ReadMail(box.api, false)
      assert.is_false(full)

      box = Mailbox.new({ mail({ [1] = { itemID = 2589, count = 1 } }) })
      box.api.GetInboxHeaderInfo = function() end
      _, full = HR.ReadMail(box.api, false)
      assert.is_false(full)
    end)

    it("an attachment the client has not named yet makes the pass not full", function()
      local box = Mailbox.new({ mail({ [1] = { itemID = 2589, count = 1 }, [2] = { itemID = 2592, count = 1 } }) })
      local real = box.api.GetInboxItem
      box.api.GetInboxItem = function(index, slot)
        if slot == 2 then return nil, 2592, "texture", 1 end
        return real(index, slot)
      end
      local items, full = HR.ReadMail(box.api, false)
      assert.same({ [2589] = 1 }, items)
      assert.is_false(full)
    end)
  end)

  describe("the auctions place", function()
    it("auctions sum per item and skip sold lots", function()
      local owned = {
        { itemKey = { itemID = 2589 }, quantity = 20, status = 0 },
        { itemKey = { itemID = 2589 }, quantity = 5, status = 0 },
        { itemKey = { itemID = 2592 }, quantity = 3, status = 1 },
        { itemKey = { itemID = 2594 }, quantity = 1 },
      }
      assert.same({ [2589] = 25, [2594] = 1 }, GC.CraftQueue.SumListed(owned))
      assert.same({}, GC.CraftQueue.SumListed(nil))
    end)

    it("the craft queue's listed counts are the same sum", function()
      GC.CraftQueue.FoldListed("Bob-Argent Dawn", { { itemKey = { itemID = 2589 }, quantity = 20 },
        { itemKey = { itemID = 2592 }, quantity = 3, status = 1 } }, NOW)
      local listed, at = GC.CraftQueue.Listed("Bob-Argent Dawn", NOW)
      assert.same({ [2589] = 20 }, listed)
      assert.equal(NOW, at)
    end)
  end)

  describe("the bank", function()
    local INDEX = { Backpack = 0, Bag_1 = 1, ReagentBag = 5, Keyring = -1, Characterbanktab = -2,
      Accountbanktab = -3, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, AccountBankTab_1 = 12,
      AccountBankTab_2 = 13 }
    local purchased

    before_each(function()
      purchased = { [0] = { 6, 7 }, [2] = { 12, 13 } }
      _G.C_Container = containers
      _G.Enum = { BagIndex = INDEX, BankType = { Character = 0, Account = 2 } }
      _G.C_Bank = { FetchPurchasedBankTabIDs = function(bankType) return purchased[bankType] end }
      BAGS[0] = { slots = 1, [1] = stack(1, 1) }
    end)

    it("lists the bank's containers that report slots, the character's apart from the account's", function()
      BAGS[6] = { slots = 98 }
      BAGS[12] = { slots = 98 }
      BAGS[13] = { slots = 98 }
      local character, account = HR.BankBags()
      assert.same({ 6 }, character)
      assert.same({ 12, 13 }, account)
    end)

    it("the bank read while closed records nothing", function()
      BAGS[6] = { slots = 98, [1] = stack(2589, 20) }
      BAGS[7] = { slots = 98 }
      BAGS[12] = { slots = 98, [1] = stack(2592, 5) }
      HR.OnBags(NOW)
      assert.is_nil(GC.db.holdings.chars["Bob-Argent Dawn"].bank)
      assert.same({}, GC.db.holdings.warband)
      HR.OnBankOpened(NOW)
      HR.OnBankClosed()
      BAGS[6][2] = stack(2589, 1)
      HR.OnBags(NOW + 60)
      assert.same({ at = NOW, full = true, items = { [2589] = 20 } }, place("Bob-Argent Dawn", "bank"))
    end)

    it("reads the bank and the warband bank while open, and on each bag change then", function()
      BAGS[6] = { slots = 98, [1] = stack(2589, 20) }
      BAGS[7] = { slots = 98, [4] = stack(2589, 2) }
      BAGS[12] = { slots = 98, [1] = stack(2592, 5) }
      BAGS[13] = { slots = 98 }
      HR.OnBankOpened(NOW)
      assert.same({ at = NOW, full = true, items = { [2589] = 22 } }, place("Bob-Argent Dawn", "bank"))
      assert.same({ at = NOW, full = true, items = { [2592] = 5 } }, GC.db.holdings.warband.eu)
      BAGS[7][4] = nil
      HR.OnBags(NOW + 30)
      assert.same({ at = NOW + 30, full = true, items = { [2589] = 20 } }, place("Bob-Argent Dawn", "bank"))
    end)

    it("a purchased tab that reports no slots makes the reading not full", function()
      BAGS[6] = { slots = 98, [1] = stack(2589, 20) }
      HR.OnBankOpened(NOW)
      assert.same({ at = NOW, full = false, items = { [2589] = 20 } }, place("Bob-Argent Dawn", "bank"))
    end)

    it("only the account bank open records no bank reading", function()
      BAGS[12] = { slots = 98, [1] = stack(2592, 5) }
      BAGS[13] = { slots = 98 }
      HR.OnBankOpened(NOW)
      assert.is_nil(GC.db.holdings.chars["Bob-Argent Dawn"] and GC.db.holdings.chars["Bob-Argent Dawn"].bank)
      assert.same({ at = NOW, full = true, items = { [2592] = 5 } }, GC.db.holdings.warband.eu)
    end)

    it("a warband tab's change is read once, on the next frame, while the bank is open", function()
      local timers = {}
      _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
      BAGS[6] = { slots = 98 }
      BAGS[7] = { slots = 98 }
      BAGS[12] = { slots = 98 }
      BAGS[13] = { slots = 98 }
      HR.OnBankSlots()
      assert.equal(0, #timers)
      HR.OnBankOpened(NOW)
      BAGS[12][1] = stack(2592, 5)
      HR.OnBankSlots()
      HR.OnBankSlots()
      assert.equal(1, #timers)
      timers[1]()
      assert.same({ [2592] = 5 }, GC.db.holdings.warband.eu.items)
    end)
  end)

  describe("the mailbox, through the scan's api", function()
    it("records what the inbox holds, and the opening pass of an empty inbox changes nothing", function()
      local box = Mailbox.new({ { sender = "Alt", items = { [1] = { itemID = 2589, count = 20 } } } })
      HR.OnInbox(box.api, false, NOW)
      assert.same({ at = NOW, full = true, items = { [2589] = 20 } }, place("Bob-Argent Dawn", "mail"))
      local empty = Mailbox.new({})
      HR.OnInbox(empty.api, true, NOW + 60)
      assert.same({ at = NOW, full = true, items = { [2589] = 20 } }, place("Bob-Argent Dawn", "mail"))
      HR.OnInbox(empty.api, false, NOW + 61)
      assert.same({ at = NOW + 61, full = true, items = {} }, place("Bob-Argent Dawn", "mail"))
    end)
  end)

  describe("the guild bank", function()
    local G = "Gold Hands-Argent Dawn"
    local function guild() return GC.db.holdings.guilds[G] end

    it("a visit loading 3 of 4 viewable tabs is not full", function()
      HR.GuildVisitStart(G)
      for tab = 1, 3 do assert.is_true(HR.RecordGuildTab(G, "eu", tab, { [2589] = tab }, NOW)) end
      assert.is_false(HR.GuildVisitDone(G, { 1, 2, 3, 4 }, NOW))
      assert.is_false(guild().full)
      HR.RecordGuildTab(G, "eu", 4, { [2592] = 1 }, NOW + 5)
      assert.is_true(HR.GuildVisitDone(G, { 1, 2, 3, 4 }, NOW + 5))
      assert.same({ region = "eu", at = NOW + 5, full = true, tabs = {
        { at = NOW, items = { [2589] = 1 } }, { at = NOW, items = { [2589] = 2 } },
        { at = NOW, items = { [2589] = 3 } }, { at = NOW + 5, items = { [2592] = 1 } },
      } }, guild())
    end)

    it("a tab not loaded this visit keeps its items", function()
      HR.GuildVisitStart(G)
      for tab = 1, 4 do HR.RecordGuildTab(G, "eu", tab, { [2589] = tab }, NOW) end
      assert.is_true(HR.GuildVisitDone(G, { 1, 2, 3, 4 }, NOW))
      HR.GuildVisitStart(G)
      for tab = 1, 3 do HR.RecordGuildTab(G, "eu", tab, { [2592] = tab }, NOW + DAY) end
      assert.is_false(HR.GuildVisitDone(G, { 1, 2, 3, 4 }, NOW + DAY))
      assert.same({ at = NOW, items = { [2589] = 4 } }, guild().tabs[4])
      assert.same({ at = NOW + DAY, items = { [2592] = 1 } }, guild().tabs[1])
    end)

    it("a character who can view no tab reads nothing full", function()
      HR.GuildVisitStart(G)
      HR.RecordGuildTab(G, "eu", 1, { [2589] = 1 }, NOW)
      assert.is_false(HR.GuildVisitDone(G, {}, NOW))
      assert.is_false(HR.GuildVisitDone("Nobody-Argent Dawn", {}, NOW))
    end)

    it("refuses a guild without a realm, a bad tab and a bad item list", function()
      assert.is_false(HR.RecordGuildTab("Gold Hands", "eu", 1, { [2589] = 1 }, NOW))
      assert.is_false(HR.RecordGuildTab(G, "cn", 1, { [2589] = 1 }, NOW))
      assert.is_false(HR.RecordGuildTab(G, "eu", 0, { [2589] = 1 }, NOW))
      assert.is_false(HR.RecordGuildTab(G, "eu", 1, { [2589] = 0 }, NOW))
      assert.is_nil(GC.db.holdings)
    end)

    it("keeps 10 guilds, the oldest read going first", function()
      for i = 1, 11 do HR.RecordGuildTab("Guild" .. i .. "-Realm", "eu", 1, { [1] = 1 }, NOW + i) end
      assert.is_nil(GC.db.holdings.guilds["Guild1-Realm"])
      assert.is_not_nil(GC.db.holdings.guilds["Guild2-Realm"])
      assert.is_not_nil(GC.db.holdings.guilds["Guild11-Realm"])
      -- The guild just read is never the one that goes, whatever its clock says.
      HR.RecordGuildTab("Late-Realm", "eu", 1, { [1] = 1 }, NOW - DAY)
      assert.is_not_nil(GC.db.holdings.guilds["Late-Realm"])
      assert.is_nil(GC.db.holdings.guilds["Guild2-Realm"])
    end)

    describe("ReadGuildTab", function()
      -- SLOTS[tab][slot] = { link, count }, as GetGuildBankItemInfo and GetGuildBankItemLink answer.
      local SLOTS
      local api = {
        GetGuildBankItemInfo = function(tab, slot)
          local s = SLOTS[tab] and SLOTS[tab][slot]
          if s then return "texture", s.count, false, false, 1 end
        end,
        GetGuildBankItemLink = function(tab, slot)
          local s = SLOTS[tab] and SLOTS[tab][slot]
          return s and s.link or nil
        end,
      }
      local function link(id) return ("|cffffffff|Hitem:%d::::::::70:::::|h[Item]|h|r"):format(id) end

      before_each(function() SLOTS = {} end)

      it("reads every slot by the item its link names, a caged pet as the cage", function()
        SLOTS[2] = { [1] = { link = link(2589), count = 20 }, [98] = { link = link(2589), count = 5 },
          [40] = { link = "|cff0070dd|Hbattlepet:868:1:3:155:12:12:0x0|h[Pet]|h|r", count = 1 } }
        assert.same({ [2589] = 25, [82800] = 1 }, HR.ReadGuildTab(api, 2))
      end)

      it("a tab showing nothing cannot be told from one not loaded yet, and reads as nil", function()
        assert.is_nil(HR.ReadGuildTab(api, 1))
      end)

      it("an item with no link yet, or a call that raises, makes the tab nil", function()
        SLOTS[1] = { [1] = { link = link(2589), count = 20 }, [2] = { count = 1 } }
        assert.is_nil(HR.ReadGuildTab(api, 1))
        SLOTS[1][2] = nil
        assert.is_nil(HR.ReadGuildTab({ GetGuildBankItemInfo = function() error("no") end,
          GetGuildBankItemLink = api.GetGuildBankItemLink }, 1))
      end)
    end)

    describe("at the guild bank", function()
      local SLOTS, VIEWABLE, queried

      before_each(function()
        SLOTS, VIEWABLE, queried = {}, { true, true, false }, {}
        _G.GetRealmName = function() return "Argent Dawn" end
        _G.GetGuildInfo = function() return "Gold Hands", "Banker", 3, nil end
        _G.GetNumGuildBankTabs = function() return #VIEWABLE end
        _G.GetGuildBankTabInfo = function(tab) return "Tab " .. tab, "icon", VIEWABLE[tab], true, 0, 0 end
        _G.QueryGuildBankTab = function(tab) queried[#queried + 1] = tab end
        _G.GetGuildBankItemInfo = function(tab, slot)
          local n = SLOTS[tab] and SLOTS[tab][slot]
          if n then return "texture", n end
        end
        _G.GetGuildBankItemLink = function(tab, slot)
          return SLOTS[tab] and SLOTS[tab][slot] and ("|Hitem:%d::|h[x]|h"):format(1000 + tab) or nil
        end
      end)

      after_each(function()
        _G.GetRealmName, _G.GetGuildInfo, _G.GetNumGuildBankTabs, _G.GetGuildBankTabInfo = nil, nil, nil, nil
        _G.QueryGuildBankTab, _G.GetGuildBankItemInfo, _G.GetGuildBankItemLink = nil, nil, nil
      end)

      it("queries each viewable tab once a visit, and records the tabs as they load", function()
        HR.OnGuildBankOpened(NOW)
        HR.OnGuildBankOpened(NOW)
        assert.same({ 1, 2 }, queried)
        SLOTS[1] = { [1] = 20 }
        HR.OnGuildBankSlots(NOW + 1)
        assert.same({ 1, 2 }, queried)
        local g = GC.db.holdings.guilds["Gold Hands-Argent Dawn"]
        assert.same({ [1001] = 20 }, g.tabs[1].items)
        assert.is_nil(g.tabs[2])
        assert.is_false(g.full)
        SLOTS[2] = { [7] = 3 }
        HR.OnGuildBankSlots(NOW + 2)
        assert.same({ [1002] = 3 }, g.tabs[2].items)
        assert.is_true(g.full)
        -- The next visit asks again.
        HR.OnGuildBankClosed()
        HR.OnGuildBankOpened(NOW + DAY)
        assert.same({ 1, 2, 1, 2 }, queried)
      end)

      it("keys the guild by its own realm when it is not the character's", function()
        _G.GetGuildInfo = function() return "Gold Hands", "Banker", 3, "Silvermoon" end
        SLOTS[1] = { [1] = 20 }
        HR.OnGuildBankSlots(NOW)
        assert.is_not_nil(GC.db.holdings.guilds["Gold Hands-Silvermoon"])
      end)

      it("a character in no guild records nothing", function()
        _G.GetGuildInfo = function() return nil end
        SLOTS[1] = { [1] = 20 }
        HR.OnGuildBankOpened(NOW)
        HR.OnGuildBankSlots(NOW)
        assert.same({}, queried)
        assert.is_nil(GC.db.holdings)
      end)
    end)
  end)

  describe("mail sends", function()
    local function sends() return GC.db.holdings and GC.db.holdings.sends or {} end

    it("a send is recorded only after MAIL_SEND_SUCCESS", function()
      assert.is_true(HR.PendingSend("Alt-Argent Dawn", { [2589] = 20, [2592] = 1 }, NOW))
      assert.same({}, sends())
      assert.is_true(HR.SendSucceeded(NOW + 2))
      assert.same({ { from = "Bob-Argent Dawn", to = "Alt-Argent Dawn", region = "eu", at = NOW + 2,
        items = { [2589] = 20, [2592] = 1 } } }, sends())
      -- Nothing waits any more: a second answer records nothing.
      assert.is_false(HR.SendSucceeded(NOW + 3))
      assert.equal(1, #sends())
    end)

    it("MAIL_FAILED drops the pending send", function()
      HR.PendingSend("Alt-Argent Dawn", { [2589] = 20 }, NOW)
      HR.SendDropped()
      assert.is_false(HR.SendSucceeded(NOW + 2))
      assert.same({}, sends())
    end)

    it('"Bob" sent from Argent Dawn is recorded as "Bob-Argent Dawn"', function()
      context.char = "Me-Argent Dawn"
      HR.PendingSend(" Bob ", { [2589] = 1 }, NOW)
      HR.SendSucceeded(NOW)
      HR.PendingSend("Bob-ArgentDawn", { [2589] = 1 }, NOW)
      HR.SendSucceeded(NOW + 1)
      assert.equal("Bob-Argent Dawn", sends()[1].to)
      assert.equal("Bob-ArgentDawn", sends()[2].to)
    end)

    it("a send with no item, to no one, or from a character without a realm records nothing", function()
      assert.is_false(HR.PendingSend("Alt-Argent Dawn", {}, NOW))
      assert.is_false(HR.PendingSend("  ", { [2589] = 1 }, NOW))
      assert.is_false(HR.PendingSend(nil, { [2589] = 1 }, NOW))
      context.char = "Me"
      assert.is_false(HR.PendingSend("Bob", { [2589] = 1 }, NOW))
      assert.is_false(HR.SendSucceeded(NOW))
      assert.is_nil(GC.db.holdings)
    end)

    it("a new send replaces the one still waiting", function()
      HR.PendingSend("Alt-Argent Dawn", { [2589] = 20 }, NOW)
      HR.PendingSend("Other-Argent Dawn", { [2592] = 1 }, NOW)
      HR.SendSucceeded(NOW + 1)
      assert.equal(1, #sends())
      assert.equal("Other-Argent Dawn", sends()[1].to)
    end)

    it("sends keep 300 and drop 91-day-old ones", function()
      HR.PendingSend("Old-Argent Dawn", { [1] = 1 }, NOW - 91 * DAY)
      HR.SendSucceeded(NOW - 91 * DAY)
      HR.PendingSend("Ninety-Argent Dawn", { [1] = 1 }, NOW - 90 * DAY)
      HR.SendSucceeded(NOW - 90 * DAY)
      HR.Prune(NOW)
      assert.equal(1, #sends())
      assert.equal("Ninety-Argent Dawn", sends()[1].to)
      for i = 1, 305 do
        HR.PendingSend("Alt" .. i .. "-Argent Dawn", { [1] = 1 }, NOW + i)
        HR.SendSucceeded(NOW + i)
      end
      assert.equal(300, #sends())
      assert.equal("Alt6-Argent Dawn", sends()[1].to)
      assert.equal("Alt305-Argent Dawn", sends()[300].to)
    end)
  end)
end)

-- The events that reach the record, through the real Core/Init.lua of each game's TOC.
for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
  describe("the holdings record, wired in " .. toc, function()
    local GC, onEvent, OWNED, fullOwned, sendHook

    local function stubFrame()
      local f
      f = {
        RegisterEvent = function() end, UnregisterEvent = function() end,
        SetScript = function(_, which, fn) if which == "OnEvent" then onEvent = fn end end,
        SetSize = function() end, SetPoint = function() end, SetMovable = function() end,
        EnableMouse = function() end, RegisterForDrag = function() end,
        Show = function() end, Hide = function() end, IsShown = function() return false end,
        SetText = function() end, SetTexture = function() end, SetTextColor = function() end,
        SetJustifyH = function() end, SetWidth = function() end, SetScrollChild = function() end,
        StartMoving = function() end, StopMovingOrSizing = function() end,
        CreateFontString = function() return stubFrame() end,
        CreateTexture = function() return stubFrame() end,
        TitleText = { SetText = function() end },
        EnableMouseWheel = function() end, SetVerticalScroll = function() end,
        GetVerticalScroll = function() return 0 end, GetVerticalScrollRange = function() return 0 end,
        SetWordWrap = function() end, SetMaxLines = function() end,
        Enable = function() end, Disable = function() end,
        GetFontString = function() return nil end,
        SetResizable = function() end, SetResizeBounds = function() end,
        StartSizing = function() end, ClearAllPoints = function() end,
        GetPoint = function() return nil end, GetHeight = function() return 0 end,
        GetFrameLevel = function() return 1 end, SetFrameLevel = function() end,
        SetColorTexture = function() end, SetAllPoints = function() end,
        SetFont = function() return true end,
        SetHeight = function() end,
      }
      return f
    end

    local BAGS = {}

    before_each(function()
      onEvent = nil
      for k in pairs(BAGS) do BAGS[k] = nil end
      OWNED, fullOwned = {}, true
      _G.CreateFrame = function() return stubFrame() end
      _G.UISpecialFrames = {}
      _G.SlashCmdList = {}
      _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
      _G.GoldCapDB = nil
      _G.GetTime = function() return 0 end
      _G.time = function() return 5000 end
      _G.UnitName = function() return "Aiyana" end
      _G.GetRealmName = function() return "Dentarg" end
      _G.GetCVar = function(k) if k == "portal" then return "eu" end end
      _G.RETRIEVING_DATA = "Retrieving data"
      _G.C_Timer = { After = function() end }
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return BAGS[bag] and BAGS[bag].slots or 0 end,
        GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] or nil end,
      }
      _G.C_AuctionHouse = {
        GetOwnedAuctions = function() return OWNED end,
        QueryOwnedAuctions = function() end,
        GetItemKeyInfo = function() return { isCommodity = true } end,
        HasFullOwnedAuctionResults = function() return fullOwned end,
      }
      -- The post-hook GoldCap puts on SendMail at ADDON_LOADED, kept so a spec can play the send.
      sendHook = nil
      _G.SendMail = function() end
      _G.hooksecurefunc = function(name, fn) if name == "SendMail" then sendHook = fn end end

      GC = {}
      local f = assert(io.open(toc, "r"))
      local files = {}
      for rawLine in f:lines() do
        local line = rawLine:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then files[#files + 1] = line end
      end
      f:close()
      for _, rel in ipairs(files) do
        local chunk = assert(loadfile("GoldCap/" .. rel:gsub("\\", "/")))
        chunk("GoldCap", GC)
      end
      onEvent(nil, "ADDON_LOADED", "GoldCap")
    end)

    after_each(function()
      _G.CreateFrame, _G.UISpecialFrames, _G.SlashCmdList = nil, nil, nil
      _G.C_AddOns, _G.GoldCapDB, _G.GoldCap_MarketData = nil, nil, nil
      _G.SLASH_GOLDCAP1 = nil
      _G.GetTime, _G.UnitName, _G.GetRealmName, _G.GetCVar = nil, nil, nil, nil
      _G.C_Container, _G.C_AuctionHouse, _G.RETRIEVING_DATA, _G.C_Timer = nil, nil, nil, nil
      _G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxInvoiceInfo, _G.GetInboxItem = nil, nil, nil, nil
      _G.SendMail, _G.hooksecurefunc, _G.GetSendMailItem, _G.Enum = nil, nil, nil, nil
      _G.GetGuildInfo, _G.GetNumGuildBankTabs, _G.GetGuildBankTabInfo = nil, nil, nil
      _G.QueryGuildBankTab, _G.GetGuildBankItemInfo, _G.GetGuildBankItemLink = nil, nil, nil
      _G.time = os.time
    end)

    local function chars() return _G.GoldCapDB.holdings and _G.GoldCapDB.holdings.chars or {} end

    it("reads the bags at the loading screen and on every bag change", function()
      BAGS[0] = { slots = 16, [1] = { itemID = 2589, stackCount = 20 } }
      onEvent(nil, "PLAYER_ENTERING_WORLD")
      assert.same({ [2589] = 20 }, chars()["Aiyana-Dentarg"].bags.items)
      BAGS[0][2] = { itemID = 2592, stackCount = 1 }
      onEvent(nil, "BAG_UPDATE_DELAYED")
      assert.same({ [2589] = 20, [2592] = 1 }, chars()["Aiyana-Dentarg"].bags.items)
      assert.is_true(chars()["Aiyana-Dentarg"].bags.full)
      assert.equal("eu", chars()["Aiyana-Dentarg"].region)
    end)

    it("reads the mailbox on the scan's passes", function()
      local box = Mailbox.new({ { sender = "Alt", items = { [1] = { itemID = 2589, count = 20 } } } })
      for name, fn in pairs(box.api) do _G[name] = fn end
      onEvent(nil, "MAIL_SHOW")
      onEvent(nil, "MAIL_INBOX_UPDATE")
      assert.same({ at = 5000, full = true, items = { [2589] = 20 } }, chars()["Aiyana-Dentarg"].mail)
    end)

    it("records the auctions from an answered read only, and only a whole one", function()
      OWNED = { { auctionID = 1, itemKey = { itemID = 2589 }, quantity = 20, status = 0, timeLeftSeconds = 3600 },
        { auctionID = 2, itemKey = { itemID = 2592 }, quantity = 3, status = 1, timeLeftSeconds = 3600 } }
      onEvent(nil, "AUCTION_CANCELED", 99)
      assert.is_nil(chars()["Aiyana-Dentarg"] and chars()["Aiyana-Dentarg"].auctions)
      fullOwned = false
      onEvent(nil, "OWNED_AUCTIONS_UPDATED")
      assert.is_nil(chars()["Aiyana-Dentarg"] and chars()["Aiyana-Dentarg"].auctions)
      fullOwned = true
      onEvent(nil, "OWNED_AUCTIONS_UPDATED")
      assert.same({ at = 5000, full = true, items = { [2589] = 20 } }, chars()["Aiyana-Dentarg"].auctions)
    end)

    it("records a mail sent once the server says it went, and drops it when it fails or the mailbox closes", function()
      assert.is_function(sendHook)
      _G.GetSendMailItem = function(slot)
        if slot == 1 then return "Linen Cloth", 2589, "texture", 20, 1 end
        if slot == 12 then return "Linen Cloth", 2589, "texture", 4, 1 end
      end
      sendHook("Alt")
      assert.is_nil(_G.GoldCapDB.holdings and _G.GoldCapDB.holdings.sends[1])
      onEvent(nil, "MAIL_SEND_SUCCESS")
      assert.same({ { from = "Aiyana-Dentarg", to = "Alt-Dentarg", region = "eu", at = 5000,
        items = { [2589] = 24 } } }, _G.GoldCapDB.holdings.sends)
      sendHook("Alt")
      onEvent(nil, "MAIL_FAILED")
      onEvent(nil, "MAIL_SEND_SUCCESS")
      sendHook("Alt")
      onEvent(nil, "MAIL_CLOSED")
      onEvent(nil, "MAIL_SEND_SUCCESS")
      assert.equal(1, #_G.GoldCapDB.holdings.sends)
    end)

    it("reads the guild bank from either open, querying each viewable tab once", function()
      local queried = {}
      _G.Enum = { PlayerInteractionType = { Auctioneer = 21, Merchant = 5, GuildBanker = 10 } }
      _G.GetGuildInfo = function() return "Gold Hands" end
      _G.GetNumGuildBankTabs = function() return 2 end
      _G.GetGuildBankTabInfo = function() return "Tab", "icon", true end
      _G.QueryGuildBankTab = function(tab) queried[#queried + 1] = tab end
      _G.GetGuildBankItemInfo = function(tab, slot) if slot == 1 then return "texture", tab * 10 end end
      _G.GetGuildBankItemLink = function(tab, slot) if slot == 1 then return "|Hitem:" .. (500 + tab) .. "::|h[x]|h" end end
      onEvent(nil, "GUILDBANKFRAME_OPENED")
      onEvent(nil, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
      assert.same({ 1, 2 }, queried)
      onEvent(nil, "GUILDBANKBAGSLOTS_CHANGED")
      local g = _G.GoldCapDB.holdings.guilds["Gold Hands-Dentarg"]
      assert.same({ [501] = 10 }, g.tabs[1].items)
      assert.same({ [502] = 20 }, g.tabs[2].items)
      assert.is_true(g.full)
      onEvent(nil, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
      onEvent(nil, "GUILDBANKFRAME_CLOSED")
      onEvent(nil, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
      assert.same({ 1, 2, 1, 2 }, queried)
    end)
  end)
end
