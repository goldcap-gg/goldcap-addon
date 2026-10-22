local _, GC = ...

-- The Collect button beside the mailbox: one press takes the sales, the lots that came back, the
-- purchases and the mail from players (Core/MailClassify.lua decides which mail, Core/MailLoop.lua
-- paces the takes). The card anchors to MailFrame and nothing of Blizzard's is hooked or touched:
-- no hooksecurefunc on the inbox, no InboxFrame_Update, no OpenAllMail. This file owns the only
-- TakeInboxMoney and TakeInboxItem calls in the addon, inside clientApi below, reached from
-- onCollectClick (the press itself) and from the timer chain that carries a run on.
--
-- A take is not a protected call: Blizzard's own Open All and Postal take from a timer. Even so the
-- press keeps the clean shape of the auction house flows: the first take is the first thing the
-- click does, and the button is never disabled around it (a second press is Stop).
--
-- Retail only (it is not in GoldCap_Camelot.toc): WoW: Forever's mailbox is untested here.
GC.MailCollect = {}
local M = GC.MailCollect

local LAYOUT = { MIN_BUTTON_W = 150, BUTTON_H = 24, PAD = 10, GAP = 6, X = 4, TITLE = 12 }

local frame, loop, patterns, api
local tickToken = 0
local active = false           -- a run was started and its result not yet announced
local lastSummary
local eventFrame

-- Which kinds of mail Collect takes (the MAIL card in Settings). A missing setting counts as on.
function M.Enabled()
  local s = GC.db and GC.db.settings and GC.db.settings.sniper or {}
  return {
    sales = s.collectSales ~= false, returns = s.collectReturns ~= false,
    purchases = s.collectPurchases ~= false, players = s.collectPlayers ~= false,
  }
end

-- The client as Core/MailLoop.lua wants it. Every mailbox call the loop makes goes through here,
-- and the two takes are named nowhere else (spec/mail_collect_wiring_spec.lua).
local function clientApi()
  return {
    GetInboxNumItems = GetInboxNumItems,
    GetInboxHeaderInfo = GetInboxHeaderInfo,
    GetInboxInvoiceInfo = GetInboxInvoiceInfo,
    GetInboxItem = GetInboxItem,
    -- The client's own subjects for the auction mails that never carry an invoice (the same list
    -- Core/Init.lua gives the ledger scan); a global this client lacks is simply absent.
    noInvoiceSubjects = { AUCTION_EXPIRED_MAIL_SUBJECT, AUCTION_REMOVED_MAIL_SUBJECT,
      AUCTION_OUTBID_MAIL_SUBJECT },
    TakeInboxMoney = function(index) TakeInboxMoney(index) end,
    TakeInboxItem = function(index, slot) TakeInboxItem(index, slot) end,
    CheckInbox = function() CheckInbox() end,
    CanCheckInbox = function() return C_Mail.CanCheckInbox() end,
    IsCommandPending = function() return C_Mail.IsCommandPending() end,
    SetOpeningAll = function(flag) C_Mail.SetOpeningAll(flag) end,
    FreeBagSlots = function() return C_Container.CalculateTotalNumberOfFreeBagSlots() end,
  }
end

local function mailPatterns()
  if not patterns then
    patterns = GC.MailClassify.Patterns({ expired = AUCTION_EXPIRED_MAIL_SUBJECT,
      removed = AUCTION_REMOVED_MAIL_SUBJECT, outbid = AUCTION_OUTBID_MAIL_SUBJECT })
  end
  return patterns
end

local function client()
  api = api or clientApi()
  return api
end

local function getLoop()
  if loop then return loop end
  loop = GC.MailLoop.New({
    api = client(),
    patterns = mailPatterns(),
    enabled = M.Enabled,
    -- A synchronous ledger scan: a sale or a purchase is read before its mail is taken.
    scanLedger = function()
      if GC.Ledger and GC.Ledger.ScanInbox then
        GC.Ledger.ScanInbox(client(), GC.Ledger.Context(), nil, false)
      end
    end,
    -- Whose ledger a sale is recorded in: the loop takes a sale or a purchase only when the ledger
    -- can record its invoice under it.
    context = function() return GC.Ledger.Context() end,
    -- The returns log keeps wall clock time, which survives a /reload; the loop's own clock is
    -- session time.
    epoch = time,
    errors = { full = ERR_INV_FULL, unique = ERR_ITEM_MAX_COUNT },
  })
  return loop
end

local function isRunning()
  return loop ~= nil and (loop:State() == "running" or loop:State() == "refresh")
end

local function mailEvents(frameToUse, register)
  for _, event in ipairs({ "MAIL_FAILED", "UI_ERROR_MESSAGE" }) do
    if register then
      pcall(frameToUse.RegisterEvent, frameToUse, event)
    else
      pcall(frameToUse.UnregisterEvent, frameToUse, event)
    end
  end
end

-- MAIL_FAILED carries the itemID the client refused; UI_ERROR_MESSAGE carries (messageType,
-- message), Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua line 21.
local function onClientEvent(_, event, ...)
  if not loop then return end
  if event == "MAIL_FAILED" then
    loop:OnMailFailed((...))
  elseif event == "UI_ERROR_MESSAGE" then
    local _, message = ...
    loop:OnUiError(message)
  end
