-- The dock's posting panel (owner, 2026-10-10). It used to take three places to post one item --
-- the circle to mark it, the item's panel for its price and how many, the dock's POST to send it
-- -- so the bulk action was more work than the row it was meant to save. Now the dock holds the
-- item POST posts next, with its price and how many, beside SKIP and POST: Blizzard's own sell
-- pane, and Auctionator's. Each row keeps a Post of its own beside its price (owner, same day:
-- "it is handy"). The dock's item is the one the player clicked (S.dockKey), or the next one on
-- the selling list in the list's own order (UI.Dock.Current). After a post or a SKIP the dock
-- moves on; the walk goes over the list once a visit (GC.Sell._HoldDoneInQueue).
--
-- What a post spends is still decided where it always was: the price and the number typed here
-- are the same priceOverrides and quantityOverrides BuildPostPlan reads, and POST is onQueueClick
-- (UI/Sell/Dock.lua) -- this file makes no auction-house call.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local Post = GC.SellPost
local exact, safeMultiply, overrideKey = GC.SellUtil.exact, GC.SellUtil.safeMultiply, GC.SellUtil.overrideKey
local effectivePostUnit, postQuantity = GC.SellUtil.effectivePostUnit, GC.SellUtil.postQuantity
local UI = GC.SellUI
local PostPanel, DOCK = UI.PostPanel, UI.DOCK
local setColor, formatCell = UI.fmt.setColor, UI.fmt.cell
local priceText, priceBoxCopper = UI.fmt.priceText, UI.fmt.priceBoxCopper

-- A sunken well with a bare EditBox in it: the look the item panel's price box had.
local function well(container, width)
  local bg = CreateFrame("Frame", nil, container)
  bg:SetSize(width, DOCK.BOX_H)
  -- The window's own ground colour; several of this suite's theme doubles carry no `bg`.
  local wellc = Theme.color.bg or Theme.color.panel
  local fill = Theme.SlicedTexture(bg, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { wellc[1], wellc[2], wellc[3], 1 }, 12)
  fill:SetAllPoints(bg)
  bg.ring = Theme.SlicedTexture(bg, "BORDER", Theme.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.14 }, 12)
  bg.ring:SetAllPoints(bg)
  local box = CreateFrame("EditBox", nil, bg)
  box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -2)
  box:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 2)
  -- Guarded for busted, whose EditBox doubles stop at the text API. In the client a bare
  -- EditBox with no font does not draw its text at all, so this is not optional.
  if box.SetFont then
    box:SetFont(Theme.FONT_UI_BOLD, 13 * Theme.Scale(), "")
    box:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    Theme.OnRescale(function(scale) box:SetFont(Theme.FONT_UI_BOLD, 13 * scale, "") end)
  end
  return bg, box
end

-- What a box typed into belongs to: the item that was in the dock when the box was clicked into.
-- A post landing mid-typing moves the dock on, and a number typed for one item must never land
-- on the next. `apply(box, key, settled)` records it -- live on every keystroke, settled on
-- Enter or focus loss -- into S[`store`]; Escape puts back what was there before the box was
-- clicked into, since the keystrokes recorded as they went (review). A box clicked into and out
-- of without a keystroke records nothing: GoldCap's own price must not turn into the seller's
-- and stop following the market (review). `refuse(box)`, when given, turns away text that
-- cannot be recorded at all: nothing is, and the typing and the cursor stay for the seller to
-- fix rather than reverting under them.
local function bind(box, store, apply, refuse)
  box:SetScript("OnEditFocusGained", function(self)
    self.editingKey, self.edited = PostPanel.key, false
    self.before = self.editingKey and S[store][self.editingKey]
  end)
  box:SetScript("OnTextChanged", function(self, byUser)
    -- Only the player's own typing: a SetText from a paint fires this too.
    if not byUser or self.committing then return end
    if not self.editingKey or self.editingKey ~= PostPanel.key then return end
    self.edited = true
    apply(self, self.editingKey, false)
  end)
  local function commit(self)
    if self.committing then return end
    local key = self.editingKey
    local mine = key ~= nil and key == PostPanel.key and self.edited
    if mine and refuse and refuse(self) then return end
    self.editingKey, self.edited = nil, false
    -- ClearFocus raises OnEditFocusLost, which is this same function.
    self.committing = true
    self:ClearFocus()
    self.committing = false
    if mine then apply(self, key, true) else UI.List.RenderRows() end
  end
  box:SetScript("OnEnterPressed", commit)
  box:SetScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function(self)
    local key = self.editingKey
    if key ~= nil and key == PostPanel.key and self.edited then
      -- A Confirm armed with what was typed is let go, as any other change does.
      if S[store][key] ~= self.before then Post.WalkAway() end
      S[store][key] = self.before
    end
    self.editingKey, self.edited = nil, false
    self.committing = true
    self:ClearFocus()
    self.committing = false
    UI.List.RenderRows()
  end)
