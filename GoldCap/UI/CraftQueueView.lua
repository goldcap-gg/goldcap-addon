local _, GC = ...

-- The craft panel's Queue view (retail, beside the profession window), as the owner approved it
-- (canvas version 17, 2026-10-26). In one scroll:
-- - a line per queued recipe: the icon of what it makes with its crafting quality, its name, what
--   is left ("5 to craft. Reagents for 3 now", "Restock to 40: you hold 20, 4 crafts"), a bar of how
--   far it is (crafts made of those asked for in gold, a restock's held of its target in blue) and
--   its Craft button, which crafts what the reagents allow of what is left in one press (newLine).
--   Dimmed, the line says why under its bar. While the client crafts a queued recipe (a run of
--   them, from this button or Blizzard's own), that line is busy: gold, "Crafting", what the run
--   has made and has left; while it crafts any recipe, every other line's Craft waits. A click on
--   a line opens its recipe in Blizzard's window, a right click offers the queue. A craft from
--   Blizzard's own button takes one off a counted line all the same (UNIT_SPELLCAST_SUCCEEDED);
-- - Missing: what the reagents the queue is short of cost to buy, a cell per reagent with what is
--   still to get into the bags, what of it waits in the mailbox and what the rest costs; a currency
--   named as not sold on the auction house; and Make a BUY list, which writes what the queue needs
--   into the character's one Craft queue list for the BUY tab at the auction house. Nothing is
--   bought here.
--
-- That list follows the queue: every change to the queue, and to what a restock holds, rewrites
-- its lines (SyncBuyList), so BUY never buys again what a craft already used. It is known by the
-- code GC.db.craft keeps for the character, never by its name: the player's other lists, one
-- named Craft queue included, are never touched, and one the player deleted is made again only
-- by the button.
--
-- Its events are its own, each registered under pcall (Core/Collection.lua's shape), so
-- Core/Init.lua is not touched. The arithmetic is Core/CraftQueue.lua's; every count and price
-- comes through Services/CraftClient.lua. Item icons, the bar and the lines are drawn with the
-- GoldCap Hoard's and the panel's helpers (UI/HoardRow.lua's icon, UI/Kit/Bar.lua, HF.ui,
-- UI/CraftPanel.lua's P.ui), and every line it draws is drawn again whenever it shows again
-- (docs/addon/AGENTS.md "Text").
GC.CraftQueueView = GC.CraftQueueView or {}
local QV = GC.CraftQueueView
local HF = GC.HoardFrame
local U = HF.ui
local K = GC.Kit.Tokens.color
local setText, colour, wrapping, heightOf, track, restamp = U.setText, U.colour, U.wrapping, U.heightOf, U.track,
  U.restamp

-- In UI units; the approved board is drawn at twice that. A line: PAD its margin, ICON its item,
-- COL_GAP between its columns, BLOCK_GAP between its top, its bar and its notes, LINE_GAP between
-- lines of text; CRAFT_H and CRAFT_MIN its Craft button, BAR_H its bar; LINE_SPACE between lines.
-- GAP between the lines and Missing. Missing: M_PAD its margin, M_GAP between its parts, CELL_GAP
-- between its cells, CELL_PAD a cell's margin, CELL_ICON its item; MAIL the mailbox glyph, MAIL_GAP
-- right of it, MAIL_Y down from its line's top, level with the letters; BUTTON_H Make a BUY list.
-- BAR: the scroll's bar right of them all. The rest are font sizes.
local LAYOUT = {
  PAD = 6, ICON = 24, COL_GAP = 6, BLOCK_GAP = 5, LINE_GAP = 2, CRAFT_H = 21, CRAFT_MIN = 56, BAR_H = 4,
  LINE_SPACE = 4, GAP = 8,
  M_PAD = 7, M_GAP = 6, CELL_GAP = 4, CELL_PAD = 4, CELL_ICON = 22, MAIL = 8, MAIL_GAP = 3, MAIL_Y = 1,
  BUTTON_H = 24, BAR = 16,
  NAME = 11, SMALL = 9, KICKER = 9, NOTE = 10, CELL_NAME = 10,
}
-- Where a cell's words start: right of its icon.
local CELL_TEXT_X = LAYOUT.CELL_PAD + LAYOUT.CELL_ICON + LAYOUT.COL_GAP

-- The board's colours, from the kit's tokens: a line on the glass in its faint edge, the busy one in
-- the gold This recipe wears; Crafting ringed in gold; a dimmed Craft in a faint white outline,
-- drawn at the kit's disabled share of it (0.45: the board's 0.12); Missing's cells on the window's
-- dark.
local BUSY_FILL = { K.gold[1], K.gold[2], K.gold[3], 0.07 }
local BUSY_RING = { K.gold[1], K.gold[2], K.gold[3], 0.6 }
local GOLD_RING = { K.gold[1], K.gold[2], K.gold[3], 0.5 }
local DIM_RING = { 1, 1, 1, 0.27 }
local CELL_FILL, NO_RING = { 0, 0, 0, 0.25 }, { 0, 0, 0, 0 }

-- How wide the view's content is: the panel's body less the scroll's bar.
local function contentWidth()
  return (GC.CraftPanel and GC.CraftPanel.BODY_W or 280) - LAYOUT.BAR
end

local function textWidth(fs) return GC.CraftPanel.ui.textWidth(fs) end

-- `fn` once `seconds` have passed (the next frame for 0), or now on a client without timers.
local function after(fn, seconds)
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds or 0, fn) else fn() end
end

-- How many of an item `char` holds, its mailbox included (Services/CraftClient.lua's CountOf), for
-- every count of one pass over the queue: the character is read once by the caller, not per item.
local function counter(char)
  local CC = GC.CraftClient
  return function(itemID) return CC.CountOf(itemID, char) end
end

-- What the queue needs that waits in the mailbox (Core/MailStock.lua, retail only), one row per
-- reagent ({ ids, n, itemID }, `ids` the need's own): held, so not missing, but Blizzard's Create
-- takes reagents from the bags and the banks alone. `n` is what the bags and the banks do not
-- cover of the need, `itemID` the quality the mailbox holds most of.
local function inMailbox(needs, char, countOf)
  local stock = GC.MailStock
  local out = {}
  if not stock then return out end
  for _, row in ipairs(needs) do
    local mail, held, itemID, most = 0, 0, nil, 0
    for _, id in ipairs(row.ids or {}) do
      local m = stock.Count(char, id)
      mail = mail + m
      held = held + countOf(id) - m
      if m > most then itemID, most = id, m end
    end
    local n = math.min(mail, row.q - held)
    if n > 0 then out[#out + 1] = { ids = row.ids, n = n, itemID = itemID } end
  end
  return out
end

-- The queue as it stands: one row per entry ({ entry, crafts, held }), what the queue is short
-- of, when the auction house was last read for this character (nil: not yet), what the queue
-- needs in all, and what of that waits in the mailbox.
local function work(char)
  local CC, Q = GC.CraftClient, GC.CraftQueue
  local countOf = counter(char)
  local entries = Q.Entries(char)
  local listed, listedAt = Q.Listed(char, time())
  local rows, crafts = {}, {}
  for i, e in ipairs(entries) do
    local held = e.restock and Q.Held(e, countOf, listed) or nil
    local n = Q.CraftsNeeded(e, held or 0)
    crafts[e] = n
    rows[i] = { entry = e, crafts = n, held = held }
  end
  local needs = Q.Needs(entries, function(e) return crafts[e] end)
  return rows, Q.Missing(needs, countOf, CC.CurrencyCount), listedAt, needs, inMailbox(needs, char, countOf)
end

--- What `char`'s queue needs in all (Core/CraftQueue.lua's Needs), over what each entry has left
--- to craft as this view counts it, and how many crafts that is. The GoldCap Hoard's For your
--- crafts tile (UI/HoardTiles.lua) asks it and counts the bags alone against it.
function QV.Needs(char)
  local rows, _, _, needs = work(char)
  local crafts = 0
  for _, row in ipairs(rows) do crafts = crafts + row.crafts end
  return needs, crafts
end

-- Whether the queue is short of anything the BUY tab can buy (a currency it cannot).
local function buyable(missing)
  for _, row in ipairs(missing) do
    if type(row.ids) == "table" and row.ids[1] then return true end
  end
  return false
end

-- The character's craft queue list, while the store may be written and the list is still there.
local function listOf(char)
  local Q = GC.CraftQueue
  local code = char and Q.Writable() and Q.BuyList(char) or nil
  local run = code and GC.AppRuns.Get(code) or nil
  return (type(run) == "table" and run.origin == "game") and run or nil
end

-- Writes what the queue needs into the character's craft queue list, making it when the
-- character has none (named "Craft queue: <character>"). Returns the list and whether its lines changed, or
-- nil when nothing may be written.
local function writeList(char, needs)
  local CC, Q = GC.CraftClient, GC.CraftQueue
  local lines = Q.BuyLines(needs, CC.UnitOf, counter(char), CC.VendorOf)
  local run = listOf(char)
  if run then return GC.AppRuns.SetLines(run.code, lines) end
  if not (char and Q.Writable()) then return nil end
  -- Lists are account wide: the character's name keeps two characters' queues apart in BUY.
  run = GC.AppRuns.NewList(GC.L["Craft queue"] .. ": " .. (char:match("^([^%-]+)") or char), lines)
  if not (run and Q.SetBuyList(char, run.code)) then return nil end
  return run, true
end

--- The queue changed, or what it holds did: its list, when the character has one, says what the
--- queue needs now. Only the button makes one. BUY rebuilds a list whose updatedAt moved the next
--- time it shows (UI/BuyFrame.lua's ensureRun); the one it holds now is rebuilt here, so what it
--- counts as bought is read afresh, unless a purchase is in the client's hands. Returns the list
--- or nil.
function QV.SyncBuyList()
  local char = GC.CraftClient.Char()
  if not listOf(char) then return nil end
  local _, _, _, needs = work(char)
  local run, changed = writeList(char, needs)
  local buy = GC.Buy
  local shown = changed and buy and buy.CurrentRun and buy.CurrentRun() or nil
  if shown and shown:Code() == run.code and not (buy._InFlight and buy._InFlight()) then
    buy.SelectRun(run.code)
    if buy.RefreshIfShown then buy.RefreshIfShown() end
  end
  return run
end

-- The panel's top counts the queue's lines and says how it holds the open recipe
-- (UI/CraftPanel.lua): drawn again after this view changed the queue or what a restock holds.
local function panelChanged()
  local P = GC.CraftPanel
  if P and P.QueueOpen then P.QueueOpen() end
end

--- A queue line's right click: more crafts, a restock target, or off the queue.
function QV.OpenLineMenu(owner, entry)
  local menu = _G.MenuUtil
  if not (type(menu) == "table" and menu.CreateContextMenu and type(entry) == "table" and GC.CraftQueue.Writable()) then
    return false
  end
  local recipe = entry.recipe
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(GC.Util.ClientText(recipe.name))
    root:CreateButton(GC.Util.ClientText(GC.L["Add to queue"]), function() GC.CraftPanel.AskCount(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Restock to"]), function() GC.CraftPanel.AskRestock(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Remove from queue"]), function()
      local char = GC.CraftClient.Char()
      if char then GC.CraftQueue.Remove(char, recipe.recipeID) end
      QV.SyncBuyList()
      QV.Queue()
      panelChanged()
    end)
  end)
  return true
end

-- ---------------------------------------------------------------------------------------------
-- A running craft
-- ---------------------------------------------------------------------------------------------

-- What the client is crafting (CraftClient.Repeating, which counts the run whether or not this view
-- is on screen, and takes a press of Craft for crafting until the client begins it): { running =
-- recipeID, name, left, count }, the casts left (this one included) and the run's length, with
-- `busy` the same recipe when it is queued. An empty table when nothing is.
local function runOf(rows)
  local CC = GC.CraftClient
  local id, left, count = CC.Repeating()
  if not id then return {} end
  for _, row in ipairs(rows) do
    local recipe = row.entry.recipe
    if recipe.recipeID == id then return { running = id, busy = id, name = recipe.name, left = left, count = count } end
  end
  return { running = id, name = CC.RecipeName(id), left = left, count = count }
end

-- ---------------------------------------------------------------------------------------------
-- A line
-- ---------------------------------------------------------------------------------------------

-- What the Craft button's tooltip says: what a press does, or why it cannot.
local function craftTooltip(line)
  local tip = _G.GameTooltip
  if not tip then return end
  tip:SetOwner(line.craft, "ANCHOR_RIGHT")
  local text = line.craftWhy
    or GC.L["Crafts %d now, one after another, with the reagents the profession window would use. Moving stops it."]:format(line.craftCount or 0)
  tip:SetText(GC.Util.ClientText(text), 1, 1, 1, 1, true)
  tip:Show()
end

local function wrapped(owner, parent, size, c)
  local fs = track(owner, wrapping(GC.Theme.Label(parent, size)))
  if c then colour(fs, c) end
  return fs
end

-- A card on the glass in its faint edge, with the engine's gold wash under the cursor (HF.ui.plate),
-- as a Worth crafting row is: the item, the name over what is left, Craft at the right; under them
-- the bar with its figures; under that the notes.
local function newLine(v)
  local T = GC.Theme
  local frame = U.plate(v.content, K.glassBorder, "plaque")
  frame:SetWidth(contentWidth())
  frame.fill = T.SlicedTexture(frame, "BACKGROUND", T.MEDIA .. "plaque.png", K.glassTop, T.SLICE.plaque)
  frame.fill:SetAllPoints()
  local line = { frame = frame }
  line.slot = HF.Row.NewIcon(frame, LAYOUT.ICON)
  line.name = wrapped(line, frame, LAYOUT.NAME, K.text1)
  line.detail = wrapped(line, frame, LAYOUT.SMALL, K.text3)
  -- Craft: what the reagents allow of what is left, in one press. CraftRecipe with a count crafts
  -- that many one after another, and only from the player's own press: from a timer the client
  -- blocks it (probe A2 and A4, retail 12.1.5, 2026-10-26). So the press is the call, with nothing
  -- before it but reading what the line was painted with. After it, bookkeeping only: the line
  -- drops its count, so a second press before the next paint calls nothing, and CraftClient takes
  -- the recipe for crafting until the client begins it (CC.Started), so the line paints busy from
  -- the next frame and repaints when that hold lapses. Each finished cast takes one off the line
  -- (QV.OnEvent). The reagents are the ones Blizzard's own Create would use (an empty list, as the
  -- probe crafted with). A busy line's button and a dimmed one carry no count, so a press of them
  -- calls nothing. The press never disables the button: the busy look keeps it enabled.
  line.craft = T.Button(frame, "ghost", "badge")
  line.craft:SetGlow(false)
  line.craft:SetUppercase(true)
  line.craft:SetHeight(LAYOUT.CRAFT_H)
  line.craft:FitLabels({ GC.L["Craft %d"]:format(9999), GC.L["Crafting"] }, LAYOUT.CRAFT_MIN)
  line.craft:SetScript("OnClick", function()
    local e, n = line.entry, line.craftCount
    if not (e and n) then return end
    C_TradeSkillUI.CraftRecipe(e.recipe.recipeID, n, {}, nil, nil, false)
    line.craftCount = nil
    GC.CraftClient.Started(e.recipe.recipeID, n)
    QV.Queue()
    after(QV.Queue, GC.CraftClient.PENDING)
  end)
  -- A disabled button says why on hover: the client sends a disabled button no hover otherwise.
  if line.craft.SetMotionScriptsWhileDisabled then line.craft:SetMotionScriptsWhileDisabled(true) end
  line.craft:HookScript("OnEnter", function() craftTooltip(line) end)
  line.craft:HookScript("OnLeave", U.hideTip)
  track(line, line.craft.text)
  line.bar = T.Bar(frame, LAYOUT.BAR_H)
  line.count = track(line, T.Num(frame, LAYOUT.SMALL))
  line.count:SetWordWrap(false)
  colour(line.count, K.text3)
  line.note = wrapped(line, frame, LAYOUT.SMALL)
  line.listed = wrapped(line, frame, LAYOUT.SMALL, K.text4)
  -- A click opens the line's recipe in Blizzard's window, called from the click itself as
  -- Blizzard's recipe tracker does (CraftClient.Open); a right click offers the queue.
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnClick", function(self, button)
    local e = line.entry
    if not e then return end
    if button == "RightButton" then
      QV.OpenLineMenu(self, e)
    else
      GC.CraftClient.Open(e.recipe.recipeID)
    end
  end)
  return line
end

-- The line's Craft button, by its state:
-- - busy while the client crafts the line's recipe: "Crafting", ringed in gold, saying on hover that
--   it is being crafted;
-- - hidden with nothing left to craft;
-- - live with how many a press makes, the fewer of what is left and what the reagents allow;
-- - dimmed with what is left, saying why on hover: the window is on another profession or the
--   reagents do not make one (the reason the line says under its bar too), or the client is
--   crafting another recipe, queued or not (a press would reach it mid-cast).
-- Enabled before its variant is set and disabled after: a button already dim keeps its dim words.
-- Answers that reason, or nil, and how many the reagents allow.
local function paintCraft(line, row, ctx)
  local CC = GC.CraftClient
  local b = line.craft
  local recipeID = row.entry.recipe.recipeID
  local busyWhy = ctx.running and GC.L["Crafting %s now. Wait for it to finish."]:format(ctx.name)
  line.craftCount, line.craftWhy = nil, nil
  if recipeID == ctx.busy then
    line.craftWhy = busyWhy
    b:SetLabel(GC.L["Crafting"])
    b:Enable()
    b:SetVariant("active")
    b:SetRing(GOLD_RING)
    b:Show()
    return nil, 0
  end
  local left = row.crafts or 0
  if left <= 0 then
    b:Hide()
    return nil, 0
  end
  local here, where = CC.CraftableHere(recipeID)
  local n = here and math.min(left, CC.Craftable(recipeID)) or 0
  local reason
  if not here then
    reason = where and GC.L["Open %s to craft it here."]:format(where)
      or GC.L["Open this recipe's profession to craft it here."]
  elseif n <= 0 then
    reason = GC.L["Not enough reagents for one craft. Missing below says what to get."]
  end
  line.craftWhy = reason or busyWhy
  if not line.craftWhy then line.craftCount = n end
  local live = line.craftCount ~= nil
  b:SetLabel(GC.L["Craft %d"]:format(n > 0 and n or left))
  b:Enable()
  b:SetVariant(live and "primary" or "ghost")
  b:SetRing(not live and DIM_RING or nil)
  if not live then b:Disable() end
  b:Show()
  return reason, n
end

-- What the line says under its name: a busy line what this run has made and has left; a count what
-- is left, and what the reagents allow now (`allowed`) when that is fewer but some; a restock its
-- target, what is held and the crafts that bring it to the target.
local function detailText(row, ctx, allowed)
  local e = row.entry
  if e.recipe.recipeID == ctx.busy then
    return GC.L["%d crafted, %d to go"]:format(math.max(0, ctx.count - ctx.left), ctx.left)
  end
  if e.restock then
    if row.crafts == 1 then return GC.L["Restock to %d: you hold %d, 1 craft"]:format(e.restock, row.held or 0) end
    return GC.L["Restock to %d: you hold %d, %d crafts"]:format(e.restock, row.held or 0, row.crafts)
  end
  if allowed > 0 and allowed < e.count then return GC.L["%d to craft. Reagents for %d now"]:format(e.count, allowed) end
  return GC.L["%d to craft"]:format(e.count)
end

-- Under the bar, each across the card: why Craft is dimmed, in the board's amber, or the run a busy
-- line is making (when it is more than one craft); and for a restock, that what is up on the auction
-- house is not counted yet. A restock counts what is up there too, and that is read only there,
-- when something asks the auction house for the character's own auctions: in GoldCap, the Sell tab
-- (Services/Sell/Owned.lua). Until then, it says so rather than craft more than is needed without a
-- word.
local function paintNotes(line, row, ctx, reason)
  local note, tone = reason, K.warn
  if row.entry.recipe.recipeID == ctx.busy and ctx.count > 1 then
    note, tone = GC.L["Crafting %d one after another. Moving stops it."]:format(ctx.count), K.text2
  end
  if note then
    setText(line.note, note)
    colour(line.note, tone)
  end
  line.note:SetShown(note ~= nil)
  if row.entry.restock and ctx.listedAt == nil then
    setText(line.listed, GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"])
    line.listed:Show()
  else
    line.listed:Hide()
  end
end

-- One line, top to bottom: the item, the name over what is left and Craft, each centred on the top;
-- the bar across what its figures leave; the notes. Answers its height, as tall as its wrapped text.
local function paintLine(line, row, ctx)
  local e = row.entry
  local recipe, frame = e.recipe, line.frame
  line.entry = e
  local busy = recipe.recipeID == ctx.busy
  local fill, ring = busy and BUSY_FILL or K.glassTop, busy and BUSY_RING or K.glassBorder
  frame.fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
  frame.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
  HF.Row.PaintIcon(line.slot, recipe.output, GC.CraftClient.IconOf(recipe.output), nil, nil, { pip = true })
  setText(line.name, recipe.name)
  local reason, allowed = paintCraft(line, row, ctx)
  setText(line.detail, detailText(row, ctx, allowed))
  paintNotes(line, row, ctx, reason)

  local inner = contentWidth() - 2 * LAYOUT.PAD
  local craftW = line.craft:IsShown() and (line.craft:GetWidth() + LAYOUT.COL_GAP) or 0
  local textX = LAYOUT.PAD + LAYOUT.ICON + LAYOUT.COL_GAP
  local textW = inner - LAYOUT.ICON - LAYOUT.COL_GAP - craftW
  line.name:SetWidth(textW)
  line.detail:SetWidth(textW)
  local textH = heightOf(line.name, 14) + LAYOUT.LINE_GAP + heightOf(line.detail, 12)
  local topH = math.max(LAYOUT.ICON, LAYOUT.CRAFT_H, textH)
  local y = LAYOUT.PAD
  line.slot.edge:ClearAllPoints()
  line.slot.edge:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -(y + math.floor((topH - LAYOUT.ICON) / 2)))
  line.name:ClearAllPoints()
  line.name:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, -(y + math.floor((topH - textH) / 2)))
  line.detail:ClearAllPoints()
  line.detail:SetPoint("TOPLEFT", line.name, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  line.craft:ClearAllPoints()
  line.craft:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -LAYOUT.PAD, -(y + math.floor((topH - LAYOUT.CRAFT_H) / 2)))
  y = y + topH + LAYOUT.BLOCK_GAP

  local done, total = GC.CraftQueue.Progress(e, row.held)
  setText(line.count, ("%d / %d"):format(done, total))
  local countH = heightOf(line.count, 11)
  line.count:ClearAllPoints()
  line.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -LAYOUT.PAD, -y)
  line.bar:SetColor(e.restock and K.yours or K.gold)
  line.bar:SetWidth(math.max(1, inner - textWidth(line.count) - LAYOUT.BLOCK_GAP))
  line.bar:SetShare(total > 0 and done / total or 0)
  line.bar:ClearAllPoints()
  line.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -(y + math.floor((countH - LAYOUT.BAR_H) / 2)))
  y = y + countH

  local gap = LAYOUT.BLOCK_GAP
  for _, fs in ipairs({ line.note, line.listed }) do
    if fs:IsShown() then
      fs:SetWidth(inner)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -(y + gap))
      y = y + gap + heightOf(fs, 12)
      gap = LAYOUT.LINE_GAP
    end
  end
  local height = y + LAYOUT.PAD
  frame:SetHeight(height)
  return height
