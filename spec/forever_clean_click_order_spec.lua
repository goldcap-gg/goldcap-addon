local helper = require("spec.spec_helper")
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
    local prepare = helper.functionBody(helper.sellSource(), "function Post.PreparePost(row)")
    local click = helper.functionBody(text, "local function onPostClick(row)")
    local QUIET = { "_NotePost(", "notePost(", ":Disable(", ":SetLabel(", "SetBusy(" }
    -- Each arm is anchored on the statement itself (the line it ends): the comment above it
    -- quotes the same assignment and then names the busy look's calls it moved after the call.

    -- schedulePostTimeout is what recovers the row if the protected call itself raises an
    -- error and aborts the handler -- it has to stay BEFORE the call, unlike _NotePost. It
    -- only calls C_Timer.After, which registers a callback rather than reading anything
    -- GoldCap-owned synchronously, so it carries none of _NotePost's taint risk.
    it("arms the confirming stage and its recovery timeout, then hands the Confirm to the click", function()
      local armAt = assert(prepare:find('row.postStage = "confirming"\n', 1, true))
      local timeoutAt = assert(prepare:find("schedulePostTimeout(row)", armAt, true))
      local handAt = assert(prepare:find("return { confirm = true, pin = pin }", timeoutAt, true))
      local between = prepare:sub(armAt, handAt - 1)
      for _, banned in ipairs(QUIET) do
        assert.is_nil(between:find(banned, 1, true), banned .. " must not run between arming \"confirming\" and the Confirm call")
      end
    end)

    it("arms the posting stage and its recovery timeout, then hands the post to the click", function()
      local armAt = assert(prepare:find('row.postStage = "posting"\n', 1, true))
      local timeoutAt = assert(prepare:find("schedulePostTimeout(row)", armAt, true))
      local handAt = assert(prepare:find("return { pin = S.postingPin }", timeoutAt, true))
      local between = prepare:sub(armAt, handAt - 1)
      for _, banned in ipairs(QUIET) do
        assert.is_nil(between:find(banned, 1, true), banned .. " must not run between arming \"posting\" and the Post call")
      end
    end)

    it("makes the protected call before anything else and notes \"Posting…\" after it", function()
      local confirmAt = assert(click:find("C_AuctionHouse.ConfirmPostCommodity(pin.location", 1, true))
      local postAt = assert(click:find(
        "C_AuctionHouse.PostCommodity(pin.location, pin.duration, pin.quantity, pin.unitPrice)", 1, true))
      assert.is_true(assert(click:find("_NotePost(", confirmAt, true)) > confirmAt)
      assert.is_true(assert(click:find("_NotePost(", postAt, true)) > postAt)
      local before = click:sub(1, math.min(confirmAt, postAt) - 1)
      for _, banned in ipairs({ "_NotePost(", ":Disable(", ":SetLabel(", "SetBusy(", "setStatus(", "renderRows(",
          "composePositions(", "Compose.Positions(" }) do
        assert.is_nil(before:find(banned, 1, true), banned .. " must not run in the click before its protected call")
      end
    end)
  end)

  describe("SellFrame.lua Cancel lot (onRepostClick)", function()
    local text = source("GoldCap/UI/SellFrame.lua")
    local prepare = helper.functionBody(helper.sellSource(), "function Post.PrepareCancel(row, auctionID)")
    local click = helper.functionBody(text, "local function onRepostClick(row, auctionID)")

    -- The armed lot is validated against a fresh, plain GetOwnedAuctions/NormalizeOwnedLots
    -- read, never against a recompose: composePositions() runs scanBagStock(), and bag stock
    -- plays no part in whether a lot can be cancelled (final review C2). The full recompose,
    -- with its paints, moves to after the call.
    it("reads the owned-auctions list fresh but never recomposes positions before CancelAuction", function()
      assert.is_truthy(prepare:find("GC.SellPositions.NormalizeOwnedLots(", 1, true),
        "Post.PrepareCancel must refresh the owned-auctions list before the protected call")
      -- Read without its comment lines: the one above the fresh read names composePositions() as
      -- what this click no longer calls. Whole lines only, so a `--` inside a string can hide nothing.
      local code = prepare:gsub("\n[ \t]*%-%-[^\n]*", "")
      for _, banned in ipairs({ "composePositions(", "Compose.Positions(" }) do
        assert.is_nil(code:find(banned, 1, true), banned .. " must not run before the protected Cancel call -- it scans the bags")
      end
      local callAt = assert(click:find("C_AuctionHouse.CancelAuction(pin.auctionID)", 1, true))
      local before = click:sub(1, callAt - 1)
      for _, banned in ipairs({ ":Disable(", ":SetLabel(", "setStatus(", "renderRows(", "composePositions(",
          "Compose.Positions(" }) do
        assert.is_nil(before:find(banned, 1, true), banned .. " must not run in the click before CancelAuction")
      end
      local afterAt = assert(click:find("Post.Cancelling(row, pin, scope)", callAt, true),
        "positions must still be recomposed, with their paints, after the call")
      assert.is_true(afterAt > callAt)
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

    it("onPostClick, onRepostClick and the Prepare functions they call", function()
      local text, all = source("GoldCap/UI/SellFrame.lua"), helper.sellSource()
      assertClean(helper.functionBody(text, "local function onPostClick(row)"), "onPostClick")
      assertClean(helper.functionBody(text, "local function onRepostClick(row, auctionID)"), "onRepostClick")
      assertClean(helper.functionBody(all, "function Post.PreparePost(row)"), "Post.PreparePost")
      assertClean(helper.functionBody(all, "function Post.PrepareCancel(row, auctionID)"), "Post.PrepareCancel")
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
      local click = helper.functionBody(helper.sellSource(), "function Post.PreparePost(row)")
      assert.is_truthy(click:find("Bags.ResolveLocation(position)", 1, true),
        "onPostClick must resolve its location through the paint-time cache")
      assert.is_truthy(click:find("Bags.ClickSafe(", 1, true),
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
