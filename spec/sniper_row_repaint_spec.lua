local helper = require("spec.spec_helper")

-- setRowDeal ends by building a fresh Item object, a fresh ContinueOnItemLoad closure and a
-- Theme.QualityMarkup tooltip scan for every row, on every render -- and refreshRows (which
-- calls it) runs on every browse page while a full scan streams, on every watch-loop
-- observation, on every verdict stamp, and off the 0.25s ticker. With up to WIN.ROW_CAP rows
-- that is a lot of allocation for rows whose content never actually moved. These specs prove
-- the fix skips a genuinely identical re-render while still repainting whenever anything the
-- player can see -- item, price, qty, tier, profit, verdict, pinned state, placeholder state --
-- actually changed, and that the itemID name/icon cache does not stop a real repaint.
describe("Sniper row repaint skip", function()
  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end
  local function setUpvalue(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  -- A widget that counts every mutating call it receives, so a skip can be proven by the
  -- counter staying flat rather than by re-reading text that a bug could leave stale anyway.
  local function widget(calls)
    local w = {}
    function w:SetText(t) self.text = t; calls.n = calls.n + 1 end
    function w:SetTextColor(...) calls.n = calls.n + 1 end
    function w:SetTexture(t) self.texture = t; calls.n = calls.n + 1 end
    function w:SetLabel(label) self.label = label; calls.n = calls.n + 1 end
    function w:SetVariant(name) self.variant = name; calls.n = calls.n + 1 end
    function w:SetColorTexture(r, g, b) self.rgb = { r, g, b }; calls.n = calls.n + 1 end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    return w
  end

  local function fakeRow(calls)
    local row = {
      buy = widget(calls), tierChip = widget(calls), icon = widget(calls), nameText = widget(calls),
      discountText = widget(calls), unitText = widget(calls), priceText = widget(calls),
      profitText = widget(calls), trendText = widget(calls), highlight = widget(calls),
      rail = widget(calls), pinBg = widget(calls), shown = false,
    }
    function row:Show() self.shown = true end
    function row:Hide() self.shown = false end
    function row:IsShown() return self.shown end
    function row:SetAlpha(a) self.alpha = a end
    return row
  end

  local function deal(itemID, overrides)
    local d = {
      itemID = itemID, unitPrice = 1000, qty = 5, profit = 2000, discount = 0.4,
      tier = "GOOD", action = "Check",
    }
    for k, v in pairs(overrides or {}) do d[k] = v end
    return d
  end

  local function load()
    local itemLoads = 0
    local trendValue = nil
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function(_, itemID)
      itemLoads = itemLoads + 1
      return {
        ContinueOnItemLoad = function(_, cb) cb() end, -- resolves synchronously, like a cached lookup
        GetItemIcon = function() return "icon:" .. itemID end,
        GetItemQuality = function() return nil end,
        GetItemName = function() return "Item " .. itemID end,
      }
    end }

    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
          fg = { 0.92, 0.91, 0.89 }, gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return trendValue and { trend = trendValue } or nil end },
      db = { settings = { sniper = { watchPins = {} } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local setRowDeal = getUpvalue(refreshRows, "setRowDeal")
    local verdictFor = getUpvalue(setRowDeal, "verdictFor")
    local verdicts = getUpvalue(verdictFor, "verdicts")

    return {
      GC = GC,
      setRowDeal = setRowDeal,
      verdicts = verdicts,
      itemLoads = function() return itemLoads end,
      setTrend = function(v) trendValue = v end,
    }
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetCoinTextureString = nil, os.time, nil
    _G.ITEM_QUALITY_COLORS, _G.Item = nil, nil
  end)

  it("does not repaint an identical re-render, even from a different deal table", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7))
    local afterFirst = calls.n
    assert.is_true(afterFirst > 0)

    -- A brand-new table with the exact same values -- streaming/MergeDeals hands refreshRows a
    -- fresh table every pass, so the skip must be a value comparison, never `deal1 == deal2`.
    ctx.setRowDeal(row, deal(7))

    assert.equal(afterFirst, calls.n)
  end)

  it("repaints when the profit changes", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, { profit = 2000 }))
    local afterFirst = calls.n
    ctx.setRowDeal(row, deal(7, { profit = 9999 }))

    assert.is_true(calls.n > afterFirst)
    assert.equal("9999c", row.profitText.text)
  end)

  it("repaints when the unit price, quantity, or tier changes", function()
    local ctx = load()
    for _, field in ipairs({ "unitPrice", "qty", "tier" }) do
      local calls = { n = 0 }
      local row = fakeRow(calls)
      local base = deal(7)
      ctx.setRowDeal(row, base)
      local afterFirst = calls.n
      local changed = deal(7)
      changed[field] = field == "tier" and "HOT" or (changed[field] + 1)
      ctx.setRowDeal(row, changed)
      assert.is_true(calls.n > afterFirst, "expected a repaint when " .. field .. " changes")
    end
  end)

  it("repaints when a background Check's verdict changes, even though the deal itself did not", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    assert.equal("Check", row.buy.label) -- no verdict yet
    local afterFirst = calls.n

    -- stampVerdict's own shape: unitPrice-keyed, buyable, status, at.
    ctx.verdicts[7] = { unitPrice = d.unitPrice, at = 100, buyable = true, status = "SAFE" }
    ctx.setRowDeal(row, d) -- same deal object, same fields -- only the verdict moved

    assert.is_true(calls.n > afterFirst)
    assert.equal("Buy", row.buy.label)
  end)

  it("repaints when the item is pinned or unpinned, even though the deal itself did not change", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    local afterFirst = calls.n
    assert.is_nil(row.rail.rgb and row.rail.rgb[1] == ctx.GC.Theme.color.watch[1] or nil)

    ctx.GC.db.settings.sniper.watchPins = { 7 }
    ctx.setRowDeal(row, d)

    assert.is_true(calls.n > afterFirst)
    assert.same(ctx.GC.Theme.color.watch, row.rail.rgb)
  end)

  it("repaints when it becomes (or stops being) a pin placeholder", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local live = deal(7)
    ctx.setRowDeal(row, live)
    local afterFirst = calls.n

    local placeholder = deal(7, { pinPlaceholder = true })
    ctx.setRowDeal(row, placeholder)

    assert.is_true(calls.n > afterFirst)
    assert.equal("Watching", row.buy.label)
  end)

  it("repaints when the trend read against the SAME deal object changes", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    assert.equal("—", row.trendText.text)
    local afterFirst = calls.n

    ctx.setTrend(-12)
    ctx.setRowDeal(row, d) -- same deal object -- only GC.Data.GetItemValue's answer moved

    assert.is_true(calls.n > afterFirst)
    assert.equal("▼12%", row.trendText.text)
  end)

  it("still shows a row that goes hidden and comes back with the exact same deal", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    assert.is_true(row:IsShown())

    row:Hide() -- refreshRows does this to a pooled slot that has no deal this pass
    ctx.setRowDeal(row, deal(7)) -- reassigned later, content-identical to before

    assert.is_true(row:IsShown(), "a reused row must never stay hidden just because its content repeats")
  end)

  -- Fix 3: a pin placeholder (renderList's fabricated row for a pin that fell out of the deals
  -- list) is not a deal -- its discount/profit/qty fields are sentinel zeros kept only so
  -- callers that expect a number get one. Rendering those sentinels used to print "0%", a
  -- 0-copper profit coin, and (when a price WAS observed) the same unit price twice as a fake
  -- "unit/total" pair, since qty is always 1. Every one of those cells must say nothing instead.
  it("renders a priceUnknown pin placeholder's discount, profit and price as dashes, not zeros", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, {
      pinPlaceholder = true, unitPrice = 0, qty = 1, profit = 0, discount = 0,
      tier = "WATCH", action = "Check", priceUnknown = true,
    }))

    assert.equal("—", row.discountText.text)
    assert.equal("—", row.profitText.text)
    assert.equal("—", row.unitText.text)
    assert.equal("—", row.priceText.text)
    assert.equal("Watching", row.buy.label)
  end)

  it("shows a pin placeholder's last-seen unit price without duplicating it as a fake total", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, {
      pinPlaceholder = true, unitPrice = 500, qty = 1, profit = 0, discount = 0,
      tier = "WATCH", action = "Check", priceUnknown = false,
    }))

    assert.equal("—", row.discountText.text)
    assert.equal("—", row.profitText.text)
    assert.equal("500c", row.unitText.text)   -- the one real number: what it costs right now
    assert.equal("—", row.priceText.text)     -- never unitPrice * qty duplicated as a fake total
  end)

  it("resolves an itemID's name/icon once and reuses it across a genuine repaint", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, { profit = 100 }))
    assert.equal(1, ctx.itemLoads())

    ctx.setRowDeal(row, deal(7, { profit = 200 })) -- genuine change -> repaints, but same itemID
    assert.equal(1, ctx.itemLoads())
  end)
end)
