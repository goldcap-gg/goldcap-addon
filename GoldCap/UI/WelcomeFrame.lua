local _, GC = ...

-- The welcome window: what GoldCap does, the state of the player's prices, and how to get fresh
-- ones from GoldCap Companion. Core/Welcome.lua decides the state and when the window opens by
-- itself; this file reads the client for it and draws it. It took over from the old Companion
-- dialog, so every Companion nudge in the addon still lands here through GC.CompanionUI.Show
-- (/gc companion, the price line at the top of the Deals window, the empty Deals board's hint).
--
-- Drawn in the kit (dark glass, condensed headings), sized to its text: every line wraps and the
-- window grows to hold it, in every language. WoW cannot open a URL from an addon, so the link is
-- an EditBox the player copies from; it takes the keyboard only when the player clicks it or opened
-- the window themselves, never when the window opened on its own at the auction house.
GC.CompanionUI = GC.CompanionUI or {}
GC.WelcomeUI = GC.WelcomeUI or {}
GC.slashHandlers = GC.slashHandlers or {}

local Theme = GC.Theme
local K = GC.Kit.Tokens.color

local URL = "https://goldcap.gg/downloads"
local NAME = "GoldCapWelcome"
-- Width, outer padding, the card's own padding, the logo, the feature rows' name column, the link
-- box and the buttons.
local G = { W = 480, PAD = 20, IN = 16, LOGO = 40, NAME_W = 64, LINK_H = 30, BTN_H = 28 }
GC.WelcomeUI.G = G
GC.WelcomeUI.URL = URL

local TONE = {
  bad = { color = K.loss, icon = "warning" },
  warn = { color = K.warn, icon = "clock" },
  good = { color = K.profit, icon = "check" },
}

local frame

-- SetText with the text a FontString already holds does not redraw it (docs/addon/AGENTS.md
-- "Text"): clear first.
local function setText(fs, text)
  fs:SetText("")
  fs:SetText(text or "")
end

local function paint(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Places a wrapping FontString at (x, y) below the top of `parent`, `width` wide, and answers its
-- height. A FontString lays its text out when the text is set (Book.Layout's lesson, seen in game),
-- and setting the text it already holds does nothing ("Text"), so it is cleared, sized, then given
-- its text back: measured at this width, on the first open as on every other.
local function place(fs, parent, x, y, width)
  local text = fs:GetText() or ""
  fs:SetText("")
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  fs:SetWidth(width)
  fs:SetText(text)
  fs:Show()
  return math.ceil(fs:GetStringHeight() or 0)
end

local function wrapping(fs)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetMaxLines(0)
  return fs
end

local function label(parent, size, color)
  local fs = wrapping(Theme.Label(parent, size))
  paint(fs, color)
  return fs
end

local function heading(parent, size, color)
  local fs = wrapping(Theme.Heading(parent, size))
  paint(fs, color)
  return fs
end

local function isForever()
  return GC.Game and GC.Game.IsForever and GC.Game.IsForever(GC.Game.Passport()) and true or false
end

local function copyKeys()
  local mac = type(_G.IsMacClient) == "function" and _G.IsMacClient()
  return mac and "Cmd+C" or "Ctrl+C"
end

-- What Core/Welcome.lua's Prices needs, read off the client.
local function readStatus(now)
  local input = { now = now, forever = isForever() }
  local Data = GC.Data
  if input.forever then
    local payload = Data and Data.ForeverPayload and Data.ForeverPayload() or nil
    input.crowdTs = payload and payload.ts or nil
    local app = _G.GoldCap_AppData
    input.companion = type(app) == "table"
    input.writtenAt = input.companion and type(app.writtenAt) == "number" and app.writtenAt or nil
  elseif Data then
    input.origin = Data.OriginState and Data.OriginState() or "none"
    input.importedTs = GC.db and GC.db.imported and GC.db.imported.ts or nil
    input.bundledTs = Data.BundledTs and Data.BundledTs() or nil
    -- The save keeps a Companion error until a good write or a paste clears it, so a player who
    -- has since removed the Companion would hear about it forever: it counts only while the
    -- Companion's file is still there.
    if type(_G.GoldCap_AppData) == "table" then
      input.appError = Data.AppDataError and Data.AppDataError() or nil
    end
  end
  return GC.Welcome.Prices(input)
end
GC.WelcomeUI._ReadStatus = readStatus

local function ago(seconds)
  return GC.Util.FormatElapsedWords(seconds or 0) or ""
end

-- The card's two lines for a state: the status (what is true) and the body (what it means and
-- what to do about it).
local function statusText(s)
  local k = s.kind
  if k == "bundled" then
    if not s.age then return GC.L["No prices for your region yet"] end
    return GC.L["Only the prices GoldCap came with, from %s ago"]:format(ago(s.age))
  elseif k == "app" then
    return GC.L["Fresh prices from the Companion, %s ago"]:format(ago(s.age))
  elseif k == "app_stale" or k == "crowd_stale" then
    return GC.L["The Companion last sent prices %s ago"]:format(ago(s.age))
  elseif k == "manual" or k == "manual_stale" then
    return GC.L["You pasted these prices %s ago"]:format(ago(s.age))
  elseif k == "error" then
    return GC.L["The Companion's prices could not be read"]
  elseif k == "crowd" then
    return GC.L["Everyone's prices are in, from %s ago"]:format(ago(s.age))
  elseif k == "crowd_quiet" and s.age then
    return GC.L["Nobody has shared a scan of this auction house for %s"]:format(ago(s.age))
  elseif k == "crowd_missing" or k == "crowd_quiet" then
    return GC.L["No prices from other players for this auction house yet"]
  end
  return GC.L["Prices from your own scans only"]
end

local function bodyText(s)
  local k = s.kind
  if k == "bundled" and not s.age then
    return GC.L["GoldCap came with no prices for your region, so DEALS finds no deals until GoldCap Companion brings them."]
  elseif k == "bundled" then
    return GC.L["These prices came with GoldCap and change only when GoldCap itself updates. DEALS needs fresh prices from your realm to find anything, so until then it finds no deals."]
  elseif k == "app" then
    return GC.L["New prices reach GoldCap every time you log in or type /reload."]
  elseif k == "app_stale" then
    return GC.L["DEALS and every price go by what it sent last. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."]
  elseif k == "manual" then
    return GC.L["A pasted string goes stale within a day. GoldCap Companion fetches fresh prices for you every 30 minutes."]
  elseif k == "manual_stale" then
    return GC.L["With prices this old, DEALS can show deals that are no longer there. GoldCap Companion fetches fresh prices for you every 30 minutes."]
  elseif k == "error" then
    local why = GC.Data and GC.Data.DescribeImportError and GC.Data.DescribeImportError(s.reason) or tostring(s.reason)
    return GC.L["GoldCap could not read what the Companion wrote (%s). Update GoldCap and GoldCap Companion, then type /reload."]:format(why)
  elseif k == "crowd" then
    return GC.L["Your own scans and every other GoldCap player's are combined: for each item, the newer price wins."]
  elseif k == "crowd_stale" then
    return GC.L["Your own scans still work. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."]
  elseif k == "crowd_missing" then
    return GC.L["Your own scans work meanwhile. If GoldCap Companion is not running, start it and type /reload."]
  elseif k == "crowd_quiet" then
    return GC.L["GoldCap Companion is running and brings every scan of this auction house that GoldCap players share, but none has come in lately. Your own scans still work."]
  end
  return GC.L["GoldCap knows only what your own scans of this auction house found. With GoldCap Companion you also get the scans of every GoldCap player here: more items with a price, and newer prices."]
end

local FEATURES = {
  { icon = "deals", name = "DEALS" },
  { icon = "sell", name = "SELL" },
  { icon = "buy", name = "BUY" },
}

local function featureText(i, forever)
  if i == 1 then
    return forever and GC.L["Finds items listed below what a vendor pays, or far below their usual price."]
      or GC.L["Finds items listed below what they usually sell for, and checks each one before you buy."]
  elseif i == 2 then
    return GC.L["Prices everything in your bags. POST lists it, one item per click."]
  end
  return GC.L["Shopping lists for crafting: buys each item up to the price you set."]
end

local function close()
  if frame then frame:Hide() end
end

local function build()
  if frame then return frame end
  local f = CreateFrame("Frame", NAME, UIParent)
  f:SetSize(G.W, 400)
  f:SetPoint("CENTER")
  -- Above the docked GoldCap window and the auction house (HIGH), with its own mouse so a click
  -- never falls through ("Layering").
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.glass = Theme.Window(f)

  -- The GoldCap mark with the window's one warm light, as the rail draws it.
  f.logo = CreateFrame("Frame", nil, f)
  f.logo:SetSize(G.LOGO, G.LOGO)
  f.logo.mark = f.logo:CreateTexture(nil, "ARTWORK")
  f.logo.mark:SetTexture(Theme.MEDIA .. "GoldCap")
  f.logo.mark:SetAllPoints()
  f.logo.glow = Theme.Glow(f.logo, { K.gold[1], K.gold[2], K.gold[3], 0.22 }, 10)

  f.title = heading(f, 17, K.text1)
  f.sub = label(f, 12, K.text2)

  f.closeBtn = Theme.Button(f, "ghost")
  f.closeBtn:SetSize(20, 20)
  f.closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Theme.pad.s, -Theme.pad.s)
  f.closeBtn.icon = f.closeBtn:CreateTexture(nil, "ARTWORK")
  f.closeBtn.icon:SetSize(12, 12)
  f.closeBtn.icon:SetPoint("CENTER")
  Theme.SetIcon(f.closeBtn.icon, "close", K.text3)
  f.closeBtn:SetScript("OnClick", close)

  f.features = {}
  for i, feature in ipairs(FEATURES) do
    local row = { icon = f:CreateTexture(nil, "ARTWORK") }
    row.icon:SetSize(16, 16)
    Theme.SetIcon(row.icon, feature.icon, K.gold)
    -- The tabs' own names, as the window's rail spells them (UI/Theme.lua's Rail): untranslated.
    row.name = heading(f, 12, K.goldText)
    setText(row.name, feature.name)
    row.text = label(f, 12, K.text2)
    f.features[i] = row
  end

  local card = Theme.Card(f, { 1, 1, 1, 0.03 }, K.glassBorder)
  f.card = card
  card.icon = card:CreateTexture(nil, "ARTWORK")
  card.icon:SetSize(16, 16)
  card.status = heading(card, 14, K.text1)
  card.body = label(card, 12, K.text2)
  card.rule = card:CreateTexture(nil, "ARTWORK")
  card.rule:SetHeight(1)
  card.rule:SetColorTexture(K.hairline[1], K.hairline[2], K.hairline[3], K.hairline[4])
  card.ctaTitle = heading(card, 13, K.goldText)
  card.ctaSub = label(card, 12, K.text2)
  card.step1 = label(card, 12, K.text1)
  card.step2 = label(card, 12, K.text1)
  card.step3 = label(card, 12, K.text1)
  card.linkLabel = label(card, 12, K.text1)

  -- The link: a well with the URL in it, selected whole on a click so the copy keys just work.
  local box = Theme.Card(card, { 0, 0, 0, 0.35 }, K.glassBorder, true)
  box:SetHeight(G.LINK_H)
  card.box = box
  box.keys = Theme.Label(box, 11)
  paint(box.keys, K.text4)
  box.keys:SetJustifyH("RIGHT")
  box.keys:SetPoint("RIGHT", box, "RIGHT", -10, 0)
  local edit = CreateFrame("EditBox", nil, box)
  edit:SetFontObject(_G.ChatFontNormal)
  edit:SetAutoFocus(false)
  edit:SetHeight(20)
  edit:SetPoint("LEFT", box, "LEFT", 10, 0)
  edit:SetPoint("RIGHT", box, "RIGHT", -64, 0)
  edit:SetText(URL)
  edit:SetCursorPosition(0)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  edit:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); close() end)
  edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  -- The link is read-only in spirit: typed over, it comes straight back, selected.
  edit:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= URL then
      self:SetText(URL)
      self:HighlightText()
    end
  end)
  box.edit = edit

  f.hint = label(f, 11, K.text4)

  f.ok = Theme.Button(f, "primary", "plaque")
  f.ok:SetUppercase(true)
  -- Gold, without the halo: the glow belongs to the Sell dock's POST and CANCEL alone (the
  -- owner's call of 2026-10-09; the Sell tab's cost dialog lost its own for the same reason).
  f.ok:SetGlow(false)
  f.ok:SetHeight(G.BTN_H)
  f.ok:SetScript("OnClick", close)
  f.quiet = Theme.Button(f, "ghost", "plaque")
  f.quiet:SetUppercase(true)
  f.quiet:SetHeight(G.BTN_H)
  f.quiet:SetScript("OnClick", function()
    if GC.db then GC.Welcome.Quiet(GC.db.welcome) end
    close()
  end)

  -- Escape shuts this window and nothing else. Listed in UISpecialFrames it went out together
  -- with the auction house on one press: Escape runs CloseAllWindows, which hides the UI panels
  -- and the special frames in one pass. So the window keeps only Escape from going on, decided
  -- per keystroke, and lets every other key through. In combat it stands down:
  -- SetPropagateKeyboardInput is restricted there (UI/Sell/Inspector.lua, UI/BuyFrame.lua), and
  -- open() left the keys going on.
  f:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown and InCombatLockdown() then return end
    if key ~= "ESCAPE" then
      self:SetPropagateKeyboardInput(true)
      return
    end
    self:SetPropagateKeyboardInput(false)
    close()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if not (InCombatLockdown and InCombatLockdown()) then self:SetPropagateKeyboardInput(true) end
      end)
    end
  end)
  f:Hide()
  frame = f
  return f
