describe("Grouped Sell wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  it("composes positions, remembers expansion by position key, and uses the grouped columns", function()
    local text = source()
    assert.is_truthy(text:find("GC.SellPositions.Build", 1, true))
    assert.is_truthy(text:find("expanded[position.positionKey]", 1, true))
    -- Per-unit columns, plus a dedicated `action` column. The button used to be drawn on top of
    -- `status`, which erased the recommendation -- the only place the target price is written.
    -- `listed` is the optional column now: its total is already in the summary, while the market
    -- price is what every decision on this screen turns on.
    -- `min` is the width a numeric column shrinks to before ANY column is dropped: without
    -- it the layout went straight from full width to losing COST/UNIT, and at the default
    -- 720-wide window it lost it -- a market price and a profit with nothing on screen saying
    -- what either was measured against.
    assert.is_truthy(text:find('{ key = "cost", w = 92, min = 72, num = true }', 1, true))
    assert.is_truthy(text:find('{ key = "listed", w = 88, num = true, optional = true }', 1, true))
    assert.is_truthy(text:find('{ key = "market", w = 92, min = 72, num = true }', 1, true))
    assert.is_truthy(text:find('{ key = "profit", w = 96, min = 76, num = true, bold = true }', 1, true))
    assert.is_truthy(text:find('{ key = "status", w = 176 }', 1, true))
    assert.is_truthy(text:find('{ key = "action", w = 88 }', 1, true))
    assert.is_nil(text:find("BuildRow", 1, true))
    assert.is_nil(text:find("OrphanLotRows", 1, true))
  end)

  it("uses one owned-auctions refresh followed by the sequential quote walk", function()
    local text = source()
    local refresh = assert(text:match("function GC%.Sell%.Refresh%(automatic%)(.-)function GC%.Sell%.Reset"))
    assert.is_truthy(refresh:find("requestOwnedAuctions()", 1, true))
    assert.is_truthy(refresh:find("refresh.phase", 1, true))
    assert.is_truthy(text:find("Refreshing listings…", 1, true))
    assert.is_truthy(text:find("Pricing %d/%d…", 1, true))
  end)
end)
