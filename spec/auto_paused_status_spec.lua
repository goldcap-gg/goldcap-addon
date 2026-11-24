local helper = require("spec.spec_helper")

-- The status line a paused Auto writes (GC.Sniper._PausedStatusText). WoW: Forever's gear loop
-- browses all gear in Auto's place on the Items board, where the chip reads AUTO · SCANNING: the
-- line says that loop runs, never "paused".
describe("the status line of a paused Auto", function()
  local GC

  local function load(forever, code)
    _G.GetTime = function() return 100 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    GC = {
      Theme = { ROW_H = 32, RAIL_W = 76, Scale = function() return 1 end, BOARD_TAB = {},
        pad = { xs = 4, s = 8, m = 12, l = 16 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 1, 1, 1 }, fgMuted = { 1, 1, 1 }, fgDim = { 1, 1, 1 },
          red = { 1, 0, 0 }, green = { 0, 1, 0 }, gold = { 1, 1, 0 } } },
      Data = { GetItemValue = function() return nil end },
      Game = { IsForever = function() return forever end, Passport = function() return {} end },
      db = { settings = { sniper = {} } },
    }
    for _, m in ipairs({ "Core/Util.lua", "Core/AutoScan.lua", "Core/BookPass.lua", "Core/DrillQueue.lua",
      "Core/KeyPoll.lua", "Core/AutoReadout.lua", "UI/SniperFrame.lua" }) do
      helper.loadModule(m, GC)
    end
    if forever then
      for _, m in ipairs({ "Core/DealMath.lua", "Core/FullScan.lua", "Core/ForeverFold.lua", "Core/ForeverDeals.lua",
        "Core/ForeverGearLoop.lua", "Core/ForeverValue.lua", "UI/SniperGearLoop_Camelot.lua" }) do
        helper.loadModule(m, GC)
      end
      assert.truthy(GC.Sniper._gear, "the gear loop did not load")
    end
    if code and code ~= "enUS" then helper.loadModule("Locale/" .. code .. ".lua", GC) end
    GC.ActivateLocale(code or "enUS")
  end
  after_each(function() _G.GetTime, _G.C_Timer, _G.Item, _G.CreateFrame = nil, nil, nil, nil end)

  local CASES = {
    { forever = true, reasons = { items = true }, line = "auto: browsing gear" },
    { forever = true, reasons = { items = true, mail = true }, line = "auto: paused" },
    { forever = true, reasons = { items = true, search = true }, line = "auto: paused" },
    { forever = true, reasons = { dialog = true }, line = "auto: paused" },
    { forever = true, reasons = { sell = true }, line = "auto: paused" },
    { forever = false, reasons = { items = true }, line = "auto: paused" },
    { forever = false, reasons = { mail = true }, line = "auto: paused" },
  }
  for _, case in ipairs(CASES) do
    local names = {}
    for reason in pairs(case.reasons) do names[#names + 1] = reason end
    table.sort(names)
    it(("says %q for %s in %s"):format(case.line, table.concat(names, "+"),
        case.forever and "WoW: Forever" or "retail WoW"), function()
      load(case.forever)
      assert.equal(case.line, GC.Sniper._PausedStatusText(case.reasons))
    end)
  end

  it("says it in the player's language", function()
    load(true, "deDE")
    assert.equal("auto: Ausrüstungsrunde läuft", GC.Sniper._PausedStatusText({ items = true }))
    assert.equal("auto: pausiert", GC.Sniper._PausedStatusText({ mail = true }))
  end)
end)
