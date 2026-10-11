-- Set cost: what a player paid for units GoldCap has no receipt for, typed in gold and recorded in
-- copper, and the purchase lines in the inspector (WHAT YOU PAID) whose hand-entered costs it can
-- take back. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local Theme = GC.Theme
local Post = GC.SellPost
local exact, safeMultiply, activeScope = GC.SellUtil.exact, GC.SellUtil.safeMultiply, GC.SellUtil.activeScope
local UI = GC.SellUI
local CostDialog = UI.CostDialog
local setColor, formatCell = UI.fmt.setColor, UI.fmt.cell
local dialogGoldPositive, copperToGoldText = UI.fmt.goldPositive, UI.fmt.goldText
local manualRepairNonce = 0

local function setDialogError(dialog, text)
  dialog.error:SetText(text or "")
  if text and text ~= "" then dialog.error:Show() else dialog.error:Hide() end
end

local function dialogNumber(edit)
  local value = tonumber(edit:GetText())
  return value and value == math.floor(value) and value or nil
end

local function dialogExactPositive(edit)
  local value = dialogNumber(edit)
  return exact(value) and value > 0 and value or nil
end

-- The live "what this will actually record" readout under the Total field. Typing "12.5" is
-- ambiguous on its own -- seeing "12g 50s 0c" appear while typing is what makes the unit
-- unambiguous no matter what the player assumed it was.
local function updateTotalPreview(dialog, copper)
  local preview = dialog.totalPreview
  if not preview then return end
  preview:SetText(exact(copper) and copper > 0 and GC.Util.CoinText(copper) or "")
end

local function pendingRepairFor(position, scope)
  local pending = position and position.pendingAcquisitions
  if type(pending) ~= "table" or #pending ~= 1 or type(scope) ~= "table" then return nil end
  local row = pending[1]
  if type(row) ~= "table" or type(row.id) ~= "string" or row.id == ""
      or row.itemID ~= position.itemID or row.positionKey ~= position.positionKey
      or row.character ~= scope.char or row.region ~= scope.region
      or not exact(row.quantity) or row.quantity <= 0 then
    return nil
  end
  return row
end

-- How many units the player is holding that GoldCap cannot put a cost against.
--
-- This used to be `exposureQty - knownQty`, and exposureQty counts tracked
-- purchases and live listings -- it knows nothing about the bags. For anything
-- GoldCap never bought that difference is zero, so Set cost returned before it
-- showed the dialog and the button was simply dead. Bag stock is exactly the
-- case the tab now exists to serve, and it is also the case most likely to need
-- a cost typed in by hand.
--
-- Held = what is listed plus what is in the bags, or the accounting exposure,
-- whichever is larger. The two disagree while an observation lags, and the
-- larger is the safe one here: offering to cost a unit that turns out not to
-- exist is a correctable mistake, refusing to cost one that does is the bug.
--
-- knownQty is FIFO allocation against exposureQty, and exposureQty is capped
-- at listedQty once a lot is listed (decoratePosition, SellPositions.lua) --
-- so allocation can stop well short of what is actually on record. trackedQty
-- is the sum of every batch's remainingQty regardless of that cap, so a unit
-- a recorded batch covers but allocation hasn't reached yet is costed even
-- when knownQty says otherwise. Comparing against max(knownQty, trackedQty)
-- reads what is recorded, not just what allocation reached: a live incident
-- had 24 listed capping allocation at 24 while a batch actually covered 118,
-- and the dialog offering to cost the "difference" let the player double it.
local function uncostedQty(position)
  if type(position) ~= "table" then return 0 end
  local physical = (position.listedQty or 0) + (position.bagQty or 0)
  local held = math.max(position.exposureQty or 0, physical)
  return math.max(0, held - math.max(position.knownQty or 0, position.trackedQty or 0))
end

local function canSetCost(position)
  if not position or position.unresolved or type(position.positionKey) ~= "string" then return false end
  -- Not offered where it would do nothing. A button that opens no dialog is
  -- indistinguishable from a broken one, which is how this defect presented.
  if uncostedQty(position) < 1 then return false end
  local pending = position.pendingAcquisitions
  if type(pending) ~= "table" or #pending == 0 then return true end
  local scope = activeScope(position)
  return pendingRepairFor(position, scope) ~= nil
end
CostDialog.CanSetCost = canSetCost