end
GC.WelcomeUI._Build = build

-- Lays the window out for `mode` ("welcome" | "prices") and `status` (Core/Welcome.lua's
-- Prices), top to bottom, and sizes it to what it holds.
local function layout(f, mode, status, quietOffered)
  local forever = isForever()
  local inner = G.W - 2 * G.PAD
  local y = G.PAD

  -- Head: the mark, the title and, on the welcome, the line under it.
  f.logo:ClearAllPoints()
  f.logo:SetPoint("TOPLEFT", f, "TOPLEFT", G.PAD, -y)
  local headX = G.PAD + G.LOGO + 12
  local headW = G.W - headX - G.PAD - 20
  setText(f.title, mode == "welcome" and GC.Util.Upper(GC.L["Welcome to GoldCap"])
    or GC.Util.Upper(GC.L["Your GoldCap prices"]))
  local head = place(f.title, f, headX, y + 2, headW)
  if mode == "welcome" then
    setText(f.sub, GC.L["GoldCap puts its prices in item tooltips. At the auction house, the GoldCap tab has:"])
    head = head + 4 + place(f.sub, f, headX, y + 2 + head + 4, headW)
  else
    f.sub:Hide()
  end
  y = y + math.max(G.LOGO, head + 2) + 18

  -- What GoldCap does: the welcome only.
  for i, row in ipairs(f.features) do
    if mode == "welcome" then
      setText(row.text, featureText(i, forever))
      row.icon:ClearAllPoints()
      row.icon:SetPoint("TOPLEFT", f, "TOPLEFT", G.PAD, -(y + 1))
      row.icon:Show()
      place(row.name, f, G.PAD + 24, y + 1, G.NAME_W)
      local h = place(row.text, f, G.PAD + 24 + G.NAME_W + 8, y, inner - 24 - G.NAME_W - 8)
      y = y + math.max(18, h) + 10
    else
      row.icon:Hide(); row.name:Hide(); row.text:Hide()
    end
  end
  if mode == "welcome" then y = y + 6 end

  -- The card: the state of the prices, in its tone's colour, and what to do about it.
  local card, tone = f.card, TONE[status.tone] or TONE.warn
  local cw = inner - 2 * G.IN
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", f, "TOPLEFT", G.PAD, -y)
  card:SetTint({ tone.color[1], tone.color[2], tone.color[3], 0.06 },
    { tone.color[1], tone.color[2], tone.color[3], 0.5 })
  Theme.SetIcon(card.icon, tone.icon, tone.color)
  card.icon:ClearAllPoints()
  card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", G.IN, -(G.IN + 1))
  setText(card.status, statusText(status))
  paint(card.status, tone.color)
  local cy = G.IN
  cy = cy + math.max(16, place(card.status, card, G.IN + 24, cy, cw - 24)) + 8
  setText(card.body, bodyText(status))
  cy = cy + place(card.body, card, G.IN, cy, cw)

  local cta = status.cta
  for _, fs in ipairs({ card.ctaTitle, card.ctaSub, card.step1, card.step2, card.step3, card.linkLabel }) do
    fs:Hide()
  end
  if cta then
    cy = cy + 14
    card.rule:ClearAllPoints()
    card.rule:SetPoint("TOPLEFT", card, "TOPLEFT", G.IN, -cy)
    card.rule:SetWidth(cw)
    card.rule:Show()
    cy = cy + 14
    if cta == "install" then
      setText(card.ctaTitle, GC.Util.Upper(GC.L["Get GoldCap Companion"]))
      cy = cy + place(card.ctaTitle, card, G.IN, cy, cw) + 6
      setText(card.ctaSub, forever
        and GC.L["A small free app for Windows, macOS and Linux. Every 30 minutes it brings the prices every GoldCap player scanned on your auction house, with no account needed. Its code is open on GitHub."]
        or GC.L["A small free app for Windows, macOS and Linux. It fetches your realm's prices every 30 minutes, with no account needed. Its code is open on GitHub."])
      cy = cy + place(card.ctaSub, card, G.IN, cy, cw) + 12
      setText(card.step1, GC.L["1. Copy this link (%s) and open it in your browser:"]:format(copyKeys()))
      cy = cy + place(card.step1, card, G.IN, cy, cw) + 6
    else
      setText(card.linkLabel, cta == "update" and GC.L["The latest version is here:"]
        or GC.L["Not installed on this computer? It is here:"])
      cy = cy + place(card.linkLabel, card, G.IN, cy, cw) + 6
    end
    card.box:ClearAllPoints()
    card.box:SetPoint("TOPLEFT", card, "TOPLEFT", G.IN, -cy)
    card.box:SetWidth(cw)
    card.box:Show()
    setText(card.box.keys, copyKeys())
    cy = cy + G.LINK_H
    if cta == "install" then
      setText(card.step2, GC.L["2. Install GoldCap Companion and start it."])
      cy = cy + 10 + place(card.step2, card, G.IN, cy + 10, cw)
      setText(card.step3, GC.L["3. Back in the game, type /reload."])
      cy = cy + 4 + place(card.step3, card, G.IN, cy + 4, cw)
    end
  else
    card.rule:Hide()
    card.box:Hide()
  end
  cy = cy + G.IN
  card:SetSize(inner, cy)
  y = y + cy + 14

  -- Foot: how to get back here, then the buttons.
  setText(f.hint, GC.L["/gc companion opens this window again."])
  y = y + place(f.hint, f, G.PAD, y, inner) + 12
  f.ok:SetLabel(GC.L["Got it"])
  f.ok:SetWidth(110)
  f.ok:FitLabels({ GC.L["Got it"] }, 110)
  f.ok:ClearAllPoints()
  f.ok:SetPoint("TOPRIGHT", f, "TOPRIGHT", -G.PAD, -y)
  if quietOffered then
    f.quiet:SetLabel(GC.L["Don't remind me"])
    f.quiet:SetWidth(140)
    f.quiet:FitLabels({ GC.L["Don't remind me"] }, 110)
    f.quiet:ClearAllPoints()
    f.quiet:SetPoint("RIGHT", f.ok, "LEFT", -Theme.pad.s, 0)
    f.quiet:Show()
  else
    f.quiet:Hide()
  end
  y = y + G.BTN_H + G.PAD
  f:SetHeight(y)
