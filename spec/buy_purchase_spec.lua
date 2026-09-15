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
  local GC, searches, started, confirmed, timers, book, now

  local NAMES = { [101] = "Alpha Herb", [102] = "Bravo Ore", [103] = "Charlie Dust" }

  local function runData()
    return {
      code = "run-1", name = "Flask run", updatedAt = 100, origin = "app",
      lines = {
        { i = 101, q = 10 },
        { i = 103, q = 4 },
        { i = 102, q = 5, v = true },
      },
    }
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

  local function button(parent)
    local b = region("Button", parent)
    b.text = region("FontString", b)
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    function b:SetVariant(name) self.variant = name end
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

  local function containerOf() return upvalueOf(GC.Buy.Show, "container") end

  -- The commodity book the client would answer a SendSearchQuery with: cheapest level first,
  -- each level a whole price point aggregated across sellers.
  local function setBook(itemID, levels) book[itemID] = levels end

  local function hover(row)
    row.scripts.OnEnter(row)
  end

  local function click(row)
    row.action.scripts.OnClick(row.action)
  end

  before_each(function()
    searches, started, confirmed, timers, book, now = {}, {}, {}, {}, {}, 2000
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.GetTime = function() return now end
    _G.time = function() return now end
    _G.C_Item = { GetItemInfo = function(id) return NAMES[id] end }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
      GetContainerItemInfo = function() return nil end,
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
    GC.Ledger = { Context = function() return { char = "Tester-Realm", region = "eu" } end }
    -- The arbiter and the AH session flag are UI/SniperFrame.lua's, and its own batch path is
    -- covered by spec/buy_refresh_spec.lua against the real file. What this spec needs from it
    -- is only "there is a session, and BUY is the tab on screen".
    GC.Sniper = { IsAHOpen = function() return true end, CurrentView = function() return "buy" end }

    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/BuyRun.lua", GC)
    helper.loadModule("Core/PurchaseSlot.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/PurchaseCapture.lua", GC)
    GC.Acquisitions.Init({})
    helper.loadModule("UI/BuyFrame.lua", GC)

    local runs = { runData() }
    GC.AppRuns = {
      List = function() return runs end,
      Get = function(code)
        for _, r in ipairs(runs) do if r.code == code then return r end end
      end,
      FreeLines = function() return nil end,
    }

    GC.Buy.Attach(region("Frame"), { panelLeft = 88, panelRightInset = 32, top = -100,
                                     bottom = 34, rowWidth = 600, rowHeight = 28 })
    setBook(101, { { unitPrice = 900, quantity = 6 }, { unitPrice = 1200, quantity = 10 } })
    setBook(103, { { unitPrice = 2500, quantity = 20 } })
    GC.Buy.Show()
  end)

  after_each(function()
    _G.CreateFrame, _G.GetCoinTextureString, _G.C_Item, _G.C_Container = nil, nil, nil, nil
    _G.C_AuctionHouse, _G.C_Timer, _G.GetTime = nil, nil, nil
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
    assert.equal("BUY 10 · 1g02s", rowWithText("Alpha Herb").action.label)
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
    assert.equal("CONFIRM 1g02s", rowWithText("Alpha Herb").action.label)

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

    local line = GC.Buy.CurrentRun():Lines()[1]
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
end)
