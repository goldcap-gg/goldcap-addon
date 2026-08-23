local helper = require("spec.spec_helper")

-- End to end through the real modules, the same shape spec/sell_bag_to_post_spec.lua already
-- proves for a single row's own Post button: bags -> positions -> GC.PostQueue.Build -> the
-- toolbar control -> onPostClick. This is the seam that proves the queue and the button beside
-- it are wired to each other, not just that each one works alone.
describe("Sell tab, the posting queue control", function()
  local GC, root, render, container

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint() end
    function v:ClearAllPoints() end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
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

  -- Two commodities in the bags:
  --   23427 Eternium Ore, x246 -- priced, the queue's only postable entry.
  --   99001 Widget, x5 -- in the bags but never quoted, so PostQueue.Build holds it back with
  --   reason "no_fresh_price". This is what exercises the held-back surface.
  local BAGS = {
    [0] = {
      { itemID = 23427, stackCount = 200, itemName = "Eternium Ore" },
      { itemID = 23427, stackCount = 46, itemName = "Eternium Ore" },
      { itemID = 99001, stackCount = 5, itemName = "Widget" },
    },
  }

  local ITEM_NAMES = { [23427] = "Eternium Ore", [99001] = "Widget" }

  before_each(function()
    _G.time = function() return 1000 end
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
      PostCommodity = function() return false end,
    }
    _G.C_Item = { GetItemNameByID = function(id) return ITEM_NAMES[id] end }
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

  it("labels the control with the head item and price, and counts the queue on the button itself", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    local button = container.queueButton
    local label = container.queueLabel
    assert.equal("Post 1", button.label)
    assert.is_true(button.enabled)
    assert.matches("Eternium Ore", label.text, 1, true)
  end)

  it("disables with an honest word when nothing is postable", function()
    compose() -- no quote at all: BOTH bag items are held back, nothing enters the queue
    local button = container.queueButton
    assert.is_false(button.enabled)
    assert.matches("[Nn]othing", button.label)
  end)

  it("surfaces the held-back count in plain words, not the raw skip token", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    assert.equal(1, #upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "queueSkipped"))
    local heldBack = container.queueHeldBack
    assert.is_true(heldBack.shown)
    assert.matches("1", heldBack.text, 1, true)
    local hit = container.queueHeldBackHit
    assert.is_function(hit.scripts.OnEnter)
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    hit.scripts.OnEnter(hit)
    local joined = table.concat(tooltipLines, " ")
    assert.matches("Widget", joined, 1, true)
    assert.is_nil(joined:find("no_fresh_price", 1, true))
    _G.GameTooltip = nil
  end)

  it("posts the queue head when clicked, through onPostClick's own pin and validation", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    local button = container.queueButton
    button.scripts.OnClick(button)
    local rows = upvalue(render, "rows")
    -- Row 1 is now the queue's head, mid-post: onPostClick's own pin has taken over its label.
    assert.equal("commodity:23427", rows[1].position.positionKey)
    assert.is_false(rows[1].action.enabled)
  end)

  it("reads Confirm on the control and routes the second click to the same row", function()
    _G.C_AuctionHouse.PostCommodity = function() return true end -- needs a second click to confirm
    local confirmCalls = 0
    _G.C_AuctionHouse.ConfirmPostCommodity = function() confirmCalls = confirmCalls + 1 end
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    local button = container.queueButton
    button.scripts.OnClick(button)
    assert.equal("Confirm", button.label)
    assert.is_true(button.enabled)
    button.scripts.OnClick(button)
    assert.equal(1, confirmCalls)
  end)

  it("disables while the head's post is genuinely in flight (posting/confirming)", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    local button = container.queueButton
    button.scripts.OnClick(button) -- PostCommodity returns false above: lands on postStage "posting"
    assert.is_false(button.enabled)
  end)

  it("shows the queue in queue order, head at row 1, as its own filter mode", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    -- Clicking the control is what arms queue mode -- see onQueueClick -- so this drives the
    -- exact same path a player would, rather than reaching in to flip filterMode by hand.
    local button = container.queueButton
    button.scripts.OnClick(button)
    local rows = upvalue(render, "rows")
    assert.equal("position", rows[1].kind)
    assert.equal("commodity:23427", rows[1].position.positionKey)
  end)
end)
