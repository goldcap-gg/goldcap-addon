-- The Sell tab's view, the part every other file under UI/Sell/ builds on. It loads first
-- (helper.SELL_UI_FILES, both TOCs) and plays the part Services/Sell/State.lua plays for the
-- services: GC.SellUI holds one module table per part of the view, the geometry more than one
-- part lays out by, and the pure helpers that colour text and format money. Calls between the
-- parts go through these tables at call time, never through a copy taken at load, so a spec that
-- replaces a function reaches every caller (spec/sell_ui_structure_spec.lua).
-- wow-auction: docs/superpowers/specs/2026-10-09-addon-ui-kit-and-sell-design.md, Part 2.
local _, GC = ...

GC.Sell = GC.Sell or {}

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
  -- can (INSP.paintLadder); this is the fallback, the widest language's word ("стена") in mono-9 at
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
