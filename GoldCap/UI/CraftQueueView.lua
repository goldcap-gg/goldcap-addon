local _, GC = ...

-- The craft panel's Queue view (retail, beside the profession window): this character's queued
-- recipes with what is left to craft, the reagents the queue is short of, and Make a BUY list,
-- which writes what the queue needs into the character's one Craft queue list for the BUY tab at
-- the auction house. Nothing is bought here, and nothing is crafted here: a craft from Blizzard's
-- own button takes one off a counted line all the same (UNIT_SPELLCAST_SUCCEEDED).
--
-- That list follows the queue: every change to the queue, and to what a restock holds, rewrites
-- its lines (SyncBuyList), so BUY never buys again what a craft already used. It is known by the
-- code GC.db.craft keeps for the character, never by its name: the player's other lists, one
-- named Craft queue included, are never touched, and one the player deleted is made again only
-- by the button.
--
-- Its events are its own, each registered under pcall (Core/Collection.lua's shape), so
-- Core/Init.lua is not touched. The arithmetic is Core/CraftQueue.lua's; every count and price
-- comes through Services/CraftClient.lua.
GC.CraftQueueView = GC.CraftQueueView or {}
local QV = GC.CraftQueueView

local LAYOUT = { GAP = 6, LINE_GAP = 2, NAME = 11, SMALL = 10, HEAD = 12, ROW_PAD = 4, BAR = 16,
  BUTTON_H = 24, BUTTON_MIN = 72 }

local function bodyWidth()
  return GC.CraftPanel and GC.CraftPanel.BODY_W or 280
end

local function after(fn)
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, fn) else fn() end
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function wrapped(parent, size, width)
  local fs = GC.Theme.Label(parent, size)
  fs:SetWordWrap(true)
  fs:SetWidth(width)
  return fs
end

-- How many of an item `char` holds, its mailbox included (Services/CraftClient.lua's CountOf), for
-- every count of one pass over the queue: the character is read once by the caller, not per item.
local function counter(char)
  local CC = GC.CraftClient
  return function(itemID) return CC.CountOf(itemID, char) end
end

-- What the queue needs that waits in the mailbox (Core/MailStock.lua, retail only), one row per
-- reagent ({ itemID, n }): held, so not missing, but Blizzard's Create takes reagents from the
-- bags and the banks alone. `n` is what the bags and the banks do not cover of the need.
local function inMailbox(needs, char, countOf)
  local stock = GC.MailStock
  local out = {}
  if not stock then return out end
  for _, row in ipairs(needs) do
    local mail, held, named = 0, 0, nil
    for _, id in ipairs(row.ids or {}) do
      local m = stock.Count(char, id)
      if m > 0 and not named then named = id end
      mail = mail + m
      held = held + countOf(id) - m
    end
    local n = math.min(mail, row.q - held)
    if named and n > 0 then out[#out + 1] = { itemID = named, n = n } end
  end
  return out
end

-- The queue as it stands: one row per entry ({ entry, crafts, held }), what the queue is short
-- of, when the auction house was last read for this character (nil: not yet), what the queue
-- needs in all, and what of that waits in the mailbox.
local function work(char)
  local CC, Q = GC.CraftClient, GC.CraftQueue
  local countOf = counter(char)
  local entries = Q.Entries(char)
  local listed, listedAt = Q.Listed(char, time())
  local rows, crafts = {}, {}
  for i, e in ipairs(entries) do
    local held = e.restock and Q.Held(e, countOf, listed) or nil
    local n = Q.CraftsNeeded(e, held or 0)
    crafts[e] = n
    rows[i] = { entry = e, crafts = n, held = held }
  end
  local needs = Q.Needs(entries, function(e) return crafts[e] end)
  return rows, Q.Missing(needs, countOf, CC.CurrencyCount), listedAt, needs, inMailbox(needs, char, countOf)
end

--- What `char`'s queue needs in all (Core/CraftQueue.lua's Needs), over what each entry has left
--- to craft as this view counts it, and how many crafts that is. The GoldCap Hoard's For your
--- crafts tile (UI/HoardTiles.lua) asks it and counts the bags alone against it.
function QV.Needs(char)
  local rows, _, _, needs = work(char)
  local crafts = 0
  for _, row in ipairs(rows) do crafts = crafts + row.crafts end
  return needs, crafts
end

-- Whether the queue is short of anything the BUY tab can buy (a currency it cannot).
local function buyable(missing)
  for _, row in ipairs(missing) do
    if type(row.ids) == "table" and row.ids[1] then return true end
  end
  return false
end

-- The character's craft queue list, while the store may be written and the list is still there.
local function listOf(char)
  local Q = GC.CraftQueue
  local code = char and Q.Writable() and Q.BuyList(char) or nil
  local run = code and GC.AppRuns.Get(code) or nil
  return (type(run) == "table" and run.origin == "game") and run or nil
end

-- Writes what the queue needs into the character's craft queue list, making it when the
-- character has none (named "Craft queue: <character>"). Returns the list and whether its lines changed, or
-- nil when nothing may be written.
local function writeList(char, needs)
  local CC, Q = GC.CraftClient, GC.CraftQueue
  local lines = Q.BuyLines(needs, CC.UnitOf, counter(char), CC.VendorOf)
  local run = listOf(char)
  if run then return GC.AppRuns.SetLines(run.code, lines) end
  if not (char and Q.Writable()) then return nil end
  -- Lists are account wide: the character's name keeps two characters' queues apart in BUY.
  run = GC.AppRuns.NewList(GC.L["Craft queue"] .. ": " .. (char:match("^([^%-]+)") or char), lines)
  if not (run and Q.SetBuyList(char, run.code)) then return nil end
  return run, true
end

--- The queue changed, or what it holds did: its list, when the character has one, says what the
--- queue needs now. Only the button makes one. BUY rebuilds a list whose updatedAt moved the next
--- time it shows (UI/BuyFrame.lua's ensureRun); the one it holds now is rebuilt here, so what it
--- counts as bought is read afresh, unless a purchase is in the client's hands. Returns the list
--- or nil.
function QV.SyncBuyList()
  local char = GC.CraftClient.Char()
  if not listOf(char) then return nil end
  local _, _, _, needs = work(char)
  local run, changed = writeList(char, needs)
  local buy = GC.Buy
  local shown = changed and buy and buy.CurrentRun and buy.CurrentRun() or nil
  if shown and shown:Code() == run.code and not (buy._InFlight and buy._InFlight()) then
    buy.SelectRun(run.code)
    if buy.RefreshIfShown then buy.RefreshIfShown() end
  end
  return run
end

--- A queue line's right click: more crafts, a restock target, or off the queue.
function QV.OpenLineMenu(owner, entry)
  local menu = _G.MenuUtil
  if not (type(menu) == "table" and menu.CreateContextMenu and type(entry) == "table" and GC.CraftQueue.Writable()) then
    return false
  end
  local recipe = entry.recipe
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(GC.Util.ClientText(recipe.name))
    root:CreateButton(GC.Util.ClientText(GC.L["Add to queue"]), function() GC.CraftPanel.AskCount(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Restock to"]), function() GC.CraftPanel.AskRestock(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Remove from queue"]), function()
      local char = GC.CraftClient.Char()
      if char then GC.CraftQueue.Remove(char, recipe.recipeID) end
      QV.SyncBuyList()
      QV.Queue()
    end)
  end)
  return true
