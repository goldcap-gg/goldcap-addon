local helper = require("spec.spec_helper")

-- End to end through the real modules: bags -> positions -> GC.PostQueue.Build -> the rows ->
-- the dock (UI/Sell/PostPanel.lua) -> onPostClick. This is the seam that proves the queue, the
-- rows and the dock's POST are wired to each other, not just that each one works alone. The dock
-- names the item POST posts (owner, 2026-10-10): the one a row click put there, or the first item
-- of the queue in the list's own order.
describe("Sell tab, the posting queue control", function()
  local GC, root, render, container

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint(point, relative, relativePoint, x, y)
      self.points[#self.points + 1] = { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
    end
    function v:ClearAllPoints() self.points = {} end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
    function v:SetVariant(name) self.variant = name end
    function v:SetScript(n, f) self.scripts[n] = f end
    function v:HookScript(n, f) self.scripts[n] = f end
    function v:Show() self.shown = true end function v:Hide() self.shown = false end
    function v:IsShown() return self.shown end
    function v:Enable() self.enabled = true end function v:Disable() self.enabled = false end
    -- An EditBox's focus, as the dock's boxes read it.
    function v:ClearFocus() self.focused = false end function v:HasFocus() return self.focused == true end
    function v:SetJustifyH() end function v:SetWordWrap() end function v:SetTextColor(...) self.color = { ... } end
    function v:SetMaxLines(n) self.maxLines = n end
    function v:SetSpacing() end
    function v:SetAutoFocus() end function v:SetScrollChild() end
    function v:CreateTexture() return region("Texture", self) end
    function v:SetAllPoints() end function v:SetColorTexture() end
    function v:SetTexture() end function v:SetTexCoord() end
    function v:SetTextureSliceMargins() end
    function v:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
    function v:SetFrameStrata() end function v:SetFrameLevel() end
    function v:GetFrameLevel() return 0 end function v:EnableMouse() end
    return v
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
    render = GC.SellUI.List.RenderRows
    container = GC.SellUI.container
    container:Show()
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation = nil, nil, nil, nil
    _G.GetBuildInfo = nil
  end)

  local function compose()
    GC.SellCompose.Positions()
  end

  local function quotes()
    return GC.SellState.quotes
  end

  -- Composed and drawn, as GC.Sell.Refresh does it: the dock reads the rows it walks.
  local function ready()
    compose()
    render()
  end

  it("names the item POST posts, with what is in the bags", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local button = container.queueButton
    assert.equal("POST", button.label)
    assert.is_true(button.enabled)
    assert.equal("Eternium Ore", container.queueLabel.text)
    -- Widget, held back for want of a price, is next: the walk stops at it too.
    assert.equal("×246 in bags · then Widget", container.dockSub.text)
    assert.is_true(container.skipButton.shown)
  end)

  -- The owner, 2026-10-10: the gold spine beside the dock's item stood out of its card. The card's
  -- own edge is gold instead, and every other card keeps the glass edge.
  it("lights the dock's item by its card's edge, not a bar beside it", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local lit, plain = 0, 0
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" then
        assert.is_false(row.spine.shown)
        if row.position.positionKey == "commodity:23427" then
          assert.same({ 1, 1, 0, 0.45 }, row.cardRing.vertexColor)
          lit = lit + 1
        else
          assert.same({ 1, 1, 1, 0.06 }, row.cardRing.vertexColor)
          plain = plain + 1
        end
      end
    end
    assert.equal(1, lit)
    assert.is_true(plain > 0)
  end)

  -- The owner, 2026-10-10: a tier for the item over the controls was crooked and took the list's
  -- room. One row: the item left of the controls, its words stopping short of them, and the row
  -- growing only when the name wraps past it.
  it("keeps the item left of the controls in one row, which grows when its name wraps", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local DOCK = GC.SellUI.DOCK
    local label = container.queueLabel
    assert.equal(container, label.points[2].relative)
    assert.equal("TOPRIGHT", label.points[2].point)
    -- POST, SKIP, the price, MAX and how many, right to left, then the gap.
    local right = DOCK.PAD + DOCK.POST_W + 8 + DOCK.SKIP_W + 16 + DOCK.PRICE_W
      + 14 + DOCK.MAX_W + 4 + DOCK.QTY_W + DOCK.GAP
    if container.netValue.shown then right = right + 16 + 4 + DOCK.NET_W end -- and the margin beside it
    assert.equal(-right, label.points[2].x)
    assert.equal(DOCK.H, GC.SellUI.Dock.Height())
    label.GetStringHeight = function() return 30 end -- two lines of name
    container.dockSub.GetStringHeight = function() return 12 end
    render()
    local height = 30 + 2 + 12 + 2 * DOCK.PAD
    assert.equal(height, GC.SellUI.Dock.Height())
    assert.equal(math.floor(height / 2 + 22), label.points[1].y) -- the words centred on the row
    assert.equal(height + 6, container.scroll.points[2].y) -- the list stops at the dock's top edge
    assert.equal(height + 6, container.inspector.points[2].y)
  end)

  -- A refused press is answered beside the button, in the stock line's place, for a few seconds.
  it("says what a refused press is told under the item, then gives the stock line back", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local timers = {}
    local saved = _G.C_Timer
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local box = container.priceBox
    box.scripts.OnEditFocusGained(box)
    box:SetText("abc")
    box.scripts.OnTextChanged(box, true)
    box.scripts.OnEnterPressed(box)
    assert.equal("Type a price in gold, or clear the box to use GoldCap's", container.dockStatus.text)
    assert.is_true(container.dockStatus.shown)
    assert.is_false(container.dockSub.shown)
    timers[#timers]()
    assert.is_false(container.dockStatus.shown)
    assert.is_true(container.dockSub.shown)
    _G.C_Timer = saved
  end)

  -- The owner, 2026-10-10: two items marked, both held back below what they cost; SKIP on the
  -- first left the dock saying "Nothing queued to post" with the second still on the list.
  it("walks to the items the queue held back, says why in red, and SKIP goes from one to the next", function()
    ready() -- no quote at all: BOTH bag items are held back, nothing enters the queue
    local button = container.queueButton
    assert.equal(0, #GC.SellState.queueEntries)
    local first = container.queueLabel.text
    assert.is_true(first == "Eternium Ore" or first == "Widget")
    assert.equal("needs a fresh price -- press Refresh", container.dockSub.text)
    assert.same({ 1, 0, 0, 1 }, container.dockSub.color)
    -- POST asks for the price, as the row's Post does.
    assert.is_true(button.enabled)
    container.skipButton.scripts.OnClick(container.skipButton)
    local second = container.queueLabel.text
    assert.is_true(second == "Eternium Ore" or second == "Widget")
    assert.is_not.equal(first, second)
    assert.equal("needs a fresh price -- press Refresh", container.dockSub.text)
    container.skipButton.scripts.OnClick(container.skipButton)
    assert.is_false(button.enabled)
    assert.equal("POST", button.label)
    assert.equal("Nothing queued to post", container.queueLabel.text)
    assert.is_false(container.skipButton.shown)
    assert.is_false(container.priceBoxBg.shown)
    -- Passed over, they are not held back any more: the rows say "skipped".
    assert.equal(0, #GC.SellState.queueSkipped)
    assert.is_nil(GC.SellUI.Dock.SellingAside():find("held back", 1, true))
  end)

  -- Not one whose last post may still go up: that one waits for its answer.
  it("does not walk to an item waiting for its last post's answer", function()
    ready()
    GC.SellState.queueSkipped = { { positionKey = "commodity:23427", itemName = "Eternium Ore",
      reason = "awaiting_answer" } }
    GC.SellUI.Dock.PaintQueueButton()
    assert.equal("Nothing queued to post", container.queueLabel.text)
  end)

  -- The owner, 2026-10-10: the skipped item's row stayed lit, its panel open, under a dock that
  -- had moved on.
  it("shuts the skipped item's panel", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local ore
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" and row.position.itemID == 23427 then ore = row end
    end
    ore.scripts.OnClick(ore)
    assert.is_true(GC.SellUI.expanded["commodity:23427"])
    container.skipButton.scripts.OnClick(container.skipButton)
    assert.is_nil(GC.SellUI.expanded["commodity:23427"])
    assert.equal("Widget", container.queueLabel.text)
  end)

  -- The SELLING heading carries the count, and its hover the reasons (Dock.SellingAside,
  -- Dock.HeldBackHint): the dock is one row on this deck.
  it("surfaces the held-back count in plain words, not the raw skip token", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    assert.equal(1, #GC.SellState.queueSkipped)
    assert.matches("1 held back", GC.SellUI.Dock.SellingAside(), 1, true)
    local hint = GC.SellUI.Dock.HeldBackHint()
    assert.matches("Widget", hint, 1, true)
    assert.is_nil(hint:find("no_fresh_price", 1, true))
  end)

  it("posts the dock's item when clicked, through onPostClick's own pin and validation", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local button = container.queueButton
    button.scripts.OnClick(button)
    local pin = GC.SellState.postingPin
    assert.equal("commodity:23427", pin.positionKey)
    assert.equal(pin.row, GC.SellState.postingRow)
    assert.equal("posting", pin.row.postStage)
  end)

  it("reads Confirm on the control and routes the second click to the same row", function()
    _G.C_AuctionHouse.PostCommodity = function() return true end -- needs a second click to confirm
    local confirmCalls = 0
    _G.C_AuctionHouse.ConfirmPostCommodity = function() confirmCalls = confirmCalls + 1 end
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local button = container.queueButton
    button.scripts.OnClick(button)
    assert.equal("CONFIRM", button.label)
    assert.is_true(button.enabled)
    button.scripts.OnClick(button)
    assert.equal(1, confirmCalls)
  end)

  it("disables while its post is genuinely in flight (posting/confirming)", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local button = container.queueButton
    button.scripts.OnClick(button) -- PostCommodity returns false above: lands on postStage "posting"
    assert.is_false(button.enabled)
    assert.equal("POSTING…", button.label)
  end)

  -- The owner's run (2026-10-10): by value, a part-posted water stood in front of the linen
  -- marked beside it. The list's order is the one the player reads, and it settles: a quote that
  -- lands later moves a figure, never a row (GC.SellViewModel.Settle).
  it("names the first item in the list's own order, not the queue's value order", function()
    GC.QuoteCache.Set(quotes(), 99001, 700, 1000)
    ready() -- Widget is priced first, so it settles above the ore
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    assert.equal("commodity:23427", GC.SellState.queueEntries[1].positionKey) -- worth more
    assert.equal("Widget", container.queueLabel.text)
    assert.equal("×5 in bags · then Eternium Ore", container.dockSub.text)
  end)

  it("puts the item whose row is clicked in the dock, whatever the queue's order", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    GC.QuoteCache.Set(quotes(), 99001, 700, 1000)
    ready()
    local widget
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" and row.position.itemID == 99001 then widget = row end
    end
    widget.scripts.OnClick(widget)
    assert.equal("Widget", container.queueLabel.text)
    container.queueButton.scripts.OnClick(container.queueButton)
    assert.equal("commodity:99001", GC.SellState.postingPin.positionKey)
  end)

  it("passes the dock's item over with SKIP, for this visit, and names the next", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    GC.QuoteCache.Set(quotes(), 99001, 700, 1000)
    ready()
    local first = container.queueLabel.text
    container.skipButton.scripts.OnClick(container.skipButton)
    assert.is_not.equal(first, container.queueLabel.text)
    local skipped
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" and row.position.itemName == first then skipped = row end
    end
    assert.matches("skipped", skipped.itemStock.text, 1, true)
    -- Not held back: the footer's count is for what the queue refused.
    assert.equal(0, #GC.SellState.queueSkipped)
    container.skipButton.scripts.OnClick(container.skipButton)
    assert.equal("Nothing queued to post", container.queueLabel.text)
    -- The next visit walks the list again.
    GC.Sell.Reset()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    GC.QuoteCache.Set(quotes(), 99001, 700, 1000)
    ready()
    assert.equal(first, container.queueLabel.text)
  end)

  -- Review, 2026-10-10: a Confirm sends what it was armed with, so a price or a number changed
  -- while it waits has to let it go, or CONFIRM lists at a price no longer on screen.
  describe("a Confirm waiting while the price changes", function()
    local sent, confirms
    before_each(function()
      sent, confirms = {}, {}
      _G.C_AuctionHouse.PostCommodity = function(_, _, _, unit) sent[#sent + 1] = unit; return true end
      _G.C_AuctionHouse.ConfirmPostCommodity = function(_, _, _, unit) confirms[#confirms + 1] = unit end
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.equal("CONFIRM", container.queueButton.label)
    end)

    local function typePrice(text)
      local box = container.priceBox
      box.scripts.OnEditFocusGained(box)
      box.focused = true
      box.text = text
      box.scripts.OnTextChanged(box, true)
      box.scripts.OnEnterPressed(box)
    end

    it("lets it go when the dock's price is typed over, and posts at the new price", function()
      typePrice("20")
      assert.is_nil(GC.SellState.postingRow)
      assert.equal("POST", container.queueButton.label)
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.equal(200000, sent[2])
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.same({ 200000 }, confirms)
    end)

    -- The box keeps its focus through a click on POST: Escape after it puts back the price the
    -- post was not armed with, and the Confirm goes with it.
    it("lets it go when Escape puts back the price it was armed with", function()
      local box = container.priceBox
      box.scripts.OnEditFocusGained(box)
      box.focused = true
      box.text = "20"
      box.scripts.OnTextChanged(box, true) -- lets the first Confirm go
      container.queueButton.scripts.OnClick(container.queueButton) -- POST at 20g, asks to confirm
      assert.equal(200000, sent[2])
      assert.equal("CONFIRM", container.queueButton.label)
      box.scripts.OnEscapePressed(box)
      assert.is_nil(GC.SellState.priceOverrides["commodity:23427"])
      assert.is_nil(GC.SellState.postingRow)
      assert.equal("POST", container.queueButton.label)
    end)

    it("refuses the Confirm if the price changed some other way", function()
      GC.SellState.priceOverrides["commodity:23427"] = 200000
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.same({}, confirms)
      assert.equal("Post confirmation expired", root.status.text)
    end)

    -- The queue can move while a Confirm waits (the walk prices, a mark changes): the dock stays
    -- on the item that is waiting, and CONFIRM stays reachable.
    it("keeps the item it is waiting on in the dock however the queue moves", function()
      GC.db = { sellMarks = { ["commodity:23427"] = false } }
      GC.SellCompose.Queue()
      assert.equal(0, #GC.SellState.queueEntries)
      assert.equal("Eternium Ore", container.queueLabel.text)
      assert.equal("CONFIRM", container.queueButton.label)
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.equal(1, #confirms)
    end)
  end)

  it("posts nothing from the key while the Sell tab is not on screen", function()
    local posts = 0
    _G.C_AuctionHouse.PostCommodity = function() posts = posts + 1; return false end
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    container:Hide()
    root.GoldCapPostNext()
    assert.equal(0, posts)
    container:Show()
    root.GoldCapPostNext()
    assert.equal(1, posts)
  end)

  it("takes SKIP away while the dock's post is on the wire", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    assert.is_true(container.skipButton.enabled)
    container.queueButton.scripts.OnClick(container.queueButton) -- lands on postStage "posting"
    assert.is_false(container.skipButton.enabled)
  end)

  -- Opening an item to read its book must not take POST over for good (review): shut again, the
  -- dock goes back to the list.
  it("gives the dock back to the list when the clicked item's panel is shut", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    GC.QuoteCache.Set(quotes(), 99001, 700, 1000)
    ready()
    assert.equal("Eternium Ore", container.queueLabel.text)
    local function widget()
      for _, row in ipairs(GC.SellUI.rows) do
        if row:IsShown() and row.kind == "position" and row.position.itemID == 99001 then return row end
      end
    end
    widget().scripts.OnClick(widget())
    assert.equal("Widget", container.queueLabel.text)
    widget().scripts.OnClick(widget())
    assert.equal("Eternium Ore", container.queueLabel.text)
  end)

  it("says in red why the queue held back an item a click put in the dock", function()
    GC.ForeverScan = { Enabled = function() return true end }
    GC.ForeverValue = { VendorUnit = function(id) return id == 23427 and 10 ^ 9 or nil end }
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local ore
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" and row.position.itemID == 23427 then ore = row end
    end
    ore.scripts.OnClick(ore)
    assert.equal("Eternium Ore", container.queueLabel.text)
    assert.equal("a vendor pays more -- sell it there", container.dockSub.text)
    assert.same({ 1, 0, 0, 1 }, container.dockSub.color)
  end)

  -- The owner, 2026-10-10: keep the row's own Post, "it is handy". The same click as the dock's.
  it("keeps a Post on a row with stock, which posts that row", function()
    local posted = 0
    _G.C_AuctionHouse.PostCommodity = function() posted = posted + 1; return false end
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    ready()
    local ore
    for _, row in ipairs(GC.SellUI.rows) do
      if row:IsShown() and row.kind == "position" and (row.position.bagQty or 0) > 0 then
        assert.is_true(row.action.shown)
        assert.equal("Post", row.action.label)
        assert.equal("Post", row.action.helpKey)
      end
      if row:IsShown() and row.kind == "position" and row.position.itemID == 23427 then ore = row end
    end
    ore.action.scripts.OnClick(ore.action)
    assert.equal(1, posted)
    assert.equal(ore, GC.SellState.postingRow)
  end)

  it("holds Eternium Ore back in WoW: Forever when a vendor pays more for it", function()
    GC.ForeverScan = { Enabled = function() return true end }
    GC.ForeverValue = { VendorUnit = function(id) return id == 23427 and 10 ^ 9 or nil end }
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    local entries = GC.SellState.queueEntries
    local skipped = GC.SellState.queueSkipped
    for _, entry in ipairs(entries) do
      assert.is_not.equal("commodity:23427", entry.positionKey)
    end
    local sawEternium = false
    for _, skip in ipairs(skipped) do
      if skip.positionKey == "commodity:23427" then sawEternium = true end
    end
    assert.is_true(sawEternium)
    render()
    -- The dock stops at it all the same, and says why in red.
    assert.same({ 1, 0, 0, 1 }, container.dockSub.color)
    assert.matches("a vendor pays more -- sell it there", GC.SellUI.Dock.HeldBackHint(), 1, true)
  end)

  -- The tests above run with no GC.Game at all, which is retail: one press posts, exactly as
  -- addon-v0.15.3 did (retail drift audit F1). These pin the retail passport explicitly, and the
  -- WoW: Forever split -- where the press that has to render first renders only, and the next
  -- press posts (final review C1).
  -- The selling list (owner, 2026-10-09): POST and the post-next key list only what the player
  -- marked; a row's mark is the choice, kept in the saved data; TO POST reads in two sections.
  describe("the selling list", function()
    before_each(function() GC.db = { sellMarks = {} } end)

    local function rowOf(positionKey)
      for _, row in ipairs(GC.SellUI.rows) do
        if row.shown and row.kind == "position" and row.position.positionKey == positionKey then return row end
      end
    end

    -- What the list draws, top to bottom: a heading's words, or a position's key.
    local function drawn()
      local out = {}
      for _, row in ipairs(GC.SellUI.rows) do
        if row.shown and row.kind == "section" then out[#out + 1] = row.sectionLabel.text
        elseif row.shown and row.kind == "position" then out[#out + 1] = row.position.positionKey end
      end
      return out
    end

    it("posts nothing the player has not marked, and says how to mark it", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      assert.is_false(container.queueButton.enabled)
      assert.equal("Mark what to sell with the circle", container.queueLabel.text)
    end)

    it("puts an item on the list from its row's mark, keeps the choice, and takes it off again", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      local row = rowOf("commodity:23427")
      assert.is_true(row.mark.shown)
      assert.is_false(row.mark.coin.shown)

      row.mark.scripts.OnClick(row.mark)
      assert.is_true(GC.db.sellMarks["commodity:23427"])
      assert.is_true(container.queueButton.enabled)
      assert.equal("Eternium Ore", container.queueLabel.text)
      assert.is_true(rowOf("commodity:23427").mark.coin.shown)

      row = rowOf("commodity:23427")
      row.mark.scripts.OnClick(row.mark)
      assert.is_false(GC.db.sellMarks["commodity:23427"])
      assert.is_false(container.queueButton.enabled)
    end)

    -- PROCEEDS is what POST lists, so a mark moves it; ore nobody has a receipt for has no PROFIT
    -- to show. On this deck it is the SELLING heading's: the dock is one row (owner, 2026-10-10).
    it("adds up only what is marked, in the SELLING heading", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      assert.is_nil(GC.SellUI.Dock.SellingAside():find("PROCEEDS", 1, true))
      local row = rowOf("commodity:23427")
      row.mark.scripts.OnClick(row.mark)
      local entry = GC.SellState.queueEntries[1]
      local amount = GC.Sell._FormatAmount(math.floor(entry.value * 95 / 100))
      local heading = helper.plain(drawn()[1])
      assert.matches("^SELLING 1", heading)
      assert.is_truthy(heading:find("PROCEEDS " .. helper.plain(amount), 1, true))
      assert.is_nil(heading:find("PROFIT", 1, true))
      assert.is_false(container.summary.total.shown) -- the dock keeps no ledger on this deck
    end)

    it("reads in two sections: what POST lists, then what only its own Post does", function()
      GC.db.sellMarks["commodity:99001"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      local list = drawn()
      assert.equal(4, #list)
      assert.matches("^SELLING 1", helper.plain(list[1]))
      assert.equal("commodity:99001", list[2])
      assert.matches("^NOT SELLING 1", helper.plain(list[3]))
      assert.equal("commodity:23427", list[4])
    end)

    it("counts what Deals bought as marked without a click, and says why", function()
      GC.Acquisitions.Record({ source = "goldcap", itemID = 23427, positionKey = "commodity:23427",
        itemName = "Eternium Ore", quantity = 246, total = 246 * 1000, acquiredAt = 900,
        character = "Owner-Dentarg", region = "eu" })
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      assert.equal("Eternium Ore", container.queueLabel.text)
      local lines = {}
      _G.GameTooltip = { SetOwner = function() end, Show = function() end,
        AddLine = function(_, text) lines[#lines + 1] = text end }
      GC.Theme.TooltipAnchor = function() return "ANCHOR_RIGHT" end
      local row = rowOf("commodity:23427")
      assert.is_true(row.mark.coin.shown)
      row.mark.scripts.OnEnter(row.mark)
      assert.equal("Selling", lines[1])
      assert.is_truthy(table.concat(lines, "\n"):find("you bought it on DEALS", 1, true))
      _G.GameTooltip = nil
    end)

    -- Review of 523fdec, finding 1: an unmarked row lost the tag that says why its own Post would
    -- not go up.
    it("still tags an unmarked row with what is wrong with it", function()
      GC.ForeverScan = { Enabled = function() return true end }
      GC.ForeverValue = { VendorUnit = function(id) return id == 23427 and 10 ^ 9 or nil end }
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      assert.is_truthy(rowOf("commodity:23427").itemStock.text:find("vendor pays more", 1, true))
    end)

    -- Finding 2: with the SELLING heading on row 1, the dock's CONFIRM found no row to confirm.
    it("confirms from the dock a post it armed under the SELLING heading", function()
      _G.C_AuctionHouse.PostCommodity = function() return true end -- needs a second click to confirm
      local confirmCalls = 0
      _G.C_AuctionHouse.ConfirmPostCommodity = function() confirmCalls = confirmCalls + 1 end
      GC.db.sellMarks["commodity:23427"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      local button = container.queueButton
      button.scripts.OnClick(button)
      assert.equal("CONFIRM", button.label)
      button.scripts.OnClick(button)
      assert.equal(1, confirmCalls)
    end)

    -- Finding 3: an armed post held the render back, so the mark never changed and a second click
    -- could not undo the first.
    it("answers an armed post no, as a row click does, and toggles from what is saved", function()
      _G.C_AuctionHouse.PostCommodity = function() return true end
      GC.db.sellMarks["commodity:23427"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.is_not_nil(GC.SellState.postingRow)

      local widget = rowOf("commodity:99001")
      widget.mark.scripts.OnClick(widget.mark)
      assert.is_nil(GC.SellState.postingRow)
      assert.is_true(GC.db.sellMarks["commodity:99001"])
      widget = rowOf("commodity:99001")
      assert.is_true(widget.mark.coin.shown)
      widget.mark.scripts.OnClick(widget.mark)
      assert.is_false(GC.db.sellMarks["commodity:99001"])
    end)

    -- Finding 5: the hint is for a deck with nothing marked, not one whose marked items wait.
    it("does not ask for a mark while a marked item is only held back: it shows that item", function()
      GC.db.sellMarks["commodity:99001"] = true -- Widget has no price: held back
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      assert.equal("Widget", container.queueLabel.text)
      assert.equal("needs a fresh price -- press Refresh", container.dockSub.text)
    end)

    -- ...nor once the walk has been down the list.
    it("does not ask for a mark once every marked item was passed over", function()
      GC.db.sellMarks["commodity:99001"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      container.skipButton.scripts.OnClick(container.skipButton)
      assert.is_false(container.queueButton.enabled)
      assert.equal("Nothing queued to post", container.queueLabel.text)
    end)

    local function positionsDrawn()
      local out = {}
      for _, text in ipairs(drawn()) do
        if text:find("commodity:", 1, true) == 1 then out[#out + 1] = text end
      end
      return out
    end

    -- The owner, 2026-10-10: two items marked, the first taken off the list, and the second one's
    -- coin went out until the list was drawn again. The rows are pooled: the click painted the
    -- row it came from after the render had already put the second item on it.
    it("leaves the next item's coin lit when the item above it comes off the list", function()
      GC.db.sellMarks["commodity:23427"] = true
      GC.db.sellMarks["commodity:99001"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      local order = positionsDrawn()
      local first = rowOf(order[1])
      first.mark.scripts.OnClick(first.mark)
      assert.is_false(GC.db.sellMarks[order[1]])
      assert.equal(first, rowOf(order[2])) -- the same pooled row, the second item on it now
      assert.is_true(first.mark.coin.shown)
      assert.is_true(first.markSelling)
    end)

    -- The owner, 2026-10-10: after SKIP the mark stayed lit and nothing on the row looked changed.
    it("puts out a skipped item's coin for this visit, and a click on it puts it back on the walk", function()
      GC.db.sellMarks["commodity:23427"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      assert.equal("Eternium Ore", container.queueLabel.text)
      container.skipButton.scripts.OnClick(container.skipButton)
      local ore = rowOf("commodity:23427")
      assert.is_false(ore.mark.coin.shown)
      assert.is_true(ore.markDone)
      assert.is_true(GC.db.sellMarks["commodity:23427"]) -- the saved mark is as it was
      assert.equal("Nothing queued to post", container.queueLabel.text)
      local lines = {}
      _G.GameTooltip = { SetOwner = function() end, Show = function() end, GetOwner = function() end,
        AddLine = function(_, text) lines[#lines + 1] = text end }
      GC.Theme.TooltipAnchor = function() return "ANCHOR_RIGHT" end
      ore.mark.scripts.OnEnter(ore.mark)
      assert.equal("Done for this visit", lines[1])
      ore.mark.scripts.OnClick(ore.mark)
      _G.GameTooltip = nil
      ore = rowOf("commodity:23427")
      assert.is_true(ore.mark.coin.shown)
      assert.is_nil(ore.markDone)
      assert.is_true(GC.db.sellMarks["commodity:23427"])
      assert.equal("Eternium Ore", container.queueLabel.text)
    end)

    it("puts an item on the walk when it is marked, whatever this visit did with it before", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      ready()
      GC.SellState.passedThisVisit["commodity:23427"] = true
      local ore = rowOf("commodity:23427")
      ore.mark.scripts.OnClick(ore.mark)
      assert.is_true(GC.db.sellMarks["commodity:23427"])
      assert.is_true(rowOf("commodity:23427").mark.coin.shown)
      assert.equal("Eternium Ore", container.queueLabel.text)
    end)

    -- Finding 6: a row whose identity is not settled is never POST's to list.
    it("keeps a row whose identity is not settled out of SELLING, whatever Deals bought", function()
      local repair = { unresolved = true, sources = { goldcap = 3 }, bagQty = 3 }
      local ordered, sectionOf = GC.SellUI.ROW.bySelling({ repair })
      assert.equal(repair, ordered[1])
      assert.equal("notSelling", sectionOf[repair].id)
    end)

    it("draws no marks and no sections before the saved data is loaded, and lists everything as before", function()
      GC.db = nil
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      assert.equal("Eternium Ore", container.queueLabel.text)
      assert.is_false(rowOf("commodity:23427").mark.shown)
      for _, text in ipairs(drawn()) do assert.is_nil(text:find("SELLING", 1, true)) end
    end)
  end)

  describe("per game", function()
    local function passport(interface)
      helper.loadModule("Core/Game.lua", GC)
      _G.GetBuildInfo = function() return "x", "1", "Sep 27 2026", interface end
    end

    -- Which bag slot each post took: the ore is slots 1-2, the Widget slot 3.
    local function postCounter()
      local posts, slots = 0, {}
      _G.C_AuctionHouse.PostCommodity = function(location)
        posts = posts + 1
        slots[#slots + 1] = location.slot
        return false
      end
      return function() return posts end, slots
    end

    for _, game in ipairs({ { "retail", 120100 }, { "WoW: Forever", 16001 } }) do
      it(("on %s the dock's POST posts its item on the first press"):format(game[1]), function()
        passport(game[2])
        local posts = postCounter()
        GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
        ready()
        container.queueButton.scripts.OnClick(container.queueButton)
        assert.equal(1, posts())
      end)

      it(("on %s the POST keybinding posts on the first press too"):format(game[1]), function()
        passport(game[2])
        local posts = postCounter()
        GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
        ready()
        root.GoldCapPostNext()
        assert.equal(1, posts())
      end)

      -- WoW: Forever refuses a protected call once the click that makes it has run a render or the
      -- dock's own paint (final review C1, C3): the press reads the rows already drawn, and paints
      -- after the call.
      it(("on %s the press renders and paints nothing before the call"):format(game[1]), function()
        passport(game[2])
        GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
        ready()
        local renders, paints, before = 0, 0, nil
        local List, PostPanel = GC.SellUI.List, GC.SellUI.PostPanel
        local realRender, realPaint = List.RenderRows, PostPanel.Paint
        List.RenderRows = function(...) renders = renders + 1; return realRender(...) end
        PostPanel.Paint = function(...) paints = paints + 1; return realPaint(...) end
        _G.C_AuctionHouse.PostCommodity = function() before = { renders, paints }; return false end
        container.queueButton.scripts.OnClick(container.queueButton)
        List.RenderRows, PostPanel.Paint = realRender, realPaint
        assert.same({ 0, 0 }, before)
      end)
    end

    -- P1: a Cancel lot or a Remove armed on another row holds renderRows() to a no-op (its own
    -- guard), so the rows can still be whatever was drawn before the click. The dock walks those
    -- rows and paints from the same answer the press reads, so what it names is what goes up --
    -- never an item it did not name.
    describe("with a Remove armed elsewhere while the rows are stale", function()
      -- Widget (99001) is quoted and fully evidenced first, so it alone is postable and settles
      -- on row 1. A Remove is armed on ITS OWN manual cost entry -- any armed row would hold the
      -- render, this one just happens to be real -- and only THEN is Eternium Ore quoted too: its
      -- far larger value (246 units against Widget's 5) makes it the queue's new head, but
      -- nothing re-renders.
      local function armRemoveWithStaleRows()
        GC.QuoteCache.Set(quotes(), 99001, 700, 1000)
        GC.Acquisitions.RecordManual({ itemID = 99001, positionKey = "commodity:99001",
          quantity = 5, total = 2500, acquiredAt = 1000, character = "Owner-Dentarg", region = "eu" })
        compose()
        GC.SellUI.expanded["commodity:99001"] = true
        render()
        local rows = GC.SellUI.rows
        assert.equal("commodity:99001", rows[1].position.positionKey) -- sanity: Widget is row 1
        local removeRow
        for _, r in ipairs(rows) do
          if r.kind == "batch" and r.batch and r.batch.source == "manual" then removeRow = r end
        end
        assert.truthy(removeRow)
        removeRow.action.scripts.OnClick(removeRow.action) -- the row's own Remove button, for real
        assert.equal("armed", removeRow.removeStage)
        GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
        compose()
        local qe = GC.SellState.queueEntries
        assert.equal("commodity:23427", qe[1].positionKey) -- sanity: the head moved to Eternium Ore
      end

      for _, game in ipairs({ { "retail", 120100 }, { "WoW: Forever", 16001 } }) do
        it(("on %s the dock's POST posts the item the dock names"):format(game[1]), function()
          passport(game[2])
          armRemoveWithStaleRows()
          local posts, slots = postCounter()
          assert.equal("Widget", container.queueLabel.text)
          container.queueButton.scripts.OnClick(container.queueButton)
          assert.equal(1, posts())
          assert.equal(3, slots[1])
        end)
      end
    end)
  end)
end)
