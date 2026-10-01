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

  local CLICK = "local function planBuyClick"
  local CLICK_END = "local function planBuyButton"

  -- The click's plan and nothing else: planBuyButton, the next function down, begins the two
  -- handlers that hand it to the client, so this slice cannot quietly widen to cover an event
  -- handler that grew a purchase call later.
  local function clickHandler(text)
    local from = assert(text:find(CLICK, 1, true), CLICK)
    local to = assert(text:find(CLICK_END, from + #CLICK, true), CLICK_END)
    return text:sub(from, to - 1), from, to
  end

  local function code(text) return (text:gsub("%-%-[^\n]*", "")) end

  -- The guard below is only as strong as that slice is narrow. A function declared after
  -- planBuyClick but before planBuyButton would be swallowed by it.
  it("slices the click handler alone", function()
    local click = clickHandler(source())
    assert.is_nil(click:find("\nlocal function ", 1, true))
    assert.is_nil(click:find("\nfunction ", 1, true))
  end)

  -- WoW: Forever. The protected calls themselves are made by GC.PurchaseCall.Click
  -- (Core/PurchaseCall.lua), straight from the click, from what the plan answers; this file
  -- names neither of them anywhere, so nothing here can make one outside a click.
  it("keeps both protected purchase calls inside the hardware-click handler", function()
    local text = code(source())
    assert.is_nil(text:find("StartCommoditiesPurchase", 1, true))
    assert.is_nil(text:find("ConfirmCommoditiesPurchase", 1, true))

    local click = clickHandler(text)
    assert.is_truthy(click:find('return "start", attempt.itemID, attempt.qty, function()', 1, true))
    assert.is_truthy(click:find('return "confirm", attempt.itemID, attempt.qty, function()', 1, true))

    -- The plan reaches the client only through the button's click and the Enter key, each of
    -- which hands the whole click to GC.PurchaseCall.Click as its only statement.
    local handlers = {}
    for name in text:gmatch("GC%.PurchaseCall%.Click%((%w+)") do handlers[#handlers + 1] = name end
    assert.same({ "planBuyButton", "planBuyKey" }, handlers)
    assert.is_truthy(text:find("local function onBuyButtonClick(button)\n  GC.PurchaseCall.Click(planBuyButton, button)\nend", 1, true))
    assert.is_truthy(text:find("local function onBuyKey(self, key)\n  GC.PurchaseCall.Click(planBuyKey, self, key)\nend", 1, true))
    local function sites(name)
      local found = {}
      for line in text:gmatch("[^\n]*%f[%w_]" .. name .. "%f[^%w_][^\n]*") do
        found[#found + 1] = line:match("^%s*(.-)%s*$")
      end
      return found
    end
    -- BUY 2.0: the one purchase button is the dock's (createDock); no row carries one.
    assert.same({ "local function onBuyButtonClick(button)", 'dock.buy:SetScript("OnClick", onBuyButtonClick)' },
      sites("onBuyButtonClick"))
    assert.same({ "local function onBuyKey(self, key)", 'container:SetScript("OnKeyDown", onBuyKey)' },
      sites("onBuyKey"))
    assert.same({ "local function planBuyClick(line, fromDock)",
      "return planBuyClick(lineFor(button:GetParent().lineItemID), true)",
      "return planBuyClick(line)" }, sites("planBuyClick"))
  end)

  -- The confirm is a click, not a convenience. The client only demands a hardware event for
  -- Start, so an addon may legally confirm straight from the price-update event -- and this one
  -- never will: a confirm nobody asked for is gold spent by a timer. The test above already
  -- keeps every purchase call out of the event handlers; what is left is a callback declared
  -- INSIDE the click handler, which is where the watchdog lives.
  it("never confirms from a timer", function()
    local text = source()
    local timers = 0
    for body in text:gmatch("C_Timer%.After%b()") do
      timers = timers + 1
      assert.is_nil(body:find("ConfirmCommoditiesPurchase", 1, true))
      assert.is_nil(body:find("StartCommoditiesPurchase", 1, true))
      assert.is_nil(body:find("PurchaseCall", 1, true))
      assert.is_nil(body:find("planBuy", 1, true))
    end
    -- A gmatch that matched nothing would pass this in silence; the stall watchdog is armed
    -- through one of these.
    assert.is_true(timers >= 1)
  end)

  -- The row menu is the one place other than the BUY button where a click reaches this file's
  -- own code. It writes a flag and re-renders; it must never be a second way to spend gold --
  -- and it is not a hardware-click handler the client would let it from anyway.
  it("never reaches a purchase call from a context menu", function()
    local text = source()
    local menus = 0
    for body in text:gmatch("CreateContextMenu%b()") do
      menus = menus + 1
      assert.is_nil(body:find("CommoditiesPurchase", 1, true))
      assert.is_nil(body:find("planBuy", 1, true))
      assert.is_nil(body:find("PurchaseCall", 1, true))
    end
    -- A gmatch that matched nothing would pass this in silence: the run picker's menu and the
    -- row's own are both opened through one of these.
    assert.is_true(menus >= 2)
  end)

  -- The dock's second button cancels a quote or skips a line. Neither is a purchase, and it must
  -- never become a second way to spend gold.
  it("never reaches a purchase call from the dock's second button", function()
    local text = code(source())
    local from = assert(text:find("local function onDockSecondaryClick", 1, true))
    local to = assert(text:find("\nend\n", from, true))
    local body = text:sub(from, to)
    assert.is_nil(body:find("PurchaseCall", 1, true))
    assert.is_nil(body:find("planBuy", 1, true))
    assert.is_nil(body:find("CommoditiesPurchase", 1, true))
    assert.is_truthy(text:find('dock.second:SetScript("OnClick", onDockSecondaryClick)', 1, true))
  end)

  -- RAISE CAP is decided inside the click's plan, but only on the branch that makes no protected
  -- call: nothing it reads is read on a click that starts or confirms a purchase.
  it("raises a cap only on a click that makes no purchase call", function()
    local click = clickHandler(code(source()))
    local raise = assert(click:find("if fromDock and raiseOffered(line) then", 1, true))
    local start = assert(click:find('return "start"', 1, true))
    local confirm = assert(click:find('return "confirm"', 1, true))
    assert.is_true(raise > confirm)
    assert.is_true(raise < start)
    local branch = click:sub(raise, (click:find("\n    end\n", raise, true)))
    assert.is_nil(branch:find("return \"", 1, true))
  end)

  -- BUY 2.0 week 2: a gear line's one lot per press is PlaceBid, answered from inside the same click
  -- plan as the commodity calls, after the shared slot's claim; this file never names the call.
  it("answers a gear line's bid only from inside the click, after the slot claim", function()
    local click = clickHandler(code(source()))
    local bid = assert(click:find('return "bid", lot.auctionID, lot.buyout, function()', 1, true))
    local claim = assert(click:find('GC.PurchaseSlot.Claim("buy"', 1, true))
    assert.is_true(claim < bid)
    assert.is_nil(code(source()):find("PlaceBid", 1, true))
  end)

  it("claims the shared purchase slot before it starts anything", function()
    local click = clickHandler(source())
    local claim = assert(click:find('GC.PurchaseSlot.Claim("buy"', 1, true))
    local start = assert(click:find('return "start"', 1, true))
    assert.is_true(claim < start)
  end)

  -- Every handler here is dead code unless Core/Init.lua actually calls it, and the close path is
  -- the one that was missing: an attempt that outlives the session owing it an answer holds the
  -- shared slot and keeps OwnsCommodityPurchase true until /reload. Static, the way
  -- spec/purchase_capture_wiring_spec.lua pins the same contract for the passive capture.
  it("is routed from the event frame, including both ways out of a session", function()
    local f = assert(io.open("GoldCap/Core/Init.lua", "r"))
    local init = f:read("*a")
    f:close()
    for _, method in ipairs({ "OnCommodityResults", "OnCommodityPriceUpdated",
                              "OnCommodityPriceUnavailable", "OnCommodityPurchaseSucceeded",
                              "OnCommodityPurchaseFailed", "OnAuctionHouseClosed",
                              "OnAuctionHouseShow", "OnBagsChanged", "OnItemResults",
                              "OnPurchaseCompleted", "OnAuctionHouseError" }) do
      assert.is_truthy(init:find("GC.Buy." .. method, 1, true), method)
    end

    -- The four terminal commodity events are OFFERED to this tab and only passed on when it says
    -- it did not take them. Gated on slot ownership instead, the branch that books the late
    -- success of a confirm BUY gave up on is unreachable: BUY released the slot on its way out,
    -- so the event went to the Sniper -- where it could even eat the Sniper's own stranded record.
    for _, method in ipairs({ "OnCommodityPriceUpdated", "OnCommodityPriceUnavailable",
                              "OnCommodityPurchaseSucceeded", "OnCommodityPurchaseFailed" }) do
      assert.is_truthy(init:find("if not (GC.Buy and GC.Buy." .. method, 1, true), method)
    end
    -- Comments stripped first, the way spec/ui_widget_field_spec.lua does it: the line ABOVE the
    -- routing explains why the old gate is gone, and would otherwise match here.
    assert.is_nil((init:gsub("%-%-[^\n]*", "")):find('GC.PurchaseSlot.Owner() == "buy"', 1, true))
    -- The Auctioneer frame hiding and AUCTION_HOUSE_CLOSED are separate events, and either can be
    -- the last one a session gets.
    local first = assert(init:find("GC.Buy.OnAuctionHouseClosed()", 1, true))
    assert.is_truthy(init:find("GC.Buy.OnAuctionHouseClosed()", first + 1, true))
  end)

  -- The hover quote and the NOW refresh batch are two consumers of one throttled message system.
  -- Under a stuck ready flag GC.Util paces one forced send per consumer NAME, so sharing "buy"
  -- would have the board's own refresh and the player's hover taking turns in a single window.
  it("claims its own throttle window for the hover quote", function()
    local text = source()
    assert.is_truthy(text:find('ClaimThrottleSend("buy-quote")', 1, true))
    -- The hover's look at another line's book is a third consumer, with a window of its own.
    assert.is_truthy(text:find('ClaimThrottleSend("buy-look")', 1, true))
    assert.is_nil(text:find('ClaimThrottleSend("buy")', 1, true))
  end)

  -- Terminal commodity events route by whoever owns the shared slot (Core/Init.lua), and the
  -- sniper's own drain releases its slot while a late event can still be on its way -- so every
  -- handler here has to check its own attempt's stage before acting. The behaviour is covered in
  -- spec/buy_purchase_spec.lua; this pins that the guard is written at all.
  it("guards every terminal handler on the attempt's own stage", function()
    local text = source()
    for _, name in ipairs({ "OnCommodityResults", "OnCommodityPriceUpdated",
                            "OnCommodityPurchaseSucceeded", "OnCommodityPurchaseFailed",
                            "OnCommodityPriceUnavailable", "OnAuctionHouseClosed" }) do
      local from = assert(text:find("function GC.Buy." .. name, 1, true), name)
      local next_ = text:find("\nfunction ", from + 1, true) or #text
      local body = text:sub(from, next_)
      assert.is_truthy(body:find("stage", 1, true), name .. " does not look at the attempt's stage")
    end
  end)
end)
