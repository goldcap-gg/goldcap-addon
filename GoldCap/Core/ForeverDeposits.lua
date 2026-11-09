local _, GC = ...

-- WoW: Forever only: GoldCap_Camelot.toc loads this file and GoldCap.toc does not, so nothing here
-- runs on retail, and every shared caller asks `if GC.ForeverDeposits` first. A lot that expires
-- or is cancelled keeps its deposit, and nothing in the client says how much: this file remembers
-- what each post put up and writes the loss to the ledger as a row of its own, and it keeps the
-- run of lots that came back unsold, which SELL's sale pace reads (Core/ForeverPace.lua's
-- streakFor).
--
-- Saved in GoldCapDB.foreverDeposits, reached through GC.ForeverScan.Root() and created on the
-- first write (no DEFAULTS entry, no Init), so a retail save never gains the key:
--   { v = 1,
--     posts = { [auctionID] = { auctionID, itemID, itemName, quantity, duration, deposit, postedAt,
--       endsAt, char, region, faction, commodity, joinedAt, cancelledAt } },
--     streaks = { [char .. "\1" .. region] = { [itemID] = { soldAt,
--       rounds = { { at, last, duration }, ... } } } } }
-- A post is recorded only for a creation certain to be GoldCap's (GC.Sell.OnAuctionCreated) and
-- kept KEEP_SECONDS (the longest lot lasts 24 h). `deposit` is the client's quote: a commodity's is
-- asked at creation, an item's is the one the post panel quoted at paint, copied into the pin; nil
-- when there was none. A save with a newer `v` is a shape this build does not know: nothing reads
-- it and nothing writes to it.
--
-- The rows (GC.Ledger.Append) carry the lost copper in `deposit`, with `total` 0, `cut` 0 and
-- `pending` false: kind "expired" from source "mail" (a lot the returns log read back,
-- Core/MailReturns.lua) and kind "cancelled" from source "auction" (the server's AUCTION_CANCELED).
-- The Companion sends a row on when it has key, kind, source, qty, total and at, and drops every
-- field its row type does not know, so the loss rides in a field it already carries. The site must
-- accept these two kinds before any build that writes them reaches a player (site 1.74.0 first):
-- its Forever upload skips a kind it does not know, the Companion marks the row sent, and the row is
-- lost. Retail's upload refuses a whole batch for one such row, which is why retail never loads
-- this file.
--
-- What the client may not answer degrades to nothing: a quote away from the auction house is 0, a
-- mail subject the client lacks logs no lot (Core/Ledger.lua's ScanInbox), and an AUCTION_CANCELED
-- that never comes writes no cancelled row.
GC.ForeverDeposits = GC.ForeverDeposits or {}
local M = GC.ForeverDeposits

M.VERSION = 1
-- How long a post is remembered: the longest lot (24 h), its mail and a margin.
M.KEEP_SECONDS = 3 * 86400
-- Returns within this long of the last one are one round (Core/SellRounds.lua's gap).
M.ROUND_GAP_SECONDS = 3600
-- Rounds older than this are not counted (the returns log keeps 14 days, Core/MailReturns.lua).
M.STREAK_SECONDS = 14 * 86400
-- The newest rounds kept per item and character.
M.MAX_ROUNDS = 20

-- What the client is asked, through fields a spec replaces. Each degrades to nil (or false) when
-- the call is missing or raises.
function M.QuoteCommodity(itemID, quantity, durationIndex)
  local flips = GC.Flips
  if type(flips) ~= "table" then return nil end
  local ok, deposit = pcall(flips.CommodityDeposit, itemID, quantity, durationIndex)
  return ok and deposit or nil
end

function M.IsCommodity(itemID)
  return type(GC.db) == "table" and type(GC.db.commodityByItem) == "table" and GC.db.commodityByItem[itemID] == true
end

function M.NameOf(itemID)
  local item = _G.C_Item
  if type(item) ~= "table" or type(item.GetItemNameByID) ~= "function" then return nil end
  local ok, name = pcall(item.GetItemNameByID, itemID)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

function M.HoursOf(index)
  return GC.GroupRules and GC.GroupRules.HoursOf and GC.GroupRules.HoursOf(index) or nil
end

function M.SettingIndex()
  return GC.Flips and GC.Flips.PostDurationIndex and GC.Flips.PostDurationIndex() or nil
end

-- GoldCap's own cancels, by auctionID: { lot, estimate, at }, for the server's answer to read
-- (Cancelled). In memory only.
local notes = {}
-- The cancels answered this session, by auctionID: an auction is cancelled once, so a second answer
-- for one writes nothing, recorded or not.
local answered = {}

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function whole(v)
  return finite(v) and v == math.floor(v) and v > 0
end

local function copper(v)
  return finite(v) and v == math.floor(v) and v >= 0
end

local function named(context)
  return type(context) == "table" and type(context.char) == "string" and context.char ~= ""
    and type(context.region) == "string" and context.region ~= ""
end

local function validIndex(v)
  return (v == 1 or v == 2 or v == 3) and v or nil
end

-- The whole save while this file may use its key: nil on retail (no root) and over a newer save.
local function rootOf()
  local root = GC.ForeverScan and GC.ForeverScan.Root and GC.ForeverScan.Root()
  if type(root) ~= "table" then return nil end
  local s = root.foreverDeposits
  if type(s) == "table" and type(s.v) == "number" and s.v > M.VERSION then return nil end
  return root
end

-- The save, when there is one to use (rootOf): created with `create`, else nil while there is none.
local function store(create)
  local root = rootOf()
  if not root then return nil end
  local s = root.foreverDeposits
  if type(s) ~= "table" or s.v ~= M.VERSION then
    if not create then return nil end
    s = { v = M.VERSION, posts = {}, streaks = {} }
    root.foreverDeposits = s
  end
  if type(s.posts) ~= "table" then s.posts = {} end
  if type(s.streaks) ~= "table" then s.streaks = {} end
  return s
end

-- A commodity's deposit as the client quotes it, or nil: no answer, or one that raised.
local function quote(itemID, quantity, durationIndex)
  local ok, deposit = pcall(M.QuoteCommodity, itemID, quantity, durationIndex)
  return ok and copper(deposit) and deposit or nil
end

-- This character's run of returns for `itemID`, created with `create`.
local function streakOf(s, itemID, context, create)
  local key = context.char .. "\1" .. context.region
  local items = s.streaks[key]
  if type(items) ~= "table" then
    if not create then return nil end
    items = {}
    s.streaks[key] = items
  end
  local item = items[itemID]
  if type(item) ~= "table" or type(item.rounds) ~= "table" then
    if not create then return nil end
    item = { rounds = {} }
    items[itemID] = item
  end
  return item, items
end

-- Rounds that ended STREAK_SECONDS ago go, and with them an item whose sale is as old.
local function prune(items, now)
  local cutoff = now - M.STREAK_SECONDS
  for itemID, item in pairs(items) do
    local kept = {}
    for _, round in ipairs(type(item) == "table" and type(item.rounds) == "table" and item.rounds or {}) do
      if type(round) == "table" and finite(round.last) and round.last >= cutoff then kept[#kept + 1] = round end
    end
    if #kept == 0 and not (type(item) == "table" and finite(item.soldAt) and item.soldAt >= cutoff) then
      items[itemID] = nil
    else
      item.rounds = kept
    end
  end
end

-- A lot of `itemID` came back unsold at `now`, posted at `duration` when that is known: the newest
-- round takes it when it is within the round gap, else it starts one.
local function noteReturn(s, itemID, context, now, duration)
  local item, items = streakOf(s, itemID, context, true)
  local newest = item.rounds[#item.rounds]
  if type(newest) == "table" and finite(newest.last) and now - newest.last <= M.ROUND_GAP_SECONDS then
    newest.last = now
    newest.duration = validIndex(duration) or newest.duration
  else
    item.rounds[#item.rounds + 1] = { at = now, last = now, duration = validIndex(duration) }
  end
  prune(items, now)
  while #item.rounds > M.MAX_ROUNDS do table.remove(item.rounds, 1) end
end

--- A post certain to be GoldCap's went up as `auctionID` (GC.Sell.OnAuctionCreated): its pin
--- (itemID, quantity, duration, isCommodity, deposit, position) and the character it went up on.
--- Returns the record, or nil when anything it needs is missing.
function M.RecordPost(auctionID, pin, context, now)
  if not whole(auctionID) or type(pin) ~= "table" or not whole(pin.itemID) or not whole(pin.quantity)
      or not validIndex(pin.duration) or not named(context) or not finite(now) then return nil end
  local hours = M.HoursOf(pin.duration)
  if not finite(hours) or hours <= 0 then return nil end
  local s = store(true)
  if not s then return nil end
  local cutoff = now - M.KEEP_SECONDS
  for id, record in pairs(s.posts) do
    if type(record) ~= "table" or not finite(record.postedAt) or record.postedAt < cutoff then s.posts[id] = nil end
  end
  local deposit = pin.isCommodity and quote(pin.itemID, pin.quantity, pin.duration) or pin.deposit
  local record = { auctionID = auctionID, itemID = pin.itemID,
    itemName = type(pin.position) == "table" and pin.position.itemName or nil,
    quantity = pin.quantity, duration = pin.duration, deposit = copper(deposit) and deposit or nil,
    postedAt = now, endsAt = now + hours * 3600, char = context.char, region = context.region,
    faction = context.faction, commodity = pin.isCommodity == true }
  s.posts[auctionID] = record
  return record
end

-- The record a lot that came back belongs to: this character's and realm's, of the item, not yet
-- joined or cancelled, and ended (within the returns log's own margin of the read); the one of the
-- lot's quantity first, then the oldest end, then the lower auctionID.
local function joinFor(s, lot, context, now)
  local latest = now + GC.MailReturns.MATCH_SECONDS
  local best
  for _, record in pairs(s.posts) do
    if type(record) == "table" and record.char == context.char and record.region == context.region
        and record.itemID == lot.itemID and not record.joinedAt and not record.cancelledAt
        and whole(record.quantity) and finite(record.endsAt) and record.endsAt <= latest then
      if not best then
        best = record
      else
        local equal, bestEqual = record.quantity == lot.count, best.quantity == lot.count
        if equal ~= bestEqual then
          if equal then best = record end
        elseif record.endsAt ~= best.endsAt then
          if record.endsAt < best.endsAt then best = record end
        elseif record.auctionID < best.auctionID then
          best = record
        end
      end
    end
  end
  return best
end

-- Whether the ledger already holds a row under `key`.
local function inLedger(key)
  for _, entry in ipairs(GC.Ledger.GetEntries()) do
    if entry.key == key then return true end
  end
  return false
end

--- The lots one inbox scan logged for the first time (GC.MailReturns.Observe's `fresh`: { itemID,
--- count, reason, at, expiresAt }). Each expired lot joins its post record, when there is one, and
--- costs that record's deposit for the units that came back; with none, a commodity's deposit is
--- quoted again at the setting's duration, and anything else costs 0. One ledger row each, and one
--- return in the item's run. A cancelled lot's mail writes nothing: its row is the cancel's own.
--- Returns the rows written, nil where nothing may be written.
function M.OnReturns(lots, context, now)
  if not named(context) or not finite(now) or not GC.Ledger or not GC.MailReturns then return nil end
  local s = store(true)
  if not s then return nil end
  local rows, keys = {}, {}
  for _, lot in ipairs(type(lots) == "table" and lots or {}) do
    if type(lot) == "table" and lot.reason == "expired" and whole(lot.itemID) and whole(lot.count)
        and finite(lot.expiresAt) then
      local record = joinFor(s, lot, context, now)
      local key, lost, at
      if record then
        lost = record.deposit and math.floor(record.deposit * math.min(lot.count, record.quantity) / record.quantity) or 0
        key, at = "deposit\1" .. record.auctionID, math.min(record.endsAt, now)
        record.joinedAt = now
      else
        lost = M.IsCommodity(lot.itemID) and quote(lot.itemID, lot.count, M.SettingIndex()) or 0
        key, at = "deposit\1mail\1" .. context.char .. "\1" .. lot.itemID .. "\1" .. lot.expiresAt, now
        -- Two lots that read the same are two (Core/MailReturns.lua): the second takes a number.
        local base, n = key, 1
        while keys[key] or inLedger(key) do
          n = n + 1
          key = base .. "\1" .. n
        end
      end
      keys[key] = true
      local row = { key = key, kind = "expired", source = "mail", itemID = lot.itemID,
        itemName = record and record.itemName or M.NameOf(lot.itemID), qty = lot.count, total = 0,
        deposit = lost, cut = 0, pending = false, at = at, char = context.char, region = context.region }
      local stored, _, err = GC.Ledger.Append(row)
      if stored and not err then rows[#rows + 1] = row end
      noteReturn(s, lot.itemID, context, now, record and record.duration)
    end
  end
  return rows
end

--- GoldCap's own cancel of `lot` ({ auctionID, itemID, quantity, positionKey }) went out, with what
--- it was estimated to lose: kept for the server's answer (Cancelled). Called after the protected
--- call, never before it.
function M.NoteCancel(lot, estimate, now)
  if type(lot) ~= "table" or not whole(lot.auctionID) or not rootOf() then return end
  notes[lot.auctionID] = { lot = lot, estimate = estimate, at = now }
end

--- The server said `auctionID` was cancelled (AUCTION_CANCELED). `lot` and `estimate` are the
--- caller's (the owned list's row, GC.Sell.LotForfeit); a note GoldCap's own cancel left wins over
--- both. The lot loses the recorded deposit for its units, else the estimate, else 0. Returns the
--- row, or nil: answered already, no item known, or nothing may be written.
function M.Cancelled(auctionID, lot, estimate, context, now)
  if not whole(auctionID) or not named(context) or not finite(now) or not GC.Ledger then return nil end
  local s = store(true)
  if not s or answered[auctionID] then return nil end
  local note = notes[auctionID]
  if note then lot, estimate = note.lot, note.estimate end
  lot = type(lot) == "table" and lot or nil
  local record = s.posts[auctionID]
  if type(record) ~= "table" or record.char ~= context.char or record.region ~= context.region
      or not whole(record.quantity) then
    record = nil
  end
  if record and record.cancelledAt then return nil end
  local itemID = record and record.itemID or lot and lot.itemID
  local qty = lot and whole(lot.quantity) and lot.quantity or record and record.quantity
  if not whole(itemID) or not whole(qty) then return nil end
  local deposit
  if record and record.deposit then
    deposit = math.floor(record.deposit * math.min(qty, record.quantity) / record.quantity)
  else
    deposit = copper(estimate) and estimate or 0
  end
  local row = { key = "deposit\1" .. auctionID, kind = "cancelled", source = "auction", itemID = itemID,
    itemName = record and record.itemName or lot and lot.itemName or M.NameOf(itemID), qty = qty, total = 0,
    deposit = deposit, cut = 0, pending = false, at = now, char = context.char, region = context.region }
  local stored, _, err = GC.Ledger.Append(row)
  if not stored or err then return nil end
  if record then record.cancelledAt = now end
  notes[auctionID], answered[auctionID] = nil, true
  return row
end

--- A sale of `itemID` at `at` on this character (the ledger's inbox scan): its run of returns ends.
--- A return stamped in the same second as the sale counts after it, as Core/SellRounds.lua counts.
function M.Sold(itemID, at, context)
  if not whole(itemID) or not finite(at) or not named(context) then return end
  local s = store(true)
  if not s then return end
  local item, items = streakOf(s, itemID, context, true)
  item.soldAt = math.max(finite(item.soldAt) and item.soldAt or 0, at)
  local kept = {}
  for _, round in ipairs(item.rounds) do
    if type(round) == "table" and finite(round.at) and round.at >= item.soldAt then kept[#kept + 1] = round end
  end
  item.rounds = kept
  prune(items, at)
end

--- The run of `itemID` on this character since its last sale, over the last STREAK_SECONDS: how many
--- rounds came back unsold, how many of them at a duration under 24 h, and the duration of the
--- newest of those. 0, 0, nil with none.
function M.Streak(itemID, context, now)
  if not named(context) or not finite(now) then return 0, 0, nil end
  local s = store(false)
  local item = s and streakOf(s, itemID, context, false)
  if not item then return 0, 0, nil end
  local soldAt = finite(item.soldAt) and item.soldAt or nil
  local cutoff = now - M.STREAK_SECONDS
  local rounds, short, shortIndex, shortAt = 0, 0, nil, nil
  for _, round in ipairs(item.rounds) do
    if type(round) == "table" and finite(round.at) and finite(round.last) and (not soldAt or round.at >= soldAt)
        and round.last >= cutoff then
      rounds = rounds + 1
      if round.duration == 1 or round.duration == 2 then
        short = short + 1
        if not shortAt or round.at >= shortAt then shortIndex, shortAt = round.duration, round.at end
      end
    end
  end
  return rounds, short, shortIndex
end

--- The deposit recorded for `auctionID`'s post, or nil.
function M.DepositOf(auctionID)
  local s = store(false)
  local record = s and whole(auctionID) and s.posts[auctionID]
  return type(record) == "table" and copper(record.deposit) and record.deposit or nil
end
