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
  -- The window: a vertical gradient between these two, a faint white edge.
  windowTop = hex("151921", 0.955), windowBottom = hex("0C0E13", 0.97), windowBorder = { 1, 1, 1, 0.14 },
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
-- The engine's HIGHLIGHT wash: additive gold, the same "the cursor is here" everywhere.
c.hoverWash = { c.gold[1], c.gold[2], c.gold[3], 0.18 }
Tokens.color = c

Tokens.radius = { s = 6, m = 8, l = 10, xl = 12 }
Tokens.space = { xs = 4, s = 8, m = 12, l = 16 }
