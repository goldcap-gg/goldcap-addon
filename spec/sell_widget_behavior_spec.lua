local helper = require("spec.spec_helper")

describe("Sell widget geometry and manual cost", function()
  local made

  local function region(kind, parent)
    local value = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = value end
    function value:SetPoint(point, relative, relativePoint, x, y)
      if type(relative) == "table" and not relative.__frame then error("SetPoint relative must be a Region") end
      self.points[#self.points + 1] = { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
    end
    function value:ClearAllPoints() self.points = {} end
    function value:SetSize(w, h) self.width, self.height = w, h end
    function value:SetWidth(w) self.width = w end
    function value:SetHeight(h) self.height = h end
    function value:SetText(text) self.text = text end
    function value:GetText() return self.text or "" end
    function value:SetLabel(text) self.label = text end
    function value:SetScript(name, fn) self.scripts[name] = fn end
    function value:HookScript(name, fn) self.scripts[name] = fn end
    function value:Show() self.shown = true end
    function value:Hide() self.shown = false end
    function value:IsShown() return self.shown end
    function value:Enable() self.enabled = true end
    function value:Disable() self.enabled = false end
    function value:SetJustifyH() end
    function value:SetWordWrap() end
    function value:SetTextColor() end
    function value:SetAutoFocus() end
    function value:SetScrollChild(child) self.scrollChild = child end
    return value
  end

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function load(width, record)
    made = {}
    _G.CreateFrame = function(kind, _, parent)
      local value = region(kind, parent)
      made[#made + 1] = value
      return value
    end
    _G.time = function() return 77 end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    local theme = {
      color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, red = { 1, 0, 0 }, green = { 0, 1, 0 } },
      Label = function(parent) return region("FontString", parent) end,
      Num = function(parent) return region("FontString", parent) end,
      Button = function(parent) return region("Button", parent) end,
    }
    local GC = {
      Sell = {}, Theme = theme,
      QuoteCache = { Clear = function() end },
      SellViewModel = {
        Filter = function(values) return values end,
        SourceText = function() return "GC ×1" end,
        CostText = function() return "Set cost" end,
        ProfitText = function() return "Unknown" end,
        SummaryText = function(summary) return { knownCost = summary.knownCost, listedValue = summary.listedValue, profit = "Unknown" } end,
        Expansion = function() return { batches = {}, ownedLots = {}, note = "FIFO allocations" } end,
      },
      SellPositions = { Summary = function() return { invested = nil, projected = nil, profit = nil } end },
      Acquisitions = { RecordManual = function(args) record.calls[#record.calls + 1] = args; return {} end },
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
    }
    helper.loadModule("UI/SellFrame.lua", GC)
    local root = region("Frame")
    root.HookScript = function(_, name, fn) root.scripts[name] = fn end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8, rowWidth = width, rowHeight = 24 })
    return GC
  end

  local function topRows(GC, values)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "positions", values)
    render()
    return upvalue(render, "rows"), upvalue(render, "container")
  end

  after_each(function()
    _G.CreateFrame, _G.time, _G.GetCoinTextureString = nil, os.time, nil
    _G.C_AuctionHouse, _G.ItemLocation, _G.C_Container, _G.C_Item = nil, nil, nil, nil
  end)

  it("anchors header cells through real Regions and only shows MARKET wide", function()
    local record = { calls = {} }
    local narrow = load(500, record)
    local _, narrowContainer = topRows(narrow, {})
    local narrowHeader
    for _, child in ipairs(narrowContainer.children) do if child.cells then narrowHeader = child break end end
    assert.is_false(narrowHeader.cells.market.shown)
    local GC = load(620, record)
    local _, container = topRows(GC, {})
    local header
    for _, child in ipairs(container.children) do if child.cells then header = child break end end
    assert.is_nil(header.cells.queue)
    assert.is_false(header.cells.market.shown)
    assert.equal(header.cells.expand, header.cells.status.points[1].relative)
    assert.equal(header.cells.status, header.cells.profit.points[1].relative)
    assert.equal(header.cells.profit, header.cells.listed.points[1].relative)
    assert.equal(header.cells.listed, header.cells.cost.points[1].relative)
    assert.equal(header.cells.cost, header.cells.item.points[2].relative)
    assert.is_nil(header.cells.action)
    local wide = load(760, record)
    local _, wideContainer = topRows(wide, {})
    for _, child in ipairs(wideContainer.children) do if child.cells then header = child break end end
    assert.is_true(header.cells.market.shown)
  end)

  it("uses the header's ordered cell chain for real rows and sizes expansion scroll content", function()
    local function assertRow(width, market)
      local GC = load(width, { calls = {} })
      GC.SellViewModel.Expansion = function()
        return { note = "FIFO allocations", batches = { { source = "goldcap", remainingQty = 1 } },
          ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 10 } } }
      end
      local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 5, listedValue = 10, sources = {}, status = "LISTED" }
      local rows, container = topRows(GC, { p })
      local header
      for _, child in ipairs(container.children) do if child.cells then header = child break end end
      local row = rows[1]
      assert.equal(market, row.cells.market.shown)
      assert.is_nil(row.cells.queue)
      assert.is_nil(row.cells.action)
      assert.equal(row.cells.expand, row.cells.status.points[1].relative)
      assert.equal(row.cells.status, row.cells.profit.points[1].relative)
      if market then
        assert.equal(row.cells.profit, row.cells.market.points[1].relative)
        assert.equal(row.cells.market, row.cells.listed.points[1].relative)
      else
        assert.equal(row.cells.profit, row.cells.listed.points[1].relative)
      end
      assert.equal(row.cells.listed, row.cells.cost.points[1].relative)
      assert.equal(row.cells.cost, row.cells.item.points[2].relative)
      assert.equal(header.cells.expand, header.cells.status.points[1].relative)
      rows[1].scripts.OnClick(rows[1])
      local render = upvalue(GC.Sell.Attach, "renderRows")
      local content = upvalue(render, "content")
      assert.equal(width, content.width)
      assert.equal(4 * 24, content.height)
      assert.equal("detail", rows[2].kind)
      assert.equal("batch", rows[3].kind)
      assert.equal("lot", rows[4].kind)
    end
    assertRow(500, false)
    assertRow(620, false)
    assertRow(760, true)
  end)

  it("opens Set cost for listed partial and unknown orphan positions", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        coverage = "PARTIAL", exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 20, sources = {} },
      { itemID = 7, itemName = "Odd", positionKey = "item:7:1:0:0", scopeKey = "eu\1A-R\1item:7:1:0:0",
        coverage = "UNKNOWN", exposureQty = 1, knownQty = 0, knownCost = 0, listedValue = 10, sources = {} },
    })
    assert.equal("Set cost", rows[1].action.label)
    rows[1].action.scripts.OnClick()
    assert.is_true(container.costDialog.shown)
    assert.equal(2, container.costDialog.maximum)
    assert.equal("Set cost", rows[2].action.label)
  end)

  it("edits exact manual cost and mutates once only from Confirm", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local refreshes = 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        coverage = "PARTIAL", exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 20, sources = {} },
    })
    rows[1].action.scripts.OnClick()
    local dialog, confirm = container.costDialog
    for _, child in ipairs(dialog.children) do if child.label == "Confirm" then confirm = child end end
    local labels = {}
    for _, child in ipairs(dialog.children) do if child.text then labels[child.text] = true end end
    assert.is_true(labels.Quantity); assert.is_true(labels["Unit cost"]); assert.is_true(labels["Total cost"])
    dialog.quantity:SetText("1.5")
    confirm.scripts.OnClick()
    assert.equal("Enter a whole quantity", dialog.error.text)
    assert.equal(0, #record.calls)
    dialog.quantity:SetText("3")
    confirm.scripts.OnClick()
    assert.equal("Quantity exceeds missing units", dialog.error.text)
    assert.equal(0, #record.calls)
    dialog.quantity:SetText("10"); dialog.quantity.scripts.OnTextChanged()
    assert.equal("2", dialog.quantity:GetText())
    dialog.total:SetText("5"); dialog.total.scripts.OnTextChanged()
    assert.equal("5", dialog.total:GetText()); assert.equal("2", dialog.unit:GetText())
    dialog.unit:SetText("9007199254740991"); dialog.unit.scripts.OnTextChanged()
    assert.equal("Enter an exact positive cost", dialog.error.text)
    assert.equal(0, #record.calls)
    dialog.unit:SetText("3"); dialog.unit.scripts.OnTextChanged()
    confirm.scripts.OnClick(); confirm.scripts.OnClick()
    assert.equal(1, #record.calls)
    assert.same({ itemID = 42, positionKey = "commodity:42", itemName = "Ore", quantity = 2, total = 6,
      acquiredAt = 77, character = "A-R", region = "eu" }, record.calls[1])
    assert.equal(1, refreshes)
  end)

  it("invalidates a formerly valid manual total before Confirm", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        coverage = "PARTIAL", exposureQty = 2, knownQty = 0, sources = {} },
    })
    rows[1].action.scripts.OnClick()
    local dialog, confirm = container.costDialog
    for _, child in ipairs(dialog.children) do if child.label == "Confirm" then confirm = child end end
    dialog.quantity:SetText("2"); dialog.quantity.scripts.OnTextChanged()
    dialog.unit:SetText("3"); dialog.unit.scripts.OnTextChanged()
    assert.equal("6", dialog.total:GetText())
    dialog.unit:SetText("1.5"); dialog.unit.scripts.OnTextChanged()
    assert.equal("", dialog.total:GetText())
    assert.equal("Enter an exact positive cost", dialog.error.text)
    confirm.scripts.OnClick()
    assert.equal(0, #record.calls)
  end)

  it("[C2] recomputes a unit-derived manual total when quantity changes", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local refreshes = 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
        scopeKey = "eu\1A-R\1commodity:42", exposureQty = 2, knownQty = 0, sources = {} },
    })
    rows[1].action.scripts.OnClick()
    local dialog, confirm = container.costDialog
    for _, child in ipairs(dialog.children) do if child.label == "Confirm" then confirm = child end end

    dialog.quantity:SetText("2"); dialog.quantity.scripts.OnTextChanged()
    dialog.unit:SetText("3"); dialog.unit.scripts.OnTextChanged()
    assert.equal("6", dialog.total:GetText())
    dialog.quantity:SetText("1"); dialog.quantity.scripts.OnTextChanged()
    assert.equal("3", dialog.total:GetText())

    dialog.quantity:SetText("9"); dialog.quantity.scripts.OnTextChanged()
    assert.equal("2", dialog.quantity:GetText())
    assert.equal("6", dialog.total:GetText())

    dialog.total:SetText("5"); dialog.total.scripts.OnTextChanged()
    assert.equal("2", dialog.unit:GetText())
    dialog.quantity:SetText("1"); dialog.quantity.scripts.OnTextChanged()
    assert.equal("5", dialog.total:GetText())
    assert.equal("5", dialog.unit:GetText())

    confirm.scripts.OnClick(); confirm.scripts.OnClick()
    assert.same({ itemID = 42, positionKey = "commodity:42", itemName = "Ore", quantity = 1, total = 5,
      acquiredAt = 77, character = "A-R", region = "eu" }, record.calls[1])
    assert.equal(1, #record.calls)
    assert.equal(1, refreshes)
  end)

  it("[C2] rejects manual confirmation after its acquisition scope changes", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
        scopeKey = "eu\1A-R\1commodity:42", coverage = "UNKNOWN",
        exposureQty = 1, knownQty = 0, sources = {} },
    })
    rows[1].action.scripts.OnClick()
    local dialog, confirm = container.costDialog
    for _, child in ipairs(dialog.children) do if child.label == "Confirm" then confirm = child end end
    dialog.total:SetText("5"); dialog.total.scripts.OnTextChanged()
    GC.Ledger.Context = function() return { char = "B-R", region = "us" } end
    confirm.scripts.OnClick()
    assert.equal(0, #record.calls)
    assert.is_true(dialog.shown)
  end)

  it("completes Set cost from a zero-tracked unknown position", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local refreshed = 0
    GC.Sell.Refresh = function() refreshed = refreshed + 1 end
    local rows, container = topRows(GC, {
      { itemID = 7, itemName = "Odd", positionKey = "item:7:1:0:0",
        scopeKey = "eu\1A-R\1item:7:1:0:0", coverage = "UNKNOWN",
        exposureQty = 1, knownQty = 0, trackedQty = 0, listedQty = 1, sources = {} },
    })
    rows[1].action.scripts.OnClick()
    local dialog, confirm = container.costDialog
    for _, child in ipairs(dialog.children) do if child.label == "Confirm" then confirm = child end end
    dialog.total:SetText("9"); dialog.total.scripts.OnTextChanged()
    confirm.scripts.OnClick()
    assert.same({ itemID = 7, positionKey = "item:7:1:0:0", itemName = "Odd", quantity = 1, total = 9,
      acquiredAt = 77, character = "A-R", region = "eu" }, record.calls[1])
    assert.equal(1, refreshed)
  end)

  it("disarms a posting row when a rerender cannot prove the pinned position identity", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local quote = { unit = 200, at = 77 }
    GC.QuoteCache.Fresh = function() return quote end
    GC.SellPositions.BuildPostPlan = function() return { positionKey = "commodity:42",
      scopeKey = "eu\1A-R\1commodity:42", itemID = 42, quantity = 1, unitPrice = 200 } end
    _G.C_AuctionHouse = { PostCommodity = function() return false end }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
      scopeKey = "eu\1A-R\1commodity:42", coverage = "COMPLETE", exposureQty = 1,
      knownQty = 1, knownCost = 100, listedValue = 200, sources = {}, status = "LISTED" }
    local rows = topRows(GC, { p })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local post = upvalue(render, "onPostClick")
    set(post, "liveBagState", function() return { bag = 0, slot = 1, stackQty = 1, exactQty = 1, itemID = 42, positionKey = "commodity:42" } end)
    set(post, "driver", { keyInfo = function() return { isCommodity = true } end })
    post(rows[1])
    assert.equal("posting", rows[1].postStage)
    set(render, "positions", { { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
      scopeKey = "eu\1A-R\1commodity:42", coverage = "COMPLETE", exposureQty = 1,
      knownQty = 1, knownCost = 100, listedValue = 200, sources = {}, status = "LISTED" } })
    render()
    assert.is_nil(rows[1].postStage)
    assert.equal("Post", rows[1].action.label)
    assert.is_true(rows[1].action.enabled)
  end)

  it("renders expansion facts and filters the top-level summary once", function()
    local record = { calls = {} }
    local GC = load(620, record)
    GC.SellViewModel.Filter = function(values, mode)
      if mode == "goldcap" then return { values[1] } end
      return values
    end
    GC.SellViewModel.SummaryText = function(summary) return summary end
    GC.SellViewModel.Expansion = function()
      return {
        note = "FIFO allocations", quoteAge = 7, ahead = 3, sold = 4, days = 1.25,
        recommendation = { action = "repost", rec = { unit = 149, breakeven = 106 } },
        batches = { { source = "goldcap", acquiredAt = 4, originalQty = 5, remainingQty = 2,
          allocatedQty = 2, unitCost = 50, totalCost = 100, evidence = "Auction 9" } },
        ownedLots = { { auctionID = 9, quantity = 2, unitPrice = 200 } },
      }
    end
    GC.SellPositions.Summary = function(values)
      if #values == 1 then return { invested = 100, projected = 95, profit = -5 } end
      return { invested = 130, projected = 150, profit = 20 }
    end
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 2,
        knownQty = 2, knownCost = 100, listedValue = 400, sources = { goldcap = 2 }, status = "LISTED" },
      { itemID = 7, itemName = "Other", positionKey = "commodity:7", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 30, listedValue = 50, sources = { auction_house = 1 }, status = "LISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    local render = upvalue(GC.Sell.Attach, "renderRows")
    rows = upvalue(render, "rows")
    assert.equal("detail", rows[2].kind)
    assert.match("quote 7s · ahead 3 · sold/day 4 · ETA ~1d", rows[2].cells.item.text)
    assert.equal("Repost @ 149 · breakeven 106", rows[2].cells.status.text)
    assert.match("goldcap · at 4 · 5 original / 2 left / 2 FIFO", rows[3].cells.item.text)
    assert.equal("100", rows[3].cells.cost.text)
    assert.equal("400", rows[4].cells.listed.text)
    for _, child in ipairs(container.children) do
      if child.label == "GC" then child.scripts.OnClick() end
    end
    assert.equal("100", container.summary.cost.text)
    assert.equal("400", container.summary.listed.text)
    assert.equal("-5", container.summary.profit.text)
    assert.equal("position", rows[1].kind)
    assert.equal("detail", rows[2].kind)
  end)

  it("renders a direct RecommendPost decision with its exact unit and mode", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {},
        recommendation = { unit = 199, mode = "undercut", belowCost = false } }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 100, listedValue = 200, sources = {}, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("Post (undercut) @ 199", rows[2].cells.status.text)
  end)

  it("[I2] renders semantic evidence, owned unit and total, and breakeven", function()
    local GC = load(620, { calls = {} })
    helper.loadModule("UI/SellViewModel.lua", GC)
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 2, trackedQty = 2, listedQty = 2, knownQty = 2, knownCost = 100,
        listedValue = 400, sources = { goldcap = 1, auction_house = 1 }, status = "LISTED",
        recommendation = { unit = 199, mode = "undercut", breakeven = 106 },
        batches = {
          { id = "a", source = "goldcap", originalQty = 1, remainingQty = 1, remainingTotal = 50,
            sniperEvidenceKey = "capture:1" },
          { id = "b", source = "auction_house", originalQty = 1, remainingQty = 1, remainingTotal = 50,
            mailEvidenceKey = "mail:2" },
          { id = "c", source = "manual", originalQty = 1, remainingQty = 1, remainingTotal = 50 },
          { id = "d", source = "auction_house", originalQty = 1, remainingQty = 1, remainingTotal = 50 },
        },
        allocations = { { batchID = "a", quantity = 1 }, { batchID = "b", quantity = 1 } },
        ownedLots = { { auctionID = 9, quantity = 2, unitPrice = 200 } },
      },
    })
    rows[1].scripts.OnClick(rows[1])
    assert.match("captured", rows[3].cells.item.text)
    assert.match("mail%-confirmed", rows[4].cells.item.text)
    assert.match("manual", rows[5].cells.item.text)
    assert.match("unknown evidence", rows[6].cells.item.text)
    assert.equal("Post (undercut) @ 199 · breakeven 106", rows[2].cells.status.text)
    assert.match("unit 200", rows[7].cells.item.text)
    assert.equal("400", rows[7].cells.listed.text)
  end)

  it("[I2] renders no recommendation when none is available", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {}, recommendation = nil }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0,
        sources = {}, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("", rows[2].cells.status.text)
  end)
end)