end

-- Takes the focus from a box without recording anything: the dock moved on under it.
local function letGo(box)
  if not (box.HasFocus and box:HasFocus()) then return end
  box.editingKey = nil
  box.committing = true
  box:ClearFocus()
  box.committing = false
end

-- The price: empty hands the decision back to GoldCap, which is a real answer. Half-typed text
-- ("39." between two keystrokes) keeps the last price that read as one. A Confirm waiting on the
-- old price is let go: it would send the price it was armed with, not the one now on screen.
local function applyPrice(box, key)
  local copper
  if not (box:GetText() or ""):match("^%s*$") then
    copper = priceBoxCopper(box)
    if not copper then return end
  end
  if S.priceOverrides[key] ~= copper then Post.WalkAway() end
  S.priceOverrides[key] = copper
  UI.List.RenderRows()
end

local function unreadablePrice(box)
  local text = box:GetText() or ""
  if text:match("^%s*$") or priceBoxCopper(box) then return false end
  UI.Dock.Answer(GC.L["Type a price in gold, or clear the box to use GoldCap's"])
  return true
end

-- How many: empty, nought or the most there is all mean "all of it", which is no entry. The
-- queue is built again only once the number is settled, and not while a post is out: that post
-- carries the number it was pinned with, and the dock's CONFIRM follows the item it pinned.
local function setQuantity(key, n, settled)
  local _, most = postQuantity(PostPanel.position)
  local chosen = (n and n > 0 and n < most) and n or nil
  -- As the price's: a Confirm armed with another number is let go.
  if S.quantityOverrides[key] ~= chosen then Post.WalkAway() end
  S.quantityOverrides[key] = chosen
  if settled and not S.postingRow then GC.SellCompose.Queue() end
  UI.List.RenderRows()
end

local function applyQuantity(box, key, settled)
  local n = tonumber((box:GetText() or ""):match("^%s*(%d+)%s*$") or "")
  -- Between two keystrokes the box can be empty; that is not yet an answer.
  if not settled and not (n and n > 0) then return end
  setQuantity(key, n, settled)
end

-- How far from the dock's right edge the item's words stop: the controls right to left from POST,
-- as Build and Layout chain them, and DOCK.GAP. Read off the widths the client measured (POST and
-- SKIP fit their words), so the name keeps whatever the player's language leaves it.
local function controlsWidth(c)
  -- Off the client (busted) a button double may not answer GetWidth: its narrowest, then.
  local function width(button, least) return button.GetWidth and button:GetWidth() or least end
  local w = DOCK.PAD + width(c.queueButton, DOCK.POST_W)
  if c.skipButton:IsShown() then
    w = w + 8 + width(c.skipButton, DOCK.SKIP_W)
    if c.netValue:IsShown() then
      local note = c.netNote.GetUnboundedStringWidth and c.netNote:GetUnboundedStringWidth() or 0
      w = w + 16 + math.ceil(note) + 4 + DOCK.NET_W
    end
    w = w + 16 + DOCK.PRICE_W
    if c.qtyBoxBg:IsShown() then w = w + 14 + DOCK.MAX_W + 4 + DOCK.QTY_W end
  end
  return w + DOCK.GAP
end

-- The item's icon, its name and the line under it -- the stock line, or the player's own post's
-- news in its place -- left of the controls and centred on the dock, which grows when they wrap
-- past its height (UI.Dock.SetHeight). Top points only, so a wrapped name pushes the line under
-- it down rather than over it. Run after the controls are shown or hidden: they set the width.
local function fitItem(c)
  local right = controlsWidth(c)
  local x = DOCK.PAD + (c.dockIcon:IsShown() and DOCK.ICON + 8 or 0)
  local function place(top)
    c.queueLabel:ClearAllPoints()
    c.queueLabel:SetPoint("TOPLEFT", c, "BOTTOMLEFT", x, top)
    c.queueLabel:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", -right, top)
  end
  place(DOCK.H)
  for _, line in ipairs({ c.dockSub, c.dockStatus }) do
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", c.queueLabel, "BOTTOMLEFT", 0, -2)
    line:SetPoint("TOPRIGHT", c.queueLabel, "BOTTOMRIGHT", 0, -2)
  end
  local under = c.dockStatus:IsShown() and c.dockStatus or c.dockSub:IsShown() and c.dockSub or nil
  local h = 26 -- a name and a line under it, where the face cannot be measured
  if c.queueLabel.GetStringHeight then
    c.queueLabel:SetText(c.queueLabel:GetText() or "") -- laid out at this width (Book.Layout)
    h = c.queueLabel:GetStringHeight() or 0
    if under then
      under:SetText(under:GetText() or "")
      h = h + 2 + (under:GetStringHeight() or 0)
    end
  end
  h = math.ceil(h)
  local height = math.max(DOCK.H, h + 2 * DOCK.PAD)
  local mid = height / 2
  place(math.floor(mid + h / 2))
  c.dockIcon:ClearAllPoints()
  c.dockIcon:SetPoint("LEFT", c, "BOTTOMLEFT", DOCK.PAD, mid)
  UI.Dock.SetHeight(height)
