local helper = require("spec.spec_helper")

-- A UI file that copies a token's channels when it loads freezes today's colour: the skin applied
-- later, at ADDON_LOADED, never reaches the copy. Tokens.alpha / Tokens.rgb return a table that
-- Skins.Apply rewrites in place instead.
describe("skins and colours taken at load", function()
  -- True for a line at column 1 that starts `local` and copies a colour's channels or runs a tint.
  local function copiesChannels(line)
    if line:sub(1, 6) ~= "local " then return false end
    if line:find("[%w_]+%.[%w_]+%[[123]%]") then return true end
    return line:find("tint%(") ~= nil and line:find("function tint", 1, true) == nil
  end

  it("the matcher flags a copy and passes an alias and a derived colour (positive control)", function()
    assert.is_true(copiesChannels("local RING = { K.gold[1], K.gold[2], K.gold[3], 0.5 }"))
    assert.is_true(copiesChannels("local RING = tint(K.gold, 0.5)"))
    assert.is_false(copiesChannels("local RING = GC.Kit.Tokens.alpha(\"gold\", 0.5)"))
    assert.is_false(copiesChannels("local PLAY = { gather = K.profit }"))
    assert.is_false(copiesChannels("  local inside = { K.gold[1], K.gold[2], K.gold[3] }"))
  end)

  it("no UI file copies a token's channels at load", function()
    local found, files = {}, 0
    local listing = assert(io.popen("find GoldCap/UI -name '*.lua'"))
    for path in listing:lines() do
      files = files + 1
      local fh = assert(io.open(path, "r"))
      local n = 0
      for line in fh:lines() do
        n = n + 1
        if copiesChannels(line) then found[#found + 1] = path .. ":" .. n end
      end
      fh:close()
    end
    listing:close()
    assert.is_true(files > 20, "the walk found no UI files")
    assert.same({}, found)
  end)

  it("a panel built after Apply('horde') is filled with Horde's window colour", function()
    local GC = helper.loadModule("UI/Theme.lua")
    local Tokens, Skins = GC.Kit.Tokens, GC.Kit.Skins
    local painted
    local tex = setmetatable({}, { __index = function() return function() end end })
    function tex:SetColorTexture(...) painted = painted or { ... } end
    local frame = { CreateTexture = function() return tex end }
    local saved = _G.CreateFrame
    _G.CreateFrame = function() return frame end
    Skins.Apply("horde")
    local ok, err = pcall(GC.Theme.Panel, nil)
    _G.CreateFrame = saved
    assert(ok, err)
    local top = Tokens.color.windowTop
    assert.same({ top[1], top[2], top[3] }, { painted[1], painted[2], painted[3] })
    -- Horde's window top, not goldcap's 151921.
    assert.is_true(math.abs(painted[1] - 0x1F / 255) < 1e-9)
  end)
end)
