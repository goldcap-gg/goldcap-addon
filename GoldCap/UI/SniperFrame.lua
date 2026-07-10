local _, GC = ...

GC.Sniper = GC.Sniper or {}

local ROW_HEIGHT = 20
local MAX_ROWS = 20

local TIER_COLOR = {
  HOT = { 1, 0.35, 0.15 },
  GOOD = { 0.25, 0.85, 0.25 },
  WATCH = { 0.65, 0.65, 0.65 },
  SUSPECT = { 1, 0.85, 0.1 },
}

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

local frame           -- lazily created (see createFrame)
local rows = {}        -- pooled row widgets, index 1..MAX_ROWS
local deals = {}        -- itemID -> latest deal shown for it
local scanning = false

local function sortedDeals()
  local list = {}
  for _, deal in pairs(deals) do
    list[#list + 1] = deal
  end
  table.sort(list, function(a, b)
    local ra, rb = TIER_RANK[a.tier] or 9, TIER_RANK[b.tier] or 9
    if ra ~= rb then return ra < rb end
    return a.profit > b.profit
  end)
  return list
end

local function setRowDeal(row, deal)
  row.deal = deal
  local color = TIER_COLOR[deal.tier] or TIER_COLOR.WATCH
  row.tierText:SetText(deal.tier)
  row.tierText:SetTextColor(color[1], color[2], color[3])
  row.discountText:SetText(("%d%%"):format(math.floor(deal.discount * 100 + 0.5)))
  row.profitText:SetText(GetCoinTextureString(deal.profit))
  row.nameText:SetText(("item %d"):format(deal.itemID))
  row.icon:SetTexture(nil)

  local item = Item:CreateFromItemID(deal.itemID)
  item:ContinueOnItemLoad(function()
    if row.deal ~= deal then return end -- row was repurposed before the async load finished
    row.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local label = item:GetItemName() or ("item " .. deal.itemID)
    row.nameText:SetText(qc and qc:WrapTextInColorCode(label) or label)
  end)

  row:Show()
end

local function refreshRows()
  if not frame then return end
  local list = sortedDeals()
  for i = 1, MAX_ROWS do
    local row = rows[i]
    local deal = list[i]
    if deal then
      setRowDeal(row, deal)
    else
      row.deal = nil
      row:Hide()
    end
  end
end

-- Live driver bound to C_AuctionHouse; every WoW-API access below is wrapped in a
-- function so the table itself can be built at file-load with no side effects
-- (required for the headless busted load-order spec).
local driver = {
  isReady = function()
    return C_AuctionHouse.IsThrottledMessageSystemReady()
  end,

  getKeyInfo = function(itemID)
    return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
  end,

  sendSearch = function(itemID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if info and info.isCommodity then
      C_AuctionHouse.SendSearchQuery(key, {}, false)
    else
      C_AuctionHouse.SendSearchQuery(
        key, { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }, false)
    end
  end,

  itemResult = function(itemID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemSearchResultInfo(key, 1)
    if not info or not info.buyoutAmount or info.buyoutAmount == 0 then return nil end
    return { auctionID = info.auctionID, unitPrice = info.buyoutAmount, qty = info.quantity }
  end,

  commodityResult = function(itemID)
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if not info then return nil end
    return { unitPrice = info.unitPrice, qty = info.quantity }
  end,

  getValue = GC.Data.GetItemValue,

  onStatus = function(text)
    if frame then frame.status:SetText(text) end
  end,

  onDeal = function(deal)
    deals[deal.itemID] = deal
    refreshRows()
    if deal.tier == "HOT" and GC.db.settings.sniper.sound then
      PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
  end,

  now = time,
}

local function clearDeals()
  for itemID in pairs(deals) do deals[itemID] = nil end
  refreshRows()
end

local function startScanning()
  if not GC.Sniper.scanner then return end
  clearDeals()
  GC.Sniper.scanner:Stop() -- re-Start while a search is in flight drops it silently: always Stop first
  GC.Sniper.scanner:Start(GC.Data.GetWatchlist(100))
  scanning = true
  if frame then frame.toggleBtn:SetText("Stop") end
end

local function stopScanning()
  if GC.Sniper.scanner then GC.Sniper.scanner:Stop() end
  scanning = false
  if frame then frame.toggleBtn:SetText("Start") end
end

local function createRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(360, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT")
  row.icon = icon

  local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  nameText:SetWidth(130)
  nameText:SetJustifyH("LEFT")
  row.nameText = nameText

  local tierText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tierText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
  tierText:SetWidth(52)
  tierText:SetJustifyH("LEFT")
  row.tierText = tierText

  local discountText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  discountText:SetPoint("LEFT", tierText, "RIGHT", 4, 0)
  discountText:SetWidth(36)
  row.discountText = discountText

  local profitText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  profitText:SetPoint("LEFT", discountText, "RIGHT", 4, 0)
  profitText:SetWidth(90)
  profitText:SetJustifyH("LEFT")
  row.profitText = profitText

  local buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  buy:SetSize(50, 18)
  buy:SetPoint("RIGHT")
  buy:SetText("Buy")
  buy:SetScript("OnClick", function()
    local deal = row.deal
    if not deal then return end
    -- Two-click purchase + requote guard lands in a later task; `deal` is ready for it here.
  end)
  row.buy = buy

  row:Hide()
  return row
end

local function createFrame()
  local f = CreateFrame("Frame", "GoldCapSniperFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 480)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("GoldCap Sniper")

  local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  toggleBtn:SetSize(80, 22)
  toggleBtn:SetPoint("TOPRIGHT", -14, -30)
  toggleBtn:SetText("Start")
  toggleBtn:SetScript("OnClick", function()
    if not GC.Sniper.scanner then
      f.status:SetText("Open the Auction House first.")
      return
    end
    if scanning then
      stopScanning()
    else
      startScanning()
    end
  end)
  f.toggleBtn = toggleBtn

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", 14, -34)
  status:SetPoint("RIGHT", toggleBtn, "LEFT", -8, 0)
  status:SetJustifyH("LEFT")
  status:SetText("Open the Auction House to begin scanning.")
  f.status = status

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -58)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(360, MAX_ROWS * ROW_HEIGHT)
  scroll:SetScrollChild(content)

  for i = 1, MAX_ROWS do
    rows[i] = createRow(content, i)
  end

  table.insert(UISpecialFrames, "GoldCapSniperFrame") -- Escape closes the window

  return f
end

function GC.Sniper.Toggle()
  frame = frame or createFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end

function GC.Sniper.OnAuctionHouseShow()
  -- Build the scanner on the first AH visit regardless of autoOpen, so a later
  -- manual Toggle + Start has one to drive.
  GC.Sniper.scanner = GC.Sniper.scanner or GC.Scanner.New(driver, GC.db.settings.sniper)
  -- autoOpen gates the WINDOW: on it auto-appears and auto-scans; off it stays
  -- hidden until the player opens it via /goldcap sniper (Toggle) and clicks Start.
  if not GC.db.settings.sniper.autoOpen then return end
  frame = frame or createFrame()
  frame:Show()
  startScanning()
end

function GC.Sniper.OnAuctionHouseClosed()
  stopScanning()
  clearDeals() -- next AH visit starts from a clean slate; stale auctions are no longer live
  if frame then frame:Hide() end
end