end

-- The player's own post's news under the item's name, in the stock line's place, for as long as
-- there is any (GC.Sell._PaintDock wrote it); the walk's words stay in the toolbar's line.
local function placeNews(c, item)
  if GC.Sell._postNote then
    c.dockStatus:Show(); c.dockSub:Hide()
  else
    c.dockStatus:Hide()
    if item then c.dockSub:Show() end
  end
end

-- The posting row, right to left from POST (built by UI/Sell/Dock.lua): SKIP, what the post
-- fetches, the price and how many; the item itself left of them (fitItem).
function PostPanel.Build()
  local c = UI.container

  local skip = Theme.Button(c, "ghost", "plaque")
  skip:SetSize(DOCK.SKIP_W, DOCK.BUTTON_H)
  skip:SetPoint("RIGHT", c.queueButton, "LEFT", -8, 0)
  skip:SetLabel(GC.L["SKIP"])
  local function fitSkip() skip:FitLabels({ GC.L["SKIP"] }, DOCK.SKIP_W) end
  if skip.FitLabels and Theme.OnRescale then fitSkip(); Theme.OnRescale(fitSkip) end
  skip:SetScript("OnClick", function()
    local key = PostPanel.key
    if not key then return end
    -- Its post on the wire decides where the dock goes (Paint disables SKIP meanwhile; a click
    -- before that paint lands here).
    local out = S.postingRow
    if out and out.position and out.position.positionKey == key
        and (out.postStage == "posting" or out.postStage == "confirming") then return end
    Post.WalkAway() -- an armed post is a question; moving on answers it "no"
    GC.Sell.PassDockItem(key)
    -- The item's panel shuts with it, and its row stops looking chosen: the dock has moved on
    -- (owner, 2026-10-10).
    UI.expanded[key] = nil
    UI.List.RenderRows()
  end)
  c.skipButton = skip

  -- What this post fetches: the row's YOU GET, for what the dock is about to send, and beside it
  -- what the price makes over what one cost (the 3C design). The margin is as wide as its words.
  c.netValue = Theme.Num(c, 11, true)
  c.netValue:SetWidth(DOCK.NET_W)
  c.netValue:SetJustifyH("RIGHT"); c.netValue:SetWordWrap(false)
  c.netNote = Theme.Num(c, 10)
  c.netNote:SetJustifyH("LEFT"); c.netNote:SetWordWrap(false)
  c.netHead = Theme.Num(c, 9)
  c.netHead:SetJustifyH("RIGHT")
  c.netHead:SetPoint("BOTTOMRIGHT", c.netValue, "TOPRIGHT", 0, 6)
  setColor(c.netHead, Theme.color.fgDim)

  c.priceBoxBg, c.priceBox = well(c, DOCK.PRICE_W)
  bind(c.priceBox, "priceOverrides", applyPrice, unreadablePrice)
  c.priceHead = Theme.Num(c, 9)
  c.priceHead:SetPoint("BOTTOMLEFT", c.priceBoxBg, "TOPLEFT", 0, 3)

  c.qtyMax = Theme.Button(c, "ghost", "badge")
  c.qtyMax:SetSize(DOCK.MAX_W, 22)
  c.qtyMax:SetPoint("RIGHT", c.priceBoxBg, "LEFT", -14, 0)
  c.qtyMax:SetScript("OnClick", function()
    local key = PostPanel.key
    if not key then return end
    letGo(c.qtyBox)
    setQuantity(key, nil, true)
  end)
  -- How many there are is the stock line's "×246 in bags"; MAX sets all of them.
  c.qtyBoxBg, c.qtyBox = well(c, DOCK.QTY_W)
  if c.qtyBox.SetNumeric then c.qtyBox:SetNumeric(true) end
  if c.qtyBox.SetMaxLetters then c.qtyBox:SetMaxLetters(6) end
  c.qtyBoxBg:SetPoint("RIGHT", c.qtyMax, "LEFT", -4, 0)
  bind(c.qtyBox, "quantityOverrides", applyQuantity)
  c.qtyHead = Theme.Num(c, 9)
  c.qtyHead:SetPoint("BOTTOMLEFT", c.qtyBoxBg, "TOPLEFT", 0, 3)

  -- The item, left of the controls: its icon, its name, and under it how many are in the bags and
  -- what comes after it -- or, when the price is under what it cost, that, in red. Both wrap, and
  -- the dock grows to hold them (fitItem): nothing here ends in "…".
  c.dockIcon = c:CreateTexture(nil, "ARTWORK")
  c.dockIcon:SetSize(DOCK.ICON, DOCK.ICON)
  c.dockIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the stock icon border
  c.queueLabel = Theme.Num(c, 11, true)
  c.queueLabel:SetJustifyH("LEFT"); c.queueLabel:SetWordWrap(true)
  c.dockSub = Theme.Num(c, 9)
  c.dockSub:SetJustifyH("LEFT"); c.dockSub:SetWordWrap(true)
  PostPanel.Layout()
