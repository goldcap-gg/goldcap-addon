-- The Sell tab's toolbar: the deck switch (TO POST / MY LOTS), the search box, the two filter chips
-- and REFRESH, whose label carries the pricing walk's progress. Moved from UI/SellFrame.lua as it
-- was.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local UI = GC.SellUI
local Toolbar = UI.Toolbar
local setColor = UI.fmt.setColor

-- Labels for the deck switch and the two chips. Parallel tables, exactly like
-- PRICE_CHIP_LABELS/PRICE_CHIP_IDS in UI/Sell/Inspector.lua and for both of the same reasons: the contract
-- scanner reads EVERY literal inside an @localised-keys table as a key, so an id sitting in the
-- same table would be collected as a translatable string nobody ever shows; and the id is what
-- the code switches on, never the label, which a translation changes out from under it.
-- @localised-keys
local DECK_LABELS = {
  "TO POST %d", "MY LOTS %d",
}
local DECK_IDS = { "post", "listed" }
-- @localised-keys
local CHIP_LABELS = {
  "READY", "NO COST",
}
local CHIP_IDS = { "ready", "nocost" }
-- "READY" is 5 chars and "NO COST" 7, but both carry the rounded badge's own inset: 92/76 match
-- what the five chips they replaced used for labels of the same length.
local CHIP_WIDTHS = { 92, 76 }

-- The status line lives in the Sniper's toolbar, at the far left of a different
-- row from the Refresh button -- a window's width away from what was just
-- pressed. That is the same distance that made Scan look dead. So the button
-- carries the state too, and the progress with it: "PRICING 3/24" answers "is it
-- running" without the player having to hunt for a line of text.
local function paintRefreshButton()
  local button = UI.container and UI.container.refreshButton
  if not button then return end
  local phase = S.refresh.phase
  local busy = phase ~= "idle" and phase ~= "done" and phase ~= "error"
  local label = "REFRESH"
  if busy then
    -- "PRICING 10/24", not a bare "10/24". This button sits at the end of a row of filter
    -- chips, so a naked ratio reads as one more filter -- and the owner reasonably asked why
    -- the tab only had 24 items in it. It is not a count of anything the player owns: it is
    -- how far this pass has got through the pricing queue, which is capped at QUOTE_WALK_CAP
    -- because every entry is a round trip on the same throttled slot the Sniper's scans use.
    -- Once the bulk fill has priced the tab, what the walk is still fetching is each row's
    -- book -- and a button that went on saying PRICING for twelve seconds over a list whose
    -- prices were all there read as the refresh itself being that slow.
    -- Of the deck on screen, not of the queue: the walk prices both decks, and "BOOKS 4/27"
    -- over ten rows was the same puzzle again. While it is on the other deck's rows the count
    -- stands at this deck's full figure and the button stays lit.
    local counting = S.refresh.bulkLanded and GC.L["BOOKS %d/%d"] or GC.L["PRICING %d/%d"]
    local done, total = S.refresh.deckProgress()
    label = done > 0 and counting:format(done, total) or GC.L["PRICING…"]
  end
  if button.lastLabel ~= label then
    button.lastLabel = label
    button:SetLabel(label)
  end
  if button.lastBusy ~= busy then
    button.lastBusy = busy
    if button.SetVariant then button:SetVariant(busy and "active" or "ghost") end
  end
end
Toolbar.PaintRefreshButton = paintRefreshButton

