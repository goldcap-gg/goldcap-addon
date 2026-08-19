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
GC.Sold = {}

local Theme
local container, content
local rows = {}
local geometry

-- Same thresholds the Deals staleness line uses (SniperFrame's LIM table is
-- file-local; two constants are cheaper than a cross-file export).
local STALE_YELLOW_SECONDS = 6 * 3600
local STALE_RED_SECONDS = 24 * 3600

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
  -- min() guards companion clock skew: a generatedAt from the future would
  -- otherwise swallow every local row.
  local boundary = summary and math.min(summary.generatedAt, now) or 0

  if summary then
    entries[#entries + 1] = { kind = "totals", summary = summary }
    entries[#entries + 1] = { kind = "age", age = math.max(0, now - summary.generatedAt) }
    if not summary.pro then
      entries[#entries + 1] = { kind = "hint",
        text = "Profit tracking is a goldcap.gg Pro feature" }
    end
  else
    entries[#entries + 1] = { kind = "hint",
      text = "Pair the GoldCap Companion to see profit from goldcap.gg" }
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
    entries[#entries + 1] = { kind = "section",
      text = ("On goldcap.gg -- last %d days"):format(summary.days) }
    for _, sale in ipairs(summary.sales) do
      entries[#entries + 1] = { kind = "serverSale", sale = sale, pro = summary.pro }
    end
  end

  if #localSales == 0 and not (summary and #summary.sales > 0) then
    entries[#entries + 1] = { kind = "hint",
      text = "No sales recorded yet -- open your mailbox with GoldCap loaded" }
  end

  return entries
end

local function paintSaleLeft(row, name, itemID, qty, total, at, pending)
  local decorated = (itemID and Theme.WithQuality and Theme.WithQuality(name, itemID, 11)) or name
  row.left:SetText(("%dx %s"):format(qty, decorated))
  setColor(row.left, Theme.color.fg)
  -- Per-unit leads, /goldcap sales convention: "what did that actually sell
  -- for" is a per-unit question.
  local sub = formatWhen(at)
  if qty and qty > 0 and type(total) == "number" then
    local unit = ("at %s each"):format(formatAmount(math.floor(total / qty)))
    sub = sub == "" and unit or (sub .. "  " .. unit)
  end
  if pending then sub = sub .. "  [not yet paid out]" end
  row.leftSub:SetText(sub)
  setColor(row.leftSub, Theme.color.fgDim)
end

local function paintRow(row, entry)
  row.left:SetText("")
  row.leftSub:SetText("")
  row.right:SetText("")
  row.rightSub:SetText("")

  if entry.kind == "totals" then
    local t = entry.summary.totals
    row.left:SetText(("%d sales -- %s proceeds -- %s in the mail"):format(
      t.salesCount, formatAmount(t.proceeds), formatAmount(t.pending)))
    setColor(row.left, Theme.color.fg)
    if t.realized then
      row.right:SetText(signedProfit(t.realized))
      setColor(row.right, t.realized >= 0 and Theme.color.green or Theme.color.red)
    end
  elseif entry.kind == "age" then
    row.left:SetText(("data from goldcap.gg -- synced %s ago"):format(
      GC.Util.FormatAge(entry.age)))
    if entry.age >= STALE_RED_SECONDS then
      setColor(row.left, Theme.color.red)
    elseif entry.age >= STALE_YELLOW_SECONDS then
      setColor(row.left, Theme.tier.SUSPECT)
    else
      setColor(row.left, Theme.color.fgDim)
    end
  elseif entry.kind == "hint" then
    row.left:SetText(entry.text)
    setColor(row.left, Theme.color.fgMuted)
  elseif entry.kind == "section" then
    row.left:SetText(entry.text)
    setColor(row.left, Theme.color.gold)
  elseif entry.kind == "localSale" then
    local sale = entry.sale
    paintSaleLeft(row, sale.itemName or "Unknown item", sale.itemID, sale.qty or 0,
      sale.total, sale.at, sale.pending)
    row.right:SetText(formatAmount(sale.total))
    setColor(row.right, Theme.color.fg)
    if entry.realized and type(entry.realized.profit) == "number" then
      row.rightSub:SetText(signedProfit(entry.realized.profit))
      setColor(row.rightSub, entry.realized.profit >= 0 and Theme.color.green or Theme.color.red)
    else
      row.rightSub:SetText("--")
      setColor(row.rightSub, Theme.color.fgDim)
    end
  elseif entry.kind == "serverSale" then
    local sale = entry.sale
    paintSaleLeft(row, sale.name, sale.item, sale.qty, sale.total, sale.at, sale.pending)
    row.right:SetText(formatAmount(sale.total))
    setColor(row.right, Theme.color.fg)
    local basis = sale.basis
    if basis and basis.matched > 0 then
      local text = signedProfit(basis.profit)
      if basis.unmatched > 0 then
        text = text .. ("  %d/%d"):format(basis.matched, sale.qty)
      end
      row.rightSub:SetText(text)
      setColor(row.rightSub, basis.profit >= 0 and Theme.color.green or Theme.color.red)
    elseif basis then
      row.rightSub:SetText("cost unknown")
      setColor(row.rightSub, Theme.color.fgDim)
    end
  end
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(geometry.rowWidth, geometry.rowHeight)
  row.left = Theme.Label(row, 11)
  row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
  row.left:SetPoint("RIGHT", row, "RIGHT", -170, 0)
  row.left:SetJustifyH("LEFT")
  row.left:SetWordWrap(false)
  row.leftSub = Theme.Label(row, 9)
  row.leftSub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 3)
  row.leftSub:SetPoint("RIGHT", row, "RIGHT", -170, 0)
  row.leftSub:SetJustifyH("LEFT")
  row.leftSub:SetWordWrap(false)
  row.right = Theme.Num(row, 12)
  row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -3)
  row.rightSub = Theme.Label(row, 9)
  row.rightSub:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 3)
  row.rightSub:SetJustifyH("RIGHT")
  return row
end

local function renderRows()
  if not content then return end
  local entries = buildEntries()
  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  for i, entry in ipairs(entries) do
    local row = rows[i]
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * geometry.rowHeight)
    paintRow(row, entry)
    row:Show()
  end
  for i = #entries + 1, #rows do rows[i]:Hide() end
  content:SetSize(geometry.rowWidth, math.max(1, #entries * geometry.rowHeight))
end

-- Builds the tab's container, hidden, filling the same region the Deals
-- scroll occupies -- geometry passed through from createFrame, never
-- re-declared, exactly like GC.Sell.Attach.
function GC.Sold.Attach(f, geo)
  Theme = GC.Theme
  geometry = geo
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT")
  scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, geo.rowHeight)
  scroll:SetScrollChild(content)
end

function GC.Sold.Show()
  if container then
    container:Show()
    renderRows()
  end
end

function GC.Sold.Hide()
  if container then container:Hide() end
end

-- Called from GC.Ledger.ScanInbox's fan-out so a mailbox scan updates the
-- local section live while the tab is up. `rows` is referenced here so the
-- behavior spec can reach the pool via debug.getupvalue -- same pattern the
-- Sell specs use.
function GC.Sold.RefreshIfShown()
  if container and container:IsShown() and rows then renderRows() end
end
