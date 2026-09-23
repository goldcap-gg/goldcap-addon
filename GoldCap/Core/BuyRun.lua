local _, GC = ...

-- The Buy tab's shopping run as pure data: given a run (the AppRuns shape -- an ordered
-- list of items with a wanted quantity, sourced from the site's crafting/shopping-list
-- export) and a driver for the two things only the client knows (how many the player
-- already carries and what an item usually costs), this module is the arithmetic the BUY
-- tab draws: what is left to buy, what it should cost, and how far a purchase's ladder of
-- price levels reaches before the price cap says stop.
--
-- Pure and driver-injected like Core/KeyPoll.lua and Core/BookPass.lua: no WoW API call
-- lives here, and no text -- callers own every string the player reads.
GC.BuyRun = {}

local function num(v) return type(v) == "number" and v or nil end

-- The recipe the site attached to a line (Core/AppRuns.lua's `cr`), normalised once into names
-- the rest of this module and UI/BuyFrame.lua read. nil unless it is complete enough to act on:
-- a recipe yielding nothing, or naming no reagent, is not a craft anybody can plan.
local function craftOf(raw)
  if type(raw) ~= "table" then return nil end
  local craftedQty = num(raw.n)
  if not craftedQty or craftedQty <= 0 then return nil end
  local reagents = {}
  for _, entry in ipairs(type(raw.i) == "table" and raw.i or {}) do
    local itemID, qty = num(entry.i), num(entry.q)
    if itemID and qty and qty > 0 then
      reagents[#reagents + 1] = {
        itemID = itemID, qty = qty, name = type(entry.n) == "string" and entry.n or nil,
        vendor = entry.v == true, usual = num(entry.u), vendorUnit = num(entry.vu),
      }
    end
  end
  if #reagents == 0 then return nil end
  return { recipeID = num(raw.r), craftedQty = craftedQty, cost = num(raw.c) or 0,
           reagents = reagents }
end

-- The ceiling one unit of this line may cost: its own, in copper, when the site sent one;
-- otherwise the run's cap percent applied to the reference price, which is what every line
-- without one has always used. A zero or a negative is not a ceiling -- trusted, it caps the
-- line at nothing and nothing can ever be bought.
local function capFor(src, usual, capPct)
  local absolute = num(src.cc)
  if absolute and absolute > 0 then return math.floor(absolute) end
  return usual and math.floor(usual * capPct / 100) or nil
end

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

  -- One entry per run line, before any split has had its say: everything that comes straight off
  -- the run, plus the two counts the split arithmetic needs (what the character has, and what
  -- this run has already bought). The derived numbers -- buy, cap, done, the free-line gate --
  -- are NOT computed here: a reagent that lands on a line the run already had changes that
  -- line's NEED, so anything derived from NEED has to wait until the splits are in.
  local function baseEntries()
    local entries, byItem = {}, {}
    for _, src in ipairs(run.lines or {}) do
      local state = stateFor(src.i)
      local entry = {
        itemID = src.i, name = src.n, need = src.q or 0,
        have = driver.haveOf(src.i), bought = state.bought, spent = state.spent,
        vendor = src.v == true,
        lineUsual = num(src.u), vendorUnit = num(src.vu),
        -- Hour-of-day (UTC) this item is usually cheapest, and by what percent. Passed through
        -- untouched: whether the client can convert an hour into realm time, and whether the
        -- number is worth saying at all, is the caller's question (UI/BuyFrame.lua).
        cheapHour = num(src.ch), cheapPct = num(src.cp),
        capCopper = num(src.cc),
        realmName = src.rl and src.rl.n or nil, realmID = src.rl and src.rl.id or nil,
        -- The item level an alert group's gear member asks for (Core/AppRuns.lua's copyLine):
        -- UI/BuyFrame.lua says it on the line and narrows the search it opens to it.
        minIlvl = num(src.minIlvl),
        -- A vendor line is a trip to an NPC at a fixed price. The recipe the site attached
        -- describes what the item is; it is not an offer to make one, and splitting it would
        -- replace a copper purchase from a vendor with reagents bought at the auction house.
        craft = (src.v ~= true) and craftOf(src.cr) or nil,
        floor = state.floor, floorAt = state.floorAt,
      }
      entries[#entries + 1] = entry
      -- Core/AppRuns.lua already merges duplicate item ids; the `or` is for a run handed
      -- straight to New() that did not go through it. The FIRST entry keeps the item.
      byItem[entry.itemID] = byItem[entry.itemID] or entry
    end
    return entries, byItem
  end

  -- Every line the player has chosen to craft instead of buy, turned into a craft line with its
  -- reagents beside it. `crafts` is how many batches of the recipe the line still needs -- what
  -- is left to get, rounded up to a whole craft, because half a craft buys nothing.
  --
  -- A reagent the run already asks for GROWS that line rather than getting one of its own: two
  -- lines of the same item share one `bought` (progress is keyed by item id), so the second
  -- could never be bought at all. The line records what the craft added, so the row can say
  -- where its NEED came from. Everything else becomes a child line directly under its parent,
  -- and is bought, capped, counted and recorded exactly like any other line.
  --
  -- One pass, in run order: a reagent that lands on a craft line EARLIER in the run does not
  -- re-open that craft's arithmetic. Recipes whose outputs are each other's reagents do not
  -- occur in a shopping list, and an order-dependent answer is worse than a plain one.
  local function applySplits(entries, byItem, splits)
    local index = 1
    while index <= #entries do
      local parent = entries[index]
      local at = index
      if parent.craft and not parent.parent and splits[parent.itemID] then
        parent.kind = "craft"
        parent.crafts = math.ceil(
          math.max(0, parent.need - math.max(parent.have, parent.bought)) / parent.craft.craftedQty)
        for _, reagent in ipairs(parent.craft.reagents) do
          local add = parent.crafts * reagent.qty
          -- A recipe that takes its own output as a reagent would otherwise grow the very line
          -- whose crafts were just counted off it.
          if add > 0 and reagent.itemID ~= parent.itemID then
            local seen = byItem[reagent.itemID]
            if seen then
              seen.need = seen.need + add
              seen.forCraft = seen.forCraft or {}
              seen.forCraft[parent.itemID] = (seen.forCraft[parent.itemID] or 0) + add
            else
              at = at + 1
              local state = stateFor(reagent.itemID)
              local child = {
                itemID = reagent.itemID, name = reagent.name, need = add,
                parent = parent.itemID, vendor = reagent.vendor,
                lineUsual = reagent.usual, vendorUnit = reagent.vendorUnit,
                have = driver.haveOf(reagent.itemID), bought = state.bought, spent = state.spent,
                floor = state.floor, floorAt = state.floorAt,
              }
              table.insert(entries, at, child)
              byItem[child.itemID] = child
            end
          end
        end
      end
      index = at + 1
    end
  end

  -- Everything that depends on NEED, once NEED has stopped moving: the reference price, the
  -- ceiling, and what is left to buy.
  local function finish(entries, capPct)
    for _, entry in ipairs(entries) do
      -- The run's own price first: the site knew what this item cost when the list was saved,
      -- and the import's market value is a snapshot of a different moment (or, for an item the
      -- import has never carried, of nothing at all). A zero or a non-number is not a price --
      -- trusted, it caps the line at nothing and the line can never be bought.
      local lineUsual = entry.lineUsual
      entry.usual = (lineUsual and lineUsual > 0 and lineUsual) or driver.usualUnit(entry.itemID)
      if entry.vendorUnit and entry.vendorUnit <= 0 then entry.vendorUnit = nil end
      -- An absolute ceiling for one unit, when the line brought one: an alert group's own
      -- target price is the number the player chose, and a percentage of the site's reference
      -- price has nothing to say about it -- it would either buy above the alert or refuse the
      -- very lots the alert found. Everything else is capped as it always was.
      entry.cap = capFor({ cc = entry.capCopper }, entry.usual, capPct)
      -- The LARGER of the two, never their sum. `have` and `bought` are two views of the same
      -- units the moment a purchase is delivered -- the buyer's bags hold what they just bought --
      -- so subtracting both counted every purchase twice: a line needing 10 that filled 6 read
      -- have 6, bought 6, buy 0, done, and the four it still needed could never be bought again.
      -- They are kept apart rather than merged because each answers on its own: `bought` survives
      -- the units being used or mailed away, `have` covers stock that was never bought here.
      local buy = entry.need - math.max(entry.have, entry.bought)
      entry.buy = buy > 0 and buy or 0
      entry.done = entry.buy == 0
    end
  end

  -- Three buckets, in the order the list reads: what is left to buy, what is left to craft, the
  -- vendor trip, then everything already dealt with. Run order survives inside each. A craft
  -- line's reagents travel WITH it wherever it lands -- the block is one instruction, and a
  -- reagent that wandered off into another bucket is a row nobody can connect to anything.
  local function bucketed(entries)
    local open, crafting, vendor, done = {}, {}, {}, {}
    local index = 1
    while index <= #entries do
      local entry = entries[index]
      local bucket = open
      if entry.done then
        bucket = done
      elseif entry.kind == "craft" then
        bucket = crafting
      elseif entry.vendor then
        bucket = vendor
      end
      bucket[#bucket + 1] = entry
      index = index + 1
      while index <= #entries and entries[index].parent == entry.itemID do
        bucket[#bucket + 1] = entries[index]
        index = index + 1
      end
    end
    local out = {}
    for _, bucket in ipairs({ open, crafting, vendor, done }) do
      for i = 1, #bucket do out[#out + 1] = bucket[i] end
    end
    return out
  end

  -- Rebuilds every line from the run plus current state, in four passes: the run's own lines,
  -- then the splits the player chose (a craft line, with the reagents under it), then everything
  -- that depends on NEED once the reagents have stopped moving it, then the order the list reads
  -- in. `have` comes fresh from the driver every time (the bag count can change any moment the
  -- player isn't looking at this frame), `buy` from need/have/bought, and `cap` from the usual
  -- price. Lines come out in four groups -- open, then what is left to craft, then the vendor
  -- trip, then everything already done -- and keep run order inside each, a craft line's reagents
  -- travelling with it.
  function obj:Refresh()
    -- The run's code goes with every question: a cap and a set of splits are properties of the
    -- run, not of the tab (UI/BuyFrame.lua). A driver that does not care ignores the argument;
    -- one with no splits at all is a driver whose runs simply have none.
    local capPct = driver.capPct(run.code)
    -- Asked on every Refresh rather than once at construction, unlike progress: the player
    -- splits and un-splits a line from the row menu, and the answer has to be the current one.
    local splits = (driver.splits and driver.splits(run.code)) or {}
    local entries, byItem = baseEntries()
    applySplits(entries, byItem, splits)
    finish(entries, capPct)
    lines = bucketed(entries)
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
    -- A craft line is not bought: its units come out of the reagents under it, which are lines
    -- of their own. Refused here as well as in the caller's own `buyable` check -- this is the
    -- function that says how much gold a click may spend.
    if not line or line.kind == "craft" or line.buy <= 0 then return 0, 0, false end
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

  -- `left` counts open lines: a done line has nothing left to spend, so its cost is not part
  -- of "what this run needs right now". A vendor line counts at the vendor's price -- see
  -- below.
  function obj:Totals()
    local spent, left, toBuy, toCraft, atVendor, done = 0, 0, 0, 0, 0, 0
    -- Lines of the RUN, as against `lines` which counts the reagents a split put under one too.
    -- A reagent is part of the line above it, not another line of the run -- the rule a caller
    -- counting an alert group's hits needs.
    local topLines = 0
    for _, line in ipairs(lines) do
      if not line.parent then topLines = topLines + 1 end
      spent = spent + line.spent
      if line.done then
        done = done + 1
      elseif line.kind == "craft" then
        toCraft = toCraft + 1
      elseif line.vendor then
        atVendor = atVendor + 1
      else
        toBuy = toBuy + 1
      end
      -- A craft line costs nothing of its own: the gold goes on its reagents, which are lines
      -- here too. Counting both would charge the player twice for the same crafts.
      if not line.done and line.kind ~= "craft" then
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
    return { spent = spent, left = left, toBuy = toBuy, toCraft = toCraft,
             atVendor = atVendor, done = done, lines = #lines, topLines = topLines }
  end

  return obj
end

--- The two numbers a "craft it or buy it" decision is made of, for a line the site attached a
--- recipe to: what one unit costs in reagents at the prices the site quoted, and what one costs
--- at the auction house right now -- the best price actually seen for it, or the site's own
--- reference price when nothing has been seen yet.
---
--- No text, like everything else here: the caller owns every string the player reads, and the
--- claim it may make is "craft it: X vs Y", never "you will save". `reagents` are per CRAFT,
--- exactly as the recipe states them. nil for a line with no usable recipe.
function GC.BuyRun.CraftText(line)
  if type(line) ~= "table" or type(line.craft) ~= "table" then return nil end
  local craft = line.craft
  if not (craft.craftedQty and craft.craftedQty > 0) then return nil end
  local unit = math.floor((craft.cost or 0) / craft.craftedQty)
  local ahUnit = line.floor or line.usual
  local reagents = {}
  for _, reagent in ipairs(craft.reagents or {}) do
    reagents[#reagents + 1] = { itemID = reagent.itemID, qty = reagent.qty, name = reagent.name }
  end
  return {
    unit = unit, ahUnit = ahUnit,
    cheaper = (type(ahUnit) == "number" and ahUnit > 0 and unit < ahUnit) or false,
    craftedQty = craft.craftedQty, crafts = line.crafts, reagents = reagents,
  }
end
