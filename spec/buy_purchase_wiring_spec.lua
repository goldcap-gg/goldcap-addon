require("spec.spec_helper")

-- The BUY tab spends gold, so it gets the same static audit UI/SniperFrame.lua's purchase path
-- has (spec/sniper_purchase_wiring_spec.lua): the two protected C_AuctionHouse purchase calls
-- must be reachable ONLY from the player's own hardware click handler. A behavioural test
-- cannot prove that -- taint is a client rule with no headless equivalent -- so the source text
-- itself is the contract.
describe("BUY purchase wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/BuyFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local CLICK = "local function onBuyClick"
  local CLICK_END = "-- ---------------------------------------------------------------------------\n-- Rows"

  -- Exactly onBuyClick and nothing else: the handler is deliberately the last thing in its own
  -- section, so this slice cannot quietly widen to cover an event handler that grew a purchase
  -- call later.
  local function clickHandler(text)
    local from = assert(text:find(CLICK, 1, true), CLICK)
    local to = assert(text:find(CLICK_END, from + #CLICK, true), CLICK_END)
    return text:sub(from, to - 1), from, to
  end

  it("keeps both protected purchase calls inside the hardware-click handler", function()
    local text = source()
    local click, from, to = clickHandler(text)

    assert.is_truthy(click:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))

    local before, after = text:sub(1, from - 1), text:sub(to)
    assert.is_nil(before:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
  end)

  -- The confirm is a click, not a convenience. The client only demands a hardware event for
  -- Start, so an addon may legally confirm straight from the price-update event -- and this one
  -- never will: a confirm nobody asked for is gold spent by a timer. The test above already
  -- keeps every purchase call out of the event handlers; what is left is a callback declared
  -- INSIDE the click handler, which is where the watchdog lives.
  it("never confirms from a timer", function()
    local click = clickHandler(source())
    local timers = 0
    for body in click:gmatch("C_Timer%.After%b()") do
      timers = timers + 1
      assert.is_nil(body:find("ConfirmCommoditiesPurchase", 1, true))
      assert.is_nil(body:find("StartCommoditiesPurchase", 1, true))
    end
    -- A gmatch that matched nothing would pass this in silence; the watchdog is armed here.
    assert.is_true(timers >= 1)
  end)

  it("claims the shared purchase slot before it starts anything", function()
    local click = clickHandler(source())
    local claim = assert(click:find('GC.PurchaseSlot.Claim("buy"', 1, true))
    local start = assert(click:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_true(claim < start)
  end)

  -- Terminal commodity events route by whoever owns the shared slot (Core/Init.lua), and the
  -- sniper's own drain releases its slot while a late event can still be on its way -- so every
  -- handler here has to check its own attempt's stage before acting. The behaviour is covered in
  -- spec/buy_purchase_spec.lua; this pins that the guard is written at all.
  it("guards every terminal handler on the attempt's own stage", function()
    local text = source()
    for _, name in ipairs({ "OnCommodityResults", "OnCommodityPriceUpdated",
                            "OnCommodityPurchaseSucceeded", "OnCommodityPurchaseFailed",
                            "OnCommodityPriceUnavailable" }) do
      local from = assert(text:find("function GC.Buy." .. name, 1, true), name)
      local next_ = text:find("\nfunction ", from + 1, true) or #text
      local body = text:sub(from, next_)
      assert.is_truthy(body:find("stage", 1, true), name .. " does not look at the attempt's stage")
    end
  end)
end)
