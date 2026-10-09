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

  it("labels the control with the head item and price, and counts the queue on the button itself", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    local button = container.queueButton
    local label = container.queueLabel
    assert.equal("POST 1", button.label)
    assert.is_true(button.enabled)
    assert.matches("Eternium Ore", label.text, 1, true)
  end)

  it("disables with an honest word when nothing is postable", function()
    compose() -- no quote at all: BOTH bag items are held back, nothing enters the queue
    local button = container.queueButton
    assert.is_false(button.enabled)
    assert.matches("NOTHING", button.label)
  end)

  it("surfaces the held-back count in plain words, not the raw skip token", function()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    compose()
    assert.equal(1, #GC.SellState.queueSkipped)
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
    local rows = GC.SellUI.rows
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
    assert.equal("CONFIRM", button.label)
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
    local rows = GC.SellUI.rows
    assert.equal("position", rows[1].kind)
    assert.equal("commodity:23427", rows[1].position.positionKey)
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
    local button = container.queueButton
    assert.matches("NOTHING", button.label)
    local hit = container.queueHeldBackHit
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    hit.scripts.OnEnter(hit)
    local joined = table.concat(tooltipLines, " ")
    assert.matches("a vendor pays more -- sell it there", joined, 1, true)
    _G.GameTooltip = nil
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
      compose()
      assert.is_false(container.queueButton.enabled)
      assert.matches("NOTHING", container.queueButton.label)
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
      assert.equal("POST 1", container.queueButton.label)
      assert.is_true(rowOf("commodity:23427").mark.coin.shown)

      row = rowOf("commodity:23427")
      row.mark.scripts.OnClick(row.mark)
      assert.is_false(GC.db.sellMarks["commodity:23427"])
      assert.matches("NOTHING", container.queueButton.label)
    end)

    -- The dock's PROCEEDS is what POST lists, so a mark moves it; ore nobody has a receipt for
    -- has no PROFIT to show.
    it("adds up only what is marked in the dock's PROCEEDS", function()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      assert.is_false(container.summary.total.shown)
      local row = rowOf("commodity:23427")
      row.mark.scripts.OnClick(row.mark)
      local entry = GC.SellState.queueEntries[1]
      assert.equal(GC.Sell._FormatAmount(math.floor(entry.value * 95 / 100)), container.summary.total:GetText())
      assert.is_true(container.summary.total.shown)
      assert.is_false(container.summary.profit.shown)
    end)

    it("reads in two sections: what POST lists, then what only its own Post does", function()
      GC.db.sellMarks["commodity:99001"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      local list = drawn()
      assert.equal(4, #list)
      assert.matches("^SELLING 1", list[1])
      assert.equal("commodity:99001", list[2])
      assert.matches("^NOT SELLING 1", list[3])
      assert.equal("commodity:23427", list[4])
    end)

    it("counts what Deals bought as marked without a click, and says why", function()
      GC.Acquisitions.Record({ source = "goldcap", itemID = 23427, positionKey = "commodity:23427",
        itemName = "Eternium Ore", quantity = 246, total = 246 * 1000, acquiredAt = 900,
        character = "Owner-Dentarg", region = "eu" })
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      assert.equal("POST 1", container.queueButton.label)
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
    it("confirms from the dock a post the head row's own Post armed", function()
      _G.C_AuctionHouse.PostCommodity = function() return true end -- needs a second click to confirm
      local confirmCalls = 0
      _G.C_AuctionHouse.ConfirmPostCommodity = function() confirmCalls = confirmCalls + 1 end
      GC.db.sellMarks["commodity:23427"] = true
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      render()
      local row = rowOf("commodity:23427")
      row.action.scripts.OnClick(row.action)
      local button = container.queueButton
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
      local head = rowOf("commodity:23427")
      head.action.scripts.OnClick(head.action)
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
    it("does not ask for a mark while a marked item is only held back", function()
      GC.db.sellMarks["commodity:99001"] = true -- Widget has no price: held back
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      assert.matches("NOTHING", container.queueButton.label)
      assert.equal("", container.queueLabel.text)
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
      assert.equal("POST 1", container.queueButton.label)
      assert.is_false(rowOf("commodity:23427").mark.shown)
      for _, text in ipairs(drawn()) do assert.is_nil(text:find("SELLING", 1, true)) end
    end)
  end)

  describe("per game", function()
    local function passport(interface)
      helper.loadModule("Core/Game.lua", GC)
      _G.GetBuildInfo = function() return "x", "1", "Sep 27 2026", interface end
    end

    local function postCounter()
      local posts = 0
      _G.C_AuctionHouse.PostCommodity = function() posts = posts + 1; return false end
      return function() return posts end
    end

    it("on retail the dock's POST posts the head on the first press, from any deck", function()
      passport(120100)
      local posts = postCounter()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      local button = container.queueButton
      button.scripts.OnClick(button)
      assert.equal(1, posts())
      assert.equal("commodity:23427", GC.SellUI.rows[1].position.positionKey)
    end)

    it("on retail the POST keybinding posts on the first press too", function()
      passport(120100)
      local posts = postCounter()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      root.GoldCapPostNext()
      assert.equal(1, posts())
    end)

    -- P1: a Cancel lot or a Remove armed on another row holds renderRows() to a no-op (its own
    -- guard, above), so `rows` can still be whatever deck was on screen before the click. The
    -- retail branch used to trust row 1's `kind == "position"` alone, so it posted that stale
    -- row instead of refusing -- even though it was not the position the button (or the
    -- keybinding) actually named as next.
    describe("with a Remove armed elsewhere while row 1 is stale", function()
      -- Widget (99001) is quoted and fully evidenced first, so it alone is postable and sorts to
      -- row 1 (SellViewModel.Order ranks a priced position ahead of an unpriced one). A Remove is
      -- armed on ITS OWN manual cost entry -- any armed row would hold the render, this one just
      -- happens to be real -- and only THEN is Eternium Ore quoted too: its far larger value
      -- (246 units against Widget's 5) makes it the queue's new head, but nothing re-renders to
      -- move row 1 off Widget.
      local function armRemoveWithStaleRow1()
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

      it("on retail the dock's POST refuses rather than post row 1's stale item", function()
        passport(120100)
        armRemoveWithStaleRow1()
        local posts = postCounter()
        local button = container.queueButton
        button.scripts.OnClick(button)
        assert.equal(0, posts())
      end)

      it("on retail the POST keybinding refuses rather than post row 1's stale item", function()
        passport(120100)
        armRemoveWithStaleRow1()
        local posts = postCounter()
        root.GoldCapPostNext()
        assert.equal(0, posts())
      end)
    end)

    it("in WoW: Forever the first press only switches into queue mode, and the second posts", function()
      passport(16001)
      local posts = postCounter()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      local button = container.queueButton
      button.scripts.OnClick(button)
      assert.equal(0, posts())
      assert.equal("commodity:23427", GC.SellUI.rows[1].position.positionKey)
      assert.equal("Queue ready — press POST again to post it", root.status.text)
      button.scripts.OnClick(button)
      assert.equal(1, posts())
    end)

    it("in WoW: Forever the POST keybinding takes the same two presses", function()
      passport(16001)
      local posts = postCounter()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      root.GoldCapPostNext()
      assert.equal(0, posts())
      root.GoldCapPostNext()
      assert.equal(1, posts())
    end)

    it("in WoW: Forever one press posts once the queue is already the rendered view", function()
      passport(16001)
      local posts = postCounter()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      compose()
      local button = container.queueButton
      button.scripts.OnClick(button) -- into queue mode, rendered
      assert.equal(0, posts())
      render()
      button.scripts.OnClick(button)
      assert.equal(1, posts())
    end)
  end)
end)
