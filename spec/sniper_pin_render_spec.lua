local helper = require("spec.spec_helper")

-- renderList() appends a placeholder row for any watch pin whose item is not currently a deal
-- (see the comment at its own site: "a pin is not a roach motel"). But refreshRows() only ever
-- renders list[1..WIN.ROW_CAP] -- on a busy realm where WIN.ROW_CAP deals already survive the
-- refused-rows filter, a placeholder appended after them lands past the cut and never gets a
-- row. A pin is removed by right-clicking its row, so a pin with no row can never be unpinned.
describe("Sniper pin row reservation", function()
  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function loadSniper(GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
  end

  -- Reach renderList through the exact same closure chain the purchase-wiring specs already
  -- use (clearDeals -> refreshRows), rather than duplicating its logic in the fixture.
  local function renderListOf(GC)
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local renderList = getUpvalue(refreshRows, "renderList")
    local WIN = getUpvalue(refreshRows, "WIN")
    local sortedDeals = getUpvalue(renderList, "sortedDeals")
    local deals = getUpvalue(sortedDeals, "deals")
    return renderList, deals, WIN
  end

  local function positionOf(list, itemID)
    for i, entry in ipairs(list) do
      if entry.itemID == itemID then return i end
    end
    return nil
  end

  it("still gives an unpinned-from-the-list pin a row once the deal count clears the cap", function()
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
      db = { settings = { sniper = { watchPins = { 99999 } } } },
    }
    loadSniper(GC)
    local renderList, deals, WIN = renderListOf(GC)

    -- More deals than WIN.ROW_CAP, none of them the pin -- the placeholder this creates would,
    -- pre-fix, be appended after all of them and fall past the truncation refreshRows applies.
    for i = 1, WIN.ROW_CAP + 5 do
      deals[i] = { itemID = i, tier = "WATCH", profit = 100000 - i, unitPrice = 100, qty = 1 }
    end

    local list = renderList()
    assert.is_true(#list > WIN.ROW_CAP) -- the list itself is not truncated; refreshRows does that

    local pos = positionOf(list, 99999)
    assert.is_not_nil(pos, "pin placeholder missing from renderList() output entirely")
    assert.is_true(pos <= WIN.ROW_CAP,
      ("pin landed at position %d, past the %d rows refreshRows actually renders"):format(pos, WIN.ROW_CAP))

    local placeholder = list[pos]
    assert.is_true(placeholder.pinPlaceholder)
  end)

  it("still gives a real (non-placeholder) pinned deal a row when it sorts below the cap", function()
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
      db = { settings = { sniper = { watchPins = { 1 } } } },
    }
    loadSniper(GC)
    local renderList, deals, WIN = renderListOf(GC)

    -- The pin IS in the deal list, but sorts last (lowest profit): without reservation it would
    -- be exactly the entry truncation drops.
    deals[1] = { itemID = 1, tier = "WATCH", profit = 1, unitPrice = 100, qty = 1 }
    for i = 2, WIN.ROW_CAP + 5 do
      deals[i] = { itemID = i, tier = "WATCH", profit = 100000 - i, unitPrice = 100, qty = 1 }
    end

    local list = renderList()
    local pos = positionOf(list, 1)
    assert.is_not_nil(pos)
    assert.is_true(pos <= WIN.ROW_CAP)
    assert.is_nil(list[pos].pinPlaceholder) -- the real deal, not a synthesized placeholder
  end)

  it("sorts pinned rows to the top even when the list does not reach the cap", function()
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
      db = { settings = { sniper = { watchPins = { 1 } } } },
    }
    loadSniper(GC)
    local renderList, deals = renderListOf(GC)

    deals[1] = { itemID = 1, tier = "WATCH", profit = 1, unitPrice = 100, qty = 1 } -- the pin, lowest profit
    deals[2] = { itemID = 2, tier = "WATCH", profit = 500, unitPrice = 100, qty = 1 }
    deals[3] = { itemID = 3, tier = "WATCH", profit = 300, unitPrice = 100, qty = 1 }

    local list = renderList()
    -- The pin partition is unconditional (see renderList's own comment): the watched item
    -- leads the board even though it sorts last by profit -- that reorder is the immediate,
    -- unmissable feedback that the right-click landed. The rest keeps profit order.
    assert.same({ 1, 2, 3 }, { list[1].itemID, list[2].itemID, list[3].itemID })
  end)
end)