end

-- ---------------------------------------------------------------------------------------------
-- Missing
-- ---------------------------------------------------------------------------------------------

-- A cell on the window's dark: the reagent's icon with what the bags still need of it, its name,
-- what waits in the mailbox beside the kit's envelope, in the "yours" blue, and what the rest costs.
local function newCell(card)
  local T = GC.Theme
  local cell = T.Card(card, CELL_FILL, NO_RING, true)
  cell.slot = HF.Row.NewIcon(cell, LAYOUT.CELL_ICON, true)
  cell.name = wrapped(cell, cell, LAYOUT.CELL_NAME, K.text1)
  cell.mailIcon = cell:CreateTexture(nil, "OVERLAY")
  cell.mailIcon:SetSize(LAYOUT.MAIL, LAYOUT.MAIL)
  T.SetIcon(cell.mailIcon, "mail", K.yours)
  cell.mail = wrapped(cell, cell, LAYOUT.SMALL, K.yours)
  cell.price = wrapped(cell, cell, LAYOUT.SMALL, K.text3)
  return cell
end

-- One cell per reagent the bags and the banks are short of for the queue, in the order the queue
-- needs them: what is still to buy (Missing's row and its price, nil without one) and what waits in
-- the mailbox ({ itemID, buy, cost, mail }). The cell is the quality the BUY list buys (`items`,
-- Core/CraftQueue.lua's MissingCost), or, for a reagent only in the mailbox, the one there. A
-- currency is not a cell: it is not sold on the auction house, and a line under the cells says so.
local function cellsOf(needs, missing, costs, items, mailed)
  local buy, mail = {}, {}
  for k, row in ipairs(missing) do
    if row.ids then buy[row.ids] = { n = row.missing, cost = costs[k], itemID = items[k] } end
  end
  for _, row in ipairs(mailed) do mail[row.ids] = row end
  local cells = {}
  for _, need in ipairs(needs) do
    local ids = need.ids
    local b, m = ids and buy[ids], ids and mail[ids]
    if b or m then
      cells[#cells + 1] = { itemID = b and b.itemID or m.itemID or ids[1], buy = b and b.n or 0, cost = b and b.cost,
        mail = m and m.n or 0 }
    end
  end
  return cells
end

-- A cell `width` wide: its icon with its crafting quality and count, and its words wrapped right of
-- the icon, the mailbox's and the price's lines hung under the name. Answers how tall the words
-- stand.
local function paintCell(cell, data, width)
  local CC = GC.CraftClient
  HF.Row.PaintIcon(cell.slot, data.itemID, CC.IconOf(data.itemID), data.buy + data.mail, nil, { pip = true })
  cell:SetWidth(width)
  local textW = width - CELL_TEXT_X - LAYOUT.CELL_PAD
  setText(cell.name, CC.MissingName({ itemID = data.itemID }))
  cell.name:SetWidth(textW)
  -- How far under the name the next line starts.
  local below = 0
  cell.mail:SetShown(data.mail > 0)
  cell.mailIcon:SetShown(data.mail > 0)
  if data.mail > 0 then
    setText(cell.mail, GC.L["%d in your mailbox"]:format(data.mail))
    cell.mail:SetWidth(textW - LAYOUT.MAIL - LAYOUT.MAIL_GAP)
    cell.mailIcon:ClearAllPoints()
    cell.mailIcon:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -(LAYOUT.LINE_GAP + LAYOUT.MAIL_Y))
    cell.mail:ClearAllPoints()
    cell.mail:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", LAYOUT.MAIL + LAYOUT.MAIL_GAP, -LAYOUT.LINE_GAP)
    below = LAYOUT.LINE_GAP + math.max(LAYOUT.MAIL, heightOf(cell.mail, 11))
  end
  cell.price:SetShown(data.cost ~= nil)
  if data.cost then
    setText(cell.price, GC.L["about %s"]:format(GC.Util.Money(data.cost)))
    cell.price:SetWidth(textW)
    cell.price:ClearAllPoints()
    cell.price:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -(below + LAYOUT.LINE_GAP))
    below = below + LAYOUT.LINE_GAP + heightOf(cell.price, 11)
  end
  return heightOf(cell.name, 13) + below
