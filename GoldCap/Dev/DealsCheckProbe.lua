local _ = ...

-- DIAG ONLY. This file exists on the diag/deals-gear-check branch and never merges. WoW: Forever
-- only. One question: a Check of gear under its vendor price always answers "listing gone". What
-- did the auction house say to the search the Check sent?
--
-- Passive: nothing here sends a request. Into GoldCapDB.dealsCheckProbe (the last 80 entries):
--   search   every C_AuctionHouse.SendSearchQuery: its key, its sorts and who sent it;
--   answer   every ITEM_SEARCH_RESULTS_UPDATED: the key answered, how many rows it has, what a
--            vendor pays for the item, the first rows as the client reads them
--            ("buyout/bid/minBid/quantity/own"), how many of the rows read have no buyout, the
--            cheapest buyout among them and its place, and `gate`: whether row 1 alone has a
--            buyout and a quantity, which is what the Check looks at first;
--   browse   every C_AuctionHouse.SendBrowseQuery with a search string, and the keys its answer
--            listed for that name with their cheapest price and quantity.

local CAP = 80
local ROWS_KEPT = 15
local ROWS_READ = 60

local function log()
  local db = _G.GoldCapDB
  if type(db) ~= "table" then return nil end
  if type(db.dealsCheckProbe) ~= "table" then db.dealsCheckProbe = {} end
  return db.dealsCheckProbe
end

local function note(entry)
  local l = log()
  if not l then return end
  entry.at = time()
  l[#l + 1] = entry
  while #l > CAP do table.remove(l, 1) end
end

local function keyText(key)
  if type(key) ~= "table" then return tostring(key) end
  return ("%s/%s/%s"):format(tostring(key.itemID), tostring(key.itemLevel or 0), tostring(key.itemSuffix or 0))
end

-- The first AddOns file on the stack that is not this one: who made the call.
local function caller()
  local ok, stack = pcall(_G.debugstack, 3, 20, 0)
  if not ok or type(stack) ~= "string" then return "?" end
  for line in stack:gmatch("[^\n]+") do
    if not line:find("DealsCheckProbe", 1, true) then
      local folder, file = line:match("AddOns[/\\]([%w_]+)[/\\]([^\"%]:]+)")
      if folder then return folder .. "/" .. (file or "") end
    end
  end
  return "?"
end

local function sortsText(sorts)
  if type(sorts) ~= "table" then return "-" end
  local out = {}
  for i = 1, #sorts do
    local s = sorts[i]
    out[#out + 1] = type(s) == "table" and (tostring(s.sortOrder) .. (s.reverseSort and "r" or "")) or "?"
  end
  return #out > 0 and table.concat(out, ",") or "none"
end

local function vendorOf(itemID)
  local get = _G.C_Item and C_Item.GetItemInfo or _G.GetItemInfo
  if type(get) ~= "function" then return nil end
  local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(get, itemID)
  return ok and sell or nil
end

local function onAnswer(key)
  local ah = _G.C_AuctionHouse
  if type(ah) ~= "table" or type(key) ~= "table" then return end
  local n = ah.GetNumItemSearchResults(key) or 0
  local rows, noBuyout, cheapest, cheapestAt = {}, 0, nil, nil
  local gate = "empty"
  for i = 1, math.min(n, ROWS_READ) do
    local info = ah.GetItemSearchResultInfo(key, i)
    if type(info) == "table" then
      local buyout = info.buyoutAmount or 0
      if i == 1 then
        gate = (buyout > 0 and (info.quantity or 0) > 0) and "pass" or "fail"
      end
      if buyout > 0 then
        if not cheapest or buyout < cheapest then cheapest, cheapestAt = buyout, i end
      else
        noBuyout = noBuyout + 1
      end
      if i <= ROWS_KEPT then
        rows[#rows + 1] = ("%s/%s/%s/%s/%s"):format(tostring(info.buyoutAmount), tostring(info.bidAmount),
          tostring(info.minBid), tostring(info.quantity), info.containsOwnerItem and "own" or "-")
      end
    elseif i == 1 then
      gate = "nil"
    end
  end
  local full = ah.HasFullItemSearchResults and ah.HasFullItemSearchResults(key)
  note({ what = "answer", key = keyText(key), n = n, full = tostring(full), vendor = vendorOf(key.itemID),
    gate = gate, noBuyout = noBuyout, cheapest = cheapest, cheapestAt = cheapestAt, rows = rows })
end

local browseName = nil

local function onBrowse()
  if not browseName then return end
  local ah = _G.C_AuctionHouse
  local list = ah.GetBrowseResults and ah.GetBrowseResults() or {}
  local keys = {}
  for i = 1, math.min(#list, 30) do
    local row = list[i]
    if type(row) == "table" then
      keys[#keys + 1] = ("%s %s x%s"):format(keyText(row.itemKey), tostring(row.minPrice), tostring(row.totalQuantity))
    end
  end
  note({ what = "browse-answer", name = browseName, n = #list, keys = keys })
  browseName = nil
end

local hooked = false
local function hook()
  if hooked or type(_G.C_AuctionHouse) ~= "table" or type(hooksecurefunc) ~= "function" then return end
  hooked = true
  hooksecurefunc(C_AuctionHouse, "SendSearchQuery", function(key, sorts)
    pcall(function() note({ what = "search", key = keyText(key), sorts = sortsText(sorts), from = caller() }) end)
  end)
  hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
    pcall(function()
      local name = type(query) == "table" and query.searchString or nil
      if type(name) == "string" and name ~= "" then
        browseName = name
        note({ what = "browse", name = name, from = caller() })
      end
    end)
  end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
pcall(frame.RegisterEvent, frame, "ITEM_SEARCH_RESULTS_UPDATED")
pcall(frame.RegisterEvent, frame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:SetScript("OnEvent", function(_, event, a)
  if event == "PLAYER_LOGIN" then
    hook()
    return
  end
  if event == "ITEM_SEARCH_RESULTS_UPDATED" then
    pcall(onAnswer, a)
  else
    pcall(onBrowse)
  end
end)
