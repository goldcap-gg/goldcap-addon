local helper = require("spec.spec_helper")

-- One duration per post (WoW: Forever plan 2026-11-09, Task 2): the post the click pins, the
-- deposit quoted for it and the panel all read one rule, GC.Sell.PostDurationFor: the duration
-- the player picked for this post, else the followed group's, else the slow sellers' 24 h, else
-- the setting. The click keeps its own plain-field copy of that rule (Services/Sell/Post.lua,
-- read ahead of the protected call), and the cases below pin that the two agree.
describe("one duration per post", function()
  local FOREVER = { interface = 16001 }
  local RETAIL = { interface = 120100 }

  local function game(passport)
    return { Passport = function() return passport end,
      IsForever = function(p) return p.interface >= 16000 and p.interface <= 16999 end }
  end

  after_each(function()
    _G.time, _G.ItemLocation, _G.C_Timer, _G.C_AuctionHouse, _G.C_Container = os.time, nil, nil, nil, nil
  end)

  it("HoursOf answers each game's three durations", function()
    local GC = { Game = game(FOREVER) }
    helper.loadModule("Core/GroupRules.lua", GC)
    assert.same({ 2, 8, 24 }, { GC.GroupRules.HoursOf(1), GC.GroupRules.HoursOf(2), GC.GroupRules.HoursOf(3) })
    GC.Game = game(RETAIL)
    assert.same({ 12, 24, 48 }, { GC.GroupRules.HoursOf(1), GC.GroupRules.HoursOf(2), GC.GroupRules.HoursOf(3) })
    assert.is_nil(GC.GroupRules.HoursOf(0))
    assert.is_nil(GC.GroupRules.HoursOf(4))
    assert.is_nil(GC.GroupRules.HoursOf(nil))
  end)

  -- picked = S.durationOverrides for the position, rule = position.ruleDurationIndex, slow =
  -- position.slowDurationIndex, setting = settings.sniper.postDuration.
  local CASES = {
    { picked = 1, rule = 3, slow = 3, setting = 2, want = 1, why = "picked" },
    { rule = 3, slow = 3, setting = 1, want = 3, why = "rule" },
    { slow = 3, setting = 2, want = 3, why = "slow" },
    { setting = 1, want = 1, why = "setting" },
    { picked = 9, rule = 0, setting = 99, want = 2, why = "setting" },
  }

  local function position(case)
    return { itemID = 42, positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
      character = "A-R", region = "eu", trackedQty = 1, listedQty = 0,
      ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 200 } },
      ruleDurationIndex = case and case.rule, slowDurationIndex = case and case.slow }
  end

  it("PostDurationFor follows picked, rule, slow, setting", function()
    for i, case in ipairs(CASES) do
      local GC = { Sell = {}, db = { settings = { sniper = { postDuration = case.setting } } } }
      helper.loadSell(GC)
      GC.SellState.durationOverrides["commodity:42"] = case.picked
      local index, why = GC.Sell.PostDurationFor(position(case))
      assert.equal(case.want, index, "case " .. i)
      assert.equal(case.why, why, "case " .. i)
    end
  end)

  -- The harness of spec/sell_action_safety_spec.lua's "posts at the configured duration": a stub
  -- plan, a recorder on the protected call, the click-safe bag state primed as a paint would.
  local function harness(setting, opts)
    opts = opts or {}
    local calls, confirms = {}, {}
    local location = { bag = 0, slot = 1 }
    _G.time = function() return 100 end
    _G.C_Timer = nil
    _G.ItemLocation = { CreateFromBagAndSlot = function() return location end }
    _G.C_AuctionHouse = {
      PostCommodity = function(...) calls[#calls + 1] = { ... }; return opts.confirm == true end,
      ConfirmPostCommodity = function(...) confirms[#confirms + 1] = { ... } end,
    }
    local stacks = { [1] = { itemID = 42, stackCount = 2 }, [2] = { itemID = 42, stackCount = 3 } }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot) return stacks[slot] end,
    }
    local quote = { unit = 200, at = 100 }
    local GC = { Sell = {}, QuoteCache = { Fresh = function() return quote end }, SellPositions = {
      BuildPostPlan = function() return { positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        itemID = 42, quantity = 5, unitPrice = 200 } end,
    }, db = { settings = { sniper = { postDuration = setting } } } }
    helper.loadSell(GC)
    GC.Ledger = { Context = function() return { char = "A-R", region = "eu" } end }
    GC.Acquisitions = { ScopeKey = function(positionKey, scope)
      return table.concat({ scope.region, scope.char, positionKey }, "\1")
    end }
    GC.SellQuotes.driver = { keyInfo = function() return { isCommodity = true } end }
    GC.SellState.bagLocationCache["commodity:42"] = { itemID = 42, bag = 0, slot = 1, location = location }
    local button = { enabled = true }
    function button:Enable() self.enabled = true end
    function button:Disable() self.enabled = false end
    function button:SetLabel(label) self.label = label end
    return GC, calls, confirms, button
  end

  it("the click pins the same duration PostDurationFor gives", function()
    for i, case in ipairs(CASES) do
      local GC, calls, _, button = harness(case.setting)
      GC.SellState.durationOverrides["commodity:42"] = case.picked
      local p = position(case)
      GC.SellUI.Dock.OnPostClick({ position = p, action = button, renderEntryID = "entry:post:42" })
      local want = GC.Sell.PostDurationFor(p)
      assert.equal(1, #calls, "case " .. i)
      assert.equal(want, calls[1][2], "case " .. i)
      assert.equal(want, GC.SellState.postingPin.duration, "case " .. i)
      assert.equal(case.picked, GC.SellState.postingPin.pickedDuration, "case " .. i)
    end
  end)

  it("the Confirm lets a post go when the picked duration changed", function()
    -- Unchanged, the second press confirms.
    local GC, calls, confirms, button = harness(2, { confirm = true })
    GC.SellState.durationOverrides["commodity:42"] = 1
    local row = { position = position(), action = button, renderEntryID = "entry:post:42" }
    GC.SellUI.Dock.OnPostClick(row)
    GC.SellUI.Dock.OnPostClick(row)
    assert.equal(1, #calls)
    assert.equal(1, #confirms)

    -- Changed between the two presses, the post it armed is let go and nothing is confirmed.
    GC, calls, confirms, button = harness(2, { confirm = true })
    GC.SellState.durationOverrides["commodity:42"] = 1
    row = { position = position(), action = button, renderEntryID = "entry:post:42" }
    GC.SellUI.Dock.OnPostClick(row)
    assert.equal(1, #calls)
    assert.equal(1, GC.SellState.postingPin.duration)
    GC.SellState.durationOverrides["commodity:42"] = 3
    GC.SellUI.Dock.OnPostClick(row)
    assert.equal(0, #confirms)
    assert.is_nil(GC.SellState.postingPin)
  end)

  it("an item's deposit is quoted at the duration it will post at", function()
    local asked = {}
    _G.C_AuctionHouse = { CalculateItemDeposit = function(location, duration, quantity)
      asked[#asked + 1] = { location = location, duration = duration, quantity = quantity }
      return 300
    end }
    local GC = { Sell = {}, db = { settings = { sniper = { postDuration = 1 } } } }
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadSell(GC)
    local location = { bag = 0, slot = 3 }
    GC.SellBags.ResolveLocation = function() return location end
    local p = { positionKey = "item:7", itemID = 7, ruleDurationIndex = 3 }
    assert.equal(300, GC.SellBags.Deposit(p, 2))
    assert.same({ location = location, duration = 3, quantity = 2 }, asked[1])
    assert.same({ quantity = 2, deposit = 300 }, GC.SellState.depositQuotes["item:7\1" .. 3])
    assert.equal(300, GC.SellBags.Deposit(p, 2, 1))
    assert.equal(1, asked[2].duration)
    assert.same({ quantity = 2, deposit = 300 }, GC.SellState.depositQuotes["item:7\1" .. 1])
  end)

  it("the pin carries the quote of the same quantity and duration", function()
    local GC, _, _, button = harness(2)
    GC.SellState.depositQuotes["commodity:42\1" .. 2] = { quantity = 5, deposit = 123 }
    GC.SellUI.Dock.OnPostClick({ position = position(), action = button, renderEntryID = "entry:post:42" })
    assert.equal(123, GC.SellState.postingPin.deposit)

    GC, _, _, button = harness(2)
    GC.SellState.depositQuotes["commodity:42\1" .. 2] = { quantity = 4, deposit = 123 }
    GC.SellUI.Dock.OnPostClick({ position = position(), action = button, renderEntryID = "entry:post:42" })
    assert.equal(2, GC.SellState.postingPin.duration)
    assert.is_nil(GC.SellState.postingPin.deposit)
  end)

  it("CommodityDeposit takes the duration it is given", function()
    local asked
    _G.C_AuctionHouse = { CalculateCommodityDeposit = function(itemID, duration, quantity)
      asked = { itemID, duration, quantity }
      return 50
    end }
    local GC = { db = { settings = { sniper = { postDuration = 1 } } } }
    helper.loadModule("Core/Flips.lua", GC)
    GC.Flips.CommodityDeposit(42, 5, 3)
    assert.same({ 42, 3, 5 }, asked)
    GC.Flips.CommodityDeposit(42, 5)
    assert.same({ 42, 1, 5 }, asked)
    GC.GroupRules = { durationByItem = { [42] = 2 } }
    GC.Flips.CommodityDeposit(42, 5)
    assert.same({ 42, 2, 5 }, asked)
    GC.Flips.CommodityDeposit(42, 5, 9) -- not a duration: today's rule
    assert.same({ 42, 2, 5 }, asked)
    GC.Flips.CommodityDeposit(42, 5, 1)
    assert.same({ 42, 1, 5 }, asked)
  end)

  -- A live lot went up before anything picked for the next post: its forfeit stays quoted at the
  -- duration GoldCap posts the item at (its group's, else the setting), as before.
  it("a lot's forfeit is quoted at its group's duration, not at one picked for the next post", function()
    local asked
    _G.C_AuctionHouse = { CalculateCommodityDeposit = function(itemID, duration, quantity)
      asked = { itemID, duration, quantity }
      return 50
    end }
    local GC = { Sell = {}, ForeverScan = { Enabled = function() return true end },
      db = { settings = { sniper = { postDuration = 1 } } } }
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadSell(GC)
    GC.SellState.durationOverrides["commodity:42"] = 2
    local lot = { positionKey = "commodity:42", itemID = 42, quantity = 5 }
    GC.GroupRules = { durationByItem = { [42] = 3 } }
    assert.equal(50, GC.Sell.LotForfeit(lot))
    assert.same({ 42, 3, 5 }, asked)
    GC.GroupRules = nil
    GC.Sell.LotForfeit(lot)
    assert.same({ 42, 1, 5 }, asked)
  end)

  it("Reset forgets picked durations and quotes", function()
    local GC = { Sell = {} }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadSell(GC)
    local S = GC.SellState
    S.durationOverrides["commodity:1"] = 3
    S.depositQuotes["commodity:1\1" .. 3] = { quantity = 1, deposit = 10 }
    S.priceOverrides["commodity:1"] = 500
    GC.Sell.Reset()
    assert.is_nil(next(S.durationOverrides))
    assert.is_nil(next(S.depositQuotes))
    assert.equal(500, S.priceOverrides["commodity:1"]) -- the typed price outlives the visit, as before
  end)
end)
