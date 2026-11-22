local helper = require("spec.spec_helper")
local ThemeShape = require("spec.support.theme_shape")

-- What SELL shows of the sale pace on WoW: Forever (plan 2026-11-09, Task 9), through the real Sell
-- services and view: the dock's duration buttons and pace lines, MAX meaning "all", the "24 h" mark
-- on a slow seller's stock line and the pace on its row's tooltip. The harness is
-- spec/forever_sell_pace_wiring_spec.lua's: item 10, a commodity, twenty in the bags, the player's
-- duration 8 h (index 2); the tape says three a day sold over a week.
describe("SELL's pace view on WoW: Forever", function()
  local FOREVER = { interface = 16001 }
  local RETAIL = { interface = 120100 }
  local GC, root, container, posted, timers, sales, BAGS, tooltip, deposits

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
    posted, timers, tooltip, deposits = {}, {}, {}, {}
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
      CalculateCommodityDeposit = function(_, duration) return deposits[duration] end,
      PostCommodity = function(_, duration, quantity, unit)
        posted[#posted + 1] = { duration = duration, quantity = quantity, unit = unit }
        return false
      end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Herb" end }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.GameTooltip = {
      SetOwner = function(self) self.owner = true end, GetOwner = function() return nil end,
      AddLine = function(_, text) tooltip[#tooltip + 1] = text end,
      Show = function() end, Hide = function() end, SetItemByID = function() end,
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
        Plate = function() return nil end, -- no skin plates in this fake
        ShapeTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
        Shape = ThemeShape.Shape, SetShape = ThemeShape.SetShape,
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
    -- GoldCap_Camelot.toc alone loads the Sell pace view, after the Sell view.
    if forever then helper.loadModule("UI/SellPace_Camelot.lua", GC) end
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

  local function owned(lots)
    _G.C_AuctionHouse.GetOwnedAuctions = function() return lots end
    GC.Sell.OnOwnedAuctions()
  end

  local function lot(id) return { auctionID = id, itemKey = { itemID = 10 }, quantity = 1, unitPrice = 12000, isCommodity = true } end

  local function type_(text)
    local box = container.qtyBox
    box.scripts.OnEditFocusGained(box)
    box:SetText(text)
    box.scripts.OnTextChanged(box, true)
    box.scripts.OnEnterPressed(box)
  end

  local function hover()
    tooltip = {}
    local row = herbRow()
    row.scripts.OnEnter(row)
    return table.concat(tooltip, "\n")
  end

  describe("on WoW: Forever", function()
    before_each(function() setup(FOREVER) end)

    it("the panel says how many sell", function()
      ready(12000)
      assert.is_not_nil(GC.SellUI.PostPanel.Forever)
      assert.equal("About 1 sell in 8 h on this auction house.", container.paceLines.text)
      assert.equal("1", container.qtyBox.text)
      assert.is_truthy(container.dockSub.text:find("×20 in bags", 1, true))
      assert.equal("DURATION", container.durationHead.text)
      assert.equal("2 h", container.durationButtons[1].label)
      assert.equal("8 h", container.durationButtons[2].label)
      assert.equal("24 h", container.durationButtons[3].label)
      assert.equal("active", container.durationButtons[2].variant)
      assert.equal("ghost", container.durationButtons[3].variant)
    end)

    it("the duration buttons change the post", function()
      ready(12000)
      container.durationButtons[3].scripts.OnClick(container.durationButtons[3])
      assert.equal(3, GC.SellState.durationOverrides["commodity:10"])
      assert.equal("About 3 sell in 24 h on this auction house.", container.paceLines.text)
      assert.equal("active", container.durationButtons[3].variant)
      assert.equal("ghost", container.durationButtons[2].variant)
      assert.equal(0, #posted) -- a button never posts
      assert.equal(3, GC.SellState.queueEntries[1].postableQty)
      post()
      assert.equal(3, posted[1].duration)
      assert.equal(3, posted[1].quantity)
    end)

    it("a held item says why and how to post more", function()
      owned({ lot(1), lot(2) })
      -- The walk passes a held item over: the player's click on its row brings it to the dock.
      GC.SellState.dockKey = "commodity:10"
      ready(12000)
      assert.equal("Your 2 already up cover about 8 h of sales. Type a number or press MAX to post more.",
        container.paceLines.text)
      container.qtyMax.scripts.OnClick(container.qtyMax)
      assert.equal(GC.SellPositions.ALL, GC.SellState.quantityOverrides["commodity:10"])
      assert.equal("20", container.qtyBox.text)
      assert.equal("active", container.qtyMax.variant)
      post()
      assert.equal(20, posted[1].quantity)
    end)

    it("typing a number posts it, and a number over the stock means all", function()
      ready(12000)
      type_("5")
      assert.equal(5, GC.SellState.quantityOverrides["commodity:10"])
      assert.equal("ghost", container.qtyMax.variant)
      type_("50")
      assert.equal(GC.SellPositions.ALL, GC.SellState.quantityOverrides["commodity:10"])
      assert.equal("active", container.qtyMax.variant)
      type_("5")
      post()
      assert.equal(5, posted[1].quantity)
    end)

    it("says when nobody buys it", function()
      sales.perDay, sales.hours = 0, 168
      ready(12000)
      assert.equal("Nobody bought this here in the last 7 days. Posting 1 to test the price.",
        container.paceLines.text)
      sales.hours = 30
      ready(12000)
      assert.equal("Nobody bought this here in the last day. Posting 1 to test the price.",
        container.paceLines.text)
    end)

    it("marks a slow seller 24 h and says why and what the deposit does", function()
      sales.perDay = 0.5
      deposits[2], deposits[3] = 10, 30
      ready(12000)
      assert.is_truthy(herbRow().itemStock.text:find("24 h", 1, true))
      local shown = container.paceLines.text
      assert.is_truthy(shown:find("24 h: about 0.5 sell a day here.", 1, true))
      assert.is_truthy(shown:find(("Deposit %s instead of %s, returned when it sells."):format(
        GC.SellUI.fmt.cell(30), GC.SellUI.fmt.cell(10)), 1, true))
      assert.equal("active", container.durationButtons[3].variant)
    end)

    it("a slow seller with a returns history says how often it came back", function()
      ready(12000)
      local p = position()
      p.slowDurationIndex, p.slowWhy, p.returnShort, p.returnShortIndex, p.returnRounds = 3, "history", 2, 2, 2
      GC.SellUI.List.RenderRows()
      local shown = container.paceLines.text
      assert.is_truthy(shown:find("24 h: came back unsold 2 times at 8 h.", 1, true))
      assert.is_truthy(shown:find("Came back unsold 2 times since its last sale.", 1, true))
    end)

    it("an ordinary item has no 24 h on its stock line", function()
      ready(12000)
      assert.is_nil(herbRow().itemStock.text:find("24 h", 1, true))
    end)

    it("the row tooltip says the pace and the returns", function()
      ready(12000)
      assert.is_truthy(hover():find("Sells about 3.0 a day here", 1, true))
      local p = position()
      p.pacePerDay, p.paceHours = 0, 168
      assert.is_truthy(hover():find("No sales here in 7 days", 1, true))
      p.returnRounds = 2
      assert.is_truthy(hover():find("Came back unsold 2 times since its last sale.", 1, true))
      p.returnRounds = 1
      assert.is_truthy(hover():find("Came back unsold once since its last sale.", 1, true))
      p.paceHours = 30
      assert.is_truthy(hover():find("No sales here in the last day", 1, true))
    end)

    it("the dock grows by the measured height of the wrapped pace lines", function()
      ready(12000)
      local Forever = GC.SellUI.PostPanel.Forever
      local lines = 1
      local c = {
        durationHead = { IsShown = function() return true end },
        paceLines = { IsShown = function() return true end, SetText = function() end,
          GetText = function() return "pace" end, GetStringHeight = function() return lines * 14 end },
      }
      local one = Forever.Height(c)
      lines = 2
      local two = Forever.Height(c)
      assert.equal(14, two - one)
      assert.is_true(two > one)
      -- An unmeasurable face falls back to one eleven-point line.
      c.paceLines.GetStringHeight = nil
      assert.equal(one, Forever.Height(c))
    end)
  end)

  describe("a held item", function()
    local LINK = "|cffffffff|Hitem:10:0:0:0:0:0:0:0:60:0:0:0:0:0|h[Belt]|h|r"
    local KEY = "item:10:5:0:0"

    -- One belt in the bags, one of the same up: the pace holds it as "enough".
    local function oneBelt()
      BAGS = { [0] = { { itemID = 10, stackCount = 1, itemName = "Belt", hyperlink = LINK } } }
      _G.C_Container.GetContainerItemLink = function(bag, slot)
        local stack = (BAGS[bag] or {})[slot]
        return stack and stack.hyperlink
      end
      _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = false } end
      _G.C_AuctionHouse.PostItem = function(_, duration, quantity)
        posted[#posted + 1] = { duration = duration, quantity = quantity }
        return false
      end
      _G.C_Item.GetDetailedItemLevelInfo = function() return 5 end
      GC.db.sellMarks = { [KEY] = true }
      owned({ { auctionID = 9, itemKey = { itemID = 10, itemLevel = 5, itemSuffix = 0 }, quantity = 1,
        buyoutAmount = 12000 } })
    end

    before_each(function() setup(FOREVER) end)

    it("a one-stack item shows HOW MANY and MAX, and MAX posts it", function()
      oneBelt()
      GC.SellState.dockKey = KEY
      GC.QuoteCache.Set(GC.SellState.quotes, KEY, 12000, time())
      ready(12000)
      assert.equal(KEY, GC.SellUI.PostPanel.key)
      assert.is_truthy(container.paceLines.text:find("Your 1 already up cover", 1, true))
      assert.is_true(container.qtyMax.shown)
      assert.is_true(container.qtyBoxBg.shown)
      assert.equal("ghost", container.qtyMax.variant)
      container.qtyMax.scripts.OnClick(container.qtyMax)
      assert.equal(GC.SellPositions.ALL, GC.SellState.quantityOverrides[KEY])
      assert.equal("active", container.qtyMax.variant)
      post()
      assert.equal(1, #posted)
      assert.equal(1, posted[1].quantity)
    end)

    it("the POST walk passes over it to the item that should go up", function()
      BAGS = { [0] = { { itemID = 10, stackCount = 20, itemName = "Herb" },
        { itemID = 11, stackCount = 5, itemName = "Moss" } } }
      GC.db.sellMarks = { ["commodity:10"] = true, ["commodity:11"] = true }
      owned({ lot(1), lot(2) })
      GC.QuoteCache.Set(GC.SellState.quotes, 11, 5000, time())
      ready(12000)
      assert.equal("enough_listed", (function()
        for _, e in ipairs(GC.SellState.queueSkipped) do
          if e.positionKey == "commodity:10" then return e.reason end
        end
      end)())
      local current = GC.SellUI.Dock.Current()
      assert.equal("commodity:11", current.position.positionKey)
      -- The row still says why: clicking it brings the held item to the dock.
      GC.SellState.dockKey = "commodity:10"
      assert.equal("commodity:10", GC.SellUI.Dock.Current().position.positionKey)
    end)

    it("retail has no enough_listed reason, so its walk is as it was", function()
      setup(RETAIL)
      owned({ lot(1), lot(2) })
      ready(12000)
      for _, e in ipairs(GC.SellState.queueSkipped) do assert.not_equal("enough_listed", e.reason) end
      assert.equal("commodity:10", GC.SellUI.Dock.Current().position.positionKey)
    end)
  end)

  describe("on retail", function()
    before_each(function() setup(RETAIL) end)

    it("retail SELL is unchanged", function()
      ready(12000)
      assert.is_nil(GC.SellUI.PostPanel.Forever)
      assert.is_nil(GC.SellUI.ROW.foreverMark)
      assert.is_nil(GC.SellUI.fmt.paceTooltip)
      assert.is_nil(container.durationButtons)
      assert.is_nil(container.durationHead)
      assert.is_nil(container.paceLines)
      GC.SellState.quantityOverrides["commodity:10"] = 5
      container.qtyMax.scripts.OnClick(container.qtyMax)
      assert.is_nil(GC.SellState.quantityOverrides["commodity:10"]) -- MAX clears the typed number
      sales.perDay = 0.5
      ready(12000)
      assert.is_nil(herbRow().itemStock.text:find("24 h", 1, true))
      assert.is_not_nil(hover())
    end)
  end)
end)
