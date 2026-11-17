local helper = require("spec.spec_helper")

describe("ForeverDisenchant", function()
  local GC, D
  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    GC.L = setmetatable({}, { __index = function(_, k) return k end })
    helper.loadModule("Core/ForeverDisenchant.lua", GC)
    D = GC.ForeverDisenchant
  end)

  -- A slip in copying a row shows here: the chances of every row make 100, and the rows follow one
  -- another with no gap and no overlap.
  it("has rows that follow one another, each with chances that make 100", function()
    for _, rows in ipairs({ D.UNCOMMON, D.RARE, D.EPIC }) do
      for i, row in ipairs(rows) do
        assert.is_true(row[1] <= row[2])
        if i > 1 then assert.equal(rows[i - 1][2] + 1, row[1]) end
      end
    end
    for _, row in ipairs(D.UNCOMMON) do
      for _, chance in ipairs({ row[10], row[11] }) do
        assert.equal(100, chance[1] + chance[2] + chance[3])
        assert.equal(row[9] == nil, chance[3] == 0)
      end
    end
    for _, rows in ipairs({ D.RARE, D.EPIC }) do
      for _, row in ipairs(rows) do
        local sum = 0
        for i = 3, #row do sum = sum + row[i][4] end
        assert.equal(100, sum)
      end
    end
  end)

  it("gives a green weapon of level 16 to 20 mostly essence, and armor mostly dust", function()
    assert.same({
      { itemID = 10939, min = 1, max = 2, chance = 75 },
      { itemID = 10940, min = 2, max = 3, chance = 20 },
      { itemID = 10978, min = 1, max = 1, chance = 5 },
    }, D.Results(2, 18, true))
    local armor = D.Results(2, 18, false)
    assert.equal(10940, armor[1].itemID)
    assert.equal(75, armor[1].chance)
    assert.equal(2, #D.Results(2, 10, false)) -- no shard under level 16
  end)

  it("gives rare and epic gear shards and crystals", function()
    assert.same({ { itemID = 10978, min = 1, max = 1, chance = 100 } }, D.Results(3, 20, true))
    assert.equal(2, #D.Results(3, 60, false))
    assert.same({ { itemID = 11177, min = 2, max = 4, chance = 100 } }, D.Results(4, 42, false))
  end)

  it("says nothing where the table has no row", function()
    assert.is_nil(D.Results(2, 4, false))
    assert.is_nil(D.Results(2, 5, true))
    assert.is_nil(D.Results(2, 90, false))
    assert.is_nil(D.Results(4, 30, false))
    assert.is_nil(D.Results(1, 20, false))
    assert.is_nil(D.Results(2, nil, false))
  end)

  it("knows what is disenchanted at all", function()
    assert.is_true(D.Can(3021, 2, 2, "INVTYPE_RANGED"))
    assert.is_false(D.Can(3021, 1, 2, "INVTYPE_RANGED")) -- white
    assert.is_false(D.Can(2589, 2, 7, ""))               -- not gear
    assert.is_false(D.Can(4334, 2, 4, "INVTYPE_BODY"))   -- a shirt
    assert.is_false(D.Can(11287, 2, 2, "INVTYPE_RANGEDRIGHT")) -- an enchanter's wand
    assert.is_false(D.Can(1, 5, 4, "INVTYPE_CHEST"))
  end)

  it("values a cast at chance x mean count x price, over what has a price", function()
    local price = { [10939] = 440, [10940] = 88, [10978] = 420 }
    local results = D.Results(2, 18, true)
    -- 440 x 1.5 x 0.75 + 88 x 2.5 x 0.20 + 420 x 1 x 0.05 = 495 + 44 + 21
    assert.same({ 560, false }, { D.Value(results, function(id) return price[id] end) })
    price[10978] = nil
    assert.same({ 539, true }, { D.Value(D.Results(2, 18, true), function(id) return price[id] end) })
    assert.same({ nil, true }, { D.Value(D.Results(2, 18, true), function() return nil end) })
  end)

  it("writes the tooltip's lines: the worth, then a material a line", function()
    local price = { [10939] = 440, [10940] = 88 }
    local driver = {
      priceOf = function(id) return price[id] end,
      nameOf = function(id) return ({ [10939] = "Greater Magic Essence", [10940] = "Strange Dust" })[id] end,
      iconOf = function(id) return id == 10940 and 132858 or nil end,
      coin = function(c) return c .. "c" end,
    }
    assert.same({
      { kind = "text", left = "Disenchant", right = "~539c" },
      { kind = "text", left = "  Greater Magic Essence ×1-2 · 440c", right = "75%" },
      { kind = "text", left = "  |T132858:0|t Strange Dust ×2-3 · 88c", right = "20%" },
      { kind = "text", left = "  #10978 ×1 · no price yet", right = "5%" },
    }, D.Lines({ itemID = 3021, quality = 2, itemLevel = 18, classID = 2, equipLoc = "INVTYPE_RANGED" }, driver))
    local item = { itemID = 3021, quality = 2, itemLevel = 18, classID = 2, equipLoc = "INVTYPE_RANGED" }
    -- Settings > TOOLTIP: the value alone, or nothing.
    assert.same({ { kind = "text", left = "Disenchant", right = "~539c" } }, D.Lines(item, driver, { mats = false }))
    assert.is_nil(D.Lines(item, driver, { value = false }))
    assert.equal(4, #D.Lines(item, driver, {}))
    assert.equal("99.5%", D.Lines({ itemID = 1, quality = 3, itemLevel = 60, classID = 4,
      equipLoc = "INVTYPE_CHEST" }, driver)[2].right)
    assert.is_nil(D.Lines({ itemID = 2589, quality = 1, itemLevel = 5, classID = 7, equipLoc = "" }, driver))
    assert.is_nil(D.Lines({ itemID = 1, quality = 2, itemLevel = 90, classID = 4, equipLoc = "INVTYPE_CHEST" }, driver))
  end)
end)
