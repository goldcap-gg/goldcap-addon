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
--
-- With W.CLIENT_METRICS (a spec turns it on for itself, `false` again after), text is measured
-- closer to the client, for a spec that lays out tightly packed lines: CHAR_W and LINE_H are a
-- 12-point face's and scale with the size SetFont gave, a colour escape (|cAARRGGBB, |r) takes no
-- room, and a texture or atlas escape (|T..|t, |A..|a) the face's height plus its 2px offset, as
-- the coin a money figure ends in does.
local W = { CHAR_W = 6, LINE_H = 14, unknownEvents = {}, CLIENT_METRICS = false }

local STATE = setmetatable({}, { __mode = "k" })

function W.state(widget)
  return STATE[widget]
end

local function chars(text)
  local n = 0
  for _ in tostring(text or ""):gmatch("[^\128-\191]") do n = n + 1 end
  return n
end

-- How wide `text` draws on one line at `size` points (CLIENT_METRICS above).
local function measure(text, size)
  if not W.CLIENT_METRICS then return chars(text) * W.CHAR_W end
  local plain = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local icons
  plain, icons = plain:gsub("|[TA].-|[ta]", "")
  return chars(plain) * W.CHAR_W * size / 12 + icons * (size + 2)
end

local function lineHeight(size)
  if not W.CLIENT_METRICS then return W.LINE_H end
  return W.LINE_H * size / 12
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
  -- Region:CreateAnimationGroup, down to what an Alpha pulse uses. The group's state is the
  -- engine's, read back with IsPlaying, as the client does.
  function r:CreateAnimationGroup()
    local g, gs = {}, { playing = false, animations = {} }
    STATE[g] = gs
    function g:CreateAnimation(animationType)
      local a = { kind = animationType }
      function a:SetFromAlpha(v) self.from = v end
      function a:SetToAlpha(v) self.to = v end
      function a:SetDuration(v) self.duration = v end
      function a:SetSmoothing(v) self.smoothing = v end
      gs.animations[#gs.animations + 1] = a
      return a
    end
    function g:SetLooping(v) gs.looping = v end
    function g:Play() gs.playing = true; gs.plays = (gs.plays or 0) + 1 end
    function g:Stop() gs.playing = false end
    function g:IsPlaying() return gs.playing end
    s.animationGroups = s.animationGroups or {}
    s.animationGroups[#s.animationGroups + 1] = g
    return g
  end
  return r, s
end

function W.Texture(parent)
  local t, s = region("Texture", parent)
  function t:SetTexture(file) s.file = file end
  -- TextureBase:SetAtlas(atlas [, useAtlasSize]): the game's own art by its atlas name.
  function t:SetAtlas(atlas, useAtlasSize) s.atlas, s.useAtlasSize = atlas, useAtlasSize end
  function t:SetColorTexture(...) s.color = { ... } end
  function t:SetTextureSliceMargins(...) s.slice = { ... } end
  function t:SetVertexColor(...) s.vertex = { ... } end
  function t:SetDesaturated(flag) s.desaturated = flag and true or false end
  function t:SetBlendMode(mode) s.blend = mode end
  function t:SetTexCoord(...) s.texCoord = { ... } end
  -- Texture:SetMask(file): drawn through the file's alpha (a portrait's round mask).
  function t:SetMask(file) s.mask = file end
  function t:SetGradient(orientation, minColor, maxColor) s.gradient = { orientation, minColor, maxColor } end
  function t:SetAlpha(a) s.alpha = a end
  -- Texture:AddMaskTexture(mask) (SimpleTextureAPIDocumentation.lua): the mask's alpha cuts what
  -- the texture draws.
  function t:AddMaskTexture(mask) s.masks = s.masks or {}; s.masks[#s.masks + 1] = mask end
  return t
end

-- A MaskTexture (Frame:CreateMaskTexture, SimpleFrameAPIDocumentation.lua): placed like any region,
-- its file and wrap modes set by SetTexture(file, wrapModeHorizontal, wrapModeVertical).
function W.MaskTexture(parent)
  local m, s = region("MaskTexture", parent)
  function m:SetTexture(file, wrapH, wrapV) s.file, s.wrapH, s.wrapV = file, wrapH, wrapV end
  return m
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
  function f:SetNonSpaceWrap(v) s.nonSpaceWrap = v end
  function f:SetMaxLines(n) s.maxLines = n end
  function f:SetTextColor(r, g, b, a) s.color = { r, g, b, a or 1 } end
  function f:GetTextColor() return s.color[1], s.color[2], s.color[3], s.color[4] end
  function f:SetFont(path, size, flags) s.font = { path, size, flags }; return true end
  function f:GetFont() return s.font[1], s.font[2], s.font[3] end
  function f:GetStringWidth() return measure(s.text, s.font[2]) end
  -- The width the text would take on one line, whatever width the FontString was given.
  function f:GetUnboundedStringWidth() return measure(s.text, s.font[2]) end
  function f:GetStringHeight()
    if chars(s.text) == 0 then return 0 end
    if s.wordWrap ~= false and (s.width or 0) > 0 then
      return math.ceil(measure(s.text, s.font[2]) / s.width) * lineHeight(s.font[2])
    end
    return lineHeight(s.font[2])
  end
  function f:GetHeight() return s.height or f:GetStringHeight() end
  return f
end

-- CreateFrame's double. A Button is a Frame with the state methods Theme.Button calls.
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
  function f:GetChildren() return unpack(s.children) end
  function f:SetFrameLevel(level) s.level = level end
  function f:GetFrameLevel() return s.level end
  function f:SetFrameStrata(strata) s.strata = strata end
  -- Frame:SetAlpha: the frame's own alpha, which the client multiplies into everything it and its
  -- children draw (a Texture's SetAlpha, above, replaces its vertex alpha instead).
  function f:SetAlpha(a) s.alpha = a end
  function f:GetAlpha() return s.alpha or 1 end
  function f:EnableMouse(v) s.mouse = v and true or false end
  function f:IsMouseEnabled() return s.mouse == true end
  function f:SetID(id) s.id = id end
  function f:GetID() return s.id or 0 end
  function f:SetScript(name, fn) s.scripts[name] = fn end
  -- The client raises on an event name it does not know; a spec lists those in W.unknownEvents.
  function f:RegisterEvent(event)
    if W.unknownEvents[event] then error(("Attempt to register unknown event %q"):format(event), 2) end
    s.events = s.events or {}
    s.events[event] = true
  end
  -- Frame:RegisterUnitEvent: the event, for the listed units only.
  function f:RegisterUnitEvent(event, ...)
    if W.unknownEvents[event] then error(("Attempt to register unknown event %q"):format(event), 2) end
    s.events = s.events or {}
    s.events[event] = true
    s.unitEvents = s.unitEvents or {}
    s.unitEvents[event] = { ... }
  end
  function f:UnregisterEvent(event) if s.events then s.events[event] = nil end end
  function f:IsEventRegistered(event) return s.events ~= nil and s.events[event] == true end
  function f:RegisterForDrag(...) s.drag = { ... } end
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
  function f:CreateMaskTexture(_, layer, _, sublevel)
    local m = W.MaskTexture(f)
    STATE[m].layer = layer
    STATE[m].sublevel = sublevel
    return m
  end
  -- A window's own placement: dragging, staying on screen, coming to the front.
  function f:SetToplevel(v) s.toplevel = v and true or false end
  function f:SetClampedToScreen(v) s.clamped = v and true or false end
  function f:SetMovable(v) s.movable = v and true or false end
  function f:IsMovable() return s.movable == true end
  function f:StartMoving() s.moving = true end
  function f:StopMovingOrSizing() s.moving = false end
  function f:Raise() s.raised = (s.raised or 0) + 1 end
  -- The keyboard: whether the frame takes keys, and whether a key it took goes on to the bindings.
  -- The client starts a frame with neither.
  function f:EnableKeyboard(v) s.keyboard = v and true or false end
  function f:IsKeyboardEnabled() return s.keyboard == true end
  function f:SetPropagateKeyboardInput(v) s.propagate = v and true or false end
  function f:GetPropagateKeyboardInput() return s.propagate == true end
  -- EditBox: text, focus and selection. SetText runs OnTextChanged with userInput false, as the
  -- client does.
  if s.kind == "EditBox" then
    s.text, s.focus = "", false
    function f:SetFontObject(font) s.fontObject = font end
    function f:SetAutoFocus(v) s.autoFocus = v and true or false end
    function f:SetText(text)
      s.text = text
      if s.scripts.OnTextChanged then s.scripts.OnTextChanged(f, false) end
    end
    function f:GetText() return s.text end
    function f:SetCursorPosition(n) s.cursor = n end
    function f:SetFocus()
      if s.focus then return end
      s.focus = true
      if s.scripts.OnEditFocusGained then s.scripts.OnEditFocusGained(f) end
    end
    function f:ClearFocus()
      if not s.focus then return end
      s.focus, s.highlighted = false, false
      if s.scripts.OnEditFocusLost then s.scripts.OnEditFocusLost(f) end
    end
    function f:HasFocus() return s.focus end
    function f:HighlightText() s.highlighted = true end
  end
  -- ScrollFrame: its scroll child and offset, what UIPanelScrollFrameTemplate's users call. The
  -- template's ScrollBar is not built here (Theme.QuietScrollBar skips a scrollbar that is absent).
  if s.kind == "ScrollFrame" then
    s.scroll = 0
    function f:SetScrollChild(child) s.scrollChild = child end
    function f:GetScrollChild() return s.scrollChild end
    function f:SetVerticalScroll(v) s.scroll = v end
    function f:GetVerticalScroll() return s.scroll end
    function f:GetVerticalScrollRange()
      local child = s.scrollChild
      return math.max(0, (child and child:GetHeight() or 0) - f:GetHeight())
    end
    function f:UpdateScrollChildRect() end
    function f:EnableMouseWheel(v) s.wheel = v and true or false end
  end
  -- Button: the state methods Theme.Button uses. Enable and Disable run OnEnable/OnDisable on a
  -- change, as the client does.
  if s.kind == "Button" then
    s.enabled = true
    function f:RegisterForClicks(...) s.clicks = { ... } end
    function f:SetPushedTexture(t) s.pushed = t end
    function f:GetPushedTexture() return s.pushed end
    function f:IsEnabled() return s.enabled end
    function f:SetMotionScriptsWhileDisabled(on) s.motionWhileDisabled = on and true or false end
    function f:Enable()
      if s.enabled then return end
      s.enabled = true
      if s.scripts.OnEnable then s.scripts.OnEnable(f) end
    end
    function f:Disable()
      if not s.enabled then return end
      s.enabled = false
      if s.scripts.OnDisable then s.scripts.OnDisable(f) end
    end
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
