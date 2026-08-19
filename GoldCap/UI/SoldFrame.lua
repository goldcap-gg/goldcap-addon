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
  if amount == nil then return "Unknown" end
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
        text = "Profit tracking is a goldcap.gg Pro feature" }
    end
  else
    entries[#entries + 1] = { kind = "hint",
      text = "Pair or update the GoldCap Companion to see profit from goldcap.gg" }
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
      text = "Not on goldcap.gg yet -- syncs on /reload or logout" }
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
    local header = ("On goldcap.gg -- last %d days"):format(summary.days)
    if summary.totals.salesCount > #summary.sales then
      header = ("On goldcap.gg -- last %d days, latest %d of %d"):format(
        summary.days, #summary.sales, summary.totals.salesCount)
    end
    entries[#entries + 1] = { kind = "section", text = header }
    for _, sale in ipairs(summary.sales) do
      entries[#entries + 1] = { kind = "serverSale", sale = sale }
    end
  end

  if #localSales == 0 and not (summary and #summary.sales > 0) then
    entries[#entries + 1] = { kind = "hint",
      text = "No sales recorded yet -- open your mailbox with GoldCap loaded" }
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
  BAND_LINE2_Y = -18,
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

local HEADER_TEXT = { item = "ITEM", when = "WHEN", qty = "QTY", unit = "UNIT",
                       total = "TOTAL", profit = "PROFIT" }

-- Anchors every visible fixed COLUMNS entry's RIGHT edge right-to-left off
-- `host`'s own RIGHT edge, skipping any key present in `hidden`; returns the
-- flex ("item") column's anchor pair for the caller to anchor the item
-- text's RIGHT edge to. Identical in shape to SniperFrame's anchorColumns --
-- duplicated rather than shared, the same way SellFrame's own column layout
-- is its own copy: these locals do not cross files (see addon/AGENTS.md on
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
  local decorated = (itemID and Theme.WithQuality and Theme.WithQuality(name, itemID, 11)) or name
  row.item:SetText(decorated)
  setColor(row.item, Theme.color.fg)

  -- The sale exists, the gold is just in transit -- same honesty the old
  -- "[not yet paid out]" suffix carried, now the WHEN column's own content
  -- rather than an appendix to it.
  row.cells.when:SetText(pending and "in the mail" or formatWhen(at))
  setColor(row.cells.when, Theme.color.fgDim)

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
local function clearRow(row)
  row.item:SetText("")
  row.item:Show()
  row.wide:SetText("")
  row.wide:Hide()
  row.underline:Hide()
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
  row.zebra:SetColorTexture(zc[1], zc[2], zc[3], (index % 2 == 1) and (zc[4] or 0) or 0)

  if entry.kind == "hint" then
    -- Centered, muted, in the list area -- Deals' empty-state language --
    -- rather than a top-left label. A hint can appear alongside real rows
    -- (the Pro notice sits above server rows that still render), so it
    -- stays a row in the same flow instead of a separate overlay widget.
    row.item:Hide()
    for _, col in ipairs(COLUMNS) do
      if not col.flex then row.cells[col.key]:Hide() end
    end
    row.wide:Show()
    row.wide:SetJustifyH("CENTER")
    row.wide:SetWordWrap(true)
    row.wide:SetText(entry.text)
    setColor(row.wide, Theme.color.fgMuted)
  elseif entry.kind == "section" then
    -- Full-width gold label with a thin gold underline -- the Sell
    -- group-row aesthetic, adapted: Sell's group text lives in the flexible
    -- item column because its siblings still show blank cells beside it;
    -- Sold's section rows have nothing to say in QTY/UNIT/TOTAL/PROFIT at
    -- all, so the label spans the row outright.
    row.item:Hide()
    for _, col in ipairs(COLUMNS) do
      if not col.flex then row.cells[col.key]:Hide() end
    end
    row.wide:Show()
    row.wide:SetJustifyH("LEFT")
    row.wide:SetWordWrap(false)
    row.wide:SetText(entry.text)
    setColor(row.wide, Theme.color.gold)
    row.underline:Show()
  elseif entry.kind == "localSale" then
    local sale = entry.sale
    paintSaleCells(row, sale.itemName or "Unknown item", sale.itemID, sale.qty or 0,
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
    elseif basis then
      row.cells.profit:SetText("cost unknown")
      setColor(row.cells.profit, Theme.color.fgDim)
    end
    -- else: free tier, no basis at all -- row.cells.profit stays "" (M2/
    -- design: "free tier (no basis) -> empty"), never an invented dash.
  end
end

layoutRow = function(row)
  local flexAnchor = anchorColumns(row, hiddenColumns, function(col) return row.cells[col.key] end)
  row.item:ClearAllPoints()
  row.item:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.item:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
end

createRow = function(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(geometry.rowHeight)

  -- Zebra + hover, same convention as Deals/Sell: a full-width BACKGROUND
  -- zebra fill, recomputed every render off the row's CURRENT position
  -- (Sell's approach -- Sold's entry composition reshuffles kind-to-kind far
  -- more than Deals' pool ever does, so baking zebra in at creation time,
  -- the way Deals does, would go stale the moment a section appears above a
  -- row that used to sit at an even index).
  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints()
  zebra:SetColorTexture(zc[1], zc[2], zc[3], 0)
  row.zebra = zebra

  -- Hover: the real engine HIGHLIGHT draw layer, shown/hidden by the client
  -- itself for as long as the cursor is over a mouse-enabled frame -- never
  -- an OnEnter/OnLeave repaint (addon/AGENTS.md's "Buttons and hover").
  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(hc[1], hc[2], hc[3], hc[4])
  row.highlight = highlight
  row:EnableMouse(true)

  -- Thin gold underline, shown only for a "section" row.
  local gc = Theme.color.gold
  local underline = row:CreateTexture(nil, "ARTWORK")
  underline:SetHeight(1)
  underline:SetPoint("BOTTOMLEFT")
  underline:SetPoint("BOTTOMRIGHT")
  underline:SetColorTexture(gc[1], gc[2], gc[3], 0.6)
  underline:Hide()
  row.underline = underline

  -- The full-row text used by "section" and "hint" kinds -- see paintRow.
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
      local label = Theme.Label(hit, 11)
      label:SetAllPoints()
      label:SetJustifyH(col.num and "RIGHT" or "LEFT")
      label:SetText((HEADER_TEXT[col.key] or ""):upper())
      hit.label = label
      header.cells[col.key] = hit
    end
  end

  local itemHit = CreateFrame("Frame", nil, header)
  itemHit.label = Theme.Label(itemHit, 11)
  itemHit.label:SetAllPoints()
  itemHit.label:SetJustifyH("LEFT")
  itemHit.label:SetText(HEADER_TEXT.item)

  headerLayout = function()
    local flexAnchor = anchorColumns(header, hiddenColumns, function(col) return header.cells[col.key] end)
    itemHit:ClearAllPoints()
    itemHit:SetPoint("TOPLEFT", header, "TOPLEFT")
    itemHit:SetPoint("BOTTOMRIGHT", flexAnchor.frame, "BOTTOMLEFT", -Theme.pad.s, 0)
  end
  headerLayout()

  return header
end

-- The header band: two persistent lines above the table (totals + realized
-- profit, then sync age), not table rows -- SellFrame's header-band
-- convention, styled with this tab's own font sizes/spacing rather than its
-- code. `totals` line 1 and `age` line 2 are plain Theme.Label; `profit` is
-- Theme.Num bold and larger, matching "realized profit right in bold
-- green/red".
local function createBand(parent)
  local profit = Theme.Num(parent, 15, true)
  profit:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

  local totals = Theme.Label(parent, 11)
  totals:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  totals:SetPoint("RIGHT", profit, "LEFT", -Theme.pad.s, 0)
  totals:SetJustifyH("LEFT")
  totals:SetWordWrap(false)

  local age = Theme.Label(parent, 10)
  age:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, SD.BAND_LINE2_Y)
  age:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, SD.BAND_LINE2_Y)
  age:SetJustifyH("LEFT")
  age:SetWordWrap(false)

  return { totals = totals, profit = profit, age = age }
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
  local listEntries = {}
  for _, entry in ipairs(entries) do
    if entry.kind == "totals" then
      local t = entry.summary.totals
      band.totals:SetText(("%d sales -- %s proceeds -- %s in the mail"):format(
        t.salesCount, formatAmount(t.proceeds), formatAmount(t.pending)))
      setColor(band.totals, Theme.color.fg)
      if t.realized then
        band.profit:SetText(signedProfit(t.realized))
        setColor(band.profit, t.realized >= 0 and Theme.color.green or Theme.color.red)
      end
    elseif entry.kind == "age" then
      band.age:SetText(("data from goldcap.gg -- synced %s ago"):format(
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
