local helper = require("spec.spec_helper")

-- The BUY tab's purchase: hover quotes the line against the live commodity book, one click
-- starts the purchase for exactly the quoted quantity, and a second click confirms the server's
-- own price -- but only while that price is still inside the line's cap.
--
-- Core/BuyRun.lua, Core/PurchaseSlot.lua, Core/Acquisitions.lua and Core/PurchaseCapture.lua
-- are all loaded for real: what this spec is actually about is the four of them agreeing --
-- one purchase in flight addon-wide, one acquisition batch per purchase, and no second batch
-- from the passive capture hooks. Only the client itself is faked.
describe("BUY purchase", function()
  local GC, searches, started, confirmed, cancels, timers, book, now, bags, sniperCalls
  -- Whether the fake Sniper is holding a stranded confirm of its own (GC.Sniper.HasStrandedConfirmed).
  local sniperStranded

  local NAMES = { [101] = "Alpha Herb", [102] = "Bravo Ore", [103] = "Charlie Dust",
                  [105] = "Echo Salt" }

  local function runData()
    return {
      code = "run-1", name = "Flask run", updatedAt = 100, origin = "app",
      lines = {
        { i = 101, q = 10, ch = 3, cp = -18 },
        { i = 103, q = 4 },
        -- 105 has no market value at all, so it has no cap: the quote is the only number
        -- anybody ever checks for it.
        { i = 105, q = 5 },
        { i = 102, q = 5, v = true },
      },
    }
  end

  local function otherRun()
    return { code = "run-2", name = "Potion run", updatedAt = 100, origin = "app",
             lines = { { i = 103, q = 2 } } }
  end

  local function region(kind, parent)
    local r = { __frame = true, kind = kind, children = {}, textValue = nil, visible = true,
                enabled = true, points = {}, scripts = {}, propagate = nil, mouseOver = false }
    function r:SetPoint() end
    function r:ClearAllPoints() end
    function r:SetAllPoints() end
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
    function r:GetScript(name) return self.scripts[name] end
    function r:EnableMouse() end
    function r:RegisterEvent() end
    function r:UnregisterEvent() end
    function r:EnableKeyboard() self.keyboard = true end
    function r:SetPropagateKeyboardInput(value) self.propagate = value end
    function r:IsMouseOver() return self.mouseOver end
    function r:RegisterForClicks() end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:IsEnabled() return self.enabled end
    function r:CreateTexture() return region("Texture", self) end
    function r:CreateFontString() return region("FontString", self) end
    if parent then parent.children[#parent.children + 1] = r end
    return r
  end

  -- Theme.Button's real contract, as far as this spec needs it: `.label` is the caller's exact
  -- string, SetVariant repaints background and text in the variant's own live colours, and
  -- OnEnable/OnDisable fire only on a state CHANGE (UI/Theme.lua) -- which is the whole reason
  -- paintLine has to Enable before it Disables. `painted` stands in for that colour.
  local function button(parent)
    local b = region("Button", parent)
    b.text = region("FontString", b)
    b.painted = "variant"
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    function b:SetVariant(name) self.variant = name; self.painted = "variant" end
    function b:Enable()
      if not self.enabled then self.painted = "variant" end
      self.enabled = true
    end
    function b:Disable()
      if self.enabled then self.painted = "dim" end
      self.enabled = false
    end
    function b:SetUppercase() end
    return b
  end

  local function chip(parent)
    local c = region("Frame", parent)
    c.text = region("FontString", c)
    function c:SetLabel(text, color) self.label = text; self.text:SetText(text); self.chipColor = color end
    return c
  end

  local function upvalueOf(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function rowWithText(text)
    for _, row in ipairs(upvalueOf(GC.Buy.RefreshIfShown, "rows")) do
      if row:IsShown() and (row.reagent:GetText() or ""):find(text, 1, true) then return row end
    end
  end

  -- A bought-out line sinks to the bottom of the run, so a line is found by its item and never
  -- by the position it held before the purchase.
  local function runLine(itemID)
    for _, l in ipairs(GC.Buy.CurrentRun():Lines()) do
      if l.itemID == itemID then return l end
    end
  end

  local function containerOf() return upvalueOf(GC.Buy.Show, "container") end

  -- Core/Init.lua's own OnEvent, so the routing between GC.Buy and GC.Sniper is exercised rather
  -- than assumed. Every other test here calls a handler directly, which is exactly how a router
  -- bug hides: the whole late-success path lives on the far side of one.
  local function loadRouter()
    _G.hooksecurefunc = function() end
    _G.SlashCmdList = {}
    _G.Enum = { PlayerInteractionType = { Auctioneer = 21 } }
    local captured
    local realCreate = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent)
      local f = realCreate(kind, name, parent)
      local set = f.SetScript
      f.SetScript = function(self, script, fn)
        set(self, script, fn)
        if script == "OnEvent" then captured = fn end
      end
      return f
    end
    helper.loadModule("Core/Init.lua", GC)
    _G.CreateFrame = realCreate
    assert.is_truthy(captured)
    return captured
  end

  -- The commodity book the client would answer a SendSearchQuery with: cheapest level first,
  -- each level a whole price point aggregated across sellers.
  local function setBook(itemID, levels) book[itemID] = levels end

  local function hover(row)
    row.scripts.OnEnter(row)
  end

  local function click(row)
    row.action.scripts.OnClick(row.action)
  end

  local function keyDown(key)
    local container = containerOf()
    container.scripts.OnKeyDown(container, key)
    return container
  end

  -- The units the client hands over on a successful purchase. Called before the terminal event,
  -- because that is the order the client uses: the stack is in the bag by the time it fires.
  local function deliver(itemID, qty)
    bags[1] = { itemID = itemID, qty = (bags[1] and bags[1].qty or 0) + qty }
  end

  before_each(function()
    searches, started, confirmed, timers, book, now = {}, {}, {}, {}, {}, 2000
    bags, cancels = {}, 0
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.GetTime = function() return now end
    _G.time = function() return now end
    _G.C_Item = { GetItemInfo = function(id) return NAMES[id] end }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    -- Realm clock says 14:00 while UTC says 12:00: a realm two hours ahead of UTC.
    _G.C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 14 } end }
    _G.GetServerTime = function() return 1757937600 end
    _G.date = function() return { hour = 12 } end
    -- One real bag, so a purchase can be delivered into it the way the client delivers one.
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
      GetContainerItemInfo = function(bag, slot)
        if bag ~= 0 then return nil end
        local entry = bags[slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.qty,
                 hyperlink = "|Hitem:" .. entry.itemID .. "|h" }
      end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      SendSearchQuery = function(key) searches[#searches + 1] = key.itemID end,
      SearchForItemKeys = function() end,
      GetNumCommoditySearchResults = function(itemID) return #(book[itemID] or {}) end,
      GetCommoditySearchResultInfo = function(itemID, index) return (book[itemID] or {})[index] end,
      StartCommoditiesPurchase = function(itemID, quantity)
        started[#started + 1] = { itemID = itemID, quantity = quantity }
      end,
      ConfirmCommoditiesPurchase = function(itemID, quantity)
        confirmed[#confirmed + 1] = { itemID = itemID, quantity = quantity }
      end,
      CancelCommoditiesPurchase = function() cancels = cancels + 1 end,
    }

    GC = helper.loadModule("Core/Util.lua")
    GC.Theme = {
      MEDIA = "",
      color = { fg = {1,1,1}, fgMuted = {0.8,0.8,0.8}, fgDim = {0.55,0.54,0.52},
                gold = {0.83,0.64,0.22}, red = {1,0,0}, green = {0,1,0}, panel = {0,0,0},
                bg = {0,0,0}, zebra = {1,1,1,0.04}, hover = {1,1,1,0.08}, border = {1,1,1,0.06} },
      tier = { SUSPECT = {1,1,0} },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      Label = function(parent) return region("FontString", parent) end,
      Num = function(parent) return region("FontString", parent) end,
      Button = function(parent) return button(parent) end,
      Chip = function(parent) return chip(parent) end,
      WithQuality = function(name) return name end,
    }
    GC.db = { settings = { sniper = { buyCapPct = 130 } } }
    GC.Data = { GetItemValue = function(itemID)
      return ({ [101] = { mv = 1000 }, [102] = { mv = 2000 }, [103] = { mv = 3000 } })[itemID]
    end }
    GC.Print = function() end
    -- The real ledger, so the row this tab writes has to be one Core/Ledger.lua will actually
    -- accept; only the character/region lookup is faked, since a headless run has no player.
    helper.loadModule("Core/Ledger.lua", GC)
    GC.Ledger.Init({})
    GC.Ledger.Context = function() return { char = "Tester-Realm", region = "eu" } end
    -- The arbiter and the AH session flag are UI/SniperFrame.lua's, and its own batch path is
    -- covered by spec/buy_refresh_spec.lua against the real file. What this spec needs from it
    -- is only "there is a session, and BUY is the tab on screen".
    sniperCalls, sniperStranded = {}, false
    GC.Sniper = {
      IsAHOpen = function() return true end, CurrentView = function() return "buy" end,
      HasStrandedConfirmed = function() return sniperStranded end,
      OnCommodityPurchaseSucceeded = function() sniperCalls[#sniperCalls + 1] = "succeeded" end,
      OnCommodityPurchaseFailed = function() sniperCalls[#sniperCalls + 1] = "failed" end,
      OnCommodityPriceUnavailable = function() sniperCalls[#sniperCalls + 1] = "unavailable" end,
      OnCommodityPriceUpdated = function() sniperCalls[#sniperCalls + 1] = "priceUpdated" end,
      OnCommoditySearchResults = function() end,
      scanner = nil,
    }
    GC.Sell = {}

    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)
    helper.loadModule("Core/PurchaseSlot.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/PurchaseCapture.lua", GC)
    GC.Acquisitions.Init({})
    helper.loadModule("UI/BuyFrame.lua", GC)

    local runs = { runData(), otherRun() }
    GC.AppRuns = {
      List = function() return runs end,
      Get = function(code)
        for _, r in ipairs(runs) do if r.code == code then return r end end
      end,
      _set = function(list) runs = list end,
    }

    GC.Buy.Attach(region("Frame"), { panelLeft = 88, panelRightInset = 32, top = -100,
                                     bottom = 34, rowWidth = 600, rowHeight = 28 })
    setBook(101, { { unitPrice = 900, quantity = 6 }, { unitPrice = 1200, quantity = 10 } })
    setBook(103, { { unitPrice = 2500, quantity = 20 } })
    setBook(105, { { unitPrice = 400, quantity = 20 } })
    GC.Buy.Show()
  end)

  after_each(function()
    _G.CreateFrame, _G.GetCoinTextureString, _G.C_Item, _G.C_Container = nil, nil, nil, nil
    _G.C_AuctionHouse, _G.C_Timer, _G.GetTime = nil, nil, nil
    _G.GameTooltip, _G.C_DateAndTime, _G.GetServerTime, _G.date = nil, nil, nil, nil
    _G.hooksecurefunc, _G.SlashCmdList, _G.Enum = nil, nil, nil
    -- .busted runs without isolation, so the combat flag one test sets must not outlive it.
    _G.InCombatLockdown = nil
    -- Core/Init.lua sets both; .busted runs without isolation and spec/loadorder_spec.lua asserts
    -- on them, so a router-loading spec has to take them back out.
    _G.SLASH_GOLDCAP1, _G.SLASH_GOLDCAP2 = nil, nil
    _G.time = os.time
  end)

  -- Step 1: the quote.

  it("asks the auction house once when the cursor lands on a buyable line", function()
    hover(rowWithText("Alpha Herb"))
    assert.same({ 101 }, searches)
    assert.equal("quoting", GC.Buy._attempt.stage)
    -- Hovering the same line again inside the quote window does not ask twice.
    GC.Buy.OnCommodityResults(101)
    hover(rowWithText("Alpha Herb"))
    assert.same({ 101 }, searches)
  end)

  it("quotes the missing quantity and what it costs, off the live ladder", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local attempt = GC.Buy._attempt
    assert.equal("quoted", attempt.stage)
    assert.equal(10, attempt.qty)                       -- 6 @ 900 + 4 @ 1200
    assert.equal(6 * 900 + 4 * 1200, attempt.total)
    assert.is_false(attempt.capped)
    assert.equal("BUY 10", rowWithText("Alpha Herb").action.label)
    assert.equal("1g02s", rowWithText("Alpha Herb").cells.cost:GetText())
  end)

  it("never prices against the player's own units", function()
    setBook(101, { { unitPrice = 900, quantity = 6, numOwnerItems = 6 },
                   { unitPrice = 1200, quantity = 10 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.equal(10 * 1200, GC.Buy._attempt.total)
  end)

  it("says how far over usual the rest is when the cap stops the ladder dead", function()
    setBook(101, { { unitPrice = 2000, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local attempt = GC.Buy._attempt
    assert.equal(0, attempt.qty)
    assert.is_true(attempt.capped)
    local row = rowWithText("Alpha Herb")
    assert.equal("▲100% over usual", row.action.label)
    assert.is_false(row.action:IsEnabled())
    -- The over-cap look, which a line where only PART fits wears too (see the partial-fill test).
    assert.equal("warn", row.action.variant)
  end)

  -- Spec rule 3: the cheap hour is the answer to "why did the cap refuse this", so it rides the
  -- same log line the over-usual percentage does -- which is what `/gc buy` prints back.
  it("puts the cheap hour on the log line of a quote the cap refused", function()
    setBook(101, { { unitPrice = 2000, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local text = GC.Buy._log[#GC.Buy._log].text
    assert.is_truthy(text:find("▲100% over usual", 1, true))
    assert.is_truthy(text:find("usually cheapest around 05:00 · -18%", 1, true))
  end)

  it("leaves the cheap hour off a quote the cap was happy with", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.is_nil(GC.Buy._log[#GC.Buy._log].text:find("usually cheapest", 1, true))
  end)

  it("does not quote a vendor line, and offers it no button to click", function()
    local vendor = rowWithText("Bravo Ore")
    assert.is_false(vendor.action:IsShown())
    hover(vendor)
    assert.same({}, searches)
    assert.is_nil(GC.Buy._attempt)
  end)

  it("offers an enabled BUY button for the quantity still missing", function()
    local row = rowWithText("Alpha Herb")
    assert.equal("BUY 10", row.action.label)
    assert.is_true(row.action:IsEnabled())
  end)

  -- Step 2: the click that starts.

  it("starts the purchase for exactly the quoted quantity, holding the shared slot", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    assert.same({ { itemID = 101, quantity = 10 } }, started)
    assert.equal("started", GC.Buy._attempt.stage)
    assert.equal("buy", GC.PurchaseSlot.Owner())
  end)

  it("quotes instead of buying when the click lands without a fresh quote", function()
    click(rowWithText("Alpha Herb"))
    assert.same({}, started)
    assert.same({ 101 }, searches)
    assert.equal("quoting", GC.Buy._attempt.stage)
  end)

  it("refuses to start while the sniper holds the purchase slot", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    GC.PurchaseSlot.Claim("sniper", now)
    click(rowWithText("Alpha Herb"))
    assert.same({}, started)
    assert.equal("sniper", GC.PurchaseSlot.Owner())
  end)

  it("ignores a second click while a purchase is already started", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    click(rowWithText("Alpha Herb"))
    assert.equal(1, #started)
    assert.same({}, confirmed)
    assert.equal("started", GC.Buy._attempt.stage)
  end)

  it("gives the slot back when the purchase never answers", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    local watchdog = timers[#timers]
    assert.equal(10, watchdog.seconds)
    watchdog.fn()
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.equal("expired", GC.Buy._attempt.stage)
  end)

  -- Step 3: the server's price, and the click that confirms it.

  it("asks for a confirming click when the server price is inside the cap", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    assert.equal("confirm", GC.Buy._attempt.stage)
    assert.same({}, confirmed) -- nothing is confirmed by the event itself
    assert.equal("CONFIRM", rowWithText("Alpha Herb").action.label)
    assert.equal("1g02s", rowWithText("Alpha Herb").cells.cost:GetText())

    click(rowWithText("Alpha Herb"))
    assert.same({ { itemID = 101, quantity = 10 } }, confirmed)
    assert.equal("confirming", GC.Buy._attempt.stage)
  end)

  it("confirms a price above the quote as long as the unit is under the cap", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1200, 12000) -- 1200/unit, cap is 1300
    assert.equal("confirm", GC.Buy._attempt.stage)
  end)

  it("re-quotes rather than confirming when the price moved over the cap", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1400, 14000) -- 1400/unit, over the 1300 cap
    assert.equal("requote", GC.Buy._attempt.stage)
    assert.same({}, confirmed)
    assert.is_nil(GC.PurchaseSlot.Owner())
    -- ...and the click that follows asks the auction house again instead of buying.
    click(rowWithText("Alpha Herb"))
    assert.same({}, confirmed)
    assert.same({ 101, 101 }, searches)
  end)

  -- Step 4: the terminal events.

  it("records the purchase against the run and the acquisition store, then advances", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPurchaseSucceeded()

    local line = runLine(101)
    assert.equal(101, line.itemID)
    assert.equal(10, line.bought)
    assert.equal(10200, line.spent)
    assert.equal(0, line.buy)
    assert.is_true(line.done)

    local batches = GC.Acquisitions.GetAll()
    assert.equal(1, #batches)
    assert.equal("goldcap_buy", batches[1].source)
    assert.equal("commodity:101", batches[1].positionKey)
    assert.equal(10, batches[1].originalQty)
    assert.equal(10200, batches[1].originalTotal)
    assert.equal("run-1", batches[1].runCode)
    assert.equal("Alpha Herb", batches[1].itemName)
    assert.equal("Tester-Realm", batches[1].character)

    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.is_nil(GC.Buy._attempt)
    -- Focus moves to the next line that still has something to buy, so Enter carries on.
    assert.equal(103, GC.Buy._focus)
  end)

  -- Spec rule 4: the site's ledger is where a run's real spend is reported, so a BUY purchase
  -- goes there as well as into the addon's own cost basis.
  it("writes a goldcap_buy ledger row for a purchase it confirmed", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPurchaseSucceeded()

    local rows = GC.Ledger.GetEntries()
    assert.equal(1, #rows)
    local row = rows[1]
    assert.equal("buy", row.kind)
    assert.equal("goldcap_buy", row.source)
    assert.equal(101, row.itemID)
    assert.equal("Alpha Herb", row.itemName)
    assert.equal(10, row.qty)
    assert.equal(10200, row.total)
    assert.equal(0, row.cut)
    assert.equal(0, row.deposit)
    assert.is_false(row.pending)
    assert.equal("run-1", row.runCode)
    assert.equal(now, row.at)
    assert.equal("Tester-Realm", row.char)
    assert.equal("eu", row.region)
    -- No natural dedupe key exists -- two identical buys a second apart are two real buys -- so
    -- the key carries a counter, exactly as a sniper buy's does.
    assert.is_truthy(row.key:find("buyrun", 1, true))
  end)

  -- The gold left the bags whichever way the success arrived.
  it("writes the same row for a success it had already given up on", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    now = now + 21
    timers[#timers].fn()
    deliver(101, 10)
    GC.Buy.OnCommodityPurchaseSucceeded()

    local rows = GC.Ledger.GetEntries()
    assert.equal(1, #rows)
    assert.equal("goldcap_buy", rows[1].source)
    assert.equal(10200, rows[1].total)
    assert.equal("run-1", rows[1].runCode)
  end)

  -- A buy has no natural dedupe key, so the counter in the key is what keeps two purchases in
  -- the same second from collapsing into one row (GC.Ledger.Append merges on the key).
  it("gives two purchases two rows", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPurchaseSucceeded()

    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    click(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityPriceUpdated(2500, 10000)
    click(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityPurchaseSucceeded()

    local rows = GC.Ledger.GetEntries()
    assert.equal(2, #rows)
    assert.not_equal(rows[1].key, rows[2].key)
    assert.equal(103, rows[2].itemID)
  end)

  it("gives the slot back on a failure and on an unavailable price", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPurchaseFailed()
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.equal("failed", GC.Buy._attempt.stage)

    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUnavailable()
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.equal("failed", GC.Buy._attempt.stage)
  end)

  -- The sniper's drain releases its slot while a late terminal event can still be on its way,
  -- and Core/Init.lua routes terminal events here whenever BUY owns the slot. A window that
  -- believed one would record a purchase nobody made.
  it("records nothing and releases nothing for a success it never started", function()
    GC.PurchaseSlot.Claim("sniper", now)
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.same({}, GC.Acquisitions.GetAll())
    assert.equal("sniper", GC.PurchaseSlot.Owner())

    GC.PurchaseSlot.Release("sniper")
    GC.Buy.OnCommodityPriceUpdated(1, 1)
    GC.Buy.OnCommodityPurchaseFailed()
    assert.same({}, GC.Acquisitions.GetAll())
    assert.is_nil(GC.Buy._attempt)
  end)

  it("ignores a commodity result for an item it is not quoting", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(103)
    assert.equal("quoting", GC.Buy._attempt.stage)
    assert.is_nil(GC.Buy._attempt.qty)
  end)

  -- Core/PurchaseCapture.lua hooks StartCommoditiesPurchase for the player's OWN auction-house
  -- buys. Left alone it would file a second, `auction_house` batch for every BUY purchase --
  -- the same gold counted twice in the Sell tab's cost basis.
  it("keeps the passive purchase capture out of its own purchases", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    assert.is_true(GC.Buy.OwnsCommodityPurchase(101, 10))
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, 9))
    assert.is_false(GC.Buy.OwnsCommodityPurchase(102, 10))
    -- ...and it stops owning it the moment the attempt is over.
    GC.Buy.OnCommodityPurchaseFailed()
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, 10))
  end)

  it("files exactly one batch when the capture hooks are live too", function()
    local hooks = {}
    GC.PurchaseCapture.Init({
      hooksecurefunc = function(_, name, fn) hooks[name] = fn end,
      time = function() return now end,
      after = function() end,
    }, GC.Ledger.Context)

    -- Exactly the client's own order: Start (hook), the price event, Confirm (hook), success.
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    hooks.StartCommoditiesPurchase(101, 10)
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    GC.PurchaseCapture.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    hooks.ConfirmCommoditiesPurchase(101, 10)
    GC.Buy.OnCommodityPurchaseSucceeded()
    GC.PurchaseCapture.OnCommodityPurchaseSucceeded()

    local batches = GC.Acquisitions.GetAll()
    assert.equal(1, #batches)
    assert.equal("goldcap_buy", batches[1].source)
    -- ...and no half-known row either: a pending acquisition is a second claim on the same gold.
    assert.same({}, GC.Acquisitions.GetPending(GC.Ledger.Context()))
  end)

  -- Step 5: the Enter key.

  it("buys the focused line on Enter, and lets every other key through", function()
    local container = containerOf()
    assert.is_truthy(container.scripts.OnKeyDown)

    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)

    -- Mouse not over the window: the key belongs to whatever normally receives it.
    container.mouseOver = false
    container.scripts.OnKeyDown(container, "ENTER")
    assert.is_true(container.propagate)
    assert.same({}, started)

    container.mouseOver = true
    container.scripts.OnKeyDown(container, "W")
    assert.is_true(container.propagate)
    assert.same({}, started)

    container.scripts.OnKeyDown(container, "ENTER")
    assert.is_false(container.propagate)
    assert.same({ { itemID = 101, quantity = 10 } }, started)
  end)

  -- C1/I1: a price update after the confirm click is the server RE-QUOTING. No terminal event
  -- ever follows one, so a handler that only listened in "started" left the attempt owned, the
  -- button on "confirming...", and the shared slot held until /reload.
  it("takes a second price update after the confirm click and asks again", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    assert.equal("confirming", GC.Buy._attempt.stage)

    GC.Buy.OnCommodityPriceUpdated(1200, 12000) -- still inside the 1300 cap
    assert.equal("confirm", GC.Buy._attempt.stage)
    assert.equal(12000, GC.Buy._attempt.serverTotal)
    assert.equal("CONFIRM", rowWithText("Alpha Herb").action.label)
    assert.equal("1g20s", rowWithText("Alpha Herb").cells.cost:GetText())
    assert.equal(1, #confirmed) -- the event confirmed nothing by itself

    -- ...and the click that follows agrees to the NEW price.
    click(rowWithText("Alpha Herb"))
    assert.equal(2, #confirmed)
    assert.equal("confirming", GC.Buy._attempt.stage)
  end)

  it("requotes and frees the slot when the re-quote after a confirm click leaves the cap", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1400, 14000)
    assert.equal("requote", GC.Buy._attempt.stage)
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, 10))
  end)

  -- I1: the confirm click may never agree to a total nothing has judged.
  it("refuses to confirm a price that moved over the cap while waiting for the click", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    assert.equal("confirm", GC.Buy._attempt.stage)
    GC.Buy.OnCommodityPriceUpdated(1400, 14000)
    assert.equal("requote", GC.Buy._attempt.stage)

    click(rowWithText("Alpha Herb"))
    assert.same({}, confirmed)
  end)

  -- C1: a stage waiting on a person needs a way out too, or the slot and the capture stand-down
  -- outlive the attempt.
  it("gives the slot back when nobody ever clicks confirm", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    local watchdog = timers[#timers]
    assert.equal(20, watchdog.seconds)
    watchdog.fn()
    assert.equal("expired", GC.Buy._attempt.stage)
    assert.is_nil(GC.PurchaseSlot.Owner())
  end)

  -- Confirm reached the server, so the units may already be paid for: the slot goes back, but the
  -- line is never offered again for a click that could buy them twice.
  it("says nothing came back rather than offering a confirmed purchase for retry", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    assert.equal("unknown", GC.Buy._attempt.stage)
    assert.is_nil(GC.PurchaseSlot.Owner())
    -- Still ours as far as the passive capture is concerned: the success is owed, and the capture
    -- threw its own record away at the Start hook while this tab owned the purchase.
    assert.is_true(GC.Buy.OwnsCommodityPurchase(101, 10))
    local row = rowWithText("Alpha Herb")
    assert.equal("no answer — check your mail", row.action.label)
    assert.is_false(row.action:IsEnabled())
  end)

  -- An earlier arming must not retire a stage that has since moved on.
  it("lets a superseded watchdog expire quietly", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    local firstWatchdog = timers[#timers]
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    firstWatchdog.fn()
    assert.equal("confirm", GC.Buy._attempt.stage)
    assert.equal("buy", GC.PurchaseSlot.Owner())
  end)

  -- C1: no terminal event can arrive once the session is gone.
  it("gives the slot back when the auction house closes mid-purchase", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnAuctionHouseClosed()
    assert.equal("expired", GC.Buy._attempt.stage)
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, 10))
  end)

  it("drops a quote the closing auction house has made meaningless", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    GC.Buy.OnAuctionHouseClosed()
    assert.is_nil(GC.Buy._attempt)
    assert.equal("BUY 10", rowWithText("Alpha Herb").action.label)
  end)

  -- I2/3: reaching "confirm" is not reaching "confirming". A purchase landed that this tab never
  -- saw a price for -- the player confirmed on Blizzard's own buy page, or the event is somebody
  -- else's. Nothing is recorded (a cost basis from a total nobody was charged is worse than no
  -- row), and the attempt ENDS: left live, its CONFIRM button invites a second purchase and the
  -- watchdog later aims a Cancel at a purchase that already succeeded.
  it("ends the attempt and records nothing for a success it never priced", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    assert.equal("confirm", GC.Buy._attempt.stage)

    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.same({}, GC.Acquisitions.GetAll())
    assert.equal(0, GC.Buy.CurrentRun():Lines()[1].bought)
    assert.is_nil(GC.Buy._attempt)
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.same({}, confirmed)

    -- ...and the watchdog that was armed for the confirm click finds nothing left to cancel.
    timers[#timers].fn()
    assert.equal(0, cancels)
  end)

  -- N3: at `started` our own Start is still unconfirmed and dangling in the client, so it is ours
  -- to take back. At `confirm`/`confirming` it is not: the success may be its own answer, and the
  -- test above pins that nothing is cancelled there.
  it("takes back its own unconfirmed start when a purchase it never priced lands", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    assert.equal("started", GC.Buy._attempt.stage)

    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.equal(1, cancels)
    assert.is_nil(GC.Buy._attempt)
    assert.same({}, GC.Acquisitions.GetAll())
  end)

  -- I3: the client drops a throttled search without naming it, so a question with no answer has
  -- to age out -- otherwise the line sits on "quoting..." for the rest of the session.
  it("asks again when a quote query is never answered", function()
    hover(rowWithText("Alpha Herb"))
    assert.same({ 101 }, searches)
    assert.equal("quoting", GC.Buy._attempt.stage)

    now = now + 5
    hover(rowWithText("Alpha Herb"))
    assert.same({ 101 }, searches) -- still worth waiting for

    now = now + 6
    hover(rowWithText("Alpha Herb"))
    assert.same({ 101, 101 }, searches)
  end)

  -- C2, through the whole tab: what is delivered lands in the bags, and `have` and `bought` are
  -- then the same units. Subtracting both retired the line with four still to buy.
  it("keeps buying the remainder after a thin ladder fills only part of the line", function()
    setBook(101, { { unitPrice = 900, quantity = 6 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.equal(6, GC.Buy._attempt.qty)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(900, 5400)
    click(rowWithText("Alpha Herb"))
    deliver(101, 6)
    GC.Buy.OnCommodityPurchaseSucceeded()

    local line = GC.Buy.CurrentRun():Lines()[1]
    assert.equal(6, line.have)
    assert.equal(6, line.bought)
    assert.equal(4, line.buy)
    assert.is_false(line.done)
    assert.equal("BUY 4", rowWithText("Alpha Herb").action.label)
    -- ...and the run still counts those four as gold it expects to spend.
    assert.is_true(GC.Buy.CurrentRun():Totals().left > 0)
  end)

  -- M1: Enter is swallowed only once there is something for it to do. Deciding on the key and the
  -- cursor alone ate Enter -- and with it opening chat -- whenever the cursor sat over the board.
  it("hands Enter back when there is no line to act on", function()
    local container = containerOf()
    container.mouseOver = true
    GC.Buy._focus = nil
    keyDown("ENTER")
    assert.is_true(container.propagate)
    assert.same({}, started)

    -- A vendor line is focused but cannot be acted on: the key still belongs to the game.
    GC.Buy._focus = 102
    keyDown("ENTER")
    assert.is_true(container.propagate)
    assert.same({}, started)
  end)

  -- M2: a click on another line must not steal the focus from the one waiting for its confirm.
  it("keeps the focus on the line waiting to be confirmed", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)

    click(rowWithText("Charlie Dust"))
    assert.equal(101, GC.Buy._focus)
    assert.equal("confirm", GC.Buy._attempt.stage)

    local container = containerOf()
    container.mouseOver = true
    keyDown("ENTER")
    assert.same({ { itemID = 101, quantity = 10 } }, confirmed)
  end)

  -- M4: rows are pooled and repainted on every render. SetVariant puts the variant's own live
  -- colours back, and Disable() on an already-disabled button fires nothing -- so a button that
  -- cannot be clicked came back looking exactly as clickable as its neighbours.
  it("keeps a disabled button looking disabled across a repaint", function()
    setBook(101, { { unitPrice = 2000, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local row = rowWithText("Alpha Herb")
    assert.is_false(row.action:IsEnabled())
    assert.equal("dim", row.action.painted)

    GC.Buy.RefreshIfShown()
    row = rowWithText("Alpha Herb")
    assert.is_false(row.action:IsEnabled())
    assert.equal("dim", row.action.painted)
  end)

  -- 1: a real close fires BOTH session exits (Core/Init.lua routes both on purpose). The second
  -- call used to clear `unknown` -- the one state whose whole job is to warn that a confirm may
  -- have taken gold -- before the player could read it.
  it("keeps the no-answer warning when the close fires twice", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))

    GC.Buy.OnAuctionHouseClosed()
    assert.equal("unknown", GC.Buy._attempt.stage)
    GC.Buy.OnAuctionHouseClosed()
    assert.equal("unknown", GC.Buy._attempt.stage)
    assert.equal("no answer — check your mail", rowWithText("Alpha Herb").action.label)
  end)

  it("keeps a timed-out line's warning when the close fires twice", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    assert.equal("expired", GC.Buy._attempt.stage)
    GC.Buy.OnAuctionHouseClosed()
    GC.Buy.OnAuctionHouseClosed()
    assert.equal("expired", GC.Buy._attempt.stage)
  end)

  -- 2: the confirming timeout gives up, and the success turns up anyway. The gold left the bags,
  -- so the books have to say so -- at the total the server last quoted.
  it("books the late success of a purchase it had given up on", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    now = now + 21
    timers[#timers].fn()
    assert.equal("unknown", GC.Buy._attempt.stage)

    deliver(101, 10)
    GC.Buy.OnCommodityPurchaseSucceeded()

    local batches = GC.Acquisitions.GetAll()
    assert.equal(1, #batches)
    assert.equal("goldcap_buy", batches[1].source)
    assert.equal(10200, batches[1].originalTotal)
    assert.equal(10, batches[1].originalQty)
    assert.equal("run-1", batches[1].runCode)
    assert.equal(10, runLine(101).bought)
    assert.is_nil(GC.Buy._attempt)
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, 10))
  end)

  it("books a stranded success only once", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    GC.Buy.OnCommodityPurchaseSucceeded()
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("forgets a stranded confirm the session can no longer answer for", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    GC.Buy.OnAuctionHouseClosed()
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.same({}, GC.Acquisitions.GetAll())
  end)

  -- 4: GC.PurchaseSlot expires a claim MAX_SECONDS after it was STAMPED, while these watchdogs
  -- are armed from now. A confirm click late in the window would otherwise be watched past the
  -- moment the claim goes stale, and the Sniper could take the slot out from under a purchase
  -- this tab is still holding.
  it("keeps the claim alive for as long as it watches the purchase", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    assert.equal("buy", GC.PurchaseSlot.Owner())

    now = now + 19
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    assert.equal("confirm", GC.Buy._attempt.stage)

    -- 35s after the slot was first claimed, 16s after the arming re-stamped it.
    now = now + 16
    assert.is_false(GC.PurchaseSlot.Claim("sniper"))
    assert.equal("buy", GC.PurchaseSlot.Owner())
  end)

  -- 5: a line whose confirm may have taken gold is not handed back for another click until
  -- something says what happened.
  it("does not re-quote a line whose purchase never answered", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    now = now + 60
    local before = #searches

    hover(rowWithText("Alpha Herb"))
    click(rowWithText("Alpha Herb"))
    assert.equal(before, #searches)
    assert.equal("unknown", GC.Buy._attempt.stage)
  end)

  it("offers the line again once the bags say what happened", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    now = now + 60

    -- The units turn up after all: BAG_UPDATE_DELAYED recounts, and the line is a line again.
    deliver(101, 4)
    GC.Buy.OnBagsChanged()
    local before = #searches
    hover(rowWithText("Alpha Herb"))
    assert.equal(before + 1, #searches)
  end)

  it("offers the line again in the next auction house session", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
    now = now + 60

    GC.Buy.OnAuctionHouseShow()
    assert.is_nil(GC.Buy._attempt)
    local before = #searches
    hover(rowWithText("Alpha Herb"))
    assert.equal(before + 1, #searches)
  end)

  -- 6: a question the client swallowed has to offer the click that asks it again.
  it("offers a quote again once the query it sent has gone unanswered", function()
    hover(rowWithText("Alpha Herb"))
    assert.equal("...", rowWithText("Alpha Herb").action.label)
    assert.is_false(rowWithText("Alpha Herb").action:IsEnabled())

    now = now + 11
    GC.Buy.RefreshIfShown()
    local row = rowWithText("Alpha Herb")
    assert.equal("BUY 10", row.action.label)
    assert.is_true(row.action:IsEnabled())
    click(row)
    assert.same({ 101, 101 }, searches)
  end)

  -- 7: a line with no market value has no cap, and an absent cap is not permission. The quote is
  -- then the only number anybody checked.
  it("holds a capless line to the total the player was quoted", function()
    local row = rowWithText("Echo Salt")
    hover(row)
    GC.Buy.OnCommodityResults(105)
    assert.is_nil(GC.Buy.CurrentRun():Lines()[3].cap)
    assert.equal(5 * 400, GC.Buy._attempt.total)
    click(rowWithText("Echo Salt"))

    GC.Buy.OnCommodityPriceUpdated(500, 2500) -- above the 2000 quoted, and nothing caps it
    assert.equal("requote", GC.Buy._attempt.stage)
    assert.equal(1, cancels)
    assert.is_nil(GC.PurchaseSlot.Owner())

    click(rowWithText("Echo Salt"))
    assert.same({}, confirmed)
  end)

  it("confirms a capless line at no more than the quote", function()
    hover(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityResults(105)
    click(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityPriceUpdated(400, 2000)
    assert.equal("confirm", GC.Buy._attempt.stage)
  end)

  -- 7: the run was swapped under the purchase. There is nothing left to judge the price against
  -- and nothing to credit the units to.
  it("hands the purchase back when the line it was for is gone", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.SelectRun("run-2")
    assert.equal("run-2", GC.Buy.CurrentRun():Code())

    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    assert.is_nil(GC.Buy._attempt)
    assert.equal(1, cancels)
    assert.is_nil(GC.PurchaseSlot.Owner())
    assert.same({}, GC.Acquisitions.GetAll())

    -- N4: and `/gc buy` can still say WHICH line it was about. The id is the last honest name --
    -- logging after the attempt was cleared left the only record of it reading "?".
    local last = GC.Buy._log[#GC.Buy._log]
    assert.equal(101, last.itemID)
    assert.equal("#101 · the run changed — start again", last.text)
  end)

  -- R1: the whole late-success path lives on the far side of Core/Init.lua's router, and the
  -- router used to hand it to the Sniper -- BUY releases the slot on its way out of a stranded
  -- confirm, so a route gated on slot ownership could never reach it.
  local function strandOne()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn()
  end

  it("routes a late success to the tab that is owed it, not to the sniper", function()
    local onEvent = loadRouter()
    strandOne()
    assert.is_nil(GC.PurchaseSlot.Owner())

    onEvent(nil, "COMMODITY_PURCHASE_SUCCEEDED")
    assert.same({}, sniperCalls)
    local batches = GC.Acquisitions.GetAll()
    assert.equal(1, #batches)
    assert.equal(10200, batches[1].originalTotal)
  end)

  it("hands a commodity event the tab has no claim on straight to the sniper", function()
    local onEvent = loadRouter()
    onEvent(nil, "COMMODITY_PURCHASE_SUCCEEDED")
    onEvent(nil, "COMMODITY_PURCHASE_FAILED")
    onEvent(nil, "COMMODITY_PRICE_UNAVAILABLE")
    onEvent(nil, "COMMODITY_PRICE_UPDATED", 1, 2)
    assert.same({ "succeeded", "failed", "unavailable", "priceUpdated" }, sniperCalls)
    assert.same({}, GC.Acquisitions.GetAll())
  end)

  it("routes a late failure to the tab too, and clears the warning it left", function()
    local onEvent = loadRouter()
    strandOne()
    onEvent(nil, "COMMODITY_PURCHASE_FAILED")
    assert.same({}, sniperCalls)
    assert.same({}, GC.Acquisitions.GetAll())

    -- The purchase did not happen, so the line is a line again.
    local row = rowWithText("Alpha Herb")
    assert.equal("purchase failed — try again", row.action.label)
    local before = #searches
    hover(rowWithText("Alpha Herb"))
    assert.equal(before + 1, #searches)
  end)

  it("routes a live purchase's own events to the tab that holds the slot", function()
    local onEvent = loadRouter()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    onEvent(nil, "COMMODITY_PRICE_UPDATED", 1020, 10200)
    assert.same({}, sniperCalls)
    assert.equal("confirm", GC.Buy._attempt.stage)
  end)

  -- A stranded record may never take an event from somebody holding the slot: that purchase owns
  -- its own terminals. ANY live claim, stale or not -- the Sniper claims once at its buy click and
  -- never re-stamps, so its own success can land past GC.PurchaseSlot.MAX_SECONDS with its claim
  -- no longer reported busy but still in place.
  it("leaves the sniper's own events alone while it holds the slot", function()
    local onEvent = loadRouter()
    strandOne()
    GC.PurchaseSlot.Claim("sniper", now)
    onEvent(nil, "COMMODITY_PURCHASE_SUCCEEDED")
    assert.same({ "succeeded" }, sniperCalls)
    assert.same({}, GC.Acquisitions.GetAll())

    GC.PurchaseSlot.Release("sniper")
    GC.PurchaseSlot.Claim("sniper", now - 31)
    assert.is_false(GC.PurchaseSlot.IsBusy())
    onEvent(nil, "COMMODITY_PURCHASE_SUCCEEDED")
    assert.same({ "succeeded", "succeeded" }, sniperCalls)
    assert.same({}, GC.Acquisitions.GetAll())
    assert.is_truthy(GC.Buy._stranded[101])
  end)

  -- Item 3: with a stranded confirm on BOTH sides, a success carries nothing that could say whose it
  -- is. BUY says no and the Sniper gets it, exactly as two records of BUY's own would be refused.
  it("hands a success to the sniper when both windows have a stranded confirm", function()
    local onEvent = loadRouter()
    strandOne()
    sniperStranded = true
    onEvent(nil, "COMMODITY_PURCHASE_SUCCEEDED")
    assert.same({ "succeeded" }, sniperCalls)
    assert.same({}, GC.Acquisitions.GetAll())
    assert.equal(0, GC.Buy.CurrentRun():Lines()[1].bought)
    assert.is_truthy(GC.Buy._stranded[101])
  end)

  -- Item 1: the button on a stranded line is disabled, and Enter has to agree with it -- swallowed,
  -- the keystroke did nothing; worse, it reached onBuyClick for a line the player may not touch.
  it("hands Enter back on a line whose confirm never answered", function()
    strandOne()
    assert.equal(101, GC.Buy._focus)
    local container = containerOf()
    container.mouseOver = true
    keyDown("ENTER")
    assert.is_true(container.propagate)
    assert.equal(1, #started)
    assert.equal(1, #confirmed)
  end)

  -- Item 2: a late FAILED answers exactly one stranded confirm, and only when that confirm is still
  -- the attempt on screen. Wiping every record on any failure lifted a warning on evidence about
  -- some other purchase -- including one whose success was still on its way.
  it("keeps both stranded records when a late failure cannot say which one it answers", function()
    strandOne()
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    click(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityPriceUpdated(2500, 10000)
    click(rowWithText("Charlie Dust"))
    timers[#timers].fn()
    assert.equal("unknown", GC.Buy._attempt.stage)

    assert.is_false(GC.Buy.OnCommodityPurchaseFailed())
    assert.is_truthy(GC.Buy._stranded[101])
    assert.is_truthy(GC.Buy._stranded[103])
    assert.equal("unknown", GC.Buy._attempt.stage)
    assert.equal("no answer — check your mail", rowWithText("Alpha Herb").action.label)
  end)

  it("keeps a stranded record a failure cannot be pinned to the attempt for", function()
    strandOne()
    GC.Buy._attempt = nil
    assert.is_false(GC.Buy.OnCommodityPurchaseFailed())
    assert.is_truthy(GC.Buy._stranded[101])
    assert.equal("no answer — check your mail", rowWithText("Alpha Herb").action.label)

    -- The player has moved on to another line: the attempt is that line's, and says nothing
    -- about the one that went unanswered.
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    assert.equal("quoted", GC.Buy._attempt.stage)
    assert.is_false(GC.Buy.OnCommodityPriceUnavailable())
    assert.is_truthy(GC.Buy._stranded[101])
    assert.equal("quoted", GC.Buy._attempt.stage)
  end)

  -- `/gc buy` names the item even when its line is gone: the record knows the id.
  it("names the item when it drops what it cannot attribute", function()
    strandOne()
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    click(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityPriceUpdated(2500, 10000)
    click(rowWithText("Charlie Dust"))
    timers[#timers].fn()
    GC.Buy.SelectRun("run-2")
    assert.is_nil(GC.Buy._attempt)

    GC.Buy.OnCommodityPurchaseSucceeded()
    local last = GC.Buy._log[#GC.Buy._log]
    assert.is_true(last.itemID == 101 or last.itemID == 103)
    assert.is_nil(last.text:find("?", 1, true))
    assert.is_truthy(last.text:find("could not attribute", 1, true))
  end)

  -- S1: one slot let a second strand overwrite the first, and the first one's late success was
  -- then booked as the wrong item at the wrong price.
  it("keeps one stranded record per item", function()
    strandOne()
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    click(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityPriceUpdated(2500, 10000)
    click(rowWithText("Charlie Dust"))
    timers[#timers].fn()
    assert.is_truthy(GC.Buy._stranded[101])
    assert.is_truthy(GC.Buy._stranded[103])
  end)

  -- ...and with two live, a commodity event carries nothing that could say which one it answers.
  it("records nothing when two stranded confirms could each be the one that landed", function()
    strandOne()
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    click(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityPriceUpdated(2500, 10000)
    click(rowWithText("Charlie Dust"))
    timers[#timers].fn()

    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.same({}, GC.Acquisitions.GetAll())
    assert.is_nil(next(GC.Buy._stranded))
    assert.equal(0, GC.Buy.CurrentRun():Lines()[1].bought)
  end)

  it("forgets a stranded confirm that has aged out", function()
    strandOne()
    now = now + 601
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.same({}, GC.Acquisitions.GetAll())
    assert.is_nil(next(GC.Buy._stranded))
  end)

  it("does not claim a purchase of another item, or another quantity of its own", function()
    strandOne()
    assert.is_true(GC.Buy.OwnsCommodityPurchase(101, 10))
    assert.is_false(GC.Buy.OwnsCommodityPurchase(103, 10))
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, 4))
    -- A nil quantity means "any" only for a purchase actually in flight, never for a record.
    assert.is_false(GC.Buy.OwnsCommodityPurchase(101, nil))
  end)

  -- U1: the warning used to live on the attempt, which the very next hover replaces.
  it("keeps the warning on the line when the cursor moves to another one", function()
    strandOne()
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)

    local before = #searches
    hover(rowWithText("Alpha Herb"))
    assert.equal(before, #searches)
    local row = rowWithText("Alpha Herb")
    assert.equal("no answer — check your mail", row.action.label)
    assert.is_false(row.action:IsEnabled())
    click(row)
    assert.equal(before, #searches)
  end)

  it("keeps the last twenty attempt lines", function()
    for _ = 1, 12 do
      hover(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      click(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityPurchaseFailed()
      now = now + 30
    end
    assert.is_true(#GC.Buy._log <= 20)
    assert.is_true(#GC.Buy._log > 0)
  end)

  -- Review item 3: a gear, pet or recipe line answers the ITEM buffer, not the commodity one, so
  -- the ladder probe comes back empty and the quote was qty 0 -- which the button reported as
  -- "nothing on offer" while Blizzard's own pane showed a full list of lots. Never bought
  -- anything, but said something false about the market.
  it("says a line the client will not sell as a commodity has to be bought by hand", function()
    _G.C_AuctionHouse.GetItemKeyInfo = function(key) return { isCommodity = key.itemID ~= 103 } end
    setBook(103, {})
    local before = #searches
    hover(rowWithText("Charlie Dust"))
    -- Settled at the ask: the client answers a gear key with ITEM_SEARCH_RESULTS_UPDATED, which
    -- never reaches this tab, so no commodity event is needed (or waited for) to say so. The
    -- search itself still goes, because it is what opens Blizzard's own page for the player.
    local row = rowWithText("Charlie Dust")
    assert.equal(before + 1, #searches)
    assert.equal("quoted", GC.Buy._attempt.stage)
    assert.equal("not a commodity — buy by hand", row.action.label)
    assert.is_false(row.action:IsEnabled())
    GC.Buy.OnCommodityResults(103)
    row = rowWithText("Charlie Dust")
    assert.equal("not a commodity — buy by hand", row.action.label)
    assert.is_false(row.action:IsEnabled())

    -- ...and a commodity line with an empty book still says the honest thing about the book.
    setBook(105, {})
    hover(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityResults(105)
    assert.equal("nothing on offer", rowWithText("Echo Salt").action.label)
  end)

  -- Review item 5: the cap stopping the ladder PART-WAY was silent -- a plain "BUY 6 · ..." and
  -- nothing about the four units it refused. The label stays inside the 72px badge, so the
  -- percentage rides on the log line `/gc buy` prints and the button wears the over-cap look.
  it("says how far over usual the rest is when only part of the line fits under the cap", function()
    setBook(101, { { unitPrice = 900, quantity = 6 }, { unitPrice = 2000, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local attempt = GC.Buy._attempt
    assert.equal(6, attempt.qty)
    assert.is_true(attempt.capped)
    assert.equal(100, attempt.overPct) -- 2000 against a 1000 usual

    local row = rowWithText("Alpha Herb")
    assert.equal("BUY 6", row.action.label)
    assert.equal("5400c", row.cells.cost:GetText())
    assert.is_true(row.action:IsEnabled()) -- the part that fits is still buyable
    assert.equal("warn", row.action.variant)
    assert.is_truthy(GC.Buy._log[#GC.Buy._log].text:find("▲100% over usual", 1, true))
  end)

  -- Review item 10: while the client holds a purchase of ours, neither onBuyClick nor quote will
  -- act for any other line -- so every other button read "BUY n", enabled, and did nothing at all.
  it("disables the other lines while a purchase is waiting to be confirmed", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)

    local other = rowWithText("Charlie Dust")
    assert.equal("BUY 4", other.action.label)
    assert.is_false(other.action:IsEnabled())
    local before = #searches
    click(rowWithText("Charlie Dust"))
    assert.equal(before, #searches) -- and the disabled look is telling the truth
    assert.same({}, confirmed)

    -- Offered again the moment the purchase is over.
    click(rowWithText("Alpha Herb"))
    deliver(101, 10)
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.is_true(rowWithText("Charlie Dust").action:IsEnabled())
  end)

  -- Review item 7: SetPropagateKeyboardInput is combat-protected, and this container holds the
  -- keyboard for as long as the tab is up -- including the standalone window, which outlives the
  -- auction house and can be open in a fight.
  it("touches nothing on a keystroke in combat", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local container = containerOf()
    container.mouseOver = true

    _G.InCombatLockdown = function() return true end
    keyDown("ENTER")
    assert.is_nil(container.propagate)
    assert.same({}, started)

    _G.InCombatLockdown = function() return false end
    keyDown("ENTER")
    assert.is_false(container.propagate)
    assert.same({ { itemID = 101, quantity = 10 } }, started)
  end)

  -- Review item 11: `/gc buy` is asked "what happened when I clicked", and an attempt, a stranded
  -- confirm and the log all outlive the run being swapped away -- which is exactly when it is asked.
  it("still prints the attempt, the stranded confirms and the log with no run selected", function()
    strandOne()
    local printed = {}
    GC.Print = function(text) printed[#printed + 1] = text end
    GC.Buy.SelectRun(nil)
    assert.is_nil(GC.Buy.CurrentRun())

    GC.Buy.DebugPrint()
    local text = table.concat(printed, "\n")
    assert.is_truthy(text:find("Buy: no run selected.", 1, true))
    assert.is_truthy(text:find("attempt: stage=", 1, true))
    assert.is_truthy(text:find("stranded: 1", 1, true))
    assert.is_truthy(text:find("log: ", 1, true))
  end)
  -- An alert group's line carries the target price the player set, and a percentage of the
  -- site's usual price has nothing to say about it: a target BELOW usual -- which is what an
  -- alert group is for -- made the refusal read as a NEGATIVE amount over usual, a claim about
  -- the market that is both false and impossible to act on.
  local function showAlertRun(levels)
    GC.AppRuns._set({ { code = "a0000001", name = "Cheap ore", updatedAt = 900, origin = "app",
                        k = "alert", lines = { { i = 101, q = 4, u = 5800, cc = 4000 } } } })
    GC.db.settings.sniper.buyRun = "a0000001"
    setBook(101, levels)
    GC.Buy.Show()
  end

  it("measures a refused lot against the alert's own target, not against usual", function()
    showAlertRun({ { unitPrice = 4500, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local attempt = GC.Buy._attempt
    assert.equal(0, attempt.qty)
    assert.is_true(attempt.capped)
    assert.equal(12, attempt.overPct)          -- 4500 against the 4000 target, not the 5800 usual
    assert.equal("▲12% over the alert target", rowWithText("Alpha Herb").action.label)
  end)

  it("says the same on the log line when part of the line fit under the target", function()
    showAlertRun({ { unitPrice = 3900, quantity = 2 }, { unitPrice = 4500, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.equal(2, GC.Buy._attempt.qty)
    assert.equal("BUY 2", rowWithText("Alpha Herb").action.label)
    assert.is_truthy(GC.Buy._log[#GC.Buy._log].text:find("▲12% over the alert target", 1, true))
  end)

  -- A lot one copper over the target is not "0% over" anything, and a target the book never
  -- reached is not over it at all: neither is a reason, so the button says what it says when
  -- there is nothing to buy.
  it("says nothing rather than a percentage that is not over anything", function()
    showAlertRun({ { unitPrice = 4001, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.is_true(GC.Buy._attempt.capped)
    assert.is_nil(GC.Buy._attempt.overPct)
    assert.equal("nothing on offer", rowWithText("Alpha Herb").action.label)
  end)

  it("says nothing at all about a book that stayed under the target", function()
    showAlertRun({ { unitPrice = 3900, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.is_false(GC.Buy._attempt.capped)
    assert.is_nil(GC.Buy._attempt.overPct)
    assert.equal("BUY 4", rowWithText("Alpha Herb").action.label)
  end)
end)
