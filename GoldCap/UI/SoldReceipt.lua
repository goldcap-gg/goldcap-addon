local _, GC = ...

-- The receipt a Sold row opens into (UI/SoldFrame.lua): three columns under the row, inside its
-- gold outline. RECEIPT, the sale's own sums that add up to what reached the mailbox; AGAINST
-- TODAY'S MARKET, only for an item with an exact market price; and the third, which finishes the
-- sale -- a cost typed for it, or the way to SELL for the units still in the bags -- or, with
-- nothing to finish, says where its profit came from. Everything the hover tooltip said before
-- it is here. What shows is decided in Core/SoldReceipt.lua; this file only draws it.
--
-- One receipt for the whole tab, moved to whichever row is open: only one ever is.
GC.SoldReceiptUI = {}
local UIR = GC.SoldReceiptUI

local RC = {
  PAD = 12, COL_GAP = 18, LINE = 5, AFTER_TITLE = 8, RULE_DASH = 4, RULE_GAP = 3, RULE_H = 1,
  BAR_H = 4, INPUT_W = 96, INPUT_H = 22, BTN_H = 22, BTN_PAD = 10, PAIR_GAP = 8, COL_MIN = 120,
}
UIR.RC = RC

-- @localised-keys: where the stock a sale drew on came from (GC.Acquisitions batch sources).
local SOURCE_TEXT = {
  goldcap = "Sniper", goldcap_buy = "BUY list", manual = "set by you", auction_house = "the auction house",
  craft = "crafted",
}

-- The sale's own sentences about the reagents a crafted item's cost counted (or could not):
-- the same lines /gc craft prints, read through the item's exact id only.
local function craftLines(id, which)
  local cc = GC.CraftCapture
  local api = _G.C_Item
  if not (id and cc and cc[which] and api and api.GetItemNameByID) then return {} end
  return cc[which](id, function(itemID)
    local ok, name = pcall(api.GetItemNameByID, itemID)
    return ok and type(name) == "string" and name or nil
  end) or {}
end

