local helper = require("spec.spec_helper")

describe("Tooltip.BuildLines", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    -- Trigger before Tooltip, as the .toc loads them: a realm item's line is the region
    -- reference GC.Trigger.RealmReference picks, not a second copy of that rule here.
    helper.loadModule("Core/Trigger.lua", GC)
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
    assert.equal("52", lines[2].right) -- a whole number from 10 up: see "counts" below
  end)

  it("falls back to listings for item data", function()
    local lines = GC.Tooltip.BuildLines({ mv = 990000, listings = 14, ts = 1000 }, 2000)
    assert.equal("Listings", lines[2].left)
    assert.equal("14", lines[2].right)
  end)

  -- currentQty and listings ride the import string's verification token, which the server
  -- writes for commodities only (routes/addon.ts). So the depth line is an imported-commodity
  -- line by construction: the bundled snapshot carries no verification at all, and a realm
  -- item from an I token has no depth to report.
  it("shows the shelf and how long it lasts for a verified commodity", function()
    local lines = GC.Tooltip.BuildLines(
      { mv = 12400, sold = 86, currentQty = 4210, listings = 68, ts = 1000, source = "import" }, 2000)
    assert.equal("Sold per day", lines[2].left)
    assert.equal("Listed", lines[3].left)
    assert.equal("4,210 · 48d", lines[3].right)
  end)

  it("shows the shelf alone when nothing is selling to divide by", function()
    local lines = GC.Tooltip.BuildLines(
      { mv = 12400, currentQty = 4210, listings = 68, ts = 1000, source = "import" }, 2000)
    assert.equal("Listed", lines[2].left)
    assert.equal("4,210", lines[2].right)
    for _, ln in ipairs(lines) do
      assert.not_equal("Listings", ln.left) -- the shelf count replaces the auction count
    end
  end)

  it("falls back to the auction count when the shelf is empty or unknown", function()
    for _, value in ipairs({
      { mv = 990000, listings = 14, ts = 1000 },
      { mv = 990000, listings = 14, currentQty = 0, ts = 1000, source = "import" },
    }) do
      local lines = GC.Tooltip.BuildLines(value, 2000)
      assert.equal("Listings", lines[2].left)
      assert.equal("14", lines[2].right)
    end
  end)

  -- The two lines were an if/elseif before the shelf line existed, so no item ever showed
  -- both. Nothing in the bundled table sets `s` and `l` together today, but the exclusivity
  -- is what the tooltip's width was drawn against -- keep it rather than rely on that.
  it("never shows the auction count next to a sales rate", function()
    local lines = GC.Tooltip.BuildLines({ mv = 12400, sold = 86, listings = 68, ts = 1000 }, 2000)
    assert.equal(2, #lines)
    assert.equal("Sold per day", lines[2].left)
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

  -- The tooltip kept a 48h threshold of its own while the Sniper's banner and the Sold tab
  -- called the same data stale at 6h (yellow) and 24h (red). A player who only ever mouses
  -- over items was the last to hear about it.
  it("shows the age from the same 6h boundary the rest of the addon turns yellow at", function()
    assert.equal(1, #GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 6 * 3600 - 1))
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 6 * 3600)
    assert.equal("GoldCap data age", lines[#lines].left)
    assert.equal("6h", lines[#lines].right)
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

  -- The nudge. Prices that did not come from the Companion say so in one muted line --
  -- the tooltip is the only GoldCap surface a player sees without ever opening the AH
  -- tab, so this is where the largest audience learns the Companion exists. `origin` is
  -- GC.Data.OriginState()'s word, passed by the caller like `region` is: it describes
  -- the save as a whole, not this value, so it does not belong inside `v`.
  it("nudges toward the Companion under a bundled-data line", function()
    local lines = GC.Tooltip.BuildLines({ mv = 1000, ts = 0, source = "bundled" }, 3600,
      { region = "eu", origin = "none" })
    assert.equal("hint", lines[#lines].kind)
    assert.equal("Companion keeps prices fresh — /goldcap companion", lines[#lines].text)
  end)

  it("nudges when a manual import has gone stale", function()
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0, source = "import" }, 3 * 86400,
      { origin = "manual" })
    assert.equal("hint", lines[#lines].kind)
  end)

  it("never nudges a player whose prices already come from the Companion", function()
    for _, value in ipairs({
      { mv = 1000, ts = 0, source = "bundled" }, -- bundled fallback for one item
      { mv = 100, ts = 0, source = "import" },   -- app-synced data gone stale
    }) do
      for _, ln in ipairs(GC.Tooltip.BuildLines(value, 3 * 86400, { origin = "app" })) do
        assert.not_equal("hint", ln.kind)
      end
    end
  end)

  it("stays quiet on a fresh manual import", function()
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0, source = "import" }, 3600,
      { origin = "manual" })
    assert.equal(1, #lines)
  end)

  it("reads the origin from the one source of truth", function()
    local text = assert(io.open("GoldCap/UI/Tooltip.lua")):read("*a")
    assert.is_truthy(text:find("GC.Data.OriginState", 1, true))
  end)

  it("nudges from the same 24h boundary the Sniper calls an import stale at", function()
    local quiet = GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 24 * 3600 - 1, { origin = "manual" })
    for _, ln in ipairs(quiet) do assert.not_equal("hint", ln.kind) end
    local lines = GC.Tooltip.BuildLines({ mv = 100, ts = 0 }, 24 * 3600, { origin = "manual" })
    assert.equal("hint", lines[#lines].kind)
  end)

  -- An imported realm item's `mv` is this ONE realm's median, which Core/DealMath.lua and
  -- Core/Trigger.lua both refuse to price anything from (two listings make a median of
  -- whichever is the odd one out). The tooltip printed it as "GoldCap value" anyway, on the
  -- most-seen surface in the addon.
  describe("realm items", function()
    it("shows the region reference, with the item level it was measured on", function()
      local lines = GC.Tooltip.BuildLines(
        { mv = 2700000, ref = 190000, refIlvl = 623, ts = 1000, source = "import",
          kind = "realm_item" }, 2000)
      assert.equal("money", lines[1].kind)
      assert.equal("GoldCap region price (ilvl 623)", lines[1].label)
      assert.equal(190000, lines[1].copper)
    end)

    it("takes the realm's own median when it is the lower of the two", function()
      local lines = GC.Tooltip.BuildLines(
        { mv = 90000, ref = 190000, refIlvl = 0, ts = 1000, source = "import",
          kind = "realm_item" }, 2000)
      assert.equal("GoldCap region price", lines[1].label) -- no ilvl to name
      assert.equal(90000, lines[1].copper)
    end)

    -- The T section can name a reference for an item this realm has no median for at all.
    it("prices an item the realm has no median for", function()
      local lines = GC.Tooltip.BuildLines(
        { ref = 190000, refIlvl = 610, ts = 1000, source = "import", kind = "realm_item" }, 2000)
      assert.equal(190000, lines[1].copper)
    end)

    -- With no region reference the median is all there is. It is still shown -- a player
    -- looking at an item wants a figure -- but under its own name, and alone: a median of
    -- two listings has no sale speed or depth behind it, and a second number beside it
    -- would lend the first one authority it has not got.
    it("labels a median with no region reference for what it is", function()
      local lines = GC.Tooltip.BuildLines(
        { mv = 2700000, sold = 4, trend = -12, listings = 2, ts = 1000, source = "import",
          kind = "realm_item" }, 2000)
      assert.equal(1, #lines)
      assert.equal("money", lines[1].kind)
      assert.equal("GoldCap realm median (unverified)", lines[1].label)
      assert.equal(2700000, lines[1].copper)
    end)

    it("says nothing when the import knows neither a reference nor a median", function()
      assert.is_nil(GC.Tooltip.BuildLines(
        { ts = 1000, source = "import", kind = "realm_item" }, 2000))
    end)

    -- Nothing on the realm path may imply a sale rate that was never measured, reference or
    -- not: neither figure rides a realm item's token in the first place.
    it("shows no trend, sale speed or depth beside a region price either", function()
      local lines = GC.Tooltip.BuildLines(
        { mv = 190000, ref = 190000, refIlvl = 623, sold = 4, trend = -12, currentQty = 40,
          listings = 2, ts = 1000, source = "import", kind = "realm_item" }, 2000)
      assert.equal(1, #lines)
    end)

    it("still shows what you paid for stock you are holding", function()
      local lines = GC.Tooltip.BuildLines(
        { mv = 2700000, ts = 1000, source = "import", kind = "realm_item" }, 2000,
        { unitCost = 640 })
      assert.equal("You paid", lines[#lines].label)
      assert.equal(640, lines[#lines].copper)
    end)

    -- Bundled realm items are unaffected: their figure comes from item_region_snapshots,
    -- a region-wide median already (apps/api/src/lib/addonMarketData.ts).
    it("still reports a bundled realm item as a GoldCap value", function()
      local lines = GC.Tooltip.BuildLines(
        { mv = 990000, listings = 14, ts = 0, source = "bundled", kind = "realm_item" }, 3600,
        { region = "eu" })
      assert.equal("GoldCap value", lines[1].label)
      assert.equal(990000, lines[1].copper)
    end)
  end)

  -- An auction house item-GROUP row (one "Star Belt" standing for every listing of it) is an
  -- item key: its tooltip payload carries neither a hyperlink nor a guid, so the old two-way
  -- lookup gave up on the one screen this addon exists for.
  it("resolves the item from the payload id and the shown link, not only a hyperlink", function()
    local text = assert(io.open("GoldCap/UI/Tooltip.lua")):read("*a")
    assert.is_truthy(text:find("data.id", 1, true))
    assert.is_truthy(text:find("tooltip:GetItem()", 1, true))
  end)

  describe("the live line", function()
    local LIVE = { floor = 11500, qty = 40, age = 150 }

    it("says what the auction house showed this session, before what you paid", function()
      local lines = GC.Tooltip.BuildLines({ mv = 12400, sold = 86, ts = 1000, source = "region" }, 2000,
        { live = LIVE, unitCost = 640 })
      local live, paid
      for i, ln in ipairs(lines) do
        if ln.kind == "live" then live = i end
        if ln.label == "You paid" then paid = i end
      end
      assert.is_truthy(live)
      assert.equal("On the AH now", lines[live].left)
      assert.equal(11500, lines[live].copper)
      assert.equal("40 listed · 2 min ago", lines[live].detail)
      assert.is_true(live < paid)
    end)

    it("says just now under a minute", function()
      local lines = GC.Tooltip.BuildLines({ mv = 12400, ts = 1000 }, 2000,
        { live = { floor = 11500, qty = 3, age = 59 } })
      assert.equal("3 listed · just now", lines[#lines].detail)
    end)

    it("stands alone for an item nothing else prices", function()
      local lines = GC.Tooltip.BuildLines(nil, 2000, { live = LIVE })
      assert.equal(1, #lines)
      assert.equal("live", lines[1].kind)
      assert.is_nil(GC.Tooltip.BuildLines(nil, 2000))
    end)

    it("stands alone beside a realm figure too thin to print", function()
      local lines = GC.Tooltip.BuildLines({ source = "import", kind = "realm_item", ts = 1000 }, 2000,
        { live = LIVE })
      assert.equal(1, #lines)
      assert.equal("live", lines[1].kind)
    end)

    it("never prints an age below zero", function()
      local lines = GC.Tooltip.BuildLines(nil, 2000, { live = { floor = 11500, qty = 3, age = -600 } })
      assert.equal("3 listed · just now", lines[1].detail)
    end)

    it("is drawn with the coin string, from what the Sniper's book saw", function()
      local text = assert(io.open("GoldCap/UI/Tooltip.lua")):read("*a")
      assert.is_truthy(text:find("GC.Sniper.LiveFloor(itemID, now)", 1, true))
      assert.is_truthy(text:find('ln.kind == "live"', 1, true))
      assert.is_truthy(text:find('GetCoinTextureString(ln.copper) .. " · " .. ln.detail', 1, true))
    end)
  end)

  describe("a region-payload price", function()
    it("prints as the GoldCap value with its sales and depth", function()
      local lines = GC.Tooltip.BuildLines({ mv = 12400, sold = 86, currentQty = 4210, listings = 68,
        ts = 1000, source = "region", kind = "region_commodity" }, 2000)
      assert.equal("GoldCap value", lines[1].label)
      assert.equal("Sold per day", lines[2].left)
      assert.equal("Listed", lines[3].left)
    end)

    it("is dated by the payload once it is six hours old, and not before", function()
      local fresh = GC.Tooltip.BuildLines({ mv = 100, ts = 0, source = "region" }, 6 * 3600 - 1)
      for _, ln in ipairs(fresh) do assert.not_equal("GoldCap data age", ln.left) end
      local old = GC.Tooltip.BuildLines({ mv = 100, ts = 0, source = "region" }, 7 * 3600)
      assert.equal("GoldCap data age", old[#old].left)
      assert.equal("7h", old[#old].right)
    end)

    it("prints a realm item's region reference like the bundled one, fresh", function()
      local lines = GC.Tooltip.BuildLines({ mv = 720, listings = 11, ts = 1000, source = "region",
        kind = "realm_item" }, 2000)
      assert.equal("GoldCap value", lines[1].label)
      assert.equal(720, lines[1].copper)
      assert.equal("Listings", lines[2].left)
      assert.equal(2, #lines)
    end)
  end)

  -- Counts. A region's staple commodity sells tens of thousands a day and lists a hundred
  -- thousand, and the tooltip printed them as "29728.0" and "98470": a trailing .0 that says
  -- nothing and five digits the eye has to count. A slow seller keeps its decimal, because
  -- there 3.5 against 3 a day is the decision.
  describe("counts", function()
    local function right(lines, left)
      for _, ln in ipairs(lines) do
        if ln.left == left then return ln.right end
      end
    end

    it("keeps one decimal on a seller under ten a day", function()
      assert.equal("3.5", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 3.5, ts = 1000 }, 2000), "Sold per day"))
      assert.equal("9.9", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 9.94, ts = 1000 }, 2000), "Sold per day"))
    end)

    it("prints a faster seller as a whole number, grouped in thousands", function()
      assert.equal("29,728", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 29728, ts = 1000 }, 2000), "Sold per day"))
      assert.equal("1,234,568", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 1234567.6, ts = 1000 }, 2000), "Sold per day"))
      assert.equal("10", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 10, ts = 1000 }, 2000), "Sold per day"))
    end)

    -- 9.96 rounds to "10.0" at one decimal, which is the very figure this rule exists to drop.
    it("never prints 10.0 for a rate that rounds up to ten", function()
      assert.equal("10", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 9.96, ts = 1000 }, 2000), "Sold per day"))
    end)

    it("groups the shelf, with its days of supply after it", function()
      local lines = GC.Tooltip.BuildLines({ mv = 1000, sold = 29728, currentQty = 98470, ts = 1000,
        source = "import" }, 2000)
      assert.equal("98,470 · 3d", right(lines, "Listed"))
    end)

    it("groups the auction count", function()
      assert.equal("1,234", right(GC.Tooltip.BuildLines({ mv = 1000, listings = 1234, ts = 1000 }, 2000), "Listings"))
      assert.equal("12,345", right(GC.Tooltip.BuildLines({ mv = 720, listings = 12345, ts = 1000,
        source = "region", kind = "realm_item" }, 2000), "Listings"))
    end)

    it("groups what the auction house showed this session", function()
      local now = GC.Tooltip.BuildLines(nil, 2000, { live = { floor = 11500, qty = 98470, age = 10 } })
      assert.equal("98,470 listed · just now", now[1].detail)
      local ago = GC.Tooltip.BuildLines(nil, 2000, { live = { floor = 11500, qty = 98470, age = 150 } })
      assert.equal("98,470 listed · 2 min ago", ago[1].detail)
    end)

    it("leaves a count under a thousand as it is", function()
      assert.equal("999", right(GC.Tooltip.BuildLines({ mv = 1000, listings = 999, ts = 1000 }, 2000), "Listings"))
    end)

    -- The client's own grouping follows the player's locale (a German client writes 29.728);
    -- the fallback above is only for a runtime without it, which is this spec suite. The stub
    -- keeps the client's quirk of handing a whole number under a thousand back as a number.
    describe("in the client", function()
      before_each(function()
        _G.BreakUpLargeNumbers = function(n)
          if n < 1000 then return n end
          return (tostring(n):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", ""))
        end
      end)
      after_each(function() _G.BreakUpLargeNumbers = nil end)

      it("groups with the client's separator", function()
        local lines = GC.Tooltip.BuildLines({ mv = 1000, sold = 29728, currentQty = 98470, ts = 1000,
          source = "import" }, 2000)
        assert.equal("29.728", right(lines, "Sold per day"))
        assert.equal("98.470 · 3d", right(lines, "Listed"))
        local live = GC.Tooltip.BuildLines(nil, 2000, { live = { floor = 11500, qty = 1500, age = 10 } })
        assert.equal("1.500 listed · just now", live[1].detail)
      end)

      it("still hands the tooltip a string for a small count", function()
        assert.equal("14", right(GC.Tooltip.BuildLines({ mv = 1000, listings = 14, ts = 1000 }, 2000), "Listings"))
        assert.equal("12", right(GC.Tooltip.BuildLines({ mv = 1000, sold = 12, ts = 1000 }, 2000), "Sold per day"))
      end)
    end)
  end)

end)
