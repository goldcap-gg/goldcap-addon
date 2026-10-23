local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/HoardFrame.lua and UI/HoardRow.lua: GoldCap Hoard, the window beside Blizzard's bank window.
-- Its followed groups as rows and folders, with Store and Take out on each, Store all and Take all
-- out over every group, the bank switch, and the sections later tasks paint into it. The real Theme
-- and kit, the real group rules (from a Companion file), the real plan (Core/BankGroups.lua) and
-- rows (Core/Hoard.lua), the real press machine (Core/VendorPress.lua) and the real bank route
-- (UI/BankRoute.lua), whose reader, move function and guards the window uses; the bags, both banks,
-- the bank window, the tooltip and the client calls are faked, shaped as the client's.
describe("GoldCap Hoard window", function()
  local GC, HF, restore, saved, bags, sizes, used, timers, canUse, tabs, refundable, refused, reads, asked
  local closedFor, showing, usable, charTabs, refusedHere, targeting, landing, tip
  -- Enum.BankType (Blizzard_APIDocumentationGenerated's ItemConstantsDocumentation.lua).
  local CHARACTER, ACCOUNT = 0, 2
  local KEYS = { "Enum", "UIParent", "BankFrame", "BankPanel", "MerchantFrame", "ItemLocation", "C_Container",
    "C_Item", "C_Bank", "C_Timer", "hooksecurefunc", "GoldCap_AppRuns", "SpellIsTargeting", "GetCursorInfo", "BANK",
    "ACCOUNT_BANK_PANEL_TITLE", "CreateColor", "GameTooltip" }

  -- Herbs: Bloom (two qualities, 1 and 2) and Mycobloom (6); Ore: Bismuth (3); Cloth: Weavercloth
  -- (4), never in the bags here. Item 9 is in no followed group.
  local FILE = {
    v = 3, generatedAt = 1, runs = {}, groups = { "G" },
    caps = {
      { i = 1, c = 700, u = 1000, r = 1, k = true }, { i = 2, c = 700, u = 1000, r = 1, k = true },
      { i = 3, c = 700, u = 1000, r = 2, k = true }, { i = 4, c = 700, u = 1000, r = 3, k = true },
      { i = 6, c = 700, u = 1000, r = 1, k = true },
    },
    rules = { { n = "Herbs", p = "gather", d = 24, fp = 80 }, { n = "Ore", p = "gather", d = 24, fp = 80 },
      { n = "Cloth", p = "craft", d = 24, fp = 80 } },
  }
  local NAMES = { [1] = "Bloom", [2] = "Bloom", [3] = "Bismuth", [4] = "Weavercloth", [6] = "Mycobloom of the Deepest Earthen Caverns",
    [9] = "Linen Cloth" }
  -- Market values in copper: at the Warband Bank Herbs is worth 220 x 5g + 600 x 6g = 4,700g, Ore
  -- 50 x 2g = 100g.
  local VALUE = { [1] = 50000, [2] = 60000, [3] = 20000, [4] = 10000, [6] = 10000 }

  local function info(itemID, count, over)
    local i = { itemID = itemID, itemName = NAMES[itemID], stackCount = count, iconFileID = 5000 + itemID,
      hyperlink = "item:" .. itemID, isBound = false, isLocked = false }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  local function textOf(fs) return W.state(fs).text end
  local function shown(widget) return widget ~= nil and widget:IsShown() end
  local function windowUp() return HF._frame ~= nil and HF._frame:IsShown() end
  local function press(button) W.state(button).scripts.OnClick(button) end
  local function at(widget) return W.state(widget).points[1] end

  -- A shown row by the name it shows, and of a kind when asked.
  local function row(name, kind)
    for _, r in ipairs(HF._rows) do
      if r:IsShown() and textOf(r.name) == name and (kind == nil or r.data.kind == kind) then return r end
    end
  end
  local function rowNames()
    local out = {}
    for _, r in ipairs(HF._rows) do if r:IsShown() then out[#out + 1] = textOf(r.name) end end
    return out
  end
  local function openRow(name) press(row(name).head) end
  local function lines(r, list)
    local out = {}
    for _, fs in ipairs(r[list]) do
      local text = fs.counts and textOf(fs.counts) or textOf(fs)
      if (fs.counts and fs.counts:IsShown()) or (not fs.counts and fs:IsShown()) then out[#out + 1] = text end
    end
    return out
  end

  -- The window's bank switch: its side for a bank, and a click on it.
  local function side(bankType)
    for _, b in ipairs(HF._frame.choice.sides) do
      if b.bankType == bankType then return b end
    end
  end
  local function choose(bankType) press(side(bankType)) end
  -- The player clicks the bank window's other tab: BankFrame:SetTab sets the panel's bank type and
  -- the panel resets (Blizzard_UIPanels_Game's BankFrame.lua); the window repaints on the next
  -- frame.
  local function nextFrame()
    for i = #timers, 1, -1 do
      if timers[i].seconds == 0 then table.remove(timers, i).fn() end
    end
  end
  local function switchTo(bankType)
    showing = bankType
    _G.BankPanel:Reset()
    nextFrame()
  end

  local function open() GC.BankRoute.OnBankOpened() end
  local function close() GC.BankRoute.OnBankClosed() end
  local function bagsChanged() GC.BankRoute.OnBagsChanged() end

  -- The press machine's own timers (Core/VendorPress.lua's STEP), first armed first, until none is
  -- left; answers how many ran. The settle timers stay.
  local function ticks()
    local n = 0
    while true do
      local due
      for k, t in ipairs(timers) do
        if t.seconds == GC.VendorPress.STEP then due = k break end
      end
      if not due then return n end
      table.remove(timers, due).fn()
      n = n + 1
    end
  end

  -- n followed groups, "Group 01" to "Group n", each with one item (100 + k), 20 of it in the bags.
  local function manyGroups(n)
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = {}, rules = {} }
    bags = { [0] = {}, [12] = {} }
    for k = 1, n do
      file.caps[k] = { i = 100 + k, c = 700, u = 1000, r = k, k = true }
      file.rules[k] = { n = ("Group %02d"):format(k), p = "gather", d = 24, fp = 80 }
      NAMES[100 + k] = "Item " .. k
      bags[0][k] = info(100 + k, 20)
    end
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
  end

  -- Folders: Herbs and Ore are subgroups of Gathering on goldcap.gg, so they fold under one folder
  -- named after it; Cloth is a top group. With `clash`, a top group the player follows has the
  -- folder's own key (gathering): two rows, told apart by kind.
  local function folders(clash)
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = {
      { i = 1, c = 700, u = 1000, r = 1, k = true }, { i = 2, c = 700, u = 1000, r = 1, k = true },
      { i = 3, c = 700, u = 1000, r = 2, k = true }, { i = 4, c = 700, u = 1000, r = 3, k = true },
      { i = 9, c = 700, u = 1000, r = 4, k = true },
    }, rules = {
      { n = "Gathering: Herbs", id = "herbs", pi = "gathering", pn = "Gathering", cn = "Herbs", p = "gather", d = 24 },
      { n = "Gathering: Ore", id = "ore", pi = "gathering", pn = "Gathering", cn = "Ore", p = "gather", d = 24 },
      { n = "Cloth", id = "cloth", p = "craft", d = 24 },
      { n = clash and "Gathering" or "Linen", id = clash and "gathering" or "linen", p = "stock", d = 24 },
    } }
    VALUE[9] = 1000
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    used, timers, canUse, tabs, refundable, refused, reads, asked = {}, {}, true, { 12 }, {}, {}, 0, nil
    landing = false
    -- The bank window shows the Warband Bank unless a spec switches it; refusedHere is what the
    -- character's own bank refuses, refused what the Warband Bank does.
    showing, usable, charTabs, refusedHere = ACCOUNT, { [ACCOUNT] = true, [CHARACTER] = true }, { 6 }, {}
    -- 0: the backpack; 5: the reagent bag; 6: the character's first bank tab; 12: the first
    -- Warband Bank tab. `sizes` is how many slots each has; a missing one has as many as it holds.
    bags = {
      [0] = { info(1, 200), info(1, 20), info(9, 20) },
      [5] = { info(3, 50) },
      [6] = { info(2, 40) },
      [12] = { info(2, 600) },
    }
    sizes = { [0] = 20, [5] = 36, [6] = 98, [12] = 98 }
    _G.Enum = { BankType = { Character = CHARACTER, Account = ACCOUNT } }
    -- The client's own names for the two banks, which the bank window's tabs read.
    _G.BANK, _G.ACCOUNT_BANK_PANEL_TITLE = "Bank", "Warband Bank"
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    -- Read by GC.Util.CursorBusy: no spell waits for a target and the cursor is empty.
    targeting = false
    _G.SpellIsTargeting = function() return targeting end
    _G.GetCursorInfo = function() return nil end
    _G.UIParent = W.CreateFrame("Frame")
    _G.BankFrame = W.CreateFrame("Frame")
    _G.BankFrame:Show()
    -- BankFrameMixin:GetActiveBankType, and the panel's BankPanelMixin:Reset, which the window
    -- post-hooks.
    function _G.BankFrame:GetActiveBankType() return showing end
    _G.BankPanel = W.CreateFrame("Frame", nil, _G.BankFrame)
    function _G.BankPanel:Reset() end
    -- A frame the client builds is hidden until it opens; a W frame starts shown.
    _G.MerchantFrame = W.CreateFrame("Frame")
    _G.MerchantFrame:Hide()
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    local function slots(bag) return sizes[bag] or (bags[bag] and #bags[bag]) or 0 end
    _G.C_Container = {
      GetContainerNumSlots = slots,
      -- numFreeSlots, bagFamily (ContainerDocumentation.lua).
      GetContainerNumFreeSlots = function(bag)
        local free = 0
        for s = 1, slots(bag) do
          if not (bags[bag] and bags[bag][s]) then free = free + 1 end
        end
        return free, 0
      end,
      GetContainerItemInfo = function(bag, slot) reads = reads + 1; return bags[bag] and bags[bag][slot] or nil end,
      -- With `landing`, the server takes each move at once: the slot empties (false keeps the bag's
      -- size) and the stack lands at the end of the bags, the character's bank tab or the Warband
      -- Bank's, as the call names them.
      UseContainerItem = function(...)
        used[#used + 1] = { n = select("#", ...), ... }
        if not landing then return end
        local bag, slot, _, bankType = ...
        local stack = bags[bag][slot]
        bags[bag][slot] = false
        local into = select("#", ...) == 5 and (bankType == CHARACTER and 6 or 12) or 0
        bags[into][#bags[into] + 1] = stack
      end,
    }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function() return false end,
      CanBeRefunded = function(loc) return refundable[loc.bag .. ":" .. loc.slot] == true end,
      GetCurrentItemLevel = function() return 0 end,
    }
    _G.C_Bank = {
      CanUseBank = function(t) return canUse and usable[t] == true end,
      IsItemAllowedInBankType = function(t, loc)
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
    -- The client's GameTooltip, down to the calls a button's tooltip makes. What it holds is kept
    -- here, never on the fake.
    tip = { owner = nil, lines = {} }
    _G.GameTooltip = {
      SetOwner = function(_, owner) tip.owner, tip.lines = owner, {} end,
      AddLine = function(_, text) tip.lines[#tip.lines + 1] = text end,
      Show = function() end,
      Hide = function() tip.owner = nil end,
      IsOwned = function(_, owner) return tip.owner == owner end,
    }
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
    -- No route data (no Companion region payload): the carry list stays hidden.
    GC.SellRoute = { HereId = function() return nil end }
    GC.Data = { GetItemValue = function(id) return VALUE[id] and { mv = VALUE[id] } or nil end }
    GC.db = {}
    closedFor = {}
    GC.BuyCapEditor = {
      Open = function(anchor, opts) asked = { anchor = anchor, opts = opts } end,
      CloseFor = function(anchor) closedFor[anchor] = true end,
    }
    helper.loadModule("UI/BankRoute.lua", GC)
    helper.loadModule("UI/HoardFrame.lua", GC)
    helper.loadModule("UI/HoardRow.lua", GC)
    HF = GC.HoardFrame
  end)

  after_each(function()
    GC.ActivateLocale(nil)
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
    NAMES[1], VALUE[9] = "Bloom", nil
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The window: where it stands and when
  -- ---------------------------------------------------------------------------------------------

  it("stands beside the bank window with a followed group, its groups as rows, and goes with the bank", function()
    open()
    assert.is_true(windowUp())
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 4, 0 }, at(HF._frame))
    assert.equal(1, #W.state(HF._frame).points)
    assert.is_true(W.state(HF._frame).clamped)
    assert.equal("GoldCap", textOf(HF._frame.brand))
    -- By worth here, the most first: Herbs 4,700g, Ore 100g.
    assert.same({ "Herbs", "Ore" }, rowNames())
    assert.equal("YOUR GROUPS", textOf(HF._frame.groupsTitle))
    close()
    assert.is_false(windowUp())
  end)

  -- Most players follow no group: they see no window at all, and nothing is built or read for it.
  it("is not there at all when no group is followed: builds nothing and reads no slot", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    open()
    assert.is_nil(HF._frame)
    assert.equal(0, reads)
    bagsChanged()
    assert.is_nil(HF._frame)
    assert.equal(0, reads)
  end)

  it("hides once the last followed group is gone, and reads no slot for it", function()
    open()
    assert.is_true(windowUp())
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    reads = 0
    bagsChanged()
    assert.is_false(windowUp())
    assert.equal(0, reads)
  end)

  it("says so when none of the followed groups' items are here", function()
    bags = { [0] = { info(9, 20) } }
    open()
    assert.is_true(windowUp())
    assert.same({}, rowNames())
    assert.is_true(shown(HF._frame.empty))
    assert.equal("None of your groups' items are in your bags or this bank.", textOf(HF._frame.empty))
    assert.is_false(HF._frame.storeAll:IsEnabled())
    assert.is_false(HF._frame.takeAll:IsEnabled())
  end)

  it("shows nothing when neither bank can be used here, or neither has a tab", function()
    canUse = false
    open()
    assert.is_false(windowUp())
    close()
    canUse, tabs, charTabs = true, {}, {}
    open()
    assert.is_false(windowUp())
  end)

  -- Blizzard hangs the bank's tab buttons off the bank panel's right edge (BankFrame.lua,
  -- BankPanelMixin:RefreshBankTabs); the window starts past them (GC.BankRoute.BesideBankX).
  it("starts past the bank's tab buttons, their border included", function()
    function _G.BankFrame:GetRight() return 500 end
    local tab = W.CreateFrame("Button", nil, _G.BankPanel)
    function tab:GetRight() return 534 end -- 2 out from the edge, 32 wide
    open()
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 34 + 4 + 4, 0 }, at(HF._frame))
    tab:Hide()
    close()
    open()
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 4, 0 }, at(HF._frame))
  end)

  -- Bagnon shows Blizzard's window under a hidden parent (BagBrother's
  -- core/features/uiOverrides.lua): there is no window to stand beside, so the Hoard stands at the
  -- screen's left, as the bank card did with no bank window.
  it("stands at the screen's left when a bag addon keeps Blizzard's bank window out of sight", function()
    local hidden = W.CreateFrame("Frame")
    hidden:Hide()
    _G.BankFrame:SetParent(hidden)
    open()
    assert.is_true(windowUp())
    assert.same({ "LEFT", _G.UIParent, "LEFT", 20, 0 }, at(HF._frame))
  end)

  -- A TSM player brings 8 to 20 groups: the window stays on the screen, no taller than the room
  -- under its top, and the rest scrolls.
  it("stays on the screen with many groups: no taller than the room under its top, the rest scrolls", function()
    manyGroups(20)
    _G.BankFrame.GetTop = function() return 700 end
    open()
    local f = HF._frame
    assert.equal(700 - 80, f:GetHeight())
    local scroll, content = f.scroll, f.content
    assert.equal(content, scroll:GetScrollChild())
    assert.is_true(scroll:GetVerticalScrollRange() > 0)
    assert.equal(20, #rowNames())
    for _, r in ipairs(HF._rows) do
      if r:IsShown() then assert.equal(content, r:GetParent()) end
    end
    close()
    manyGroups(1)
    open()
    assert.is_true(f:GetHeight() < 700 - 80)
    assert.equal(0, scroll:GetVerticalScrollRange())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Closing it
  -- ---------------------------------------------------------------------------------------------

  -- The X hides the window for good (GC.db.hoard), and a small handle stays beside the bank window
  -- instead; a click on the handle brings the window back.
  it("closes to a handle beside the bank, remembered for the account, and the handle opens it again", function()
    open()
    press(HF._frame.close)
    assert.is_false(windowUp())
    assert.is_true(GC.Hoard.Closed(GC.db))
    assert.is_true(shown(HF._handle))
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 4, 0 }, at(HF._handle))
    close()
    assert.is_false(shown(HF._handle))
    open()
    assert.is_false(windowUp())
    assert.is_true(shown(HF._handle))
    press(HF._handle)
    assert.is_true(windowUp())
    assert.is_false(shown(HF._handle))
    assert.is_false(GC.Hoard.Closed(GC.db))
  end)

  it("stops a run when it is closed", function()
    landing = true
    open()
    press(row("Herbs").store)
    press(HF._frame.close)
    ticks()
    assert.equal(1, #used)
    assert.is_nil(HF.Running())
  end)

  -- A newer GoldCap's memory cannot be written: the X still hides the window for this session.
  it("closes for the session when a newer GoldCap saved the window's memory", function()
    GC.db.hoard = { v = GC.Hoard.VERSION + 1 }
    open()
    press(HF._frame.close)
    assert.is_false(windowUp())
    assert.is_true(shown(HF._handle))
    press(HF._handle)
    assert.is_true(windowUp())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The bank switch and the free slots
  -- ---------------------------------------------------------------------------------------------

  it("names the two banks as the bank window's tabs do, starts on the one it shows, and counts free slots", function()
    open()
    assert.equal("Bank", side(CHARACTER).label)
    assert.equal("Warband Bank", side(ACCOUNT).label)
    assert.equal(ACCOUNT, HF._bankType)
    -- The backpack's 20 slots hold 3, the reagent bag's 36 hold 1; the Warband Bank's tab holds 1
    -- of 98.
    assert.equal("Bags 52 free", helper.plain(textOf(HF._frame.freeBags)))
    assert.equal("Bank 97 free", helper.plain(textOf(HF._frame.freeBank)))
    choose(CHARACTER)
    assert.equal("Bank 97 free", helper.plain(textOf(HF._frame.freeBank)))
    charTabs = { 6, 7 }
    sizes[7] = 98
    bagsChanged()
    assert.equal("Bank 195 free", helper.plain(textOf(HF._frame.freeBank)))
  end)

  -- Bagnon keeps Blizzard's bank window on the character's bank for the whole visit and never calls
  -- SetTab: the switch is how its player reaches the Warband Bank.
  it("reaches the Warband Bank through its own switch while the bank window stays on the character's bank", function()
    showing = CHARACTER
    open()
    assert.equal(CHARACTER, HF._bankType)
    choose(ACCOUNT)
    assert.equal(ACCOUNT, HF._bankType)
    bagsChanged()
    assert.equal(ACCOUNT, HF._bankType)
    press(row("Herbs").store)
    press(row("Herbs").take)
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 2, 12, 1 } }, used)
  end)

  it("goes along when the bank window comes to show the other bank, over the switch's own choice", function()
    open()
    choose(CHARACTER)
    switchTo(CHARACTER)
    assert.equal(CHARACTER, HF._bankType)
    switchTo(ACCOUNT)
    assert.equal(ACCOUNT, HF._bankType)
    choose(CHARACTER)
    -- A reset that shows the same bank (a tab bought) leaves the choice as it is.
    switchTo(ACCOUNT)
    assert.equal(CHARACTER, HF._bankType)
  end)

  it("starts again on the bank the window shows at each open", function()
    showing = CHARACTER
    open()
    choose(ACCOUNT)
    close()
    open()
    assert.equal(CHARACTER, HF._bankType)
  end)

  -- On the session's first open BANKFRAME_OPENED can come before Blizzard's bank panel shows: the
  -- window answers no bank and the Hoard starts on the Warband Bank, then the panel's Reset from
  -- its OnShow brings it to the bank the window shows.
  it("on the first open, before the bank panel shows, starts on the Warband Bank and goes along once it shows", function()
    showing = nil
    open()
    assert.equal(ACCOUNT, HF._bankType)
    switchTo(CHARACTER)
    assert.equal(CHARACTER, HF._bankType)
    press(row("Herbs").store)
    assert.same({ { n = 5, 0, 1, nil, CHARACTER, false } }, used)
  end)

  it("disables the side of a bank with no tab or out of reach, and works with the other", function()
    tabs = {}
    open()
    assert.is_true(windowUp())
    assert.equal(CHARACTER, HF._bankType)
    assert.is_false(side(ACCOUNT):IsEnabled())
    assert.is_true(side(CHARACTER):IsEnabled())
    press(row("Herbs").store)
    assert.same({ { n = 5, 0, 1, nil, CHARACTER, false } }, used)
    close()
    tabs, charTabs, showing = { 12 }, {}, CHARACTER
    open()
    assert.equal(ACCOUNT, HF._bankType)
    assert.is_false(side(CHARACTER):IsEnabled())
  end)

  -- The panel resets from inside Blizzard's own work (a tab click, the window opening, twice as it
  -- opens): the window repaints once, on the next frame, so nothing of it runs in that call.
  it("repaints once on the next frame for a run of bank panel resets, not inside them", function()
    open()
    reads = 0
    local before = #timers
    showing = CHARACTER
    _G.BankPanel:Reset()
    _G.BankPanel:Reset()
    assert.equal(0, reads)
    assert.equal(ACCOUNT, HF._bankType)
    assert.equal(before + 1, #timers)
    nextFrame()
    assert.is_true(reads > 0)
    assert.equal(CHARACTER, HF._bankType)
  end)

  it("reads nothing when the bank panel resets with the bank closed", function()
    open()
    close()
    reads = 0
    local before = #timers
    switchTo(CHARACTER)
    assert.equal(before, #timers)
    assert.equal(0, reads)
    assert.is_false(windowUp())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- A group's row
  -- ---------------------------------------------------------------------------------------------

  it("draws a group as one row: its name, its play, its items' icons and counts, its worth and where it is", function()
    open()
    local herbs = row("Herbs")
    assert.equal("GATHER", textOf(herbs.chip.text))
    assert.is_true(shown(herbs.chip))
    -- Its items, the most worth first: Bloom of the second quality (600 here), then the first
    -- (220). Mycobloom has no stack here.
    assert.equal(5002, W.state(herbs.icons[1].icon).file)
    assert.equal("600", textOf(herbs.icons[1].count))
    assert.equal(5001, W.state(herbs.icons[2].icon).file)
    assert.equal("220", textOf(herbs.icons[2].count))
    assert.is_false(shown(herbs.icons[3].icon))
    assert.is_false(shown(herbs.more))
    assert.equal(GC.Util.Money(4700 * 10000), textOf(herbs.worth))
    -- The bar along its bottom: 220 of 820 in the bags.
    local track = herbs.bankBar:GetWidth()
    assert.equal(math.floor(track * 220 / 820 + 0.5), herbs.bagsBar:GetWidth())
    -- The two moves, as icons.
    assert.is_true(shown(herbs.store))
    assert.is_true(shown(herbs.take))
    assert.is_true(shown(herbs.store.icon))
  end)

  it("names what the next press moves in each move's tooltip", function()
    open()
    local herbs, ore = row("Herbs"), row("Ore")
    W.state(herbs.store).scripts.OnEnter(herbs.store)
    assert.same({ "Store", "Bloom ×200 (2 left)" }, tip.lines)
    W.state(herbs.take).scripts.OnEnter(herbs.take)
    assert.same({ "Take out", "Bloom ×600 (1 left)" }, tip.lines)
    -- Nothing of Ore in the Warband Bank: Take out stays in its place, saying so, disabled.
    W.state(ore.take).scripts.OnEnter(ore.take)
    assert.same({ "Take out", "Nothing to move" }, tip.lines)
    assert.is_true(shown(ore.take))
    assert.is_false(ore.take:IsEnabled())
  end)

  it("stores the group's whole list on one press: the first inside the click, the rest from timers", function()
    landing = true
    open()
    local store = row("Herbs").store
    W.state(store).scripts.OnEnter(store)
    press(store)
    -- Inside the click: the first stack, and no other before a timer runs.
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
    assert.equal(store, HF.Running())
    -- The tooltip under the cursor names the next stack.
    assert.same({ "Store", "Bloom ×20 (1 left)" }, tip.lines)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 0, 2, nil, ACCOUNT, false } }, used)
    assert.is_nil(HF.Running())
    bagsChanged()
    -- Never put to sleep by the press; the repaint after the last move says there is nothing left.
    assert.is_true(shown(store))
    assert.is_false(store:IsEnabled())
    assert.same({ "Store", "Nothing to move" }, tip.lines)
  end)

  it("takes the group's whole list out on one press", function()
    landing = true
    bags[12][2] = info(1, 30)
    open()
    -- The bank's Bloom of the first quality first, the biggest stack first.
    press(row("Herbs").take)
    assert.same({ { n = 2, 12, 2 } }, used)
    ticks()
    assert.same({ { n = 2, 12, 2 }, { n = 2, 12, 1 } }, used)
    bagsChanged()
    assert.is_false(row("Herbs").take:IsEnabled())
  end)

  it("stops at a second press, which moves nothing itself, and starts again at the next", function()
    landing = true
    bags[0][4] = info(6, 5)
    open()
    press(row("Herbs").store)
    press(row("Herbs").store)
    assert.is_nil(HF.Running())
    ticks()
    assert.equal(1, #used)
    bagsChanged()
    press(row("Herbs").store)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 0, 2, nil, ACCOUNT, false },
      { n = 5, 0, 4, nil, ACCOUNT, false } }, used)
  end)

  it("stops at another button's press, which starts its own", function()
    landing = true
    open()
    press(row("Herbs").store)
    press(row("Ore").store)
    assert.equal(row("Ore").store, HF.Running())
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 5, 1, nil, ACCOUNT, false } }, used)
  end)

  it("stops when the bank closes, and when the switch comes to the other bank", function()
    landing = true
    open()
    press(row("Herbs").store)
    close()
    ticks()
    assert.equal(1, #used)
    open()
    press(row("Herbs").store)
    assert.equal(2, #used)
    choose(CHARACTER)
    assert.is_nil(HF.Running())
    ticks()
    assert.equal(2, #used)
    assert.equal(CHARACTER, HF._bankType)
  end)

  it("skips a stack whose slot no longer holds it when its turn comes", function()
    landing = true
    bags[0][4] = info(6, 5)
    open()
    press(row("Herbs").store)
    bags[0][2] = info(9, 20)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 0, 4, nil, ACCOUNT, false } }, used)
  end)

  -- A move the server refused (a full bank): the stack stays in its slot. The run stops without a
  -- word (the game says why itself), the press after it still moves in its click, and the stack is
  -- offered again once nothing showed it moved in time.
  it("stops quietly when a move stays, and offers the stack again when nothing moved in time", function()
    open()
    local store = row("Herbs").store
    press(store)
    assert.equal(1, #used)
    assert.equal(15, ticks())
    assert.equal(1, #used)
    assert.is_false(HF._Machine():IsRunning())
    press(store)
    assert.equal(2, #used)
    ticks()
    assert.is_false(store:IsEnabled())
    for i = #timers, 1, -1 do
      if timers[i].seconds == GC.BankRoute.SETTLE_SECONDS then table.remove(timers, i).fn() end
    end
    assert.is_true(store:IsEnabled())
    press(store)
    assert.equal(3, #used)
  end)

  it("keeps the keep count in the bags: a press moves only what is over it", function()
    landing = true
    GC.BankGroups.SetKeep(GC.db, "Herbs", 20)
    open()
    press(row("Herbs").store)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
  end)

  -- The bank route's own guards, reused: the same call equips gear with no bank open (which binds
  -- it) and sells to an open vendor.
  it("moves nothing once the bank has closed, while a vendor is open, or with the bank out of reach", function()
    open()
    local store = row("Herbs").store
    close()
    press(store)
    assert.same({}, used)
    open()
    store = row("Herbs").store
    _G.MerchantFrame:Show()
    press(store)
    assert.same({}, used)
    _G.MerchantFrame:Hide()
    canUse = false
    press(store)
    assert.same({}, used)
  end)

  it("moves nothing while a spell waits for an item target", function()
    open()
    targeting = true
    press(row("Herbs").store)
    press(row("Herbs").take)
    assert.same({}, used)
    targeting = false
    press(row("Herbs").store)
    assert.equal(1, #used)
  end)

  it("never offers a stack still refundable to the Warband Bank, and refuses it at the press too", function()
    refundable["0:1"], refused["0:2"] = true, true
    open()
    assert.is_false(row("Herbs").store:IsEnabled())
    refundable["0:1"], refused["0:2"] = nil, nil
    bagsChanged()
    refundable["0:1"] = true
    press(row("Herbs").store)
    assert.same({ { n = 5, 0, 2, nil, ACCOUNT, false } }, used)
  end)

  -- The row is pressed again and again in one spot: nothing in the window moves between two
  -- presses, or while a press runs, an opened row's lines included, and no button is disabled
  -- before its call.
  it("keeps every row and button where it is while a press runs, and disables nothing before its call", function()
    bags[0][4] = info(6, 5)
    open()
    openRow("Herbs")
    local f, herbs, ore = HF._frame, row("Herbs"), row("Ore")
    local function snapshot()
      return {
        width = f:GetWidth(), height = f:GetHeight(), content = f.content:GetHeight(), herbs = at(herbs),
        herbsH = herbs:GetHeight(), ore = at(ore), store = at(herbs.store), take = at(herbs.take),
        oreStore = at(ore.store), storeAll = at(f.storeAll), takeAll = at(f.takeAll), worth = at(herbs.worth),
        icon = at(herbs.icons[1].icon),
      }
    end
    local before = snapshot()
    local enabledAtCall = {}
    local use = _G.C_Container.UseContainerItem
    _G.C_Container.UseContainerItem = function(...)
      enabledAtCall[#enabledAtCall + 1] = herbs.store:IsEnabled()
      return use(...)
    end
    landing = true
    press(herbs.store)
    assert.same(before, snapshot())
    while true do
      local due
      for k, t in ipairs(timers) do
        if t.seconds == GC.VendorPress.STEP then due = k break end
      end
      if not due then break end
      table.remove(timers, due).fn()
      bagsChanged()
      assert.same(before, snapshot())
    end
    assert.same({ true, true, true }, enabledAtCall)
    assert.is_false(herbs.store:IsEnabled())
    assert.same(before, snapshot())
  end)

  -- A group the player is pressing must not leave the list under the cursor: once listed it stays
  -- listed until the bank closes, with nothing left to move.
  it("keeps a group's row while the bank is open once it has shown, even with nothing left to move", function()
    landing = true
    -- Ore keeps 100 in the bags: once its 30 in the Warband Bank are out, it has nothing to move.
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100 } }
    bags[12][2] = info(3, 30)
    open()
    local ore = row("Ore")
    local before = at(ore)
    press(ore.take)
    ticks()
    bagsChanged()
    assert.is_false(ore.take:IsEnabled())
    assert.equal(ore, row("Ore"))
    assert.same(before, at(ore))
    assert.is_false(shown(HF._frame.fold))
    close()
    open()
    assert.is_nil(row("Ore"))
  end)

  -- A newer GoldCap's keep counts cannot be read here, so Store would ignore them: no Store
  -- anywhere (each keeps its place) and no keep count; Take out still works.
  it("offers neither Store nor the keep count when a newer GoldCap saved the keep counts", function()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION + 1 }
    open()
    local herbs = row("Herbs")
    assert.is_false(shown(herbs.store))
    assert.is_false(shown(HF._frame.storeAll))
    assert.is_true(shown(herbs.take))
    openRow("Herbs")
    assert.is_false(shown(row("Herbs").keep))
    press(herbs.store)
    assert.same({}, used)
    press(herbs.take)
    assert.same({ { n = 2, 12, 1 } }, used)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- An opened row
  -- ---------------------------------------------------------------------------------------------

  it("opens a row on a click: every item with where it is, the keep count, and what stays; one at a time", function()
    refundable["0:2"] = true
    open()
    assert.is_false(shown(row("Herbs").keep))
    openRow("Herbs")
    local herbs = row("Herbs")
    assert.is_true(shown(herbs.keep))
    assert.equal("Keep in bags: 0 of each", herbs.keep.label)
    -- Its items by name: Bloom of each quality, each with its count in the bags and the bank
    -- chosen.
    assert.same({ "220 in bags, 0 in the Warband Bank", "0 in bags, 600 in the Warband Bank" }, lines(herbs, "items"))
    assert.same({ "Stays in bags: Bloom ×20, can still be refunded" }, lines(herbs, "stays"))
    openRow("Ore")
    assert.is_false(shown(row("Herbs").keep))
    assert.is_true(shown(row("Ore").keep))
    openRow("Ore")
    assert.is_false(shown(row("Ore").keep))
    -- A press on its buttons does not open it.
    press(row("Herbs").take)
    assert.is_false(shown(row("Herbs").keep))
  end)

  it("names the bank chosen in an opened row, and what that bank refuses", function()
    bags[5][2] = info(3, 7)
    refusedHere["5:2"] = true
    showing = CHARACTER
    open()
    openRow("Ore")
    assert.same({ "57 in bags, 0 in your bank" }, lines(row("Ore"), "items"))
    assert.same({ "Stays in bags: Bismuth ×7, your bank does not take it" }, lines(row("Ore"), "stays"))
  end)

  it("sets the keep count from the opened row, remembered for the account, and repaints", function()
    open()
    openRow("Herbs")
    local keep = row("Herbs").keep
    press(keep)
    assert.equal(keep, asked.anchor)
    assert.equal("How many of each item in Herbs to keep in your bags?", asked.opts.title)
    assert.equal("0", asked.opts.text)
    assert.equal(30, asked.opts.read("30"))
    assert.is_nil(asked.opts.read("lots"))
    asked.opts.onCommit(30)
    assert.same({ v = GC.BankGroups.VERSION, groups = { Herbs = 30 } }, GC.db.bankKeep)
    local herbs = row("Herbs")
    assert.equal("Keep in bags: 30 of each", herbs.keep.label)
    -- 220 Bloom: the 200 would leave 20, under 30; the 20 leaves 200.
    W.state(herbs.store).scripts.OnEnter(herbs.store)
    assert.same({ "Store", "Bloom ×20 (1 left)" }, tip.lines)
    asked.opts.onCommit(300)
    assert.is_false(row("Herbs").store:IsEnabled())
  end)

  it("closes the keep popup with the bank", function()
    open()
    openRow("Herbs")
    local keep = row("Herbs").keep
    press(keep)
    close()
    assert.is_true(closedFor[keep])
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Folders and the fold line
  -- ---------------------------------------------------------------------------------------------

  it("folds the subgroups of one group on goldcap.gg into a folder, closed until opened, and remembers it", function()
    folders()
    open()
    local gathering = row("Gathering", "folder")
    assert.is_truthy(gathering)
    assert.equal("2 groups", textOf(gathering.sub))
    assert.is_nil(row("Herbs"))
    press(gathering.head)
    assert.is_true(GC.Hoard.FolderOpen(GC.db, "gathering"))
    -- Its groups under it, by their short names, indented.
    local herbs, ore = row("Herbs"), row("Ore")
    assert.is_truthy(herbs)
    assert.is_truthy(ore)
    assert.is_true(at(herbs)[4] > at(row("Gathering", "folder"))[4])
    press(row("Gathering", "folder").head)
    assert.is_nil(row("Herbs"))
    assert.is_false(GC.Hoard.FolderOpen(GC.db, "gathering"))
  end)

  it("stores every listed group of a folder on one press of its Store", function()
    landing = true
    folders()
    open()
    press(row("Gathering", "folder").store)
    ticks()
    -- Herbs' two Bloom stacks and Ore's Bismuth, group by group.
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 0, 2, nil, ACCOUNT, false },
      { n = 5, 5, 1, nil, ACCOUNT, false } }, used)
  end)

  -- A folder's key is its parent's, which a followed top group may share: two rows, and opening the
  -- group does not open the folder.
  it("tells a folder from a top group with the same key", function()
    folders(true)
    open()
    local folder, group = row("Gathering", "folder"), row("Gathering", "group")
    assert.is_truthy(folder)
    assert.is_truthy(group)
    press(group.head)
    assert.is_true(shown(row("Gathering", "group").keep))
    assert.is_false(shown(row("Gathering", "folder").keep))
    assert.is_false(GC.Hoard.FolderOpen(GC.db, "gathering"))
    assert.is_nil(row("Herbs"))
  end)

  -- A group with nothing to move here (all of it kept in the bags) is one line among others; the
  -- line opens them below it, so their keep count can still be changed.
  it("folds the groups with nothing to move into one line, which opens them below it", function()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100 } }
    open()
    assert.is_nil(row("Ore"))
    local fold = HF._frame.fold
    assert.is_true(shown(fold))
    assert.equal("1 more group has nothing to move at this bank", helper.plain(textOf(fold.text)))
    local foldAt = at(fold)
    press(fold)
    assert.same(foldAt, at(fold))
    local ore = row("Ore")
    assert.is_truthy(ore)
    assert.is_true(at(ore)[5] < foldAt[5])
    press(fold)
    assert.is_nil(row("Ore"))
  end)

  it("counts the folded groups on the fold line", function()
    bags[12] = {}
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100, Herbs = 9999 } }
    open()
    assert.equal("2 more groups have nothing to move at this bank", helper.plain(textOf(HF._frame.fold.text)))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Store all and Take all out
  -- ---------------------------------------------------------------------------------------------

  it("stores every group on one press of Store all, and takes them all out with Take all out", function()
    landing = true
    open()
    local storeAll, takeAll = HF._frame.storeAll, HF._frame.takeAll
    assert.equal("Store all", storeAll.label)
    assert.equal("Take all out", takeAll.label)
    press(storeAll)
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 0, 2, nil, ACCOUNT, false },
      { n = 5, 5, 1, nil, ACCOUNT, false } }, used)
    bagsChanged()
    assert.is_false(storeAll:IsEnabled())
    used = {}
    press(takeAll)
    ticks()
    assert.equal(4, #used)
    for _, call in ipairs(used) do assert.equal(2, call.n) end
    bagsChanged()
    assert.is_false(takeAll:IsEnabled())
  end)

  it("keeps each group's keep count on Store all, and stops at a second press", function()
    landing = true
    GC.BankGroups.SetKeep(GC.db, "Herbs", 20)
    open()
    press(HF._frame.storeAll)
    press(HF._frame.storeAll)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
    bagsChanged()
    press(HF._frame.storeAll)
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 5, 1, nil, ACCOUNT, false } }, used)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- What later parts of the window build on
  -- ---------------------------------------------------------------------------------------------

  -- Sections: the tiles above the groups, the carry list and the footer below them, each built once
  -- in a frame of its own and painted with what it needs.
  it("paints its sections in their places with what they need, and works with none", function()
    local built, ctxs, frames = {}, {}, {}
    local function section(name, h)
      return {
        build = function(parent) built[#built + 1] = { name = name, parent = parent } end,
        paint = function(f, ctx)
          ctxs[name], frames[name] = ctx, f
          return h
        end,
      }
    end
    HF.AddSection("footer", section("footer", 20))
    HF.AddSection("tiles", section("tiles", 40))
    HF.AddSection("carry", section("carry", 0))
    open()
    bagsChanged()
    assert.equal(3, #built)
    local tiles, footer = ctxs.tiles, ctxs.footer
    assert.equal(ACCOUNT, tiles.bankType)
    assert.same({ [CHARACTER] = true, [ACCOUNT] = true }, tiles.usable)
    assert.is_false(tiles.running)
    assert.same({ "Herbs", "Ore" }, { tiles.groups[1].name, tiles.groups[2].name })
    assert.equal(60000, tiles.valueOf(2))
    assert.equal(HF._frame.content:GetWidth(), tiles.width)
    -- The tiles first, then the groups, then the carry list (empty: not shown), then the footer.
    assert.equal(footer.bankType, tiles.bankType)
    local tilesY, titleY = -at(frames.tiles)[5], -at(HF._frame.groupsTitle)[5]
    local footerY, oreY = -at(frames.footer)[5], -at(row("Ore"))[5]
    assert.equal(0, tilesY)
    assert.is_true(titleY >= 40)
    assert.is_true(footerY > oreY)
    assert.is_false(shown(frames.carry))
    assert.is_true(shown(frames.footer))
    -- Each built once, in a frame of its own in the scroll.
    for _, b in ipairs(built) do assert.equal(HF._frame.content, b.parent:GetParent()) end
    press(row("Herbs").store)
    assert.is_true(ctxs.tiles.running)
  end)

  -- A section's own press (the carry list into the Warband Bank) names its bank; the rest of the
  -- run is the window's: one machine, one run.
  it("presses through Press with the switch's bank, or the one a section names", function()
    showing = CHARACTER
    open()
    local mine = W.CreateFrame("Button")
    HF.Press(mine, { { itemID = 1, bag = 0, slot = 1, count = 200, link = "item:1" } }, true, ACCOUNT)
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
    assert.equal(mine, HF.Running())
    -- Another press stops it and starts its own.
    press(row("Herbs").take)
    assert.same({ n = 2, 6, 1 }, used[2])
    assert.equal(row("Herbs").take, HF.Running())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Words
  -- ---------------------------------------------------------------------------------------------

  -- Labels wrap and buttons are as wide as their words: a long name in a long language grows the
  -- row or the window instead of being cut.
  it("never cuts a label, in any language", function()
    _G.BANK, _G.ACCOUNT_BANK_PANEL_TITLE = "Persönliches Bankfach des Charakters", "Kriegsmeutenbank der Kriegsmeute"
    NAMES[1] = "Verzauberte Blütenblätter der leuchtenden Hochenblume"
    bags[0][1] = info(1, 200)
    refundable["0:2"], refusedHere["0:2"] = true, true
    bags[5][2] = info(3, 7)
    refused["5:2"], refusedHere["5:2"] = true, true
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Cloth = 10 } }
    bags[0][4] = info(4, 3)
    for _, code in ipairs(helper.localeCodes()) do
      helper.loadModule("Locale/" .. code .. ".lua", GC)
    end
    local function fits(button, what)
      assert.is_true(button:GetWidth() >= button.text:GetUnboundedStringWidth(), what .. " " .. tostring(button.label))
    end
    for _, code in ipairs(helper.localeCodes()) do
      for _, bankType in ipairs({ ACCOUNT, CHARACTER }) do
        GC.ActivateLocale(code)
        showing = bankType
        open()
        openRow("Herbs")
        local f = HF._frame
        local inner = f.content:GetWidth()
        assert.is_true(f:GetWidth() >= 360, code)
        for _, b in ipairs(f.choice.sides) do
          fits(b, code)
          assert.is_true(inner >= b:GetWidth(), code)
        end
        fits(f.storeAll, code)
        fits(f.takeAll, code)
        assert.is_true(inner >= f.choice:GetWidth(), code)
        for _, fs in ipairs({ f.freeBags, f.freeBank }) do
          assert.is_true(W.state(fs).wordWrap == false, code)
        end
        local fold = f.fold
        assert.is_true(shown(fold), code)
        assert.is_true(W.state(fold.text).wordWrap ~= false, code)
        assert.is_true(inner >= fold:GetWidth(), code)
        for _, r in ipairs(HF._rows) do
          if r:IsShown() then
            assert.is_true(W.state(r.name).wordWrap ~= false, code)
            assert.is_true(r.name:GetWidth() >= 40, code)
            if r.chip:IsShown() then
              assert.is_true(r.chip:GetWidth() >= r.chip.text:GetUnboundedStringWidth(), code .. " " .. textOf(r.chip.text))
            end
            if r.keep:IsShown() then
              fits(r.keep, code)
              assert.is_true(inner >= r.keep:GetWidth(), code)
            end
            for _, fs in ipairs(r.stays) do
              if fs:IsShown() then assert.is_true(W.state(fs).wordWrap ~= false, code) end
            end
            for _, item in ipairs(r.items) do
              if item.counts:IsShown() then assert.is_true(W.state(item.counts).wordWrap ~= false, code) end
            end
          end
        end
        close()
      end
    end
  end)
end)
