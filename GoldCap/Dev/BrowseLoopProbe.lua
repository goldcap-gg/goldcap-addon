local _ = ...

-- DIAG ONLY. This file exists on the diag/deals-gear-check branch and never merges. WoW: Forever
-- only. One question: how long does one round of browsing all gear take, and does a browse row
-- say enough (key, cheapest price) to spot a lot under what a vendor pays?
--
-- /gcloop starts it with the auction house open; /gcloop again stops it. It browses weapons, then
-- armor, cheapest first, page by page, and starts over, MAX_ROUNDS rounds or MAX_SECONDS at most.
-- It buys nothing and searches no item. Into GoldCapDB.browseLoopProbe (the last 6 runs):
--   rounds   one line a class a round: "class rows pages seconds suffixed unknownVendor under";
--   under    every browse row cheaper than the vendor price, once per key and price:
--            "seconds item/level/suffix minPrice vVendor xQuantity";
--   head     the first rows of the first page of each class, to see the order the server sends;
--   stops    why it ended.

local MAX_ROUNDS = 6
local MAX_SECONDS = 240
local CLASSES = { 2, 4 } -- Enum.ItemClass.Weapon, Enum.ItemClass.Armor

local run = nil

local function say(text)
  if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffffd100GoldCap probe:|r " .. text) end
end

local function vendorOf(itemID)
  local get = _G.C_Item and C_Item.GetItemInfo or _G.GetItemInfo
  if type(get) ~= "function" then return nil end
  local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(get, itemID)
  return ok and sell or nil
end

local function finish(why)
  if not run then return end
  run.stops = why
  run.seconds = math.floor((GetTime() - run.t0) * 10) / 10
  local db = _G.GoldCapDB
  if type(db) == "table" then
    if type(db.browseLoopProbe) ~= "table" then db.browseLoopProbe = {} end
    local l = db.browseLoopProbe
    l[#l + 1] = { at = time(), stops = run.stops, seconds = run.seconds, rounds = run.rounds,
      under = run.under, head = run.head }
    while #l > 6 do table.remove(l, 1) end
  end
  say(("stopped (%s) after %d class passes in %.0f s. /reload to save."):format(why, #run.rounds, run.seconds))
  run = nil
end

local function send()
  local r = run
  r.class = CLASSES[r.classAt]
  r.pages, r.passStart, r.sent, r.asked = 0, GetTime(), true, GetTime()
  local order = Enum.AuctionHouseSortOrder
  C_AuctionHouse.SendBrowseQuery({ searchString = "", filters = {},
    itemClassFilters = { { classID = r.class } },
    sorts = { { sortOrder = order.Price, reverseSort = false } } })
end

-- A class is read whole: its rows are counted and weighed against the vendor price.
local function closePass()
  local r = run
  local rows = C_AuctionHouse.GetBrowseResults() or {}
  local suffixed, unknown, under = 0, 0, 0
  for i = 1, #rows do
    local row = rows[i]
    local key = row.itemKey
    if type(key) == "table" then
      if (key.itemSuffix or 0) ~= 0 then suffixed = suffixed + 1 end
      local vendor = vendorOf(key.itemID)
      if not vendor then
        unknown = unknown + 1
      elseif vendor > 0 and type(row.minPrice) == "number" and row.minPrice > 0 and row.minPrice < vendor then
        under = under + 1
        local id = ("%d/%d/%d %d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, row.minPrice)
        if not r.seen[id] and #r.under < 60 then
          r.seen[id] = true
          r.under[#r.under + 1] = ("%.0f %s v%d x%s"):format(GetTime() - r.t0, id, vendor, tostring(row.totalQuantity))
        end
      end
    end
  end
  r.rounds[#r.rounds + 1] = ("c%d rows=%d pages=%d %.1fs suffixed=%d unknownVendor=%d under=%d")
    :format(r.class, #rows, r.pages, GetTime() - r.passStart, suffixed, unknown, under)
  r.sent = false
  r.classAt = r.classAt + 1
  if r.classAt > #CLASSES then
    r.classAt = 1
    r.round = r.round + 1
    say(("round %d done at %.0f s"):format(r.round, GetTime() - r.t0))
  end
  if r.round >= MAX_ROUNDS then return finish("rounds") end
  r.wantSend = true
end

local function onResults()
  local r = run
  if not r or not r.sent then return end
  r.pages = r.pages + 1
  if r.pages == 1 and #r.head < 2 then
    local rows = C_AuctionHouse.GetBrowseResults() or {}
    local first = {}
    for i = 1, math.min(#rows, 8) do
      local key = rows[i].itemKey or {}
      first[#first + 1] = ("%s/%s/%s %s x%s"):format(tostring(key.itemID), tostring(key.itemLevel),
        tostring(key.itemSuffix), tostring(rows[i].minPrice), tostring(rows[i].totalQuantity))
    end
    r.head[#r.head + 1] = { class = r.class, n = #rows, first = first }
  end
  if C_AuctionHouse.HasFullBrowseResults() then
    closePass()
  else
    r.wantMore = true
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
  if not run then return end
  if event == "AUCTION_HOUSE_CLOSED" then return finish("closed") end
  local ok, err = pcall(onResults)
  if not ok then finish("error: " .. tostring(err)) end
end)

-- Requests go only when the client says its auction-house throttle is ready.
frame:SetScript("OnUpdate", function()
  local r = run
  if not r then return end
  if GetTime() - r.t0 > MAX_SECONDS then return finish("time") end
  if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
  if r.wantMore then
    r.wantMore = false
    r.asked = GetTime()
    C_AuctionHouse.RequestMoreBrowseResults()
  elseif r.wantSend then
    r.wantSend = false
    local ok, err = pcall(send)
    if not ok then finish("error: " .. tostring(err)) end
  elseif r.sent and GetTime() - r.asked > 20 then
    finish("no answer for 20 s")
  end
end)

_G.SLASH_GCLOOP1 = "/gcloop"
SlashCmdList["GCLOOP"] = function()
  if run then return finish("stopped by hand") end
  if not (_G.AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    return say("open the auction house first")
  end
  run = { t0 = GetTime(), round = 0, classAt = 1, rounds = {}, under = {}, head = {}, seen = {}, wantSend = true }
  say(("browsing all gear, %d rounds or %d s at most. /gcloop stops it."):format(MAX_ROUNDS, MAX_SECONDS))
end
