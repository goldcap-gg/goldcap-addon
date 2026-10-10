-- The inspector: the side panel a position opens into. The price the dock posts the item at, the
-- five fills for it and GoldCap's advice; the panel's other lines (a heading, a live lot, the bag
-- line); the panel frame. The price is typed, and the item posted, in the dock (UI/Sell/
-- PostPanel.lua): one place to post from (owner, 2026-10-10). THE BOOK beside the price is
-- UI/Sell/Book.lua's, and a purchase line UI/Sell/CostDialog.lua's. Moved from UI/SellFrame.lua
-- as it was.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local Bags, Post = GC.SellBags, GC.SellPost
local exact, safeMultiply, overrideKey, effectivePostUnit = GC.SellUtil.exact, GC.SellUtil.safeMultiply,
  GC.SellUtil.overrideKey, GC.SellUtil.effectivePostUnit
local postQuantity = GC.SellUtil.postQuantity
local UI = GC.SellUI
local Inspector = UI.Inspector
local COLUMNS, ROW, DR, INSP = UI.COLUMNS, UI.ROW, UI.DR, UI.INSP
local setColor, formatCell = UI.fmt.setColor, UI.fmt.cell

-- The book's own four columns, mirroring the design: price, depth at that price, a bar for
-- that depth, and the units queued in front of it. Fixed, and deliberately independent of
-- shownColumns -- a book row shows the same four things at every window width.
-- The chips' own width. Laid out by layoutDrawer, independently of the shedding column set: the
-- panel shows the same things at every width.
local PRICE_CHIP_W = 56
-- The chips, by slot. Two parallel tables rather than one of {id, label} pairs: the contract
-- scanner reads every literal inside an @localised-keys table, and an id sitting in the same
-- table would be collected as a translatable string nobody ever shows.
-- @localised-keys
local PRICE_CHIP_LABELS = {
  "GOLDCAP", "MATCH", "UNDERCUT", "MARKET", "COST",
}
-- What each slot fills from. The SLOT is the stable key the click handler switches on, never
-- the label -- a translated label would look up nothing (the addon's engineering notes' own rule).
-- "goldcap" is the way BACK: it fills from nothing and clears the seller's own price, which
-- until now could only be done by emptying the box -- a gesture nothing on screen suggested.
local PRICE_CHIP_IDS = { "goldcap", "match", "under", "market", "cost" }

-- Whether the panel is open, and whether it has a column of its own. Hung on INSP rather than
-- left as four more file-level locals: WoW's Lua 5.1 allows a chunk 200 of them, and
-- UI/SellFrame.lua was close enough to that for the client to refuse to load it (busted's newer
-- Lua never says).
do
  local isOpen = false
  function INSP.docked()
    return isOpen and (UI.rowWidth or 0) >= INSP.DOCK_MIN
  end
  -- The LIST's width, which is the container's less a docked panel's column.
  function INSP.listWidth()
    local width = UI.rowWidth or 0
    if INSP.docked() then width = width - INSP.W - INSP.GAP end
    return width
  end
  -- Opens or shuts the panel as far as geometry goes: the list's heading row and scroll area
  -- are re-anchored only when that changes whether the panel has a column of its own.
  function INSP.sync(open)
    isOpen = open
    local container = UI.container
    if container.scroll and container.listDocked ~= INSP.docked() then
      container.listDocked = INSP.docked()
      UI.List.ApplyListGeometry()
    end
  end
end

-- Beside the panel's YOUR LOTS heading: how many, and what they ask for in all.
function ROW.lotsAside(position)
  local lots = #(position.ownedLots or {})
  local asked = formatCell(position.listedValue)
  if lots == 1 then return (GC.L["1 lot, %s asked"]):format(asked) end
  return (GC.L["%d lots, %s asked"]):format(lots, asked)
end

-- Action and price, nothing else. This cell used to narrate the pricing mode
-- in a sentence ("Post (queueing at your exit -- cheaper lots sell through
-- first) @ 18g15s · breakeven 20g41s"), and in game the words won: the column
-- truncated BEFORE the price, showing "Post (queueing at…" — advice with the
-- one number that matters cut off (owner, 2026-08-19). What survives the trim
-- is only what changes the player's next move: RepostAdvice's one-word hold
-- reason ("loss"/"slow"), and the below-cost warning.
-- A GC.Sell field, not a top-level local: paint-only (final review "Headroom").
function GC.Sell._RecommendationText(recommendation)
  if type(recommendation) == "string" then return recommendation end
  if type(recommendation) ~= "table" then return "" end
  local action = recommendation.action
  if type(action) ~= "string" or action == "" then action = "post" end
  action = action:sub(1, 1):upper() .. action:sub(2)
  local nested = recommendation.rec
  local unit = nested and nested.unit or recommendation.unit
  local reason = type(recommendation.reason) == "string" and recommendation.reason or nil
  local text = action .. (reason and (" (" .. reason .. ")") or "")
    .. (unit and (" @ " .. formatCell(unit)) or "")
  if recommendation.belowCost then text = text .. GC.L[" · below cost"] end
  return text
