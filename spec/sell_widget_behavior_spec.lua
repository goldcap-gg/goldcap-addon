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
    function value:SetVariant(name) self.variant = name end
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
    -- The price box commits on Enter and on focus loss, and both clear focus afterwards.
    function value:ClearFocus() self.focused = false end
    function value:SetScrollChild(child) self.scrollChild = child end
    -- Rows own textures now (zebra banding, hover highlight, the bottom rule, the child spine
    -- and the item icon), so the double has to hand back regions for them like the real API.
    function value:CreateTexture(_, layer) local t = region("Texture", self); t.layer = layer; return t end
    function value:SetAllPoints(relative) self.allPoints = relative or self.parent end
    function value:SetColorTexture(...) self.colorTexture = { ... } end
    function value:SetTexture(path) self.texture = path end
    function value:SetTexCoord(...) self.texCoord = { ... } end
    function value:SetTextureSliceMargins(...) self.sliceMargins = { ... } end
    function value:SetVertexColor(...) self.vertexColor = { ... } end
    function value:SetBlendMode(mode) self.blendMode = mode end
    function value:SetSpacing(n) self.spacing = n end
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
        gold = { 0.83, 0.64, 0.22 }, panel = { 0.078, 0.086, 0.110 }, panelHi = { 0.102, 0.114, 0.141 },
        -- `watch` is the book's "this level is already yours" tint: its own colour on
        -- purpose, since gold already means "where your price would land".
        watch = { 0.35, 0.72, 0.90 } },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      MEDIA = "",
      Label = function(parent) return region("FontString", parent) end,
      Num = function(parent) return region("FontString", parent) end,
      -- M11: records the 3rd (rounded) argument -- Theme.Button(parent, variant, rounded)
      -- silently falls back to square on an unknown key, and this fake used to drop the
      -- argument entirely, so nothing here ever proved a caller actually asked for the
      -- rounded kit.
      Button = function(parent, _, rounded) local b = region("Button", parent); b.rounded = rounded; return b end,
      Card = function(parent) local card = region("Frame", parent); function card:SetTint() end return card end,
      SlicedTexture = function(parent, layer) local t = region("Texture", parent); t.layer = layer; return t end,
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
      -- Summary/Build stay doubles (see their own note below), but the rest of this module is
      -- loaded for real just after: the price control reads GC.SellPositions.PriceRisk, and a
      -- hand-written stand-in for that rule would let the warning a seller reads drift away
      -- from the flag BuildPostPlan actually carries -- which is the exact thing PriceRisk
      -- exists to keep in one place.
      SellPositions = {},
      Acquisitions = {
        RecordManual = function(args) record.calls[#record.calls + 1] = args; return {} end,
        RepairPendingManual = function(args) record.repairs[#record.repairs + 1] = args; return {} end,
      },
      Ledger = { Context = function() return { char = "A-R", region = "eu" } end },
    }
    -- Core/Util.lua: the order book formats its unit counts through GC.Util.FormatCount, and
    -- the .toc loads it long before this file, so a double without it is the spec lying about
    -- what the frame runs against.
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    -- Back over the real module: Refresh composes from the bags before it asks the server
    -- anything, so the tab shows what you could sell even away from an auctioneer. Tests that
    -- drive Refresh need a Build; those that assert on rows they injected by hand stub Refresh
    -- out instead, and neither wants the real composition walk here.
    GC.SellPositions.Summary = function() return { invested = nil, projected = nil, profit = nil } end
    GC.SellPositions.Build = function() return {} end
    helper.loadModule("UI/SellFrame.lua", GC)
    local root = region("Frame")
    root.HookScript = function(_, name, fn) root.scripts[name] = fn end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8, rowWidth = width, rowHeight = 24 })
    -- Attach leaves the Sell container hidden (it is only one of several tabs on the real
    -- Sniper window) -- renderRows now defers a rebuild while it is hidden, so every test
    -- below that reads rendered rows needs the container shown, the way GC.Sell.Show() (or
    -- the real tab switch that calls it) would leave it before a player ever sees this tab.
    local render = upvalue(GC.Sell.Attach, "renderRows")
    upvalue(render, "container"):Show()
    return GC, root
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

  -- A tracked position with nothing in the bags AND nothing listed is stock sitting in the
  -- mail, the bank, or on another character. Its status used to talk about cost coverage,
  -- which answered a question nobody asked while the real one -- "where is my ore?" -- went
  -- unanswered.
  it("says where the stock is not, for a position with no bags and no listings", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
        exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 0,
        bagQty = 0, listedQty = 0, sources = {} },
    })
    assert.equal("Not in your bags or listed — mail or bank?", rows[1].cells.status.text)
  end)

  -- Same shape, checking the ITEM cell and the row's own tooltip rather than STATUS: the row is
  -- real cost history, not a broken one, and the item name says so wherever the player is
  -- actually looking, not only in the one column that happened to have room.
  it("appends '· not on hand' to the item cell and its tooltip for a bag 0 / listed 0 position", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
        exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 0,
        bagQty = 0, listedQty = 0, sources = {} },
    })
    assert.matches("· not on hand", rows[1].itemStock.text, 1, true)
    assert.is_true(rows[1].notOnHand)
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end, Hide = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    rows[1].scripts.OnEnter(rows[1])
    local joined = table.concat(tooltipLines, " ")
    assert.matches("Not on hand", joined, 1, true)
    _G.GameTooltip = nil
  end)

  -- The row's own OnEnter only reads self.itemID via self.position -- give it one, since the
  -- fixture above never set it, and OnEnter guards on `self.position.itemID` before it does
  -- anything at all.
  it("clears the not-on-hand flag for a position with bag stock", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED" },
    })
    assert.not_matches("· not on hand", rows[1].itemStock.text, 1, true)
    assert.is_false(rows[1].notOnHand)
  end)

  -- Item 4 (addon polish batch): row.itemInset used to be set to 26 unconditionally, before the
  -- icon lookup even ran -- a position with no resolvable icon (no _G.C_Item stub, the default
  -- in every fixture in this file) showed the item name indented into a blank gap.
  it("does not indent the item name when no icon resolves", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED" },
    })
    assert.equal(0, rows[1].itemInset)
  end)

  it("indents the item name for the icon's width when one resolves", function()
    _G.C_Item = { GetItemIconByID = function() return "Interface\\Icons\\INV_Misc_Ore_01" end }
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED" },
    })
    assert.equal(26, rows[1].itemInset)
    -- MINOR-5 (fix round 1): no inline `_G.C_Item = nil` here on purpose -- the file's own
    -- after_each (top of this describe block) already clears it unconditionally, even if an
    -- assertion above this point had failed. A cleanup line living only on this test's last
    -- line ran only when nothing above it failed first.
  end)

  -- I2 (fix wave, sell honesty): an unresolved position (unassigned_acquisition/
  -- pending_purchase/paid_sale/ambiguous_sale, see Core/SellPositions.lua) has no stock to be
  -- "elsewhere" -- there IS no batch/lot backing it yet, so the mail/bank/alt claim above would
  -- be a fabrication about a position that is really "GoldCap doesn't know what this is",
  -- mirroring the STATUS branch's own `not p.unresolved` guard a few lines down.
  it("does not claim 'not on hand' for an unresolved position with bag 0 / listed 0", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "UNKNOWN",
        exposureQty = 5, knownQty = 5, knownCost = 500, listedValue = 0,
        bagQty = 0, listedQty = 0, sources = {}, unresolved = true },
    })
    assert.not_matches("· not on hand", rows[1].itemStock.text, 1, true)
    assert.is_false(rows[1].notOnHand)
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end, Hide = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    rows[1].scripts.OnEnter(rows[1])
    local joined = table.concat(tooltipLines, " ")
    assert.not_matches("Not on hand", joined, 1, true)
    _G.GameTooltip = nil
  end)

  -- "—" in MARKET is ambiguous: it reads as "not asked yet" even when the auction house
  -- already answered "nothing is listed". The remembered empty answer paints as "none".
  it("shows 'none' in the market cell for an item the AH answered empty about", function()
    local GC = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "emptyAnswers", { [42] = 70 })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        sources = {}, status = "UNLISTED" },
    })
    assert.equal("none", rows[1].cells.market.text)
    assert.equal("Nothing listed on the AH right now", rows[1].cells.status.text)
  end)

  -- Below "none" and "—" sits a third case: no live quote yet at all, but the position carries
  -- the imported goldcap.gg market value (the same number Deals shows). It stands in, dim and
  -- "≈"-prefixed so it never impersonates a live number, until a real quote lands.
  it("falls back to the imported market value, dim and '≈'-prefixed, with no live quote yet", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED", marketValue = 100000 },
    })
    assert.equal("≈10g", rows[1].cells.market.text)
    assert.same({ .5, .5, .5, 1 }, rows[1].cells.market.color)
    assert.is_true(rows[1].marketFallback)
    -- Minor (fix wave, sell honesty): "Unknown" profit beside a dim "≈" market used to render
    -- in the row's ordinary fg -- a confident-looking pair next to an admittedly approximate
    -- number. This fixture's ProfitText stub always returns "Unknown" (never overridden in
    -- this test), so the profit cell should read dim here too.
    assert.same({ .5, .5, .5, 1 }, rows[1].cells.profit.color)
    local tooltipLines = {}
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end, Hide = function() end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    rows[1].scripts.OnEnter(rows[1])
    local joined = table.concat(tooltipLines, " ")
    assert.matches("goldcap.gg market value", joined, 1, true)
    _G.GameTooltip = nil
  end)

  -- An AH answer of "nothing listed" still outranks the imported value: the addon already asked
  -- and got a real answer, so falling back to a guess from the last import would contradict it.
  it("keeps 'none' rather than the market-value fallback when the AH already answered empty", function()
    local GC = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "emptyAnswers", { [42] = 70 })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED", marketValue = 100000 },
    })
    assert.equal("none", rows[1].cells.market.text)
    assert.is_false(rows[1].marketFallback)
  end)

  -- Item 5 (addon polish batch): a one-off empty AH answer used to hide the market-value
  -- fallback forever (only a manual Refresh cleared emptyAnswers), even though nothing else in
  -- the tab treats a one-off empty answer as permanent -- see EMPTY_ANSWER_AGE and
  -- uniqueQuoteItemIDs's own re-query staleness check just above where this lives.
  -- MINOR-1 (fix round 1): STATUS now reads the same age-gated `emptyKnown` MARKET's fallback
  -- decides from, so a stale empty answer can't leave MARKET showing "≈…" while STATUS still
  -- insists "Nothing listed on the AH right now".
  it("shows the market-value fallback again once an empty answer goes stale, and STATUS agrees", function()
    local GC = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "emptyAnswers", { [42] = 0 }) -- load()'s _G.time() returns 77 -- 77s old, past EMPTY_ANSWER_AGE (60)
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED", marketValue = 100000 },
    })
    assert.equal("≈10g", rows[1].cells.market.text)
    assert.is_true(rows[1].marketFallback)
    assert.equal("Waiting for a live price", rows[1].cells.status.text)
  end)

  -- A stale empty answer becomes "due" for re-query (uniqueQuoteItemIDs), and the walk only
  -- ever has one request in flight (refresh.pending) -- while THIS item is the one being asked
  -- again, the row must not flicker fallback-in only to flicker back to a real answer moments
  -- later. STATUS must stay consistent with MARKET here too: both still call it "none" known,
  -- not stale-and-unknown, while the re-query is in flight.
  it("keeps 'none' while the walk is actively re-querying a now-stale empty answer, and STATUS agrees", function()
    local GC = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "emptyAnswers", { [42] = 0 })
    -- MINOR-4 (fix round 1): sets .pending on the REAL shared `refresh` table (real shape:
    -- generation/phase/queue/index/pending/awaiting/drain) instead of replacing the whole
    -- upvalue with a one-field double -- renderRows only happens to read `.pending` today, but
    -- a double this thin is the "fakes richer than the real widget" trap in reverse.
    upvalue(render, "refresh").pending = { itemID = 42 }
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED", marketValue = 100000 },
    })
    assert.equal("none", rows[1].cells.market.text)
    assert.is_false(rows[1].marketFallback)
    assert.equal("Nothing listed on the AH right now", rows[1].cells.status.text)
  end)

  -- "Unknown · 1 partial · 37 missing" used to render in the same confident green as a real
  -- profit, which read as a number the addon stood behind. A non-number is an absence: dim.
  it("paints a non-numeric summary profit dim instead of a confident green", function()
    local GC = load(620, { calls = {} })
    local _, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "UNKNOWN",
        exposureQty = 1, knownQty = 0, knownCost = 0, listedValue = 0, sources = {} },
    })
    assert.equal("Unknown", container.summary.profit.text)
    assert.same({ .5, .5, .5, 1 }, container.summary.profit.color)
    -- Plain "Unknown" carries no " · " suffix at all: no detail to show, so no tooltip either.
    assert.is_nil(container.summaryProfitDetail)
  end)

  -- The stat-card's own value line ellipsized into unreadable garbage at Theme.Scale() 1.3 when
  -- SummaryText's non-number carried a "12 partial"/"37 missing" suffix. The card now shows
  -- plain "Unknown" and the suffix moves to container.summaryProfitDetail, which the profit
  -- card's own hit frame reads live to build its tooltip (see summaryProfitHit below).
  it("moves the missing/partial detail off the profit card and onto its tooltip", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.SummaryText = function(summary)
      return { knownCost = summary.knownCost, listedValue = summary.listedValue, profit = "Unknown · 2 partial" }
    end
    local _, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
        exposureQty = 1, knownQty = 0, knownCost = 0, listedValue = 0, sources = {} },
    })
    assert.equal("Unknown", container.summary.profit:GetText())
    assert.equal("2 partial", container.summaryProfitDetail)
    local hit = container.summaryProfitHit
    assert.truthy(hit)
    assert.is_true(hit.mouseEnabled)
    assert.is_function(hit.scripts.OnEnter)
    local tooltipLines = {}
    local hidden = false
    _G.GameTooltip = {
      SetOwner = function() end, Show = function() end, Hide = function() hidden = true end,
      AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    }
    hit.scripts.OnEnter(hit)
    local joined = table.concat(tooltipLines, " ")
    assert.matches("Est. profit", joined, 1, true)
    assert.matches("2 partial", joined, 1, true)
    assert.matches("excluded", joined, 1, true)
    hit.scripts.OnLeave(hit)
    assert.is_true(hidden)
    _G.GameTooltip = nil
  end)

  -- Numeric profit is unchanged, and any stale detail from an earlier render is cleared rather
  -- than lingering for the tooltip to keep showing on a now-complete summary.
  it("clears summaryProfitDetail once the profit is a real number again", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.SummaryText = function(summary)
      return { knownCost = summary.knownCost, listedValue = summary.listedValue, profit = "Unknown · 2 partial" }
    end
    local _, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
        exposureQty = 1, knownQty = 0, knownCost = 0, listedValue = 0, sources = {} },
    })
    assert.equal("2 partial", container.summaryProfitDetail)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    GC.SellViewModel.SummaryText = function(summary)
      return { knownCost = summary.knownCost, listedValue = summary.listedValue, profit = 50000 }
    end
    render()
    assert.equal("5g", container.summary.profit:GetText())
    assert.is_nil(container.summaryProfitDetail)
  end)

  -- A real number is no longer proof that nothing was excluded: SellPositions.Summary sums only
  -- the positions that individually clear both gates, so the total can still be partial. The
  -- exclusions ride along on summaryProfitDetail exactly like the "Unknown · ..." case above,
  -- for the same hit-frame tooltip to show.
  it("carries the exclusion detail on summaryProfitDetail even when the card shows a real number", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.SummaryText = function(summary)
      return { knownCost = summary.knownCost, listedValue = summary.listedValue,
        profit = 900000, profitDetail = "over 1 position · 1 without cost · 1 without a price" }
    end
    local _, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 0, listedValue = 0, sources = {} },
    })
    assert.equal("90g", container.summary.profit:GetText())
    assert.equal("over 1 position · 1 without cost · 1 without a price", container.summaryProfitDetail)
  end)

  -- Item 2 (addon polish batch): a partial total painting the number itself in full confidence
  -- (only the tooltip said otherwise) is exactly the failure mode the exclusion-detail fix above
  -- was meant to close -- the card's own text must carry the marker too. Real (unstubbed)
  -- SellViewModel.SummaryText here, so this proves the frame actually renders profitMarker, not
  -- just that the view model computes it (see spec/sell_view_model_spec.lua for that half).
  it("marks the profit card itself when the total is partial, not only its tooltip", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.SummaryText = function(summary)
      return { knownCost = summary.knownCost, listedValue = summary.listedValue,
        profit = 900000, profitDetail = "over 1 position · 1 without cost", partial = true,
        profitMarker = "*" }
    end
    local _, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 0, listedValue = 0, sources = {} },
    })
    assert.equal("90g*", container.summary.profit:GetText())
  end)

  -- The PROFIT / UNIT cell has never had a numeric assertion of its own -- every existing test
  -- either stubs ProfitText to "Unknown" or checks the row it lives on for something else. Row
  -- 1: a known cost with no hold price renders the plain per-unit figure, untouched -- the
  -- "nothing changes" half of the hold-price fix. Rows 2 and 3 are that fix: `profitAtHold` set
  -- on the position means PostFloor (or the queue-at-exit rule) held postRecommendation.unit
  -- above the live ask, so this number is the recommendation, not today's market, and the cell
  -- says so with a dim ` @ <holdUnit>` suffix and a gold (not green) tone -- unless the held
  -- number is STILL a loss, which stays red regardless.
  describe("PROFIT / UNIT cell", function()
    it("renders the exact per-unit figure for a position with a known cost and no hold price", function()
      local GC = load(620, { calls = {} })
      GC.SellViewModel.ProfitText = function(p) return p.profit end
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 2, knownQty = 2, knownCost = 100, listedValue = 0, bagQty = 2,
          listedQty = 0, sources = {}, profit = 170000 },
      })
      -- 170000 / 2 = 85000/unit = 8g50s.
      assert.equal("8g50s", rows[1].cells.profit.text)
      assert.same({ 1, 1, 1, 1 }, rows[1].cells.profit.color)
    end)

    -- The regression this cell is most exposed to: rows are pooled and rebound to a new
    -- position on every render, so a row painted gold or red by the hold branch on one pass
    -- must not still be gold or red on the next pass, once the position it now holds is back
    -- to the ordinary case. A row.cells.profit that only ever gets SetColor'd from the hold
    -- branch would leak exactly that tint forward.
    it("clears a held row's gold tint on the next render once the position is ordinary again", function()
      local GC = load(620, { calls = {} })
      GC.SellViewModel.ProfitText = function(p) return p.profit end
      local held = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {}, profit = 8500, profitAtHold = 15000 },
      })
      assert.same({ 0.83, 0.64, 0.22, 1 }, held[1].cells.profit.color)

      local ordinary = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {}, profit = 8500 },
      })
      assert.equal("8500", ordinary[1].cells.profit.text)
      assert.same({ 1, 1, 1, 1 }, ordinary[1].cells.profit.color)
    end)

    it("renders a positive hold-price profit in gold with the held unit named", function()
      local GC = load(620, { calls = {} })
      GC.SellViewModel.ProfitText = function(p) return p.profit end
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {}, profit = 8500, profitAtHold = 15000 },
      })
      assert.equal("8500 |cff9d9d9d@1g|r", rows[1].cells.profit.text)
      assert.same({ 0.83, 0.64, 0.22, 1 }, rows[1].cells.profit.color)
    end)

    it("keeps a negative hold-price profit red, suffix and all", function()
      local GC = load(620, { calls = {} })
      GC.SellViewModel.ProfitText = function(p) return p.profit end
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {}, profit = -11500, profitAtHold = 15000 },
      })
      assert.equal("-1g15s |cff9d9d9d@1g|r", rows[1].cells.profit.text)
      assert.same({ 1, 0, 0, 1 }, rows[1].cells.profit.color)
    end)
  end)

  -- I3 (fix wave, sell honesty): "no live quote yet -- pricing..." on an expanded position's
  -- detail row promises the pricing walk will reach this row -- but uniqueQuoteItemIDs (the
  -- walk's own queue builder, see the comment above `notOnHand` in renderRows) only picks up a
  -- position with bag or listed stock. A not-on-hand position is never queued, so the old copy
  -- was a promise the addon could not keep. GC.SellViewModel.Expansion is stubbed to an empty
  -- table by this file's own `load()`, so `#facts == 0` on every case below regardless.
  describe("detail row copy for the empty-facts fallback", function()
    it("says 'not priced' for a not-on-hand position's expanded detail row", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
          exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 0,
          bagQty = 0, listedQty = 0, sources = {} },
      })
      assert.equal("not priced — nothing on hand to sell", rows[2].subItem.text)
      assert.same({ .5, .5, .5, 1 }, rows[2].subItem.color)
    end)

    it("keeps 'no live quote yet -- pricing...' for a bag-stock position awaiting a quote", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "PARTIAL",
          exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 0,
          bagQty = 3, listedQty = 0, sources = {} },
      })
      assert.equal("no live quote yet — pricing…", rows[2].subItem.text)
      assert.same({ .5, .5, .5, 1 }, rows[2].subItem.color)
    end)
  end)

  -- The one number on this screen that spends real gold was, until now, the one number a
  -- seller could not see the workings of or change: GoldCap picked it and Post sent it. These
  -- cover the control that changed that -- and, just as much, the two warnings that are the
  -- price of allowing it, since the floor those warnings name used to be enforced by refusing.
  describe("the price control in an expanded row", function()
    local function priceRow(GC, over)
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      GC.SellViewModel.Expansion = function()
        return { batches = {}, ownedLots = {}, note = "FIFO allocations",
          book = { rows = {}, levels = 3, totalUnits = 300, widest = 100,
            cheapestCompeting = 420500, yourUnit = 420400, yourRow = nil } }
      end
      local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 5, knownQty = 5, knownCost = 2000000, listedValue = 0, -- 400000/unit paid
        bagQty = 5, listedQty = 0, sources = {}, marketValue = 500000,
        postRecommendation = { unit = 430000 } }
      for k, v in pairs(over or {}) do p[k] = v end
      local rows = topRows(GC, { p })
      for _, row in ipairs(rows) do if row.kind == "price" then return row, rows, GC end end
      error("no price row rendered")
    end

    it("prefills the box with the price Post would actually list at", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      assert.equal("YOUR PRICE", row.subItem.text)
      assert.equal("43", row.priceBox.text) -- 430000 copper, in gold, as the box takes it
      assert.matches("GoldCap's", row.priceNote.text, 1, true)
      assert.matches("×5", row.priceNote.text, 1, true)
    end)

    -- Asserted through the box the seller looks at, not through the table behind it: what
    -- matters is that the number they typed is the number the row now shows and prices with.
    it("takes a price the seller types and says it is theirs now", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      -- Above the 40g break-even on purpose: a price under it gets the loss warning instead,
      -- which is its own test below.
      row.priceBox.text = "45"
      row.priceBox.scripts.OnEnterPressed(row.priceBox)
      local after = priceRow(GC)
      assert.equal("45", after.priceBox.text)
      assert.matches("yours", after.priceNote.text, 1, true)
    end)

    -- Emptying the box is an answer, not a failure to give one.
    it("hands the decision back to GoldCap when the box is cleared", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      row.priceBox.text = "45"
      row.priceBox.scripts.OnEnterPressed(row.priceBox)
      row = priceRow(GC)
      row.priceBox.text = "  "
      row.priceBox.scripts.OnEnterPressed(row.priceBox)
      local after = priceRow(GC)
      assert.equal("43", after.priceBox.text)
      assert.matches("GoldCap's", after.priceNote.text, 1, true)
    end)

    it("refuses a price it cannot read rather than recording a nonsense one", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      row.priceBox.text = "not a price"
      row.priceBox.scripts.OnEnterPressed(row.priceBox)
      assert.equal("43", priceRow(GC).priceBox.text)
    end)

    -- Every fill comes from a number already on the screen, so none of them can invent a price.
    it("fills from the book, the market and the cost, and disables a chip with nothing behind it", function()
      local function fill(slot)
        local GC = load(700, { calls = {} })
        local row = priceRow(GC)
        row.priceChips[slot].scripts.OnClick(row.priceChips[slot])
        return priceRow(GC).priceBox.text
      end
      assert.equal("42.05", fill(1)) -- MATCH: the cheapest ask that is not yours
      assert.equal("42.04", fill(2)) -- UNDERCUT: one silver under it
      assert.equal("50", fill(3))    -- MARKET: the imported market value
      assert.equal("40", fill(4))    -- COST: the break-even, 2000000 over 5 units

      -- No cost basis, no COST chip: the alternative is a chip that fills a cost the addon
      -- does not have.
      local bare = load(700, { calls = {} })
      local row2 = priceRow(bare, { coverage = "UNKNOWN", knownQty = 0, knownCost = 0 })
      assert.is_false(row2.priceChips[4].enabled)
      assert.is_true(row2.priceChips[1].enabled)
    end)

    -- The price of letting the price be typed: the addon says what it would otherwise have
    -- quietly prevented, at the moment of the decision rather than after the gold is gone.
    it("says out loud when the chosen price is under GoldCap's own floor", function()
      local GC = load(700, { calls = {} })
      -- No cost basis, so the floor is the only thing this price is under.
      local row = priceRow(GC, { coverage = "UNKNOWN", knownQty = 0, knownCost = 0,
        postFloor = 450000, postRecommendation = { unit = 300000 } })
      assert.matches("under GoldCap's own floor", row.priceNote.text, 1, true)
      assert.same({ 1, 0, 0, 1 }, row.priceNote.color)
    end)

    -- Below what it cost outranks below the floor: one is a loss, the other is a rule.
    it("leads with the loss when the price is under what the stock cost", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC, { postFloor = 450000, postRecommendation = { unit = 300000 } })
      assert.matches("below the 40g you paid", row.priceNote.text, 1, true)
      assert.same({ 1, 0, 0, 1 }, row.priceNote.color)
    end)

    it("draws no price control for a position with nothing in the bags", function()
      local GC = load(700, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      GC.SellViewModel.Expansion = function()
        return { batches = {}, ownedLots = {}, note = "FIFO allocations" }
      end
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 5, knownQty = 5, knownCost = 10, listedValue = 0,
          bagQty = 0, listedQty = 0, sources = {} },
      })
      for _, row in ipairs(rows) do assert.not_equal("price", row.kind) end
    end)
  end)

  -- The Sell tab has priced against the live order book since it existed and never showed it:
  -- the floor, the recommendation and the depth ahead of your own lot all read `levels`, and
  -- the seller got a price with nothing to say what it was standing on. These drive the real
  -- renderRows, so they cover the rows a player actually sees rather than the model behind
  -- them (spec/sell_book_spec.lua covers that).
  describe("the order book in an expanded row", function()
    local function bookRows(GC, book)
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      GC.SellViewModel.Expansion = function()
        return { batches = {}, ownedLots = {}, note = "FIFO allocations", book = book }
      end
      return topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 5, knownQty = 5, knownCost = 10, listedValue = 0,
          bagQty = 5, listedQty = 0, sources = {} },
      })
    end

    -- By kind, not by index: the expansion gained the price control ahead of the book, and a
    -- test that counts rows breaks every time a section is added rather than when the thing it
    -- is about changes.
    local function nth(rows, kind, n)
      local seen = 0
      for _, row in ipairs(rows) do
        if row.kind == kind then
          seen = seen + 1
          if seen == (n or 1) then return row end
        end
      end
      error(("no %s row #%d"):format(kind, n or 1))
    end

    local BOOK = {
      levels = 4, totalUnits = 1062, truncated = false, widest = 620,
      cheapestCompeting = 418800, yourUnit = 420400, yourRow = 2,
      rows = {
        { unit = 418800, units = 12, ownerUnits = 0, mine = false, cumulative = 12 },
        { unit = 420500, units = 340, ownerUnits = 0, mine = false, cumulative = 352 },
        { unit = 426000, units = 90, ownerUnits = 90, mine = true, cumulative = 442 },
      },
    }

    it("heads the section with the price to actually beat, not the cheapest row on screen", function()
      local GC = load(620, { calls = {} })
      local rows = bookRows(GC, BOOK)
      -- The heading carries its own hint inline: the status cell it used to sit in is the
      -- first column a narrow window sheds, and the cheapest ask that is not yours is the one
      -- line worth keeping when the window is too small to show much else.
      assert.matches("^THE BOOK", nth(rows, "group").sectionLabel.text)
      assert.matches("cheapest not yours", nth(rows, "group").sectionLabel.text, 1, true)
      assert.matches("1062 units", nth(rows, "group").sectionLabel.text, 1, true)
      assert.matches("4 prices", nth(rows, "group").sectionLabel.text, 1, true)
      -- The colour legend is said once, in the heading, because the rows carry the two facts
      -- in colour rather than in a marker glyph the bundled face does not have.
      assert.matches("gold is where your price lands", nth(rows, "group").sectionLabel.text, 1, true)
    end)

    -- Depth and queue live in the book's OWN widgets, not in the position columns: those shed
    -- on a narrow window, which is exactly how the first cut of this ended up drawing a bare
    -- list of prices with the two numbers that matter missing.
    it("prints each level with its own depth and the queue standing in front of it", function()
      local GC = load(620, { calls = {} })
      local rows = bookRows(GC, BOOK)
      assert.equal("12", nth(rows, "level", 1).bookUnits.text)
      assert.equal("12", nth(rows, "level", 1).bookCumul.text)
      assert.equal("340", nth(rows, "level", 2).bookUnits.text)
      assert.equal("352", nth(rows, "level", 2).bookCumul.text)  -- 12 + 340 ahead of this price
      assert.is_true(nth(rows, "level", 1).bookUnits.shown)
      assert.is_true(nth(rows, "level", 1).bookBar.shown)
    end)

    -- Colour carries the two things a seller cannot work out from one recommended number.
    -- Deliberately not a ◆/▸ glyph: the bundled face has neither, and they drew as empty
    -- boxes in game.
    it("colours where your price lands and which levels are already yours", function()
      local GC = load(620, { calls = {} })
      local rows = bookRows(GC, BOOK)
      local GOLD, WATCH = GC.Theme.color.gold, GC.Theme.color.watch
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 1 }, nth(rows, "level", 2).subItem.color)
      assert.is_true(nth(rows, "level", 2).bookTint.shown)
      assert.same({ WATCH[1], WATCH[2], WATCH[3], 1 }, nth(rows, "level", 3).subItem.color)
      assert.is_true(nth(rows, "level", 3).bookTint.shown)
      -- A level that is neither is just a price: no tint, no marker in the text.
      assert.is_false(nth(rows, "level", 1).bookTint.shown)
      assert.equal("", nth(rows, "level", 1).subItem.text:gsub("[%d%a]", ""):gsub("%s", ""))
    end)

    -- Rows are pooled and rebound to a different kind on every render, so a book row's own
    -- widgets have to be put away by whichever kind takes the row next.
    it("puts the book widgets away on a row that stops being a level", function()
      local GC = load(620, { calls = {} })
      -- The row OBJECT is captured before the second render, not looked up again after it:
      -- rows are pooled, and a pooled row that goes unused keeps the kind it last carried.
      local reused = nth(bookRows(GC, BOOK), "level", 1)
      assert.is_true(reused.bookUnits.shown)
      bookRows(GC, nil)
      assert.is_false(reused.bookUnits.shown)
      assert.is_false(reused.bookBar.shown)
      assert.is_false(reused.bookTint.shown)
      -- And the fixed price-column width goes with them: a leftover width fights the
      -- LEFT/RIGHT pair every other sub-row is anchored with.
      assert.equal(0, reused.subItem.width)
    end)

    it("draws no book section at all when the addon has no live book", function()
      local GC = load(620, { calls = {} })
      local rows = bookRows(GC, nil)
      for _, row in ipairs(rows) do
        if row.sectionLabel and row.sectionLabel.text == "THE BOOK" then
          error("a book section was rendered with no book behind it")
        end
      end
    end)
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

  -- OnClick hands its handler (self, button, down). Passing GC.Sell.Refresh
  -- straight in meant the button arrived as the `automatic` flag -- truthy -- and
  -- every press took the stand-aside path that exists for the self-driven repeat.
  -- The button would have gone on doing nothing, which is the bug that flag was
  -- added to fix.
  it("presses Refresh as a real press, not as the automatic repeat", function()
    local GC = load(620, { calls = {} })
    -- Counted separately from the captured argument: the argument this asserts on
    -- is nil, and `seen[#seen + 1] = nil` stores nothing at all.
    local presses, captured = 0, "unset"
    GC.Sell.Refresh = function(automatic) presses = presses + 1; captured = automatic end
    local _, container = topRows(GC, {})
    for _, child in ipairs(container.children) do
      if child.label == "REFRESH" then child.scripts.OnClick(child, "LeftButton", false) end
    end
    assert.equal(1, presses)
    assert.is_nil(captured)
  end)

  -- "I pressed Refresh but I cannot tell whether it is running." The status line
  -- it writes to lives in the Sniper's toolbar, at the far left of a different
  -- row -- a window's width from the button that was just pressed. Same distance
  -- that made Scan look dead.
  it("shows its own progress on the Refresh button", function()
    local GC = load(620, { calls = {} })
    local _, container = topRows(GC, {})
    local button
    for _, child in ipairs(container.children) do
      if child.label == "REFRESH" then button = child end
    end
    assert.is_not_nil(button)

    local setStatus = upvalue(GC.Sell.Refresh, "setStatus")
    local state = upvalue(GC.Sell.OnThrottleReady, "refresh")
    state.phase, state.queue, state.index = "waiting_result", { 1, 2, 3 }, 2
    setStatus("Pricing 2/3…")
    -- The word matters, not just the ratio. This button is the last thing in a row of filter
    -- chips, so a bare "2/3" read as another filter -- and the count it shows is a position in
    -- the pricing queue, not a number of items the player owns.
    assert.equal("PRICING 2/3", button.label)

    state.phase = "done"
    setStatus("Prices up to date")
    assert.equal("REFRESH", button.label)
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
    assert.equal(buttons.REFRESH, buttons["MISSING COST"].points[1].relative)
    assert.equal(buttons["MISSING COST"], buttons.LISTED.points[1].relative)
    assert.equal(buttons.LISTED, buttons["IN BAGS"].points[1].relative)
    assert.equal(buttons["IN BAGS"], buttons.GC.points[1].relative)
    assert.equal(buttons.GC, buttons.ALL.points[1].relative)
    assert.is_nil(buttons.AH)

    -- The active filter must be visible on the chip itself (SetVariant), not just
    -- inferred from filterMode -- see paintFilterChips.
    assert.equal("active", buttons.ALL.variant)
    assert.equal("ghost", buttons["MISSING COST"].variant)
    assert.equal("ghost", buttons.LISTED.variant)
    assert.equal("ghost", buttons["IN BAGS"].variant)
    assert.equal("ghost", buttons.GC.variant)

    buttons.LISTED.scripts.OnClick()
    assert.equal("active", buttons.LISTED.variant)
    assert.equal("ghost", buttons.ALL.variant)
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
      -- listedQty is part of the shape Build actually produces for a listed position; the
      -- fixture originally omitted it and silently modelled a stockless ghost instead.
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", scopeKey = "eu\1A-R\1commodity:42",
        coverage = "PARTIAL", exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 20,
        listedQty = 1, sources = {} },
    })
    assert.equal("Set cost", rows[1].action.label)
    assert.equal("Cost unknown for 2 of 5", rows[1].cells.status.text)
    assert.equal("CENTER", rows[1].action.points[1].point)
    assert.equal(rows[1].cells.action, rows[1].action.points[1].relative)
    assert.equal("CENTER", rows[1].action.points[1].relativePoint)
  end)

  -- M11: Theme.Button(parent, variant, rounded) silently falls back to square on an unknown
  -- `rounded` key, and until now every Sell spec fake ignored the 3rd argument entirely -- so
  -- nothing here ever proved a real caller actually asked for the rounded kit.
  it("builds every toolbar control and the row action in the rounded kit", function()
    local GC = load(620, { calls = {} })
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {} },
    })
    assert.equal("plaque", container.queueButton.rounded)
    assert.equal("plaque", container.refreshButton.rounded)
    assert.equal("plaque", container.cancelButton.rounded)
    assert.equal("badge", container.filterButtons.all.rounded)
    assert.equal("badge", rows[1].action.rounded)
  end)

  it("uses the header's ordered cell chain for real rows and sizes expansion scroll content", function()
    local function assertRow(width, listed, advice)
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
      assert.equal(advice, row.cells.status.shown)
      assert.is_true(row.cells.market.shown)
      -- What you paid survives every one of these widths now: it is the question the tab
      -- exists to answer, and it used to be dropped before the window even left its default.
      assert.is_true(row.cells.cost.shown)
      assert.is_nil(row.cells.queue)
      assert.equal(row.cells.expand, row.cells.action.points[1].relative)
      -- Each shown column anchors to the one on its right, right to left, whichever of the
      -- optional two survived this width. Built from the shown set rather than branched per
      -- case: the three widths below now produce three different chains, not two.
      local chain = { "cost" }
      if listed then chain[#chain + 1] = "listed" end
      chain[#chain + 1] = "market"
      chain[#chain + 1] = "profit"
      if advice then chain[#chain + 1] = "status" end
      chain[#chain + 1] = "action"
      chain[#chain + 1] = "expand"
      for i = 1, #chain - 1 do
        assert.equal(row.cells[chain[i + 1]], row.cells[chain[i]].points[1].relative,
          chain[i] .. " does not anchor to " .. chain[i + 1])
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
      assert.matches("^ON THE AUCTION HOUSE", rows[3].sectionLabel.text)
      assert.equal("lot", rows[4].kind)
      assert.equal("group", rows[5].kind)
      assert.matches("^WHAT YOU PAID", rows[5].sectionLabel.text)
      assert.equal("batch", rows[6].kind)
    end
    -- 700 sheds the listed total but keeps the advice at its own minimum; 620 sheds the
    -- advice as well; 1100 keeps every column at full width. COST/UNIT survives all three.
    assertRow(700, false, true)
    assertRow(620, false, false)
    assertRow(1100, true, true)
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
    -- Which item, and the default quantity: both used to be missing/wrong. The dialog was
    -- anonymous (no header said which position it was for) and always defaulted to "1" even
    -- when several units had no cost.
    assert.match("^Ore", container.costDialog.header:GetText())
    assert.match("2 units without a cost$", container.costDialog.header:GetText())
    assert.equal("2", container.costDialog.quantity:GetText())
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
    assert.is_true(labels.Quantity); assert.is_true(labels["Unit cost (gold)"]); assert.is_true(labels["Total cost (gold)"])
    -- Default quantity is the full uncosted count (2 here), not "1".
    assert.equal("2", dialog.quantity:GetText())
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
    -- "5" is 5 GOLD, not 5 copper: with quantity 2 that is 2.5g/unit, and the live coin
    -- preview under Total shows what will actually be recorded, in copper.
    dialog.total:SetText("5"); dialog.total.scripts.OnTextChanged()
    assert.equal("5", dialog.total:GetText()); assert.equal("2.5", dialog.unit:GetText())
    assert.equal("50000", dialog.totalPreview:GetText())
    dialog.unit:SetText("9007199254740991"); dialog.unit.scripts.OnTextChanged()
    assert.equal("Enter an exact positive cost", dialog.error.text)
    assert.equal(0, #record.calls)
    assert.equal("", dialog.totalPreview:GetText())
    dialog.unit:SetText("3"); dialog.unit.scripts.OnTextChanged()
    assert.equal("6", dialog.total:GetText())
    assert.equal("60000", dialog.totalPreview:GetText())
    confirm.scripts.OnClick(); confirm.scripts.OnClick()
    assert.equal(1, #record.calls)
    -- Downstream (RecordManual) still receives an exact COPPER total: 2 units at 3g each is
    -- 60000 copper, never "6".
    assert.same({ itemID = 42, positionKey = "commodity:42", itemName = "Ore", quantity = 2, total = 60000,
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
    -- Unit/Total now accept decimals ("1.5" is a perfectly valid 1g50s), so what invalidates a
    -- formerly-valid total is a negative amount, not a fractional one.
    dialog.unit:SetText("-2"); dialog.unit.scripts.OnTextChanged()
    assert.equal("", dialog.total:GetText())
    assert.equal("Enter an exact positive cost", dialog.error.text)
    assert.equal("", dialog.totalPreview:GetText())
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

    -- "5" is 5 GOLD; with quantity still 2 that is 2.5g/unit.
    dialog.total:SetText("5"); dialog.total.scripts.OnTextChanged()
    assert.equal("2.5", dialog.unit:GetText())
    dialog.quantity:SetText("1"); dialog.quantity.scripts.OnTextChanged()
    assert.equal("5", dialog.total:GetText())
    assert.equal("5", dialog.unit:GetText())

    confirm.scripts.OnClick(); confirm.scripts.OnClick()
    -- Recorded total is the exact COPPER amount (5g = 50000c), not the typed "5".
    assert.same({ itemID = 42, positionKey = "commodity:42", itemName = "Ore", quantity = 1, total = 50000,
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
    -- "9" is 9 gold; RecordManual still receives an exact copper total (90000), never "9".
    assert.same({ itemID = 7, positionKey = "item:7:1:0:0", itemName = "Odd", quantity = 1, total = 90000,
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

  -- Was: "disarms a posting row when a rerender cannot prove the pinned position
  -- identity". A render used to answer an armed post by cancelling it, which is
  -- the wrong half of the trade -- the player is one click from confirming, and
  -- the tab now re-prices itself every few seconds, so that cancellation went
  -- from occasional to certain. The render is held instead. Safety is unchanged:
  -- the confirm path re-reads the bag live, re-checks the scope, and re-checks
  -- the quote identity, so a stale position table can only supply keys that are
  -- all verified again before any gold moves. Both arms are timeout-bounded.
  it("holds a rerender while a post is armed, and runs it once the arm clears", function()
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
    assert.equal("posting", rows[1].postStage)

    -- The post resolves (here: the auction house reports it failed), which
    -- disarms the row and flushes the render that was held. Refresh is stubbed
    -- out: this is about the disarm, not about recomposing from the bags.
    GC.Sell.Refresh = function() end
    GC.Sell.OnPostError()
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
      if child.label == "LISTED" then child.scripts.OnClick() end
    end
    -- The filter change cannot repoint this pooled row at auction 8 while the row
    -- is armed on auction 7 -- which is the hazard the old behaviour answered by
    -- cancelling the arm. Holding the render answers it at the source: the row
    -- never moves, so nothing can carry the arm to a different auction.
    assert.equal(7, firstLotRow.lot.auctionID)
    assert.equal("armed", firstLotRow.repostStage)

    GC.Sell.Refresh = function() end -- see above: this is about the disarm
    GC.Sell.OnPostError() -- disarms, and flushes the render the filter asked for
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
    assert.match("quote 7s ago · 3 ahead of you · sells 4/day · clears in ~1d", rows[2].subItem.text)
    assert.equal("Repost @ 149", rows[2].cells.status.text)
    -- rows[3] is the listings heading, rows[4] the lot, rows[5] the purchases heading.
    assert.equal("group", rows[3].kind)
    assert.equal("400", rows[4].cells.listed.text)
    -- "»", not "→": U+2192 is missing from the client font and rendered as a tofu box.
    assert.equal("» needs price", rows[4].cells.market.text)
    assert.equal("group", rows[5].kind)
    -- No epoch, no allocator counters: how many, when, at what price, from where. The unit
    -- price no longer repeats -- the COST cell two columns over already carries it.
    assert.match("×5 · bought .+ · GoldCap", rows[6].subItem.text)
    assert.equal("50", rows[6].cells.cost.text)
    assert.equal("100", rows[6].cells.listed.text)
    assert.equal("2 still unsold", rows[6].cells.status.text)
    -- The nested "well" replaces the list's own zebra for a sub-row (a batch here), never for
    -- a position -- and exactly one of item/subItem/sectionLabel is visible per row, whichever
    -- widget this row's kind actually writes to.
    assert.is_false(rows[1].well.shown)
    assert.is_true(rows[1].cells.item.shown)
    assert.is_false(rows[1].subItem.shown)
    assert.is_false(rows[1].sectionLabel.shown)
    assert.is_true(rows[6].well.shown)
    assert.is_false(rows[6].cells.item.shown)
    assert.is_true(rows[6].subItem.shown)
    assert.is_false(rows[6].sectionLabel.shown)
    assert.is_true(rows[3].well.shown)
    assert.is_false(rows[3].cells.item.shown)
    assert.is_false(rows[3].subItem.shown)
    assert.is_true(rows[3].sectionLabel.shown)
    assert.matches("^ON THE AUCTION HOUSE", rows[3].sectionLabel.text)
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
    -- No mode words at all: the price IS the advice, and the sentences that
    -- used to wrap it pushed it clean out of the cell in game (2026-08-19).
    assert.equal("Post @ 199", rows[2].cells.status.text)
  end)

  -- The two annotations that survive the trim, because both change what the
  -- player should DO: a hold's one-word reason, and the below-cost warning.
  it("keeps a hold's short reason through the trim", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {},
        recommendation = { action = "hold", reason = "loss", rec = { unit = 149 } } }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 100, listedValue = 200, sources = {}, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("Hold (loss) @ 149", rows[2].cells.status.text)
  end)

  it("keeps the below-cost warning through the trim", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {},
        recommendation = { unit = 100, mode = "undercut", belowCost = true } }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 300, listedValue = 200, sources = {}, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("Post @ 100 · below cost", rows[2].cells.status.text)
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
    assert.equal("Post @ 199", rows[2].cells.status.text)
    assert.match("×2 listed at 200 each", rows[4].subItem.text)
    assert.equal("400", rows[4].cells.listed.text)
    assert.match("captured", rows[6].subItem.text)
    assert.match("mail%-confirmed", rows[7].subItem.text)
    assert.match("manual", rows[8].subItem.text)
    assert.match("unknown evidence", rows[9].subItem.text)
  end)

  it("renders a collapsed purchase run as one line with its count and date range", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", ownedLots = {}, batches = {
        { source = "goldcap", purchases = 2, acquiredAtFirst = 4, acquiredAtLast = 9,
          originalQty = 400, remainingQty = 350, unitCost = 198, totalCost = 79200, evidence = "captured" },
        -- A run bought inside one date stamp shows that date once, not "12 – 12".
        { source = "goldcap", purchases = 3, acquiredAtFirst = 12, acquiredAtLast = 12,
          originalQty = 30, remainingQty = 0, unitCost = 500, totalCost = 15000, evidence = "captured" },
      } }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 430, knownQty = 430, knownCost = 94200, listedValue = 0,
        sources = { goldcap = 430 }, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    local render = upvalue(GC.Sell.Attach, "renderRows")
    rows = upvalue(render, "rows")
    assert.equal("group", rows[3].kind)
    assert.matches("^WHAT YOU PAID", rows[3].sectionLabel.text)
    -- The count sits right after the quantity: the sub-row cell ellipsizes at narrow widths and
    -- the tail is the first thing lost, so trailing the count would hide exactly the fact the
    -- collapse exists to show. Headless there is no date(), so the raw stamps stand in for
    -- the formatted dates; the range separator is ASCII on purpose (the client font has no
    -- U+2192 -- it drew a tofu box in game -- so exotic punctuation is proven-glyphs only). The
    -- unit price no longer repeats here -- the COST/LISTED cells two columns over carry it.
    assert.match("×400 · 2 purchases · bought 4 %- 9 · GoldCap · captured", rows[4].subItem.text)
    assert.equal("198", rows[4].cells.cost.text)
    assert.equal("7g92s", rows[4].cells.listed.text)
    assert.equal("350 still unsold", rows[4].cells.status.text)
    assert.match("×30 · 3 purchases · bought 12 · GoldCap · captured", rows[5].subItem.text)
    assert.equal("all sold", rows[5].cells.status.text)
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
    assert.match("market 150 · fresh · age 3s", rows[2].subItem.text)
    assert.same({ 1, 1, 1, 1 }, rows[2].subItem.color)
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

    -- Ghost rows (no bags, no listings -- item 42 here) sink below listed ones now, so the
    -- row under test is found by item, not assumed to be first.
    local function positionRow(itemID)
      for _, row in ipairs(upvalue(render, "rows")) do
        if row.kind == "position" and row.position.itemID == itemID then return row end
      end
    end
    local unlisted = positionRow(42)
    assert.equal("150", unlisted.cells.market.text)
    assert.equal(1, #timers)
    -- Wakes when the quote actually expires. The Sell tab treats a quote as good
    -- for SELL_QUOTE_ACTION_AGE (45s), not the Sniper's 10s: a listing competes
    -- over hours, and a 10s window made Post unclickable because pricing the tab
    -- took longer than the quote lasted.
    assert.equal(46, timers[1].seconds)
    unlisted.scripts.OnClick(unlisted)
    local rows = upvalue(render, "rows")
    local freshDetail
    for _, row in ipairs(rows) do
      if row.kind == "detail" and row.position.itemID == 42 then freshDetail = row end
    end
    assert.match("market 150 · fresh · age 0s", freshDetail.subItem.text)
    assert.same({ 1, 1, 1, 1 }, freshDetail.subItem.color)

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
    assert.match("market 150 · stale · age 51s", staleDetail.subItem.text)
    assert.same({ .5, .5, .5, 1 }, staleDetail.subItem.color)

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

  -- renderRows used to have no visibility check at all: composePositions()+renderRows() run
  -- from GC.Sell.Refresh() regardless of which tab is active (bag counts and the tab badge
  -- must stay current either way), so a background Refresh() while the Deals tab was showing
  -- rebuilt every Sell row for nothing, and dragging the window's resize grip rebuilt it
  -- again on every pixel.
  it("[perf] defers a render while the Sell container is hidden, and catches up once GC.Sell.Show reveals it", function()
    local record = { calls = {} }
    local GC = load(620, record)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local container = upvalue(render, "container")
    container:Hide()
    set(render, "positions", {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 5, listedValue = 10, sources = {}, status = "LISTED" },
    })
    render()
    local rows = upvalue(render, "rows")
    assert.equal(0, #rows) -- nothing built while hidden

    local refreshes = 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1; render() end
    GC.Sell.Show()
    assert.is_true(container:IsShown())
    assert.equal(1, refreshes) -- Show()'s own Refresh() call is what flushes the deferred render
    rows = upvalue(render, "rows")
    assert.is_true(#rows > 0)
    assert.equal("commodity:42", rows[1].position.positionKey)
  end)

  -- OnSizeChanged fires once per pixel while the resize grip is dragged. Layout (the
  -- width-driven column drop) must stay immediate every event; only the row rebuild is
  -- coalesced to a single pass, once the size has settled.
  it("[perf] throttles the resize hook's row rebuild to the settled width, but keeps layout immediate", function()
    local timers = {}
    _G.C_Timer = { After = function(seconds, callback) timers[#timers + 1] = { seconds = seconds, callback = callback } end }
    local GC, root = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local container = upvalue(render, "container")
    container:Show()
    set(render, "positions", {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 5, listedValue = 10, sources = {}, status = "LISTED" },
    })
    local rows = upvalue(render, "rows")
    assert.equal(0, #rows) -- nothing rendered by Attach itself

    -- Simulate a drag: the grip fires OnSizeChanged once per pixel.
    for _, width in ipairs({ 700, 720, 740, 760 }) do
      root.scripts.OnSizeChanged(root, width)
    end
    local content = upvalue(render, "content")
    assert.equal(760 - 16, content.width) -- ROW_WIDTH = width - panelLeft - panelRightInset (8+8); tracked every event, immediately
    assert.equal(0, #rows) -- but no row rebuild has run yet -- it is still deferred
    assert.is_true(#timers >= 2)

    -- Every stale (superseded) resize callback is inert; only the last-scheduled one renders.
    for i = 1, #timers - 1 do timers[i].callback() end
    rows = upvalue(render, "rows")
    assert.equal(0, #rows)
    timers[#timers].callback()
    rows = upvalue(render, "rows")
    assert.is_true(#rows > 0)
    assert.equal("commodity:42", rows[1].position.positionKey)
  end)

  -- A mistaken "Set cost" entry used to have no way back out short of raw SavedVariables
  -- surgery. "What you paid" rows for a hand-entered batch now get a Remove affordance;
  -- goldcap/auction_house rows are evidence-backed and never do, matching Core/Acquisitions'
  -- own RemoveManual refusal.
  it("shows a remove button only on a manual 'What you paid' row", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {
        { source = "manual", ids = { "acq:1" }, unitCost = 100, totalCost = 100,
          originalQty = 1, remainingQty = 1, evidence = "manual" },
        { source = "goldcap", ids = { "acq:2" }, unitCost = 50, totalCost = 50,
          originalQty = 1, remainingQty = 1, evidence = "captured" },
      }, ownedLots = {} }
    end
    local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
      exposureQty = 2, knownQty = 2, knownCost = 150, listedValue = 0, sources = {} }
    local rows = topRows(GC, { p })
    rows[1].scripts.OnClick(rows[1])
    -- rows[2] is "detail", rows[3] the "What you paid" group heading, then one row per batch.
    local manualRow, goldcapRow = rows[4], rows[5]
    assert.equal("batch", manualRow.kind)
    assert.equal("manual", manualRow.batch.source)
    assert.is_true(manualRow.action.shown)
    assert.equal("Remove", manualRow.action.label)
    assert.equal("batch", goldcapRow.kind)
    assert.equal("goldcap", goldcapRow.batch.source)
    assert.is_false(goldcapRow.action.shown)
  end)

  -- The armed/disarm two-click shape onRepostClick already uses for a cancel: an explicit
  -- first-click label change, a second click within the window that actually acts.
  it("arms then confirms removal of a single manual batch and refreshes", function()
    local removed = {}
    local GC = load(620, { calls = {} })
    GC.Acquisitions.RemoveManual = function(id) removed[#removed + 1] = id; return true end
    local refreshes = 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {
        { source = "manual", ids = { "acq:1" }, unitCost = 100, totalCost = 100,
          originalQty = 1, remainingQty = 1, evidence = "manual" },
      }, ownedLots = {} }
    end
    local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
      exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, sources = {} }
    local rows = topRows(GC, { p })
    rows[1].scripts.OnClick(rows[1])
    local row = rows[4]
    assert.equal("Remove", row.action.label)
    row.action.scripts.OnClick()
    assert.equal("armed", row.removeStage)
    assert.equal("Remove?", row.action.label)
    assert.equal(0, #removed)
    assert.equal(0, refreshes)
    row.action.scripts.OnClick()
    assert.same({ "acq:1" }, removed)
    assert.equal(1, refreshes)
    assert.is_nil(row.removeStage)
    assert.equal("Remove", row.action.label)
  end)

  -- "What you paid" collapses adjacent identical purchases into one counted line
  -- (SellViewModel.Expansion); a manual run's Remove button has to take every batch behind it
  -- with it, not just the one the collapsed line happens to keep a reference to.
  it("removes every batch in a collapsed manual run on one confirm", function()
    local removed = {}
    local GC = load(620, { calls = {} })
    GC.Acquisitions.RemoveManual = function(id) removed[#removed + 1] = id; return true end
    local refreshes = 0
    GC.Sell.Refresh = function() refreshes = refreshes + 1 end
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {
        { source = "manual", ids = { "acq:1", "acq:2" }, purchases = 2, unitCost = 100,
          totalCost = 200, originalQty = 2, remainingQty = 2, evidence = "manual" },
      }, ownedLots = {} }
    end
    local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
      exposureQty = 2, knownQty = 2, knownCost = 200, listedValue = 0, sources = {} }
    local rows = topRows(GC, { p })
    rows[1].scripts.OnClick(rows[1])
    local row = rows[4]
    row.action.scripts.OnClick()
    row.action.scripts.OnClick()
    assert.same({ "acq:1", "acq:2" }, removed)
    assert.equal(1, refreshes)
  end)

  -- Expansion's collapse key guarantees every id in one run shares a source, so a mixed run
  -- cannot occur through the real collapse -- this stands in for that invariant breaking, to
  -- prove the button check itself (source == "manual"), not just today's caller.
  it("gives no button when a run's source is not manual", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {
        { source = "mixed", ids = { "acq:1", "acq:2" }, purchases = 2, unitCost = 100,
          totalCost = 200, originalQty = 2, remainingQty = 2, evidence = "unknown evidence" },
      }, ownedLots = {} }
    end
    local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
      exposureQty = 2, knownQty = 2, knownCost = 200, listedValue = 0, sources = {} }
    local rows = topRows(GC, { p })
    rows[1].scripts.OnClick(rows[1])
    assert.is_false(rows[4].action.shown)
  end)

  -- The empty-state panel is the only thing standing between "nothing rendered" and "the tab is
  -- broken" -- a swapped copy string, a dropped Hide(), or a flipped `#entries == 0` branch would
  -- all leave the row list silently blank, and nothing above this describe block would notice.
  describe("empty state", function()
    it("says nothing is in bags or listed when the default filter has no positions at all", function()
      local GC = load(620, { calls = {} })
      local _, container = topRows(GC, {})
      assert.is_true(container.emptyText:IsShown())
      assert.equal("Nothing to sell — no items in bags or listed", container.emptyText:GetText())
    end)

    it("says no items match this filter when a chip empties an otherwise non-empty list", function()
      local GC = load(620, { calls = {} })
      -- The real GC.SellViewModel.Filter narrows by mode; this fake normally ignores it
      -- entirely (returns `values` unchanged), so it is overridden here to reproduce the one
      -- behavior this test needs: a non-"all" mode that matches nothing.
      GC.SellViewModel.Filter = function(values, mode) return mode == "all" and values or {} end
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "positions", {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {} },
      })
      set(render, "filterMode", "listed")
      render()
      local container = upvalue(render, "container")
      assert.is_true(container.emptyText:IsShown())
      assert.equal("No items match this filter", container.emptyText:GetText())
    end)

    it("hides once a render produces at least one row", function()
      local GC = load(620, { calls = {} })
      local _, container = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {} },
      })
      assert.is_false(container.emptyText:IsShown())
    end)
  end)
end)
