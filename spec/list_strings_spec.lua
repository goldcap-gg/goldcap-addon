local helper = require("spec.spec_helper")

-- Core/ListStrings.lua: the two shopping-list strings other addons write, read and written as
-- plain data. The grammars are TSM's and Auctionator's own (the file's header says where each was
-- read); goldcap.gg reads the same two in packages/tsm's parseItemList.
describe("ListStrings", function()
  local LS

  before_each(function()
    local GC = helper.loadModule("Core/ListStrings.lua")
    LS = GC.ListStrings
  end)

  describe("a TSM string", function()
    it("reads item tokens, bare ids and the base item of a bonus-id token", function()
      local parsed = LS.Parse("i:2589, i:2592,2996, i:190395::2:1798:1810")
      assert.equal("tsm", parsed.format)
      assert.same({ { itemID = 2589, qty = 1 }, { itemID = 2592, qty = 1 }, { itemID = 2996, qty = 1 },
        { itemID = 190395, qty = 1 } }, parsed.lists[1].items)
      assert.is_nil(parsed.lists[1].name)
    end)

    it("names the list after its group, the last step of a sub-group's path, and skips pets", function()
      local parsed = LS.Parse("group:Leveling`Alchemy,i:1,p:2,group:Leveling`Alchemy`Herbs,i:3")
      assert.equal("Alchemy", parsed.lists[1].name)
      assert.same({ { itemID = 1, qty = 1 }, { itemID = 3, qty = 1 } }, parsed.lists[1].items)
      assert.same({ pets = 1, groups = 2 }, parsed.skipped)
    end)

    it("is not a TSM string when any token is something else", function()
      assert.is_nil(LS.Parse("i:2589,Linen Cloth"))
      assert.is_nil(LS.Parse("i:2589x"))
    end)

    -- TSM 4.10's packed export is deflated; Lua 5.1 has no inflate.
    it("says so about TSM's packed export rather than reading it as words", function()
      local _, why = LS.Parse("abcdefghijklmnopqrstuvwxyzABCDEF0123(())xyz")
      assert.equal("tsm_packed", why)
      _, why = LS.Parse("not a list at all")
      assert.equal("unknown", why)
      _, why = LS.Parse("   ")
      assert.equal("empty", why)
    end)
  end)

  describe("an Auctionator list", function()
    it("reads the name, exact and plain searches, and the quantity in the fourteenth field", function()
      local parsed = LS.Parse('Cooking^"Plant Protein";;;;;;;;;;;#;;210^Tavern Fixings^"Linen Cloth";;;;;;;;;;;;')
      assert.equal("auctionator", parsed.format)
      assert.equal("Cooking", parsed.lists[1].name)
      assert.same({ { name = "Plant Protein", qty = 210 }, { name = "Tavern Fixings", qty = 1 },
        { name = "Linen Cloth", qty = 1 } }, parsed.lists[1].items)
    end)

    it("reads one list per line, and an item id as an item", function()
      local parsed = LS.Parse('First^"A"\r\n\nSecond^i:2589;;;;;;;;;;;#;;4')
      assert.equal(2, #parsed.lists)
      assert.equal("Second", parsed.lists[2].name)
      assert.same({ { itemID = 2589, qty = 4 } }, parsed.lists[2].items)
    end)

    it("has no name when its first segment is itself an item", function()
      local parsed = LS.Parse('"Linen Cloth"^"Wool Cloth"')
      assert.is_nil(parsed.lists[1].name)
      assert.equal(2, #parsed.lists[1].items)
    end)

    it("counts a quantity that is no whole positive number as one", function()
      local parsed = LS.Parse('L^"A";;;;;;;;;;;#;;0^"B";;;;;;;;;;;#;;x^"C";;;;;;;;;;;#;;2.7')
      local items = parsed.lists[1].items
      assert.same({ 1, 1, 2 }, { items[1].qty, items[2].qty, items[3].qty })
    end)
  end)

  describe("names", function()
    it("finds an item by its name, case-blind and with its spaces evened out", function()
      local index = LS.NameIndex()
      index:Add(2589, "Linen Cloth")
      assert.equal(2589, index:Find("linen  cloth "))
      assert.is_nil(index:Find("Wool Cloth"))
    end)

    -- Crafted reagents come in ranks under one name: a name two items share says which of them
    -- nobody can tell.
    it("refuses a name two items go by", function()
      local index = LS.NameIndex()
      index:Add(1, "Ore")
      index:Add(1, "Ore")
      assert.equal(1, index:Find("Ore"))
      index:Add(2, "Ore")
      assert.is_false(index:Find("Ore"))
    end)

    it("turns found names into lines and hands back each one it could not", function()
      local lookup = function(name) return ({ A = 10, B = false })[name] end
      local lines, unresolved = LS.Resolve({ { name = "A", qty = 3 }, { itemID = 7, qty = 1 },
        { name = "B", qty = 1 }, { name = "C", qty = 2 }, { name = "c", qty = 1 } }, lookup)
      assert.same({ { i = 10, q = 3 }, { i = 7, q = 1 } }, lines)
      assert.same({ "B", "C" }, unresolved)
    end)
  end)

  describe("writing", function()
    it("writes a TSM item string in the list's order, once per item", function()
      assert.equal("i:2589,i:2592", LS.TSM({ { i = 2589, q = 20 }, { i = 2592, q = 5 }, { i = 2589, q = 1 } }))
    end)

    it("writes an Auctionator list the way Auctionator writes one, leaving vendor lines out", function()
      local names = { [1] = "Plant Protein", [3] = 'Deckhand\'s "Shirt"' }
      local text, missing = LS.Auctionator("Cooking 1-100",
        { { i = 1, q = 210 }, { i = 2, q = 215, v = true }, { i = 3, q = 1 } },
        function(id) return names[id] end)
      -- goldcap.gg's own export of the same list (packages/tsm's runStrings.test.ts).
      assert.equal('Cooking 1-100^"Plant Protein";;;;;;;;;;;#;;210^"Deckhand\'s Shirt";;;;;;;;;;;#;;1', text)
      assert.same({}, missing)
    end)

    it("never writes an item the client has not named as a blank search", function()
      local text, missing = LS.Auctionator("", { { i = 1, q = 2 }, { i = 2, q = 1 } },
        function(id) return id == 2 and "Wool Cloth" or nil end)
      assert.equal('GoldCap^"Wool Cloth";;;;;;;;;;;#;;1', text)
      assert.same({ 1 }, missing)
    end)

    it("keeps a separator out of a name", function()
      local text = LS.Auctionator("a^b;c\nd", { { i = 1, q = 2 } }, function() return "x^y;z" end)
      assert.equal('abcd^"xyz";;;;;;;;;;;#;;2', text)
    end)
  end)

  describe("round trips", function()
    it("TSM string -> list -> TSM string", function()
      local source = "i:2589,i:2592,i:2996"
      local parsed = LS.Parse(source)
      local lines = LS.Resolve(parsed.lists[1].items)
      assert.equal(source, LS.TSM(lines))
    end)

    it("Auctionator string -> list -> Auctionator string, for names the client can resolve", function()
      local source = 'My list^"Linen Cloth";;;;;;;;;;;#;;20^"Wool Cloth";;;;;;;;;;;#;;5'
      local ids = { ["Linen Cloth"] = 2589, ["Wool Cloth"] = 2592 }
      local names = { [2589] = "Linen Cloth", [2592] = "Wool Cloth" }
      local parsed = LS.Parse(source)
      local lines, unresolved = LS.Resolve(parsed.lists[1].items, function(n) return ids[n] end)
      assert.same({}, unresolved)
      assert.equal(source, (LS.Auctionator(parsed.lists[1].name, lines, function(id) return names[id] end)))
    end)
  end)
end)
