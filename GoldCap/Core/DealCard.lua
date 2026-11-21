local _, GC = ...

-- What the DEALS row's tooltip card and the check panel SHOW, decided away from the frames that
-- draw them (UI/DealCard.lua, UI/SniperInspector.lua). Nothing here touches a frame: every answer
-- is plain data and finished text, so the specs can walk every row kind and every verdict.
--
-- Text is looked up through GC.L when a function runs, never while this file loads (a lookup at
-- load time freezes to English: spec/locale_load_time_spec.lua). Money is formatted with
-- GC.Util.FormatMoney, the figure the board's own cells print.
GC.DealCard = {}
local DC = GC.DealCard

local function L(key) return GC.L and GC.L[key] or key end
local function money(copper) return GC.Util.FormatMoney(copper) end

local function positive(v)
  return type(v) == "number" and v == v and v > 0 and v ~= math.huge
end

-- A count as a whole number grouped in thousands ("2,731"), in the client's own grouping where it
-- has one (BreakUpLargeNumbers writes a German client's 2.731), as GoldCap's tooltip block does.
function DC.Count(n)
  n = math.floor(n + 0.5)
  if BreakUpLargeNumbers then return tostring(BreakUpLargeNumbers(n)) end
  local text, found = tostring(n), 1
  while found > 0 do text, found = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
  return text
end

-- How long ago a check was, in the player's language ("4s", "19m"); nil without a time.
function DC.Age(seconds)
  if type(seconds) ~= "number" then return nil end
  return GC.Util.FormatElapsedWords(math.max(0, seconds))
end

-- A verdict the live check turned down: not a buy, not a deal only the wallet stopped, not a realm
-- lot it found, not the player's own price. The board hides exactly these (renderList).
function DC.Refused(verdict)
  return verdict ~= nil and not verdict.buyable and not verdict.needsGold
    and not verdict.unverified and not verdict.cap
end

-- ---------------------------------------------------------------------------------------------
-- The tooltip card
-- ---------------------------------------------------------------------------------------------

--- The verdict pill in the card's header: { tone, text }. Tones: "safe" (green), "warn" (amber),
-- "refuse" (red), "muted" (grey). `age`: seconds since the check, for a buyable verdict.
function DC.Pill(deal, verdict, age)
  deal = deal or {}
  if deal.kind == "rare" then return { tone = "warn", text = GC.L["RARE FIND"] } end
  if deal.cap or (verdict and verdict.cap) then
    return { tone = "safe", text = (deal.capFollowed or (verdict and verdict.followed)) and GC.L["GROUP"] or GC.L["YOUR PRICE"] }
  end
  if not verdict then
    if deal.pinPlaceholder then return { tone = "muted", text = GC.L["WATCHING"] } end
    return { tone = "warn", text = GC.L["NOT CHECKED YET"] }
  end
  if verdict.buyable then
    local ago = DC.Age(age)
    return { tone = "safe", text = ago and (GC.L["SAFE · LIVE %s AGO"]):format(ago) or GC.L["SAFE"] }
  end
  if positive(verdict.needsGold) then
    return { tone = "warn", text = (GC.L["NEEDS %s ON THIS CHARACTER"]):format(GC.Util.FormatGoldCeil(verdict.needsGold)) }
  end
  if verdict.unverified then return { tone = "warn", text = GC.L["YOUR CALL"] } end
  return { tone = "refuse", text = GC.L["WON'T BUY"] }
end

--- The card's one big number, or nil: { label, text, tone } with tone "profit" or "loss".
-- A refused row with a buy limit says how far over it the cheapest listing is; a deal says what
-- it makes, "+" when the figure is exact (a vendor pays a fixed price) and "~+" when it is an
-- estimate. `profit` is the figure the row's own profit cell shows (GC.BoardRows.Figures).
function DC.Big(deal, verdict, profit)
  deal = deal or {}
  if deal.kind == "rare" then return nil end
  if DC.Refused(verdict) then
    local cheapest = verdict.unitPrice or deal.unitPrice
    if positive(deal.ceiling) and positive(cheapest) and cheapest > deal.ceiling then
      return { label = GC.L["Over your limit by"], text = money(cheapest - deal.ceiling), tone = "loss" }
    end
    return nil
  end
  if not positive(profit) then return nil end
  local exact = deal.forever == "vendor"
  return { label = exact and GC.L["You make"] or GC.L["You make about"],
    text = (exact and "+" or "~+") .. money(profit), tone = "profit" }
end

-- The share of the scale past the largest figure: a marker at the very end reads as clipped.
local SCALE_HEADROOM = 1.1

--- Where the cheapest listing, the buy limit and the reference sit on the card's price scale, as
-- shares of its width (0..1), and the three labels under it; nil when any figure is missing.
-- `refKind`: "vendor" for a vendor's price, anything else for the AH value.
function DC.Scale(cheapest, limit, ref, refKind)
  if not (positive(cheapest) and positive(limit) and positive(ref)) then return nil end
  local top = math.max(cheapest, limit, ref) * SCALE_HEADROOM
  return {
    cheap = cheapest / top, limit = limit / top, ref = ref / top,
    under = cheapest <= limit,
    labels = {
      (GC.L["cheapest %s"]):format(money(cheapest)),
      (GC.L["limit %s"]):format(money(limit)),
      (refKind == "vendor" and GC.L["vendor %s"] or GC.L["AH %s"]):format(money(ref)),
    },
  }
end

--- The card's small chips, each { text, tone }: how many are listed, and for a market deal that
-- nothing has measured how fast it resells.
function DC.Chips(deal)
  local out = {}
  if not deal then return out end
  if positive(deal.avail) then out[#out + 1] = { text = (GC.L["%s listed"]):format(DC.Count(deal.avail)), tone = "muted" } end
  if deal.forever == "market" and deal.refSource ~= "sold" and deal.refSource ~= "group" then
    out[#out + 1] = { text = GC.L["resale speed unknown"], tone = "warn" }
  end
  return out
end

--- The key hints in the card's footer, each { key, text }.
function DC.Hints(deal, pinned, dressable)
  local out = {}
  if deal and deal.kind ~= "rare" then
    out[#out + 1] = { key = GC.L["RMB"], text = pinned and GC.L["stop watching"] or GC.L["watch it"] }
    out[#out + 1] = { key = GC.L["CLICK"], text = GC.L["open details"] }
  end
  if dressable then out[#out + 1] = { key = GC.L["CTRL"], text = GC.L["try it on"] } end
  return out
end

--- GoldCap's own item lines (GC.Tooltip.BuildLines) as the card's small facts, each { left, right
-- or copper, tone }: what the scale above already shows (the cheapest lot, the AH value, the live
-- floor) is left out while it is drawn, and so is the Companion nudge, which is about the prices
-- as a whole and not about this deal. A verdict line ("Sell it on the AH") keeps its tone.
function DC.Facts(lines, scaled)
  local out = {}
  if type(lines) ~= "table" then return out end
  local shown = { [GC.L["Cheapest"]] = true, [GC.L["AH value"]] = true, [GC.L["AH, cheapest version"]] = true }
  for _, ln in ipairs(lines) do
    if ln.kind == "money" then
      if not (scaled and shown[ln.label]) then out[#out + 1] = { left = ln.label, copper = ln.copper } end
    elseif ln.kind == "live" then
      if not scaled then out[#out + 1] = { left = ln.left, copper = ln.copper, right = ln.detail } end
    elseif ln.kind == "verdict" then
      out[#out + 1] = { left = ln.text, tone = ln.tone }
    elseif ln.kind ~= "hint" and ln.left then
      out[#out + 1] = { left = ln.left, right = ln.right }
    end
  end
  return out
end

--- Whether the card hangs under the tooltip or over it: "below" while the screen has room under
-- the tooltip's bottom edge, else "above" when it has room over its top, else "below" (the client
-- clamps it on screen). All in one coordinate space.
function DC.Side(tipBottom, tipTop, cardHeight, screenTop)
  if type(tipBottom) ~= "number" or type(cardHeight) ~= "number" then return "below" end
  if tipBottom - cardHeight >= 0 then return "below" end
  if type(tipTop) == "number" and type(screenTop) == "number" and tipTop + cardHeight <= screenTop then
    return "above"
  end
  return "below"
end

-- ---------------------------------------------------------------------------------------------
-- The check panel
-- ---------------------------------------------------------------------------------------------

DC.LADDER_ROWS = 5

--- The CHEAPEST LISTINGS ladder from the book the check read: up to `n` cheapest price levels,
-- each { price, qty, share (of the largest shown quantity), under (at or under the limit) },
-- and `limitAt`, how many rows sit at or under the limit (the gold line goes after that row;
-- nil without a limit). nil when there is no book. Levels at one price are merged.
function DC.Ladder(levels, limit, n)
  if type(levels) ~= "table" or #levels == 0 then return nil end
  n = n or DC.LADDER_ROWS
  local byPrice, prices = {}, {}
  for _, level in ipairs(levels) do
    local price, qty = level.unitPrice, level.quantity
    if positive(price) and positive(qty) then
      if not byPrice[price] then prices[#prices + 1] = price end
      byPrice[price] = (byPrice[price] or 0) + qty
    end
  end
  if #prices == 0 then return nil end
  table.sort(prices)
  local rows, most = {}, 0
  for i = 1, math.min(n, #prices) do
    local qty = byPrice[prices[i]]
    rows[i] = { price = prices[i], qty = qty }
    if qty > most then most = qty end
  end
  local hasLimit = positive(limit)
  local limitAt = hasLimit and 0 or nil
  for _, row in ipairs(rows) do
    row.share = row.qty / most
    row.under = hasLimit and row.price <= limit or false
    if row.under then limitAt = limitAt + 1 end
  end
  return { rows = rows, limitAt = limitAt, limit = hasLimit and limit or nil,
    label = hasLimit and (limitAt == 0 and (GC.L["your limit %s · nothing under it"]):format(money(limit))
      or (GC.L["your limit %s"]):format(money(limit))) or nil }
end

--- The panel's state for a verdict (Core/CheckVerdict.lua's Build): "refuse" for a refusal,
-- "warn" for a deal only the wallet stopped, "buy" for every answer the panel can act on.
function DC.State(tone)
  if tone == "refuse" then return "refuse" end
  if tone == "gold" then return "warn" end
  return "buy"
end

-- The caps word of each CheckVerdict tone, for the label over the hero.
-- @localised-keys
DC.TONE_CAPS = {
  refuse = "WON'T BUY", clear = "SAFE", vendor = "SAFE", market = "SAFE", adjust = "BUY LESS",
  unverified = "YOUR CALL", cap = "YOUR PRICE", gold = "NEEDS GOLD",
}

--- The small caps line over the hero: the answer and how long ago the live check gave it.
function DC.HeroLabel(tone, age, group)
  local word = tone == "cap" and group and GC.L["GROUP"] or L(DC.TONE_CAPS[tone] or "WON'T BUY")
  local ago = DC.Age(age)
  if not ago then return word end
  if tone == "refuse" or tone == "gold" then return (GC.L["%s · CHECKED %s AGO"]):format(word, ago) end
  return (GC.L["%s · CHECKED LIVE %s AGO"]):format(word, ago)
end

--- A refusal measured against a buy limit, in the panel's words: { big, sentence }, or nil when
-- the cheapest is not over the limit or a figure is missing. `refKind` "vendor" or "market".
function DC.RefusedHero(cheapest, limit, ref, refKind)
  if not (positive(cheapest) and positive(limit)) or cheapest <= limit then return nil end
  local big = (GC.L["%s too pricey"]):format(money(cheapest - limit))
  local sentence
  if positive(ref) and refKind == "vendor" then
    sentence = (GC.L["The cheapest costs %s. It's a deal only under %s; a vendor pays %s."]):format(
      money(cheapest), money(limit), money(ref))
  elseif positive(ref) then
    sentence = (GC.L["The cheapest costs %s. It's a deal only under %s, %d%% of the AH value of %s."]):format(
      money(cheapest), money(limit), math.floor(limit / ref * 100 + 0.5), money(ref))
  else
    sentence = (GC.L["The cheapest costs %s. It's a deal only under %s."]):format(money(cheapest), money(limit))
  end
  return { big = big, sentence = sentence }
end

--- The three stat tiles, each { label, value }. A refusal: the market, how many are listed, and
-- how many sell a day ("unknown" when nothing measured it). A buy: what you pay, what the vendor
-- pays or the AH value, and the return. A tile with no figure is left out, never shown as "-".
-- `facts`: { marketValue, listed, soldPerDay, entryTotal, quantity, refUnit, profit, forever }.
function DC.Tiles(state, facts)
  facts = facts or {}
  local out = {}
  local function add(label, value) if value then out[#out + 1] = { label = label, value = value } end end
  if state == "refuse" or state == "warn" then
    add(GC.L["MARKET"], positive(facts.marketValue) and money(facts.marketValue) or nil)
    add(GC.L["LISTED"], positive(facts.listed) and DC.Count(facts.listed) or nil)
    add(GC.L["SELLS PER DAY"], positive(facts.soldPerDay) and GC.Util.PerDay(facts.soldPerDay) or GC.L["unknown"])
    return out
  end
  add(GC.L["YOU PAY"], positive(facts.entryTotal) and money(facts.entryTotal) or nil)
  local qty = positive(facts.quantity) and facts.quantity or 1
  if facts.forever == "vendor" then
    add(GC.L["VENDOR PAYS"], positive(facts.refUnit) and money(facts.refUnit * qty) or nil)
  else
    local ref = positive(facts.refUnit) and facts.refUnit or facts.marketValue
    add(GC.L["AH VALUE"], positive(ref) and money(ref) or nil)
  end
  if positive(facts.entryTotal) and type(facts.profit) == "number" then
    add(GC.L["RETURN"], ("%+d%%"):format(math.floor(facts.profit / facts.entryTotal * 100 + 0.5)))
  end
  return out
end

-- The purchase stages in which a commodity purchase is open on the server: its Cancel must stay.
local OPEN_STAGES = { buying = true, confirm = true, requote = true }

--- Which footer controls show: { watch, check, hide, qty, buy, cancel }. A refusal offers to
-- watch the item for a price under its limit, to check again and to hide it; a buy the quantity,
-- BUY and hiding it. Cancel stays whenever a purchase is open on the server, whatever the verdict
-- says now. `qty`: whether the buy has a quantity to choose (a commodity, not a single lot).
function DC.Footer(state, stage, qty)
  local open = OPEN_STAGES[stage] == true
  if state == "buy" then
    return { buy = true, qty = qty and true or false, hide = true, cancel = open }
  end
  return { watch = true, check = not open, hide = true, cancel = open, buy = open }
end
