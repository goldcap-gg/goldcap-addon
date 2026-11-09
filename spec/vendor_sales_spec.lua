local helper = require("spec.spec_helper")

-- Core/VendorSales.lua (WoW: Forever only): a stack sold to a merchant spends the purchase lots it
-- came from, read off the merchant's buyback list. The merchant is an API-shaped fake: the client's
-- GetNumBuybackItems, GetBuybackItemInfo (exactly name, texture, price, quantity, numAvailable,
-- isUsable, isBound, as Blizzard's MerchantFrame.lua reads it), GetBuybackItemLink and
-- C_MerchantFrame.GetBuybackItemID, plus MerchantFrame:IsShown(); and the bags, through
-- C_Container.GetContainerNumSlots and GetContainerItemInfo (itemID and stackCount, fields the real
-- ContainerItemInfo has). A sale takes its units out of the bags and a buyback puts them back. The
-- acquisition store is the real one. The sale is booked when the merchant closes, as Core/Init.lua
-- forwards MERCHANT_CLOSED, and only for units that left the bags during the visit.
describe("merchant sales spend purchase lots", function()
  local GC, db, shelf, ledgerRows, bag, hidden
  local me = { char = "Seller-Realm", region = "110" }

  local function link(itemID, suffix)
    return ("|cffffffff|Hitem:%d::::::%s:::::::::|h[Item %d]|h|r"):format(itemID, suffix or "", itemID)
  end

  local function hold(itemID, count) bag[itemID] = count end

  -- The merchant's buyback page: oldest first, the newest sale last, twelve at most.
  local function sell(itemID, quantity, price, suffix)
    assert((bag[itemID] or 0) >= quantity, "the bags do not hold what the test sells")
    bag[itemID] = bag[itemID] - quantity
    shelf[#shelf + 1] = { itemID = itemID, quantity = quantity, price = price, link = link(itemID, suffix) }
    if #shelf > 12 then table.remove(shelf, 1) end
  end

  local function buyBack(index)
    local entry = table.remove(shelf, index)
    bag[entry.itemID] = (bag[entry.itemID] or 0) + entry.quantity
  end

  -- The bags as one backpack of stacks, in item order.
  local function slots()
    local out = {}
    for itemID, count in pairs(bag) do
      if count > 0 then out[#out + 1] = { itemID = itemID, stackCount = count } end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
  end

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
    shelf, bag, hidden = {}, {}, false
    _G.GetNumBuybackItems = function() return hidden and 0 or #shelf end
    _G.GetBuybackItemInfo = function(index)
      local entry = shelf[index]
      if not entry then return nil end
      return "Item " .. entry.itemID, 134400, entry.price, entry.quantity, -1, true, false
    end
    _G.GetBuybackItemLink = function(index) return shelf[index] and shelf[index].link end
    _G.C_MerchantFrame = { GetBuybackItemID = function(index) return shelf[index] and shelf[index].itemID end }
    _G.MerchantFrame = { shown = true }
    function _G.MerchantFrame:IsShown() return self.shown end
    _G.C_Container = {
      GetContainerNumSlots = function(index) return index == 0 and #slots() or 0 end,
      GetContainerItemInfo = function(index, slot) return index == 0 and slots()[slot] or nil end,
    }
    GC.VendorSales.Install()
  end)

  after_each(function()
    _G.GetNumBuybackItems, _G.GetBuybackItemInfo, _G.GetBuybackItemLink = nil, nil, nil
    _G.C_MerchantFrame, _G.MerchantFrame, _G.C_Container = nil, nil, nil
  end)

  it("books a stack sold to a merchant against the oldest purchase of the item, once", function()
    local batch = lot()
    hold(1206, 4)
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
    hold(1206, 6)
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

  it("books nothing net for a stack bought back before the merchant closed", function()
    local batch = lot()
    hold(1206, 4)
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
    hold(1206, 4)
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
    hold(1206, 4)
    for i = 1, 11 do hold(9000 + i, 1) end
    hold(9100, 1)
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
    hold(1206, 4)
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(201)
    _G.MerchantFrame.shown = false
    shelf = {}
    GC.VendorSales.OnChanged(202) -- not "everything was bought back"
    GC.VendorSales.OnClosed(203)
    assert.equal(0, batch.remainingQty)
    assert.equal(1, #saleKeys())
    hold(1206, 4)
    sell(1206, 4, 1600)
    GC.VendorSales.OnChanged(204) -- no visit open: says nothing
    GC.VendorSales.OnClosed(205)
    assert.equal(1, #saleKeys())
  end)

  it("takes a list still empty at the door for the last visit's, not as everything new", function()
    lot({ quantity = 8, total = 2880 })
    hold(1206, 8)
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
    hold(1206, 4)
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
    hold(2632, 2)
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
    hold(1206, 4)
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
    hold(1206, 4)
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
    hold(1206, 4)
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    _G.C_MerchantFrame.GetBuybackItemID = function() return nil end
    shelf[1].link = nil
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(4, batch.remainingQty)
  end)

  -- After a /reload the session's buyback page is still the server's, but the first read at the door
  -- can come back empty: the stacks sold before the reload then appear a tick later as if new.
  it("books nothing for a page that fills after the door while the bags did not move", function()
    local batch = lot()
    hold(1206, 4)
    shelf = { { itemID = 1206, quantity = 4, price = 1600, link = link(1206) } } -- sold before the reload
    hidden = true
    GC.VendorSales.OnShow(200)
    hidden = false
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(4, batch.remainingQty)
    assert.equal(0, #saleKeys())
  end)

  it("books no more units than left the bags, at their share of the price", function()
    local batch = lot()
    hold(1206, 4)
    GC.VendorSales.OnShow(200)
    sell(1206, 4, 1600)
    hold(1206, 2) -- the bags lost two of the four the page names
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.equal(2, batch.remainingQty)
    local realized = GC.Acquisitions.GetRealized(me)[1]
    assert.equal(2, realized.quantity)
    assert.equal(800, realized.proceeds)
  end)

  it("counts what this merchant sold the player during the visit as units the bags could lose", function()
    GC.VendorSales.OnShow(200)
    -- Core/VendorBuys.lua books a merchant purchase once the bags show it: 4 vials, 8c each.
    local vials = lot({ source = "vendor", itemID = 3371, positionKey = "commodity:3371", itemName = "Empty Vial",
      quantity = 4, total = 32, acquiredAt = 201 })
    hold(3371, 4)
    GC.VendorSales.OnChanged(201)
    sell(3371, 4, 4)
    GC.VendorSales.OnChanged(202)
    GC.VendorSales.OnClosed(203)
    assert.equal(0, vials.remainingQty)
  end)

  it("books every sale of a visit even when one booking fails", function()
    local booked = {}
    local page, counts = {}, { [1] = 1, [2] = 1 }
    GC.VendorSales.SetDriver({
      open = function() return true end,
      buyback = function() return page end,
      bags = function() return counts end,
      record = function(sale)
        if sale.itemID == 1 then error("store refused") end
        booked[#booked + 1] = sale.itemID
      end,
    })
    GC.VendorSales.OnShow(200)
    page = { { itemID = 1, quantity = 1, price = 5 }, { itemID = 2, quantity = 1, price = 5 } }
    counts = {}
    GC.VendorSales.OnChanged(201)
    GC.VendorSales.OnClosed(202)
    assert.same({ 2 }, booked)
  end)

  describe("the bags' word on a visit's sales", function()
    local function sale(itemID, quantity, price) return { itemID = itemID, quantity = quantity, price = price, at = 1 } end
    local function units(list)
      local out = {}
      for _, s in ipairs(list) do out[#out + 1] = s.itemID .. "x" .. s.quantity .. "@" .. s.price end
      return out
    end

    it("lets a sale through only for the units that left the bags, oldest sale first", function()
      local sales = { sale(1, 4, 400), sale(1, 4, 400), sale(2, 1, 9) }
      assert.same({ "1x4@400", "1x2@200", "2x1@9" },
        units(GC.VendorSales.Corroborate(sales, { [1] = 8, [2] = 1 }, { [1] = 2 }, {})))
    end)

    it("lets nothing through for an item the bags did not lose, or got back", function()
      local sales = { sale(1, 4, 400), sale(3, 2, 10) }
      assert.same({}, units(GC.VendorSales.Corroborate(sales, { [1] = 4 }, { [1] = 4 }, {})))
      assert.same({}, units(GC.VendorSales.Corroborate(sales, { [1] = 4 }, { [1] = 6 }, {})))
    end)

    it("adds what the merchant sold the player during the visit to what the bags could lose", function()
      assert.same({ "1x3@30" }, units(GC.VendorSales.Corroborate({ sale(1, 3, 30) }, {}, {}, { [1] = 3 })))
    end)
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
