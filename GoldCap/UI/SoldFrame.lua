local _, GC = ...
local B = GC.Kit.Tokens.blizzard

-- The Sold tab: what the player sold, what reached the mailbox, and the profit GoldCap knows.
-- The arithmetic lives in Core/SoldView.lua and the receipt's rules in Core/SoldReceipt.lua; this
-- file reads the stores, hands their rows to them, and paints what comes back.
--
-- Honesty rules, unchanged from the tab's first design:
--   * Two sources, never merged or fuzzy-matched: the goldcap.gg snapshot (GC.AppLedger, as of
--     the last /reload -- ON GOLDCAP.GG) and the local ledger rows the snapshot cannot hold yet
--     (JUST SOLD). The boundary is the newest `at` among the snapshot's OWN sale rows, never
--     its generatedAt: SavedVariables are written on /reload or logout, so the file the
--     companion read was written before that reload and generatedAt is always newer than the
--     sales the snapshot is missing. Deriving the boundary from the sales can show one sale in
--     both labelled sections for a reload (accepted); it can never hide one.
--   * Local profit only on an EXACT evidence-key join to GC.Acquisitions.GetRealized(), and the
--     stock's sources only through the same key (GC.Acquisitions.SourcesIndex). Everything else
--     says "-" (or "set cost" where the receipt can finish it), never an invented number. Pro
--     gating happened server-side: a free summary carries no basis, and its rows show no profit.
--   * WoW: Forever has no goldcap.gg sales. Its local sales are the whole list, grouped by day,
--     and a snapshot is never read there.
--
-- Layout, top to bottom: the header (the tab's name, the period switch, the search button and
-- the box it reveals), the cards (YOU GOT, PROFIT, BEST SALE, and Road to 40 on Forever or the
-- goldcap.gg sync on retail), the list, and at the bottom one quiet line for the bag items that
-- fetch more on the auction house. A sale row opens, on a click, into its receipt
-- (UI/SoldReceipt.lua); a second click or Escape closes it. Hover only lights the row.
--
-- Nothing is cut short. Every figure column is as wide as the widest text it holds this render,
-- measured with GetUnboundedStringWidth, so the active language and the font scale are both in
-- the number, and the item takes what is left. Sentences (card lines, the bottom line, section
-- notes, hints, the empty state) wrap inside a box that grows, and so does an item name longer
-- than its room: its row grows to hold the extra lines.
GC.Sold = {}
local Sold = GC.Sold

local Theme, V, R

-- Every widget the tab owns. A field on GC.Sold so the module's own spec can read the pool and
-- the cards without reaching into upvalues; nothing else reads it.
local view = { rows = {} }
Sold._view = view
-- `open` is the one sale whose receipt is open, by the sale's identity (saleID), never by the
-- pooled row that happens to draw it.
local state = { period = "7d", query = "", open = nil, searchOpen = false }
Sold._state = state

local SD = {
  GAP = 10,           -- between the tab's blocks, and between two cards
  HEAD_H = 28, TITLE_GAP = 12,
  CARD_PAD_X = 12, CARD_PAD_Y = 10, CARD_LINE = 6, CARD_MIN_H = 70, CARD_MIN_W = 150,
  RING = 34, RING_DOTS = 16, RING_DOT = 3, RING_GAP = 8,
  FOOT_MIN_H = 26, FOOT_PAD = 6,
  BTN_H = 22, BTN_PAD = 10,
  CHIP_H = 22, CHIP_PAD = 10, CHIP_GAP = 2, GROUP_PAD = 3,
  SEARCH_W = 210, SEARCH_MIN = 120, SEARCH_PAD = 10, CTRL_H = 26, GLYPH = 12, GLYPH_GAP = 7,
  ROW_H = 52, ROW_PAD_Y = 9, SUB_GAP = 3, DAY_H = 28, ICON = 32, ICON_GAP = 10, CHEVRON = 12,
  MKT_BAR_W = 56, MKT_DOT = 7, MKT_TICK_H = 9, MKT_GAP = 6, OPEN_INSET = 4,
  PAD_X = 10, COL_GAP = 12, ITEM_MIN = 110, NOTE_MIN = 80, RULE_GAP = 8,
  EMPTY_PAD = 20,
  STALE_YELLOW = 6 * 3600, STALE_RED = 24 * 3600,
}

-- Inline colour escapes of the window's figures, read from the applied skin when a line is built.
local HEX_KEY = { g = "soldGold", s = "soldSilver", c = "soldCopper", green = "soldGreen", gold = "soldGold", dim = "soldDim" }
local HEX = setmetatable({}, { __index = function(_, key)
  local color = GC.Kit.Tokens.color[HEX_KEY[key]]
  return color and GC.Util.Colored(color, ""):sub(1, -3)
end })
local COLOR_KEY = { tile = "soldTile", road = "soldRoad", empty = "soldEmpty", faint = "soldFaint" }
-- The window's fills and faint text, read from the applied skin when a card is built; `white` is
-- the game tooltip's.
local COLOR = setmetatable({ white = B.tipWhite }, { __index = function(_, key)
  return GC.Kit.Tokens.color[COLOR_KEY[key]]
end })

-- @localised-keys: date("*t").wday order, Sunday first. The literals ARE GC.L keys, looked up
-- where they are read: at FILE SCOPE GC.L still answers in English (ApplyLocale runs at
-- ADDON_LOADED). The table closes with a `}` on its own line -- that is where the spec's scanner
-- stops.
local WEEKDAY = {
  "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT",
}

local function setColor(fs, c)
  if fs and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

-- Writes a FontString's text so the client draws it. SetText with the text a string already
-- holds is a no-op, and a one-line string that sat under a hidden parent can come back undrawn
-- (docs: "Text", measured in game) -- so it is cleared first, and on a re-show also hidden and
-- shown again (view.restamp, set by Sold.Show).
local function put(fs, text)
  fs:SetText("")
  fs:SetText(text or "")
  if view.restamp then fs:Hide() end
  fs:Show()
end

-- A Theme.Button's label, written the same way.
local function setLabel(button, text)
  button:SetLabel(text)
  put(button.text, text)
end

-- A string's own width on one line, rounded up with a pixel spare: a box exactly as wide as
-- the fractional width can still break or clip the last glyph once the engine snaps to pixels.
local function widthOf(fs)
  return fs.GetUnboundedStringWidth and math.ceil(fs:GetUnboundedStringWidth() or 0) + 1 or 0
end

local function heightOf(fs)
  return fs.GetStringHeight and math.ceil(fs:GetStringHeight() or 0) or 0
end

-- A sentence that wraps inside `width` and says how tall it came out. The height is read only
-- after the text is written again at the new width -- Blizzard's own wrapped strings do the
-- same (ObjectiveTrackerBlockMixin:SetStringText), since a height measured at the old width
-- can be stale.
local function wrapTo(fs, width)
  fs:SetWidth(math.max(1, width))
  fs:SetWordWrap(true)
  if fs.SetMaxLines then fs:SetMaxLines(0) end
  -- A word longer than the line (a figure, goldcap.gg) breaks onto the next line instead of
  -- being cut.
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
  fs:SetHeight(0)
  local text = fs:GetText()
  fs:SetText("")
  fs:SetText(text or "")
  return heightOf(fs)
end

-- One line, exactly as wide as its text: nothing to cut.
local function hug(fs)
  fs:SetWordWrap(false)
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  local w = widthOf(fs)
  fs:SetWidth(math.max(1, w))
  return w
end

-- Money ------------------------------------------------------------------------------------

local function group(n)
  local fn = _G.BreakUpLargeNumbers
  if type(fn) ~= "function" then return nil end
  local ok, text = pcall(fn, n)
  return ok and text ~= nil and tostring(text) or nil
end

local function plain(copper, full) return V.Money(copper, group, full) end
local function signed(copper, full) return V.Signed(copper, group, full) end

-- The unit letters in their coin's colour, the figures in the string's own.
local function coins(copper, full)
  return (plain(copper, full):gsub("(%d)([gsc])", function(d, u) return d .. HEX[u] .. u .. "|r" end))
end

-- The clock -------------------------------------------------------------------------------

local EPOCH = { year = 1970, month = 1, day = 1, hour = 0, min = 0, sec = 0, wday = 5 }
local function dateOf(at)
  local d = _G.date
  return type(d) == "function" and d("*t", at) or EPOCH
