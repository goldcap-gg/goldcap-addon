require("spec.spec_helper") -- side effect: seeds _G.time for load-time use

-- Loads the whole TOC the way loadorder_spec does, but keeps hold of the event
-- handler Init.lua installs so the ledger's four events can actually be fired.
-- Without this, a typo in a global name (GetInboxNumItems, GetMoney) would sit
-- undetected until someone opened a mailbox in the live game.
describe("Ledger event wiring", function()
  local GC, onEvent, registered

  local function stubFrame()
    local f
    f = {
      RegisterEvent = function(_, event) registered[event] = true end,
      UnregisterEvent = function() end,
      SetScript = function(_, which, fn) if which == "OnEvent" then onEvent = fn end end,
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
      SetHeight = function() end,
    }
    return f
  end

  before_each(function()
    onEvent, registered = nil, {}
    _G.CreateFrame = function() return stubFrame() end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.GoldCapDB = nil
    -- Sniper v3 §3: MAIL_SHOW/MAIL_CLOSED now also forward into GC.Sniper.OnMailShow/
    -- OnMailClosed (Auto's mail pause reason), which calls GetTime() via feedAuto -- this
    -- spec fires onEvent(nil, "MAIL_SHOW"/"MAIL_CLOSED") directly (a real dispatch, not an
    -- inert closure), so unlike loadorder_spec's stub the call genuinely happens.
    _G.GetTime = function() return 0 end

    GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then files[#files + 1] = line end
    end
    toc:close()
    for _, rel in ipairs(files) do
      local chunk = assert(loadfile("GoldCap/" .. rel:gsub("\\", "/")))
      chunk("GoldCap", GC)
    end
    -- ADDON_LOADED is what creates GoldCapDB and calls every module's Init.
    onEvent(nil, "ADDON_LOADED", "GoldCap")
  end)

  after_each(function()
    _G.CreateFrame, _G.UISpecialFrames, _G.SlashCmdList = nil, nil, nil
    _G.C_AddOns, _G.GoldCapDB, _G.GoldCap_MarketData = nil, nil, nil
    _G.SLASH_GOLDCAP1 = nil
    _G.GetInboxNumItems, _G.GetInboxHeaderInfo = nil, nil
    _G.GetInboxInvoiceInfo, _G.GetInboxItem = nil, nil
    _G.GetMoney, _G.GetCoinTextureString, _G.UnitName, _G.GetRealmName = nil, nil, nil, nil
    _G.GetTime = nil
  end)

  it("registers every event the ledger depends on", function()
    assert.is_true(registered.MAIL_SHOW)
    assert.is_true(registered.MAIL_INBOX_UPDATE)
    assert.is_true(registered.PLAYER_MONEY)
    assert.is_true(registered.PLAYER_LOGOUT)
  end)

  it("initialises the ledger tables on ADDON_LOADED", function()
    assert.is_table(_G.GoldCapDB.ledger)
    assert.is_table(_G.GoldCapDB.gold)
  end)

  it("migrates raw persisted flips and stored buyer mail during ADDON_LOADED", function()
    local flip = { itemID = 42, qty = 2, paidUnit = 100, paidTotal = 201,
      boughtAt = 500, targetUnit = 180 }
    local mail = { key = "mail:42", kind = "buy", source = "mail", itemID = 42,
      qty = 2, total = 201, at = 600, char = "Belarsa-Dentarg", region = "eu" }
    _G.GoldCapDB = { flips = { flip }, ledger = { mail } }

    onEvent(nil, "ADDON_LOADED", "GoldCap")

    assert.same(flip, _G.GoldCapDB.flips[1])
    assert.same(mail, _G.GoldCapDB.ledger[1])
    assert.equal(1, _G.GoldCapDB.acquisitionVersion)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.is_true(GC.Acquisitions.GetAll()[1].evidenceKeys["mail:42"])
  end)

  it("records a sale when the mailbox opens", function()
    _G.UnitName = function() return "Belarsa" end
    _G.GetRealmName = function() return "Dentarg" end
    _G.GetInboxNumItems = function() return 1 end
    _G.GetInboxHeaderInfo = function()
      return nil, nil, "Auction House", "Auction successful", 0, 0, 30
    end
    _G.GetInboxInvoiceInfo = function()
      return "seller", "Ironclaw Ore", "Buyerguy", 500000, 500000, 1000, 25000, 0, 0, 0, 20, true
    end
    _G.GetInboxItem = function() return nil end

    onEvent(nil, "MAIL_SHOW")

    local entries = GC.Ledger.GetEntries()
    assert.equal(1, #entries)
    assert.equal("sale", entries[1].kind)
    assert.equal(500000, entries[1].total)
    assert.equal("Belarsa-Dentarg", entries[1].char)

    -- The inbox refresh that always follows must not fork the row.
    onEvent(nil, "MAIL_INBOX_UPDATE")
    assert.equal(1, #GC.Ledger.GetEntries())
  end)

  it("reconciles the stored seller row only when its pending mailbox update becomes paid", function()
    GC.Ledger.Context = function() return { char = "Belarsa-Dentarg", region = "eu" } end
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42,
      positionKey = "commodity:42", itemName = "Ironclaw Ore", quantity = 20, total = 400000,
      acquiredAt = 900, evidenceKey = "buy:1", character = "Belarsa-Dentarg", region = "eu" })
    GC.Acquisitions.RecordPost("commodity:42", 42, "Ironclaw Ore", "Belarsa-Dentarg", "eu", 20, 950)
    local pending = true
    _G.GetInboxNumItems = function() return 1 end
    _G.GetInboxHeaderInfo = function()
      return nil, nil, "Auction House", "Auction successful", 0, 0, 30
    end
    _G.GetInboxInvoiceInfo = function()
      return pending and "seller_temp_invoice" or "seller", "Ironclaw Ore", "Buyerguy",
        500000, 500000, 1000, 25000, 500000, 1, 0, 20, true
    end
    _G.GetInboxItem = function() return nil end

    onEvent(nil, "MAIL_SHOW")
    assert.equal(20, batch.remainingQty)
    pending = false
    onEvent(nil, "MAIL_INBOX_UPDATE")

    assert.equal(0, batch.remainingQty)
    assert.equal(1, #GC.Acquisitions.GetRealized({ char = "Belarsa-Dentarg", region = "eu" }))
  end)

  it("does not blow up on a mailbox the API refuses to describe", function()
    _G.GetInboxNumItems = function() error("throttled") end
    assert.has_no.errors(function() onEvent(nil, "MAIL_SHOW") end)
  end)

  it("records gold on PLAYER_MONEY and forces a final reading on logout", function()
    _G.UnitName = function() return "Belarsa" end
    _G.GetRealmName = function() return "Dentarg" end

    _G.GetMoney = function() return 111 end
    onEvent(nil, "PLAYER_MONEY")
    assert.equal(1, #GC.Ledger.GetGold())

    -- Well inside the debounce window: only the forced logout reading lands.
    _G.GetMoney = function() return 222 end
    onEvent(nil, "PLAYER_MONEY")
    assert.equal(1, #GC.Ledger.GetGold())

    onEvent(nil, "PLAYER_LOGOUT")
    local points = GC.Ledger.GetGold()
    assert.equal(2, #points)
    assert.equal(222, points[2].copper)
  end)

  it("registers a /goldcap ledger recap that runs without erroring", function()
    assert.is_function(GC.slashHandlers.ledger)

    _G.GetCoinTextureString = function(amount) return tostring(amount) .. "c" end
    local printed
    local realPrint = _G.print
    _G.print = function(msg) printed = msg end
    GC.slashHandlers.ledger()
    _G.print = realPrint

    assert.is_string(printed)
    assert.truthy(printed:find("last 24h"))
  end)

  local function assertMalformedLoadedStartupFailsClosed(acquisitions, mailKey)
    local database = { acquisitions = acquisitions }
    local originalAcquisitions = database.acquisitions
    _G.GoldCapDB = database

    local loadedOK = pcall(onEvent, nil, "ADDON_LOADED", "GoldCap")
    assert.is_true(loadedOK)
    assert.equal(database, _G.GoldCapDB)
    assert.equal(originalAcquisitions, database.acquisitions)
    local databaseFieldCount = 0
    for _ in pairs(database) do databaseFieldCount = databaseFieldCount + 1 end
    assert.equal(1, databaseFieldCount)
    assert.is_nil(database.acquisitionPending)
    assert.is_nil(database.acquisitionRepairGroups)
    assert.is_nil(database.acquisitionConsumptionEvidence)
    assert.is_nil(database.acquisitionVersion)
    for _, row in pairs(acquisitions) do
      if type(row) == "table" then
        assert.is_nil(row.evidenceKeys)
        assert.is_nil(row.consumedEvidenceKeys)
      end
    end

    local reconcileOK, matched, isNew = pcall(GC.Acquisitions.ReconcileBuy, {
      key = mailKey, kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = "A-R", region = "eu",
    })
    assert.is_true(reconcileOK)
    assert.is_nil(matched)
    assert.is_false(isNew)
  end

  it("[WAVE3 I1 fix5] aborts loaded startup for a dense non-table acquisition row", function()
    assertMalformedLoadedStartupFailsClosed({ true }, "mail:fix5-loaded-non-table")
  end)

  it("[WAVE3 I1 fix5] aborts loaded startup for a sparse acquisition store", function()
    assertMalformedLoadedStartupFailsClosed({ [2] = {
      id = "acq:2", repairedPendingID = "pending:fix5-loaded-sparse",
    } }, "mail:fix5-loaded-sparse")
  end)

  it("[WAVE3 I1 fix5] aborts loaded startup for a dictionary acquisition store", function()
    assertMalformedLoadedStartupFailsClosed({ ["dictionary-orphan"] = {
      id = "acq:2", repairEvidenceKey = "repair:fix5-loaded-dictionary",
    } }, "mail:fix5-loaded-dictionary")
  end)
end)
