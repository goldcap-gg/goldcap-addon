local helper = require("spec.spec_helper")

-- Option (a) from the Task 1 brief: build a REAL Theme.Button against stubbed globals,
-- the way the client would build it, rather than faking Theme.Button and asserting the
-- fake's own bookkeeping. Every spec that drives UI/SellFrame.lua fakes GC.Theme.Button
-- with its own `function w:SetLabel(t) self.label = t end` (sell_widget_behavior_spec.lua,
-- sell_action_safety_spec.lua, sell_bag_to_post_spec.lua, auto_verify_spec.lua,
-- watch_loop_spec.lua, auction_house_tab_spec.lua) -- so ~10 assertions of the shape
-- `assert.equal("Post", rows[1].action.label)` were proving a contract the real widget
-- never had. This spec is the one place `.label` is asserted against the ACTUAL
-- `GC.Theme.Button`, so a regression here cannot hide behind a richer fake again.
--
-- (b) -- a spec asserting the real Button and the fakes expose the same method/field
-- names -- was considered instead. It only proves interface SHAPE (both have a
-- `SetLabel` key); it would not have caught this bug, because the real Button DID have
-- a `SetLabel` method, it just did not do the one thing every caller relied on it for.
-- Only exercising the real behaviour catches that.
describe("Theme.Button real-widget label contract", function()
  local GC

  local function stubFrame()
    local f = { points = {}, scripts = {} }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:HookScript(name, fn) self.scripts[name] = fn end
    function f:RegisterForClicks(kind) self.clicks = kind end
    function f:RegisterForDrag(kind) self.drag = kind end
    function f:EnableMouse(enabled) self.mouseEnabled = enabled end
    function f:SetJustifyH(v) self.justify = v end
    function f:SetWordWrap(v) self.wordWrap = v end
    function f:SetText(text) self.rawText = text end
    function f:GetText() return self.rawText or "" end
    function f:SetTextColor(...) self.color = { ... } end
    function f:SetFont(path, size, flags) self.font = { path, size, flags } end
    function f:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function f:SetColorTexture(...) self.colorTexture = { ... } end
    function f:SetBlendMode(mode) self.blend = mode end
    function f:SetAllPoints(rel) self.allPoints = rel end
    function f:SetAlpha(a) self.alpha = a end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture() return stubFrame() end
    function f:CreateFontString() return stubFrame() end
    return f
  end

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return stubFrame() end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
  end)

  it("assigns .label alongside the FontString text a real button draws", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "primary")
    assert.is_nil(btn.label) -- nothing labelled it yet
    btn:SetLabel("Post")
    assert.equal("Post", btn.label)
    assert.equal("Post", btn.text.rawText)
  end)

  it("keeps .label current across repeated SetLabel calls, matching pooled rows rebound every render", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "ghost")
    btn:SetLabel("Repost")
    assert.equal("Repost", btn.label)
    btn:SetLabel("Cancel lot?")
    assert.equal("Cancel lot?", btn.label)
  end)

  -- GC.Sniper.SetDocked blanks the docked window's own title through TitleBar's return
  -- value. The first shipped version returned only {gear, close}: `titleBar.title` was nil,
  -- the nil-guard skipped silently, and the docked window kept its duplicate title clipped
  -- under the auction house portrait -- the same real-widget-poorer-than-the-caller-assumed
  -- class this spec file exists for.
  it("returns the title FontString so docked mode can blank and restore it", function()
    local parent = stubFrame()
    local bar = GC.Theme.TitleBar(parent, "GoldCap Sniper")
    assert.is_truthy(bar.title)
    assert.equal("GoldCap Sniper", bar.title.rawText)
    bar.title:SetText("")
    assert.equal("", bar.title.rawText)
    assert.is_truthy(bar.bar)
  end)

  -- The exact failure mode: UI/SellFrame.lua's ACTION_HELP tooltip keys off
  -- `self.label` inside the button's own OnEnter hook.
  it("makes a hand-rolled ACTION_HELP-style lookup work against the real widget", function()
    local ACTION_HELP = { Post = "Lists what is sitting in your bags." }
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "ghost")
    btn:SetLabel("Post")
    assert.equal("Lists what is sitting in your bags.", ACTION_HELP[btn.label])
  end)
end)