local function openCostDialog(position)
  local dialog = UI.container.costDialog
  local missing = uncostedQty(position)
  if missing < 1 then return end
  local scope = activeScope(position)
  local pending = pendingRepairFor(position, scope)
  if type(position.pendingAcquisitions) == "table" and #position.pendingAcquisitions > 0 and not pending then return end
  if pending then missing = math.min(missing, pending.quantity) end
  dialog.position, dialog.maximum, dialog.pendingRepair = position, missing, pending
  manualRepairNonce = manualRepairNonce + 1
  dialog.repairID = pending and table.concat({ "manual-repair", pending.id, tostring(time()),
    tostring(manualRepairNonce) }, "\1") or nil
  dialog.submitted, dialog.costMode, dialog.syncing = false, nil, false
  -- Which item, and how many of its units have no cost -- the two facts a player needs
  -- before touching any of the numbers below. The dialog used to be anonymous: nothing on
  -- it said which of several open positions it belonged to.
  dialog.header:SetText((GC.L["%s: %d unit%s without a cost"]):format(
    position.itemName or GC.L["Item"], missing, missing == 1 and "" or "s"))
  -- Defaults to the full uncosted count, not "1" -- entering a cost for stock GoldCap never
  -- saw the player buy is the ordinary case this dialog exists for, and "1" made the player
  -- retype the real quantity every single time.
  dialog.quantity:SetText(tostring(missing))
  dialog.unit:SetText("")
  dialog.total:SetText("")
  updateTotalPreview(dialog, nil)
  setDialogError(dialog)
  dialog:Show()
end
CostDialog.OpenCostDialog = openCostDialog

local function confirmCostDialog(dialog)
  if dialog.submitted then return end
  -- Quantity is a whole unit count; Unit/Total are gold, converted to exact copper here --
  -- the same conversion the live preview already showed, so what gets recorded is never a
  -- surprise. Everything from here down is copper, exactly as it always was.
  local quantity, total = dialogExactPositive(dialog.quantity), dialogGoldPositive(dialog.total)
  if not quantity or quantity < 1 then return setDialogError(dialog, GC.L["Enter a whole quantity"]) end
  if quantity > dialog.maximum then return setDialogError(dialog, GC.L["Quantity exceeds missing units"]) end
  if not total then return setDialogError(dialog, GC.L["Enter an exact positive cost"]) end
  if dialog.costMode == "unit" then
    local unit = dialogGoldPositive(dialog.unit)
    if not unit or safeMultiply(quantity, unit) ~= total then
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
    end
  elseif dialog.costMode ~= "total" then
    return setDialogError(dialog, GC.L["Enter an exact positive cost"])
  end
  local position = dialog.position
  local scope = activeScope(position)
  if not scope then return setDialogError(dialog, GC.L["Position scope changed"]) end
  local batch
  if dialog.pendingRepair then
    local pending = pendingRepairFor(position, scope)
    if not pending or pending.id ~= dialog.pendingRepair.id or not dialog.repairID
        or not (GC.Acquisitions and GC.Acquisitions.RepairPendingManual) then
      return setDialogError(dialog, GC.L["Position scope changed"])
    end
    batch = GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = dialog.repairID,
      itemID = position.itemID, positionKey = position.positionKey, itemName = position.itemName,
      quantity = quantity, total = total, acquiredAt = time(), character = scope.char, region = scope.region })
  else
    batch = GC.Acquisitions.RecordManual({ itemID = position.itemID, positionKey = position.positionKey,
      itemName = position.itemName, quantity = quantity, total = total, acquiredAt = time(),
      character = scope.char, region = scope.region })
  end
  if batch then dialog.submitted = true; dialog:Hide(); GC.Sell.Refresh() else setDialogError(dialog, GC.L["Enter an exact positive cost"]) end
end