end

local function newLine(v)
  local T = GC.Theme
  local width = bodyWidth() - LAYOUT.BAR
  local frame = CreateFrame("Button", nil, v.content)
  frame:SetWidth(width)
  local line = { frame = frame }
  line.name = wrapped(frame, LAYOUT.NAME, width)
  line.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LAYOUT.ROW_PAD)
  setColor(line.name, T.color.fg)
  line.detail = wrapped(frame, LAYOUT.SMALL, width)
  line.detail:SetPoint("TOPLEFT", line.name, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  setColor(line.detail, T.color.fgMuted)
  line.note = wrapped(frame, LAYOUT.SMALL, width)
  line.note:SetPoint("TOPLEFT", line.detail, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  setColor(line.note, T.color.fgDim)
  frame:RegisterForClicks("RightButtonUp")
  frame:SetScript("OnClick", function(self, button)
    if button == "RightButton" and line.entry then QV.OpenLineMenu(self, line.entry) end
  end)
  return line
end

--- Builds the view in the panel's body (UI/CraftPanel.lua calls this once, hidden until picked).
function QV.Build(host)
  if QV._frame then return QV._frame end
  local T = GC.Theme
  local width = bodyWidth() - LAYOUT.BAR
  local v = CreateFrame("Frame", nil, host)
  v:SetAllPoints(host)
  v.buy = T.Button(v, "primary", "plaque")
  v.buy:SetHeight(LAYOUT.BUTTON_H)
  v.buy:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0)
  v.buy:SetScript("OnClick", function() QV.MakeBuyList() end)
  v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(v.scroll) end
  v.scroll:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -LAYOUT.BAR, LAYOUT.BUTTON_H + LAYOUT.GAP)
  v.content = CreateFrame("Frame", nil, v.scroll)
  v.content:SetSize(width, 1)
  v.scroll:SetScrollChild(v.content)
  v.empty = wrapped(v.content, LAYOUT.NAME, width)
  setColor(v.empty, T.color.fgMuted)
  v.missingHeading = T.Heading(v.content, LAYOUT.HEAD)
  v.missingHeading:SetJustifyH("LEFT")
  v.missingHeading:SetWordWrap(true)
  v.missingHeading:SetWidth(width)
  setColor(v.missingHeading, T.color.gold)
  v.none = wrapped(v.content, LAYOUT.SMALL, width)
  setColor(v.none, T.color.fgMuted)
  v.lines, v.missingLines = {}, {}
  v:Hide()
  QV._frame = v
  return v
