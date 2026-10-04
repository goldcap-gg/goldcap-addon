local _, GC = ...

-- The BUY tab's search of the auction house, as Auctionator's Shopping tab has it: a name typed in
-- the item box at the top (UI/BuyAddBox.lua, through GC.Buy._SearchSubmit) is looked for among
-- everything on sale right now, and the answer is a table in the tab's right-hand pane in place of
-- the list -- each item key on sale, its cheapest price and how many there are -- until the player
-- goes back to the list. The lists stay as they are.
--
-- A result clicked opens in the dock BUY already has (UI/BuyFrame.lua): a run of one line that lives
-- only in memory, CODE, so a commodity is quoted and bought BUY then CONFIRM, and gear one lot per
-- press under its own exact item key, both through planBuyClick and GC.PurchaseCall.Click and
-- nothing else -- this file names no purchase call. What it buys is booked as BUY's purchases are,
-- on no list. The line's cap is BUY's default: the item's market price times the player's BUY cap
-- percent; the dock's RAISE CAP TO and a typed cap (the result's right-click) hold for this session.
-- No market price, no cap: gear is never bid on without one.
--
-- The request itself is Core/BuySearchModel.lua's, under the addon's request rules; this file is
-- its driver and the drawing. The browse answer is offered here by UI/SniperFrame.lua's
-- OnBrowseResults, after a keys batch's own claim and before the book pass's
-- (docs/addon/AGENTS.md, "Sharing the search slot"). Its own file: UI/BuyFrame.lua is near its
-- ceiling of top-level locals.
GC.BuySearch = {}
local S = GC.BuySearch

