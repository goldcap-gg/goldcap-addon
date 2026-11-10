local helper = require("spec.spec_helper")

-- The order SELL settled on (GC.SellViewModel.Settle, S.rowPlaces) lasts the whole auction-house
-- visit. A press of REFRESH, a post's own refresh and coming back to the tab change the numbers on
-- the rows, never where the rows are: the owner pressed REFRESH and watched the list jump, and sat
-- in SELL and watched it jump again when one of those refreshes ran (owner, 2026-11-09).
describe("SELL keeps its order through a visit", function()
  local function load(now)
    _G.time = function() return now.value end
    _G.C_AuctionHouse = {
      QueryOwnedAuctions = function() end,
      GetOwnedAuctions = function() return {} end,
    }
    local GC = {
      Sell = {}, Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end },
      QuoteCache = { MAX_AGE_SECONDS = 10, Set = function() end, Clear = function() end },
      SellPositions = {
        NormalizeOwnedLots = function() return {} end,
        Build = function() return {
          { itemID = 42, positionKey = "commodity:42", bagQty = 5, displayMarketUnit = 900 },
          { itemID = 43, positionKey = "commodity:43", bagQty = 5, displayMarketUnit = 100 },
        } end,
      },
    }
    helper.loadModule("UI/SellViewModel.lua", GC)
    helper.loadSell(GC)
    GC.SellQuotes.driver = {
      isReady = function() return true end, keyInfo = function() return { isCommodity = true } end,
      send = function() end,
      item = function() return 111 end, itemLevels = function() return nil end,
      commodity = function() return 222 end, commodityLevels = function() return nil end,
    }
    return GC
  end
  after_each(function() _G.time, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil end)

  -- The cheap stack settled on top (its price came in first); by value it would now sort second.
  local function settled(GC)
    local places = GC.SellState.rowPlaces
    places["commodity:43"], places["commodity:42"] = 1, 2
  end
  local function drawn(GC)
    local keys = {}
    for _, position in ipairs(GC.SellViewModel.Settle(GC.SellViewModel.Order(GC.SellState.positions),
      GC.SellState.rowPlaces)) do
      keys[#keys + 1] = position.positionKey
    end
    return keys
  end

  it("a press of REFRESH leaves every row where it is", function()
    local GC = load({ value = 100 })
    settled(GC)
    GC.Sell.Refresh()
    assert.same({ "commodity:43", "commodity:42" }, drawn(GC))
  end)

  it("coming back to the tab, or opening the window again, leaves them too", function()
    local GC = load({ value = 100 })
    settled(GC)
    GC.Sell.Refresh(nil, true)
    assert.same({ "commodity:43", "commodity:42" }, drawn(GC))
  end)

  it("the refresh a post runs leaves them too", function()
    local GC = load({ value = 100 })
    settled(GC)
    GC.Sell._RefreshAfterPost()
    assert.same({ "commodity:43", "commodity:42" }, drawn(GC))
  end)

  it("the next visit sorts again: closing the auction house lets the order go", function()
    local GC = load({ value = 100 })
    settled(GC)
    GC.Sell.Reset()
    GC.Sell.Refresh(nil, true)
    assert.same({ "commodity:42", "commodity:43" }, drawn(GC))
  end)
end)
