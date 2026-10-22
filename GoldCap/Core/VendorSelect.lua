local _, GC = ...

-- Which stacks one press at a vendor sells, and why the others stay. Pure: the stacks come from
-- Services/VendorBags.lua, the figures from the same ForeverValue verdict the merchant note uses,
-- so the note and this list never claim the same stack.
--
-- Stack: { bag, slot, itemID, link, count, quality, vendorUnit, ahUnit, hasNoValue, isLocked,
--   isBound, isGear, isReagent, refundable, tradeTimer, inSet, excludedBag, selling }.
GC.VendorSelect = {}
local V = GC.VendorSelect

-- BUYBACK_ITEMS_PER_PAGE: the vendor's Buyback tab holds the last 12 stacks sold.
V.MAX_STACKS = 12

-- What the auction house leaves the seller; the same factor ForeverValue.Verdict applies.
local KEEP = 0.95

local WHY = {
  EMPTY = "empty", LOCKED = "locked", NO_VALUE = "no_value", NO_PRICE = "no_price",
  REFUNDABLE = "refundable", TRADE_TIMER = "trade_timer", SET = "set", EXCLUDED = "excluded_bag",
  KEPT = "kept", SELLING = "selling", AH = "ah", JUNK_OFF = "junk_off", BOUND = "bound",
  REAGENT = "reagent", WORTH_OFF = "worth_off", UNPRICED = "unpriced", NOT_WORTH = "not_worth",
}

local function positive(n) return type(n) == "number" and n > 0 end

-- rule ("junk" or "vendor"), or nil and the first reason the stack stays. The order is the contract.
function V.Decide(stack, opts)
  opts = opts or {}
  if not stack.itemID or type(stack.count) ~= "number" or stack.count < 1 then return nil, WHY.EMPTY end
  if stack.isLocked then return nil, WHY.LOCKED end
  if stack.hasNoValue then return nil, WHY.NO_VALUE end
  if not positive(stack.vendorUnit) then return nil, WHY.NO_PRICE end
  if stack.refundable then return nil, WHY.REFUNDABLE end
  if stack.tradeTimer then return nil, WHY.TRADE_TIMER end
  if stack.inSet then return nil, WHY.SET end
  if stack.excludedBag then return nil, WHY.EXCLUDED end
  if opts.kept and opts.kept[stack.itemID] then return nil, WHY.KEPT end
  if stack.selling then return nil, WHY.SELLING end
  -- The merchant note's "keep for the auction house": never listed twice, grey or not.
  if not stack.isBound and positive(stack.ahUnit) and math.floor(stack.ahUnit * KEEP) > stack.vendorUnit then
    return nil, WHY.AH
  end
  if stack.quality == 0 then
    if opts.junk then return "junk" end
    return nil, WHY.JUNK_OFF
  end
  if stack.isBound then return nil, WHY.BOUND end
  if stack.isReagent then return nil, WHY.REAGENT end
  if not opts.worth then return nil, WHY.WORTH_OFF end
  if not positive(stack.ahUnit) then return nil, WHY.UNPRICED end
  if GC.ForeverValue.Verdict(stack.ahUnit, stack.vendorUnit, nil, stack.isGear) == "vendor" then
    return "vendor"
  end
  return nil, WHY.NOT_WORTH
end

local function before(a, b)
  if a.copper ~= b.copper then return a.copper > b.copper end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

function V.Pick(stacks, opts)
  local eligible = {}
  for _, s in ipairs(stacks or {}) do
    local rule = V.Decide(s, opts)
    if rule then
      local row = {}
      for k, v in pairs(s) do row[k] = v end
      row.rule = rule
      row.copper = s.vendorUnit * s.count
      eligible[#eligible + 1] = row
    end
  end
  table.sort(eligible, before)
  local rows, total = {}, 0
  for i = 1, math.min(#eligible, V.MAX_STACKS) do
    rows[i] = eligible[i]
    total = total + rows[i].copper
  end
  return { rows = rows, total = total, more = #eligible - #rows }
end

-- What the button promises: every row, or the first alone when the game sells one per press.
function V.PressTotals(pick, oneAtATime)
  local rows = pick.rows
  if #rows == 0 then return 0, 0 end
  if oneAtATime then return 1, rows[1].copper end
  return #rows, pick.total
end
