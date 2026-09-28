local _, GC = ...

-- /gc forever: what this client offers GoldCap, printed plainly so a player can paste it into a
-- bug report, and the full-scan probe that answers the open WoW: Forever scan questions. English
-- on purpose (a diagnostic, like the beta probe), so it adds no GC.L keys.
--
-- What the beta showed first (owner, build 1.60.1.70009): 1024 rows at +2 s and +5 s, none at
-- +10 s, and nothing at all for a second request after a /reload inside ~15 minutes. So this
-- probe reads the WHOLE dump at the first rows it sees (REPLICATE_ITEM_LIST_UPDATE or a poll,
-- whichever comes first), keeps polling to time the dump's life, and stamps
-- GoldCapDB.foreverScan.requestedAt -- the field Core/ForeverScan.lua's own cooldown reads -- so
-- a probe never spends the account's throttle twice.
GC.ForeverCheck = GC.ForeverCheck or {}

local POLL_SECONDS = 0.5
local WATCH_SECONDS = 40
local LINEN_CLOTH = 2589 -- a commodity the beta lists (spec: item 2589 isCommodity=true)

-- One number governs both this probe's throttle guess and Core/ForeverScan.lua's real one:
-- GC.ForeverScan.C.COOLDOWN_SECONDS (both read the same stamp, GoldCapDB.foreverScan.requestedAt).
-- Core/ForeverCheck.lua loads before Core/ForeverScan.lua (GoldCap.toc), so this can only be read
-- at call time, not at load time -- and a fallback covers a client that never loaded that module
-- at all (a spec, or a build that dropped it).
local function cooldownSeconds()
  return (GC.ForeverScan and GC.ForeverScan.C and GC.ForeverScan.C.COOLDOWN_SECONDS) or 15 * 60
end

local function realEnv()
  return {
    C_AuctionHouse = _G.C_AuctionHouse,
    AuctionHouseFrame = _G.AuctionHouseFrame,
    C_Timer = _G.C_Timer,
    CreateFrame = _G.CreateFrame,
    GoldCap_MarketData = _G.GoldCap_MarketData,
    GoldCap_AppData = _G.GoldCap_AppData,
    now = function() return time() end,
    clock = function() return type(_G.GetTime) == "function" and _G.GetTime() or time() end,
    realm = function() local ok, r = pcall(_G.GetRealmName) return ok and r or nil end,
    faction = function() local ok, f = pcall(_G.UnitFactionGroup, "player") return ok and f or nil end,
    portal = function() local ok, p = pcall(_G.GetCVar, "portal") return ok and p or nil end,
    store = function()
      if type(_G.GoldCapDB) ~= "table" then return nil end
      if type(_G.GoldCapDB.foreverScan) ~= "table" then _G.GoldCapDB.foreverScan = {} end
      return _G.GoldCapDB.foreverScan
    end,
    commodities = function() return GC.db and GC.db.commodityByItem or {} end,
    book = function() return GC.Sniper and GC.Sniper._bookPass and GC.Sniper._bookPass:Book() or nil end,
    lastPass = function() return GC.Sniper and GC.Sniper._lastPass or nil end,
    print = function(msg) if GC.Print then GC.Print(msg) else print(msg) end end,
    -- Plan 3e's client reads, looked up by name so a spec can hand in a client without them.
    global = function(name) return _G[name] end,
  }
end

local function has(t, name) return type(t) == "table" and type(t[name]) == "function" end
local function call(env, name) return env[name] and env[name]() or nil end

