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

  local function liveBagState(post)
    return upvalue(post, "liveBagState")
  end

  local function button()
    local value = { enabled = true }
    function value:Enable() self.enabled = true end
    function value:Disable() self.enabled = false end
    function value:SetLabel(label) self.label = label end
    return value
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
    _G.time, _G.ItemLocation, _G.C_Timer, _G.C_AuctionHouse, _G.C_Container, _G.C_Item = os.time, nil, nil, nil, nil, nil
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

  it("fails closed for a malformed Fresh quote before building a post", function()
    local calls = 0
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 0, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", itemID = 42, quantity = 1, unitPrice = 1 } end,
    } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    set(post, "liveBagState", function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, positionKey = "commodity:42" } end)
    set(post, "driver", { keyInfo = function() return { isCommodity = true } end })
    set(post, "startQuoteRefreshFor", function() end)
    post({ position = position(), action = button() })
    assert.equal(0, calls)
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

  it("attributes a successful post once and restores its pinned row", function()
    local records, refreshes = {}, 0
    _G.C_AuctionHouse = { PostCommodity = function() return false end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    }, Acquisitions = { RecordPost = function(...) records[#records + 1] = { ... } end },
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end } }
    helper.loadModule("UI/SellFrame.lua", GC)
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local post = handlers(GC)
    set(post, "liveBagState", function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    set(post, "driver", { keyInfo = function() return { isCommodity = true } end })
    local row = { position = position(), action = button() }
    post(row)
    GC.Sell.OnAuctionCreated()
    assert.same({ "commodity:42", 42, "Item 42", "A-R", "eu", 1, 100 }, records[1])
    assert.is_nil(row.postStage)
    assert.is_true(row.action.enabled)
    assert.equal("Post", row.action.label)
    assert.equal(1, refreshes)
  end)

  it("clears a confirmation pin when the fresh quote changes", function()
    local posts, confirms, refreshes = 0, 0, 0
    _G.C_AuctionHouse = { PostCommodity = function() posts = posts + 1; return true end,
      ConfirmPostCommodity = function() confirms = confirms + 1 end }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    set(post, "liveBagState", function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    set(post, "driver", { keyInfo = function() return { isCommodity = true } end })
    set(post, "startQuoteRefreshFor", function() refreshes = refreshes + 1 end)
    local row = { position = position(), action = button() }
    post(row)
    quote = { unit = 201, at = 101 }
    post(row)
    assert.equal(1, posts); assert.equal(0, confirms); assert.equal(1, refreshes)
    assert.is_nil(row.postStage); assert.equal("Post", row.action.label); assert.is_true(row.action.enabled)
  end)

  it("resets an in-flight post without recording activity", function()
    local records = 0
    _G.C_AuctionHouse = { PostCommodity = function() return false end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end, Clear = function() end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    }, Acquisitions = { RecordPost = function() records = records + 1 end } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    set(post, "liveBagState", function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    set(post, "driver", { keyInfo = function() return { isCommodity = true } end })
    local row = { position = position(), action = button() }
    post(row)
    assert.is_false(row.action.enabled)
    GC.Sell.Reset()
    assert.is_nil(row.postStage); assert.is_true(row.action.enabled); assert.equal("Post", row.action.label)
    GC.Sell.OnAuctionCreated()
    assert.equal(0, records)
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

  it("reacquires the owned-auction snapshot before cancelling an armed repost", function()
    local cancelCalls, ownedReads = 0, 0
    _G.C_AuctionHouse = {
      CancelAuction = function() cancelCalls = cancelCalls + 1 end,
      GetOwnedAuctions = function() ownedReads = ownedReads + 1; return { { auctionID = 7 } } end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID, fresh) return { positionKey = "commodity:42", auctionID = auctionID, quantity = 1, unitPrice = fresh.unit } end,
      NormalizeOwnedLots = function() return { { positionKey = "commodity:42", auctionID = 7, quantity = 1 } } end,
    } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local _, repost = handlers(GC)
    set(repost, "composePositions", function() end)
    set(repost, "currentPosition", function() return position() end)
    local row = { position = position(), action = button() }
    repost(row, 7)
    row.repostReady = true
    repost(row, 7)
    assert.equal(1, ownedReads)
    assert.equal(1, cancelCalls)
  end)

  it("reset disarms a repost without cancelling", function()
    local cancels = 0
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end, Clear = function() end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID, fresh) return { positionKey = "commodity:42", auctionID = auctionID, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadModule("UI/SellFrame.lua", GC)
    local _, repost = handlers(GC)
    local row = { position = position(), action = button() }
    repost(row, 7)
    assert.equal("armed", row.repostStage)
    GC.Sell.Reset()
    assert.is_nil(row.repostStage); assert.equal("Repost", row.action.label); assert.is_true(row.action.enabled)
    assert.equal(0, cancels)
  end)

  it("keeps exact commodity stack aggregate and rejects bonus-bearing normal links", function()
    local stacks = {
      [1] = { itemID = 42, stackCount = 2 }, [2] = { itemID = 42, stackCount = 3 },
    }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot) return stacks[slot] end,
      GetContainerItemLink = function() return "item:42:0:0:0:0:0:7:0:0:0:0:0:1:999" end,
    }
    _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
    local GC = { Sell = {}, QuoteCache = {}, SellPositions = {} }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    assert.equal(5, liveBagState(post)({ itemID = 42, positionKey = "commodity:42" }).exactQty)
    local normal = liveBagState(post)({ itemID = 42, positionKey = "item:42:100:7:0" })
    assert.is_nil(normal.bag)
  end)

  it("accepts a normal identity with empty fixed link fields", function()
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 2 } end,
      GetContainerItemLink = function() return "item:42:0::0:0:0:7:0:0:0:0:0:0" end,
    }
    _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
    local GC = { Sell = {}, QuoteCache = {}, SellPositions = {} }
    helper.loadModule("UI/SellFrame.lua", GC)
    local post = handlers(GC)
    local state = liveBagState(post)({ itemID = 42, positionKey = "item:42:100:7:0" })
    assert.equal(2, state.exactQty)
    assert.equal("item:42:100:7:0", state.positionKey)
  end)
end)