end

-- The panel head's own layout, one column. Independent of shownColumns: the panel shows the
-- same things at every window width, and its width is INSP's, not the list's.
local function layoutDrawer(row)
  local left, right = INSP.PAD, -INSP.PAD
  local postable = type(row.position) == "table" and (row.position.bagQty or 0) > 0

  -- ---- the price section: the price the dock posts at, whose it is, and the fills for it
  row.drawerPriceHead:ClearAllPoints()
  row.drawerPriceHead:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.HEAD_Y)
  row.priceFigure:ClearAllPoints()
  row.priceFigure:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.PRICE_Y)
  row.priceFigure:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.priceNote:ClearAllPoints()
  row.priceNote:SetPoint("TOPLEFT", row, "TOPLEFT", left, postable and DR.NOTE_Y or DR.PRICE_Y)
  row.priceNote:SetPoint("RIGHT", row, "RIGHT", right, 0)
  -- Wraps rather than cuts: "under GoldCap's own floor of ..." has to be read whole in every
  -- language.
  row.priceNote:SetWordWrap(true)
  row.priceNote:SetMaxLines(2)

  -- One strip, five equal segments: a switch with a position, not five loose buttons.
  row.chipsBg:ClearAllPoints()
  row.chipsBg:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.CHIPS_Y)
  row.chipsBg:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, DR.CHIPS_Y)
  row.chipsBg:SetHeight(DR.CHIP_H + 4)
  local prev
  for i = 1, #row.priceChips do
    local chip = row.priceChips[i]
    chip:ClearAllPoints()
    chip:SetSize(PRICE_CHIP_W, DR.CHIP_H)
    if prev then chip:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    else chip:SetPoint("TOPLEFT", row, "TOPLEFT", left + 3, DR.CHIPS_Y - 2) end
    prev = chip
  end

  -- What GoldCap would do and why, in a sentence that is allowed its second line. It lives
  -- HERE because WHAT TO DO is not a column on either deck.
  row.subItem:ClearAllPoints()
  row.subItem:SetWidth(0)
  row.subItem:SetPoint("TOPLEFT", row, "TOPLEFT", left, postable and DR.REC_Y or (DR.PRICE_Y - 18))
  row.subItem:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.subItem:SetWordWrap(true)
  row.subItem:SetMaxLines(2)
  if row.subItem.SetSpacing then row.subItem:SetSpacing(3) end
  row.subItem:SetText(row.subItem:GetText() or "") -- measured again now that it wraps

  -- With nothing to say about the price, the book moves up into the paragraph's room (one slot
  -- of it; the head was given one slot less -- see DR.NO_REASON_SLOTS).
  local rise = postable and (row.subItem:GetText() or "") == "" and DR.NO_REASON_SLOTS * (UI.rowHeight or 32) or 0

  -- ---- the book section, under a rule across the panel
  local top = (postable and DR.BOOK_Y or DR.BOOK_Y_BARE) + rise
  UI.Book.Layout(row, top)
end

