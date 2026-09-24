local helper = require("spec.spec_helper")

describe("GC.Util.CoinText", function()
  local saved = {}
  before_each(function()
    saved.global = _G.GetCoinTextureString
    saved.currency = _G.C_CurrencyInfo
  end)
  after_each(function()
    _G.GetCoinTextureString = saved.global
    _G.C_CurrencyInfo = saved.currency
  end)

  it("prefers the global GetCoinTextureString, which retail has", function()
    _G.GetCoinTextureString = function(c) return "g:" .. c end
    _G.C_CurrencyInfo = { GetCoinTextureString = function() error("C_CurrencyInfo must not be called") end }
    local GC = helper.loadModule("Core/Util.lua")
    assert.equal("g:12345", GC.Util.CoinText(12345))
  end)

  it("uses C_CurrencyInfo.GetCoinTextureString when the global is gone", function()
    _G.GetCoinTextureString = nil
    _G.C_CurrencyInfo = { GetCoinTextureString = function(c) return "ci:" .. c end }
    local GC = helper.loadModule("Core/Util.lua")
    assert.equal("ci:250", GC.Util.CoinText(250))
  end)

  it("formats by itself when the client has neither (WoW: Forever)", function()
    _G.C_CurrencyInfo = nil
    _G.GetCoinTextureString = nil
    local GC = helper.loadModule("Core/Util.lua")
    local G, S, C = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t", "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
    assert.equal("12" .. G .. " 34" .. S .. " 56" .. C, GC.Util.CoinText(123456))
    assert.equal("5" .. S, GC.Util.CoinText(500))
    assert.equal("0" .. C, GC.Util.CoinText(0))
    assert.equal("7" .. C, GC.Util.CoinText(7))
    assert.equal("1" .. G, GC.Util.CoinText(10000))
    assert.equal("-3" .. S, GC.Util.CoinText(-300))
    assert.equal("99999999" .. G, GC.Util.CoinText(999999990000))
    -- Sign comes from the ROUNDED magnitude: a value that rounds to zero has no sign.
    assert.equal("0" .. C, GC.Util.CoinText(-0.4))
  end)

  it("FormatMoney keeps its compact forms and uses the helper under a gold", function()
    _G.C_CurrencyInfo = nil
    _G.GetCoinTextureString = function(c) return "g:" .. c end
    local GC = helper.loadModule("Core/Util.lua")
    assert.equal("150g", GC.Util.FormatMoney(1500000))
    assert.equal("12g34s", GC.Util.FormatMoney(123400))
    assert.equal("g:4321", GC.Util.FormatMoney(4321))
  end)
end)

describe("no bare GetCoinTextureString", function()
  it("is called only inside Core/Util.lua", function()
    local offenders = {}
    local p = io.popen("grep -rn 'GetCoinTextureString' GoldCap --include='*.lua'")
    for line in p:lines() do
      local file = line:match("^([^:]+):")
      local code = line:gsub("^[^:]+:%d+:", "")
      local isComment = code:match("^%s*%-%-")
      local isCall = code:find("GetCoinTextureString%s*%(")
      if file ~= "GoldCap/Core/Util.lua" and isCall and not isComment then
        offenders[#offenders + 1] = line
      end
    end
    p:close()
    assert.same({}, offenders)
  end)
end)
