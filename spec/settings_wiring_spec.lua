-- Source-text wiring assertions (the deliberate style for wiring, see addon/AGENTS.md):
-- the settings panel's fieldRow binder and Core/Init.lua's ApplyDefaults are both already
-- covered behaviourally; what can silently go missing is the one line that enrolls a key in
-- each of them.
describe("Settings wiring", function()
  local function sourceOf(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
  end

  it("[wiring] the settings panel exposes the absorb window and the spike threshold", function()
    local text = sourceOf("GoldCap/UI/SettingsFrame.lua")
    assert.is_truthy(text:find('"wallAbsorbHours"', 1, true))
    assert.is_truthy(text:find('"spikeTrendPct"', 1, true))
  end)

  -- The threshold deflates the price a resale is projected to EXIT at -- SniperDecision's
  -- release ceiling, and the stored target the Sell queue posts against. The market value is
  -- never touched, and the help had said it was for as long as the field existed.
  it("[wiring] the spike threshold's help names the resale exit, not the market value", function()
    local text = sourceOf("GoldCap/UI/SettingsFrame.lua")
    assert.is_truthy(text:find("resale exit price is treated as spike-inflated", 1, true))
    assert.is_nil(text:find("market value is treated as a spike", 1, true))
  end)

  it("[wiring] a save is stamped with the spike-threshold default", function()
    -- ApplyDefaults fills DEFAULTS keys into existing saves on login; without this entry the
    -- new setting would read nil forever and both readers would silently fall back.
    local text = sourceOf("GoldCap/Core/Init.lua")
    assert.is_truthy(text:find("spikeTrendPct = 30", 1, true))
  end)
end)
