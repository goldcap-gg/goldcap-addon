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
  -- itemID -> true/false, "does this item sell as a commodity". Learned from
  -- C_AuctionHouse.GetItemKeyInfo, which only answers while the auction house is
  -- open, and remembered because the Sell tab lists bag stock wherever the player
  -- is standing. Getting this wrong files one item under two position keys (see
  -- UI/SellFrame.lua's classifyBagItem), so an unknown item is left out rather
  -- than guessed at. Same empty-table ApplyDefaults contract as `flips` above.
  commodityByItem = {},
  -- P2 ledger + gold curve. Same ApplyDefaults contract as `flips` above: an
  -- empty table default only fills in when the persisted value isn't already a
  -- table, so a populated SavedVariables array is never truncated on login.
  ledger = {},
  gold = {},
  settings = {
    tooltip = true,
    sniper = {
      autoOpen = true,
      auto = false,
      sound = true,
      -- Whether the deals list shows rows the background live check has refused. Off by
      -- default: the point of checking in the background is that the list stops offering
      -- flips a Check has already ruled out. Owned by the Deals toolbar's own toggle (see
      -- UI/SniperFrame.lua's verifyBtn), which is also where the count of hidden rows lives,
      -- so a shorter list always arrives with the number that explains it.
      showRefused = false,
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
      maxCapitalShare = 0.05,
      maxDailyDemandShare = 0.02,
      maxQuantity = 200,
      minimumProfitCopper = 50000,
      profitFloorVersion = 1,
      minimumRoi = 0.10,
      -- Sniper v3 T10: UI-only scale multiplier for Theme's fonts (0.9-1.3), persisted so a
      -- player's chosen text size survives relog. Read back once GC.db exists (see this file's
      -- ADDON_LOADED handler below) and re-written by UI/Theme.lua's SetScale itself on every
      -- change (the settings panel's font-scale slider), not by UI/SettingsFrame.lua directly.
      fontScale = 1.0,
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
frame:RegisterEvent("PLAYER_LOGOUT")

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

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end
    GoldCapDB = GoldCapDB or {}
    local acquisitionsInitialized = not GC.Acquisitions or GC.Acquisitions.Init(GoldCapDB)
    if not acquisitionsInitialized then
      frame:UnregisterEvent("ADDON_LOADED")
      return
    end
    migrateSniperProfitFloor(GoldCapDB)
    migrateSniperTierProfit(GoldCapDB)
    if GC.Util then GC.Util.ApplyDefaults(GoldCapDB, GC.DEFAULTS) end
    GC.db = GoldCapDB
    if GC.Data then
      GC.Data.Init(GC.db)
      -- Companion sync (Task A): adopts `GoldCap_AppData` (see the .toc's OptionalDeps)
      -- over any existing import when it's present and strictly newer -- see
      -- Core/Data.lua's AdoptAppData for the full contract. Runs after Init above so
      -- db.imported already reflects the prior session's state to compare against.
      GC.Data.AdoptAppData()
    end
    if GC.Ledger then GC.Ledger.Init(GC.db) end
    if GC.Acquisitions then
      GC.Acquisitions.MigrateLegacy(GoldCapDB.flips, GC.Ledger and GC.Ledger.GetEntries() or {})
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
      GC.Sniper.OnAuctionHouseShow()
    end
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local interactionType = ...
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
      GC.Sniper.OnAuctionHouseClosed()
      if GC.PurchaseCapture then GC.PurchaseCapture.Reset() end
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
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
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if GC.Sniper.OnPurchaseCompleted then
      local auctionID = ...
      GC.Sniper.OnPurchaseCompleted(auctionID)
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnPurchaseCompleted(...) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if GC.Sniper.OnCommodityPriceUpdated then
      local unitPrice, totalPrice = ...
      GC.Sniper.OnCommodityPriceUpdated(unitPrice, totalPrice)
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPriceUpdated(...) end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if GC.Sniper.OnCommodityPriceUnavailable then
      GC.Sniper.OnCommodityPriceUnavailable()
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPriceUnavailable() end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if GC.Sniper.OnCommodityPurchaseSucceeded then
      GC.Sniper.OnCommodityPurchaseSucceeded()
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.OnCommodityPurchaseSucceeded() end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if GC.Sniper.OnCommodityPurchaseFailed then
      GC.Sniper.OnCommodityPurchaseFailed()
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
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if GC.Sniper.OnAuctionHouseClosed then
      GC.Sniper.OnAuctionHouseClosed()
    end
    if GC.PurchaseCapture then GC.PurchaseCapture.Reset() end
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    if GC.Sell.OnAuctionCreated then
      GC.Sell.OnAuctionCreated()
    end
  elseif event == "AUCTION_HOUSE_POST_ERROR" then
    if GC.Sell.OnPostError then
      GC.Sell.OnPostError()
    end
  elseif event == "OWNED_AUCTIONS_UPDATED" or event == "AUCTION_CANCELED" then
    if GC.Sell.OnOwnedAuctions then
      GC.Sell.OnOwnedAuctions()
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
    GC.Print("v" .. GC.version .. " — commands: /goldcap import, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger")
  end
end

GC.slashHandlers.sniper = function() GC.Sniper.Toggle() end

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
  GC.Print(("last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent")
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
    GC.Print("no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices")
    return
  end
  GC.Print("recent sales (newest first):")
  for i = 1, math.min(#sales, 15) do
    local sale = sales[i]
    local qty = (type(sale.qty) == "number" and sale.qty > 0) and sale.qty or 1
    local total = sale.total or 0
    local when = "?"
    if type(sale.at) == "number" and _G.date then
      local ok, formatted = pcall(_G.date, "%d %b %H:%M", sale.at)
      if ok then when = formatted end
    end
    GC.Print((" %s  %s  x%d at %s each  (%s total, %s cut)%s"):format(
      when, sale.itemName, qty, GetCoinTextureString(math.floor(total / qty)),
      GetCoinTextureString(total), GetCoinTextureString(sale.cut or 0),
      sale.pending and "  [not yet paid out]" or ""))
  end
end

SLASH_GOLDCAP1 = "/goldcap"
SlashCmdList.GOLDCAP = GC.OnSlash
