local helper = require("spec.spec_helper")

describe("ForeverUpgrades", function()
  local GC, U, items, statsOf, usableOf, worn, requested
  local W = { STR = 1, STA = 0.5 }

  local function drv(over)
    local d = {
      level = function() return 20 end,
      classFile = function() return "WARRIOR" end,
      equipped = function(slot) return worn[slot] end,
      instant = function(id)
        local it = items[id]
        if it then return it.loc, it.class, it.sub end
      end,
      info = function(str)
        local it = items[tonumber(str:match("item:(%d+)"))]
        if it and not it.loading then return it.minLevel or 1, "[" .. str .. "]" end
      end,
      stats = function(s) return statsOf[s] end,
      usable = function(s) return usableOf[s] end,
      requestLoad = function(id) requested[#requested + 1] = id end,
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
  end

  local function gear(t) return { v = 1, at = 5, items = t } end
  local function STR(n) return { ITEM_MOD_STRENGTH_SHORT = n } end

  before_each(function()
    GC = helper.loadModule("Core/ForeverGear.lua")
    helper.loadModule("Core/ForeverUpgrades.lua", GC)
    U = GC.ForeverUpgrades
    items, statsOf, usableOf, worn, requested = {}, {}, {}, {}, {}
  end)

  it("picks the cheapest piece that beats the worn one, per slot", function()
    for _, id in ipairs({ 101, 102, 103 }) do items[id] = { loc = "INVTYPE_HEAD", class = 4, sub = 2 } end
    worn[1] = "item:900"
    statsOf = { ["item:900"] = STR(5), ["item:101"] = STR(4), ["item:102"] = STR(8), ["item:103"] = STR(7) }
    local r = U.Build(gear({ [101] = "100:0:0", [102] = "300:0:0", [103] = "200:0:0" }), drv(), W)
    assert.equal(1, #r.rows)
    local row = r.rows[1]
    assert.equal("HEAD", row.group); assert.equal("INVTYPE_HEAD", row.labelKey)
    assert.equal(103, row.itemID); assert.equal(200, row.unit); assert.equal(2, row.gain)
    assert.equal("[item:103]", row.link)
    assert.same({ ITEM_MOD_STRENGTH_SHORT = 2 }, row.diffs)
    assert.is_nil(row.later)
  end)

  it("scores each version of a random-suffix item by its own stats", function()
    items[200] = { loc = "INVTYPE_CLOAK", class = 4, sub = 1 }
    statsOf = { ["item:200:0:0:0:0:0:-12:3"] = { ITEM_MOD_INTELLECT_SHORT = 6 },   -- of the Owl: nothing for W
                ["item:200:0:0:0:0:0:-9:3"] = STR(4) }                              -- of the Bear
    local r = U.Build(gear({ [200] = "50:-12:3 90:-9:3" }), drv(), W)
    assert.equal(1, #r.rows)
    assert.equal(90, r.rows[1].unit)
    assert.equal("item:200:0:0:0:0:0:-9:3", r.rows[1].itemString)
  end)

  it("never scores a piece the client has not answered for, and asks for it once", function()
    items[300] = { loc = "INVTYPE_FEET", class = 4, sub = 1, loading = true }   -- no level yet
    items[301] = { loc = "INVTYPE_FEET", class = 4, sub = 1 }                   -- no stats yet
    local r = U.Build(gear({ [300] = "10:0:0", [301] = "20:0:0" }), drv(), W)
    assert.equal(0, #r.rows)
    assert.equal(2, r.loading)
    table.sort(requested)
    assert.same({ 300, 301 }, requested)
    -- M1 (final review): the exact ids still loading, for the window to filter arrivals against.
    assert.same({ [300] = true, [301] = true }, r.loadingIds)
  end)

  it("keeps out what the class cannot use: its armour rules, and a red line on the tooltip", function()
    items[400] = { loc = "INVTYPE_CHEST", class = 4, sub = 4 }        -- plate at 20: not before 40
    items[401] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }     -- two-handed sword
    items[402] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 1 }     -- two-handed axe
    statsOf = { ["item:400"] = STR(20), ["item:401"] = STR(10), ["item:402"] = STR(9) }
    usableOf = { ["item:401"] = false }                               -- the skill is not trained: red
    local r = U.Build(gear({ [400] = "10:0:0", [401] = "20:0:0", [402] = "30:0:0" }), drv(), W)
    assert.equal(1, #r.rows)
    assert.equal("MAINHAND", r.rows[1].group)
    assert.equal(402, r.rows[1].itemID)
    items[500] = { loc = "INVTYPE_LEGS", class = 4, sub = 2 }           -- leather
    statsOf["item:500"] = STR(3)
    assert.equal(0, #U.Build(gear({ [500] = "5:0:0" }), drv({ classFile = function() return "MAGE" end }), W).rows)
  end)

  it("offers a piece one or two levels ahead only when nothing usable now qualifies", function()
    items[600] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 22 }
    items[601] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 23 }   -- three ahead: never
    statsOf = { ["item:600"] = STR(5), ["item:601"] = STR(9) }
    local r = U.Build(gear({ [600] = "10:0:0", [601] = "5:0:0" }), drv(), W)
    assert.equal(600, r.rows[1].itemID)
    assert.equal(22, r.rows[1].later)
    items[602] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 18 }
    statsOf["item:602"] = STR(2)
    r = U.Build(gear({ [600] = "10:0:0", [602] = "999:0:0" }), drv(), W)
    assert.equal(602, r.rows[1].itemID)                    -- usable now wins, even dearer
    assert.is_nil(r.rows[1].later)
  end)

  -- Final review M4: a level-ahead pick used to trust only the class table, so a class the table
  -- does not know could never get one -- even when the tooltip itself says yes.
  it("runs the tooltip usability check for a level-ahead pick too, not just the class table", function()
    items[1200] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 22 }   -- TINKER: not in ARMOR
    statsOf["item:1200"] = STR(5)
    local tinker = drv({ classFile = function() return "TINKER" end })
    assert.equal(0, #U.Build(gear({ [1200] = "10:0:0" }), tinker, W).rows)
    usableOf["item:1200"] = true
    local r = U.Build(gear({ [1200] = "10:0:0" }), tinker, W)
    assert.equal(1, #r.rows)
    assert.equal(1200, r.rows[1].itemID)
    assert.equal(22, r.rows[1].later)
  end)

  it("compares a two-hander with main and off hand together, and skips the off hand under a two-hander", function()
    items[910] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }
    items[911] = { loc = "INVTYPE_SHIELD", class = 4, sub = 6 }
    worn[16], worn[17] = "item:910", "item:911"
    statsOf = { ["item:910"] = STR(6), ["item:911"] = { ITEM_MOD_STAMINA_SHORT = 8 } }   -- 6 + 4 = 10
    items[700] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }
    items[701] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }
    statsOf["item:700"], statsOf["item:701"] = STR(9), STR(12)
    local r = U.Build(gear({ [700] = "10:0:0", [701] = "80:0:0" }), drv(), W)
    assert.equal(1, #r.rows)
    assert.equal(701, r.rows[1].itemID)
    assert.equal(2, r.rows[1].gain)
    items[920] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }
    worn[16], worn[17] = "item:920", nil
    statsOf["item:920"] = STR(12)
    items[702] = { loc = "INVTYPE_SHIELD", class = 4, sub = 6 }
    statsOf["item:702"] = { ITEM_MOD_STAMINA_SHORT = 20 }
    assert.equal(0, #U.Build(gear({ [702] = "1:0:0" }), drv(), W).rows)
  end)

  -- Final review I1: a class that can equip a dagger (per the WEAPON table) is not necessarily
  -- allowed to WEAR ONE IN THE OFF HAND -- that is a separate dual-wield restriction the tooltip
  -- does not redline, so ClassAllows alone offered it.
  it("offers an off-hand weapon only to a class and level that can dual-wield", function()
    items[1100] = { loc = "INVTYPE_WEAPONOFFHAND", class = 2, sub = 15 }   -- dagger
    statsOf["item:1100"] = STR(5)
    -- The default driver: a level-20 warrior -- dual-wields from level 20.
    assert.equal(1, #U.Build(gear({ [1100] = "10:0:0" }), drv(), W).rows)
    -- A level-19 warrior cannot yet.
    assert.equal(0, #U.Build(gear({ [1100] = "10:0:0" }), drv({ level = function() return 19 end }), W).rows)
    -- A rogue always can, at any level.
    assert.equal(1, #U.Build(gear({ [1100] = "10:0:0" }),
      drv({ classFile = function() return "ROGUE" end, level = function() return 1 end }), W).rows)
    -- A mage can equip a dagger (ClassAllows says yes) but can never dual-wield one.
    assert.equal(0, #U.Build(gear({ [1100] = "10:0:0" }),
      drv({ classFile = function() return "MAGE" end, level = function() return 60 end }), W).rows)
  end)

  it("trusts the client's own CanDualWield over the Classic fallback when it answers", function()
    items[1101] = { loc = "INVTYPE_WEAPONOFFHAND", class = 2, sub = 15 }
    statsOf["item:1101"] = STR(5)
    -- A rogue would fall back to true, but the client says no.
    assert.equal(0, #U.Build(gear({ [1101] = "10:0:0" }),
      drv({ classFile = function() return "ROGUE" end, canDualWield = function() return false end }), W).rows)
    -- A class the Classic fallback table does not list, but the client says yes.
    assert.equal(1, #U.Build(gear({ [1101] = "10:0:0" }),
      drv({ classFile = function() return "SHAMAN" end, canDualWield = function() return true end }), W).rows)
  end)

  it("measures a ring against the weaker of the two worn", function()
    items[800] = { loc = "INVTYPE_FINGER", class = 4, sub = 0 }
    items[801] = { loc = "INVTYPE_FINGER", class = 4, sub = 0 }
    items[802] = { loc = "INVTYPE_FINGER", class = 4, sub = 0 }
    worn[11], worn[12] = "item:801", "item:802"
    statsOf = { ["item:801"] = STR(3), ["item:802"] = STR(6), ["item:800"] = STR(4) }
    local r = U.Build(gear({ [800] = "7:0:0" }), drv(), W)
    assert.equal(800, r.rows[1].itemID)
    assert.equal(1, r.rows[1].gain)
  end)

  it("shows a class it has no rules for only what the tooltip says it can use", function()
    items[1000] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
    statsOf["item:1000"] = STR(3)
    local tinker = drv({ classFile = function() return "TINKER" end })
    assert.equal(0, #U.Build(gear({ [1000] = "1:0:0" }), tinker, W).rows)
    usableOf["item:1000"] = true
    assert.equal(1, #U.Build(gear({ [1000] = "1:0:0" }), tinker, W).rows)
  end)

  it("says what it lacks instead of guessing", function()
    assert.is_true(U.Build(gear({}), drv(), {}).noWeights)
    assert.is_true(U.Build(nil, drv(), W).noScan)
  end)

  it("scores, diffs and words stats with the client's own names", function()
    local was = { _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT, _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT }
    _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT = "Strength", "Stamina"
    _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = nil
    local score, parts = U.Score({ ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 2, ITEM_MOD_SPIRIT_SHORT = 9 }, W)
    assert.equal(5, score)
    assert.same({ ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 2 }, parts)   -- spirit weighs nothing here
    local diffs = U.Diff({ ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5.5 },
      { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4 })
    assert.same({ ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = -1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1.5 }, diffs)
    assert.equal("+3 Strength, -1 Stamina, +1.5 DPS", U.DiffText(diffs))   -- no client name: the token
    _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT, _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = was[1], was[2], was[3]
  end)

  it("reads a red tooltip line as unusable, and cannot tell without colours or a client", function()
    local function api(lines) return { GetHyperlink = function() return { lines = lines } end } end
    local white, red = { r = 1, g = 1, b = 1 }, { r = 1, g = 0.125, b = 0.125 }
    assert.is_false(U.TooltipUsable("item:1", api({ { leftText = "Chest", leftColor = white, rightText = "Plate", rightColor = red } })))
    assert.is_true(U.TooltipUsable("item:1", api({ { leftText = "Chest", leftColor = white } })))
    assert.is_nil(U.TooltipUsable("item:1", api({ { leftText = "Chest" } })))
    assert.is_nil(U.TooltipUsable("item:1", api({})))
    assert.is_nil(U.TooltipUsable("item:1", {}))
    assert.is_nil(U.TooltipUsable("item:1", { GetHyperlink = function() error("not loaded") end }))
  end)

  it("knows Classic's armour and weapon rules, and says nothing for a class it does not know", function()
    assert.is_false(U.ClassAllows("WARRIOR", 4, 4, 39))
    assert.is_true(U.ClassAllows("WARRIOR", 4, 4, 40))
    assert.is_true(U.ClassAllows("HUNTER", 4, 3, 40))
    assert.is_false(U.ClassAllows("ROGUE", 4, 3, 60))
    assert.is_true(U.ClassAllows("MAGE", 2, 19, 5))          -- wand
    assert.is_false(U.ClassAllows("PRIEST", 2, 7, 5))        -- one-handed sword
    assert.is_false(U.ClassAllows("WARRIOR", 15, 0, 20))     -- neither armour nor weapon
    assert.is_nil(U.ClassAllows("TINKER", 4, 2, 20))
  end)
end)

describe("ForeverUpgrades in the client", function()
  local GC, db, printed, saved
  local INFO = { [101] = { loc = "INVTYPE_HEAD", class = 4, sub = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 8 } } }
  local KEYS = { "C_Item", "UnitLevel", "UnitClass", "GetInventoryItemLink", "C_TooltipInfo", "GetItemStats",
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT" }

  local function init(interface)
    GC.ForeverScan.Init(db, { passport = function() return { interface = interface, region = 90, realm = "Forever" } end })
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    local function idOf(s) return tonumber(tostring(s):match("item:(%d+)")) end
    _G.C_Item = {
      GetItemInfoInstant = function(id)
        local it = INFO[id]
        if it then return id, "Armor", "Leather", it.loc, 0, it.class, it.sub end
      end,
      GetItemInfo = function(s) if INFO[idOf(s)] then return "Cap", "|Hitem:" .. idOf(s) .. "|h[Cap]|h", 2, 20, 18 end end,
      GetItemStats = function(s) return INFO[idOf(s)] and INFO[idOf(s)].stats or nil end,
      RequestLoadItemDataByID = function() end,
    }
    _G.UnitLevel = function() return 20 end
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    _G.GetInventoryItemLink = function() return nil end
    _G.C_TooltipInfo, _G.GetItemStats = nil, nil
    _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT = "Strength", "Stamina"
    GC = helper.loadModule("Core/Util.lua")
    for _, f in ipairs({ "Core/Game.lua", "Core/ForeverFold.lua", "Core/ForeverGear.lua", "Core/ForeverScan.lua",
        "Core/ForeverUpgrades.lua" }) do
      helper.loadModule(f, GC)
    end
    printed = {}
    GC.Print = function(m) printed[#printed + 1] = m end
    db = { foreverScan = { fold = { region = 90, realm = "Forever", at = 5000, items = {} },
      gear = { v = 1, at = 5000, items = { [101] = "250:0:0" } } } }
  end)

  after_each(function() for _, k in ipairs(KEYS) do _G[k] = saved[k] end end)

  it("counts the upgrades after a scan through the client's own reads", function()
    init(16001)
    GC.ForeverUpgrades.PrintCount()
    assert.same({ "Upgrades for your gear on the auction house: 1. Type /gc upgrades to see them." }, printed)
    local r = GC.ForeverUpgrades.Current()
    assert.equal("|Hitem:101|h[Cap]|h", r.rows[1].link)
    assert.equal(5000, r.at)
  end)

  it("says nothing when nothing beats the worn piece, and reports a client with no stats call", function()
    init(16001)
    _G.GetInventoryItemLink = function(_, slot) return slot == 1 and "item:101" or nil end
    GC.ForeverUpgrades.PrintCount()
    assert.same({}, printed)
    _G.C_Item.GetItemStats = nil
    assert.is_true(GC.ForeverUpgrades.Current().noStats)
  end)

  it("says there is no scan when the saved gear lots are not this fold's", function()
    init(16001)
    db.foreverScan.gear.at = 4000
    assert.is_true(GC.ForeverUpgrades.Current().noScan)
  end)

  it("shows, changes and resets the class's stat weights with /gc weights", function()
    init(16001)
    GC.ForeverUpgrades.SlashWeights("")
    assert.equal("Stat weights: Strength 1, AGI 0.5, Stamina 0.5, ARMOR 0.01, DPS 2, AP 0.5", printed[1])
    GC.ForeverUpgrades.SlashWeights("str 2 dps 0")
    assert.same({ STR = 2, AGI = 0.5, STA = 0.5, AP = 0.5, ARMOR = 0.01 }, db.forever.weights.WARRIOR)
    assert.equal("Stat weights: Strength 2, AGI 0.5, Stamina 0.5, ARMOR 0.01, AP 0.5", printed[2])
    GC.ForeverUpgrades.SlashWeights("LUCK 3")
    assert.equal("Unknown stat LUCK. Use one of: STR, AGI, STA, INT, SPI, ARMOR, DPS, AP, SP", printed[3])
    GC.ForeverUpgrades.SlashWeights("STR lots")
    assert.equal("Unknown stat STR lots. Use one of: STR, AGI, STA, INT, SPI, ARMOR, DPS, AP, SP", printed[4])
    assert.equal(2, db.forever.weights.WARRIOR.STR)          -- a refused line changes nothing
    GC.ForeverUpgrades.SlashWeights("reset")
    assert.is_nil(db.forever.weights.WARRIOR)
    assert.equal(printed[1], printed[5])
  end)

  -- V3: a valid token with nothing after it at all ("/gc weights STR") is a different mistake
  -- than a genuinely unrecognized word -- calling STR "unknown" while listing it as a valid
  -- option one comma later is self-contradictory. "STR lots" (a trailing word that is not a
  -- number either) keeps the old message; only the lone-token case changes.
  it("tells a valid stat typed with no number apart from a genuinely unknown one", function()
    init(16001)
    GC.ForeverUpgrades.SlashWeights("STR")
    assert.equal("STR needs a number, for example /gc weights STR 1.5", printed[#printed])
    GC.ForeverUpgrades.SlashWeights("STR lots")
    assert.equal("Unknown stat STR lots. Use one of: STR, AGI, STA, INT, SPI, ARMOR, DPS, AP, SP",
      printed[#printed])
  end)

  it("asks for weights for a class it has none for", function()
    init(16001)
    _G.UnitClass = function() return "Tinker", "TINKER", 13 end
    GC.ForeverUpgrades.SlashWeights("")
    assert.equal("No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5", printed[1])
    assert.is_true(GC.ForeverUpgrades.Current().noWeights)
  end)

  it("does nothing on retail", function()
    init(120100)
    GC.ForeverUpgrades.PrintCount()
    GC.ForeverUpgrades.SlashWeights("STR 2")
    assert.is_nil(GC.ForeverUpgrades.Current())
    assert.same({}, printed)
    assert.is_nil(db.forever)
  end)
end)
