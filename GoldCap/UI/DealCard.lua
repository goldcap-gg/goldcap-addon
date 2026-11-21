local _, GC = ...

-- The GoldCap card under a DEALS row's tooltip. The game's tooltip keeps the item's own lines and
-- nothing else; what GoldCap says about the deal is drawn here, on a frame of its own, docked flush
-- under the tooltip (over it when the screen has no room below), as wide as the tooltip and never
-- narrower than MIN_W. What it shows is decided in Core/DealCard.lua; the row builds the model
-- (GC.Sniper._CardModel) and this only draws it.
--
-- The card is a child of GameTooltip, so it hides with it, takes its scale and strata, and can
-- never be left on screen behind it. It also hides the moment the tooltip is cleared for anything
-- else (OnTooltipCleared) or changes owner, so it only ever stands under the row that drew it.
GC.DealCardUI = {}
local UI = GC.DealCardUI

local MIN_W = 300
local PAD, GAP = 10, 6
local HEAD_H, BIG_H, BAR_H, CHIP_H, FACT_H, HINT_H = 18, 24, 4, 18, 14, 16
-- How often the card re-reads the tooltip's width and the check's age while it is up.
local REFRESH_SECONDS = 0.5

-- Tooltip-ground colours (Tokens.blizzard: the tooltip stays dark in every skin), per tone.
local TONE = { safe = "profit", profit = "profit", good = "profit", warn = "warn", refuse = "loss",
  loss = "loss", muted = "text3", dim = "text3" }
local function colour(tone)
  local B = GC.Kit.Tokens.blizzard
  return B[TONE[tone] or "text2"] or B.text2
end

local card

local function paint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- How wide a FontString's text draws, `fallback` before the client has measured it.
local function textWidth(fs, fallback)
  local w = fs.GetStringWidth and fs:GetStringWidth()
  return math.ceil(type(w) == "number" and w > 0 and w or fallback)
end

-- The i-th widget of a pool, built on first use.
local function slot(list, i, make)
  if not list[i] then list[i] = make() end
  return list[i]
end

local function hideFrom(list, first)
  for i = first, #list do
    local w = list[i]
    if w.left then w.left:Hide() w.right:Hide() else w:Hide() end
  end
end