end

local function clock(at)
  local t = dateOf(at)
  local fmt = _G.GameTime_GetFormattedTime
  if type(fmt) == "function" then
    local ok, text = pcall(fmt, t.hour, t.min, true)
    if ok and type(text) == "string" then return text end
  end
  return ("%02d:%02d"):format(t.hour, t.min)
end

local function shortDate(at)
  local t = dateOf(at)
  local fmt = _G.FormatShortDate
  if type(fmt) == "function" then
    local ok, text = pcall(fmt, t.day, t.month)
    if ok and type(text) == "string" then return text end
  end
  return ("%d/%d"):format(t.month, t.day)
end

local function isToday(at, now) return V.DayKey(at, dateOf) == V.DayKey(now, dateOf) end

local function dayLabel(at, now)
  if isToday(at, now) then return GC.L["TODAY"] end
  local yesterday = V.DayStart(now, 0, dateOf) - 1
  if V.DayKey(at, dateOf) == V.DayKey(yesterday, dateOf) then return GC.L["YESTERDAY"] end
  local wday = WEEKDAY[dateOf(at).wday]
  return (wday and GC.L[wday] .. ", " or "") .. shortDate(at)
end

local function periodLabel(period)
  if period == "today" then return GC.L["TODAY"] end
  return GC.L["%d DAYS"]:format(V.PERIOD_DAYS[period] or 7)
end

-- The item behind a row ---------------------------------------------------------------------