end

-- Re-run on every resize: under DOCK.WIDE the row drops YOU GET and the price moves up against
-- SKIP.
function PostPanel.Layout()
  local c = UI.container
  if not (c and c.priceBoxBg) then return end
  PostPanel.wide = (UI.rowWidth or 0) >= DOCK.WIDE
  c.netNote:ClearAllPoints()
  c.netNote:SetPoint("RIGHT", c.skipButton, "LEFT", -16, 0)
  c.netValue:ClearAllPoints()
  c.netValue:SetPoint("RIGHT", c.netNote, "LEFT", -4, 0)
  c.priceBoxBg:ClearAllPoints()
  c.priceBoxBg:SetPoint("RIGHT", PostPanel.wide and c.netValue or c.skipButton, "LEFT", -16, 0)
end

local ITEM_WIDGETS = { "dockIcon", "dockSub", "qtyHead", "qtyBoxBg", "qtyMax", "priceHead",
  "priceBoxBg", "netHead", "netValue", "netNote", "skipButton" }

local function hideItem(c)
  for _, name in ipairs(ITEM_WIDGETS) do c[name]:Hide() end
end

-- The icon the row shows for the item.
local function iconOf(itemID)
  if not (itemID and C_Item and C_Item.GetItemIconByID) then return nil end
  local ok, texture = pcall(C_Item.GetItemIconByID, itemID)
  return ok and texture or nil
end

-- A box's text, unless the player is typing into it for this same item.
local function stamp(box, key, text)
  if box.HasFocus and box:HasFocus() then
    if box.editingKey == key then return end
    letGo(box)
  end
  box:SetText(text)
end

-- Off the posting deck the row is the cancel queue's, and the status line is its own again
-- (UI.Dock.LayoutLedger places it).
function PostPanel.Hide()
  local c = UI.container
  if not (c and c.dockIcon) then return end
  hideItem(c)
  letGo(c.priceBox); letGo(c.qtyBox)
  c.queueLabel:Hide()
  c.dockStatus:Show()
  PostPanel.position, PostPanel.key = nil, nil
  UI.Dock.SetHeight(DOCK.H)
end

