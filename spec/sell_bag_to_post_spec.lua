local helper = require("spec.spec_helper")

-- End to end through the real modules: bags -> positions -> rendered rows -> a
-- post plan. The unit specs each prove one seam; this proves they are wired to
-- each other, which is the class of bug that survives a green unit suite and
-- then greets the player as an empty tab.
describe("Sell tab, bags to Post", function()
  local GC, root, rows, render

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

  -- Slot 1: 200 Eternium Ore, a commodity, freely sellable.
  -- Slot 2: 46 more of the same, so the aggregate has to add up across stacks.
  -- Slot 3: soulbound, which the auction house refuses.
  -- Slot 4: vendor-worthless, likewise.
  local BAGS = {
    [0] = {
      { itemID = 23427, stackCount = 200, itemName = "Eternium Ore" },
      { itemID = 23427, stackCount = 46, itemName = "Eternium Ore" },
      { itemID = 6948, stackCount = 1, itemName = "Hearthstone", isBound = true },
      { itemID = 1, stackCount = 1, itemName = "Junk", hasNoValue = true },
    },
  }

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
      GetItemKeyInfo = function(key) return { isCommodity = key.itemID == 23427 } end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Eternium Ore" end }

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
    helper.loadModule("UI/SellViewModel.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    GC.Acquisitions.Init({})

    root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    render = upvalue(GC.Sell.Attach, "renderRows")
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil
  end)

  local function compose()
    upvalue(GC.Sell.SellableCount, "composePositions")()
    render()
    rows = upvalue(render, "rows")
  end

  local function positionRow()
    for _, row in ipairs(rows) do
      if row.shown and row.kind == "position" then return row end
    end
  end

  it("lists bag stock GoldCap never bought, and offers to post it", function()
    compose()
    local row = positionRow()
    assert.is_not_nil(row)
    assert.equal("commodity:23427", row.position.positionKey)
    -- 200 + 46, added across both stacks.
    assert.equal(246, row.position.bagQty)
    assert.match("×246 in bags", row.cells.item.text)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.shown)
  end)

  it("counts only what the auction house would accept", function()
    compose()
    local shown = 0
    for _, r in ipairs(rows) do if r.shown and r.kind == "position" then shown = shown + 1 end end
    assert.equal(1, shown) -- the soulbound and the worthless are not positions
    assert.equal(1, GC.Sell.SellableCount())
  end)

  it("reports the cost as unknown rather than inventing one", function()
    compose()
    local row = positionRow()
    assert.equal("—", row.cells.cost.text)
    assert.equal("Unknown", row.cells.profit.text)
  end)

  it("advises a price once a live quote lands, and builds a post plan for it", function()
    local quotes = upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    -- The honest cheap side of the real EU book, after the ingest fix.
    GC.QuoteCache.Set(quotes, 23427, 184719, 1000)
    compose()
    local row = positionRow()
    assert.equal(184719, row.position.freshMarketUnit)
    assert.match("Post", row.cells.status.text)

    local plan, reason = GC.SellPositions.BuildPostPlan(row.position,
      { itemID = 23427, exactQty = 246, positionKey = "commodity:23427" },
      { unit = 184719, fresh = true })
    assert.is_nil(reason)
    assert.equal(246, plan.quantity)
    assert.is_false(plan.costKnown)
    assert.equal(184719, plan.unitPrice)
  end)

  it("prices only what there is something to do with", function()
    local ready = upvalue(GC.Sell.OnOwnedAuctions, "onOwnedAuctionsReady")
    local walk = upvalue(upvalue(ready, "beginQuoteWalk"), "uniqueQuoteItemIDs")
    compose()
    assert.same({ 23427 }, walk())
  end)
end)
