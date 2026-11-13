local _, GC = ...

-- WoW: Forever's HERO tab (the HERO plan and the boards the owner approved, 2026-11-13): for every
-- equipment slot, the strongest piece on the auction house this character can wear, up to three
-- other choices beside it, and the best set the gold carried pays for, all from
-- Core/ForeverUpgrades.lua; the stat weights it scores by and the gold toward a mount in two side
-- panels. It replaced the /gc upgrades window. Only GoldCap_Camelot.toc loads this file, and it adds
-- its own rail entry as it loads, so retail's rail keeps its four tabs.
--
-- A tab of the GoldCap window as Sold is (UI/SoldFrame.lua): Attach builds its container over the
-- same region, Show and Hide follow the rail, RefreshIfShown repaints it while it is on screen, and
-- a re-show writes every string again (docs/addon/AGENTS.md "Text"). Built from the kit: the rows
-- are BUY's glass cards (UI/BuyFrame.lua), the dock BUY's raised plate, the side panels the Sell
-- inspector's (UI/Sell/Inspector.lua), the icons Theme.Parts'. Nothing is cut: names, gains, notes
-- and headings wrap and their row, the strip or the dock grows; buttons and tags are as wide as
-- their words, measured at each paint.
--
-- It never bids and makes no auction-house call: "+ Buy" and "Add N to BUY" write a BUY list
-- (Hero.AddToBuy) and open the BUY tab, whose own press buys. It reads only saved data, so it works
-- away from the auction house, as the old window did.
GC.Hero = GC.Hero or {}
local Hero = GC.Hero

