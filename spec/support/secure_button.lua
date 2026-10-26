-- API-shaped doubles of the client's secure parts, over spec/support/wow_frames.lua's widgets, for a
-- spec that drives a SecureActionButtonTemplate button (UI/DisenchantFrame.lua's).
--
-- - Every frame has SetAttribute and GetAttribute, as every frame in the client does.
-- - CreateFrame(kind, name, parent, template): a named frame is published as _G[name], as the client
--   publishes it; a frame made from SecureActionButtonTemplate is protected and carries the
--   template's own OnClick (Blizzard_FrameXML/SecureTemplates.xml: <OnClick
--   function="SecureActionButton_OnClick"/>), modelled below on SecureActionButton_OnClick and
--   OnActionButtonClick (live Blizzard_FrameXML/SecureTemplates.lua:762-829).
-- - A protected frame, and every frame a protected frame stands under (its parent, the parent's
--   parent: what hides or moves with it), refuses Show, Hide, SetShown, SetPoint, ClearAllPoints,
--   SetAllPoints, SetWidth, SetHeight, SetSize, SetParent, SetAttribute, Enable and Disable from
--   addon code while S.combat is on: the call raises, as the client blocks it (ADDON_ACTION_BLOCKED).
-- - InCombatLockdown answers S.combat. RegisterStateDriver keeps the frame's driver, as
--   Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua's manager does, and S.tick resolves
--   every driver the way its resolveDriver does: "visibility" shows or hides the frame, from secure
--   code, so in combat too; any other state sets the "state-<name>" attribute. Only the [combat]
--   condition is modelled. S.enterCombat and S.leaveCombat turn S.combat and tick once.
-- - S.click(button, mouseButton, down) is the player's click: the client hands it to the button only
--   when RegisterForClicks named its kind ("LeftButtonUp", or "AnyUp" and "AnyDown"), and runs
--   PreClick, OnClick and PostClick in that order. S.key(button) is a key bound to the button by a
--   CLICK binding: a click on the key's press and another on its release. Whether the engine sends
--   both is not in Blizzard's Lua; the double sends both, the case in which a button could act twice.
-- - A cast the template's OnClick makes is kept in S.casts: { spell, bag, slot } read from the
--   attributes as they stood at that click.
local W = require("spec.support.wow_frames")

local S = { combat = false, casts = {}, keyDownCVar = true }

local ATTRIBUTES = setmetatable({}, { __mode = "k" })
local SECURE = setmetatable({}, { __mode = "k" })
local DRIVERS = setmetatable({}, { __mode = "k" })
local GUARDED = { "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetWidth", "SetHeight",
  "SetSize", "SetParent", "SetAttribute", "Enable", "Disable" }

-- Secure code is running (a state driver): its calls are not addon code's.
local secureDepth = 0
local named = {}

local function protected(frame)
  for secure in pairs(SECURE) do
    local p = secure
    while p do
      if p == frame then return true end
      local st = W.state(p)
      p = st and st.parent
    end
  end
  return false
end

-- SecureButton_GetModifiedAttribute for the left button with no modifier held: "type1", "*type1",
-- then "type"; ATTRIBUTE_NOOP ("") reads as nothing.
local function modified(frame, name)
  local a = ATTRIBUTES[frame]
  local value = a[name .. "1"]
  if value == nil then value = a["*" .. name .. "1"] end
  if value == nil then value = a[name] end
  if value == "" then value = nil end
  return value
end

-- SecureActionButton_OnClick(self, inputButton, down), with no isKeyPress or isSecureAction (the
-- template's own call): acting on the down click when useOnKeyDown is on (the attribute, else the
-- ActionButtonUseKeyDown CVar), on the up click otherwise; a "spell" action casts the spell and,
-- while it waits for an item, targets the bag slot the target-bag and target-slot attributes name.
local function secureOnClick(self, _, down)
  local useOnKeyDown = ATTRIBUTES[self].useOnKeyDown
  if useOnKeyDown == nil then useOnKeyDown = S.keyDownCVar end
  local clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
  if not clickAction then return false end
  local spell = modified(self, "spell")
  if modified(self, "type") == "spell" and spell ~= nil then
    S.casts[#S.casts + 1] = { spell = tonumber(spell) or spell, bag = modified(self, "target-bag"),
      slot = modified(self, "target-slot") }
  end
  return true
