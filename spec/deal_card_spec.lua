local helper = require("spec.spec_helper")

-- Core/DealCard.lua: what the DEALS row's tooltip card and the check panel show, for every row
-- kind and every verdict, without a frame in sight.
describe("DealCard", function()
  local GC, DC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    helper.loadModule("Core/DealCard.lua", GC)
    DC = GC.DealCard
  end)

  after_each(function() _G.GetCoinTextureString = nil end)

  describe("Pill", function()
    local cases = {
      { "a buyable check, with its age", {}, { buyable = true }, 4, "safe", "SAFE · LIVE 4s AGO" },
      { "a row nothing has checked", {}, nil, nil, "warn", "NOT CHECKED YET" },
      { "a pinned placeholder", { pinPlaceholder = true }, nil, nil, "muted", "WATCHING" },
      { "a refusal", {}, { status = "WATCH" }, 30, "refuse", "WON'T BUY" },
      { "a deal only the wallet stopped", {}, { needsGold = 25000 }, 1, "warn", "NEEDS 2g 50s ON THIS CHARACTER" },
      { "a realm lot the check found", {}, { unverified = true }, 1, "warn", "YOUR CALL" },
      { "a cap row", { cap = true }, nil, nil, "safe", "YOUR PRICE" },
      { "a followed group's cap", { cap = true, capFollowed = true }, nil, nil, "safe", "GROUP" },
      { "a rare find", { kind = "rare" }, nil, nil, "warn", "RARE FIND" },
    }
    for _, c in ipairs(cases) do
      it("reads " .. c[1], function()
        local pill = DC.Pill(c[2], c[3], c[4])
        assert.equal(c[5], pill.tone)
        assert.equal(c[6], pill.text)
      end)
    end
  end)

  describe("Big", function()
    it("says how far over the limit a refused row is", function()
      local big = DC.Big({ unitPrice = 1520, ceiling = 850 }, { status = "WATCH" }, 0)
      assert.same({ label = "Over your limit by", text = GC.Util.FormatMoney(670), tone = "loss" }, big)
    end)

    it("measures the cheapest listing the check read, not the price the row was found at", function()
      local verdict = { status = "WATCH", unitPrice = 800, levels = { { unitPrice = 1520, quantity = 3 } } }
      assert.equal(1520, DC.Cheapest({ unitPrice = 800 }, verdict))
      assert.equal(GC.Util.FormatMoney(670), DC.Big({ unitPrice = 800, ceiling = 850 }, verdict, 0).text)
      -- Refused for another reason, under its limit: no number, the reason says why.
      assert.is_nil(DC.Big({ unitPrice = 800, ceiling = 850 }, { status = "WATCH", unitPrice = 800 }, 0))
    end)

    it("has no number for a refusal without a limit", function()
      assert.is_nil(DC.Big({ unitPrice = 1520 }, { status = "WATCH" }, 0))
    end)

    it("is exact for a vendor deal and an estimate otherwise", function()
      assert.equal("+" .. GC.Util.FormatMoney(113), DC.Big({ forever = "vendor" }, nil, 113).text)
      assert.equal("You make", DC.Big({ forever = "vendor" }, nil, 113).label)
      assert.equal("~+" .. GC.Util.FormatMoney(113), DC.Big({ forever = "market" }, nil, 113).text)
      assert.equal("You make about", DC.Big({}, { buyable = true }, 113).label)
    end)

    it("has no number for a deal with no profit, or a rare find", function()
      assert.is_nil(DC.Big({}, nil, 0))
      assert.is_nil(DC.Big({ kind = "rare" }, nil, 500))
    end)
  end)

  describe("Scale", function()
    it("places the three marks as shares of the bar", function()
      local s = DC.Scale(500, 850, 1700, "market")
      assert.near(500 / 1870, s.cheap, 1e-9)
      assert.near(850 / 1870, s.limit, 1e-9)
      assert.near(1700 / 1870, s.ref, 1e-9)
      assert.is_true(s.under)
      assert.same({ "cheapest " .. GC.Util.FormatMoney(500), "limit " .. GC.Util.FormatMoney(850),
        "AH " .. GC.Util.FormatMoney(1700) }, s.labels)
    end)

    it("names a vendor's price and knows a cheapest over the limit", function()
      local s = DC.Scale(1000, 12, 13, "vendor")
      assert.is_false(s.under)
      assert.equal("vendor " .. GC.Util.FormatMoney(13), s.labels[3])
      assert.near(1 / 1.1, s.cheap, 1e-9)
    end)

    for _, missing in ipairs({ { nil, 1, 2 }, { 1, nil, 2 }, { 1, 2, nil }, { 0, 1, 2 } }) do
      it("is omitted when a figure is missing", function()
        assert.is_nil(DC.Scale(missing[1], missing[2], missing[3]))
      end)
    end
  end)

  describe("Chips", function()
    it("counts what is listed and flags a market resale nobody measured", function()
      assert.same({ { text = "2,731 listed", tone = "muted" }, { text = "resale speed unknown", tone = "warn" } },
        DC.Chips({ avail = 2731, forever = "market" }))
    end)

    it("says nothing about speed for a vendor deal or one priced by what sold", function()
      assert.same({}, DC.Chips({ forever = "vendor" }))
      assert.same({}, DC.Chips({ forever = "market", refSource = "sold" }))
    end)
  end)

  describe("Hints", function()
    it("offers watch and open, and try-on for gear", function()
      local hints = DC.Hints({}, false, true)
      assert.same({ "watch it", "open details", "try it on" }, { hints[1].text, hints[2].text, hints[3].text })
      assert.equal("stop watching", DC.Hints({}, true)[1].text)
    end)

    it("offers no watch or open for a rare find", function()
      assert.same({}, DC.Hints({ kind = "rare" }, false, false))
    end)
  end)

  describe("Facts", function()
    local lines = {
      { kind = "money", label = "Cheapest", copper = 60 },
      { kind = "money", label = "AH value", copper = 72 },
      { kind = "live", left = "Cheapest", copper = 59, detail = "4 listed · just now" },
      { kind = "money", label = "GoldCap region price (ilvl 623)", copper = 900 },
      { kind = "text", left = "Source", right = "your scan, 3m ago" },
      { kind = "verdict", tone = "good", text = "Sell it on the AH" },
      { kind = "hint", text = "Companion keeps prices fresh: /goldcap companion" },
    }

    it("leaves out what the scale shows, and the Companion nudge", function()
      assert.same({
        { left = "GoldCap region price (ilvl 623)", copper = 900 },
        { left = "Source", right = "your scan, 3m ago" },
        { left = "Sell it on the AH", tone = "good" },
      }, DC.Facts(lines, true))
    end)

    it("keeps the prices when there is no scale", function()
      local facts = DC.Facts(lines, false)
      assert.equal(6, #facts)
      assert.same({ left = "Cheapest", copper = 59, right = "4 listed · just now" }, facts[3])
      assert.same({}, DC.Facts(nil, false))
    end)
  end)

  describe("Side", function()
    it("hangs below while there is room under the tooltip", function()
      assert.equal("below", DC.Side(300, 600, 120, 1000))
    end)
    it("goes above at the screen's foot", function()
      assert.equal("above", DC.Side(50, 400, 120, 1000))
    end)
    it("stays below when neither side has room", function()
      assert.equal("below", DC.Side(50, 950, 120, 1000))
      assert.equal("below", DC.Side(nil, nil, 120, 1000))
    end)
  end)

  describe("Ladder", function()
    local levels = {
      { unitPrice = 900, quantity = 40 }, { unitPrice = 800, quantity = 10 }, { unitPrice = 800, quantity = 10 },
      { unitPrice = 1200, quantity = 5 }, { unitPrice = 1000, quantity = 2 }, { unitPrice = 1500, quantity = 1 },
      { unitPrice = 2000, quantity = 99 },
    }

    it("keeps the five cheapest levels, merged and in order, with bars against the largest", function()
      local ladder = DC.Ladder(levels, 850)
      assert.equal(5, #ladder.rows)
      assert.same({ 800, 900, 1000, 1200, 1500 }, { ladder.rows[1].price, ladder.rows[2].price,
        ladder.rows[3].price, ladder.rows[4].price, ladder.rows[5].price })
      assert.equal(20, ladder.rows[1].qty)
      assert.equal(1, ladder.rows[2].share)
      assert.equal(0.5, ladder.rows[1].share)
    end)

    it("draws the limit after the last row under it", function()
      local ladder = DC.Ladder(levels, 950)
      assert.equal(2, ladder.limitAt)
      assert.is_true(ladder.rows[2].under)
      assert.is_false(ladder.rows[3].under)
      assert.equal("your limit " .. GC.Util.FormatMoney(950), ladder.label)
    end)

    it("says so when nothing is under the limit", function()
      local ladder = DC.Ladder(levels, 100)
      assert.equal(0, ladder.limitAt)
      assert.equal("your limit " .. GC.Util.FormatMoney(100) .. " · nothing under it", ladder.label)
    end)

    it("has no line without a limit and no ladder without a book", function()
      local ladder = DC.Ladder(levels, nil)
      assert.is_nil(ladder.limitAt)
      assert.is_nil(ladder.label)
      assert.is_false(ladder.rows[1].under)
      assert.is_nil(DC.Ladder(nil, 5))
      assert.is_nil(DC.Ladder({}, 5))
    end)
  end)

  describe("the panel's answer for every CheckVerdict tone", function()
    local tones = {
      { "refuse", "refuse", "WON'T BUY · CHECKED 19m AGO" },
      { "gold", "warn", "NEEDS GOLD · CHECKED 19m AGO" },
      { "clear", "buy", "SAFE · CHECKED LIVE 19m AGO" },
      { "vendor", "buy", "SAFE · CHECKED LIVE 19m AGO" },
      { "market", "buy", "SAFE · CHECKED LIVE 19m AGO" },
      { "adjust", "buy", "BUY LESS · CHECKED LIVE 19m AGO" },
      { "unverified", "buy", "YOUR CALL · CHECKED LIVE 19m AGO" },
      { "cap", "buy", "YOUR PRICE · CHECKED LIVE 19m AGO" },
    }
    for _, t in ipairs(tones) do
      it(t[1] .. " is a " .. t[2] .. " panel", function()
        local state = DC.State(t[1])
        assert.equal(t[2], state)
        assert.equal(t[3], DC.HeroLabel(t[1], 19 * 60))
        local footer = DC.Footer(state, "check", true)
        if state == "buy" then
          assert.same({ buy = true, qty = true, hide = true, cancel = false }, footer)
        else
          assert.same({ watch = true, check = true, hide = true, cancel = false, buy = false }, footer)
        end
      end)
    end

    it("names a followed group's cap and drops the age before a check", function()
      assert.equal("GROUP · CHECKED LIVE 4s AGO", DC.HeroLabel("cap", 4, "Herbs"))
      assert.equal("WON'T BUY", DC.HeroLabel("refuse", nil))
    end)

    it("keeps Cancel while a purchase is open on the server, whatever the verdict", function()
      for _, stage in ipairs({ "buying", "confirm", "requote" }) do
        assert.is_true(DC.Footer("buy", stage, true).cancel)
        local refused = DC.Footer("refuse", stage)
        assert.is_true(refused.cancel)
        assert.is_true(refused.buy)
        assert.is_false(refused.check)
      end
    end)

    it("offers no quantity for a single lot", function()
      assert.is_false(DC.Footer("buy", "ready", false).qty)
    end)
  end)

  describe("RefusedHero", function()
    it("says the gap once, and what makes it a deal", function()
      local hero = DC.RefusedHero(1520, 850, 1700, "market")
      assert.equal(GC.Util.FormatMoney(670) .. " too pricey", hero.big)
      assert.equal(("The cheapest costs %s. It's a deal only under %s, 50%% of the AH value of %s.")
        :format(GC.Util.FormatMoney(1520), GC.Util.FormatMoney(850), GC.Util.FormatMoney(1700)), hero.sentence)
    end)

    it("names the vendor's price for a vendor deal", function()
      assert.equal(("The cheapest costs %s. It's a deal only under %s; a vendor pays %s.")
        :format(GC.Util.FormatMoney(20), GC.Util.FormatMoney(12), GC.Util.FormatMoney(13)),
        DC.RefusedHero(20, 12, 13, "vendor").sentence)
    end)

    it("is nil when the cheapest is under the limit or a figure is missing", function()
      assert.is_nil(DC.RefusedHero(800, 850, 1700))
      assert.is_nil(DC.RefusedHero(nil, 850, 1700))
      assert.is_nil(DC.RefusedHero(900, nil, 1700))
    end)
  end)

  describe("Tiles", function()
    it("shows market, listed and sales for a refusal, unknown sales included", function()
      local tiles = DC.Tiles("refuse", { marketValue = 1700, listed = 412 })
      assert.same({ "MARKET", "LISTED", "SELLS PER DAY" }, { tiles[1].label, tiles[2].label, tiles[3].label })
      assert.equal("412", tiles[2].value)
      assert.equal("unknown", tiles[3].value)
    end)

    it("leaves a tile out when it has no figure", function()
      local tiles = DC.Tiles("refuse", {})
      assert.equal(1, #tiles)
      assert.equal("SELLS PER DAY", tiles[1].label)
    end)

    it("shows pay, the vendor's total and the return for a vendor buy", function()
      local tiles = DC.Tiles("buy", { entryTotal = 100, quantity = 10, refUnit = 13, profit = 30, forever = "vendor" })
      assert.same({ "YOU PAY", "VENDOR PAYS", "RETURN" }, { tiles[1].label, tiles[2].label, tiles[3].label })
      assert.equal(GC.Util.FormatMoney(130), tiles[2].value)
      assert.equal("+30%", tiles[3].value)
    end)

    it("shows the AH value for a market or retail buy", function()
      local tiles = DC.Tiles("buy", { entryTotal = 1000, marketValue = 250, profit = -50 })
      assert.equal("AH VALUE", tiles[2].label)
      assert.equal(GC.Util.FormatMoney(250), tiles[2].value)
      assert.equal("-5%", tiles[3].value)
    end)
  end)
end)
