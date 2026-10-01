local _, GC = ...

-- BUY 2.0's "next purchase" dock as data: what its one line of text says and what its two
-- buttons do, for the line the dock is on. Pure and text-free: every sub-line is a key and its
-- numbers, and UI/BuyFrame.lua turns them into GC.L strings. The purchase button's own words
-- (BUY n, CONFIRM, buying..., waiting...) are NOT decided here: UI/BuyFrame.lua's actionLabel stays
-- the one source the dock, the Enter key and the attempt log read, so they can never disagree.
GC.BuyDock = {}

-- The stages in which a purchase of this line is in the client's hands or has just been answered:
-- the button's own label says what happened, and the total rides along on the sub-line.
local ANSWERED = { started = true, confirming = true, requote = true, expired = true,
  failed = true, unknown = true }

-- `d` = { line, status (GC.BuyView.Status), attempt = { stage, qty, total, serverTotal, capped,
-- secondsLeft } (this line's own only), quote = { qty, total } (a recent read), raiseTo, cheapest,
-- craft = { unit, ahUnit }, vendorLeft, craftLeft, skippedLeft }. With no line: the run's end.
function GC.BuyDock.View(d)
  d = d or {}
  local line = d.line
  if not line then
    local v, c = d.vendorLeft or 0, d.craftLeft or 0
    local view = { mode = "none", title = (d.skippedLeft or 0) > 0 and "rest_skipped" or "all_bought" }
    if v > 0 or c > 0 then view.sub = { key = "left", args = { v, c } } end
    return view
  end
  local attempt = d.attempt
  local stage = attempt and attempt.stage
  -- A purchase of this line in the client's hands outranks every status: the dock is where it is
  -- confirmed, cancelled or read back.
  if stage == "confirm" then
    local total = attempt.serverTotal or attempt.total
    return { mode = "confirm", primary = "purchase", secondary = "cancel",
      sub = attempt.secondsLeft and { key = "blizzard_left", args = { total, attempt.secondsLeft } }
        or { key = "blizzard", args = { total } } }
  end
  if ANSWERED[stage] then
    local total = attempt.serverTotal or attempt.total
    return { mode = "buy", primary = "purchase",
      sub = total and total > 0 and { key = "total", args = { total } } or nil }
  end
  local status = d.status
  if status == "done" then
    -- Covered by what the character already owns, with nothing bought here: "bought 0 for 0c"
    -- would be a false account of it.
    if (line.bought or 0) <= 0 then return { mode = "done", sub = { key = "have" } } end
    return { mode = "done", sub = { key = "bought", args = { line.bought, line.spent or 0 } } }
  end
  if status == "skipped" then return { mode = "skipped", sub = { key = "skipped" } } end
  -- A line that is not bought here says why even with no price to name.
  if status == "vendor" then
    if not line.vendorUnit then return { mode = "vendor", sub = { key = "vendor_only" } } end
    return { mode = "vendor", sub = d.cheapest and { key = "vendor_vs", args = { line.vendorUnit, d.cheapest } }
      or { key = "vendor", args = { line.vendorUnit } } }
  end
  if status == "craft" then
    if not d.craft then return { mode = "craft", sub = { key = "craft_only" } } end
    return { mode = "craft", sub = d.craft.ahUnit and { key = "craft_vs", args = { d.craft.unit, d.craft.ahUnit } }
      or { key = "craft", args = { d.craft.unit } } }
  end
  if status == "over" then
    return { mode = "over", primary = d.raiseTo and "raise" or nil, secondary = "skip",
      raiseTo = d.raiseTo,
      sub = d.cheapest and { key = "over", args = { d.cheapest, line.cap } }
        or { key = "over_nocheap", args = { line.cap } } }
  end
  -- ready, unpriced, lots, stranded: the purchase button's own label says the rest.
  local quoted = (stage == "quoted" and (attempt.qty or 0) > 0) and attempt or d.quote
  local sub
  if quoted and (quoted.qty or 0) > 0 and quoted.total then
    if quoted == attempt and attempt.capped then
      sub = { key = "partial", args = { quoted.qty, line.buy } }
    elseif line.usual and quoted.qty == line.buy then
      local under = line.buy * line.usual - quoted.total
      sub = under > 0 and { key = "under", args = { quoted.total, under } }
        or { key = "at_market", args = { quoted.total } }
    else
      sub = { key = "total", args = { quoted.total } }
    end
  elseif status == "ready" and (line.floor or line.usual) and (line.buy or 0) > 0 then
    sub = { key = "estimate", args = { line.buy * (line.floor or line.usual) } }
  end
  return { mode = "buy", primary = "purchase", sub = sub }
end
