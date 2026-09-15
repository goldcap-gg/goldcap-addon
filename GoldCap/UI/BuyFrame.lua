local _, GC = ...

-- The BUY tab: one shopping run at a time, rendered as "what do I still need, what have I
-- already got, what should the rest cost". The arithmetic is entirely Core/BuyRun.lua's --
-- this file owns only the picking of the run, the four things the client alone can answer
-- (bag counts, market value, the price cap setting, the free-line limit), and the drawing.
--
-- Nothing here buys anything yet. Every row's BUY button is built and immediately disabled:
-- a purchase must be reached from the player's own hardware click (addon/AGENTS.md's
-- "Protected actions"), and the click handler that does it lands with the purchase slot in a
-- later task. The button exists now so the column's width and the row's shape are settled
-- against real labels rather than guessed at later.
--
-- Presentation is the Sold tab's (UI/SoldFrame.lua): one COLUMNS table driving both the
-- header row and every pooled row, responsive column drop in a declared priority order,
-- zebra/hover through the engine's own HIGHLIGHT layer. Duplicated rather than shared -- as
-- Sold duplicates it from Deals -- because these locals do not cross files.
GC.Buy = {}

local Theme
local container, content
local rows = {}
local geometry
local band

-- The BuyRun object for the run currently on screen (nil until one is picked), the
-- `updatedAt` of the AppRuns run it was built from (see ensureRun), and the itemID -> count
-- map its `haveOf` driver reads. Module-local so the whole file agrees on one answer.
local current, currentUpdatedAt
local bagStock = {}

-- The header says "in bags", so the walk covers exactly the bags: the backpack and the five
-- carried bags. Bank and reagent-bank stock is not in the player's bags and must not be
-- counted as though a trip to the auction house could skip it.
local BUY_BAGS = { 0, 1, 2, 3, 4, 5 }

-- Not a translatable string: a glyph standing in for a number nobody has measured yet.
local EM_DASH = "—"

local BD = {
  BAND_HEIGHT = 44, -- header band: the run picker + two text lines above the table
  HEADER_H = 16,    -- column header row height, matches Deals' CH.HEADER
  -- How long a NOW price is allowed to stand before this tab asks again. Twenty seconds is
  -- the shopping rhythm, not a network budget: the batch costs one throttled message, and a
  -- player working down a run is buying a line every ten to thirty seconds, so anything much
  -- longer has them clicking BUY against a price the board learned two purchases ago.
  REFRESH_SECONDS = 20,
  -- Blizzard's hard ceiling for one SearchForItemKeys call (Core/KeyPoll.lua's MAX_BATCH); a
  -- run longer than this loses its tail rather than disconnecting the client.
  MAX_KEYS = 100,
}

-- When the last batch's answer landed. Zero means "never", which is what makes the first ask
-- on Show() free. Advanced by FoldRefresh alone, not by the send: a batch the client swallowed
-- leaves this where it was, so the next tick retries instead of waiting out a refresh window
-- for prices that never arrived.
local lastRefreshAt = 0

local function setColor(fontString, color)
  if fontString and color then
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  end
end

-- Mirrors SellFrame/SoldFrame's formatAmount: plain "65g24s" text, coin icons only below one
-- gold (icon escapes truncate mid-escape in clipped FontStrings).
local function formatAmount(amount)
  if amount == nil then return EM_DASH end
  if amount < 0 then return "-" .. formatAmount(-amount) end
  if amount >= 10000 then
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
  end
  return GetCoinTextureString(amount)
end

local COLUMNS = {
  { key = "reagent", flex = true, min = 140 },
  { key = "need",   w = 36, num = true, size = 11 },
  { key = "have",   w = 36, num = true, size = 11 },
  { key = "buy",    w = 36, num = true, size = 11, bold = true },
  { key = "now",    w = 66, num = true, size = 11, optional = true },
  { key = "usual",  w = 66, num = true, size = 11, optional = true },
  { key = "cost",   w = 72, num = true, size = 11 },
  { key = "action", w = 80, center = true },
}

