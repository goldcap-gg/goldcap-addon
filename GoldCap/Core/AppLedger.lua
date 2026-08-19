local _, GC = ...

-- Sold tab, leg 2 (sold-tab design doc): adopts the companion-written
-- `GoldCap_AppLedger` global (LedgerSummary.lua in the GoldCap_AppData
-- mini-addon) once at ADDON_LOADED. Memory only, on purpose: nothing here
-- touches SavedVariables, so an unpaired companion honestly means "no
-- server data next login" and there is nothing to migrate. Anything
-- malformed is a silent no-op — the companion is optional, same contract
-- as Core/Data.lua's AdoptAppData. Individual sale rows are dropped (not
-- repaired) when a required field has the wrong type; a malformed optional
-- basis drops the basis, not its row.
GC.AppLedger = {}

local summary = nil

local function num(v) return type(v) == "number" and v or nil end

local function copyBasis(raw)
  if type(raw) ~= "table" then return nil end
  local matched, unmatched = num(raw.matched), num(raw.unmatched)
  local cost, profit = num(raw.cost), num(raw.profit)
  if not (matched and unmatched and cost and profit) then return nil end
  return { matched = matched, unmatched = unmatched, cost = cost, profit = profit }
end

local function copySale(raw)
  if type(raw) ~= "table" then return nil end
  if type(raw.name) ~= "string" then return nil end
  local qty, total, cut, at = num(raw.qty), num(raw.total), num(raw.cut), num(raw.at)
  if not (qty and total and cut and at) or qty <= 0 then return nil end
  return {
    name = raw.name,
    item = num(raw.item),
    qty = qty,
    total = total,
    cut = cut,
    pending = raw.pending == true,
    at = at,
    basis = copyBasis(raw.basis),
  }
end

function GC.AppLedger.Adopt()
  local raw = _G.GoldCap_AppLedger
  if type(raw) ~= "table" or raw.v ~= 1 then return end
  if type(raw.generatedAt) ~= "number" then return end
  if type(raw.totals) ~= "table" or type(raw.sales) ~= "table" then return end

  local totals = {
    proceeds = num(raw.totals.proceeds) or 0,
    spent = num(raw.totals.spent) or 0,
    pending = num(raw.totals.pending) or 0,
    salesCount = num(raw.totals.salesCount) or 0,
    realized = num(raw.totals.realized), -- Pro-only; nil stays nil
    medianHold = num(raw.totals.medianHold),
  }
  local sales = {}
  for _, rawSale in ipairs(raw.sales) do
    local sale = copySale(rawSale)
    if sale then sales[#sales + 1] = sale end
  end

  summary = {
    generatedAt = raw.generatedAt,
    pro = raw.pro == true,
    days = num(raw.days) or 30,
    totals = totals,
    sales = sales,
  }
end

function GC.AppLedger.GetSummary()
  return summary
end
