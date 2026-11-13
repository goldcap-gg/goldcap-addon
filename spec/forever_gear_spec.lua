local helper = require("spec.spec_helper")

describe("ForeverGear", function()
  local G
  before_each(function()
    local GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ForeverGear.lua", GC)
    G = GC.ForeverGear
  end)

  it("reads the suffix and its scale from a link, and 0/0 for a plain piece", function()
    assert.same({ "0", "0", "0" }, { G.Variant("|cff1eff00|Hitem:6125::::::::20:::::|h[Brawler's Harness]|h|r") })
    assert.same({ "-12", "1583", "0" },
      { G.Variant("|cff1eff00|Hitem:15210:0:0:0:0:0:-12:1583:20|h[Raider Shortsword of the Bear]|h|r") })
    assert.same({ "612", "0", "0" }, { G.Variant("item:4564:0:0:0:0:0:612:0") })
    assert.is_nil(G.Variant(nil))
    assert.is_nil(G.Variant("not a link"))
  end)

  it("keeps the cheapest lot of each version, cheapest first", function()
    local acc = G.New()
    assert.is_true(G.AddRow(acc, 15210, 1, 900, "item:15210:0:0:0:0:0:-12:1583"))
    assert.is_true(G.AddRow(acc, 15210, 1, 700, "item:15210:0:0:0:0:0:-12:1583"))
    G.AddRow(acc, 15210, 1, 500, "item:15210:0:0:0:0:0:-9:1583")
    G.AddRow(acc, 15210, 1, 800, "item:15210:0:0:0:0:0:-5:1583")
    G.AddRow(acc, 6125, 2, 1001, "item:6125::::::::20")              -- 500.5 a unit rounds to 501
    assert.same({ v = 2, at = 777, items = {
      [15210] = "500:-9:1583:0 700:-12:1583:0 800:-5:1583:0",
      [6125] = "501:0:0:0",
    } }, G.Freeze(acc, 777))
  end)

  -- The HERO probe (P1, 13.11): Forever writes a random suffix as one bonus ID after field 13's
  -- count, with or without a context in field 12 and a modifier after the IDs, and a crafted piece
  -- ends with its crafter's GUID. The scan, an item-search row and the key's sample link carry the
  -- same IDs. Every link here is copied from the probe's record.
  it("reads a Forever suffix from the link's bonus IDs, the same from the scan, a search row and a sample link", function()
    -- Militant Shortsword of Magic, key 15211/22/14314: as the scan read it, as its key's search
    -- answered it, and as GetItemKeySampleLink named the key right after the browse.
    local scan = "|cnIQ2:|Hitem:15211::::::::17:1488::1:1:12917:1:28:5254:::::|h[Militant Shortsword of Magic]|h|r"
    local row = "|cnIQ2:|Hitem:15211::::::::17:1488::1:1:12917:1:28:5240:::::|h[Militant Shortsword of Magic]|h|r"
    local sample = "|cnIQ2:|Hitem:15211::::::::17:1488::1:1:12917:1:28:5254:::::|h[Militant Shortsword of Magic]|h|r"
    assert.same({ "12917", "12917", "12917" }, { G.BonusKey(scan), G.BonusKey(row), G.BonusKey(sample) })
    -- No context, no modifier.
    assert.equal("12729",
      G.BonusKey("|cnIQ2:|Hitem:15211::::::::17:1488:::1:12729::::::|h[Militant Shortsword of Intellect]|h|r"))
    -- Crafted, enchanted (field 2), with the crafter's GUID: no bonus IDs.
    assert.equal("0",
      G.BonusKey("|cnIQ2:|Hitem:4243:15:::::::17:1488::::::::Player-6949-006A8F82:|h[Fine Leather Tunic]|h|r"))
    assert.equal("0", G.BonusKey("|cnIQ2:|Hitem:11288::::::::17:1488:::::::::|h[Greater Magic Wand]|h|r"))
    assert.same({ "0", "0", "12917" }, { G.Variant(row) })
    -- The probe saw no link with two IDs; built from P1's shape, two IDs in either order are one
    -- version, sorted as numbers (6654 before 12729).
    assert.equal("6654.12729", G.BonusKey("item:15211::::::::17:1488:::2:12729:6654::::::"))
    assert.equal("6654.12729", G.BonusKey("item:15211::::::::17:1488::1:2:6654:12729:1:28:5240:::::"))
    assert.is_nil(G.BonusKey(nil))
    assert.is_nil(G.BonusKey("not a link"))
  end)

  -- Nine versions of Raider Shortsword at the prices the probe's scan read them (P1, 13.11).
  it("keeps the cheapest lot of each bonus version, up to VARIANTS", function()
    assert.equal(8, G.VARIANTS)
    local acc = G.New()
    for _, r in ipairs({
      { 825, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12920::::::|h[Raider Shortsword of Healing]|h|r" },
      { 819, "|cnIQ2:|Hitem:15210::::::::17:1488::1:1:12920:1:28:5240:::::|h[Raider Shortsword of Healing]|h|r" },
      { 819, "|cnIQ2:|Hitem:15210::::::::17:1488::1:1:12917:1:28:5244:::::|h[Raider Shortsword of Magic]|h|r" },
      { 819, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12733::::::|h[Raider Shortsword of Power]|h|r" },
      { 823, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12718::::::|h[Raider Shortsword of the Eagle]|h|r" },
      { 825, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12729::::::|h[Raider Shortsword of Intellect]|h|r" },
      { 900, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12744::::::|h[Raider Shortsword of Shadow Protection]|h|r" },
      { 925, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12720::::::|h[Raider Shortsword of the Owl]|h|r" },
      { 1223, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12719::::::|h[Raider Shortsword of the Whale]|h|r" },
      { 1525, "|cnIQ2:|Hitem:15210::::::::17:1488:::1:12741::::::|h[Raider Shortsword of Fire Protection]|h|r" },
    }) do
      assert.is_true(G.AddRow(acc, 15210, 1, r[1], r[2]))
    end
    -- Healing at its cheaper lot; the ninth version, Fire Protection, goes. Equal prices in the
    -- order of their IDs.
    assert.equal("819:0:0:12733 819:0:0:12917 819:0:0:12920 823:0:0:12718 825:0:0:12729 900:0:0:12744 "
      .. "925:0:0:12720 1223:0:0:12719", G.Freeze(acc, 1).items[15210])
  end)

  it("writes v2 lots and reads a v1 one as version unknown", function()
    local acc = G.New()
    G.AddRow(acc, 15211, 1, 1932,
      "|cnIQ2:|Hitem:15211::::::::17:1488:::1:12917::::::|h[Militant Shortsword of Magic]|h|r")
    local frozen = G.Freeze(acc, 5)
    assert.same({ v = 2, at = 5, items = { [15211] = "1932:0:0:12917" } }, frozen)
    assert.same({ { unit = 1932, suffix = "0", unique = "0", bonus = "12917" } }, G.Decode(frozen.items[15211]))
    assert.same({ { unit = 501, suffix = "0", unique = "0", bonus = "0" } }, G.Decode("501:0:0:0"))
    -- A v1 save: no fourth field, so the version is not known -- not "0", which says none.
    assert.same({ { unit = 500, suffix = "-9", unique = "1583" }, { unit = 501, suffix = "0", unique = "0" } },
      G.Decode("500:-9:1583 501:0:0"))
    assert.is_nil(G.Decode("500:-9:1583")[1].bonus)
  end)

  -- P2 (13.11): "item:<id>::::::::::::1:<bonus>" gave exactly the full link's stats and name in all
  -- 9 reads; the bare id gave the base item's. The literal is the probe's own S2.
  it("builds the item string the client scores by its bonus IDs", function()
    assert.equal("item:15211::::::::::::1:12729", G.ItemString(15211, { suffix = "0", unique = "0", bonus = "12729" }))
    assert.equal("item:15211::::::::::::2:6654:12729",
      G.ItemString(15211, { suffix = "0", unique = "0", bonus = "6654.12729" }))
    assert.equal("item:6125", G.ItemString(6125, { suffix = "0", unique = "0", bonus = "0" }))
    -- A v1 lot builds the string it always did.
    assert.equal("item:15210:0:0:0:0:0:-9:1583", G.ItemString(15210, { suffix = "-9", unique = "1583" }))
    assert.equal("item:6125", G.ItemString(6125, { suffix = "0", unique = "0" }))
    -- The string a lot is built into reads back as the same version.
    assert.equal("12729", G.BonusKey(G.ItemString(15211, { suffix = "0", unique = "0", bonus = "12729" })))
  end)

  -- P1 (13.11): a lot's modifier (":1:28:<value>", 4522 to 5256) varies between lots of one version
  -- and changes no stat; a context in field 12 is sometimes there and sometimes not.
  it("keeps two lots that differ only in bonus as two versions, and lots that differ only in a modifier as one", function()
    local acc = G.New()
    -- Militant Shortsword of Intellect, three of its lots as key 15211/22/14309's search answered them.
    G.AddRow(acc, 15211, 1, 1930, "|cnIQ2:|Hitem:15211::::::::17:1488:::1:12729::::::|h[Militant Shortsword of Intellect]|h|r")
    G.AddRow(acc, 15211, 1, 1920,
      "|cnIQ2:|Hitem:15211::::::::17:1488::1:1:12729:1:28:5237:::::|h[Militant Shortsword of Intellect]|h|r")
    G.AddRow(acc, 15211, 1, 1949,
      "|cnIQ2:|Hitem:15211::::::::17:1488::1:1:12729:1:28:5254:::::|h[Militant Shortsword of Intellect]|h|r")
    -- ...and of Magic, a version of its own.
    G.AddRow(acc, 15211, 1, 1918,
      "|cnIQ2:|Hitem:15211::::::::17:1488::1:1:12917:1:28:5240:::::|h[Militant Shortsword of Magic]|h|r")
    assert.equal("1918:0:0:12917 1920:0:0:12729", G.Freeze(acc, 1).items[15211])
  end)

  -- Same class of bug as Core/ForeverFold.lua's Encode (owner, Forever beta 2026-09-28): a
  -- gear lot's price is copper too, and WoW's own string.format raises "integer overflow
  -- attempting to store N" past +-2^31, where busted's own Lua has no such ceiling. .busted's
  -- own helper installs the shim that reproduces it for this whole run.
  it("encodes and round-trips a gear lot's price past 2^31 without WoW's own string.format overflowing",
    function()
      local acc = G.New()
      G.AddRow(acc, 15210, 1, 15000001200, "item:15210:0:0:0:0:0:-9:1583")
      local frozen = G.Freeze(acc, 1)
      local lots = G.Decode(frozen.items[15210])
      assert.equal(15000001200, lots[1].unit)
    end)

  it("counts a row without a link, folds nothing that is not a price, and freezes nothing from nothing", function()
    local acc = G.New()
    assert.same({ false, "nolink" }, { G.AddRow(acc, 6125, 1, 100, nil) })
    assert.is_false(G.AddRow(acc, 6125, 1, 0, "item:6125"))
    assert.is_false(G.AddRow(acc, nil, 1, 100, "item:6125"))
    assert.equal(1, acc.nolink)
    assert.is_nil(G.Freeze(acc, 1))
  end)

  it("decodes what it encodes and builds the item string a lot's stats are read from", function()
    local lots = G.Decode("500:-9:1583 501:0:0")
    assert.same({ { unit = 500, suffix = "-9", unique = "1583" }, { unit = 501, suffix = "0", unique = "0" } }, lots)
    assert.equal("item:15210:0:0:0:0:0:-9:1583", G.ItemString(15210, lots[1]))
    assert.equal("item:6125", G.ItemString(6125, lots[2]))
    assert.same({}, G.Decode(nil))
  end)

  -- Final review I2: two real auction lots of "... of the Bear" carry different large,
  -- per-instance uniqueIDs (1999963695 and 1583 both end in the same low 16 bits, 1583) -- they
  -- must count as ONE version, not two, or the lot cap fills with one suffix and crowds out a
  -- different, cheaper one ("... of the Eagle").
  it("dedupes a random suffix by its low 16 bits, never the whole per-instance unique id", function()
    local acc = G.New()
    assert.equal(1999963695 % 65536, 1583)   -- the fixture below relies on this
    G.AddRow(acc, 15210, 1, 900, "item:15210:0:0:0:0:0:-9:1583")
    G.AddRow(acc, 15210, 1, 700, "item:15210:0:0:0:0:0:-9:1999963695")   -- same Bear, cheaper lot
    G.AddRow(acc, 15210, 1, 800, "item:15210:0:0:0:0:0:-12:1583")        -- a different suffix: the Eagle
    assert.same({ v = 2, at = 1, items = {
      -- The Bear kept at its cheapest lot's own uniqueID; the Eagle survives as its own version.
      [15210] = "700:-9:1999963695:0 800:-12:1583:0",
    } }, G.Freeze(acc, 1))
  end)
end)
