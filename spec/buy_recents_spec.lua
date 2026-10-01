local helper = require("spec.spec_helper")

-- Core/BuyRecents.lua: the item box's recent searches and items, newest first, each once, capped.
describe("BuyRecents", function()
  local R

  before_each(function()
    local GC = helper.loadModule("Core/NameMatch.lua")
    R = helper.loadModule("Core/BuyRecents.lua", GC).BuyRecents
  end)

  local function keys(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.i and ("i" .. e.i) or ("s:" .. e.s) end
    return out
  end

  local cases = {
    { "puts the newest first", { { i = 1 }, { s = "silk" } }, { i = 2 }, nil, { "i2", "i1", "s:silk" } },
    { "starts a list from nothing", nil, { s = "линен" }, nil, { "s:линен" } },
    { "moves an item added again to the front, once", { { i = 1 }, { i = 2 }, { i = 3 } }, { i = 3 }, nil,
      { "i3", "i1", "i2" } },
    { "takes a search typed again in other case and spacing as the same one",
      { { s = "Linen" }, { i = 4 } }, { s = " LINEN " }, nil, { "s: LINEN ", "i4" } },
    { "folds Russian case for a search", { { s = "Льняная" } }, { s = "льняная" }, nil, { "s:льняная" } },
    { "keeps an item and a search of the same words apart", { { i = 2589 } }, { s = "2589" }, nil,
      { "s:2589", "i2589" } },
    { "cuts to max", { { i = 1 }, { i = 2 }, { i = 3 } }, { i = 4 }, 3, { "i4", "i1", "i2" } },
    { "ignores an empty search", { { i = 1 } }, { s = "   " }, nil, { "i1" } },
    { "drops what is neither an item nor a search", { { i = 1 }, { foo = 1 }, "x", { i = -2 } }, { i = 5 }, nil,
      { "i5", "i1" } },
  }
  for _, case in ipairs(cases) do
    it(case[1], function() assert.same(case[5], keys(R.Push(case[2], case[3], case[4]))) end)
  end

  it("keeps ten by default", function()
    local list
    for i = 1, 14 do list = R.Push(list, { i = i }) end
    assert.equal(10, #list)
    assert.equal(14, list[1].i)
    assert.equal(5, list[10].i)
  end)

  it("keeps what an item entry carries: its count and the name the client gave it", function()
    local list = R.Push({}, { i = 2589, q = 20, n = "Linen Cloth" })
    assert.same({ { i = 2589, q = 20, n = "Linen Cloth" } }, list)
  end)
end)
