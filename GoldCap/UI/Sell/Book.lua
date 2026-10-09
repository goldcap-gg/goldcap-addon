-- THE BOOK in the inspector: the live order book the price beside it stands on, eight levels and
-- the lines under them. Built onto every pooled row (Book.Decorate), laid out and painted for the
-- panel's head. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local Theme = GC.Theme
local UI = GC.SellUI
local Book = UI.Book
local DR, INSP = UI.DR, UI.INSP
local setColor, formatCell = UI.fmt.setColor, UI.fmt.cell

-- The one line a seller needs before reading a single price: who is actually under me, and
-- how much stock is sitting there. `cheapestCompeting` subtracts the player's own units from a
-- shared price level rather than dropping the level (see CheapestCompetingUnit), so this is
-- the price to beat, not the cheapest row on screen.
-- A GC.Sell field, not a top-level local: paint-only, same reason as _FormatAmount in UI/Sell/Frame.lua
-- (final review "Headroom").
function GC.Sell._BookHint(book)
  if type(book) ~= "table" then return "" end
  local parts = {}
  if book.cheapestCompeting then
    parts[#parts + 1] = (GC.L["cheapest not yours %s"]):format(formatCell(book.cheapestCompeting))
  end
  -- The colour key that used to follow is said on the levels themselves now, in a word each.
  return table.concat(parts, " · ")
end

local BOOK_BAR_H = 6

-- Clear, set, hide, show: a one-line FontString on a pooled row that was hidden and shown again
-- can keep its text undrawn, and SetText with the text it already holds does not redraw it (the
-- engineering notes' "Text"). Ends shown.
local function stamp(fs, text)
  fs:SetText(""); fs:SetText(text or ""); fs:Hide(); fs:Show()
end

-- THE BOOK's eight lines. A commodity's book is chosen around the player's price (SellViewModel's
-- ladder): levels, a gap line for the stretch it skips, and a marker for the price itself. A
-- function of its own: paintHead sits near Lua 5.1's cap on upvalues.
local function paintLadder(row, book)
  local widest = book.widest or 0
  local count = function(n) return GC.Util.FormatCount(n or 0) or tostring(n or 0) end
  for lineIndex = 1, DR.LINES do
    local line, entry = row.bookLines[lineIndex], book.rows[lineIndex]
    line.tag:Hide(); line.note:Hide()
    if entry and entry.kind == "yours" then
      -- The player's own price at its sorted place, after the levels at an equal price: it
      -- would join their tail. What stands ahead of it is the one number this panel is for.
      -- The count first, and nothing the gold price and its wash already say: "your price · …
      -- units ahead of you" ran past the line in English and cut the number itself in Russian
      -- and Ukrainian (review M1). The same words as a row's own standing.
      local words = entry.pastRead and (GC.L["%s+ ahead"]):format(count(entry.ahead))
        or (entry.ahead or 0) == 0 and GC.L["first in line"]
        or (GC.L["%s ahead"]):format(count(entry.ahead))
      line.price:SetText(formatCell(entry.unit)); setColor(line.price, Theme.color.gold)
      line.price:Show(); line.qty:Hide(); line.bar:Hide()
      stamp(line.note, words); setColor(line.note, Theme.color.goldHi or Theme.color.gold)
      line.wash:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.10)
      line.wash:Show()
    elseif entry and entry.kind == "gap" then
      line.price:SetText("…"); setColor(line.price, Theme.color.fgDim)
      line.price:Show(); line.qty:Hide(); line.bar:Hide(); line.wash:Hide()
      stamp(line.note, (GC.L["%s units in %d prices"]):format(count(entry.units), entry.prices or 0))
      setColor(line.note, Theme.color.fgDim)
    elseif entry then
      -- Colour carries the facts a single number cannot: gold is where GoldCap's price would
      -- put you (a realm item's book, which has no marker), blue is stock already yours, red is
      -- a wall -- a level holding a big share of the day, that sells before anything priced
      -- over it.
      local colour, tint, wash = Theme.color.fg, nil, nil
      if book.yourRow == lineIndex then colour, tint, wash = Theme.color.gold, Theme.color.gold, Theme.color.gold
      elseif entry.mine then colour, tint, wash = Theme.color.watch, Theme.color.watch, Theme.color.watch end
      if entry.wall then tint = Theme.color.red end
      line.price:SetText(formatCell(entry.unit)); setColor(line.price, colour)
      line.qty:SetText(GC.Util.FormatCount(entry.units) or "—")
      setColor(line.qty, entry.wall and Theme.color.red or Theme.color.fgDim)
      -- A wall says so in a word at the start of its own bar, which then starts after it. A
      -- column for the word on every level held the bars and the figures off an edge of the
      -- panel for one level in eight (seen in game, twice); this costs only the wall's own bar.
      -- The word first, then the bar after it: measured, so it holds in every language and scale.
      local offset = 0
      if entry.wall then
        stamp(line.tag, GC.L["wall"]); setColor(line.tag, Theme.color.red)
        local measured = line.tag.GetUnboundedStringWidth and line.tag:GetUnboundedStringWidth()
        offset = type(measured) == "number" and measured > 0 and math.ceil(measured) + 3 or DR.WALL_TAG_W
        line.tag:SetWidth(offset)
      end
      local span = widest > 0 and (entry.units / widest) or 0
      line.bar.fill:ClearAllPoints()
      line.bar.fill:SetPoint("TOPLEFT", line.bar, "TOPLEFT", offset, 0)
      line.bar.fill:SetPoint("BOTTOMLEFT", line.bar, "BOTTOMLEFT", offset, 0)
      line.bar.fill:SetWidth(math.max(DR.BAR_MIN, math.floor((DR.BAR_MAX - offset) * span + 0.5)))
      if tint then line.bar.fill:SetVertexColor(tint[1], tint[2], tint[3], 0.8)
      else line.bar.fill:SetVertexColor(1, 1, 1, 0.22) end
      line.price:Show(); line.qty:Show(); line.bar:Show()
      if wash then
        line.wash:SetColorTexture(wash[1], wash[2], wash[3], 0.10)
        line.wash:Show()
      else
        line.wash:Hide()
      end
    else
      line.price:Hide(); line.qty:Hide(); line.bar:Hide(); line.wash:Hide()
    end
  end
end

-- The line under a commodity's ladder: past the levels read, that the marker's count is a floor
-- (the read stopped there; nothing past it is counted or guessed); otherwise how long the queue
-- ahead of the price takes at today's pace -- the sells/day the panel shows, nothing when that
-- is unknown or nothing is ahead. Count first and short, in its own cell beside "yours ×N": the
-- long wording cut the count itself, and the key after it, in most languages (final review I1).
local function standWords(book)
  if book.pastRead then
    -- The marker's number, which leaves the player's own units out -- the book's total put a
    -- second figure beside it (review M4).
    return (GC.L["%s+, %d prices read"]):format(GC.Util.FormatCount(book.ahead or 0) or tostring(book.ahead or 0),
      book.levels or 0)
  end
  local hours = book.hoursToReach
  if type(hours) ~= "number" then return "" end
  if hours < 24 then return (GC.L["~%dh to reach you"]):format(math.max(1, math.floor(hours + 0.5))) end
  return (GC.L["~%dd to reach you"]):format(math.floor(hours / 24 + 0.5))
end

-- The walls around a commodity's price, for the facts line: the nearest at or under it and the
-- first above it. Empty for a book with no price of the player's, or no walls.
local function wallWords(book)
  local words = {}
  local function amount(wall)
    return GC.Util.FormatCount(wall.units) or tostring(wall.units), formatCell(wall.unit)
  end
  if book.commodity and book.wallBelow then
    words[#words + 1] = (GC.L["wall %s at %s -- price under it to sell first"]):format(amount(book.wallBelow))
  end
  if book.commodity and book.wallAbove then
    words[#words + 1] = (GC.L["wall %s at %s above you"]):format(amount(book.wallAbove))
  end
  return words
end

-- The book lines and the drawer's headings, on every pooled row: createRow (UI/Sell/Row.lua) calls
-- this. See the first comment inside for why they are built up front.
function Book.Decorate(row)
  -- The drawer's own five book lines. Built here rather than lazily on first open: a widget
  -- created mid-render is how this suite's fakes start failing on a method they were never
  -- taught, and rows are pooled and few.
  row.bookLines = {}
  for i = 1, DR.LINES do
    local line = {}
    line.price = Theme.Num(row, 11)
    line.price:SetJustifyH("RIGHT")
    line.price:SetWordWrap(false)
    line.qty = Theme.Num(row, 10)
    line.qty:SetJustifyH("RIGHT")
    line.qty:SetWordWrap(false)
    line.bar = CreateFrame("Frame", nil, row)
    line.bar:SetHeight(BOOK_BAR_H)
    -- Pills, as the design drew them: bar.png is white art with rounded ends, sliced so the ends
    -- keep their shape at any width and tinted through SetVertexColor -- SetColorTexture on a
    -- sliced region drops the art and paints the square block these replaced.
    line.bar.track = Theme.SlicedTexture(line.bar, "BACKGROUND", Theme.MEDIA .. "bar.png",
      { 1, 1, 1, 0.05 }, DR.BAR_SLICE)
    line.bar.track:SetAllPoints()
    line.bar.fill = Theme.SlicedTexture(line.bar, "ARTWORK", Theme.MEDIA .. "bar.png",
      { 1, 1, 1, 0.22 }, DR.BAR_SLICE)
    line.bar.fill:SetPoint("TOPLEFT")
    line.bar.fill:SetPoint("BOTTOMLEFT")
    line.bar.fill:SetWidth(DR.BAR_MIN)
    -- The level the seller's price lands on, or already holds, is said in a word beside it and
    -- a wash behind it. Colour alone carried that, explained once in a hint long enough to be
    -- cut off at the panel's width -- a colour nobody explained is a colour nobody reads.
    line.tag = Theme.Num(row, 9)
    line.tag:SetJustifyH("LEFT"); line.tag:SetWordWrap(false); line.tag:SetMaxLines(1)
    -- The line's words when it is not a level: "your price · 2.3k units ahead of you", or the
    -- stretch of the book the ladder skips.
    line.note = Theme.Num(row, 10)
    line.note:SetJustifyH("LEFT"); line.note:SetWordWrap(false); line.note:SetMaxLines(1)
    line.wash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    line.price:Hide(); line.qty:Hide(); line.bar:Hide(); line.tag:Hide(); line.note:Hide(); line.wash:Hide()
    row.bookLines[i] = line
  end
  -- Column headings and the bottom line. Separate FontStrings rather than reusing subItem and
  -- sectionLabel: the drawer shows all four AT ONCE, where every other row kind shows exactly
  -- one of them.
  row.drawerPriceHead = Theme.Num(row, 9)
  row.drawerBookHead = Theme.Num(row, 10, true)
  row.drawerHint = Theme.Num(row, 9)
  row.drawerHint:SetJustifyH("RIGHT")
  -- Mono-10, as the rest of the foot: the line and "yours ×N" beside it are budgeted in that face
  -- (spec/button_label_width_spec.lua).
  row.drawerStand = Theme.Num(row, 10)
  row.drawerStand:SetJustifyH("LEFT")
  row.drawerOwn = Theme.Num(row, 10)
  row.drawerOwn:SetJustifyH("RIGHT")
  row.drawerOwn:SetWordWrap(false)
  row.drawerOwn:SetMaxLines(1)
  row.drawerOwn:Hide()
  row.drawerFacts = Theme.Num(row, 10)
  row.drawerFacts:SetJustifyH("LEFT")
  -- The right-hand ends of the two lines under the book: how deep it is, how old the quote is.
  row.drawerDepth = Theme.Num(row, 10)
  row.drawerQuote = Theme.Num(row, 10)
  for _, line in ipairs({ row.drawerDepth, row.drawerQuote }) do
    line:SetWordWrap(false); setColor(line, Theme.color.fgDim); line:Hide()
  end
  row.drawerFacts:SetWordWrap(false)
  row.drawerPriceHead:Hide(); row.drawerBookHead:Hide()
  row.drawerHint:Hide(); row.drawerStand:Hide(); row.drawerFacts:Hide()
end

-- The book section of the panel's head, under the rule across the panel at `top`, which the price
-- section above decides (layoutDrawer, UI/Sell/Inspector.lua).
function Book.Layout(row, top)
  local left, right = INSP.PAD, -INSP.PAD
  row.headRules[1]:ClearAllPoints()
  row.headRules[1]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, top)
  row.headRules[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, top)
  row.drawerBookHead:ClearAllPoints()
  row.drawerBookHead:SetPoint("TOPLEFT", row, "TOPLEFT", left, top - 12)
  row.drawerHint:ClearAllPoints()
  row.drawerHint:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, top - 12)
  row.drawerHint:SetPoint("LEFT", row.drawerBookHead, "RIGHT", 8, 0)
  row.drawerHint:SetJustifyH("RIGHT")
  row.drawerHint:SetWordWrap(false)

  local body = top - 32
  for i = 1, DR.LINES do
    local line = row.bookLines[i]
    local y = body - (i - 1) * DR.LINE_H
    line.price:ClearAllPoints()
    line.price:SetWidth(DR.PRICE_W)
    line.price:SetPoint("TOPLEFT", row, "TOPLEFT", left, y)
    -- The word sits at the LEFT of its level, in the room a right-aligned price leaves in its
    -- own column. It had a column to itself at the right edge, empty on every level but one or
    -- two, so the bars and the unit counts stopped 46px short of the panel they sit in.
    line.qty:ClearAllPoints()
    line.qty:SetWidth(DR.UNITS_W)
    line.qty:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, y)
    line.bar:ClearAllPoints()
    line.bar:SetPoint("LEFT", line.price, "RIGHT", Theme.pad.s, 0)
    line.bar:SetPoint("RIGHT", line.qty, "LEFT", -Theme.pad.s, 0)
    -- "wall" at the start of its own level's bar, which then starts after the word: a column of
    -- its own for one level in eight cost the book its width twice before (paintLadder, below).
    -- Its width is the word's own, set where the word is (paintLadder, below).
    line.tag:ClearAllPoints()
    line.tag:SetPoint("LEFT", line.bar, "LEFT", 0, 0)
    -- The marker's and the gap's words, where a level has its bar and its count.
    line.note:ClearAllPoints()
    line.note:SetPoint("LEFT", line.bar, "LEFT", 0, 0)
    line.note:SetPoint("RIGHT", line.qty, "RIGHT", 0, 0)
    line.wash:ClearAllPoints()
    line.wash:SetPoint("TOPLEFT", row, "TOPLEFT", left - 4, y + 4)
    line.wash:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", right + 4, y - DR.LINE_H + 4)
  end

  -- No book: the foot follows the heading directly, and its first line -- the sentence saying
  -- the auction house has not answered -- is allowed to wrap instead of being cut mid-word.
  local hasBook = row.bookLines[1].price:IsShown()
  local foot = hasBook and (body - DR.LINES * DR.LINE_H - 4) or body
  row.drawerStand:ClearAllPoints()
  -- Three lines, each with the panel's width to itself or a fixed half of it, so nothing is
  -- ever cut to "stands 1 o...": where the price stands; how deep the book is, with the quote's
  -- state at the right; how fast it sells and how long the queue is.
  row.drawerStand:SetPoint("TOPLEFT", row, "TOPLEFT", left, foot)
  -- "yours ×N" at the right end of the same line, the words ending where it begins.
  row.drawerOwn:ClearAllPoints()
  row.drawerOwn:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, foot)
  if hasBook and row.drawerOwn:IsShown() then
    row.drawerStand:SetPoint("RIGHT", row.drawerOwn, "LEFT", -8, 0)
  else
    row.drawerStand:SetPoint("RIGHT", row, "RIGHT", right, 0)
  end
  row.drawerStand:SetWordWrap(not hasBook)
  row.drawerStand:SetMaxLines(hasBook and 1 or 2)
  if not hasBook then
    row.drawerStand:SetText(row.drawerStand:GetText() or "")
    foot = foot - 14
  end
  row.drawerDepth:ClearAllPoints()
  row.drawerDepth:SetJustifyH("LEFT")
  row.drawerDepth:SetPoint("TOPLEFT", row, "TOPLEFT", left, foot - 18)
  row.drawerQuote:ClearAllPoints()
  row.drawerQuote:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, foot - 18)
  row.drawerFacts:ClearAllPoints()
  row.drawerFacts:SetPoint("TOPLEFT", row, "TOPLEFT", left, foot - 36)
  row.drawerFacts:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.drawerFacts:SetJustifyH("LEFT")
  row.drawerFacts:SetWordWrap(true)
  row.drawerFacts:SetMaxLines(2)
  if row.drawerFacts.SetSpacing then row.drawerFacts:SetSpacing(3) end
  -- A FontString sizes itself when its text is SET, and renderRows sets these before this
  -- runs: on a pooled row that was a one-line kind a moment ago, two lines of facts got one
  -- line's height and the rest was not drawn until the next render (seen in game).
  row.drawerFacts:SetText(row.drawerFacts:GetText() or "")
