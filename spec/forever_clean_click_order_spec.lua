-- WoW: Forever's taint engine blocks a protected AH call once the same hardware click has
-- already read certain GoldCap runtime state -- observed in the beta as a click that starts
-- clean but taints partway through, on a read that happens well before the protected call
-- itself (see docs/superpowers/sdd/2026-09-24-forever-addon-3a/post-taint-analysis.md and
-- clean-click-report.md). The confirmed culprits so far:
--   * GC.Sell._NotePost -> setStatus -> paintRefreshButton -> refresh.deckProgress()
--     (SellFrame.lua, refresh is a plain module-local table -- see paintRefreshButton's own
--     comment for why reading and calling that particular field is what trips it).
--   * composePositions()'s own trailing container.paintDeckSwitch() call, which reads
--     position.listedQty/bagQty off `positions`.
--   * SniperFrame's refreshQtyRow(), which reads dialog.bookLevels and calls
--     GC.Sniper._RowCap -- the buy dialog's own analogue of paintRefreshButton.
-- Retail behaviour must not change: this file pins ORDER only -- the protected call must run
-- before any of these, in every click that reaches one. busted cannot see WoW's taint system
-- directly (spec/spec_helper.lua's fixtures carry no such thing), so this is a source-text
-- guard, the same idiom spec/sell_post_wiring_spec.lua and spec/sniper_purchase_wiring_spec.lua
-- already use for the safety-critical wiring around these exact calls.
describe("Clean click ordering (WoW: Forever taint fix)", function()
  local function source(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  describe("SellFrame.lua Post", function()
    local text = source("GoldCap/UI/SellFrame.lua")
    local clickStart = assert(text:find("local function onPostClick(row)", 1, true))
    local clickEnd = assert(text:find("local function onRepostClick(row, auctionID)", clickStart, true))
    local click = text:sub(clickStart, clickEnd - 1)

    it("arms the confirming stage but never notes it before ConfirmPostCommodity/ConfirmPostItem", function()
      local armAt = assert(click:find('row.postStage = "confirming"', 1, true))
      local callAt = assert(click:find("C_AuctionHouse.ConfirmPostCommodity(pin.location", armAt, true))
      local between = click:sub(armAt, callAt - 1)
      assert.is_nil(between:find("_NotePost(", 1, true),
        "_NotePost must not run between arming \"confirming\" and the protected Confirm call")
      local noteAt = assert(click:find("_NotePost(", callAt, true),
        "the Confirm branch must still note \"Posting…\" after the call")
      assert.is_true(noteAt > callAt)
    end)

    it("arms the posting stage but never notes it before PostCommodity/PostItem", function()
      local armAt = assert(click:find('row.postStage = "posting"', 1, true))
      local callAt = assert(click:find(
        "C_AuctionHouse.PostCommodity(location, duration, plan.quantity, plan.unitPrice)", armAt, true))
      local between = click:sub(armAt, callAt - 1)
      assert.is_nil(between:find("_NotePost(", 1, true),
        "_NotePost must not run between arming \"posting\" and the protected Post call")
      local noteAt = assert(click:find("_NotePost(", callAt, true),
        "the first click must still note \"Posting…\" after the call")
      assert.is_true(noteAt > callAt)
    end)

    it("still arms the recovery timeout before the call (C_Timer.After only registers a callback)", function()
      -- schedulePostTimeout is what recovers the row if the protected call itself raises an
      -- error and aborts the handler -- it has to stay BEFORE the call, unlike _NotePost. It
      -- only calls C_Timer.After, which registers a callback rather than reading anything
      -- GoldCap-owned synchronously, so it carries none of _NotePost's taint risk.
      local confirmArm = assert(click:find('row.postStage = "confirming"', 1, true))
      local confirmCall = assert(click:find("C_AuctionHouse.ConfirmPostCommodity(pin.location", confirmArm, true))
      local confirmTimeout = assert(click:find("schedulePostTimeout(row)", confirmArm, true))
      assert.is_true(confirmTimeout < confirmCall)

      local postArm = assert(click:find('row.postStage = "posting"', confirmCall, true))
      local postCall = assert(click:find(
        "C_AuctionHouse.PostCommodity(location, duration, plan.quantity, plan.unitPrice)", postArm, true))
      local postTimeout = assert(click:find("schedulePostTimeout(row)", postArm, true))
      assert.is_true(postTimeout < postCall)
    end)
  end)

  describe("SellFrame.lua Cancel lot (onRepostClick)", function()
    local text = source("GoldCap/UI/SellFrame.lua")
    local clickStart = assert(text:find("local function onRepostClick(row, auctionID)", 1, true))
    local clickEnd = assert(text:find("function GC.Sell.OnAuctionCreated(", clickStart, true))
    local click = text:sub(clickStart, clickEnd - 1)

    -- The armed lot is validated against a fresh, plain GetOwnedAuctions/NormalizeOwnedLots
    -- read, never against a recompose: composePositions() runs scanBagStock(), and bag stock
    -- plays no part in whether a lot can be cancelled (final review C2). The full recompose,
    -- with its paints, moves to after the call.
    it("reads the owned-auctions list fresh but never recomposes positions before CancelAuction", function()
      local ownedAt = assert(click:find("GC.SellPositions.NormalizeOwnedLots(", 1, true),
        "onRepostClick must refresh the owned-auctions list before its protected call")
      local callAt = assert(click:find("C_AuctionHouse.CancelAuction(pin.auctionID)", ownedAt, true))
      local between = click:sub(ownedAt, callAt - 1)
      assert.is_nil(between:find("composePositions(", 1, true),
        "composePositions must not run before the protected Cancel call -- it scans the bags")
      local composeAt = assert(click:find("composePositions()", callAt, true),
        "positions must still be recomposed, with their paints, after the call")
      assert.is_true(composeAt > callAt)
    end)
  end)

  describe("SellFrame.lua composePositions", function()
    it("only repaints the deck switch by default; the caller can skip it", function()
      local text = source("GoldCap/UI/SellFrame.lua")
      local defAt = assert(text:find("local function composePositions(skipPaint)", 1, true))
      local endAt = assert(text:find("\nend\n", defAt, true))
      local body = text:sub(defAt, endAt)
      assert.is_truthy(body:find("if not skipPaint and container and container.paintDeckSwitch then", 1, true))
    end)
  end)

  -- The Deals buy window and the BUY tab no longer depend on this ordering: their plans run
  -- inside securecallfunction (GC.PurchaseCall.Click, Core/PurchaseCall.lua), so nothing they
  -- read reaches the protected call's execution -- spec/forever_taint_flow_spec.lua's "every
  -- field GoldCap wrote tainted" proves it on the model. The bookkeeping still runs after the
  -- call: each plan hands it back as the closure GC.PurchaseCall.Click runs once the call is made.
  describe("SniperFrame.lua buy dialog (planDialogPrimaryClick)", function()
    local text = source("GoldCap/UI/SniperFrame.lua")
    local clickStart = assert(text:find("local function planDialogPrimaryClick()", 1, true))
    local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
    local click = text:sub(clickStart, clickEndStop)

    it("repaints the quantity row and says what it sent only after Start or PlaceBid", function()
      local armAt = assert(click:find("row.purchaseDeal = purchaseDeal", 1, true))
      local answerAt = assert(click:find("return call, first, second, function()", armAt, true))
      assert.is_nil(click:sub(armAt, answerAt - 1):find("refreshQtyRow()", 1, true),
        "refreshQtyRow must not run between the claim succeeding and the answer")
      local after = click:sub(answerAt)
      assert.is_truthy(after:find("if refreshQtyRow then refreshQtyRow() end", 1, true))
      assert.is_truthy(after:find("setDialogStatus(sent)", 1, true))
      assert.is_truthy(after:find("scheduleBuyTimeout(row, purchaseDeal, token)", 1, true))
    end)

    it("keeps ConfirmCommoditiesPurchase's own bookkeeping (setDialogStatus, refreshQtyRow) after the call", function()
      local answerAt = assert(click:find(
        'return "confirm", quoteSnapshot.itemID, quoteSnapshot.quantity, function()', 1, true))
      local confirmedAt = assert(click:find("pending.confirmed = true", answerAt, true))
      local statusAt = assert(click:find("setDialogStatus(GC.L[\"confirming purchase...\"])", answerAt, true))
      assert.is_true(confirmedAt > answerAt and statusAt > answerAt)
    end)
  end)

  -- Fresh beta evidence (itemlocation-fix-report.md): the block moved on, from GoldCap's own
  -- paint/status reads to Blizzard's own ItemLocation mixin code -- ItemLocation:CreateFromBagAndSlot,
  -- called from onPostClick, tainted execution for the rest of that click even though its own
  -- arguments were clean locals. Any Blizzard Lua/mixin call reached from inside a click -- not
  -- just GoldCap's own tables -- risks the same block, so every protected-call click handler is
  -- pinned source-text clean of the whole family: ItemLocation's own methods, Item:CreateFrom*,
  -- ContinuableContainer and CreateFromMixins. A location built at paint time (SellFrame.lua's
  -- cacheBagLocation, above liveBagState) and only read, never rebuilt, in the click is the fix --
  -- see spec/sell_action_safety_spec.lua's "[Forever]" tests for the behavioural half of it.
  describe("No Blizzard mixin/location code inside a protected-call click handler", function()
    local BANNED = {
      "ItemLocation:", "ItemLocation.CreateFromBagAndSlot", "ItemLocation.CreateFromItemID",
      ":CreateFromBagAndSlot(", ":CreateFromItemID(", "Item:CreateFrom", "ContinuableContainer",
      "CreateFromMixins",
    }

    local function assertClean(click, label)
      for _, pattern in ipairs(BANNED) do
        assert.is_nil(click:find(pattern, 1, true),
          label .. " must not run " .. pattern .. " -- Blizzard Lua/mixin code -- before its protected call")
      end
    end

    it("onPostClick (Post/Confirm)", function()
      local text = source("GoldCap/UI/SellFrame.lua")
      local clickStart = assert(text:find("local function onPostClick(row)", 1, true))
      local clickEnd = assert(text:find("local function onRepostClick(row, auctionID)", clickStart, true))
      assertClean(text:sub(clickStart, clickEnd - 1), "onPostClick")
    end)

    it("onRepostClick (Cancel lot)", function()
      local text = source("GoldCap/UI/SellFrame.lua")
      local clickStart = assert(text:find("local function onRepostClick(row, auctionID)", 1, true))
      local clickEnd = assert(text:find("function GC.Sell.OnAuctionCreated(", clickStart, true))
      assertClean(text:sub(clickStart, clickEnd - 1), "onRepostClick")
    end)

    it("planDialogPrimaryClick (Sniper Start/Confirm/PlaceBid)", function()
      local text = source("GoldCap/UI/SniperFrame.lua")
      local clickStart = assert(text:find("local function planDialogPrimaryClick()", 1, true))
      local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
      assertClean(text:sub(clickStart, clickEndStop), "planDialogPrimaryClick")
    end)

    it("planBuyClick (BUY tab)", function()
      local text = source("GoldCap/UI/BuyFrame.lua")
      local clickStart = assert(text:find("local function planBuyClick(line, fromDock)", 1, true))
      local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
      assertClean(text:sub(clickStart, clickEndStop), "planBuyClick")
    end)

    it("onPostClick resolves its location from the paint-time cache, never builds one itself", function()
      local text = source("GoldCap/UI/SellFrame.lua")
      local clickStart = assert(text:find("local function onPostClick(row)", 1, true))
      local clickEnd = assert(text:find("local function onRepostClick(row, auctionID)", clickStart, true))
      local click = text:sub(clickStart, clickEnd - 1)
      assert.is_truthy(click:find("resolvePostLocation(position)", 1, true),
        "onPostClick must resolve its location through the paint-time cache")
      assert.is_truthy(click:find("clickSafeBagState(", 1, true),
        "onPostClick must read bag state through the click-safe wrapper, not liveBagState directly")
    end)
  end)

  describe("BuyFrame.lua planBuyClick", function()
    local text = source("GoldCap/UI/BuyFrame.lua")
    local clickStart = assert(text:find("local function planBuyClick(line, fromDock)", 1, true))
    local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
    local click = text:sub(clickStart, clickEndStop)

    it("runs armStall and afterClick only once the call has been made", function()
      for _, answer in ipairs({ 'return "confirm", attempt.itemID, attempt.qty, function()',
                                'return "start", attempt.itemID, attempt.qty, function()',
                                'return "bid", lot.auctionID, lot.buyout, function()' }) do
        local answerAt = assert(click:find(answer, 1, true), answer)
        local arm = click:sub(1, answerAt - 1):match('.*()attempt%.stage = "')
        assert.is_nil(click:sub(arm, answerAt - 1):find("logAttempt(", 1, true))
        local afterAt = assert(click:find("afterClick(line)", answerAt, true))
        assert.is_true(afterAt > answerAt)
      end
    end)
  end)
end)
