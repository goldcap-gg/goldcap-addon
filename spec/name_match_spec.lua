local helper = require("spec.spec_helper")

-- Core/NameMatch.lua: how a typed name is compared with the names GoldCap knows. Pure, so every
-- case is a row. The owner plays in Russian: a lower-case Cyrillic fragment has to find the item.
describe("NameMatch", function()
  local M

  before_each(function()
    M = helper.loadModule("Core/NameMatch.lua").NameMatch
  end)

  describe("Fold", function()
    local cases = {
      { "ASCII capitals", "LINEN Cloth", "linen cloth" },
      { "Russian capitals", "Плотные ЛЬНЯНЫЕ Бинты", "плотные льняные бинты" },
      { "every Russian capital, А to Я", "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ",
        "абвгдежзийклмнопрстуфхцчшщъыьэюя" },
      { "Ё reads as Е, both cases", "ЁЛКА ёлка", "елка елка" },
      { "Ukrainian і ї є ґ", "ІЇЄҐ іїєґ", "іїєґ іїєґ" },
      { "Latin-1 accents", "Éclat DE Fûr Ñandú Ça Ø", "eclat de fur nandu ca o" },
      { "German umlauts, ß kept", "Größe ÄÖÜ", "große aou" },
      { "Œ and Ÿ", "ŒUF Ÿ", "œuf y" },
      { "the times sign is no letter", "Linen ×20", "linen ×20" },
      { "white space runs and ends", "  Bolt\tof   Silk  ", "bolt of silk" },
      { "a Korean name untouched", "리넨 옷감", "리넨 옷감" },
      { "nothing", nil, "" },
    }
    for _, case in ipairs(cases) do
      it(case[1], function() assert.equal(case[3], M.Fold(case[2])) end)
    end
  end)

  describe("Find", function()
    local KNOWN = {
      { itemID = 1, name = "Плотные льняные бинты" },
      { itemID = 2, name = "Льняная ткань" },
      { itemID = 3, name = "Linen Cloth" },
      { itemID = 4, name = "Bolt of Linen Cloth" },
      { itemID = 5, name = "Heavy Linen Bandage" },
      { itemID = 6, name = "Silklinen Thread" },
      { itemID = 7, name = "Ёлочная игрушка" },
      { itemID = 3, name = "Ткань из льна" },
    }
    local function ids(found)
      local out = {}
      for i, e in ipairs(found) do out[i] = e.itemID end
      return out
    end
    local cases = {
      { "a lower-case Cyrillic fragment", "льнян", 10, { 2, 1 } },
      { "capitals find a mixed-case name", "LINEN", 10, { 3, 4, 5, 6 } },
      { "a name that starts with the query first, then a word that does, then the rest", "linen", 10,
        { 3, 4, 5, 6 } },
      { "every word, in any order", "cloth bolt", 10, { 4 } },
      { "е finds ё", "елоч", 10, { 7 } },
      { "one row per item, under its best name", "ткан", 10, { 3, 2 } },
      { "at most max", "linen", 2, { 3, 4 } },
      { "nothing for a name nobody knows", "Арканит", 10, {} },
      { "nothing for an empty query", "   ", 10, {} },
    }
    for _, case in ipairs(cases) do
      it(case[1], function() assert.same(case[4], ids(M.Find(KNOWN, case[2], case[3]))) end)
    end

    it("answers the entries it was given, so a caller keeps what it put on them", function()
      local entry = { itemID = 9, name = "Wool Cloth", source = "bags" }
      assert.equal(entry, M.Find({ entry }, "wool")[1])
    end)
  end)
end)
