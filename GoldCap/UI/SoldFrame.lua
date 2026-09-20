local _, GC = ...

-- Sold tab, leg 3 (sold-tab design doc): "what did I sell and at what
-- profit", rendered from two honestly separate sections -- the server
-- snapshot (GC.AppLedger, same answer as goldcap.gg/ledger, as of the last
-- /reload) and the local ledger rows the server has not seen yet. The two
-- are NEVER merged or fuzzy-matched (the sell-identity lesson): near the
-- boundary a sale may briefly appear in both labeled sections, and that is
-- accepted. Local profit appears only on an exact evidence-key join to
-- db.acquisitionRealized; everything else says "--", never an invented
-- number. Pro gating happened server-side: a free summary simply carries no
-- basis/realized, and this file renders what is there.
--
-- Local/server boundary (C1 fix): the boundary is the newest `at` among the
-- snapshot's OWN sale rows, never its generatedAt. occurredAt != uploadedAt
-- -- SavedVariables only flushes to disk on /reload or logout, so the file
-- the addon reads was written BEFORE that reload, and generatedAt is
-- therefore always newer than the sales the snapshot is missing. Clamping
-- the boundary to generatedAt (the old rule) hid a whole session's worth of
-- sales in neither section. Deriving the boundary from the sales themselves
-- is a fact about what the server demonstrably holds: it can duplicate a
-- sale across both sections for one reload (accepted, honest -- the
-- sections are labeled) but it can never hide one. generatedAt remains only
-- the "age" line's surface below.
GC.Sold = {}

local Theme
local container, content
local rows = {}
local geometry

-- Same thresholds the Deals staleness line uses (SniperFrame's LIM table is
-- file-local; two constants are cheaper than a cross-file export).
local STALE_YELLOW_SECONDS = 6 * 3600
local STALE_RED_SECONDS = 24 * 3600

-- Close to Theme.color.fgDim. The PROFIT cell is one FontString, so the
-- partial-coverage "N/M" suffix (M2) can't get its own setColor call like
-- the profit number beside it -- an inline escape is the only way to make
-- it read dim instead of inheriting the green/red profit color.
local DIM_HEX = "|cff9d9d9d"

local function setColor(fontString, color)
  if fontString and color then
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  end
end

-- Mirrors SellFrame's formatAmount: plain "65g24s" text, coin icons only
-- below one gold (icon escapes truncate mid-escape in clipped FontStrings).
local function formatAmount(amount)
  if amount == nil then return GC.L["Unknown"] end
  if amount < 0 then return "-" .. formatAmount(-amount) end
  if amount >= 10000 then
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
  end
  return GetCoinTextureString(amount)
end

-- `_G.date`, not a bare global: `date` is a WoW-injected global that is
-- absent headless and undeclared in .luacheckrc -- Init.lua's sales printer
-- reads it the same guarded way.
local function formatWhen(at)
  if not _G.date then return "" end
  local ok, text = pcall(_G.date, "%d %b %H:%M", at)
  return ok and text or ""
end

local function signedProfit(profit)
  return (profit >= 0 and "+" or "") .. formatAmount(profit)
end

