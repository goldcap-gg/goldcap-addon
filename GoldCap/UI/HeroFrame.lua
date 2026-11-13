local _, GC = ...

-- WoW: Forever's HERO tab, read like the character sheet (the HERO plan's Task 8b and the board the
-- owner approved, "6. v2", 2026-11-13): the player's own paper doll, each slot showing the piece
-- ticked to buy there or what is worn; a panel listing the selected slot's choices from
-- Core/ForeverUpgrades.lua with a tick each; and a bar that counts only the ticked pieces. The ticks
-- start as the best set the gold carried pays for, and a slot the player ticked keeps the player's
-- tick through rebuilds. The stat weights and the gold toward a mount open over the slot panel. Only
-- GoldCap_Camelot.toc loads this file, and it adds its own rail entry as it loads, so retail's rail
-- keeps its four tabs.
--
-- A tab of the GoldCap window as Sold is (UI/SoldFrame.lua): Attach builds its container over the
-- same region, Show and Hide follow the rail, RefreshIfShown repaints it while it is on screen, and
-- a re-show writes every string again (docs/addon/AGENTS.md "Text"). Built from the kit: cards,
-- buttons, chips and item icons (Theme.Parts). Nothing is cut: names, gains, notes and headings wrap
-- and their row, the panel or the bar grows; buttons and tags are as wide as their words, measured
-- at each paint. The tab scores nothing itself: it reads Build's slots and set.
--
-- It never bids and makes no auction-house call: "Add N to BUY" writes a BUY list (Hero.AddToBuy)
-- and opens the BUY tab, whose own press buys. It reads only saved data and the character, so it
-- works away from the auction house.
GC.Hero = GC.Hero or {}
local Hero = GC.Hero

