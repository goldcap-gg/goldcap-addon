local helper = require("spec.spec_helper")
local Client = require("spec.support.collection_client")
local W = require("spec.support.wow_frames")

-- Core/Collection.lua through its public functions, against spec/support/collection_client.lua's
-- API-shaped double. The one property every case below circles: "missing" only ever comes from
-- data the client has loaded, never from a function that is absent, raised or answered nil.

-- A small client world. Appearance 100 has four sources: two plate chests, a cosmetic chest and a
-- mail chest. Nothing is collected; each case adds what it needs.
local function world()
  return {
    items = {
      [7935] = { classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", appearanceID = 100, sourceID = 1001 },
      [7936] = { classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", appearanceID = 100, sourceID = 1002 },
      [7937] = { classID = 4, subclassID = 5, equipLoc = "INVTYPE_CHEST", appearanceID = 100, sourceID = 1003 },
      [7938] = { classID = 4, subclassID = 3, equipLoc = "INVTYPE_CHEST", appearanceID = 100, sourceID = 1004 },
      [2575] = { classID = 4, subclassID = 0, equipLoc = "INVTYPE_BODY", appearanceID = 200, sourceID = 2001 },
      [5976] = { classID = 4, subclassID = 0, equipLoc = "INVTYPE_TABARD", appearanceID = 300, sourceID = 3001 },
      [2549] = { classID = 2, subclassID = 10, equipLoc = "INVTYPE_2HWEAPON", appearanceID = 400, sourceID = 4001 },
      [8350] = { classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER" },
      -- Miscellaneous armor outside a shirt, tabard or off-hand slot, even with an appearance read.
      [4000] = { classID = 4, subclassID = 0, equipLoc = "INVTYPE_WAIST", appearanceID = 500, sourceID = 5001 },
      [2589] = { classID = 7, subclassID = 5, equipLoc = "" },
      [8485] = { classID = 15, subclassID = 2, petSpecies = 40 },
      [82800] = { classID = 17, subclassID = 0 },
      [1973] = { classID = 15, subclassID = 4, toy = true },
      [36862] = { classID = 0, subclassID = 8, toy = true },
      [34060] = { classID = 15, subclassID = 5, mountID = 7 },
      [2414] = { classID = 15, subclassID = 5 },
      [2553] = { classID = 9, subclassID = 6, tooltip = { "Recipe: Elixir of Minor Agility", "Requires Alchemy (50)" } },
    },
    sources = { [1001] = 7935, [1002] = 7936, [1003] = 7937, [1004] = 7938, [2001] = 2575, [3001] = 5976, [4001] = 2549 },
    appearances = { [100] = { 1001, 1002, 1003, 1004 }, [200] = { 2001 }, [300] = { 3001 }, [400] = { 4001 } },
    mounts = { [7] = false },
    species = { [40] = { owned = 0, max = 3 }, [41] = { owned = 2, max = 3 } },
    owned = { sources = {}, tabards = {}, toys = {} },
  }
end

local ITEMS = { 7935, 7936, 7937, 7938, 2575, 5976, 2549, 8350, 4000, 2589, 8485, 82800, 1973, 36862, 34060, 2414, 2553 }

describe("Collection", function()
  local GC, savedCreateFrame

  local function load(w)
    GC = helper.loadModule("Core/Collection.lua")
    local client, calls = Client.new(w)
    GC.Collection.SetClient(client)
    return calls
  end

  before_each(function()
    -- The event frame is its own spec below; here the module loads with no CreateFrame at all.
    savedCreateFrame = _G.CreateFrame
    _G.CreateFrame = nil
  end)

  after_each(function()
    _G.CreateFrame = savedCreateFrame
  end)

  describe("State", function()
    local function known(text) return { "Recipe: Elixir of Minor Agility", text } end

    local CASES = {
      -- appearances
      { "an appearance from this very source", 7935, nil, "collected", "appearance", function(w) w.owned.sources[1001] = true end },
      { "an appearance nobody has", 7935, nil, "missing", "appearance" },
      { "an appearance known through another plate chest", 7935, nil, "elsewhere", "appearance", function(w) w.owned.sources[1002] = true end },
      { "an appearance known through a cosmetic chest", 7935, nil, "elsewhere", "appearance", function(w) w.owned.sources[1003] = true end },
      { "an appearance known only through a mail chest (another armor type)", 7935, nil, "missing", "appearance", function(w) w.owned.sources[1004] = true end },
      { "a weapon appearance nobody has", 2549, nil, "missing", "appearance" },
      { "a shirt (miscellaneous armor in a shirt slot)", 2575, nil, "missing", "appearance" },
      { "a tabard, asked by item", 5976, nil, "collected", "appearance", function(w) w.owned.tabards[5976] = true end },
      { "a character that cannot learn it, on an account that can", 7935, nil, "missing", "appearance",
        function(w) w.collect = { [1001] = { player = { true, false }, account = { true, true } } } end },
      { "a source nobody on the account can collect", 7935, nil, "unknown", "appearance",
        function(w) w.collect = { [1001] = { player = { true, false }, account = { true, false } } } end },
      { "a source the account check has no data for", 7935, nil, "unknown", "appearance",
        function(w) w.collect = { [1001] = { player = { true, false }, account = { false, true } } } end },
      { "a source whose data is not loaded", 7935, nil, "unknown", "appearance",
        function(w) w.collect = { [1001] = { player = { false, false } } } end },
      { "an item the transmog API does not answer for", 7935, nil, "unknown", "appearance",
        function(w) w.items[7935].appearanceID = nil end },
      { "another known source whose item the client cannot name", 7935, nil, "unknown", "appearance",
        function(w) w.owned.sources[1002] = true; w.sources[1002] = nil end },
      { "Forever, an account with no appearance at all", 7935, nil, "unknown", "appearance", function(w) w.anyAppearance = false end },
      { "Forever, an account with appearances", 7935, nil, "missing", "appearance", function(w) w.anyAppearance = true end },
      { "Forever, HasAnyAppearance raising", 7935, nil, "unknown", "appearance",
        function(w) w.anyAppearance = true; w.raising = { ["C_TransmogCollection.HasAnyAppearance"] = true } end },
      -- not collectibles
      { "a ring", 8350, nil, nil, nil },
      { "miscellaneous armor in a waist slot", 4000, nil, nil, nil },
      { "a trade good", 2589, nil, nil, nil },
      -- pets
      { "a pet item whose species is owned", 8485, nil, "collected", "pet", function(w) w.species[40].owned = 1 end },
      { "a pet item whose species is not owned", 8485, nil, "missing", "pet" },
      { "a pet item whose species the journal does not know", 8485, nil, "unknown", "pet", function(w) w.species[40] = nil end },
      { "a cage with an owned species", 82800, 41, "collected", "pet" },
      { "a cage with a species not owned", 82800, 40, "missing", "pet" },
      { "a cage without its species", 82800, nil, "unknown", "pet" },
      -- toys
      { "a toy the account has", 1973, nil, "collected", "toy", function(w) w.owned.toys[1973] = true end },
      { "a toy the account lacks", 1973, nil, "missing", "toy" },
      { "a toy outside the Miscellaneous class", 36862, nil, "missing", "toy" },
      { "Forever, an account with no toy at all", 1973, nil, "unknown", "toy", function(w) w.anyToy = false end },
      { "Forever, an account with toys", 1973, nil, "missing", "toy", function(w) w.anyToy = true end },
      { "Forever, HasAnyToy raising", 1973, nil, "unknown", "toy",
        function(w) w.anyToy = true; w.raising = { ["C_ToyBoxInfo.HasAnyToy"] = true } end },
      -- mounts
      { "a mount the account has", 34060, nil, "collected", "mount", function(w) w.mounts[7] = true end },
      { "a mount the account lacks", 34060, nil, "missing", "mount" },
      { "a mount the journal returns nothing for", 34060, nil, "unknown", "mount", function(w) w.mounts[7] = nil end },
      { "a mount item the journal does not name", 2414, nil, "unknown", "mount" },
      -- recipes (the logged-in character only)
      { "a recipe this character knows", 2553, nil, "collected", "recipe", function(w) w.items[2553].tooltip = known(Client.ITEM_SPELL_KNOWN) end },
      { "a recipe this character does not know", 2553, nil, "missing", "recipe" },
      { "a recipe whose tooltip has not loaded", 2553, nil, "unknown", "recipe", function(w) w.items[2553].tooltip = nil end },
      { "a recipe whose tooltip is empty", 2553, nil, "unknown", "recipe", function(w) w.items[2553].tooltip = {} end },
      { "a recipe whose tooltip is still retrieving", 2553, nil, "unknown", "recipe",
        function(w) w.items[2553].tooltip = { Client.RETRIEVING_ITEM_INFO } end },
      { "a recipe on a client without ITEM_SPELL_KNOWN", 2553, nil, "unknown", "recipe",
        function(w) w.absent = { ITEM_SPELL_KNOWN = true } end },
      -- the client itself
      { "an item the client has never heard of", 999999, nil, "unknown", nil },
    }

    for _, case in ipairs(CASES) do
      local name, itemID, species, state, kind, edit = case[1], case[2], case[3], case[4], case[5], case[6]
      it(name .. " is " .. tostring(state) .. " (" .. tostring(kind) .. ")", function()
        local w = world()
        if edit then edit(w) end
        load(w)
        local gotState, gotKind = GC.Collection.State(itemID, species)
        assert.equal(state, gotState)
        assert.equal(kind, gotKind)
      end)
    end

    it("answers unknown, never missing, when the client has none of its functions", function()
      GC = helper.loadModule("Core/Collection.lua")
      GC.Collection.SetClient({})
      for _, itemID in ipairs(ITEMS) do
        local state = GC.Collection.State(itemID)
        assert.equal("unknown", state, itemID)
      end
      assert.equal("unknown", (GC.Collection.State(82800, 40)))
    end)

    it("answers unknown for something that is not an item id", function()
      load(world())
      assert.same({ "unknown" }, { GC.Collection.State("7935") })
      assert.same({ "unknown" }, { GC.Collection.State(nil) })
    end)
  end)

  -- A function the client lacks, or one that raises, may only ever turn an answer into
  -- "unknown". Run over three worlds so every path meets every function: nothing collected,
  -- a mixed account, and a Forever account whose HasAny reads say it has collections.
  describe("an absent or raising client function", function()
    local function mixed(w)
      w.owned.sources[1002] = true
      w.owned.tabards[5976] = true
      w.owned.toys[1973] = true
      w.mounts[7] = true
      w.species[40].owned = 1
      w.items[2553].tooltip = { "Recipe: Elixir of Minor Agility", Client.ITEM_SPELL_KNOWN }
      w.collect = { [4001] = { player = { true, false }, account = { true, true } } }
    end
    local function forever(w)
      w.anyAppearance, w.anyToy = true, true
    end
    local WORLDS = { { "nothing collected" }, { "a mixed account", mixed }, { "a Forever account", forever } }

    local function answers(edit, broken)
      local w = world()
      if edit then edit(w) end
      for k, v in pairs(broken or {}) do w[k] = v end
      load(w)
      local out = {}
      for _, itemID in ipairs(ITEMS) do out[#out + 1] = { itemID, GC.Collection.State(itemID) } end
      out[#out + 1] = { "82800:40", GC.Collection.State(82800, 40) }
      return out
    end

    local function degradesOnly(baseline, got, label)
      for i, row in ipairs(got) do
        local want = baseline[i]
        if not (row[2] == want[2] and row[3] == want[3]) then
          assert.equal("unknown", row[2], label .. ": " .. tostring(row[1]) .. " was " .. tostring(want[2]))
        end
        if want[2] ~= "missing" then
          assert.are_not.equal("missing", row[2], label .. ": " .. tostring(row[1]))
        end
      end
    end

    for _, wcase in ipairs(WORLDS) do
      for _, name in ipairs(Client.NAMES) do
        it("absent: " .. name .. " (" .. wcase[1] .. ")", function()
          local baseline = answers(wcase[2])
          degradesOnly(baseline, answers(wcase[2], { absent = { [name] = true } }), name)
        end)
        it("raising: " .. name .. " (" .. wcase[1] .. ")", function()
          local baseline = answers(wcase[2])
          degradesOnly(baseline, answers(wcase[2], { raising = { [name] = true } }), name)
        end)
      end
      for _, name in ipairs(Client.STRINGS) do
        it("absent: " .. name .. " (" .. wcase[1] .. ")", function()
          local baseline = answers(wcase[2])
          degradesOnly(baseline, answers(wcase[2], { absent = { [name] = true } }), name)
        end)
      end
    end

    it("the worlds above do reach every answer, so the property has something to hold", function()
      local seen = {}
      for _, wcase in ipairs(WORLDS) do
        for _, row in ipairs(answers(wcase[2])) do seen[tostring(row[2])] = true end
      end
      for _, state in ipairs({ "collected", "elsewhere", "missing", "unknown", "nil" }) do
        assert.is_true(seen[state] == true, state)
      end
    end)
  end)

  describe("the cache", function()
    it("answers a second time without asking the client, and asks again after Reset", function()
      local calls = load(world())
      assert.equal("missing", (GC.Collection.State(7935)))
      local asked = calls.total
      assert.equal("missing", (GC.Collection.State(7935)))
      assert.equal(asked, calls.total)
      GC.Collection.Reset()
      assert.equal("missing", (GC.Collection.State(7935)))
      assert.is_true(calls.total > asked)
    end)

    it("remembers a non-collectible too", function()
      local calls = load(world())
      assert.is_nil(GC.Collection.State(2589))
      local asked = calls.total
      assert.is_nil(GC.Collection.State(2589))
      assert.equal(asked, calls.total)
    end)

    it("does not remember unknown: the tooltip that loads later is read", function()
      local w = world()
      w.items[2553].tooltip = nil
      local calls = load(w)
      assert.equal("unknown", (GC.Collection.State(2553)))
      local asked = calls["C_TooltipInfo.GetItemByID"]
      assert.equal("unknown", (GC.Collection.State(2553)))
      assert.equal(asked + 1, calls["C_TooltipInfo.GetItemByID"])
      w.items[2553].tooltip = { "Recipe: Elixir of Minor Agility", Client.ITEM_SPELL_KNOWN }
      assert.same({ "collected", "recipe" }, { GC.Collection.State(2553) })
    end)

    it("keeps one answer per species for the same cage item", function()
      load(world())
      assert.equal("missing", (GC.Collection.State(82800, 40)))
      assert.equal("collected", (GC.Collection.State(82800, 41)))
      assert.equal("unknown", (GC.Collection.State(82800)))
    end)

    it("answers from what is collected now once Reset has run", function()
      local w = world()
      load(w)
      assert.equal("missing", (GC.Collection.State(1973)))
      w.owned.toys[1973] = true
      assert.equal("missing", (GC.Collection.State(1973)))
      GC.Collection.Reset()
      assert.equal("collected", (GC.Collection.State(1973)))
    end)
  end)

  describe("OnChange", function()
    it("calls every listener after a Reset", function()
      load(world())
      local heard = {}
      GC.Collection.OnChange(function() heard[#heard + 1] = "a" end)
      GC.Collection.OnChange(function() heard[#heard + 1] = "b" end)
      GC.Collection.OnChange("not a function")
      GC.Collection.Reset()
      assert.same({ "a", "b" }, heard)
    end)
  end)

  describe("the client it reads by default", function()
    it("is the real globals, looked up at call time", function()
      local saved = _G.C_PetJournal
      GC = helper.loadModule("Core/Collection.lua")
      GC.Collection.SetClient(nil)
      _G.C_PetJournal = { GetNumCollectedInfo = function() return 1, 3 end }
      local ok, state, kind = pcall(GC.Collection.State, 82800, 40)
      _G.C_PetJournal = saved
      assert.is_true(ok)
      assert.same({ "collected", "pet" }, { state, kind })
    end)
  end)

  describe("the collection events", function()
    local EVENTS = {
      "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED",
      "NEW_PET_ADDED", "PET_JOURNAL_LIST_UPDATE", "PET_JOURNAL_PET_DELETED",
      "NEW_TOY_ADDED", "TOYS_UPDATED",
      "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "COMPANION_UNLEARNED",
      "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE",
    }
    local frame

    before_each(function()
      frame = nil
      _G.CreateFrame = function(...)
        frame = W.CreateFrame(...)
        return frame
      end
    end)

    after_each(function()
      W.unknownEvents = {}
    end)

    it("are each registered, and one the client does not know does not stop the rest", function()
      W.unknownEvents = { NEW_RECIPE_LEARNED = true }
      load(world())
      assert.is_not_nil(frame)
      for _, event in ipairs(EVENTS) do
        assert.equal(event ~= "NEW_RECIPE_LEARNED", frame:IsEventRegistered(event), event)
      end
    end)

    it("forget every answer and tell the listeners", function()
      local w = world()
      local calls = load(w)
      local heard = 0
      GC.Collection.OnChange(function() heard = heard + 1 end)
      assert.equal("missing", (GC.Collection.State(34060)))
      w.mounts[7] = true
      local asked = calls.total
      frame:GetScript("OnEvent")(frame, "NEW_MOUNT_ADDED", 7)
      assert.equal(1, heard)
      assert.equal("collected", (GC.Collection.State(34060)))
      assert.is_true(calls.total > asked)
    end)
  end)
end)