-- Already uppercase in the key, and never passed through :upper() -- Lua's upper is byte-wise
-- and would leave every non-ASCII letter in a translated heading alone, coming back half-cased.
-- Keys, not translations: this table is built at FILE SCOPE and GC.L only resolves once
-- ApplyLocale has run at ADDON_LOADED, so headerText() below looks up where the header is
-- actually built.
-- @localised-keys: literals in this table ARE GC.L keys; see the comment above for why the
-- lookup happens where the table is read rather than where it is built. The table has to close
-- with a `}` on its own line -- that is where the spec's scanner stops.
local HEADER_TEXT = {
  reagent = "REAGENT", need = "NEED", have = "HAVE", buy = "BUY",
  now = "NOW", usual = "USUAL", cost = "COST", action = "ACTION",
}
local function headerText(key) return GC.L[HEADER_TEXT[key] or ""] end

-- Drop priority, spelled out rather than derived from COLUMNS' order (Sold derives it, and can
-- only because its optional columns happen to sit in priority order). USUAL goes first: it is
-- the reference price, and a shopper who has lost a column would rather keep NOW, which is
-- what the next click actually pays.
local OPTIONAL_KEYS, DROP_THRESHOLDS = { "usual", "now" }, { 130, 100 }

-- Anchors every visible fixed COLUMNS entry's RIGHT edge right-to-left off `host`'s own RIGHT
-- edge, skipping any key present in `hidden`; returns the flex ("reagent") column's anchor pair.
-- Identical in shape to SoldFrame's/SniperFrame's anchorColumns.
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
    local reagentWidth = containerWidth - fixedColumnBudget(hidden)
    if reagentWidth < DROP_THRESHOLDS[i] then
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

local hiddenColumns = {}

local createRow, layoutRow, headerLayout

local function applyColumnVisibility(containerWidth)
  if not headerLayout then return end
  local newHidden = computeHidden(containerWidth)
  if sameHidden(newHidden, hiddenColumns) then return end
  hiddenColumns = newHidden
  headerLayout()
  for i = 1, #rows do layoutRow(rows[i]) end
end

-- ---------------------------------------------------------------------------
-- The run, and what only the client knows about it
-- ---------------------------------------------------------------------------

local function settings()
  local db = GC.db
  local s = type(db) == "table" and db.settings or nil
  local sniper = type(s) == "table" and s.sniper or nil
  return type(sniper) == "table" and sniper or nil
end

-- Bag stock, from the same C_Container walk UI/SellFrame.lua's scanBagStock uses. The classify
-- hook is deliberately NOT Sell's: Sell has to tell a commodity from a bonus-id bearing item
-- because it posts them differently, and returns nil -- dropping the stack -- when it cannot.
-- This tab only ever asks "how many of item N am I already carrying", so it keys on the item id
-- alone; borrowing Sell's rule would silently under-count every stack the auction house API has
-- not classified yet and send the player shopping for what is already in the bag.
local function scanBags()
  bagStock = {}
  if not GC.BagStock then return end
  local entries = GC.BagStock.Scan({
    numSlots = function(bag)
      return C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    end,
    itemInfo = function(bag, slot)
      if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if type(info) ~= "table" then return nil end
      return {
        itemID = info.itemID, stackCount = info.stackCount,
        -- isBound is deliberately dropped, not forwarded. GC.BagStock.Scan skips a bound stack
        -- because the auction house refuses to POST it (Core/BagStock.lua) -- a Sell rule. This
        -- tab asks a different question: a soulbound reagent sitting in the bags is still a
        -- reagent the player does not have to buy, and crafting does not care how it got bound.
        -- Forwarding the flag made HAVE under-count and sent the player shopping for what they
        -- were already carrying.
        isBound = nil,
        hasNoValue = info.hasNoValue, itemName = info.itemName,
        hyperlink = info.hyperlink
          or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or nil,
      }
    end,
    classify = function(itemID) return ("buy:%d"):format(itemID), nil end,
  }, BUY_BAGS)
  -- Folded into itemID -> count here, once per scan, rather than re-walked per line: `haveOf`
  -- is called for every line of every Refresh(), and a run is dozens of lines long.
  for _, entry in ipairs(entries) do
    bagStock[entry.itemID] = (bagStock[entry.itemID] or 0) + (entry.quantity or 0)
  end
end

local function haveOf(itemID)
  return bagStock[itemID] or 0
end

local function usualUnit(itemID)
  local value = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(itemID)
  return type(value) == "table" and value.mv or nil
end

local DRIVER = {
  now = function() return time() end,
  haveOf = haveOf,
  usualUnit = usualUnit,
  capPct = function()
    local sniper = settings()
    return (sniper and sniper.buyCapPct) or 130
  end,
  freeLines = function()
    return GC.AppRuns and GC.AppRuns.FreeLines and GC.AppRuns.FreeLines() or nil
  end,
}

