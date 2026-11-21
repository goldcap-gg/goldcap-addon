local helper = require("spec.spec_helper")

-- Core/SoldReceipt.lua: the Sold tab's receipt rules, apart from the frames. SaveCost runs
-- against the real Core/Acquisitions.lua, so "the profit appears" is the store's own answer.
describe("SoldReceipt", function()
  local R

  before_each(function()
    R = helper.loadModule("Core/SoldReceipt.lua").SoldReceipt
  end)

  describe("the vs-market dot", function()
    local cases = {
      { pct = 0, want = 0.5, tone = "at" },
      { pct = 25, want = 0.75, tone = "above" },
      { pct = -25, want = 0.25, tone = "under" },
      { pct = 50, want = 1, tone = "above" },
      { pct = 300, want = 1, tone = "above" },      -- clamped: the figure says the rest
      { pct = -100, want = 0, tone = "under" },
    }
    for _, case in ipairs(cases) do
      it(("sits at %s for %d%%"):format(case.want, case.pct), function()
        assert.equal(case.want, R.BarPosition(case.pct))
        assert.equal(case.tone, R.Tone(case.pct))
      end)
    end
    it("has no place without a percent", function() assert.is_nil(R.BarPosition(nil)) end)
  end)

  describe("the market a sale is compared with", function()
    local cases = {
      { name = "an item priced as one thing", value = { mv = 70 }, want = 70 },
      { name = "a realm item's one-version figure", value = { mv = 900, kind = "realm_item" }, want = nil },
      { name = "a gear piece's cheapest version", value = { mv = 900, gear = true }, want = nil },
      { name = "no price", value = { mv = 0 }, want = nil },
      { name = "nothing", value = nil, want = nil },
    }
    for _, case in ipairs(cases) do
      it(case.name, function() assert.equal(case.want, R.Market(case.value)) end)
    end
  end)

  describe("which receipt columns show", function()
    local cases = {
      { name = "a costed sale with a market: receipt and market, nothing to finish",
        row = { profit = 10 }, opts = { market = 70 },
        want = { market = true, finish = false } },
      { name = "no exact market: the market column is left out",
        row = { profit = 10 }, opts = {}, want = { market = false, finish = false } },
      { name = "a sale it can finish: the cost box",
        row = {}, opts = { canSave = true }, want = { finish = true, save = true, title = "finish" } },
      { name = "bags still hold the item: the way to SELL, even with a known profit",
        row = { profit = 10 }, opts = { bags = 14 }, want = { finish = true, bags = 14, title = "finish" } },
      { name = "money still in the mail: says so",
        row = { pending = true }, opts = {}, want = { finish = true, note = "pending", title = "profit" } },
      { name = "a free account: the Pro sentence",
        row = { noBasis = true }, opts = {}, want = { finish = true, note = "pro", save = false } },
      { name = "never seen bought and not finishable here: the SELL sentence",
        row = {}, opts = {}, want = { finish = true, note = "unseen" } },
      { name = "a crafted cost with reagents at market: the why lines",
        row = { profit = 10 }, opts = { why = true }, want = { finish = true, title = "profit" } },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        local cols = R.Columns(case.row, case.opts)
        assert.is_true(cols.receipt)
        for key, value in pairs(case.want) do assert.equal(value, cols[key], key) end
      end)
    end
  end)

  describe("the row's PROFIT cell", function()
    local cases = {
      { row = { profit = -3 }, save = false, want = "profit" },
      { row = { noBasis = true }, save = false, want = "blank" },
      { row = {}, save = true, want = "set" },
      { row = { costUnknown = true }, save = false, want = "dash" },
    }
    for i, case in ipairs(cases) do
      it(("case %d -> %s"):format(i, case.want), function() assert.equal(case.want, R.ProfitCell(case.row, case.save)) end)
    end
  end)

  describe("a typed price", function()
    local cases = {
      { "2s 34c", 234 }, { "1g22s90c", 12290 }, { "75c", 75 }, { "1g 0s 62c", 10062 }, { "3", 30000 },
      { "1.5", 15000 }, { "0.0001", 1 }, { "2S", 200 },
      { "", nil }, { "0", nil }, { "abc", nil }, { "1s2", nil }, { "2c 1s", nil }, { "0.00001", nil }, { "-1", nil },
    }
    for _, case in ipairs(cases) do
      it(("%q -> %s"):format(case[1], tostring(case[2])), function() assert.equal(case[2], R.ParseMoney(case[1])) end)
    end
  end)

  it("lights the ring's segments by progress", function()
    assert.equal(0, R.RingLit(0, 16))
    assert.equal(5, R.RingLit(0.3, 16))
    assert.equal(16, R.RingLit(2, 16))
  end)

  describe("saving a cost for a sale", function()
    local GC, context, entry, row

    before_each(function()
      GC = helper.loadModule("Core/Acquisitions.lua")
      helper.loadModule("Core/SoldView.lua", GC)
      helper.loadModule("Core/SoldReceipt.lua", GC)
      R = GC.SoldReceipt
      context = { char = "Me-Realm", region = "eu" }
      GC.Ledger = { Context = function() return context end }
      GC.Acquisitions.Init({})
      -- The character listed it before it sold: how a name-only mail is placed on its item.
      GC.Acquisitions.RecordPost("commodity:2589", 2589, "Linen Cloth", context.char, context.region, 14, 100)
      entry = { key = "sale:1", kind = "sale", source = "mail", itemName = "Linen Cloth", qty = 14,
        total = 1050, cut = 53, at = 200, char = context.char, region = context.region, pending = false }
      -- The sale as the ledger first met it: nothing on the books to place it on.
      assert.equal("unresolved", GC.Acquisitions.ReconcileSale(entry).status)
      row = GC.SoldView.LocalRow(entry, nil, nil, 2589)
    end)

    local function realized()
      for _, r in ipairs(GC.Acquisitions.GetRealized()) do
        if r.evidenceKey == entry.key then return r end
      end
    end

    it("books the sale against what was paid each, and the profit appears", function()
      assert.truthy(R.CostTarget(row, entry, GC.Acquisitions.GetActivities(context), GC.Acquisitions.GetActive(context)))
      assert.is_true(R.SaveCost(GC.Acquisitions, row, entry, 48))
      local hit = assert(realized())
      assert.equal(672, hit.cost)                                   -- 14 x 48c
      local after = GC.SoldView.LocalRow(entry, hit, nil, 2589)
      assert.equal(1050 - 672 - 53, after.profit)
      assert.equal(48, after.paidEach)
      -- Spent whole: nothing is left on the books as stock.
      assert.same({}, GC.Acquisitions.GetActive(context))
      local batches = GC.Acquisitions.GetAll()
      assert.equal(1, #batches)
      assert.equal("manual", batches[1].source)
      -- Once booked, there is nothing left to finish.
      assert.is_false((R.SaveCost(GC.Acquisitions, after, entry, 48)))
    end)

    it("takes the batch back when the sale does not book", function()
      local store = setmetatable({ ReconcileSale = function() return { status = "unresolved", reason = "x" } end },
        { __index = GC.Acquisitions })
      local ok, why = R.SaveCost(store, row, entry, 48)
      assert.is_false(ok)
      assert.equal("x", why)
      assert.same({}, GC.Acquisitions.GetAll())
      assert.is_nil(realized())
    end)

    it("refuses a bad cost, a pending sale, a server row, and two items under one name", function()
      assert.is_false((R.SaveCost(GC.Acquisitions, row, entry, 0)))
      assert.is_false((R.SaveCost(GC.Acquisitions, row, entry, 1.5)))
      local pending = GC.SoldView.LocalRow(entry, nil, nil, 2589)
      pending.pending = true
      assert.is_false((R.SaveCost(GC.Acquisitions, pending, entry, 48)))
      local server = GC.SoldView.ServerRow({ name = "Linen Cloth", qty = 14, total = 1050, at = 200,
        basis = { matched = 0, unmatched = 14, cost = 0, profit = 0 } })
      assert.is_false((R.SaveCost(GC.Acquisitions, server, entry, 48)))
      GC.Acquisitions.RecordPost("commodity:2590", 2590, "Linen Cloth", context.char, context.region, 1, 100)
      local ok, why = R.SaveCost(GC.Acquisitions, row, entry, 48)
      assert.is_false(ok)
      assert.equal("ambiguous_name", why)
      assert.same({}, GC.Acquisitions.GetAll())
    end)

    it("leaves a sale whose position still holds costed stock to SELL", function()
      GC.Acquisitions.Record({ source = "auction_house", itemID = 2589, positionKey = "commodity:2589",
        itemName = "Linen Cloth", quantity = 2, total = 200, acquiredAt = 300, evidenceKey = "tx:later",
        character = context.char, region = context.region })
      local ok, why = R.SaveCost(GC.Acquisitions, row, entry, 48)
      assert.is_false(ok)
      assert.equal("has_stock", why)
      assert.equal(1, #GC.Acquisitions.GetAll())
    end)

    it("refuses a name first listed after the sale", function()
      GC.Acquisitions.Init({})
      GC.Acquisitions.RecordPost("commodity:2589", 2589, "Linen Cloth", context.char, context.region, 14, 900)
      local ok, why = R.SaveCost(GC.Acquisitions, row, entry, 48)
      assert.is_false(ok)
      assert.equal("never_listed", why)
    end)
  end)
end)
