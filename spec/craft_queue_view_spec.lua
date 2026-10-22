local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")

-- UI/CraftQueueView.lua: the panel's Queue view. Each queued recipe with what is left to craft, the
-- reagents the queue is short of, and Make a BUY list, which writes what the queue needs into the
-- character's one Craft queue list, the list the queue then keeps in step with itself.
describe("craft queue view", function()
  local GC, P, QV, restore, VALUES, printed, selected, refreshed

  local function commodity(mv, sold)
    return { mv = mv, sold = sold, ts = 0, source = "import", kind = "region_commodity" }
  end

  -- Recipe 3 (Potion) makes 903 from two of Item A; recipe 5 (Flask) makes 905 from one. Item A
  -- comes in three qualities, 101 to 103.
  local function recipes()
    return {
      [3] = { info = TS.info(3, "Potion"), schematic = TS.schematic(3, 903, { TS.slot(1, 2, TS.items(101, 102, 103)) }) },
      [5] = { info = TS.info(5, "Flask"), schematic = TS.schematic(5, 905, { TS.slot(1, 1, TS.items(101, 102, 103)) }) },
      [7] = { info = TS.info(7, "Elixir"), schematic = TS.schematic(7, 907, { TS.slot(1, 1, TS.items(101)), TS.slot(2, 2, { { currencyID = 3008 } }) }) },
    }
  end

  local function load(opts)
    opts = opts or {}
    opts.recipes = opts.recipes or recipes()
    opts.filtered = opts.filtered or { 3, 5 }
    opts.professionID = 2823
    opts.open = opts.open or { recipeID = 3, allocations = {} }
    opts.names = opts.names or { [101] = "Item A", [102] = "Item A", [103] = "Item A" }
    opts.currencies = { [3008] = "Valorstones" }
    restore = TS.install(opts)
    GC = TS.craftGC()
    VALUES = {}
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    GC.Ledger = { Context = function() return { char = "Name-Realm" } end }
    GC.db = {}
    helper.loadModule("Core/AppRuns.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)
    printed, selected, refreshed = {}, {}, 0
    GC.Print = function(msg) printed[#printed + 1] = msg end
    GC.Buy = { SelectRun = function(code) selected[#selected + 1] = code end, RefreshIfShown = function() refreshed = refreshed + 1 end }
    helper.loadModule("UI/CraftPanel.lua", GC)
    helper.loadModule("UI/CraftQueueView.lua", GC)
    P, QV = GC.CraftPanel, GC.CraftQueueView
  end

  local function snapshot(id) return GC.CraftClient.Snapshot(id) end

  -- Opens the window, then the Queue view.
  local function showQueue()
    local ev = P._events
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    TS.runTimers()
    local f = P._frame
    f.switch.queue:GetScript("OnClick")(f.switch.queue)
    TS.runTimers()
    return QV._frame
  end

  local function lineTexts(i)
    local w = QV._rows[i].widget
    local out = { w.name:GetText(), w.detail:GetText() }
    if w.note:IsShown() then out[#out + 1] = w.note:GetText() end
    return out
  end

  local function missingTexts(v)
    local out = {}
    for _, fs in ipairs(v.missingLines) do if fs:IsShown() then out[#out + 1] = fs:GetText() end end
    return out
  end

  local function codes()
    local out = {}
    for code in pairs(GC.db.runs or {}) do out[#out + 1] = code end
    table.sort(out)
    return out
  end

  local function linesOf(run)
    local out = {}
    for n, line in ipairs(run.lines) do out[n] = { line.i, line.q } end
    return out
  end

  local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
  end

  -- What BUY buys of each line of `run` and the BuyRun it worked that out with: Core/BuyRun.lua
  -- with UI/BuyFrame.lua's driver for this character (held from the same count the queue reads,
  -- what was bought for the list from GC.db.buyProgress).
  local function buyRun(run)
    local r = GC.BuyRun.New(run, {
      now = function() return 1 end,
      haveOf = function(id) return (TS.opts.counts or {})[id] or 0 end,
      usualUnit = function() return nil end,
      capPct = function() return 130 end,
      progress = function(code)
        GC.db.buyProgress = GC.db.buyProgress or {}
        local mine = GC.db.buyProgress["Name-Realm"] or {}
        GC.db.buyProgress["Name-Realm"] = mine
        mine[code] = mine[code] or {}
        return mine[code]
      end,
    })
    r:Refresh()
    local out = {}
    for _, line in ipairs(r:Lines()) do out[line.itemID] = line.buy end
    return out, r
  end

  -- A finished cast of `spellID`, as the client fires it.
  local function crafted(spellID, times)
    local ev = QV._events
    for _ = 1, times or 1 do
      ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. spellID, spellID)
    end
    TS.runTimers()
  end

  -- The entries of a queue line's right click menu.
  local function lineMenu(i)
    local entries = {}
    local saved = _G.MenuUtil
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      generator(nil, {
        CreateTitle = function() end,
        CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
      })
    end }
    local line = QV._rows[i].widget.frame
    line:GetScript("OnClick")(line, "RightButton")
    _G.MenuUtil = saved
    return entries
  end

  after_each(function() if restore then restore() end end)

  it("lists each queued recipe with what is left to craft", function()
    load({ counts = { [905] = 3 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
    GC.CraftQueue.FoldListed("Name-Realm", { { itemKey = { itemID = 905 }, quantity = 1, status = 0 } }, time())
    showQueue()
    assert.equal(2, #QV._rows)
    assert.same({ "Potion", GC.L["%d to craft"]:format(3) }, lineTexts(1))
    assert.same({ "Flask", GC.L["Restock to %d: %d held"]:format(10, 4) }, lineTexts(2))
    assert.equal(3, QV._rows[1].crafts)
    assert.equal(6, QV._rows[2].crafts)
  end)

  it("says listings are not counted until the auction house is seen", function()
    load({ counts = { [905] = 3 }, owned = { { auctionID = 1, itemKey = { itemID = 905 }, quantity = 2, status = 0 },
      { auctionID = 2, itemKey = { itemID = 905 }, quantity = 5, status = 1 } } })
    GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
    showQueue()
    assert.same({ "Flask", GC.L["Restock to %d: %d held"]:format(10, 3),
      GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] }, lineTexts(1))
    local ev = QV._events
    assert.is_true(ev:IsEventRegistered("OWNED_AUCTIONS_UPDATED"))
    ev:GetScript("OnEvent")(ev, "OWNED_AUCTIONS_UPDATED")
    TS.runTimers()
    assert.same({ "Flask", GC.L["Restock to %d: %d held"]:format(10, 5) }, lineTexts(1))
  end)

  it("stops counting auctions read more than 48 hours ago, and says so", function()
    load({ counts = { [905] = 3 } })
    GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
    GC.CraftQueue.FoldListed("Name-Realm", { { itemKey = { itemID = 905 }, quantity = 2, status = 0 } },
      time() - 48 * 3600 - 60)
    showQueue()
    assert.same({ "Flask", GC.L["Restock to %d: %d held"]:format(10, 3),
      GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] }, lineTexts(1))
    assert.equal(7, QV._rows[1].crafts)
  end)

  it("says the queue is empty", function()
    load()
    local v = showQueue()
    assert.equal(0, #QV._rows)
    assert.is_true(v.empty:IsShown())
    assert.equal(GC.L["The queue is empty. Add a recipe from This recipe."], v.empty:GetText())
  end)

  it("lists only what is short, summed across recipes", function()
    load({ counts = { [101] = 4, [103] = 1 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 3)
    local v = showQueue()
    assert.equal(GC.L["Missing"], v.missingHeading:GetText())
    assert.same({ GC.L["%d %s"]:format(2, "Item A") }, missingTexts(v))
    assert.is_false(v.none:IsShown())
  end)

  it("Make a BUY list makes the character's Craft queue list and opens it in BUY, one list however often it is pressed", function()
    load({ counts = { [101] = 4, [103] = 1 } })
    VALUES[101], VALUES[102], VALUES[103] = commodity(500), commodity(450), commodity(400)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 3)
    local v = showQueue()
    assert.is_true(v.buy:IsEnabled())
    v.buy:GetScript("OnClick")(v.buy)
    assert.equal(1, #codes())
    local run = GC.db.runs[codes()[1]]
    -- Named after the character: lists are account wide, so two characters' queues read apart.
    assert.equal(GC.L["Craft queue"] .. ": Name", run.name)
    -- 7 of Item A in all, 4 of them held as 101: BUY buys 3 of 103, less the one it sees held.
    assert.same({ { 103, 3 } }, linesOf(run))
    assert.same({ run.code }, selected)
    assert.equal(1, refreshed)
    assert.same({ GC.L["BUY list %s is ready in the BUY tab at the auction house"]:format(GC.L["Craft queue"] .. ": Name") }, printed)
    -- Recognised by its code, kept per character, not by its name.
    assert.equal(run.code, GC.CraftQueue.BuyList("Name-Realm"))
    -- A second press writes into the same list: never a second one.
    v.buy:GetScript("OnClick")(v.buy)
    assert.same({ run.code }, codes())
    assert.same({ run.code, run.code }, selected)
  end)

  it("makes the list again once the player deleted it, and brings it out of the archive", function()
    load({ counts = {} })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 1)
    local first = QV.MakeBuyList()
    GC.AppRuns.SetArchived(first.code, true)
    assert.equal(first, QV.MakeBuyList())
    assert.is_false(GC.AppRuns.IsArchived(first.code))
    GC.AppRuns.Remove(first.code)
    -- A queue change alone makes nothing: only the button does.
    crafted(5)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
    P.OnQueueChanged()
    assert.same({}, codes())
    local made = QV.MakeBuyList()
    assert.is_true(made.code ~= first.code)
    assert.same({ made.code }, codes())
    assert.equal(made.code, GC.CraftQueue.BuyList("Name-Realm"))
  end)

  it("never touches the player's other lists, one named Craft queue included", function()
    load({ counts = {} })
    local mine = GC.AppRuns.NewList(GC.L["Craft queue"], { { i = 101, q = 7 } })
    local before = copy(mine)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    showQueue()
    local run = QV.MakeBuyList()
    assert.is_true(run.code ~= mine.code)
    crafted(3)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
    P.OnQueueChanged()
    lineMenu(1)[3].fn()
    TS.runTimers()
    QV.MakeBuyList()
    assert.same(before, GC.db.runs[mine.code])
    assert.equal(2, #codes())
  end)

  it("keeps the list in step with the queue: a finished craft, an add and a removal, down to empty", function()
    load({ counts = {} })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    showQueue()
    local run = QV.MakeBuyList()
    assert.same({ { 101, 6 } }, linesOf(run))
    -- A Potion takes two of Item A: two fewer to buy.
    crafted(3)
    assert.same({ { 101, 4 } }, linesOf(run))
    -- The panel adds a Flask, one more.
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
    P.OnQueueChanged()
    assert.same({ { 101, 5 } }, linesOf(run))
    -- The Flask taken off from its line's menu.
    TS.runTimers()
    assert.equal("Flask", QV._rows[2].widget.name:GetText())
    lineMenu(2)[3].fn()
    TS.runTimers()
    assert.same({ { 101, 4 } }, linesOf(run))
    -- The last two Potions: an empty queue leaves the list, empty.
    crafted(3, 2)
    assert.same({}, GC.CraftQueue.Entries("Name-Realm"))
    assert.equal(run, GC.AppRuns.Get(run.code))
    assert.same({}, run.lines)
  end)

  it("lets BUY buy nothing a craft already used", function()
    load({ counts = { [101] = 4 } })
    VALUES[101], VALUES[102], VALUES[103] = commodity(400), commodity(450), commodity(500)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    assert.same({ { 101, 10 } }, linesOf(run))
    assert.equal(6, buyRun(run)[101])
    -- Two Potions use the four held, before anything is bought: still six short, not ten.
    TS.opts.counts[101] = 0
    crafted(3, 2)
    assert.same({ { 101, 6 } }, linesOf(run))
    assert.equal(6, buyRun(run)[101])
  end)

  it("lets BUY buy the rest after some was bought and used", function()
    load({ counts = {} })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    local _, r = buyRun(run)
    r:RecordPurchase(101, 4, 1600, 1)
    TS.opts.counts[101] = 4
    assert.equal(6, buyRun(run)[101])
    -- Two Potions use the four bought: six still to buy, none of them counted as bought.
    TS.opts.counts[101] = 0
    crafted(3, 2)
    assert.equal(6, buyRun(run)[101])
    -- Bought into the mailbox (bags full): not held, but bought, and not bought again.
    _, r = buyRun(run)
    r:RecordPurchase(101, 6, 2400, 2)
    assert.equal(0, buyRun(run)[101])
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
    P.OnQueueChanged()
    assert.equal(1, buyRun(run)[101])
  end)

  it("follows a restock as what it holds changes", function()
    load({ counts = {} })
    GC.CraftQueue.Restock("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    assert.same({ { 101, 10 } }, linesOf(run))
    -- Two Potions made: the restock needs three more, which reach the bags after the cast.
    TS.opts.counts[903] = 2
    local ev = QV._events
    assert.is_true(ev:IsEventRegistered("BAG_UPDATE_DELAYED"))
    ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
    assert.same({ { 101, 6 } }, linesOf(run))
  end)

  it("rebuilds the list BUY holds when the queue changes it, never under a purchase", function()
    load({ counts = {} })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    local run = QV.MakeBuyList()
    selected = {}
    local inFlight = false
    GC.Buy.CurrentRun = function() return { Code = function() return run.code end } end
    GC.Buy._InFlight = function() return inFlight end
    crafted(3)
    assert.same({ run.code }, selected)
    inFlight = true
    crafted(3)
    assert.same({ run.code }, selected)
    assert.same({ { 101, 2 } }, linesOf(run))
  end)

  it("leaves a store and a list a newer GoldCap wrote as they are", function()
    load({ counts = {} })
    GC.db.craft = { v = 2, chars = { ["Name-Realm"] = { entries = { { recipe = snapshot(3), count = 2 } },
      listed = {}, buyList = "game-1" } } }
    GC.db.runs = { ["game-1"] = { code = "game-1", origin = "game", name = "Craft queue", createdAt = 1, updatedAt = 1,
      lines = { { i = 101, q = 3, v = false } } } }
    local craft, runs = copy(GC.db.craft), copy(GC.db.runs)
    local v = showQueue()
    assert.is_false(v.buy:IsEnabled())
    assert.is_nil(QV.MakeBuyList())
    crafted(3)
    local ev = QV._events
    ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
    P.OnQueueChanged()
    TS.runTimers()
    assert.same(craft, GC.db.craft)
    assert.same(runs, GC.db.runs)
  end)

  it("puts a reagent a vendor sells on the BUY list as a vendor stop", function()
    load({ counts = { [101] = 1 } })
    -- A list the player holds says a vendor sells Item A for 50 (Core/AppRuns.lua's VendorUnitFor).
    GC.db.runs = { vendor = { code = "vendor", updatedAt = 1, lines = { { i = 101, q = 1, v = true, vu = 50 } } } }
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    showQueue()
    local run = QV.MakeBuyList()
    assert.equal(1, #run.lines)
    assert.same({ 101, 4, true, 50 }, { run.lines[1].i, run.lines[1].q, run.lines[1].v, run.lines[1].vu })
  end)

  it("leaves a currency off the BUY list and says it is not on the auction house", function()
    load({ filtered = { 7 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
    local v = showQueue()
    assert.same({ GC.L["%d %s"]:format(1, "Item A"), GC.L["%s is not sold on the auction house"]:format("Valorstones") },
      missingTexts(v))
    local run = QV.MakeBuyList()
    assert.same({ { 101, 1 } }, { { run.lines[1].i, run.lines[1].q } })
    assert.equal(1, #run.lines)
  end)

  it("names a currency only when the player holds too little of it, and can say nothing is missing", function()
    load({ filtered = { 7 }, counts = { [101] = 1 }, currencyHeld = { [3008] = 2 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
    local v = showQueue()
    assert.same({}, missingTexts(v))
    assert.is_true(v.none:IsShown())
    assert.equal(GC.L["Nothing is missing for the queue"], v.none:GetText())
    restore()
    load({ filtered = { 7 }, counts = { [101] = 1 }, currencyHeld = { [3008] = 1 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
    v = showQueue()
    assert.same({ GC.L["%s is not sold on the auction house"]:format("Valorstones") }, missingTexts(v))
    assert.is_false(v.none:IsShown())
  end)

  it("disables Make a BUY list when nothing is missing", function()
    load({ counts = { [101] = 10 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    local v = showQueue()
    assert.same({}, missingTexts(v))
    assert.is_true(v.none:IsShown())
    assert.equal(GC.L["Nothing is missing for the queue"], v.none:GetText())
    assert.is_false(v.buy:IsEnabled())
    assert.is_nil(QV.MakeBuyList())
  end)

  it("a bag change repaints what is missing", function()
    load({ counts = { [101] = 1 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    local v = showQueue()
    assert.same({ GC.L["%d %s"]:format(3, "Item A") }, missingTexts(v))
    TS.opts.counts[101] = 4
    local ev = P._events
    ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
    TS.runTimers()
    assert.same({}, missingTexts(v))
    assert.is_true(v.none:IsShown())
  end)

  it("a finished craft takes one off its line", function()
    load()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    showQueue()
    local ev = QV._events
    assert.is_true(ev:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED"))
    ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1234-5678-9-3-ABCDEF", 3)
    TS.runTimers()
    assert.same({ "Potion", GC.L["%d to craft"]:format(2) }, lineTexts(1))
    ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1234-5678-9-133-ABCDEF", 133)
    TS.runTimers()
    assert.same({ "Potion", GC.L["%d to craft"]:format(2) }, lineTexts(1))
  end)

  it("counts a craft while the window is closed too", function()
    load()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 1)
    local ev = QV._events
    ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 3)
    TS.runTimers()
    assert.same({}, GC.CraftQueue.Entries("Name-Realm"))
  end)

  it("the switch shows one view at a time", function()
    load()
    local v = showQueue()
    local f = P._frame
    assert.is_true(v:IsShown())
    assert.is_false(f.worth:IsShown())
    assert.equal(f.body, v:GetParent())
    f.switch.worth:GetScript("OnClick")(f.switch.worth)
    TS.runTimers()
    assert.is_false(v:IsShown())
    assert.is_true(f.worth:IsShown())
    assert.equal(GC.L["Worth crafting"], f.switch.worth.label)
    assert.equal(GC.L["Queue"], f.switch.queue.label)
    for _, b in ipairs({ f.switch.worth, f.switch.queue }) do
      assert.is_true(b:GetWidth() >= b.text:GetUnboundedStringWidth())
    end
  end)

  it("offers the queue's own changes on a line's right click", function()
    load()
    local savedUIParent = _G.UIParent
    finally(function() _G.UIParent = savedUIParent end)
    _G.UIParent = W.CreateFrame("Frame")
    helper.loadModule("UI/BuyCapEditor.lua", GC)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
    showQueue()
    local entries = {}
    local saved = _G.MenuUtil
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      generator(nil, {
        CreateTitle = function() end,
        CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
      })
    end }
    local line = QV._rows[1].widget.frame
    line:GetScript("OnClick")(line, "RightButton")
    _G.MenuUtil = saved
    local texts = {}
    for _, e in ipairs(entries) do texts[#texts + 1] = e.text end
    assert.same({ GC.Util.ClientText(GC.L["Add to queue"]), GC.Util.ClientText(GC.L["Restock to"]),
      GC.Util.ClientText(GC.L["Remove from queue"]) }, texts)
    entries[3].fn()
    TS.runTimers()
    assert.equal(1, #QV._rows)
    assert.equal("Flask", QV._rows[1].widget.name:GetText())
  end)

  it("repaints when the panel adds to the queue", function()
    load()
    showQueue()
    assert.equal(QV.OnQueueChanged, P.OnQueueChanged)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 2)
    P.OnQueueChanged()
    assert.equal(1, #QV._rows)
  end)

  it("registers its events through pcall", function()
    local file = assert(io.open("GoldCap/UI/CraftQueueView.lua", "r"))
    local src = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    assert.is_nil(src:find(":RegisterEvent%("))
    assert.is_nil(src:find(":RegisterUnitEvent%("))
    assert.is_truthy(src:find('pcall%(events%.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player"%)'))
    assert.is_nil(src:find("CraftRecipe", 1, true))
    assert.is_nil(src:find("hooksecurefunc", 1, true))
  end)
end)
