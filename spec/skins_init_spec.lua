require("spec.spec_helper")

describe("Skin applied at load", function()
  local GC, onEvent

  local function stubFrame()
    return setmetatable({}, { __index = function(t, k)
      if k == "GetFrameLevel" then return function() return 1 end end
      if k == "GetHeight" then return function() return 0 end end
      if k == "GetVerticalScroll" or k == "GetVerticalScrollRange" then return function() return 0 end end
      if k == "IsShown" then return function() return false end end
      if k == "GetPoint" or k == "GetFontString" then return function() return nil end end
      if k == "SetFont" then return function() return true end end
      if k == "CreateFontString" or k == "CreateTexture" then return function() return stubFrame() end end
      if k == "TitleText" then return { SetText = function() end } end
      if k == "SetScript" then return function(_, which, fn) if which == "OnEvent" then onEvent = fn end end end
      return function() end
    end })
  end

  local function load(db, prepare)
    onEvent = nil
    _G.CreateFrame = function() return stubFrame() end
    _G.UISpecialFrames, _G.SlashCmdList = {}, {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.GetTime = function() return 0 end
    _G.GoldCapDB = db
    GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^#") then
        assert(loadfile("GoldCap/" .. line:gsub("\\", "/")))("GoldCap", GC)
      end
    end
    toc:close()
    if prepare then prepare() end
    onEvent(nil, "ADDON_LOADED", "GoldCap")
  end

  -- A skin whose Apply raises (once it has written part of its palette), and what was printed.
  local function breaking(failing)
    local said = {}
    return said, function()
      local Skins = GC.Kit.Skins
      local apply = Skins.Apply
      Skins.Apply = function(id)
        if failing[id] then
          apply(id)
          error("broken skin")
        end
        return apply(id)
      end
      GC.Print = function(msg) said[#said + 1] = msg end
    end
  end

  local LINE = "the chosen skin could not be applied, so this session uses the GoldCap skin"

  after_each(function()
    _G.CreateFrame, _G.UISpecialFrames, _G.SlashCmdList = nil, nil, nil
    _G.C_AddOns, _G.GoldCapDB, _G.GetTime = nil, nil, nil
  end)

  local function sameBg(def)
    local want, got = def.color.windowBottom, GC.Theme.color.bg
    for i = 1, 3 do assert.are.equal(want[i], got[i]) end
  end

  it("applies the saved skin before anything is built", function()
    load({ settings = { sniper = { skin = "forever" } } })
    sameBg(GC.Kit.Skins.defs.forever)
  end)

  it("a fresh install is goldcap", function()
    load(nil)
    assert.are.equal("goldcap", GC.db.settings.sniper.skin)
    sameBg(GC.Kit.Skins.defs.goldcap)
  end)

  it("a skin that fails to apply loads goldcap, says so once in the player's language, and loads the rest", function()
    local said, prepare = breaking({ horde = true })
    load({ settings = { locale = "ruRU", sniper = { skin = "horde" } } }, prepare)
    sameBg(GC.Kit.Skins.defs.goldcap)
    assert.are.equal("goldcap", GC.Kit.Skins.Current().id)
    assert.are.equal("Оформление", GC.L["Skin"])      -- the language was still settled
    assert.is_not_nil(GC.db)
    assert.are.equal("horde", _G.GoldCapDB.settings.sniper.skin)  -- never written back
    local lines = 0
    for _, msg in ipairs(said) do
      if msg == GC.L[LINE] then lines = lines + 1 end
    end
    assert.are.equal(1, lines)
    assert.are_not.equal(LINE, GC.L[LINE])            -- translated, not the English key
  end)

  it("still loads when goldcap itself fails to apply", function()
    local said, prepare = breaking({ horde = true, goldcap = true })
    load({ settings = { sniper = { skin = "horde" } } }, prepare)
    assert.is_not_nil(GC.db)
    assert.is_not_nil(GC.L)
    local lines = 0
    for _, msg in ipairs(said) do
      if msg == GC.L[LINE] then lines = lines + 1 end
    end
    assert.are.equal(1, lines)
  end)

  it("says nothing when the skin applies", function()
    local said, prepare = breaking({})
    load({ settings = { sniper = { skin = "pixel" } } }, prepare)
    for _, msg in ipairs(said) do assert.are_not.equal(GC.L[LINE], msg) end
  end)

  it("a broken saved id loads goldcap and keeps the stored value", function()
    load({ settings = { sniper = { skin = 42 } } })
    sameBg(GC.Kit.Skins.defs.goldcap)
    assert.are.equal(42, _G.GoldCapDB.settings.sniper.skin)
  end)
end)
