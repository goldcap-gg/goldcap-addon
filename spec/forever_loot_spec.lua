local helper = require("spec.spec_helper")

describe("ForeverLoot record", function()
  local L
  local CTX = { map = 1429, level = 12, now = 200 }
  local G1, G2 = "Creature-0-1-0-2-448-0000AA", "Creature-0-1-0-2-448-0000BB"
  local OBJ = "GameObject-0-1-0-2-1731-0000DD"

  local function newStore() return { v = 1, id = "x", gen = 1, since = 100, n = 0, rows = {} } end
  local function seen() return { list = {}, set = {} } end
  local function item(id, sources, quest) return { kind = "item", itemID = id, quest = quest, sources = sources } end

  before_each(function() L = helper.loadModule("Core/ForeverLoot.lua").ForeverLoot end)

  it("names a source by kind and id, and nothing that is not a creature or an object", function()
    assert.same({ "c", 448 }, { L.Source(G1) })
    assert.same({ "c", 3342 }, { L.Source("Vehicle-0-1-0-2-3342-0000CC") })
    assert.same({ "o", 1731 }, { L.Source(OBJ) })
    assert.is_nil(L.Source("Player-1-0000ABCD"))
    assert.is_nil(L.Source("Item-1-0-4000000123"))
    assert.is_nil(L.Source(nil))
    assert.equal("c:448:1429", L.Key(G1, 1429, nil))
    assert.equal("s:448:1429:921", L.Key(G1, 1429, 921))
    assert.equal("o:1731:0", L.Key(OBJ, nil, 2366))                 -- an object is an object, whatever opened it
  end)

  it("counts coin, items and units per window, and leaves quest items out", function()
    local s = newStore()
    local n = L.Record(s, { slots = {
      { kind = "money", sources = { { G1, 35 } } },
      item(2589, { { G1, 2 } }),
      item(750, { { G1, 1 } }, true),
    } }, CTX, seen())
    assert.equal(1, n)
    assert.same({ ["c:448:1429"] = "1,35,12,12,0;2589:1:2" }, s.rows)
    assert.equal(1, s.n)
  end)

  it("credits each source of a window its own share", function()
    local s = newStore()
    L.Record(s, { slots = { item(2589, { { G1, 1 }, { G2, 2 } }) } }, CTX, seen())
    assert.equal("2,0,12,12,0;2589:2:3", s.rows["c:448:1429"])
  end)

  it("adds a later corpse to the same row, and never the same corpse twice", function()
    local s, sn = newStore(), seen()
    L.Record(s, { slots = { item(2589, { { G1, 2 } }) } }, CTX, sn)
    L.Record(s, { slots = { item(750, { { G2, 1 } }), item(2589, { { G2, 1 } }) } }, { map = 1429, level = 13, now = 300 }, sn)
    assert.equal("2,0,12,13,0;750:1:1 2589:2:3", s.rows["c:448:1429"])
    L.Record(s, { slots = { item(2589, { { G2, 5 } }) } }, CTX, sn)          -- LOOT_OPENED, or a reopened corpse
    assert.equal("2,0,12,13,0;750:1:1 2589:2:3", s.rows["c:448:1429"])
    L.Record(s, { slots = { item(2318, { { G2, 1 } }) } }, { map = 1429, level = 13, now = 310, spell = 8613 }, sn)
    assert.equal("1,0,13,13,0;2318:1:1", s.rows["s:448:1429:8613"])        -- skinning it after: its own row
  end)

  it("skips a fishing window, and loot from a player or an item", function()
    local s = newStore()
    assert.equal(0, L.Record(s, { fishing = true, slots = { item(1, { { G1, 1 } }) } }, CTX, seen()))
    assert.equal(0, L.Record(s, { slots = { item(1, { { "Item-1-0-4000000123", 1 } }) } }, CTX, seen()))
    assert.same({}, s.rows)
  end)

  it("keeps at most MAX_ITEMS items in a row and counts what it had to skip", function()
    L.C.MAX_ITEMS = 2
    local s = newStore()
    L.Record(s, { slots = { item(1, { { G1, 1 } }), item(2, { { G1, 1 } }) } }, CTX, seen())
    L.Record(s, { slots = { item(3, { { G2, 1 } }), item(1, { { G2, 1 } }) } }, CTX, seen())
    assert.equal("2,0,12,12,1;1:2:2 2:1:1", s.rows["c:448:1429"])
  end)

  it("rotates to a new generation when full, keeping the one before", function()
    L.C.MAX_KEYS = 1
    local s, sn = newStore(), seen()
    L.Record(s, { slots = { item(1, { { G1, 1 } }) } }, CTX, sn)
    L.Record(s, { slots = { item(1, { { OBJ, 1 } }) } }, { map = 1429, level = 12, now = 500 }, sn)
    assert.equal(2, s.gen)
    assert.equal(500, s.since)
    assert.equal(1, s.n)
    assert.same({ ["o:1731:1429"] = "1,0,12,12,0;1:1:1" }, s.rows)
    assert.same({ gen = 1, since = 100, to = 500, n = 1, rows = { ["c:448:1429"] = "1,0,12,12,0;1:1:1" } }, s.prev)
  end)

  it("starts a new generation when the client's build or region changes", function()
    local s = newStore()
    L.Ensure(s, { build = "1.60.1.70009", region = 90, now = 150 })
    assert.equal(1, s.gen)                                   -- empty: stamped, not rotated
    s.rows["c:1:1"], s.n = "1,0,1,1,0;", 1
    L.Ensure(s, { build = "1.60.1.70009", region = 90, now = 160 })
    assert.equal(1, s.gen)
    L.Ensure(s, { build = "1.60.2.71000", region = 90, now = 170 })
    assert.equal(2, s.gen)
    assert.equal("1.60.2.71000", s.build)
    assert.equal(170, s.prev.to)
  end)

  it("encodes what it decodes", function()
    local r = L.DecodeRow("3,120,10,14,2;750:1:1 2589:3:7")
    assert.same({ opens = 3, coin = 120, minLevel = 10, maxLevel = 14, skipped = 2, count = 2,
      items = { [750] = { 1, 1 }, [2589] = { 3, 7 } } }, r)
    assert.equal("3,120,10,14,2;750:1:1 2589:3:7", L.EncodeRow(r))
    assert.same({ opens = 0, coin = 0, skipped = 0, count = 0, items = {} }, L.DecodeRow(nil))
  end)
end)
