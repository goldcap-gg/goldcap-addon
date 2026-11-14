local helper = require("spec.spec_helper")

-- Core/ForeverSources.lua: what WoW: Forever's profession trainers teach and its merchants sell, as
-- the player saw it. GUIDs and rows are shaped as the client gave them (probe, 2026-11-14).
describe("Forever trainers and merchants", function()
  local S

  before_each(function()
    S = helper.loadModule("Core/ForeverSources.lua").ForeverSources
  end)

  local MARY = "Creature-0-7101-0-2-4591-7D50BEF864"
  local function npc(guid, extra)
    local t = { guid = guid or MARY, name = "Mary Edras", map = 1458, zone = "Undercity",
      subzone = "Rogues' Quarter", faction = "Horde" }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end
  local function service(spellID, extra)
    local t = { spellID = spellID, skillLine = "First Aid", requiredSkill = 20, cost = 90, level = 0 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end
  local function ware(itemID, extra)
    local t = { itemID = itemID, price = 180, stack = 5, available = -1, classID = 7, subclassID = 11,
      extended = false }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end

  describe("the npc id", function()
    local GUIDS = {
      { name = "a creature", guid = MARY, id = 4591 },
      { name = "another creature", guid = "Creature-0-7101-0-2-5820-7D50BEF864", id = 5820 },
      { name = "a player", guid = "Player-7101-0A1B2C3D", id = nil },
      { name = "a vehicle", guid = "Vehicle-0-7101-0-2-4591-7D50BEF864", id = nil },
      { name = "a pet", guid = "Pet-0-7101-0-2-4591-7D50BEF864", id = nil },
      { name = "a game object", guid = "GameObject-0-7101-0-2-1617-7D50BEF864", id = nil },
      { name = "a creature id of 0", guid = "Creature-0-7101-0-2-0-7D50BEF864", id = nil },
      { name = "a cut GUID", guid = "Creature-0-7101-0-2-4591", id = nil },
      { name = "an empty string", guid = "", id = nil },
      { name = "no GUID", guid = nil, id = nil },
      { name = "a number", guid = 4591, id = nil },
    }
    for _, case in ipairs(GUIDS) do
      it("is " .. tostring(case.id) .. " for " .. case.name, function()
        assert.equal(case.id, S.NpcId(case.guid))
      end)
    end

    for _, case in ipairs(GUIDS) do
      if case.id == nil then
        it("keeps nothing for " .. case.name, function()
          local root, who = {}, npc()
          who.guid = case.guid
          assert.equal(0, S.RecordTrainer(root, who, { service(3274) }, 100))
          assert.equal(0, S.RecordVendor(root, who, { ware(3372) }, 100))
          assert.is_nil(root.foreverSources)
        end)
      end
    end
  end)

  describe("a trainer", function()
    it("keeps the npc, where it stands and each service by its spell", function()
      local root = {}
      assert.equal(2, S.RecordTrainer(root, npc(), {
        service(3274, { skillLine = "First Aid", requiredSkill = 50, cost = 450 }), -- Journeyman: no item
        service(1230117, { link = "|cnIQ1:|Hitem:6454::::::::17:1488:::::::::|h[Strong Anti-Venom]|h|r" }),
      }, 100))
      assert.same({ v = 1, vendors = {}, trainers = { [4591] = {
        n = "Mary Edras", m = 1458, z = "Undercity", s = "Rogues' Quarter", f = "Horde", at = 100,
        sv = {
          [3274] = { l = "First Aid", r = 50, c = 450, lv = 0 },
          [1230117] = { l = "First Aid", r = 20, c = 90, lv = 0, i = 6454 },
        } } } }, root.foreverSources)
    end)

    -- Blizzard's trainer window hides what the character has learned: a second character sees
    -- another part of the list, and nothing the first one saw is lost.
    it("merges what each visit shows and deletes nothing", function()
      local root = {}
      S.RecordTrainer(root, npc(), { service(1, { cost = 10 }), service(2, { cost = 20 }) }, 100)
      assert.equal(2, S.RecordTrainer(root, npc(), { service(2, { cost = 25 }), service(3, { cost = 30 }) }, 200))
      local sv = root.foreverSources.trainers[4591].sv
      assert.equal(10, sv[1].c)
      assert.equal(25, sv[2].c)
      assert.equal(30, sv[3].c)
      assert.equal(200, root.foreverSources.trainers[4591].at)
    end)

    local LINKS = {
      { name = "a later visit with the link fills the item", first = nil,
        second = "|Hitem:6454::::::::17:1488:::::::::|h[Strong Anti-Venom]|h", item = 6454 },
      { name = "a later visit still loading the item keeps it",
        first = "|Hitem:6454::::::::17:1488:::::::::|h[Strong Anti-Venom]|h", second = nil, item = 6454 },
      { name = "a link that is not an item's is no item", first = "|Hspell:3274|h[First Aid]|h", second = nil,
        item = nil },
    }
    for _, case in ipairs(LINKS) do
      it("merges field by field: " .. case.name, function()
        local root = {}
        S.RecordTrainer(root, npc(), { service(7934, { link = case.first }) }, 100)
        S.RecordTrainer(root, npc(), { service(7934, { link = case.second }) }, 200)
        assert.equal(case.item, root.foreverSources.trainers[4591].sv[7934].i)
      end)
    end

    it("keeps a field a later visit could not read, and where the npc stands", function()
      local root = {}
      S.RecordTrainer(root, npc(), { service(7934, { level = 10 }) }, 100)
      local later = npc(nil, { subzone = "" })
      later.faction = nil
      S.RecordTrainer(root, later, { service(7934, { level = "x", cost = 95 }) }, 200)
      local entry = root.foreverSources.trainers[4591]
      assert.same({ l = "First Aid", r = 20, c = 95, lv = 10 }, entry.sv[7934])
      assert.equal("Rogues' Quarter", entry.s)
      assert.equal("Horde", entry.f)
    end)

    -- A row's spell is its tooltip's id: a row whose tooltip is not a spell's has none.
    local NO_SPELL = { 0, -1, 2.5, "3274", false }
    for _, spell in ipairs(NO_SPELL) do
      it("skips a row whose spell id is " .. tostring(spell), function()
        local root = {}
        assert.equal(1, S.RecordTrainer(root, npc(), { service(spell), service(3274) }, 100))
        local sv = root.foreverSources.trainers[4591].sv
        local n = 0
        for _ in pairs(sv) do n = n + 1 end
        assert.equal(1, n)
        assert.is_not_nil(sv[3274])
      end)
    end

    it("skips a row with no spell id, and keeps nothing when no row has one", function()
      local root = {}
      assert.equal(0, S.RecordTrainer(root, npc(), { { skillLine = "First Aid", cost = 90 }, service(0) }, 100))
      assert.is_nil(root.foreverSources)
    end)
  end)

  describe("a merchant", function()
    it("keeps the npc and each item it sells", function()
      local root = {}
      assert.equal(3, S.RecordVendor(root, npc("Creature-0-7101-0-2-4585-7D50BEF864", { name = "Joseph Moore",
        faction = "" }), {
        ware(3372),
        ware(799, { price = 320, stack = 1, classID = 4, subclassID = 2 }),
        ware(21099, { price = 0, stack = 1, available = 2, classID = 9, subclassID = 6, extended = true }),
      }, 100))
      assert.same({ v = 1, trainers = {}, vendors = { [4585] = {
        n = "Joseph Moore", m = 1458, z = "Undercity", s = "Rogues' Quarter", at = 100,
        it = {
          [3372] = { p = 180, k = 5, a = -1, c = 7, sc = 11 },
          [799] = { p = 320, k = 1, a = -1, c = 4, sc = 2 },
          [21099] = { p = 0, k = 1, a = 2, c = 9, sc = 6, x = true },
        } } } }, root.foreverSources)
    end)

    -- Blizzard's merchant window filters by the player's class at each show: a second character
    -- can see fewer items, and nothing the first one saw is lost.
    it("merges what each visit shows and deletes nothing", function()
      local root = {}
      S.RecordVendor(root, npc(), { ware(3372), ware(2320), ware(799, { classID = 4, subclassID = 2 }) }, 100)
      assert.equal(2, S.RecordVendor(root, npc(), { ware(3372, { price = 200, available = 4 }), ware(2321) }, 200))
      local entry = root.foreverSources.vendors[4591]
      assert.same({
        [3372] = { p = 200, k = 5, a = 4, c = 7, sc = 11 },
        [2320] = { p = 180, k = 5, a = -1, c = 7, sc = 11 },
        [799] = { p = 180, k = 5, a = -1, c = 4, sc = 2 },
        [2321] = { p = 180, k = 5, a = -1, c = 7, sc = 11 },
      }, entry.it)
      assert.equal(200, entry.at)
    end)

    it("merges field by field: a field a visit could not read stays, and `x` is the visit's", function()
      local root = {}
      S.RecordVendor(root, npc(), { ware(3372, { price = 0, extended = true }) }, 100)
      S.RecordVendor(root, npc(), { ware(3372, { classID = "x", price = 180 }) }, 200)
      assert.same({ p = 180, k = 5, a = -1, c = 7, sc = 11 }, root.foreverSources.vendors[4591].it[3372])
    end)

    -- Half the probe's merchant reads, a second after the window opened, listed no items.
    it("changes nothing on a read with no items", function()
      local root = {}
      S.RecordVendor(root, npc(), { ware(3372) }, 100)
      assert.equal(0, S.RecordVendor(root, npc(), {}, 200))
      assert.equal(0, S.RecordVendor(root, npc(), { { price = 10 } }, 300))
      assert.same({ [3372] = { p = 180, k = 5, a = -1, c = 7, sc = 11 } }, root.foreverSources.vendors[4591].it)
      assert.equal(100, root.foreverSources.vendors[4591].at)
    end)

    it("makes no store on a read with no items", function()
      local root = {}
      assert.equal(0, S.RecordVendor(root, npc(), {}, 100))
      assert.is_nil(root.foreverSources)
    end)

    it("keeps an item listed twice by its row for gold", function()
      local root = {}
      assert.equal(1, S.RecordVendor(root, npc(), { ware(3372, { price = 0, extended = true }), ware(3372) }, 100))
      assert.same({ p = 180, k = 5, a = -1, c = 7, sc = 11 }, root.foreverSources.vendors[4591].it[3372])
      S.RecordVendor(root, npc(), { ware(3372), ware(3372, { price = 0, extended = true }) }, 200)
      assert.same({ p = 180, k = 5, a = -1, c = 7, sc = 11 }, root.foreverSources.vendors[4591].it[3372])
    end)
  end)

  describe("the caps", function()
    local function guid(id) return ("Creature-0-7101-0-2-%d-7D50BEF864"):format(id) end
    local function count(t)
      local n = 0
      for _ in pairs(t) do n = n + 1 end
      return n
    end

    local CAPS = {
      { name = "trainers", list = "trainers", cap = 400,
        record = function(root, id, now) return S.RecordTrainer(root, npc(guid(id)), { service(3274) }, now) end },
      { name = "merchants", list = "vendors", cap = 600,
        record = function(root, id, now) return S.RecordVendor(root, npc(guid(id)), { ware(3372) }, now) end },
    }
    for _, case in ipairs(CAPS) do
      it("keep " .. case.cap .. " " .. case.name .. ", dropping the one seen longest ago", function()
        assert.equal(case.cap, S.C[case.list == "trainers" and "MAX_TRAINERS" or "MAX_VENDORS"])
        local root = {}
        for id = 1, case.cap do case.record(root, id, 1000 + id) end
        local list = root.foreverSources[case.list]
        assert.equal(case.cap, count(list))
        -- A visit to one already kept drops nobody.
        case.record(root, 1, 5000)
        assert.equal(case.cap, count(list))
        -- A new one drops the oldest, now npc 2 (npc 1 was just seen again).
        case.record(root, 99999, 6000)
        assert.equal(case.cap, count(list))
        assert.is_nil(list[2])
        assert.is_not_nil(list[1])
        assert.is_not_nil(list[99999])
      end)

      it("never drop the " .. case.name .. " entry just written, and break a tie by the lower id", function()
        local root = {}
        for id = 1, case.cap do case.record(root, id + 10, 9000) end
        -- A clock that went back: the new one is the oldest of all, and stays.
        case.record(root, 5, 100)
        local list = root.foreverSources[case.list]
        assert.equal(case.cap, count(list))
        assert.is_not_nil(list[5])
        assert.is_nil(list[11])
        assert.is_not_nil(list[12])
      end)
    end
  end)

  -- A store a newer GoldCap wrote, or one of another shape, is neither read nor written.
  describe("a store it does not know", function()
    local FOREIGN = {
      { name = "a newer version", store = { v = 2, trainers = {}, vendors = {} } },
      { name = "no version", store = { trainers = {}, vendors = {} } },
      { name = "no trainers table", store = { v = 1, vendors = {} } },
      { name = "no vendors table", store = { v = 1, trainers = {} } },
      { name = "not a table", store = "x" },
    }
    for _, case in ipairs(FOREIGN) do
      it("is left alone: " .. case.name, function()
        local store = case.store
        local before = type(store) == "table" and {} or store
        if type(store) == "table" then for k, v in pairs(store) do before[k] = v end end
        local root = { foreverSources = store }
        assert.is_nil(S.Store(root, true))
        assert.equal(0, S.RecordTrainer(root, npc(), { service(3274) }, 100))
        assert.equal(0, S.RecordVendor(root, npc(), { ware(3372) }, 100))
        assert.equal(store, root.foreverSources)
        if type(store) == "table" then
          assert.same(before, store)
          for _, k in ipairs({ "trainers", "vendors" }) do
            if type(store[k]) == "table" then assert.is_nil(next(store[k]), k) end
          end
        end
      end)
    end
  end)

  it("answers nothing without a save, an npc, rows or a time", function()
    assert.equal(0, S.RecordTrainer(nil, npc(), { service(3274) }, 100))
    assert.equal(0, S.RecordTrainer({}, nil, { service(3274) }, 100))
    assert.equal(0, S.RecordTrainer({}, npc(), nil, 100))
    assert.equal(0, S.RecordTrainer({}, npc(), { service(3274) }, nil))
    assert.equal(0, S.RecordVendor(nil, npc(), { ware(3372) }, 100))
    assert.equal(0, S.RecordVendor({}, nil, { ware(3372) }, 100))
    assert.equal(0, S.RecordVendor({}, npc(), "x", 100))
    assert.equal(0, S.RecordVendor({}, npc(), { ware(3372) }, nil))
    assert.is_nil(S.Store(nil, true))
    assert.is_nil(S.Store({}, false))
  end)
end)