-- A lot, a bag line, a purchase or a heading inside the panel. None of the deck's columns
-- apply at this width: a line is its sentence, with its one button -- or, for a purchase, its
-- unit cost -- at the right edge. Two lines allowed, because "x50 . 3 purchases . bought 29 Aug
-- . GoldCap . mail-confirmed" is a sentence the panel is narrower than.
local function layoutDetailRow(row)
  for _, column in ipairs(COLUMNS) do row.cells[column.key]:Hide() end
  local edge, edgePoint, inset = row, "RIGHT", -INSP.PAD
  if row.action:IsShown() then
    row.cells.action:ClearAllPoints()
    row.cells.action:SetWidth(88)
    row.cells.action:SetPoint("RIGHT", row, "RIGHT", -INSP.PAD, 0)
    edge, edgePoint, inset = row.cells.action, "LEFT", -4
  end
  if row.kind == "batch" then
    -- Quantity, unit cost, source-and-date, evidence -- or, for a hand-entered cost, the button
    -- that takes it back, where the evidence word would only say "manual" a second time.
    row.subItem:ClearAllPoints()
    row.subItem:SetWidth(50) -- "×99999"
    row.subItem:SetPoint("LEFT", row, "LEFT", INSP.PAD, 0)
    row.subItem:SetWordWrap(false)
    row.subItem:SetMaxLines(1)
    row.cells.cost:ClearAllPoints()
    row.cells.cost:SetWidth(88) -- "999[g] 99[s]" in the game's coins
    row.cells.cost:SetPoint("LEFT", row.subItem, "RIGHT", 2, 0)
    row.cells.cost:Show()
    row.sectionHint:ClearAllPoints()
    row.sectionHint:SetPoint("RIGHT", row, "RIGHT", -INSP.PAD, 0)
    if row.action:IsShown() then row.sectionHint:Hide() end
    row.itemStock:ClearAllPoints()
    -- One line in a one-slot row: a list position wraps its stock line (List.lua's placeName), a
    -- purchase's source and date are short words that stay on theirs.
    row.itemStock:SetWordWrap(false)
    row.itemStock:SetPoint("LEFT", row.cells.cost, "RIGHT", 10, 0)
    if row.action:IsShown() then row.itemStock:SetPoint("RIGHT", row.cells.action, "LEFT", -6, 0)
    else row.itemStock:SetPoint("RIGHT", row.sectionHint, "LEFT", -8, 0) end
    row.itemStock:Show()
  else
    -- Every other line is one sentence, allowed a second line when the panel is narrower than
    -- it, with air between the two.
    row.subItem:ClearAllPoints()
    row.subItem:SetWidth(0)
    row.subItem:SetPoint("LEFT", row, "LEFT", INSP.PAD, 0)
    row.subItem:SetPoint("RIGHT", edge, edgePoint, inset, 0)
    row.subItem:SetWordWrap(true)
    row.subItem:SetMaxLines(2)
    if row.subItem.SetSpacing then row.subItem:SetSpacing(3) end
    row.subItem:SetText(row.subItem:GetText() or "") -- re-measured now that it wraps; see layoutDrawer
  end
  row.sectionLabel:ClearAllPoints()
  row.sectionLabel:SetPoint("LEFT", row, "LEFT", INSP.PAD, -4)
  if row.kind ~= "batch" then -- a purchase has just placed it as its evidence column
    row.sectionHint:ClearAllPoints()
    row.sectionHint:SetPoint("RIGHT", row, "RIGHT", -INSP.PAD, -4)
  end
  -- A section starts under a rule across the whole panel, the way the book's does, rather than
  -- with a gold line trailing off its own heading.
  row.sectionRule:ClearAllPoints()
  row.sectionRule:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
  row.sectionRule:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  row.sectionRule:SetColorTexture(1, 1, 1, 0.06)
  setColor(row.sectionLabel, Theme.color.fgMuted)
  -- The head lays itself out over this: called from here so renderRows has one panel layout
  -- to know about, not two (see rowTag on why that function counts its upvalues).
  if row.kind == "drawer" then layoutDrawer(row) end
end

Inspector.LayoutDetailRow = layoutDetailRow

-- The price section on every pooled row: createRow (UI/Sell/Row.lua) calls this. Only the panel's
-- head shows it (INSP.paintHead); every other kind puts it away (Inspector.PutAway).
function Inspector.Decorate(row)
  -- The price the dock posts this item at, big enough to be the first thing read in the panel.
  -- Read-only here: it is typed in the dock beside POST, the one place it posts from, and the
  -- chips under it fill the same price.
  row.priceFigure = Theme.Num(row, 14, true)
  row.priceFigure:SetJustifyH("LEFT"); row.priceFigure:SetWordWrap(false)
  row.priceFigure:Hide()
  -- The strip the five price chips sit in, and the rule over the book section. The window's own
  -- ground colour, a step darker than the panel; several of this suite's theme doubles carry no
  -- `bg`, hence the fallback.
  local wellc = Theme.color.bg or Theme.color.panel
  row.chipsBg = Theme.SlicedTexture(row, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { wellc[1], wellc[2], wellc[3], 1 }, 12)
  row.chipsBg:Hide()
  row.headRules = {}
  for i = 1, 1 do
    local rule = row:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.06)
    rule:SetHeight(1)
    rule:Hide()
    row.headRules[i] = rule
  end

  row.priceNote = Theme.Num(row, 10)
  row.priceNote:SetJustifyH("LEFT")
  row.priceNote:SetWordWrap(false)
  row.priceNote:Hide()

  -- Five one-click fills, each from a number already on the screen, so the common cases need no
  -- arithmetic. Each writes the price the dock posts at; GOLDCAP gives it back to GoldCap.
  row.priceChips = {}
  for slot = 1, #PRICE_CHIP_LABELS do
    local chip = Theme.Button(row, "ghost", "badge")
    chip:SetSize(PRICE_CHIP_W, DR.CHIP_H)
    chip:SetScript("OnClick", function(self)
      local key = overrideKey(row.position)
      if not key or not (self.priceSource or self.handsBack) then return end
      -- handsBack is the GOLDCAP chip: no price of its own, it gives the decision back.
      local price = not self.handsBack and self.priceSource or nil
      -- A Confirm armed with the old price is let go: it would send that one (review).
      if S.priceOverrides[key] ~= price then Post.WalkAway() end
      S.priceOverrides[key] = price
      UI.List.RenderRows()
    end)
    chip:Hide()
    row.priceChips[slot] = chip
  end
