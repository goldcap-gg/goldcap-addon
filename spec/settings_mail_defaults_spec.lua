local helper = require("spec.spec_helper")

-- The four MAIL settings the Collect button reads (UI/MailCollect.lua, Enabled). Core/Init.lua
-- only builds GC.DEFAULTS and wires events when loaded; the frames it creates are stand-ins here.
describe("MAIL settings defaults", function()
  local GC, savedGlobals

  local function stub()
    return setmetatable({}, { __index = function() return function() end end })
  end

  before_each(function()
    savedGlobals = { CreateFrame = _G.CreateFrame, hooksecurefunc = _G.hooksecurefunc,
      SlashCmdList = _G.SlashCmdList }
    _G.CreateFrame = function() return stub() end
    _G.hooksecurefunc = function() end
    _G.SlashCmdList = {}
    GC = {}
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Init.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame, _G.hooksecurefunc, _G.SlashCmdList =
      savedGlobals.CreateFrame, savedGlobals.hooksecurefunc, savedGlobals.SlashCmdList
  end)

  it("switches all four kinds of mail on", function()
    local sniper = GC.DEFAULTS.settings.sniper
    for _, key in ipairs({ "collectSales", "collectReturns", "collectPurchases", "collectPlayers" }) do
      assert.is_true(sniper[key], key)
    end
  end)

  it("keeps a saved false and fills a missing key with true", function()
    local saved = { settings = { sniper = { collectSales = false } } }
    GC.Util.ApplyDefaults(saved, GC.DEFAULTS)
    assert.is_false(saved.settings.sniper.collectSales)
    assert.is_true(saved.settings.sniper.collectReturns)
    assert.is_true(saved.settings.sniper.collectPurchases)
    assert.is_true(saved.settings.sniper.collectPlayers)
  end)
end)
