local _, GC = ...

-- The Sold tab's receipt, apart from the frames that draw it (UI/SoldReceipt.lua): what a sale's
-- vs-market mark says, which of the receipt's three columns a sale gets, the cost a player types
-- for it, and the store calls that turn that cost into the sale's profit. Pure Lua but for
-- SaveCost, which is handed the store; the spec (spec/sold_receipt_spec.lua) drives it with
-- plain tables and the real Core/Acquisitions.lua.
GC.SoldReceipt = {}
local R = GC.SoldReceipt

-- How far from the market price the vs-market dot reaches the end of its track, in percent: a
-- sale 50% above sits at the right end, and so does one 300% above. The figure beside the dot
-- says the rest.
R.MARKET_SPAN = 50

--- Where the vs-market dot sits on its track, 0 (left end) to 1 (right end), the market price
--- at 0.5. nil without a percent.
function R.BarPosition(pct)
  if type(pct) ~= "number" then return nil end
  local span = R.MARKET_SPAN
  return 0.5 + math.max(-span, math.min(span, pct)) / (2 * span)
end

--- "above", "under" or "at": which side of the market a sale's percent puts it.
function R.Tone(pct)
  if type(pct) ~= "number" or pct == 0 then return "at" end
  return pct > 0 and "above" or "under"
end

--- The market price a sale is compared with, from the figure GoldCap's own item tooltip prices
--- the item at (GC.Data.GetItemValue): an item priced as one thing only. A realm item's figure is
--- one item level's or one realm's median, and a piece of Forever gear's is its cheapest
--- version's; the copy that sold may have been another, so neither is a market for the sale.
function R.Market(value)
  if type(value) ~= "table" or value.gear or value.kind == "realm_item" then return nil end
  return type(value.mv) == "number" and value.mv > 0 and value.mv or nil
end

--- What the row's PROFIT cell says: "profit" (the number), "set" (a quiet "set cost": a local
--- sale this tab can finish), "dash" (a cost it cannot learn here) or "blank" (a free account is
--- told nothing about profit -- an empty cell, not a dash that implies a cost was looked for).
function R.ProfitCell(row, canSave)
  if type(row.profit) == "number" then return "profit" end
  if row.noBasis then return "blank" end
  if canSave then return "set" end
  return "dash"
end

--- The receipt's columns for a sale. RECEIPT always; AGAINST TODAY'S MARKET only with an exact
--- market price (`market`, from R.Market on the sale's exact item -- never one found by its
--- name); the third always, since it is where the profit is either shown or explained. `note`
--- names the sentence it says without a profit: the money is still in the mail, profit is a Pro
--- feature, or GoldCap never saw the item bought (and it cannot be finished here). `title` is
--- "finish" when the column holds an action (a cost to type, units in the bags to sell), else
--- "profit".
function R.Columns(row, opts)
  opts = opts or {}
  local market = type(opts.market) == "number" and opts.market > 0 and opts.market or nil
  local cols = { receipt = true, market = market ~= nil, marketPrice = market,
    save = opts.canSave == true, bags = math.max(0, math.floor(tonumber(opts.bags) or 0)) }
  if type(row.profit) ~= "number" then
    if row.pending then cols.note = "pending"
    elseif row.noBasis then cols.note = "pro"
    elseif not cols.save then cols.note = "unseen" end
  end
  cols.title = (cols.save or cols.bags > 0) and "finish" or "profit"
  return cols
end

--- Copper from what a player typed for a price: "2s 34c", "1g22s90c", "75c", or a bare number,
--- read as gold the way SELL's cost boxes read it ("1.5" is 1g 50s). nil for anything that is
--- not an exact, positive copper amount.
function R.ParseMoney(text)
  if type(text) ~= "string" then return nil end
  local s = text:lower():gsub("%s+", "")
  if s == "" then return nil end
  local copper
  if s:find("[gsc]") then
    -- Each figure carries its unit, in g, s, c order, each optional.
    copper = 0
    for _, unit in ipairs({ { "g", 10000 }, { "s", 100 }, { "c", 1 } }) do
      local n, rest = s:match("^(%d+)" .. unit[1] .. "(.*)$")
      if n then copper, s = copper + tonumber(n) * unit[2], rest end
    end
    if s ~= "" then return nil end
  else
    local gold = tonumber(s:match("^%d+%.?%d*$") or s:match("^%.%d+$") or "")
    if not gold then return nil end
    copper = gold * 10000
    -- A gold figure finer than a copper is not an amount.
    if math.abs(copper - math.floor(copper + 0.5)) > 1e-6 then return nil end
    copper = math.floor(copper + 0.5)
  end
  return copper > 0 and copper or nil
