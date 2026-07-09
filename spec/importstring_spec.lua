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

  it("tolerates surrounding whitespace/newlines (paste artifacts)", function()
    local r = GC.ImportString.Parse("  GCS1;us;area-52;1;I:1=10\n")
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

  it("rejects strings with no items", function()
    local r, err = GC.ImportString.Parse("GCS1;eu;silvermoon;1;W:123")
    assert.is_nil(r); assert.equal("no_items", err)
  end)

  it("rejects oversized input", function()
    local r, err = GC.ImportString.Parse("GCS1;eu;x;1;I:" .. string.rep("1=1,", 20000))
    assert.is_nil(r); assert.equal("too_long", err)
  end)
end)
