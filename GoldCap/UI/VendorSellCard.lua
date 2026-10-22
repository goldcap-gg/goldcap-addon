local _, GC = ...

-- At a vendor: the third GoldCap card in the merchant column, under the merchant note and the BUY
-- panel (UI/MerchantNote.lua, UI/BuyVendorPanel.lua). It lists what one press would sell, a line
-- per stack with its price, and the total on its button. Which stacks those are is
-- Core/VendorSelect.lua's Pick; the bags are read by Services/VendorBags.lua. Right click a line
-- to keep that item for good (GC.db.vendorKeep).
--
-- The one sale call in the addon outside the Warband Bank carry (UI/BankRoute.lua) is in this
-- file: the driver's `use` below, made for the first stack inside the player's own click and for
-- the rest by Core/VendorPress.lua's timers, each after it has checked that the merchant is still
-- open and the slot still holds the chosen item (the same call equips a piece of gear when no
-- vendor is open, which binds it). spec/vendor_sell_wiring_spec.lua audits it.
--
-- Retail only (GoldCap.toc): WoW: Forever loads none of the vendor sell files.
GC.VendorSellCard = {}
local C = GC.VendorSellCard

-- The column the other two cards open: the same width, the same gap from the merchant window.
local LAYOUT = { WIDTH = 220, PAD = 10, GAP = 4, X = 4, ICON = 16, ICON_GAP = 6, ROW_GAP = 6,
  BUTTON_H = 22, BUTTON_MIN_W = 80 }

C._rows = {}
local frame

local function sniperSettings()
  return GC.db and GC.db.settings and GC.db.settings.sniper or {}
end

-- The lowest card of the column that is up, so the three never overlap: the BUY panel sits under
-- the note while the note is up, and this card sits under whichever is last.
local function isUp(card)
  return type(card) == "table" and card.IsShown and card:IsShown()
end

