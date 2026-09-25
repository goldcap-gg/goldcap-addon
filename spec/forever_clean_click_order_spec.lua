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

    it("onDialogPrimaryClick (Sniper Start/Confirm/PlaceBid)", function()
      local text = source("GoldCap/UI/SniperFrame.lua")
      local clickStart = assert(text:find("local function onDialogPrimaryClick()", 1, true))
      local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
      assertClean(text:sub(clickStart, clickEndStop), "onDialogPrimaryClick")
    end)

    it("onBuyClick (BUY tab)", function()
      local text = source("GoldCap/UI/BuyFrame.lua")
      local clickStart = assert(text:find("local function onBuyClick(line)", 1, true))
      local _, clickEndStop = assert(text:find("\nend\n", clickStart, true))
      assertClean(text:sub(clickStart, clickEndStop), "onBuyClick")
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