end

-- The cell as tall as the tallest of its row (`inside` within its margins), its icon and its words
-- (`textH` tall, from paintCell) each centred down it.
local function placeCell(cell, textH, inside)
  cell.name:ClearAllPoints()
  cell.name:SetPoint("TOPLEFT", cell, "TOPLEFT", CELL_TEXT_X, -(LAYOUT.CELL_PAD + math.floor((inside - textH) / 2)))
  cell.slot.edge:ClearAllPoints()
  cell.slot.edge:SetPoint("TOPLEFT", cell, "TOPLEFT", LAYOUT.CELL_PAD,
    -(LAYOUT.CELL_PAD + math.floor((inside - LAYOUT.CELL_ICON) / 2)))
  cell:SetHeight(inside + 2 * LAYOUT.CELL_PAD)
end

-- Missing's card: its heading and what the rest costs, the cells, the currencies, Make a BUY list
-- and what the list does.
local function buildMissing(v)
  local T = GC.Theme
  local card = T.Card(v.content, K.glassTop, K.glassBorder)
  card:SetWidth(contentWidth())
  v.missing = card
  v.heading = track(v, wrapping(T.Heading(card, LAYOUT.KICKER)))
  colour(v.heading, K.warn)
  v.cost = wrapped(v, card, LAYOUT.NOTE, K.text2)
  v.unpriced = wrapped(v, card, LAYOUT.SMALL, K.text3)
  v.none = wrapped(v, card, LAYOUT.NOTE, K.text2)
  v.buy = GC.CraftPanel.ui.glyphButton(card, "primary", "buy", K.onGold)
  v.buy:SetHeight(LAYOUT.BUTTON_H)
  v.buy:SetScript("OnClick", function() QV.MakeBuyList() end)
  track(v, v.buy.text)
  v.buyNote = wrapped(v, card, LAYOUT.SMALL, K.text3)
