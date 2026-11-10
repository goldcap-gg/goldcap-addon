local helper = require("spec.spec_helper")

-- A UI file that copies a token's channels when it loads freezes today's colour: the skin applied
-- later, at ADDON_LOADED, never reaches the copy. Tokens.alpha / Tokens.rgb return a table that
-- Skins.Apply rewrites in place instead.
describe("skins and colours taken at load", function()
  -- True for a line that copies a colour's channels (`a.b[1]`) or runs a tint( call.
  local function copies(line)
    if line:find("([%w_]+%.[%w_]+)%[1%]%s*,%s*%1%[2%]") then return true end
    return line:find("tint%(") ~= nil and line:find("function tint", 1, true) == nil
  end

  -- The offending lines of a file's text: those outside a body that opens on a column-1 line with `function` and closes on a column-1 `end`, so a
  -- copy made when a window is built is fine, one in a load-time constructor (indented or not) is not.
  local function offenders(lines)
    local bad, inFn = {}, false
    for n, line in ipairs(lines) do
      if line:match("^%S") and line:find("function", 1, true) and not line:find("end%s*[,)]*%s*$") then
        inFn = true
      elseif inFn and line:match("^end") then
        inFn = false
      elseif not inFn and copies(line) then
        bad[#bad + 1] = n
      end
    end
    return bad
  end

  it("the matcher flags load-time copies and passes aliases, derived colours and copies in functions", function()
    assert.same({ 1 }, offenders({ "local RING = { K.gold[1], K.gold[2], K.gold[3], 0.5 }" }))
    assert.same({ 1 }, offenders({ "local RING = tint(K.gold, 0.5)" }))
    assert.same({ 2 }, offenders({ "local V = {", "  active = { bg = { K.gold[1], K.gold[2], K.gold[3], 0.14 } },", "}" }))
    assert.same({}, offenders({ "local RING = GC.Kit.Tokens.alpha(\"gold\", 0.5)", "local PLAY = { gather = K.profit }" }))
    assert.same({}, offenders({ "local function f()", "  local c = { K.gold[1], K.gold[2], K.gold[3] }", "end",
      "function T.X()", "  return { K.gold[1], K.gold[2], 0 }", "end" }))
    -- Back at file level after a function ends, a copy is flagged again.
    assert.same({ 4 }, offenders({ "local function f()", "  return 1", "end", "local A = { K.gold[1], K.gold[2] }" }))
  end)

  it("no UI file copies a token's channels at load", function()
    local found, files = {}, 0
    local listing = assert(io.popen("find GoldCap/UI -name '*.lua'"))
    for path in listing:lines() do
      files = files + 1
      local fh = assert(io.open(path, "r"))
      local lines = {}
      for line in fh:lines() do lines[#lines + 1] = line end
      fh:close()
      for _, n in ipairs(offenders(lines)) do found[#found + 1] = path .. ":" .. n end
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
