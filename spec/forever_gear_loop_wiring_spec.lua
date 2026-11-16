local helper = require("spec.spec_helper")

-- WoW: Forever's browse of all gear between scans, wired to the arbiter
-- (UI/SniperGearLoop_Camelot.lua). The Sniper here is a table of the fields the file reads, so the
-- spec says what the file asks of it; the auction house is the calls the file makes.
describe("Forever gear loop wiring", function()
  local GC, S, clock, wall, tick, sent, full, list, checked, vendor, state, batches

  local function row(itemID, level, suffix, minPrice, qty)
    return { itemKey = { itemID = itemID, itemLevel = level, itemSuffix = suffix, battlePetSpeciesID = 0 },
      minPrice = minPrice, totalQuantity = qty }
  end

  -- The client answers the query or page out: `rows` land, and the list is whole when `last`.
  local function answer(rows, last, first)
    full = last and true or false
    if first then list = rows else for _, r in ipairs(rows) do list[#list + 1] = r end end
    return S._GearBrowse((not first) and rows or nil)
  end

  -- One arbiter turn as GC.Sniper.OnThrottleReady gives the loop its two chances.
  local function turn()
    if S._GearTurn(false) then return true end
    return S._GearTurn(false, true)
  end

  local function advance(seconds)
    clock = clock + seconds
    tick()
  end

  local function classOf(query) return query.itemClassFilters[1].classID end

  before_each(function()
    clock, wall = 100, 50000
    sent, full, list, checked, batches = {}, false, {}, {}, 0
    vendor = { [3021] = 2426, [2140] = 500, [6000] = 900 }
    state = { auto = true, scanBusy = false, passPaging = false, passPending = false, keys = false,
      owned = false, naming = false, quiet = false, fold = { at = 4000, items = {} } }
    _G.GetTime = function() return clock end
    _G.time = function() return wall end
    _G.PlaySound = function() state.rang = (state.rang or 0) + 1 end
    _G.SOUNDKIT = { MAP_PING = 3175 }
    _G.C_Item = { RequestLoadItemDataByID = function(id) state.loaded = (state.loaded or 0) + 1; state.lastLoad = id end }
    _G.C_Timer = { NewTicker = function(_, fn)
      tick = fn
      return { Cancel = function() tick = function() end; state.cancelled = true end }
    end }
    _G.CreateFrame = function()
      return { RegisterEvent = function() end,
        SetScript = function(_, _, fn) state.onEvent = fn end }
    end
    _G.hooksecurefunc = function(t, name, hook)
      local orig = t[name]
      t[name] = function(...) orig(...); hook(...) end
    end
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function(query) sent[#sent + 1] = query end,
      RequestMoreBrowseResults = function() sent[#sent + 1] = "more" end,
      SearchForItemKeys = function() end,
      HasFullBrowseResults = function() return full end,
      GetBrowseResults = function() return list end,
    }

    GC = helper.loadModule("Core/Util.lua")
    for _, m in ipairs({ "Core/DealMath.lua", "Core/FullScan.lua", "Core/BookPass.lua", "Core/KeyPoll.lua",
      "Core/ForeverFold.lua", "Core/ForeverDeals.lua", "Core/ForeverGearLoop.lua" }) do
      helper.loadModule(m, GC)
    end
    GC.db = { settings = { sniper = { sound = true } }, commodityByItem = {} }
    GC.ForeverScan = { Enabled = function() return true end, IsBusy = function() return state.scanBusy end,
      Fold = function() return state.fold end }
    GC.ForeverValue = {
      VendorUnit = function(id, ask)
        if ask ~= false then state.asks = (state.asks or 0) + 1 end
        return vendor[id]
      end,
      Known = function(id) return vendor[id] ~= nil end,
      Quality = function(id) state.kept = id end,
    }
    GC.Sniper = {
      _named = {},
      _slotTurn = "pass",
      _bookPass = { IsPaging = function() return state.passPaging end,
        PendingStart = function() return state.passPending end },
      _AutoOnItems = function() return state.auto end,
      _KeysOutstanding = function() return state.keys end,
      _BrowseOwned = function() return state.owned end,
      _NamingBusy = function() return state.naming end,
      IsPurchaseQuiet = function() return state.quiet end,
      _IsOrphanAnswer = function() return false end,
      _CheckNow = function(deal) checked[#checked + 1] = deal; return true end,
      OnForeverFold = function() state.repaints = (state.repaints or 0) + 1 end,
      _SendNaming = function(itemID, attempt) state.named = { itemID, attempt }; return "sent" end,
      _TrySendKeysBatch = function() batches = batches + 1; return true end,
      _TrySendCapBatch = function() batches = batches + 1; return true end,
      -- Retail's own answers, which the file replaces.
      _GearTurn = function() return false end,
      _GearBrowse = function() return false end,
    }
    S = GC.Sniper
    S.OnThrottleReady = function() return turn() end
    helper.loadModule("UI/SniperGearLoop_Camelot.lua", GC)
    state.onEvent(nil, "AUCTION_HOUSE_SHOW")
  end)

  it("starts nothing before the auction house settles, and stops its clock when it closes", function()
    advance(0.25)
    assert.equal(0, #sent)
    state.onEvent(nil, "AUCTION_HOUSE_CLOSED")
    assert.is_true(state.cancelled)
  end)

  it("browses weapons, then armor, each class whole, then starts over", function()
    advance(2.25)
    assert.equal(1, #sent)
    assert.equal(2, classOf(sent[1]))
    assert.equal("", sent[1].searchString)
    assert.is_true(answer({ row(1, 5, 0, 10, 1) }, false, true))
    assert.is_true(turn())
    assert.equal("more", sent[2])
    assert.is_true(answer({ row(2, 5, 0, 10, 1) }, true))
    advance(0.75)
    assert.equal(4, classOf(sent[3]))
    assert.is_true(answer({ row(3, 5, 0, 10, 1) }, true, true))
    advance(0.75)
    assert.equal(2, classOf(sent[4]))
    assert.equal(1, #GC.db.foreverGearLoop.rounds)
  end)

  it("sends one message a turn, and takes the pass's place in the alternation with the tail", function()
    advance(2.25)
    answer({ row(1, 5, 0, 10, 1) }, false, true)
    assert.equal("tail", S._slotTurn)
    assert.is_false(S._GearTurn(false))      -- the tail's turn
    assert.equal(1, #sent)
    assert.is_true(S._GearTurn(false, true)) -- the tail had nothing to ask
    assert.equal(2, #sent)
  end)

  describe("a key under the vendor price", function()
    before_each(function()
      advance(2.25)
      answer({ row(3021, 20, 0, 2200, 1), row(2140, 11, 14315, 400, 121), row(2140, 11, 14300, 350, 13) }, false, true)
    end)

    it("is an Items row at once, with a repaint and a bell", function()
      local r = GC.ForeverDeals.LiveRow(3021)
      assert.equal(2200, r.unitPrice)
      assert.equal(350, GC.ForeverDeals.LiveRow(2140).unitPrice)
      assert.equal(1, state.repaints)
      assert.equal(1, state.rang)
    end)

    it("leaves the keys the round saw where the Check looks for an item's variants", function()
      local named = S._named[2140]
      assert.equal(clock, named.at)
      local key = GC.KeyPoll.VariantKeyFor(named.entry, 0)
      assert.equal(14300, key.itemSuffix)
      assert.equal(11, key.itemLevel)
    end)

    it("gets its live Check on the next turns, ahead of the next page, one a turn", function()
      assert.is_true(turn())
      assert.equal(1, #checked)
      assert.equal(3021, checked[1].itemID)
      assert.equal(1, #sent)
      assert.is_true(turn())
      assert.equal(2140, checked[2].itemID)
      assert.is_true(turn())
      assert.equal(2, #checked)
      assert.equal("more", sent[2])
      assert.equal(2, #GC.db.foreverGearLoop.hits)
      assert.matches("^50000 3021/20/0 2200 v2426 ", GC.db.foreverGearLoop.hits[1])
    end)

    it("is checked again only when its price moves", function()
      turn(); turn(); turn()
      answer({ row(3021, 20, 0, 2200, 1) }, true)
      assert.equal(2, #checked)
      assert.is_false(S._GearTurn(false, true))
    end)

    it("leaves the board when a whole round no longer sees it", function()
      turn(); turn(); turn()
      answer({}, true)                                   -- weapons read whole
      advance(0.75)
      answer({ row(6000, 30, 0, 9999, 1) }, true, true)  -- armor read whole: the round ends
      assert.is_not_nil(GC.ForeverDeals.LiveRow(3021))   -- seen this round
      advance(0.75)
      answer({ row(2140, 11, 14300, 350, 13) }, true, true)
      advance(0.75)
      answer({}, true, true)
      assert.is_nil(GC.ForeverDeals.LiveRow(3021))
      assert.is_not_nil(GC.ForeverDeals.LiveRow(2140))
    end)

    it("buys nothing: the file makes no purchase call", function()
      local source = assert(io.open("GoldCap/UI/SniperGearLoop_Camelot.lua")):read("*a")
      for _, call in ipairs({ "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase",
        "PostItem", "PostCommodity", "CancelAuction" }) do
        assert.is_nil(source:find(call, 1, true), call)
      end
    end)
  end)

  describe("stands down", function()
    local holds = {
      { name = "with Auto off, paused, or another board up", set = function() state.auto = false end },
      { name = "while the full scan runs", set = function() state.scanBusy = true end },
      { name = "with no scan saved yet", set = function() state.fold = nil end },
      { name = "while a pass is armed", set = function() state.passPending = true end },
      { name = "while a pass pages", set = function() state.passPaging = true end },
      { name = "while a keys batch is out", set = function() state.keys = true end },
      { name = "while the list is the player's own search", set = function() state.owned = true end },
      { name = "while a browse by an item's name is out", set = function() state.naming = true end },
      { name = "while a purchase is under way", set = function() state.quiet = true end },
    }
    for _, hold in ipairs(holds) do
      it(hold.name .. ": no round starts", function()
        hold.set()
        advance(2.25)
        advance(5)
        assert.equal(0, #sent)
      end)
    end

    it("for the player busy on Blizzard's panes, as the arbiter says it", function()
      advance(2.25)
      answer({ row(1, 5, 0, 10, 1) }, false, true)
      S._slotTurn = "pass"
      assert.is_false(S._GearTurn(true))
      assert.equal(1, #sent)
    end)

    it("with a page on the wire: holds the turn for its answer, then ends the round", function()
      advance(2.25)
      state.scanBusy = true
      assert.is_true(S._GearTurn(false))     -- nothing goes over the page that is out
      assert.equal(1, #sent)
      assert.is_true(answer({ row(3021, 20, 0, 2200, 1) }, false, true)) -- the loop's own answer
      assert.is_nil(GC.ForeverDeals.LiveRow(3021))                        -- and not folded
      assert.is_false(S._GearBrowse())       -- the next answer is somebody else's
      assert.is_false(S._GearTurn(false))
    end)

    it("a page never answered ends the round after twenty seconds, and the next starts over", function()
      advance(2.25)
      advance(20.5)
      assert.is_false(S._GearBrowse())
      advance(2.25)
      assert.equal(2, #sent)
      assert.equal(2, classOf(sent[2]))
    end)
  end)

  it("anybody else's browse ends the round: the list is theirs", function()
    advance(2.25)
    answer({ row(1, 5, 0, 10, 1) }, false, true)
    C_AuctionHouse.SendBrowseQuery({ searchString = "Carving Knife" })
    assert.is_false(S._GearBrowse({ row(3021, 20, 0, 2200, 1) }))
    assert.is_nil(GC.ForeverDeals.LiveRow(3021))
  end)

  it("a pass whose query went out over the round takes the answer", function()
    advance(2.25)
    state.passPaging = true
    assert.is_false(S._GearBrowse())
  end)

  it("holds our own keys batches while a class is read, and lets them go between two classes", function()
    advance(2.25)
    assert.is_false(S._TrySendKeysBatch())
    assert.is_false(S._TrySendCapBatch())
    assert.equal(0, batches)
    answer({ row(1, 5, 0, 10, 1) }, true, true)
    assert.is_true(S._TrySendCapBatch())
    assert.equal(1, batches)
  end)

  it("holds a background browse by an item's name while a class is read; the player's own Check goes", function()
    advance(2.25)
    assert.equal("wait", S._SendNaming(2140))
    assert.is_nil(state.named)
    local attempt = {}
    assert.equal("sent", S._SendNaming(2140, attempt))
    assert.same({ 2140, attempt }, state.named)
    answer({ row(1, 5, 0, 10, 1) }, true, true)
    assert.equal("sent", S._SendNaming(3021)) -- between two classes
  end)

  it("names every key of an item the board already shows, once its class is read whole", function()
    vendor[2140] = 300
    state.fold.items[2140] = "250,1,250,;0x1|0,0,1" -- the scan's row: 250 under a vendor's 300
    assert.is_not_nil(GC.ForeverDeals.Rows()[1])
    advance(2.25)
    answer({ row(2140, 11, 14315, 400, 121) }, false, true)
    assert.is_nil(S._named[2140]) -- a class half read says nothing of the item's cheapest key
    turn()
    answer({ row(2140, 11, 14300, 350, 13) }, true)
    local key = GC.KeyPoll.VariantKeyFor(S._named[2140].entry, 0)
    assert.equal(14300, key.itemSuffix)
  end)

  it("a round held between its classes waits, and is not started over for a short hold", function()
    advance(2.25)
    answer({ row(1, 5, 0, 10, 1) }, true, true)
    state.keys = true
    advance(3)
    assert.equal(1, #sent)
    state.keys = false
    advance(0.25)
    assert.equal(4, classOf(sent[2]))
  end)

  describe("an item with no kept vendor price", function()
    it("is asked of the client once, and its answer kept when it comes", function()
      vendor[7001] = nil
      advance(2.25)
      answer({ row(7001, 30, 0, 1, 1) }, false, true)
      assert.equal(1, state.loaded)
      assert.equal(7001, state.lastLoad)
      GC.ForeverDeals.OnItemInfo(7001)
      assert.equal(7001, state.kept)
      state.kept = nil
      GC.ForeverDeals.OnItemInfo(7001)
      assert.is_nil(state.kept)
    end)

    it("costs the round nothing when every price is kept", function()
      advance(2.25)
      answer({ row(3021, 20, 0, 9999, 1), row(6000, 30, 0, 9999, 1) }, true, true)
      assert.is_nil(state.asks)
      assert.is_nil(state.loaded)
    end)
  end)

  it("closing the auction house ends the round and forgets what waited", function()
    advance(2.25)
    answer({ row(3021, 20, 0, 2200, 1) }, false, true)
    state.onEvent(nil, "AUCTION_HOUSE_CLOSED")
    assert.is_false(S._GearTurn(false))
    assert.is_false(S._GearBrowse())
    assert.equal(0, #checked)
  end)

  describe("retail", function()
    it("has the two hooks as no-ops in the shared file, and loads neither Forever file", function()
      local sniper = assert(io.open("GoldCap/UI/SniperFrame.lua")):read("*a")
      assert.is_not_nil(sniper:find("function GC.Sniper._GearTurn() return false end", 1, true))
      assert.is_not_nil(sniper:find("function GC.Sniper._GearBrowse() return false end", 1, true))
      local toc = assert(io.open("GoldCap/GoldCap.toc")):read("*a")
      assert.is_nil(toc:find("GearLoop", 1, true))
    end)
  end)
end)