-- What each column says, as a list of items the layout below stacks top-down. `r` is the sale's
-- row (Core/SoldView.lua), `info` its item (exact id or nil), `cols` Core/SoldReceipt.Columns.
function UIR.Content(r, info, cols, H)
  local plain, signed, color = H.plain, H.signed, GC.Theme.color
  local warn = GC.Kit.Tokens.color.warn or color.goldHi
  local each = plain(r.each or 0, true)

  local receipt = { { kind = "title", text = GC.L["RECEIPT"] } }
  local when
  if r.pending then when = GC.L["sold, the money is in your mail"]
  elseif H.isToday(r.at) then when = GC.L["sold today at %s"]:format(H.clock(r.at))
  else when = GC.L["sold %s at %s"]:format(H.shortDate(r.at), H.clock(r.at)) end
  receipt[#receipt + 1] = { kind = "text", text = when, color = color.fgDim }
  receipt[#receipt + 1] = { kind = "pair", left = GC.L["%d sold at %s"]:format(r.qty, each),
    right = plain(r.gross, true), rc = color.fg }
  receipt[#receipt + 1] = { kind = "pair", left = r.cutEstimated and GC.L["Auction house, 5%"] or GC.L["Auction house"],
    right = "-" .. plain(r.cut, true), rc = color.red }
  receipt[#receipt + 1] = { kind = "rule" }
  receipt[#receipt + 1] = { kind = "total", left = GC.L["You got"], right = plain(r.net, true) }

  local market
  if cols.market then
    local pct = GC.SoldView.Percent(r.each, cols.marketPrice)
    local tone = GC.SoldReceipt.Tone(pct)
    local big = tone == "above" and GC.L["%d%% above"]:format(pct) or tone == "under" and GC.L["%d%% under"]:format(-pct)
      or GC.L["at the market"]
    local top = math.max(cols.marketPrice, r.each or 0)
    market = { { kind = "title", text = GC.L["AGAINST TODAY'S MARKET"] },
      { kind = "big", text = big, color = tone == "above" and color.green or tone == "under" and warn or color.fgDim },
      { kind = "bar", text = GC.L["market %s"]:format(plain(cols.marketPrice, true)), share = cols.marketPrice / top,
        color = color.fgDim },
      { kind = "bar", text = GC.L["you %s"]:format(each), share = (r.each or 0) / top,
        color = tone == "under" and warn or color.green } }
  end

  local third = { { kind = "title", text = cols.title == "finish" and GC.L["FINISH THIS SALE"] or GC.L["PROFIT"] } }
  if type(r.profit) == "number" then
    local names = {}
    for _, source in ipairs(r.sources or {}) do
      if SOURCE_TEXT[source] then names[#names + 1] = GC.L[SOURCE_TEXT[source]] end
    end
    local paid = #names > 0 and GC.L["You paid (%s)"]:format(table.concat(names, ", ")) or GC.L["You paid"]
    if r.paid then third[#third + 1] = { kind = "pair", left = paid, right = plain(r.paid, true), rc = color.cost } end
    if r.paidEach then third[#third + 1] = { kind = "text", text = GC.L["%s each"]:format(plain(r.paidEach, true)), color = color.fgDim } end
    if r.costUnits then
      third[#third + 1] = { kind = "text", text = GC.L["cost known for %d of %d"]:format(r.costUnits, r.qty), color = color.fgDim }
    end
    third[#third + 1] = { kind = "total", left = GC.L["Profit"], right = signed(r.profit, true),
      rc = r.profit >= 0 and color.green or color.red }
    -- A crafted item whose cost counts reagents at the market price says so, and which.
    for _, why in ipairs(craftLines(info.id, "WhyEstimated")) do
      third[#third + 1] = { kind = "text", text = why, color = color.fgDim }
    end
  elseif cols.note == "pending" then
    third[#third + 1] = { kind = "text", text = GC.L["The profit is worked out once the money arrives."], color = color.fgMuted }
  elseif cols.note == "pro" then
    third[#third + 1] = { kind = "text", text = GC.L["Profit tracking is a goldcap.gg Pro feature"], color = color.fgMuted }
  else
    if cols.note == "unseen" then
      third[#third + 1] = { kind = "text",
        text = GC.L["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."],
        color = color.fgMuted }
    end
    -- A crafted item says which reagent had no price and why (/gc craft says the same).
    for _, why in ipairs(craftLines(info.id, "WhyUncosted")) do
      third[#third + 1] = { kind = "text", text = why, color = color.fgMuted }
    end
  end
  if cols.save then
    third[#third + 1] = { kind = "text", text = GC.L["Paid each"], color = color.fgDim }
    third[#third + 1] = { kind = "input" }
  end
  if cols.bags > 0 then
    third[#third + 1] = { kind = "button", text = cols.bags == 1 and GC.L["1 MORE IN BAGS · SELL"]
      or GC.L["%d MORE IN BAGS · SELL"]:format(cols.bags) }
  end
  return { receipt, market, third }
end

-- Widgets -----------------------------------------------------------------------------------

local function newText(rc, kind)
  local T = GC.Theme
  local w = {}
  if kind == "title" then
    w.left = T.Num(rc.frame, 9, true)
  elseif kind == "text" or kind == "bar" then
    w.left = T.Num(rc.frame, 10)
  elseif kind == "big" then
    w.left = T.Num(rc.frame, 16, true)
  elseif kind == "pair" then
    w.left, w.right = T.Num(rc.frame, 10), T.Num(rc.frame, 11, true)
  elseif kind == "total" then
    w.left, w.right = T.Label(rc.frame, 12), T.Num(rc.frame, 15, true)
  end
  w.left:SetJustifyH("LEFT")
  if w.right then w.right:SetJustifyH("RIGHT") end
  if kind == "bar" then w.bar = T.Bar(rc.frame, RC.BAR_H) end
  return w
end

local function take(rc, kind)
  local pool = rc.pool[kind]
  if not pool then pool = { used = 0 }; rc.pool[kind] = pool end
  pool.used = pool.used + 1
  pool[pool.used] = pool[pool.used] or newText(rc, kind)
  return pool[pool.used]
end

local function hideAll(rc)
  for _, pool in pairs(rc.pool) do
    for i = 1, #pool do
      local w = pool[i]
      w.left:Hide()
      if w.right then w.right:Hide() end
      if w.bar then w.bar:Hide() end
    end
    pool.used = 0
  end
  for _, dash in ipairs(rc.dashes) do dash:Hide() end
  rc.dashesUsed = 0
  -- The cost box's well is left alone here: hiding an EditBox's parent takes its focus, and the
  -- receipt is painted again on every keystroke and every mail scan. Paint hides it only when this
  -- paint places no box.
  rc.save:Hide(); rc.preview:Hide(); rc.error:Hide(); rc.bags:Hide()
  rc.placedInput = false
end

local function dash(rc)
  rc.dashesUsed = rc.dashesUsed + 1
  local d = rc.dashes[rc.dashesUsed]
  if not d then
    d = GC.Theme.Solid(rc.frame, "ARTWORK", GC.Kit.Tokens.ink(0.22))
    rc.dashes[rc.dashesUsed] = d
  end
  return d
end

-- The width the third column's widgets need on one line: the cost box with SAVE beside it, or
-- the way to SELL with its whole label.
local function widgetNeed(rc, items, H)
  local need = 0
  for _, item in ipairs(items) do
    if item.kind == "input" then
      H.setLabel(rc.save, GC.L["SAVE"])
      need = math.max(need, RC.INPUT_W + RC.PAIR_GAP + H.widthOf(rc.save.text) + 2 * RC.BTN_PAD)
    elseif item.kind == "button" then
      H.setLabel(rc.bags, item.text)
      need = math.max(need, H.widthOf(rc.bags.text) + 2 * RC.BTN_PAD)
    end
  end
  return need
end

-- Stacks one column's items at (x, top) in `w` and says how tall it came out.
local function layColumn(rc, items, x, top, w, H)
  local y = 0
  local function at(fs, dx, dy) fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", rc.frame, "TOPLEFT", x + dx, -(RC.PAD + top + dy)) end
  for i, item in ipairs(items) do
    local gap = i == 1 and 0 or (items[i - 1].kind == "title" and RC.AFTER_TITLE or RC.LINE)
    y = y + gap
    if item.kind == "rule" then
      local n = math.max(1, math.floor((w + RC.RULE_GAP) / (RC.RULE_DASH + RC.RULE_GAP)))
      for k = 1, n do
        local d = dash(rc)
        d:SetSize(RC.RULE_DASH, RC.RULE_H)
        at(d, (k - 1) * (RC.RULE_DASH + RC.RULE_GAP), y)
        d:Show()
      end
      y = y + RC.RULE_H
    elseif item.kind == "input" then
      rc.placedInput = true
      H.setLabel(rc.save, GC.L["SAVE"])
      local saveW = H.widthOf(rc.save.text) + 2 * RC.BTN_PAD
      rc.well:SetSize(math.min(RC.INPUT_W, w), RC.INPUT_H)
      at(rc.well, 0, y)
      rc.well:Show()
      rc.save:SetSize(saveW, RC.INPUT_H)
      rc.save:ClearAllPoints()
      if RC.INPUT_W + RC.PAIR_GAP + saveW <= w then
        rc.save:SetPoint("LEFT", rc.well, "RIGHT", RC.PAIR_GAP, 0)
      else
        -- No room beside the box: SAVE goes under it.
        y = y + RC.INPUT_H + RC.LINE
        at(rc.save, 0, y)
      end
      rc.save:Show()
      y = y + RC.INPUT_H
      local preview = rc.preview:GetText() or ""
      if preview ~= "" then
        H.hug(rc.preview)
        at(rc.preview, 0, y + 3)
        rc.preview:Show()
        y = y + 3 + H.heightOf(rc.preview)
      end
      if (rc.error:GetText() or "") ~= "" then
        local eh = H.wrapTo(rc.error, w)
        at(rc.error, 0, y + 3)
        rc.error:Show()
        y = y + 3 + eh
      end
    elseif item.kind == "button" then
      H.setLabel(rc.bags, item.text)
      rc.bags:SetSize(H.widthOf(rc.bags.text) + 2 * RC.BTN_PAD, RC.BTN_H)
      at(rc.bags, 0, y + 2)
      rc.bags:Show()
      y = y + 2 + RC.BTN_H
    else
      local wdg = take(rc, item.kind)
      H.put(wdg.left, item.text or item.left)
      H.setColor(wdg.left, item.color or (item.kind == "title" and GC.Theme.color.goldHi)
        or (item.kind == "total" and GC.Theme.color.fg) or GC.Theme.color.fgMuted)
      local h
      if wdg.right then
        H.put(wdg.right, item.right)
        H.setColor(wdg.right, item.rc or GC.Theme.color.fg)
        local rw = math.min(w, H.hug(wdg.right))
        local lh = H.wrapTo(wdg.left, math.max(1, w - rw - RC.PAIR_GAP))
        wdg.right:ClearAllPoints()
        wdg.right:SetPoint("TOPRIGHT", rc.frame, "TOPLEFT", x + w, -(RC.PAD + top + y))
        at(wdg.left, 0, y + math.max(0, (H.heightOf(wdg.right) - lh) / 2))
        h = math.max(lh, H.heightOf(wdg.right))
      else
        h = H.wrapTo(wdg.left, w)
        at(wdg.left, 0, y)
      end
      if wdg.bar then
        wdg.bar:ClearAllPoints()
        wdg.bar:SetPoint("TOPLEFT", rc.frame, "TOPLEFT", x, -(RC.PAD + top + y + h + 3))
        wdg.bar:SetWidth(w)
        if wdg.bar.SetColor then wdg.bar:SetColor(item.color) end
        wdg.bar:SetShare(item.share)
        wdg.bar:Show()
        h = h + 3 + RC.BAR_H
      end
      y = y + h
    end
  end
  return y
end

--- Paints the receipt for `r` across `width` and says how tall it came out. `opts` carries what
--- the row worked out: cols (Core/SoldReceipt.Columns, with marketPrice), info, and the ledger
--- entry a typed cost books.
function UIR.Paint(rc, r, opts, width, H)
  hideAll(rc)
  if rc.forID ~= opts.id then
    -- Another sale: the box starts empty. The same sale re-rendered (a mail scan, a keystroke in
    -- search) keeps what was typed.
    rc.forID = opts.id
    rc.input:SetText("")
    rc.preview:SetText("")
    rc.error:SetText("")
  end
  rc.sale, rc.entry, rc.cols = r, opts.entry, opts.cols
  local columns = UIR.Content(r, opts.info, opts.cols, H)
  local shown = {}
  -- The market column may be nil: a hole ipairs would stop at.
  for i = 1, 3 do
    if columns[i] then shown[#shown + 1] = columns[i] end
  end
  rc.columns = shown
  local inner = width - 2 * RC.PAD
  local n = #shown
  local colW = math.floor((inner - (n - 1) * RC.COL_GAP) / n)
  local last = shown[n]
  local below = n > 1 and colW < math.max(RC.COL_MIN, widgetNeed(rc, last, H))
  -- The third column's box and button never squeeze or cut: where the columns side by side are
  -- too narrow for them (the narrowest window, a long translation, the largest font scale), the
  -- third goes under the others, as wide as the receipt.
  local across = below and n - 1 or n
  colW = math.floor((inner - (across - 1) * RC.COL_GAP) / across)
  local height = 0
  for i = 1, across do
    height = math.max(height, layColumn(rc, shown[i], RC.PAD + (i - 1) * (colW + RC.COL_GAP), 0, colW, H))
  end
  if below then
    height = height + RC.COL_GAP
    height = height + layColumn(rc, last, RC.PAD, height, inner, H)
  end
  rc.below = below
  if not rc.placedInput then rc.well:Hide() end
  height = height + 2 * RC.PAD
  rc.frame:SetSize(width, height)
  return height
end

--- The receipt is put away: the next one opened, even on the same sale, starts with an empty box.
function UIR.Close(rc)
  rc.frame:Hide()
  rc.forID = nil
end

--- Every shown line of the receipt, column by column, as text: what a player can read in it.
function UIR.Lines(rc)
  local out = {}
  for _, items in ipairs(rc.columns or {}) do
    local col = {}
    for _, item in ipairs(items) do
      if item.kind == "pair" or item.kind == "total" then col[#col + 1] = item.left .. " | " .. item.right
      elseif item.kind == "rule" then col[#col + 1] = "- - -"
      elseif item.kind == "input" then col[#col + 1] = "[input] " .. GC.L["SAVE"]
      else col[#col + 1] = item.text end
    end
    out[#out + 1] = col
  end
  return out
end

-- Saving ------------------------------------------------------------------------------------

local function save(rc, H)
  local copper = GC.SoldReceipt.ParseMoney(rc.input:GetText())
  if not copper then
    rc.error:SetText(GC.L["Enter an exact positive cost"])
    H.render()
    return
  end
  local ok = GC.SoldReceipt.SaveCost(GC.Acquisitions, rc.sale, rc.entry, copper)
  if ok then
    rc.input:SetText("")
    rc.preview:SetText("")
    rc.error:SetText("")
    if rc.input.ClearFocus then rc.input:ClearFocus() end
  else
    rc.error:SetText(GC.L["This sale could not be matched to its stock."])
  end
  H.render()
end
UIR.Save = save

--- Builds the tab's one receipt under `parent` (the list's scroll child), hidden. `H` is the
--- Sold tab's own drawing helpers and its render/close.
function UIR.Create(parent, H)
  local T = GC.Theme
  local rc = { pool = {}, dashes = {}, dashesUsed = 0 }
  rc.frame = CreateFrame("Frame", nil, parent)
  -- Clicks inside the receipt stay in it: they do not reach the row and close it.
  rc.frame:EnableMouse(true)
  rc.frame:Hide()

  rc.well = T.Card(rc.frame, T.color.bg, GC.Kit.Tokens.ink(0.14), true)
  local input = CreateFrame("EditBox", nil, rc.well)
  input:SetAutoFocus(false)
  input:SetPoint("TOPLEFT", 8, -2)
  input:SetPoint("BOTTOMRIGHT", -8, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if input.SetFont then
    input:SetFont(T.FONT_UI, 11 * T.Scale(), "")
    input:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3], 1)
    if T.OnRescale then T.OnRescale(function(scale) input:SetFont(T.FONT_UI, 11 * scale, "") end) end
  end
  rc.input = input
  rc.preview = T.Num(rc.frame, 10)
  rc.preview:SetJustifyH("LEFT")
  H.setColor(rc.preview, T.color.fgDim)
  rc.error = T.Num(rc.frame, 10)
  rc.error:SetJustifyH("LEFT")
  H.setColor(rc.error, T.color.red)
  rc.save = T.Button(rc.frame, "primary", "badge")
  if rc.save.SetGlow then rc.save:SetGlow(false) end
  rc.save:SetScript("OnClick", function() save(rc, H) end)
  rc.bags = T.Button(rc.frame, "ghost", "plaque")
  rc.bags:SetScript("OnClick", function()
    -- SELL on that item, and nothing more: posting stays the player's own click there.
    local name = rc.sale and rc.sale.name
    if GC.Sniper and GC.Sniper.ShowView then GC.Sniper.ShowView("sell") end
    if GC.Sell and GC.Sell.FocusItem then GC.Sell.FocusItem(name) end
  end)

  -- What the typed text records, live, in the full form: "2.5" reads 2g 50s before it is saved.
  input:SetScript("OnTextChanged", function(box, byUser)
    if not byUser then return end
    local copper = GC.SoldReceipt.ParseMoney(box:GetText())
    rc.preview:SetText(copper and H.plain(copper, true) or "")
    rc.error:SetText("")
    H.render()
  end)
  input:SetScript("OnEnterPressed", function() save(rc, H) end)
  input:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
    H.close()
  end)

  -- Escape closes the receipt, never the whole window: the window's own Escape is what the next
  -- press reaches -- the SELL inspector's rule (UI/Sell/Inspector.lua). Only Escape is kept from
  -- going on, per keystroke, and the keys go on again a frame later. In combat it stands down:
  -- SetPropagateKeyboardInput is restricted there.
  local f = rc.frame
  local function passKeys(on)
    if f.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
      f:SetPropagateKeyboardInput(on)
    end
  end
  if f.EnableKeyboard then f:EnableKeyboard(true) end
  -- Keys go on by default, so movement keys still work with a receipt open, in combat too: only an
  -- Escape out of combat is kept.
  passKeys(true)
  f:SetScript("OnKeyDown", function(_, key)
    if InCombatLockdown and InCombatLockdown() then return end
    if key ~= "ESCAPE" then passKeys(true) return end
    passKeys(false)
    H.close()
    if C_Timer and C_Timer.After then C_Timer.After(0, function() passKeys(true) end) end
  end)
  return rc
end