end

-- The heading at the left and, at the right, what the rest costs to buy ("about 486g to buy", the
-- figure in gold) over how many reagents have no price; under the heading when the two do not fit
-- side by side. The cost only when something has a price. Answers its height.
local function paintHead(v, total, unpriced, inner)
  local card = v.missing
  setText(v.heading, GC.Util.Upper(GC.L["Missing"]))
  local right = {}
  if total > 0 then
    setText(v.cost, GC.L["about %s to buy"]:format(GC.Util.Colored(K.goldText, GC.Util.Money(total))))
    right[#right + 1] = v.cost
  end
  v.cost:SetShown(total > 0)
  if unpriced > 0 then
    setText(v.unpriced, unpriced == 1 and GC.L["1 has no price yet"] or GC.L["%d have no price yet"]:format(unpriced))
    right[#right + 1] = v.unpriced
  end
  v.unpriced:SetShown(unpriced > 0)
  local a, b = textWidth(v.heading) + 1, 0
  for _, fs in ipairs(right) do b = math.max(b, textWidth(fs) + 1) end
  local beside = #right > 0 and a + LAYOUT.M_GAP + b <= inner
  v.heading:SetWidth((beside or #right == 0) and a or inner)
  v.heading:ClearAllPoints()
  v.heading:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.M_PAD, -LAYOUT.M_PAD)
  local y = beside and 0 or (heightOf(v.heading, 11) + LAYOUT.LINE_GAP)
  for i, fs in ipairs(right) do
    if i > 1 then y = y + LAYOUT.LINE_GAP end
    fs:SetWidth(beside and b or inner)
    fs:SetJustifyH(beside and "RIGHT" or "LEFT")
    fs:ClearAllPoints()
    if beside then
      fs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -LAYOUT.M_PAD, -(LAYOUT.M_PAD + y))
    else
      fs:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.M_PAD, -(LAYOUT.M_PAD + y))
    end
    y = y + heightOf(fs, 12)
  end
  return math.max(heightOf(v.heading, 11), y)
end

-- Places `fs` across the card at `y` and answers the y under it.
local function stack(card, fs, y)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.M_PAD, -y)
  fs:Show()
  return y + heightOf(fs, 12)
