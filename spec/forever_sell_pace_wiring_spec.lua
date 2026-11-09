local helper = require("spec.spec_helper")

-- WoW: Forever posts by sale pace (plan 2026-11-09, Task 5), through the real Sell services and
-- view: Compose hands SellPositions the sale tape and decorates every position with
-- Core/ForeverPace.lua, the queue reads the pace at each post's duration and price, a post the
-- pace capped is done for the visit, and a post certain to be ours counts as listed at once
-- (S.pacePosted) until the owned list holds it. The harness is the "on screen" one of
-- spec/sell_group_rules_wiring_spec.lua: item 10, a commodity, twenty in the bags, on the selling
-- list, the player's duration 8 h (index 2); the tape says three a day sold over a week.
describe("SELL by sale pace on WoW: Forever", function()
  local FOREVER = { interface = 16001 }
  local RETAIL = { interface = 120100 }
  local GC, root, container, posted, timers, sales, BAGS

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint() end
    function v:ClearAllPoints() end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
    function v:SetVariant(name) self.variant = name end
    function v:SetScript(n, f) self.scripts[n] = f end
    function v:HookScript(n, f) self.scripts[n] = f end
    function v:Show() self.shown = true end function v:Hide() self.shown = false end
    function v:IsShown() return self.shown end
    function v:Enable() self.enabled = true end function v:Disable() self.enabled = false end
    function v:ClearFocus() self.focused = false end function v:HasFocus() return self.focused == true end
    function v:SetJustifyH() end function v:SetWordWrap(w) self.wordWrap = w end
    function v:SetTextColor(...) self.color = { ... } end
    function v:SetMaxLines(n) self.maxLines = n end
    function v:SetSpacing() end
    function v:SetAutoFocus() end function v:SetScrollChild() end
    function v:CreateTexture() return region("Texture", self) end
    function v:SetAllPoints() end function v:SetColorTexture() end
    function v:SetTexture() end function v:SetTexCoord() end
    function v:SetTextureSliceMargins() end
    function v:SetVertexColor() end
    function v:SetFrameStrata() end function v:SetFrameLevel() end
    function v:GetFrameLevel() return 0 end function v:EnableMouse() end
    return v
  end

  local function setup(passport)
    BAGS = { [0] = { { itemID = 10, stackCount = 20, itemName = "Herb" } } }
    posted, timers = {}, {}
    sales = { units = 21, sales = 9, median = 12000, perDay = 3, hours = 168 }
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
      GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      PostCommodity = function(_, duration, quantity, unit)
        posted[#posted + 1] = { duration = duration, quantity = quantity, unit = unit }
        return false
      end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Herb" end }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.GameTooltip = {
      SetOwner = function(self) self.owner = true end, GetOwner = function() return nil end,
      AddLine = function() end, Show = function() end, Hide = function() end, SetItemByID = function() end,
    }
    local forever = passport.interface >= 16000 and passport.interface <= 16999
    GC = {
      Sell = {},
      Theme = {
        color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = { .72, .71, .69 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
          zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
          gold = { 1, 1, 0 }, panel = { 0, 0, 0 }, panelHi = { 0.102, 0.114, 0.141 } },
        pad = { xs = 4, s = 8, m = 12, l = 16 },
        MEDIA = "",
        Label = function(p) return region("FontString", p) end,
        Num = function(p) return region("FontString", p) end,
        Button = function(p) return region("Button", p) end,
        Card = function(p) local card = region("Frame", p); function card:SetTint() end return card end,
        SlicedTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
        ItemTooltipOutside = function() end,
        TooltipAnchor = function() return "ANCHOR_RIGHT" end,
      },
      Game = { Passport = function() return passport end,
        IsForever = function(p) return p.interface >= 16000 and p.interface <= 16999 end },
      ForeverScan = { Enabled = function() return forever end },
      Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
        GetEntries = function() return {} end },
      -- The same tape on either game: only Forever's compose may read it.
      Data = { GetItemValue = function() return nil end,
        ForeverSales = function(itemID) return itemID == 10 and sales or nil end },
      db = { settings = { sniper = { postDuration = 2 } }, sellMarks = { ["commodity:10"] = true } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    helper.loadModule("Core/GroupRules.lua", GC)
    -- As each TOC loads it: GoldCap_Camelot.toc alone.
    if forever then helper.loadModule("Core/ForeverPace.lua", GC) end
    helper.loadModule("UI/SellViewModel.lua", GC)
    helper.loadSell(GC)
    GC.Acquisitions.Init({})

    root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    container = GC.SellUI.container
    container:Show()
  end

  after_each(function()
    _G.time = os.time
    _G.C_Timer, _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil, nil
    _G.CreateFrame, _G.GetCoinTextureString, _G.ItemLocation, _G.GameTooltip = nil, nil, nil, nil
  end)

  local function ready(ask)
    GC.QuoteCache.Set(GC.SellState.quotes, 10, ask, time())
    GC.SellCompose.Positions()
    GC.SellUI.List.RenderRows()
  end

  local function position() return GC.SellState.positions[1] end

  local function herbRow()
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" and row.position.itemID == 10 then return row end
    end
  end

  local function post()
    container.queueButton.scripts.OnClick(container.queueButton)
  end

  -- The auction house's list of the player's own auctions, as the client gives it.
  local function owned(lots)
    _G.C_AuctionHouse.GetOwnedAuctions = function() return lots end
    GC.Sell.OnOwnedAuctions()
  end

  local function reasonOf(list, key)
    for _, entry in ipairs(list or {}) do
      if entry.positionKey == key then return entry.reason end
    end
  end

  describe("on WoW: Forever", function()
    before_each(function() setup(FOREVER) end)

    it("POST lists what sells in 8 h", function()
      ready(12000)
      assert.same({ 1, 1, 3 }, position().paceTargets)
      local entry = GC.SellState.queueEntries[1]
      assert.equal("commodity:10", entry.positionKey)
      assert.equal(entry.unitPrice * 1, entry.value) -- Target(3, 8) = 1
      post()
      assert.equal(1, #posted)
      assert.equal(1, posted[1].quantity)
      assert.equal(2, posted[1].duration)
      assert.is_true(GC.SellState.postingPin.paceCapped)
    end)

    it("a post the pace capped is done for the visit", function()
      ready(12000)
      post()
      assert.equal(1, posted[1].quantity) -- nineteen stay in the bags
      GC.Sell.OnAuctionCreated(501)
      assert.is_true(GC.SellState.postedThisVisit["commodity:10"])
    end)

    it("a second POST in the same visit is held", function()
      ready(12000)
      post()
      GC.Sell.OnAuctionCreated(501)
      assert.same({ { auctionID = 501, quantity = 1, unitPrice = 12000 } }, GC.SellState.pacePosted["commodity:10"])
      BAGS[0][1].stackCount = 19
      ready(12000)
      local _, skipped = GC.PostQueue.Build(GC.SellState.positions, GC.Sell._QueueOpts())
      assert.equal("enough_listed", reasonOf(skipped, "commodity:10"))
      assert.equal(1, GC.SellPositions.ListedAtOrBelow(position(), 12000))
      -- The row's own Post is held in words, and posts nothing.
      local row = herbRow()
      GC.SellUI.Dock.OnPostClick(row)
      assert.equal(1, #posted)
      assert.equal("Your 1 already up cover about 8 h of sales. Type a number or press MAX to post more.",
        GC.Sell._lastStatus)
      -- Once the owned list holds the lot it counts from there, once.
      owned({ { auctionID = 501, itemKey = { itemID = 10 }, quantity = 1, unitPrice = 12000, isCommodity = true } })
      ready(12000)
      assert.is_nil(position().paceRecent)
      assert.equal(1, GC.SellPositions.ListedAtOrBelow(position(), 12000))
      _, skipped = GC.PostQueue.Build(GC.SellState.positions, GC.Sell._QueueOpts())
      assert.equal("enough_listed", reasonOf(skipped, "commodity:10"))
    end)

    it("a lot the owned list has held is not counted again once it sells", function()
      ready(12000)
      post()
      GC.Sell.OnAuctionCreated(501)
      BAGS[0][1].stackCount = 19
      owned({ { auctionID = 501, itemKey = { itemID = 10 }, quantity = 1, unitPrice = 12000, isCommodity = true } })
      ready(12000)
      assert.is_nil(GC.SellState.pacePosted["commodity:10"])
      -- Sold: off the owned list, and nothing of it is up any more.
      owned({})
      ready(12000)
      assert.equal(0, GC.SellPositions.ListedAtOrBelow(position(), 12000))
      local entries = GC.PostQueue.Build(GC.SellState.positions, GC.Sell._QueueOpts())
      assert.equal(1, entries[1].postableQty)
    end)

    it("a guessed creation notes nothing", function()
      ready(12000)
      post()
      -- The watchdog gives up on the post: its answer is listened for a minute.
      for _, timer in ipairs(timers) do
        if timer.seconds == 8 then timer.fn() end
      end
      assert.is_nil(GC.SellState.postingRow)
      assert.equal(1, #GC.Sell._LiveLate())
      -- A creation the client names nothing about: the order rule gives it to that post.
      GC.Sell.OnAuctionCreated(502)
      assert.equal(0, #GC.Sell._LiveLate())
      assert.is_nil(next(GC.SellState.pacePosted))
    end)

    it("slow sellers go up for 24 h", function()
      sales.perDay = 0.5
      ready(12000)
      assert.same({ 3, "slow" }, { GC.Sell.PostDurationFor(position()) })
      assert.equal("pace", position().slowWhy)
      post()
      assert.equal(3, posted[1].duration)
      assert.equal(1, posted[1].quantity)
    end)

    it("slow sellers stay at the setting when the player turned it off", function()
      sales.perDay = 0.5
      GC.db.settings.sniper.foreverSlowSellers24h = false
      ready(12000)
      assert.same({ 2, "setting" }, { GC.Sell.PostDurationFor(position()) })
      assert.is_nil(position().slowDurationIndex)
    end)

    it("Reset forgets the visit's posts", function()
      ready(12000)
      post()
      GC.Sell.OnAuctionCreated(501)
      assert.is_not_nil(GC.SellState.pacePosted["commodity:10"])
      GC.Sell.Reset()
      assert.is_nil(next(GC.SellState.pacePosted))
    end)

    -- M3 (review of Tasks 1-3): a price the player types moves what the queue counts as already up
    -- at once, so the queue and the click agree on it before the next compose.
    describe("a typed price", function()
      local function typePrice(text)
        local box = container.priceBox
        box.scripts.OnEditFocusGained(box)
        box:SetText(text)
        box.scripts.OnTextChanged(box, true)
        box.scripts.OnEnterPressed(box)
      end

      it("over our own lot holds the item, as the click does", function()
        owned({ { auctionID = 77, itemKey = { itemID = 10 }, quantity = 1, unitPrice = 13000, isCommodity = true } })
        ready(12000)
        assert.equal("commodity:10", GC.SellState.queueEntries[1].positionKey)
        assert.equal("commodity:10", GC.SellUI.PostPanel.key)
        typePrice("1.3")
        assert.equal(13000, GC.SellState.priceOverrides["commodity:10"])
        assert.equal(0, #GC.SellState.queueEntries)
        assert.equal("enough_listed", reasonOf(GC.SellState.queueSkipped, "commodity:10"))
        assert.same({ nil, "enough_listed", 1 }, { GC.SellPositions.BuildPostPlan(position(),
          { itemID = 10, exactQty = 20, positionKey = "commodity:10" }, { unit = 12000, fresh = true },
          { overrideUnit = 13000, durationIndex = 2 }) })
      end)

      it("under our own lot posts the item, as the click does", function()
        owned({ { auctionID = 77, itemKey = { itemID = 10 }, quantity = 1, unitPrice = 12000, isCommodity = true } })
        ready(12000)
        assert.equal("enough_listed", reasonOf(GC.SellState.queueSkipped, "commodity:10"))
        assert.equal("commodity:10", GC.SellUI.PostPanel.key)
        typePrice("1.1")
        assert.equal("commodity:10", GC.SellState.queueEntries[1].positionKey)
        post()
        assert.equal(1, #posted)
        assert.equal(1, posted[1].quantity)
        assert.equal(11000, posted[1].unit)
      end)

      it("from the item panel's chips moves the queue the same way", function()
        GC.Data.GetItemValue = function() return { mv = 13000 } end
        owned({ { auctionID = 77, itemKey = { itemID = 10 }, quantity = 1, unitPrice = 13000, isCommodity = true } })
        ready(12000)
        assert.equal("commodity:10", GC.SellState.queueEntries[1].positionKey)
        GC.SellUI.expanded = { ["commodity:10"] = true }
        GC.SellUI.List.RenderRows()
        local drawer
        for _, row in ipairs(GC.SellUI.rows) do
          if row:IsShown() and row.kind == "drawer" then drawer = row end
        end
        local market = drawer.priceChips[4] -- MARKET: the item's value, 13000
        assert.equal(13000, market.priceSource)
        market.scripts.OnClick(market)
        assert.equal(13000, GC.SellState.priceOverrides["commodity:10"])
        assert.equal(0, #GC.SellState.queueEntries)
        assert.equal("enough_listed", reasonOf(GC.SellState.queueSkipped, "commodity:10"))
      end)
    end)
  end)

  -- Retail proof: the same tape stub, and nothing reads it. Every unit goes up at the setting's
  -- duration, as before.
  describe("on retail", function()
    before_each(function() setup(RETAIL) end)

    it("posts all of it at the setting's duration", function()
      assert.is_nil(GC.ForeverPace)
      ready(12000)
      local p = position()
      assert.is_nil(p.tape)
      assert.is_nil(p.paceTargets)
      assert.is_nil(p.slowDurationIndex)
      post()
      assert.equal(1, #posted)
      assert.equal(20, posted[1].quantity)
      assert.equal(2, posted[1].duration)
      assert.is_false(GC.SellState.postingPin.paceCapped)
      GC.Sell.OnAuctionCreated(501)
      assert.is_nil(next(GC.SellState.pacePosted))
    end)
  end)
end)
