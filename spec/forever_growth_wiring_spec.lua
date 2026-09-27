-- Plan 3e (Road to 40, AH Upgrade Finder, loot recorder): the source wiring in Core/Init.lua.
-- Every event and slash command the plan adds lives inside one of Init.lua's two Forever gates
-- (`if GC.Game and GC.Game.IsForever(GC.Game.Passport()) then`), and nowhere else -- so a retail
-- client registers exactly what it did before.

local function read(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

local GATE = "if GC%.Game and GC%.Game%.IsForever%(GC%.Game%.Passport%(%)%) then"

-- The Forever gate that registers REPLICATE_ITEM_LIST_UPDATE: its text, and where it starts and ends.
local function foreverEventBlock(init)
  local start = assert(init:find('RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")', 1, true))
  local open = assert(init:sub(1, start):match(".*()" .. GATE))
  local close = assert(init:find("\nend\n", start, true))
  return init:sub(open, close), open, close
end

-- The Forever gate that holds /gc scan and /gc bags.
local function foreverSlashBlock(init)
  local start = assert(init:find("GC.slashHandlers.scan =", 1, true))
  local open = assert(init:sub(1, start):match(".*()" .. GATE))
  local close = assert(init:find("\nend\n", start, true))
  return init:sub(open, close)
end

-- A registration inside the event gate and nowhere outside it.
local function assertGatedEvent(init, needle)
  local block, open, close = foreverEventBlock(init)
  assert.truthy(block:find(needle, 1, true), needle .. " is not inside the Forever gate")
  local outside = init:sub(1, open - 1) .. init:sub(close + 1)
  assert.is_nil(outside:find(needle, 1, true), needle .. " is registered outside the Forever gate")
end

describe("plan 3e wiring", function()
  local init
  before_each(function() init = read("GoldCap/Core/Init.lua") end)

  it("hands every slash command the text after its word", function()
    assert.truthy(init:find("local cmd, rest = GC.Util.SlashArgs(msg)", 1, true))
    assert.truthy(init:find("local handler = GC.slashHandlers[cmd:lower()]", 1, true))
    assert.truthy(init:find("handler(rest)", 1, true))
  end)

  it("registers Road to 40's level events only inside the Forever gate", function()
    assertGatedEvent(init, 'frame:RegisterEvent("PLAYER_XP_UPDATE")')
    assertGatedEvent(init, 'frame:RegisterEvent("PLAYER_LEVEL_UP")')
  end)

  it("routes money, level, world and logout to Road to 40, and /gc mount only in Forever", function()
    assert.truthy(init:find("GC.ForeverRoad.OnMoney()", 1, true))
    assert.truthy(init:find('event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP"', 1, true))
    assert.truthy(init:find("GC.ForeverRoad.OnEnteringWorld()", 1, true))
    assert.truthy(init:find("GC.ForeverRoad.OnLogout()", 1, true))
    assert.truthy(foreverSlashBlock(init):find(
      "GC.slashHandlers.mount = function(rest) GC.ForeverRoad.Slash(rest) end", 1, true))
    assert.equal(1, select(2, init:gsub("slashHandlers%.mount =", "")))
  end)

  it("gives /gc weights only in Forever, and queues the upgrades update after the bag line of a finished scan", function()
    assert.truthy(foreverSlashBlock(init):find(
      "GC.slashHandlers.weights = function(rest) GC.ForeverUpgrades.SlashWeights(rest) end", 1, true))
    assert.equal(1, select(2, init:gsub("slashHandlers%.weights =", "")))
    local scan = read("GoldCap/Core/ForeverScan.lua")
    local bags = assert(scan:find("GC.ForeverValue.PrintBags()", 1, true))
    assert.truthy(scan:find("GC.ForeverScan._QueueUpgradesUpdate()", bags, true))
  end)

  it("opens the upgrades window only in Forever, and repaints it on item data and a finished scan", function()
    assert.truthy(foreverSlashBlock(init):find(
      "GC.slashHandlers.upgrades = function() GC.ForeverUpgradesUI.Toggle() end", 1, true))
    assert.equal(1, select(2, init:gsub("slashHandlers%.upgrades =", "")))
    local info = assert(init:find('event == "GET_ITEM_INFO_RECEIVED"', 1, true))
    assert.truthy(init:find("GC.ForeverUpgradesUI.OnItemInfo(itemID)", info, true))
    -- The queued update (deferred with C_Timer.After, see the test below) is what repaints an open
    -- window after a finished scan now, sharing the one Build its chat count also uses -- not a
    -- second, independent RefreshIfShown() call.
    local scan = read("GoldCap/Core/ForeverScan.lua")
    local queue = assert(scan:find("function GC.ForeverScan._QueueUpgradesUpdate()", 1, true))
    assert.truthy(scan:find("UI.Render(r, time())", queue, true))
  end)

  it("registers the loot and spell events only inside the Forever gate", function()
    assertGatedEvent(init, 'frame:RegisterEvent("LOOT_READY")')
    assertGatedEvent(init, 'frame:RegisterEvent("LOOT_OPENED")')
    assertGatedEvent(init, 'frame:RegisterEvent("LOOT_CLOSED")')
    assertGatedEvent(init, 'frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")')
  end)

  it("routes loot, the player's spells and the first world entry to the recorder, and /gc loot only in Forever", function()
    assert.truthy(init:find('event == "LOOT_READY" or event == "LOOT_OPENED"', 1, true))
    assert.truthy(init:find("GC.ForeverLoot.OnLootReady()", 1, true))
    assert.truthy(init:find('event == "LOOT_CLOSED"', 1, true))
    assert.truthy(init:find("GC.ForeverLoot.OnLootClosed()", 1, true))
    assert.truthy(init:find("GC.ForeverLoot.OnSpellSucceeded(spellID)", 1, true))
    assert.truthy(init:find("GC.ForeverLoot.MaybeIntro()", 1, true))
    assert.truthy(foreverSlashBlock(init):find(
      "GC.slashHandlers.loot = function(rest) GC.ForeverLoot.Slash(rest) end", 1, true))
    assert.equal(1, select(2, init:gsub("slashHandlers%.loot =", "")))
  end)
end)
