local helper = require("spec.spec_helper")

-- In game 2026-09-23 the owner could not tell why AUTO did nothing: `/gc board` printed
-- `auto: state=PAUSED reasons=[mail,buy]` while the button said little more than "AUTO". The
-- button now names what holds it in plain words, its tooltip says what to do about it, and a
-- mailbox the auction house has already closed no longer holds it for the whole visit.
describe("Auto says why it is not scanning", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 }, fgDim = { 0.55, 0.54, 0.52 },
          red = { 0.9, 0.28, 0.3 }, green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      Data = { GetItemValue = function() return nil end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/AutoScan.lua", GC) -- the real machine
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local feedAuto = upvalue(GC.Sniper.OnMailShow, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")
    local autoButtonText = upvalue(upvalue(feedAuto, "refreshAutoButton"), "autoButtonText")
    return GC, feedAuto, autoScan, autoButtonText
  end

  after_each(function()
    _G.GetTime, _G.C_Timer, _G.Item, _G.C_PlayerInteractionManager, _G.Enum = nil, nil, nil, nil, nil
  end)

  it("names the pause on the button in plain words", function()
    local _, _, _, autoButtonText = loadSniper()
    assert.equal("AUTO · PAUSED: MAILBOX OPEN", autoButtonText("PAUSED", { mail = true }))
    assert.equal("AUTO · PAUSED: BUY TAB", autoButtonText("PAUSED", { buy = true }))
    assert.equal("AUTO · PAUSED: SELL TAB", autoButtonText("PAUSED", { sell = true }))
    -- Two at once: the button names the first, the tooltip names both.
    assert.equal("AUTO · PAUSED: MAILBOX OPEN", autoButtonText("PAUSED", { mail = true, buy = true }))
  end)

  it("says in the tooltip what holds it and what the player can do, every reason", function()
    local GC, feedAuto = loadSniper()
    feedAuto("toggleOn")
    feedAuto("pause:mail")
    feedAuto("pause:buy")
    assert.same({
      GC.L["Paused while the mailbox is open. Close it and Auto carries on."],
      GC.L["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."],
    }, GC.Sniper._AutoHelp())
    feedAuto("toggleOff")
    assert.same({}, GC.Sniper._AutoHelp())
  end)

  -- The start the machine asks for can be withheld with no pause reason at all -- the player
  -- busy on the auction house's own panes, or their own search on its Buy list -- and the button
  -- used to read a bare "AUTO" through all of it.
  it("says when it is waiting for the player rather than paused", function()
    local GC, feedAuto, autoScan, autoButtonText = loadSniper()
    local busy = true
    GC.AuctionHouseTab = { PlayerIsBusy = function() return busy end }
    feedAuto("toggleOn")
    autoScan:Tick(101)
    assert.equal("WAITING", autoScan:State())
    assert.equal("AUTO · WAITING FOR YOU", autoButtonText(autoScan:State(), autoScan:PauseReasons()))
    assert.equal(GC.L["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."],
      GC.Sniper._AutoHelp()[1])

    busy = false
    GC.Sniper._BrowseOwned = function() return true end
    autoScan:Tick(200)
    assert.equal("AUTO · WAITING: YOUR LIST", autoButtonText(autoScan:State(), autoScan:PauseReasons()))
  end)

  -- The mailbox and the auction house are one interaction at a time, so at an auction house
  -- open the mailbox is shut -- whether or not a MAIL_CLOSED said so.
  it("lets go of a mailbox pause the auction house has already closed", function()
    local GC, feedAuto, autoScan = loadSniper()
    feedAuto("toggleOn")
    GC.Sniper.OnMailShow()
    assert.is_true(autoScan:PauseReasons().mail)

    GC.Sniper._ClearStaleMailPause()

    assert.is_nil(autoScan:PauseReasons().mail)
  end)

  it("keeps it while the client still says the mailbox is open", function()
    local GC, feedAuto, autoScan = loadSniper()
    _G.Enum = { PlayerInteractionType = { MailInfo = 17 } }
    _G.C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(kind) return kind == 17 end }
    feedAuto("toggleOn")
    GC.Sniper.OnMailShow()

    GC.Sniper._ClearStaleMailPause()

    assert.is_true(autoScan:PauseReasons().mail)
  end)

  it("is asked at every auction house open, and its tooltip is built when hovered", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    local from = assert(text:find("function GC.Sniper.OnAuctionHouseShow()", 1, true))
    local to = assert(text:find("\nend\n", from, true))
    assert.is_truthy(text:sub(from, to):find("GC.Sniper._ClearStaleMailPause()", 1, true))
    assert.is_truthy(text:find("for _, line in ipairs(GC.Sniper._AutoHelp()) do", 1, true))
  end)
end)
