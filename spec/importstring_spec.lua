local helper = require("spec.spec_helper")

describe("ImportString.Parse", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/ImportString.lua")
  end)

  it("parses a valid string with sold rates and watchlist", function()
    local s = "GCS1;eu;silvermoon;1751990400;I:190396=123400=52.3,201234=990000;W:190396,201234"
    local r, err = GC.ImportString.Parse(s)
    assert.is_nil(err)
    assert.equal("eu", r.region)
    assert.equal("silvermoon", r.realm)
    assert.equal(1751990400, r.ts)
    assert.equal(123400, r.items[190396].m)
    assert.equal(52.3, r.items[190396].s)
    assert.equal(990000, r.items[201234].m)
    assert.is_nil(r.items[201234].s)
    assert.same({ 190396, 201234 }, r.watchlist)
  end)

  it("parses the N section into namesWanted", function()
    local r = GC.ImportString.Parse("GCS1;eu;silvermoon;1751990400;I:42=1000;N:201420,201421")
    assert.same({ 201420, 201421 }, r.namesWanted)
  end)

  it("leaves namesWanted empty when the section is absent", function()
    local r = GC.ImportString.Parse("GCS1;eu;silvermoon;1751990400;I:42=1000")
    assert.same({}, r.namesWanted)
  end)

  it("tolerates surrounding whitespace/newlines (paste artifacts)", function()
    local r = GC.ImportString.Parse("  GCS1;us;area-52;1;I:1=10\n")
    assert.equal(10, r.items[1].m)
  end)

  it("tolerates a leading UTF-8 BOM / zero-width byte from browser copy", function()
    local bom = string.char(239, 187, 191) -- UTF-8 BOM, not matched by %s
    local r = GC.ImportString.Parse(bom .. "GCS1;eu;dentarg;1;I:1=10")
    assert.equal("dentarg", r.realm)
    assert.equal(10, r.items[1].m)
  end)

  it("rejects empty input", function()
    local r, err = GC.ImportString.Parse("")
    assert.is_nil(r); assert.equal("empty", err)
  end)

  it("rejects wrong header", function()
    local r, err = GC.ImportString.Parse("WA2;eu;x;1;I:1=10")
    assert.is_nil(r); assert.equal("bad_header", err)
  end)

  it("accepts all four supported regions", function()
    for _, region in ipairs({ "us", "eu", "kr", "tw" }) do
      local r = GC.ImportString.Parse(("GCS1;%s;azshara;1;I:1=10"):format(region))
      assert.is_table(r)
      assert.equal(region, r.region)
    end
  end)

  it("rejects an unsupported region with its own error code", function()
    local r, err = GC.ImportString.Parse("GCS1;zz;silvermoon;1;I:1=10")
    assert.is_nil(r); assert.equal("bad_region", err)
  end)

  it("accepts a hyphenated kr/tw realm slug", function()
    local r = GC.ImportString.Parse("GCS1;tw;krol-blade;1;I:1=10")
    assert.equal("krol-blade", r.realm)
  end)

  -- The realm is a label the addon stores and prints back, never parses. Matching it as
  -- ASCII lowercase rejected every Korean and Taiwanese realm -- Blizzard's own slugs there
  -- are not ASCII -- with the message that says the string itself is broken.
  it("accepts a realm slug in the client's own alphabet", function()
    -- No spaces in the list: whitespace is stripped from the whole paste above, and a slug
    -- has none to begin with.
    for _, realm in ipairs({ "아즈샤라", "Silvermoon", "area_52", "burning-légion" }) do
      local r, err = GC.ImportString.Parse(("GCS1;kr;%s;1;I:1=10"):format(realm))
      assert.is_nil(err)
      assert.equal(realm, r.realm)
    end
  end)

  it("rejects a string that names no realm, in its own words", function()
    local r, err = GC.ImportString.Parse("GCS1;eu;;1;I:1=10")
    assert.is_nil(r); assert.equal("no_realm", err)
  end)

  -- Two strings pasted one after the other: the header match runs from the first marker to
  -- the end of the paste, so the second realm's sections used to be read as the first
  -- realm's and overwrite its prices under its name.
  it("rejects two import strings pasted together", function()
    local r, err = GC.ImportString.Parse(
      "GCS1;eu;silvermoon;1;I:1=10GCS1;us;area-52;2;I:1=99")
    assert.is_nil(r); assert.equal("two_strings", err)
    local separated, err2 = GC.ImportString.Parse(
      "GCS1;eu;silvermoon;1;I:1=10\nGCS1;us;area-52;2;I:1=99")
    assert.is_nil(separated); assert.equal("two_strings", err2)
  end)

  it("rejects strings with no items", function()
    local r, err = GC.ImportString.Parse("GCS1;eu;silvermoon;1;W:123")
    assert.is_nil(r); assert.equal("no_items", err)
  end)

  it("rejects oversized input", function()
    local r, err = GC.ImportString.Parse("GCS1;eu;x;1;I:" .. string.rep("1=1,", 20000))
    assert.is_nil(r); assert.equal("too_long", err)
  end)

  describe("4th field (trend)", function()
    it("parses a negative trend on a 4-field token", function()
      local r = GC.ImportString.Parse("GCS1;eu;silvermoon;1;I:190396=123400=52.3=-12")
      assert.equal(123400, r.items[190396].m)
      assert.equal(52.3, r.items[190396].s)
      assert.equal(-12, r.items[190396].t)
    end)

    it("parses a positive trend on a 4-field token", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=100=2.0=7")
      assert.equal(7, r.items[1].t)
    end)

    it("parses multiple 4-field tokens in one string", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=100=2.0=-7,2=200=3.0=15")
      assert.equal(-7, r.items[1].t)
      assert.equal(15, r.items[2].t)
    end)

    it("still parses a 2-field token with no trend or sold field (regression)", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=100")
      assert.equal(100, r.items[1].m)
      assert.is_nil(r.items[1].s)
      assert.is_nil(r.items[1].t)
    end)

    it("still parses a 3-field token with sold but no trend (regression)", function()
      local r = GC.ImportString.Parse("GCS1;eu;silvermoon;1751990400;I:190396=123400=52.3,201234=990000")
      assert.equal(52.3, r.items[190396].s)
      assert.is_nil(r.items[190396].t)
      assert.is_nil(r.items[201234].s)
      assert.is_nil(r.items[201234].t)
    end)

    it("parses a mix of 2-, 3-, and 4-field tokens in the same string", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10,2=20=3.0,3=30=4.0=-9")
      assert.is_nil(r.items[1].s); assert.is_nil(r.items[1].t)
      assert.equal(3.0, r.items[2].s); assert.is_nil(r.items[2].t)
      assert.equal(4.0, r.items[3].s); assert.equal(-9, r.items[3].t)
    end)
  end)

  describe("V verification facts", function()
    it("parses canonical per-item commodity verification facts", function()
      local r = GC.ImportString.Parse(
        "GCS1;eu;silvermoon;1751990400;I:42=123400=52.3=-2;V:42=1700000042=600=7000=90=400=6=12=321=1;W:42")

      assert.same({
        sourceAt = 1700000042, stressUnit = 600, sellThroughBps = 7000,
        liquidityConfidence = 90, currentQty = 400, listings = 6,
        observations = 12, madBps = 321, flags = 1,
      }, r.verification[42])
    end)

    it("ignores unknown sections and unknown verification flag bits", function()
      local r = GC.ImportString.Parse(
        "GCS1;eu;x;1;I:1=10;X:ignored;V:1=2=3=4=5=6=7=8=9=129")

      assert.equal(10, r.items[1].m)
      assert.equal(129, r.verification[1].flags)
    end)

    it("skips only malformed V tokens beside valid facts", function()
      local r = GC.ImportString.Parse(
        "GCS1;eu;x;1;I:1=10,2=20;V:1=2=3=4=5=6=7=8=9=0,2=bad=3=4=5=6=7=8=9=0")

      assert.equal(10, r.items[1].m)
      assert.equal(20, r.items[2].m)
      assert.equal(2, r.verification[1].sourceAt)
      assert.is_nil(r.verification[2])
    end)

    it("does not accept a valid V prefix followed by malformed fields", function()
      local r = GC.ImportString.Parse(
        "GCS1;eu;x;1;I:1=10,2=20;V:1=2=3=4=5=6=7=8=9=0,2=2=3=4=5=6=7=8=9=0=extra")

      assert.equal(2, r.verification[1].sourceAt)
      assert.is_nil(r.verification[2])
    end)

    it("keeps legacy GCS1 imports valid when V is absent", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10")
      assert.equal(10, r.items[1].m)
      assert.same({}, r.verification)
    end)
  end)

  describe("Q section (cheap-quarter line)", function()
    it("parses Q tokens into quarter, keyed by item id", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10,2=20;V:1=2=3=4=5=6=7=8=9=0;Q:1=12,2=25;W:1")
      assert.equal(12, r.quarter[1])
      assert.equal(25, r.quarter[2])
      assert.same({ 1 }, r.watchlist)
    end)

    it("leaves quarter empty when the section is absent", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10")
      assert.same({}, r.quarter)
    end)

    it("drops only the malformed Q token", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10,2=20;Q:1=12,2=bad,3=7=extra")
      assert.equal(12, r.quarter[1])
      assert.is_nil(r.quarter[2])
      assert.is_nil(r.quarter[3])
      assert.equal(20, r.items[2].m)
    end)
  end)

  -- R rides between Q and W, and neither of those may be disturbed by it: an older string
  -- without R has to keep parsing exactly as before, and a newer one must not lose its
  -- watchlist to the new section.
  describe("R section (reach24)", function()
    it("parses R tokens into reach, keyed by item id", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10,2=20;Q:1=12,2=25;R:1=30,2=44;W:1")
      assert.equal(30, r.reach[1])
      assert.equal(44, r.reach[2])
      assert.equal(12, r.quarter[1])
      assert.same({ 1 }, r.watchlist)
    end)

    it("leaves reach empty when the section is absent", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10;Q:1=12")
      assert.same({}, r.reach)
      assert.equal(12, r.quarter[1])
    end)

    it("drops only the malformed R token", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10,2=20;R:1=30,2=bad,3=7=extra")
      assert.equal(30, r.reach[1])
      assert.is_nil(r.reach[2])
      assert.is_nil(r.reach[3])
      assert.equal(20, r.items[2].m)
    end)
  end)

  describe("T section (region reference for realm items)", function()
    it("parses T tokens into targets, keyed by item id", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10;R:1=30;T:5=900=610,6=1200=0;W:1")
      assert.same({ ref = 900, ilvl = 610 }, r.targets[5])
      assert.same({ ref = 1200, ilvl = 0 }, r.targets[6])
      -- The sections around it still parse: T sits after R and before W.
      assert.equal(30, r.reach[1])
      assert.same({ 1 }, r.watchlist)
    end)

    it("leaves targets empty when the section is absent", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10;W:1")
      assert.same({}, r.targets)
    end)

    it("drops only the malformed T token", function()
      local r = GC.ImportString.Parse("GCS1;eu;x;1;I:1=10;T:5=900=610,6=nope=0,7=1200,8=1=2=3")
      assert.same({ ref = 900, ilvl = 610 }, r.targets[5])
      assert.is_nil(r.targets[6])
      assert.is_nil(r.targets[7])
      assert.is_nil(r.targets[8])
    end)
  end)
