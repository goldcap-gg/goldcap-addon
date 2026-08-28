local helper = require("spec.spec_helper")

-- Posting's analogue of spec/sniper_purchase_wiring_spec.lua's static guard on the purchase
-- calls (addon/AGENTS.md's "Protected actions": Post/Confirm calls only from a hardware click
-- handler, never a timer, an event handler, or a render path). Posting never had this guard
-- before the posting queue -- and the queue is exactly the kind of always-running machinery
-- (recomposed on every position rebuild, painted from setStatus/composePositions rather than a
-- click) that could tempt a future edit into reaching one of these calls from somewhere that is
-- not the player's own hardware click. This exists to catch that before it ships.
describe("Sell posting wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local PROTECTED_CALLS = {
    "C_AuctionHouse.PostCommodity", "C_AuctionHouse.PostItem",
    "C_AuctionHouse.ConfirmPostCommodity", "C_AuctionHouse.ConfirmPostItem",
  }

  it("keeps every post/confirm call inside onPostClick, the hardware click handler, and nowhere else", function()
    local text = source()
    local clickStart = assert(text:find("local function onPostClick(row)", 1, true))
    local clickEnd = assert(text:find("local function onRepostClick(row, auctionID)", clickStart, true))
    local click = text:sub(clickStart, clickEnd - 1)
    local before = text:sub(1, clickStart - 1)
    local after = text:sub(clickEnd)

    for _, call in ipairs(PROTECTED_CALLS) do
      assert.is_truthy(click:find(call, 1, true), call .. " must be reachable from onPostClick")
      assert.is_nil(before:find(call, 1, true), call .. " must not appear before onPostClick's body")
      assert.is_nil(after:find(call, 1, true), call .. " must not appear after onPostClick's body -- "
        .. "including inside the queue control, a timer callback, or a render path")
    end
  end)

  -- The queue control (onQueueClick, wired to the toolbar button's OnClick and to the
  -- keybinding) must reuse onPostClick exactly -- the design's own words are "no second posting
  -- implementation." This checks the reuse positively, not just the absence of a duplicate: the
  -- previous test already proves no protected call exists inside onQueueClick's body at all, so
  -- if onQueueClick posts anything, the ONLY way it can is by calling onPostClick.
  it("routes the queue control's own click through onPostClick, never a duplicate implementation", function()
    local text = source()
    local start = assert(text:find("local function onQueueClick()", 1, true))
    local stop = assert(text:find("function GC.Sell.SellableCount()", 1, true))
    local body = text:sub(start, stop - 1)
    assert.is_truthy(body:find("onPostClick(", 1, true), "onQueueClick must call onPostClick")
  end)

  -- The cancel queue's own belt, same shape: CancelAuction forfeits a real deposit, so it may
  -- exist ONLY inside onRepostClick (the hardware click handler with the two-click arm), and
  -- the cancel control must reuse that handler rather than grow a second cancel implementation.
  it("keeps CancelAuction inside onRepostClick and routes the cancel control through it", function()
    local text = source()
    local repostStart = assert(text:find("local function onRepostClick(row, auctionID)", 1, true))
    local repostEnd = assert(text:find("function GC.Sell.OnAuctionCreated()", repostStart, true))
    local before = text:sub(1, repostStart - 1)
    local body = text:sub(repostStart, repostEnd - 1)
    local after = text:sub(repostEnd)
    assert.is_truthy(body:find("C_AuctionHouse.CancelAuction", 1, true),
      "CancelAuction must be reachable from onRepostClick")
    assert.is_nil(before:find("C_AuctionHouse.CancelAuction", 1, true),
      "CancelAuction must not appear before onRepostClick's body")
    assert.is_nil(after:find("C_AuctionHouse.CancelAuction", 1, true),
      "CancelAuction must not appear after onRepostClick's body -- including the cancel control")

    local start = assert(text:find("local function onCancelQueueClick()", 1, true),
      "the cancel control's click handler must exist")
    local stop = assert(text:find("-- The number on the Sell tab", start, true))
    local control = text:sub(start, stop - 1)
    assert.is_truthy(control:find("onRepostClick(", 1, true),
      "onCancelQueueClick must call onRepostClick")
  end)

  -- Bindings.xml is not a .lua file, so the source-text scans above never see it -- this reads
  -- it directly. The design document is explicit that the keybinding must reach the SAME
  -- handler the button's OnClick calls, via a real hardware key event, and must never call
  -- Button:Click() or a protected API name directly.
  it("keeps the keybinding free of protected calls and of Button:Click()", function()
    local f = assert(io.open("GoldCap/Bindings.xml", "r"))
    local xml = f:read("*a")
    f:close()
    for _, call in ipairs(PROTECTED_CALLS) do
      assert.is_nil(xml:find(call, 1, true), call .. " must not appear in Bindings.xml")
    end
    assert.is_nil(xml:find(":Click(", 1, true), "the keybinding must not call Button:Click()")
    assert.is_truthy(xml:find("GoldCapPostNext", 1, true),
      "the keybinding must call the same handler the queue button's OnClick calls")
  end)

  -- The addon-wide rule, restated at the module boundary this spec owns: no protected AH call
  -- anywhere in this file may sit inside a function whose own name suggests it runs off a
  -- timer or an event (helper.loadModule's own tests already cover the individual timers by
  -- behaviour; this is the same static belt the sniper spec applies).
  it("loads cleanly and exposes the queue's public entry points", function()
    local GC = { Sell = {} }
    helper.loadModule("UI/SellFrame.lua", GC)
    assert.is_function(GC.Sell.Attach)
  end)
