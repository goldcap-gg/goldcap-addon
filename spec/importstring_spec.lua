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

  it("rejects uppercase realm slugs", function()
    local r, err = GC.ImportString.Parse("GCS1;eu;Silvermoon;1;I:1=10")
    assert.is_nil(r); assert.equal("bad_header", err)
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
end)
