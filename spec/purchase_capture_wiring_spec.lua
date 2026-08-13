describe("Purchase capture wiring", function()
  local function source(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  it("installs exactly the three passive post-call hooks", function()
    local text = source("GoldCap/Core/PurchaseCapture.lua")
    assert.equal(3, select(2, text:gsub("api%.hooksecurefunc", "")))
    assert.is_truthy(text:find('api.hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", onCommodityStart)', 1, true))
    assert.is_truthy(text:find('api.hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", onCommodityConfirm)', 1, true))
    assert.is_truthy(text:find('api.hooksecurefunc(C_AuctionHouse, "PlaceBid", onPlaceBid)', 1, true))
  end)

  it("fans every purchase event out to Sniper and PurchaseCapture", function()
    local text = source("GoldCap/Core/Init.lua")
    for _, method in ipairs({ "OnItemSearchResults", "OnPurchaseCompleted", "OnCommodityPriceUpdated",
      "OnCommodityPriceUnavailable", "OnCommodityPurchaseSucceeded", "OnCommodityPurchaseFailed", "Reset" }) do
      assert.is_truthy(text:find("GC.PurchaseCapture." .. method, 1, true), method)
    end
  end)

  it("exposes read-only, exact Sniper ownership inspectors", function()
    local text = source("GoldCap/UI/SniperFrame.lua")
    assert.is_truthy(text:find("function GC.Sniper.OwnsCommodityPurchase", 1, true))
    assert.is_truthy(text:find("function GC.Sniper.OwnsAuctionPurchase", 1, true))
  end)

  it("loads PurchaseCapture after Acquisitions and before Init", function()
    local toc = source("GoldCap/GoldCap.toc")
    local acquisitions = assert(toc:find("Core/Acquisitions.lua", 1, true))
    local capture = assert(toc:find("Core/PurchaseCapture.lua", 1, true))
    local init = assert(toc:find("Core/Init.lua", 1, true))
    assert.is_true(acquisitions < capture)
    assert.is_true(capture < init)
  end)
end)