function C._Place()
  if not frame then return end
  frame:ClearAllPoints()
  local buy = GC.BuyVendorPanel and GC.BuyVendorPanel._frame
  local note = GC.MerchantNote and GC.MerchantNote._frame
  if isUp(buy) then
    frame:SetPoint("TOPLEFT", buy, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  elseif isUp(note) then
    frame:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  elseif _G.MerchantFrame then
    frame:SetPoint("TOPLEFT", _G.MerchantFrame, "TOPRIGHT", LAYOUT.X, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- The other two cards refresh on their own events; after each of their refreshes this one is
-- placed again, whichever ran last (the BUY panel hides and shows by its own Refresh). Installed
-- once per card.
local function followColumn()
  if not hooksecurefunc then return end
  for _, name in ipairs({ "MerchantNote", "BuyVendorPanel" }) do
    local card = GC[name]
    if type(card) == "table" and type(card.Refresh) == "function" and not C["_following" .. name] then
      C["_following" .. name] = true
      hooksecurefunc(card, "Refresh", C._Place)
    end
  end
end

-- The button as wide as its label in the player's language, never narrower than BUTTON_MIN_W nor
-- wider than the card: a label is never cut.
local function fitButton(button)
  local fs = button.text
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(width) ~= "number" then width = 0 end
  button:SetWidth(math.min(LAYOUT.WIDTH - 2 * LAYOUT.PAD,
    math.max(LAYOUT.BUTTON_MIN_W, math.ceil(width) + 2 * GC.Theme.pad.m)))
end

-- The button says Stop while a press is going, else what the next press promises: every row, or
-- only the first when the game sold one stack per press this visit.
local function paintButton()
  if not (frame and C._pick) then return end
  local machine = C.machine
  if machine and machine:IsRunning() then
    frame.button:SetLabel(GC.L["Stop"])
  else
    local count, copper = GC.VendorSelect.PressTotals(C._pick, machine and machine.oneAtATime or false)
    frame.button:SetLabel(GC.L["Sell %d for %s"]:format(count, GC.Util.CoinText(copper)))
  end
  fitButton(frame.button)
end

-- What the machine (Core/VendorPress.lua) drives. `use` is the single place the addon sells; the
-- other fields read the client or arm a timer.
--
-- Busy when the cursor carries something, or when a spell waits for an item target (Disenchant, an
-- enchant scroll). GetCursorInfo is nil then, and UseContainerItem casts that spell on the item
-- instead of selling it: Blizzard's own bag click calls it for exactly that (live
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1340-1342), and shows the sell cursor over a
-- bag item only while SpellIsTargeting() is false (same file, :1559). The machine checks this
-- before every call, the one in the click included. An error from either read counts as busy.
local function cursorBusy()
  local okSpell, targeting = pcall(SpellIsTargeting)
  if not okSpell or targeting then return true end
  local ok, kind = pcall(GetCursorInfo)
  return ok and kind ~= nil
end

local function slotNow(bag, slot)
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if ok and type(info) == "table" then return { link = info.hyperlink, isLocked = info.isLocked == true } end
  return nil
end

local function merchantOpen()
  local merchant = _G.MerchantFrame
  if type(merchant) == "table" and merchant.IsShown and not merchant:IsShown() then return false end
  return C._open == true
end

local function report(result)
  if result.sold > 0 then
    local coins = GC.Util.CoinText(result.copper)
    if result.sold == 1 then
      GC.Print(GC.L["Sold 1 stack for %s. Buyback keeps the last 12 you sold."]:format(coins))
    else
      GC.Print(GC.L["Sold %d stacks for %s. Buyback keeps the last 12 you sold."]:format(result.sold, coins))
    end
  end
  C.Refresh()
end

function C._Machine()
  if not C.machine then
    C.machine = GC.VendorPress.New({
      merchantOpen = merchantOpen,
      slot = slotNow,
      cursorBusy = cursorBusy,
      use = function(bag, slot) C_Container.UseContainerItem(bag, slot) end,
      after = function(seconds, fn) C_Timer.After(seconds, fn) end,
      report = report,
    })
  end
  return C.machine
end

-- The button's own click: the only handler that starts a press. The machine makes the first sale
-- inside this call; the button is repainted only afterwards, and never put to sleep, because a
-- second press stops a run.
local function onSellClick(button)
  C._Machine():Press(button.rows or {})
  paintButton()
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
  frame.title:SetText(GC.L["Sell to vendor"])
  frame.more = T.Label(frame, 10)
  frame.more:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  frame.more:SetJustifyH("LEFT")
  frame.more:SetWordWrap(true)
  frame.more:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  frame.slow = T.Label(frame, 10)
  frame.slow:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  frame.slow:SetJustifyH("LEFT")
  frame.slow:SetWordWrap(true)
  frame.slow:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  frame.hint = T.Label(frame, 10)
  frame.hint:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  frame.hint:SetJustifyH("LEFT")
  frame.hint:SetWordWrap(true)
  frame.hint:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  frame.hint:SetText(GC.L["Right click a line to keep that item."])
  frame.button = T.Button(frame, "primary", "plaque")
  frame.button:SetHeight(LAYOUT.BUTTON_H)
  frame.button:SetScript("OnClick", onSellClick)
  C._frame = frame
end

local function itemName(row)
  local name
  if C_Item and C_Item.GetItemInfo then
    local ok, got = pcall(C_Item.GetItemInfo, row.itemID)
    if ok and type(got) == "string" then name = got end
  end
  return name or ("#" .. tostring(row.itemID))
end

-- Right click on a line: the one entry, Never sell this.
local function openKeepMenu(owner, itemID)
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return end
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateButton(GC.Util.ClientText(GC.L["Never sell this"]), function() C.Keep(itemID) end)
  end)
end

-- One line: the icon, the item and how many (wrapping), and under them what the vendor pays.
local function rowAt(i)
  local T = GC.Theme
  local row = C._rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, frame)
  row:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  row:RegisterForClicks("RightButtonUp")
  row:EnableMouse(true)
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
  row.price = T.Num(row, 10)
  row.price:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.price:SetWidth(textW)
  row.price:SetJustifyH("LEFT")
  row.price:SetWordWrap(true)
  row:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" and self.itemID then openKeepMenu(self, self.itemID) end
  end)
  C._rows[i] = row
  return row
end

local function paintRow(row, stack)
  row.itemID = stack.itemID
  local icon
  if C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, stack.itemID)
    icon = ok and texture or nil
  end
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
  row.name:SetText(("%s ×%d"):format(itemName(stack), stack.count))
  local color = _G.ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[stack.quality]
  if color then row.name:SetTextColor(color.r, color.g, color.b) end
  row.price:SetText(GC.Util.CoinText(stack.copper))