end

-- The whole card from the queue as it stands. Answers its height.
local function paintMissing(v, missing, needs, mailed)
  local CC, Q = GC.CraftClient, GC.CraftQueue
  local card = v.missing
  local inner = contentWidth() - 2 * LAYOUT.M_PAD
  local costs, total, unpriced, items = Q.MissingCost(missing, CC.UnitOf, CC.VendorOf)
  local y = LAYOUT.M_PAD + paintHead(v, total, unpriced, inner)
  if #missing == 0 then
    setText(v.none, GC.L["Nothing is missing for the queue"])
    v.none:SetWidth(inner)
    y = stack(card, v.none, y + LAYOUT.M_GAP)
  else
    v.none:Hide()
  end

  -- Two to a row, each row as tall as its taller cell.
  local cells = cellsOf(needs, missing, costs, items, mailed)
  local cellW = math.floor((inner - LAYOUT.CELL_GAP) / 2)
  for i = 1, #cells, 2 do
    local row, inside = {}, LAYOUT.CELL_ICON
    for j = i, math.min(i + 1, #cells) do
      local cell = v.cells[j] or newCell(card)
      v.cells[j] = cell
      local wasUp = cell:IsShown()
      local textH = paintCell(cell, cells[j], cellW)
      row[#row + 1] = { cell, textH }
      inside = math.max(inside, textH)
      cell:Show()
      -- A pooled cell a shorter list hid, shown again: drawn again whole.
      if not wasUp and v:IsShown() then restamp(cell) end
    end
    y = y + (i == 1 and LAYOUT.M_GAP or LAYOUT.CELL_GAP)
    for k, part in ipairs(row) do
      local cell = part[1]
      placeCell(cell, part[2], inside)
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.M_PAD + (k - 1) * (cellW + LAYOUT.CELL_GAP), -y)
    end
    y = y + inside + 2 * LAYOUT.CELL_PAD
  end
  for i = #cells + 1, #v.cells do v.cells[i]:Hide() end

  local shown = 0
  for _, row in ipairs(missing) do
    if row.currency then
      shown = shown + 1
      local fs = v.currencies[shown] or wrapped(v, card, LAYOUT.NOTE, K.text2)
      v.currencies[shown] = fs
      setText(fs, GC.L["%s is not sold on the auction house"]:format(CC.MissingName({ currencyID = row.currency })))
      fs:SetWidth(inner)
      y = stack(card, fs, y + (shown == 1 and LAYOUT.M_GAP or LAYOUT.LINE_GAP))
    end
  end
  for i = shown + 1, #v.currencies do v.currencies[i]:Hide() end

  local b = v.buy
  b:SetLabel(GC.L["Make a BUY list"])
  GC.CraftPanel.ui.fitGlyph(b, inner)
  if buyable(missing) then b:Enable() else b:Disable() end
  local glyph = b:IsEnabled() and K.onGold or K.text3
  b.glyph:SetVertexColor(glyph[1], glyph[2], glyph[3], 1)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.M_PAD, -(y + LAYOUT.M_GAP))
  y = y + LAYOUT.M_GAP + LAYOUT.BUTTON_H
  setText(v.buyNote, GC.L["The BUY tab at the auction house buys what is missing, and the list follows the queue."])
  v.buyNote:SetWidth(inner)
  y = stack(card, v.buyNote, y + 2 * LAYOUT.LINE_GAP)
  local height = y + LAYOUT.M_PAD
  card:SetHeight(height)
  return height
