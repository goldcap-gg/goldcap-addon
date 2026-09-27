local helper = require("spec.spec_helper")

describe("ForeverGear", function()
  local G
  before_each(function() G = helper.loadModule("Core/ForeverGear.lua").ForeverGear end)

  it("reads the suffix and its scale from a link, and 0/0 for a plain piece", function()
    assert.same({ "0", "0" }, { G.Variant("|cff1eff00|Hitem:6125::::::::20:::::|h[Brawler's Harness]|h|r") })
    assert.same({ "-12", "1583" },
      { G.Variant("|cff1eff00|Hitem:15210:0:0:0:0:0:-12:1583:20|h[Raider Shortsword of the Bear]|h|r") })
    assert.same({ "612", "0" }, { G.Variant("item:4564:0:0:0:0:0:612:0") })
    assert.is_nil(G.Variant(nil))
    assert.is_nil(G.Variant("not a link"))
  end)

  it("keeps the cheapest lot of each version, cheapest first, at most VARIANTS of them", function()
    local acc = G.New()
    assert.is_true(G.AddRow(acc, 15210, 1, 900, "item:15210:0:0:0:0:0:-12:1583"))
    assert.is_true(G.AddRow(acc, 15210, 1, 700, "item:15210:0:0:0:0:0:-12:1583"))
    G.AddRow(acc, 15210, 1, 500, "item:15210:0:0:0:0:0:-9:1583")
    G.AddRow(acc, 15210, 1, 800, "item:15210:0:0:0:0:0:-5:1583")
    G.AddRow(acc, 15210, 1, 950, "item:15210:0:0:0:0:0:-3:1583")   -- the fourth version: dropped
    G.AddRow(acc, 6125, 2, 1001, "item:6125::::::::20")              -- 500.5 a unit rounds to 501
    assert.same({ v = 1, at = 777, items = {
      [15210] = "500:-9:1583 700:-12:1583 800:-5:1583",
      [6125] = "501:0:0",
    } }, G.Freeze(acc, 777))
  end)

  it("counts a row without a link, folds nothing that is not a price, and freezes nothing from nothing", function()
    local acc = G.New()
    assert.is_false(G.AddRow(acc, 6125, 1, 100, nil))
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
end)
