local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/HeroFrame.lua: WoW: Forever's HERO tab as the character sheet the owner approved (board "6. v2",
-- 2026-11-13). The real Theme and kit, the real BUY lists (Core/AppRuns.lua), the real weights and
-- the words of Core/ForeverUpgrades.lua and the real /gc mount lines (Core/ForeverRoad.lua); what the
-- tab is handed is a seam: GC.ForeverUpgrades.Current answers `result`, GC.ForeverRoad.Snapshot
-- `road`, GetInventoryItemLink `wornLinks`, GC.Buy.BoughtOn `boughtOn[code]`. The window around it
-- (GC.Sniper) and the BUY tab (GC.Buy) are doubles that remember what they were asked. The widgets are spec/support/wow_frames.lua's,
-- read through W.state.
describe("HERO tab", function()
  local GC, H, restore, saved, timers, delays, prefs, result, road, builds, views, toggled, windowShown
  local selected, tipLink, tipShown, tipOwner, tipText, modified, clicked, chat, host, snapshots, wornLinks
  local units, noModel, modelAnswer, boughtOn
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
  -- Runs only the timers that wait `s` seconds; the others stay on their way.
  local function runDue(s)
    local fns, ds = timers, delays
    timers, delays = {}, {}
    for i, fn in ipairs(fns) do
      if ds[i] == s then
        fn()
      else
        timers[#timers + 1], delays[#delays + 1] = fn, ds[i]
      end
    end
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

  local function run() return prefs.heroList and GC.AppRuns.Get(prefs.heroList) or nil end
  local function doll() return H._view.doll end
  local function HERO_C() return GC.Hero.C end
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
  -- An option the list holds for its slot: its box filled, the check in it; else the "+".
  local function ticked(row)
    local glyph = W.state(row.boxGlyph).texCoord
    assert.same({ GC.Theme.IconCoords(shown(row.boxFill) and "check" or "plus") }, glyph)
    return shown(row.boxFill)
  end
  local function idsOf(list)
    local out = {}
    for _, line in ipairs(list and list.lines or {}) do out[#out + 1] = line.i end
    return out
  end
  -- The list's lines as the tab writes them: item, quantity, version.
  local function linesOf()
    local out = {}
    for _, line in ipairs(run() and run().lines or {}) do out[#out + 1] = { i = line.i, q = line.q, ver = line.ver } end
    return out
  end
  local function qOf(itemID)
    for _, line in ipairs(run() and run().lines or {}) do if line.i == itemID then return line.q end end
    return nil
  end
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
    timers, delays, builds, views, toggled, windowShown, snapshots, boughtOn = {}, {}, 0, {}, false, true, 0, {}
    selected, tipLink, tipShown, tipOwner, tipText, modified, clicked, chat = nil, nil, false, nil, nil, false, nil, nil
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
    -- The class icons, and the auction house's favourite star (Forever's Blizzard_AuctionHouseUI).
    _G.C_Texture = { GetAtlasInfo = function(atlas)
      return (atlas:find("^classicon%-") or atlas == "auctionhouse-icon-favorite") and {} or nil
    end }
    _G.C_Item = {
      GetItemIconByID = function(id) return 100000 + (tonumber(id) or 0) end,
      GetItemNameByID = function() return nil end,
      GetItemQualityByID = function() return 2 end,
    }
    _G.C_PaperDollInfo = { GetInventorySlotInfo = function(name) return 1, "slot:" .. name, false end }
    _G.GameTooltip = {
      SetOwner = function(_, owner) tipOwner = owner end, SetHyperlink = function(_, l) tipLink = l end,
      SetText = function(_, text) tipText = text end,
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
    -- The guide read already: the cases below look at the tab under it (the guide's own case clears it).
    prefs = { heroGuide = true }
    GC.ForeverScan = { Prefs = function() return prefs end }
    GC.Buy = {
      _SetLineCap = function(code, itemID, copper)
        GC.db.runLineCaps = GC.db.runLineCaps or {}
        GC.db.runLineCaps[code] = GC.db.runLineCaps[code] or {}
        GC.db.runLineCaps[code][itemID] = copper
      end,
      SelectRun = function(code) selected = code end,
      BoughtOn = function(code) return boughtOn[code] or {} end,
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
    host.heroTab = CreateFrame("Button", nil, host)                -- the rail's HERO tab (UI/SniperFrame.lua)
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

  it("draws every paper-doll slot in the client's order, the pieces on the list green with their price", function()
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
    -- Nothing on the list yet: a slot with choices shows what is worn there, framed thin and gold,
    -- and GoldCap's star inside its top right where GoldCap picks a piece for it.
    local chest, main = slotAt(5), slotAt(16)
    assert.equal(100000 + 85, W.state(chest.icon.icon).file)          -- the tunic worn
    assert.same(rgb(gold), colourOf(chest.frameRing))
    assert.is_false(shown(chest.badge))
    assert.is_false(shown(chest.price))
    assert.equal("slot:MainHandSlot", W.state(main.icon.icon).file)
    assert.same(rgb(gold), colourOf(main.frameRing))
    assert.same({ true, true }, { shown(chest.star), shown(main.star) })
    assert.equal("auctionhouse-icon-favorite", W.state(chest.star).atlas)
    local corner = W.state(chest.star).points[1]
    assert.same({ "TOPRIGHT", chest, "TOPRIGHT" }, { corner[1], corner[2], corner[3] })
    assert.is_true(corner[4] <= 0 and corner[5] <= 0)                  -- inside the slot's own square
    -- The tunic on the list: its icon, a green frame, the check and its price, and no star.
    press(opt(1))
    assert.is_false(shown(chest.star))
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
    -- The sword in the main hand. No level badges on the doll: the panel marks the club.
    press(main)
    press(opt(1))
    assert.equal(100000 + WATCH, W.state(main.icon.icon).file)
    assert.equal("75s", textOf(main.price))
    assert.is_nil(main.level)
    -- Green means on the list only: no icon on the doll wears its quality's edge.
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
      assert.is_false(shown(slotAt(inv).star), inv)
    end
    assert.is_false(shown(head.star))
    -- A piece of the player's own in the main hand: green, no star; off again, the star is back.
    press(slotAt(16))
    press(opt(1))
    press(opt(3))                                                       -- the hatchet
    assert.is_false(shown(main.star))
    press(opt(3))
    assert.is_true(shown(main.star))
    assert.equal("Click a slot to see what you can buy for it.", textOf(d.hint))
  end)

  it("selects the first slot with choices and lists them, GoldCap's pick first and starred", function()
    H.Show()
    assert.equal(5, H._state.sel)                                       -- the chest comes before the main hand
    assert.is_true(shown(slotAt(5).glow))
    assert.is_false(shown(slotAt(16).glow))
    local p = sp()
    assert.equal("CHEST", textOf(p.title))
    assert.equal("You wear Old Tunic", textOf(p.sub))
    assert.is_nil(p.hint)                                               -- the head, then the list
    assert.same({ "Dark Leather Tunic" }, optsShown())                  -- no row to keep what is worn
    assert.is_nil(opt(1).tags)                                          -- no chips
    assert.is_false(ticked(opt(1)))
    -- GoldCap's pick: the auction house's own favourite star before its name, on the name's line,
    -- the name moved right of it, nothing over the icon; and a thin gold frame.
    local row = opt(1)
    assert.is_true(shown(row.star))
    assert.equal("auctionhouse-icon-favorite", W.state(row.star.tex).atlas)
    assert.same({ HERO_C().STAR_W, HERO_C().STAR_H }, { row.star:GetWidth(), row.star:GetHeight() })
    local star, name, icon = W.state(row.star).points[1], W.state(row.name).points[1], W.state(row.icon.edge).points[1]
    assert.same({ "LEFT", row, "TOPLEFT" }, { star[1], star[2], star[3] })
    assert.is_true(star[4] >= icon[4] + HERO_C().OPT_ICON)              -- right of the icon
    assert.equal(star[4] + HERO_C().STAR_W + HERO_C().STAR_GAP, name[4]) -- the name after it
    assert.equal(name[5] - math.floor(row.name:GetLineHeight() / 2 + 0.5), star[5])
    assert.is_true(shown(row.pickRing))
    local gold = GC.Theme.color.gold
    assert.same({ gold[1], gold[2], gold[3], 0.85 }, W.state(row.pickRing).vertex)
    -- Its hover says what the star means, and the click goes on to the row.
    assert.is_true(W.state(row.star).mouseMotion)
    assert.is_false(W.state(row.star).mouseClicks)
    W.state(row.star).scripts.OnEnter(row.star)
    assert.equal("GoldCap's pick: part of the strongest mix your gold pays for", tipText)
    assert.equal(row.star, tipOwner)
    W.state(row.star).scripts.OnLeave(row.star)
    assert.is_false(tipShown)
    -- On the list: green over the gold, the star kept.
    press(row)
    assert.is_true(shown(row.onRing))
    assert.is_false(shown(row.pickRing))
    assert.is_true(shown(row.star))
    press(row)
    -- The main hand: the set's pick, the strongest, the others by what they add.
    -- Its list starts at the top, wherever the chest's was scrolled to.
    W.state(H._view.scroll).scroll = 40
    press(slotAt(16))
    assert.equal(0, H._view.scroll:GetVerticalScroll())
    assert.equal(16, H._state.sel)
    assert.is_true(shown(slotAt(16).glow))
    assert.is_false(shown(slotAt(5).glow))
    assert.equal("MAIN HAND", textOf(p.title))
    assert.equal("Nothing worn here", textOf(p.sub))
    assert.same({ "Night Watch Shortsword", "Skeletal Club", "Rusty Hatchet", "Bruiser Club" }, optsShown())
    assert.same({ true, false, false, false },
      { shown(opt(1).star), shown(opt(2).star), shown(opt(3).star), shown(opt(4).star) })
    assert.same({ true, false, false, false },
      { shown(opt(1).pickRing), shown(opt(2).pickRing), shown(opt(3).pickRing), shown(opt(4).pickRing) })
    -- A row without the star has its name where the words start.
    assert.equal(W.state(opt(1).star).points[1][4], W.state(opt(2).name).points[1][4])
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
    for _, i in ipairs({ 1, 3, 4 }) do
      assert.same({ 1, 1, 1, 1 }, W.state(opt(i).icon.icon).vertex, i)
      assert.equal("", textOf(opt(i).icon.count), i)
    end
    -- Its gains run the whole width, as wide as a piece's with nothing to wait for.
    assert.equal(opt(1).gain:GetWidth(), opt(2).gain:GetWidth())
    assert.is_true(opt(2).gain:GetWidth() > opt(2).name:GetWidth())
    -- Every row of one list as tall as the others.
    local hs = heightsShown()
    for i = 2, #hs do assert.equal(hs[1], hs[i], i) end
    assert.same({ false, false, false, false }, { ticked(opt(1)), ticked(opt(2)), ticked(opt(3)), ticked(opt(4)) })
    -- Its name in its quality's colour; what a piece gives up red.
    local q = GC.Theme.QualityColor(WATCH)
    assert.same({ q.r, q.g, q.b, 1 }, W.state(opt(1).name).color)
    -- The club usable now: its row untinted again, with no number.
    result.slots[2].best.later = nil
    H.RefreshIfShown(true)
    assert.same({ 1, 1, 1, 1 }, W.state(opt(2).icon.icon).vertex)
    assert.equal("", textOf(opt(2).icon.count))
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
    -- A rebuild keeps the slot the player looks at; a fresh open picks the first with choices again.
    press(slotAt(16))
    H.RefreshIfShown(true)
    assert.equal(16, H._state.sel)
    H.Hide()
    H.Show()
    assert.equal(5, H._state.sel)
  end)

  it("puts a piece on the Upgrades list with its +, takes it off with its check, one piece a slot", function()
    H.Show()
    press(slotAt(16))
    assert.is_nil(run())                                                -- no list until a piece goes on one
    local walks = snapshots
    press(opt(3))                                                       -- the hatchet
    assert.equal(walks, snapshots)                                      -- a click repaints; the bags are not walked again
    local list = run()
    assert.equal("Upgrades", list.name)
    assert.equal("game", list.origin)
    assert.same({ HATCHET }, idsOf(list))
    assert.equal(1, qOf(HATCHET))
    assert.equal(math.floor(2900 * 105 / 100), GC.db.runLineCaps[list.code][HATCHET])
    assert.same({ false, false, true, false }, { ticked(opt(1)), ticked(opt(2)), ticked(opt(3)), ticked(opt(4)) })
    assert.equal(100000 + HATCHET, W.state(slotAt(16).icon.icon).file)
    assert.equal("29s", textOf(slotAt(16).price))
    assert.same({}, views)                                              -- the tab stays: BUY opens from the bar
    -- Another piece for the same hand takes the hatchet's place on the list.
    press(opt(1))                                                       -- the sword
    assert.same({ WATCH }, idsOf(run()))
    assert.same({ true, false, false, false }, { ticked(opt(1)), ticked(opt(2)), ticked(opt(3)), ticked(opt(4)) })
    -- Its check takes it off: nothing for the main hand on the list, nothing on the doll.
    press(opt(1))
    assert.same({}, idsOf(run()))
    assert.is_false(ticked(opt(1)))
    assert.equal("slot:MainHandSlot", W.state(slotAt(16).icon.icon).file)
    assert.is_false(shown(slotAt(16).badge))
    assert.same(rgb(GC.Theme.color.gold), colourOf(slotAt(16).frameRing))
    -- The chest was never touched.
    assert.is_false(shown(slotAt(5).badge))
    -- The list is BUY's own: a line put there in BUY shows on the doll, and one taken off goes.
    GC.AppRuns.SetLines(run().code, { { i = TUNIC, q = 1 } })
    H.RefreshIfShown(true)
    assert.is_true(shown(slotAt(5).badge))
    GC.AppRuns.SetLines(run().code, {})
    H.RefreshIfShown(true)
    assert.is_false(shown(slotAt(5).badge))
  end)

  it("keeps the list as it is through a new scan, whatever GoldCap picks now", function()
    H.Show()
    press(opt(1))                                                       -- the tunic
    -- A new scan: the set takes a vest for the chest now.
    result = aResult()
    local vest = piece("CHEST", VEST, "Cracked Leather Vest", 900, { ITEM_MOD_AGILITY_SHORT = 3 }, { inSet = true })
    result.slots[1].best.inSet = false
    result.slots[1].alts = { vest }
    result.set.picks.CHEST, result.set.list[1] = vest, vest
    H.RefreshIfShown(true)
    assert.equal(100000 + TUNIC, W.state(slotAt(5).icon.icon).file)
    assert.same({ "Cracked Leather Vest", "Dark Leather Tunic" }, optsShown())
    assert.same({ true, false }, { shown(opt(1).star), shown(opt(2).star) })
    assert.same({ false, true }, { ticked(opt(1)), ticked(opt(2)) })
    assert.same({ { i = TUNIC, q = 1 } }, linesOf())
  end)

  it("says Bought on a piece bought on the list, and its + buys one more", function()
    H.Show()
    press(opt(1))                                                       -- the tunic
    local code = run().code
    boughtOn[code] = { [TUNIC] = 1 }
    H.RefreshIfShown(true)
    assert.equal("Bought", textOf(opt(1).price))
    assert.same(rgb(GC.Theme.color.fgMuted), rgb(W.state(opt(1).price).color))
    assert.is_false(ticked(opt(1)))
    assert.equal(100000 + 85, W.state(slotAt(5).icon.icon).file)       -- the doll: what is worn
    assert.equal("In your list: 0", textOf(bar().title))
    press(opt(1))
    assert.equal(2, qOf(TUNIC))
    assert.is_true(ticked(opt(1)))
    assert.equal("1589c", textOf(opt(1).price))
    assert.equal("In your list: 1", textOf(bar().title))
    -- Off again: down to what was bought, the line kept for it.
    press(opt(1))
    assert.equal(1, qOf(TUNIC))
    assert.equal("Bought", textOf(opt(1).price))
  end)

  it("buys one version of an item at a time", function()
    local watch = result.slots[2].alts[1]
    watch.version = "612"
    H.Show()
    press(slotAt(16))
    press(opt(1))
    assert.same({ { i = WATCH, q = 1, ver = "612" } }, linesOf())
    -- A new scan: the sword's lot now of another version, the one on the list gone.
    result = aResult()
    local other = result.slots[2].alts[1]
    other.version, other.unit = "607", 7000
    result.set.picks.MAINHAND = other
    H.RefreshIfShown(true)
    assert.is_false(ticked(opt(1)))                                     -- the list buys 612 only
    press(opt(1))
    assert.same({ { i = WATCH, q = 1, ver = "607" } }, linesOf())     -- 607 instead, one of it
    assert.equal(math.floor(7000 * 105 / 100), GC.db.runLineCaps[prefs.heroList][WATCH])
    assert.is_true(ticked(opt(1)))
    -- The same version again on the list, a cap the player raised in BUY kept.
    GC.db.runLineCaps[prefs.heroList][WATCH] = 9000
    press(opt(1))
    press(opt(1))
    assert.equal(1, qOf(WATCH))
    assert.equal(math.floor(7000 * 105 / 100), GC.db.runLineCaps[prefs.heroList][WATCH])
  end)

  it("the bar counts what the list holds, and says short by when it costs more than the gold carried", function()
    H.Show()
    local b = bar()
    assert.equal("In your list: 0", textOf(b.title))
    assert.is_false(shown(b.sub))
    assert.equal("LIST COST", textOf(b.costHead))
    assert.equal("0c", textOf(b.cost))
    assert.equal("LEFT AFTER", textOf(b.leftHead))
    assert.equal("5973c", textOf(b.left))
    assert.equal("Best for my gold (2)", textOf(b.picks.text))
    assert.is_true(b.picks:IsEnabled())
    assert.equal("Open BUY", textOf(b.open.text))
    assert.is_false(b.open:IsEnabled())                                 -- nothing on the list to open
    assert.is_nil(b.icons)                                              -- the doll shows what is on it
    press(opt(1))                                                       -- the tunic
    assert.equal("In your list: 1", textOf(b.title))
    assert.equal("+6 Agility, -4 Stamina", textOf(b.sub))
    assert.equal("1589c", textOf(b.cost))
    assert.equal(tostring(5973 - 1589) .. "c", textOf(b.left))
    assert.is_true(b.open:IsEnabled())
    press(slotAt(16))
    press(opt(1))                                                       -- the sword
    assert.equal("In your list: 2", textOf(b.title))
    assert.equal("+6 Agility, +4.4 Damage Per Second", textOf(b.sub))
    assert.equal("9088c", textOf(b.cost))
    assert.equal("Short by 3115c", textOf(b.left))
    assert.is_false(shown(b.leftHead))
    local red = GC.Theme.color.red
    assert.same({ red[1], red[2], red[3], 1 }, W.state(b.left).color)
    -- Open BUY: BUY, on the list.
    press(b.open)
    assert.equal(run().code, selected)
    assert.equal("buy", views[#views])
    -- A piece the build no longer offers stays on the list and in the count, at its line's cap.
    result = aResult()
    table.remove(result.slots[2].alts, 1)                               -- the sword's lot gone
    result.set.picks.MAINHAND, result.set.list[2] = nil, nil
    H.RefreshIfShown(true)
    assert.equal("slot:MainHandSlot", W.state(slotAt(16).icon.icon).file)
    assert.equal("In your list: 2", textOf(b.title))
    assert.equal("+6 Agility, -4 Stamina", textOf(b.sub))
    assert.equal(tostring(1589 + math.floor(7499 * 105 / 100)) .. "c", textOf(b.cost))
  end)

  it("Best for my gold puts GoldCap's picks on the list, each in its slot, and stays for the player to look over", function()
    H.Show()
    press(slotAt(16))
    press(opt(4))                                                       -- the bruiser, the player's own
    assert.equal("Best for my gold (2)", textOf(bar().picks.text))      -- neither pick on the list yet
    press(bar().picks)
    local list = run()
    -- The bruiser made way for the set's sword; the tunic went on beside it.
    local ids = idsOf(list)
    table.sort(ids)
    assert.same({ TUNIC, WATCH }, ids)
    assert.same({ 1, 1 }, { qOf(TUNIC), qOf(WATCH) })
    assert.equal(math.floor(1589 * 105 / 100), GC.db.runLineCaps[list.code][TUNIC])
    assert.equal(math.floor(7499 * 105 / 100), GC.db.runLineCaps[list.code][WATCH])
    assert.equal(prefs.heroList, list.code)
    -- The tab stays: the doll green, the bar what the list costs; BUY waits for "Open BUY".
    assert.same({}, views)
    assert.is_nil(selected)
    assert.same(rgb(GC.Theme.color.green), colourOf(slotAt(5).frameRing))
    assert.same(rgb(GC.Theme.color.green), colourOf(slotAt(16).frameRing))
    assert.equal("In your list: 2", textOf(bar().title))
    assert.equal("9088c", textOf(bar().cost))
    -- All of the picks on the list: nothing for it to add.
    assert.equal("Best for my gold (0)", textOf(bar().picks.text))
    assert.is_false(bar().picks:IsEnabled())
    -- One taken off with its check: that one again.
    press(slotAt(5))
    press(opt(1))
    assert.equal("Best for my gold (1)", textOf(bar().picks.text))
    assert.is_true(bar().picks:IsEnabled())
    press(bar().picks)
    assert.same({ 1, 1 }, { qOf(TUNIC), qOf(WATCH) })
    press(bar().open)
    assert.equal(list.code, selected)
    assert.equal("buy", views[#views])
    -- Both bought in BUY and not worn yet: the picks are not wanted again, and their stars stay off.
    boughtOn[list.code] = { [TUNIC] = 1, [WATCH] = 1 }
    H.RefreshIfShown(true)
    assert.equal("In your list: 0", textOf(bar().title))
    assert.equal("Best for my gold (0)", textOf(bar().picks.text))
    assert.is_false(bar().picks:IsEnabled())
    assert.same({ false, false }, { shown(slotAt(5).star), shown(slotAt(16).star) })
    press(bar().picks)
    assert.same({ 1, 1 }, { qOf(TUNIC), qOf(WATCH) })
    -- A row's own "+" still buys one more.
    press(slotAt(5))
    press(opt(1))
    assert.equal(2, qOf(TUNIC))
  end)

  it("makes a new Upgrades list when the remembered one is gone", function()
    prefs.heroList = "game-7"                                    -- deleted in BUY since
    H.Show()
    press(opt(1))
    assert.are_not.equal("game-7", prefs.heroList)
    assert.equal("Upgrades", run().name)
    assert.same({ TUNIC }, idsOf(run()))
    -- One the site made has the same code shape but is not the player's to rewrite: a new one again.
    GC.db.runs.SITE1234 = { code = "SITE1234", origin = "site", lines = { { i = TUNIC, q = 1 } } }
    prefs.heroList = "SITE1234"
    H.RefreshIfShown(true)
    assert.is_false(ticked(opt(1)))                                     -- not the tab's list
    press(opt(1))
    assert.are_not.equal("SITE1234", prefs.heroList)
    assert.same({ { i = TUNIC, q = 1 } }, GC.db.runs.SITE1234.lines)
    -- An archived Upgrades list comes back out of the archive as it is used.
    GC.db.runsArchived = { [prefs.heroList] = true }
    press(slotAt(16))
    press(opt(1))
    assert.is_nil(GC.db.runsArchived[prefs.heroList])
  end)

  -- One lot cannot fill two hands, and a two-hander takes both (BestSet's own rules): the list
  -- keeps them as the set does.
  it("keeps one piece to one hand and a two-hander to both, whichever hand it goes in", function()
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
    assert.same({ "slot:MainHandSlot", "slot:SecondaryHandSlot" }, { icon(16), icon(17) })
    -- A sword in each hand: two of it on one line.
    press(slotAt(16))
    press(opt(1))                                                       -- options: sword (set), axe
    press(slotAt(17))
    press(opt(2))                                                       -- options: buckler (set), sword
    assert.equal("Short Sword", textOf(opt(2).name))
    assert.same({ 100000 + SWORD, 100000 + SWORD }, { icon(16), icon(17) })
    assert.same({ { i = SWORD, q = 2 } }, linesOf())
    -- The axe in the main hand: both swords go.
    press(slotAt(16))
    press(opt(2))
    assert.equal("Woodsman Axe", textOf(opt(2).name))
    assert.same({ 100000 + AXE, "slot:SecondaryHandSlot" }, { icon(16), icon(17) })
    assert.same({ { i = AXE, q = 1 } }, linesOf())
    -- The buckler under the axe: the axe goes.
    press(slotAt(17))
    press(opt(1))
    assert.same({ "slot:MainHandSlot", 100000 + SHIELD }, { icon(16), icon(17) })
    assert.same({ { i = SHIELD, q = 1 } }, linesOf())
    assert.equal("In your list: 1", textOf(bar().title))
  end)

  -- What the tab is handed is ForeverUpgrades.Build's own answer: a warrior with two rings, each
  -- finger weighed against its own, and a ring on the auction house better than both.
  it("gives each finger its own choices, and a ring on the list twice is on both", function()
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::|h[Band " .. id .. "]|h|r" end
    wornLinks = { [11] = link(801), [12] = link(802) }
    local strength = { [801] = 6, [802] = 3, [800] = 9, [803] = 5 }
    local driver = {
      level = function() return 20 end,
      classFile = function() return "WARRIOR" end,
      equipped = function(slot) return wornLinks[slot] end,
      instant = function(id) if strength[id] then return "INVTYPE_FINGER", 4, 0 end end,
      info = function(str) return 1, link(tonumber(str:match("item:(%d+)"))) end,
      stats = function(str) return { ITEM_MOD_STRENGTH_SHORT = strength[tonumber(str:match("item:(%d+)"))] } end,
      usable = function() return true end,
      speed = function() return nil end,
      requestLoad = function() end,
      money = function() return 5000 end,
    }
    result = GC.ForeverUpgrades.Build({ v = 2, at = NOW - 60, items = { [800] = "70:0:0", [803] = "40:0:0" } },
      driver, { STR = 1 })
    H.Show()
    local gold, green = rgb(GC.Theme.color.gold), rgb(GC.Theme.color.green)
    assert.same({ gold, gold }, { colourOf(slotAt(11).frameRing), colourOf(slotAt(12).frameRing) })
    -- The first finger: only the band that beats the ring it wears.
    assert.equal(11, H._state.sel)
    assert.equal("FINGER", textOf(sp().title))
    assert.equal("You wear Band 801", textOf(sp().sub))
    assert.same({ "Band 800" }, optsShown())
    assert.is_false(shown(opt(1).star))                                 -- GoldCap puts it on the other finger
    press(opt(1))
    assert.equal(100000 + 800, W.state(slotAt(11).icon.icon).file)
    assert.same(green, colourOf(slotAt(11).frameRing))
    assert.equal(100000 + 802, W.state(slotAt(12).icon.icon).file)     -- the other finger as it is
    -- The second: the weaker ring's own choices, the band on the list for the first finger not here.
    press(slotAt(12))
    assert.equal("You wear Band 802", textOf(sp().sub))
    assert.same({ "Band 800", "Band 803" }, optsShown())
    assert.is_true(shown(opt(1).star))
    assert.is_false(ticked(opt(1)))
    press(opt(1))
    assert.same({ { i = 800, q = 2 } }, linesOf())
    assert.same({ green, green }, { colourOf(slotAt(11).frameRing), colourOf(slotAt(12).frameRing) })
    -- Off the first finger: the one left stays on the second.
    press(slotAt(11))
    press(opt(1))
    assert.same({ { i = 800, q = 1 } }, linesOf())
    assert.equal(100000 + 801, W.state(slotAt(11).icon.icon).file)
    assert.equal(100000 + 800, W.state(slotAt(12).icon.icon).file)
    -- Another band on the second finger: the first band comes off the list.
    press(slotAt(12))
    press(opt(2))
    assert.same({ { i = 803, q = 1 } }, linesOf())
    -- GoldCap's picks: the band on the second finger, where the set puts it. After a reload, which
    -- forgets where the player put what, it is still there, and the picks are on the list already.
    press(bar().picks)
    assert.same({ { i = 800, q = 1 } }, linesOf())
    H._state.placed = {}
    H.Hide()
    H.Show()
    assert.equal(100000 + 801, W.state(slotAt(11).icon.icon).file)
    assert.equal(100000 + 800, W.state(slotAt(12).icon.icon).file)
    assert.equal("+6 Strength", textOf(bar().sub))
    assert.is_false(bar().picks:IsEnabled())
    assert.is_false(shown(slotAt(12).star))
    press(bar().picks)
    assert.same({ { i = 800, q = 1 } }, linesOf())
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
    assert.equal(100000 + 85, W.state(slotAt(5).icon.icon).file)
    assert.equal("In your list: 0", textOf(bar().title))
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
    press(opt(2))                                                       -- the club on the list: the bar's gains show
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
    for _, button in ipairs({ bar().picks, bar().open }) do
      assert.is_true(button:GetWidth() >= button.text:GetUnboundedStringWidth())
    end
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
    assert.is_false(ticked(row))                                       -- a shift-click links it, lists nothing
    assert.is_nil(run())
    modified = false
    -- A doll slot shows what it shows: the piece on the list, else what is worn.
    press(opt(1))
    local main = slotAt(16)
    assert.is_true(W.state(main).mouse)
    W.state(main).scripts.OnEnter(main)
    assert.equal(result.slots[2].alts[1].link, tipLink)
    W.state(slotAt(5)).scripts.OnLeave(slotAt(5))
    assert.is_false(tipShown)
    W.state(slotAt(5)).scripts.OnEnter(slotAt(5))
    assert.equal(wornLinks[5], tipLink)
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

  -- Owner, 14.11: "+0.7 DPS" instead of adding up -4 Agility and +14 Attack Power.
  it("says on each choice what it adds to the character's DPS, then only the stats that figure leaves out", function()
    local green, red, muted = GC.Theme.color.green, GC.Theme.color.red, GC.Theme.color.fgMuted
    local function hex(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
      math.floor(c[3] * 255 + 0.5)) end
    local r = aResult()
    local tunic = r.slots[1].best
    tunic.dps, tunic.diffs = 0.66, { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STAMINA_SHORT = -4, ITEM_MOD_ATTACK_POWER_SHORT = 2 }
    local slot = r.slots[2]
    slot.best.dps, slot.alts[1].dps, slot.alts[2].dps = -0.34, 0.01, nil
    result = r
    H.Show()
    assert.equal("+0.7 DPS, -4 Stamina", textOf(opt(1).gain))
    assert.equal(hex(green) .. "+0.7 DPS|r, " .. hex(red) .. "-4 Stamina|r", W.state(opt(1).gain).text)
    -- A choice that costs DPS says it in red, one that changes it by less than 0.05 says 0.0, and
    -- one without a figure reads as before.
    press(slotAt(16))
    assert.equal("0.0 DPS, +4 Stamina", textOf(opt(1).gain))                    -- the sword, the set's
    assert.equal(hex(muted) .. "0.0 DPS|r, " .. hex(green) .. "+4 Stamina|r", W.state(opt(1).gain).text)
    assert.equal("-0.3 DPS", textOf(opt(2).gain))                                -- the club
    assert.equal(hex(red) .. "-0.3 DPS|r", W.state(opt(2).gain).text)
    assert.equal("+2 Strength, +2 Damage Per Second", textOf(opt(4).gain))       -- the bruiser
    -- The bar sums what the list's pieces add: their DPS, and the tunic's stamina and the sword's even out.
    press(slotAt(5))
    press(opt(1))
    assert.equal("+0.7 DPS, -4 Stamina", textOf(bar().sub))
    press(slotAt(16))
    press(opt(1))
    assert.equal("+0.7 DPS", textOf(bar().sub))
  end)

  it("shows the weights the character's numbers set, to two decimals, and saves them as shown once one is typed", function()
    local U = GC.ForeverUpgrades
    local m = U.DpsModel("ROGUE", { ap = 100, rap = 50, crit = 0.05, apPer = { STR = 1, AGI = 1 }, rapPer = { AGI = 1 },
      critPer = { AGI = 0.0005 } }, { MAINHAND = { dps = 8, speed = 1.8 }, OFFHAND = { dps = 6 } })
    result.model = m
    H.Show()
    press(top().weights)
    local p = panel("weights")
    local note = "Strength, Agility, Attack Power and DPS come from your character and change as it levels and gears up."
      .. " Change a number and yours stay until Reset."
    assert.equal(note, textOf(p.derived))
    assert.is_true(shown(p.derived))
    assert.same({ "0.92", "0.77", "0.85", "7.35", "0.4", "0.01" }, { W.state(p.boxes.AGI.box).text,
      W.state(p.boxes.STR.box).text, W.state(p.boxes.AP.box).text, W.state(p.boxes.DPS.box).text,
      W.state(p.boxes.STA.box).text, W.state(p.boxes.ARMOR.box).text })
    -- A number typed: the whole table saved as the boxes showed it, and the boxes the player's now.
    typeInto(p.boxes.STA.box, "0.5")
    assert.same({ AGI = 0.92, STR = 0.77, AP = 0.85, DPS = 7.35, STA = 0.5, ARMOR = 0.01 }, prefs.weights.ROGUE)
    H.RefreshIfShown(true)
    assert.is_false(shown(p.derived))
    assert.equal("0.92", W.state(p.boxes.AGI.box).text)
    -- Reset: from the character again.
    press(p.secondary)
    assert.is_nil(prefs.weights.ROGUE)
    assert.is_true(shown(p.derived))
    -- No model (a mage, or a client that did not answer): the defaults, and no line.
    result.model = nil
    H.RefreshIfShown(true)
    assert.is_false(shown(p.derived))
    assert.equal("1", W.state(p.boxes.AGI.box).text)
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

  -- 14.11: every class's DPS row says what weapon DPS is to that class, and leads where it counts.
  it("says under DPS what each class's weapon DPS is", function()
    local HINT = {
      ROGUE = "Main hand, about 14 attack power. Off hand half, gun or bow a seventh",
      WARRIOR = "Main hand, about 14 attack power. Off hand half, gun or bow a seventh",
      PALADIN = "Main hand, about 14 attack power", SHAMAN = "Main hand, about 14 attack power",
      HUNTER = "The bow, gun or crossbow: about 14 attack power. Melee weapons hardly count",
      MAGE = "The wand's damage per second. A staff or dagger counts for its stats only",
      PRIEST = "The wand's damage per second. A staff or dagger counts for its stats only",
      WARLOCK = "The wand's damage per second. A staff or dagger counts for its stats only",
      DRUID = "Cat and bear forms do not use it, so it counts for nothing",
    }
    H.Show()
    H.TogglePanel("weights")
    local p = panel("weights")
    for class, hint in pairs(HINT) do
      _G.UnitClass = function() return class, class, 1 end
      H.RefreshIfShown(true)
      local dps
      for _, row in ipairs(p.rows) do if row.token == "DPS" and shown(row.frame) then dps = row end end
      assert.equal(hint, textOf(dps.hint), class)
      -- DPS second, after the class's top stat, wherever its defaults weigh it; a druid's further down.
      assert.equal(class ~= "DRUID", (statsShown(p))[2] == "DPS", class)
    end
  end)

  it("says what to do when nothing fits the purse, and when the scan is stale", function()
    result.set = { picks = {}, list = {}, cost = 0, left = 5973, diffs = {} }
    result.stale = true
    H.Show()
    local b, t = bar(), top()
    assert.equal("Nothing on the auction house fits the gold you carry yet.", textOf(b.title))
    assert.is_false(shown(b.sub))
    assert.equal("Best for my gold (0)", textOf(b.picks.text))
    assert.is_false(b.picks:IsEnabled())
    assert.is_false(b.open:IsEnabled())
    assert.equal("5973c", textOf(b.left))
    assert.equal("Scan again to read each version's own stats.", textOf(t.note))
    assert.equal("Rogue · level 17", textOf(t.name))
    assert.equal("Scan 4m ago", textOf(t.sub))
    -- Every slot still shows its choices, the strongest marked over the gold when it is.
    assert.same({ "Dark Leather Tunic" }, optsShown())
    -- The set back: its picks one press away.
    result = aResult()
    H.RefreshIfShown(true)
    assert.equal("In your list: 0", textOf(b.title))
    assert.is_true(b.picks:IsEnabled())
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
    result.waiting, result.loading = { HEAD = true, FINGER2 = true }, 2
    H.Show()
    -- First the tab settles: how many items are left, and not the wait as well.
    assert.equal("Reading the auction house's items: 2 left.", textOf(sp().message))
    assert.is_false(shown(bar().sub))
    runDue(GC.Hero.C.HOLD_S)                                            -- the client never answered
    assert.equal("Items still loading: 2. Open this again in a moment.", textOf(top().note))
    assert.equal("Still reading what you wear: the picks may change", textOf(bar().sub))
    press(slotAt(1))
    assert.equal("HEAD", textOf(sp().title))
    assert.equal("Still reading what you wear here. This fills in by itself.", textOf(sp().message))
    press(slotAt(12))
    assert.equal("Still reading what you wear here. This fills in by itself.", textOf(sp().message))
    press(slotAt(2))                                                    -- the neck waits for nothing
    assert.equal("Nothing on the auction house beats what you wear at your level.", textOf(sp().message))
    press(slotAt(11))                                                   -- the other finger waits for nothing
    assert.equal("Nothing on the auction house beats what you wear at your level.", textOf(sp().message))
    -- With a piece on the list, what it adds, then the wait.
    press(slotAt(5))
    press(opt(1))
    assert.equal("+6 Agility, -4 Stamina\nStill reading what you wear: the picks may change", textOf(bar().sub))
    -- Read: the line goes.
    result = aResult()
    H.RefreshIfShown(true)
    assert.equal("+6 Agility, -4 Stamina", textOf(bar().sub))
  end)

  -- In game, 14.11: after a reload the tab opened at "Items still loading: 67", then 13, then 0,
  -- and every partial build moved the gold frames and stars between slots and "Best for my gold"
  -- from (1) to (3). It waits now, the picks held back, and shows them once.
  it("holds GoldCap's picks back while the game still loads items, and shows them once it has", function()
    local gold = GC.Theme.color.gold
    local function calm(left)
      for _, inv in ipairs(DOLL_ORDER) do
        local b = slotAt(inv)
        assert.are_not.same(rgb(gold), colourOf(b.frameRing), inv)
        assert.is_false(shown(b.star), inv)
        assert.is_false(shown(b.badge), inv)
      end
      assert.equal(100000 + 85, W.state(slotAt(5).icon.icon).file)     -- what is worn
      assert.equal("Best for my gold", textOf(bar().picks.text))
      assert.is_false(bar().picks:IsEnabled())
      local note = ("Reading the auction house's items: %d left."):format(left)
      assert.equal(note, textOf(top().note))
      assert.equal(note, textOf(sp().message))
      assert.same({}, optsShown())
    end
    -- The guide up: a slot clicked while the tab settles is selected, and the guide stays.
    prefs.heroGuide = nil
    result.loading = 67
    H.Show()
    assert.is_true(H._state.settling)
    calm(67)
    assert.equal("In your list: 0", textOf(bar().title))
    assert.equal(1, H._state.sel)                                       -- no slot chosen by its choices yet
    press(slotAt(16))
    assert.equal(16, H._state.sel)
    assert.equal("MAIN HAND", textOf(sp().title))
    assert.is_true(H._state.guide)
    assert.is_true(shown(H._view.guide))
    press(H._view.guide.primary)
    calm(67)
    -- 13 left: still calm.
    result.loading = 13
    H.RefreshIfShown()
    calm(13)
    -- All read: the frames, the stars and the count, once.
    result.loading = 0
    H.RefreshIfShown()
    assert.is_false(H._state.settling)
    assert.same(rgb(gold), colourOf(slotAt(5).frameRing))
    assert.same({ true, true }, { shown(slotAt(5).star), shown(slotAt(16).star) })
    assert.equal("Best for my gold (2)", textOf(bar().picks.text))
    assert.is_true(bar().picks:IsEnabled())
    assert.is_false(shown(top().note))
    assert.equal(5, H._state.sel)                                       -- the guide put away: the first with choices
    assert.same({ "Dark Leather Tunic" }, optsShown())
    -- Nothing loading at the Show: nothing held back, and no hold on its way.
    local holds = due(GC.Hero.C.HOLD_S)
    H.Hide()
    H.Show()
    assert.is_false(H._state.settling)
    assert.equal(holds, due(GC.Hero.C.HOLD_S))
  end)

  it("stops holding back when its own rebuilds give up, after HOLD_S, and never again until the next Show", function()
    local C, gold = GC.Hero.C, GC.Theme.color.gold
    local function settled()
      assert.is_false(H._state.settling)
      assert.same(rgb(gold), colourOf(slotAt(5).frameRing))
      assert.is_true(bar().picks:IsEnabled())
    end
    -- An item the client never answers for: the count stays at 5, and the rebuild that makes the
    -- SELF_FLAT-th in a row loading nothing is the chain's last, and shows the picks.
    GC.ForeverUpgrades.Current = function()
      builds = builds + 1
      local r = aResult()
      r.loading = 5
      return r
    end
    H.Show()
    for _ = 1, C.SELF_FLAT - 1 do
      runDue(C.SELF_S)
      assert.is_true(H._state.settling)
    end
    runDue(C.SELF_S)
    settled()
    assert.equal(0, due(C.SELF_S))
    assert.equal("Items still loading: 5. Open this again in a moment.", textOf(top().note))
    -- A scan's build with items loading again moves nothing back.
    local r = aResult()
    r.loading = 9
    H.Render(r, NOW)
    settled()
    assert.equal("Items still loading: 9. Open this again in a moment.", textOf(top().note))
    -- Items that keep answering but never finish: HOLD_S after the Show, the picks show, with no
    -- build of its own.
    local loading = 40
    GC.ForeverUpgrades.Current = function()
      builds = builds + 1
      loading = loading - 1
      local out = aResult()
      out.loading = loading
      return out
    end
    timers, delays = {}, {}                                             -- the first Show's hold, dead
    H.Show()
    for _ = 1, 4 do runDue(C.SELF_S) end
    assert.is_true(H._state.settling)
    assert.equal(1, due(C.HOLD_S))
    builds = 0
    runDue(C.HOLD_S)
    assert.equal(0, builds)
    settled()
    assert.equal(1, due(C.SELF_S))                                      -- the rebuilds go on
    -- A hold from an earlier Show does nothing to a later one.
    H.Show()
    H.Hide()
    H.Show()
    assert.equal(2, due(C.HOLD_S))
    timers[1]()                                                         -- the dead one, run first
    assert.is_true(H._state.settling)
    runDue(C.HOLD_S)
    settled()
  end)

  it("stops holding back when the storm cap gives up on an item", function()
    local C = GC.Hero.C
    result.loading, result.loadingIds = 1, { [42] = true }
    H.Show()
    -- The first repaint sets the count it is measured from; each after it that loads nothing is one.
    for _ = 1, C.STALE_LIMIT do
      H.OnItemInfo(42)
      runDue(C.REPAINT_S)
    end
    assert.is_true(H._state.settling)
    H.OnItemInfo(42)
    runDue(C.REPAINT_S)
    assert.is_false(H._state.settling)
  end)

  it("gives the doll the room at the default window: a one-band bar and large slots", function()
    W.CLIENT_METRICS = true
    finally(function() W.CLIENT_METRICS = false end)
    -- The GoldCap window's own size on a fresh install, less its rail and title bar.
    W.state(H._view.container).width, W.state(H._view.container).height = 600, 552
    H.Show()
    assert.is_true(bar().frame:GetHeight() <= 64, bar().frame:GetHeight())
    -- With the set on the list: the count, what it adds, short by, the two buttons, still one band.
    press(bar().picks)
    assert.equal("In your list: 2", textOf(bar().title))
    assert.is_true(shown(bar().sub))
    assert.is_true(bar().frame:GetHeight() <= 64, bar().frame:GetHeight())
    local mid = W.state(bar().open).points[1][5]
    assert.equal(mid, W.state(bar().picks).points[1][5])           -- beside the words, not under them
    assert.is_true(-mid < bar().frame:GetHeight() / 2 + 1)
    assert.is_true(slotAt(1):GetWidth() >= 40, slotAt(1):GetWidth())
    assert.is_true(sp().frame:GetWidth() >= 330, sp().frame:GetWidth())
    assert.equal(W.LINE_H * 11 / 12, doll().hint:GetStringHeight())    -- one line
    -- A choice is two lines, its name and price over its gains: a piece that waits for a level too,
    -- with three stats, the line the level line used to take its gains from.
    result.slots[2].best.diffs = { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 }
    H.RefreshIfShown(true)
    press(slotAt(16))
    local hs = heightsShown()
    assert.equal(4, #hs)
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
    assert.equal("Play a little longer for an estimate of your pace.", textOf(p.pace.text))
    -- The pieces on the list, and what they leave toward it.
    press(bar().picks)
    assert.equal("Play a little longer for an estimate of your pace. The 2 upgrades on your list leave 1505c toward it.",
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
  -- In game, 13.11: right after a reload six items were loading and the tab waited for an event
  -- that never came until the player searched the auction house.
  it("rebuilds itself once a second while items load, at most SELF_MAX times a show, and stops at none or on hide", function()
    local C = GC.Hero.C
    -- One item more answers each second: the count always shrinks.
    local loading = 40
    GC.ForeverUpgrades.Current = function()
      builds = builds + 1
      loading = loading - 1
      return { slots = {}, loading = loading, loadingIds = { [42] = true } }
    end
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
    GC.ForeverUpgrades.Current = function() builds = builds + 1; return { slots = {}, loading = 0 } end
    builds = 0
    runTimers()
    assert.equal(1, builds)
    assert.equal(0, due(C.SELF_S))
    -- Hidden: a tick already on its way rebuilds nothing.
    GC.ForeverUpgrades.Current = function() builds = builds + 1; return { slots = {}, loading = 1 } end
    H.Show()
    builds = 0
    H.Hide()
    runTimers()
    assert.equal(0, builds)
    assert.equal(0, due(C.SELF_S))
  end)

  -- An item the client never answers for keeps the count where it is: three rebuilds of its own
  -- that loaded nothing, and the tab stops asking until it is opened again.
  it("stops rebuilding itself after SELF_FLAT rebuilds in a row that loaded nothing", function()
    local C = GC.Hero.C
    local counts = { 5, 4, 4, 4, 4, 4, 4 }
    GC.ForeverUpgrades.Current = function()
      builds = builds + 1
      return { slots = {}, loading = counts[math.min(builds, #counts)] }
    end
    builds = 0
    H.Show()                                        -- 5
    runTimers()                                     -- 4: fewer
    for _ = 1, C.SELF_FLAT do runTimers() end       -- 4, 4, 4: flat
    assert.equal(2 + C.SELF_FLAT, builds)
    assert.equal(0, due(C.SELF_S))
    runTimers()
    assert.equal(2 + C.SELF_FLAT, builds)
    -- One that loaded something in between starts the count again.
    counts, builds = { 6, 6, 5, 5, 5, 5 }, 0
    H.Show()                                        -- 6
    runTimers()                                     -- 6: one flat
    runTimers()                                     -- 5: fewer, the count again from none
    for _ = 1, C.SELF_FLAT do runTimers() end
    assert.equal(3 + C.SELF_FLAT, builds)
    assert.equal(0, due(C.SELF_S))
  end)

  it("keeps the movement keys the player's while a side panel is up, in a fight too", function()
    H.Show()
    H.TogglePanel("weights")
    local p = panel("weights")
    assert.is_true(W.state(p).keyboard)
    assert.is_true(p:GetPropagateKeyboardInput())                  -- on before any key comes
    local scripts = W.state(p).scripts
    scripts.OnKeyDown(p, "W")
    assert.is_true(p:GetPropagateKeyboardInput())
    -- Escape shuts the panel and is the panel's own; its release hands the keys back.
    scripts.OnKeyDown(p, "ESCAPE")
    assert.is_false(p:GetPropagateKeyboardInput())
    assert.is_nil(H._state.panel)
    scripts.OnKeyUp(p, "ESCAPE")
    assert.is_true(p:GetPropagateKeyboardInput())
    -- A fight began between the press and the release: the release waits for the fight's end, and
    -- the panel shown again hands the keys back as it shows.
    H.TogglePanel("weights")
    scripts.OnKeyDown(p, "ESCAPE")
    _G.InCombatLockdown = function() return true end
    scripts.OnKeyUp(p, "ESCAPE")
    assert.is_false(p:GetPropagateKeyboardInput())
    _G.InCombatLockdown = function() return false end
    W.state(p).hooks.OnShow(p)
    assert.is_true(p:GetPropagateKeyboardInput())
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
    local function x(frame) return W.state(frame).points[1][4] end
    assert.equal(y(t.mount.frame), y(t.weights))
    assert.equal(y(t.help), y(t.weights))
    assert.is_true(-y(t.mount.frame) < 10)
    -- The chip, "?" square, then the button, ending at the right edge.
    assert.is_true(x(t.mount.frame) < x(t.help) and x(t.help) < x(t.weights))
    assert.equal(t.help:GetWidth(), t.help:GetHeight())
    assert.equal(H._view.width, x(t.weights) + t.weights:GetWidth())
    W.state(H._view.container).width = 300
    H.RefreshIfShown(true)
    assert.is_true(-y(t.mount.frame) > 20)                        -- under the name, not beside it
    assert.is_true(x(t.mount.frame) < x(t.help) and x(t.help) < x(t.weights))
  end)

  -- Owner, 14.11: players have to understand what the tab is and what it is for.
  it("explains itself the first time it opens, until the player has read it", function()
    prefs.heroGuide = nil
    H.Show()
    local g = H._view.guide
    assert.is_true(shown(g))
    -- Over the slot panel's area, under the side panels, and the keys stay the window's.
    assert.equal(sp().frame, W.state(g).points[1][2])
    assert.equal(sp().frame, W.state(g).points[2][2])
    assert.is_false(W.state(g).keyboard)
    assert.equal("How HERO works", textOf(g.title))
    assert.equal("HERO: gear upgrades for your character from the auction house", textOf(g.sub))
    assert.equal("Interface\\Icons\\INV_Sword_04", W.state(g.icon).file)
    -- Four steps, each with its picture at the left of its words.
    assert.equal(4, #g.steps)
    local words = {
      "A gold frame: the auction house has something better for that slot. Click the slot to see its choices.",
      "+ puts a piece on your Upgrades list, its check takes it off. The star is GoldCap's pick.",
      "Best for my gold puts the strongest mix your gold pays for on the list. The bar shows what the list costs and the gold left.",
      "Open BUY and buy the list there, at the auction house. Stat weights sets what counts for your class.",
    }
    for i, st in ipairs(g.steps) do
      assert.equal(words[i], textOf(st.text), i)
      assert.is_true(W.state(st.text).points[1][4] >= GC.Hero.C.GUIDE_COL, i)
      assert.equal(st.frame, W.state(st.art).points[1][2], i)
    end
    local slot, plus, coin, buy = g.steps[1], g.steps[2], g.steps[3], g.steps[4]
    assert.equal("Interface\\Icons\\INV_Boots_05", W.state(slot.icon.icon).file)
    assert.same(rgb(GC.Theme.color.gold), colourOf(slot.ring))
    assert.same({ GC.Theme.IconCoords("plus") }, W.state(plus.glyph).texCoord)
    assert.equal("auctionhouse-icon-favorite", W.state(plus.star).atlas)
    assert.equal("Interface\\Icons\\INV_Misc_Coin_01", W.state(coin.icon.icon).file)
    assert.same({ GC.Theme.IconCoords("buy") }, W.state(buy.glyph).texCoord)
    assert.equal("Got it", textOf(g.primary.text))
    assert.is_false(shown(g.close))
    assert.is_false(shown(g.secondary))
    -- No slot is listed under it, and "?" is lit.
    assert.is_false(shown(slotAt(5).glow))
    local help, lit = top().help, nil
    local setVariant = help.SetVariant
    help.SetVariant = function(self, name) lit = name; return setVariant(self, name) end
    H.RefreshIfShown(true)
    assert.equal("active", lit)
    -- The weights open over it as over a slot, and shut back onto it.
    press(top().weights)
    assert.equal("weights", H._state.panel)
    assert.is_true(shown(g))
    press(panel("weights").primary)
    assert.is_true(shown(g))
    -- Got it: remembered, the first slot with choices listed.
    press(g.primary)
    assert.is_true(prefs.heroGuide)
    assert.is_false(shown(g))
    assert.equal("ghost", lit)
    assert.equal(5, H._state.sel)
    assert.is_true(shown(slotAt(5).glow))
    H.Hide()
    H.Show()
    assert.is_false(shown(g))                                    -- read: it stays away
  end)

  it("puts the guide away for a slot clicked without remembering it, and brings it back from ?", function()
    prefs.heroGuide = nil
    H.Show()
    local g = H._view.guide
    press(slotAt(16))
    assert.is_false(shown(g))
    assert.is_nil(prefs.heroGuide)
    assert.equal(16, H._state.sel)
    assert.equal("MAIN HAND", textOf(sp().title))
    H.Hide()
    H.Show()
    assert.is_true(shown(g))                                     -- not read yet: up again
    press(g.primary)
    -- "?" brings it back over an open panel, its tooltip says what it is; a second press puts it away.
    local help = top().help
    assert.equal("?", textOf(help.text))
    W.state(help).hooks.OnEnter(help)
    assert.equal("How HERO works", tipText)
    W.state(help).hooks.OnLeave(help)
    press(top().weights)
    press(help)
    assert.is_true(shown(g))
    assert.is_nil(H._state.panel)
    assert.is_true(prefs.heroGuide)
    press(help)
    assert.is_false(shown(g))
  end)

  it("says what HERO is for under the cursor on its rail tab", function()
    local tab = host.heroTab
    W.state(tab).hooks.OnEnter(tab)
    assert.equal("HERO: gear upgrades for your character from the auction house", tipText)
    assert.equal(tab, tipOwner)
    assert.is_true(tipShown)
    W.state(tab).hooks.OnLeave(tab)
    assert.is_false(tipShown)
  end)
end)
