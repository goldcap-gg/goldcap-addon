local helper = require("spec.spec_helper")

-- End to end through the real modules, the same seam spec/sell_post_queue_control_spec.lua
-- proves for posting: owned lots -> positions -> GC.CancelQueue.Build -> the Cancel control ->
-- onRepostClick's own arm/confirm/pin machinery -> C_AuctionHouse.CancelAuction. The control
-- must never grow a second cancel implementation, so the assertions below reach the protected
-- call ONLY through the same handler a row's own Repost button uses.
describe("Sell tab, the cancel queue control", function()
  local GC, root, render, container, cancelCalls

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
    function v:SetAutoFocus() end function v:SetScrollChild() end
    function v:CreateTexture() return region("Texture", self) end
    function v:SetAllPoints() end function v:SetColorTexture() end
    function v:SetTexture() end function v:SetTexCoord() end
    function v:SetTextureSliceMargins() end function v:SetVertexColor() end
    function v:SetFrameStrata() end function v:SetFrameLevel() end
    function v:GetFrameLevel() return 0 end function v:EnableMouse() end
    return v
  end

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local n, val = debug.getupvalue(fn, i)
      if not n then break end
      if n == wanted then return val end
    end
    error("missing upvalue " .. wanted)
  end

  -- One live lot: 400 Sanguithorn Tea listed at 2g73s against a market that has moved to
  -- 1g98s -- the undercut-leftover shape the queue exists for. The paid basis (1g/unit,
  -- recorded below) sits far under the relist price, so RepostAdvice says "repost".
  local OWNED = { { auctionID = 77, itemKey = { itemID = 23427 }, quantity = 400,
    unitPrice = 27300, isCommodity = true } }

  before_each(function()
    cancelCalls = 0
    _G.time = function() return 1000 end
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    _G.C_Container = {
      GetContainerNumSlots = function() return 0 end,
      GetContainerItemInfo = function() return nil end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      GetOwnedAuctions = function() return OWNED end,
      QueryOwnedAuctions = function() end,
      CancelAuction = function() cancelCalls = cancelCalls + 1 end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Sanguithorn Tea" end }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }

    GC = {
      Sell = {},
      Theme = {
        color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
          zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
          gold = { 1, 1, 0 }, panel = { 0, 0, 0 } },
        Label = function(p) return region("FontString", p) end,
        Num = function(p) return region("FontString", p) end,
        Button = function(p) return region("Button", p) end,
      },
      Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
        GetEntries = function() return {} end },
      Data = { GetItemValue = function() return { sold = 7447 } end },
    }
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
    -- The cost basis that makes coverage COMPLETE and the repost advice computable: 400 units
    -- at 1g each, well under the 1g98s relist price.
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
    container:Show()
    GC.Sell.OnOwnedAuctions() -- what stamps the module-local ownedLots from GetOwnedAuctions
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

  it("counts the queue on the button and holds an honest disabled state when it is empty", function()
    compose() -- no quote at all: the lot cannot be judged, nothing enters the queue
    local button = container.cancelButton
    assert.is_false(button.enabled)
    assert.matches("NOTHING", button.label)
    assert.equal("ghost", button.variant)

    GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
    compose()
    assert.equal("CANCEL 1", button.label)
    assert.is_true(button.enabled)
    assert.equal("danger", button.variant)
  end)

  it("surfaces the held-back count in plain words, not the raw skip token", function()
    compose() -- no fresh quote: the position is held back with reason no_fresh_price
    local heldBack = container.cancelHeldBack
    assert.is_true(heldBack.shown)
    assert.matches("1", heldBack.text, 1, true)
    local hit = container.cancelHeldBackHit
    assert.is_function(hit.scripts.OnEnter)
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    hit.scripts.OnEnter(hit)
    local joined = table.concat(tooltipLines, " ")
    assert.matches("Sanguithorn Tea", joined, 1, true)
    assert.is_nil(joined:find("no_fresh_price", 1, true))
    _G.GameTooltip = nil
  end)

  it("arms the head lot through onRepostClick on the first click -- destroying nothing", function()
    GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
    compose()
    local button = container.cancelButton
    button.scripts.OnClick(button)

    -- The list is now the cancel queue: head position at row 1, force-expanded so the head's
    -- own lot row (the thing onRepostClick pins to) is rendered further down.
    local rows = upvalue(render, "rows")
    assert.equal("position", rows[1].kind)
    assert.equal("commodity:23427", rows[1].position.positionKey)
    local lotRow = armedLotRow()
    assert.is_table(lotRow)
    assert.equal("armed", lotRow.repostStage)
    assert.equal("Cancel lot?", lotRow.action.label)
    assert.equal(0, cancelCalls)
    -- The control mirrors the arm; without C_Timer the arm delay never elapses headless, so it
    -- shows the confirm label while staying disabled.
    assert.equal("CANCEL LOT?", button.label)
    assert.is_false(button.enabled)
  end)

  it("routes the confirm click through the same pin and actually cancels once", function()
    GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
    compose()
    local button = container.cancelButton
    button.scripts.OnClick(button)
    local lotRow = armedLotRow()
    lotRow.repostReady = true -- what the REPOST_ARM_SECONDS timer does in the client

    button.scripts.OnClick(button)

    assert.equal(1, cancelCalls)
    assert.equal("cancelling", lotRow.repostStage)
    assert.matches("CANCELLING", button.label)
    assert.is_false(button.enabled)
  end)
end)
