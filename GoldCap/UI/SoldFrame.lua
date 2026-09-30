local _, GC = ...

-- The Sold tab: what the player sold, what reached the mailbox, and the profit GoldCap knows.
-- The arithmetic lives in Core/SoldView.lua; this file reads the stores, hands their rows to
-- it, and paints what comes back.
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
--     stock's sources only through the same key (GC.Acquisitions.SourcesOf). Everything else
--     says "—", never an invented number. Pro gating happened server-side: a free summary
--     carries no basis, and its rows show no profit at all.
--   * WoW: Forever has no goldcap.gg sales. Its local sales are the whole list, grouped by day,
--     and a snapshot is never read there.
--
-- Layout, top to bottom: three summary tiles, the Forever banner (bag items worth more on the
-- auction house), the period chips and the search box, the column headings, the list.
--
-- Nothing is cut short. Every figure column is as wide as the widest text it holds this render,
-- heading included -- measured with GetUnboundedStringWidth, so the active language and the
-- font scale are both in the number -- and ITEM takes what is left. Sentences (tile lines, the
-- banner, section notes, hints, the empty state) wrap inside a box that grows. The one string
-- the engine may still shorten is an item NAME on a window too narrow for it; the row's
-- tooltip then carries the full name.
GC.Sold = {}
local Sold = GC.Sold

local Theme, V

-- Every widget the tab owns. A field on GC.Sold so the module's own spec can read the pool and
-- the tiles without reaching into upvalues; nothing else reads it.
local view = { rows = {} }
Sold._view = view
local state = { period = "7d", query = "" }
Sold._state = state

local SD = {
  GAP = 10,           -- between the tab's blocks, and between two tiles
  TILE_PAD_X = 14, TILE_PAD_Y = 11, TILE_LINE = 7, TILE_MIN_H = 74,
  BAR_H = 5,          -- bar.png's caps are 2px: under half of this
  BANNER_MIN_H = 34, BANNER_PAD_X = 12, BANNER_PAD_Y = 6,
  BTN_H = 24, BTN_PAD = 12,
  CHIP_H = 22, CHIP_PAD = 10, CHIP_GAP = 2, GROUP_PAD = 3,
  SEARCH_W = 210, SEARCH_MIN = 120, SEARCH_PAD = 10, CTRL_H = 28,
  HEAD_H = 16,
  ROW_H = 34, DAY_H = 26, ICON = 24, ICON_GAP = 10, QTY_GAP = 6,
  PAD_X = 10, COL_GAP = 10, ITEM_MIN = 110, NOTE_MIN = 80,
  EMPTY_PAD = 20,
  STALE_YELLOW = 6 * 3600, STALE_RED = 24 * 3600,
}

local HEX = {
  g = "|cffe8c15a", s = "|cffc9ced6", c = "|cffd08a5a",
  green = "|cff5fd38d", gold = "|cffe8c15a", dim = "|cff9d9d9d",
}
local COLOR = {
  tile = { 0.071, 0.078, 0.098 }, road = { 0.117, 0.112, 0.105 },
  banner = { 0.099, 0.138, 0.109 }, empty = { 0.063, 0.071, 0.090 },
  faint = { 0.459, 0.451, 0.435 }, orange = { 0.941, 0.627, 0.294 }, white = { 1, 1, 1 },
}

-- @localised-keys: literals in these tables ARE GC.L keys. They are built at FILE SCOPE, where
-- GC.L still answers in English (ApplyLocale runs at ADDON_LOADED), so each is looked up where
-- it is read. Every table closes with a `}` on its own line -- that is where the spec's scanner
-- stops.
local HEADER_TEXT = {
  item = "ITEM", when = "WHEN", each = "EACH", got = "YOU GOT", profit = "PROFIT",
}
-- @localised-keys: date("*t").wday order, Sunday first.
local WEEKDAY = {
  "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT",
}
-- @localised-keys: where the stock a sale drew on came from (GC.Acquisitions batch sources).
local SOURCE_TEXT = {
  goldcap = "Sniper", goldcap_buy = "BUY list", manual = "set by you", auction_house = "the auction house",
  craft = "crafted",
}

local COLS = { "when", "each", "got", "profit" }

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
-- two quality ranks of one reagent share a name, so a tooltip or a market price read off a
-- name could describe the other rank. Only an exact id (the sale's own, or the position its
-- profit was matched to) opens the item's tooltip.
local byName = {}
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
  if not icon and quality == nil then return nil end
  byName[name] = { icon = icon, quality = quality }
  return byName[name]
end

local function qualityColor(quality)
  if type(quality) ~= "number" or quality < 2 then return nil end
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
  return { id = id, icon = icon or _G.QUESTION_MARK_ICON or 134400, color = qualityColor(quality) }
end