end

-- THE BOOK's half of the panel's head: the heading, the eight levels, and the lines under them.
-- INSP.paintHead calls this between the price side and the advice.
function Book.Paint(row, p, d)
  local book = d and d.book or nil
  row.drawerBookHead:SetText(GC.L["THE BOOK"]); row.drawerBookHead:Show()
  setColor(row.drawerBookHead, Theme.color.fgDim)

  -- ---- the book side: the evidence the price on the left stands on, beside it rather
  -- than eight rows below it.
  if book then
    row.headRules[1]:Show()
    row.drawerHint:SetText(GC.Sell._BookHint(book)); row.drawerHint:Show()
    setColor(row.drawerHint, Theme.color.fgDim)
    paintLadder(row, book)
    -- How deep the book is rides here, after where the price stands in it: the hint beside the
    -- heading has room for the price to beat and nothing else.
    row.drawerDepth:SetText((GC.L["%d units · %d prices"]):format(book.totalUnits or 0, book.levels or 0))
    row.drawerDepth:Show()
    -- What is already the seller's, in the blue its levels are drawn in -- the colour's key: every
    -- unit of theirs the book read, drawn or not (final review M6). A cell of its own at the right
    -- of the line, so the words beside it can never push it off (I1).
    local ownUnits = type(book.ownUnits) == "number" and book.ownUnits or 0
    local own = ownUnits > 0 and (book.yourRow or (book.commodity and book.yourUnit))
    if own then
      row.drawerOwn:SetText((GC.L["yours ×%s"]):format(GC.Util.FormatCount(ownUnits) or tostring(ownUnits)))
      setColor(row.drawerOwn, Theme.color.watch)
      row.drawerOwn:Show()
    else
      row.drawerOwn:SetText(""); row.drawerOwn:Hide()
    end
    if book.commodity and book.yourUnit then
      -- Where the price stands is the marker's, in the ladder; this line says what it means:
      -- how long the queue ahead takes at today's pace, or -- past the levels read -- that the
      -- count is a floor, never a number made up for the rest.
      row.drawerStand:SetText(standWords(book))
      setColor(row.drawerStand, Theme.color.goldHi)
    elseif book.yourRow then
      row.drawerStand:SetText((GC.L["price stands %d of %d"]):format(book.yourRow, book.levels or 0))
      setColor(row.drawerStand, Theme.color.goldHi)
    else
      row.drawerStand:SetText(GC.L["your price is above every level shown"])
      setColor(row.drawerStand, Theme.color.fgDim)
    end
  else
    row.drawerHint:Hide()
    row.headRules[1]:Show()
    for _, line in ipairs(row.bookLines) do
      line.price:Hide(); line.qty:Hide(); line.bar:Hide(); line.tag:Hide(); line.note:Hide(); line.wash:Hide()
    end
    row.drawerDepth:Hide(); row.drawerOwn:Hide()
    row.drawerStand:SetText(GC.L["the Auction House has not answered for this item yet"])
    setColor(row.drawerStand, Theme.color.fgDim)
  end
  row.drawerStand:Show()

  -- ---- the foot of the book section, split the way it is read: how fast this sells and how
  -- long the queue is on the left, how old the quote behind all of it is on the right. It was
  -- one run-on line ("market 199g97s . fresh . age 12s . ...") led by a price the book's own
  -- first level and the hint beside the heading both already show.
  local facts, quote = {}, nil
  if d and d.displayMarketUnit ~= nil then
    -- The market price is said in words only when there is no book to read it off: with one,
    -- it is the first level and the hint beside the heading.
    if not book then facts[#facts + 1] = (GC.L["market %s"]):format(formatCell(d.displayMarketUnit)) end
    if d.marketState == "stale" and type(d.quoteAge) == "number" then
      -- The age of the last LIVE quote for this item, not of the prices behind the tab: right
      -- after a full scan a red "stale" read as an error (WoW: Forever, 2026-09-26).
      quote = (GC.L["last live price %s ago"]):format(GC.Util.FormatElapsedWords(d.quoteAge)
        or GC.Util.FormatElapsedWords(0))
    else
      quote = d.marketState == "fresh" and GC.L["fresh"] or GC.L["unavailable"]
      if type(d.quoteAge) == "number" then quote = quote .. " · " .. (GC.L["age %ss"]):format(d.quoteAge) end
    end
  elseif d and type(d.quoteAge) == "number" then
    quote = (GC.L["quote %ss ago"]):format(d.quoteAge)
  end
  -- A listed lot's own queue -- but not beside THE BOOK's marker, whose count and times are
  -- about the post price: one count on the panel, not two (review N2).
  local marker = book and book.commodity and book.yourUnit
  if d and type(d.ahead) == "number" and not marker then facts[#facts + 1] = (GC.L["%d ahead of you"]):format(d.ahead) end
  if d and d.sold ~= nil then facts[#facts + 1] = (GC.L["sells %s/day"]):format(d.sold) end
  -- In hours under a day: rounded to whole days, anything that sells through by this
  -- evening read "clears in ~0d". A commodity priced in THE BOOK clears on the book's own pace
  -- -- the queue ahead of it, then its own units, the same figure "~Xh to reach you" is the first
  -- half of (SellViewModel's clearsHours). The listed-lot outlook left the queue out for bag
  -- stock and said ~1h beside ~6h (review I1).
  local days = d and type(d.days) == "number" and d.days or nil
  if marker then
    days = type(book.clearsHours) == "number" and book.clearsHours / 24 or nil
  end
  if days then
    facts[#facts + 1] = days < 1 and (GC.L["clears in ~%dh"]):format(math.max(1, math.floor(days * 24 + 0.5)))
      or (GC.L["clears in ~%dd"]):format(math.floor(days + 0.5))
  end
  -- The walls around the price last: the two lines may cut a wall -- the ladder still shows it,
  -- in red -- but not the pace every time on this panel is measured by (review M2).
  for _, words in ipairs(book and wallWords(book) or {}) do facts[#facts + 1] = words end
  local notPriced = (p.bagQty or 0) == 0 and (p.listedQty or 0) == 0 and not p.unresolved
  row.drawerFacts:SetText(#facts > 0 and table.concat(facts, " · ")
    or (quote and "" or (notPriced and GC.L["not priced — nothing on hand to sell"] or GC.L["no live quote yet — pricing…"])))
  setColor(row.drawerFacts, Theme.color.fgDim)
  row.drawerFacts:Show()
  -- The words already say whether this is the last live price or a fresh one, so the color
  -- no longer has to carry that too (WoW: Forever, 2026-09-26).
  row.drawerQuote:SetText(quote or "")
  setColor(row.drawerQuote, Theme.color.fgDim)
  row.drawerQuote:Show()
end

-- A pooled row is rebound to another kind on every render: whatever kind takes it next puts the
-- book away (renderRows' put-away, for every kind but the panel's head).
function Book.PutAway(row)
  row.drawerPriceHead:Hide(); row.drawerBookHead:Hide()
  row.drawerHint:Hide(); row.drawerStand:Hide(); row.drawerFacts:Hide(); row.drawerOwn:Hide()
  row.drawerDepth:Hide(); row.drawerQuote:Hide()
  for _, line in ipairs(row.bookLines) do
    line.price:Hide(); line.qty:Hide(); line.bar:Hide(); line.tag:Hide(); line.note:Hide(); line.wash:Hide()
  end
end
