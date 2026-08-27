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

  it("shows a signed trend when the import carries one", function()
    local lines = GC.Tooltip.BuildLines({ mv = 1000, sold = 5, trend = -12, ts = 1000, source = "import" }, 2000)
    assert.equal("24h trend", lines[2].left)
    assert.equal("-12%", lines[2].right)
  end)

  it("signs a positive trend too", function()
    local lines = GC.Tooltip.BuildLines({ mv = 1000, trend = 7, ts = 1000, source = "import" }, 2000)
    assert.equal("+7%", lines[2].right)
  end)

  it("omits the trend line when there is none or it is flat", function()
    for _, value in ipairs({ { mv = 1000, ts = 1000 }, { mv = 1000, trend = 0, ts = 1000 } }) do
      for _, ln in ipairs(GC.Tooltip.BuildLines(value, 2000)) do
        assert.not_equal("24h trend", ln.left)
      end
    end
  end)

  it("shows what you paid when stock is held", function()
    local lines = GC.Tooltip.BuildLines({ mv = 1000, ts = 1000, source = "import" }, 2000, { unitCost = 640 })
    assert.equal("money", lines[#lines].kind)
    assert.equal("You paid", lines[#lines].label)
    assert.equal(640, lines[#lines].copper)
  end)

  it("always labels bundled data with its region and age", function()
    local lines = GC.Tooltip.BuildLines({ mv = 1000, ts = 0, source = "bundled" }, 3600, { region = "kr" })
    assert.equal("Bundled KR data", lines[#lines].left)
    assert.equal("1h", lines[#lines].right) -- FormatAge: "<1h" is strictly under an hour
    local fresh = GC.Tooltip.BuildLines({ mv = 1000, ts = 0, source = "bundled" }, 60, { region = "us" })
    assert.equal("<1h", fresh[#fresh].right)
  end)

  it("labels bundled data sensibly when the region is unknown", function()
    local lines = GC.Tooltip.BuildLines({ mv = 1000, ts = 0, source = "bundled" }, 3600)
    assert.equal("Bundled data", lines[#lines].left)
  end)

  it("reads the region without walking the item tables", function()
    local text = assert(io.open("GoldCap/UI/Tooltip.lua")):read("*a")
    assert.is_nil(text:find("GetStatus", 1, true),
      "the tooltip path must not call GetStatus -- it counts every bundled and imported item")
    assert.is_truthy(text:find("GC.Data.Region", 1, true))
  end)

  it("still hides the age line for fresh imported data", function()
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0, source = "import" }, 3600)
    assert.equal(1, #lines)
  end)
end)