-- The market price the tooltip compares a sale with: the figure GoldCap's own item tooltip
-- prices the item at (UI/Tooltip.lua), for an item priced as one thing. A realm item's figure
-- is one item level's or one realm's median, and a piece of Forever gear's is its cheapest
-- version's; the copy that sold may have been another, so those are never compared.
local function marketFor(itemID)
  if not (itemID and GC.Data and GC.Data.GetItemValue) then return nil end
  local ok, v = pcall(GC.Data.GetItemValue, itemID)
  if not ok or type(v) ~= "table" or v.gear or v.kind == "realm_item" then return nil end
  return type(v.mv) == "number" and v.mv > 0 and v.mv or nil
end

-- The model ---------------------------------------------------------------------------------

local function buildModel()
  local isForever = GC.Game and GC.Game.IsForever and GC.Game.IsForever(GC.Game.Passport()) or false
  local summary = not isForever and GC.AppLedger and GC.AppLedger.GetSummary and GC.AppLedger.GetSummary() or nil
  local now = time()
  local m = { isForever = isForever, summary = summary, now = now,
    from = V.PeriodStart(state.period, now, dateOf) }
  local realized = {}
  if GC.Acquisitions and GC.Acquisitions.GetRealized then
    for _, row in ipairs(GC.Acquisitions.GetRealized()) do
      if row.evidenceKey then realized[row.evidenceKey] = row end
    end
  end
  local sourcesOf = GC.Acquisitions and GC.Acquisitions.SourcesOf
  local entries = GC.Ledger and GC.Ledger.GetEntries and GC.Ledger.GetEntries() or {}
  local locals, servers = {}, {}
  for _, sale in ipairs(V.LocalSales(entries, V.Boundary(summary))) do
    local hit = sale.key and realized[sale.key] or nil
    locals[#locals + 1] = V.LocalRow(sale, hit, hit and sourcesOf and sourcesOf(sale.key) or nil)
  end
  for _, sale in ipairs(summary and summary.sales or {}) do servers[#servers + 1] = V.ServerRow(sale) end
  m.anySales = #locals + #servers > 0
  m.locals = V.Filter(locals, m.from, state.query)
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

-- Tiles ------------------------------------------------------------------------------------

local function tileParts(tile)
  return { tile.label, tile.value, tile.small, tile.name, tile.sub }
end

-- A tile's headline figure, in the big face; stackTile moves it to the smaller one when it is
-- wider than the tile.
local function putValue(tile, text, color)
  put(tile.value, text)
  setColor(tile.value, color)
  tile.valueColor = color
end

local function resetTile(tile)
  for _, fs in ipairs(tileParts(tile)) do fs:Hide() end
  tile.bar:Hide()
  tile.icon:Hide(); tile.iconEdge:Hide()
  tile.frame:SetTint(COLOR.tile, Theme.color.border)
  setColor(tile.label, Theme.color.fgDim)
  setColor(tile.value, Theme.color.fg)
  setColor(tile.small, Theme.color.fg)
  setColor(tile.sub, Theme.color.fgDim)
  tile.hasBar, tile.hasIcon, tile.road = false, false, nil
end

local function paintGot(tile, m)
  put(tile.label, GC.L["YOU GOT · %s"]:format(periodLabel(state.period)))
  putValue(tile, coins(m.totals.net), Theme.color.fg)
  local count = m.totals.count
  local sub
  if m.truncated then sub = GC.L["%d here · all on goldcap.gg"]:format(count)
  elseif count == 1 then sub = GC.L["1 sale · after the AH cut"]
  else sub = GC.L["%d sales · after the AH cut"]:format(count) end
  put(tile.sub, sub)
end

local function paintProfit(tile, m)
  put(tile.label, GC.L["PROFIT"])
  local t = m.totals
  if t.known > 0 then
    putValue(tile, signed(t.profit), t.profit >= 0 and Theme.color.green or Theme.color.red)
  else
    putValue(tile, "—", COLOR.faint)
  end
  if t.count > 0 then put(tile.sub, GC.L["cost known for %d of %d"]:format(t.known, t.count)) end
end

local function paintRoad(tile, s)
  local gc = Theme.color.gold
  tile.frame:SetTint(COLOR.road, { gc[1], gc[2], gc[3], 0.22 })
  tile.road = s
  put(tile.label, GC.L["ROAD TO 40"])
  setColor(tile.label, Theme.color.goldHi)
  local have = (s.money or 0) + (s.bags or 0)
  if type(s.cost) == "number" and s.cost > 0 then
    put(tile.small, GC.L["%s of %s"]:format(coins(have), coins(s.cost)))
    tile.hasBar = true
    tile.progress = V.Progress(have, s.cost)
  else
    put(tile.small, GC.L["%s · gold %s, bags %s"]:format(coins(have), coins(s.money or 0), coins(s.bags or 0)))
    put(tile.sub, GC.L["set the riding cost: %s"]:format(HEX.gold .. "/gc mount 90g|r"))
  end
end

local function paintSynced(tile, m)
  local s = m.summary
  put(tile.label, GC.L["GOLDCAP.GG · %d DAYS"]:format(s.days))
  local age = math.max(0, m.now - (s.generatedAt or m.now))
  local ago = GC.Util.FormatAge(age)
  if type(s.totals.realized) == "number" then
    putValue(tile, signed(s.totals.realized), s.totals.realized >= 0 and Theme.color.green or Theme.color.red)
    put(tile.sub, GC.L["profit · synced %s ago"]:format(ago))
  else
    putValue(tile, coins(s.totals.proceeds or 0), Theme.color.fg)
    put(tile.sub, GC.L["after the AH cut · synced %s ago"]:format(ago))
  end
  if age >= SD.STALE_RED then setColor(tile.sub, Theme.color.red)
  elseif age >= SD.STALE_YELLOW then setColor(tile.sub, Theme.tier.SUSPECT) end
end

local function paintBest(tile, m)
  put(tile.label, GC.L["BEST SALE"])
  local best = m.best
  if not best then
    put(tile.small, "—")
    setColor(tile.small, COLOR.faint)
    put(tile.sub, GC.L["no sale with a known profit yet"])
    return
  end
  local info = itemInfo(best)
  tile.icon:SetTexture(info.icon)
  local edge = info.color and { info.color[1], info.color[2], info.color[3], 0.6 } or { 1, 1, 1, 0.16 }
  tile.iconEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
  tile.icon:Show(); tile.iconEdge:Show()
  tile.hasIcon = true
  put(tile.name, best.name or GC.L["Unknown item"])
  setColor(tile.name, info.color or Theme.color.fg)
  put(tile.sub, GC.L["%s profit"]:format(signed(best.profit)))
  setColor(tile.sub, Theme.color.green)
end

-- Stacks a tile's shown parts top-down inside `inner` and says how tall they came out.
local function stackTile(tile, inner)
  local y = SD.TILE_PAD_Y - SD.TILE_LINE -- the first part sits at TILE_PAD_Y
  local function place(fs, width)
    local h = wrapTo(fs, width)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", tile.frame, "TOPLEFT", SD.TILE_PAD_X, -(y + SD.TILE_LINE))
    y = y + SD.TILE_LINE + h
  end
  if tile.label:IsShown() then place(tile.label, inner) end
  if tile.value:IsShown() and widthOf(tile.value) > inner and not tile.small:IsShown() then
    -- A figure too wide for the tile at the big size (a retail total, the largest font scale,
    -- the narrowest window) steps down to the tile's smaller face rather than be cut.
    tile.value:Hide()
    put(tile.small, tile.value:GetText())
    setColor(tile.small, tile.valueColor)
  end
  if tile.value:IsShown() then place(tile.value, inner) end
  if tile.small:IsShown() then place(tile.small, inner) end
  if tile.hasIcon then
    -- The best sale: its icon beside its name, the name wrapping in what the icon leaves.
    local h = wrapTo(tile.name, inner - 28)
    local line, top = math.max(h, 22), y + SD.TILE_LINE
    tile.iconEdge:ClearAllPoints()
    tile.iconEdge:SetPoint("TOPLEFT", tile.frame, "TOPLEFT", SD.TILE_PAD_X, -(top + (line - 22) / 2))
    tile.name:ClearAllPoints()
    tile.name:SetPoint("TOPLEFT", tile.frame, "TOPLEFT", SD.TILE_PAD_X + 28, -(top + (line - h) / 2))
    y = top + line
  end
  if tile.hasBar then
    y = y + SD.TILE_LINE
    tile.bar:ClearAllPoints()
    tile.bar:SetPoint("TOPLEFT", tile.frame, "TOPLEFT", SD.TILE_PAD_X, -y)
    tile.bar:SetSize(inner, SD.BAR_H)
    tile.bar.fill:SetWidth(math.max(SD.BAR_H, inner * (tile.progress or 0)))
    if (tile.progress or 0) > 0 then tile.bar.fill:Show() else tile.bar.fill:Hide() end
    tile.bar:Show()
    y = y + SD.BAR_H
  end
  if tile.sub:IsShown() then place(tile.sub, inner) end
  return y + SD.TILE_PAD_Y
end

local function layoutTiles(m, width)
  local tiles = view.tiles
  for _, tile in ipairs(tiles) do resetTile(tile) end
  paintGot(tiles[1], m)
  paintProfit(tiles[2], m)
  if m.road then paintRoad(tiles[3], m.road)
  elseif m.summary then paintSynced(tiles[3], m)
  else paintBest(tiles[3], m) end
  local w = math.floor((width - 2 * SD.GAP) / 3)
  local height = SD.TILE_MIN_H
  for _, tile in ipairs(tiles) do height = math.max(height, stackTile(tile, w - 2 * SD.TILE_PAD_X)) end
  for i, tile in ipairs(tiles) do
    tile.frame:ClearAllPoints()
    tile.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", (i - 1) * (w + SD.GAP), 0)
    tile.frame:SetSize(w, height)
  end
  return height
end

-- The Forever banner: bag items the auction house pays more for than a vendor, and the way to
-- the tab that sells them. The sentence wraps and the banner grows; the button is as wide as
-- its own label.
local function layoutBanner(m, width, y)
  local b = view.banner
  local s = m.road
  if not (s and (s.gainItems or 0) > 0 and (s.gain or 0) > 0) then
    b.frame:Hide()
    return y
  end
  setLabel(b.button, GC.L["OPEN SELL"])
  local bw = widthOf(b.button.text) + 2 * SD.BTN_PAD
  b.button:SetSize(bw, SD.BTN_H)
  put(b.text, GC.L["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."]
    :format(s.gainItems, HEX.green .. plain(s.gain) .. "|r"))
  local th = wrapTo(b.text, width - 2 * SD.BANNER_PAD_X - bw - SD.GAP)
  local h = math.max(SD.BANNER_MIN_H, th + 2 * SD.BANNER_PAD_Y, SD.BTN_H + 2 * SD.BANNER_PAD_Y)
  b.frame:ClearAllPoints()
  b.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -y)
  b.frame:SetSize(width, h)
  b.frame:Show()
  return y + h + SD.GAP
end

-- The period chips and the search box. The chips are as wide as their labels; the search box
-- takes up to SEARCH_W of what is left on the line, or a line of its own when too little is.
local function layoutControls(width, y)
  local c = view.controls
  local x = SD.GROUP_PAD
  for _, period in ipairs(V.PERIODS) do
    local chip = c.chips[period]
    setLabel(chip, periodLabel(period))
    local w = widthOf(chip.text) + 2 * SD.CHIP_PAD
    chip:SetSize(w, SD.CHIP_H)
    chip:ClearAllPoints()
    chip:SetPoint("LEFT", c.group, "LEFT", x, 0)
    x = x + w + SD.CHIP_GAP
    if period == state.period then
      chip:SetVariant("active")
    else
      chip:SetVariant("ghost")
      chip.bg:SetVertexColor(1, 1, 1, 0)
      setColor(chip.text, Theme.color.fgDim)
    end
  end
  local groupW = x - SD.CHIP_GAP + SD.GROUP_PAD
  c.group:ClearAllPoints()
  c.group:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -y)
  c.group:SetSize(groupW, SD.CTRL_H)

  put(c.hint, GC.L["Find an item"])
  local least = math.max(SD.SEARCH_MIN, hug(c.hint) + 2 * SD.SEARCH_PAD)
  local room = width - groupW - SD.GAP
  local searchW, searchY = math.min(math.max(SD.SEARCH_W, least), room), y
  if room < least then searchW, searchY = math.min(width, math.max(least, SD.SEARCH_W)), y + SD.CTRL_H + SD.GAP / 2 end
  c.well:ClearAllPoints()
  c.well:SetPoint("TOPRIGHT", view.container, "TOPRIGHT", 0, -searchY)
  c.well:SetSize(searchW, SD.CTRL_H)
  local text = c.search:GetText() or ""
  if text ~= "" or (c.search.HasFocus and c.search:HasFocus()) then c.hint:Hide() end
  return searchY + SD.CTRL_H + SD.GAP
