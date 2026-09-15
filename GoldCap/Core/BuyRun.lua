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

local function num(v) return type(v) == "number" and v or nil end

function GC.BuyRun.New(run, driver)
  local obj = {}
  local lines = {}    -- rebuilt by Refresh(), in display order
  local perItem = {}  -- itemID -> { bought, spent, floor, floorAt, boughtAt }; survives Refresh()
  -- What this character has already bought for this run, kept by the driver across sessions
  -- (driver.progress(code) hands back a table the driver persists; nil when it keeps none).
  -- Floors stay in memory -- a price from a previous session is not a quote -- but bought and
  -- spent are the run's score, and a /reload must not read as "nothing bought yet".
  local progress = driver.progress and driver.progress(run.code) or nil

  local function stateFor(itemID)
    local state = perItem[itemID]
    if not state then
      local saved = progress and progress[itemID] or nil
      state = {
        bought = saved and tonumber(saved.bought) or 0,
        spent = saved and tonumber(saved.spent) or 0,
        boughtAt = saved and saved.boughtAt or nil,
      }
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
  -- this frame), `buy` from need/have/bought, and `cap` from the usual price. Lines come
  -- out in three groups -- open, then the vendor trip, then everything already done -- and
  -- keep run order inside each. `index` counts only non-vendor lines, in run order and
  -- regardless of whether they are done, so the free-lines gate is about which lines of the
  -- run are unlocked rather than about what is left of it.
  function obj:Refresh()
    -- The run's code goes with the question: a cap is a property of the run, not of the tab
    -- (UI/BuyFrame.lua's runCapPct). A driver that does not care simply ignores the argument.
    local capPct = driver.capPct(run.code)
    local freeLines = driver.freeLines()
    local open, vendor, done = {}, {}, {}
    local index = 0
    for _, src in ipairs(run.lines or {}) do
      local itemID = src.i
      local state = stateFor(itemID)
      -- The run's own price first: the site knew what this item cost when the list was saved,
      -- and the import's market value is a snapshot of a different moment (or, for an item the
      -- import has never carried, of nothing at all). A zero or a non-number is not a price --
      -- trusted, it caps the line at nothing and the line can never be bought.
      local lineUsual = num(src.u)
      local usual = (lineUsual and lineUsual > 0 and lineUsual) or driver.usualUnit(itemID)
      local vendorUnit = num(src.vu)
      if vendorUnit and vendorUnit <= 0 then vendorUnit = nil end
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
        vendor = isVendor, usual = usual, vendorUnit = vendorUnit,
        -- Hour-of-day (UTC) this item is usually cheapest, and by what percent. Passed through
        -- untouched: whether the client can convert an hour into realm time, and whether the
        -- number is worth saying at all, is the caller's question (UI/BuyFrame.lua).
        cheapHour = num(src.ch), cheapPct = num(src.cp),
        cap = usual and math.floor(usual * capPct / 100) or nil,
        floor = state.floor, floorAt = state.floorAt,
        spent = state.spent, bought = state.bought,
        done = buy == 0, locked = false, index = lineIndex,
      }
      -- The free-lines gate is about the run, not about what is left of it, so `locked` is still
      -- decided by the line's position among the non-vendor lines and nothing else.
      if not isVendor then
        line.locked = freeLines ~= nil and lineIndex > freeLines
      end
      -- Three buckets, in the order the list reads: what is left to buy, then the vendor trip,
      -- then everything already dealt with. A line that is done is done whether or not it is a
      -- vendor stop -- the player has it, so it is not a stop to make. Run order survives inside
      -- each bucket rather than sorting by when a line finished: the run is still the run.
      if line.done then
        done[#done + 1] = line
      elseif isVendor then
        vendor[#vendor + 1] = line
      else
        open[#open + 1] = line
      end
    end
    lines = {}
    for _, bucket in ipairs({ open, vendor, done }) do
      for i = 1, #bucket do lines[#lines + 1] = bucket[i] end
    end
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
    if progress then
      progress[itemID] = { bought = state.bought, spent = state.spent, boughtAt = at }
    end
    local line = findLine(itemID)
    if line then
      line.bought = state.bought
      line.spent = state.spent
      line.buy = math.max(line.need - math.max(line.have, state.bought), 0)
      line.done = line.buy == 0
    end
  end

  -- `left` counts open, unlocked lines: a done line has nothing left to spend and a locked
  -- line is not yet buyable, so its cost is not part of "what this run needs right now". A
  -- vendor line counts at the vendor's price -- see below.
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
      if not line.done and not line.locked then
        -- A vendor line is priced at the vendor's own price -- it never touches the auction
        -- house, so a floor or a market value would be a number from the wrong market. With no
        -- vendor price it counts nothing, the same way a line with no price at all does.
        if line.vendor then
          left = left + line.buy * (line.vendorUnit or 0)
        else
          left = left + line.buy * (line.floor or line.usual or 0)
        end
      end
    end
    return { spent = spent, left = left, toBuy = toBuy, atVendor = atVendor, done = done, lines = #lines }
  end

  return obj
end