-- The rail's fifth tab (UI/Theme.lua's RAIL_ORDER) and its icon in the Classic skin, an item icon
-- both clients have (UI/Kit/Textures.lua's T.CLASSIC.icons).
GC.Theme.RAIL_ORDER[#GC.Theme.RAIL_ORDER + 1] = { key = "hero", icon = "hero", label = "HERO" }
GC.Theme.CLASSIC.icons.hero = "Interface\\Icons\\INV_Sword_04"

local HD = {
  GAP = 10, SMALL = 6,     -- between the tab's blocks; between the parts of one
  WHO_ICON = 34, WHO_MIN = 150, CHIP_H = 34, CHIP_PAD = 9, CHIP_ICON = 20, -- the top line
  -- The doll: a slot's frame (RING) and the selected one's glow (GLOW) stay inside the gap between it
  -- and the next, and its check and price inside its own square. SLOT_MAX is the most DOLL_W holds
  -- with the three hands between the two columns: (DOLL_W - 2 DOLL_PAD - 2 MODEL_GAP - 2 HAND_GAP) / 5.
  DOLL_W = 260, DOLL_PAD = 8, SLOT_GAP = 6, SLOT_MIN = 20, SLOT_MAX = 42, HAND_GAP = 6, MODEL_GAP = 9,
  RING = 2, GLOW = 3, BADGE = 14, BADGE_GLYPH = 10, PORTRAIT = 64,
  PAD = 12, HEAD_ICON = 34, LIST_GUTTER = 22, -- the slot panel
  OPT_PAD_X = 8, OPT_PAD_Y = 6, OPT_GAP = 4, BOX = 16, BOX_GLYPH = 12, OPT_ICON = 28, TEXT_MIN = 110,
  BAR_PAD = 8, BAR_TEXT_MIN = 150, BAR_BTN_H = 32, BAR_BTN_W = 120,
  BTN_H = 26, -- plaque's 12px caps stay under half the height
  PANEL_W = 336, PANEL_PAD = 12, PANEL_HEAD_H = 58, PANEL_FOOT_H = 48, PANEL_GUTTER = 22, BOX_W = 62,
  COST_W = 92, PANEL_ICON = 26, LINE_ICON = 22,
  HEIGHT = 480, -- the tab's height until the client has laid the container out
  STALE_LIMIT = 6, REPAINT_S = 0.5, SPEED_S = 0.2, TYPE_S = 0.4,
  SELF_S = 1, SELF_MAX = 15, -- the tab's own rebuild while items load: once a second, so many a Show
}
Hero.C = HD

-- Every widget the tab owns, and what it last painted: fields on GC.Hero so the module's own spec
-- reads them without reaching into upvalues; nothing else reads them.
local view = {}
Hero._view = view
-- The result painted (r), when (now), the panel open ("weights", "mount" or nil), the road to a
-- mount read this paint, the doll slot selected (sel, an inventory slot; selByHand once the player
-- clicked one), and the ticks: touched[group] is the player's own (an item string, or false for
-- "keep"), kept for the session; ticked[group] the piece each group has ticked this paint,
-- tickedList those in the result's slot order, options[group] each slot's choices as listed.
local state = { touched = {} }
Hero._state = state
-- The repaint rules, moved over from the old window unchanged (Hero.OnItemInfo and below), and the
-- tab's own rebuild while items load (selfRefresh): gen is bumped by every Show and Hide, so a tick
-- of an older chain does nothing; selfCount counts this Show's ticks; selfDue, one on its way.
local repaint = { stale = 0, gen = 0, selfCount = 0 }
Hero._repaint = repaint

local Theme, KP

-- Real WoW icons for what the panels count: items and spells both clients have.
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
-- The paper doll's slots in the client's own order (Forever's Camelot/PaperDollFrame.xml): eight
-- down the left, eight down the right, the three hands under the character. Each: the inventory
-- slot, its name for C_PaperDollInfo.GetInventorySlotInfo (whose texture is the empty slot's art),
-- the client's own name for it (an INVTYPE_* global), and its column.
local DOLL = {
  { 1, "HeadSlot", "INVTYPE_HEAD", "L" }, { 2, "NeckSlot", "INVTYPE_NECK", "L" },
  { 3, "ShoulderSlot", "INVTYPE_SHOULDER", "L" }, { 15, "BackSlot", "INVTYPE_CLOAK", "L" },
  { 5, "ChestSlot", "INVTYPE_CHEST", "L" }, { 4, "ShirtSlot", "INVTYPE_BODY", "L" },
  { 19, "TabardSlot", "INVTYPE_TABARD", "L" }, { 9, "WristSlot", "INVTYPE_WRIST", "L" },
  { 10, "HandsSlot", "INVTYPE_HAND", "R" }, { 6, "WaistSlot", "INVTYPE_WAIST", "R" },
  { 7, "LegsSlot", "INVTYPE_LEGS", "R" }, { 8, "FeetSlot", "INVTYPE_FEET", "R" },
  { 11, "Finger0Slot", "INVTYPE_FINGER", "R" }, { 12, "Finger1Slot", "INVTYPE_FINGER", "R" },
  { 13, "Trinket0Slot", "INVTYPE_TRINKET", "R" }, { 14, "Trinket1Slot", "INVTYPE_TRINKET", "R" },
  { 16, "MainHandSlot", "INVTYPE_WEAPONMAINHAND", "H" }, { 17, "SecondaryHandSlot", "INVTYPE_WEAPONOFFHAND", "H" },
  { 18, "RangedSlot", "INVTYPE_RANGED", "H" },
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

-- The paper doll's empty-slot art for a slot, by its name ("HeadSlot"), or nil.
local function slotArt(name)
  local api = _G.C_PaperDollInfo
  local call = (api and api.GetInventorySlotInfo) or _G.GetInventorySlotInfo
  if type(call) ~= "function" or not name then return nil end
  local ok, _, texture = pcall(call, name)
  return ok and texture or nil
end

-- What the character wears in each of the doll's slots (view.worn[inventory slot], a link), read
-- once a paint, and a line of them all that changes when any of them does (view.wornSig).
local function readWorn()
  local worn, parts = {}, {}
  for i, e in ipairs(DOLL) do
    local ok, link = pcall(_G.GetInventoryItemLink, "player", e[1])
    worn[e[1]] = ok and type(link) == "string" and link or nil
    parts[i] = worn[e[1]] or "-"
  end
  view.worn, view.wornSig = worn, table.concat(parts, "\n")
end

-- The gold toward a mount (GC.ForeverRoad.Snapshot), read as the tab is built from a new result or
-- the riding cost changes, not on every paint: it walks the bags.
local function readRoad()
  state.road = GC.ForeverRoad and GC.ForeverRoad.Snapshot and GC.ForeverRoad.Snapshot() or nil
end

local function current()
  local U = GC.ForeverUpgrades
  local r = U and U.Current and U.Current() or nil
  return r or { slots = {}, loading = 0, noScan = true }
end

local function shown()
  return view.container ~= nil and view.doll ~= nil and view.container:IsVisible() == true
end

-- Whether the tab is on screen: Core/ForeverScan.lua's post-scan update builds with the tooltip
-- pass only then, and hands this tab its result.
function Hero.IsShown() return shown() end

local function carried()
  return state.road and state.road.money or moneyOf()
end

-- The tooltip of the piece under the cursor (self.tipLink, a doll slot's or an option's): the item's
-- own, beside the window rather than over what it describes (Theme.ItemTooltipOutside), with
-- GoldCap's own lines under it (UI/Tooltip.lua).
local function pieceTip(self)
  if not (self.tipLink and GameTooltip and view.container) then return end
  Theme.ItemTooltipOutside(self, view.container:GetParent())
  GameTooltip:SetHyperlink(self.tipLink)
  GameTooltip:Show()
end

local function hideTip()
  if GameTooltip then GameTooltip:Hide() end
end

local paint -- forward: the whole tab from the last result (below)

-- Ticks ----------------------------------------------------------------------------------

-- The slot's candidate the set picked (r.set.picks, by item string), or nil.
local function setPickOf(r, s)
  local p = r.set and r.set.picks and r.set.picks[s.group]
  if not p then return nil end
  if s.best and s.best.itemString == p.itemString then return s.best end
  for _, a in ipairs(s.alts or {}) do
    if a.itemString == p.itemString then return a end
  end
  return nil
end

-- A slot's choices as its panel lists them: the set's pick, the strongest, then the other choices
-- by what they add (ties to the lower price, then the item string, as Build orders them).
local function optionsOf(s, pick)
  local out, seen, rest = {}, {}, {}
  local function add(c)
    if c and not seen[c.itemString] then
      seen[c.itemString] = true
      out[#out + 1] = c
    end
  end
  add(pick)
  add(s.best)
  for _, a in ipairs(s.alts or {}) do
    if not seen[a.itemString] then rest[#rest + 1] = a end
  end
  table.sort(rest, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    if a.unit ~= b.unit then return a.unit < b.unit end
    return a.itemString < b.itemString
  end)
  for _, a in ipairs(rest) do add(a) end
  return out
end

-- Which piece each group has ticked, from the player's own ticks and the set: a group the player
-- touched keeps its tick while that item string is still among its choices, and follows the set
-- again once it is not; "keep" stays kept; a group nobody touched follows the set. The hands keep
-- BestSet's rules: one lot fills one hand, a two-hander both. Ticking keeps them (Hero tick below);
-- a clash can only come from a rebuild moving the set's pick against a hand the player ticked, and
-- then the hand that follows the set lets its piece go.
local function resolve(r)
  local touched, ticked, options = state.touched, {}, {}
  for _, s in ipairs(r.slots or {}) do
    local pick = setPickOf(r, s)
    local list = optionsOf(s, pick)
    options[s.group] = list
    local want = touched[s.group]
    if type(want) == "string" then
      for _, c in ipairs(list) do
        if c.itemString == want then ticked[s.group] = c end
      end
      if not ticked[s.group] then
        touched[s.group] = nil
        want = nil
      end
    end
    if want == nil then ticked[s.group] = pick end
  end
  -- A slot gone from the build has none of its choices left: a piece ticked there is forgotten
  -- with it, so its slot follows the set when it comes back; a "keep" stays kept.
  for group, want in pairs(touched) do
    if type(want) == "string" and options[group] == nil then touched[group] = nil end
  end
  local m, o = ticked.MAINHAND, ticked.OFFHAND
  if m and o and (m.itemString == o.itemString or m.twoHand) then
    if touched.MAINHAND == nil then ticked.MAINHAND = nil else ticked.OFFHAND = nil end
  end
  local list = {}
  for _, s in ipairs(r.slots or {}) do
    if ticked[s.group] then list[#list + 1] = ticked[s.group] end
  end
  state.ticked, state.options, state.tickedList = ticked, options, list
end

-- The player ticks `c` for `group`, or "keep" (nil): the rest of the slot unticks. In the hands, a
-- piece ticked in one unticks the same item string in the other, a two-hander unticks the off hand,
-- and an off-hand piece unticks a two-hander; the hand let go keeps what it wears.
local function tick(group, c)
  local touched, ticked = state.touched, state.ticked or {}
  touched[group] = c and c.itemString or false
  if c and (group == "MAINHAND" or group == "OFFHAND") then
    local other = group == "MAINHAND" and "OFFHAND" or "MAINHAND"
    local o = ticked[other]
    local main = group == "MAINHAND" and c or o
    if o and (o.itemString == c.itemString or (main and main.twoHand)) then touched[other] = false end
  end
  paint()
end

local function anyTouched() return next(state.touched) ~= nil end

-- The group a doll slot's choices come from (GC.ForeverUpgrades.GROUPS' slots), or nil for one
-- that has none: the shirt, the tabard, the trinkets.
local function groupAt(inv)
  for _, g in ipairs(GC.ForeverUpgrades and GC.ForeverUpgrades.GROUPS or {}) do
    for _, slot in ipairs(g.slots) do
      if slot == inv then return g.key end
    end
  end
  return nil
end

-- The doll slot selected: the one the player clicked; else, at each paint, the first slot with
-- choices in the doll's order, or the first slot.
local function pickSelection()
  if state.selByHand and state.sel then return end
  state.sel = DOLL[1][1]
  for _, e in ipairs(DOLL) do
    if view.at[e[1]] then
      state.sel = e[1]
      return
    end
  end
end

-- The class --------------------------------------------------------------------------------

-- The class's own icon (GetClassAtlas, the atlas Forever's character creation draws), or nil where
-- the client has no such atlas.
local function classAtlas(file)
  if not file then return nil end
  local get = _G.GetClassAtlas
  local atlas = type(get) == "function" and get(file:lower()) or ("classicon-" .. file:lower())
  local tex = _G.C_Texture
  if tex and tex.GetAtlasInfo and not tex.GetAtlasInfo(atlas) then return nil end
  return atlas
end

-- The class's icon at the head of the top line, in its colour's frame; hidden without an atlas.
local function paintClassIcon(s, file, colour)
  local atlas = classAtlas(file)
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

-- The top line ------------------------------------------------------------------------------

-- Who looks (the class's icon, its name and level, the scan's age and any note about the scan),
-- and at the right the gold toward a mount, a chip that opens its panel, and the button that opens
-- the stat weights.
local function createTop(container)
  local t = {}
  t.classEdge = container:CreateTexture(nil, "BORDER")
  t.classEdge:SetSize(HD.WHO_ICON, HD.WHO_ICON)
  t.classIcon = container:CreateTexture(nil, "ARTWORK")
  t.classIcon:SetPoint("TOPLEFT", t.classEdge, "TOPLEFT", 1, -1)
  t.classIcon:SetPoint("BOTTOMRIGHT", t.classEdge, "BOTTOMRIGHT", -1, 1)
  t.name = Theme.Label(container, 15)
  t.name:SetJustifyH("LEFT")
  setColor(t.name, Theme.color.fg)
  t.sub = Theme.Num(container, 10)
  t.sub:SetJustifyH("LEFT")
  setColor(t.sub, Theme.color.fgDim)
  t.note = Theme.Label(container, 10)
  t.note:SetJustifyH("LEFT")
  setColor(t.note, Theme.tier.SUSPECT)
  -- The mount chip: a quiet plate (the engine's wash under the cursor), its fill under it.
  local m = { frame = KP.plate(container, Theme.color.border, "plaque") }
  local ph = Theme.color.panelHi or Theme.color.panel
  Theme.ShapeTexture(m.frame, "BACKGROUND", "control", { ph[1], ph[2], ph[3], 1 }):SetAllPoints(m.frame)
  m.icon = KP.NewIcon(m.frame, HD.CHIP_ICON)
  m.icon.edge:SetPoint("LEFT", m.frame, "LEFT", HD.CHIP_PAD, 0)
  m.label = Theme.Num(m.frame, 9, true)
  m.label:SetJustifyH("LEFT")
  setColor(m.label, Theme.color.fgDim)
  m.value = Theme.Num(m.frame, 12, true)
  m.value:SetJustifyH("LEFT")
  setColor(m.value, Theme.color.fg)
  m.frame:SetScript("OnClick", function() Hero.TogglePanel("mount") end)
  t.mount = m
  t.weights = Theme.Button(container, "ghost", "plaque")
  t.weights:SetScript("OnClick", function() Hero.TogglePanel("weights") end)
  return t
end

-- The chip's words and its width: the gold carried and in the bags, of the riding cost.
local function paintChip(m)
  local road = state.road
  local have = road and (road.money or 0) + (road.bags or 0) or moneyOf()
  local cost = road and tonumber(road.cost) or nil
  KP.PaintIcon(m.icon, nil, ICON.mount)
  put(m.label, GC.Util.Upper(GC.L["Mount at 40"]))
  put(m.value, cost and cost > 0 and GC.L["%s of %s"]:format(coins(have), coins(cost)) or coins(have))
  local textW = math.max(hug(m.label), hug(m.value))
  local textX = HD.CHIP_PAD + HD.CHIP_ICON + 7
  local textH = heightOf(m.label) + 1 + heightOf(m.value)
  local h = math.max(HD.CHIP_H, textH + 8)
  m.label:ClearAllPoints()
  m.label:SetPoint("TOPLEFT", m.frame, "TOPLEFT", textX, -math.floor((h - textH) / 2))
  m.value:ClearAllPoints()
  m.value:SetPoint("TOPLEFT", m.label, "BOTTOMLEFT", 0, -1)
  local gold = Theme.color.gold
  local ring = state.panel == "mount" and { gold[1], gold[2], gold[3], 0.6 } or Theme.color.border
  m.frame.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4] or 1)
  local w = textX + textW + HD.CHIP_PAD
  m.frame:SetSize(w, h)
  return w, h
end

-- The top line at `width`: who looks at the left, the chip and the button at the right; on one
-- line while the name keeps WHO_MIN beside them, else the chip and the button on a line under it.
-- Answers its height.
local function layoutTop(r, width)
  local t = view.top
  local className, file = classOf()
  local rc = file and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[file] or nil
  local colour = rc and { rc.r, rc.g, rc.b } or Theme.color.goldHi
  local withIcon = paintClassIcon(t, file, colour)
  local level = levelOf()
  local who = className and GC.Util.Colored(colour, className) or ""
  put(t.name, level and GC.L["%s · level %d"]:format(who, level) or who)
  local age = ageWords(r, state.now)
  if age then put(t.sub, GC.L["Scan %s ago"]:format(age)) else t.sub:Hide() end
  local notes = {}
  if r.stale then notes[#notes + 1] = GC.L["Scan again to read each version's own stats."] end
  if (r.loading or 0) > 0 then
    notes[#notes + 1] = GC.L["Items still loading: %d. Open this again in a moment."]:format(r.loading)
  end
  if #notes > 0 then put(t.note, table.concat(notes, " ")) else t.note:Hide() end

  local chipW, chipH = paintChip(t.mount)
  label(t.weights, GC.L["Stat weights"], 0)
  t.weights:SetVariant(state.panel == "weights" and "active" or "ghost")
  t.weights:SetHeight(chipH)
  local partsW = chipW + HD.SMALL + (t.weights:GetWidth() or 0)
  local whoRoom = width - partsW - HD.GAP
  local oneLine = whoRoom >= HD.WHO_MIN
  local whoW = oneLine and whoRoom or width
  local textX = withIcon and HD.WHO_ICON + 9 or 0
  local nameH = wrapTo(t.name, whoW - textX)
  local subH = t.sub:IsShown() and wrapTo(t.sub, whoW - textX) or 0
  local noteH = t.note:IsShown() and wrapTo(t.note, whoW - textX) or 0
  local textH = nameH + (subH > 0 and 2 + subH or 0) + (noteH > 0 and 2 + noteH or 0)
  local whoH = math.max(withIcon and HD.WHO_ICON or 0, textH)
  local band = oneLine and math.max(whoH, chipH) or whoH
  local whoTop = math.floor((band - whoH) / 2)
  t.classEdge:ClearAllPoints()
  t.classEdge:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -(whoTop + math.floor((whoH - HD.WHO_ICON) / 2)))
  t.name:ClearAllPoints()
  t.name:SetPoint("TOPLEFT", view.container, "TOPLEFT", textX, -(whoTop + math.floor((whoH - textH) / 2)))
  t.sub:ClearAllPoints()
  t.sub:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -2)
  t.note:ClearAllPoints()
  t.note:SetPoint("TOPLEFT", subH > 0 and t.sub or t.name, "BOTTOMLEFT", 0, -2)
  -- The chip and the button, right to left, centred in the band; under it when the line is short.
  local y = oneLine and math.floor((band - chipH) / 2) or whoH + HD.SMALL
  local x = width - (t.weights:GetWidth() or 0)
  t.weights:ClearAllPoints()
  t.weights:SetPoint("TOPLEFT", view.container, "TOPLEFT", oneLine and x or chipW + HD.SMALL, -y)
  t.mount.frame:ClearAllPoints()
  t.mount.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", oneLine and x - HD.SMALL - chipW or 0, -y)
  return oneLine and band or y + chipH
end

-- The doll ---------------------------------------------------------------------------------

-- A slot of the doll: the piece ticked there or what is worn, in a frame that says which (green:
-- ticked to buy; thin gold: choices, nothing ticked), a check and the price over a ticked piece,
-- both inside the slot's own square, and a gold glow while it is the slot the panel lists. Hover is
-- the engine's HIGHLIGHT layer (docs: "Buttons and hover"); the glow is state.
local function newSlot(parent, e)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp")
  b:EnableMouse(true)
  b.isHeroPiece = true
  b.invSlot, b.art, b.labelKey = e[1], e[2], e[3]
  local gold = Theme.color.gold
  b.glow = Theme.Solid(b, "BACKGROUND", { gold[1], gold[2], gold[3], 0.45 })
  b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -HD.GLOW, HD.GLOW)
  b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", HD.GLOW, -HD.GLOW)
  b.frameRing = b:CreateTexture(nil, "BORDER", nil, -2)
  b.frameRing:SetPoint("TOPLEFT", b, "TOPLEFT", -HD.RING, HD.RING)
  b.frameRing:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", HD.RING, -HD.RING)
  b.icon = KP.NewIcon(b, HD.SLOT_MAX)
  b.icon.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  local hc = Theme.color.hover
  b.hover = b:CreateTexture(nil, "HIGHLIGHT")
  b.hover:SetAllPoints()
  b.hover:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.16)
  b.badge = Theme.ShapeTexture(b, "OVERLAY", "chip", Theme.color.green)
  b.badge:SetSize(HD.BADGE, HD.BADGE)
  b.badge:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  b.glyph = b:CreateTexture(nil, "OVERLAY", nil, 3)
  b.glyph:SetSize(HD.BADGE_GLYPH, HD.BADGE_GLYPH)
  b.glyph:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
  Theme.SetIcon(b.glyph, "check", GC.Kit.Tokens.color.onGold)
  -- The price as the game writes a stack's count over its slot: the condensed heavy face, outlined.
  b.price = b:CreateFontString(nil, "OVERLAY")
  b.price:SetFont(Theme.FONT_HEAD_HEAVY, 10 * Theme.Scale(), "OUTLINE")
  if Theme.TrackFont then
    Theme.TrackFont(b.price, { role = "count", path = Theme.FONT_HEAD_HEAVY, size = 10, flags = "OUTLINE" })
  end
  b.price:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.price:SetJustifyH("RIGHT")
  b:SetScript("OnEnter", pieceTip)
  b:SetScript("OnLeave", hideTip)
  -- A modified click is the client's (shift links the piece shown, ctrl tries it on); a plain one
  -- lists the slot's choices.
  b:SetScript("OnClick", function(self)
    local handle = _G.HandleModifiedItemClick
    if self.tipLink and type(handle) == "function" and handle(self.tipLink) then return end
    state.sel, state.selByHand = self.invSlot, true
    paint()
  end)
  return b
end

-- The doll's frame, its hint, the character, and a slot per entry of DOLL.
local function createDoll(container)
  local d = { frame = Theme.Card(container, Theme.color.bg, Theme.color.border), slots = {}, order = {} }
  d.hint = Theme.Label(d.frame, 11)
  d.hint:SetJustifyH("CENTER")
  setColor(d.hint, Theme.color.fgMuted)
  -- The character: a PlayerModel, a frame type WoW: Forever's own UI builds (Blizzard_FrameXML's
  -- TalkingHeadUI.xml, loaded on the mainline family Forever belongs to), dressed with SetUnit
  -- (FrameAPICharacterModelBase). Made in a pcall: a client without it shows the class's icon, and
  -- the tab works either way. It takes no clicks.
  local ok, model = pcall(CreateFrame, "PlayerModel", nil, d.frame)
  if ok and type(model) == "table" and type(model.SetUnit) == "function" then
    d.model = model
  elseif ok and type(model) == "table" and model.Hide then
    model:Hide()
  end
  d.portrait = d.frame:CreateTexture(nil, "ARTWORK")
  d.portrait:Hide()
  for _, e in ipairs(DOLL) do
    d.slots[e[1]] = newSlot(d.frame, e)
    d.order[#d.order + 1] = e[1]
  end
  return d
end

-- Dresses the character as it stands now (SetUnit answers whether it took); the class's icon where
-- there is no model or it did not.
local function dress()
  local d = view.doll
  local live = false
  if d.model then
    local ok, took = pcall(d.model.SetUnit, d.model, "player")
    live = ok and took ~= false
    d.model:SetShown(live)
  end
  local atlas = classAtlas(select(2, classOf()))
  if atlas and not live then d.portrait:SetAtlas(atlas) end
  d.portrait:SetShown(not live and atlas ~= nil)
end

-- One slot as this paint sees it: what it shows, its frame, its marks. Its icon wears no quality
-- edge (KP.PaintIcon without the item's id draws the untinted one): on the doll, green means ticked.
local function paintSlot(b)
  local s = view.at[b.invSlot]
  local c = s and state.ticked[s.group] or nil
  local worn = view.worn[b.invSlot]
  b.tipLink = c and (c.link or c.itemString) or worn
  if c then
    KP.PaintIcon(b.icon, nil, itemIcon(c.itemID))
  elseif worn then
    KP.PaintIcon(b.icon, nil, itemIcon(itemIdOf(worn)))
  else
    KP.PaintIcon(b.icon, nil, slotArt(b.art))
  end
  b.icon.icon:SetAlpha((c or worn) and 1 or 0.55)
  local ring = c and Theme.color.green or s and Theme.color.gold or GC.Kit.Tokens.ink(0.14)
  b.frameRing:SetColorTexture(ring[1], ring[2], ring[3], ring[4] or 1)
  b.badge:SetShown(c ~= nil)
  b.glyph:SetShown(c ~= nil)
  if c then put(b.price, GC.Util.FormatGoldCeil(c.unit)) else b.price:Hide() end
  b.glow:SetShown(b.invSlot == state.sel)
end

-- The doll at the tab's left, `midTop` down and `midH` tall: the hint over it; eight slots down
-- each side, as large as the height lets them be; the character between them; the three hands in
-- a row under it.
local function layoutDoll(midTop, midH)
  local d = view.doll
  d.frame:ClearAllPoints()
  d.frame:SetPoint("TOPLEFT", view.container, "TOPLEFT", 0, -midTop)
  d.frame:SetSize(HD.DOLL_W, midH)
  put(d.hint, GC.L["Click a slot to see what you can buy for it."])
  local hintH = wrapTo(d.hint, HD.DOLL_W - 2 * HD.DOLL_PAD)
  d.hint:ClearAllPoints()
  d.hint:SetPoint("TOP", d.frame, "TOP", 0, -HD.DOLL_PAD)
  local top = HD.DOLL_PAD + hintH + HD.SMALL
  local size = math.floor((midH - top - HD.DOLL_PAD - 7 * HD.SLOT_GAP) / 8)
  size = math.max(HD.SLOT_MIN, math.min(HD.SLOT_MAX, size))
  -- The two columns stand centred in the height left under the hint; the hands in a row level with
  -- their last slots, the character between them all.
  local block = 8 * size + 7 * HD.SLOT_GAP
  local colTop = top + math.max(0, math.floor((midH - top - HD.DOLL_PAD - block) / 2))
  local rightX = HD.DOLL_W - HD.DOLL_PAD - size
  local handsW = 3 * size + 2 * HD.HAND_GAP
  local handX, handY = math.floor((HD.DOLL_W - handsW) / 2), colTop + block - size
  local row = { L = 0, R = 0, H = 0 }
  for _, e in ipairs(DOLL) do
    local b, col = d.slots[e[1]], e[4]
    local x, y
    if col == "H" then
      x, y = handX + row.H * (size + HD.HAND_GAP), handY
    else
      x, y = col == "L" and HD.DOLL_PAD or rightX, colTop + row[col] * (size + HD.SLOT_GAP)
    end
    row[col] = row[col] + 1
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", d.frame, "TOPLEFT", x, -y)
    b:SetSize(size, size)
    b.icon.edge:SetSize(size, size)
    paintSlot(b)
    b:Show()
  end
  local side = HD.DOLL_PAD + size + HD.MODEL_GAP
  local modelH = math.max(1, handY - HD.HAND_GAP - colTop)
  if d.model then
    d.model:ClearAllPoints()
    d.model:SetPoint("TOPLEFT", d.frame, "TOPLEFT", side, -colTop)
    d.model:SetSize(math.max(1, HD.DOLL_W - 2 * side), modelH)
  end
  local portrait = math.max(1, math.min(HD.PORTRAIT, HD.DOLL_W - 2 * side, modelH))
  d.portrait:ClearAllPoints()
  d.portrait:SetPoint("CENTER", d.frame, "TOP", 0, -(colTop + math.floor(modelH / 2)))
  d.portrait:SetSize(portrait, portrait)
end

-- The slot panel ----------------------------------------------------------------------------

-- The game's own red (RED_FONT_COLOR: a tooltip's level line you cannot meet yet, a buyout the AH
-- says you cannot pay), the kit's where the client has none.
local function gameRed()
  local c = _G.RED_FONT_COLOR
  if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b, 1 } end
  return Theme.color.red
end

-- A piece's icon as the game draws one you cannot use yet: the art tinted red, as Forever's own
-- paper doll tints an equipped piece it cannot use (Blizzard_UIPanels_Game/Camelot/
-- PaperDollFrame.lua, SetItemButtonTextureVertexColor 0.9, 0, 0), with the level it waits for in
-- the corner a stack's count takes, in the client's red. The same in every skin. Anything else
-- untinted, with no number: a row's icon is reused from piece to piece.
local function markLevel(icon, later)
  if later then
    icon.icon:SetVertexColor(0.9, 0, 0, 1) -- untinted
    setColor(icon.count, gameRed())
  else
    icon.icon:SetVertexColor(1, 1, 1, 1) -- untinted
  end
  -- The count is the kit's: written, it is hidden and shown again on a re-show, as put() does.
  if view.restamp then icon.count:Hide() end
  icon.count:Show()
end

-- One option of the slot panel, two lines as the auction house lists a lot: a checkbox and the
-- piece's icon (marked when it waits for a level, markLevel), then its name with its price at the
-- right, and under them what it adds, across the whole width. The whole row is the click that ticks
-- it; hover is the engine's HIGHLIGHT layer, a ticked row is green as state.
local function newOption(parent)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp")
  b:EnableMouse(true)
  b.isHeroPiece = true
  local zc, gb, green, hc = Theme.color.zebra, Theme.color.border, Theme.color.green, Theme.color.hover
  b.card = Theme.ShapeTexture(b, "BACKGROUND", "control", { zc[1], zc[2], zc[3], zc[4] or 0.035 })
  b.card:SetAllPoints()
  b.cardRing = Theme.ShapeTexture(b, "BORDER", "control", { gb[1], gb[2], gb[3], gb[4] or 0.075 }, true)
  b.cardRing:SetAllPoints()
  b.onWash = Theme.ShapeTexture(b, "BACKGROUND", "control", { green[1], green[2], green[3], 0.10 })
  b.onWash:SetAllPoints()
  b.onRing = Theme.ShapeTexture(b, "ARTWORK", "control", { green[1], green[2], green[3], 0.85 }, true)
  b.onRing:SetAllPoints()
  b.hover = b:CreateTexture(nil, "HIGHLIGHT")
  Theme.SetShape(b.hover, "control")
  b.hover:SetAllPoints()
  b.hover:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  local dim = Theme.color.fgDim
  b.box = Theme.ShapeTexture(b, "ARTWORK", "chip", { dim[1], dim[2], dim[3], 0.9 }, true)
  b.box:SetSize(HD.BOX, HD.BOX)
  b.boxFill = Theme.ShapeTexture(b, "ARTWORK", "chip", green)
  b.boxFill:SetAllPoints(b.box)
  b.boxGlyph = b:CreateTexture(nil, "OVERLAY")
  b.boxGlyph:SetSize(HD.BOX_GLYPH, HD.BOX_GLYPH)
  b.boxGlyph:SetPoint("CENTER", b.box, "CENTER", 0, 0)
  Theme.SetIcon(b.boxGlyph, "check", GC.Kit.Tokens.color.onGold)
  b.icon = KP.NewIcon(b, HD.OPT_ICON, true)
  b.name = Theme.Label(b, 13)
  b.name:SetJustifyH("LEFT")
  b.gain = Theme.Label(b, 11)
  b.gain:SetJustifyH("LEFT")
  b.price = Theme.Num(b, 13, true)
  b.price:SetJustifyH("RIGHT")
  b:SetScript("OnEnter", pieceTip)
  b:SetScript("OnLeave", hideTip)
  -- A modified click is the client's (shift links the piece, ctrl tries it on); a plain one ticks it.
  b:SetScript("OnClick", function(self)
    local handle = _G.HandleModifiedItemClick
    if self.cand and type(handle) == "function" and handle(self.cand.link or self.cand.itemString) then return end
    tick(self.group, self.cand)
  end)
  return b
end

-- An option for `c`, or the row that buys nothing (c nil): `worn` its link, `art` the empty slot.
-- A price over the gold carried is red, as the AH paints a buyout you cannot pay.
local function paintOption(b, group, c, on, worn, art)
  b.group, b.cand = group, c
  b.tipLink = c and (c.link or c.itemString) or worn
  if c then
    KP.PaintIcon(b.icon, c.itemID, itemIcon(c.itemID), c.later)
    markLevel(b.icon, c.later)
    put(b.name, nameOf(c))
    setColor(b.name, qualityOf(c.itemID))
    local gains = gainText(c.diffs)
    if gains ~= "" then put(b.gain, gains) else b.gain:Hide() end
    put(b.price, coins(c.unit))
    setColor(b.price, c.overGold and gameRed() or Theme.color.fg)
  else
    local id = itemIdOf(worn)
    KP.PaintIcon(b.icon, id, (id and itemIcon(id)) or art)
    markLevel(b.icon, nil)
    put(b.name, worn and GC.L["Keep %s"]:format(nameOf({ link = worn, itemID = id })) or GC.L["Buy nothing here"])
    setColor(b.name, Theme.color.fgMuted)
    b.gain:Hide()
    b.price:Hide()
  end
  b.onWash:SetShown(on)
  b.onRing:SetShown(on)
  b.boxFill:SetShown(on)
  b.boxGlyph:SetShown(on)
  b:Show()
end

-- How a list lays its rows out at `width`: where the words start, and how wide the name runs beside
-- the price column, as wide as the list's widest price (measured over its first `n` rows). The
-- gains take the whole width under it. In a panel too narrow for the price beside the name and
-- TEXT_MIN of it, the price goes under the words.
local function listShape(width, rows, n)
  local priceW = 0
  for i = 1, n do
    if rows[i].price:IsShown() then priceW = math.max(priceW, hug(rows[i].price)) end
  end
  local textX = HD.OPT_PAD_X + HD.BOX + HD.SMALL + HD.OPT_ICON + HD.SMALL + 2
  local full = math.max(1, width - textX - HD.OPT_PAD_X)
  local shape = { textX = textX, full = full, nameW = priceW > 0 and full - HD.SMALL - priceW or full }
  if shape.nameW < HD.TEXT_MIN then shape.under, shape.nameW = true, full end
  return shape
end

-- An option in `shape`: its words wrap, never cut. Answers the height it needs; placeOption puts
-- it at the list's height.
local function layoutOption(b, shape)
  local at = {}
  local y = wrapTo(b.name, shape.nameW)
  if b.gain:IsShown() then
    at.gainY = y + 2
    y = at.gainY + wrapTo(b.gain, shape.full)
  end
  if b.price:IsShown() then
    if shape.under then
      at.priceY = y + 2
      y = at.priceY + heightOf(b.price)
    else
      at.priceY = 0
      y = math.max(y, heightOf(b.price))
    end
  end
  at.blockH = y
  b.at = at
  return math.max(HD.OPT_ICON, y) + 2 * HD.OPT_PAD_Y
end

-- An option `h` tall: its words in the middle of the row, the box and the icon too.
local function placeOption(b, shape, h)
  local at = b.at
  local top = HD.OPT_PAD_Y + math.floor((h - 2 * HD.OPT_PAD_Y - at.blockH) / 2)
  b.name:ClearAllPoints()
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", shape.textX, -top)
  if at.gainY then
    b.gain:ClearAllPoints()
    b.gain:SetPoint("TOPLEFT", b, "TOPLEFT", shape.textX, -(top + at.gainY))
  end
  if at.priceY then
    b.price:ClearAllPoints()
    if shape.under then
      b.price:SetPoint("TOPLEFT", b, "TOPLEFT", shape.textX, -(top + at.priceY))
    else
      b.price:SetPoint("TOPRIGHT", b, "TOPRIGHT", -HD.OPT_PAD_X, -(top + at.priceY))
    end
  end
  b.box:ClearAllPoints()
  b.box:SetPoint("LEFT", b, "TOPLEFT", HD.OPT_PAD_X, -math.floor(h / 2))
  b.icon.edge:ClearAllPoints()
  b.icon.edge:SetPoint("LEFT", b, "TOPLEFT", HD.OPT_PAD_X + HD.BOX + HD.SMALL, -math.floor(h / 2))
end

local function createPanel(container)
  local p = { frame = Theme.Card(container, Theme.color.panel, Theme.color.border), rows = {} }
  local f = p.frame
  p.icon = KP.NewIcon(f, HD.HEAD_ICON)
  p.icon.edge:SetPoint("TOPLEFT", f, "TOPLEFT", HD.PAD, -HD.PAD)
  p.title = Theme.Heading(f, 12)
  p.title:SetJustifyH("LEFT")
  setColor(p.title, Theme.color.goldHi)
  p.sub = Theme.Label(f, 12)
  p.sub:SetJustifyH("LEFT")
  setColor(p.sub, Theme.color.fgMuted)
  p.message = Theme.Label(f, 12)
  p.message:SetJustifyH("CENTER")
  setColor(p.message, Theme.color.fgMuted)
  -- The options scroll in the tab's own scroll frame, above the card it stands on.
  view.scroll:SetFrameLevel((f:GetFrameLevel() or 0) + 2)
  return p
end

-- Why the panel has nothing to list for the doll slot `inv`, or nil: a slot whose group waits for
-- the stats of what is worn there (Build's r.waiting) says so, not that nothing beats it.
local function emptyWhy(r, s, inv)
  if r.noScan then return GC.L["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] end
  if r.noStats then return GC.L["This client does not report item stats, so GoldCap cannot compare gear."] end
  if r.noWeights then return GC.L["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] end
  if s then return nil end
  local group = groupAt(inv)
  if group and r.waiting and r.waiting[group] then
    return GC.L["Still reading what you wear here. This fills in by itself."]
  end
  return GC.L["Nothing on the auction house beats what you wear at your level."]
end

-- The slot panel at `x`, `midTop` down, `w` wide and `midH` tall: the selected slot's head (what is
-- worn there) and its options, the set's pick first and "keep" last, every row of the list as tall
-- as its tallest.
local function layoutPanel(r, x, midTop, w, midH)
  local p, f = view.panel, view.panel.frame
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", view.container, "TOPLEFT", x, -midTop)
  f:SetSize(w, midH)
  local inv = state.sel
  local s = view.at[inv]
  local b = view.doll.slots[inv]
  local worn = (s and s.worn) or view.worn[inv]
  local wornID = itemIdOf(worn)
  KP.PaintIcon(p.icon, wornID, (wornID and itemIcon(wornID)) or slotArt(b.art))
  local labelKey = s and s.labelKey or b.labelKey
  put(p.title, GC.Util.Upper(_G[labelKey] or labelKey))
  if worn then
    put(p.sub, GC.L["You wear %s"]:format(GC.Util.Colored(Theme.color.fg, nameOf({ link = worn, itemID = wornID }))))
  else
    put(p.sub, GC.L["Nothing worn here"])
  end
  local textX = HD.PAD + HD.HEAD_ICON + HD.GAP
  local textW = w - textX - HD.PAD
  local th, sh = wrapTo(p.title, textW), wrapTo(p.sub, textW)
  local headH = math.max(HD.HEAD_ICON, th + 2 + sh)
  local top = HD.PAD + math.floor((headH - th - 2 - sh) / 2)
  p.title:ClearAllPoints()
  p.title:SetPoint("TOPLEFT", f, "TOPLEFT", textX, -top)
  p.sub:ClearAllPoints()
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -2)
  local y = HD.PAD + headH + HD.GAP
  local why = emptyWhy(r, s, inv)
  local rows = p.rows
  if why then
    for _, row in ipairs(rows) do row:Hide() end
    put(p.message, why)
    wrapTo(p.message, w - 2 * HD.PAD)
    p.message:ClearAllPoints()
    p.message:SetPoint("TOP", f, "TOP", 0, -(y + HD.SMALL))
    view.scroll:Hide()
    return
  end
  p.message:Hide()
  -- The list: its own scroll, inside the panel under the head.
  local scroll, content = view.scroll, view.content
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", HD.PAD, -y)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -HD.LIST_GUTTER, HD.PAD)
  scroll:Show()
  -- Another slot's list starts at its top: the set's pick first.
  if view.listFor ~= inv then
    view.listFor = inv
    scroll:SetVerticalScroll(0)
  end
  local listW = math.max(1, w - HD.PAD - HD.LIST_GUTTER)
  content:SetWidth(listW)
  local options = state.options[s.group] or {}
  local ticked = state.ticked[s.group]
  local n = #options + 1
  for i = #rows + 1, n do rows[i] = newOption(content) end
  for i, c in ipairs(options) do
    paintOption(rows[i], s.group, c, c == ticked)
  end
  paintOption(rows[n], s.group, nil, ticked == nil, worn, slotArt(b.art))
  local shape = listShape(listW, rows, n)
  local rowH = 0
  for i = 1, n do rowH = math.max(rowH, layoutOption(rows[i], shape)) end
  local ly = 0
  for i = 1, n do
    local row = rows[i]
    placeOption(row, shape, rowH)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -ly)
    row:SetSize(listW, rowH)
    ly = ly + rowH + HD.OPT_GAP
  end
  for i = n + 1, #rows do
    rows[i].cand, rows[i].tipLink = nil, nil
    rows[i]:Hide()
  end
  content:SetHeight(math.max(1, ly))
end

-- The bar ------------------------------------------------------------------------------------

-- What the ticked pieces come to, at the tab's foot, in one band: how many and what they add, who
-- ticked them (or that what is worn is still being read), what they cost and what that leaves of
-- the gold carried, and the one button that puts exactly them on a BUY list. The doll shows the
-- pieces themselves.
local function createBar(container)
  local gold, ph = Theme.color.gold, Theme.color.panelHi or Theme.color.panel
  local b = { frame = Theme.Card(container, { ph[1], ph[2], ph[3], 1 }, { gold[1], gold[2], gold[3], 0.35 }) }
  local f = b.frame
  f:EnableMouse(true)
  b.title = Theme.Label(f, 13)
  setColor(b.title, Theme.color.fg)
  b.sub = Theme.Label(f, 11)
  setColor(b.sub, Theme.color.fgMuted)
  for _, key in ipairs({ "cost", "left" }) do
    b[key .. "Head"] = Theme.Num(f, 9, true)
    b[key .. "Head"]:SetJustifyH("RIGHT")
    setColor(b[key .. "Head"], Theme.color.fgDim)
    b[key] = Theme.Num(f, key == "cost" and 15 or 13, true)
    b[key]:SetJustifyH("RIGHT")
  end
  b.add = Theme.Button(f, "primary", "plaque")
  b.add:SetHeight(HD.BAR_BTN_H)
  b.add:SetScript("OnClick", function()
    local list = state.tickedList
    if list and #list > 0 then Hero.AddToBuy(list) end
  end)
  return b
end

-- A figure under its heading, right-aligned at `right`, its top `y` down the bar.
local function placeFigure(head, value, f, right, y)
  head:ClearAllPoints()
  if head:IsShown() then
    head:SetPoint("TOPRIGHT", f, "TOPLEFT", right, -y)
    value:ClearAllPoints()
    value:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -2)
  else
    value:ClearAllPoints()
    value:SetPoint("TOPRIGHT", f, "TOPLEFT", right, -y)
  end
