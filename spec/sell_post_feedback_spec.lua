local helper = require("spec.spec_helper")

-- The owner, in game (2026-09-23): "I press Post and cannot tell whether our post request is
-- running or not." The button only dimmed, the "Posting…" it wrote in the dock was written over
-- by the pricing walk within the second, a success said nothing at all, and a refusal from the
-- auction house was either invisible (the refresh after "Posting failed" replaced it at once) or
-- never heard (AUCTION_HOUSE_SHOW_ERROR reached the Sniper only, so the row sat disabled until
-- the watchdog called it a timeout).
--
-- End to end through the real modules, the same shape spec/sell_post_queue_control_spec.lua
-- uses: bags -> positions -> the row and the dock -> onPostClick -> the events that answer it.
describe("Sell tab, a Post says what it is doing", function()
  local GC, root, render, container, timers, posts, postReturn, onPost, bags, postedSlots, auctions, sentUnits

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint() end
    function v:ClearAllPoints() end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
    function v:SetVariant(name) self.variant = name end
    -- Theme.Button's own: the real one turns the client's spinner inside the button
    -- (spec/theme_button_contract_spec.lua drives the real widget).
    function v:SetBusy(on) self.busy = on and true or false end
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

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local n, val = debug.getupvalue(fn, i)
      if not n then break end
      if n == wanted then return val end
    end
    error("missing upvalue " .. wanted)
  end

  local BAGS = {
    [0] = {
      { itemID = 23427, stackCount = 200, itemName = "Eternium Ore" },
      { itemID = 23427, stackCount = 46, itemName = "Eternium Ore" },
    },
  }
  -- The ore and a second commodity, for what has to go on posting while the ore waits.
  local TWO_ITEMS = {
    [0] = {
      { itemID = 23427, stackCount = 200, itemName = "Eternium Ore" },
      { itemID = 23427, stackCount = 46, itemName = "Eternium Ore" },
      { itemID = 210796, stackCount = 80, itemName = "Mycobloom" },
    },
  }
  local ITEM_NAMES = { [23427] = "Eternium Ore", [210796] = "Mycobloom" }
  -- Enum.AuctionHouseError values the stub client has words for; anything else answers "",
  -- which is what Blizzard's own AuctionHouseUtil.GetErrorText does for a code it cannot name.
  local CLIENT_ERRORS = { [0] = "You don't have enough money.", [7] = "The Auction House is busy.",
    [1] = "There is already a higher bid on that item.", [12] = "You don't have enough of that item." }
  -- The client's own Enum.AuctionHouseError, as far as these specs name it.
  local AH_ERROR = { NotEnoughMoney = 0, HigherBid = 1, BidIncrement = 2, BidOwn = 3, ItemNotFound = 4,
    IsBusy = 7, Unavailable = 8, ItemHasQuote = 9, DatabaseError = 10, MinBid = 11, NotEnoughItems = 12,
    RepairItem = 13, BoundItem = 16, DoubleBid = 23 }

  local GREEN, RED, MUTED = { 0, 1, 0 }, { 1, 0, 0 }, { .72, .71, .69 }

  before_each(function()
    timers, posts, postReturn, onPost, bags, postedSlots, auctions = {}, 0, false, nil, BAGS, {}, {}
    sentUnits = {}
    _G.time = function() return 1000 end
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(bags[bag] or {}) end,
      GetContainerItemInfo = function(bag, slot) return (bags[bag] or {})[slot] end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      PostCommodity = function(location, _, _, unitPrice)
        posts = posts + 1
        postedSlots[#postedSlots + 1] = location.slot
        sentUnits[#sentUnits + 1] = unitPrice
        if onPost then onPost() end
        return postReturn
      end,
      ConfirmPostCommodity = function() end,
      -- What AUCTION_HOUSE_AUCTION_CREATED's auctionID names, when the client knows it.
      GetAuctionInfoByID = function(auctionID)
        local itemID = auctions[auctionID]
        return itemID and { itemKey = { itemID = itemID } } or nil
      end,
    }
    _G.AuctionHouseUtil = { GetErrorText = function(code) return CLIENT_ERRORS[code] or "" end }
    _G.Enum = { AuctionHouseError = AH_ERROR }
    _G.C_Item = { GetItemNameByID = function(id) return ITEM_NAMES[id] end }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }

    GC = {
      Sell = {},
      Theme = {
        color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = MUTED, red = RED, green = GREEN,
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
    helper.loadModule("UI/SellFrame.lua", GC)
    GC.Acquisitions.Init({})

    root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    render = upvalue(GC.Sell.Attach, "renderRows")
    container = upvalue(render, "container")
    container:Show()
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString, _G.C_Timer = os.time, nil, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation = nil, nil, nil, nil
    _G.AuctionHouseUtil, _G.AUCTION_POSTING_ERROR_TEXT, _G.Enum = nil, nil, nil
  end)

  local function quotes()
    return upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
  end

  -- Priced, composed and drawn: the ore's row is on screen with its own Post button.
  local function ready()
    GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
    upvalue(GC.Sell.SellableCount, "composePositions")()
    render()
  end

  local function rowOf(itemID)
    for _, row in ipairs(upvalue(render, "rows")) do
      if row:IsShown() and row.kind == "position" and row.position.itemID == itemID then return row end
    end
    error(("item %d's row is not on screen"):format(itemID))
  end

  local function oreRow() return rowOf(23427) end

  local function pressRowPost(itemID)
    local row = rowOf(itemID or 23427)
    row.action.scripts.OnClick(row.action)
    return row
  end

  -- Every RecordPost the tab makes, through the real Acquisitions underneath.
  local function recordedPosts()
    local recorded, real = {}, GC.Acquisitions.RecordPost
    GC.Acquisitions.RecordPost = function(...)
      recorded[#recorded + 1] = { ... }
      return real(...)
    end
    return recorded
  end

  -- What the pricing walk does every few seconds while a post is going up.
  local function walkSays(text)
    upvalue(GC.Sell.Refresh, "setStatus")(text)
  end

  local function fire(seconds)
    local fired = 0
    for i = #timers, 1, -1 do
      if timers[i].seconds == seconds then
        local timer = table.remove(timers, i)
        timer.fn()
        fired = fired + 1
      end
    end
    return fired
  end

  describe("the moment Post is pressed", function()
    it("turns the row's own button busy: disabled, Posting…, the spinner going", function()
      ready()
      local row = pressRowPost()
      assert.equal(1, posts)
      assert.is_false(row.action.enabled)
      assert.equal("Posting…", row.action.label)
      assert.is_true(row.action.busy)
      assert.equal("Posting…", container.dockStatus.text)
    end)

    it("turns the dock's POST busy too, beside the name of the item going up", function()
      ready()
      pressRowPost()
      local button = container.queueButton
      assert.equal("POSTING…", button.label)
      assert.is_false(button.enabled)
      assert.is_true(button.busy)
      assert.matches("Eternium Ore", container.queueLabel.text, 1, true)
    end)

    it("from the dock's POST, busies the row it is posting as well", function()
      ready()
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.equal(1, posts)
      local row = oreRow()
      assert.equal("Posting…", row.action.label)
      assert.is_true(row.action.busy)
      assert.is_true(container.queueButton.busy)
    end)

    -- The walk re-prices every few seconds and wrote over "Posting…" before it could be read.
    it("keeps Posting… in the dock while the pricing walk talks underneath", function()
      ready()
      pressRowPost()
      walkSays("Checking this item's price…")
      assert.equal("Posting…", container.dockStatus.text)
      assert.equal("Checking this item's price…", root.status.text)
    end)
  end)

  describe("when the auction house takes it", function()
    it("says Posted, in green, for a moment, and frees both buttons", function()
      ready()
      local row = pressRowPost()
      GC.Sell.OnAuctionCreated()
      assert.matches("^Posted", container.dockStatus.text)
      assert.matches("Eternium Ore ×246", container.dockStatus.text, 1, true)
      assert.same(GREEN, { unpack(container.dockStatus.color, 1, 3) })
      assert.is_false(row.action.busy)
      assert.is_false(container.queueButton.busy)
      assert.equal("POST 1", container.queueButton.label)
      -- The refresh that follows every post does not talk over it...
      walkSays("Checking prices…")
      assert.matches("^Posted", container.dockStatus.text)
      -- ...and after its moment the dock goes back to what the tab is doing.
      assert.equal(1, fire(1.5))
      assert.equal("Checking prices…", container.dockStatus.text)
      assert.same(MUTED, { unpack(container.dockStatus.color, 1, 3) })
    end)
  end)

  describe("when the auction house refuses it", function()
    it("says why in the client's own words, frees the row, and holds the words long enough to read", function()
      ready()
      local row = pressRowPost()
      GC.Sell.OnAuctionHouseError(0)
      assert.equal("You don't have enough money.", container.dockStatus.text)
      assert.same(RED, { unpack(container.dockStatus.color, 1, 3) })
      assert.is_nil(row.postStage)
      assert.equal("Post", row.action.label)
      assert.is_true(row.action.enabled)
      assert.is_false(row.action.busy)
      assert.is_false(container.queueButton.busy)
      walkSays("Checking prices…")
      assert.equal("You don't have enough money.", container.dockStatus.text)
      assert.equal(1, fire(10))
      assert.equal("Checking prices…", container.dockStatus.text)
    end)

    it("says the post failed when the client has no words for the error", function()
      ready()
      pressRowPost()
      GC.Sell.OnAuctionHouseError(99)
      assert.equal("Posting failed", container.dockStatus.text)
    end)

    it("leaves the tab alone for an auction house error while nothing of ours is going up", function()
      ready()
      walkSays("Prices up to date")
      GC.Sell.OnAuctionHouseError(0)
      assert.equal("Prices up to date", container.dockStatus.text)
    end)

    -- AUCTION_HOUSE_POST_ERROR carries no payload; the default UI answers it with
    -- AUCTION_POSTING_ERROR_TEXT, a two-paragraph sentence the one-line dock has to flatten.
    it("reads the post-error event in the client's own sentence, on one line", function()
      _G.AUCTION_POSTING_ERROR_TEXT =
        "Items can't be posted right now.|n|nThe auction house is about to undergo a major update."
      postReturn = true -- the maintenance-window warning: the post waits for Confirm
      ready()
      local row = pressRowPost()
      assert.equal("confirm", row.postStage)
      GC.Sell.OnPostError()
      assert.equal("Items can't be posted right now. The auction house is about to undergo a major update.",
        container.dockStatus.text)
      assert.same(RED, { unpack(container.dockStatus.color, 1, 3) })
      assert.equal("Post", row.action.label)
    end)
  end)

  describe("when nothing answers", function()
    -- A post that was SENT can still go up; the line says so rather than "try again", which the
    -- hold on that item would contradict a moment later (review I3).
    it("gives the row back and says the auction house has not answered yet", function()
      ready()
      local row = pressRowPost()
      assert.equal(1, fire(8))
      assert.equal("No answer yet -- listening for a minute", container.dockStatus.text)
      assert.same(RED, { unpack(container.dockStatus.color, 1, 3) })
      assert.equal("Post", row.action.label)
      assert.is_true(row.action.enabled)
      assert.is_false(row.action.busy)
      assert.is_false(container.queueButton.busy)
    end)

    -- Nobody asked the auction house anything yet: it is the player's Confirm that lapsed.
    it("says a Confirm nobody pressed expired, not that the auction house went quiet", function()
      postReturn = true
      ready()
      local row = pressRowPost()
      assert.equal("Confirm", row.action.label)
      assert.is_false(row.action.busy)
      assert.equal(1, fire(8))
      assert.equal("Post confirmation expired", container.dockStatus.text)
    end)
  end)

  describe("when the client queues it", function()
    it("says it is waiting for the auction house, and the row keeps turning", function()
      onPost = function() GC.Sell.OnThrottleQueued() end
      ready()
      local row = pressRowPost()
      assert.equal("Waiting for the Auction House…", container.dockStatus.text)
      assert.equal("Posting…", row.action.label)
      assert.is_true(row.action.busy)
      walkSays("Checking prices…")
      assert.equal("Waiting for the Auction House…", container.dockStatus.text)
    end)

    it("ignores a queued message while nothing of ours is going up", function()
      ready()
      walkSays("Prices up to date")
      GC.Sell.OnThrottleQueued()
      assert.equal("Prices up to date", container.dockStatus.text)
    end)
  end)

  describe("a second press", function()
    -- The keybinding reaches onPostClick through onQueueClick whatever the buttons look like.
    -- A post on its way used to be let go of the moment its quote passed 45 seconds -- the
    -- row came back as Post, and the next press posted the same stack a second time.
    it("sends nothing while the post is on its way, even once the quote behind it has aged", function()
      ready()
      local row = pressRowPost()
      assert.equal(1, posts)
      _G.time = function() return 1100 end
      root.GoldCapPostNext()
      assert.equal("posting", row.postStage)
      assert.is_true(row.action.busy)
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1100)
      root.GoldCapPostNext()
      assert.equal(1, posts)
    end)
  end)

  -- The 8 s watchdog gives up on the wire, not on the post: a slow or queued post can still be
  -- created afterwards, and an unrelated auction house error (AUCTION_HOUSE_SHOW_ERROR names no
  -- request) can free a row whose post then goes up anyway. Either way the auction exists.
  describe("a late answer", function()
    local function readyTwo()
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      GC.QuoteCache.Set(quotes(), 210796, 5000, 1000)
      upvalue(GC.Sell.SellableCount, "composePositions")()
      render()
    end

    -- The dock says Posted over the timeout and the item is free again. Nothing durable is written
    -- from the creation: which post it answers is the order rule's guess. The owned list the
    -- refresh asks for next names the auction, and OnOwnedAuctions records it from there.
    it("is still the post's: the dock says Posted over the timeout, and the item is free again", function()
      local recorded = recordedPosts()
      ready()
      pressRowPost()
      assert.equal(1, fire(8))
      assert.equal("No answer yet -- listening for a minute", container.dockStatus.text)
      _G.time = function() return 1030 end
      GC.Sell.OnAuctionCreated()
      assert.matches("^Posted", container.dockStatus.text)
      assert.matches("Eternium Ore ×246", container.dockStatus.text, 1, true)
      assert.same(GREEN, { unpack(container.dockStatus.color, 1, 3) })
      assert.equal(0, #GC.Sell._LiveLate())
      assert.equal(0, #recorded)
    end)

    -- An error both a post and a purchase can raise, while a purchase of ours is out too: it may
    -- not have been the post's. The post is let go of but listened for.
    it("corrects a shared-code error that may have been somebody else's", function()
      local recorded = recordedPosts()
      ready()
      pressRowPost()
      GC.PurchaseSlot = { IsBusy = function() return true end }
      GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughMoney)
      GC.PurchaseSlot = nil
      assert.equal("You don't have enough money.", container.dockStatus.text)
      -- Meanwhile the stack is not sent again: the post the error may not have been about can
      -- still be taking it.
      pressRowPost()
      assert.equal(1, posts)
      assert.equal("Last post may still go up -- wait a minute", container.dockStatus.text)
      GC.Sell.OnAuctionCreated()
      assert.matches("^Posted", container.dockStatus.text)
      assert.equal(0, #recorded) -- a guess: the owned list records it
    end)

    -- A purchase either window CONFIRMED is out until it is answered, and that can run past the
    -- slot's MAX_SECONDS, where IsBusy stops saying so (GC.PurchaseSlot.ConfirmOwed): its error is
    -- no more the post's than one from a purchase still inside its claim.
    it("counts a confirmed purchase still owed its answer after its claim has gone stale", function()
      ready()
      pressRowPost()
      GC.PurchaseSlot = {
        IsBusy = function() return false end,
        ConfirmOwed = function() return "sniper" end,
      }
      GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughMoney)
      GC.PurchaseSlot = nil
      pressRowPost()
      assert.equal(1, posts)
      assert.equal("Last post may still go up -- wait a minute", container.dockStatus.text)
    end)

    it("holds another Post of the same item while its last post may still be answered", function()
      ready()
      pressRowPost()
      fire(8)
      pressRowPost()
      assert.equal(1, posts)
      assert.equal("Last post may still go up -- wait a minute", container.dockStatus.text)
      -- The dock's POST does not offer it either: held back, with the reason in words.
      assert.equal("NOTHING TO POST", container.queueButton.label)
      assert.matches("1", container.queueHeldBack.text, 1, true)
      root.GoldCapPostNext()
      assert.equal(1, posts)
    end)

    it("goes on posting every other item meanwhile, from the dock's POST as from a row", function()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      assert.matches("Mycobloom", container.queueLabel.text, 1, true)
      container.queueButton.scripts.OnClick(container.queueButton)
      assert.equal(2, posts)
      assert.equal(3, postedSlots[2]) -- Mycobloom's own slot
    end)

    it("tells the late answer from the post on the wire by the item the client names", function()
      local recorded = recordedPosts()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      local myco = pressRowPost(210796)
      auctions[501] = 23427
      GC.Sell.OnAuctionCreated(501)
      assert.matches("Posted · Eternium Ore ×246", container.dockStatus.text, 1, true)
      assert.equal("posting", myco.postStage) -- still waiting for its own answer
      assert.is_true(myco.action.busy)
      -- Its moment over, the dock is back on the post still out, not on the walk.
      assert.equal(1, fire(1.5))
      assert.equal("Posting…", container.dockStatus.text)
      auctions[502] = 210796
      GC.Sell.OnAuctionCreated(502)
      assert.matches("Posted · Mycobloom ×80", container.dockStatus.text, 1, true)
      assert.is_nil(myco.postStage)
      -- Mycobloom went out while the ore's answer was still open: neither is certain.
      assert.equal(0, #recorded)
    end)

    it("credits nobody with an auction the client names as some other item", function()
      local recorded = recordedPosts()
      ready()
      local row = pressRowPost()
      auctions[777] = 555
      GC.Sell.OnAuctionCreated(777)
      assert.equal(0, #recorded)
      assert.equal("posting", row.postStage)
    end)

    -- The client names nothing (GetAuctionInfoByID is nilable, and nothing in Blizzard's UI looks
    -- up an auction it just created -- the likely path in game). Answers come in the order the
    -- posts went out, so the OLDEST post still out owns a creation; the one on the wire stays
    -- armed for its own answer (review P1).
    it("credits an unnamed creation to the oldest post out and keeps the one on the wire", function()
      local recorded = recordedPosts()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      local myco = pressRowPost(210796)
      GC.Sell.OnAuctionCreated(601) -- the client knows nothing of 601
      assert.matches("Posted · Eternium Ore ×246", container.dockStatus.text, 1, true)
      assert.equal("posting", myco.postStage)
      assert.is_true(myco.action.busy)
      myco.action.scripts.OnClick(myco.action)
      assert.equal(2, posts) -- never a second post of Mycobloom's pool
      GC.Sell.OnAuctionCreated(602)
      assert.matches("Posted · Mycobloom ×80", container.dockStatus.text, 1, true)
      assert.is_nil(myco.postStage)
      assert.equal(0, #recorded)
    end)

    -- ...and once every post of ours is answered, a creation is somebody else's -- Blizzard's
    -- own Sell pane, another addon's -- and books nothing (review P1b).
    it("books nothing for a creation once no sent post of ours is out", function()
      local recorded = recordedPosts()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      local myco = pressRowPost(210796)
      GC.Sell.OnAuctionCreated(601)
      GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems) -- Mycobloom refused: a post's own code
      assert.is_nil(myco.postStage)
      GC.Sell.OnAuctionCreated(603)
      assert.equal("You don't have enough of that item.", container.dockStatus.text) -- nobody's Posted
      assert.equal(0, #recorded)
    end)

    -- A post waiting for its Confirm has sent nothing and can own no creation (review P9).
    it("never lets a post still waiting for its Confirm claim a creation", function()
      local recorded = recordedPosts()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      postReturn = true
      local myco = pressRowPost(210796)
      assert.equal("confirm", myco.postStage)
      GC.Sell.OnAuctionCreated(601)
      assert.matches("Posted · Eternium Ore ×246", container.dockStatus.text, 1, true)
      assert.equal("confirm", myco.postStage)
      assert.equal("Confirm", myco.action.label)
      assert.equal(0, #recorded)
    end)

    -- An error only a post can raise is the post's refusal, whole: nothing is listened for and
    -- nothing held, so the next press posts again at once (review P2, P2b).
    it("takes a post-only error as the post's refusal: no hold, and a later creation is nobody's", function()
      local recorded = recordedPosts()
      ready()
      pressRowPost()
      GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems)
      GC.Sell.OnAuctionCreated(604) -- Blizzard's own Sell pane
      assert.equal(0, #recorded)
      pressRowPost()
      assert.equal(2, posts)
    end)

    it("takes a shared-code error as the post's own when nothing else of ours is out", function()
      ready()
      pressRowPost()
      GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy)
      assert.equal("The Auction House is busy.", container.dockStatus.text)
      pressRowPost()
      assert.equal(2, posts) -- "busy": press again at once
    end)

    it("keeps waiting through an error only a bid or a purchase can raise", function()
      ready()
      local row = pressRowPost()
      GC.Sell.OnAuctionHouseError(AH_ERROR.HigherBid)
      assert.equal("posting", row.postStage)
      assert.is_true(row.action.busy)
      assert.equal("Posting…", container.dockStatus.text)
    end)

    -- A late answer can land a minute on, with the player on another tab. The toolbar is the
    -- whole window's; only the dock, which is ours, is told (review M1).
    it("writes a late answer into the dock only while another tab is on screen", function()
      ready()
      pressRowPost()
      fire(8)
      container:Hide()
      root.status:SetText("scanning auction house...")
      GC.Sell.OnAuctionCreated()
      assert.equal("scanning auction house...", root.status.text)
      assert.matches("^Posted", container.dockStatus.text)
    end)

    -- Pressing a held item while another post is out answers "Finish the pending post first",
    -- and leaves the dock saying what that post is doing (review M3).
    it("leaves the post on the wire its dock line when a held item is pressed", function()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      pressRowPost(210796)
      pressRowPost(23427)
      assert.equal("Posting…", container.dockStatus.text)
      assert.equal(2, posts)
    end)

    -- For the owner to settle in game what the client says about an auction it just created.
    it("traces what the client names for every created auction", function()
      ready()
      auctions[501] = 23427
      GC.Sell.OnAuctionCreated(501)
      GC.Sell.OnAuctionCreated(777)
      local trace = table.concat(GC.Util.TraceDump(10), "\n")
      assert.matches("sell: created 501 %-> 23427:0:0:0", trace)
      assert.matches("sell: created 777 %-> nil", trace)
    end)

    -- The order rule holds for an error as for a creation: while a late post is still unanswered
    -- and the next post is on the wire, the late post's answer comes first -- so a refusal ends
    -- the OLDEST late answer and leaves the wire armed. It used to free the wire: the re-press
    -- sent its stack twice, and the wire's creation was booked as the late item (review NI1, PX).
    it("reads a refusal that lands while a late post is open as that late post's", function()
      local recorded = recordedPosts()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      local myco = pressRowPost(210796)
      GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy)
      assert.equal("posting", myco.postStage)
      assert.is_true(myco.action.busy)
      myco.action.scripts.OnClick(myco.action)
      assert.equal(2, posts) -- never a second post of Mycobloom's pool
      GC.Sell.OnAuctionCreated(605)
      assert.matches("Posted · Mycobloom ×80", container.dockStatus.text, 1, true) -- never the ore
      assert.is_nil(myco.postStage)
      assert.equal(0, #recorded)
      -- The ore's post is answered (refused): it may be posted again.
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000)
      pressRowPost(23427)
      assert.equal(3, posts)
    end)

    it("reads a post-only refusal the same way (PX2)", function()
      local recorded = recordedPosts()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      local myco = pressRowPost(210796)
      GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems)
      assert.equal("posting", myco.postStage)
      GC.Sell.OnAuctionCreated(606)
      assert.matches("Posted · Mycobloom ×80", container.dockStatus.text, 1, true)
      assert.equal(0, #recorded)
    end)

    -- An error raised inside the post call itself (nothing sent yet) is that call's answer.
    it("reads an error from inside the post call as the wire's own", function()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      onPost = function() GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems) end
      local myco = pressRowPost(210796)
      assert.is_nil(myco.postStage)
      -- ...and the ore is still the one being listened for.
      onPost = nil
      pressRowPost(23427)
      assert.equal(2, posts)
    end)

    -- The Confirm call can raise an error on the spot too ("You don't have enough money."). It
    -- is that post's own, as inside the first click's call: the post is refused, not late, and
    -- the older late answer stays open (review NM-B, S9).
    it("reads an error from inside the Confirm call as the wire's own (S9)", function()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8) -- the ore is late
      postReturn = true -- Mycobloom asks for a Confirm
      local myco = pressRowPost(210796)
      assert.equal("confirm", myco.postStage)
      _G.C_AuctionHouse.ConfirmPostCommodity = function() GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughMoney) end
      myco.action.scripts.OnClick(myco.action)
      assert.is_nil(myco.postStage)
      assert.equal("You don't have enough money.", container.dockStatus.text)
      fire(8)
      local live = GC.Sell._LiveLate()
      assert.equal(1, #live)
      assert.equal(23427, live[1].pin.itemID) -- the ore still, never Mycobloom
    end)

    -- A creation is a server answer: it can never be the answer to a post call that raised and
    -- sent nothing (review NM1, PR).
    it("never credits a creation to a post whose call raised", function()
      local recorded = recordedPosts()
      onPost = function() error("bad argument") end
      ready()
      assert.has_error(function() pressRowPost() end)
      GC.Sell.OnAuctionCreated(607)
      assert.equal(0, #recorded)
      assert.equal("posting", oreRow().postStage)
    end)

    -- Our own requests that can draw a shared-code error: the tab's own owned-auctions query and
    -- a Sniper page still in flight (review NM3). With one out, the error may be theirs.
    it("listens late after a shared error while the owned-auctions query or a Sniper page is out", function()
      ready()
      pressRowPost()
      upvalue(GC.Sell.Refresh, "refresh").phase = "owned"
      GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy)
      upvalue(GC.Sell.Refresh, "refresh").phase = "idle"
      pressRowPost()
      assert.equal(1, posts) -- held: that post may still go up
      assert.equal("Last post may still go up -- wait a minute", container.dockStatus.text)
    end)

    -- The Sniper's own "busy" -- a pass paging, a purchase out -- counts too. A page still out
    -- after the switch to this tab, which that no longer sees, is driven through the real Sniper
    -- in spec/sell_sniper_page_out_spec.lua (review NM-C).
    it("counts whatever the Sniper calls busy as a request of ours", function()
      ready()
      pressRowPost()
      GC.Sniper = { IsBusy = function() return true end }
      GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy)
      GC.Sniper = nil
      pressRowPost()
      assert.equal(1, posts)
    end)

    -- Off the tab, the on-time path does not write "Refreshing listings…" into the window's
    -- toolbar either.
    it("keeps an on-time Posted off another tab's toolbar", function()
      ready()
      pressRowPost()
      container:Hide()
      root.status:SetText("scanning auction house...")
      GC.Sell.OnAuctionCreated()
      assert.equal("scanning auction house...", root.status.text)
    end)

    -- With another post out, a press answers "Finish the pending post first" before it spends a
    -- search on a stale quote.
    it("answers another row's press with the pending post before any price fetch", function()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      _G.time = function() return 1100 end -- Mycobloom's quote has gone stale
      pressRowPost(210796)
      assert.equal("Finish the pending post first", root.status.text)
      assert.equal(1, posts)
    end)

    -- /gc sell answers "why can't I post this?" and "why wasn't that post booked?" from a paste:
    -- which items a late answer holds and for how long, whether an answer is still owed, whether
    -- a post now would be certain, the stock waiting for the auction house, and whether the
    -- Sniper or a purchase has a request out (final review M7).
    it("prints the late window, the owed answer, certainty and requests out in /gc sell", function()
      local printed = {}
      GC.Print = function(line) printed[#printed + 1] = line end
      GC.Sniper = { RequestOut = function() return true end }
      GC.PurchaseSlot = { ConfirmOwed = function() return "buy" end }
      ready()
      pressRowPost()
      fire(8)
      _G.time = function() return 1020 end
      GC.Sell.DebugPrint()
      GC.Sniper, GC.PurchaseSlot = nil, nil
      local text = table.concat(printed, "\n")
      assert.matches("post: late=1 %[Eternium Ore 40s%] owed=0s certain=false waiting=0 requestOut=true confirmOwed=buy", text)
    end)

    -- What is written down, and when (review sell-fix3, design). The owned-auctions list is the
    -- durable record of every auction on it (OnOwnedAuctions -> ObserveOwnedPosition). A creation
    -- adds a booking of its own only when it is CERTAINLY the post on the wire's: no late answer
    -- open when that post went out, or taken while it was out. Every other credit moves the
    -- screen only. It replaced a settlement that booked guesses and corrected them against the
    -- list -- which wrote what the list writes anyway, and found a new edge every round.
    describe("the durable record", function()
      local function activityFor(positionKey)
        for _, activity in ipairs(GC.Acquisitions.GetActivities({ char = "Owner-Dentarg", region = "eu" })) do
          if activity.positionKey == positionKey then return activity end
        end
        return nil
      end
      local function ownedList(list) _G.C_AuctionHouse.GetOwnedAuctions = function() return list end end
      local function overrides() return upvalue(GC.Sell._SpendPrice, "priceOverrides") end

      it("books the post on the wire at its creation when no late answer shared its flight", function()
        local recorded = recordedPosts()
        ready()
        pressRowPost()
        GC.Sell.OnAuctionCreated(700)
        assert.equal(1, #recorded)
        assert.equal(23427, recorded[1][2])
        assert.equal(246, recorded[1][6])
        -- ...so a post the player closes the auction house straight after is still on record.
        GC.Sell.Reset()
        assert.equal(246, activityFor("commodity:23427").lastPostedQty)
      end)

      it("writes nothing from a guess; the owned list records the auction for what it is", function()
        local recorded = recordedPosts()
        ready()
        pressRowPost()
        fire(8)
        GC.Sell.OnAuctionCreated(608)
        assert.equal(0, #recorded)
        assert.is_nil(activityFor("commodity:23427"))
        ownedList({ { auctionID = 608, itemKey = { itemID = 23427 }, quantity = 246, buyoutAmount = 184719, status = 0 } })
        GC.Sell.OnOwnedAuctions()
        local activity = activityFor("commodity:23427")
        assert.is_truthy(activity)
        assert.equal(1000, activity.firstSeenAt)
      end)

      -- A guess that was wrong is never on record: an auction the list names as another item
      -- leaves the ore unrecorded, and records the other item only if it is ours to name.
      it("never records a guess the owned list contradicts", function()
        ready()
        pressRowPost()
        fire(8)
        GC.Sell.OnAuctionCreated(604) -- Blizzard's own Sell pane, the client naming nothing
        ownedList({ { auctionID = 604, itemKey = { itemID = 555 }, quantity = 1, buyoutAmount = 99, status = 0 } })
        GC.Sell.OnOwnedAuctions()
        assert.is_nil(activityFor("commodity:23427"))
      end)

      -- A post that went out while an older one's answer was still open is not certain of the next
      -- creation, even as the post on the wire.
      it("does not book the wire's creation while an older post's answer was open as it went out", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        pressRowPost(210796)
        auctions[610] = 210796
        GC.Sell.OnAuctionCreated(610)
        assert.matches("Posted · Mycobloom ×80", container.dockStatus.text, 1, true)
        assert.equal(0, #recorded)
      end)

      -- ...nor once an older answer is taken while it is out (the late window only shrinks during a
      -- post's flight, so this is the belt to the check at send).
      it("stops counting the wire as certain once a late answer is taken while it is out", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        local myco = pressRowPost(210796)
        upvalue(GC.Sell.OnAuctionCreated, "postingPin").clean = true -- as if nothing had been open
        GC.Sell.OnAuctionCreated(611) -- unnamed: the ore's, the oldest
        GC.Sell.OnAuctionCreated(612) -- Mycobloom's
        assert.is_nil(myco.postStage)
        assert.equal(0, #recorded)
      end)

      -- A late answer ended by a guess -- a creation the client names nothing about, a "busy"
      -- that may be somebody else's -- may still be owed its real answer for the rest of its
      -- minute. A post sent meanwhile is not certain of the next creation either (review sell-fix4
      -- M1, probe B): the ore's real creation lands in Mycobloom's flight and must not be booked
      -- as Mycobloom, which the auction house then refuses.
      it("does not book a post sent while a guess may still owe an answer (probe B)", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        GC.Sell.OnAuctionCreated(901) -- Blizzard's own pane, unnamed: ends the ore's wait
        assert.equal(0, #GC.Sell._LiveLate())
        pressRowPost(210796)
        GC.Sell.OnAuctionCreated(902) -- the ore's real creation, in Mycobloom's flight
        GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems) -- Mycobloom refused
        assert.equal(0, #recorded)
        assert.is_nil(activityFor("commodity:210796"))
      end)

      it("does not book a post sent while a busy that ended a late answer may be someone else's (probe C)", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        local myco = pressRowPost(210796)
        GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy) -- ends the ore's wait: maybe not its answer
        auctions[903] = 210796
        GC.Sell.OnAuctionCreated(903)
        assert.is_nil(myco.postStage)
        pressRowPost(23427) -- the ore again, into an empty window
        GC.Sell.OnAuctionCreated(904) -- the first ore post's real creation
        assert.equal(0, #recorded)
      end)

      -- ...and once the minute that answer was owed in is over, posts are certain again.
      it("books again once the owed answer's minute is over", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        GC.Sell.OnAuctionCreated(905)
        _G.time = function() return 1000 + GC.Sell.LATE_ANSWER_SECONDS + 1 end
        GC.QuoteCache.Set(quotes(), 210796, 5000, 1000 + GC.Sell.LATE_ANSWER_SECONDS + 1)
        upvalue(GC.Sell.SellableCount, "composePositions")()
        render()
        pressRowPost(210796)
        GC.Sell.OnAuctionCreated(906)
        assert.equal(1, #recorded)
        assert.equal(210796, recorded[1][2])
      end)

      -- The Confirm path decides `clean` as it sends, too (review N4, probe F).
      it("does not book a confirmed post that went out while a late answer was open", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        postReturn = true
        local myco = pressRowPost(210796)
        myco.action.scripts.OnClick(myco.action) -- Confirm
        auctions[907] = 210796
        GC.Sell.OnAuctionCreated(907) -- named: Mycobloom's own, but not certain
        assert.is_nil(myco.postStage)
        assert.equal(0, #recorded)
        assert.equal(1, #GC.Sell._LiveLate()) -- the ore still listened for
      end)

      -- The error order rule's own belt (review N4): a wire it takes a late answer from is not
      -- certain any more, even if nothing else had said so.
      it("stops counting the wire as certain once the error order rule takes a late answer", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        pressRowPost(210796)
        upvalue(GC.Sell.OnAuctionCreated, "postingPin").clean = true -- as if nothing had been open
        GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy)
        auctions[908] = 210796
        GC.Sell.OnAuctionCreated(908)
        assert.equal(0, #recorded)
      end)

      -- Off the tab, a credited late creation still asks for the owned list at once -- a query
      -- only, no walk -- so the auction is on record before the player closes the auction house
      -- from Deals or BUY (review sell-fix4 M2).
      it("asks for the owned list after a late credit while the tab is hidden", function()
        local queried = 0
        _G.C_AuctionHouse.QueryOwnedAuctions = function() queried = queried + 1 end
        _G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
        GC.Sniper = { IsAHOpen = function() return true end }
        ready()
        pressRowPost()
        fire(8)
        container:Hide()
        GC.Sell.OnAuctionCreated(909)
        GC.Sniper = nil
        assert.equal(1, queried)
        assert.are_not.equal("owned", upvalue(GC.Sell.Refresh, "refresh").phase)
      end)

      -- S1: a commodity lot sells from the front of the queue. However much of it has gone by the
      -- time the list names it, the booking stands and the typed price stays spent.
      it("keeps the booking and the spent price when the lot has partly sold (S1)", function()
        ready()
        overrides()["commodity:23427"] = 184719
        pressRowPost()
        GC.Sell.OnAuctionCreated(701)
        assert.is_nil(overrides()["commodity:23427"])
        ownedList({ { auctionID = 701, itemKey = { itemID = 23427 }, quantity = 200, buyoutAmount = 184719, status = 0 } })
        GC.Sell.OnOwnedAuctions()
        assert.equal(246, activityFor("commodity:23427").lastPostedQty)
        assert.is_nil(overrides()["commodity:23427"])
        assert.equal(0, #GC.Sell._LiveLate())
      end)

      -- S2 / S2b: nothing reads a list against an old post, whether the auction house closed in
      -- between or not.
      it("never undoes a booking over a later list (S2)", function()
        ready()
        pressRowPost()
        GC.Sell.OnAuctionCreated(702)
        GC.Sell.Reset()
        _G.time = function() return 11800 end
        ownedList({ { auctionID = 702, itemKey = { itemID = 555 }, quantity = 1, buyoutAmount = 99, status = 0 } })
        GC.Sell.OnOwnedAuctions()
        local activity = activityFor("commodity:23427")
        assert.equal(246, activity.lastPostedQty)
        assert.equal(1000, activity.firstSeenAt)
      end)

      -- S3: a Blizzard-pane post lands while the ore is late and Mycobloom is on the wire. The
      -- guesses record nothing; the list records the ore and Mycobloom for what they are.
      it("records a cascade from the owned list alone, never from the guesses (S3)", function()
        local recorded = recordedPosts()
        bags = TWO_ITEMS
        readyTwo()
        pressRowPost(23427)
        fire(8)
        pressRowPost(210796)
        GC.Sell.OnAuctionCreated(901) -- Blizzard's own pane: credited to the ore
        GC.Sell.OnAuctionCreated(902) -- the ore's own: credited to Mycobloom
        GC.Sell.OnAuctionCreated(903) -- Mycobloom's own: no post of ours left
        assert.equal(0, #recorded)
        ownedList({
          { auctionID = 903, itemKey = { itemID = 210796 }, quantity = 80, buyoutAmount = 5000, status = 0 },
          { auctionID = 902, itemKey = { itemID = 23427 }, quantity = 246, buyoutAmount = 184719, status = 0 },
          { auctionID = 901, itemKey = { itemID = 555 }, quantity = 1, buyoutAmount = 99, status = 0 },
        })
        GC.Sell.OnOwnedAuctions()
        assert.is_truthy(activityFor("commodity:23427"))
        assert.is_truthy(activityFor("commodity:210796"))
        assert.equal(0, #GC.Sell._LiveLate())
      end)

      -- S4: a guess frees the ore, the ore goes out again, and the first post's auction lands on
      -- it. The second post went out while that guess could still be owed its real answer, so the
      -- creation books nothing (M1); the owned list records the ore, and nothing takes it back.
      it("records the ore from the list when its second post went out while a guess was owed (S4)", function()
        local recorded = recordedPosts()
        ready()
        pressRowPost()
        fire(8)
        GC.Sell.OnAuctionCreated(911)
        pressRowPost()
        assert.equal(2, posts)
        GC.Sell.OnAuctionCreated(912)
        assert.equal(0, #recorded)
        ownedList({
          { auctionID = 911, itemKey = { itemID = 555 }, quantity = 1, buyoutAmount = 99, status = 0 },
          { auctionID = 912, itemKey = { itemID = 23427 }, quantity = 246, buyoutAmount = 184719, status = 0 },
        })
        GC.Sell.OnOwnedAuctions()
        local activity = activityFor("commodity:23427")
        assert.is_truthy(activity)
        assert.equal(1000, activity.firstSeenAt)
      end)

      -- S8: a lot that sold whole before the list is on it as Sold: the booking stands.
      it("keeps the booking when the list shows the lot sold (S8)", function()
        ready()
        pressRowPost()
        GC.Sell.OnAuctionCreated(708)
        ownedList({ { auctionID = 708, itemKey = { itemID = 23427 }, quantity = 246, buyoutAmount = 184719, status = 1 } })
        GC.Sell.OnOwnedAuctions()
        assert.equal(246, activityFor("commodity:23427").lastPostedQty)
      end)

      -- S7: the owned list answers no post. A list landing while a post is on the wire leaves it
      -- armed for its own creation.
      it("leaves the post on the wire armed when the owned list lands (S7)", function()
        local row
        ready()
        row = pressRowPost()
        ownedList({ { auctionID = 709, itemKey = { itemID = 23427 }, quantity = 246, buyoutAmount = 184719, status = 0 } })
        GC.Sell.OnOwnedAuctions()
        assert.equal("posting", row.postStage)
      end)

      -- One rule for a typed price: spent by the credit, dropped when the window closes
      -- unanswered or the auction house closes over it, never put back.
      describe("a typed price", function()
        it("is spent when a late creation is credited, and never put back", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          fire(8)
          assert.equal(190000, overrides()["commodity:23427"]) -- the post may still go up
          GC.Sell.OnAuctionCreated(801)
          assert.is_nil(overrides()["commodity:23427"])
          ownedList({ { auctionID = 801, itemKey = { itemID = 555 }, quantity = 1, buyoutAmount = 99, status = 0 } })
          GC.Sell.OnOwnedAuctions()
          assert.is_nil(overrides()["commodity:23427"])
        end)

        -- An unanswered post is treated like a refused one: its price stays, on the row, for the
        -- retry. Dropped behind the row's back, it was still shown while GoldCap's price went out
        -- (review sell-fix4 I1).
        it("stays for the retry when the late window closes unanswered", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          fire(8)
          _G.time = function() return 1000 + GC.Sell.LATE_ANSWER_SECONDS + 1 end
          assert.equal(0, #GC.Sell._LiveLate())
          assert.equal(190000, overrides()["commodity:23427"])
        end)

        -- The price on the row is the price that goes out: whatever the row says when Post is
        -- pressed is the unit the post call is given.
        local function shownCopper(row)
          local gold, silver = row.cells.price.text:match("^(%d+)g(%d*)s?$")
          return gold and (tonumber(gold) * 10000 + (tonumber(silver) or 0) * 100) or nil
        end

        it("is what the post call sends, at GoldCap's price and at a typed one", function()
          ready()
          local row = oreRow()
          local shown = shownCopper(row)
          pressRowPost()
          assert.equal(shown, sentUnits[1])
          GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems) -- refused: free again
          overrides()["commodity:23427"] = 190000
          upvalue(GC.Sell.SellableCount, "composePositions")()
          render()
          row = oreRow()
          assert.equal(190000, shownCopper(row))
          pressRowPost()
          assert.equal(190000, sentUnits[2])
        end)

        -- The reviewer's probe A: the price set, the post late, a walk re-quoting and drawing the
        -- row, the minute running out, Post pressed as the hold lifts with no compose between.
        it("is shown and sent alike when Post is pressed as the hold lifts (probe A)", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          fire(8)
          _G.time = function() return 1040 end
          GC.QuoteCache.Set(quotes(), 23427, 184719, 1040)
          upvalue(GC.Sell.SellableCount, "composePositions")()
          render()
          _G.time = function() return 1061 end
          local row = oreRow()
          assert.equal(190000, shownCopper(row))
          pressRowPost()
          assert.equal(2, posts)
          assert.equal(190000, sentUnits[2])
        end)

        -- Probe H: the same, with the compose that notices the minute is over running first.
        it("is shown and sent alike after the compose that closes the window (probe H)", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          fire(8)
          _G.time = function() return 1061 end
          GC.QuoteCache.Set(quotes(), 23427, 184719, 1061)
          upvalue(GC.Sell.SellableCount, "composePositions")()
          render()
          local row = oreRow()
          assert.equal(190000, shownCopper(row))
          pressRowPost()
          assert.equal(190000, sentUnits[2])
        end)

        -- One rule at a close: every post that went out and was never answered drops its price,
        -- the one on the wire as well as the late ones (review N3). A post still waiting for its
        -- Confirm sent nothing, and keeps it.
        it("is dropped for the post on the wire when the auction house closes over it", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          GC.Sell.Reset()
          assert.is_nil(overrides()["commodity:23427"])
        end)

        it("stays for a post still waiting for its Confirm when the auction house closes", function()
          postReturn = true
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          assert.equal("confirm", oreRow().postStage)
          GC.Sell.Reset()
          assert.equal(190000, overrides()["commodity:23427"])
        end)

        it("is dropped when the auction house closes over the late window", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          fire(8)
          GC.Sell.Reset()
          assert.is_nil(overrides()["commodity:23427"])
        end)

        it("leaves a price typed since alone", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          fire(8)
          overrides()["commodity:23427"] = 175000 -- the player's next choice
          GC.Sell.OnAuctionCreated(802)
          assert.equal(175000, overrides()["commodity:23427"])
        end)

        it("stays for the retry when the post is refused", function()
          ready()
          overrides()["commodity:23427"] = 190000
          pressRowPost()
          GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughMoney)
          assert.equal(190000, overrides()["commodity:23427"])
        end)
      end)
    end)

    -- S5: a shared code while the ore is late, Mycobloom is on the wire and a walk search is out.
    -- The order rule reads it as the ore's (a note in the review, unchanged): the ore is free
    -- again, and Mycobloom stays armed.
    it("reads a shared error as the late post's even with a walk search out (S5)", function()
      bags = TWO_ITEMS
      readyTwo()
      pressRowPost(23427)
      fire(8)
      local myco = pressRowPost(210796)
      upvalue(GC.Sell.Refresh, "refresh").pending = true
      GC.Sell.OnAuctionHouseError(AH_ERROR.IsBusy)
      upvalue(GC.Sell.Refresh, "refresh").pending = nil
      assert.equal("posting", myco.postStage)
      assert.equal(0, #GC.Sell._LiveLate())
    end)

    -- S6: with no post on the wire, an error is nobody's this tab can name: the late item stays
    -- held for the rest of its minute.
    it("keeps a late item held through an error while nothing of ours is on the wire (S6)", function()
      ready()
      pressRowPost()
      fire(8)
      GC.Sell.OnAuctionHouseError(AH_ERROR.NotEnoughItems)
      pressRowPost()
      assert.equal(1, posts)
      assert.equal("Last post may still go up -- wait a minute", container.dockStatus.text)
    end)

    -- S9b: a plain Confirm, then its creation -- booked, and the row freed.
    it("books a confirmed post at its creation and frees the row (S9b)", function()
      local recorded = recordedPosts()
      postReturn = true
      ready()
      local row = pressRowPost()
      assert.equal("confirm", row.postStage)
      row.action.scripts.OnClick(row.action)
      assert.equal("confirming", row.postStage)
      GC.Sell.OnAuctionCreated(710)
      assert.is_nil(row.postStage)
      assert.equal(1, #recorded)
    end)

    it("stops listening, and lets the item post again, once its window has closed", function()
      local recorded = recordedPosts()
      ready()
      pressRowPost()
      fire(8)
      _G.time = function() return 1000 + GC.Sell.LATE_ANSWER_SECONDS + 1 end
      GC.Sell.OnAuctionCreated()
      assert.equal(0, #recorded)
      GC.QuoteCache.Set(quotes(), 23427, 184719, 1000 + GC.Sell.LATE_ANSWER_SECONDS + 1)
      pressRowPost()
      assert.equal(2, posts)
    end)
  end)

  -- A post call that raises (a client "bad argument") used to leave the row and the dock on
  -- "Posting…" until the auction house closed: the watchdog was armed only after the call
  -- returned, and every other Post answered "Finish the pending post first" (review I2).
  it("never leaves a Post stuck when the post call itself raises", function()
    onPost = function() error("bad argument #1 to 'PostCommodity'") end
    ready()
    local row
    assert.has_error(function() row = pressRowPost() end)
    row = oreRow()
    assert.is_true(row.action.busy)
    assert.equal(1, fire(8))
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    assert.is_false(row.action.busy)
    assert.is_false(container.queueButton.busy)
    assert.equal("The auction house did not answer -- try again", container.dockStatus.text)
  end)

  -- The note's clock can run out after the player has gone to another tab. The toolbar line is
  -- the whole window's, and Deals was writing its own there by then (review M1).
  it("does not write into another tab's status line when a note runs out", function()
    ready()
    pressRowPost()
    GC.Sell.OnAuctionHouseError(0)
    container:Hide() -- the player went to Deals...
    root.status:SetText("scanning auction house...") -- ...which says what it is doing
    assert.equal(1, fire(10))
    assert.equal("scanning auction house...", root.status.text)
    assert.not_equal("You don't have enough money.", container.dockStatus.text)
  end)

  -- A one-line FontString whose frame was hidden and shown again can come back undrawn, and
  -- SetText with the text it already holds does not redraw it (docs/addon/AGENTS.md, "Text").
  -- Mid-post, renders are held, so coming back to the tab re-set the dock with identical text.
  it("restamps the dock's post lines when the tab comes back mid-post", function()
    ready()
    pressRowPost()
    local calls = {}
    local function record(fs, name)
      local setText, hide, show = fs.SetText, fs.Hide, fs.Show
      function fs:SetText(t) calls[#calls + 1] = name .. ":text:" .. tostring(t); return setText(self, t) end
      function fs:Hide() calls[#calls + 1] = name .. ":hide"; return hide(self) end
      function fs:Show() calls[#calls + 1] = name .. ":show"; return show(self) end
    end
    record(container.dockStatus, "dock")
    local button = container.queueButton
    local setLabel = button.SetLabel
    function button:SetLabel(t) calls[#calls + 1] = "button:" .. tostring(t); return setLabel(self, t) end
    container:Hide()
    GC.Sell.Show()
    local joined = table.concat(calls, "|")
    assert.is_truthy(joined:find("dock:text:|dock:text:Posting…|dock:hide|dock:show", 1, true), joined)
    assert.is_truthy(joined:find("button:|button:POSTING…", 1, true), joined)
    assert.equal("Posting…", container.dockStatus.text)
    assert.equal("POSTING…", container.queueButton.label)
  end)

  -- The client can answer inside the post call itself. The row that answer already gave back
  -- must not be turned into a Confirm, or a watchdog armed for it, by the code after the call.
  it("does not undo an answer that landed while the post call was still running", function()
    postReturn = true
    onPost = function() GC.Sell.OnPostError() end
    ready()
    local row = pressRowPost()
    assert.is_nil(row.postStage)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.enabled)
    -- The watchdog is armed before the call (see above); the answer already let it go.
    fire(8)
    assert.is_nil(row.postStage)
    assert.not_equal("The auction house did not answer -- try again", container.dockStatus.text)
  end)
end)
