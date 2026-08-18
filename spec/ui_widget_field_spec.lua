require("spec.spec_helper")

-- busted runs headless, with no WoW globals, so every spec builds its own widget doubles. Those
-- doubles are repeatedly RICHER than the real widget, and each time that happens a green test
-- proves a contract the client does not have. It has now cost this addon three shipped defects:
--
--   * `Theme.Button:SetLabel` never set `.label`, while every fake did -- so the Sell tab's
--     Post / Repost / Set cost / "Cancel lot?" tooltips, including the only warning that
--     cancelling forfeits a deposit, never rendered once.
--   * a Frame has no `.shown` FIELD, only `:IsShown()`, while every fake implements Show/Hide by
--     writing `self.shown` -- so the posting queue's button read nil in the client and refused
--     to post anything at all, with seven tests proving it worked.
--
-- The fix for each was to make the real widget and the double agree. This guard is what stops
-- the next one: production code may not read a field that only the doubles define.
--
-- Comments are stripped before matching, so the explanations above (and the one at the call site
-- in UI/SellFrame.lua) do not trip it. Stripping is a plain `--` to end-of-line cut, which can
-- also truncate a string literal containing `--`; that can only ever cause this spec to scan
-- LESS text, never to invent a hit, so it is safe in the direction that matters.
describe("widget fields the real client actually has", function()
  local SOURCES = {
    "GoldCap/UI/SellFrame.lua",
    "GoldCap/UI/SniperFrame.lua",
    "GoldCap/UI/SettingsFrame.lua",
    "GoldCap/UI/Theme.lua",
    "GoldCap/UI/ImportDialog.lua",
    "GoldCap/UI/AuctionHouseTab.lua",
    "GoldCap/UI/Tooltip.lua",
    "GoldCap/UI/SellViewModel.lua",
  }

  -- Every field the widget doubles in spec/sell_widget_behavior_spec.lua and friends invent for
  -- their own bookkeeping. A real Frame/FontString/Button exposes none of them; each has a
  -- method that answers the same question, named beside it here so a failure says what to use.
  local DOUBLE_ONLY = {
    shown = "Frame:IsShown()",
    points = "Frame:GetPoint()",
    scripts = "Frame:GetScript(name)",
    children = "Frame:GetChildren()",
  }

  local function stripComments(text)
    return (text:gsub("%-%-[^\n]*", ""))
  end

  local function read(path)
    local file = assert(io.open(path, "r"), path .. " is missing")
    local text = file:read("*a")
    file:close()
    return stripComments(text)
  end

  for _, path in ipairs(SOURCES) do
    it(("%s reads no field that only a test double defines"):format(path), function()
      local text = read(path)
      for field, instead in pairs(DOUBLE_ONLY) do
        local found = text:find("%.".. field .. "%f[%W]")
        assert.is_nil(found,
          ("%s reads `.%s`, which exists only on this suite's widget doubles -- use %s")
            :format(path, field, instead))
      end
    end)
  end
end)
