local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The welcome window (UI/WelcomeFrame.lua) drawn on API-shaped doubles: what each state puts in
-- front of the player, when it opens by itself, and the link box that cannot open a browser.
describe("welcome window", function()
  local GC, restore, savedTime, savedMac
  local NOW = 1800000000
  local DAY = 86400
  local URL = "https://goldcap.gg/downloads"

  -- What the client would hold: the game, where the prices came from, the save.
  local function client(opts)
    GC.Game = {
      Passport = function() return {} end,
      IsForever = function() return opts.forever == true end,
    }
    GC.Data = {
      OriginState = function() return opts.origin or "none" end,
      BundledTs = function() return opts.bundledTs end,
      AppDataError = function() return opts.appError end,
      ForeverPayload = function() return opts.crowdTs and { ts = opts.crowdTs } or nil end,
      DescribeImportError = function(reason) return "reason " .. tostring(reason) end,
    }
    GC.db = { welcome = opts.welcome or {}, imported = opts.importedTs and { ts = opts.importedTs } or nil }
    _G.GoldCap_AppData = opts.appData
  end

  local function text(fs) return W.state(fs).text end
  local function shown(r) return W.state(r).shown end
  local function window() return _G.GoldCapWelcome end

  before_each(function()
    restore = W.install()
    savedTime, savedMac = _G.time, _G.IsMacClient
    _G.time = function() return NOW end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.UIParent = W.CreateFrame("Frame")
    _G.UISpecialFrames = {}
    _G.ChatFontNormal = {}
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    GC.Theme.RefreshFonts("enUS")
    helper.loadModule("Core/Welcome.lua", GC)
    -- The window is named, and the client publishes a named frame as a global: the double does
    -- not, so the spec does it the way the client would.
    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, ...)
      local f = create(kind, name, parent, ...)
      if name then _G[name] = f end
      return f
    end
    helper.loadModule("UI/WelcomeFrame.lua", GC)
  end)

  after_each(function()
    restore()
    _G.time, _G.IsMacClient = savedTime, savedMac
    _G.CreateColor, _G.UIParent, _G.UISpecialFrames, _G.ChatFontNormal = nil, nil, nil, nil
    _G.GoldCapWelcome, _G.GoldCap_AppData = nil, nil
  end)

  it("greets a new player on their first visit with what GoldCap does and why DEALS is empty", function()
    client({ welcome = { firstRun = true }, bundledTs = NOW - 12 * DAY })
    GC.WelcomeUI.MaybeShow()
    local f = window()
    assert.is_true(shown(f))
    assert.equal("DIALOG", W.state(f).strata)
    assert.equal("WELCOME TO GOLDCAP", text(f.title))
    for i, name in ipairs({ "DEALS", "SELL", "BUY" }) do
      assert.equal(name, text(f.features[i].name))
      assert.is_true(shown(f.features[i].text))
    end
    assert.equal("Finds items listed below what they usually sell for, and checks each one before you buy.",
      text(f.features[1].text))
    assert.equal("Only the prices GoldCap came with, from 12d ago", text(f.card.status))
    assert.truthy(text(f.card.body):find("it finds no deals", 1, true))
    -- The way to fresh prices, in three steps around the link.
    assert.equal("GET GOLDCAP COMPANION", text(f.card.ctaTitle))
    assert.equal("1. Copy this link (Ctrl+C) and open it in your browser:", text(f.card.step1))
    assert.equal("2. Install GoldCap Companion and start it.", text(f.card.step2))
    assert.equal("3. Back in the game, type /reload.", text(f.card.step3))
    assert.is_true(shown(f.card.box))
    assert.equal(URL, f.card.box.edit:GetText())
    -- Opened by itself: the link waits for a click instead of taking the keyboard, and there is
    -- nothing yet to stop reminding about.
    assert.is_false(f.card.box.edit:HasFocus())
    assert.is_false(shown(f.quiet))
    assert.same({ seen = true, nextAt = NOW + 3 * DAY }, GC.db.welcome)
  end)

  it("tints the card in the state's colour: red for prices DEALS cannot use", function()
    client({ welcome = { firstRun = true }, bundledTs = NOW - DAY })
    GC.WelcomeUI.MaybeShow()
    local K = GC.Kit.Tokens.color
    local ring = W.state(window().card.ring).vertex
    assert.same({ K.loss[1], K.loss[2], K.loss[3], 0.5 }, ring)
    assert.same({ K.loss[1], K.loss[2], K.loss[3], 1 }, W.state(window().card.status).color)
  end)

  it("does not open again on the next visit before its interval is over", function()
    client({ welcome = { firstRun = true }, bundledTs = NOW - DAY })
    GC.WelcomeUI.MaybeShow()
    window():Hide()
    GC.WelcomeUI.MaybeShow()
    assert.is_false(shown(window()))
  end)

  it("leaves a player who had GoldCap and whose Companion is fresh alone", function()
    client({ origin = "app", importedTs = NOW - 3600 })
    GC.WelcomeUI.MaybeShow()
    assert.is_nil(window())
    assert.is_nil(GC.db.welcome.seen)
  end)

  it("shows a player whose Companion stopped only the prices, and offers Don't remind me", function()
    client({ origin = "app", importedTs = NOW - 2 * DAY })
    GC.WelcomeUI.MaybeShow()
    local f = window()
    assert.equal("YOUR GOLDCAP PRICES", text(f.title))
    assert.is_false(shown(f.sub))
    for _, row in ipairs(f.features) do assert.is_false(shown(row.text)) end
    assert.equal("The Companion last sent prices 2d ago", text(f.card.status))
    assert.equal("Not installed on this computer? It is here:", text(f.card.linkLabel))
    assert.is_false(shown(f.card.step1))
    assert.is_true(shown(f.quiet))
    assert.equal("Don't remind me", f.quiet.label)
    W.state(f.quiet).scripts.OnClick(f.quiet)
    assert.is_true(GC.db.welcome.quiet)
    assert.is_false(shown(f))
  end)

  it("names the reason a Companion write could not be read, and points at the latest version", function()
    client({ origin = "none", appError = { reason = "bad_header" }, appData = {} })
    GC.WelcomeUI.MaybeShow()
    local f = window()
    assert.equal("The Companion's prices could not be read", text(f.card.status))
    assert.truthy(text(f.card.body):find("(reason bad_header)", 1, true))
    assert.equal("The latest version is here:", text(f.card.linkLabel))
  end)

  it("forgets a saved Companion error once the Companion's file is gone: the install steps instead", function()
    client({ origin = "none", appError = { reason = "bad_header" }, bundledTs = NOW - DAY })
    GC.WelcomeUI.MaybeShow()
    assert.equal("Only the prices GoldCap came with, from 24h ago", text(window().card.status))
    assert.is_true(shown(window().card.step1))
  end)

  it("says plainly when GoldCap came with no prices for the region at all", function()
    client({ welcome = { firstRun = true } })
    GC.WelcomeUI.MaybeShow()
    assert.equal("No prices for your region yet", text(window().card.status))
    assert.equal("GoldCap came with no prices for your region, so DEALS finds no deals until GoldCap Companion brings them.",
      text(window().card.body))
  end)

  it("speaks WoW: Forever's own case: own scans, and the Companion as everyone's scans", function()
    client({ forever = true, welcome = { firstRun = true } })
    GC.WelcomeUI.MaybeShow()
    local f = window()
    assert.equal("Finds items listed below what a vendor pays, or far below their usual price.",
      text(f.features[1].text))
    assert.equal("Prices from your own scans only", text(f.card.status))
    assert.truthy(text(f.card.ctaSub):find("every GoldCap player scanned on your auction house", 1, true))
    local K = GC.Kit.Tokens.color
    assert.same({ K.warn[1], K.warn[2], K.warn[3], 1 }, W.state(f.card.status).color)
  end)

  it("opens for the player on /gc companion with the link selected, ready to copy", function()
    client({ origin = "manual", importedTs = NOW - 7200 })
    GC.slashHandlers.companion()
    local edit = window().card.box.edit
    assert.is_true(edit:HasFocus())
    assert.is_true(W.state(edit).highlighted)
    assert.is_true(GC.db.welcome.seen)
    -- The clock starts now (a paste is "warn": a week), so arriving at the auction house next
    -- does not open it again.
    assert.equal(NOW + 7 * DAY, GC.db.welcome.nextAt)
    assert.is_false(shown(window().quiet))
  end)

  it("draws fresh Companion prices green, with no steps and no link", function()
    client({ origin = "app", importedTs = NOW - 1800 })
    GC.CompanionUI.Show()
    local f = window()
    assert.equal("Fresh prices from the Companion, 30m ago", text(f.card.status))
    assert.is_false(shown(f.card.box))
    assert.is_false(shown(f.card.rule))
    assert.is_false(f.card.box.edit:HasFocus())
  end)

  it("puts the link back when the player types over it", function()
    client({})
    GC.CompanionUI.Show()
    local edit = window().card.box.edit
    edit:SetText("goldcap.gg/something")
    assert.equal(URL, edit:GetText())
  end)

  it("names the Mac's copy keys on a Mac", function()
    _G.IsMacClient = function() return true end
    client({ welcome = { firstRun = true } })
    GC.WelcomeUI.MaybeShow()
    assert.equal("1. Copy this link (Cmd+C) and open it in your browser:", text(window().card.step1))
  end)

  it("grows to hold its text", function()
    client({ welcome = { firstRun = true }, bundledTs = NOW - DAY })
    GC.WelcomeUI.MaybeShow()
    local f = window()
    local welcomeH = f:GetHeight()
    local cardH = f.card:GetHeight()
    assert.is_true(cardH > 150)
    assert.is_true(welcomeH > cardH + 150)
    f:Hide()
    GC.CompanionUI.Show() -- seen now: the prices alone
    assert.is_true(f:GetHeight() < welcomeH)
  end)

  -- Escape runs CloseAllWindows, which shuts UI panels and UISpecialFrames in one pass: listed
  -- there, the window took the auction house down with it. It keeps Escape to itself instead,
  -- and lets every other key go on to the player's bindings.
  it("shuts on Escape without letting it reach the auction house, and lets other keys through", function()
    client({ welcome = { firstRun = true } })
    GC.WelcomeUI.MaybeShow()
    local f = window()
    for _, name in ipairs(_G.UISpecialFrames) do assert.not_equal("GoldCapWelcome", name) end
    assert.is_true(f:IsKeyboardEnabled())
    assert.is_true(f:GetPropagateKeyboardInput())
    local onKey = W.state(f).scripts.OnKeyDown
    onKey(f, "W")
    assert.is_true(f:GetPropagateKeyboardInput())
    assert.is_true(shown(f))
    onKey(f, "ESCAPE")
    assert.is_false(f:GetPropagateKeyboardInput())
    assert.is_false(shown(f))
  end)

  it("stands down in combat: opened there it takes no keys, and a key in a fight changes nothing", function()
    _G.InCombatLockdown = function() return true end
    client({})
    GC.CompanionUI.Show()
    local f = window()
    assert.is_false(f:IsKeyboardEnabled())
    W.state(f).scripts.OnKeyDown(f, "ESCAPE")
    assert.is_true(shown(f))
    _G.InCombatLockdown = nil
  end)

  it("opens nothing before the save is loaded, and nothing on top of itself", function()
    client({ welcome = { firstRun = true } })
    GC.db = nil
    GC.WelcomeUI.MaybeShow()
    assert.is_nil(window())
    client({ welcome = { firstRun = true } })
    GC.CompanionUI.Show()
    local before = W.state(window()).raised
    GC.WelcomeUI.MaybeShow()
    assert.equal(before, W.state(window()).raised)
  end)
end)
