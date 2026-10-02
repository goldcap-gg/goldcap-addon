local _, GC = ...

-- BUY 2.0 at a vendor: beside the merchant window, the current BUY list's vendor lines this merchant
-- sells, each with one button that buys what is left of it. The only BuyMerchantItem call in the
-- addon is in onVendorBuyClick, made by the player's own click (spec/buy_vendor_wiring_spec.lua).
-- It is not a restricted call -- the BUY 2.0 probe (2026-10-01) bought from a GoldCap button in both
-- games -- but it spends gold, so it keeps the auction house's shape anyway: the call first, then
-- the button goes busy. A merchant purchase has no answer event: the bag count moving is the
-- answer (GC.BuyVendor.Settle).
--
-- The panel is one GoldCap column beside the merchant with the merchant note (UI/MerchantNote.lua,
-- where that file is loaded): below the note while the note is up, in its place while it is not.
GC.BuyVendorPanel = {}
local P = GC.BuyVendorPanel

-- The probe measured one BuyMerchantItem call per click, buying up to the item's max stack (20
-- in one call). Several calls in one click were not measured, so a press makes one call and the
-- button walks the line: BUY 20, BUY 20, BUY 5.
P.MULTI_CALL = false
-- How long a press waits for the bags to show what it bought before the button is given back.
P.SETTLE_SECONDS = 5
P._pending = nil
P._rows = {}
-- Lines bought at this merchant this visit: they stay on the panel, reading "bought".
P._bought = {}

-- The column the merchant note opens (UI/MerchantNote.lua's LAYOUT): the same width and the same
-- gap from the merchant window, so the two read as one.
local LAYOUT = { WIDTH = 220, PAD = 10, GAP = 4, X = 4, ICON = 24, ICON_GAP = 6, ROW_GAP = 8,
  BUTTON_H = 22, BUTTON_MIN_W = 80 }

local frame
local pendingSeq = 0

local function merchantRows()
  local rows = {}
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
  for index = 1, n do
    local row = GC.VendorBuys.MerchantRow(index)
    if row then rows[#rows + 1] = row end
  end
  return rows
end

local function itemCount(itemID)
  if not (C_Item and C_Item.GetItemCount) then return 0 end
  local ok, n = pcall(C_Item.GetItemCount, itemID)
  return ok and tonumber(n) or 0
end

-- The button's own click: the one place the addon buys from a merchant. Reads the plan the panel
-- painted on the button and the bag count, writes the pending purchase (the double-click guard),
-- makes the call, and only then puts the button to sleep.
local function onVendorBuyClick(button)
  local plan = button.plan
  if not plan or P._pending or (plan.qty or 0) <= 0 then return end
  local qty = P.MULTI_CALL and plan.qty or plan.calls[1]
  pendingSeq = pendingSeq + 1
  P._pending = { itemID = plan.itemID, qty = qty, unit = plan.cost / plan.qty,
    countBefore = itemCount(plan.itemID), token = pendingSeq, code = P._code }
  -- The merchant hook (Core/VendorBuys.lua) books this purchase as cost, once, for the list.
  if GC.VendorBuys then GC.VendorBuys.Tag(P._code) end
  if P.MULTI_CALL then
    for _, n in ipairs(plan.calls) do BuyMerchantItem(plan.index, n) end
  else
    BuyMerchantItem(plan.index, plan.calls[1])
  end
  button:Disable()
  button:SetLabel(GC.L["buying..."])
  local token = pendingSeq
  if C_Timer and C_Timer.After then
    C_Timer.After(P.SETTLE_SECONDS, function() P._Expire(token) end)
  end
end

-- Nothing arrived in time: the press is given up and the button offered again (a merchant can
-- refuse a purchase without a word the addon could read).
function P._Expire(token)
  if P._pending and P._pending.token == token then
    P._pending = nil
    P.Refresh()
  end
end

local function build()
  local T = GC.Theme
  local host = _G.MerchantFrame or UIParent
  frame = T.Card(host, T.color.panel, T.color.border, true)
  frame:SetWidth(LAYOUT.WIDTH)
  frame:EnableMouse(true)
  frame.title = T.Label(frame, 12)
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  frame.title:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(true)
  frame.title:SetTextColor(T.color.gold[1], T.color.gold[2], T.color.gold[3])
  P._frame = frame
end

-- One line of the panel: the icon, the item and how many (wrapping), the list it is from
-- (wrapping), and under them the button, as wide as its label.
local function rowAt(i)
  local T = GC.Theme
  local row = P._rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, frame)
  row:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(LAYOUT.ICON, LAYOUT.ICON)
  row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  local textW = LAYOUT.WIDTH - 2 * LAYOUT.PAD - LAYOUT.ICON - LAYOUT.ICON_GAP
  row.name = T.Label(row, 11)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", LAYOUT.ICON + LAYOUT.ICON_GAP, 0)
  row.name:SetWidth(textW)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(true)
  row.name:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3])
  row.from = T.Num(row, 9)
  row.from:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.from:SetWidth(textW)
  row.from:SetJustifyH("LEFT")
  row.from:SetWordWrap(true)
  row.from:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  local button = T.Button(row, "primary", "plaque")
  button:SetHeight(LAYOUT.BUTTON_H)
  button:SetScript("OnClick", onVendorBuyClick)
  row.button = button
  P._rows[i] = row
  return row
