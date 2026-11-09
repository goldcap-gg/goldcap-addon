local helper = require("spec.spec_helper")

-- One quantity rule (WoW: Forever plan 2026-11-09, Task 3): the post plan (BuildPostPlan), the
-- panel (GC.SellUtil.postQuantity) and the queue (Core/PostQueue.lua) all ask
-- GC.SellPositions.PostQuantity how many one post lists: a number the player typed (or MAX's
-- "all"), a followed group's "1 at a time", WoW: Forever's sale pace (position.paceTargets, set
-- only by Core/ForeverPace.lua) less what is already up at or under the price, then everything.
describe("one quantity rule", function()
  after_each(function()
    _G.time, _G.ItemLocation, _G.C_Timer, _G.C_AuctionHouse, _G.C_Container = os.time, nil, nil, nil, nil
  end)

  local function load()
    local GC = helper.loadModule("Core/Acquisitions.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    GC.db = { settings = { sniper = {} } }
    return GC
  end

  describe("PostQuantity", function()
    local GC
    before_each(function() GC = load() end)

    local function base()
      return { paceTargets = { [2] = 8 }, ownedLots = { { quantity = 5, unitPrice = 100 } } }
    end

    local function with(fields)
      local p = base()
      for k, v in pairs(fields or {}) do p[k] = v end
      return p
    end

    local CASES = {
      { "MAX is every unit", nil, "all", 100, 2, 20, "all" },
      { "a typed number under the most", nil, 6, 100, 2, 6, "typed" },
      { "a typed number over the most is all of it", nil, 25, 100, 2, 20, "all" },
      { "a group's one at a time", { rulePostQty = 1 }, nil, 100, 2, 1, "rule" },
      { "the pace less what is up at or under the price", nil, nil, 100, 2, 3, "pace" },
      { "our lot above the post does not count", nil, nil, 90, 2, 8, "pace" },
      { "enough is up", { ownedLots = { { quantity = 10, unitPrice = 100 } } }, nil, 100, 2, 0, "enough" },
      { "the pace above the bags", { paceTargets = { [2] = 30 }, ownedLots = {} }, nil, 100, 2, 20, "pace" },
      { "no pace", { paceTargets = false }, nil, 100, 2, 20, "most" },
      { "no duration", nil, nil, 100, nil, 20, "most" },
      { "a typed nought is no number", nil, 0, 100, 2, 3, "pace" },
    }

    for _, case in ipairs(CASES) do
      it(case[1], function()
        local fields = case[2]
        local typed = case[3]
        local p = with(fields)
        if p.paceTargets == false then p.paceTargets = nil end
        local qty, why = GC.SellPositions.PostQuantity(p, typed, 20, case[4], case[5])
        assert.equal(case[6], qty)
        assert.equal(case[7], why)
      end)
    end

    -- Review of Tasks 1-3, M2: with one unit left in the bags the rule's one is still one, where
    -- the pace would have held it; at or over the most the quantity is the most, as before.
    it("a group's one at a time holds with one in the bags", function()
      local p = with({ rulePostQty = 1, paceTargets = { [2] = 2 }, ownedLots = { { quantity = 2, unitPrice = 100 } } })
      assert.same({ 1, "rule" }, { GC.SellPositions.PostQuantity(p, nil, 1, 100, 2) })
      assert.same({ 1, "rule" }, { GC.SellPositions.PostQuantity(p, nil, 5, 100, 2) })
      assert.same({ 3, "rule" }, { GC.SellPositions.PostQuantity({ rulePostQty = 5 }, nil, 3, 100, nil) })
    end)

    it("MAX is the value the panel stores", function()
      assert.equal("all", GC.SellPositions.ALL)
      assert.same({ 20, "all" }, { GC.SellPositions.PostQuantity(base(), GC.SellPositions.ALL, 20, 100, 2) })
    end)
  end)

  it("ListedAtOrBelow", function()
    local GC = load()
    local p = { ownedLots = { { quantity = 5, unitPrice = 100 }, { quantity = 3, unitPrice = 120 } },
      paceRecent = { { quantity = 2, unitPrice = 100 } } }
    assert.equal(7, GC.SellPositions.ListedAtOrBelow(p, 100))
    assert.equal(7, GC.SellPositions.ListedAtOrBelow(p, 110))
    assert.equal(10, GC.SellPositions.ListedAtOrBelow(p, 120))
    assert.equal(10, GC.SellPositions.ListedAtOrBelow(p, nil))
    assert.equal(0, GC.SellPositions.ListedAtOrBelow({}, 100))
  end)

  -- The plan, the panel and the queue, each asked about the same position (the "one at a time"
  -- test in spec/sell_group_rules_spec.lua does the same for the rule alone).
  describe("the three places", function()
    local GC
    local context = { char = "A-R", region = "eu" }
    local FLIP = { name = "Transmog", play = "flip", durationIndex = 2, perItem = 1, floorPct = 70,
      floorUnit = 7000, usualUnit = 10000 }

    before_each(function()
      GC = load()
      GC.Sell = {}
      helper.loadModule("Services/Sell/State.lua", GC)
    end)

    -- Twenty of commodity 10 in the bags, quoted fresh at 12000.
    local function position(rule)
      local args = {
        acquisitions = {}, ownedLots = {},
        bagStock = { { positionKey = "commodity:10", itemID = 10, itemName = "Herb", quantity = 20, isCommodity = true } },
        quotes = { [10] = { unit = 12000, at = 9 } }, statsByItemID = {}, context = context, now = 10,
      }
      if rule then args.rules = { ruleFor = function() return rule end, roundsFor = function() return 0 end } end
      return GC.SellPositions.Build(args)[1]
    end

    local function three(p, typed)
      GC.SellState.quantityOverrides[p.positionKey] = typed
      local duration = GC.Sell.PostDurationFor(p)
      local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 10, exactQty = p.bagQty, positionKey = p.positionKey },
        { unit = p.freshMarketUnit, fresh = true }, { overrideQuantity = typed, durationIndex = duration })
      local panel = GC.SellUtil.postQuantity(p)
      local entries = GC.PostQueue.Build({ p }, { quantities = GC.SellState.quantityOverrides,
        durationFor = function(q) return (GC.Sell.PostDurationFor(q)) end })
      return plan, panel, entries[1]
    end

    for _, case in ipairs({
      { name = "typed", typed = 6, want = 6 },
      { name = "rule", rule = true, want = 1 },
      { name = "pace", pace = true, want = 3 },
      { name = "all", all = true, want = 20 },
    }) do
      it("agree on " .. case.name, function()
        local p = position(case.rule and FLIP or nil)
        if case.pace then
          p.paceTargets = { [2] = 8 }
          p.ownedLots = { { quantity = 5, unitPrice = 100 } }
        end
        local plan, panel, entry = three(p, case.all and GC.SellPositions.ALL or case.typed)
        assert.equal(case.want, plan.quantity)
        assert.equal(case.want, panel)
        assert.equal(case.want, entry.value / entry.unitPrice)
        assert.equal(case.name, plan.quantityWhy)
      end)
    end

    it("the panel says whether the number is the player's, as before", function()
      local p = position(FLIP)
      GC.SellState.quantityOverrides[p.positionKey] = 3
      assert.same({ 3, 20, true, "typed" }, { GC.SellUtil.postQuantity(p) })
      GC.SellState.quantityOverrides[p.positionKey] = nil
      assert.same({ 1, 20, false, "rule" }, { GC.SellUtil.postQuantity(p) })
      GC.SellState.quantityOverrides[p.positionKey] = 50
      assert.same({ 20, 20, false, "all" }, { GC.SellUtil.postQuantity(p) })
    end)

    it("an item with enough listed is held, with its reason", function()
      local p = position()
      p.paceTargets = { [2] = 8 }
      p.ownedLots = { { quantity = 10, unitPrice = 100 } }
      local entries, skipped = GC.PostQueue.Build({ p }, { durationFor = function(q) return (GC.Sell.PostDurationFor(q)) end })
      assert.equal(0, #entries)
      assert.equal("enough_listed", skipped[1].reason)
      assert.same({ nil, "enough_listed", 10 }, { GC.SellPositions.BuildPostPlan(p,
        { itemID = 10, exactQty = p.bagQty, positionKey = p.positionKey },
        { unit = p.freshMarketUnit, fresh = true }, { durationIndex = 2 }) })
      -- Without a duration (retail's queue passes none) the pace is not read.
      entries = GC.PostQueue.Build({ p })
      assert.equal(1, #entries)
      assert.equal(20, entries[1].postableQty)

      local view = { Sell = {} }
      helper.loadModule("Core/QuoteCache.lua", view)
      helper.loadSell(view)
      assert.equal("Enough listed", view.SellUI.fmt.skipText("enough_listed"))
      assert.equal("would sell at a loss", view.SellUI.fmt.skipText("below_breakeven"))
      assert.is_nil(view.SellUI.fmt.skipText("no_such_reason"))
    end)
  end)

  -- The safety harness of spec/sell_action_safety_spec.lua, on a WoW: Forever passport.
  it("the click refuses it in words", function()
    local calls, status = 0, {}
    _G.time = function() return 100 end
    _G.C_Timer = nil
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.C_AuctionHouse = {
      PostCommodity = function() calls = calls + 1 end,
      PostItem = function() calls = calls + 1 end,
    }
    local stacks = { [1] = { itemID = 42, stackCount = 20 } }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function(_, slot) return stacks[slot] end,
    }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return { unit = 200, at = 100 } end },
      Game = { Passport = function() return { interface = 16001 } end,
        IsForever = function(p) return p.interface >= 16000 and p.interface <= 16999 end },
      SellPositions = { BuildPostPlan = function() return nil, "enough_listed", 10 end },
      db = { settings = { sniper = { postDuration = 1 } } } }
    helper.loadModule("Core/GroupRules.lua", GC)
    helper.loadSell(GC)
    GC.Ledger = { Context = function() return { char = "A-R", region = "eu" } end }
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    GC.SellState.bagLocationCache["commodity:42"] = { itemID = 42, bag = 0, slot = 1, location = { bag = 0, slot = 1 } }
    GC.SellView.status = function(text) status[#status + 1] = text end
    local button = {}
    function button:Enable() end
    function button:Disable() end
    function button:SetLabel(label) self.label = label end
    GC.SellUI.Dock.OnPostClick({ position = { itemID = 42, positionKey = "commodity:42",
      scopeKey = "eu\1A-R\1commodity:42", ruleDurationIndex = 2 }, action = button, renderEntryID = "entry:post:42" })
    assert.equal(0, calls)
    assert.is_nil(GC.SellState.postingPin)
    assert.equal("Your 10 already up cover about 8 h of sales. Type a number or press MAX to post more.",
      status[#status])
  end)
end)
