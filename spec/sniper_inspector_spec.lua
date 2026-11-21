local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/SniperInspector.lua: the check panel's hero, cheapest listings, tiles and footer, for a
-- refusal and for a buy, and the footer following the purchase stage. The panel's own widgets
-- (the verdict slots, the status line, BUY and Cancel, the quantity box) are built here the way
-- createDialog builds them; the inspector is handed them and nothing else.
describe("check panel inspector", function()
  local GC, SI, restore, savedTime, now, acted

  before_each(function()
    restore = W.install()
    GC = helper.loadModule("Core/Util.lua")
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    savedTime = _G.GetTime
    now = 5000
    _G.GetTime = function() return now end
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealCard.lua", GC)
    helper.loadModule("UI/SniperInspector.lua", GC)
    SI = GC.SniperInspector
    acted = {}
  end)

  after_each(function()
    _G.GetTime, _G.GetCoinTextureString = savedTime, nil
    restore()
  end)

  local function panel()
    local T = GC.Theme
    local d = CreateFrame("Frame")
    d:SetWidth(320)
    d.verdictLabel = T.Num(d, 9, true)
    d.verdictAmount = T.Num(d, 22, true)
    d.verdictAmountNote = T.Label(d, 10)
    d.heroText = T.Label(d, 16)
    d.verdictHead = T.Label(d, 12)
    d.status = T.Num(d, 10)
    d.primaryBtn = T.Button(d, "primary", "plaque")
    d.cancelBtn = T.Button(d, "ghost", "badge")
    d.qtyBox = CreateFrame("Frame", nil, CreateFrame("Frame", nil, d))
    d.banner = CreateFrame("Frame", nil, d)
    SI.Build(d, {
      watch = function() acted[#acted + 1] = "watch" end,
      hide = function() acted[#acted + 1] = "hide" end,
      step = function(n) acted[#acted + 1] = "step " .. n end,
      all = function() acted[#acted + 1] = "all" end,
    })
    return d
  end

  local LEVELS = {
    { unitPrice = 1520, quantity = 30 }, { unitPrice = 1600, quantity = 300 }, { unitPrice = 1750, quantity = 82 },
  }

  local function refusal(d, extra)
    local ctx = {
      cv = { tone = "refuse", reason = "profit_below_minimum" },
      decision = { reasons = { "profit_below_minimum" }, ceiling = 850, refUnit = 1700, entryUnitDisplay = 1520 },
      deal = { itemID = 7, forever = "market", isCommodity = true, avail = 412, refUnit = 1700 },
      market = {}, levels = LEVELS, checkedAt = function() return now - 19 * 60 end,
      figure = "-12c", sentence = GC.SniperDecision.ReasonText("profit_below_minimum"),
      caption = "",
    }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    SI.Paint(d, ctx)
    return ctx
  end

  local function buy(d, extra)
    local ctx = {
      cv = { tone = "vendor" },
      decision = { reasons = {}, ceiling = 12, refUnit = 13, entryTotal = 100, quantity = 10, stressProfit = 30 },
      deal = { itemID = 8, forever = "vendor", isCommodity = true, avail = 40 },
      market = {}, levels = { { unitPrice = 10, quantity = 10 }, { unitPrice = 15, quantity = 4 } },
      checkedAt = function() return 5000 - 4 end, figure = "+30c", figureColor = GC.Kit.Tokens.color.profit,
      caption = "sure profit: a vendor pays 13c each", sentence = "Checked against the live auction house a moment ago.",
      maxQty = function() return 10 end,
    }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    SI.Paint(d, ctx)
    return ctx
  end

  describe("a refusal", function()
    it("says the answer, the gap and the reason once", function()
      local d = panel()
      d.status:SetText(GC.SniperDecision.ReasonText("profit_below_minimum"))
      refusal(d)
      assert.equal("WON'T BUY · CHECKED 19m AGO", d.verdictLabel:GetText())
      assert.equal(GC.Util.FormatMoney(670) .. " too pricey", d.verdictAmount:GetText())
      assert.equal(GC.DealCard.RefusedHero(1520, 850, 1700, "market").sentence, d.verdictHead:GetText())
      assert.is_false(d.verdictAmountNote:IsShown())
      assert.is_false(d.heroText:IsShown())
      -- The status line under it does not say it again.
      assert.equal("", d.status:GetText())
      assert.is_true(d.quietReasons[GC.SniperDecision.ReasonText("profit_below_minimum")])
      assert.equal("COMMODITY · 412 LISTED", d.kindText:GetText())
    end)

    it("draws the cheapest listings with the limit line over the first, none under it", function()
      local d = panel()
      refusal(d)
      local rows = d.ladderBlock.rows
      assert.equal(GC.Util.FormatMoney(1520), rows[1].price:GetText())
      assert.equal("×300", rows[2].qty:GetText())
      assert.is_true(rows[3].price:IsShown())
      assert.is_false(rows[4].price:IsShown())
      assert.equal("your limit " .. GC.Util.FormatMoney(850) .. " · nothing under it", d.ladderBlock.lineLabel:GetText())
      assert.is_true(d.ladderBlock.lineLabel:IsShown())
      assert.is_true(d.inspect.ladderH > 0)
    end)

    it("shows market, listed and sales per day, unknown when unmeasured", function()
      local d = panel()
      refusal(d)
      local tiles = d.tilesBlock.tiles
      assert.same({ "MARKET", "LISTED", "SELLS PER DAY" },
        { tiles[1].label:GetText(), tiles[2].label:GetText(), tiles[3].label:GetText() })
      assert.equal(GC.Util.FormatMoney(1700), tiles[1].value:GetText())
      assert.equal("412", tiles[2].value:GetText())
      assert.equal("unknown", tiles[3].value:GetText())
    end)

    it("offers WATCH under the limit, CHECK and HIDE ITEM, and no quantity or Cancel", function()
      local d = panel()
      refusal(d)
      assert.is_true(d.watchBtn:IsShown())
      assert.equal("WATCH FOR UNDER " .. GC.Util.FormatMoney(850), d.watchBtn.label)
      assert.is_true(d.primaryBtn:IsShown()) -- the panel's own button, as CHECK
      assert.is_true(d.hideBtn:IsShown())
      assert.equal("HIDE ITEM", d.hideBtn.label)
      assert.is_false(d.cancelBtn:IsShown())
      assert.is_false(d.qtyMinus:IsShown())
      W.state(d.watchBtn).scripts.OnClick(d.watchBtn)
      W.state(d.hideBtn).scripts.OnClick(d.hideBtn)
      assert.same({ "watch", "hide" }, acted)
    end)

    it("says STOP WATCHING for a watched item and SHOW THIS ITEM AGAIN for a hidden one", function()
      local d = panel()
      refusal(d, { isPinned = function() return true end, isHidden = function() return true end })
      assert.equal("STOP WATCHING", d.watchBtn.label)
      assert.equal("SHOW THIS ITEM AGAIN", d.hideBtn.label)
    end)

    it("keeps Cancel and the purchase's own button while a purchase is open on the server", function()
      local d = panel()
      d.row = { purchaseStage = "confirm" }
      refusal(d)
      assert.is_true(d.cancelBtn:IsShown())
      assert.is_true(d.primaryBtn:IsShown())
      assert.is_false(d.watchBtn:IsShown())
    end)

    it("says Checking... while the live check is on its way, and no age before any check", function()
      local d = panel()
      refusal(d, { checkedAt = function() return nil end })
      assert.equal("WON'T BUY", d.verdictLabel:GetText())
      SI.Pending(d)
      assert.equal("Checking...", d.verdictLabel:GetText())
      assert.is_false(d.verdictAmount:IsShown())
      refusal(d) -- the answer
      assert.equal("WON'T BUY · CHECKED 19m AGO", d.verdictLabel:GetText())
    end)

    it("keeps the panel's own button in one place whatever the verdict", function()
      local d = panel()
      refusal(d)
      local refusedAt = { W.state(d.primaryBtn).points[1][5], d.primaryBtn:GetWidth() }
      local watchAt = W.state(d.watchBtn).points[1][5]
      buy(d)
      assert.same(refusedAt, { W.state(d.primaryBtn).points[1][5], d.primaryBtn:GetWidth() })
      assert.is_true(watchAt > refusedAt[1]) -- WATCH sits above it, where the stepper goes on a buy
    end)

    it("keeps the reason as the sentence when there is no limit to measure by", function()
      local d = panel()
      refusal(d, { decision = { reasons = { "source_stale" } }, deal = { itemID = 9, isCommodity = true },
        levels = false, sentence = GC.SniperDecision.ReasonText("source_stale"), figure = false })
      assert.equal(GC.SniperDecision.ReasonText("source_stale"), d.verdictHead:GetText())
      assert.is_false(d.verdictAmount:IsShown())
      assert.is_nil(d.inspect.ladderH) -- no book: no ladder
      assert.equal("WATCH THIS ITEM", d.watchBtn.label)
    end)
  end)

  describe("a buy", function()
    it("says SAFE with the check's age, the profit, and what it is measured against", function()
      local d = panel()
      buy(d)
      assert.equal("SAFE · CHECKED LIVE 4s AGO", d.verdictLabel:GetText())
      assert.equal("+30c", d.verdictAmount:GetText())
      assert.equal("sure profit: a vendor pays 13c each", d.verdictHead:GetText())
      assert.is_nil(d.quietReasons)
    end)

    it("shows what you pay, what the vendor pays and the return", function()
      local d = panel()
      buy(d)
      local tiles = d.tilesBlock.tiles
      assert.same({ "YOU PAY", "VENDOR PAYS", "RETURN" },
        { tiles[1].label:GetText(), tiles[2].label:GetText(), tiles[3].label:GetText() })
      assert.equal("+30%", tiles[3].value:GetText())
    end)

    it("draws the levels under the limit and the line after them", function()
      local d = panel()
      buy(d)
      assert.equal("your limit " .. GC.Util.FormatMoney(12), d.ladderBlock.lineLabel:GetText())
      assert.is_false(d.ladderBlock.rows[3].price:IsShown())
    end)

    it("offers the quantity stepper, BUY and HIDE THIS ITEM", function()
      local d = panel()
      d.row = { purchaseStage = "ready" }
      buy(d)
      assert.is_true(d.primaryBtn:IsShown())
      assert.is_false(d.watchBtn:IsShown())
      assert.is_true(d.qtyMinus:IsShown())
      assert.is_true(d.qtyBox:IsShown())
      assert.equal(d, d.qtyBox:GetParent()) -- moved into the footer
      assert.equal("ALL 10", d.qtyAll.label)
      assert.equal("HIDE THIS ITEM", d.hideBtn.label)
      assert.is_false(d.cancelBtn:IsShown())
      W.state(d.qtyPlus).scripts.OnClick(d.qtyPlus)
      W.state(d.qtyAll).scripts.OnClick(d.qtyAll)
      assert.same({ "step 1", "all" }, acted)

      d.row.purchaseStage = "buying" -- the click went out: Cancel comes back at once
      SI.Refresh(d)
      assert.is_true(d.cancelBtn:IsShown())
    end)

    it("offers no stepper for a single realm lot", function()
      local d = panel()
      buy(d, { deal = { itemID = 8, isCommodity = false }, levels = false }) -- a realm lot has no book
      assert.is_false(d.qtyMinus:IsShown())
      assert.equal("ITEM", d.kindText:GetText())
    end)

    it("keeps counting the check's age", function()
      local d = panel()
      buy(d)
      now = now + 120
      SI.Refresh(d)
      assert.equal("SAFE · CHECKED LIVE 2m AGO", d.verdictLabel:GetText())
    end)
  end)
end)
