-- The skins: each a table of colours, shape and frame, applied in place over UI/Kit/Tokens.lua so
-- every colour a window already holds follows the choice. `goldcap` is Tokens.lua's own palette,
-- value for value, and the default: a player who never opens the setting sees no change. The values
-- come from the owner-approved mockup (wow-auction: docs/design/2026-11-09-addon-skins-mock.css);
-- the design is docs/superpowers/specs/2026-11-09-addon-skins-design.md. Loads right after
-- UI/Kit/Tokens.lua and reads no Theme.* (Theme.lua loads later).
local _, GC = ...
GC.Kit = GC.Kit or {}
local Tokens = GC.Kit.Tokens
local hex = Tokens.hex
local blizzard = Tokens.blizzard

local Skins = {}
GC.Kit.Skins = Skins

--- CSS rgba(r, g, b, a) as a colour.
local function rgba(r, g, b, a)
  return { r / 255, g / 255, b / 255, a }
end

Skins.ORDER = { "goldcap", "forever", "pixel", "parchment", "horde", "alliance", "midnight", "classic", "leather" }

local defs = {}
Skins.defs = defs

-- Goldcap (today's dark glass in gold).
defs.goldcap = {
  color = {
    text1 = hex("F3F1EC"), text2 = hex("C3C8D0"), text3 = hex("8B93A0"), text4 = hex("6F7885"),
    text5 = hex("4F5763"),
    windowTop = hex("151921", 0.93), windowBottom = hex("0C0E13", 0.93),
    windowBorder = { 1, 1, 1, 0.14 },
    glassTop = { 1, 1, 1, 0.035 }, glassBottom = { 1, 1, 1, 0.02 }, glassBorder = { 1, 1, 1, 0.075 },
    popup = { 0.086, 0.102, 0.133, 0.98 }, popupBorder = { 1, 1, 1, 0.09 },
    raised = hex("1B2029"),
    hairline = { 1, 1, 1, 0.06 },
    gold = hex("E8B04B"), goldText = hex("F7CF5A"),
    profit = hex("6EE7A0"), loss = hex("FF8A8A"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("7CC0FF"),
    cost = { 0.788, 0.663, 0.341, 1 },
    onGold = hex("160F04"),
    -- Tokens.lua holds goldcap's values for these; Tokens.blizzard is its untouched copy.
    railIdle = blizzard.railIdle, railActive = blizzard.railActive,
    primaryTop = blizzard.primaryTop, primaryBottom = blizzard.primaryBottom, primaryText = blizzard.primaryText,
    frameTint = blizzard.frameTint,
  },
  quality = nil,
  radius = { 12, 10, 8, 12 },
  frame = "hairline",
  frameWidth = 0,
  ornament = nil,
  plates = false,
  glow = true,
  fonts = {},
}

-- Forever (bronze bevel on warm dark brown).
defs.forever = {
  color = {
    text1 = hex("F4EAD6"), text2 = hex("D8CBB3"), text3 = hex("AE9D82"), text4 = hex("978670"),
    text5 = hex("978670", 0.7),
    windowTop = hex("1F1913", 0.92), windowBottom = hex("110D0A", 0.94),
    windowBorder = rgba(196, 150, 92, 0.5),
    glassTop = rgba(255, 230, 190, 0.045), glassBottom = rgba(255, 230, 190, 0.02), glassBorder = rgba(196, 150, 92, 0.22),
    popup = rgba(27, 21, 16, 0.985), popupBorder = rgba(255, 255, 255, 0.1),
    raised = hex("251F19"),
    hairline = rgba(196, 150, 92, 0.18),
    gold = hex("D9A85A"), goldText = hex("FFD27A"),
    profit = hex("8AE38E"), loss = hex("FF927D"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("7CC0FF"),
    cost = hex("E3C27C"),
    onGold = hex("1B1107"),
    railIdle = hex("A8977C"), railActive = hex("FFD27A"),
    primaryTop = hex("E8BC72"), primaryBottom = hex("9E6E36"), primaryText = hex("1B1107"),
    frameTint = hex("AD7F49"),
  },
  quality = nil,
  radius = { 8, 4, 6, 5 },
  frame = "bevel",
  frameWidth = 2,
  ornament = nil,
  plates = true,
  glow = true,
  fonts = {},
}

-- Pixel (flat #111, square, black lines).
defs.pixel = {
  color = {
    text1 = hex("FFFFFF"), text2 = hex("D8D8D8"), text3 = hex("A3A3A3"), text4 = hex("8A8A8A"),
    text5 = hex("8A8A8A", 0.7),
    windowTop = hex("111111", 0.93), windowBottom = hex("111111", 0.93),
    windowBorder = hex("000000"),
    glassTop = hex("1A1A1A"), glassBottom = hex("181818"), glassBorder = hex("000000"),
    popup = rgba(20, 20, 20, 0.985), popupBorder = hex("000000"),
    raised = hex("171717"),
    hairline = hex("000000"),
    gold = hex("E8B04B"), goldText = hex("F2C14E"),
    profit = hex("6EE7A0"), loss = hex("FF8A8A"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("7CC0FF"),
    cost = hex("D9B866"),
    onGold = hex("000000"),
    railIdle = hex("8A8A8A"), railActive = hex("F2C14E"),
    primaryTop = hex("E8B04B"), primaryBottom = hex("E8B04B"), primaryText = hex("000000"),
    frameTint = hex("000000"),
  },
  quality = nil,
  radius = { 0, 0, 0, 0 },
  frame = "pixel",
  frameWidth = 2,
  ornament = nil,
  plates = false,
  glow = false,
  fonts = {},
}

-- Parchment (aged parchment with dark wood frame).
defs.parchment = {
  color = {
    text1 = hex("2A1A0A"), text2 = hex("46301B"), text3 = hex("5F4529"), text4 = hex("6A4F30"),
    text5 = hex("6A4F30", 0.7),
    windowTop = hex("F4E8C8"), windowBottom = hex("CFB27C"),
    windowBorder = hex("8A6A3A"),
    glassTop = rgba(255, 250, 232, 0.42), glassBottom = rgba(255, 250, 232, 0.24), glassBorder = rgba(90, 60, 25, 0.26),
    popup = hex("E6D3A9"), popupBorder = { 0, 0, 0, 0 },
    raised = hex("FAEECE"),
    hairline = rgba(80, 50, 20, 0.22),
    gold = hex("9B2C1A"), goldText = hex("8A230F"),
    profit = hex("1D6A2A"), loss = hex("A3261B"), lossFill = hex("E25A5E"),
    warn = hex("8A230F"), yours = hex("00469A"),
    cost = hex("6F4C0E"),
    onGold = hex("FFD100"),
    railIdle = hex("D2BD93"), railActive = hex("FFD100"),
    primaryTop = hex("C92D1C"), primaryBottom = hex("7E140A"), primaryText = hex("FFD100"),
    frameTint = hex("3B2511"),
  },
  quality = { [2] = "106A00", [3] = "00469A" },
  radius = { 5, 3, 4, 4 },
  frame = "bevel",
  frameWidth = 4,
  ornament = nil,
  plates = false,
  glow = false,
  fonts = {},
}

-- Horde (war-red iron with rivets).
defs.horde = {
  color = {
    text1 = hex("F6E9E1"), text2 = hex("DAC7BE"), text3 = hex("AF988E"), text4 = hex("9A8277"),
    text5 = hex("9A8277", 0.7),
    windowTop = hex("1F100D", 0.93), windowBottom = hex("0F0807", 0.95),
    windowBorder = hex("5D4C45"),
    glassTop = rgba(255, 200, 180, 0.04), glassBottom = rgba(255, 200, 180, 0.02), glassBorder = rgba(170, 90, 70, 0.24),
    popup = rgba(29, 16, 14, 0.985), popupBorder = rgba(255, 255, 255, 0.1),
    raised = hex("251613"),
    hairline = rgba(200, 80, 60, 0.18),
    gold = hex("CB3A2C"), goldText = hex("FFC46B"),
    profit = hex("86DD8E"), loss = hex("FF8C7C"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("7CC0FF"),
    cost = hex("E4BF7A"),
    onGold = hex("FFD58A"),
    railIdle = hex("AE948A"), railActive = hex("FFC46B"),
    primaryTop = hex("CF3B2D"), primaryBottom = hex("7A1710"), primaryText = hex("FFD58A"),
    frameTint = hex("3B3431"),
  },
  quality = nil,
  radius = { 5, 3, 3, 3 },
  frame = "bevel",
  frameWidth = 3,
  ornament = "rivets",
  plates = true,
  glow = true,
  fonts = {},
}

-- Alliance (royal blue and gold, corner brackets).
defs.alliance = {
  color = {
    text1 = hex("EEF3FC"), text2 = hex("C9D3E6"), text3 = hex("9AA7BF"), text4 = hex("8592AB"),
    text5 = hex("8592AB", 0.7),
    windowTop = hex("0E1626", 0.93), windowBottom = hex("080C16", 0.95),
    windowBorder = rgba(201, 162, 79, 0.55),
    glassTop = rgba(190, 215, 255, 0.045), glassBottom = rgba(190, 215, 255, 0.02), glassBorder = rgba(120, 160, 230, 0.22),
    popup = rgba(13, 20, 35, 0.985), popupBorder = rgba(255, 255, 255, 0.1),
    raised = hex("141C2C"),
    hairline = rgba(120, 160, 230, 0.16),
    gold = hex("4183E6"), goldText = hex("FFD978"),
    profit = hex("80E4A9"), loss = hex("FF9090"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("9CC8FF"),
    cost = hex("E4C67E"),
    onGold = hex("FFE79A"),
    railIdle = hex("94A2BC"), railActive = hex("FFD978"),
    primaryTop = hex("4E91EE"), primaryBottom = hex("1F4E9E"), primaryText = hex("FFE79A"),
    frameTint = hex("BA933F"),
  },
  quality = nil,
  radius = { 8, 5, 5, 10 },
  frame = "bevel",
  frameWidth = 2,
  ornament = "brackets",
  plates = true,
  glow = true,
  fonts = {},
}

-- Midnight (violet glass with shimmer lines).
defs.midnight = {
  color = {
    text1 = hex("F4F0FF"), text2 = hex("D2CAEC"), text3 = hex("A79DC7"), text4 = hex("958BB6"),
    text5 = hex("958BB6", 0.7),
    windowTop = hex("170F2A", 0.93), windowBottom = hex("090612", 0.95),
    windowBorder = rgba(150, 115, 255, 0.5),
    glassTop = rgba(200, 180, 255, 0.045), glassBottom = rgba(200, 180, 255, 0.02), glassBorder = rgba(150, 115, 255, 0.24),
    popup = rgba(20, 12, 36, 0.985), popupBorder = rgba(255, 255, 255, 0.1),
    raised = hex("1D1530"),
    hairline = rgba(160, 120, 255, 0.17),
    gold = hex("9C6BFF"), goldText = hex("FFD98A"),
    profit = hex("7FE6B0"), loss = hex("FF8FA3"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("8FC4FF"),
    cost = hex("E4C482"),
    onGold = hex("FFF1C9"),
    railIdle = hex("A097C4"), railActive = hex("FFD98A"),
    primaryTop = hex("A97FFF"), primaryBottom = hex("5B32C9"), primaryText = hex("FFF1C9"),
    frameTint = hex("7356D0"),
  },
  quality = nil,
  radius = { 10, 6, 6, 10 },
  frame = "bevel",
  frameWidth = 1.5,
  ornament = "shimmer",
  plates = false,
  glow = true,
  fonts = {},
}

-- Classic (the game's own marble, gold border and panel buttons).
defs.classic = {
  color = {
    text1 = hex("FFFFFF"), text2 = hex("E6E6E6"), text3 = hex("BDBDBD"), text4 = hex("A6A6A6"),
    text5 = hex("A6A6A6", 0.7),
    windowTop = hex("0B0B0B"), windowBottom = hex("0B0B0B"),
    windowBorder = hex("8A8A8A"),
    glassTop = { 0, 0, 0, 0 }, glassBottom = { 0, 0, 0, 0 }, glassBorder = { 0, 0, 0, 0 },
    popup = hex("10101F"), popupBorder = { 0, 0, 0, 0 },
    raised = hex("111111"),
    hairline = rgba(255, 209, 0, 0.2),
    gold = hex("FFD100"), goldText = hex("FFD100"),
    profit = hex("1EFF00"), loss = hex("FF4A4A"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("71D5FF"),
    cost = hex("FFD100"),
    onGold = hex("160F04"),
    railIdle = hex("FFD100"), railActive = hex("FFFFFF"),
    primaryTop = hex("F2BE57"), primaryBottom = hex("C9922F"), primaryText = hex("160F04"),
    frameTint = hex("8A8A8A"),
  },
  quality = { [3] = "2E8BFF" },
  radius = { 4, 6, 3, 3 },
  frame = "classic",
  frameWidth = 0,
  ornament = nil,
  plates = true,
  glow = false,
  fonts = {},
}

-- Leather (tooled leather with gold stitching).
defs.leather = {
  color = {
    text1 = hex("F4E8CF"), text2 = hex("DFCDAC"), text3 = hex("B9A27D"), text4 = hex("A58F6B"),
    text5 = hex("A58F6B", 0.7),
    windowTop = hex("2F2016"), windowBottom = hex("1C130C"),
    windowBorder = rgba(201, 162, 79, 0.55),
    glassTop = rgba(255, 225, 170, 0.055), glassBottom = rgba(255, 225, 170, 0.02), glassBorder = rgba(190, 150, 80, 0.3),
    popup = hex("2A1C13"), popupBorder = rgba(255, 255, 255, 0.1),
    raised = hex("35261C"),
    hairline = rgba(214, 170, 90, 0.22),
    gold = hex("C9A24F"), goldText = hex("F3D27E"),
    profit = hex("A0DC8E"), loss = hex("F2907A"), lossFill = hex("E25A5E"),
    warn = hex("F5C469"), yours = hex("7CC0FF"),
    cost = hex("E3C27C"),
    onGold = hex("2A1A08"),
    railIdle = hex("BDA77F"), railActive = hex("F3D27E"),
    primaryTop = hex("E8C877"), primaryBottom = hex("9A7431"), primaryText = hex("2A1A08"),
    frameTint = hex("AB8742"),
  },
  quality = nil,
  radius = { 6, 4, 4, 4 },
  frame = "bevel",
  frameWidth = 3,
  ornament = "stitch",
  plates = true,
  glow = true,
  fonts = {},
}

local current = "goldcap"

--- Writes the skin's colours into the existing Tokens.color tables (so every alias stays valid) and
--- re-derives what follows them. An unknown or missing id means goldcap. Returns the id applied.
function Skins.Apply(id)
  if type(id) ~= "string" or not defs[id] then id = "goldcap" end
  local color = Tokens.color
  for key, value in pairs(defs[id].color) do
    local into = color[key]
    if into then
      for i = 1, 4 do into[i] = value[i] end
    else
      color[key] = { value[1], value[2], value[3], value[4] }
    end
  end
  current = id
  Tokens.refresh()
  return id
end

--- The def of the skin last applied (goldcap until Apply runs).
function Skins.Current()
  return defs[current]
end
