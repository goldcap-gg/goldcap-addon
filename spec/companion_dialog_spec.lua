local helper = require("spec.spec_helper")

local COMPANION_URL = "https://goldcap.gg/downloads"

describe("CompanionDialog", function()
  local GC

  local function region(kind)
    local f = { kind = kind, shown = false, points = {}, scripts = {} }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetHeight() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:SetFrameStrata(strata) self.strata = strata end
    function f:SetFontObject() end
    function f:SetJustifyH() end
    function f:SetWordWrap() end
    function f:SetAutoFocus() end
    function f:SetFocus() end
    function f:HighlightText() self.highlighted = true end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text or "" end
    function f:CreateFontString() return region("FontString") end
    function f:CreateTexture() return region("Texture") end
    f.TitleText = { SetText = function(_, t) f.titleText = t end }
    return f
  end

  before_each(function()
    _G.CreateFrame = function(kind, name, parent, template)
      local f = region(kind)
      f.name, f.parent, f.template = name, parent, template
      if name and name ~= "" then _G[name] = f end -- real WoW auto-publishes named frames
      return f
    end
    _G.UIParent = {}
    _G.UISpecialFrames = {}
    _G.ChatFontNormal = {}
    GC = { slashHandlers = {}, UI = {} }
    helper.loadModule("UI/CompanionDialog.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
    _G.UIParent = nil
    _G.UISpecialFrames = nil
    _G.ChatFontNormal = nil
    _G.GoldCapCompanionDialog = nil
  end)

  it("registers /goldcap companion as a slash handler", function()
    assert.is_function(GC.slashHandlers.companion)
  end)

  it("shows the dialog with the Companion download link, focused and selected", function()
    GC.slashHandlers.companion()
    local dialog = _G.GoldCapCompanionDialog
    assert.is_true(dialog.shown)
    assert.equal(COMPANION_URL, dialog.edit:GetText())
    assert.is_true(dialog.edit.highlighted)
    -- Reachable from a click inside the docked AH window (SniperFrame.lua), which sits at the
    -- AH's own strata with a high frame level -- without DIALOG strata this dialog opens behind
    -- it, invisible to the player. Same rule as SniperFrame.lua/SellFrame.lua's own dialogs.
    assert.equal("DIALOG", dialog.strata)
  end)

  it("registers the dialog with UISpecialFrames so Escape closes it", function()
    GC.CompanionUI.Show()
    local found = false
    for _, name in ipairs(_G.UISpecialFrames) do
      if name == "GoldCapCompanionDialog" then found = true end
    end
    assert.is_true(found)
  end)

  it("restores the URL if the player edits the EditBox", function()
    GC.CompanionUI.Show()
    local edit = _G.GoldCapCompanionDialog.edit
    edit.text = "something else entirely"
    edit.scripts.OnTextChanged(edit)
    assert.equal(COMPANION_URL, edit:GetText())
  end)

  it("does not touch the text when it still matches the URL", function()
    GC.CompanionUI.Show()
    local edit = _G.GoldCapCompanionDialog.edit
    edit.highlighted = false
    edit.scripts.OnTextChanged(edit)
    assert.is_false(edit.highlighted) -- no redundant re-highlight when nothing changed
  end)

  it("closes on Escape via the EditBox's OnEscapePressed", function()
    GC.CompanionUI.Show()
    local dialog = _G.GoldCapCompanionDialog
    dialog.edit.scripts.OnEscapePressed()
    assert.is_false(dialog.shown)
  end)

  it("has a Close button that hides the dialog", function()
    GC.CompanionUI.Show()
    local dialog = _G.GoldCapCompanionDialog
    assert.equal("Close", dialog.closeBtn.text)
    dialog.closeBtn.scripts.OnClick()
    assert.is_false(dialog.shown)
  end)

  it("exposes GC.CompanionUI.Hide()", function()
    GC.CompanionUI.Show()
    GC.CompanionUI.Hide()
    assert.is_false(_G.GoldCapCompanionDialog.shown)
  end)
end)
