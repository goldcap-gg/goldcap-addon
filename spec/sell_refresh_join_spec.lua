local helper = require("spec.spec_helper")

describe("Sell refresh pressed while a full pass is reading books", function()
  local function load(now, sent)
    _G.time = function() return now.value end
    _G.C_AuctionHouse = {
      QueryOwnedAuctions = function() sent.owned = sent.owned + 1 end,
      GetOwnedAuctions = function() return {} end,
    }
    local GC = {
      Sell = {}, Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end },
      QuoteCache = { MAX_AGE_SECONDS = 10, Set = function() end, Clear = function() end },
      SellPositions = {
        NormalizeOwnedLots = function() return {} end,
        Build = function() return {
          { itemID = 42, positionKey = "commodity:42", bagQty = 5 },
          { itemID = 43, positionKey = "commodity:43", bagQty = 5 },
          { itemID = 44, positionKey = "commodity:44", bagQty = 5 },
        } end,
      },
    }
    helper.loadSell(GC)
    GC.SellQuotes.driver = {
      isReady = function() return true end, keyInfo = function() return { isCommodity = true } end,
      send = function(itemID) sent.keys[#sent.keys + 1] = itemID end,
      item = function() return 111 end, itemLevels = function() return nil end,
      commodity = function() return 222 end, commodityLevels = function() return nil end,
    }
    return GC
  end
  after_each(function() _G.time, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil end)

  it("a press while the walk reads books keeps the pass, its place and its count", function()
    local now, sent = { value = 100 }, { owned = 0, keys = {} }
    local GC = load(now, sent)
    local refresh = GC.SellState.refresh
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    GC.Sell.OnCommoditySearchResults(42)
    assert.same({ 42, 43 }, sent.keys)
    assert.equal(2, refresh.index)
    local generation, queue = refresh.generation, refresh.queue
    now.value = 105
    GC.Sell.Refresh() -- pressed again five seconds later, mid-pass
    -- what the player should get: the same pass carrying on
    assert.equal(1, sent.owned)
    assert.equal(generation, refresh.generation)
    assert.equal(queue, refresh.queue)
    assert.equal(2, refresh.index)
    GC.Sell.OnCommoditySearchResults(43) -- the answer on the wire is still the pass's
    assert.same({ 42, 43, 44 }, sent.keys)
  end)
end)

describe("Sell refresh button and listings query across a mid-pass refresh", function()
  local function load(now, sent)
    _G.time = function() return now.value end
    _G.C_AuctionHouse = {
      QueryOwnedAuctions = function() sent.owned = sent.owned + 1 end,
      GetOwnedAuctions = function() return {} end,
    }
    local GC = {
      Sell = {}, Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end },
      QuoteCache = { MAX_AGE_SECONDS = 10, Set = function() end, Clear = function() end },
      SellPositions = { NormalizeOwnedLots = function() return {} end,
        Build = function() return {
          { itemID = 42, positionKey = "commodity:42", bagQty = 5 },
          { itemID = 43, positionKey = "commodity:43", bagQty = 5 },
        } end },
    }
    helper.loadSell(GC)
    GC.SellQuotes.driver = {
      isReady = function() return true end, keyInfo = function() return { isCommodity = true } end,
      send = function(itemID) sent.keys[#sent.keys + 1] = itemID end,
      item = function() return 111 end, itemLevels = function() return nil end,
      commodity = function() return 222 end, commodityLevels = function() return nil end,
    }
    return GC
  end
  after_each(function() _G.time, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil end)

  it("a press mid-walk leaves the button's count where it was", function()
    local now, sent = { value = 100 }, { owned = 0, keys = {} }
    local GC = load(now, sent)
    GC.Sell.Refresh(true)
    local button = { SetLabel = function(self, label) self.label = label end }
    GC.SellUI.container = { refreshButton = button }
    GC.SellUI.Toolbar.PaintRefreshButton()
    assert.equal("PRICING 1/2", button.label)
    now.value = 105
    GC.Sell.Refresh()
    GC.SellUI.Toolbar.PaintRefreshButton()
    assert.equal("PRICING 1/2", button.label)
  end)

  it("a post's refresh mid-walk still asks for the listings, once the slot is free", function()
    local now, sent = { value = 100 }, { owned = 0, keys = {} }
    local GC = load(now, sent)
    GC.Sell.Refresh(true)
    assert.equal(0, sent.owned)
    GC.Sell.Refresh() -- what GC.Sell._RefreshAfterPost does on the tab
    GC.Sell.Tick()
    assert.is_true(sent.owned >= 1)
  end)
end)
