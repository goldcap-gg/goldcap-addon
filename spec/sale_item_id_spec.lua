local helper = require("spec.spec_helper")

-- A seller invoice carries the item's name and the money, never the item: every sale row the
-- mailbox wrote had no itemID (owner's WoW: Forever save, 2026-11-25: 160 of 160). SOLD then found
-- the item through a listing of the same name, and WoW: Forever names gear with its random suffix
-- in the mailbox ("Jade Bracers of the Defender") but by the bare item in a listing ("Jade
-- Bracers"): the three pieces of gear the owner sold showed an empty icon, "-" for profit and no
-- bar, and their purchases were never matched to the sales. The id comes from the player's own
-- rows of the exact same name (the purchase it came from, a lot's deposit), confirmed by a listing
-- of that item at the price it sold for.
describe("A sale's item", function()
  local GC, db, context

  local DEFENDER, BEAR = "item:14914:46:14333:0", "item:14914:46:14334:0"
  local NAME = "Jade Bracers of the Defender"

  local function sale(over)
    local entry = { key = "SALE", kind = "sale", source = "mail", itemName = NAME, qty = 1, total = 26900,
      cut = 1345, deposit = 718, pending = false, at = 5000, char = context.char, region = context.region }
    for k, v in pairs(over or {}) do entry[k] = v end
    return entry
  end

  -- The owner's Jade Bracers: a sniper buy (the bare name), its mail (the suffixed one), the batch
  -- that mail filed, and the listing the Sell tab saw at 269 silver.
  local function bracers()
    db.ledger[#db.ledger + 1] = { key = "SNIPE", kind = "buy", source = "goldcap_sniper", itemID = 14914,
      itemName = "Jade Bracers", qty = 1, total = 9915, at = 1000, char = context.char, region = context.region }
    db.ledger[#db.ledger + 1] = { key = "BUYMAIL", kind = "buy", source = "mail", itemID = 14914,
      itemName = NAME, qty = 1, total = 9915, at = 1010, char = context.char, region = context.region }
    GC.Acquisitions.Record({ source = "goldcap", itemID = 14914, positionKey = DEFENDER, itemName = NAME,
      quantity = 1, total = 9915, acquiredAt = 1000, evidenceKey = "SNIPE", character = context.char,
      region = context.region })
    GC.Acquisitions.RecordPost(DEFENDER, 14914, "Jade Bracers", context.char, context.region, 1, 2000, 26900)
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    helper.loadModule("Core/Ledger.lua", GC)
    db = {}
    GC.Acquisitions.Init(db)
    GC.Ledger.Init(db)
    context = { char = "Meolys-Realm", region = "eu" }
  end)

  describe("SaleItemID", function()
    it("names the item the player's own rows of the exact name carry, listed at the price it sold for", function()
      bracers()
      assert.equal(14914, GC.Acquisitions.SaleItemID(sale(), db.ledger))
    end)

    it("reads a purchase's mail alone, without the batch it filed", function()
      db.ledger[1] = { key = "BUYMAIL", kind = "buy", source = "mail", itemID = 14914, itemName = NAME,
        qty = 1, total = 9915, at = 1010, char = context.char, region = context.region }
      GC.Acquisitions.RecordPost(DEFENDER, 14914, "Jade Bracers", context.char, context.region, 1, 2000, 26900)
      assert.equal(14914, GC.Acquisitions.SaleItemID(sale(), db.ledger))
    end)

    it("names nothing without a listing of the item at the price it sold for", function()
      bracers()
      assert.is_nil(GC.Acquisitions.SaleItemID(sale({ total = 27000 }), db.ledger))
      -- A listing keeps the last time its price was seen: the lot read at its price again after
      -- the mail came (the owner's Medicine Staff of the Bandit, 32 seconds after) still names it.
      assert.equal(14914, GC.Acquisitions.SaleItemID(sale({ at = 1500 }), db.ledger))
    end)

    -- Farmed gear has no purchase and, sold at its first post, no deposit row: its own lot on the
    -- saved roster carries the name the mail does (owner's save: Edged Bastard Sword of the Wolf).
    it("names a farmed piece from its own lot on the saved roster", function()
      db.ownedLots = { { auctionID = 77, itemID = 15213, itemName = "Edged Bastard Sword of the Wolf", unitPrice = 1300,
        quantity = 1, isCommodity = false, char = context.char, region = context.region, seenAt = 4000 } }
      assert.equal(15213, GC.Acquisitions.SaleItemID(sale({ itemName = "Edged Bastard Sword of the Wolf", total = 1300 }),
        db.ledger))
      assert.is_nil(GC.Acquisitions.SaleItemID(sale({ itemName = "Edged Bastard Sword of the Wolf", total = 1300,
        char = "Other-Realm" }), db.ledger))
    end)

    it("names nothing from another character's rows, from another sale, or from no row at all", function()
      assert.is_nil(GC.Acquisitions.SaleItemID(sale(), db.ledger))
      bracers()
      assert.is_nil(GC.Acquisitions.SaleItemID(sale({ char = "Other-Realm" }), db.ledger))
      local only = { { key = "OLD", kind = "sale", source = "mail", itemID = 14914, itemName = NAME, qty = 1,
        total = 26900, at = 900, char = context.char, region = context.region } }
      db.acquisitions = {}
      assert.is_nil(GC.Acquisitions.SaleItemID(sale(), only))
    end)

    -- Two quality ranks of a reagent share one name and are two ids: the price they were listed
    -- at tells them apart, and nothing else does.
    it("tells two items of one name apart by the price each was listed at, and only by that", function()
      local ore = "Brilliant Silver Ore"
      for _, id in ipairs({ 237364, 237365 }) do
        db.ledger[#db.ledger + 1] = { key = "B" .. id, kind = "buy", source = "mail", itemID = id, itemName = ore,
          qty = 10, total = 1000, at = 100, char = context.char, region = context.region }
      end
      GC.Acquisitions.RecordPost("commodity:237364", 237364, ore, context.char, context.region, 5, 200, 655)
      GC.Acquisitions.RecordPost("commodity:237365", 237365, ore, context.char, context.region, 5, 200, 3459)
      assert.equal(237365, GC.Acquisitions.SaleItemID(sale({ itemName = ore, qty = 2, total = 6918 }), db.ledger))
      assert.equal(237364, GC.Acquisitions.SaleItemID(sale({ itemName = ore, qty = 2, total = 1310 }), db.ledger))
      GC.Acquisitions.RecordPost("commodity:237364", 237364, ore, context.char, context.region, 5, 300, 3459)
      assert.is_nil(GC.Acquisitions.SaleItemID(sale({ itemName = ore, qty = 2, total = 6918 }), db.ledger))
    end)
  end)

  describe("ReconcileSale", function()
    it("places a suffixed piece's sale on the position its purchase of that name was filed under", function()
      bracers()
      local result = GC.Acquisitions.ReconcileSale(sale({ itemID = 14914 }))
      assert.equal("applied", result.status)
      assert.equal(DEFENDER, result.positionKey)
      assert.equal(9915, result.cost)
      assert.equal(1, #GC.Acquisitions.GetRealized(context))
    end)

    -- Random suffixes share one item ID: a sale "of the Defender" must never draw down the
    -- purchase "of the Bear".
    it("never draws on another suffix's purchase of the same item", function()
      bracers()
      GC.Acquisitions.Record({ source = "goldcap", itemID = 14914, positionKey = BEAR,
        itemName = "Jade Bracers of the Bear", quantity = 1, total = 5000, acquiredAt = 1100,
        evidenceKey = "BEARBUY", character = context.char, region = context.region })
      GC.Acquisitions.RecordPost(BEAR, 14914, "Jade Bracers", context.char, context.region, 1, 2100, 26900)
      local result = GC.Acquisitions.ReconcileSale(sale({ itemID = 14914 }))
      assert.equal("applied", result.status)
      assert.equal(DEFENDER, result.positionKey)
      local bear
      for _, batch in ipairs(GC.Acquisitions.GetAll()) do
        if batch.positionKey == BEAR then bear = batch end
      end
      assert.equal(1, bear.remainingQty)
    end)

    it("draws a replayed sale only on stock bought by the time it was read", function()
      bracers()
      -- Listed since 500, the purchase on the books made at 1000, the sale read at 900.
      GC.Acquisitions.RecordPost(DEFENDER, 14914, "Jade Bracers", context.char, context.region, 1, 500, 26900)
      local old = sale({ itemID = 14914, at = 900 })
      assert.equal("unresolved", GC.Acquisitions.ReconcileSale(old, { boughtBy = old.at }).status)
      assert.equal(1, GC.Acquisitions.GetAll()[1].remainingQty)
    end)

    it("does not place a sale on a position of another item than the sale names", function()
      bracers()
      assert.equal("unresolved", GC.Acquisitions.ReconcileSale(sale({ itemID = 9999 })).status)
    end)
  end)

  describe("the mailbox", function()
    local function api(invoice)
      return {
        GetInboxNumItems = function() return 1 end,
        GetInboxHeaderInfo = function()
          return nil, nil, "Horde Auction House", "Auction successful", 0, 0, 30, false, false, false, false, false
        end,
        GetInboxInvoiceInfo = function()
          return invoice.invoiceType or "seller", invoice.itemName or NAME, "Buyer", invoice.bid or 26900,
            invoice.bid or 26900, 718, 1345, invoice.moneyDelay or 0, 0, 0, 1, true
        end,
        GetInboxItem = function() return nil end,
      }
    end

    it("records a sale with the item its own rows name, and matches it to its purchase", function()
      bracers()
      GC.Ledger.ScanInbox(api({}), context, 5000)
      local row = GC.Ledger.GetEntries()[#GC.Ledger.GetEntries()]
      assert.equal("sale", row.kind)
      assert.equal(14914, row.itemID)
      local realized = GC.Acquisitions.GetRealized(context)
      assert.equal(1, #realized)
      assert.equal(DEFENDER, realized[1].positionKey)
    end)

    it("leaves a sale it cannot name without an item, as it always was", function()
      GC.Ledger.ScanInbox(api({}), context, 5000)
      assert.is_nil(GC.Ledger.GetEntries()[1].itemID)
    end)
  end)

  -- The sales already recorded without their item get it once, and those whose stock was never
  -- drawn down are matched to it then.
  describe("RepairSaleItemIDs", function()
    it("names the item on a recorded sale and matches it to its purchase, once per save", function()
      bracers()
      db.ledger[#db.ledger + 1] = sale()
      local named, matched = GC.Acquisitions.RepairSaleItemIDs()
      assert.equal(1, named)
      assert.equal(1, matched)
      assert.equal(14914, db.ledger[#db.ledger].itemID)
      assert.equal(1, #GC.Acquisitions.GetRealized(context))
      assert.equal(1, db.saleItemRepairVersion)
      db.ledger[#db.ledger].itemID = nil
      assert.equal(0, (GC.Acquisitions.RepairSaleItemIDs()))
      assert.is_nil(db.ledger[#db.ledger].itemID)
    end)

    -- The repair replays sales read long ago: what was bought since is still the player's.
    it("names an old sale but leaves stock bought after it alone", function()
      bracers()
      GC.Acquisitions.RecordPost(DEFENDER, 14914, "Jade Bracers", context.char, context.region, 1, 500, 26900)
      db.ledger[#db.ledger + 1] = sale({ at = 900 })
      local named, matched = GC.Acquisitions.RepairSaleItemIDs()
      assert.equal(1, named)
      assert.equal(0, matched)
      assert.equal(14914, db.ledger[#db.ledger].itemID)
      assert.equal(1, GC.Acquisitions.GetAll()[1].remainingQty)
    end)

    it("does not match a sale twice, nor touch a sale that already names its item or cannot be named", function()
      bracers()
      db.ledger[#db.ledger + 1] = sale()
      assert.equal("applied", GC.Acquisitions.ReconcileSale(db.ledger[#db.ledger]).status)
      db.ledger[#db.ledger + 1] = sale({ key = "NAMED", itemID = 777 })
      db.ledger[#db.ledger + 1] = sale({ key = "UNKNOWN", itemName = "Something Else" })
      local named, matched = GC.Acquisitions.RepairSaleItemIDs()
      assert.equal(1, named)
      assert.equal(0, matched)
      assert.equal(1, #GC.Acquisitions.GetRealized(context))
      assert.equal(777, db.ledger[#db.ledger - 1].itemID)
      assert.is_nil(db.ledger[#db.ledger].itemID)
    end)
  end)
end)