end

-- The button as wide as its label in the player's language, never narrower than BUTTON_MIN_W nor
-- wider than the panel: a label is never cut.
local function fitButton(button)
  local fs = button.text
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(width) ~= "number" then width = 0 end
  button:SetWidth(math.min(LAYOUT.WIDTH - 2 * LAYOUT.PAD,
    math.max(LAYOUT.BUTTON_MIN_W, math.ceil(width) + 2 * GC.Theme.pad.m)))
end

-- Lays a row out for what it now says, and answers its height.
local function layoutRow(row)
  local nameH = row.name.GetStringHeight and row.name:GetStringHeight() or 12
  local fromH = row.from.GetStringHeight and row.from:GetStringHeight() or 10
  local textH = math.max(LAYOUT.ICON, (nameH or 0) + 2 + (fromH or 0))
  fitButton(row.button)
  row.button:ClearAllPoints()
  row.button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -(textH + LAYOUT.GAP))
  local h = math.ceil(textH + LAYOUT.GAP + LAYOUT.BUTTON_H)
  row:SetHeight(h)
  return h
end

-- Where the column starts: under the merchant note while it is up, else beside the merchant window.
function P._Place()
  if not frame then return end
  frame:ClearAllPoints()
  local note = GC.MerchantNote and GC.MerchantNote._frame
  if note and note.IsShown and note:IsShown() then
    frame:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  elseif _G.MerchantFrame then
    frame:SetPoint("TOPLEFT", _G.MerchantFrame, "TOPRIGHT", LAYOUT.X, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- The note refreshes itself on the same events this panel does; after each of its refreshes the
-- column is laid out again, so the two never overlap whichever ran first.
local function followNote()
  local note = GC.MerchantNote
  if P._followingNote or type(note) ~= "table" or type(note.Refresh) ~= "function" or not hooksecurefunc then
    return
  end
  P._followingNote = true
  hooksecurefunc(note, "Refresh", P._Place)
end

-- One row's words and its button, for a plan (GC.BuyVendor.Plan) or a line bought here this visit.
local function paintRow(row, entry, runName)
  local plan = entry.plan
  row.button.plan = plan
  local icon
  if C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, entry.itemID)
    icon = ok and texture or nil
  end
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
  local name = entry.name or ("#" .. tostring(entry.itemID))
  row.name:SetText(("%s ×%d"):format(name, entry.count))
  row.from:SetText((GC.L["from %s"]):format(runName or ""))
  local b = row.button
  -- SetVariant before Enable/Disable, and a disabled look is Enable() then Disable() (UI/Theme.lua).
  b:SetVariant("primary")
  if not plan then
    b:SetLabel(GC.L["bought"])
    b:Enable(); b:Disable()
  elseif P._pending and P._pending.itemID == plan.itemID then
    b:SetLabel(GC.L["buying..."])
    b:Enable(); b:Disable()
  elseif plan.qty <= 0 then
    b:SetLabel(GC.L["not enough gold"])
    b:Enable(); b:Disable()
  else
    local each = P.MULTI_CALL and plan.qty or plan.calls[1]
    local cost = P.MULTI_CALL and plan.cost or plan.firstCost
    if each == plan.qty and not plan.short then
      b:SetLabel((GC.L["BUY · %s"]):format(GC.Util.CoinText(cost)))
    else
      b:SetLabel((GC.L["BUY %d · %s"]):format(each, GC.Util.CoinText(cost)))
    end
    b:Enable()
  end
