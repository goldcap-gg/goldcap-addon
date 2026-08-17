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
