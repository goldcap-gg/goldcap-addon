local helper = require("spec.spec_helper")

-- BUY 2.0's price box (UI/BuyCapEditor.lua): the player types the most one unit of a line may
-- cost. Parsing is GC.Util.ParseMoney's; this is about the box itself.
describe("BuyCapEditor", function()
  local GC, committed

  local function region(kind)
    local r = { kind = kind, visible = true, enabled = true, scripts = {}, points = {} }
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:SetFrameStrata(s) self.strata = s end
    function r:SetFrameLevel() end
    function r:EnableMouse(on) self.mouse = on end
    function r:SetJustifyH() end
    function r:SetWordWrap(on) self.wrap = on end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:SetTextColor(...) self.colorValue = { ... } end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    return r
  end

  local function button(parent)
    local b = region("Button", parent)
    b.text = region("FontString", b)
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    return b
  end

  local function editBox(parent)
    local e = region("EditBox", parent)
    function e:SetAutoFocus(on) self.autoFocus = on end
    function e:SetFont() end
    function e:SetFocus() self.focused = true end
    function e:ClearFocus() self.focused = false end
    function e:HasFocus() return self.focused == true end
    return e
  end

  before_each(function()
    _G.CreateFrame = function(kind, _, parent)
      if kind == "EditBox" then return editBox(parent) end
      return region(kind, parent)
    end
    _G.UIParent = region("Frame")
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    GC = helper.loadModule("Core/Util.lua")
    GC.Theme = { MEDIA = "", FONT_UI = "f",
      color = { fg = { 1, 1, 1 }, fgDim = { 0.5, 0.5, 0.5 }, red = { 1, 0, 0 }, panel = { 0, 0, 0 },
                bg = { 0, 0, 0 }, border = { 1, 1, 1, 0.1 } },
      pad = { s = 8, m = 12 },
      Label = function(p) return region("FontString", p) end,
      Num = function(p) return region("FontString", p) end,
      Button = function(p) return button(p) end,
      SlicedTexture = function(p) return region("Texture", p) end,
      Scale = function() return 1 end,
    }
    helper.loadModule("UI/BuyCapEditor.lua", GC)
    committed = "untouched"
    GC.BuyCapEditor.Open(region("Frame"), { title = "Cap for Linen Cloth", current = 91,
      onCommit = function(copper) committed = copper end })
  end)

  after_each(function()
    _G.CreateFrame, _G.UIParent, _G.GetCoinTextureString = nil, nil, nil
  end)

  local function typeAndSet(text)
    local f = GC.BuyCapEditor._frame
    f.box:SetText(text)
    f.box.scripts.OnTextChanged(f.box, true)
    f.set.scripts.OnClick(f.set)
  end

  it("opens on the line's current cap, over what it covers, with the box in focus", function()
    local f = GC.BuyCapEditor._frame
    assert.equal("91c", f.box:GetText())
    assert.equal("Cap for Linen Cloth", f.title:GetText())
    assert.equal("DIALOG", f.strata)
    assert.is_true(f.mouse)
    assert.is_true(f.box:HasFocus())
    assert.equal("Set cap", f.set.label)
    assert.equal("Cancel", f.cancel.label)
  end)

  it("writes a cap in gold and silver the way a player types it", function()
    GC.BuyCapEditor.Open(region("Frame"), { title = "x", current = 125000, onCommit = function() end })
    assert.equal("12g 50s", GC.BuyCapEditor._frame.box:GetText())
  end)

  it("commits a price the player typed and closes", function()
    typeAndSet("1s 40c")
    assert.equal(140, committed)
    assert.is_false(GC.BuyCapEditor._frame:IsShown())
  end)

  -- Review Focus 4: a bare number is gold, as in every other GoldCap box -- and shows its coins
  -- before Set, because "90" meaning 90 gold is exactly the surprise a preview exists for.
  it("reads a bare number as gold, and shows it before Set", function()
    local f = GC.BuyCapEditor._frame
    f.box:SetText("90"); f.box.scripts.OnTextChanged(f.box, true)
    assert.equal(GC.Util.CoinText(900000), f.preview:GetText())
    assert.equal("untouched", committed)
  end)

  for _, bad in ipairs({ "abc", "0", "-5", "12g 5g", "" }) do
    it(("refuses %q and says how to type it"):format(bad), function()
      typeAndSet(bad)
      assert.equal("untouched", committed)
      assert.equal("Could not read that amount. Type it like 12g 50s.", GC.BuyCapEditor._frame.preview:GetText())
      assert.is_true(GC.BuyCapEditor._frame:IsShown())
    end)
  end

  it("Escape closes without committing", function()
    local f = GC.BuyCapEditor._frame
    f.box.scripts.OnEscapePressed(f.box)
    assert.equal("untouched", committed)
    assert.is_false(f:IsShown())
  end)

  it("Cancel closes without committing", function()
    local f = GC.BuyCapEditor._frame
    f.cancel.scripts.OnClick(f.cancel)
    assert.equal("untouched", committed)
    assert.is_false(f:IsShown())
  end)

  it("Enter commits like Set", function()
    local f = GC.BuyCapEditor._frame
    f.box:SetText("2s"); f.box.scripts.OnEnterPressed(f.box)
    assert.equal(200, committed)
  end)

  -- The owner's rule: nothing is cut short. The warning wraps inside the box, which grows to it.
  it("wraps its title and its warning rather than cutting them", function()
    local f = GC.BuyCapEditor._frame
    assert.is_true(f.title.wrap)
    assert.is_true(f.preview.wrap)
  end)

  -- The same popup asks the BUY tab's list questions (UI/BuyLists.lua): a name, and "delete?".
  describe("for a list", function()
    it("asks for a name over the list, opening on the name it has, and takes what is typed", function()
      local named, anchor = "untouched", region("Frame")
      GC.BuyCapEditor.Open(anchor, { over = true, title = "Name this list", text = "List 2", setLabel = "Save",
        onCommit = function(text) named = text end })
      local f = GC.BuyCapEditor._frame
      assert.equal("List 2", f.box:GetText())
      assert.equal("Save", f.set.label)
      assert.same({ "TOPLEFT", anchor, "TOPLEFT", 0, 0 }, f.points[#f.points])
      assert.is_true(f.box:HasFocus())
      f.box:SetText("Herbs"); f.box.scripts.OnTextChanged(f.box, true)
      assert.equal("", f.preview:GetText()) -- a name has no coins to preview
      f.box.scripts.OnEnterPressed(f.box)
      assert.equal("Herbs", named)
      assert.is_false(f:IsShown())
    end)

    it("keeps the name as it was on Escape", function()
      local named = "untouched"
      GC.BuyCapEditor.Open(region("Frame"), { text = "List 2", onCommit = function(text) named = text end })
      local f = GC.BuyCapEditor._frame
      f.box.scripts.OnEscapePressed(f.box)
      assert.equal("untouched", named)
    end)

    it("asks yes or no with no box, and then opens on a cap again as it always did", function()
      local answered = false
      GC.BuyCapEditor.Open(region("Frame"), { box = false, danger = true, title = "Delete Herbs?",
        setLabel = "Delete", onCommit = function(yes) answered = yes end })
      local f = GC.BuyCapEditor._frame
      assert.is_false(f.box:IsShown())
      assert.equal("Delete", f.set.label)
      f.set.scripts.OnClick(f.set)
      assert.is_true(answered)
      GC.BuyCapEditor.Open(region("Frame"), { title = "x", current = 140, onCommit = function() end })
      assert.is_true(f.box:IsShown())
      assert.equal("1s 40c", f.box:GetText())
      assert.equal("Set cap", f.set.label)
    end)
  end)
end)