local function runList()
  return (GC.AppRuns and GC.AppRuns.List and GC.AppRuns.List()) or {}
end

-- The run's own name if the site gave it one, otherwise its code -- never an invented label.
local function runLabel(run)
  return (run and (run:Name() or run:Code())) or ""
end

function GC.Buy.CurrentRun() return current end

-- Adopts `code` as the shown run and remembers it. A code with no run behind it (the companion
-- dropped it on its next sync, or the saved preference outlived the run) clears the board
-- rather than resurrecting a stale copy.
function GC.Buy.SelectRun(code)
  local run = code and GC.AppRuns and GC.AppRuns.Get and GC.AppRuns.Get(code) or nil
  local sniper = settings()
  -- A new BuyRun object carries no floors at all, so the twenty-second window that was
  -- protecting the OLD run's prices is now protecting nothing -- it would just hold every NOW
  -- cell on an em dash for up to twenty seconds after a cycle-run click or a companion sync
  -- that rebuilt the run under ensureRun(). The window belongs to a run's prices, not to the
  -- tab, so it is given up with them. Reset before the early return too: clearing the board is
  -- just as much a replacement, and the next run picked must not inherit a stale window.
  lastRefreshAt = 0
  if not run then
    current, currentUpdatedAt = nil, nil
    if sniper then sniper.buyRun = nil end
    return
  end
  if sniper then sniper.buyRun = run.code end
  current = GC.BuyRun.New(run, DRIVER)
  currentUpdatedAt = run.updatedAt
  current:Refresh()
end