end

local function create(kind, name, parent, template)
  local f = W.CreateFrame(kind, name, parent)
  ATTRIBUTES[f] = {}
  function f:SetAttribute(key, value) ATTRIBUTES[f][key] = value end
  function f:GetAttribute(key) return ATTRIBUTES[f][key] end
  for _, method in ipairs(GUARDED) do
    local original = f[method]
    if original then
      f[method] = function(self, ...)
        if S.combat and secureDepth == 0 and protected(self) then
          error(("ADDON_ACTION_BLOCKED: %s on a protected frame in combat"):format(method), 2)
        end
        return original(self, ...)
      end
    end
  end
  if type(template) == "string" and template:find("SecureActionButtonTemplate", 1, true) then
    SECURE[f] = true
    W.state(f).scripts.OnClick = secureOnClick
  end
  if type(name) == "string" and name ~= "" then
    _G[name] = f
    named[#named + 1] = name
  end
  return f
end

-- The first clause of `values` whose condition holds ("[combat] hide; show").
local function resolve(values)
  for clause in values:gmatch("[^;]+") do
    local condition, action = clause:match("^%s*%[(.-)%]%s*(%S+)%s*$")
    if condition then
      if (condition == "combat" and S.combat) or (condition == "nocombat" and not S.combat) then return action end
    else
      local bare = clause:match("^%s*(%S+)%s*$")
      if bare then return bare end
    end
  end
  return nil
end

function S.tick()
  secureDepth = secureDepth + 1
  for frame, drivers in pairs(DRIVERS) do
    for state, values in pairs(drivers) do
      local value = resolve(values)
      if state == "visibility" then
        if value == "show" then frame:Show() elseif value == "hide" then frame:Hide() end
      else
        ATTRIBUTES[frame]["state-" .. state] = value
      end
    end
  end
  secureDepth = secureDepth - 1
end

-- RegisterStateDriver hands the frame to the secure manager through its attributes, which addon
-- code cannot set in combat.
local function registerStateDriver(frame, state, values)
  if S.combat then error("ADDON_ACTION_BLOCKED: RegisterStateDriver in combat", 2) end
  DRIVERS[frame] = DRIVERS[frame] or {}
  DRIVERS[frame][state] = values
  S.tick()
end

function S.driver(frame, state)
  return DRIVERS[frame] and DRIVERS[frame][state]
end

function S.enterCombat()
  S.combat = true
  S.tick()
end

function S.leaveCombat()
  S.combat = false
  S.tick()
end

local function registered(frame, mouseButton, down)
  local kind = mouseButton .. (down and "Down" or "Up")
  local any = down and "AnyDown" or "AnyUp"
  for _, c in ipairs(W.state(frame).clicks or {}) do
    if c == kind or c == any then return true end
  end
  return false
end

function S.click(button, mouseButton, down)
  mouseButton = mouseButton or "LeftButton"
  down = down == true
  if not registered(button, mouseButton, down) or not button:IsEnabled() then return false end
  local scripts = W.state(button).scripts
  for _, name in ipairs({ "PreClick", "OnClick", "PostClick" }) do
    if scripts[name] then scripts[name](button, mouseButton, down) end
  end
  return true
end

function S.key(button)
  S.click(button, "LeftButton", true)
  S.click(button, "LeftButton", false)
end

-- Puts the doubles in place of the client's globals for the length of a spec; the function it
-- answers puts back what was there and forgets the frames it published by name.
function S.install()
  local saved = { CreateFrame = _G.CreateFrame, InCombatLockdown = _G.InCombatLockdown,
    RegisterStateDriver = _G.RegisterStateDriver }
  S.combat, S.casts, S.keyDownCVar = false, {}, true
  _G.CreateFrame = create
  _G.InCombatLockdown = function() return S.combat end
  _G.RegisterStateDriver = registerStateDriver
  return function()
    for k, v in pairs(saved) do _G[k] = v end
    for _, name in ipairs(named) do _G[name] = nil end
    named = {}
  end
end

return S
