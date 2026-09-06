require("spec.spec_helper") -- side effect: seeds _G.time for load-time use

-- Wiring, not just capability (live_observations_spec.lua's phrase): OWNED_AUCTIONS_UPDATED
-- and AUCTION_CANCELED must actually reach GC.Data.RecordOwnedLots / MarkOwnedLotCancelled,
-- or owned_lots_spec.lua's store never fills from a real client session. Loads the whole TOC
-- the way ledger_wiring_spec.lua does, so the real Init.lua dispatch runs.
describe("Owned lots event wiring", function()
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

  local OWNED = { { auctionID = 555, itemKey = { itemID = 190316 }, isCommodity = true,
    quantity = 20, unitPrice = 921200, timeLeftSeconds = 3600 } }

  before_each(function()
    onEvent, registered = nil, {}
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
    _G.C_AuctionHouse = {
      GetOwnedAuctions = function() return OWNED end,
      QueryOwnedAuctions = function() end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
    }

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
    onEvent(nil, "ADDON_LOADED", "GoldCap")
  end)

  after_each(function()
    _G.CreateFrame, _G.UISpecialFrames, _G.SlashCmdList = nil, nil, nil
    _G.C_AddOns, _G.GoldCapDB, _G.GoldCap_MarketData = nil, nil, nil
    _G.SLASH_GOLDCAP1 = nil
    _G.GetTime, _G.time, _G.UnitName, _G.GetRealmName, _G.GetCVar = nil, os.time, nil, nil, nil
    _G.C_AuctionHouse = nil
  end)

  it("registers OWNED_AUCTIONS_UPDATED and AUCTION_CANCELED", function()
    assert.is_true(registered.OWNED_AUCTIONS_UPDATED)
    assert.is_true(registered.AUCTION_CANCELED)
  end)

  it("records the owned roster into GoldCapDB.ownedLots on OWNED_AUCTIONS_UPDATED", function()
    onEvent(nil, "OWNED_AUCTIONS_UPDATED")
    assert.equal(1, #_G.GoldCapDB.ownedLots)
    local row = _G.GoldCapDB.ownedLots[1]
    assert.equal(555, row.auctionID)
    assert.equal(190316, row.itemID)
    assert.is_true(row.isCommodity)
    assert.equal(20, row.quantity)
    assert.equal(921200, row.unitPrice)
    assert.equal(5000 + 3600, row.expiresAt)
    assert.equal("Aiyana-Dentarg", row.char)
    assert.equal("eu", row.region)
    assert.equal(5000, row.seenAt)
    assert.is_nil(row.cancelledAt)
  end)

  it("stamps cancelledAt when AUCTION_CANCELED carries the auctionID", function()
    onEvent(nil, "OWNED_AUCTIONS_UPDATED")
    onEvent(nil, "AUCTION_CANCELED", 555)
    assert.equal(5000, _G.GoldCapDB.ownedLots[1].cancelledAt)
  end)

  it("does not stamp anything when AUCTION_CANCELED carries no usable payload", function()
    onEvent(nil, "OWNED_AUCTIONS_UPDATED")
    assert.has_no.errors(function() onEvent(nil, "AUCTION_CANCELED") end)
    assert.is_nil(_G.GoldCapDB.ownedLots[1].cancelledAt)
  end)

  describe("wiring", function()
    local function fileText(path)
      local file = assert(io.open(path, "r"))
      local text = file:read("*a")
      file:close()
      return text
    end

    it("the repost flow's own cancel stamps the lot cancelled the moment it fires", function()
      local text = fileText("GoldCap/UI/SellFrame.lua")
      local cancelAt = text:find("C_AuctionHouse.CancelAuction(plan.auctionID)", 1, true)
      local markAt = text:find("GC.Data.MarkOwnedLotCancelled(", 1, true)
      assert.is_truthy(cancelAt)
      assert.is_truthy(markAt)
      assert.is_true(markAt > cancelAt)
    end)
  end)
end)
