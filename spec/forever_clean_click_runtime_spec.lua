local helper = require("spec.spec_helper")

-- Final review "Specs": spec/forever_clean_click_order_spec.lua guards handler SOURCE TEXT --
-- it cannot see what a handler's own helpers go on to call, which is exactly how C1-C3 slipped
-- past it (onQueueClick's renderRows(), onRepostClick's composePositions(true), the busy look's
-- SetBusy -- none of them live in the click handler's own body, so the text guard never read
-- them). This file drives the real click handlers instead, through the same end-to-end harnesses
-- spec/sell_post_queue_control_spec.lua, spec/sell_cancel_queue_control_spec.lua and
-- spec/caps_purchase_spec.lua already use, and watches a SHARED ORDER LOG that every stubbed
-- Blizzard mixin call (ItemLocation:CreateFromBagAndSlot, CreateFrame(..., "SpinnerTemplate"))
-- and every protected C_AuctionHouse call appends to. The assertion is always the same: the
-- protected call is the FIRST thing logged for that click -- nothing Blizzard-Lua-shaped ran
-- ahead of it, whatever GoldCap's own bookkeeping did before or after.
describe("Clean click ordering, driven end to end", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local n, val = debug.getupvalue(fn, i)
      if not n then break end
      if n == wanted then return val end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local n = debug.getupvalue(fn, i)
      if not n then break end
      if n == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  -- The shared log every click path below is checked against: `log[1]` must be the protected
  -- call's own name once a click has fired one, or the click drove nothing yet.
  local log

  local function record(name)
    log[#log + 1] = name
  end

  local function assertCleanCall(name)
    assert.is_true(#log > 0, name .. " was never logged -- the click made no protected call")
    assert.equal(name, log[1], ("%s was not first: %s ran before it in the same click")
      :format(name, table.concat(log, ", ", 1, math.max(1, #log - 1))))
  end

  local PROTECTED = { PostCommodity = true, PostItem = true, ConfirmPostCommodity = true,
    ConfirmPostItem = true, CancelAuction = true, StartCommoditiesPurchase = true,
    ConfirmCommoditiesPurchase = true, PlaceBid = true }

  -- A click that only arms (renders, paints, caches a bag location for next time) is free to
  -- log ItemLocation/CreateFrame calls of its own -- that is what a render is for, outside a
  -- protected-call click. What it must never do is reach a protected call at all.
  local function assertNoProtectedCall()
    for _, name in ipairs(log) do
      assert.is_nil(PROTECTED[name], name .. " ran on a click that should have armed only")
    end
  end

  -- Wired onto whatever table/key combination the harness's ItemLocation/CreateFrame/
  -- C_AuctionHouse doubles already use, so the click paths keep behaving exactly as their own
  -- spec files prove -- only the extra bookkeeping (the order log) is new.
  local function wrapItemLocation()
    local real = _G.ItemLocation.CreateFromBagAndSlot
    _G.ItemLocation.CreateFromBagAndSlot = function(...)
      record("ItemLocation.CreateFromBagAndSlot")
      if real then return real(...) end
    end
  end

  local function wrapCreateFrame(regionFn)
    _G.CreateFrame = function(kind, _, parent, template)
      if template == "SpinnerTemplate" then record("CreateFrame:SpinnerTemplate") end
      return regionFn(kind, parent)
    end
  end

  local function wrapAH(names)
    for _, name in ipairs(names) do
      local real = _G.C_AuctionHouse[name]
      _G.C_AuctionHouse[name] = function(...)
        record(name)
        if real then return real(...) end
      end
    end
  end

  describe("SellFrame.lua, the Post/queue paths", function()
    local GC, root, render, container

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
      function v:SetJustifyH() end function v:SetWordWrap() end function v:SetTextColor(...) self.color = { ... } end
      function v:SetMaxLines(n) self.maxLines = n end
      function v:SetSpacing() end
      function v:SetAutoFocus() end function v:SetScrollChild() end
      function v:CreateTexture() return region("Texture", self) end
      function v:SetAllPoints() end function v:SetColorTexture() end
      function v:SetTexture() end function v:SetTexCoord() end
      function v:SetTextureSliceMargins() end function v:SetVertexColor() end
      function v:SetFrameStrata() end function v:SetFrameLevel() end
      function v:GetFrameLevel() return 0 end function v:EnableMouse() end
      return v
    end

    -- Two commodities, mirroring spec/sell_post_queue_control_spec.lua: Eternium Ore is priced
    -- and postable, Widget never gets a quote so it never enters the queue.
    local BAGS = {
      [0] = {
        { itemID = 23427, stackCount = 200, itemName = "Eternium Ore" },
        { itemID = 23427, stackCount = 46, itemName = "Eternium Ore" },
        { itemID = 99001, stackCount = 5, itemName = "Widget" },
      },
    }
    local ITEM_NAMES = { [23427] = "Eternium Ore", [99001] = "Widget" }

    before_each(function()
      log = {}
      _G.time = function() return 1000 end
      wrapCreateFrame(region)
      _G.GetCoinTextureString = function(n) return tostring(n) end
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
        GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
        GetContainerItemLink = function() return nil end,
      }
      _G.C_AuctionHouse = {
        MakeItemKey = function(itemID) return { itemID = itemID } end,
        GetItemKeyInfo = function() return { isCommodity = true } end,
        PostCommodity = function() return false end,
        ConfirmPostCommodity = function() end,
      }
      wrapAH({ "PostCommodity", "ConfirmPostCommodity" })
      _G.C_Item = { GetItemNameByID = function(id) return ITEM_NAMES[id] end }
      _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
      wrapItemLocation()

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
        },
        Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
          GetEntries = function() return {} end },
        Data = { GetItemValue = function() return { sold = 7447 } end },
      }
      helper.loadModule("Core/Util.lua", GC)
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("Core/BagStock.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      helper.loadModule("Core/PostQueue.lua", GC)
      helper.loadModule("UI/SellViewModel.lua", GC)
      helper.loadModule("UI/SellFrame.lua", GC)
      GC.Acquisitions.Init({})

      root = region("Frame")
      root.HookScript = function(_, n, f) root.scripts[n] = f end
      root.status = region("FontString", root)
      GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
        rowWidth = 1100, rowHeight = 24 })
      render = upvalue(GC.Sell.Attach, "renderRows")
      container = upvalue(render, "container")
      container:Show()
    end)

    after_each(function()
      _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
      _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation = nil, nil, nil, nil
    end)

    local function compose()
      upvalue(GC.Sell.SellableCount, "composePositions")()
    end

    local function quotes()
      return upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    end

    local function oreRow()
      for _, row in ipairs(upvalue(render, "rows")) do
        if row:IsShown() and row.kind == "position" and row.position.itemID == 23427 then return row end
      end
      error("Eternium Ore row is not on screen")
    end

    it("Post's first click: the row's own button", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose(); render()
      log = {}
      local row = oreRow()
      row.action.scripts.OnClick(row.action)
      assertCleanCall("PostCommodity")
    end)

    it("Post's Confirm click, once PostCommodity itself asked for one", function()
      _G.C_AuctionHouse.PostCommodity = function() return true end
      wrapAH({ "PostCommodity" })
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose(); render()
      local row = oreRow()
      row.action.scripts.OnClick(row.action) -- first click: posts, asks for Confirm
      assert.equal("confirm", row.postStage)
      log = {}
      row.action.scripts.OnClick(row.action) -- Confirm
      assertCleanCall("ConfirmPostCommodity")
    end)

    it("the dock's POST queue button, on the click that actually posts", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      local button = container.queueButton
      -- The first click only switches into queue mode and renders it (final review C1): no
      -- protected call in that click at all.
      button.scripts.OnClick(button)
      assertNoProtectedCall()
      log = {}
      button.scripts.OnClick(button)
      assertCleanCall("PostCommodity")
    end)

    it("the POST keybinding (f.GoldCapPostNext), the same handler onQueueClick is", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      root.GoldCapPostNext()
      assertNoProtectedCall()
      log = {}
      root.GoldCapPostNext()
      assertCleanCall("PostCommodity")
    end)
  end)

  describe("SellFrame.lua, the Cancel lot paths", function()
    local GC, root, render, container

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
      function v:SetJustifyH() end function v:SetWordWrap() end function v:SetTextColor(...) self.color = { ... } end
      function v:SetMaxLines(n) self.maxLines = n end
      function v:SetSpacing() end
      function v:SetAutoFocus() end function v:SetScrollChild() end
      function v:CreateTexture() return region("Texture", self) end
      function v:SetAllPoints() end function v:SetColorTexture() end
      function v:SetTexture() end function v:SetTexCoord() end
      function v:SetTextureSliceMargins() end function v:SetVertexColor() end
      function v:SetFrameStrata() end function v:SetFrameLevel() end
      function v:GetFrameLevel() return 0 end function v:EnableMouse() end
      return v
    end

    local now
    -- One unbound Eternium Ore stack sits in the bags alongside the lot: this is what makes
    -- the pre-C2 composePositions(true) taint reachable at all (classifyBagItem's
    -- IsSellItemValid(ItemLocation:CreateFromBagAndSlot(...)) call only ever runs for a
    -- non-commodity, unbound bag stock -- so a gear item is what the beta actually tripped on).
    local BAGS = {
      [0] = { { itemID = 19019, stackCount = 1, itemName = "Thunderfury",
        hyperlink = "item:19019:0:0:0:0:0:0:0:0:0", isBound = false } },
    }
    local OWNED = { { auctionID = 77, itemKey = { itemID = 23427 }, quantity = 400,
      unitPrice = 27300, isCommodity = true } }

    before_each(function()
      log = {}
      now = 1000
      _G.time = function() return now end
      wrapCreateFrame(region)
      _G.GetCoinTextureString = function(n) return tostring(n) end
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
        GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
        GetContainerItemLink = function(bag, slot)
          local item = (BAGS[bag] or {})[slot]
          return item and item.hyperlink or nil
        end,
      }
      _G.C_AuctionHouse = {
        MakeItemKey = function(itemID) return { itemID = itemID } end,
        GetItemKeyInfo = function() return { isCommodity = true } end,
        GetOwnedAuctions = function() return OWNED end,
        QueryOwnedAuctions = function() end,
        CancelAuction = function() end,
        -- The exact non-commodity taint site classifyBagItem calls while the auction house is
        -- open (final review C2's own root cause): logged too, so a regression that brings back
        -- composePositions(true) before CancelAuction fails loudly here, not just in-client.
        IsSellItemValid = function() return true end,
      }
      wrapAH({ "CancelAuction" })
      _G.C_Item = { GetItemNameByID = function() return "Sanguithorn Tea" end }
      _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
      wrapItemLocation()

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
        },
        Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
          GetEntries = function() return {} end },
        Data = { GetItemValue = function() return { sold = 7447 } end },
      }
      helper.loadModule("Core/Util.lua", GC)
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("Core/BagStock.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      helper.loadModule("Core/PostQueue.lua", GC)
      helper.loadModule("Core/CancelQueue.lua", GC)
      helper.loadModule("UI/SellViewModel.lua", GC)
      helper.loadModule("UI/SellFrame.lua", GC)
      GC.Acquisitions.Init({})
      assert(GC.Acquisitions.RecordManual({ itemID = 23427, positionKey = "commodity:23427",
        itemName = "Sanguithorn Tea", quantity = 400, total = 4000000, acquiredAt = 900,
        character = "Owner-Dentarg", region = "eu" }))

      root = region("Frame")
      root.HookScript = function(_, n, f) root.scripts[n] = f end
      root.status = region("FontString", root)
      GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
        rowWidth = 1100, rowHeight = 24 })
      render = upvalue(GC.Sell.Attach, "renderRows")
      container = upvalue(render, "container")
      set(render, "filterMode", "listed")
      container:Show()
      GC.Sell.OnOwnedAuctions()
    end)

    after_each(function()
      _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
      _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation = nil, nil, nil, nil
    end)

    local function compose()
      upvalue(GC.Sell.SellableCount, "composePositions")()
    end

    local function quotes()
      return upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    end

    local function armedLotRow()
      for _, row in ipairs(upvalue(render, "rows")) do
        if row.kind == "lot" and row.lot and row.lot.auctionID == 77 then return row end
      end
      return nil
    end

    it("Cancel lot's confirming click, from the row's own button", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose(); render()
      local action
      for _, row in ipairs(upvalue(render, "rows")) do
        if row.shown and row.kind == "position" then action = row.action end
      end
      log = {}
      action.scripts.OnClick(action) -- arm: no protected call
      assertNoProtectedCall()
      armedLotRow().repostReady = true
      log = {}
      action.scripts.OnClick(action) -- confirm
      assertCleanCall("CancelAuction")
    end)

    it("the cancel queue control, on the confirming click", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose()
      local button = container.cancelButton
      log = {}
      button.scripts.OnClick(button) -- arm through ROW.armLot: no protected call
      assertNoProtectedCall()
      armedLotRow().repostReady = true
      log = {}
      button.scripts.OnClick(button) -- confirm
      assertCleanCall("CancelAuction")
    end)
  end)

  -- The Sniper buy dialog, on the same seam spec/caps_purchase_spec.lua drives it through --
  -- onDialogPrimaryClick reached by upvalue chain from a real board row's own click, not a
  -- hand-built double of the handler.
  describe("SniperFrame.lua buy dialog (onDialogPrimaryClick)", function()
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

    local books, money, cancels, confirms

    local function loadSniper()
      books, money, cancels, confirms = {}, 10000000000, 0, 0
      _G.time = function() return 100000 end
      _G.GetTime = function() return 100 end
      _G.GetMoney = function() return money end
      _G.GetCoinTextureString = function(value) return tostring(value) end
      _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
      _G.SOUNDKIT = { RAID_WARNING = 1, MAP_PING = 2, READY_CHECK = 3 }
      _G.PlaySound = function() end
      _G.ITEM_QUALITY_COLORS = {}
      _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
      wrapCreateFrame(function(kind) local f = { kind = kind }
        function f:SetSize() end function f:SetPoint() end function f:Hide() end function f:Show() end
        function f:SetScript() end
        return f
      end)
      _G.C_AuctionHouse = {
        CalculateCommodityDeposit = function() return 0 end,
        CancelCommoditiesPurchase = function() cancels = cancels + 1 end,
        ConfirmCommoditiesPurchase = function() confirms = confirms + 1 end,
        StartCommoditiesPurchase = function() end,
        PlaceBid = function() end,
        MakeItemKey = function(itemID) return { itemID = itemID } end,
        HasFullBrowseResults = function() return false end,
        GetNumCommoditySearchResults = function() return 0 end,
        GetCommoditySearchResultInfo = function() return nil end,
      }
      wrapAH({ "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "PlaceBid" })
      local sniper = { sound = false, showRefused = false, watchPins = {},
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 50000, minimumRoi = 0.10 }
      local GC = {
        Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
          tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
          color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
            fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
            green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
        AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end } end },
        Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end,
          RecordFlip = function() end },
        Print = function() end,
        db = { settings = { sniper = sniper } },
      }
      helper.loadModule("Core/Util.lua", GC)
      helper.loadModule("Core/Book.lua", GC)
      helper.loadModule("Core/SniperDecision.lua", GC)
      helper.loadModule("Core/CheckVerdict.lua", GC)
      helper.loadModule("Core/DealMath.lua", GC)
      helper.loadModule("Core/Trigger.lua", GC)
      helper.loadModule("Core/FullScan.lua", GC)
      helper.loadModule("Core/AutoScan.lua", GC)
      helper.loadModule("Core/BookPass.lua", GC)
      helper.loadModule("Core/DrillQueue.lua", GC)
      helper.loadModule("Core/KeyPoll.lua", GC)
      helper.loadModule("Core/BoardRows.lua", GC)
      helper.loadModule("Core/Caps.lua", GC)
      helper.loadModule("Core/Ledger.lua", GC)
      helper.loadModule("Core/Acquisitions.lua", GC)
      local saved = {}
      GC.Ledger.Init(saved)
      GC.Acquisitions.Init(saved)
      helper.loadModule("UI/SniperFrame.lua", GC)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
        isReady = function() return true end,
        getKeyInfo = function() return { isCommodity = true } end,
        sendSearch = function() end,
        commodityBook = function(itemID) return books[itemID] end,
        commodityResult = function(itemID) return books[itemID] and { avail = 1 } or nil end,
        itemResult = function() return {} end,
        itemLots = function() return {} end,
        onStatus = function() end,
      })
      return GC
    end

    local function adoptCap(GC, itemID, c, l)
      _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {},
        caps = { { i = itemID, c = c, l = l or 0 } } }
      GC.Caps.Adopt()
    end

    local function recorder()
      local w = { text = "", shown = nil }
      function w:SetText(t) self.text = t end
      function w:SetTextColor() end
      function w:Show() self.shown = true end
      function w:Hide() self.shown = false end
      function w:ClearAllPoints() end
      function w:SetPoint() end
      function w:SetHeight() end
      function w:GetStringHeight() return 24 end
      return w
    end

    local function fakeDialog(row, deal)
      local d = { row = row, deal = deal, written = {}, enabled = false, height = 0, baseHeight = 400 }
      d.primaryBtn = {
        Disable = function() d.enabled = false end,
        Enable = function() d.enabled = true end,
        IsEnabled = function() return d.enabled end,
        SetLabel = function(_, text) d.label = text end,
        text = { SetTextColor = function() end },
      }
      d.cancelBtn = { Enable = function() end, Disable = function() end, SetLabel = function() end }
      d.status = {
        SetText = function(_, text) d.written[#d.written + 1] = text end,
        SetTextColor = function() end, ClearAllPoints = function() end, SetPoint = function() end,
      }
      d.banner = { shown = false,
        Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
        IsShown = function(self) return self.shown end,
        head = { SetText = function(_, text) d.bannerHead = text end }, detail = { SetText = function() end } }
      d.SetHeight = function(_, height) d.height = height end
      d.Hide = function() end
      d.IsShown = function() return true end
      d.fixedHeight, d.diagnosticGaps, d.diagnosticMinimumHeight = 400, 4, 108
      d.detailsOpen, d.evidenceTopOpen, d.evidenceTopClosed = false, -200, -100
      for _, field in ipairs({ "decisionStatusText", "unitPriceText", "totalCostText", "exitUnitText",
        "profitText", "mvText", "soldText", "sellThroughText", "sourceAgeText", "reasonText",
        "verdictHead", "verdictSub", "diagnosticText", "mvNote", "nameText", "qtyLotText",
        "qtyOfLabel" }) do
        d[field] = recorder()
      end
      d.tierChip = { SetLabel = function() end, Show = function() end, Hide = function() end }
      d.icon = { SetTexture = function() end }
      local editBox = { text = "" }
      function editBox:SetText(t) self.text = t end
      function editBox:GetText() return self.text end
      function editBox:HasFocus() return false end
      function editBox:ClearFocus() end
      function editBox:EnableMouse() end
      function editBox:SetTextColor() end
      d.qtyBox = { editBox = editBox, Show = function() end, Hide = function() end }
      d.quickFillBtns = {}
      return d
    end

    local function capLive(GC, itemID, levels)
      books[itemID] = levels
      local evaluate = getUpvalue(GC.Sniper.OnCommoditySearchResults, "evaluateLiveCommodityDeal")
      return evaluate(itemID, levels)
    end

    local function boardDeal(GC, itemID)
      return GC.Sniper._CurrentLiveDeal(itemID)
    end

    local function armReadyFn(GC)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local applyRequeryResult = getUpvalue(finishRequery, "applyRequeryResult")
      return getUpvalue(applyRequeryResult, "armReady")
    end

    local function armOnDialog(GC, row, deal, decision, levels)
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      armReadyFn(GC)(row, deal, decision, levels)
      return d
    end

    local function clickHandler(GC)
      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = getUpvalue(clearDeals, "refreshRows")
      local createRow = getUpvalue(refreshRows, "createRow")
      local buildRowCell = getUpvalue(createRow, "buildRowCell")
      local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      local createDialog = getUpvalue(openDialog, "createDialog")
      return getUpvalue(createDialog, "onDialogPrimaryClick")
    end

    after_each(function()
      _G.time, _G.GetTime, _G.GetMoney, _G.GetCoinTextureString = os.time, nil, nil, nil
      _G.C_Timer, _G.SOUNDKIT, _G.PlaySound, _G.ITEM_QUALITY_COLORS, _G.Item = nil, nil, nil, nil, nil
      _G.C_AuctionHouse, _G.GoldCap_AppRuns, _G.CreateFrame = nil, nil, nil
    end)

    it("Start (StartCommoditiesPurchase), on a cap decision's own Buy", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 200 } })
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseToken = 1 }
      armOnDialog(GC, row, deal, live.decision, { { unitPrice = 900000, quantity = 200 } })
      local click = clickHandler(GC)
      log = {}
      click()
      assertCleanCall("StartCommoditiesPurchase")
    end)

    it("Confirm (ConfirmCommoditiesPurchase), once the quote holds against the cap plan", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 200 } })
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseToken = 1 }
      local d = armOnDialog(GC, row, deal, live.decision, { { unitPrice = 900000, quantity = 200 } })
      local click = clickHandler(GC)
      click() -- Start
      GC.Sniper.OnCommodityPriceUpdated(900000, 900000 * 200) -- the server's own quote, unchanged
      assert.equal("confirm", row.purchaseStage)
      assert.is_true(d.enabled)
      log = {}
      click()
      assertCleanCall("ConfirmCommoditiesPurchase")
    end)

    it("PlaceBid, on a realm lot at or under the player's own price", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } })
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 800000, qty = 1,
        auctionID = 9, stale = true }
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      assert.equal("ready", row.purchaseStage)
      assert.is_true(d.enabled)
      local click = clickHandler(GC)
      log = {}
      click()
      assertCleanCall("PlaceBid")
    end)
  end)
end)
