local helper = require("spec.spec_helper")

describe("ForeverUpgrades", function()
  local GC, U, items, statsOf, usableOf, speedOf, worn, requested
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
      speed = function(s) return speedOf[s] end,
      requestLoad = function(id) requested[#requested + 1] = id end,
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
  end

  local function gear(t) return { v = 1, at = 5, items = t } end
  local function STR(n) return { ITEM_MOD_STRENGTH_SHORT = n } end
  local function DPS(n) return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = n } end
  local function idsOf(list)
    local out = {}
    for i, c in ipairs(list) do out[i] = c.itemID end
    return out
  end
  local function rogue(over)
    local d = drv(over)
    d.classFile = function() return "ROGUE" end
    return d
  end

  before_each(function()
    GC = helper.loadModule("Core/ForeverGear.lua")
    helper.loadModule("Core/ForeverUpgrades.lua", GC)
    U = GC.ForeverUpgrades
    items, statsOf, usableOf, speedOf, worn, requested = {}, {}, {}, {}, {}, {}
  end)

  -- Owner, 2026-11-06: the cheapest piece that beat the worn one offered "+1 armour" for 1s in every
  -- slot, "while there are much better things" a silver or two dearer.
  it("picks the piece that beats the worn one by the most, per slot", function()
    for _, id in ipairs({ 101, 102, 103 }) do items[id] = { loc = "INVTYPE_HEAD", class = 4, sub = 2 } end
    worn[1] = "item:900"
    statsOf = { ["item:900"] = STR(5), ["item:101"] = STR(4), ["item:102"] = STR(8), ["item:103"] = STR(7) }
    local r = U.Build(gear({ [101] = "100:0:0", [102] = "300:0:0", [103] = "200:0:0" }), drv(), W)
    assert.equal(1, #r.rows)
    local row = r.rows[1]
    assert.equal("HEAD", row.group); assert.equal("INVTYPE_HEAD", row.labelKey)
    assert.equal(102, row.itemID); assert.equal(300, row.unit); assert.equal(3, row.gain)
    assert.equal("[item:102]", row.link)
    assert.same({ ITEM_MOD_STRENGTH_SHORT = 3 }, row.diffs)
    assert.is_nil(row.later); assert.is_nil(row.known); assert.is_nil(row.usable)
  end)

  -- Owner's save, 2026-11-06, rogue weights: "+3 armour" for 6s on the feet and "+2 strength, -2
  -- stamina" for 5s on the chest cleared 5% of a white piece's near-zero score.
  it("wants at least MIN_GAIN_POINTS of the top primary stat, however weak the worn piece", function()
    local R = { AGI = 1, STR = 0.5, STA = 0.4, ARMOR = 0.01 }
    for _, id in ipairs({ 141, 142 }) do items[id] = { loc = "INVTYPE_FEET", class = 4, sub = 2 } end
    items[143] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
    worn[8], worn[5] = "item:940", "item:941"
    statsOf = {
      ["item:940"] = { RESISTANCE0_NAME = 10 },
      ["item:141"] = { RESISTANCE0_NAME = 13 },                                  -- +0.03
      ["item:142"] = { RESISTANCE0_NAME = 10, ITEM_MOD_AGILITY_SHORT = 1 },      -- +1
      ["item:941"] = { RESISTANCE0_NAME = 20, ITEM_MOD_STAMINA_SHORT = 2 },
      ["item:143"] = { RESISTANCE0_NAME = 20, ITEM_MOD_STRENGTH_SHORT = 2 },     -- +0.2
    }
    local r = U.Build(gear({ [141] = "600:0:0", [142] = "900:0:0", [143] = "500:0:0" }), drv(), R)
    assert.equal(1, #r.rows)
    assert.equal(142, r.rows[1].itemID)
  end)

  -- HERO plan (2026-11-13): the strongest piece leads, and a cheaper one nearly as good sits beside
  -- it instead of taking its place (NEAR_BEST used to swap them, so the strongest was never seen).
  it("shows the strongest piece first and cheaper ones nearly as good beside it", function()
    for _, id in ipairs({ 111, 112, 113 }) do items[id] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 } end
    statsOf = { ["item:111"] = STR(20), ["item:112"] = STR(18), ["item:113"] = STR(19) }
    local r = U.Build(gear({ [111] = "5000:0:0", [112] = "120:0:0", [113] = "400:0:0" }), drv(), W)
    assert.equal(1, #r.slots)
    assert.equal(111, r.slots[1].best.itemID)
    assert.same({ 113, 112 }, idsOf(r.slots[1].alts))       -- strongest first: 400 is under 80% of 5000, 120 of 400
  end)

  it("lists cheaper pieces on the price frontier, each at most 80% of the last one's price", function()
    local lots = {}
    for id, pg in pairs({ [1401] = { 100, 10 }, [1402] = { 90, 9.5 }, [1403] = { 60, 8 }, [1404] = { 50, 4 },
        [1405] = { 20, 3 } }) do
      items[id] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
      statsOf["item:" .. id] = STR(pg[2])
      lots[id] = pg[1] .. ":0:0"
    end
    -- By gain: 90 is over 80 (80% of 100), 60 is taken, 50 is over 48 (80% of 60), 20 is taken.
    local r = U.Build(gear(lots), drv(), W)
    assert.equal(1401, r.slots[1].best.itemID)
    assert.same({ 1403, 1405 }, idsOf(r.slots[1].alts))
    -- A frontier piece the tooltip refuses is not shown, and does not hide the ones it was ahead of.
    usableOf["item:1403"] = false
    r = U.Build(gear(lots), drv(), W)
    assert.same({ 1404, 1405 }, idsOf(r.slots[1].alts))
  end)

  it("reads at most FRONTIER_CHECKS tooltips for the cheaper pieces of a slot, none for one over the step", function()
    local lots, asked = { [1450] = "1000:0:0" }, {}
    items[1450] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
    statsOf["item:1450"] = STR(20)
    items[1451] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }      -- 900: over 80% of 1000, never read
    statsOf["item:1451"], lots[1451] = STR(19), "900:0:0"
    for i = 1, 10 do                                               -- ten cheaper ones, each red on the tooltip
      local id = 1460 + i
      items[id] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
      statsOf["item:" .. id] = STR(19 - i)
      lots[id] = (800 - i) .. ":0:0"
      usableOf["item:" .. id] = false
    end
    local d = drv({ usable = function(s) asked[#asked + 1] = s; return usableOf[s] end })
    local r = U.Build(gear(lots), d, W)
    assert.equal(1450, r.slots[1].best.itemID)
    assert.same({}, r.slots[1].alts)
    assert.equal(1 + U.C.FRONTIER_CHECKS, #asked)                  -- the strongest, then eight of the ten
    for _, s in ipairs(asked) do assert.are_not.equal("item:1451", s) end
  end)

  it("passes over the strongest piece when the tooltip says it cannot be used", function()
    for _, id in ipairs({ 121, 122 }) do items[id] = { loc = "INVTYPE_WRIST", class = 4, sub = 2 } end
    statsOf = { ["item:121"] = STR(9), ["item:122"] = STR(4) }
    usableOf = { ["item:121"] = false }
    local r = U.Build(gear({ [121] = "50:0:0", [122] = "80:0:0" }), drv(), W)
    assert.equal(122, r.rows[1].itemID)
  end)

  -- HERO plan, Finding 4 (owner's scan, 2026-11-13): at 0 gold the window showed one line saying
  -- everything costs more, so the strongest piece on the auction house was never seen.
  it("shows the strongest piece even when it costs more than the gold carried, marked", function()
    for _, id in ipairs({ 131, 132 }) do items[id] = { loc = "INVTYPE_HAND", class = 4, sub = 2 } end
    items[133] = { loc = "INVTYPE_WAIST", class = 4, sub = 2 }
    statsOf = { ["item:131"] = STR(10), ["item:132"] = STR(3), ["item:133"] = STR(6) }
    local g = gear({ [131] = "3000:0:0", [132] = "200:0:0", [133] = "900:0:0" })
    local r = U.Build(g, drv({ money = function() return 1000 end }), W)
    assert.equal(2, #r.slots)
    local hands, waist = r.slots[1], r.slots[2]
    assert.equal("HANDS", hands.group)
    assert.equal(131, hands.best.itemID); assert.is_true(hands.best.overGold)   -- 3000c, more than 1000c
    assert.equal(132, hands.alts[1].itemID); assert.is_false(hands.alts[1].overGold)
    assert.equal(133, waist.best.itemID); assert.is_false(waist.best.overGold)  -- 900c fits
    r = U.Build(g, drv({ money = function() return 0 end }), W)
    assert.equal(2, #r.slots)
    assert.is_true(r.slots[1].best.overGold); assert.is_true(r.slots[2].best.overGold)
    assert.equal(0, r.dearer)                               -- the old window's count of hidden slots: none now
    r = U.Build(g, drv(), W)                                -- no money read: nothing is over it
    assert.is_false(r.slots[1].best.overGold)
    usableOf = { ["item:133"] = false }                     -- the waist piece is red on the tooltip
    r = U.Build(g, drv({ money = function() return 0 end }), W)
    assert.equal(1, #r.slots)
  end)

  it("offers a one-hand weapon for the off hand to a class that dual-wields", function()
    items[1300] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }    -- a one-handed sword
    statsOf["item:1300"] = DPS(10)
    local g, w = gear({ [1300] = "40:0:0" }), { STR = 1, DPS = 7 }
    local r = U.Build(g, drv(), w)                                 -- a level-20 warrior dual-wields
    assert.equal(2, #r.slots)
    assert.equal("MAINHAND", r.slots[1].group)
    assert.equal(70, r.slots[1].best.gain)
    assert.equal("OFFHAND", r.slots[2].group); assert.equal("INVTYPE_WEAPONOFFHAND", r.slots[2].labelKey)
    assert.same({ group = "OFFHAND", itemID = 1300, itemString = "item:1300", link = "[item:1300]", unit = 40,
      gain = 35, diffs = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, overGold = false, inSet = false,
      twoHand = false }, r.slots[2].best)                          -- the off hand swings for half
    assert.are_not.equal(r.slots[1].best, r.slots[2].best)         -- one candidate per hand
    local mage = U.Build(g, drv({ classFile = function() return "MAGE" end }), w)
    assert.equal(1, #mage.slots)
    assert.equal("MAINHAND", mage.slots[1].group)
  end)

  it("keeps only daggers for the main hand of a Backstab rogue", function()
    local R = { AGI = 1 }
    items[1500] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }    -- sword
    items[1501] = { loc = "INVTYPE_WEAPON", class = 2, sub = 15 }   -- dagger
    statsOf["item:1500"], statsOf["item:1501"] = { ITEM_MOD_AGILITY_SHORT = 9 }, { ITEM_MOD_AGILITY_SHORT = 5 }
    local g = gear({ [1500] = "50:0:0", [1501] = "40:0:0" })
    local r = U.Build(g, rogue(), R, false, { style = "backstab" })
    assert.equal("MAINHAND", r.slots[1].group)
    assert.equal(1501, r.slots[1].best.itemID)
    assert.same({}, r.slots[1].alts)                              -- the sword is not offered for it
    assert.equal("OFFHAND", r.slots[2].group)
    assert.equal(1500, r.slots[2].best.itemID)                     -- the off hand takes any
    assert.equal(1500, U.Build(g, rogue(), R, false, { style = "sinister" }).slots[1].best.itemID)
    assert.equal(1500, U.Build(g, rogue(), R).slots[1].best.itemID)   -- no style: no filter
  end)

  it("picks a slower sword over a faster one with the same DPS for Sinister Strike", function()
    local R = { AGI = 1, DPS = 7 }
    items[1600] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }
    items[1601] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }
    statsOf["item:1600"], statsOf["item:1601"] = DPS(10), DPS(10)
    speedOf = { ["item:1600"] = 1.8, ["item:1601"] = 2.7 }
    local g = gear({ [1600] = "50:0:0", [1601] = "50:0:0" })
    local r = U.Build(g, rogue(), R, false, { style = "sinister" })
    assert.equal(1601, r.slots[1].best.itemID)
    assert.near(70 * U.DpsFactor("ROGUE", "MAINHAND", 2.7), r.slots[1].best.gain, 1e-9)
    -- A warrior has no ability timer: the same gain, and the tie goes to the lower item string.
    assert.equal(1600, U.Build(g, drv(), { STR = 1, DPS = 7 }).slots[1].best.itemID)
    -- The worn sword is weighed by its own speed too: 9 DPS at 2.7 beats 10 at 1.8.
    worn[16] = "item:1690"
    statsOf["item:1690"], speedOf["item:1690"] = DPS(9), 2.7
    r = U.Build(g, rogue(), R, false, { style = "sinister" })
    assert.equal(1, #r.slots)
    assert.equal(1601, r.slots[1].best.itemID)
    assert.same({}, r.slots[1].alts)
    assert.equal("item:1690", r.slots[1].worn)
  end)

  it("reads a weapon's speed only for a rogue's main hand, once its stats answered, never on the count path", function()
    local R = { AGI = 1, DPS = 7 }
    items[1700] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }           -- either hand
    items[1701] = { loc = "INVTYPE_RANGEDRIGHT", class = 2, sub = 3 }      -- a gun
    items[1702] = { loc = "INVTYPE_HAND", class = 4, sub = 2 }
    items[1703] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }   -- its stats not answered yet
    worn[16] = "item:1790"
    statsOf = { ["item:1700"] = DPS(10), ["item:1701"] = DPS(10), ["item:1702"] = { ITEM_MOD_AGILITY_SHORT = 3 },
      ["item:1790"] = DPS(5) }
    local asked = {}
    local function speed(s) asked[#asked + 1] = s; return 2.6 end
    local g = gear({ [1700] = "10:0:0", [1701] = "10:0:0", [1702] = "10:0:0", [1703] = "10:0:0" })
    U.Build(g, rogue({ speed = speed }), R)
    table.sort(asked)
    assert.same({ "item:1700", "item:1790" }, asked)               -- the main-hand candidate and the worn one
    asked = {}
    local r = U.Build(g, rogue({ speed = speed, usable = function() error("a tooltip read on the count path") end }),
      R, true)
    assert.same({}, asked)
    assert.equal(4, #r.slots)                                     -- main hand, off hand, gloves, ranged
    U.Build(g, drv({ speed = speed }), { STR = 1, DPS = 7 })      -- a warrior
    assert.same({}, asked)
    U.Build(g, rogue({ speed = speed }), { AGI = 1 })              -- weights that do not count DPS
    assert.same({}, asked)
  end)

  -- HERO plan, Review Focus 2: the client's item cache answers part of the lots, and two builds over
  -- the same answers must show the same thing (the 0.28.1 rows came and went every half second).
  it("gives the same slots twice over the same answers", function()
    items[1800] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
    items[1801] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
    items[1802] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }
    items[1803] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }
    items[1804] = { loc = "INVTYPE_FEET", class = 4, sub = 2, loading = true }
    for _, id in ipairs({ 1805, 1806, 1807 }) do items[id] = { loc = "INVTYPE_HEAD", class = 4, sub = 2 } end
    statsOf = { ["item:1800:0:0:0:0:0:-5:3"] = STR(8), ["item:1800:0:0:0:0:0:-6:3"] = STR(8), ["item:1801"] = STR(8),
      ["item:1802"] = STR(6), ["item:1803"] = STR(6), ["item:1805"] = STR(9), ["item:1806"] = STR(4),
      ["item:1807"] = STR(4) }
    local entries = { { 1800, "100:-5:3 100:-6:3" }, { 1801, "100:0:0" }, { 1802, "60:0:0" }, { 1803, "60:0:0" },
      { 1804, "5:0:0" }, { 1805, "500:0:0" }, { 1806, "90:0:0" }, { 1807, "90:0:0" } }
    local function gearOf(list)
      local t = {}
      for _, e in ipairs(list) do t[e[1]] = e[2] end
      return gear(t)
    end
    local d = drv({ money = function() return 150 end })
    local a = U.Build(gearOf(entries), d, W)
    assert.same(a, U.Build(gearOf(entries), d, W))
    local reversed = {}
    for i = #entries, 1, -1 do reversed[#reversed + 1] = entries[i] end
    assert.same(a, U.Build(gearOf(reversed), d, W))
    -- Ties go to the lower price, then the lower item string.
    assert.equal("item:1805", a.slots[1].best.itemString)
    assert.equal(1, #a.slots[1].alts)
    assert.equal("item:1806", a.slots[1].alts[1].itemString)
    assert.equal("item:1800:0:0:0:0:0:-5:3", a.slots[2].best.itemString)
    assert.equal(1, a.loading)
  end)

  it("offers a stronger piece a level or two ahead beside the strongest one usable now", function()
    items[600] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 22 }
    items[602] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 18 }
    items[603] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 21 }   -- ahead, but weaker than 602
    statsOf = { ["item:600"] = STR(5), ["item:602"] = STR(2), ["item:603"] = { ITEM_MOD_STRENGTH_SHORT = 1.5 } }
    local r = U.Build(gear({ [600] = "10:0:0", [602] = "999:0:0", [603] = "1:0:0" }), drv(), W)
    assert.equal(602, r.slots[1].best.itemID)
    assert.same({ 600 }, idsOf(r.slots[1].alts))
    assert.equal(22, r.slots[1].alts[1].later)
    r = U.Build(gear({ [600] = "10:0:0", [603] = "1:0:0" }), drv(), W)   -- nothing usable now: the ahead one leads
    assert.equal(600, r.slots[1].best.itemID)
    assert.same({}, r.slots[1].alts)
  end)

  it("says a scan saved before suffix versions is stale", function()
    items[101] = { loc = "INVTYPE_HEAD", class = 4, sub = 2 }
    statsOf["item:101"] = STR(3)
    assert.is_true(U.Build({ v = 1, at = 5, items = { [101] = "10:0:0" } }, drv(), W).stale)
    assert.is_nil(U.Build({ v = 2, at = 5, items = { [101] = "10:0:0" } }, drv(), W).stale)
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

  -- HERO plan, Finding 3 (2026-11-13): in Classic a point of weapon DPS is worth 14 attack power,
  -- the off hand swings for half, and a melee class's ranged weapon is worth about a seventh.
  it("weighs off-hand DPS at half and a rogue's gun at a seventh", function()
    local w = { DPS = 7 }
    local dps = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }
    assert.equal(35, U.Score(dps, w, U.DpsFactor("ROGUE", "OFFHAND")))
    assert.equal(10, U.Score(dps, w, U.DpsFactor("ROGUE", "RANGED")))
    assert.equal(70, U.Score(dps, w, U.DpsFactor("ROGUE", "MAINHAND")))
    assert.equal(70, U.Score(dps, w, U.DpsFactor("HUNTER", "RANGED")))   -- a class not listed: as before
    assert.equal(70, U.Score(dps, w))                                    -- no factor: 1
    -- Only DPS's share is scaled, and the parts stay the piece's own numbers.
    local score, parts = U.Score({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 2 },
      { DPS = 7, STR = 1 }, 0.5)
    assert.equal(37, score)
    assert.same({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 2 }, parts)
  end)

  it("prefers a slower main hand for Sinister Strike", function()
    local ref = 1 + 2 / 4.5
    assert.near((1 + 2.6 / 4.5) / ref, U.DpsFactor("ROGUE", "MAINHAND", 2.6), 1e-9)
    assert.near((1 + 1.8 / 4.5) / ref, U.DpsFactor("ROGUE", "MAINHAND", 1.8), 1e-9)
    assert.equal(1, U.DpsFactor("ROGUE", "MAINHAND", nil))
    assert.equal(0.5, U.DpsFactor("ROGUE", "OFFHAND", 2.6))        -- Sinister Strike swings the main hand
    assert.equal(1, U.DpsFactor("WARRIOR", "MAINHAND", 3.8))       -- no ability timer: speed changes nothing
  end)

  it("reads the rogue's style from the worn main hand unless the player chose one", function()
    assert.equal("backstab", U.StyleFor({}, "ROGUE", 15))
    assert.equal("sinister", U.StyleFor({}, "ROGUE", 7))
    assert.equal("sinister", U.StyleFor(nil, "ROGUE", nil))         -- nothing worn, no prefs yet
    assert.equal("sinister", U.StyleFor({ heroStyle = "sinister" }, "ROGUE", 15))
    assert.equal("backstab", U.StyleFor({ heroStyle = "backstab" }, "ROGUE", 7))
    assert.equal("backstab", U.StyleFor({ heroStyle = "bogus" }, "ROGUE", 15))   -- not a style: the weapon says
    assert.is_nil(U.StyleFor({ heroStyle = "backstab" }, "WARRIOR", 15))
  end)

  it("values a melee main hand's DPS at 14 attack power", function()
    for _, class in ipairs({ "ROGUE", "WARRIOR", "PALADIN" }) do
      local d = U.DEFAULT_WEIGHTS[class]
      assert.equal(14 * d.AP, d.DPS)
    end
    assert.equal(2, U.DEFAULT_WEIGHTS.HUNTER.DPS)                   -- nothing measured says otherwise for it
    assert.equal(0.5, U.DEFAULT_WEIGHTS.MAGE.DPS)
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
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT", "GetMoney" }

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
    _G.C_TooltipInfo, _G.GetItemStats, _G.GetMoney = nil, nil, nil
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

  it("counts slots after a scan, through the client's own reads", function()
    init(16001)
    GC.ForeverUpgrades.PrintCount()
    assert.same({ "Upgrades for your gear on the auction house: 1. Type /gc upgrades to see them." }, printed)
    local r = GC.ForeverUpgrades.Current()
    assert.equal("|Hitem:101|h[Cap]|h", r.rows[1].link)
    assert.equal("|Hitem:101|h[Cap]|h", r.slots[1].best.link)
    assert.equal(5000, r.at)
    assert.is_true(r.stale)                                   -- a v1 save: no suffix versions in it
    -- A slot whose strongest piece costs more than the gold carried still counts (HERO plan, Finding 4).
    _G.GetMoney = function() return 0 end
    GC.ForeverUpgrades.PrintCount()
    assert.equal(2, #printed)
    assert.equal(printed[1], printed[2])
    assert.is_true(GC.ForeverUpgrades.Current().slots[1].best.overGold)
  end)

  it("with a session record: the same count is not said twice, a changed one is", function()
    init(16001)
    local said = {}
    GC.ForeverUpgrades.PrintCount(nil, said)
    GC.ForeverUpgrades.PrintCount(nil, said)
    assert.equal(1, #printed)
    GC.ForeverUpgrades.PrintCount({ slots = { {}, {} } }, said)
    assert.equal(2, #printed)
    GC.ForeverUpgrades.PrintCount()
    assert.equal(3, #printed) -- a direct call always says it
  end)

  it("says nothing when nothing beats the worn piece, and reports a client with no stats call", function()
    init(16001)
    _G.GetInventoryItemLink = function(_, slot) return slot == 1 and "item:101" or nil end
    GC.ForeverUpgrades.PrintCount()
    assert.same({}, printed)
    _G.C_Item.GetItemStats = nil
    assert.is_true(GC.ForeverUpgrades.Current().noStats)
  end)

  -- The owner's window, 2026-11-13 (recorded): ~1170 lots asked about on every repaint, a client
  -- cache that held about half of them, and the two halves swapping places on each repaint -- the
  -- rows came and went every half second. Here the client holds one piece: the last one asked for.
  it("keeps what the client said about a piece, so one its cache drops later stays on the window", function()
    init(16001)
    INFO[102] = { loc = "INVTYPE_HAND", class = 4, sub = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 6 } }
    finally(function() INFO[102] = nil end)
    db.foreverScan.gear.items[102] = "300:0:0"
    local function idOf(s) return tonumber(tostring(s):match("item:(%d+)")) end
    local held, asked = {}, {}
    local info, stats = _G.C_Item.GetItemInfo, _G.C_Item.GetItemStats
    _G.C_Item.GetItemInfo = function(s)
      if held[idOf(s)] then return info(s) end
      asked[#asked + 1] = idOf(s)
    end
    _G.C_Item.GetItemStats = function(s)
      if held[idOf(s)] then return stats(s) end
      asked[#asked + 1] = idOf(s)
    end
    local counts = {}
    for i = 1, 4 do
      counts[i] = #GC.ForeverUpgrades.Current().rows
      held = {}
      if #asked > 0 then held[asked[#asked]] = true end
      asked = {}
    end
    assert.same({ 0, 1, 2, 2 }, counts)
  end)

  -- The tooltip read is the priciest call here, and its answer only changes with the character's
  -- level (or a skill trained, which a level-up or a /reload then picks up): kept per piece and level.
  it("asks the tooltip about a piece once per level, and again when it could not tell", function()
    init(16001)
    local level, reads, colour = 20, 0, { r = 1, g = 1, b = 1 }
    _G.UnitLevel = function() return level end
    _G.C_TooltipInfo = { GetHyperlink = function()
      reads = reads + 1
      return { lines = { { leftText = "Cap", leftColor = colour } } }
    end }
    assert.equal(1, #GC.ForeverUpgrades.Current().slots)
    GC.ForeverUpgrades.Current()
    assert.equal(1, reads)
    level = 21
    GC.ForeverUpgrades.Current()
    assert.equal(2, reads)
    level, colour = 22, nil                                    -- no colours: the tooltip cannot tell
    GC.ForeverUpgrades.Current()
    GC.ForeverUpgrades.Current()
    assert.equal(4, reads)
  end)

  it("shows a rogue with a dagger in hand only daggers for the main hand, unless it chose otherwise", function()
    init(16001)
    INFO[150] = { loc = "INVTYPE_WEAPON", class = 2, sub = 15, stats = { ITEM_MOD_AGILITY_SHORT = 1 } }
    INFO[151] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7, stats = { ITEM_MOD_AGILITY_SHORT = 9 } }
    INFO[152] = { loc = "INVTYPE_WEAPON", class = 2, sub = 15, stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
    finally(function() INFO[150], INFO[151], INFO[152] = nil, nil, nil end)
    db.foreverScan.gear.items = { [151] = "300:0:0", [152] = "200:0:0" }
    _G.UnitClass = function() return "Rogue", "ROGUE", 4 end
    _G.GetInventoryItemLink = function(_, slot) return slot == 16 and "item:150" or nil end
    local r = GC.ForeverUpgrades.Current()
    assert.equal("backstab", r.style)
    assert.equal("MAINHAND", r.slots[1].group)
    assert.equal(152, r.slots[1].best.itemID)
    assert.equal(151, r.slots[2].best.itemID)                  -- the off hand takes the sword
    GC.ForeverScan.Prefs().heroStyle = "sinister"
    r = GC.ForeverUpgrades.Current()
    assert.equal("sinister", r.style)
    assert.equal(151, r.slots[1].best.itemID)
  end)

  it("says there is no scan when the saved gear lots are not this fold's", function()
    init(16001)
    db.foreverScan.gear.at = 4000
    assert.is_true(GC.ForeverUpgrades.Current().noScan)
  end)

  it("shows, changes and resets the class's stat weights with /gc weights", function()
    init(16001)
    GC.ForeverUpgrades.SlashWeights("")
    assert.equal("Stat weights: Strength 1, AGI 0.5, Stamina 0.5, ARMOR 0.01, DPS 7, AP 0.5", printed[1])
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