end
GC.WelcomeUI._Layout = layout

-- Opens the window for `mode`. `byPlayer`: the player asked for it, so the link takes the keyboard
-- at once, ready to copy. Answers the status it drew.
local function open(mode, byPlayer, status)
  local f = build()
  status = status or readStatus(time())
  -- "Don't remind me" belongs to a window that came back by itself: the welcome is the first word,
  -- and a player who asked for the window is not being reminded of anything.
  layout(f, mode, status, not byPlayer and mode == "prices" and status.tone ~= "good")
  -- The keyboard, for Escape alone (OnKeyDown above), and only out of combat, where keys can be
  -- let through: opened in a fight (/gc companion), the window takes no keys at all.
  local calm = not (InCombatLockdown and InCombatLockdown())
  f:EnableKeyboard(calm)
  if calm then f:SetPropagateKeyboardInput(true) end
  f:Show()
  if f.Raise then f:Raise() end
  local edit = f.card.box.edit
  if byPlayer and status.cta then
    edit:SetFocus()
    edit:HighlightText()
  else
    edit:ClearFocus()
  end
  return status
end

--- The player asked (/gc companion, the Deals window's price line): the welcome if they have never
-- seen it, otherwise the prices.
function GC.CompanionUI.Show()
  local w = GC.db and GC.db.welcome or nil
  local status = open((w and w.firstRun and not w.seen) and "welcome" or "prices", true)
  if w then GC.Welcome.MarkOpened(w, status, time()) end
end

function GC.CompanionUI.Hide()
  close()
end

function GC.WelcomeUI.IsShown()
  return frame ~= nil and frame:IsShown() == true
end

--- An auction house visit (Core/Init.lua): opens the window when Core/Welcome.lua says so.
function GC.WelcomeUI.MaybeShow()
  local w = GC.db and GC.db.welcome
  if type(w) ~= "table" or GC.WelcomeUI.IsShown() then return end
  local now = time()
  local status = readStatus(now)
  local mode = GC.Welcome.Decide(w, status, now)
  if not mode then return end
  open(mode, false, status)
  GC.Welcome.MarkShown(w, status, now)
end

GC.slashHandlers.companion = function() GC.CompanionUI.Show() end
GC.slashHandlers.welcome = function()
  local status = open("welcome", true)
  if GC.db and GC.db.welcome then GC.Welcome.MarkOpened(GC.db.welcome, status, time()) end
end
