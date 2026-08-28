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
    function f:SetMaxLines(n) self.maxLines = n end
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

  -- A CENTER-anchored FontString has no width: it grows both ways until the label fits,
  -- straight over whatever sits beside the button. English hid it (every label is short);
  -- "Set cost" as "Задати собівартість" in the Sell tab's 88px action column did not -- it
  -- painted across the price column to its left. Bounded LEFT..RIGHT, the engine truncates
  -- inside the button instead. Asserted on the REAL widget for the same reason the rest of
  -- this file is: a fake with a `SetPoint` that records nothing proves none of it.
  it("bounds the label to the button's own width so a long translation cannot paint outside it", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "ghost")
    local sides = {}
    for _, point in ipairs(btn.text.points) do sides[point[1]] = point end
    assert.is_truthy(sides.LEFT)
    assert.is_truthy(sides.RIGHT)
    assert.is_nil(sides.CENTER) -- an unbounded CENTER anchor is exactly the bug
    assert.equal(btn, sides.LEFT[2])
    assert.equal(btn, sides.RIGHT[2])
    -- Flush to both edges: callers size these buttons to their longest English label to the
    -- pixel (row.action's 86 fits "Cancel lot?" at 85.8px), so an inset here would clip a
    -- label that fits today. Symmetric either way, so a centred label stays centred.
    assert.equal(0, sides.LEFT[4])
    assert.equal(0, sides.RIGHT[4])
  end)

  -- Word wrap off alone is not enough: a label that wraps inside a ~22px button draws NOTHING,
  -- which is worse than a clipped one. Both calls, or neither is worth making.
  it("keeps a bounded label on one line rather than wrapping it out of sight", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "primary")
    assert.is_false(btn.text.wordWrap)
    assert.equal(1, btn.text.maxLines)
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

  -- Task 2 restyle: SetUppercase changes only the drawn FontString text -- `.label` stays the
  -- caller's exact source string, since ACTION_HELP-style lookups and pooled-row rebinding
  -- both read `.label` back, not the FontString.
  it("draws the label upper-case without changing .label when SetUppercase(true) is on", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "primary")
    btn:SetUppercase(true)
    btn:SetLabel("Post")
    assert.equal("Post", btn.label)
    assert.equal("POST", btn.text.rawText)
  end)

  it("draws the label as given once SetUppercase(false) turns it back off", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "primary")
    btn:SetUppercase(true)
    btn:SetLabel("Post")
    assert.equal("POST", btn.text.rawText)
    btn:SetUppercase(false)
    assert.equal("Post", btn.text.rawText)
    assert.equal("Post", btn.label) -- .label never moved
  end)

  it("re-draws an already-labelled button upper-case when SetUppercase(true) runs after SetLabel", function()
    local parent = stubFrame()
    local btn = GC.Theme.Button(parent, "primary")
    btn:SetLabel("Post")
    assert.equal("Post", btn.text.rawText)
    btn:SetUppercase(true)
    assert.equal("POST", btn.text.rawText)
    assert.equal("Post", btn.label)
  end)
end)
