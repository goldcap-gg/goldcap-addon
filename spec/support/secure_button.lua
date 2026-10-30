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
-- - InCombatLockdown answers S.combat. RegisterAttributeDriver(frame, attribute, values) keeps the
--   frame's driver and RegisterStateDriver(frame, state, values) is its "state-<state>" form, as
--   Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua's manager keeps them (live :8-29), and
--   S.tick resolves every driver the way its resolveDriver does (live :97-118): "state-visibility"
--   shows or hides the frame, from secure code, so in combat too; any other attribute is set to the
--   matching clause's action when there is one ("nil" sets nothing there, a number its number, an
--   empty action ""), and only when it differs from what the attribute holds. Only the [combat] and
--   [nocombat] conditions are modelled. S.enterCombat and S.leaveCombat turn S.combat and tick once,
--   as the manager rescans on PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED (live :193-194).
-- - S.click(button, mouseButton, down) is the player's click: the client hands it to the button only
--   when RegisterForClicks named its kind ("LeftButtonUp", or "AnyUp" and "AnyDown"), and runs
--   PreClick, OnClick and PostClick in that order. S.key(button) is a key bound to the button by a
--   CLICK binding: a click on the key's press and another on its release. Whether the engine sends
--   both is not in Blizzard's Lua; the double sends both, the case in which a button could act twice.
-- - A cast the template's OnClick makes is kept in S.casts: { spell, bag, slot } read from the
--   attributes as they stood at that click. After the action, whatever its type, a spell waiting for
--   an item (S.awaiting: SpellCanTargetItem, true after a cast of a spell in S.ITEM_SPELLS, or set by a
--   spec for another spell the player cast) is aimed at the target-bag and target-slot attributes
--   when target-slot reads as something (OnActionButtonClick, live SecureTemplates.lua:762-781): the
--   bag slot used is kept in S.targets, and in the waiting cast's bag and slot.
local W = require("spec.support.wow_frames")

local S = { combat = false, casts = {}, targets = {}, awaiting = nil, keyDownCVar = true, ITEM_SPELLS = { [13262] = true } }

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
-- ActionButtonUseKeyDown CVar), on the up click otherwise. A "spell" action casts the spell; then,
-- whatever the type, a spell waiting for an item is aimed at the bag slot the target-bag and
-- target-slot attributes name, when target-slot reads as something.
local function secureOnClick(self, _, down)
  local useOnKeyDown = ATTRIBUTES[self].useOnKeyDown
  if useOnKeyDown == nil then useOnKeyDown = S.keyDownCVar end
  local clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
  if not clickAction then return false end
  local spell = modified(self, "spell")
  if modified(self, "type") == "spell" and spell ~= nil then
    local cast = { spell = tonumber(spell) or spell }
    S.casts[#S.casts + 1] = cast
    if S.ITEM_SPELLS[cast.spell] then S.awaiting = cast end
  end
  if S.awaiting then
    local slot = modified(self, "target-slot")
    if slot ~= nil then
      local bag = modified(self, "target-bag")
      S.targets[#S.targets + 1] = { bag = bag, slot = slot }
      if type(S.awaiting) == "table" then S.awaiting.bag, S.awaiting.slot = bag, slot end
      S.awaiting = nil
    end
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

-- SecureCmdOptionParse for the conditions modelled: the action of the first clause whose condition
-- holds, trimmed, "" for a clause with no action ("[combat] ; nil" in combat), nil when none holds.
local function resolve(values)
  for clause in (values .. ";"):gmatch("([^;]*);") do
    local condition, action = clause:match("^%s*%[(.-)%]%s*(.-)%s*$")
    if condition then
      if (condition == "combat" and S.combat) or (condition == "nocombat" and not S.combat) then return action end
    else
      return (clause:match("^%s*(.-)%s*$"))
    end
  end
  return nil
end

-- resolveDriver (live SecureStateDriver.lua:97-118).
local function resolveDriver(frame, attribute, values)
  local value = resolve(values)
  if attribute == "state-visibility" then
    if value == "show" then frame:Show() elseif value == "hide" then frame:Hide() end
  elseif value then
    if value == "nil" then value = nil else value = tonumber(value) or value end
    if value ~= frame:GetAttribute(attribute) then frame:SetAttribute(attribute, value) end
  end
end

function S.tick()
  secureDepth = secureDepth + 1
  for frame, drivers in pairs(DRIVERS) do
    for attribute, values in pairs(drivers) do resolveDriver(frame, attribute, values) end
  end
  secureDepth = secureDepth - 1
end

-- RegisterAttributeDriver hands the frame to the secure manager through the manager's attributes,
-- which addon code cannot set in combat; an attribute starting with "_" is refused, and empty
-- values drop the driver (live SecureStateDriver.lua:8-13, :160-167).
local function registerAttributeDriver(frame, attribute, values)
  if S.combat then error("ADDON_ACTION_BLOCKED: RegisterAttributeDriver in combat", 2) end
  if not (attribute and values and attribute:sub(1, 1) ~= "_") then return end
  DRIVERS[frame] = DRIVERS[frame] or {}
  if values == "" then
    DRIVERS[frame][attribute] = nil
    return
  end
  DRIVERS[frame][attribute] = values
  secureDepth = secureDepth + 1
  resolveDriver(frame, attribute, values)
  secureDepth = secureDepth - 1
end

local function registerStateDriver(frame, state, values)
  registerAttributeDriver(frame, "state-" .. state, values)
end

-- The values a frame's driver for `name` resolves: a state's ("visibility") or an attribute's.
function S.driver(frame, name)
  local drivers = DRIVERS[frame]
  return drivers and (drivers["state-" .. name] or drivers[name])
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
    RegisterStateDriver = _G.RegisterStateDriver, RegisterAttributeDriver = _G.RegisterAttributeDriver }
  S.combat, S.casts, S.targets, S.awaiting, S.keyDownCVar = false, {}, {}, nil, true
  _G.CreateFrame = create
  _G.InCombatLockdown = function() return S.combat end
  _G.RegisterStateDriver = registerStateDriver
  _G.RegisterAttributeDriver = registerAttributeDriver
  return function()
    for k, v in pairs(saved) do _G[k] = v end
    for _, name in ipairs(named) do _G[name] = nil end
    named = {}
  end
end

return S
