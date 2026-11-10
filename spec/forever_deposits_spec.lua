local helper = require("spec.spec_helper")

-- WoW: Forever's lost deposits (Core/ForeverDeposits.lua): a record of every post certain to be
-- ours, the expired lot joined to it and its share of the deposit, the cancelled lot's row, and
-- the per-character run of lots that came back unsold. Pure: the client is reached only through
-- the module's replaceable fields, stubbed here.
--
-- A key is spelled with "\1" .. id, never "\1501": Lua reads "\150" as one byte.
describe("ForeverDeposits", function()
  local GC, db, D, quotes
  local CTX = { char = "A-R", region = "eu", faction = "Alliance" }
  local HOURS = { 2, 8, 24 }
  local DAY = 86400

  local function pin(fields)
    local p = { itemID = 42, quantity = 7, duration = 1, deposit = 99, isCommodity = false,
      position = { itemName = "Silk" } }
    for k, v in pairs(fields or {}) do p[k] = v end
    return p
  end

  -- A lot as GC.MailReturns.Observe hands it on: { itemID, count, reason, at, expiresAt }.
  local function lot(count, now, fields)
    local l = { itemID = 42, count = count, reason = "expired", at = now, expiresAt = now + 30 * DAY }
    for k, v in pairs(fields or {}) do l[k] = v end
    return l
  end

  local function rowsOf(kind)
    local out = {}
    for _, entry in ipairs(GC.Ledger.GetEntries()) do
      if entry.kind == kind then out[#out + 1] = entry end
    end
    return out
  end

  before_each(function()
    db = {}
    GC = helper.loadModule("Core/Ledger.lua")
    GC.Ledger.Init(db)
    helper.loadModule("Core/MailReturns.lua", GC)
    GC.MailReturns.Init(db)
    GC.ForeverScan = { Root = function() return db end }
    helper.loadModule("Core/ForeverDeposits.lua", GC)
    D = GC.ForeverDeposits
    quotes = {}
    D.HoursOf = function(index) return HOURS[index] end
    D.QuoteCommodity = function(itemID, quantity, durationIndex)
      quotes[#quotes + 1] = { itemID, quantity, durationIndex }
      return nil
    end
    D.IsCommodity = function() return false end
    D.NameOf = function(itemID) return "Item " .. itemID end
    D.SettingIndex = function() return 2 end
  end)

  it("keeps its constants", function()
    assert.equal(1, D.VERSION)
    assert.equal(3 * DAY, D.KEEP_SECONDS)
    assert.equal(3600, D.ROUND_GAP_SECONDS)
    assert.equal(14 * DAY, D.STREAK_SECONDS)
    assert.equal(20, D.MAX_ROUNDS)
  end)

  describe("records a certain post", function()
    it("with the deposit the pin carries and the hours its duration lasts", function()
      local record = D.RecordPost(501, pin(), CTX, 1000)
      assert.same({ auctionID = 501, itemID = 42, itemName = "Silk", quantity = 7, duration = 1, deposit = 99,
        postedAt = 1000, endsAt = 1000 + 2 * 3600, char = "A-R", region = "eu", faction = "Alliance",
        commodity = false }, db.foreverDeposits.posts[501])
      assert.equal(db.foreverDeposits.posts[501], record)
      assert.equal(1, db.foreverDeposits.v)
      assert.equal(99, D.DepositOf(501))
    end)

    it("hands out the deposit's share for the units still listed", function()
      D.RecordPost(501, pin({ quantity = 200, deposit = 20000 }), CTX, 1000)
      assert.equal(1000, D.DepositOf(501, 10))
      assert.equal(20000, D.DepositOf(501, 200))
      assert.equal(20000, D.DepositOf(501, 250))
      assert.equal(20000, D.DepositOf(501))
      assert.is_nil(D.DepositOf(501, 0))
      assert.is_nil(D.DepositOf(502, 10))
    end)

    it("quotes a commodity's deposit then, for its quantity and duration", function()
      D.QuoteCommodity = function(itemID, quantity, durationIndex)
        quotes[#quotes + 1] = { itemID, quantity, durationIndex }
        return 30
      end
      D.RecordPost(502, pin({ isCommodity = true, quantity = 12, duration = 3, deposit = 5 }), CTX, 1000)
      assert.same({ { 42, 12, 3 } }, quotes)
      assert.equal(30, db.foreverDeposits.posts[502].deposit)
      assert.is_true(db.foreverDeposits.posts[502].commodity)
      assert.equal(1000 + 24 * 3600, db.foreverDeposits.posts[502].endsAt)
    end)

    it("keeps an unquoted deposit unknown", function()
      local unquoted = pin()
      unquoted.deposit = nil
      D.RecordPost(501, unquoted, CTX, 1000)
      assert.is_nil(db.foreverDeposits.posts[501].deposit)
      assert.is_nil(D.DepositOf(501))
    end)

    it("records nothing without an auction id, an item, a quantity, a duration or a character", function()
      assert.is_nil(D.RecordPost(nil, pin(), CTX, 1000))
      assert.is_nil(D.RecordPost(0, pin(), CTX, 1000))
      assert.is_nil(D.RecordPost(501.5, pin(), CTX, 1000))
      assert.is_nil(D.RecordPost(501, pin({ itemID = "42" }), CTX, 1000))
      assert.is_nil(D.RecordPost(501, pin({ quantity = 0 }), CTX, 1000))
      assert.is_nil(D.RecordPost(501, pin({ duration = 4 }), CTX, 1000))
      assert.is_nil(D.RecordPost(501, pin(), { region = "eu" }, 1000))
      assert.is_nil(D.RecordPost(501, pin(), { char = "A-R" }, 1000))
      assert.is_nil(db.foreverDeposits)
    end)

    it("forgets a post after three days", function()
      D.RecordPost(501, pin(), CTX, 1000)
      D.RecordPost(502, pin(), CTX, 1000 + D.KEEP_SECONDS)
      assert.is_not_nil(db.foreverDeposits.posts[501])
      D.RecordPost(503, pin(), CTX, 1001 + D.KEEP_SECONDS)
      assert.is_nil(db.foreverDeposits.posts[501])
      assert.is_not_nil(db.foreverDeposits.posts[502])
    end)
  end)

  describe("an expired lot", function()
    it("costs its share of the deposit", function()
      D.RecordPost(501, pin(), CTX, 1000)
      local rows = D.OnReturns({ lot(3, 9000) }, CTX, 9000)
      assert.same({ { key = "deposit\1" .. 501, kind = "expired", source = "mail", itemID = 42, itemName = "Silk",
        qty = 3, total = 0, deposit = 42, cut = 0, pending = false, at = 1000 + 7200, char = "A-R",
        region = "eu" } }, rows)
      assert.same(rows, rowsOf("expired"))
      assert.equal(9000, db.foreverDeposits.posts[501].joinedAt)

      D.RecordPost(502, pin(), CTX, 1000)
      assert.equal(99, D.OnReturns({ lot(7, 9000) }, CTX, 9000)[1].deposit)
    end)

    it("joins the record of equal quantity first", function()
      D.RecordPost(501, pin({ quantity = 3 }), CTX, 1000)
      D.RecordPost(502, pin({ quantity = 7 }), CTX, 1500)
      local rows = D.OnReturns({ lot(7, 9000) }, CTX, 9000)
      assert.equal("deposit\1" .. 502, rows[1].key)
    end)

    it("joins two equal lots one each, the older first", function()
      local B = 100000
      D.RecordPost(502, pin({ quantity = 5 }), CTX, B + 3000 - 7200)
      D.RecordPost(501, pin({ quantity = 5 }), CTX, B + 2000 - 7200)
      local rows = D.OnReturns({ lot(5, B + 4000), lot(5, B + 4000) }, CTX, B + 4000)
      assert.same({ "deposit\1" .. 501, "deposit\1" .. 502 }, { rows[1].key, rows[2].key })
      assert.same({ B + 2000, B + 3000 }, { rows[1].at, rows[2].at })
    end)

    it("joins by the lower auction id between two that ended together", function()
      D.RecordPost(502, pin({ quantity = 5 }), CTX, 1000)
      D.RecordPost(501, pin({ quantity = 5 }), CTX, 1000)
      assert.equal("deposit\1" .. 501, D.OnReturns({ lot(5, 9000) }, CTX, 9000)[1].key)
    end)

    it("is not joined to a lot that ends 10 minutes after the read", function()
      local now = 1000 + 7200 - 600
      D.RecordPost(501, pin(), CTX, 1000)
      local rows = D.OnReturns({ lot(7, now) }, CTX, now)
      assert.equal("deposit\1mail\1A-R\1" .. "42\1" .. (now + 30 * DAY), rows[1].key)
      assert.equal(0, rows[1].deposit)
      assert.equal(now, rows[1].at)
      assert.is_nil(db.foreverDeposits.posts[501].joinedAt)
    end)

    it("is joined to one that ends within five minutes of the read", function()
      local now = 1000 + 7200 - 300
      D.RecordPost(501, pin(), CTX, 1000)
      local rows = D.OnReturns({ lot(7, now) }, CTX, now)
      assert.equal("deposit\1" .. 501, rows[1].key)
      -- Dated no later than the mail was read.
      assert.equal(now, rows[1].at)
      D.RecordPost(502, pin(), CTX, 1000)
      assert.equal("deposit\1mail\1A-R\1" .. "42\1" .. (now - 1 + 30 * DAY),
        D.OnReturns({ lot(7, now - 1) }, CTX, now - 1)[1].key)
    end)

    it("is joined only to this character's and realm's records of the item", function()
      D.RecordPost(501, pin(), { char = "B-R", region = "eu" }, 1000)
      D.RecordPost(502, pin(), { char = "A-R", region = "us" }, 1000)
      D.RecordPost(503, pin({ itemID = 43 }), CTX, 1000)
      local rows = D.OnReturns({ lot(7, 9000) }, CTX, 9000)
      assert.equal("deposit\1mail\1A-R\1" .. "42\1" .. (9000 + 30 * DAY), rows[1].key)
    end)

    it("with no record: a commodity is quoted again at the setting, anything else costs 0", function()
      D.IsCommodity = function(itemID) return itemID == 42 end
      D.QuoteCommodity = function(itemID, quantity, durationIndex)
        quotes[#quotes + 1] = { itemID, quantity, durationIndex }
        return 30
      end
      local rows = D.OnReturns({ lot(4, 9000) }, CTX, 9000)
      assert.same({ { 42, 4, 2 } }, quotes)
      assert.same({ key = "deposit\1mail\1A-R\1" .. "42\1" .. (9000 + 30 * DAY), kind = "expired", source = "mail",
        itemID = 42, itemName = "Item 42", qty = 4, total = 0, deposit = 30, cut = 0, pending = false, at = 9000,
        char = "A-R", region = "eu" }, rows[1])

      D.QuoteCommodity = function() return nil end
      assert.equal(0, D.OnReturns({ lot(4, 9100) }, CTX, 9100)[1].deposit)
      D.QuoteCommodity = function() error("not at the auction house") end
      assert.equal(0, D.OnReturns({ lot(4, 9200) }, CTX, 9200)[1].deposit)

      D.IsCommodity = function() return false end
      D.QuoteCommodity = function() return 30 end
      assert.equal(0, D.OnReturns({ lot(4, 9300) }, CTX, 9300)[1].deposit)
    end)

    it("sums a lot that came back in several mails, and joins it whole", function()
      D.RecordPost(501, pin({ quantity = 200, deposit = 600 }), CTX, 1000)
      local rows = D.OnReturns({ lot(100, 9000), lot(100, 9000) }, CTX, 9000)
      assert.equal(1, #rows)
      assert.same({ "deposit\1" .. 501, 200, 600 }, { rows[1].key, rows[1].qty, rows[1].deposit })
      assert.equal(1, (D.Streak(42, CTX, 9000)))
    end)

    it("places summed units on as many records as they fill, and what is left on a row of its own", function()
      D.RecordPost(501, pin({ quantity = 3, deposit = 30 }), CTX, 1000)
      D.RecordPost(502, pin({ quantity = 7, deposit = 70 }), CTX, 1500)
      local rows = D.OnReturns({ lot(6, 9000), lot(6, 9000) }, CTX, 9000)
      assert.same({ "deposit\1" .. 501, 3, 30 }, { rows[1].key, rows[1].qty, rows[1].deposit })
      assert.same({ "deposit\1" .. 502, 7, 70 }, { rows[2].key, rows[2].qty, rows[2].deposit })
      assert.same({ "deposit\1mail\1A-R\1" .. "42\1" .. (9000 + 30 * DAY), 2, 0 },
        { rows[3].key, rows[3].qty, rows[3].deposit })
    end)

    it("sums two unrecorded lots of one expiry, and keeps a later lot under a taken key on its own row", function()
      local rows = D.OnReturns({ lot(1, 9000), lot(1, 9000) }, CTX, 9000)
      assert.equal(1, #rows)
      assert.equal(2, rows[1].qty)
      local again = D.OnReturns({ lot(1, 9000) }, CTX, 9000)
      assert.are_not.equal(rows[1].key, again[1].key)
      assert.equal(2, #rowsOf("expired"))
    end)

    it("costs nothing for a record whose saved deposit is damaged", function()
      D.RecordPost(501, pin(), CTX, 1000)
      db.foreverDeposits.posts[501].deposit = "x"
      local rows = D.OnReturns({ lot(7, 9000) }, CTX, 9000)
      assert.same({ "deposit\1" .. 501, 0 }, { rows[1].key, rows[1].deposit })
      assert.is_nil(D.DepositOf(501))
    end)

    it("writes nothing for a cancelled lot's mail", function()
      D.RecordPost(501, pin(), CTX, 1000)
      assert.same({}, D.OnReturns({ lot(7, 9000, { reason = "cancelled" }) }, CTX, 9000))
      assert.same({}, rowsOf("expired"))
      assert.equal(0, (D.Streak(42, CTX, 9000)))
    end)
  end)

  -- A lot that sold never comes back by mail: the owned list says so, and its record joins nothing.
  describe("an owned-list read", function()
    local T = 1000000
    local function posts() return db.foreverDeposits.posts end

    it("keeps a sold lot's record from taking the deposit of the lot that came back", function()
      -- Silk, 5 units: 8 h for 40c, and it sold; then 24 h for 120c, and it expired.
      D.RecordPost(501, pin({ quantity = 5, duration = 2, deposit = 40 }), CTX, T)
      D.OnOwnedRoster({}, CTX, T + 3600, {})
      assert.equal(T + 3600, posts()[501].goneAt)
      local second = T + 9 * 3600
      D.RecordPost(502, pin({ quantity = 5, duration = 3, deposit = 120 }), CTX, second)
      D.OnOwnedRoster({ { auctionID = 502, status = 0 } }, CTX, second + 60, {})
      assert.is_nil(posts()[502].goneAt)
      local now = second + 24 * 3600 + 60
      local rows = D.OnReturns({ lot(5, now) }, CTX, now)
      assert.same({ "deposit\1" .. 502, 120, second + 24 * 3600 }, { rows[1].key, rows[1].deposit, rows[1].at })
      assert.same({ 1, 0 }, { D.Streak(42, CTX, now) })
    end)

    it("marks a lot it shows sold gone", function()
      D.RecordPost(501, pin(), CTX, T)
      D.OnOwnedRoster({ { auctionID = 501, status = 1 } }, CTX, T + 60, {})
      assert.equal(T + 60, posts()[501].goneAt)
    end)

    it("leaves a lot whose cancel is on its way, a cancelled one and another character's", function()
      D.RecordPost(501, pin(), CTX, T)
      D.RecordPost(502, pin(), CTX, T)
      D.RecordPost(503, pin(), { char = "B-R", region = "eu" }, T)
      D.Cancelled(502, { auctionID = 502, itemID = 42, quantity = 7 }, nil, CTX, T + 30)
      D.OnOwnedRoster({}, CTX, T + 60, { [501] = { at = T + 30 } })
      assert.is_nil(posts()[501].goneAt)
      assert.is_nil(posts()[502].goneAt)
      assert.is_nil(posts()[503].goneAt)
    end)

    it("reads nothing into a read in the second of the post, or into a lot gone after its end", function()
      D.RecordPost(501, pin({ duration = 1 }), CTX, T)
      D.OnOwnedRoster({}, CTX, T, {})
      assert.is_nil(posts()[501].goneAt)
      D.OnOwnedRoster({}, CTX, T + 2 * 3600, {})
      assert.is_nil(posts()[501].goneAt)
    end)

    it("still listed, it stays a record to join", function()
      D.RecordPost(501, pin(), CTX, T)
      D.OnOwnedRoster({ { auctionID = 501, status = 0 } }, CTX, T + 60, {})
      assert.is_nil(posts()[501].goneAt)
      assert.equal("deposit\1" .. 501, D.OnReturns({ lot(7, T + 7200) }, CTX, T + 7200)[1].key)
    end)
  end)

  describe("a cancelled lot", function()
    it("loses the recorded deposit for its units", function()
      D.RecordPost(501, pin({ quantity = 20, deposit = 100 }), CTX, 1000)
      local row = D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 12 }, 35, CTX, 2000)
      assert.same({ key = "deposit\1" .. 501, kind = "cancelled", source = "auction", itemID = 42, itemName = "Silk",
        qty = 12, total = 0, deposit = 60, cut = 0, pending = false, at = 2000, char = "A-R", region = "eu" }, row)
      assert.same({ row }, rowsOf("cancelled"))
      assert.equal(2000, db.foreverDeposits.posts[501].cancelledAt)
    end)

    it("loses the record's units when the event names no lot", function()
      D.RecordPost(501, pin({ quantity = 20, deposit = 100 }), CTX, 1000)
      local row = D.Cancelled(501, nil, nil, CTX, 2000)
      assert.equal(20, row.qty)
      assert.equal(100, row.deposit)
    end)

    it("without a record loses the estimate, else nothing", function()
      local row = D.Cancelled(502, { auctionID = 502, itemID = 42, quantity = 12, itemName = "Silk" }, 35, CTX, 2000)
      assert.equal(35, row.deposit)
      assert.equal(12, row.qty)
      assert.equal("Silk", row.itemName)
      assert.equal(0, D.Cancelled(503, { auctionID = 503, itemID = 42, quantity = 12 }, nil, CTX, 2000).deposit)
      assert.equal("Item 42", rowsOf("cancelled")[2].itemName)
    end)

    it("writes one row, however often it is answered", function()
      D.RecordPost(501, pin({ quantity = 20, deposit = 100 }), CTX, 1000)
      assert.is_not_nil(D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 12 }, nil, CTX, 2000))
      assert.is_nil(D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 12 }, nil, CTX, 2001))
      assert.is_not_nil(D.Cancelled(502, { auctionID = 502, itemID = 42, quantity = 1 }, 5, CTX, 2000))
      assert.is_nil(D.Cancelled(502, { auctionID = 502, itemID = 42, quantity = 1 }, 5, CTX, 2001))
      assert.equal(2, #rowsOf("cancelled"))
    end)

    it("writes nothing when no item is known", function()
      assert.is_nil(D.Cancelled(501, nil, 35, CTX, 2000))
      assert.is_nil(D.Cancelled(nil, { auctionID = 1, itemID = 42, quantity = 1 }, 35, CTX, 2000))
      assert.same({}, rowsOf("cancelled"))
    end)

    it("is no longer joined when its lot comes back by mail", function()
      D.RecordPost(501, pin({ quantity = 20, deposit = 100 }), CTX, 1000)
      D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 20 }, nil, CTX, 2000)
      local rows = D.OnReturns({ lot(20, 9000) }, CTX, 9000)
      assert.equal("deposit\1mail\1A-R\1" .. "42\1" .. (9000 + 30 * DAY), rows[1].key)
    end)

    it("takes the lot and the estimate GoldCap's own cancel noted over the event's", function()
      D.NoteCancel({ auctionID = 502, itemID = 42, quantity = 5, positionKey = "commodity:42" }, 44, 1900)
      local row = D.Cancelled(502, { auctionID = 502, itemID = 42, quantity = 9 }, 70, CTX, 2000)
      assert.equal(5, row.qty)
      assert.equal(44, row.deposit)

      D.RecordPost(501, pin({ quantity = 20, deposit = 100 }), CTX, 1000)
      D.NoteCancel({ auctionID = 501, itemID = 42, quantity = 5 }, 44, 1900)
      row = D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 20 }, 70, CTX, 2000)
      assert.equal(5, row.qty)
      assert.equal(25, row.deposit)
    end)

  end)

  describe("the streak", function()
    local T = 1000000

    local function back(at, duration, auctionID)
      if duration then
        D.RecordPost(auctionID or at, pin({ quantity = 1, duration = duration }), CTX, at - HOURS[duration] * 3600)
      end
      D.OnReturns({ lot(1, at) }, CTX, at)
    end

    it("counts returns within an hour of each other as one round", function()
      back(T)
      back(T + 1800)
      assert.same({ 1, 0 }, { D.Streak(42, CTX, T + 1800) })
      back(T + 1800 + 3601)
      assert.equal(2, (D.Streak(42, CTX, T + 1800 + 3601)))
    end)

    it("counts returns two hours apart as two rounds", function()
      back(T)
      back(T + 7200)
      assert.equal(2, (D.Streak(42, CTX, T + 7200)))
    end)

    it("counts the rounds under 24 h and names the last one's duration", function()
      back(T, 1)
      back(T + 7200, 1)
      assert.same({ 2, 2, 1 }, { D.Streak(42, CTX, T + 7200) })
    end)

    it("does not count a 24 h round as short, nor let it reset the short ones", function()
      back(T, 1)
      back(T + 7200, 3)
      assert.same({ 2, 1, 1 }, { D.Streak(42, CTX, T + 7200) })
      back(T + 14400, 2)
      assert.same({ 3, 2, 2 }, { D.Streak(42, CTX, T + 14400) })
    end)

    it("ends at a sale, and a return stamped with the sale's second counts after it", function()
      back(T)
      back(T + 1800)
      D.Sold(42, T + 5000, CTX)
      assert.same({ 0, 0 }, { D.Streak(42, CTX, T + 5000) })
      back(T + 5000)
      assert.equal(1, (D.Streak(42, CTX, T + 5000)))
      -- An older sale read later moves nothing back.
      D.Sold(42, T + 100, CTX)
      assert.equal(1, (D.Streak(42, CTX, T + 5000)))
    end)

    it("does not count a round older than 14 days", function()
      back(T)
      back(T + 7200)
      assert.equal(1, (D.Streak(42, CTX, T + D.STREAK_SECONDS + 1)))
      assert.equal(0, (D.Streak(42, CTX, T + 7200 + D.STREAK_SECONDS + 1)))
    end)

    it("keeps nothing for a sale of an item that never came back", function()
      D.Sold(42, T, CTX)
      D.Sold(43, T, CTX)
      assert.same({}, db.foreverDeposits and db.foreverDeposits.streaks or {})
      back(T + 10)
      assert.equal(1, (D.Streak(42, CTX, T + 10)))
    end)

    it("is this character's: another character's sale does not end it", function()
      back(T)
      D.Sold(42, T + 5000, { char = "B-R", region = "eu" })
      D.Sold(42, T + 5000, { char = "A-R", region = "us" })
      assert.equal(1, (D.Streak(42, CTX, T + 5000)))
      assert.equal(0, (D.Streak(42, { char = "B-R", region = "eu" }, T + 5000)))
    end)

    it("keeps the newest rounds only", function()
      for i = 0, D.MAX_ROUNDS + 4 do back(T + i * 7200) end
      local now = T + (D.MAX_ROUNDS + 4) * 7200
      assert.equal(D.MAX_ROUNDS, (D.Streak(42, CTX, now)))
      local key = CTX.char .. "\1" .. CTX.region
      assert.equal(D.MAX_ROUNDS, #db.foreverDeposits.streaks[key][42].rounds)
    end)

    it("reads none for an item it never saw, or without a character", function()
      assert.same({ 0, 0 }, { D.Streak(99, CTX, T) })
      assert.is_nil(select(3, D.Streak(99, CTX, T)))
      back(T)
      assert.same({ 0, 0 }, { D.Streak(42, nil, T) })
    end)
  end)

  it("asks the client only through its guarded defaults", function()
    helper.loadModule("Core/ForeverDeposits.lua", GC)
    D = GC.ForeverDeposits
    GC.Flips = { CommodityDeposit = function(itemID, quantity, durationIndex) return itemID + quantity + durationIndex end,
      PostDurationIndex = function() return 3 end }
    GC.GroupRules = { HoursOf = function(index) return index * 10 end }
    GC.db = { commodityByItem = { [42] = true, [43] = false } }
    _G.C_Item = { GetItemNameByID = function(itemID) return itemID == 42 and "Silk" or nil end }
    assert.equal(42 + 5 + 1, D.QuoteCommodity(42, 5, 1))
    assert.equal(3, D.SettingIndex())
    assert.equal(20, D.HoursOf(2))
    assert.is_true(D.IsCommodity(42))
    assert.is_false(D.IsCommodity(43))
    assert.is_false(D.IsCommodity(44))
    assert.equal("Silk", D.NameOf(42))
    assert.is_nil(D.NameOf(43))
    GC.Flips.CommodityDeposit = function() error("no auction house") end
    _G.C_Item = { GetItemNameByID = function() error("not loaded") end }
    assert.is_nil(D.QuoteCommodity(42, 5, 1))
    assert.is_nil(D.NameOf(42))
    GC.Flips, GC.GroupRules, GC.db = nil, nil, nil
    _G.C_Item = nil
    assert.is_nil(D.QuoteCommodity(42, 5, 1))
    assert.is_false(D.IsCommodity(42))
    assert.is_nil(D.NameOf(42))
  end)

  it("writes nothing on retail", function()
    GC.ForeverScan.Root = function() return nil end
    assert.is_nil(D.RecordPost(501, pin(), CTX, 1000))
    assert.is_nil(D.OnReturns({ lot(7, 9000) }, CTX, 9000))
    D.NoteCancel({ auctionID = 501, itemID = 42, quantity = 7 }, 44, 9000)
    assert.is_nil(D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 7 }, 44, CTX, 9000))
    D.Sold(42, 9000, CTX)
    assert.is_nil(D.DepositOf(501))
    assert.same({ 0, 0 }, { D.Streak(42, CTX, 9000) })
    assert.same({}, GC.Ledger.GetEntries())
    assert.is_nil(db.foreverDeposits)
  end)

  it("leaves a newer save as it is", function()
    D.RecordPost(501, pin(), CTX, 1000)
    db.foreverDeposits.v = 2
    local before = {}
    for k, v in pairs(db.foreverDeposits.posts[501]) do before[k] = v end
    assert.is_nil(D.RecordPost(502, pin(), CTX, 1100))
    assert.is_nil(D.OnReturns({ lot(7, 9000) }, CTX, 9000))
    assert.is_nil(D.Cancelled(501, { auctionID = 501, itemID = 42, quantity = 7 }, 44, CTX, 9000))
    D.Sold(42, 9000, CTX)
    assert.is_nil(D.DepositOf(501))
    assert.same({ 0, 0 }, { D.Streak(42, CTX, 9000) })
    assert.same(before, db.foreverDeposits.posts[501])
    assert.is_nil(db.foreverDeposits.posts[502])
    assert.same({}, db.foreverDeposits.streaks)
    assert.same({}, GC.Ledger.GetEntries())
  end)
end)
