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

  -- The shared log every click path below is checked against: `log[1]` must be the protected
  -- call's own name once a click has fired one, or the click drove nothing yet.
  local log

  local function record(name)
    log[#log + 1] = name
  end

  local function logged(name)
    for i, entry in ipairs(log) do if entry == name then return i end end
    return nil
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
      -- Theme.lua's own SetBusy (UI/Theme.lua:889): the first busy look mints a SpinnerTemplate.
      function v:SetBusy(on)
        if on and not self.spinner then
          self.spinner = _G.CreateFrame("Frame", nil, self, "SpinnerTemplate")
        end
      end
      function v:SetScript(n, f) self.scripts[n] = f end
      function v:HookScript(n, f) self.scripts[n] = f end
      function v:Show() self.shown = true end function v:Hide() self.shown = false end
      function v:IsShown() return self.shown end
      function v:Enable() self.enabled = true end function v:Disable() if log then record("Disable") end self.enabled = false end
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
      helper.loadSell(GC)
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
      _G.GetBuildInfo = nil
    end)

    local function compose()
      upvalue(GC.Sell.SellableCount, "composePositions")()
    end

    local function quotes()
      return GC.SellState.quotes
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
      -- Reach: the busy look really ran in this click -- after the call, never before it.
      assert.is_truthy(logged("CreateFrame:SpinnerTemplate"))
      assert.is_true(logged("CreateFrame:SpinnerTemplate") > logged("PostCommodity"))
      -- And the clicked button went busy after the call, never before it (WoW: Forever refuses
      -- a protected call from a button disabled ahead of it).
      assert.is_truthy(logged("Disable"))
      assert.is_true(logged("Disable") > logged("PostCommodity"))
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

    -- The dock's two-press split is WoW: Forever's only (retail drift audit F1): the passport
    -- below is Forever's, read fresh by onQueueClick through the real Core/Game.lua.
    local function forever()
      helper.loadModule("Core/Game.lua", GC)
      _G.GetBuildInfo = function() return "1.60.1", "69977", "Sep 23 2026", 16001 end
    end

    it("the dock's POST queue button, on the click that actually posts", function()
      forever()
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
      forever()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      root.GoldCapPostNext()
      assertNoProtectedCall()
      log = {}
      root.GoldCapPostNext()
      assertCleanCall("PostCommodity")
    end)

    -- Retail keeps addon-v0.15.3's one press: the render runs inside the same click, ahead of the
    -- call, exactly as it always has there. Pinned so the Forever split never leaks back in.
    it("on retail the dock's POST and the keybinding post on the first press, as 0.15.3 did", function()
      helper.loadModule("Core/Game.lua", GC)
      _G.GetBuildInfo = function() return "12.1.0", "69933", "Sep 23 2026", 120100 end
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.is_truthy(logged("PostCommodity"))
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
      -- Theme.lua's own SetBusy (UI/Theme.lua:889): the first busy look mints a SpinnerTemplate.
      function v:SetBusy(on)
        if on and not self.spinner then
          self.spinner = _G.CreateFrame("Frame", nil, self, "SpinnerTemplate")
        end
      end
      function v:SetScript(n, f) self.scripts[n] = f end
      function v:HookScript(n, f) self.scripts[n] = f end
      function v:Show() self.shown = true end function v:Hide() self.shown = false end
      function v:IsShown() return self.shown end
      function v:Enable() self.enabled = true end function v:Disable() if log then record("Disable") end self.enabled = false end
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
        -- Thunderfury (19019) answers as an ITEM, not a commodity, so classifyBagItem's
        -- IsSellItemValid branch is actually reachable -- previously every key answered
        -- "commodity" and that branch was dead code as far as this fixture went.
        GetItemKeyInfo = function(key) return { isCommodity = not (key and key.itemID == 19019) } end,
        GetOwnedAuctions = function() return OWNED end,
        QueryOwnedAuctions = function() end,
        CancelAuction = function() end,
        -- The exact non-commodity taint site classifyBagItem calls while the auction house is
        -- open (final review C2's own root cause): logged too, so a regression that brings back
        -- composePositions(true) before CancelAuction fails loudly here, not just in-client.
        IsSellItemValid = function() return true end,
      }
      wrapAH({ "CancelAuction", "IsSellItemValid" })
      _G.C_Item = { GetItemNameByID = function() return "Sanguithorn Tea" end }
      _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
      wrapItemLocation()

      GC = {
        Sell = {},
        -- classifyBagItem's IsSellItemValid branch also requires GC.Sniper.IsAHOpen(): absent
        -- before, so the branch was unreachable on that count too.
        Sniper = { IsAHOpen = function() return true end },
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
      helper.loadSell(GC)
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
      GC.SellState.filterMode = "listed"
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
      return GC.SellState.quotes
    end

    local function armedLotRow()
      for _, row in ipairs(upvalue(render, "rows")) do
        if row.kind == "lot" and row.lot and row.lot.auctionID == 77 then return row end
      end
      return nil
    end

    it("reaches the item branch at a render, so the confirm test below is not blind to it", function()
      log = {}
      compose(); render()
      assert.is_truthy(logged("IsSellItemValid"))
      assert.is_truthy(logged("ItemLocation.CreateFromBagAndSlot"))
    end)

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
      -- The dock's cancel button renders only the CANCELLED positions (filterMode
      -- "cancelqueue"), never the whole "listed" deck -- so the reach check below needs the
      -- lot's OWN item to have bag stock, not Thunderfury's (which this deck never draws).
      -- Local to this test, and commodity-only, so it never touches classifyBagItem's
      -- IsSellItemValid branch itself (that would double-count with the confirming click's own
      -- post-cancel refresh below, which is free to rescan the whole bag -- see the comment on
      -- CancelAuction's own logged() check).
      _G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
      _G.C_Container.GetContainerItemInfo = function(bag, slot)
        return (bag == 0 and slot == 1) and { itemID = 23427, stackCount = 50, itemName = "Sanguithorn Tea" } or nil
      end
      _G.C_Container.GetContainerItemLink = function() return nil end
      -- Covers the 50 units now in bags too, at the lot's own 10000cp/unit cost, so coverage
      -- stays COMPLETE and the repost advice this test's cancelEntries depend on is unaffected.
      assert(GC.Acquisitions.RecordManual({ itemID = 23427, positionKey = "commodity:23427",
        itemName = "Sanguithorn Tea", quantity = 50, total = 500000, acquiredAt = 950,
        character = "Owner-Dentarg", region = "eu" }))
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose()
      local button = container.cancelButton
      log = {}
      button.scripts.OnClick(button) -- arm through ROW.armLot: no protected call
      assertNoProtectedCall()
      -- Reach: the arming click did render (ROW.armLot -> renderRows), which is what built the
      -- ItemLocation; the confirming click below must not need to build one of its own.
      assert.is_truthy(logged("ItemLocation.CreateFromBagAndSlot"))
      armedLotRow().repostReady = true
      log = {}
      button.scripts.OnClick(button) -- confirm
      assertCleanCall("CancelAuction")
      assert.is_nil(logged("IsSellItemValid"))
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

    local books, money, cancels, confirms, saved, realItemLots

    local function loadSniper()
      books, money, cancels, confirms = {}, 10000000000, 0, 0
      log = {}
      _G.time = function() return 100000 end
      _G.GetTime = function() return 100 end
      _G.GetMoney = function() return money end
      -- Logged: Blizzard's money formatter is the Sniper's named taint risk (3b ledger), so a
      -- click that formats money ahead of its protected call must fail assertCleanCall.
      _G.GetCoinTextureString = function(value)
        record("GetCoinTextureString")
        return tostring(value)
      end
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
      saved = {}
      GC.Ledger.Init(saved)
      GC.Acquisitions.Init(saved)
      helper.loadModule("UI/SniperFrame.lua", GC)
      -- The real driver's lot reader, kept for the specs that walk a search's own rows.
      realItemLots = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver").itemLots
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
        isReady = function() return true end,
        lastSearchKey = {},
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
        -- Logged: WoW: Forever refuses a restricted call (StartCommoditiesPurchase, PlaceBid) from a
        -- click whose own button was disabled before it (beta 2026-09-28: the Deals Buy was
        -- blocked, the same plan run from another button bought) -- so a Buy click that disables
        -- its button ahead of its protected call must fail assertCleanCall.
        Disable = function() record("dialog.primaryBtn:Disable"); d.enabled = false end,
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


    -- WoW: Forever rows (plan 3c): the ceiling a Check is held to, as GC.ForeverDeals.CeilingFor
    -- hands it out, and a board row as GC.ForeverDeals.Build makes one. The real module is
    -- loaded so the buy limits are its own (GC.ForeverDeals.BuyLimits); only the fold-backed
    -- CeilingFor/Drop are stood in for.
    local FOREVER_BOOK = { { unitPrice = 8, quantity = 5 }, { unitPrice = 9, quantity = 10 },
      { unitPrice = 12, quantity = 40 }, { unitPrice = 13, quantity = 100 } }

    local function foreverCeiling(GC, itemID, ceilingUnit, exitUnit, kind)
      helper.loadModule("Core/ForeverDeals.lua", GC)
      -- Both logged: a Forever decision re-run inside a Buy click, ahead of its protected call,
      -- must fail assertCleanCall rather than pass unseen.
      local buyLimits = GC.ForeverDeals.BuyLimits
      GC.ForeverDeals.BuyLimits = function(...)
        record("ForeverDeals.BuyLimits")
        return buyLimits(...)
      end
      GC.ForeverDeals.CeilingFor = function(id)
        record("ForeverDeals.CeilingFor")
        if id ~= itemID then return nil end
        return { ceilingUnit = ceilingUnit, kind = kind or "vendor", exitUnit = exitUnit, minimumProfit = 20 }
      end
      GC.ForeverDeals.Drop = function(id) GC._dropped = id end
    end

    local function foreverDeal(itemID, isCommodity)
      return { itemID = itemID, isCommodity = isCommodity, forever = "vendor", ceiling = 12, refUnit = 13,
        unitPrice = 8, qty = 55, capTotal = 610, profit = 105, estProfit = 105, stale = true }
    end

    -- The check panel's own words (drawVerdict): the tone word, the figure's caption and the
    -- sentence under it, recorded on a buy window that has those slots.
    local function panelDialog(row, deal)
      local d = fakeDialog(row, deal)
      d.verdictLabel, d.verdictAmount, d.verdictAmountNote = recorder(), recorder(), recorder()
      return d
    end

    -- None of the retail answers may speak for a Forever row: they are about a market engine's
    -- resale estimate or a region reference, and a Forever row has neither.
    local function assertNoRetailWords(d)
      for _, text in ipairs({ d.verdictLabel.text, d.verdictAmountNote.text, d.verdictHead.text }) do
        assert.is_nil(text:find("worst case", 1, true), text)
        assert.is_nil(text:find("selling all", 1, true), text)
        assert.is_nil(text:find("Your call", 1, true), text)
        assert.is_nil(text:find("region", 1, true), text)
        assert.is_nil(text:find("if it sells", 1, true), text)
      end
    end

    after_each(function()
      _G.time, _G.GetTime, _G.GetMoney, _G.GetCoinTextureString = os.time, nil, nil, nil
      _G.C_Timer, _G.SOUNDKIT, _G.PlaySound, _G.ITEM_QUALITY_COLORS, _G.Item = nil, nil, nil, nil, nil
      _G.C_AuctionHouse, _G.GoldCap_AppRuns, _G.CreateFrame = nil, nil, nil
    end)

    it("a Forever row's Check is its ceiling's; without one the market engine answers as before", function()
      local GC = loadSniper()
      local evaluate = getUpvalue(GC.Sniper.OnCommoditySearchResults, "evaluateLiveCommodityDeal")
      books[42] = FOREVER_BOOK
      local retail = evaluate(42, FOREVER_BOOK)
      assert.equal("AVOID", retail.decision.status)
      assert.is_nil(retail.decision.ceiling)
      foreverCeiling(GC, 42, 12, 13)
      local live = evaluate(42, FOREVER_BOOK)
      assert.equal("SAFE", live.decision.status)
      assert.equal(55, live.decision.quantity)
      assert.equal(12, live.decision.ceiling)
      assert.equal(105, live.decision.stressProfit)
    end)

    it("Start (StartCommoditiesPurchase), on a Forever row armed by its ceiling", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      local live = capLive(GC, 42, FOREVER_BOOK)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseToken = 1 }
      local d = armOnDialog(GC, row, deal, live.decision, FOREVER_BOOK)
      -- The quantity row offers what the ceiling allows, not the whole book's 155.
      assert.equal("of 55", d.qtyOfLabel.text)
      local click = clickHandler(GC)
      log = {}
      click()
      assertCleanCall("StartCommoditiesPurchase")
    end)

    it("Confirm (ConfirmCommoditiesPurchase), once the quote holds against the ceiling plan", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      local live = capLive(GC, 42, FOREVER_BOOK)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseToken = 1 }
      local d = armOnDialog(GC, row, deal, live.decision, FOREVER_BOOK)
      local click = clickHandler(GC)
      click() -- Start
      GC.Sniper.OnCommodityPriceUpdated(11, 610) -- the server's quote: what those 55 units cost on the book
      assert.equal("confirm", row.purchaseStage)
      assert.is_true(d.enabled)
      log = {}
      click()
      assertCleanCall("ConfirmCommoditiesPurchase")
    end)

    it("cancels a quote dearer than the ceiling plan, and never offers Confirm on it", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      local live = capLive(GC, 42, FOREVER_BOOK)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseToken = 1 }
      armOnDialog(GC, row, deal, live.decision, FOREVER_BOOK)
      clickHandler(GC)() -- Start
      local before = cancels
      GC.Sniper.OnCommodityPriceUpdated(12, 660) -- 55 units quoted at 660: dearer than the 610 on the book
      assert.is_true(cancels > before)
      assert.are_not.equal("confirm", row.purchaseStage)
    end)

    it("PlaceBid, on a Forever lot under the vendor price", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      local decision = GC.SniperDecision.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
        exitUnit = 100, lots = { { auctionID = 9, buyout = 60, quantity = 1, itemLevel = 18 } },
        minimumProfit = 20 })
      local deal = foreverDeal(42, false)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      assert.equal("ready", row.purchaseStage)
      assert.is_true(d.enabled)
      local said = false
      for _, text in ipairs(d.written) do
        if text:find("under the vendor price", 1, true) then said = true end
      end
      assert.is_true(said)
      local click = clickHandler(GC)
      log = {}
      click()
      assertCleanCall("PlaceBid")
    end)

    it("the check panel says a Below vendor commodity in its own words", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      local live = capLive(GC, 42, FOREVER_BOOK)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseToken = 1 }
      local d = panelDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      armReadyFn(GC)(row, deal, live.decision, FOREVER_BOOK)
      assert.equal("Below vendor", d.verdictLabel.text)
      assert.equal("+" .. GC.Util.FormatMoney(105), d.verdictAmount.text)
      assert.equal(("sure profit: a vendor pays %s each"):format(GC.Util.FormatMoney(13)), d.verdictAmountNote.text)
      assert.equal("Checked against the live auction house a moment ago.", d.verdictHead.text)
      assertNoRetailWords(d)
    end)

    it("the check panel says a Below vendor lot in its own words, not \"Your call\"", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      local decision = GC.SniperDecision.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
        exitUnit = 100, lots = { { auctionID = 9, buyout = 60, quantity = 1, itemLevel = 18 } },
        minimumProfit = 20 })
      local deal = foreverDeal(42, false)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = panelDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      assert.equal("Below vendor", d.verdictLabel.text)
      assert.equal("+" .. GC.Util.FormatMoney(40), d.verdictAmount.text)
      assert.equal(("sure profit: a vendor pays %s each"):format(GC.Util.FormatMoney(100)), d.verdictAmountNote.text)
      assertNoRetailWords(d)
    end)

    -- Final review m6: a Forever Check refused on the minimum still shows what the buy makes,
    -- but dim and without the "sure profit" caption -- green "+15c, sure profit" under a red
    -- REFUSED read as an endorsement.
    it("the check panel shows a refused Forever figure dim, without the sure-profit caption", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 8, 11) -- 5 units at 8c under a vendor's 11c: 15c, under the 20c minimum
      local live = capLive(GC, 42, FOREVER_BOOK)
      assert.same({ "profit_below_minimum" }, live.decision.reasons)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = panelDialog(row, deal)
      function d.verdictAmount:SetTextColor(r, g, b) self.color = { r, g, b } end
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, live)
      assert.equal("+" .. GC.Util.FormatMoney(15), d.verdictAmount.text)
      assert.same(GC.Theme.color.fgDim, d.verdictAmount.color)
      assert.equal("", d.verdictAmountNote.text)
      assert.is_nil(d.verdictLabel.text:find("Below vendor", 1, true))
    end)

    it("the check panel says an Under market commodity is a resale at the scan's AH value, speed unknown", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 20, "market")
      local live = capLive(GC, 42, FOREVER_BOOK)
      assert.equal("SAFE", live.decision.status)
      local deal = foreverDeal(42, true)
      deal.forever, deal.refUnit = "market", 20
      local row = { deal = deal, purchaseToken = 1 }
      local d = panelDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      armReadyFn(GC)(row, deal, live.decision, FOREVER_BOOK)
      assert.equal("Under market", d.verdictLabel.text)
      -- 55 units resold at 20c: 1,100c, less the 55c cut, the 0c deposit and the 610c paid.
      assert.equal("+" .. GC.Util.FormatMoney(435), d.verdictAmount.text)
      assert.equal(("resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown")
        :format(GC.Util.FormatMoney(20)), d.verdictAmountNote.text)
      assertNoRetailWords(d)
    end)

    -- How a Forever buy is recorded (purchaseFacts): in the evidence-free shape a YOUR PRICE buy
    -- has (`cap = true`: no engine decision, stress exit or region reference to keep), at what it
    -- cost, with the profit its own ceiling decision worked out -- the ledger's kind "buy" row,
    -- the acquisition batch the Sell tab's cost basis comes from, and the session's estimate.
    local function assertForeverRecord(GC, quantity, total, profit)
      local entry = saved.ledger[#saved.ledger]
      assert.is_table(entry)
      assert.equal("buy", entry.kind)
      assert.equal("goldcap_sniper", entry.source)
      assert.is_true(entry.cap)
      assert.is_nil(entry.decisionVersion)
      assert.equal(42, entry.itemID)
      assert.equal(quantity, entry.qty)
      assert.equal(total, entry.total)
      -- The cost basis the Sell tab reads: what was paid for how many, and no resale target
      -- (no stress exit was measured).
      local batch = saved.acquisitions[#saved.acquisitions]
      assert.equal("goldcap", batch.source)
      assert.equal(quantity, batch.originalQty)
      assert.equal(total, batch.originalTotal)
      assert.is_nil(batch.targetUnit)
      assert.equal(1, GC.Sniper.session.buys)
      assert.equal(total, GC.Sniper.session.spent)
      assert.equal(profit, GC.Sniper.session.estProfit)
    end

    it("records a Forever commodity buy at its quote, with the ceiling decision's profit", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      local live = capLive(GC, 42, FOREVER_BOOK)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseToken = 1 }
      armOnDialog(GC, row, deal, live.decision, FOREVER_BOOK)
      local click = clickHandler(GC)
      click() -- Start
      GC.Sniper.OnCommodityPriceUpdated(11, 610)
      click() -- Confirm
      assert.equal(1, confirms)
      local facts = getUpvalue(GC.Sniper.OnPurchaseCompleted, "purchaseFacts")(deal, row.quoteSnapshot)
      assert.same({ itemID = 42, quantity = 55, total = 610, unitDisplay = 11, cap = true,
        expectedProfit = 105 }, facts)
      GC.Sniper.OnCommodityPurchaseSucceeded()
      assertForeverRecord(GC, 55, 610, 105)
      assert.equal(42, GC._dropped) -- and the lead leaves the board
    end)

    it("records a Forever lot at its buyout, with what the vendor pays over it", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      local decision = GC.SniperDecision.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
        exitUnit = 100, lots = { { auctionID = 9, buyout = 60, quantity = 1, itemLevel = 18 } },
        minimumProfit = 20 })
      local deal = foreverDeal(42, false)
      local row = { deal = deal, purchaseStage = "requerying" }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", fakeDialog(row, deal))
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      clickHandler(GC)() -- PlaceBid
      local facts = getUpvalue(GC.Sniper.OnPurchaseCompleted, "purchaseFacts")(deal,
        { itemID = 42, quantity = 1, total = 60, decision = decision })
      -- One at 60c, which a vendor takes at 100c: 40c.
      assert.same({ itemID = 42, quantity = 1, total = 60, unitDisplay = 60, cap = true,
        expectedProfit = 40 }, facts)
      GC.Sniper.OnPurchaseCompleted(9)
      assertForeverRecord(GC, 1, 60, 40)
    end)

    -- At the PlaceBid path itself: from the rows the item search answered, through the real
    -- driver.itemLots and the real Check (evaluateLiveItemDeal) and arm, to the click. An item
    -- search row groups identical one-item auctions and PlaceBid pays its buyoutAmount for one
    -- of them (addon 0.15.2) -- in WoW: Forever exactly as on retail.
    local function checkRows(GC, rows)
      local bids = {}
      _G.C_AuctionHouse.PlaceBid = function(auctionID, amount)
        record("PlaceBid")
        bids[#bids + 1] = { auctionID, amount }
      end
      _G.C_AuctionHouse.GetNumItemSearchResults = function() return #rows end
      _G.C_AuctionHouse.GetItemSearchResultInfo = function(_, i) return rows[i] end
      getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver").itemLots = realItemLots
      local live = getUpvalue(GC.Sniper.OnItemSearchResults, "evaluateLiveItemDeal")(42)
      return live, bids
    end

    local function armAndClick(GC, deal, live)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, live)
      -- Armed or not, as the click found it: the client fires no OnClick on a disabled Button.
      local armed = d.enabled
      log = {}
      if armed then clickHandler(GC)() end
      return armed, d
    end

    it("PlaceBid on a Forever row buys one item of a row listed many times, at its buyoutAmount", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      local live, bids = checkRows(GC, { { auctionID = 5, buyoutAmount = 19, quantity = 11 },
        { auctionID = 6, buyoutAmount = 70, quantity = 1 } })
      assert.equal(1, live.decision.quantity); assert.equal(19, live.decision.entryTotal)
      assert.is_true(armAndClick(GC, foreverDeal(42, false), live))
      assertCleanCall("PlaceBid")
      assert.same({ { 5, 19 } }, bids)
    end)

    it("PlaceBid never fires for a Forever row whose one item costs more than the vendor price", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      -- 240c for one item, listed three times: under the ceiling only if divided by the count.
      local live, bids = checkRows(GC, { { auctionID = 5, buyoutAmount = 240, quantity = 3 } })
      assert.same({ "price_rose" }, live.decision.reasons)
      local _, d = armAndClick(GC, foreverDeal(42, false), live)
      assert.are_not.equal("Buy", d.label)
      log = {}
      clickHandler(GC)()
      assertNoProtectedCall()
      assert.same({}, bids)
    end)

    -- Retail, as released in 0.15.2: a YOUR PRICE cap of 100g never fires on 240g items, however
    -- many identical ones are listed, and one under it is bought one at a time.
    it("retail: a cap never fires on one item priced over it, listed several times", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live, bids = checkRows(GC, { { auctionID = 9, buyoutAmount = 2400000, quantity = 3, itemKey = { itemLevel = 615 } } })
      assert.is_falsy(live and live.decision and live.decision.cap)
      assert.same({}, bids)
    end)

    it("retail: a lot at the player's own price is bid on as one item at its buyoutAmount", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live, bids = checkRows(GC, { { auctionID = 9, buyoutAmount = 900000, quantity = 3, itemKey = { itemLevel = 615 } } })
      assert.is_true(live.decision.cap)
      assert.equal(1, live.decision.quantity); assert.equal(900000, live.decision.entryTotal)
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 900000, qty = 1,
        auctionID = 9, stale = true }
      assert.is_true(armAndClick(GC, deal, live))
      assertCleanCall("PlaceBid")
      assert.same({ { 9, 900000 } }, bids)
    end)

    -- The Forever buy limits (plan 3c, Decision 5: GC.ForeverDeals.BuyLimits), where they bite.
    -- Every other spec here runs with a wallet no budget ever reaches. A refused lot is held by
    -- its disabled Buy button -- the client fires no OnClick on a disabled Button -- exactly as a
    -- YOUR PRICE lot over its limit is, so `d.enabled` is the gate these pin.
    local function applyLot(GC, lot)
      local decision = GC.SniperDecision.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
        exitUnit = 100, lots = { lot }, minimumProfit = 20 })
      local deal = foreverDeal(42, false)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      return d
    end

    local function said(d, text)
      for _, line in ipairs(d.written) do
        if line:find(text, 1, true) then return true end
      end
      return false
    end

    it("holds a Forever lot to the Forever per-buy share, not to the whole wallet", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      money = 100 -- the vendor share at the default setting: half, 50c
      local d = applyLot(GC, { auctionID = 9, buyout = 60, quantity = 1, itemLevel = 18 })
      assert.is_false(d.enabled)
      assert.is_true(said(d, "Costs more than your per-buy wallet limit allows."))

      d = applyLot(GC, { auctionID = 9, buyout = 50, quantity = 1, itemLevel = 18 })
      assert.is_true(d.enabled)
    end)

    -- The arm's own gate, for when a stacked lot is let through again (final review I4 keeps
    -- EvaluateCeilingLot to single lots until then): a decision naming a stack is handed in
    -- directly, as a ceiling decision would name one.
    it("holds a Forever lot to Max units per buy", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 99, 100)
      GC.db.settings.sniper.maxQuantity = 5
      local function stackDecision(quantity, buyout)
        local lot = { auctionID = 9, buyout = buyout, quantity = quantity, itemLevel = 18 }
        return { version = GC.SniperDecision.VERSION, status = "WATCH", buyable = false, reasons = {},
          candidate = lot, quantity = quantity, entryTotal = buyout, entryUnitDisplay = math.floor(buyout / quantity),
          unit = math.floor(buyout / quantity), ceiling = 99, forever = "vendor", exitUnit = 100,
          stressProfit = 100 * quantity - buyout, estProfit = 100 * quantity - buyout, reference = 100 }
      end
      local function apply(decision)
        local deal = foreverDeal(42, false)
        local row = { deal = deal, purchaseStage = "requerying" }
        local d = fakeDialog(row, deal)
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
        local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
        getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
        return d
      end
      local d = apply(stackDecision(6, 360))
      assert.is_false(d.enabled)
      assert.is_true(said(d, "This lot holds more units than your Max units per buy."))

      d = apply(stackDecision(5, 300))
      assert.is_true(d.enabled)
    end)

    it("plans a Below vendor Check inside half the wallet while the share is at its default", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      money = 200 -- half: 100c buys 5 at 8c and 6 at 9c; the retail 5% (10c) buys one, under 20c
      local live = capLive(GC, 42, FOREVER_BOOK)
      assert.equal("SAFE", live.decision.status)
      assert.equal(11, live.decision.quantity)
      assert.equal(94, live.decision.entryTotal)
      assert.equal(49, live.decision.stressProfit)
    end)

    it("plans a Below vendor Check inside the player's own share once they changed it", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      GC.db.settings.sniper.maxCapitalShare = 0.10
      money = 1000 -- 10%: 100c, not half the wallet (which would buy all 55)
      local live = capLive(GC, 42, FOREVER_BOOK)
      assert.equal("SAFE", live.decision.status)
      assert.equal(11, live.decision.quantity)
      assert.equal(94, live.decision.entryTotal)
    end)

    it("walks an item's lots for a Forever ceiling only when the item has one", function()
      local GC = loadSniper()
      local walks = 0
      local driver = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver")
      driver.itemLots = function() walks = walks + 1; return {} end
      local evaluate = getUpvalue(GC.Sniper.OnItemSearchResults, "evaluateLiveItemDeal")
      evaluate(42) -- retail: no ceiling, and no realm value to walk them for either
      assert.equal(0, walks)
      foreverCeiling(GC, 42, 99, 100)
      evaluate(42)
      assert.equal(1, walks)
    end)

    it("takes a Forever row down when its Check finds the listing gone", function()
      local GC = loadSniper()
      foreverCeiling(GC, 42, 12, 13)
      local deal = foreverDeal(42, true)
      local row = { deal = deal, purchaseStage = "requerying" }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", fakeDialog(row, deal))
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, nil)
      assert.equal(42, GC._dropped)
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

    it("a Buy click with the quantity box focused commits the quantity and buys nothing", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 200 } })
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseToken = 1 }
      local d = armOnDialog(GC, row, deal, live.decision, { { unitPrice = 900000, quantity = 200 } })
      local focused = true
      d.qtyBox.editBox.HasFocus = function() return focused end
      d.qtyBox.editBox.ClearFocus = function() focused = false; log[#log + 1] = "EditBox:ClearFocus" end
      local click = clickHandler(GC)
      log = {}
      click()
      assertNoProtectedCall()
      assert.equal("EditBox:ClearFocus", log[1])
      assert.equal("ready", row.purchaseStage)
      log = {}
      click() -- the box no longer has focus: this is the buy
      assertCleanCall("StartCommoditiesPurchase")
    end)
  end)
end)