end

-- ---------------------------------------------------------------------------------------------
-- The view
-- ---------------------------------------------------------------------------------------------

-- docs/addon/AGENTS.md "Text": shown again (its tab picked, the recipes page back), the view draws
-- again each line it shows, as the panel does its own.
local function restampAll(v)
  restamp(v)
  for _, line in ipairs(v.lines) do
    if line.frame:IsShown() then restamp(line) end
  end
  for _, cell in ipairs(v.cells) do
    if cell:IsShown() then restamp(cell) end
  end
end

--- Builds the view in the panel's body (UI/CraftPanel.lua calls this once, hidden until picked).
function QV.Build(host)
  if QV._frame then return QV._frame end
  local T = GC.Theme
  local v = CreateFrame("Frame", nil, host)
  v:SetAllPoints(host)
  v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
  T.QuietScrollBar(v.scroll)
  v.scroll:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -LAYOUT.BAR, 0)
  v.content = CreateFrame("Frame", nil, v.scroll)
  v.content:SetSize(contentWidth(), 1)
  v.scroll:SetScrollChild(v.content)
  v.empty = wrapped(v, v.content, LAYOUT.NOTE, K.text2)
  v.empty:SetWidth(contentWidth())
  buildMissing(v)
  v.lines, v.cells, v.currencies = {}, {}, {}
  v:SetScript("OnShow", restampAll)
  v:Hide()
  QV._frame = v
  return v