-- A sale mail carries the item's NAME only, and the client answers a name only for an item it
-- has cached. What a name lookup finds is used for the icon and the colour and nothing else:
-- two quality ranks of one reagent share a name, so a market price or a bag count read off a
-- name could describe the other rank. Only an exact id (the sale's own, the position its profit
-- was matched to, or the one item the character listed under that name) is priced or counted,
-- and nothing here ever opens the item's own tooltip.
local byName, unnamed = {}, {}
local function lookupName(name)
  local api = _G.C_Item
  if type(name) ~= "string" or name == "" or not api then return nil end
  if byName[name] then return byName[name] end
  local icon, quality
  if api.GetItemInfoInstant then
    local ok, id, _, _, _, tex = pcall(api.GetItemInfoInstant, name)
    if ok and type(id) == "number" then icon = tex end
  end
  if api.GetItemInfo then
    local ok, _, _, q, _, _, _, _, _, _, tex = pcall(api.GetItemInfo, name)
    if ok then quality, icon = q, icon or tex end
  end
  -- WoW: Forever: a name the client has not cached left a blank grey square (Relic Coffer Key,
  -- Pitchblende, owner's screenshot, 2026-11-21). The names the last scan saw (Core/ForeverNames.lua)
  -- give the item's id, and an icon by id needs no cache. The icon only: the id is still not exact.
  if not icon and not unnamed[name] and api.GetItemIconByID and GC.ForeverNames and GC.ForeverNames.Each then
    local id
    GC.ForeverNames.Each(function(itemID, known) if known == name then id = itemID end end)
    unnamed[name] = id == nil or nil
    if id then
      local ok, tex = pcall(api.GetItemIconByID, id)
      if ok then icon = tex end
    end
  end
  if not icon and quality == nil then return nil end
  byName[name] = { icon = icon, quality = quality }
  return byName[name]
end

local function qualityColor(quality)
  if type(quality) ~= "number" or quality < 2 then return nil end
  -- The skin's colour first; the game's below comes from the client's colour call before the table
  -- (so this one site does not take the root's table fallback).
  local skinned = Theme.SkinQuality(quality)
  if skinned then return { skinned.r, skinned.g, skinned.b } end
  local api = _G.C_Item
  if api and api.GetItemQualityColor then
    local ok, r, g, b = pcall(api.GetItemQualityColor, quality)
    if ok and type(r) == "number" then return { r, g, b } end
  end
  local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
  return c and type(c.r) == "number" and { c.r, c.g, c.b } or nil
end

local function itemInfo(row)
  local api = _G.C_Item
  local id = row.itemExact and row.itemID or nil
  local icon, quality
  if id and api then
    if api.GetItemIconByID then
      local ok, tex = pcall(api.GetItemIconByID, id)
      if ok then icon = tex end
    end
    if api.GetItemQualityByID then
      local ok, q = pcall(api.GetItemQualityByID, id)
      if ok then quality = q end
    end
  end
  if not icon or quality == nil then
    local hit = lookupName(row.name)
    if hit then
      icon = icon or hit.icon
      if quality == nil then quality = hit.quality end
    end
  end
  return { id = id, icon = icon, color = qualityColor(quality) }
end

-- The market price a sale is compared with (Core/SoldReceipt.Market): the figure GoldCap's own
-- item tooltip prices the item at (UI/Tooltip.lua), for an exact item priced as one thing.
local function marketFor(itemID)
  if not (itemID and GC.Data and GC.Data.GetItemValue) then return nil end
  local ok, v = pcall(GC.Data.GetItemValue, itemID)
  return ok and R.Market(v) or nil
end

-- How many of the exact item the bags hold, for the receipt's way to SELL.
local function bagsOf(itemID)
  local api = _G.C_Item
  local fn = (api and api.GetItemCount) or _G.GetItemCount
  if not (itemID and type(fn) == "function") then return 0 end
  local ok, n = pcall(fn, itemID)
  return ok and type(n) == "number" and n or 0
end

-- A sale's identity across renders: the ledger key for a local sale, and for a goldcap.gg one
-- the fields the snapshot holds it by.
local function saleID(r)
  if r.key then return "local\1" .. r.key end
  return table.concat({ r.section or "", tostring(r.at), tostring(r.name), tostring(r.qty), tostring(r.gross) }, "\1")
end

-- The model ---------------------------------------------------------------------------------

local function buildModel()
  local isForever = GC.Game and GC.Game.IsForever and GC.Game.IsForever(GC.Game.Passport()) or false
  local summary = not isForever and GC.AppLedger and GC.AppLedger.GetSummary and GC.AppLedger.GetSummary() or nil
  local now = time()
  local m = { isForever = isForever, summary = summary, now = now,
    from = V.PeriodStart(state.period, now, dateOf) }
  local acq = GC.Acquisitions or {}
  local realized = {}
  if acq.GetRealized then
    for _, row in ipairs(acq.GetRealized()) do
      if row.evidenceKey then realized[row.evidenceKey] = row end
    end
  end
  local activities = acq.GetActivities and acq.GetActivities() or {}
  local listed = V.ListedIndex(activities)
  local entries = GC.Ledger and GC.Ledger.GetEntries and GC.Ledger.GetEntries() or {}
  local locals, servers = {}, {}
  for _, sale in ipairs(V.LocalSales(entries, V.Boundary(summary))) do
    local hit = sale.key and realized[sale.key] or nil
    local listedID = V.ListedItemID(listed, sale.itemName, sale.char, sale.region)
    local row = V.LocalRow(sale, hit, nil, listedID)
    row.entry = sale
    locals[#locals + 1] = row
  end
  for _, sale in ipairs(summary and summary.sales or {}) do servers[#servers + 1] = V.ServerRow(sale) end
  m.anySales = #locals + #servers > 0
  m.locals = V.Filter(locals, m.from, state.query)
  -- Sources only for the rows the period and the search left, and from one pass over the store
  -- for all of them: SourcesOf per sale scanned every batch for every sale ever made, on each render.
  -- A row has a profit exactly when LocalRow found its sale realized.
  local index
  local active = {}
  for _, row in ipairs(m.locals) do
    if row.profit ~= nil and row.key and acq.SourcesIndex then
      index = index or acq.SourcesIndex()
      row.sources = index[row.key] or {}
    elseif row.profit == nil and not row.pending and acq.GetActive then
      -- Whether the receipt can finish this sale with a typed cost (Core/SoldReceipt.CostTarget):
      -- the books' stock once per character, not once per sale.
      local e = row.entry
      local scope = tostring(e.char) .. "\1" .. tostring(e.region)
      active[scope] = active[scope] or acq.GetActive({ char = e.char, region = e.region })
      row.canSave = R.CostTarget(row, e, activities, active[scope]) ~= nil
    end
  end
  m.servers = V.Filter(servers, m.from, state.query)
  m.all = {}
  for _, row in ipairs(m.locals) do m.all[#m.all + 1] = row end
  for _, row in ipairs(m.servers) do m.all[#m.all + 1] = row end
  m.totals, m.best = V.Totals(m.all), V.Best(m.all)
  m.truncated = V.Truncated(summary, m.from)
  m.road = GC.ForeverRoad and GC.ForeverRoad.Snapshot and GC.ForeverRoad.Snapshot() or nil
  return m
end

local function salesNote(count, copper)
  if count == 1 then return GC.L["1 sale · %s"]:format(plain(copper)) end
  return GC.L["%d sales · %s"]:format(count, plain(copper))
end

local function listEntries(m)
  local out = {}
  if not m.isForever and not m.summary then
    out[#out + 1] = { kind = "hint", text = GC.L["Pair or update the GoldCap Companion to see profit from goldcap.gg"] }
  elseif m.summary and not m.summary.pro then
    out[#out + 1] = { kind = "hint", text = GC.L["Profit tracking is a goldcap.gg Pro feature"] }
  end
  if m.summary then
    if #m.locals > 0 then
      out[#out + 1] = { kind = "head", title = GC.L["JUST SOLD"], note = GC.L["reaches goldcap.gg on /reload or logout"] }
      for _, row in ipairs(m.locals) do out[#out + 1] = { kind = "sale", row = row } end
    end
    if #m.servers > 0 then
      local s = m.summary
      local note = s.totals.salesCount > #s.sales
        and GC.L["latest %d of %d · the rest on goldcap.gg"]:format(#s.sales, s.totals.salesCount)
        or GC.L["last %d days"]:format(s.days)
      out[#out + 1] = { kind = "head", title = GC.L["ON GOLDCAP.GG"], note = note }
      for _, row in ipairs(m.servers) do out[#out + 1] = { kind = "sale", row = row } end
    end
  else
    for _, day in ipairs(V.Days(m.locals, dateOf)) do
      out[#out + 1] = { kind = "head", title = dayLabel(day.rows[1].at, m.now), note = salesNote(day.count, day.net) }
      for _, row in ipairs(day.rows) do out[#out + 1] = { kind = "sale", row = row, grouped = true } end
    end
  end
  return out
end

-- Cards ------------------------------------------------------------------------------------

local function cardParts(card)
  return { card.label, card.value, card.small, card.name, card.sub }
end

-- A card's headline figure, in the big face; stackCard moves it to the smaller one when it is
-- wider than the card.
local function putValue(card, text, color)
  put(card.value, text)
  setColor(card.value, color)
  card.valueColor = color
end

local function resetCard(card)
  for _, fs in ipairs(cardParts(card)) do fs:Hide() end
  card.ring:Hide()
  card.icon:Hide(); card.iconEdge:Hide()
  card.frame:SetTint(COLOR.tile, Theme.color.border)
  setColor(card.label, Theme.color.fgDim)
  setColor(card.value, Theme.color.fg)
  setColor(card.small, Theme.color.fg)
  setColor(card.sub, Theme.color.fgDim)
  card.hasRing, card.hasIcon, card.road, card.progress = false, false, nil, nil
end

local function paintGot(card, m)
  put(card.label, GC.L["YOU GOT"])
  putValue(card, coins(m.totals.net), Theme.color.fg)
  local count = m.totals.count
  local sub
  if m.truncated then sub = GC.L["%d here · all on goldcap.gg"]:format(count)
  elseif count == 1 then sub = GC.L["1 sale, after the cut"]
  else sub = GC.L["%d sales, after the cut"]:format(count) end
  put(card.sub, sub)
end

local function paintProfit(card, m)
  put(card.label, GC.L["PROFIT"])
  local t = m.totals
  if t.known > 0 then
    putValue(card, signed(t.profit), t.profit >= 0 and Theme.color.green or Theme.color.red)
  else
    putValue(card, "-", COLOR.faint)
  end
  if t.count > 0 then put(card.sub, GC.L["%d of %d have a cost"]:format(t.known, t.count)) end
end

local function paintBest(card, m)
  put(card.label, GC.L["BEST SALE"])
  local best = m.best
  if not best then
    put(card.small, "-")
    setColor(card.small, COLOR.faint)
    put(card.sub, GC.L["no sale with a known profit yet"])
    return
  end
  local info = itemInfo(best)
  if info.icon then card.icon:SetTexture(info.icon)
  else card.icon:SetColorTexture(GC.Kit.Tokens.color.ink[1], GC.Kit.Tokens.color.ink[2], GC.Kit.Tokens.color.ink[3], 0.05) end
  local edge = info.color and { info.color[1], info.color[2], info.color[3], 0.6 } or GC.Kit.Tokens.ink(0.16)
  card.iconEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
  card.icon:Show(); card.iconEdge:Show()
  card.hasIcon = true
  put(card.name, best.name or GC.L["Unknown item"])
  setColor(card.name, info.color or Theme.color.fg)
  put(card.small, coins(best.net))
  put(card.sub, GC.L["%s profit"]:format(signed(best.profit)))
  setColor(card.sub, Theme.color.green)
end

-- Road to 40: a ring of segments with the percent inside, and gold plus bags against the cost.
local function paintRoad(card, s)
  local gc = Theme.color.gold
  card.frame:SetTint(COLOR.road, { gc[1], gc[2], gc[3], 0.22 })
  card.road = s
  put(card.label, GC.L["ROAD TO 40"])
  setColor(card.label, Theme.color.goldHi)
  local have = (s.money or 0) + (s.bags or 0)
  if type(s.cost) == "number" and s.cost > 0 then
    put(card.small, coins(have) .. " / " .. coins(s.cost))
    card.hasRing = true
    card.progress = V.Progress(have, s.cost)
    put(card.ring.pct, ("%d%%"):format(math.floor(card.progress * 100)))
  else
    put(card.small, GC.L["%s · gold %s, bags %s"]:format(coins(have), coins(s.money or 0), coins(s.bags or 0)))
    put(card.sub, GC.L["set the riding cost: %s"]:format(HEX.gold .. "/gc mount 90g|r"))
  end
end

local function paintSynced(card, m)
  local s = m.summary
  put(card.label, GC.L["GOLDCAP.GG · %d DAYS"]:format(s.days))
  local age = math.max(0, m.now - (s.generatedAt or m.now))
  local ago = GC.Util.FormatAge(age)
  if type(s.totals.realized) == "number" then
    putValue(card, signed(s.totals.realized), s.totals.realized >= 0 and Theme.color.green or Theme.color.red)
    put(card.sub, GC.L["profit · synced %s ago"]:format(ago))
  else
    putValue(card, coins(s.totals.proceeds or 0), Theme.color.fg)
    put(card.sub, GC.L["after the AH cut · synced %s ago"]:format(ago))
  end
  if age >= SD.STALE_RED then setColor(card.sub, Theme.color.red)
  elseif age >= SD.STALE_YELLOW then setColor(card.sub, Theme.tier.SUSPECT) end
end

-- The ring's segments lit for the card's progress, clockwise from the top.
local function paintRing(card)
  local lit = R.RingLit(card.progress, SD.RING_DOTS)
  local on, off = Theme.color.gold, GC.Kit.Tokens.ink(0.14)
  for i, dot in ipairs(card.ring.dots) do
    local c = i <= lit and on or off
    dot:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  end
  card.ring:Show()
end

-- Stacks a card's shown parts top-down inside `inner` and says how tall they came out.
local function stackCard(card, inner)
  local y = SD.CARD_PAD_Y - SD.CARD_LINE -- the first part sits at CARD_PAD_Y
  local function place(fs, width, x)
    local h = wrapTo(fs, width)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card.frame, "TOPLEFT", SD.CARD_PAD_X + (x or 0), -(y + SD.CARD_LINE))
    y = y + SD.CARD_LINE + h
  end
  if card.label:IsShown() then place(card.label, inner) end
  if card.value:IsShown() and widthOf(card.value) > inner and not card.small:IsShown() then
    -- A figure too wide for the card at the big size (a retail total, the largest font scale,
    -- the narrowest window) steps down to the card's smaller face rather than be cut.
    card.value:Hide()
    put(card.small, card.value:GetText())
    setColor(card.small, card.valueColor)
  end
  if card.value:IsShown() then place(card.value, inner) end
  if card.hasIcon then
    -- The best sale: its icon beside its name, the name wrapping in what the icon leaves.
    local h = wrapTo(card.name, inner - 28)
    local line, top = math.max(h, 22), y + SD.CARD_LINE
    card.iconEdge:ClearAllPoints()
    card.iconEdge:SetPoint("TOPLEFT", card.frame, "TOPLEFT", SD.CARD_PAD_X, -(top + (line - 22) / 2))
    card.name:ClearAllPoints()
    card.name:SetPoint("TOPLEFT", card.frame, "TOPLEFT", SD.CARD_PAD_X + 28, -(top + (line - h) / 2))
    y = top + line
  end
  if card.hasRing then
    -- The ring at the left, gold plus bags of the cost beside it, centred on it.
    local top = y + SD.CARD_LINE
    card.ring:ClearAllPoints()
    card.ring:SetPoint("TOPLEFT", card.frame, "TOPLEFT", SD.CARD_PAD_X, -top)
    paintRing(card)
    local h = wrapTo(card.small, inner - SD.RING - SD.RING_GAP)
    card.small:ClearAllPoints()
    card.small:SetPoint("TOPLEFT", card.frame, "TOPLEFT", SD.CARD_PAD_X + SD.RING + SD.RING_GAP,
      -(top + math.max(0, (SD.RING - h) / 2)))
    y = top + math.max(SD.RING, h)
  elseif card.small:IsShown() then
    place(card.small, inner)
  end
  if card.sub:IsShown() then place(card.sub, inner) end
  return y + SD.CARD_PAD_Y
end

local function layoutCards(m, width, top)
  local cards = view.cards
  for _, card in ipairs(cards) do resetCard(card); card.frame:Hide() end
  paintGot(cards[1], m)
  paintProfit(cards[2], m)
  paintBest(cards[3], m)
  local shown = { cards[1], cards[2], cards[3] }
  if m.road then paintRoad(cards[4], m.road); shown[4] = cards[4]
  elseif m.summary then paintSynced(cards[4], m); shown[4] = cards[4] end
  -- One row of cards; two rows of two when four in one would leave a card too narrow for its
  -- figure (the narrowest window, the largest font scale).
  local perRow = #shown
  if perRow == 4 and (width - 3 * SD.GAP) / 4 < SD.CARD_MIN_W then perRow = 2 end
  local w = math.floor((width - (perRow - 1) * SD.GAP) / perRow)
  local height = SD.CARD_MIN_H
  for _, card in ipairs(shown) do height = math.max(height, stackCard(card, w - 2 * SD.CARD_PAD_X)) end
  for i, card in ipairs(shown) do
    local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
    card.frame:ClearAllPoints()
    card.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", col * (w + SD.GAP), -(top + line * (height + SD.GAP)))
    card.frame:SetSize(w, height)
    card.frame:Show()
  end
  local lines = math.ceil(#shown / perRow)
  return top + lines * height + (lines - 1) * SD.GAP
end

-- The header -------------------------------------------------------------------------------

-- The tab's name at the left; at the right the period switch and the search button. The search
-- box shows while it is open or holds a query: in the header between the name and the switch
-- when there is room, else on a line of its own under it. The window's own close is the
-- window's (its title bar), not drawn again here.
local function layoutHeader(width)
  local h = view.head
  -- The tab's own name, exactly as the rail writes it: the tab names (DEALS, SELL, SOLD, BUY) are
  -- the same word in every language, as "OPEN SELL" is translated around them.
  local name = "SOLD"
  for _, tab in ipairs(Theme.RAIL_ORDER or {}) do
    if tab.key == "sold" then name = tab.label end
  end
  put(h.title, name)
  h.title:ClearAllPoints()
  h.title:SetPoint("LEFT", view.container, "TOPLEFT", 0, -SD.HEAD_H / 2)
  local titleW = hug(h.title)

  h.find:SetSize(SD.CTRL_H, SD.CTRL_H)
  h.find:ClearAllPoints()
  h.find:SetPoint("TOPRIGHT", view.container, "TOPRIGHT", 0, -(SD.HEAD_H - SD.CTRL_H) / 2)

  local x = SD.GROUP_PAD
  for _, period in ipairs(V.PERIODS) do
    local chip = h.chips[period]
    setLabel(chip, periodLabel(period))
    local w = widthOf(chip.text) + 2 * SD.CHIP_PAD
    chip:SetSize(w, SD.CHIP_H)
    chip:ClearAllPoints()
    chip:SetPoint("LEFT", h.group, "LEFT", x, 0)
    x = x + w + SD.CHIP_GAP
    if period == state.period then
      chip:SetVariant("active")
    else
      chip:SetVariant("ghost")
      chip.bg:SetVertexColor(1, 1, 1, 0) -- untinted
      setColor(chip.text, Theme.color.fgDim)
    end
  end
  local groupW = x - SD.CHIP_GAP + SD.GROUP_PAD
  h.group:ClearAllPoints()
  h.group:SetPoint("TOPRIGHT", view.container, "TOPRIGHT", -(SD.CTRL_H + SD.GAP / 2), -(SD.HEAD_H - SD.CTRL_H) / 2)
  h.group:SetSize(groupW, SD.CTRL_H)

  local y = SD.HEAD_H
  local text = h.search:GetText() or ""
  if not (state.searchOpen or text ~= "") then
    h.well:Hide()
    return y + SD.GAP
  end
  put(h.hint, GC.L["Find an item"])
  local least = math.max(SD.SEARCH_MIN, hug(h.hint) + 2 * SD.SEARCH_PAD + 2 * SD.GLYPH + 2 * SD.GLYPH_GAP)
  local room = width - titleW - SD.TITLE_GAP - groupW - SD.CTRL_H - SD.GAP
  h.well:ClearAllPoints()
  if room >= least then
    h.well:SetPoint("TOPRIGHT", h.group, "TOPLEFT", -SD.GAP, 0)
    h.well:SetSize(math.min(SD.SEARCH_W, room), SD.CTRL_H)
  else
    h.well:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -(y + SD.GAP / 2))
    h.well:SetSize(math.min(width, math.max(least, SD.SEARCH_W)), SD.CTRL_H)
    y = y + SD.GAP / 2 + SD.CTRL_H
  end
  h.well:Show()
  if text ~= "" or (h.search.HasFocus and h.search:HasFocus()) then h.hint:Hide() end
  return y + SD.GAP
end

-- The bottom line ---------------------------------------------------------------------------

-- WoW: Forever: bag items the auction house pays more for than a vendor, and the way to the tab
-- that sells them, in one quiet line at the foot of the tab. The sentence wraps and the line
-- grows; the button is as wide as its own label. Returns the room it takes at the bottom.
local function layoutFoot(m, width)
  local f = view.foot
  local s = m.road
  if not (s and (s.gainItems or 0) > 0 and (s.gain or 0) > 0) then
    f.frame:Hide()
    return 0
  end
  setLabel(f.button, GC.L["OPEN SELL"])
  local bw = widthOf(f.button.text) + 2 * SD.BTN_PAD + SD.GLYPH
  f.button:SetSize(bw, SD.BTN_H)
  put(f.text, GC.L["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."]
    :format(s.gainItems, HEX.green .. plain(s.gain) .. "|r"))
  local th = wrapTo(f.text, width - (SD.GLYPH + 2 + SD.GLYPH_GAP) - bw - SD.GAP)
  local h = math.max(SD.FOOT_MIN_H, th + 2 * SD.FOOT_PAD, SD.BTN_H + 2 * SD.FOOT_PAD)
  f.frame:ClearAllPoints()
  f.frame:SetPoint("BOTTOMLEFT", view.container, "BOTTOMLEFT", 0, 0)
  f.frame:SetSize(width, h)
  f.frame:Show()
  return h + SD.GAP / 2
end

-- Rows -------------------------------------------------------------------------------------

local function whenText(r, grouped, now)
  if r.pending then return HEX.gold .. GC.L["in the mail"] .. "|r" end
  if grouped or isToday(r.at, now) then return clock(r.at) end
  return shortDate(r.at)
end

local function profitText(r)
  local cell = R.ProfitCell(r, r.canSave)
  if cell == "profit" then
    local text = signed(r.profit)
    if r.costUnits then text = text .. "  " .. HEX.dim .. ("%d/%d"):format(r.costUnits, r.qty) .. "|r" end
    return text, r.profit >= 0 and Theme.color.green or Theme.color.red
  end
  if cell == "set" then return GC.L["set cost"], COLOR.faint end
  if cell == "blank" then return "", COLOR.faint end
  return "-", COLOR.faint
end

local function clearRow(row)
  row.name:Hide(); row.sub:Hide(); row.icon:Hide(); row.iconEdge:Hide(); row.chevron:Hide()
  row.title:Hide(); row.note:Hide(); row.rule:Hide(); row.wide:Hide()
  for _, key in ipairs({ "mkt", "got", "profit" }) do row.cells[key]:Hide() end
  row.track:Hide(); row.tick:Hide(); row.dot:Hide()
  -- Hide/Show, never SetAlpha: on a texture SetAlpha writes the very alpha the wash's colour
  -- set, and SetAlpha(1) turns the faint wash into a solid bar.
  row.highlight:Hide(); row.outline:Hide(); row.openFill:Hide()
  row.sale, row.info, row.saleID, row.isOpen, row.pct = nil, nil, nil, false, nil
end

-- Pass one: the texts. The figure columns are fitted to what these come out as.
local function paintRow(row, entry, now)
  clearRow(row)
  row.kind = entry.kind
  if entry.kind == "hint" then
    put(row.wide, entry.text)
    setColor(row.wide, Theme.color.fgDim)
    return
  end
  if entry.kind == "head" then
    put(row.title, entry.title)
    put(row.note, entry.note)
    row.rule:Show()
    return
  end
  local r = entry.row
  row.sale, row.info, row.saleID = r, itemInfo(r), saleID(r)
  row.isOpen = state.open == row.saleID
  if row.info.icon then
    row.icon:SetTexture(row.info.icon)
  else
    -- An item the client cannot name yet: a quiet empty slot, not the red question mark that
    -- reads as an error.
    row.icon:SetColorTexture(GC.Kit.Tokens.color.ink[1], GC.Kit.Tokens.color.ink[2], GC.Kit.Tokens.color.ink[3], 0.05)
  end
  local c = row.info.color
  local edge = c and { c[1], c[2], c[3], 0.6 } or GC.Kit.Tokens.ink(0.16)
  row.iconEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
  row.icon:Show(); row.iconEdge:Show()
  put(row.name, r.name or GC.L["Unknown item"])
  setColor(row.name, c or Theme.color.fg)
  put(row.sub, ("%d × %s · %s"):format(r.qty, r.each and plain(r.each) or "-", whenText(r, entry.grouped, now)))
  -- Against the market: only an exact item's own price (Core/SoldReceipt.Market).
  row.market = marketFor(row.info.id)
  row.pct = row.market and V.Percent(r.each, row.market) or nil
  if row.pct then
    put(row.cells.mkt, row.pct == 0 and "0%" or ("%+d%%"):format(row.pct))
    local tone = R.Tone(row.pct)
    row.mktColor = tone == "above" and Theme.color.green or tone == "under"
      and (GC.Kit.Tokens.color.warn or Theme.color.goldHi) or Theme.color.fgDim
    setColor(row.cells.mkt, row.mktColor)
  else
    put(row.cells.mkt, "")
  end
  put(row.cells.got, coins(r.net))
  local text, color = profitText(r)
  put(row.cells.profit, text)
  setColor(row.cells.profit, color)
  Theme.SetIcon(row.chevron, row.isOpen and "caretDown" or "caretRight", row.isOpen and Theme.color.goldHi or Theme.color.fgDim)
  row.chevron:Show()
end

-- The vs-market mark: a thin track, the market's tick at its middle, a dot left or right of it
-- by the percent (Core/SoldReceipt.BarPosition), the figure beside it.
local function layoutMarket(row, right, mid, width)
  local cell = row.cells.mkt
  local pctW = width - SD.MKT_BAR_W - SD.MKT_GAP
  cell:SetWidth(math.max(1, pctW))
  cell:ClearAllPoints()
  cell:SetPoint("RIGHT", row, "TOPRIGHT", -right, -mid)
  if not row.pct then return end
  local barRight = right + pctW + SD.MKT_GAP
  row.track:ClearAllPoints()
  row.track:SetPoint("RIGHT", row, "TOPRIGHT", -barRight, -mid)
  row.track:SetSize(SD.MKT_BAR_W, 2)
  row.tick:ClearAllPoints()
  row.tick:SetPoint("CENTER", row.track, "CENTER", 0, 0)
  row.tick:SetSize(1, SD.MKT_TICK_H)
  local at = R.BarPosition(row.pct)
  row.dot:ClearAllPoints()
  row.dot:SetPoint("CENTER", row.track, "LEFT", at * SD.MKT_BAR_W, 0)
  row.dot:SetSize(SD.MKT_DOT, SD.MKT_DOT)
  local dc = row.mktColor
  row.dot:SetColorTexture(dc[1], dc[2], dc[3], 1)
  row.dotAt = at
  row.track:Show(); row.tick:Show(); row.dot:Show()
end

-- One line when it fits in `room`, else wrapped inside it: a long name grows its row and is
-- never cut. Says how tall it came out.
local function fitLine(fs, room)
  if widthOf(fs) > room then return wrapTo(fs, room) end
  hug(fs)
  return heightOf(fs)
end

-- Pass two: the anchors, now that the columns are fitted. Returns the row's own height (without
-- an open receipt).
local function layoutRow(row, width, fit)
  local inner = width - 2 * SD.PAD_X
  if row.kind == "hint" then
    local h = wrapTo(row.wide, inner)
    row.wide:ClearAllPoints()
    row.wide:SetPoint("TOP", row, "TOP", 0, -8)
    return h + 16
  end
  if row.kind == "head" then
    -- "TODAY" in gold small caps, a hairline, and the day's count and sum at the right.
    local titleW = math.min(widthOf(row.title), inner)
    local th = wrapTo(row.title, titleW)
    local noteRoom = inner - titleW - 2 * SD.RULE_GAP - 24
    local beside = noteRoom >= SD.NOTE_MIN
    local nh
    row.note:ClearAllPoints()
    if beside then
      nh = wrapTo(row.note, math.min(noteRoom, widthOf(row.note)))
      row.note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -SD.PAD_X, 6)
    else
      -- No room beside the title: the note takes a line of its own under it.
      nh = wrapTo(row.note, inner)
      row.note:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SD.PAD_X, 6)
      th = th + nh + 2
    end
    row.title:ClearAllPoints()
    row.title:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SD.PAD_X, 6 + (beside and 0 or nh + 2))
    row.note:SetJustifyH(beside and "RIGHT" or "LEFT")
    row.rule:ClearAllPoints()
    row.rule:SetPoint("LEFT", row.title, "RIGHT", SD.RULE_GAP, 0)
    if beside then row.rule:SetPoint("RIGHT", row.note, "LEFT", -SD.RULE_GAP, 0)
    else row.rule:SetPoint("RIGHT", row, "RIGHT", -SD.PAD_X, 0) end
    return math.max(SD.DAY_H, th + 12, nh + 12)
  end
  -- A sale: the chevron at the right edge, the figure columns right to left off it, the item in
  -- what is left. The figures sit on the middle of the row's own 52px, whether or not a receipt
  -- hangs under it.
  local right = SD.PAD_X
  row.chevron:ClearAllPoints()
  row.chevron:SetSize(SD.CHEVRON, SD.CHEVRON)
  local textX = SD.PAD_X + SD.ICON + 2 + SD.ICON_GAP
  -- The name block first, at the room the columns leave, so the row's height is known.
  local used = SD.CHEVRON + SD.COL_GAP
  for _, key in ipairs({ "mkt", "got", "profit" }) do
    if not fit.hidden[key] then used = used + fit.widths[key] + SD.COL_GAP end
  end
  local nameRoom = math.max(24, width - SD.PAD_X - used - textX)
  local nh, sh = fitLine(row.name, nameRoom), fitLine(row.sub, nameRoom)
  local h = math.max(SD.ROW_H, nh + SD.SUB_GAP + sh + 2 * SD.ROW_PAD_Y)
  local mid = h / 2
  row.chevron:SetPoint("RIGHT", row, "TOPRIGHT", -right, -mid)
  right = right + SD.CHEVRON + SD.COL_GAP
  for _, key in ipairs({ "profit", "got", "mkt" }) do
    local cell = row.cells[key]
    if fit.hidden[key] then
      cell:Hide()
    elseif key == "mkt" then
      layoutMarket(row, right, mid, fit.widths.mkt)
    else
      cell:SetWidth(fit.widths[key])
      cell:ClearAllPoints()
      cell:SetPoint("RIGHT", row, "TOPRIGHT", -right, -mid)
    end
    if not fit.hidden[key] then right = right + fit.widths[key] + SD.COL_GAP end
  end
  row.iconEdge:ClearAllPoints()
  row.iconEdge:SetPoint("LEFT", row, "TOPLEFT", SD.PAD_X, -mid)
  local top = (h - (nh + SD.SUB_GAP + sh)) / 2
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -top)
  row.sub:ClearAllPoints()
  row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -(top + nh + SD.SUB_GAP))
  return h
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(SD.ROW_H)
  -- The hover wash sits UNDER the text (BACKGROUND, sublevel 1), as on the Sell and Deals rows:
  -- in the HIGHLIGHT layer it drew over the name and the figures and tinted them. paintRow's
  -- clearRow hides it on every repaint, so a row hidden under a still cursor cannot keep it.
  local hc = Theme.color.hover
  row.highlight = Theme.ShapeTexture(row, "BACKGROUND", "control", hc)
  row.highlight:SetDrawLayer("BACKGROUND", 1)
  row.highlight:SetPoint("TOPLEFT", 2, -1)
  row.highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  row.highlight:Hide()
  -- An open row: a faint gold fill and a gold outline round the row and its receipt.
  local gc = Theme.color.gold
  row.openFill = Theme.ShapeTexture(row, "BACKGROUND", "control", { gc[1], gc[2], gc[3], 0.05 })
  row.openFill:SetPoint("TOPLEFT", 2, -1)
  row.openFill:SetPoint("BOTTOMRIGHT", -2, 1)
  row.outline = Theme.ShapeTexture(row, "BORDER", "control", { gc[1], gc[2], gc[3], 0.55 }, true)
  row.outline:SetPoint("TOPLEFT", 2, -1)
  row.outline:SetPoint("BOTTOMRIGHT", -2, 1)
  row:EnableMouse(true)
  -- Wired once on the pooled row; it reads whatever paintRow last stamped. Hover only lights the
  -- row; a click opens its receipt, or closes it again.
  row:SetScript("OnEnter", function(self)
    if self.sale then self.highlight:Show() end
  end)
  row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
  row:SetScript("OnMouseUp", function(self, button)
    if not self.saleID or (button and button ~= "LeftButton") then return end
    Sold.Toggle(self.saleID)
  end)

  row.iconEdge = row:CreateTexture(nil, "BORDER")
  row.iconEdge:SetSize(SD.ICON + 2, SD.ICON + 2)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(SD.ICON, SD.ICON)
  row.icon:SetPoint("CENTER", row.iconEdge, "CENTER")
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.name = Theme.Label(row, 12)
  row.name:SetJustifyH("LEFT")
  row.sub = Theme.Num(row, 10)
  row.sub:SetJustifyH("LEFT")
  setColor(row.sub, Theme.color.fgDim)

  row.cells = { mkt = Theme.Num(row, 10, true), got = Theme.Num(row, 12, true), profit = Theme.Num(row, 12, true) }
  setColor(row.cells.got, Theme.color.fg)
  for _, cell in pairs(row.cells) do
    cell:SetJustifyH("RIGHT")
    cell:SetWordWrap(false)
    if cell.SetMaxLines then cell:SetMaxLines(1) end
  end
  row.track = Theme.Solid(row, "ARTWORK", GC.Kit.Tokens.ink(0.12))
  row.tick = Theme.Solid(row, "ARTWORK", GC.Kit.Tokens.ink(0.45))
  -- A solid square: at 7px the chip art's 6px caps would overlap.
  row.dot = Theme.Solid(row, "OVERLAY", Theme.color.fgDim)
  row.chevron = row:CreateTexture(nil, "ARTWORK")

  row.title = Theme.Num(row, 9, true)
  row.title:SetJustifyH("LEFT")
  setColor(row.title, Theme.color.goldHi)
  row.note = Theme.Num(row, 10)
  setColor(row.note, Theme.color.fgDim)
  row.rule = Theme.Solid(row, "ARTWORK", Theme.color.border)
  row.rule:SetHeight(1)

  row.wide = Theme.Label(row, 11)
  row.wide:SetJustifyH("CENTER")
  clearRow(row)
  return row
end

-- The empty states: nothing sold yet, or nothing in this period or search.
local function layoutEmpty(m, width, y)
  local e = view.empty
  if #m.all > 0 then
    e.frame:Hide()
    return y
  end
  local days = V.PERIOD_DAYS[state.period] or 7
  local query = (state.query or ""):match("^%s*(.-)%s*$")
  local message, sub, button
  if not m.anySales then
    message = GC.L["Your sales show up here once you open a mailbox with GoldCap loaded."]
    sub = GC.L["List something in SELL first."]
  elseif query ~= "" then
    message = state.period == "today" and GC.L["No sales match “%s” today."]:format(query)
      or GC.L["No sales match “%s” in these %d days."]:format(query, days)
    button = state.period ~= "30d" and GC.L["SEARCH 30 DAYS"] or nil
  else
    message = state.period == "today" and GC.L["No sales today."] or GC.L["No sales in these %d days."]:format(days)
    button = state.period ~= "30d" and GC.L["SHOW 30 DAYS"] or nil
  end
  local inner = width - 2 * SD.EMPTY_PAD
  -- The first visit is a welcome, set left under the mail glyph; a period or a search with
  -- nothing in it is a centred note.
  local welcome = not m.anySales
  local anchor, x, justify = "TOP", 0, "CENTER"
  local top = SD.EMPTY_PAD
  e.icon:ClearAllPoints()
  if welcome then
    anchor, x, justify = "TOPLEFT", SD.EMPTY_PAD, "LEFT"
    e.icon:SetPoint("TOPLEFT", e.frame, "TOPLEFT", SD.EMPTY_PAD, -top)
    e.icon:Show()
    top = top + 26 + 10
  else
    e.icon:Hide()
  end
  e.message:SetJustifyH(justify)
  e.sub:SetJustifyH(justify)
  put(e.message, message)
  local mh = wrapTo(e.message, inner)
  e.message:ClearAllPoints()
  e.message:SetPoint(anchor, e.frame, anchor, x, -top)
  top = top + mh
  if sub then
    put(e.sub, sub)
    local sh = wrapTo(e.sub, inner)
    e.sub:ClearAllPoints()
    e.sub:SetPoint(anchor, e.frame, anchor, x, -(top + 8))
    top = top + 8 + sh
  else
    e.sub:Hide()
  end
  if button then
    setLabel(e.button, button)
    e.button:SetSize(widthOf(e.button.text) + 2 * SD.BTN_PAD, SD.BTN_H + 2)
    e.button:ClearAllPoints()
    e.button:SetPoint("TOP", e.frame, "TOP", 0, -(top + 10))
    e.button:Show()
    top = top + 10 + SD.BTN_H + 2
  else
    e.button:Hide()
  end
  local h = top + SD.EMPTY_PAD
  e.frame:ClearAllPoints()
  e.frame:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
  e.frame:SetSize(width, h)
  e.frame:Show()
  return y + h
end

-- The open row's receipt under its own 52px, inside its outline. Returns the receipt's height.
local function openReceipt(row, width)
  local r, rc = row.sale, view.receipt
  local cols = R.Columns(r, { market = row.market, canSave = r.canSave, bags = bagsOf(row.info.id) })
  local h = GC.SoldReceiptUI.Paint(rc, r, { id = row.saleID, info = row.info, cols = cols, entry = r.entry },
    width - 2 * SD.OPEN_INSET, view.helpers)
  rc.frame:ClearAllPoints()
  rc.frame:SetPoint("TOPLEFT", row, "TOPLEFT", SD.OPEN_INSET, -row.topH)
  if rc.frame.SetFrameLevel and row.GetFrameLevel then rc.frame:SetFrameLevel((row:GetFrameLevel() or 0) + 2) end
  rc.frame:Show()
  row.outline:Show(); row.openFill:Show()
  return h
end

local function renderList(m, width, top, bottom)
  local entries = listEntries(m)
  local rows = view.rows
  for i = #rows + 1, #entries do rows[i] = createRow(view.content) end
  local need = { mkt = 0, got = 0, profit = 0 }
  for i, entry in ipairs(entries) do
    paintRow(rows[i], entry, m.now)
    if entry.kind == "sale" then
      local row = rows[i]
      for _, key in ipairs({ "got", "profit" }) do need[key] = math.max(need[key], widthOf(row.cells[key])) end
      if row.pct then need.mkt = math.max(need.mkt, SD.MKT_BAR_W + SD.MKT_GAP + widthOf(row.cells.mkt)) end
    end
  end
  local cols = {}
  for _, key in ipairs({ "mkt", "got", "profit" }) do
    cols[#cols + 1] = { key = key, need = need[key] > 0 and need[key] + 2 or 0 }
  end
  local fit = V.FitColumns(width - 2 * SD.PAD_X - SD.CHEVRON - SD.COL_GAP, cols, SD.COL_GAP, SD.ITEM_MIN, { "mkt" })
  -- No row with an exact market price this render: the mark's column takes no room at all.
  if need.mkt == 0 then fit.hidden.mkt = true end
  view.fit = fit
  view.scroll:ClearAllPoints()
  view.scroll:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -top)
  view.scroll:SetPoint("BOTTOMRIGHT", view.container, "BOTTOMRIGHT", 0, bottom)
  -- The receipt is not hidden ahead of the layout: an open one is moved, never hidden and shown
  -- again, so its cost box keeps the keyboard while the player types (see openReceipt).
  local y, opened = 0, false
  for i = 1, #entries do
    local row = rows[i]
    local h = layoutRow(row, width, fit)
    row.topH = h
    if row.isOpen then
      h = h + openReceipt(row, width) + SD.OPEN_INSET
      opened = true
    end
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, -y)
    row:Show()
    y = y + h
  end
  -- The open sale left the list (the period, a search): nothing stays open behind it.
  if not opened then
    state.open = nil
    GC.SoldReceiptUI.Close(view.receipt)
  end
  for i = #entries + 1, #rows do rows[i]:Hide() end
  y = layoutEmpty(m, width, y)
  view.content:SetHeight(math.max(1, y))
end

local function currentWidth()
  local w = view.container:GetWidth()
  if w and w > 0 then view.width = w end
  return view.width or 600
end

local function render()
  if not view.container then return end
  local width = currentWidth()
  view.content:SetWidth(width)
  local m = buildModel()
  view.model = m
  local y = layoutHeader(width)
  y = layoutCards(m, width, y) + SD.GAP
  local bottom = layoutFoot(m, width)
  renderList(m, width, y, bottom)
end

--- Opens a sale's receipt, or closes it when it is the one open (a second click). One at a time.
function Sold.Toggle(id)
  state.open = state.open ~= id and id or nil
  render()
end

-- Building ---------------------------------------------------------------------------------

local function createCard(parent)
  local card = { frame = Theme.Card(parent, COLOR.tile, Theme.color.border, true) }
  card.label = Theme.Num(card.frame, 9, true)
  card.value = Theme.Num(card.frame, 17, true)
  card.small = Theme.Num(card.frame, 12, true)
  card.name = Theme.Label(card.frame, 12)
  card.sub = Theme.Num(card.frame, 10)
  for _, fs in ipairs(cardParts(card)) do fs:SetJustifyH("LEFT") end
  card.iconEdge = card.frame:CreateTexture(nil, "BORDER")
  card.iconEdge:SetSize(22, 22)
  card.icon = card.frame:CreateTexture(nil, "ARTWORK")
  card.icon:SetSize(20, 20)
  card.icon:SetPoint("CENTER", card.iconEdge, "CENTER")
  card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- The ring: RING_DOTS small squares on a circle, no ring art needed, the percent in the middle.
  local ring = CreateFrame("Frame", nil, card.frame)
  ring:SetSize(SD.RING, SD.RING)
  ring.dots = {}
  local radius = (SD.RING - SD.RING_DOT) / 2
  for i = 1, SD.RING_DOTS do
    local a = (i - 1) / SD.RING_DOTS * 2 * math.pi
    local dot = Theme.Solid(ring, "ARTWORK", GC.Kit.Tokens.ink(0.14))
    dot:SetSize(SD.RING_DOT, SD.RING_DOT)
    dot:SetPoint("CENTER", ring, "CENTER", math.floor(radius * math.sin(a) + 0.5), math.floor(radius * math.cos(a) + 0.5))
    ring.dots[i] = dot
  end
  ring.pct = Theme.Num(ring, 9, true)
  ring.pct:SetPoint("CENTER", ring, "CENTER", 0, 0)
  ring.pct:SetJustifyH("CENTER")
  setColor(ring.pct, Theme.color.goldHi)
  card.ring = ring
  -- The Road to 40 card on hover: its sums as a short table, a label and an amount a row, then the
  -- forecast sentence. /gc mount's chat sentence with four amounts in it wrapped to three lines of
  -- coins here and could not be read (owner, 2026-11-16).
  card.frame:EnableMouse(true)
  card.frame:SetScript("OnEnter", function(self)
    local s = card.road
    if not (GameTooltip and s and GC.ForeverRoad and GC.ForeverRoad.Lines) then return end
    local tip = GC.Util.ClientText
    local coin = GC.Util.CoinText
    local title, body, dim, white, green = B.tipTitle, B.tipBody, B.text3, COLOR.white, Theme.color.green
    local function pair(left, right, rc)
      GameTooltip:AddDoubleLine(tip(left), tip(right), dim[1], dim[2], dim[3], rc[1], rc[2], rc[3])
    end
    GameTooltip:SetOwner(self, Theme.TooltipAnchor and Theme.TooltipAnchor(self) or "ANCHOR_RIGHT")
    GameTooltip:SetText(tip(GC.L["ROAD TO 40"]), title[1], title[2], title[3])
    pair(GC.L["Gold you carry"], coin(s.money or 0), white)
    pair(GC.L["Your bags"], coin(s.bags or 0), white)
    if type(s.cost) == "number" and s.cost > 0 then pair(GC.L["Riding cost"], coin(s.cost), white) end
    if (s.gainItems or 0) > 0 and (s.gain or 0) > 0 then
      pair(GC.L["%d items fetch more on the AH"]:format(s.gainItems), "+" .. coin(s.gain), green)
    end
    local forecast = GC.ForeverRoad.Lines(s)[2]
    if forecast then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(GC.Util.WrapText(tip(forecast)), body[1], body[2], body[3], true)
    end
    GameTooltip:Show()
  end)
  card.frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return card
end

local function createFoot(parent)
  local green = Theme.color.green
  local f = { frame = CreateFrame("Frame", nil, parent) }
  f.rule = Theme.Solid(f.frame, "ARTWORK", Theme.color.border)
  f.rule:SetHeight(1)
  f.rule:SetPoint("TOPLEFT", f.frame, "TOPLEFT", 0, 0)
  f.rule:SetPoint("TOPRIGHT", f.frame, "TOPRIGHT", 0, 0)
  f.text = Theme.Num(f.frame, 10)
  f.text:SetJustifyH("LEFT")
  setColor(f.text, Theme.color.fgMuted)
  f.icon = f.frame:CreateTexture(nil, "ARTWORK")
  Theme.SetIcon(f.icon, "trend")
  f.icon:SetVertexColor(green[1], green[2], green[3], 1)
  f.icon:SetSize(SD.GLYPH + 2, SD.GLYPH + 2)
  f.icon:SetPoint("LEFT", f.frame, "LEFT", 0, 0)
  f.text:SetPoint("LEFT", f.icon, "RIGHT", SD.GLYPH_GAP, 0)
  -- A quiet ghost button, its label in gold with a caret after it: "OPEN SELL >".
  f.button = Theme.Button(f.frame, "ghost", "badge")
  f.button:SetPoint("RIGHT", f.frame, "RIGHT", 0, 0)
  f.button.bg:SetVertexColor(1, 1, 1, 0) -- untinted
  setColor(f.button.text, Theme.color.goldHi)
  f.caret = f.button:CreateTexture(nil, "OVERLAY")
  Theme.SetIcon(f.caret, "caretRight", Theme.color.goldHi)
  f.caret:SetSize(SD.GLYPH, SD.GLYPH)
  f.caret:SetPoint("RIGHT", f.button, "RIGHT", -SD.BTN_PAD / 2, 0)
  f.button:SetScript("OnClick", function()
    if GC.Sniper and GC.Sniper.ShowView then GC.Sniper.ShowView("sell") end
  end)
  f.frame:Hide()
  return f
end

local function createHead(parent)
  local h = { chips = {} }
  h.title = Theme.Heading and Theme.Heading(parent, 14) or Theme.Num(parent, 14, true)
  h.title:SetJustifyH("LEFT")
  setColor(h.title, Theme.color.goldHi)
  h.group = Theme.Card(parent, COLOR.tile, Theme.color.border, true)
  for _, period in ipairs(V.PERIODS) do
    local chip = Theme.Button(h.group, "ghost", "badge")
    chip:SetScript("OnClick", function()
      state.period = period
      render()
    end)
    h.chips[period] = chip
  end
  local dim = Theme.color.fgDim
  -- The search button: a magnifier that reveals the box, and hides it again (clearing it).
  h.find = Theme.Button(parent, "ghost", "badge")
  h.find.glyph = h.find:CreateTexture(nil, "OVERLAY")
  Theme.SetIcon(h.find.glyph, "search", dim)
  h.find.glyph:SetSize(SD.GLYPH, SD.GLYPH)
  h.find.glyph:SetPoint("CENTER", h.find, "CENTER", 0, 0)

  h.well = Theme.Card(parent, COLOR.tile, GC.Kit.Tokens.ink(0.08), true)
  h.glass = h.well:CreateTexture(nil, "ARTWORK")
  Theme.SetIcon(h.glass, "search")
  h.glass:SetVertexColor(dim[1], dim[2], dim[3], 1)
  h.glass:SetSize(SD.GLYPH, SD.GLYPH)
  h.glass:SetPoint("LEFT", h.well, "LEFT", SD.SEARCH_PAD, 0)
  h.close = Theme.Button(h.well, "ghost", "badge")
  h.close:SetSize(SD.GLYPH + 8, SD.GLYPH + 8)
  h.close:SetPoint("RIGHT", h.well, "RIGHT", -4, 0)
  h.close.bg:SetVertexColor(1, 1, 1, 0) -- untinted
  h.close.glyph = h.close:CreateTexture(nil, "OVERLAY")
  Theme.SetIcon(h.close.glyph, "close", dim)
  h.close.glyph:SetSize(SD.GLYPH - 2, SD.GLYPH - 2)
  h.close.glyph:SetPoint("CENTER", h.close, "CENTER", 0, 0)
  local search = CreateFrame("EditBox", nil, h.well)
  search:SetAutoFocus(false)
  search:SetPoint("TOPLEFT", SD.SEARCH_PAD + SD.GLYPH + SD.GLYPH_GAP, -2)
  search:SetPoint("BOTTOMRIGHT", -(SD.GLYPH + 14), 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if search.SetFont then
    search:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    search:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    if Theme.OnRescale then Theme.OnRescale(function(scale) search:SetFont(Theme.FONT_UI, 11 * scale, "") end) end
  end
  h.search = search
  h.hint = Theme.Num(h.well, 10)
  h.hint:SetJustifyH("LEFT")
  h.hint:SetPoint("LEFT", h.glass, "RIGHT", SD.GLYPH_GAP, 0)
  setColor(h.hint, dim)
  local function hint()
    local text = search:GetText() or ""
    if text ~= "" or (search.HasFocus and search:HasFocus()) then h.hint:Hide() else h.hint:Show() end
  end
  -- Closing the box clears it: a list narrowed by a box nobody can see is a list that looks broken.
  local function shut()
    search:SetText("")
    search:ClearFocus()
    state.query, state.searchOpen = "", false
    render()
  end
  h.find:SetScript("OnClick", function()
    if state.searchOpen or (search:GetText() or "") ~= "" then return shut() end
    state.searchOpen = true
    render()
    if search.SetFocus then search:SetFocus() end
  end)
  h.close:SetScript("OnClick", shut)
  search:SetScript("OnTextChanged", function(_, byUser)
    state.query = search:GetText() or ""
    hint()
    if byUser then render() end
  end)
  search:SetScript("OnEditFocusGained", hint)
  search:SetScript("OnEditFocusLost", hint)
  search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
  search:SetScript("OnEscapePressed", shut)
  return h
end

local function createEmpty(parent)
  local e = { frame = Theme.Card(parent, COLOR.empty, GC.Kit.Tokens.ink(0.07), true) }
  e.icon = e.frame:CreateTexture(nil, "ARTWORK")
  Theme.SetIcon(e.icon, "mail")
  local gold = Theme.color.goldHi
  e.icon:SetVertexColor(gold[1], gold[2], gold[3], 1)
  e.icon:SetSize(26, 26)
  e.icon:Hide()
  e.message = Theme.Label(e.frame, 13)
  e.message:SetJustifyH("CENTER")
  e.sub = Theme.Num(e.frame, 10)
  e.sub:SetJustifyH("CENTER")
  setColor(e.sub, Theme.color.fgDim)
  e.button = Theme.Button(e.frame, "ghost", "plaque")
  local gc = Theme.color.gold
  -- A plate's ring is baked in colour: a tint would spoil it.
  if e.button.ring and not e.button.plate then e.button.ring:SetVertexColor(gc[1], gc[2], gc[3], 0.5) end
  e.button.bg:SetVertexColor(1, 1, 1, 0) -- untinted
  setColor(e.button.text, Theme.color.goldHi)
  e.button:SetScript("OnClick", function()
    state.period = "30d"
    render()
  end)
  e.frame:Hide()
  return e
end

-- Builds the tab's container, hidden, over the same region the Deals list occupies --
-- geometry passed through from createFrame, never re-declared, exactly like GC.Sell.Attach.
-- Only the container and its scroll are made here; the header, cards and receipt wait for the
-- tab's first Show (build below), so a session that never opens Sold never makes them.
function Sold.Attach(f, geo)
  Theme, V, R = GC.Theme, GC.SoldView, GC.SoldReceipt
  local container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()
  view.container, view.width = container, geo.rowWidth

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
  scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT")
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, SD.ROW_H)
  scroll:SetScrollChild(content)
  view.scroll, view.content = scroll, content

  -- A resize, a dock reparent or a font-scale change moves every measured width, so the tab is
  -- laid out again whole. A frame resized while hidden does not reliably fire OnSizeChanged;
  -- Show() lays it out anyway.
  container:HookScript("OnSizeChanged", function(_, width)
    if width and width > 0 then view.width = width end
    if container:IsVisible() and view.cards then render() end
  end)
  if Theme.OnRescale then
    Theme.OnRescale(function() if container:IsVisible() and view.cards then render() end end)
  end
end

local function build()
  if view.cards then return end
  local container = view.container
  view.head = createHead(container)
  view.cards = { createCard(container), createCard(container), createCard(container), createCard(container) }
  view.foot = createFoot(container)
  view.empty = createEmpty(view.content)
  view.helpers = { put = put, setLabel = setLabel, widthOf = widthOf, heightOf = heightOf, wrapTo = wrapTo,
    hug = hug, setColor = setColor, plain = plain, signed = signed, clock = clock, shortDate = shortDate,
    isToday = function(at) return isToday(at, time()) end, render = render,
    close = function() if state.open then Sold.Toggle(state.open) end end }
  view.receipt = GC.SoldReceiptUI.Create(view.content, view.helpers)
end

function Sold.Show()
  if not view.container then return end
  view.container:Show()
  build()
  view.restamp = true -- see put(): every string is drawn again after the hide
  render()
  view.restamp = false
end

-- The window's status line is not this tab's to show or hide: the Sniper's setView keeps it to
-- Deals. This used to hand it back shown on the way out, which put it over Sell's MY LOTS.
function Sold.Hide()
  if view.container then view.container:Hide() end
end

-- Called from GC.Ledger.ScanInbox (a mailbox scan is when sales appear) and from Road to 40's
-- money and cost changes.
function Sold.RefreshIfShown()
  -- IsVisible: with the window closed and Sold still the chosen tab, the container is "shown"
  -- but nothing under it is drawn, and strings written then come back blank (see put()). The
  -- window's OnShow calls Show, which draws everything again.
  if view.container and view.container:IsVisible() and view.cards then render() end
end
