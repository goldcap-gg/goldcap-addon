local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")
local Mailbox = require("spec.support.mail_inbox")

-- UI/CraftQueueView.lua: the panel's Queue view, as the owner approved it (canvas version 17). A
-- line per queued recipe with its item, what is left, how far along it is and Craft N, live, dimmed
-- or busy while the client crafts it; then Missing, a cell per reagent the queue is short of with
-- what waits in the mailbox and what the rest costs, and Make a BUY list, which writes what the
-- queue needs into the character's one Craft queue list, the list the queue then keeps in step
-- with itself.
describe("craft queue view", function()
  local GC, P, QV, K, restore, VALUES, printed, selected, refreshed, buyTab

  local function commodity(mv, sold)
    return { mv = mv, sold = sold, ts = 0, source = "import", kind = "region_commodity" }
  end

  -- Recipe 3 (Potion) makes 903 from two of Item A; recipe 5 (Flask) makes 905 from one. Item A
  -- comes in three qualities, 101 to 103. Recipe 7 (Elixir) takes a currency too, recipe 9 (Tonic)
  -- one of Item A and one of Item B (111), which has no price.
  local function recipes()
    return {
      [3] = { info = TS.info(3, "Potion"), schematic = TS.schematic(3, 903, { TS.slot(1, 2, TS.items(101, 102, 103)) }) },
      [5] = { info = TS.info(5, "Flask"), schematic = TS.schematic(5, 905, { TS.slot(1, 1, TS.items(101, 102, 103)) }) },
      [7] = { info = TS.info(7, "Elixir"), schematic = TS.schematic(7, 907, { TS.slot(1, 1, TS.items(101)), TS.slot(2, 2, { { currencyID = 3008 } }) }) },
      [9] = { info = TS.info(9, "Tonic"), schematic = TS.schematic(9, 909, { TS.slot(1, 1, TS.items(101, 102, 103)), TS.slot(2, 1, TS.items(111)) }) },
    }
  end

  local function load(opts)
    opts = opts or {}
    opts.recipes = opts.recipes or recipes()
    opts.filtered = opts.filtered or { 3, 5 }
    opts.professionID = 2823
    opts.open = opts.open or { recipeID = 3, allocations = {} }
    opts.names = opts.names or { [101] = "Item A", [102] = "Item A", [103] = "Item A", [111] = "Item B" }
    opts.icons = opts.icons or { [101] = 1101, [111] = 1111, [903] = 1903, [905] = 1905 }
    opts.currencies = { [3008] = "Valorstones" }
    restore = TS.install(opts)
    -- BUY asks the client what the character owns and what it carries, and counts the difference
    -- as the banks (UI/BuyFrame.lua's bankOf). The spec's counts are all owned and none walked in
    -- a bag, so BUY reads them as banked: the same total the queue reads.
    local owned = _G.C_Item.GetItemCount
    _G.C_Item.GetItemCount = function(id, includeBank, ...)
      local n = owned(id, includeBank, ...)
      return includeBank and n or 0
    end
    GC = TS.craftGC()
    K = GC.Kit.Tokens.color
    VALUES = {}
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    GC.db = {}
    -- The real ledger, whose inbox scan reads the mailbox for Core/MailStock.lua; a headless run
    -- has no player, so only the character is faked.
    helper.loadModule("Core/Ledger.lua", GC)
    GC.Ledger.Init(GC.db)
    GC.Ledger.Context = function() return { char = "Name-Realm", region = "eu" } end
    helper.loadModule("Core/MailClassify.lua", GC)
    helper.loadModule("Core/MailStock.lua", GC)
    helper.loadModule("Core/AppRuns.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)
    printed, selected, refreshed = {}, {}, 0
    GC.Print = function(msg) printed[#printed + 1] = msg end
    GC.Buy = { SelectRun = function(code) selected[#selected + 1] = code end, RefreshIfShown = function() refreshed = refreshed + 1 end }
    helper.loadModule("UI/CraftPanel.lua", GC)
    helper.loadModule("UI/CraftQueueView.lua", GC)
    P, QV = GC.CraftPanel, GC.CraftQueueView
    -- The BUY tab itself (UI/BuyFrame.lua), over this GC's SavedVariables, lists and mailbox and
    -- loaded beside the GC.Buy double the queue view talks to: its own driver works out HAVE and
    -- what each line still buys.
    helper.loadModule("Core/DealMath.lua", GC)
    local tab = setmetatable({}, { __index = GC })
    helper.loadModule("UI/BuyFrame.lua", tab)
    buyTab = tab.Buy
  end

  local function snapshot(id) return GC.CraftClient.Snapshot(id) end

  -- An event as the client delivers it: to every frame registered for it (Services/CraftClient.lua's,
  -- the panel's and this view's), then a frame passes.
  local function fire(event, ...)
    for _, ev in ipairs({ GC.CraftClient._events, P._events, QV._events }) do
      if ev:IsEventRegistered(event) then ev:GetScript("OnEvent")(ev, event, ...) end
    end
    TS.runTimers()
  end

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

  local function line(i) return QV._rows[i].widget end

  -- A line's name and what it says, then the notes it shows under its bar.
  local function lineTexts(i)
    local w = line(i)
    local out = { w.name:GetText(), w.detail:GetText() }
    for _, fs in ipairs({ w.note, w.listed }) do
      if fs:IsShown() then out[#out + 1] = fs:GetText() end
    end
    return out
  end

  -- What Missing shows: a cell per reagent ({ name, count, mail, price }, a field left out where the
  -- cell says nothing of it).
  local function cellsOf(v)
    local out = {}
    for _, cell in ipairs(v.cells) do
      if cell:IsShown() then
        out[#out + 1] = { name = cell.name:GetText(), count = cell.slot.count:GetText(),
          mail = cell.mail:IsShown() and cell.mail:GetText() or nil,
          price = cell.price:IsShown() and cell.price:GetText() or nil }
      end
    end
    return out
  end

  local function currenciesOf(v)
    local out = {}
    for _, fs in ipairs(v.currencies) do if fs:IsShown() then out[#out + 1] = fs:GetText() end end
    return out
  end

  local function rgb(fs)
    local r, g, b = fs:GetTextColor()
    return { r, g, b }
  end

  local function same(c) return { c[1], c[2], c[3] } end

  local function vertex(t)
    local c = W.state(t).vertex
    return { c[1], c[2], c[3], c[4] }
  end

  local function codes()
    local out = {}
    for code in pairs(GC.db.runs or {}) do out[#out + 1] = code end
    table.sort(out)
    return out
  end

  local function linesOf(run)
    local out = {}
    for n, l in ipairs(run.lines) do out[n] = { l.i, l.q } end
    return out
  end

  local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
  end

  -- What BUY buys of each line of `run` and the BuyRun it worked that out with: the BUY tab picks
  -- the list, as the run cycle does, and its own driver reads HAVE (bags, banks and what
  -- Core/MailStock.lua says waits in the mailbox) and what was bought for the list.
  local function buyRun(run)
    buyTab.SelectRun(run.code)
    local r = buyTab.CurrentRun()
    local out = {}
    for _, l in ipairs(r:Lines()) do out[l.itemID] = l.buy end
    return out, r
  end

  -- A purchase at the auction house as UI/BuyFrame.lua's settlePurchase books it: against the list,
  -- and on its way to the mailbox, where retail delivers every purchase. The bags do not change.
  local function purchase(run, itemID, qty)
    local _, r = buyRun(run)
    r:RecordPurchase(itemID, qty, 400 * qty, 1)
    GC.MailStock.Bought("Name-Realm", itemID, qty)
  end

  -- Just delivered: an auction house mail has 30 days left when it arrives.
  local function wonMail(itemID, count)
    return { sender = "Auction House", subject = "Auction won: Item A", auction = true, daysLeft = 30,
      invoice = { invoiceType = "buyer", itemName = "Item A", count = count, bid = 400 * count },
      items = { [1] = { itemID = itemID, count = count } } }
  end

  -- One pass of the ledger's inbox scan, as Core/Init.lua runs it while the mailbox shows
  -- (`opening` for MAIL_SHOW's).
  local function readMailbox(box, opening)
    GC.Ledger.ScanInbox(box.api, GC.Ledger.Context(), time(), opening)
  end

  local function bagsChanged()
    local ev = QV._events
    ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
    TS.runTimers()
  end

  -- Takes the first mail's first attachment, as a click on it does, and puts it in the bags.
  local function takeFirst(box, itemID, count)
    box.api.TakeInboxItem(1, 1)
    box:advance()
    TS.opts.counts[itemID] = (TS.opts.counts[itemID] or 0) + count
    readMailbox(box)
  end

  local function mailClosed()
    local ev = QV._events
    ev:GetScript("OnEvent")(ev, "MAIL_CLOSED")
    TS.runTimers()
  end

  -- The character has opened the mailbox once before: Core/MailStock.lua takes nothing in a
  -- character's first read for a delivery.
  local function visitedMailbox()
    readMailbox(Mailbox.new({ { sender = "Friend", subject = "Hi", canReply = true } }), true)
    mailClosed()
  end

  -- A finished cast of `spellID`, as the client fires it at this view.
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
    local frame = line(i).frame
    frame:GetScript("OnClick")(frame, "RightButton")
    _G.MenuUtil = saved
    return entries
  end

  -- GameTooltip as the Craft button's hover uses it: the owner and the text.
  local function tooltip()
    local saved = _G.GameTooltip
    local tip = {}
    _G.GameTooltip = {
      SetOwner = function(_, owner) tip.owner = owner end,
      SetText = function(_, text) tip.text = text end,
      Show = function() tip.shown = true end,
      Hide = function() tip.shown = false end,
    }
    return tip, function() _G.GameTooltip = saved end
  end

  local function hover(button) W.state(button).hooks.OnEnter(button) end

  after_each(function()
    if restore then restore() end
    W.unknownEvents = {}
  end)

  describe("a line", function()
    -- Reagents for every line, so no line says why it cannot craft.
    local function stocked()
      local r = recipes()
      r[3].craftable, r[5].craftable = 9, 9
      return r
    end

    it("shows each queued recipe's item, its name and what is left to craft", function()
      load({ recipes = stocked(), counts = { [905] = 3 }, tiers = { [903] = 2 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
      GC.CraftQueue.FoldListed("Name-Realm", { { itemKey = { itemID = 905 }, quantity = 1, status = 0 } }, time())
      local v = showQueue()
      assert.equal(2, #QV._rows)
      assert.same({ "Potion", GC.L["%d to craft"]:format(3) }, lineTexts(1))
      assert.same({ "Flask", GC.L["Restock to %d: you hold %d, %d crafts"]:format(10, 4, 6) }, lineTexts(2))
      assert.equal(3, QV._rows[1].crafts)
      assert.equal(6, QV._rows[2].crafts)
      -- What the recipe makes, with its crafting quality top left where it has one.
      assert.equal(1903, W.state(line(1).slot.icon).file)
      assert.is_true(line(1).slot.pip:IsShown())
      assert.equal("Professions-Icon-Quality-Tier2-Small", W.state(line(1).slot.pip).atlas)
      assert.equal(1905, W.state(line(2).slot.icon).file)
      assert.is_false(line(2).slot.pip:IsShown())
      -- Each a card on the glass, one under the other in the view's scroll.
      assert.same(K.glassTop, vertex(line(1).frame.fill))
      assert.same(K.glassBorder, vertex(line(1).frame.ring))
      assert.equal(v.content, line(1).frame:GetParent())
      local _, _, _, _, y = line(2).frame:GetPoint(1)
      assert.is_true(-y >= line(1).frame:GetHeight())
    end)

    it("says a restock that needs one craft in its own words", function()
      load({ recipes = stocked(), counts = { [905] = 9 } })
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
      GC.CraftQueue.FoldListed("Name-Realm", {}, time())
      showQueue()
      assert.same({ "Flask", GC.L["Restock to %d: you hold %d, 1 craft"]:format(10, 9) }, lineTexts(1))
    end)

    it("says listings are not counted until the auction house is seen", function()
      load({ recipes = stocked(), counts = { [905] = 3 }, owned = { { auctionID = 1, itemKey = { itemID = 905 }, quantity = 2, status = 0 },
        { auctionID = 2, itemKey = { itemID = 905 }, quantity = 5, status = 1 } } })
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
      showQueue()
      assert.same({ "Flask", GC.L["Restock to %d: you hold %d, %d crafts"]:format(10, 3, 7),
        GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] }, lineTexts(1))
      local ev = QV._events
      assert.is_true(ev:IsEventRegistered("OWNED_AUCTIONS_UPDATED"))
      ev:GetScript("OnEvent")(ev, "OWNED_AUCTIONS_UPDATED")
      TS.runTimers()
      assert.same({ "Flask", GC.L["Restock to %d: you hold %d, %d crafts"]:format(10, 5, 5) }, lineTexts(1))
    end)

    it("stops counting auctions read more than 48 hours ago, and says so", function()
      load({ recipes = stocked(), counts = { [905] = 3 } })
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
      GC.CraftQueue.FoldListed("Name-Realm", { { itemKey = { itemID = 905 }, quantity = 2, status = 0 } },
        time() - 48 * 3600 - 60)
      showQueue()
      assert.same({ "Flask", GC.L["Restock to %d: you hold %d, %d crafts"]:format(10, 3, 7),
        GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] }, lineTexts(1))
      assert.equal(7, QV._rows[1].crafts)
    end)

    -- The bar: crafts made of the crafts asked for, gold; a restock's held of its target, blue.
    it("draws how far each line is under it, with the figures at its right", function()
      load({ counts = { [905] = 12, [903] = 4 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
      crafted(3, 2)
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
      GC.CraftQueue.Add("Name-Realm", snapshot(9), 1)
      GC.CraftQueue.FoldListed("Name-Realm", {}, time())
      showQueue()
      local count, restock, fresh = line(1), line(2), line(3)
      assert.equal("2 / 5", count.count:GetText())
      assert.same(K.gold, W.state(count.bar.fill).color)
      assert.is_true(count.bar:GetWidth() > 0)
      assert.equal(math.floor(count.bar:GetWidth() * 0.4 + 0.5), W.state(count.bar.fill).width)
      -- Held above the target reads full, not past it.
      assert.equal("10 / 10", restock.count:GetText())
      assert.same(K.yours, W.state(restock.bar.fill).color)
      assert.equal(restock.bar:GetWidth(), W.state(restock.bar.fill).width)
      assert.equal("0 / 1", fresh.count:GetText())
      assert.is_false(W.state(fresh.bar.fill).shown)
      -- A finished craft moves it.
      crafted(3)
      assert.equal("3 / 5", line(1).count:GetText())
    end)

    it("wraps a long name and what it says in its language, never cuts them, and grows for them", function()
      local long = "Phiole der unerschütterlichen Konzentrationsfähigkeitssteigerungsmeisterschaft"
      local reagent = "Пыльца неувядающей безмятежности серебристолунных садов"
      local r = recipes()
      r[3].info = TS.info(3, long)
      load({ recipes = r, names = { [101] = reagent, [102] = reagent, [103] = reagent } })
      for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
      GC.ActivateLocale("deDE")
      finally(function() GC.ActivateLocale(nil) end)
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      GC.CraftQueue.Add("Name-Realm", snapshot(5), 3)
      local v = showQueue()
      local wide, short = line(1), line(2)
      assert.equal(long, wide.name:GetText())
      for _, fs in ipairs({ wide.name, wide.detail, wide.note, wide.listed, v.cells[1].name, v.cells[1].mail,
        v.cells[1].price, v.cost, v.unpriced, v.none, v.buyNote, v.empty }) do
        assert.is_true(W.state(fs).wordWrap)
        assert.is_true(W.state(fs).nonSpaceWrap)
        assert.is_nil(W.state(fs).maxLines)
      end
      assert.is_true(wide.name:GetStringHeight() > short.name:GetStringHeight())
      assert.is_true(wide.frame:GetHeight() > short.frame:GetHeight())
      -- The reagent's cell grows past its icon and margins (30) for the name.
      assert.is_true(v.cells[1]:GetHeight() > 30)
      -- Craft is as wide as the longest of its words in German, Crafting among them.
      local b = wide.craft
      for _, label in ipairs({ GC.L["Craft %d"]:format(3), GC.L["Crafting"] }) do
        b:SetLabel(label)
        assert.is_true(b:GetWidth() >= b.text:GetUnboundedStringWidth(), label)
      end
    end)

    it("opens its recipe in Blizzard's window on a left click, inside the click", function()
      load()
      GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
      showQueue()
      local frame = line(1).frame
      frame:GetScript("OnClick")(frame, "LeftButton")
      local calls = TS.callsOf("OpenRecipe")
      assert.equal(1, #calls)
      assert.same({ 5 }, calls[1].args)
      assert.equal(0, #TS.timers)
    end)
  end)

  -- Probe A (retail 12.1.5, 2026-10-26): CraftRecipe with a count crafts that many one after another
  -- from the player's own press with the window open; from a timer the client blocks it. A line's
  -- Craft button is that press.
  describe("a line's Craft button", function()
    it("crafts in one press what the reagents allow of what is left, and says when that is fewer", function()
      local r = recipes()
      r[3].craftable = 2
      load({ recipes = r })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      showQueue()
      local l = line(1)
      assert.same({ "Potion", GC.L["%d to craft. Reagents for %d now"]:format(3, 2) }, lineTexts(1))
      assert.equal(GC.L["Craft %d"]:format(2), l.craft.label)
      assert.is_true(l.craft:IsEnabled())
      assert.same(same(K.onGold), rgb(l.craft.text))
      assert.is_true(W.state(l.craft).motionWhileDisabled)

      l.craft:GetScript("OnClick")(l.craft)

      local calls = TS.callsOf("CraftRecipe")
      assert.equal(1, #calls)
      assert.same({ 3, 2, {}, nil, nil, false }, calls[1].args)
    end)

    it("crafts all that is left when the reagents allow more", function()
      local r = recipes()
      r[3].craftable = 9
      load({ recipes = r })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      showQueue()
      assert.equal(GC.L["Craft %d"]:format(3), line(1).craft.label)
      assert.same({ "Potion", GC.L["%d to craft"]:format(3) }, lineTexts(1))
    end)

    it("says on hover what a press does", function()
      local r = recipes()
      r[3].craftable = 9
      load({ recipes = r })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      showQueue()
      local tip, put = tooltip()
      finally(put)
      hover(line(1).craft)
      assert.equal(line(1).craft, tip.owner)
      assert.equal(GC.Util.ClientText(GC.L["Crafts %d now, one after another, with the reagents the profession window would use. Moving stops it."]:format(3)), tip.text)
    end)

    it("is dimmed, with what is left, and says why on hover and under the bar when the reagents do not make one", function()
      load()
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      showQueue()
      local l = line(1)
      local why = GC.L["Not enough reagents for one craft. Missing below says what to get."]
      assert.equal(GC.L["Craft %d"]:format(3), l.craft.label)
      assert.is_false(l.craft:IsEnabled())
      assert.same({ "Potion", GC.L["%d to craft"]:format(3), why }, lineTexts(1))
      assert.same(same(K.warn), rgb(l.note))
      local tip, put = tooltip()
      finally(put)
      hover(l.craft)
      assert.equal(GC.Util.ClientText(why), tip.text)
      l.craft:GetScript("OnClick")(l.craft)
      assert.equal(0, #TS.callsOf("CraftRecipe"))
    end)

    it("is dimmed for a recipe of another skill line, and names it", function()
      local r = recipes()
      r[5].craftable = 4
      r[5].inSkillLine = false
      r[5].professionName = "Midnight Tailoring"
      load({ recipes = r })
      GC.CraftQueue.Add("Name-Realm", snapshot(5), 2)
      showQueue()
      local l = line(1)
      assert.is_false(l.craft:IsEnabled())
      assert.equal(GC.L["Open %s to craft it here."]:format("Midnight Tailoring"), l.craftWhy)
      assert.same({ "Flask", GC.L["%d to craft"]:format(2), GC.L["Open %s to craft it here."]:format("Midnight Tailoring") },
        lineTexts(1))
    end)

    it("draws a line dimmed again in the dim colours, and a live one again live", function()
      local r = recipes()
      load({ recipes = r })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
      showQueue()
      QV.Refresh()
      assert.is_false(line(1).craft:IsEnabled())
      assert.same(same(K.text3), rgb(line(1).craft.text))
      r[3].craftable = 3
      QV.Refresh()
      assert.is_true(line(1).craft:IsEnabled())
      assert.same(same(K.onGold), rgb(line(1).craft.text))
      assert.is_false(line(1).note:IsShown())
    end)

    it("is not there for a restock that holds enough", function()
      local r = recipes()
      r[5].craftable = 4
      load({ recipes = r, counts = { [905] = 3 } })
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 2)
      GC.CraftQueue.FoldListed("Name-Realm", {}, time())
      showQueue()
      assert.equal(0, QV._rows[1].crafts)
      assert.is_false(line(1).craft:IsShown())
    end)
  end)

  -- Blizzard's crafting page and the player's casts (Services/CraftClient.lua's Repeating):
  -- TRADE_SKILL_CRAFT_BEGIN starts each cast of a run, GetRemainingRecasts says how many come after
  -- the first, each finished cast is the player's UNIT_SPELLCAST_SUCCEEDED of the recipe, and
  -- UPDATE_TRADESKILL_CAST_STOPPED ends the run.
  describe("while the client crafts", function()
    local function begin(recipeID, left)
      TS.opts.recasts = left - 1
      fire("TRADE_SKILL_CRAFT_BEGIN", recipeID)
    end

    -- A cast of the player's, as the client fires it (UnitDocumentation.lua's payload).
    local function cast(event, guid, spellID) fire(event, "player", guid, spellID) end

    local function stopped() fire("UPDATE_TRADESKILL_CAST_STOPPED", false) end

    local function queued(r)
      r = r or recipes()
      r[3].craftable, r[5].craftable = 9, 9
      load({ recipes = r })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
      GC.CraftQueue.Add("Name-Realm", snapshot(5), 2)
      return showQueue()
    end

    local function press(i)
      local b = line(i).craft
      b:GetScript("OnClick")(b)
    end

    local function run(n) return GC.L["Crafting %d one after another. Moving stops it."]:format(n) end

    it("shows the line being crafted as Crafting, in gold, with what this run has made and has left", function()
      queued()
      press(1)
      assert.same({ 3, 5, {}, nil, nil, false }, TS.callsOf("CraftRecipe")[1].args)
      cast("UNIT_SPELLCAST_START", "Cast-1", 3)
      begin(3, 5)
      local l = line(1)
      assert.equal(GC.L["Crafting"], l.craft.label)
      assert.is_true(l.craft:IsEnabled())
      assert.same(same(K.goldText), rgb(l.craft.text))
      assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.07 }, vertex(l.frame.fill))
      assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.6 }, vertex(l.frame.ring))
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(0, 5), run(5) }, lineTexts(1))
      assert.same(same(K.text2), rgb(l.note))
      -- One cast made: one off the line, and the run says so before the next cast begins, whatever
      -- the client's count of casts to come says then.
      TS.opts.recasts = 4
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 3)
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(1, 4), run(5) }, lineTexts(1))
      assert.equal("1 / 5", line(1).count:GetText())
      cast("UNIT_SPELLCAST_START", "Cast-2", 3)
      begin(3, 4)
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(1, 4), run(5) }, lineTexts(1))
      -- The run stops (the player moved): the line is live again with what is left.
      stopped()
      l = line(1)
      assert.equal(GC.L["Craft %d"]:format(4), l.craft.label)
      assert.same(same(K.onGold), rgb(l.craft.text))
      assert.same(K.glassTop, vertex(l.frame.fill))
      assert.same({ "Potion", GC.L["%d to craft"]:format(4) }, lineTexts(1))
    end)

    it("is busy from the press on, so a second press before the craft begins calls nothing", function()
      queued()
      -- A double click: both presses before a frame passes.
      press(1)
      press(1)
      assert.equal(1, #TS.callsOf("CraftRecipe"))
      TS.runTimers()
      assert.equal(GC.L["Crafting"], line(1).craft.label)
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(0, 5), run(5) }, lineTexts(1))
      assert.is_false(line(2).craft:IsEnabled())
      press(1)
      press(2)
      assert.equal(1, #TS.callsOf("CraftRecipe"))
    end)

    it("is live again about a second after a press when no craft began", function()
      queued()
      press(1)
      TS.runTimers()
      assert.equal(GC.L["Crafting"], line(1).craft.label)
      TS.now = 0.5
      TS.runTimers()
      assert.equal(GC.L["Crafting"], line(1).craft.label)
      TS.now = 1.5
      TS.runTimers()
      assert.equal(GC.L["Craft %d"]:format(5), line(1).craft.label)
      assert.is_true(line(1).craft:IsEnabled())
      assert.is_true(line(2).craft:IsEnabled())
    end)

    it("stays busy through a cast the client refuses while it crafts", function()
      queued()
      press(1)
      cast("UNIT_SPELLCAST_START", "Cast-1", 3)
      TS.casting = { guid = "Cast-1", spellID = 3 }
      begin(3, 5)
      -- An action refused mid-cast (another key, Blizzard's own Create) fails with its own GUID.
      cast("UNIT_SPELLCAST_FAILED", "Cast-2", 3)
      assert.equal(GC.L["Crafting"], line(1).craft.label)
      assert.is_false(line(2).craft:IsEnabled())
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 3)
      cast("UNIT_SPELLCAST_START", "Cast-3", 3)
      begin(3, 4)
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(1, 4), run(5) }, lineTexts(1))
      assert.equal("1 / 5", line(1).count:GetText())
    end)

    it("shows one craft going as Crafting too, without calling it a run", function()
      queued()
      begin(5, 1)
      assert.equal(GC.L["Crafting"], line(2).craft.label)
      assert.same({ "Flask", GC.L["%d crafted, %d to go"]:format(0, 1) }, lineTexts(2))
    end)

    it("dims every other line's Craft while one is crafting, saying why, and a press of either calls nothing", function()
      queued()
      begin(3, 5)
      local busy, other = line(1), line(2)
      local why = GC.L["Crafting %s now. Wait for it to finish."]:format("Potion")
      assert.is_false(other.craft:IsEnabled())
      assert.equal(GC.L["Craft %d"]:format(2), other.craft.label)
      assert.equal(why, other.craftWhy)
      assert.same({ "Flask", GC.L["%d to craft"]:format(2) }, lineTexts(2))
      local tip, put = tooltip()
      finally(put)
      hover(other.craft)
      assert.equal(GC.Util.ClientText(why), tip.text)
      busy.craft:GetScript("OnClick")(busy.craft)
      other.craft:GetScript("OnClick")(other.craft)
      assert.equal(0, #TS.callsOf("CraftRecipe"))
      stopped()
      assert.is_true(line(2).craft:IsEnabled())
      assert.equal(GC.L["Craft %d"]:format(2), line(2).craft.label)
    end)

    it("dims every line's Craft while a recipe not in the queue is crafting, and names it", function()
      local r = recipes()
      r[11] = { info = TS.info(11, "Bandage") }
      queued(r)
      begin(11, 4)
      local why = GC.L["Crafting %s now. Wait for it to finish."]:format("Bandage")
      for i = 1, 2 do
        assert.is_false(line(i).craft:IsEnabled())
        assert.equal(why, line(i).craftWhy)
      end
      assert.same({ "Potion", GC.L["%d to craft"]:format(5) }, lineTexts(1))
      press(1)
      assert.equal(0, #TS.callsOf("CraftRecipe"))
      stopped()
      assert.is_true(line(1).craft:IsEnabled())
      assert.equal(GC.L["Craft %d"]:format(5), line(1).craft.label)
    end)

    it("counts a run Blizzard's own Create started from its first cast", function()
      queued()
      begin(3, 3)
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(0, 3), run(3) }, lineTexts(1))
    end)

    it("counts a run while the view is away, and forgets one that ended then", function()
      local v = queued()
      local f = P._frame
      local function away()
        f.switch.worth:GetScript("OnClick")(f.switch.worth)
        TS.runTimers()
        assert.is_false(v:IsShown())
      end
      local function back()
        f.switch.queue:GetScript("OnClick")(f.switch.queue)
        TS.runTimers()
      end
      away()
      begin(3, 5)
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 3)
      begin(3, 4)
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-2", 3)
      back()
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(2, 3), run(5) }, lineTexts(1))
      assert.equal("2 / 5", line(1).count:GetText())
      away()
      stopped()
      begin(3, 2)
      back()
      assert.same({ "Potion", GC.L["%d crafted, %d to go"]:format(0, 2), run(2) }, lineTexts(1))
    end)

    it("repaints as a run begins and ends", function()
      queued()
      local ev = QV._events
      for _, event in ipairs({ "TRADE_SKILL_CRAFT_BEGIN", "UPDATE_TRADESKILL_CAST_STOPPED", "TRADE_SKILL_CLOSE",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
        assert.is_true(ev:IsEventRegistered(event), event)
      end
      assert.same({ "player" }, W.state(ev).unitEvents.UNIT_SPELLCAST_INTERRUPTED)
      assert.same({ "player" }, W.state(ev).unitEvents.UNIT_SPELLCAST_FAILED)
      cast("UNIT_SPELLCAST_START", "Cast-1", 3)
      begin(3, 5)
      cast("UNIT_SPELLCAST_INTERRUPTED", "Cast-1", 3)
      assert.equal(GC.L["Craft %d"]:format(5), line(1).craft.label)
      -- A scrap's stop is not a craft's.
      begin(3, 5)
      fire("UPDATE_TRADESKILL_CAST_STOPPED", true)
      assert.equal(GC.L["Crafting"], line(1).craft.label)
    end)
  end)

  describe("Missing", function()
    it("says the queue is empty, with no Missing under it", function()
      load()
      local v = showQueue()
      assert.equal(0, #QV._rows)
      assert.is_true(v.empty:IsShown())
      assert.equal(GC.L["The queue is empty. Add a recipe from This recipe."], v.empty:GetText())
      assert.is_false(v.missing:IsShown())
    end)

    it("shows a cell for what is short, summed across recipes, with its icon and what it costs", function()
      load({ counts = { [101] = 4, [103] = 1 }, icons = { [101] = 1101, [102] = 1102, [103] = 1103 },
        tiers = { [101] = 1, [102] = 2, [103] = 3 } })
      VALUES[101], VALUES[102], VALUES[103] = commodity(500), commodity(450), commodity(400)
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
      GC.CraftQueue.Add("Name-Realm", snapshot(5), 3)
      local v = showQueue()
      assert.equal(GC.Util.Upper(GC.L["Missing"]), v.heading:GetText())
      assert.same(same(K.warn), rgb(v.heading))
      -- 7 of Item A in all, 5 held: 2 to buy, at 400 each (the cheapest quality BUY buys).
      assert.same({ { name = "Item A", count = "2", price = GC.L["about %s"]:format(GC.Util.Money(800)) } }, cellsOf(v))
      -- The cell draws the quality BUY buys, with its pip.
      assert.equal(1103, W.state(v.cells[1].slot.icon).file)
      assert.is_true(v.cells[1].slot.pip:IsShown())
      assert.equal("Professions-Icon-Quality-Tier3-Small", W.state(v.cells[1].slot.pip).atlas)
      assert.equal(GC.L["about %s to buy"]:format(GC.Util.Colored(K.goldText, GC.Util.Money(800))), v.cost:GetText())
      assert.is_true(v.cost:IsShown())
      assert.is_false(v.unpriced:IsShown())
      assert.is_false(v.none:IsShown())
      assert.equal(v.content, v.missing:GetParent())
    end)

    it("totals what has a price and counts what has none, one and many", function()
      load({ filtered = { 9 } })
      VALUES[101] = commodity(400)
      GC.CraftQueue.Add("Name-Realm", snapshot(9), 2)
      local v = showQueue()
      assert.same({ { name = "Item A", count = "2", price = GC.L["about %s"]:format(GC.Util.Money(800)) },
        { name = "Item B", count = "2" } }, cellsOf(v))
      assert.equal(GC.L["about %s to buy"]:format(GC.Util.Colored(K.goldText, GC.Util.Money(800))), v.cost:GetText())
      assert.is_true(v.unpriced:IsShown())
      assert.equal(GC.L["1 has no price yet"], v.unpriced:GetText())
      -- Nothing priced: no total, only how many have no price.
      VALUES[101] = nil
      QV.Refresh()
      assert.is_false(v.cost:IsShown())
      assert.equal(GC.L["%d have no price yet"]:format(2), v.unpriced:GetText())
    end)

    it("shows a reagent to buy and the same reagent waiting in the mailbox in one cell", function()
      load({ counts = {} })
      VALUES[101], VALUES[102], VALUES[103] = commodity(400), commodity(450), commodity(500)
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
      local box = Mailbox.new({
        { sender = "Friend", subject = "Mats", canReply = true,
          items = { [1] = { itemID = 101, count = 4 }, [2] = { itemID = 102, count = 3 } } },
      })
      readMailbox(box, true)
      mailClosed()
      local v = showQueue()
      -- 10 needed: 7 in the mailbox, 3 to buy at 400. The icon counts all ten the bags still need.
      assert.same({ { name = "Item A", count = "10", mail = GC.L["%d in your mailbox"]:format(7),
        price = GC.L["about %s"]:format(GC.Util.Money(1200)) } }, cellsOf(v))
      local cell = v.cells[1]
      assert.same(same(K.yours), rgb(cell.mail))
      assert.is_true(cell.mailIcon:IsShown())
      assert.same(same(K.text3), rgb(cell.price))
    end)

    it("draws a reagent that waits only in the mailbox as the item there, with its pip", function()
      load({ counts = {}, icons = { [101] = 1101, [102] = 1102 }, tiers = { [101] = 1, [102] = 2 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
      local box = Mailbox.new({
        { sender = "Friend", subject = "Mats", canReply = true, items = { [1] = { itemID = 102, count = 10 } } },
      })
      readMailbox(box, true)
      mailClosed()
      local v = showQueue()
      assert.same({ { name = "Item A", count = "10", mail = GC.L["%d in your mailbox"]:format(10) } }, cellsOf(v))
      assert.equal(1102, W.state(v.cells[1].slot.icon).file)
      assert.equal("Professions-Icon-Quality-Tier2-Small", W.state(v.cells[1].slot.pip).atlas)
      assert.is_true(v.cells[1].slot.pip:IsShown())
    end)

    -- The Tonic's Item A (three qualities) and Item B, then the Elixir's Item A of one quality: a
    -- reagent is one need only for slots that take the same qualities (Core/CraftQueue.lua's Needs).
    it("puts the cells two to a row, as tall as each other", function()
      load({ filtered = { 7, 9 }, counts = {} })
      GC.CraftQueue.Add("Name-Realm", snapshot(9), 1)
      GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
      local v = showQueue()
      assert.same({ "Item A", "Item B", "Item A" }, { cellsOf(v)[1].name, cellsOf(v)[2].name, cellsOf(v)[3].name })
      local first, second, third = v.cells[1], v.cells[2], v.cells[3]
      local _, _, _, x1, y1 = first:GetPoint(1)
      local _, _, _, x2, y2 = second:GetPoint(1)
      local _, _, _, x3, y3 = third:GetPoint(1)
      assert.equal(y1, y2)
      assert.is_true(x2 >= x1 + first:GetWidth())
      assert.equal(first:GetHeight(), second:GetHeight())
      assert.equal(x1, x3)
      assert.is_true(-y3 >= -y1 + first:GetHeight())
    end)

    it("leaves a currency off the BUY list and says it is not on the auction house", function()
      load({ filtered = { 7 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
      local v = showQueue()
      assert.same({ { name = "Item A", count = "1" } }, cellsOf(v))
      assert.same({ GC.L["%s is not sold on the auction house"]:format("Valorstones") }, currenciesOf(v))
      local run = QV.MakeBuyList()
      assert.same({ { 101, 1 } }, { { run.lines[1].i, run.lines[1].q } })
      assert.equal(1, #run.lines)
    end)

    it("names a currency only when the player holds too little of it, and can say nothing is missing", function()
      load({ filtered = { 7 }, counts = { [101] = 1 }, currencyHeld = { [3008] = 2 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
      local v = showQueue()
      assert.same({}, cellsOf(v))
      assert.same({}, currenciesOf(v))
      assert.is_true(v.none:IsShown())
      assert.equal(GC.L["Nothing is missing for the queue"], v.none:GetText())
      restore()
      load({ filtered = { 7 }, counts = { [101] = 1 }, currencyHeld = { [3008] = 1 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
      v = showQueue()
      assert.same({ GC.L["%s is not sold on the auction house"]:format("Valorstones") }, currenciesOf(v))
      assert.is_false(v.none:IsShown())
    end)

    it("disables Make a BUY list when nothing is missing, and says what the list does", function()
      load({ counts = { [101] = 10 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
      local v = showQueue()
      assert.same({}, cellsOf(v))
      assert.is_true(v.none:IsShown())
      assert.equal(GC.L["Nothing is missing for the queue"], v.none:GetText())
      assert.is_false(v.cost:IsShown())
      assert.equal(GC.L["Make a BUY list"], v.buy.label)
      assert.is_false(v.buy:IsEnabled())
      assert.is_nil(QV.MakeBuyList())
      assert.equal(GC.L["The BUY tab at the auction house buys what is missing, and the list follows the queue."],
        v.buyNote:GetText())
      assert.equal(v.missing, v.buy:GetParent())
    end)

    it("a bag change repaints what is missing", function()
      load({ counts = { [101] = 1 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
      local v = showQueue()
      assert.same({ { name = "Item A", count = "3" } }, cellsOf(v))
      TS.opts.counts[101] = 4
      local ev = P._events
      ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
      TS.runTimers()
      assert.same({}, cellsOf(v))
      assert.is_true(v.none:IsShown())
    end)

    it("scrolls the lines and Missing together, Missing under the last line", function()
      load({ counts = {} })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
      GC.CraftQueue.Add("Name-Realm", snapshot(5), 2)
      local v = showQueue()
      local _, _, _, _, y = v.missing:GetPoint(1)
      local _, _, _, _, last = line(2).frame:GetPoint(1)
      assert.is_true(-y >= -last + line(2).frame:GetHeight())
      assert.equal(-y + v.missing:GetHeight(), v.content:GetHeight())
      assert.equal(v.content, v.scroll:GetScrollChild())
    end)
  end)

  -- The GoldCap Hoard's For your crafts tile reads the queue the way this view does: what each
  -- entry has left to craft (a restock by what it holds) and what that needs in all. It counts the
  -- bags alone against it itself.
  it("answers what the queue needs in all and how many crafts are left, as the view counts them", function()
    load({ counts = { [905] = 4 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    GC.CraftQueue.Restock("Name-Realm", snapshot(5), 10)
    local needs, crafts = QV.Needs("Name-Realm")
    -- 2 Potions at two of Item A, 6 Flasks at one: one reagent in three qualities.
    assert.equal(8, crafts)
    assert.same({ { ids = { 101, 102, 103 }, q = 10 } }, needs)
    assert.same({}, (QV.Needs("Other-Realm")))
    assert.equal(0, select(2, QV.Needs("Other-Realm")))
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
    assert.equal("Flask", line(2).name:GetText())
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

  -- Four of Item A held, five Potions (ten) queued, the list made, six bought at the auction
  -- house. Retail delivers a purchase by mail, so the bags still hold the four.
  local function boughtIntoMailbox()
    load({ counts = { [101] = 4 } })
    visitedMailbox()
    VALUES[101], VALUES[102], VALUES[103] = commodity(400), commodity(450), commodity(500)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    assert.same({ { 101, 10 } }, linesOf(run))
    assert.equal(6, buyRun(run)[101])
    purchase(run, 101, 6)
    return run
  end

  -- The money bug: BUY subtracted only the bags and the banks, or what the list bought, whichever
  -- was more, so it offered 4 again right after this purchase, and 4 again once two Potions used
  -- the four held, until the mail was taken.
  it("lets BUY buy nothing that waits in the mailbox, before and after a craft used what was held", function()
    local run = boughtIntoMailbox()
    assert.equal(0, buyRun(run)[101])
    TS.opts.counts[101] = 0
    crafted(3, 2)
    assert.same({ { 101, 6 } }, linesOf(run))
    assert.equal(0, buyRun(run)[101])
    -- The queue says the same: nothing to buy, and Make a BUY list has nothing to add. What waits
    -- in the mailbox has its cell under Missing, since a craft takes reagents from the bags, and the
    -- line over the cells says to take it, never that nothing is missing.
    local v = showQueue()
    assert.same({ { name = "Item A", count = "6", mail = GC.L["%d in your mailbox"]:format(6) } }, cellsOf(v))
    assert.equal(GC.L["Nothing to buy. Take what waits in your mailbox before you craft."], v.none:GetText())
    assert.is_false(v.buy:IsEnabled())
    -- The line's Craft is dimmed for it, and says the mailbox is why.
    local why = GC.L["Some reagents wait in your mailbox. Take them out before you craft."]
    assert.equal(why, line(1).craftWhy)
    assert.equal(why, line(1).note:GetText())
  end)

  -- Something to buy as well: Missing says what to get, as before.
  it("keeps saying Missing has what to get when a reagent is to buy as well as in the mailbox", function()
    load({ counts = {} })
    visitedMailbox()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local box = Mailbox.new({
      { sender = "Friend", subject = "Mats", canReply = true, items = { [1] = { itemID = 101, count = 4 } } },
    })
    readMailbox(box, true)
    mailClosed()
    showQueue()
    assert.equal(GC.L["Not enough reagents for one craft. Missing below says what to get."], line(1).craftWhy)
  end)

  -- A reagent the client has not loaded yet has no name: the cell asks for it and is drawn again
  -- when it comes (GET_ITEM_INFO_RECEIVED), never left as "Item 111".
  it("names a reagent once the client has loaded it", function()
    load({ filtered = { 9 }, names = { [101] = "Item A", [102] = "Item A", [103] = "Item A" } })
    GC.CraftQueue.Add("Name-Realm", snapshot(9), 1)
    local v = showQueue()
    assert.equal(GC.L["Item %d"]:format(111), cellsOf(v)[2].name)
    local asked = TS.callsOf("RequestLoadItemDataByID")
    assert.equal(111, asked[#asked].args[1])
    assert.is_true(QV._events:IsEventRegistered("GET_ITEM_INFO_RECEIVED"))
    -- A load that failed changes nothing: no repaint, no new request.
    local before = #asked
    TS.opts.names[111] = "Item B"
    fire("GET_ITEM_INFO_RECEIVED", 111, false)
    assert.equal(GC.L["Item %d"]:format(111), cellsOf(v)[2].name)
    assert.equal(before, #TS.callsOf("RequestLoadItemDataByID"))
    fire("GET_ITEM_INFO_RECEIVED", 111, true)
    assert.equal("Item B", cellsOf(v)[2].name)
    -- Every cell named: the view stops listening for item loads.
    assert.is_false(QV._events:IsEventRegistered("GET_ITEM_INFO_RECEIVED"))
  end)

  -- Item loads fire for every item the game loads: the view listens only while a cell waits.
  it("listens for item loads only while a cell waits for its item's name", function()
    load({ filtered = { 3, 9 } })
    assert.is_false(QV._events:IsEventRegistered("GET_ITEM_INFO_RECEIVED"))
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    showQueue()
    assert.is_false(QV._events:IsEventRegistered("GET_ITEM_INFO_RECEIVED"))
    -- The Tonic's Item B has no name yet; the queue emptied, nothing waits any more.
    TS.opts.names[111] = nil
    GC.CraftQueue.Add("Name-Realm", snapshot(9), 1)
    QV.Refresh()
    assert.is_true(QV._events:IsEventRegistered("GET_ITEM_INFO_RECEIVED"))
    GC.CraftQueue.Remove("Name-Realm", 3)
    GC.CraftQueue.Remove("Name-Realm", 9)
    QV.Refresh()
    assert.is_false(QV._events:IsEventRegistered("GET_ITEM_INFO_RECEIVED"))
  end)

  -- Under Missing, only what the bags and the banks do not cover.
  it("shows under Missing what the queue needs from the mailbox, no more", function()
    boughtIntoMailbox()
    local v = showQueue()
    assert.same({ { name = "Item A", count = "6", mail = GC.L["%d in your mailbox"]:format(6) } }, cellsOf(v))
    TS.opts.counts[101] = 8
    QV.Refresh()
    assert.same({ { name = "Item A", count = "2", mail = GC.L["%d in your mailbox"]:format(2) } }, cellsOf(v))
    TS.opts.counts[101] = 10
    QV.Refresh()
    assert.same({}, cellsOf(v))
  end)

  -- I1 at the queue: a mailbox opened soon after the purchase can list what the client held before
  -- it; the purchase still counts, and BUY offers nothing.
  it("lets BUY buy nothing again when the mailbox shows a list from before the purchase", function()
    local run = boughtIntoMailbox()
    readMailbox(Mailbox.new({ { sender = "Friend", subject = "Hi", canReply = true } }), true)
    mailClosed()
    assert.equal(0, buyRun(run)[101])
    assert.same({ { 101, 10 } }, linesOf(run))
  end)

  it("counts the mail once, when the mailbox shows it and after it is taken", function()
    local run = boughtIntoMailbox()
    TS.opts.counts[101] = 0
    crafted(3, 2)
    local box = Mailbox.new({ wonMail(101, 6) })
    readMailbox(box, true)
    assert.equal(0, buyRun(run)[101])
    -- The last mail taken: the empty inbox counts when the visit ends on it.
    takeFirst(box, 101, 6)
    mailClosed()
    local offer, r = buyRun(run)
    assert.equal(0, offer[101])
    assert.equal(6, r:Lines()[1].have)
    -- One more Potion queued: two more to buy, not none.
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 1)
    P.OnQueueChanged()
    assert.same({ { 101, 8 } }, linesOf(run))
    assert.equal(2, buyRun(run)[101])
  end)

  it("keeps a purchase in the mailbox counted across a relog before the mailbox is opened", function()
    local run = boughtIntoMailbox()
    local saved = GC.db
    load({ counts = { [101] = 4 } })
    GC.db = saved
    run = GC.AppRuns.Get(run.code)
    assert.equal(0, buyRun(run)[101])
    TS.opts.counts[101] = 0
    crafted(3, 2)
    assert.equal(0, buyRun(run)[101])
  end)

  -- A vendor's purchase lands in the bags and never reaches Core/MailStock.lua: what BUY offers
  -- after it is what it always was.
  it("counts a purchase that lands in the bags once, as before", function()
    load({ counts = { [101] = 4 } })
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    local _, r = buyRun(run)
    r:RecordPurchase(101, 6, 2400, 1)
    TS.opts.counts[101] = 10
    assert.equal(0, buyRun(run)[101])
    TS.opts.counts[101] = 6
    crafted(3, 2)
    assert.same({ { 101, 6 } }, linesOf(run))
    assert.equal(0, buyRun(run)[101])
    TS.opts.counts[101] = 2
    crafted(3, 2)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    P.OnQueueChanged()
    assert.same({ { 101, 6 } }, linesOf(run))
    assert.equal(4, buyRun(run)[101])
  end)

  -- Mail from another player is the player's own once the mailbox has shown it, in any quality: the
  -- list's line is the need less the other qualities held, and BUY subtracts the line's own.
  it("counts another player's mail of a reagent as held once the mailbox has shown it", function()
    load({ counts = {} })
    VALUES[101], VALUES[102], VALUES[103] = commodity(400), commodity(450), commodity(500)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    assert.equal(10, buyRun(run)[101])
    local box = Mailbox.new({
      { sender = "Friend", subject = "Mats", canReply = true,
        items = { [1] = { itemID = 101, count = 4 }, [2] = { itemID = 102, count = 3 } } },
      { sender = "Stranger", subject = "Pay me", canReply = true, cod = 5000, items = { [1] = { itemID = 101, count = 9 } } },
    })
    readMailbox(box, true)
    mailClosed()
    assert.same({ { 101, 7 } }, linesOf(run))
    assert.equal(3, buyRun(run)[101])
    local v = showQueue()
    assert.same({ { name = "Item A", count = "10", mail = GC.L["%d in your mailbox"]:format(7),
      price = GC.L["about %s"]:format(GC.Util.Money(1200)) } }, cellsOf(v))
  end)

  -- M1: a take can reach the bags before the read of the inbox that sees it gone. Counted then, the
  -- three would count twice and shrink the list for a moment; the list waits for the close.
  it("leaves the list alone while the mailbox is open, and counts once at the close", function()
    load({ counts = {} })
    visitedMailbox()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    local box = Mailbox.new({ { sender = "Friend", subject = "Mats", canReply = true,
      items = { [1] = { itemID = 102, count = 3 } } } })
    readMailbox(box, true)
    mailClosed()
    assert.same({ { 101, 7 } }, linesOf(run))
    readMailbox(box, true)
    box.api.TakeInboxItem(1, 1)
    box:advance()
    TS.opts.counts[102] = 3
    bagsChanged()
    assert.same({ { 101, 7 } }, linesOf(run))
    readMailbox(box)
    mailClosed()
    assert.same({ { 101, 7 } }, linesOf(run))
    assert.equal(7, buyRun(run)[101])
  end)

  -- Walking from the mailbox straight to an auctioneer can shut it with no MAIL_CLOSED: the client
  -- says so, and the bags count again.
  it("counts the bags again when the client says the mailbox shut with no MAIL_CLOSED", function()
    load({ counts = {} })
    visitedMailbox()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    readMailbox(Mailbox.new({ { sender = "Friend", subject = "Hi", canReply = true } }), true)
    local interacting = true
    _G.Enum.PlayerInteractionType = { MailInfo = 17 }
    _G.C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(kind) return kind == 17 and interacting end }
    TS.opts.counts[102] = 4
    bagsChanged()
    assert.same({ { 101, 10 } }, linesOf(run))
    interacting = false
    bagsChanged()
    _G.C_PlayerInteractionManager = nil
    assert.same({ { 101, 6 } }, linesOf(run))
  end)

  it("counts a crafted item waiting in the mailbox toward its restock", function()
    load({ counts = {} })
    GC.CraftQueue.Restock("Name-Realm", snapshot(3), 5)
    local run = QV.MakeBuyList()
    assert.same({ { 101, 10 } }, linesOf(run))
    local box = Mailbox.new({ { sender = "Auction House", subject = "Auction expired: Potion", auction = true,
      items = { [1] = { itemID = 903, count = 2 } } } })
    readMailbox(box, true)
    mailClosed()
    assert.same({ { 101, 6 } }, linesOf(run))
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
    -- It reads as an empty queue: no Missing, so no Make a BUY list.
    assert.is_true(v.empty:IsShown())
    assert.is_false(v.missing:IsShown())
    assert.is_nil(QV.MakeBuyList())
    crafted(3)
    local ev = QV._events
    ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
    P.OnQueueChanged()
    TS.runTimers()
    assert.same(craft, GC.db.craft)
    assert.same(runs, GC.db.runs)
  end)

  it("puts a reagent a vendor sells on the BUY list as a vendor stop, and prices it at the vendor's price", function()
    load({ counts = { [101] = 1 } })
    -- A list the player holds says a vendor sells Item A for 50 (Core/AppRuns.lua's VendorUnitFor).
    GC.db.runs = { vendor = { code = "vendor", updatedAt = 1, lines = { { i = 101, q = 1, v = true, vu = 50 } } } }
    VALUES[101] = commodity(400)
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 2)
    local v = showQueue()
    assert.same({ { name = "Item A", count = "3", price = GC.L["about %s"]:format(GC.Util.Money(150)) } }, cellsOf(v))
    local run = QV.MakeBuyList()
    assert.equal(1, #run.lines)
    assert.same({ 101, 4, true, 50 }, { run.lines[1].i, run.lines[1].q, run.lines[1].v, run.lines[1].vu })
  end)

  it("a finished craft takes one off its line", function()
    load()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    showQueue()
    local ev = QV._events
    assert.is_true(ev:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED"))
    ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1234-5678-9-3-ABCDEF", 3)
    TS.runTimers()
    assert.equal(GC.L["%d to craft"]:format(2), line(1).detail:GetText())
    ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1234-5678-9-133-ABCDEF", 133)
    TS.runTimers()
    assert.equal(GC.L["%d to craft"]:format(2), line(1).detail:GetText())
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
    local entries = lineMenu(1)
    local texts = {}
    for _, e in ipairs(entries) do texts[#texts + 1] = e.text end
    assert.same({ GC.Util.ClientText(GC.L["Add to queue"]), GC.Util.ClientText(GC.L["Restock to"]),
      GC.Util.ClientText(GC.L["Remove from queue"]) }, texts)
    entries[3].fn()
    TS.runTimers()
    assert.equal(1, #QV._rows)
    assert.equal("Flask", line(1).name:GetText())
  end)

  -- The panel's top counts the queue's lines and says how the queue holds the open recipe
  -- (UI/CraftPanel.lua's QueueOpen).
  it("redraws the panel's top after it changes the queue or what a restock holds", function()
    load()
    GC.CraftQueue.Add("Name-Realm", snapshot(3), 3)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 1)
    showQueue()
    local f = P._frame
    assert.equal("2", f.switch.badge.text:GetText())
    local asked = 0
    local real = P.QueueOpen
    P.QueueOpen = function(...)
      asked = asked + 1
      return real(...)
    end
    lineMenu(2)[3].fn()
    TS.runTimers()
    assert.equal(1, asked)
    assert.equal("1", f.switch.badge.text:GetText())
    local ev = QV._events
    for _, event in ipairs({ "OWNED_AUCTIONS_UPDATED", "MAIL_CLOSED" }) do
      asked = 0
      ev:GetScript("OnEvent")(ev, event)
      TS.runTimers()
      assert.equal(1, asked, event)
    end
    asked = 0
    crafted(3)
    assert.equal(1, asked)
    assert.equal(GC.L["In queue: %d"]:format(2), f.card.queued.text:GetText())
  end)

  it("repaints when the panel adds to the queue", function()
    load()
    showQueue()
    assert.equal(QV.OnQueueChanged, P.OnQueueChanged)
    GC.CraftQueue.Add("Name-Realm", snapshot(5), 2)
    P.OnQueueChanged()
    assert.equal(1, #QV._rows)
  end)

  describe("coming back", function()
    -- docs/addon/AGENTS.md "Text": a one-line label whose frame or a parent was hidden and shown
    -- again can come back blank, and SetText with the text it holds does not redraw it. The cure
    -- is clear, set, hide, show, on every re-show.
    local function watch(logs, fs)
      local log = {}
      local set, hide, showIt = fs.SetText, fs.Hide, fs.Show
      fs.SetText = function(self, text, ...)
        log[#log + 1] = "set " .. tostring(text)
        return set(self, text, ...)
      end
      fs.Hide = function(self) log[#log + 1] = "hide"; return hide(self) end
      fs.Show = function(self) log[#log + 1] = "show"; return showIt(self) end
      logs[fs] = log
    end

    local function restamped(logs, fs)
      local log, n = logs[fs], #logs[fs]
      return n >= 4 and log[n - 3] == "set " and log[n - 2] == "set " .. tostring(fs:GetText()) and log[n - 1] == "hide"
        and log[n] == "show"
    end

    local function watchAll(logs, owners)
      for _, owner in ipairs(owners) do
        for _, fs in ipairs(owner.texts or {}) do watch(logs, fs) end
      end
    end

    it("redraws every line it shows when it shows again", function()
      load({ counts = {}, filtered = { 7 } })
      VALUES[101] = commodity(400)
      GC.CraftQueue.Restock("Name-Realm", snapshot(5), 4)
      GC.CraftQueue.Add("Name-Realm", snapshot(7), 1)
      local v = showQueue()
      local logs = {}
      local owners = { v }
      for _, l in ipairs(v.lines) do owners[#owners + 1] = l end
      for _, cell in ipairs(v.cells) do owners[#owners + 1] = cell end
      watchAll(logs, owners)
      local first, cell = line(1), v.cells[1]
      for _, fs in ipairs({ v.heading, v.cost, v.buy.text, v.buyNote, v.currencies[1], first.name, first.detail,
        first.craft.text, first.count, first.note, first.listed, cell.name, cell.slot.count, cell.price }) do
        assert.is_truthy(logs[fs])
      end
      v:GetScript("OnShow")(v)
      local checked = 0
      for fs in pairs(logs) do
        if fs:IsShown() and fs:GetText() ~= nil then
          assert.is_true(restamped(logs, fs), tostring(fs:GetText()))
          checked = checked + 1
        end
      end
      assert.is_true(checked >= 14)
    end)

    it("redraws a line and a cell a shorter queue hid, when a longer one shows them again", function()
      load({ counts = {}, filtered = { 9 } })
      GC.CraftQueue.Add("Name-Realm", snapshot(3), 1)
      GC.CraftQueue.Add("Name-Realm", snapshot(9), 1)
      local v = showQueue()
      local l, cell = v.lines[2], v.cells[2]
      GC.CraftQueue.Remove("Name-Realm", 9)
      QV.Refresh()
      assert.is_false(l.frame:IsShown())
      assert.is_false(cell:IsShown())
      local logs = {}
      watch(logs, l.name)
      watch(logs, cell.name)
      GC.CraftQueue.Add("Name-Realm", snapshot(9), 1)
      QV.Refresh()
      assert.is_true(restamped(logs, l.name))
      assert.is_true(restamped(logs, cell.name))
    end)
  end)

  it("registers its events through pcall", function()
    local file = assert(io.open("GoldCap/UI/CraftQueueView.lua", "r"))
    local src = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    assert.is_nil(src:find(":RegisterEvent%("))
    assert.is_nil(src:find(":RegisterUnitEvent%("))
    assert.is_truthy(src:find('pcall%(events%.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player"%)'))
    assert.is_nil(src:find("hooksecurefunc", 1, true))
  end)

  -- The craft is the player's press and nothing else's: one CraftRecipe in the file, inside the
  -- Craft button's own OnClick (probe A4: from a timer the client blocks it), the first thing it
  -- calls, the button never disabled before it.
  it("crafts only inside the Craft button's click", function()
    local file = assert(io.open("GoldCap/UI/CraftQueueView.lua", "r"))
    local src = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    local _, count = src:gsub("CraftRecipe", "")
    assert.equal(1, count)
    local from = assert(src:find('line.craft:SetScript("OnClick", function()', 1, true))
    local to = assert(src:find("\n  end)", from, true))
    local body = src:sub(from, to)
    local call = assert(body:find("C_TradeSkillUI.CraftRecipe(", 1, true))
    assert.is_nil(body:sub(1, call):find("Disable", 1, true))
    assert.is_nil(body:sub(1, call):find("SetText", 1, true))
  end)
end)
