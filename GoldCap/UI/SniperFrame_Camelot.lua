local _, GC = ...

-- WoW: Forever's Deals Check. Loaded by GoldCap_Camelot.toc alone, right after UI/SniperFrame.lua,
-- whose functions it replaces where Forever differs. Retail never loads it.
--
-- An item that is not a commodity has its variant keys learnt by its name before it is searched
-- (GC.Sniper._SendNaming). Forever files an item with random suffixes under one key per suffix and
-- answers its bare key with no lots: every Carving Knife and Birchwood Maul deal came back "listing
-- gone" while hundreds were up (probe 08.11). A browse by the name names each suffix's key; the
-- search then asks the cheapest one's. An item the polls or a recent browse already know is not
-- asked again, and a commodity has one key and needs none of this.
function GC.Sniper._VariantsOwed(itemID)
  if GC.Sniper._IsCommodityId(itemID) then return false end
  if GC.Sniper._PolledEntry(itemID) or GC.Sniper._NamedFresh(itemID) then return false end
  return GC.Sniper._NameOf(itemID) ~= nil
end

-- DIAG, branch diag/forever-item-bid, never released. What a Deals Buy of an item lot meets on
-- WoW: Forever: the owner's first Buy says "placing bid..." and nothing comes back, Cancel and Buy
-- again buys at once. A ring of the last 800 lines in GoldCapDB.bidTrace, written only while the
-- auction house is open. Nothing here acts: hooks run after the call they watch; the one wrapper
-- (GC.PurchaseCall.Click) reads two numbers before handing the click on untouched.
(function()
  local ahOpen = false
  local recentKeys = {}

  local function now() return _G.GetTimePreciseSec and _G.GetTimePreciseSec() or GetTime() end

  local function rec(...)
    if not ahOpen or type(GoldCapDB) ~= "table" then return end
    local ring = GoldCapDB.bidTrace
    if type(ring) ~= "table" then ring = {}; GoldCapDB.bidTrace = ring end
    local parts = { ("%.3f"):format(now()) }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    ring[#ring + 1] = table.concat(parts, " ")
    while #ring > 800 do table.remove(ring, 1) end
  end

  local function ready()
    local ok, r = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return ok and tostring(r) or "?"
  end

  local function keyText(key)
    if type(key) ~= "table" then return tostring(key) end
    return ("%s:%s:%s:%s"):format(key.itemID or 0, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
  end

  -- Where in the client's item results the auction is: "key#i/n", or "absent" with the keys looked at.
  local function placeOf(auctionID)
    local looked = {}
    for _, key in ipairs(recentKeys) do
      local okN, n = pcall(C_AuctionHouse.GetNumItemSearchResults, key)
      n = okN and n or 0
      looked[#looked + 1] = keyText(key) .. "=" .. n
      for i = 1, n do
        local okI, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, key, i)
        if okI and type(info) == "table" and info.auctionID == auctionID then
          return keyText(key) .. "#" .. i .. "/" .. n
        end
      end
    end
    return "absent[" .. table.concat(looked, ",") .. "]"
  end

  -- The SniperFrame/Kit lines that called the hooked method, squeezed onto one line.
  local function caller()
    local stack = _G.debugstack and _G.debugstack(2, 8, 0) or ""
    local out = {}
    for file, line in stack:gmatch("([%w_]+%.lua)\"?%]?:(%d+)") do
      if file ~= "SniperFrame_Camelot.lua" then out[#out + 1] = file .. ":" .. line end
      if #out >= 3 then break end
    end
    return table.concat(out, "<")
  end

  local origClick = GC.PurchaseCall and GC.PurchaseCall.Click
  if not (origClick and CreateFrame and hooksecurefunc and C_AuctionHouse) then return end
  GC.PurchaseCall.Click = function(plan, ...)
    local r0, money0 = ready(), GetMoney()
    origClick(plan, ...)
    local last = GC.PurchaseCall.last
    rec("CLICK", "readyBefore=" .. r0, "money=" .. money0, "call=" .. tostring(last and last.call),
      "readyAfter=" .. ready())
  end

  local function watchButton(btn)
    hooksecurefunc(btn, "Enable", function(self) rec("BTN+", self.label, caller()) end)
    hooksecurefunc(btn, "Disable", function(self) rec("BTN-", self.label, caller()) end)
  end

  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_LOGIN")
  for _, name in ipairs({
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_SHOW_NOTIFICATION", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM", "PLAYER_MONEY", "ITEM_SEARCH_RESULTS_UPDATED",
  }) do
    pcall(events.RegisterEvent, events, name)
  end
  events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
      local origButton = GC.Theme and GC.Theme.Button
      if origButton then
        GC.Theme.Button = function(parent, variant, rounded, ...)
          local btn = origButton(parent, variant, rounded, ...)
          if variant == "primary" and rounded == "plaque" and btn then watchButton(btn) end
          return btn
        end
      end
      for _, fn in ipairs({ "SendSearchQuery", "SendBrowseQuery", "SearchForItemKeys", "RequestMoreItemSearchResults" }) do
        if C_AuctionHouse[fn] then
          hooksecurefunc(C_AuctionHouse, fn, function(arg)
            if fn == "SendSearchQuery" and type(arg) == "table" then
              table.insert(recentKeys, 1, arg)
              if #recentKeys > 6 then table.remove(recentKeys) end
            end
            rec("SEND", fn, fn == "SearchForItemKeys" and type(arg) == "table" and #arg or keyText(arg), "ready=" .. ready())
          end)
        end
      end
      hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bid)
        rec("PLACEBID", auctionID, bid, "ready=" .. ready(), placeOf(auctionID))
      end)
      return
    end
    if event == "AUCTION_HOUSE_SHOW" then ahOpen = true end
    if event == "ITEM_SEARCH_RESULTS_UPDATED" then
      local key, newID = ...
      rec("EV", event, keyText(key), newID)
    elseif event == "PLAYER_MONEY" then
      rec("EV", event, GetMoney())
    else
      rec("EV", event, ...)
    end
    if event == "AUCTION_HOUSE_CLOSED" then ahOpen = false end
  end)
end)()
