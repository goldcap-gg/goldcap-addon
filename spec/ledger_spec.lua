local helper = require("spec.spec_helper")

describe("Ledger store", function()
  local GC, db

  local function baseFields(overrides)
    local f = {
      sender = "Auction House",
      itemName = "Ironclaw Ore",
      count = 20,
      bid = 500000,
      buyout = 500000,
      deposit = 1000,
      consignment = 25000,
      expiresAt = 1000000,
    }
    for k, v in pairs(overrides or {}) do f[k] = v end
    return f
  end

  local function saleEntry(overrides)
    local e = {
      kind = "sale",
      source = "mail",
      itemName = "Ironclaw Ore",
      qty = 20,
      total = 500000,
      cut = 25000,
      deposit = 1000,
      pending = false,
      at = 900000,
      char = "Belarsa-Dentarg",
      region = "eu",
    }
    for k, v in pairs(overrides or {}) do e[k] = v end
    e.key = e.key or GC.Ledger.EntryKey(baseFields({ itemName = e.itemName, count = e.qty }))
    return e
  end

  before_each(function()
    GC = helper.loadModule("Core/Ledger.lua")
    db = {}
    GC.Ledger.Init(db)
  end)

  it("keys an invoice on its immutable money fields, not on the mail index", function()
    local a = GC.Ledger.EntryKey(baseFields())
    local b = GC.Ledger.EntryKey(baseFields())
    assert.equal(a, b)
    assert.is_string(a)
  end)

  it("gives two different sales two different keys", function()
    local a = GC.Ledger.EntryKey(baseFields())
    local b = GC.Ledger.EntryKey(baseFields({ bid = 500001 }))
    assert.not_equal(a, b)
  end)

  it("appends a new entry and reports it as new", function()
    local entry, isNew = GC.Ledger.Append(saleEntry())
    assert.is_true(isNew)
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal("sale", entry.kind)
    assert.equal("mail", entry.source)
  end)

  it("updates in place on a repeat key instead of appending a duplicate", function()
    GC.Ledger.Append(saleEntry({ pending = true, total = 0 }))
    local entry, isNew = GC.Ledger.Append(saleEntry({ pending = false, total = 500000 }))

    assert.is_false(isNew)
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.is_false(entry.pending)
    assert.equal(500000, entry.total)
  end)

  it("clears the uploaded flag when a row's contents change", function()
    local first = GC.Ledger.Append(saleEntry({ pending = true }))
    GC.Ledger.MarkUploaded({ first.key })
    local updated = GC.Ledger.Append(saleEntry({ pending = false }))
    -- The row changed, so whatever the server holds is now out of date and it
    -- has to be sent again.
    assert.is_falsy(updated.uploaded)
  end)

  it("marks only the keys it was given", function()
    local a = GC.Ledger.Append(saleEntry({ itemName = "A" }))
    local b = GC.Ledger.Append(saleEntry({ itemName = "B" }))
    assert.equal(1, GC.Ledger.MarkUploaded({ a.key }))
    assert.is_true(a.uploaded)
    assert.is_falsy(b.uploaded)
  end)

  it("ignores unknown keys when marking uploaded", function()
    assert.equal(0, GC.Ledger.MarkUploaded({ "nope" }))
  end)

  it("drops the oldest already-uploaded entry first when full", function()
    for i = 1, GC.Ledger.MAX_ENTRIES do
      GC.Ledger.Append(saleEntry({ itemName = "Item" .. i, at = i }))
    end
    local entries = GC.Ledger.GetEntries()
    GC.Ledger.MarkUploaded({ entries[1].key })
    local survivorKey = entries[2].key

    GC.Ledger.Append(saleEntry({ itemName = "Overflow", at = 999999 }))

    entries = GC.Ledger.GetEntries()
    assert.equal(GC.Ledger.MAX_ENTRIES, #entries)
    assert.equal(survivorKey, entries[1].key)
    assert.equal("Overflow", entries[#entries].itemName)
  end)

  it("drops the oldest un-uploaded entry only when nothing uploaded is left to drop", function()
    for i = 1, GC.Ledger.MAX_ENTRIES do
      GC.Ledger.Append(saleEntry({ itemName = "Item" .. i, at = i }))
    end
    local firstKey = GC.Ledger.GetEntries()[1].key
    GC.Ledger.Append(saleEntry({ itemName = "Overflow", at = 999999 }))

    local entries = GC.Ledger.GetEntries()
    assert.equal(GC.Ledger.MAX_ENTRIES, #entries)
    assert.not_equal(firstKey, entries[1].key)
  end)

  it("tolerates being used before Init, the way Data.lua does", function()
    local fresh = helper.loadModule("Core/Ledger.lua")
    assert.has_no.errors(function() fresh.Ledger.Append({ key = "k" }) end)
    assert.same({}, fresh.Ledger.GetEntries())
  end)

  describe("RecordSniperBuy", function()
    local context = { char = "Belarsa-Dentarg", region = "eu" }

    local function purchase(overrides)
      local facts = {
        itemID = 210930,
        quantity = 1,
        total = 100,
        unitDisplay = 100,
        decisionVersion = 1,
        decisionStatus = "SAFE",
        decisionReasons = {},
        stressUnit = 200,
        expectedProfit = 50,
        recommendedQuantity = 1,
        sourceAt = 4000,
      }
      for k, v in pairs(overrides or {}) do facts[k] = v end
      return facts
    end

    it("records the buy with the market value it was judged against", function()
      local entry = GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 20, unitPrice = 12000, mv = 25000, discount = 0.52 },
        purchase({ quantity = 20, total = 240000, unitDisplay = 12000, recommendedQuantity = 20 }),
        context, 5000)

      assert.equal("buy", entry.kind)
      -- The whole point of the feature: only a buy tagged here can ever be
      -- credited to GoldCap when it later sells.
      assert.equal("goldcap_sniper", entry.source)
      assert.equal(210930, entry.itemID)
      assert.equal(20, entry.qty)
      assert.equal(240000, entry.total)
      assert.equal(25000, entry.mv)
      assert.equal(5000, entry.at)
      assert.equal("Belarsa-Dentarg", entry.char)
    end)

    it("preserves exact purchase cost and every decision fact without mutation", function()
      local reasons = { "capital_limit", "demand_limit" }
      local facts = purchase({
        quantity = 2,
        total = 201,
        unitDisplay = 100,
        decisionVersion = 7,
        decisionStatus = "SAFE",
        decisionReasons = reasons,
        stressUnit = 300,
        expectedProfit = 99,
        recommendedQuantity = 2,
        sourceAt = 4321,
      })
      local entry = GC.Ledger.RecordSniperBuy({ itemID = 210930, mv = 25000 }, facts, context, 5000)

      assert.equal(2, entry.qty)
      assert.equal(201, entry.total)
      assert.equal(7, entry.decisionVersion)
      assert.equal("SAFE", entry.decisionStatus)
      assert.same({ "capital_limit", "demand_limit" }, entry.decisionReasons)
      assert.not_equal(reasons, entry.decisionReasons)
      assert.equal(300, entry.stressUnit)
      assert.equal(99, entry.expectedProfit)
      assert.equal(2, entry.recommendedQuantity)
      assert.equal(4321, entry.sourceAt)
    end)

    it("records an upstream-valid zero source timestamp without losing exact cost", function()
      local entry = GC.Ledger.RecordSniperBuy({ itemID = 210930, mv = 25000 }, purchase({
        quantity = 2, total = 201, unitDisplay = 100, recommendedQuantity = 2, sourceAt = 0,
      }), context, 5000)
      assert.equal(201, entry.total)
      assert.equal(0, entry.sourceAt)
    end)

    it("gives two buys of the same item at the same second distinct keys", function()
      local deal = { itemID = 210930, qty = 20, unitPrice = 12000, mv = 25000 }
      local facts = purchase({ quantity = 20, total = 240000, unitDisplay = 12000, recommendedQuantity = 20 })
      local a = GC.Ledger.RecordSniperBuy(deal, facts, context, 5000)
      local b = GC.Ledger.RecordSniperBuy(deal, facts, context, 5000)
      -- Sniping the same item twice in one second is ordinary, and collapsing
      -- the second buy into the first would silently lose real spend.
      assert.not_equal(a.key, b.key)
      assert.equal(2, #GC.Ledger.GetEntries())
    end)

    it("stores a buy with no known market value rather than dropping it", function()
      local entry = GC.Ledger.RecordSniperBuy(
        { itemID = 7, qty = 1, unitPrice = 100 }, purchase({ itemID = 7 }), context, 1)
      assert.is_nil(entry.mv)
      assert.equal(100, entry.total)
    end)

    it("is a no-op before Init instead of erroring mid-purchase", function()
      local fresh = helper.loadModule("Core/Ledger.lua")
      assert.has_no.errors(function()
        fresh.Ledger.RecordSniperBuy({ itemID = 1 }, purchase({ itemID = 1, total = 1, unitDisplay = 1 }), context, 1)
      end)
    end)

    it("carries the item name when the client can supply one", function()
      _G.C_Item = { GetItemNameByID = function() return "Ironclaw Ore" end }
      local entry = GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 100 }, purchase(), context, 1)
      _G.C_Item = nil
      assert.equal("Ironclaw Ore", entry.itemName)
    end)

    it("tolerates a client that cannot name the item", function()
      -- No C_Item under busted -- exactly the degraded in-game case.
      local entry = GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 100 }, purchase(), context, 1)
      assert.is_nil(entry.itemName)
    end)

    it("returns nil for a direct caller that lacks immutable purchase facts", function()
      assert.is_nil(GC.Ledger.RecordSniperBuy({ itemID = 210930, qty = 1, unitPrice = 100 }, nil, context, 1))
    end)

    -- Sniper phase 2: a realm lot is bought on a candidate, never on a SAFE decision -- nothing
    -- measures how fast a realm item sells. The gold still left the player's bags, so the buy
    -- is recorded, and `unverified` is the field that says what was not known about it.
    it("records an unverified realm buy and marks the row", function()
      local entry = GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 750000, mv = 1000000, discount = 0.25 },
        purchase({
          quantity = 1, total = 750000, unitDisplay = 750000,
          decisionStatus = "WATCH", unverified = true,
          decisionReasons = { "realm_item_unverified" },
          stressUnit = 1000000, expectedProfit = 200000, sourceAt = 0,
        }), context, 5000)

      assert.equal("buy", entry.kind)
      assert.equal("goldcap_sniper", entry.source)
      assert.equal(750000, entry.total)
      assert.equal("WATCH", entry.decisionStatus)
      assert.is_true(entry.unverified)
      assert.same({ "realm_item_unverified" }, entry.decisionReasons)
      assert.equal(1000000, entry.stressUnit)
    end)

    it("still refuses a WATCH fact that does not claim to be an unverified realm buy", function()
      assert.is_nil(GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 100 },
        purchase({ decisionStatus = "WATCH" }), context, 1))
      assert.is_nil(GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 100 },
        purchase({ decisionStatus = "WATCH", unverified = "yes" }), context, 1))
      assert.is_nil(GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 100 },
        purchase({ decisionStatus = "AVOID", unverified = true }), context, 1))
      assert.equal(0, #GC.Ledger.GetEntries())
    end)

    it("leaves a SAFE row's shape exactly as it was, with no unverified field", function()
      local entry = GC.Ledger.RecordSniperBuy(
        { itemID = 210930, qty = 1, unitPrice = 100 }, purchase(), context, 1)
      assert.is_nil(entry.unverified)
    end)

    it("rejects non-finite and unsafe direct purchase facts without recording a ledger row", function()
      local MAX_EXACT = 9007199254740991
      local cases = {
        { deal = { itemID = math.huge }, facts = { itemID = math.huge } },
        { facts = { quantity = math.huge, unitDisplay = 0 } },
        { facts = { total = -math.huge, unitDisplay = -math.huge } },
        { facts = { decisionVersion = 0 / 0 } },
        { facts = { stressUnit = 1.5 } },
        { facts = { expectedProfit = -1 } },
        { facts = { recommendedQuantity = math.huge } },
        { facts = { sourceAt = MAX_EXACT + 1 } },
      }

      for _, candidate in ipairs(cases) do
        local deal = candidate.deal or { itemID = 210930, qty = 1, unitPrice = 100 }
        local facts = purchase(candidate.facts)
        local ok, entry = pcall(GC.Ledger.RecordSniperBuy, deal, facts, context, 1)
        assert.is_true(ok)
        assert.is_nil(entry)
        assert.equal(0, #GC.Ledger.GetEntries())
      end
    end)
  end)

  describe("Context", function()
    it("returns a nil-safe shape when there is no player, as under busted", function()
      assert.has_no.errors(function()
        local ctx = GC.Ledger.Context()
        assert.is_table(ctx)
      end)
    end)

    it("joins name and realm when the game provides both", function()
      _G.UnitName = function() return "Belarsa" end
      _G.GetRealmName = function() return "Dentarg" end
      local ctx = GC.Ledger.Context()
      _G.UnitName, _G.GetRealmName = nil, nil
      assert.equal("Belarsa-Dentarg", ctx.char)
    end)
  end)

  -- Task 9 Step 4b: the Sell tab's pending-sync hint reads this counter to explain why
  -- goldcap.gg hasn't seen this session's buys/sales yet (SavedVariables only flush on
  -- /reload or logout). before_each above already gives every test a FRESH GC.Ledger module
  -- (helper.loadModule re-executes the chunk), so sessionEventCount starts at 0 every time.
  describe("SessionEventCount", function()
    it("starts at zero on a fresh module load", function()
      assert.equal(0, GC.Ledger.SessionEventCount())
    end)

    it("increments once per genuinely new Append", function()
      GC.Ledger.Append(saleEntry())
      assert.equal(1, GC.Ledger.SessionEventCount())
      GC.Ledger.Append(saleEntry({ itemName = "Runed Copper Rod", bid = 999 }))
      assert.equal(2, GC.Ledger.SessionEventCount())
    end)

    it("does not increment when a repeat key just updates the stored row", function()
      GC.Ledger.Append(saleEntry({ pending = true }))
      assert.equal(1, GC.Ledger.SessionEventCount())
      -- Same key (same money fields) as above -- a mailbox re-scan of the same invoice, not
      -- a new fact reaching the ledger.
      GC.Ledger.Append(saleEntry({ pending = false }))
      assert.equal(1, GC.Ledger.SessionEventCount())
    end)

    it("counts a RecordSniperBuy the same way a mail-scanned Append counts", function()
      local context = { char = "Belarsa-Dentarg", region = "eu" }
      GC.Ledger.RecordSniperBuy({ itemID = 210930, qty = 1, unitPrice = 100 }, {
        itemID = 210930, quantity = 1, total = 100, unitDisplay = 100,
        decisionVersion = 1, decisionStatus = "SAFE", decisionReasons = {}, stressUnit = 200,
        expectedProfit = 50, recommendedQuantity = 1, sourceAt = 1,
      }, context, 1)
      assert.equal(1, GC.Ledger.SessionEventCount())
    end)
  end)
end)
