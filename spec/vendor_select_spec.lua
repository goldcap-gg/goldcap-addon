local helper = require("spec.spec_helper")

describe("VendorSelect", function()
  local GC, S
  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    helper.loadModule("Core/VendorSelect.lua", GC)
    S = GC.VendorSelect
  end)

  local nextID = 1000
  local function stack(over)
    nextID = nextID + 1
    local s = {
      bag = 0, slot = 1, itemID = nextID, link = "item:" .. nextID, count = 1, quality = 0,
      vendorUnit = 10, ahUnit = nil, hasNoValue = false, isLocked = false, isBound = false,
      isGear = false, isReagent = false, refundable = false, tradeTimer = false, inSet = false,
      excludedBag = false, selling = false,
    }
    for k, v in pairs(over or {}) do s[k] = v end
    if over and over.vendorUnit == false then s.vendorUnit = nil end
    if over and over.ahUnit == false then s.ahUnit = nil end
    return s
  end
  local ON = { junk = true, worth = true, kept = {} }

  it("sells a grey stack the vendor buys", function()
    assert.equal("junk", (S.Decide(stack({}), { junk = true })))
  end)

  describe("never sells", function()
    local cases = {
      { "empty", { itemID = false } },
      { "empty", { count = 0 } },
      { "locked", { isLocked = true } },
      { "no_value", { hasNoValue = true } },
      { "no_price", { vendorUnit = false } },
      { "no_price", { vendorUnit = 0 } },
      { "refundable", { refundable = true } },
      { "trade_timer", { tradeTimer = true } },
      { "set", { inSet = true } },
      { "excluded_bag", { excludedBag = true } },
      { "selling", { selling = true } },
      { "bound", { quality = 1, isBound = true } },
      { "reagent", { quality = 1, isReagent = true } },
    }
    for _, c in ipairs(cases) do
      it(c[1] .. " " .. tostring(next(c[2])), function()
        local s = stack(c[2])
        if c[2].itemID == false then s.itemID = nil end
        local rule, why = S.Decide(s, ON)
        assert.is_nil(rule)
        assert.equal(c[1], why)
      end)
    end

    it("kept", function()
      local s = stack({})
      local rule, why = S.Decide(s, { junk = true, worth = true, kept = { [s.itemID] = true } })
      assert.is_nil(rule)
      assert.equal("kept", why)
    end)
  end)

  it("still sells bound junk", function()
    assert.equal("junk", (S.Decide(stack({ isBound = true, quality = 0 }), ON)))
  end)

  it("keeps a grey item the auction house pays more for", function()
    local rule, why = S.Decide(stack({ ahUnit = 100, vendorUnit = 10 }), ON)
    assert.is_nil(rule)
    assert.equal("ah", why)
  end)

  it("draws the verdict boundary after the auction house cut", function()
    local function d(ah)
      return S.Decide(stack({ quality = 1, vendorUnit = 95, ahUnit = ah }), ON)
    end
    assert.equal("vendor", (d(100)))
    assert.equal("vendor", (d(101)))
    local rule, why = d(102)
    assert.is_nil(rule)
    assert.equal("ah", why)
  end)

  it("never sells an item with no auction house price by the vendor rule", function()
    local rule, why = S.Decide(stack({ quality = 1, ahUnit = false }), ON)
    assert.is_nil(rule)
    assert.equal("unpriced", why)
  end)

  it("never sells gear by the vendor rule", function()
    local rule = S.Decide(stack({ quality = 2, isGear = true, ahUnit = 100, vendorUnit = 95 }), ON)
    assert.is_nil(rule)
  end)

  it("honours the toggles", function()
    local _, why = S.Decide(stack({}), { junk = false, worth = true, kept = {} })
    assert.equal("junk_off", why)
    _, why = S.Decide(stack({ quality = 1, vendorUnit = 95, ahUnit = 100 }), { junk = true, worth = false, kept = {} })
    assert.equal("worth_off", why)
    local pick = S.Pick({ stack({}), stack({ quality = 1, vendorUnit = 95, ahUnit = 100 }) }, { junk = false, worth = false })
    assert.same({}, pick.rows)
    assert.equal(0, pick.more)
  end)

  describe("Pick", function()
    it("caps at 12, orders by copper then bag and slot, and counts the rest", function()
      local stacks = {}
      for i = 1, 15 do
        stacks[#stacks + 1] = stack({ bag = 1, slot = i, vendorUnit = (i % 3) + 1, count = 1 })
      end
      stacks[#stacks + 1] = stack({ locked = true, isLocked = true, slot = 99 })
      local pick = S.Pick(stacks, ON)
      assert.equal(12, #pick.rows)
      assert.equal(3, pick.more)
      local sum = 0
      for i, r in ipairs(pick.rows) do
        sum = sum + r.copper
        assert.equal("junk", r.rule)
        local p = pick.rows[i - 1]
        if p then
          assert.is_true(p.copper > r.copper or (p.copper == r.copper and (p.bag < r.bag or (p.bag == r.bag and p.slot < r.slot))))
        end
      end
      assert.equal(sum, pick.total)
    end)

    it("multiplies the unit price by the count", function()
      local pick = S.Pick({ stack({ vendorUnit = 7, count = 5 }) }, ON)
      assert.equal(35, pick.rows[1].copper)
      assert.equal(35, pick.total)
    end)

    it("gives an empty pick for empty input", function()
      assert.same({ rows = {}, total = 0, more = 0 }, S.Pick({}, ON))
    end)
  end)

  describe("PressTotals", function()
    local pick = { rows = { { copper = 30 }, { copper = 20 }, { copper = 5 } }, total = 55, more = 0 }
    it("counts all rows, or only the first when one at a time", function()
      assert.same({ 3, 55 }, { S.PressTotals(pick, false) })
      assert.same({ 1, 30 }, { S.PressTotals(pick, true) })
    end)
    it("is zero for an empty pick", function()
      assert.same({ 0, 0 }, { S.PressTotals({ rows = {}, total = 0, more = 0 }, false) })
    end)
  end)
end)