-- The rail's fifth tab (UI/Theme.lua's RAIL_ORDER) and its icon in the Classic skin, an item icon
-- both clients have (UI/Kit/Textures.lua's T.CLASSIC.icons).
GC.Theme.RAIL_ORDER[#GC.Theme.RAIL_ORDER + 1] = { key = "hero", icon = "hero", label = "HERO" }
GC.Theme.CLASSIC.icons.hero = "Interface\\Icons\\INV_Sword_04"

local HD = {
  GAP = 8,               -- between the strip's parts, a row's columns, the tab's blocks
  WHO_ICON = 36, WHO_MIN = 150, -- the class icon; the least room the name keeps beside the tiles
  TILE_H = 40, TILE_PAD = 8, TILE_ICON = 26, TILE_GAP = 7, BAR_W = 86, BAR_H = 4, -- bar.png caps are 2px
  HEAD_GAP = 4,
  ROW_PAD_X = 8, ROW_PAD_Y = 5, ROW_GAP = 3, SLOT_W = 50, SLOT_ICON = 26,
  BEST_MIN = 160, BEST_MAX = 238, BEST_ICON = 32, BEST_PAD = 7,
  MINI_H = 21, MINI_ICON = 18, MINI_GAP = 3,
  TAG_H = 20, TAG_PAD = 5, TAG_GAP = 4, -- the kit's chip: its slice margin stays under half of 20
  BTN_H = 26, BTN_MIN = 50, -- plaque's 12px caps stay under half the height
  DOCK_ICON = 26, DOCK_ICONS = 6, DOCK_STEP = 19, DOCK_PAD = 10, DOCK_MIN_H = 48, DOCK_BTN_W = 120,
  PANEL_W = 336, PANEL_PAD = 12, PANEL_HEAD_H = 58, PANEL_FOOT_H = 48, PANEL_GUTTER = 22, BOX_W = 62,
  COST_W = 92, PANEL_ICON = 26, LINE_ICON = 22,
  EMPTY_PAD = 20,
  STALE_LIMIT = 6, REPAINT_S = 0.5, SPEED_S = 0.2, TYPE_S = 0.4,
}
Hero.C = HD

-- Every widget the tab owns, and what it last painted: fields on GC.Hero so the module's own spec
-- reads them without reaching into upvalues; nothing else reads them.
local view = { rows = {} }
Hero._view = view
-- The result painted (r), when (now), the piece each row's "+ Buy" adds (chosen[group], an item
-- string), the panel open ("weights", "mount" or nil), and the road to a mount read this paint.
local state = { chosen = {} }
Hero._state = state
-- The repaint rules, moved over from the old window unchanged (Hero.OnItemInfo and below).
local repaint = { stale = 0 }
Hero._repaint = repaint

local Theme, KP

-- Real WoW icons for what the tiles and the panels count: items and spells both clients have.
local ICON = {
  carry = "Interface\\Icons\\INV_Misc_Coin_01", bags = "Interface\\Icons\\INV_Misc_Bag_08",
  mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
}
local STAT_ICON = {
  STR = "Interface\\Icons\\Spell_Nature_Strength", AGI = "Interface\\Icons\\Spell_Holy_BlessingOfAgility",
  STA = "Interface\\Icons\\Spell_Holy_WordFortitude", INT = "Interface\\Icons\\Spell_Holy_MagicalSentry",
  SPI = "Interface\\Icons\\Spell_Holy_DivineSpirit", ARMOR = "Interface\\Icons\\INV_Shield_06",
  DPS = "Interface\\Icons\\Ability_MeleeDamage", AP = "Interface\\Icons\\Ability_Warrior_BattleShout",
  SP = "Interface\\Icons\\Spell_Fire_FlameBolt",
}
-- The slot a row is named by, as the paper doll names it (C_PaperDollInfo.GetInventorySlotInfo):
-- its empty-slot art stands in for a slot with nothing worn.
local SLOT_NAME = {
  HEAD = "HeadSlot", NECK = "NeckSlot", SHOULDER = "ShoulderSlot", BACK = "BackSlot", CHEST = "ChestSlot",
  WRIST = "WristSlot", HANDS = "HandsSlot", WAIST = "WaistSlot", LEGS = "LegsSlot", FEET = "FeetSlot",
  FINGER = "Finger0Slot", MAINHAND = "MainHandSlot", OFFHAND = "SecondaryHandSlot", RANGED = "RangedSlot",
}

-- @localised-keys: literals in these tables ARE GC.L keys, looked up where they are read. Each table
-- closes with a `}` on its own line.
-- What each stat buys a levelling character, under its name in the weights panel.
local STAT_HINT = {
  STR = "Attack power", AGI = "Attack power, crit and dodge", STA = "Health while you level",
  INT = "Mana and spell crit", SPI = "Health and mana back between fights", ARMOR = "Less damage from hits",
  AP = "From Equip lines", SP = "Spell damage and healing", DPS = "The weapon's damage per second",
}
-- @localised-keys: a rogue's or a warrior's weapon DPS, weighed per hand (GC.ForeverUpgrades.HANDS).
local HANDS_HINT = {
  DPS = "Main hand, about 14 attack power. Off hand half, gun or bow a seventh",
}

-- Text ------------------------------------------------------------------------------------

-- Writes a FontString so the client draws it: SetText with the text a string already holds is a
-- no-op, and a string under a parent hidden and shown again can come back undrawn (docs: "Text",
-- measured in game) -- so it is cleared first, and on a re-show also hidden and shown again.
local function put(fs, text)
  fs:SetText("")
  fs:SetText(text or "")
  if view.restamp then fs:Hide() end
  fs:Show()
end

-- A Theme.Button's label, written the same way, and the button as wide as its words.
local function label(button, text, minW)
  button:SetLabel(text)
  put(button.text, button.uppercase and GC.Util.Upper(text) or text)
  if button.FitLabels then button:FitLabels({ text }, minW or 0) end
end

-- A string's own width on one line, rounded up with a pixel spare, as Sold measures it.
local function widthOf(fs)
  return fs.GetUnboundedStringWidth and math.ceil(fs:GetUnboundedStringWidth() or 0) + 1 or 0
end

local function heightOf(fs)
  return fs.GetStringHeight and math.ceil(fs:GetStringHeight() or 0) or 0
end

-- A line that wraps inside `width`, at word breaks and, for a word longer than the line, anywhere;
-- the height is read after the text is written again at the new width (Sold's wrapTo).
local function wrapTo(fs, width)
  fs:SetWidth(math.max(1, width))
  fs:SetWordWrap(true)
  if fs.SetMaxLines then fs:SetMaxLines(0) end
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

local function setColor(fs, c)
  if fs and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function coins(copper) return GC.Util.CoinText(math.max(0, math.floor(tonumber(copper) or 0))) end

-- What a piece adds, in the client's own stat names (GC.ForeverUpgrades.DiffText), each part green
-- or, where it gives something up, red.
local function gainText(diffs)
  local text = GC.ForeverUpgrades.DiffText(diffs)
  if text == "" then return "" end
  local parts = {}
  for part in (text .. ", "):gmatch("(.-), ") do
    parts[#parts + 1] = GC.Util.Colored(part:sub(1, 1) == "-" and Theme.color.red or Theme.color.green, part)
  end
  return table.concat(parts, ", ")
end

-- The client ------------------------------------------------------------------------------

local function prefs()
  return GC.ForeverScan and GC.ForeverScan.Prefs and GC.ForeverScan.Prefs() or nil
end

-- The class's name in the player's language and its file name ("ROGUE").
local function classOf()
  local ok, name, file = pcall(_G.UnitClass, "player")
  if ok and type(file) == "string" then return name or file, file end
  return nil, nil
end

local function levelOf()
  local ok, level = pcall(_G.UnitLevel, "player")
  return ok and tonumber(level) or nil
end

local function moneyOf()
  local ok, m = pcall(_G.GetMoney)
  return ok and tonumber(m) or 0
end

local function itemIcon(item)
  local api = _G.C_Item
  if not (item and api and api.GetItemIconByID) then return nil end
  local ok, file = pcall(api.GetItemIconByID, item)
  return ok and file or nil
end

local function itemIdOf(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- A piece's name as the auction house lists it, its suffix included ("... of the Monkey"): read off
-- its link; the client's name for the item while the link has none.
local function nameOf(c)
  local name = type(c.link) == "string" and c.link:match("|h%[(.-)%]|h") or nil
  if not name and _G.C_Item and _G.C_Item.GetItemNameByID then
    local ok, n = pcall(_G.C_Item.GetItemNameByID, c.itemID)
    if ok and type(n) == "string" and n ~= "" then name = n end
  end
  return name or GC.L["Unknown item"]
end

local function qualityOf(itemID)
  local q = Theme.QualityColor(itemID)
  return q and { q.r, q.g, q.b } or Theme.color.fg
end

-- The paper doll's empty-slot art for a group, or nil.
local function slotArt(group)
  local api = _G.C_PaperDollInfo
  local call = (api and api.GetInventorySlotInfo) or _G.GetInventorySlotInfo
  if type(call) ~= "function" or not SLOT_NAME[group] then return nil end
  local ok, _, texture = pcall(call, SLOT_NAME[group])
  return ok and texture or nil
end

local function current()
  local U = GC.ForeverUpgrades
  local r = U and U.Current and U.Current() or nil
  return r or { slots = {}, loading = 0, noScan = true }
end

local function shown()
  return view.container ~= nil and view.strip ~= nil and view.container:IsVisible() == true
end

-- Whether the tab is on screen: Core/ForeverScan.lua's post-scan update builds with the tooltip
-- pass only then, and hands this tab its result.
function Hero.IsShown() return shown() end

-- Pieces ----------------------------------------------------------------------------------

-- The piece a row's "+ Buy" adds: the one the player clicked, while the row still offers it; else
-- the set's pick for the slot; else the strongest.
local function chosenFor(slot)
  local pieces = { slot.best }
  for _, a in ipairs(slot.alts or {}) do pieces[#pieces + 1] = a end
  local want = state.chosen[slot.group]
  for _, c in ipairs(pieces) do
    if want and c.itemString == want then return c end
  end
  for _, c in ipairs(pieces) do
    if c.inSet then return c end
  end
  return slot.best
end

-- The tags a piece wears, in this order.
local function tagsOf(c)
  local out = {}
  if c.overGold then out[#out + 1] = { GC.L["Over your gold"], Theme.tier.SUSPECT } end
  if c.later then out[#out + 1] = { GC.L["At %d"]:format(c.later), Theme.color.goldHi } end
  if c.inSet then out[#out + 1] = { GC.L["In set"], Theme.color.gold } end
  return out
end

-- A tag: the kit's chip, as wide as its words, over an opaque base, so one that stands on a plate's
-- edge does not show the edge through its tint.
local function newTag(parent)
  local chip = Theme.Chip(parent)
  chip:SetHeight(HD.TAG_H)
  chip.base = chip:CreateTexture(nil, "BACKGROUND", nil, -8)
  Theme.SetShape(chip.base, "chip")
  local p = Theme.color.panel
  chip.base:SetVertexColor(p[1], p[2], p[3], 1)
  chip.base:SetAllPoints()
  chip:Hide()
  return chip
end

local function paintTag(chip, tag)
  chip:SetLabel(GC.Util.Upper(tag[1]), tag[2])
  put(chip.text, GC.Util.Upper(tag[1]))
  local w = widthOf(chip.text) + 2 * HD.TAG_PAD
  chip:SetWidth(w)
  chip:Show()
  return w
end

-- A tag per entry of `tags` on `owner` (its pool owner.tags), the rest hidden; answers their widths.
local function paintTags(owner, tags)
  owner.tags = owner.tags or {}
  local widths = {}
  for i, tag in ipairs(tags) do
    owner.tags[i] = owner.tags[i] or newTag(owner)
    widths[i] = paintTag(owner.tags[i], tag)
  end
  for i = #tags + 1, #owner.tags do owner.tags[i]:Hide() end
  return widths
end

-- The tooltip of the piece under the cursor: the item's own, beside the window rather than over the
-- list it describes (Theme.ItemTooltipOutside), with GoldCap's own lines under it (UI/Tooltip.lua).
local function pieceTip(self)
  local c = self.cand
  if not (c and GameTooltip and view.container) then return end
  Theme.ItemTooltipOutside(self, view.container:GetParent())
  GameTooltip:SetHyperlink(c.link or c.itemString)
  GameTooltip:Show()
end

local paint -- forward: the whole tab from the last result (below)

-- A piece the player can point at and click: the strongest one's sunken plate (`big`), or one of the
-- other choices' slim lines. Hover is the engine's HIGHLIGHT layer (docs: "Buttons and hover"); the
-- piece chosen for the row wears a gold ring, painted as state, never on hover.
local function newPiece(parent, big)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp")
  b:EnableMouse(true)
  b.big = big
  b.isHeroPiece = true
  if big then
    local wc, gb = Theme.color.bg, Theme.color.border
    b.plate = Theme.ShapeTexture(b, "BACKGROUND", "control", { wc[1], wc[2], wc[3], 1 })
    b.plate:SetAllPoints()
    b.ring = Theme.ShapeTexture(b, "BORDER", "control", { gb[1], gb[2], gb[3], gb[4] or 0.075 }, true)
    b.ring:SetAllPoints()
  end
  local gc, hc = Theme.color.gold, Theme.color.hover
  b.onWash = Theme.ShapeTexture(b, "BACKGROUND", "control", { gc[1], gc[2], gc[3], 0.10 })
  b.onWash:SetAllPoints()
  b.onRing = Theme.ShapeTexture(b, "ARTWORK", "control", { gc[1], gc[2], gc[3], 0.72 }, true)
  b.onRing:SetAllPoints()
  b.hover = b:CreateTexture(nil, "HIGHLIGHT")
  Theme.SetShape(b.hover, "control")
  b.hover:SetAllPoints()
  b.hover:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  b.icon = KP.NewIcon(b, big and HD.BEST_ICON or HD.MINI_ICON)
  b.name = Theme.Label(b, big and 12 or 11)
  b.name:SetJustifyH("LEFT")
  b.gain = Theme.Label(b, big and 11 or 10)
  b.gain:SetJustifyH("LEFT")
  b.price = Theme.Num(b, big and 12 or 11, true)
  b.price:SetJustifyH("RIGHT")
  setColor(b.price, Theme.color.fg)
  b:SetScript("OnEnter", pieceTip)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- A modified click is the client's (shift links the piece, ctrl tries it on); a plain one picks it
  -- for the row's "+ Buy".
  b:SetScript("OnClick", function(self)
    local c = self.cand
    if not c then return end
    local handle = _G.HandleModifiedItemClick
    if type(handle) == "function" and handle(c.link or c.itemString) then return end
    state.chosen[c.group] = c.itemString
    paint()
  end)
  return b
end

local function paintPiece(b, c, on)
  b.cand = c
  KP.PaintIcon(b.icon, c.itemID, itemIcon(c.itemID) or itemIcon(c.link))
  put(b.name, nameOf(c))
  setColor(b.name, qualityOf(c.itemID))
  put(b.gain, gainText(c.diffs))
  setColor(b.gain, Theme.color.green)
  put(b.price, coins(c.unit))
  b.onWash:SetShown(on)
  b.onRing:SetShown(on)
  b.tagWidths = paintTags(b, tagsOf(c))
  b:Show()
end

-- The strongest piece's plate at `width`: its icon, its name and what it adds wrapping beside it,
-- its price at the right; its tags on the plate's top edge while they fit along it (`ribbon`), else
-- a line of their own under what it adds. Answers its height and whether the tags stand on its edge.
local function layoutBest(b, width)
  local priceW = hug(b.price)
  local textX = HD.BEST_PAD + HD.BEST_ICON + HD.GAP
  local textW = width - textX - HD.GAP - priceW - HD.BEST_PAD
  local nameH = wrapTo(b.name, textW)
  local gainH = (b.gain:GetText() or "") ~= "" and wrapTo(b.gain, textW) or 0
  local tagsW = 0
  for i, w in ipairs(b.tagWidths) do tagsW = tagsW + w + (i > 1 and HD.TAG_GAP or 0) end
  local ribbon = #b.tagWidths > 0 and tagsW <= width - 2 * HD.BEST_PAD
  local tagsH = (#b.tagWidths > 0 and not ribbon) and (HD.TAG_H + 3) or 0
  local textH = nameH + (gainH > 0 and gainH + 2 or 0) + tagsH
  local h = math.max(HD.BEST_ICON + 8, textH + 10)
  b.icon.edge:ClearAllPoints()
  b.icon.edge:SetPoint("LEFT", b, "LEFT", HD.BEST_PAD, 0)
  local top = math.floor((h - textH) / 2)
  b.name:ClearAllPoints()
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", textX, -top)
  b.gain:ClearAllPoints()
  b.gain:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
  if gainH == 0 then b.gain:Hide() end
  b.price:ClearAllPoints()
  b.price:SetPoint("RIGHT", b, "RIGHT", -HD.BEST_PAD, 0)
  local x = ribbon and -HD.BEST_PAD or nil
  local line = top + nameH + (gainH > 0 and gainH + 2 or 0) + 3
  local left = textX
  for i = 1, #b.tagWidths do
    local chip = b.tags[i]
    chip:ClearAllPoints()
    if ribbon then
      -- Right to left along the top edge, half over it.
      chip:SetPoint("RIGHT", b, "TOPRIGHT", x, 0)
      x = x - b.tagWidths[i] - HD.TAG_GAP
    else
      if left + b.tagWidths[i] > textX + textW and left > textX then
        left = textX
        line = line + HD.TAG_H + 2
        h = h + HD.TAG_H + 2
      end
      chip:SetPoint("TOPLEFT", b, "TOPLEFT", left, -line)
      left = left + b.tagWidths[i] + HD.TAG_GAP
    end
  end
  return h, ribbon
end

-- One of the other choices at `width`: its icon, name, what it adds and its tags on one line while
-- they fit before its price; else the name wrapping on its own line, and what it adds and the tags
-- on the lines under it, the tags beside what it adds while they fit there and flowing on otherwise.
-- Answers its height.
local function layoutMini(b, width)
  local priceW = hug(b.price)
  local textX = 3 + HD.MINI_ICON + 6
  local room = width - textX - 6 - priceW - 6
  local tagsW = 0
  for i, w in ipairs(b.tagWidths) do tagsW = tagsW + w + (i > 1 and HD.TAG_GAP or 0) end
  local hasGain = (b.gain:GetText() or "") ~= ""
  local nameW, gainW = widthOf(b.name), hasGain and widthOf(b.gain) or 0
  b.icon.edge:ClearAllPoints()
  b.price:ClearAllPoints()
  b.name:ClearAllPoints()
  b.gain:ClearAllPoints()
  if not hasGain then b.gain:Hide() end
  if nameW + (hasGain and 6 + gainW or 0) + (tagsW > 0 and 5 + tagsW or 0) <= room then
    hug(b.name)
    if hasGain then hug(b.gain) end
    b.icon.edge:SetPoint("LEFT", b, "LEFT", 3, 0)
    b.name:SetPoint("LEFT", b, "LEFT", textX, 0)
    b.gain:SetPoint("LEFT", b.name, "RIGHT", 6, 0)
    local x = textX + nameW + (hasGain and 6 + gainW or 0) + 5
    for i = 1, #b.tagWidths do
      b.tags[i]:ClearAllPoints()
      b.tags[i]:SetPoint("LEFT", b, "LEFT", x, 0)
      x = x + b.tagWidths[i] + HD.TAG_GAP
    end
    b.price:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    return HD.MINI_H
  end
  local y = 3
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", textX, -y)
  y = y + wrapTo(b.name, room) + 2
  -- `y` is the top of the line being filled, `lineH` how tall it is so far, `x` where on it next.
  local x, lineH = textX, 0
  if hasGain then
    local gainH
    if gainW <= room then
      hug(b.gain)
      gainH = heightOf(b.gain)
    else
      gainH = wrapTo(b.gain, room)
    end
    b.gain:SetPoint("TOPLEFT", b, "TOPLEFT", textX, -y)
    if tagsW > 0 and gainW + 5 + tagsW <= room then
      x, lineH = textX + gainW + 5, gainH
    else
      y = y + gainH + 2
    end
  end
  for i = 1, #b.tagWidths do
    if x > textX and x + b.tagWidths[i] > textX + room then
      x, y, lineH = textX, y + math.max(lineH, HD.TAG_H) + 2, 0
    end
    b.tags[i]:ClearAllPoints()
    b.tags[i]:SetPoint("TOPLEFT", b, "TOPLEFT", x, -y)
    x, lineH = x + b.tagWidths[i] + HD.TAG_GAP, math.max(lineH, HD.TAG_H)
  end
  b.icon.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  b.price:SetPoint("TOPRIGHT", b, "TOPRIGHT", -6, -4)
  return math.max(HD.MINI_H, y + lineH + 3)
end

-- Rows ------------------------------------------------------------------------------------

-- The row's columns at `width`: the slot, the strongest piece's plate, the other choices, "+ Buy".
local function columns(width, actW)
  local inner = width - 2 * HD.ROW_PAD_X
  local free = inner - HD.SLOT_W - actW - 3 * HD.GAP
  local best = math.max(HD.BEST_MIN, math.min(HD.BEST_MAX, math.floor(free * 0.5)))
  return { slot = HD.ROW_PAD_X, best = HD.ROW_PAD_X + HD.SLOT_W + HD.GAP, bestW = best,
    alts = HD.ROW_PAD_X + HD.SLOT_W + HD.GAP + best + HD.GAP, altsW = math.max(1, free - best), actW = actW }
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  -- A glass card, BUY's (UI/BuyFrame.lua): a sliced rounded fill and the kit's glass edge.
  local zc, gb = Theme.color.zebra, Theme.color.border
  row.card = Theme.ShapeTexture(row, "BACKGROUND", "control", { zc[1], zc[2], zc[3], zc[4] or 0.035 })
  row.card:SetPoint("TOPLEFT", 2, 0)
  row.card:SetPoint("BOTTOMRIGHT", -2, 0)
  row.cardRing = Theme.ShapeTexture(row, "BORDER", "control", { gb[1], gb[2], gb[3], gb[4] or 0.075 }, true)
  row.cardRing:SetPoint("TOPLEFT", 2, 0)
  row.cardRing:SetPoint("BOTTOMRIGHT", -2, 0)
  row.worn = KP.NewIcon(row, HD.SLOT_ICON)
  row.slotName = Theme.Heading(row, 9)
  row.slotName:SetJustifyH("CENTER")
  setColor(row.slotName, Theme.color.fgDim)
  row.best = newPiece(row, true)
  row.minis = {}
  row.add = Theme.Button(row, "ghost", "plaque")
  row.add:SetHeight(HD.BTN_H)
  row.add:SetScript("OnClick", function(self)
    local c = self:GetParent().chosen
    if c then Hero.AddToBuy({ c }) end
  end)
  return row
end

local function paintRow(row, slot)
  row.slot = slot
  local wornID = itemIdOf(slot.worn)
  KP.PaintIcon(row.worn, wornID, (wornID and itemIcon(wornID)) or slotArt(slot.group))
  put(row.slotName, GC.Util.Upper(_G[slot.labelKey] or slot.labelKey or ""))
  local chosen = chosenFor(slot)
  row.chosen = chosen
  paintPiece(row.best, slot.best, chosen == slot.best)
  for i, alt in ipairs(slot.alts or {}) do
    row.minis[i] = row.minis[i] or newPiece(row, false)
    paintPiece(row.minis[i], alt, chosen == alt)
  end
  for i = #(slot.alts or {}) + 1, #row.minis do
    row.minis[i].cand = nil
    row.minis[i]:Hide()
  end
  label(row.add, GC.L["+ Buy"], HD.BTN_MIN)
end

-- Pass two: the anchors at the columns' widths. Every block stands centred in the row, which is as
-- tall as its tallest block. Answers the row's height.
local function layoutRow(row, cols)
  local slotH = HD.SLOT_ICON + 3 + wrapTo(row.slotName, HD.SLOT_W)
  local bestH, ribbon = layoutBest(row.best, cols.bestW)
  local bestTop = ribbon and math.ceil(HD.TAG_H / 2) or 0
  local altH, heights = 0, {}
  for i, mini in ipairs(row.minis) do
    if mini.cand then
      heights[i] = layoutMini(mini, cols.altsW)
      altH = altH + heights[i] + (i > 1 and HD.MINI_GAP or 0)
    end
  end
  local inner = math.max(slotH, bestTop + bestH, altH, HD.BTN_H)
  local h = inner + 2 * HD.ROW_PAD_Y
  row.worn.edge:ClearAllPoints()
  row.worn.edge:SetPoint("TOP", row, "TOPLEFT", cols.slot + HD.SLOT_W / 2,
    -(HD.ROW_PAD_Y + math.floor((inner - slotH) / 2)))
  row.slotName:ClearAllPoints()
  row.slotName:SetPoint("TOP", row.worn.edge, "BOTTOM", 0, -3)
  row.best:ClearAllPoints()
  row.best:SetPoint("TOPLEFT", row, "TOPLEFT", cols.best,
    -(HD.ROW_PAD_Y + bestTop + math.floor((inner - bestTop - bestH) / 2)))
  row.best:SetSize(cols.bestW, bestH)
  local y = HD.ROW_PAD_Y + math.floor((inner - altH) / 2)
  for i, mini in ipairs(row.minis) do
    if mini.cand then
      mini:ClearAllPoints()
      mini:SetPoint("TOPLEFT", row, "TOPLEFT", cols.alts, -y)
      mini:SetSize(cols.altsW, heights[i])
      y = y + heights[i] + HD.MINI_GAP
    end
  end
  row.add:ClearAllPoints()
  row.add:SetPoint("RIGHT", row, "RIGHT", -HD.ROW_PAD_X, 0)
  return h
end

-- The strip ---------------------------------------------------------------------------------

local function newTile(parent, file, clickable)
  local t = { frame = Theme.Card(parent, Theme.color.panel, Theme.color.border, true) }
  t.icon = KP.NewIcon(t.frame, HD.TILE_ICON)
  t.icon.edge:SetPoint("LEFT", t.frame, "LEFT", HD.TILE_PAD, 0)
  t.file = file
  t.label = Theme.Num(t.frame, 9, true)
  t.label:SetJustifyH("LEFT")
  setColor(t.label, Theme.color.fgDim)
  t.value = Theme.Num(t.frame, 12, true)
  t.value:SetJustifyH("LEFT")
  setColor(t.value, Theme.color.fg)
  t.small = Theme.Num(t.frame, 10)
  t.small:SetJustifyH("LEFT")
  setColor(t.small, Theme.color.fgMuted)
  if clickable then
    -- A quiet plate over the whole tile: the engine's wash under the cursor, a click opens its panel.
    t.hit = KP.plate(t.frame, nil, "plaque")
    t.hit:SetAllPoints(t.frame)
    t.bar = CreateFrame("Frame", nil, t.frame)
    local track = Theme.SlicedTexture(t.bar, "BACKGROUND", Theme.MEDIA .. "bar.png", GC.Kit.Tokens.ink(0.07), 2)
    track:SetAllPoints()
    t.bar.fill = Theme.SlicedTexture(t.bar, "ARTWORK", Theme.MEDIA .. "bar.png", Theme.color.gold, 2)
    t.bar.fill:SetPoint("TOPLEFT")
    t.bar.fill:SetPoint("BOTTOMLEFT")
  end
  return t
end

-- A tile's figures and its width; `small` beside the value, `progress` its bar's share.
local function paintTile(t, labelText, value, small, progress)
  KP.PaintIcon(t.icon, nil, t.file)
  put(t.label, GC.Util.Upper(labelText))
  put(t.value, value)
  if small then put(t.small, small) else t.small:Hide() end
  local textW = math.max(hug(t.label), hug(t.value) + (small and 3 + hug(t.small) or 0), progress and HD.BAR_W or 0)
  local textX = HD.TILE_PAD + HD.TILE_ICON + HD.TILE_GAP
  local h = math.max(HD.TILE_H, heightOf(t.label) + heightOf(t.value) + (progress and HD.BAR_H + 3 or 0) + 10)
  local top = math.floor((h - (heightOf(t.label) + 1 + heightOf(t.value) + (progress and HD.BAR_H + 3 or 0))) / 2)
  t.label:ClearAllPoints()
  t.label:SetPoint("TOPLEFT", t.frame, "TOPLEFT", textX, -top)
  t.value:ClearAllPoints()
  t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -1)
  t.small:ClearAllPoints()
  t.small:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 3, 0)
  if t.bar then
    if progress then
      t.bar:ClearAllPoints()
      t.bar:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -3)
      t.bar:SetSize(HD.BAR_W, HD.BAR_H)
      t.bar.fill:SetWidth(math.max(HD.BAR_H, HD.BAR_W * math.min(1, progress)))
      t.bar.fill:SetShown(progress > 0)
      t.bar:Show()
    else
      t.bar:Hide()
    end
  end
  local w = textX + textW + HD.TILE_PAD
  t.frame:SetSize(w, h)
  return w, h
end

local function createStrip(container)
  local s = {}
  s.classEdge = container:CreateTexture(nil, "BORDER")
  s.classEdge:SetSize(HD.WHO_ICON, HD.WHO_ICON)
  s.classIcon = container:CreateTexture(nil, "ARTWORK")
  s.classIcon:SetPoint("TOPLEFT", s.classEdge, "TOPLEFT", 1, -1)
  s.classIcon:SetPoint("BOTTOMRIGHT", s.classEdge, "BOTTOMRIGHT", -1, 1)
  s.name = Theme.Label(container, 14)
  s.name:SetJustifyH("LEFT")
  setColor(s.name, Theme.color.fg)
  s.sub = Theme.Num(container, 10)
  s.sub:SetJustifyH("LEFT")
  setColor(s.sub, Theme.color.fgDim)
  s.note = Theme.Label(container, 10)
  s.note:SetJustifyH("LEFT")
  setColor(s.note, Theme.tier.SUSPECT)
  s.carry = newTile(container, ICON.carry)
  s.bags = newTile(container, ICON.bags)
  s.mount = newTile(container, ICON.mount, true)
  s.mount.hit:SetScript("OnClick", function() Hero.TogglePanel("mount") end)
  s.weights = Theme.Button(container, "ghost", "plaque")
  s.weights:SetScript("OnClick", function() Hero.TogglePanel("weights") end)
  return s
end

-- The class's own icon in its colour's frame (GetClassAtlas, the atlas Forever's character creation
-- draws), hidden where the client has no such atlas.
local function paintClassIcon(s, file, colour)
  local atlas
  if file then
    local get = _G.GetClassAtlas
    atlas = type(get) == "function" and get(file:lower()) or ("classicon-" .. file:lower())
    local tex = _G.C_Texture
    if tex and tex.GetAtlasInfo and not tex.GetAtlasInfo(atlas) then atlas = nil end
  end
  if atlas then
    s.classIcon:SetAtlas(atlas)
    s.classEdge:SetColorTexture(colour[1], colour[2], colour[3], 1)
  end
  s.classIcon:SetShown(atlas ~= nil)
  s.classEdge:SetShown(atlas ~= nil)
  return atlas ~= nil
end

local function ageWords(r, now)
  local at = tonumber(r.at)
  if not at then return nil end
  return GC.Util.FormatElapsedWords(math.max(0, (now or at) - at))
end

-- The strip at `width`: who looks, then the three tiles and the Weights button; on one line while the
-- name keeps WHO_MIN beside them, else the tiles on the lines under it, flowing. Answers its height.
local function layoutStrip(r, width)
  local s = view.strip
  local className, file = classOf()
  local rc = file and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[file] or nil
  local colour = rc and { rc.r, rc.g, rc.b } or Theme.color.goldHi
  local withIcon = paintClassIcon(s, file, colour)
  local level = levelOf()
  local who = className and GC.Util.Colored(colour, className) or ""
  put(s.name, level and GC.L["%s · level %d"]:format(who, level) or who)
  local age = ageWords(r, state.now)
  if age then put(s.sub, GC.L["Scan %s ago"]:format(age)) else s.sub:Hide() end
  local notes = {}
  if r.stale then notes[#notes + 1] = GC.L["Scan again to read each version's own stats."] end
  if (r.loading or 0) > 0 then
    notes[#notes + 1] = GC.L["Items still loading: %d. Open this again in a moment."]:format(r.loading)
  end
  if #notes > 0 then put(s.note, table.concat(notes, " ")) else s.note:Hide() end

  local road = state.road
  local carry = road and road.money or moneyOf()
  local parts = {}
  parts[1] = { s.carry.frame, (paintTile(s.carry, GC.L["You carry"], coins(carry))) }
  parts[2] = { s.bags.frame, (paintTile(s.bags, GC.L["Bags on the AH"], road and coins(road.bags) or "-")) }
  local have = road and (road.money or 0) + (road.bags or 0) or carry
  local cost = road and tonumber(road.cost) or nil
  local mountW = paintTile(s.mount, GC.L["Mount at 40"], coins(have),
    cost and GC.L["of %s"]:format(coins(cost)) or nil, cost and cost > 0 and have / cost or nil)
  parts[3] = { s.mount.frame, mountW }
  local gold = Theme.color.gold
  s.mount.frame:SetTint(nil, state.panel == "mount" and { gold[1], gold[2], gold[3], 0.6 } or Theme.color.border)
  label(s.weights, GC.L["Weights"], 0)
  s.weights:SetVariant(state.panel == "weights" and "active" or "ghost")
  s.weights:SetHeight(HD.TILE_H)
  parts[4] = { s.weights, s.weights:GetWidth() or 0 }

  local tileH = HD.TILE_H
  for i = 1, 3 do tileH = math.max(tileH, parts[i][1]:GetHeight() or 0) end
  local partsW = -HD.GAP
  for _, part in ipairs(parts) do partsW = partsW + part[2] + HD.GAP end
  local whoRoom = width - partsW - HD.GAP
  local oneLine = whoRoom >= HD.WHO_MIN
  local whoW = oneLine and whoRoom or width
  local textX = withIcon and HD.WHO_ICON + 9 or 0
  local nameH = wrapTo(s.name, whoW - textX)
  local subH = s.sub:IsShown() and wrapTo(s.sub, whoW - textX) or 0
  local noteH = s.note:IsShown() and wrapTo(s.note, whoW - textX) or 0
  local textH = nameH + (subH > 0 and 2 + subH or 0) + (noteH > 0 and 2 + noteH or 0)
  local whoH = math.max(withIcon and HD.WHO_ICON or 0, textH)
  local band = oneLine and math.max(whoH, tileH) or whoH
  local whoTop = math.floor((band - whoH) / 2)
  s.classEdge:ClearAllPoints()
  s.classEdge:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -(whoTop + math.floor((whoH - HD.WHO_ICON) / 2)))
  s.name:ClearAllPoints()
  s.name:SetPoint("TOPLEFT", view.container, "TOPLEFT", textX, -(whoTop + math.floor((whoH - textH) / 2)))
  s.sub:ClearAllPoints()
  s.sub:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -2)
  s.note:ClearAllPoints()
  s.note:SetPoint("TOPLEFT", subH > 0 and s.sub or s.name, "BOTTOMLEFT", 0, -2)

  if oneLine then
    local x = width
    for i = #parts, 1, -1 do
      local frame, w = parts[i][1], parts[i][2]
      x = x - w
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", x, -math.floor((band - tileH) / 2))
      x = x - HD.GAP
    end
    for i = 1, 3 do parts[i][1]:SetHeight(tileH) end
    return band
  end
  -- Too narrow: the tiles flow on the lines under the name, each line as tall as its tiles.
  local x, y = 0, whoH + HD.GAP
  for i, part in ipairs(parts) do
    if x > 0 and x + part[2] > width then
      x, y = 0, y + tileH + HD.GAP
    end
    part[1]:ClearAllPoints()
    part[1]:SetPoint("TOPLEFT", view.container, "TOPLEFT", x, -y)
    if i <= 3 then part[1]:SetHeight(tileH) end
    x = x + part[2] + HD.GAP
  end
  return y + tileH
end

-- The column headings, wrapping inside their columns.
local function createHeader(container)
  local h = { frame = CreateFrame("Frame", nil, container) }
  for _, key in ipairs({ "slot", "best", "alts" }) do
    local fs = Theme.Num(h.frame, 9, true)
    fs:SetJustifyH(key == "slot" and "CENTER" or "LEFT")
    setColor(fs, Theme.color.fgDim)
    h[key] = fs
  end
  return h
end

local function layoutHeader(width, y, cols)
  local h = view.header
  put(h.slot, GC.Util.Upper(GC.L["Slot"]))
  put(h.best, GC.Util.Upper(GC.L["Strongest you can wear now"]))
  put(h.alts, GC.Util.Upper(GC.L["Other choices"]))
  local height = math.max(wrapTo(h.slot, HD.SLOT_W), wrapTo(h.best, cols.bestW), wrapTo(h.alts, cols.altsW))
  for key, x in pairs({ slot = cols.slot, best = cols.best, alts = cols.alts }) do
    h[key]:ClearAllPoints()
    h[key]:SetPoint("BOTTOMLEFT", h.frame, "BOTTOMLEFT", x, 0)
  end
  h.frame:ClearAllPoints()
  h.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -y)
  h.frame:SetSize(width, height)
  return height
end

-- The dock ----------------------------------------------------------------------------------

-- The best set for the gold carried, at the tab's foot: BUY's raised plate (UI/BuyFrame.lua's
-- dock), the set's icons stacked at the left, what it adds, its cost and the one button that puts
-- it on a BUY list; under them where the prices come from and what is left after it.
local function createDock(container)
  local d = { frame = CreateFrame("Frame", nil, container) }
  local f = d.frame
  f:EnableMouse(true)
  local phc, gb = Theme.color.panelHi or Theme.color.panel, Theme.color.border
  Theme.ShapeTexture(f, "BACKGROUND", "control", { phc[1], phc[2], phc[3], 1 }):SetAllPoints(f)
  Theme.ShapeTexture(f, "ARTWORK", "control", { gb[1], gb[2], gb[3], gb[4] or 0.075 }, true):SetAllPoints(f)
  d.icons = {}
  d.title = Theme.Label(f, 13)
  setColor(d.title, Theme.color.fg)
  d.sub = Theme.Label(f, 10)
  d.sumHead = Theme.Num(f, 9, true)
  d.sumHead:SetJustifyH("RIGHT")
  setColor(d.sumHead, Theme.color.fgDim)
  d.sum = Theme.Num(f, 13, true)
  setColor(d.sum, Theme.color.fg)
  d.add = Theme.Button(f, "primary", "plaque")
  d.add:SetHeight(28)
  d.add:SetScript("OnClick", function()
    local set = state.r and state.r.set
    if set and #set.list > 0 then Hero.AddToBuy(set.list) end
  end)
  d.note = Theme.Num(f, 10)
  d.note:SetJustifyH("LEFT")
  setColor(d.note, Theme.color.fgDim)
  d.leftHead = Theme.Num(f, 9, true)
  setColor(d.leftHead, Theme.color.fgDim)
  d.left = Theme.Num(f, 12, true)
  setColor(d.left, Theme.color.fg)
  local rc = Theme.color.border
  d.rule = f:CreateTexture(nil, "ARTWORK")
  d.rule:SetColorTexture(rc[1], rc[2], rc[3], rc[4] or 0.06)
  d.rule:SetHeight(1)
  return d
end

local function layoutDock(r, width)
  local d = view.dock
  local f = d.frame
  local set = r.set
  local picks = set and set.list or {}
  local n = #picks
  local carry = state.road and state.road.money or moneyOf()
  for i = 1, math.min(n, HD.DOCK_ICONS) do
    d.icons[i] = d.icons[i] or KP.NewIcon(f, HD.DOCK_ICON)
    KP.PaintIcon(d.icons[i], picks[i].itemID, itemIcon(picks[i].itemID))
  end
  for i = math.min(n, HD.DOCK_ICONS) + 1, #d.icons do KP.HideIcon(d.icons[i]) end
  if n > 0 then
    put(d.title, GC.L["Best buys for the %s you carry"]:format(coins(carry)))
    local gains = GC.ForeverUpgrades.DiffText(set.diffs)
    put(d.sub, n == 1 and GC.L["1 upgrade: %s"]:format(gains) or GC.L["%d upgrades: %s"]:format(n, gains))
    setColor(d.sub, Theme.color.fgMuted)
    put(d.sumHead, GC.Util.Upper(GC.L["All %d"]:format(n)))
    put(d.sum, coins(set.cost))
    label(d.add, GC.L["Add %d to BUY"]:format(n), HD.DOCK_BTN_W)
    d.add:Show()
  else
    put(d.title, GC.L["Nothing on the auction house fits the gold you carry yet."])
    d.sub:Hide(); d.sumHead:Hide(); d.sum:Hide(); d.add:Hide()
  end
  local age = ageWords(r, state.now)
  local note = GC.L["Use and Chance on hit effects are not counted."]
  if age then note = GC.L["Prices from your scan %s ago."]:format(age) .. " " .. note end
  put(d.note, note)
  if set then
    put(d.leftHead, GC.Util.Upper(GC.L["Left after"]))
    put(d.left, coins(set.left))
  else
    d.leftHead:Hide(); d.left:Hide()
  end

  -- Tier one, right to left: the button, the sum; the icons at the left, the words between.
  local right = width - HD.DOCK_PAD
  if d.add:IsShown() then
    d.add:ClearAllPoints()
    right = right - (d.add:GetWidth() or HD.DOCK_BTN_W)
    right = right - HD.GAP
  end
  local sumW = 0
  if d.sum:IsShown() then sumW = math.max(hug(d.sum), hug(d.sumHead)) end
  local stack = math.min(n, HD.DOCK_ICONS)
  local textX = HD.DOCK_PAD + (stack > 0 and HD.DOCK_ICON + (stack - 1) * HD.DOCK_STEP + HD.GAP or 0)
  local textW = right - (sumW > 0 and sumW + HD.GAP or 0) - textX
  local titleH = wrapTo(d.title, textW)
  local subH = d.sub:IsShown() and wrapTo(d.sub, textW) or 0
  local tier1 = math.max(HD.DOCK_ICON, 28, titleH + (subH > 0 and subH + 2 or 0), sumW > 0 and heightOf(d.sumHead) + heightOf(d.sum) + 2 or 0)
  -- Tier two: the note wrapping at the left, LEFT AFTER and the figure at the right.
  local leftW = d.left:IsShown() and math.max(hug(d.left), hug(d.leftHead)) or 0
  local noteH = wrapTo(d.note, width - 2 * HD.DOCK_PAD - (leftW > 0 and leftW + HD.GAP or 0))
  local tier2 = math.max(noteH, leftW > 0 and heightOf(d.leftHead) + heightOf(d.left) + 2 or 0)
  local h = math.max(HD.DOCK_MIN_H, HD.DOCK_PAD + tier1 + HD.GAP + 1 + HD.GAP + tier2 + HD.DOCK_PAD)
  local mid = HD.DOCK_PAD + tier1 / 2
  for i = 1, stack do
    local icon = d.icons[i]
    icon.edge:ClearAllPoints()
    icon.edge:SetPoint("LEFT", f, "TOPLEFT", HD.DOCK_PAD + (i - 1) * HD.DOCK_STEP, -mid)
  end
  local textTop = HD.DOCK_PAD + math.floor((tier1 - titleH - (subH > 0 and subH + 2 or 0)) / 2)
  d.title:ClearAllPoints()
  d.title:SetPoint("TOPLEFT", f, "TOPLEFT", textX, -textTop)
  d.sub:ClearAllPoints()
  d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -2)
  if d.add:IsShown() then d.add:SetPoint("RIGHT", f, "TOPRIGHT", -HD.DOCK_PAD, -mid) end
  if sumW > 0 then
    d.sumHead:ClearAllPoints()
    d.sumHead:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", right, -mid)
    d.sum:ClearAllPoints()
    d.sum:SetPoint("TOPRIGHT", d.sumHead, "BOTTOMRIGHT", 0, -2)
  end
  local ruleY = HD.DOCK_PAD + tier1 + HD.GAP
  d.rule:ClearAllPoints()
  d.rule:SetPoint("TOPLEFT", f, "TOPLEFT", HD.DOCK_PAD, -ruleY)
  d.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -HD.DOCK_PAD, -ruleY)
  d.note:ClearAllPoints()
  d.note:SetPoint("TOPLEFT", f, "TOPLEFT", HD.DOCK_PAD, -(ruleY + 1 + HD.GAP))
  if leftW > 0 then
    d.leftHead:ClearAllPoints()
    d.leftHead:SetPoint("TOPRIGHT", f, "TOPRIGHT", -HD.DOCK_PAD, -(ruleY + 1 + HD.GAP))
    d.left:ClearAllPoints()
    d.left:SetPoint("TOPRIGHT", d.leftHead, "BOTTOMRIGHT", 0, -2)
  end
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", view.container, "BOTTOMLEFT", 0, 0)
  f:SetSize(width, h)
  return h
end

-- The list's empty states: why there is nothing to show, centred where the rows would be.
local function createEmpty(parent)
  local e = { frame = Theme.Card(parent, Theme.color.panel, GC.Kit.Tokens.ink(0.07), true) }
  e.message = Theme.Label(e.frame, 13)
  e.message:SetJustifyH("CENTER")
  setColor(e.message, Theme.color.fgMuted)
  e.frame:Hide()
  return e
end

local function layoutEmpty(r, width, y)
  local e = view.empty
  local message
  if r.noScan then
    message = GC.L["No scan with gear in it yet. Open the auction house and let GoldCap scan it."]
  elseif r.noStats then
    message = GC.L["This client does not report item stats, so GoldCap cannot compare gear."]
  elseif r.noWeights then
    message = GC.L["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"]
  elseif #(r.slots or {}) == 0 then
    message = GC.L["Nothing on the auction house beats what you wear at your level."]
  end
  if not message then
    e.frame:Hide()
    return y
  end
  put(e.message, message)
  local mh = wrapTo(e.message, width - 2 * HD.EMPTY_PAD)
  e.message:ClearAllPoints()
  e.message:SetPoint("TOP", e.frame, "TOP", 0, -HD.EMPTY_PAD)
  local h = mh + 2 * HD.EMPTY_PAD
  e.frame:ClearAllPoints()
  e.frame:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
  e.frame:SetSize(width, h)
  e.frame:Show()
  return y + h
end

-- The panels --------------------------------------------------------------------------------

local panelPaint = {} -- per panel key: function(p, width), set below

-- Where an open panel lives: down the tab's right side, from under the strip to the dock's top
-- edge, `dx` px right of that while it slides (Theme.Slide), as the Sell inspector does.
local function placePanel(p, dx)
  if dx then p.dx = dx end
  p:ClearAllPoints()
  p:SetPoint("TOPRIGHT", view.container, "TOPRIGHT", p.dx or 0, -(state.panelTop or 0))
  p:SetPoint("BOTTOMRIGHT", view.container, "BOTTOMRIGHT", p.dx or 0, state.panelBottom or 0)
end

-- A side panel, the Sell inspector's (UI/Sell/Inspector.lua): its fill and edge (the client's
-- tooltip border in Classic), a head with an icon, a title and a line under it, an X, a scrolling
-- body, and a foot with a button at each end. Escape shuts it, never the whole window.
local function newPanel()
  local container = view.container
  local p = CreateFrame("Frame", nil, container)
  p:SetFrameLevel((container:GetFrameLevel() or 0) + 20)
  p:EnableMouse(true)
  p:Hide()
  local clientPanel = Theme.ClientPanel and Theme.ClientPanel(p)
  local ibc = Theme.color.border
  if clientPanel then
    clientPanel:SetAllPoints(p)
  else
    local ipc = Theme.color.panel
    Theme.ShapeTexture(p, "BACKGROUND", "panel", { ipc[1], ipc[2], ipc[3], 1 }):SetAllPoints(p)
    p.bevel = Theme.PanelBevel and Theme.PanelBevel(p, "panel", p)
    if not p.bevel then
      Theme.ShapeTexture(p, "BORDER", "panel", GC.Kit.Tokens.ink((ibc[4] or 0.06) * 2), true):SetAllPoints(p)
    end
  end
  p.iconEdge = p:CreateTexture(nil, "BORDER")
  p.iconEdge:SetSize(HD.WHO_ICON, HD.WHO_ICON)
  p.iconEdge:SetPoint("TOPLEFT", HD.PANEL_PAD + 3, -10)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetPoint("TOPLEFT", p.iconEdge, "TOPLEFT", 1, -1)
  p.icon:SetPoint("BOTTOMRIGHT", p.iconEdge, "BOTTOMRIGHT", -1, 1)
  p.iconFrame = Theme.IconFrame and Theme.IconFrame(p.icon, p)
  p.title = Theme.Label(p, 15)
  p.title:SetJustifyH("LEFT")
  p.sub = Theme.Num(p, 10)
  p.sub:SetJustifyH("LEFT")
  setColor(p.sub, Theme.color.fgMuted)
  p.close = Theme.Button(p, "ghost", "badge")
  p.close:SetSize(22, 20)
  p.close:SetPoint("TOPRIGHT", -HD.PANEL_PAD - 2, -18)
  p.close:SetLabel("X")
  p.close:SetScript("OnClick", function() Hero.TogglePanel(nil) end)
  if p.EnableKeyboard then p:EnableKeyboard(true) end
  local function passKeys(on)
    if p.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
      p:SetPropagateKeyboardInput(on)
    end
  end
  p:SetScript("OnKeyDown", function(_, key)
    if InCombatLockdown and InCombatLockdown() then return end
    if key ~= "ESCAPE" or (p.slider and p.slider:Leaving()) then passKeys(true) return end
    passKeys(false)
    Hero.TogglePanel(nil)
    if C_Timer and C_Timer.After then C_Timer.After(0, function() passKeys(true) end) end
  end)
  if Theme.Slide then p.slider = Theme.Slide(p, function(dx) placePanel(p, dx) end) end
  p.headRule = p:CreateTexture(nil, "ARTWORK")
  p.headRule:SetColorTexture(ibc[1], ibc[2], ibc[3], ibc[4] or 0.06)
  p.headRule:SetHeight(1)
  p.footRule = p:CreateTexture(nil, "ARTWORK")
  p.footRule:SetColorTexture(ibc[1], ibc[2], ibc[3], ibc[4] or 0.06)
  p.footRule:SetHeight(1)
  p.footRule:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", HD.PANEL_PAD, HD.PANEL_FOOT_H)
  p.footRule:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -HD.PANEL_PAD, HD.PANEL_FOOT_H)
  p.scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(p.scroll) end
  p.body = CreateFrame("Frame", nil, p.scroll)
  p.body:SetSize(HD.PANEL_W - 4 - HD.PANEL_GUTTER, 1)
  p.scroll:SetScrollChild(p.body)
  p.secondary = Theme.Button(p, "ghost", "plaque")
  p.secondary:SetHeight(30)
  p.secondary:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", HD.PANEL_PAD, 9)
  p.primary = Theme.Button(p, "primary", "plaque")
  p.primary:SetHeight(30)
  p.primary:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -HD.PANEL_PAD, 9)
  p.primary:SetScript("OnClick", function() Hero.TogglePanel(nil) end)
  return p
