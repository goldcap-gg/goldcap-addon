local _, GC = ...

-- Sniper fast loop, phase 1 (docs/superpowers/specs/2026-09-10-sniper-fast-loop-design.md
-- §2 Trigger): the highest unit price at which one unit could still clear the player's own
-- floor, computed from the import alone -- no order book. A pre-filter for Core/BookPass.lua,
-- never a verdict: the live ladder (SniperDecision.Evaluate) still decides everything the
-- purchase path reads. nil whenever the import carries nothing to compute from (no V fact at
-- all -- mv or stressUnit missing/non-positive), or when no positive price clears both the
-- flat profit floor and the ROI floor -- in either case the item can never register a hit.
GC.Trigger = {}

function GC.Trigger.For(value, settings)
  if type(value) ~= "table" or type(settings) ~= "table" then return nil end
  local mv = value.mv
  local stressUnit = value.stressUnit
  if type(mv) ~= "number" or mv ~= mv or mv <= 0 then return nil end
  if type(stressUnit) ~= "number" or stressUnit ~= stressUnit or stressUnit <= 0 then return nil end
  local minimumProfitCopper = settings.minimumProfitCopper
  local minimumRoi = settings.minimumRoi
  if type(minimumProfitCopper) ~= "number" or type(minimumRoi) ~= "number" then return nil end
  if minimumRoi <= -1 then return nil end -- would divide by <= 0 below

  -- Same cap SniperDecision.Evaluate applies to its own exit price.
  local exit = math.min(stressUnit, mv)
  local netExit = exit * 0.95 -- the AH cut; the deposit is quoted live later, by the ladder
  local byProfit = netExit - minimumProfitCopper
  local byRoi = netExit / (1 + minimumRoi)
  local trigger = math.min(byProfit, byRoi)
  if trigger <= 0 then return nil end
  return math.floor(trigger)
end

-- Whether AT LEAST ONE of the given itemIDs currently has a trigger -- the question the
-- board's empty state asks: can the loaded import ever arm the sniper at all? Pure over an
-- injected getValue (GC.Data.GetItemValue in production), so it needs no import-shape
-- knowledge beyond what GC.Trigger.For already reads.
function GC.Trigger.AnyArmed(itemIDs, getValue, settings)
  if type(itemIDs) ~= "table" or type(getValue) ~= "function" then return false end
  for i = 1, #itemIDs do
    if GC.Trigger.For(getValue(itemIDs[i]), settings) then return true end
  end
  return false
end
