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
      hotDiscount = 0.40, hotProfit = 5000000,
      goodDiscount = 0.25, goodProfit = 1000000,
      watchDiscount = 0.10, suspectDiscount = 0.90,
      -- Liquidity floors, sold per day (from a realm import's soldPerDay); only enforced
      -- against import-sourced values, see DealMath.Evaluate.
      hotMinSold = 3, goodMinSold = 1,
      -- Anti-dump gate (Sniper v2): units are whole percent, matching the
      -- import string's signed trend field; a deal whose 24h market-value
      -- trend is <= -dumpTrendPct is capped below GOOD, see DealMath.Evaluate.
      dumpTrendPct = 10,
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

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end
    GoldCapDB = GoldCapDB or {}
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
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if GC.Sniper.scanner then GC.Sniper.scanner:OnSystemReady() end
    if GC.Sniper.OnThrottleReady then GC.Sniper.OnThrottleReady() end
    -- D: serviced AFTER the scanner and the Sniper's own pendingFullScanStart/pendingBrowsePage/
    -- pendingRequerySend flush above -- GC.Sell.OnThrottleReady only ever advances its OWN
    -- sequential quote walk (and even then refuses while GC.Sniper.IsBusy()), so it can never
    -- steal this throttle-ready tick out from under a scan or a buy requery.
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
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if GC.Sniper.OnCommodityPriceUpdated then
      local unitPrice, totalPrice = ...
      GC.Sniper.OnCommodityPriceUpdated(unitPrice, totalPrice)
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if GC.Sniper.OnCommodityPriceUnavailable then
      GC.Sniper.OnCommodityPriceUnavailable()
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if GC.Sniper.OnCommodityPurchaseSucceeded then
      GC.Sniper.OnCommodityPurchaseSucceeded()
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if GC.Sniper.OnCommodityPurchaseFailed then
      GC.Sniper.OnCommodityPurchaseFailed()
    end
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
    GC.Print("v" .. GC.version .. " — commands: /goldcap import, /goldcap status, /goldcap sniper")
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

SLASH_GOLDCAP1 = "/goldcap"
SlashCmdList.GOLDCAP = GC.OnSlash
