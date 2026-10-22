local helper = require("spec.spec_helper")

-- Followed groups (plan 2026-10-22): SELL wired to the groups' rules, through the real Sell
-- services. GroupRules, SellRounds and the mail returns log are each optional: WoW: Forever loads
-- none of them, and an addon without the mail branch has no returns log at all.
describe("Sell tab with followed groups' rules", function()
  local GC

  local BAGS

  local function services()
    BAGS = { [0] = { { itemID = 10, stackCount = 5, itemName = "Herb" } } }
    _G.time = function() return 1000 end
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
      GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Herb" end }
    GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
        GetEntries = function() return {} end },
      Data = { GetItemValue = function() return { sold = 7447 } end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    helper.loadModule("Core/CancelQueue.lua", GC)
    for _, path in ipairs(helper.SELL_FILES) do helper.loadModule(path, GC) end
    GC.Acquisitions.Init({})
    return GC
  end

  after_each(function()
    _G.time = os.time
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil
  end)

  -- The mail branch (GC.MailReturns) keeps the returns log; SELL counts its expired lots as
  -- unsold rounds every time it composes. Without the mail module there are no returns.
  describe("the returns log", function()
    local function expired(itemID, at) return { itemID = itemID, count = 1, reason = "expired", at = at } end

    before_each(function()
      services()
      helper.loadModule("Core/SellRounds.lua", GC)
      GC.SellRounds.Init(GC.db)
    end)

    it("counts the returns the mail module hands out", function()
      GC.MailReturns = { Entries = function() return { expired(10, 900) } end }
      GC.SellCompose.Positions()
      assert.equal(1, GC.SellRounds.Rounds(10))
    end)

    it("reads the saved log when the mail module is not loaded", function()
      GC.db.mailReturns = { expired(10, 900) }
      GC.SellCompose.Positions()
      assert.equal(1, GC.SellRounds.Rounds(10))
    end)

    it("has no returns, and no error, without the mail module or its log", function()
      assert.is_nil(GC.MailReturns)
      assert.is_nil(GC.db.mailReturns)
      GC.SellCompose.Positions()
      assert.equal(0, GC.SellRounds.Rounds(10))
      assert.is_true(#GC.SellState.positions > 0)
    end)

    it("composes as before without SellRounds", function()
      GC.SellRounds = nil
      GC.MailReturns = { Entries = function() error("must not be read") end }
      GC.SellCompose.Positions()
      assert.is_true(#GC.SellState.positions > 0)
    end)
  end)
  -- Task 11: Compose hands SellPositions the followed groups' rules, only where GroupRules is
  -- loaded (retail's TOC). WoW: Forever loads none of it and SELL composes as it always has.
  describe("Compose", function()
    before_each(function() services() end)

    it("hands SellPositions the rules when GroupRules is loaded", function()
      GC.GroupRules = { RuleFor = function(itemID)
        if itemID == 10 then return { name = "Herbs", play = "gather", durationIndex = 2, floorUnit = 7000 } end
      end }
      GC.SellCompose.Positions()
      local position = GC.SellState.positions[1]
      assert.equal("Herbs", position.rule.name)
      assert.equal(0, position.sellRounds) -- no SellRounds: no rounds
      GC.SellRounds = { Ingest = function() return 0 end, Rounds = function() return 3 end }
      GC.SellCompose.Positions()
      assert.equal(3, GC.SellState.positions[1].sellRounds)
    end)

    it("Compose without GroupRules gives no position a rule", function()
      GC.QuoteCache.Set(GC.SellState.quotes, 10, 12000, 1000)
      GC.SellCompose.Positions()
      for _, position in ipairs(GC.SellState.positions) do assert.is_nil(position.rule) end
      local without = GC.SellState.queueEntries
      -- The same fixture with a GroupRules that holds nothing for this item queues the same.
      GC.GroupRules = { RuleFor = function() return nil end }
      GC.SellCompose.Positions()
      assert.same(without, GC.SellState.queueEntries)
      assert.equal(1, #without)
    end)
  end)

  it("postQuantity starts at the rule's one", function()
    services()
    local postQuantity = GC.SellUtil.postQuantity
    local position = { positionKey = "commodity:10", rulePostQty = 1, postableQty = 5 }
    assert.same({ 1, 5, false }, { postQuantity(position) })
    GC.SellState.quantityOverrides["commodity:10"] = 3
    assert.same({ 3, 5, true }, { postQuantity(position) })
    assert.same({ 5, 5, false }, { postQuantity({ positionKey = "commodity:11", postableQty = 5 }) })
  end)

  -- The deposit estimates read the rule's duration through a plain table: the Sniper's runs inside
  -- the purchase click, where only field reads belong ahead of the protected call.
  it("deposits read the rule's duration", function()
    services()
    local asked
    _G.C_AuctionHouse.CalculateCommodityDeposit = function(itemID, duration, quantity)
      asked = { itemID, duration, quantity }
      return 100
    end
    GC.db.settings.sniper.postDuration = 2
    GC.GroupRules = { durationByItem = { [10] = 3 } }
    GC.Flips.CommodityDeposit(10, 1)
    assert.same({ 10, 3, 1 }, asked)
    GC.Flips.CommodityDeposit(11, 1)
    assert.same({ 11, 2, 1 }, asked)
    GC.GroupRules = nil
    GC.Flips.CommodityDeposit(10, 1)
    assert.same({ 10, 2, 1 }, asked)

    local f = assert(io.open("GoldCap/UI/SniperFrame.lua"))
    local text = f:read("*a")
    f:close()
    local body = helper.functionBody(text, "local function depositFor(itemID, quantity)"):gsub("%-%-[^\n]*", "")
    assert.is_truthy(body:find("durationByItem[itemID]", 1, true))
    assert.is_nil(body:find("GC%.GroupRules%.[%w_]+%s*%("))
  end)

  -- The Sell tab on screen: the rows, the dock and the Post click, through the real view.
  describe("on screen", function()
    local root, container, posted, tooltip

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

    -- Item 10, five in the bags, in a gather group (24 h, not under 80% of usual) and the
    -- player's post duration set to 12 h.
    before_each(function()
      BAGS = { [0] = { { itemID = 10, stackCount = 5, itemName = "Herb" } } }
      posted = {}
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
        PostCommodity = function(_, duration, quantity, unit)
          posted[#posted + 1] = { duration = duration, quantity = quantity, unit = unit }
          return false
        end,
      }
      _G.C_Item = { GetItemNameByID = function() return "Herb" end }
      _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
      tooltip = {}
      _G.GameTooltip = {
        SetOwner = function(self) self.owner = true end, GetOwner = function() return nil end,
        AddLine = function(_, text) tooltip[#tooltip + 1] = text end,
        Show = function() end, Hide = function() end, SetItemByID = function() end,
      }

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
        Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
          GetEntries = function() return {} end },
        Data = { GetItemValue = function() return { sold = 7447 } end },
        db = { settings = { sniper = { postDuration = 1 } }, sellMarks = {} },
      }
      helper.loadModule("Core/Util.lua", GC)
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("Core/BagStock.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      helper.loadModule("Core/PostQueue.lua", GC)
      helper.loadModule("Core/GroupRules.lua", GC)
      helper.loadModule("UI/SellViewModel.lua", GC)
      helper.loadSell(GC)
      GC.Acquisitions.Init({})
      GC.GroupRules.Adopt({ v = 3, groups = { "Herbs" },
        caps = { { i = 10, c = 8000, g = 1, u = 10000, r = 1, k = true } },
        rules = { { n = "Herbs", p = "gather", d = 24, fp = 80 } } })

      root = region("Frame")
      root.HookScript = function(_, n, f) root.scripts[n] = f end
      root.status = region("FontString", root)
      GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
        rowWidth = 1100, rowHeight = 24 })
      container = GC.SellUI.container
      container:Show()
    end)

    after_each(function()
      _G.CreateFrame, _G.GetCoinTextureString, _G.ItemLocation, _G.GameTooltip = nil, nil, nil, nil
    end)

    local function ready(ask)
      GC.QuoteCache.Set(GC.SellState.quotes, 10, ask, 1000)
      GC.SellCompose.Positions()
      GC.SellUI.List.RenderRows()
    end

    local function herbRow()
      for _, row in ipairs(GC.SellUI.rows) do
        if row:IsShown() and row.kind == "position" and row.position.itemID == 10 then return row end
      end
    end

    it("the rule's duration is the one posted", function()
      ready(12000)
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.equal(1, #posted)
      assert.equal(2, posted[1].duration) -- the group's 24 h, not the setting's 12 h
      assert.equal(2, GC.SellState.postingPin.duration)
    end)

    it("the row names the group and its rule", function()
      ready(12000)
      local row = herbRow()
      assert.is_truthy(row.itemStock:GetText():find("Herbs", 1, true))
      assert.is_true(row.itemStock.wordWrap)
      row.scripts.OnEnter(row)
      local joined = table.concat(tooltip, "\n")
      assert.is_truthy(joined:find("Group you follow: Herbs", 1, true))
      assert.is_truthy(joined:find("all you have, 24 h, not under 80% of usual", 1, true))
    end)

    it("says the mark is the group's when the player never set it", function()
      ready(12000)
      local row = herbRow()
      assert.is_true(row.markSelling)
      GC.SellUI.ROW.markTooltip(row.mark, row)
      assert.is_truthy(table.concat(tooltip, "\n"):find("Marked for you: it is in a group you follow.", 1, true))
    end)

    it("Dock explains a held POST", function()
      ready(6000) -- the market is under the group's 8000 floor
      assert.equal("below_rule_floor", GC.SellState.queueSkipped[1].reason)
      assert.equal("the market is under your group's floor. Type a price to post anyway",
        GC.SellUI.Dock.HeldBackText("commodity:10"))
      assert.is_truthy(herbRow().itemStock:GetText():find("under group floor", 1, true))
    end)
  end)
end)
