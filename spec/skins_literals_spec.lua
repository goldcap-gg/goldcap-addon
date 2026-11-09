local helper = require("spec.spec_helper")

-- Every colour in UI code is a token read: a window colour follows the applied skin, a Blizzard
-- surface (the game tooltip, a menu, a popup, chat) reads the fixed set that never changes. A
-- literal that is right in every skin by design (white meaning "no tint" on art, a black shade)
-- stays, marked `-- untinted`; an escape on a Blizzard surface is marked `-- blizzard surface`.
describe("skins and literal colours", function()
  local CALLS = { "SetColorTexture", "SetVertexColor", "SetTextColor", "SetGradient", "CreateColor" }

  local function isComment(line) return line:match("^%s*%-%-") ~= nil end

  -- True for a colour call whose first argument is a number literal and whose line is not marked.
  local function literalCall(line)
    if isComment(line) or line:find("%-%- untinted%s*$") then return false end
    for _, name in ipairs(CALLS) do
      if line:find(name .. "%(%s*%-?%.?%d") then return true end
    end
    return false
  end

  -- True for a `|cff` escape of six hex digits that is not marked as a Blizzard surface's.
  local function literalEscape(line)
    if isComment(line) or line:find("%-%- blizzard surface%s*$") then return false end
    return line:find("|c[fF][fF]%x%x%x%x%x%x") ~= nil
  end

  -- The text of each AddLine / AddDoubleLine call in `text`, parentheses balanced, strings skipped.
  local function tooltipCalls(text)
    local calls, from = {}, 1
    while true do
      local s, e = text:find("Add[%a]*Line%(", from)
      if not s then break end
      local depth, i, quote = 1, e + 1, nil
      while depth > 0 and i <= #text do
        local ch = text:sub(i, i)
        if quote then
          if ch == "\\" then i = i + 1 elseif ch == quote then quote = nil end
        elseif ch == '"' or ch == "'" then quote = ch
        elseif ch == "(" then depth = depth + 1
        elseif ch == ")" then depth = depth - 1 end
        i = i + 1
      end
      calls[#calls + 1] = text:sub(s, i - 1)
      from = i
    end
    return calls
  end

  -- True for a tooltip call that colours with a literal triple or a window token.
  local function windowTooltipCall(call)
    call = call:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
    return call:find(",%s*%.?%d[%d.]*%s*,%s*%.?%d[%d.]*%s*,%s*%.?%d") ~= nil
      or call:find("Theme%.color%.") ~= nil or call:find("Tokens%.color%.") ~= nil
      or call:find("[^%w_.]K%.") ~= nil
  end

  local function eachUiFile(fn)
    local files = 0
    local listing = assert(io.popen("find GoldCap/UI -name '*.lua'"))
    for path in listing:lines() do
      files = files + 1
      local fh = assert(io.open(path, "r"))
      local text = fh:read("*a")
      fh:close()
      fn(path, text)
    end
    listing:close()
    assert.is_true(files > 20, "the walk found no UI files")
  end

  it("the call matcher flags a number as the first argument and passes tokens and marked lines", function()
    assert.is_true(literalCall("  hl:SetColorTexture(1, 1, 1, 0.08)"))
    assert.is_true(literalCall("  fs:SetTextColor(0.25, 0.85, 0.25)"))
    assert.is_true(literalCall("  tex:SetVertexColor(.5, 0, 0, 1)"))
    assert.is_true(literalCall("  x:SetGradient(\"VERTICAL\", CreateColor(0, 0, 0, 1), c)"))
    assert.is_false(literalCall("  hl:SetColorTexture(ink[1], ink[2], ink[3], 0.08)"))
    assert.is_false(literalCall("  hl:SetColorTexture(r, g, b, 0.08)"))
    assert.is_false(literalCall("  b.bg:SetVertexColor(1, 1, 1, 0) -- untinted"))
    assert.is_false(literalCall("  -- SetColorTexture(1, 1, 1, 1) is the old way"))
  end)

  it("the escape matcher flags a hex escape and passes tokens and marked lines", function()
    assert.is_true(literalEscape('  text = "|cff8c8a85" .. x .. "|r"'))
    assert.is_true(literalEscape('  text = "|cFFE8C15A"'))
    assert.is_false(literalEscape('  text = GC.Util.Colored(K.text3, x)'))
    assert.is_false(literalEscape('local LINK = "|cff71d5ff|Hx|h[y]|h|r" -- blizzard surface'))
    assert.is_false(literalEscape('  -- the |cff8c8a85 escape was here'))
    assert.is_false(literalEscape('  text = "|cn" .. name .. ":" .. x'))
  end)

  it("the tooltip matcher flags a literal or window colour and passes the fixed set", function()
    local function flagged(src) return windowTooltipCall(tooltipCalls(src)[1]) end
    assert.is_true(flagged('tip:AddLine(text, 1, 0.82, 0, true)'))
    assert.is_true(flagged('tip:AddDoubleLine(a, b, 0.65, 0.82, 1, 1, 1, 1)'))
    assert.is_true(flagged('tip:AddLine(text, Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])'))
    assert.is_true(flagged('tip:AddLine(text, K.text1[1], K.text1[2], K.text1[3])'))
    assert.is_false(flagged('tip:AddLine(text, B.tipTitle[1], B.tipTitle[2], B.tipTitle[3], true)'))
    assert.is_false(flagged('tip:AddLine(text, KB.text1[1], KB.text1[2], KB.text1[3])'))
    assert.is_false(flagged('tip:AddLine((GC.L["a (b, 1, 2, 3)"]):format(n), c[1], c[2], c[3])'))
    assert.is_false(flagged('GameTooltip:AddLine(" ")'))
  end)

  it("colour calls read tokens", function()
    local found = {}
    eachUiFile(function(path, text)
      local n = 0
      for line in (text .. "\n"):gmatch("(.-)\n") do
        n = n + 1
        if literalCall(line) then found[#found + 1] = path .. ":" .. n end
      end
    end)
    assert.same({}, found)
  end)

  it("escapes come from tokens", function()
    local found = {}
    eachUiFile(function(path, text)
      local n = 0
      for line in (text .. "\n"):gmatch("(.-)\n") do
        n = n + 1
        if literalEscape(line) then found[#found + 1] = path .. ":" .. n end
      end
    end)
    assert.same({}, found)
  end)

  it("tooltip lines read the Blizzard set, never a literal or a window token", function()
    local found = {}
    eachUiFile(function(path, text)
      for _, call in ipairs(tooltipCalls(text)) do
        if windowTooltipCall(call) then found[#found + 1] = path .. ": " .. call:sub(1, 70) end
      end
    end)
    assert.same({}, found)
  end)

  describe("a GoldCap tooltip", function()
    local GC, postCall, drawn
    local LINK = "|cnIQ2:|Hitem:501::::::::80:::::|h[Belt]|h|r"

    before_each(function()
      drawn = {}
      _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
      _G.Enum = { TooltipDataType = { Item = 0 } }
      _G.GameTooltip = {
        GetOwner = function() return { name = "bag button" } end,
        AddLine = function(_, _, r, g, b) drawn[#drawn + 1] = { r, g, b } end,
        AddDoubleLine = function(_, _, _, r1, g1, b1, r2, g2, b2)
          drawn[#drawn + 1] = { r1, g1, b1 }
          drawn[#drawn + 1] = { r2, g2, b2 }
        end,
      }
      _G.C_Item = { GetItemInfoInstant = function(link)
        local id = type(link) == "number" and link or tonumber(tostring(link):match("item:(%d+)"))
        return id, "", "", "", 0, 4, 4
      end }
      _G.GetCoinTextureString = function(n) return tostring(n) end
      GC = helper.loadModule("Core/Util.lua")
      helper.loadModule("Core/Trigger.lua", GC)
      GC.db = { settings = { tooltip = true } }
      GC.Data = { GetItemValue = function() return { mv = 123400, sold = 52.34, ts = time() } end }
      helper.loadModule("UI/Tooltip.lua", GC)
      helper.loadModule("UI/Kit/Skins.lua", GC)
    end)

    after_each(function()
      _G.TooltipDataProcessor, _G.Enum, _G.GameTooltip, _G.C_Item, _G.GetCoinTextureString = nil, nil, nil, nil, nil
    end)

    it("keeps today's colours in every skin", function()
      local B = GC.Kit.Tokens.blizzard
      GC.Kit.Skins.Apply("parchment")
      postCall(_G.GameTooltip, { hyperlink = LINK })
      assert.is_true(#drawn >= 4, "the tooltip drew no GoldCap lines")
      -- The label column is the game-tooltip blue, the figure column white: the same in Parchment.
      for i = 1, #drawn, 2 do
        assert.same({ B.tipLabel[1], B.tipLabel[2], B.tipLabel[3] }, drawn[i])
        assert.same({ B.tipWhite[1], B.tipWhite[2], B.tipWhite[3] }, drawn[i + 1])
      end
      assert.same({ 0.65, 0.82, 1 }, { B.tipLabel[1], B.tipLabel[2], B.tipLabel[3] })
    end)
  end)
end)
