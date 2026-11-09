local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

-- WoW: Forever's lost deposits (Core/ForeverDeposits.lua) fed from where they happen: a post
-- certain to be ours (GC.Sell.OnAuctionCreated), the mail that brings an expired lot back
-- (Core/Ledger.lua's ScanInbox through GC.MailReturns.Observe), GoldCap's own cancel
-- (Post.Cancelling, after the protected call) and the server's AUCTION_CANCELED (Core/Init.lua),
-- and read back by SELL's sale pace (Compose's streakFor) and the cancel's forfeit
-- (GC.Sell.LotForfeit). Retail loads no ForeverDeposits and writes no new ledger kind.
--
-- A key is spelled with "\1" .. id, never "\1501": Lua reads "\150" as one byte.
describe("lost deposits on WoW: Forever, wired", function()
  local DAY = 86400
  local SUBJECTS = { expired = "Auction expired: %s", cancelled = "Auction cancelled: %s", outbid = "Outbid on %s" }

  local function rowsOf(entries, kind)
    local out = {}
    for _, entry in ipairs(entries) do
      if entry.kind == kind then out[#out + 1] = entry end
    end
    return out
  end

  local function expiredMail(itemID, name, stacks)
    local items = {}
    for slot, count in ipairs(stacks) do items[slot] = { itemID = itemID, count = count } end
    return { sender = "Auction House", subject = "Auction expired: " .. name, auction = true, daysLeft = 30,
      items = items }
  end

  -- The Sell tab through its real services and view: the "on screen" harness of
  -- spec/forever_sell_pace_wiring_spec.lua (item 10, a commodity, twenty in the bags, on the selling
  -- list, the player's duration 8 h), with the real ledger and returns log under it.
  describe("at the auction house", function()
    local FOREVER = { interface = 16001 }
    local GC, root, container, posted, timers, BAGS, clock

    local function region(kind, parent)
      local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
      if parent then parent.children[#parent.children + 1] = v end
      function v:SetPoint() end
      function v:ClearAllPoints() end
      function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
      function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
      function v:SetLabel(t) self.label = t end
      function v:SetVariant(name) self.variant = name end
      function v:SetScript(n, f) self.scripts[n] = f end
      function v:HookScript(n, f) self.scripts[n] = f end
      function v:Show() self.shown = true end function v:Hide() self.shown = false end
      function v:IsShown() return self.shown end
      function v:Enable() self.enabled = true end function v:Disable() self.enabled = false end
      function v:ClearFocus() self.focused = false end function v:HasFocus() return self.focused == true end
      function v:SetJustifyH() end function v:SetWordWrap(w) self.wordWrap = w end
      function v:SetTextColor(...) self.color = { ... } end
      function v:SetMaxLines(n) self.maxLines = n end
      function v:SetSpacing() end
      function v:SetAutoFocus() end function v:SetScrollChild() end
      function v:CreateTexture() return region("Texture", self) end
      function v:SetAllPoints() end function v:SetColorTexture() end
      function v:SetTexture() end function v:SetTexCoord() end
      function v:SetTextureSliceMargins() end
      function v:SetVertexColor() end
      function v:SetFrameStrata() end function v:SetFrameLevel() end
      function v:GetFrameLevel() return 0 end function v:EnableMouse() end
      return v
    end

    before_each(function()
      BAGS = { [0] = { { itemID = 10, stackCount = 20, itemName = "Herb" } } }
      posted, timers, clock = {}, {}, 1000
      _G.time = function() return clock end
      _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
      _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
      _G.GetCoinTextureString = function(n) return tostring(n) end
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
        GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
        GetContainerItemLink = function() return nil end,
      }
      _G.C_AuctionHouse = {
        MakeItemKey = function(itemID) return { itemID = itemID } end,
        GetItemKeyInfo = function() return { isCommodity = true } end,
        PostCommodity = function(_, duration, quantity, unit)
          posted[#posted + 1] = { duration = duration, quantity = quantity, unit = unit }
          return false
        end,
        -- 15 copper a unit for every duration step: a quote the record can be told apart by.
        CalculateCommodityDeposit = function(_, duration, quantity) return 15 * quantity * duration end,
      }
      _G.C_Item = { GetItemNameByID = function() return "Herb" end }
      _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
      _G.GameTooltip = {
        SetOwner = function(self) self.owner = true end, GetOwner = function() return nil end,
        AddLine = function() end, Show = function() end, Hide = function() end, SetItemByID = function() end,
      }
      local passport = FOREVER
      GC = {
        Sell = {},
        Theme = {
          color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = { .72, .71, .69 }, red = { 1, 0, 0 },
            green = { 0, 1, 0 }, zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
            gold = { 1, 1, 0 }, panel = { 0, 0, 0 }, panelHi = { 0.102, 0.114, 0.141 } },
          pad = { xs = 4, s = 8, m = 12, l = 16 },
          MEDIA = "",
          Label = function(p) return region("FontString", p) end,
          Num = function(p) return region("FontString", p) end,
          Button = function(p) return region("Button", p) end,
          Card = function(p) local card = region("Frame", p); function card:SetTint() end return card end,
          SlicedTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
          ItemTooltipOutside = function() end,
          TooltipAnchor = function() return "ANCHOR_RIGHT" end,
        },
        Game = { Passport = function() return passport end,
          IsForever = function(p) return p.interface >= 16000 and p.interface <= 16999 end },
        Data = { GetItemValue = function() return nil end,
          ForeverSales = function(itemID)
            return itemID == 10 and { units = 21, sales = 9, median = 12000, perDay = 3, hours = 168 } or nil
          end },
        db = { settings = { sniper = { postDuration = 2 } }, sellMarks = { ["commodity:10"] = true } },
      }
      GC.ForeverScan = { Enabled = function() return true end, Root = function() return GC.db end }
      helper.loadModule("Core/Util.lua", GC)
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/Ledger.lua", GC)
      GC.Ledger.Init(GC.db)
      GC.Ledger.Context = function() return { char = "Owner-Dentarg", region = "eu" } end
      helper.loadModule("Core/MailReturns.lua", GC)
      GC.MailReturns.Init(GC.db)
      helper.loadModule("Core/ForeverDeposits.lua", GC)
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/QuoteCache.lua", GC)
      helper.loadModule("Core/BagStock.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      helper.loadModule("Core/PostQueue.lua", GC)
      helper.loadModule("Core/GroupRules.lua", GC)
      helper.loadModule("Core/ForeverPace.lua", GC)
      helper.loadModule("UI/SellViewModel.lua", GC)
      helper.loadSell(GC)
      GC.Acquisitions.Init({})

      root = region("Frame")
      root.HookScript = function(_, n, f) root.scripts[n] = f end
      root.status = region("FontString", root)
      GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
        rowWidth = 1100, rowHeight = 24 })
      container = GC.SellUI.container
      container:Show()
    end)

    after_each(function()
      _G.time = os.time
      _G.C_Timer, _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil, nil
      _G.CreateFrame, _G.GetCoinTextureString, _G.ItemLocation, _G.GameTooltip = nil, nil, nil, nil
    end)

    local function ready(ask)
      GC.QuoteCache.Set(GC.SellState.quotes, 10, ask, time())
      GC.SellCompose.Positions()
      GC.SellUI.List.RenderRows()
    end

    local function position() return GC.SellState.positions[1] end

    local function post()
      container.queueButton.scripts.OnClick(container.queueButton)
    end

    it("a certain creation records the post", function()
      ready(12000)
      post()
      assert.equal(1, #posted)
      GC.Sell.OnAuctionCreated(501)
      local record = GC.db.foreverDeposits.posts[501]
      assert.equal(10, record.itemID)
      assert.equal("Herb", record.itemName)
      assert.equal(posted[1].quantity, record.quantity)
      assert.equal(posted[1].duration, record.duration)
      -- A commodity's deposit is quoted at creation, for the lot's quantity and duration.
      assert.equal(15 * record.quantity * record.duration, record.deposit)
      assert.equal(1000 + 8 * 3600, record.endsAt)
      assert.same({ "Owner-Dentarg", "eu", true }, { record.char, record.region, record.commodity })
    end)

    it("a guessed creation records nothing", function()
      ready(12000)
      post()
      -- The watchdog gives up on the post: its answer is listened for a minute.
      for _, timer in ipairs(timers) do
        if timer.seconds == 8 then timer.fn() end
      end
      assert.equal(1, #GC.Sell._LiveLate())
      -- A creation the client names nothing about: the order rule gives it to that post.
      GC.Sell.OnAuctionCreated(502)
      assert.equal(0, #GC.Sell._LiveLate())
      assert.is_nil(GC.db.foreverDeposits)
    end)

    it("the step-down hears what came back", function()
      ready(12000)
      post()
      GC.Sell.OnAuctionCreated(501)
      clock = 1000 + 8 * 3600 + 60
      local box = Mailbox.new({ expiredMail(10, "Herb", { 1 }) })
      GC.Ledger.ScanInbox({ GetInboxNumItems = box.api.GetInboxNumItems, GetInboxHeaderInfo = box.api.GetInboxHeaderInfo,
        GetInboxInvoiceInfo = box.api.GetInboxInvoiceInfo, GetInboxItem = box.api.GetInboxItem,
        noInvoiceSubjects = SUBJECTS }, GC.Ledger.Context(), clock, true)
      local rows = rowsOf(GC.Ledger.GetEntries(), "expired")
      assert.equal(1, #rows)
      assert.equal("deposit\1" .. 501, rows[1].key)
      assert.equal(30, rows[1].deposit)
      ready(12000)
      assert.same({ 1, 1, 2 }, { position().returnRounds, position().returnShort, position().returnShortIndex })
    end)

    it("the recorded deposit is the forfeit", function()
      ready(12000)
      post()
      GC.Sell.OnAuctionCreated(501)
      -- The setting moves to 24 h and the bags empty: today's quote is another number, the record's
      -- is the one the lot put up.
      GC.db.settings.sniper.postDuration = 3
      BAGS[0] = {}
      assert.equal(30, GC.Sell.LotForfeit({ auctionID = 501, itemID = 10, quantity = 1, positionKey = "commodity:10" }))
      assert.equal(45, GC.Sell.LotForfeit({ auctionID = 999, itemID = 10, quantity = 1, positionKey = "commodity:10" }))
      -- An item lot no bag stack can quote: only its record knows.
      local item = { auctionID = 601, itemID = 20, quantity = 1, positionKey = "item:20:0:0:0" }
      assert.is_nil(GC.Sell.LotForfeit(item))
      GC.ForeverDeposits.RecordPost(601, { itemID = 20, quantity = 1, duration = 2, deposit = 77, isCommodity = false },
        GC.Ledger.Context(), clock)
      assert.equal(77, GC.Sell.LotForfeit(item))
      -- The cancel fee comes on top either way.
      _G.C_AuctionHouse.GetCancelCost = function() return 5 end
      assert.equal(82, GC.Sell.LotForfeit(item))
    end)
  end)

  -- The ledger's inbox scan, as spec/ledger_returns_spec.lua drives it, with Forever's modules.
  describe("at the mailbox", function()
    local GC, db, box, last
    local CONTEXT = { char = "A-B", region = "eu" }

    local function clockTo(now)
      for i = 1, box:rowCount() do
        local row = box:row(i)
        row.daysLeft = row.daysLeft - (now - last) / DAY
      end
      last = now
    end

    local function scan(now, opening)
      clockTo(now)
      local api = box.api
      return GC.Ledger.ScanInbox({ GetInboxNumItems = api.GetInboxNumItems,
        GetInboxHeaderInfo = api.GetInboxHeaderInfo, GetInboxInvoiceInfo = api.GetInboxInvoiceInfo,
        GetInboxItem = api.GetInboxItem, noInvoiceSubjects = SUBJECTS }, CONTEXT, now, opening)
    end

    before_each(function()
      GC = helper.loadModule("Core/Ledger.lua")
      db = {}
      GC.Ledger.Init(db)
      helper.loadModule("Core/MailReturns.lua", GC)
      GC.MailReturns.Init(db)
      GC.ForeverScan = { Root = function() return db end }
      helper.loadModule("Core/ForeverDeposits.lua", GC)
      GC.ForeverDeposits.HoursOf = function(index) return ({ 2, 8, 24 })[index] end
      last = 1000
    end)

    it("an expired mail writes one row however often it is read", function()
      GC.ForeverDeposits.RecordPost(501, { itemID = 5, quantity = 20, duration = 1, deposit = 60,
        position = { itemName = "Silk" } }, CONTEXT, 1000 - 2 * 3600)
      box = Mailbox.new({ expiredMail(5, "Silk", { 20 }) })
      scan(1000, true)
      scan(1060)
      scan(4000)
      local rows = rowsOf(GC.Ledger.GetEntries(), "expired")
      assert.same({ { key = "deposit\1" .. 501, kind = "expired", source = "mail", itemID = 5, itemName = "Silk",
        qty = 20, total = 0, deposit = 60, cut = 0, pending = false, at = 1000, char = "A-B", region = "eu" } }, rows)
      assert.same({ 1, 1, 1 }, { GC.ForeverDeposits.Streak(5, CONTEXT, 4000) })
    end)

    it("a cancelled lot's mail writes nothing", function()
      box = Mailbox.new({ { sender = "Auction House", subject = "Auction cancelled: Silk", auction = true, daysLeft = 30,
        items = { { itemID = 5, count = 3 } } } })
      scan(1000, true)
      assert.equal(1, #GC.MailReturns.Entries())
      assert.same({}, GC.Ledger.GetEntries())
      assert.equal(0, (GC.ForeverDeposits.Streak(5, CONTEXT, 1000)))
    end)

    it("a sale ends the streak", function()
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/SoldView.lua", GC)
      GC.Acquisitions.Init(db)
      assert.is_nil(GC.SellRounds)
      GC.Acquisitions.RecordPost("commodity:210930", 210930, "Ironclaw Ore", CONTEXT.char, CONTEXT.region, 20, 950)
      box = Mailbox.new({ expiredMail(210930, "Ironclaw Ore", { 20 }) })
      scan(1000, true)
      box:removeRow(1)
      scan(1010)
      assert.equal(1, (GC.ForeverDeposits.Streak(210930, CONTEXT, 1010)))
      box:addRow({ sender = "Auction House", subject = "Auction successful: Ironclaw Ore", money = 400000,
        auction = true, daysLeft = 30,
        invoice = { invoiceType = "seller", itemName = "Ironclaw Ore", bid = 400000, buyout = 400000, count = 20 } })
      scan(9000)
      assert.equal(0, (GC.ForeverDeposits.Streak(210930, CONTEXT, 9000)))
    end)
  end)

  -- Every file of a TOC, as the client loads it, with the event handler Core/Init.lua installs
  -- kept so its events can be fired (spec/owned_lots_wiring_spec.lua's rig).
  local function loadClient(toc, forever)
    local rig = { registered = {} }
    local function stubFrame()
      local f
      f = {
        RegisterEvent = function(_, event) rig.registered[event] = true end,
        RegisterUnitEvent = function(_, event) rig.registered[event] = true end,
        UnregisterEvent = function() end,
        SetScript = function(_, which, fn) if which == "OnEvent" then rig.onEvent = fn end end,
        SetSize = function() end, SetPoint = function() end, SetMovable = function() end,
        EnableMouse = function() end, RegisterForDrag = function() end,
        Show = function() end, Hide = function() end, IsShown = function() return false end,
        SetText = function() end, SetTexture = function() end, SetTextColor = function() end,
        SetJustifyH = function() end, SetWidth = function() end, SetScrollChild = function() end,
        StartMoving = function() end, StopMovingOrSizing = function() end,
        CreateFontString = function() return stubFrame() end,
        CreateTexture = function() return stubFrame() end,
        TitleText = { SetText = function() end },
        EnableMouseWheel = function() end, SetVerticalScroll = function() end,
        GetVerticalScroll = function() return 0 end, GetVerticalScrollRange = function() return 0 end,
        SetWordWrap = function() end, SetMaxLines = function() end,
        Enable = function() end, Disable = function() end,
        GetFontString = function() return nil end,
        SetResizable = function() end, SetResizeBounds = function() end,
        StartSizing = function() end, ClearAllPoints = function() end,
        GetPoint = function() return nil end, GetHeight = function() return 0 end,
        GetFrameLevel = function() return 1 end, SetFrameLevel = function() end,
        SetColorTexture = function() end, SetAllPoints = function() end,
        SetFont = function() return true end,
        SetHeight = function() end,
      }
      return f
    end
    _G.CreateFrame = function() return stubFrame() end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.GoldCapDB = nil
    _G.GetTime = function() return 0 end
    _G.time = function() return 5000 end
    _G.UnitName = function() return "Aiyana" end
    _G.GetRealmName = function() return "Dentarg" end
    _G.GetCVar = function(k) if k == "portal" then return "eu" end end
    _G.GetBuildInfo = forever and function() return "1.60.1", "70790", "Nov 1 2026", 16001 end or nil
    _G.AUCTION_EXPIRED_MAIL_SUBJECT = SUBJECTS.expired
    _G.AUCTION_REMOVED_MAIL_SUBJECT = SUBJECTS.cancelled
    rig.owned = {}
    _G.C_AuctionHouse = {
      GetOwnedAuctions = function() return rig.owned end,
      QueryOwnedAuctions = function() end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      CalculateCommodityDeposit = function(_, duration, quantity) return 7 * quantity * duration end,
      GetCancelCost = function() return 15 end,
    }
    rig.GC = {}
    local file = assert(io.open(toc, "r"))
    for rawLine in file:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^#") then
        local chunk = assert(loadfile("GoldCap/" .. line:gsub("\\", "/")))
        chunk("GoldCap", rig.GC)
      end
    end
    file:close()
    rig.onEvent(nil, "ADDON_LOADED", "GoldCap")
    return rig
  end

  local function unloadClient()
    _G.CreateFrame, _G.UISpecialFrames, _G.SlashCmdList = nil, nil, nil
    _G.C_AddOns, _G.GoldCapDB, _G.GoldCap_MarketData = nil, nil, nil
    _G.SLASH_GOLDCAP1, _G.SLASH_GOLDCAP2 = nil, nil
    _G.GetTime, _G.time, _G.UnitName, _G.GetRealmName, _G.GetCVar = nil, os.time, nil, nil, nil
    _G.GetBuildInfo, _G.C_AuctionHouse = nil, nil
    _G.AUCTION_EXPIRED_MAIL_SUBJECT, _G.AUCTION_REMOVED_MAIL_SUBJECT = nil, nil
    _G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxInvoiceInfo, _G.GetInboxItem = nil, nil, nil, nil
  end

  local function ownedLot(auctionID, quantity)
    return { auctionID = auctionID, itemKey = { itemID = 190316 }, isCommodity = true, quantity = quantity,
      unitPrice = 921200, timeLeftSeconds = 3600 }
  end

  describe("a cancel answered by the server", function()
    local rig, GC

    before_each(function()
      rig = loadClient("GoldCap/GoldCap_Camelot.toc", true)
      GC = rig.GC
    end)

    after_each(unloadClient)

    local function cancelled() return rowsOf(GC.Ledger.GetEntries(), "cancelled") end

    -- A lot of twenty went up; eight of it sold, and GoldCap cancels the twelve still listed.
    local function postedAndPartlySold()
      GC.ForeverDeposits.RecordPost(501, { itemID = 190316, quantity = 20, duration = 2, isCommodity = true,
        position = { itemName = "Ore" } }, GC.Ledger.Context(), 4000)
      rig.owned = { ownedLot(501, 12) }
      rig.onEvent(nil, "OWNED_AUCTIONS_UPDATED")
      local pin = { auctionID = 501, itemID = 190316, quantity = 12, positionKey = "commodity:190316" }
      local row = { repostStage = "cancelling" }
      GC.SellPost.Cancelling(row, pin, GC.Ledger.Context())
      return row, pin
    end

    it("loses the recorded deposit for the units GoldCap cancelled", function()
      assert.is_true(GC.ForeverScan.Enabled())
      postedAndPartlySold()
      assert.same({}, cancelled())
      rig.onEvent(nil, "AUCTION_CANCELED", 501)
      -- The record: 7 a unit for each duration step, twenty at 8 h, twelve of them cancelled.
      assert.same({ { key = "deposit\1" .. 501, kind = "cancelled", source = "auction", itemID = 190316,
        itemName = "Ore", qty = 12, total = 0, deposit = math.floor(7 * 20 * 2 * 12 / 20), cut = 0, pending = false,
        at = 5000, char = "Aiyana-Dentarg", region = "eu" } }, cancelled())
      rig.onEvent(nil, "AUCTION_CANCELED", 501)
      assert.equal(1, #cancelled())
    end)

    it("answers an event that names no lot with the one cancel waiting", function()
      local row, pin = postedAndPartlySold()
      GC.SellState.repostingRow, GC.SellState.repostPin = row, pin
      GC.SellPost.CancelSent()
      rig.onEvent(nil, "AUCTION_CANCELED")
      local rows = cancelled()
      assert.equal(1, #rows)
      assert.same({ "deposit\1" .. 501, 12, 168 }, { rows[1].key, rows[1].qty, rows[1].deposit })
    end)

    it("takes a cancel from Blizzard's own window from the owned list and its estimate", function()
      rig.owned = { ownedLot(555, 20) }
      rig.onEvent(nil, "OWNED_AUCTIONS_UPDATED")
      assert.same({ auctionID = 555, itemID = 190316, quantity = 20, positionKey = "commodity:190316" },
        GC.Sell.OwnedLot(555))
      rig.onEvent(nil, "AUCTION_CANCELED", 555)
      -- Quoted again at the setting (8 h), and the cancel fee on top.
      assert.same({ { key = "deposit\1" .. 555, kind = "cancelled", source = "auction", itemID = 190316,
        qty = 20, total = 0, deposit = 7 * 20 * 2 + 15, cut = 0, pending = false, at = 5000,
        char = "Aiyana-Dentarg", region = "eu" } }, cancelled())
    end)

    it("writes nothing for a lot nobody knows", function()
      rig.onEvent(nil, "AUCTION_CANCELED", 777)
      rig.onEvent(nil, "AUCTION_CANCELED")
      assert.same({}, cancelled())
    end)

    it("reads the owned list's newest row of this character and realm", function()
      rig.owned = { ownedLot(555, 20) }
      rig.onEvent(nil, "OWNED_AUCTIONS_UPDATED")
      local lots = _G.GoldCapDB.ownedLots
      lots[#lots + 1] = { auctionID = 555, itemID = 190316, isCommodity = true, quantity = 3, unitPrice = 1,
        char = "Other-Dentarg", region = "eu", seenAt = 6000 }
      lots[#lots + 1] = { auctionID = 555, itemID = 190316, isCommodity = true, quantity = 4, unitPrice = 1,
        char = "Aiyana-Dentarg", region = "us", seenAt = 6000 }
      lots[#lots + 1] = { auctionID = 556, itemID = 2589, isCommodity = false, quantity = 1, unitPrice = 100,
        char = "Aiyana-Dentarg", region = "eu", seenAt = 6000 }
      assert.equal(20, GC.Sell.OwnedLot(555).quantity)
      assert.same({ auctionID = 556, itemID = 2589, quantity = 1 }, GC.Sell.OwnedLot(556))
      assert.is_nil(GC.Sell.OwnedLot(557))
    end)
  end)

  -- Retail proof: the whole retail TOC, a lot that came back by mail and a lot cancelled. The mail
  -- is read (the returns log has it) and the cancel is heard (the owned list stamps it), and no
  -- ledger row carries a kind retail's upload would refuse.
  describe("on retail", function()
    after_each(unloadClient)

    it("writes no new kinds", function()
      local rig = loadClient("GoldCap/GoldCap.toc", false)
      local GC = rig.GC
      assert.is_nil(GC.ForeverDeposits)
      assert.is_false(GC.ForeverScan.Enabled())
      local box = Mailbox.new({ expiredMail(190316, "Ore", { 20 }) })
      _G.GetInboxNumItems, _G.GetInboxHeaderInfo = box.api.GetInboxNumItems, box.api.GetInboxHeaderInfo
      _G.GetInboxInvoiceInfo, _G.GetInboxItem = box.api.GetInboxInvoiceInfo, box.api.GetInboxItem
      rig.onEvent(nil, "MAIL_SHOW")
      assert.equal(1, #GC.MailReturns.Entries())
      rig.owned = { ownedLot(555, 20) }
      rig.onEvent(nil, "OWNED_AUCTIONS_UPDATED")
      rig.onEvent(nil, "AUCTION_CANCELED", 555)
      assert.equal(5000, _G.GoldCapDB.ownedLots[1].cancelledAt)
      for _, entry in ipairs(GC.Ledger.GetEntries()) do
        assert.is_true(entry.kind ~= "expired" and entry.kind ~= "cancelled", entry.kind)
      end
      assert.is_nil(_G.GoldCapDB.foreverDeposits)
    end)
  end)
end)
