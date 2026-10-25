-- Source-text wiring assertions (the deliberate style for wiring, see the addon's engineering notes):
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

  it("[wiring] the settings panel exposes the BUY tab's cap", function()
    local text = sourceOf("GoldCap/UI/SettingsFrame.lua")
    assert.is_truthy(text:find('"buyCapPct"', 1, true))
  end)

  it("[wiring] the settings panel builds a VENDOR card with one toggle and a forget button on retail only", function()
    local text = sourceOf("GoldCap/UI/SettingsFrame.lua")
    local at = text:find('GC.L["VENDOR"]', 1, true)
    assert.is_truthy(at, "no VENDOR card")
    assert.is_nil(text:find('"vendorJunk"', 1, true))
    assert.is_truthy(text:find('"vendorWorth"', 1, true))
    assert.is_truthy(text:find('GC.L["Forget kept items"]', 1, true))
    -- The card is built inside an `if not isForeverClient() then` block: the last such guard
    -- before the card's title must not have been closed by an `end` at the same indent.
    local before = text:sub(1, at)
    local guard = before:match(".*()\n  if not isForeverClient%(%) then\n")
    assert.is_truthy(guard, "the VENDOR card is not inside an isForeverClient guard")
    assert.is_nil(before:sub(guard + 1):find("\n  end\n", 1, true), "the guard closed before the VENDOR card")
  end)

  it("defaults: vendorWorth is on, vendorKeep is an empty table, and junk has no setting", function()
    local helper = require("spec.spec_helper")
    local keys = { "CreateFrame", "hooksecurefunc", "SlashCmdList", "Enum" }
    local saved = {}
    for _, k in ipairs(keys) do saved[k] = _G[k] end
    -- Init.lua only needs a frame that takes any call, to register its events.
    _G.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
    _G.hooksecurefunc = function() end
    _G.SlashCmdList = {}
    _G.Enum = { PlayerInteractionType = {} }
    local GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Init.lua", GC)
    for _, k in ipairs(keys) do _G[k] = saved[k] end
    assert.is_nil(GC.DEFAULTS.settings.sniper.vendorJunk)
    assert.is_true(GC.DEFAULTS.settings.sniper.vendorWorth)
    assert.same({}, GC.DEFAULTS.vendorKeep)
  end)
end)
