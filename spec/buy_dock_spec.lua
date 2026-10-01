local helper = require("spec.spec_helper")

-- The dock's view model (Core/BuyDock.lua): which buttons it offers and what its one line says.
-- The purchase button's own words stay UI/BuyFrame.lua's actionLabel; this decides only whether
-- the dock offers a purchase at all, a raise, a cancel or a skip.
describe("BuyDock.View", function()
  local D
  before_each(function() D = helper.loadModule("Core/BuyDock.lua").BuyDock end)

  local function line(over)
    local l = { itemID = 1, buy = 120, need = 160, cap = 91, usual = 70, floor = 67, bought = 0, spent = 0 }
    for k, v in pairs(over or {}) do l[k] = v end
    return l
  end

  local cases = {
    { "nothing left, vendor and craft still on the list",
      { vendorLeft = 1, craftLeft = 1 },
      { mode = "none", title = "all_bought", sub = { key = "left", args = { 1, 1 } } } },
    { "nothing left and nothing else",
      {}, { mode = "none", title = "all_bought" } },
    { "nothing left but some lines skipped",
      { skippedLeft = 2 }, { mode = "none", title = "rest_skipped" } },
    { "ready with a quote for the whole line, under market",
      { line = line(), status = "ready", attempt = { stage = "quoted", qty = 120, total = 8107 } },
      { mode = "buy", primary = "purchase", sub = { key = "under", args = { 8107, 293 } } } },
    { "ready with a quote at or over market",
      { line = line({ usual = 60 }), status = "ready", attempt = { stage = "quoted", qty = 120, total = 8107 } },
      { mode = "buy", primary = "purchase", sub = { key = "at_market", args = { 8107 } } } },
    { "a partial fill says how many of the line fit",
      { line = line(), status = "ready", attempt = { stage = "quoted", qty = 80, total = 5400, capped = true } },
      { mode = "buy", primary = "purchase", sub = { key = "partial", args = { 80, 120 } } } },
    { "a recent quote from a hover counts as the line's price",
      { line = line(), status = "ready", quote = { qty = 120, total = 8107 } },
      { mode = "buy", primary = "purchase", sub = { key = "under", args = { 8107, 293 } } } },
    { "no quote: an estimate from NOW",
      { line = line(), status = "ready" },
      { mode = "buy", primary = "purchase", sub = { key = "estimate", args = { 8040 } } } },
    { "unpriced: the button, no sub",
      { line = { itemID = 1, buy = 120, need = 160 }, status = "unpriced" },
      { mode = "buy", primary = "purchase" } },
    { "at CONFIRM with the countdown running",
      { line = line(), status = "ready", attempt = { stage = "confirm", qty = 120, total = 8000, serverTotal = 8107, secondsLeft = 8 } },
      { mode = "confirm", primary = "purchase", secondary = "cancel", sub = { key = "blizzard_left", args = { 8107, 8 } } } },
    { "at CONFIRM before the countdown",
      { line = line(), status = "ready", attempt = { stage = "confirm", qty = 120, total = 8107 } },
      { mode = "confirm", primary = "purchase", secondary = "cancel", sub = { key = "blizzard", args = { 8107 } } } },
    { "buying...: the button says it, the total rides along",
      { line = line(), status = "ready", attempt = { stage = "started", qty = 120, total = 8107 } },
      { mode = "buy", primary = "purchase", sub = { key = "total", args = { 8107 } } } },
    { "a refused bid says why in the auction house's own words",
      { line = line({ buy = 1, need = 1 }), status = "lots",
        attempt = { stage = "failed", qty = 1, total = 900, errorText = "That auction is gone." } },
      { mode = "buy", primary = "purchase", sub = { key = "error", args = { "That auction is gone." } } } },
    -- BUY 2.0 week 2: a gear line's dock lists its lots by price, cheapest first.
    { "a lot line with lots under the cap",
      { line = line({ buy = 1, need = 1, cap = 1170 }), status = "lots",
        lots = { groups = { { buyout = 900, count = 4, over = false }, { buyout = 1900, count = 1, over = true } } } },
      { mode = "lots", primary = "purchase", sub = { key = "lots",
        groups = { { buyout = 900, count = 4, over = false }, { buyout = 1900, count = 1, over = true } } } } },
    { "a lot line with no cap",
      { line = { itemID = 1, buy = 1, need = 1 }, status = "lots", lots = { groups = {}, why = "nocap" } },
      { mode = "lots", primary = "purchase", sub = { key = "nocap" } } },
    { "a lot line not read yet",
      { line = line({ buy = 1, need = 1 }), status = "lots" },
      { mode = "lots", primary = "purchase" } },
    { "a purchase in flight outranks an over-cap status",
      { line = line(), status = "over", attempt = { stage = "confirming", qty = 120, total = 8107 } },
      { mode = "buy", primary = "purchase", sub = { key = "total", args = { 8107 } } } },
    { "over the cap with a raise on offer",
      { line = line({ cap = 140 }), status = "over", raiseTo = 187, cheapest = 186 },
      { mode = "over", primary = "raise", secondary = "skip", raiseTo = 187, sub = { key = "over", args = { 186, 140 } } } },
    { "over the cap on an alert line: skip only",
      { line = line({ cap = 140 }), status = "over", cheapest = 186 },
      { mode = "over", secondary = "skip", sub = { key = "over", args = { 186, 140 } } } },
    { "over the cap with nothing seen to name",
      { line = line({ cap = 140 }), status = "over" },
      { mode = "over", secondary = "skip", sub = { key = "over_nocheap", args = { 140 } } } },
    { "a vendor line with the auction house's price beside it",
      { line = line({ vendor = true, vendorUnit = 10 }), status = "vendor", cheapest = 16 },
      { mode = "vendor", sub = { key = "vendor_vs", args = { 10, 16 } } } },
    -- A line that is not bought here still says why, even when there is no price to name.
    { "a vendor line with no vendor price",
      { line = line({ vendor = true }), status = "vendor" },
      { mode = "vendor", sub = { key = "vendor_only" } } },
    { "a vendor line with no auction house price beside it",
      { line = line({ vendor = true, vendorUnit = 10 }), status = "vendor" },
      { mode = "vendor", sub = { key = "vendor", args = { 10 } } } },
    { "a craft line",
      { line = line({ kind = "craft" }), status = "craft", craft = { unit = 136, ahUnit = 160 } },
      { mode = "craft", sub = { key = "craft_vs", args = { 136, 160 } } } },
    { "a craft line with no auction house price",
      { line = line({ kind = "craft" }), status = "craft", craft = { unit = 136 } },
      { mode = "craft", sub = { key = "craft", args = { 136 } } } },
    { "a line the route crafts, with no recipe to price",
      { line = line({ kind = "craft", make = true }), status = "craft" },
      { mode = "craft", sub = { key = "craft_only" } } },
    { "a bought line",
      { line = line({ done = true, bought = 5, spent = 275 }), status = "done" },
      { mode = "done", sub = { key = "bought", args = { 5, 275 } } } },
    { "a line the bags and bank already cover",
      { line = line({ done = true, buy = 0 }), status = "done" },
      { mode = "done", sub = { key = "have" } } },
    { "a skipped line",
      { line = line(), status = "skipped" },
      { mode = "skipped", sub = { key = "skipped" } } },
  }
  for _, case in ipairs(cases) do
    it(case[1], function() assert.same(case[3], D.View(case[2])) end)
  end
end)