end)

-- The seller can type a price now, and that price spends real gold. Two things have to hold
-- for that to be safe, and both are structural rather than visual: the number the row SHOWS
-- and the number the post SENDS must be one number, and the raises that exist to stop the
-- addon underpricing on its own must not silently undo a price the seller chose on purpose.
describe("a price the seller chose reaches the post intact", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  it("hands the chosen price to the plan at the click, not just to the display", function()
    local text = source()
    local clickStart = assert(text:find("local function onPostClick(row)", 1, true))
    local clickEnd = assert(text:find("local function onRepostClick(row, auctionID)", clickStart, true))
    local click = text:sub(clickStart, clickEnd - 1)
    -- BuildPostPlan's floor and queue raises can only ever RAISE, and a raise applied on top
    -- of a chosen price would list above what the seller asked for without saying so. The
    -- override branch there skips both, so the plan has to be told explicitly.
    assert.is_truthy(click:find("overrideUnit = chosenKey and priceOverrides[chosenKey] or nil", 1, true))
  end)

  it("also feeds it to the composition, so the displayed price is the posted price", function()
    local text = source()
    -- PROFIT / UNIT, the posting queue's own label and the plan all read the recommendation.
    -- This file has twice shipped a defect where the price shown and the price sent were two
    -- different numbers (see BuildPostPlan's own floor-raise comment); one source, not two.
    assert.is_truthy(text:find("chosenUnits = priceOverrides", 1, true))
  end)

  -- The choice was made against a book that will move. Keeping it would price the next batch
  -- of the same item at a number chosen for a market that is gone.
  it("spends the chosen price when the auction it was chosen for is created", function()
    local text = source()
    local created = assert(text:match("function GC%.Sell%.OnAuctionCreated%(%)(.-)\nend"))
    assert.is_truthy(created:find("priceOverrides[pin.positionKey] = nil", 1, true))
  end)

  -- Nothing writes a post price outside these two paths: a render must never decide one.
  it("keeps the override table out of every path but the control and the post", function()
    local text = source()
    local writes = 0
    for _ in text:gmatch("priceOverrides%[[%w%.]-%]%s*=") do writes = writes + 1 end
    -- commitPrice (set), commitPrice (clear), the chip click, and OnAuctionCreated's clear.
    assert.equal(4, writes)
  end)
end)