end

-- The detail panel's head: the price control, the book it lands in, and the line of facts.
-- A function of its own rather than a branch of renderRows, which is where it was written:
-- in UI/SellFrame.lua that function sat two short of Lua 5.1's 60-upvalue cap, and everything
-- this reads -- the price chips, the book hint, the gold parser -- was counted against it.
function INSP.paintHead(row, p, d)
  local book = d and d.book or nil
  local postable = (p.bagQty or 0) > 0

  -- ---- the price side: the same widgets and the same commit path the price ROW used,
  -- so nothing about what a typed price does has changed -- only where it is shown.
  local unit, chosen = effectivePostUnit(p)
  local risk = GC.SellPositions.PriceRisk(p, unit)
  row.drawerPriceHead:SetText(GC.L["YOUR PRICE"]); row.drawerPriceHead:Show()
  setColor(row.drawerPriceHead, chosen and Theme.color.gold or Theme.color.fgDim)
  if postable then
    -- The price the dock posts at (UI/Sell/PostPanel.lua), with whose it is and how many go, or
    -- what is wrong with it in red -- the dock's own box says the same.
    row.priceFigure:SetText(unit and formatCell(unit) or "")
    setColor(row.priceFigure, (risk.belowCost or risk.belowFloor) and Theme.color.red
      or chosen and Theme.color.gold or Theme.color.fg)
    row.priceFigure:Show(); row.chipsBg:Show()
    if risk.belowCost then
      row.priceNote:SetText((GC.L["below the %s you paid"]):format(formatCell(risk.paidUnit)))
      setColor(row.priceNote, Theme.color.red)
    elseif risk.belowFloor then
      row.priceNote:SetText((GC.L["under GoldCap's own floor of %s"]):format(formatCell(risk.floor)))
      setColor(row.priceNote, Theme.color.red)
    elseif unit then
      -- Whose price, and over how many -- the number the dock's POST lists, not the one in the
      -- bags.
      local whose = chosen and GC.L["yours"] or GC.L["GoldCap's"]
      row.priceNote:SetText(("%s · ×%d"):format(whose, (postQuantity(p))))
      setColor(row.priceNote, Theme.color.fgDim)
    else
      row.priceNote:SetText(GC.L["no live price yet"])
      setColor(row.priceNote, Theme.color.fgDim)
    end
    row.priceNote:Show()
    -- UNDERCUT is a rung BELOW the cheapest competing ask, one step of the auction house's own
    -- grid (GC.Flips.PriceStep() -- 1 copper where the client takes copper, a silver
    -- otherwise), and a step under an ask of a step or less is zero or negative. Zero is
    -- truthy in Lua, so the chip enabled itself, stored a price of 0 as the seller's choice,
    -- and effectivePostUnit then refused it -- which emptied the box the player had just
    -- filled. Nothing here may offer a price that is not a price.
    local step = GC.Flips.PriceStep()
    local competing = book and exact(book.cheapestCompeting) and book.cheapestCompeting > 0
      and book.cheapestCompeting or nil
    local sources = {
      match = competing,
      under = competing and competing > step and (competing - step) or nil,
      market = exact(p.marketValue) and p.marketValue > 0 and p.marketValue or nil,
      cost = exact(risk.paidUnit) and risk.paidUnit > 0 and risk.paidUnit or nil,
    }
    local key = overrideKey(p)
    local typed = key and S.priceOverrides[key] or nil
    for slot, chip in ipairs(row.priceChips) do
      local id = PRICE_CHIP_IDS[slot]
      local source = sources[id]
      chip:SetLabel(GC.L[PRICE_CHIP_LABELS[slot]])
      chip.priceSource, chip.handsBack = source, id == "goldcap"
      -- The chip the price on screen came from is lit, so the row of five reads as a switch
      -- with a position rather than as five buttons: GOLDCAP while the price is GoldCap's,
      -- another while the seller's own price is exactly that chip's. SetVariant BEFORE
      -- Enable/Disable -- it restores full-brightness text, which would undo a Disable's dim.
      local lit = (chip.handsBack and not chosen) or (source ~= nil and typed == source)
      if chip.SetVariant then chip:SetVariant(lit and "active" or "ghost") end
      if source or chip.handsBack then chip:Enable() else chip:Disable() end
      -- A segment of the strip behind it, not a pill of its own: only the one in force keeps
      -- a fill. After Enable/Disable on purpose -- the kit repaints the fill on both.
      if chip.bg and not lit then chip.bg:SetVertexColor(1, 1, 1, 0) end
      if chip.ring then chip.ring:Hide() end
      chip:Show()
    end
  else
    -- Nothing in the bags: there is no price to set. Say why instead.
    row.priceFigure:Hide(); row.chipsBg:Hide()
    for _, chip in ipairs(row.priceChips) do chip:Hide() end
    row.priceNote:SetText(GC.L["nothing in your bags to price"])
    setColor(row.priceNote, Theme.color.fgDim)
    row.priceNote:Show()
  end

  UI.Book.Paint(row, p, d)

  -- What GoldCap would do and at what price -- the text the expansion's own detail row
  -- used to put in the status CELL, which the deck's shed order now takes off the row at
  -- the default window width.
  -- The sentence and its reason together ("Post @ 18g15s -- above the cheapest, within the
  -- day's reach..."): the reason used to trail the line of market facts under the book, a
  -- screen away from the price it explains.
  -- Only what nothing else on the panel already says. With stock to price, "Post @ 2g85s" is
  -- the box and the button, and "below cost" is the red line under the box -- repeated here
  -- they pushed the one new thing, WHY the price is what it is, off the end of the second line
  -- ("...27875 u..."). So a postable head carries the reason alone, and nothing at all when
  -- there is none; a head with no price control (a live lot) keeps the advice sentence, which
  -- is the only place "Hold (loss)" is ever said.
  local advice
  if postable then
    advice = d and d.factsText or ""
  else
    advice = GC.Sell._RecommendationText(d and d.recommendation)
    -- The verdict in the verdict's colour: green to hold, red to cancel and relist. It is the
    -- one word this panel is opened for, and it used to sit in the same grey as its reasons.
    local action = d and type(d.recommendation) == "table" and d.recommendation.action
    local tone = (action == "hold" and Theme.color.green) or (action == "repost" and Theme.color.red) or nil
    if tone then advice = (advice:gsub("^(%a+)", function(word) return GC.Sell._InlineColor(tone, word) end, 1)) end
    if d and d.factsText then advice = (advice ~= "" and (advice .. " · ") or "") .. d.factsText end
  end
  row.subItem:SetText(advice)
  setColor(row.subItem, Theme.color.fgMuted)
  row.subItem:Show()
  for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
  -- Nothing to press in the head: the item posts from the dock.
  row.action:Hide()
end

-- The panel's other lines: a heading (YOUR LOTS, ON THE AUCTION HOUSE, WHAT YOU PAID), a live lot
-- with its own Cancel lot, and the bag line. A purchase line is UI.CostDialog.PaintBatch.
function Inspector.PaintPanelRow(row, entry, bagSnapshot)
  local p = entry.position
  if entry.kind == "group" then
    -- The hint rides IN the heading, not in the status cell. That cell is the first thing
    -- a narrow window sheds, and the book's own hint -- the cheapest ask that is not yours
    -- -- is the single most useful line in the section: losing it exactly when the window
    -- is too small to show much else is backwards.
    -- On hover, not in the heading: at the panel's width "Sales are costed from your oldest
    -- units first" ran off the edge after its sixth word.
    row.sectionLabel:SetText(entry.title)
    row.groupHint = entry.hint
    row.sectionHint:SetText(entry.aside or "")
    row.sectionHint:Show()
    for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
    row.action:Hide()
  elseif entry.kind == "lot" then
    local total = safeMultiply(entry.lot.unitPrice, entry.lot.quantity)
    -- The auction ID is the addon's handle for cancelling the right lot; it means nothing to
    -- a player, so it moves to the tooltip and the row says what is actually listed.
    setColor(row.subItem, Theme.color.fg) -- see the batch branch: pooled rows keep colour
    row.subItem:SetText((GC.L["×%d listed at %s each"]):format(
      entry.lot.quantity, formatCell(entry.lot.unitPrice)))
    row.cells.listed:SetText(formatCell(total))
    -- Repost only cancels this lot -- Core/SellPositions.lua's BuildRepostPlan prices that
    -- cancel at exactly the fresh quote, and nothing here ever posts at anything else. The
    -- actual relist happens later, once the units are back in the bags, through the
    -- ordinary Post path (BuildPostPlan), which DOES apply the queue/overcut/floor raise --
    -- so this cell shows that as a DISPLAY of what the units will be posted at once they
    -- are back on hand, not a number Repost itself uses. `queue` never reaches a listed
    -- lot's own recommendation (RepostAdvice never passes it a targetUnit), so only
    -- overcut/floor are worth predicting here.
    if p.displayMarketUnit and p.freshMarketUnit then
      local rec = type(p.recommendation) == "table" and p.recommendation.rec or nil
      local repostUnit = p.displayMarketUnit
      if type(rec) == "table" and (rec.mode == "overcut" or rec.mode == "floor")
          and type(rec.unit) == "number" and rec.unit > repostUnit then
        repostUnit = rec.unit
      end
      -- "→", which this cell can draw: it is a T.Num, so T.FONT_UI -- the bundled face, or on
      -- Korean and Chinese the client's face for the script, all of which have U+2192. The
      -- "»" it wore after a Label-era tofu (that cell drew in FRIZQT__, which has no arrow)
      -- is the glyph the Chinese faces lack.
      row.cells.market:SetText("→ " .. formatCell(repostUnit))
      setColor(row.cells.market, Theme.color.gold)
    else
      row.cells.market:SetText(GC.L["→ needs price"])
      setColor(row.cells.market, Theme.color.fgDim)
    end
    row.cells.profit:SetText("")
    row.cells.status:SetText(GC.Sell._RecommendationText(p.recommendation))
    setColor(row.cells.status, Theme.color.fg)
    UI.Row.ShowRowAction(row, "Cancel lot", function()
      UI.Dock.OnRepostClick(row, entry.lot.auctionID)
      Post.CancelSent()
    end)
  else
    -- "In your bags" used to be inferred as tracked minus listed, which is an accounting
    -- leftover, not a measurement: whenever GoldCap had not seen one of the player's own
    -- auctions, the difference was announced as sitting in their bags when it was in fact on
    -- the Auction House. The real bag count is available -- it already gates the Post button
    -- below -- so state it, and when the two disagree say what is unaccounted for instead of
    -- picking one and presenting it as fact.
    -- Post moved up to the position row, so this line's job is now to say
    -- exactly what one click would list, and how much would be left behind.
    -- A normal item posts from ONE bag stack (PostItem pins a single
    -- ItemLocation), so a split stack cannot all go at once; a commodity
    -- aggregates across the bags and can.
    local inBags = p.bagQty or 0
    local bagState = Bags.LiveState(p, nil, bagSnapshot)
    GC.Sell._CacheBagLocation(p, bagState)
    local postable = bagState and bagState.bag and exact(bagState.exactQty) and bagState.exactQty or 0
    setColor(row.subItem, Theme.color.fg) -- see the batch branch: pooled rows keep colour
    -- With a number typed into HOW MANY, the head says how many Post lists; "the largest stack"
    -- beside it would be a second, different answer.
    local _, _, typed = postQuantity(p)
    if postable > 0 and postable < inBags and not typed then
      row.subItem:SetText((GC.L["×%d in your bags · Post lists %d of them, the largest stack"]):format(
        inBags, postable))
    elseif postable > 0 then
      row.subItem:SetText((GC.L["×%d in your bags, ready to list"]):format(typed and inBags or postable))
    else
      row.subItem:SetText((GC.L["×%d in your bags · no stack GoldCap can identify exactly"]):format(inBags))
    end

    if postable > 0 then
      -- Say what Post will charge before it is clicked -- postRecommendation.unit when
      -- there is one (floor/queue/overcut raises included), not the raw cheapest ask:
      -- BuildPostPlan lists at postRecommendation.unit when it applies, and this cell has
      -- to name the same price or it is exactly the "two different numbers" defect the
      -- floor-raise comment in Core/SellPositions.lua describes.
      local postUnit = type(p.postRecommendation) == "table" and type(p.postRecommendation.unit) == "number"
        and p.postRecommendation.unit > 0 and p.postRecommendation.unit or p.displayMarketUnit
      if postUnit and p.freshMarketUnit then
        row.cells.market:SetText("→ " .. formatCell(postUnit))
        setColor(row.cells.market, Theme.color.gold)
      else
        row.cells.market:SetText(GC.L["→ needs price"])
        setColor(row.cells.market, Theme.color.fgDim)
      end
      row.cells.status:SetText(GC.Sell._RecommendationText(p.recommendation))
      setColor(row.cells.status, Theme.color.fg)
    else
      row.cells.status:SetText("")
      setColor(row.cells.status, Theme.color.fgDim)
    end
    -- Gated on canSetCost alone, not on the coverage label. A position that
    -- is COMPLETE against its tracked purchases can still hold uncosted
    -- stock -- five units bought through GoldCap and two hundred farmed is
    -- the ordinary case -- and the coverage flag would have hidden the
    -- button for exactly those.
    if UI.CostDialog.CanSetCost(p) then
      UI.Row.ShowRowAction(row, GC.L["Set cost"], function() UI.CostDialog.OpenCostDialog(p) end)
    else
      row.action:Hide()
    end
  end
end

-- The price section, put away by whatever kind takes the head's pooled row next (renderRows'
-- put-away).
function Inspector.PutAway(row)
  row.priceFigure:Hide(); row.priceNote:Hide(); row.chipsBg:Hide()
  row.headRules[1]:Hide()
  for _, chip in ipairs(row.priceChips) do chip:Hide() end
