local _, GC = ...

-- The check panel's answer, drawn (UI/SniperFrame.lua's createDialog builds the panel and calls
-- Build; drawVerdict calls Paint on every stamp). What it shows is decided in Core/DealCard.lua and
-- Core/CheckVerdict.lua; this places it:
--
--   the hero: a small caps line with the answer and how long ago the live check gave it, one big
--     figure, and ONE sentence -- the reason a refusal is given once, never again below it;
--   CHEAPEST LISTINGS: the five cheapest price levels the check read, a bar per level against
--     its quantity, green under the buy limit, and a dashed gold line at the limit;
--   three stat tiles;
--   the footer, pinned to the bottom: WATCH FOR UNDER ..., CHECK and HIDE ITEM on a refusal; the
--     quantity stepper, BUY and HIDE THIS ITEM on a buy.
--
-- BUY and CHECK are the panel's own primary button, its click handler untouched (the protected
-- purchase rules live there); this file only moves and restyles it. WATCH pins the item (the
-- board's own watch), HIDE hides it from the board (GC.Sniper._ToggleHidden). Neither posts or buys.
GC.SniperInspector = {}
local SI = GC.SniperInspector

local LADDER_ROW_H, LADDER_TITLE_H, LADDER_LINE_H = 16, 16, 16
local PRICE_W, QTY_W = 72, 52
local TILE_H, TILE_GAP = 40, 6
local DASHES = 28
local PRIMARY_H, SMALL_H, STEP_H, STATUS_H = 32, 22, 20, 32
-- The footer's three rows, bottom up: HIDE (and Cancel), the panel's own button (BUY or CHECK),
-- then WATCH or the quantity stepper. The panel's own button keeps one rectangle in every state,
-- so a verdict that changes under the cursor never puts BUY where WATCH or CHECK was.
local TOP_ROW_H = PRIMARY_H
local KICKER_H, FIGURE_H = 12, 28
-- How often the panel repaints the check's age and re-reads the purchase stage for its footer.
local TICK_SECONDS = 0.2

local function colour(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

local function measured(fs, fallback)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return math.ceil(type(h) == "number" and h > 0 and h or fallback)
end

-- ---------------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------------

local function buildLadder(d)
  local T, K = GC.Theme, GC.Kit.Tokens.color
  local block = CreateFrame("Frame", nil, d)
  block:Hide()
  block.title = T.Heading(block, 10)
  block.title:SetPoint("TOPLEFT", T.pad.m, -T.pad.s)
  block.title:SetText(GC.L["CHEAPEST LISTINGS"])
  colour(block.title, K.text3)
  block.rows = {}
  for i = 1, GC.DealCard.LADDER_ROWS do
    local row = {}
    row.price = T.Num(block, 10)
    row.price:SetJustifyH("LEFT")
    row.price:SetWidth(PRICE_W)
    row.price:SetWordWrap(false)
    row.track = T.Solid(block, "BACKGROUND", GC.Kit.Tokens.ink(0.05))
    row.track:SetHeight(6)
    row.fill = T.Solid(block, "ARTWORK", K.text4)
    row.fill:SetHeight(6)
    row.qty = T.Num(block, 10)
    row.qty:SetJustifyH("RIGHT")
    row.qty:SetWidth(QTY_W)
    row.qty:SetWordWrap(false)
    block.rows[i] = row
  end
  -- The limit: a dashed gold line between the rows, and what it is.
  block.dashes = {}
  for i = 1, DASHES do block.dashes[i] = T.Solid(block, "OVERLAY", K.gold) end
  block.lineLabel = T.Label(block, 9)
  block.lineLabel:SetJustifyH("RIGHT")
  block.lineLabel:SetWordWrap(false)
  colour(block.lineLabel, K.gold)
  d.ladderBlock = block
end

local function buildTiles(d)
  local T, K = GC.Theme, GC.Kit.Tokens.color
  local block = CreateFrame("Frame", nil, d)
  block:Hide()
  block.tiles = {}
  for i = 1, 3 do
    local tile = T.Card(block, GC.Kit.Tokens.ink(0.04), GC.Kit.Tokens.ink(0.08), true)
    tile.label = T.Heading(tile, 8)
    tile.label:SetPoint("TOPLEFT", T.pad.s, -T.pad.xs - 2)
    tile.label:SetPoint("RIGHT", -T.pad.s, 0)
    tile.label:SetWordWrap(false)
    colour(tile.label, K.text3)
    tile.value = T.Num(tile, 13, true)
    tile.value:SetJustifyH("LEFT")
    tile.value:SetPoint("BOTTOMLEFT", T.pad.s, T.pad.xs + 2)
    tile.value:SetPoint("RIGHT", -T.pad.s, 0)
    tile.value:SetWordWrap(false)
    block.tiles[i] = tile
  end
  d.tilesBlock = block
end

-- `act`: { watch(), hide(), step(delta), all() } -- the panel's owner wires them to the board.
function SI.Build(d, act)
  local T, K = GC.Theme, GC.Kit.Tokens.color
  d.inspect = {}
  d.kindText = T.Num(d, 9)
  d.kindText:SetJustifyH("LEFT")
  d.kindText:SetWordWrap(false)
  colour(d.kindText, K.text3)
  buildLadder(d)
  buildTiles(d)

  d.watchBtn = T.Button(d, "primary", "plaque")
  d.watchBtn:SetHeight(PRIMARY_H)
  d.watchBtn:SetScript("OnClick", function() act.watch() end)
  d.hideBtn = T.Button(d, "ghost", "badge")
  d.hideBtn:SetHeight(SMALL_H)
  d.hideBtn:SetScript("OnClick", function() act.hide() end)
  d.qtyMinus = T.Button(d, "ghost", "badge")
  d.qtyMinus:SetSize(STEP_H + 2, STEP_H)
  d.qtyMinus:SetLabel("-")
  d.qtyMinus:SetScript("OnClick", function() act.step(-1) end)
  d.qtyPlus = T.Button(d, "ghost", "badge")
  d.qtyPlus:SetSize(STEP_H + 2, STEP_H)
  d.qtyPlus:SetLabel("+")
  d.qtyPlus:SetScript("OnClick", function() act.step(1) end)
  d.qtyAll = T.Button(d, "ghost", "badge")
  d.qtyAll:SetHeight(STEP_H)
  d.qtyAll:SetScript("OnClick", function() act.all() end)
  -- The quantity box moves into the footer's stepper, between - and +.
  if d.qtyBox then d.qtyBox:SetParent(d) end
  -- The footer's height, which the status line and the requote banner sit on:
  -- margin + hide/cancel + gap + BUY or CHECK + gap + WATCH or stepper + gap = 114.
  d.footerH = T.pad.m + SMALL_H + T.pad.xs + PRIMARY_H + T.pad.xs + TOP_ROW_H + T.pad.s
  -- The requote banner's slot stays over the status line, as the panel reserves it.
  if d.banner then
    d.banner:ClearAllPoints()
    d.banner:SetPoint("BOTTOMLEFT", T.pad.m, d.footerH + STATUS_H + T.pad.xs)
    d.banner:SetPoint("BOTTOMRIGHT", -T.pad.m, d.footerH + STATUS_H + T.pad.xs)
  end

  -- Its own frame: the panel's slide-in drives the panel's OnUpdate.
  local tick, wait = CreateFrame("Frame", nil, d), 0
  tick:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = TICK_SECONDS
    SI.Refresh(d)
  end)
  d.inspectTick = tick
end

-- ---------------------------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------------------------

-- The hero's three lines, top down, and the height they take.
local function paintHero(d, ctx, refusedHero)
  local T, K = GC.Theme, GC.Kit.Tokens.color
  local width = (d:GetWidth() or 320) - 2 - 2 * T.pad.m
  local y = -T.pad.s
  local figure = refusedHero and refusedHero.big or ctx.figure
  if d.heroText then d.heroText:Hide() end
  if d.verdictAmountNote then d.verdictAmountNote:Hide() end
  y = y - KICKER_H - T.pad.xs
  if figure then
    d.verdictAmount:SetText(figure)
    local c = refusedHero and K.loss or ctx.figureColor or K.text1
    colour(d.verdictAmount, c)
    d.verdictAmount:Show()
    y = y - FIGURE_H - T.pad.xs
  else
    d.verdictAmount:Hide()
  end
  -- ONE sentence: on a refusal the reason (or what would make it a deal); on a buy what the
  -- figure is, the vendor's exact price or the market's estimate.
  local sentence = refusedHero and refusedHero.sentence
    or (ctx.state ~= "refuse" and ctx.caption ~= nil and ctx.caption ~= "" and ctx.caption) or ctx.sentence or ""
  local head = d.verdictHead
  head:ClearAllPoints()
  head:SetPoint("TOPLEFT", T.pad.m, y)
  head:SetWidth(width)
  head:SetText(sentence)
  colour(head, K.text2)
  local h = sentence ~= "" and measured(head, 14) or 0
  head:SetHeight(math.max(1, h))
  -- The owner's screenshot (2026-11-21) caught the sentence cut to one line with an ellipsis: grow
  -- the box a line at a time while the client still says it is cut, up to four lines.
  if sentence ~= "" and head.IsTruncated then
    local line = measured(head, 14)
    for _ = 1, 3 do
      if not head:IsTruncated() then break end
      h = h + math.max(14, math.floor(line))
      head:SetHeight(h)
    end
  end
  return -y + h + T.pad.s
end

local function paintLadder(d, ladder)
  local T, K = GC.Theme, GC.Kit.Tokens.color
  local block = d.ladderBlock
  if not ladder then return nil end
  local width = (d:GetWidth() or 320) - 2
  local barX = T.pad.m + PRICE_W + T.pad.s
  local barW = width - barX - T.pad.s - QTY_W - T.pad.m
  local y = -(T.pad.s + LADDER_TITLE_H)
  local function line(at)
    local gap = math.floor((width - 2 * T.pad.m) / DASHES)
    for i, dash in ipairs(block.dashes) do
      dash:ClearAllPoints()
      dash:SetSize(math.max(1, gap - 3), 1)
      dash:SetPoint("TOPLEFT", block, "TOPLEFT", T.pad.m + (i - 1) * gap, at - 3)
      dash:Show()
    end
    block.lineLabel:ClearAllPoints()
    block.lineLabel:SetPoint("TOPRIGHT", block, "TOPRIGHT", -T.pad.m, at - 5)
    block.lineLabel:SetText(ladder.label)
    block.lineLabel:Show()
  end
  local drawn = false
  for i, row in ipairs(block.rows) do
    local level = ladder.rows[i]
    if ladder.limitAt == 0 and i == 1 and level then
      line(y)
      drawn = true
      y = y - LADDER_LINE_H
    end
    if level then
      row.price:ClearAllPoints()
      row.price:SetPoint("TOPLEFT", block, "TOPLEFT", T.pad.m, y - 2)
      row.price:SetText(GC.Util.FormatMoney(level.price))
      -- Bought: green. Under the limit but past what the buy takes: green, dimmed.
      local bought = level.under and level.taken ~= false
      colour(row.price, bought and K.profit or K.text2)
      row.track:ClearAllPoints()
      row.track:SetPoint("TOPLEFT", block, "TOPLEFT", barX, y - 5)
      row.track:SetWidth(barW)
      row.fill:ClearAllPoints()
      row.fill:SetPoint("TOPLEFT", block, "TOPLEFT", barX, y - 5)
      row.fill:SetWidth(math.max(1, math.floor(barW * level.share + 0.5)))
      local c = level.under and K.profit or K.text4
      row.fill:SetColorTexture(c[1], c[2], c[3], (level.under and not bought) and 0.3 or 0.85)
      row.qty:ClearAllPoints()
      row.qty:SetPoint("TOPRIGHT", block, "TOPRIGHT", -T.pad.m, y - 2)
      row.qty:SetText("×" .. GC.DealCard.Count(level.qty))
      colour(row.qty, K.text3)
      for _, part in ipairs({ row.price, row.track, row.fill, row.qty }) do part:Show() end
      y = y - LADDER_ROW_H
      if ladder.limitAt == i and ladder.limitAt > 0 then
        line(y)
        drawn = true
        y = y - LADDER_LINE_H
      end
    else
      for _, part in ipairs({ row.price, row.track, row.fill, row.qty }) do part:Hide() end
    end
  end
  if not drawn then
    for _, dash in ipairs(block.dashes) do dash:Hide() end
    block.lineLabel:Hide()
  end
  return -y + T.pad.xs
end

local function paintTiles(d, tiles)
  local T = GC.Theme
  if #tiles == 0 then return nil end
  local width = (d:GetWidth() or 320) - 2 - 2 * T.pad.m
  local each = math.floor((width - (#tiles - 1) * TILE_GAP) / #tiles)
  for i, tile in ipairs(d.tilesBlock.tiles) do
    local stat = tiles[i]
    if stat then
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", d.tilesBlock, "TOPLEFT", T.pad.m + (i - 1) * (each + TILE_GAP), -T.pad.s)
      tile:SetSize(each, TILE_H)
      tile.label:SetText(stat.label)
      tile.value:SetText(stat.value)
      tile:Show()
    else
      tile:Hide()
    end
  end
  return T.pad.s + TILE_H + T.pad.xs
end

-- The panel's figures as Core/DealCard.lua's Tiles reads them.
local function facts(ctx)
  local decision, deal, market = ctx.decision or {}, ctx.deal or {}, ctx.market or {}
  local listed = deal.avail
  if not listed and ctx.levels then
    listed = 0
    for _, level in ipairs(ctx.levels) do listed = listed + (level.quantity or 0) end
  end
  return {
    marketValue = market.marketValue or deal.refUnit, listed = listed,
    soldPerDay = market.soldPerDay or deal.soldPerDay,
    entryTotal = decision.entryTotal, quantity = decision.quantity,
    -- Forever's AH value or vendor price; retail's exit is a stress price, not a market value.
    refUnit = decision.refUnit or (deal.forever and decision.exitUnit) or deal.refUnit,
    profit = decision.stressProfit, forever = deal.forever, targets = ctx.targets,
  }
end

--- Draws the verdict `ctx` holds: { cv (CheckVerdict.Build's answer), decision, deal, market,
-- levels (the book the check read), checkedAt() (GetTime of the board's verdict for the row, nil
-- before any check), figure, figureColor, caption, sentence (what drawVerdict worked out),
-- isPinned(), isHidden(), maxQty() }.
function SI.Paint(d, ctx)
  local DC = GC.DealCard
  local cv, decision, deal = ctx.cv or {}, ctx.decision or {}, ctx.deal or {}
  ctx.state = DC.State(cv.tone)
  local limit = decision.ceiling or decision.capUnit or deal.ceiling
  local cheapest = ctx.levels and ctx.levels[1] and ctx.levels[1].unitPrice or decision.entryUnitDisplay or deal.unitPrice
  local refusedHero = ctx.state == "refuse"
    and DC.RefusedHero(cheapest, limit, decision.refUnit or deal.refUnit, deal.forever) or nil
  -- A market buy: the target (sold at the AH value) is the figure, the stress exit the sentence.
  ctx.targets = ctx.state == "buy"
    and DC.Targets(deal, { quantity = decision.quantity, levels = ctx.levels }) or nil
  if ctx.targets and ctx.targets.upside > 0 then
    ctx.figure = "~+" .. GC.Util.FormatMoney(ctx.targets.upside)
    ctx.caption = DC.TargetSentence(ctx.targets)
  end
  d.inspect = {
    ctx = ctx, limit = limit,
    heroH = paintHero(d, ctx, refusedHero),
    ladderH = paintLadder(d, DC.Ladder(ctx.levels, limit, nil, ctx.state == "buy" and decision.quantity or nil)),
    tilesH = paintTiles(d, DC.Tiles(ctx.state, facts(ctx))),
  }
  -- The reason is said in the hero; the status line under it does not say it again.
  local quiet = {}
  for _, reason in ipairs(decision.reasons or {}) do quiet[GC.SniperDecision.ReasonText(reason)] = true end
  quiet[GC.L["live verification required"]] = true
  if type(decision.needsGold) == "number" then
    quiet[(GC.L["not enough gold on this character: you need %s"]):format(GC.Util.FormatGoldCeil(decision.needsGold))] = true
  end
  d.quietReasons = ctx.state ~= "buy" and quiet or nil
  if d.status and d.quietReasons and d.quietReasons[d.status:GetText() or ""] then d.status:SetText("") end
  SI.Refresh(d)
end

-- The header's caps line under the name: what kind of listing, and how many are up.
local function kindLine(deal, levels)
  local listed = deal.avail
  if not listed and levels then
    listed = 0
    for _, level in ipairs(levels) do listed = listed + (level.quantity or 0) end
  end
  local commodity = deal.isCommodity ~= false
  if type(listed) == "number" and listed > 0 then
    return (commodity and GC.L["COMMODITY · %s LISTED"] or GC.L["ITEM · %s LISTED"]):format(GC.DealCard.Count(listed))
  end
  return commodity and GC.L["COMMODITY"] or GC.L["ITEM"]
end

-- Lays the footer out for the verdict and the purchase stage: bottom-up from the panel's foot.
local function layoutFooter(d, flags)
  local T = GC.Theme
  local width = (d:GetWidth() or 320) - 2 * T.pad.m
  local half = math.floor((width - T.pad.xs) / 2)
  local y = T.pad.m
  local function put(btn, x, w, h)
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", T.pad.m + x, y)
    btn:SetSize(w, h)
    btn:Show()
  end
  -- The bottom row: HIDE, with Cancel beside it while a purchase is open on the server.
  if flags.cancel then
    put(d.cancelBtn, 0, half, SMALL_H)
    put(d.hideBtn, half + T.pad.xs, width - half - T.pad.xs, SMALL_H)
  else
    d.cancelBtn:Hide()
    put(d.hideBtn, 0, width, SMALL_H)
  end
  y = y + SMALL_H + T.pad.xs
  -- The panel's own button, always here: BUY (or Confirm) on a buy, CHECK as a secondary on a
  -- refusal. Switched only when it changes: the purchase flow colours its label (a red Confirm),
  -- and a variant change repaints it.
  local refusal = flags.watch and not flags.buy
  local variant = refusal and "ghost" or "primary"
  if d.inspectVariant ~= variant then
    d.inspectVariant = variant
    d.primaryBtn:SetVariant(variant)
  end
  put(d.primaryBtn, 0, width, PRIMARY_H)
  y = y + PRIMARY_H + T.pad.xs
  -- The top row: WATCH on a refusal, the quantity stepper on a buy.
  local steppers = { d.qtyMinus, d.qtyBox, d.qtyPlus, d.qtyAll }
  if refusal then
    put(d.watchBtn, 0, width, TOP_ROW_H)
  else
    d.watchBtn:Hide()
  end
  if flags.qty and d.qtyBox and not refusal then
    local x = 0
    for _, w in ipairs(steppers) do
      local wide = w == d.qtyBox and 64 or w == d.qtyAll and 70 or STEP_H + 2
      put(w, x, wide, w == d.qtyBox and 18 or STEP_H)
      x = x + wide + T.pad.xs
    end
  else
    for _, w in ipairs(steppers) do if w then w:Hide() end end
  end
end

--- Repaints what moves while the panel is up: the check's age and the footer, which follows the
-- purchase stage (Cancel stays while a purchase is open on the server).
function SI.Refresh(d, force)
  local inspect = d.inspect
  local ctx = inspect and inspect.ctx
  if not ctx then return end
  local DC = GC.DealCard
  -- Read live: the board records the check's verdict after the panel is stamped with it.
  local at = ctx.checkedAt and ctx.checkedAt() or nil
  local age = at and GetTime and math.max(0, GetTime() - at) or nil
  local cv = ctx.cv or {}
  local label = inspect.pending and GC.L["Checking..."] or DC.HeroLabel(cv.tone, age, cv.group)
  if d.verdictLabel:GetText() ~= label then d.verdictLabel:SetText(label) end
  d.kindText:SetText(kindLine(ctx.deal or {}, ctx.levels))

  local row = d.row
  local deal = ctx.deal or {}
  local single = deal.isCommodity == false
  local flags = DC.Footer(ctx.state, row and row.purchaseStage, deal.isCommodity and not single)
  local limit = inspect.limit
  local pinned = ctx.isPinned and ctx.isPinned() or false
  d.watchBtn:SetLabel(pinned and GC.L["STOP WATCHING"]
    or limit and (GC.L["WATCH FOR UNDER %s"]):format(GC.Util.FormatMoney(limit)) or GC.L["WATCH THIS ITEM"])
  local hidden = ctx.isHidden and ctx.isHidden() or false
  d.hideBtn:SetLabel(hidden and GC.L["SHOW THIS ITEM AGAIN"]
    or ctx.state == "buy" and GC.L["HIDE THIS ITEM"] or GC.L["HIDE ITEM"])
  local most = ctx.maxQty and ctx.maxQty() or nil
  d.qtyAll:SetLabel(most and (GC.L["ALL %s"]):format(GC.DealCard.Count(most)) or GC.L["ALL"])
  local sig = table.concat({ tostring(flags.watch), tostring(flags.check), tostring(flags.cancel),
    tostring(flags.buy), tostring(flags.qty), tostring(d:GetWidth()) }, "|")
  if force or sig ~= inspect.footerSig then
    inspect.footerSig = sig
    layoutFooter(d, flags)
  end
end

--- The panel was stamped with what the board knew, and the live check is on its way: the label
-- says so, and the figure waits for the answer (never a "-" in its place).
function SI.Pending(d)
  if not (d.inspect and d.inspect.ctx) then return end
  d.inspect.pending = true
  d.verdictAmount:Hide()
  SI.Refresh(d)
end

-- For the specs: the footer flags the panel last laid out.
function SI._Flags(d)
  local ctx = d.inspect and d.inspect.ctx
  if not ctx then return nil end
  local deal = ctx.deal or {}
  return GC.DealCard.Footer(ctx.state, d.row and d.row.purchaseStage, deal.isCommodity and deal.isCommodity ~= false)
end
