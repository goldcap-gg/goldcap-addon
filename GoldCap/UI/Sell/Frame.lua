-- The Sell tab's view, the part every other file under UI/Sell/ builds on. It loads first
-- (helper.SELL_UI_FILES, both TOCs) and plays the part Services/Sell/State.lua plays for the
-- services: GC.SellUI holds one module table per part of the view, the geometry more than one
-- part lays out by, and the pure helpers that colour text and format money. Calls between the
-- parts go through these tables at call time, never through a copy taken at load, so a spec that
-- replaces a function reaches every caller (spec/sell_ui_structure_spec.lua).
-- The positions module owns all accounting and action-plan decisions.  The view only joins
-- live AH observations, a cached quote stream, and widgets around that single model.
-- wow-auction: docs/superpowers/specs/2026-10-09-addon-ui-kit-and-sell-design.md, Part 2.
local _, GC = ...

GC.Sell = GC.Sell or {}

-- Labels for the posting-queue keybinding (Bindings.xml, auto-loaded by the client -- see that
-- file for the binding itself and UI/Sell/Dock.lua's Dock.Build for the handler it calls). Purely
-- cosmetic: the Key Bindings UI falls back to the raw action name if these are missing, so the
-- feature works without them, but a human label is worth the two lines. `_G.` explicit, not a
-- bare assignment, so this is a plain field write on the standard `_G` table rather than a new
-- global luacheck would need to be told about.
_G.BINDING_HEADER_GOLDCAP = "GoldCap"
-- Assigned through GC.SellUI_RefreshBindingName, called from Init once the locale is
-- active. Resolving GC.L here would capture the English fallback: this file loads long
-- before ApplyLocale picks a language, so the binding would read English forever.
function GC.SellUI_RefreshBindingName()
  _G.BINDING_NAME_GOLDCAP_POST_NEXT = GC.L["Post the next queued item"]
end

GC.SellUI = {
  -- Set by GC.Sell.Attach: the tab's own frame (container), the list's and the inspector's scroll
  -- children (content, detailContent), the Sniper window the tab lives in (window, whose `status`
  -- is the toolbar's line), and the list's width and line pitch (rowWidth, rowHeight; the resize
  -- hook keeps rowWidth current). Absent until then: `container == nil` is how the services ask
  -- whether the tab is built.
  -- The pool of rows every render draws from. It only grows.
  rows = {},
  -- The open position, by position key. One at a time.
  expanded = {},
  -- Whether the posting deck's "not on hand" fold is open. The player's to set and kept for the
  -- session: a fold that shut itself on every refresh would be a control that does not work.
  showNotOnHand = false,
  -- The two chips beside the deck switch, keyed by the same stable ids UI/Sell/Toolbar.lua's
  -- CHIP_IDS carries. Flags
  -- that NARROW whichever deck is up rather than replacing it -- which is exactly what the five
  -- mutually-exclusive chips this replaced could not express -- so both can be on at once.
  chips = { ready = false, nocost = false },
  -- One per part of the view, each filled by its own file under UI/Sell/.
  Toolbar = {}, List = {}, Row = {}, Inspector = {}, Book = {}, Dock = {}, CostDialog = {},
}
local UI = GC.SellUI

-- The checks and constants this file shares with the Sell services (Services/Sell/State.lua).
local S = GC.SellState
local Walk = GC.SellWalk
local itemName = GC.SellUtil.itemName
local EMPTY_ANSWER_AGE = GC.Sell.EMPTY_ANSWER_AGE

-- Per-unit framing: a seller reasons in "what did one cost me, what does one fetch, what do I
-- clear on one", not in position totals -- the totals already sit in the summary above the list.
-- `status` carries the recommendation (what to do and at what price) and `action` owns the
-- button. They used to be one column, with the button drawn over the text, which destroyed the
-- only place the target price was ever shown. `listed` is the optional one now: its total is in
-- the summary, whereas the market price is what every decision on this screen turns on.
UI.COLUMNS = {
  { key = "item", flex = true, min = 200 },
  -- The three the posting deck is really about: what this stack fetches at the price GoldCap
  -- would list it at, that price, and how it compares with what it cost. They replaced COST /
  -- MARKET / PROFIT / WHAT TO DO on the row -- four columns whose headings, translated, ran
  -- into one another at every width ("РИНОК / ШТ ПРИБУТОК / ШТ ЩО РОБИТИ", seen in game).
  -- Those four facts did not disappear: they are what the drawer is made of.
  -- PRICE leads and carries a second line -- where that price stands in the live book -- so it
  -- is wide enough for five queue marks and "12 340 ahead" beside them. MARGIN is no longer a
  -- column: it is the line under YOU GET, the figure it qualifies.
  { key = "price", w = 132, min = 116, num = true, bold = true },
  { key = "gross", w = 100, min = 84, num = true, bold = true },
  -- `min` is what a numeric column shrinks to before anything is DROPPED. Without it the
  -- shedding order jumped straight from "everything at full width" to "COST/UNIT is gone",
  -- and at the default 720-wide window it landed on the gone side: a seller looking at a
  -- market price and a profit with nothing on screen saying what either was measured against.
  { key = "cost", w = 92, min = 72, num = true },
  { key = "listed", w = 88, num = true, optional = true },
  { key = "market", w = 92, min = 72, num = true },
  { key = "profit", w = 96, min = 76, num = true, bold = true },
  { key = "status", w = 176 },
  { key = "action", w = 88 },
}

-- The side panel a position opens into. W is its whole width; the scroll bar lives INSIDE it
-- (SCROLL_GUTTER) so that docked beside the list or laid over it the panel is one rectangle.
-- DOCK_MIN is the content width from which the list can give the panel its own column and
-- still read; under it the panel is a sheet over the list's right side -- the item names stay
-- visible at the left, which is what a seller picks the next row by.
UI.INSP = { W = 340, GAP = 28, HEAD_H = 58, SCROLL_GUTTER = 26, PAD = 8, DOCK_MIN = 880 }

-- Queue marks under a row's price: one per price level, counted from the cheapest. Five is
-- where a seller stops caring which level exactly -- past that the words beside them carry it.
-- H is a POSITION row's height in the list -- taller than the list's 32px pitch, which every
-- other kind keeps: two lines of text, a 28px icon and a button a finger's width tall need the
-- room. LIFT is how far each of the two lines sits from the row's centre.
UI.ROW = { MARKS = 5, H = 44, LIFT = 10, ICON = 28, BUTTON_H = 26, BUTTON_GAP = 14 }
-- The five marks and the gaps layoutCells chains them with (5px to the words, 2px between).
UI.ROW.MARKS_W = 5 + UI.ROW.MARKS * 3 + (UI.ROW.MARKS - 1) * 2
-- The selling mark before a TO POST row's icon (Row.Style): its button, and the room it takes.
UI.ROW.MARK, UI.ROW.MARK_W = 16, 20

-- The dock along the bottom of the tab. STAT_W fits "1234567g89s" at mono-10 and Theme.Scale()
-- 1.3 (~7.8px/char); NARROW is the content width under which the ledger keeps only the total a
-- seller is here for -- at the default 720px window all three would leave the line beside the
-- bulk action no room to name the item it is about to post.
UI.DOCK = { H = 44, PAD = 8, STAT_W = 92, NARROW = 700 }

-- The detail panel's head: one row that is a PANEL rather than a line, claiming DR.SLOTS of the
-- list's own pitch. It used to open INLINE under its position, two columns wide, with the lot
-- and purchase rows stacked under it -- ten rows of detail that buried the list it was opened
-- from, and only five book levels because that was all a panel that short could carry.
--
-- It lives in the side panel now (see INSP), one column: the price you are about to list at,
-- then the book that price lands in, all eight levels the view model hands over.
UI.DR = {
  SLOTS = 14,              -- 14 * ROW_H(32) = 448px: a position with stock to price
  SLOTS_BARE = 11,         -- no stock in the bags: no price control, the book moves up
  LINE_H = 20,             -- one book level
  LINES = 8,               -- SellViewModel's own BOOK_ROWS
  BOX_W = 112, BOX_H = 34, -- the price box: the one figure on this tab that spends gold
  HEAD_Y = -10,            -- "YOUR PRICE" / "YOU GET"
  BOX_Y = -26,             -- the price box, and what it fetches beside it
  NOTE_Y = -68,            -- whose price it is, or what is wrong with it
  CHIPS_Y = -88,           -- the five one-click fills, one segmented strip
  CHIP_H = 22,
  REC_Y = -120,            -- what GoldCap would do and why, two lines of it
  POST_Y = -156,           -- Post, the panel's own
  POST_H = 24,
  BOOK_Y = -192,           -- where the book section starts when there is a price control
  BOOK_Y_BARE = -84,       -- ...and when there is not
  BAR_MAX = 160,
  BAR_SLICE = 2,           -- bar.png's end caps; under half of BOOK_BAR_H, or the caps overlap and notch
  BAR_MIN = 5,             -- the narrowest fill that still holds both caps
  PRICE_W = 76, UNITS_W = 40, TAG_W = 40,
  -- "wall", at the start of its own level's bar: the bar starts after it. Measured where the client
  -- can (UI/Sell/Book.lua's paintLadder); this is the fallback, the widest language's word ("стена") in mono-9 at
  -- Theme.Scale() 1.3 with air -- 28 cut it to "ст…" (final review I2).
  WALL_TAG_W = 38,
  NO_REASON_SLOTS = 1,     -- what a postable head gives back when there is no reason to state
  NO_BOOK_SLOTS = 4,       -- what a head without a book gives back: 8 levels less two lines of text
}

-- Text helpers every part paints with. Pure: they read only their arguments and GC.Util, so a file
-- may alias them at load, as the services alias GC.SellUtil.
local fmt = {}
UI.fmt = fmt

function fmt.setColor(fontString, color)
  if fontString and color then fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

-- Gold-carrying amounts render as plain text ("65g24s"), not GetCoinTextureString's coin
-- icons: the icon escapes are wide, and a truncated FontString cuts them MID-ESCAPE, which
-- painted lot labels as "bought 17 Aug at 1|..." in game. Sub-gold amounts keep the icons,
-- where they fit. Mirrors the Deals board's formatColumnAmount rule.
--
-- A GC.Sell field, not a top-level local: paint-only (every call site is inside render or
-- drawer/summary paint code, never a click's pre-call body; final review "Headroom").
-- `gold` goes through GC.Util.IntText, not %d: WoW's own string.format raises "integer
-- overflow attempting to store N" past +-2^31 copper (about 214,748g). `silver` stays on %d:
-- it is bounded 0-99 by the mod above.
function GC.Sell._FormatAmount(amount)
  if amount == nil then return GC.L["Unknown"] end
  if amount < 0 then return "-" .. GC.Sell._FormatAmount(-amount) end
  if amount >= 10000 then
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    if silver == 0 then return GC.Util.IntText(gold) .. "g" end
    return GC.Util.IntText(gold) .. ("g%02ds"):format(silver)
  end
  return GC.Util.CoinText(amount)
end

function fmt.cell(value)
  return type(value) == "number" and GC.Sell._FormatAmount(value) or tostring(value or "")
end

-- Same inline color escape UI/SoldFrame.lua's partial-cost count uses, for the same reason: the hold-price
-- suffix on the PROFIT/UNIT cell shares one FontString with the number in front of it, so there
-- is no separate region to SetTextColor -- the only way to dim part of the text is to color it
-- inline and close with |r.
fmt.DIM_HEX = "|cff8f8d88"

-- Theme.color.cost as an inline escape, for the one number on the stock line that is money.
-- The line under an item name is a run-on -- count, then listed, then what a unit cost -- drawn
-- at size 10 in a single uniform weight, and the owner of a live client said of the cost he had
-- asked to be shown: "I did not even see it, it just sits there." He was right. It is the figure
-- the PRICE / UNIT column two feet to the right is meant to be compared against, and it carried
-- no more emphasis than the word "in". Colouring the amount (never the words around it) gives
-- the eye something to land on without adding a row, a column or a line.
fmt.MONEY_HEX = "|cffc9a957"

-- A GC.Sell field, not a top-level local: paint-only, same reason as _FormatAmount above
-- (final review "Headroom").
function GC.Sell._InlineColor(color, text)
  return ("|cff%02x%02x%02x%s|r"):format(
    math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5), text)
end

local exact = GC.SellUtil.exact

local COPPER_PER_GOLD = 10000

-- The Unit/Total cost fields are GOLD, explicitly -- see the field labels in UI/Sell/CostDialog.lua's CostDialog.Build.
-- A player typing "250" means 250 gold, and used to be recorded as 250 COPPER with no unit
-- shown anywhere; that number then drove cost basis, profit and the below-cost warning
-- forever. This is the one place that boundary is crossed, and it is crossed the same way
-- GetCoinTextureString's own rounding implies: round to the nearest copper, never truncate.
local function dialogGoldCopper(edit)
  local value = tonumber(edit:GetText())
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
    return nil
  end
  local copper = math.floor(value * COPPER_PER_GOLD + 0.5)
  return exact(copper) and copper or nil
end

local function dialogGoldPositive(edit)
  local copper = dialogGoldCopper(edit)
  return copper and copper > 0 and copper or nil
end

-- Exact copper -> a decimal gold string with no trailing noise ("2.5", never "2.5000"), so
-- the Unit/Total fields can keep syncing each other in the same units the player types in.
-- Copper is always an integer count of 1/10000 gold, so this round-trips exactly -- no
-- floating point is involved in this direction, only integer division and remainder.
local function copperToGoldText(copper)
  if not exact(copper) then return "" end
  local whole = math.floor(copper / COPPER_PER_GOLD)
  local remainder = copper - whole * COPPER_PER_GOLD
  if remainder == 0 then return tostring(whole) end
  -- `whole` goes through GC.Util.IntText, not %d: WoW's own string.format raises "integer
  -- overflow attempting to store N" past +-2^31 copper (about 214,748g). `remainder` stays on
  -- %d: it is bounded 0-9999 by COPPER_PER_GOLD above.
  local text = GC.Util.IntText(whole) .. (".%04d"):format(remainder)
  text = (text:gsub("0+$", ""))
  text = (text:gsub("%.$", ""))
  return text
end

-- YOUR PRICE only (row.priceBox, in UI/Sell/Inspector.lua) -- everything above (the Set-Cost
-- dialog's Unit/Total fields) stays gold-decimal unconditionally, on retail and on WoW: Forever alike, because a
-- purchase cost is always gold-denominated regardless of what the auction house can post.
--
-- Exact copper -> plain coin text ("90c", "1g22s90c", never "1g" with a silent 90c dropped),
-- for the one client where a price can actually carry a copper remainder
-- (GC.Flips.PriceStep() == 1 -- see that function's own comment). The owner's own bug report:
-- the gold-decimal box above showed "0.009" for 90c -- correct arithmetic, unreadable, and
-- easy to mistype back wrong. No coin ICONS (GC.Util.CoinText): this is an EditBox the seller
-- retypes, not a read-only label, and `|T...|t` escapes are not something a person can edit.
-- Falls back to the gold-decimal text unconditionally on any other client -- retail's box is
-- byte-identical to before this existed.
local function copperToPriceText(copper)
  if not exact(copper) then return "" end
  if GC.Flips.PriceStep() ~= 1 then return copperToGoldText(copper) end
  if copper == 0 then return "0c" end
  local gold = math.floor(copper / COPPER_PER_GOLD)
  local silver = math.floor((copper % COPPER_PER_GOLD) / 100)
  local rest = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. "g" end
  if silver > 0 then parts[#parts + 1] = silver .. "s" end
  if rest > 0 then parts[#parts + 1] = rest .. "c" end
  return table.concat(parts)
end

-- The inverse of copperToPriceText, and YOUR PRICE's own parse -- everywhere else (the Set-Cost
-- dialog) keeps reading dialogGoldPositive/dialogGoldCopper directly, gold-decimal always.
-- Accepts "1g22s90c" or any subset of those three suffixes, in order, each optional; a bare
-- number with none of them is read as GOLD, through the exact same parser as retail's own box
-- and the Set-Cost dialog (UI/Sell/CostDialog.lua) (B2: a bare number used to mean copper here and gold
-- everywhere else on this same tab -- a typed "5" was 5g in the cost box and 5c one control
-- down). An explicit g/s/c suffix is still the one way to reach sub-gold precision on Forever.
-- Falls back to dialogGoldPositive unconditionally off the copper grid, so retail typing is
-- exactly what it always was.
local function priceBoxCopper(box)
  if GC.Flips.PriceStep() ~= 1 then return dialogGoldPositive(box) end
  local text = (box:GetText() or ""):gsub("%s+", ""):lower()
  if text == "" then return nil end
  if not text:find("[gsc]") then
    return dialogGoldPositive(box)
  end
  local gold = tonumber(text:match("^(%d+)g")) or 0
  local silver = tonumber(text:match("g?(%d+)s")) or 0
  local rest = tonumber(text:match("s?(%d+)c")) or 0
  local copper = gold * COPPER_PER_GOLD + silver * 100 + rest
  return exact(copper) and copper > 0 and copper or nil
end

-- The dialog's gold fields and YOUR PRICE's box both read and write these, so they live here.
fmt.goldPositive, fmt.goldText = dialogGoldPositive, copperToGoldText
fmt.priceText, fmt.priceBoxCopper = copperToPriceText, priceBoxCopper

function GC.Sell.Show()
  if UI.container then UI.container:Show() end
  -- The headings are otherwise only ever stamped when the DECK changes (List.RenderRows), and this
  -- tab spends most of its life hidden behind Deals or Sold: a one-line FontString that was on
  -- screen when its parent hid can come back with its text simply not drawn, and SetText is
  -- what the client needs to draw it again (UI/SniperFrame.lua's updateHeaderSortIndicators
  -- carries the full story). Unconditional, from the deck the header is currently showing.
  if UI.container and UI.container.header then
    UI.List.PaintHeaderText(UI.container.header, UI.container.headerDeck)
  end
  -- This is what flushes a render List.RenderRows() deferred while the container was hidden: Show()
  -- has always called Refresh() unconditionally, and Refresh()'s own Compose.Positions()+
  -- List.RenderRows() pass now runs for real the instant Walk.Shown() is true. An explicit
  -- flushDeferredRender() call here would render this same pass a second time.
  GC.Sell.Refresh()
  -- Mid-post the render is held, so coming back to the tab re-sets the dock's line and the
  -- busy labels with the text they already hold -- a no-op the client does not redraw on a
  -- one-line FontString that was hidden and shown (the engineering notes' "Text"): the row and
  -- the dock could sit on a bare spinner until the answer (review M4). Clear, set, hide, show,
  -- the cure UI/BuyFrame.lua's restampHeadings uses.
  if UI.container and (S.postingRow or GC.Sell._postNote) then
    local function restamp(fs)
      if not (fs and fs.IsShown and fs:IsShown()) then return end
      local text = fs:GetText() or ""
      fs:SetText(""); fs:SetText(text); fs:Hide(); fs:Show()
    end
    restamp(UI.container.dockStatus)
    restamp(UI.container.queueLabel)
    for _, button in ipairs({ UI.container.queueButton or false, S.postingRow and S.postingRow.action or false }) do
      if button and button.label and button.SetLabel then
        local label = button.label
        button:SetLabel(""); button:SetLabel(label)
        if type(button.text) == "table" then restamp(button.text) end
      end
    end
  end
end
function GC.Sell.Hide() if UI.container then UI.container:Hide() end end

function GC.Sell.Attach(f, geometry)
  UI.rowWidth, UI.rowHeight, UI.window = geometry.rowWidth, geometry.rowHeight, f
  UI.container = CreateFrame("Frame", nil, f)
  local container = UI.container
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top); container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom); container:Hide()
  -- Two rows of chrome and a footer, down from three rows of chrome. The three stat cards that
  -- used to own row 3 were 40px of ACCOUNTING sitting above the work; they are one quiet line
  -- in the footer now, beside the bulk action, where the eye ends rather than where it starts.
  --   row 1 (y   0): [TO POST N][MY LOTS N] ·········· [NO COST][READY][REFRESH]
  --   row 2 (y -34): column headings for the deck below
  --   list  (y -52) ......................................................... (to footer)
  --   footer (bottom, h32): [POST N] head label ··· held-back · cost / listed / profit
  -- Each row still owns its whole width: the layout this replaced let two anchor chains grow
  -- toward each other on one shared row and collide at ordinary window widths (the queue's head
  -- label ran under the filter chips; the cancel cluster ran under EST. PROFIT).
  UI.Dock.BuildFill()
  UI.Toolbar.Build()
  UI.Dock.Build(f)
  UI.List.Build()
  UI.Inspector.Build()
  UI.CostDialog.Build()
  -- OnSizeChanged fires once per pixel while the resize grip is being dragged -- as often as
  -- every frame -- and List.RenderRows is not free: it walks the filtered position list and
  -- rebuilds every visible row. Layout (the width-driven column drop) is cheap and stays
  -- immediate; the row rebuild is coalesced to a single pass once the size has settled,
  -- rather than rebuilding the model up to 60 times a second while the grip is dragged.
  local resizeRenderToken = 0
  f:HookScript("OnSizeChanged", function(_, width)
    UI.rowWidth = math.max(1, width - geometry.panelLeft - geometry.panelRightInset)
    -- Through the same function a panel opening uses: the width a resize leaves decides
    -- whether the panel still has a column of its own.
    container.listDocked = UI.INSP.docked()
    UI.List.ApplyListGeometry()
    UI.Dock.LayoutLedger()
    UI.Toolbar.LayoutSearch()
    resizeRenderToken = resizeRenderToken + 1
    local token = resizeRenderToken
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if token == resizeRenderToken then UI.List.RenderRows() end
      end)
    else
      UI.List.RenderRows()
    end
  end)
end

-- Live diagnosis for a wedged pricing walk, straight from the client: /goldcap sellstate
-- prints the machine's actual state instead of leaving "PRICING…" to be guessed about.
-- Registered here (not Core/Init.lua) because every field it reads is the Sell tab's own.
GC.slashHandlers = GC.slashHandlers or {}
-- The throttle flag as the CLIENT reports it, with no side effect.
--
-- Quotes.driver.isReady() is GC.Util.ThrottleReady(), which past its stuck window answers true on a
-- flag the client is still reporting false. That is the right answer for a sender and the
-- wrong one for a readout of what the CLIENT says, which is what these two printers want.
local function throttleReadyForDisplay()
  return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
    and C_AuctionHouse.IsThrottledMessageSystemReady() == true or false
end

GC.slashHandlers.sellstate = function()
  local pending = S.refresh.pending
  GC.Print((GC.L["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"]):format(
    tostring(S.refresh.phase), #S.refresh.queue, S.refresh.index or 0, S.refresh.skipped or 0,
    time() - (S.refresh.progressAt or 0),
    pending and (" · pending item %s for %ds"):format(tostring(pending.itemID), time() - pending.at) or ""))
  local blocking = GC.Sniper and (GC.Sniper.IsSearchCritical or GC.Sniper.IsBusy)
  local rested = 0
  for _, rest in pairs(S.emptyAnswers) do
    if type(rest) == "table" and type(rest.at) == "number"
        and time() - rest.at <= EMPTY_ANSWER_AGE then rested = rested + 1 end
  end
  GC.Print((GC.L["throttle ready=%s · sniper busy=%s · empty answers resting=%d"]):format(
    tostring(throttleReadyForDisplay()),
    tostring(blocking and blocking() or false), rested))
  -- Every row without a market price, and the EXACT reason the walk is not asking about it --
  -- mirrors Walk.Queue's own membership rules, so a "—" can always be explained.
  local shown = 0
  for _, position in ipairs(S.positions) do
    if position.displayMarketUnit == nil and position.itemID and shown < 12 then
      local inBags = type(position.bagQty) == "number" and position.bagQty > 0
      local listed = type(position.listedQty) == "number" and position.listedQty > 0
      local commodity = type(position.positionKey) == "string"
        and position.positionKey:find("commodity:", 1, true) == 1
      local restingAt = Walk.RestedAt(position.quoteKey or position.itemID)
      local resting = restingAt ~= nil and (time() - restingAt) <= EMPTY_ANSWER_AGE
      local why
      if position.unresolved and not commodity then
        why = GC.L["identity unresolved (variant item -- not priced by design)"]
      elseif not (inBags or listed) then
        why = GC.L["no stock in bags or listed -- nothing to price for"]
      elseif resting and Walk.RestedEmptyFresh(position.quoteKey or position.itemID, time()) then
        why = (GC.L["AH answered empty %ds ago"]):format(time() - restingAt)
      elseif resting then
        -- Rested but never ANSWERED. Printing the line above here is what made a wedged walk
        -- read as a quiet auction house.
        why = (GC.L["no answer %ds ago -- resting"]):format(time() - restingAt)
      else
        why = GC.L["due -- will be asked next pass"]
      end
      shown = shown + 1
      -- A variant by its exact key: two item levels of one piece read as one line by item ID.
      GC.Print(("  %s (%s): %s"):format(tostring(position.itemName or "?"),
        tostring(position.quoteKey or position.itemID), why))
    end
  end
end

-- `/gc sell`: the pricing walk's state and who holds the shared search slot, printed to
-- chat. For a live client that sits at "PRICING…" -- the walk yields to whatever owns the
-- slot and there is otherwise nothing on screen that says which gate it is waiting on.
function GC.Sell.DebugPrint()
  local sniper = GC.Sniper or {}
  -- What C_AuctionHouse.GetAuctionInfoByID said about the last auction created (GC.Sell.
  -- OnAuctionCreated): whether the client names a just-created auction at all.
  GC.Print(GC.Sell._createdSeen or "sell: created -- none this session")
  local function call(fn, ...) if type(fn) == "function" then return tostring(fn(...)) end return "n/a" end
  -- Why an item will not post, or a post was not booked (final review M7): the items a late
  -- answer holds and for how long, how long an answer a guess ended may still be owed, whether a
  -- post now would be certain, the stock waiting for the auction house, and the requests out.
  local held, now = {}, time()
  for _, late in ipairs(GC.Sell._LiveLate()) do
    held[#held + 1] = ("%s %ds"):format(itemName(late.pin.itemID) or tostring(late.pin.itemID),
      GC.Sell.LATE_ANSWER_SECONDS - (now - late.at))
  end
  GC.Print(("post: late=%d [%s] owed=%ds certain=%s waiting=%d requestOut=%s confirmOwed=%s"):format(
    #held, table.concat(held, ", "), math.max(0, (GC.Sell._owedUntil or 0) - now), tostring(GC.Sell._Certain()),
    #(GC.Sell._waitingStock or {}), call(sniper.RequestOut),
    GC.PurchaseSlot and call(GC.PurchaseSlot.ConfirmOwed) or "n/a"))
  GC.Print(("sell walk: phase=%s index=%d/%d pending=%s awaiting=%s gen=%d progress=%ds ago waitingNoted=%s"):format(
    tostring(S.refresh.phase), S.refresh.index or 0, #(S.refresh.queue or {}),
    tostring(S.refresh.pending and S.refresh.pending.itemID), tostring(S.refresh.awaiting),
    S.refresh.generation or 0, time() - (S.refresh.progressAt or time()), tostring(S.refresh.waitingNoted)))
  -- `apiReady` is the CLIENT's own flag, read with no side effect -- see throttleReadyForDisplay.
  GC.Print(("slot: ahOpen=%s apiReady=%s searchCritical=%s busy=%s paging=%s quietZone=%s quietSince=%s"):format(
    call(sniper.IsAHOpen),
    tostring(throttleReadyForDisplay()),
    call(sniper.IsSearchCritical), call(sniper.IsBusy),
    sniper._bookPass and call(function() return sniper._bookPass:IsPaging() end) or "n/a",
    call(sniper._QuietZoneOpen), tostring(sniper._quietSince)))
  -- The bulk fill's own state: whether a press is still owed one, whether it went, whether it
  -- landed, and every gate the arbiter would hold it at -- so "the prices did not come at once"
  -- can be answered from a paste instead of guessed at.
  GC.Print(("bulk: wanted=%s sent=%s landed=%s outstanding=%s targets=%d view=%s keysOwner=%s keysOut=%s pendingStart=%s playerBusy=%s"):format(
    tostring(S.refresh.bulkWanted), tostring(S.refresh.bulkSent), tostring(S.refresh.bulkLanded),
    tostring(GC.Sell.BulkOutstanding()), #GC.Sell.BulkTargets(), call(sniper.CurrentView),
    tostring(sniper._keysOwner), call(sniper._KeysOutstanding),
    sniper._bookPass and call(function() return sniper._bookPass:PendingStart() end) or "n/a",
    GC.AuctionHouseTab and call(GC.AuctionHouseTab.PlayerIsBusy) or "n/a"))
  -- A cancel's own state, so "I pressed Cancel lot and the tab went dead" can be answered from a
  -- paste: what is armed and how far it got, whether a render is being held behind it, and
  -- which lots were sent for cancelling and whether the server ever confirmed them.
  local sent, confirmed = 0, 0
  for _, lot in pairs(GC.Sell.cancelledLots or {}) do
    if lot.confirmed then confirmed = confirmed + 1 else sent = sent + 1 end
  end
  GC.Print(("cancel: armed=%s stage=%s ready=%s lot=%s renderHeld=%s posting=%s removing=%s sentUnconfirmed=%d confirmed=%d requery=%s"):format(
    tostring(S.repostingRow ~= nil), tostring(S.repostingRow and S.repostingRow.repostStage),
    tostring(S.repostingRow and S.repostingRow.repostReady), tostring(S.repostPin and S.repostPin.auctionID),
    tostring(S.deferredRender), tostring(S.postingRow ~= nil), tostring(S.removingRow ~= nil),
    sent, confirmed, tostring(S.refresh.ownedWanted)))
  local status = UI.window and UI.window.status and UI.window.status.GetText and UI.window.status:GetText()
  GC.Print("status: " .. tostring(status))
  local t = GC.Util.throttleStats
  GC.Print(("throttle events: queued=%d dropped=%d ready=%d forcedSends=%d"):format(t.queued, t.dropped, t.ready, t.forced))
end

-- What the Sell services (GoldCap/Services/Sell) ask of this screen. Each part fills its own slots
-- (List: render; Dock: status, paintQueue, paintCancel, notePost, endPostNote; Toolbar: paintDeck);
-- these two are the view's as a whole.
GC.SellView.attached = function() return UI.container ~= nil end
-- nil until the tab is built, then its own shown flag: the two questions the services ask of it
-- ("is it built", "is it up") stay as distinct as `container ~= nil` and `container:IsShown()` were.
GC.SellView.isShown = function()
  if UI.container and UI.container.IsShown then return UI.container:IsShown() end
end
