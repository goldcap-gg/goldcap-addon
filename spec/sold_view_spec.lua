local helper = require("spec.spec_helper")

-- Core/SoldView.lua: the Sold tab's arithmetic, driven with plain tables. The clock is the
-- spec's own: `dateOf` is os.date("*t", at) in UTC-free local time, exactly what the tab hands
-- it from the client's `date`.
describe("SoldView", function()
  local V
  local function dateOf(at) return os.date("*t", at) end
  -- A local-time instant, so the day arithmetic below is in the same zone dateOf reads.
  local function at(y, m, d, h, mi) return os.time({ year = y, month = m, day = d, hour = h or 12, min = mi or 0 }) end

  before_each(function()
    V = helper.loadModule("Core/SoldView.lua").SoldView
  end)

  describe("Cut", function()
    for _, case in ipairs({
      { name = "the recorded cut", gross = 1000, cut = 37, want = 37, est = false },
      { name = "a recorded zero", gross = 10, cut = 0, want = 0, est = false },
      { name = "5% when none was recorded", gross = 1050, cut = nil, want = 53, est = true },
      { name = "5% of nothing", gross = nil, cut = nil, want = 0, est = true },
    }) do
      it(case.name, function()
        local cut, est = V.Cut(case.gross, case.cut)
        assert.equal(case.want, cut)
        assert.equal(case.est, est)
      end)
    end
  end)

  describe("LocalRow", function()
    it("takes the cut off the realized profit, once, and reads the cost per unit", function()
      local row = V.LocalRow({ key = "k", itemName = "Linen Cloth", qty = 14, total = 1050, cut = 53, at = 5 },
        { profit = 378, cost = 672, quantity = 14, positionKey = "commodity:2589" }, { "goldcap" })
      assert.equal("local", row.section)
      assert.equal(997, row.net)
      assert.equal(75, row.each)
      assert.equal(325, row.profit)            -- 378 gross profit - 53 cut
      assert.equal(672, row.paid)
      assert.equal(48, row.paidEach)
      assert.same({ "goldcap" }, row.sources)
      -- The mail names no item; the position the sale was matched to does, exactly.
      assert.equal(2589, row.itemID)
      assert.is_true(row.itemExact)
    end)

    it("knows no profit without its realized row, and keeps the mail's own item when it has one", function()
      local row = V.LocalRow({ itemName = "Red Dye", itemID = 2604, qty = 10, total = 860, cut = 43, pending = true, at = 5 })
      assert.is_nil(row.profit)
      assert.is_nil(row.paid)
      assert.is_true(row.pending)
      assert.equal(2604, row.itemID)
      assert.is_true(row.itemExact)
      local nameOnly = V.LocalRow({ itemName = "Red Dye", qty = 1, total = 86, cut = 4, at = 5 })
      assert.is_nil(nameOnly.itemID)
      assert.is_false(nameOnly.itemExact)
    end)

    it("takes the item from the character's own listings only when nothing more exact says", function()
      local listed = V.LocalRow({ itemName = "Linen Cloth", qty = 1, total = 70, cut = 3, at = 5 }, nil, nil, 2589)
      assert.equal(2589, listed.itemID)
      assert.is_true(listed.itemExact)
      local matched = V.LocalRow({ itemName = "Linen Cloth", qty = 1, total = 70, cut = 3, at = 5 },
        { profit = 10, positionKey = "commodity:2590" }, nil, 2589)
      assert.equal(2590, matched.itemID)
    end)
  end)

  describe("ListedItemID", function()
    local index = V.ListedIndex({
      { itemName = "Linen Cloth", itemID = 2589, character = "Me-Realm", region = "us" },
      { itemName = "Linen Cloth", itemID = 2589, character = "Me-Realm", region = "us" },
      { itemName = "Silverleaf", itemID = 765, character = "Alt-Realm", region = "us" },
      { itemName = "Hochenblume", itemID = 191460, character = "Me-Realm", region = "us" },
      { itemName = "Hochenblume", itemID = 191461, character = "Me-Realm", region = "us" },
    })
    it("answers the one item this character listed in this region under the name", function()
      assert.equal(2589, V.ListedItemID(index, "Linen Cloth", "Me-Realm", "us"))
    end)
    it("answers nothing for another character, another region, two items under one name, or no name", function()
      assert.is_nil(V.ListedItemID(index, "Silverleaf", "Me-Realm", "us"))
      assert.is_nil(V.ListedItemID(index, "Linen Cloth", "Me-Realm", "eu"))
      assert.is_nil(V.ListedItemID(index, "Hochenblume", "Me-Realm", "us"))
      assert.is_nil(V.ListedItemID(index, nil, "Me-Realm", "us"))
      assert.is_nil(V.ListedItemID(nil, "Linen Cloth", "Me-Realm", "us"))
      assert.is_nil(V.ListedItemID(V.ListedIndex(nil), "Linen Cloth", "Me-Realm", "us"))
    end)
  end)

  describe("ServerRow", function()
    for _, case in ipairs({
      { name = "full basis", basis = { matched = 2, unmatched = 0, cost = 50, profit = 45 },
        profit = 45, paidEach = 25 },
      { name = "partial basis: profit and cost over the matched units only",
        basis = { matched = 1, unmatched = 3, cost = 10, profit = 12 }, profit = 12, paidEach = 10, costUnits = 1 },
      { name = "no unit matched", basis = { matched = 0, unmatched = 1, cost = 0, profit = 0 }, costUnknown = true },
      { name = "free account: no basis at all", basis = nil, noBasis = true },
    }) do
      it(case.name, function()
        local row = V.ServerRow({ name = "Ore", item = 5, qty = 2, total = 100, cut = 5, at = 9, basis = case.basis })
        assert.equal("server", row.section)
        assert.equal(95, row.net)
        assert.equal(case.profit, row.profit)
        assert.equal(case.paidEach, row.paidEach)
        assert.equal(case.costUnits, row.costUnits)
        assert.equal(case.costUnknown, row.costUnknown)
        assert.equal(case.noBasis, row.noBasis)
      end)
    end
  end)

  describe("the local/server boundary", function()
    it("is the newest sale the snapshot holds, not its generatedAt", function()
      assert.equal(900, V.Boundary({ generatedAt = 1000, sales = { { at = 900 }, { at = 800 } } }))
      assert.equal(0, V.Boundary(nil))
      assert.equal(0, V.Boundary({ sales = {} }))
    end)

    it("keeps local only the sales newer than it, newest first", function()
      local sales = V.LocalSales({
        { kind = "sale", at = 900, itemName = "covered" },
        { kind = "sale", at = 950, itemName = "gap" },
        { kind = "buy", at = 990, itemName = "a buy" },
        { kind = "sale", at = 1500, itemName = "new" },
      }, 900)
      assert.equal(2, #sales)
      assert.equal("new", sales[1].itemName)
      assert.equal("gap", sales[2].itemName)
    end)
  end)

  describe("search", function()
    for _, case in ipairs({
      { name = "Linen Cloth", query = "linen", want = true },
      { name = "Linen Cloth", query = "  CLOTH ", want = true },
      { name = "Linen Cloth", query = "", want = true },
      { name = "Linen Cloth", query = nil, want = true },
      { name = "Linen Cloth", query = "wool", want = false },
      { name = "Льняная ткань", query = "льн", want = true },
      { name = "льняная ткань", query = "ЛЬН", want = true },
      { name = "Ґудзик і Їжак", query = "ґудзик і ї", want = true },
      { name = "Élixir de soin", query = "élixir", want = true },
      { name = "ÄRMEL", query = "ärmel", want = true },
      { name = "리넨 옷감", query = "리넨", want = true },
      { name = "a.b", query = ".", want = true },
      { name = nil, query = "x", want = false },
    }) do
      it(("%q in %q -> %s"):format(tostring(case.query), tostring(case.name), tostring(case.want)), function()
        assert.equal(case.want, V.Matches(case.name, case.query))
      end)
    end

    it("filters by period and name together, keeping the rows' order", function()
      local rows = { { name = "Linen", at = 30 }, { name = "Wool", at = 20 }, { name = "Linen Bolt", at = 10 } }
      local out = V.Filter(rows, 15, "linen")
      assert.equal(1, #out)
      assert.equal(30, out[1].at)
      assert.equal(2, #V.Filter(rows, 15, ""))
    end)
  end)

  describe("totals", function()
    it("sums what reached the mailbox and the profit it knows, counting on how many", function()
      local t = V.Totals({ { net = 100, profit = 30 }, { net = 50 }, { net = 20, profit = -5 } })
      assert.same({ count = 3, net = 170, profit = 25, known = 2 }, t)
      assert.same({ count = 0, net = 0, profit = 0, known = 0 }, V.Totals({}))
    end)

    it("names the best sale by known profit, above zero only", function()
      local a, b = { net = 1, profit = 30 }, { net = 1, profit = 90 }
      assert.equal(b, V.Best({ a, { net = 1 }, b, { net = 1, profit = 90 } }))
      assert.is_nil(V.Best({ { net = 1, profit = -3 }, { net = 1 } }))
    end)
  end)

  describe("days", function()
    it("groups rows by calendar day with a count and a sum each, newest day first", function()
      local rows = {
        { net = 10, at = at(2026, 9, 30, 11, 6) },
        { net = 20, at = at(2026, 9, 30, 9, 40) },
        { net = 5, at = at(2026, 9, 29, 22, 44) },
        { net = 7, at = at(2026, 9, 26, 18, 41) },
      }
      local days = V.Days(rows, dateOf)
      assert.equal(3, #days)
      assert.same({ 20260930, 2, 30 }, { days[1].key, days[1].count, days[1].net })
      assert.same({ 20260929, 1, 5 }, { days[2].key, days[2].count, days[2].net })
      assert.same({ 20260926, 1, 7 }, { days[3].key, days[3].count, days[3].net })
      assert.equal(rows[2], days[1].rows[2])
    end)

    for _, case in ipairs({
      { period = "today", back = 0 },
      { period = "7d", back = 6 },
      { period = "30d", back = 29 },
      { period = "nonsense", back = 6 },
    }) do
      it(("starts %s at local midnight %d days back"):format(case.period, case.back), function()
        local now = at(2026, 9, 30, 15, 20)
        local start = V.PeriodStart(case.period, now, dateOf)
        local t = os.date("*t", start)
        assert.same({ 0, 0, 0 }, { t.hour, t.min, t.sec })
        local want = os.date("*t", now - case.back * 86400)
        assert.same({ want.year, want.month, want.day }, { t.year, t.month, t.day })
      end)
    end

    it("snaps to midnight when a clock change falls inside the span", function()
      -- A dateOf with a one-hour jump: every instant before the change reads an hour later
      -- than a plain UTC clock would, the way a zone leaving summer time does.
      local change = 1000000 * 86400 -- midnight UTC, some day
      local function shifted(t)
        local u = os.date("!*t", t < change and (t + 3600) or t)
        return u
      end
      local now = change + 5 * 86400 + 12 * 3600
      local start = V.DayStart(now, 7, shifted)
      local t = shifted(start)
      assert.same({ 0, 0, 0 }, { t.hour, t.min, t.sec })
    end)
  end)

  describe("the snapshot tail", function()
    local summary = { totals = { salesCount = 5 }, sales = { { at = 900 }, { at = 800 } } }
    for _, case in ipairs({
      { from = 700, want = true, why = "the period reaches past the oldest listed sale" },
      { from = 850, want = false, why = "the period starts inside the listed sales" },
    }) do
      it(case.why, function() assert.equal(case.want, V.Truncated(summary, case.from)) end)
    end
    it("is never a tail when the server listed every sale", function()
      assert.is_false(V.Truncated({ totals = { salesCount = 2 }, sales = { { at = 900 }, { at = 800 } } }, 0))
      assert.is_false(V.Truncated(nil, 0))
    end)
  end)

  describe("money", function()
    for _, case in ipairs({
      { copper = 75, want = "75c" },
      { copper = 0, want = "0c" },
      { copper = 8210, want = "82s 10c" },
      { copper = 1000, want = "10s" },
      { copper = 12050, want = "1g 20s" },
      { copper = 2280000, want = "228g" },
      { copper = 2280055, want = "228g" },
      { copper = 94000000, want = "9,400g" },
      { copper = 94005000, want = "9,400g" },
      { copper = 4326100000, want = "432,610g" },
      { copper = -380000, want = "38g" },
    }) do
      it(("%s -> %s"):format(tostring(case.copper), case.want), function()
        assert.equal(case.want, V.Money(case.copper))
      end)
    end

    it("keeps every unit for a breakdown that has to add up", function()
      assert.equal("1,234g 50s 3c", V.Money(12345003, nil, true))
      assert.equal("10s 50c", V.Money(1050, nil, true))
      assert.equal("0c", V.Money(0, nil, true))
      assert.equal("5g", V.Money(50000, nil, true))
    end)

    it("groups the gold with the client's own separator when given one", function()
      assert.equal("9.400g", V.Money(94000000, function(n) return (("%d"):format(n):gsub("^(%d)(%d%d%d)$", "%1.%2")) end))
    end)

    it("signs a profit", function()
      assert.equal("+61g", V.Signed(610000))
      assert.equal("-38g", V.Signed(-380000))
      assert.equal("+0c", V.Signed(0))
    end)
  end)

  describe("percent and progress", function()
    for _, case in ipairs({
      { each = 75, market = 70, want = 7 },
      { each = 1170, market = 1250, want = -6 },
      { each = 70, market = 70, want = 0 },
      { each = 70, market = 0, want = nil },
      { each = nil, market = 70, want = nil },
    }) do
      it(("%s against %s"):format(tostring(case.each), tostring(case.market)), function()
        assert.equal(case.want, V.Percent(case.each, case.market))
      end)
    end

    it("caps progress at the whole cost and floors it at nothing", function()
      assert.equal(0.5, V.Progress(450000, 900000))
      assert.equal(1, V.Progress(2000000, 900000))
      assert.equal(0, V.Progress(-5, 900000))
      assert.equal(0, V.Progress(5, nil))
    end)
  end)

  describe("FitColumns", function()
    local cols = { { key = "when", need = 40 }, { key = "each", need = 50 }, { key = "got", need = 60 },
      { key = "profit", need = 70 } }

    it("gives every column what its widest text needs and ITEM the rest", function()
      local fit = V.FitColumns(600, cols, 10, 92, { "when", "each" })
      assert.same({ when = 40, each = 50, got = 60, profit = 70 }, fit.widths)
      assert.same({}, fit.hidden)
      assert.equal(600 - 220 - 40, fit.item)
    end)

    it("drops WHEN, then EACH, before it would squeeze ITEM under its minimum -- never a figure", function()
      local narrow = V.FitColumns(320, cols, 10, 92, { "when", "each" })
      assert.same({ when = true }, narrow.hidden)
      assert.equal(320 - 180 - 30, narrow.item)
      local narrower = V.FitColumns(240, cols, 10, 92, { "when", "each" })
      assert.same({ when = true, each = true }, narrower.hidden)
      assert.equal(240 - 130 - 20, narrower.item)
      -- The figures that stay are never cut down to make room.
      assert.equal(70, narrower.widths.profit)
    end)
  end)
end)
