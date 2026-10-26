local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local Post = require("spec.support.mail_send")

-- UI/MailAltsFrame.lua: Send to alts, the window beside Blizzard's mail frame (retail only). The
-- real Theme and kit, the real group rules (from a Companion file), the real planner
-- (Core/MailGroups.lua over Core/BankGroups.lua), the real characters (Core/Alts.lua), the real press
-- machine (Core/MailPress.lua) and the real bag reader (UI/BankRoute.lua); the bags, the Send Mail
-- tab, the cursor and the mailbox frames are spec/support/mail_send.lua's, shaped as the client's.
describe("Send to alts window", function()
  local GC, MA, post, timers, asked, closedFor, menu, restore, saved, now
  local KEYS = { "Enum", "UIParent", "ItemLocation", "C_Container", "C_Item", "C_Timer", "hooksecurefunc", "GoldCap_AppRuns",
    "SpellIsTargeting", "GetCursorInfo", "ClearCursor", "CreateColor", "GameTooltip", "ClickSendMailItemButton",
    "HasSendMailItem", "SetSendMailCOD", "SetSendMailMoney", "SendMail", "MailFrame", "SendMailFrame",
    "SendMailNameEditBox", "MailFrameTab_OnClick", "GetAutoCompleteRealms", "UnitName", "GetNormalizedRealmName",
    "UnitClass", "UnitLevel", "UnitFactionGroup", "GetClassAtlas", "GetClassColor", "MenuUtil", "OpenMailFrame" }

  -- Herbs: Bloom (1, 2); Ore: Bismuth (3); Potions: Tonic (5); Cloth: Weavercloth (4), never in the
  -- bags here. Item 9 is in no followed group.
  local FILE = {
    v = 3, generatedAt = 1, runs = {}, groups = { "G" },
    caps = {
      { i = 1, c = 700, u = 1000, r = 1, k = true }, { i = 2, c = 700, u = 1000, r = 1, k = true },
      { i = 3, c = 700, u = 1000, r = 2, k = true }, { i = 5, c = 700, u = 1000, r = 3, k = true },
      { i = 4, c = 700, u = 1000, r = 4, k = true },
    },
    rules = { { n = "Herbs", p = "gather", d = 24, fp = 80 }, { n = "Ore", p = "gather", d = 24, fp = 80 },
      { n = "Potions", p = "craft", d = 24, fp = 80 }, { n = "Cloth", p = "craft", d = 24, fp = 80 } },
  }
  local NAMES = { [1] = "Bloom", [2] = "Bloom", [3] = "Bismuth", [4] = "Weavercloth", [5] = "Tonic", [9] = "Linen Cloth" }
  local DAY = 86400

  local function info(itemID, count, over)
    local i = { itemID = itemID, itemName = NAMES[itemID], stackCount = count, iconFileID = 5000 + itemID,
      hyperlink = "item:" .. itemID, isBound = false, isLocked = false }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  local function textOf(fs) return helper.plain(W.state(fs).text or "") end
  local function shown(widget) return widget ~= nil and widget:IsShown() end
  local function press(button) W.state(button).scripts.OnClick(button) end
  local function at(widget) return W.state(widget).points[1] end
  local function windowUp() return MA._frame ~= nil and MA._frame:IsShown() end
  local function top() return MA._frame.top end
  local function event(name) MA.OnEvent(name) end

  local function rowOf(key)
    for _, r in ipairs(MA._rows) do
      if r:IsShown() and r.data and r.data.key == key then return r end
    end
  end
  local function rowKeys()
    local out = {}
    for _, r in ipairs(MA._rows) do if r:IsShown() then out[#out + 1] = r.data.key end end
    return out
  end

  -- The timers armed so far for `seconds`, first armed first; then the frame after them, where the
  -- window paints. Answers how many ran.
  local function fire(seconds)
    local n = 0
    for i = 1, #timers do
      local t = timers[i]
      if t and not t.done and t.seconds == seconds then
        t.done = true
        t.fn()
        n = n + 1
      end
    end
    return n
  end
  local function nextFrame() fire(0) end

  -- The calls whose names `keep` lists, in order, from the post's log.
  local function sequence(keep)
    local want, out = {}, {}
    for _, name in ipairs(keep) do want[name] = true end
    for _, call in ipairs(post:calls()) do
      if want[call.name] then
        local args = {}
        for i = 1, call.n do args[i] = call[i] end
        out[#out + 1] = { call.name, unpack(args) }
      end
    end
    return out
  end

  -- MenuUtil as far as the window uses it: titles, buttons and a divider, kept in order.
  local function entry(text, fn)
    local e = { text = text, fn = fn, children = {} }
    function e:CreateButton(t, f)
      local child = entry(t, f)
      self.children[#self.children + 1] = child
      return child
    end
    function e:CreateTitle(t) self.children[#self.children + 1] = { title = t, children = {} } end
    function e:CreateDivider() self.children[#self.children + 1] = { divider = true, children = {} } end
    return e
  end
  local function openMenu(row)
    menu = nil
    _G.MenuUtil = { CreateContextMenu = function(owner, generator)
      menu = entry("root")
      menu.owner = owner
      generator(owner, menu)
    end }
    press(row.to)
    return menu
  end
  -- A menu line as the player reads it: no colour, and no class icon (an |A..|a escape) before it.
  local function plainLine(text) return (helper.plain(text):gsub("^|A.-|a%s*", "")) end
  local function menuTexts(m)
    local out = {}
    for _, child in ipairs(m.children) do
      if child.title then out[#out + 1] = "title: " .. plainLine(child.title)
      elseif child.text then out[#out + 1] = plainLine(child.text) end
    end
    return out
  end
  local function choose(m, startsWith)
    for _, child in ipairs(m.children) do
      if child.text and plainLine(child.text):find(startsWith, 1, true) == 1 then return child.fn() end
    end
    error("no menu entry " .. startsWith)
  end

  local function record(name, realm, class, faction, seen)
    GC.Alts.Record(GC.db, { name = name, realm = realm, class = class, level = 80, faction = faction }, seen)
  end
  local function sendTo(key, full) GC.MailGroups.SetRecipient(GC.db, "Tarren", key, full) end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    timers, asked, closedFor = {}, nil, {}
    now = os.time()
    post = Post.new({
      bags = {
        [0] = { info(1, 200), info(1, 20), info(9, 20), info(5, 20) },
        [1] = {}, [2] = {}, [3] = {}, [4] = {},
        [5] = { info(3, 50) },
      },
      sizes = { [0] = 20, [5] = 36 },
      realms = { "Kazzak" },
    })
    local api = post.api
    _G.C_Container = { GetContainerNumSlots = api.GetContainerNumSlots, GetContainerItemInfo = api.GetContainerItemInfo,
      PickupContainerItem = api.PickupContainerItem }
    for _, name in ipairs({ "ClickSendMailItemButton", "HasSendMailItem", "SetSendMailCOD", "SetSendMailMoney", "SendMail",
      "GetCursorInfo", "ClearCursor", "MailFrameTab_OnClick", "GetAutoCompleteRealms", "MailFrame", "SendMailFrame",
      "SendMailNameEditBox" }) do
      _G[name] = api[name]
    end
    _G.SpellIsTargeting = function() return false end
    _G.Enum = { BankType = { Character = 0, Account = 2 } }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.UIParent = W.CreateFrame("Frame")
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function() return false end,
      CanBeRefunded = function() return false end,
      GetCurrentItemLevel = function() return 0 end,
    }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.hooksecurefunc = nil
    -- This character, as the client tells it (Core/Alts.lua reads the same).
    _G.UnitName = function() return "Me" end
    _G.GetNormalizedRealmName = function() return "Tarren" end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitLevel = function() return 80 end
    _G.UnitFactionGroup = function() return "Alliance" end
    -- Blizzard_SharedXML's own helpers (SharedConstants.lua, ColorUtil.lua).
    _G.GetClassAtlas = function(class) return ("classicon-%s"):format(class) end
    _G.GetClassColor = function(class)
      if class == "MAGE" then return 0.25, 0.78, 0.92, "ff3fc7eb" end
      return 1, 1, 1, "ffffffff"
    end
    _G.GameTooltip = {
      lines = {},
      SetOwner = function(self, owner) self.owner, self.lines = owner, {} end,
      ClearAllPoints = function() end,
      SetPoint = function() end,
      AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
      Show = function() end,
      Hide = function(self) self.owner = nil end,
      IsOwned = function(self, owner) return self.owner == owner end,
    }
    _G.GoldCap_AppRuns = FILE
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/NameMatch.lua", GC)
    helper.loadModule("Core/GroupRules.lua", GC)
    helper.loadModule("Core/CraftQueue.lua", GC)
    helper.loadModule("Core/BankGroups.lua", GC)
    helper.loadModule("Core/Hoard.lua", GC)
    helper.loadModule("Core/VendorPress.lua", GC)
    helper.loadModule("Core/Alts.lua", GC)
    helper.loadModule("Core/MailGroups.lua", GC)
    helper.loadModule("Core/MailPress.lua", GC)
    GC.GroupRules.Adopt()
    GC.Data = { GetItemValue = function() return nil end }
    GC.db = {}
    GC.BuyCapEditor = {
      Open = function(anchor, opts) asked = { anchor = anchor, opts = opts } end,
      CloseFor = function(anchor) closedFor[anchor] = true end,
    }
    helper.loadModule("UI/BankRoute.lua", GC)
    helper.loadModule("UI/HoardFrame.lua", GC)
    helper.loadModule("UI/HoardRow.lua", GC)
    helper.loadModule("UI/HoardList.lua", GC)
    helper.loadModule("UI/MailAltsFrame.lua", GC)
    MA = GC.MailAlts
    -- The account's characters: two alts here, one on a connected realm, one on a realm this one
    -- cannot mail, and one of the other faction.
    record("Me", "Tarren", "WARRIOR", "Alliance", now)
    record("Mirelle", "Tarren", "MAGE", "Alliance", now - 3600)
    record("Thornwick", "Tarren", "PRIEST", "Alliance", now - 2 * DAY - 60)
    record("Kaz", "Kazzak", "ROGUE", "Alliance", now - DAY - 60)
    record("Far", "Silvermoon", "MAGE", "Alliance", now)
    record("Orcy", "Tarren", "SHAMAN", "Horde", now)
    sendTo("Herbs", "Mirelle-Tarren")
    sendTo("Ore", "Mirelle-Tarren")
    sendTo("Potions", "Thornwick-Tarren")
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Where it stands and when
  -- ---------------------------------------------------------------------------------------------

  it("listens to the mailbox, the server's answers and the bags", function()
    local events = W.state(MA._events).events
    for _, name in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED" }) do
      assert.is_true(events[name], name)
    end
  end)

  it("stands beside the mail frame on MAIL_SHOW and goes on MAIL_CLOSED", function()
    event("MAIL_SHOW")
    assert.is_true(windowUp())
    local point = at(MA._frame)
    assert.equal("TOPLEFT", point[1])
    assert.equal(_G.MailFrame, point[2])
    assert.equal("TOPRIGHT", point[3])
    assert.equal(_G.UIParent, MA._frame:GetParent())
    assert.equal("GoldCap", textOf(MA._frame.brand))
    assert.equal("Send to alts", textOf(MA._frame.title))
    assert.same({ "Herbs", "Ore", "Potions" }, rowKeys())
    event("MAIL_CLOSED")
    assert.is_false(windowUp())
  end)

  -- Blizzard's open letter (OpenMailFrame, a UIChildWindow at the inbox's right edge) opens where
  -- the window stands: while it shows, the window and its handle stand past it.
  it("steps past an open letter while it shows, and back beside the mail frame when it closes", function()
    local letter = W.CreateFrame("Frame")
    letter:Hide()
    _G.OpenMailFrame = letter
    event("MAIL_SHOW")
    assert.equal(_G.MailFrame, at(MA._frame)[2])
    letter:Show()
    W.state(letter).hooks.OnShow(letter)
    local point = at(MA._frame)
    assert.same({ "TOPLEFT", letter, "TOPRIGHT" }, { point[1], point[2], point[3] })
    letter:Hide()
    W.state(letter).hooks.OnHide(letter)
    point = at(MA._frame)
    assert.same({ "TOPLEFT", _G.MailFrame, "TOPRIGHT" }, { point[1], point[2], point[3] })
    letter:Show()
    W.state(letter).hooks.OnShow(letter)
    press(MA._frame.close)
    assert.equal(letter, at(MA._handle)[2])
    letter:Hide()
    W.state(letter).hooks.OnHide(letter)
    assert.equal(_G.MailFrame, at(MA._handle)[2])
  end)

  it("remembers this character as the mailbox opens", function()
    GC.db.alts = nil
    event("MAIL_SHOW")
    assert.is_true(GC.Alts.IsMine(GC.db, "Me-Tarren"))
  end)

  it("says how many mails go to whom, the stacks and the postage, with Send all", function()
    event("MAIL_SHOW")
    assert.equal("2 mails to 2 of your characters", textOf(top().title))
    assert.equal("Herbs and Ore to Mirelle in one mail, Potions to Thornwick. 4 stacks.", textOf(top().line))
    assert.equal("POSTAGE", textOf(top().postageLabel))
    assert.equal(GC.Util.Money(4 * GC.MailGroups.POSTAGE), W.state(top().postage).text)
    assert.is_true(shown(top().send))
    assert.equal("Send all", top().send.label)
    assert.equal("YOUR GROUPS IN YOUR BAGS", textOf(MA._frame.section))
    assert.is_true(shown(MA._frame.footer))
  end)

  it("closes with its X, remembered, and its handle beside the mail frame opens it again", function()
    event("MAIL_SHOW")
    press(MA._frame.close)
    assert.is_false(windowUp())
    assert.same({ v = 1, closed = true }, GC.db.mailAlts)
    assert.is_true(shown(MA._handle))
    assert.equal("Send to alts", textOf(MA._handle.text))
    assert.equal(_G.MailFrame, at(MA._handle)[2])
    event("MAIL_CLOSED")
    assert.is_false(shown(MA._handle))
    event("MAIL_SHOW")
    assert.is_false(windowUp())
    assert.is_true(shown(MA._handle))
    press(MA._handle)
    assert.is_true(windowUp())
    assert.is_false(shown(MA._handle))
    assert.is_nil(GC.db.mailAlts.closed)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Rows
  -- ---------------------------------------------------------------------------------------------

  it("shows each group with its play, its keep count, who sells it, its items and its Send", function()
    event("MAIL_SHOW")
    local herbs = rowOf("Herbs")
    assert.equal("Herbs", textOf(herbs.name))
    assert.equal("GATHER", textOf(herbs.chip.text))
    assert.equal("Keep 0", herbs.keep.label)
    assert.equal("Mirelle", textOf(herbs.to.text))
    assert.equal("classicon-MAGE", W.state(herbs.to.icon).atlas)
    assert.equal("2 stacks", textOf(herbs.line))
    assert.is_true(shown(herbs.send))
    assert.equal("Send", herbs.send.label)
    assert.equal(5001, W.state(herbs.icons[1].icon).file)
    assert.equal("220", W.state(herbs.icons[1].count).text)
    assert.equal("1 stack", textOf(rowOf("Ore").line))
  end)

  it("gives a group this character sells no Send, and says why", function()
    sendTo("Potions", "Me-Tarren")
    event("MAIL_SHOW")
    local potions = rowOf("Potions")
    assert.is_false(shown(potions.send))
    assert.equal("This character", textOf(potions.to.text))
    assert.equal("This character sells them, so they stay.", textOf(potions.line))
    assert.equal(0.6, potions:GetAlpha())
    assert.equal("1 mail to 1 of your characters", textOf(top().title))
  end)

  it("asks who sells a group with no one chosen, and sends nothing of it", function()
    sendTo("Potions", nil)
    event("MAIL_SHOW")
    local potions = rowOf("Potions")
    assert.is_false(shown(potions.send))
    assert.equal("Who sells it?", textOf(potions.to.text))
    assert.equal("Choose who it goes to, once. GoldCap remembers.", textOf(potions.line))
    assert.equal("Herbs and Ore to Mirelle in one mail. 3 stacks.", textOf(top().line))
  end)

  it("keeps a bound stack in the bags, dimmed with a lock that says why", function()
    post.bags[5][1].isBound = true
    event("MAIL_SHOW")
    local ore = rowOf("Ore")
    assert.is_false(shown(ore.send))
    assert.equal("Nothing to send beyond what it keeps.", textOf(ore.line))
    local slot = ore.icons[1]
    assert.is_true(shown(slot.lock))
    assert.is_true(shown(slot.shade))
    W.state(slot.hit).scripts.OnEnter(slot.hit)
    assert.equal("Bound to you: a mail cannot take it.", helper.plain(_G.GameTooltip.lines[#_G.GameTooltip.lines]))
  end)

  it("asks the Hoard's keep count from Keep, and sends only what is over it", function()
    event("MAIL_SHOW")
    press(rowOf("Herbs").keep)
    assert.equal(rowOf("Herbs").keep, asked.anchor)
    assert.equal("How many of each item in Herbs to keep in your bags?", asked.opts.title)
    asked.opts.onCommit(20)
    assert.equal(20, GC.BankGroups.KeepFor(GC.db, "Herbs"))
    assert.equal("Keep 20", rowOf("Herbs").keep.label)
    assert.equal("1 stack", textOf(rowOf("Herbs").line))
  end)

  it("says there is nothing to send with no followed group, and with everything kept", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    event("MAIL_SHOW")
    assert.is_true(windowUp())
    assert.equal("Nothing to send now", textOf(top().title))
    assert.equal("Follow groups on goldcap.gg to send them to your alts here.", textOf(top().line))
    assert.is_false(shown(top().send))
    assert.is_false(shown(MA._frame.section))
    assert.same({}, rowKeys())
    event("MAIL_CLOSED")

    _G.GoldCap_AppRuns = FILE
    GC.GroupRules.Adopt()
    for _, key in ipairs({ "Herbs", "Ore", "Potions" }) do GC.BankGroups.SetKeep(GC.db, key, 9999) end
    event("MAIL_SHOW")
    assert.equal("Nothing to send now", textOf(top().title))
    assert.equal("Your groups have nothing in your bags beyond what they keep.", textOf(top().line))
    assert.is_false(shown(top().send))
  end)

  it("paints again on the frame after the bags change", function()
    event("MAIL_SHOW")
    post.bags[0][4] = false
    event("BAG_UPDATE_DELAYED")
    assert.equal("2 mails to 2 of your characters", textOf(top().title))
    nextFrame()
    assert.equal("1 mail to 1 of your characters", textOf(top().title))
    assert.same({ "Herbs", "Ore" }, rowKeys())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The press
  -- ---------------------------------------------------------------------------------------------

  it("attaches and sends the first mail inside the click, gold set to none before SendMail", function()
    _G.SendMailFrame:Show()
    event("MAIL_SHOW")
    press(top().send)
    assert.same({
      { "PickupContainerItem", 0, 1 }, { "ClickSendMailItemButton" },
      { "PickupContainerItem", 0, 2 }, { "ClickSendMailItemButton" },
      { "PickupContainerItem", 5, 1 }, { "ClickSendMailItemButton" },
      { "SetSendMailCOD", 0 }, { "SetSendMailMoney", 0 }, { "SendMail", "Mirelle", "GoldCap: Herbs, Ore", "" },
    }, sequence({ "PickupContainerItem", "ClickSendMailItemButton", "SetSendMailCOD", "SetSendMailMoney", "SendMail" }))
    assert.same({ "0:1", "0:2", "5:1" }, post:pending().items)
    assert.equal(0, #post:calls("MailFrameTab_OnClick"))
  end)

  it("sends the second mail only after MAIL_SEND_SUCCESS and the press machine's step", function()
    event("MAIL_SHOW")
    press(top().send)
    assert.equal(1, #post:calls("SendMail"))
    post:succeed()
    fire(GC.MailPress.STEP)
    assert.equal(1, #post:calls("SendMail"))
    event("MAIL_SEND_SUCCESS")
    assert.equal(1, #post:calls("SendMail"))
    fire(GC.MailPress.STEP)
    local sends = post:calls("SendMail")
    assert.equal(2, #sends)
    assert.same({ "Thornwick", "GoldCap: Potions", "" }, { sends[2][1], sends[2][2], sends[2][3] })
    assert.equal(0, post:pending().cod)
    assert.equal(0, post:pending().money)
  end)

  it("opens the Send Mail tab inside the click, before the first attach, when the inbox shows", function()
    event("MAIL_SHOW")
    assert.is_false(_G.SendMailFrame:IsShown())
    press(top().send)
    local names = post:names()
    assert.equal("MailFrameTab_OnClick", names[1])
    assert.same({ nil, 2 }, { post:calls("MailFrameTab_OnClick")[1][1], post:calls("MailFrameTab_OnClick")[1][2] })
    assert.equal("PickupContainerItem", names[2])
  end)

  it("shows the run: Sending, Next and Sent on the rows, the mail in flight and Stop on top", function()
    event("MAIL_SHOW")
    press(top().send)
    assert.equal("Sending 2 mails", textOf(top().title))
    assert.equal("Sending Herbs and Ore to Mirelle now.", textOf(top().line))
    assert.equal("Mail 1 of 2: Herbs and Ore to Mirelle", textOf(top().cast.label))
    assert.equal("0 sent", textOf(top().cast.count))
    assert.equal("Stop", top().send.label)
    assert.equal("Sending", textOf(rowOf("Herbs").status))
    assert.equal("Sending", textOf(rowOf("Ore").status))
    assert.equal("Next", textOf(rowOf("Potions").status))
    assert.is_false(shown(rowOf("Herbs").send))

    post:succeed()
    event("MAIL_SEND_SUCCESS")
    assert.equal("Sent", textOf(rowOf("Herbs").status))
    assert.equal("1 sent", textOf(top().cast.count))
    fire(GC.MailPress.STEP)
    assert.equal("Mail 2 of 2: Potions to Thornwick", textOf(top().cast.label))
    assert.equal("Herbs and Ore went to Mirelle in one mail. Sending Potions to Thornwick now.", textOf(top().line))

    -- The bags change while it goes: what it shows stays as it was pressed.
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ "Herbs", "Ore", "Potions" }, rowKeys())

    post:succeed()
    event("MAIL_SEND_SUCCESS")
    assert.is_false(MA.machine:IsRunning())
    nextFrame()
    -- Over: every group that went says Sent for the rest of the visit.
    assert.same({ "Herbs", "Ore", "Potions" }, rowKeys())
    assert.equal("Sent", textOf(rowOf("Potions").status))
    assert.equal("Nothing to send now", textOf(top().title))
  end)

  -- The mail already handed to SendMail is the server's: it still goes, and nothing after it.
  it("stops on a second press of Send all, its Stop", function()
    event("MAIL_SHOW")
    press(top().send)
    press(top().send)
    assert.is_false(MA.machine:IsRunning())
    assert.equal("Stopped.", textOf(top().note))
    assert.equal("Send all", top().send.label)
    post:succeed()
    event("MAIL_SEND_SUCCESS")
    fire(GC.MailPress.STEP)
    assert.equal(1, #post:calls("SendMail"))
  end)

  it("lets go of the name box after a run, which Blizzard focuses after each mail", function()
    event("MAIL_SHOW")
    press(rowOf("Potions").send)
    _G.SendMailNameEditBox:SetFocus()
    post:succeed()
    event("MAIL_SEND_SUCCESS")
    nextFrame()
    assert.is_false(_G.SendMailNameEditBox:HasFocus())
  end)

  it("sends one group alone from its own Send", function()
    event("MAIL_SHOW")
    press(rowOf("Herbs").send)
    local sends = post:calls("SendMail")
    assert.equal(1, #sends)
    assert.same({ "Mirelle", "GoldCap: Herbs" }, { sends[1][1], sends[1][2] })
    assert.same({ "0:1", "0:2" }, post:pending().items)
  end)

  it("puts the attachments back on MAIL_FAILED and says the run stopped", function()
    event("MAIL_SHOW")
    press(top().send)
    assert.equal(3, post:attached())
    post:fail()
    event("MAIL_FAILED")
    assert.equal(0, post:attached())
    for _, slot in ipairs({ { 0, 1 }, { 0, 2 }, { 5, 1 } }) do
      assert.is_false(post.bags[slot[1]][slot[2]].isLocked)
    end
    assert.is_false(MA.machine:IsRunning())
    assert.equal("The mail did not go: what was attached is back in your bags.", textOf(top().note))
    assert.is_true(shown(top().note))
    assert.equal("Send all", top().send.label)
  end)

  -- The server may still have taken the mail it never answered for: the window does not say where
  -- the items are, only where to look.
  it("stops when the mailbox does not answer, and says where to look", function()
    event("MAIL_SHOW")
    press(top().send)
    fire(GC.MailPress.SEND_WAIT)
    assert.is_false(MA.machine:IsRunning())
    assert.equal("The mailbox did not answer. Check your bags and the Send Mail tab.", textOf(top().note))
  end)

  -- A pickup the client drops without a word leaves the cursor empty and the Send Mail tab as it
  -- was: that stack counts as refused, and a mail with nothing in it is never sent.
  it("sends no mail when a stack it picked up never reached the Send Mail tab", function()
    post:ignore(0, 4)
    event("MAIL_SHOW")
    press(rowOf("Potions").send)
    assert.equal(0, #post:calls("SendMail"))
    assert.equal(0, post:attached())
    assert.equal("Stopped: Tonic would not go into the mail.", textOf(top().note))
  end)

  it("stops when the mailbox closes mid-run, and sends nothing after", function()
    event("MAIL_SHOW")
    press(top().send)
    post:succeed()
    event("MAIL_SEND_SUCCESS")
    event("MAIL_CLOSED")
    assert.is_false(MA.machine:IsRunning())
    fire(GC.MailPress.STEP)
    assert.equal(1, #post:calls("SendMail"))
    assert.is_false(windowUp())
  end)

  it("stops, putting the stack back from the cursor, when the Send Mail tab will not take it", function()
    post:refuse(0, 2)
    event("MAIL_SHOW")
    press(top().send)
    assert.equal(0, #post:calls("SendMail"))
    assert.is_nil(post:holding())
    assert.equal(1, #post:calls("ClearCursor"))
    assert.equal(0, post:attached())
    assert.equal("Stopped: Bloom would not go into the mail.", textOf(top().note))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- A name typed by hand
  -- ---------------------------------------------------------------------------------------------

  it("asks once before mailing a typed name that is not one of yours: the first press arms", function()
    sendTo("Potions", "Stranger-Tarren")
    event("MAIL_SHOW")
    press(top().send)
    assert.equal(0, #post:calls("SendMail"))
    assert.equal(0, #post:calls("PickupContainerItem"))
    assert.equal("Send to Stranger? Press again", top().send.label)
    -- A double click's second click lands while the armed button still refuses it.
    assert.is_false(top().send:IsEnabled())
    press(top().send)
    assert.equal(0, #post:calls("SendMail"))
    assert.is_falsy(GC.MailGroups.Trusted(GC.db, "Stranger-Tarren"))
    fire(MA.ARM_HOLD)
    assert.is_true(top().send:IsEnabled())
    assert.equal("Send to Stranger? Press again", top().send.label)
    press(top().send)
    assert.equal(1, #post:calls("SendMail"))
    assert.is_true(GC.MailGroups.Trusted(GC.db, "Stranger-Tarren"))
  end)

  it("lets the ask go after 5 seconds, and asks again", function()
    sendTo("Potions", "Stranger-Tarren")
    event("MAIL_SHOW")
    press(rowOf("Potions").send)
    assert.equal("Send to Stranger? Press again", rowOf("Potions").send.label)
    assert.is_false(rowOf("Potions").send:IsEnabled())
    fire(5)
    assert.equal("Send", rowOf("Potions").send.label)
    press(rowOf("Potions").send)
    assert.equal(0, #post:calls("SendMail"))
    assert.equal("Send to Stranger? Press again", rowOf("Potions").send.label)
  end)

  it("never asks about one of the player's own characters", function()
    event("MAIL_SHOW")
    press(rowOf("Potions").send)
    assert.equal(1, #post:calls("SendMail"))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Who sells a group
  -- ---------------------------------------------------------------------------------------------

  it("lists only the characters this one can mail, with what they get or when they were seen", function()
    event("MAIL_SHOW")
    local m = openMenu(rowOf("Herbs"))
    assert.equal(rowOf("Herbs").to, m.owner)
    assert.same({
      "title: Who sells Herbs?", "title: Your characters on this realm",
      "Mirelle  gets Herbs, Ore", "Kaz-Kazzak  seen yesterday", "Thornwick  gets Potions",
      "This character", "Type a name", "Nobody yet",
    }, menuTexts(m))
    for _, child in ipairs(m.children) do
      if child.text and helper.plain(child.text):find("^Mirelle") then
        assert.truthy(child.text:find("|A:classicon-MAGE:", 1, true))
        assert.truthy(child.text:find("|cff40c7eb", 1, true))
      end
    end
  end)

  it("saves the character chosen for this realm, and sends there", function()
    event("MAIL_SHOW")
    choose(openMenu(rowOf("Herbs")), "Kaz-Kazzak")
    assert.equal("Kaz-Kazzak", GC.MailGroups.RecipientOf(GC.db, "Tarren", "Herbs"))
    assert.equal("Kaz-Kazzak", textOf(rowOf("Herbs").to.text))
    assert.equal("Herbs to Kaz-Kazzak, Ore to Mirelle, Potions to Thornwick. 4 stacks.", textOf(top().line))
    choose(openMenu(rowOf("Herbs")), "This character")
    assert.equal("Me-Tarren", GC.MailGroups.RecipientOf(GC.db, "Tarren", "Herbs"))
    choose(openMenu(rowOf("Herbs")), "Nobody yet")
    assert.is_nil(GC.MailGroups.RecipientOf(GC.db, "Tarren", "Herbs"))
    assert.equal("Who sells it?", textOf(rowOf("Herbs").to.text))
  end)

  it("takes a typed Name or Name-Realm in the kit's popup", function()
    event("MAIL_SHOW")
    choose(openMenu(rowOf("Potions")), "Type a name")
    assert.equal(rowOf("Potions").to, asked.anchor)
    assert.truthy(asked.opts.title:find("Name or Name-Realm", 1, true))
    assert.truthy(asked.opts.title:find("A name that is not one of your characters is asked about once, before the first mail goes.", 1, true))
    assert.equal("Type a character name", asked.opts.invalid)
    assert.equal("Stranger-Tarren", asked.opts.read("  stranger  "))
    assert.equal("Kaz-Kazzak", asked.opts.read("kaz-Kazzak"))
    assert.is_nil(asked.opts.read("two words"))
    assert.is_nil(asked.opts.read(""))
    assert.equal("Me-Tarren", asked.opts.read("me"))
    -- A realm this character cannot mail: refused, saying why.
    local full, why = asked.opts.read("Far-Silvermoon")
    assert.is_nil(full)
    assert.equal("Mail goes only to a character on this realm or a connected one.", why)
    asked.opts.onCommit("Stranger-Tarren")
    assert.equal("Stranger-Tarren", GC.MailGroups.RecipientOf(GC.db, "Tarren", "Potions"))
    assert.equal("Stranger", textOf(rowOf("Potions").to.text))
  end)

  it("closes the popups it opened when the mailbox closes", function()
    event("MAIL_SHOW")
    local keep, to = rowOf("Herbs").keep, rowOf("Herbs").to
    event("MAIL_CLOSED")
    assert.is_true(closedFor[keep])
    assert.is_true(closedFor[to])
  end)
end)
