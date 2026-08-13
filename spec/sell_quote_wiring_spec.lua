local helper = require("spec.spec_helper")

describe("Sell quote wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local function section(text, first, last)
    local from = assert(text:find(first, 1, true), first)
    local to = assert(text:find(last, from + #first, true), last)
    return text:sub(from, to - 1)
  end

  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function setUpvalue(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function actionHandlers(GC)
    local renderRows = getUpvalue(GC.Sell.Refresh, "renderRows")
    local createRow = getUpvalue(renderRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onActionClick = getUpvalue(buildRowCell, "onActionClick")
    return getUpvalue(onActionClick, "onPostClick"), getUpvalue(onActionClick, "onRepostClick"),
      getUpvalue(buildRowCell, "onCancelConfirmClick")
  end

  it("uses QuoteCache.Get for rendering and every sell action, with no target fallback", function()
    local text = source()
    local render = section(text, "local function renderRows()", "-- ---------------------------------------------------------------------------\n-- Public entry points.")
    local post = section(text, "local function onPostClick(row)", "function GC.Sell.OnAuctionCreated")
    local repost = section(text, "local function onRepostClick(row)", "local function onCancelConfirmClick(row)")
    local itemResult = section(text, "function GC.Sell.OnItemSearchResults", "function GC.Sell.OnCommoditySearchResults")
    local commodityResult = section(text, "function GC.Sell.OnCommoditySearchResults", "-- ---------------------------------------------------------------------------\n-- Posting.")

    assert.is_truthy(render:find("GC.QuoteCache.Get(quotes, f.itemID, time())", 1, true))
    assert.is_truthy(post:find("GC.QuoteCache.Get(quotes, flip.itemID, time())", 1, true))
    assert.is_truthy(repost:find("GC.QuoteCache.Get(quotes, flip.itemID, time())", 1, true))
    assert.is_truthy(itemResult:find("GC.QuoteCache.Set(quotes, itemID, price, time())", 1, true))
    assert.is_truthy(commodityResult:find("GC.QuoteCache.Set(quotes, itemID, price, time())", 1, true))
    assert.is_nil(post:find("or flip.targetUnit", 1, true))
  end)

  it("deletes an old item quote when the live result is empty", function()
    _G.time = function() return 101 end
    local GC = { Sell = {}, Sniper = { IsBusy = function() return false end } }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)

    local quotes = getUpvalue(GC.Sell.OnItemSearchResults, "quotes")
    GC.QuoteCache.Set(quotes, 42, 12345, 100)
    setUpvalue(GC.Sell.OnItemSearchResults, "pendingQuote", 42)
    setUpvalue(GC.Sell.OnItemSearchResults, "driver", {
      itemResult = function() return nil end,
      isReady = function() return false end,
    })

    GC.Sell.OnItemSearchResults(42)

    assert.is_nil(GC.QuoteCache.Get(quotes, 42, 101))
    _G.time = os.time
  end)

  it("keeps bounded live-book depth on the same fresh quote entry", function()
    _G.time = function() return 101 end
    local GC = { Sell = {}, Sniper = { IsBusy = function() return false end } }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)

    local quotes = getUpvalue(GC.Sell.OnCommoditySearchResults, "quotes")
    setUpvalue(GC.Sell.OnCommoditySearchResults, "pendingQuote", 42)
    setUpvalue(GC.Sell.OnCommoditySearchResults, "driver", {
      commodityResult = function() return 12345 end,
      commodityBook = function() return { { unitPrice = 12345, quantity = 4 } } end,
      isReady = function() return false end,
    })

    GC.Sell.OnCommoditySearchResults(42)

    assert.equal(12345, GC.QuoteCache.Get(quotes, 42, 101))
    assert.same({ { unitPrice = 12345, quantity = 4 } }, quotes[42].levels)
    assert.equal(101, quotes[42].at)
    _G.time = os.time
  end)

  it("does not post or cancel from an eleven-second-old quote", function()
    local postCalls, cancelCalls = 0, 0
    local statusText
    _G.time = function() return 111 end
    _G.C_Container = {
      GetContainerNumSlots = function() return 1 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 1 } end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = false } end,
      PostItem = function() postCalls = postCalls + 1 end,
      CancelAuction = function() cancelCalls = cancelCalls + 1 end,
    }
    _G.C_Timer = { After = function() end }

    local GC = {
      Sell = {}, Sniper = { IsBusy = function() return false end },
      Flips = { CheapestOwnedLot = function() return { auctionID = 7, unitPrice = 20000 } end },
    }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    local onPostClick, onRepostClick, onCancelConfirmClick = actionHandlers(GC)
    local quotes = getUpvalue(onPostClick, "quotes")
    local setStatus = getUpvalue(onPostClick, "setStatus")
    setUpvalue(setStatus, "statusOwner", { status = { SetText = function(_, text) statusText = text end } })
    GC.QuoteCache.Set(quotes, 42, 20000, 100)

    local btn = {
      Disable = function() end, Enable = function() end, SetLabel = function() end,
      Hide = function() end, Show = function() end, IsEnabled = function() return true end,
    }
    local row = { flip = { itemID = 42, qty = 1, targetUnit = 999999 }, actionBtn = btn, cancelBtn = btn }

    onPostClick(row)
    onRepostClick(row)
    onCancelConfirmClick(row)

    assert.equal("Refresh prices first", statusText)
    assert.equal(0, postCalls)
    assert.equal(0, cancelCalls)
    _G.time, _G.C_Container, _G.ItemLocation, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil, nil, nil
  end)

  it("disarms an armed repost when its quote expires before cancel confirmation", function()
    local now, cancelCalls = 100, 0
    local statusText
    _G.time = function() return now end
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = false } end,
      CancelAuction = function() cancelCalls = cancelCalls + 1 end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(amount) return tostring(amount) end

    local GC = {
      Sell = {}, Sniper = { IsBusy = function() return false end },
      Flips = { CheapestOwnedLot = function() return { auctionID = 7, unitPrice = 20000 } end },
    }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    local onPostClick, onRepostClick, onCancelConfirmClick = actionHandlers(GC)
    local quotes = getUpvalue(onPostClick, "quotes")
    local setStatus = getUpvalue(onPostClick, "setStatus")
    setUpvalue(setStatus, "statusOwner", { status = { SetText = function(_, text) statusText = text end } })
    GC.QuoteCache.Set(quotes, 42, 20000, now)

    local btn = {
      Disable = function() end, Enable = function() end, SetLabel = function() end,
      Hide = function() end, Show = function() end, IsEnabled = function() return true end,
    }
    local row = { flip = { itemID = 42, qty = 1 }, actionBtn = btn, cancelBtn = btn }

    onRepostClick(row)
    assert.equal("armed", row.repostStage)
    assert.equal(0, cancelCalls)

    now = 111
    onCancelConfirmClick(row)

    assert.equal(0, cancelCalls)
    assert.is_nil(row.repostStage)
    assert.equal("Refresh prices first", statusText)
    _G.time, _G.C_AuctionHouse, _G.C_Timer, _G.GetCoinTextureString = os.time, nil, nil, nil
  end)

  it("does not confirm a post after its quote expires", function()
    local now, postCalls, confirmCalls = 100, 0, 0
    local statusText
    _G.time = function() return now end
    _G.C_Container = {
      GetContainerNumSlots = function() return 1 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 1 } end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = false } end,
      PostItem = function() postCalls = postCalls + 1; return true end,
      ConfirmPostItem = function() confirmCalls = confirmCalls + 1 end,
    }
    _G.C_Timer = { After = function() end }

    local GC = { Sell = {}, Sniper = { IsBusy = function() return false end } }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    local onPostClick = actionHandlers(GC)
    local quotes = getUpvalue(onPostClick, "quotes")
    local setStatus = getUpvalue(onPostClick, "setStatus")
    setUpvalue(setStatus, "statusOwner", { status = { SetText = function(_, text) statusText = text end } })
    GC.QuoteCache.Set(quotes, 42, 20000, now)

    local btn = { Disable = function() end, Enable = function() end, SetLabel = function() end }
    local row = { flip = { itemID = 42, qty = 1 }, actionBtn = btn }
    onPostClick(row)
    now = 111
    onPostClick(row)

    assert.equal(1, postCalls)
    assert.equal(0, confirmCalls)
    assert.equal("Refresh prices first", statusText)
    _G.time, _G.C_Container, _G.ItemLocation, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil, nil, nil
  end)

  it("observes commodity and exact item-variant owned positions in the current character scope", function()
    local observed = {}
    _G.time = function() return 777 end
    _G.C_Item = { GetItemNameByID = function(itemID) return itemID == 42 and "Ore" or "Variant" end }
    _G.C_AuctionHouse = { GetOwnedAuctions = function() return { { itemID = 42 }, { itemID = 7 } } end }
    local GC = {
      Sell = {}, Sniper = {}, Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Flips = { ExtractOwnedLots = function()
        return {
          { itemID = 42, itemKey = { itemID = 42 }, isCommodity = true, quantity = 2 },
          { itemID = 7, itemKey = { itemID = 7, itemLevel = 447, itemSuffix = 3, battlePetSpeciesID = 0 },
            isCommodity = false, quantity = 1 },
        }
      end },
      Acquisitions = {
        PositionKey = function(itemID, itemKey, isCommodity)
          if isCommodity then return "commodity:" .. itemID end
          return ("item:%d:%d:%d:%d"):format(itemID, itemKey.itemLevel, itemKey.itemSuffix, itemKey.battlePetSpeciesID)
        end,
        ObserveOwnedPosition = function(...) observed[#observed + 1] = { ... } end,
      },
    }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)

    GC.Sell.OnOwnedAuctions()

    assert.same({
      { "commodity:42", 42, "Ore", "A-R", "eu", 777 },
      { "item:7:447:3:0", 7, "Variant", "A-R", "eu", 777 },
    }, observed)
    _G.time, _G.C_Item, _G.C_AuctionHouse = os.time, nil, nil
  end)

  it("records only the position key pinned at a successful hardware-click post", function()
    local recorded, now = {}, 100
    _G.time = function() return now end
    _G.C_Item = { GetItemNameByID = function() return "Variant" end }
    _G.C_Container = {
      GetContainerNumSlots = function() return 1 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 1 } end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = false } end,
      PostItem = function() return false end,
    }
    _G.C_Timer = { After = function() end }
    local flip = { itemID = 42, qty = 1 }
    local GC = {
      Sell = {}, Sniper = {},
      QuoteCache = nil,
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Data = { GetFlips = function() return { flip } end, MarkFlipPosted = function() end,
        RecordPostEvent = function() end, GetItemValue = function() end },
      Acquisitions = { RecordPost = function(...) recorded[#recorded + 1] = { ... } end },
    }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    local onPostClick = actionHandlers(GC)
    local quotes = getUpvalue(onPostClick, "quotes")
    GC.QuoteCache.Set(quotes, 42, 20000, now)
    local btn = { Disable = function() end, Enable = function() end, SetLabel = function() end }
    local row = { flip = flip, position = { positionKey = "item:42:447:3:0" }, actionBtn = btn }

    onPostClick(row)
    GC.Sell.OnAuctionCreated()

    assert.same({ { "item:42:447:3:0", 42, "Variant", "A-R", "eu", 1, 100 } }, recorded)
    _G.time, _G.C_Item, _G.C_Container, _G.ItemLocation, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil, nil, nil, nil
  end)

  it("clears a pinned post without recording it on post error or auction-house reset", function()
    local recorded, now = {}, 100
    _G.time = function() return now end
    _G.C_Item = { GetItemNameByID = function() return "Variant" end }
    _G.C_Container = {
      GetContainerNumSlots = function() return 1 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 1 } end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = false } end,
      PostItem = function() return false end,
    }
    _G.C_Timer = { After = function() end }
    local flip = { itemID = 42, qty = 1 }
    local GC = {
      Sell = {}, Sniper = {}, Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Data = { GetFlips = function() return { flip } end, MarkFlipPosted = function() end,
        RecordPostEvent = function() end, GetItemValue = function() end },
      Acquisitions = { RecordPost = function(...) recorded[#recorded + 1] = { ... } end },
    }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    local onPostClick = actionHandlers(GC)
    local quotes = getUpvalue(onPostClick, "quotes")
    GC.QuoteCache.Set(quotes, 42, 20000, now)
    local btn = { Disable = function() end, Enable = function() end, SetLabel = function() end }
    local row = { flip = flip, position = { positionKey = "item:42:447:3:0" }, actionBtn = btn }

    onPostClick(row)
    GC.Sell.OnPostError()
    GC.Sell.OnAuctionCreated()
    onPostClick(row)
    GC.Sell.Reset()
    GC.Sell.OnAuctionCreated()

    assert.same({}, recorded)
    _G.time, _G.C_Item, _G.C_Container, _G.ItemLocation, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil, nil, nil, nil
  end)

  it("clears sell quotes when the auction house closes", function()
    local GC = { Sell = {} }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    local quotes = getUpvalue(GC.Sell.OnCommoditySearchResults, "quotes")
    GC.QuoteCache.Set(quotes, 42, 12345, 100)

    GC.Sell.Reset()

    assert.is_nil(GC.QuoteCache.Get(quotes, 42, 100))
  end)

  it("supplies a fresh ten-second cache quote to BuildRow", function()
    local GC = {}
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 1000, 100)

    local row = GC.Flips.BuildRow({ itemID = 42, qty = 1, paidUnit = 100, paidTotal = 100 }, {},
      { unit = GC.QuoteCache.Get(cache, 42, 110) }, {})

    assert.equal(1000, row.marketUnit)
    assert.equal(850, row.profit)
  end)

  it("gives BuildRow no quote or projected profit after eleven seconds", function()
    local GC = {}
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 1000, 100)

    local quote = GC.QuoteCache.Get(cache, 42, 111)
    local row = GC.Flips.BuildRow({ itemID = 42, qty = 1, paidUnit = 100, paidTotal = 100 }, {},
      quote and { unit = quote } or nil, {})

    assert.is_nil(row.marketUnit)
    assert.is_nil(row.profit)
  end)
end)