end

-- Rows -------------------------------------------------------------------------------------

local function whenText(r, grouped, now)
  if r.pending then return GC.L["in the mail"] end
  if grouped or isToday(r.at, now) then return clock(r.at) end
  return shortDate(r.at)
end

local function profitText(r)
  if type(r.profit) == "number" then
    local text = signed(r.profit)
    if r.costUnits then text = text .. "  " .. HEX.dim .. ("%d/%d"):format(r.costUnits, r.qty) .. "|r" end
    return text, r.profit >= 0 and Theme.color.green or Theme.color.red
  end
  -- A free account is told nothing about profit: an empty cell, not a dash that implies a
  -- cost was looked for.
  if r.noBasis then return "", COLOR.faint end
  return "—", COLOR.faint
end

local function clearRow(row)
  row.name:Hide(); row.qty:Hide(); row.icon:Hide(); row.iconEdge:Hide()
  row.title:Hide(); row.note:Hide(); row.rule:Hide(); row.wide:Hide()
  for _, key in ipairs(COLS) do row.cells[key]:Hide() end
  row.highlight:SetAlpha(0)
  row.sale, row.info = nil, nil
end

-- Pass one: the texts. The table's columns are fitted to what these come out as.
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
  row.sale, row.info = r, itemInfo(r)
  row.highlight:SetAlpha(1)
  row.icon:SetTexture(row.info.icon)
  local c = row.info.color
  local edge = c and { c[1], c[2], c[3], 0.6 } or { 1, 1, 1, 0.16 }
  row.iconEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
  row.icon:Show(); row.iconEdge:Show()
  put(row.name, r.name or GC.L["Unknown item"])
  setColor(row.name, c or Theme.color.fg)
  put(row.qty, "×" .. tostring(r.qty))
  put(row.cells.when, whenText(r, entry.grouped, now))
  setColor(row.cells.when, r.pending and Theme.color.goldHi or Theme.color.fgDim)
  put(row.cells.each, r.each and coins(r.each) or "")
  put(row.cells.got, coins(r.net))
  local text, color = profitText(r)
  put(row.cells.profit, text)
  setColor(row.cells.profit, color)
