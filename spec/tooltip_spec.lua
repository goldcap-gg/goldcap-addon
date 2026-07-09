local helper = require("spec.spec_helper")

describe("Tooltip.BuildLines", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Tooltip.lua", GC)
  end)

  it("returns nil without a value", function()
    assert.is_nil(GC.Tooltip.BuildLines(nil, 0))
  end)

  it("builds money + sold lines for fresh commodity data", function()
    local lines = GC.Tooltip.BuildLines({ mv = 123400, sold = 52.34, ts = 1000 }, 2000)
    assert.equal(2, #lines)
    assert.equal("money", lines[1].kind)
    assert.equal("GoldCap value", lines[1].label)
    assert.equal(123400, lines[1].copper)
    assert.equal("Sold per day", lines[2].left)
    assert.equal("52.3", lines[2].right)
  end)

  it("falls back to listings for item data", function()
    local lines = GC.Tooltip.BuildLines({ mv = 990000, listings = 14, ts = 1000 }, 2000)
    assert.equal("Listings", lines[2].left)
    assert.equal("14", lines[2].right)
  end)

  it("appends an age line when data is older than 48h", function()
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 3 * 86400)
    assert.equal("GoldCap data age", lines[#lines].left)
    assert.equal("3d", lines[#lines].right)
  end)

  it("omits the age line for fresh data", function()
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 3600)
    assert.equal(1, #lines)
  end)

  it("omits the age line at exactly 48h", function()
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 48 * 3600)
    assert.equal(1, #lines)
  end)
end)
