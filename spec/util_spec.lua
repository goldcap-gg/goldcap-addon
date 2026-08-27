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

  -- FormatAge above is deliberately coarse -- it answers "is my whole snapshot stale",
  -- where anything under an hour is equally fine. A freshness figure on a decision the
  -- player is one click from acting on is a different question: the check panel printed
  -- "3384s", which is both unreadable and, through FormatAge, would have collapsed to
  -- "<1h" and lost the very resolution that matters there.
  describe("FormatElapsed", function()
    it("keeps seconds while they are what the player is watching", function()
      assert.equal("0s", GC.Util.FormatElapsed(0))
      assert.equal("45s", GC.Util.FormatElapsed(45))
    end)

    it("switches to whole minutes at a minute", function()
      assert.equal("1m", GC.Util.FormatElapsed(60))
      assert.equal("56m", GC.Util.FormatElapsed(3384))
    end)

    it("switches to hours, then days", function()
      assert.equal("1h", GC.Util.FormatElapsed(3600))
      assert.equal("5h", GC.Util.FormatElapsed(5 * 3600 + 120))
      assert.equal("3d", GC.Util.FormatElapsed(3 * 86400 + 3600))
    end)

    it("floors rather than rounds up -- never claims fresher than it is", function()
      assert.equal("59s", GC.Util.FormatElapsed(59.9))
      assert.equal("1m", GC.Util.FormatElapsed(119))
    end)

    it("refuses a corrupt or negative number rather than printing one", function()
      assert.is_nil(GC.Util.FormatElapsed(-1))
      assert.is_nil(GC.Util.FormatElapsed(0 / 0))
      assert.is_nil(GC.Util.FormatElapsed(math.huge))
      assert.is_nil(GC.Util.FormatElapsed("60"))
    end)
  end)

  -- The panel printed a region-wide commodity's turnover as "856146.0": a trailing .0 on
  -- a figure whose last five digits carry no decision, in a 64px-wide cell.
  describe("FormatCount", function()
    it("prints small counts exactly -- three a day is a decision", function()
      assert.equal("0", GC.Util.FormatCount(0))
      assert.equal("3", GC.Util.FormatCount(3))
      assert.equal("999", GC.Util.FormatCount(999))
    end)

    it("drops a fraction rather than showing .0", function()
      assert.equal("3", GC.Util.FormatCount(3.0))
      assert.equal("3", GC.Util.FormatCount(3.4))
      assert.equal("4", GC.Util.FormatCount(3.6))
    end)

    it("compacts thousands and millions", function()
      assert.equal("1.2k", GC.Util.FormatCount(1234))
      assert.equal("12k", GC.Util.FormatCount(12345))
      assert.equal("856k", GC.Util.FormatCount(856146))
      assert.equal("1.4M", GC.Util.FormatCount(1420000))
    end)

    it("refuses a corrupt number rather than printing one", function()
      assert.is_nil(GC.Util.FormatCount(0 / 0))
      assert.is_nil(GC.Util.FormatCount(math.huge))
      assert.is_nil(GC.Util.FormatCount(-1))
      assert.is_nil(GC.Util.FormatCount("3"))
    end)
  end)
end)