end

-- Pass two: the anchors, now that the columns are fitted. Returns the row's height.
local function layoutRow(row, width, fit)
  local inner = width - 2 * SD.PAD_X
  if row.kind == "hint" then
    local h = wrapTo(row.wide, inner)
    row.wide:ClearAllPoints()
    row.wide:SetPoint("TOP", row, "TOP", 0, -8)
    return h + 16
  end
  if row.kind == "head" then
    local titleW = math.min(widthOf(row.title), inner)
    local th = wrapTo(row.title, titleW)
    local noteRoom = inner - titleW - SD.GAP
    local nh
    row.note:ClearAllPoints()
    if noteRoom >= SD.NOTE_MIN then
      nh = wrapTo(row.note, math.min(noteRoom, widthOf(row.note)))
      row.note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -SD.PAD_X, 5)
    else
      -- No room beside the title: the note takes a line of its own under it.
      nh = wrapTo(row.note, inner)
      row.note:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SD.PAD_X, 5)
      th = th + nh + 2
    end
    row.title:ClearAllPoints()
    row.title:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SD.PAD_X, 5 + (noteRoom >= SD.NOTE_MIN and 0 or nh + 2))
    row.note:SetJustifyH(noteRoom >= SD.NOTE_MIN and "RIGHT" or "LEFT")
    return math.max(SD.DAY_H, th + 11, nh + 11)
  end
  -- A sale: the fixed columns right to left off the row's edge, ITEM in what is left.
  local right = SD.PAD_X
  local leftmost = width - SD.PAD_X
  for i = #COLS, 1, -1 do
    local key = COLS[i]
    local cell = row.cells[key]
    if fit.hidden[key] then
      cell:Hide()
    else
      cell:SetWidth(fit.widths[key])
      cell:ClearAllPoints()
      cell:SetPoint("RIGHT", row, "RIGHT", -right, 0)
      leftmost = width - right - fit.widths[key]
      right = right + fit.widths[key] + SD.COL_GAP
    end
  end
  row.iconEdge:ClearAllPoints()
  row.iconEdge:SetPoint("LEFT", row, "LEFT", SD.PAD_X, 0)
  local qtyW = hug(row.qty)
  local nameRoom = leftmost - SD.COL_GAP - (SD.PAD_X + SD.ICON + 2 + SD.ICON_GAP) - SD.QTY_GAP - qtyW
  if nameRoom < 24 then
    -- Too narrow for the name and the count both: the count goes (the tooltip says "14 × 75c"),
    -- so it cannot run into the first figure column.
    row.qty:Hide()
    nameRoom = nameRoom + SD.QTY_GAP + qtyW
  end
  local nameW = math.max(1, math.min(widthOf(row.name), nameRoom))
  -- The one string the engine may still shorten: an item name on a window too narrow for it.
  -- The full name is on the row's tooltip.
  row.name:SetWordWrap(false)
  if row.name.SetMaxLines then row.name:SetMaxLines(1) end
  row.name:SetWidth(nameW)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row.iconEdge, "RIGHT", SD.ICON_GAP, 0)
  row.qty:ClearAllPoints()
  row.qty:SetPoint("LEFT", row.name, "RIGHT", SD.QTY_GAP, 0)
  return SD.ROW_H
