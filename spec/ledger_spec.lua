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
end)