end

--- Reads the queue again and repaints the view, while it is on screen.
function QV.Refresh()
  QV._pending = false
  local v = QV._frame
  if not (v and v:IsVisible()) then return end
  local char = GC.CraftClient.Char()
  local rows, missing, listedAt, needs, mailed = work(char)
  QV._rows = rows
  local ctx = runOf(rows)
  ctx.listedAt = listedAt
  local y = 0
  for i, row in ipairs(rows) do
    local line = v.lines[i] or newLine(v)
    v.lines[i] = line
    local wasUp = line.frame:IsShown()
    local height = paintLine(line, row, ctx)
    line.frame:ClearAllPoints()
    line.frame:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -y)
    line.frame:Show()
    -- A pooled line a shorter queue hid, shown again: drawn again whole.
    if not wasUp and v:IsShown() then restamp(line) end
    row.widget = line
    y = y + height + LAYOUT.LINE_SPACE
  end
  for i = #rows + 1, #v.lines do
    v.lines[i].frame:Hide()
    v.lines[i].entry = nil
  end

  if #rows == 0 then
    setText(v.empty, GC.L["The queue is empty. Add a recipe from This recipe."])
    v.empty:ClearAllPoints()
    v.empty:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, 0)
    v.empty:Show()
    v.missing:Hide()
    y = heightOf(v.empty, 12)
  else
    v.empty:Hide()
    y = y - LAYOUT.LINE_SPACE + LAYOUT.GAP
    local height = paintMissing(v, missing, needs, mailed)
    v.missing:ClearAllPoints()
    v.missing:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -y)
    v.missing:Show()
    y = y + height
  end
  v.content:SetHeight(math.max(1, y))