-- Picks up the remembered run, falling back to the first the list offers (app runs first,
-- newest first -- Core/AppRuns.lua's own order), so a first visit lands on something rather
-- than on the empty state with runs sitting right there.
-- Returns whether it (re)built `current`, so Show() can skip a second Refresh() of a run that
-- was just built and refreshed.
local function ensureRun()
  local list = runList()
  if #list == 0 then
    current, currentUpdatedAt = nil, nil
    return false
  end
  local sniper = settings()
  local wanted = sniper and sniper.buyRun
  for _, run in ipairs(list) do
    if run.code == wanted then
      -- Already on it: keep the BuyRun object rather than rebuilding it, so what this session
      -- has already bought against the run survives leaving the tab and coming back.
      --
      -- A run keeps its code across a companion sync while its LINES change (the site's list
      -- was edited, quantities moved), so the code alone does not prove the object is current.
      -- `updatedAt` does -- Core/AppRuns.lua stamps it on every adopted run -- and a newer one
      -- means the object was built from lines that no longer exist. Rebuilding drops this
      -- session's recorded purchases against the old lines, deliberately: they were counted
      -- against quantities the run no longer asks for, and carrying them over would credit
      -- the new lines with buys that were never made for them.
      if not (current and current:Code() == wanted)
          or (run.updatedAt or 0) > (currentUpdatedAt or 0) then
        GC.Buy.SelectRun(run.code)
        return true
      end
      return false
    end
  end
  -- The remembered run is gone (the companion dropped it on its last sync, or it was never
  -- there): fall to the top of the list rather than to the empty state with runs sitting in it.
  GC.Buy.SelectRun(list[1].code)
  return true
end

-- The picker is a cycle, not a dropdown: a player has one or two runs open at a time, and a
-- button that names the next one is a smaller control than a menu for a list that short.
local function cycleRun()
  local list = runList()
  if #list == 0 then return end
  local index = 1
  for i, run in ipairs(list) do
    if current and run.code == current:Code() then
      index = i % #list + 1
      break
    end
  end
  -- One run in the list cycles back onto itself: re-selecting would rebuild the BuyRun object
  -- and forget what this session has already bought against it, for a click that changed
  -- nothing the player can see.
  if current and list[index].code == current:Code() then return end
  GC.Buy.SelectRun(list[index].code)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

-- The one list this tab renders, top to bottom. Vendor lines are already last (Core/BuyRun.lua's
-- Refresh puts them there); this only decides what is a row at all.
local function buildEntries()
  local entries = {}
  if not current then
    entries[#entries + 1] = { kind = "hint", text =
      GC.L["No runs yet. Save a list with quantities on goldcap.gg, or paste a run string in Import."] }
    return entries
  end
  local locked = 0
  for _, line in ipairs(current:Lines()) do
    if line.locked then locked = locked + 1 end
    entries[#entries + 1] = { kind = "line", line = line }
  end
  if locked > 0 then
    entries[#entries + 1] = { kind = "hint", text = (GC.L["%d more lines with Pro"]):format(locked) }
  end
  return entries
end

local function heightFor(kind)
  if kind == "hint" then return geometry.rowHeight * 2 end
  return geometry.rowHeight
end

-- The client's own name for the line's item. A run from the companion carries one; a pasted
-- GCR1 string carries none (Core/AppRuns.lua's ImportString), and an item the client has never
-- cached answers nothing at all -- so the id itself is the last honest fallback.
local function lineName(line)
  if line.name then return line.name end
  if C_Item and C_Item.GetItemInfo then
    local ok, name = pcall(C_Item.GetItemInfo, line.itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return "#" .. tostring(line.itemID)
end

local function buildRowCell(row, col)
  local fs
  if col.num then
    fs = Theme.Num(row, col.size or 11, col.bold)
  else
    fs = Theme.Label(row, col.size or 11)
    fs:SetJustifyH(col.center and "CENTER" or "LEFT")
  end
  fs:SetWordWrap(false)
  return fs
end

local function clearRow(row)
  row.reagent:SetText("")
  row.reagent:Show()
  row.wide:SetText("")
  row.wide:Hide()
  row.action:Hide()
  row.pro:Hide()
  row.reagentInset = 0
  row.icon:Hide()
  row.tooltipItemID = nil
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

local function paintLine(row, line)
  row.tooltipItemID = line.itemID
  local name = lineName(line)
  local decorated = (Theme.WithQuality and Theme.WithQuality(name, line.itemID, 11)) or name
  row.reagent:SetText(decorated)
  -- A vendor line is not something this tab can act on -- the whole row reads back, so it does
  -- not compete with the lines the player is actually here to buy.
  setColor(row.reagent, line.vendor and Theme.color.fgDim or Theme.color.fg)

  local icon = nil
  if C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, line.itemID)
    icon = ok and texture or nil
  end
  row.reagentInset = icon and 26 or 0
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end

  row.cells.need:SetText(tostring(line.need))
  setColor(row.cells.need, Theme.color.fgDim)
  row.cells.have:SetText(tostring(line.have))
  setColor(row.cells.have, line.have > 0 and Theme.color.fg or Theme.color.fgDim)
  row.cells.buy:SetText(tostring(line.buy))
  setColor(row.cells.buy, line.buy > 0 and Theme.color.gold or Theme.color.fgDim)

  -- NOW is the best unit price actually seen for this item; nothing has looked yet on a fresh
  -- run, and an em dash says so rather than borrowing the USUAL beside it.
  row.cells.now:SetText(formatAmount(line.floor))
  setColor(row.cells.now, line.floor and Theme.color.fg or Theme.color.fgDim)
  row.cells.usual:SetText(formatAmount(line.usual))
  setColor(row.cells.usual, Theme.color.fgDim)

  -- What the rest of this line should cost at the best price known for it. With neither a seen
  -- floor nor a market value there is no honest number, so the cell stays an em dash.
  local unit = line.floor or line.usual
  row.cells.cost:SetText(unit and formatAmount(line.buy * unit) or EM_DASH)
  setColor(row.cells.cost, Theme.color.fg)

  if line.vendor then
    row.cells.action:SetText(GC.L["vendor"])
    setColor(row.cells.action, Theme.color.fgDim)
  elseif line.done then
    row.cells.action:SetText(GC.L["done"])
    setColor(row.cells.action, Theme.color.fgDim)
  elseif line.locked then
    row.pro:SetLabel(GC.L["Pro"], Theme.color.gold)
    row.pro:Show()
  else
    row.action:SetLabel((GC.L["BUY %d"]):format(line.buy))
    -- Disabled on purpose: see this file's header. The control is built, sized and labelled,
    -- and the click that spends gold arrives with the purchase slot.
    row.action:Disable()
    row.action:Show()
  end
end

local function paintRow(row, entry, index)
  clearRow(row)

  local zc = Theme.color.zebra
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], (index % 2 == 1) and (zc[4] or 0) or 0)

  if entry.kind == "hint" then
    row.reagent:Hide()
    row.wide:Show()
    row.wide:SetJustifyH("CENTER")
    row.wide:SetWordWrap(true)
    row.wide:SetText(entry.text)
    setColor(row.wide, Theme.color.fgDim)
    row.wide:SetSpacing(4)
  elseif entry.kind == "line" then
    paintLine(row, entry.line)
  end

  -- Re-anchor the reagent cell now that this render's own row.reagentInset is known; rows are
  -- pooled and an index's kind can change between renders (SoldFrame's paintRow carries the
  -- same call for the same reason).
  layoutRow(row)
end

layoutRow = function(row)
  local flexAnchor = anchorColumns(row, hiddenColumns, function(col) return row.cells[col.key] end)
  row.reagent:ClearAllPoints()
  row.reagent:SetPoint("LEFT", row, "LEFT", row.reagentInset or 0, 0)
  row.reagent:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
end

createRow = function(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(geometry.rowHeight)

  -- Zebra + hover, the Sell/Sold convention: a sliced rounded fill recomputed every render off
  -- the row's CURRENT index, since this tab's entry composition reshuffles between renders.
  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  zebra:SetTextureSliceMargins(12, 12, 12, 12)
  zebra:SetPoint("TOPLEFT", 2, -1)
  zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  zebra:SetVertexColor(zc[1], zc[2], zc[3], 0)
  row.zebra = zebra

  -- Hover is the engine's HIGHLIGHT draw layer on a mouse-enabled frame, never an
  -- OnEnter/OnLeave repaint (addon/AGENTS.md's "Buttons and hover").
  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  highlight:SetTextureSliceMargins(12, 12, 12, 12)
  highlight:SetPoint("TOPLEFT", 2, -1)
  highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight = highlight
  row:EnableMouse(true)

  -- The item's own tooltip on hover, the same affordance Deals, Sell and Sold give their rows.
  -- Wired ONCE on the pooled row, reading whatever paintRow last stamped.
  row:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.tooltipItemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.tooltipItemID) end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.icon:Hide()

  -- The full-row text used by the "hint" kind -- the empty state and the locked-lines notice.
  row.wide = Theme.Label(row, 11)
  row.wide:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.wide:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.wide:Hide()

  row.reagent = Theme.Label(row, 11)
  row.reagent:SetWordWrap(false)

  row.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then row.cells[col.key] = buildRowCell(row, col) end
  end

  -- One control with one look, shown only on a line that can actually be bought (paintLine).
  -- 72 inside an 80px column, the same "sized to the longest English label" rule SellFrame's
  -- 86px action button follows.
  row.action = Theme.Button(row, "ghost", "badge")
  row.action:SetSize(72, 18)
  row.action:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  row.action:Hide()

  -- The locked-line marker sits in the same cell the BUY button would have: a line past the
  -- free limit is not a line with no action, it is a line whose action is behind Pro.
  row.pro = Theme.Chip(row)
  row.pro:SetSize(40, 16)
  row.pro:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  row.pro:Hide()

  layoutRow(row)
  return row
end

local function createHeaderRow(parent)
  local header = CreateFrame("Frame", nil, parent)
  header:SetHeight(BD.HEADER_H)
  header.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      local hit = CreateFrame("Frame", nil, header)
      hit:SetHeight(BD.HEADER_H)
      local label = Theme.Num(hit, 9)
      label:SetWordWrap(false)
      -- One line, hard capped: the label is SetAllPoints() onto a BD.HEADER_H-tall cell, and a
      -- line that does not fit the height it is given is not drawn at all.
      label:SetMaxLines(1)
      setColor(label, Theme.color.fgDim)
      label:SetAllPoints()
      label:SetJustifyH(col.num and "RIGHT" or (col.center and "CENTER" or "LEFT"))
      label:SetText(headerText(col.key))
      hit.label = label
      header.cells[col.key] = hit
    end
  end

  local reagentHit = CreateFrame("Frame", nil, header)
  local reagentLabel = Theme.Num(reagentHit, 9)
  reagentLabel:SetWordWrap(false)
  reagentLabel:SetMaxLines(1)
  setColor(reagentLabel, Theme.color.fgDim)
  reagentLabel:SetAllPoints()
  reagentLabel:SetJustifyH("LEFT")
  reagentLabel:SetText(headerText("reagent"))
  reagentHit.label = reagentLabel
  -- Not read by any production code; exposed so the behavior spec can reach the REAGENT cell.
  header.reagentCell = reagentHit

  headerLayout = function()
    local flexAnchor = anchorColumns(header, hiddenColumns, function(col) return header.cells[col.key] end)
    reagentHit:ClearAllPoints()
    reagentHit:SetPoint("TOPLEFT", header, "TOPLEFT")
    reagentHit:SetPoint("BOTTOMRIGHT", flexAnchor.frame, "BOTTOMLEFT", -Theme.pad.s, 0)
  end
  headerLayout()

  local bc = Theme.color.border
  local rule = header:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)
  header.rule = rule

  return header
end

-- The headings are stamped once, at build, and this tab spends most of its life hidden behind
-- Deals. A one-line FontString hidden with its parent can come back with its text simply not
-- drawn (see UI/SniperFrame.lua's updateHeaderSortIndicators for the full story), and SetText
-- is what the client needs to draw it again -- so Show() goes through here.
local function restampHeadings()
  local header = band and band.header
  if not header or not header.cells then return end
  for key, hit in pairs(header.cells) do hit.label:SetText(headerText(key)) end
  if header.reagentCell then header.reagentCell.label:SetText(headerText("reagent")) end
end

-- The header band: the run picker and the run's line counts on one line, the money and the
-- "in bags" legend under them. SellFrame/SoldFrame's header-band convention.
local function createBand(parent)
  local picker = Theme.Button(parent, "ghost", "badge")
  picker:SetSize(150, 20)
  picker:SetPoint("TOPLEFT", 0, -2)
  picker:SetScript("OnClick", function()
    cycleRun()
    GC.Buy.RefreshIfShown()
  end)

  local counts = Theme.Num(parent, 9)
  counts:SetJustifyH("RIGHT")
  counts:SetWordWrap(false)
  counts:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -6)
  counts:SetPoint("LEFT", picker, "RIGHT", Theme.pad.s, 0)
  setColor(counts, Theme.color.fgDim)

  -- What the HAVE column counts, said once rather than in every row: the bags, not the bank.
  -- Anchored first and by its RIGHT edge alone, so its width is its own text -- `spent` below
  -- binds to its LEFT, and binding them to each other in both directions would be circular.
  local bags = Theme.Num(parent, 9)
  bags:SetJustifyH("RIGHT")
  bags:SetWordWrap(false)
  bags:SetPoint("TOPRIGHT", 0, -26)
  bags:SetText(GC.L["in bags"])
  setColor(bags, Theme.color.fgDim)

  local spent = Theme.Num(parent, 10)
  spent:SetJustifyH("LEFT")
  spent:SetWordWrap(false)
  spent:SetPoint("TOPLEFT", 0, -26)
  spent:SetPoint("RIGHT", bags, "LEFT", -Theme.pad.s, 0)
  setColor(spent, Theme.color.fgMuted)

  -- Band rule: a separate frame pinned to the band's own height so the 1px line sits at the
  -- band's bottom edge regardless of where the text above it ends.
  local bandFrame = CreateFrame("Frame", nil, parent)
  bandFrame:SetPoint("TOPLEFT", 0, 0)
  bandFrame:SetPoint("TOPRIGHT", 0, 0)
  bandFrame:SetHeight(BD.BAND_HEIGHT)
  local bc = Theme.color.border
  local rule = bandFrame:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)

  return { picker = picker, counts = counts, spent = spent, bags = bags, rule = rule }
