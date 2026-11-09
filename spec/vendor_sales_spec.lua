local helper = require("spec.spec_helper")

-- Core/VendorSales.lua (WoW: Forever only): a stack sold to a merchant spends the purchase lots it
-- came from, read off the merchant's buyback list. The merchant is an API-shaped fake: the client's
-- GetNumBuybackItems, GetBuybackItemInfo (exactly name, texture, price, quantity, numAvailable,
-- isUsable, isBound, as Blizzard's MerchantFrame.lua reads it), GetBuybackItemLink and
-- C_MerchantFrame.GetBuybackItemID, plus MerchantFrame:IsShown(). The acquisition store is the real
-- one. The sale is booked when the merchant closes, as Core/Init.lua forwards MERCHANT_CLOSED.
describe("merchant sales spend purchase lots", function()
  local GC, db, shelf, ledgerRows
  local me = { char = "Seller-Realm", region = "110" }

  local function link(itemID, suffix)
    return ("|cffffffff|Hitem:%d::::::%s:::::::::|h[Item %d]|h|r"):format(itemID, suffix or "", itemID)
  end

  -- The merchant's buyback page: oldest first, the newest sale last, twelve at most.
  local function sell(itemID, quantity, price, suffix)
    shelf[#shelf + 1] = { itemID = itemID, quantity = quantity, price = price, link = link(itemID, suffix) }
    if #shelf > 12 then table.remove(shelf, 1) end
  end

  local function buyBack(index) table.remove(shelf, index) end

  local function lot(fields)
    local args = { source = "goldcap", itemID = 1206, positionKey = "commodity:1206", itemName = "Moss Agate",
      quantity = 4, total = 1440, acquiredAt = 100, character = me.char, region = me.region }
    for key, value in pairs(fields or {}) do args[key] = value end
    args.evidenceKey = args.evidenceKey or ("deal:" .. tostring(args.itemID) .. ":" .. tostring(args.acquiredAt)
      .. ":" .. tostring(args.character) .. ":" .. tostring(args.region))
    return (GC.Acquisitions.Record(args))
  end

  local function saleKeys()
    local keys = {}
    for key in pairs(db.acquisitionConsumptionEvidence) do
      if key:find("^vendorsale\1") then keys[#keys + 1] = key end
    end
    return keys
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/VendorSales.lua", GC)
    ledgerRows = {}
    db = { ledger = {} }
    GC.db = db
    GC.Acquisitions.Init(db)
    GC.Ledger = { Context = function() return me end,
      Append = function(row) ledgerRows[#ledgerRows + 1] = row end }
    shelf = {}
    _G.GetNumBuybackItems = function() return #shelf end
    _G.GetBuybackItemInfo = function(index)
      local entry = shelf[index]
      if not entry then return nil end
      return "Item " .. entry.itemID, 134400, entry.price, entry.quantity, -1, true, false
    end
    _G.GetBuybackItemLink = function(index) return shelf[index] and shelf[index].link end
    _G.C_MerchantFrame = { GetBuybackItemID = function(index) return shelf[index] and shelf[index].itemID end }
    _G.MerchantFrame = { shown = true }
    function _G.MerchantFrame:IsShown() return self.shown end
    GC.VendorSales.Install()
  end)

  after_each(function()
    _G.GetNumBuybackItems, _G.GetBuybackItemInfo, _G.GetBuybackItemLink = nil, nil, nil
    _G.C_MerchantFrame, _G.MerchantFrame = nil, nil
  end)

  it("books a stack sold to a merchant against the oldest purchase of the item, once", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    assert.equal(4, batch.remainingQty) -- booked at the close, not before
    GC.VendorSales.OnClosed(202)

    assert.equal(0, batch.remainingQty)
    assert.equal(0, batch.remainingTotal)
    local keys = saleKeys()
    assert.equal(1, #keys)
    assert.is_true(batch.consumedEvidenceKeys[keys[1]])
    local realized = GC.Acquisitions.GetRealized(me)
    assert.equal(1, #realized)
    assert.equal(keys[1], realized[1].evidenceKey)
    assert.equal(4, realized[1].quantity)
    assert.equal(1440, realized[1].cost)
    assert.equal(1600, realized[1].proceeds)
    assert.equal(160, realized[1].profit)
    assert.equal("vendor_sale", realized[1].source)
    assert.equal("commodity:1206", realized[1].positionKey)

    -- The same stack still on the page is not sold again: another read, another visit.
    GC.VendorSales.OnChanged(203)
    GC.VendorSales.OnClosed(204)
    GC.VendorSales.OnShow(300)
    GC.VendorSales.OnChanged(301)
    GC.VendorSales.OnClosed(302)
    assert.equal(1, #saleKeys())
    assert.equal(1, #GC.Acquisitions.GetRealized(me))
  end)

  it("takes only what the books hold when bought and looted units are sold together", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 6, 600)
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(0, batch.remainingQty)
    local realized = GC.Acquisitions.GetRealized(me)[1]
    assert.equal(4, realized.quantity)
    assert.equal(400, realized.proceeds) -- four sixths of what the merchant paid
    assert.equal(1440, realized.cost)
  end)

  it("books nothing for a stack bought back before the merchant closed", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    buyBack(1)
    GC.VendorSales.OnChanged(202)
    GC.VendorSales.OnClosed(203)
    assert.equal(4, batch.remainingQty)
    assert.equal(0, #saleKeys())
    assert.equal(0, #GC.Acquisitions.GetRealized(me))
  end)

  it("keeps a sale when the stack sold before it is the one bought back", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 2, 800)
    GC.VendorSales.OnChanged(201)
    sell(1206, 2, 800)
    GC.VendorSales.OnChanged(202)
    buyBack(1)
    GC.VendorSales.OnChanged(203)
    GC.VendorSales.OnClosed(204)
    assert.equal(2, batch.remainingQty)
    assert.equal(1, #saleKeys())
  end)

  it("reads a full page that drops its oldest as one new sale, not a buyback", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    for i = 1, 11 do
      sell(9000 + i, 1, 5)
      GC.VendorSales.OnChanged(201 + i)
    end
    assert.equal(12, #shelf)
    sell(9100, 1, 5) -- a full page: the Moss Agate, oldest, goes off its front
    assert.equal(9001, shelf[1].itemID)
    GC.VendorSales.OnChanged(220)
    GC.VendorSales.OnClosed(221)
    assert.equal(0, batch.remainingQty)
    assert.equal(1, #saleKeys())
  end)

  it("ignores a read made after the merchant closed, and loses no sale to it", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    _G.MerchantFrame.shown = false
    shelf = {}
    GC.VendorSales.OnChanged(202) -- not "everything was bought back"
    GC.VendorSales.OnClosed(203)
    assert.equal(0, batch.remainingQty)
    assert.equal(1, #saleKeys())
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(204) -- no visit open: says nothing
    GC.VendorSales.OnClosed(205)
    assert.equal(1, #saleKeys())
  end)

  it("takes a list still empty at the door for the last visit's, not as everything new", function()
    lot({ quantity = 8, total = 2880 })
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    local kept = shelf
    shelf = {}
    GC.VendorSales.OnShow(300) -- the client has not handed the page over yet
    shelf = kept
    GC.VendorSales.OnChanged(301)
    GC.VendorSales.OnClosed(302)
    assert.equal(1, #saleKeys())
  end)

  it("books a visit the client never closed at the next door", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnShow(300)
    assert.equal(0, batch.remainingQty)
    assert.equal(1, #saleKeys())
  end)

  it("leaves an item alone when its lots carry two keys and the sale cannot say which", function()
    local a = lot({ itemID = 2632, positionKey = "item:2632:14:14311:0", quantity = 1, total = 500 })
    local b = lot({ itemID = 2632, positionKey = "item:2632:14:14303:0", quantity = 1, total = 700, acquiredAt = 110 })
    GC.VendorSales.OnShow(200)
    sell(2632, 1, 900)
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(1, a.remainingQty)
    assert.equal(1, b.remainingQty)
    assert.equal(0, #saleKeys())
  end)

  it("spends only this character's and region's lots", function()
    local alt = lot({ character = "Alt-Realm", acquiredAt = 50 })
    local other = lot({ region = "90", acquiredAt = 60 })
    local mine = lot({ acquiredAt = 100 })
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(4, alt.remainingQty)
    assert.equal(4, other.remainingQty)
    assert.equal(0, mine.remainingQty)
  end)

  it("never writes a ledger row", function()
    lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(1, #saleKeys())
    assert.same({}, db.ledger)
    assert.same({}, ledgerRows)
  end)

  it("reads nothing as a sale when an entry of the page cannot be read", function()
    local batch = lot()
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    _G.C_MerchantFrame.GetBuybackItemID = function() return nil end
    shelf[1].link = nil
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(4, batch.remainingQty)
  end)

  it("books every sale of a visit even when one booking fails", function()
    local booked = {}
    local page = {}
    GC.VendorSales.SetDriver({
      open = function() return true end,
      buyback = function() return page end,
      record = function(sale)
        if sale.itemID == 1 then error("store refused") end
        booked[#booked + 1] = sale.itemID
      end,
    })
    GC.VendorSales.OnShow(200)
    page = { { itemID = 1, quantity = 1, price = 5 }, { itemID = 2, quantity = 1, price = 5 } }
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.same({ 2 }, booked)
  end)

  describe("the page diff", function()
    local function entry(itemID, quantity) return { itemID = itemID, link = "l" .. itemID, quantity = quantity or 1, price = 5 } end
    local function ids(list)
      local out = {}
      for _, e in ipairs(list) do out[#out + 1] = e.itemID end
      return out
    end

    it("finds the sales after the old entries and the entries bought back from among them", function()
      local a, b, c, d = entry(1), entry(2), entry(3), entry(4)
      local sold, back = GC.VendorSales.Diff({ a, b, c }, { a, c, d }, 12)
      assert.same({ 4 }, ids(sold))
      assert.same({ 2 }, ids(back))
    end)

    it("counts a stack equal to one already on the page as a sale of its own", function()
      local sold, back = GC.VendorSales.Diff({ entry(1), entry(2) }, { entry(1), entry(2), entry(1) }, 12)
      assert.same({ 1 }, ids(sold))
      assert.same({}, ids(back))
    end)

    it("pushes off the oldest of equal stacks on a full page, and never more than were sold", function()
      local before = { entry(7), entry(7) }
      for i = 3, 12 do before[i] = entry(i) end
      local after = {}
      for i = 2, 12 do after[#after + 1] = before[i] end
      after[12] = entry(99)
      local sold, back = GC.VendorSales.Diff(before, after, 12)
      assert.same({ 99 }, ids(sold))
      assert.same({}, ids(back))
      -- A page that is not full again drops nothing: its missing oldest was bought back.
      local short = {}
      for i = 2, 12 do short[#short + 1] = before[i] end
      sold, back = GC.VendorSales.Diff(before, short, 12)
      assert.same({}, ids(sold))
      assert.same({ 7 }, ids(back))
    end)
  end)
end)
