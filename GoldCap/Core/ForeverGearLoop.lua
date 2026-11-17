local _, GC = ...

-- WoW: Forever: gear listed under what a vendor pays, found while it is still there.
--
-- The Deals board is built from the full scan, which the server allows once in fifteen minutes and
-- which is about thirty seconds old by the time a row of it is checked. A lot under the vendor
-- price with a real margin is bought inside those seconds: Precision Bow at 22s against a vendor's
-- 24s 26c was in the 12:08 scan and gone from the live search four seconds after the save (owner's
-- client, 2026-11-16). So between scans the auction house is browsed class by class, weapons then
-- armor, round after round (UI/SniperGearLoop_Camelot.lua owns the requests). Measured the same
-- day: 2,263 weapon keys in 5 pages and 2.9 s, 11,700 armor keys in 24 pages and 15.5 s, six
-- rounds back to back with no throttling. A browse row is one item key (item, level, suffix) with
-- its cheapest price and how many are up, which is all the vendor test needs. The server does not
-- honour the price sort, so a class is read whole.
--
-- Pure: this module judges rows and keeps a round's figures. It sends nothing and reads no clock
-- but the one it is handed.
GC.ForeverGearLoop = GC.ForeverGearLoop or {}
local L = GC.ForeverGearLoop

L.C = {
  -- Enum.ItemClass.Weapon and .Armor, in the order a round reads them: the short class first.
  CLASSES = { 2, 4 },
  -- Items a page may ask the client about when no vendor price is kept for them. Asking is a load
  -- (Core/ForeverValue.lua): thousands at once made 130-200 ms frames (owner's client, 2026-11-13).
  -- At about 0.6 s a page a new install learns the ~4,700 unloaded armor items over a few rounds,
  -- and the answers are kept in the save from then on.
  ASKS_PER_PAGE = 25,
  -- A hit whose Check could not go out is let go after this long: the next round reports the lot
  -- again if it is still up.
  HIT_WAIT_SECONDS = 30,
  KEEP_ROUNDS = 10,
  KEEP_HITS = 30,
}

local function whole(n)
  return type(n) == "number" and n == n and n > 0 and n == math.floor(n)
end

--- "item/level/suffix", the key as the save and the trace print it.
function L.KeyText(key)
  if type(key) ~= "table" then return "?" end
  return ("%d/%d/%d"):format(key.itemID or 0, key.itemLevel or 0, key.itemSuffix or 0)
end

--- One round's bookkeeping. `driver`:
---   vendorFor(itemID)  what a vendor pays for one, from the kept answers only; nil when none is kept
---   known(itemID)      whether an answer about the item is kept (a kept "no vendor price" included)
---   listed(itemID)     whether the board already shows a row of the item (optional)
function L.New(driver)
  local obj = {}
  local round = nil      -- { startedAt, rows, pages, under = { [itemID] = { variants } }, asked }
  local queue = {}       -- hits waiting for their Check: { itemID, unit, at }
  local asked = {}       -- itemID -> true: the client was asked about it this session

  function obj:BeginRound(now)
    round = { startedAt = now, rows = 0, pages = 0, under = {}, keys = {}, underCount = 0, unknown = 0, hits = 0 }
  end

  function obj:InRound() return round ~= nil end

  -- A page of browse rows. Answers:
  --   under    the rows cheaper than the vendor price, each { itemID, key, unit, qty, vendor };
  --   ask      items with no kept answer the client may be asked about now (ASKS_PER_PAGE at most,
  --            each once a session).
  function obj:Fold(rows)
    local under, ask = {}, {}
    if not round or type(rows) ~= "table" then return under, ask end
    round.pages = round.pages + 1
    for i = 1, #rows do
      local row = rows[i]
      local key = type(row) == "table" and row.itemKey or nil
      local itemID = type(key) == "table" and key.itemID or nil
      if whole(itemID) then
        round.rows = round.rows + 1
        local unit, qty = row.minPrice, row.totalQuantity
        if whole(unit) and whole(qty) then
          local vendor = driver.vendorFor(itemID)
          local isUnder = whole(vendor) and unit < vendor
          -- Every key with lots of an item the board shows, or is about to, is kept for its Check.
          local keys = round.keys[itemID]
          if not keys and (isUnder or (driver.listed and driver.listed(itemID))) then
            keys = {}
            round.keys[itemID] = keys
          end
          local variant
          if keys then
            variant = { itemLevel = key.itemLevel or 0, itemSuffix = key.itemSuffix or 0,
              battlePetSpeciesID = key.battlePetSpeciesID or 0, floor = unit, qty = qty, vendor = vendor }
            keys[#keys + 1] = variant
          end
          if whole(vendor) then
            if isUnder then
              local seen = round.under[itemID]
              if not seen then
                seen = {}
                round.under[itemID] = seen
                round.underCount = round.underCount + 1
              end
              seen[#seen + 1] = variant
              under[#under + 1] = { itemID = itemID, key = key, unit = unit, qty = qty, vendor = vendor }
            end
          elseif not driver.known(itemID) then
            round.unknown = round.unknown + 1
            if not asked[itemID] and #ask < L.C.ASKS_PER_PAGE then
              asked[itemID] = true
              ask[#ask + 1] = itemID
            end
          end
        end
      end
    end
    return under, ask
  end

  --- The keys with lots this round has read of an item the board shows, shaped as a browse by the
  --- item's name leaves them (UI/SniperFrame.lua's GC.Sniper._named): the Check searches the
  --- cheapest. For an item under the vendor price, from its first such key on.
  function obj:Variants(itemID)
    return round and round.keys[itemID] or nil
  end

  --- Every item the round keeps keys of, with them.
  function obj:Tracked()
    return round and round.keys or {}
  end

  --- The round read both classes whole. Answers its figures, with `under`: the items it saw under
  --- the vendor price. A live row of any other item is of a lot that is gone.
  function obj:EndRound(now)
    local r = round
    round = nil
    if not r then return nil end
    return { seconds = now - r.startedAt, rows = r.rows, pages = r.pages, under = r.under,
      underCount = r.underCount, unknown = r.unknown, hits = r.hits }
  end

  --- The round was cut short (a scan, the player's own search, the auction house closing): what it
  --- saw proves nothing about the lots it did not reach.
  function obj:AbortRound() round = nil end

  --- A lot the board took as a new row waits for its Check.
  function obj:Push(itemID, unit, now)
    if round then round.hits = round.hits + 1 end
    for i = #queue, 1, -1 do
      if queue[i].itemID == itemID then table.remove(queue, i) end
    end
    queue[#queue + 1] = { itemID = itemID, unit = unit, at = now }
  end

  --- The waiting hits, oldest first, without those past HIT_WAIT_SECONDS.
  function obj:Waiting(now)
    for i = #queue, 1, -1 do
      if now - queue[i].at > L.C.HIT_WAIT_SECONDS then table.remove(queue, i) end
    end
    return queue
  end

  function obj:Take(itemID)
    for i = #queue, 1, -1 do
      if queue[i].itemID == itemID then return table.remove(queue, i) end
    end
    return nil
  end

  function obj:Clear()
    round, queue = nil, {}
  end

  return obj
end

--- The save's journal of the loop (GoldCapDB.foreverGearLoop, made by the first round, only on
--- Forever): the last rounds and the last lots found, for reading how the loop does in the game.
---   { v = 1, rounds = { "at seconds rows pages under unknown" }, hits = { "at key unit vVendor checkedAfter" } }
function L.Journal(root, create)
  if type(root) ~= "table" then return nil end
  local j = root.foreverGearLoop
  if j == nil and create then
    j = { v = 1, rounds = {}, hits = {} }
    root.foreverGearLoop = j
  end
  if type(j) ~= "table" or j.v ~= 1 or type(j.rounds) ~= "table" or type(j.hits) ~= "table" then return nil end
  return j
end

local function keep(list, line, cap)
  list[#list + 1] = line
  while #list > cap do table.remove(list, 1) end
end

function L.NoteRound(root, at, figures)
  local j = L.Journal(root, true)
  if not j or type(figures) ~= "table" then return end
  keep(j.rounds, ("%d %.1f %d %d %d %d"):format(at, figures.seconds or 0, figures.rows or 0,
    figures.pages or 0, figures.underCount or 0, figures.unknown or 0), L.C.KEEP_ROUNDS)
end

function L.NoteHit(root, at, keyText, unit, vendor, checkedAfter)
  local j = L.Journal(root, true)
  if not j then return end
  keep(j.hits, ("%d %s %d v%d %s"):format(at, keyText, unit, vendor,
    checkedAfter and ("%.1f"):format(checkedAfter) or "-"), L.C.KEEP_HITS)
end
