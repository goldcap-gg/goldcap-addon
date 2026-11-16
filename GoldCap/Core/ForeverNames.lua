local _, GC = ...

-- WoW: Forever: the names of the items the last full scan saw, kept in the save, so the BUY box
-- finds an item by its name with the auction house closed (UI/BuyLists.lua's KnownNames). The
-- owner typed "Forest" for Forest Mushroom Cap, which was on sale and not in the bags, and was
-- offered nothing (2026-11-16).
--
-- The client cannot be asked at the moment of typing. Measured the same day (the names probe,
-- 6,429 scanned ids): C_Item.GetItemNameByID named 1,087 of them after login and 511 after a scan,
-- and ten seconds later exactly 2,000 both times: asking loads a name, the client keeps about two
-- thousand, and the rest are let go. Asking all 6,429 took 13 ms. So the ids are walked a window at
-- a time: asked, read again a step later, and what answered is written down for good.
--
-- GoldCapDB.foreverNames = { v = 1, locale = "enUS", names = { [itemID] = "name" } }. The names are
-- the client's own, in its language: another language starts the table again.
--
-- The walk is pure: it is handed the clock, the ids and the client's answer.
GC.ForeverNames = GC.ForeverNames or {}
local N = GC.ForeverNames

N.C = {
  -- Ids asked a step, far under the two thousand the client keeps.
  WINDOW = 200,
  STEP_SECONDS = 2,
  -- An id the client never names (an item the game dropped) is let be after this many asks a
  -- session.
  TRIES = 3,
  -- How often the scan is looked over for ids with no name yet, once the walk has run dry.
  REFILL_SECONDS = 60,
}

--- The save's table for `locale`, made on first use; another locale's names are dropped.
function N.Store(root, locale, create)
  if type(root) ~= "table" or type(locale) ~= "string" then return nil end
  local s = root.foreverNames
  if type(s) ~= "table" or s.v ~= 1 or s.locale ~= locale or type(s.names) ~= "table" then
    if not create then return nil end
    s = { v = 1, locale = locale, names = {} }
    root.foreverNames = s
  end
  return s
end

--- Every kept name, as add(itemID, name).
function N.Each(add)
  local s = type(GC.db) == "table" and GC.db.foreverNames or nil
  if type(s) ~= "table" or type(s.names) ~= "table" then return end
  for itemID, name in pairs(s.names) do add(itemID, name) end
end

--- The walk. `driver`:
---   ids()          the item ids of the kept scan, as a set { [itemID] = anything }, or nil
---   nameOf(itemID) the client's name for the item now, or nil; asking is what loads it
---   names()        the table the names are written into, or nil when there is none to write to
function N.New(driver)
  local obj = {}
  local queue, at = {}, 1     -- ids still to ask
  local asked = {}            -- the window asked a step ago, read again now
  local tries = {}
  local nextStep, nextFill = 0, 0

  local function take(names, itemID)
    local name = driver.nameOf(itemID)
    if name then names[itemID] = name end
    return name ~= nil
  end

  --- One step, when it is due. Answers how many names it wrote.
  function obj:Tick(now)
    if now < nextStep then return 0 end
    nextStep = now + N.C.STEP_SECONDS
    local names = driver.names()
    if not names then return 0 end
    local wrote = 0
    -- What the last step asked has had a step to load.
    for i = 1, #asked do
      local itemID = asked[i]
      if take(names, itemID) then
        wrote = wrote + 1
      else
        tries[itemID] = (tries[itemID] or 0) + 1
      end
    end
    asked = {}
    if at > #queue then
      if now < nextFill then return wrote end
      nextFill = now + N.C.REFILL_SECONDS
      queue, at = {}, 1
      for itemID in pairs(driver.ids() or {}) do
        if type(itemID) == "number" and names[itemID] == nil and (tries[itemID] or 0) < N.C.TRIES then
          queue[#queue + 1] = itemID
        end
      end
    end
    for i = at, math.min(at + N.C.WINDOW - 1, #queue) do
      local itemID = queue[i]
      if take(names, itemID) then wrote = wrote + 1 else asked[#asked + 1] = itemID end
    end
    at = at + N.C.WINDOW
    return wrote
  end

  --- Ids of the queue not asked yet, and those waiting for their second read.
  function obj:Left() return math.max(#queue - at + 1, 0), #asked end

  return obj
end

-- The client. Runs only where this file is loaded (GoldCap_Camelot.toc), out of combat, from
-- twenty seconds after the addon loads.
if type(CreateFrame) == "function" then
  local walk = N.New({
    ids = function()
      local fold = GC.ForeverScan and GC.ForeverScan.Fold and GC.ForeverScan.Fold()
      return fold and fold.items or nil
    end,
    nameOf = function(itemID)
      local ok, name = pcall(C_Item.GetItemNameByID, itemID)
      return (ok and type(name) == "string" and name ~= "") and name or nil
    end,
    names = function()
      local locale = type(GetLocale) == "function" and GetLocale() or nil
      local s = N.Store(GC.db, locale, true)
      return s and s.names or nil
    end,
  })
  N._walk = walk
  local frame, since, up = CreateFrame("Frame"), 0, 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    since, up = since + elapsed, up + elapsed
    if since < 0.5 or up < 20 then return end
    since = 0
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    walk:Tick(GetTime())
  end)
end
