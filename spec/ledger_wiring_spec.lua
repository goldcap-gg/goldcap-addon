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
end)
