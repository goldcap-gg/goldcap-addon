local helper = require("spec.spec_helper")

describe("Passive normal-AH purchase capture", function()
  local GC, hooks, results, now, timers, ownsCommodity, ownsAuction, captureApi, hookCalls

  local function fire(name, ...)
    assert.is_function(hooks[name])
    hooks[name](...)
  end

  before_each(function()
    hooks, results, timers, hookCalls = {}, {}, {}, 0
    now, ownsCommodity, ownsAuction = 100, false, false
    _G.C_AuctionHouse = {}
    GC = helper.loadModule("Core/Acquisitions.lua")
    GC.Acquisitions.Init({})
    GC.Sniper = {
      OwnsCommodityPurchase = function() return ownsCommodity end,
      OwnsAuctionPurchase = function() return ownsAuction end,
    }
    helper.loadModule("Core/PurchaseCapture.lua", GC)
    captureApi = {
      hooksecurefunc = function(_, name, callback)
        hookCalls = hookCalls + 1
        hooks[name] = callback
      end,
      getNumItemSearchResults = function() return #results end,
      getItemSearchResultInfo = function(_, index) return results[index] end,
      time = function() return now end,
      after = function(_, callback) timers[#timers + 1] = callback end,
    }
    GC.PurchaseCapture.Init(captureApi, function() return { char = "A-R", region = "eu" } end)
  end)

  after_each(function() _G.C_AuctionHouse = nil end)

  it("installs its three hooks only once", function()
    GC.PurchaseCapture.Init(captureApi, function() return { char = "A-R", region = "eu" } end)
    assert.equal(3, hookCalls)
  end)

  it("records a normal commodity only after confirm and success", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()

    local batch = GC.Acquisitions.GetAll()[1]
    assert.equal("auction_house", batch.source)
    assert.equal(3, batch.originalQty)
    assert.equal(301, batch.originalTotal)
    assert.equal("commodity:42", batch.positionKey)
  end)

  it("does not record an unconfirmed commodity quote", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("drops failures, unavailable quotes, and explicit resets without a cost", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPurchaseFailed()

    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUnavailable()

    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.Reset()
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()

    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("drops a mismatched commodity confirmation", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    fire("ConfirmCommoditiesPurchase", 42, 2)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("records one pending commodity observation when success lacks an exact final total", function()
    fire("StartCommoditiesPurchase", 42, 3)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()

    assert.equal(0, #GC.Acquisitions.GetAll())
    local pending = GC.Acquisitions.GetPending()[1]
    assert.equal(42, pending.itemID)
    assert.equal(3, pending.quantity)
    assert.equal("commodity:42", pending.positionKey)
  end)

  it("does not use a quote that arrives after commodity confirmation", function()
    fire("StartCommoditiesPurchase", 42, 3)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()

    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending())
  end)

  it("keeps a confirmed unavailable commodity as one pending observation", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUnavailable()
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()

    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending())
  end)

  it("drops an unconfirmed unavailable commodity without pending evidence", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUnavailable()
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("keeps two identical sequential commodity purchases distinct", function()
    for _ = 1, 2 do
      fire("StartCommoditiesPurchase", 42, 3)
      GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
      fire("ConfirmCommoditiesPurchase", 42, 3)
      GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
      now = now + 1
    end

    local batches = GC.Acquisitions.GetAll()
    assert.equal(2, #batches)
    assert.not_equal(batches[1].evidenceKeys, batches[2].evidenceKeys)
    local key1 = next(batches[1].evidenceKeys)
    local key2 = next(batches[2].evidenceKeys)
    assert.not_equal(key1, key2)
  end)

  it("clears an unfinished commodity attempt on its ownership timeout", function()
    fire("StartCommoditiesPurchase", 42, 3)
    assert.equal(1, #timers)
    timers[1]()
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("clears an unfinished item attempt on its ownership timeout", function()
    results[1] = { auctionID = 9001, quantity = 2, buyoutAmount = 100000 }
    GC.PurchaseCapture.OnItemSearchResults({ itemID = 77, itemLevel = 10,
      itemSuffix = 0, battlePetSpeciesID = 0 })
    fire("PlaceBid", 9001, 100000)
    timers[1]()
    GC.PurchaseCapture.OnPurchaseCompleted(9001)
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("indexes an item result and records only the matching completed auction", function()
    results[1] = { auctionID = 9001, quantity = 2, buyoutAmount = 100000 }
    GC.PurchaseCapture.OnItemSearchResults({ itemID = 77, itemLevel = 10,
      itemSuffix = 0, battlePetSpeciesID = 0 })
    fire("PlaceBid", 9001, 100000)
    GC.PurchaseCapture.OnPurchaseCompleted(9002)
    assert.equal(0, #GC.Acquisitions.GetAll())
    GC.PurchaseCapture.OnPurchaseCompleted(9001)
    local batch = GC.Acquisitions.GetAll()[1]
    assert.equal(100000, batch.originalTotal)
    assert.equal(2, batch.originalQty)
    assert.equal("item:77:10:0:0", batch.positionKey)
  end)

  it("keeps an item completion with incomplete identity as pending evidence", function()
    results[1] = { auctionID = 9001, quantity = 2, buyoutAmount = 100000 }
    GC.PurchaseCapture.OnItemSearchResults({ itemID = 77, itemLevel = 10,
      itemSuffix = 0 })
    fire("PlaceBid", 9001, 100000)
    GC.PurchaseCapture.OnPurchaseCompleted(9001)
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending())
  end)

  it("keeps an item completion with a nonmatching visible total as pending evidence", function()
    results[1] = { auctionID = 9001, quantity = 2, buyoutAmount = 100000 }
    GC.PurchaseCapture.OnItemSearchResults({ itemID = 77, itemLevel = 10,
      itemSuffix = 0, battlePetSpeciesID = 0 })
    fire("PlaceBid", 9001, 99999)
    GC.PurchaseCapture.OnPurchaseCompleted(9001)
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending())
  end)

  it("keeps an item completion with unknown quantity as pending evidence", function()
    results[1] = { auctionID = 9001, buyoutAmount = 100000 }
    GC.PurchaseCapture.OnItemSearchResults({ itemID = 77, itemLevel = 10,
      itemSuffix = 0, battlePetSpeciesID = 0 })
    fire("PlaceBid", 9001, 100000)
    GC.PurchaseCapture.OnPurchaseCompleted(9001)
    assert.equal(0, #GC.Acquisitions.GetAll())
    local pending = GC.Acquisitions.GetPending()[1]
    assert.equal(77, pending.itemID)
    assert.is_nil(pending.quantity)
  end)

  it("ignores every GoldCap-owned purchase hook", function()
    ownsCommodity = true
    fire("StartCommoditiesPurchase", 42, 3)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    ownsAuction = true
    results[1] = { auctionID = 9001, quantity = 2, buyoutAmount = 100000 }
    GC.PurchaseCapture.OnItemSearchResults({ itemID = 77, itemLevel = 10,
      itemSuffix = 0, battlePetSpeciesID = 0 })
    fire("PlaceBid", 9001, 100000)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    GC.PurchaseCapture.OnPurchaseCompleted(9001)
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("invalidates a stale passive commodity attempt when GoldCap owns the later lifecycle", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    ownsCommodity = true
    fire("StartCommoditiesPurchase", 42, 3)
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("invalidates a passive commodity attempt when GoldCap owns confirm", function()
    fire("StartCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPriceUpdated(100, 301)
    ownsCommodity = true
    fire("ConfirmCommoditiesPurchase", 42, 3)
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)
end)