end

local function build(host)
  local T = GC.Theme
  local f = T.Card(host, T.color.panel, T.color.border, true)
  f.title = T.Label(f, LAYOUT.TITLE)
  f.title:SetPoint("TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  f.title:SetTextColor(T.color.gold[1], T.color.gold[2], T.color.gold[3])
  f.title:SetText("GoldCap")
  f.button = T.Button(f, "primary", "plaque")
  f.button:SetHeight(LAYOUT.BUTTON_H)
  f.button:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  return f
end

-- The button as wide as its label in the player's language, never cut; the card follows.
local function fit()
  local width = frame.button.text and frame.button.text.GetUnboundedStringWidth
    and frame.button.text:GetUnboundedStringWidth()
  if type(width) ~= "number" then width = 0 end
  local buttonW = math.max(LAYOUT.MIN_BUTTON_W, math.ceil(width) + 2 * GC.Theme.pad.m)
  frame.button:SetWidth(buttonW)
  frame:SetWidth(buttonW + 2 * LAYOUT.PAD)
  frame:SetHeight(LAYOUT.PAD + frame.title:GetHeight() + LAYOUT.GAP + LAYOUT.BUTTON_H + LAYOUT.PAD)
end

-- Repaints the label and the tooltip's text from where the run stands.
function M.Refresh()
  if not frame then return end
  local button = frame.button
  local label, enabled
  if loop and loop:State() == "refresh" and loop:WaitSeconds() then
    label, enabled = (GC.L["More mail in %d s"]):format(loop:WaitSeconds()), true
  elseif isRunning() then
    label, enabled = GC.L["Stop"], true
  else
    local takeable = GC.MailClassify.Count(client(), mailPatterns(), M.Enabled(), GC.Ledger.Context())
    if takeable > 0 then
      label, enabled = (GC.L["Collect %d"]):format(takeable), true
    else
      label, enabled = GC.L["Collect"], false
    end
  end
  -- SetVariant before Enable/Disable, and a disabled look is Enable() then Disable() (UI/Theme.lua).
  button:SetVariant("primary")
  button:SetLabel(label)
  if enabled then button:Enable() else button:Enable(); button:Disable() end
  fit()
end

-- A run is over once the loop says done: say what it collected, once.
local function settle()
  if active and loop and loop:State() == "done" then
    active = false
    if eventFrame then mailEvents(eventFrame, false) end
    lastSummary = GC.MailLoop.Summary(loop:Result())
    GC.Print(lastSummary)
  end
  M.Refresh()
end

local armTimer

-- One timer step. A chain whose token is stale (the mailbox closed, opened again, or the run was
-- stopped) does nothing and does not re-arm.
function M._Tick(token)
  if token ~= tickToken or not isRunning() then return end
  loop:Step(GetTime())
  settle()
  if token == tickToken and isRunning() then armTimer(token) end
end

function armTimer(token)
  C_Timer.After(GC.MailLoop.DELAY, function() M._Tick(token) end)
end

-- The press. The first take is the first thing it does: Start makes it. The timer, the event
-- frame and the repaint all come after the call.
local function onCollectClick()
  if isRunning() then
    loop:Stop("stopped")
    tickToken = tickToken + 1
    settle()
    return
  end
  local current = getLoop()
  if current:Start(GetTime()) then
    active = true
    tickToken = tickToken + 1
    if not eventFrame then
      eventFrame = CreateFrame("Frame")
      eventFrame:SetScript("OnEvent", onClientEvent)
    end
    mailEvents(eventFrame, true)
    if isRunning() then armTimer(tickToken) end
    settle()
  else
    if C_Mail.IsCommandPending() then GC.Print(GC.L["The mailbox did not answer"]) end
    M.Refresh()
  end
end

local function showTooltip(button)
  if not lastSummary then return end
  GameTooltip:SetOwner(button, GC.Theme.TooltipAnchor(button))
  GameTooltip:AddLine(GC.Util.ClientText(lastSummary), 1, 1, 1, true)
  GameTooltip:Show()
end

-- MAIL_SHOW: a fresh visit, a clean run. Anything still going from an earlier visit is finished
-- first, so SetOpeningAll(false) is called and its timer chain dies.
function M.OnMailShow()
  local host = _G.MailFrame
  if type(host) ~= "table" then return end
  if loop then loop:OnClosed() end
  tickToken = tickToken + 1
  settle()
  loop, active, lastSummary = nil, false, nil
  if not frame then
    frame = build(host)
    frame:SetPoint("TOPLEFT", host, "TOPRIGHT", LAYOUT.X, 0)
    frame.button:SetScript("OnClick", onCollectClick)
    frame.button:SetScript("OnEnter", showTooltip)
    frame.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  frame:Show()
  M.Refresh()
end

-- MAIL_INBOX_UPDATE: Init has already given the ledger its scan.
function M.OnInboxUpdate()
  if not frame then return end
  if loop then loop:OnInboxUpdate() end
  M.Refresh()
end

function M.OnMailClosed()
  if loop then loop:OnClosed() end
  tickToken = tickToken + 1
  settle()
end
