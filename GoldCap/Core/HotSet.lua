local _, GC = ...

-- Items to look at more often for a while: each one marked is in the set for `seconds` after its
-- latest mark, then drops out on its own. UI/SniperFrame.lua keeps two: the items a live Check just
-- found a buyable deal on (ten minutes), and the caps just found under their price. Pure and
-- driver-injected (`now`), like every other module the Sniper drives.
GC.HotSet = {}

function GC.HotSet.New(now, seconds)
  local obj, untilAt = {}, {}

  function obj:Mark(itemID)
    if type(itemID) == "number" then untilAt[itemID] = now() + seconds end
  end

  function obj:Has(itemID)
    local at = untilAt[itemID]
    if not at then return false end
    if now() >= at then
      untilAt[itemID] = nil
      return false
    end
    return true
  end

  function obj:Count()
    local n, t = 0, now()
    for itemID, at in pairs(untilAt) do
      if t >= at then untilAt[itemID] = nil else n = n + 1 end
    end
    return n
  end

  return obj
end
