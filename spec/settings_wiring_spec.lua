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

  it("[wiring] a save is stamped with the spike-threshold default", function()
    -- ApplyDefaults fills DEFAULTS keys into existing saves on login; without this entry the
    -- new setting would read nil forever and both readers would silently fall back.
    local text = sourceOf("GoldCap/Core/Init.lua")
    assert.is_truthy(text:find("spikeTrendPct = 30", 1, true))
  end)
end)