end)

describe("ImportString.ParseRegion", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/ImportString.lua")
  end)

  local PAYLOAD = "GCM1;eu;1789819200;I:42=500,43=700=12.0=-8"
    .. ";V:43=1789819200=600=8000=90=400=6=12=150=0"
    .. ";Q:42=510,43=720;R:43=760;M:300001=20000=2,300002=480000=6"

  it("reads every section of a GCM1 payload", function()
    local r, err = GC.ImportString.ParseRegion(PAYLOAD)
    assert.is_nil(err)
    assert.equal("eu", r.region)
    assert.equal(1789819200, r.ts)
    assert.same({ m = 500 }, r.items[42])
    assert.same({ m = 700, s = 12, t = -8 }, r.items[43])
    assert.equal(1789819200, r.verification[43].sourceAt)
    assert.equal(600, r.verification[43].stressUnit)
    assert.equal(90, r.verification[43].liquidityConfidence)
    assert.equal(510, r.quarter[42])
    assert.equal(760, r.reach[43])
    -- Two flat maps, not a {m, l} table per item: 25,000 of those held 3 MB (final review M5).
    assert.equal(20000, r.refs[300001])
    assert.equal(2, r.refListings[300001])
    assert.equal(480000, r.refs[300002])
    assert.equal(6, r.refListings[300002])
    assert.same({ items = 2, facts = 1, refs = 2 }, r.counts)
  end)

  it("skips a section it does not know", function()
    local r = GC.ImportString.ParseRegion("GCM1;eu;1;X:1,2,3;I:1=2")
    assert.equal(2, r.items[1].m)
  end)

  it("drops a malformed fact or reference and nothing else", function()
    local r = GC.ImportString.ParseRegion("GCM1;eu;1;I:1=2,3=4;V:1=2=3,3=1=1=1=1=1=1=1=1=0;M:5=6,7=8=9")
    assert.is_nil(r.verification[1])
    assert.equal(0, r.verification[3].flags)
    assert.is_nil(r.refs[5])
    assert.is_nil(r.refListings[5])
    assert.equal(8, r.refs[7])
    assert.equal(9, r.refListings[7])
    assert.same({ items = 2, facts = 1, refs = 1 }, r.counts)
  end)

  it("refuses an import string, a buy run and a region it does not know", function()
    local r, err = GC.ImportString.ParseRegion("GCS1;eu;silvermoon;1;I:1=2")
    assert.is_nil(r)
    assert.equal("bad_header", err)
    r, err = GC.ImportString.ParseRegion("GCR1;abcd2345;Cooking;5=210")
    assert.is_nil(r)
    assert.equal("bad_header", err)
    r, err = GC.ImportString.ParseRegion("GCM1;cn;1;I:1=2")
    assert.is_nil(r)
    assert.equal("bad_region", err)
  end)

  it("refuses nothing at all and a payload without prices", function()
    local r, err = GC.ImportString.ParseRegion(nil)
    assert.is_nil(r)
    assert.equal("empty", err)
    r, err = GC.ImportString.ParseRegion("")
    assert.is_nil(r)
    assert.equal("empty", err)
    r, err = GC.ImportString.ParseRegion("GCM1;eu;1;M:1=20000=2")
    assert.is_nil(r)
    assert.equal("no_items", err)
    -- What the site sends for a region with no eligible commodity: I is always there, empty.
    r, err = GC.ImportString.ParseRegion("GCM1;eu;1;I:;M:1=20000=2")
    assert.is_nil(r)
    assert.equal("no_items", err)
  end)

  it("takes a payload past the import string's limit and refuses one past its own", function()
    local tokens = {}
    for i = 1, 9500 do tokens[i] = (100000 + i) .. "=99999999=999.9" end
    local big = "GCM1;eu;1;I:" .. table.concat(tokens, ",")
    assert.is_true(#big > GC.ImportString.MAX_LEN)
    assert.equal(9500, GC.ImportString.ParseRegion(big).counts.items)

    assert.equal(6000000, GC.ImportString.REGION_MAX_LEN)
    local huge = "GCM1;eu;1;I:1=2;M:" .. string.rep("1=20000=2,", 600001)
    local r, err = GC.ImportString.ParseRegion(huge)
    assert.is_nil(r)
    assert.equal("too_long", err)
  end)

  it("reads a whole region's worth of sections", function()
    local items, facts, refs = {}, {}, {}
    for i = 1, 9500 do items[i] = (100000 + i) .. "=" .. (1000 + i) .. "=12.5" end
    for i = 1, 5500 do facts[i] = (100000 + i) .. "=1789819200=900=8000=90=400=6=12=150=0" end
    for i = 1, 25000 do refs[i] = (200000 + i) .. "=20000=3" end
    local r = GC.ImportString.ParseRegion("GCM1;us;1789819200;I:" .. table.concat(items, ",")
      .. ";V:" .. table.concat(facts, ",") .. ";M:" .. table.concat(refs, ","))
    assert.same({ items = 9500, facts = 5500, refs = 25000 }, r.counts)
    assert.equal(1789819200, r.ts)
  end)

  it("reads every I token shape the site writes exactly as the import string does", function()
    local tokens = "42=500,43=700=12.0=-8,44=1=0.0,45=99999999=99999.9=-100,46=5=3.5=12"
    local region = GC.ImportString.ParseRegion("GCM1;eu;1;I:" .. tokens)
    local import = GC.ImportString.Parse("GCS1;eu;silvermoon;1;I:" .. tokens)
    assert.same(import.items, region.items)
    assert.equal(5, region.counts.items)
  end)

  -- A corrupt or hand-edited regionString must not stall the load. The I reader Parse uses is
  -- unanchored: on a digit run with no "=" it restarts at every position and backtracks through
  -- the rest of the run, so a million digits would take hours. The payload's reader matches each
  -- token whole instead, which also keeps a junk token out of counts.items.
  it("reads a million-digit junk token at once, and counts no junk as an item", function()
    local started = os.clock()
    local r, err = GC.ImportString.ParseRegion("GCM1;eu;1;I:" .. string.rep("7", 1000000))
    assert.is_nil(r)
    assert.equal("no_items", err)
    r = GC.ImportString.ParseRegion("GCM1;eu;1;I:1=2=" .. string.rep("7", 1000000) .. "x,3=4,5=6x")
    assert.same({ items = 1, facts = 0, refs = 0 }, r.counts)
    assert.same({ m = 4 }, r.items[3])
    assert.is_nil(r.items[1])
    assert.is_nil(r.items[5])
    local elapsed = os.clock() - started
    assert.is_true(elapsed < 2, ("junk took %.2f s to read"):format(elapsed))
  end)

  -- Neither producer ends the payload with a newline today, but nothing enforces it, and every
  -- reader here is anchored per token: a trailing "\n" would silently cost the last section its
  -- last token.
  it("keeps the last token of a payload that ends in whitespace", function()
    for _, tail in ipairs({ "\n", "\r\n", " \t\n" }) do
      local r = GC.ImportString.ParseRegion("GCM1;eu;1;I:1=2,3=4;M:5=20000=3,6=20000=3" .. tail)
      assert.equal(20000, r.refs[6])
      assert.equal(3, r.refListings[6])
      assert.same({ items = 2, facts = 0, refs = 2 }, r.counts)
      r = GC.ImportString.ParseRegion("GCM1;eu;1;I:1=2,3=4=1.5" .. tail)
      assert.same({ m = 4, s = 1.5 }, r.items[3])
    end
    local r, err = GC.ImportString.ParseRegion(" \r\n")
    assert.is_nil(r)
    assert.equal("empty", err)
  end)
end)
