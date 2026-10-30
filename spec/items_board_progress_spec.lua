local helper = require("spec.spec_helper")

-- Owner, retail 2026-10-11: on the Items board "I did not understand whether a scan was running or
-- not, or when the items would appear": the board sat empty for about twenty seconds, the toolbar
-- read "AUTO · PAUSED: ITEMS BOARD" beside the Commodities pass's numbers, SCAN read idle, and the
-- empty board claimed there was nothing cheap before a single answer had come back. The board's
-- first look at its set each visit to the auction house is now said in all three places, and SCAN
-- on this board asks for that look again instead of starting a Commodities pass under it.
describe("the Items board says when it is looking", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function button()
    local b = { labels = {} }
    function b:SetLabel(t) self.labels[#self.labels + 1] = t end
    function b:SetVariant(v) self.variant = v end
    return b
  end

  local clock, sent, browses

  -- The real UI/SniperFrame.lua on the Items board of an open auction house, with a poll set of
  -- `count` realm items -- three batches for 250 -- and nothing cheap among them.
  local function loadSniper(count)
    clock, sent, browses = 1000, {}, 0
    _G.GetTime = function() return clock end
    _G.time = function() return clock end
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() browses = browses + 1 end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
      MakeItemKey = function(id) return { itemID = id } end,
      SearchForItemKeys = function(keys) sent[#sent + 1] = #keys end,
    }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, Scale = function() return 1 end, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
          fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
          gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } },
      Game = { IsForever = function() return false end, Passport = function() return {} end },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "PAUSED" end,
          PauseReasons = function() return { items = true } end, Tick = function() end }
      end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end,
        OriginState = function() return "manual" end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(token) return tostring(token) end },
      FullScan = {
        RowsFromBrowse = function() return {} end,
        CapDeals = function(deals) return deals end,
      },
      Trigger = { AnyArmed = function() return true end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, showRefused = false, watchPins = {} } } },
    }
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local show = GC.Sniper.OnAuctionHouseShow
    local api = { GC = GC, scan = button() }
    local refreshRows = upvalue(show, "refreshRows")
    set(refreshRows, "content", { SetHeight = function() end })
    set(refreshRows, "createRow", function()
      local row = { shown = false }
      function row:Show() self.shown = true end
      function row:Hide() self.shown = false end
      function row:IsShown() return self.shown end
      return row
    end)
    set(GC.Sniper.OnItemKeyInfo, "driver", { getKeyInfo = function() return nil end,
      isReady = function() return true end, claimSend = function() return true end })
    set(show, "mode", "fullscan")
    set(show, "view", "deals")
    set(show, "ahOpen", true)
    api.frame = {
      scroll = { SetVerticalScroll = function() end },
      emptyText = { SetText = function(_, text) api.emptyText = text end,
        Show = function() end, Hide = function() api.emptyText = nil end },
      status = { SetText = function(_, text) api.status = text end },
      fullScanBtn = api.scan,
    }
    set(show, "frame", api.frame)
    GC.Sniper.scanner = {}
    local ids = {}
    for i = 1, count or 250 do ids[i] = 1000 + i end
    GC.Sniper._keyPoll:SetTargets(ids)
    -- The batch out answers: no row comes back, so nothing on this board is cheap.
    api.answer = function()
      clock = clock + 3
      GC.Sniper.OnBrowseResults()
    end
    api.next = function() return GC.Sniper._TrySendKeysBatch() end
    api.scanLabel = function()
      GC.Sniper.RepaintScanState()
      return api.scan.labels[#api.scan.labels]
    end
    api.click = upvalue(upvalue(show, "createFrame"), "onFullScanClick")
    return api
  end

  local function emptyText(api)
    api.GC.Sniper._UpdateEmptyState(0)
    return api.emptyText or ""
  end

  after_each(function()
    _G.GetTime, _G.time, _G.Item, _G.C_Timer, _G.C_AuctionHouse = nil, os.time, nil, nil, nil
  end)

  it("tells the empty board it is checking until the first look has answered, then what it found", function()
    local api = loadSniper(250)
    api.GC.Sniper._SetBoard("items")
    assert.same({ 100 }, sent)
    assert.is_truthy(emptyText(api):find("Checking 250 gear, pets and recipes…", 1, true))
    assert.is_nil(emptyText(api):find("No gear, pets or recipes", 1, true))

    api.answer(); api.next()
    api.answer(); api.next()
    assert.same({ 100, 100, 50 }, sent)
    assert.is_truthy(emptyText(api):find("Checking 250", 1, true))

    api.answer()
    assert.is_truthy(emptyText(api):find("No gear, pets or recipes under their region price right now.", 1, true))
  end)

  it("reads the board's own progress on the status line, and the pass's again on Commodities", function()
    local api = loadSniper(250)
    api.GC.Sniper._readout = "deals 3 · items 900 · filtered 12"
    api.GC.Sniper._SetBoard("items")
    assert.equal("checking items 0 of 250", api.status)
    api.answer(); api.next()
    assert.equal("checking items 100 of 250", api.status)
    api.answer(); api.next()
    api.answer()
    assert.equal("deals 0 · watching 250 items", api.status)

    api.GC.Sniper._SetBoard("commodities")
    assert.equal("deals 3 · items 900 · filtered 12", api.status)
  end)

  it("lights SCAN for the first look of the visit, and not for the quiet rounds after it", function()
    local api = loadSniper(150)
    api.GC.Sniper._SetBoard("items")
    assert.equal("SCANNING…", api.scanLabel())
    assert.equal("active", api.scan.variant)
    api.answer(); api.next()
    assert.equal("SCANNING…", api.scanLabel())
    api.answer()
    assert.equal("SCAN", api.scanLabel())
    assert.equal("ghost", api.scan.variant)

    -- The board keeps checking while it is open; those rounds are not announced.
    clock = clock + 10
    assert.is_true(api.next())
    assert.equal("SCAN", api.scanLabel())
  end)

  it("makes SCAN on this board look at the whole set again now, not start a Commodities pass", function()
    local api = loadSniper(150)
    api.GC.Sniper._SetBoard("items")
    api.answer(); api.next()
    api.answer()
    assert.same({ 100, 50 }, sent)

    -- Inside the breather between rounds, a press does not wait for it.
    clock = clock + 1
    api.click()
    assert.equal(0, browses)
    assert.same({ 100, 50, 100 }, sent)
    assert.equal("SCANNING…", api.scanLabel())
    assert.equal("checking items 0 of 150", api.status)
    api.answer(); api.next()
    api.answer()
    assert.equal("SCAN", api.scanLabel())

    -- A press while a round is already out joins it: nothing more is sent, and SCAN lights for it.
    clock = clock + 10
    assert.is_true(api.next())
    assert.equal("SCAN", api.scanLabel())
    api.click()
    assert.same({ 100, 50, 100, 50, 100 }, sent)
    assert.equal("SCANNING…", api.scanLabel())
  end)

  it("looks again at the start of every visit, since the board starts every visit empty", function()
    local api = loadSniper(150)
    api.GC.Sniper._SetBoard("items")
    api.answer(); api.next()
    api.answer()
    assert.equal("SCAN", api.scanLabel())

    -- What OnAuctionHouseClosed does to the poll and the store, without the rest of the close.
    api.GC.Sniper._ForgetItemsVisit()
    api.GC.Sniper._keyPoll:Reset()
    clock = clock + 600
    assert.is_true(api.next())
    assert.equal("SCANNING…", api.scanLabel())
    assert.is_truthy(emptyText(api):find("Checking 150", 1, true))
  end)

  -- Owner 2026-10-26. The player's own search on Blizzard's Buy list holds every batch of this
  -- board's, and the waiting label says to press SCAN; SCAN here did nothing until the auction
  -- house closed. And every batch is an answer the Buy list beside the window will show.
  describe("with the auction house tab", function()
    local api, tab
    before_each(function()
      api = loadSniper(150)
      tab = { owned = true, veiled = 0 }
      tab.PlayerOwnsBrowseList = function() return tab.owned end
      tab.ReleaseBrowseList = function() tab.owned = false end
      tab.PlayerIsBusy = function() return false end
      tab.NoteAddonSearch = function() end
      tab.NoteAddonBrowse = function() tab.veiled = tab.veiled + 1 end
      api.GC.AuctionHouseTab = tab
    end)

    it("makes SCAN take the Buy list back from the player's own search", function()
      api.GC.Sniper._SetBoard("items")
      assert.same({}, sent)

      api.click()

      assert.is_false(tab.owned)
      assert.same({ 100 }, sent)
    end)

    it("tells the tab that the Buy list shows GoldCap's searches, batch by batch", function()
      tab.owned = false
      api.GC.Sniper._SetBoard("items")
      assert.equal(1, tab.veiled)
      api.answer(); api.next()
      assert.equal(2, tab.veiled)
    end)
  end)

  it("says nothing of a look on the Commodities board, or with the auction house closed", function()
    local api = loadSniper(150)
    assert.is_nil(api.GC.Sniper._ItemsChecking())
    api.GC.Sniper._SetBoard("items")
    assert.is_not_nil(api.GC.Sniper._ItemsChecking())
    set(api.GC.Sniper.OnAuctionHouseShow, "ahOpen", false)
    assert.is_nil(api.GC.Sniper._ItemsChecking())
  end)
end)
