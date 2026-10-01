local helper = require("spec.spec_helper")

-- The BUY tab's search of the auction house (UI/BuySearch.lua), end to end over the real BUY tab:
-- the item box sends a name, the list goes aside for the results, a result opens in BUY's own dock
-- and is bought there -- a commodity BUY then CONFIRM, gear one lot per press under its own item
-- key -- through planBuyClick and GC.PurchaseCall.Click alone, booked on no list, and nothing of it
-- stored. Core/BuyRun.lua, Core/BuySearchModel.lua, Core/AppRuns.lua, Core/PurchaseSlot.lua,
-- Core/Acquisitions.lua and Core/Ledger.lua are the real ones; only the client is faked, and only
-- with what the client has.
describe("BUY search", function()
  local GC, now, timers, hooks, browseSent, mores, buffer, full, searches, sellSent, book, lots
  local started, confirmed, placed, ready, keysOut, writeOffs, playerBrowses, flagAtSend, money

  local INFO = {
    [2589] = { itemName = "Linen Cloth", quality = 1, iconFileID = 1, isCommodity = true, isEquipment = false },
    [2996] = { itemName = "Bolt of Linen Cloth", quality = 1, iconFileID = 2, isCommodity = true, isEquipment = false },
    [4309] = { itemName = "Handstitched Linen Britches", quality = 2, iconFileID = 3, isCommodity = false, isEquipment = true },
    [4310] = { itemName = "Heavy Linen Gloves", quality = 2, iconFileID = 4, isCommodity = false, isEquipment = true },
  }
  local info -- what the client has cached, by item

  local function key(itemID, level)
    return { itemID = itemID, itemLevel = level or 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  end
  local function keyOf(k) return ("%d:%d:%d"):format(k.itemID, k.itemLevel or 0, k.itemSuffix or 0) end
  local function result(itemID, price, qty, level)
    return { itemKey = key(itemID, level), minPrice = price, totalQuantity = qty, containsOwnerItem = false }
  end
  local function lot(id, buyout, itemID, level)
    return { auctionID = id, buyoutAmount = buyout, quantity = 1, containsOwnerItem = false,
             itemKey = key(itemID, level), itemLink = "item:" .. itemID .. ":" .. level }
  end
  local LINEN_ANSWER = { result(2996, 300, 50), result(2589, 120, 400), result(4309, 900, 2, 18) }

  local function region(kind, parent)
    local r = { kind = kind, children = {}, visible = true, enabled = true, scripts = {} }
    function r:SetPoint() end
    function r:ClearAllPoints() end
    function r:SetAllPoints() end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width or 600 end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:SetMaxLines() end
    function r:SetTextColor() end
    function r:SetColorTexture() end
    function r:SetTexture(t) self.texture = t end
    function r:SetTexCoord() end
    function r:SetTextureSliceMargins() end
    function r:SetVertexColor() end
    function r:SetSpacing() end
    function r:SetAlpha() end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:GetStringHeight() return 12 end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:SetAutoFocus() end
    function r:HasFocus() return self.focused == true end
    function r:SetFocus() self.focused = true end
    function r:ClearFocus() self.focused = false end
    function r:EnableMouse() end
    function r:EnableKeyboard() end
    function r:SetPropagateKeyboardInput() end
    function r:IsMouseOver() return false end
    function r:SetFrameStrata() end
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

  local function button(parent)
    local b = region("Button", parent)
    b.text = region("FontString", b)
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    function b:SetVariant(name) self.variant = name end
    return b
  end

  -- MenuUtil as far as this file uses it: a title, buttons, and a button that holds buttons.
  local menu
  local function entry(text, fn)
    local e = { text = text, fn = fn, children = {} }
    function e:CreateButton(t, f)
      local child = entry(t, f)
      self.children[#self.children + 1] = child
      return child
    end
    function e:CreateTitle(t) self.children[#self.children + 1] = { text = t, children = {} } end
    function e:CreateDivider() end
    return e
  end
  local function openMenuOf(row)
    menu = nil
    _G.MenuUtil = { CreateContextMenu = function(_, generator)
      menu = entry("root")
      generator(nil, menu)
    end }
    row.scripts.OnMouseUp(row, "RightButton")
    _G.MenuUtil = nil
    return menu
  end
  local function find(e, text)
    for _, child in ipairs(e.children) do if child.text == text then return child end end
  end

  local function view() return GC.Buy._view end
  local function dock() return GC.Buy._view.dock end
  local function panel() return GC.BuySearch._panel end
  local function press() dock().buy.scripts.OnClick(dock().buy) end
  local function resultRow(text)
    for _, row in ipairs(panel().rows) do
      if row:IsShown() and (row.name:GetText() or ""):find(text, 1, true) then return row end
    end
  end
  local function open(text) local row = resultRow(text); row.scripts.OnMouseUp(row, "LeftButton") end
  local function enter(text)
    local box = view().add.box
    box:SetText(text)
    box.scripts.OnEnterPressed(box)
  end
  local function answer(rows, isFull)
    buffer, full = rows, isFull ~= false
    return GC.BuySearch.OnBrowseResults()
  end

  before_each(function()
    now, timers, hooks, browseSent, mores, buffer, full = 5000, {}, {}, {}, 0, {}, true
    searches, sellSent, started, confirmed, placed = {}, {}, {}, {}, {}
    ready, keysOut, writeOffs, playerBrowses, money = true, false, 0, 0, 1000000
    info = { [2589] = INFO[2589], [2996] = INFO[2996], [4309] = INFO[4309], [4310] = INFO[4310] }
    book = { [2589] = { { unitPrice = 110, quantity = 15 }, { unitPrice = 125, quantity = 30 } } }
    lots = {}
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetTime = function() return now end
    _G.time = function() return now end
    _G.GetMoney = function() return money end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_Item = { GetItemInfo = function(id) return info[id] and info[id].itemName or nil end }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.C_Container = { GetContainerNumSlots = function() return 0 end }
    _G.Enum = { AuctionHouseSortOrder = { Price = 0, Name = 1, Buyout = 4 } }
    -- Post-hooks run after the call, as the client runs them: the BUY tab counts every search.
    _G.hooksecurefunc = function(target, name, fn)
      if target == _G.C_AuctionHouse then hooks[name] = fn end
    end
    local function hooked(name, fn)
      return function(...)
        local a, b = fn(...)
        if hooks[name] then hooks[name](...) end
        return a, b
      end
    end
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return ready end,
      MakeItemKey = function(itemID, level, suffix, species) return { itemID = itemID, itemLevel = level or 0,
        itemSuffix = suffix or 0, battlePetSpeciesID = species or 0 } end,
      GetItemKeyInfo = function(k) return info[k.itemID] end,
      SendBrowseQuery = hooked("SendBrowseQuery", function(query)
        flagAtSend = GC.AuctionHouseTab.addonBrowse
        browseSent[#browseSent + 1] = query
      end),
      RequestMoreBrowseResults = hooked("RequestMoreBrowseResults", function() mores = mores + 1 end),
      GetBrowseResults = function() return buffer end,
      HasFullBrowseResults = function() return full end,
      SearchForItemKeys = hooked("SearchForItemKeys", function() end),
      SendSearchQuery = hooked("SendSearchQuery", function(k, sorts, separate)
        searches[#searches + 1] = { key = k, sorts = sorts, separate = separate }
      end),
      SendSellSearchQuery = hooked("SendSellSearchQuery", function(k) sellSent[#sellSent + 1] = k end),
      GetNumCommoditySearchResults = function(itemID) return #(book[itemID] or {}) end,
      GetCommoditySearchResultInfo = function(itemID, i) return (book[itemID] or {})[i] end,
      GetNumItemSearchResults = function(k)
        local n = 0
        for _, l in ipairs(lots) do if keyOf(l.itemKey) == keyOf(k) then n = n + 1 end end
        return n
      end,
      GetItemSearchResultInfo = function(k, i)
        local n = 0
        for _, l in ipairs(lots) do
          if keyOf(l.itemKey) == keyOf(k) then
            n = n + 1
            if n == i then return l end
          end
        end
      end,
      HasFullItemSearchResults = function() return true end,
      StartCommoditiesPurchase = function(itemID, qty) started[#started + 1] = { itemID, qty } end,
      ConfirmCommoditiesPurchase = function(itemID, qty) confirmed[#confirmed + 1] = { itemID, qty } end,
      CancelCommoditiesPurchase = function() end,
      PlaceBid = function(auctionID, amount) placed[#placed + 1] = { auctionID, amount } end,
    }

    GC = helper.loadModule("Core/Util.lua")
    GC.Theme = {
      MEDIA = "", FONT_UI = "font",
      color = { fg = {1,1,1}, fgMuted = {0.8,0.8,0.8}, fgDim = {0.5,0.5,0.5}, gold = {1,0.8,0}, goldHi = {1,0.9,0},
                red = {1,0,0}, green = {0,1,0}, panel = {0,0,0}, bg = {0,0,0}, zebra = {1,1,1,0.04},
                hover = {1,1,1,0.08}, border = {1,1,1,0.06} },
      tier = { SUSPECT = {1,1,0} },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      Scale = function() return 1 end,
      Label = function(parent) return region("FontString", parent) end,
      Num = function(parent) return region("FontString", parent) end,
      Button = function(parent) return button(parent) end,
      SlicedTexture = function(parent) return region("Texture", parent) end,
      WithQuality = function(name) return name end,
      ItemTooltipOutside = function() end,
    }
    GC.db = { settings = { sniper = { buyCapPct = 130 } }, runs = {
      ["game-1"] = { code = "game-1", origin = "game", num = 1, createdAt = 1, updatedAt = 1,
                     lines = { { i = 2589, q = 10 } } },
    }, listSeq = 1 }
    GC.Data = { GetItemValue = function(itemID) return ({ [2589] = { mv = 100 }, [4309] = { mv = 1000 } })[itemID] end }
    GC.Print = function() end
    helper.loadModule("Core/Ledger.lua", GC)
    GC.Ledger.Init({})
    GC.Ledger.Context = function() return { char = "Tester-Realm", region = "eu" } end
    GC.AuctionHouseTab = { addonBrowse = false }
    GC.Sniper = {
      IsAHOpen = function() return true end, CurrentView = function() return "buy" end,
      HasStrandedConfirmed = function() return false end, BidOut = function() return false end,
      IsPurchaseQuiet = function() return false end,
      _KeysOutstanding = function() return keysOut end,
      _WriteOffKeys = function(why) writeOffs = writeOffs + 1; keysOut = false; GC._why = why end,
      _OnPlayerBrowse = function() playerBrowses = playerBrowses + 1 end,
      _IsOrphanAnswer = function() return false end,
      _TrySendKeysBatchFor = function() return false end,
    }
    GC.Sell = {}
    for _, path in ipairs({ "Core/BagStock.lua", "Core/BuyRun.lua", "Core/NameMatch.lua", "Core/BuyView.lua",
        "Core/BuyDock.lua", "Core/BuyLots.lua", "Core/BuyRecents.lua", "Core/BuySearchModel.lua",
        "Core/PurchaseSlot.lua", "Core/Acquisitions.lua", "Core/PurchaseCapture.lua", "Core/DealMath.lua",
        "Core/AppRuns.lua", "UI/BuyFrame.lua", "UI/BuyCapEditor.lua", "UI/BuyLists.lua", "UI/BuyAddBox.lua",
        "UI/BuySearch.lua" }) do
      helper.loadModule(path, GC)
    end
    GC.Acquisitions.Init({})
    GC.BuySearch._caps, GC.BuySearch._progress = {}, {}
    GC.Buy.Attach(region("Frame"), { panelLeft = 88, panelRightInset = 32, top = -100,
                                     bottom = 34, rowWidth = 600, rowHeight = 28 })
    GC.Buy.Show()
  end)

  after_each(function()
    _G.CreateFrame, _G.C_Item, _G.C_Container, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil, nil
    _G.GetTime, _G.GetMoney, _G.Enum, _G.hooksecurefunc, _G.MenuUtil, _G.GameTooltip = nil, nil, nil, nil, nil, nil
    _G.GetCoinTextureString = nil
    _G.time = os.time
  end)

  describe("without the auction house", function()
    it("leaves the box to the items GoldCap knows and says to open the auction house", function()
      GC.Sniper.IsAHOpen = function() return false end
      enter("linen")
      assert.same({}, browseSent)
      assert.is_false(GC.BuySearch.Shown())
      assert.equal("Open the auction house to search what's on sale.", view().add.note:GetText())
    end)
  end)

  describe("a search", function()
    it("sends one browse query for the text, as GoldCap's own, and puts the list aside", function()
      enter("linen x20")
      assert.equal(1, #browseSent)
      local query = browseSent[1]
      assert.equal("linen", query.searchString)
      assert.same({ { sortOrder = 0, reverseSort = false }, { sortOrder = 1, reverseSort = false } }, query.sorts)
      assert.same({}, query.filters)
      assert.same({}, query.itemClassFilters)
      -- Marked as GoldCap's for the player-browse hook, and every other browse writer stood down.
      assert.is_true(flagAtSend)
      assert.is_false(GC.AuctionHouseTab.addonBrowse)
      assert.equal(1, playerBrowses)
      assert.is_true(GC.BuySearch.Shown())
      assert.is_true(GC.BuySearch.OwnsBrowse())
      assert.equal("Searching the auction house for “linen”…", panel().status:GetText())
      -- The list waits aside: the item box still adds to it, the dock is not on it.
      assert.equal("game-1", GC.Buy.CurrentRun():Code())
      assert.is_false(dock():IsShown())
      assert.is_false(view().band.header:IsShown())
    end)

    it("shows every item key on sale, the closest names first, with the price from and how many", function()
      enter("linen")
      assert.is_true(answer(LINEN_ANSWER))
      assert.equal("On sale for “linen”: 3", panel().status:GetText())
      local names = {}
      for i = 1, 3 do names[i] = panel().rows[i].name:GetText() end
      assert.same({ "Linen Cloth", "Bolt of Linen Cloth", "Handstitched Linen Britches · ilvl 18" }, names)
      assert.equal("120c", panel().rows[1].price:GetText())
      assert.equal("400", panel().rows[1].avail:GetText())
      assert.equal("ITEM", panel().headings.name:GetText())
      assert.is_false(panel().more:IsShown())
      assert.is_false(GC.BuySearch.OwnsBrowse())
    end)

    it("says when nothing is on sale", function()
      enter("zzz")
      answer({})
      assert.equal("Nothing on sale for “zzz”.", panel().status:GetText())
    end)

    it("fills in a name the client did not have yet", function()
      info[2996] = nil
      enter("linen")
      answer(LINEN_ANSWER)
      assert.is_truthy(resultRow("#2996"))
      info[2996] = INFO[2996]
      GC.BuySearch.OnItemKeyInfo(2996)
      assert.is_truthy(resultRow("Bolt of Linen Cloth"))
      assert.is_nil(resultRow("#2996"))
    end)

    it("pages for more results while the answer is not whole", function()
      enter("linen")
      answer({ result(2589, 120, 400) }, false)
      assert.is_true(panel().more:IsShown())
      assert.equal("More results", panel().more.label)
      panel().more.scripts.OnClick(panel().more)
      assert.equal(1, mores)
      assert.equal("Loading more results…", panel().status:GetText())
      answer(LINEN_ANSWER, true)
      assert.equal("On sale for “linen”: 3", panel().status:GetText())
      assert.is_false(panel().more:IsShown())
    end)

    it("waits for the throttle, saying so, and goes on the tick", function()
      ready = false
      enter("linen")
      assert.same({}, browseSent)
      assert.equal("Waiting for the auction house…", panel().status:GetText())
      ready = true
      GC.Buy.Tick()
      assert.equal(1, #browseSent)
    end)

    it("lets an unanswered keys batch answer, then writes it off the way a Check does", function()
      keysOut = true
      enter("linen")
      assert.same({}, browseSent)
      now = now + 2
      GC.Buy.Tick()
      assert.equal(1, writeOffs)
      assert.equal("player search", GC._why)
      assert.equal(1, #browseSent)
    end)

    it("says when the answer never came, and searches again on the button", function()
      enter("linen")
      now = now + GC.BuySearchModel.TIMEOUT_SECONDS
      GC.Buy.Tick()
      assert.equal("The auction house did not answer. Search again.", panel().status:GetText())
      assert.equal("Search again", panel().more.label)
      -- The late answer is still swallowed for a moment, so the button waits that out first.
      now = now + GC.BuySearchModel.ORPHAN_SECONDS
      panel().more.scripts.OnClick(panel().more)
      assert.equal(2, #browseSent)
    end)

    it("goes back to the list on screen, and the list's own refresh resumes", function()
      enter("linen")
      answer(LINEN_ANSWER)
      assert.is_truthy(panel().back.label:find("List 1", 1, true))
      panel().back.scripts.OnClick(panel().back)
      assert.is_false(GC.BuySearch.Shown())
      assert.is_false(panel():IsShown())
      assert.equal("game-1", GC.Buy.CurrentRun():Code())
      assert.is_nil(GC.Buy._aside)
      assert.is_true(dock():IsShown())
      assert.equal(2589, dock().lineItemID)
    end)

    it("closes with the auction house and hands the list back", function()
      enter("linen")
      answer(LINEN_ANSWER)
      open("Linen Cloth")
      GC.Buy.OnAuctionHouseClosed()
      GC.BuySearch.OnAuctionHouseClosed()
      assert.is_false(GC.BuySearch.Shown())
      assert.equal("game-1", GC.Buy.CurrentRun():Code())
      assert.is_nil(GC.Buy._SearchRun())
    end)
  end)

  describe("a commodity result", function()
    before_each(function()
      enter("linen x20")
      answer(LINEN_ANSWER)
      open("Linen Cloth")
    end)

    it("opens in the dock for the quantity searched, and asks for its price at once", function()
      assert.equal(GC.BuySearch.CODE, GC.Buy._SearchRun():Code())
      assert.equal("Linen Cloth ×20", dock().title:GetText())
      assert.equal(2589, searches[#searches].key.itemID)
      assert.is_false(searches[#searches].separate)
      assert.is_true(panel().strip:IsShown())
      assert.equal("20", panel().strip.box:GetText())
    end)

    it("is bought BUY then CONFIRM through the dock, and booked on no list", function()
      GC.Buy.OnCommodityResults(2589)
      assert.equal("BUY 20", dock().buy.label)
      press()
      assert.same({ { 2589, 20 } }, started)
      GC.Buy.OnCommodityPriceUpdated(114, 2275)
      assert.equal("CONFIRM", dock().buy.label)
      press()
      assert.same({ { 2589, 20 } }, confirmed)
      assert.is_true(GC.Buy.OnCommodityPurchaseSucceeded())
      local rows = GC.Ledger.GetEntries()
      assert.equal(1, #rows)
      assert.same({ "goldcap_buy", 2589, 20, 2275 }, { rows[1].source, rows[1].itemID, rows[1].qty, rows[1].total })
      assert.is_nil(rows[1].runCode)
      local batches = GC.Acquisitions.GetAll()
      assert.equal(1, #batches)
      assert.equal("goldcap_buy", batches[1].source)
      assert.is_nil(batches[1].runCode)
      -- Nothing of the search is stored: no run, no progress, no cap.
      assert.is_nil(GC.db.runs[GC.BuySearch.CODE])
      for _, perChar in pairs(GC.db.buyProgress or {}) do assert.is_nil(perChar[GC.BuySearch.CODE]) end
      assert.is_nil(GC.db.runLineCaps)
      assert.is_nil(GC.db.runCaps)
      -- And the list it put aside never heard of it.
      assert.equal(0, GC.Buy.CurrentRun():Lines()[1].bought)
      assert.equal("Everything here is bought", dock().title:GetText())
    end)

    it("buys the quantity typed under the results", function()
      local box = panel().strip.box
      box:SetText("5")
      box.scripts.OnEnterPressed(box)
      assert.equal("Linen Cloth ×5", dock().title:GetText())
      GC.Buy.OnCommodityResults(2589)
      assert.equal("BUY 5", dock().buy.label)
    end)

    it("does not count what the bags hold against what was asked for", function()
      local line = GC.Buy._SearchRun():Lines()[1]
      assert.equal(0, line.have)
      assert.equal(20, line.buy)
    end)

    it("is capped at the market price times the BUY cap, as any line is", function()
      local line = GC.Buy._SearchRun():Lines()[1]
      assert.equal(130, line.cap)
      assert.equal("default", line.capFrom)
    end)

    it("cannot be closed or swapped while its purchase is in the client's hands", function()
      GC.Buy.OnCommodityResults(2589)
      press()
      assert.is_false(panel().back.enabled)
      assert.is_false(GC.BuySearch.Close())
      assert.is_false(GC.BuySearch.Open(GC.BuySearch._panel.rows[2].id))
      assert.equal(GC.BuySearch.CODE, GC.Buy._SearchRun():Code())
    end)
  end)

  describe("a gear result", function()
    before_each(function()
      lots = { lot(21, 900, 4309, 18), lot(22, 1200, 4309, 18), lot(23, 700, 4309, 25) }
      enter("linen")
      answer(LINEN_ANSWER)
      open("Handstitched Linen Britches")
    end)

    it("arms its own item key at once: a buy search on that variant, no whole-item read", function()
      assert.equal(0, #sellSent)
      local sent = searches[#searches]
      assert.same(key(4309, 18), sent.key)
      assert.is_true(sent.separate)
      assert.equal("arm", GC.Buy._attempt.phase)
      assert.is_true(GC.Buy.HoldsSearch())
    end)

    it("bids one lot per press under its cap, and books it on no list", function()
      GC.Buy.OnItemResults(key(4309, 18))
      assert.equal("BUY ONE · 900c", dock().buy.label)
      press()
      assert.same({ { 21, 900 } }, placed)
      assert.is_true(GC.Buy.OnPurchaseCompleted(21))
      local rows = GC.Ledger.GetEntries()
      assert.equal(1, #rows)
      assert.same({ 4309, 1, 900 }, { rows[1].itemID, rows[1].qty, rows[1].total })
      assert.is_nil(rows[1].runCode)
      local batches = GC.Acquisitions.GetAll()
      assert.is_nil(batches[1].runCode)
      assert.equal("item:4309:18:0:0", batches[1].positionKey)
    end)

    it("holds a new search while its armed read holds the auction house's search", function()
      GC.Buy.OnItemResults(key(4309, 18))
      enter("silk")
      assert.equal(1, #browseSent)
      assert.equal("Waiting for the purchase to finish…", panel().status:GetText())
      press()
      GC.Buy.OnPurchaseCompleted(21)
      -- The client refreshes the armed key itself after a purchase; with nothing left, the read ends.
      lots = {}
      GC.Buy.OnItemResults(key(4309, 18))
      GC.Buy.Tick()
      assert.equal(2, #browseSent)
      assert.equal("silk", browseSent[2].searchString)
      assert.is_nil(GC.Buy._SearchRun())
    end)
  end)

  describe("a gear result with no market price", function()
    before_each(function()
      lots = { lot(31, 4000, 4310, 22) }
      enter("linen")
      answer({ result(4310, 4000, 1, 22) })
      open("Heavy Linen Gloves")
      GC.Buy.OnItemResults(key(4310, 22))
    end)

    it("is never bid on without a cap", function()
      assert.equal("set a cap first", dock().buy.label)
      press()
      assert.same({}, placed)
    end)

    it("takes a cap typed for it, for this session only", function()
      local row = resultRow("Heavy Linen Gloves")
      local m = openMenuOf(row)
      local change = find(m, "Change the cap…")
      assert.is_truthy(change)
      change.fn()
      local editor = GC.BuyCapEditor._frame
      editor.box:SetText("50")
      editor.set.scripts.OnClick(editor.set)
      assert.equal(500000, GC.BuySearch._caps[4310])
      assert.is_nil(GC.db.runLineCaps)
      GC.Buy.Tick()
      GC.Buy.OnItemResults(key(4310, 22))
      assert.equal("BUY ONE · 4000c", dock().buy.label)
    end)
  end)

  describe("adding a result to a list", function()
    before_each(function()
      enter("linen x20")
      answer(LINEN_ANSWER)
    end)

    it("adds it to one of the player's lists with the quantity asked for, and stays on the search", function()
      local m = openMenuOf(resultRow("Bolt of Linen Cloth"))
      local add = find(m, "Add to list…")
      find(add, "List 1").fn()
      local editor = GC.BuyCapEditor._frame
      assert.equal("How many of Bolt of Linen Cloth?", editor.title:GetText())
      assert.equal("20", editor.box:GetText())
      editor.box:SetText("5")
      editor.set.scripts.OnClick(editor.set)
      local lines = GC.db.runs["game-1"].lines
      assert.same({ 2996, 5 }, { lines[2].i, lines[2].q })
      assert.is_truthy(panel().status:GetText():find("Added 5× Bolt of Linen Cloth to List 1.", 1, true))
      assert.is_true(GC.BuySearch.Shown())
      assert.equal(2996, GC.db.buyRecents[1].i)
    end)

    it("makes a new list for it", function()
      local m = openMenuOf(resultRow("Linen Cloth"))
      find(find(m, "Add to list…"), "New list").fn()
      local editor = GC.BuyCapEditor._frame
      editor.set.scripts.OnClick(editor.set)
      assert.equal(20, GC.db.runs["game-2"].lines[1].q)
      assert.is_truthy(panel().status:GetText():find("to a new list, List 2.", 1, true))
    end)

    it("refuses a quantity that is not a whole number", function()
      local m = openMenuOf(resultRow("Linen Cloth"))
      find(find(m, "Add to list…"), "List 1").fn()
      local editor = GC.BuyCapEditor._frame
      editor.box:SetText("lots")
      editor.set.scripts.OnClick(editor.set)
      assert.equal("Type a whole number.", editor.preview:GetText())
      assert.equal(1, #GC.db.runs["game-1"].lines)
    end)

    it("offers the opened result's own button for it too", function()
      open("Linen Cloth")
      assert.equal("Add to list…", panel().strip.add.label)
    end)
  end)
end)