end

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

  if current then
    local totals = current:Totals()
    band.picker:SetLabel(runLabel(current))
    band.picker:Show()
    band.counts:SetText((GC.L["%d lines · %d to buy · %d at the vendor"]):format(
      totals.lines, totals.toBuy, totals.atVendor))
    band.spent:SetText((GC.L["spent %s · left ~%s"]):format(
      formatAmount(totals.spent), formatAmount(totals.left)))
  else
    -- Nothing to name and nothing to count: a picker offering a run that does not exist is
    -- worse than no picker at all.
    band.picker:Hide()
    band.counts:SetText("")
    band.spent:SetText("")
  end

  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  local y = 0
  for i, entry in ipairs(entries) do
    local row = rows[i]
    local h = heightFor(entry.kind)
    row:SetHeight(h)
    -- TOPLEFT + TOPRIGHT so a row's width tracks content's, which updateContentWidth keeps
    -- current with the real window/dock width.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    paintRow(row, entry, i)
    row:Show()
    y = y + h
  end
  for i = #entries + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, y))
end

-- Builds the tab's container, hidden, filling the same region Deals' scroll occupies --
-- geometry passed through from createFrame, never re-declared, exactly like GC.Sold.Attach.
function GC.Buy.Attach(f, geo)
  Theme = GC.Theme
  geometry = geo
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()

  -- Establish the drop state from the starting width, so the first header/row layout already
  -- reflects it instead of waiting for a resize.
  hiddenColumns = computeHidden(geo.rowWidth or 0)

  band = createBand(container)

  local header = createHeaderRow(container)
  header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -BD.BAND_HEIGHT)
  header:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -BD.BAND_HEIGHT)
  -- Not read by any production code -- attached so the behavior spec can reach the column
  -- header's cells through the same `band` upvalue it already uses for the summary lines.
  band.header = header

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(BD.BAND_HEIGHT + BD.HEADER_H + Theme.pad.xs))
  scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, geo.rowHeight)
  scroll:SetScrollChild(content)
  -- OnSizeChanged is the live path (the resize grip, or the AH tab reparenting the window into
  -- a different-width dock); Show() below is the catch-up path for a frame that was hidden
  -- while that happened, since a hidden frame does not reliably fire OnSizeChanged.
  container:HookScript("OnSizeChanged", function(_, width)
    if not width or width <= 0 then return end
    geometry.rowWidth = width
    content:SetWidth(width)
    applyColumnVisibility(width)
  end)
