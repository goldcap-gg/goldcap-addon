local helper = require("spec.spec_helper")

describe("QuestReward", function()
  local Q
  before_each(function()
    local GC = helper.loadModule("Core/QuestReward.lua")
    Q = GC.QuestReward
  end)

  describe("Worth", function()
    local cases = {
      { "a priced item, one unit", 1200, 1, 1200 },
      { "a stack of five", 1200, 5, 6000 },
      { "a count the quest leaves out reads as one", 1200, nil, 1200 },
      { "a count of zero reads as one", 1200, 0, 1200 },
      { "no price", nil, 3, nil },
      { "a price of nothing", 0, 3, nil },
      { "a negative price", -5, 1, nil },
      { "not a number", "12g", 1, nil },
      { "NaN", 0 / 0, 1, nil },
    }
    for _, c in ipairs(cases) do
      it(c[1], function()
        assert.equal(c[4], Q.Worth(c[2], c[3]))
      end)
    end
  end)

  describe("Best", function()
    local function choices(...)
      local list = {}
      for i = 1, select("#", ...) do list[i] = { worth = (select(i, ...)) } end
      return list
    end
    local NONE = false -- a choice with no price; `false` so the vararg keeps its place
    local cases = {
      { "the dearest of three", { 500, 1200, 800 }, 2, 1200 },
      { "the dearest is first", { 1200, 500, 800 }, 1, 1200 },
      { "the dearest is last", { 500, 800, 1200 }, 3, 1200 },
      { "a tie goes to the first drawn", { 500, 1200, 1200 }, 2, 1200 },
      { "a tie of all goes to the first", { 700, 700, 700 }, 1, 700 },
      { "choices with no price are passed over", { NONE, 900, NONE, 300 }, 2, 900 },
      { "only one priced: marked when it is worth more than nothing", { NONE, NONE, 1 }, 3, 1 },
      { "only one priced at nothing: no mark", { NONE, 0, NONE }, nil, nil },
      { "nothing priced: no mark", { NONE, NONE }, nil, nil },
      { "one choice is no choice", { 1200 }, nil, nil },
      { "no choices", {}, nil, nil },
      { "a currency choice (no price) beside one priced item", { NONE, 4000 }, 2, 4000 },
    }
    for _, c in ipairs(cases) do
      it(c[1], function()
        local list = choices(unpack(c[2]))
        for _, entry in ipairs(list) do
          if entry.worth == NONE then entry.worth = nil end
        end
        local best, worth = Q.Best(list)
        assert.equal(c[3], best)
        assert.equal(c[4], worth)
      end)
    end

    it("answers nothing for something that is not a list", function()
      assert.is_nil(Q.Best(nil))
      assert.is_nil(Q.Best("choices"))
    end)
  end)
end)
