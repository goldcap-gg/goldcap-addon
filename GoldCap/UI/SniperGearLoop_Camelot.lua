local _, GC = ...

-- WoW: Forever's browse of all gear between scans (Core/ForeverGearLoop.lua says why and what was
-- measured). Loaded by GoldCap_Camelot.toc alone, after UI/SniperFrame.lua, whose two no-op hooks
-- it replaces (GC.Sniper._GearTurn, GC.Sniper._GearBrowse). Retail never loads it.
--
-- While Auto is on and the Items board is up, where Auto's own pass stands down, weapons and then
-- armor are browsed whole, round after round. A key listed under what a vendor pays becomes a row
-- of the Items board at once (GC.ForeverDeals.Live) and is given a live Check on the next turn,
-- by the key the round saw it under. So does a key far under what its own version sells for on the
-- house (GC.ForeverDeals.LiveMarket, ClickUp 1an60dzy9nt). It buys nothing: a purchase is the
-- player's click in the buy window, as for every other row.
--
-- One browse list serves everybody, so the loop keeps to the arbiter's rules:
--   * it sends only in a turn GC.Sniper.OnThrottleReady hands it, one message a turn, in the
--     pass's place of the pass/tail alternation, and never while a pass is armed or paging;
--   * it stands down for the full scan, the player's own search or pane, a purchase under way,
--     any board but Items, Auto off or paused, and a browse by an item's name;
--   * anybody else's browse sent while a round is out ends the round (the list is theirs now);
--   * a keys batch of ours waits for the class being read, and goes between two classes.
local Loop = GC.ForeverGearLoop
local S = GC.Sniper
if not (Loop and S and GC.BookPass and GC.ForeverDeals and GC.ForeverValue) then return end

local LIM = {
  STALL_SECONDS = 20,   -- a page not answered in this long is not coming: the round ends
  HOLD_SECONDS = 5,     -- how long a stop waits for the page on the wire before giving it up
  REST_SECONDS = 2,     -- after a round cut short
  GAP_SECONDS = 0.5,    -- between two classes: the turn a waiting keys batch goes in
  BETWEEN_SECONDS = 20, -- a round held between its classes this long starts over
  RING_SECONDS = 10,    -- the bell for a new lot, at most this often
}

local G = { on = false, classAt = 1, active = nil, sent = false, outAt = nil, stopping = false,
  sending = false, nextAt = 0, pokeAt = 0, ringAt = -LIM.RING_SECONDS, asked = {}, passes = {} }
S._gear = G

local function trace(tag)
  if GC.Util and GC.Util.Trace then GC.Util.Trace(tag) end
end

-- ClickUp 1an60dzy9nt: a key far under what its own version sold for on the house (GCF1's V,
-- GC.ForeverItemMarket's gear rule). It is screened against the dearest version's median first,
-- so the version -- the key's sample link, which the client answers right after the browse (HERO
-- probe P3, GC.Buy._VersionOfKey) -- is read only for a key that could be a deal at all. Gear the
-- site lists no versions of is measured against the item's own figure (S) when the key has no
-- suffix, and only once the payload tells versions apart at all: before V, S's figure may be every
-- version together. A key whose version the client did not say is counted (G.unread, the round's
-- journal line).
-- `refs` keeps a round's answers per item and version: a class holds many keys of one item.
local refs = {}
G.unread = 0
local function marketFor(itemID, key, unit)
  local IM, D = GC.ForeverItemMarket, GC.Data
  if not (IM and D and D.ForeverVersionsKnown and D.ForeverVersionsKnown()) then return nil end
  local rule = IM.C.GEAR
  local version
  local top = D.ForeverVersionTop(itemID)
  if top then
    if unit > math.floor(math.min(top, rule.maxRef - 1) * rule.share) then return nil end
    version = GC.Buy and GC.Buy._VersionOfKey and GC.Buy._VersionOfKey(itemID,
      { itemLevel = key.itemLevel or 0, itemSuffix = key.itemSuffix or 0, species = key.battlePetSpeciesID or 0 })
    if not version then
      G.unread = G.unread + 1
      return nil
    end
  elseif (key.itemSuffix or 0) ~= 0 then
    -- A suffixed key of an item the site lists no version of: S's figure is another version's.
    return nil
  end
  local slot = itemID .. ":" .. (version or "")
  local ref = refs[slot]
  if ref == nil then
    ref = IM.Reference(version and D.ForeverVersionSales(itemID, version) or D.ForeverSales(itemID), true) or false
    refs[slot] = ref
  end
  if not ref or unit > ref.ceiling then return nil end
  return { ref = ref, version = version, ceiling = ref.ceiling, vendor = GC.ForeverValue.VendorUnit(itemID, false),
    key = { itemLevel = key.itemLevel or 0, itemSuffix = key.itemSuffix or 0 } }
