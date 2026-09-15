local helper = require("spec.spec_helper")

-- The BUY tab's floor refresh: one C_AuctionHouse.SearchForItemKeys batch for the lines the
-- run still has to buy, sent through the very same arbiter and the very same one-batch-at-a-
-- time interlock the Items board's realm poll uses (UI/SniperFrame.lua's _keysAwaiting).
--
-- Both real files are loaded, not stubbed: the whole point of this feature is that BUY does
-- NOT open a second search channel of its own, so a spec that faked the sender would prove
-- nothing about the one rule that matters -- only one batch may be outstanding addon-wide.
describe("BUY floor refresh", function()
  local GC, sent, now, browseRows

  local NAMES = { [101] = "Alpha Herb", [102] = "Bravo Ore", [103] = "Charlie Dust",
                  [104] = "Delta Vial" }

  -- Four lines, one of each state: 101 open, 102 already covered by the bags (done), 103 open
  -- (or locked, depending on the free-line limit the test asks for), 104 at the vendor.
  -- `allDone` zeroes 101/103's own quantities so every non-vendor line reads done (102 is
  -- already covered by the bags either way) -- the "nothing left to ask about" run HasPending
  -- exists to answer false for.
  local function runData(opts)
    opts = opts or {}
    return {
      code = "run-1", name = "Flask run", updatedAt = 100, origin = "app",
      lines = {
        { i = 101, q = opts.allDone and 0 or 10 },
        { i = 102, q = 5 },
        { i = 103, q = opts.allDone and 0 or 3 },
        { i = 104, q = 20, v = true },
      },
    }
  end

  local function region(kind, parent)
    local r = { __frame = true, kind = kind, children = {}, textValue = nil, visible = true,
                enabled = true, points = {}, scripts = {} }
    function r:SetPoint(point, relative, relativePoint, x, y)
      self.points[#self.points + 1] = { point = point, relative = relative,
                                        relativePoint = relativePoint, x = x, y = y }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() self.points[#self.points + 1] = { point = "ALL" } end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetWordWrap() end
    function r:SetMaxLines(n) self.maxLines = n end
    function r:SetTextColor(...) self.colorValue = { ... } end
    function r:SetColorTexture(...) self.colorTexture = { ... } end
    function r:SetTexture(f) self.texture = f end
    function r:SetTexCoord() end
    function r:SetTextureSliceMargins(...) self.sliceMargins = { ... } end
    function r:SetVertexColor(...) self.vertexColor = { ... } end
    function r:SetSpacing(s) self.spacing = s end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:EnableMouse() end
    function r:RegisterForClicks() end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:IsEnabled() return self.enabled end
    function r:CreateTexture() return region("Texture", self) end
    function r:CreateFontString() return region("FontString", self) end
    if parent then parent.children[#parent.children + 1] = r end
    return r
  end

  local function button(parent)
    local b = region("Button", parent)
    b.text = region("FontString", b)
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    function b:SetVariant() end
    function b:SetUppercase() end
    return b
  end

  local function chip(parent)
    local c = region("Frame", parent)
    c.text = region("FontString", c)
    function c:SetLabel(text, color) self.label = text; self.text:SetText(text); self.chipColor = color end
    return c
  end

  -- Whichever upvalue slot the wanted name happens to occupy -- the same reach
  -- spec/slot_arbiter_spec uses, and the only way to drive the rail's current tab or the AH
  -- session flag without building the whole window and firing real client events.
  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function setView(v) set(GC.Sniper.OnThrottleReady, "view", v) end

  local function upvalueOf(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function load(opts)
    opts = opts or {}
    sent, now, browseRows = {}, 2000, {}
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetTime = function() return 100 end
    _G.time = function() return now end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_Item = { GetItemInfo = function(id) return NAMES[id] end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
      GetContainerItemInfo = function(bag, slot)
        -- One bag holding the five Bravo Ore that make line 102 `done`.
        if bag == 0 and slot == 1 then
          return { itemID = 102, stackCount = 5, hyperlink = "|Hitem:102|h" }
        end
      end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return browseRows end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function(key) return { isCommodity = not opts.gear or opts.gear ~= key.itemID } end,
      SearchForItemKeys = function(keys)
        local ids = {}
        for i = 1, #keys do ids[i] = keys[i].itemID end
        sent[#sent + 1] = ids
      end,
    }

    GC = {
      Theme = {
        MEDIA = "", ROW_H = 20, RAIL_W = 76,
        pad = { xs = 4, s = 8, m = 12, l = 16 },
        tier = { WATCH = { 1, 1, 1 }, SUSPECT = { 1, 1, 0 } },
        color = { fg = { 1, 1, 1 }, fgMuted = { 0.8, 0.8, 0.8 }, fgDim = { 0.55, 0.54, 0.52 },
                  gold = { 0.83, 0.64, 0.22 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
                  panel = { 0, 0, 0 }, bg = { 0, 0, 0 }, zebra = { 1, 1, 1, 0.04 },
                  hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 } },
        Label = function(parent) return region("FontString", parent) end,
        Num = function(parent) return region("FontString", parent) end,
        Button = function(parent) return button(parent) end,
        Chip = function(parent) return chip(parent) end,
        WithQuality = function(name) return name end,
      },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = {
        GetItemValue = function(itemID)
          return ({ [101] = { mv = 1000 }, [102] = { mv = 2000 }, [103] = { mv = 3000 } })[itemID]
        end,
        GetWatchlist = function() return {} end,
      },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
        CapDeals = function(deals) return deals end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, board = "items", buyCapPct = 130 } } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    helper.loadModule("UI/BuyFrame.lua", GC)

    local runs = { runData(opts) }
    if opts.secondRun then runs[#runs + 1] = opts.secondRun end
    GC.AppRuns = {
      List = function() return runs end,
      Get = function(code)
        for _, r in ipairs(runs) do if r.code == code then return r end end
      end,
      FreeLines = function() return opts.freeLines end,
    }

    GC.Buy.Attach(region("Frame"), { panelLeft = 88, panelRightInset = 32, top = -100,
                                     bottom = 34, rowWidth = 600, rowHeight = 28 })
    setView("buy")
    -- OnAuctionHouseShow's own flag, which BUY refuses to send without: this whole tab only
    -- has a question while there is a session to answer it. Opt out with ahClosed.
    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", not opts.ahClosed)
    return GC
  end

  after_each(function()
    _G.CreateFrame, _G.GetCoinTextureString, _G.C_Item, _G.C_Container = nil, nil, nil, nil
    _G.C_AuctionHouse, _G.C_Timer, _G.GetTime = nil, nil, nil
    _G.time = os.time
  end)

  local function rowWithText(text)
    for _, row in ipairs(upvalueOf(GC.Buy.RefreshIfShown, "rows")) do
      if row:IsShown() and (row.reagent:GetText() or ""):find(text, 1, true) then return row end
    end
  end

  it("asks about every line the run still has to buy, the moment the tab opens", function()
    load({ freeLines = 3 })
    GC.Buy.Show()
    -- 102 is covered by the bags and 104 is a vendor line: neither is something this tab will
    -- ever spend gold on, so neither is worth a slot in the one batch the run gets.
    assert.same({ { 101, 103 } }, sent)
  end)

  it("leaves a locked line out of the batch", function()
    load({ freeLines = 1 })
    GC.Buy.Show()
    assert.same({ { 101 } }, sent)
  end)

  -- HasPending() used to be a stub that always answered true, so an all-done run still took
  -- the shared throttle claim for a batch NextBatch would then send empty. Wired honestly, a
  -- run with nothing open (not vendor, not locked, not done) must never even reach
  -- GC.Util.ClaimThrottleSend, let alone SearchForItemKeys.
  it("an all-done run: Tick sends nothing and never claims the throttle", function()
    load({ freeLines = 3, allDone = true })
    local claims = 0
    local realClaim = GC.Util.ClaimThrottleSend
    GC.Util.ClaimThrottleSend = function(...)
      claims = claims + 1
      return realClaim(...)
    end
    GC.Buy.Show()
    assert.same({}, sent)
    assert.equal(0, claims)

    now = now + 60
    GC.Buy.Tick()
    assert.same({}, sent)
    assert.equal(0, claims)
  end)

  it("leaves out an item the auction house says is not a commodity", function()
    load({ freeLines = 3, gear = 103 })
    GC.Buy.Show()
    assert.same({ { 101 } }, sent)
  end)

  it("folds the answer into the lines' floors, and the board shows them", function()
    load({ freeLines = 3 })
    GC.Buy.Show()
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 900, totalQuantity = 40 } }
    GC.Sniper.OnBrowseResults()
    assert.equal("900c", rowWithText("Alpha Herb").cells.now:GetText())
    -- 103 was asked about and no row came back for it: it keeps the floor it had (none), and
    -- says so, rather than borrowing the answer that did arrive.
    assert.equal("—", rowWithText("Charlie Dust").cells.now:GetText())
  end)

  it("keeps a floor an answer does not mention", function()
    load({ freeLines = 3 })
    GC.Buy.Show()
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 900, totalQuantity = 40 } }
    GC.Sniper.OnBrowseResults()
    now = now + 30
    GC.Buy.Tick()
    browseRows = { { itemKey = { itemID = 103 }, minPrice = 2500, totalQuantity = 4 } }
    GC.Sniper.OnBrowseResults()
    assert.equal("900c", rowWithText("Alpha Herb").cells.now:GetText())
    assert.equal("2500c", rowWithText("Charlie Dust").cells.now:GetText())
  end)

  it("waits twenty seconds before asking again", function()
    load({ freeLines = 3 })
    GC.Buy.Show()
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 900 } }
    GC.Sniper.OnBrowseResults()
    assert.equal(1, #sent)

    now = now + 19
    GC.Buy.Tick()
    assert.equal(1, #sent)

    now = now + 1
    GC.Buy.Tick()
    assert.equal(2, #sent)
  end)

  it("sends nothing while the Items board's own batch is outstanding", function()
    local gc = load({ freeLines = 3 })
    setView("deals")
    gc.Sniper._keyPoll:SetTargets({ 501, 502 })
    gc.Sniper.OnThrottleReady()
    assert.same({ { 501, 502 } }, sent)

    setView("buy")
    gc.Buy.Show()
    assert.equal(1, #sent) -- one batch addon-wide, and it is not ours

    -- And the answer belongs to the poll that asked, not to whoever asked last.
    browseRows = { { itemKey = { itemID = 501 }, minPrice = 7 } }
    gc.Sniper.OnBrowseResults()
    assert.equal(7, gc.Sniper._keyPoll:Book()[501].floor)
    assert.equal("—", rowWithText("Alpha Herb").cells.now:GetText())
  end)

  -- Every cheaper gate is deliberately left OPEN here -- the container is shown, a run is
  -- picked, the refresh window has expired -- so the only thing that can refuse this tick is
  -- the view. (Written the other way round, with the tab never opened, the test passes with
  -- the view gate deleted: it never reaches it.)
  it("sends nothing while another tab is on screen", function()
    load({ freeLines = 3 })
    GC.Buy.Show()
    assert.equal(1, #sent)
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 900 } }
    GC.Sniper.OnBrowseResults()

    now = now + 60
    setView("deals") -- a rail click leaves this tab's container shown behind Deals
    GC.Buy.Tick()
    GC.Buy.TrySendRefresh()
    assert.equal(1, #sent)

    -- ...and the moment the player is back on it, the same tick goes through.
    setView("buy")
    GC.Buy.Tick()
    assert.equal(2, #sent)
  end)

  it("sends nothing with no auction house session to answer it", function()
    load({ freeLines = 3, ahClosed = true })
    GC.Buy.Show()
    assert.same({}, sent)
    GC.Buy.Tick()
    assert.same({}, sent)
  end)

  -- The twenty-second window belongs to a run's prices, not to the tab. A new run has no
  -- floors at all, so a window left standing across the switch holds every NOW cell on an em
  -- dash for up to twenty seconds -- with the batch that would fill them refused.
  it("gives the refresh window up when the shown run is replaced", function()
    load({ freeLines = 3, secondRun = {
      code = "run-2", name = "Potion run", updatedAt = 100, origin = "app",
      lines = { { i = 103, q = 7 } },
    } })
    GC.Buy.Show()
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 900 } }
    GC.Sniper.OnBrowseResults()
    assert.equal(1, #sent)

    now = now + 1 -- well inside the window the first run had earned
    GC.Buy.SelectRun("run-2")
    GC.Buy.RefreshIfShown()
    GC.Buy.Tick()
    assert.same({ 103 }, sent[2])
  end)

  it("gives the Items poll its answer back once BUY's own batch has landed", function()
    local gc = load({ freeLines = 3 })
    gc.Buy.Show()
    assert.equal(1, #sent)
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 900 } }
    gc.Sniper.OnBrowseResults()

    setView("deals")
    gc.Sniper._keyPoll:SetTargets({ 501 })
    gc.Sniper.OnThrottleReady()
    assert.same({ 501 }, sent[2])
    browseRows = { { itemKey = { itemID = 501 }, minPrice = 7 } }
    gc.Sniper.OnBrowseResults()
    assert.equal(7, gc.Sniper._keyPoll:Book()[501].floor)
  end)
end)
