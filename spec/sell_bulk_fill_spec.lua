local helper = require("spec.spec_helper")

-- The Sell tab's bulk price fill: one SearchForItemKeys batch for every commodity on the tab,
-- borrowed from UI/SniperFrame.lua's arbiter the way the BUY tab borrows it. What comes back is
-- a price to SHOW -- never one to post against.
describe("Sell bulk price fill", function()
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

  local function refreshState(GC) return upvalue(GC.Sell.OnThrottleReady, "refresh") end

  -- `asked` records what the arbiter was handed; `grant` is whether it lets the batch go.
  local function load(now, positions, asked, grant)
    _G.time = function() return now.value end
    _G.C_AuctionHouse = { QueryOwnedAuctions = function() asked.owned = (asked.owned or 0) + 1 end,
      GetOwnedAuctions = function() return {} end }
    local GC = {
      Sell = {},
      Sniper = {
        IsAHOpen = function() return true end, IsBusy = function() return false end,
        CurrentView = function() return asked.view or "sell" end,
        _TrySendKeysBatchFor = function(poll, who, wants)
          asked.calls = (asked.calls or 0) + 1
          if not (grant.value and wants() and poll:HasPending()) then return false end
          asked.who, asked.batch = who, poll.NextBatch()
          return true
        end,
      },
      QuoteCache = {
        MAX_AGE_SECONDS = 10,
        Set = function(store, itemID, unit, at) store[itemID] = { unit = unit, at = at } end,
        Fresh = function(store, itemID, at, maxAge)
          local quote = store[itemID]
          return quote and (at - quote.at) <= maxAge and quote or nil
        end,
        Clear = function() end,
      },
      SellPositions = { NormalizeOwnedLots = function() return {} end,
        Build = function() return positions end },
    }
    helper.loadModule("UI/SellFrame.lua", GC)
    set(upvalue(GC.Sell.OnThrottleReady, "advanceQuote"), "driver", {
      isReady = function() return true end, keyInfo = function() return { isCommodity = true } end,
      send = function(itemID) asked.searches = asked.searches or {}; asked.searches[#asked.searches + 1] = itemID end,
      item = function() return nil end, itemLevels = function() return nil end,
      commodity = function() return nil end, commodityLevels = function() return nil end,
    })
    -- tabIsLive wants the container on screen; these specs have no frames, so say it is.
    set(GC.Sell.TrySendBulk, "tabIsLive", function() return true end)
    return GC
  end

  after_each(function() _G.time, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil end)

  local STOCK = {
    { itemID = 42, positionKey = "commodity:42", bagQty = 5 },
    { itemID = 43, positionKey = "commodity:43", listedQty = 3 },
    { itemID = 42, positionKey = "commodity:42", bagQty = 1 },       -- same item twice: asked once
    { itemID = 50, positionKey = "item:50:100:0:0", bagQty = 1 },    -- a variant item: the walk's
    { itemID = 51, positionKey = "commodity:51" },                   -- nothing to act on
  }

  it("asks for every actionable commodity in one batch on a press of Refresh, under its own name", function()
    local now, asked = { value = 100 }, {}
    local GC = load(now, STOCK, asked, { value = true })
    GC.Sell.Refresh()
    assert.equal("sell", asked.who)
    assert.same({ 42, 43 }, asked.batch)
    -- The listings query gives the batch the first slot and takes the next ready tick.
    assert.is_nil(asked.owned)
    assert.equal("waiting_owned", refreshState(GC).phase)
    GC.Sell.OnThrottleReady()
    assert.equal(1, asked.owned)
  end)

  it("does not ask on the walk's own repeat, and asks once per press", function()
    local now, asked = { value = 100 }, {}
    local GC = load(now, STOCK, asked, { value = true })
    GC.Sell.Refresh(true)
    assert.is_nil(asked.who)
    GC.Sell.Refresh()
    assert.equal("sell", asked.who)
    asked.who = nil
    GC.Sell.Tick(); GC.Sell.Tick()
    assert.is_nil(asked.who)
  end)

  it("keeps asking from the ticker when the slot was taken at the moment of the press", function()
    local now, asked, grant = { value = 100 }, {}, { value = false }
    local GC = load(now, STOCK, asked, grant)
    GC.Sell.Refresh()
    assert.is_nil(asked.who)
    assert.equal(1, asked.owned) -- the press carried on with the listings query
    grant.value = true
    GC.Sell.Tick()
    assert.equal("sell", asked.who)
  end)

  it("never asks from another tab", function()
    local now, asked = { value = 100 }, { view = "deals" }
    local GC = load(now, STOCK, asked, { value = true })
    GC.Sell.Refresh()
    assert.is_nil(asked.who)
  end)

  it("caps the batch at the hundred keys one call may carry", function()
    local many = {}
    for id = 1, 140 do many[id] = { itemID = id, positionKey = "commodity:" .. id, bagQty = 1 } end
    local now, asked = { value = 100 }, {}
    local GC = load(now, many, asked, { value = true })
    GC.Sell.Refresh()
    assert.equal(100, #asked.batch)
  end)

  describe("folding the answer", function()
    local function folded(rows, before)
      local now, asked = { value = 100 }, {}
      local GC = load(now, STOCK, asked, { value = true })
      GC.Sell.Refresh()
      local quotes = upvalue(GC.Sell.FoldBulk, "quotes")
      for id, quote in pairs(before or {}) do quotes[id] = quote end
      GC.Sell.FoldBulk(rows)
      return quotes, GC, now, asked
    end

    it("prices the rows it was answered for, marked as a price to show", function()
      local quotes = folded({ { itemKey = { itemID = 42 }, minPrice = 1200, totalQuantity = 900 } })
      assert.equal(1200, quotes[42].unit)
      assert.is_true(quotes[42].bulk)
      assert.is_nil(quotes[43]) -- silence is not news: nothing invented for the item not mentioned
    end)

    it("leaves a row where the player is among the sellers to the walk", function()
      local quotes = folded({ { itemKey = { itemID = 42 }, minPrice = 1200, containsOwnerItem = true } })
      assert.is_nil(quotes[42])
    end)

    it("does not replace a real quote the walk still holds fresh", function()
      local quotes = folded({ { itemKey = { itemID = 42 }, minPrice = 1200 } },
        { [42] = { unit = 1500, at = 90 } })
      assert.equal(1500, quotes[42].unit)
      assert.is_nil(quotes[42].bulk)
    end)

    it("never backs a post: freshQuote refuses a bulk price and still takes a real one", function()
      local quotes, GC = folded({ { itemKey = { itemID = 42 }, minPrice = 1200 } },
        { [43] = { unit = 1500, at = 95 } })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      local freshQuote = upvalue(upvalue(render, "onPostClick"), "freshQuote")
      assert.is_true(quotes[42].bulk)
      assert.is_nil(freshQuote({ itemID = 42 }))
      assert.equal(1500, freshQuote({ itemID = 43 }).unit)
    end)

    it("is still owed a real quote by the walk, however young it is", function()
      local _, GC, _, asked = folded({ { itemKey = { itemID = 42 }, minPrice = 1200 } })
      -- The repeat that follows: 42 holds a one-second-old price, and is asked about anyway.
      refreshState(GC).phase = "done"
      GC.Sell.Refresh(true)
      local queued = {}
      for _, id in ipairs(refreshState(GC).queue) do queued[id] = true end
      assert.is_true(queued[42])
      assert.is_truthy(asked.searches)
    end)
  end)
end)