end

function GC.Buy.Show()
  if not container then return end
  container:Show()
  restampHeadings() -- see its comment: a heading can come back from a hide undrawn
  -- The bags move while this tab is hidden; a Show that trusted the last scan would open on
  -- counts from whenever the player last looked.
  scanBags()
  -- SelectRun already refreshes what it builds, so only a run ensureRun left alone needs one.
  local rebuilt = ensureRun()
  if current and not rebuilt then current:Refresh() end
  updateContentWidth()
  renderRows()
  -- Ask for prices the moment the tab is up, rather than waiting for the ticker's next second:
  -- the board draws em dashes until an answer lands, and a second of them is a second of a
  -- shopping list that looks like it does not know anything.
  GC.Buy.TrySendRefresh()
end

function GC.Buy.Hide()
  if container then container:Hide() end
end

function GC.Buy.RefreshIfShown()
  if container and container:IsShown() and rows and band then
    if current then current:Refresh() end
    renderRows()
  end
end

-- ---------------------------------------------------------------------------
-- NOW: the floors, refreshed through the addon's one search slot
-- ---------------------------------------------------------------------------

-- Whether an item is something a keys batch can usefully price. C_AuctionHouse.SearchForItemKeys
-- answers with one aggregate row per item key, which is the whole truth for a commodity and
-- only the cheapest variant for anything carrying bonus ids -- so a gear line's "floor" would
-- be a price for some other item's stats. A run is reagents in practice, but a pasted GCR1
-- string can hold anything. Unknown counts as askable: the client answers nil for an item key
-- it has not cached yet, and refusing those would leave a fresh session's whole run unpriced.
local function askableItem(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.MakeItemKey) then
    return true
  end
  local ok, info = pcall(function()
    return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
  end)
  if not ok or type(info) ~= "table" or info.isCommodity == nil then return true end
  return info.isCommodity == true