end

-- The panel's head (an icon in its frame's colour, the title and the line under it wrapping, as tall
-- as they come out) and its body's place under it. Answers the body's width.
local function paintHead(p, width, opts)
  if opts.atlas then p.icon:SetAtlas(opts.atlas) else p.icon:SetTexture(opts.file) end
  if p.icon.SetTexCoord and not opts.atlas then p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  local edge = opts.edge or Theme.color.border
  p.iconEdge:SetColorTexture(edge[1], edge[2], edge[3], 1)
  put(p.title, opts.title)
  setColor(p.title, opts.titleColor or Theme.color.fg)
  put(p.sub, opts.sub)
  local textX = HD.PANEL_PAD + 3 + HD.WHO_ICON + 10
  local textW = width - textX - (HD.PANEL_PAD + 2 + 22 + 6)
  local th, sh = wrapTo(p.title, textW), wrapTo(p.sub, textW)
  p.title:ClearAllPoints()
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", textX, -12)
  p.sub:ClearAllPoints()
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
  local head = math.max(HD.PANEL_HEAD_H, 12 + th + 3 + sh + 10)
  p.headRule:ClearAllPoints()
  p.headRule:SetPoint("TOPLEFT", p, "TOPLEFT", HD.PANEL_PAD, -head + 2)
  p.headRule:SetPoint("TOPRIGHT", p, "TOPRIGHT", -HD.PANEL_PAD, -head + 2)
  p.scroll:ClearAllPoints()
  p.scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -head)
  p.scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -HD.PANEL_GUTTER, HD.PANEL_FOOT_H + 2)
  local bodyW = width - 4 - HD.PANEL_GUTTER
  p.body:SetWidth(bodyW)
  return bodyW