local function build()
  local T, B = GC.Theme, GC.Kit.Tokens.blizzard
  local f = CreateFrame("Frame", nil, GameTooltip)
  f:Hide()
  f.bg = T.Solid(f, "BACKGROUND", B.popup)
  f.bg:SetAllPoints()
  T.EdgeBorder(f, B.popupBorder)
  -- The 2px top edge: gold for a deal, grey for a refusal.
  f.edge = T.Solid(f, "ARTWORK", B.gold)
  f.edge:SetPoint("TOPLEFT")
  f.edge:SetPoint("TOPRIGHT")
  f.edge:SetHeight(2)

  T.Parts.newBrand(f, 14, 11, 5)
  f.logo:SetPoint("TOPLEFT", PAD, -PAD - 2)
  f.brand:SetText("GOLDCAP")
  f.pill = T.Chip(f)
  f.pill:SetPoint("TOPRIGHT", -PAD, -PAD)

  f.bigLabel = T.Label(f, 11)
  paint(f.bigLabel, B.text2)
  f.bigValue = T.Num(f, 20, true)
  f.bigValue:SetJustifyH("RIGHT")

  -- The price scale: a thin track, green up to the buy limit, a mark for the cheapest listing and
  -- ticks for the limit and the reference.
  local bar = CreateFrame("Frame", nil, f)
  bar:SetHeight(BAR_H)
  bar.track = T.Solid(bar, "BACKGROUND", { B.ink[1], B.ink[2], B.ink[3], 0.1 })
  bar.track:SetAllPoints()
  bar.fill = T.Solid(bar, "ARTWORK", { B.profit[1], B.profit[2], B.profit[3], 0.55 })
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  bar.cheap = T.Solid(bar, "OVERLAY", B.text1)
  bar.cheap:SetSize(3, BAR_H + 6)
  bar.limit = T.Solid(bar, "OVERLAY", B.gold)
  bar.limit:SetSize(1, BAR_H + 6)
  bar.ref = T.Solid(bar, "OVERLAY", B.text3)
  bar.ref:SetSize(1, BAR_H + 6)
  bar.labels = {}
  for i, justify in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
    bar.labels[i] = T.Label(f, 9)
    bar.labels[i]:SetJustifyH(justify)
    bar.labels[i]:SetWordWrap(false)
  end
  paint(bar.labels[1], B.text1)
  paint(bar.labels[2], B.gold)
  paint(bar.labels[3], B.text3)
  f.bar = bar

  f.chips, f.notes, f.facts, f.hints = {}, {}, {}, {}
  f.foot = T.Solid(f, "ARTWORK", B.hairline)
  f.foot:SetHeight(1)

  local wait = 0
  f:SetScript("OnUpdate", function(self, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = REFRESH_SECONDS
    if not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= self.owner then
      self:Hide()
      return
    end
    UI.Layout()
  end)
  if GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipCleared", function() if card then card:Hide() end end)
  end
  return f
end

local function placeText(fs, x, y, width, text)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
  fs:SetWidth(width)
  fs:SetText(text)
  fs:Show()
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return math.ceil(type(h) == "number" and h > 0 and h or 12)
end

-- Draws the model at the tooltip's current width and docks the card. Run on every show and on
-- the card's own refresh, so the pill's age keeps counting and a tooltip that grew is followed.
function UI.Layout()
  local f, m = card, card and card.model
  if not (f and m) then return end
  local T, B, DC = GC.Theme, GC.Kit.Tokens.blizzard, GC.DealCard
  local refused = DC.Refused(m.verdict)
  local edge = refused and B.text4 or B.gold
  f.edge:SetColorTexture(edge[1], edge[2], edge[3], 1)

  local pill = DC.Pill(m.deal, m.verdict, m.verdict and m.verdict.at and m.now and (m.now() - m.verdict.at) or nil)
  f.pill:SetLabel(pill.text, colour(pill.tone))
  f.pill:SetWidth(textWidth(f.pill.text, 60) + 14)
  -- As wide as the tooltip, never under MIN_W, and wider still when a language's pill beside the
  -- brand, or its three scale labels, need it: a cut word is never drawn.
  local bar, s = f.bar, m.scale
  local need = 14 + 5 + textWidth(f.brand, 60) + 12 + f.pill:GetWidth()
  if s then
    local sum = 0
    for i, label in ipairs(bar.labels) do
      label:SetText(s.labels[i])
      sum = sum + textWidth(label, 60)
    end
    need = math.max(need, sum + 2 * 12)
  end
  local width = math.max(MIN_W, math.floor((GameTooltip:GetWidth() or 0) + 0.5), need + 2 * PAD)
  local inner = width - 2 * PAD
  f:SetWidth(width)
  local y = -PAD - HEAD_H - GAP

  if m.big then
    f.bigLabel:ClearAllPoints()
    f.bigLabel:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, y - BIG_H + 4)
    f.bigLabel:SetText(m.big.label)
    f.bigLabel:Show()
    f.bigValue:ClearAllPoints()
    f.bigValue:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    f.bigValue:SetText(m.big.text)
    paint(f.bigValue, colour(m.big.tone))
    f.bigValue:Show()
    y = y - BIG_H - GAP
  else
    f.bigLabel:Hide()
    f.bigValue:Hide()
  end

  if s then
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 3)
    bar:SetWidth(inner)
    bar.fill:SetWidth(math.max(1, math.floor(inner * s.limit + 0.5)))
    for _, mark in ipairs({ { bar.cheap, s.cheap }, { bar.limit, s.limit }, { bar.ref, s.ref } }) do
      mark[1]:ClearAllPoints()
      mark[1]:SetPoint("CENTER", bar, "LEFT", math.floor(inner * mark[2] + 0.5), 0)
    end
    paint(bar.labels[1], s.under and B.profit or B.loss)
    bar.cheap:SetColorTexture((s.under and B.profit or B.loss)[1], (s.under and B.profit or B.loss)[2],
      (s.under and B.profit or B.loss)[3], 1)
    -- The cheapest from the left edge, the AH value or vendor price to the right one, the limit
    -- between them, each at its own width.
    local labelY = y - BAR_H - 10
    for i, label in ipairs(bar.labels) do
      label:ClearAllPoints()
      label:SetWidth(textWidth(label, 60) + 2)
      if i == 1 then
        label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, labelY)
      elseif i == 3 then
        label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, labelY)
      else
        label:SetPoint("TOP", f, "TOPLEFT", PAD + math.floor(inner / 2), labelY)
      end
      label:Show()
    end
    bar:Show()
    y = y - BAR_H - 10 - 12 - GAP
  else
    bar:Hide()
    for _, label in ipairs(bar.labels) do label:Hide() end
  end

  if #m.chips > 0 then
    local x = PAD
    for i, chip in ipairs(m.chips) do
      local c = slot(f.chips, i, function() return T.Chip(f) end)
      c:SetLabel(chip.text, colour(chip.tone))
      c:SetWidth(textWidth(c.text, 40) + 14)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
      c:Show()
      x = x + c:GetWidth() + 4
    end
    y = y - CHIP_H - GAP
  end
  hideFrom(f.chips, #m.chips + 1)

  for i, note in ipairs(m.notes) do
    local fs = slot(f.notes, i, function()
      local n = T.Label(f, 10)
      n:SetWordWrap(true)
      return n
    end)
    paint(fs, note.color or colour(note.tone))
    y = y - placeText(fs, PAD, y, inner, note.text) - 3
  end
  if #m.notes > 0 then y = y - GAP + 3 end
  hideFrom(f.notes, #m.notes + 1)

  for i, fact in ipairs(m.facts) do
    local row = slot(f.facts, i, function()
      local left, right = T.Label(f, 10), T.Num(f, 10)
      left:SetWordWrap(false)
      right:SetJustifyH("RIGHT")
      return { left = left, right = right }
    end)
    local value = fact.copper and GC.Util.CoinText(fact.copper) or fact.right or ""
    if fact.copper and fact.right then value = value .. " · " .. fact.right end
    paint(row.left, fact.tone and colour(fact.tone) or B.text3)
    paint(row.right, B.text1)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    row.right:SetText(value)
    row.right:Show()
    placeText(row.left, PAD, y, math.max(40, inner - textWidth(row.right, 0) - 6), fact.left)
    y = y - FACT_H
  end
  if #m.facts > 0 then y = y - GAP + 2 end
  hideFrom(f.facts, #m.facts + 1)

  if #m.hints > 0 then
    f.foot:ClearAllPoints()
    f.foot:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f.foot:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    f.foot:Show()
    y = y - GAP
    local x = PAD
    for i, hint in ipairs(m.hints) do
      local h = slot(f.hints, i, function()
        local cap = CreateFrame("Frame", nil, f)
        cap:SetHeight(HINT_H - 2)
        cap.bg = T.Solid(cap, "BACKGROUND", { B.ink[1], B.ink[2], B.ink[3], 0.08 })
        cap.bg:SetAllPoints()
        T.EdgeBorder(cap, { B.ink[1], B.ink[2], B.ink[3], 0.25 })
        cap.key = T.Num(cap, 8, true)
        cap.key:SetJustifyH("CENTER")
        cap.key:SetPoint("CENTER")
        cap.text = T.Label(f, 9)
        cap.text:SetWordWrap(false)
        return cap
      end)
      h.key:SetText(hint.key)
      paint(h.key, B.text1)
      h:SetWidth(textWidth(h.key, 20) + 8)
      h.text:SetText(hint.text)
      -- A hint that does not fit what is left of the row starts the next one.
      local wide = h:GetWidth() + 4 + textWidth(h.text, 40)
      if x > PAD and x + wide > width - PAD then
        x = PAD
        y = y - HINT_H - 2
      end
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
      h:Show()
      h.text:ClearAllPoints()
      h.text:SetPoint("LEFT", h, "RIGHT", 4, 0)
      paint(h.text, B.text3)
      h.text:Show()
      x = x + wide + 10
    end
    for i = #m.hints + 1, #f.hints do f.hints[i]:Hide() f.hints[i].text:Hide() end
    y = y - HINT_H
  else
    f.foot:Hide()
    for _, h in ipairs(f.hints) do h:Hide() h.text:Hide() end
  end

  local height = -y + PAD - GAP
  f:SetHeight(height)
  UI.Dock(height)
end

-- Docks the card on the tooltip's bottom edge, or its top when the screen has no room below.
-- Flush with the tooltip's edge that faces away from the GoldCap window, so a card wider than the
-- tooltip grows away from the board, never over it.
function UI.Dock(height)
  local f = card
  local tipScale = GameTooltip.GetEffectiveScale and GameTooltip:GetEffectiveScale() or 1
  local screen = UIParent
  local screenTop = screen and screen.GetTop and screen:GetTop()
  if screenTop and screen.GetEffectiveScale then screenTop = screenTop * screen:GetEffectiveScale() / tipScale end
  local side = GC.DealCard.Side(GameTooltip:GetBottom(), GameTooltip:GetTop(), height, screenTop)
  local window = f.window
  local tipLeft, winLeft = GameTooltip:GetLeft(), window and window.GetLeft and window:GetLeft()
  local leftOfWindow = false
  if tipLeft and winLeft and window.GetEffectiveScale then
    leftOfWindow = tipLeft * tipScale < winLeft * window:GetEffectiveScale()
  end
  local edge = leftOfWindow and "RIGHT" or "LEFT"
  f:ClearAllPoints()
  if side == "above" then
    f:SetPoint("BOTTOM" .. edge, GameTooltip, "TOP" .. edge, 0, 0)
  else
    f:SetPoint("TOP" .. edge, GameTooltip, "BOTTOM" .. edge, 0, 0)
  end
end

--- Shows the card for `owner` (the row GameTooltip was just drawn for) with `model` (see
-- GC.Sniper._CardModel), beside `window`. Call after GameTooltip:Show(), so its width is laid out.
function UI.Show(owner, model, window)
  if not (GameTooltip and model) then return end
  card = card or build()
  card.owner, card.model, card.window = owner, model, window
  model.chips, model.notes = model.chips or {}, model.notes or {}
  model.facts, model.hints = model.facts or {}, model.hints or {}
  card:Show()
  UI.Layout()
end

function UI.Hide()
  if card then card:Hide() end
end

-- For the specs: the card frame, once built.
function UI._Frame() return card end