-- State on the chip itself: SetVariant, never a second overlaid button (one control, two
-- variants -- see the addon's engineering notes on buttons).
function Toolbar.PaintFilterChips()
  local container = UI.container
  for _, id in ipairs(CHIP_IDS) do
    local chip = container.filterButtons[id]
    if chip then
      -- Both chips ask POST-deck questions, so on LISTED they are disabled rather than
      -- hidden: a control that vanishes reads as a bug, one that dims reads as "not here".
      local onPostDeck = S.filterMode ~= "listed" and S.filterMode ~= "cancelqueue"
      chip:SetVariant(UI.chips[id] and onPostDeck and "active" or "ghost")
      if onPostDeck then chip:Enable() else chip:Disable() end
    end
  end
end

local function deckCounts()
  local post, listed = 0, 0
  for _, position in ipairs(S.positions) do
    local bags = type(position.bagQty) == "number" and position.bagQty or 0
    local live = type(position.listedQty) == "number" and position.listedQty or 0
    -- What can be POSTED, not everything the deck holds. The deck also lists stock that is
    -- neither in the bags nor listed -- folded away under NOT ON HAND, or a purchase not yet
    -- identified -- and counting those read "TO POST 17" over three rows with a Post button
    -- (seen in game). The rows stay where they were; only the number says what it names.
    if bags > 0 then post = post + 1 end
    if live > 0 then listed = listed + 1 end
  end
  return post, listed
end
-- Deliberately reads the deck the cancel queue's focus state belongs to: "cancelqueue" is a
-- focus inside listed, so pressing CANCEL must not leave the switch painting neither half active.
local function activeDeck()
  return (S.filterMode == "listed" or S.filterMode == "cancelqueue") and "listed" or "post"
end
function Toolbar.PaintDeckSwitch()
  local container = UI.container
  local post, listed = deckCounts()
  local counts = { post = post, listed = listed }
  for slot, id in ipairs(DECK_IDS) do
    local button = container.deckButtons[id]
    if button then
      button:SetLabel(UI.fmt.count(GC.L[DECK_LABELS[slot]], counts[id] or 0))
      button:SetVariant(activeDeck() == id and "active" or "segment")
    end
  end
end

local function applySearch()
  local search, searchHint = UI.container.search, UI.container.searchHint
  local text = (search:GetText() or ""):lower():match("^%s*(.-)%s*$")
  UI.chips.search = search:IsShown() and text ~= "" and text or nil
  if text ~= "" or (search.HasFocus and search:HasFocus()) then searchHint:Hide() else searchHint:Show() end
end

-- The deck switch's two halves and the track's inset around and between them.
local DECK_W, DECK_PAD = 127, 2
-- Row 1's fixed occupants: the deck switch, REFRESH, the two chips and their gaps.
local SEARCH_MIN, SEARCH_MAX, ROW1_FIXED = 120, 220, 2 * DECK_W + 3 * DECK_PAD + 104 + 92 + 76 + 4
function Toolbar.LayoutSearch()
  local container = UI.container
  local room = (UI.rowWidth or 0) - ROW1_FIXED - 36
  if room >= SEARCH_MIN then
    container.searchWell:SetWidth(math.min(SEARCH_MAX, room)); container.searchWell:Show(); container.search:Show()
  else
    container.searchWell:Hide(); container.search:Hide()
  end
  applySearch()
  if not container.search:IsShown() then container.searchHint:Hide() end
end

function Toolbar.Build()
  local container = UI.container
  local refreshButton = Theme.Button(container, "ghost", "plaque")
  -- 104, not 72: the busy label is "PRICING 10/24" (see paintRefreshButton), which is 101.4px
  -- at mono-10 and Theme.Scale() 1.3 (JetBrains Mono ~0.6em/char -> 7.8px/char) -- a button
  -- sized for "REFRESH" alone would have let that overflow its own edges into the filter chip
  -- beside it.
  refreshButton:SetSize(104, 26); refreshButton:SetPoint("TOPRIGHT", 0, 0); refreshButton:SetLabel(GC.L["REFRESH"])
  container.refreshButton = refreshButton
  -- Wrapped, not passed directly: OnClick hands the handler (self, button, down),
  -- so GC.Sell.Refresh would receive the button as its `automatic` flag -- truthy
  -- -- and every press would take the stand-aside path that exists for the timer.
  -- The button would have gone on doing nothing, which is the bug this argument
  -- was added to fix.
  refreshButton:SetScript("OnClick", function() GC.Sell.Refresh() end)
  -- Two chips, where there were five. Not a cut: three of the old five became the DECK switch
  -- below ("in bags" and "listed" are the decks themselves) and "GC" was a provenance cut
  -- sitting where a player expected "my auctions" -- provenance stays on the tooltip. What is
  -- left are the two questions that NARROW a deck instead of replacing it, which is why they
  -- are booleans and can both be on at once. The old five could not express that at all.
  container.filterButtons = {}
  local previous = refreshButton
  for slot, id in ipairs(CHIP_IDS) do
    local button = Theme.Button(container, "ghost", "badge")
    button:SetSize(CHIP_WIDTHS[slot], 20)
    button:SetPoint("RIGHT", previous, "LEFT", -2, 0)
    button:SetLabel(GC.L[CHIP_LABELS[slot]])
    button:SetScript("OnClick", function()
      UI.chips[id] = not UI.chips[id]
      -- "cancelqueue" is a transient FOCUS state, not a deck, and nothing else clears it: press
      -- CANCEL once and the tab rendered the cancel queue's own order for the rest of the
      -- session, with these chips lighting up over a list they could not narrow. Pressing a
      -- chip is a request to filter a deck, so give the chip its deck back.
      if S.filterMode == "cancelqueue" then S.filterMode = "listed" end
      -- A chip changes which rows are on screen, so the order is the player's to have again.
      S.rowPlaces = {}
      Toolbar.PaintDeckSwitch()
      Toolbar.PaintFilterChips()
      UI.List.RenderRows()
    end)
    container.filterButtons[id] = button
    previous = button
  end

  -- The deck switch: the one control this redesign turns on. "What can I list" and "what is
  -- already listed" are two jobs, and serving both from one table is what forced the action
  -- column to change its verb from row to row -- Post here, Repost there, Set cost on the next
  -- -- so no player could ever read ahead. One deck, one verb.
  -- One control, as the design draws it: a sunken track the two decks sit in, the one that is on
  -- lit and the other bare text. The track is the tab's own regions, not a frame of its own: a
  -- frame at the buttons' level would draw its fill over theirs, layer by layer (the window
  -- glass did that to the Sniper's buttons, 691786b).
  local trackW = 2 * DECK_W + 3 * DECK_PAD
  local trackFill = Theme.SlicedTexture(container, "BACKGROUND", Theme.MEDIA .. "plaque.png", { 0, 0, 0, 0.3 }, 12)
  trackFill:SetPoint("TOPLEFT"); trackFill:SetSize(trackW, 26)
  local tb = Theme.color.border
  local trackRing = Theme.SlicedTexture(container, "BORDER", Theme.MEDIA .. "plaque_ring.png",
    { tb[1], tb[2], tb[3], tb[4] or 0.075 }, 12)
  trackRing:SetPoint("TOPLEFT"); trackRing:SetSize(trackW, 26)
  container.deckTrack = trackFill
  container.deckButtons = {}
  local deckPrevious
  for _, id in ipairs(DECK_IDS) do
    local button = Theme.Button(container, "segment", "plaque")
    -- DECK_W, sized for "TO POST 88" at mono-10 and Theme.Scale() 1.3 (~7.8px/char = 78px) with
    -- room for the rounded plaque's own inset, the same way REFRESH is sized for "PRICING 10/24".
    button:SetSize(DECK_W, 26 - 2 * DECK_PAD)
    if deckPrevious then button:SetPoint("LEFT", deckPrevious, "RIGHT", DECK_PAD, 0)
    else button:SetPoint("TOPLEFT", DECK_PAD, -DECK_PAD) end
    button:SetScript("OnClick", function()
      S.filterMode = id
      S.rowPlaces = {} -- a different deck is a different list; settle it fresh
      -- A deck change invalidates whatever the other deck's chips were narrowing to, and an
      -- expansion opened on a row that is not on this deck would render against nothing.
      Toolbar.PaintDeckSwitch(); Toolbar.PaintFilterChips(); UI.List.RenderRows()
    end)
    container.deckButtons[id] = button
    deckPrevious = button
  end
  Toolbar.PaintDeckSwitch()
  Toolbar.PaintFilterChips()

  -- Search, between the deck switch and the chips. Forty positions is an ordinary posting deck
  -- and finding one of them was a matter of reading down the list. It lives in whatever room
  -- row 1 has left, so under SEARCH_MIN of it the box is not drawn at all -- and takes its
  -- filter with it, because a list narrowed by a box nobody can see is a list that looks broken.
  -- The kit's own well at the height of the deck buttons it sits beside (InputBoxTemplate is a
  -- fixed 20px strip of Blizzard's stone border, a third shorter than everything on the row).
  local searchWell = CreateFrame("Frame", nil, container)
  container.searchWell = searchWell
  searchWell:SetHeight(26)
  searchWell:SetPoint("LEFT", deckPrevious, "RIGHT", 12 + DECK_PAD, 0)
  local swc = Theme.color.bg or Theme.color.panel
  Theme.SlicedTexture(searchWell, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { swc[1], swc[2], swc[3], 1 }, 12):SetAllPoints(searchWell)
  Theme.SlicedTexture(searchWell, "BORDER", Theme.MEDIA .. "plaque_ring.png",
    { 1, 1, 1, 0.12 }, 12):SetAllPoints(searchWell)
  local search = CreateFrame("EditBox", nil, searchWell)
  search:SetAutoFocus(false)
  search:SetPoint("TOPLEFT", 10, -2)
  search:SetPoint("BOTTOMRIGHT", -8, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if search.SetFont then
    search:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    search:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    Theme.OnRescale(function(scale) search:SetFont(Theme.FONT_UI, 11 * scale, "") end)
  end
  container.search = search
  local searchHint = Theme.Num(searchWell, 10)
  searchHint:SetJustifyH("LEFT")
  searchHint:SetPoint("LEFT", searchWell, "LEFT", 10, 0)
  searchHint:SetText(GC.L["Search"])
  setColor(searchHint, Theme.color.fgDim)
  container.searchHint = searchHint
  search:SetScript("OnTextChanged", function(_, byUser)
    applySearch()
    if byUser then UI.List.RenderRows() end
  end)
  search:SetScript("OnEditFocusGained", applySearch)
  search:SetScript("OnEditFocusLost", applySearch)
  search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(box)
    box:SetText(""); box:ClearFocus()
    applySearch(); UI.List.RenderRows()
  end)
  Toolbar.LayoutSearch()
end

GC.SellView.paintDeck = function()
  if UI.container and UI.container.deckButtons then UI.Toolbar.PaintDeckSwitch() end
end