end

-- A number or amount box: an EditBox in a well, its edge red while what it holds cannot be read.
local function newBox(parent, width)
  local well = Theme.Card(parent, Theme.color.bg, GC.Kit.Tokens.ink(0.14), true)
  well:SetSize(width, 24)
  local box = CreateFrame("EditBox", nil, well)
  box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -2)
  box:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if box.SetFont then
    box:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    box:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    if Theme.OnRescale then Theme.OnRescale(function(scale) box:SetFont(Theme.FONT_UI, 11 * scale, "") end) end
  end
  if box.SetJustifyH then box:SetJustifyH("RIGHT") end
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  well.box = box
  function well:SetBad(bad)
    well.bad = bad and true or nil
    well:SetTint(nil, bad and Theme.color.red or GC.Kit.Tokens.ink(0.14))
  end
  return well
end

-- The text a box shows: written only while the player is not typing in it.
local function fill(well, text)
  if not (well.box.HasFocus and well.box:HasFocus()) then well.box:SetText(text) end
end

local function trim(text) return ((text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function rebuildSoon()
  if state.typeDue then return end
  local timer = _G.C_Timer
  if not (timer and timer.After) then Hero.RefreshIfShown(true) return end
  state.typeDue = true
  timer.After(HD.TYPE_S, function()
    state.typeDue = nil
    Hero.RefreshIfShown(true)
  end)
end

-- The weights panel ---------------------------------------------------------------------------

-- The stats the panel offers: every one the class's defaults name, DPS, and any the player's own
-- weights hold; all of them for a class with no defaults. The class's strongest primary stat and,
-- for a class whose hands are weighed, DPS lead, framed gold.
local function weightTokens(class, weights)
  local U = GC.ForeverUpgrades
  local defaults = U.DEFAULT_WEIGHTS[class] or {}
  local any = next(defaults) ~= nil
  local top, topW = nil, 0
  for _, token in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
    if (defaults[token] or 0) > topW then top, topW = token, defaults[token] end
  end
  local lead = {}
  if top then lead[#lead + 1] = top end
  if U.HANDS[class] then lead[#lead + 1] = "DPS" end
  local out, seen = {}, {}
  local function add(token, isTop)
    if seen[token] then return end
    seen[token] = true
    out[#out + 1] = { token = token, top = isTop }
  end
  for _, token in ipairs(lead) do add(token, true) end
  for _, token in ipairs(U.TOKEN_ORDER) do
    if not any or defaults[token] ~= nil or weights[token] ~= nil or token == "DPS" then add(token, false) end
  end
  return out
end

local function onWeight(token, text)
  local p, class = prefs(), select(2, classOf())
  local well = view.panels.weights.boxes[token]
  if not (p and class and well) then return end
  text = trim(text)
  if text == "" then well:SetBad(false) return end
  local v = tonumber((text:gsub(",", ".")))
  if not v then well:SetBad(true) return end
  well:SetBad(false)
  -- A copy of the weights in force, so a stat with no box here keeps its weight.
  local new = {}
  for k, w in pairs(GC.ForeverUpgrades.WeightsFor(p, class)) do new[k] = w end
  new[token] = v ~= 0 and v or nil
  p.weights = type(p.weights) == "table" and p.weights or {}
  p.weights[class] = new
  rebuildSoon()
end

local function newWeightRow(p, token)
  local row = { frame = CreateFrame("Frame", nil, p.body) }
  row.icon = KP.NewIcon(row.frame, HD.PANEL_ICON)
  row.icon.edge:SetPoint("LEFT", row.frame, "LEFT", 0, 0)
  row.name = Theme.Label(row.frame, 12)
  setColor(row.name, Theme.color.fg)
  row.hint = Theme.Label(row.frame, 10)
  setColor(row.hint, Theme.color.fgDim)
  row.box = newBox(row.frame, HD.BOX_W)
  row.box:SetPoint("RIGHT", row.frame, "RIGHT", 0, 0)
  row.box.box:SetScript("OnTextChanged", function(self, byUser)
    if byUser then onWeight(token, self:GetText()) end
  end)
  row.box.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local rc = Theme.color.border
  row.rule = row.frame:CreateTexture(nil, "ARTWORK")
  row.rule:SetColorTexture(rc[1], rc[2], rc[3], rc[4] or 0.06)
  row.rule:SetHeight(1)
  row.rule:SetPoint("BOTTOMLEFT")
  row.rule:SetPoint("BOTTOMRIGHT")
  p.boxes[token] = row.box
  return row
end

local function setStyle(style)
  local p = prefs()
  if not p then return end
  p.heroStyle = style
  Hero.RefreshIfShown(true)
end

local function newWeights()
  local p = newPanel()
  p.rows, p.boxes = {}, {}
  -- A rogue's main hand: the two ways it is used, in the sunken track of a two-way switch
  -- (Theme.Parts.sunkenTrack), the one in force filled gold.
  p.style = { cap = Theme.Num(p.body, 9, true), hint = Theme.Label(p.body, 10) }
  setColor(p.style.cap, Theme.color.fgDim)
  setColor(p.style.hint, Theme.color.fgDim)
  p.style.switch = CreateFrame("Frame", nil, p.body)
  KP.sunkenTrack(p.style.switch)
  for _, id in ipairs({ "sinister", "backstab" }) do
    local b = Theme.Button(p.style.switch, "segment", "badge")
    if b.SetGlow then b:SetGlow(false) end
    b:SetHeight(22)
    b:SetScript("OnClick", function() setStyle(id) end)
    p.style[id] = b
  end
  p.secondary:SetScript("OnClick", function()
    local prefsNow, class = prefs(), select(2, classOf())
    if not (prefsNow and class) then return end
    if type(prefsNow.weights) == "table" then prefsNow.weights[class] = nil end
    prefsNow.heroStyle = nil
    for _, well in pairs(p.boxes) do
      well.box:ClearFocus()
      well:SetBad(false)
    end
    Hero.RefreshIfShown(true)
  end)
  return p
end

panelPaint.weights = function(p, width)
  local className, class = classOf()
  local rc = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class] or nil
  local colour = rc and { rc.r, rc.g, rc.b } or Theme.color.goldHi
  local get = _G.GetClassAtlas
  local bodyW = paintHead(p, width, {
    atlas = class and (type(get) == "function" and get(class:lower()) or ("classicon-" .. class:lower())) or nil,
    file = ICON.carry, edge = colour, titleColor = colour,
    title = GC.L["What counts for a %s"]:format(className or ""),
    sub = GC.L["The list changes as you type"] })
  local U = GC.ForeverUpgrades
  local weights = (class and U.WeightsFor(prefs() or {}, class)) or {}
  local y = 0
  for i, entry in ipairs(weightTokens(class, weights)) do
    local row = p.rows[i]
    if not row or row.token ~= entry.token then
      if row then row.frame:Hide() end
      row = p.rows[entry.token .. "#"] or newWeightRow(p, entry.token)
      p.rows[entry.token .. "#"] = row
      row.token = entry.token
      p.rows[i] = row
    end
    KP.PaintIcon(row.icon, nil, STAT_ICON[entry.token])
    local key = U.TOKENS[entry.token][1]
    put(row.name, _G[key] or entry.token)
    put(row.hint, GC.L[(U.HANDS[class] and HANDS_HINT[entry.token]) or STAT_HINT[entry.token]])
    local gold = Theme.color.gold
    if not row.box.bad then
      row.box:SetTint(nil, entry.top and { gold[1], gold[2], gold[3], 0.65 } or GC.Kit.Tokens.ink(0.14))
    end
    local w = weights[entry.token]
    fill(row.box, w and ("%g"):format(w) or "0")
    local textX = HD.PANEL_ICON + 9
    local textW = bodyW - 2 * HD.PANEL_PAD - textX - HD.BOX_W - HD.GAP
    local nh, hh = wrapTo(row.name, textW), wrapTo(row.hint, textW)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.frame, "TOPLEFT", textX, -5)
    row.hint:ClearAllPoints()
    row.hint:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    local h = math.max(HD.PANEL_ICON, nh + 1 + hh) + 10
    row.frame:ClearAllPoints()
    row.frame:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
    row.frame:SetSize(bodyW - 2 * HD.PANEL_PAD, h)
    row.frame:Show()
    y = y + h
  end
  for i = #weightTokens(class, weights) + 1, #p.rows do p.rows[i].frame:Hide() end

  local st = p.style
  local style = state.r and state.r.style
  local rogue = class == "ROGUE"
  for _, part in ipairs({ st.cap, st.hint, st.switch }) do part:SetShown(rogue) end
  if rogue then
    y = y + 10
    put(st.cap, GC.Util.Upper(_G.INVTYPE_WEAPONMAINHAND or ""))
    st.cap:ClearAllPoints()
    st.cap:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
    y = y + heightOf(st.cap) + 5
    local inner = bodyW - 2 * HD.PANEL_PAD
    label(st.sinister, GC.L["Sword, mace, fist"], 0)
    label(st.backstab, GC.L["Dagger"], 0)
    local half = math.floor((inner - 6) / 2)
    local beside = math.max(st.sinister:GetWidth() or 0, st.backstab:GetWidth() or 0) <= half
    st.sinister:ClearAllPoints()
    st.sinister:SetPoint("TOPLEFT", st.switch, "TOPLEFT", 2, -2)
    st.backstab:ClearAllPoints()
    if beside then
      st.backstab:SetPoint("LEFT", st.sinister, "RIGHT", 2, 0)
      st.switch:SetSize(inner, 26)
    else
      st.backstab:SetPoint("TOPLEFT", st.sinister, "BOTTOMLEFT", 0, -2)
      st.switch:SetSize(inner, 50)
    end
    for _, id in ipairs({ "sinister", "backstab" }) do
      st[id]:SetWidth(beside and half or inner - 4)
      st[id]:SetVariant((style or "sinister") == id and "primary" or "segment")
    end
    st.switch:ClearAllPoints()
    st.switch:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
    y = y + (beside and 26 or 50) + 5
    put(st.hint, GC.L["From the weapon in your main hand. Backstab needs a dagger."])
    local hh = wrapTo(st.hint, inner)
    st.hint:ClearAllPoints()
    st.hint:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
    y = y + hh
  end
  p.body:SetHeight(math.max(1, y + HD.PANEL_PAD))
  label(p.secondary, GC.L["Reset to %s"]:format(className or ""), 0)
  label(p.primary, GC.L["DONE"], 0)
end

-- The mount panel -----------------------------------------------------------------------------

-- The riding cost the player typed, taken as the box loses focus (Enter, Escape, a click away): an
-- empty box is the trainer's price again (GoldCapDB.forever.mountCost cleared, as /gc mount clear);
-- one that cannot be read stays red and changes nothing.
local function applyCost(well)
  local p = prefs()
  if not p then return end
  local text = trim(well.box:GetText())
  if text == "" then
    p.mountCost = nil
  else
    local copper = GC.ForeverRoad.ParseMoney(text)
    if not copper then well:SetBad(true) return end
    p.mountCost = copper
  end
  well:SetBad(false)
  paint()
end

-- A line of the mount panel: an icon, its words with a smaller line under them, and at the right an
-- amount or a button.
local function newMountLine(body, file)
  local l = { frame = CreateFrame("Frame", nil, body) }
  l.icon = KP.NewIcon(l.frame, HD.LINE_ICON)
  l.icon.edge:SetPoint("LEFT", l.frame, "LEFT", 0, 0)
  l.file = file
  l.text = Theme.Label(l.frame, 12)
  setColor(l.text, Theme.color.fgMuted)
  l.small = Theme.Label(l.frame, 10)
  setColor(l.small, Theme.color.fgDim)
  l.amount = Theme.Num(l.frame, 12, true)
  setColor(l.amount, Theme.color.fg)
  local rc = Theme.color.border
  l.rule = l.frame:CreateTexture(nil, "ARTWORK")
  l.rule:SetColorTexture(rc[1], rc[2], rc[3], rc[4] or 0.06)
  l.rule:SetHeight(1)
  l.rule:SetPoint("BOTTOMLEFT")
  l.rule:SetPoint("BOTTOMRIGHT")
  return l
end

local function newMount()
  local p = newPanel()
  local b = p.body
  p.big = Theme.Num(b, 16, true)
  p.big:SetJustifyH("LEFT")
  setColor(p.big, Theme.color.fg)
  p.bar = CreateFrame("Frame", nil, b)
  local track = Theme.SlicedTexture(p.bar, "BACKGROUND", Theme.MEDIA .. "bar.png", GC.Kit.Tokens.ink(0.07), 2)
  track:SetAllPoints()
  local gold = Theme.color.gold
  p.bar.gold = Theme.SlicedTexture(p.bar, "ARTWORK", Theme.MEDIA .. "bar.png", gold, 2)
  p.bar.gold:SetPoint("TOPLEFT")
  p.bar.gold:SetPoint("BOTTOMLEFT")
  p.bar.bags = Theme.SlicedTexture(p.bar, "ARTWORK", Theme.MEDIA .. "bar.png", { gold[1], gold[2], gold[3], 0.5 }, 2)
  p.bar.bags:SetPoint("TOPLEFT", p.bar.gold, "TOPRIGHT")
  p.bar.bags:SetPoint("BOTTOMLEFT", p.bar.gold, "BOTTOMRIGHT")
  p.lines = { carry = newMountLine(b, ICON.carry), bags = newMountLine(b, ICON.bags), gain = newMountLine(b, ICON.bags) }
  p.sell = Theme.Button(p.lines.gain.frame, "ghost", "plaque")
  p.sell:SetHeight(HD.BTN_H)
  p.sell:SetPoint("RIGHT", p.lines.gain.frame, "RIGHT", 0, 0)
  p.sell:SetScript("OnClick", function() if GC.Sniper and GC.Sniper.ShowView then GC.Sniper.ShowView("sell") end end)
  p.pace = Theme.Card(b, Theme.color.panel, { gold[1], gold[2], gold[3], 0.3 }, true)
  p.pace:SetTint({ gold[1], gold[2], gold[3], 0.08 }, nil)
  p.pace.text = Theme.Label(p.pace, 12)
  setColor(p.pace.text, Theme.color.fgMuted)
  p.costLabel = Theme.Num(b, 9, true)
  p.costLabel:SetJustifyH("LEFT")
  setColor(p.costLabel, Theme.color.fgDim)
  p.costHint = Theme.Label(b, 10)
  setColor(p.costHint, Theme.color.fgDim)
  p.cost = newBox(b, HD.COST_W)
  p.cost.box:SetScript("OnTextChanged", function(self, byUser)
    if not byUser then return end
    local text = trim(self:GetText())
    p.cost:SetBad(text ~= "" and GC.ForeverRoad.ParseMoney(text) == nil)
  end)
  p.cost.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.cost.box:SetScript("OnEditFocusLost", function() applyCost(p.cost) end)
  p.secondary:SetScript("OnClick", function() GC.ForeverRoad.Slash("share") end)
  return p
end

local function paintLine(l, width, text, small, amount)
  KP.PaintIcon(l.icon, nil, l.file)
  put(l.text, text)
  if small then put(l.small, small) else l.small:Hide() end
  local amountW = 0
  if amount then put(l.amount, amount); amountW = hug(l.amount) else l.amount:Hide() end
  local textX = HD.LINE_ICON + 8
  local textW = width - textX - amountW - HD.GAP
  local th = wrapTo(l.text, textW)
  local sh = small and wrapTo(l.small, textW) or 0
  l.text:ClearAllPoints()
  l.text:SetPoint("TOPLEFT", l.frame, "TOPLEFT", textX, -6)
  l.small:ClearAllPoints()
  l.small:SetPoint("TOPLEFT", l.text, "BOTTOMLEFT", 0, -1)
  l.amount:ClearAllPoints()
  l.amount:SetPoint("RIGHT", l.frame, "RIGHT", 0, 0)
  local h = math.max(HD.LINE_ICON, th + (sh > 0 and sh + 1 or 0)) + 12
  l.frame:SetSize(width, h)
  l.frame:Show()
  return h
end

panelPaint.mount = function(p, width)
  local s = state.road or {}
  local bodyW = paintHead(p, width, { file = ICON.mount, title = GC.L["Gold for your mount"],
    sub = GC.L["Riding at level 40"] })
  local inner = bodyW - 2 * HD.PANEL_PAD
  local money, bags = s.money or moneyOf(), s.bags or 0
  local have, cost = money + bags, tonumber(s.cost) or 0
  local y = 4
  put(p.big, GC.L["%s of %s"]:format(coins(have), coins(cost)))
  local bh = wrapTo(p.big, inner)
  p.big:ClearAllPoints()
  p.big:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
  y = y + bh + 8
  p.bar:ClearAllPoints()
  p.bar:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
  p.bar:SetSize(inner, 8)
  local share = cost > 0 and math.min(1, money / cost) or 0
  local bagShare = cost > 0 and math.min(1 - share, bags / cost) or 0
  p.bar.gold:SetWidth(math.max(1, inner * share))
  p.bar.gold:SetShown(share > 0)
  p.bar.bags:SetWidth(math.max(1, inner * bagShare))
  p.bar.bags:SetShown(bagShare > 0)
  y = y + 8 + 6
  local lines = p.lines
  local function place(l, h)
    l.frame:ClearAllPoints()
    l.frame:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
    y = y + h
  end
  place(lines.carry, paintLine(lines.carry, inner, GC.L["Gold you carry"], nil, coins(money)))
  place(lines.bags, paintLine(lines.bags, inner, GC.L["Your bags"],
    GC.L["Each stack at the better of a vendor and the AH"], coins(bags)))
  if (s.gainItems or 0) > 0 and (s.gain or 0) > 0 then
    label(p.sell, GC.L["OPEN SELL"], 0)
    local sellW = (p.sell:GetWidth() or 0) + HD.GAP
    local h = paintLine(lines.gain, inner - sellW, GC.L["%d items fetch more on the AH"]:format(s.gainItems),
      GC.L["%s more than a vendor pays"]:format(coins(s.gain)), nil)
    lines.gain.frame:SetSize(inner, h)
    place(lines.gain, h)
  else
    lines.gain.frame:Hide()
  end
  -- The pace: the forecast sentence of /gc mount (GC.ForeverRoad.Lines' second), and what the best
  -- set for the gold carried leaves toward it.
  local words = {}
  local roadLines = s.cost and GC.ForeverRoad.Lines(s) or {}
  if roadLines[2] then words[#words + 1] = roadLines[2] end
  local set = state.r and state.r.set
  local n = set and #set.list or 0
  if n == 1 then
    words[#words + 1] = GC.L["The upgrade in your set leaves %s toward it."]:format(coins(have - set.cost))
  elseif n > 1 then
    words[#words + 1] = GC.L["The %d upgrades in your set leave %s toward it."]:format(n, coins(have - set.cost))
  end
  if #words > 0 then
    y = y + 9
    put(p.pace.text, table.concat(words, " "))
    local ph = wrapTo(p.pace.text, inner - 18)
    p.pace.text:ClearAllPoints()
    p.pace.text:SetPoint("TOPLEFT", p.pace, "TOPLEFT", 9, -8)
    p.pace:ClearAllPoints()
    p.pace:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
    p.pace:SetSize(inner, ph + 16)
    p.pace:Show()
    y = y + ph + 16
  else
    p.pace:Hide()
  end
  y = y + 10
  put(p.costLabel, GC.Util.Upper(GC.L["Riding cost"]))
  put(p.costHint, GC.L["%s at the trainer. Type your own after a discount."]:format(coins(GC.ForeverRoad.C.RIDING_COST)))
  local textW = inner - HD.COST_W - HD.GAP
  local lh, hh = wrapTo(p.costLabel, textW), wrapTo(p.costHint, textW)
  p.costLabel:ClearAllPoints()
  p.costLabel:SetPoint("TOPLEFT", p.body, "TOPLEFT", HD.PANEL_PAD, -y)
  p.costHint:ClearAllPoints()
  p.costHint:SetPoint("TOPLEFT", p.costLabel, "BOTTOMLEFT", 0, -2)
  local rowH = math.max(24, lh + 2 + hh)
  p.cost:ClearAllPoints()
  p.cost:SetPoint("TOPRIGHT", p.body, "TOPRIGHT", -HD.PANEL_PAD, -(y + math.floor((rowH - 24) / 2)))
  -- The player's own cost, or nothing while the trainer's price stands (the line above names it).
  local own = (prefs() or {}).mountCost
  if not p.cost.bad then fill(p.cost, type(own) == "number" and own > 0 and GC.ForeverRoad.Plain(own) or "") end
  y = y + rowH
  p.body:SetHeight(math.max(1, y + HD.PANEL_PAD))
  label(p.secondary, GC.L["Share in chat"], 0)
  label(p.primary, GC.L["DONE"], 0)
end

local PANEL_NEW = { weights = newWeights, mount = newMount }

local function paintPanels(width)
  view.panels = view.panels or {}
  local w = math.max(200, math.min(HD.PANEL_W, width - 120))
  for key, p in pairs(view.panels) do
    if key ~= state.panel and p:IsShown() then
      if p.slider then p.slider:Shut() else p:Hide() end
    end
  end
  local key = state.panel
  if not key then return end
  local p = view.panels[key]
  if not p then
    p = PANEL_NEW[key]()
    view.panels[key] = p
  end
  p:SetWidth(w)
  placePanel(p)
  panelPaint[key](p, w)
  if p.slider then p.slider:Open() else p:Show() end
end

--- Opens the panel `key` ("weights" or "mount"), or shuts it when it is the one open; nil shuts
--- whichever is.
function Hero.TogglePanel(key)
  if key ~= nil and state.panel == key then key = nil end
  state.panel = key
  paint()
end

-- The whole tab -------------------------------------------------------------------------------

local function currentWidth()
  local w = view.container:GetWidth()
  if w and w > 0 then view.width = w end
  return view.width or 600
end

local function renderRows(r, width)
  local entries = r.slots or {}
  local rows = view.rows
  for i = #rows + 1, #entries do rows[i] = createRow(view.content) end
  local actW = HD.BTN_MIN
  for i, slot in ipairs(entries) do
    paintRow(rows[i], slot)
    actW = math.max(actW, rows[i].add:GetWidth() or 0)
  end
  local cols = columns(width, actW)
  local y = 0
  for i = 1, #entries do
    local row = rows[i]
    row.add:SetWidth(actW)
    local h = layoutRow(row, cols)
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, -y)
    row:Show()
    y = y + h + HD.ROW_GAP
  end
  for i = #entries + 1, #rows do
    rows[i].slot, rows[i].chosen = nil, nil
    rows[i]:Hide()
  end
  y = layoutEmpty(r, width, y)
  view.content:SetHeight(math.max(1, y))
  return cols
end

paint = function()
  if not (view.container and view.strip) then return end
  local r = state.r or { slots = {}, loading = 0 }
  local width = currentWidth()
  view.content:SetWidth(width)
  state.road = GC.ForeverRoad and GC.ForeverRoad.Snapshot and GC.ForeverRoad.Snapshot() or nil
  local top = layoutStrip(r, width) + HD.GAP
  local dockH = layoutDock(r, width)
  local cols = renderRows(r, width)
  local headH = layoutHeader(width, top, cols)
  view.scroll:ClearAllPoints()
  view.scroll:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -(top + headH + HD.HEAD_GAP))
  view.scroll:SetPoint("BOTTOMRIGHT", view.container, "BOTTOMRIGHT", 0, dockH + HD.GAP)
  state.panelTop, state.panelBottom = top, dockH + HD.GAP
  paintPanels(width)
  -- A repaint under a still cursor can hand the hovered piece another item, or take it away: its
  -- tooltip follows, or goes.
  local owner = GameTooltip and GameTooltip:IsShown() and GameTooltip.GetOwner and GameTooltip:GetOwner() or nil
  if type(owner) == "table" and owner.isHeroPiece then
    if owner.cand and owner:IsVisible() then pieceTip(owner) else GameTooltip:Hide() end
  end
end

local function build()
  if view.strip then return end
  local container = view.container
  view.strip = createStrip(container)
  view.header = createHeader(container)
  view.dock = createDock(container)
  view.empty = createEmpty(view.content)
end

-- BUY ---------------------------------------------------------------------------------------

--- Puts `picks` (candidates: the set's list, or one row's piece) on the player's Upgrades list and
--- opens it in BUY. The list is the one prefs.heroList names, while it is still one of the player's
--- own made in the game; else a new one, remembered there. Its other lines stay as they are; a line
--- for an item already on it keeps the larger quantity and buys the versions of both, or any when
--- either side buys any (GC.AppRuns.JoinVer): adding a pick twice is still one line of one.
--- Lines go in through GC.AppRuns.SetLines, already merged here, never AddLines, which sums. Each
--- item's cap is the lot's price and 5% (GC.ForeverUpgrades.BuyLines), the player's own line cap
--- BUY ranks first; on an item already listed, the higher of that and the cap it had. Returns the
--- list, or nil.
function Hero.AddToBuy(picks)
  local lines, caps = GC.ForeverUpgrades.BuyLines(picks)
  if #lines == 0 then return nil end
  local p = prefs()
  local run = p and p.heroList and GC.AppRuns.Get(p.heroList) or nil
  if not (type(run) == "table" and run.origin == "game") then
    run = GC.AppRuns.NewList(GC.L["Upgrades"], {})
    if not run then return nil end
    if p then p.heroList = run.code end
  end
  local merged, byItem, listed = {}, {}, {}
  for _, line in ipairs(run.lines or {}) do
    -- A copy: SetLines tells a change from what the run holds, so the run's own lines stay as they are.
    local copy = {}
    for k, v in pairs(line) do copy[k] = v end
    merged[#merged + 1] = copy
    byItem[copy.i] = copy
  end
  for _, line in ipairs(lines) do
    local have = byItem[line.i]
    if have then
      have.q = math.max(tonumber(have.q) or 0, line.q)
      have.ver = GC.AppRuns.JoinVer(have.ver, line.ver)
      listed[line.i] = true
    else
      local copy = { i = line.i, q = line.q, ver = line.ver }
      merged[#merged + 1] = copy
      byItem[line.i] = copy
    end
  end
  if not GC.AppRuns.SetLines(run.code, merged) then return nil end
  local own = GC.db and type(GC.db.runLineCaps) == "table" and GC.db.runLineCaps[run.code] or nil
  for itemID, copper in pairs(caps) do
    local had = listed[itemID] and type(own) == "table" and tonumber(own[itemID]) or nil
    if GC.Buy and GC.Buy._SetLineCap then GC.Buy._SetLineCap(run.code, itemID, math.max(copper, had or 0)) end
  end
  GC.AppRuns.SetArchived(run.code, false)
  if GC.Buy and GC.Buy.SelectRun then GC.Buy.SelectRun(run.code) end
  if GC.Sniper and GC.Sniper.ShowView then GC.Sniper.ShowView("buy") end
  return run
end

-- The tab contract --------------------------------------------------------------------------

-- Builds the tab's container, hidden, over the same region the Deals list occupies -- geometry
-- passed through from the Sniper's createFrame, exactly as GC.Sold.Attach. The strip, the rows and
-- the dock wait for the first Show.
function Hero.Attach(f, geo)
  Theme, KP = GC.Theme, GC.Theme.Parts
  local container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()
  view.container, view.width = container, geo.rowWidth
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, HD.MINI_H)
  scroll:SetScrollChild(content)
  view.scroll, view.content = scroll, content
  -- A resize, a dock reparent or a font-scale change moves every measured width, so the tab is
  -- laid out again whole, from the result it holds. A frame resized while hidden does not reliably
  -- fire OnSizeChanged; Show() lays it out anyway.
  container:HookScript("OnSizeChanged", function(_, width)
    if width and width > 0 then view.width = width end
    if shown() then paint() end
  end)
  if Theme.OnRescale then Theme.OnRescale(function() if shown() then paint() end end) end
end

-- One more repaint SPEED_S on while Core/ForeverUpgrades.lua says weapon speeds are still being
-- read (r.speedPending), and only while that count shrinks, so a speed the client never tells
-- cannot keep the tab rebuilding.
local function chaseSpeed(r)
  local n = tonumber(r.speedPending) or 0
  if n <= 0 then repaint.speedLast = nil return end
  if repaint.speedDue or (repaint.speedLast ~= nil and n >= repaint.speedLast) then return end
  local timer = _G.C_Timer
  if not (timer and timer.After) then return end
  repaint.speedLast, repaint.speedDue = n, true
  timer.After(HD.SPEED_S, function()
    repaint.speedDue = false
    Hero.RefreshIfShown(true)
  end)
end

--- Paints `r` (GC.ForeverUpgrades.Current's answer) as of `now`: Show and RefreshIfShown build it
--- and hand it here, and so does Core/ForeverScan.lua's post-scan update, which built it already.
function Hero.Render(r, now)
  state.r = r or current()
  state.now = now or time()
  repaint.ids = state.r.loadingIds
  paint()
  chaseSpeed(state.r)
end

function Hero.Show()
  if not view.container then return end
  view.container:Show()
  build()
  -- A fresh open always gets a fresh chance, whatever a previous visit's storm cap reached.
  repaint.stale, repaint.last, repaint.speedLast = 0, nil, nil
  view.restamp = true -- see put(): every string is drawn again after the hide
  Hero.Render(current(), time())
  view.restamp = false
end

function Hero.Hide()
  if view.container then view.container:Hide() end
end

-- notLoad: a repaint for another reason (the gold carried, a worn piece, a weight), which says
-- nothing about whether the items still loading answer, so it leaves the storm cap's count alone.
function Hero.RefreshIfShown(notLoad)
  if not shown() then return end
  local r = current()
  local loading = r.loading or 0
  -- A repaint that did not shrink the loading count is one item (or more) that still has not
  -- answered; after STALE_LIMIT of those in a row, stop chasing it until the tab reopens.
  if not notLoad then
    if repaint.last ~= nil and loading > 0 and loading >= repaint.last then
      repaint.stale = repaint.stale + 1
    else
      repaint.stale = 0
    end
    repaint.last = loading
  end
  Hero.Render(r, time())
end

-- One repaint half a second after the first answer, not one per answer; nothing at all while the
-- tab is not on screen.
local function repaintSoon(notLoad)
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  repaint.pending = true
  timer.After(HD.REPAINT_S, function()
    repaint.pending = false
    Hero.RefreshIfShown(notLoad)
  end)
end

-- GET_ITEM_INFO_RECEIVED: an item the last build counted as loading may have arrived. An answer for
-- an item the last build was not waiting on repaints nothing, and a storm that has stopped shrinking
-- the loading count gives up until the tab is opened again.
function Hero.OnItemInfo(itemID)
  if repaint.pending or not shown() then return end
  if repaint.ids and itemID ~= nil and not repaint.ids[itemID] then return end
  if repaint.stale >= HD.STALE_LIMIT then return end
  repaintSoon()
end

-- PLAYER_MONEY and PLAYER_EQUIPMENT_CHANGED: the gold carried or a worn piece moved, and the rows
-- are weighed against both. The same single repaint half a second on, only while the tab is up.
function Hero.OnChange()
  if repaint.pending or not shown() then return end
  repaintSoon(true)
end

--- /gc upgrades: the GoldCap window, shown if it is hidden, on HERO. Away from the auction house too.
function Hero.Open()
  local S = GC.Sniper
  if not (S and S.ShowView) then return end
  if S.IsWindowShown and not S.IsWindowShown() and S.Toggle then S.Toggle() end
  S.ShowView("hero")
end
