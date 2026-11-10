local helper = require("spec.spec_helper")
local ThemeShape = require("spec.support.theme_shape")

-- End to end through the real modules: bags -> positions -> rendered rows -> a
-- post plan. The unit specs each prove one seam; this proves they are wired to
-- each other, which is the class of bug that survives a green unit suite and
-- then greets the player as an empty tab.
describe("Sell pricing walk order", function()
  local GC, root, render

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

  -- (unused) Eternium Ore, a commodity, freely sellable.
  -- Slot 2: 46 more of the same, so the aggregate has to add up across stacks.
  -- Slot 3: soulbound, which the auction house refuses.
  -- Slot 4: no link, so its exact auction identity cannot be derived and classify refuses it.
  --         (It is also vendor-worthless, which is NOT why it is out -- see the regression
  --         test below and Core/BagStock.lua's own note on `hasNoValue`.)
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
        color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = { .72, .71, .69 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
          zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
          gold = { 1, 1, 0 }, panel = { 0, 0, 0 }, panelHi = { 0.102, 0.114, 0.141 } },
        pad = { xs = 4, s = 8, m = 12, l = 16 },
        MEDIA = "",
        Label = function(p) return region("FontString", p) end,
        Num = function(p) return region("FontString", p) end,
        Button = function(p) return region("Button", p) end,
        Card = function(p) local card = region("Frame", p); function card:SetTint() end return card end,
        Plate = function() return nil end, -- no skin plates in this fake
        SlicedTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
        ShapeTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
        Shape = ThemeShape.Shape, SetShape = ThemeShape.SetShape,
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
    helper.loadModule("Core/PostQueue.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
    GC.Sniper = {
      IsAHOpen = function() return true end, IsBusy = function() return false end, CurrentView = function() return "sell" end,
      _TrySendKeysBatchFor = function(_, who)
        GC.Sniper._keysOwner, GC.Sniper._keysAwaiting = who, 100
        return true
      end,
    }
    helper.loadSell(GC)
    GC.Acquisitions.Init({})

    root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    render = GC.SellUI.List.RenderRows
    -- Attach leaves the Sell container hidden (one of several tabs on the real Sniper
    -- window); renderRows now defers a rebuild while it is hidden, so this whole suite --
    -- which reads rendered rows directly -- needs it shown, the way GC.Sell.Show() (the
    -- real tab switch) would leave it.
    GC.SellUI.container:Show()
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil
  end)

  local function compose()
    GC.SellCompose.Positions()
    render()
  end

  local function shownIDs()
    local ids = {}
    for _, r in ipairs(GC.SellUI.rows) do
      if r.shown and r.kind == "position" then ids[#ids + 1] = r.position.itemID end
    end
    return ids
  end

  local sent
  before_each(function()
    BAGS[0] = {}
    for id = 100, 106 do BAGS[0][#BAGS[0] + 1] = { itemID = id, stackCount = 5, itemName = "Item" .. id } end
    _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true } end
    _G.C_AuctionHouse.QueryOwnedAuctions = function() end
    _G.C_AuctionHouse.GetOwnedAuctions = function() return {} end
    GC.db = { sellMarks = {}, commodityByItem = {} }
    GC.SellWalk.Live = function() return true end
    sent = {}
    GC.SellQuotes.driver = {
      isReady = function() return true end, keyInfo = function() return { isCommodity = true } end,
      send = function(itemID) sent[#sent + 1] = itemID end,
      item = function() return nil end, itemLevels = function() return nil end,
      commodity = function() return nil end, commodityLevels = function() return nil end,
    }
  end)

  local function answerAll()
    for _ = 1, 20 do
      if GC.SellState.refresh.phase ~= "waiting_result" then return end
      GC.Sell.OnCommoditySearchResults(sent[#sent])
    end
  end

  it("asks the due rows top to bottom as the list draws them, SELLING above NOT SELLING", function()
    -- Marked rows draw above unmarked ones whatever their order in the bags.
    GC.db.sellMarks["commodity:105"], GC.db.sellMarks["commodity:102"] = true, true
    compose()
    local drawn = shownIDs()
    assert.same({ 102, 105 }, { drawn[1], drawn[2] }) -- the SELLING section first
    GC.Sell.Refresh(true); GC.Sell.OnOwnedAuctions()
    answerAll()
    assert.same(drawn, sent)
  end)

  it("walks only the due rows, in drawn order, and leaves a fresh quote alone", function()
    GC.db.sellMarks["commodity:105"] = true
    for _, id in ipairs({ 100, 104 }) do
      GC.SellState.quotes[id] = { unit = 900, at = 1000, levels = { { unit = 900, qty = 3 } } }
    end
    compose()
    local expected = {}
    for _, id in ipairs(shownIDs()) do
      if id ~= 100 and id ~= 104 then expected[#expected + 1] = id end
    end
    GC.Sell.Refresh(true); GC.Sell.OnOwnedAuctions()
    answerAll()
    assert.same(expected, sent)
    assert.equal(5, #sent)
  end)

  it("asks a row the player clicked before the rest of the walk", function()
    compose()
    GC.SellState.refresh.priority[1] = 106
    GC.Sell.Refresh(true); GC.Sell.OnOwnedAuctions()
    answerAll()
    assert.equal(106, sent[1])
    assert.equal(100, sent[2])
  end)
end)
