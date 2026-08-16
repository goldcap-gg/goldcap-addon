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
    function value:SetWordWrap(enabled) self.wordWrap = enabled end
    function value:SetTextColor(...) self.color = { ... } end
    function value:SetAutoFocus() end
    function value:SetScrollChild(child) self.scrollChild = child end
    -- Rows own textures now (zebra banding, hover highlight, the bottom rule, the child spine
    -- and the item icon), so the double has to hand back regions for them like the real API.
    function value:CreateTexture(_, layer) local t = region("Texture", self); t.layer = layer; return t end
    function value:SetAllPoints(relative) self.allPoints = relative or self.parent end
    function value:SetColorTexture(...) self.colorTexture = { ... } end
    function value:SetTexture(path) self.texture = path end
    function value:SetTexCoord(...) self.texCoord = { ... } end
    function value:SetFrameStrata(strata) self.strata = strata end
    function value:SetFrameLevel(level) self.level = level end
    function value:GetFrameLevel() return self.level or 0 end
    function value:EnableMouse(enabled) self.mouseEnabled = enabled end
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
    record.calls, record.repairs = record.calls or {}, record.repairs or {}
    _G.CreateFrame = function(kind, _, parent)
      local value = region(kind, parent)
      made[#made + 1] = value
      return value
    end
    _G.time = function() return 77 end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    local theme = {
      color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
        zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
        gold = { 0.83, 0.64, 0.22 }, panel = { 0.078, 0.086, 0.110 } },
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
      Acquisitions = {
        RecordManual = function(args) record.calls[#record.calls + 1] = args; return {} end,
        RepairPendingManual = function(args) record.repairs[#record.repairs + 1] = args; return {} end,
      },
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

  -- MARKET is now unconditional and LISTED is the column that drops on a narrow window: the
  -- market price drives every decision on this screen, while the listed total is already
  -- reported in the summary above the list.
  -- The name column has a floor, and the layout sheds columns to keep it: the listed total
  -- first (the summary already reports it), then the advice text (the action button repeats it
  -- on hover). MARKET, PROFIT and the action survive every width, because they are what a
  -- decision on this screen is made from.
  it("sheds columns from the least load-bearing end to keep the item name readable", function()
    local record = { calls = {} }
    local narrow = load(620, record)
    local _, narrowContainer = topRows(narrow, {})
    local narrowHeader
    for _, child in ipairs(narrowContainer.children) do if child.cells then narrowHeader = child break end end
    assert.is_false(narrowHeader.cells.listed.shown)
    assert.is_false(narrowHeader.cells.status.shown)
    assert.is_true(narrowHeader.cells.market.shown)
    assert.is_true(narrowHeader.cells.profit.shown)
    assert.equal(narrowHeader.cells.expand, narrowHeader.cells.action.points[1].relative)
    assert.equal(narrowHeader.cells.action, narrowHeader.cells.profit.points[1].relative)
    assert.equal(narrowHeader.cells.profit, narrowHeader.cells.market.points[1].relative)
    assert.equal(narrowHeader.cells.market, narrowHeader.cells.cost.points[1].relative)
    assert.equal(narrowHeader.cells.cost, narrowHeader.cells.item.points[2].relative)

    local GC = load(1100, record)
    local _, container = topRows(GC, {})
    local header
    for _, child in ipairs(container.children) do if child.cells then header = child break end end
    assert.is_nil(header.cells.queue)
    assert.is_true(header.cells.listed.shown)
    assert.is_true(header.cells.status.shown)
    assert.equal(header.cells.expand, header.cells.action.points[1].relative)
    assert.equal(header.cells.action, header.cells.status.points[1].relative)
    assert.equal(header.cells.status, header.cells.profit.points[1].relative)
    assert.equal(header.cells.profit, header.cells.market.points[1].relative)
    assert.equal(header.cells.market, header.cells.listed.points[1].relative)
    assert.equal(header.cells.listed, header.cells.cost.points[1].relative)
    assert.equal(header.cells.cost, header.cells.item.points[2].relative)
  end)

  it("orders Sell filters from broad to specific before Refresh", function()
    local GC = load(620, { calls = {} })
    local _, container = topRows(GC, {})
    local buttons = {}
    for _, child in ipairs(container.children) do
      if child.label then buttons[child.label] = child end
    end
    -- "AH" used to sit here as a provenance filter (units GoldCap watched arrive
    -- by mail), which reads as "my auctions" and is not what it did. The two
    -- cuts a seller actually wants are what is in the bags and what is already
    -- up for sale.
    assert.equal(buttons.Refresh, buttons["Missing cost"].points[1].relative)
    assert.equal(buttons["Missing cost"], buttons.Listed.points[1].relative)
    assert.equal(buttons.Listed, buttons["In bags"].points[1].relative)
    assert.equal(buttons["In bags"], buttons.GC.points[1].relative)
    assert.equal(buttons.GC, buttons.All.points[1].relative)
    assert.is_nil(buttons.AH)
  end)

  it("keeps every fixed-width Sell cell on one line", function()
    local GC = load(620, { calls = {} })
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 5, listedValue = 168898, sources = {}, status = "LISTED" },
    })
    local header
    for _, child in ipairs(container.children) do if child.cells then header = child break end end
    for _, key in ipairs({ "cost", "listed", "market", "profit", "status", "expand" }) do
      assert.is_false(header.cells[key].wordWrap, key)
      assert.is_false(rows[1].cells[key].wordWrap, key)
    end
  end)

  -- The action button gets its own column, and `status` keeps saying what is wrong or what to
  -- do. Drawing the button over `status` is what used to erase that sentence.
  it("keeps the row action in its own column beside the advice text", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        coverage = "PARTIAL", exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 20, sources = {} },
    })
    assert.equal("Set cost", rows[1].action.label)
    assert.equal("Cost unknown for 2 of 5", rows[1].cells.status.text)
    assert.equal("CENTER", rows[1].action.points[1].point)
    assert.equal(rows[1].cells.action, rows[1].action.points[1].relative)
    assert.equal("CENTER", rows[1].action.points[1].relativePoint)
  end)

  it("uses the header's ordered cell chain for real rows and sizes expansion scroll content", function()
    local function assertRow(width, listed)
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
      assert.equal(listed, row.cells.listed.shown)
      assert.equal(listed, row.cells.status.shown)
      assert.is_true(row.cells.market.shown)
      assert.is_nil(row.cells.queue)
      assert.equal(row.cells.expand, row.cells.action.points[1].relative)
      if listed then
        assert.equal(row.cells.action, row.cells.status.points[1].relative)
        assert.equal(row.cells.status, row.cells.profit.points[1].relative)
        assert.equal(row.cells.profit, row.cells.market.points[1].relative)
        assert.equal(row.cells.market, row.cells.listed.points[1].relative)
        assert.equal(row.cells.listed, row.cells.cost.points[1].relative)
      else
        assert.equal(row.cells.action, row.cells.profit.points[1].relative)
        assert.equal(row.cells.profit, row.cells.market.points[1].relative)
        assert.equal(row.cells.market, row.cells.cost.points[1].relative)
      end
      assert.equal(row.cells.cost, row.cells.item.points[2].relative)
      assert.equal(header.cells.expand, header.cells.action.points[1].relative)
      rows[1].scripts.OnClick(rows[1])
      local render = upvalue(GC.Sell.Attach, "renderRows")
      local content = upvalue(render, "content")
      assert.equal(width, content.width)
      -- Six rows now: the expansion is split into two labelled groups, listings before
      -- purchase history, because the listings are the part a player acts on.
      assert.equal(6 * 24, content.height)
      assert.equal("detail", rows[2].kind)
      assert.equal("group", rows[3].kind)
      assert.equal("On the Auction House", rows[3].cells.item.text:gsub("^%s+", ""))
      assert.equal("lot", rows[4].kind)
      assert.equal("group", rows[5].kind)
      assert.equal("What you paid", rows[5].cells.item.text:gsub("^%s+", ""))
      assert.equal("batch", rows[6].kind)
    end
    -- 700 and 620 both land past the advice column being shed; 1100 keeps every column.
    assertRow(700, false)
    assertRow(620, false)
    assertRow(1100, true)
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

  it("[WAVE2 I1] repairs the one displayed pending evidence by exact ID instead of inferring generic manual cost", function()
    local record = { calls = {}, repairs = {} }
    local GC = load(620, record)
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        coverage = "UNKNOWN", exposureQty = 2, knownQty = 0, knownCost = 0, listedValue = 0,
        pendingAcquisitions = { { id = "pending:9", itemID = 42, positionKey = "commodity:42",
          quantity = 2, character = "A-R", region = "eu" } }, sources = {} },
    })
    rows[1].action.scripts.OnClick()
    local dialog, confirm = container.costDialog
    for _, child in ipairs(dialog.children) do if child.label == "Confirm" then confirm = child end end
    dialog.total:SetText("9"); dialog.total.scripts.OnTextChanged()
    confirm.scripts.OnClick()

    assert.equal(0, #record.calls)
    assert.equal(1, #record.repairs)
    assert.equal("pending:9", record.repairs[1].pendingID)
    assert.equal("commodity:42", record.repairs[1].positionKey)
    assert.equal("A-R", record.repairs[1].character)
    assert.equal("eu", record.repairs[1].region)
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

  it("[round5 rerender] disarms an armed Repost when its pooled row shifts to another auction", function()
    local cancels, activity, timers = 0, 0, {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.C_AuctionHouse = { CancelAuction = function() cancels = cancels + 1 end }
    local GC = load(620, { calls = {} })
    local quote = { unit = 200, at = 77 }
    GC.QuoteCache.Fresh = function() return quote end
    GC.Acquisitions.RecordPost = function() activity = activity + 1 end
    GC.SellPositions.BuildRepostPlan = function(p, auctionID)
      return { positionKey = p.positionKey, scopeKey = p.scopeKey, itemID = p.itemID,
        auctionID = auctionID, quantity = 1, unitPrice = 200 }
    end
    GC.SellViewModel.Filter = function(values, mode)
      if mode == "listed" then return { values[2] } end
      return values
    end
    GC.SellViewModel.Expansion = function(p)
      return { note = "FIFO allocations", batches = {}, ownedLots = p.ownedLots }
    end
    local first = { itemID = 42, itemName = "First", positionKey = "commodity:42",
      scopeKey = "eu\1A-R\1commodity:42", coverage = "COMPLETE", exposureQty = 1,
      trackedQty = 1, listedQty = 1, knownQty = 1, knownCost = 100, listedValue = 220,
      sources = { goldcap = 1 }, status = "LISTED",
      ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 220 } } }
    local second = { itemID = 43, itemName = "Second", positionKey = "commodity:43",
      scopeKey = "eu\1A-R\1commodity:43", coverage = "COMPLETE", exposureQty = 1,
      trackedQty = 1, listedQty = 1, knownQty = 1, knownCost = 100, listedValue = 230,
      sources = { auction_house = 1 }, status = "LISTED",
      ownedLots = { { auctionID = 8, quantity = 1, unitPrice = 230 } } }
    local rows, container = topRows(GC, { first, second })

    rows[2].scripts.OnClick(rows[2])
    rows[1].scripts.OnClick(rows[1])
    -- rows[3] is the "On the Auction House" group heading now; the lot follows it.
    local firstLotRow = rows[4]
    assert.equal(7, firstLotRow.lot.auctionID)
    local staleClick = firstLotRow.action.scripts.OnClick
    firstLotRow.action.scripts.OnClick()
    assert.equal("armed", firstLotRow.repostStage)
    assert.equal(0, cancels)

    for _, child in ipairs(container.children) do
      if child.label == "Listed" then child.scripts.OnClick() end
    end
    assert.equal(8, firstLotRow.lot.auctionID)
    assert.is_nil(firstLotRow.repostStage)
    assert.equal("Repost", firstLotRow.action.label)
    assert.is_true(firstLotRow.action.enabled)

    for _, callback in ipairs(timers) do callback() end
    staleClick()
    GC.Sell.OnAuctionCreated()
    assert.equal(0, cancels)
    assert.equal(0, activity)
    assert.equal(8, firstLotRow.lot.auctionID)
    assert.is_nil(firstLotRow.repostStage)
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
    -- Plain-language detail line: market state, competition, velocity and time to clear. It no
    -- longer opens by naming the allocation rule, which told a seller nothing.
    assert.match("quote 7s · 3 ahead of you · sells 4/day · clears in ~1 days", rows[2].cells.item.text)
    assert.equal("Repost @ 149 · breakeven 106", rows[2].cells.status.text)
    -- rows[3] is the listings heading, rows[4] the lot, rows[5] the purchases heading.
    assert.equal("group", rows[3].kind)
    assert.equal("400", rows[4].cells.listed.text)
    assert.equal("group", rows[5].kind)
    -- No epoch, no allocator counters: how many, when, at what price, from where.
    assert.match("×5 bought .+ at 50 each · GoldCap", rows[6].cells.item.text)
    assert.equal("50", rows[6].cells.cost.text)
    assert.equal("100", rows[6].cells.listed.text)
    assert.equal("2 still unsold", rows[6].cells.status.text)
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
    -- Listings first, then purchases, each behind its own heading: rows[3] heading, rows[4] the
    -- lot, rows[5] heading, rows[6..9] the four batches.
    assert.equal("Post (undercut) @ 199 · breakeven 106", rows[2].cells.status.text)
    assert.match("×2 listed at 200 each", rows[4].cells.item.text)
    assert.equal("400", rows[4].cells.listed.text)
    assert.match("captured", rows[6].cells.item.text)
    assert.match("mail%-confirmed", rows[7].cells.item.text)
    assert.match("manual", rows[8].cells.item.text)
    assert.match("unknown evidence", rows[9].cells.item.text)
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

  it("[WAVE2 I4] renders a fresh quote price and age in the visible default-width expansion", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function(position)
      return { note = "FIFO allocations", batches = {}, ownedLots = {},
        displayMarketUnit = position.displayMarketUnit, quoteAge = position.quoteAge,
        marketState = position.marketState, marketFresh = position.marketFresh,
        marketStale = position.marketStale }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, sources = {},
        displayMarketUnit = 150, freshMarketUnit = 150, quoteAge = 3,
        marketState = "fresh", marketFresh = true, marketStale = false, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    local render = upvalue(GC.Sell.Attach, "renderRows")
    rows = upvalue(render, "rows")
    assert.equal("detail", rows[2].kind)
    assert.match("market 150 · fresh · age 3s", rows[2].cells.item.text)
    assert.same({ 1, 1, 1, 1 }, rows[2].cells.item.color)
  end)

  it("[WAVE2 I4] keeps a visible stale quote after timer recomposition and never acts on it", function()
    local now, timers = { value = 100 }, {}
    _G.time = function() return now.value end
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local GC = load(620, { calls = {} })
    _G.time = function() return now.value end
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
    GC.Acquisitions.Init({})
    GC.Acquisitions.Record({ source = "goldcap", itemID = 42, positionKey = "commodity:42",
      itemName = "Unlisted", quantity = 1, total = 100, acquiredAt = 1,
      evidenceKey = "buy:42", character = "A-R", region = "eu" })
    GC.Acquisitions.Record({ source = "goldcap", itemID = 43, positionKey = "commodity:43",
      itemName = "Listed", quantity = 1, total = 100, acquiredAt = 1,
      evidenceKey = "buy:43", character = "A-R", region = "eu" })

    local render = upvalue(GC.Sell.Attach, "renderRows")
    local compose = upvalue(GC.Sell.SellableCount, "composePositions")
    local owned = upvalue(compose, "ownedLots")
    owned[1] = { itemID = 43, positionKey = "commodity:43", quantity = 1,
      unitPrice = 200, auctionID = 7, firstSeenAt = 1 }
    local quotes = upvalue(compose, "quotes")
    quotes[42], quotes[43] = { unit = 150, at = 100 }, { unit = 150, at = 100 }
    compose()
    render()

    local rows = upvalue(render, "rows")
    assert.equal("150", rows[1].cells.market.text)
    assert.equal("42", tostring(rows[1].position.itemID))
    assert.equal(1, #timers)
    -- Wakes when the quote actually expires. The Sell tab treats a quote as good
    -- for SELL_QUOTE_ACTION_AGE (45s), not the Sniper's 10s: a listing competes
    -- over hours, and a 10s window made Post unclickable because pricing the tab
    -- took longer than the quote lasted.
    assert.equal(46, timers[1].seconds)
    rows[1].scripts.OnClick(rows[1])
    rows = upvalue(render, "rows")
    local freshDetail
    for _, row in ipairs(rows) do
      if row.kind == "detail" and row.position.itemID == 42 then freshDetail = row end
    end
    assert.match("market 150 · fresh · age 0s", freshDetail.cells.item.text)
    assert.same({ 1, 1, 1, 1 }, freshDetail.cells.item.color)

    now.value = 151
    assert.equal(2, #timers) -- the expansion render fences the older expiry callback
    timers[#timers].callback()
    rows = upvalue(render, "rows")
    local byItem = {}
    for _, row in ipairs(rows) do if row.kind == "position" then byItem[row.position.itemID] = row end end
    assert.equal(51, byItem[42].position.quoteAge)
    assert.equal("150 · stale 51s", byItem[42].cells.market.text)
    assert.equal("Unknown", byItem[42].cells.profit.text)
    assert.same({ .5, .5, .5, 1 }, byItem[42].cells.market.color)
    assert.equal(190, byItem[43].position.projectedNet)
    local staleDetail
    for _, row in ipairs(rows) do
      if row.kind == "detail" and row.position.itemID == 42 then staleDetail = row end
    end
    assert.match("market 150 · stale · age 51s", staleDetail.cells.item.text)
    assert.same({ .5, .5, .5, 1 }, staleDetail.cells.item.color)

    local listedPosition
    for _, row in ipairs(rows) do
      if row.kind == "position" and row.position.itemID == 43 then listedPosition = row end
    end
    listedPosition.scripts.OnClick(listedPosition)
    rows = upvalue(render, "rows")
    local listedLot
    for _, row in ipairs(rows) do
      if row.kind == "lot" and row.position.itemID == 43 then listedLot = row end
    end
    local refreshes, protectedCalls = 0, 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    _G.C_AuctionHouse = {
      CancelAuction = function() protectedCalls = protectedCalls + 1 end,
      PostCommodity = function() protectedCalls = protectedCalls + 1 end,
      PostItem = function() protectedCalls = protectedCalls + 1 end,
    }
    GC.Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end }
    listedLot.action.scripts.OnClick()
    -- A stale quote re-prices THIS item, not the whole tab. The old behaviour ran
    -- the full Refresh: owned auctions, then every priced row, one throttled round
    -- trip each -- so the "press it again in a moment" the button promised could be
    -- a minute away, by which point this item's quote had aged out again and the
    -- next click started another walk. That loop is why Post could not be pressed.
    assert.equal(0, refreshes)
    assert.same({ 43 }, upvalue(GC.Sell.OnThrottleReady, "refresh").queue)
    assert.equal(0, protectedCalls)

    now.value = 200
    quotes[42] = { unit = 160, at = 200 }
    compose()
    render()
    local resetTimer = timers[#timers]
    GC.Sell.Reset()
    resetTimer.callback()
    assert.equal("", tostring(quotes[42] or ""))
  end)
end)
