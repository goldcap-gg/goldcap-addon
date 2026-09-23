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
  local GC, root, render, container, timers, posts, postReturn, onPost, bags, postedSlots, auctions

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
  local CLIENT_ERRORS = { [0] = "You don't have enough money." }

  local GREEN, RED, MUTED = { 0, 1, 0 }, { 1, 0, 0 }, { .72, .71, .69 }

  before_each(function()
    timers, posts, postReturn, onPost, bags, postedSlots, auctions = {}, 0, false, nil, BAGS, {}, {}
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
      PostCommodity = function(location)
        posts = posts + 1
        postedSlots[#postedSlots + 1] = location.slot
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
    _G.AuctionHouseUtil, _G.AUCTION_POSTING_ERROR_TEXT = nil, nil
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
    it("gives the row back and says the auction house did not answer", function()
      ready()
      local row = pressRowPost()
      assert.equal(1, fire(8))
      assert.equal("The auction house did not answer -- try again", container.dockStatus.text)
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

    it("is still the post's: recorded like one on time, and the dock says Posted over the timeout", function()
      local recorded = recordedPosts()
      ready()
      pressRowPost()
      assert.equal(1, fire(8))
      assert.equal("The auction house did not answer -- try again", container.dockStatus.text)
      assert.equal(0, #recorded)
      _G.time = function() return 1030 end
      GC.Sell.OnAuctionCreated()
      assert.equal(1, #recorded)
      assert.equal(23427, recorded[1][2])
      assert.equal(246, recorded[1][6])
      assert.matches("^Posted", container.dockStatus.text)
      assert.matches("Eternium Ore ×246", container.dockStatus.text, 1, true)
      assert.same(GREEN, { unpack(container.dockStatus.color, 1, 3) })
      -- Once: a second creation is not the same post over again.
      GC.Sell.OnAuctionCreated()
      assert.equal(1, #recorded)
    end)

    it("corrects an unrelated auction house error that freed the row", function()
      local recorded = recordedPosts()
      ready()
      pressRowPost()
      GC.Sell.OnAuctionHouseError(0)
      assert.equal("You don't have enough money.", container.dockStatus.text)
      -- Meanwhile the stack is not sent again: the post the error may not have been about can
      -- still be taking it.
      pressRowPost()
      assert.equal(1, posts)
      assert.equal("Still waiting for the auction house to answer the last post", container.dockStatus.text)
      GC.Sell.OnAuctionCreated()
      assert.equal(1, #recorded)
      assert.matches("^Posted", container.dockStatus.text)
    end)

    it("holds another Post of the same item while its last post may still be answered", function()
      ready()
      pressRowPost()
      fire(8)
      pressRowPost()
      assert.equal(1, posts)
      assert.equal("Still waiting for the auction house to answer the last post", container.dockStatus.text)
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
      assert.equal(1, #recorded)
      assert.equal(23427, recorded[1][2])
      assert.equal("posting", myco.postStage) -- still waiting for its own answer
      assert.is_true(myco.action.busy)
      assert.matches("^Posted", container.dockStatus.text)
      -- Its moment over, the dock is back on the post still out, not on the walk.
      assert.equal(1, fire(1.5))
      assert.equal("Posting…", container.dockStatus.text)
      auctions[502] = 210796
      GC.Sell.OnAuctionCreated(502)
      assert.equal(2, #recorded)
      assert.equal(210796, recorded[2][2])
      assert.is_nil(myco.postStage)
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
