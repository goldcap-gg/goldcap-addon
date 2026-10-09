-- A row of the Sell list: one pooled frame that can be a position, a heading (a section, the NOT ON
-- HAND fold, the stock waiting for the auction house) or, re-parented into the inspector, one of the
-- panel's lines. Row.CreateRow builds every widget any kind needs (the book by UI.Book.Decorate, the
-- price control by UI.Inspector.Decorate); Row.PaintPosition, Row.PaintHeading and Row.Style paint it
-- for the entry it holds this render. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local Walk, Post = GC.SellWalk, GC.SellPost
local exact, safeMultiply, effectivePostUnit = GC.SellUtil.exact, GC.SellUtil.safeMultiply,
  GC.SellUtil.effectivePostUnit
local UI = GC.SellUI
local Row = UI.Row
local COLUMNS, ROW = UI.COLUMNS, UI.ROW
local setColor, formatCell, DIM_HEX, MONEY_HEX = UI.fmt.setColor, UI.fmt.cell, UI.fmt.DIM_HEX, UI.fmt.MONEY_HEX

-- The one-word state a row wears at the end of its stock line, and only when something is off:
-- a row that is ready says nothing. It replaces the WHAT TO DO column, which no deck had room
-- for at any width, so the reason a row was left out of the queue was one hover away on a
-- counter in the footer and nowhere on the row it was about. Keyed by GC.PostQueue's and
-- GC.CancelQueue's own reason tokens; `alarm` paints red, `wait` the watch blue, the rest dim.
-- @localised-keys
local ROW_TAG_TEXT = {
  no_fresh_price = "no live price",
  unresolved_identity = "stack not identified",
  advised_hold = "hold",
  below_vendor = "vendor pays more",
}

local rowTag
do
-- No tag for below_breakeven: the red margin under YOU GET is that fact, on the same row, and
-- the words were the first thing a narrow list cut to "be...".
local ROW_TAG_TONE = { no_fresh_price = "wait" }

-- The tag itself, already coloured, or "" for a row with nothing to say. `reason` is the skip
-- token the deck's queue gave this position, if it skipped it. Money leaving silently outranks
-- everything: a lot standing far below market is the one thing on the row that has to be read
-- first, and it used to be written into a column no deck shows.
--
-- A function of its own rather than lines inside renderRows for a reason the client enforces
-- and busted does not: WoW runs Lua 5.1, which caps a function at 60 upvalues, and renderRows
-- sits close enough to that cap that three more tables put the whole file out of action.
rowTag = function(position, reason, notOnHand)
  local tag, tone
  if position.facts and position.facts.underpriced then
    tag, tone = GC.L["far below market"], "alarm"
  elseif reason then
    tag, tone = ROW_TAG_TEXT[reason] and GC.L[ROW_TAG_TEXT[reason]] or nil, ROW_TAG_TONE[reason]
  end
  local uncosted = math.max(0, (position.exposureQty or 0) - (position.knownQty or 0))
  if not tag and position.coverage ~= "COMPLETE" and not notOnHand and uncosted > 0 then
    tag = (GC.L["no cost for %d"]):format(uncosted)
  end
  if not tag then return "" end
  local color = tone == "alarm" and Theme.color.red or tone == "wait" and Theme.color.watch
    or Theme.color.fgDim
  return "  " .. GC.Sell._InlineColor(color, tag)
end
end -- do: keeps the helpers above out of the file's own local count (Lua 5.1 allows 200)

-- "400 in 2 lots" on MY LOTS, where how the stock is listed is what the row is about; the
-- posting deck keeps its plain count beside the bags'.
function ROW.listedText(position, listedQty, onListed)
  local lots = #(position.ownedLots or {})
  if not onListed or lots == 0 then return (GC.L["×%d listed"]):format(listedQty) end
  if lots == 1 then return (GC.L["%d in 1 lot"]):format(listedQty) end
  return (GC.L["%d in %d lots"]):format(listedQty, lots)
end

-- Two copies of one piece at two item levels were two identical rows (review M9): a variant's
-- row names its level -- a pet's, its pet level -- from its own key.
function ROW.variantSuffix(position)
  local level = type(position.quoteKey) == "string" and tonumber(position.quoteKey:match("^item:%d+:(%d+):"))
  if position.variantKind == "pet" then
    -- A pet's level is the one its battle-pet link states. What the client's ItemKey carries in
    -- its level field for a caged pet is not confirmed off the client (final review M5).
    local stack = position.bagStacks and position.bagStacks[1]
    local lot = position.ownedLots and position.ownedLots[1]
    local link = stack and stack.link or lot and lot.itemLink
    level = type(link) == "string" and tonumber(link:match("battlepet:%d+:(%d+)")) or nil
  end
  if not level or level <= 0 then return "" end
  local words = position.variantKind == "pet" and (GC.L["level %d"]):format(level) or (GC.L["ilvl %d"]):format(level)
  return "  " .. DIM_HEX .. words .. "|r"
end

-- The first of this position's lots the cancel queue holds, or nil: the queue is the one
-- judge of what is worth cancelling, for the row's button as for the dock's.
function ROW.queuedLot(position)
  for _, entry in ipairs(S.cancelEntries) do
    if entry.positionKey == position.positionKey then return entry end
  end
  return nil
end

