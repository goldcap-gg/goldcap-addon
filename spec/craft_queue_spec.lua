local helper = require("spec.spec_helper")

-- Core/CraftQueue.lua: the per-character craft queue in GC.db.craft and its arithmetic -- crafts
-- left, what is held and listed, what the queue needs and is missing, and the BUY lines that buy
-- exactly that.
describe("craft queue", function()
  local GC, Q

  local function recipe(id, slots, outputs, per)
    return { recipeID = id, name = "Recipe " .. id, per = per or 1, output = (outputs or { 900 })[1],
      outputs = outputs or { 900 }, slots = slots or { { slotIndex = 1, q = 2, ids = { 101, 102, 103 } } } }
  end

  local function counts(t) return function(id) return t[id] or 0 end end
  local function unit(t) return function(id) return t[id] end end

  before_each(function()
    GC = helper.loadModule("Core/CraftMath.lua")
    helper.loadModule("Core/CraftQueue.lua", GC)
    GC.db = {}
    Q = GC.CraftQueue
  end)

  it("creates the craft store on the first write, one per character", function()
    assert.same({}, Q.Entries("A-R"))
    assert.is_nil(GC.db.craft)
    Q.Add("A-R", recipe(1), 2)
    assert.equal(1, GC.db.craft.v)
    assert.same({}, Q.Entries("B-R"))
    assert.equal(1, #Q.Entries("A-R"))
  end)

  it("leaves a store a newer GoldCap wrote untouched", function()
    GC.db.craft = { v = 2, chars = {} }
    assert.is_nil(Q.Add("A-R", recipe(1), 2))
    assert.is_nil(Q.Restock("A-R", recipe(1), 5))
    Q.FoldListed("A-R", { { itemKey = { itemID = 900 }, quantity = 1, status = 0 } }, 100)
    assert.same({ v = 2, chars = {} }, GC.db.craft)
    assert.is_false(Q.Writable())
  end)

  it("is writable when no store exists yet or it is this version's", function()
    assert.is_true(Q.Writable())
    Q.Add("A-R", recipe(1), 1)
    assert.is_true(Q.Writable())
  end)

  it("adds crafts to a recipe already counted", function()
    Q.Add("A-R", recipe(1), 3)
    Q.Add("A-R", recipe(1), 2)
    local entries = Q.Entries("A-R")
    assert.equal(1, #entries)
    assert.equal(5, entries[1].count)
  end)

  it("keeps the newest snapshot of a recipe it already holds", function()
    Q.Add("A-R", recipe(1), 1)
    local fresh = recipe(1, nil, { 900, 901 })
    Q.Add("A-R", fresh, 1)
    assert.same({ 900, 901 }, Q.Entries("A-R")[1].recipe.outputs)
  end)

  it("refuses a count that is not a whole number above zero", function()
    assert.is_nil(Q.Add("A-R", recipe(1), 0))
    assert.is_nil(Q.Add("A-R", recipe(1), 1.5))
    assert.is_nil(GC.db.craft)
  end)

  it("turns a restock into a count when crafts are added, and a count into a restock", function()
    Q.Restock("A-R", recipe(1), 20)
    Q.Add("A-R", recipe(1), 3)
    local e = Q.Entries("A-R")[1]
    assert.equal(3, e.count)
    assert.is_nil(e.restock)
    Q.Restock("A-R", recipe(1), 10)
    e = Q.Entries("A-R")[1]
    assert.equal(10, e.restock)
    assert.is_nil(e.count)
    assert.equal(1, #Q.Entries("A-R"))
  end)

  it("keeps a recipe's place in the queue when its kind changes", function()
    Q.Add("A-R", recipe(1), 1)
    Q.Add("A-R", recipe(2), 1)
    Q.Restock("A-R", recipe(1), 5)
    local entries = Q.Entries("A-R")
    assert.same({ 1, 2 }, { entries[1].recipe.recipeID, entries[2].recipe.recipeID })
  end)

  it("takes the recipe off at restock 0", function()
    Q.Restock("A-R", recipe(1), 5)
    Q.Restock("A-R", recipe(1), 0)
    assert.same({}, Q.Entries("A-R"))
  end)

  it("takes a recipe off the queue", function()
    Q.Add("A-R", recipe(1), 1)
    Q.Add("A-R", recipe(2), 1)
    Q.Remove("A-R", 1)
    local entries = Q.Entries("A-R")
    assert.equal(1, #entries)
    assert.equal(2, entries[1].recipe.recipeID)
  end)

  it("counts what is held in every quality plus what is listed", function()
    local e = { recipe = recipe(1, nil, { 900, 901 }), restock = 10 }
    assert.equal(9, Q.Held(e, counts({ [900] = 3, [901] = 2 }), { [900] = 4 }))
    assert.equal(5, Q.Held(e, counts({ [900] = 3, [901] = 2 }), nil))
  end)

  it("crafts a restock up to its target in whole crafts", function()
    local e = { recipe = recipe(1, nil, nil, 2), restock = 20 }
    assert.equal(7, Q.CraftsNeeded(e, 7))
    assert.equal(0, Q.CraftsNeeded(e, 25))
    assert.equal(4, Q.CraftsNeeded({ recipe = recipe(1), count = 4 }, 100))
  end)

  it("sums what several recipes need of the same reagent", function()
    local a = { recipe = recipe(1, { { slotIndex = 1, q = 2, ids = { 101, 102, 103 } } }), count = 2 }
    local b = { recipe = recipe(2, { { slotIndex = 3, q = 3, ids = { 101, 102, 103 } } }), count = 1 }
    local c = { recipe = recipe(3, { { slotIndex = 1, q = 9, ids = { 201 } } }), restock = 1 }
    local crafts = { [a] = 2, [b] = 1, [c] = 0 }
    local needs = Q.Needs({ a, b, c }, function(e) return crafts[e] end)
    assert.same({ { ids = { 101, 102, 103 }, q = 7 } }, needs)
  end)

  it("keeps a currency reagent as its own need", function()
    local a = { recipe = recipe(1, { { slotIndex = 1, q = 1, ids = { 101 } }, { slotIndex = 2, q = 5, currency = 3008 } }), count = 2 }
    assert.same({ { ids = { 101 }, q = 2 }, { currency = 3008, q = 10 } }, Q.Needs({ a }, function() return 2 end))
  end)

  it("counts every quality of a reagent as held", function()
    local rows = Q.Missing({ { ids = { 101, 102, 103 }, q = 10 } }, counts({ [101] = 3, [102] = 2 }))
    assert.same({ { ids = { 101, 102, 103 }, need = 10, have = 5, missing = 5 } }, rows)
    assert.same({}, Q.Missing({ { ids = { 101, 102, 103 }, q = 4 } }, counts({ [103] = 5 })))
  end)

  it("counts what the player holds of a currency reagent, and misses only the shortfall", function()
    local needs = { { currency = 3008, q = 10 } }
    assert.same({}, Q.Missing(needs, counts({}), counts({ [3008] = 10 })))
    assert.same({}, Q.Missing(needs, counts({}), counts({ [3008] = 25 })))
    assert.same({ { currency = 3008, need = 10, have = 4, missing = 6 } }, Q.Missing(needs, counts({}), counts({ [3008] = 4 })))
    -- No way to count it: held as none.
    assert.same({ { currency = 3008, need = 10, have = 0, missing = 10 } }, Q.Missing(needs, counts({})))
  end)

  it("BuyLines adds back what is held of the bought quality", function()
    local missing = { { ids = { 101, 102, 103 }, need = 6, have = 1, missing = 5 } }
    local prices = unit({ [101] = 500, [102] = 450, [103] = 400 })
    assert.same({ { i = 103, q = 6 } }, (Q.BuyLines(missing, prices, counts({ [103] = 1 }))))
    assert.same({ { i = 103, q = 5 } }, (Q.BuyLines(missing, prices, counts({ [101] = 3 }))))
  end)

  it("marks a reagent a vendor sells as a vendor stop with the vendor's price", function()
    local missing = { { ids = { 101, 102 }, need = 4, have = 0, missing = 4 }, { ids = { 201 }, need = 2, have = 0, missing = 2 } }
    local prices = unit({ [101] = 50, [102] = 900, [201] = 300 })
    local vendor = function(id) return id == 101 and 50 or nil end
    assert.same({ { i = 101, q = 4, v = true, vu = 50 }, { i = 201, q = 2 } },
      (Q.BuyLines(missing, prices, counts({}), vendor)))
  end)

  it("buys the lowest quality when no quality has a price, and leaves a currency out", function()
    local missing = { { ids = { 101, 102 }, need = 4, have = 0, missing = 4 }, { currency = 3008, need = 2, have = 0, missing = 2 } }
    local lines, notBuyable = Q.BuyLines(missing, unit({}), counts({}))
    assert.same({ { i = 101, q = 4 } }, lines)
    assert.same({ { currency = 3008 } }, notBuyable)
  end)

  it("FoldListed counts live auctions and never sold ones", function()
    Q.FoldListed("A-R", {
      { itemKey = { itemID = 900 }, quantity = 4, status = 0 },
      { itemKey = { itemID = 900 }, quantity = 2, status = 1 },
    }, 1234)
    local listed, at = Q.Listed("A-R")
    assert.equal(4, listed[900])
    assert.equal(1234, at)
    Q.FoldListed("A-R", {}, 1300)
    listed, at = Q.Listed("A-R")
    assert.same({}, listed)
    assert.equal(1300, at)
  end)

  it("takes a read older than the longest auction, 48 hours, as no read", function()
    -- What sold and was collected since cannot be told from it.
    Q.FoldListed("A-R", { { itemKey = { itemID = 900 }, quantity = 4, status = 0 } }, 1000)
    local listed, at = Q.Listed("A-R", 1000 + 48 * 3600)
    assert.same({ [900] = 4 }, listed)
    assert.equal(1000, at)
    listed, at = Q.Listed("A-R", 1000 + 48 * 3600 + 1)
    assert.same({}, listed)
    assert.is_nil(at)
  end)

  it("knows nothing listed before the auction house was seen", function()
    local listed, at = Q.Listed("A-R")
    assert.same({}, listed)
    assert.is_nil(at)
    assert.is_nil(GC.db.craft)
  end)

  it("a finished craft takes one off a counted recipe", function()
    Q.Add("A-R", recipe(1), 2)
    Q.Restock("A-R", recipe(2), 5)
    assert.is_true(Q.OnCraftSucceeded("A-R", 1))
    assert.equal(1, Q.Entries("A-R")[1].count)
    assert.is_true(Q.OnCraftSucceeded("A-R", 1))
    local entries = Q.Entries("A-R")
    assert.equal(1, #entries)
    assert.equal(2, entries[1].recipe.recipeID)
    assert.is_false(Q.OnCraftSucceeded("A-R", 2))
    assert.is_false(Q.OnCraftSucceeded("A-R", 99))
    assert.is_false(Q.OnCraftSucceeded("Other-R", 2))
    assert.same(5, Q.Entries("A-R")[1].restock)
  end)

  it("reads a count the player typed", function()
    assert.equal(12, Q.ParseCount("12"))
    assert.equal(3, Q.ParseCount(" 3 "))
    assert.is_nil(Q.ParseCount("0"))
    assert.equal(0, Q.ParseCount("0", true))
    assert.is_nil(Q.ParseCount("2.5"))
    assert.is_nil(Q.ParseCount("abc"))
    assert.is_nil(Q.ParseCount("10000"))
    assert.equal(9999, Q.ParseCount("9999"))
    assert.is_nil(Q.ParseCount(nil))
  end)
end)
