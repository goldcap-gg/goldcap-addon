-- GoldCap's design tokens: the colours, radii and spacing every window draws with. The values are
-- a dark-glass look in GoldCap's gold (wow-auction: docs/superpowers/specs/
-- 2026-10-09-addon-ui-kit-and-sell-design.md, "Tokens"). UI/Theme.lua maps its long-standing colour
-- names onto these, so a window reading Theme.color.* draws in them without being edited. Kit files
-- read these tokens, never Theme.color: they load before UI/Theme.lua.
local _, GC = ...
GC.Kit = GC.Kit or {}
GC.Kit.MEDIA = "Interface\\AddOns\\GoldCap\\Media\\"

local function hex(s, a)
  return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, a or 1 }
end

local Tokens = { hex = hex }
GC.Kit.Tokens = Tokens

local c = {
  -- Five steps of text: titles, body, secondary, labels, faint.
  text1 = hex("F3F1EC"), text2 = hex("C3C8D0"), text3 = hex("8B93A0"), text4 = hex("6F7885"), text5 = hex("4F5763"),
  -- The window: a vertical gradient between these two, a faint white edge. 93% opaque, so the
  -- world shows through a little (the owner's call, 2026-10-09). Over the auction house its own
  -- rows show faintly too: at 95% they already did (seen in game), and nothing can blur them.
  windowTop = hex("151921", 0.93), windowBottom = hex("0C0E13", 0.93), windowBorder = { 1, 1, 1, 0.14 },
  -- Glass: rows, cards and panels inside the window, white at a few percent over the dark.
  glassTop = { 1, 1, 1, 0.035 }, glassBottom = { 1, 1, 1, 0.02 }, glassBorder = { 1, 1, 1, 0.075 },
  -- A panel over the window (the inspector, menus, dialogs): denser, with a shadow.
  popup = { 0.086, 0.102, 0.133, 0.98 }, popupBorder = { 1, 1, 1, 0.09 },
  raised = hex("1B2029"),
  hairline = { 1, 1, 1, 0.06 },
  gold = hex("E8B04B"), goldText = hex("F7CF5A"),
  profit = hex("6EE7A0"), loss = hex("FF8A8A"), lossFill = hex("E25A5E"),
  warn = hex("F5C469"), yours = hex("7CC0FF"),
  -- What a unit cost: a muted gold, so a price paid never competes with a price asked.
  cost = { 0.788, 0.663, 0.341, 1 },
  -- Lettering on a gold fill.
  onGold = hex("160F04"),
}
Tokens.color = c

-- What text on a Blizzard surface (a tooltip, a menu, chat) reads: today's palette, copied before
-- any skin can touch Tokens.color, so a skin never changes a colour the game draws on its own ground.
Tokens.blizzard = {}
for key, value in pairs(c) do
  Tokens.blizzard[key] = { value[1], value[2], value[3], value[4] }
end

-- Colours derived from a token. Each is registered, so Tokens.refresh() rewrites it in place and
-- every file that kept a reference sees the applied skin.
local derived = {}

--- {r, g, b, a} of Tokens.color[key]: alpha `a`, or (nil) the token's own, which then follows it.
function Tokens.alpha(key, a)
  local from = c[key]
  local out = { from[1], from[2], from[3], a or from[4] }
  derived[#derived + 1] = { out = out, key = key, a = a }
  return out
end

--- {r, g, b} of Tokens.color[key].
function Tokens.rgb(key)
  local from = c[key]
  local out = { from[1], from[2], from[3] }
  derived[#derived + 1] = { out = out, key = key }
  return out
end

--- Rewrites every derived colour from the current Tokens.color.
function Tokens.refresh()
  for _, d in ipairs(derived) do
    local from = c[d.key]
    local out = d.out
    out[1], out[2], out[3] = from[1], from[2], from[3]
    if out[4] then out[4] = d.a or from[4] end
  end
end

-- The engine's HIGHLIGHT wash: additive gold, the same "the cursor is here" everywhere.
c.hoverWash = Tokens.alpha("gold", 0.18)

Tokens.radius = { s = 6, m = 8, l = 10, xl = 12 }
Tokens.space = { xs = 4, s = 8, m = 12, l = 16 }
