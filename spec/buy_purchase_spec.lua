local helper = require("spec.spec_helper")

-- The BUY tab's purchase: picking a line (a left click on its row) quotes it against the live
-- commodity book, the dock's one button starts the purchase for exactly the quoted quantity, and a
-- second press confirms the server's own price -- but only while that price is still inside the
-- line's cap.
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
    function r:SetAlpha(a)
      self.alpha = a
      if self.kind == "Texture" and self.vertexColor then self.vertexColor[4] = a end
    end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:SetAutoFocus(on) self.autoFocus = on end
    function r:HasFocus() return self.focused == true end
    function r:SetFocus() self.focused = true end
    function r:ClearFocus() self.focused = false end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:GetScript(name) return self.scripts[name] end
    function r:EnableMouse() end
    function r:RegisterEvent() end
    function r:UnregisterEvent() end
    function r:EnableKeyboard() self.keyboard = true end
    function r:SetPropagateKeyboardInput(value) self.propagate = value end
    function r:IsMouseOver() return self.mouseOver end
    function r:GetParent() return parent end
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

  -- GC.Buy._view is the one seam BUY exposes for specs (set at Attach); no upvalue chains.
  local function dock() return GC.Buy._view.dock end
  local function rowWithText(text)
    for _, row in ipairs(GC.Buy._view.rows) do
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

  local function containerOf() return GC.Buy._view.container end

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

  -- BUY 2.0: a left click on a row picks the line the dock buys, and asks for its price -- what a
  -- hover used to do. The hover now only explains the line.
  local function pick(row) row.scripts.OnMouseUp(row, "LeftButton") end
  local hover = pick
  -- The dock's one button, for the line on it. A test that "clicks" a row the dock is not on has
  -- to say so: `click` refuses, loudly, rather than pressing the dock for some other line.
  local function press() dock().buy.scripts.OnClick(dock().buy) end
  local function click(row)
    if dock().lineItemID ~= row.lineItemID then pick(row) end
    assert.equal(row.lineItemID, dock().lineItemID, "the dock is not on this row's line")
    press()
  end
  -- What the dock's button says for a row's line: the dock has to be on that line already.
  local function buttonFor(row)
    assert.equal(row.lineItemID, dock().lineItemID, "the dock is not on this row's line")
    return dock().buy
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
      SlicedTexture = function(parent) return region("Texture", parent) end,
      Chip = function(parent) return chip(parent) end,
      WithQuality = function(name) return name end,
      -- UI/Theme.lua's own: opens GameTooltip on the row, placed beside the window. Which window
      -- it was placed beside is kept on the tooltip for the hover specs.
      ItemTooltipOutside = function(row, window)
        _G.GameTooltip:SetOwner(row, "ANCHOR_NONE")
        _G.GameTooltip.besideWindow = window
      end,
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
    helper.loadModule("Core/NameMatch.lua", GC)
    helper.loadModule("Core/BuyView.lua", GC)
    helper.loadModule("Core/BuyDock.lua", GC)
    helper.loadModule("Core/BuyLots.lua", GC)
    helper.loadModule("Core/PurchaseSlot.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/PurchaseCapture.lua", GC)
    GC.Acquisitions.Init({})
    helper.loadModule("Core/DealMath.lua", GC)
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

  -- Caps fixes 4a, round 2: a search sent on top of an unanswered keys batch takes its answer
  -- and comes back empty itself (UI/SellFrame.lua's advanceQuote, seen in game) -- an empty quote
  -- here. So a hover waits for the batch (one still out from the Deals board, or this tab's own
  -- refresh) and is asked again once it is gone, while the line still has the focus.
  it("waits for an unanswered keys batch, then asks for the line still in focus", function()
    local out = true
    GC.Sniper._KeysOutstanding = function() return out end
    hover(rowWithText("Alpha Herb"))
    assert.same({}, searches)
    -- Caps fixes 5i: and says it is waiting. The button kept reading "BUY 4", clickable, while the
    -- quote it needs was held back -- for as long as thirty seconds behind a lost batch.
    local row = rowWithText("Alpha Herb")
    assert.equal("...", buttonFor(row).label)
    assert.is_false(buttonFor(row):IsEnabled())
    GC.Buy.Tick()
    assert.same({}, searches)
    out = false
    GC.Buy.Tick()
    assert.same({ 101 }, searches)
  end)

  -- ...and the other way round: this tab's own refresh batch does not go out over a hover quote
  -- still waiting for its answer, which it would take.
  it("sends no refresh batch over an unanswered quote", function()
    local batches = 0
    GC.Sniper._TrySendKeysBatchFor = function() batches = batches + 1; return true end
    hover(rowWithText("Alpha Herb"))
    assert.same({ 101 }, searches)
    now = now + 1 -- the refresh is due (none has run yet), the quote still on the wire
    GC.Buy.Tick()
    assert.equal(0, batches)
    GC.Buy.OnCommodityResults(101)
    GC.Buy.Tick()
    assert.equal(1, batches)
  end)

  it("quotes the missing quantity and what it costs, off the live ladder", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local attempt = GC.Buy._attempt
    assert.equal("quoted", attempt.stage)
    assert.equal(10, attempt.qty)                       -- 6 @ 900 + 4 @ 1200
    assert.equal(6 * 900 + 4 * 1200, attempt.total)
    assert.is_false(attempt.capped)
    assert.equal("BUY 10", buttonFor(rowWithText("Alpha Herb")).label)
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
    -- BUY 2.0: the dock says what the cheapest unit costs against the cap and offers to raise the
    -- cap to it (or skip the line); how far over usual that is rides on the log line `/gc buy`
    -- prints.
    assert.equal("the cheapest is 2000c, your cap is 1300c", dock().sub:GetText())
    assert.equal("RAISE CAP TO 2000c", buttonFor(rowWithText("Alpha Herb")).label)
    assert.equal("Skip", dock().second.label)
    assert.is_truthy(GC.Buy._log[#GC.Buy._log].text:find("▲100% over usual", 1, true))
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
    pick(rowWithText("Bravo Ore"))
    assert.is_false(buttonFor(rowWithText("Bravo Ore")):IsShown())
    assert.same({}, searches)
    assert.is_nil(GC.Buy._attempt)
  end)

  it("offers an enabled BUY button for the quantity still missing", function()
    local row = rowWithText("Alpha Herb")
    assert.equal("BUY 10", buttonFor(row).label)
    assert.is_true(buttonFor(row):IsEnabled())
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

  -- Final money review n1: and says so on the button, dark, as the Sniper's Buy waits over a BUY
  -- purchase in flight -- not a lit "BUY n" whose click only prints a refusal.
  it("waits, dark, while the sniper holds a purchase it started", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    GC.PurchaseSlot.Claim("sniper", now)
    GC.Buy.RefreshIfShown()
    local row = rowWithText("Alpha Herb")
    assert.equal("waiting...", buttonFor(row).label)
    assert.is_false(buttonFor(row):IsEnabled())
  end)

  -- Load-bearing round (M-1): and reads BUY again the moment the Sniper lets go, from the auction
  -- house ticker -- not on this tab's next refresh, up to twenty seconds later.
  it("reads BUY again as soon as the sniper lets go of the slot", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    GC.PurchaseSlot.Claim("sniper", now)
    GC.Buy.RefreshIfShown()
    GC.Buy.TickCountdown() -- the ticker sees the wait
    assert.equal("waiting...", buttonFor(rowWithText("Alpha Herb")).label)

    GC.PurchaseSlot.Release("sniper")
    GC.Buy.TickCountdown()

    assert.equal("BUY 10", buttonFor(rowWithText("Alpha Herb")).label)
  end)

  -- Load-bearing round (M-3): its own confirm the close hit holds this tab too, and the line keeps
  -- saying what it said, while the units may still come by mail -- not a fresh BUY at reopen.
  it("holds its own Starts, and the line's warning, on a confirm the auction house closed on", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb")) -- confirm at 2000: owed until 2020
    now = now + 5
    GC.Buy.OnAuctionHouseClosed()
    GC.Buy.OnAuctionHouseShow()
    GC.Buy.RefreshIfShown()
    assert.equal("unknown", GC.Buy._attempt.stage)
    assert.equal(GC.L["no answer — check your mail"], buttonFor(rowWithText("Alpha Herb")).label)

    local before = #started
    hover(rowWithText("Charlie Dust"))
    GC.Buy.OnCommodityResults(103)
    click(rowWithText("Charlie Dust"))
    assert.equal(before, #started)
  end)

  -- Final money review M3: a confirm the auction house closed on is owed its answer across the
  -- reopen, for as long as BUY would have waited for it -- as a Sniper confirm carried across a close
  -- holds BUY. It went to "unknown" and stopped counting at once, and the Sniper could start while
  -- BUY's purchase might still take the gold its checks were counting.
  it("still owes a confirm the auction house closed on, until its own wait would have ended", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb")) -- confirm at 2000: waited for until 2020
    now = now + 5
    GC.Buy.OnAuctionHouseClosed()
    GC.Buy.OnAuctionHouseShow()
    now = now + 1

    assert.is_true(GC.Buy.ConfirmOwed())
    assert.equal("buy", GC.PurchaseSlot.ConfirmOwed())
    now = 2020
    assert.is_false(GC.Buy.ConfirmOwed())
    assert.is_nil(GC.PurchaseSlot.ConfirmOwed())
  end)

  -- Fix round 2: a slot claim goes stale after GC.PurchaseSlot.MAX_SECONDS, but a purchase the
  -- Sniper confirmed can stay owed its answer longer than that (its stranded release waits 35 s,
  -- and one carried across an auction house close keeps the claim it had). BUY took the stale
  -- claim over and started a purchase of its own on top of one that may already have taken gold.
  describe("while a purchase the sniper confirmed is still owed its answer", function()
    local owed
    before_each(function()
      owed = { confirmed = true }
      GC.Sniper._ConfirmedOwed = function() return owed end
      hover(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      GC.PurchaseSlot.Claim("sniper", now - 31) -- claimed at its Start, 31 s ago: stale
    end)

    it("does not start, even over the sniper's stale claim", function()
      click(rowWithText("Alpha Herb"))
      assert.same({}, started)
      assert.equal("sniper", GC.PurchaseSlot.Owner())
    end)

    it("says it is waiting on the button that would start, not BUY", function()
      GC.Buy.RefreshIfShown()
      local row = rowWithText("Alpha Herb")
      -- ASCII, like its neighbours "buying...", "confirming..." and "..." (fix round 3, n3).
      assert.equal("waiting...", buttonFor(row).label)
      assert.is_false(buttonFor(row):IsEnabled())
    end)

    it("starts once that purchase has its answer", function()
      owed = nil
      GC.Buy.RefreshIfShown()
      local row = rowWithText("Alpha Herb")
      assert.equal("BUY 10", buttonFor(row).label)
      click(row)
      assert.same({ { itemID = 101, quantity = 10 } }, started)
    end)
  end)

  -- The other direction of the same rule: the sniper asks too (GC.PurchaseSlot.ConfirmOwed).
  it("says its own confirmed purchase is owed its answer, and only while it is", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    assert.is_false(GC.Buy.ConfirmOwed()) -- started, not confirmed
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb")) -- confirm
    assert.is_true(GC.Buy.ConfirmOwed())
    assert.equal("buy", GC.PurchaseSlot.ConfirmOwed())
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.is_false(GC.Buy.ConfirmOwed())
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

  it("gives the slot back when the purchase never answers, once its drain is over", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    local watchdog = timers[#timers]
    assert.equal(10, watchdog.seconds)
    watchdog.fn()
    assert.equal("expired", GC.Buy._attempt.stage)
    assert.equal("buy", GC.PurchaseSlot.Owner()) -- held for the drain (below)
    local drain = timers[#timers]
    assert.equal(20, drain.seconds)
    drain.fn()
    assert.is_nil(GC.PurchaseSlot.Owner())
  end)

  -- Final money review I1: a Start cancelled before the server answered it still has that answer
  -- coming, and commodity events name no attempt. BUY released the slot at once; the Sniper could
  -- start in the gap and BUY's late quote reached it (the reverse way round: the Sniper's late quote
  -- lit BUY's CONFIRM at a total BUY never quoted). The slot stays BUY's until that Start's drain
  -- is over: its late quote consumed here, or the drain's own bound -- and BUY starts nothing of its
  -- own meanwhile, which that quote would otherwise be read as the answer to.
  describe("a Start it cancelled before the server answered it", function()
    local function cancelledUnanswered()
      hover(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      click(rowWithText("Alpha Herb"))
      timers[#timers].fn() -- the watchdog: no answer in ten seconds
      assert.equal("expired", GC.Buy._attempt.stage)
      assert.equal(1, cancels)
    end

    it("keeps the slot until its late quote has been drained, and never lights CONFIRM on it", function()
      cancelledUnanswered()
      assert.equal("buy", GC.PurchaseSlot.Owner())
      assert.is_false(GC.PurchaseSlot.Claim("sniper", now)) -- the Sniper cannot start under it

      assert.is_true(GC.Buy.OnCommodityPriceUpdated(1020, 10200)) -- the late quote: BUY's to drain

      assert.equal("expired", GC.Buy._attempt.stage)
      assert.is_nil(GC.Buy._attempt.serverTotal)
      assert.equal(2, cancels) -- the Cancel sent again
      assert.are_not.equal("CONFIRM", buttonFor(rowWithText("Alpha Herb")).label)
      assert.is_nil(GC.PurchaseSlot.Owner())
      assert.is_true(GC.PurchaseSlot.Claim("sniper", now))
    end)

    it("drains a late failure the same way", function()
      cancelledUnanswered()
      assert.is_true(GC.Buy.OnCommodityPurchaseFailed())
      assert.is_nil(GC.PurchaseSlot.Owner())
    end)

    it("starts nothing of its own while it drains", function()
      cancelledUnanswered()
      hover(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101) -- a fresh quote
      click(rowWithText("Alpha Herb"))
      assert.equal(1, #started)
      assert.equal("waiting...", buttonFor(rowWithText("Alpha Herb")).label)
    end)
  end)

  -- Step 3: the server's price, and the click that confirms it.

  it("asks for a confirming click when the server price is inside the cap", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    assert.equal("confirm", GC.Buy._attempt.stage)
    assert.same({}, confirmed) -- nothing is confirmed by the event itself
    assert.equal("CONFIRM", buttonFor(rowWithText("Alpha Herb")).label)
    assert.equal("1g02s", rowWithText("Alpha Herb").cells.cost:GetText())

    click(rowWithText("Alpha Herb"))
    assert.same({ { itemID = 101, quantity = 10 } }, confirmed)
    assert.equal("confirming", GC.Buy._attempt.stage)
  end)

  -- Fix round 4 (m2): the CONFIRM a quote leaves waits twenty seconds -- no longer than the
  -- server's own quote when the client can say how long that is -- and shows the seconds left once
  -- ten remain, as Blizzard's own buy dialog does, from the auction house ticker.
  describe("the CONFIRM a quote leaves", function()
    local function atConfirm()
      hover(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      click(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityPriceUpdated(1020, 10200)
      assert.equal("confirm", GC.Buy._attempt.stage)
    end
    after_each(function() if _G.C_AuctionHouse then _G.C_AuctionHouse.GetQuoteDurationRemaining = nil end end)

    -- Fix round 5 (m1), BUY 2.0: on the dock's second line, beside Blizzard's price, never on the
    -- button -- "CONFIRM (9)" clipped the digit in seven languages.
    it("counts down its last ten seconds beside Blizzard's price, leaving CONFIRM as it is", function()
      atConfirm()
      assert.equal("Blizzard's price: 1g02s", dock().sub:GetText())
      now = now + 8 -- 12 s left: nothing yet
      GC.Buy.TickCountdown()
      GC.Buy.RefreshIfShown()
      assert.equal("Blizzard's price: 1g02s", dock().sub:GetText())

      now = now + 3 -- 11 s after the quote: 9 left
      GC.Buy.TickCountdown()
      assert.equal("Blizzard's price: 1g02s · 9 s left", dock().sub:GetText())
      local row = rowWithText("Alpha Herb")
      assert.equal("CONFIRM", buttonFor(row).label)
      assert.is_true(buttonFor(row):IsEnabled())
      assert.equal("Cancel", dock().second.label)
    end)

    -- Final micro round (nit 2): only the line whose quote it is, and only while it waits at
    -- CONFIRM -- after the click the wait is the server's, and no seconds are the player's to beat.
    it("counts in the dock only, never in a row", function()
      atConfirm()
      now = now + 11
      GC.Buy.TickCountdown()
      assert.is_nil(rowWithText("Charlie Dust").reagent:GetText():find("9 s", 1, true))
      assert.is_nil(rowWithText("Alpha Herb").reagent:GetText():find("9 s", 1, true))
    end)

    it("stops counting once CONFIRM has been clicked", function()
      atConfirm()
      click(rowWithText("Alpha Herb")) -- confirm: the stage is the server's now
      assert.equal("confirming", GC.Buy._attempt.stage)
      now = now + 11
      GC.Buy.TickCountdown()
      GC.Buy.RefreshIfShown()
      assert.is_nil(dock().sub:GetText():find("s left", 1, true))
    end)

    it("repaints once a second while it counts, not on every tick", function()
      atConfirm()
      local repaints, repaint = 0, GC.Buy.RefreshIfShown
      GC.Buy.RefreshIfShown = function(...) repaints = repaints + 1; return repaint(...) end
      now = now + 11
      GC.Buy.TickCountdown()
      now = now + 0.25
      GC.Buy.TickCountdown()
      now = now + 0.25
      GC.Buy.TickCountdown()
      now = now + 0.25
      GC.Buy.TickCountdown()
      GC.Buy.RefreshIfShown = repaint
      assert.equal(1, repaints)
    end)

    it("waits no longer than twenty seconds, whatever the client says", function()
      _G.C_AuctionHouse.GetQuoteDurationRemaining = function() return 45 end
      atConfirm()
      assert.equal(20, timers[#timers].seconds)
    end)

    it("waits no longer than the server's own quote", function()
      _G.C_AuctionHouse.GetQuoteDurationRemaining = function() return 12 end
      atConfirm()
      assert.equal(12, timers[#timers].seconds)
    end)

    it("waits its twenty seconds when the client cannot say", function()
      _G.C_AuctionHouse.GetQuoteDurationRemaining = function() return nil end
      atConfirm()
      assert.equal(20, timers[#timers].seconds)
    end)
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

  -- The site says "cheaper than market by ..." from these (the week 3 contract, part B): the
  -- line's usual price per unit at the moment of the purchase -- the number its cap was built on
  -- -- rides on the row as `mv`, and a line with no usual price leaves the field off.
  it("puts the line's usual price on the ledger row, and nothing for a line with none", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPurchaseSucceeded()

    hover(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityResults(105)
    click(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityPriceUpdated(400, 2000)
    click(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityPurchaseSucceeded()

    local rows = GC.Ledger.GetEntries()
    assert.equal(2, #rows)
    assert.equal(101, rows[1].itemID)
    assert.equal(1000, rows[1].mv)
    assert.equal(105, rows[2].itemID)
    assert.is_nil(rows[2].mv)
    local keys = {}
    for k in pairs(rows[2]) do keys[#keys + 1] = k end
    table.sort(keys)
    assert.is_nil(("," .. table.concat(keys, ",") .. ","):find(",mv,", 1, true))
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
    assert.equal("CONFIRM", buttonFor(rowWithText("Alpha Herb")).label)
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
    assert.equal("no answer — check your mail", buttonFor(row).label)
    assert.is_false(buttonFor(row):IsEnabled())
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
    assert.equal("BUY 10", buttonFor(rowWithText("Alpha Herb")).label)
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
    -- The dock has moved on to the next line; picked again, this one offers the four it still needs.
    assert.equal(103, dock().lineItemID)
    pick(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.equal("BUY 4", buttonFor(rowWithText("Alpha Herb")).label)
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

    pick(rowWithText("Charlie Dust"))
    assert.equal(101, GC.Buy._focus)
    assert.equal(101, dock().lineItemID)
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
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    GC.PurchaseSlot.Claim("sniper", now) -- "waiting...": a look the button cannot be clicked in
    GC.Buy.RefreshIfShown()
    local row = rowWithText("Alpha Herb")
    assert.is_false(buttonFor(row):IsEnabled())
    assert.equal("dim", buttonFor(row).painted)

    GC.Buy.RefreshIfShown()
    row = rowWithText("Alpha Herb")
    assert.is_false(buttonFor(row):IsEnabled())
    assert.equal("dim", buttonFor(row).painted)
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
    assert.equal("no answer — check your mail", buttonFor(rowWithText("Alpha Herb")).label)
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
  -- The quote search is a request of ours the Sell tab has to know is out: a "busy" it draws is
  -- not a post's refusal (review sell-fix4 M3). Noted with the key it went out with.
  it("notes its quote search as out, by the key it sent", function()
    local noted = {}
    GC.Sniper._NoteSearchSent = function(key) noted[#noted + 1] = key end
    hover(rowWithText("Alpha Herb"))
    assert.equal(1, #searches)
    assert.equal(1, #noted)
    assert.equal(101, noted[1].itemID)
  end)

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
    assert.equal("...", buttonFor(rowWithText("Alpha Herb")).label)
    assert.is_false(buttonFor(rowWithText("Alpha Herb")):IsEnabled())

    now = now + 11
    GC.Buy.RefreshIfShown()
    local row = rowWithText("Alpha Herb")
    assert.equal("BUY 10", buttonFor(row).label)
    assert.is_true(buttonFor(row):IsEnabled())
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

  -- Final money review I1, through Core/Init.lua's own routing: a late quote goes to the window
  -- whose cancelled Start it answers, and never lights anything in the other.
  it("routes the late quote of a Start it cancelled unanswered to itself, and swallows it", function()
    local onEvent = loadRouter()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    timers[#timers].fn() -- the watchdog: no answer, cancelled, drained

    onEvent(nil, "COMMODITY_PRICE_UPDATED", 1020, 10200)

    assert.same({}, sniperCalls)
    assert.equal("expired", GC.Buy._attempt.stage)
    assert.is_nil(GC.PurchaseSlot.Owner())
  end)

  it("leaves the late quote of the Sniper's cancelled Start to the Sniper, starting nothing under it", function()
    local onEvent = loadRouter()
    GC.PurchaseSlot.Claim("sniper", now) -- the Sniper holds the slot for its drain
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    assert.same({}, started)

    onEvent(nil, "COMMODITY_PRICE_UPDATED", 50, 150)

    assert.same({ "priceUpdated" }, sniperCalls)
    assert.equal("quoted", GC.Buy._attempt.stage)
    assert.is_nil(GC.Buy._attempt.serverTotal)
    assert.are_not.equal("CONFIRM", buttonFor(rowWithText("Alpha Herb")).label)
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
    assert.equal("purchase failed — try again", buttonFor(row).label)
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
    assert.equal("no answer — check your mail", buttonFor(rowWithText("Charlie Dust")).label)
    pick(rowWithText("Alpha Herb"))
    assert.equal("no answer — check your mail", buttonFor(rowWithText("Alpha Herb")).label)
  end)

  it("keeps a stranded record a failure cannot be pinned to the attempt for", function()
    strandOne()
    GC.Buy._attempt = nil
    assert.is_false(GC.Buy.OnCommodityPurchaseFailed())
    assert.is_truthy(GC.Buy._stranded[101])
    assert.equal("no answer — check your mail", buttonFor(rowWithText("Alpha Herb")).label)

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
    assert.equal("no answer — check your mail", buttonFor(row).label)
    assert.is_false(buttonFor(row):IsEnabled())
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

  -- A commodity line with an empty book says the honest thing about the book.
  it("says nothing is on offer for a commodity whose book came back empty", function()
    setBook(105, {})
    hover(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityResults(105)
    assert.equal("nothing on offer", buttonFor(rowWithText("Echo Salt")).label)
  end)

  -- The client's GameTooltip, as far as a line's tooltip uses it: every line it was handed, in
  -- order, the double ones as "left | right". The game's own lines for an item are the client's to
  -- draw: SetItemByID and SetHyperlink stand for them as one line naming what was asked for.
  local tip
  local function fakeTooltip()
    tip = { lines = {}, owner = nil }
    function tip:SetOwner(o) self.owner = o; self.lines = {} end
    function tip:SetText(t) self.lines[#self.lines + 1] = { t } end
    function tip:SetItemByID(id) self.lines[#self.lines + 1] = { "item:" .. tostring(id) } end
    function tip:SetHyperlink(link) self.lines[#self.lines + 1] = { "link:" .. tostring(link) } end
    function tip:AddLine(t) self.lines[#self.lines + 1] = { t } end
    function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = { l, r } end
    function tip:Show() end
    function tip:Hide() self.owner = nil end
    function tip:IsOwned(o) return self.owner == o end
    _G.GameTooltip = tip
  end
  local function tipText()
    local out = {}
    for _, l in ipairs(tip.lines) do out[#out + 1] = table.concat(l, " | ") end
    return table.concat(out, "\n")
  end

  -- BUY 2.0 week 2: a gear line (anything the client will not sell as a commodity) is bought here,
  -- one lot per press, the cheapest at or under the line's cap, never over it.
  --
  -- How the lots are found (the BUY 2.0 probe, 2026-10-01, docs/addon/AGENTS.md "Auction house"):
  -- a BUY search on the bare key finds no lots for gear that has item-level or suffix variants,
  -- and PlaceBid buys only while the auction house's current search is a buy search for the lot's
  -- exact key. So the read is two searches: a SELL search on the bare key, which Blizzard's own
  -- sell frame sends for equipment so that every variant's lots come back, each row with its own
  -- item key (Blizzard_AuctionHouseUtil.lua's ConvertItemSellItemKey, the same in both games);
  -- then a buy search on the chosen lot's own key, whose answer is what a press bids on. Nothing
  -- may search in between: GC.Buy.HoldsSearch holds the addon's other senders, and a search
  -- anybody sends (seen by a post-hook) voids the armed lot.
  describe("a gear line", function()
    local placed, sent, sellSent, rowsFor, money, hooks, LOTS

    local function keyOf(k)
      return ("%d:%d:%d"):format(k.itemID, k.itemLevel or 0, k.itemSuffix or 0)
    end
    local function lot(id, buyout, qty, level)
      return { auctionID = id, buyoutAmount = buyout, quantity = qty, containsOwnerItem = false,
               itemKey = { itemID = 201, itemLevel = level or 20, itemSuffix = 0, battlePetSpeciesID = 0 } }
    end
    local BARE = { itemID = 201, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
    local AT20 = { itemID = 201, itemLevel = 20, itemSuffix = 0, battlePetSpeciesID = 0 }

    local function gearRun(line)
      GC.AppRuns._set({ { code = "run-g", name = "Gear run", updatedAt = 100, origin = "app",
        lines = { line or { i = 201, q = 1, cc = 1170 }, { i = 101, q = 10 } } } })
      GC.Buy.SelectRun("run-g")
      GC.Buy.RefreshIfShown()
    end

    -- Picked, the sell search answered, the lot's own key searched and answered: a lot in hand.
    local function readBoots()
      pick(rowWithText("Dark Leather Boots"))
      GC.Buy.OnItemResults(BARE)
      GC.Buy.OnItemResults(AT20)
    end

    before_each(function()
      placed, sent, sellSent, rowsFor, money, hooks = {}, {}, {}, {}, 1000000, {}
      LOTS = { lot(11, 900, 4), lot(12, 1000, 2), lot(13, 1900, 1, 25) }
      NAMES[201] = "Dark Leather Boots"
      local ah = _G.C_AuctionHouse
      ah.MakeItemKey = function(itemID, itemLevel, itemSuffix, species)
        return { itemID = itemID, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0,
                 battlePetSpeciesID = species or 0 }
      end
      ah.GetItemKeyInfo = function(key) return { isCommodity = key.itemID ~= 201 } end
      -- The client as the probe found it: a sell search on the bare key answers with every
      -- variant's lots; a buy search answers with the lots of exactly the key it was sent with.
      ah.SendSellSearchQuery = function(key, sorts, separate)
        sellSent[#sellSent + 1] = { key = key, sorts = sorts, separate = separate }
        local all = {}
        for _, r in ipairs(LOTS) do if r.itemKey.itemID == key.itemID then all[#all + 1] = r end end
        rowsFor[keyOf(key)] = all
        if hooks.SendSellSearchQuery then hooks.SendSellSearchQuery(key, sorts, separate) end
      end
      ah.SendSearchQuery = function(key, sorts, separate)
        searches[#searches + 1] = key.itemID
        sent[#sent + 1] = { key = key, sorts = sorts, separate = separate }
        local exact = {}
        for _, r in ipairs(LOTS) do
          if keyOf(r.itemKey) == keyOf(key) then exact[#exact + 1] = r end
        end
        rowsFor[keyOf(key)] = exact
        if hooks.SendSearchQuery then hooks.SendSearchQuery(key, sorts, separate) end
      end
      ah.GetNumItemSearchResults = function(key) return #(rowsFor[keyOf(key)] or {}) end
      ah.GetItemSearchResultInfo = function(key, i) return (rowsFor[keyOf(key)] or {})[i] end
      ah.HasFullItemSearchResults = function(key) return rowsFor[keyOf(key)] ~= nil end
      ah.PlaceBid = function(auctionID, amount) placed[#placed + 1] = { auctionID = auctionID, amount = amount } end
      for _, name in ipairs({ "SendBrowseQuery", "SearchForFavorites", "RefreshItemSearchResults",
          "RefreshCommoditySearchResults", "RequestMoreItemSearchResults",
          "RequestMoreCommoditySearchResults", "RequestMoreBrowseResults", "QueryOwnedAuctions",
          "QueryBids", "ReplicateItems" }) do
        ah[name] = function() end
      end
      _G.GetMoney = function() return money end
      _G.Enum = { AuctionHouseSortOrder = { Buyout = 4 } }
      -- The post-hooks the tab watches every search with, captured so a test can be "somebody else".
      _G.hooksecurefunc = function(target, name, fn)
        if target == _G.C_AuctionHouse then hooks[name] = fn end
      end
      GC.Buy._WatchSearches()
      GC.Util.AuctionHouseErrorText = function() return "That auction is gone." end
      gearRun()
    end)

    after_each(function() _G.GetMoney = nil end)

    it("reads every variant's lots with one sell search on the bare key, the player's own apart", function()
      pick(rowWithText("Dark Leather Boots"))
      assert.equal(1, #sellSent)
      assert.same(BARE, sellSent[1].key)
      assert.same({ { sortOrder = 4, reverseSort = false } }, sellSent[1].sorts)
      assert.is_true(sellSent[1].separate)
      assert.equal(0, #sent)
      assert.equal("quoting", GC.Buy._attempt.stage)
    end)

    it("then searches the cheapest lot's own key, and offers that lot", function()
      pick(rowWithText("Dark Leather Boots"))
      GC.Buy.OnItemResults(BARE)
      assert.same(AT20, sent[#sent].key)
      assert.same({ { sortOrder = 4, reverseSort = false } }, sent[#sent].sorts)
      assert.is_true(sent[#sent].separate)
      assert.equal("quoting", GC.Buy._attempt.stage)
      GC.Buy.OnItemResults(AT20)
      assert.equal("quoted", GC.Buy._attempt.stage)
      assert.equal(11, GC.Buy._attempt.lot.auctionID)
    end)

    it("ignores an answer about another item, and one that has not landed yet", function()
      pick(rowWithText("Dark Leather Boots"))
      GC.Buy.OnItemResults({ itemID = 999 })
      assert.equal(0, #sent)
      rowsFor = {} -- the client holds nothing for the bare key yet
      GC.Buy.OnItemResults(BARE)
      assert.equal(0, #sent)
      assert.equal("quoting", GC.Buy._attempt.stage)
    end)

    it("reads nothing under the cap as over the cap, and searches no variant", function()
      LOTS = { lot(13, 1900, 1, 25) }
      pick(rowWithText("Dark Leather Boots"))
      GC.Buy.OnItemResults(BARE)
      assert.equal(0, #sent)
      assert.equal("quoted", GC.Buy._attempt.stage)
      assert.equal("over", GC.Buy._attempt.lotWhy)
      local row = rowWithText("Dark Leather Boots")
      assert.equal("over your cap · 1900c", row.status:GetText())
      assert.equal("RAISE CAP TO 1900c", dock().buy.label)
    end)

    it("arms the lot once the cap is raised to it", function()
      LOTS = { lot(13, 1900, 1, 25) }
      pick(rowWithText("Dark Leather Boots"))
      GC.Buy.OnItemResults(BARE)
      press() -- RAISE CAP TO 1900c
      assert.same({ itemID = 201, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 0 }, sent[#sent].key)
      assert.equal(0, #placed)
    end)

    it("takes no lot below the line's item level", function()
      gearRun({ i = 201, q = 1, cc = 2000, minIlvl = 25 })
      pick(rowWithText("Dark Leather Boots"))
      GC.Buy.OnItemResults(BARE)
      assert.same({ itemID = 201, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 0 }, sent[#sent].key)
    end)

    it("holds the addon's other searches from the ask until the lot is bought or goes stale", function()
      assert.is_false(GC.Buy.HoldsSearch())
      pick(rowWithText("Dark Leather Boots"))
      assert.is_true(GC.Buy.HoldsSearch())
      GC.Buy.OnItemResults(BARE)
      GC.Buy.OnItemResults(AT20)
      assert.is_true(GC.Buy.HoldsSearch())
      now = now + 11
      assert.is_false(GC.Buy.HoldsSearch())
    end)

    it("reads again instead of bidding once anybody else has searched", function()
      readBoots()
      hooks.SendBrowseQuery({ searchString = "boots" }) -- the player's own search on Blizzard's pane
      local asked = #sellSent
      press()
      assert.equal(0, #placed)
      assert.equal(asked + 1, #sellSent)
    end)

    it("reads again when anything refreshes, pages or queries the auction house in between", function()
      for _, name in ipairs({ "RefreshItemSearchResults", "RequestMoreItemSearchResults",
          "RequestMoreBrowseResults", "QueryOwnedAuctions", "QueryBids", "ReplicateItems" }) do
        readBoots()
        hooks[name]()
        local asked = #sellSent
        press()
        assert.equal(0, #placed, name)
        assert.equal(asked + 1, #sellSent, name)
        now = now + 11 -- the next pass starts from a read of its own
      end
    end)

    -- Task 4: one lot per press.
    it("buys one lot per press: the cheapest under the cap, at its buyout", function()
      readBoots()
      assert.equal("BUY ONE · 900c", dock().buy.label)
      press()
      assert.same({ { auctionID = 11, amount = 900 } }, placed)
      assert.equal("bidding", GC.Buy._attempt.stage)
      assert.equal("buy", GC.PurchaseSlot.Owner())
      assert.equal("buying...", dock().buy.label)
    end)

    it("keeps its button enabled until PlaceBid has been called", function()
      readBoots()
      local b = dock().buy
      local enabledAtCall
      _G.C_AuctionHouse.PlaceBid = function() enabledAtCall = b.enabled end
      press()
      assert.is_true(enabledAtCall)
      assert.is_false(b.enabled)
    end)

    it("books the lot on its own completion event and frees the slot", function()
      readBoots()
      press()
      assert.is_true(GC.Buy.OnPurchaseCompleted(11))
      assert.is_nil(GC.PurchaseSlot.Owner())
      local line = runLine(201)
      assert.equal(1, line.bought)
      assert.equal(900, line.spent)
      local rows = GC.Ledger.GetEntries()
      assert.equal(1, #rows)
      assert.same({ 201, 1, 900, "goldcap_buy" }, { rows[1].itemID, rows[1].qty, rows[1].total, rows[1].source })
    end)

    it("files the lot under its own item key", function()
      readBoots()
      press()
      GC.Buy.OnPurchaseCompleted(11)
      local batches = GC.Acquisitions.GetAll()
      assert.equal(1, #batches)
      assert.equal("item:201:20:0:0", batches[1].positionKey)
      assert.equal(900, batches[1].originalTotal)
    end)

    it("re-reads the lots from the client's own refresh after a purchase, sending nothing", function()
      gearRun({ i = 201, q = 2, cc = 1170 })
      readBoots()
      GC.Buy._focus = 201
      press()
      local searchesBefore, sellsBefore = #sent, #sellSent
      LOTS = { lot(11, 900, 3), lot(12, 1000, 2), lot(13, 1900, 1, 25) }
      rowsFor[keyOf(AT20)] = { LOTS[1], LOTS[2] }
      GC.Buy.OnPurchaseCompleted(11)
      -- The dock stays on the gear line, so the next press -- and Enter -- act on it.
      assert.equal(201, dock().lineItemID)
      assert.equal(201, GC.Buy._focus)
      GC.Buy.OnItemResults(AT20)
      assert.equal(searchesBefore, #sent)
      assert.equal(sellsBefore, #sellSent)
      assert.equal("quoted", GC.Buy._attempt.stage)
      assert.equal(11, GC.Buy._attempt.lot.auctionID)
      -- ...and the second press bids on the lot that refresh read, with no search in between.
      assert.equal("BUY ONE · 900c", dock().buy.label)
      press()
      assert.same({ 11, 900 }, { placed[2].auctionID, placed[2].amount })
    end)

    -- The armed variant sold between the whole-item read and its own: the next variant under the
    -- cap is armed, not a dead "nothing on offer".
    it("arms the next variant when the armed one sold before its own read", function()
      LOTS = { lot(11, 900, 1), lot(13, 1000, 1, 25) }
      pick(rowWithText("Dark Leather Boots"))
      table.remove(LOTS, 1) -- lot 11 sells before the variant's own search is answered
      GC.Buy.OnItemResults(BARE)
      GC.Buy.OnItemResults(AT20)
      local AT25 = { itemID = 201, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 0 }
      assert.same(AT25, sent[#sent].key)
      GC.Buy.OnItemResults(AT25)
      assert.equal("BUY ONE · 1000c", dock().buy.label)
    end)

    it("arms no watchdog for a bid the client answered inside its own call", function()
      readBoots()
      _G.C_AuctionHouse.PlaceBid = function(auctionID) GC.Buy.OnPurchaseCompleted(auctionID) end
      local before = #timers
      press()
      assert.equal(before, #timers)
    end)

    it("ignores the completion of an auction it did not bid on", function()
      readBoots()
      press()
      assert.is_false(GC.Buy.OnPurchaseCompleted(99))
      assert.equal("bidding", GC.Buy._attempt.stage)
    end)

    -- Review Focus 1.
    it("says the auction house's error, frees the slot, and reads the lots again on the next press", function()
      GC.Sell = { _ErrorKind = function() return "bid" end }
      readBoots()
      press()
      assert.is_true(GC.Buy.OnAuctionHouseError(7))
      assert.equal("failed", GC.Buy._attempt.stage)
      assert.is_nil(GC.PurchaseSlot.Owner())
      assert.equal("That auction is gone.", dock().sub:GetText())
      local bids, sells = #placed, #sellSent
      press()
      assert.equal(bids, #placed)
      assert.equal(sells + 1, #sellSent)
    end)

    -- An error that names no request may be another sender's: the bid is kept as one with no answer,
    -- so its late completion is still booked and the line is not bought past its need.
    it("keeps a bid an error of nobody in particular may not have answered", function()
      GC.Sell = { _ErrorKind = function() return "shared" end }
      readBoots()
      press()
      assert.is_true(GC.Buy.OnAuctionHouseError(9))
      assert.equal("unknown", GC.Buy._attempt.stage)
      assert.is_nil(GC.PurchaseSlot.Owner())
      assert.equal("That auction is gone.", dock().sub:GetText())
      assert.equal("no answer — check your mail", dock().buy.label)
      assert.is_false(dock().buy.enabled)
      assert.is_true(GC.Buy.OwnsAuctionPurchase(11))
      assert.is_true(GC.Buy.OnPurchaseCompleted(11))
      assert.is_false(GC.Buy.OnPurchaseCompleted(11))
      assert.equal(1, runLine(201).bought)
    end)

    it("goes on with a line that wants more than its unanswered bids could cover", function()
      GC.Sell = { _ErrorKind = function() return "shared" end }
      gearRun({ i = 201, q = 2, cc = 1170 })
      readBoots()
      press()
      GC.Buy.OnAuctionHouseError(9)
      assert.is_true(dock().buy.enabled)
      local sells = #sellSent
      press()
      assert.equal(sells + 1, #sellSent)
    end)

    it("books a bid the auction house closed on once it answers after the reopen", function()
      readBoots()
      press()
      GC.Buy.OnAuctionHouseClosed()
      GC.Buy.OnAuctionHouseClosed()
      GC.Buy.OnAuctionHouseShow()
      assert.is_true(GC.Buy.OnPurchaseCompleted(11))
      assert.equal(1, runLine(201).bought)
      assert.equal(900, runLine(201).spent)
    end)

    it("leaves an error only a post can raise to the Sell tab", function()
      GC.Sell = { _ErrorKind = function() return "post" end }
      readBoots()
      press()
      assert.is_false(GC.Buy.OnAuctionHouseError(3))
      assert.equal("bidding", GC.Buy._attempt.stage)
    end)

    -- Review Focus 2.
    it("warns instead of re-offering when a bid gets no answer, and books a late one once", function()
      readBoots()
      press()
      timers[#timers].fn() -- the watchdog
      assert.equal("unknown", GC.Buy._attempt.stage)
      assert.equal("no answer — check your mail", dock().buy.label)
      assert.is_false(dock().buy.enabled)
      assert.is_nil(GC.PurchaseSlot.Owner())
      assert.is_true(GC.Buy.OnPurchaseCompleted(11))
      assert.is_false(GC.Buy.OnPurchaseCompleted(11))
      assert.equal(1, runLine(201).bought)
    end)

    it("never bids without a cap", function()
      gearRun({ i = 201, q = 1 })
      readBoots()
      assert.equal("set a cap first", dock().buy.label)
      assert.is_false(dock().buy.enabled)
      press()
      assert.equal(0, #placed)
    end)

    it("reads the line again once a cap is typed for it", function()
      gearRun({ i = 201, q = 1 })
      readBoots()
      now = now + 11
      local commit
      GC.BuyCapEditor = { Open = function(_, opts) commit = opts.onCommit end, Close = function() end }
      _G.MenuUtil = { CreateContextMenu = function(_, build)
        build(nil, { CreateTitle = function() end, CreateDivider = function() end,
          CreateButton = function(_, text, fn) if text == "Change the cap…" then fn() end end })
      end }
      local row = rowWithText("Dark Leather Boots")
      row.scripts.OnMouseUp(row, "RightButton")
      _G.MenuUtil = nil
      local sells = #sellSent
      commit(1170)
      GC.Buy.Tick()
      assert.equal(sells + 1, #sellSent)
      GC.Buy.OnItemResults(BARE)
      GC.Buy.OnItemResults(AT20)
      assert.equal("BUY ONE · 900c", dock().buy.label)
    end)

    it("never bids what the wallet cannot pay", function()
      money = 850
      readBoots()
      assert.equal("not enough gold", dock().buy.label)
      assert.is_false(dock().buy.enabled)
    end)

    it("never bids on a stale read", function()
      readBoots()
      now = now + 11
      press()
      assert.equal(0, #placed)
    end)

    it("never bids over a cap that moved down after the read", function()
      readBoots()
      GC.Buy._SetLineCap("run-g", 201, 800)
      GC.Buy.RefreshIfShown()
      press()
      assert.equal(0, #placed)
    end)

    it("hands commodity events on while a bid is out", function()
      readBoots()
      press()
      assert.is_false(GC.Buy.OnCommodityPurchaseSucceeded())
      assert.is_false(GC.Buy.OnCommodityPriceUpdated(1, 1))
      assert.is_false(GC.Buy.OnCommodityPurchaseFailed())
      assert.is_false(GC.Buy.OnCommodityPriceUnavailable())
      assert.equal("bidding", GC.Buy._attempt.stage)
    end)

    it("waits while the Deals window has a bid out", function()
      GC.Sniper.BidOut = function() return true end
      readBoots()
      assert.equal("waiting...", dock().buy.label)
      press()
      assert.equal(0, #placed)
    end)

    it("says it has a bid out, for the Deals window to wait on", function()
      readBoots()
      assert.is_false(GC.Buy.BidOut())
      press()
      assert.is_true(GC.Buy.BidOut())
    end)

    it("owns its own bid for the passive capture, so it is not filed twice", function()
      readBoots()
      press()
      assert.is_true(GC.Buy.OwnsAuctionPurchase(11))
      assert.is_false(GC.Buy.OwnsAuctionPurchase(12))
    end)

    it("gives the slot back and keeps the warning when the auction house closes on a bid", function()
      readBoots()
      press()
      GC.Buy.OnAuctionHouseClosed()
      assert.equal("unknown", GC.Buy._attempt.stage)
      assert.is_nil(GC.PurchaseSlot.Owner())
      assert.equal(0, cancels)
    end)

    -- Task 5: the dock lists the lots by price, the row says what the next press costs.
    it("lists the lots by price on the dock, the dear ones marked over the cap", function()
      readBoots()
      assert.equal("900c · 4 lots   1000c · 2 lots   1900c · over your cap", dock().sub:GetText())
      local row = rowWithText("Dark Leather Boots")
      assert.equal("900c", row.cells.price:GetText())
      assert.equal("900c", row.cells.cost:GetText())
    end)

    it("says how to set a cap on a gear line that has none", function()
      gearRun({ i = 201, q = 1 })
      readBoots()
      assert.equal("no cap for this item — right-click the line to set one", dock().sub:GetText())
    end)

    it("says the floor on a gear line that has one", function()
      gearRun({ i = 201, q = 1, cc = 2000, minIlvl = 25 })
      assert.is_truthy(rowWithText("Dark Leather Boots").reagent:GetText():find("item level 25+", 1, true))
    end)

    -- The hover: the game's own tooltip for the lot it buys next (its own link: the item level and
    -- bonuses the player would get), its lots by price under it, and that lot named.
    it("shows the lot it buys next in the game's own tooltip, and its lots by price under it", function()
      LOTS[1].itemLink = "boots-20"
      readBoots()
      fakeTooltip()
      local row = rowWithText("Dark Leather Boots")
      row.scripts.OnEnter(row)
      assert.same({ "link:boots-20" }, tip.lines[1])
      local text = tipText()
      assert.is_truthy(text:find("4 at 900c", 1, true))
      assert.is_truthy(text:find("2 at 1000c", 1, true))
      assert.is_truthy(text:find("1 at 1900c | over your cap", 1, true))
      assert.is_truthy(text:find("next to buy: 900c | ilvl 20", 1, true))
      assert.is_nil(text:find("you take", 1, true)) -- a press buys one lot, not a walk up the book
    end)

    it("shows the item itself when no lot is known yet", function()
      fakeTooltip()
      local row = rowWithText("Dark Leather Boots")
      row.scripts.OnEnter(row)
      assert.same({ "item:201" }, tip.lines[1])
      assert.is_nil(tipText():find("next to buy", 1, true))
    end)

    it("says why there is no lot to buy next", function()
      money = 500
      readBoots()
      fakeTooltip()
      local row = rowWithText("Dark Leather Boots")
      row.scripts.OnEnter(row)
      assert.is_truthy(tipText():find("not enough gold", 1, true))
      assert.same({ "item:201" }, tip.lines[1])
      gearRun({ i = 201, q = 1 })
      money = 1000000
      readBoots()
      row = rowWithText("Dark Leather Boots")
      row.scripts.OnEnter(row)
      assert.is_truthy(tipText():find("no cap for this item — right-click the line to set one", 1, true))
    end)
  end)

  -- Review round 1: a line whose quote is still fresh keeps its clickable "BUY n" while a batch is
  -- out -- only a line with no fresh quote is waiting on one.
  it("keeps a freshly quoted line's own label while a keys batch is out", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    hover(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityResults(105)
    GC.Sniper._KeysOutstanding = function() return true end

    hover(rowWithText("Alpha Herb"))

    local row = rowWithText("Alpha Herb")
    assert.equal("BUY 10", buttonFor(row).label)
    assert.is_true(buttonFor(row):IsEnabled())
  end)

  -- Final review m10: a click on that line then asks again -- the quote it shows is not the
  -- attempt a click spends -- and the ask is held for the batch. The button stayed "BUY 10",
  -- enabled, as if the click had done nothing. It says it is waiting until the ask goes.
  it("says it is waiting after a click that has to wait for a keys batch", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    hover(rowWithText("Echo Salt"))
    GC.Buy.OnCommodityResults(105)
    local out = true
    GC.Sniper._KeysOutstanding = function() return out end
    hover(rowWithText("Alpha Herb"))
    local asked = #searches

    click(rowWithText("Alpha Herb"))

    local row = rowWithText("Alpha Herb")
    assert.equal("...", buttonFor(row).label)
    assert.is_false(buttonFor(row):IsEnabled())
    out = false
    GC.Buy.Tick()
    assert.equal(asked + 1, #searches)
    assert.equal(101, searches[#searches])
  end)

  -- Final review m9: the Sniper asks this before it sends any keys batch -- a hover quote left on
  -- the wire by a switch to Deals is one a cap batch would take the answer of.
  it("says a quote is waiting for its answer until it lands", function()
    assert.is_false(GC.Buy.QuotePending())
    hover(rowWithText("Alpha Herb"))
    assert.is_true(GC.Buy.QuotePending())
    GC.Buy.OnCommodityResults(101)
    assert.is_false(GC.Buy.QuotePending())
  end)

  -- Caps fixes 5i: a quote owed across the end of the session was asked for in the next one, of
  -- a line the player had long since stopped pointing at.
  it("forgets a quote it owed when the auction house closes", function()
    GC.Sniper._KeysOutstanding = function() return true end
    hover(rowWithText("Alpha Herb"))
    assert.equal(101, GC.Buy._quoteOwed)
    GC.Buy.OnAuctionHouseClosed()
    assert.is_nil(GC.Buy._quoteOwed)
    GC.Buy.RefreshIfShown()
    assert.equal("BUY 10", buttonFor(rowWithText("Alpha Herb")).label)
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
    assert.equal("BUY 6", buttonFor(row).label)
    assert.equal("5400c", row.cells.cost:GetText())
    assert.is_true(buttonFor(row):IsEnabled()) -- the part that fits is still buyable
    assert.equal("warn", buttonFor(row).variant)
    assert.is_truthy(GC.Buy._log[#GC.Buy._log].text:find("▲100% over usual", 1, true))
  end)

  -- Review item 10: while the client holds a purchase of ours, neither planBuyClick nor quote will
  -- act for any other line. BUY 2.0: the dock stays on the line waiting to be confirmed -- a click
  -- on another row moves nothing and asks nothing -- and CONFIRM is still that line's.
  it("keeps the dock on a purchase waiting to be confirmed", function()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    click(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityPriceUpdated(1020, 10200)

    local before = #searches
    pick(rowWithText("Charlie Dust"))
    assert.equal(101, dock().lineItemID)
    assert.equal(before, #searches)
    assert.equal("CONFIRM", dock().buy.label)
    assert.same({}, confirmed)

    -- The next line is offered the moment the purchase is over.
    press()
    deliver(101, 10)
    GC.Buy.OnCommodityPurchaseSucceeded()
    assert.equal(103, dock().lineItemID)
    assert.is_true(buttonFor(rowWithText("Charlie Dust")):IsEnabled())
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
    assert.is_truthy(GC.Buy._log[#GC.Buy._log].text:find("▲12% over the alert target", 1, true))
    -- An alert group's target is the group's own, set on goldcap.gg: the dock offers no raise,
    -- only Skip, and says what the cheapest unit costs against it.
    assert.equal("the cheapest is 4500c, your cap is 4000c", dock().sub:GetText())
    assert.is_false(dock().buy:IsShown())
    assert.equal("Skip", dock().second.label)
  end)

  it("says the same on the log line when part of the line fit under the target", function()
    showAlertRun({ { unitPrice = 3900, quantity = 2 }, { unitPrice = 4500, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.equal(2, GC.Buy._attempt.qty)
    assert.equal("BUY 2", buttonFor(rowWithText("Alpha Herb")).label)
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
    local text = GC.Buy._log[#GC.Buy._log].text
    assert.is_truthy(text:find("nothing on offer", 1, true))
    assert.is_nil(text:find("%", 1, true))
    assert.equal("the cheapest is 4001c, your cap is 4000c", dock().sub:GetText())
  end)

  it("says nothing at all about a book that stayed under the target", function()
    showAlertRun({ { unitPrice = 3900, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.is_false(GC.Buy._attempt.capped)
    assert.is_nil(GC.Buy._attempt.overPct)
    assert.equal("BUY 4", buttonFor(rowWithText("Alpha Herb")).label)
  end)

  -- BUY 2.0: the player's own price for a line is the ceiling that refused the lot, and the
  -- button says it is theirs rather than borrowing the alert target's words or usual's.
  it("measures a refused lot against the player's own cap and says it is theirs", function()
    GC.db.runLineCaps = { ["run-1"] = { [101] = 800 } }
    GC.Buy.RefreshIfShown()
    setBook(101, { { unitPrice = 900, quantity = 50 } })
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    assert.equal(12, GC.Buy._attempt.overPct)   -- 900 against the 800 cap, not the 1000 usual
    assert.equal("yours", GC.Buy._attempt.overTarget)
    assert.is_truthy(GC.Buy._log[#GC.Buy._log].text:find("▲12% over your cap", 1, true))
  end)

  -- The week 3 contract (part A): on an ordinary list, a site ceiling (`cc`) is the cap its owner
  -- set on goldcap.gg -- theirs, not an alert's target.
  it("calls a site cap on an ordinary list the player's own", function()
    GC.AppRuns._set({ { code = "run-9", name = "List", updatedAt = 900, origin = "app",
                        lines = { { i = 101, q = 4, u = 5800, cc = 4000 } } } })
    GC.db.settings.sniper.buyRun = "run-9"
    setBook(101, { { unitPrice = 4500, quantity = 50 } })
    GC.Buy.Show()
    hover(rowWithText("Alpha Herb"))
    GC.Buy.OnCommodityResults(101)
    local text = GC.Buy._log[#GC.Buy._log].text
    assert.is_truthy(text:find("▲12% over your cap", 1, true))
    assert.is_nil(text:find("alert target", 1, true))
    assert.equal("RAISE CAP TO 5800c", dock().buy.label) -- the market is above the cheapest ask
  end)

  describe("the dock", function()
    it("buys the picked line in two presses: BUY, then CONFIRM", function()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      local row = rowWithText("Alpha Herb")
      pick(row)
      GC.Buy.OnCommodityResults(101)
      assert.equal("BUY 10", dock().buy.label)
      press()
      assert.same({ itemID = 101, quantity = 10 }, started[1])
      GC.Buy.OnCommodityPriceUpdated(900, 9000)
      assert.equal("CONFIRM", dock().buy.label)
      assert.equal("Cancel", dock().second.label)
      press()
      assert.same({ itemID = 101, quantity = 10 }, confirmed[1])
    end)

    it("names the line and what it costs against the market", function()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      assert.equal("Alpha Herb ×10", dock().title:GetText())
      assert.equal("9000c · 1000c under market", dock().sub:GetText())
    end)

    it("keeps its button enabled until the protected call has been made", function()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      local b = dock().buy
      local enabledAtCall
      _G.C_AuctionHouse.StartCommoditiesPurchase = function() enabledAtCall = b.enabled end
      press()
      assert.is_true(enabledAtCall)
      assert.is_false(b.enabled) -- and only then: "buying..."
    end)

    it("Cancel at CONFIRM hands the quote back and frees the slot", function()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      press()
      GC.Buy.OnCommodityPriceUpdated(900, 9000)
      dock().second.scripts.OnClick(dock().second)
      assert.equal(1, cancels)
      assert.is_nil(GC.Buy._attempt)
      assert.is_nil(GC.PurchaseSlot.Owner())
      assert.same({}, confirmed)
    end)

    -- Review Focus 1: the dock moved on between two presses.
    it("a press that lands after the dock moved to the next line only asks for that line's price", function()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      press()
      GC.Buy.OnCommodityPriceUpdated(900, 9000)
      press()
      deliver(101, 10)
      GC.Buy.OnCommodityPurchaseSucceeded()
      assert.equal(103, dock().lineItemID)
      local before = #started
      press()
      assert.equal(before, #started)
      assert.equal(103, searches[#searches])
      assert.equal("...", dock().buy.label)
    end)

    it("RAISE CAP raises the line's cap to the dock's price and the next press buys", function()
      GC.db.runLineCaps = { ["run-1"] = { [101] = 800 } }
      GC.Buy.RefreshIfShown()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      assert.equal("RAISE CAP TO 1000c", dock().buy.label) -- market 1000 > cheapest 900
      assert.equal("Skip", dock().second.label)
      local before, searched = #started, #searches
      press()
      assert.equal(before, #started)       -- a raise is not a purchase
      assert.equal(searched, #searches)    -- nor a second look at the book
      assert.equal(1000, GC.db.runLineCaps["run-1"][101])
      assert.equal("BUY 10", dock().buy.label)
      press()
      assert.same({ itemID = 101, quantity = 10 }, started[#started])
    end)

    -- A cap moved while a quote is in hand (the cap box, the row menu, the run's percent) changes what
    -- the next press may spend: the quote is judged again against the line as it is now.
    it("never lets a press spend a quote the line's new cap refuses", function()
      pick(rowWithText("Alpha Herb"))            -- 6 at 900, 10 at 1200: 10 for 10200 under 1300
      GC.Buy.OnCommodityResults(101)
      assert.equal("BUY 10", dock().buy.label)
      GC.Buy._SetLineCap("run-1", 101, 1000)
      GC.Buy.RefreshIfShown()
      assert.equal("BUY 6", dock().buy.label)    -- only the 900s fit now
      press()
      assert.same({ itemID = 101, quantity = 6 }, started[#started])
    end)

    it("offers the raise once a lowered cap leaves nothing in the quote", function()
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      GC.Buy._SetLineCap("run-1", 101, 800)
      GC.Buy.RefreshIfShown()
      assert.equal("RAISE CAP TO 1000c", dock().buy.label)
      local before = #started
      press()                                    -- the raise, not a purchase
      assert.equal(before, #started)
    end)

    it("Enter never raises a cap", function()
      GC.db.runLineCaps = { ["run-1"] = { [101] = 800 } }
      GC.Buy.RefreshIfShown()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      local container = containerOf()
      container.mouseOver = true
      keyDown("ENTER")
      assert.equal(800, GC.db.runLineCaps["run-1"][101])
      assert.same({}, started)
    end)

    it("Skip takes the line out of this session's run and moves the dock on", function()
      GC.db.runLineCaps = { ["run-1"] = { [101] = 800 } }
      GC.Buy.RefreshIfShown()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      dock().second.scripts.OnClick(dock().second)
      assert.is_true(GC.Buy._skipped["run-1"][101])
      assert.equal(103, dock().lineItemID)
    end)

    -- Review Focus 3.
    it("Enter on a skipped line buys nothing and gives the key back", function()
      GC.Buy._skipped = { ["run-1"] = { [101] = true } }
      GC.Buy._focus = 101
      GC.Buy.RefreshIfShown()
      local container = containerOf()
      container.mouseOver = true
      keyDown("ENTER")
      assert.equal(0, #started)
      assert.is_true(container.propagate)
      GC.Buy._skipped = {}
    end)

    it("a hover picks nothing", function()
      local row = rowWithText("Charlie Dust")
      row.scripts.OnEnter(row)
      assert.are_not.equal(103, GC.Buy._focus)
    end)

    -- The dock's line gets its first quote from the ticker, so the first press can buy.
    it("asks for the price of the line it lands on, once", function()
      assert.equal(101, dock().lineItemID)
      GC.Buy.Tick()
      assert.same({ 101 }, searches)
      GC.Buy.OnCommodityResults(101)
      GC.Buy.Tick()
      assert.same({ 101 }, searches)
    end)

    -- The week 3 contract, part A: a line the route crafts itself is never the next purchase.
    it("never lands on a line the route crafts itself", function()
      GC.AppRuns._set({ { code = "run-mk", name = "Route", updatedAt = 900, origin = "app",
                          lines = { { i = 101, q = 10, mk = true }, { i = 103, q = 4 } } } })
      GC.db.settings.sniper.buyRun = "run-mk"
      GC.Buy.Show()
      assert.equal(103, dock().lineItemID)
    end)
  end)

  describe("the hover", function()
    before_each(fakeTooltip)

    -- The game's own tooltip for the item, as the Deals and Sell rows open theirs -- beside the
    -- window, never over the list -- and GoldCap's lines under it. UI/Tooltip.lua's block stands
    -- aside for the row (`goldcapOwnLines`): it would print a second market figure and Source.
    it("opens the game's own tooltip for the line's item beside the window, GoldCap's lines after it", function()
      local row = rowWithText("Alpha Herb")
      row.scripts.OnEnter(row)
      assert.equal(row, tip.owner)
      assert.equal(containerOf():GetParent(), tip.besideWindow)
      assert.same({ "item:101" }, tip.lines[1])
      assert.same({ " " }, tip.lines[2])
      assert.is_truthy(tip.lines[3][1]:find("buy 10 of 10", 1, true))
      assert.is_true(row.goldcapOwnLines)
    end)

    it("says what was bought on the list, and that a vendor sells a vendor line", function()
      GC.AppRuns._set({ { code = "run-v", name = "Vendor", updatedAt = 900, origin = "app",
                          lines = { { i = 102, q = 5, v = true, vu = 25 }, { i = 103, q = 4 } } } })
      GC.db.settings.sniper.buyRun = "run-v"
      GC.Buy.Show()
      GC.Buy.CurrentRun():RecordPurchase(103, 2, 5000, now)
      GC.Buy.RefreshIfShown()
      local vendorRow = rowWithText("Bravo Ore")
      vendorRow.scripts.OnEnter(vendorRow)
      assert.is_truthy(tipText():find("a vendor sells it for 25c each", 1, true))
      local row = rowWithText("Charlie Dust")
      row.scripts.OnEnter(row)
      assert.is_truthy(tipText():find("bought 2 for 5000c", 1, true))
      assert.is_nil(tipText():find("vendor", 1, true))
    end)

    it("draws the ladder the line's purchase would walk, what it takes, the market and the cap", function()
      setBook(101, { { unitPrice = 67, quantity = 53 }, { unitPrice = 68, quantity = 156 }, { unitPrice = 69, quantity = 24 } })
      local row = rowWithText("Alpha Herb")
      pick(row) -- the dock's own line: its quote is the read
      GC.Buy.OnCommodityResults(101)
      row.scripts.OnEnter(row)
      local text = tipText()
      assert.same({ "item:101" }, tip.lines[1])
      assert.is_truthy(text:find("buy 10 of 10", 1, true))
      assert.is_truthy(text:find("53 at 67c | you take 10", 1, true))
      assert.is_truthy(text:find("156 at 68c", 1, true))
      assert.is_nil(text:find("24 at 69c", 1, true)) -- the first level it does not reach, and no further
      assert.is_truthy(text:find("Market | 1000c each", 1, true))
      assert.is_truthy(text:find("Your cap | 1300c each", 1, true))
      assert.is_truthy(text:find("right-click to skip or change the cap", 1, true))
    end)

    it("reads another line's book after a short dwell, without touching the dock's purchase", function()
      local row = rowWithText("Charlie Dust")
      row.scripts.OnEnter(row)
      assert.equal(0, #searches)                       -- nothing before the dwell
      assert.equal(0.35, timers[#timers].seconds)
      timers[#timers].fn()                             -- the dwell elapses, pointer still there
      assert.equal(103, searches[#searches])
      assert.equal(103, GC.Buy._look.itemID)
      local attemptBefore = GC.Buy._attempt
      setBook(103, { { unitPrice = 2000, quantity = 9 } })
      GC.Buy.OnCommodityResults(103)
      assert.equal(attemptBefore, GC.Buy._attempt)
      assert.is_nil(GC.Buy._look)
      -- Drawn again, the item's own tooltip first and the ladder now under it.
      assert.same({ "item:103" }, tip.lines[1])
      assert.is_truthy(tipText():find("9 at 2000c | you take 4", 1, true))
    end)

    it("reads nothing for a pointer that moved on before the dwell", function()
      local row = rowWithText("Charlie Dust")
      row.scripts.OnEnter(row)
      row.scripts.OnLeave(row)
      timers[#timers].fn()
      assert.equal(0, #searches)
    end)

    it("sends no look while the dock's quote is fresh or a purchase is in flight", function()
      setBook(101, { { unitPrice = 900, quantity = 50 } })
      pick(rowWithText("Alpha Herb"))
      GC.Buy.OnCommodityResults(101)
      local before = #searches
      local row = rowWithText("Charlie Dust")
      row.scripts.OnEnter(row)
      timers[#timers].fn()
      assert.equal(before, #searches)
      press()                                          -- started: in flight
      now = now + 11                                   -- the quote is no longer fresh
      row.scripts.OnEnter(row)
      timers[#timers].fn()
      assert.equal(before, #searches)
    end)

    it("holds the dock's quote while a look is out, then asks", function()
      local row = rowWithText("Charlie Dust")
      row.scripts.OnEnter(row)
      timers[#timers].fn()
      pick(rowWithText("Alpha Herb"))
      assert.equal(101, GC.Buy._quoteOwed)
      assert.is_true(GC.Buy.QuotePending())
      GC.Buy.OnCommodityResults(103)
      GC.Buy.Tick()
      assert.equal(101, searches[#searches])
    end)

    it("says whose market price it is on WoW: Forever", function()
      GC.Data.ForeverReference = function(itemID)
        if itemID == 101 then return { value = 70, source = "crowd", scanners = 3, at = now - 720 } end
        return { source = "own" }
      end
      GC.Buy.RefreshIfShown()
      local row = rowWithText("Alpha Herb")
      row.scripts.OnEnter(row)
      assert.is_truthy(tipText():find("Market | 70c each", 1, true))
      assert.is_truthy(tipText():find("Source | 3 scanners, 12m ago", 1, true))
    end)

    -- Retail has no crowd price: nothing says whose the market price is.
    it("says nothing about a source on retail", function()
      local row = rowWithText("Alpha Herb")
      row.scripts.OnEnter(row)
      assert.is_nil(tipText():find("Source", 1, true))
    end)

    it("names an alert group's cap as its target", function()
      GC.AppRuns._set({ { code = "a0000001", name = "Cheap ore", updatedAt = 900, origin = "app",
                          k = "alert", lines = { { i = 101, q = 4, u = 5800, cc = 4000 } } } })
      GC.db.settings.sniper.buyRun = "a0000001"
      GC.Buy.Show()
      local row = rowWithText("Alpha Herb")
      row.scripts.OnEnter(row)
      assert.is_truthy(tipText():find("Alert target | 4000c each", 1, true))
      assert.is_nil(tipText():find("right-click", 1, true)) -- its cap is the group's, set on the site
    end)
  end)
end)
