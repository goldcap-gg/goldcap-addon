local helper = require("spec.spec_helper")

-- The vendor list dialog: WoW has no clipboard API, so a copyable list is an EditBox holding the
-- text, focused and fully selected, the way UI/CompanionDialog.lua hands over the download link.
describe("VendorListDialog", function()
  local GC

  local function region(kind)
    local f = { kind = kind, shown = false, points = {}, scripts = {}, textValue = "" }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetHeight() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:SetFrameStrata(strata) self.strata = strata end
    function f:SetToplevel(top) self.toplevel = top end
    function f:SetMultiLine() end
    function f:SetFontObject() end
    function f:SetJustifyH() end
    function f:SetWordWrap() end
    function f:SetAutoFocus() end
    function f:SetFocus() self.focused = true end
    function f:HighlightText() self.highlighted = true end
    function f:Raise() self.raised = true end
    function f:SetScrollChild(child) self.child = child end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetText(t)
      self.textValue = t
      if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function f:GetText() return self.textValue end
    function f:CreateFontString() return region("FontString") end
    function f:CreateTexture() return region("Texture") end
    f.TitleText = { SetText = function(_, t) f.titleText = t end }
    return f
  end

  before_each(function()
    _G.CreateFrame = function(kind, name)
      local f = region(kind)
      if name and name ~= "" then _G[name] = f end -- real WoW auto-publishes named frames
      return f
    end
    _G.UIParent, _G.UISpecialFrames, _G.ChatFontNormal = {}, {}, {}
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/VendorListDialog.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame, _G.UIParent, _G.UISpecialFrames, _G.ChatFontNormal = nil, nil, nil, nil
    _G.GoldCapVendorListDialog = nil
  end)

  it("shows the list, focused and selected, ready for Ctrl+C", function()
    GC.UI.ShowVendorList("5× Water · 25c each · 1s25c\nTotal: 1s25c")
    local dialog = _G.GoldCapVendorListDialog
    assert.is_true(dialog.shown)
    assert.equal("Vendor list", dialog.titleText)
    assert.equal("5× Water · 25c each · 1s25c\nTotal: 1s25c", dialog.edit:GetText())
    assert.is_true(dialog.edit.focused)
    assert.is_true(dialog.edit.highlighted)
    -- Opened from the BUY band inside the docked auction house window, which sits at the AH's own
    -- strata: a MEDIUM dialog comes up behind it and reads as a button that did nothing.
    assert.equal("DIALOG", dialog.strata)
    assert.is_true(dialog.toplevel)
    assert.is_true(dialog.raised)
  end)

  it("puts the list straight back when the player types into it", function()
    GC.UI.ShowVendorList("5× Water · 25c each · 1s25c")
    local edit = _G.GoldCapVendorListDialog.edit
    edit.highlighted = false
    edit:SetText("oops")
    assert.equal("5× Water · 25c each · 1s25c", edit:GetText())
    assert.is_true(edit.highlighted)
  end)

  it("shows a second run's list rather than the first one's", function()
    GC.UI.ShowVendorList("first")
    GC.UI.ShowVendorList("second")
    assert.equal("second", _G.GoldCapVendorListDialog.edit:GetText())
  end)

  it("shows nothing at all when there is no list to show", function()
    GC.UI.ShowVendorList(nil)
    assert.is_nil(_G.GoldCapVendorListDialog)
  end)

  it("shows nothing at all for an empty list", function()
    GC.UI.ShowVendorList("")
    assert.is_nil(_G.GoldCapVendorListDialog)
  end)

  it("closes on Escape from the EditBox and from the Close button", function()
    GC.UI.ShowVendorList("x")
    local dialog = _G.GoldCapVendorListDialog
    dialog.edit.scripts.OnEscapePressed()
    assert.is_false(dialog.shown)
    GC.UI.ShowVendorList("x")
    dialog.closeBtn.scripts.OnClick()
    assert.is_false(dialog.shown)
  end)

  it("registers the dialog with UISpecialFrames so Escape closes it", function()
    GC.UI.ShowVendorList("x")
    local found = false
    for _, name in ipairs(_G.UISpecialFrames) do
      if name == "GoldCapVendorListDialog" then found = true end
    end
    assert.is_true(found)
  end)
end)