end

local function saleTooltip(row)
  local r, info = row.sale, row.info
  if not (GameTooltip and r and info) then return end
  local anchor = Theme.TooltipAnchor and Theme.TooltipAnchor(row) or "ANCHOR_RIGHT"
  GameTooltip:SetOwner(row, anchor)
  if info.id and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(info.id)
  else
    local c = info.color or COLOR.white
    GameTooltip:SetText(r.name or GC.L["Unknown item"], c[1], c[2], c[3])
  end
  local dim, body, white = Theme.color.fgDim, { 0.85, 0.85, 0.85 }, COLOR.white
  local function line(text, c, wrap) GameTooltip:AddLine(text, c[1], c[2], c[3], wrap) end
  local function pair(left, right, lc, rc) GameTooltip:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3]) end
  line(" ", dim)
  local each = plain(r.each or 0, true)
  if r.pending then
    line(GC.L["sold, the money is in your mail · %d × %s"]:format(r.qty, each), dim, true)
  elseif isToday(r.at, time()) then
    line(GC.L["sold today at %s · %d × %s"]:format(clock(r.at), r.qty, each), dim, true)
  else
    line(GC.L["sold %s at %s · %d × %s"]:format(shortDate(r.at), clock(r.at), r.qty, each), dim, true)
  end
  pair(GC.L["Sale price"], plain(r.gross, true), body, white)
  pair(r.cutEstimated and GC.L["Auction house cut, 5%"] or GC.L["Auction house cut"], "-" .. plain(r.cut, true), body, body)
  pair(GC.L["You got"], plain(r.net, true), white, white)
  line(" ", dim)
  if type(r.profit) == "number" then
    local names = {}
    for _, source in ipairs(r.sources or {}) do
      if SOURCE_TEXT[source] then names[#names + 1] = GC.L[SOURCE_TEXT[source]] end
    end
    local paid = #names > 0 and GC.L["You paid · %s"]:format(table.concat(names, ", ")) or GC.L["You paid"]
    if r.paid then pair(paid, plain(r.paid, true), body, Theme.color.cost) end
    if r.paidEach then line(GC.L["%s each"]:format(plain(r.paidEach, true)), dim) end
    if r.costUnits then line(GC.L["cost known for %d of %d"]:format(r.costUnits, r.qty), dim) end
    pair(GC.L["Profit"], signed(r.profit, true), white, r.profit >= 0 and Theme.color.green or Theme.color.red)
  elseif r.pending then
    line(GC.L["The profit is worked out once the money arrives."], body, true)
  elseif r.noBasis then
    line(GC.L["Profit tracking is a goldcap.gg Pro feature"], body, true)
  else
    line(GC.L["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."],
      body, true)
  end
  local market = info.id and marketFor(info.id)
  local pct = market and V.Percent(r.each, market)
  if pct then
    local price = plain(market, true)
    if pct > 0 then line(GC.L["Market now %s · you sold %d%% above it"]:format(price, pct), Theme.color.green, true)
    elseif pct < 0 then line(GC.L["Market now %s · you sold %d%% under it"]:format(price, -pct), COLOR.orange, true)
    else line(GC.L["Market now %s · you sold at it"]:format(price), dim, true) end
  end
  GameTooltip:Show()
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(SD.ROW_H)
  -- Hover is the engine's HIGHLIGHT layer on a mouse-enabled frame, never an OnEnter repaint.
  local hc = Theme.color.hover
  row.highlight = Theme.SlicedTexture(row, "HIGHLIGHT", Theme.MEDIA .. "plaque.png", hc, 12)
  row.highlight:SetPoint("TOPLEFT", 2, -1)
  row.highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  row:EnableMouse(true)
  -- Wired once on the pooled row; it reads whatever paintRow last stamped.
  row:SetScript("OnEnter", function(self) if self.sale then saleTooltip(self) end end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  row.iconEdge = row:CreateTexture(nil, "BORDER")
  row.iconEdge:SetSize(SD.ICON + 2, SD.ICON + 2)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(SD.ICON, SD.ICON)
  row.icon:SetPoint("CENTER", row.iconEdge, "CENTER")
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.name = Theme.Label(row, 12)
  row.name:SetJustifyH("LEFT")
  row.qty = Theme.Num(row, 10)
  row.qty:SetJustifyH("LEFT")
  setColor(row.qty, Theme.color.fgDim)

  row.cells = {
    when = Theme.Num(row, 10),
    each = Theme.Num(row, 11),
    got = Theme.Num(row, 12, true),
    profit = Theme.Num(row, 12, true),
  }
  setColor(row.cells.each, Theme.color.fgMuted)
  setColor(row.cells.got, Theme.color.fg)
  for _, key in ipairs(COLS) do
    row.cells[key]:SetJustifyH("RIGHT")
    row.cells[key]:SetWordWrap(false)
    if row.cells[key].SetMaxLines then row.cells[key]:SetMaxLines(1) end
  end

  row.title = Theme.Num(row, 9, true)
  row.title:SetJustifyH("LEFT")
  setColor(row.title, Theme.color.goldHi)
  row.note = Theme.Num(row, 10)
  setColor(row.note, Theme.color.fgDim)
  local bc = Theme.color.border
  row.rule = row:CreateTexture(nil, "ARTWORK")
  row.rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  row.rule:SetPoint("BOTTOMLEFT", 0, 0)
  row.rule:SetPoint("BOTTOMRIGHT", 0, 0)
  row.rule:SetHeight(1)

  row.wide = Theme.Label(row, 11)
  row.wide:SetJustifyH("CENTER")
  clearRow(row)
  return row
end

-- The column headings, fitted with the rows.
local function layoutHeader(width, y, fit)
  local h = view.header
  h.frame:ClearAllPoints()
  h.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -y)
  h.frame:SetSize(width, SD.HEAD_H)
  local right = SD.PAD_X
  local leftmost = width - SD.PAD_X
  for i = #COLS, 1, -1 do
    local key = COLS[i]
    local label = h.cells[key]
    if fit.hidden[key] then
      label:Hide()
    else
      label:SetWidth(fit.widths[key])
      label:ClearAllPoints()
      label:SetPoint("RIGHT", h.frame, "RIGHT", -right, 0)
      leftmost = width - right - fit.widths[key]
      right = right + fit.widths[key] + SD.COL_GAP
    end
  end
  h.cells.item:ClearAllPoints()
  h.cells.item:SetPoint("LEFT", h.frame, "LEFT", SD.PAD_X, 0)
  h.cells.item:SetWidth(math.max(1, leftmost - SD.COL_GAP - SD.PAD_X))
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
  put(e.message, message)
  local top = SD.EMPTY_PAD
  local mh = wrapTo(e.message, inner)
  e.message:ClearAllPoints()
  e.message:SetPoint("TOP", e.frame, "TOP", 0, -top)
  top = top + mh
  if sub then
    put(e.sub, sub)
    local sh = wrapTo(e.sub, inner)
    e.sub:ClearAllPoints()
    e.sub:SetPoint("TOP", e.frame, "TOP", 0, -(top + 8))
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

local function renderList(m, width, top)
  local entries = listEntries(m)
  local rows = view.rows
  for i = #rows + 1, #entries do rows[i] = createRow(view.content) end
  local need = {}
  for _, key in ipairs(COLS) do
    put(view.header.cells[key], GC.L[HEADER_TEXT[key]])
    need[key] = widthOf(view.header.cells[key])
  end
  put(view.header.cells.item, GC.L[HEADER_TEXT.item])
  for i, entry in ipairs(entries) do
    paintRow(rows[i], entry, m.now)
    if entry.kind == "sale" then
      for _, key in ipairs(COLS) do need[key] = math.max(need[key], widthOf(rows[i].cells[key])) end
    end
  end
  local cols = {}
  for _, key in ipairs(COLS) do cols[#cols + 1] = { key = key, need = need[key] + 2 } end
  local fit = V.FitColumns(width - 2 * SD.PAD_X, cols, SD.COL_GAP, SD.ITEM_MIN, { "when", "each" })
  view.fit = fit
  layoutHeader(width, top, fit)
  view.scroll:ClearAllPoints()
  view.scroll:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -(top + SD.HEAD_H + 4))
  view.scroll:SetPoint("BOTTOMRIGHT", view.container, "BOTTOMRIGHT", 0, 0)
  local y = 0
  for i = 1, #entries do
    local row = rows[i]
    local h = layoutRow(row, width, fit)
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, -y)
    row:Show()
    y = y + h
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
  local y = layoutTiles(m, width) + SD.GAP
  y = layoutBanner(m, width, y)
  y = layoutControls(width, y)
  renderList(m, width, y)
