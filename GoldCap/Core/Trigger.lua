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

-- Sniper phase 2 (docs/superpowers/specs/2026-09-10-sniper-phase2-realm-items-design.md):
-- the least a realm item has to be discounted before it is worth looking at. The profit
-- formula above, run on a reference price alone, allows roughly a 14% discount -- fine for a
-- commodity whose exit price is measured from a live tape, far too loose for a region
-- reference, which is a median across realms and cannot be that precise about THIS realm.
GC.Trigger.REALM_MIN_DISCOUNT = 0.25

-- The one price a realm item is judged against: this realm's own median (import I section)
-- and the region reference (import T section) are both estimates of the same thing, so the
-- LOWER of the two is used whenever both exist -- the conservative choice, since it is the
-- one that makes a discount look smaller and a trigger stricter. nil when neither exists, and
-- an item with no reference is never polled and can never hit.
function GC.Trigger.RealmReference(value)
  if type(value) ~= "table" then return nil end
  local mv = value.mv
  local ref = value.ref
  if type(mv) ~= "number" or mv ~= mv or mv <= 0 then mv = nil end
  if type(ref) ~= "number" or ref ~= ref or ref <= 0 then ref = nil end
  if mv and ref then return math.min(mv, ref) end
  return mv or ref
end

-- The realm-item counterpart of GC.Trigger.For: the highest price at which a realm lot is
-- still worth a live look. The stricter of the two floors applies -- the profit/ROI formula
-- (run with the reference standing in for both the market value and the exit price, since a
-- realm item has no stress figure of its own) and REALM_MIN_DISCOUNT. nil whenever the
-- reference is unusable or the profit floor leaves no positive price, exactly like For.
function GC.Trigger.ForRealm(reference, settings)
  if type(reference) ~= "number" or reference ~= reference or reference <= 0 then return nil end
  local byProfit = GC.Trigger.For({ mv = reference, stressUnit = reference }, settings)
  if not byProfit then return nil end
  local byDiscount = math.floor(reference * (1 - GC.Trigger.REALM_MIN_DISCOUNT))
  local trigger = math.min(byProfit, byDiscount)
  if trigger <= 0 then return nil end
  return trigger
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