end

-- The ids this run still has a reason to price: open (something left to buy), unlocked (a Pro
-- line has no BUY button to spend the price on), not a vendor line (the auction house has no
-- answer about it and the row is greyed out anyway). Deduplicated -- a run may name the same
-- reagent twice -- because a duplicate key spends a slot in a batch that is capped.
local function refreshTargets()
  if not current then return nil end
  local ids, seen = {}, {}
  for _, line in ipairs(current:Lines()) do
    if not line.vendor and not line.locked and not line.done and not seen[line.itemID]
        and askableItem(line.itemID) then
      seen[line.itemID] = true
      ids[#ids + 1] = line.itemID
      if #ids >= BD.MAX_KEYS then break end
    end
  end
  return ids
end

-- Asks UI/SniperFrame.lua's arbiter for the one outstanding keys batch this addon allows, on
-- this tab's behalf. Every addon-wide rule (no second batch, not across a book pass's browse
-- buffer, not while the player is on Blizzard's own panes, and the throttle claim) lives
-- there; what belongs here is only what BUY alone knows -- the tab is on screen, a run is
-- shown, and the last answer is old enough to be worth replacing. Returns whether a batch went.
function GC.Buy.TrySendRefresh(playerBusy)
  if not (container and container:IsShown() and current) then return false end
  if not (GC.Sniper and GC.Sniper._TrySendKeysBatchFor and GC.Sniper.CurrentView
      and GC.Sniper.IsAHOpen) then return false end
  -- No auction house session, no question to ask. This window outlives the auction house --
  -- it can be re-shown with /goldcap with yesterday's board still in it -- so a rail click to
  -- BUY lands here with nothing to query against, and a SearchForItemKeys nobody will ever
  -- answer would hold the addon-wide keys interlock shut for the full thirty-second timeout.
  -- Same gate, same reason, as canDrillNow's first line in UI/SniperFrame.lua.
  if not GC.Sniper.IsAHOpen() then return false end
  if (time() - lastRefreshAt) < BD.REFRESH_SECONDS then return false end
  -- refreshTargets is handed to the arbiter rather than called here: it walks the whole run
  -- asking the client about every line's item key, and this function runs once a second off
  -- the auction house ticker. Inside NextBatch it runs only on the tick that has already
  -- cleared every gate and taken the throttle claim -- at most once per batch actually sent.
  -- An empty answer is the arbiter's to handle, and it does (it sends nothing).
  return GC.Sniper._TrySendKeysBatchFor({
    HasPending = function() return true end,
    NextBatch = refreshTargets,
  }, "buy", function() return GC.Sniper.CurrentView() == "buy" end, playerBusy) and true or false
end

-- The once-a-second nudge from UI/SniperFrame.lua's auction-house ticker. A ready tick is not
-- enough on its own: Auto is paused for as long as this tab is up, so on a quiet client
-- nothing else sends anything and no readiness event ever fires.
function GC.Buy.Tick()
  GC.Buy.TrySendRefresh()
end

-- The batch's answer, routed here by GC.Sniper._FoldKeysBatch because this tab is what asked.
-- Browse rows are one aggregate per item key: `minPrice` is the cheapest unit on the realm,
-- which is exactly what NOW claims to be. An item the answer does not mention keeps the floor
-- it had -- unlike the Items board, silence here is not news (a run line the auction house has
-- nothing for is simply unbuyable right now), and blanking it would throw away the only price
-- the player had for a line they are still shopping.
function GC.Buy.FoldRefresh(browsed)
  local now = time()
  lastRefreshAt = now
  if not current then return end
  for i = 1, #(browsed or {}) do
    local row = browsed[i]
    local itemKey = type(row) == "table" and row.itemKey or nil
    local itemID = type(itemKey) == "table" and itemKey.itemID or nil
    local floor = type(row) == "table" and row.minPrice or nil
    if itemID and floor and floor > 0 then current:SetFloor(itemID, floor, now) end
  end
  GC.Buy.RefreshIfShown()
end

-- BAG_UPDATE_DELAYED (Core/Init.lua). Fires on every loot, craft, mail and vendor trip for the
-- whole session, so it does nothing at all unless this tab is actually on screen -- a six-bag
-- walk behind Deals costs the player frames and buys nothing. Nothing goes stale by skipping
-- it: Show() rescans before it renders, which is the only moment a hidden tab's counts could
-- have been read.
function GC.Buy.OnBagsChanged()
  if not (container and container:IsShown()) then return end
  scanBags()
  GC.Buy.RefreshIfShown()
end

-- `/gc buy` (the slash command itself lands with the purchase flow): what the tab believes,
-- printed, so a player can report a wrong count without a screenshot.
function GC.Buy.DebugPrint()
  if not current then
    GC.Print(GC.L["Buy: no run selected."])
    return
  end
  local totals = current:Totals()
  GC.Print((GC.L["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"]):format(
    runLabel(current), totals.lines, totals.toBuy, totals.atVendor,
    formatAmount(totals.spent), formatAmount(totals.left)))
  for _, line in ipairs(current:Lines()) do
    local state = ""
    if line.vendor then state = GC.L["vendor"]
    elseif line.done then state = GC.L["done"]
    elseif line.locked then state = GC.L["Pro"] end
    GC.Print((GC.L["  %s · need %d · have %d · buy %d · %s"]):format(
      lineName(line), line.need, line.have, line.buy, state))
  end
end
