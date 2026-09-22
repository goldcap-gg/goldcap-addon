local helper = require("spec.spec_helper")

-- Live price caps, final review I5 + I6: what drainCapPings is allowed to do to the screen.
-- It rings the board (pingNewHotDeals, floored per item exactly as stampVerdict's own bell is)
-- and, when the player has opted in, reuses the row's own click path to open the buy window.
-- Neither reaches a protected purchase call -- those stay behind onDialogPrimaryClick's
-- hardware click (spec/sniper_purchase_wiring_spec.lua) -- but "opens a window" is still an
-- action taken out of the player's hands, so it may never take a window away from them.
--
-- Caps fixes 3e: and both wait for the row. The hit used to spend its announcement (GC.Caps
-- .Announce) and its bell floor the moment it was found, and the open looked for a row that
-- was merely IsShown -- so a hit found while the player was on another board, another tab or
-- with the window closed rang for nothing, opened nothing, and was never told again that
-- visit. A cap ping now waits in the queue until its row is on screen (bounded, and dropped
-- when the row leaves the board); the announcement is committed only when the ring plays there;
-- the open wants a visible row, a player not busy on Blizzard's own panes, and no other dialog
-- on screen -- and is retried once that dialog closes. Opens happen on the 0.25s ticker
-- (drainCapPings(true)), never from inside a render, so a dialog's own OnHide can never open
-- the next one from under itself.
describe("Caps stop-and-open", function()
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

  local now, clicked, rung, busy, settingsOpen

  local function load(stopAndOpen)
    now, clicked, rung, busy, settingsOpen = 100, {}, {}, false, false
    _G.GetTime = function() return now end
    _G.time = function() return 1000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      SearchForItemKeys = function() end,
    }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
          fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
        CapDeals = function(deals) return deals end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      AuctionHouseTab = { PlayerIsBusy = function() return busy end },
      SettingsUI = { IsShown = function() return settingsOpen end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, board = "items",
        capStopAndOpen = stopAndOpen and true or false } } },
    }
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local drain = upvalue(upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows"), "drainCapPings")
    -- Hooks in place of the two things this may reach: the row's own click path, and the bell.
    set(drain, "onBuyClick", function(row) clicked[#clicked + 1] = row end)
    set(drain, "pingNewHotDeals", function(list) rung[#rung + 1] = list end)
    -- The window, as far as the drain looks at it: the board's ScrollFrame and the part of the
    -- screen it shows (UI coordinates, bottom-up, like Region:GetTop/GetBottom).
    set(GC.Sniper.OnAuctionHouseShow, "frame", { scroll = {
      GetTop = function() return 500 end, GetBottom = function() return 100 end } })
    return GC, drain
  end

  -- A realm cap row, put on the Items board and queued the way evaluateLiveItemDeal does.
  local function hit(GC, itemID, auctionID, unitPrice)
    local deal = { itemID = itemID, isCommodity = false, auctionID = auctionID,
      unitPrice = unitPrice or 80, cap = 100 }
    GC.Sniper._realmDeals[itemID] = deal
    GC.Sniper._QueueCapPing(deal)
    return deal
  end

  -- A pooled row carrying `deal`. `visible` is what IsVisible answers -- the row and every
  -- parent up to the screen shown -- and it is false for a row that is merely IsShown on a
  -- hidden board, tab or window.
  -- Geometry is the docked window's (about 805 wide): the row runs from the rail (84) to the
  -- scrollbar gutter (773).
  local function fakeRow(deal, visible)
    local row = { deal = deal, visible = visible ~= false, top = 480, left = 84, right = 773 }
    function row:IsShown() return true end
    function row:IsVisible() return self.visible end
    function row:GetTop() return self.top end
    function row:GetBottom() return self.top - 32 end
    function row:GetLeft() return self.left end
    function row:GetRight() return self.right end
    return row
  end
  -- The check drawer: 320 wide on the window's right edge, full height below the title bar
  -- (createDialog). On the docked window it covers the right part of every row -- price, profit,
  -- the button -- and leaves the item and its verdict chip in view.
  local function fakeDialog(row)
    local d = { row = row, deal = row and row.deal, shown = true, left = 485, right = 805 }
    function d:IsShown() return self.shown end
    function d:GetLeft() return self.left end
    function d:GetRight() return self.right end
    function d:GetTop() return 520 end
    function d:GetBottom() return 0 end
    return d
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetCoinTextureString, _G.C_Timer = nil, os.time, nil, nil
    _G.C_AuctionHouse = nil
  end)

  it("opens the buy window for the row it just rang", function()
    local GC, drain = load(true)
    local deal = hit(GC, 42, 1)
    local row = fakeRow(deal)
    set(drain, "rows", { row })

    drain(true)

    assert.same({ row }, clicked)
    assert.equal(GC.Sniper._rangAt[42], 100)
  end)

  it("rings from a render but leaves the opening to the ticker", function()
    local GC, drain = load(true)
    local deal = hit(GC, 42, 1)
    local row = fakeRow(deal)
    set(drain, "rows", { row })

    drain(false)
    assert.equal(1, #rung[1])
    assert.same({}, clicked)

    GC.Sniper._TickCapPings()
    assert.same({ row }, clicked)
    assert.same({}, rung[2]) -- rang once, not again for the open
  end)

  it("leaves a dialog the player is reading for another row exactly where it is", function()
    local GC, drain = load(true)
    local deal = hit(GC, 42, 1)
    local row, otherRow = fakeRow(deal), fakeRow({ itemID = 7 })
    set(drain, "rows", { row })
    set(drain, "dialog", fakeDialog(otherRow))

    drain(true)

    assert.same({}, clicked)
  end)

  it("never replaces a dialog left on screen with no row (a listing gone)", function()
    local GC, drain = load(true)
    local deal = hit(GC, 42, 1)
    set(drain, "rows", { fakeRow(deal) })
    set(drain, "dialog", fakeDialog(nil))

    drain(true)

    assert.same({}, clicked)
  end)

  it("opens it once the dialog for the other row has closed", function()
    local GC, drain = load(true)
    local deal = hit(GC, 42, 1)
    local row = fakeRow(deal)
    local dialog = fakeDialog(fakeRow({ itemID = 7 }))
    set(drain, "rows", { row })
    set(drain, "dialog", dialog)

    drain(true)
    assert.same({}, clicked)

    dialog.row, dialog.shown = nil, false
    drain(true)
    assert.same({ row }, clicked)
    assert.equal(1, #rung[1]) -- the bell rang the first time,
    assert.same({}, rung[2]) -- and only then
  end)

  -- Fix round 3: while the buy window is on screen for this very item AND owns its live state --
  -- armed or re-checking, the item pinned in activeItemID (round 4) -- the player is already
  -- looking at it. A ping for the item -- queued by the window's own Check when it sees a better
  -- price or a cheaper lot, or pending from before a manual open -- is settled right there:
  -- announced, with no bell and no open. Left queued, it rang the moment the player cancelled,
  -- and the next tick reopened the window on what they had just declined.
  --
  -- The window's pin, as openDialog/startRequery/armReady set it and abortRowPurchase/armCheck/
  -- showGoneState clear it: the file's own activeItemID table.
  local function activeItems(GC)
    local refreshRows = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows")
    return upvalue(upvalue(upvalue(refreshRows, "renderList"), "sortedDeals"), "activeItemID")
  end

  it("settles a ping for the item whose buy window is already open: no bell, no open, told", function()
    local GC, drain = load(true)
    local deal = hit(GC, 42, 1)
    local row = fakeRow(deal)
    set(drain, "rows", { row })
    set(drain, "dialog", fakeDialog(row))
    activeItems(GC)[42] = true

    drain(true)

    assert.same({}, clicked)
    assert.same({}, rung[1])
    assert.is_false(GC.Caps.IsNews(deal))
  end)

  it("does not ring or reopen what the window's own Check found once the player cancels", function()
    local GC, drain = load(true)
    local first = hit(GC, 42, 1)
    local row = fakeRow(first)
    local window = fakeDialog(row)
    set(drain, "rows", { row })
    set(drain, "dialog", window)
    activeItems(GC)[42] = true
    drain(true)

    -- The window's live Check sees a cheaper lot for the item and queues it, under the window.
    local cheaper = hit(GC, 42, 2, 60)
    drain(false)
    window.shown, window.row = false, nil -- the player cancels
    activeItems(GC)[42] = nil
    row.deal = cheaper
    drain(true)
    drain(true)

    assert.same({}, clicked)
    for i = 1, #rung do assert.same({}, rung[i]) end
  end)

  it("settles a ring still held by the floor when the player opens the item's window by hand", function()
    local GC, drain = load(false)
    GC.Sniper._rangAt[42] = now
    local deal = hit(GC, 42, 1)
    local row = fakeRow(deal)
    set(drain, "rows", { row })
    drain(true) -- held by the floor
    local window = fakeDialog(row) -- the player clicks the row (startRequery pins the item)
    set(drain, "dialog", window)
    activeItems(GC)[42] = true
    drain(false)

    window.shown = false -- and cancels
    activeItems(GC)[42] = nil
    now = now + 31
    drain(true)

    for i = 1, #rung do assert.same({}, rung[i]) end
  end)

  -- Fix round 4: but a window that does NOT own the item's live state shows nothing new. After a
  -- Check that came back not buyable (armCheck releases the pin) or once the listing has gone
  -- (showGoneState: the notice stays up, with no row and no pin), a background drill can still
  -- find another lot at the player's price -- and nothing puts it in that window. It takes the
  -- ordinary road: it rings where it lands, and it opens once the window is out of the way.
  it("rings a lot found while the window says the listing is gone, and opens it after Close", function()
    local GC, drain = load(true)
    local gone = hit(GC, 42, 1)
    local row = fakeRow(gone)
    local notice = fakeDialog(row)
    notice.row = nil -- showGoneState: the notice stays, the row is released, no pin
    set(drain, "rows", { row })
    set(drain, "dialog", notice)
    drain(false) -- the first lot's own ping is dealt with; what matters is the next one
    rung, clicked = {}, {}
    now = now + 60 -- the repost lands a minute later, past the first lot's bell floor

    local repost = hit(GC, 42, 2, 70) -- a drill finds a new lot at the player's price
    row.deal = repost -- the released row renders it
    drain(true)
    assert.same({ repost }, rung[1])
    assert.same({}, clicked) -- the notice is still on screen: no window replaces it

    notice.shown = false -- the player closes the notice
    drain(true)
    assert.same({ row }, clicked)
  end)

  it("rings a lot found while the window shows a Check that came back not buyable", function()
    local GC, drain = load(true)
    local first = hit(GC, 42, 1)
    local row = fakeRow(first) -- frozen under the window on the lot it checked
    local window = fakeDialog(row) -- armCheck: the window stays, the pin is released
    set(drain, "rows", { row })
    set(drain, "dialog", window)
    drain(false)
    rung, clicked = {}, {}
    now = now + 60 -- past the first lot's bell floor

    local other = hit(GC, 42, 2, 70)
    drain(true)
    assert.is_true(GC.Caps.IsNews(other)) -- not settled: that window never shows it

    window.shown, window.row = false, nil -- the player cancels
    row.deal = other -- and the board renders the lot it did not show
    drain(true)
    assert.same({ other }, rung[#rung])
    assert.same({ row }, clicked)
  end)

  it("opens one window per drain, not one per hit", function()
    local GC, drain = load(true)
    local rowA, rowB = fakeRow(hit(GC, 42, 1)), fakeRow(hit(GC, 43, 2))
    set(drain, "rows", { rowA, rowB })

    drain(true)

    assert.same({ rowA }, clicked)
  end)

  it("opens nothing at all when the player has not opted in", function()
    local GC, drain = load(false)
    set(drain, "rows", { fakeRow(hit(GC, 42, 1)) })

    drain(true)

    assert.same({}, clicked)
    assert.equal(1, #rung[1]) -- the bell is not the opt-in; it always rings
  end)

  it("does not open while the player is busy on Blizzard's own panes, and does once they are not", function()
    local GC, drain = load(true)
    local row = fakeRow(hit(GC, 42, 1))
    set(drain, "rows", { row })
    busy = true

    drain(true)
    assert.equal(1, #rung[1]) -- the ring is not theirs to hold up
    assert.same({}, clicked)

    busy = false
    drain(true)
    assert.same({ row }, clicked)
  end)

  describe("a row the player cannot see", function()
    it("neither rings nor opens, and leaves the lot unannounced", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      set(drain, "rows", { fakeRow(deal, false) }) -- shown, under a hidden board or window

      drain(true)

      assert.same({}, rung[1])
      assert.same({}, clicked)
      assert.is_nil(GC.Sniper._rangAt[42])
      assert.is_true(GC.Caps.IsNews(deal))
    end)

    it("rings and opens once it is on screen", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal, false)
      set(drain, "rows", { row })
      drain(true)

      row.visible = true
      drain(true)

      assert.equal(deal, rung[2][1])
      assert.same({ row }, clicked)
      assert.is_false(GC.Caps.IsNews(deal))
    end)

    -- Fix round 1: the board is a real ScrollFrame and its row pool is not virtualised -- every
    -- stamped row is shown and anchored down the scroll child (createRow), so a row scrolled out
    -- of view is still IsVisible. Visible has to mean inside the part of the board on screen.
    it("neither rings nor opens a row scrolled out of the board's view, and does once it is in it", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal)
      row.top = 60 -- below the viewport's bottom edge (100): scrolled out of view
      set(drain, "rows", { row })

      drain(true)
      assert.same({}, rung[1])
      assert.same({}, clicked)
      assert.is_true(GC.Caps.IsNews(deal))

      row.top = 300 -- scrolled into view
      drain(true)
      assert.same({ deal }, rung[2])
      assert.same({ row }, clicked)
    end)

    it("counts a row cut in half by the view's edge as on screen only past its middle", function()
      local GC, drain = load(false)
      local row = fakeRow(hit(GC, 42, 1))
      row.top = 510 -- 10 px above the top edge, 22 px of it inside: its middle (494) is in view
      set(drain, "rows", { row })
      drain(true)
      assert.equal(1, #rung[1])

      local other = fakeRow(hit(GC, 43, 2))
      other.top = 520 -- only 12 px inside: its middle (504) is not
      set(drain, "rows", { other })
      drain(true)
      assert.same({}, rung[2])
    end)

    -- Fix round 3: below WIN.PANEL_SHIFT_MIN the check drawer lies over the list, but it covers
    -- exactly the rightmost 288 px of a row (320 wide, flush with the window's right edge; the
    -- row ends 32 px short of it), and at every width below 990 the item and its verdict chip
    -- stay in view. A row under the drawer is a row the player can see.
    it("rings a row the drawer only partly covers, its item and verdict still in view", function()
      local GC, drain = load(false)
      local deal = hit(GC, 42, 1)
      set(drain, "rows", { fakeRow(deal) }) -- the docked window
      set(drain, "dialog", fakeDialog(fakeRow({ itemID = 7 })))

      drain(true)
      assert.same({ deal }, rung[1])
    end)

    it("still rings it on a narrow window, where the drawer reaches past the row's middle", function()
      local GC, drain = load(false)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal)
      row.right = 648 -- a 680-wide undocked window: the row's middle (366) is under the drawer
      local drawer = fakeDialog(fakeRow({ itemID = 7 }))
      drawer.left, drawer.right = 360, 680
      set(drain, "rows", { row })
      set(drain, "dialog", drawer)

      drain(true)
      assert.same({ deal }, rung[1])
    end)

    -- Fix round 3: the settings sheet is another matter. It lies over the whole content area,
    -- every row entire, at every width (UI/SettingsFrame.lua), fifty levels above them.
    it("neither rings nor opens a row under the settings sheet, and does once settings close", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal)
      set(drain, "rows", { row })
      settingsOpen = true

      drain(true)
      assert.same({}, rung[1])
      assert.same({}, clicked)
      assert.is_true(GC.Caps.IsNews(deal))

      settingsOpen = false
      drain(true)
      assert.same({ deal }, rung[2])
      assert.same({ row }, clicked)
    end)

    it("waits for a row the render has not stamped yet (another board is on screen)", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      set(drain, "rows", {})
      drain(true)

      local row = fakeRow(deal)
      set(drain, "rows", { row })
      drain(true)

      assert.equal(deal, rung[2][1])
      assert.same({ row }, clicked)
    end)

    it("stops waiting once the row has left the board", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal, false)
      set(drain, "rows", { row })
      drain(true)

      GC.Sniper._realmDeals[42] = nil
      row.visible = true
      drain(true)

      assert.same({}, rung[2])
      assert.same({}, clicked)
    end)

    it("stops waiting once the lot on the board is a different one", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal, false)
      set(drain, "rows", { row })
      drain(true)

      GC.Sniper._realmDeals[42] = { itemID = 42, isCommodity = false, auctionID = 2, unitPrice = 90, cap = 100 }
      row.visible = true
      drain(true)

      assert.same({}, rung[2])
    end)

    it("stops waiting after its bound", function()
      local GC, drain = load(true)
      local deal = hit(GC, 42, 1)
      local row = fakeRow(deal, false)
      set(drain, "rows", { row })
      drain(true)

      now = now + 3600
      row.visible = true
      drain(true)

      assert.same({}, rung[2])
      assert.same({}, clicked)
    end)
  end)

  -- I6: the same per-item floor stampVerdict's own bell observes. A capped commodity whose
  -- book churns under the cap announces on every improvement, and every one of those still
  -- SHOWS on the board -- but a bell every few seconds stops carrying information.
  --
  -- Fix round 1: a ring the floor holds back is held, not spent. It used to be announced on the
  -- spot and dropped without a sound -- and the floor is not only the cap bell's: stampVerdict
  -- stamps it for an ordinary verdict too, so a cap row that came on screen within thirty seconds
  -- of some other bell for the item was never rung at all. It now waits, unannounced, and rings
  -- once the floor has passed (still bounded, still dropped when the row leaves).
  describe("the ring floor", function()
    it("holds a ring inside the floor back, unannounced, and plays it once the floor has passed", function()
      local GC, drain = load(false)
      local first = hit(GC, 42, 1)
      set(drain, "rows", { fakeRow(first) })
      drain(true)
      assert.equal(1, #rung[1])

      now = now + 5
      local second = hit(GC, 42, 2, 70)
      set(drain, "rows", { fakeRow(second) })
      drain(true)
      assert.same({}, rung[2])
      assert.is_true(GC.Caps.IsNews(second))

      now = now + 30 -- 35 s after the first bell
      drain(true)
      assert.same({ second }, rung[3])
      assert.is_false(GC.Caps.IsNews(second))
    end)

    it("does not let a floor stamped by another bell swallow a cap row's ring", function()
      local GC, drain = load(false)
      GC.Sniper._rangAt[42] = now -- an ordinary verdict bell for the item, a moment ago
      local deal = hit(GC, 42, 1)
      set(drain, "rows", { fakeRow(deal) })

      drain(true)
      assert.same({}, rung[1])
      assert.is_true(GC.Caps.IsNews(deal))

      now = now + 31
      drain(true)
      assert.same({ deal }, rung[2])
    end)

    it("still drops a held-back ring whose row leaves the board meanwhile", function()
      local GC, drain = load(false)
      GC.Sniper._rangAt[42] = now
      set(drain, "rows", { fakeRow(hit(GC, 42, 1)) })
      drain(true)

      GC.Sniper._realmDeals[42] = nil
      now = now + 31
      drain(true)
      assert.same({}, rung[2])
    end)

    it("rings again once the floor has passed", function()
      local GC, drain = load(false)
      set(drain, "rows", { fakeRow(hit(GC, 42, 1)) })
      drain(true)

      now = now + 3600
      set(drain, "rows", { fakeRow(hit(GC, 42, 2, 70)) })
      drain(true)
      assert.equal(1, #rung[2])
    end)

    it("never lets one item silence a different one", function()
      local GC, drain = load(false)
      set(drain, "rows", { fakeRow(hit(GC, 42, 1)) })
      drain(true)

      now = now + 5
      set(drain, "rows", { fakeRow(hit(GC, 43, 2)) })
      drain(true)
      assert.equal(1, #rung[2])
    end)
  end)

  -- Fix round 2: with the floor holding a ring back and the opt-in on, the drain opened the row
  -- without announcing it. The lot stayed news, so every re-decision of it -- the watch loop, the
  -- dialog's own Check -- queued it again as a fresh entry, and the next tick opened the window
  -- again over a player who had just cancelled it (each open also stopping the pass and pausing
  -- Auto), until the floor passed and a late bell rang for a window already shown. An open IS
  -- the announcement: the lot is told, and nothing re-decided about it is news any more.
  describe("an open is the announcement", function()
    local function hitCommodity(GC, itemID, unitPrice)
      local deal = { itemID = itemID, isCommodity = true, unitPrice = unitPrice, cap = 100 }
      GC.Sniper._PutCapRow(itemID, deal) -- the watchlist board: no scan has run in this spec
      GC.Sniper._QueueCapPing(deal)
      return deal
    end

    it("opens a realm lot the floor holds back once, and never rings it late", function()
      local GC, drain = load(true)
      GC.Sniper._rangAt[42] = now -- another bell for the item a moment ago
      local row = fakeRow(hit(GC, 42, 1))
      set(drain, "rows", { row })

      drain(true)
      assert.same({ row }, clicked)
      assert.same({}, rung[1])

      -- The player cancels; the dialog's own Check and the watch loop re-decide the same lot.
      row.deal = hit(GC, 42, 1)
      drain(true)
      now = now + 31 -- past the floor
      row.deal = hit(GC, 42, 1)
      drain(true)

      assert.same({ row }, clicked) -- no second open
      assert.same({}, rung[2])
      assert.same({}, rung[3]) -- and no late bell
    end)

    it("does the same for a commodity re-decided at the same price", function()
      local GC, drain = load(true)
      GC.Sniper._rangAt[42] = now
      local row = fakeRow(hitCommodity(GC, 42, 80))
      set(drain, "rows", { row })

      drain(true)
      assert.same({ row }, clicked)

      row.deal = hitCommodity(GC, 42, 80)
      now = now + 31
      drain(true)

      assert.same({ row }, clicked)
      assert.same({}, rung[1])
      assert.same({}, rung[2])
    end)

    it("still treats a better commodity price as a new opportunity", function()
      local GC, drain = load(true)
      GC.Sniper._rangAt[42] = now
      local row = fakeRow(hitCommodity(GC, 42, 80))
      set(drain, "rows", { row })
      drain(true)

      row.deal = hitCommodity(GC, 42, 70)
      now = now + 31
      drain(true)

      assert.equal(2, #clicked)
      assert.same({ row.deal }, rung[2])
    end)
  end)

  -- The ticker is the one place opens come from, so it has to be wired to the queue. Checked
  -- against the source: the ticker's body cannot run headless (it repaints the window's
  -- toolbar, which a spec without a frame does not have).
  it("is driven off the Auction House ticker", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local src = f:read("*a")
    f:close()
    local start = src:find("autoScanTicker = autoScanTicker or C_Timer.NewTicker(", 1, true)
    assert.is_number(start)
    local body = src:sub(start, src:find("\n  end)\n", start, true))
    assert.is_truthy(body:find("GC.Sniper._TickCapPings()", 1, true))
  end)
end)