end

-- The panel frame and its scrolling content: built once, by Attach.
function Inspector.Build()
  local container = UI.container
  -- The detail panel: what a position opens INTO, beside the list instead of inside it. Opening
  -- a row used to push ten rows of panel, lots and purchases into the list under it, so the
  -- list a seller was working down scrolled away from under the cursor on every click. The
  -- list now stays exactly where it is, and the panel has the height for the whole book.
  --
  -- From INSP.DOCK_MIN up it takes a column of its own and the list narrows to make room;
  -- under that it lies over the list's right side as a sheet (see List.ApplyListGeometry in
  -- UI/Sell/List.lua). Its rows
  -- are the SAME pooled rows renderRows has always made -- re-parented, not rebuilt -- so every
  -- Post, Repost and Remove in it runs the code, and holds the pin, it always has.
  local inspector = CreateFrame("Frame", nil, container)
  inspector:SetPoint("TOPRIGHT", 0, -34)
  inspector:SetPoint("BOTTOMRIGHT", 0, UI.Dock.Height() + 6)
  inspector:SetWidth(INSP.W)
  -- Above the list it may be lying over, and swallowing its own mouse: a click on the panel's
  -- background must not land on whichever row sits behind it.
  inspector:SetFrameLevel((container:GetFrameLevel() or 0) + 20)
  inspector:EnableMouse(true)
  inspector:Hide()
  container.inspector = inspector
  local ipc = Theme.color.panel
  local inspectorFill = Theme.SlicedTexture(inspector, "BACKGROUND", Theme.MEDIA .. "card.png",
    { ipc[1], ipc[2], ipc[3], 1 }, 24)
  inspectorFill:SetAllPoints(inspector)
  local ibc = Theme.color.border
  local inspectorEdge = Theme.SlicedTexture(inspector, "BORDER", Theme.MEDIA .. "ring.png",
    { 1, 1, 1, (ibc[4] or 0.06) * 2 }, 24)
  inspectorEdge:SetAllPoints(inspector)

  inspector.icon = inspector:CreateTexture(nil, "ARTWORK")
  inspector.icon:SetSize(36, 36)
  inspector.icon:SetPoint("TOPLEFT", INSP.PAD + 4, -11)
  -- Guarded for busted: most of this suite's frame doubles hand back textures that were never
  -- taught SetTexCoord, because nothing built at Attach time trimmed an icon before this.
  if inspector.icon.SetTexCoord then inspector.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  -- The name and the stock line wrap, and the head grows to hold them (PaintInspector): a name
  -- cut with "…" is the one thing the panel exists to say (owner's rule).
  inspector.name = Theme.Label(inspector, 15)
  inspector.name:SetJustifyH("LEFT"); inspector.name:SetWordWrap(true)
  inspector.stock = Theme.Num(inspector, 10)
  inspector.stock:SetJustifyH("LEFT"); inspector.stock:SetWordWrap(true)
  setColor(inspector.stock, Theme.color.fgMuted)
  local closeInspector = Theme.Button(inspector, "ghost", "badge")
  closeInspector:SetSize(22, 20)
  closeInspector:SetPoint("TOPRIGHT", -INSP.PAD - 2, -18)
  closeInspector:SetLabel("X")
  closeInspector:SetScript("OnClick", function()
    Post.WalkAway()
    for key in pairs(UI.expanded) do
      UI.expanded[key] = nil
      -- Shut, the item leaves the dock as it does when its row is clicked again (UI/Sell/Row.lua).
      if S.dockKey == key then S.dockKey = nil end
    end
    UI.List.RenderRows()
  end)
  inspector.close = closeInspector
  local headRule = inspector:CreateTexture(nil, "ARTWORK")
  headRule:SetColorTexture(ibc[1], ibc[2], ibc[3], ibc[4] or 0.06)
  headRule:SetHeight(1)
  inspector.headRule = headRule

  local detailScroll = CreateFrame("ScrollFrame", nil, inspector, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(detailScroll) end -- no Blizzard arrows beside a kit panel
  inspector.detailScroll = detailScroll
  Inspector.PlaceHead(INSP.HEAD_H)
  UI.detailContent = CreateFrame("Frame", nil, detailScroll)
  UI.detailContent:SetSize(INSP.W - 4 - INSP.SCROLL_GUTTER, UI.rowHeight)
  detailScroll:SetScrollChild(UI.detailContent)
end

-- The rule under the panel's head and the scrolling body below it, `height` down from the top.
function Inspector.PlaceHead(height)
  local inspector = UI.container and UI.container.inspector
  if not (inspector and inspector.headRule) or inspector.headHeight == height then return end
  inspector.headHeight = height
  inspector.headRule:ClearAllPoints()
  inspector.headRule:SetPoint("TOPLEFT", inspector, "TOPLEFT", INSP.PAD, -height + 2)
  inspector.headRule:SetPoint("TOPRIGHT", inspector, "TOPRIGHT", -INSP.PAD, -height + 2)
  inspector.detailScroll:ClearAllPoints()
  inspector.detailScroll:SetPoint("TOPLEFT", inspector, "TOPLEFT", 4, -height)
  inspector.detailScroll:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMRIGHT", -INSP.SCROLL_GUTTER, 6)
end

-- The panel's head: which item this is, and where its stock is. Read off the position at
-- render time -- the panel is one frame reused for every position, like the cost dialog.
function Inspector.PaintInspector(position)
  local inspector = UI.container and UI.container.inspector
  if not inspector then return end
  if not position then inspector:Hide(); return end
  local icon
  if position.itemID and C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, position.itemID)
    icon = ok and texture or nil
  end
  if icon then inspector.icon:SetTexture(icon); inspector.icon:Show() else inspector.icon:Hide() end
  local left = icon and (INSP.PAD + 50) or (INSP.PAD + 4)
  -- Top points only, so a wrapped name pushes its stock line down rather than over it.
  local right = -(INSP.PAD + 2 + 22 + 6) -- clear of the close button
  inspector.name:ClearAllPoints()
  inspector.name:SetPoint("TOPLEFT", left, -12)
  inspector.name:SetPoint("TOPRIGHT", right, -12)
  inspector.stock:ClearAllPoints()
  inspector.stock:SetPoint("TOPLEFT", inspector.name, "BOTTOMLEFT", 0, -4)
  inspector.stock:SetPoint("TOPRIGHT", inspector.name, "BOTTOMRIGHT", 0, -4)
  local name = position.itemName or GC.L["Item"]
  inspector.name:SetText(Theme.WithQuality and Theme.WithQuality(name, position.itemID) or name)
  local parts = {}
  if (position.bagQty or 0) > 0 then parts[#parts + 1] = (GC.L["×%d in bags"]):format(position.bagQty) end
  if (position.listedQty or 0) > 0 then parts[#parts + 1] = (GC.L["×%d listed"]):format(position.listedQty) end
  inspector.stock:SetText(#parts > 0 and table.concat(parts, " · ") or GC.SellViewModel.SourceText(position))
  -- The head as tall as what it says, never shorter than the icon's own room.
  local head = INSP.HEAD_H
  if inspector.name.GetStringHeight then
    head = math.max(head, math.ceil(12 + (inspector.name:GetStringHeight() or 0) + 4
      + (inspector.stock:GetStringHeight() or 0) + 10))
  end
  Inspector.PlaceHead(head)
  inspector:Show()
end