end

-- Places `region` at `y` down the content and answers the y under it.
local function stack(v, region, y, gap)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -(y + gap))
  region:Show()
  return y + gap + region:GetHeight()
end

local function paintLine(line, row, listedAt)
  local e = row.entry
  line.entry = e
  line.name:SetText(e.recipe.name)
  if e.count then
    line.detail:SetText(GC.L["%d to craft"]:format(e.count))
  else
    line.detail:SetText(GC.L["Restock to %d: %d held"]:format(e.restock, row.held or 0))
  end
  local height = LAYOUT.ROW_PAD + line.name:GetHeight() + LAYOUT.LINE_GAP + line.detail:GetHeight()
  -- A restock counts what is up on the auction house too, and that is read only there, when
  -- something asks the auction house for the character's own auctions: in GoldCap, the Sell tab
  -- (Services/Sell/Owned.lua). Until then, say so rather than craft more than is needed without
  -- a word.
  if e.restock and listedAt == nil then
    line.note:SetText(GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"])
    line.note:Show()
    height = height + LAYOUT.LINE_GAP + line.note:GetHeight()
  else
    line.note:Hide()
  end
  line.frame:SetHeight(height + LAYOUT.ROW_PAD)
end

local function missingText(row)
  local CC = GC.CraftClient
  if row.currency then
    return GC.L["%s is not sold on the auction house"]:format(CC.MissingName({ currencyID = row.currency }))
  end
  return GC.L["%d %s"]:format(row.missing, CC.MissingName({ itemID = row.ids[1] }))
end

--- Reads the queue again and repaints the view, while it is on screen.
function QV.Refresh()
  QV._pending = false
  local v = QV._frame
  if not (v and v:IsVisible()) then return end
  local char = GC.CraftClient.Char()
  local rows, missing, listedAt, _, mailed = work(char)
  QV._rows = rows
  local y = 0
  for i, row in ipairs(rows) do
    local line = v.lines[i] or newLine(v)
    v.lines[i] = line
    paintLine(line, row, listedAt)
    row.widget = line
    y = stack(v, line.frame, y, 0)
  end
  for i = #rows + 1, #v.lines do
    v.lines[i].frame:Hide()
    v.lines[i].entry = nil
  end

  local width = bodyWidth() - LAYOUT.BAR
  if #rows == 0 then
    v.empty:SetText(GC.L["The queue is empty. Add a recipe from This recipe."])
    y = stack(v, v.empty, y, LAYOUT.ROW_PAD)
    v.missingHeading:Hide()
    v.none:Hide()
  else
    v.empty:Hide()
    v.missingHeading:SetText(GC.L["Missing"])
    y = stack(v, v.missingHeading, y, 2 * LAYOUT.GAP)
    if #missing == 0 then
      v.none:SetText(GC.L["Nothing is missing for the queue"])
      y = stack(v, v.none, y, LAYOUT.LINE_GAP)
    else
      v.none:Hide()
    end
  end
  -- Under Missing, what is held but waits in the mailbox: take it out before crafting.
  local texts = {}
  if #rows > 0 then
    for _, row in ipairs(missing) do texts[#texts + 1] = missingText(row) end
    for _, row in ipairs(mailed) do
      texts[#texts + 1] = GC.L["%d %s in the mailbox"]:format(row.n, GC.CraftClient.MissingName({ itemID = row.itemID }))
    end
  end
  local shown = #texts
  for i = 1, shown do
    local fs = v.missingLines[i]
    if not fs then
      fs = wrapped(v.content, LAYOUT.SMALL, width)
      setColor(fs, GC.Theme.color.fg)
      v.missingLines[i] = fs
    end
    fs:SetText(texts[i])
    y = stack(v, fs, y, LAYOUT.LINE_GAP)
  end
  for i = shown + 1, #v.missingLines do v.missingLines[i]:Hide() end
  v.content:SetHeight(math.max(1, y + LAYOUT.ROW_PAD))

  v.buy:SetLabel(GC.L["Make a BUY list"])
  v.buy:FitLabels({ v.buy.label }, LAYOUT.BUTTON_MIN)
  if buyable(missing) then v.buy:Enable() else v.buy:Disable() end
end

--- One repaint on the next frame, however many times this is asked for before then.
function QV.Queue()
  if QV._pending then return end
  QV._pending = true
  after(QV.Refresh)
end

--- The character's craft queue list, made when it has none (named "Craft queue"), holding what
--- the queue needs (Core/CraftQueue.lua's BuyLines), out of the archive and shown in the BUY tab.
--- Returns the list, or nil when nothing is missing.
function QV.MakeBuyList()
  local char = GC.CraftClient.Char()
  if not char then return nil end
  local _, missing, _, needs = work(char)
  if not buyable(missing) then return nil end
  local run = writeList(char, needs)
  if not run then return nil end
  GC.AppRuns.SetArchived(run.code, false)
  if GC.Buy and GC.Buy.SelectRun then GC.Buy.SelectRun(run.code) end
  if GC.Buy and GC.Buy.RefreshIfShown then GC.Buy.RefreshIfShown() end
  GC.Print(GC.L["BUY list %s is ready in the BUY tab at the auction house"]:format(GC.AppRuns.Label(run)))
  return run
end

-- Whether a visit to the mailbox is going on (Core/MailStock.lua, retail only). The client is
-- asked as well, as UI/SniperFrame.lua's _ClearStaleMailPause asks it: walking from the mailbox
-- straight to an auctioneer can shut it with no MAIL_CLOSED (in game 2026-09-23), and a visit left
-- open would keep the bags uncounted. A client that cannot say leaves it to the events.
local function mailboxOpen()
  if not (GC.MailStock and GC.MailStock.IsOpen()) then return false end
  local manager, kinds = _G.C_PlayerInteractionManager, _G.Enum and _G.Enum.PlayerInteractionType
  if manager and manager.IsInteractingWithNpcOfType and kinds and kinds.MailInfo then
    local ok, open = pcall(manager.IsInteractingWithNpcOfType, kinds.MailInfo)
    if ok and open == false then return false end
  end
  return true
end

--- UNIT_SPELLCAST_SUCCEEDED: a craft of a counted recipe takes one off its line, the window open
--- or not. OWNED_AUCTIONS_UPDATED: what this character has up on the auction house, for restocks.
--- BAG_UPDATE_DELAYED: what a restock holds, which a craft of it adds to only once the item is in
--- the bags. MAIL_CLOSED: what waits in the mailbox, as the visit's last read of the inbox left it
--- (Core/MailStock.lua): a reagent's other quality or a crafted item there is held too. Each one
--- brings the craft queue list in step (SyncBuyList).
---
--- While the mailbox is open the bags are not counted: a take can reach the bags before the read of
--- the inbox that sees it gone, and for that moment the units count twice. The list would shrink
--- with them, and what it lowered as bought would not come back when the read caught up.
--- MAIL_CLOSED counts once, when the visit is over.
function QV.OnEvent(event, ...)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    -- Every cast the player makes lands here. In a restricted context the client hands a secret
    -- spell id, which addon code may not compare: such a cast is never a craft from the queue.
    local ok, changed = pcall(function()
      local secret = _G.issecretvalue
      if type(secret) == "function" and secret(spellID) then return false end
      local char = GC.CraftClient.Char()
      return char ~= nil and GC.CraftQueue.OnCraftSucceeded(char, spellID)
    end)
    if ok and changed then
      QV.SyncBuyList()
      QV.Queue()
    end
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    if GC.CraftClient.ReadListed() then
      QV.SyncBuyList()
      QV.Queue()
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    if not mailboxOpen() then QV.SyncBuyList() end
  elseif event == "MAIL_CLOSED" then
    -- Core/Init.lua ends the visit too; whichever frame hears the event first ends it, so what is
    -- counted here is what the visit settled.
    if GC.MailStock then GC.MailStock.Closed() end
    QV.SyncBuyList()
    QV.Queue()
  end
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
  pcall(events.RegisterEvent, events, "OWNED_AUCTIONS_UPDATED")
  pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
  pcall(events.RegisterEvent, events, "MAIL_CLOSED")
  events:SetScript("OnEvent", function(_, event, ...) QV.OnEvent(event, ...) end)
  QV._events = events
end

--- What the panel's This recipe and row menu add or restock: into the list, and on screen at once.
function QV.OnQueueChanged()
  QV.SyncBuyList()
  QV.Refresh()
end

if GC.CraftPanel then GC.CraftPanel.OnQueueChanged = QV.OnQueueChanged end
