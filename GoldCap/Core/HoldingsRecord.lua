local _, GC = ...

-- What each character holds, place by place, for goldcap.gg: the Companion uploads it, and the site
-- keeps the latest reading of each place to tell stock that is gone from stock that only moved.
-- Core/Holdings.lua is the buy limit's arithmetic and keeps no store; this file is the store.
--
-- Store: GC.db.holdings = { v = 1,
--   chars = { ["Name-Realm"] = { region, bags = P, bank = P, mail = P, auctions = P } },
--   warband = { [region] = P },
--   guilds = { ["Guild-Realm"] = { region, at, full, tabs = { [tab] = { at, items } } } },
--   sends = { { from, to, region, at, items } } }
-- P = { at = time(), full = true | false, items = { [itemID] = count } }.
-- A guild bank belongs to no one character: each tab keeps the items of the last visit that read
-- it, and `full` says every tab the character could view was read on the last visit. A send is a
-- mail that left with items, so the site learns that a bank alt holds what it was sent.
--
-- A reading holds every item of its place with its count, not only items GoldCap saw bought, so an
-- item missing from a full reading is none there. A reading replaces its place whole, so the save
-- holds at most a place's slots' item ids. `full` is false for a reading cut short (bags before
-- the client has them, more mail than the inbox shows, a slot or a row not loaded yet): the site
-- counts such a place as unread. A character key without a realm records nothing.
--
-- The store is made on the first write and never by a read. A store a newer GoldCap wrote (v above
-- this file's) is left exactly as it is: every write answers false.
GC.HoldingsRecord = GC.HoldingsRecord or {}
local HR = GC.HoldingsRecord

local C = {
  VERSION = 1,
  PLACES = { bags = true, bank = true, mail = true, auctions = true },
  REGIONS = { us = true, eu = true, kr = true, tw = true },
  -- A character with no place read for this long is dropped, and at most this many are kept.
  KEEP_SECONDS = 90 * 86400,
  MAX_CHARS = 50,
  MAX_GUILDS = 10,
  MAX_SENDS = 300,
  -- MAX_GUILDBANK_SLOTS_PER_TAB, a local of Blizzard_GuildBankUI in both games.
  GUILD_SLOTS = 98,
  -- A caged battle pet is this item whatever species is inside, as the containers report it.
  PET_CAGE = 82800,
  -- The bags, as Services/Sell/Bags.lua walks them: the backpack, four bags and the reagent bag.
  BAGS = { 0, 1, 2, 3, 4, 5 },
  MAX_COUNT = 2147483647,
}
HR.KEEP_SECONDS, HR.MAX_CHARS, HR.BAGS = C.KEEP_SECONDS, C.MAX_CHARS, C.BAGS
HR.MAX_GUILDS, HR.MAX_SENDS = C.MAX_GUILDS, C.MAX_SENDS

local function isCount(n)
  return type(n) == "number" and n == math.floor(n) and n >= 1 and n <= C.MAX_COUNT
end

-- "Name-Realm" with both parts: rows were once written as "Name-" while the client named no realm
-- (Core/Game.lua), and a bare "Name" is no character the site can tell apart.
local function isKey(key)
  return type(key) == "string" and key:match("^[^%-]+%-.+$") ~= nil
end

-- A copy of `items`, or nil when one id or count is not a whole number of at least 1: a reading
-- the site would drop whole is never written.
local function cleanItems(items)
  if type(items) ~= "table" then return nil end
  local copy = {}
  for id, n in pairs(items) do
    if not (isCount(id) and isCount(n)) then return nil end
    copy[id] = n
  end
  return copy
end

-- The store, or nil. `create`: make it when absent. A newer store is never handed out.
local function store(create)
  local db = GC.db
  if type(db) ~= "table" then return nil end
  local s = db.holdings
  if type(s) ~= "table" then
    if not create then return nil end
    s = { v = C.VERSION, chars = {}, warband = {}, guilds = {}, sends = {} }
    db.holdings = s
  end
  if (tonumber(s.v) or 0) > C.VERSION then return nil end
  for _, name in ipairs({ "chars", "warband", "guilds", "sends" }) do
    if type(s[name]) ~= "table" then s[name] = {} end
  end
  return s
end

local function reading(items, full, now)
  return { at = now, full = full == true, items = items }
end

--- Records `char`'s reading of `place` (bags, bank, mail or auctions), replacing the last one whole.
--- False, and nothing written, for a key without a realm, a region outside us, eu, kr and tw, an
--- unknown place, an item list the site would refuse, or a newer store.
function HR.Record(char, region, place, items, full, now)
  if not isKey(char) or not C.REGIONS[region] or not C.PLACES[place] or type(now) ~= "number" then
    return false
  end
  local copy = cleanItems(items)
  if not copy then return false end
  local s = store(true)
  if not s then return false end
  local c = s.chars[char]
  if type(c) ~= "table" then
    c = {}
    s.chars[char] = c
  end
  c.region = region
  c[place] = reading(copy, full, now)
  HR.Prune(now)
  return true
end

--- Records the warband bank of `region` (retail: its tabs report slots only while it is open).
function HR.RecordWarband(region, items, full, now)
  if not C.REGIONS[region] or type(now) ~= "number" then return false end
  local copy = cleanItems(items)
  if not copy then return false end
  local s = store(true)
  if not s then return false end
  s.warband[region] = reading(copy, full, now)
  return true
end

-- The newest `at` of a character's places, or nil.
local function newestAt(c)
  local newest
  for place in pairs(C.PLACES) do
    local p = type(c) == "table" and c[place] or nil
    local at = type(p) == "table" and tonumber(p.at) or nil
    if at and (not newest or at > newest) then newest = at end
  end
  return newest
end

-- The sends of the last 90 days, at most the 300 newest, oldest first.
local function pruneSends(s, now)
  local kept = {}
  for _, send in ipairs(s.sends) do
    local at = type(send) == "table" and tonumber(send.at) or nil
    if at and now - at <= C.KEEP_SECONDS then kept[#kept + 1] = send end
  end
  table.sort(kept, function(a, b) return a.at < b.at end)
  while #kept > C.MAX_SENDS do table.remove(kept, 1) end
  s.sends = kept
end

--- Drops the characters whose newest place is more than 90 days old, then keeps the 50 read most
--- recently (the oldest read goes first). Sends: those of the last 90 days, at most 300.
function HR.Prune(now)
  local s = store(false)
  if not s or type(now) ~= "number" then return end
  pruneSends(s, now)
  local kept = {}
  for key, c in pairs(s.chars) do
    local at = newestAt(c)
    if not at or now - at > C.KEEP_SECONDS then
      s.chars[key] = nil
    else
      kept[#kept + 1] = { key = key, at = at }
    end
  end
  if #kept <= C.MAX_CHARS then return end
  table.sort(kept, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.key < b.key
  end)
  for i = 1, #kept - C.MAX_CHARS do s.chars[kept[i].key] = nil end
end

--- Every item in `bags` (container ids) with its count, as { [itemID] = count }, and whether the
--- reading is full: only when the first container reports slots (the backpack: none at login before
--- the client has the bags) and every occupied slot names its item. `api` is C_Container's
--- GetContainerNumSlots and GetContainerItemInfo.
function HR.ReadContainers(api, bags)
  local items, full = {}, true
  if type(api) ~= "table" or type(bags) ~= "table" or #bags == 0 then return items, false end
  for i, bag in ipairs(bags) do
    local ok, slots = pcall(api.GetContainerNumSlots, bag)
    slots = ok and tonumber(slots) or 0
    if i == 1 and slots <= 0 then full = false end
    for slot = 1, slots do
      local got, info = pcall(api.GetContainerItemInfo, bag, slot)
      if not got then
        full = false
      elseif type(info) == "table" then
        local id, n = info.itemID, info.stackCount
        if isCount(id) and isCount(n) then
          items[id] = (items[id] or 0) + n
        else
          full = false
        end
      end
    end
  end
  return items, full
end

-- The bank's containers by the client's own names for them (Enum.BagIndex). Both games today name
-- them CharacterBankTab_1.. and AccountBankTab_1.. (6 and 5 in retail, 9 each in WoW: Forever);
-- Bank, BankBag_N and ReagentBank are the names of an older bank, kept so a client that still has
-- them is read the same way.
local CHARACTER_BANK = { "^Bank$", "^BankBag_%d+$", "^ReagentBank$", "^CharacterBankTab_%d+$" }
local ACCOUNT_BANK = { "^AccountBankTab_%d+$" }

local function matches(name, patterns)
  for _, pattern in ipairs(patterns) do
    if name:match(pattern) then return true end
  end
  return false
end

local function clientContainers()
  local CC = _G.C_Container
  return type(CC) == "table" and { GetContainerNumSlots = CC.GetContainerNumSlots,
    GetContainerItemInfo = CC.GetContainerItemInfo } or nil
end

--- The bank's containers that report slots, as two sorted lists of container ids: the character's
--- own bank and the account's (the warband bank). A bank the client has not opened this session
--- answers no slots and is simply not there. `api`: { BagIndex, GetContainerNumSlots }, the
--- client's when omitted.
function HR.BankBags(api)
  if not api then
    local CC = _G.C_Container
    api = { BagIndex = type(_G.Enum) == "table" and _G.Enum.BagIndex or nil,
      GetContainerNumSlots = type(CC) == "table" and CC.GetContainerNumSlots or nil }
  end
  local character, account = {}, {}
  for name, index in pairs(type(api.BagIndex) == "table" and api.BagIndex or {}) do
    if type(name) == "string" and type(index) == "number" then
      local list = (matches(name, CHARACTER_BANK) and character) or (matches(name, ACCOUNT_BANK) and account) or nil
      if list then
        local ok, slots = pcall(api.GetContainerNumSlots, index)
        if ok and (tonumber(slots) or 0) > 0 then list[#list + 1] = index end
      end
    end
  end
  table.sort(character)
  table.sort(account)
  return character, account
end

--- Every attachment in the inbox (slots 1 to 16 of every mail shown), as { [itemID] = count }, and
--- whether the reading is full: only when GetInboxNumItems shows every mail and no row is still
--- loading (a header the client cannot answer, its "Retrieving data" subject, or fewer named
--- attachments than the header counts). An empty inbox is full only on a pass after MAIL_SHOW's
--- (`opening`), which can see 0 of 0 before the inbox arrives. Cash on delivery is counted: what
--- the site counts as held errs high. `api` is the ledger's inbox scan's (Core/Init.lua).
function HR.ReadMail(api, opening)
  local items, full = {}, true
  local ok, shown, total = pcall(api.GetInboxNumItems)
  if not ok or type(shown) ~= "number" or shown < 0 then return items, false end
  if type(total) == "number" and total > shown then full = false end
  if shown == 0 then return items, full and not opening end
  local MC = GC.MailClassify
  for index = 1, shown do
    local mail = MC.Read(api, index)
    if not mail or MC.IsRetrieving(mail.subject) then
      full = false
    else
      local found = 0
      for _, item in ipairs(mail.items) do
        if isCount(item.itemID) and isCount(item.count) then
          found = found + 1
          items[item.itemID] = (items[item.itemID] or 0) + item.count
        else
          full = false
        end
      end
      if found < (tonumber(mail.itemCount) or 0) then full = false end
    end
  end
  return items, full
end

-- What the client reads for, and the character at the keyboard: nil while either is unknown.
local function context()
  local ctx = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
  if type(ctx) ~= "table" or not isKey(ctx.char) or not C.REGIONS[ctx.region] then return nil end
  return ctx
end

-- How many tabs `bankType`'s bank has bought, or nil when the client cannot say.
local function purchasedTabs(bankType)
  local bank = _G.C_Bank
  if bankType == nil or type(bank) ~= "table" or type(bank.FetchPurchasedBankTabIDs) ~= "function" then return nil end
  local ok, tabs = pcall(bank.FetchPurchasedBankTabIDs, bankType)
  return ok and type(tabs) == "table" and #tabs or nil
end

local bankOpen, bankQueued = false, false

-- The bank and the warband bank, only while the bank is open. A frame that shows no container of
-- the character's own (only the warband bank open) records no bank reading. A tab the bank has
-- bought that reports no slots makes its reading not full (the count may only lower `full`).
local function readBank(now)
  local ctx = bankOpen and context() or nil
  local api = ctx and clientContainers() or nil
  if not api then return end
  local types = type(_G.Enum) == "table" and _G.Enum.BankType or {}
  local character, account = HR.BankBags()
  if #character > 0 then
    local items, full = HR.ReadContainers(api, character)
    if full and (purchasedTabs(types.Character) or 0) > #character then full = false end
    HR.Record(ctx.char, ctx.region, "bank", items, full, now)
  end
  if #account > 0 then
    local items, full = HR.ReadContainers(api, account)
    if full and (purchasedTabs(types.Account) or 0) > #account then full = false end
    HR.RecordWarband(ctx.region, items, full, now)
  end
end

--- PLAYER_ENTERING_WORLD and BAG_UPDATE_DELAYED (Core/Init.lua): the bags of the character at the
--- keyboard, and the bank too while it is open (a move into or out of it is a bag change).
function HR.OnBags(now)
  local ctx = context()
  local api = ctx and clientContainers() or nil
  if not api then return end
  local items, full = HR.ReadContainers(api, C.BAGS)
  HR.Record(ctx.char, ctx.region, "bags", items, full, now)
  readBank(now)
end

--- BANKFRAME_OPENED: the bank's containers answer from now until BANKFRAME_CLOSED.
function HR.OnBankOpened(now)
  bankOpen = true
  readBank(now)
end

function HR.OnBankClosed()
  bankOpen = false
end

--- PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED comes once a slot (hundreds for a sort): read once, on the
--- next frame, while the bank is open.
function HR.OnBankSlots()
  local timer = _G.C_Timer
  if not bankOpen or bankQueued or type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  bankQueued = true
  timer.After(0, function()
    bankQueued = false
    readBank(time())
  end)
end

--- MAIL_SHOW and MAIL_INBOX_UPDATE, after the ledger's inbox scan, with its `api`: WoW: Forever's
--- item reading of the mailbox too (its scan reads invoices and returned lots only, and
--- Core/MailStock.lua is retail only). The opening pass of an empty inbox says nothing yet and
--- leaves the last reading as it was.
function HR.OnInbox(api, opening, now)
  local ctx = context()
  if not ctx or type(api) ~= "table" then return end
  local items, full = HR.ReadMail(api, opening)
  if opening and not full and next(items) == nil then return end
  HR.Record(ctx.char, ctx.region, "mail", items, full, now)
end

-- The guild bank -----------------------------------------------------------------------------------

-- The visit going on: the guild it is at, the tabs read and the tabs asked for. Kept in memory: a
-- visit ends with the session at the latest.
local guildVisit
local guildOpen = false

--- A visit to `guild`'s bank starts: no tab is read yet (GUILDBANKFRAME_OPENED).
function HR.GuildVisitStart(guild)
  guildVisit = { guild = guild, read = {}, queried = {} }
end

--- Records tab `tab` of `guild` ("Guild-Realm") as read now, replacing that tab whole. At most 10
--- guilds are kept, the oldest read going first, never the one just written.
function HR.RecordGuildTab(guild, region, tab, items, now)
  if not isKey(guild) or not C.REGIONS[region] or not isCount(tab) or type(now) ~= "number" then return false end
  local copy = cleanItems(items)
  if not copy then return false end
  local s = store(true)
  if not s then return false end
  local g = s.guilds[guild]
  if type(g) ~= "table" or type(g.tabs) ~= "table" then
    g = { tabs = {}, full = false }
    s.guilds[guild] = g
  end
  g.region, g.at = region, now
  g.tabs[tab] = { at = now, items = copy }
  if not (guildVisit and guildVisit.guild == guild) then HR.GuildVisitStart(guild) end
  guildVisit.read[tab] = true
  local keys = {}
  for key, other in pairs(s.guilds) do
    if key ~= guild then keys[#keys + 1] = { key = key, at = type(other) == "table" and tonumber(other.at) or 0 } end
  end
  if #keys >= C.MAX_GUILDS then
    table.sort(keys, function(a, b)
      if a.at ~= b.at then return a.at < b.at end
      return a.key < b.key
    end)
    for i = 1, #keys - C.MAX_GUILDS + 1 do s.guilds[keys[i].key] = nil end
  end
  return true
end

--- After a pass over `guild`'s bank: the reading is full only when every tab in `viewable` (the tab
--- numbers the character can view) was read this visit. Returns it; false for a guild never read.
function HR.GuildVisitDone(guild, viewable, now)
  local s = store(false)
  local g = s and s.guilds[guild] or nil
  if type(g) ~= "table" or type(viewable) ~= "table" then return false end
  local read = guildVisit and guildVisit.guild == guild and guildVisit.read or {}
  local full = #viewable > 0
  for _, tab in ipairs(viewable) do
    if not read[tab] then full = false end
  end
  g.full = full
  if type(now) == "number" then g.at = now end
  return full
end

local function linkedItem(link)
  if type(link) ~= "string" then return nil end
  local id = tonumber(link:match("item:(%d+)"))
  if id then return id end
  if link:find("battlepet:", 1, true) then return C.PET_CAGE end
  return nil
end

--- One guild bank tab as { [itemID] = count }, the id from each slot's link, or nil while it cannot
--- be read whole: a call that raises, an item with no link or count yet, or a tab that shows no item
--- at all (an empty tab cannot be told from one the server has not sent yet, so it is never read as
--- empty). `api`: GetGuildBankItemInfo and GetGuildBankItemLink.
function HR.ReadGuildTab(api, tab)
  local items, any = {}, false
  for slot = 1, C.GUILD_SLOTS do
    local ok, texture, count = pcall(api.GetGuildBankItemInfo, tab, slot)
    if not ok then return nil end
    if texture ~= nil then
      local got, link = pcall(api.GetGuildBankItemLink, tab, slot)
      local id = got and linkedItem(link) or nil
      if not id or not isCount(count) then return nil end
      items[id] = (items[id] or 0) + count
      any = true
    end
  end
  return any and items or nil
end

-- "Guild-Realm" of the character's guild: GetGuildInfo's fourth value is the guild's realm when it
-- is not the character's own. nil out of a guild or while the realm is unknown.
local function guildKey()
  if type(GetGuildInfo) ~= "function" then return nil end
  local ok, name, _, _, realm = pcall(GetGuildInfo, "player")
  if not ok or type(name) ~= "string" or name == "" then return nil end
  if type(realm) ~= "string" or realm == "" then
    realm = GC.Game and GC.Game.RealmName and GC.Game.RealmName() or nil
  end
  local key = type(realm) == "string" and (name .. "-" .. realm) or nil
  return isKey(key) and key or nil
end

-- The tabs the character can view, by number.
local function viewableTabs()
  local tabs = {}
  if type(GetNumGuildBankTabs) ~= "function" or type(GetGuildBankTabInfo) ~= "function" then return tabs end
  local ok, n = pcall(GetNumGuildBankTabs)
  for tab = 1, ok and tonumber(n) or 0 do
    local got, _, _, isViewable = pcall(GetGuildBankTabInfo, tab)
    if got and isViewable then tabs[#tabs + 1] = tab end
  end
  return tabs
end

-- Each viewable tab is asked for once a visit: the server sends a tab's items only when asked.
local function queryTabs(tabs)
  if not guildVisit or type(QueryGuildBankTab) ~= "function" then return end
  for _, tab in ipairs(tabs) do
    if not guildVisit.queried[tab] then
      guildVisit.queried[tab] = true
      pcall(QueryGuildBankTab, tab)
    end
  end
end

--- GUILDBANKBAGSLOTS_CHANGED: every viewable tab the client has now is recorded, the rest keep
--- their last items; tabs not asked for yet this visit are asked for.
function HR.OnGuildBankSlots(now)
  local ctx, guild = context(), guildKey()
  if not ctx or not guild then return end
  if not (guildVisit and guildVisit.guild == guild) then HR.GuildVisitStart(guild) end
  local tabs = viewableTabs()
  queryTabs(tabs)
  local api = { GetGuildBankItemInfo = GetGuildBankItemInfo, GetGuildBankItemLink = GetGuildBankItemLink }
  for _, tab in ipairs(tabs) do
    local items = HR.ReadGuildTab(api, tab)
    if items then HR.RecordGuildTab(guild, ctx.region, tab, items, now) end
  end
  HR.GuildVisitDone(guild, tabs, now)
end

--- GUILDBANKFRAME_OPENED, or the interaction manager's GuildBanker (whichever the client sends;
--- once until the bank closes): a new visit, each viewable tab asked for.
function HR.OnGuildBankOpened(now)
  if guildOpen then return end
  local guild = guildKey()
  if not guild then return end
  guildOpen = true
  HR.GuildVisitStart(guild)
  HR.OnGuildBankSlots(now)
end

function HR.OnGuildBankClosed()
  guildOpen = false
end

-- Mail sends ---------------------------------------------------------------------------------------

-- The mail being sent, from SendMail until the server answers it. One at a time: Send to alts sends
-- a mail only once the one before was answered (Core/MailPress.lua).
local pendingSend

--- A mail is on its way to `to` with `items` ({ [itemID] = count }) from the character at the
--- keyboard. A recipient with no realm is on the sender's (GC.Game.RealmName, through the key).
--- False, and nothing waits, for a mail with no item, no recipient, or a sender without a realm.
function HR.PendingSend(to, items, now)
  pendingSend = nil
  local ctx = context()
  if not ctx or type(to) ~= "string" then return false end
  to = to:match("^%s*(.-)%s*$")
  if to == "" then return false end
  if not to:find("-", 1, true) then to = to .. "-" .. ctx.char:match("^[^%-]+%-(.+)$") end
  local copy = cleanItems(items)
  if not isKey(to) or not copy or next(copy) == nil then return false end
  pendingSend = { from = ctx.char, to = to, region = ctx.region, at = now, items = copy }
  return true
end

--- MAIL_SEND_SUCCESS: the mail waiting went. False when none was waiting.
function HR.SendSucceeded(now)
  local send = pendingSend
  pendingSend = nil
  if not send or type(now) ~= "number" then return false end
  local s = store(true)
  if not s then return false end
  send.at = now
  s.sends[#s.sends + 1] = send
  pruneSends(s, now)
  return true
end

--- MAIL_FAILED and MAIL_CLOSED: the mail waiting did not go, or its answer can no longer be told.
function HR.SendDropped()
  pendingSend = nil
end

-- The attachments of the Send Mail frame, as { [itemID] = count }.
local function sendItems()
  local items = {}
  if type(GetSendMailItem) ~= "function" then return items end
  for slot = 1, tonumber(ATTACHMENTS_MAX_SEND) or 12 do
    local ok, _, itemID, _, count = pcall(GetSendMailItem, slot)
    if ok and isCount(itemID) then items[itemID] = (items[itemID] or 0) + (isCount(count) and count or 1) end
  end
  return items
end

local sendHooked = false

--- ADDON_LOADED: a post-hook on SendMail keeps the recipient and the attachments, which Blizzard
--- empties on MAIL_SEND_SUCCESS. Once; nothing where the client has no hooksecurefunc or SendMail.
function HR.HookSendMail()
  if sendHooked or type(hooksecurefunc) ~= "function" or type(SendMail) ~= "function" then return false end
  sendHooked = pcall(hooksecurefunc, "SendMail", function(recipient)
    pcall(function() HR.PendingSend(recipient, sendItems(), time()) end)
  end)
  return sendHooked
end