end

local rounds = Loop.New({
  vendorFor = function(itemID) return GC.ForeverValue.VendorUnit(itemID, false) end,
  known = function(itemID) return GC.ForeverValue.Known(itemID) end,
  listed = function(itemID) return GC.ForeverDeals.Listed(itemID) end,
  marketFor = marketFor,
  -- A new row waiting for its Check: a find for DEALS' AUTO readout, unless its item already had
  -- a row there (GC.ForeverDeals.Found counts each item once per appearance).
  onPush = function(itemID) GC.ForeverDeals.Found(itemID) end,
})
G.rounds = rounds

-- An item's keys, left where a browse by its name leaves them (GC.Sniper._named). An "Under market"
-- row is priced for one version, so its Check searches that version's key alone.
local function nameFrom(itemID, variants)
  local row = GC.ForeverDeals.LiveRow(itemID)
  if row and row.forever == "market" and row.keySuffix ~= nil and type(variants) == "table" then
    local only = {}
    for i = 1, #variants do
      local v = variants[i]
      if v.itemSuffix == row.keySuffix and v.itemLevel == row.keyLevel then only[#only + 1] = v end
    end
    if #only > 0 then variants = only end
  end
  S._named[itemID] = { at = GetTime(), entry = { itemID = itemID, variants = variants } }
end

-- A lot under the vendor price goes to the board. True when it is a new row there (or its price
-- moved): that one waits for its Check, and rings.
local function take(itemID, variant, settled)
  if GC.ForeverDeals.Live(itemID, variant.floor, variant.qty, variant.vendor, time(), settled) ~= "new" then
    return false
  end
  rounds:Push(itemID, variant.floor, GetTime())
  trace(("gear: %d/%d/%d at %d, vendor %d"):format(itemID, variant.itemLevel or 0, variant.itemSuffix or 0,
    variant.floor, variant.vendor))
  return true
end

local function repaint(rang)
  if S.OnForeverFold then S.OnForeverFold(true) end
  -- A new lot under its price is a deal, whether or not the bell may ring again yet.
  if rang and GC.AutoReadout then GC.AutoReadout.Note("deals") end
  local sniper = GC.db and GC.db.settings and GC.db.settings.sniper
  if rang and sniper and sniper.sound and GetTime() - G.ringAt >= LIM.RING_SECONDS then
    G.ringAt = GetTime()
    if GC.DealSound then GC.DealSound.Play(sniper) end
  end
end

-- The client is asked about an item with no kept vendor price: asking loads it, and its answer
-- (GET_ITEM_INFO_RECEIVED, below) is kept for every round after.
local function askAbout(list)
  for i = 1, #list do
    local itemID = list[i]
    if not GC.ForeverValue.VendorUnit(itemID) and not GC.ForeverValue.Known(itemID) then
      G.asked[itemID] = true
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    end
  end
end

-- A key far under what its version sells for goes to the board as an "Under market" row.
local function takeMarket(m, settled)
  if GC.ForeverDeals.LiveMarket(m.itemID, m.unit, m.qty, m.market, time(), settled) ~= "new" then return false end
  rounds:Push(m.itemID, m.unit, GetTime())
  trace(("gear: %s at %d, median %d (version %s)"):format(Loop.KeyText(m.key), m.unit, m.market.ref.ref,
    tostring(m.market.version)))
  return true
end

local function onRows(tail)
  local under, ask, market = rounds:Fold(tail)
  local fresh, touched = false, {}
  for i = 1, #under do
    local u = under[i]
    touched[u.itemID] = true
    local key = u.key
    if take(u.itemID, { floor = u.unit, qty = u.qty, vendor = u.vendor, itemLevel = key.itemLevel,
        itemSuffix = key.itemSuffix }) then
      fresh = true
    end
  end
  for i = 1, #market do
    touched[market[i].itemID] = true
    if takeMarket(market[i]) then fresh = true end
  end
  -- Its keys so far go to the Check at once: it searches the cheapest of them (an "Under market"
  -- row's own key), with no browse of its own.
  for itemID in pairs(touched) do nameFrom(itemID, rounds:Variants(itemID)) end
  askAbout(ask)
  if fresh then repaint(true) end
end

local function endRound()
  local figures = rounds:EndRound(GetTime())
  if not figures then return end
  G.lastRound = figures.seconds -- DEALS' AUTO readout
  refs = {}
  -- Every key of each item is read now: its row settles on the sighting that makes most -- the
  -- cheapest key under the vendor price, or a key far under its version's median -- and a row of
  -- an item the round saw neither way is of a lot that is gone.
  local fresh, seen = false, {}
  for itemID in pairs(figures.under) do seen[itemID] = true end
  for itemID in pairs(figures.market or {}) do seen[itemID] = true end
  for itemID in pairs(seen) do
    local sightings, best = {}, nil
    local under = figures.under[itemID] or {}
    for i = 1, #under do
      if not best or under[i].floor < best.floor then best = under[i] end
    end
    if best then sightings[1] = { unit = best.floor, qty = best.qty, vendor = best.vendor } end
    local market = figures.market and figures.market[itemID] or {}
    for i = 1, #market do
      sightings[#sightings + 1] = { kind = "market", unit = market[i].floor, qty = market[i].qty, info = market[i].market }
    end
    if GC.ForeverDeals.LiveBest(itemID, sightings, time()) == "new" then
      local row = GC.ForeverDeals.LiveRow(itemID)
      if row then rounds:Push(itemID, row.unitPrice, GetTime()) end
      fresh = true
    end
    local keys = {}
    for i = 1, #under do keys[#keys + 1] = under[i] end
    for i = 1, #market do keys[#keys + 1] = market[i] end
    nameFrom(itemID, keys)
  end
  local gone = GC.ForeverDeals.LiveKeep(seen)
  figures.unread = G.unread
  Loop.NoteRound(GC.db, time(), figures)
  trace(("gear: round %.1f s, %d rows, %d under vendor, %d under market, %d unknown, %d gone"):format(figures.seconds,
    figures.rows, figures.underCount, figures.marketCount or 0, figures.unknown, gone))
  if fresh or gone > 0 then repaint(fresh) end
end

local function classDone()
  G.active, G.sent, G.outAt, G.stopping = nil, false, nil, false
  -- The class is read whole: every key of each of its items the board shows is known, so their
  -- Checks, the fold's rows' too, search the cheapest key with no browse by name of their own.
  for itemID, variants in pairs(rounds:Tracked()) do nameFrom(itemID, variants) end
  G.classAt = G.classAt + 1
  if G.classAt > #Loop.C.CLASSES then
    G.classAt = 1
    endRound()
  end
  G.nextAt = GetTime() + LIM.GAP_SECONDS
end

-- Ours, for the hook below and for the player's-search hook (UI/AuctionHouseTab.lua).
local function sendOurs(fn, ...)
  local tab = GC.AuctionHouseTab
  G.sending = true
  if tab then tab.addonBrowse = true end
  local ok, err = pcall(fn, ...)
  if tab then tab.addonBrowse = false end
  if ok and GC.Util and GC.Util.NoteSend then GC.Util.NoteSend("gear") end
  G.sending = false
  G.outAt = GetTime()
  S._browseOutAt = time()
  if not ok then trace("gear: send failed: " .. tostring(err)) end
end

local function newPass(classID)
  return GC.BookPass.New({
    now = time,
    sendBrowseQuery = function(query)
      trace("gear: SendBrowseQuery class " .. classID)
      G.sent = true
      sendOurs(C_AuctionHouse.SendBrowseQuery, query)
    end,
    requestMoreBrowseResults = function() sendOurs(C_AuctionHouse.RequestMoreBrowseResults) end,
    hasFullBrowseResults = function() return C_AuctionHouse.HasFullBrowseResults() end,
    getBrowseResults = function() return C_AuctionHouse.GetBrowseResults() end,
    triggerFor = function() return nil end,
    onHit = function() end,
    onRows = onRows,
    onPassDone = classDone,
  }, { widePassSeconds = math.huge, itemClassFilters = { { classID = classID } } })
end
for i, classID in ipairs(Loop.C.CLASSES) do G.passes[i] = newPass(classID) end

-- Ends the round out: what it read says nothing of the keys it did not reach, so no row leaves
-- the board for it. The next round starts from the first class.
function G.Abort(why)
  local pass = G.active
  if not pass and not rounds:InRound() then return end
  G.active, G.sent, G.outAt, G.stopping = nil, false, nil, false
  if pass then pass:Abort() end
  rounds:AbortRound()
  refs = {}
  G.classAt = 1
  G.nextAt = GetTime() + LIM.REST_SECONDS
  trace("gear: round given up (" .. tostring(why) .. ")")
end

-- Whether the loop may ask the auction house anything now.
function G.MayRun(playerBusy)
  if not G.on or not S._AutoOnItems() then return false end
  local scan = GC.ForeverScan
  if not (scan and scan.Enabled and scan.Enabled()) then return false end
  if scan.IsBusy() or not scan.Fold() then return false end
  if playerBusy == nil then
    local tab = GC.AuctionHouseTab
    playerBusy = tab and tab.PlayerIsBusy and tab.PlayerIsBusy()
  end
  if playerBusy then return false end
  if S._bookPass:IsPaging() or S._bookPass:PendingStart() then return false end
  if S._KeysOutstanding() or S._BrowseOwned() or S._NamingBusy() then return false end
  if S.IsPurchaseQuiet() then return false end
  return true
end

-- A page of ours is out and may still be answered.
local function onWire()
  return G.outAt ~= nil and GetTime() - G.outAt <= LIM.HOLD_SECONDS
end

-- The new lots' Checks, oldest first: one query at most. A lot whose row has left the board, or
-- moved to another price, has nothing to check.
local function checkNext()
  local waiting = rounds:Waiting(GetTime())
  local list = {}
  for i = 1, #waiting do list[i] = waiting[i] end
  for i = 1, #list do
    local hit = list[i]
    local row = GC.ForeverDeals.LiveRow(hit.itemID)
    if not row or row.unitPrice ~= hit.unit then
      rounds:Take(hit.itemID)
    else
      local named = S._named[hit.itemID]
      if named then named.at = GetTime() end
      if S._CheckNow(row) then
        rounds:Take(hit.itemID)
        local key = named and named.entry and GC.KeyPoll.VariantKeyFor(named.entry, 0) or { itemID = hit.itemID }
        Loop.NoteHit(GC.db, time(), Loop.KeyText(key), hit.unit, row.refUnit, GetTime() - hit.at, row.forever)
        return true
      end
    end
  end
  return false
end

-- The arbiter's turn (GC.Sniper.OnThrottleReady). `last`: the tail had nothing to ask, so the turn
-- is the loop's whoever's it was. True when the turn is spent.
function S._GearTurn(playerBusy, last)
  if not G.on then return false end
  if not G.MayRun(playerBusy) then
    if G.active then
      -- A page still on the wire is waited for, with nothing else sent over it: its answer is
      -- this round's, and read as anybody else's it would be folded into theirs.
      if G.sent and onWire() then
        G.stopping = true
        return true
      end
      G.Abort("held")
    end
    return false
  end
  G.stopping = false
  if not last and checkNext() then return true end
  local pass = G.active
  if not pass or not pass:Wants() then return false end
  if not last and S._slotTurn == "tail" then return false end
  if pass:OnThrottleReady() then
    S._slotTurn = "tail"
    return true
  end
  return false
end

-- A browse answer (GC.Sniper.OnBrowseResults, OnBrowseResultsAdded). True when it is the loop's.
function S._GearBrowse(added)
  local pass = G.active
  if not pass or not G.sent then return false end
  -- A pass whose query is out owns the list (the loop never sends beside one).
  if S._bookPass:IsPaging() and not S._bookPass:PendingStart() then
    G.Abort("pass")
    return false
  end
  -- A keys batch written off just before this page went may still answer first.
  if S._keysOrphan and S._IsOrphanAnswer(C_AuctionHouse.GetBrowseResults()) then return true end
  G.outAt = nil
  if G.stopping then
    G.Abort("held")
    return true
  end
  pass:OnResultsAdded(added)
  return true
end

-- Four times a second while the auction house is open: starts a class when the loop may run,
-- ends a round that may not go on or whose page never came, and asks for the turn a waiting send
-- has nothing to ride on (an idle client that is ready already sends no readiness event).
function G.Tick()
  if not G.on then return end
  local now = GetTime()
  if G.active then
    if G.sent and G.outAt and now - G.outAt > LIM.STALL_SECONDS then return G.Abort("stall") end
    if not G.MayRun() then
      if G.sent and onWire() then G.stopping = true else G.Abort("held") end
      return
    end
  else
    if not G.MayRun() then
      -- Between two classes a hold is waited out (a keys batch goes there), but not for long: the
      -- class already read grows old, and the round's end would speak for lots long gone.
      if rounds:InRound() and now - G.nextAt > LIM.BETWEEN_SECONDS then G.Abort("held") end
      return
    end
    if now < G.nextAt then return end
    if not rounds:InRound() then
      rounds:BeginRound(now)
      G.unread = 0
      G.classAt = 1
    end
    G.active, G.sent, G.outAt, G.stopping = G.passes[G.classAt], false, nil, false
    G.active:Start("classes")
  end
  -- A class's first query is asked for at once; a page, which nearly always has a readiness event
  -- of its own coming, once a second at most.
  if G.active:Wants() and (G.active:PendingStart() or now - G.pokeAt >= 1) and GC.Util.ThrottleReady()
      and GC.Util.ClaimThrottleSend("sniper") then
    G.pokeAt = now
    S.OnThrottleReady()
  end
end

-- A keys batch of ours answers into the same list: held while a class is being read.
for _, name in ipairs({ "_TrySendKeysBatch", "_TrySendCapBatch" }) do
  local send = S[name]
  if type(send) == "function" then
    S[name] = function(...)
      if G.active then return false end
      return send(...)
    end
  end
end

-- A browse by an item's name that no Check of the player's waits on (the background walk's, a
-- hover's) waits while a class is read, as it does for a paging pass, and goes between two
-- classes: sent between two pages it would end every round the board has rows for. The player's
-- own Check carries its attempt and goes; the round ends for it (below).
local sendNaming = S._SendNaming
if type(sendNaming) == "function" then
  S._SendNaming = function(itemID, attempt)
    if G.active and not attempt then return "wait" end
    return sendNaming(itemID, attempt)
  end
end

-- Anybody else's browse replaces the list the round was paging: the player's, another addon's, a
-- pass, a browse by an item's name. The round ends there.
local function foreign()
  if G.active and G.sent and not G.sending then G.Abort("list taken") end
end
if type(hooksecurefunc) == "function" and C_AuctionHouse then
  for _, name in ipairs({ "SendBrowseQuery", "SearchForItemKeys", "SearchForFavorites" }) do
    if type(C_AuctionHouse[name]) == "function" then pcall(hooksecurefunc, C_AuctionHouse, name, foreign) end
  end
end

-- What became of a find (ClickUp 1an60dzy9nt): its Check's answer, from the one routing point every
-- live decision on a lot goes through (UI/SniperFrame.lua's evaluateLiveItemDeal), and the buy.
-- Written into the find's line of the save's journal, for reading where lots are lost.
function S._GearOutcome(itemID, decision, lotCount)
  if not GC.ForeverDeals.LiveRow(itemID) or type(decision) ~= "table" then return end
  local outcome
  if lotCount == 0 then
    outcome = "gone"
  elseif decision.candidate then
    outcome = "armed"
  else
    outcome = "refused:" .. tostring(decision.reasons and decision.reasons[1])
  end
  Loop.NoteOutcome(GC.db, itemID, outcome)
end

local bought = GC.ForeverDeals.Bought
function GC.ForeverDeals.Bought(itemID, qty)
  if GC.ForeverDeals.LiveRow(itemID) then Loop.NoteOutcome(GC.db, itemID, "bought") end
  return bought(itemID, qty)
end

-- The vendor price of an item the loop asked about is kept the moment the client has it.
local onItemInfo = GC.ForeverDeals.OnItemInfo
function GC.ForeverDeals.OnItemInfo(itemID)
  if onItemInfo then onItemInfo(itemID) end
  if G.asked[itemID] then
    G.asked[itemID] = nil
    GC.ForeverValue.Quality(itemID)
  end
end

-- The auction house opening and closing, on a frame of the loop's own: the Sniper's handlers
-- (GC.Sniper.OnAuctionHouseShow, OnAuctionHouseClosed) stay as they are.
function G.Open()
  G.on = true
  G.nextAt = GetTime() + LIM.REST_SECONDS
  G.ticker = G.ticker or C_Timer.NewTicker(0.25, G.Tick)
end

function G.Close()
  G.Abort("closed")
  G.on = false
  rounds:Clear()
  for i = 1, #G.passes do G.passes[i]:Reset() end
  if G.ticker then
    G.ticker:Cancel()
    G.ticker = nil
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then G.Open() else G.Close() end
end)