end

function P.Refresh()
  P._refreshing = true
  local want = GC.Buy and GC.Buy.VendorLines and GC.Buy.VendorLines() or nil
  P._refreshing = nil
  P._code = want and want.code or nil
  -- Each open line this merchant sells, named with what it still needs; then the lines bought here
  -- this visit, named with what was bought.
  local entries = {}
  if want and #want.lines > 0 then
    local open, need = {}, {}
    for _, line in ipairs(want.lines) do
      if (line.buy or 0) > 0 then open[#open + 1], need[line.itemID] = line, line.buy end
    end
    local plans = GC.BuyVendor.Plan(open, GC.BuyVendor.Offers(merchantRows()), GetMoney and GetMoney() or nil)
    for _, plan in ipairs(plans) do
      entries[#entries + 1] = { itemID = plan.itemID, name = plan.name, count = need[plan.itemID], plan = plan }
    end
    for _, line in ipairs(want.lines) do
      if not need[line.itemID] and P._bought[line.itemID] then
        entries[#entries + 1] = { itemID = line.itemID, name = line.name, count = P._bought[line.itemID] }
      end
    end
  end
  if #entries == 0 then
    if frame then frame:Hide() end
    return
  end
  if not frame then build() end
  followNote()
  P._Place()
  local merchant = UnitName and UnitName("npc") or nil
  frame.title:SetText((type(merchant) == "string" and merchant ~= "") and merchant or "GoldCap")
  local y = LAYOUT.PAD + (frame.title.GetStringHeight and frame.title:GetStringHeight() or 12) + LAYOUT.ROW_GAP
  for i, entry in ipairs(entries) do
    local row = rowAt(i)
    paintRow(row, entry, want.runName)
    local h = layoutRow(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
    row:Show()
    y = y + h + LAYOUT.ROW_GAP
  end
  for i = #entries + 1, #P._rows do P._rows[i]:Hide() end
  frame:SetHeight(math.ceil(y - LAYOUT.ROW_GAP + LAYOUT.PAD))
  frame:Show()
end

function P.OnMerchantShow()
  P._open, P._bought = true, {}
  P.Refresh()
end

-- The BUY tab changed what the panel shows -- another list picked, an item added to the quick list,
-- a cap typed -- while a merchant is open: read again, without waiting for the next visit.
function P.OnListChanged()
  if P._open and not P._refreshing then P.Refresh() end
end

function P.OnMerchantUpdate()
  if frame and frame:IsShown() then P.Refresh() end
end

function P.OnMerchantClosed()
  P._open, P._pending, P._bought = false, nil, {}
  if frame then frame:Hide() end
end

-- BAG_UPDATE_DELAYED: what a press bought has arrived (or loot of the same item, which Settle never
-- credits beyond what the press asked for). The units credit the list the press was for
-- (`pending.code`), not whichever list is open now, and the press stays pending until the whole
-- quantity has arrived or P._Expire gives it up: a merchant's stacks can land one bag update at a
-- time, and the later ones are the press's too.
function P.OnBagsChanged()
  local pending = P._pending
  if not pending then return end
  local got = GC.BuyVendor.Settle(pending, itemCount(pending.itemID))
  if not got then return end
  pending.qty, pending.countBefore = pending.qty - got.qty, pending.countBefore + got.qty
  if pending.qty <= 0 then P._pending = nil end
  P._bought[got.itemID] = (P._bought[got.itemID] or 0) + got.qty
  if GC.Buy and GC.Buy.RecordVendorPurchase then
    GC.Buy.RecordVendorPurchase(got.itemID, got.qty, got.spent, pending.code)
  end
  if frame and frame:IsShown() then P.Refresh() end
end
