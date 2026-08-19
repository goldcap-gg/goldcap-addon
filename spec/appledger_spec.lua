local helper = require("spec.spec_helper")

describe("AppLedger.Adopt", function()
  local GC

  local function fixture()
    return {
      v = 1, generatedAt = 1787130262, pro = true, days = 30,
      totals = { proceeds = 100, spent = 50, pending = 7, salesCount = 2,
                 realized = 25, medianHold = 3600 },
      sales = {
        { name = "Umbral Tin Ore", item = 190396, qty = 2, total = 100, cut = 5,
          pending = false, at = 86400,
          basis = { matched = 2, unmatched = 0, cost = 50, profit = 45 } },
        { name = "It's odd", qty = 1, total = 10, cut = 0, pending = true, at = 10 },
      },
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/AppLedger.lua", GC)
  end)

  after_each(function()
    _G.GoldCap_AppLedger = nil
  end)

  it("returns nil before anything is adopted", function()
    assert.is_nil(GC.AppLedger.GetSummary())
  end)

  it("adopts a valid summary and exposes a whitelist copy", function()
    _G.GoldCap_AppLedger = fixture()
    GC.AppLedger.Adopt()
    local s = GC.AppLedger.GetSummary()
    assert.equal(1787130262, s.generatedAt)
    assert.is_true(s.pro)
    assert.equal(30, s.days)
    assert.equal(25, s.totals.realized)
    assert.equal(2, #s.sales)
    assert.equal(45, s.sales[1].basis.profit)
    -- Whitelist copy, not the raw global: mutating the global later must
    -- not reach into the adopted summary.
    _G.GoldCap_AppLedger.sales[1].total = 999
    assert.equal(100, GC.AppLedger.GetSummary().sales[1].total)
  end)

  it("refuses any version but 1, silently", function()
    local f = fixture(); f.v = 2
    _G.GoldCap_AppLedger = f
    assert.has_no.errors(function() GC.AppLedger.Adopt() end)
    assert.is_nil(GC.AppLedger.GetSummary())
  end)

  it("refuses a malshaped global, silently", function()
    for _, bad in ipairs({ "oops", 42,
        { v = 1, generatedAt = "later", totals = {}, sales = {} },
        { v = 1, generatedAt = 1, totals = "no", sales = {} },
        { v = 1, generatedAt = 1, totals = {}, sales = "no" } }) do
      _G.GoldCap_AppLedger = bad
      assert.has_no.errors(function() GC.AppLedger.Adopt() end)
      assert.is_nil(GC.AppLedger.GetSummary())
    end
  end)

  it("drops a malformed sale row and keeps the valid ones", function()
    local f = fixture()
    table.insert(f.sales, 2, { name = 42, qty = 1, total = 1, cut = 0, pending = false, at = 1 })
    table.insert(f.sales, { name = "no timestamp", qty = 1, total = 1, cut = 0, pending = false })
    _G.GoldCap_AppLedger = f
    GC.AppLedger.Adopt()
    assert.equal(2, #GC.AppLedger.GetSummary().sales)
  end)

  it("adopts a valid summary whose totals omit realized/medianHold as nil, never 0", function()
    -- The free tier never sends these keys at all (companion's
    -- render_ledger_summary_lua omits them, never zeros). Adopt must not
    -- turn their absence into a fake 0 -- num() already returns nil for a
    -- missing field, but nothing pinned that until now.
    local f = fixture()
    f.totals.realized = nil
    f.totals.medianHold = nil
    _G.GoldCap_AppLedger = f
    GC.AppLedger.Adopt()
    local totals = GC.AppLedger.GetSummary().totals
    assert.is_nil(totals.realized)
    assert.is_nil(totals.medianHold)
  end)

  it("drops a malformed basis but keeps its row", function()
    local f = fixture()
    f.sales[1].basis = { matched = "two", unmatched = 0, cost = 50, profit = 45 }
    _G.GoldCap_AppLedger = f
    GC.AppLedger.Adopt()
    local s = GC.AppLedger.GetSummary()
    assert.equal(2, #s.sales)
    assert.is_nil(s.sales[1].basis)
  end)
end)