end

--- One repaint on the next frame, however many times this is asked for before then.
function QV.Queue()
  if QV._pending then return end
  QV._pending = true
  after(QV.Refresh)
end

--- The character's craft queue list, made when it has none (named "Craft queue"), holding what
--- the queue needs (Core/CraftQueue.lua's BuyLines), out of the archive and shown in the BUY tab.
--- Returns the list, or nil when nothing is missing.
function QV.MakeBuyList()
  local char = GC.CraftClient.Char()
  if not char then return nil end
  local _, missing, _, needs = work(char)
  if not buyable(missing) then return nil end
  local list = writeList(char, needs)
  if not list then return nil end
  GC.AppRuns.SetArchived(list.code, false)
  if GC.Buy and GC.Buy.SelectRun then GC.Buy.SelectRun(list.code) end
  if GC.Buy and GC.Buy.RefreshIfShown then GC.Buy.RefreshIfShown() end
  GC.Print(GC.L["BUY list %s is ready in the BUY tab at the auction house"]:format(GC.AppRuns.Label(list)))
  return list
end

-- Whether a visit to the mailbox is going on (Core/MailStock.lua, retail only). The client is
-- asked as well, as UI/SniperFrame.lua's _ClearStaleMailPause asks it: walking from the mailbox
-- straight to an auctioneer can shut it with no MAIL_CLOSED (in game 2026-09-23), and a visit left
-- open would keep the bags uncounted. A client that cannot say leaves it to the events.
local function mailboxOpen()
  if not (GC.MailStock and GC.MailStock.IsOpen()) then return false end
  local manager, kinds = _G.C_PlayerInteractionManager, _G.Enum and _G.Enum.PlayerInteractionType
  if manager and manager.IsInteractingWithNpcOfType and kinds and kinds.MailInfo then
    local ok, open = pcall(manager.IsInteractingWithNpcOfType, kinds.MailInfo)
    if ok and open == false then return false end
  end
  return true
end

-- Where Services/CraftClient.lua may end a run of crafts: the player's cast interrupted or failed
-- (when it is the run's own cast, which CraftClient tells), the window closed, and the cast stopped.
-- The view paints what CraftClient says on the next frame, so the order the client hands the event
-- to the two of them is no matter.
local RUN_ENDS = { UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_FAILED = true, TRADE_SKILL_CLOSE = true,
  UPDATE_TRADESKILL_CAST_STOPPED = true }

--- UNIT_SPELLCAST_SUCCEEDED: a craft of a counted recipe takes one off its line, the window open
--- or not. OWNED_AUCTIONS_UPDATED: what this character has up on the auction house, for restocks.
--- BAG_UPDATE_DELAYED: what a restock holds, which a craft of it adds to only once the item is in
--- the bags. MAIL_CLOSED: what waits in the mailbox, as the visit's last read of the inbox left it
--- (Core/MailStock.lua): a reagent's other quality or a crafted item there is held too. Each one
--- brings the craft queue list in step (SyncBuyList), and the panel's top with the view.
--- TRADE_SKILL_CRAFT_BEGIN, each finished cast and the run's ends: the line being crafted, what its
--- run has made, busy or live again.
---
--- While the mailbox is open the bags are not counted: a take can reach the bags before the read of
--- the inbox that sees it gone, and for that moment the units count twice. The list would shrink
--- with them, and what it lowered as bought would not come back when the read caught up.
--- MAIL_CLOSED counts once, when the visit is over.
function QV.OnEvent(event, ...)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    -- Every cast the player makes lands here. In a restricted context the client hands a secret
    -- spell id, which addon code may not compare: such a cast is never a craft from the queue.
    local ok, changed = pcall(function()
      local secret = _G.issecretvalue
      if type(secret) == "function" and secret(spellID) then return false end
      local char = GC.CraftClient.Char()
      return char ~= nil and GC.CraftQueue.OnCraftSucceeded(char, spellID)
    end)
    if ok and changed then
      QV.SyncBuyList()
      panelChanged()
    end
    QV.Queue()
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    if GC.CraftClient.ReadListed() then
      QV.SyncBuyList()
      QV.Queue()
      panelChanged()
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    if not mailboxOpen() then QV.SyncBuyList() end
  elseif event == "MAIL_CLOSED" then
    -- Core/Init.lua ends the visit too; whichever frame hears the event first ends it, so what is
    -- counted here is what the visit settled.
    if GC.MailStock then GC.MailStock.Closed() end
    QV.SyncBuyList()
    QV.Queue()
    panelChanged()
  elseif event == "TRADE_SKILL_CRAFT_BEGIN" or RUN_ENDS[event] then
    QV.Queue()
  end
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
  pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_INTERRUPTED", "player")
  pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_FAILED", "player")
  for _, event in ipairs({ "OWNED_AUCTIONS_UPDATED", "BAG_UPDATE_DELAYED", "MAIL_CLOSED", "TRADE_SKILL_CRAFT_BEGIN",
    "UPDATE_TRADESKILL_CAST_STOPPED", "TRADE_SKILL_CLOSE" }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event, ...) QV.OnEvent(event, ...) end)
  QV._events = events
end

--- What the panel's This recipe and row menu add or restock: into the list, and on screen at once.
function QV.OnQueueChanged()
  QV.SyncBuyList()
  QV.Refresh()
end

if GC.CraftPanel then GC.CraftPanel.OnQueueChanged = QV.OnQueueChanged end
