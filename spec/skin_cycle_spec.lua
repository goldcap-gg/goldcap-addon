local helper = require("spec.spec_helper")

describe("Dev/SkinCycle.lua (/gcskin)", function()
  local GC, reloads, printed

  before_each(function()
    GC = { Kit = { Skins = { ORDER = { "goldcap", "forever", "pixel" } } } }
    GC.db = { settings = { sniper = { skin = "goldcap" } } }
    printed = {}
    GC.Print = function(msg) printed[#printed + 1] = msg end
    reloads = 0
    _G.ReloadUI = function() reloads = reloads + 1 end
    _G.SlashCmdList = {}
    helper.loadModule("Dev/SkinCycle.lua", GC)
  end)

  after_each(function()
    _G.ReloadUI = nil
    _G.SlashCmdList = nil
    _G.SLASH_GOLDCAPSKIN1 = nil
  end)

  it("registers /gcskin", function()
    assert.equal("/gcskin", _G.SLASH_GOLDCAPSKIN1)
  end)

  it("stores the next skin, prints it and reloads once", function()
    SlashCmdList.GOLDCAPSKIN("")
    assert.equal("forever", GC.db.settings.sniper.skin)
    assert.equal(1, reloads)
    assert.equal(1, #printed)
    assert.is_truthy(printed[1]:find("forever", 1, true))
  end)

  it("wraps from the last skin to the first", function()
    GC.db.settings.sniper.skin = "pixel"
    SlashCmdList.GOLDCAPSKIN("")
    assert.equal("goldcap", GC.db.settings.sniper.skin)
    assert.equal(1, reloads)
  end)

  it("treats an unknown id as goldcap", function()
    GC.db.settings.sniper.skin = "nonsense"
    SlashCmdList.GOLDCAPSKIN("")
    assert.equal("forever", GC.db.settings.sniper.skin)
  end)
end)