-- Keyed by the label the button currently carries. Every one of these either spends gold or
-- destroys a deposit, so none of them should be a word a player has to guess at.
--
-- English here on purpose, and translated where it is READ (actionHelp below). This table
-- is built at file scope, and GC.L only resolves once ApplyLocale has run at ADDON_LOADED
-- -- so GC.L[...] in these entries would capture the English fallback once and stay English
-- in every language. The outer KEYS stay English for a different reason: they are the
-- stable helpKey the buttons carry, which is the defect helpKey was introduced to fix.
-- @localised-keys: literals in this table ARE GC.L keys; see the comment above for why
-- the lookup happens where the table is read rather than where it is built.
local ACTION_HELP = {
  ["Set cost"] = { "Set cost", { "Tell GoldCap what you actually paid for these units.", "It will not invent a cost from the market price, so profit stays unknown until you enter one." } },
  -- Two short paragraphs each, never more (sell_action_help_spec locks the length): the
  -- tooltip opens beside a button inside the list, so every extra line is a row it covers.
  ["Post"] = { "Post", { "Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item.", "The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price." } },
  ["Cancel lot"] = { "Cancel lot", { "Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive.", "Asks for a second click to confirm." } },
  ["Cancel lot?"] = { "Confirm the cancel", { "Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags.", "The button waits a moment before it can be pressed, so this is never an accidental double-click." } },
  ["Remove"] = { "Remove this cost", { "Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail.", "There is no undo. Clicking asks for a second click to confirm." } },
  ["Remove?"] = { "Confirm the removal", { "Clicking again deletes this hand-entered cost for good.", "A run of several purchases collapsed onto one line removes every one of them." } },
}
Row.ACTION_HELP = ACTION_HELP

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(UI.rowHeight)

  -- Sell rows carried no banding, no hover feedback and no rule between them, so a screenful
  -- of positions read as one undifferentiated block -- and an expanded position's children were
  -- distinguishable only by two leading spaces in their text. Same treatment as the Deals list:
  -- BACKGROUND zebra, a highlight above it, a hairline at the bottom edge, and an item icon so
  -- rows are scannable by shape rather than by reading every name.
  -- Sliced rounded fills (batch-2 pattern). Insets: 1px top/bottom so margin 12 <= 15 = half of
  -- the 30px effective fill (Theme.ROW_H 32 minus 2px); right inset is 2, NOT Deals' 26 -- this
  -- container is already inset by CONTENT_RIGHT_GUTTER (see Attach in UI/SellFrame.lua) and the scrollbar hangs
  -- outside in that gutter.
  local zc = Theme.color.zebra
  row.zebra = row:CreateTexture(nil, "BACKGROUND")
  row.zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  row.zebra:SetTextureSliceMargins(12, 12, 12, 12)
  row.zebra:SetPoint("TOPLEFT", 2, -1); row.zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], 0)
  -- The open position's outline, over the same rect as its fill: gold at the design's 38%.
  -- Built through the kit's own sliced texture so a spec's Theme double serves it too.
  row.selectRing = Theme.SlicedTexture(row, "BORDER", Theme.MEDIA .. "plaque_ring.png",
    { Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.38 }, 12)
  row.selectRing:SetPoint("TOPLEFT", 2, -1); row.selectRing:SetPoint("BOTTOMRIGHT", -2, 1)
  row.selectRing:Hide()
  -- The "well": a sunken fill an expanded position's children sit in instead of the list's
  -- alternating zebra, so a sub-row reads as nested inside its position rather than as one more
  -- row in the same flat list (row.spine, below, is the other half of that cue). Same sliced
  -- plaque and insets as the zebra it replaces -- only shown for sub-rows (the kind branch in
  -- Row.Style), never alongside it.
  row.well = row:CreateTexture(nil, "BACKGROUND")
  row.well:SetTexture(Theme.MEDIA .. "plaque.png")
  row.well:SetTextureSliceMargins(12, 12, 12, 12)
  row.well:SetPoint("TOPLEFT", 2, -1); row.well:SetPoint("BOTTOMRIGHT", -2, 1)
  local phc = Theme.color.panelHi
  row.well:SetVertexColor(phc[1], phc[2], phc[3], 0.5)
  row.well:Hide()
  row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  row.highlight:SetTextureSliceMargins(12, 12, 12, 12)
  row.highlight:SetPoint("TOPLEFT", 2, -1); row.highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  local hc = Theme.color.hover
  row.highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight:Hide()
  row.divider = row:CreateTexture(nil, "ARTWORK")
  row.divider:SetHeight(1)
  row.divider:SetPoint("BOTTOMLEFT", 0, 0)
  row.divider:SetPoint("BOTTOMRIGHT", 0, 0)
  local bc = Theme.color.border
  row.divider:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.06)
  -- Child rows (batch/detail/lot) get a gold spine at the left edge instead of a bottom rule,
  -- so an expanded group reads as one bracketed unit rather than as more top-level rows.
  row.spine = row:CreateTexture(nil, "ARTWORK")
  row.spine:SetWidth(2)
  row.spine:SetPoint("TOPLEFT", 0, 0)
  row.spine:SetPoint("BOTTOMLEFT", 0, 0)
  local gc = Theme.color.gold
  row.spine:SetColorTexture(gc[1], gc[2], gc[3], 0.45)
  row.spine:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW.ICON, ROW.ICON)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the stock icon border
  row.icon:Hide()
  row:SetScript("OnEnter", function(self)
    self.goldcapVariant = nil
    -- The list's rows are what a hover picks between; a wash over the panel's twelve-slot
    -- head, or over a heading inside it, points at nothing.
    if not self.inPanel then self.highlight:Show() end
    -- Rows are pooled and rebound every render, so the item tooltip is wired once here and
    -- reads whatever position the row currently holds. Hooking it per render would stack.
    if GameTooltip and self.kind == "position" and self.position and self.position.itemID then
      -- Outside the window, never over it -- a row's own item tooltip used to cover the deck
      -- it is describing (Theme.ItemTooltipOutside; see UI/Theme.lua's own comment on it).
      Theme.ItemTooltipOutside(self, UI.window)
      -- A variant is the stack itself -- its item level, its bonuses, its pet -- not the base item
      -- (for every caged pet, "Pet Cage"): the bag slot, else the lot's own link (review M9).
      -- GoldCap's own block under this tooltip (UI/Tooltip.lua) reads the site's figure for the
      -- item -- every item level at once, every pet at once. Under a variant row it says there is
      -- none for this one instead (review N7), reading which variant off the tooltip's owner --
      -- this row -- so it can never outlive the row onto some other item's tooltip (NI-B).
      self.goldcapVariant = self.position.variantKind
      local stack = self.position.quoteKey and self.position.bagStacks and self.position.bagStacks[1]
      local lot = self.position.quoteKey and self.position.ownedLots and self.position.ownedLots[1]
      if stack and GameTooltip.SetBagItem then GameTooltip:SetBagItem(stack.bag, stack.slot)
      elseif lot and lot.itemLink and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(lot.itemLink)
      elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.position.itemID) end
      -- Flags painted onto the row at the same time as the cells they describe (MARKET/UNIT's
      -- fallback, the item cell's "· not on hand" suffix) -- read here rather than re-derived,
      -- so the tooltip can never disagree with what the row is actually showing.
      if self.marketFallback then
        GameTooltip:AddLine(GC.Util.ClientText(GC.L["~ goldcap.gg market value — no live quote yet"]), 0.85, 0.85, 0.85, true)
      end
      if self.notOnHand then
        GameTooltip:AddLine(GC.Util.ClientText(GC.L["Not on hand — the stock is in the mail, the bank, or on another character"]),
          0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    elseif GameTooltip and (self.kind == "group" or self.kind == "batch")
        and self.groupHint and self.groupHint ~= "" then
      GameTooltip:SetOwner(self, Theme.TooltipAnchor(self))
      -- A fact a line. The sentence is a run of facts joined by one separator, and wrapped as
      -- a paragraph it broke mid-fact ("bought 29 / Aug"), which is harder to read than the row.
      local first = true
      for fact in (self.groupHint .. " · "):gmatch("(.-) · ") do
        local factLine = GC.Util.ClientText(fact)
        if first then GameTooltip:AddLine(factLine, 1, 1, 1) else GameTooltip:AddLine(factLine, 0.85, 0.85, 0.85) end
        first = false
      end
      GameTooltip:Show()
    end
  end)
  -- Belt and braces: a row hidden under a stationary cursor (Escape, the auction house closing,
  -- a re-render) never gets its OnLeave.
  row:SetScript("OnHide", function(self) self.goldcapVariant = nil end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    self.goldcapVariant = nil
    -- GameTooltip_Hide closes Blizzard's battle-pet card too, which a caged pet's bag slot or
    -- link may open beside GameTooltip (review N5).
    if _G.GameTooltip_Hide then _G.GameTooltip_Hide()
    elseif GameTooltip then GameTooltip:Hide() end
  end)

  row.cells = {}
  for _, column in ipairs(COLUMNS) do
    -- Figures in the mono face, names and prose in the client's own -- the kit's rule (see
    -- Theme.Label). Every cell here used to be a Label, so the two columns a seller compares
    -- down the list were set in a face whose digits do not line up.
    local cell = column.num and Theme.Num(row, 11, column.bold) or Theme.Label(row, column.key == "item" and 12 or 11)
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    cell:SetWordWrap(false)
    row.cells[column.key] = cell
  end
  row.cells.item:SetJustifyH("LEFT")
  -- The stock line ("×246 in bags · ×11 listed") used to ride in cells.item as a second line
  -- behind a "\n". cells.item is SetWordWrap(false) like every other cell, which renders ONE
  -- line and marks the rest with an ellipsis -- so the second line was never drawn at all and
  -- every item on the screen appeared truncated, whatever its name. Its own FontString, its
  -- own anchor (UI.List.LayoutCells splits the flex box in half vertically for the pair).
  row.itemStock = Theme.Num(row, 10)
  -- Said out loud rather than inherited from the font template: this line is deliberately one
  -- step back from the item name above it, so that the money coloured into it (MONEY_HEX) is
  -- the thing that steps forward. Leaving it on the template's own colour made the whole line
  -- compete with the name and the cost compete with nothing.
  row.itemStock:SetTextColor(Theme.color.fgMuted[1], Theme.color.fgMuted[2], Theme.color.fgMuted[3])
  row.itemStock:SetJustifyH("LEFT")
  row.itemStock:SetWordWrap(false)
  row.itemStock:Hide()

  -- The second line of the two figures, the same split the name and its stock line already
  -- make. Under the price: where that price stands in the live book -- five marks, one per
  -- price level from the cheapest, the one this price lands on lit -- and the stock queued
  -- under it in words. Under YOU GET: the margin, which used to be a column of its own a row's
  -- width away from the figure it qualifies. Both answer before anything is opened.
  row.priceStand = Theme.Num(row, 10)
  row.priceStand:SetJustifyH("RIGHT")
  row.priceStand:SetWordWrap(false)
  row.priceStand:Hide()
  row.standMarks = {}
  for i = 1, ROW.MARKS do
    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetSize(3, 8)
    mark:Hide()
    row.standMarks[i] = mark
  end
  -- 11, the size of the figure above it: at 9 the one number that says whether the row makes
  -- or loses money was the smallest thing on it.
  row.grossNote = Theme.Num(row, 11)
  row.grossNote:SetJustifyH("RIGHT")
  row.grossNote:SetWordWrap(false)
  row.grossNote:Hide()

  UI.Book.Decorate(row)

  UI.Inspector.Decorate(row)
  -- Sub-rows (detail/batch/lot/listing) write into their own widget, one size down from a
  -- position's name (11, not 12) -- the flex column's box is shared by three mutually
  -- exclusive widgets (this, row.cells.item, row.sectionLabel below), and UI.List.LayoutCells anchors
  -- all three to the same LEFT/RIGHT points every render since exactly one is shown per row
  -- (the kind branch in Row.Style).
  row.subItem = Theme.Num(row, 10)
  row.subItem:SetJustifyH("LEFT")
  row.subItem:SetWordWrap(false)
  row.subItem:Hide()
  -- Group headings (Sold's own pattern, UI/SoldFrame.lua's row.sectionLabel/row.sectionRule):
  -- a mono micro-label plus a hairline rule running to the row's right edge, instead of a
  -- gold line sharing the item cell's own font -- gold and uppercase are the group's whole
  -- visual language, so nothing about the flex column's shared styling has to bend for it.
  row.sectionLabel = Theme.Num(row, 9, true)
  row.sectionLabel:SetJustifyH("LEFT")
  setColor(row.sectionLabel, Theme.color.gold)
  row.sectionLabel:Hide()
  -- A heading's aside, at the right end of its row ("oldest units sell first").
  row.sectionHint = Theme.Num(row, 9)
  row.sectionHint:SetJustifyH("RIGHT")
  row.sectionHint:SetWordWrap(false)
  setColor(row.sectionHint, Theme.color.fgDim)
  row.sectionHint:Hide()
  local gc2 = Theme.color.gold
  row.sectionRule = row:CreateTexture(nil, "ARTWORK")
  row.sectionRule:SetColorTexture(gc2[1], gc2[2], gc2[3], 0.25)
  row.sectionRule:SetHeight(1)
  row.sectionRule:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.s, 0)
  row.sectionRule:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
  row.sectionRule:Hide()
  row.action = Theme.Button(row, "ghost", "badge")
  -- 86, not 84: "Cancel lot?" is 85.8px at mono-10 and Theme.Scale() 1.3 (JetBrains Mono
  -- ~0.6em/char -> 7.8px/char); 86 is the largest width that still leaves >=2px clearance
  -- from the neighbouring cells inside the 88px `action` column (UI.List.LayoutCells packs cells with
  -- an explicit 2px gap between them, so an inset button never touches the gap).
  row.action:SetSize(86, 18)
  -- Its own column. Anchored over `status` it covered the recommendation text, which is where
  -- the price and the breakeven are written.
  row.action:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  row.action:Hide()
  -- Wired once on the pooled button; the text is chosen at hover time from the label it
  -- currently carries, so it always describes the action actually on offer.
  if row.action.HookScript then
    row.action:HookScript("OnEnter", function(self)
      if not GameTooltip then return end
      -- helpKey is the English action name the row set; self.label is display text and may be
      -- in any language. Fall back to the label for buttons that predate the key.
      local help = ACTION_HELP[self.helpKey or ""]
        or ACTION_HELP[self.label]
        or ACTION_HELP[(self.label or ""):gsub("%s*%(.*", "")]
      if not help then return end
      -- Not ANCHOR_RIGHT: this button sits in the far-right column of a window that can fill
      -- the screen, and a tooltip told to grow rightward from there gets clamped back over the
      -- list, the header and the button itself. Theme reads where the button is and opens the
      -- tooltip on the side that has room.
      GameTooltip:SetOwner(self, Theme.TooltipAnchor(self))
      -- Translated at READ time -- see ACTION_HELP's own comment for why the table itself
      -- cannot hold GC.L lookups.
      GameTooltip:AddLine(GC.Util.ClientText(GC.L[help[1]]), 1, 0.82, 0)
      for _, line in ipairs(help[2]) do
        GameTooltip:AddLine(GC.Util.ClientText(GC.L[line]), 0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    end)
    row.action:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  row:SetScript("OnClick", function(self)
    if self.kind == "fold" then
      UI.showNotOnHand = not UI.showNotOnHand
      UI.List.RenderRows()
    elseif self.kind == "position" and type(self.position.positionKey) == "string" then
      Post.WalkAway() -- an armed post or cancel is a question; this click answers it "no"
      -- One open position at a time. Two open panels are two hundred pixels of detail each,
      -- and the second one pushed the first -- the one being compared against -- off screen.
      local key = self.position.positionKey
      local wasOpen = UI.expanded[key]
      for other in pairs(UI.expanded) do UI.expanded[other] = nil end
      UI.expanded[key] = not wasOpen or nil
      UI.List.RenderRows()
    end
  end)
  return row
end
Row.CreateRow = createRow

-- `key` is the ENGLISH action name, not display text. ACTION_HELP is keyed by it, so once the
-- interface is translated a lookup by the visible label would miss every time and silently
-- drop the help from exactly the buttons that spend gold. The key is remembered on the button;
-- the label is only what the player reads.
local function showRowAction(row, key, onClick)
  -- Deliberately does NOT clear `status` any more: that cell holds the recommendation -- what
  -- to do, at what unit price, and the breakeven under it -- and blanking it was the reason a
  -- player could never tell what a Post or Repost was about to charge.
  row.action.helpKey = key
  row.action:SetLabel(GC.L[key])
  if onClick then row.action:SetScript("OnClick", onClick) end
  row.action:Show()
end
UI.Row.ShowRowAction = showRowAction
Row.ShowRowAction = showRowAction

-- A position in the list: its name and stock line, the deck's figures and their second lines, and
-- the row's own button. `ctx` carries what the render works out once for all rows: `onListed`
-- (the deck on screen is MY LOTS) and `heldBackReason` (why a position is not in the bulk action,
-- by position key).
function Row.PaintPosition(row, entry, ctx)
  local p = entry.position
  local onListed, heldBackReason = ctx.onListed, ctx.heldBackReason
  -- Second line answers "how many of these do I have, and where are they" -- the question
  -- a seller actually asks. Where each unit came from stays available on the tooltip.
  -- The bag count is now measured, not inferred. It used to be tracked
  -- minus listed -- an accounting leftover that announced stock as "in
  -- your bags" whenever GoldCap had not seen one of the player's own
  -- auctions, and that showed nothing at all for anything GoldCap never
  -- bought, which was most of what a seller actually has to sell.
  local listedQty, bagQty = p.listedQty or 0, p.bagQty or 0
  local stockParts = {}
  if bagQty > 0 then stockParts[#stockParts + 1] = (GC.L["×%d in bags"]):format(bagQty) end
  if listedQty > 0 then stockParts[#stockParts + 1] = ROW.listedText(p, listedQty, onListed) end
  -- What one of these cost, on the line under the name. COST / UNIT was its own column
  -- until this deck's column set replaced it; the fact is too load-bearing to lose with
  -- the column, and it reads better beside the quantity it applies to anyway.
  local paidUnit = nil
  if p.coverage == "COMPLETE" and exact(p.knownCost) and exact(p.knownQty) and p.knownQty > 0 then
    paidUnit = math.floor(p.knownCost / p.knownQty)
    -- Escaped around the AMOUNT, not around the whole phrase: a translation is free to
    -- put the money anywhere in its own sentence, and only the money should light up.
    stockParts[#stockParts + 1] =
      (GC.L["paid %s each"]):format(MONEY_HEX .. formatCell(paidUnit) .. "|r")
  end
  -- The quality pip goes in the label rather than beside it: this row and
  -- the Sniper's deal row anchor their cells completely differently, and an
  -- inline atlas escape needs no layout in either. Empty for the vast
  -- majority of items, which have no quality tier at all.
  local named = Theme.WithQuality and Theme.WithQuality(p.itemName or "Item", p.itemID)
    or (p.itemName or "Item")
  -- Nothing in the bags and nothing listed means the stock this row tracks is real cost
  -- history sitting somewhere else -- the mail, the bank, another character -- not a
  -- position that vanished. The dim "· not on hand" suffix goes AFTER the qty suffix (or
  -- its SourceText fallback, when there is no qty to show), same idiom as SniperFrame's
  -- "· watching" suffix in setRowDeal, and its own color code so it never inherits
  -- whatever color the line before it painted.
  --
  -- Deliberately not queued into the pricing walk: Walk.Queue (Services/Sell/Walk.lua) only picks
  -- up a position with `inBags or listed`, so this row keeps whatever quote it already
  -- has (or none) and stays ranked last -- there is nothing actionable to price a quote
  -- for, and spending one of the walk's throttled requests on it would starve a row a
  -- player can actually act on right now.
  -- I2 (fix wave, sell honesty): an unresolved position (unassigned_acquisition/
  -- pending_purchase/paid_sale/ambiguous_sale, see Core/SellPositions.lua ~:579-616) has
  -- no batch or lot backing it at all -- there is no stock to be "elsewhere", so the
  -- mail/bank/alt claim below would be a fabrication about a position that is really
  -- "GoldCap doesn't know what this is yet". Mirrors the STATUS branch's own
  -- `not p.unresolved` guard further down.
  local notOnHand = not p.unresolved and (p.bagQty or 0) == 0 and (p.listedQty or 0) == 0
  row.notOnHand = notOnHand
  row.cells.item:SetText(named .. ROW.variantSuffix(p))
  -- What is off about this row, if anything -- see rowTag.
  row.itemStock:SetText((#stockParts > 0 and table.concat(stockParts, " · ")
    or GC.SellViewModel.SourceText(p))
    .. (notOnHand and (DIM_HEX .. " · not on hand|r") or "")
    .. rowTag(p, heldBackReason[p.positionKey], notOnHand))
  -- Cost per unit, not the position total: it is the number that compares against the
  -- market price in the very next column. An incomplete basis says so in words below.
  local unitCost = nil
  if p.coverage == "COMPLETE" and exact(p.knownCost) and exact(p.knownQty) and p.knownQty > 0 then
    unitCost = math.floor(p.knownCost / p.knownQty)
  end
  row.cells.cost:SetText(unitCost and formatCell(unitCost) or "—")
  row.cells.listed:SetText(formatCell(p.listedValue))
  -- "none" ~= "—": the first is an answer ("the AH has zero listings right now",
  -- remembered in emptyAnswers), the second is the absence of one. Conflating them made
  -- honestly-unlisted items read as the pricing walk being slow or stuck.
  --
  -- Below both of those sits a third case: no live quote yet AT ALL (not even a stale
  -- one), but the item was imported from goldcap.gg with a market value -- the same
  -- number Deals shows. That value is not live, so it never overrides an actual AH
  -- answer (an empty one included -- the AH answered "none", which outranks a guess from
  -- the last import), but showing it beats a "—" that reads as "the addon hasn't checked
  -- yet" for as long as the pricing walk takes to reach this row.
  -- Item 5 (addon polish batch): a bare `emptyAnswers[p.itemID]` presence check made a
  -- ONE-OFF empty AH answer hide the fallback forever -- only a manual Refresh (which
  -- wipes emptyAnswers outright) brought it back. Age-gate it the same way
  -- Walk.Queue already does for re-query eligibility, so a stale empty answer
  -- lets the fallback show again instead of only a fresh one suppressing it. While the
  -- walk is actively re-querying THIS exact item (refresh.pending, the walk's one
  -- in-flight slot), keep "none" rather than flicker the fallback in for the few seconds
  -- until the real (still probably empty) answer lands.
  --
  -- Fix wave: a request that never came back was recorded in emptyAnswers exactly like a
  -- reply that carried no listings, so an item the auction house had said nothing about
  -- at all rendered as "none" here and "Nothing listed on the AH right now" in STATUS.
  -- Only an ANSWER may drive that text now (emptyAnswers' own comment); silence falls
  -- back to the dash and "Waiting for a live price", which is what it is. The re-query
  -- guard keeps its job -- holding the last KNOWN-EMPTY answer on screen while the walk
  -- re-asks -- but it cannot invent one for an item that has never answered.
  -- By quote id: an item-level variant's answers are its own (GC.Sell._QuoteItemKey).
  local quoteID = p.quoteKey or p.itemID
  local answeredEmpty = Walk.RestedEmptyFresh(quoteID, time())
  local requeryingThis = S.refresh.pending and S.refresh.pending.itemID == quoteID
  local rest = S.emptyAnswers[quoteID]
  local emptyKnown = answeredEmpty
    or (requeryingThis and type(rest) == "table" and rest.answered == true) or false
  local marketFallback = p.displayMarketUnit == nil and type(p.marketValue) == "number"
    and p.marketValue > 0 and not emptyKnown
  row.marketFallback = marketFallback
  local marketText
  if p.displayMarketUnit then
    marketText = formatCell(p.displayMarketUnit)
  elseif marketFallback then
    -- "~", not "≈": on Korean this cell draws in the client's 2002.TTF, which has no U+2248.
    marketText = "~" .. formatCell(p.marketValue)
  else
    marketText = emptyKnown and "none" or "—"
  end
  if p.displayMarketUnit and not p.freshMarketUnit and type(p.quoteAge) == "number" then
    marketText = marketText .. (GC.L[" · stale %ds"]):format(p.quoteAge)
  end
  row.cells.market:SetText(marketText)
  setColor(row.cells.market, (marketFallback or (p.displayMarketUnit and not p.freshMarketUnit))
    and Theme.color.fgDim or Theme.color.fg)
  -- Per unit, to match the two columns it is compared against. The view model reports the
  -- position total; showing that under a "/ UNIT" heading turned a loss of under a gold
  -- per unit into a headline "-128g".
  local profit = GC.SellViewModel.ProfitText(p)
  if type(profit) == "number" and exact(p.knownQty) and p.knownQty > 0 then
    local perUnit = profit / p.knownQty
    profit = perUnit >= 0 and math.floor(perUnit) or -math.floor(-perUnit)
  end
  -- position.profitAtHold names the case where this number was computed at
  -- postRecommendation.unit and that unit sat ABOVE the fresh live quote (PostFloor, or
  -- the queue-at-exit rule, holding the recommendation above what a seller could actually
  -- get selling into today's book right now). The number itself stays the recommendation
  -- -- it IS the price GoldCap would post at -- but green would claim it as ordinary
  -- market profit when it is really a bet on the hold, so it renders in the same gold the
  -- MARKET/UNIT column already uses for a computed forward price (see the "→ <price>"
  -- cells below), with the price it assumes named in the cell rather than left implicit.
  -- A hold that is STILL a loss is not softened by the gold tone -- red outranks it.
  --
  -- setColor runs in BOTH branches, never just the hold one: rows are pooled and rebound
  -- to a new position on every render (renderRows reuses `rows[i]` rather than creating a
  -- fresh cell each time -- see createRow's own call site), so a row painted gold or red
  -- here on one render and left uncolored on the next would carry that tint into whatever
  -- unrelated number lands in the same slot afterward. Same failure class the addon's engineering notes
  -- already documents for hover fills painted in OnEnter and never cleared in OnLeave.
  if type(profit) == "number" and exact(p.profitAtHold) then
    -- Whole gold only: "@ 18g15s" was precisely the tail the column cut
    -- off in game. The exact figure is the Post price, one column over.
    -- GC.Util.IntText, not %d: WoW's own string.format raises "integer overflow
    -- attempting to store N" past +-2^31 copper (about 214,748g).
    local hold = p.profitAtHold >= 10000
      and GC.Util.IntText(math.floor(p.profitAtHold / 10000)) .. "g"
      or formatCell(p.profitAtHold)
    row.cells.profit:SetText(("%s %s@%s|r"):format(
      formatCell(profit), DIM_HEX, hold))
    setColor(row.cells.profit, profit < 0 and Theme.color.red or Theme.color.gold)
  else
    row.cells.profit:SetText(formatCell(profit))
    -- Minor (fix wave, sell honesty): "Unknown" beside a dim "~" market used to render in
    -- the row's ordinary fg -- a confident-looking pair next to an admittedly approximate
    -- number. Dim whenever there is no real number here; the gold/red hold-price branch
    -- above (a real number either way) is untouched.
    setColor(row.cells.profit, type(profit) == "number" and Theme.color.fg or Theme.color.fgDim)
  end
  -- "Unknown" (profit) sitting beside "UNLISTED" (status) read as one meaningless phrase.
  -- This column now says what to do about it, in a sentence, or names what is missing.
  local knownQty, exposureQty = p.knownQty or 0, p.exposureQty or 0
  if p.facts and p.facts.underpriced then
    -- Money leaving, silently. A listing posted against a thin cheap lot
    -- looks ordinary until that lot clears and the book springs back --
    -- which is how five Arcane Crystals bought at 70g ended up on sale at
    -- 18g against a 92g market. This is the one thing on the row that has
    -- to be read before anything else, so it takes the column and the
    -- alarm colour, and the advice moves aside for it.
    row.cells.status:SetText((GC.L["Listed at %s — far below market. Repost."]):format(
      formatCell(p.underpricedUnit)))
    setColor(row.cells.status, Theme.color.red)
  elseif p.recommendation then
    row.cells.status:SetText(GC.Sell._RecommendationText(p.recommendation))
    setColor(row.cells.status, Theme.color.fg)
  elseif bagQty > 0 then
    -- The advice column is not the place to report bookkeeping when the
    -- player is holding sellable stock: say what is missing to price it.
    -- "Waiting" when the answer already arrived and was "nothing on sale"
    -- is a lie that reads as the addon being slow -- name the real state.
    -- MINOR-1 (fix round 1): reuses the same age-gated `emptyKnown` the MARKET column
    -- decides its fallback from, above -- a bare `emptyAnswers[p.itemID]` here disagreed
    -- with MARKET once the answer went stale (MARKET said "~…", STATUS still said
    -- "Nothing listed").
    if p.displayMarketUnit == nil and emptyKnown then
      row.cells.status:SetText(GC.L["Nothing listed on the AH right now"])
    else
      row.cells.status:SetText(GC.L["Waiting for a live price"])
    end
    setColor(row.cells.status, Theme.color.fgDim)
  elseif not p.unresolved and (p.listedQty or 0) == 0 then
    -- Nothing in the bags AND nothing listed: the stock this row tracks is in the
    -- mail, the bank, or on another character. Cost coverage is a real question too,
    -- but "where is my ore?" is the one the player is actually asking here.
    row.cells.status:SetText(GC.L["Not in your bags or listed — mail or bank?"])
    setColor(row.cells.status, Theme.color.fgDim)
  elseif p.coverage ~= "COMPLETE" then
    row.cells.status:SetText((GC.L["Cost unknown for %d of %d"]):format(
      math.max(0, exposureQty - knownQty), exposureQty))
    setColor(row.cells.status, Theme.color.fgDim)
  else
    row.cells.status:SetText("")
    setColor(row.cells.status, Theme.color.fg)
  end
  -- The deck's own three figures. Written for BOTH decks and shown per DECK_COLUMNS, so
  -- a cell never carries a number belonging to the deck the player is not looking at.
  local onListedDeck = S.filterMode == "listed" or S.filterMode == "cancelqueue"
  local rowUnit
  if onListedDeck and listedQty > 0 and exact(p.listedValue) then
    -- The average a live lot is actually standing at, which is what "your price" means
    -- once it is posted -- not what Post would choose for the stock still in the bags.
    rowUnit = math.floor(p.listedValue / listedQty)
  else
    rowUnit = effectivePostUnit(p)
  end
  -- YOU GET answers "what does this row fetch if I click Post", so on the post deck it is
  -- counted over what one click LISTS -- the largest stack for a normal item, the whole
  -- pool for a commodity (position.postableQty, see Core/SellPositions). Counting the bag
  -- sum quoted a figure four fifths of which stayed in the bags.
  local postableQty = exact(p.postableQty) and p.postableQty > 0 and p.postableQty or bagQty
  local grossQty = onListedDeck and listedQty or postableQty
  local gross = rowUnit and safeMultiply(rowUnit, grossQty) or nil
  row.cells.gross:SetText(gross and formatCell(gross) or "—")
  setColor(row.cells.gross, gross and Theme.color.fg or Theme.color.fgDim)
  row.cells.price:SetText(rowUnit and formatCell(rowUnit) or "—")
  -- A lot the cancel queue calls urgent is priced far under the market: that figure is
  -- the problem, and it is the one on this row that goes red.
  local queuedLot = onListed and ROW.queuedLot(p) or nil
  setColor(row.cells.price, (queuedLot and queuedLot.urgent and Theme.color.red)
    or (rowUnit and Theme.color.fg) or Theme.color.fgDim)
  if rowUnit and paidUnit and paidUnit > 0 then
    local pct = math.floor(((rowUnit - paidUnit) / paidUnit) * 100 + 0.5)
    row.grossNote:SetText((pct >= 0 and "+" or "") .. pct .. "%")
    setColor(row.grossNote, pct >= 0 and Theme.color.green or Theme.color.red)
  else
    -- Nothing is "no price yet"; the words are "no receipt, so the margin is not a number
    -- anybody can know". Conflating them is what made Unknown read as broken.
    row.grossNote:SetText(rowUnit and not paidUnit and GC.L["no cost"] or "")
    setColor(row.grossNote, Theme.color.fgDim)
  end
  -- Where rowUnit stands in the live book. The marks count price levels from the
  -- cheapest; the lit one is where this price lands -- gold for a price about to be
  -- posted, the watch blue for a lot already standing there, the same two colours the
  -- book itself uses for the same two facts.
  -- On TO POST the price is about to be posted and joins any level at the same price, so
  -- that level counts as ahead -- what THE BOOK's marker says (SellViewModel.UnitsAhead).
  local standing = rowUnit and GC.SellViewModel.Standing
    and GC.SellViewModel.Standing(p, rowUnit, not onListedDeck) or nil
  local lit = onListedDeck and Theme.color.watch or Theme.color.gold
  for slot, mark in ipairs(row.standMarks) do
    if not standing then
      -- No book, no marks: five grey ticks beside nothing read as a broken widget.
      mark:SetColorTexture(1, 1, 1, 0)
    elseif slot == standing.slot then
      mark:SetColorTexture(lit[1], lit[2], lit[3], 1)
    else
      mark:SetColorTexture(1, 1, 1, slot < standing.slot and 0.32 or 0.10)
    end
  end
  if not standing then
    row.priceStand:SetText("")
  elseif standing.ahead == 0 then
    row.priceStand:SetText(GC.L["first in line"])
    setColor(row.priceStand, Theme.color.green)
  else
    row.priceStand:SetText((onListedDeck and GC.L["%s under you"] or GC.L["%s ahead"]):format(
      GC.Util.FormatCount(standing.ahead) or tostring(standing.ahead)))
    -- Gold where those units are why the lot is worth cancelling; quiet on one being held.
    setColor(row.priceStand, (queuedLot and not queuedLot.urgent)
      and (Theme.color.goldHi or Theme.color.gold) or Theme.color.fgDim)
  end
  -- Post is the point of this screen, so it lives on the row itself. It
  -- used to be reachable only by expanding the position and finding a
  -- sub-row, and only for stock GoldCap had a receipt for -- which is why
  -- the honest answer to "what can I list" was "go use the Blizzard tab".
  -- Set cost is bookkeeping and stays available whenever there is no
  -- stock to act on; the expansion carries it in either case.
  if onListed and ROW.queuedLot(p) then
    -- MY LOTS' own control, on the rows worth cancelling and no others. It cancels nothing
    -- itself: ROW.armLot opens the position and hands the click to the lot's own button.
    showRowAction(row, "Cancel lot", function()
      ROW.mirror = row.action
      ROW.armLot(ROW.queuedLot(row.position))
    end)
  elseif bagQty > 0 and not onListed then
    showRowAction(row, "Post", function() UI.Dock.OnPostClick(row) end)
  elseif UI.CostDialog.CanSetCost(p) then
    showRowAction(row, GC.L["Set cost"], function() UI.CostDialog.OpenCostDialog(p) end)
  else
    row.action:Hide()
  end
end

-- A heading in the list's own column: the NOT ON HAND fold, a MY LOTS section, the waiting stock.
function Row.PaintHeading(row, entry)
  if entry.kind == "fold" then
    -- "+" and "-" rather than an arrow: only in-game-proven punctuation goes on screen (the
    -- bundled face drew tofu for the arrows the design used).
    row.sectionLabel:SetText((entry.open and "- " or "+ ")
      .. (GC.L["NOT ON HAND %d"]):format(entry.count)
      .. "  " .. DIM_HEX .. GC.L["in the mail, the bank or on another character"] .. "|r")
    row.action:Hide()
  elseif entry.kind == "section" then
    row.sectionLabel:SetText(ROW.sectionText(entry.section))
    row.action:Hide()
  else
    local title, aside = ROW.waitText(entry)
    row.sectionLabel:SetText(title)
    row.sectionHint:SetText(aside or "")
    row.action:Hide()
  end
end

-- How a row looks for its kind this render, after its cells are filled: banding, the open
-- position's ring, the surface's fill, what it puts away of the last kind's widgets, which of the
-- three name widgets shows, the icon, and the layout (the list's columns, or the panel's).
function Row.Style(row, entry, listIndex)
  local p = entry.position
  -- Banding, hierarchy and the icon are decided here, after the cells are filled, because
  -- only `entry.kind` distinguishes a position from one of its expanded children. Exactly
  -- one of row.cells.item / row.subItem / row.sectionLabel is shown per row -- the other
  -- two are hidden here rather than merely left un-set, since rows are pooled and rebound
  -- to a different kind on every render (a "batch" this pass can be a "position" the next).
  local zc2 = Theme.color.zebra
  -- An OPEN position and the panel under it are one block, so the row wears the same gold
  -- the panel's left rail does instead of its turn in the white zebra. Without it the pair
  -- read as two unrelated rows that happened to land next to each other.
  if entry.kind == "position" and UI.expanded[p.positionKey] then
    local gc3 = Theme.color.gold
    row.zebra:SetVertexColor(gc3[1], gc3[2], gc3[3], 0.10)
    row.selectRing:Show()
  else
    row.zebra:SetVertexColor(zc2[1], zc2[2], zc2[3], (listIndex % 2 == 1) and (zc2[4] or 0.04) or 0)
    row.selectRing:Hide()
  end
  -- The drawer is a SURFACE, not a shaded row: at the well's usual half alpha the window
  -- behind it (and, docked, the auction house's own art at the edges) mixed straight
  -- through and left the panel looking washed out rather than the flat panel colour the
  -- design is drawn in. Every other sub-row keeps the translucent well, so this is set on
  -- both branches -- rows are pooled and one would otherwise inherit the other's fill.
  local pnc = Theme.color.panel
  local phc2 = Theme.color.panelHi
  if entry.kind == "drawer" then
    row.well:SetVertexColor(pnc[1], pnc[2], pnc[3], 1)
  else
    row.well:SetVertexColor(phc2[1], phc2[2], phc2[3], 0.5)
  end
  -- Pooled rows are rebound to a different kind on every render, so a book row's own
  -- widgets have to be put away by whatever kind takes the row next.
  if entry.kind ~= "price" and entry.kind ~= "drawer" then
    UI.Inspector.PutAway(row)
    -- The head dresses the pooled action button as the panel's own Post; every other kind
    -- gets the row button back.
    -- ...at the row's own height for a position, where it is the control the row exists for.
    row.action:SetSize(86, entry.kind == "position" and ROW.BUTTON_H or 18)
    if row.action.SetVariant then row.action:SetVariant("ghost") end
    -- Gold lettering on the row's Post, the way the design drew it: the fill stays the
    -- quiet ghost, so a list of ten does not become ten gold bars.
    -- Red for the one that cancels, on the row and on the panel's lots alike.
    local cancels = row.action.helpKey == "Cancel lot"
    if (entry.kind == "position" or cancels) and row.action.text and row.action.text.SetTextColor then
      local lettering = cancels and Theme.color.red or Theme.color.goldHi or Theme.color.gold
      row.action.text:SetTextColor(lettering[1], lettering[2], lettering[3], 1)
    end
    -- ...and a thin outline with it, on a position or a cancel alone: the pooled button is
    -- every other kind's too, and theirs stay bare.
    if row.action.SetRing then
      local ring = cancels and Theme.color.red or Theme.color.gold
      row.action:SetRing((entry.kind == "position" or cancels) and { ring[1], ring[2], ring[3], cancels and 0.5 or 0.45 } or nil)
    end
  end
  if entry.kind ~= "group" and entry.kind ~= "batch" then row.sectionHint:Hide() end
  -- Same rule, and the drawer has the most to put away: five book lines and four headings.
  -- A pooled row that painted a panel last render would otherwise keep every one of them
  -- on top of whatever line it becomes next.
  if entry.kind ~= "drawer" then
    UI.Book.PutAway(row)
  end
  -- The second lines belong to a position alone; a pooled row that was one last render
  -- must not keep its queue marks under a lot or a batch.
  local twoLine = entry.kind == "position"
  if twoLine then row.priceStand:Show(); row.grossNote:Show()
  else row.priceStand:Hide(); row.grossNote:Hide() end
  for _, mark in ipairs(row.standMarks) do
    if twoLine then mark:Show() else mark:Hide() end
  end
  if entry.kind == "position" then
    row.spine:Hide()
    row.divider:Show()
    row.zebra:Show()
    row.well:Hide()
    row.cells.item:Show()
    row.itemStock:Show()
    row.subItem:Hide()
    row.sectionLabel:Hide()
    row.sectionRule:Hide()
    local icon = nil
    if p.itemID and C_Item and C_Item.GetItemIconByID then
      local ok, texture = pcall(C_Item.GetItemIconByID, p.itemID)
      icon = ok and texture or nil
    end
    -- Item 4 (addon polish batch): no icon means nothing to indent past -- the old
    -- unconditional 26 left the name floating in a blank gap for a row with no
    -- resolvable icon.
    row.itemInset = icon and (ROW.ICON + 10) or 0
    if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
  elseif entry.kind == "fold" or entry.kind == "section" or entry.kind == "waitHead"
      or entry.kind == "waitItem" then
    -- A heading in the list's own column, not a child of the row above it: no spine, no
    -- well, and the label starts where the item names do.
    row.itemInset = 2
    row.icon:Hide(); row.spine:Hide(); row.divider:Hide()
    row.zebra:Hide(); row.well:Hide()
    row.cells.item:Hide(); row.itemStock:Hide(); row.subItem:Hide()
    row.sectionLabel:Show(); row.sectionRule:Show()
    row.sectionRule:ClearAllPoints()
    row.sectionRule:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.s, 0)
    row.sectionRule:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
    -- The fold is a control and wears gold; a section is a caption and stays quiet.
    local fgc = entry.kind == "fold" and Theme.color.gold or Theme.color.fgMuted
    row.sectionRule:SetColorTexture(fgc[1], fgc[2], fgc[3], entry.kind == "fold" and 0.25 or 0.12)
    setColor(row.sectionLabel, fgc)
    -- An item waiting for its key is a line under that heading, not a heading of its own.
    if entry.kind == "waitItem" then row.sectionRule:Hide() end
    -- The waiting heading's aside, one line from its title to the list's edge, where the
    -- rule would run.
    if entry.kind == "waitHead" then
      row.sectionRule:Hide()
      row.sectionHint:ClearAllPoints()
      row.sectionHint:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.m, 0)
      row.sectionHint:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
      row.sectionHint:SetWordWrap(false)
      row.sectionHint:SetMaxLines(1)
      row.sectionHint:Show()
    end
  else
    row.itemInset = 34
    row.icon:Hide()
    row.spine:Show()
    row.divider:Hide() -- a group's children are bracketed by the spine, not sliced by rules
    -- The well, not the zebra: a sub-row sits on a nested fill instead of the list's own
    -- banding, so an expanded group reads as one bracketed unit (the spine is the other
    -- half of that cue) rather than as more top-level rows in the same alternating list.
    row.zebra:Hide()
    row.well:Show()
    row.cells.item:Hide()
    row.itemStock:Hide()
    if entry.kind == "group" then
      row.subItem:Hide()
      row.sectionLabel:Show()
      row.sectionRule:Show()
    else
      row.subItem:Show()
      row.sectionLabel:Hide()
      row.sectionRule:Hide()
    end
  end
  if entry.panel then
    -- The panel is the surface these sit on: no well, no spine bracketing them to a row
    -- that is a column away.
    row.spine:Hide(); row.well:Hide(); row.zebra:Hide()
    UI.Inspector.LayoutDetailRow(row)
  else
    UI.List.LayoutCells(row)
  end
end
