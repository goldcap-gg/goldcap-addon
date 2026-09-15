local helper = require("spec.spec_helper")

describe("BuyRun", function()
  local GC, run
  local have, usual
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
    have, usual = { [5] = 60, [7] = 0, [9] = 300 }, { [5] = 30000, [7] = nil, [9] = 100 }
    run = GC.BuyRun.New({ code = "abcd2345", name = "Cooking", updatedAt = 1, lines = {
      { i = 5, q = 210, v = false, n = "Plant Protein" },
      { i = 8, q = 215, v = true, n = "Tavern Fixings" },
      { i = 7, q = 5, v = false, n = "Petrified Root" },
      { i = 9, q = 100, v = false, n = "Done Thing" },
    } }, { now = function() return 1000 end, haveOf = function(id) return have[id] or 0 end,
           usualUnit = function(id) return usual[id] end, capPct = function() return 130 end,
           freeLines = function() return nil end })
    run:Refresh()
  end)

  -- The list is reordered by Refresh, so a line is found by the item it is for and never by
  -- where it happens to sit -- which is the point of the ordering these tests pin.
  local function lineOf(itemID)
    for _, l in ipairs(run:Lines()) do if l.itemID == itemID then return l end end
  end

  it("computes buy = need - have and orders the list open, then vendor, then done", function()
    local ids = {}
    for _, l in ipairs(run:Lines()) do ids[#ids + 1] = l.itemID .. ":" .. l.buy end
    assert.same({ "5:150", "7:5", "8:215", "9:0" }, ids)
    assert.is_true(run:Lines()[3].vendor)
    assert.is_true(run:Lines()[4].done)
  end)

  it("caps at 1.3x the usual price and buys only what fits", function()
    local qty, total, capped = run:PurchaseQuantity(5, { { unit = 30000, qty = 100 }, { unit = 39000, qty = 100 }, { unit = 39001, qty = 100 } })
    assert.equal(150, qty)                -- 100 @ 3g + 50 @ 3g90 (cap = 3g90)
    assert.equal(100 * 30000 + 50 * 39000, total)
    assert.is_false(capped)
    qty, total, capped = run:PurchaseQuantity(5, { { unit = 30000, qty = 20 }, { unit = 50000, qty = 500 } })
    assert.equal(20, qty)
    assert.equal(20 * 30000, total)       -- 20 @ 3g fit under the cap before the 5g level
    assert.is_true(capped)
  end)

  it("stops at whatever the ladder has when it runs out before need is met", function()
    local qty, total, capped = run:PurchaseQuantity(5, { { unit = 30000, qty = 40 } })
    assert.equal(40, qty)
    assert.equal(40 * 30000, total)
    assert.is_false(capped)               -- ran out of ladder, not stopped by the cap
  end)

  it("a line without a usual price has no cap and buys the whole need", function()
    local qty, _, capped = run:PurchaseQuantity(7, { { unit = 999999, qty = 10 } })
    assert.equal(5, qty)
    assert.is_false(capped)
  end)

  it("records purchases into bought, spent and the totals", function()
    -- What was bought lands in the bags, which is where `have` reads it from on the next
    -- Refresh -- so the fixture moves it there, exactly as the client would.
    run:RecordPurchase(5, 150, 4410000, 1001)
    have[5] = 60 + 150
    run:Refresh()
    local line = lineOf(5)
    assert.equal(150, line.bought)
    assert.equal(4410000, line.spent)
    assert.equal(210, line.have)
    assert.equal(0, line.buy)
    assert.is_true(line.done)
    assert.equal(4410000, run:Totals().spent)
  end)

  -- `have` and `bought` are two views of the SAME units once a purchase is delivered. Subtracting
  -- both counted every buy twice: a line that filled only part of what it needed went straight to
  -- done, and the rest of it could never be bought -- which is the whole job of this tab.
  it("keeps the remainder buyable after a partial fill lands in the bags", function()
    run:RecordPurchase(5, 90, 90 * 30000, 1001)
    have[5] = 60 + 90
    run:Refresh()
    local line = lineOf(5)
    assert.equal(150, line.have)
    assert.equal(90, line.bought)
    assert.equal(60, line.buy)
    assert.is_false(line.done)
    -- ...and the run still says those 60 cost something.
    assert.equal(60 * 30000, run:Totals().left)
  end)

  it("left to spend uses the floor when one is known, else the usual price", function()
    run:SetFloor(5, 29400, 999)
    assert.equal(150 * 29400 + 0, run:Totals().left)   -- line 7 has no usual and no floor: counts 0
  end)

  it("locks lines past the free limit, vendor lines never count", function()
    local gated = GC.BuyRun.New({ code = "x", lines = {
      { i = 1, q = 1 }, { i = 2, q = 1 }, { i = 8, q = 1, v = true }, { i = 3, q = 1 } } },
      { now = function() return 0 end, haveOf = function() return 0 end, usualUnit = function() return nil end,
        capPct = function() return 130 end, freeLines = function() return 2 end })
    gated:Refresh()
    local locked = {}
    for _, l in ipairs(gated:Lines()) do locked[#locked + 1] = tostring(l.locked) end
    assert.same({ "false", "false", "true", "false" }, locked)   -- 1, 2 buyable; 3 locked; vendor line last, never locked
  end)

  -- A line that is both done and a vendor stop is done: the player already has it, so it is not
  -- a stop to make and it must not sit above one that is.
  it("puts a finished vendor line with the finished lines, not with the vendor stops", function()
    local r = GC.BuyRun.New({ code = "z", lines = {
      { i = 11, q = 10 },               -- open
      { i = 12, q = 1, v = true },      -- a vendor stop the bags already cover
      { i = 13, q = 5, v = true },      -- a vendor stop still to make
    } }, { now = function() return 0 end,
           haveOf = function(id) return id == 12 and 1 or 0 end,
           usualUnit = function() return nil end, capPct = function() return 130 end,
           freeLines = function() return nil end })
    r:Refresh()
    local ids = {}
    for _, l in ipairs(r:Lines()) do ids[#ids + 1] = tostring(l.itemID) end
    assert.same({ "11", "13", "12" }, ids)
  end)
end)

describe("BuyRun progress across sessions", function()
  local GC
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
  end)
  local function newRun(progress)
    return GC.BuyRun.New({ code = "abcd2345", name = "Cooking", updatedAt = 1, lines = {
      { i = 5, q = 210, v = false, n = "Plant Protein" },
    } }, { now = function() return 1000 end, haveOf = function() return 0 end,
           usualUnit = function() return 30000 end, capPct = function() return 130 end,
           freeLines = function() return nil end,
           progress = function(code) assert.equal("abcd2345", code); return progress end })
  end

  it("writes bought and spent into the driver's progress table and reads them back", function()
    local saved = {}
    local run = newRun(saved)
    run:Refresh()
    run:RecordPurchase(5, 60, 60 * 30000, 1000)
    assert.same({ bought = 60, spent = 1800000, boughtAt = 1000 }, saved[5])

    -- A fresh object over the same table -- a /reload -- starts from the saved score, so the
    -- header says what was spent and the line continues from what was bought, not from zero.
    local again = newRun(saved)
    again:Refresh()
    assert.equal(1800000, again:Totals().spent)
    assert.equal(60, again:Lines()[1].bought)
    assert.equal(150, again:Lines()[1].buy)
  end)

  it("keeps a run that has no progress table in memory only", function()
    local run = GC.BuyRun.New({ code = "abcd2345", lines = { { i = 5, q = 10 } } },
      { now = function() return 1 end, haveOf = function() return 0 end,
        usualUnit = function() return nil end, capPct = function() return 130 end,
        freeLines = function() return nil end })
    run:Refresh()
    run:RecordPurchase(5, 4, 400, 1)
    assert.equal(400, run:Totals().spent)
  end)
end)

describe("BuyRun prices from the run itself", function()
  local GC
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
  end)

  local function build(lines)
    local run = GC.BuyRun.New({ code = "abcd2345", lines = lines },
      { now = function() return 1000 end, haveOf = function() return 0 end,
        -- The import knows 100 about item 9 and nothing about anything else.
        usualUnit = function(id) return id == 9 and 100 or nil end,
        capPct = function() return 130 end, freeLines = function() return nil end })
    run:Refresh()
    return run
  end

  -- The run was priced by the site when it was saved; the addon's bundled/imported market data
  -- is a fallback for a pasted run that carries none. Linen Cloth on a modern realm has no
  -- import price at all, which is the whole reason the line brings its own.
  it("prefers the run line's own price, falls back to the import, and caps off whichever won", function()
    local run = build({ { i = 5, q = 10, u = 44000 }, { i = 9, q = 10 }, { i = 7, q = 10 } })
    assert.equal(44000, run:Lines()[1].usual)
    assert.equal(math.floor(44000 * 130 / 100), run:Lines()[1].cap)
    assert.equal(100, run:Lines()[2].usual)
    assert.equal(130, run:Lines()[2].cap)
    assert.is_nil(run:Lines()[3].usual)
    assert.is_nil(run:Lines()[3].cap)
  end)

  -- Both known and different: the run's own price wins outright, not "whichever is set". Without
  -- this case a reversed precedence (import first) passes the case above unchanged.
  it("lets the run line's own price beat an import price the addon also knows", function()
    local run = build({ { i = 9, q = 10, u = 44000 } })
    assert.equal(44000, run:Lines()[1].usual)
    assert.equal(math.floor(44000 * 130 / 100), run:Lines()[1].cap)
  end)

  -- A zero is not a price. Trusted, it caps the line at zero and nothing can ever be bought.
  it("treats a zero or a non-number on the line as no price at all", function()
    assert.equal(100, build({ { i = 9, q = 10, u = 0 } }):Lines()[1].usual)
    assert.equal(100, build({ { i = 9, q = 10, u = "cheap" } }):Lines()[1].usual)
  end)

  it("carries the vendor price and the cheap hour through to the line", function()
    local run = build({ { i = 5, q = 10, vu = 25, ch = 3, cp = -18 } })
    local line = run:Lines()[1]
    assert.equal(25, line.vendorUnit)
    assert.equal(3, line.cheapHour)
    assert.equal(-18, line.cheapPct)
  end)

  -- A vendor stop still costs gold, and a run's "left to spend" that leaves it out understates
  -- the trip. It is priced off the vendor's own price, never off the auction house's.
  it("counts an open vendor line into what the run has left to spend", function()
    local run = build({ { i = 5, q = 10, u = 1000 }, { i = 8, q = 4, v = true, vu = 25 } })
    assert.equal(10 * 1000 + 4 * 25, run:Totals().left)
  end)

  it("counts a vendor line with no vendor price as nothing, not as an auction house price", function()
    local run = build({ { i = 9, q = 4, v = true } })  -- 9 has an import price of 100
    assert.equal(0, run:Totals().left)
  end)
end)

