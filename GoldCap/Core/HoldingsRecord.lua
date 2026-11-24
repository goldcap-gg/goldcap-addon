local _, GC = ...

-- What each character holds, place by place, for goldcap.gg: the Companion uploads it, and the site
-- keeps the latest reading of each place to tell stock that is gone from stock that only moved.
-- Core/Holdings.lua is the buy limit's arithmetic and keeps no store; this file is the store.
--
-- Store: GC.db.holdings = { v = 1,
--   chars = { ["Name-Realm"] = { region, bags = P, bank = P, mail = P, auctions = P } },
--   warband = { [region] = P } }
-- P = { at = time(), full = true | false, items = { [itemID] = count } }.
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
  -- The bags, as Services/Sell/Bags.lua walks them: the backpack, four bags and the reagent bag.
  BAGS = { 0, 1, 2, 3, 4, 5 },
  MAX_COUNT = 2147483647,
}
HR.KEEP_SECONDS, HR.MAX_CHARS, HR.BAGS = C.KEEP_SECONDS, C.MAX_CHARS, C.BAGS

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
    s = { v = C.VERSION, chars = {}, warband = {} }
    db.holdings = s
  end
  if (tonumber(s.v) or 0) > C.VERSION then return nil end
  if type(s.chars) ~= "table" then s.chars = {} end
  if type(s.warband) ~= "table" then s.warband = {} end
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

--- Drops the characters whose newest place is more than 90 days old, then keeps the 50 read most
--- recently (the oldest read goes first).
function HR.Prune(now)
  local s = store(false)
  if not s or type(now) ~= "number" then return end
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
