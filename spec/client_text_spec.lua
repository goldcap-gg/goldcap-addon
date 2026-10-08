local helper = require("spec.spec_helper")

-- Text drawn with one of the CLIENT's fonts -- a MenuUtil menu, a tooltip, the chat frame, a
-- Blizzard template, a Theme.Label (it inherits GameFontHighlightSmall) -- is drawn in whatever
-- that client's face happens to cover, and a glyph it lacks is an empty box. Seen in game
-- 2026-10-01 on the Russian client: the BUY tab's list menu read "• Quick list [] 2 lines []
-- pasted", the bullet fine and every middle dot a box. The faces were then read from the
-- client's own font cache (Fonts/*.slug, its code point table): FRIZQT___CYR.TTF has no U+00B7,
-- U+2192, U+2212, U+2248, U+25B2 or U+25BC; FRIZQT__.TTF has the dot but none of the arrows or
-- triangles. GC.Util.ClientText is the one place such text is made drawable, and this file is
-- what keeps every such widget going through it.

-- ---------------------------------------------------------------------------------------------
-- Source reading. Strings and comments are masked out (same length, so positions survive) before
-- anything is matched, so a "(" inside a string or a call named in a comment counts for nothing.
-- ---------------------------------------------------------------------------------------------

local function readFile(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local function luaFiles(dir)
  local out = {}
  local listing = assert(io.popen('find GoldCap/' .. dir .. ' -name "*.lua" | sort'))
  for path in listing:lines() do out[#out + 1] = path end
  listing:close()
  return out
end

local ESCAPES = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v" }

-- Returns the source with every comment blanked and every string's body replaced by \1, and the
-- strings themselves ({ start, stop, value }) in the order they appear.
local function mask(src)
  local out, strings = {}, {}
  local i, n = 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i + 1, i + 1) == "-" then
      local level = src:match("^%[(=*)%[", i + 2)
      local stop
      if level then
        local _, e = src:find("]" .. level .. "]", i + 4 + #level, true)
        stop = e or n
      else
        stop = (src:find("\n", i, true) or (n + 1)) - 1
      end
      out[#out + 1] = (src:sub(i, stop):gsub("[^\n]", " "))
      i = stop + 1
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then
          local e = src:sub(j + 1, j + 1)
          local digits = src:match("^%d%d?%d?", j + 1)
          if digits then
            buf[#buf + 1] = string.char(tonumber(digits))
            j = j + 1 + #digits
          else
            buf[#buf + 1] = ESCAPES[e] or e
            j = j + 2
          end
        elseif d == c or d == "\n" then
          break
        else
          buf[#buf + 1] = d
          j = j + 1
        end
      end
      strings[#strings + 1] = { start = i, stop = j, value = table.concat(buf) }
      out[#out + 1] = c .. string.rep("\1", j - i - 1) .. c
      i = j + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local level = src:match("^%[(=*)%[", i)
      local open, close = "[" .. level .. "[", "]" .. level .. "]"
      local s, e = src:find(close, i + #open, true)
      s, e = s or (n + 1), e or n
      strings[#strings + 1] = { start = i, stop = e, value = src:sub(i + #open, s - 1) }
      out[#out + 1] = open .. string.rep("\1", e - i + 1 - #open - #close) .. close
      i = e + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out), strings
end

local function lineOf(src, pos)
  local _, count = src:sub(1, pos):gsub("\n", "")
  return count + 1
end

-- The argument spans of the call whose "(" is at `open`, on the masked text.
local function callArgs(masked, open)
  local depth, start, list = 0, open + 1, {}
  for k = open, #masked do
    local ch = masked:sub(k, k)
    if ch == "(" or ch == "{" or ch == "[" then
      depth = depth + 1
    elseif ch == ")" or ch == "}" or ch == "]" then
      depth = depth - 1
      if depth == 0 then
        list[#list + 1] = { start, k - 1 }
        return list, k
      end
    elseif ch == "," and depth == 1 then
      list[#list + 1] = { start, k - 1 }
      start = k + 1
    end
  end
  return list, #masked
end

local function trimSpan(masked, span)
  local a, b = span[1], span[2]
  while a <= b and masked:sub(a, a):match("%s") do a = a + 1 end
  while b >= a and masked:sub(b, b):match("%s") do b = b - 1 end
  return a, b
end

local function isAscii(value)
  return not value:find("[\128-\255]")
end

-- The names a file may use for the helper: the two GC.Util spellings, and any local alias of
-- them (`local tip = GC.Util.ClientText`).
local function wrapperNames(masked)
  local names = { "GC.Util.ClientText", "GC.Util.TooltipText" }
  for alias in masked:gmatch("local%s+([%w_]+)%s*=%s*GC%.Util%.ClientText[^%w_]") do names[#names + 1] = alias end
  for alias in masked:gmatch("local%s+([%w_]+)%s*=%s*GC%.Util%.TooltipText[^%w_]") do names[#names + 1] = alias end
  return names
end

-- Producers whose output is known not to carry a glyph: the client's own coin string.
local ASCII_PRODUCERS = { "GC.Util.CoinText" }

-- nil when the argument is fine, else why it is not. A bare name is fine when every assignment
-- to it in the file is (`local URL = "https://..."`, `shownText = GC.Util.ClientText(text)`).
local function judgeArg(file, a, b, nested)
  if a > b then return nil end
  local m = file.masked:sub(a, b)
  if m == "nil" or m:match("^%-?[%d%.]+$") then return nil end
  for _, s in ipairs(file.strings) do
    if s.start == a and s.stop == b then
      if isAscii(s.value) then return nil end
      return "a literal with non-ASCII text, not passed through GC.Util.ClientText"
    end
  end
  local function isCallOf(name)
    if m:sub(1, #name) ~= name then return false end
    local rest = m:sub(#name + 1)
    return rest:match("^%s*%b()$") ~= nil
  end
  for _, name in ipairs(file.wrappers) do
    if isCallOf(name) then return nil end
  end
  for _, name in ipairs(ASCII_PRODUCERS) do
    if isCallOf(name) then return nil end
  end
  if not nested and m:match("^[%a_][%w_]*$") then
    local init, assignments, allFine = 1, 0, true
    while true do
      local _, e = file.masked:find("[^%w_%.]" .. m .. "%s*=[^=]", init)
      if not e then break end
      -- The expression runs from just after the "=" to the end of its line.
      local stop = (file.masked:find("\n", e, true) or (#file.masked + 1)) - 1
      local x, y = trimSpan(file.masked, { e, stop })
      if judgeArg(file, x, y, true) then
        allFine = false
        break
      end
      assignments = assignments + 1
      init = e
    end
    if allFine and assignments > 0 then return nil end
  end
  return "not passed through GC.Util.ClientText"
end

local function loadSource(path)
  local src = readFile(path)
  local masked, strings = mask(src)
  return { path = path, src = src, masked = "\n" .. masked, strings = strings,
    wrappers = wrapperNames(masked) }
end

-- Masked text is prefixed with one "\n" so a pattern may look one character back at position 1;
-- string spans are shifted by the same one here.
local function shiftStrings(file)
  for _, s in ipairs(file.strings) do s.start, s.stop = s.start + 1, s.stop + 1 end
  return file
end

local SOURCES = {}
local function sources()
  if #SOURCES == 0 then
    for _, dir in ipairs({ "Core", "UI" }) do
      for _, path in ipairs(luaFiles(dir)) do SOURCES[#SOURCES + 1] = shiftStrings(loadSource(path)) end
    end
  end
  return SOURCES
end

-- Every call matching `pattern` (which ends at the call's "("), with the listed argument
-- positions judged.
local function auditCalls(file, pattern, positions, problems, what)
  local init = 1
  while true do
    local s, e = file.masked:find(pattern, init)
    if not s then break end
    local spans = callArgs(file.masked, e)
    for _, index in ipairs(positions) do
      local span = spans[index]
      if span then
        local a, b = trimSpan(file.masked, span)
        local why = judgeArg(file, a, b)
        if why then
          problems[#problems + 1] = ("%s:%d: %s argument %d is %s"):format(
            file.path, lineOf(file.masked, s) - 1, what, index, why)
        end
      end
    end
    init = e + 1
  end
end

describe("GC.Util.ClientText", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
  end)

  it("joins with a comma where the text used a middle dot", function()
    assert.equal("• Quick list, 2 lines, pasted", GC.Util.ClientText("• Quick list  ·  2 lines  ·  pasted"))
    assert.equal("9c, 547 listed, just now", GC.Util.ClientText("9c · 547 listed · just now"))
  end)

  -- A dot with no space either side is not a separator: it is part of a name, the way Chinese
  -- writes a transliterated one, and the Chinese faces have it.
  it("leaves a middle dot inside a word alone", function()
    assert.equal("阿尔萨斯·米奈希尔", GC.Util.ClientText("阿尔萨斯·米奈希尔"))
  end)

  it("spells the arrows and triangles the Friz faces lack in ASCII", function()
    assert.equal("Linen ×4 -> craft 2× (2 per craft)", GC.Util.ClientText("Linen ×4 → craft 2× (2 per craft)"))
    assert.equal("+12% over usual", GC.Util.ClientText("▲12% over usual"))
    assert.equal("-3%", GC.Util.ClientText("▼3%"))
  end)

  it("keeps every glyph the client faces do draw, and every script", function()
    for _, text in ipairs({ "• bullet", "a — b", "wait…", "×40", "Льняная ткань", "리넨", "亚麻布",
      "«цитата»", "„Zitat“", "¿Comprar?" }) do
      assert.equal(text, GC.Util.ClientText(text))
    end
  end)

  it("leaves colour codes, links and textures intact", function()
    local link = "|cff1eff00|Hitem:2589::::::::70:::::|h[Linen Cloth]|h|r"
    assert.equal("|cffffd100GoldCap|r: " .. link .. ", 12|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
      GC.Util.ClientText("|cffffd100GoldCap|r: " .. link .. " · 12|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"))
  end)

  it("is idempotent and passes anything that is not a string through", function()
    local once = GC.Util.ClientText("a · b → c ▲1")
    assert.equal(once, GC.Util.ClientText(once))
    assert.is_nil(GC.Util.ClientText(nil))
    assert.equal(5, GC.Util.ClientText(5))
  end)

  -- The Sold tab's tooltips were written against this name before the helper covered menus,
  -- chat and labels too. One implementation, two names.
  it("is what GC.Util.TooltipText is", function()
    assert.equal(GC.Util.ClientText, GC.Util.TooltipText)
  end)
end)

describe("Theme: a FontString in a client face", function()
  local GC

  local function stubRegion()
    local f = { points = {}, scripts = {} }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:HookScript(name, fn) self.scripts[name] = fn end
    function f:RegisterForClicks(kind) self.clicks = kind end
    function f:EnableMouse(enabled) self.mouseEnabled = enabled end
    function f:SetJustifyH(v) self.justify = v end
    function f:SetWordWrap(v) self.wordWrap = v end
    function f:SetMaxLines(n) self.maxLines = n end
    function f:SetText(text) self.drawn = text end
    function f:GetText() return self.drawn end
    function f:SetTextColor(...) self.color = { ... } end
    function f:SetFont(path, size, flags) self.font = { path, size, flags } end
    function f:GetFont() return "Fonts\\FRIZQT___CYR.TTF", 12, "" end
    function f:SetColorTexture(...) self.colorTexture = { ... } end
    function f:SetVertexColor(...) self.vertex = { ... } end
    function f:SetTexture(t) self.texture = t end
    function f:SetTextureSliceMargins(...) self.slice = { ... } end
    function f:SetTextureSliceMode(m) self.sliceMode = m end
    function f:SetBlendMode(mode) self.blend = mode end
    function f:SetAllPoints(rel) self.allPoints = rel end
    function f:SetAlpha(a) self.alpha = a end
    function f:SetDrawLayer(l) self.layer = l end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture() return stubRegion() end
    function f:CreateFontString() return stubRegion() end
    return f
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    _G.CreateFrame = function() return stubRegion() end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
  end)

  it("draws a Label's text through ClientText", function()
    local label = GC.Theme.Label(stubRegion(), 11)
    label:SetText("Linen ×4 · item level 200+ → craft")
    assert.equal("Linen ×4, item level 200+ -> craft", label.drawn)
  end)

  it("does so for a plain button's label, which is a Label", function()
    local button = GC.Theme.Button(stubRegion(), "ghost")
    button:SetLabel("a · b")
    assert.equal("a, b", button.text.drawn)
    assert.equal("a · b", button.label)
  end)

  -- A rounded button draws in GoldCap's own face (T.FONT_UI), which has the triangle the list
  -- picker ends in; only the client's faces need the text changed.
  it("leaves a rounded button's label as written", function()
    local button = GC.Theme.Button(stubRegion(), "ghost", "plaque")
    button:SetLabel("Quick list ▼")
    assert.equal("Quick list ▼", button.text.drawn)
  end)

  it("wraps a FontString once however often it is handed over", function()
    local fs = stubRegion()
    GC.Theme.ClientFont(fs)
    local first = fs.SetText
    assert.equal(fs, GC.Theme.ClientFont(fs))
    assert.equal(first, fs.SetText)
    fs:SetText("x · y")
    assert.equal("x, y", fs.drawn)
  end)
end)

describe("client-font sinks", function()
  it("hand every tooltip line, menu entry and chat line to ClientText", function()
    local problems = {}
    for _, file in ipairs(sources()) do
      auditCalls(file, ":AddLine%s*%(", { 1 }, problems, "AddLine")
      auditCalls(file, ":AddDoubleLine%s*%(", { 1, 2 }, problems, "AddDoubleLine")
      auditCalls(file, "[Tt]ooltip:SetText%s*%(", { 1 }, problems, "tooltip SetText")
      -- A Blizzard frame template's title (BasicFrameTemplateWithInset's TitleText, SetTitle).
      auditCalls(file, "%.TitleText:SetText%s*%(", { 1 }, problems, "TitleText:SetText")
      auditCalls(file, ":SetTitle%s*%(", { 1 }, problems, "SetTitle")
      for _, method in ipairs({ "CreateTitle", "CreateButton", "CreateRadio", "CreateCheckbox" }) do
        auditCalls(file, ":" .. method .. "%s*%(", { 1 }, problems, method)
      end
      auditCalls(file, "[^%w_%.:]print%s*%(", { 1 }, problems, "print")
      auditCalls(file, ":AddMessage%s*%(", { 1 }, problems, "AddMessage")
    end
    assert.same({}, problems)
  end)

  -- A radio menu built from a list takes its texts from table entries, not from a call this file
  -- can see: the entries themselves are what must be wrapped.
  it("hand a radio menu's entries to ClientText", function()
    local problems, seen = {}, 0
    for _, file in ipairs(sources()) do
      for list in file.masked:gmatch("CreateRadioContextMenu%b()") do
        local name = list:match("unpack%(%s*([%w_]+)%s*%)")
        assert.is_not_nil(name, file.path .. ": a radio menu whose entries this spec cannot find")
        seen = seen + 1
        local pattern = name .. "%[#" .. name .. "%s*%+%s*1%]%s*=%s*{"
        local init, found = 1, 0
        while true do
          local _, e = file.masked:find(pattern, init)
          if not e then break end
          found = found + 1
          local spans = callArgs(file.masked, e)
          local a, b = trimSpan(file.masked, spans[1])
          local why = judgeArg(file, a, b)
          if why then problems[#problems + 1] = ("%s:%d: radio entry text is %s"):format(file.path, lineOf(file.masked, e) - 1, why) end
          init = e + 1
        end
        assert.is_true(found > 0, file.path .. ": no entries found for " .. name)
      end
      -- Any other MenuUtil builder takes its texts some other way; teach this spec about it first.
      for builder in file.masked:gmatch("MenuUtil%.(Create[%w_]*Menu)%s*%(") do
        assert.is_true(builder == "CreateContextMenu" or builder == "CreateRadioContextMenu",
          file.path .. ": MenuUtil." .. builder .. " is not covered by this spec")
      end
      for builder in file.masked:gmatch("menu%.(Create[%w_]*Menu)%s*%(") do
        assert.is_true(builder == "CreateContextMenu" or builder == "CreateRadioContextMenu",
          file.path .. ": MenuUtil." .. builder .. " is not covered by this spec")
      end
    end
    assert.is_true(seen > 0)
    assert.same({}, problems)
  end)

  it("print through GC.Print, which cleans what it prints", function()
    local init = readFile("GoldCap/Core/Init.lua")
    local body = init:match("function GC%.Print%(msg%)(.-)\nend")
    assert.is_not_nil(body)
    assert.matches("GC%.Util%.ClientText", body)
  end)

  -- A FontString built from one of Blizzard's font objects draws in the client's face. Theme's
  -- ClientFont makes its SetText go through the helper, so it has to be applied where the
  -- FontString is made: the same statement.
  it("make every FontString built from a client font object a ClientFont", function()
    local problems = {}
    for _, file in ipairs(sources()) do
      local init = 1
      while true do
        local s, e = file.masked:find("[%w_%.]+:CreateFontString%s*%(", init)
        if not s then break end
        local spans = callArgs(file.masked, e)
        if #spans >= 3 then
          local before = file.masked:sub(math.max(1, s - 80), s - 1):match("ClientFont%s*%(%s*$")
          if not before then
            problems[#problems + 1] = ("%s:%d: a FontString from a client font object outside Theme.ClientFont")
              :format(file.path, lineOf(file.masked, s) - 1)
          end
        end
        init = e + 1
      end
    end
    assert.same({}, problems)
  end)

  -- Blizzard's own templates and font objects: a button template's label, an edit box set to a
  -- chat font. Whatever GoldCap writes into them goes through the helper.
  it("hand template buttons and font-object edit boxes their text through ClientText", function()
    local problems = {}
    local TEXT_TEMPLATES = { "UIPanelButtonTemplate", "AuctionHouseFrameTabTemplate" }
    for _, file in ipairs(sources()) do
      local names = {}
      -- Templates are named in strings, which the mask blanks; find them in the source instead.
      for _, template in ipairs(TEXT_TEMPLATES) do
        for name in file.src:gmatch("([%w_%.]+)%s*=%s*CreateFrame%([^\n]-\"" .. template .. "\"") do
          names[name] = true
        end
      end
      -- An edit box given a chat font is also reached as `f.edit` or, in its own handlers, `self`.
      local fontObjects = false
      for name in file.masked:gmatch("([%w_]+):SetFontObject%s*%(") do
        names[name], fontObjects = true, true
      end
      if fontObjects then names.self = true end
      for name in pairs(names) do
        local escaped = name:gsub("%.", "%%.")
        auditCalls(file, "[^%w_%.]" .. escaped .. ":SetText%s*%(", { 1 }, problems, name .. ":SetText")
        auditCalls(file, "%." .. escaped .. ":SetText%s*%(", { 1 }, problems, name .. ":SetText")
      end
    end
    assert.same({}, problems)
  end)

  -- No static popup exists today. One added later is another client-font sink; this spec has to
  -- learn about it first.
  it("has no StaticPopup this spec does not know about", function()
    for _, file in ipairs(sources()) do
      assert.is_nil(file.masked:find("StaticPopup", 1, true), file.path .. ": add StaticPopup text to this audit")
    end
  end)
end)

-- Every glyph GoldCap writes anywhere, against what the faces that draw it hold -- read from the
-- faces themselves (docs/addon/AGENTS.md, "Text"): the bundled Fira faces (Fira Mono has · → ▲ ▼; Fira Sans and Fira Sans Condensed have · → and no triangles, so their text goes through GC.Util.ClientText), the client's
-- FRIZQT__ and FRIZQT___CYR (menus, tooltips, labels), and 2002 and the two Kai faces (GoldCap's
-- own frames on Korean and Chinese). A new glyph fails here until somebody has looked it up.
describe("glyph inventory", function()
  local function codepoints(value)
    local out = {}
    -- A byte pattern ("[\194\226]") is not text: only whole sequences count.
    for ch in value:gmatch("[\192-\255][\128-\191]*") do
      local b1 = ch:byte(1)
      local cp
      if b1 < 0xE0 and #ch == 2 then cp = (b1 - 0xC0) * 64 + (ch:byte(2) - 0x80)
      elseif b1 >= 0xE0 and b1 < 0xF0 and #ch == 3 then
        cp = ((b1 - 0xE0) * 64 + (ch:byte(2) - 0x80)) * 64 + (ch:byte(3) - 0x80)
      elseif b1 >= 0xF0 and #ch == 4 then
        cp = (((b1 - 0xF0) * 64 + (ch:byte(2) - 0x80)) * 64 + (ch:byte(3) - 0x80)) * 64 + (ch:byte(4) - 0x80)
      end
      if cp then out[#out + 1] = { cp = cp, ch = ch } end
    end
    return out
  end

  local function isLetter(cp)
    return (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7) -- Latin-1 and Latin Extended
      or (cp >= 0x370 and cp <= 0x52F)     -- Greek, Cyrillic
      or (cp >= 0x1100 and cp <= 0x11FF) or (cp >= 0x3130 and cp <= 0x318F) or (cp >= 0xAC00 and cp <= 0xD7AF) -- Hangul
      or (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0xF900 and cp <= 0xFAFF) -- Han
      or (cp >= 0x3040 and cp <= 0x30FF)   -- kana
  end

  -- In every face listed above.
  local EVERY_FACE = { [0x2022] = "•", [0x2014] = "—", [0x2013] = "–", [0x2026] = "…", [0x00D7] = "×",
    [0x2019] = "’", [0x201C] = "“", [0x201D] = "”" }
  -- In the bundled face and the Korean and Chinese ones, missing from a Friz face: GoldCap's own
  -- figures may use them, and GC.Util.ClientText respells them for a client face.
  local CLIENT_TEXT = { [0x00B7] = "·", [0x2192] = "→", [0x25B2] = "▲", [0x25BC] = "▼" }
  -- European punctuation: in the bundled face and both Friz faces, not in the Chinese ones.
  -- Only a European language writes it, and in GoldCap's own frames that language draws in the
  -- bundled face.
  local EUROPEAN = { [0x00AB] = "«", [0x00BB] = "»", [0x201E] = "„", [0x00BF] = "¿", [0x00A0] = "no-break space" }
  local CJK_FILES = { koKR = true, zhCN = true, zhTW = true }

  it("holds only glyphs the faces that draw them have", function()
    local files = {}
    for _, dir in ipairs({ "Core", "UI", "Locale" }) do
      for _, path in ipairs(luaFiles(dir)) do files[#files + 1] = path end
    end
    local problems, seen = {}, {}
    for _, path in ipairs(files) do
      local code = path:match("Locale/(%a%a%u%u)%.lua$")
      local _, strings = mask(readFile(path))
      for _, s in ipairs(strings) do
        for _, g in ipairs(codepoints(s.value)) do
          local cp = g.cp
          local ok = isLetter(cp) or EVERY_FACE[cp] or CLIENT_TEXT[cp]
            or (EUROPEAN[cp] and not CJK_FILES[code])
            or (CJK_FILES[code] and ((cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF00 and cp <= 0xFFEF)))
          local key = path .. cp
          if not ok and not seen[key] then
            seen[key] = true
            problems[#problems + 1] = ("%s: U+%04X %s"):format(path, cp, g.ch)
          end
        end
      end
    end
    assert.same({}, problems)
  end)
end)