end

-- Building ---------------------------------------------------------------------------------

local function createTile(parent)
  local tile = { frame = Theme.Card(parent, COLOR.tile, Theme.color.border, true) }
  tile.label = Theme.Num(tile.frame, 9, true)
  tile.value = Theme.Num(tile.frame, 17, true)
  tile.small = Theme.Num(tile.frame, 13, true)
  tile.name = Theme.Label(tile.frame, 12)
  tile.sub = Theme.Num(tile.frame, 10)
  for _, fs in ipairs(tileParts(tile)) do fs:SetJustifyH("LEFT") end
  tile.iconEdge = tile.frame:CreateTexture(nil, "BORDER")
  tile.iconEdge:SetSize(22, 22)
  tile.icon = tile.frame:CreateTexture(nil, "ARTWORK")
  tile.icon:SetSize(20, 20)
  tile.icon:SetPoint("CENTER", tile.iconEdge, "CENTER")
  tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  tile.bar = CreateFrame("Frame", nil, tile.frame)
  local track = Theme.SlicedTexture(tile.bar, "BACKGROUND", Theme.MEDIA .. "bar.png", { 1, 1, 1, 0.07 }, 2)
  track:SetAllPoints()
  tile.bar.fill = Theme.SlicedTexture(tile.bar, "ARTWORK", Theme.MEDIA .. "bar.png", Theme.color.gold, 2)
  tile.bar.fill:SetPoint("TOPLEFT")
  tile.bar.fill:SetPoint("BOTTOMLEFT")
  -- The Road to 40 tile's forecast is the chat sentences /gc mount prints, on hover: the tile
  -- itself stays three lines.
  tile.frame:EnableMouse(true)
  tile.frame:SetScript("OnEnter", function(self)
    local s = tile.road
    if not (GameTooltip and s and GC.ForeverRoad and GC.ForeverRoad.Lines) then return end
    GameTooltip:SetOwner(self, Theme.TooltipAnchor and Theme.TooltipAnchor(self) or "ANCHOR_RIGHT")
    for i, text in ipairs(GC.ForeverRoad.Lines(s)) do
      if i == 1 then GameTooltip:AddLine(text, 1, 0.82, 0, true) else GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true) end
    end
    GameTooltip:Show()
  end)
  tile.frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return tile