end

local function figureH(head, value)
  return (head:IsShown() and heightOf(head) + 2 or 0) + heightOf(value)
end

-- The bar at `width`: the words at the left, the figures and the button at the right, on one band
-- while the words keep BAR_TEXT_MIN beside them, else the figures and the button on a line under
-- the words. Its height follows the words. Answers it.
local function layoutBar(r, width)
  local b, f = view.bar, view.bar.frame
  local list = state.tickedList or {}
  local n = #list
  local cost, diffs = 0, {}
  for _, c in ipairs(list) do
    cost = cost + (tonumber(c.unit) or 0)
    for k, v in pairs(c.diffs or {}) do diffs[k] = (diffs[k] or 0) + v end
  end
  for k, v in pairs(diffs) do
    if v == 0 then diffs[k] = nil end
  end
  local carry = carried()
  local waiting = r.waiting and next(r.waiting) ~= nil
  if n > 0 then
    put(b.title, GC.L["%d ticked: %s"]:format(n, gainText(diffs)))
  else
    local none = r.set and not anyTouched()
    put(b.title, none and GC.L["Nothing on the auction house fits the gold you carry yet."] or GC.L["Nothing ticked"])
  end
  if waiting then
    put(b.sub, GC.L["Still reading what you wear: the picks may change"])
  elseif n == 0 then
    b.sub:Hide()
  elseif anyTouched() then
    put(b.sub, GC.L["Your own picks"])
  else
    put(b.sub, GC.L["Picked by GoldCap for the gold you carry"])
  end
  put(b.costHead, GC.Util.Upper(GC.L["Ticked cost"]))
  put(b.cost, coins(cost))
  setColor(b.cost, Theme.color.fg)
  local left = carry - cost
  if left >= 0 then
    put(b.leftHead, GC.Util.Upper(GC.L["Left after"]))
    put(b.left, coins(left))
    setColor(b.left, Theme.color.fgMuted)
  else
    b.leftHead:Hide()
    put(b.left, GC.L["Short by %s"]:format(coins(-left)))
    setColor(b.left, Theme.color.red)
  end
  label(b.add, GC.L["Add %d to BUY"]:format(n), HD.BAR_BTN_W)
  if n > 0 then b.add:Enable() else b.add:Disable() end

  local pad, addW = HD.BAR_PAD, b.add:GetWidth() or HD.BAR_BTN_W
  local costW = math.max(hug(b.cost), hug(b.costHead))
  local leftW = math.max(hug(b.left), b.leftHead:IsShown() and hug(b.leftHead) or 0)
  local figuresW = costW + HD.GAP + leftW + HD.GAP + addW
  local textW = width - 2 * pad - figuresW - HD.GAP
  local oneLine = textW >= HD.BAR_TEXT_MIN
  if not oneLine then textW = width - 2 * pad end
  local titleH = wrapTo(b.title, textW)
  local subH = b.sub:IsShown() and wrapTo(b.sub, textW) or 0
  local textH = titleH + (subH > 0 and 2 + subH or 0)
  local figH = math.max(figureH(b.costHead, b.cost), figureH(b.leftHead, b.left), HD.BAR_BTN_H)
  local tier1 = math.max(textH, oneLine and figH or 0)
  local h = oneLine and tier1 + 2 * pad or pad + tier1 + HD.GAP + figH + pad
  b.title:ClearAllPoints()
  b.title:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(pad + math.floor((tier1 - textH) / 2)))
  b.sub:ClearAllPoints()
  b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -2)
  local figMid = oneLine and pad + tier1 / 2 or pad + tier1 + HD.GAP + figH / 2
  b.add:ClearAllPoints()
  b.add:SetPoint("RIGHT", f, "TOPRIGHT", -pad, -figMid)
  local right = width - pad - addW - HD.GAP
  placeFigure(b.leftHead, b.left, f, right, math.floor(figMid - figureH(b.leftHead, b.left) / 2))
  right = right - leftW - HD.GAP
  placeFigure(b.costHead, b.cost, f, right, math.floor(figMid - figureH(b.costHead, b.cost) / 2))
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", view.container, "BOTTOMLEFT", 0, 0)
  f:SetSize(width, h)
  return h