function GC.ForeverCheck.Report(env)
  env = env or realEnv()
  local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or nil
  local game = "unknown client"
  if p then
    if GC.Game.IsForever(p) then game = "WoW: Forever"
    elseif GC.Game.IsRetail(p) then game = "retail"
    else game = "another WoW client" end
  end
  local ah = env.C_AuctionHouse
  local deposit = "unavailable"
  if has(ah, "CalculateCommodityDeposit") then
    local ok, d = pcall(ah.CalculateCommodityDeposit, LINEN_CLOTH, 1, 1)
    -- Money always renders through GC.Util.CoinText (docs/addon/AGENTS.md "Money text"); the
    -- raw copper stays in parentheses because this line is a diagnostic, not a UI label. The
    -- raw figure goes through GC.Util.IntText, not %d: WoW's own string.format raises "integer
    -- overflow attempting to store N" past +-2^31 copper (Core/ForeverFold.lua's Encode hit
    -- exactly this on a live scan).
    if ok and type(d) == "number" then
      deposit = ("%s (%sc)"):format(GC.Util.CoinText(d), GC.Util.IntText(d))
    end
  end
  local copper = "unknown"
  if has(ah, "SupportsCopperValues") then
    local ok, s = pcall(ah.SupportsCopperValues)
    if ok then copper = tostring(s) end
  end
  local lines = {
    ("game: %s (interface %s, build %s, region id %s)"):format(
      game, p and tostring(p.interface) or "?", p and p.build or "?", p and tostring(p.regionId) or "?"),
    ("realm %s, faction %s, portal %s"):format(tostring(call(env, "realm")), tostring(call(env, "faction")),
      tostring(call(env, "portal"))),
    "retail price snapshot: " .. (env.GoldCap_MarketData and "loaded" or "not loaded"),
    "Companion data: " .. (env.GoldCap_AppData and "present" or "none"),
    "ReplicateItems: " .. (has(ah, "ReplicateItems") and "present" or "missing"),
    "GetNumReplicateItems: " .. (has(ah, "GetNumReplicateItems") and "present" or "missing"),
    ("deposit for 1 Linen Cloth (duration 1): %s; copper prices: %s"):format(deposit, copper),
  }
  -- Plan 3e's client reads. warcraft.wiki.gg lists every one for 1.60.1; this says whether this
  -- client really has them, and reads one live sample -- the chest's stats -- so a beta run shows
  -- the stat keys GetItemStats answers with (Core/ForeverUpgrades.lua's TOKENS read those keys).
  local function global(name) return env.global and env.global(name) or nil end
  local function present(yes) return yes and "present" or "missing" end
  local item, getStats, statsName = global("C_Item"), nil, "missing"
  if has(item, "GetItemStats") then
    getStats, statsName = item.GetItemStats, "C_Item.GetItemStats"
  elseif type(global("GetItemStats")) == "function" then
    getStats, statsName = global("GetItemStats"), "GetItemStats"
  end
  lines[#lines + 1] = ("3e reads: GetReplicateItemLink %s, item stats %s, C_TooltipInfo.GetHyperlink %s, C_PlayerInfo.CanUseItem %s")
    :format(present(has(ah, "GetReplicateItemLink")), statsName,
      present(has(global("C_TooltipInfo"), "GetHyperlink")), present(has(global("C_PlayerInfo"), "CanUseItem")))
  local map, mapID = global("C_Map"), nil
  if has(map, "GetBestMapForUnit") then
    local ok, id = pcall(map.GetBestMapForUnit, "player")
    mapID = ok and id or nil
  end
  lines[#lines + 1] = ("3e reads: GetLootSourceInfo %s, IsFishingLoot %s, C_Map.GetBestMapForUnit %s, map %s")
    :format(present(type(global("GetLootSourceInfo")) == "function"),
      present(type(global("IsFishingLoot")) == "function"), present(has(map, "GetBestMapForUnit")), tostring(mapID))
  local invLink, chest = global("GetInventoryItemLink"), nil
  if type(invLink) == "function" then
    local ok, link = pcall(invLink, "player", 5)
    chest = ok and type(link) == "string" and link or nil
  end
  if chest and getStats then
    local ok, stats = pcall(getStats, chest)
    local parts = {}
    if ok and type(stats) == "table" then
      for k, v in pairs(stats) do parts[#parts + 1] = ("%s=%s"):format(tostring(k), tostring(v)) end
      table.sort(parts)
    end
    lines[#lines + 1] = ("3e sample: chest %s stats %s"):format(chest, #parts > 0 and table.concat(parts, " ") or "none")
  else
    lines[#lines + 1] = "3e sample: " .. (chest and "no stats call" or "no chest item")
  end
  if GC.ForeverScan and GC.ForeverScan.Summary then
    for _, line in ipairs(GC.ForeverScan.Summary(env.now and env.now() or time())) do lines[#lines + 1] = line end
  end
  if GC.ForeverLoot and GC.ForeverLoot.Summary then
    for _, line in ipairs(GC.ForeverLoot.Summary()) do lines[#lines + 1] = line end
  end
  local crowd = GC.Data and GC.Data.ForeverPayload and GC.Data.ForeverPayload() or nil
  local sharing = GC.Data and GC.Data.CompanionShares and GC.Data.CompanionShares() and "on" or "off"
  lines[#lines + 1] = crowd
    and ("crowd prices: %d items, market %s, newest scan %ds old, sharing %s"):format(
      crowd.count, crowd.slug, (env.now and env.now() or time()) - crowd.ts, sharing)
    or ("crowd prices: none, sharing %s"):format(sharing)
  return lines
end

-- Every row of the dump, counted the ways the scan design needs. GetReplicateItemInfo(i) is
-- 0-based and returns, in order: name, texture, count, qualityID, usable, level, levelType,
-- minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
-- ownerFullName, saleStatus, itemID, hasAllInfo (Auctionator 339 reads [3], [10], [17], [18]).
-- The first row is printed raw so the positions can be checked on this client.
function GC.ForeverCheck.Walk(ah, n, commodities)
  local s = { rows = n, buyout = 0, bidOnly = 0, pending = 0, unreadable = 0, items = 0,
    commodityRows = 0, commodityItems = 0, linenRows = 0, linenUnits = 0, sample = "none" }
  for _, yes in pairs(commodities or {}) do
    if yes == true then s.commodityItems = s.commodityItems + 1 end
  end
  local first = { pcall(ah.GetReplicateItemInfo, 0) }
  if first[1] then
    local parts = {}
    for k = 2, 19 do parts[#parts + 1] = (k - 1) .. "=" .. tostring(first[k]) end
    s.sample = table.concat(parts, " ")
  end
  -- Plan 3e reads each gear row's link (Core/ForeverGear.lua); "if loaded", so a nil here on a
  -- fresh dump is a fact worth seeing, not an error.
  if has(ah, "GetReplicateItemLink") then
    local okL, link = pcall(ah.GetReplicateItemLink, 0)
    if okL and type(link) == "string" then s.link = link end
  end
  local seen = {}
  for i = 0, n - 1 do
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAll =
      pcall(ah.GetReplicateItemInfo, i)
    if not ok or type(itemID) ~= "number" then
      s.unreadable = s.unreadable + 1
    else
      if hasAll == false then s.pending = s.pending + 1 end
      local priced = type(buyout) == "number" and buyout > 0
      if priced then s.buyout = s.buyout + 1 else s.bidOnly = s.bidOnly + 1 end
      if not seen[itemID] then seen[itemID], s.items = true, s.items + 1 end
      if (commodities or {})[itemID] == true then s.commodityRows = s.commodityRows + 1 end
      if itemID == LINEN_CLOTH and type(count) == "number" and count > 0 then
        s.linenRows, s.linenUnits = s.linenRows + 1, s.linenUnits + count
        if priced then
          local unit = math.floor(buyout / count + 0.5)
          if not s.linenMin or unit < s.linenMin then s.linenMin = unit end
        end
      end
    end
  end
  return s
end

local function bookLine(env)
  local book, n = call(env, "book"), 0
  if type(book) == "table" then for _ in pairs(book) do n = n + 1 end end
  local last = call(env, "lastPass")
  return ("forever check: browse book this visit: %d items (last pass: %s)"):format(n,
    last and ("%s, %d results, %d pages"):format(tostring(last.kind), last.items or 0, last.pages or 0) or "none")
end

function GC.ForeverCheck.Run(env)
  env = env or realEnv()
  local say = env.print
  for _, line in ipairs(GC.ForeverCheck.Report(env)) do say("forever check: " .. line) end
  -- ReplicateItems is a server-side dump of the whole auction house under an account-wide
  -- throttle; run on retail this would fire it for no reason (3a final review M1).
  local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or nil
  if not (GC.Game and GC.Game.IsForever and GC.Game.IsForever(p)) then
    say("forever check: the full-scan test runs only in WoW: Forever"); return
  end
  local ah = env.C_AuctionHouse
  if not (has(ah, "ReplicateItems") and has(ah, "GetNumReplicateItems")) then
    say("forever check: ReplicateItems is missing -- no full scan in this client"); return
  end
  say(bookLine(env))
  local frame = env.AuctionHouseFrame
  if not (frame and frame.IsShown and frame:IsShown()) then
    say("forever check: open the auction house, then run /gc forever again to test the full scan"); return
  end
  local store = call(env, "store")
  local now = env.now()
  local last = store and store.requestedAt
  local since = type(last) == "number" and now - last or nil
  local cooldown = cooldownSeconds()
  if since and since >= 0 and since < cooldown then
    say(("forever check: last full-scan request %ds ago -- skipped, the auction house ignores another inside ~15 minutes (%d min left)")
      :format(since, math.ceil((cooldown - since) / 60)))
    return
  end
  say("forever check: last full-scan request: " .. (since and (since .. "s ago") or "none on record"))
  if store then store.requestedAt = now end

  local w = { t0 = env.clock(), read = false, events = {}, maxRows = 0, maxAt = 0 }
  local function elapsed() return env.clock() - w.t0 end
  local function readDump(trigger)
    if w.read then return end
    local okN, n = pcall(ah.GetNumReplicateItems)
    if not okN or type(n) ~= "number" or n <= 0 then return end
    w.read = true
    local s = GC.ForeverCheck.Walk(ah, n, call(env, "commodities"))
    -- Money always renders through GC.Util.CoinText; the raw copper stays in parentheses
    -- because this line is a diagnostic, not a UI label. GC.Util.IntText, not %d: this is a
    -- price straight off the live dump, which is exactly what overflowed WoW's own
    -- string.format on a live scan (Core/ForeverFold.lua's Encode).
    local cheapest = s.linenMin
      and ("%s (%sc)"):format(GC.Util.CoinText(s.linenMin), GC.Util.IntText(s.linenMin)) or "none"
    say(("forever check: dump read at +%.1fs (%s): %d rows, %d with a buyout, %d bid-only, %d missing item data, %d unreadable, %d distinct items, %d rows of %d known commodities, Linen Cloth: %d rows / %d units / cheapest %s")
      :format(elapsed(), trigger, s.rows, s.buyout, s.bidOnly, s.pending, s.unreadable, s.items,
        s.commodityRows, s.commodityItems, s.linenRows, s.linenUnits, cheapest))
    say("forever check: first row: " .. s.sample)
    say("forever check: first row link: " .. tostring(s.link))
  end

  local listener = env.CreateFrame and env.CreateFrame("Frame") or nil
  if listener then
    pcall(listener.RegisterEvent, listener, "REPLICATE_ITEM_LIST_UPDATE")
    listener:SetScript("OnEvent", function()
      local okN, n = pcall(ah.GetNumReplicateItems)
      w.events[#w.events + 1] = ("+%.1fs:%s"):format(elapsed(), okN and tostring(n) or "?")
      readDump("event")
    end)
  end
  local ok, err = pcall(ah.ReplicateItems)
  if not ok then
    if listener then pcall(listener.UnregisterEvent, listener, "REPLICATE_ITEM_LIST_UPDATE") end
    say("forever check: ReplicateItems failed: " .. tostring(err)); return
  end
  say("forever check: full scan requested; watching it for 40 s -- keep the auction house open")
  if not has(env.C_Timer, "After") then return end
  local function poll(t)
    local okN, n = pcall(ah.GetNumReplicateItems)
    n = okN and tonumber(n) or 0
    if n > 0 and not w.firstAt then w.firstAt, w.firstRows = t, n end
    if n > w.maxRows then w.maxRows, w.maxAt = n, t end
    if n == 0 and w.firstAt and not w.goneAt then w.goneAt = t end
    readDump("poll")
    if t + POLL_SECONDS <= WATCH_SECONDS then
      env.C_Timer.After(POLL_SECONDS, function() poll(t + POLL_SECONDS) end)
      return
    end
    if listener then pcall(listener.UnregisterEvent, listener, "REPLICATE_ITEM_LIST_UPDATE") end
    say(("forever check: timeline: first rows %s, most rows %d at +%.1fs, gone %s, events %d [%s]"):format(
      w.firstAt and ("at +%.1fs (%d)"):format(w.firstAt, w.firstRows) or "never", w.maxRows, w.maxAt,
      w.goneAt and ("at +%.1fs"):format(w.goneAt) or "not within 40 s", #w.events, table.concat(w.events, " ")))
  end
  env.C_Timer.After(POLL_SECONDS, function() poll(POLL_SECONDS) end)
end