describe("BuyRun carries the v3 fields", function()
  local GC
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
  end)

  local function build(lines)
    local run = GC.BuyRun.New({ code = "abcd2345", lines = lines },
      { now = function() return 1000 end, haveOf = function() return 0 end,
        usualUnit = function() return nil end,
        capPct = function() return 130 end, freeLines = function() return nil end })
    run:Refresh()
    return run:Lines()[1]
  end

  -- An alert fired at a price the player chose. That price IS the ceiling: judging it again by
  -- 130% of the site's reference price would buy above the number the alert was set for, or
  -- refuse the very lots it found.
  it("takes an absolute cap in copper off the line, ahead of the run's cap percent", function()
    local line = build({ { i = 5, q = 10, u = 44000, cc = 9990000 } })
    assert.equal(9990000, line.cap)
    assert.equal(44000, line.usual)
  end)

  it("caps a line with no cap of its own by the percentage, as before", function()
    assert.equal(math.floor(44000 * 130 / 100), build({ { i = 5, q = 10, u = 44000 } }).cap)
  end)

  it("treats a zero cap as no cap at all", function()
    assert.equal(math.floor(44000 * 130 / 100), build({ { i = 5, q = 10, u = 44000, cc = 0 } }).cap)
  end)

  it("carries the realm a hit is bound to", function()
    local line = build({ { i = 5, q = 10, rl = { id = 1305, n = "Kazzak" } } })
    assert.equal("Kazzak", line.realmName)
    assert.equal(1305, line.realmID)
  end)

  it("normalises the recipe onto the line", function()
    local line = build({ { i = 50, q = 20, cr = { r = 900, n = 5, c = 2300, i = {
      { i = 51, q = 5, n = "Eversong Trout", u = 300 },
      { i = 52, q = 5, n = "Tavern Fixings", v = true, vu = 150 },
    } } } })
    assert.equal(900, line.craft.recipeID)
    assert.equal(5, line.craft.craftedQty)
    assert.equal(2300, line.craft.cost)
    assert.equal(2, #line.craft.reagents)
    assert.same({ itemID = 51, qty = 5, name = "Eversong Trout", vendor = false,
                  usual = 300, vendorUnit = nil }, line.craft.reagents[1])
    assert.is_true(line.craft.reagents[2].vendor)
    assert.equal(150, line.craft.reagents[2].vendorUnit)
  end)

  it("drops a recipe that yields nothing or names no reagent", function()
    assert.is_nil(build({ { i = 50, q = 20, cr = { n = 0, c = 10, i = { { i = 51, q = 5 } } } } }).craft)
    assert.is_nil(build({ { i = 50, q = 20, cr = { n = 5, c = 10, i = {} } } }).craft)
    assert.is_nil(build({ { i = 50, q = 20 } }).craft)
  end)
end)

