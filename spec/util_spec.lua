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

  describe("FormatAge", function()
    it("formats sub-hour as <1h", function() assert.equal("<1h", GC.Util.FormatAge(59 * 60)) end)
    it("formats hours under 48h", function() assert.equal("5h", GC.Util.FormatAge(5 * 3600 + 120)) end)
    it("formats days from 48h", function() assert.equal("3d", GC.Util.FormatAge(3 * 86400 + 3600)) end)
  end)
end)
