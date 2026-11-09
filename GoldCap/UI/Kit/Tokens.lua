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
  -- The rail's label colours, the primary button's two fills and label, and the frame's tint.
  -- Nothing reads them in the plain look; skins (UI/Kit/Skins.lua) rewrite them in place.
  railIdle = hex("6F7885"), railActive = hex("F7CF5A"),
  primaryTop = hex("F2BE57"), primaryBottom = hex("C9922F"), primaryText = hex("160F04"),
  frameTint = { 1, 1, 1, 0.14 },
  -- The colour of a faint fill or stroke laid over the window (an empty slot, a meter's track, a
  -- scrollbar thumb, a standing mark): white on a dark skin, dark ink on a light one. The alpha
  -- is the caller's.
  ink = { 1, 1, 1, 1 },
  -- A verdict's two colours in a dialog: a refusal, and a safe buy.
  danger = { 1, 0.3, 0.3, 1 }, safe = { 0.25, 0.85, 0.25, 1 },
  -- Inline-escape colours of single words in running text: a failed import, and the Sold
  -- window's gold, green and dim figures, the Deals rows' muted counts, the Sell rows' dim note.
  fail = hex("FF4040"),
  -- The Sniper tiers as text (hot, good, watch, suspect), and the Disenchant window's vendor figure.
  tierHot = { 1, 0.35, 0.15, 1 }, tierGood = { 0.25, 0.85, 0.25, 1 },
  tierWatch = { 0.65, 0.65, 0.65, 1 }, tierSuspect = { 1, 0.85, 0.1, 1 },
  vendor = hex("F2B544"),
  -- Lettering on the loss fill (the same red in every skin).
  onLoss = { 0.102, 0.024, 0.024, 1 },
  -- The Sold window's tile fills (a tile, the road, the banner, an empty slot) and its faint text.
  soldTile = { 0.071, 0.078, 0.098, 1 }, soldRoad = { 0.117, 0.112, 0.105, 1 },
  soldBanner = { 0.099, 0.138, 0.109, 1 }, soldEmpty = { 0.063, 0.071, 0.090, 1 },
  soldFaint = { 0.459, 0.451, 0.435, 1 },
  soldGold = hex("E8C15A"), soldSilver = hex("C9CED6"), soldCopper = hex("D08A5A"), soldGreen = hex("5FD38D"), soldDim = hex("9D9D9D"),
  dealMuted = hex("8C8A85"), rowDim = hex("8F8D88"),
}
Tokens.color = c

-- What text on a Blizzard surface (a tooltip, a menu, chat) reads: today's palette, copied before
-- any skin can touch Tokens.color, so a skin never changes a colour the game draws on its own ground.
Tokens.blizzard = {}
for key, value in pairs(c) do
  Tokens.blizzard[key] = { value[1], value[2], value[3], value[4] }
end

-- The game tooltip's own palette, for the lines GoldCap adds to it. It has no window twin: the
-- tooltip stays dark in every skin.
local b = Tokens.blizzard
b.tipTitle = { 1, 0.82, 0, 1 }
b.tipLabel = { 0.65, 0.82, 1, 1 }
b.tipWhite = { 1, 1, 1, 1 }
b.tipBody = { 0.85, 0.85, 0.85, 1 }
b.tipSoft = { 0.7, 0.7, 0.7, 1 }
b.tipNote = { 0.6, 0.6, 0.6, 1 }
b.tipHint = { 0.55, 0.55, 0.55, 1 }
b.tipGrey = { 0.65, 0.65, 0.65, 1 }
b.tipGood = { 0.3, 0.85, 0.4, 1 }
b.tipSafe = { 0.25, 0.85, 0.25, 1 }
b.tipWarn = { 1, 0.6, 0.2, 1 }
b.tipOrange = { 0.941, 0.627, 0.294, 1 }
b.tipAmber = { 0.83, 0.64, 0.22, 1 }

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

--- A fresh {r, g, b, a} in the skin's ink at alpha `a`, for a fill or stroke a window builds once
--- (a window is built after the skin is applied; for a colour held since load, use alpha()).
function Tokens.ink(a)
  local ink = c.ink
  return { ink[1], ink[2], ink[3], a }
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
