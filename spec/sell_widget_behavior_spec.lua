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
    -- A position's detail rows move between the list and the side panel by re-parenting.
    function value:SetParent(to) self.parent = to end
    function value:SetSize(w, h) self.width, self.height = w, h end
    function value:SetWidth(w) self.width = w end
    function value:SetHeight(h) self.height = h end
    function value:SetText(text) self.text = text end
    function value:GetText() return self.text or "" end
    function value:SetLabel(text) self.label = text end
    function value:SetVariant(name) self.variant = name end
    function value:SetRing(c) self.ringColor = c or false end
    function value:SetScript(name, fn) self.scripts[name] = fn end
    function value:HookScript(name, fn) self.scripts[name] = fn end
    function value:Show() self.shown = true end
    function value:Hide() self.shown = false end
    function value:IsShown() return self.shown end
    function value:Enable() self.enabled = true end
    function value:Disable() self.enabled = false end
    function value:SetJustifyH() end
    function value:SetWordWrap(enabled) self.wordWrap = enabled end
    function value:SetMaxLines(lines) self.maxLines = lines end
    function value:SetTextColor(...) self.color = { ... } end
    function value:SetAutoFocus() end
    -- The price box commits on Enter and on focus loss, and both clear focus afterwards.
    function value:ClearFocus() self.focused = false end
    function value:SetFocus() self.focused = true end
    function value:HasFocus() return self.focused == true end
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
      color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = { .72, .71, .69 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
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
      -- Records what the real one does with its arguments: a caller that tints a sliced region
      -- any other way than SetVertexColor loses the art, and only the file name shows that.
      SlicedTexture = function(parent, layer, file, c, margin)
        local t = region("Texture", parent)
        t.layer = layer
        t:SetTexture(file); t:SetTextureSliceMargins(margin, margin, margin, margin)
        t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        return t
      end,
      -- The real one reads the owner's place on screen; the double lets a test plant the answer
      -- on the owner and checks the widget passes it through rather than assuming a side.
      TooltipAnchor = function(owner) return owner.tooltipAnchor or "ANCHOR_RIGHT" end,
      -- The real geometry (right of the window, or left when there's no room) is covered by
      -- theme_item_tooltip_outside_spec.lua against the real Theme.lua -- this double only has
      -- to open SOME tooltip so the row's OnEnter can go on to AddLine the rest of its content.
      ItemTooltipOutside = function(owner) GameTooltip:SetOwner(owner, "ANCHOR_RIGHT") end,
    }
    -- Loaded into its own table so borrowing Deck below cannot drag the rest of the real view
    -- model (SourceText, CostText, SummaryText) into a double these tests deliberately control.
    local realViewModel = helper.loadModule("UI/SellViewModel.lua")
    local GC = {
      Sell = {}, Theme = theme,
      QuoteCache = { Clear = function() end },
      SellViewModel = {
        Filter = function(values) return values end,
        -- Borrowed from the REAL module, never hand-written: Deck decides which rows this tab
        -- shows AT ALL, and a stand-in that returned its input would let every test in this
        -- file pass against a deck split that does not exist -- the same reason SellPositions
        -- is loaded for real just below. The rest of the double stays hand-written because
        -- these tests are about the widget, not about the view model's text.
        Deck = realViewModel.SellViewModel.Deck,
        LotSections = realViewModel.SellViewModel.LotSections,
        Order = realViewModel.SellViewModel.Order,
        -- Borrowed for the same reason Deck is: Settle decides whether a row MOVES between
        -- renders, and a stand-in that handed the list straight back would let every test here
        -- pass against an order that still jumps.
        Settle = realViewModel.SellViewModel.Settle,
        -- And for the same reason again: Standing is the arithmetic behind the line under a
        -- row's price, and a stand-in would let that line say anything.
        Standing = realViewModel.SellViewModel.Standing,
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

  -- `deck` is optional and defaults to the tab's own default ("post"). A fixture carrying only
  -- listedQty is a LIVE LOT, and live lots live on the listed deck -- passing "listed" for those
  -- is the test looking where the row actually is, not a workaround. Set through the same
  -- upvalue the deck buttons write, so a test can never select a deck the chrome cannot.
  local function topRows(GC, values, deck)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "positions", values)
    if deck then set(render, "filterMode", deck) end
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

  -- The action button lives in the far-right column, and its help (four paragraphs for Post)
  -- opened ANCHOR_RIGHT -- into space a screen-wide window does not have. The client clamped
  -- the tooltip back over the list, the header and the very button under the cursor. Which
  -- side has room is Theme.TooltipAnchor's call, from where the button sits on screen; the
  -- button's job is to ask it rather than assume.
  it("opens the action button's help on the side Theme.TooltipAnchor picks for it", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
        listedQty = 0, sources = {}, status = "UNLISTED" },
    })
    local action = rows[1].action
    action.helpKey = "Post"
    action.tooltipAnchor = "ANCHOR_BOTTOMLEFT"
    local anchor, shown = nil, false
    _G.GameTooltip = {
      SetOwner = function(_, owner, a) assert.equal(action, owner); anchor = a end,
      Show = function() shown = true end, Hide = function() end, AddLine = function() end,
    }
    action.scripts.OnEnter(action)
    assert.equal("ANCHOR_BOTTOMLEFT", anchor)
    assert.is_true(shown)
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
    assert.equal(38, rows[1].itemInset) -- a 28px icon and its gap
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
    set(render, "emptyAnswers", { [42] = { at = 70, answered = true } })
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
    set(render, "emptyAnswers", { [42] = { at = 70, answered = true } })
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
    set(render, "emptyAnswers", { [42] = { at = 0, answered = true } }) -- load()'s _G.time() returns 77 -- 77s old, past EMPTY_ANSWER_AGE (60)
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
    set(render, "emptyAnswers", { [42] = { at = 0, answered = true } })
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
      assert.equal("8500 |cff8f8d88@1g|r", rows[1].cells.profit.text)
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
      assert.equal("-1g15s |cff8f8d88@1g|r", rows[1].cells.profit.text)
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
      assert.equal("not priced — nothing on hand to sell", rows[2].drawerFacts.text)
      assert.same({ .5, .5, .5, 1 }, rows[2].drawerFacts.color)
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
      assert.equal("no live quote yet — pricing…", rows[2].drawerFacts.text)
      assert.same({ .5, .5, .5, 1 }, rows[2].drawerFacts.color)
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
      -- The price control moved into the drawer panel, widgets and commit path unchanged --
      -- only the row kind that hosts it.
      for _, row in ipairs(rows) do if row.kind == "drawer" then return row, rows, GC end end
      error("no drawer rendered")
    end

    it("prefills the box with the price Post would actually list at", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      assert.equal("YOUR PRICE", row.drawerPriceHead.text)
      assert.equal("43", row.priceBox.text) -- 430000 copper, in gold, as the box takes it
      assert.matches("GoldCap's", row.priceNote.text, 1, true)
      assert.matches("×5", row.priceNote.text, 1, true)
    end)

    -- A real commit starts in the box: the focus is what tells the row which position the
    -- typing belongs to, and a commit with no focus behind it is refused (pooled rows).
    local function typePrice(row, text)
      row.priceBox.scripts.OnEditFocusGained(row.priceBox)
      row.priceBox.focused = true
      row.priceBox.text = text
      row.priceBox.scripts.OnEnterPressed(row.priceBox)
    end

    -- Asserted through the box the seller looks at, not through the table behind it: what
    -- matters is that the number they typed is the number the row now shows and prices with.
    it("takes a price the seller types and says it is theirs now", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      -- Above the 40g break-even on purpose: a price under it gets the loss warning instead,
      -- which is its own test below.
      typePrice(row, "45")
      local after = priceRow(GC)
      assert.equal("45", after.priceBox.text)
      assert.matches("yours", after.priceNote.text, 1, true)
    end)

    -- Emptying the box is an answer, not a failure to give one.
    it("hands the decision back to GoldCap when the box is cleared", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      typePrice(row, "45")
      typePrice(priceRow(GC), "  ")
      local after = priceRow(GC)
      assert.equal("43", after.priceBox.text)
      assert.matches("GoldCap's", after.priceNote.text, 1, true)
    end)

    -- ClearFocus raises OnEditFocusLost, which is bound to the same commit -- so a commit
    -- re-enters itself once by construction. A loop inside the client on a path that spends
    -- gold is not something to leave to luck.
    it("does not re-enter itself when committing clears the focus", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      local clears = 0
      local realClear = row.priceBox.ClearFocus
      row.priceBox.ClearFocus = function(self)
        clears = clears + 1
        realClear(self)
        if clears < 5 then row.priceBox.scripts.OnEditFocusLost(row.priceBox) end
      end
      typePrice(row, "45")
      assert.equal(1, clears)
      assert.equal("45", priceRow(GC).priceBox.text)
    end)

    -- Reported in-game 2026-08-28: "из-за того, что делается постоянно refresh, цена
    -- сбивается до 40.3 хотя вводил другую". This tab re-renders on its own constantly -- the
    -- quote walk finishes an item, an owned-auction scan lands, a refresh ticks -- and the
    -- render stamped the box every time, so a price typed and not yet committed was wiped
    -- back to the recommendation before Enter could ever reach it.
    it("does not type over the seller when the list refreshes under them", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      row.priceBox.scripts.OnEditFocusGained(row.priceBox)
      row.priceBox.focused = true
      row.priceBox.text = "45"        -- typed, NOT committed

      local again = priceRow(GC)      -- the refresh the player did not ask for
      assert.equal("45", again.priceBox.text)

      -- And the commit that follows records what was actually typed, not what the render
      -- would have put back.
      again.priceBox.scripts.OnEnterPressed(again.priceBox)
      assert.equal("45", priceRow(GC).priceBox.text)
      assert.matches("yours", priceRow(GC).priceNote.text, 1, true)
    end)

    -- The other half of the same defect: rows are POOLED, so a refresh can hand the row --
    -- and the box holding the cursor -- to a different position. A price typed for one item
    -- must never be committed against another.
    it("gives up a half-typed price rather than moving it to another item", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      row.priceBox.scripts.OnEditFocusGained(row.priceBox)
      row.priceBox.focused = true
      row.priceBox.text = "45"

      -- Same pooled row, now rendering a different position.
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:99"] = true })
      topRows(GC, {
        { itemID = 99, itemName = "Other", positionKey = "commodity:99", coverage = "UNKNOWN",
          exposureQty = 1, knownQty = 0, knownCost = 0, listedValue = 0,
          bagQty = 1, listedQty = 0, sources = {}, postRecommendation = { unit = 700000 } },
      })
      assert.is_false(row.priceBox:HasFocus())
      assert.equal("70", row.priceBox.text)

      -- And nothing was recorded for either item.
      set(render, "expanded", { ["commodity:42"] = true })
      assert.equal("43", priceRow(GC).priceBox.text)
    end)

    -- Nothing is recorded, and the typo is left where the seller can see and fix it: the box
    -- keeps the cursor rather than silently reverting under them. Escape is the way out.
    it("refuses a price it cannot read rather than recording a nonsense one", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      typePrice(row, "not a price")
      assert.equal("not a price", row.priceBox.text)
      assert.is_true(row.priceBox:HasFocus())

      row.priceBox.scripts.OnEscapePressed(row.priceBox)
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
      assert.equal("42.05", fill(2)) -- MATCH: the cheapest ask that is not yours
      assert.equal("42.04", fill(3)) -- UNDERCUT: one silver under it
      assert.equal("50", fill(4))    -- MARKET: the imported market value
      assert.equal("40", fill(5))    -- COST: the break-even, 2000000 over 5 units

      -- No cost basis, no COST chip: the alternative is a chip that fills a cost the addon
      -- does not have.
      local bare = load(700, { calls = {} })
      local row2 = priceRow(bare, { coverage = "UNKNOWN", knownQty = 0, knownCost = 0 })
      assert.is_false(row2.priceChips[5].enabled)
      assert.is_true(row2.priceChips[2].enabled)
    end)

    -- The first chip is the way back: it carries no price, it clears the seller's own, and it
    -- is the lit one for as long as the price on screen is GoldCap's.
    it("hands the price back to GoldCap from the GOLDCAP chip, and lights the chip in force", function()
      local GC = load(700, { calls = {} })
      local row = priceRow(GC)
      assert.equal("GOLDCAP", row.priceChips[1].label)
      assert.equal("active", row.priceChips[1].variant)
      assert.equal("ghost", row.priceChips[2].variant)
      local theirs = row.priceBox.text
      row.priceChips[4].scripts.OnClick(row.priceChips[4]) -- MARKET
      row = priceRow(GC)
      assert.equal("50", row.priceBox.text)
      assert.equal("active", row.priceChips[4].variant)
      assert.equal("ghost", row.priceChips[1].variant)
      row.priceChips[1].scripts.OnClick(row.priceChips[1])
      row = priceRow(GC)
      assert.equal(theirs, row.priceBox.text)
      assert.equal("active", row.priceChips[1].variant)
    end)

    it("shows what the price fetches beside the box, by the row's own arithmetic", function()
      local GC = load(700, { calls = {} })
      local row, rows = priceRow(GC)
      assert.equal("YOU GET", row.priceNetHead.text)
      assert.equal(rows[1].cells.gross.text, row.priceNet.text)
      assert.matches(rows[1].grossNote.text, row.priceNetNote.text, 1, true)
      assert.matches("after the AH cut", row.priceNetNote.text, 1, true)
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

    -- UNDERCUT is a rung BELOW the cheapest competing ask, and a silver under an ask of a silver
    -- or less is zero or negative. Zero is truthy in Lua, so the chip enabled itself, stored a
    -- price of 0 as the seller's choice, and the box they had just filled came back empty.
    it("[S16] offers no UNDERCUT rung when there is nothing under the cheapest ask", function()
      local GC = load(700, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      GC.SellViewModel.Expansion = function()
        return { batches = {}, ownedLots = {}, note = "FIFO allocations",
          book = { rows = {}, levels = 1, totalUnits = 3, widest = 3, cheapestCompeting = 100 } }
      end
      local rows = topRows(GC, {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "UNKNOWN",
          exposureQty = 5, knownQty = 0, knownCost = 0, listedValue = 0, bagQty = 5,
          listedQty = 0, sources = {}, postRecommendation = { unit = 100 } },
      })
      local drawer
      for _, row in ipairs(rows) do if row.kind == "drawer" then drawer = row end end
      assert.is_true(drawer.priceChips[2].enabled) -- MATCH: one silver is a price
      assert.is_false(drawer.priceChips[3].enabled) -- UNDERCUT: zero is not
      assert.is_nil(drawer.priceChips[3].priceSource)
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
      levels = 4, totalUnits = 1062, truncated = false, widest = 620, ownUnits = 90,
      cheapestCompeting = 418800, yourUnit = 420400, yourRow = 2,
      rows = {
        { unit = 418800, units = 12, ownerUnits = 0, mine = false, cumulative = 12 },
        { unit = 420500, units = 340, ownerUnits = 0, mine = false, cumulative = 352 },
        { unit = 426000, units = 90, ownerUnits = 90, mine = true, cumulative = 442 },
      },
    }

    -- The heading and its hint are the drawer's own, not a group row: the whole point of the
    -- panel is that the book sits BESIDE the price it justifies instead of eight rows below it.
    it("heads the book with the price to actually beat, not the cheapest row on screen", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, BOOK), "drawer")
      assert.equal("THE BOOK", drawer.drawerBookHead.text)
      assert.matches("cheapest not yours", drawer.drawerHint.text, 1, true)
      -- How deep the book is follows where the price stands in it, under the levels: beside
      -- the heading there is room for the price to beat and nothing else.
      assert.matches("1062 units", drawer.drawerDepth.text, 1, true)
      assert.matches("4 prices", drawer.drawerDepth.text, 1, true)
      -- The colour key is no longer a sentence in the hint: each level that needs one says it
      -- in a word of its own (see the colouring test below).
      assert.is_nil(drawer.drawerHint.text:find("gold is", 1, true))
    end)

    it("prints each level with its own price and depth, and says where you would stand", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, BOOK), "drawer")
      assert.equal("12", drawer.bookLines[1].qty.text)
      assert.equal("340", drawer.bookLines[2].qty.text)
      assert.is_true(drawer.bookLines[1].qty.shown)
      assert.is_true(drawer.bookLines[1].bar.shown)
      -- Per-level cumulative depth is gone with the level rows -- the panel answers the same
      -- question once, for the price the seller is actually about to list at, rather than four
      -- times for prices they are not.
      assert.matches("stands 2 of 4", drawer.drawerStand.text)
      -- A book shorter than the panel leaves its spare lines put away, never blank-but-shown.
      assert.is_false(drawer.bookLines[4].qty.shown)
      assert.is_false(drawer.bookLines[4].bar.shown)
    end)

    -- Colour carries the two things a seller cannot work out from one recommended number.
    -- Deliberately not a diamond/arrow glyph: the bundled face has neither, and they drew as
    -- empty boxes in game.
    it("colours where your price lands and which levels are already yours", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, BOOK), "drawer")
      local GOLD, WATCH = GC.Theme.color.gold, GC.Theme.color.watch
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 1 }, drawer.bookLines[2].price.color)
      assert.same({ WATCH[1], WATCH[2], WATCH[3], 1 }, drawer.bookLines[3].price.color)
      -- A level that is neither is just a price, in the ordinary foreground.
      local FG = GC.Theme.color.fg
      assert.same({ FG[1], FG[2], FG[3], 1 }, drawer.bookLines[1].price.color)
      -- And in a word, with a wash behind the level: colour alone was a key nobody was given.
      -- No word beside a level -- a word needs a column, and the column cost the book its
      -- width. The line under the book is the key: gold like the landing, and naming the blue.
      assert.is_true(drawer.bookLines[2].wash.shown)
      assert.is_true(drawer.bookLines[3].wash.shown)
      assert.is_false(drawer.bookLines[1].wash.shown)
      assert.is_false(drawer.bookLines[2].tag.shown)
      -- The key to the blue: "yours ×N" in a cell of its own at the right of the line, so the
      -- words beside it can never push it off (final review I1).
      assert.equal("yours ×90", drawer.drawerOwn.text)
      assert.is_true(drawer.drawerOwn.shown)
      assert.is_nil(drawer.drawerStand.text:find("yours", 1, true))
    end)

    -- The depth bars are pills, as drawn: a sliced bar.png, track and fill. A sliced region is
    -- tinted through its vertices -- SetColorTexture on it throws the art away and paints the
    -- square block this replaced -- and may not be narrower than its two end caps.
    it("draws each level's depth as a rounded bar, tinted without losing its art", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, BOOK), "drawer")
      local GOLD, WATCH = GC.Theme.color.gold, GC.Theme.color.watch
      for index = 1, 3 do
        local bar = drawer.bookLines[index].bar
        assert.equal("bar.png", bar.track.texture)
        assert.equal("bar.png", bar.fill.texture)
        assert.is_nil(bar.track.colorTexture)
        assert.is_nil(bar.fill.colorTexture)
      end
      assert.same({ 1, 1, 1, 0.22 }, drawer.bookLines[1].bar.fill.vertexColor)
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 0.8 }, drawer.bookLines[2].bar.fill.vertexColor)
      assert.same({ WATCH[1], WATCH[2], WATCH[3], 0.8 }, drawer.bookLines[3].bar.fill.vertexColor)
      -- 12 units against a widest level of 340 is under six pixels of a 160px bar.
      local caps = drawer.bookLines[1].bar.fill.sliceMargins
      assert.is_true(drawer.bookLines[1].bar.fill.width >= caps[1] + caps[3])
    end)

    -- Rows are pooled and rebound to a different kind on every render, so the drawer's own
    -- widgets have to be put away by whichever kind takes the row next -- and it has more of
    -- them to put away than any other kind.
    it("puts every drawer widget away on a row that stops being a drawer", function()
      local GC = load(620, { calls = {} })
      -- The row OBJECT is captured before the second render, not looked up again after it:
      -- rows are pooled, and a pooled row that goes unused keeps the kind it last carried.
      local reused = nth(bookRows(GC, BOOK), "drawer")
      assert.is_true(reused.bookLines[1].qty.shown)
      assert.is_true(reused.drawerBookHead.shown)
      -- Collapse the expansion AND give the list a second position, so this pooled row is
      -- rebound to a "position" instead of merely dropped: a row that leaves the list is hidden
      -- by the engine along with its children, which would prove nothing about the reset.
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", {})
      set(render, "positions", {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 5, knownQty = 5, knownCost = 10, bagQty = 5, listedQty = 0, sources = {} },
        { itemID = 43, itemName = "Bar", positionKey = "commodity:43", coverage = "COMPLETE",
          exposureQty = 5, knownQty = 5, knownCost = 10, bagQty = 5, listedQty = 0, sources = {} },
      })
      -- The drawer's own button wears no outline; as a position's Post it gets the gold one.
      assert.is_false(reused.action.ringColor)
      render()
      local GOLD = GC.Theme.color.gold
      assert.equal("position", reused.kind)
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 0.45 }, reused.action.ringColor)
      assert.is_false(reused.bookLines[1].qty.shown)
      assert.is_false(reused.bookLines[1].bar.shown)
      assert.is_false(reused.drawerBookHead.shown)
      assert.is_false(reused.drawerPriceHead.shown)
      assert.is_false(reused.drawerHint.shown)
      assert.is_false(reused.drawerStand.shown)
      assert.is_false(reused.drawerFacts.shown)
    end)

    -- A commodity's book, as the view model now hands it over: the ladder around the seller's
    -- price (cheapest, a gap, the levels under it, the marker, the levels above), walls, and
    -- what stands ahead. See spec/sell_book_spec.lua for how the rows are chosen.
    local LADDER = {
      commodity = true, levels = 20, totalUnits = 9000, truncated = true, widest = 420,
      cheapestCompeting = 101000, yourUnit = 115500, yourRow = 6, ahead = 2321,
      hoursToReach = 6, pastRead = false,
      wallBelow = { unit = 115000, units = 420 }, wallAbove = { unit = 117000, units = 400 },
      rows = {
        { kind = "level", unit = 101000, units = 10, ownerUnits = 0, mine = false },
        { kind = "level", unit = 102000, units = 10, ownerUnits = 0, mine = false },
        { kind = "gap", units = 1100, prices = 11 },
        { kind = "level", unit = 114000, units = 10, ownerUnits = 0, mine = false },
        { kind = "level", unit = 115000, units = 420, ownerUnits = 0, mine = false, wall = true },
        { kind = "yours", unit = 115500, ahead = 2321 },
        { kind = "level", unit = 116000, units = 10, ownerUnits = 0, mine = false },
        { kind = "level", unit = 117000, units = 400, ownerUnits = 0, mine = false, wall = true },
      },
    }

    it("marks your own price at its place in the ladder, with what stands ahead of it", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, LADDER), "drawer")
      local marker = drawer.bookLines[6]
      local GOLD = GC.Theme.color.gold
      assert.equal("11g55s", marker.price.text)
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 1 }, marker.price.color)
      -- The gold price and the wash already say "your price": the words lead with the count, so a
      -- narrow panel or a long language cuts words, never the number (review M1).
      assert.equal("2.3k ahead", marker.note.text)
      assert.is_true(marker.note.shown)
      assert.is_false(marker.qty.shown)
      assert.is_false(marker.bar.shown)
      assert.is_true(marker.wash.shown)
      -- The levels around it are levels, with no note.
      assert.equal("10", drawer.bookLines[4].qty.text)
      assert.is_false(drawer.bookLines[4].note.shown)
    end)

    it("folds the skipped middle of the book into one line", function()
      local GC = load(620, { calls = {} })
      local gap = nth(bookRows(GC, LADDER), "drawer").bookLines[3]
      assert.equal("…", gap.price.text)
      assert.equal("1.1k units in 11 prices", gap.note.text)
      assert.is_false(gap.qty.shown)
      assert.is_false(gap.bar.shown)
    end)

    it("marks a wall with its own colour and a word, and names the walls around your price", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, LADDER), "drawer")
      local RED = GC.Theme.color.red
      local wall = drawer.bookLines[5]
      assert.equal("wall", wall.tag.text)
      assert.is_true(wall.tag.shown)
      assert.same({ RED[1], RED[2], RED[3], 0.8 }, wall.bar.fill.vertexColor)
      assert.is_false(drawer.bookLines[4].tag.shown)
      assert.matches("wall 420 at 11g50s -- price under it to sell first", drawer.drawerFacts.text, 1, true)
      assert.matches("wall 400 at 11g70s above you", drawer.drawerFacts.text, 1, true)

    end)

    it("says how long the queue ahead of your price takes at today's pace", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, LADDER), "drawer")
      assert.equal("~6h to reach you", drawer.drawerStand.text)
      -- Nothing of the player's in the book: no key to draw, and the words have the line.
      assert.is_false(drawer.drawerOwn.shown)
      assert.equal(drawer.drawerStand.points[2].relative, drawer)
    end)

    -- Two cells, the words first and "yours ×N" at the right edge, the words ending where the key
    -- begins: at 1.3 in German the one run-on line lost the count and the key (final review I1).
    -- The count is every unit of the player's the book read, not only the levels drawn (M6).
    it("keeps yours ×N in its own cell beside the words, counting every level read", function()
      local GC = load(620, { calls = {} })
      local book = {}
      for k, v in pairs(LADDER) do book[k] = v end
      book.ownUnits = 3000
      local drawer = nth(bookRows(GC, book), "drawer")
      assert.equal("~6h to reach you", drawer.drawerStand.text)
      assert.equal("yours ×3.0k", drawer.drawerOwn.text)
      assert.is_true(drawer.drawerOwn.shown)
      assert.equal(1, drawer.drawerOwn.maxLines)
      assert.equal(drawer.drawerOwn, drawer.drawerStand.points[2].relative)
      local WATCH = GC.Theme.color.watch
      assert.same({ WATCH[1], WATCH[2], WATCH[3], 1 }, drawer.drawerOwn.color)
    end)

    -- The word is measured where the client can: its tag, and the bar after it, are as wide as
    -- the word drawn, in any language at any scale (final review I2).
    it("sizes a wall's word to the word itself", function()
      local GC = load(620, { calls = {} })
      local drawer = nth(bookRows(GC, LADDER), "drawer")
      for _, line in ipairs(drawer.bookLines) do
        function line.tag:GetUnboundedStringWidth() return #(self.text or "") * 9.2 end
      end
      upvalue(GC.Sell.Attach, "renderRows")()
      drawer = nth(upvalue(upvalue(GC.Sell.Attach, "renderRows"), "rows"), "drawer")
      local wall = drawer.bookLines[5]
      assert.equal(40, wall.tag.width) -- ceil(36.8) + 3 of air
      assert.equal(40, wall.bar.fill.points[1].x)
    end)

    -- "clears in" is your own units after the queue ahead, from the book's same pace -- never the
    -- listed-lot outlook, which for bag stock left the queue out and said ~1h beside ~6h (I1).
    it("says clears in from the book's own pace, after the queue ahead of you", function()
      local GC = load(620, { calls = {} })
      local book = {}
      for k, v in pairs(LADDER) do book[k] = v end
      book.clearsHours = 6.4
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      GC.SellViewModel.Expansion = function()
        return { batches = {}, ownedLots = {}, note = "FIFO allocations", book = book, sold = 9867, days = 0.03,
          ahead = 2321 }
      end
      local drawer = nth(topRows(GC, { { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
        coverage = "COMPLETE", exposureQty = 5, knownQty = 5, knownCost = 10, listedValue = 0, bagQty = 5,
        listedQty = 0, sources = {} } }), "drawer")
      assert.matches("clears in ~6h", drawer.drawerFacts.text, 1, true)
      assert.is_nil(drawer.drawerFacts.text:find("clears in ~1h", 1, true))
      -- The walls come after the sales figure, never ahead of it: the two lines may cut a wall,
      -- not the pace the time under the book is measured by (review M2).
      local facts = drawer.drawerFacts.text
      assert.is_true(facts:find("sells", 1, true) < facts:find("wall", 1, true), facts)
      -- One count: with THE BOOK's marker drawn, the listed lot's own "N ahead of you" is not
      -- said beside a time that is about the post price (review N2).
      assert.is_nil(facts:find("ahead of you", 1, true), facts)
    end)

    -- "clears in" and a lot's "N ahead of you" go through the string layer like the rest of the
    -- line: a German panel read "~6 Std. bis du dran bist" beside English (review N8).
    it("says clears in in the panel's language", function()
      local GC = load(620, { calls = {} })
      local german = { ["clears in ~%dh"] = "weg in ~%d Std.", ["%d ahead of you"] = "%d vor dir" }
      GC.L = setmetatable({}, { __index = function(_, key) return german[key] or key end })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      GC.SellViewModel.Expansion = function()
        return { batches = {}, ownedLots = {}, note = "FIFO allocations", sold = 9867, days = 0.03, ahead = 12 }
      end
      local drawer = nth(topRows(GC, { { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
        coverage = "COMPLETE", exposureQty = 5, knownQty = 5, knownCost = 10, listedValue = 0, bagQty = 5,
        listedQty = 0, sources = {} } }), "drawer")
      assert.matches("weg in ~1 Std.", drawer.drawerFacts.text, 1, true)
      assert.matches("12 vor dir", drawer.drawerFacts.text, 1, true)
    end)

    -- The rest of the same foot: the market price, the quote's state and age, and the line said
    -- when there are no facts at all (review NM-D: "weg in ~1 Std." beside "fresh · age 12s").
    it("says the whole drawer foot in the panel's language", function()
      local GC = load(620, { calls = {} })
      local german = { ["market %s"] = "Markt %s", ["fresh"] = "aktuell", ["stale"] = "veraltet",
        ["age %ss"] = "vor %ss" }
      GC.L = setmetatable({}, { __index = function(_, key) return german[key] or key end })
      GC.SellViewModel.Expansion = function(position)
        return { note = "FIFO allocations", batches = {}, ownedLots = {},
          displayMarketUnit = position.displayMarketUnit, quoteAge = position.quoteAge,
          marketState = position.marketState, marketFresh = position.marketFresh,
          marketStale = position.marketStale }
      end
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      local drawer = nth(topRows(GC, { { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
        coverage = "COMPLETE", exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, sources = {},
        displayMarketUnit = 150, freshMarketUnit = 150, quoteAge = 3,
        marketState = "fresh", marketFresh = true, marketStale = false, status = "UNLISTED" } }), "drawer")
      assert.equal("Markt 150", drawer.drawerFacts.text)
      assert.equal("aktuell · vor 3s", drawer.drawerQuote.text)
    end)

    it("says the empty foot in the panel's language", function()
      local GC = load(620, { calls = {} })
      local german = { ["not priced — nothing on hand to sell"] = "kein Preis — nichts zum Verkaufen vorrätig",
        ["no live quote yet — pricing…"] = "noch kein Live-Kurs — Preis wird ermittelt…" }
      GC.L = setmetatable({}, { __index = function(_, key) return german[key] or key end })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "expanded", { ["commodity:42"] = true })
      local empty = nth(topRows(GC, { { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
        coverage = "PARTIAL", exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 0,
        bagQty = 0, listedQty = 0, sources = {} } }), "drawer")
      assert.equal("kein Preis — nichts zum Verkaufen vorrätig", empty.drawerFacts.text)
      local pricing = nth(topRows(GC, { { itemID = 42, itemName = "Ore", positionKey = "commodity:42",
        coverage = "PARTIAL", exposureQty = 5, knownQty = 3, knownCost = 10, listedValue = 0,
        bagQty = 3, listedQty = 0, sources = {} } }), "drawer")
      assert.equal("noch kein Live-Kurs — Preis wird ermittelt…", pricing.drawerFacts.text)
    end)

    it("says a price past the levels read has at least that many ahead, and no time", function()
      local GC = load(620, { calls = {} })
      local past = {}
      for k, v in pairs(LADDER) do past[k] = v end
      past.pastRead, past.levels, past.totalUnits, past.hoursToReach, past.ahead = true, 100, 5605, nil, 5100
      past.rows = { { kind = "level", unit = 101000, units = 10, ownerUnits = 0, mine = false },
        { kind = "yours", unit = 999999, ahead = 5100, pastRead = true } }
      past.yourRow = 2
      local drawer = nth(bookRows(GC, past), "drawer")
      assert.equal("5.1k+ ahead", drawer.bookLines[2].note.text)
      -- One number: the marker's, which leaves the player's own units out (review M4).
      assert.equal("5.1k+, 100 prices read", drawer.drawerStand.text)
      assert.is_nil(drawer.drawerStand.text:find("to reach you", 1, true))
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

  -- The column sets got SHORTER when they got split by deck, and that is what finally bought
  -- the room: four columns whose translated headings ran into one another on the row ("РИНОК /
  -- ШТ ПРИБУТОК / ШТ ЩО РОБИТИ", seen in game) became three whose headings are one word each.
  -- Nothing is shed at any width this addon supports -- the shed lists exist for a window
  -- narrower than the resize floor, not for the ordinary case.
  it("carries its whole deck at every supported width", function()
    local record = { calls = {} }
    -- 520 is the content width at the 640px resize FLOOR, the narrowest a player can get to.
    for _, width in ipairs({ 520, 600, 666, 1100 }) do
      local GC = load(width, record)
      local _, container = topRows(GC, {})
      local header
      for _, child in ipairs(container.children) do if child.cells then header = child break end end
      assert.is_true(header.cells.gross.shown, ("gross hidden at %d"):format(width))
      assert.is_true(header.cells.price.shown, ("price hidden at %d"):format(width))
      -- MARGIN is the line under YOU GET now, not a column of its own.
      assert.is_nil(header.cells.margin)
      -- The four the drawer took over are off the row on this deck, at every width.
      assert.is_false(header.cells.cost.shown)
      assert.is_false(header.cells.market.shown)
      assert.is_false(header.cells.profit.shown)
      assert.is_false(header.cells.status.shown)
    end

    local GC = load(600, record)
    local _, container = topRows(GC, {})
    local header
    for _, child in ipairs(container.children) do if child.cells then header = child break end end
    assert.is_nil(header.cells.queue)
    -- Right to left: the button, what the stack fetches, the price it fetches it at, the name.
    assert.is_nil(header.cells.expand)
    assert.equal(header, header.cells.action.points[1].relative)
    assert.equal(header.cells.action, header.cells.gross.points[1].relative)
    assert.equal(header.cells.gross, header.cells.price.points[1].relative)
    assert.equal(header.cells.price, header.cells.item.points[2].relative)

    -- The other deck carries a different set AND different words for one of the same columns:
    -- MARKET / UNIT is "the cheapest ask that is not mine" while you are choosing a price, and
    -- "who is standing under my lot" once it is posted.
    local listedDeck = load(600, record)
    local _, listedContainer = topRows(listedDeck, {}, "listed")
    local listedHeader
    for _, child in ipairs(listedContainer.children) do if child.cells then listedHeader = child break end end
    -- "Who is under me" is the line under YOUR PRICE on this deck, in units; the column that
    -- carried a bare price under that heading is gone from it.
    assert.is_true(listedHeader.cells.listed.shown)
    assert.is_true(listedHeader.cells.price.shown)
    assert.is_false(listedHeader.cells.market.shown)
    assert.is_false(listedHeader.cells.gross.shown)
    assert.equal("YOUR PRICE", listedHeader.cells.price.text)
    assert.equal("PRICE / UNIT", header.cells.price.text)
  end)

  -- The complaint this answers, in the owner's words: "список постоянно прыгает, когда
  -- обновляется, трудно работать вначале". The pricing walk answers one item at a time, and
  -- until now every answer re-ranked a row out from under the cursor.
  it("does not move a row when a background render lands a price on it", function()
    local GC = load(700, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local slow = { itemID = 42, itemName = "Slow", positionKey = "commodity:42",
      coverage = "COMPLETE", exposureQty = 1, knownQty = 1, knownCost = 10,
      bagQty = 10, listedQty = 0, sources = {} }
    local priced = { itemID = 43, itemName = "Priced", positionKey = "commodity:43",
      coverage = "COMPLETE", exposureQty = 1, knownQty = 1, knownCost = 10,
      bagQty = 10, listedQty = 0, sources = {}, freshMarketUnit = 500 }
    set(render, "positions", { slow, priced })
    render()

    local function order()
      local out = {}
      for _, row in ipairs(upvalue(render, "rows")) do
        if row.IsShown and row:IsShown() and row.kind == "position" then
          out[#out + 1] = row.position.itemID
        end
      end
      return out
    end
    -- Priced first: that is the order the list settles on.
    assert.same({ 43, 42 }, order())

    -- The walk answers for the other one, and it is worth more. Order() alone would now put it
    -- first -- which is precisely the jump.
    slow.freshMarketUnit = 9000
    render()
    assert.same({ 43, 42 }, order())

    -- A stack looted mid-session lands at the BOTTOM rather than shouldering in above rows the
    -- player is working down, however valuable it is.
    local looted = { itemID = 44, itemName = "Looted", positionKey = "commodity:44",
      coverage = "COMPLETE", exposureQty = 1, knownQty = 1, knownCost = 10,
      bagQty = 10, listedQty = 0, sources = {}, freshMarketUnit = 99999 }
    set(render, "positions", { slow, priced, looted })
    render()
    assert.same({ 43, 42, 44 }, order())
  end)

  it("keeps every fixed-width Sell cell on one line", function()
    local GC = load(620, { calls = {} })
    local rows, container = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 1, knownQty = 1, knownCost = 5, listedValue = 168898, sources = {}, status = "LISTED" },
    })
    local header
    for _, child in ipairs(container.children) do if child.cells then header = child break end end
    for _, key in ipairs({ "cost", "listed", "market", "profit", "status" }) do
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
    }, "listed")
    -- MY LOTS opens on a section heading: rows[1] is it, rows[2] the position.
    assert.equal("section", rows[1].kind)
    assert.equal("Set cost", rows[2].action.label)
    assert.equal("Cost unknown for 2 of 5", rows[2].cells.status.text)
    assert.equal("CENTER", rows[2].action.points[1].point)
    assert.equal(rows[2].cells.action, rows[2].action.points[1].relative)
    assert.equal("CENTER", rows[2].action.points[1].relativePoint)
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
    assert.equal("badge", container.filterButtons.ready.rounded)
    assert.equal("badge", container.filterButtons.nocost.rounded)
    -- The deck switch is a plaque like the other primary controls, not a badge like the chips:
    -- it selects the JOB, the chips only narrow it.
    assert.equal("plaque", container.deckButtons.post.rounded)
    assert.equal("plaque", container.deckButtons.listed.rounded)
    assert.equal("badge", rows[1].action.rounded)
  end)

  it("uses the header's ordered cell chain for real rows and sizes expansion scroll content", function()
    local function assertRow(width)
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
      -- The posting deck's own three, at every width: what the stack fetches, at what price,
      -- and how that compares with what it cost. What you paid is on the stock line under the
      -- name now -- it used to be a column that got dropped before the window even left its
      -- default size.
      assert.is_true(row.cells.gross.shown)
      assert.is_true(row.cells.price.shown)
      -- The margin rides under YOU GET and the queue standing under the price, each on the
      -- row's second line, so neither costs a column.
      assert.is_nil(row.cells.margin)
      assert.is_true(row.grossNote.shown)
      assert.is_true(row.priceStand.shown)
      assert.is_false(row.cells.cost.shown)
      assert.is_false(row.cells.status.shown)
      assert.is_nil(row.cells.queue)
      assert.equal(row, row.cells.action.points[1].relative)
      -- Each shown column anchors to the one on its right, right to left.
      local chain = { "price", "gross", "action" }
      for i = 1, #chain - 1 do
        assert.equal(row.cells[chain[i + 1]], row.cells[chain[i]].points[1].relative,
          chain[i] .. " does not anchor to " .. chain[i + 1])
      end
      assert.equal(row.cells.price, row.cells.item.points[2].relative)
      -- A position's two figures sit in the upper half, their second lines in the lower one.
      -- Offsets are relative to the neighbour a cell hangs off, so a lifted neighbour must not
      -- lift it a second time: YOU GET rises 10 off the button, the price 0 off YOU GET.
      assert.equal(10, row.cells.gross.points[1].y)
      assert.equal(0, row.cells.price.points[1].y)
      assert.equal(0, row.cells.item.points[2].y)
      assert.equal(-20, row.itemStock.points[2].y)
      -- A position is 44px tall whatever the list's slot pitch, with a button to match.
      assert.equal(44, row.height)
      assert.equal(26, row.action.height)
      assert.equal(row.cells.price, row.priceStand.points[1].relative)
      assert.equal(row.cells.gross, row.grossNote.points[1].relative)
      assert.equal(header, header.cells.action.points[1].relative)
      assert.equal(0, header.cells.price.points[1].y)
      rows[1].scripts.OnClick(rows[1])
      local render = upvalue(GC.Sell.Attach, "renderRows")
      local content = upvalue(render, "content")
      local detailContent = upvalue(render, "detailContent")
      -- An open position's detail is drawn in the side panel. From 880 up the panel has a
      -- column of its own and the list gives up the panel's width and the gap; under that it
      -- lies over the list as a sheet and the list keeps every pixel.
      assert.equal(width >= 880 and width - 340 - 28 or width, content.width)
      assert.is_true(container.inspector.shown)
      -- The list does not grow by a single row when a position opens -- that is the point.
      assert.equal(44, content.height)
      -- Eleven slots in the panel: a seven-slot head (this position has nothing in the bags, so
      -- no price control, and no book, so no room kept for its levels), the auction-house
      -- heading, its lot, the purchase heading and its batch. A scroll child sized by entry
      -- COUNT would clip the head by six rows' worth.
      assert.equal(11 * 24, detailContent.height)
      for index = 2, 6 do assert.equal(detailContent, rows[index].parent, "row " .. index) end
      assert.equal(content, rows[1].parent)
      assert.equal("drawer", rows[2].kind)
      assert.equal("group", rows[3].kind)
      assert.matches("^ON THE AUCTION HOUSE", rows[3].sectionLabel.text)
      assert.equal("lot", rows[4].kind)
      assert.equal("group", rows[5].kind)
      assert.matches("^WHAT YOU PAID", rows[5].sectionLabel.text)
      assert.equal("batch", rows[6].kind)
    end
    -- Same three columns at all three widths: the deck's set is short enough that the window
    -- never has to give one of them up.
    assertRow(1100)
    assertRow(620)
    assertRow(600)
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
    }, "listed")
    rows[2].action.scripts.OnClick() -- rows[1] is the deck's section heading
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
    GC.SellViewModel.Deck = function(values, deck)
      if deck == "listed" then return { values[2] } end
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

    -- Both positions open at once. A click opens one and shuts the rest, so the pair is set
    -- straight on the state a click writes: what this test needs is the SAME pooled row
    -- carrying a lot before the deck change and a different lot after it.
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local expanded = upvalue(render, "expanded")
    expanded["commodity:42"], expanded["commodity:43"] = true, true
    render()
    -- rows[3] is the "On the Auction House" group heading now; the lot follows it.
    local firstLotRow = rows[4]
    assert.equal(7, firstLotRow.lot.auctionID)
    local staleClick = firstLotRow.action.scripts.OnClick
    firstLotRow.action.scripts.OnClick()
    assert.equal("armed", firstLotRow.repostStage)
    assert.equal(0, cancels)

    -- By id, never by label: the deck button's text carries a live count ("MY LOTS 2"), so
    -- matching on it would break the moment the fixture changes size.
    container.deckButtons.listed.scripts.OnClick()
    -- The deck change cannot repoint this pooled row at auction 8 while the row
    -- is armed on auction 7 -- which is the hazard the old behaviour answered by
    -- cancelling the arm. Holding the render answers it at the source: the row
    -- never moves, so nothing can carry the arm to a different auction.
    assert.equal(7, firstLotRow.lot.auctionID)
    assert.equal("armed", firstLotRow.repostStage)

    GC.Sell.Refresh = function() end -- see above: this is about the disarm
    GC.Sell.OnPostError() -- disarms, and flushes the render the filter asked for
    assert.equal(8, firstLotRow.lot.auctionID)
    assert.is_nil(firstLotRow.repostStage)
    assert.equal("Cancel lot", firstLotRow.action.label)
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
      -- listedQty makes this one a LIVE LOT, so the post deck under test excludes it and the
      -- summary below is over a single position -- the narrowing the removed "GC" provenance
      -- chip used to do by hand.
      { itemID = 7, itemName = "Other", positionKey = "commodity:7", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 30, listedValue = 50, listedQty = 1,
        sources = { auction_house = 1 }, status = "LISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    local render = upvalue(GC.Sell.Attach, "renderRows")
    rows = upvalue(render, "rows")
    assert.equal("drawer", rows[2].kind)
    -- Plain-language detail line: market state, competition, velocity and time to clear. It no
    -- longer opens by naming the allocation rule, which told a seller nothing.
    -- Split the way it is read: the queue and the velocity on the left, the quote's age right.
    assert.equal("3 ahead of you · sells 4/day · clears in ~1d", rows[2].drawerFacts.text)
    assert.equal("quote 7s ago", rows[2].drawerQuote.text)
    assert.equal("|cffff0000Repost|r @ 149", rows[2].subItem.text) -- the verdict's word in the verdict's colour
    -- rows[3] is the listings heading, rows[4] the lot, rows[5] the purchases heading.
    assert.equal("group", rows[3].kind)
    assert.equal("400", rows[4].cells.listed.text)
    -- "»", not "→": U+2192 is missing from the client font and rendered as a tofu box.
    assert.equal("» needs price", rows[4].cells.market.text)
    assert.equal("group", rows[5].kind)
    -- No epoch, no allocator counters: how many, when, at what price, from where. The unit
    -- price no longer repeats -- the COST cell two columns over already carries it.
    -- Four columns in the panel: how many, what each cost, where from and when, on what
    -- evidence. The whole sentence -- with what is left of the run -- is the row's hover.
    assert.equal("×5", rows[6].subItem.text)
    -- This fixture's evidence is not the ordinary kind, so it gets the room and the source
    -- steps back to the hover: the middle column is the date alone.
    assert.is_nil(rows[6].itemStock.text:find("GoldCap", 1, true))
    assert.is_true(rows[6].itemStock.shown)
    assert.equal("Auction 9", rows[6].sectionHint.text)
    assert.is_true(rows[6].sectionHint.shown)
    assert.is_true(rows[6].cells.cost.shown)
    assert.match("^×5 · bought .+ · GoldCap · Auction 9 · 2 still unsold$", rows[6].groupHint)
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
    -- A sub-row sits on the detail panel's own surface now, so it wears neither the list's
    -- zebra nor the nested well that used to bracket it to the row above.
    assert.is_false(rows[6].well.shown)
    assert.is_false(rows[6].zebra.shown)
    assert.is_false(rows[6].cells.item.shown)
    assert.is_true(rows[6].subItem.shown)
    assert.is_false(rows[6].sectionLabel.shown)
    assert.is_false(rows[3].well.shown)
    assert.is_false(rows[3].cells.item.shown)
    assert.is_false(rows[3].subItem.shown)
    assert.is_true(rows[3].sectionLabel.shown)
    assert.matches("^ON THE AUCTION HOUSE", rows[3].sectionLabel.text)
    assert.equal("100", container.summary.cost.text)
    assert.equal("400", container.summary.listed.text)
    assert.equal("-5", container.summary.profit.text)
    assert.equal("position", rows[1].kind)
    assert.equal("drawer", rows[2].kind)
  end)

  -- Post charges postRecommendation.unit, floor/queue/overcut raises included -- not the raw
  -- cheapest ask (see the "Say what Post will charge before it is clicked" comment in
  -- SellFrame.lua). The sub-row cell has to name that same price, or it is the "two different
  -- numbers" defect the queue-at-exit raise comment in Core/SellPositions.lua describes.
  it("shows the overcut-raised unit on a bag-stock sub-row, not the raw cheapest ask", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {} }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 5,
        knownQty = 5, knownCost = 500, listedValue = 0, bagQty = 5, listedQty = 0, sources = { goldcap = 5 },
        status = "UNLISTED", displayMarketUnit = 9900, freshMarketUnit = 9900,
        postRecommendation = { unit = 11500, mode = "overcut", ahead = 12 } },
    })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "liveBagState",
      function() return { bag = 0, slot = 1, stackQty = 3, exactQty = 3, itemID = 42, positionKey = "commodity:42" } end)
    rows[1].scripts.OnClick(rows[1])
    rows = upvalue(render, "rows")
    -- rows[3] is the "ON THE AUCTION HOUSE" heading, rows[4] the bag-stock sub-row -- there
    -- because one click lists three of the five, which the panel's heading does not say.
    assert.equal("» 1g15s", rows[4].cells.market.text)
  end)

  it("falls back to the raw cheapest ask on a bag-stock sub-row when there is no recommendation", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {} }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 5,
        knownQty = 5, knownCost = 500, listedValue = 0, bagQty = 5, listedQty = 0, sources = { goldcap = 5 },
        status = "UNLISTED", displayMarketUnit = 9900, freshMarketUnit = 9900 },
    })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "liveBagState",
      function() return { bag = 0, slot = 1, stackQty = 3, exactQty = 3, itemID = 42, positionKey = "commodity:42" } end)
    rows[1].scripts.OnClick(rows[1])
    rows = upvalue(render, "rows")
    assert.equal("» 9900", rows[4].cells.market.text)
  end)

  -- Same "two different numbers" defect, the other sub-row. Repost itself only cancels --
  -- BuildRepostPlan prices at exactly the fresh quote and must keep doing so (its confirm guard
  -- compares against that quote). The cell beside the button is a DISPLAY of what BuildPostPlan
  -- will list at once the units are back in bags, so it shows the recommendation's unit, not
  -- the raw fresh quote.
  it("shows the overcut-raised unit on a listed lot's repost sub-row, not the raw quote", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {},
        ownedLots = { { auctionID = 9, quantity = 2, unitPrice = 200 } } }
    end
    -- listedQty makes this a LIVE LOT, so it needs the "listed" deck the same way the earlier
    -- "listedQty makes this one a LIVE LOT" fixture above does.
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 2,
        knownQty = 2, knownCost = 100, listedValue = 400, listedQty = 2, sources = { goldcap = 2 },
        status = "LISTED", displayMarketUnit = 9900, freshMarketUnit = 9900,
        recommendation = { action = "repost", rec = { unit = 11500, mode = "overcut", ahead = 12 } } },
    }, "listed")
    rows[2].scripts.OnClick(rows[2])
    local render = upvalue(GC.Sell.Attach, "renderRows")
    rows = upvalue(render, "rows")
    -- rows[1] the deck's section heading, rows[2] the position, rows[3] "YOUR LOTS", rows[4] the lot.
    assert.equal("» 1g15s", rows[4].cells.market.text)
  end)

  it("renders a direct RecommendPost decision with its exact unit and mode", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {},
        recommendation = { unit = 199, mode = "match", belowCost = false } }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 100, listedValue = 200, sources = {}, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    -- No mode words at all: the price IS the advice, and the sentences that
    -- used to wrap it pushed it clean out of the cell in game (2026-08-19).
    assert.equal("Post @ 199", rows[2].subItem.text)
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
    -- The verdict is the word the panel is read for, so it wears the verdict's colour -- green
    -- for a hold -- and the figures after it stay in the sentence's own.
    assert.equal("|cff00ff00Hold|r (loss) @ 149", rows[2].subItem.text)
  end)

  it("keeps the below-cost warning through the trim", function()
    local GC = load(620, { calls = {} })
    GC.SellViewModel.Expansion = function()
      return { note = "FIFO allocations", batches = {}, ownedLots = {},
        recommendation = { unit = 100, mode = "match", belowCost = true } }
    end
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 1,
        knownQty = 1, knownCost = 300, listedValue = 200, sources = {}, status = "UNLISTED" },
    })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("Post @ 100 · below cost", rows[2].subItem.text)
  end)

  it("[I2] renders semantic evidence, owned unit and total, and breakeven", function()
    local GC = load(620, { calls = {} })
    helper.loadModule("UI/SellViewModel.lua", GC)
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 2, trackedQty = 2, listedQty = 2, knownQty = 2, knownCost = 100,
        listedValue = 400, sources = { goldcap = 1, auction_house = 1 }, status = "LISTED",
        recommendation = { unit = 199, mode = "match", breakeven = 106 },
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
    }, "listed")
    rows[2].scripts.OnClick(rows[2])
    -- On MY LOTS the lots open the panel and the advice and book follow: rows[1] the deck's
    -- section heading, rows[2] the position, rows[3] "YOUR LOTS", rows[4] the lot, rows[5] the
    -- head, rows[6] "WHAT YOU PAID", rows[7..10] the four batches.
    assert.equal("YOUR LOTS", rows[3].sectionLabel.text)
    assert.match("×2 listed at 200 each", rows[4].subItem.text)
    assert.equal("400", rows[4].cells.listed.text)
    assert.equal("Post @ 199", rows[5].subItem.text)
    -- The evidence word is a purchase's last column in the panel.
    assert.equal("captured", rows[7].sectionHint.text)
    -- The ordinary evidence for a purchase is not drawn: it is on the hover, with the rest.
    assert.equal("", rows[8].sectionHint.text)
    assert.match("mail%-confirmed", rows[8].groupHint)
    assert.match("^Auction House, ", rows[8].itemStock.text) -- ...and the source has its room back
    assert.equal("manual", rows[9].sectionHint.text)
    assert.equal("unknown evidence", rows[10].sectionHint.text)
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
    assert.equal("×400", rows[4].subItem.text)
    assert.equal("4 - 9", rows[4].itemStock.text) -- "captured" is news for a purchase: it gets the room
    assert.equal("captured", rows[4].sectionHint.text)
    assert.equal("×400 · 2 purchases · bought 4 - 9 · GoldCap · captured · 350 still unsold", rows[4].groupHint)
    assert.equal("198", rows[4].cells.cost.text)
    assert.equal("7g92s", rows[4].cells.listed.text)
    assert.equal("350 still unsold", rows[4].cells.status.text)
    assert.equal("×30", rows[5].subItem.text)
    assert.match("^×30 · 3 purchases · bought 12 · GoldCap · captured · all sold$", rows[5].groupHint)
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
    assert.equal("", rows[2].subItem.text)
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
    assert.equal("drawer", rows[2].kind)
    -- No book here, so the market price is said in words; the quote's state and age sit at
    -- the right end of the same line, dim while it is fresh.
    assert.equal("market 150", rows[2].drawerFacts.text)
    assert.equal("fresh · age 3s", rows[2].drawerQuote.text)
    assert.same({ .5, .5, .5, 1 }, rows[2].drawerQuote.color)
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
      if row.kind == "drawer" and row.position.itemID == 42 then freshDetail = row end
    end
    assert.equal("market 150", freshDetail.drawerFacts.text)
    assert.equal("fresh · age 0s", freshDetail.drawerQuote.text)
    assert.same({ .5, .5, .5, 1 }, freshDetail.drawerQuote.color)

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
    local staleDetail
    for _, row in ipairs(rows) do
      if row.kind == "drawer" and row.position.itemID == 42 then staleDetail = row end
    end
    -- A stale quote is the one thing at the foot of the book worth a second look: red.
    assert.equal("stale · age 51s", staleDetail.drawerQuote.text)
    assert.same({ 1, 0, 0, 1 }, staleDetail.drawerQuote.color)

    -- Item 42 is unlisted and item 43 is a live lot, so they sit on opposite decks: everything
    -- above is the post deck's half of this test, everything below is the listed deck's. One
    -- list holding both halves of the job is exactly what the deck split ended.
    set(render, "filterMode", "listed")
    render()
    rows = upvalue(render, "rows")
    local listedPosition
    for _, row in ipairs(rows) do
      if row.kind == "position" and row.position.itemID == 43 then listedPosition = row end
    end
    assert.equal(190, listedPosition.position.projectedNet)
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
    -- Asked as a click (refresh.priority), with no tab-wide queue behind it.
    local walk = upvalue(GC.Sell.OnThrottleReady, "refresh")
    assert.same({ 43 }, walk.priority)
    assert.same({}, walk.queue)
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
      assert.equal("Nothing in your bags to list", container.emptyText:GetText())
    end)

    -- Three emptinesses, three different next moves. The copy this replaced said "No items
    -- match this filter" for all of them, which told a player nothing about what to do.
    it("names the CHIP that emptied the deck, not just that it is empty", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      -- Bag stock the Auction House has not answered on yet: on the deck, but not READY.
      set(render, "positions", {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {} },
      })
      local container = upvalue(render, "container")
      container.filterButtons.ready.scripts.OnClick()
      assert.is_true(container.emptyText:IsShown())
      assert.equal("Nothing is priced yet - the Auction House is still answering",
        container.emptyText:GetText())

      -- Same deck, same stock, the other chip: this one is about the cost basis, and saying so
      -- is what stops a player hunting for stock that is right there.
      container.filterButtons.ready.scripts.OnClick()
      container.filterButtons.nocost.scripts.OnClick()
      assert.equal("Every position in your bags already has a cost on record",
        container.emptyText:GetText())
    end)

    it("says the OTHER deck holds everything rather than claiming nothing exists", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "positions", {
        { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
          exposureQty = 1, knownQty = 1, knownCost = 100, listedValue = 0, bagQty = 1,
          listedQty = 0, sources = {} },
      })
      local container = upvalue(render, "container")
      container.deckButtons.listed.scripts.OnClick()
      assert.is_true(container.emptyText:IsShown())
      assert.equal("No live auctions on this character", container.emptyText:GetText())
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

  -- YOU GET answers "what does this row fetch if I click Post". A normal item posts ONE stack
  -- (PostItem pins a single ItemLocation), so counting the bag SUM quoted a figure four fifths
  -- of which would still be sitting in the bags after the click.
  it("[S11] counts YOU GET over what one click lists, not over the whole bag total", function()
    local GC = load(620, { calls = {} })
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Blade", positionKey = "item:42:100:0:0", coverage = "UNKNOWN",
        exposureQty = 0, knownQty = 0, knownCost = 0, listedValue = 0, bagQty = 100,
        postableQty = 20, listedQty = 0, sources = {}, status = "UNLISTED",
        postRecommendation = { unit = 10000 } },
    })
    assert.equal("1g", rows[1].cells.price.text)
    assert.equal("20g", rows[1].cells.gross.text)
  end)

  -- "queue" and "cancelqueue" are transient FOCUS states, not decks, and nothing ever cleared
  -- them: one press of the POST control left the tab rendering the queue's own order for the
  -- rest of the session, with these chips lighting up over a list they could not narrow.
  it("[S14] a filter chip takes the tab back to the deck it belongs to", function()
    local GC = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "filterMode", "queue")
    local container = upvalue(render, "container")
    local chip = container.filterButtons.ready
    chip.scripts.OnClick(chip)
    assert.equal("post", upvalue(render, "filterMode"))
    set(render, "filterMode", "cancelqueue")
    -- The chips are disabled on the listed deck, so this is the cancel queue's own restore.
    chip.scripts.OnClick(chip)
    assert.equal("listed", upvalue(render, "filterMode"))
  end)

  -- The row after the redesign: two figures, each with a second line that answers before the
  -- position is opened, and a tag on the stock line only when something is off.
  describe("the row's second lines and tag", function()
    local BOOK = {
      { unitPrice = 179000, quantity = 35 }, { unitPrice = 179500, quantity = 85 },
      { unitPrice = 181500, quantity = 240 }, { unitPrice = 184000, quantity = 410 },
    }
    local function stock(over)
      local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 40, knownQty = 40, knownCost = 4000000, bagQty = 40, listedQty = 0, sources = {},
        freshMarketUnit = 179000, displayMarketUnit = 179000, levels = BOOK,
        postRecommendation = { unit = 181500 } }
      for key, value in pairs(over or {}) do p[key] = value end
      return p
    end

    -- A price about to be posted joins the tail of the level at the same price: at an equal
    -- price the auction house sells the older listing first, so those 240 are ahead too -- the
    -- count THE BOOK's marker shows for the same price (SellViewModel.UnitsAhead). It said 120.
    it("says how much stock is queued at or under the price and lights the level it lands on", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock() })
      assert.equal("360 ahead", rows[1].priceStand.text)
      assert.is_true(rows[1].priceStand.shown)
      local GOLD = GC.Theme.color.gold
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 1 }, rows[1].standMarks[3].colorTexture)
      assert.same({ 1, 1, 1, 0.32 }, rows[1].standMarks[1].colorTexture)
      assert.same({ 1, 1, 1, 0.10 }, rows[1].standMarks[4].colorTexture)
    end)

    it("says first in line, in green, when nothing at or under the price is not the player's own", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock({ postRecommendation = { unit = 178900 } }) })
      assert.equal("first in line", rows[1].priceStand.text)
      assert.same({ 0, 1, 0, 1 }, rows[1].priceStand.color)
      -- Matching the cheapest joins its tail: its 35 sell first. This used to say first in line.
      rows = topRows(GC, { stock({ postRecommendation = { unit = 179000 } }) })
      assert.equal("35 ahead", rows[1].priceStand.text)
    end)

    it("leaves the standing empty rather than claiming an empty queue when there is no book", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock({ levels = false }) })
      assert.equal("", rows[1].priceStand.text)
      assert.same({ 1, 1, 1, 0 }, rows[1].standMarks[1].colorTexture)
    end)

    it("counts a live lot's standing in the watch blue, as stock under it", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock({ bagQty = 0, listedQty = 20, listedValue = 3680000 }) }, "listed")
      -- rows[1] is the deck's section heading.
      assert.equal("360 under you", rows[2].priceStand.text)
      local WATCH = GC.Theme.color.watch
      assert.same({ WATCH[1], WATCH[2], WATCH[3], 1 }, rows[2].standMarks[4].colorTexture)
    end)

    -- The count under a lot says whether it matters: gold on a lot the cancel queue holds
    -- (those units are why it is worth cancelling), quiet on one being held. A lot priced far
    -- under the market wears its price in red -- that figure is the problem.
    it("lights the units under a lot worth cancelling, and reddens a price that is far too low", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      local lot = stock({ bagQty = 0, listedQty = 20, listedValue = 3680000 })
      set(render, "cancelEntries", { { positionKey = lot.positionKey, auctionID = 1 } })
      local rows = topRows(GC, { lot }, "listed")
      local GOLD = GC.Theme.color.goldHi or GC.Theme.color.gold
      assert.equal("360 under you", rows[2].priceStand.text)
      assert.same({ GOLD[1], GOLD[2], GOLD[3], 1 }, rows[2].priceStand.color)
      local FG = GC.Theme.color.fg
      assert.same({ FG[1], FG[2], FG[3], 1 }, rows[2].cells.price.color)

      set(render, "cancelEntries", { { positionKey = lot.positionKey, auctionID = 1, urgent = true } })
      rows = topRows(GC, { lot }, "listed")
      local RED = GC.Theme.color.red
      assert.same({ RED[1], RED[2], RED[3], 1 }, rows[2].cells.price.color)
    end)

    it("puts the margin under YOU GET, and names a missing receipt instead of a number", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock() })
      assert.equal("+82%", rows[1].grossNote.text)
      assert.same({ 0, 1, 0, 1 }, rows[1].grossNote.color)
      rows = topRows(GC, { stock({ coverage = "PARTIAL", knownQty = 10 }) })
      assert.equal("no cost", rows[1].grossNote.text)
    end)

    it("puts the second lines away on a pooled row that stops being a position", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock() })
      rows[1].scripts.OnClick(rows[1])
      assert.equal("drawer", rows[2].kind)
      assert.is_false(rows[2].priceStand.shown)
      assert.is_false(rows[2].grossNote.shown)
      assert.is_false(rows[2].standMarks[1].shown)
    end)

    it("tags a row the post queue left out with the reason, and a ready row with nothing", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      set(render, "queueSkipped", { { positionKey = "commodity:42", reason = "no_fresh_price" },
        { positionKey = "commodity:43", reason = "below_breakeven" } })
      local rows = topRows(GC, { stock(), stock({ positionKey = "commodity:43", itemID = 43 }),
        stock({ positionKey = "commodity:44", itemID = 44 }) })
      local WATCH = "|cff59b8e6no price|r"
      assert.matches(WATCH, rows[1].itemStock.text, 1, true)
      -- A loss is the red margin under YOU GET, not a second set of words beside the stock.
      assert.is_nil(rows[2].itemStock.text:find("below", 1, true))
      assert.is_nil(rows[2].itemStock.text:find("no price", 1, true))
      assert.is_nil(rows[3].itemStock.text:find("no price", 1, true))
    end)

    it("tags uncosted stock with how many units have no receipt", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock({ coverage = "PARTIAL", knownQty = 10 }) })
      assert.matches("no cost for 30", rows[1].itemStock.text, 1, true)
    end)

    it("leads with a lot standing far below market, over every other tag", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { stock({ bagQty = 0, listedQty = 20, listedValue = 3680000,
        coverage = "PARTIAL", knownQty = 10, facts = { underpriced = true } }) }, "listed")
      assert.matches("|cffff0000far below market|r", rows[2].itemStock.text, 1, true)
    end)
  end)

  -- "TO POST 17" over a list of three rows that could be posted (seen in game): the number
  -- counted everything the deck HOLDS -- stock in the mail or the bank folded away under NOT ON
  -- HAND, purchases not yet identified -- where a seller reads it as what there is to post.
  it("counts what can be posted on the deck switch, not everything the deck holds", function()
    local GC = load(620, { calls = {} })
    local function position(id, fields)
      local entry = { itemID = id, itemName = "Item " .. id, positionKey = "commodity:" .. id,
        coverage = "COMPLETE", exposureQty = 5, knownQty = 5, knownCost = 50, sources = {} }
      for key, value in pairs(fields) do entry[key] = value end
      return entry
    end
    local _, container = topRows(GC, {
      position(1, { bagQty = 5, listedQty = 0 }),
      position(2, { bagQty = 3, listedQty = 7 }),          -- on both decks: counted on both
      position(3, { bagQty = 0, listedQty = 0 }),          -- in the mail or the bank
      position(4, { bagQty = 0, listedQty = 0 }),
      position(5, { bagQty = 0, listedQty = 0, unresolved = true }), -- bought, not yet identified
      position(6, { bagQty = 0, listedQty = 4 }),
    })
    container.paintDeckSwitch()
    assert.equal("TO POST 2", container.deckButtons.post.label)
    assert.equal("MY LOTS 2", container.deckButtons.listed.label)
  end)

  describe("the not-on-hand fold", function()
    local function onHand()
      return { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
        exposureQty = 5, knownQty = 5, knownCost = 50, bagQty = 5, listedQty = 0, sources = {} }
    end
    local function ghost(id)
      return { itemID = id, itemName = "Gone", positionKey = "commodity:" .. id, coverage = "COMPLETE",
        exposureQty = 5, knownQty = 5, knownCost = 50, bagQty = 0, listedQty = 0, sources = {} }
    end
    local function kinds(rows)
      local out = {}
      for _, row in ipairs(rows) do if row.shown then out[#out + 1] = row.kind end end
      return out
    end

    it("folds a tail of not-on-hand positions under one counted heading", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { onHand(), ghost(43), ghost(44) })
      assert.same({ "position", "fold" }, kinds(rows))
      assert.matches("^%+ NOT ON HAND 2", rows[2].sectionLabel.text)
    end)

    it("opens and shuts on a click, and stays as the player left it across renders", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { onHand(), ghost(43), ghost(44) })
      rows[2].scripts.OnClick(rows[2])
      assert.same({ "position", "fold", "position", "position" }, kinds(rows))
      assert.matches("^%- NOT ON HAND 2", rows[2].sectionLabel.text)
      upvalue(GC.Sell.Attach, "renderRows")()
      assert.same({ "position", "fold", "position", "position" }, kinds(rows))
      rows[2].scripts.OnClick(rows[2])
      assert.same({ "position", "fold" }, kinds(rows))
    end)

    it("does not fold when nothing on the deck is on hand", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { ghost(43), ghost(44) })
      assert.same({ "position", "position" }, kinds(rows))
    end)

    it("opens by itself under NO COST, where Set cost for those positions lives", function()
      local GC = load(620, { calls = {} })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      local noCost = ghost(43); noCost.coverage = "UNKNOWN"
      local partial = onHand(); partial.coverage = "PARTIAL"
      upvalue(render, "chips").nocost = true
      local rows = topRows(GC, { partial, noCost })
      assert.same({ "position", "fold", "position" }, kinds(rows))
    end)
  end)

  it("keeps one position open at a time", function()
    local GC = load(620, { calls = {} })
    local function p(id)
      return { itemID = id, itemName = "Ore", positionKey = "commodity:" .. id, coverage = "COMPLETE",
        exposureQty = 5, knownQty = 5, knownCost = 50, bagQty = 5, listedQty = 0, sources = {} }
    end
    local rows = topRows(GC, { p(42), p(43) })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("drawer", rows[2].kind)
    local second
    for _, row in ipairs(rows) do
      if row.shown and row.kind == "position" and row.position.itemID == 43 then second = row end
    end
    second.scripts.OnClick(second)
    local drawers = 0
    for _, row in ipairs(rows) do
      if row.shown and row.kind == "drawer" then
        drawers = drawers + 1
        assert.equal(43, row.position.itemID)
      end
    end
    assert.equal(1, drawers)
    -- And a click on the open one shuts it.
    for _, row in ipairs(rows) do
      if row.shown and row.kind == "position" and row.position.itemID == 43 then row.scripts.OnClick(row) break end
    end
    for _, row in ipairs(rows) do assert.is_false(row.shown and row.kind == "drawer") end
  end)

  it("says the status in the dock, beside the bulk action, as well as in the toolbar", function()
    local GC, root = load(620, { calls = {} })
    local _, container = topRows(GC, {})
    GC.Sell.OnPostError()
    assert.is_truthy(root.status.text)
    assert.equal(root.status.text, container.dockStatus.text)
  end)

  it("keeps only AT MARKET in the dock's ledger when the window is narrow", function()
    local GC, root = load(600, { calls = {} })
    local _, container = topRows(GC, {})
    assert.is_true(container.summary.profit.shown)
    assert.is_false(container.summary.cost.shown)
    assert.is_false(container.summary.listed.shown)
    assert.equal(container.summary.profit, container.dockStatus.points[2].relative)
    root.scripts.OnSizeChanged(root, 900)
    assert.is_true(container.summary.cost.shown)
    assert.equal(container.summary.cost, container.dockStatus.points[2].relative)
  end)
  -- What a position opens into: a panel beside the list, not ten rows inside it.
  describe("the detail panel", function()
    local function p(id, over)
      local value = { itemID = id, itemName = "Ore " .. id, positionKey = "commodity:" .. id,
        coverage = "COMPLETE", exposureQty = 5, knownQty = 5, knownCost = 50, bagQty = 5,
        listedQty = 0, sources = {} }
      for key, field in pairs(over or {}) do value[key] = field end
      return value
    end

    it("opens beside the list, names the item, and leaves the list where it was", function()
      local GC = load(1100, { calls = {} })
      local rows, container = topRows(GC, { p(42), p(43) })
      assert.is_false(container.inspector.shown)
      rows[1].scripts.OnClick(rows[1])
      assert.is_true(container.inspector.shown)
      assert.equal("Ore 42", container.inspector.name.text)
      assert.equal("×5 in bags", container.inspector.stock.text)
      -- The second position is still the second thing in the list: nothing was pushed under it.
      local listed = {}
      for _, row in ipairs(rows) do
        if row.shown and not row.inPanel then listed[#listed + 1] = row.position.itemID end
      end
      assert.same({ 42, 43 }, listed)
    end)

    it("has a column of its own on a wide window and lies over the list on a narrow one", function()
      local wide = load(1100, { calls = {} })
      local rows, container = topRows(wide, { p(42) })
      local header
      for _, child in ipairs(container.children) do if child.cells then header = child break end end
      rows[1].scripts.OnClick(rows[1])
      -- The short SetPoint form: (point, x, y), which the double files under `relative`.
      assert.equal(-(340 + 28), header.points[2].relative)

      local narrow = load(620, { calls = {} })
      rows, container = topRows(narrow, { p(42) })
      for _, child in ipairs(container.children) do if child.cells then header = child break end end
      rows[1].scripts.OnClick(rows[1])
      assert.is_true(container.inspector.shown)
      assert.equal(0, header.points[2].relative)
      assert.is_true(container.inspector.mouseEnabled)
    end)

    it("gives the list its width back when it shuts, from its own close button", function()
      local GC = load(1100, { calls = {} })
      local rows, container = topRows(GC, { p(42) })
      local render = upvalue(GC.Sell.Attach, "renderRows")
      rows[1].scripts.OnClick(rows[1])
      assert.equal(1100 - 340 - 28, upvalue(render, "content").width)
      container.inspector.close.scripts.OnClick()
      assert.is_false(container.inspector.shown)
      assert.equal(1100, upvalue(render, "content").width)
      for _, row in ipairs(rows) do assert.is_false(row.shown and row.inPanel) end
    end)

    it("shuts when the open position is no longer on the deck", function()
      local GC = load(620, { calls = {} })
      local rows, container = topRows(GC, { p(42) })
      rows[1].scripts.OnClick(rows[1])
      assert.is_true(container.inspector.shown)
      container.deckButtons.listed.scripts.OnClick()
      assert.is_false(container.inspector.shown)
    end)

    it("carries Post in its head for stock in the bags, and no button for stock that is not", function()
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { p(42) })
      rows[1].scripts.OnClick(rows[1])
      assert.equal("drawer", rows[2].kind)
      assert.is_true(rows[2].action.shown)
      assert.equal("Post", rows[2].action.helpKey)

      local listedOnly = load(620, { calls = {} })
      rows = topRows(listedOnly, { p(42, { bagQty = 0, listedQty = 5, listedValue = 500 }) }, "listed")
      rows[2].scripts.OnClick(rows[2]) -- rows[1] is the deck's section heading
      local head
      for _, row in ipairs(rows) do if row.shown and row.kind == "drawer" then head = row end end
      assert.is_table(head)
      assert.is_false(head.action.shown)
    end)

    it("washes a hovered list row and nothing inside the panel", function()
      _G.GameTooltip = nil
      local GC = load(620, { calls = {} })
      local rows = topRows(GC, { p(42) })
      rows[1].scripts.OnClick(rows[1])
      rows[1].scripts.OnEnter(rows[1])
      assert.is_true(rows[1].highlight.shown)
      rows[2].scripts.OnEnter(rows[2])
      assert.is_false(rows[2].highlight.shown)
    end)
  end)
  describe("the search box", function()
    local function p(id, name)
      return { itemID = id, itemName = name, positionKey = "commodity:" .. id, coverage = "COMPLETE",
        exposureQty = 5, knownQty = 5, knownCost = 50, bagQty = 5, listedQty = 0, sources = {} }
    end
    local function names(rows)
      local out = {}
      for _, row in ipairs(rows) do
        if row.shown and row.kind == "position" then out[#out + 1] = row.position.itemName end
      end
      return out
    end
    local function type_(container, text)
      container.search:SetText(text)
      container.search.scripts.OnTextChanged(container.search, true)
    end

    it("narrows the list to the names that contain what was typed, whatever its case", function()
      local GC = load(800, { calls = {} })
      local rows, container = topRows(GC, { p(1, "Arcanoweave"), p(2, "Arcanoweave Lining"), p(3, "Pygmy Oil") })
      type_(container, "  LINING ")
      assert.same({ "Arcanoweave Lining" }, names(rows))
      type_(container, "")
      assert.same({ "Arcanoweave", "Arcanoweave Lining", "Pygmy Oil" }, names(rows))
    end)

    it("says so when nothing matches, and gives the list back on Escape", function()
      local GC = load(800, { calls = {} })
      local rows, container = topRows(GC, { p(1, "Arcanoweave") })
      type_(container, "zzz")
      assert.same({}, names(rows))
      assert.is_true(container.emptyText.shown)
      assert.equal("Nothing on this deck matches that search", container.emptyText.text)
      container.search.scripts.OnEscapePressed(container.search)
      assert.equal("", container.search.text)
      assert.same({ "Arcanoweave" }, names(rows))
    end)

    it("leaves the dock's totals the deck's own while it narrows the rows", function()
      local GC = load(800, { calls = {} })
      local _, container = topRows(GC, { p(1, "Arcanoweave"), p(2, "Pygmy Oil") })
      local before = container.summary.cost.text
      type_(container, "pygmy")
      assert.equal(before, container.summary.cost.text)
    end)

    it("is not drawn where row 1 has no room for it, and cannot filter from there", function()
      local GC, root = load(800, { calls = {} })
      local rows, container = topRows(GC, { p(1, "Arcanoweave"), p(2, "Pygmy Oil") })
      assert.is_true(container.search.shown)
      type_(container, "pygmy")
      assert.same({ "Pygmy Oil" }, names(rows))
      -- 640 is the window's resize floor; this harness insets the content by 16.
      root.scripts.OnSizeChanged(root, 640)
      assert.is_false(container.search.shown)
      upvalue(GC.Sell.Attach, "renderRows")()
      assert.same({ "Arcanoweave", "Pygmy Oil" }, names(rows))
    end)
  end)
  it("drops the bag line from the panel when it would only repeat the panel's own heading", function()
    local GC = load(620, { calls = {} })
    local render = upvalue(GC.Sell.Attach, "renderRows")
    set(render, "liveBagState",
      function() return { bag = 0, slot = 1, stackQty = 5, exactQty = 5, itemID = 42, positionKey = "commodity:42" } end)
    local rows = topRows(GC, {
      { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE", exposureQty = 5,
        knownQty = 5, knownCost = 500, listedValue = 0, bagQty = 5, listedQty = 0, sources = { goldcap = 5 } },
    })
    rows[1].scripts.OnClick(rows[1])
    for _, row in ipairs(rows) do
      assert.is_false(row.shown and (row.kind == "listing" or row.kind == "group"), row.kind)
    end
  end)
  -- Under the price chips: only what the box, the red note and the button do not already say.
  it("states the reason for the price alone on a postable head, and nothing when there is none", function()
    local GC = load(620, { calls = {} })
    local p = { itemID = 42, itemName = "Ore", positionKey = "commodity:42", coverage = "COMPLETE",
      exposureQty = 5, knownQty = 5, knownCost = 500, bagQty = 5, listedQty = 0, sources = {},
      recommendation = { action = "post", unit = 28500, belowCost = true } }
    GC.SellViewModel.Expansion = function()
      return { batches = {}, ownedLots = {}, recommendation = p.recommendation,
        factsText = "above the cheapest, within the day's reach · 12 units queued below" }
    end
    local rows = topRows(GC, { p })
    rows[1].scripts.OnClick(rows[1])
    assert.equal("above the cheapest, within the day's reach · 12 units queued below", rows[2].subItem.text)
    local withReason = rows[2].height

    GC.SellViewModel.Expansion = function()
      return { batches = {}, ownedLots = {}, recommendation = p.recommendation }
    end
    upvalue(GC.Sell.Attach, "renderRows")()
    assert.equal("", rows[2].subItem.text)
    -- ...and the head gives the paragraph's slot back rather than keeping a gap for it.
    assert.equal(withReason - 24, rows[2].height)
  end)
end)
