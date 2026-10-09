-- API-shaped doubles of the client's widgets: a Frame (and Button), a FontString and a Texture
-- that carry only methods the real widgets have, and no fields at all. Whatever a double has to
-- remember lives in a side table, read by a spec through `W.state(widget)` -- so production code
-- cannot come to depend on a field only the double defines (spec/ui_widget_field_spec.lua has
-- the history of that: `.shown`, `.label`, `.points`).
--
-- A caller adds the fields Blizzard's own Lua or XML puts on a frame (a reward button's `type`,
-- a frame's parentKey children) itself, at the spec, where the comment can say where in
-- Blizzard's source the client sets them.
--
-- A FontString with word wrap and a width answers GetHeight with its wrapped height, the way the
-- client does for one whose height was never set (Blizzard's QuestInfo_ShowRewards measures its
-- own ItemChooseText that way): CHAR_W pixels a character, LINE_H a line.
local W = { CHAR_W = 6, LINE_H = 14 }

local STATE = setmetatable({}, { __mode = "k" })

function W.state(widget)
  return STATE[widget]
end

local function chars(text)
  local n = 0
  for _ in tostring(text or ""):gmatch("[^\128-\191]") do n = n + 1 end
  return n
end

-- Methods every region has: anchors, size, visibility, parent.
local function region(kind, parent)
  local r = {}
  local s = { kind = kind, parent = parent, shown = true, points = {}, width = 0, height = nil }
  STATE[r] = s
  function r:GetObjectType() return s.kind end
  function r:SetPoint(point, relativeTo, relativePoint, x, y)
    s.points[#s.points + 1] = { point, relativeTo, relativePoint, x, y }
  end
  function r:ClearAllPoints() s.points = {}; s.allPoints = nil end
  function r:SetAllPoints(relativeTo) s.allPoints = relativeTo or s.parent end
  function r:GetNumPoints() return #s.points end
  function r:GetPoint(i)
    local p = s.points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
  end
  function r:SetWidth(w) s.width = w end
  function r:SetHeight(h) s.height = h end
  function r:SetSize(w, h) s.width, s.height = w, h end
  function r:GetWidth() return s.width end
  function r:GetHeight() return s.height or 0 end
  function r:Show() s.shown = true end
  function r:Hide() s.shown = false end
  function r:SetShown(v) s.shown = v and true or false end
  function r:IsShown() return s.shown end
  function r:GetParent() return s.parent end
  function r:SetParent(p) s.parent = p end
  return r, s
end

function W.Texture(parent)
  local t, s = region("Texture", parent)
  function t:SetTexture(file) s.file = file end
  function t:SetColorTexture(...) s.color = { ... } end
  function t:SetTextureSliceMargins(...) s.slice = { ... } end
  function t:SetVertexColor(...) s.vertex = { ... } end
  function t:SetBlendMode(mode) s.blend = mode end
  function t:SetTexCoord(...) s.texCoord = { ... } end
  function t:SetGradient(orientation, minColor, maxColor) s.gradient = { orientation, minColor, maxColor } end
  function t:SetAlpha(a) s.alpha = a end
  return t
end

function W.FontString(parent, inherits)
  local f, s = region("FontString", parent)
  s.inherits, s.text, s.color = inherits, nil, { 1, 1, 1, 1 }
  s.font = { "Fonts\\FRIZQT__.TTF", 12, "" }
  function f:SetText(text) s.text = text end
  function f:GetText() return s.text end
  function f:SetJustifyH(v) s.justifyH = v end
  function f:SetJustifyV(v) s.justifyV = v end
  function f:SetWordWrap(v) s.wordWrap = v end
  function f:SetMaxLines(n) s.maxLines = n end
  function f:SetTextColor(r, g, b, a) s.color = { r, g, b, a or 1 } end
  function f:GetTextColor() return s.color[1], s.color[2], s.color[3], s.color[4] end
  function f:SetFont(path, size, flags) s.font = { path, size, flags }; return true end
  function f:GetFont() return s.font[1], s.font[2], s.font[3] end
  function f:GetStringWidth() return chars(s.text) * W.CHAR_W end
  function f:GetStringHeight()
    local n = chars(s.text)
    if n == 0 then return 0 end
    if s.wordWrap ~= false and (s.width or 0) > 0 then
      return math.ceil(n * W.CHAR_W / s.width) * W.LINE_H
    end
    return W.LINE_H
  end
  function f:GetHeight() return s.height or f:GetStringHeight() end
  return f
end

-- CreateFrame's double. A Button is a Frame here: the specs that use it need no button method.
function W.CreateFrame(kind, _, parent)
  local f, s = region(kind or "Frame", parent)
  s.level = 1
  s.children = {}
  if parent and STATE[parent] then
    s.level = (STATE[parent].level or 1) + 1
    local siblings = STATE[parent].children
    if siblings then siblings[#siblings + 1] = f end
  end
  s.scripts = {}
  function f:SetFrameLevel(level) s.level = level end
  function f:GetFrameLevel() return s.level end
  function f:SetFrameStrata(strata) s.strata = strata end
  function f:EnableMouse(v) s.mouse = v and true or false end
  function f:IsMouseEnabled() return s.mouse == true end
  function f:SetID(id) s.id = id end
  function f:GetID() return s.id or 0 end
  function f:SetScript(name, fn) s.scripts[name] = fn end
  function f:GetScript(name) return s.scripts[name] end
  function f:HookScript(name, fn) s.hooks = s.hooks or {}; s.hooks[name] = fn end
  function f:IsVisible()
    local p = f
    while p do
      local ps = STATE[p]
      if not ps or not ps.shown then return false end
      p = ps.parent
    end
    return true
  end
  function f:CreateFontString(_, layer, inherits)
    local fs = W.FontString(f, inherits)
    STATE[fs].layer = layer
    return fs
  end
  function f:CreateTexture(_, layer, _, sublevel)
    local t = W.Texture(f)
    STATE[t].layer = layer
    STATE[t].sublevel = sublevel
    return t
  end
  return f
end

-- Puts W.CreateFrame in place of the global for the length of a spec; `restore()` puts back what
-- was there.
function W.install()
  local saved = _G.CreateFrame
  _G.CreateFrame = W.CreateFrame
  return function() _G.CreateFrame = saved end
end

return W
