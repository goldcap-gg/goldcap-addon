local ADDON_NAME, GC = ...

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
GC.version = getMeta and getMeta(ADDON_NAME, "Version") or "dev"

GC.DEFAULTS = {
  dbVersion = 1,
  -- D: flip queue (Sniper v2 §D) -- see Core/Data.lua's RecordFlip/GetFlips. An empty default
  -- table is safe against GC.Util.ApplyDefaults: it only fills db.flips in when the persisted
  -- value isn't already a table, and recursing over an empty table's pairs() is a no-op, so a
  -- populated SavedVariables array is never touched or truncated on later logins.
  flips = {},
  acquisitions = {},
  acquisitionPending = {},
  acquisitionRealized = {},
  acquisitionActivity = {},
  acquisitionSeq = 0,
  acquisitionPendingSeq = 0,
  acquisitionVersion = 0,
  mailOccurrences = {},
  mailOccurrenceSeq = 0,
  mailOccurrenceGeneration = 0,
  -- One-shot marker for the 2026-08-28 region repair (see the ADDON_LOADED handler below).
  ledgerRegionRepairVersion = 0,
  -- itemID -> true/false, "does this item sell as a commodity". Learned from
  -- C_AuctionHouse.GetItemKeyInfo, which only answers while the auction house is
  -- open, and remembered because the Sell tab lists bag stock wherever the player
  -- is standing. Getting this wrong files one item under two position keys (see
  -- UI/SellFrame.lua's classifyBagItem), so an unknown item is left out rather
  -- than guessed at. Same empty-table ApplyDefaults contract as `flips` above.
  commodityByItem = {},
  -- itemID -> { unit, at } (copper, epoch seconds): the Sell tab's own last resolved market
  -- quote, so a /reload shows the last known price and its age instead of a dash for the
  -- minutes it takes the pricing walk to catch back up. `levels` is deliberately never
  -- persisted here -- only a fresh walk's levels are usable for anything beyond the headline
  -- unit, and keeping them would just bloat the save file for no reader. See UI/SellFrame.lua's
  -- seedPersistedQuotes for the retention window that prunes this on the way back in. Same
  -- empty-table ApplyDefaults contract as `flips` above.
  sellQuotes = {},
  -- Live observations: bounded facts about the book the client just saw, for the companion
  -- to upload -- see Core/Data.lua's RecordLiveObservation. Same empty-table ApplyDefaults
  -- contract as `flips` above.
  liveObservations = {},
  -- Owned lots: the roster the Sell tab's own GetOwnedAuctions read already produces, kept
  -- for the companion to upload -- see Core/Data.lua's RecordOwnedLots. Same empty-table
  -- ApplyDefaults contract as `flips` above.
  ownedLots = {},
  -- Names the client resolved for items the site cannot name (Core/ItemNames.lua), for the
  -- Companion to upload. Same empty-table ApplyDefaults contract as `flips` above.
  itemNames = {},
  -- P2 ledger + gold curve. Same ApplyDefaults contract as `flips` above: an
  -- empty table default only fills in when the persisted value isn't already a
  -- table, so a populated SavedVariables array is never truncated on login.
  ledger = {},
  gold = {},
  -- Buy runs (companion "Runs" plan or a pasted GCR1 string) -- Core/AppRuns.lua. code ->
  -- { code, name, updatedAt, lines, origin = "app"|"paste" }. Same empty-table ApplyDefaults
  -- contract as `flips` above: a populated SavedVariables table is never touched or truncated.
  runs = {},
  -- Metadata for the companion-sourced half of `runs` above: which plan generated the file,
  -- how many lines the free tier gets, and when it was generated (so Adopt can tell a fresher
  -- file from a stale one already applied). generatedAt = 0 means "nothing adopted yet", which
  -- is always older than any real Unix timestamp the companion writes.
  runsMeta = { plan = "free", freeLines = 5, generatedAt = 0 },
  -- What each character has bought for each run, by run code: the BUY tab's "spent" and the
  -- bought count a partial fill continues from. Survives /reload; see UI/BuyFrame.lua's driver.
  buyProgress = {},
  -- A per-run price cap, whole percent of the run's own reference price, set from the BUY tab's
  -- run menu; absent means the global settings.sniper.buyCapPct. Same empty-table ApplyDefaults
  -- contract as `runs` above.
  runCaps = {},
  -- Runs the player has finished with, by code: they leave the BUY picker but stay in `runs`,
  -- because the companion re-adopts them on every sync anyway (Core/AppRuns.lua's Adopt).
  runsArchived = {},
  settings = {
    tooltip = true,
    -- "auto" follows GetLocale(); anything else is the player's own pick from Settings.
    -- That pick is the ONLY way to reach Ukrainian, which no WoW client reports (see
    -- Locale/Core.lua's LOCALE_CHOICES).
    locale = "auto",
    sniper = {
      autoOpen = true,
      auto = false,
      sound = true,
      -- Sell tab: post at the highest occupied rung the item's floor still reaches within a
      -- day, when the queue under it fits the item's own turnover (Flips.RecommendPost's
      -- overcut mode; docs/superpowers/specs/2026-09-10-sell-reach-pricing-design.md). On by
      -- default because the measurement says so; off posts at the cheapest ask instead.
      -- ApplyDefaults fills it in on existing saves.
      overcut = true,
      -- Whether the deals list shows rows the background live check has refused. Off by
      -- default: the point of checking in the background is that the list stops offering
      -- flips a Check has already ruled out. Owned by the Deals toolbar's own toggle (see
      -- UI/SniperFrame.lua's verifyBtn), which is also where the count of hidden rows lives,
      -- so a shorter list always arrives with the number that explains it.
      showRefused = false,
      -- Which of the Deals view's two boards is up: "commodities" (the scan's own finds, the
      -- only rows a live check can approve for buying) or "items" (the key poll's gear, pets
      -- and recipes -- leads, never buyable). Commodities by default because that is where the
      -- money is made and because the Items board costs a throttled search slot while it is
      -- open. Owned by the two chips at the top of the deals board (UI/SniperFrame.lua's
      -- GC.Sniper._SetBoard), which validates whatever it reads back -- anything but "items"
      -- is Commodities, so no migration is owed to a save written before this existed.
      board = "commodities",
      -- Items the owner has asked the watch loop to poll closely, in their own order. A
      -- standing instruction, so unlike the loop's own churn observations it survives the
      -- session. Same empty-table ApplyDefaults contract as `flips`.
      watchPins = {},
      -- Tier profit floors, in copper, measured against the WHOLE lot -- deliberately per-lot
      -- and not per-unit, because SniperDecision's own gate (requiredProfitFor) is per-lot too,
      -- so the preview and the live check keep speaking in the same unit: total gold out of
      -- this trade. A per-unit floor would rank a one-unit 51g flip identically to a fifty-unit
      -- one, which rewards exactly the trivial rows this list should be burying.
      --
      -- Both were cut tenfold (500g/100g -> 50g/10g) when discovery stopped multiplying by a
      -- day's sold volume and started using SniperDecision.DemandCap, the same quantity Check
      -- approves -- typically single digits rather than 200. Against the old floors almost
      -- nothing would ever have reached HOT or GOOD again and the board would have gone
      -- uniformly WATCH: measured on a 5,600-row synthetic spread, HOT+GOOD fell from 49.5%
      -- to 27.9% and collapsed hardest on cheap staples (10g items: 50% -> 9.4%). The 5:1
      -- ratio between them is unchanged. See migrateSniperTierProfit below for existing saves.
      hotDiscount = 0.40, hotProfit = 500000,
      goodDiscount = 0.25, goodProfit = 100000,
      -- Stamped by ApplyDefaults for a fresh database; migrateSniperTierProfit stamps it for
      -- an existing one, so the tenfold cut is applied exactly once per save.
      tierProfitVersion = 1,
      watchDiscount = 0.10, suspectDiscount = 0.90,
      -- Liquidity floors, sold per day (from a realm import's soldPerDay); only enforced
      -- against import-sourced values, see DealMath.Evaluate.
      hotMinSold = 3, goodMinSold = 1,
      -- Anti-dump gate (Sniper v2): units are whole percent, matching the
      -- import string's signed trend field; a deal whose 24h market-value
      -- trend is <= -dumpTrendPct is capped below GOOD, see DealMath.Evaluate.
      dumpTrendPct = 10,
      -- How long a posted auction runs: 1 = 12h, 2 = 24h, 3 = 48h, matching the `duration`
      -- argument C_AuctionHouse.PostCommodity/PostItem take. 2 preserves what UI/SellFrame.lua
      -- had hardcoded, so an existing save keeps posting exactly as it did and needs no
      -- migration -- ApplyDefaults fills the field in on the next login.
      --
      -- Filed under `sniper` with every other setting rather than under a new `sell` branch:
      -- UI/SettingsFrame.lua's cfg() reads this one table, `settings.tooltip` is already the
      -- lone exception at the top level, and inventing a second branch for a single field
      -- would buy structure nobody reads at the cost of a second accessor.
      postDuration = 2,
      maxCapitalShare = 0.05,
      maxDailyDemandShare = 0.02,
      maxQuantity = 200,
      minimumProfitCopper = 50000,
      profitFloorVersion = 1,
      -- Same reason as profitFloorVersion above: stamped here so ApplyDefaults versions a
      -- FRESH database immediately, before migrateSniperWindowWidth ever runs on it -- without
      -- this a brand-new save had no version at all, so the very first resize the player made
      -- looked identical to an untouched pre-rail save and got widened by the rail's 76px on
      -- its very next login.
      windowWidthVersion = 1,
      minimumRoi = 0.10,
      -- Velocity release for the stress exit (SniperDecision.Evaluate): a leftover cheap wall
      -- amounting to no more than this many hours of the item's measured daily sales is
      -- treated as turnover, not competition, and the exit prices at stressUnit instead of
      -- undercutting it. 0 disables the release (every partial wall is competition again);
      -- normalizeConfig caps it at 6. ApplyDefaults fills this in on existing saves.
      wallAbsorbHours = 2,
      -- Above this 24h market-value trend (whole percent) a stress exit counts as
      -- spike-contaminated and deflates to the pre-spike estimate, on both the buy side
      -- (SniperDecision.Evaluate, via its config) and the sell-side queue ceiling
      -- (Flips.RecommendPost, via SellPositions). SniperDecision.SPIKE_TREND_PCT documents
      -- the mechanism and stays as the fallback; normalizeConfig clamps this to 1-500.
      -- ApplyDefaults fills it in on existing saves.
      spikeTrendPct = 30,
      -- Sniper v3 T10: UI-only scale multiplier for Theme's fonts (0.9-1.3), persisted so a
      -- player's chosen text size survives relog. Read back once GC.db exists (see this file's
      -- ADDON_LOADED handler below) and re-written by UI/Theme.lua's SetScale itself on every
      -- change (the settings panel's font-scale slider), not by UI/SettingsFrame.lua directly.
      fontScale = 1.0,
      -- Check panel v2: the evidence grid defaults open where the drawer fits -- the F5 guard
      -- in UI/SniperFrame.lua's applyDetailsState still closes it on a short window, and the
      -- toggle itself keeps persisting whatever the player actually chooses from here on.
      dialogDetailsOpen = true,
      -- Same reason as windowWidthVersion above: stamped here so ApplyDefaults versions a
      -- FRESH database immediately, before migrateSniperDialogDetails ever runs on it --
      -- without this a brand-new save would carry no version at all, so its very first real
      -- toggle-off would look identical to an unversioned pre-open-by-default save and get
      -- silently reopened by the migration on its next login.
      dialogDetailsOpenVersion = 1,
      -- Buy runs (Core/AppRuns.lua): how far over the run's own recorded price a lot may cost
      -- and still count as "still cheap enough to buy", as a whole percent of that price (130
      -- = up to 30% over). Filed under `sniper` for the same reason postDuration is above --
      -- one settings table UI/SettingsFrame.lua already reads, not a second branch for one field.
      buyCapPct = 130,
      -- buyRun: undeclared here on purpose (a nil-valued table field is never actually stored,
      -- so ApplyDefaults' pairs() walk would just skip it either way). The run code last shown
      -- in the Buy Runs panel, so reopening it returns to where the player left off; written by
      -- whatever UI shows that panel, read back the same way `window` below is.
      -- window: undeclared here on purpose (a nil-valued table field is never actually
      -- stored, so ApplyDefaults' pairs() walk would just skip it either way). Populated by
      -- UI/SniperFrame.lua's persistWindowGeometry as { point, x, y, width, height } (Sniper
      -- v3: width joined height once the window became width-resizable, not just height) --
      -- called via hooksecurefunc(frame, "StopMovingOrSizing", ...) rather than an
      -- OnDragStop/OnMouseUp script, since that one native method covers both the title bar
      -- drag and the resize-grip drag regardless of which triggered it. Read back by
      -- createFrame to restore position/size, defaulting to CENTER / FRAME_WIDTH x
      -- FRAME_HEIGHT until then.
    },
  },
}

GC.slashHandlers = GC.slashHandlers or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED")
frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
frame:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
frame:RegisterEvent("COMMODITY_PRICE_UPDATED")
frame:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
frame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
frame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
-- The client's own error channel. Observed live 2026-09-11: the red "Internal auction error."
-- over the auction house columns arrived with NO commodity terminal event and NO search result
-- behind it, so every wait the Sniper had open at that moment waited for something that never
-- came. One payload argument, `error` (Enum.AuctionHouseError -- warcraft.wiki.gg's
-- AUCTION_HOUSE_SHOW_ERROR); see UI/SniperFrame.lua's GC.Sniper.OnAuctionHouseError.
frame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
-- D: Sell view posting signals (verified against Blizzard_AuctionHouseUI's
-- AuctionHouseFrameMixin:OnEvent, which reacts to both the same way: AUCTION_HOUSE_AUCTION_CREATED
-- fires with no addon-usable per-post identity, and AUCTION_HOUSE_POST_ERROR the same -- GC.Sell
-- correlates either to its own single in-flight post via a local pinned-row slot, not the event
-- payload).
frame:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
frame:RegisterEvent("AUCTION_HOUSE_POST_ERROR")
-- Task 9: fires after C_AuctionHouse.QueryOwnedAuctions({}) resolves (tab show or the Sell
-- tab's own ghost Refresh button -- see UI/SellFrame.lua) AND after any other change to the
-- player's own listed lots (a post going through, an in-flight repost's CancelAuction landing).
-- No payload -- the handler re-reads C_AuctionHouse.GetOwnedAuctions() itself.
frame:RegisterEvent("OWNED_AUCTIONS_UPDATED")
-- Task 9 fix round 1 (minor: deterministic post-cancel refresh): AUCTION_CANCELED is not a
-- documented/stable event on every client build -- RegisterEvent throws for an unknown event
-- name, which would abort the WHOLE frame's event registration (everything below this line)
-- mid-list. pcall-guarded so a bad event name only loses this one, optional, refresh signal
-- instead of the rest of the addon. Dispatched identically to OWNED_AUCTIONS_UPDATED below.
pcall(function() frame:RegisterEvent("AUCTION_CANCELED") end)
-- P2 ledger. MAIL_SHOW/MAIL_INBOX_UPDATE are the ONLY chance to read an
-- invoice: once the player collects a mail it is gone from the client
-- entirely, so a scan that waited for collection would record nothing.
-- PLAYER_MONEY drives the gold curve (debounced inside the module);
-- PLAYER_LOGOUT forces the session's last reading, because SavedVariables are
-- flushed to disk at exactly that moment.
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
-- Sniper v3 §3: MAIL_CLOSED has no ledger use (there's nothing left to scan once the mailbox
-- closes) -- registered purely so the Sniper's Auto mode can resume once the player's done
-- with mail. MAIL_SHOW is forwarded to the Sniper too, below, alongside its existing ledger use.
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("PLAYER_MONEY")
-- BAG_UPDATE_DELAYED, not BAG_UPDATE: the delayed form fires once after a burst of container
-- changes, which is exactly the granularity a re-count of "what have I already got" wants.
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_LOGOUT")
-- Task 2 (item names from the client): the wanted-list walk needs the world loaded (item
-- data is not reliably queryable at ADDON_LOADED) and needs to hear back when the client
-- resolves an id it did not have cached yet. Core/ItemNames.lua.
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function migrateSniperProfitFloor(db)
  local settings = type(db) == "table" and db.settings or nil
  local sniper = type(settings) == "table" and settings.sniper or nil
  if type(sniper) ~= "table" or sniper.profitFloorVersion ~= nil then return end
  -- The old 100g value was implicit and had no settings control. Move only that exact legacy
  -- default; preserve any manually edited value. ApplyDefaults stamps the version for new DBs.
  if sniper.minimumProfitCopper == 1000000 then sniper.minimumProfitCopper = 50000 end
  sniper.profitFloorVersion = 1
end

-- The tier floors below were sized for a lot of up to 200 units, because that is what discovery
-- used to propose. Discovery now proposes what SniperDecision.DemandCap would approve, which is
-- usually single digits, so a floor of 500g per lot became unreachable for everything but
-- high-ticket items -- see GC.DEFAULTS above. Cut both tenfold, once.
--
-- Same contract as migrateSniperProfitFloor: move ONLY the exact legacy defaults, so a value a
-- player edited by hand survives untouched (neither field has ever had a settings control, so
-- any non-default value here is deliberate), and stamp the version so this never runs twice.
-- ApplyDefaults stamps it for a database that has no sniper settings at all yet.
local function migrateSniperTierProfit(db)
  local settings = type(db) == "table" and db.settings or nil
  local sniper = type(settings) == "table" and settings.sniper or nil
  if type(sniper) ~= "table" or sniper.tierProfitVersion ~= nil then return end
  if sniper.hotProfit == 5000000 then sniper.hotProfit = 500000 end
  if sniper.goodProfit == 1000000 then sniper.goodProfit = 100000 end
  sniper.tierProfitVersion = 1
end

-- Batch-1's rail consumed 76px of every window's content area, so a width a
-- player chose before the rail shows 76px less list than they chose it for.
-- One-time: hand those 76px back. 1100 mirrors WIN.RESIZE_MAX_WIDTH.
local function migrateSniperWindowWidth(sniper)
  if sniper.windowWidthVersion ~= nil then return end
  sniper.windowWidthVersion = 1
  local window = sniper.window
  if type(window) == "table" and type(window.width) == "number" then
    window.width = math.min(window.width + 76, 1100)
  end
end

-- Earlier builds seeded dialogDetailsOpen = false from the dialog's own construction (UI/
-- SniperFrame.lua's createDialog, before the toggle or a saved preference ever ran), not from
-- a player choice -- so every save written before the evidence grid became open-by-default
-- carries a plain, unversioned false that ApplyDefaults will never touch (it only fills in
-- nil fields). This one-time reset gives every such profile the open default once; the
-- toggle's own writes (UI/SniperFrame.lua's applyDetailsState) stick afterwards, same contract
-- as migrateSniperProfitFloor/migrateSniperTierProfit above.
local function migrateSniperDialogDetails(db)
  local s = db.settings and db.settings.sniper
  if not s then return end
  if (s.dialogDetailsOpenVersion or 0) < 1 then
    s.dialogDetailsOpen = true
    s.dialogDetailsOpenVersion = 1
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end
    GoldCapDB = GoldCapDB or {}
    -- Damaged purchase records used to stop the load dead here: this returned with GC.db
    -- never published and the event unregistered, so nothing else in the addon existed --
    -- no window, no slash commands, no tooltips -- and not one word said why. It now says
    -- so and carries on without that one feature. Init(nil) leaves the acquisitions module
    -- with no database at all, so each of its entry points refuses (every one of them opens
    -- with `if not db`) rather than writing into the damaged table.
    local acquisitionsInitialized = not GC.Acquisitions or GC.Acquisitions.Init(GoldCapDB)
    local damagedAcquisitions
    if not acquisitionsInitialized then
      GC.Acquisitions.Init(nil)
      -- Held across the defaults pass below, which would otherwise replace a store that is not
      -- a table at all with an empty one -- quietly destroying whatever a human might still
      -- have recovered from it. Damaged is not the same as worthless.
      damagedAcquisitions = GoldCapDB.acquisitions
    end
    migrateSniperProfitFloor(GoldCapDB)
    migrateSniperTierProfit(GoldCapDB)
    local sniper = GoldCapDB.settings and GoldCapDB.settings.sniper or nil
    if type(sniper) == "table" then migrateSniperWindowWidth(sniper) end
    migrateSniperDialogDetails(GoldCapDB)
    if GC.Util then GC.Util.ApplyDefaults(GoldCapDB, GC.DEFAULTS) end
    if damagedAcquisitions ~= nil then GoldCapDB.acquisitions = damagedAcquisitions end
    GC.db = GoldCapDB
    -- Before any frame is built: every widget reads its label through GC.L at construction,
    -- so the active language has to be settled first. After ApplyDefaults, because it reads
    -- settings.locale.
    if GC.ApplyLocale then GC.ApplyLocale() end
    -- Said AFTER the language is settled, so the one line explaining a lost feature is not
    -- the only English sentence in an otherwise translated addon.
    if not acquisitionsInitialized and GC.Print then
      GC.Print(GC.L["your saved purchase records are damaged -- cost tracking is off, the rest of GoldCap is running"])
    end
    -- Anything resolved through GC.L at FILE scope would have captured the English
    -- fallback, since every file loads before the line above picks a language. The
    -- keybinding label is the one such value that cannot wait to be read lazily.
    if GC.SellUI_RefreshBindingName then GC.SellUI_RefreshBindingName() end
    if GC.Data then
      GC.Data.Init(GC.db)
      -- Companion sync (Task A): adopts `GoldCap_AppData` (see the .toc's OptionalDeps)
      -- over any existing import when it's present and strictly newer -- see
      -- Core/Data.lua's AdoptAppData for the full contract. Runs after Init above so
      -- db.imported already reflects the prior session's state to compare against.
      GC.Data.AdoptAppData()
      -- A snapshot adopted in an earlier session is just as wrong as one pasted now, and
      -- nothing else revisits it -- SetImported only fires when an import actually lands.
      if GC.Data.WarnRegionMismatch then GC.Data.WarnRegionMismatch() end
    end
    if GC.AppLedger then
      -- Sold tab: adopt the companion-written ledger summary the same way
      -- AdoptAppData above adopts prices -- once, at load, memory only.
      GC.AppLedger.Adopt()
    end
    if GC.AppRuns then
      -- Buy runs: adopt `GoldCap_AppRuns` the same way AppLedger.Adopt above adopts the ledger
      -- summary. The companion writes its file at Interface/AddOns/GoldCap_AppData/Runs.lua,
      -- and the client only reads that file (into the `_G.GoldCap_AppRuns` this call reads)
      -- when the addon's files load -- at login or on a full /reload -- so a run the companion
      -- wrote mid-session is invisible until one of those happens. This call catches the
      -- login/reload case; the AUCTION_HOUSE_SHOW handler below calls Adopt again so a
      -- /reload the player did mid-session (for any unrelated reason) is picked up the next
      -- time the Auction House opens, rather than waiting for the next full login.
      GC.AppRuns.Adopt()
    end
    if GC.Ledger then GC.Ledger.Init(GC.db) end
    if GC.Acquisitions and acquisitionsInitialized then
      GC.Acquisitions.MigrateLegacy(GoldCapDB.flips, GC.Ledger and GC.Ledger.GetEntries() or {})
      -- One-shot cleanup of phantom mail-buy duplicates (2026-08-17 incident); says what it
      -- deleted, because silently editing the cost base is exactly what phantoms did.
      local repaired = GC.Acquisitions.RepairDuplicateMailBuys
        and GC.Acquisitions.RepairDuplicateMailBuys() or 0
      -- Two whole sentences, not one with an "s" posted into it: that trick is English
      -- grammar wearing a format specifier, and every translation of it came back with the
      -- English suffix glued into the middle of a German or Russian word.
      if repaired > 0 and GC.Print then
        GC.Print((repaired == 1
          and GC.L["removed %d duplicate purchase record left by a mail-scan bug"]
          or GC.L["removed %d duplicate purchase records left by a mail-scan bug"]):format(repaired))
      end
      -- Same announcement rule for the 2026-08-19 double-scan sale duplicates.
      local rescanned = GC.Acquisitions.RepairRescannedMailSales
        and GC.Acquisitions.RepairRescannedMailSales() or 0
      if rescanned > 0 and GC.Print then
        GC.Print((rescanned == 1
          and GC.L["removed %d duplicate sale record left by a mail-scan bug"]
          or GC.L["removed %d duplicate sale records left by a mail-scan bug"]):format(rescanned))
      end
    end
    -- One-shot repair of the 2026-08-28 region defect: rows stamped with the region of the
    -- last IMPORT instead of the region the character plays in (see GC.Ledger.Context and
    -- GC.Data.ClientRegion). Runs after Acquisitions is up, because a repaired SALE has to
    -- be offered back to reconciliation -- its position was left open when the sale first
    -- arrived under a region no purchase of it could share, and nothing else would ever
    -- retry it: mail reconciliation only fires for rows a fresh inbox scan produces.
    if GC.Ledger and GC.Ledger.RepairCharacterRegions
        and GoldCapDB.ledgerRegionRepairVersion ~= 1 then
      local context = GC.Ledger.Context and GC.Ledger.Context() or {}
      local repairedRows = GC.Ledger.RepairCharacterRegions(context.char, context.region)
      GoldCapDB.ledgerRegionRepairVersion = 1
      local reconciled = 0
      if GC.Acquisitions and GC.Acquisitions.ReconcileSale then
        for _, entry in ipairs(repairedRows) do
          if entry.kind == "sale" then
            local result = GC.Acquisitions.ReconcileSale(entry)
            if type(result) == "table" and result.status == "applied" then reconciled = reconciled + 1 end
          end
        end
      end
      -- Two plain counts, no "record%s" plural trick: this string has to survive eleven
      -- translations, and the trick only ever worked in English anyway.
      if #repairedRows > 0 and GC.Print then
        GC.Print((GC.L["region corrected on %d ledger rows; %d sales matched back to their stock"])
          :format(#repairedRows, reconciled))
      end
    end
    if GC.PurchaseCapture and GC.PurchaseCapture.Init and hooksecurefunc and C_AuctionHouse then
      GC.PurchaseCapture.Init({
        hooksecurefunc = hooksecurefunc,
        getNumItemSearchResults = function(itemKey) return C_AuctionHouse.GetNumItemSearchResults(itemKey) end,
        getItemSearchResultInfo = function(itemKey, index)
          return C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        end,
        time = time,
        after = function(seconds, callback)
          if C_Timer and C_Timer.After then C_Timer.After(seconds, callback) end
        end,
      }, GC.Ledger and GC.Ledger.Context or nil)
    end
    -- Sniper v3 T10: apply the persisted font-scale multiplier as soon as GC.db exists, NOT
    -- gated on the Sniper window ever being built -- UI/SniperFrame.lua's window frame is
    -- created lazily (first Toggle()/AH visit), so a player who never opens the Sniper this
    -- session would otherwise never get their saved scale applied. GC.Theme itself is never
    -- lazy: UI/Theme.lua loads unconditionally, earlier in the .toc, so GC.Theme.SetScale
    -- already exists here regardless of whether any UI frame has been constructed yet -- this
    -- only updates Theme's own module-local scale (there are no live widgets to re-font yet),
    -- so later widget construction (Theme.Label/Num/Chip/etc. all read the current scale at
    -- creation time) picks up the right size from the very first frame, with no dependency on
    -- UI file load order beyond Theme.lua itself already having run.
    if GC.Theme and GC.db.settings and GC.db.settings.sniper then
      GC.Theme.SetScale(GC.db.settings.sniper.fontScale)
    end
    frame:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
    local interactionType = ...
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
      GC.Util.Trace("ah: show")
      -- Buy runs: re-adopt `GoldCap_AppRuns` here (see the ADDON_LOADED handler above for the
      -- full contract) so a /reload the player did mid-session picks up a run the companion
      -- wrote in between, by the next time the board that shows it actually matters.
      if GC.AppRuns then GC.AppRuns.Adopt() end
      -- The BUY tab too: a new session cannot answer for the last one, so what the last one left
      -- half-finished is cleared here rather than carried into a book that has since moved.
      if GC.Buy and GC.Buy.OnAuctionHouseShow then GC.Buy.OnAuctionHouseShow() end
      GC.Sniper.OnAuctionHouseShow()
    end
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local interactionType = ...
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
      GC.Util.Trace("ah: closed")
      GC.Sniper.OnAuctionHouseClosed()
      -- The BUY tab too: no terminal commodity event can arrive once the session is gone, so an
      -- attempt left standing holds the shared purchase slot and keeps the passive capture stood
      -- down for that item until /reload.
      if GC.Buy and GC.Buy.OnAuctionHouseClosed then GC.Buy.OnAuctionHouseClosed() end
      if GC.PurchaseCapture then GC.PurchaseCapture.Reset() end
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    GC.Util.NoteThrottleEvent(event)
    -- A DROPPED message is the client saying it threw our request away, so the reply it was
    -- going to answer with is never coming. Counting it and doing nothing else meant whatever
    -- was waiting on that reply sat there until its own timeout -- eight seconds of a dead
    -- search slot, and a fence behind it -- when the answer was already known.
    if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" and GC.Sniper.OnThrottledMessageDropped then
      GC.Sniper.OnThrottledMessageDropped()
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    GC.Util.NoteThrottleEvent(event)
    -- The scanner is NOT woken here any more. It is one of two background consumers of a
    -- single search slot, and calling it first meant it took every slot ahead of the browse
    -- scan -- see UI/SniperFrame.lua's OnThrottleReady, which now owns that decision. Result
    -- routing (OnKeyInfo/OnItemResults/OnCommodityResults below) stays here: that is delivery,
    -- not allocation.
    if GC.Sniper.OnThrottleReady then GC.Sniper.OnThrottleReady() end
    if GC.Sell.OnThrottleReady then GC.Sell.OnThrottleReady() end
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
    local itemID = ...
    if GC.Sniper.scanner then
      GC.Sniper.scanner:OnKeyInfo(itemID)
    end
    if GC.Sniper.OnItemKeyInfo then
      GC.Sniper.OnItemKeyInfo(itemID)
    end
    if GC.Sell.OnItemKeyInfo then
      GC.Sell.OnItemKeyInfo(itemID)
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemKey = ...
    -- The payload is documented as an itemKey, and every line below reads a field off it.
    -- A client that fires this event with nothing attached would take the whole event frame
    -- down with an index-a-nil error -- taking mail scanning, the ledger and the auction
    -- house tab with it, because they all share this one handler.
    if type(itemKey) ~= "table" or not itemKey.itemID then return end
    if GC.Sniper.scanner then
      GC.Sniper.scanner:OnItemResults(itemKey.itemID)
    end
    if GC.Sniper.OnItemSearchResults then
      GC.Sniper.OnItemSearchResults(itemKey.itemID)
    end
    -- D: GC.Sell's own handler only reacts when itemKey.itemID matches its own pending quote
    -- slot -- see SellFrame.lua's OnItemSearchResults -- so this adds zero crosstalk with the
    -- scanner's or the buy-requery's unrelated in-flight searches.
    if GC.Sell.OnItemSearchResults then
      GC.Sell.OnItemSearchResults(itemKey.itemID)
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnItemSearchResults(itemKey) end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local itemID = ...
    if GC.Sniper.scanner then
      GC.Sniper.scanner:OnCommodityResults(itemID)
    end
    if GC.Sniper.OnCommoditySearchResults then
      GC.Sniper.OnCommoditySearchResults(itemID)
    end
    if GC.Sell.OnCommoditySearchResults then
      GC.Sell.OnCommoditySearchResults(itemID)
    end
    if GC.Buy and GC.Buy.OnCommodityResults then
      GC.Buy.OnCommodityResults(itemID)
    end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if GC.Sniper.OnPurchaseCompleted then
      local auctionID = ...
      GC.Sniper.OnPurchaseCompleted(auctionID)
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnPurchaseCompleted(...) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    -- Terminal commodity events carry no attempt id, so nothing in the payload can say whose they
    -- are. They are OFFERED to the BUY tab first and only passed on when it says it did not take
    -- them -- GC.Buy's handlers answer true when they consumed the event.
    --
    -- Not gated on GC.PurchaseSlot.Owner() == "buy" here any more, deliberately: the branch that
    -- books the late success of a confirm BUY had given up on runs precisely when BUY no longer
    -- holds the slot (it released it on the way out), so an ownership gate made that whole path
    -- unreachable and handed those successes to the Sniper. GC.Buy.mayOwnTerminal is where the
    -- "can this be ours" question now lives, slot included.
    local unitPrice, totalPrice = ...
    if not (GC.Buy and GC.Buy.OnCommodityPriceUpdated
        and GC.Buy.OnCommodityPriceUpdated(unitPrice, totalPrice)) then
      if GC.Sniper.OnCommodityPriceUpdated then GC.Sniper.OnCommodityPriceUpdated(unitPrice, totalPrice) end
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPriceUpdated(...) end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if not (GC.Buy and GC.Buy.OnCommodityPriceUnavailable and GC.Buy.OnCommodityPriceUnavailable()) then
      if GC.Sniper.OnCommodityPriceUnavailable then GC.Sniper.OnCommodityPriceUnavailable() end
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPriceUnavailable() end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if not (GC.Buy and GC.Buy.OnCommodityPurchaseSucceeded and GC.Buy.OnCommodityPurchaseSucceeded()) then
      if GC.Sniper.OnCommodityPurchaseSucceeded then GC.Sniper.OnCommodityPurchaseSucceeded() end
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPurchaseSucceeded() end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if not (GC.Buy and GC.Buy.OnCommodityPurchaseFailed and GC.Buy.OnCommodityPurchaseFailed()) then
      if GC.Sniper.OnCommodityPurchaseFailed then GC.Sniper.OnCommodityPurchaseFailed() end
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPurchaseFailed() end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if GC.Sniper.OnBrowseResults then
      GC.Sniper.OnBrowseResults()
    end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    if GC.Sniper.OnBrowseResultsAdded then
      GC.Sniper.OnBrowseResultsAdded()
    end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    if GC.Sniper.OnAuctionHouseError then
      local errorCode = ...
      GC.Sniper.OnAuctionHouseError(errorCode)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if GC.Sniper.OnAuctionHouseClosed then
      GC.Sniper.OnAuctionHouseClosed()
    end
    if GC.Buy and GC.Buy.OnAuctionHouseClosed then GC.Buy.OnAuctionHouseClosed() end
    if GC.PurchaseCapture then GC.PurchaseCapture.Reset() end
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    if GC.Sell.OnAuctionCreated then
      GC.Sell.OnAuctionCreated()
    end
  elseif event == "AUCTION_HOUSE_POST_ERROR" then
    if GC.Sell.OnPostError then
      GC.Sell.OnPostError()
    end
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    if GC.Sell.OnOwnedAuctions then
      GC.Sell.OnOwnedAuctions()
    end
  elseif event == "AUCTION_CANCELED" then
    if GC.Sell.OnOwnedAuctions then
      GC.Sell.OnOwnedAuctions()
    end
    -- My-auctions: the payload is not documented on every build (see the RegisterEvent
    -- comment above), so only stamp a cancellation when the first arg is a genuine auctionID.
    local auctionID = ...
    if GC.Data and GC.Data.MarkOwnedLotCancelled and type(auctionID) == "number"
        and auctionID == math.floor(auctionID) and auctionID > 0 and GC.Ledger and GC.Ledger.Context then
      GC.Data.MarkOwnedLotCancelled(GC.db, auctionID, GC.Ledger.Context(), time())
    end
  elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
    if GC.Ledger then
      GC.Ledger.ScanInbox({
        GetInboxNumItems = GetInboxNumItems,
        GetInboxHeaderInfo = GetInboxHeaderInfo,
        GetInboxInvoiceInfo = GetInboxInvoiceInfo,
        GetInboxItem = GetInboxItem,
      }, GC.Ledger.Context())
    end
    -- Sniper v3 §3: forwarded alongside the ledger's own use of this event, not in place of
    -- it. Only MAIL_SHOW (not the repeated MAIL_INBOX_UPDATE) -- Auto only needs to know mail
    -- is open, once, the same way OnAuctionHouseShow's ahOpened fires once per AH visit.
    if event == "MAIL_SHOW" and GC.Sniper.OnMailShow then
      GC.Sniper.OnMailShow()
    end
  elseif event == "MAIL_CLOSED" then
    if GC.Sniper.OnMailClosed then
      GC.Sniper.OnMailClosed()
    end
  elseif event == "PLAYER_MONEY" then
    if GC.Ledger then GC.Ledger.RecordGold(GetMoney(), GC.Ledger.Context()) end
  elseif event == "BAG_UPDATE_DELAYED" then
    -- Guarded: the BUY tab is optional in the same sense every other UI file is -- a load that
    -- stopped short of it must not take the event handler down with it.
    if GC.Buy and GC.Buy.OnBagsChanged then GC.Buy.OnBagsChanged() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Item data is not reliably queryable at ADDON_LOADED; the wanted list is walked from
    -- here. Fires again on every loading screen, which Pending() makes harmless.
    if GC.ItemNames and GC.db then GC.ItemNames.OnEnteringWorld(GC.db, GC.db.imported) end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    local itemID, success = ...
    if GC.ItemNames and GC.db then GC.ItemNames.OnEngineItemInfo(GC.db, itemID, success) end
  elseif event == "PLAYER_LOGOUT" then
    if GC.Ledger then GC.Ledger.RecordGold(GetMoney(), GC.Ledger.Context(), nil, true) end
  end
end)

function GC.Print(msg)
  print("|cffffd100GoldCap|r: " .. tostring(msg))
end

function GC.OnSlash(msg)
  msg = (msg or ""):match("^%s*(%S*)") or ""
  local handler = GC.slashHandlers[msg:lower()]
  if handler then
    handler()
  else
    GC.Print("v" .. GC.version .. GC.L[" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"])
  end
end

GC.slashHandlers.sniper = function() GC.Sniper.Toggle() end

-- The way back to a window you cannot reach. Settings' own RESET WINDOW button does the same
-- thing, but it lives INSIDE the window -- no use at all when the window itself has ended up
-- off-screen (a resolution change, another addon moving it, a UI scale that no longer matches
-- the one it was saved on). Same path either way, so there is one behaviour to remember.
GC.slashHandlers.reset = function()
  if GC.SettingsUI and GC.SettingsUI.ResetWindow then GC.SettingsUI.ResetWindow() end
  GC.Print(GC.L["window moved back to the middle of the screen at its default size"])
end
-- Diagnostics for the Sell tab's pricing walk; see GC.Sell.DebugPrint.
GC.slashHandlers.sell = function() if GC.Sell and GC.Sell.DebugPrint then GC.Sell.DebugPrint() end end
GC.slashHandlers.board = function() if GC.Sniper and GC.Sniper.DebugBoard then GC.Sniper.DebugBoard() end end
-- Diagnostics for the BUY tab's run/attempt state; see GC.Buy.DebugPrint.
GC.slashHandlers.buy = function() if GC.Buy and GC.Buy.DebugPrint then GC.Buy.DebugPrint() end end

-- A printed recap rather than a frame: the numbers are the deliverable here,
-- and an untested UI window isn't worth carrying until the web dashboard makes
-- the same data properly visible.
GC.slashHandlers.ledger = function()
  local entries = GC.Ledger and GC.Ledger.GetEntries() or {}
  local since = time() - 86400
  local sales, gross, cut, buys, spent = 0, 0, 0, 0, 0
  for i = 1, #entries do
    local e = entries[i]
    if (e.at or 0) >= since then
      if e.kind == "sale" then
        sales = sales + 1
        gross = gross + (e.total or 0)
        cut = cut + (e.cut or 0)
      elseif e.kind == "buy" then
        buys = buys + 1
        spent = spent + (e.total or 0)
      end
    end
  end
  GC.Print((GC.L["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"])
    :format(sales, GetCoinTextureString(gross), GetCoinTextureString(cut),
      buys, GetCoinTextureString(spent)))
end

-- "What did that actually sell for?" had no answer anywhere in the addon. The
-- ledger recorded every sale invoice and only ever reported them as a 24h total,
-- which cannot tell you the price of one item -- and the mail carrying the
-- invoice is gone from the client the moment it is collected, so afterwards
-- this store is the only record that exists.
--
-- `total` is what the buyer paid; `cut` is the auction house's consignment,
-- already deducted from what arrived. Per-unit is what a seller compares against
-- a market price, so it leads.
GC.slashHandlers.sales = function()
  local entries = GC.Ledger and GC.Ledger.GetEntries() or {}
  local sales = {}
  for i = 1, #entries do
    local e = entries[i]
    if e.kind == "sale" and (e.itemName or "") ~= "" then sales[#sales + 1] = e end
  end
  table.sort(sales, function(left, right) return (left.at or 0) > (right.at or 0) end)
  if #sales == 0 then
    GC.Print(GC.L["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"])
    return
  end
  GC.Print(GC.L["recent sales (newest first):"])
  for i = 1, math.min(#sales, 15) do
    local sale = sales[i]
    local qty = (type(sale.qty) == "number" and sale.qty > 0) and sale.qty or 1
    local total = sale.total or 0
    local when = "?"
    if type(sale.at) == "number" and _G.date then
      local ok, formatted = pcall(_G.date, "%d %b %H:%M", sale.at)
      if ok then when = formatted end
    end
    GC.Print((GC.L[" %s  %s  x%d at %s each  (%s total, %s cut)%s"]):format(
      when, sale.itemName, qty, GetCoinTextureString(math.floor(total / qty)),
      GetCoinTextureString(total), GetCoinTextureString(sale.cut or 0),
      sale.pending and "  [not yet paid out]" or ""))
  end
end

-- The minimap's addon compartment (TOC directives, Patch 10.1.0) is the engine's own
-- answer to "give the addon a button", so no minimap-icon library is embedded for it.
-- Patch 11.0.0 dropped the third menuButtonFrame argument from automatic registrations:
-- the click handler receives (addonName, buttonName) and needs neither.
function GoldCap_OnAddonCompartmentClick()
  GC.Sniper.Toggle()
end

function GoldCap_OnAddonCompartmentEnter(_, button)
  if not GameTooltip or not button then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:AddLine("GoldCap")
  GameTooltip:AddLine(GC.L["Open the deals board. /gc for commands."], 1, 1, 1)
  GameTooltip:Show()
end

function GoldCap_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end

SLASH_GOLDCAP1 = "/goldcap"
-- Item 6 (addon polish batch): a second, shorter alias -- both strings share the same command
-- table entry, no handler change needed.
SLASH_GOLDCAP2 = "/gc"
SlashCmdList.GOLDCAP = GC.OnSlash
