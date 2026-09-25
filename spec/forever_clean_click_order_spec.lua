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

    it("recomposes positions without repainting the deck switch before CancelAuction", function()
      local composeAt = assert(click:find("composePositions(true)", 1, true),
        "onRepostClick must skip composePositions' own paint before its protected call")
      local callAt = assert(click:find("C_AuctionHouse.CancelAuction(plan.auctionID)", composeAt, true))
      local between = click:sub(composeAt, callAt - 1)
      assert.is_nil(between:find("paintDeckSwitch()", 1, true),
        "paintDeckSwitch must not run between the recompose and the protected Cancel call")
      local paintAt = assert(click:find("paintDeckSwitch()", callAt, true),
        "the deck switch must still be repainted after the call")
      assert.is_true(paintAt > callAt)
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

  describe("SniperFrame.lua buy dialog (onDialogPrimaryClick)", function()
    local text = source("GoldCap/UI/SniperFrame.lua")
    local clickStart = assert(text:find("local function onDialogPrimaryClick()", 1, true))
    local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
    local click = text:sub(clickStart, clickEndStop)

    it("never calls refreshQtyRow on the path that reaches StartCommoditiesPurchase", function()
      -- Anchored at "row.purchaseDeal = purchaseDeal" (commodity branch), not the earlier
      -- "buying" arm: the claim-refused bail just above it also calls refreshQtyRow(), on a
      -- path that returns without ever reaching the protected call -- see the BuyFrame.lua
      -- test below for why a bail branch's own paint is not a taint risk regardless.
      local armAt = assert(click:find("row.purchaseDeal = purchaseDeal", 1, true))
      local callAt = assert(click:find(
        "C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)", armAt, true))
      local between = click:sub(armAt, callAt - 1)
      assert.is_nil(between:find("refreshQtyRow()", 1, true),
        "refreshQtyRow must not run on the path from the claim succeeding to StartCommoditiesPurchase")
      local afterAt = assert(click:find("refreshQtyRow()", callAt, true),
        "the box/quick-fill must still be repainted after Start fires")
      assert.is_true(afterAt > callAt)
    end)

    it("never calls refreshQtyRow between building the bid copy and PlaceBid", function()
      local armAt = assert(click:find("pendingAuction[purchaseDeal.auctionID] = row", 1, true))
      local callAt = assert(click:find("C_AuctionHouse.PlaceBid(candidate.auctionID, candidate.buyout)", armAt, true))
      local between = click:sub(armAt, callAt - 1)
      assert.is_nil(between:find("refreshQtyRow()", 1, true),
        "refreshQtyRow must not run between building the bid copy and PlaceBid")
      local afterAt = assert(click:find("refreshQtyRow()", callAt, true),
        "the box/quick-fill must still be repainted after PlaceBid fires")
      assert.is_true(afterAt > callAt)
    end)

    it("keeps ConfirmCommoditiesPurchase's own bookkeeping (setDialogStatus, refreshQtyRow) after the call", function()
      -- The Confirm branch was already clean before this fix; pinned here so a future edit
      -- cannot quietly reintroduce a pre-call paint the way the Start/PlaceBid branch had one.
      local confirmCallAt = assert(click:find(
        "C_AuctionHouse.ConfirmCommoditiesPurchase(quoteSnapshot.itemID, quoteSnapshot.quantity)", 1, true))
      local statusAt = assert(click:find("setDialogStatus(GC.L[\"confirming purchase...\"])", confirmCallAt, true))
      assert.is_true(statusAt > confirmCallAt)
    end)
  end)

  describe("BuyFrame.lua onBuyClick", function()
    local text = source("GoldCap/UI/BuyFrame.lua")
    local clickStart = assert(text:find("local function onBuyClick(line)", 1, true))
    local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
    local click = text:sub(clickStart, clickEndStop)

    it("was already clean: no paint/status helper runs between arming and either protected call", function()
      local confirmArm = assert(click:find('attempt.stage = "confirming"', 1, true))
      local confirmCall = assert(click:find(
        "C_AuctionHouse.ConfirmCommoditiesPurchase(attempt.itemID, attempt.qty)", confirmArm, true))
      assert.is_nil(click:sub(confirmArm, confirmCall - 1):find("logAttempt(", 1, true))

      local startArm = assert(click:find('attempt.stage = "started"', 1, true))
      local startCall = assert(click:find(
        "C_AuctionHouse.StartCommoditiesPurchase(attempt.itemID, attempt.qty)", startArm, true))
      assert.is_nil(click:sub(startArm, startCall - 1):find("logAttempt(", 1, true))

      -- afterClick/armStall -- the bookkeeping -- run only after each call.
      local afterConfirm = assert(click:find("afterClick(line)", confirmCall, true))
      assert.is_true(afterConfirm > confirmCall)
      local afterStart = assert(click:find("afterClick(line)", startCall, true))
      assert.is_true(afterStart > startCall)
    end)
  end)
end)
