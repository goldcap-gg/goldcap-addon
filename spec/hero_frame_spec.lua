local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/HeroFrame.lua: WoW: Forever's HERO tab as the character sheet the owner approved (board "6. v2",
-- 2026-11-13). The real Theme and kit, the real BUY lists (Core/AppRuns.lua), the real weights and
-- the words of Core/ForeverUpgrades.lua and the real /gc mount lines (Core/ForeverRoad.lua); what the
-- tab is handed is a seam: GC.ForeverUpgrades.Current answers `result`, GC.ForeverRoad.Snapshot
-- `road`, GetInventoryItemLink `wornLinks`. The window around it (GC.Sniper) and the BUY tab (GC.Buy)
-- are doubles that remember what they were asked. The widgets are spec/support/wow_frames.lua's,
-- read through W.state.
describe("HERO tab", function()
  local GC, H, restore, saved, timers, delays, prefs, result, road, builds, views, toggled, windowShown
  local selected, tipLink, tipShown, tipOwner, modified, clicked, chat, host, snapshots, wornLinks
  local units, noModel, modelAnswer
  local KEYS = { "UIParent", "C_Item", "C_Timer", "GameTooltip", "HandleModifiedItemClick", "UnitClass", "UnitLevel",
    "GetMoney", "RAID_CLASS_COLORS", "GetClassAtlas", "C_Texture", "C_PaperDollInfo", "GetInventorySlotInfo",
    "GetCoinTextureString", "ChatFrame_OpenChat", "InCombatLockdown", "ITEM_MOD_STRENGTH_SHORT",
    "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "RESISTANCE0_NAME",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_CHEST", "INVTYPE_HEAD", "INVTYPE_FINGER",
    "ITEM_QUALITY_COLORS", "GetInventoryItemLink", "time", "RED_FONT_COLOR" }
  local NOW = 1800000000
  local CLUB, WATCH, BRUISER, TUNIC, HATCHET, VEST = 2130, 15210, 2131, 2316, 2134, 2317
  -- The paper doll's slots in the client's own order (Forever's Camelot/PaperDollFrame.xml).
  local DOLL_ORDER = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

  local function plain(text) return helper.plain(text) end
  local function textOf(fs) return plain(W.state(fs).text or "") end
  local function shown(widget) return W.state(widget).shown and true or false end
  local function press(widget) W.state(widget).scripts.OnClick(widget, "LeftButton", false) end
  local function runTimers()
    local fns = timers
    timers, delays = {}, {}
    for _, fn in ipairs(fns) do fn() end
  end
  -- How many timers wait `s` seconds: the tab's own once-a-second rebuild runs beside the others.
  local function due(s)
    local n = 0
    for _, d in ipairs(delays) do if d == s then n = n + 1 end end
    return n
  end
  -- What a player types into a box: the text, then the client's OnTextChanged with userInput true.
  local function typeInto(box, text)
    W.state(box).text = text
    W.state(box).scripts.OnTextChanged(box, true)
  end
  local function rgb(c) return { c[1], c[2], c[3] } end
  local function colourOf(tex) local c = W.state(tex).color; return c and { c[1], c[2], c[3] } end

  local function piece(group, itemID, name, unit, diffs, extra)
    local c = { group = group, itemID = itemID, itemString = "item:" .. itemID,
      link = "|cff1eff00|Hitem:" .. itemID .. "::::|h[" .. name .. "]|h|r", unit = unit, gain = 1, diffs = diffs,
      version = nil }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
  end

  -- A level 17 rogue with 59s 73c: a club it can wear at 19 is the strongest main hand, a sword the
  -- set takes is one of the other choices, with a hatchet and a club weaker still; a tunic is the
  -- strongest chest piece and in the set too, over the tunic worn.
  local function aResult()
    local club = piece("MAINHAND", CLUB, "Skeletal Club", 3990, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6.5 },
      { later = 19, gain = 9 })
    local watch = piece("MAINHAND", WATCH, "Night Watch Shortsword", 7499,
      { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.4, ITEM_MOD_STAMINA_SHORT = 4 }, { inSet = true, gain = 6 })
    local bruiser = piece("MAINHAND", BRUISER, "Bruiser Club", 2700,
      { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2, ITEM_MOD_STRENGTH_SHORT = 2 }, { gain = 3 })
    local hatchet = piece("MAINHAND", HATCHET, "Rusty Hatchet", 2900, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3 },
      { gain = 4 })
    local tunic = piece("CHEST", TUNIC, "Dark Leather Tunic", 1589,
      { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STAMINA_SHORT = -4 }, { inSet = true })
    return {
      at = NOW - 240, loading = 0, weights = { AGI = 1 }, style = "sinister",
      slots = {
        { group = "CHEST", labelKey = "INVTYPE_CHEST", best = tunic, alts = {}, invSlot = 5,
          worn = "|Hitem:85::::|h[Old Tunic]|h" },
        { group = "MAINHAND", labelKey = "INVTYPE_WEAPONMAINHAND", best = club, alts = { watch, bruiser, hatchet },
          invSlot = 16 },
      },
      set = { picks = { MAINHAND = watch, CHEST = tunic }, list = { tunic, watch }, cost = 9088, left = 5973 - 9088,
        diffs = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.4, ITEM_MOD_AGILITY_SHORT = 6 } },
    }
  end

  local function doll() return H._view.doll end
  local function slotAt(inv) return H._view.doll.slots[inv] end
  local function sp() return H._view.panel end
  local function opt(i) return H._view.panel.rows[i] end
  local function optsShown()
    local out = {}
    for _, r in ipairs(H._view.panel.rows) do if shown(r) then out[#out + 1] = textOf(r.name) end end
    return out
  end
  -- The heights of the rows a list shows, top to bottom.
  local function heightsShown()
    local out = {}
    for _, r in ipairs(H._view.panel.rows) do if shown(r) then out[#out + 1] = r:GetHeight() end end
    return out
  end
  local function ticked(row) return shown(row.boxFill) end
  local function bar() return H._view.bar end
  local function top() return H._view.top end
  -- The weights panel's stats, top to bottom, as shown.
  local function statsShown(p)
    local out = {}
    for _, r in ipairs(p.rows) do if shown(r.frame) then out[#out + 1] = r.token end end
    local hidden = 0
    for _, r in pairs(p.pool) do if not shown(r.frame) then hidden = hidden + 1 end end
    return out, hidden
  end
  local function panel(key) return H._view.panels and H._view.panels[key] end
  local function run() return GC.AppRuns.Get(prefs.heroList) end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    -- A PlayerModel: a frame with only what Forever's own source shows one has besides a frame's,
    -- SetUnit (Blizzard_APIDocumentationGenerated/FrameAPICharacterModelBaseDocumentation.lua, the
    -- forever branch), which answers whether it took. noModel: a client without the frame type.
    units, noModel, modelAnswer = {}, false, true
    local frame = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
      if kind ~= "PlayerModel" then return frame(kind, name, parent, template) end
      if noModel then error("CreateFrame: Unknown frame type 'PlayerModel'") end
      local m = frame("Frame", name, parent, template)
      function m.SetUnit(_, unit) units[#units + 1] = unit; return modelAnswer end
      return m
    end
    timers, delays, builds, views, toggled, windowShown, snapshots = {}, {}, 0, {}, false, true, 0
    selected, tipLink, tipShown, tipOwner, modified, clicked, chat = nil, nil, false, nil, false, nil, nil
    wornLinks = { [5] = "|Hitem:85::::|h[Old Tunic]|h" }
    _G.C_Timer = { After = function(s, fn) delays[#delays + 1] = s; timers[#timers + 1] = fn end }
    _G.UnitClass = function() return "Rogue", "ROGUE", 4 end
    _G.UnitLevel = function() return 17 end
    _G.GetMoney = function() return 5973 end
    _G.GetInventoryItemLink = function(unit, slot) return unit == "player" and wornLinks[slot] or nil end
    -- The client's own red, a tooltip's level line's and an unaffordable buyout's.
    _G.RED_FONT_COLOR = { r = 1, g = 0.125, b = 0.125 }
    _G.RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    _G.GetClassAtlas = function(file) return ("classicon-%s"):format(file) end
    _G.C_Texture = { GetAtlasInfo = function(atlas) return atlas:find("^classicon%-") and {} or nil end }
    _G.C_Item = {
      GetItemIconByID = function(id) return 100000 + (tonumber(id) or 0) end,
      GetItemNameByID = function() return nil end,
      GetItemQualityByID = function() return 2 end,
    }
    _G.C_PaperDollInfo = { GetInventorySlotInfo = function(name) return 1, "slot:" .. name, false end }
    _G.GameTooltip = {
      SetOwner = function(_, owner) tipOwner = owner end, SetHyperlink = function(_, l) tipLink = l end,
      Show = function() tipShown = true end, Hide = function() tipShown = false end,
      IsShown = function() return tipShown end, GetOwner = function() return tipOwner end,
    }
    _G.HandleModifiedItemClick = function(l) clicked = l; return modified end
    _G.GetCoinTextureString = function(c) return c .. "c" end
    _G.ChatFrame_OpenChat = function(text) chat = text end
    _G.InCombatLockdown = function() return false end
    _G.time = function() return NOW end
    _G.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0, hex = "|cff1eff00" } }
    _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_AGILITY_SHORT, _G.ITEM_MOD_STAMINA_SHORT = "Strength", "Agility", "Stamina"
    _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, _G.RESISTANCE0_NAME = "Damage Per Second", "Armor"
    _G.INVTYPE_WEAPONMAINHAND, _G.INVTYPE_CHEST, _G.INVTYPE_HEAD = "Main Hand", "Chest", "Head"
    _G.INVTYPE_WEAPONOFFHAND, _G.INVTYPE_FINGER = "Off Hand", "Finger"

    GC = helper.loadModule("UI/Theme.lua", {})
    GC.db = { runs = {} }
    helper.loadModule("Core/AppRuns.lua", GC)
    helper.loadModule("Core/ForeverGear.lua", GC)
    helper.loadModule("Core/ForeverUpgrades.lua", GC)
    helper.loadModule("Core/ForeverRoad.lua", GC)
    prefs = {}
    GC.ForeverScan = { Prefs = function() return prefs end }
    GC.Buy = {
      _SetLineCap = function(code, itemID, copper)
        GC.db.runLineCaps = GC.db.runLineCaps or {}
        GC.db.runLineCaps[code] = GC.db.runLineCaps[code] or {}
        GC.db.runLineCaps[code][itemID] = copper
      end,
      SelectRun = function(code) selected = code end,
    }
    GC.Sniper = {
      ShowView = function(v) views[#views + 1] = v end,
      IsWindowShown = function() return windowShown end,
      Toggle = function() toggled = true; windowShown = true end,
    }
    helper.loadModule("UI/HeroFrame.lua", GC)
    H = GC.Hero
    result = aResult()
    road = { money = 5973, bags = 4620, gain = 3112, gainItems = 12, cost = 20000, level = 17, progress = 17.5 }
    GC.ForeverUpgrades.Current = function() builds = builds + 1; return result end
    GC.ForeverRoad.Snapshot = function() snapshots = snapshots + 1; return road end
    host = CreateFrame("Frame")
    H.Attach(host, { panelLeft = 90, panelRightInset = 14, top = -52, bottom = 14, rowWidth = 640, rowHeight = 32 })
    W.state(H._view.container).height = 500
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  it("builds hidden over the Deals list's region and waits for the first Show", function()
    local c = H._view.container
    assert.equal(host, c:GetParent())
    assert.is_false(shown(c))
    assert.same({ "TOPLEFT", host, "TOPLEFT", 90, -52 }, W.state(c).points[1])
    assert.same({ "BOTTOMRIGHT", host, "BOTTOMRIGHT", -14, 14 }, W.state(c).points[2])
    assert.is_nil(H._view.doll)
    assert.is_false(H.IsShown())
    H.Show()
    assert.is_true(H.IsShown())
    assert.equal(1, builds)
    H.Hide()
    assert.is_false(H.IsShown())
  end)

  it("draws every paper-doll slot in the client's order, ticked pieces green with their price", function()
    H.Show()
    local d = doll()
    assert.same(DOLL_ORDER, d.order)
    -- Eight down the left, eight down the right, the three hands in a row under the character.
    local function at(inv) local p = W.state(slotAt(inv)).points[1]; return p[4], p[5] end
    local lx, ly = at(1)
    local rx, ry = at(10)
    assert.is_true(rx > lx)
    assert.equal(ly, ry)
    for i = 2, 8 do
      local x, y = at(DOLL_ORDER[i])
      assert.equal(lx, x)
      assert.is_true(y < select(2, at(DOLL_ORDER[i - 1])))
      x, y = at(DOLL_ORDER[i + 8])
      assert.equal(rx, x)
      assert.is_true(y < select(2, at(DOLL_ORDER[i + 7])))
    end
    local mx, my = at(16)
    local ox, oy = at(17)
    local gx, gy = at(18)
    assert.is_true(mx > lx and ox > mx and gx > ox and gx < rx)
    assert.equal(my, oy)
    assert.equal(my, gy)
    local green, gold = GC.Theme.color.green, GC.Theme.color.gold
    -- The chest: the set's tunic ticked, its icon, a green frame, the check and its price.
    local chest = slotAt(5)
    assert.equal(100000 + TUNIC, W.state(chest.icon.icon).file)
    assert.same(rgb(green), colourOf(chest.frameRing))
    assert.is_true(shown(chest.badge))
    assert.equal("16s", textOf(chest.price))
    assert.is_true(shown(chest.price))
    -- The check and the price stand inside the slot's own square, over nothing of a neighbour's.
    local badge, price = W.state(chest.badge).points[1], W.state(chest.price).points[1]
    assert.same({ "TOPLEFT", chest, "TOPLEFT" }, { badge[1], badge[2], badge[3] })
    assert.is_true(badge[4] >= 0 and badge[5] <= 0)
    assert.same({ "BOTTOMRIGHT", chest, "BOTTOMRIGHT" }, { price[1], price[2], price[3] })
    assert.is_true(price[4] <= 0 and price[5] >= 0)
    -- The main hand: the set's sword ticked. No level badges on the doll: the panel marks the club.
    local main = slotAt(16)
    assert.equal(100000 + WATCH, W.state(main.icon.icon).file)
    assert.equal("75s", textOf(main.price))
    assert.is_nil(main.level)
    -- Green means ticked only: no icon on the doll wears its quality's edge.
    local q = GC.Theme.QualityColor(TUNIC)
    assert.are_not.same({ q.r, q.g, q.b }, colourOf(chest.icon.edge))
    -- Nothing to buy for the head: nothing worn there, the client's empty-slot art, no frame of note.
    local head = slotAt(1)
    assert.equal("slot:HeadSlot", W.state(head.icon.icon).file)
    assert.is_false(shown(head.badge))
    assert.is_false(shown(head.price))
    assert.are_not.same(rgb(green), colourOf(head.frameRing))
    assert.are_not.same(rgb(gold), colourOf(head.frameRing))
    for _, inv in ipairs({ 4, 19, 13, 14, 17, 18 }) do
      assert.is_false(shown(slotAt(inv).badge), inv)
    end
    assert.equal("Click a slot to see what you can buy for it.", textOf(d.hint))
    -- Nothing ticked in a slot with choices: what is worn there, framed thin and gold.
    result.set = { picks = {}, list = {}, cost = 0, left = 5973, diffs = {} }
    H.RefreshIfShown(true)
    assert.equal(100000 + 85, W.state(chest.icon.icon).file)          -- the tunic worn
    assert.equal("slot:MainHandSlot", W.state(main.icon.icon).file)
    assert.same(rgb(gold), colourOf(main.frameRing))
    assert.is_false(shown(main.badge))
    assert.is_false(shown(main.price))
  end)

  it("selects the first slot with choices and lists its options: the set's pick first, keep last", function()
    H.Show()
    assert.equal(5, H._state.sel)                                       -- the chest comes before the main hand
    assert.is_true(shown(slotAt(5).glow))
    assert.is_false(shown(slotAt(16).glow))
    local p = sp()
    assert.equal("CHEST", textOf(p.title))
    assert.equal("You wear Old Tunic", textOf(p.sub))
    assert.is_nil(p.hint)                                               -- the head, then the list
    assert.same({ "Dark Leather Tunic", "Keep Old Tunic" }, optsShown())
    assert.is_nil(opt(1).tags)                                          -- no chips: the tick says it
    assert.is_true(ticked(opt(1)))
    -- Keep: the box, what is worn and its name, no price; as tall as the piece above it.
    assert.is_false(shown(opt(2).price))
    assert.equal(100000 + 85, W.state(opt(2).icon.icon).file)
    local hs = heightsShown()
    assert.equal(hs[1], hs[2])
    assert.is_false(ticked(opt(2)))
    -- The main hand: the set's pick, the strongest, the others by what they add; nothing worn to keep.
    -- Its list starts at the top, wherever the chest's was scrolled to.
    W.state(H._view.scroll).scroll = 40
    press(slotAt(16))
    assert.equal(0, H._view.scroll:GetVerticalScroll())
    assert.equal(16, H._state.sel)
    assert.is_true(shown(slotAt(16).glow))
    assert.is_false(shown(slotAt(5).glow))
    assert.equal("MAIN HAND", textOf(p.title))
    assert.equal("Nothing worn here", textOf(p.sub))
    assert.same({ "Night Watch Shortsword", "Skeletal Club", "Rusty Hatchet", "Bruiser Club", "Buy nothing here" },
      optsShown())
    assert.equal("+4 Stamina, +4.4 Damage Per Second", textOf(opt(1).gain))
    assert.equal("7499c", textOf(opt(1).price))
    assert.equal("3990c", textOf(opt(2).price))
    -- The club waits for level 19, marked as the game marks a piece you cannot use yet: its art
    -- tinted red, the level in a stack count's corner, white as a count is. The others untinted.
    local club = opt(2).icon
    assert.same({ 0.9, 0, 0, 1 }, W.state(club.icon).vertex)
    assert.equal("19", textOf(club.count))
    assert.equal(result.slots[2].best.later, tonumber(textOf(club.count)))
    assert.same({ 1, 1, 1, 1 }, W.state(club.count).color)
    local corner = W.state(club.count).points[1]
    assert.same({ "BOTTOMRIGHT", club.edge, "BOTTOMRIGHT" }, { corner[1], corner[2], corner[3] })
    for _, i in ipairs({ 1, 3, 4, 5 }) do
      assert.same({ 1, 1, 1, 1 }, W.state(opt(i).icon.icon).vertex, i)
      assert.equal("", textOf(opt(i).icon.count), i)
    end
    -- Its gains run the whole width, as wide as a piece's with nothing to wait for.
    assert.equal(opt(1).gain:GetWidth(), opt(2).gain:GetWidth())
    assert.is_true(opt(2).gain:GetWidth() > opt(2).name:GetWidth())
    assert.is_false(shown(opt(5).price))
    -- Every row of one list as tall as the others, keep too.
    hs = heightsShown()
    for i = 2, #hs do assert.equal(hs[1], hs[i], i) end
    assert.equal("slot:MainHandSlot", W.state(opt(5).icon.icon).file)
    assert.same({ true, false, false, false, false },
      { ticked(opt(1)), ticked(opt(2)), ticked(opt(3)), ticked(opt(4)), ticked(opt(5)) })
    -- Its name in its quality's colour; what a piece gives up red.
    local q = GC.Theme.QualityColor(WATCH)
    assert.same({ q.r, q.g, q.b, 1 }, W.state(opt(1).name).color)
    press(slotAt(5))
    local red, green = GC.Theme.color.red, GC.Theme.color.green
    assert.equal(GC.Util.Colored(green, "+6 Agility") .. ", " .. GC.Util.Colored(red, "-4 Stamina"),
      W.state(opt(1).gain).text)
    local fg = GC.Theme.color.fg
    assert.same({ fg[1], fg[2], fg[3], 1 }, W.state(opt(1).price).color)  -- within the gold carried
    -- Over the gold carried: still listed, its price red as the AH paints a buyout you cannot pay.
    result.slots[1].best.overGold = true
    H.RefreshIfShown(true)
    assert.equal("1589c", textOf(opt(1).price))
    assert.same({ 1, 0.125, 0.125, 1 }, W.state(opt(1).price).color)
    -- Keep reuses the club's row: its icon untinted again, with no number.
    assert.equal("Keep Old Tunic", textOf(opt(2).name))
    assert.same({ 1, 1, 1, 1 }, W.state(opt(2).icon.icon).vertex)
    assert.equal("", textOf(opt(2).icon.count))
    -- A rebuild keeps the slot the player looks at; a fresh open picks the first with choices again.
    press(slotAt(16))
    H.RefreshIfShown(true)
    assert.equal(16, H._state.sel)
    H.Hide()
    H.Show()
    assert.equal(5, H._state.sel)
  end)

  it("ticking one option unticks the rest of its slot, keep unticks all", function()
    H.Show()
    press(slotAt(16))
    press(opt(3))                                                       -- the hatchet
    assert.same({ false, false, true, false, false },
      { ticked(opt(1)), ticked(opt(2)), ticked(opt(3)), ticked(opt(4)), ticked(opt(5)) })
    assert.equal("item:" .. HATCHET, H._state.touched.MAINHAND)
    assert.equal(100000 + HATCHET, W.state(slotAt(16).icon.icon).file)
    assert.equal("29s", textOf(slotAt(16).price))
    local walks = snapshots
    press(opt(5))                                                       -- buy nothing here
    assert.equal(walks, snapshots)                                      -- a tick repaints; the bags are not walked again
    assert.same({ false, false, false, false, true },
      { ticked(opt(1)), ticked(opt(2)), ticked(opt(3)), ticked(opt(4)), ticked(opt(5)) })
    assert.is_false(H._state.touched.MAINHAND)
    assert.equal("slot:MainHandSlot", W.state(slotAt(16).icon.icon).file)
    assert.is_false(shown(slotAt(16).badge))
    assert.same(rgb(GC.Theme.color.gold), colourOf(slotAt(16).frameRing))
    -- The chest was never touched: still the set's.
    assert.is_nil(H._state.touched.CHEST)
    assert.is_true(shown(slotAt(5).badge))
  end)

  it("the bar counts only ticked pieces, and says short by when they cost more than the gold carried", function()
    H.Show()
    local b = bar()
    assert.equal("2 ticked: +6 Agility, +4.4 Damage Per Second", textOf(b.title))
    assert.equal("Picked by GoldCap for the gold you carry", textOf(b.sub))
    assert.equal("TICKED COST", textOf(b.costHead))
    assert.equal("9088c", textOf(b.cost))
    assert.equal("Short by 3115c", textOf(b.left))
    local red = GC.Theme.color.red
    assert.same({ red[1], red[2], red[3], 1 }, W.state(b.left).color)
    assert.is_nil(b.icons)                                              -- the doll shows what is ticked
    assert.equal("Add 2 to BUY", textOf(b.add.text))
    assert.is_true(b.add:IsEnabled())
    -- Keep the main hand's nothing: one piece left, the player's own.
    press(slotAt(16))
    press(opt(5))
    assert.equal("1 ticked: +6 Agility, -4 Stamina", textOf(b.title))
    assert.equal("Your own picks", textOf(b.sub))
    assert.equal("1589c", textOf(b.cost))
    assert.equal("LEFT AFTER", textOf(b.leftHead))
    assert.is_true(shown(b.leftHead))
    assert.equal(tostring(5973 - 1589) .. "c", textOf(b.left))
    assert.are_not.same({ red[1], red[2], red[3], 1 }, W.state(b.left).color)
    assert.equal("Add 1 to BUY", textOf(b.add.text))
    -- Nothing ticked at all: the button cannot be pressed.
    press(slotAt(5))
    press(opt(2))
    assert.equal("Nothing ticked", textOf(b.title))
    assert.equal("0c", textOf(b.cost))
    assert.equal("Add 0 to BUY", textOf(b.add.text))
    assert.is_false(b.add:IsEnabled())
  end)

  it("a slot the player changed keeps its tick through a rebuild, untouched slots follow the set", function()
    H.Show()
    press(slotAt(16))
    press(opt(4))                                                       -- the bruiser, by hand
    -- A new scan: new candidates, and the set now takes a vest for the chest.
    result = aResult()
    local vest = piece("CHEST", VEST, "Cracked Leather Vest", 900, { ITEM_MOD_AGILITY_SHORT = 3 }, { inSet = true })
    result.slots[1].best.inSet = false
    result.slots[1].alts = { vest }
    result.set.picks.CHEST, result.set.list[1] = vest, vest
    H.RefreshIfShown(true)
    assert.equal(100000 + BRUISER, W.state(slotAt(16).icon.icon).file)
    assert.equal(100000 + VEST, W.state(slotAt(5).icon.icon).file)
    -- The bruiser gone from the main hand's choices: the set's pick again, the touch forgotten.
    result = aResult()
    table.remove(result.slots[2].alts, 2)
    H.RefreshIfShown(true)
    assert.is_nil(H._state.touched.MAINHAND)
    assert.equal(100000 + WATCH, W.state(slotAt(16).icon.icon).file)
    -- A slot gone from the build forgets its tick too, and follows the set when it is back.
    press(slotAt(16))
    press(opt(3))                                                       -- the hatchet
    result = aResult()
    table.remove(result.slots, 2)
    H.RefreshIfShown(true)
    assert.is_nil(H._state.touched.MAINHAND)
    result = aResult()
    H.RefreshIfShown(true)
    assert.equal(100000 + WATCH, W.state(slotAt(16).icon.icon).file)
    -- A kept slot stays kept through a rebuild that offers it something new.
    press(slotAt(5))
    press(opt(2))                                                       -- keep the old tunic
    result = aResult()
    H.RefreshIfShown(true)
    assert.is_false(H._state.touched.CHEST)
    assert.equal(100000 + 85, W.state(slotAt(5).icon.icon).file)
    assert.is_false(shown(slotAt(5).badge))
  end)

  it("Add N to BUY sends exactly the ticked pieces", function()
    H.Show()
    press(slotAt(16))
    press(opt(4))                                                       -- the bruiser instead of the set's sword
    press(bar().add)
    local list = run()
    assert.equal("Upgrades", list.name)
    assert.equal("game", list.origin)
    local ids = {}
    for _, line in ipairs(list.lines) do ids[#ids + 1] = line.i end
    assert.same({ TUNIC, BRUISER }, ids)
    assert.equal(1, list.lines[1].q)
    assert.equal(math.floor(2700 * 105 / 100), GC.db.runLineCaps[list.code][BRUISER])
    assert.equal(math.floor(1589 * 105 / 100), GC.db.runLineCaps[list.code][TUNIC])
    assert.is_nil(GC.db.runLineCaps[list.code][WATCH])
    assert.equal(list.code, selected)
    assert.equal("buy", views[#views])
    assert.equal(prefs.heroList, list.code)
  end)

  -- One lot cannot fill two hands, and a two-hander takes both (BestSet's own rules): a free tick
  -- keeps them as the set does.
  it("keeps one piece to one hand and a two-hander to both, whichever hand is ticked", function()
    local AXE, SWORD, SHIELD = 1400, 1300, 1500
    local function hands()
      local axe = piece("MAINHAND", AXE, "Woodsman Axe", 5000, { ITEM_MOD_STRENGTH_SHORT = 9 }, { twoHand = true, gain = 9 })
      local swordM = piece("MAINHAND", SWORD, "Short Sword", 2000, { ITEM_MOD_STRENGTH_SHORT = 4 }, { inSet = true, gain = 4 })
      local swordO = piece("OFFHAND", SWORD, "Short Sword", 2000, { ITEM_MOD_STRENGTH_SHORT = 2 }, { gain = 2 })
      local shield = piece("OFFHAND", SHIELD, "Buckler", 1000, { RESISTANCE0_NAME = 20 }, { inSet = true, gain = 1 })
      return {
        at = NOW, loading = 0, weights = { STR = 1 },
        slots = {
          { group = "MAINHAND", labelKey = "INVTYPE_WEAPONMAINHAND", best = axe, alts = { swordM }, invSlot = 16 },
          { group = "OFFHAND", labelKey = "INVTYPE_WEAPONOFFHAND", best = swordO, alts = { shield }, invSlot = 17 },
        },
        set = { picks = { MAINHAND = swordM, OFFHAND = shield }, list = { swordM, shield }, cost = 3000, left = 2973,
          diffs = {} },
      }
    end
    local function icon(inv) return W.state(slotAt(inv).icon.icon).file end
    result = hands()
    H.Show()
    assert.same({ 100000 + SWORD, 100000 + SHIELD }, { icon(16), icon(17) })
    -- The sword in the off hand: the main hand lets it go and keeps what is worn there.
    press(slotAt(17))
    press(opt(2))                                                       -- options: buckler (set), sword, keep
    assert.equal("Short Sword", textOf(opt(2).name))
    assert.same({ "slot:MainHandSlot", 100000 + SWORD }, { icon(16), icon(17) })
    assert.is_false(H._state.touched.MAINHAND)
    -- The axe in the main hand: the off hand empties.
    press(slotAt(16))
    press(opt(2))                                                       -- options: sword (set), axe, keep
    assert.equal("Woodsman Axe", textOf(opt(2).name))
    assert.same({ 100000 + AXE, "slot:SecondaryHandSlot" }, { icon(16), icon(17) })
    assert.is_false(H._state.touched.OFFHAND)
    -- The buckler under the axe: the axe goes.
    press(slotAt(17))
    press(opt(1))
    assert.same({ "slot:MainHandSlot", 100000 + SHIELD }, { icon(16), icon(17) })
    assert.is_false(H._state.touched.MAINHAND)
    -- A rebuild that moves the set's sword into the hand the player filled with it: the hand that
    -- follows the set lets it go, the player's stays.
    H._state.touched = { OFFHAND = "item:" .. SWORD }
    H.RefreshIfShown(true)
    assert.same({ "slot:MainHandSlot", 100000 + SWORD }, { icon(16), icon(17) })
    assert.equal("1 ticked: +2 Strength", textOf(bar().title))
    -- And one that makes the set's main hand a two-hander under a shield the player ticked.
    H._state.touched = { OFFHAND = "item:" .. SHIELD }
    result = hands()
    result.set.picks.MAINHAND = result.slots[1].best
    H.RefreshIfShown(true)
    assert.same({ "slot:MainHandSlot", 100000 + SHIELD }, { icon(16), icon(17) })
  end)

  -- What the tab is handed is ForeverUpgrades.Build's own answer: a ring for a warrior whose second
  -- finger wears the weaker ring.
  it("a ring upgrade shows on the weaker worn ring", function()
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::|h[Band " .. id .. "]|h|r" end
    wornLinks = { [11] = link(801), [12] = link(802) }
    local strength = { [801] = 6, [802] = 3, [800] = 9 }
    local driver = {
      level = function() return 20 end,
      classFile = function() return "WARRIOR" end,
      equipped = function(slot) return wornLinks[slot] end,
      instant = function(id) if id == 800 or id == 801 or id == 802 then return "INVTYPE_FINGER", 4, 0 end end,
      info = function(str) return 1, link(tonumber(str:match("item:(%d+)"))) end,
      stats = function(str) return { ITEM_MOD_STRENGTH_SHORT = strength[tonumber(str:match("item:(%d+)"))] } end,
      usable = function() return true end,
      speed = function() return nil end,
      requestLoad = function() end,
      money = function() return 5000 end,
    }
    result = GC.ForeverUpgrades.Build({ v = 2, at = NOW - 60, items = { [800] = "70:0:0" } }, driver, { STR = 1 })
    assert.equal(12, result.slots[1].invSlot)
    H.Show()
    assert.equal(12, H._state.sel)
    assert.equal(100000 + 800, W.state(slotAt(12).icon.icon).file)
    assert.is_true(shown(slotAt(12).badge))
    assert.equal(100000 + 801, W.state(slotAt(11).icon.icon).file)   -- the stronger ring stays as it is
    assert.is_false(shown(slotAt(11).badge))
    assert.equal("FINGER", textOf(sp().title))
    assert.equal("You wear Band 802", textOf(sp().sub))
    assert.same({ "Band 800", "Keep Band 802" }, optsShown())
  end)

  it("dresses the character in a PlayerModel on every Show", function()
    H.Show()
    local d = doll()
    assert.same({ "player" }, units)
    assert.is_true(shown(d.model))
    assert.is_false(shown(d.portrait))
    assert.is_false(W.state(d.model).mouse == true)                   -- clicks on it reach nothing of ours
    H.Hide()
    H.Show()
    assert.same({ "player", "player" }, units)
    -- A worn piece changed while the tab is up: the character is dressed again.
    wornLinks[1] = "|Hitem:90::::|h[Cap]|h"
    H.RefreshIfShown(true)
    assert.same({ "player", "player", "player" }, units)
    H.RefreshIfShown(true)
    assert.equal(3, #units)
    -- A model that will not take the player: the class's icon instead.
    modelAnswer = false
    H.Hide()
    H.Show()
    assert.is_false(shown(d.model))
    assert.is_true(shown(d.portrait))
    assert.equal("classicon-rogue", W.state(d.portrait).atlas)
  end)

  it("shows the class's icon where the client has no PlayerModel, and draws the rest", function()
    noModel = true
    H.Show()
    local d = doll()
    assert.is_nil(d.model)
    assert.is_true(shown(d.portrait))
    assert.equal("classicon-rogue", W.state(d.portrait).atlas)
    assert.equal(100000 + TUNIC, W.state(slotAt(5).icon.icon).file)
    assert.equal("2 ticked: +6 Agility, +4.4 Damage Per Second", textOf(bar().title))
  end)

  -- The doll's empty slots are the client's own art for every slot the doll draws.
  it("has the paper doll's empty-slot art for every slot", function()
    result = { slots = {}, loading = 0, at = NOW, set = { picks = {}, list = {}, cost = 0, left = 5973, diffs = {} } }
    wornLinks = {}
    H.Show()
    local NAMES = { [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [15] = "BackSlot", [5] = "ChestSlot",
      [4] = "ShirtSlot", [19] = "TabardSlot", [9] = "WristSlot", [10] = "HandsSlot", [6] = "WaistSlot",
      [7] = "LegsSlot", [8] = "FeetSlot", [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot",
      [14] = "Trinket1Slot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot" }
    for inv, name in pairs(NAMES) do
      assert.equal("slot:" .. name, W.state(slotAt(inv).icon.icon).file, name)
    end
  end)

  it("wraps every name, gain and heading instead of cutting it, and sizes buttons to their words", function()
    result.slots[2].best.link = "|Hitem:2130::::|h[A very long name of a club that takes far more than one line]|h"
    H.Show()
    press(slotAt(16))
    local row = opt(2)
    for _, fs in ipairs({ row.name, row.gain, sp().title, sp().sub, bar().title, bar().sub, doll().hint,
        top().name }) do
      assert.is_true(W.state(fs).wordWrap ~= false)
      assert.equal(0, W.state(fs).maxLines)
      assert.is_true(W.state(fs).nonSpaceWrap)
    end
    assert.is_true(row:GetHeight() > W.LINE_H * 2)
    -- The rest of its list grows with it: one height per list.
    for i, h in ipairs(heightsShown()) do assert.equal(row:GetHeight(), h, i) end
    -- The price is as wide as its words.
    assert.is_true(row.price:GetWidth() >= row.price:GetUnboundedStringWidth())
    -- A button is as wide as its words.
    local add = bar().add
    assert.is_true(add:GetWidth() >= add.text:GetUnboundedStringWidth())
    local weights = top().weights
    assert.is_true(weights:GetWidth() >= weights.text:GetUnboundedStringWidth())
  end)

  it("hovers with the engine's HIGHLIGHT layer, shows the piece's own tooltip, and hands a modified click to the client", function()
    H.Show()
    press(slotAt(16))
    local row = opt(4)
    assert.is_true(W.state(row).mouse)
    assert.equal("HIGHLIGHT", W.state(row.hover).layer)
    W.state(row).scripts.OnEnter(row)
    assert.equal(result.slots[2].alts[2].link, tipLink)
    assert.equal(row, tipOwner)
    modified = true
    press(row)
    assert.equal(result.slots[2].alts[2].link, clicked)
    assert.is_false(ticked(row))                                       -- a shift-click links it, ticks nothing
    modified = false
    -- A doll slot shows what it shows: the ticked piece, else what is worn.
    local main = slotAt(16)
    assert.is_true(W.state(main).mouse)
    W.state(main).scripts.OnEnter(main)
    assert.equal(result.slots[2].alts[1].link, tipLink)
    W.state(slotAt(5)).scripts.OnLeave(slotAt(5))
    assert.is_false(tipShown)
    press(slotAt(5))
    press(opt(2))                                                       -- keep the old tunic
    W.state(slotAt(5)).scripts.OnEnter(slotAt(5))
    assert.equal(wornLinks[5], tipLink)
  end)

  it("adding the same pick twice leaves one line of one", function()
    local watch = result.slots[2].alts[1]
    watch.version = "612"
    H.AddToBuy({ watch })
    local other = piece("MAINHAND", WATCH, "Night Watch Shortsword of the Monkey", 7000, {}, { version = "607" })
    H.AddToBuy({ other })
    assert.equal(1, #run().lines)
    assert.equal(1, run().lines[1].q)
    assert.equal("607,612", run().lines[1].ver)                 -- either version will do now
    -- The cap stays at the higher of the two, the player's own raise kept.
    assert.equal(math.floor(7499 * 105 / 100), GC.db.runLineCaps[prefs.heroList][WATCH])
    -- A piece with no version on either side buys any.
    H.AddToBuy({ piece("MAINHAND", WATCH, "Night Watch Shortsword", 7499, {}) })
    assert.is_nil(run().lines[1].ver)
    assert.equal(1, run().lines[1].q)
  end)

  it("makes a new Upgrades list when the remembered one is gone", function()
    prefs.heroList = "game-7"                                    -- deleted in BUY since
    H.AddToBuy({ result.slots[1].best })
    assert.are_not.equal("game-7", prefs.heroList)
    assert.equal("Upgrades", run().name)
    -- One the site made has the same code shape but is not the player's to rewrite: a new one again.
    GC.db.runs.SITE1234 = { code = "SITE1234", origin = "site", lines = {} }
    prefs.heroList = "SITE1234"
    H.AddToBuy({ result.slots[1].best })
    assert.are_not.equal("SITE1234", prefs.heroList)
    assert.same({}, GC.db.runs.SITE1234.lines)
    -- An archived Upgrades list comes back out of the archive as it is used.
    GC.db.runsArchived = { [prefs.heroList] = true }
    H.AddToBuy({ result.slots[2].best })
    assert.is_nil(GC.db.runsArchived[prefs.heroList])
  end)

  it("saves a weight typed in the panel and refuses one that is not a number", function()
    H.Show()
    press(top().weights)
    assert.equal("Stat weights", textOf(top().weights.text))
    local p = panel("weights")
    assert.is_true(shown(p))
    -- Over the slot panel's area.
    assert.equal(sp().frame, W.state(p).points[1][2])
    assert.equal(sp().frame, W.state(p).points[2][2])
    assert.equal("What counts for a Rogue", textOf(p.title))
    assert.equal("classicon-rogue", W.state(p.icon).atlas)
    assert.equal("classicon-rogue", W.state(top().classIcon).atlas)
    -- One box per stat the class's defaults name, and DPS; the class's main stat and DPS first.
    assert.same({ "AGI", "DPS", "STR", "STA", "ARMOR", "AP" }, (statsShown(p)))
    assert.equal("1", W.state(p.boxes.AGI.box).text)
    assert.equal("7", W.state(p.boxes.DPS.box).text)
    builds = 0
    typeInto(p.boxes.AGI.box, "1,5")
    assert.equal(1.5, prefs.weights.ROGUE.AGI)
    assert.equal(0.5, prefs.weights.ROGUE.STR)                    -- the others kept as they were
    assert.equal(0, builds)                                       -- a rebuild waits for the typing to stop
    assert.equal(GC.Hero.C.TYPE_S, delays[#delays])
    runTimers()
    assert.equal(1, builds)
    -- Not a number: the box goes red and the weight stays.
    typeInto(p.boxes.AGI.box, "lots")
    assert.is_true(p.boxes.AGI.bad)
    local red = GC.Theme.color.red
    assert.same({ red[1], red[2], red[3], red[4] or 1 }, W.state(p.boxes.AGI.ring).vertex)
    assert.equal(1.5, prefs.weights.ROGUE.AGI)
    typeInto(p.boxes.STR.box, "0")                                -- nothing: off the list of weights
    assert.is_nil(prefs.weights.ROGUE.STR)
    -- A stat of the player's own the defaults do not name gets a box too.
    prefs.weights.ROGUE.SPI = 2
    H.RefreshIfShown(true)
    assert.same({ "AGI", "DPS", "STR", "STA", "SPI", "ARMOR", "AP" }, (statsShown(p)))
    -- Reset: the class's own defaults again, the box no longer red, the rows under SPI still there.
    assert.equal("Reset to Rogue", textOf(p.secondary.text))
    press(p.secondary)
    assert.is_nil(prefs.weights.ROGUE)
    assert.is_nil(p.boxes.AGI.bad)
    local after, hidden = statsShown(p)
    assert.same({ "AGI", "DPS", "STR", "STA", "ARMOR", "AP" }, after)
    assert.equal(1, hidden)                                       -- SPI's row, kept for next time
    -- Done shuts it.
    press(p.primary)
    assert.is_nil(H._state.panel)
    assert.is_true(p.slider == nil or p.slider:Leaving() or not shown(p))
  end)

  it("switches a rogue between Sinister Strike and Backstab and rebuilds", function()
    H.Show()
    H.TogglePanel("weights")
    local st = panel("weights").style
    assert.is_true(shown(st.switch))
    assert.equal("Sword, mace, fist", textOf(st.sinister.text))
    assert.equal("Dagger", textOf(st.backstab.text))
    assert.equal("From the weapon in your main hand. Backstab needs a dagger.", textOf(st.hint))
    builds = 0
    press(st.backstab)
    assert.equal("backstab", prefs.heroStyle)
    assert.equal(1, builds)
    press(st.sinister)
    assert.equal("sinister", prefs.heroStyle)
    -- Any other class has no such switch.
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    H.RefreshIfShown(true)
    assert.is_false(shown(st.switch))
    assert.equal("What counts for a Warrior", textOf(panel("weights").title))
    assert.same({ "STR", "DPS", "AGI", "STA", "ARMOR", "AP" }, (statsShown(panel("weights"))))
  end)

  it("says what to do when nothing fits the purse, and when the scan is stale", function()
    result.set = { picks = {}, list = {}, cost = 0, left = 5973, diffs = {} }
    result.stale = true
    H.Show()
    local b, t = bar(), top()
    assert.equal("Nothing on the auction house fits the gold you carry yet.", textOf(b.title))
    assert.is_false(shown(b.sub))
    assert.is_false(b.add:IsEnabled())
    assert.equal("5973c", textOf(b.left))
    assert.equal("Scan again to read each version's own stats.", textOf(t.note))
    assert.equal("Rogue · level 17", textOf(t.name))
    assert.equal("Scan 4m ago", textOf(t.sub))
    -- Every slot still shows its choices, the strongest marked over the gold when it is.
    assert.same({ "Dark Leather Tunic", "Keep Old Tunic" }, optsShown())
    -- The set back: what it adds and what it costs.
    result = aResult()
    H.RefreshIfShown(true)
    assert.equal("2 ticked: +6 Agility, +4.4 Damage Per Second", textOf(b.title))
    assert.equal("9088c", textOf(b.cost))
    assert.is_false(shown(t.note))
  end)

  it("says why there is nothing to show", function()
    local function message() return textOf(sp().message) end
    result = { slots = {}, loading = 0, noScan = true }
    H.Show()
    assert.equal("No scan with gear in it yet. Open the auction house and let GoldCap scan it.", message())
    assert.same({}, optsShown())
    assert.equal(1, H._state.sel)                                       -- no slot with choices: the first
    result = { slots = {}, loading = 0, noStats = true }
    H.RefreshIfShown(true)
    assert.equal("This client does not report item stats, so GoldCap cannot compare gear.", message())
    result = { slots = {}, loading = 0, noWeights = true }
    H.RefreshIfShown(true)
    assert.equal("No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5", message())
    result = { slots = {}, loading = 3, at = NOW, weights = {}, set = { picks = {}, list = {}, cost = 0, left = 0,
      diffs = {} } }
    H.RefreshIfShown(true)
    assert.equal("Nothing on the auction house beats what you wear at your level.", message())
    assert.equal("Items still loading: 3. Open this again in a moment.", textOf(top().note))
    result = aResult()
    H.RefreshIfShown(true)
    assert.is_false(shown(sp().message))
    -- A slot with nothing to buy says so, under what it wears.
    press(slotAt(1))
    assert.equal("HEAD", textOf(sp().title))
    assert.equal("Nothing on the auction house beats what you wear at your level.", message())
    assert.same({}, optsShown())
  end)

  -- In game, 13.11: five groups without choices right after a reload, the worn pieces' stats not
  -- read yet, and the panel saying nothing beat them.
  it("says a slot still waits for what is worn there, and that the picks may change", function()
    result.waiting, result.loading = { HEAD = true, FINGER = true }, 2
    H.Show()
    assert.equal("Still reading what you wear: the picks may change", textOf(bar().sub))
    press(slotAt(1))
    assert.equal("HEAD", textOf(sp().title))
    assert.equal("Still reading what you wear here. This fills in by itself.", textOf(sp().message))
    press(slotAt(12))
    assert.equal("Still reading what you wear here. This fills in by itself.", textOf(sp().message))
    press(slotAt(2))                                                    -- the neck waits for nothing
    assert.equal("Nothing on the auction house beats what you wear at your level.", textOf(sp().message))
    -- Read: the picks are GoldCap's again.
    result = aResult()
    H.RefreshIfShown(true)
    assert.equal("Picked by GoldCap for the gold you carry", textOf(bar().sub))
  end)

  it("gives the doll the room at the default window: a one-band bar and large slots", function()
    W.CLIENT_METRICS = true
    finally(function() W.CLIENT_METRICS = false end)
    -- The GoldCap window's own size on a fresh install, less its rail and title bar.
    W.state(H._view.container).width, W.state(H._view.container).height = 600, 552
    H.Show()
    assert.is_true(bar().frame:GetHeight() <= 64, bar().frame:GetHeight())
    assert.is_true(slotAt(1):GetWidth() >= 40, slotAt(1):GetWidth())
    assert.is_true(sp().frame:GetWidth() >= 330, sp().frame:GetWidth())
    assert.equal(W.LINE_H * 11 / 12, doll().hint:GetStringHeight())    -- one line
    -- A choice is two lines, its name and price over its gains, and so is keep: a piece that waits
    -- for a level too, with three stats, the line the level line used to take its gains from.
    result.slots[2].best.diffs = { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    H.RefreshIfShown(true)
    press(slotAt(16))
    local hs = heightsShown()
    assert.equal(5, #hs)
    for i = 1, #hs do
      assert.equal(hs[1], hs[i], i)
      assert.is_true(hs[i] <= 46, hs[i])
    end
  end)

  it("shows the gold toward a mount: the chip, its panel, a riding cost typed, a line to share", function()
    H.Show()
    local chip = top().mount
    assert.equal("MOUNT AT 40", textOf(chip.label))
    assert.equal(tostring(5973 + 4620) .. "c of 20000c", textOf(chip.value))
    press(chip.frame)
    local p = panel("mount")
    assert.is_true(shown(p))
    assert.equal(sp().frame, W.state(p).points[1][2])
    assert.equal("Gold for your mount", textOf(p.title))
    assert.equal("10593c of 20000c", textOf(p.big))
    assert.equal("12 items fetch more on the AH", textOf(p.lines.gain.text))
    assert.equal("3112c more than a vendor pays", textOf(p.lines.gain.small))
    press(p.sell)
    assert.equal("sell", views[#views])
    assert.equal("Play a little longer for an estimate of your pace. The 2 upgrades in your set leave 1505c toward it.",
      textOf(p.pace.text))
    -- The trainer's price stands while the box is empty; one typed is taken as the box lets go.
    assert.equal("100g at the trainer. Type your own after a discount.",
      textOf(p.costHint):gsub("1000000c", "100g"))
    assert.equal("", W.state(p.cost.box).text)
    local box = p.cost.box
    box:SetFocus()
    typeInto(box, "35g")
    box:ClearFocus()
    assert.equal(350000, prefs.mountCost)
    assert.equal("35g", W.state(box).text)
    box:SetFocus()
    typeInto(box, "lots")
    assert.is_true(p.cost.bad)
    box:ClearFocus()
    assert.equal(350000, prefs.mountCost)                         -- unreadable: nothing changed
    box:SetFocus()
    typeInto(box, "")
    box:ClearFocus()
    assert.is_nil(prefs.mountCost)                                -- empty: the trainer's price again
    press(p.secondary)
    assert.equal("Road to 40 with GoldCap: 1g 5s of 2g for my mount (52%).", chat)
    -- One panel at a time.
    press(top().weights)
    assert.equal("weights", H._state.panel)
    assert.is_true(p.slider == nil or p.slider:Leaving() or not shown(p))
  end)

  it("opens away from the auction house", function()
    windowShown = false
    H.Open()
    assert.is_true(toggled)
    assert.equal("hero", views[#views])
    toggled = false
    H.Open()                                                      -- already up: no second toggle, which would hide it
    assert.is_false(toggled)
    assert.equal("hero", views[#views])
  end)

  it("repaints once, a moment after item data arrives, and only while shown", function()
    builds = 0
    H.OnItemInfo()                                  -- never opened (retail, or not yet): nothing
    assert.equal(0, #timers)
    H.Show()
    assert.equal(1, builds)
    H.OnItemInfo()
    H.OnItemInfo()
    assert.equal(1, #timers)
    assert.equal(GC.Hero.C.REPAINT_S, delays[1])
    runTimers()
    assert.equal(2, builds)
    H.Hide()
    H.OnItemInfo()
    assert.equal(0, #timers)
  end)

  it("repaints once a moment after the gold carried or a worn piece changes, only while shown", function()
    builds = 0
    H.OnChange()                                    -- never opened: nothing
    assert.equal(0, #timers)
    H.Show()
    H.OnChange()
    H.OnChange()
    assert.equal(1, #timers)
    runTimers()
    assert.equal(2, builds)
    H.Hide()
    H.OnChange()
    assert.equal(0, #timers)
  end)

  it("never lets gold or gear repaints use up the cap on chasing an item that does not load", function()
    result = { slots = {}, loading = 1, loadingIds = { [42] = true } }
    H.Show()
    for _ = 1, GC.Hero.C.STALE_LIMIT + 2 do         -- buying on the auction house: PLAYER_MONEY after PLAYER_MONEY
      H.OnChange()
      runTimers()
    end
    H.OnItemInfo(42)                                 -- the item it waits for still gets its repaint
    assert.equal(1, due(GC.Hero.C.REPAINT_S))
  end)

  -- An id nobody was waiting for must not itself trigger a rebuild, and an id that never resolves
  -- must not keep the tab rebuilding forever.
  it("ignores an item it was not waiting for, and gives up once the loading count stops shrinking", function()
    result = { slots = {}, loading = 1, loadingIds = { [42] = true } }
    builds = 0
    H.Show()
    assert.equal(1, builds)
    H.OnItemInfo(7)                      -- not one of the ids the last build is waiting on
    assert.equal(0, due(GC.Hero.C.REPAINT_S))
    H.OnItemInfo(42)                     -- one it IS waiting on
    assert.equal(1, due(GC.Hero.C.REPAINT_S))
    -- Item 42 never actually resolves: loading stays at 1 every time. Run the storm cap's limit.
    for _ = 1, GC.Hero.C.STALE_LIMIT do
      runTimers()
      H.OnItemInfo(42)
    end
    runTimers()
    H.OnItemInfo(42)
    assert.equal(0, due(GC.Hero.C.REPAINT_S))  -- the storm cap has kicked in: no new timer
    -- Reopening the tab resets the cap.
    H.Show()
    H.OnItemInfo(42)
    assert.equal(1, due(GC.Hero.C.REPAINT_S))
  end)

  -- In game, 13.11: right after a reload six items were loading and the tab waited for an event
  -- that never came until the player searched the auction house.
  it("rebuilds itself once a second while items load, at most SELF_MAX times a show, and stops at none or on hide", function()
    local C = GC.Hero.C
    result = { slots = {}, loading = 2, loadingIds = { [42] = true } }
    builds = 0
    H.Show()
    assert.equal(1, due(C.SELF_S))
    for _ = 1, C.SELF_MAX + 5 do runTimers() end
    assert.equal(1 + C.SELF_MAX, builds)
    assert.equal(0, due(C.SELF_S))
    -- Other repaints on the way start no second chain, and a second Show leaves the first one dead.
    builds = 0
    H.Show()
    H.Show()
    H.OnChange()
    runTimers()                                     -- the dead chain's tick, the live one's, the gold's
    assert.equal(2 + 2, builds)
    assert.equal(1, due(C.SELF_S))
    -- Loaded: the chain stops.
    result = { slots = {}, loading = 0 }
    builds = 0
    runTimers()
    assert.equal(1, builds)
    assert.equal(0, due(C.SELF_S))
    -- Hidden: a tick already on its way rebuilds nothing.
    result = { slots = {}, loading = 1 }
    H.Show()
    builds = 0
    H.Hide()
    runTimers()
    assert.equal(0, builds)
    assert.equal(0, due(C.SELF_S))
  end)

  it("repaints while weapon speeds are still being read, only while that count shrinks", function()
    local pending = { 3, 2, 2, 2 }
    GC.ForeverUpgrades.Current = function()
      builds = builds + 1
      local r = aResult()
      r.speedPending = pending[math.min(builds, #pending)]
      return r
    end
    builds = 0
    H.Show()
    assert.equal(1, #timers)
    assert.equal(GC.Hero.C.SPEED_S, delays[1])
    runTimers()                                     -- 2: fewer, one more look
    assert.equal(2, builds)
    assert.equal(1, #timers)
    runTimers()                                     -- 2 again: a speed the client never tells stops it
    assert.equal(3, builds)
    assert.equal(0, #timers)
    -- Nothing pending, and an answer without the field, need nothing.
    GC.ForeverUpgrades.Current = function() return aResult() end
    H.Show()
    assert.equal(0, #timers)
  end)

  it("lays the top line on one line in a wide tab and the chip and button under the name in a narrow one", function()
    H.Show()
    local t = top()
    local function y(frame) return W.state(frame).points[1][5] end
    assert.equal(y(t.mount.frame), y(t.weights))
    assert.is_true(-y(t.mount.frame) < 10)
    W.state(H._view.container).width = 300
    H.RefreshIfShown(true)
    assert.is_true(-y(t.mount.frame) > 20)                        -- under the name, not beside it
  end)
end)
