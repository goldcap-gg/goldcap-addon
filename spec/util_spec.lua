local helper = require("spec.spec_helper")

describe("Util", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
  end)

  describe("ApplyDefaults", function()
    it("fills missing keys recursively without clobbering existing", function()
      local dst = { settings = { tooltip = false } }
      GC.Util.ApplyDefaults(dst, { dbVersion = 1, settings = { tooltip = true, sound = true } })
      assert.equal(1, dst.dbVersion)
      assert.equal(false, dst.settings.tooltip) -- preserved
      assert.equal(true, dst.settings.sound)    -- filled
    end)

    it("replaces non-table values where a table is expected", function()
      local dst = { settings = "corrupt" }
      GC.Util.ApplyDefaults(dst, { settings = { tooltip = true } })
      assert.equal(true, dst.settings.tooltip)
    end)
  end)

  -- Depth for the tooltip: how long the shelf lasts at the rate the market is clearing it.
  -- Both numbers ride the import string's verification token, so either can be absent and
  -- neither may be trusted to be sane.
  describe("FormatSupplyDays", function()
    it("divides the shelf by the daily rate, floored like FormatAge", function()
      assert.equal("48d", GC.Util.FormatSupplyDays(4210, 86)) -- 48.95, not 49
    end)

    it("says <1d when the shelf turns over inside a day", function()
      assert.equal("<1d", GC.Util.FormatSupplyDays(40, 86))
      assert.equal("<1d", GC.Util.FormatSupplyDays(85, 86))
    end)

    it("keeps a shelf of exactly one day out of the <1d bucket", function()
      assert.equal("1d", GC.Util.FormatSupplyDays(86, 86))
    end)

    -- Past three months the figure stops carrying information: "400d" and "99d+" tell a
    -- player the same thing, and the short one does not stretch the tooltip.
    it("caps the display rather than printing a year of supply", function()
      assert.equal("99d", GC.Util.FormatSupplyDays(99 * 86 + 85, 86))
      assert.equal("99d+", GC.Util.FormatSupplyDays(100 * 86, 86))
    end)

    it("returns nil when there is no rate to divide by", function()
      assert.is_nil(GC.Util.FormatSupplyDays(4210, nil))
      assert.is_nil(GC.Util.FormatSupplyDays(4210, 0))
      assert.is_nil(GC.Util.FormatSupplyDays(4210, -3))
    end)

    it("returns nil when there is no shelf", function()
      assert.is_nil(GC.Util.FormatSupplyDays(0, 86))
      assert.is_nil(GC.Util.FormatSupplyDays(nil, 86))
    end)

    it("returns nil rather than a word for a corrupt number", function()
      assert.is_nil(GC.Util.FormatSupplyDays(0 / 0, 86))
      assert.is_nil(GC.Util.FormatSupplyDays(4210, 0 / 0))
      assert.is_nil(GC.Util.FormatSupplyDays(math.huge, 86))
      assert.is_nil(GC.Util.FormatSupplyDays("4210", 86))
    end)
  end)

  describe("FormatAge", function()
    it("formats sub-hour as <1h", function() assert.equal("<1h", GC.Util.FormatAge(59 * 60)) end)
    it("formats hours under 48h", function() assert.equal("5h", GC.Util.FormatAge(5 * 3600 + 120)) end)
    it("formats days from 48h", function() assert.equal("3d", GC.Util.FormatAge(3 * 86400 + 3600)) end)
  end)
end)