end

-- The panels --------------------------------------------------------------------------------

local panelPaint = {} -- per panel key: function(p, width), set below

-- Where an open panel lives: over the slot panel's area, `dx` px right of it while it slides
-- (Theme.Slide), as the Sell inspector does.
local function placePanel(p, dx)
  if dx then p.dx = dx end
  local area = view.panel.frame
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", area, "TOPLEFT", p.dx or 0, 0)
  p:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", p.dx or 0, 0)
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

-- A weight typed in its box: read as /gc weights reads one (GC.ForeverUpgrades.ApplyWeights, a comma
-- taken for the decimal point), into a copy of the weights in force, so a stat with no box here
-- keeps its own; 0 takes the stat off. What cannot be read turns the box red and changes nothing.
local function onWeight(token, text)
  local p, class = prefs(), select(2, classOf())
  local well = view.panels.weights.boxes[token]
  if not (p and class and well) then return end
  text = trim(text)
  if text == "" then well:SetBad(false) return end
  local U = GC.ForeverUpgrades
  local new = U.ApplyWeights(U.WeightsFor(p, class), token .. " " .. text:gsub(",", "."))
  if not new then well:SetBad(true) return end
  well:SetBad(false)
  p.weights = type(p.weights) == "table" and p.weights or {}
  p.weights[class] = new
  rebuildSoon()
