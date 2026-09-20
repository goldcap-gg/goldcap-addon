local helper = require("spec.spec_helper")

-- A /reload wipes `quotes` (see SellFrame.lua's own module-local declaration): it is never
-- persisted, so every MARKET/UNIT cell used to show "-" and the expansion "quote ?s" for
-- minutes after every reload, until the pricing walk repopulated it from scratch. The display
-- path was already safe for old data -- SellPositions' quoteInfo reads GC.QuoteCache.Latest
-- (no age bound) and the renderer appends " . stale %ds" when a quote is not fresh -- so
-- restoring old quotes at load time is honest by construction; only Post/Repost stay gated on
-- GC.QuoteCache.Fresh's 45s window (SELL_QUOTE_ACTION_AGE), untouched by any of this.
describe("Sell quote persistence across a reload", function()
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

  after_each(function()
    _G.time, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil
  end)

  describe("seeding on the first compose after a reload", function()
    local function load(now)
      _G.time = function() return now.value end
      local GC = {
        Sell = {},
        SellPositions = { Build = function() return {} end },
      }
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("UI/SellFrame.lua", GC)
      return GC
    end

    local function compose(GC)
      upvalue(GC.Sell.SellableCount, "composePositions")()
    end

    local function quotesTable(GC)
      return upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    end

    it("seeds a valid persisted entry into the live quote cache, and leaves it in the store", function()
      local now = { value = 100000 }
      local GC = load(now)
      GC.db = { sellQuotes = { [42] = { unit = 1500, at = now.value - 100 } } }
      compose(GC)
      -- Marked bookless: the store keeps a unit and its date, never the levels, so the walk
      -- still owes this quote a real answer however young it is. The store itself is untouched.
      assert.same({ unit = 1500, at = now.value - 100, bookless = true }, quotesTable(GC)[42])
      assert.same({ unit = 1500, at = now.value - 100 }, GC.db.sellQuotes[42])
    end)

    it("drops an expired persisted entry from both the live cache and the store", function()
      local now = { value = 100000 }
      local GC = load(now)
      local tooOld = now.value - (3 * 24 * 60 * 60) - 10
      GC.db = { sellQuotes = { [42] = { unit = 1500, at = tooOld } } }
      compose(GC)
      assert.is_nil(quotesTable(GC)[42])
      assert.is_nil(GC.db.sellQuotes[42])
    end)

    it("drops a garbage entry (negative unit) from the store without seeding it", function()
      local now = { value = 100000 }
      local GC = load(now)
      GC.db = { sellQuotes = { [42] = { unit = -5, at = now.value } } }
      compose(GC)
      assert.is_nil(quotesTable(GC)[42])
      assert.is_nil(GC.db.sellQuotes[42])
    end)

    it("drops a garbage entry (an 'at' in the future) from the store without seeding it", function()
      local now = { value = 100000 }
      local GC = load(now)
      GC.db = { sellQuotes = { [42] = { unit = 1500, at = now.value + 500 } } }
      compose(GC)
      assert.is_nil(quotesTable(GC)[42])
      assert.is_nil(GC.db.sellQuotes[42])
    end)

    it("never overwrites an existing in-memory quote with a persisted one", function()
      local now = { value = 100000 }
      local GC = load(now)
      GC.db = { sellQuotes = { [42] = { unit = 1500, at = now.value - 100 } } }
      -- A live answer this session already produced before the first compose ever ran.
      quotesTable(GC)[42] = { unit = 999, at = now.value - 5 }
      compose(GC)
      assert.same({ unit = 999, at = now.value - 5 }, quotesTable(GC)[42])
    end)

    it("seeds only once: a store entry added after the first compose is not picked up later", function()
      local now = { value = 100000 }
      local GC = load(now)
      GC.db = { sellQuotes = {} }
      compose(GC) -- first compose ever: store is empty, but seeding is now one-shot
      GC.db.sellQuotes[42] = { unit = 1500, at = now.value - 100 }
      compose(GC)
      assert.is_nil(quotesTable(GC)[42])
    end)

    it("skips seeding while GC.db does not exist yet, and seeds once it appears", function()
      local now = { value = 100000 }
      local GC = load(now)
      compose(GC) -- GC.db is nil: composes fine, nothing to seed from
      assert.is_nil(quotesTable(GC)[42])
      GC.db = { sellQuotes = { [42] = { unit = 1500, at = now.value - 100 } } }
      compose(GC)
      assert.same({ unit = 1500, at = now.value - 100, bookless = true }, quotesTable(GC)[42])
    end)
  end)

  describe("write-through from the pricing walk", function()
    local function load(now, sent, keyInfo, driverOverrides)
      _G.time = function() return now.value end
      _G.C_AuctionHouse = {
        QueryOwnedAuctions = function() sent.owned = sent.owned + 1 end,
        GetOwnedAuctions = function() return {} end,
      }
      local GC = {
        Sell = {}, Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end },
        SellPositions = {
          NormalizeOwnedLots = function() return {} end,
          Build = function() return { { itemID = 42, positionKey = "commodity:42", bagQty = 5 } } end,
        },
      }
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("UI/SellFrame.lua", GC)
      local driver = {
        isReady = function() return true end,
        keyInfo = keyInfo,
        send = function(itemID) sent.keys[#sent.keys + 1] = itemID end,
        item = function() return nil end, itemLevels = function() return nil end,
        commodity = function() return 111 end, commodityLevels = function() return nil end,
      }
      for key, value in pairs(driverOverrides or {}) do driver[key] = value end
      set(upvalue(GC.Sell.OnThrottleReady, "advanceQuote"), "driver", driver)
      return GC
    end

    it("mirrors a resolved quote into the persisted store", function()
      local now, sent = { value = 1000 }, { owned = 0, keys = {} }
      local GC = load(now, sent, function() return { isCommodity = true } end)
      GC.db = {}
      GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
      assert.same({ 42 }, sent.keys)
      GC.Sell.OnCommoditySearchResults(42)
      assert.same({ unit = 111, at = 1000 }, GC.db.sellQuotes[42])
    end)

    it("clears the persisted entry when the auction house genuinely answers 'nothing listed'", function()
      local now, sent = { value = 1000 }, { owned = 0, keys = {} }
      local GC = load(now, sent, function() return { isCommodity = true } end,
        { commodity = function() return nil end })
      GC.db = { sellQuotes = { [42] = { unit = 500, at = 900 } } }
      GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
      assert.same({ 42 }, sent.keys)
      GC.Sell.OnCommoditySearchResults(42)
      assert.is_nil(GC.db.sellQuotes[42])
    end)
  end)

  describe("Reset", function()
    -- Reset's only caller is the auction house CLOSING, which is the live session ending and
    -- not the player asking to forget anything. Wiping the store there re-priced every position
    -- from a dash on the next visit -- the tab spent its first half-minute saying "—" about
    -- prices it had known thirty seconds before ("ЦІНИ 4/17" on a list of seventeen, in game).
    it("keeps the persisted store when the auction house session ends", function()
      local now = { value = 100000 }
      _G.time = function() return now.value end
      local GC = { Sell = {}, SellPositions = { Build = function() return {} end } }
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("UI/SellFrame.lua", GC)
      local stored = {
        [42] = { unit = 1500, at = now.value - 100 },
        [7] = { unit = 20, at = now.value - 5 },
      }
      GC.db = { sellQuotes = stored }
      GC.Sell.Reset()
      assert.same(stored, GC.db.sellQuotes)
    end)

    it("clears the live cache and arms seeding again, so the next visit refills from the store", function()
      local now = { value = 100000 }
      _G.time = function() return now.value end
      local GC = { Sell = {}, SellPositions = { Build = function() return {} end } }
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("UI/SellFrame.lua", GC)
      GC.db = { sellQuotes = { [42] = { unit = 1500, at = now.value - 100 } } }

      local compose = upvalue(GC.Sell.SellableCount, "composePositions")
      compose()
      assert.equal(1500, upvalue(compose, "quotes")[42].unit)

      GC.Sell.Reset()
      -- The live cache is genuinely gone: a quote is a claim about an order book, and there is
      -- no order book once the session is over.
      assert.is_nil(upvalue(compose, "quotes")[42])
      -- ...but the next compose puts the remembered price back, rather than starting from a
      -- dash and re-walking every item.
      compose()
      assert.equal(1500, upvalue(compose, "quotes")[42].unit)
    end)
  end)
end)