end

local function createBanner(parent)
  local green = Theme.color.green
  local b = { frame = Theme.Card(parent, COLOR.banner, { green[1], green[2], green[3], 0.2 }, true) }
  b.text = Theme.Num(b.frame, 10)
  b.text:SetJustifyH("LEFT")
  setColor(b.text, Theme.color.fgMuted)
  b.text:SetPoint("LEFT", b.frame, "LEFT", SD.BANNER_PAD_X, 0)
  b.button = Theme.Button(b.frame, "ghost", "plaque")
  b.button:SetPoint("RIGHT", b.frame, "RIGHT", -SD.BANNER_PAD_X / 2, 0)
  local gc = Theme.color.gold
  if b.button.ring then b.button.ring:SetVertexColor(gc[1], gc[2], gc[3], 0.5) end
  b.button.bg:SetVertexColor(1, 1, 1, 0)
  setColor(b.button.text, Theme.color.goldHi)
  b.button:SetScript("OnClick", function()
    if GC.Sniper and GC.Sniper.ShowView then GC.Sniper.ShowView("sell") end
  end)
  b.frame:Hide()
  return b
end

local function createControls(parent)
  local c = { chips = {} }
  c.group = Theme.Card(parent, COLOR.tile, Theme.color.border, true)
  for _, period in ipairs(V.PERIODS) do
    local chip = Theme.Button(c.group, "ghost", "badge")
    chip:SetScript("OnClick", function()
      state.period = period
      render()
    end)
    c.chips[period] = chip
  end
  c.well = Theme.Card(parent, COLOR.tile, { 1, 1, 1, 0.08 }, true)
  local search = CreateFrame("EditBox", nil, c.well)
  search:SetAutoFocus(false)
  search:SetPoint("TOPLEFT", SD.SEARCH_PAD, -2)
  search:SetPoint("BOTTOMRIGHT", -SD.SEARCH_PAD, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if search.SetFont then
    search:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    search:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    if Theme.OnRescale then Theme.OnRescale(function(scale) search:SetFont(Theme.FONT_UI, 11 * scale, "") end) end
  end
  c.search = search
  c.hint = Theme.Num(c.well, 10)
  c.hint:SetJustifyH("LEFT")
  c.hint:SetPoint("LEFT", c.well, "LEFT", SD.SEARCH_PAD, 0)
  setColor(c.hint, Theme.color.fgDim)
  local function hint()
    local text = search:GetText() or ""
    if text ~= "" or (search.HasFocus and search:HasFocus()) then c.hint:Hide() else c.hint:Show() end
  end
  search:SetScript("OnTextChanged", function(_, byUser)
    state.query = search:GetText() or ""
    hint()
    if byUser then render() end
  end)
  search:SetScript("OnEditFocusGained", hint)
  search:SetScript("OnEditFocusLost", hint)
  search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
    state.query = ""
    hint()
    render()
  end)
  return c