end

local function newWeightRow(p, token)
  local row = { frame = CreateFrame("Frame", nil, p.body), token = token }
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
  p.rows, p.pool, p.boxes = {}, {}, {}
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
  -- The class's own icon, as the top line draws it; the strength icon where the client has no such atlas.
  local bodyW = paintHead(p, width, {
    atlas = classAtlas(class), file = STAT_ICON.STR, edge = colour, titleColor = colour,
    title = GC.L["What counts for a %s"]:format(className or ""),
    sub = GC.L["The list changes as you type"] })
  local U = GC.ForeverUpgrades
  local weights = (class and U.WeightsFor(prefs() or {}, class)) or {}
  -- A row per stat, kept by its stat (p.pool) and laid out in this paint's order (p.rows): every
  -- one hidden first, so a stat that moved up the list or dropped off it is never left showing.
  local y = 0
  for _, row in pairs(p.pool) do row.frame:Hide() end
  p.rows = {}
  for i, entry in ipairs(weightTokens(class, weights)) do
    local row = p.pool[entry.token] or newWeightRow(p, entry.token)
    p.pool[entry.token] = row
    p.rows[i] = row
    KP.PaintIcon(row.icon, nil, STAT_ICON[entry.token])
    local key = U.TOKENS[entry.token][1]
    put(row.name, _G[key] or entry.token)
    put(row.hint, GC.L[(U.HANDS[class] and HANDS_HINT[entry.token]) or STAT_HINT[entry.token]])
    -- While the player is not typing in it, the box holds the weight in force and is no longer red.
    local box = row.box
    if not (box.box.HasFocus and box.box:HasFocus()) then
      box.bad = nil
      local w = weights[entry.token]
      box.box:SetText(w and ("%g"):format(w) or "0")
    end
    local gold = Theme.color.gold
    if not box.bad then
      box:SetTint(nil, entry.top and { gold[1], gold[2], gold[3], 0.65 } or GC.Kit.Tokens.ink(0.14))
    end
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
  readRoad()
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
  -- The pace: the forecast sentence of /gc mount (GC.ForeverRoad.Lines' second), and what the
  -- pieces ticked to buy leave toward it.
  local words = {}
  local roadLines = s.cost and GC.ForeverRoad.Lines(s) or {}
  if roadLines[2] then words[#words + 1] = roadLines[2] end
  local list = state.tickedList or {}
  local n, spent = #list, 0
  for _, c in ipairs(list) do spent = spent + (tonumber(c.unit) or 0) end
  if n == 1 then
    words[#words + 1] = GC.L["The upgrade in your set leaves %s toward it."]:format(coins(have - spent))
  elseif n > 1 then
    words[#words + 1] = GC.L["The %d upgrades in your set leave %s toward it."]:format(n, coins(have - spent))
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

-- The open panel, as wide as the slot panel it covers; the others shut.
local function paintPanels(w)
  view.panels = view.panels or {}
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

local function currentHeight()
  local h = view.container:GetHeight()
  if h and h > 0 then view.height = h end
  return view.height or HD.HEIGHT
end

paint = function()
  if not (view.container and view.doll) then return end
  local r = state.r or { slots = {}, loading = 0 }
  local width, height = currentWidth(), currentHeight()
  readWorn()
  local at = {}
  for _, s in ipairs(r.slots or {}) do
    if s.invSlot then at[s.invSlot] = s end
  end
  view.at = at
  resolve(r)
  pickSelection()
  local topH = layoutTop(r, width)
  local barH = layoutBar(r, width)
  local midTop = topH + HD.GAP
  local midH = math.max(1, height - midTop - barH - HD.GAP)
  layoutDoll(midTop, midH)
  local panelW = math.max(1, width - HD.DOLL_W - HD.GAP)
  layoutPanel(r, HD.DOLL_W + HD.GAP, midTop, panelW, midH)
  paintPanels(panelW)
  -- The character dressed again on every Show and whenever what it wears changed, once laid out.
  if view.dressed ~= view.wornSig then
    view.dressed = view.wornSig
    dress()
  end
  -- A repaint under a still cursor can hand the hovered slot or option another item, or take it
  -- away: its tooltip follows, or goes.
  local owner = GameTooltip and GameTooltip:IsShown() and GameTooltip.GetOwner and GameTooltip:GetOwner() or nil
  if type(owner) == "table" and owner.isHeroPiece then
    if owner.tipLink and owner:IsVisible() then pieceTip(owner) else GameTooltip:Hide() end
  end
end

local function build()
  if view.doll then return end
  local container = view.container
  view.top = createTop(container)
  view.panel = createPanel(container)
  view.bar = createBar(container)
  view.doll = createDoll(container)
end

-- BUY ---------------------------------------------------------------------------------------

--- Puts `picks` (candidates: the pieces ticked to buy) on the player's Upgrades list and
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
-- passed through from the Sniper's createFrame, exactly as GC.Sold.Attach. The top line, the doll,
-- the slot panel and the bar wait for the first Show; the scroll here holds the slot panel's options.
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
  content:SetSize(geo.rowWidth, 1)
  scroll:SetScrollChild(content)
  view.scroll, view.content = scroll, content
  -- A resize, a dock reparent or a font-scale change moves every measured width, so the tab is
  -- laid out again whole, from the result it holds. A frame resized while hidden does not reliably
  -- fire OnSizeChanged; Show() lays it out anyway.
  container:HookScript("OnSizeChanged", function(_, width, height)
    if width and width > 0 then view.width = width end
    if height and height > 0 then view.height = height end
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

-- While the shown tab's last build still counts items loading, it builds itself again SELF_S on,
-- whatever events arrive or do not, at most SELF_MAX times a Show, and stops at none loading or on
-- Hide. One chain at a time: a repaint for any other reason finds the tick on its way and adds none.
local function selfRefresh(r)
  if (tonumber(r.loading) or 0) <= 0 or repaint.selfDue or not shown() then return end
  if repaint.selfCount >= HD.SELF_MAX then return end
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  local gen = repaint.gen
  repaint.selfDue = true
  timer.After(HD.SELF_S, function()
    if gen ~= repaint.gen then return end
    repaint.selfDue = false
    if not shown() then return end
    repaint.selfCount = repaint.selfCount + 1
    Hero.RefreshIfShown(true)
  end)
end

--- Paints `r` (GC.ForeverUpgrades.Current's answer) as of `now`: Show and RefreshIfShown build it
--- and hand it here, and so does Core/ForeverScan.lua's post-scan update, which built it already.
function Hero.Render(r, now)
  state.r = r or current()
  state.now = now or time()
  repaint.ids = state.r.loadingIds
  readRoad()
  paint()
  chaseSpeed(state.r)
  selfRefresh(state.r)
end

function Hero.Show()
  if not view.container then return end
  view.container:Show()
  build()
  -- A fresh open always gets a fresh chance, whatever a previous visit's storm cap reached.
  repaint.stale, repaint.last, repaint.speedLast = 0, nil, nil
  repaint.gen, repaint.selfCount, repaint.selfDue = repaint.gen + 1, 0, false
  -- And lists the first slot with choices again, and dresses the character as it stands now.
  state.selByHand, view.dressed = nil, nil
  view.restamp = true -- see put(): every string is drawn again after the hide
  Hero.Render(current(), time())
  view.restamp = false
end

function Hero.Hide()
  repaint.gen, repaint.selfDue = repaint.gen + 1, false
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

-- PLAYER_MONEY and PLAYER_EQUIPMENT_CHANGED: the gold carried or a worn piece moved, and the slots
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
