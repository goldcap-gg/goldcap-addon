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

describe("plan 3e wiring", function()
  local init
  before_each(function() init = read("GoldCap/Core/Init.lua") end)

  it("hands every slash command the text after its word", function()
    assert.truthy(init:find("local cmd, rest = GC.Util.SlashArgs(msg)", 1, true))
    assert.truthy(init:find("local handler = GC.slashHandlers[cmd:lower()]", 1, true))
    assert.truthy(init:find("handler(rest)", 1, true))
  end)

  -- Later tasks (7, 9, 10, 12) append their `it(...)` blocks here, inside this describe. Task 7
  -- adds the gate helpers above it (added there, not here: luacheck fails an unused local).
end)