describe("BuyRun splits a line into its reagents", function()
  local GC
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
  end)

  -- Thalassian Fillet (50): five to a craft, 2300c of reagents per craft -- five Eversong
  -- Trout (51) and five Tavern Fixings (52, a vendor reagent).
  local function fillet(over)
    local line = { i = 50, q = 20, u = 5800, n = "Thalassian Fillet",
      cr = { r = 900, n = 5, c = 2300, i = {
        { i = 51, q = 5, n = "Eversong Trout", u = 300 },
        { i = 52, q = 5, n = "Tavern Fixings", v = true, vu = 150 },
      } } }
    for k, v in pairs(over or {}) do line[k] = v end
    return line
  end

  local function build(lines, opts)
    opts = opts or {}
    local run = GC.BuyRun.New({ code = "abcd2345", lines = lines },
      { now = function() return 1000 end,
        haveOf = function(id) return (opts.have or {})[id] or 0 end,
        usualUnit = function() return nil end,
        capPct = function() return 130 end,
        freeLines = function() return opts.freeLines end,
        splits = function(code)
          assert.equal("abcd2345", code)
          return opts.splits
        end,
        progress = function() return opts.progress end })
    run:Refresh()
    return run
  end

  local function idsOf(run)
    local out = {}
    for _, line in ipairs(run:Lines()) do out[#out + 1] = tostring(line.itemID) end
    return out
  end

  local function lineOf(run, itemID)
    for _, line in ipairs(run:Lines()) do if line.itemID == itemID then return line end end
  end

  it("leaves a line nobody has split exactly as it was", function()
    local run = build({ fillet() })
    assert.same({ "50" }, idsOf(run))
    assert.is_nil(run:Lines()[1].kind)
    assert.equal(20, run:Lines()[1].buy)
  end)

  -- 20 needed, five to a craft: four crafts, and four crafts of five of each reagent.
  it("turns a split line into a craft line with its reagents under it", function()
    local run = build({ fillet() }, { splits = { [50] = true } })
    assert.same({ "50", "51", "52" }, idsOf(run))
    local parent = lineOf(run, 50)
    assert.equal("craft", parent.kind)
    assert.equal(4, parent.crafts)
    assert.equal(20, lineOf(run, 51).need)
    assert.equal(50, lineOf(run, 51).parent)
    assert.equal("Eversong Trout", lineOf(run, 51).name)
    assert.equal(20, lineOf(run, 52).need)
    assert.is_true(lineOf(run, 52).vendor)
    assert.equal(150, lineOf(run, 52).vendorUnit)
  end)

  -- The crafts arithmetic itself, pinned in both directions: what is left to get, rounded UP to
  -- a whole craft -- half a craft buys nothing -- and "left" counted against the LARGER of have
  -- and bought, the same rule `buy` follows (see Core/BuyRun.lua).
  it("rounds a part craft up to a whole one", function()
    local run = build({ fillet({ q = 22 }) }, { splits = { [50] = true } })
    assert.equal(5, lineOf(run, 50).crafts)      -- 22 at five a craft is five crafts, not four
    assert.equal(25, lineOf(run, 51).need)       -- and five crafts of five trout each
    assert.equal(25, lineOf(run, 52).need)
  end)

  -- The units this run already bought cover the need whether they are still in the bags or not:
  -- counting only `have` would re-craft everything the player bought and then used or mailed on.
  it("counts what the run already bought as covered, exactly as have is", function()
    local run = build({ fillet() },
      { have = { [50] = 3 }, progress = { [50] = { bought = 8, spent = 4000 } },
        splits = { [50] = true } })
    -- 20 needed, 8 of them accounted for (the larger of have 3 and bought 8), 12 left, five to
    -- a craft: three crafts, and three crafts of five trout.
    assert.equal(3, lineOf(run, 50).crafts)
    assert.equal(15, lineOf(run, 51).need)
  end)

  -- A reagent the run already asks for must not become a second line of the same item: the two
  -- would share one `bought` (progress is keyed by item id), so buying the first would mark the
  -- second done and the second's quantity could never be bought at all.
  it("grows a reagent the run already asks for instead of repeating it", function()
    local run = build({ fillet(), { i = 51, q = 7, n = "Eversong Trout" } },
      { splits = { [50] = true } })
    -- The merged line is an ordinary open line and keeps its own place; the craft block is the
    -- parent and the one reagent the split really added.
    assert.same({ "51", "50", "52" }, idsOf(run))
    local trout = lineOf(run, 51)
    assert.equal(27, trout.need)
    assert.is_nil(trout.parent)
    assert.same({ [50] = 20 }, trout.forCraft)
  end)

  -- A vendor line is a trip to an NPC at a fixed price: the recipe the site attached to the item
  -- describes what the item IS, it is not an offer to make one. Split, it would replace a copper
  -- purchase from a vendor with a shopping list of reagents bought at the auction house.
  it("never turns a vendor line into a craft, whatever recipe it carries", function()
    local run = build({ fillet({ v = true }) }, { splits = { [50] = true } })
    assert.same({ "50" }, idsOf(run))
    local line = lineOf(run, 50)
    assert.is_nil(line.craft)
    assert.is_nil(line.kind)
    assert.is_true(line.vendor)
    -- ...so there is nothing to compare and nothing for a row menu to offer either.
    assert.is_nil(GC.BuyRun.CraftText(line))
  end)

  it("orders the list open, then the craft block, then vendor, then done", function()
    local run = build({ { i = 40, q = 3 }, fillet(), { i = 41, q = 2, v = true },
                        { i = 42, q = 1 } },
      { splits = { [50] = true }, have = { [42] = 1 } })
    assert.same({ "40", "50", "51", "52", "41", "42" }, idsOf(run))
  end)

  -- The player crafted them: HAVE covers the need, so there is nothing left to craft and
  -- nothing left to buy for it.
  it("finishes a craft line once the crafted units are in hand", function()
    local run = build({ fillet() }, { splits = { [50] = true }, have = { [50] = 20 } })
    local parent = lineOf(run, 50)
    assert.equal("craft", parent.kind)
    assert.equal(0, parent.crafts)
    assert.is_true(parent.done)
    assert.same({ "50" }, idsOf(run))     -- no reagents: nothing left to craft
  end)

  -- The gold goes on the reagents, which are lines of their own. Counting the craft line too
  -- would charge the player twice for the same crafts.
  it("counts the reagents into what is left, never the craft line itself", function()
    local run = build({ fillet() }, { splits = { [50] = true } })
    local totals = run:Totals()
    assert.equal(20 * 300 + 20 * 150, totals.left)
    assert.equal(1, totals.toCraft)
    assert.equal(1, totals.toBuy)         -- the trout
    assert.equal(1, totals.atVendor)      -- the fixings
    assert.equal(3, totals.lines)
  end)

  -- A reagent a split put under a line is part of that line, not another one of them. The tab
  -- says how many lines a run HAS in more than one wording (UI/BuyFrame.lua calls an alert
  -- group's lines its hits), and a split must not be able to inflate the count.
  it("counts the run's own lines apart from the reagents a split added", function()
    local run = build({ { i = 40, q = 3 }, fillet() }, { splits = { [50] = true } })
    local totals = run:Totals()
    assert.equal(4, totals.lines)
    assert.equal(2, totals.topLines)
  end)

  -- Nothing may spend gold on a craft line: there is no auction house lot that IS the crafted
  -- item's recipe, and its own units are what the reagents become.
  it("refuses to quote a purchase for a craft line", function()
    local run = build({ fillet() }, { splits = { [50] = true } })
    local qty, total, capped = run:PurchaseQuantity(50, { { unit = 10, qty = 100 } })
    assert.equal(0, qty)
    assert.equal(0, total)
    assert.is_false(capped)
    -- ...while its reagents quote exactly like any other line.
    assert.equal(20, (run:PurchaseQuantity(51, { { unit = 10, qty = 100 } })))
  end)

  -- The free-line gate is about which lines of the RUN are unlocked. A reagent is not a line of
  -- the run: it may not consume a slot, and it may not be free while the line it came out of is
  -- not.
  it("gives a reagent the lock of the line it was split out of", function()
    local run = build({ { i = 40, q = 3 }, fillet() },
      { splits = { [50] = true }, freeLines = 1 })
    assert.is_false(lineOf(run, 40).locked)
    assert.is_true(lineOf(run, 50).locked)
    assert.is_true(lineOf(run, 51).locked)
    assert.is_nil(lineOf(run, 51).index)
    assert.equal(2, lineOf(run, 50).index)
  end)

  it("still builds a run whose driver knows nothing about splits", function()
    local run = GC.BuyRun.New({ code = "x", lines = { fillet() } },
      { now = function() return 0 end, haveOf = function() return 0 end,
        usualUnit = function() return nil end, capPct = function() return 130 end,
        freeLines = function() return nil end })
    run:Refresh()
    assert.equal(1, #run:Lines())
    assert.is_nil(run:Lines()[1].kind)
  end)
end)

describe("BuyRun's craft-or-buy comparison", function()
  local GC
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
  end)

  local function line(over)
    local l = { itemID = 50, usual = 5800, craft = { recipeID = 900, craftedQty = 5, cost = 2300,
      reagents = {
        { itemID = 51, qty = 5, name = "Eversong Trout" },
        { itemID = 52, qty = 5, name = "Tavern Fixings" },
      } } }
    for k, v in pairs(over or {}) do l[k] = v end
    return l
  end

  -- 2300c of reagents for five units is 460c each, against 5800c at the auction house.
  it("prices one crafted unit against one bought unit", function()
    local compare = GC.BuyRun.CraftText(line())
    assert.equal(460, compare.unit)
    assert.equal(5800, compare.ahUnit)
    assert.is_true(compare.cheaper)
    assert.equal(5, compare.craftedQty)
    assert.same({ { itemID = 51, qty = 5, name = "Eversong Trout" },
                  { itemID = 52, qty = 5, name = "Tavern Fixings" } }, compare.reagents)
  end)

  -- A price actually seen on this realm beats the site's reference price: the comparison is a
  -- statement about what the auction house is asking now.
  it("prefers the price the auction house is actually asking", function()
    assert.equal(400, GC.BuyRun.CraftText(line({ floor = 400 })).ahUnit)
    assert.is_false(GC.BuyRun.CraftText(line({ floor = 400 })).cheaper)
  end)

  it("says nothing about being cheaper when there is no price to compare against", function()
    local l = line()
    l.usual = nil
    local compare = GC.BuyRun.CraftText(l)
    assert.equal(460, compare.unit)
    assert.is_nil(compare.ahUnit)
    assert.is_false(compare.cheaper)
  end)

  it("carries the craft count of a line that is already split", function()
    assert.equal(4, GC.BuyRun.CraftText(line({ crafts = 4 })).crafts)
  end)

  it("answers nothing for a line with no recipe", function()
    assert.is_nil(GC.BuyRun.CraftText({ itemID = 50, usual = 5800 }))
    assert.is_nil(GC.BuyRun.CraftText(nil))
  end)
end)
