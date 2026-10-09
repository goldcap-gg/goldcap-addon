local helper = require("spec.spec_helper")

describe("Sell protected action state", function()
  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function handlers(GC)
    GC.Ledger = GC.Ledger or { Context = function() return { char = "A-R", region = "eu" } end }
    GC.Acquisitions = GC.Acquisitions or {}
    GC.Acquisitions.ScopeKey = GC.Acquisitions.ScopeKey or function(positionKey, scope)
      return table.concat({ scope.region, scope.char, positionKey }, "\1")
    end
    return GC.SellUI.Dock.OnPostClick, GC.SellUI.Dock.OnRepostClick
  end

  -- onPostClick no longer calls liveBagState directly for a non-commodity position (it goes
  -- through clickSafeBagState's cache instead -- see SellFrame.lua's own comment on why), so
  -- liveBagState is now clickSafeBagState's upvalue, not onPostClick's own. Every test here posts
  -- a "commodity:42" position, which clickSafeBagState still hands straight to the real
  -- liveBagState, so reaching it one hop further still reaches exactly what these tests stub.
  -- The click's pre-call part is GC.SellPost.PreparePost now, so the hops start there, and so
  -- does every stub below of a helper that part uses.
  local function liveBagState(GC)
    return GC.SellBags.LiveState
  end

  -- Primes the cache resolvePostLocation reads (onPostClick never builds an ItemLocation itself
  -- any more -- see SellFrame.lua's own comment on cacheBagLocation) and a matching C_Container
  -- read, mirroring what a real paint would already have done before any of these specs click
  -- Post directly with no render pass first.
  local function primeLocation(GC, positionKey, itemID, bag, slot, stackCount, location)
    location = location or { bag = bag, slot = slot }
    local cache = GC.SellState.bagLocationCache
    cache[positionKey] = { itemID = itemID, bag = bag, slot = slot, location = location }
    local previousInfo = _G.C_Container and _G.C_Container.GetContainerItemInfo
    _G.C_Container = _G.C_Container or {}
    _G.C_Container.GetContainerItemInfo = function(b, s)
      if b == bag and s == slot then return { itemID = itemID, stackCount = stackCount or 1, isBound = false } end
      if previousInfo then return previousInfo(b, s) end
      return nil
    end
    return location
  end

  local function setLiveBagState(GC, value)
    GC.SellBags.LiveState = value
    -- Same mirror as primeLocation above, run automatically: every stub here returns a fixed bag
    -- state, so priming from that one sample is exactly what a real paint would have cached for
    -- it before the click these specs fire directly.
    local ok, sample = pcall(value)
    if ok and type(sample) == "table" and sample.bag and sample.slot and sample.itemID and sample.positionKey then
      primeLocation(GC, sample.positionKey, sample.itemID, sample.bag, sample.slot,
        sample.stackQty or sample.exactQty)
    end
  end

  local function button()
    local value = { enabled = true }
    function value:Enable() self.enabled = true end
    function value:Disable() self.enabled = false end
    function value:SetLabel(label) self.label = label end
    return value
  end

  local function position()
    return { itemID = 42, positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
      character = "A-R", region = "eu", trackedQty = 1, listedQty = 0,
      ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 200 } } }
  end

  before_each(function()
    _G.time = function() return 100 end
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_Timer = nil
  end)

  after_each(function()
    _G.time, _G.GetTime, _G.ItemLocation, _G.C_Timer, _G.C_AuctionHouse, _G.C_Container, _G.C_Item = os.time, nil, nil, nil, nil, nil, nil
  end)

  it("does not call protected post APIs for a stale quote", function()
    local calls, refreshed = 0, false
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return nil end }, SellPositions = {} }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellWalk.RefreshFor = function() refreshed = true end
    post({ position = position(), action = button() })
    assert.equal(0, calls)
    assert.is_true(refreshed)
  end)

  it("routes a stale post through the Refresh open-AH guard", function()
    local owned, protected, status = 0, 0, {}
    _G.C_AuctionHouse = {
      QueryOwnedAuctions = function() owned = owned + 1 end,
      PostCommodity = function() protected = protected + 1 end,
    }
    local GC = { Sell = {}, Sniper = { IsAHOpen = function() return false end },
      QuoteCache = { Fresh = function() return nil end }, SellPositions = {} }
    helper.loadSell(GC)
    local spy = function(text) status[#status + 1] = text end
    GC.SellView.status = spy -- the click's own lines and the walk's
    local post = handlers(GC)
    post({ position = position(), action = button() })
    assert.equal(0, owned)
    assert.equal(0, protected)
    assert.equal("Auction House is not open", status[#status])
  end)

  it("fails closed for a malformed Fresh quote before building a post", function()
    local calls = 0
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 0, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 1, unitPrice = 1 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, positionKey = "commodity:42" } end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    GC.SellWalk.RefreshFor = function() end
    post({ position = position(), action = button() })
    assert.equal(0, calls)
  end)

  it("pins a post once and confirms exactly once from the same quote snapshot", function()
    local postCalls, confirmCalls = 0, 0
    local postArgs, confirmArgs
    local location = { bag = 0, slot = 1 }
    _G.ItemLocation = {
      CreateFromBagAndSlot = function(_, bag, slot)
        assert.equal(0, bag)
        assert.equal(1, slot)
        return location
      end,
    }
    _G.C_AuctionHouse = {
      PostCommodity = function(...) postCalls = postCalls + 1; postArgs = { ... }; return true end,
      ConfirmPostCommodity = function(...) confirmCalls = confirmCalls + 1; confirmArgs = { ... } end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    -- Overrides setLiveBagState's own auto-primed cache entry with this test's own `location`
    -- table, so the reference-equality checks below (assert.equal, not assert.same) hold.
    primeLocation(GC, "commodity:42", 42, 0, 1, 1, location)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local row = { position = position(), action = button(), renderEntryID = "entry:post:42" }
    post(row); post(row); post(row)
    assert.equal(1, postCalls)
    assert.equal(1, confirmCalls)
    assert.equal(location, postArgs[1])
    assert.equal(location, confirmArgs[1])
    assert.same({ 2, 1, 200 }, { postArgs[2], postArgs[3], postArgs[4] })
    assert.same({ 2, 1, 200 }, { confirmArgs[2], confirmArgs[3], confirmArgs[4] })
  end)

  it("posts a commodity aggregate with commodity API arguments", function()
    local calls = {}
    local location = { bag = 0, slot = 1 }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return location end }
    _G.C_AuctionHouse = { PostCommodity = function(...) calls[#calls + 1] = { ... }; return false end }
    local stacks = { [1] = { itemID = 42, stackCount = 2 }, [2] = { itemID = 42, stackCount = 3 } }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot) return stacks[slot] end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 5, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    primeLocation(GC, "commodity:42", 42, 0, 1, 2, location)
    post({ position = position(), action = button(), renderEntryID = "entry:post:42" })
    assert.equal(location, calls[1][1])
    assert.same({ 2, 5, 200 }, { calls[1][2], calls[1][3], calls[1][4] })
  end)

  -- The auction's listing duration used to be a hardcoded constant (24h). It now reads
  -- GC.db.settings.sniper.postDuration -- the same field the settings panel's segmented
  -- 12H/24H/48H duration control writes -- so a player's choice takes effect on the very next
  -- click, with no reload.
  it("posts at the configured duration, not a hardcoded one", function()
    local calls = {}
    local location = { bag = 0, slot = 1 }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return location end }
    _G.C_AuctionHouse = { PostCommodity = function(...) calls[#calls + 1] = { ... }; return false end }
    local stacks = { [1] = { itemID = 42, stackCount = 2 }, [2] = { itemID = 42, stackCount = 3 } }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot) return stacks[slot] end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 5, unitPrice = 200 } end,
    }, db = { settings = { sniper = { postDuration = 3 } } } }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    primeLocation(GC, "commodity:42", 42, 0, 1, 2, location)
    post({ position = position(), action = button(), renderEntryID = "entry:post:42" })
    assert.equal(3, calls[1][2])
  end)

  -- A malformed or hand-edited SavedVariables value must never reach a protected call: fall
  -- back to the addon's long-standing default (24h) rather than pass a duration the API would
  -- reject or, worse, silently misinterpret.
  it("falls back to 24h for a settings value that is not one of the three the API accepts", function()
    local calls = {}
    local location = { bag = 0, slot = 1 }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return location end }
    _G.C_AuctionHouse = { PostCommodity = function(...) calls[#calls + 1] = { ... }; return false end }
    local stacks = { [1] = { itemID = 42, stackCount = 2 }, [2] = { itemID = 42, stackCount = 3 } }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot) return stacks[slot] end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 5, unitPrice = 200 } end,
    }, db = { settings = { sniper = { postDuration = 99 } } } }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    primeLocation(GC, "commodity:42", 42, 0, 1, 2, location)
    post({ position = position(), action = button(), renderEntryID = "entry:post:42" })
    assert.equal(2, calls[1][2])
  end)

  -- Was: "fails closed when a commodity bag slot cannot produce an ItemLocation" -- the click
  -- no longer builds one at all (see cacheBagLocation's own comment above liveBagState), so the
  -- equivalent fail-closed case now is a position resolvePostLocation has no cache entry for: it
  -- resolves live (a real paint would have painted it), but nothing painted it in this test, so
  -- onPostClick must still refuse rather than build the location itself.
  it("fails closed when the bag location cache has nothing for this position", function()
    local calls = 0
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 1, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    -- Stubbed directly, not through setLiveBagState, which would prime the cache from the same
    -- sample -- this test needs the cache to stay empty.
    GC.SellBags.LiveState = function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1,
        itemID = 42, positionKey = "commodity:42" }
    end
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    post({ position = position(), action = button(), renderEntryID = "entry:post:no-location" })
    assert.equal(0, calls)
  end)

  -- Forever addon task 3a, itemlocation-fix-report.md: the cache pins a bag slot at paint time,
  -- and the click only re-checks it with a plain C API (never rebuilding the location) -- so a
  -- stack that moved between that paint and this click is refused, not silently re-resolved.
  it("[Forever] refuses to post a commodity when the cached slot no longer holds this item (stack moved)", function()
    local calls = 0
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    -- The cache's own anchor slot (1) no longer holds item 42 -- the player moved bags since the
    -- last paint -- while slot 2 still carries enough for the aggregate liveBagState finds live,
    -- so only the location step, not the aggregate quantity, is what refuses this.
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot)
        if slot == 2 then return { itemID = 42, stackCount = 5 } end
        return { itemID = 999, stackCount = 3 }
      end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 5, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    -- Pinned at the paint's own bag/slot directly (not primeLocation, which would also rewrite
    -- GetContainerItemInfo for that slot and defeat the point of this test).
    GC.SellState.bagLocationCache["commodity:42"] =
      { itemID = 42, bag = 0, slot = 1, location = { bag = 0, slot = 1 } }
    post({ position = position(), action = button(), renderEntryID = "entry:post:moved-stack" })
    assert.equal(0, calls)
  end)

  it("[Forever] refuses to post a normal item when its cached slot no longer holds enough of it", function()
    local calls = 0
    _G.C_AuctionHouse = { PostItem = function() calls = calls + 1 end }
    -- The cached slot (0,2) now holds only 1, not the 3 the plan needs -- sold or moved since
    -- the last paint.
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function(_, slot) return slot == 2 and { itemID = 42, stackCount = 1 } or nil end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "item:42:100:7:0",
        scopeKey = "eu\1A-R\1item:42:100:7:0", itemID = 42, quantity = 3, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = false } end }
    local p = position(); p.positionKey = "item:42:100:7:0"; p.scopeKey = "eu\1A-R\1item:42:100:7:0"
    GC.SellState.bagLocationCache["item:42:100:7:0"] =
      { itemID = 42, bag = 0, slot = 2, location = { bag = 0, slot = 2 } }
    post({ position = p, action = button(), renderEntryID = "entry:post:variant-moved" })
    assert.equal(0, calls)
  end)

  it("rejects commodity confirmation after the pinned bag slot changes", function()
    local confirms = 0
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_AuctionHouse = {
      PostCommodity = function() return true end,
      ConfirmPostCommodity = function() confirms = confirms + 1 end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 1, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    local bagState = { bag = 0, slot = 1, stackQty = 1, exactQty = 1,
      itemID = 42, positionKey = "commodity:42" }
    setLiveBagState(GC, function() return bagState end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local row = { position = position(), action = button(), renderEntryID = "entry:post:moved" }

    post(row)
    bagState = { bag = 0, slot = 2, stackQty = 1, exactQty = 1,
      itemID = 42, positionKey = "commodity:42" }
    post(row)

    assert.equal(0, confirms)
    assert.is_nil(row.postStage)
  end)

  it("posts a normal variant from a later stack that holds the full plan", function()
    local calls = {}
    _G.C_AuctionHouse = { PostItem = function(...) calls[#calls + 1] = { ... }; return false end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot) return { itemID = 42, stackCount = slot == 1 and 1 or 5 } end,
      GetContainerItemLink = function() return "item:42:0::0:0:0:7:0:0:0:0:0:0" end,
    }
    _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "item:42:100:7:0",
        scopeKey = "eu\1A-R\1item:42:100:7:0", itemID = 42, quantity = 3, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = false } end }
    local p = position(); p.positionKey = "item:42:100:7:0"; p.scopeKey = "eu\1A-R\1item:42:100:7:0"
    -- The cache pins the later stack directly: onPostClick's non-commodity path only re-checks
    -- the bag/slot the cache already resolved (clickSafeBagState), it never re-runs the
    -- GC.Sell._SlotKey matching that picked it -- that only happens at paint time now.
    primeLocation(GC, "item:42:100:7:0", 42, 0, 2, 5)
    post({ position = p, action = button(), renderEntryID = "entry:post:variant" })
    assert.equal(2, calls[1][1].slot)
    assert.equal(2, calls[1][2])
    assert.equal(3, calls[1][3])
    assert.is_nil(calls[1][4])
    assert.equal(600, calls[1][5])
  end)

  it("attributes a successful post once and restores its pinned row", function()
    local records, refreshes = {}, 0
    _G.C_AuctionHouse = { PostCommodity = function() return false end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    }, Acquisitions = { RecordPost = function(...) records[#records + 1] = { ... } end },
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end } }
    helper.loadSell(GC)
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    local row = { position = p, action = button(), renderEntryID = "entry:post:42" }
    post(row)
    GC.Sell.OnAuctionCreated()
    -- The trailing 200 is the posted UNIT price (pin.total / pin.quantity), remembered so a
    -- later mail invoice naming two quality ranks of one reagent can be told apart by the
    -- price it sold at -- see GC.Acquisitions.WasListedAt.
    assert.same({ "commodity:42", 42, "Item 42", "A-R", "eu", 1, 100, 200 }, records[1])
    assert.is_nil(row.postStage)
    assert.is_true(row.action.enabled)
    assert.equal("Post", row.action.label)
    assert.equal(1, refreshes)
  end)

  it("attributes a post to its immutable armed scope rather than a later context", function()
    local records, scope = {}, { char = "A-R", region = "eu" }
    _G.C_AuctionHouse = { PostCommodity = function() return false end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42", itemID = 42, quantity = 1, unitPrice = 200 } end,
    }, Acquisitions = { RecordPost = function(...) records[#records + 1] = { ... } end },
      Ledger = { Context = function() return scope end } }
    helper.loadSell(GC)
    GC.Sell.Refresh = function() end
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    local row = { position = p, action = button(), renderEntryID = "entry:post:42" }
    post(row)
    scope = { char = "B-R", region = "us" }
    GC.Sell.OnAuctionCreated()
    assert.same({ "commodity:42", 42, "Item 42", "A-R", "eu", 1, 100, 200 }, records[1])
  end)

  it("rejects a post plan whose scope cannot prove the clicked position", function()
    local calls = 0
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "other", itemID = 42, quantity = 1, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position()
    post({ position = p, action = button() })
    assert.equal(0, calls)
  end)

  it("[C3] rejects current-context scope drift before the first protected Post call", function()
    local calls, records = 0, 0
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1; return false end }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "B-R", region = "us" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
        RecordPost = function() records = records + 1 end,
      },
      QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      SellPositions = {
        BuildPostPlan = function()
          return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
            itemID = 42, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" }
    end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    post({ position = p, action = button(), renderEntryID = "entry:post:42" })
    assert.equal(0, calls)
    assert.equal(0, records)
  end)

  it("[C3] fails closed and restores the exact pin when ConfirmPost is unavailable", function()
    local postCalls, records = 0, 0
    local quote = { unit = 200, at = 100 }
    _G.C_AuctionHouse = {
      PostCommodity = function() postCalls = postCalls + 1; return true end,
    }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
        RecordPost = function() records = records + 1 end,
      },
      QuoteCache = { Fresh = function() return quote end },
      SellPositions = {
        BuildPostPlan = function()
          return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
            itemID = 42, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" }
    end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    local row = { position = p, action = button(), renderEntryID = "entry:post:42" }
    post(row)
    local ok = pcall(post, row)
    assert.is_true(ok)
    assert.equal(1, postCalls)
    assert.equal(0, records)
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.enabled)
  end)

  it("clears a confirmation pin when the fresh quote changes", function()
    local posts, confirms, refreshes = 0, 0, 0
    _G.C_AuctionHouse = { PostCommodity = function() posts = posts + 1; return true end,
      ConfirmPostCommodity = function() confirms = confirms + 1 end }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    GC.SellWalk.RefreshFor = function() refreshes = refreshes + 1 end
    local row = { position = position(), action = button(), renderEntryID = "entry:post:42" }
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
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    }, Acquisitions = { RecordPost = function() records = records + 1 end } }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local row = { position = position(), action = button(), renderEntryID = "entry:post:42" }
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
        return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
          itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = fresh.unit }
      end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    GC.SellCompose.Positions = function() end
    local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.equal(0, cancelCalls)
    row.repostReady = true
    quote = { unit = 201, at = 101 }
    repost(row, 7)
    assert.equal(0, cancelCalls)
  end)

  it("disarms an armed repost immediately when its confirmation quote is stale", function()
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID) return { positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = 200 } end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    GC.QuoteCache.Fresh = function() return nil end
    repost(row, 7)
    assert.is_nil(row.repostStage)
    assert.equal("Cancel lot", row.action.label)
    assert.is_true(row.action.enabled)
  end)

  it("rejects an armed repost when the live lot has the same key but a different scope", function()
    local cancels = 0
    _G.C_AuctionHouse = {
      CancelAuction = function() cancels = cancels + 1 end,
      GetOwnedAuctions = function() return { { auctionID = 7 } } end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildRepostPlan = function(p, auctionID) return { positionKey = "commodity:42", scopeKey = p.scopeKey,
        itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = 200 } end,
      NormalizeOwnedLots = function() return {
        { positionKey = "commodity:42", itemID = 42, auctionID = 7, quantity = 1, unitPrice = 200 },
      } end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    GC.SellCompose.Positions = function() end
    local p = position(); p.scopeKey = "mine"
    local row = { position = p, action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7); row.repostReady = true; repost(row, 7)
    assert.equal(0, cancels)
    assert.is_nil(row.repostStage)
  end)

  it("restores an armed repost row when its owned lot disappears", function()
    _G.C_AuctionHouse = { GetOwnedAuctions = function() return {} end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID) return { positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = 200 } end,
      NormalizeOwnedLots = function() return {} end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    GC.SellOwned.OnReady = function() end
    local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    GC.Sell.OnOwnedAuctions()
    assert.is_nil(row.repostStage)
    assert.equal("Cancel lot", row.action.label)
    assert.is_true(row.action.enabled)
  end)

  it("reacquires the owned-auction snapshot before cancelling an armed repost", function()
    local cancelCalls, ownedReads, cancelID = 0, 0, nil
    _G.C_AuctionHouse = {
      CancelAuction = function(auctionID) cancelCalls = cancelCalls + 1; cancelID = auctionID end,
      GetOwnedAuctions = function() ownedReads = ownedReads + 1; return { { auctionID = 7 } } end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID, fresh) return { positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = fresh.unit } end,
      NormalizeOwnedLots = function() return {
        { positionKey = "commodity:42", itemID = 42, auctionID = 7, quantity = 1, unitPrice = 200 },
      } end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    GC.SellCompose.Positions = function() end
    local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    row.repostReady = true
    repost(row, 7)
    assert.equal(1, ownedReads)
    assert.equal(1, cancelCalls)
    assert.equal(7, cancelID)
  end)

  -- Repost is a cancel-only flow -- CancelAuction, then "Lot cancelled; wait for it to return
  -- to bags" (see the comment right after CancelAuction in onRepostClick, and Core/Flips.lua's
  -- "Repost's cancel step"). The actual relist happens later through the ordinary Post path
  -- (BuildPostPlan, which already carries the queue/overcut raise) once the units are back in
  -- the bags -- BuildRepostPlan.unitPrice is never posted at all. Its ONLY runtime consumer is
  -- this confirm guard, which compares it against the RAW fresh quote (pin.quoteUnit, set from
  -- quote.unit at arm time, never from the plan). If BuildRepostPlan raised its unit for a
  -- "queue"/"overcut" recommendation the way BuildPostPlan does, that comparison would never
  -- match on a row where overcut fired -- the second click would always read "Repost
  -- confirmation expired" and the button could never confirm. Real BuildRepostPlan (not
  -- stubbed), so this exercises the actual guard rather than a double that assumes the fix.
  it("confirms an armed repost for an overcut-recommended lot without BuildRepostPlan raising the price", function()
    local cancelCalls, cancelID = 0, nil
    _G.C_AuctionHouse = {
      CancelAuction = function(auctionID) cancelCalls = cancelCalls + 1; cancelID = auctionID end,
      -- A real-shaped owned auction (itemID, isCommodity, quantity, unitPrice), not the bare
      -- {auctionID=7} the pre-C2 fix's composePositions(true)/currentPosition stub let stand in
      -- for: the confirming click now validates the armed lot against exactly what real
      -- NormalizeOwnedLots turns this into.
      GetOwnedAuctions = function() return { { auctionID = 7, itemID = 42, isCommodity = true, quantity = 1, unitPrice = 200 } } end,
    }
    local quote = { unit = 200, at = 100 }
    local function overcutPosition()
      return { itemID = 42, positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        character = "A-R", region = "eu", trackedQty = 1, listedQty = 1,
        ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 200 } },
        recommendation = { action = "repost", rec = { mode = "overcut", unit = 11500, ahead = 12 } } }
    end
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end },
      Acquisitions = { PositionKey = function(itemID) return ("commodity:%d"):format(itemID) end } }
    -- The REAL BuildRepostPlan/NormalizeOwnedLots, not a stub: a double that just passes
    -- fresh.unit through would prove nothing about the guard this test exists to protect.
    GC = helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    GC.SellCompose.Positions = function() end
    local row = { position = overcutPosition(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.equal("armed", row.repostStage)
    row.repostReady = true
    repost(row, 7)
    assert.equal(1, cancelCalls)
    assert.equal(7, cancelID)
    assert.equal("cancelling", row.repostStage)
  end)

  it("reset disarms a repost without cancelling", function()
    local cancels = 0
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end, Clear = function() end }, SellPositions = {
      BuildRepostPlan = function(_, auctionID, fresh) return { positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.equal("armed", row.repostStage)
    GC.Sell.Reset()
    assert.is_nil(row.repostStage); assert.equal("Cancel lot", row.action.label); assert.is_true(row.action.enabled)
    assert.equal(0, cancels)
  end)

  it("[C4] disarms the previous exact Repost pin when a different row is clicked", function()
    local cancels = 0
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
      },
      QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      SellPositions = {
        BuildRepostPlan = function(p, auctionID)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, auctionID = auctionID,
            itemID = p.itemID, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    local first = { itemID = 42, positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
      ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 220 } } }
    local second = { itemID = 43, positionKey = "commodity:43", scopeKey = "eu\1A-R\1commodity:43",
      ownedLots = { { auctionID = 8, quantity = 1, unitPrice = 230 } } }
    local firstRow = { position = first, action = button(), renderEntryID = "entry:lot:7" }
    local secondRow = { position = second, action = button(), renderEntryID = "entry:lot:8" }
    repost(firstRow, 7)
    assert.equal("armed", firstRow.repostStage)
    repost(secondRow, 8)
    assert.is_nil(firstRow.repostStage)
    assert.equal("Cancel lot", firstRow.action.label)
    assert.is_true(firstRow.action.enabled)
    assert.is_nil(secondRow.repostStage)
    assert.equal(0, cancels)
  end)

  it("[C4] rejects changed live lot fields and a missing Cancel API", function()
    for _, case in ipairs({ { name = "changed unit", unit = 201, withAPI = true },
      { name = "missing API", unit = 200, withAPI = false } }) do
      local cancels = 0
      _G.C_AuctionHouse = {
        GetOwnedAuctions = function() return { { auctionID = 7 } } end,
        CancelAuction = case.withAPI and function() cancels = cancels + 1 end or nil,
      }
      local GC = {
        Sell = {},
        Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
        Acquisitions = {
          ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
        },
        QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
        SellPositions = {
          BuildRepostPlan = function(p, auctionID)
            return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
              auctionID = auctionID, quantity = 1, unitPrice = 200 }
          end,
          NormalizeOwnedLots = function()
            return { { positionKey = "commodity:42", itemID = 42, auctionID = 7,
              quantity = 1, unitPrice = case.unit } }
          end,
        },
      }
      helper.loadSell(GC)
      local _, repost = handlers(GC)
      GC.SellCompose.Positions = function() end
      local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
      repost(row, 7)
      row.repostReady = true
      repost(row, 7)
      assert.equal(0, cancels, case.name)
      assert.is_nil(row.repostStage, case.name)
      assert.equal("Cancel lot", row.action.label, case.name)
      assert.is_true(row.action.enabled, case.name)
    end
  end)

  it("[C4] rejects a Repost plan redirected from the clicked auction", function()
    local cancels = 0
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
      },
      QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      SellPositions = {
        BuildRepostPlan = function(p)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
            auctionID = 8, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    local p = position()
    p.ownedLots[2] = { auctionID = 8, quantity = 1, unitPrice = 200 }
    local row = { position = p, action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.is_nil(row.repostStage)
    assert.equal(0, cancels)
  end)

  it("[C6] OnPostError disarms Repost and makes its timer callbacks inert", function()
    local cancels, refreshes, timers = 0, 0, {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
      },
      QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      SellPositions = {
        BuildRepostPlan = function(p, auctionID)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, auctionID = auctionID,
            itemID = p.itemID, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local _, repost = handlers(GC)
    local p = position()
    p.scopeKey = "eu\1A-R\1commodity:42"
    p.ownedLots[1].unitPrice = 220
    local row = { position = p, action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.equal(2, #timers)
    GC.Sell.OnPostError()
    assert.is_nil(row.repostStage)
    assert.equal("Cancel lot", row.action.label)
    assert.is_true(row.action.enabled)
    for _, callback in ipairs(timers) do callback() end
    assert.equal(0, cancels)
    assert.equal(1, refreshes)
  end)

  -- The watchdog gives up on the wire, not on the post. PostCommodity answering false means the
  -- post was SENT (Blizzard's own sell frame reads it the same way), so an
  -- AUCTION_HOUSE_AUCTION_CREATED after the timeout is that post going up late. This test used to
  -- pin the opposite ("prevents later activity"): the late auction was thrown away and the price
  -- chosen for it never spent. It is now credited once -- the Posted line, the typed price spent,
  -- the item free to post again -- and the row the timeout handed back stays handed back. Which
  -- post a late creation answers is the order rule's guess, so it writes nothing durable: the
  -- owned-auctions list the refresh asks for records the auction for what it is.
  it("[C6] post timeout restores the exact row, and a late answer is still that post's", function()
    local calls, records, timers = 0, 0, {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.C_AuctionHouse = { PostCommodity = function() calls = calls + 1; return false end }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
        RecordPost = function() records = records + 1 end,
      },
      QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      SellPositions = {
        BuildPostPlan = function()
          return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
            itemID = 42, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    local quote = { unit = 200, at = 100 }
    GC.QuoteCache.Fresh = function() return quote end
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" }
    end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local row = { position = position(), action = button(), renderEntryID = "entry:post:42" }
    post(row)
    assert.equal("posting", row.postStage)
    assert.equal(1, #timers)
    timers[1]()
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.enabled)
    local refreshes = 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    assert.equal(1, #GC.Sell._LiveLate())
    GC.Sell.OnAuctionCreated()
    assert.equal(1, calls)
    assert.equal(0, #GC.Sell._LiveLate())
    assert.equal(1, refreshes)
    assert.equal(0, records)
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    -- Once: a second creation is not the same post again.
    GC.Sell.OnAuctionCreated()
    assert.equal(1, refreshes)
  end)

  it("[C6] OnPostError restores Post and invalidates its timer and activity pin", function()
    local records, refreshes, timers = 0, 0, {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.C_AuctionHouse = { PostCommodity = function() return false end }
    local quote = { unit = 200, at = 100 }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
        RecordPost = function() records = records + 1 end,
      },
      QuoteCache = { Fresh = function() return quote end },
      SellPositions = {
        BuildPostPlan = function()
          return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
            itemID = 42, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local post = handlers(GC)
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" }
    end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local row = { position = position(), action = button(), renderEntryID = "entry:post:42" }
    post(row)
    GC.Sell.OnPostError()
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.enabled)
    for _, callback in ipairs(timers) do callback() end
    GC.Sell.OnAuctionCreated()
    assert.equal(0, records)
    assert.equal(1, refreshes)
  end)

  it("[C6] Repost arm and expiry timers restore without cancelling", function()
    local cancels, timers = 0, {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
      },
      QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      SellPositions = {
        BuildRepostPlan = function(p, auctionID)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
            auctionID = auctionID, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    local row = { position = position(), action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.equal("armed", row.repostStage)
    assert.is_false(row.action.enabled)
    timers[1]()
    assert.is_true(row.repostReady)
    assert.is_true(row.action.enabled)
    timers[2]()
    assert.is_nil(row.repostStage)
    assert.equal("Cancel lot", row.action.label)
    assert.is_true(row.action.enabled)
    assert.equal(0, cancels)
  end)

  it("[round5 close] routes real Sniper AH close through real Sell cleanup and preserves its drain fence", function()
    local calls = { post = 0, confirm = 0, cancel = 0, activity = 0, cacheSet = 0, cacheClear = 0 }
    local sent, timers = {}, {}
    _G.GetTime = function() return 100 end
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.C_AuctionHouse = {
      QueryOwnedAuctions = function() end,
      GetOwnedAuctions = function() return { { auctionID = 7 } } end,
      PostCommodity = function() calls.post = calls.post + 1; return false end,
      ConfirmPostCommodity = function() calls.confirm = calls.confirm + 1 end,
      CancelAuction = function() calls.cancel = calls.cancel + 1 end,
    }
    local quote = { unit = 200, at = 100 }
    local postPosition = position()
    postPosition.ownedLots = {}
    -- Matches the liveBagState stub further down: this item IS in the bags, and
    -- the pricing walk only asks about positions there is something to do with.
    postPosition.bagQty = 1
    local repostPosition = { itemID = 43, itemName = "Lot", positionKey = "commodity:43",
      scopeKey = "eu\1A-R\1commodity:43", character = "A-R", region = "eu",
      trackedQty = 1, listedQty = 1,
      ownedLots = { { positionKey = "commodity:43", itemID = 43,
        auctionID = 7, quantity = 1, unitPrice = 220 } } }
    local GC = {
      Sell = {},
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      db = { settings = { sniper = {} } },
      SniperDecision = { Evaluate = function() return {} end },
      Print = function() end,
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope)
          return table.concat({ scope.region, scope.char, positionKey }, "\1")
        end,
        GetActive = function() return {} end,
        RecordPost = function() calls.activity = calls.activity + 1 end,
      },
      QuoteCache = {
        MAX_AGE_SECONDS = 10,
        Fresh = function() return quote end,
        Set = function() calls.cacheSet = calls.cacheSet + 1 end,
        Clear = function() calls.cacheClear = calls.cacheClear + 1 end,
      },
      SellViewModel = {},
      SellPositions = {
        NormalizeOwnedLots = function() return repostPosition.ownedLots end,
        Build = function() return { postPosition, repostPosition } end,
        BuildPostPlan = function(p)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
            quantity = 1, unitPrice = 200 }
        end,
        BuildRepostPlan = function(p, auctionID)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
            auctionID = auctionID, quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    set(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    local post, repost = handlers(GC)
    local refreshDriver = {
      isReady = function() return true end,
      keyInfo = function() return { isCommodity = true } end,
      send = function(itemID) sent[#sent + 1] = itemID end,
      commodity = function() return 111 end,
      commodityLevels = function() return nil end,
      item = function() return nil end,
      itemLevels = function() return nil end,
    }
    GC.SellQuotes.driver = refreshDriver
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1,
        itemID = 42, positionKey = "commodity:42" }
    end)

    GC.Sell.Refresh()
    GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent)
    local refresh = GC.SellState.refresh
    local sentGeneration = refresh.generation
    assert.equal("waiting_result", refresh.phase)
    assert.is_table(refresh.pending)

    local postAction = button(); postAction:SetLabel("Post")
    local postRow = { position = postPosition, action = postAction, renderEntryID = "entry:post:42" }
    local repostAction = button(); repostAction:SetLabel("Cancel lot")
    local repostRow = { position = repostPosition, action = repostAction, renderEntryID = "entry:lot:7" }
    post(postRow)
    repost(repostRow, 7)
    assert.equal("posting", postRow.postStage)
    assert.equal("armed", repostRow.repostStage)
    assert.equal(1, calls.post)
    assert.equal(0, calls.cancel)

    GC.Sniper.OnAuctionHouseClosed()

    assert.is_nil(postRow.postStage)
    assert.equal("Post", postRow.action.label)
    assert.is_true(postRow.action.enabled)
    assert.is_nil(repostRow.repostStage)
    assert.equal("Cancel lot", repostRow.action.label)
    assert.is_true(repostRow.action.enabled)
    assert.equal(sentGeneration + 1, refresh.generation)
    assert.equal("idle", refresh.phase)
    assert.is_nil(refresh.pending)
    assert.equal(1, refresh.drain["commodity:42"].terminals)
    local afterClose = { post = calls.post, confirm = calls.confirm,
      cancel = calls.cancel, activity = calls.activity }
    for _, callback in ipairs(timers) do callback() end
    GC.Sell.OnAuctionCreated()
    assert.equal("idle", refresh.phase)
    assert.equal(1, refresh.drain["commodity:42"].terminals)
    assert.same(afterClose, { post = calls.post, confirm = calls.confirm,
      cancel = calls.cancel, activity = calls.activity })

    set(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sell.Refresh()
    GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent)
    assert.equal("draining", refresh.phase)
    GC.Sell.OnCommoditySearchResults(42)
    assert.equal(0, calls.cacheSet)
    assert.same({ 42, 42 }, sent)
    assert.equal("waiting_result", refresh.phase)
    -- Once, not twice: closing the auction house clears the SESSION quote cache and leaves the
    -- persisted mirror alone, so the next visit opens with the prices it already knew instead
    -- of re-walking every position from a dash. See sell_quote_persistence_spec.lua's Reset
    -- tests for the store's own half of that contract.
    assert.equal(1, calls.cacheClear)
    assert.same(afterClose, { post = calls.post, confirm = calls.confirm,
      cancel = calls.cancel, activity = calls.activity })
  end)

  it("[C6] rejects malformed, pet, and overflowing bag identity with zero protected calls", function()
    local fixtures = {
      { name = "malformed", key = "item:42:100:7:0", link = "item:42:broken", stacks = { 1 } },
      { name = "pet", key = "item:42:100:7:0", link = "battlepet:42:1:1:1:1:1", stacks = { 1 } },
      { name = "overflow", key = "commodity:42", stacks = { 9007199254740991, 1 } },
    }
    for _, fixture in ipairs(fixtures) do
      local calls = 0
      _G.C_AuctionHouse = {
        PostCommodity = function() calls = calls + 1 end,
        PostItem = function() calls = calls + 1 end,
      }
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #fixture.stacks or 0 end,
        GetContainerItemInfo = function(_, slot) return { itemID = 42, stackCount = fixture.stacks[slot] } end,
        GetContainerItemLink = function() return fixture.link end,
      }
      _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
      local GC = {
        Sell = {},
        Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
        Acquisitions = {
          ScopeKey = function(positionKey, scope) return table.concat({ scope.region, scope.char, positionKey }, "\1") end,
        },
        QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
        SellPositions = {
          BuildPostPlan = function(p)
            return { positionKey = p.positionKey, scopeKey = p.scopeKey,
              itemID = 42, quantity = 1, unitPrice = 200 }
          end,
        },
      }
      helper.loadSell(GC)
      local post = handlers(GC)
      GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = fixture.key == "commodity:42" } end }
      local p = position()
      p.positionKey = fixture.key
      p.scopeKey = "eu\1A-R\1" .. fixture.key
      post({ position = p, action = button(), renderEntryID = "entry:" .. fixture.name })
      assert.equal(0, calls, fixture.name)
    end
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
    helper.loadSell(GC)
    handlers(GC)
    assert.equal(5, liveBagState(GC)({ itemID = 42, positionKey = "commodity:42" }).exactQty)
    local normal = liveBagState(GC)({ itemID = 42, positionKey = "item:42:100:7:0" })
    assert.is_nil(normal.bag)
  end)

  it("[round5 bonus] rejects a bonus-bearing normal bag link through the loaded Post handler", function()
    local calls = { postItem = 0, postCommodity = 0, confirmItem = 0, confirmCommodity = 0,
      activity = 0, cache = 0 }
    local status = {}
    _G.C_AuctionHouse = {
      PostItem = function() calls.postItem = calls.postItem + 1 end,
      PostCommodity = function() calls.postCommodity = calls.postCommodity + 1 end,
      ConfirmPostItem = function() calls.confirmItem = calls.confirmItem + 1 end,
      ConfirmPostCommodity = function() calls.confirmCommodity = calls.confirmCommodity + 1 end,
    }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 2 } end,
      GetContainerItemLink = function() return "item:42:0:0:0:0:0:7:0:0:0:0:0:1:999" end,
    }
    _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
    local quote = { unit = 200, at = 100 }
    local GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
      Acquisitions = {
        ScopeKey = function(positionKey, scope)
          return table.concat({ scope.region, scope.char, positionKey }, "\1")
        end,
        RecordPost = function() calls.activity = calls.activity + 1 end,
      },
      QuoteCache = {
        Fresh = function() return quote end,
        Set = function() calls.cache = calls.cache + 1 end,
        Clear = function() calls.cache = calls.cache + 1 end,
      },
      SellPositions = {
        BuildPostPlan = function(p)
          return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
            quantity = 1, unitPrice = 200 }
        end,
      },
    }
    helper.loadSell(GC)
    local post = handlers(GC)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = false } end }
    GC.SellView.status = function(text) status[#status + 1] = text end
    local p = position()
    p.positionKey = "item:42:100:7:0"
    p.scopeKey = "eu\1A-R\1item:42:100:7:0"
    local action = button()
    action:SetLabel("Post")
    local row = { position = p, action = action, renderEntryID = "entry:post:bonus" }

    post(row)
    GC.Sell.OnAuctionCreated()

    assert.same({ postItem = 0, postCommodity = 0, confirmItem = 0, confirmCommodity = 0,
      activity = 0, cache = 0 }, calls)
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.enabled)
    assert.equal("No exact bag stack", status[#status])
  end)

  it("accepts a normal identity with empty fixed link fields", function()
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function() return { itemID = 42, stackCount = 2 } end,
      GetContainerItemLink = function() return "item:42:0::0:0:0:7:0:0:0:0:0:0" end,
    }
    _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
    local GC = { Sell = {}, QuoteCache = {}, SellPositions = {} }
    helper.loadSell(GC)
    handlers(GC)
    local state = liveBagState(GC)({ itemID = 42, positionKey = "item:42:100:7:0" })
    assert.equal(2, state.exactQty)
    assert.equal("item:42:100:7:0", state.positionKey)
  end)
  -- The post watchdog was armed once, on the FIRST click, and never re-armed for the confirming
  -- one -- so the seconds a player spent reading "lose its deposit" came out of the seconds the
  -- auction house had to answer the confirm, and a slow server produced "Posting timed out" over
  -- a post that had gone through.
  it("[S4] gives the confirming click its own timeout window", function()
    local timers = {}
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local confirms = 0
    _G.C_AuctionHouse = {
      PostCommodity = function() return true end,
      ConfirmPostCommodity = function() confirms = confirms + 1 end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    } }
    helper.loadSell(GC)
    local post = handlers(GC)
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" }
    end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    local row = { position = p, action = button(), renderEntryID = "entry:post:42" }
    post(row)
    assert.equal("confirm", row.postStage)
    post(row)
    assert.equal(1, confirms)
    assert.equal("confirming", row.postStage)
    local armed = {}
    for _, timer in ipairs(timers) do if timer.seconds == 8 then armed[#armed + 1] = timer.callback end end
    assert.equal(2, #armed)
    armed[1]() -- the first click's clock, already spent: inert
    assert.equal("confirming", row.postStage)
    armed[2]()
    assert.is_nil(row.postStage)
  end)

  -- And when the auction house really is slower than the watchdog, the post it announces is
  -- still a real post: it used to be lost entirely -- the price the seller had typed never
  -- cleared, so the next stack of that item quietly inherited a number chosen against a book that
  -- had moved. It is credited now; the owned list, not the guess, records it.
  it("[S4] credits a post the auction house confirmed after the watchdog gave up", function()
    local timers, records, refreshes = {}, {}, 0
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    _G.C_AuctionHouse = { PostCommodity = function() return true end, ConfirmPostCommodity = function() end }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function(_, _, fresh) return { positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", itemID = 42, quantity = 1, unitPrice = fresh.unit } end,
    }, Acquisitions = { RecordPost = function(...) records[#records + 1] = { ... } end },
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end } }
    helper.loadSell(GC)
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local post = handlers(GC)
    setLiveBagState(GC, function()
      return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" }
    end)
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    local row = { position = p, action = button(), renderEntryID = "entry:post:42" }
    post(row); post(row)
    local armed = {}
    for _, timer in ipairs(timers) do if timer.seconds == 8 then armed[#armed + 1] = timer.callback end end
    armed[#armed]()
    assert.is_nil(row.postStage)
    GC.Sell.OnAuctionCreated()
    assert.equal(0, #GC.Sell._LiveLate())
    assert.equal(1, refreshes)
    assert.equal(0, #records)
    -- Consumed once. A second, unrelated creation must not be credited to the same pin.
    GC.Sell.OnAuctionCreated()
    assert.equal(1, refreshes)
  end)

  -- A cancel is a server round trip. While it was in flight the row's own button was disabled,
  -- but the footer's CANCEL control still read "CANCEL LOT?" and was still enabled -- and that
  -- click fell straight past the armed branch into the arm branch, re-arming the very lot whose
  -- cancel the server was still working on.
  it("[S12] refuses a second click on a lot whose cancel is already on the wire", function()
    local cancels = 0
    _G.C_AuctionHouse = {
      CancelAuction = function() cancels = cancels + 1 end,
      GetOwnedAuctions = function() return { { auctionID = 7 } } end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildRepostPlan = function(target, auctionID) return { positionKey = "commodity:42",
        scopeKey = target.scopeKey, itemID = 42, auctionID = auctionID, quantity = 1, unitPrice = 200 } end,
      NormalizeOwnedLots = function() return {
        { positionKey = "commodity:42", itemID = 42, auctionID = 7, quantity = 1, unitPrice = 200 },
      } end,
    } }
    helper.loadSell(GC)
    local _, repost = handlers(GC)
    GC.SellCompose.Positions = function() end
    local p = position(); p.scopeKey = "eu\1A-R\1commodity:42"
    local row = { position = p, action = button(), renderEntryID = "entry:lot:7" }
    repost(row, 7)
    assert.equal("armed", row.repostStage)
    row.repostReady = true
    repost(row, 7)
    assert.equal(1, cancels)
    assert.equal("cancelling", row.repostStage)
    repost(row, 7)
    assert.equal(1, cancels)
    assert.equal("cancelling", row.repostStage)
    assert.is_false(row.action.enabled)
  end)
end)
