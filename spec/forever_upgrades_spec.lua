local helper = require("spec.spec_helper")

describe("ForeverUpgrades", function()
  local GC, U, items, statsOf, usableOf, speedOf, worn, requested, speedReads
  local W = { STR = 1, STA = 0.5 }

  local function drv(over)
    -- Speeds as the client's driver keeps them: per itemID, what it already knows on a lookup
    -- (read false), and one tooltip read (read true) when it knows none, which speedReads records.
    local kept = {}
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
      speed = function(id, read)
        if kept[id] or not read then return kept[id] end
        speedReads[#speedReads + 1] = id
        kept[id] = speedOf[id]
        return kept[id]
      end,
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
    items, statsOf, usableOf, speedOf, worn, requested, speedReads = {}, {}, {}, {}, {}, {}, {}
  end)

  -- Owner, 2026-11-06: the cheapest piece that beat the worn one offered "+1 armour" for 1s in every
  -- slot, "while there are much better things" a silver or two dearer.
  it("picks the piece that beats the worn one by the most, per slot", function()
    for _, id in ipairs({ 101, 102, 103 }) do items[id] = { loc = "INVTYPE_HEAD", class = 4, sub = 2 } end
    worn[1] = "item:900"
    statsOf = { ["item:900"] = STR(5), ["item:101"] = STR(4), ["item:102"] = STR(8), ["item:103"] = STR(7) }
    local r = U.Build(gear({ [101] = "100:0:0", [102] = "300:0:0", [103] = "200:0:0" }), drv(), W)
    assert.equal(1, #r.slots)
    local row = r.slots[1].best
    assert.equal("HEAD", row.group); assert.equal("INVTYPE_HEAD", r.slots[1].labelKey)
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
    assert.equal(1, #r.slots)
    assert.equal(142, r.slots[1].best.itemID)
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
    assert.equal(122, r.slots[1].best.itemID)
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
    speedOf = { [1600] = 1.8, [1601] = 2.7 }
    local g = gear({ [1600] = "50:0:0", [1601] = "50:0:0" })
    local r = U.Build(g, rogue(), R, false, { style = "sinister" })
    assert.equal(1601, r.slots[1].best.itemID)
    assert.near(70 * U.DpsFactor("ROGUE", "MAINHAND", 2.7), r.slots[1].best.gain, 1e-9)
    -- A warrior has no ability timer: the same gain, and the tie goes to the lower item string.
    assert.equal(1600, U.Build(g, drv(), { STR = 1, DPS = 7 }).slots[1].best.itemID)
    -- The worn sword is weighed by its own speed too: 9 DPS at 2.7 beats 10 at 1.8.
    worn[16] = "item:1690"
    statsOf["item:1690"], speedOf[1690] = DPS(9), 2.7
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
    speedOf = { [1700] = 2.6, [1701] = 2.6, [1703] = 2.6, [1790] = 2.6 }
    local g = gear({ [1700] = "10:0:0", [1701] = "10:0:0", [1702] = "10:0:0", [1703] = "10:0:0" })
    U.Build(g, rogue(), R)
    assert.same({ 1790, 1700 }, speedReads)                       -- the worn one first, then the candidate
    speedReads = {}
    local r = U.Build(g, rogue({ speed = function() error("a speed read on the count path") end,
      usable = function() error("a tooltip read on the count path") end }), R, true)
    assert.equal(4, #r.slots)                                     -- main hand, off hand, gloves, ranged
    assert.is_nil(r.speedPending)
    U.Build(g, drv(), { STR = 1, DPS = 7 })                       -- a warrior
    assert.same({}, speedReads)
    U.Build(g, rogue(), { AGI = 1 })                              -- weights that do not count DPS
    assert.same({}, speedReads)
  end)

  -- A rogue's first build read a tooltip for every main-hand lot it weighed (13.11), several
  -- hundred in one frame. A suffix never changes a weapon's speed, so one read covers the item.
  it("reads a weapon's speed once per item, at most SPEED_READS a build, the rest at REF_SPEED", function()
    local R, lots = { AGI = 1, DPS = 7 }, {}
    for i = 1, 50 do
      local id = 2000 + i
      items[id] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }
      statsOf["item:" .. id], speedOf[id], lots[id] = DPS(i), 2.6, "10:0:0"
    end
    local d = rogue()
    local r = U.Build(gear(lots), d, R)
    assert.equal(U.C.SPEED_READS, #speedReads)
    assert.equal(2050, speedReads[1]); assert.equal(2011, speedReads[40])   -- the strongest forty
    assert.equal(10, r.speedPending)
    assert.near(7 * 50 * U.DpsFactor("ROGUE", "MAINHAND", 2.6), r.slots[1].best.gain, 1e-9)
    r = U.Build(gear(lots), d, R)                                 -- the next build reads the other ten
    assert.equal(50, #speedReads)
    assert.is_nil(r.speedPending)
    U.Build(gear(lots), d, R)
    assert.equal(50, #speedReads)                                 -- every speed kept: no read at all
  end)

  it("reads the strongest main-hand item's speed first, ties on the itemID, each version weighed", function()
    local R = { AGI = 1, DPS = 7 }
    for _, id in ipairs({ 2101, 2102, 2103, 2104, 2105 }) do
      items[id] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }
      speedOf[id] = 2.6
    end
    statsOf = { ["item:2101"] = DPS(5), ["item:2102"] = DPS(9), ["item:2103"] = DPS(9), ["item:2104"] = DPS(7),
      ["item:2105::::::::::::1:12729"] = DPS(3), ["item:2105::::::::::::1:12917"] = DPS(8) }
    local g = { v = 2, at = 5, items = { [2101] = "10:0:0", [2102] = "10:0:0", [2103] = "10:0:0", [2104] = "10:0:0",
      [2105] = "10:0:0:12729 12:0:0:12917" } }
    U.C.SPEED_READS = 2
    local d = rogue()
    local r = U.Build(g, d, R)
    assert.same({ 2102, 2103 }, speedReads)
    assert.equal(3, r.speedPending)
    assert.equal(1, U.Build(g, d, R).speedPending)
    assert.same({ 2102, 2103, 2105, 2104 }, speedReads)           -- 2105 by its stronger version, read once
    assert.is_nil(U.Build(g, d, R).speedPending)
    assert.same({ 2102, 2103, 2105, 2104, 2101 }, speedReads)
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

  describe("the best set for the gold carried", function()
    local function cand(group, s, unit, gain, twoHand)
      return { group = group, itemString = s, unit = unit, gain = gain, twoHand = twoHand == true,
        diffs = { ITEM_MOD_STRENGTH_SHORT = gain } }
    end

    it("spends the purse where it adds the most", function()
      local h1, h2 = cand("HEAD", "item:1", 70, 9), cand("HEAD", "item:2", 30, 5)
      local c1, c2 = cand("CHEST", "item:3", 60, 8), cand("CHEST", "item:4", 25, 4)
      local f1 = cand("FEET", "item:5", 40, 5)
      -- The strongest head first leaves 30 for a 4-point chest (13); the cheaper head pays for all
      -- three: 30 + 25 + 40 = 95 for 5 + 4 + 5.
      local set = U.BestSet({ HEAD = { h1, h2 }, CHEST = { c1, c2 }, FEET = { f1 } }, 100)
      assert.equal(h2, set.picks.HEAD); assert.equal(c2, set.picks.CHEST); assert.equal(f1, set.picks.FEET)
      assert.equal(3, #set.list)
      assert.equal(h2, set.list[1]); assert.equal(c2, set.list[2]); assert.equal(f1, set.list[3])   -- GROUPS order
      assert.equal(95, set.cost); assert.equal(14, set.gain); assert.equal(5, set.left)
      assert.same({ ITEM_MOD_STRENGTH_SHORT = 14 }, set.diffs)
    end)

    it("buys nothing when nothing fits", function()
      assert.same({ picks = {}, list = {}, cost = 0, gain = 0, left = 0, diffs = {} },
        U.BestSet({ HEAD = { cand("HEAD", "item:1", 70, 9) } }, 0))
      assert.same({}, U.BestSet({ HEAD = { cand("HEAD", "item:1", 70, 9) } }, 69).picks)
      -- HERO plan, Review Focus 1: at 0 gold every slot still shows its strongest piece, and the set is empty.
      items[131] = { loc = "INVTYPE_HAND", class = 4, sub = 2 }
      statsOf["item:131"] = STR(10)
      local r = U.Build(gear({ [131] = "3000:0:0" }), drv({ money = function() return 0 end }), W)
      assert.equal(1, #r.slots)
      assert.is_true(r.slots[1].best.overGold)
      assert.is_false(r.slots[1].best.inSet)
      assert.same({}, r.set.picks)
      assert.equal(0, r.set.cost); assert.equal(0, r.set.left)
    end)

    it("gives nothing without a money read", function()
      assert.is_nil(U.BestSet({ HEAD = { cand("HEAD", "item:1", 70, 9) } }, nil))
      items[131] = { loc = "INVTYPE_HAND", class = 4, sub = 2 }
      statsOf["item:131"] = STR(10)
      local r = U.Build(gear({ [131] = "30:0:0" }), drv(), W)
      assert.is_nil(r.set)
      assert.is_false(r.slots[1].best.inSet)
    end)

    it("weighs a two-hander against both hands", function()
      local two = cand("MAINHAND", "item:10", 80, 15, true)
      local one, off = cand("MAINHAND", "item:11", 40, 8), cand("OFFHAND", "item:12", 40, 5)
      local set = U.BestSet({ MAINHAND = { two, one }, OFFHAND = { off } }, 100)
      assert.equal(two, set.picks.MAINHAND); assert.is_nil(set.picks.OFFHAND)   -- 15 beats 8 + 5
      off = cand("OFFHAND", "item:12", 40, 8)
      set = U.BestSet({ MAINHAND = { two, one }, OFFHAND = { off } }, 100)
      assert.equal(one, set.picks.MAINHAND); assert.equal(off, set.picks.OFFHAND)   -- 8 + 8 beats 15
      -- Never a two-hander with an off hand, however much gold: 15 + 8 for 120 is not a choice.
      set = U.BestSet({ MAINHAND = { two, one }, OFFHAND = { off } }, 200)
      assert.equal(one, set.picks.MAINHAND); assert.equal(off, set.picks.OFFHAND)
      assert.equal(80, set.cost)
    end)

    -- HERO plan, Review Focus 3: one lot cannot fill two hands.
    it("never puts one lot in both hands", function()
      local w = { STR = 1, DPS = 7 }
      items[1900] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }
      items[1901] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }
      statsOf["item:1900"], statsOf["item:1901"] = DPS(10), DPS(8)
      -- Main hand: 70 and 56. Off hand: 35 and 28. The stronger sword is the best choice for both.
      local d = drv({ money = function() return 1000 end })
      local r = U.Build(gear({ [1900] = "50:0:0", [1901] = "30:0:0" }), d, w)
      assert.equal(1900, r.set.picks.MAINHAND.itemID)
      assert.equal(1901, r.set.picks.OFFHAND.itemID)
      assert.equal(80, r.set.cost); assert.equal(98, r.set.gain)
      assert.equal("MAINHAND", r.slots[1].group)
      assert.is_true(r.slots[1].best.inSet)
      assert.equal("OFFHAND", r.slots[2].group)
      assert.is_false(r.slots[2].best.inSet)                       -- the stronger sword, in the other hand
      assert.equal(1901, r.slots[2].alts[1].itemID)                -- the set's off hand comes first
      assert.is_true(r.slots[2].alts[1].inSet)
      -- The weaker sword dearer than the stronger one: still the off hand's piece, though no
      -- price frontier of the off hand alone holds it.
      r = U.Build(gear({ [1900] = "50:0:0", [1901] = "60:0:0" }), d, w)
      assert.equal(1900, r.set.picks.MAINHAND.itemID)
      assert.equal(1901, r.set.picks.OFFHAND.itemID)
      assert.equal(110, r.set.cost)
      -- One sword only: one hand.
      r = U.Build(gear({ [1900] = "50:0:0" }), d, w)
      assert.equal(1900, r.set.picks.MAINHAND.itemID)
      assert.is_nil(r.set.picks.OFFHAND)
      assert.equal(50, r.set.cost)
    end)

    it("offers a one-hander that a cheaper, stronger two-hander would hide, for its pair with the off hand", function()
      local w = { STR = 1 }
      items[1950] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }
      items[1951] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }
      items[1952] = { loc = "INVTYPE_SHIELD", class = 4, sub = 6 }
      statsOf = { ["item:1950"] = STR(10), ["item:1951"] = STR(9), ["item:1952"] = STR(5) }
      local r = U.Build(gear({ [1950] = "40:0:0", [1951] = "50:0:0", [1952] = "30:0:0" }),
        drv({ money = function() return 100 end }), w)
      assert.equal(1951, r.set.picks.MAINHAND.itemID)               -- 9 + 5 for 80 beats 10 for 40
      assert.equal(1952, r.set.picks.OFFHAND.itemID)
    end)

    it("reads at most FRONTIER_CHECKS tooltips for a slot's set choices", function()
      local lots, asked = { [1460] = "100:0:0" }, {}
      items[1460] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
      statsOf["item:1460"] = STR(20)
      -- Ten a little cheaper, each red on the tooltip: all over the 80% step, so only the set's walk
      -- reads them.
      for i = 1, 10 do
        local id = 1460 + i
        items[id] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
        statsOf["item:" .. id] = STR(19 - i)
        lots[id] = (91 - i) .. ":0:0"
        usableOf["item:" .. id] = false
      end
      local d = drv({ money = function() return 500 end,
        usable = function(s) asked[#asked + 1] = s; return usableOf[s] end })
      local r = U.Build(gear(lots), d, W)
      assert.equal(1460, r.set.picks.CHEST.itemID)
      assert.same({}, r.slots[1].alts)
      assert.equal(1 + U.C.FRONTIER_CHECKS, #asked)                -- the strongest, then eight of the ten
    end)

    it("counts the set's piece, shown first, as the last one shown for the 80% step", function()
      for _, id in ipairs({ 1970, 1971, 1972 }) do items[id] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 } end
      statsOf = { ["item:1970"] = STR(10), ["item:1971"] = STR(8), ["item:1972"] = STR(7) }
      local r = U.Build(gear({ [1970] = "100:0:0", [1971] = "60:0:0", [1972] = "55:0:0" }),
        drv({ money = function() return 70 end }), W)
      assert.equal(1970, r.slots[1].best.itemID)                     -- over the gold
      assert.equal(1971, r.set.picks.CHEST.itemID)
      assert.same({ 1971 }, idsOf(r.slots[1].alts))                -- 55 is over 48, 80% of the set's 60
    end)

    it("builds no set on the count-only path, which only counts slots", function()
      items[131] = { loc = "INVTYPE_HAND", class = 4, sub = 2 }
      statsOf["item:131"] = STR(10)
      local r = U.Build(gear({ [131] = "30:0:0" }), drv({ money = function() return 1000 end }), W, true)
      assert.equal(1, #r.slots)
      assert.is_nil(r.set)
    end)

    -- Keeping only the cheapest states made a rich character's set spend less than it could: with
    -- two kept, the head and the chest together (11) lost to the head alone (5).
    it("thins a front past SET_STATES evenly, always keeping the cheapest and the strongest", function()
      local h, c = cand("HEAD", "item:1", 10, 5), cand("CHEST", "item:2", 20, 6)
      U.C.SET_STATES = 2
      assert.equal(11, U.BestSet({ HEAD = { h }, CHEST = { c } }, 100).gain)
      -- Five heads make a front of six states after the head: nothing and 10, 20, 30, 40, 50.
      -- Three kept are the first, a middle one (30) and the last, whatever comes after them.
      U.C.SET_STATES = 3
      local heads = {}
      for i = 1, 5 do heads[i] = cand("HEAD", "item:" .. i, 10 * i, i) end
      local function setWith(chest)
        return U.BestSet({ HEAD = heads, CHEST = { cand("CHEST", "item:9", chest[1], chest[2]) } }, 100)
      end
      local set = setWith({ 5, 10 })                               -- the strongest head still there
      assert.equal(heads[5], set.picks.HEAD); assert.equal(15, set.gain)
      set = setWith({ 65, 20 })                                    -- 35 left for a head: the middle one
      assert.equal(heads[3], set.picks.HEAD); assert.equal(95, set.cost)
      set = setWith({ 95, 30 })                                    -- nothing but the chest: the empty set
      assert.is_nil(set.picks.HEAD); assert.equal(30, set.gain)
    end)
  end)

  -- The HERO tab's "Add" (Task 8 writes the caps with GC.Buy._SetLineCap): one BUY line per item,
  -- pinned to the version picked, capped 5% over the lot's price.
  describe("BUY lines for picks", function()
    before_each(function() helper.loadModule("Core/AppRuns.lua", GC) end)
    local function pick(itemID, unit, version)
      return { itemID = itemID, unit = unit, version = version, itemString = "item:" .. itemID }
    end

    it("turns the set into BUY lines capped 5% over the price", function()
      local lines, caps = U.BuyLines({ pick(15210, 2700, "12718"), pick(6125, 1929, "0") })
      assert.same({ { i = 15210, q = 1, ver = "12718" }, { i = 6125, q = 1, ver = "0" } }, lines)
      assert.same({ [15210] = 2835, [6125] = 2025 }, caps)
      assert.same({ {}, {} }, { U.BuyLines({}) })
      assert.same({ {}, {} }, { U.BuyLines(nil) })
    end)

    it("gives one line of two for an item picked for both hands", function()
      local lines, caps = U.BuyLines({ pick(15210, 1200, "12721"), pick(15210, 1000, "12718") })
      assert.same({ { i = 15210, q = 2, ver = "12718,12721" } }, lines)
      assert.same({ [15210] = 1260 }, caps)                          -- the higher of 1260 and 1050
      lines = U.BuyLines({ pick(15210, 1200, "12718"), pick(15210, 1000, "12718") })
      assert.same({ { i = 15210, q = 2, ver = "12718" } }, lines)
    end)

    it("pins no version for a lot from a scan saved before versions", function()
      assert.same({ { i = 200, q = 1 } }, (U.BuyLines({ pick(200, 90) })))
      assert.same({ { i = 200, q = 2 } }, (U.BuyLines({ pick(200, 90, "12718"), pick(200, 80) })))
      assert.same({ { i = 200, q = 2 } }, (U.BuyLines({ pick(200, 90), pick(200, 80, "12718") })))
      -- Build's own candidates carry the lot's version: a v1 lot's is nil.
      items[200] = { loc = "INVTYPE_CLOAK", class = 4, sub = 1 }
      statsOf["item:200"] = STR(4)
      local best = U.Build(gear({ [200] = "90:0:0" }), drv(), W).slots[1].best
      assert.is_nil(best.version)
      assert.same({ { i = 200, q = 1 } }, (U.BuyLines({ best })))
      statsOf["item:200::::::::::::1:12718"] = STR(4)
      best = U.Build({ v = 2, at = 5, items = { [200] = "90:0:0:12718" } }, drv(), W).slots[1].best
      assert.same({ { i = 200, q = 1, ver = "12718" } }, (U.BuyLines({ best })))
    end)
  end)

  -- HERO plan, Task 9: an item's tooltip says whether the piece beats what the character wears, by
  -- the HERO tab's own rules, and reads no tooltip of its own to say it.
  describe("the upgrade line in an item's tooltip", function()
    local NAMES = { ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_STAMINA_SHORT = "Stamina",
      ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Damage per Second", SPEED = "Speed" }
    local was
    before_each(function()
      was = {}
      for k, v in pairs(NAMES) do was[k] = _G[k]; _G[k] = v end
    end)
    after_each(function()
      for k in pairs(NAMES) do _G[k] = was[k] end
    end)

    -- A link as the client writes one, the name in brackets; a bonus ID makes it a suffix version.
    local function link(id, name, bonus)
      local tail = bonus and ("::::::::20:1488:::1:%d::::::"):format(bonus) or ""
      return ("|cff1eff00|Hitem:%d%s|h[%s]|h|r"):format(id, tail, name)
    end
    local function say(text, tone) return { kind = "verdict", tone = tone or "good", text = text } end
    -- The spec's driver with no tooltip to read: a read inside a tooltip fails the spec.
    local function quiet(over)
      local d = drv(over)
      d.usable = function() error("a tooltip read inside a tooltip") end
      return d
    end
    local HEAD, RING = { loc = "INVTYPE_HEAD", class = 4, sub = 2 }, { loc = "INVTYPE_FINGER", class = 4, sub = 0 }

    it("says how much a piece beats the worn one", function()
      items[101], items[900] = HEAD, HEAD
      local old, new = link(900, "Old Cap"), link(101, "Iron Cap", 12729)
      worn[1] = old
      statsOf[old] = { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3 }
      statsOf[new] = { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 1 }
      assert.same({ say("Upgrade: +3 Strength, -2 Stamina over your Old Cap") }, U.TooltipVerdict(new, quiet(), W))
      worn[1] = nil
      assert.same({ say("Upgrade: +8 Strength, +1 Stamina, nothing worn there") }, U.TooltipVerdict(new, quiet(), W))
      -- A ring beats the weaker of the two worn, and the stronger worn ring itself says nothing.
      items[801], items[802], items[803] = RING, RING, RING
      local weak, strong, bag = link(801, "Copper Band"), link(802, "Silver Band"), link(803, "Gold Band")
      worn[11], worn[12] = strong, weak
      statsOf[weak], statsOf[strong], statsOf[bag] = STR(2), STR(6), STR(4)
      assert.same({ say("Upgrade: +2 Strength over your Copper Band") }, U.TooltipVerdict(bag, quiet(), W))
      assert.is_nil(U.TooltipVerdict(strong, quiet(), W))
      assert.same({}, speedReads)
    end)

    it("weighs a one-hand weapon for either hand and says the larger gain, with that hand's piece", function()
      local R = { AGI = 1, DPS = 7 }
      items[1300], items[1390] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }, { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }
      items[1391] = { loc = "INVTYPE_WEAPON", class = 2, sub = 15 }
      local sword, main, off = link(1300, "Raider Shortsword"), link(1390, "Militant Shortsword"), link(1391, "Hook Dagger")
      worn[16], worn[17] = main, off
      statsOf[sword], statsOf[main], statsOf[off] = DPS(11), DPS(10), DPS(4)
      local d = quiet({ classFile = function() return "ROGUE" end })
      -- +1 DPS in the main hand is 7; +7 in the off hand, which swings for half, is 24.5.
      assert.same({ say("Upgrade: +7 Damage per Second over your Hook Dagger") },
        U.TooltipVerdict(sword, d, R, { style = "sinister" }))
      statsOf[off] = DPS(12)
      assert.same({ say("Upgrade: +1 Damage per Second over your Militant Shortsword") },
        U.TooltipVerdict(sword, d, R, { style = "sinister" }))
      -- A Backstab rogue's main hand takes only a dagger, and the sword is weaker than its off hand.
      assert.is_nil(U.TooltipVerdict(sword, d, R, { style = "backstab" }))
      -- A mage never dual-wields: an off-hand dagger goes nowhere it can wear it.
      items[1100] = { loc = "INVTYPE_WEAPONOFFHAND", class = 2, sub = 15 }
      local dirk = link(1100, "Dirk")
      statsOf[dirk] = DPS(20)
      assert.is_nil(U.TooltipVerdict(dirk, quiet({ classFile = function() return "MAGE" end }), R))
    end)

    it("weighs a two-hander against both hands, naming both", function()
      items[910], items[911] = { loc = "INVTYPE_WEAPON", class = 2, sub = 7 }, { loc = "INVTYPE_SHIELD", class = 4, sub = 6 }
      items[701] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }
      local main, shield, great = link(910, "Short Sword"), link(911, "Buckler"), link(701, "Claymore")
      worn[16], worn[17] = main, shield
      statsOf[main], statsOf[shield], statsOf[great] = STR(6), { ITEM_MOD_STAMINA_SHORT = 8 }, STR(12)
      assert.same({ say("Upgrade: +6 Strength, -8 Stamina over your Short Sword and Buckler") },
        U.TooltipVerdict(great, quiet(), W))
      statsOf[great] = STR(10.5)                                   -- 0.5 over both: under MIN_GAIN_POINTS
      assert.is_nil(U.TooltipVerdict(great, quiet(), W))
    end)

    it("says when a piece is wearable in N levels", function()
      items[600] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 23 }
      items[601] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 21 }
      items[602] = { loc = "INVTYPE_LEGS", class = 4, sub = 4, minLevel = 40 }     -- plate, which a warrior wears from 40
      local silk, linen, plate = link(600, "Silk Pants"), link(601, "Linen Pants"), link(602, "Plate Legguards")
      statsOf[silk], statsOf[linen], statsOf[plate] = STR(5), STR(4), STR(9)
      assert.same({ say("Upgrade: +5 Strength, nothing worn there"), say("You can wear it in 3 levels", "dim") },
        U.TooltipVerdict(silk, quiet(), W))
      assert.same({ say("Upgrade: +4 Strength, nothing worn there"), say("You can wear it next level", "dim") },
        U.TooltipVerdict(linen, quiet(), W))
      assert.same({ say("Upgrade: +9 Strength, nothing worn there"), say("You can wear it in 2 levels", "dim") },
        U.TooltipVerdict(plate, quiet({ level = function() return 38 end }), W))
    end)

    it("says plainly when a piece holds nothing the class uses", function()
      items[810] = RING
      local owl = link(810, "Band of the Owl")
      statsOf[owl] = { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 3 }
      assert.same({ say("Not an upgrade for your Krieger: nothing here you use", "dim") },
        U.TooltipVerdict(owl, quiet({ className = function() return "Krieger" end }), W))
    end)

    it("says nothing for a weaker piece, one the class cannot wear, or one it cannot weigh", function()
      items[101], items[900] = HEAD, HEAD
      local old, new = link(900, "Old Cap"), link(101, "Iron Cap")
      worn[1], statsOf[old] = old, STR(5)
      statsOf[new] = STR(4)
      assert.is_nil(U.TooltipVerdict(new, quiet(), W))
      statsOf[new] = STR(5.5)                                      -- better, by less than a point of strength
      assert.is_nil(U.TooltipVerdict(new, quiet(), W))
      items[400] = { loc = "INVTYPE_CHEST", class = 4, sub = 4 }   -- plate at 20: the client's red line says so
      items[420] = { loc = "INVTYPE_TRINKET", class = 4, sub = 0 }
      items[430] = { loc = "INVTYPE_HEAD", class = 4, sub = 2, loading = true }
      items[440] = HEAD                                            -- its stats not answered
      for _, id in ipairs({ 400, 420, 430 }) do statsOf[link(id, "Piece")] = STR(30) end
      for _, id in ipairs({ 400, 420, 430, 440 }) do assert.is_nil(U.TooltipVerdict(link(id, "Piece"), quiet(), W)) end
      statsOf["item:101"] = STR(30)                                -- a bare id: a suffix version's base stats
      assert.is_nil(U.TooltipVerdict(101, quiet(), W))
      assert.is_nil(U.TooltipVerdict(nil, quiet(), W))
      assert.is_nil(U.TooltipVerdict(link(101, "Iron Cap"), quiet(), {}))   -- no weights
    end)

    -- A worn 1.50 dagger kept (about 0.92) against a weapon not read yet (1) would call a weapon
    -- of the same DPS an upgrade.
    it("weighs a weapon's speed only as kept, for both sides or neither, and never reads one", function()
      local R = { AGI = 1, DPS = 7 }
      items[1600] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7 }
      items[1690] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 15 }
      local cutlass, dagger = link(1600, "Cutlass"), link(1690, "Hook Dagger")
      worn[16], statsOf[cutlass], statsOf[dagger] = dagger, DPS(10.3), DPS(10)
      local kept, reads = { [1690] = 1.5 }, 0
      local d = quiet({ classFile = function() return "ROGUE" end, speed = function(id, read)
        if read then reads = reads + 1 end
        return kept[id]
      end })
      -- The dagger's speed is kept and the cutlass's is not: both weigh at REF_SPEED, and 0.3 DPS
      -- more is under 5% of the dagger's score.
      assert.is_nil(U.TooltipVerdict(cutlass, d, R, { style = "sinister" }))
      kept[1600] = 2.7                                             -- Build has read it since
      assert.same({ say("Upgrade: +0.3 Damage per Second over your Hook Dagger") },
        U.TooltipVerdict(cutlass, d, R, { style = "sinister" }))
      -- The same DPS at a slower speed: the swing is all that changes, and the line says so.
      statsOf[cutlass] = DPS(10)
      assert.same({ say("Upgrade: +1.20 Speed over your Hook Dagger") }, U.TooltipVerdict(cutlass, d, R, { style = "sinister" }))
      assert.equal(0, reads)
    end)
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
    assert.equal(1, #r.slots)
    assert.equal(90, r.slots[1].best.unit)
    assert.equal("item:200:0:0:0:0:0:-9:3", r.slots[1].best.itemString)
  end)

  it("never scores a piece the client has not answered for, and asks for it once", function()
    items[300] = { loc = "INVTYPE_FEET", class = 4, sub = 1, loading = true }   -- no level yet
    items[301] = { loc = "INVTYPE_FEET", class = 4, sub = 1 }                   -- no stats yet
    local r = U.Build(gear({ [300] = "10:0:0", [301] = "20:0:0" }), drv(), W)
    assert.equal(0, #r.slots)
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
    assert.equal(1, #r.slots)
    assert.equal("MAINHAND", r.slots[1].best.group)
    assert.equal(402, r.slots[1].best.itemID)
    items[500] = { loc = "INVTYPE_LEGS", class = 4, sub = 2 }           -- leather
    statsOf["item:500"] = STR(3)
    assert.equal(0, #U.Build(gear({ [500] = "5:0:0" }), drv({ classFile = function() return "MAGE" end }), W).slots)
  end)

  it("offers a piece one or two levels ahead only when nothing usable now qualifies", function()
    items[600] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 22 }
    items[601] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 23 }   -- three ahead: never
    statsOf = { ["item:600"] = STR(5), ["item:601"] = STR(9) }
    local r = U.Build(gear({ [600] = "10:0:0", [601] = "5:0:0" }), drv(), W)
    assert.equal(600, r.slots[1].best.itemID)
    assert.equal(22, r.slots[1].best.later)
    items[602] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 18 }
    statsOf["item:602"] = STR(2)
    r = U.Build(gear({ [600] = "10:0:0", [602] = "999:0:0" }), drv(), W)
    assert.equal(602, r.slots[1].best.itemID)                    -- usable now wins, even dearer
    assert.is_nil(r.slots[1].best.later)
  end)

  -- Final review M4: a level-ahead pick used to trust only the class table, so a class the table
  -- does not know could never get one -- even when the tooltip itself says yes.
  it("runs the tooltip usability check for a level-ahead pick too, not just the class table", function()
    items[1200] = { loc = "INVTYPE_LEGS", class = 4, sub = 1, minLevel = 22 }   -- TINKER: not in ARMOR
    statsOf["item:1200"] = STR(5)
    local tinker = drv({ classFile = function() return "TINKER" end })
    assert.equal(0, #U.Build(gear({ [1200] = "10:0:0" }), tinker, W).slots)
    usableOf["item:1200"] = true
    local r = U.Build(gear({ [1200] = "10:0:0" }), tinker, W)
    assert.equal(1, #r.slots)
    assert.equal(1200, r.slots[1].best.itemID)
    assert.equal(22, r.slots[1].best.later)
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
    assert.equal(1, #r.slots)
    assert.equal(701, r.slots[1].best.itemID)
    assert.equal(2, r.slots[1].best.gain)
    items[920] = { loc = "INVTYPE_2HWEAPON", class = 2, sub = 8 }
    worn[16], worn[17] = "item:920", nil
    statsOf["item:920"] = STR(12)
    items[702] = { loc = "INVTYPE_SHIELD", class = 4, sub = 6 }
    statsOf["item:702"] = { ITEM_MOD_STAMINA_SHORT = 20 }
    assert.equal(0, #U.Build(gear({ [702] = "1:0:0" }), drv(), W).slots)
  end)

  -- Final review I1: a class that can equip a dagger (per the WEAPON table) is not necessarily
  -- allowed to WEAR ONE IN THE OFF HAND -- that is a separate dual-wield restriction the tooltip
  -- does not redline, so ClassAllows alone offered it.
  it("offers an off-hand weapon only to a class and level that can dual-wield", function()
    items[1100] = { loc = "INVTYPE_WEAPONOFFHAND", class = 2, sub = 15 }   -- dagger
    statsOf["item:1100"] = STR(5)
    -- The default driver: a level-20 warrior -- dual-wields from level 20.
    assert.equal(1, #U.Build(gear({ [1100] = "10:0:0" }), drv(), W).slots)
    -- A level-19 warrior cannot yet.
    assert.equal(0, #U.Build(gear({ [1100] = "10:0:0" }), drv({ level = function() return 19 end }), W).slots)
    -- A rogue always can, at any level.
    assert.equal(1, #U.Build(gear({ [1100] = "10:0:0" }),
      drv({ classFile = function() return "ROGUE" end, level = function() return 1 end }), W).slots)
    -- A mage can equip a dagger (ClassAllows says yes) but can never dual-wield one.
    assert.equal(0, #U.Build(gear({ [1100] = "10:0:0" }),
      drv({ classFile = function() return "MAGE" end, level = function() return 60 end }), W).slots)
  end)

  it("trusts the client's own CanDualWield over the Classic fallback when it answers", function()
    items[1101] = { loc = "INVTYPE_WEAPONOFFHAND", class = 2, sub = 15 }
    statsOf["item:1101"] = STR(5)
    -- A rogue would fall back to true, but the client says no.
    assert.equal(0, #U.Build(gear({ [1101] = "10:0:0" }),
      drv({ classFile = function() return "ROGUE" end, canDualWield = function() return false end }), W).slots)
    -- A class the Classic fallback table does not list, but the client says yes.
    assert.equal(1, #U.Build(gear({ [1101] = "10:0:0" }),
      drv({ classFile = function() return "SHAMAN" end, canDualWield = function() return true end }), W).slots)
  end)

  it("measures a ring against the weaker of the two worn", function()
    items[800] = { loc = "INVTYPE_FINGER", class = 4, sub = 0 }
    items[801] = { loc = "INVTYPE_FINGER", class = 4, sub = 0 }
    items[802] = { loc = "INVTYPE_FINGER", class = 4, sub = 0 }
    worn[11], worn[12] = "item:801", "item:802"
    statsOf = { ["item:801"] = STR(3), ["item:802"] = STR(6), ["item:800"] = STR(4) }
    local r = U.Build(gear({ [800] = "7:0:0" }), drv(), W)
    assert.equal(800, r.slots[1].best.itemID)
    assert.equal(1, r.slots[1].best.gain)
  end)

  it("shows a class it has no rules for only what the tooltip says it can use", function()
    items[1000] = { loc = "INVTYPE_CHEST", class = 4, sub = 2 }
    statsOf["item:1000"] = STR(3)
    local tinker = drv({ classFile = function() return "TINKER" end })
    assert.equal(0, #U.Build(gear({ [1000] = "1:0:0" }), tinker, W).slots)
    usableOf["item:1000"] = true
    assert.equal(1, #U.Build(gear({ [1000] = "1:0:0" }), tinker, W).slots)
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

  -- The HERO probe's tooltips (13.11, a level 17 rogue), line by line as the client drew them: the
  -- worn Hook Dagger of the Falcon (P4) and Feet of the Lynx, which requires level 19 (P5).
  local WHITE, GREEN, BLUE, GOLD = { r = 1, g = 1, b = 1 }, { r = 0.12, g = 1, b = 0 }, { r = 0, g = 0.44, b = 0.87 },
    { r = 1, g = 0.82, b = 0 }
  local LEVEL_RED = { r = 1, g = 0.13, b = 0.13 }
  local function hookDagger()
    return {
      { leftText = "Hook Dagger of the Falcon", leftColor = GREEN, type = 22 },
      { leftText = "Binds when equipped", leftColor = WHITE, type = 20 },
      { leftText = "One-Hand", leftColor = WHITE, rightText = "Dagger", rightColor = WHITE, type = 21 },
      { leftText = "10 - 20 Damage", leftColor = WHITE, rightText = "Speed 1.50", rightColor = WHITE, type = 0 },
      { leftText = "(10.0 damage per second)", leftColor = WHITE, type = 0 },
      { leftText = "+2 Agility", leftColor = WHITE, type = 0 },
      { leftText = "+2 Intellect", leftColor = WHITE, type = 0 },
      { leftText = "Requires Level 15", leftColor = WHITE, type = 43 },
      { leftText = "", leftColor = GOLD, type = 11 },
    }
  end
  local function feetOfTheLynx()
    return {
      { leftText = "Feet of the Lynx", leftColor = BLUE, type = 22 },
      { leftText = "Binds when equipped", leftColor = WHITE, type = 20 },
      { leftText = "Feet", leftColor = WHITE, rightText = "Leather", rightColor = WHITE, type = 21 },
      { leftText = "63 Armor", leftColor = WHITE, type = 0 },
      { leftText = "+3 Strength", leftColor = WHITE, type = 0 },
      { leftText = "+8 Agility", leftColor = WHITE, type = 0 },
      { leftText = "Requires Level 19", leftColor = LEVEL_RED, type = 43 },
      { leftText = "", leftColor = GOLD, type = 11 },
    }
  end
  local function tip(lines) return { GetHyperlink = function() return { lines = lines } end } end
  local function withGlobals(values, fn)
    local was = {}
    for k, v in pairs(values) do was[k] = _G[k]; _G[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(values) do _G[k] = was[k] end
    if not ok then error(err, 0) end
  end

  it("reads weapon speed from the tooltip", function()
    withGlobals({ SPEED = "Speed" }, function()
      assert.equal(1.5, U.TooltipSpeed("item:3184", tip(hookDagger())))
      -- Jagged Knives (P4): the thrown weapon's damage line.
      assert.equal(1.8, U.TooltipSpeed("item:285282", tip({
        { leftText = "10 - 19 Damage", leftColor = WHITE, rightText = "Speed 1.80", rightColor = WHITE, type = 0 } })))
      -- A language that writes the decimal with a comma reads the same.
      local comma = hookDagger()
      comma[4].rightText = "Speed 1,50"
      assert.equal(1.5, U.TooltipSpeed("item:3184", tip(comma)))
      assert.is_nil(U.TooltipSpeed("item:1121", tip(feetOfTheLynx())))   -- no speed line
      assert.is_nil(U.TooltipSpeed("item:3184", {}))                       -- no client call
      assert.is_nil(U.TooltipSpeed("item:3184", { GetHyperlink = function() error("not loaded") end }))
    end)
    withGlobals({ SPEED = false }, function()
      assert.is_nil(U.TooltipSpeed("item:3184", tip(hookDagger())))        -- no word to look for
    end)
  end)

  it("offers a level-ahead piece whose only red line is its level", function()
    withGlobals({ ITEM_MIN_LEVEL = "Requires Level %d" }, function()
      assert.is_true(U.TooltipUsable("item:1121", tip(feetOfTheLynx())))
      -- Any other red line still says no: leather this class cannot wear, here.
      local leather = feetOfTheLynx()
      leather[3].rightColor = LEVEL_RED
      assert.is_false(U.TooltipUsable("item:1121", tip(leather)))
      -- A red line that only starts like the level line is not it.
      local other = feetOfTheLynx()
      other[7].leftText = "Requires Level 19 Engineering"
      assert.is_false(U.TooltipUsable("item:1121", tip(other)))
    end)
    -- Without the client's string the level line cannot be known, and red is a no, as before.
    withGlobals({ ITEM_MIN_LEVEL = false }, function()
      assert.is_false(U.TooltipUsable("item:1121", tip(feetOfTheLynx())))
    end)
  end)

  -- Blizzard draws RETRIEVING_ITEM_INFO in RED_FONT_COLOR: a tooltip still loading is not a "no".
  it("cannot tell from a tooltip that is still loading", function()
    withGlobals({ RETRIEVING_ITEM_INFO = "Retrieving item information" }, function()
      assert.is_nil(U.TooltipUsable("item:1121", tip({
        { leftText = "Retrieving item information", leftColor = { r = 1, g = 0.125, b = 0.125 } } })))
      assert.is_false(U.TooltipUsable("item:1121", tip({                  -- loaded, and red: a no
        { leftText = "Feet", leftColor = WHITE, rightText = "Plate", rightColor = { r = 1, g = 0.125, b = 0.125 } } })))
    end)
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
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT", "GetMoney", "SPEED" }

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
    assert.equal("|Hitem:101|h[Cap]|h", r.slots[1].best.link)
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
      counts[i] = #GC.ForeverUpgrades.Current().slots
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

  it("keeps no \"no\" from a tooltip that was still loading, and asks it again", function()
    init(16001)
    local was = _G.RETRIEVING_ITEM_INFO
    _G.RETRIEVING_ITEM_INFO = "Retrieving item information"
    finally(function() _G.RETRIEVING_ITEM_INFO = was end)
    local reads, red = 0, { r = 1, g = 0.125, b = 0.125 }
    _G.C_TooltipInfo = { GetHyperlink = function()
      reads = reads + 1
      if reads == 1 then return { lines = { { leftText = "Retrieving item information", leftColor = red } } } end
      return { lines = { { leftText = "Cap", leftColor = { r = 1, g = 1, b = 1 } } } }
    end }
    assert.equal(1, #GC.ForeverUpgrades.Current().slots)         -- cannot tell: the class rules say yes
    assert.equal(1, #GC.ForeverUpgrades.Current().slots)
    assert.equal(2, reads)                                        -- asked again, then kept
    GC.ForeverUpgrades.Current()
    assert.equal(2, reads)
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

  -- HERO probe P4 (13.11): the speed is on the tooltip's damage line. A random suffix changes a
  -- weapon's stats, never its speed, so one bare "item:<id>" read serves every version and the worn
  -- piece; read per item string, two versions of one sword cost two reads.
  it("reads a weapon's speed from its tooltip once per item, by its bare item string, the worn one's too", function()
    init(16001)
    _G.SPEED = "Speed"
    local function idOf(s) return tonumber(tostring(s):match("item:(%d+)")) end
    INFO[150] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9 } }
    INFO[160] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } }
    INFO[161] = { loc = "INVTYPE_WEAPONMAINHAND", class = 2, sub = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } }
    finally(function() INFO[150], INFO[160], INFO[161] = nil, nil, nil end)
    db.foreverScan.gear = { v = 2, at = 5000, items = { [160] = "300:0:0:12729 310:0:0:12917",
      [161] = "300:0:0:12800" } }
    _G.UnitClass = function() return "Rogue", "ROGUE", 4 end
    local WORN = "|cnIQ2:|Hitem:150::::::::17:1488:::1:12718::::::|h[Worn Sword of the Monkey]|h|r"
    _G.GetInventoryItemLink = function(_, slot) return slot == 16 and WORN or nil end
    local speeds, asked = { [150] = "Speed 2.70", [160] = "Speed 1.80", [161] = "Speed 2.70" }, {}
    _G.C_TooltipInfo = { GetHyperlink = function(s)
      asked[s] = (asked[s] or 0) + 1
      return { lines = { { leftText = "10 - 20 Damage", leftColor = { r = 1, g = 1, b = 1 }, rightText = speeds[idOf(s)],
        rightColor = { r = 1, g = 1, b = 1 } } } }
    end }
    local r = GC.ForeverUpgrades.Current()
    -- The slower sword at the same DPS; the faster one beats nothing the worn 2.7 sword does.
    assert.equal(1, #r.slots)
    assert.equal(161, r.slots[1].best.itemID)
    assert.equal(WORN, r.slots[1].worn)
    assert.equal(1, asked["item:150"])                            -- the worn sword, by its item
    assert.is_nil(asked[WORN])
    assert.equal(1, asked["item:160"])                            -- one read for both versions
    assert.equal(1, asked["item:161"])
    GC.ForeverUpgrades.Current()
    assert.equal(1, asked["item:150"])                            -- kept: not asked again
    assert.equal(1, asked["item:160"])
    assert.equal(1, asked["item:161"])
  end)

  it("tells the character looking at a piece whether it is an upgrade, on WoW: Forever only", function()
    INFO[102] = { loc = "INVTYPE_HEAD", class = 4, sub = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } }
    INFO[103] = { loc = "INVTYPE_FINGER", class = 4, sub = 0, stats = { ITEM_MOD_INTELLECT_SHORT = 5 } }
    finally(function() INFO[102], INFO[103] = nil, nil end)
    _G.GetInventoryItemLink = function(_, slot) return slot == 1 and "|cffffffff|Hitem:102|h[Old Cap]|h|r" or nil end
    _G.C_TooltipInfo = { GetHyperlink = function() error("a tooltip read inside a tooltip") end }
    local cap, ring = "|cff1eff00|Hitem:101|h[Cap]|h|r", "|cff1eff00|Hitem:103|h[Band]|h|r"
    init(120100)
    assert.is_nil(GC.ForeverUpgrades.TooltipVerdict(cap))
    assert.is_nil(db.forever)                                     -- retail never makes Forever's prefs
    init(16001)
    assert.same({ { kind = "verdict", tone = "good", text = "Upgrade: +3 Strength over your Old Cap" } },
      GC.ForeverUpgrades.TooltipVerdict(cap))
    assert.same({ { kind = "verdict", tone = "dim", text = "Not an upgrade for your Warrior: nothing here you use" } },
      GC.ForeverUpgrades.TooltipVerdict(ring))
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

  -- Finding 3 (13.11): the old DPS default of 2 rode along in every table /gc weights saved. It moves
  -- to the new default once, for the account's every melee class, and never again.
  it("moves a saved DPS weight of the old default to the new one, once", function()
    init(16001)
    db.forever = { weights = { ROGUE = { AGI = 1.5, DPS = 2 }, WARRIOR = { STR = 1, DPS = 2 },
      MAGE = { INT = 1, DPS = 2 }, PALADIN = { STR = 1, DPS = 3 } } }
    assert.same({ AGI = 1.5, DPS = 7 }, GC.ForeverUpgrades.WeightsFor(GC.ForeverScan.Prefs(), "ROGUE"))
    assert.same({ STR = 1, DPS = 7 }, db.forever.weights.WARRIOR)   -- the alt's too, in the same pass
    assert.same({ INT = 1, DPS = 2 }, db.forever.weights.MAGE)      -- a mage's 2 was never the old melee one
    assert.same({ STR = 1, DPS = 3 }, db.forever.weights.PALADIN)   -- typed, not the old default
    assert.equal(2, db.forever.weightsV)
    -- Typed again after the move, a 2 is the player's own.
    db.forever.weights.ROGUE.DPS = 2
    assert.same({ AGI = 1.5, DPS = 2 }, GC.ForeverUpgrades.WeightsFor(GC.ForeverScan.Prefs(), "ROGUE"))
    -- A save with no weights of its own is marked done too, so a 2 typed later stays.
    db.forever = {}
    GC.ForeverUpgrades.WeightsFor(GC.ForeverScan.Prefs(), "ROGUE")
    assert.equal(2, db.forever.weightsV)
    db.forever.weights = { ROGUE = { AGI = 1, DPS = 2 } }
    assert.equal(2, GC.ForeverUpgrades.WeightsFor(GC.ForeverScan.Prefs(), "ROGUE").DPS)
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
