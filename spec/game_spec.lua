local helper = require("spec.spec_helper")

describe("Client passport", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Game.lua")
  end)

  local function api(version, build, toc, region)
    return {
      GetBuildInfo = function() return version, build, "Sep 23 2026", toc end,
      GetCurrentRegion = function() return region end,
    }
  end

  it("stamps interface, full build and region id", function()
    local p = GC.Game.Passport(api("1.60.1", "69977", nil, 90))
    assert.is_nil(p) -- no interface number, no passport
    p = GC.Game.Passport(api("1.60.1", "69977", 16001, 90))
    assert.same({ interface = 16001, build = "1.60.1.69977", regionId = 90 }, p)
  end)

  it("tells retail from other games by interface number", function()
    assert.is_true(GC.Game.IsRetail(GC.Game.Passport(api("12.1.0", "69933", 120100, 3))))
    assert.is_false(GC.Game.IsRetail(GC.Game.Passport(api("1.60.1", "69977", 16001, 90))))
    assert.equal(100000, GC.Game.RETAIL_MIN_INTERFACE)
  end)

  it("leaves regionId out when the client cannot say", function()
    local p = GC.Game.Passport(api("12.1.0", "69933", 120100, nil))
    assert.equal(120100, p.interface)
    assert.is_nil(p.regionId)
  end)

  it("returns nil instead of erroring when GetBuildInfo is missing or fails", function()
    assert.is_nil(GC.Game.Passport({}))
    assert.is_nil(GC.Game.Passport({ GetBuildInfo = function() error("boom") end }))
    assert.is_nil(GC.Game.Passport({ GetBuildInfo = function() return nil end }))
  end)

  it("treats no passport as retail, as the companion does", function()
    assert.is_true(GC.Game.IsRetail(nil))
  end)

  it("recognises WoW: Forever by its interface number", function()
    assert.is_true(GC.Game.IsForever({ interface = 16001, build = "1.60.1.69977" }))
    assert.is_true(GC.Game.IsForever({ interface = 16999, build = "1.69.9.1" }))
    assert.is_false(GC.Game.IsForever({ interface = 120100, build = "12.1.0.69933" }))
    assert.is_false(GC.Game.IsForever({ interface = 11508, build = "1.15.8.1" }))
    assert.is_false(GC.Game.IsForever(nil))
  end)
end)
