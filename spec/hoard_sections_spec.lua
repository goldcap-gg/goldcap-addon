local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The GoldCap Hoard's later parts (UI/HoardTiles.lua, UI/HoardCarry.lua, UI/HoardFooter.lua): the
-- tiles pinned under the switch (Prices are up, For your crafts, Put away), the carry cards in the
-- scroll under the groups, and the footer pinned at the window's foot (Make room, Put back and
-- where the prices come from). The real Theme and kit, the real window (UI/HoardFrame.lua and its
-- rows and list), the real model (Core/Hoard.lua, Core/BankGroups.lua, Core/GroupRules.lua from a
-- Companion file), the real press machine (Core/VendorPress.lua), the real bank route
-- (UI/BankRoute.lua) and the real carry plan (Core/SellRoute.lua); the bags, both banks, the bank
-- window, the tooltip and the client calls are faked, shaped as the client's. The craft queue's
-- needs are UI/CraftQueueView.lua's Needs, faked here (spec/craft_queue_view_spec.lua has its own).
describe("GoldCap Hoard sections", function()
  local GC, HF, restore, saved, bags, sizes, used, timers, canUse, tabs, reads, showing, usable, charTabs
  local refused, refusedHere, landing, arrivals, tip, needs, crafts, now, origin, warbound
  -- Enum.BankType (Blizzard_APIDocumentationGenerated's ItemConstantsDocumentation.lua).
  local CHARACTER, ACCOUNT = 0, 2
  local G = 10000
  local KEYS = { "Enum", "UIParent", "BankFrame", "BankPanel", "MerchantFrame", "ItemLocation", "C_Container",
    "C_Item", "C_Bank", "C_Timer", "hooksecurefunc", "GoldCap_AppRuns", "SpellIsTargeting", "GetCursorInfo", "BANK",
    "ACCOUNT_BANK_PANEL_TITLE", "CreateColor", "GameTooltip", "GetRealmName", "time" }

  -- Herbs: Bloom (two qualities, 1 and 2) and Mycobloom (6); Ore: Bismuth (3); Cloth: Weavercloth
  -- (4). The usual prices (u): Bloom 1 sells under its usual price, Bloom 2 at 120% of it,
  -- Weavercloth at twice it, Mycobloom at 111%, Bismuth at it: Bloom 2, Weavercloth and Mycobloom
  -- are up. Linen (9) is in no group; Resilient Leather (7, 8: two qualities) is the craft queue's.
  local FILE = {
    v = 3, generatedAt = 1, runs = {}, groups = { "G" },
    caps = {
      { i = 1, c = 700, u = 60000, r = 1, k = true }, { i = 2, c = 700, u = 50000, r = 1, k = true },
      { i = 6, c = 700, u = 9000, r = 1, k = true }, { i = 3, c = 700, u = 20000, r = 2, k = true },
      { i = 4, c = 700, u = 5000, r = 3, k = true },
    },
    rules = { { n = "Herbs", p = "gather", d = 24, fp = 80 }, { n = "Ore", p = "gather", d = 24, fp = 80 },
      { n = "Cloth", p = "craft", d = 24, fp = 80 } },
  }
  local NAMES = { [1] = "Bloom", [2] = "Bloom", [3] = "Bismuth", [4] = "Weavercloth", [6] = "Mycobloom", [7] = "Resilient Leather",
    [8] = "Resilient Leather", [9] = "Linen Cloth", [100] = "Gem-Inlaid Velvet Cinch", [200] = "Recipe: Ornate Plate" }
  local VALUE = { [1] = 50000, [2] = 60000, [3] = 20000, [4] = 10000, [6] = 10000 }

  local function info(itemID, count, over)
    local i = { itemID = itemID, itemName = NAMES[itemID], stackCount = count, iconFileID = 5000 + itemID,
      hyperlink = "item:" .. itemID, isBound = false, isLocked = false }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  local function textOf(fs) return W.state(fs).text end
  local function plainOf(fs) return helper.plain(textOf(fs) or "") end
  local function shown(widget) return widget ~= nil and widget:IsShown() end
  local function press(button) W.state(button).scripts.OnClick(button) end
  local function hover(button) W.state(button).scripts.OnEnter(button) end
  local function at(widget) return W.state(widget).points[1] end
  local function alpha(widget) return widget:GetAlpha() end

  local function open() GC.BankRoute.OnBankOpened() end
  local function close() GC.BankRoute.OnBankClosed() end
  local function nextFrame()
    for i = #timers, 1, -1 do
      if timers[i].seconds == 0 then table.remove(timers, i).fn() end
    end
  end
  -- BAG_UPDATE_DELAYED, and the frame after it, where the window paints.
  local function bagsChanged()
    GC.BankRoute.OnBagsChanged()
    nextFrame()
  end
  local function switchTo(bankType)
    showing = bankType
    _G.BankPanel:Reset()
    nextFrame()
  end

  -- The server's answer to the moves sent so far (with `landing`): each slot empties and its stack
  -- lands at the end of the bags, the character's bank tab or the Warband Bank's.
  local function land()
    for _, a in ipairs(arrivals) do
      bags[a.bag][a.slot] = false
      bags[a.into][#bags[a.into] + 1] = a.stack
    end
    arrivals = {}
  end
  -- The press machine's timers until none is left, the server answering before each, then the
  -- bags' event; answers how many ran.
  local function ticks()
    local n = 0
    while true do
      local due
      for k, t in ipairs(timers) do
        if t.seconds == GC.VendorPress.STEP then due = k break end
      end
      if not due then break end
      land()
      table.remove(timers, due).fn()
      n = n + 1
    end
    bagsChanged()
    return n
  end

  -- The settle timers armed so far (the route's SETTLE_SECONDS): what is still on its way is given
  -- up, and the window paints on the frame after.
  local function settle()
    for i = #timers, 1, -1 do
      if timers[i].seconds == GC.BankRoute.SETTLE_SECONDS then table.remove(timers, i).fn() end
    end
    nextFrame()
  end
  -- The player types into the search box: the client changes its text and runs OnTextChanged with
  -- userInput true.
  local function typeInto(box, text)
    W.state(box).text = text
    W.state(box).scripts.OnTextChanged(box, true)
  end
  -- Which kit glyph a texture draws: its name in the atlas, from its coordinates.
  local function glyph(texture)
    local coords = W.state(texture).texCoord
    for name in pairs(GC.Kit.Icons.index) do
      if coords and coords[1] == GC.Theme.IconCoords(name) and select(3, GC.Theme.IconCoords(name)) == coords[3] then
        return name
      end
    end
  end

  -- What the moves made: { bag, slot, "in" with the bank | "out" }, in order.
  local function moves()
    local out = {}
    for _, u in ipairs(used) do
      out[#out + 1] = u.n == 5 and { u[1], u[2], u[4] } or { u[1], u[2], "out" }
    end
    return out
  end

  -- The sections' frames and their parts.
  local function section(name) return HF._sections[name] and HF._sections[name].frame end
  local function tile(id)
    local f = section("tiles")
    return f.mode == "compact" and f.compact[id] or f.full[id]
  end
  local function tileButton(id) return tile(id).button end
  local function footer() return section("footer") end
  local function cards()
    local out = {}
    for _, card in ipairs(section("carry").cards) do
      if card:IsShown() then out[#out + 1] = card end
    end
    return out
  end

  -- n followed groups, "Group 01" to "Group n", each with one item (300 + k), 20 of it in the bags and
  -- 30 in the Warband Bank; an odd one sells at twice its usual price, an even one at it.
  local function manyGroups(n)
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = {}, rules = {} }
    bags = { [0] = {}, [12] = {} }
    for k = 1, n do
      local id = 300 + k
      file.caps[k] = { i = id, c = 700, u = 1000, r = k, k = true }
      file.rules[k] = { n = ("Group %02d"):format(k), p = "gather", d = 24, fp = 80 }
      NAMES[id], VALUE[id] = "Item " .. k, k % 2 == 1 and 2000 or 1000
      bags[0][k] = info(id, 20)
      bags[12][k] = info(id, 30)
    end
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    used, timers, canUse, tabs, reads, landing, arrivals = {}, {}, true, { 12 }, 0, false, {}
    W.CLIENT_METRICS = true
    showing, usable, charTabs, refused, refusedHere = ACCOUNT, { [ACCOUNT] = true, [CHARACTER] = true }, { 6 }, {}, {}
    -- The slots holding an item bound to the account (Warbound): the client reports it isBound as it
    -- does a soulbound one, and the Warband Bank takes it.
    warbound = {}
    -- 0: the backpack; 5: the reagent bag; 6: the character's first bank tab; 12: the first
    -- Warband Bank tab.
    bags = {
      [0] = { info(1, 200), info(1, 20), info(9, 20), info(6, 15), info(3, 10), info(7, 5) },
      [5] = { info(3, 50) },
      [6] = { info(2, 40) },
      [12] = { info(2, 600), info(4, 30), info(6, 10), info(7, 15), info(8, 40) },
    }
    sizes = { [0] = 20, [5] = 36, [6] = 98, [12] = 98 }
    _G.Enum = { BankType = { Character = CHARACTER, Account = ACCOUNT } }
    _G.BANK, _G.ACCOUNT_BANK_PANEL_TITLE = "Bank", "Warband Bank"
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.SpellIsTargeting = function() return false end
    _G.GetCursorInfo = function() return nil end
    _G.UIParent = W.CreateFrame("Frame")
    _G.BankFrame = W.CreateFrame("Frame")
    function _G.BankFrame:GetActiveBankType() return showing end
    function _G.BankFrame:GetTop() return 4000 end
    _G.BankPanel = W.CreateFrame("Frame", nil, _G.BankFrame)
    function _G.BankPanel:Reset() end
    _G.MerchantFrame = W.CreateFrame("Frame")
    _G.MerchantFrame:Hide()
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    local function slots(bag) return sizes[bag] or (bags[bag] and #bags[bag]) or 0 end
    _G.C_Container = {
      GetContainerNumSlots = slots,
      GetContainerNumFreeSlots = function(bag)
        local free = 0
        for s = 1, slots(bag) do
          if not (bags[bag] and bags[bag][s]) then free = free + 1 end
        end
        return free, 0
      end,
      GetContainerItemInfo = function(bag, slot) reads = reads + 1; return bags[bag] and bags[bag][slot] or nil end,
      UseContainerItem = function(...)
        used[#used + 1] = { n = select("#", ...), ... }
        if not landing then return end
        local bag, slot, _, bankType = ...
        local stack = bags[bag][slot]
        local locked = {}
        for k, v in pairs(stack) do locked[k] = v end
        locked.isLocked = true
        bags[bag][slot] = locked
        local into = select("#", ...) == 5 and (bankType == CHARACTER and 6 or 12) or 0
        arrivals[#arrivals + 1] = { bag = bag, slot = slot, into = into, stack = stack }
      end,
    }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function() return false end,
      CanBeRefunded = function() return false end,
      GetCurrentItemLevel = function() return 0 end,
    }
    -- The Warband Bank refuses a soulbound item and takes a Warbound one, as the client answers.
    _G.C_Bank = {
      CanUseBank = function(t) return canUse and usable[t] == true end,
      IsItemAllowedInBankType = function(t, loc)
        local held = bags[loc.bag] and bags[loc.bag][loc.slot]
        if t == ACCOUNT and held and held.isBound and not warbound[loc.bag .. ":" .. loc.slot] then return false end
        return not (t == CHARACTER and refusedHere or refused)[loc.bag .. ":" .. loc.slot]
      end,
      FetchPurchasedBankTabIDs = function(t)
        if t == ACCOUNT then return tabs end
        return t == CHARACTER and charTabs or {}
      end,
    }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.hooksecurefunc = function(t, name, fn)
      local original = t[name]
      t[name] = function(...)
        local result = original(...)
        fn(...)
        return result
      end
    end
    -- The client's GameTooltip, down to the calls a button's tooltip makes; a double line is kept
    -- as its two sides joined by " | ".
    tip = { owner = nil, lines = {} }
    _G.GameTooltip = {
      SetOwner = function(_, owner) tip.owner, tip.lines = owner, {} end,
      ClearAllPoints = function() end,
      SetPoint = function(_, ...) tip.point = { ... } end,
      AddLine = function(_, text) tip.lines[#tip.lines + 1] = text end,
      AddDoubleLine = function(_, left, right) tip.lines[#tip.lines + 1] = left .. " | " .. right end,
      Show = function() end,
      Hide = function() tip.owner = nil end,
      IsOwned = function(_, owner) return tip.owner == owner end,
    }
    now = 1800000000
    _G.time = function() return now end
    _G.GetRealmName = function() return "Tarren Mill" end
    _G.GoldCap_AppRuns = FILE
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/NameMatch.lua", GC)
    helper.loadModule("Core/GroupRules.lua", GC)
    helper.loadModule("Core/CraftQueue.lua", GC)
    helper.loadModule("Core/BankGroups.lua", GC)
    helper.loadModule("Core/Hoard.lua", GC)
    helper.loadModule("Core/VendorPress.lua", GC)
    GC.GroupRules.Adopt()
    -- No route data unless a spec gives it: the carry cards stay away.
    local spots = {}
    origin = "app"
    GC.Data = {
      GetItemValue = function(id) return VALUE[id] and { mv = VALUE[id] } or nil end,
      SellSpots = function(id) return spots[id] end,
      FlipLevel = function() return nil end,
      RealmName = function(id) return ({ [1084] = "Tarren Mill", [1305] = "Kazzak" })[id] end,
      RealmIdByKey = function() return nil end,
      ClientRegion = function() return "eu" end,
      OriginState = function() return origin end,
      _spots = spots,
    }
    GC.Ledger = { GetGold = function() return { { char = "Alt-Kazzak", region = "eu", copper = 1 } } end }
    helper.loadModule("Core/SellRoute.lua", GC)
    -- 12 minutes ago, from the Companion.
    GC.db = { imported = { ts = now - 12 * 60 } }
    -- The craft queue of the character at the keyboard: 30 Resilient Leather of either quality, and
    -- 100 Bloom, for 3 crafts.
    needs, crafts = { { ids = { 7, 8 }, q = 30 }, { ids = { 1 }, q = 100 } }, 3
    GC.CraftQueueView = { Needs = function(char) return char == "Me-Tarren Mill" and needs or {}, crafts end }
    GC.CraftClient = { Char = function() return "Me-Tarren Mill" end, CurrencyCount = function() return 0 end }
    GC.BuyCapEditor = { Open = function() end, CloseFor = function() end }
    helper.loadModule("UI/BankRoute.lua", GC)
    helper.loadModule("UI/HoardFrame.lua", GC)
    helper.loadModule("UI/HoardRow.lua", GC)
    helper.loadModule("UI/HoardList.lua", GC)
    helper.loadModule("UI/HoardTiles.lua", GC)
    helper.loadModule("UI/HoardCarry.lua", GC)
    helper.loadModule("UI/HoardFooter.lua", GC)
    HF = GC.HoardFrame
  end)

  after_each(function()
    W.CLIENT_METRICS, W.CHAR_W = false, 6
    GC.ActivateLocale(nil)
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
    for id = 301, 320 do NAMES[id], VALUE[id] = nil, nil end
    NAMES[70], VALUE[70] = nil, nil
  end)

  -- Route data: this realm is Tarren Mill (1084), the account has a character on Kazzak (1305). The
  -- cinch (100) sells better on Kazzak, the recipe (200) best here.
  local function route()
    GC.Data.RealmIdByKey = function(key) return ({ tarrenmill = 1084, kazzak = 1305 })[key] end
    GC.Data._spots[100] = { { realmId = 1305, list = 2200 * G, days = 2.4, own = true },
      { realmId = 1084, list = 1500 * G, days = 1, own = true } }
    GC.Data._spots[200] = { { realmId = 1084, list = 900 * G, days = 0.5, own = true } }
    NAMES[100], NAMES[200] = "Gem-Inlaid Velvet Cinch", "Recipe: Ornate Plate"
    bags[0][#bags[0] + 1] = info(100, 1)
    bags[12][#bags[12] + 1] = info(200, 1)
  end

  -- ---------------------------------------------------------------------------------------------
  -- The tiles
  -- ---------------------------------------------------------------------------------------------

  it("stands three tiles under the switch, over the groups: Prices are up, For your crafts, Put away", function()
    open()
    local f = section("tiles")
    assert.equal(HF._frame, f:GetParent())
    assert.equal("full", f.mode)
    assert.equal("READY NOW", textOf(f.heading))
    assert.same({ "Prices are up", "For your crafts", "Put away" },
      { textOf(tile("pricesUp").title), textOf(tile("forCrafts").title), textOf(tile("putAway").title) })
    -- Side by side, as wide as each other, in the order of the board.
    local x1, x2, x3 = at(tile("pricesUp").card)[4], at(tile("forCrafts").card)[4], at(tile("putAway").card)[4]
    assert.is_true(x1 < x2 and x2 < x3)
    assert.equal(tile("pricesUp").card:GetWidth(), tile("putAway").card:GetWidth())
    assert.equal(tile("pricesUp").card:GetHeight(), tile("forCrafts").card:GetHeight())
    -- Above the groups' heading, which is in the scroll under them.
    assert.is_true(-at(f)[5] + f:GetHeight() <= -at(HF._frame.scroll)[5])
  end)

  -- At the Warband Bank: Bloom 2 (600 at 6g), Weavercloth (30 at 1g) and Mycobloom (10 at 1g) sell
  -- above their usual price; Bloom 1 and Bismuth do not.
  it("takes out exactly what sells above its usual price from the bank chosen, the most worth first", function()
    landing = true
    open()
    local pricesUp = tile("pricesUp")
    assert.equal("Take out " .. helper.money("3640g"), textOf(pricesUp.button.text))
    assert.equal("3 items sell above your usual price", textOf(pricesUp.line))
    assert.equal(1, alpha(pricesUp.card))
    press(pricesUp.button)
    assert.equal("tile:pricesUp", HF.Running())
    ticks()
    assert.same({ { 12, 1, "out" }, { 12, 2, "out" }, { 12, 3, "out" } }, moves())
    -- All three out: nothing is up any more, and the tile says so, dimmed, its button disabled.
    assert.is_nil(HF.Running())
    assert.is_false(tileButton("pricesUp"):IsEnabled())
    assert.equal(0.45, alpha(tile("pricesUp").card))
    assert.equal("Nothing sells above your usual price now", textOf(tile("pricesUp").line))
  end)

  it("lists in Prices are up's tooltip what it takes out, each price now and usual, its worth and what comes next", function()
    open()
    -- The kit's helper puts the tooltip beside a window, never inside it (UI/Theme.lua).
    local beside, real = nil, GC.Theme.ItemTooltipOutside
    GC.Theme.ItemTooltipOutside = function(owner, window)
      beside = { owner, window }
      return real(owner, window)
    end
    hover(tileButton("pricesUp"))
    GC.Theme.ItemTooltipOutside = real
    local lines = {}
    for i, line in ipairs(tip.lines) do lines[i] = helper.plain(line) end
    assert.equal("Prices are up", lines[1])
    assert.equal("These sell above the usual price you set for their group.", lines[2])
    assert.equal("Price per unit: now / usual", lines[3])
    assert.is_truthy(lines[4]:find("Bloom ×600 | " .. helper.money("6g") .. " / " .. helper.money("5g"), 1, true))
    assert.is_truthy(lines[5]:find("Weavercloth ×30 | " .. helper.money("1g") .. " / 50", 1, true))
    assert.is_truthy(lines[6]:find("Mycobloom ×10 | ", 1, true))
    assert.equal("Worth about " .. helper.money("3640g"), lines[7])
    assert.equal("Takes them out to your bags, ready for the Sell tab.", lines[8])
    -- Beside the window, never over the list it describes, as the approved board draws it.
    assert.same({ tileButton("pricesUp"), HF._frame }, beside)
  end)

  -- The queue needs 30 Resilient Leather: the bags hold 5, the Warband Bank 15 of one quality and
  -- 40 of the other. The fewest whole stacks that cover the 25 missing: the 40. Bloom is in the
  -- queue too, and the bags hold all it needs.
  it("takes out for the craft queue the fewest whole stacks that cover what the bags lack", function()
    landing = true
    open()
    local forCrafts = tile("forCrafts")
    assert.equal("Reagents for the 3 crafts in your queue", textOf(forCrafts.line))
    assert.equal("Take out 1 stack", textOf(forCrafts.button.text))
    hover(forCrafts.button)
    assert.equal("For your crafts", helper.plain(tip.lines[1]))
    assert.is_truthy(helper.plain(tip.lines[4]):find("Resilient Leather | 30 / 5 / 40", 1, true))
    press(forCrafts.button)
    ticks()
    assert.same({ { 12, 5, "out" } }, moves())
    assert.equal("Take out", textOf(tileButton("forCrafts").text))
    assert.is_false(tileButton("forCrafts"):IsEnabled())
  end)

  it("says the craft queue is empty, and asks the queue for the character at the keyboard", function()
    needs, crafts = {}, 0
    open()
    assert.equal("Your craft queue is empty", textOf(tile("forCrafts").line))
    assert.is_false(tileButton("forCrafts"):IsEnabled())
    needs, crafts = { { ids = { 7, 8 }, q = 30 } }, 1
    bagsChanged()
    assert.equal("Reagents for the craft in your queue", textOf(tile("forCrafts").line))
    GC.CraftClient.Char = function() return nil end
    bagsChanged()
    assert.is_false(tileButton("forCrafts"):IsEnabled())
  end)

  -- Put away is the groups' Store lists, keep counts held, less what Prices are up would sell from
  -- the bags (Mycobloom) and what the craft queue needs (Bloom): the two Bismuth stacks.
  it("stores the groups' stacks, leaving out what sells above its usual price and what the queue needs", function()
    landing = true
    open()
    local putAway = tile("putAway")
    assert.equal("Store 2 stacks", textOf(putAway.button.text))
    hover(putAway.button)
    local lines = {}
    for i, line in ipairs(tip.lines) do lines[i] = helper.plain(line) end
    assert.equal("Put away", lines[1])
    assert.equal("Leaves out what sells above its usual price and what your craft queue needs.", lines[2])
    assert.is_truthy(lines[3]:find("Bismuth ×60", 1, true))
    assert.equal("2 stacks into Warband Bank", lines[4])
    press(putAway.button)
    ticks()
    assert.same({ { 5, 1, ACCOUNT }, { 0, 5, ACCOUNT } }, moves())
  end)

  it("keeps a tile with nothing to do in its place, dimmed, its button disabled", function()
    open()
    local before = {}
    for _, id in ipairs({ "pricesUp", "forCrafts", "putAway" }) do
      before[id] = { at(tile(id).card), tile(id).card:GetHeight(), at(tile(id).button), tile(id).button:GetHeight() }
    end
    bags[12] = { info(7, 15), info(8, 40) }
    bagsChanged()
    local t = tile("pricesUp")
    assert.is_true(shown(t.card))
    assert.equal(0.45, alpha(t.card))
    assert.is_false(t.button:IsEnabled())
    assert.equal("Take out", textOf(t.button.text))
    for _, id in ipairs({ "pricesUp", "forCrafts", "putAway" }) do
      assert.same(before[id], { at(tile(id).card), tile(id).card:GetHeight(), at(tile(id).button), tile(id).button:GetHeight() }, id)
    end
  end)

  -- While a run goes the tiles dim and take no click, the one that runs excepted: its button is its
  -- Stop where it stands, and a second press of it stops the run.
  it("dims the other tiles while a run goes and makes the running tile's button its Stop", function()
    landing = true
    open()
    local before = { at(tileButton("putAway")), tileButton("putAway"):GetHeight(), tileButton("putAway"):GetWidth() }
    press(tileButton("putAway"))
    assert.equal("tile:putAway", HF.Running())
    assert.equal(tileButton("putAway"), select(2, HF.Running()))
    assert.equal("Stop", textOf(tileButton("putAway").text))
    assert.is_true(tileButton("putAway"):IsEnabled())
    assert.equal(1, alpha(tile("putAway").card))
    assert.same(before, { at(tileButton("putAway")), tileButton("putAway"):GetHeight(), tileButton("putAway"):GetWidth() })
    for _, id in ipairs({ "pricesUp", "forCrafts" }) do
      assert.equal(0.45, alpha(tile(id).card), id)
      assert.is_false(tileButton(id):IsEnabled(), id)
    end
    -- How far the run is, in the tile's line.
    assert.is_true(shown(tile("putAway").cast.count))
    assert.equal("0 / 2", textOf(tile("putAway").cast.count))
    press(tileButton("putAway"))
    assert.is_nil(HF.Running())
    assert.equal(1, #used)
    assert.equal(1, alpha(tile("pricesUp").card))
    assert.is_true(tileButton("pricesUp"):IsEnabled())
    -- The stack sent is on its way until the bags show it: the rest is offered.
    assert.equal("Store 1 stack", textOf(tileButton("putAway").text))
  end)

  it("dims every tile while a group's run goes", function()
    open()
    local herbs
    for _, r in ipairs(HF._rows) do if r:IsShown() and textOf(r.name) == "Herbs" then herbs = r end end
    press(herbs.take)
    for _, id in ipairs({ "pricesUp", "forCrafts", "putAway" }) do
      assert.equal(0.45, alpha(tile(id).card), id)
      assert.is_false(tileButton(id):IsEnabled(), id)
    end
  end)

  -- The tiles work with the bank the switch names: at the character's own bank its tab's Bloom 2
  -- (40 at 6g) is up, and Put away stores there.
  it("plans each tile against the bank the switch names", function()
    switchTo(CHARACTER)
    open()
    assert.equal("Take out " .. helper.money("240g"), textOf(tileButton("pricesUp").text))
    press(tileButton("putAway"))
    assert.same({ { 5, 1, CHARACTER } }, moves())
  end)

  -- A piece of gear is priced at the item level its group's cap names (610 here): a 615 sells above
  -- its usual price, a 600 has none (Core/GroupRules.lua's RuleFor). Prices are up takes out only
  -- the 615 in the bank, and Put away stores the 600 in the bags and keeps the 615 out.
  it("reads a piece of gear at its own item level for Prices are up and Put away", function()
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = {}, rules = FILE.rules }
    for i, cap in ipairs(FILE.caps) do file.caps[i] = cap end
    file.caps[#file.caps + 1] = { i = 70, c = 700, u = 5000, l = 610, r = 1, k = true }
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
    NAMES[70], VALUE[70] = "Ornate Girdle", 9000
    local levels = { ["12:6"] = 615, ["12:7"] = 600, ["0:7"] = 615, ["0:8"] = 600 }
    _G.C_Item.GetCurrentItemLevel = function(loc) return levels[loc.bag .. ":" .. loc.slot] or 0 end
    bags[12][6], bags[12][7] = info(70, 1), info(70, 1)
    bags[0][7], bags[0][8] = info(70, 1), info(70, 1)
    open()
    local function slots(id)
      local out = {}
      for _, stack in ipairs(tileButton(id).plan.stacks) do out[stack.bag .. ":" .. stack.slot] = true end
      return out
    end
    assert.is_true(slots("pricesUp")["12:6"])
    assert.is_nil(slots("pricesUp")["12:7"])
    assert.is_true(slots("putAway")["0:8"])
    assert.is_nil(slots("putAway")["0:7"])
    assert.equal("4 items sell above your usual price", textOf(tile("pricesUp").line))
  end)

  -- From SEARCH_MIN_GROUPS groups the tiles are the board's compact strip: each tile one button,
  -- two icons, its name, how much, and a chevron.
  it("is a compact strip of three buttons over many groups", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    open()
    local f = section("tiles")
    assert.equal("compact", f.mode)
    assert.is_false(shown(f.heading))
    for _, id in ipairs({ "pricesUp", "forCrafts", "putAway" }) do assert.is_false(shown(f.full[id].card), id) end
    local putAway = tile("putAway")
    assert.is_true(shown(putAway.button))
    assert.equal("Put away", textOf(putAway.title))
    -- The even ones: the odd ones sell above their usual price.
    assert.equal(math.floor(GC.Hoard.SEARCH_MIN_GROUPS / 2) .. " stacks", textOf(putAway.sub))
    -- The odd ones' 30 at 2,000 copper each, in the Warband Bank.
    assert.equal(helper.money("24g"), plainOf(tile("pricesUp").sub))
    press(putAway.button)
    assert.equal("tile:putAway", HF.Running())
    assert.equal(ACCOUNT, moves()[1][3])
    -- The strip stands over the search row.
    assert.is_true(-at(f)[5] + f:GetHeight() <= -at(HF._frame.search)[5])
  end)

  -- Pressed again and again in one spot: Prices are up's worth can grow up to the gold cap in the
  -- visit, and the strip keeps its height, in a face a step wider than the spec's own too, where the
  -- gold cap's figure takes two lines beside the icons.
  it("keeps the compact strip's height however much Prices are up comes to, in any language", function()
    W.CHAR_W = 7
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
    for _, code in ipairs(helper.localeCodes()) do
      GC.ActivateLocale(code)
      close()
      manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
      open()
      local h = tile("pricesUp").button:GetHeight()
      -- The four odd ones' 30 each, at 80,000g.
      for k = 1, GC.Hoard.SEARCH_MIN_GROUPS, 2 do VALUE[300 + k] = 80000 * 10000 end
      bagsChanged()
      assert.equal(helper.money("9600000g"), plainOf(tile("pricesUp").sub), code)
      assert.equal(h, tile("pricesUp").button:GetHeight(), code)
    end
  end)

  -- A compact tile is one button: while its run goes, the kit's close glyph stands where its chevron
  -- was, as an icon button's Stop wears it (UI/HoardList.lua's PaintPair), and its line says how far.
  it("shows the kit's close glyph in a compact tile's chevron place while its run goes", function()
    landing = true
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    open()
    local button = tileButton("putAway")
    local place = { at(button.icon), button.icon:GetWidth(), button.icon:GetHeight() }
    assert.equal("caretRight", glyph(button.icon))
    press(button)
    assert.equal("tile:putAway", HF.Running())
    assert.is_true(shown(button.icon))
    assert.equal("close", glyph(button.icon))
    assert.same(place, { at(button.icon), button.icon:GetWidth(), button.icon:GetHeight() })
    press(button)
    assert.is_nil(HF.Running())
    assert.is_true(shown(button.icon))
    assert.equal("caretRight", glyph(button.icon))
  end)

  -- With no followed group the tiles have nothing to move and stay away; the window reads only the
  -- bags, once, for Make room.
  it("paints no tile without a followed group, and reads no slot for them", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    open()
    assert.is_true(HF._frame:IsShown())
    assert.is_false(shown(section("tiles")))
    -- The backpack's 20 slots and the reagent bag's 36.
    assert.equal(20 + 36, reads)
  end)

  -- Pressed again and again in one spot: a tile keeps its place and size through a run and after it,
  -- in every language, and nothing on it is cut: its words wrap inside it.
  it("never moves a tile under the cursor and never cuts its words, in any language", function()
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
    for _, code in ipairs(helper.localeCodes()) do
      GC.ActivateLocale(code)
      close()
      bags[0] = { info(1, 200), info(1, 20), info(9, 20), info(6, 15), info(3, 10), info(7, 5) }
      bags[5] = { info(3, 50) }
      used, landing = {}, true
      open()
      local function place()
        local out = {}
        for _, id in ipairs({ "pricesUp", "forCrafts", "putAway" }) do
          local t = tile(id)
          out[#out + 1] = { at(t.card), t.card:GetHeight(), at(t.button), t.button:GetHeight(), t.button:GetWidth() }
        end
        return out
      end
      local before = place()
      for _, id in ipairs({ "pricesUp", "forCrafts", "putAway" }) do
        local t = tile(id)
        local card = t.card
        for _, fs in ipairs({ t.title, t.line, t.button.text }) do
          assert.is_true(fs:GetStringHeight() <= (fs == t.button.text and t.button:GetHeight() or card:GetHeight()),
            code .. " " .. id)
        end
        -- The button's words fit inside it, a line each, however many lines.
        assert.is_true(t.button.text:GetStringHeight() + 4 <= t.button:GetHeight(), code .. " " .. id)
        -- The line ends over the button.
        assert.is_true(-at(t.line)[5] + t.line:GetStringHeight() <= card:GetHeight() - 8 - t.button:GetHeight(),
          code .. " " .. id)
      end
      press(tileButton("putAway"))
      assert.same(before, place(), code)
      ticks()
      assert.same(before, place(), code)
    end
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The carry cards
  -- ---------------------------------------------------------------------------------------------

  it("shows a card for each flip to carry, under the groups, with where it sells and for how much", function()
    route()
    open()
    local list = cards()
    assert.equal(2, #list)
    assert.equal("CARRY TO ANOTHER REALM", textOf(list[1].eyebrow))
    assert.equal("Gem-Inlaid Velvet Cinch", plainOf(list[1].name))
    assert.equal("for Kazzak: " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days", textOf(list[1].where))
    assert.equal("Put in", textOf(list[1].button.text))
    assert.equal("TAKE OUT TO SELL HERE", textOf(list[2].eyebrow))
    assert.equal("Take out", textOf(list[2].button.text))
    assert.equal("Then log in a character on that realm and open a bank: GoldCap lists what to take out.",
      textOf(section("carry").note))
    -- In the scroll, under the groups.
    assert.equal(HF._frame.content, section("carry"):GetParent())
    -- The item's icon in its quality's edge.
    assert.equal(5100, W.state(list[1].icon.icon).file)
  end)

  -- The cards hand items to another character, which only the Warband Bank does: whatever bank the
  -- switch names.
  it("puts the card's stack into the Warband Bank whatever the switch says, and takes one out of it", function()
    route()
    switchTo(CHARACTER)
    open()
    assert.equal(CHARACTER, HF._bankType)
    local list = cards()
    press(list[1].button)
    assert.same({ { n = 5, 0, 7, nil, ACCOUNT, false } }, used)
    assert.equal("carry:100:0:7:in", HF.Running())
    press(cards()[2].button)
    assert.same({ n = 2, 12, 6 }, used[2])
    assert.equal("carry:200:12:6:out", HF.Running())
  end)

  -- A card's button moves the first stack of its item that the game does not hold and no press has
  -- sent: a stack on the cursor or on its way is passed over for the next.
  it("moves the card's first free stack, passing over one the game holds", function()
    route()
    bags[0][7] = info(100, 1, { isLocked = true })
    bags[0][8] = info(100, 1)
    open()
    local card = cards()[1]
    assert.equal("Gem-Inlaid Velvet Cinch ×2", plainOf(card.name))
    assert.is_true(card.button:IsEnabled())
    press(card.button)
    assert.same({ { n = 5, 0, 8, nil, ACCOUNT, false } }, used)
    assert.equal("carry:100:0:8:in", HF.Running())
    -- Its own run's Stop while that stack is on its way.
    assert.equal("Stop", textOf(cards()[1].button.text))
  end)

  -- A card done in this visit keeps its place, so the next press in that spot is not another card's.
  it("keeps a card whose stack has gone in its place for the visit, its button disabled", function()
    route()
    landing = true
    open()
    local first = cards()[1]
    local before = { at(first), first:GetHeight(), at(cards()[2]) }
    press(first.button)
    ticks()
    assert.equal(first, cards()[1])
    assert.same(before, { at(first), first:GetHeight(), at(cards()[2]) })
    assert.is_false(first.button:IsEnabled())
  end)

  it("shows no card without route data, without the Warband Bank, or with only a piece that cannot be sold", function()
    open()
    assert.same({}, cards())
    close()
    route()
    usable[ACCOUNT] = false
    open()
    assert.same({}, cards())
    close()
    usable[ACCOUNT] = true
    _G.C_Item.IsBoundToAccountUntilEquip = function(loc) return loc.bag == 0 and loc.slot == 7 end
    bags[12][6] = false
    open()
    assert.same({}, cards())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The footer
  -- ---------------------------------------------------------------------------------------------

  it("stands Make room, Put back and where the prices come from at the window's foot", function()
    open()
    local f = footer()
    assert.equal(HF._frame, f:GetParent())
    assert.equal("BOTTOMLEFT", at(f)[1])
    assert.equal("Make room", textOf(f.makeRoom.text))
    assert.equal("Put back", textOf(f.putBack.text))
    assert.equal("Prices from the Companion, 12m ago", textOf(f.prices))
    assert.same(GC.Kit.Tokens.color.profit, W.state(f.dot).vertex)
  end)

  -- Make room at the Warband Bank: every stack in the bags it takes, the biggest first, a Warbound
  -- one too, which the client reports bound as it does a soulbound one. At the character's own bank
  -- a soulbound one too, which the Warband Bank refuses.
  it("makes room with every stack the bank chosen takes, soulbound ones only into the character's bank", function()
    landing = true
    bags[0][2] = info(1, 20, { isBound = true })
    bags[0][7] = info(9, 5, { isBound = true })
    warbound["0:7"] = true
    open()
    press(footer().makeRoom)
    assert.same({ 0, 1, ACCOUNT }, moves()[1])
    ticks()
    -- Every stack of the bags but the soulbound one: six in the backpack, the Warbound one among
    -- them, and one in the reagent bag.
    assert.equal(7, #used)
    local slots = {}
    for _, m in ipairs(moves()) do slots[m[1] .. ":" .. m[2]] = true end
    assert.is_nil(slots["0:2"])
    assert.is_true(slots["0:7"])
    close()
    -- Put back would bring those back first (a room is one bank's): this is another character's day.
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", nil)
    used = {}
    switchTo(CHARACTER)
    bags[0] = { info(1, 20, { isBound = true }), info(9, 5, { isBound = true }) }
    warbound = { ["0:2"] = true }
    bags[5] = {}
    open()
    press(footer().makeRoom)
    ticks()
    assert.same({ { 0, 1, CHARACTER }, { 0, 2, CHARACTER } }, moves())
  end)

  -- What Make room put away is what left the bags, remembered for this character, and a second Make
  -- room into the same bank adds to it; Put back takes it back from that bank, then forgets it.
  it("remembers what Make room moved, adds a second one to it, and forgets it once Put back brings it back", function()
    landing = true
    bags[0] = { info(9, 20) }
    bags[5] = {}
    open()
    assert.is_false(footer().putBack:IsEnabled())
    press(footer().makeRoom)
    ticks()
    local room = GC.Hoard.Room(GC.db, "Me-Tarren Mill")
    assert.equal(ACCOUNT, room.bankType)
    assert.same({ [9] = 20 }, room.items)
    assert.equal(now, room.at)
    bags[0] = { info(3, 7) }
    bagsChanged()
    press(footer().makeRoom)
    ticks()
    assert.same({ [9] = 20, [3] = 7 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    -- Put back: the 20 Linen and the 7 Bismuth, from the Warband Bank's tab.
    assert.is_true(footer().putBack:IsEnabled())
    used = {}
    press(footer().putBack)
    ticks()
    for _, m in ipairs(moves()) do assert.same({ 12, "out" }, { m[1], m[3] }) end
    assert.equal(2, #used)
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    assert.is_false(footer().putBack:IsEnabled())
  end)

  -- Put back works from the bank Make room put things in: with the switch on the other one it is
  -- disabled, and its tooltip says which bank holds them.
  it("disables Put back with nothing remembered, and when the switch names the other bank, saying which", function()
    open()
    hover(footer().putBack)
    assert.equal("Make room has put nothing away to bring back.", helper.plain(tip.lines[2]))
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = CHARACTER, at = now, items = { [2] = 40 } })
    bagsChanged()
    assert.is_false(footer().putBack:IsEnabled())
    hover(footer().putBack)
    assert.equal("What Make room put away is in Bank: switch to it to put it back.", helper.plain(tip.lines[2]))
    W.state(HF._frame.choice.sides[1]).scripts.OnClick(HF._frame.choice.sides[1])
    assert.equal(CHARACTER, HF._bankType)
    assert.is_true(footer().putBack:IsEnabled())
    hover(footer().putBack)
    assert.equal("Takes back from Bank what Make room put there. It lands wherever your bags have room, not in its old slots.",
      helper.plain(tip.lines[2]))
  end)

  -- What Make room put away is never more than its bank holds: another character took some of it
  -- out of the Warband Bank, or the player took it all by hand. A later Make room starts afresh.
  it("caps what Put back brings back at what the bank still holds, and forgets what it holds none of", function()
    landing = true
    bags[0] = { info(9, 20), info(3, 7) }
    bags[5] = {}
    open()
    press(footer().makeRoom)
    ticks()
    assert.same({ [9] = 20, [3] = 7 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    -- A minute later another character took 8 of the Linen; the player took the Bismuth by hand.
    now = now + 60
    for slot, held in pairs(bags[12]) do
      if held and held.itemID == 9 then bags[12][slot] = info(9, 12) end
      if held and held.itemID == 3 then bags[12][slot] = false end
    end
    bagsChanged()
    assert.same({ [9] = 12 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    -- The player takes the rest by hand: nothing is left to put back.
    for slot, held in pairs(bags[12]) do
      if held and held.itemID == 9 then bags[12][slot] = false end
    end
    bagsChanged()
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    assert.is_false(footer().putBack:IsEnabled())
    -- A later Make room remembers what it puts away now, not the count that was.
    bags[0] = { info(9, 5) }
    bagsChanged()
    press(footer().makeRoom)
    ticks()
    assert.same({ [9] = 5 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
  end)

  -- Make room's 220 Linen merged into two stacks in the Warband Bank, 200 and 20. Put back's run
  -- stopped once the 200 came out, the window repainting in between: the 20 the bank still holds
  -- are still to bring back. What a paint caps while a run goes is never written, so the run's end
  -- does not take the 200 off a second time.
  local function linenRoom()
    bags[12][6], bags[12][7] = info(9, 200), info(9, 20)
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = ACCOUNT, at = now, items = { [9] = 220 } })
  end

  it("keeps what is still in the bank when Put back's run stops partway", function()
    landing = true
    linenRoom()
    open()
    press(footer().putBack)
    assert.same({ { 12, 6, "out" } }, moves())
    land()
    bagsChanged()
    assert.same({ [9] = 220 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    press(footer().putBack)
    assert.is_nil(HF.Running())
    assert.same({ [9] = 20 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    assert.is_true(footer().putBack:IsEnabled())
  end)

  it("forgets the room once Put back's run brought it all back", function()
    landing = true
    linenRoom()
    open()
    press(footer().putBack)
    ticks()
    assert.same({ { 12, 6, "out" }, { 12, 7, "out" } }, moves())
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
  end)

  -- The server refused the 20 (the bags were full): it stays in the bank, and in the room.
  it("keeps a stack the server refused in the middle of Put back's run", function()
    landing = true
    linenRoom()
    open()
    press(footer().putBack)
    landing = false
    ticks()
    assert.equal(2, #used)
    assert.same({ [9] = 220 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    settle()
    assert.same({ [9] = 20 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
  end)

  -- A room is one bank's: while what Make room put into the other bank is not back, Make room is
  -- disabled and says where it is; it works again once Put back brings it back.
  it("disables Make room while what it put into the other bank is not back, and enables it once Put back has", function()
    landing = true
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = CHARACTER, at = now, items = { [2] = 40 } })
    open()
    assert.equal(ACCOUNT, HF._bankType)
    assert.is_false(footer().makeRoom:IsEnabled())
    hover(footer().makeRoom)
    assert.equal("Make room", helper.plain(tip.lines[1]))
    assert.equal("What Make room put away is still in Bank: put it back first.", helper.plain(tip.lines[2]))
    W.state(HF._frame.choice.sides[1]).scripts.OnClick(HF._frame.choice.sides[1])
    assert.equal(CHARACTER, HF._bankType)
    press(footer().putBack)
    ticks()
    assert.same({ { 6, 1, "out" } }, moves())
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    assert.is_true(footer().makeRoom:IsEnabled())
    W.state(HF._frame.choice.sides[2]).scripts.OnClick(HF._frame.choice.sides[2])
    assert.equal(ACCOUNT, HF._bankType)
    assert.is_true(footer().makeRoom:IsEnabled())
  end)

  it("enables Make room again once the other bank holds none of what it put there", function()
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = CHARACTER, at = now - 60, items = { [2] = 40 } })
    open()
    assert.is_false(footer().makeRoom:IsEnabled())
    -- The player took the 40 out of the character's bank by hand.
    bags[6] = {}
    bagsChanged()
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    assert.is_true(footer().makeRoom:IsEnabled())
  end)

  it("disables Make room while it could not remember what it puts away, saying why", function()
    GC.db.hoard = { v = GC.Hoard.VERSION + 1 }
    open()
    assert.is_false(footer().makeRoom:IsEnabled())
    hover(footer().makeRoom)
    assert.equal("A newer version of GoldCap saved what Make room remembers: update GoldCap to use it.",
      helper.plain(tip.lines[2]))
    GC.db.hoard = nil
    GC.CraftClient.Char = function() return nil end
    bagsChanged()
    assert.is_false(footer().makeRoom:IsEnabled())
    hover(footer().makeRoom)
    assert.equal("GoldCap does not know this character's name and realm yet, so Make room cannot remember what it puts away.",
      helper.plain(tip.lines[2]))
    GC.CraftClient.Char = function() return "Me-Tarren Mill" end
    bagsChanged()
    assert.is_true(footer().makeRoom:IsEnabled())
  end)

  -- The bank closed while Make room's stack was on its way: it is remembered once the bags show it
  -- left.
  it("remembers a stack Make room sent before the bank closed once it lands", function()
    landing = true
    bags[0] = { info(9, 20), info(3, 7) }
    bags[5] = {}
    open()
    press(footer().makeRoom)
    close()
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    land()
    bagsChanged()
    assert.same({ [9] = 20 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
  end)

  -- The Warband Bank can show a deposit a moment after the bags show it gone: for the route's
  -- SETTLE_SECONDS after Make room remembered it, the room is not capped at what the bank's slots
  -- show, so a slot that updates late does not lose what went in.
  it("keeps what Make room remembered while the bank has not shown it yet", function()
    landing = true
    bags[0] = { info(9, 20) }
    bags[5] = {}
    open()
    press(footer().makeRoom)
    -- The bags show the Linen gone; the Warband Bank's slot does not show it yet.
    arrivals = {}
    bags[0][1] = false
    bagsChanged()
    ticks()
    assert.is_nil(HF.Running())
    assert.same({ bankType = ACCOUNT, at = now, items = { [9] = 20 } }, GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    now = now + GC.BankRoute.SETTLE_SECONDS - 1
    bagsChanged()
    assert.same({ [9] = 20 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    -- It shows: kept, as the bank holds it.
    bags[12][#bags[12] + 1] = info(9, 20)
    now = now + 1
    bagsChanged()
    assert.same({ [9] = 20 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
    -- Once settled, what the bank does not hold is no longer remembered.
    bags[12][#bags[12]] = info(9, 12)
    bagsChanged()
    assert.same({ [9] = 12 }, GC.Hoard.Room(GC.db, "Me-Tarren Mill").items)
  end)

  -- A move takes what the other side has room for: the bags had room for 150 of the 200 Linen Put
  -- back took out, so the bank's slot keeps 50. What left the slot is what came back, and the 50 are
  -- still to put back.
  it("counts what left a slot: a withdraw the bags took only part of leaves the rest to put back", function()
    landing = true
    bags[12][6] = info(9, 200)
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = ACCOUNT, at = now - 60, items = { [9] = 200 } })
    open()
    press(footer().putBack)
    assert.same({ { 12, 6, "out" } }, moves())
    arrivals = {}
    bags[12][6] = info(9, 50)
    bags[0][#bags[0] + 1] = info(9, 150)
    bagsChanged()
    -- The slot still holds Linen: the run waits for it, then stops.
    ticks()
    assert.is_nil(HF.Running())
    assert.same({ bankType = ACCOUNT, at = now - 60, items = { [9] = 50 } }, GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    assert.is_true(footer().putBack:IsEnabled())
  end)

  -- Pressed again and again in one spot: the price line can say an older age or another source in
  -- the visit, and the footer keeps its height and its buttons their place.
  it("keeps the footer's room and its buttons' place whatever the price line says in the visit, in any language", function()
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
    for _, code in ipairs(helper.localeCodes()) do
      GC.ActivateLocale(code)
      close()
      origin, GC.db.imported = "app", { ts = now - 12 * 60 }
      open()
      local f = footer()
      local function place() return { f:GetHeight(), at(f), at(f.makeRoom), at(f.putBack) } end
      local before = place()
      for _, age in ipairs({ 59 * 60, 23 * 3600, 400 * 86400 }) do
        GC.db.imported.ts = now - age
        bagsChanged()
        assert.same(before, place(), code .. " " .. age)
      end
      origin = "manual"
      bagsChanged()
      assert.same(before, place(), code .. " manual")
      origin, GC.db.imported = "none", nil
      bagsChanged()
      assert.same(before, place(), code .. " none")
    end
  end)

  it("turns the price line amber once the prices are older than FRESH_SECONDS, and says where they came from", function()
    local K = GC.Kit.Tokens.color
    GC.db.imported.ts = now - HF.Footer.FRESH_SECONDS + 1
    open()
    assert.same(K.profit, W.state(footer().dot).vertex)
    GC.db.imported.ts = now - HF.Footer.FRESH_SECONDS
    bagsChanged()
    assert.same(K.warn, W.state(footer().dot).vertex)
    assert.equal("Prices from the Companion, 2h ago", textOf(footer().prices))
    origin = "manual"
    bagsChanged()
    assert.equal("You pasted these prices 2h ago", textOf(footer().prices))
    origin, GC.db.imported = "none", nil
    bagsChanged()
    assert.equal("No prices for your region yet", textOf(footer().prices))
    assert.same(K.warn, W.state(footer().dot).vertex)
  end)

  -- Make room and Put back need no group: the footer stands with none.
  it("shows the footer with no followed group", function()
    route()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    open()
    assert.is_true(HF._frame:IsShown())
    assert.is_true(shown(footer()))
    assert.is_true(footer().makeRoom:IsEnabled())
    assert.is_false(footer().putBack:IsEnabled())
    assert.equal(2, #cards())
  end)

  -- Unfollowing every group does not strand what Make room put away: Put back brings it back.
  it("brings back what Make room put away with no followed group", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = ACCOUNT, at = now, items = { [2] = 100 } })
    landing = true
    open()
    assert.is_true(HF._frame:IsShown())
    assert.is_true(shown(footer()))
    assert.is_true(footer().putBack:IsEnabled())
    press(footer().putBack)
    ticks()
    assert.same({ { 12, 1, "out" } }, moves())
    assert.is_nil(GC.Hoard.Room(GC.db, "Me-Tarren Mill"))
    assert.is_true(HF._frame:IsShown())
    assert.is_false(footer().putBack:IsEnabled())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The window while things move
  -- ---------------------------------------------------------------------------------------------

  -- Where the window's height leaves its foot on the screen: the window hangs from the bank
  -- window's top, and the footer and the selection bar stand on its bottom.
  local function foot()
    local f = HF._frame
    local bottom = _G.BankFrame:GetTop() + at(f)[5] - f:GetHeight()
    return { height = f:GetHeight(), footer = bottom + at(footer())[5], bar = bottom + at(f.selection)[5],
      makeRoom = at(footer().makeRoom)[4], putBack = at(footer().putBack)[4] }
  end

  -- Pressed again and again in one spot: Make room's Stop and the selection bar stay under the
  -- cursor while its run changes the list. The bags keep 100 Bismuth for Ore, so Ore has nothing to
  -- move here and folds under the line; Make room puts its Bismuth into the Warband Bank, and Ore
  -- comes up from under it. The window keeps its height and the scroll takes the change.
  it("keeps its height and its foot where they are while Make room brings a folded group up", function()
    landing = true
    GC.BankGroups.SetKeep(GC.db, "Ore", 100)
    open()
    local f = HF._frame
    assert.is_true(shown(f.fold))
    local before = foot()
    press(footer().makeRoom)
    assert.same(before, foot())
    for _ = 1, 3 do
      land()
      bagsChanged()
      assert.same(before, foot())
      for k, t in ipairs(timers) do
        if t.seconds == GC.VendorPress.STEP then table.remove(timers, k).fn() break end
      end
    end
    ticks()
    assert.is_nil(HF.Running())
    assert.is_false(shown(f.fold))
    assert.same(before, foot())
  end)

  -- Put back takes the cinch out of the Warband Bank to the bags, where it sells better on another
  -- of the player's realms: a carry card comes under the others, and the foot stays where it was.
  it("keeps its height and its foot where they are while Put back brings a card to carry", function()
    route()
    landing = true
    bags[0][7] = false
    bags[12][7] = info(100, 1)
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = ACCOUNT, at = now - 60, items = { [100] = 1 } })
    open()
    local list = cards()
    local before = foot()
    press(footer().putBack)
    assert.same(before, foot())
    ticks()
    assert.equal(#list + 1, #cards())
    assert.same(before, foot())
  end)

  -- The player's own clicks that change what the list holds take the window to its new height:
  -- opening a row.
  it("takes its new height at a click that opens a row, never at a bag event", function()
    open()
    local f = HF._frame
    local h = f:GetHeight()
    -- Another character takes the Weavercloth out of the Warband Bank: Cloth's row goes, and the
    -- window stays as it was, the scroll taking the room.
    local scrollH = f.scroll:GetHeight()
    bags[12][2] = false
    bagsChanged()
    assert.equal(h, f:GetHeight())
    assert.equal(scrollH, f.scroll:GetHeight())
    local herbs
    for _, r in ipairs(HF._rows) do if r:IsShown() and textOf(r.name) == "Herbs" then herbs = r end end
    press(herbs.head)
    assert.is_true(f:GetHeight() > h)
  end)

  -- The bank window's own tab brings up the other bank, a new list: the window takes the height that
  -- list asks for, as the switch's click would.
  it("takes its height again when the bank window's own tab shows the other bank", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    -- Nothing in the bags or the character's bank: every group folds there, and the window is low.
    bags[0], bags[5], bags[6] = {}, {}, {}
    showing = CHARACTER
    open()
    local f = HF._frame
    local low = f:GetHeight()
    switchTo(ACCOUNT)
    assert.equal(ACCOUNT, HF._bankType)
    local h = f:GetHeight()
    assert.is_true(h > low)
    HF.Refresh(false, true)
    assert.equal(h, f:GetHeight())
  end)

  -- A bag event outside a run keeps the window's height, but never under the least it has room for:
  -- rows that came since the list showed less than ROWS_MIN of them get that room.
  it("grows to its least height at a bag event when the list it kept was shorter", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    -- Nothing in the bags or the Warband Bank: every group folds, and the window is low.
    bags[0], bags[5], bags[12] = {}, {}, {}
    open()
    local f = HF._frame
    local low, scrollLow = f:GetHeight(), f.scroll:GetHeight()
    -- Another character puts three groups' items into the Warband Bank: three rows to take out.
    for k = 1, 3 do bags[12][k] = info(300 + k, 30) end
    bagsChanged()
    assert.is_true(f:GetHeight() > low)
    assert.is_true(f.scroll:GetHeight() > scrollLow)
    local L = HF.ui.L
    assert.is_true(f.scroll:GetHeight() >= L.ROWS_MIN * (L.ROW_H + L.ROW_GAP))
  end)

  -- One paint reads each bag slot and each bank tab's slot once, whatever its parts need: here the
  -- groups at the character's own bank, the craft queue's reagents (the tiles), the carry cards (the
  -- Warband Bank) and what Make room put into the Warband Bank (the footer).
  it("reads the bags and each bank once a paint", function()
    route()
    switchTo(CHARACTER)
    GC.Hoard.SetRoom(GC.db, "Me-Tarren Mill", { bankType = ACCOUNT, at = now - 60, items = { [2] = 600 } })
    open()
    assert.equal(CHARACTER, HF._bankType)
    assert.is_true(#cards() > 0)
    reads = 0
    bagsChanged()
    -- The backpack's 20 slots and the reagent bag's 36, the character's tab and the Warband Bank's.
    assert.equal(20 + 36 + 98 + 98, reads)
  end)

  -- A click that only changes what the window shows paints from what the last paint read.
  it("reads nothing for a keystroke in the search box, the filter, the sort or a checkbox", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    open()
    local search = HF._frame.search
    reads = 0
    typeInto(search.box, "G")
    typeInto(search.box, "Gr")
    press(search.filter.sides[2])
    press(search.sort)
    for _, r in ipairs(HF._rows) do
      if r:IsShown() then press(r.check) break end
    end
    assert.equal(0, reads)
  end)

  -- A move into the Warband Bank is told twice, by BAG_UPDATE_DELAYED and by the Warband Bank's
  -- slot that took it (PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED): one paint for both, on the next
  -- frame.
  it("paints once for a move into the Warband Bank, on the next frame", function()
    landing = true
    open()
    reads = 0
    bagsChanged()
    local one = reads
    assert.is_true(one > 0)
    press(tileButton("putAway"))
    land()
    reads = 0
    GC.BankRoute.OnBagsChanged()
    GC.BankRoute.OnTabSlotsChanged()
    GC.BankRoute.OnTabSlotsChanged()
    assert.equal(0, reads)
    nextFrame()
    nextFrame()
    assert.equal(one, reads)
  end)
end)
