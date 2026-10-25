local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/HoardFrame.lua, UI/HoardRow.lua and UI/HoardList.lua: GoldCap Hoard, the window beside
-- Blizzard's bank window. Its followed groups as rows and folders, with Store and Take out on each,
-- Store all and Take all out over every group, the bank switch, the search row over many groups,
-- the checkboxes with the selection bar, a run's cast bar with Stop, and the sections later tasks
-- paint into it. The real Theme
-- and kit, the real group rules (from a Companion file), the real plan (Core/BankGroups.lua) and
-- rows (Core/Hoard.lua), the real press machine (Core/VendorPress.lua) and the real bank route
-- (UI/BankRoute.lua), whose reader, move function and guards the window uses; the bags, both banks,
-- the bank window, the tooltip and the client calls are faked, shaped as the client's.
describe("GoldCap Hoard window", function()
  local GC, HF, restore, saved, bags, sizes, used, timers, canUse, tabs, refundable, refused, reads, asked
  local closedFor, showing, usable, charTabs, refusedHere, targeting, landing, tip, arrivals
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
  -- A free-slot chip as the player reads it: its words, its number and the words after it.
  local function freeText(chip)
    local rest = textOf(chip.rest) or ""
    return helper.plain(textOf(chip.words)) .. " " .. textOf(chip.num) .. (rest ~= "" and (" " .. rest) or "")
  end
  local function shown(widget) return widget ~= nil and widget:IsShown() end
  local function windowUp() return HF._frame ~= nil and HF._frame:IsShown() end
  local function press(button) W.state(button).scripts.OnClick(button) end
  local function at(widget) return W.state(widget).points[1] end

  -- A shown row by the name it shows, and of a kind when asked; or by its group's key.
  local function row(name, kind)
    for _, r in ipairs(HF._rows) do
      if r:IsShown() and textOf(r.name) == name and (kind == nil or r.data.kind == kind) then return r end
    end
  end
  local function rowByKey(key)
    for _, r in ipairs(HF._rows) do
      if r:IsShown() and r.data.kind == "group" and r.data.key == key then return r end
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

  -- The search row over many groups and the selection bar (UI/HoardList.lua).
  local function search() return HF._frame.search end
  local function bar() return HF._frame.selection end
  local function filterSide(key)
    for _, s in ipairs(search().filter.sides) do
      if s.filter == key then return s end
    end
  end
  -- The player types into the search box: the client changes its text and runs OnTextChanged with
  -- userInput true.
  local function typeInto(box, text)
    W.state(box).text = text
    W.state(box).scripts.OnTextChanged(box, true)
  end
  local function checkOf(name, kind) press(row(name, kind).check) end
  local function plainText(fs) return helper.plain(textOf(fs) or "") end
  -- Which kit glyph a texture draws: its name in the atlas, from its coordinates.
  local function glyph(texture)
    local coords = W.state(texture).texCoord
    for name in pairs(GC.Kit.Icons.index) do
      if coords and coords[1] == GC.Theme.IconCoords(name) and select(3, GC.Theme.IconCoords(name)) == coords[3] then
        return name
      end
    end
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
  -- BAG_UPDATE_DELAYED, and the frame after it, where the window paints.
  local function bagsChanged()
    GC.BankRoute.OnBagsChanged()
    nextFrame()
  end

  -- The server's answer to the moves sent so far (with `landing`): each slot empties (false keeps
  -- the bag's size) and its stack lands at the end of the bags, the character's bank tab or the
  -- Warband Bank's, as the call named them.
  local function land()
    for _, a in ipairs(arrivals) do
      bags[a.bag][a.slot] = false
      bags[a.into][#bags[a.into] + 1] = a.stack
    end
    arrivals = {}
  end

  -- The settle timers armed so far (the route's SETTLE_SECONDS): what is still on its way is given
  -- up, and the window paints on the frame after.
  local function settle()
    for i = #timers, 1, -1 do
      if timers[i].seconds == GC.BankRoute.SETTLE_SECONDS then table.remove(timers, i).fn() end
    end
    nextFrame()
  end

  -- The press machine's own timers (Core/VendorPress.lua's STEP), first armed first, until none is
  -- left, the server answering before each, then the frame after the last, where the window paints
  -- the run's end; answers how many ran. The settle timers stay.
  local function ticks()
    local n = 0
    while true do
      local due
      for k, t in ipairs(timers) do
        if t.seconds == GC.VendorPress.STEP then due = k break end
      end
      if not due then
        nextFrame()
        return n
      end
      land()
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
    landing, arrivals = false, {}
    -- Measured as the client measures text (spec/support/wow_frames.lua): the rows pack a name, a
    -- chip, icons and a worth on one line.
    W.CLIENT_METRICS = true
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
      -- With `landing`, the server takes each move: the slot locks at once, as the client locks a
      -- slot whose item is on its way, and the stack arrives at the server's answer (land).
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
      ClearAllPoints = function() end,
      SetPoint = function(_, ...) tip.point = { ... } end,
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
    helper.loadModule("UI/HoardList.lua", GC)
    HF = GC.HoardFrame
  end)

  after_each(function()
    W.CLIENT_METRICS = false
    GC.ActivateLocale(nil)
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
    NAMES[1], VALUE[9] = "Bloom", nil
    for id = 21, 25 do NAMES[id], VALUE[id] = nil, nil end
    for id = 101, 120 do NAMES[id], VALUE[id] = nil, nil end
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

  -- Most players follow no group yet: the window stands at the bank all the same and says where
  -- groups come from, with no heading, legend or move buttons, and reads no slot for groups.
  it("stands at the bank with no followed group and says where groups come from", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    open()
    assert.is_true(windowUp())
    assert.same({}, rowNames())
    assert.is_true(shown(HF._frame.empty))
    assert.equal("You follow no groups yet. Follow some on goldcap.gg under Groups, and the GoldCap Companion brings them here: what each holds in your bags and this bank, to store or take out in one press.", textOf(HF._frame.empty))
    for _, key in ipairs({ "groupsTitle", "storeAll", "takeAll", "fold" }) do assert.is_false(shown(HF._frame[key]), key) end
    assert.equal(0, reads)
    bagsChanged()
    assert.is_true(windowUp())
    assert.equal(0, reads)
  end)

  it("says where groups come from once the last followed group is gone, and reads no slot for it", function()
    open()
    assert.is_true(windowUp())
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    reads = 0
    bagsChanged()
    assert.is_true(windowUp())
    assert.same({}, rowNames())
    assert.equal("You follow no groups yet. Follow some on goldcap.gg under Groups, and the GoldCap Companion brings them here: what each holds in your bags and this bank, to store or take out in one press.", textOf(HF._frame.empty))
    assert.is_false(shown(HF._frame.storeAll))
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

  -- The groups' items are all in the other bank: the line names it, so the player knows where to
  -- switch; there they show.
  it("names the other bank when only that one holds the followed groups' items", function()
    bags = { [0] = { info(9, 20) }, [6] = { info(2, 40) }, [12] = {} }
    open()
    assert.equal(ACCOUNT, HF._bankType)
    assert.same({}, rowNames())
    assert.equal("None of your groups' items are in your bags or this bank. Bank holds some of them: pick it at the top.",
      textOf(HF._frame.empty))
    choose(CHARACTER)
    assert.equal(CHARACTER, HF._bankType)
    assert.same({ "Herbs" }, rowNames())
    assert.is_false(shown(HF._frame.empty))
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

  -- The window stands at the bank with no followed group too, so closed, its handle does.
  it("keeps its handle beside the bank with no followed group", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    GC.Hoard.SetClosed(GC.db, true)
    open()
    assert.is_false(windowUp())
    assert.is_true(shown(HF._handle))
    assert.equal(0, reads)
    press(HF._handle)
    assert.is_true(windowUp())
    assert.is_false(shown(HF._handle))
  end)

  -- A keep count asked from a row goes when the list is redrawn under it or the window closes: the
  -- row may show another group by then.
  it("closes the keep popup on the X, on a row's click and on the fold line's", function()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100 } }
    open()
    openRow("Herbs")
    local keep = row("Herbs").keep
    press(keep)
    assert.equal(keep, asked.anchor)
    press(HF._frame.fold)
    assert.is_true(closedFor[keep])
    closedFor = {}
    openRow("Herbs")
    assert.is_true(closedFor[keep])
    closedFor = {}
    press(HF._frame.close)
    assert.is_true(closedFor[keep])
  end)

  -- The same for every other click that redraws the list: the bank switch, a search, the filter,
  -- the sort and a checkbox.
  it("closes the keep popup on the bank switch, a search, the filter, the sort and a checkbox", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    open()
    openRow("Group 01")
    local keep = row("Group 01").keep
    press(keep)
    assert.equal(keep, asked.anchor)
    local clicks = {
      search = function() typeInto(search().box, "Group") end,
      filter = function() press(filterSide("all")) end,
      sort = function() press(search().sort) end,
      check = function() checkOf("Group 02") end,
      switch = function() choose(CHARACTER) end,
    }
    for _, name in ipairs({ "search", "filter", "sort", "check", "switch" }) do
      closedFor = {}
      clicks[name]()
      assert.is_true(closedFor[keep], name)
    end
  end)

  it("names itself Hoard in the player's language beside the brand, and on its handle", function()
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
    GC.ActivateLocale("ruRU")
    open()
    assert.equal("GoldCap", textOf(HF._frame.brand))
    assert.equal("Клад", textOf(HF._frame.title))
    press(HF._frame.close)
    assert.equal("Клад", textOf(HF._handle.text))
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
    assert.equal("Bags 52 free", freeText(HF._frame.freeBags))
    assert.equal("Bank 97 free", freeText(HF._frame.freeBank))
    choose(CHARACTER)
    assert.equal("Bank 97 free", freeText(HF._frame.freeBank))
    charTabs = { 6, 7 }
    sizes[7] = 98
    bagsChanged()
    assert.equal("Bank 195 free", freeText(HF._frame.freeBank))
  end)

  -- Bagnon keeps Blizzard's bank window on the character's bank for the whole visit and never calls
  -- SetTab: the switch is how its player reaches the Warband Bank.
  -- Side by side in the bank window's own order, its tabs' (BankFrame.lua's GenerateBankTypeTabs):
  -- the character's bank, then the Warband Bank.
  it("orders the switch as the bank window's tabs: the character's bank, then the Warband Bank", function()
    open()
    local sides = HF._frame.choice.sides
    assert.same({ CHARACTER, ACCOUNT }, { sides[1].bankType, sides[2].bankType })
    assert.same({ "LEFT", sides[1], "RIGHT", 2, 0 }, at(sides[2]))
  end)

  -- As the approved board draws them: "Hoard" in Fira Sans SemiBold, the bank not chosen in the
  -- second text colour in a ringed track, the free slots with the kit's glyphs and the number in the
  -- mono face, Store all and Take all out quiet, and everything on the right 12 in from the edge,
  -- the rows keeping the board's 336 beside the scroll's gutter.
  it("draws the header, the switch, the free slots and the buttons over the groups as the board does", function()
    open()
    local f, T, K = HF._frame, GC.Theme, GC.Kit.Tokens.color
    local function same(c, fs, what) assert.same({ c[1], c[2], c[3], c[4] or 1 }, W.state(fs).color, what) end
    assert.equal("Hoard", textOf(f.title))
    assert.equal(T.FONT_TEXT_SEMI, W.state(f.title).font[1])
    assert.equal(382, f:GetWidth())
    assert.equal(336, f.content:GetWidth())
    assert.equal(336, row("Herbs"):GetWidth())
    assert.same({ "TOPRIGHT", f, "TOPLEFT", 382 - 12 }, { unpack(at(f.close), 1, 4) })
    assert.same({ "RIGHT", f, "TOPLEFT", 382 - 12 }, { unpack(at(f.freeBank), 1, 4) })
    same(K.text2, side(CHARACTER).text, "the bank not chosen")
    same(K.onGold, side(ACCOUNT).text, "the bank chosen")
    assert.is_true(shown(f.choice.edge))
    same(K.text2, f.freeBags.words)
    same(K.text1, f.freeBags.num)
    same(K.text3, f.freeBags.rest)
    assert.equal(T.FONT_UI, W.state(f.freeBags.num).font[1])
    assert.same({ T.IconCoords("bag") }, W.state(f.freeBags.icon).texCoord)
    assert.same({ T.IconCoords("bank") }, W.state(f.freeBank.icon).texCoord)
    for _, b in ipairs({ f.storeAll, f.takeAll }) do
      same(K.text2, b.text, b.label)
      assert.equal(0, W.state(b.bg).vertex[4])
      assert.is_true(shown(b.ring))
    end
  end)

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

  it("wears the kit's tray arrows on Store and Take out, and its pencil on the keep count", function()
    open()
    openRow("Herbs")
    local herbs, T = row("Herbs"), GC.Theme
    assert.same({ T.IconCoords("arrowDown") }, W.state(herbs.store.icon).texCoord)
    assert.same({ T.IconCoords("arrowUp") }, W.state(herbs.take.icon).texCoord)
    assert.same({ T.IconCoords("pencil") }, W.state(herbs.keep.pencil).texCoord)
    assert.equal("RIGHT", at(herbs.keep.pencil)[1])
    assert.is_true(herbs.keep:GetWidth() >= herbs.keep.text:GetUnboundedStringWidth() + 8 + 2 * 5)
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
    assert.equal("group:Herbs:in", HF.Running())
    assert.equal(store, select(2, HF.Running()))
    -- The button is Stop now, and its tooltip under the cursor says what a press of it stops.
    assert.same({ "Stop moving", "Moving to Warband Bank" }, tip.lines)
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
    assert.equal("group:Ore:in", HF.Running())
    assert.equal(row("Ore").store, select(2, HF.Running()))
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 5, 1, nil, ACCOUNT, false } }, used)
  end)

  -- Rows are pooled by place: a folder opened mid-run draws another group on the running row's
  -- widget. A run is known by what it moves, so a press there is that group's own.
  it("knows a run by what it moves, not by the row's widget it was pressed on", function()
    landing = true
    folders()
    open()
    local widget = row("Linen").store
    press(widget)
    assert.equal("group:linen:in", HF.Running())
    press(row("Gathering", "folder").head)
    assert.equal(widget, row("Herbs").store)
    assert.equal("group:linen:in", HF.Running())
    assert.equal(row("Linen").store, select(2, HF.Running()))
    press(widget)
    assert.equal("group:herbs:in", HF.Running())
    assert.equal(widget, select(2, HF.Running()))
    assert.same({ { n = 5, 0, 3, nil, ACCOUNT, false }, { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
    -- Store all and Take all out are runs of their own too.
    assert.equal("all:in", HF._frame.storeAll.runId)
    assert.equal("all:out", HF._frame.takeAll.runId)
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
    settle()
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

  it("moves nothing from a locked slot", function()
    open()
    local store = row("Herbs").store
    bags[0][1], bags[0][2] = info(1, 200, { isLocked = true }), info(1, 20, { isLocked = true })
    press(store)
    assert.same({}, used)
    assert.is_false(HF._Machine():IsRunning())
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
    -- Painted while the first stack is on its way (its slot locked, the window waiting for it) as
    -- well as after each landing.
    bagsChanged()
    assert.is_true(bags[0][1].isLocked)
    assert.is_truthy(HF._moving["0:1"])
    assert.same(before, snapshot())
    while true do
      local due
      for k, t in ipairs(timers) do
        if t.seconds == GC.VendorPress.STEP then due = k break end
      end
      if not due then break end
      land()
      bagsChanged()
      assert.same(before, snapshot())
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

  -- Blizzard asks before a deposit into the Warband Bank ends a refund, and deposits into the
  -- character's own bank without asking (BankFrame.lua's BankUtil_IsAccountBankDepositRefundable).
  it("toward the character's own bank, offers a refundable stack and names one that bank refuses", function()
    refundable["0:2"] = true
    bags[5][2] = info(3, 7)
    refused["5:2"], refusedHere["5:2"] = true, true
    showing = CHARACTER
    open()
    openRow("Herbs")
    local herbs = row("Herbs")
    assert.same({}, lines(herbs, "stays"))
    W.state(herbs.store).scripts.OnEnter(herbs.store)
    assert.same({ "Store", "Bloom ×200 (2 left)" }, tip.lines)
    openRow("Ore")
    assert.same({ "Stays in bags: Bismuth ×7, your bank does not take it" }, lines(row("Ore"), "stays"))
    landing = true
    press(row("Herbs").store)
    ticks()
    assert.same({ n = 5, 0, 2, nil, CHARACTER, false }, used[2])
    -- What only the Warband Bank refuses goes into the character's own bank.
    refusedHere["5:2"] = nil
    bagsChanged()
    assert.same({}, lines(row("Ore"), "stays"))
  end)

  -- A group is its id on goldcap.gg: a follow from the site in another language keeps its count,
  -- and a catalog group and a player's own list that read alike are two groups.
  it("keeps a group's count by its id: a new name keeps it, and two groups named alike are two", function()
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = FILE.caps, rules = {
      { n = "Herbs", id = "herbs", p = "gather", d = 24, fp = 80 },
      { n = "Herbs", id = "u_a1b2c3d4e5f6", p = "gather", d = 24, fp = 80 },
      { n = "Cloth", id = "cloth", p = "gather", d = 24, fp = 80 },
    } }
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
    open()
    assert.same({ "Herbs", "Herbs" }, rowNames())
    press(rowByKey("herbs").head)
    press(rowByKey("herbs").keep)
    assert.equal("How many of each item in Herbs to keep in your bags?", asked.opts.title)
    asked.opts.onCommit(30)
    assert.same({ v = GC.BankGroups.VERSION, groups = { herbs = 30 } }, GC.db.bankKeep)
    assert.equal("Keep in bags: 30 of each", rowByKey("herbs").keep.label)
    press(rowByKey("u_a1b2c3d4e5f6").head)
    assert.equal("Keep in bags: 0 of each", rowByKey("u_a1b2c3d4e5f6").keep.label)
    press(rowByKey("herbs").head)
    -- The same group, followed again from the site in German: its id stays, its name changes.
    file.rules[1].n = "Kräuter"
    GC.GroupRules.Adopt()
    bagsChanged()
    local herbs = rowByKey("herbs")
    assert.equal("Kräuter", textOf(herbs.name))
    assert.equal("Keep in bags: 30 of each", herbs.keep.label)
    W.state(herbs.store).scripts.OnEnter(herbs.store)
    assert.same({ "Store", "Bloom ×20 (1 left)" }, tip.lines)
    press(herbs.keep)
    assert.equal("How many of each item in Kräuter to keep in your bags?", asked.opts.title)
    assert.equal("30", asked.opts.text)
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
  -- Many groups: the search, the filter and the sort
  -- ---------------------------------------------------------------------------------------------

  -- A TSM player brings 8 to 20 groups (GC.Hoard.SEARCH_MIN_GROUPS): over the rows a search box,
  -- the filter and the sort; with fewer, none of it, and the list is what can move here, by value.
  it("shows the search row from 8 groups, and under 8 lists what can move here by value", function()
    manyGroups(7)
    VALUE[105] = 50000
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { ["Group 01"] = 100 } }
    open()
    assert.is_false(shown(search()))
    -- Group 05 is worth 100g, the rest nothing; Group 01 keeps all of its 20: under the fold line.
    assert.same({ "Group 05", "Group 02", "Group 03", "Group 04", "Group 06", "Group 07" }, rowNames())
    assert.is_true(shown(HF._frame.fold))
    close()
    manyGroups(8)
    open()
    local s = search()
    assert.is_true(shown(s))
    assert.equal("To move here 7", filterSide("move").label)
    assert.equal("All 8", filterSide("all").label)
    assert.equal("By value ▼", s.sort.label)
    -- The BUY tab's search box, its hint and all.
    assert.is_true(shown(s.hint))
    assert.equal("Search", textOf(s.hint))
    -- Fixed above the list, outside the scroll, as the board draws it: it never scrolls away.
    local f = HF._frame
    assert.equal(f, s:GetParent())
    assert.equal(f, at(s)[2])
    assert.equal(12, at(s)[4])
    assert.is_true(-at(s)[5] + s:GetHeight() < -at(f.scroll)[5])
    assert.equal(f.content:GetWidth(), s:GetWidth())
  end)

  it("narrows the rows to the groups whose name or items' names hold what is typed, case-blind", function()
    manyGroups(10)
    open()
    local box = search().box
    typeInto(box, "group 03")
    assert.same({ "Group 03" }, rowNames())
    -- Item 1 and Item 10.
    typeInto(box, "ITEM 1")
    assert.same({ "Group 01", "Group 10" }, rowNames())
    assert.is_false(shown(search().hint))
    typeInto(box, "zzz")
    assert.same({}, rowNames())
    assert.is_true(shown(HF._frame.empty))
    assert.equal("No group or item matches your search.", textOf(HF._frame.empty))
    typeInto(box, "")
    assert.equal(10, #rowNames())
    assert.is_false(shown(HF._frame.empty))
    assert.is_true(shown(search().hint))
  end)

  it("switches between what can move here and all of it, counting each, the switch staying where it is", function()
    manyGroups(8)
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { ["Group 01"] = 100, ["Group 02"] = 100 } }
    open()
    local move, all = filterSide("move"), filterSide("all")
    local K = GC.Kit.Tokens.color
    assert.equal("To move here 6", move.label)
    assert.equal("All 8", all.label)
    assert.same({ K.goldText[1], K.goldText[2], K.goldText[3], 1 }, W.state(move.text).color)
    assert.same({ K.text2[1], K.text2[2], K.text2[3], 1 }, W.state(all.text).color)
    assert.equal(6, #rowNames())
    assert.is_true(shown(HF._frame.fold))
    local before = { at(move), at(all), move:GetWidth(), all:GetWidth() }
    press(all)
    assert.equal(8, #rowNames())
    assert.is_false(shown(HF._frame.fold))
    assert.same({ K.goldText[1], K.goldText[2], K.goldText[3], 1 }, W.state(all.text).color)
    assert.same(before, { at(move), at(all), move:GetWidth(), all:GetWidth() })
    press(move)
    assert.equal(6, #rowNames())
  end)

  it("sorts by value or by name at a click of the sort button, which keeps its width", function()
    manyGroups(8)
    VALUE[105], VALUE[103] = 50000, 10000
    open()
    local sort = search().sort
    assert.same({ "Group 05", "Group 03", "Group 01", "Group 02", "Group 04", "Group 06", "Group 07", "Group 08" },
      rowNames())
    local width, place = sort:GetWidth(), at(sort)
    press(sort)
    assert.equal("By name ▼", sort.label)
    assert.same({ "Group 01", "Group 02", "Group 03", "Group 04", "Group 05", "Group 06", "Group 07", "Group 08" },
      rowNames())
    assert.equal(width, sort:GetWidth())
    assert.same(place, at(sort))
    press(sort)
    assert.equal("By value ▼", sort.label)
    assert.equal("Group 05", rowNames()[1])
  end)

  it("keeps the search, the filter and the sort for the visit, and starts again at the next", function()
    manyGroups(10)
    open()
    local s = search()
    typeInto(s.box, "group 0")
    press(filterSide("all"))
    press(s.sort)
    bagsChanged()
    assert.equal(9, #rowNames())
    assert.equal("By name ▼", s.sort.label)
    close()
    assert.equal("", W.state(s.box).text)
    open()
    assert.equal(10, #rowNames())
    assert.equal("By value ▼", s.sort.label)
    assert.same({ GC.Kit.Tokens.color.goldText[1], GC.Kit.Tokens.color.goldText[2], GC.Kit.Tokens.color.goldText[3], 1 },
      W.state(filterSide("move").text).color)
  end)

  -- The BUY tab's search box: Enter lets go of the keyboard and keeps what was typed, Escape lets
  -- go and empties it, and nothing keeps the keyboard once the bank has closed.
  it("lets go of the keyboard at Enter, at Escape, which empties it, and when the bank closes", function()
    manyGroups(10)
    open()
    local box = search().box
    box:SetFocus()
    assert.is_false(shown(search().hint))
    typeInto(box, "group 04")
    W.state(box).scripts.OnEnterPressed(box)
    assert.is_false(box:HasFocus())
    assert.same({ "Group 04" }, rowNames())
    box:SetFocus()
    W.state(box).scripts.OnEscapePressed(box)
    assert.is_false(box:HasFocus())
    assert.equal("", W.state(box).text)
    assert.equal(10, #rowNames())
    box:SetFocus()
    typeInto(box, "group 05")
    close()
    assert.is_false(box:HasFocus())
    open()
    box:SetFocus()
    press(HF._frame.close)
    assert.is_false(box:HasFocus())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Several groups at once
  -- ---------------------------------------------------------------------------------------------

  -- Every row has its checkbox in the same room at its left from the first paint, so checking one
  -- moves nothing and never sends a row's play under its name some of the time.
  it("draws a checkbox in fixed room at the left of every group and folder row, and moves nothing when checked", function()
    folders()
    GC.Hoard.SetFolderOpen(GC.db, "gathering", true)
    open()
    local f = HF._frame
    local function snapshot()
      local out = { content = f.content:GetHeight() }
      for _, r in ipairs(HF._rows) do
        if r:IsShown() then out[#out + 1] = { at(r), r:GetHeight(), at(r.name), at(r.check), at(r.store) } end
      end
      return out
    end
    for _, r in ipairs(HF._rows) do
      if r:IsShown() then
        assert.is_true(shown(r.check), textOf(r.name))
        assert.equal(6, at(r.check)[4])
        assert.is_true(at(r.name)[4] >= 6 + r.check:GetWidth() + 4, textOf(r.name))
      end
    end
    assert.equal(at(row("Herbs").name)[4], at(row("Linen").name)[4])
    local before = snapshot()
    checkOf("Herbs")
    assert.same(before, snapshot())
    -- A click on the box checks it and does not open the row.
    assert.is_false(shown(row("Herbs").keep))
    assert.equal("check", glyph(row("Herbs").check.glyph))
  end)

  -- The board's ManyGroups: a checked group in a gold wash with a gold ring, a folder with any of
  -- its groups checked ringed in gold; the rest as they were.
  it("draws a checked group in gold, and a folder with checked groups ringed in gold", function()
    folders()
    GC.Hoard.SetFolderOpen(GC.db, "gathering", true)
    open()
    local K = GC.Kit.Tokens.color
    local function look(r) return { W.state(r.bg).vertex, W.state(r.ring).vertex } end
    local plain = { herbs = look(row("Herbs")), folder = look(row("Gathering", "folder")) }
    checkOf("Herbs")
    assert.same({ { K.gold[1], K.gold[2], K.gold[3], 0.06 }, { K.gold[1], K.gold[2], K.gold[3], 0.3 } },
      look(row("Herbs")))
    local folder = look(row("Gathering", "folder"))
    assert.same(plain.folder[1], folder[1])
    assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.35 }, folder[2])
    assert.same(plain.herbs, look(row("Ore")))
    checkOf("Herbs")
    assert.same(plain.herbs, look(row("Herbs")))
    assert.same(plain.folder, look(row("Gathering", "folder")))
  end)

  -- The bar's room is the window's from its first paint with checkboxes, for the visit: nothing
  -- checked, it holds a quiet hint; a check fills it, and the list above never moves.
  it("keeps the selection bar's room at the window's foot from the first paint, with a hint while nothing is checked", function()
    open()
    local f, b = HF._frame, bar()
    local K = GC.Kit.Tokens.color
    local function place() return { at(f.scroll), f.scroll:GetHeight(), f:GetHeight(), at(b), b:GetHeight() } end
    assert.is_true(shown(b))
    assert.same({ "BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12 }, at(b))
    assert.equal(382 - 24, b:GetWidth())
    assert.is_true(shown(b.hint))
    assert.equal("Tick groups to move several at once", plainText(b.hint))
    assert.same({ K.text3[1], K.text3[2], K.text3[3], 1 }, W.state(b.hint).color)
    for _, part in ipairs({ b.title, b.sub, b.store, b.take, b.clear, b.bg, b.ring }) do assert.is_false(shown(part)) end
    -- The scroll keeps clear of it.
    assert.is_true(-at(f.scroll)[5] + f.scroll:GetHeight() <= f:GetHeight() - 12 - b:GetHeight())
    local before = place()
    checkOf("Herbs")
    assert.same(before, place())
    assert.is_false(shown(b.hint))
    -- Herbs: 4,700g here; its Store moves the bags' two Bloom stacks, its Take out the Warband
    -- Bank's one, each tooltip saying so.
    assert.equal("1 group selected", plainText(b.title))
    assert.equal(helper.plain(("Worth about %s"):format(GC.Util.Money(4700 * 10000))), plainText(b.sub))
    W.state(b.store).scripts.OnEnter(b.store)
    assert.same({ "Store", "2 stacks into Warband Bank", "Bloom ×200 (2 left)" }, tip.lines)
    W.state(b.take).scripts.OnEnter(b.take)
    assert.same({ "Take out", "1 stack into your bags", "Bloom ×600 (1 left)" }, tip.lines)
    checkOf("Ore")
    assert.same(before, place())
    assert.equal("2 groups selected", plainText(b.title))
    assert.equal(helper.plain(("Worth about %s"):format(GC.Util.Money(4800 * 10000))), plainText(b.sub))
    checkOf("Ore")
    press(b.clear)
    assert.is_nil(next(HF._selected))
    assert.same(before, place())
    assert.is_true(shown(b.hint))
    assert.is_false(shown(b.title))
  end)

  -- Over many groups the list scrolls, and the room is the same: checking moves nothing.
  it("never moves or resizes the scroll as groups are checked and unchecked", function()
    manyGroups(20)
    _G.BankFrame.GetTop = function() return 400 end
    open()
    local f = HF._frame
    local function place() return { at(f.scroll), f.scroll:GetHeight(), f:GetHeight(), f.content:GetHeight() } end
    local before = place()
    checkOf("Group 01")
    assert.same(before, place())
    checkOf("Group 02")
    press(bar().clear)
    assert.same(before, place())
  end)

  -- Groups checked that the search or the fold line hide are still selected, and the bar says how
  -- many of them it cannot show.
  it("counts the checked groups the search or the fold line hide", function()
    manyGroups(10)
    open()
    checkOf("Group 03")
    checkOf("Group 04")
    typeInto(search().box, "group 03")
    assert.equal("2 groups selected, 1 not shown", plainText(bar().title))
    typeInto(search().box, "")
    assert.equal("2 groups selected", plainText(bar().title))
    -- One key with its own punctuation in every language, not a Latin comma glued on.
    helper.loadModule("Locale/zhCN.lua", GC)
    GC.ActivateLocale("zhCN")
    typeInto(search().box, "group 03")
    assert.equal(GC.L["%d groups selected"]:format(2) .. GC.L[", %d not shown"]:format(1), plainText(bar().title))
    assert.is_nil(plainText(bar().title):find(", ", 1, true))
  end)

  it("checks every group of a folder from off, and clears them all from on or mixed", function()
    folders()
    open()
    local folder = row("Gathering", "folder")
    assert.equal("off", folder.check.state)
    press(folder.check)
    assert.same({ herbs = true, ore = true }, HF._selected)
    assert.equal("check", glyph(row("Gathering", "folder").check.glyph))
    assert.equal("2 groups selected", plainText(bar().title))
    press(row("Gathering", "folder").head)
    checkOf("Herbs")
    assert.same({ ore = true }, HF._selected)
    assert.equal("mixed", row("Gathering", "folder").check.state)
    assert.equal("minus", glyph(row("Gathering", "folder").check.glyph))
    press(row("Gathering", "folder").check)
    assert.is_nil(next(HF._selected))
    assert.is_false(shown(bar().title))
    press(row("Gathering", "folder").check)
    press(row("Gathering", "folder").check)
    assert.is_nil(next(HF._selected))
  end)

  it("stores the selected groups' stacks on one press of the bar's Store, the first inside the click", function()
    landing = true
    open()
    checkOf("Herbs")
    checkOf("Ore")
    local store = bar().store
    assert.equal("selection:in", store.runId)
    assert.equal("selection:out", bar().take.runId)
    press(store)
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
    assert.equal("selection:in", HF.Running())
    assert.equal(store, select(2, HF.Running()))
    ticks()
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false }, { n = 5, 0, 2, nil, ACCOUNT, false },
      { n = 5, 5, 1, nil, ACCOUNT, false } }, used)
    bagsChanged()
    assert.is_false(store:IsEnabled())
    used = {}
    press(bar().take)
    ticks()
    assert.equal(4, #used)
    for _, call in ipairs(used) do assert.equal(2, call.n) end
  end)

  it("drops the selection when the bank closes and when the switch comes to the other bank", function()
    open()
    checkOf("Herbs")
    close()
    open()
    assert.is_false(shown(bar().title))
    assert.is_nil(next(HF._selected))
    checkOf("Herbs")
    choose(CHARACTER)
    assert.is_false(shown(bar().title))
    assert.is_nil(next(HF._selected))
    -- The bank window comes to the bank the switch names: kept; then to the other: dropped.
    checkOf("Herbs")
    switchTo(CHARACTER)
    assert.is_true(shown(bar().title))
    switchTo(ACCOUNT)
    assert.is_false(shown(bar().title))
    -- A repaint on the same bank keeps it.
    checkOf("Ore")
    bagsChanged()
    assert.is_true(shown(bar().title))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- A run as it goes
  -- ---------------------------------------------------------------------------------------------

  -- One step of the press machine: the server answers the move in flight, then the machine's next
  -- timer runs. Answers whether there was one.
  local function step()
    for k, t in ipairs(timers) do
      if t.seconds == GC.VendorPress.STEP then
        land()
        table.remove(timers, k).fn()
        return true
      end
    end
    return false
  end

  -- The pressed button turns into Stop where it stands (one button, two looks: docs/addon/AGENTS.md
  -- "Buttons and hover"), the other move gives way, the row keeps its name and its play and wears
  -- the board's gold, and its worth gives way to how far the run is. An item wears a gold ring
  -- while a stack of it is on its way, and a check once every stack of it in the run has left its
  -- slot.
  it("turns the pressed button into Stop and shows how far the run is, and what has moved", function()
    landing = true
    bags[0][4] = info(6, 5)
    open()
    local K = GC.Kit.Tokens.color
    local herbs = row("Herbs")
    local store, take = herbs.store, herbs.take
    local storeAt, height, nameAt, chipAt = at(store), herbs:GetHeight(), at(herbs.name), at(herbs.chip)
    press(store)
    assert.same(storeAt, at(store))
    assert.is_true(shown(store))
    assert.is_true(store:IsEnabled())
    assert.equal("close", glyph(store.icon))
    assert.is_false(shown(take))
    assert.is_false(shown(herbs.worth))
    -- The name and the play stay, where they were; the row keeps its height.
    assert.is_true(shown(herbs.name))
    assert.equal("Herbs", textOf(herbs.name))
    assert.is_true(shown(herbs.chip))
    assert.same({ nameAt, chipAt, height }, { at(herbs.name), at(herbs.chip), herbs:GetHeight() })
    assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.07 }, W.state(herbs.bg).vertex)
    assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.6 }, W.state(herbs.ring).vertex)
    assert.equal("0 / 3", textOf(herbs.cast.count))
    -- Its icons: Bloom of the second quality (not in the run), Bloom of the first (two stacks, the
    -- one of 200 on its way), Mycobloom.
    assert.is_true(shown(herbs.icons[2].ring))
    assert.is_false(shown(herbs.icons[1].ring))
    assert.is_false(shown(herbs.icons[2].mark))
    -- The first stack has left its slot: one of three, and Bloom's other stack is still to go.
    land()
    bagsChanged()
    assert.equal("1 / 3", textOf(herbs.cast.count))
    assert.is_true(herbs.cast.fill:GetWidth() > 0)
    assert.is_false(shown(herbs.icons[2].mark))
    assert.is_false(shown(herbs.icons[2].ring))
    step()
    bagsChanged()
    assert.is_true(shown(herbs.icons[2].ring))
    land()
    bagsChanged()
    assert.equal("2 / 3", textOf(herbs.cast.count))
    assert.is_true(shown(herbs.icons[2].mark))
    assert.equal("check", glyph(herbs.icons[2].mark))
    assert.is_true(shown(herbs.icons[2].shade))
    assert.is_false(shown(herbs.icons[2].ring))
    -- Stop: a second press where the button was pressed, through the same machine.
    press(store)
    assert.is_nil(HF.Running())
    ticks()
    assert.equal(2, #used)
    bagsChanged()
    assert.equal("arrowDown", glyph(store.icon))
    assert.is_true(shown(take))
    assert.is_true(shown(herbs.worth))
    assert.is_false(shown(herbs.cast.count))
    assert.is_false(shown(herbs.icons[2].mark))
    assert.equal(height, herbs:GetHeight())
    assert.same({ K.glassBottom[1], K.glassBottom[2], K.glassBottom[3], K.glassBottom[4] }, W.state(herbs.bg).vertex)
  end)

  -- A stack whose slot never shows the move (a full bank) is offered again once the settle timer
  -- gives up on it, and is never counted or checked as moved.
  it("never counts or checks a stack whose slot does not show the move", function()
    bags[0][4] = info(6, 5)
    open()
    local herbs = row("Herbs")
    press(herbs.store)
    assert.equal(1, #used)
    settle()
    assert.is_true(HF._Machine():IsRunning())
    assert.equal("0 / 3", textOf(herbs.cast.count))
    assert.is_false(shown(herbs.icons[2].mark))
    assert.is_false(shown(herbs.icons[2].ring))
  end)

  -- Where a run goes is said where the player looks for it: in its Stop's tooltip.
  it("says in Stop's tooltip that a run out goes to the bags, and a run in to the bank the switch names", function()
    landing = true
    showing = CHARACTER
    open()
    local take = row("Herbs").take
    press(take)
    W.state(take).scripts.OnEnter(take)
    assert.same({ "Stop moving", "Moving to your bags" }, tip.lines)
    assert.equal("close", glyph(take.icon))
    assert.is_false(shown(row("Herbs").store))
    press(take)
    local store = row("Herbs").store
    press(store)
    W.state(store).scripts.OnEnter(store)
    assert.same({ "Stop moving", "Moving to Bank" }, tip.lines)
  end)

  -- Store all and Take all out, and the selection bar, run the same way: the pressed button says
  -- Stop where it stands, the other gives way, and the line says where the run goes and how far.
  it("shows the run on Store all's line and on the selection bar, Stop where the press was", function()
    landing = true
    open()
    local f = HF._frame
    local storeAll, takeAll = f.storeAll, f.takeAll
    local width, place = storeAll:GetWidth(), at(storeAll)
    press(storeAll)
    assert.equal("Stop", storeAll.label)
    assert.equal(width, storeAll:GetWidth())
    assert.same(place, at(storeAll))
    assert.is_false(shown(takeAll))
    assert.is_true(shown(f.cast.label))
    assert.equal("Moving to Warband Bank", textOf(f.cast.label))
    assert.equal("0 / 3", textOf(f.cast.count))
    press(storeAll)
    assert.is_nil(HF.Running())
    assert.equal("Store all", storeAll.label)
    assert.is_true(shown(takeAll))
    assert.is_false(shown(f.cast.label))
    bagsChanged()
    used = {}
    checkOf("Herbs")
    local b = bar()
    local barH, takeW, takeAt = b:GetHeight(), b.take:GetWidth(), at(b.take)
    press(b.take)
    assert.equal(1, #used)
    assert.equal("Stop", b.take.label)
    assert.equal(takeW, b.take:GetWidth())
    assert.same(takeAt, at(b.take))
    assert.is_false(shown(b.store))
    assert.is_false(shown(b.sub))
    assert.equal("Moving to your bags", textOf(b.cast.label))
    assert.equal("0 / 1", textOf(b.cast.count))
    assert.equal(barH, b:GetHeight())
    press(b.take)
    assert.is_nil(HF.Running())
    assert.equal("Take out", b.take.label)
    assert.is_true(shown(b.sub))
  end)

  -- A run whose row the list does not show (the search hides its group, or its folder is closed)
  -- can still be watched and stopped: on Store all's line, the button of its way is its Stop, the
  -- other gives way, and the line says where it goes and how far. A press of that Stop stops it.
  it("shows a run whose row is out of view on Store all's line, where its Stop stops it", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    open()
    local f = HF._frame
    local storeAll, takeAll = f.storeAll, f.takeAll
    local width, place = storeAll:GetWidth(), at(storeAll)
    press(row("Group 01").store)
    assert.equal("group:Group 01:in", HF.Running())
    assert.equal("Store all", storeAll.label)
    typeInto(search().box, "Group 02")
    assert.is_nil(row("Group 01"))
    assert.equal("Stop", storeAll.label)
    assert.same({ width, place }, { storeAll:GetWidth(), at(storeAll) })
    assert.is_false(shown(takeAll))
    assert.is_true(shown(f.cast.label))
    assert.equal("Moving to Warband Bank", textOf(f.cast.label))
    assert.equal("0 / 1", textOf(f.cast.count))
    press(storeAll)
    assert.is_nil(HF.Running())
    assert.equal(1, #used)
    assert.equal("Store all", storeAll.label)
    assert.equal("all:in", storeAll.runId)
    assert.is_true(shown(takeAll))
    assert.is_false(shown(f.cast.label))
  end)

  -- A run out of a group whose folder the player closes, on Take all out's side.
  it("shows a run whose folder is closed on Store all's line, Take all out its Stop", function()
    folders()
    open()
    local f = HF._frame
    local storeAll, takeAll = f.storeAll, f.takeAll
    press(row("Gathering", "folder").head)
    press(row("Herbs").take)
    assert.equal("group:herbs:out", HF.Running())
    press(row("Gathering", "folder").head)
    assert.is_nil(row("Herbs"))
    assert.equal("Stop", takeAll.label)
    assert.is_false(shown(storeAll))
    assert.equal("Moving to your bags", textOf(f.cast.label))
    press(takeAll)
    assert.is_nil(HF.Running())
    assert.equal(1, #used)
    assert.equal("Take all out", takeAll.label)
    assert.equal("all:out", takeAll.runId)
  end)

  -- A press checks nothing away under the cursor: the selection bar keeps its run's Stop until the
  -- run ends, and clearing the selection stops it with the bar.
  it("stops a selection's run when the selection is cleared", function()
    landing = true
    open()
    checkOf("Herbs")
    press(bar().store)
    assert.equal("selection:in", HF.Running())
    press(bar().clear)
    assert.is_nil(HF.Running())
    ticks()
    assert.equal(1, #used)
  end)

  it("hands sections the run as it goes", function()
    landing = true
    local seen
    HF.AddSection("tiles", { build = function() end, paint = function(_, ctx) seen = ctx return 0 end })
    open()
    assert.is_false(seen.running)
    assert.is_nil(seen.run)
    checkOf("Herbs")
    press(bar().store)
    assert.is_true(seen.running)
    assert.equal("selection:in", seen.run.id)
    assert.same({ 0, 2 }, { seen.run.done, seen.run.total })
    land()
    bagsChanged()
    assert.same({ 1, 2 }, { seen.run.done, seen.run.total })
    ticks()
    bagsChanged()
    assert.is_false(seen.running)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Redrawing what is shown again
  -- ---------------------------------------------------------------------------------------------

  -- docs/addon/AGENTS.md "Text": a one-line label whose frame was hidden and shown again can come
  -- back blank, and SetText with the text it holds does not redraw it. The cure is clear, set,
  -- hide, show, on every re-show.
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
    return n >= 4 and log[n - 3] == "set " and log[n - 2] == "set " .. tostring(textOf(fs)) and log[n - 1] == "hide"
      and log[n] == "show"
  end

  it("redraws every label it shows when the window comes back", function()
    open()
    openRow("Herbs")
    press(HF._frame.close)
    local f, herbs, logs = HF._frame, row("Herbs"), {}
    for _, fs in ipairs(f.texts) do watch(logs, fs) end
    for _, r in ipairs(HF._rows) do
      if r:IsShown() then
        for _, fs in ipairs(r.texts) do watch(logs, fs) end
      end
    end
    -- Each named one is among them.
    for _, fs in ipairs({ f.title, f.brand, side(CHARACTER).text, side(ACCOUNT).text, f.storeAll.text, f.takeAll.text,
      f.freeBags.words, f.freeBags.num, f.freeBank.words, f.groupsTitle, herbs.name, herbs.chip.text,
      herbs.keep.text, herbs.worth }) do
      assert.is_truthy(logs[fs])
    end
    press(HF._handle)
    assert.is_true(windowUp())
    local checked = 0
    for fs in pairs(logs) do
      if fs:IsShown() and textOf(fs) ~= nil then
        assert.is_true(restamped(logs, fs), tostring(textOf(fs)))
        checked = checked + 1
      end
    end
    assert.is_true(checked >= 14)
  end)

  it("redraws an opened row's keep count, a row shown again and the handle", function()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100 } }
    open()
    openRow("Herbs")
    openRow("Herbs")
    local logs = {}
    local keep = row("Herbs").keep
    watch(logs, keep.text)
    openRow("Herbs")
    assert.is_true(restamped(logs, keep.text))
    -- The fold line's rows, folded away and shown again.
    press(HF._frame.fold)
    local ore = row("Ore")
    press(HF._frame.fold)
    assert.is_false(ore:IsShown())
    watch(logs, ore.name)
    press(HF._frame.fold)
    assert.is_true(ore:IsShown())
    assert.is_true(restamped(logs, ore.name))
    -- The handle, at the next visit.
    press(HF._frame.close)
    close()
    watch(logs, HF._handle.text)
    open()
    assert.is_true(shown(HF._handle))
    assert.is_true(restamped(logs, HF._handle.text))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- What later parts of the window build on
  -- ---------------------------------------------------------------------------------------------

  -- Sections: the tiles pinned under the switch, the carry cards in the scroll under the groups and
  -- the footer pinned at the window's foot, each built once in a frame of its own and painted with
  -- what it needs.
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
    HF.AddSection("carry", section("carry", 30))
    open()
    bagsChanged()
    assert.equal(3, #built)
    local tiles, carry, footer = ctxs.tiles, ctxs.carry, ctxs.footer
    assert.equal(ACCOUNT, tiles.bankType)
    assert.same({ [CHARACTER] = true, [ACCOUNT] = true }, tiles.usable)
    assert.is_false(tiles.running)
    assert.same({ "Herbs", "Ore" }, { tiles.groups[1].name, tiles.groups[2].name })
    assert.equal(60000, tiles.valueOf(2))
    assert.equal(footer.bankType, tiles.bankType)
    -- The pinned ones as wide as the header, the carry cards as the list.
    assert.equal(382 - 24, tiles.width)
    assert.equal(382 - 24, footer.width)
    assert.equal(HF._frame.content:GetWidth(), carry.width)
    -- What the paint read, for each part to take what it wants from: every stack in the bags (the
    -- backpack's three and the reagent bag's one) and in a bank's tabs.
    assert.equal(4, #tiles.inBags())
    assert.same({ 2, 600 }, { tiles.inBank(ACCOUNT)[1].itemID, tiles.inBank(ACCOUNT)[1].count })
    assert.same({ 2, 40 }, { carry.inBank(CHARACTER)[1].itemID, carry.inBank(CHARACTER)[1].count })
    -- The tiles under the switch, outside the scroll; the carry cards in the scroll under the
    -- groups; the footer at the window's foot.
    local f = HF._frame
    assert.equal(f, frames.tiles:GetParent())
    assert.same({ "TOPLEFT", f, "TOPLEFT", 12 }, { unpack(at(frames.tiles), 1, 4) })
    assert.is_true(-at(frames.tiles)[5] + 40 <= -at(f.scroll)[5])
    assert.equal(f.content, frames.carry:GetParent())
    assert.is_true(-at(frames.carry)[5] > -at(row("Ore"))[5])
    assert.is_true(shown(frames.carry))
    assert.equal(f, frames.footer:GetParent())
    assert.same({ "BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12 }, at(frames.footer))
    assert.is_true(shown(frames.footer))
    press(row("Herbs").store)
    assert.is_true(ctxs.tiles.running)
  end)

  -- The footer is pinned at the window's foot, outside the scroll: under the selection bar's room,
  -- at the window's width less its margins.
  it("pins the footer under the selection bar's room, outside the scroll", function()
    local frames, ctxs = {}, {}
    HF.AddSection("footer", { build = function() end,
      paint = function(f, ctx) frames.footer, ctxs.footer = f, ctx return 30 end })
    open()
    local f, b, footer = HF._frame, bar(), frames.footer
    assert.equal(f, footer:GetParent())
    assert.same({ "BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12 }, at(footer))
    assert.equal(30, footer:GetHeight())
    assert.equal(382 - 24, ctxs.footer.width)
    assert.equal(382 - 24, footer:GetWidth())
    assert.same({ "BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12 + 30 + 11 }, at(b))
    assert.is_true(-at(f.scroll)[5] + f.scroll:GetHeight() <= f:GetHeight() - (12 + 30 + 11 + b:GetHeight()))
  end)

  -- The tiles are pinned under the switch, over the search row (the ManyGroups board), at the
  -- window's width less its margins, and never scroll away.
  it("pins the tiles under the switch and over the search row, outside the scroll", function()
    manyGroups(GC.Hoard.SEARCH_MIN_GROUPS)
    local frames, ctxs = {}, {}
    HF.AddSection("tiles", { build = function() end,
      paint = function(f, ctx) frames.tiles, ctxs.tiles = f, ctx return 40 end })
    open()
    local f, tiles = HF._frame, frames.tiles
    assert.equal(f, tiles:GetParent())
    assert.equal(382 - 24, ctxs.tiles.width)
    assert.equal(12, at(tiles)[4])
    local tilesY = -at(tiles)[5]
    assert.is_true(tilesY >= -at(f.choice)[5] + f.choice:GetHeight())
    local searchY = -at(search())[5]
    assert.equal(tilesY + 40 + 11, searchY)
    assert.is_true(-at(f.scroll)[5] >= searchY + search():GetHeight())
    -- What the tiles are told of the window: the search row shows, the stacks of the groups.
    assert.is_true(ctxs.tiles.many)
    assert.is_true(ctxs.tiles.hasGroups)
    assert.equal(GC.Hoard.SEARCH_MIN_GROUPS, #ctxs.tiles.bagStacks)
    assert.same({}, ctxs.tiles.bankStacks)
    local first = ctxs.tiles.visit
    bagsChanged()
    assert.equal(first, ctxs.tiles.visit)
    close()
    open()
    assert.is_true(ctxs.tiles.visit > first)
  end)

  -- A low bank window (a small screen, a high UI scale): with the tiles over the list and the footer
  -- under it, the scroll still keeps three rows' room, and the window grows past the room under its
  -- top for that rather than leaving the list none (the window is clamped to the screen).
  it("keeps three rows' room in the scroll however low the room beside the bank window is", function()
    manyGroups(12)
    function _G.BankFrame:GetTop() return 100 end
    HF.AddSection("tiles", { build = function() end, paint = function() return 120 end })
    HF.AddSection("footer", { build = function() end, paint = function() return 60 end })
    open()
    local f = HF._frame
    assert.equal(3 * (26 + 3), f.scroll:GetHeight())
    assert.equal(f:GetHeight(), -at(f.scroll)[5] + f.scroll:GetHeight() + (f:GetHeight() - (-at(f.scroll)[5]) - f.scroll:GetHeight()))
    assert.is_true(f:GetHeight() > 160)
    -- With room under its top, at the next open it is as tall as all it shows, the scroll ends over
    -- its foot.
    function _G.BankFrame:GetTop() return 4000 end
    close()
    open()
    assert.is_true(f.scroll:GetHeight() > 3 * (26 + 3))
    assert.equal(f.content:GetHeight(), f.scroll:GetHeight())
  end)

  -- The run's end tells the button that pressed it which of its stacks left their slots: what the
  -- footer's Make room remembers for Put back. A stack the server never moved is not among them.
  it("tells a button's onRunEnd which of its stacks left their slots, once, however the run ended", function()
    landing = true
    open()
    local ends = {}
    local mine = W.CreateFrame("Button")
    mine.runId = "footer:makeRoom"
    mine.onRunEnd = function(moved, bank, result) ends[#ends + 1] = { moved = moved, bank = bank, result = result } end
    local first, second = bags[0][1], bags[0][2]
    HF.Press(mine, { { itemID = 1, bag = 0, slot = 1, count = 200, link = "item:1" },
      { itemID = 1, bag = 0, slot = 2, count = 20, link = "item:1" } }, true)
    assert.equal(0, #ends)
    ticks()
    assert.equal(1, #ends)
    assert.equal(ACCOUNT, ends[1].bank)
    assert.same({ 1, 1 }, { ends[1].moved[1].itemID, ends[1].moved[2].itemID })
    assert.same({ 200, 20 }, { ends[1].moved[1].count, ends[1].moved[2].count })
    assert.is_nil(ends[1].result.stopped)
    assert.is_truthy(first and second)
    -- Stopped after its first move: only that one.
    bags[0] = { info(1, 200), info(1, 20) }
    HF.Press(mine, { { itemID = 1, bag = 0, slot = 1, count = 200, link = "item:1" },
      { itemID = 1, bag = 0, slot = 2, count = 20, link = "item:1" } }, true)
    land()
    HF.Press(mine, {}, true)
    assert.equal(2, #ends)
    assert.equal(1, #ends[2].moved)
    assert.equal(200, ends[2].moved[1].count)
    assert.equal("pressed", ends[2].result.stopped)
    -- Nothing moved: the stack sent is waited for until the settle timer gives up on it, then an
    -- empty list, still once.
    bags[0] = { info(1, 200) }
    landing = false
    HF.Press(mine, { { itemID = 1, bag = 0, slot = 1, count = 200, link = "item:1" } }, true)
    ticks()
    assert.equal(2, #ends)
    settle()
    assert.equal(3, #ends)
    assert.equal("refused", ends[3].result.stopped)
    assert.same({}, ends[3].moved)
    settle()
    assert.equal(3, #ends)
  end)

  -- A Stop, the bank closing or the switch can end a run while a stack it sent is on its way: the
  -- button hears once that stack has landed, so what Make room put away is remembered whole.
  it("waits for a stack on its way as the run ends, and tells onRunEnd once it lands, the bank open or not", function()
    landing = true
    open()
    local ends = {}
    local mine = W.CreateFrame("Button")
    mine.runId = "footer:makeRoom"
    mine.onRunEnd = function(moved) ends[#ends + 1] = moved end
    local function two()
      return { { itemID = 1, bag = 0, slot = 1, count = 200, link = "item:1" },
        { itemID = 1, bag = 0, slot = 2, count = 20, link = "item:1" } }
    end
    -- Stopped right after its first move, before the server answered. Not settled until the button
    -- has heard (HF.Settled).
    assert.is_true(HF.Settled())
    HF.Press(mine, two(), true)
    assert.is_false(HF.Settled())
    HF.Press(mine, {}, true)
    assert.equal(0, #ends)
    assert.is_false(HF.Settled())
    land()
    bagsChanged()
    assert.equal(1, #ends)
    assert.is_true(HF.Settled())
    assert.same({ 200 }, { ends[1][1].count })
    -- The bank closed under it: the bags still tell the move.
    bags[0] = { info(1, 200), info(1, 20) }
    open()
    HF.Press(mine, two(), true)
    close()
    assert.equal(1, #ends)
    land()
    bagsChanged()
    assert.equal(2, #ends)
    assert.same({ 200 }, { ends[2][1].count })
    -- Heard once: the settle timer finds nothing more to tell.
    settle()
    assert.equal(2, #ends)
  end)

  -- A section's button that lists what it moves its own way (a tile's) says it in its tooltip
  -- instead of the stack line; its Stop says what it stops as every Stop does.
  it("lets a button list what it moves in its tooltip its own way", function()
    open()
    local mine = HF.ui.moveButton(HF._frame, false, { variant = "active" })
    mine.runId = "tile:test"
    mine.tipLines = function(tooltip) tooltip:AddLine("Mine") end
    HF.ui.paintMove(mine, { { itemID = 1, bag = 12, slot = 1, count = 600, link = "item:1", name = "Bloom" } }, "Tile")
    W.state(mine).scripts.OnEnter(mine)
    assert.same({ "Tile", "Mine" }, tip.lines)
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
    assert.equal("group:Herbs:out", HF.Running())
    assert.equal(row("Herbs").take, select(2, HF.Running()))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Words
  -- ---------------------------------------------------------------------------------------------

  -- A subgroup's top line, one level in, packs its name, its play's chip, five icons with their
  -- counts and a seven-figure worth: nothing overlaps or runs past the row in any language, the row
  -- showing fewer icons or its chip under the name where they do not fit side by side, and a press
  -- leaves it as it was.
  it("never overlaps or cuts a row's top line, in any language", function()
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
    local COUNTS = { 12345, 1234, 999, 20, 5 }
    local function deep(play, name)
      local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" },
        caps = { { i = 3, c = 700, u = 1000, r = 2, k = true } }, rules = {
          { n = "Gathering: " .. name, id = "herbs", pi = "gathering", pn = "Gathering", cn = name, p = play, d = 24 },
          { n = "Gathering: Ore", id = "ore", pi = "gathering", pn = "Gathering", cn = "Ore", p = play, d = 24 },
        } }
      bags = { [0] = {}, [5] = { info(3, 50) }, [12] = {} }
      for k = 1, 5 do
        local id = 20 + k
        file.caps[#file.caps + 1] = { i = id, c = 700, u = 1000, r = 1, k = true }
        -- 100g each: 14,603 of them, 1,460,300g.
        NAMES[id], VALUE[id] = "Herb " .. k, 1000000
        bags[0][k] = info(id, COUNTS[k])
      end
      _G.GoldCap_AppRuns = file
      GC.GroupRules.Adopt()
      GC.Hoard.SetFolderOpen(GC.db, "gathering", true)
    end
    local beside, under = 0, 0
    local function check(r, what)
      local nameX, nameTop = at(r.name)[4], -at(r.name)[5]
      local nameRight, nameBottom = nameX + r.name:GetWidth(), nameTop + r.name:GetHeight()
      local worthRight = at(r.worth)[4]
      local worthLeft = worthRight - r.worth:GetStringWidth()
      local firstLeft, lastRight = worthLeft, nil
      local function take(region)
        local x = at(region)[4]
        firstLeft, lastRight = math.min(firstLeft, x), math.max(lastRight or x, x + region:GetWidth())
      end
      for _, slot in ipairs(r.icons) do
        if slot.edge:IsShown() then
          take(slot.edge)
          assert.is_true(slot.count:GetStringWidth() <= slot.edge:GetWidth() - 2, what .. " " .. textOf(slot.count))
        end
      end
      if r.more:IsShown() then take(r.more) end
      assert.is_true(at(r.check)[4] + r.check:GetWidth() < nameX, what .. ": the checkbox under the name")
      assert.is_true(nameRight <= firstLeft, what .. ": the name over the icons")
      assert.is_true(r.name:GetWidth() >= math.min(r.name:GetUnboundedStringWidth(), 60), what .. ": the name squeezed")
      assert.is_true(nameBottom <= r.head:GetHeight(), what .. ": the name below its line")
      if r.chip:IsShown() then
        local chipX, chipTop = at(r.chip)[4], -at(r.chip)[5]
        if chipX >= nameRight then beside = beside + 1 end
        if chipTop >= nameBottom then under = under + 1 end
        assert.is_true(chipX >= nameRight or chipTop >= nameBottom, what .. ": the chip over the name")
        assert.is_true(chipX + r.chip:GetWidth() <= firstLeft, what .. ": the chip over the icons")
        assert.is_true(chipTop + r.chip:GetHeight() <= r.head:GetHeight(), what .. ": the chip below its line")
        assert.is_true(r.chip:GetWidth() >= r.chip.text:GetUnboundedStringWidth(), what .. ": the chip cut")
      end
      if lastRight then assert.is_true(lastRight <= worthLeft, what .. ": the icons over the worth") end
      assert.is_true(worthRight <= at(r.store)[4], what .. ": the worth over Store")
      assert.is_true(at(r.take)[4] + r.take:GetWidth() <= r:GetWidth(), what .. ": past the row's edge")
    end
    for _, code in ipairs(helper.localeCodes()) do
      GC.ActivateLocale(code)
      for _, play in ipairs({ "gather", "craft", "flip", "stock" }) do
        for _, name in ipairs({ "Herbs", "Kräuterblumen der Insel von Dorn und der Tiefen" }) do
          deep(play, name)
          open()
          local what = ("%s %s %s"):format(code, play, name)
          local r = rowByKey("herbs")
          assert.equal(1, r.data.depth, what)
          assert.equal(5, #r.data.icons, what)
          for _, each in ipairs(HF._rows) do
            if each:IsShown() then check(each, what) end
          end
          local height, chipAt, nameAt = r:GetHeight(), at(r.chip), at(r.name)
          press(r.store)
          local ran = rowByKey("herbs")
          assert.equal(height, ran:GetHeight(), what)
          assert.same({ chipAt, nameAt }, { at(ran.chip), at(ran.name) }, what)
          assert.is_true(shown(ran.name), what)
          check(ran, what)
          -- How far it is, inside the worth column.
          local count = ran.cast.count
          assert.is_true(count:GetStringWidth() <= HF._worthW, what .. ": the count past the worth column")
          assert.is_true(at(count)[4] <= at(ran.store)[4], what .. ": the count over Store")
          close()
        end
      end
    end
    assert.is_true(beside > 0)
    assert.is_true(under > 0)
  end)

  -- A count over an item's icon fits inside it: smaller, or in whole thousands, or not at all.
  it("fits each item's count inside its icon", function()
    bags[0][1], bags[12][1] = info(1, 1234), info(2, 123456)
    open()
    local herbs = row("Herbs")
    local counts = {}
    for i = 1, 2 do
      local slot = herbs.icons[i]
      counts[i] = textOf(slot.count)
      assert.is_true(slot.count:GetStringWidth() <= 15 - 2, counts[i])
    end
    assert.same({ "123k", "1.2k" }, counts)
  end)

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
        -- The switch lays out in the header's room, the window's less its margins; the rest in the
        -- list's, which the scroll's gutter takes from.
        local head = f:GetWidth() - 24
        assert.is_true(f:GetWidth() >= 360, code)
        for _, b in ipairs(f.choice.sides) do
          fits(b, code)
          assert.is_true(head >= b:GetWidth(), code)
        end
        fits(f.storeAll, code)
        fits(f.takeAll, code)
        assert.is_true(head >= f.choice:GetWidth(), code)
        -- The free slots: one line each, as wide as its parts, inside the header.
        for _, chip in ipairs({ f.freeBags, f.freeBank }) do
          for _, fs in ipairs({ chip.words, chip.num, chip.rest }) do
            assert.is_true(W.state(fs).wordWrap == false, code)
          end
          local need = 10 + 4 + chip.words:GetStringWidth() + 4 + chip.num:GetStringWidth()
          if (textOf(chip.rest) or "") ~= "" then need = need + 4 + chip.rest:GetStringWidth() end
          assert.is_true(chip:GetWidth() >= need, code)
        end
        local fold = f.fold
        assert.is_true(shown(fold), code)
        assert.is_true(W.state(fold.text).wordWrap ~= false, code)
        assert.is_true(inner >= fold:GetWidth(), code)
        for _, r in ipairs(HF._rows) do
          if r:IsShown() then
            assert.is_true(W.state(r.name).wordWrap ~= false, code)
            -- As wide as it is, or at least 60 for a name that wraps.
            assert.is_true(r.name:GetWidth() >= math.min(r.name:GetUnboundedStringWidth(), 60), code)
            assert.is_true(W.state(r.name).nonSpaceWrap == true, code)
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

  -- Over many groups, with groups checked and a run going, in every language and toward both banks
  -- (named long, as a German client might): every button as wide as its words, Stop included on
  -- the button that turns into it, every line that can run long wrapping, everything inside the
  -- window, and a run that changes no height.
  it("never cuts the search row, the selection bar or a run's words, in any language", function()
    _G.BANK, _G.ACCOUNT_BANK_PANEL_TITLE = "Persönliches Bankfach des Charakters", "Kriegsmeutenbank der Kriegsmeute"
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
    -- The room a button's words have between their two anchors.
    local function room(button)
      local left, right = 0, 0
      for _, p in ipairs(W.state(button.text).points) do
        if p[1] == "LEFT" then left = p[4] end
        if p[1] == "RIGHT" then right = p[4] end
      end
      return button:GetWidth() - left + right
    end
    local function fits(button, what)
      assert.is_true(room(button) >= button.text:GetUnboundedStringWidth(), what .. " " .. tostring(button.label))
    end
    local function within(widget, width, what)
      local x = at(widget)[4]
      assert.is_true(x >= 0 and x + widget:GetWidth() <= width + 0.01, what)
    end
    for _, code in ipairs(helper.localeCodes()) do
      for _, bankType in ipairs({ ACCOUNT, CHARACTER }) do
        GC.ActivateLocale(code)
        manyGroups(8)
        showing, landing = bankType, true
        open()
        local f, s = HF._frame, search()
        local inner, head = f.content:GetWidth(), f:GetWidth() - 24
        local what = ("%s %d"):format(code, bankType)
        assert.is_true(shown(s), what)
        for _, half in ipairs(s.filter.sides) do fits(half, what) end
        fits(s.sort, what)
        for _, part in ipairs({ s.well, s.filter, s.sort }) do within(part, inner, what) end
        local hint = at(s.hint)
        assert.is_true(hint[4] + s.hint:GetStringWidth() <= s.well:GetWidth(), what .. " " .. textOf(s.hint))
        local b = bar()
        assert.is_true(W.state(b.hint).wordWrap ~= false, what)
        within(b.hint, head, what)
        assert.is_true(-at(b.hint)[5] + b.hint:GetHeight() <= b:GetHeight(), what .. " " .. plainText(b.hint))
        checkOf("Group 01")
        checkOf("Group 02")
        typeInto(s.box, "Group 01")
        assert.equal(head, b:GetWidth(), what)
        for _, button in ipairs({ b.store, b.take }) do fits(button, what) end
        for _, fs in ipairs({ b.title, b.sub }) do
          assert.is_true(W.state(fs).wordWrap ~= false, what)
          within(fs, head, what)
          assert.is_true(-at(fs)[5] + fs:GetHeight() <= b:GetHeight(), what .. " " .. plainText(fs))
        end
        local barH = b:GetHeight()
        press(b.store)
        assert.equal(GC.L["Stop"], b.store.label, what)
        fits(b.store, what)
        assert.equal(barH, b:GetHeight(), what)
        local label = b.cast.label
        assert.is_true(W.state(label).wordWrap ~= false, what)
        within(label, head, what)
        -- Left of the buttons, or over them when they have a line of their own.
        local labelRight = at(label)[4] + label:GetWidth() + b.cast.count:GetStringWidth()
        assert.is_true(labelRight <= at(b.store)[4] or -at(label)[5] + label:GetHeight() <= -at(b.store)[5], what)
        assert.is_true(-at(label)[5] + label:GetHeight() <= barH, what .. " " .. textOf(label))
        press(b.store)
        typeInto(s.box, "")
        press(f.storeAll)
        assert.equal(GC.L["Stop"], f.storeAll.label, what)
        fits(f.storeAll, what)
        -- Store all stands by its right edge.
        assert.is_true(at(f.cast.label)[4] + f.cast.label:GetWidth() <= at(f.storeAll)[4] - f.storeAll:GetWidth(), what)
        press(f.storeAll)
        close()
      end
    end
  end)
end)
