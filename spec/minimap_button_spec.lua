local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/MinimapButton.lua (retail only): GoldCap's own round button on the minimap's edge (the owner,
-- 2026-10-27 00:30: the entry above the bags blended in). Its look is Blizzard's own round map
-- button's (Blizzard_WorldMapTemplates.xml, WorldMapTrackingOptionsButtonTemplate), it moves round
-- the edge by a left drag and keeps the angle in GC.db.minimap, a left click opens a menu, and for an
-- enchanter it counts what is worth disenchanting. The Disenchant window is a seam here
-- (GC.DisenchantFrame: Known, Counts, Toggle; spec/disenchant_frame_spec.lua tests it).
describe("GoldCap minimap button", function()
  local GC, MB, restore, saved, menu, printed, toggled, knows, counts, cursor, tip, repainted, planned, fighting
  local KEYS = { "Minimap", "GetCursorPosition", "GetMinimapShape", "MenuUtil", "GameTooltip", "UIParent" }

  local function button() return MB._button end
  local function at() return W.state(button()).points[1] end
  local function near(want, got) assert.is_true(math.abs(want - got) < 0.01, ("%s ~= %s"):format(want, got)) end
  local function login() MB.OnEvent("PLAYER_LOGIN") end
  local function click() W.state(button()).scripts.OnClick(button(), "LeftButton", false) end
  local function hover() W.state(button()).scripts.OnEnter(button()) end
  local function tipTexts()
    local out = {}
    for i, l in ipairs(tip.lines) do out[i] = l.text end
    return out
  end
  local function entries()
    local out = {}
    for _, e in ipairs(menu.entries) do out[#out + 1] = e.kind .. ":" .. tostring(e.text) end
    return out
  end
  local function buttonNamed(text)
    for _, e in ipairs(menu.entries) do
      if e.kind == "button" and e.text == text then return e end
    end
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    printed, toggled, knows, counts, cursor, repainted = {}, {}, true, { 0, 0, 0 }, { 0, 0 }, 0
    planned, fighting = true, false
    _G.UIParent = CreateFrame("Frame")
    -- The minimap: 140 wide, its centre at (500, 400) on the screen, at scale 1.
    _G.Minimap = CreateFrame("Frame", nil, _G.UIParent)
    _G.Minimap:SetSize(140, 140)
    function _G.Minimap:GetCenter() return 500, 400 end
    function _G.Minimap:GetEffectiveScale() return 1 end
    -- GetCursorPosition (InputDocumentation.lua): the cursor in screen pixels, scale 1 here.
    _G.GetCursorPosition = function() return cursor[1], cursor[2] end
    -- GetMinimapShape is not the client's: a minimap addon defines it. None here unless a case does.
    _G.GetMinimapShape = nil
    -- MenuUtil's description (live Blizzard_Menu/MenuUtil.lua:151): titles, dividers and buttons.
    local function node(kind, text, fn)
      local n = { kind = kind, text = text, fn = fn, entries = {} }
      function n:CreateButton(t, f)
        local c = node("button", t, f)
        self.entries[#self.entries + 1] = c
        return c
      end
      function n:CreateTitle(t) self.entries[#self.entries + 1] = node("title", t) end
      function n:CreateDivider() self.entries[#self.entries + 1] = node("divider") end
      return n
    end
    _G.MenuUtil = { CreateContextMenu = function(owner, generator)
      menu = node("root")
      menu.owner = owner
      generator(owner, menu)
    end }
    tip = { lines = {} }
    -- GameTooltip: SetOwner, AddLine, Show, Hide, IsShown and IsOwned (live InputUtil.lua:41 asks
    -- IsOwned so).
    _G.GameTooltip = {
      SetOwner = function(_, owner, anchor) tip.owner, tip.anchor, tip.lines = owner, anchor, {} end,
      AddLine = function(_, text, r, g, b) tip.lines[#tip.lines + 1] = { text = text, r = r, g = g, b = b } end,
      Show = function() tip.shown = true end,
      Hide = function() tip.shown = false end,
      IsShown = function() return tip.shown == true end,
      IsOwned = function(_, owner) return tip.owner == owner end,
    }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    GC.db = {}
    GC.slashHandlers = {}
    GC.Print = function(msg) printed[#printed + 1] = msg end
    GC.Sniper = { Toggle = function() toggled[#toggled + 1] = "deals" end }
    GC.DisenchantFrame = {
      Known = function() return knows end,
      -- Nil for a character without Disenchant, and while no plan was read: asked to (`readNow`),
      -- the window reads one then, out of combat.
      Counts = function(readNow)
        if not knows then return nil end
        if not planned and readNow and not fighting then planned = true end
        if not planned then return nil end
        return counts[1], counts[2], counts[3]
      end,
      Toggle = function() toggled[#toggled + 1] = "disenchant" end,
      Refresh = function() repainted = repainted + 1 end,
    }
    helper.loadModule("UI/MinimapButton.lua", GC)
    MB = GC.MinimapButton
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  it("stands on the minimap's edge at the lower left, in Blizzard's round map button's look", function()
    login()
    local b = button()
    assert.is_true(b:IsShown())
    assert.equal(_G.Minimap, b:GetParent())
    assert.equal(32, b:GetWidth())
    assert.equal(32, b:GetHeight())
    local p = at()
    assert.equal("CENTER", p[1])
    assert.equal(_G.Minimap, p[2])
    -- 225 degrees, the radius half the minimap's width and MB.EDGE out.
    local r = 70 + MB.EDGE
    near(r * math.cos(math.rad(225)), p[4])
    near(r * math.sin(math.rad(225)), p[5])
    assert.equal("Interface\\Minimap\\MiniMap-TrackingBorder", W.state(b.border).file)
    assert.equal("Interface\\Minimap\\UI-Minimap-Background", W.state(b.back).file)
    assert.equal("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", W.state(b.wash).file)
    assert.equal(GC.Theme.MEDIA .. "GoldCap", W.state(b.logo).file)
  end)

  it("moves round the edge under a left drag and keeps the angle for the account", function()
    login()
    local b = button()
    assert.same({ "LeftButton" }, W.state(b).drag)
    W.state(b).scripts.OnDragStart(b)
    cursor = { 600, 400 }
    W.state(b).scripts.OnUpdate(b, 0.01)
    near(70 + MB.EDGE, at()[4])
    near(0, at()[5])
    cursor = { 500, 300 }
    W.state(b).scripts.OnUpdate(b, 0.01)
    W.state(b).scripts.OnDragStop(b)
    assert.is_nil(W.state(b).scripts.OnUpdate)
    near(270, GC.db.minimap.angle)
    near(0, at()[4])
    near(-(70 + MB.EDGE), at()[5])
  end)

  it("keeps to a square minimap's edge", function()
    _G.GetMinimapShape = function() return "SQUARE" end
    GC.db.minimap = { angle = 45 }
    login()
    near(70 + MB.EDGE, at()[4])
    near(70 + MB.EDGE, at()[5])
  end)

  it("counts what is worth disenchanting in a gold pill for an enchanter, only above 0", function()
    local K = GC.Kit.Tokens.color
    counts = { 3, 1, 2 }
    login()
    local b = button()
    assert.is_true(b.pill:IsShown())
    assert.equal("3", helper.plain(W.state(b.count).text))
    local v = W.state(b.pill).vertex
    assert.same({ K.gold[1], K.gold[2], K.gold[3] }, { v[1], v[2], v[3] })
    counts = { 0, 1, 2 }
    MB.Refresh()
    assert.is_false(b.pill:IsShown())
    assert.is_false(b.count:IsShown())
    counts = { 4, 0, 0 }
    knows = false
    MB.Refresh()
    assert.is_false(b.pill:IsShown())
  end)

  it("opens a menu on a left click: the deals board, Disenchant with its count, and a way to hide it", function()
    counts = { 3, 0, 0 }
    login()
    click()
    assert.same({ "title:GoldCap", "button:Deals board", "button:Disenchant (3)", "divider:nil",
      "button:Hide this button" }, entries())
    buttonNamed("Deals board").fn()
    buttonNamed("Disenchant (3)").fn()
    assert.same({ "deals", "disenchant" }, toggled)
    counts = { 0, 0, 0 }
    click()
    assert.is_not_nil(buttonNamed("Disenchant"))
    knows = false
    click()
    assert.same({ "title:GoldCap", "button:Deals board", "divider:nil", "button:Hide this button" }, entries())
  end)

  it("hides on Hide this button, says how to bring it back, and /gc minimap shows or hides it", function()
    login()
    click()
    buttonNamed("Hide this button").fn()
    assert.is_false(button():IsShown())
    assert.is_true(GC.db.minimap.hide)
    assert.same({ "The GoldCap button by the minimap is hidden. Type /gc minimap to bring it back." }, printed)
    GC.slashHandlers.minimap("")
    assert.is_true(button():IsShown())
    assert.is_false(GC.db.minimap.hide)
    GC.slashHandlers.minimap("")
    assert.is_false(button():IsShown())
    assert.equal(2, #printed)
  end)

  -- Shown again, it asks the window for a fresh count: while it was hidden nothing read the bags.
  it("builds nothing at login while hidden, and appears on /gc minimap with a fresh count", function()
    GC.db.minimap = { hide = true }
    login()
    assert.is_nil(button())
    assert.is_false(MB.Shown())
    GC.slashHandlers.minimap("")
    assert.is_true(button():IsShown())
    assert.is_true(MB.Shown())
    assert.equal(1, repainted)
  end)

  -- Before the window read any plan (at login, or the button shown again) the tooltip and the menu
  -- ask for one: out of combat it is read then; in combat they say only what the button is.
  it("asks for a plan on hover before any was read, and claims no count while none can be read", function()
    planned, fighting = false, true
    login()
    hover()
    assert.same({ "GoldCap", "Click for GoldCap. Drag to move it." }, tipTexts())
    click()
    assert.same({ "title:GoldCap", "button:Deals board", "button:Disenchant", "divider:nil",
      "button:Hide this button" }, entries())
    assert.is_false(button().pill:IsShown())
    fighting = false
    hover()
    assert.same({ "GoldCap", "Nothing in your bags to disenchant.", "Click for GoldCap. Drag to move it." }, tipTexts())
  end)

  -- The old entry's tooltip was painted again on every paint; so is this one, while it shows.
  it("repaints its tooltip when the count changes while it shows, and leaves a hidden one hidden", function()
    counts = { 2, 0, 0 }
    login()
    hover()
    counts = { 5, 1, 0 }
    MB.Refresh()
    assert.same({ "GoldCap", "Worth disenchanting: 5", "The auction house pays more: 1",
      "Click for GoldCap. Drag to move it." }, tipTexts())
    assert.is_true(tip.shown)
    W.state(button()).scripts.OnLeave(button())
    counts = { 1, 0, 0 }
    MB.Refresh()
    assert.is_false(tip.shown)
    assert.equal("Worth disenchanting: 5", tipTexts()[2])
  end)

  it("says in its tooltip what is worth disenchanting and how to use it", function()
    local K = GC.Kit.Tokens.color
    counts = { 2, 1, 3 }
    login()
    local b = button()
    W.state(b).scripts.OnEnter(b)
    local texts = {}
    for i, l in ipairs(tip.lines) do texts[i] = l.text end
    assert.same({ "GoldCap", "Worth disenchanting: 2", "The auction house pays more: 1", "A vendor pays more: 3",
      "Click for GoldCap. Drag to move it." }, texts)
    local last = tip.lines[#tip.lines]
    assert.same({ K.text3[1], K.text3[2], K.text3[3] }, { last.r, last.g, last.b })
    counts = { 0, 0, 0 }
    W.state(b).scripts.OnEnter(b)
    texts = {}
    for i, l in ipairs(tip.lines) do texts[i] = l.text end
    assert.same({ "GoldCap", "Nothing in your bags to disenchant.", "Click for GoldCap. Drag to move it." }, texts)
    knows = false
    W.state(b).scripts.OnEnter(b)
    texts = {}
    for i, l in ipairs(tip.lines) do texts[i] = l.text end
    assert.same({ "GoldCap", "Click for GoldCap. Drag to move it." }, texts)
    W.state(b).scripts.OnLeave(b)
    assert.is_false(tip.shown)
  end)
end)
