local helper = require("spec.spec_helper")

-- Money in the Sell view, in the game's own coins with gold grouped in thousands (owner,
-- 2026-10-09): what GC.Sell._FormatAmount writes into every figure the tab shows.
describe("the Sell view's money", function()
  local G = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
  local S = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
  local C = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
  local saved

  local function load()
    local GC = helper.loadModule("Core/Util.lua")
    GC.L = setmetatable({}, { __index = function(_, key) return key end })
    helper.loadSell(GC)
    return GC
  end

  before_each(function()
    saved = { _G.GetCoinTextureString, _G.C_CurrencyInfo, _G.BreakUpLargeNumbers }
    _G.GetCoinTextureString, _G.C_CurrencyInfo, _G.BreakUpLargeNumbers = nil, nil, nil
  end)
  after_each(function()
    _G.GetCoinTextureString, _G.C_CurrencyInfo, _G.BreakUpLargeNumbers = saved[1], saved[2], saved[3]
  end)

  it("writes gold and silver under a thousand gold, and drops copper", function()
    local GC = load()
    assert.equal("12" .. G .. " 5" .. S, GC.Sell._FormatAmount(120512))
    assert.equal("999" .. G .. " 99" .. S, GC.Sell._FormatAmount(9999999))
    assert.equal("43" .. G, GC.Sell._FormatAmount(430000))
  end)

  it("groups gold in thousands and drops the silver from a thousand gold up", function()
    local GC = load()
    assert.equal("2,450" .. G, GC.Sell._FormatAmount(24505000))
    -- Past 2^31 copper, where WoW's own %d raises "integer overflow".
    assert.equal("2,147,483" .. G, GC.Sell._FormatAmount(21474836470))
  end)

  it("groups with the client's own separator where the client has one", function()
    _G.BreakUpLargeNumbers = function(n) return (tostring(n):gsub("^(%d+)(%d%d%d)$", "%1.%2")) end
    local GC = load()
    assert.equal("2.450" .. G, GC.Sell._FormatAmount(24505000))
  end)

  it("keeps silver and copper coins under a gold, and a sign in front", function()
    local GC = load()
    assert.equal("45" .. S .. " 50" .. C, GC.Sell._FormatAmount(4550))
    assert.equal("-1" .. G .. " 15" .. S, GC.Sell._FormatAmount(-11500))
  end)
end)
