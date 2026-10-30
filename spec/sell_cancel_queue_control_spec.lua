local helper = require("spec.spec_helper")

-- End to end through the real modules, the same seam spec/sell_post_queue_control_spec.lua
-- proves for posting: owned lots -> positions -> GC.CancelQueue.Build -> the Cancel control ->
-- onRepostClick's own arm/confirm/pin machinery -> C_AuctionHouse.CancelAuction. The control
-- must never grow a second cancel implementation, so the assertions below reach the protected
-- call ONLY through the same handler a row's own Repost button uses.
describe("Sell tab, the cancel queue control", function()
  local GC, root, render, container, cancelCalls

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {}, calls = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint() end
    function v:ClearAllPoints() end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
    -- I2: the real Theme.Button dims text via OnDisable and SetVariant restores full
    -- brightness -- calling SetVariant after Disable() silently wipes the disabled look.
    -- This fake has no such color coupling to assert against (that would just restate the
    -- production code), so it logs call order instead: a caller must invoke SetVariant
    -- BEFORE Enable/Disable in every branch, provably, not just by inspection.
    function v:SetVariant(name) self.variant = name; self.calls[#self.calls + 1] = "SetVariant:" .. name end
    function v:SetScript(n, f) self.scripts[n] = f end
    function v:HookScript(n, f) self.scripts[n] = f end
    function v:Show() self.shown = true end function v:Hide() self.shown = false end
    function v:IsShown() return self.shown end
    function v:Enable() self.enabled = true; self.calls[#self.calls + 1] = "Enable" end
    function v:Disable() self.enabled = false; self.calls[#self.calls + 1] = "Disable" end
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
  -- One live lot: 400 Sanguithorn Tea listed at 2g73s against a market that has moved to
  -- 1g98s -- the undercut-leftover shape the queue exists for. The paid basis (1g/unit,
  -- recorded below) sits far under the relist price, so RepostAdvice says "repost".
  local OWNED = { { auctionID = 77, itemKey = { itemID = 23427 }, quantity = 400,
    unitPrice = 27300, isCommodity = true } }

  before_each(function()
    cancelCalls = 0
    now = 1000
    _G.time = function() return now end
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
    render = GC.SellUI.List.RenderRows
    container = GC.SellUI.container
    -- The cancel queue is the LISTED deck's bulk action and shares its footer slot with the
    -- post queue's, so it is hidden on the post deck the tab opens on. Every test in this file
    -- is about that control, which means the listed deck is where they all belong.
    GC.SellState.filterMode = "listed"
    container:Show()
    GC.Sell.OnOwnedAuctions() -- what stamps the module-local ownedLots from GetOwnedAuctions
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation = nil, nil, nil, nil
  end)

  local function compose()
    GC.SellCompose.Positions()
  end

  local function quotes()
    return GC.SellState.quotes
  end

  local function armedLotRow()
    for _, row in ipairs(GC.SellUI.rows) do
      if row.kind == "lot" and row.lot and row.lot.auctionID == 77 then return row end
    end
    return nil
  end

  it("counts the queue on the button and holds an honest disabled state when it is empty", function()
    compose() -- no quote at all: the lot cannot be judged, nothing enters the queue
    local button = container.cancelButton
    assert.is_false(button.enabled)
    -- Held back for want of a live price -- not "nothing to cancel" (3c task 9).
    assert.equal("NO LIVE PRICE YET", button.label)
    assert.equal("ghost", button.variant)
    -- I2: SetVariant must land before Disable, or Theme.Button's OnDisable dims the text and
    -- the immediately-following SetVariant would have undone it. paintCancelButton's own
    -- "not head" branch logs exactly this pair, back to back (SetLabel isn't instrumented) --
    -- so the last two calls logged by the most recent paint are the ones to check.
    local n = #button.calls
    assert.is_true(n >= 2)
    assert.matches("^SetVariant:", button.calls[n - 1])
    assert.equal("Disable", button.calls[n])

    GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
    compose()
    assert.equal("CANCEL 1", button.label)
    assert.is_true(button.enabled)
    assert.equal("danger", button.variant)
    -- ...and the line beside it names the lot the next click is about.
    assert.matches("Sanguithorn Tea ×400 @ " .. helper.money("2g73s"), container.cancelHeldBack.text, 1, true)
    assert.is_true(container.cancelHeldBack.shown)
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

  -- The owner saw this exact contradiction beside My Lots (2026-09-26): the queue was empty
  -- only because the one live lot was waiting on a fresh quote, and the button called that
  -- "NOTHING TO CANCEL" -- as if there were no lot at all.
  it("says the queue is waiting on live prices, not that there is nothing to cancel", function()
    GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
    now = 1000 + 46 -- past SELL_QUOTE_ACTION_AGE (45s): the quote is no longer fresh
    compose()
    assert.equal("NO LIVE PRICE YET", container.cancelButton.label)
  end)

  it("still says nothing to cancel when every lot is simply fine", function()
    -- Fresh, and the lot sits exactly at market: nothing held back, nothing worth cancelling.
    GC.QuoteCache.Set(quotes(), 23427, 27300, 1000)
    compose()
    assert.equal("NOTHING TO CANCEL", container.cancelButton.label)
  end)

  it("arms the head lot through onRepostClick on the first click -- destroying nothing", function()
    GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
    compose()
    local button = container.cancelButton
    button.scripts.OnClick(button)

    -- The list is now the cancel queue: head position at row 1, force-expanded so the head's
    -- own lot row (the thing onRepostClick pins to) is rendered further down.
    local rows = GC.SellUI.rows
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
    -- Sent is sent: the arm is let go at once rather than held until the client's list
    -- catches up (see "a cancel that was sent" below).
    assert.is_nil(lotRow.repostStage)
    assert.matches("Cancelling", root.status.text, 1, true)
  end)
  -- Seen in game, twice: after the confirming click the tab went dead -- the lot still listed,
  -- its button greyed at "Cancel lot?", no row opening, the panel refusing to shut -- until the
  -- cancel's own 30-second timeout. The tab held every render behind the cancel while it waited
  -- to SEE the lot leave C_AuctionHouse.GetOwnedAuctions(), which is a cache only a new query
  -- refreshes; and whether AUCTION_CANCELED arrives to say so is not something to bet the
  -- whole tab on. Once CancelAuction is sent the pin has done its job: the tab lets go at once,
  -- stops showing the lot, and sorts out what the server said afterwards.
  describe("a cancel that was sent", function()
    local function cancelHead()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose()
      local button = container.cancelButton
      button.scripts.OnClick(button)
      local lotRow = armedLotRow()
      lotRow.repostReady = true
      button.scripts.OnClick(button)
      assert.equal(1, cancelCalls)
      return lotRow
    end

    local function lotShown()
      for _, row in ipairs(GC.SellUI.rows) do
        if row.shown == true and (row.kind == "lot" or row.kind == "position") then return true end
      end
      return false
    end

    it("lets go of the tab at once, and stops showing the lot the client's list still holds", function()
      local lotRow = cancelHead()
      assert.is_nil(lotRow.repostStage)
      assert.matches("Cancelling", root.status.text, 1, true)
      assert.is_false(lotShown())
      assert.matches("NOTHING", container.cancelButton.label)
      -- ...and a list read that still holds lot 77 (the cache is stale) does not bring it back.
      GC.Sell.OnOwnedAuctions()
      assert.is_false(lotShown())
    end)

    it("says so when the server confirms, whether or not the event names the lot", function()
      cancelHead()
      GC.Sell.OnAuctionCanceled(77)
      assert.matches("cancelled", root.status.text, 1, true)
    end)

    it("asks the auction house for the listings again, once, when it can", function()
      local asked = 0
      _G.C_AuctionHouse.QueryOwnedAuctions = function() asked = asked + 1 end
      GC.Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end }
      GC.SellQuotes.driver = { isReady = function() return true end }
      cancelHead()
      GC.Sell.Tick(); GC.Sell.Tick()
      assert.equal(1, asked)
    end)

    it("brings the lot back if nothing confirmed the cancel and a later list still holds it", function()
      cancelHead()
      now = 1000 + 16 -- past the wait for a confirmation
      GC.Sell.OnOwnedAuctions()
      assert.is_true(lotShown())
      assert.matches("did not", root.status.text, 1, true)
    end)

    it("hides nothing on an event for a lot nobody here cancelled", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      GC.Sell.OnAuctionCanceled(nil)
      GC.Sell.OnOwnedAuctions()
      compose()
      assert.equal("CANCEL 1", container.cancelButton.label)
    end)
  end)

  -- The button that was pressed is the one that has to answer. The row's Cancel lot armed the
  -- lot's own button over in the panel and stayed exactly as it was -- "I press it and nothing
  -- happens", with the confirm waiting on a small button a column away.
  describe("the row's own button", function()
    it("asks for the confirming click itself, and goes back when the arm is let go", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose(); render()
      local action
      for _, row in ipairs(GC.SellUI.rows) do
        if row.shown and row.kind == "position" then action = row.action end
      end
      action.scripts.OnClick(action)
      assert.equal("Cancel lot?", action.label)
      assert.is_false(action.enabled) -- until the arm's delay has passed, like the lot's own
      armedLotRow().repostReady = true
      GC.SellUI.Dock.PaintCancelButton()
      assert.is_true(action.enabled)
      action.scripts.OnClick(action)
      assert.equal(1, cancelCalls)
    end)
  end)

  -- An armed cancel is a question, and a click anywhere else is the answer "no". The render
  -- used to stay held for the arm's full twenty seconds: rows would not open, the panel would
  -- not shut, and the tab looked hung.
  describe("walking away from an armed cancel", function()
    it("lets go of the arm when the player clicks a row, and does what the click asked", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose()
      local button = container.cancelButton
      button.scripts.OnClick(button)
      local lotRow = armedLotRow()
      assert.equal("armed", lotRow.repostStage)
      local position
      for _, row in ipairs(GC.SellUI.rows) do
        if row.shown and row.kind == "position" then position = row end
      end
      position.scripts.OnClick(position) -- the open position's own row: shut it
      assert.is_nil(lotRow.repostStage)
      assert.equal(0, cancelCalls)
      for _, row in ipairs(GC.SellUI.rows) do
        assert.is_false(row.shown == true and row.kind == "lot")
      end
    end)
  end)

  -- MY LOTS as the redesign drew it: the deck answers "what do I do with these" in three
  -- sections, a row says how its stock is listed, and the row that is worth cancelling carries
  -- the control for it -- which, like the dock's, only ever hands the click to onRepostClick.
  describe("the deck as designed", function()
    local function shownRows()
      local out = {}
      for _, row in ipairs(GC.SellUI.rows) do
        if row.IsShown and row:IsShown() then out[#out + 1] = row end
      end
      return out
    end

    it("files a lot worth cancelling under UNDERCUT, with its count", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose(); render()
      local rows = shownRows()
      assert.equal("section", rows[1].kind)
      assert.matches("UNDERCUT 1", helper.plain(rows[1].sectionLabel.text), 1, true)
      assert.matches("worth cancelling", rows[1].sectionLabel.text, 1, true)
      assert.equal("position", rows[2].kind)
      assert.equal(2, #rows)
    end)

    it("files a lot nobody has judged yet under HOLDING", function()
      compose(); render() -- no quote: nothing is queued
      local rows = shownRows()
      assert.equal("section", rows[1].kind)
      assert.matches("HOLDING 1", helper.plain(rows[1].sectionLabel.text), 1, true)
      assert.equal("position", rows[2].kind)
    end)

    it("says how the stock is listed: how many, in how many lots", function()
      compose(); render()
      assert.matches("400 in 1 lot", shownRows()[2].itemStock.text, 1, true)
    end)

    it("puts Cancel lot on the row that is worth cancelling, and nothing on one that is not", function()
      compose(); render()
      assert.is_false(shownRows()[2].action.shown)
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose(); render()
      local action = shownRows()[2].action
      assert.is_true(action.shown)
      assert.equal("Cancel lot", action.label)
      assert.equal("Cancel lot", action.helpKey)
    end)

    it("arms the lot through onRepostClick from the row's button -- destroying nothing", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose(); render()
      local action = shownRows()[2].action
      action.scripts.OnClick(action)
      local lotRow = armedLotRow()
      assert.is_table(lotRow)
      assert.equal("armed", lotRow.repostStage)
      assert.equal("Cancel lot?", lotRow.action.label)
      assert.equal(0, cancelCalls)
      -- The deck stays the deck: the row's own button does not turn the list into the queue.
      assert.equal("section", shownRows()[1].kind)
    end)

    it("opens the panel on the lots themselves: YOUR LOTS first, each with its own Cancel lot", function()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose(); render()
      local position = shownRows()[2]
      position.scripts.OnClick(position)
      local kinds = {}
      for _, row in ipairs(shownRows()) do if row.inPanel then kinds[#kinds + 1] = row.kind end end
      assert.equal("group", kinds[1])
      assert.equal("lot", kinds[2])
      assert.equal("drawer", kinds[3])
      local head, lot
      for _, row in ipairs(shownRows()) do
        if row.inPanel and row.kind == "group" and not head then head = row end
        if row.inPanel and row.kind == "lot" then lot = row end
      end
      assert.is_true(position.selectRing.shown) -- the open row wears the design's gold outline
      assert.equal("YOUR LOTS", head.sectionLabel.text)
      assert.matches("1 lot", head.sectionHint.text, 1, true)
      assert.equal("Cancel lot", lot.action.label)
    end)
  end)
  -- The cancel run (plan 2026-10-22, task 13), retail only: the first press arms the whole queue
  -- and says how many lots and what deposits they forfeit, the confirm a second later cancels the
  -- head, and every press after it cancels the next lot, each through onRepostClick, one
  -- CancelAuction per press. Without Core/CancelRun.lua (Forever) every case above is the control.
  describe("the cancel run", function()
    local LOTS = {
      { auctionID = 77, itemKey = { itemID = 23427 }, quantity = 100, unitPrice = 27300, isCommodity = true },
      { auctionID = 78, itemKey = { itemID = 23427 }, quantity = 100, unitPrice = 27300, isCommodity = true },
      { auctionID = 79, itemKey = { itemID = 23427 }, quantity = 100, unitPrice = 27300, isCommodity = true },
    }
    local COSTS = { [77] = 100, [78] = 150, [79] = 100 }
    local cancelled

    before_each(function()
      cancelled = {}
      -- The client's two clocks: GetTime in fractions of a second, time() in whole seconds.
      _G.GetTime = function() return now end
      _G.time = function() return math.floor(now) end
      _G.C_AuctionHouse.GetOwnedAuctions = function() return LOTS end
      _G.C_AuctionHouse.GetCancelCost = function(auctionID) return COSTS[auctionID] end
      _G.C_AuctionHouse.CancelAuction = function(auctionID)
        cancelCalls = cancelCalls + 1
        cancelled[#cancelled + 1] = auctionID
      end
      helper.loadModule("Core/CancelRun.lua", GC)
      GC.Sell.OnOwnedAuctions()
      GC.QuoteCache.Set(quotes(), 23427, 19800, 1000)
      compose()
    end)

    after_each(function()
      _G.GetTime, _G.C_Timer = nil, nil
    end)

    local function press(at)
      now = at
      local head = GC.SellState.cancelEntries[1]
      local button = container.cancelButton
      button.scripts.OnClick(button)
      return head and head.auctionID
    end

    it("confirms the whole queue once, then cancels one lot per press", function()
      assert.equal(3, #GC.SellState.cancelEntries)
      press(1000)
      assert.equal(0, cancelCalls)
      local status = root.status.text
      assert.matches("3", status, 1, true)
      assert.matches(GC.Util.Money(350), status, 1, true)
      assert.equal("CONFIRM", container.cancelButton.label)

      local first = press(1001.2)
      assert.same({ first }, cancelled)
      assert.equal("CANCEL NEXT (2)", container.cancelButton.label)
      assert.is_true(container.cancelButton.enabled)

      local second = press(1003)
      assert.are_not.equal(first, second)
      assert.same({ first, second }, cancelled)
      assert.equal("CANCEL NEXT (1)", container.cancelButton.label)
    end)

    it("counts a confirm only after its second", function()
      press(1000)
      assert.is_false(container.cancelButton.enabled)
      press(1000.5)
      assert.equal(0, cancelCalls)
      assert.equal("armed", GC.SellState.cancelRun.stage)
      press(1001.5)
      assert.equal(1, cancelCalls)
    end)

    it("says the deposits only when the client can tell every one", function()
      COSTS[78] = nil
      press(1000)
      COSTS[78] = 150
      assert.matches("3", root.status.text, 1, true)
      assert.is_nil(root.status.text:find(GC.Util.Money(200), 1, true))
      assert.equal(GC.L["Cancel %d lots? One press per lot, CONFIRM first."]:format(3), root.status.text)
    end)

    -- One lot is one lot, not "1 lots", and its CONFIRM is the only press it needs.
    it("asks about a single lot in the singular", function()
      _G.C_AuctionHouse.GetOwnedAuctions = function() return { LOTS[1] } end
      GC.Sell.OnOwnedAuctions()
      compose()
      assert.equal(1, #GC.SellState.cancelEntries)
      press(1000)
      assert.equal(GC.L["Cancel 1 lot? You lose its %s deposit. Press CONFIRM."]:format(GC.Util.Money(100)), root.status.text)
      press(1021.5)
      COSTS[77] = nil
      press(1043)
      COSTS[77] = 100
      assert.equal(GC.L["Cancel 1 lot? Press CONFIRM."], root.status.text)
      assert.equal(0, cancelCalls)
    end)

    it("stops after twenty seconds without a press, and the next press arms again", function()
      press(1000)
      press(1001.2)
      assert.equal(1, cancelCalls)
      press(1001.2 + 21)
      assert.equal(1, cancelCalls)
      assert.equal("armed", GC.SellState.cancelRun.stage)
      assert.equal("CONFIRM", container.cancelButton.label)
      assert.matches(GC.Util.Money(250), root.status.text, 1, true)
    end)

    it("comes alive after its second, and lets go after twenty idle seconds", function()
      local timers = {}
      _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
      local function fire(at)
        now = at
        local due = {}
        for i = #timers, 1, -1 do
          if timers[i].at <= at then due[#due + 1] = table.remove(timers, i) end
        end
        for i = #due, 1, -1 do due[i].fn() end
      end
      press(1000)
      assert.is_false(container.cancelButton.enabled)
      fire(1001)
      assert.is_true(container.cancelButton.enabled)
      press(1005)
      assert.equal(1, cancelCalls)
      -- Twenty seconds after the arm, but only fifteen after the last press: still running.
      fire(1020.2)
      assert.equal("running", GC.SellState.cancelRun.stage)
      fire(1025.2)
      assert.is_nil(GC.SellState.cancelRun)
      assert.equal("Stopped: 20 seconds without a press", root.status.text)
      assert.equal("CANCEL 2", container.cancelButton.label)
    end)

    it("comes alive when its timer fires, even on a frame a hair under the second", function()
      local timers = {}
      _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
      press(1000)
      assert.is_false(container.cancelButton.enabled)
      -- The arm's one-second timer, run on a frame whose clock reads just under it.
      now = 1000.9998
      for _, timer in ipairs(timers) do if timer.at <= 1001 then timer.fn() end end
      assert.is_true(container.cancelButton.enabled)
      press(1000.9999)
      assert.equal(1, cancelCalls)
    end)

    -- Retail sizes the button to its widest word in the player's language. A queue of a hundred
    -- lots or more is three figures, one wider than "99" measured.
    it("sizes the button for a count of three figures", function()
      local fitted = {}
      GC.Theme.OnRescale = function() end
      local plain = GC.Theme.Button
      GC.Theme.Button = function(...)
        local button = plain(...)
        function button:FitLabels(labels) fitted[#fitted + 1] = labels end
        return button
      end
      local again = region("Frame")
      again.HookScript = function(_, n, f) again.scripts[n] = f end
      again.status = region("FontString", again)
      GC.Sell.Attach(again, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
        rowWidth = 1100, rowHeight = 24 })
      GC.Theme.Button, GC.Theme.OnRescale = plain, nil
      local cancelLabels
      for _, labels in ipairs(fitted) do
        for _, label in ipairs(labels) do
          if label == GC.L["NOTHING TO CANCEL"] then cancelLabels = labels end
        end
      end
      assert.is_table(cancelLabels)
      local has = {}
      for _, label in ipairs(cancelLabels) do has[label] = true end
      assert.is_true(has[(GC.L["CANCEL %d"]):format(999)])
      assert.is_true(has[(GC.L["CANCEL NEXT (%d)"]):format(999)])
    end)

    it("ends the run once the queue is empty", function()
      press(1000)
      press(1001.2); press(1002); press(1003)
      assert.equal(3, cancelCalls)
      assert.equal(0, #GC.SellState.cancelEntries)
      -- The press that cancelled the last lot ends it: a lot that joins the queue later is armed
      -- and confirmed like any other.
      assert.is_nil(GC.SellState.cancelRun)
      press(1004)
      assert.equal(3, cancelCalls)
      assert.is_nil(GC.SellState.cancelRun)
    end)

    it("says nothing about an idle run after the run cancelled every lot", function()
      local timers = {}
      _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
      press(1000)
      press(1001.2); press(1002); press(1003)
      assert.equal(3, cancelCalls)
      root.status.text = "Lot cancelled; wait for it to return to bags"
      -- Every timer due by then, once: the run's own watcher among them.
      now = 1040
      local due = {}
      for _, timer in ipairs(timers) do if timer.at <= now then due[#due + 1] = timer end end
      for _, timer in ipairs(due) do timer.fn() end
      assert.equal("Lot cancelled; wait for it to return to bags", root.status.text)
    end)

    -- A lot that reaches the head after the confirm was not in its count or its deposits: the
    -- next press arms again, with the count and the total as they are now, and cancels nothing.
    it("asks again for a lot that joined the queue after the confirm", function()
      local live = { LOTS[1], LOTS[2], LOTS[3] }
      _G.C_AuctionHouse.GetOwnedAuctions = function() return live end
      COSTS[80] = 300
      press(1000)
      local first = press(1001.2)
      assert.same({ first }, cancelled)
      -- A bigger lot of the same tea comes up for cancelling, and heads the queue.
      live[#live + 1] = { auctionID = 80, itemKey = { itemID = 23427 }, quantity = 150, unitPrice = 27300,
        isCommodity = true }
      GC.Sell.OnOwnedAuctions()
      assert.equal(80, GC.SellState.cancelEntries[1].auctionID)
      assert.equal("CANCEL 3", container.cancelButton.label)
      assert.is_true(container.cancelButton.enabled)
      press(1002)
      COSTS[80] = nil
      assert.same({ first }, cancelled)
      assert.equal("armed", GC.SellState.cancelRun.stage)
      assert.equal("CONFIRM", container.cancelButton.label)
      assert.matches(GC.Util.Money(150 + 100 + 300), root.status.text, 1, true)
      press(1003.2)
      assert.same({ first, 80 }, cancelled)
    end)

    -- A lot's own Cancel lot, armed and waiting for its second click, holds every render and
    -- painted the dock's button as its own. Arming the queue answers it "no", as a click on a row
    -- does, so the queue's CONFIRM is the button's and the head's row is on screen for it.
    it("lets go of a lot's own armed Cancel lot when it arms the queue", function()
      GC.SellState.filterMode = "cancelqueue"
      GC.SellUI.ROW.armLot(GC.SellState.cancelEntries[1])
      assert.equal("armed", GC.SellState.repostingRow.repostStage)
      press(1000)
      assert.is_nil(GC.SellState.repostingRow)
      assert.equal("armed", GC.SellState.cancelRun.stage)
      assert.equal("CONFIRM", container.cancelButton.label)
      press(1001.2)
      assert.equal(1, cancelCalls)
      assert.equal("CANCEL NEXT (2)", container.cancelButton.label)
    end)

    it("counts down only the lots the confirm showed", function()
      local live = { LOTS[1], LOTS[2], LOTS[3] }
      _G.C_AuctionHouse.GetOwnedAuctions = function() return live end
      press(1000)
      press(1001.2)
      assert.equal("CANCEL NEXT (2)", container.cancelButton.label)
      -- A smaller lot joins at the back of the queue: two of the three left are the run's.
      live[#live + 1] = { auctionID = 81, itemKey = { itemID = 23427 }, quantity = 10, unitPrice = 27300,
        isCommodity = true }
      GC.Sell.OnOwnedAuctions()
      assert.equal(3, #GC.SellState.cancelEntries)
      assert.equal(81, GC.SellState.cancelEntries[3].auctionID)
      assert.equal("CANCEL NEXT (2)", container.cancelButton.label)
    end)
  end)
end)
