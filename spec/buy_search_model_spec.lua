local helper = require("spec.spec_helper")

-- The BUY tab's search of the auction house as data (Core/BuySearchModel.lua): the rows a browse
-- answer becomes, their order, names that arrive later, and the one request the search keeps out
-- under the addon's request rules. Pure: the driver below is the whole client.
describe("BUY search model", function()
  local GC, M

  before_each(function()
    GC = helper.loadModule("Core/NameMatch.lua")
    helper.loadModule("Core/BuySearchModel.lua", GC)
    M = GC.BuySearchModel
  end)

  local function key(itemID, level) return { itemID = itemID, itemLevel = level or 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
  local function result(itemID, price, qty, level)
    return { itemKey = key(itemID, level), minPrice = price, totalQuantity = qty, containsOwnerItem = false }
  end

  describe("rows", function()
    local INFO = {
      [2589] = { itemName = "Linen Cloth", quality = 1, iconFileID = 11, isCommodity = true, isEquipment = false },
      [2996] = { itemName = "Bolt of Linen Cloth", quality = 1, iconFileID = 12, isCommodity = true, isEquipment = false },
      [4309] = { itemName = "Handstitched Linen Britches", quality = 2, iconFileID = 13, isCommodity = false, isEquipment = true },
    }
    local function infoOf(k) return INFO[k.itemID] end

    it("reads a browse answer into one row per item key, with what the client knows of each", function()
      local rows = M.Rows({ result(2589, 120, 400), result(4309, 9000, 2, 18), result(4309, 15000, 1, 22),
        result(9999, 50, 3), "junk", { itemKey = {} } }, infoOf)
      assert.equal(4, #rows)
      assert.same({ "2589:0:0:0", "4309:18:0:0", "4309:22:0:0", "9999:0:0:0" },
        { rows[1].id, rows[2].id, rows[3].id, rows[4].id })
      assert.equal("Linen Cloth", rows[1].name)
      assert.is_true(rows[1].commodity)
      assert.equal(400, rows[1].available)
      assert.equal(120, rows[1].minPrice)
      assert.equal(22, rows[3].itemLevel)
      assert.is_false(rows[3].commodity)
      -- A key the client has no name for yet is a row all the same, waiting for one.
      assert.is_false(rows[4].known)
      assert.is_nil(rows[4].name)
    end)

    -- Table-driven: what was typed, a name, and how close the name is.
    local CASES = {
      { "linen cloth", "Linen Cloth", 0 },
      { "linen", "Linen Cloth", 1 },
      { "linen", "Bolt of Linen Cloth", 2 },
      { "cloth linen", "Bolt of Linen Cloth", 3 },
      { "inen", "Linen Cloth", 3 },
      { "silk", "Linen Cloth", 4 },
      { "linen", nil, 4 },
      -- The Russian client: case-blind in Cyrillic too.
      { "льнян", "Льняная ткань", 1 },
      { "ТКАНЬ", "Льняная ткань", 2 },
    }
    for _, case in ipairs(CASES) do
      it(("ranks %q for %q as %d"):format(tostring(case[2]), case[1], case[3]), function()
        assert.equal(case[3], M.Relevance(case[2], case[1]))
      end)
    end

    it("shows the closest names first, the cheapest first among them, unknown names last", function()
      local rows = M.Sort(M.Rows({ result(2996, 300, 50), result(9999, 10, 5), result(2589, 120, 400),
        result(4309, 15000, 1, 22), result(4309, 9000, 2, 18) }, infoOf), "linen")
      local order = {}
      for i, row in ipairs(rows) do order[i] = row.id end
      -- "Bolt of Linen Cloth" and "Handstitched Linen Britches" both have a word that starts with it:
      -- the cheaper first, and the two britches the cheaper of them first.
      assert.same({ "2589:0:0:0", "2996:0:0:0", "4309:18:0:0", "4309:22:0:0", "9999:0:0:0" }, order)
    end)

    it("fills in a name that arrives later and puts the row where it belongs", function()
      local known = {}
      local function late(k) return known[k.itemID] end
      local rows = M.Sort(M.Rows({ result(2589, 120, 400), result(2996, 300, 50) }, late), "linen")
      assert.is_false(rows[1].known)
      known[2996] = INFO[2996]
      assert.is_true(M.Fill(rows, 2996, late))
      assert.is_false(M.Fill(rows, 2996, late)) -- once
      M.Sort(rows, "linen")
      assert.equal("Bolt of Linen Cloth", rows[1].name)
      assert.equal(300, rows[1].minPrice)
      assert.equal(50, rows[1].available)
      assert.is_false(rows[2].known)
    end)

    it("tells an answer to the search from rows that name something else", function()
      local rows = M.Rows({ result(2589, 1, 1), result(2996, 1, 1) }, infoOf)
      assert.is_true(M.ReadsAs(rows, "linen"))
      assert.is_true(M.ReadsAs(rows, "LINEN cloth"))
      assert.is_false(M.ReadsAs(rows, "silk"))
      -- Names not known yet say nothing either way.
      assert.is_false(M.ReadsAs(M.Rows({ result(9999, 1, 1) }, infoOf), "linen"))
      assert.is_false(M.ReadsAs({}, "linen"))
    end)
  end)

  describe("the request", function()
    local now, d, req, sent, mores, buffer, full, seq, writeOffs, ready, busy, keysOut, orphan, ahOpen

    before_each(function()
      now, sent, mores, buffer, full, seq, writeOffs = 100, {}, 0, {}, true, 0, 0
      ready, busy, keysOut, orphan, ahOpen = true, false, false, false, true
      d = {
        now = function() return now end,
        ahOpen = function() return ahOpen end,
        purchaseBusy = function() return busy end,
        keysOut = function() return keysOut end,
        writeOffKeys = function() writeOffs = writeOffs + 1; keysOut = false end,
        ready = function() return ready end,
        send = function(text) sent[#sent + 1] = text; seq = seq + 1 end,
        more = function() mores = mores + 1 end,
        browseSeq = function() return seq end,
        results = function() return buffer end,
        full = function() return full end,
        infoOf = function(k)
          return ({ [2589] = { itemName = "Linen Cloth" }, [2996] = { itemName = "Bolt of Linen Cloth" },
            [765] = { itemName = "Silverleaf" }, [2447] = { itemName = "Peacebloom" } })[k.itemID]
        end,
        keysOrphan = function() return orphan end,
      }
      req = M.NewRequest(d)
    end)

    it("sends at once when nothing stands in the way, and reads its answer", function()
      req:Submit("linen", 20)
      assert.same({ "linen" }, sent)
      assert.equal("out", req.state)
      assert.is_true(req:Owns())
      assert.is_true(req:Pending())
      buffer, full = { result(2996, 300, 50), result(2589, 120, 400) }, false
      assert.is_true(req:OnBrowse())
      assert.equal("done", req.state)
      assert.equal("Linen Cloth", req.rows[1].name)
      assert.is_false(req.full)
      assert.equal(20, req.query.qty)
      assert.is_false(req:Owns())
    end)

    -- Table-driven: what stands in the way, why the search says it waits, and what lets it go.
    local WAITS = {
      { what = "the throttle", set = function() ready = false end, reason = "throttle",
        clear = function() ready = true end },
      { what = "a purchase holding the search", set = function() busy = true end, reason = "purchase",
        clear = function() busy = false end },
    }
    for _, w in ipairs(WAITS) do
      it("waits for " .. w.what .. " and goes once it lets go", function()
        w.set()
        req:Submit("linen", 1)
        assert.same({}, sent)
        assert.equal("wait", req.state)
        assert.equal(w.reason, req.reason)
        assert.is_true(req:Owns())
        now = now + 1
        req:Step()
        assert.same({}, sent)
        w.clear()
        req:Step()
        assert.same({ "linen" }, sent)
      end)
    end

    it("lets an unanswered keys batch answer for a moment, then writes it off and goes", function()
      keysOut = true
      req:Submit("linen", 1)
      assert.equal("batch", req.reason)
      -- The wait is the batch's own: nothing claims the browse list over it meanwhile.
      assert.is_false(req:Owns())
      now = now + 1
      req:Step()
      assert.same({}, sent)
      assert.equal(0, writeOffs)
      now = now + M.HOLD_SECONDS
      req:Step()
      assert.equal(1, writeOffs)
      assert.same({ "linen" }, sent)
    end)

    it("goes without writing anything off when the batch answers within the hold", function()
      keysOut = true
      req:Submit("linen", 1)
      keysOut = false
      now = now + 1
      req:Step()
      assert.equal(0, writeOffs)
      assert.same({ "linen" }, sent)
    end)

    it("gives an unanswered request up once, and swallows its late answer", function()
      req:Submit("linen", 1)
      now = now + M.TIMEOUT_SECONDS
      req:Step()
      assert.equal("failed", req.state)
      assert.equal("timeout", req.failed)
      -- Its answer may still come: the buffer stays the search's until then.
      assert.is_true(req:Owns())
      buffer = { result(2589, 120, 400) }
      assert.is_true(req:OnBrowse())
      assert.is_false(req:OnBrowse()) -- the next answer is somebody else's
      assert.is_false(req:Owns())
      assert.equal("failed", req.state)
    end)

    it("sends nothing new into a given-up request's window", function()
      req:Submit("linen", 1)
      now = now + M.TIMEOUT_SECONDS
      req:Step()
      req:Submit("silk", 1)
      assert.same({ "linen" }, sent)
      assert.equal("answer", req.reason)
      now = now + M.ORPHAN_SECONDS
      req:Step()
      assert.same({ "linen", "silk" }, sent)
    end)

    it("gives a request up when the client drops a message", function()
      req:Submit("linen", 1)
      req:OnDropped()
      assert.equal("failed", req.state)
      assert.equal("dropped", req.failed)
    end)

    it("leaves a keys batch's answer to the batch", function()
      req:Submit("linen", 1)
      keysOut = true
      buffer = { result(765, 10, 10) }
      assert.is_false(req:OnBrowse())
      assert.equal("out", req.state)
    end)

    it("swallows a written-off batch's late answer and waits for its own", function()
      req:Submit("linen", 1)
      orphan = true
      buffer = { result(765, 10, 10), result(2447, 5, 5) }
      assert.is_true(req:OnBrowse())
      assert.equal("out", req.state)
      buffer = { result(2589, 120, 400) }
      assert.is_true(req:OnBrowse())
      assert.equal("done", req.state)
      assert.equal(2589, req.rows[1].itemID)
    end)

    it("takes its own answer even while a batch it shares an item with is an orphan", function()
      req:Submit("linen", 1)
      orphan = true
      buffer = { result(2589, 120, 400) }
      assert.is_true(req:OnBrowse())
      assert.equal("done", req.state)
    end)

    it("takes an empty answer as nothing on sale", function()
      req:Submit("zzz", 1)
      buffer = {}
      assert.is_true(req:OnBrowse())
      assert.equal("done", req.state)
      assert.same({}, req.rows)
    end)

    it("gives up when another browse request goes after its own, and leaves that answer alone", function()
      req:Submit("linen", 1)
      seq = seq + 1 -- the player's own search on Blizzard's pane, or another addon's
      buffer = { result(765, 10, 10) }
      assert.is_false(req:OnBrowse())
      assert.equal("failed", req.state)
      assert.equal("lost", req.failed)
      assert.is_false(req:Owns())
    end)

    it("pages for more while the browse list is still its own, keeping what it had", function()
      req:Submit("linen", 1)
      buffer, full = { result(2589, 120, 400) }, false
      req:OnBrowse()
      assert.is_true(req:More())
      assert.equal(1, mores)
      assert.equal("more", req.kind)
      buffer, full = { result(2589, 120, 400), result(2996, 300, 50) }, true
      assert.is_true(req:OnBrowse())
      assert.equal(2, #req.rows)
      assert.is_true(req.full)
      assert.is_false(req:More()) -- the whole answer is in
    end)

    it("keeps the earlier pages when the client hands back only the new one", function()
      req:Submit("linen", 1)
      buffer, full = { result(2589, 120, 400) }, false
      req:OnBrowse()
      req:More()
      buffer, full = { result(2996, 300, 50) }, true
      req:OnBrowse()
      assert.equal(2, #req.rows)
    end)

    it("starts over when somebody else has used the browse list since", function()
      req:Submit("linen", 1)
      buffer, full = { result(2589, 120, 400) }, false
      req:OnBrowse()
      seq = seq + 1
      assert.is_true(req:More())
      assert.equal(0, mores)
      assert.same({ "linen", "linen" }, sent)
      assert.equal("first", req.kind)
    end)

    it("answers a request out for the search typed after it", function()
      req:Submit("linen", 1)
      req:Submit("silk", 2)
      assert.same({ "linen" }, sent)
      buffer = { result(2589, 120, 400) }
      assert.is_true(req:OnBrowse())
      assert.same({ "linen", "silk" }, sent)
      assert.equal("out", req.state)
      assert.equal(2, req.query.qty)
    end)

    it("waits for nothing once the auction house is closed", function()
      ahOpen = false
      req:Submit("linen", 1)
      assert.same({}, sent)
      assert.equal("idle", req.state)
      ahOpen = true
      req:Submit("linen", 1)
      req:OnClosed()
      assert.equal("idle", req.state)
      assert.is_false(req:Owns())
      assert.is_false(req:OnBrowse())
    end)

    it("fills in a late name and re-sorts", function()
      local names = {}
      d.infoOf = function(k) return names[k.itemID] end
      req:Submit("linen", 1)
      buffer = { result(2589, 120, 400) }
      req:OnBrowse()
      assert.is_false(req.rows[1].known)
      names[2589] = { itemName = "Linen Cloth" }
      assert.is_true(req:OnItemKeyInfo(2589))
      assert.equal("Linen Cloth", req.rows[1].name)
      assert.is_false(req:OnItemKeyInfo(765))
    end)

    it("swallows the answer of a search put away while it was out", function()
      req:Submit("linen", 1)
      req:Cancel()
      assert.equal("idle", req.state)
      buffer = { result(2589, 120, 400) }
      assert.is_true(req:OnBrowse())
      assert.is_false(req:OnBrowse())
    end)
  end)
end)