--- Paints the posting row for `row`, the dock's item (UI.Dock.Current), with `nextRow` the one
-- after it; `hint` is what to say when there is no item. Also lights the item's card: its edge in
-- gold says this is what POST posts. The card's own edge, not a bar beside it: the spine stood out
-- of the card at its left (owner, 2026-10-10).
function PostPanel.Paint(row, nextRow, hint)
  local c = UI.container
  if not (c and c.dockIcon) then return end
  local gold, edge = Theme.color.gold, Theme.color.border or { 1, 1, 1, 0.075 }
  for _, r in ipairs(UI.rows or {}) do
    if r.kind == "position" and r.cardRing then
      if r == row then r.cardRing:SetVertexColor(gold[1], gold[2], gold[3], 0.45)
      else r.cardRing:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 0.075) end
    end
  end
  local p = row and row.position or nil
  PostPanel.position, PostPanel.key = p, p and overrideKey(p) or nil
  if not p then
    hideItem(c)
    letGo(c.priceBox); letGo(c.qtyBox)
    c.queueLabel:SetText(hint or "")
    setColor(c.queueLabel, Theme.color.fgDim)
    c.queueLabel:Show()
    placeNews(c, false)
    fitItem(c)
    return
  end
  local key = PostPanel.key

  local icon = iconOf(p.itemID)
  if icon then c.dockIcon:SetTexture(icon); c.dockIcon:Show() else c.dockIcon:Hide() end
  c.queueLabel:SetText(p.itemName or GC.L["Item"])
  setColor(c.queueLabel, Theme.color.fg)
  c.queueLabel:Show()

  local unit, chosen = effectivePostUnit(p)
  local risk = GC.SellPositions.PriceRisk(p, unit)
  -- The walk and a row click both bring an item the queue held back to the dock (a vendor pays
  -- more, it would sell at a loss): POST will list it, so the dock says why the queue would not.
  local heldBack = UI.Dock.HeldBackText(p.positionKey)
  -- Under what it cost, under GoldCap's floor or held back is what the line says first, in red;
  -- otherwise what is in the bags and what POST goes to after this.
  if risk.belowCost then
    c.dockSub:SetText((GC.L["below the %s you paid"]):format(formatCell(risk.paidUnit)))
    setColor(c.dockSub, Theme.color.red)
  elseif risk.belowFloor then
    c.dockSub:SetText((GC.L["under GoldCap's own floor of %s"]):format(formatCell(risk.floor)))
    setColor(c.dockSub, Theme.color.red)
  elseif heldBack then
    c.dockSub:SetText(heldBack)
    setColor(c.dockSub, Theme.color.red)
  else
    local line = (GC.L["×%d in bags"]):format(p.bagQty or 0)
    local nextItem = nextRow and nextRow.position and nextRow.position.itemName
    if nextItem then line = line .. " · " .. (GC.L["then %s"]):format(nextItem) end
    c.dockSub:SetText(line)
    setColor(c.dockSub, Theme.color.fgDim)
  end
  placeNews(c, true)

  -- How many, only when there is more than one to choose from.
  local qty, most, typed = postQuantity(p)
  if most > 1 then
    stamp(c.qtyBox, key, tostring(qty))
    c.qtyHead:SetText(GC.L["HOW MANY"])
    setColor(c.qtyHead, typed and Theme.color.gold or Theme.color.fgDim)
    local gc = Theme.color.gold
    if typed then c.qtyBoxBg.ring:SetVertexColor(gc[1], gc[2], gc[3], 0.7)
    else c.qtyBoxBg.ring:SetVertexColor(1, 1, 1, 0.14) end
    c.qtyMax:SetLabel(GC.L["MAX"])
    -- Lit while it is all of it: a switch with a position. SetVariant before Show, as the kit asks.
    if c.qtyMax.SetVariant then c.qtyMax:SetVariant(typed and "ghost" or "active") end
    c.qtyHead:Show(); c.qtyBoxBg:Show(); c.qtyMax:Show()
  else
    letGo(c.qtyBox)
    c.qtyHead:Hide(); c.qtyBoxBg:Hide(); c.qtyMax:Hide()
  end

  -- The price: gold once it is the seller's own, red under cost or the floor, quiet while it is
  -- GoldCap's -- the ring says whose it is before a word is read.
  stamp(c.priceBox, key, unit and priceText(unit) or "")
  c.priceHead:SetText(GC.L["YOUR PRICE"])
  setColor(c.priceHead, chosen and Theme.color.gold or Theme.color.fgDim)
  local ring = (risk.belowCost or risk.belowFloor) and Theme.color.red or chosen and Theme.color.gold or nil
  if ring then c.priceBoxBg.ring:SetVertexColor(ring[1], ring[2], ring[3], 0.7)
  else c.priceBoxBg.ring:SetVertexColor(1, 1, 1, 0.14) end
  c.priceHead:Show(); c.priceBoxBg:Show()

  if PostPanel.wide then
    local gross = unit and exact(qty) and safeMultiply(unit, qty) or nil
    c.netHead:SetText(GC.L["YOU GET"])
    c.netValue:SetText(gross and formatCell(gross) or "")
    setColor(c.netValue, Theme.color.fg)
    local margin, tone = UI.fmt.margin(unit, risk.paidUnit)
    c.netNote:SetText(margin or "")
    if margin then setColor(c.netNote, tone) end
    c.netHead:Show(); c.netValue:Show(); c.netNote:Show()
  else
    c.netHead:Hide(); c.netValue:Hide(); c.netNote:Hide()
  end
  -- Nothing to pass over while its post is on the wire: the answer decides where the dock goes.
  local out = S.postingRow
  local sending = out and out.position and out.position.positionKey == p.positionKey
    and (out.postStage == "posting" or out.postStage == "confirming")
  c.skipButton:Show()
  if sending then c.skipButton:Disable() else c.skipButton:Enable() end
  fitItem(c)
end
