local _, GC = ...

-- The Buy tab's shopping run as pure data: given a run (the AppRuns shape -- an ordered
-- list of items with a wanted quantity, sourced from the site's crafting/shopping-list
-- export) and a driver for the three things only the client knows (how many the player
-- already carries, what an item usually costs, and today's free-tier line limit), this
-- module is the arithmetic the BUY tab draws: what is left to buy, what it should cost,
-- and how far a purchase's ladder of price levels reaches before the price cap says stop.
--
-- Pure and driver-injected like Core/KeyPoll.lua and Core/BookPass.lua: no WoW API call
-- lives here, and no text -- callers own every string the player reads.
GC.BuyRun = {}

function GC.BuyRun.New(run, driver)
  local obj = {}
  local lines = {}    -- rebuilt by Refresh(), in display order
  local perItem = {}  -- itemID -> { bought, spent, floor, floorAt, boughtAt }; survives Refresh()

  local function stateFor(itemID)
    local state = perItem[itemID]
    if not state then
      state = { bought = 0, spent = 0 }
      perItem[itemID] = state
    end
    return state
  end

  local function findLine(itemID)
    for i = 1, #lines do
      if lines[i].itemID == itemID then return lines[i] end
    end
    return nil
  end

  function obj:Code() return run.code end
  function obj:Name() return run.name end

  -- Rebuilds every line from the run plus current state: `have` comes fresh from the
  -- driver every time (the bag count can change any moment the player isn't looking at
  -- this frame), `buy` from need/have/bought, and `cap` from the usual price. Vendor
  -- lines move to the end so the list reads "buy this, then the vendor stuff"; everything
  -- else keeps run order, including a line that is already done -- it stays where the run
  -- put it rather than sorting to the bottom. `index` counts only non-vendor lines, in
  -- that same run order, so the free-lines gate never sees (and never locks) a vendor line.
  function obj:Refresh()
    local capPct = driver.capPct()
    local freeLines = driver.freeLines()
    local nonVendor, vendor = {}, {}
    local index = 0
    for _, src in ipairs(run.lines or {}) do
      local itemID = src.i
      local state = stateFor(itemID)
      local usual = driver.usualUnit(itemID)
      local need = src.q or 0
      local have = driver.haveOf(itemID)
      -- The LARGER of the two, never their sum. `have` and `bought` are two views of the same
      -- units the moment a purchase is delivered -- the buyer's bags hold what they just bought --
      -- so subtracting both counted every purchase twice: a line needing 10 that filled 6 read
      -- have 6, bought 6, buy 0, done, and the four it still needed could never be bought again.
      -- They are kept apart rather than merged because each answers on its own: `bought` survives
      -- the units being used or mailed away, `have` covers stock that was never bought here.
      local buy = need - math.max(have, state.bought)
      if buy < 0 then buy = 0 end
      local isVendor = src.v == true
      local lineIndex = nil
      if not isVendor then
        index = index + 1
        lineIndex = index
      end
      local line = {
        itemID = itemID, name = src.n, need = need, have = have, buy = buy,
        vendor = isVendor, usual = usual,
        cap = usual and math.floor(usual * capPct / 100) or nil,
        floor = state.floor, floorAt = state.floorAt,
        spent = state.spent, bought = state.bought,
        done = buy == 0, locked = false, index = lineIndex,
      }
      if isVendor then
        vendor[#vendor + 1] = line
      else
        line.locked = freeLines ~= nil and lineIndex > freeLines
        nonVendor[#nonVendor + 1] = line
      end
    end
    lines = nonVendor
    for i = 1, #vendor do lines[#lines + 1] = vendor[i] end
  end

  function obj:Lines() return lines end

  -- A floor learned from a keys batch or a manual search: the best price actually seen for
  -- this item, which Totals() prefers over the usual price the moment it exists.
  function obj:SetFloor(itemID, unitCopper, at)
    local state = stateFor(itemID)
    state.floor = unitCopper
    state.floorAt = at
    local line = findLine(itemID)
    if line then
      line.floor = unitCopper
      line.floorAt = at
    end
  end

  -- Walks a commodity price ladder (cheapest level first), taking units until the line's
  -- need is met or the next level's unit price exceeds the cap -- a line with no usual
  -- price has no cap and simply buys the whole need. This only estimates; it records
  -- nothing, so the caller commits with RecordPurchase once the real purchase succeeds.
  function obj:PurchaseQuantity(itemID, ladder)
    local line = findLine(itemID)
    if not line or line.buy <= 0 then return 0, 0, false end
    local need = line.buy
    local qty, total, capped = 0, 0, false
    for _, level in ipairs(ladder or {}) do
      if qty >= need then break end
      if line.cap and level.unit > line.cap then
        capped = true
        break
      end
      local take = math.min(level.qty, need - qty)
      qty = qty + take
      total = total + take * level.unit
    end
    return qty, total, capped
  end

  -- Commits a purchase. `bought` accumulates across the whole run (a partial buy today,
  -- more tomorrow), so `buy` is recomputed from it with the same formula Refresh() uses --
  -- max(have, bought), see there -- rather than decremented: the two must never drift apart.
  function obj:RecordPurchase(itemID, qty, totalCopper, at)
    local state = stateFor(itemID)
    state.bought = state.bought + qty
    state.spent = state.spent + totalCopper
    state.boughtAt = at
    local line = findLine(itemID)
    if line then
      line.bought = state.bought
      line.spent = state.spent
      line.buy = math.max(line.need - math.max(line.have, state.bought), 0)
      line.done = line.buy == 0
    end
  end

  -- `left` only counts open, unlocked, non-vendor lines -- a vendor line costs nothing to
  -- price here, a done line has nothing left to spend, and a locked line is not yet buyable
  -- so its cost isn't part of "what this run needs right now".
  function obj:Totals()
    local spent, left, toBuy, atVendor, done = 0, 0, 0, 0, 0
    for _, line in ipairs(lines) do
      spent = spent + line.spent
      if line.done then
        done = done + 1
      elseif line.vendor then
        atVendor = atVendor + 1
      else
        toBuy = toBuy + 1
      end
      if not line.vendor and not line.done and not line.locked then
        left = left + line.buy * (line.floor or line.usual or 0)
      end
    end
    return { spent = spent, left = left, toBuy = toBuy, atVendor = atVendor, done = done, lines = #lines }
  end

  return obj
end