-- The one list this tab renders, top to bottom. Every entry is
-- self-describing; paintRow below is a dumb switch over `kind`.
local function buildEntries()
  local entries = {}
  local summary = GC.AppLedger and GC.AppLedger.GetSummary and GC.AppLedger.GetSummary()
  local now = time()
  -- The boundary is the newest `at` the snapshot's own sale rows prove the
  -- server holds (see the file header comment) -- not generatedAt. No
  -- summary, or a summary with no sales yet, proves nothing: every local
  -- sale belongs in the local section.
  local boundary = 0
  if summary then
    for _, sale in ipairs(summary.sales) do
      if type(sale.at) == "number" and sale.at > boundary then boundary = sale.at end
    end
  end

  if summary then
    entries[#entries + 1] = { kind = "totals", summary = summary }
    entries[#entries + 1] = { kind = "age", age = math.max(0, now - summary.generatedAt) }
    if not summary.pro then
      entries[#entries + 1] = { kind = "hint",
        text = GC.L["Profit tracking is a goldcap.gg Pro feature"] }
    end
  else
    entries[#entries + 1] = { kind = "hint",
      text = GC.L["Pair or update the GoldCap Companion to see profit from goldcap.gg"] }
  end

  -- Local section: ledger sales the snapshot cannot contain yet. Exact-key
  -- profit join only -- realizedByKey[entry.key], nothing looser.
  local realizedByKey = {}
  if GC.Acquisitions and GC.Acquisitions.GetRealized then
    for _, row in ipairs(GC.Acquisitions.GetRealized()) do
      if row.evidenceKey then realizedByKey[row.evidenceKey] = row end
    end
  end
  local localSales = {}
  local ledgerEntries = (GC.Ledger and GC.Ledger.GetEntries and GC.Ledger.GetEntries()) or {}
  for _, entry in ipairs(ledgerEntries) do
    if entry.kind == "sale" and type(entry.at) == "number" and entry.at > boundary then
      localSales[#localSales + 1] = entry
    end
  end
  table.sort(localSales, function(a, b) return (a.at or 0) > (b.at or 0) end)
  if #localSales > 0 then
    entries[#entries + 1] = { kind = "section",
      text = GC.L["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] }
    for _, sale in ipairs(localSales) do
      entries[#entries + 1] = { kind = "localSale", sale = sale,
        realized = sale.key and realizedByKey[sale.key] or nil }
    end
  end

  -- Server section: the snapshot's own sale rows, order as served (newest
  -- first).
  if summary and #summary.sales > 0 then
    -- The snapshot's `sales` list is capped (at most 50, per the API); once
    -- totals.salesCount says the server holds more than that, the header
    -- admits this section is a tail rather than silently under-counting the
    -- window (M3).
    local header = (GC.L["ON GOLDCAP.GG — LAST %d DAYS"]):format(summary.days)
    if summary.totals.salesCount > #summary.sales then
      header = (GC.L["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"]):format(
        summary.days, #summary.sales, summary.totals.salesCount)
    end
    entries[#entries + 1] = { kind = "section", text = header }
    for _, sale in ipairs(summary.sales) do
      entries[#entries + 1] = { kind = "serverSale", sale = sale }
    end
  end

  if #localSales == 0 and not (summary and #summary.sales > 0) then
    entries[#entries + 1] = { kind = "hint",
      text = GC.L["No sales recorded yet -- open your mailbox with GoldCap loaded"] }
  end

  return entries
end

-- ---------------------------------------------------------------------------
-- Presentation layer, rebuilt to speak the same visual language as Deals
-- (UI/SniperFrame.lua) and Sell (UI/SellFrame.lua): a column table with a
-- header row, single-line zebra/hover rows, mono right-justified numbers --
-- rather than the old two-line left/right text list. buildEntries() above
-- is untouched; everything below only decides how each entry PAINTS.
--
-- One COLUMNS table drives both the header row (createHeaderRow) and every
-- data row's cells (buildRowCell/createRow), the same pattern SniperFrame's
-- COLUMNS/anchorColumns uses -- widths/order can never drift out of sync
-- between the two. `optional` columns (when, unit) responsively drop, in
-- table order, exactly like Deals' total/trend (computeHidden).
-- ---------------------------------------------------------------------------
local SD = {
  BAND_HEIGHT = 40,  -- header band: two text lines above the table
  HEADER_H = 16,     -- column header row height, matches Deals' CH.HEADER
}

local COLUMNS = {
  { key = "item",   flex = true, min = 140 },
  { key = "when",   w = 90,  optional = true, size = 10 },
  { key = "qty",    w = 45,  num = true, size = 11 },
  { key = "unit",   w = 70,  num = true, size = 11, optional = true },
  { key = "total",  w = 80,  num = true, size = 11 },
  { key = "profit", w = 110, num = true, size = 12, bold = true },
}

-- Already uppercase in the key, and never passed through :upper() -- Lua's upper is
-- byte-wise and leaves every non-ASCII letter alone, so a translated header would come
-- back half-cased. The Sell tab settled this the same way (SellFrame's header build).
-- Keys, not translations: this table is built at FILE SCOPE, and GC.L only resolves once
-- ApplyLocale has run at ADDON_LOADED. Translating here would freeze the English fallback
-- into every language. headerText() below looks up when the header is actually built.
-- @localised-keys: literals in this table ARE GC.L keys; see the comment above for why
-- the lookup happens where the table is read rather than where it is built. The table has to
-- close with a `}` on its own line -- that is where the spec's scanner stops.
local HEADER_TEXT = {
  item = "ITEM", when = "WHEN", qty = "QTY", unit = "UNIT", total = "TOTAL", profit = "PROFIT",
}
local function headerText(key) return GC.L[HEADER_TEXT[key] or ""] end

-- Anchors every visible fixed COLUMNS entry's RIGHT edge right-to-left off
-- `host`'s own RIGHT edge, skipping any key present in `hidden`; returns the
-- flex ("item") column's anchor pair for the caller to anchor the item
-- text's RIGHT edge to. Identical in shape to SniperFrame's anchorColumns --
-- duplicated rather than shared, the same way SellFrame's own column layout
-- is its own copy: these locals do not cross files (see the addon's engineering notes on
-- why the file has stayed unsplit).
local function anchorColumns(host, hidden, cellFor)
  local prev, prevPoint = host, "RIGHT"
  local flexAnchor
  for i = #COLUMNS, 1, -1 do
    local col = COLUMNS[i]
    if col.flex then
      flexAnchor = { frame = prev, point = prevPoint }
    else
      local cell = cellFor(col)
      if hidden[col.key] then
        cell:Hide()
      else
        cell:Show()
        cell:ClearAllPoints()
        cell:SetWidth(col.w)
        if prevPoint == "RIGHT" then
          cell:SetPoint("RIGHT", prev, "RIGHT")
        else
          cell:SetPoint("RIGHT", prev, "LEFT", -Theme.pad.s, 0)
        end
        prev, prevPoint = cell, "LEFT"
      end
    end
  end
  return flexAnchor
end

-- optional columns in COLUMNS' own declared order (when, then unit) -- that
-- order IS the drop priority: WHEN goes first as the window narrows, UNIT
-- second, matching the design's stated "drop WHEN first, then UNIT".
local OPTIONAL_KEYS, DROP_THRESHOLDS = {}, { 140, 110 }
for _, col in ipairs(COLUMNS) do
  if col.optional then OPTIONAL_KEYS[#OPTIONAL_KEYS + 1] = col.key end
end

local function fixedColumnBudget(hidden)
  local sum, visible = 0, 0
  for _, col in ipairs(COLUMNS) do
    if not col.flex and not hidden[col.key] then
      sum = sum + col.w
      visible = visible + 1
    end
  end
  return sum + visible * Theme.pad.s
end

local function computeHidden(containerWidth)
  local hidden = {}
  for i, key in ipairs(OPTIONAL_KEYS) do
    local itemWidth = containerWidth - fixedColumnBudget(hidden)
    if itemWidth < DROP_THRESHOLDS[i] then
      hidden[key] = true
    end
  end
  return hidden
end

local function sameHidden(a, b)
  for _, key in ipairs(OPTIONAL_KEYS) do
    if (not a[key]) ~= (not b[key]) then return false end
  end
  return true
end

-- Current drop state, shared by the header row and every pooled row --
-- recomputed by applyColumnVisibility whenever the container's live width
-- changes.
local hiddenColumns = {}

-- The two-line summary above the table (totals+realized profit, sync age).
-- Built once by Attach; `band` itself is referenced directly by
-- RefreshIfShown below purely so the behavior spec can reach it via
-- debug.getupvalue, the same way it already reaches `rows`/`container`.
local band

local createRow, layoutRow, headerLayout

-- Re-applies the current responsive column drop to the header and every
-- pooled row. Called from the container's OnSizeChanged hook (the live
-- resize/dock-reparent path) and from updateContentWidth (Show()'s catch-up
-- path for a frame resized while hidden) -- same two call sites Deals uses.
local function applyColumnVisibility(containerWidth)
  if not headerLayout then return end
  local newHidden = computeHidden(containerWidth)
  if sameHidden(newHidden, hiddenColumns) then return end
  hiddenColumns = newHidden
  headerLayout()
  for i = 1, #rows do layoutRow(rows[i]) end
end

local function buildRowCell(row, col)
  local fs
  if col.num then
    fs = Theme.Num(row, col.size or 11, col.bold)
  else
    fs = Theme.Label(row, col.size or 11)
    fs:SetJustifyH("LEFT")
  end
  fs:SetWordWrap(false)
  return fs
end

-- Fills the ITEM/WHEN/QTY/UNIT/TOTAL cells shared by a local and a server
-- sale row; PROFIT is painted separately by each caller since the two
-- sections disagree on where a profit number even comes from.
local function paintSaleCells(row, name, itemID, qty, total, at, pending)
  -- What the row's OnEnter reads (createRow). Stamped here, beside the icon that comes from
  -- the same itemID, so a row showing an icon and a row showing a tooltip can never disagree
  -- about which item they are. A sale carrying no itemID -- every mail invoice the companion
  -- has not yet paired with one -- simply has no tooltip, the same way it has no icon.
  row.tooltipItemID = itemID
  local decorated = (itemID and Theme.WithQuality and Theme.WithQuality(name, itemID, 11)) or name
  row.item:SetText(decorated)
  setColor(row.item, Theme.color.fg)

  -- Item icon, same guarded C_Item.GetItemIconByID call SellFrame's position
  -- rows use -- headless/pcall-safe, no icon rather than an error when the
  -- client doesn't have one cached yet.
  local icon = nil
  if itemID and C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, itemID)
    icon = ok and texture or nil
  end
  -- Item 4 (addon polish batch): no icon means nothing to indent past -- the old unconditional
  -- 26 left the name floating in a blank gap for a row with no resolvable icon.
  row.itemInset = icon and 26 or 0
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end

  -- The sale exists, the gold is just in transit -- same honesty the old
  -- "[not yet paid out]" suffix carried, now the WHEN column's own content
  -- rather than an appendix to it.
  -- Transit is the one thing worth calling out in this column -- the gold
  -- tint says "still moving", dates stay dim like the rest of the row.
  row.cells.when:SetText(pending and GC.L["in the mail"] or formatWhen(at))
  setColor(row.cells.when, pending and Theme.color.gold or Theme.color.fgDim)

  row.cells.qty:SetText(tostring(qty or 0))
  setColor(row.cells.qty, Theme.color.fg)

  if qty and qty > 0 and type(total) == "number" then
    row.cells.unit:SetText(formatAmount(math.floor(total / qty)))
  else
    row.cells.unit:SetText("")
  end
  setColor(row.cells.unit, Theme.color.fg)

  row.cells.total:SetText(formatAmount(total))
  setColor(row.cells.total, Theme.color.fg)
end

-- heightFor: every row is one Theme.ROW_H line, except a hint -- those carry
-- a full sentence and word-wrap, so they get two lines' worth of room
-- (Deals' emptyText is the same idea: word-wrapped, muted, centered).
local function heightFor(kind)
  if kind == "hint" then return geometry.rowHeight * 2 end
  return geometry.rowHeight
end

-- Resets a row to a blank slate before paintRow's own kind-specific branch
-- fills it in. Fixed cells are only re-Shown when their column is not
-- currently responsively hidden (hiddenColumns) -- layoutRow/anchorColumns
-- only re-runs when the column-drop state itself CHANGES (see
-- applyColumnVisibility), not on every render, so this is what keeps a
-- dropped WHEN/UNIT column from reappearing the next time an unrelated
-- entry (a new sale, a section header) repaints this same pooled row.
--
-- A hint/section row does NOT also Hide() these cells in paintRow (M3): the
-- trailing layoutRow(row) call at the end of every paintRow branch re-runs
-- anchorColumns, which unconditionally Show()s every non-dropped cell, so a
-- Hide() here would just get undone. Blank TEXT -- set below, and never
-- refilled by the hint/section branches -- is what actually keeps those
-- cells empty on a hint/section row, not visibility.
local function clearRow(row)
  row.item:SetText("")
  row.item:Show()
  row.wide:SetText("")
  row.wide:Hide()
  row.sectionLabel:SetText("")
  row.sectionLabel:Hide()
  row.sectionRule:Hide()
  -- Only a sale row (paintSaleCells) claims icon space; hint/section rows
  -- have nothing to show one for and stay flush left.
  row.itemInset = 0
  row.icon:Hide()
  -- Rows are pooled and rebound every render, so what the tooltip reads has to be cleared
  -- for EVERY kind, not written per branch -- a fact left over from an earlier sale would
  -- otherwise ride along onto a hint or section row, or onto a different item.
  row.tooltipItemID, row.tooltipPaidUnit, row.tooltipCostUnknown = nil, nil, false
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      row.cells[col.key]:SetText("")
      if hiddenColumns[col.key] then
        row.cells[col.key]:Hide()
      else
        row.cells[col.key]:Show()
      end
    end
  end
end

local function paintRow(row, entry, index)
  clearRow(row)

  local zc = Theme.color.zebra
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], (index % 2 == 1) and (zc[4] or 0) or 0)

  if entry.kind == "hint" then
    -- Centered, muted, in the list area -- Deals' empty-state language --
    -- rather than a top-left label. A hint can appear alongside real rows
    -- (the Pro notice sits above server rows that still render), so it
    -- stays a row in the same flow instead of a separate overlay widget.
    row.item:Hide()
    row.wide:Show()
    row.wide:SetJustifyH("CENTER")
    row.wide:SetWordWrap(true)
    row.wide:SetText(entry.text)
    setColor(row.wide, Theme.color.fgDim)
    row.wide:SetSpacing(4)
  elseif entry.kind == "section" then
    -- Mono micro-label + a hairline rule running to the row's right edge --
    -- not a full-width gold label: Sold's section rows have nothing to say
    -- in QTY/UNIT/TOTAL/PROFIT at all, so a small uppercase label plus a
    -- dim rule reads as a divider rather than another content row (createRow
    -- has the anchoring rationale).
    row.item:Hide()
    row.wide:Hide()
    row.sectionLabel:SetText(entry.text)
    row.sectionLabel:Show()
    row.sectionRule:Show()
  elseif entry.kind == "localSale" then
    local sale = entry.sale
    paintSaleCells(row, sale.itemName or GC.L["Unknown item"], sale.itemID, sale.qty or 0,
      sale.total, sale.at, sale.pending)
    if entry.realized and type(entry.realized.profit) == "number" then
      -- entry.realized.profit (Core/Acquisitions.lua's ReconcileSale:
      -- `profit = entry.total - allocation.knownCost`) is GROSS -- the AH
      -- cut is never subtracted there. The server section's basis.profit
      -- IS net of the cut, so the two sections would otherwise disagree on
      -- the same sale by exactly the cut. Subtract it here, at render time,
      -- from the sale's own recorded cut (I1) -- do not also subtract it in
      -- Core/Acquisitions.lua, or a future reader double-subtracts.
      local net = entry.realized.profit - (sale.cut or 0)
      -- What one of these cost, for the tooltip. `cost` is the FIFO allocation's knownCost
      -- over `quantity` units (Core/Acquisitions.lua's ReconcileSale), so the division is
      -- the same average the PROFIT cell is already computed from -- read, never re-derived.
      local cost, units = entry.realized.cost, entry.realized.quantity
      if type(cost) == "number" and type(units) == "number" and units > 0 then
        row.tooltipPaidUnit = math.floor(cost / units)
      end
      row.cells.profit:SetText(signedProfit(net))
      setColor(row.cells.profit, net >= 0 and Theme.color.green or Theme.color.red)
    else
      row.cells.profit:SetText("--")
      setColor(row.cells.profit, Theme.color.fgDim)
    end
  elseif entry.kind == "serverSale" then
    local sale = entry.sale
    paintSaleCells(row, sale.name, sale.item, sale.qty, sale.total, sale.at, sale.pending)
    local basis = sale.basis
    if basis and basis.matched > 0 then
      local text = signedProfit(basis.profit)
      if basis.unmatched > 0 then
        text = text .. "  " .. DIM_HEX .. ("%d/%d"):format(basis.matched, sale.qty) .. "|r"
      end
      row.cells.profit:SetText(text)
      setColor(row.cells.profit, basis.profit >= 0 and Theme.color.green or Theme.color.red)
      -- Only over the MATCHED units: dividing by sale.qty would quietly average in the units
      -- FIFO could not cost at all and report a cheaper purchase than ever happened.
      row.tooltipPaidUnit = math.floor(basis.cost / basis.matched)
    elseif basis then
      row.cells.profit:SetText(GC.L["cost unknown"])
      setColor(row.cells.profit, Theme.color.fgDim)
      row.tooltipCostUnknown = true
    end
    -- else: free tier, no basis at all -- row.cells.profit stays "" (M2/
    -- design: "free tier (no basis) -> empty"), never an invented dash.
  end

  -- Re-anchor the item cell now that this render's own row.itemInset is
  -- known (SellFrame's paintRow does the same: layoutCells runs once per
  -- render, after the icon/itemInset decision, not only on a column-drop
  -- change). This MUST run every render, not just on resize: rows are
  -- pooled and a given index's entry.kind can change from one render to
  -- the next (a hint row this pass, a sale row next pass), so without this
  -- call a pooled row would keep whatever itemInset it last painted as,
  -- stale until the next unrelated column-visibility change happened to
  -- re-run layoutRow for it.
  layoutRow(row)
end

layoutRow = function(row)
  local flexAnchor = anchorColumns(row, hiddenColumns, function(col) return row.cells[col.key] end)
  row.item:ClearAllPoints()
  -- row.itemInset (paintRow/paintSaleCells) leaves room for the icon on a
  -- sale row; hint/section rows (itemInset 0) stay flush with the row edge.
  row.item:SetPoint("LEFT", row, "LEFT", row.itemInset or 0, 0)
  row.item:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
end

createRow = function(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(geometry.rowHeight)

  -- Zebra + hover, same convention as Deals/Sell: a sliced rounded fill,
  -- recomputed every render off the row's CURRENT position (Sell's approach
  -- -- Sold's entry composition reshuffles kind-to-kind far more than Deals'
  -- pool ever does, so baking zebra in at creation time, the way Deals does,
  -- would go stale the moment a section appears above a row that used to sit
  -- at an even index). Insets: 1px top/bottom so margin 12 <= 15 = half of
  -- the 30px effective fill at ROW_H 32; right inset is 2, not Deals' 26 --
  -- this container is already inset by the gutter and the scrollbar hangs
  -- outside it (Sell's createRow carries the identical comment).
  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  zebra:SetTextureSliceMargins(12, 12, 12, 12)
  zebra:SetPoint("TOPLEFT", 2, -1)
  zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  zebra:SetVertexColor(zc[1], zc[2], zc[3], 0)
  row.zebra = zebra

  -- Hover: the real engine HIGHLIGHT draw layer, shown/hidden by the client
  -- itself for as long as the cursor is over a mouse-enabled frame -- never
  -- an OnEnter/OnLeave repaint (the addon's engineering notes' "Buttons and hover").
  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  highlight:SetTextureSliceMargins(12, 12, 12, 12)
  highlight:SetPoint("TOPLEFT", 2, -1)
  highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight = highlight
  row:EnableMouse(true)

  -- The item's own tooltip on hover, the same affordance Deals and the Sell tab already give
  -- their rows -- a seller reading "Apprentice's Scribbles x92" should not have to go find the
  -- item elsewhere to see what it is. Wired ONCE here, on the pooled row, reading whatever
  -- paintRow last stamped: hooking it per render would stack a handler per pass.
  --
  -- The `paid ... each` line rides along because this tab had no room for it anywhere else.
  -- Sold already carries six columns that shed as the window narrows, and a seventh would be
  -- the first to go -- taking the number off exactly the narrow window that needed the space.
  -- A tooltip costs no width at all. It is read, not recomputed: the same FIFO cost the PROFIT
  -- cell on this row was built from, so the two can never disagree.
  row:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.tooltipItemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.tooltipItemID) end
    if self.tooltipPaidUnit then
      GameTooltip:AddLine((GC.L["paid %s each"]):format(formatAmount(self.tooltipPaidUnit)),
        0.85, 0.85, 0.85, true)
    elseif self.tooltipCostUnknown then
      GameTooltip:AddLine(GC.L["cost unknown"], 0.85, 0.85, 0.85, true)
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  -- Section rows: mono micro-label + a hairline running to the row's right edge. The rule
  -- anchors to the label's RIGHT, so the label must stay single-point LEFT-anchored (its
  -- width is its text).
  row.sectionLabel = Theme.Num(row, 9, true)
  row.sectionLabel:SetJustifyH("LEFT")
  row.sectionLabel:SetPoint("LEFT", 4, 0)
  setColor(row.sectionLabel, Theme.color.gold)
  row.sectionLabel:Hide()
  local gc = Theme.color.gold
  row.sectionRule = row:CreateTexture(nil, "ARTWORK")
  row.sectionRule:SetColorTexture(gc[1], gc[2], gc[3], 0.25)
  row.sectionRule:SetHeight(1)
  row.sectionRule:SetPoint("LEFT", row.sectionLabel, "RIGHT", 10, 0)
  row.sectionRule:SetPoint("RIGHT", -2, 0)
  row.sectionRule:Hide()

  -- Item icon, shown only on sale rows (paintRow) -- same trimmed-border
  -- convention as SellFrame's position rows.
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.icon:Hide()

  -- The full-row text used by the "hint" kind -- see paintRow. Section rows
  -- use row.sectionLabel/row.sectionRule above instead.
  row.wide = Theme.Label(row, 11)
  row.wide:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.wide:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.wide:Hide()

  row.item = Theme.Label(row, 11)
  row.item:SetWordWrap(false)

  row.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then row.cells[col.key] = buildRowCell(row, col) end
  end
  layoutRow(row)
  return row
end

local function createHeaderRow(parent)
  local header = CreateFrame("Frame", nil, parent)
  header:SetHeight(SD.HEADER_H)
  header.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      local hit = CreateFrame("Frame", nil, header)
      hit:SetHeight(SD.HEADER_H)
      local label = Theme.Num(hit, 9)
      label:SetWordWrap(false)
      -- One line, hard capped -- the pair the Deals headings carry (UI/SniperFrame.lua's
      -- buildHeaderCell): the label is SetAllPoints() onto a cell SD.HEADER_H tall, and a
      -- line that does not fit the height it is given is not drawn at all.
      label:SetMaxLines(1)
      setColor(label, Theme.color.fgDim)
      label:SetAllPoints()
      label:SetJustifyH(col.num and "RIGHT" or "LEFT")
      label:SetText(headerText(col.key))
      hit.label = label
      header.cells[col.key] = hit
    end
  end

  -- ITEM reads on the kit now too, the same mono/fgDim treatment as the other
  -- header cells above -- it used to stand out as the one native-font label
  -- in an otherwise all-mono row.
  local itemHit = CreateFrame("Frame", nil, header)
  local itemLabel = Theme.Num(itemHit, 9)
  itemLabel:SetWordWrap(false)
  itemLabel:SetMaxLines(1) -- same one-line cap as the cells above
  setColor(itemLabel, Theme.color.fgDim)
  itemLabel:SetAllPoints()
  itemLabel:SetJustifyH("LEFT")
  itemLabel:SetText(headerText("item"))
  itemHit.label = itemLabel
  -- Not read by any production code; exposed so the behavior spec can reach the ITEM cell.
  header.itemCell = itemHit

  headerLayout = function()
    local flexAnchor = anchorColumns(header, hiddenColumns, function(col) return header.cells[col.key] end)
    itemHit:ClearAllPoints()
    itemHit:SetPoint("TOPLEFT", header, "TOPLEFT")
    itemHit:SetPoint("BOTTOMRIGHT", flexAnchor.frame, "BOTTOMLEFT", -Theme.pad.s, 0)
  end
  headerLayout()

  -- Separates the column headings from the first row now that both read in
  -- the same mono font (SellFrame's own header-underline precedent).
  -- Attached as header.rule (not just a local) purely so the behavior spec
  -- can reach it via band.header.rule the same way it already reaches
  -- band.header.cells -- not read by any production code.
  local bc = Theme.color.border
  local rule = header:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)
  header.rule = rule

  return header
end

-- The headings are stamped once, at build -- and this whole tab spends most of its life
-- hidden behind Deals or Sell. A one-line FontString that was on screen when its parent was
-- hidden can come back with its text simply not drawn (the Deals headings went blank exactly
-- that way -- see UI/SniperFrame.lua's updateHeaderSortIndicators for the full story), and
-- SetText is what the client needs to draw it again. So Show() goes through here.
local function restampHeadings()
  local header = band and band.header
  if not header or not header.cells then return end
  -- Cleared before it is set again: SetText with the text the string already holds is a no-op
  -- to the client, and a no-op does not make it draw. The BUY tab measured this in game (every
  -- heading but NEED came back shown, anchored, text intact, blank on screen) and this tab
  -- showed the same on 2026-09-16: ITEM and WHEN drawn, QTY/UNIT/TOTAL/PROFIT blank, because
  -- this function used to stamp the same text over itself. Same cure as UI/BuyFrame.lua.
  local function stamp(label, text)
    if not label then return end
    label:SetText("")
    label:SetText(text)
    if label.Hide and label.Show then label:Hide(); label:Show() end
  end
  for key, hit in pairs(header.cells) do stamp(hit.label, headerText(key)) end
  if header.itemCell then stamp(header.itemCell.label, headerText("item")) end
end

-- The header band: two persistent lines above the table (totals, then sync
-- age) plus a right-aligned REALIZED PROFIT block, not table rows --
-- SellFrame's header-band convention, styled with this tab's own font sizes/
-- spacing rather than its code. Every line is Theme.Num (mono), matching the
-- mono column headers/rows below it; `profit` stays the largest and bold,
-- "realized profit right in bold green/red" under its own dim caption.
local function createBand(parent)
  local profit = Theme.Num(parent, 15, true)
  profit:SetPoint("TOPRIGHT", 0, -16)

  local profitLabel = Theme.Num(parent, 9)
  setColor(profitLabel, Theme.color.fgDim)
  profitLabel:SetText(GC.L["REALIZED PROFIT"])
  profitLabel:SetPoint("TOPRIGHT", 0, -4)

  -- Both lines' RIGHT edge is bound to profitLabel's LEFT, not profit's:
  -- "REALIZED PROFIT" (M6, ~81-105px) is wider than the value it captions,
  -- so binding to the narrower value would let a long totals/age line run
  -- underneath the caption.
  local totals = Theme.Num(parent, 10)
  totals:SetJustifyH("LEFT")
  totals:SetWordWrap(false)
  totals:SetPoint("TOPLEFT", 0, -5)
  totals:SetPoint("RIGHT", profitLabel, "LEFT", -Theme.pad.s, 0)

  local age = Theme.Num(parent, 9)
  age:SetJustifyH("LEFT")
  age:SetWordWrap(false)
  age:SetPoint("TOPLEFT", 0, -24)
  age:SetPoint("RIGHT", profitLabel, "LEFT", -Theme.pad.s, 0)

  -- Band rule: a separate frame pinned to the band's own height so the 1px
  -- BOTTOMLEFT/BOTTOMRIGHT line sits at the band's bottom edge regardless of
  -- where the text lines above it end -- the same fixed-height-frame-plus-
  -- rule shape SellFrame's header underline uses.
  local bandFrame = CreateFrame("Frame", nil, parent)
  bandFrame:SetPoint("TOPLEFT", 0, 0)
  bandFrame:SetPoint("TOPRIGHT", 0, 0)
  bandFrame:SetHeight(SD.BAND_HEIGHT)
  local bc = Theme.color.border
  local rule = bandFrame:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)

  return { totals = totals, profit = profit, profitLabel = profitLabel, age = age, rule = rule }
end

-- The container is anchored TOPLEFT/BOTTOMRIGHT to the window (Attach
-- below), so it already tracks a resize or a dock reparent; this pulls its
-- actual current width into geometry.rowWidth/content, which is what every
-- row's own width then follows via its TOPLEFT+TOPRIGHT anchor in
-- renderRows (I2), and what applyColumnVisibility judges the responsive
-- column drop against. A width of 0/nil (nothing laid out yet) is a no-op --
-- geometry.rowWidth keeps whatever Attach was given.
local function updateContentWidth()
  if not container or not content then return end
  local width = container:GetWidth()
  if width and width > 0 then
    geometry.rowWidth = width
    content:SetWidth(width)
    applyColumnVisibility(width)
  end
end

local function renderRows()
  if not content then return end
  local entries = buildEntries()

  -- "totals"/"age" are the header band's two lines, not table rows (see
  -- createBand) -- pulled out of the entries list before it ever reaches
  -- the row pool. Cleared first so a state with no summary leaves the band
  -- blank rather than showing stale numbers from a previous render.
  band.totals:SetText("")
  band.profit:SetText("")
  band.age:SetText("")
  -- REALIZED PROFIT (I2): the caption is only meaningful once band.profit
  -- actually carries a value -- t.realized is nil for Free-tier/unpaired
  -- users, and this branch never sets band.profit's text in that case, so
  -- the caption must not sit there captioning nothing.
  band.profitLabel:Hide()
  local listEntries = {}
  for _, entry in ipairs(entries) do
    if entry.kind == "totals" then
      local t = entry.summary.totals
      band.totals:SetText((GC.L["%d sales · %s proceeds · %s in the mail"]):format(
        t.salesCount, formatAmount(t.proceeds), formatAmount(t.pending)))
      setColor(band.totals, Theme.color.fgMuted)
      if t.realized then
        band.profit:SetText(signedProfit(t.realized))
        setColor(band.profit, t.realized >= 0 and Theme.color.green or Theme.color.red)
        band.profitLabel:Show()
      end
    elseif entry.kind == "age" then
      band.age:SetText((GC.L["data from goldcap.gg · synced %s ago"]):format(
        GC.Util.FormatAge(entry.age)))
      if entry.age >= STALE_RED_SECONDS then
        setColor(band.age, Theme.color.red)
      elseif entry.age >= STALE_YELLOW_SECONDS then
        setColor(band.age, Theme.tier.SUSPECT)
      else
        setColor(band.age, Theme.color.fgDim)
      end
    else
      listEntries[#listEntries + 1] = entry
    end
  end

  for i = #rows + 1, #listEntries do rows[i] = createRow(content) end
  local y = 0
  for i, entry in ipairs(listEntries) do
    local row = rows[i]
    local h = heightFor(entry.kind)
    row:SetHeight(h)
    -- TOPLEFT + TOPRIGHT, not TOPLEFT plus a size fixed at creation (I2):
    -- the row's own width then always tracks content's, which
    -- updateContentWidth keeps current with the real window/dock width.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    paintRow(row, entry, i)
    row:Show()
    y = y + h
  end
  for i = #listEntries + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, y))
end

-- Builds the tab's container, hidden, filling the same region the Deals
-- scroll occupies -- geometry passed through from createFrame, never
-- re-declared, exactly like GC.Sell.Attach. Inside it: the header band
-- (createBand), the column header row (createHeaderRow), then the scroll
-- holding the data/section/hint rows -- same top-to-bottom shape as Sell's
-- own summary-band / header-row / scroll stack.
function GC.Sold.Attach(f, geo)
  Theme = GC.Theme
  geometry = geo
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()

  -- Establishes the correct drop state up front from the starting width,
  -- the same M8-style reasoning Deals uses: the very first header/row
  -- layout should already reflect it instead of waiting for a resize.
  hiddenColumns = computeHidden(geo.rowWidth or 0)

  band = createBand(container)

  local header = createHeaderRow(container)
  header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -SD.BAND_HEIGHT)
  header:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -SD.BAND_HEIGHT)
  -- Not read by any production code -- attached purely so the behavior spec
  -- can reach the column header's own cells through the same `band`
  -- upvalue it already uses for the summary lines, instead of adding a
  -- second debug.getupvalue chain just for this.
  band.header = header

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
  scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(SD.BAND_HEIGHT + SD.HEADER_H + Theme.pad.xs))
  scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, geo.rowHeight)
  scroll:SetScrollChild(content)
  -- OnSizeChanged is the live path (dragging the window's resize grip, or
  -- the AH tab reparenting it into a different-width dock); Show() below is
  -- the catch-up path for a frame that was hidden while that happened, since
  -- a hidden frame does not reliably fire OnSizeChanged (I2).
  container:HookScript("OnSizeChanged", function(_, width)
    if not width or width <= 0 then return end
    geometry.rowWidth = width
    content:SetWidth(width)
    applyColumnVisibility(width)
  end)
end

function GC.Sold.Show()
  if container then
    container:Show()
    restampHeadings() -- see its comment: a heading can come back from a hide undrawn
    updateContentWidth()
    renderRows()
  end
end

function GC.Sold.Hide()
  if container then container:Hide() end
end

-- Called from GC.Ledger.ScanInbox's fan-out so a mailbox scan updates the
-- local section live while the tab is up. `rows`/`band` are referenced
-- directly here so the behavior spec can reach the row pool and the header
-- band via debug.getupvalue -- same pattern the Sell specs use.
function GC.Sold.RefreshIfShown()
  if container and container:IsShown() and rows and band then renderRows() end
end
