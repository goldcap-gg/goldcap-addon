local helper = require("spec.spec_helper")

-- Who owns the browse list while the BUY tab's search is out, against the real UI/SniperFrame.lua:
-- its keys batches (the realm poll, the caps, BUY's own refresh, the Sell tab's fill) and its book
-- pass answer into the same C_AuctionHouse.GetBrowseResults() buffer, and the answer names no sender.
-- A keys batch out claims the answer first; the search's own request is next; nothing of the
-- Sniper's that writes the buffer goes while the search holds it (GC.Sniper._BrowseOwned).
describe("BUY search and the shared browse list", function()
  local GC, now, browseRows, browseSent, keysSent, folded

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
    function r:SetTexture() end
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
    function r:HasFocus() return false end
    function r:ClearFocus() end
    function r:EnableMouse() end
    function r:RegisterForClicks() end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:IsEnabled() return self.enabled end
    function r:GetParent() return parent end
    function r:CreateTexture() return region("Texture", self) end
    function r:CreateFontString() return region("FontString", self) end
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

  before_each(function()
    now, browseRows, browseSent, keysSent, folded = 2000, {}, {}, {}, nil
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetTime = function() return now end
    _G.time = function() return now end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_Item = { GetItemInfo = function() return nil end }
    _G.C_Container = { GetContainerNumSlots = function() return 0 end }
    _G.Enum = { AuctionHouseSortOrder = { Price = 0, Name = 1, Buyout = 4 } }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function(query) browseSent[#browseSent + 1] = query.searchString end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return browseRows end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function(k)
        return ({ [2589] = { itemName = "Linen Cloth", isCommodity = true },
                  [101] = { itemName = "Alpha Herb", isCommodity = true } })[k.itemID]
      end,
      SearchForItemKeys = function(keys) keysSent[#keysSent + 1] = #keys end,
    }
    GC = {
      Theme = {
        MEDIA = "", ROW_H = 20, RAIL_W = 76, FONT_UI = "font",
        pad = { xs = 4, s = 8, m = 12, l = 16 },
        tier = { WATCH = { 1, 1, 1 }, SUSPECT = { 1, 1, 0 } },
        color = { fg = { 1, 1, 1 }, fgMuted = { 0.8, 0.8, 0.8 }, fgDim = { 0.5, 0.5, 0.5 },
                  gold = { 1, 0.8, 0 }, red = { 1, 0, 0 }, green = { 0, 1, 0 }, panel = { 0, 0, 0 },
                  bg = { 0, 0, 0 }, zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 } },
        Scale = function() return 1 end,
        Label = function(parent) return region("FontString", parent) end,
        Num = function(parent) return region("FontString", parent) end,
        Button = function(parent) return button(parent) end,
        SlicedTexture = function(parent) return region("Texture", parent) end,
        WithQuality = function(name) return name end,
      },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      FullScan = { RowsFromBrowse = function() return {} end, EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end, MergeDeals = function(e) return e end, CapDeals = function(d) return d end },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, board = "items", buyCapPct = 130 } }, runs = {} },
      AuctionHouseTab = { addonBrowse = false },
    }
    for _, path in ipairs({ "Core/Util.lua", "Core/BagStock.lua", "Core/BuyRun.lua", "Core/NameMatch.lua",
        "Core/BuyView.lua", "Core/BuyDock.lua", "Core/BuyLots.lua", "Core/BookPass.lua", "Core/DrillQueue.lua",
        "Core/KeyPoll.lua", "Core/BuySearchModel.lua", "Core/AppRuns.lua", "UI/SniperFrame.lua",
        "Core/DealMath.lua", "UI/BuyFrame.lua", "UI/BuySearch.lua" }) do
      helper.loadModule(path, GC)
    end
    GC.Buy.Attach(region("Frame"), { panelLeft = 88, panelRightInset = 32, top = -100,
                                     bottom = 34, rowWidth = 600, rowHeight = 28 })
    -- A session to search in: the flag GC.Sniper keeps for it, answered here rather than reached into.
    GC.Sniper.IsAHOpen = function() return true end
    GC.Buy.FoldRefresh = function(rows) folded = rows end
  end)

  after_each(function()
    _G.CreateFrame, _G.GetTime, _G.GetCoinTextureString, _G.C_Timer, _G.C_Item = nil, nil, nil, nil, nil
    _G.C_Container, _G.Enum, _G.C_AuctionHouse = nil, nil, nil
    _G.time = os.time
  end)

  local function batchOut(owner, items)
    GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = now, owner, items
  end

  it("holds the browse list from the send until its answer, and no keys batch goes meanwhile", function()
    assert.is_false(GC.Sniper._BrowseOwned())
    assert.is_true(GC.BuySearch.Submit("linen", 1))
    assert.same({ "linen" }, browseSent)
    assert.is_true(GC.Sniper._BrowseOwned())
    assert.is_true(GC.Sniper.RequestOut())
    local poll = { HasPending = function() return true end, NextBatch = function() return { 101 } end }
    assert.is_false(GC.Sniper._TrySendKeysBatchFor(poll, "caps", function() return true end))
    assert.same({}, keysSent)
    browseRows = { { itemKey = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
                     minPrice = 120, totalQuantity = 400 } }
    GC.Sniper.OnBrowseResults()
    assert.is_false(GC.BuySearch.Pending())
    assert.is_false(GC.Sniper._BrowseOwned())
    assert.is_false(GC.Sniper.RequestOut())
    assert.is_true(GC.Sniper._TrySendKeysBatchFor(poll, "caps", function() return true end))
    assert.same({ 1 }, keysSent)
  end)

  it("takes its own answer through the Sniper's browse events, which then read nothing of it", function()
    GC.BuySearch.Submit("linen", 1)
    browseRows = { { itemKey = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
                     minPrice = 120, totalQuantity = 400 } }
    local fed = 0
    local pass = GC.Sniper._bookPass
    pass.OnResultsUpdated = function() fed = fed + 1 end
    pass.IsPaging = function() return true end
    pass.PendingStart = function() return false end
    GC.Sniper.OnBrowseResultsAdded()
    assert.equal(0, fed)
    assert.is_false(GC.BuySearch.Pending())
    -- The next answer is not the search's: it goes on to the pass.
    GC.Sniper.OnBrowseResults()
    assert.equal(1, fed)
  end)

  it("leaves a keys batch its own answer, then writes the batch off once the hold is over", function()
    batchOut("buy", { 101 })
    GC.BuySearch.Submit("linen", 1)
    assert.same({}, browseSent)
    -- The batch's wait is its own time: the search does not claim the list over it.
    assert.is_false(GC.Sniper._BrowseOwned())
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 50, totalQuantity = 5 } }
    GC.Sniper.OnBrowseResults()
    assert.equal(browseRows, folded)
    GC.Buy.Tick()
    assert.same({ "linen" }, browseSent)
    browseRows = { { itemKey = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
                     minPrice = 120, totalQuantity = 400 } }
    GC.Sniper.OnBrowseResults()

    -- A batch that does not answer in time is written off, and its late answer is not the search's.
    browseSent = {}
    GC.BuySearch.Close()
    batchOut("caps", { 101 })
    GC.BuySearch.Submit("linen", 1)
    now = now + GC.BuySearchModel.HOLD_SECONDS
    GC.Buy.Tick()
    assert.same({ "linen" }, browseSent)
    assert.is_nil(GC.Sniper._keysAwaiting)
    browseRows = { { itemKey = { itemID = 101 }, minPrice = 50, totalQuantity = 5 } }
    GC.Sniper.OnBrowseResults()
    assert.is_true(GC.BuySearch.Pending())
    browseRows = { { itemKey = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
                     minPrice = 120, totalQuantity = 400 } }
    GC.Sniper.OnBrowseResults()
    assert.is_false(GC.BuySearch.Pending())
  end)
end)