end

local function heightOf(fs, fallback)
  return fs.GetStringHeight and fs:GetStringHeight() or fallback
end


-- Reads the bags again and shows the card with what one press would sell, or hides it.
function C.Refresh()
  if not C._open then
    if frame then frame:Hide() end
    return
  end
  -- A press is going: the rows stay as pressed (a bag update must not rebuild them under the
  -- machine); only the button's words follow.
  if C.machine and C.machine:IsRunning() then
    paintButton()
    return
  end
  local settings = sniperSettings()
  local opts = {
    junk = settings.vendorJunk ~= false,
    worth = settings.vendorWorth ~= false,
    kept = GC.db and GC.db.vendorKeep or {},
    now = time(),
  }
  local valueFor = GC.MerchantNote and GC.MerchantNote.ValueFor
  local pick = GC.VendorSelect.Pick(GC.VendorBags.Read(valueFor), opts)
  C._pick = pick
  if #pick.rows == 0 then
    if frame then frame:Hide() end
    return
  end
  if not frame then build() end
  followColumn()
  C._Place()
  local y = LAYOUT.PAD + heightOf(frame.title, 12) + LAYOUT.ROW_GAP
  for i, stack in ipairs(pick.rows) do
    local row = rowAt(i)
    paintRow(row, stack)
    local h = math.max(LAYOUT.ICON, heightOf(row.name, 12) + 2 + heightOf(row.price, 10))
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
    row:Show()
    y = y + h + LAYOUT.ROW_GAP
  end
  for i = #pick.rows + 1, #C._rows do C._rows[i]:Hide() end
  if pick.more > 0 then
    frame.more:SetText(GC.L["%d more after this"]:format(pick.more))
    frame.more:ClearAllPoints()
    frame.more:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
    frame.more:Show()
    y = y + heightOf(frame.more, 10) + LAYOUT.ROW_GAP
  else
    frame.more:Hide()
  end
  frame.button.rows = pick.rows
  paintButton()
  frame.button:ClearAllPoints()
  frame.button:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
  y = y + LAYOUT.BUTTON_H + LAYOUT.ROW_GAP
  if C.machine and C.machine.oneAtATime then
    frame.slow:SetText(GC.L["The game sells one stack per press here."])
    frame.slow:ClearAllPoints()
    frame.slow:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
    frame.slow:Show()
    y = y + heightOf(frame.slow, 10) + LAYOUT.ROW_GAP
  else
    frame.slow:Hide()
  end
  frame.hint:ClearAllPoints()
  frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
  y = y + heightOf(frame.hint, 10)
  frame:SetHeight(math.ceil(y + LAYOUT.PAD))
  frame:Show()
end

-- Never sell this: the item stays in the bags from now on, and its line goes. During a press the
-- run leaves its stacks still to come alone; the list is read again when the run ends.
function C.Keep(itemID)
  if type(itemID) ~= "number" or not GC.db then return end
  GC.db.vendorKeep = GC.db.vendorKeep or {}
  GC.db.vendorKeep[itemID] = true
  if C.machine then C.machine:Skip(itemID) end
  C.Refresh()
end

function C.OnMerchantShow()
  C._Machine():OnMerchantShow()
  C._open = true
  C.Refresh()
end

-- MERCHANT_UPDATE: an item whose data has arrived since the last read joins the list here.
function C.OnMerchantUpdate()
  if C._open then C.Refresh() end
end

-- BAG_UPDATE_DELAYED: a sale, a buyback, a loot or a move changed what one press would sell.
function C.OnBagsChanged()
  if C._open then C.Refresh() end
end

-- MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL: the client asks the player to confirm selling tradeable
-- loot; the run stops so the question is the player's, and the next call does not stack on it.
function C.OnTradeTimerConfirm()
  if C.machine then C.machine:Stop("confirm") end
end

function C.OnMerchantClosed()
  -- First, so what sold before the window closed is counted and reported.
  if C.machine then C.machine:OnMerchantClosed() end
  C._open = false
  if frame then frame:Hide() end
end
