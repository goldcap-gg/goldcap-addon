local _, GC = ...

-- Sniper fast loop, phase 1 (design doc §3 Drill-down): a bounded priority queue of
-- Core/BookPass.lua hits waiting for a live SendSearchQuery. Pure and driver-injected
-- (driver.now() only), like every other module in this batch. Push takes whatever the
-- caller hands it (itemID, floor, estProfit); Pop returns the highest-estProfit entry still
-- queued, refusing once LIM.DRILL_PER_MINUTE sends have already gone out in the trailing 60
-- seconds -- the budget this module enforces is SENDS, not pushes, so a busy board never
-- loses a hit for being unable to even queue it.
GC.DrillQueue = {}

function GC.DrillQueue.New(driver, opts)
  opts = opts or {}
  local perMinute = opts.perMinute or 60
  local obj = {}
  local items = {}   -- array of { itemID, floor, estProfit, key }
  local queued = {}  -- "itemID:floor" -> true, cleared the moment an entry is popped
  local sentAt = {}  -- sliding 60s window of driver.now() timestamps, one per successful Pop

  local function key(itemID, floor) return itemID .. ":" .. floor end

  function obj:Push(hit)
    if type(hit) ~= "table" or type(hit.itemID) ~= "number" or type(hit.floor) ~= "number" then
      return false
    end
    local k = key(hit.itemID, hit.floor)
    if queued[k] then return false end
    queued[k] = true
    items[#items + 1] = { itemID = hit.itemID, floor = hit.floor, estProfit = hit.estProfit or 0, key = k }
    return true
  end

  local function pruneWindow(now)
    local kept = {}
    for i = 1, #sentAt do
      if now - sentAt[i] < 60 then kept[#kept + 1] = sentAt[i] end
    end
    sentAt = kept
  end

  function obj:Pop()
    if #items == 0 then return nil end
    local now = driver.now()
    pruneWindow(now)
    if #sentAt >= perMinute then return nil end

    local bestIndex = 1
    for i = 2, #items do
      if items[i].estProfit > items[bestIndex].estProfit then bestIndex = i end
    end
    local chosen = table.remove(items, bestIndex)
    queued[chosen.key] = nil
    sentAt[#sentAt + 1] = now
    return { itemID = chosen.itemID, floor = chosen.floor, estProfit = chosen.estProfit }
  end

  function obj:Depth() return #items end

  return obj
end