-- The opened result's run code. A space: a pasted GCR1 code never holds one (the paste drops white
-- space), the site's are eight letters and digits, the game's "game-N" -- so it is nobody's list,
-- and the companion leaves it off what it uploads anyway.
S.CODE = "buy search"
-- The player's own price per item for a result, for this session (UI/BuyFrame.lua's lineCapsFor),
-- and what the opened result has bought (its run's progress). Never in SavedVariables.
S._caps = {}
S._progress = {}

local LAYOUT = { HEAD_MIN = 24, HEADING_H = 16, ROW_H = 24, ICON = 18, INSET = 26, PRICE_MIN = 72,
  AVAIL_MIN = 64, STRIP_H = 30, BOX_W = 64, MORE_H = 24, BUTTON_MIN = 72, GAP = 4 }

-- @localised-keys: literals in this table ARE GC.L keys, looked up where the headings are drawn.
-- The table closes with a `}` on its own line.
local HEADING = {
  name = "ITEM", price = "PRICE FROM", avail = "AVAILABLE",
}

local panel, build
local request
local shown = false
-- The row (Core/BuySearchModel.lua's KeyString) opened in the dock, how many it asks for, and what
-- the last "add to list" did.
local opened, openedQty, note

function S.IsCode(code) return code == S.CODE end
function S.Progress() return S._progress end
function S.Shown() return shown end
-- A browse request out and unanswered: BUY's own per-item searches wait for it (UI/BuyFrame.lua).
function S.Pending() return request ~= nil and request:Pending() end
-- Whether the search holds the browse list: every other writer of it stands down
-- (UI/SniperFrame.lua's GC.Sniper._BrowseOwned).
function S.OwnsBrowse() return request ~= nil and request:Owns() end

local function setColor(fs, c)
  if fs and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function measure(fs)
  local w = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  return type(w) == "number" and math.ceil(w) or nil
end

local function heightOf(fs)
  local h = fs and fs.GetStringHeight and fs:GetStringHeight()
  return type(h) == "number" and math.ceil(h) or 12
end

local function fitButton(btn, minW)
  local w = measure(btn.text)
  if w then btn:SetWidth(math.max(minW, w + 2 * GC.Theme.pad.m)) end
end

local function ahOpen()
  return GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen() or false
end

local function itemName(itemID)
  if not (C_Item and C_Item.GetItemInfo) then return nil end
  local ok, name = pcall(C_Item.GetItemInfo, itemID)
  return (ok and type(name) == "string" and name ~= "") and name or nil
end

local function nameOf(row)
  return row.name or itemName(row.itemID) or ("#" .. tostring(row.itemID))
end

local function rowById(id)
  for _, row in ipairs(request and request.rows or {}) do
    if row.id == id then return row end
  end
  return nil
end

-- The browse sorts Blizzard's own Buy list sends: cheapest first, then by name.
local function browseSorts()
  local order = Enum and Enum.AuctionHouseSortOrder
  if not order then return {} end
  return { { sortOrder = order.Price, reverseSort = false }, { sortOrder = order.Name, reverseSort = false } }
end

-- The one browse query this file sends. A result opened from the last answer is closed first (the
-- request goes only once no purchase holds the search), and every other writer of the browse list
-- stands down for the player's own search: a book pass paging is abandoned, a keys batch still out
-- given up (UI/SniperFrame.lua's _OnPlayerBrowse). `addonBrowse` tells UI/AuctionHouseTab.lua's
-- post-hook it is GoldCap's, so the visit is not marked as the player's on Blizzard's own pane.
local function sendBrowse(text)
  GC.Buy._OpenSearchRun(nil)
  opened, note = nil, nil
  if GC.Sniper and GC.Sniper._OnPlayerBrowse then GC.Sniper._OnPlayerBrowse() end
  local tab = GC.AuctionHouseTab
  if tab then tab.addonBrowse = true end
  C_AuctionHouse.SendBrowseQuery({ searchString = text, sorts = browseSorts(), filters = {}, itemClassFilters = {} })
  if tab then tab.addonBrowse = false end
end

local function newRequest()
  return GC.BuySearchModel.NewRequest({
    now = function() return time() end,
    ahOpen = ahOpen,
    purchaseBusy = function()
      return (GC.Buy._InFlight() or GC.Buy.HoldsSearch()
        or (GC.Sniper and GC.Sniper.IsPurchaseQuiet and GC.Sniper.IsPurchaseQuiet())) and true or false
    end,
    keysOut = function() return (GC.Sniper and GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding()) or false end,
    writeOffKeys = function() GC.Sniper._WriteOffKeys("player search") end,
    ready = function()
      return GC.Util.ThrottleReady() and GC.Util.ClaimThrottleSend("buy-search") or false
    end,
    send = sendBrowse,
    more = function() C_AuctionHouse.RequestMoreBrowseResults() end,
    browseSeq = function() return GC.Buy._browseSeq or 0 end,
    results = function() return C_AuctionHouse.GetBrowseResults() or {} end,
    full = function() return C_AuctionHouse.HasFullBrowseResults() end,
    infoOf = function(key)
      local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
      return ok and info or nil
    end,
    keysOrphan = function(results)
      return (GC.Sniper and GC.Sniper._IsOrphanAnswer and GC.Sniper._IsOrphanAnswer(results)) or false
    end,
  })
end

-- What the request is doing, as one string, so a tick repaints only when it changed.
local function signature()
  if not request then return "" end
  return table.concat({ request.state, tostring(request.reason), tostring(request.failed),
    tostring(GC.Buy._aside ~= nil) }, "|")
end

-- ---------------------------------------------------------------------------
-- Opening a result, and adding one to a list
-- ---------------------------------------------------------------------------

--- Opens the row `id` in the dock, buying `qty` (what the search asked for, by default). Not while
--- a purchase is in the client's hands: CONFIRM belongs to its own line. A gear row carries its own
--- item key, so the dock arms that variant at once. Answers whether it opened.
function S.Open(id, qty)
  local row = rowById(id)
  if not row or GC.Buy._InFlight() then return false end
  qty = qty or (opened == id and openedQty) or (request.query and request.query.qty) or 1
  if opened ~= id then S._progress = {} end
  local line = { i = row.itemID, q = qty, n = row.name,
    key = (row.known and row.commodity == false) and row.itemKey or nil }
  if not GC.Buy._OpenSearchRun({ code = S.CODE, name = row.name, lines = { line } }) then return false end
  opened, openedQty = id, qty
  GC.Buy.RefreshIfShown()
  -- The dock asks for its line's price at once, as a click on a list's line does.
  GC.Buy.Tick()
  return true
end

--- The opened result asks for `qty` now (the box under the results); what it bought stays.
function S.SetQty(qty)
  qty = tonumber(qty)
  if not (opened and qty and qty >= 1) then return false end
  return S.Open(opened, math.floor(qty))
end

-- The player's own lists (made in the game or pasted): the only ones the game adds to.
local function ownLists()
  local out = {}
  for _, run in ipairs(GC.AppRuns.List()) do
    if GC.AppRuns.IsLocal(run) then out[#out + 1] = run end
  end
  return out
end

--- Adds `qty` of the row's item to the list `code`, or to a new list with nil, and says so under the
--- results. The search stays on screen. Answers whether it added.
function S.AddToList(id, code, qty)
  local row = rowById(id)
  if not (row and qty and qty >= 1) then return false end
  local made
  if not code then
    made = GC.AppRuns.NewList()
    code = made and made.code
  end
  if not (code and GC.AppRuns.AddLines(code, { { i = row.itemID, q = qty } })) then return false end
  if type(GC.db) == "table" then
    GC.db.buyRecents = GC.BuyRecents.Push(GC.db.buyRecents, { i = row.itemID, q = qty, n = row.name })
  end
  local label = GC.AppRuns.Label(GC.AppRuns.Get(code))
  note = (made and GC.L["Added %d× %s to a new list, %s."] or GC.L["Added %d× %s to %s."])
    :format(qty, nameOf(row), label)
  GC.Buy._listMeta = {}
  GC.Buy.RefreshIfShown()
  return true
end

-- How many to add, in the kit's popup over `anchor`, then onto the list.
local function askQty(anchor, id, code)
  local row = rowById(id)
  if not (row and GC.BuyCapEditor) then return end
  local qty = (opened == id and openedQty) or (request.query and request.query.qty) or 1
  GC.BuyCapEditor.Open(anchor, {
    title = (GC.L["How many of %s?"]):format(nameOf(row)), text = tostring(qty), setLabel = GC.L["Add"],
    read = function(text)
      local n = tonumber((text or ""):match("^%s*(%d+)%s*$"))
      return (n and n >= 1) and n or nil
    end,
    invalid = GC.L["Type a whole number."],
    onCommit = function(n) S.AddToList(id, code, n) end,
  })
end

--- A result's menu (its right-click, and the button under the results for the opened one): add it to
--- one of the player's lists or a new one, and for the opened result its cap. Never a purchase.
function S.OpenMenu(owner, id)
  local menu = _G.MenuUtil
  local row = rowById(id)
  if not (row and menu and menu.CreateContextMenu) then return false end
  local menuText = GC.Util.ClientText
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(menuText(nameOf(row)))
    local add = root:CreateButton(menuText(GC.L["Add to list…"]))
    if add and add.CreateButton then
      for _, run in ipairs(ownLists()) do
        local code = run.code
        add:CreateButton(menuText(GC.BuyLists.Title(run)), function() askQty(owner, id, code) end)
      end
      add:CreateButton(menuText(GC.L["New list"]), function() askQty(owner, id, nil) end)
    end
    local line = opened == id and GC.Buy._SearchRun() and GC.Buy._LineFor(row.itemID) or nil
    if line and not GC.Buy._InFlight() then
      root:CreateButton(menuText(GC.L["Change the cap…"]), function() GC.Buy._EditLineCap(owner, row.itemID) end)
      if line.capFrom == "yours" then
        root:CreateButton(menuText(GC.L["Use the default cap"]), function() GC.Buy._EditLineCap(nil, row.itemID) end)
      end
    end
  end)
  return true
end

-- ---------------------------------------------------------------------------
-- The request's seams: the item box, the ticker and the routed events
-- ---------------------------------------------------------------------------

--- The item box's search (GC.Buy._SearchSubmit): with the auction house open, the search is taken
--- -- the list goes aside for the results, or waits while a purchase of it is in the client's hands
--- -- and true is answered; without it, false, and the box keeps its own matches.
function S.Submit(query, qty)
  if not ahOpen() then return false end
  local view = GC.Buy._view
  if not (view and view.container and type(query) == "string" and query:match("%S")) then return false end
  request = request or newRequest()
  shown, note = true, nil
  GC.Buy._PutListAside()
  request:Submit(query, qty or 1)
  if GC.BuyWaitDiag then GC.BuyWaitDiag.Note("browse", "submitted " .. request.state, ("reason=%s"):format(tostring(request.reason))) end
  GC.Buy.RefreshIfShown()
  return true
end

--- The next page, or -- after an answer that never came -- the same search again.
function S.More()
  if not request then return false end
  if request.state == "failed" and request.query then
    request:Submit(request.query.text, request.query.qty)
  elseif not request:More() then
    return false
  end
  GC.Buy.RefreshIfShown()
  return true
end

--- Back to the list. Not while a purchase of the opened result is in the client's hands.
function S.Close()
  if not GC.Buy._TakeListBack() then return false end
  shown, opened, note = false, nil, nil
  if request then request:Cancel() end
  GC.Buy.RefreshIfShown()
  return true
end

--- Another list was picked (GC.Buy.SelectRun): the search goes with the list it had put aside.
function S.OnListSelected()
  if not shown then return end
  shown, opened, note = false, nil, nil
  if request then request:Cancel() end
end

--- Once a second (GC.Buy.Tick): the request moves on, and the list goes aside once a purchase of it
--- that was in the client's hands is done.
function S.Tick()
  if not request then return end
  local before = signature()
  request:Step()
  if signature() ~= before and GC.BuyWaitDiag then
    GC.BuyWaitDiag.Note("browse", request.state, ("reason=%s failed=%s"):format(tostring(request.reason), tostring(request.failed)))
  end
  if shown and not GC.Buy._aside then GC.Buy._PutListAside() end
  if shown and signature() ~= before then GC.Buy.RefreshIfShown() end
end

--- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED, offered by UI/SniperFrame.lua once no keys batch
--- has claimed it. Answers whether it was the search's.
function S.OnBrowseResults()
  if not request then return false end
  local took = request:OnBrowse()
  if GC.BuyWaitDiag then GC.BuyWaitDiag.Note("browse", "event", ("took=%s state=%s"):format(tostring(took), request.state)) end
  if took and shown then GC.Buy.RefreshIfShown() end
  return took
end

--- ITEM_KEY_ITEM_INFO_RECEIVED: a row waiting for its name gets it.
function S.OnItemKeyInfo(itemID)
  if request and request:OnItemKeyInfo(itemID) and shown then GC.Buy.RefreshIfShown() end
end

--- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED.
function S.OnDropped()
  if not request then return end
  local before = signature()
  request:OnDropped()
  if shown and signature() ~= before then GC.Buy.RefreshIfShown() end
end

--- The auction house closed (Core/Init.lua, after BUY's own close): nothing will answer, nothing can
--- be bought, and the list comes back.
function S.OnAuctionHouseClosed()
  if request then request:OnClosed() end
  if not shown then return end
  shown, opened, note = false, nil, nil
  GC.Buy._TakeListBack()
  GC.Buy.RefreshIfShown()
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

build = function()
  if panel then return end
  local Theme = GC.Theme
  local parent = GC.Buy._view.container
  panel = CreateFrame("Frame", nil, parent)
  panel:Hide()
  panel.status = Theme.Num(panel, 10)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetWordWrap(true)
  setColor(panel.status, Theme.color.fgDim)
  panel.back = Theme.Button(panel, "ghost", "plaque")
  panel.back:SetHeight(22)
  panel.back:SetScript("OnClick", function() S.Close() end)

  panel.headings = {}
  for key in pairs(HEADING) do
    local label = Theme.Num(panel, 9)
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    label:SetJustifyH(key == "name" and "LEFT" or "RIGHT")
    setColor(label, Theme.color.fgDim)
    panel.headings[key] = label
  end
  local bc = Theme.color.border
  panel.rule = panel:CreateTexture(nil, "ARTWORK")
  panel.rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  panel.rule:SetHeight(1)

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end
  panel.scroll = scroll
  panel.content = CreateFrame("Frame", nil, scroll)
  panel.content:SetSize(1, 1)
  scroll:SetScrollChild(panel.content)
  panel.rows = {}
  panel.more = Theme.Button(panel.content, "ghost", "plaque")
  panel.more:SetHeight(LAYOUT.MORE_H)
  panel.more:SetScript("OnClick", function() S.More() end)
  panel.more:Hide()

  -- Under the results while a result is open: how many it buys, and adding it to a list.
  local strip = CreateFrame("Frame", nil, panel)
  strip:SetHeight(LAYOUT.STRIP_H)
  strip:Hide()
  strip.label = Theme.Num(strip, 10)
  strip.label:SetJustifyH("LEFT")
  strip.label:SetWordWrap(false)
  setColor(strip.label, Theme.color.fgDim)
  local well = CreateFrame("Frame", nil, strip)
  well:SetSize(LAYOUT.BOX_W, 22)
  local wc = Theme.color.bg or Theme.color.panel
  Theme.SlicedTexture(well, "BACKGROUND", Theme.MEDIA .. "plaque.png", { wc[1], wc[2], wc[3], 1 }, 12):SetAllPoints(well)
  Theme.SlicedTexture(well, "BORDER", Theme.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, 12):SetAllPoints(well)
  local box = CreateFrame("EditBox", nil, well)
  box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", 8, -2)
  box:SetPoint("BOTTOMRIGHT", -6, 2)
  if box.SetFont then
    box:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    box:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
  end
  if box.SetNumeric then box:SetNumeric(true) end
  if box.SetMaxLetters then box:SetMaxLetters(5) end
  local function apply(self)
    if not S.SetQty(self:GetText()) then self:SetText(tostring(openedQty or 1)) end
    self:ClearFocus()
  end
  box:SetScript("OnEnterPressed", apply)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText(tostring(openedQty or 1))
    self:ClearFocus()
  end)
  strip.well, strip.box = well, box
  strip.add = Theme.Button(strip, "ghost", "plaque")
  strip.add:SetHeight(22)
  strip.add:SetScript("OnClick", function(self) if opened then S.OpenMenu(self, opened) end end)
  panel.strip = strip
  S._panel = panel -- spec seam
end

-- One result: the item's icon and its name in its quality's colour (wrapping, never cut), the item
-- level of a gear variant, the cheapest price and how many are up. A left click opens it in the
-- dock, a right click is its menu; hover is the engine's HIGHLIGHT layer.
local function rowAt(i)
  local row = panel.rows[i]
  if row then return row end
  local Theme = GC.Theme
  row = CreateFrame("Frame", nil, panel.content)
  row:EnableMouse(true)
  local zc, hc, gc = Theme.color.zebra, Theme.color.hover, Theme.color.gold
  local function wash(layer, c, a)
    local t = row:CreateTexture(nil, layer)
    t:SetTexture(Theme.MEDIA .. "plaque.png")
    t:SetTextureSliceMargins(12, 12, 12, 12)
    t:SetPoint("TOPLEFT", 2, -1)
    t:SetPoint("BOTTOMRIGHT", -2, 1)
    t:SetVertexColor(c[1], c[2], c[3], a)
    return t
  end
  row.zebra = wash("BACKGROUND", zc, 0)
  wash("HIGHLIGHT", hc, hc[4] or 0.08)
  row.picked = wash("BORDER", gc, 0.10)
  row.picked:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(LAYOUT.ICON, LAYOUT.ICON)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.name = Theme.Label(row, 11)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(true)
  row.price = Theme.Num(row, 11)
  row.price:SetWordWrap(false)
  row.avail = Theme.Num(row, 11)
  row.avail:SetWordWrap(false)
  row:SetScript("OnMouseUp", function(self, button)
    if not self.id then return end
    if button == "RightButton" then S.OpenMenu(self, self.id) return end
    if button == "LeftButton" then S.Open(self.id) end
  end)
  row:SetScript("OnEnter", function(self) S._ShowTip(self) end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  panel.rows[i] = row
  return row
end

-- The game's own tooltip for the item, beside the window, with what a click does under it. A gear
-- variant's level is its own key's, which the item's base tooltip would contradict: it is named by
-- itself instead.
function S._ShowTip(owner)
  local row = rowById(owner.id)
  if not (row and GameTooltip) then return end
  local tip = GC.Util.ClientText
  local dim = GC.Theme.color.fgDim
  GC.Theme.ItemTooltipOutside(owner, GC.Buy._view.container:GetParent())
  if row.known and row.commodity == false and row.itemLevel > 0 then
    GameTooltip:SetText(tip(GC.Theme.WithQuality(nameOf(row), row.itemID)))
    GameTooltip:AddLine(tip((GC.L["ilvl %d"]):format(row.itemLevel)), 1, 1, 1)
  else
    GameTooltip:SetItemByID(row.itemID)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(tip(GC.L["Click to buy it here. Right-click to add it to a list."]), dim[1], dim[2], dim[3], true)
  GameTooltip:Show()
end

local function statusText()
  local q = request.query and request.query.text or ""
  local state = request.state
  local text = ""
  if state == "wait" then
    text = request.reason == "purchase" and GC.L["Waiting for the purchase to finish…"]
      or GC.L["Waiting for the auction house…"]
  elseif state == "out" then
    text = request.kind == "more" and GC.L["Loading more results…"]
      or (GC.L["Searching the auction house for “%s”…"]):format(q)
  elseif state == "done" then
    text = #request.rows == 0 and (GC.L["Nothing on sale for “%s”."]):format(q)
      or (GC.L["On sale for “%s”: %d"]):format(q, #request.rows)
  elseif state == "failed" then
    text = GC.L["The auction house did not answer. Search again."]
  end
  if note then text = text ~= "" and (text .. "\n" .. note) or note end
  return text
end

local function backLabel()
  local aside = GC.Buy._aside
  local run = aside and aside.run and GC.AppRuns.Get(aside.run:Code()) or nil
  if run then return (GC.L["Back to %s"]):format(GC.AppRuns.Label(run)) end
  return GC.L["Close search"]
end

local function paintRow(row, r, index)
  local Theme = GC.Theme
  row.id = r.id
  local zc = Theme.color.zebra
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], (index % 2 == 1) and (zc[4] or 0) or 0)
  if r.id == opened then row.picked:Show() else row.picked:Hide() end
  local icon = r.icon
  if not icon and C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, r.itemID)
    icon = ok and texture or nil
  end
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
  local label = r.known and Theme.WithQuality(nameOf(r), r.itemID, 12) or nameOf(r)
  if r.known and r.commodity == false and r.itemLevel > 0 then
    label = ("%s · %s"):format(label, (GC.L["ilvl %d"]):format(r.itemLevel))
  end
  -- Cleared first: SetText with the text a string already holds does not draw it again, and a row
  -- that comes back from a hidden tab can be blank (docs/addon/AGENTS.md, "Text").
  row.name:SetText("")
  row.name:SetText(label)
  setColor(row.name, r.known and Theme.color.fg or Theme.color.fgDim)
  row.price:SetText("")
  row.price:SetText(r.minPrice and GC.Util.FormatMoney(r.minPrice) or "")
  row.avail:SetText("")
  row.avail:SetText(GC.Util.IntText(r.available or 0))
  setColor(row.price, Theme.color.fg)
  setColor(row.avail, Theme.color.fgMuted)
  row:Show()
end

--- Where the panel goes (UI/BuyFrame.lua's layoutBody): under the item box, `top` from the
--- container's top, `inset` from its left, and `bottom` over its foot -- the dock's height.
function S.Place(container, inset, top, bottom)
  if not shown then return end
  build()
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -top)
  panel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, bottom)
  panel.w = math.max(0, (container.GetWidth and container:GetWidth() or 0) - inset)
end

--- The headings come back from a hidden tab undrawn unless cleared, set, hidden and shown again
--- (docs/addon/AGENTS.md, "Text"); GC.Buy.Show calls this.
function S.Restamp()
  if not panel then return end
  for key, label in pairs(panel.headings) do
    label:SetText("")
    label:SetText(GC.L[HEADING[key]])
    label:Hide()
    label:Show()
  end
end

--- Draws the search for what it is now: the status and the way back, the headings, every result
--- (as tall as its wrapped name), the next page's button, and the opened result's strip. Hidden when
--- the search is not up. UI/BuyFrame.lua's render calls it.
function S.Paint()
  if not shown then
    if panel then panel:Hide() end
    return
  end
  build()
  local Theme = GC.Theme
  local pad = Theme.pad
  local width = panel.w or 0
  panel:Show()

  -- The way back names the list it goes back to, as wide as that name -- up to almost half the
  -- pane, where a long name wraps onto more lines rather than being cut.
  local back = panel.back
  back:SetLabel(backLabel())
  local maxW = math.max(LAYOUT.BUTTON_MIN, math.floor(width * 0.45))
  local labelW = measure(back.text)
  if labelW and labelW + 2 * pad.m > maxW then
    back.text:SetWordWrap(true)
    back.text:SetMaxLines(3)
    back:SetWidth(maxW)
    back:SetHeight(math.max(22, heightOf(back.text) + 8))
  else
    back.text:SetWordWrap(false)
    fitButton(back, LAYOUT.BUTTON_MIN)
    back:SetHeight(22)
  end
  back:Enable()
  if GC.Buy._InFlight() then back:Disable() end
  back:ClearAllPoints()
  back:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -2)
  local status = panel.status
  status:SetText(statusText())
  status:ClearAllPoints()
  status:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -6)
  status:SetPoint("RIGHT", back, "LEFT", -pad.s, 0)
  local backW = back.GetWidth and back:GetWidth() or LAYOUT.BUTTON_MIN
  if width > 0 then status:SetWidth(math.max(40, width - backW - pad.s - 4)) end
  local backH = back.GetHeight and back:GetHeight() or 22
  local headH = math.max(LAYOUT.HEAD_MIN + 4, heightOf(status) + 12, (backH or 22) + 6)

  -- The results, painted first and measured second: each number column is as wide as its heading
  -- and its widest cell in the player's language.
  local list = request.rows or {}
  for i, r in ipairs(list) do paintRow(rowAt(i), r, i) end
  for i = #list + 1, #panel.rows do panel.rows[i]:Hide(); panel.rows[i].id = nil end
  local priceW, availW = LAYOUT.PRICE_MIN, LAYOUT.AVAIL_MIN
  for key, label in pairs(panel.headings) do
    if (label:GetText() or "") == "" then label:SetText(GC.L[HEADING[key]]) end
    local w = measure(label) or 0
    if key == "price" then priceW = math.max(priceW, w) elseif key == "avail" then availW = math.max(availW, w) end
  end
  for i = 1, #list do
    local row = panel.rows[i]
    priceW = math.max(priceW, measure(row.price) or 0)
    availW = math.max(availW, measure(row.avail) or 0)
  end
  local nameW = math.max(40, width - LAYOUT.INSET - priceW - availW - 2 * pad.s - 4)

  local h = panel.headings
  h.avail:ClearAllPoints()
  h.avail:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -headH)
  h.avail:SetSize(availW, LAYOUT.HEADING_H)
  h.price:ClearAllPoints()
  h.price:SetPoint("TOPRIGHT", h.avail, "TOPLEFT", -pad.s, 0)
  h.price:SetSize(priceW, LAYOUT.HEADING_H)
  h.name:ClearAllPoints()
  h.name:SetPoint("TOPLEFT", panel, "TOPLEFT", LAYOUT.INSET, -headH)
  h.name:SetSize(nameW, LAYOUT.HEADING_H)
  panel.rule:ClearAllPoints()
  panel.rule:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(headH + LAYOUT.HEADING_H))
  panel.rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(headH + LAYOUT.HEADING_H))

  -- The opened result's strip at the foot, the results between it and the headings.
  local strip = panel.strip
  local openedRow = opened and GC.Buy._SearchRun() and rowById(opened) or nil
  local stripH = 0
  if openedRow then
    strip.label:SetText(GC.L["How many"])
    strip.label:ClearAllPoints()
    strip.label:SetPoint("LEFT", strip, "LEFT", 4, 0)
    strip.well:ClearAllPoints()
    strip.well:SetPoint("LEFT", strip.label, "RIGHT", pad.s, 0)
    if not (strip.box.HasFocus and strip.box:HasFocus()) then strip.box:SetText(tostring(openedQty or 1)) end
    strip.add:SetLabel(GC.L["Add to list…"])
    fitButton(strip.add, LAYOUT.BUTTON_MIN)
    strip.add:ClearAllPoints()
    strip.add:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    strip:ClearAllPoints()
    strip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    strip:Show()
    stripH = LAYOUT.STRIP_H
  else
    strip:Hide()
  end
  local scroll = panel.scroll
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(headH + LAYOUT.HEADING_H + LAYOUT.GAP))
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, stripH)

  local content = panel.content
  content:SetWidth(math.max(1, width))
  local y = 0
  for i = 1, #list do
    local row = panel.rows[i]
    row.avail:ClearAllPoints()
    row.avail:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.avail:SetWidth(availW)
    row.price:ClearAllPoints()
    row.price:SetPoint("RIGHT", row.avail, "LEFT", -pad.s, 0)
    row.price:SetWidth(priceW)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", LAYOUT.INSET, 0)
    row.name:SetWidth(nameW)
    local rh = math.max(LAYOUT.ROW_H, heightOf(row.name) + 8)
    row:SetHeight(rh)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    y = y + rh
  end
  -- The next page while the answer is not whole, or the same search again after one that never came.
  local more = panel.more
  local label = (request.state == "done" and not request.full) and GC.L["More results"]
    or (request.state == "failed" and GC.L["Search again"]) or nil
  if label then
    more:SetLabel(label)
    fitButton(more, LAYOUT.BUTTON_MIN)
    more:ClearAllPoints()
    more:SetPoint("TOP", content, "TOP", 0, -(y + LAYOUT.GAP))
    more:Show()
    y = y + LAYOUT.GAP + LAYOUT.MORE_H + LAYOUT.GAP
  else
    more:Hide()
  end
  content:SetHeight(math.max(1, y))
end