-- A purchase line in the inspector's WHAT YOU PAID: how many, what each cost, where from and when,
-- and Remove on a cost typed in by hand.
function CostDialog.PaintBatch(row, entry)
  -- Was "goldcap · at 1786831966 · 5 original / 2 left / 2 FIFO · unit 100 · captured".
  -- A raw epoch and the allocator's internal counters are not facts a seller can use; how
  -- many, when, at what price and from where are.
  local function acquiredWhen(at)
    if type(at) == "number" and _G.date then
      local ok, formatted = pcall(_G.date, "%d %b", at)
      if ok and type(formatted) == "string" then return formatted end
    elseif at ~= nil then
      return tostring(at)
    end
    return "?"
  end
  -- A collapsed run (SellViewModel.Expansion merges adjacent same-price purchases) shows
  -- its date range and how many buys it stands for; a lone purchase reads as before.
  -- The count follows the quantity directly: this cell ellipsizes from the tail at
  -- narrow widths, and the count is the one fact the collapse exists to surface. The
  -- range separator is an ASCII hyphen -- the client font is missing glyphs as common
  -- as U+2192 (it drew a tofu box), so only in-game-proven punctuation goes on screen.
  local purchases = entry.batch.purchases
  local when
  if purchases and purchases > 1 then
    local first = acquiredWhen(entry.batch.acquiredAtFirst)
    local last = acquiredWhen(entry.batch.acquiredAtLast)
    when = first == last and first or (first .. " - " .. last)
  else
    when = acquiredWhen(entry.batch.acquiredAt)
  end
  local sourceLabel = ({ goldcap = "GoldCap", auction_house = "Auction House",
    goldcap_buy = GC.L["Buy run"], vendor = GC.L["Vendor"], manual = "entered by hand" })[entry.batch.source]
    or (entry.batch.source or "manual")
  -- The evidence word stays: it is how the player knows whether that cost is a confirmed
  -- invoice or a guess, which is exactly the thing this whole tab refuses to fake. The
  -- unit price no longer repeats here -- the COST/LISTED cells two columns over already
  -- carry the unit and total, and this line was the one place on the row saying the same
  -- number twice.
  -- Pooled rows keep whatever colour the last kind painted: a dim detail line must not
  -- bleed into the next render's batch text.
  setColor(row.subItem, Theme.color.fg)
  if entry.batch.source == "craft" then
    -- A craft was not bought, and calling it a purchase is exactly the kind of small
    -- untruth this tab exists not to tell. The verb already says where the units came
    -- from, so the source word would only say it twice. The count is crafting RUNS, not
    -- crafts: one Create All press settles as one batch however many times it fired.
    row.subItem:SetText((GC.L["×%d%s · made %s · %s"]):format(
      entry.batch.originalQty or entry.batch.quantity or 0,
      purchases and purchases > 1 and (" · %d crafting runs"):format(purchases) or "",
      when, entry.batch.evidence or GC.L["unknown evidence"]))
  else
    row.subItem:SetText((GC.L["×%d%s · bought %s · %s · %s"]):format(
      entry.batch.originalQty or entry.batch.quantity or 0,
      purchases and purchases > 1 and (" · %d purchases"):format(purchases) or "",
      when, sourceLabel, entry.batch.evidence or GC.L["unknown evidence"]))
  end
  row.cells.cost:SetText(formatCell(entry.batch.unitCost)); row.cells.listed:SetText(formatCell(entry.batch.totalCost)); row.cells.market:SetText("")
  row.cells.profit:SetText("")
  row.cells.status:SetText((entry.batch.remainingQty or 0) > 0
    and ("%d still unsold"):format(entry.batch.remainingQty) or "all sold")
  setColor(row.cells.status, Theme.color.fgDim)
  -- Four columns in the panel, the way a ledger reads: how many, what each cost, where
  -- from and when, and how far that cost can be trusted. The sentence above is still
  -- what gets translated -- and, whole, what the row's hover says, with how many of the
  -- run are purchases and how many are still unsold; the columns are its facts set out
  -- so that two purchases can be compared down the panel instead of read one by one.
  row.groupHint = (row.subItem:GetText() or "") .. " · " .. (row.cells.status:GetText() or "")
  row.subItem:SetText(("×%d"):format(entry.batch.originalQty or entry.batch.quantity or 0))
  setColor(row.cells.cost, Theme.color.cost or Theme.color.goldHi or Theme.color.gold)
  -- The evidence word is drawn only when it is news. A purchase matched to the mail's
  -- invoice and a craft captured as it happened are the ordinary cases, and saying so on
  -- every line took the room the source and date needed -- "GoldCap,..." (seen in game).
  -- When the evidence IS worth a look, it gets the room and the source steps back to the
  -- hover, which carries the whole sentence either way.
  local craft = entry.batch.source == "craft"
  local evidence = entry.batch.evidence or GC.L["unknown evidence"]
  local ordinary = evidence == (craft and "captured" or "mail-confirmed")
  if craft then
    -- "crafted", not "made": the batch is known to be a craft (its source says so), and
    -- the word a player uses for it is the one that tells them GoldCap knows too.
    row.itemStock:SetText((GC.L["crafted %s"]):format(when))
  else
    row.itemStock:SetText(ordinary and (sourceLabel .. ", " .. when) or when)
  end
  row.sectionHint:SetText(ordinary and "" or evidence)
  row.sectionHint:Show()
  -- Only a hand-entered cost gets a removal affordance -- goldcap and auction_house
  -- batches are evidence-backed, and Core/Acquisitions' own RemoveManual already refuses
  -- them, but the button should never even offer the click. entry.batch.source is the one
  -- source every id in `ids` shares (Expansion's own collapse key), so this single check
  -- covers a lone purchase and a collapsed run alike -- and a mixed run cannot occur here.
  if entry.batch.source == "manual" and type(entry.batch.ids) == "table" and #entry.batch.ids > 0 then
    UI.Row.ShowRowAction(row, "Remove", function() Post.Remove(row) end)
  else
    row.action:Hide()
  end
end

-- The Set cost dialog: one frame, filled by openCostDialog for whichever position it opens on.
function CostDialog.Build()
  local container = UI.container
  local dialog = CreateFrame("Frame", nil, container, "BackdropTemplate"); dialog:SetSize(270, 170); dialog:SetPoint("CENTER"); dialog:Hide(); container.costDialog = dialog
  -- The template was carried but never given a backdrop, a strata or a frame level, so this
  -- opened as bare floating widgets: the rows underneath showed straight through it, its own
  -- error text collided with them, and clicks aimed at the dialog landed on whatever row sat
  -- behind. Give it a real surface, lift it above the list, and let it swallow its own mouse.
  dialog:SetFrameStrata("DIALOG")
  dialog:SetFrameLevel((container:GetFrameLevel() or 0) + 50)
  dialog:EnableMouse(true)
  -- Rounded kit surface. card.png margin 24 <= 85 = half of the 170px edge. Regions on the
  -- dialog frame itself, not a child Card frame: a child frame would draw over the dialog's
  -- own FontStrings.
  local pc = Theme.color.panel
  local dialogBG = Theme.SlicedTexture(dialog, "BACKGROUND", Theme.MEDIA .. "card.png", { pc[1], pc[2], pc[3], 0.98 }, 24)
  dialogBG:SetAllPoints(dialog)
  local gc2 = Theme.color.gold
  local dialogEdge = Theme.SlicedTexture(dialog, "BORDER", Theme.MEDIA .. "ring.png", { gc2[1], gc2[2], gc2[3], 0.5 }, 24)
  dialogEdge:SetAllPoints(dialog)
  -- Which item, and how many units it is missing a cost for -- filled in by openCostDialog
  -- every time it opens, since the dialog is pooled across positions. Reserves two lines'
  -- worth of height: item names run long enough that one line is not always enough.
  dialog.header = Theme.Label(dialog, 11)
  dialog.header:SetPoint("TOPLEFT", 12, -10)
  dialog.header:SetPoint("TOPRIGHT", -12, -10)
  dialog.header:SetWordWrap(true)
  setColor(dialog.header, Theme.color.fg)
  dialog.quantity, dialog.unit, dialog.total = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  -- Pushed down FIELD_LABEL_Y/FIELD_BOX_Y (was -12/-26) to leave room for the header above.
  -- Unit/Total are labelled "(gold)" -- explicitly, because the fields used to carry no unit
  -- at all and every amount typed here was read as bare copper.
  local FIELD_LABEL_Y, FIELD_BOX_Y = -40, -54
  for i, field in ipairs({ { dialog.quantity, "Quantity" }, { dialog.unit, "Unit cost (gold)" }, { dialog.total, "Total cost (gold)" } }) do
    local label = Theme.Label(dialog, 10); label:SetPoint("TOPLEFT", 12 + (i - 1) * 82, FIELD_LABEL_Y); label:SetText(field[2])
    field[1]:SetSize(70, 20); field[1]:SetPoint("TOPLEFT", 12 + (i - 1) * 82, FIELD_BOX_Y); field[1]:SetAutoFocus(false)
  end
  -- Live coin readout of exactly what Total will record, under the Total field itself. This
  -- is what makes the unit unambiguous no matter what the player assumed it was.
  dialog.totalPreview = Theme.Label(dialog, 10)
  dialog.totalPreview:SetPoint("TOPLEFT", 12 + 2 * 82, FIELD_BOX_Y - 24)
  dialog.totalPreview:SetPoint("TOPRIGHT", -12, FIELD_BOX_Y - 24)
  setColor(dialog.totalPreview, Theme.color.fgDim)
  dialog.error = Theme.Label(dialog, 10); dialog.error:SetPoint("TOPLEFT", 12, FIELD_BOX_Y - 44); setColor(dialog.error, Theme.color.red)
  local cancel = Theme.Button(dialog, "ghost", "badge"); cancel:SetSize(70, 20); cancel:SetPoint("BOTTOMLEFT", 12, 10); cancel:SetLabel(GC.L["Cancel"]); cancel:SetScript("OnClick", function() dialog:Hide() end)
  local confirm = Theme.Button(dialog, "primary", "badge"); confirm:SetSize(70, 20); confirm:SetPoint("BOTTOMRIGHT", -12, 10); confirm:SetLabel(GC.L["Confirm"]); confirm:SetScript("OnClick", function() confirmCostDialog(dialog) end)
  -- Primary without the halo: the dock's POST and CANCEL are the only things on the tab that glow.
  if confirm.SetGlow then confirm:SetGlow(false) end
  local function syncText(edit, text)
    dialog.syncing = true
    edit:SetText(text)
    dialog.syncing = false
  end
  -- All three handlers read/write GOLD text now (dialogGoldPositive / copperToGoldText), but
  -- do every comparison and every downstream write in COPPER -- the sync must stay exact in
  -- the unit RecordManual/RepairPendingManual actually store, not in the decimal the player
  -- is typing, or rounding in one direction and not the other would drift the two fields
  -- apart from what Confirm's own validation checks.
  dialog.unit:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    dialog.costMode = "unit"
    local q, unitCopper = dialogExactPositive(dialog.quantity), dialogGoldPositive(dialog.unit)
    if not q or not unitCopper then
      syncText(dialog.total, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
    end
    local totalCopper = safeMultiply(q, unitCopper)
    if not totalCopper then
      syncText(dialog.total, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
    end
    setDialogError(dialog)
    syncText(dialog.total, copperToGoldText(totalCopper))
    updateTotalPreview(dialog, totalCopper)
  end)
  dialog.quantity:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    local quantity = dialogExactPositive(dialog.quantity)
    if not quantity then
      if dialog.costMode == "unit" then syncText(dialog.total, "")
      elseif dialog.costMode == "total" then syncText(dialog.unit, "")
      else syncText(dialog.unit, ""); syncText(dialog.total, "") end
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, GC.L["Enter a whole quantity"])
    end
    if dialog.maximum then
      local clamped = math.max(1, math.min(dialog.maximum, quantity))
      if clamped ~= quantity then syncText(dialog.quantity, tostring(clamped)); quantity = clamped end
    end
    if dialog.costMode == "unit" then
      local unitCopper = dialogGoldPositive(dialog.unit)
      local totalCopper = unitCopper and safeMultiply(quantity, unitCopper)
      if not totalCopper then
        syncText(dialog.total, "")
        updateTotalPreview(dialog, nil)
        return setDialogError(dialog, GC.L["Enter an exact positive cost"])
      end
      syncText(dialog.total, copperToGoldText(totalCopper))
      updateTotalPreview(dialog, totalCopper)
      setDialogError(dialog)
    elseif dialog.costMode == "total" then
      local totalCopper = dialogGoldPositive(dialog.total)
      if not totalCopper then
        syncText(dialog.unit, "")
        updateTotalPreview(dialog, nil)
        return setDialogError(dialog, GC.L["Enter an exact positive cost"])
      end
      syncText(dialog.unit, copperToGoldText(math.floor(totalCopper / quantity)))
      updateTotalPreview(dialog, totalCopper)
      setDialogError(dialog)
    end
  end)
  dialog.total:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    dialog.costMode = "total"
    local q, totalCopper = dialogExactPositive(dialog.quantity), dialogGoldPositive(dialog.total)
    if not q or not totalCopper then
      syncText(dialog.unit, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
    end
    syncText(dialog.unit, copperToGoldText(math.floor(totalCopper / q)))
    updateTotalPreview(dialog, totalCopper)
    setDialogError(dialog)
  end)
end