end

local function createHeader(parent)
  local h = { frame = CreateFrame("Frame", nil, parent), cells = {} }
  for _, key in ipairs({ "item", "when", "each", "got", "profit" }) do
    local label = Theme.Num(h.frame, 9)
    label:SetWordWrap(false)
    if label.SetMaxLines then label:SetMaxLines(1) end
    label:SetJustifyH(key == "item" and "LEFT" or "RIGHT")
    setColor(label, COLOR.faint)
    h.cells[key] = label
  end
  local bc = Theme.color.border
  h.rule = h.frame:CreateTexture(nil, "ARTWORK")
  h.rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  h.rule:SetPoint("BOTTOMLEFT")
  h.rule:SetPoint("BOTTOMRIGHT")
  h.rule:SetHeight(1)
  return h
end

local function createEmpty(parent)
  local e = { frame = Theme.Card(parent, COLOR.empty, { 1, 1, 1, 0.07 }, true) }
  e.message = Theme.Label(e.frame, 13)
  e.message:SetJustifyH("CENTER")
  e.sub = Theme.Num(e.frame, 10)
  e.sub:SetJustifyH("CENTER")
  setColor(e.sub, Theme.color.fgDim)
  e.button = Theme.Button(e.frame, "ghost", "plaque")
  local gc = Theme.color.gold
  if e.button.ring then e.button.ring:SetVertexColor(gc[1], gc[2], gc[3], 0.5) end
  e.button.bg:SetVertexColor(1, 1, 1, 0)
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
-- Only the container and its scroll are made here; the tiles, controls and headings wait for
-- the tab's first Show (build below), so a session that never opens Sold never makes them.
function Sold.Attach(f, geo)
  Theme, V = GC.Theme, GC.SoldView
  local container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()
  view.container, view.width = container, geo.rowWidth
  -- The window's shared status line sits at this container's top, beside the (hidden) AUTO
  -- button, and says things about Deals and Sell. Over this tab it would draw across the tiles.
  view.status = f.status

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
    if container:IsShown() and view.tiles then render() end
  end)
  if Theme.OnRescale then
    Theme.OnRescale(function() if container:IsShown() and view.tiles then render() end end)
  end
end

local function build()
  if view.tiles then return end
  local container = view.container
  view.tiles = { createTile(container), createTile(container), createTile(container) }
  view.banner = createBanner(container)
  view.controls = createControls(container)
  view.header = createHeader(container)
  view.empty = createEmpty(view.content)
end

function Sold.Show()
  if not view.container then return end
  view.container:Show()
  if view.status then view.status:Hide() end
  build()
  view.restamp = true -- see put(): every string is drawn again after the hide
  render()
  view.restamp = false
end

function Sold.Hide()
  if view.container then view.container:Hide() end
  -- Handed back to the other tabs, written again so it is drawn (see put()).
  if view.status then
    local text = view.status:GetText()
    view.status:SetText("")
    view.status:SetText(text or "")
    view.status:Show()
  end
end

-- Called from GC.Ledger.ScanInbox (a mailbox scan is when sales appear) and from Road to 40's
-- money and cost changes.
function Sold.RefreshIfShown()
  if view.container and view.container:IsShown() and view.tiles then render() end
end
