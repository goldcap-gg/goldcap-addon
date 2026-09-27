local helper = require("spec.spec_helper")

-- WoW: Forever crowd prices: the Companion's GCF1 payload (the site's plan 2a, Task 9), read
-- into the tooltip and the Deals board (plan 3d, Part A).
describe("GCF1, the WoW: Forever crowd payload", function()
  local GC
  local TS = 1790000000
  local BODY = "GCF1;us-beta-classic-beta-pve-2-horde;90;Classic Beta PvE 2;Horde;" .. TS
    .. ";I:2589=68=70=69=79=7000=2=0=g,2592=255=269===2029=1=20"

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC)
  end)

  it("reads the header and every token", function()
    local p = GC.ImportString.ParseForever(BODY)
    assert.equal("us-beta-classic-beta-pve-2-horde", p.slug)
    assert.equal(90, p.regionId)
    assert.equal("Classic Beta PvE 2", p.realm)
    assert.equal("Horde", p.faction)
    assert.equal(TS, p.ts)
    assert.equal(2, p.count)
    assert.same({ min = 68, ah = 70, mv = 69, p50 = 79, qty = 7000, w = 2, age = 0, gear = true }, p.items[2589])
    assert.same({ min = 255, ah = 269, qty = 2029, w = 1, age = 20 }, p.items[2592])
  end)

  it("unescapes the realm and reads a dash as no faction", function()
    local p = GC.ImportString.ParseForever("GCF1;s;90;Odd%3BRealm%25;-;" .. TS .. ";I:1=2=2===3=1=0")
    assert.equal("Odd;Realm%", p.realm)
    assert.is_nil(p.faction)
  end)

  it("drops a malformed token alone, skips a section it does not know", function()
    local p = GC.ImportString.ParseForever("GCF1;s;90;R;Horde;" .. TS .. ";I:1=2=2===3=1=0,oops,3=x;Z:whatever")
    assert.equal(1, p.count)
    assert.is_not_nil(p.items[1])
  end)

  it("refuses what is not a Forever payload", function()
    assert.same({ nil, "empty" }, { GC.ImportString.ParseForever(nil) })
    assert.same({ nil, "bad_header" }, { GC.ImportString.ParseForever("GCM1;eu;1;I:1=2") })
    assert.same({ nil, "bad_header" }, { GC.ImportString.ParseForever("GCS1;eu;x;1;I:1=2") })
    assert.same({ nil, "no_items" }, { GC.ImportString.ParseForever("GCF1;s;90;R;Horde;1;I:") })
    assert.same({ nil, "too_long" }, { GC.ImportString.ParseForever(("x"):rep(GC.ImportString.FOREVER_MAX_LEN + 1)) })
  end)
end)