end

--- How many of the Road to 40 ring's `n` segments are lit for `progress` (0..1).
function R.RingLit(progress, n)
  local p = math.max(0, math.min(1, tonumber(progress) or 0))
  return math.floor(p * n + 0.5)
end

local function context(entry) return { char = entry.char, region = entry.region } end

--- Where a typed cost for a sale goes, or nil and why not. Only a local, paid sale with no profit
--- yet, whose name the character listed under exactly one item in this region before it sold
--- (`activities`, GC.Acquisitions.GetActivities), and whose position holds no other stock on the
--- books (`active`, GC.Acquisitions.GetActive for the sale's character): the batch typed here is
--- then the only one the sale can draw on, so it is spent whole and leaves nothing behind. Two
--- items under one name is no answer, the same rule the ledger's own reconciliation keeps.
function R.CostTarget(row, entry, activities, active)
  if type(row) ~= "table" or row.section ~= "local" or row.pending or type(row.profit) == "number" then
    return nil, "not_open"
  end
  if type(entry) ~= "table" or entry.kind ~= "sale" or type(entry.key) ~= "string"
      or type(entry.char) ~= "string" or type(entry.region) ~= "string"
      or type(entry.qty) ~= "number" or entry.qty < 1 or type(entry.at) ~= "number" then
    return nil, "no_entry"
  end
  local found
  for _, activity in ipairs(activities or {}) do
    if activity.itemName == entry.itemName and activity.character == entry.char
        and activity.region == entry.region and type(activity.positionKey) == "string"
        and type(activity.firstSeenAt) == "number" and activity.firstSeenAt <= entry.at then
      if found and found.positionKey ~= activity.positionKey then return nil, "ambiguous_name" end
      found = activity
    end
  end
  if not found then return nil, "never_listed" end
  if row.itemExact and row.itemID and row.itemID ~= found.itemID then return nil, "other_item" end
  for _, batch in ipairs(active or {}) do
    if batch.positionKey == found.positionKey then return nil, "has_stock" end
  end
  return { positionKey = found.positionKey, itemID = found.itemID, itemName = entry.itemName,
    quantity = entry.qty, character = entry.char, region = entry.region, acquiredAt = entry.at }
end

--- Records what the player paid each for the units a sale sold and books the sale against it:
--- the manual batch SELL's Set cost dialog records (GC.Acquisitions.RecordManual), then the
--- ledger's own reconciliation of the sale (GC.Acquisitions.ReconcileSale), which writes the
--- realized row the tab joins on the sale's key. If the sale does not book, the batch is taken
--- back (RemoveManual), so a refused save leaves no stock on the books. Returns true, or false
--- and why.
function R.SaveCost(acq, row, entry, paidEach)
  if type(acq) ~= "table" or not (acq.RecordManual and acq.ReconcileSale and acq.RemoveManual
      and acq.GetActivities and acq.GetActive) then
    return false, "no_store"
  end
  if type(paidEach) ~= "number" or paidEach < 1 or paidEach ~= math.floor(paidEach) then return false, "bad_cost" end
  local target, why = R.CostTarget(row, entry, acq.GetActivities(context(entry)), acq.GetActive(context(entry)))
  if not target then return false, why end
  local total = paidEach * target.quantity
  local batch = acq.RecordManual({ itemID = target.itemID, positionKey = target.positionKey,
    itemName = target.itemName, quantity = target.quantity, total = total, acquiredAt = target.acquiredAt,
    character = target.character, region = target.region })
  if not batch then return false, "not_recorded" end
  local result = acq.ReconcileSale(entry)
  if type(result) ~= "table" or result.status ~= "applied" then
    acq.RemoveManual(batch.id)
    return false, type(result) == "table" and result.reason or "not_booked"
  end
  return true
end
