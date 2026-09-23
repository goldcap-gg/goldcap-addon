describe("Sell quote and action wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  it("only derives rows from positions and keeps latest quotes display-only", function()
    local text = source()
    assert.is_truthy(text:find("GC.SellPositions.Build({", 1, true))
    -- A Sell quote is judged against the tab's own window, not the Sniper's 10s:
    -- a purchase commits gold against one price point, a listing competes over
    -- hours, and a 10s window made Post unclickable.
    -- By the position's quote id: an item-level variant is priced from its own key.
    assert.is_truthy(text:find(
      "GC.QuoteCache.Fresh(quotes, position.quoteKey or position.itemID, time(), SELL_QUOTE_ACTION_AGE)", 1, true))
    -- Dated from the ASK, not from the moment the reply was processed: the results events carry
    -- no request identifier, so a late reply can still be credited to a re-ask of the same item
    -- once the drain fence has lifted. Stamping with pending.at can only make a quote look older
    -- than it is, never fresher -- so the worst case is a re-ask, not a post at a dead price.
    assert.is_truthy(text:find("GC.QuoteCache.Set(quotes, itemID, unit, pending.at or time())", 1, true))
    assert.is_nil(text:find("GC.Data.GetFlips", 1, true))
  end)

  it("fails closed on stale quotes before protected post or cancel calls", function()
    local text = source()
    local post = assert(text:match("local function onPostClick%(row%)(.-)local function onRepostClick"))
    local repost = assert(text:match("local function onRepostClick%(row, auctionID%)(.-)function GC%.Sell%.OnAuctionCreated"))
    assert.is_truthy(post:find("if not quote then", 1, true))
    assert.is_truthy(post:find("GC.SellPositions.BuildPostPlan", 1, true))
    assert.is_truthy(repost:find("if not quote then", 1, true))
    assert.is_truthy(repost:find("GC.SellPositions.BuildRepostPlan", 1, true))
    assert.is_truthy(repost:find("C_AuctionHouse.CancelAuction(plan.auctionID)", 1, true))
    assert.is_truthy(text:find("C_AuctionHouse.ConfirmPostCommodity", 1, true))
    assert.is_truthy(text:find("C_AuctionHouse.ConfirmPostItem", 1, true))
  end)

  it("uses exact live bag identity and leaves ambiguous normal variants without an action", function()
    local text = source()
    -- Keyed exactly as the bag scan keyed it: the link where it can say, else the slot's own
    -- ItemKey (GC.Sell._SlotKey), so Post pins the very stack the row stands for.
    assert.is_truthy(text:find("GC.Sell._SlotKey(position.itemID, link, bag, slot) == position.positionKey", 1, true))
    assert.is_truthy(text:find("exactQty = total", 1, true))
    assert.is_truthy(text:find("reason == \"ambiguous_variant\"", 1, true))
  end)

  it("records manual cost only from the dialog confirmation handler", function()
    local text = source()
    local confirm = assert(text:match("local function confirmCostDialog%(dialog%)(.-)local function shownColumns"))
    assert.is_truthy(confirm:find("GC.Acquisitions.RecordManual", 1, true))
    assert.is_truthy(confirm:find("Enter a whole quantity", 1, true))
    assert.is_truthy(confirm:find("Quantity exceeds missing units", 1, true))
    assert.is_truthy(confirm:find("Enter an exact positive cost", 1, true))
  end)
end)
