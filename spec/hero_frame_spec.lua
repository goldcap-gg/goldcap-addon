local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/HeroFrame.lua: WoW: Forever's HERO tab, as the owner approved the board "Main" (2026-11-13).
-- The real Theme and kit, the real BUY lists (Core/AppRuns.lua), the real weights and the words of
-- Core/ForeverUpgrades.lua and the real /gc mount lines (Core/ForeverRoad.lua); what the tab is
-- handed is a seam: GC.ForeverUpgrades.Current answers `result`, GC.ForeverRoad.Snapshot `road`.
-- The window around it (GC.Sniper) and the BUY tab (GC.Buy) are doubles that remember what they
-- were asked. The widgets are spec/support/wow_frames.lua's, read through W.state.
describe("HERO tab", function()
  local GC, H, restore, saved, timers, delays, prefs, result, road, builds, views, toggled, windowShown
  local selected, tipLink, tipShown, tipOwner, modified, clicked, chat, host
  local KEYS = { "UIParent", "C_Item", "C_Timer", "GameTooltip", "HandleModifiedItemClick", "UnitClass", "UnitLevel",
    "GetMoney", "RAID_CLASS_COLORS", "GetClassAtlas", "C_Texture", "C_PaperDollInfo", "GetInventorySlotInfo",
    "GetCoinTextureString", "ChatFrame_OpenChat", "InCombatLockdown", "ITEM_MOD_STRENGTH_SHORT",
    "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "RESISTANCE0_NAME",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_CHEST", "INVTYPE_HEAD", "ITEM_QUALITY_COLORS", "time" }
  local NOW = 1800000000
  local CLUB, WATCH, BRUISER, TUNIC = 2130, 15210, 2131, 2316

  local function plain(text) return helper.plain(text) end
  local function textOf(fs) return plain(W.state(fs).text or "") end
  local function shown(widget) return W.state(widget).shown and true or false end
  local function press(widget) W.state(widget).scripts.OnClick(widget, "LeftButton", false) end
  local function runTimers()
    local due = timers
    timers, delays = {}, {}
    for _, fn in ipairs(due) do fn() end
  end
  -- What a player types into a box: the text, then the client's OnTextChanged with userInput true.
  local function typeInto(box, text)
    W.state(box).text = text
    W.state(box).scripts.OnTextChanged(box, true)
  end

  local function piece(group, itemID, name, unit, diffs, extra)
    local c = { group = group, itemID = itemID, itemString = "item:" .. itemID,
      link = "|cff1eff00|Hitem:" .. itemID .. "::::|h[" .. name .. "]|h|r", unit = unit, gain = 1, diffs = diffs,
      version = nil }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
  end

  -- A level 17 rogue with 59s 73c: a club it can wear at 19 is the strongest main hand, a sword the
  -- set takes is one of the other choices; a tunic is the strongest chest piece and in the set too.
  local function aResult()
    local club = piece("MAINHAND", CLUB, "Skeletal Club", 3990, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6.5 }, { later = 19 })
    local watch = piece("MAINHAND", WATCH, "Night Watch Shortsword", 7499,
      { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.4, ITEM_MOD_STAMINA_SHORT = 4 }, { inSet = true })
    local bruiser = piece("MAINHAND", BRUISER, "Bruiser Club", 2700,
      { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2, ITEM_MOD_STRENGTH_SHORT = 2 })
    local tunic = piece("CHEST", TUNIC, "Dark Leather Tunic", 1589,
      { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STAMINA_SHORT = -4 }, { inSet = true })
    return {
      at = NOW - 240, loading = 0, weights = { AGI = 1 }, style = "sinister",
      slots = {
        { group = "MAINHAND", labelKey = "INVTYPE_WEAPONMAINHAND", best = club, alts = { watch, bruiser } },
        { group = "CHEST", labelKey = "INVTYPE_CHEST", best = tunic, alts = {}, worn = "|Hitem:85::::|h[Old Tunic]|h" },
      },
      set = { picks = { MAINHAND = watch, CHEST = tunic }, list = { watch, tunic }, cost = 9088, left = 5973 - 9088,
        diffs = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.4, ITEM_MOD_AGILITY_SHORT = 6 } },
    }
  end

  local function row(i) return H._view.rows[i] end
  local function panel(key) return H._view.panels and H._view.panels[key] end
  local function run() return GC.AppRuns.Get(prefs.heroList) end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    timers, delays, builds, views, toggled, windowShown = {}, {}, 0, {}, false, true
    selected, tipLink, tipShown, tipOwner, modified, clicked, chat = nil, nil, false, nil, false, nil, nil
    _G.C_Timer = { After = function(s, fn) delays[#delays + 1] = s; timers[#timers + 1] = fn end }
    _G.UnitClass = function() return "Rogue", "ROGUE", 4 end
    _G.UnitLevel = function() return 17 end
    _G.GetMoney = function() return 5973 end
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
    GC.ForeverRoad.Snapshot = function() return road end
    host = CreateFrame("Frame")
    H.Attach(host, { panelLeft = 90, panelRightInset = 14, top = -52, bottom = 14, rowWidth = 640, rowHeight = 32 })
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
    assert.is_nil(H._view.strip)
    assert.is_false(H.IsShown())
    H.Show()
    assert.is_true(H.IsShown())
    assert.equal(1, builds)
    H.Hide()
    assert.is_false(H.IsShown())
  end)

  it("paints one row per slot: the strongest piece, its alternatives, the tags", function()
    H.Show()
    local r1, r2 = row(1), row(2)
    assert.equal("MAIN HAND", textOf(r1.slotName))
    assert.equal("CHEST", textOf(r2.slotName))
    assert.is_nil(row(3))
    -- The strongest piece: its icon in its quality's edge, its name in that colour, what it adds,
    -- its price, and the level it can be worn at, on a tag.
    assert.equal(100000 + CLUB, W.state(r1.best.icon.icon).file)
    assert.equal("Skeletal Club", textOf(r1.best.name))
    local green = GC.Theme.QualityColor(CLUB)
    assert.same({ green.r, green.g, green.b, 1 }, W.state(r1.best.name).color)
    assert.equal("+6.5 Damage Per Second", textOf(r1.best.gain))
    assert.equal("3990c", textOf(r1.best.price))
    assert.equal("AT 19", textOf(r1.best.tags[1].text))
    assert.is_true(shown(r1.best.tags[1]))
    -- The other choices: one line each, the set's pick tagged and chosen for "+ Buy".
    assert.equal("Night Watch Shortsword", textOf(r1.minis[1].name))
    assert.equal("+4 Stamina, +4.4 Damage Per Second", textOf(r1.minis[1].gain))
    assert.equal("IN SET", textOf(r1.minis[1].tags[1].text))
    assert.equal("Bruiser Club", textOf(r1.minis[2].name))
    assert.is_true(shown(r1.minis[2]))
    assert.is_nil(r1.minis[3])
    assert.equal(r1.chosen, result.slots[1].alts[1])
    assert.is_true(shown(r1.minis[1].onRing))
    assert.is_false(shown(r1.best.onRing))
    -- What a piece gives up is red, what it adds green.
    local red, gain = GC.Theme.color.red, GC.Theme.color.green
    assert.equal(GC.Util.Colored(gain, "+6 Agility") .. ", " .. GC.Util.Colored(red, "-4 Stamina"),
      W.state(r2.best.gain).text)
    -- The worn piece's own icon in the slot cell; an empty slot shows the paper doll's art.
    assert.equal(100000 + 85, W.state(r2.worn.icon).file)
    assert.equal("slot:MainHandSlot", W.state(r1.worn.icon).file)
    assert.equal("+ Buy", textOf(r1.add.text))
    -- Fewer slots on the next paint: the spare row goes, pooled.
    result.slots = { result.slots[2] }
    H.RefreshIfShown(true)
    assert.equal("CHEST", textOf(row(1).slotName))
    assert.is_false(shown(row(2)))
  end)

  it("wraps every name, gain and heading instead of cutting it, and sizes buttons and tags to their words", function()
    result.slots[1].best.link = "|Hitem:2130::::|h[A very long name of a club that takes far more than one line]|h"
    H.Show()
    local best = row(1).best
    for _, fs in ipairs({ best.name, best.gain, row(1).slotName, H._view.header.best, H._view.dock.title }) do
      assert.is_true(W.state(fs).wordWrap ~= false)
      assert.equal(0, W.state(fs).maxLines)
      assert.is_true(W.state(fs).nonSpaceWrap)
    end
    assert.is_true(best:GetHeight() > GC.Hero.C.BEST_ICON + 8)
    assert.is_true(row(1):GetHeight() >= best:GetHeight())
    -- A tag and a button are as wide as their words.
    local tag = best.tags[1]
    assert.is_true(tag:GetWidth() >= tag.text:GetUnboundedStringWidth() + 8)
    local add = row(1).add
    assert.is_true(add:GetWidth() >= add.text:GetUnboundedStringWidth())
  end)

  it("marks a piece over the gold carried and still shows it", function()
    result.slots[2].best.overGold = true
    H.Show()
    local best = row(2).best
    assert.is_true(shown(best))
    assert.equal("Dark Leather Tunic", textOf(best.name))
    assert.equal("1589c", textOf(best.price))
    assert.equal("OVER YOUR GOLD", textOf(best.tags[1].text))
    local amber = GC.Theme.tier.SUSPECT
    assert.same({ amber[1], amber[2], amber[3], 1 }, W.state(best.tags[1].text).color)
    assert.equal("IN SET", textOf(best.tags[2].text))
  end)

  it("hovers with the engine's HIGHLIGHT layer, shows the piece's own tooltip, and hands a modified click to the client", function()
    H.Show()
    local mini = row(1).minis[2]
    assert.is_true(W.state(mini).mouse)
    assert.equal("HIGHLIGHT", W.state(mini.hover).layer)
    W.state(mini).scripts.OnEnter(mini)
    assert.equal(result.slots[1].alts[2].link, tipLink)
    assert.equal(mini, tipOwner)
    modified = true
    press(mini)
    assert.equal(result.slots[1].alts[2].link, clicked)
    assert.equal(result.slots[1].alts[1], row(1).chosen)       -- a shift-click links it, picks nothing
    modified = false
    press(mini)
    assert.equal(result.slots[1].alts[2], row(1).chosen)
    assert.is_true(shown(mini.onRing))
    assert.is_false(shown(row(1).minis[1].onRing))
  end)

  it("adds the row's chosen piece and the set to the Upgrades list, caps them, and opens BUY", function()
    H.Show()
    press(row(1).minis[2])                                       -- Bruiser Club for the main hand
    press(row(1).add)
    local list = run()
    assert.equal("Upgrades", list.name)
    assert.equal("game", list.origin)
    assert.equal(1, #list.lines)
    assert.equal(BRUISER, list.lines[1].i)
    assert.equal(1, list.lines[1].q)
    assert.equal(math.floor(2700 * 105 / 100), GC.db.runLineCaps[list.code][BRUISER])
    assert.equal(list.code, selected)
    assert.equal("buy", views[#views])
    -- The set, from the dock: added beside it, the list kept.
    assert.equal("Add 2 to BUY", textOf(H._view.dock.add.text))
    press(H._view.dock.add)
    local ids = {}
    for _, line in ipairs(run().lines) do ids[#ids + 1] = line.i end
    assert.same({ BRUISER, WATCH, TUNIC }, ids)
    assert.equal(math.floor(7499 * 105 / 100), GC.db.runLineCaps[list.code][WATCH])
    assert.equal(math.floor(1589 * 105 / 100), GC.db.runLineCaps[list.code][TUNIC])
    assert.equal(prefs.heroList, list.code)
  end)

  it("adding the same pick twice leaves one line of one", function()
    local watch = result.slots[1].alts[1]
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
    H.AddToBuy({ result.slots[2].best })
    assert.are_not.equal("game-7", prefs.heroList)
    assert.equal("Upgrades", run().name)
    -- One the site made has the same code shape but is not the player's to rewrite: a new one again.
    GC.db.runs.SITE1234 = { code = "SITE1234", origin = "site", lines = {} }
    prefs.heroList = "SITE1234"
    H.AddToBuy({ result.slots[2].best })
    assert.are_not.equal("SITE1234", prefs.heroList)
    assert.same({}, GC.db.runs.SITE1234.lines)
    -- An archived Upgrades list comes back out of the archive as it is used.
    GC.db.runsArchived = { [prefs.heroList] = true }
    H.AddToBuy({ result.slots[1].best })
    assert.is_nil(GC.db.runsArchived[prefs.heroList])
  end)

  it("saves a weight typed in the panel and refuses one that is not a number", function()
    H.Show()
    press(H._view.strip.weights)
    local p = panel("weights")
    assert.is_true(shown(p))
    assert.equal("What counts for a Rogue", textOf(p.title))
    -- One box per stat the class's defaults name, and DPS; the class's main stat and DPS first.
    local order = {}
    for i = 1, #p.rows do if shown(p.rows[i].frame) then order[#order + 1] = p.rows[i].token end end
    assert.same({ "AGI", "DPS", "STR", "STA", "ARMOR", "AP" }, order)
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
    -- Reset: the class's own defaults again, the box no longer red.
    assert.equal("Reset to Rogue", textOf(p.secondary.text))
    press(p.secondary)
    assert.is_nil(prefs.weights.ROGUE)
    assert.is_nil(p.boxes.AGI.bad)
    -- Done, the X and the Weights button shut it.
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
  end)

  it("says what to do when nothing fits the purse, and when the scan is stale", function()
    result.set = { picks = {}, list = {}, cost = 0, left = 5973, diffs = {} }
    result.stale = true
    H.Show()
    local d, s = H._view.dock, H._view.strip
    assert.equal("Nothing on the auction house fits the gold you carry yet.", textOf(d.title))
    assert.is_false(shown(d.add))
    assert.equal("5973c", textOf(d.left))
    assert.equal("Scan again to read each version's own stats.", textOf(s.note))
    assert.equal("Rogue · level 17", textOf(s.name))
    assert.equal("Scan 4m ago", textOf(s.sub))
    assert.equal("Prices from your scan 4m ago. Use and Chance on hit effects are not counted.", textOf(d.note))
    -- The set back: its title, its gains, its cost.
    result = aResult()
    H.RefreshIfShown(true)
    assert.equal("Best buys for the 5973c you carry", textOf(d.title))
    assert.equal("2 upgrades: +6 Agility, +4.4 Damage Per Second", textOf(d.sub))
    assert.equal("9088c", textOf(d.sum))
    assert.is_false(shown(s.note))
  end)

  it("says why there is nothing to show", function()
    local function message() return textOf(H._view.empty.message) end
    result = { slots = {}, loading = 0, noScan = true }
    H.Show()
    assert.equal("No scan with gear in it yet. Open the auction house and let GoldCap scan it.", message())
    result = { slots = {}, loading = 0, noStats = true }
    H.RefreshIfShown(true)
    assert.equal("This client does not report item stats, so GoldCap cannot compare gear.", message())
    result = { slots = {}, loading = 0, noWeights = true }
    H.RefreshIfShown(true)
    assert.equal("No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5", message())
    result = { slots = {}, loading = 3, at = NOW, weights = {}, set = { list = {}, cost = 0, left = 0, diffs = {} } }
    H.RefreshIfShown(true)
    assert.equal("Nothing on the auction house beats what you wear at your level.", message())
    assert.equal("Items still loading: 3. Open this again in a moment.", textOf(H._view.strip.note))
    result = aResult()
    H.RefreshIfShown(true)
    assert.is_false(shown(H._view.empty.frame))
  end)

  it("shows the gold toward a mount: the tile, its panel, a riding cost typed, a line to share", function()
    H.Show()
    local tile = H._view.strip.mount
    assert.equal("MOUNT AT 40", textOf(tile.label))
    assert.equal(tostring(5973 + 4620) .. "c", textOf(tile.value))
    assert.equal("of 20000c", textOf(tile.small))
    assert.equal(math.floor(GC.Hero.C.BAR_W * (5973 + 4620) / 20000 + 0.5),
      math.floor(tile.bar.fill:GetWidth() + 0.5))
    press(tile.hit)
    local p = panel("mount")
    assert.is_true(shown(p))
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
    press(H._view.strip.weights)
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
    assert.equal(1, #timers)
  end)

  -- An id nobody was waiting for must not itself trigger a rebuild, and an id that never resolves
  -- must not keep the tab rebuilding forever.
  it("ignores an item it was not waiting for, and gives up once the loading count stops shrinking", function()
    result = { slots = {}, loading = 1, loadingIds = { [42] = true } }
    builds = 0
    H.Show()
    assert.equal(1, builds)
    H.OnItemInfo(7)                      -- not one of the ids the last build is waiting on
    assert.equal(0, #timers)
    H.OnItemInfo(42)                     -- one it IS waiting on
    assert.equal(1, #timers)
    -- Item 42 never actually resolves: loading stays at 1 every time. Run the storm cap's limit.
    for _ = 1, GC.Hero.C.STALE_LIMIT do
      runTimers()
      H.OnItemInfo(42)
    end
    runTimers()
    H.OnItemInfo(42)
    assert.equal(0, #timers)             -- the storm cap has kicked in: no new timer
    -- Reopening the tab resets the cap.
    H.Show()
    H.OnItemInfo(42)
    assert.equal(1, #timers)
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

  it("lays the strip on one line in a wide tab and the tiles under the name in a narrow one", function()
    H.Show()
    local s = H._view.strip
    local function top(frame) return W.state(frame).points[1][5] end
    assert.equal(top(s.carry.frame), top(s.mount.frame))
    W.state(H._view.container).width = 360
    H.RefreshIfShown(true)
    assert.is_true(-top(s.carry.frame) > 0)                       -- under the name, not beside it
  end)
end)
