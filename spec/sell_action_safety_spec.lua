local helper = require("spec.spec_helper")

describe("Sell protected action state", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function handlers(GC)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    return upvalue(render, "onPostClick"), upvalue(render, "onRepostClick")
  end

  local function button()
    return { Enable = function() end, Disable = function() end, SetLabel = function() end }
  end

  local function position()
    return { itemID = 42, positionKey = "commodity:42", trackedQty = 1, listedQty = 0,
      ownedLots = { { auctionID = 7, quantity = 1 } } }
  end

  before_each(function()
    _G.time = function() return 100 end
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_Timer = nil
  end)

  after_each(function()
    _G.time, _G.ItemLocation, _G.C_Timer, _G.C_AuctionHouse = os.time, nil, nil, nil
  end)

  it("does not call protected post APIs for a stale quote", function()
    local calls, refreshed = 0, false
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return nil end }, SellPositions = {} }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    set(post, "startQuoteRefreshFor", function() refreshed = true end)
    post({ position = position(), action = button() })
    assert.equal(0, calls)
    assert.is_true(refreshed)
  end)

  it("pins a post once and confirms exactly once from the same quote snapshot", function()
    local postCalls, confirmCalls = 0, 0
    _G.C_AuctionHouse = {
      PostCommodity = function() postCalls = postCalls + 1; return true end,
      ConfirmPostCommodity = function() confirmCalls = confirmCalls + 1 end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    set(post, "liveBagState", function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    set(post, "driver", { keyInfo = function() return { isCommodity = true } end })
    local row = { position = position(), action = button() }
    post(row); post(row); post(row)
    assert.equal(1, postCalls)
    assert.equal(1, confirmCalls)
  end)

  it("arms repost before cancelling and rejects a changed quote on confirmation", function()
    local cancelCalls = 0
    _G.C_AuctionHouse = { CancelAuction = function() cancelCalls = cancelCalls + 1 end }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID, fresh)
        return { positionKey = "commodity:42", auctionID = auctionID, quantity = 1, unitPrice = fresh.unit }
      end,
    } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local _, repost = handlers(GC)
    set(repost, "composePositions", function() end)
    set(repost, "currentPosition", function() return position() end)
    local row = { position = position(), action = button() }
    repost(row, 7)
    assert.equal(0, cancelCalls)
    row.repostReady = true
    quote = { unit = 201, at = 101 }
    repost(row, 7)
    assert.equal(0, cancelCalls)
  end)
end)
