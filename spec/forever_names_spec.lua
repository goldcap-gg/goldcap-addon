local helper = require("spec.spec_helper")

describe("ForeverNames", function()
  local GC, N, saved
  before_each(function()
    saved = { CreateFrame = _G.CreateFrame }
    _G.CreateFrame = nil -- the pure walk only
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ForeverNames.lua", GC)
    N = GC.ForeverNames
  end)
  after_each(function() _G.CreateFrame = saved.CreateFrame end)

  it("keeps a table of names per client language", function()
    local root = {}
    assert.is_nil(N.Store(root, "enUS"))
    local s = N.Store(root, "enUS", true)
    s.names[3] = "Thing"
    assert.equal(s, N.Store(root, "enUS", true))
    assert.same({}, N.Store(root, "deDE", true).names)
    assert.is_nil(N.Store(root, nil, true))
  end)

  it("hands every kept name to the BUY box", function()
    GC.db = { foreverNames = { v = 1, locale = "enUS", names = { [4604] = "Forest Mushroom Cap" } } }
    local got = {}
    N.Each(function(id, name) got[id] = name end)
    assert.same({ [4604] = "Forest Mushroom Cap" }, got)
    GC.db = {}
    N.Each(function() error("nothing kept") end)
  end)

  -- The client names an id only once it has loaded it, and asking is what loads it.
  it("asks a window a step, reads it again a step later, and writes down what answered", function()
    local ids, loaded, names, calls, never = {}, {}, {}, 0, 0
    for id = 1, 450 do ids[id] = true end
    loaded[7] = "Seven"
    local walk = N.New({
      ids = function() return ids end,
      names = function() return names end,
      nameOf = function(id)
        calls = calls + 1
        if id == 13 then never = never + 1 end
        local name = loaded[id]
        if id ~= 13 then loaded[id] = "Item " .. id end -- the ask loads it for the next read
        return name
      end,
    })
    walk:Tick(100)
    assert.is_true(calls <= N.C.WINDOW)
    assert.equal(0, walk:Tick(101)) -- not due
    local total = 0
    for now = 102, 110, 2 do total = total + walk:Tick(now) end
    local count = 0
    for _ in pairs(names) do count = count + 1 end
    assert.equal(449, count)
    assert.is_nil(names[13])
    assert.equal(448, total) -- the one loaded beforehand came with the first step's own ask
    -- The one the client never names is let be after three failed second reads.
    for now = 200, 600, 2 do walk:Tick(now) end
    assert.equal(2 * N.C.TRIES, never)
    local after = calls
    for now = 700, 900, 2 do walk:Tick(now) end
    assert.equal(after, calls)
  end)

  it("writes nothing while there is no table to write to, and picks up a new scan's ids", function()
    local ids, names = { [1] = true }, nil
    local walk = N.New({ ids = function() return ids end, names = function() return names end,
      nameOf = function(id) return "Item " .. id end })
    assert.equal(0, walk:Tick(10))
    names = {}
    assert.equal(1, walk:Tick(12))
    ids[2] = true
    assert.equal(0, walk:Tick(14))
    assert.equal(1, walk:Tick(100))
    assert.same({ "Item 1", "Item 2" }, names)
  end)
end)
