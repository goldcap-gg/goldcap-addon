local helper = require("spec.spec_helper")

describe("Upgrades window", function()
  local GC, U, saved, clicked, tipLink
  local KEYS = { "CreateFrame", "UIParent", "UISpecialFrames", "GameTooltip", "HandleModifiedItemClick",
    "GetCoinTextureString", "INVTYPE_HEAD", "INVTYPE_FEET", "ITEM_MOD_STRENGTH_SHORT", "C_Timer" }

  local function region(kind, parent)
    local r = { kind = kind, parent = parent, shown = true, scripts = {}, textures = {} }
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetPoint() end
    function r:SetAllPoints() end
    function r:SetFrameStrata(s) self.strata = s end
    function r:SetToplevel(v) self.toplevel = v end
    function r:SetMovable() end
    function r:EnableMouse(v) self.mouse = v end
    function r:RegisterForDrag() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:SetWidth() end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:Raise() end
    function r:CreateFontString() return region("FontString", self) end
    function r:CreateTexture(_, layer)
      local t = region("Texture", self)
      t.layer = layer
      self.textures[#self.textures + 1] = t
      return t
    end
    r.TitleText = { SetText = function(_, t) r.title = t end }
    return r
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.UIParent = region("Frame")
    _G.UISpecialFrames = {}
    clicked, tipLink = nil, nil
    _G.GameTooltip = { SetOwner = function() end, SetHyperlink = function(_, l) tipLink = l end,
      Show = function() end, Hide = function() end }
    _G.HandleModifiedItemClick = function(l) clicked = l end
    _G.GetCoinTextureString = function(c) return c .. "c" end
    _G.INVTYPE_HEAD, _G.INVTYPE_FEET, _G.ITEM_MOD_STRENGTH_SHORT = "Head", nil, "Strength"
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ForeverGear.lua", GC)
    helper.loadModule("Core/ForeverUpgrades.lua", GC)
    helper.loadModule("UI/ForeverUpgradesFrame.lua", GC)
    U = GC.ForeverUpgradesUI
  end)

  after_each(function() for _, k in ipairs(KEYS) do _G[k] = saved[k] end end)

  it("is a real window: DIALOG strata, its own mouse, on top, and Escape closes it", function()
    local f = U._Build()
    assert.equal("DIALOG", f.strata)
    assert.is_true(f.mouse)
    assert.is_true(f.toplevel)
    assert.same({ "GoldCapUpgradesFrame" }, _G.UISpecialFrames)
    assert.equal("Gear upgrades on the auction house", f.title)
  end)

  it("paints one row per upgrade -- slot, item, what it adds, price -- and says a later piece's level", function()
    U.Render({ at = 900, weights = { STR = 1 }, loading = 0, rows = {
      { labelKey = "INVTYPE_HEAD", link = "|Hitem:101|h[Cap]|h", itemString = "item:101", unit = 250,
        diffs = { ITEM_MOD_STRENGTH_SHORT = 3 } },
      { labelKey = "INVTYPE_FEET", link = "|Hitem:102|h[Boots]|h", itemString = "item:102", unit = 90,
        diffs = { ITEM_MOD_STRENGTH_SHORT = 1 }, later = 22 },
    } }, 1000)
    local f = U._Build()
    assert.equal("From your scan 1m ago. Counts only Strength 1. Change with /gc weights.", f.header:GetText())
    local r1, r2 = f.rows[1], f.rows[2]
    assert.equal("Head", r1.slot:GetText())
    assert.equal("|Hitem:101|h[Cap]|h", r1.item:GetText())
    assert.equal("+3 Strength", r1.gain:GetText())
    assert.equal("250c", r1.price:GetText())
    assert.equal("INVTYPE_FEET", r2.slot:GetText())          -- a client without the global shows its name
    assert.equal("+1 Strength  at level 22", r2.gain:GetText())
    assert.is_false(f.rows[3]:IsShown())
  end)

  it("hovers with the engine's HIGHLIGHT layer, shows the item's own tooltip, and hands a click to the client", function()
    U.Render({ at = 900, weights = { STR = 1 }, loading = 0,
      rows = { { labelKey = "INVTYPE_HEAD", link = "L", itemString = "item:1", unit = 1, diffs = {} } } }, 1000)
    local row = U._Build().rows[1]
    assert.is_true(row.mouse)
    assert.equal("HIGHLIGHT", row.textures[1].layer)
    row.scripts.OnEnter(row)
    assert.equal("L", tipLink)
    row.scripts.OnClick(row)
    assert.equal("L", clicked)
  end)

  it("says why there is nothing to show", function()
    local f = U._Build()
    U.Render({ rows = {}, loading = 0, noScan = true }, 1)
    assert.equal("No scan with gear in it yet. Open the auction house and let GoldCap scan it.", f.header:GetText())
    U.Render({ rows = {}, loading = 0, noStats = true }, 1)
    assert.equal("This client does not report item stats, so GoldCap cannot compare gear.", f.header:GetText())
    U.Render({ rows = {}, loading = 0, noWeights = true }, 1)
    assert.equal("No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5", f.header:GetText())
    U.Render({ rows = {}, loading = 3, at = 1, weights = {} }, 1)
    assert.equal("Nothing on the auction house beats what you wear at your level. "
      .. "Items still loading: 3. Open this again in a moment.", f.header:GetText())
  end)

  it("repaints once, a moment after item data arrives, and only while shown", function()
    local timers, current = {}, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    GC.ForeverUpgrades.Current = function() current = current + 1; return { rows = {}, loading = 0, noScan = true } end
    U.OnItemInfo()                                  -- never opened (retail, or not yet): nothing
    assert.equal(0, #timers)
    U.Show()
    assert.equal(1, current)
    U.OnItemInfo()
    U.OnItemInfo()
    assert.equal(1, #timers)
    timers[1]()
    assert.equal(2, current)
    U.Hide()
    U.OnItemInfo()
    assert.equal(1, #timers)
  end)

  -- Final review M1: an id nobody was waiting for must not itself trigger a rebuild, and an id
  -- that never resolves must not keep the window rebuilding forever.
  it("ignores an item it was not waiting for, and gives up once the loading count stops shrinking", function()
    local timers = {}
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local builds = 0
    GC.ForeverUpgrades.Current = function()
      builds = builds + 1
      return { rows = {}, loading = 1, loadingIds = { [42] = true } }
    end
    U.Show()
    assert.equal(1, builds)
    U.OnItemInfo(7)                      -- not one of the ids the last build is waiting on
    assert.equal(0, #timers)
    U.OnItemInfo(42)                     -- one it IS waiting on
    assert.equal(1, #timers)
    -- Item 42 never actually resolves -- loading stays at 1 every time. Run the storm cap's limit.
    for _ = 1, U.C.STALE_LIMIT do
      timers[#timers]()
      U.OnItemInfo(42)
    end
    local before = #timers
    timers[#timers]()
    U.OnItemInfo(42)
    assert.equal(before, #timers)        -- the storm cap has kicked in: no new timer
    -- Reopening the window resets the cap.
    U.Show()
    U.OnItemInfo(42)
    assert.equal(before + 1, #timers)
  end)
end)
