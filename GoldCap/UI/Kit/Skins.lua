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
    railTop = blizzard.railTop, railBottom = blizzard.railBottom,
    plateTop = blizzard.plateTop, plateBottom = blizzard.plateBottom, plateOnTop = blizzard.plateOnTop,
    plateOnBottom = blizzard.plateOnBottom,
    frameInner = blizzard.frameInner,
    ink = blizzard.ink, danger = blizzard.danger, safe = blizzard.safe,
    fail = blizzard.fail, soldGold = blizzard.soldGold, soldGreen = blizzard.soldGreen,
    soldDim = blizzard.soldDim, dealMuted = blizzard.dealMuted, rowDim = blizzard.rowDim,
    soldSilver = blizzard.soldSilver, soldCopper = blizzard.soldCopper,
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = blizzard.vendor, onLoss = blizzard.onLoss,
    soldTile = blizzard.soldTile, soldRoad = blizzard.soldRoad, soldBanner = blizzard.soldBanner,
    soldEmpty = blizzard.soldEmpty, soldFaint = blizzard.soldFaint,
  },
  quality = nil,
  radius = { 12, 12, 8, 6 },
  -- Today's rail buttons are cut from the panel art (radius 12), not the 8 of the controls.
  railRadius = 12,
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
    railTop = { 0, 0, 0, .28 }, railBottom = { 0, 0, 0, .28 },
    plateTop = hex("2A2119"), plateBottom = hex("17120D"), plateOnTop = hex("4D3A22"), plateOnBottom = hex("2B2015"),
    frameInner = blizzard.frameInner,
    ink = hex("FFFFFF"), danger = hex("FF927D"), safe = hex("8AE38E"),
    fail = hex("FF927D"), soldGold = hex("FFD27A"), soldGreen = hex("8AE38E"),
    soldDim = hex("AE9D82"), dealMuted = hex("AE9D82"), rowDim = hex("AE9D82"),
    soldSilver = hex("D8CBB3"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("FFD27A"), onLoss = blizzard.onLoss,
    soldTile = hex("251F19"), soldRoad = hex("251F19"), soldBanner = hex("251F19"), soldEmpty = hex("251F19"),
    soldFaint = hex("978670"),
  },
  quality = nil,
  radius = { 8, 4, 6, 5 },
  frame = "bevel",
  frameWidth = 2,
  ornament = nil,
  plates = true,
  -- Its plate ring is baked (gen_art.py PLATE_SKINS).
  plateArt = true,
  glow = true,
  fonts = { head = "RobotoCondensed-Bold.ttf" },
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
    railTop = hex("0C0C0C"), railBottom = hex("0C0C0C"),
    plateTop = blizzard.plateTop, plateBottom = blizzard.plateBottom, plateOnTop = blizzard.plateOnTop,
    plateOnBottom = blizzard.plateOnBottom,
    frameInner = hex("2E2E2E"),
    ink = hex("FFFFFF"), danger = hex("FF8A8A"), safe = hex("6EE7A0"),
    fail = hex("FF8A8A"), soldGold = hex("F2C14E"), soldGreen = hex("6EE7A0"),
    soldDim = hex("A3A3A3"), dealMuted = hex("A3A3A3"), rowDim = hex("A3A3A3"),
    soldSilver = hex("D8D8D8"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("F2C14E"), onLoss = blizzard.onLoss,
    soldTile = hex("171717"), soldRoad = hex("171717"), soldBanner = hex("171717"), soldEmpty = hex("171717"),
    soldFaint = hex("8A8A8A"),
  },
  quality = nil,
  radius = { 0, 0, 0, 0 },
  frame = "pixel",
  frameWidth = 2,
  ornament = nil,
  plates = false,
  glow = false,
  -- The selected rail button wears a bar on its left edge in place of a glow.
  railBar = true,
  fonts = { head = "PTSansNarrow-Bold.ttf",
    text = { regular = "PTSansNarrow-Regular.ttf", semi = "PTSansNarrow-Bold.ttf", bold = "PTSansNarrow-Bold.ttf" } },
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
    railIdle = hex("D2BD93"), railActive = hex("7A1E0F"),
    primaryTop = hex("C92D1C"), primaryBottom = hex("7E140A"), primaryText = hex("FFD100"),
    frameTint = hex("3B2511"),
    railTop = hex("342414"), railBottom = hex("21160B"),
    plateTop = blizzard.plateTop, plateBottom = blizzard.plateBottom, plateOnTop = blizzard.plateOnTop,
    plateOnBottom = blizzard.plateOnBottom,
    frameInner = blizzard.frameInner,
    ink = hex("2A1A0A"), danger = hex("A3261B"), safe = hex("1D6A2A"),
    fail = hex("A3261B"), soldGold = hex("8A230F"), soldGreen = hex("1D6A2A"),
    soldDim = hex("5F4529"), dealMuted = hex("5F4529"), rowDim = hex("5F4529"),
    soldSilver = hex("46301B"), soldCopper = hex("8A230F"),
    tierHot = hex("B02A08"), tierGood = hex("1B6B1B"), tierWatch = hex("6B5B45"),
    tierSuspect = hex("7A5200"), vendor = hex("8A230F"), onLoss = blizzard.onLoss,
    soldTile = hex("FAEECE"), soldRoad = hex("FAEECE"), soldBanner = hex("FAEECE"), soldEmpty = hex("FAEECE"),
    soldFaint = hex("6A4F30"),
  },
  -- Every quality that can stand on paper (poor to WoW token), darkened to read on it (1, common, is the body text).
  quality = { [0] = "474747", [1] = "2A1A0A", [2] = "0C5300", [3] = "004394", [4] = "5A1F9A", [5] = "7A2D00",
    [6] = "5E4000", [7] = "004B59", [8] = "004B59" },
  -- The window is the client's quest paper (Card.lua), not a gradient.
  paper = true,
  -- The selected rail button: a slip of the paper on the wood, a tan line in it and a dark one round
  -- it (the board's .rb.on); its label in red ink (railActive).
  railCard = { top = hex("F2E4C0"), bottom = hex("D8C190"), ring = hex("B8914C"), edge = hex("120A03") },
  radius = { 5, 3, 4, 4 },
  frame = "bevel",
  frameWidth = 4,
  ornament = nil,
  plates = false,
  glow = false,
  fonts = { head = "AlegreyaSC-Bold.ttf",
    text = { regular = "Alegreya-Medium.ttf", semi = "Alegreya-Bold.ttf", bold = "Alegreya-Bold.ttf" },
    display = true },
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
    railTop = { 0, 0, 0, .32 }, railBottom = { 0, 0, 0, .32 },
    plateTop = hex("2B1E1B"), plateBottom = hex("170F0D"), plateOnTop = hex("7A1F16"), plateOnBottom = hex("3E0E09"),
    frameInner = blizzard.frameInner,
    ink = hex("FFFFFF"), danger = hex("FF8C7C"), safe = hex("86DD8E"),
    fail = hex("FF8C7C"), soldGold = hex("FFC46B"), soldGreen = hex("86DD8E"),
    soldDim = hex("AF988E"), dealMuted = hex("AF988E"), rowDim = hex("AF988E"),
    soldSilver = hex("DAC7BE"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("FFC46B"), onLoss = blizzard.onLoss,
    soldTile = hex("251613"), soldRoad = hex("251613"), soldBanner = hex("251613"), soldEmpty = hex("251613"),
    soldFaint = hex("9A8277"),
  },
  quality = nil,
  radius = { 5, 3, 3, 3 },
  frame = "bevel",
  frameWidth = 3,
  ornament = "rivets",
  plates = true,
  -- Its plate ring is baked (gen_art.py PLATE_SKINS).
  plateArt = true,
  glow = true,
  fonts = { head = "RuslanDisplay-Regular.ttf", display = true },
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
    railTop = { 0, 0, 0, .26 }, railBottom = { 0, 0, 0, .26 },
    plateTop = hex("17223A"), plateBottom = hex("0C1322"), plateOnTop = hex("2F62B3"), plateOnBottom = hex("173A78"),
    frameInner = blizzard.frameInner,
    ink = hex("FFFFFF"), danger = hex("FF9090"), safe = hex("80E4A9"),
    fail = hex("FF9090"), soldGold = hex("FFD978"), soldGreen = hex("80E4A9"),
    soldDim = hex("9AA7BF"), dealMuted = hex("9AA7BF"), rowDim = hex("9AA7BF"),
    soldSilver = hex("C9D3E6"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("FFD978"), onLoss = blizzard.onLoss,
    soldTile = hex("141C2C"), soldRoad = hex("141C2C"), soldBanner = hex("141C2C"), soldEmpty = hex("141C2C"),
    soldFaint = hex("8592AB"),
  },
  quality = nil,
  radius = { 8, 5, 5, 10 },
  frame = "bevel",
  frameWidth = 2,
  ornament = "brackets",
  plates = true,
  -- Its plate ring is baked (gen_art.py PLATE_SKINS).
  plateArt = true,
  glow = true,
  fonts = { head = "PlayfairDisplaySC-Bold.ttf", display = true },
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
    railTop = { 0, 0, 0, .30 }, railBottom = { 0, 0, 0, .30 },
    plateTop = blizzard.plateTop, plateBottom = blizzard.plateBottom, plateOnTop = blizzard.plateOnTop,
    plateOnBottom = blizzard.plateOnBottom,
    frameInner = blizzard.frameInner,
    ink = hex("FFFFFF"), danger = hex("FF8FA3"), safe = hex("7FE6B0"),
    fail = hex("FF8FA3"), soldGold = hex("FFD98A"), soldGreen = hex("7FE6B0"),
    soldDim = hex("A79DC7"), dealMuted = hex("A79DC7"), rowDim = hex("A79DC7"),
    soldSilver = hex("D2CAEC"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("FFD98A"), onLoss = blizzard.onLoss,
    soldTile = hex("1D1530"), soldRoad = hex("1D1530"), soldBanner = hex("1D1530"), soldEmpty = hex("1D1530"),
    soldFaint = hex("958BB6"),
  },
  quality = nil,
  radius = { 10, 6, 6, 10 },
  frame = "bevel",
  frameWidth = 1.5,
  ornament = "shimmer",
  plates = false,
  glow = true,
  fonts = { head = "Philosopher-Bold.ttf", display = true },
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
    frameTint = hex("6A6A6A"),
    railTop = { 0, 0, 0, .35 }, railBottom = { 0, 0, 0, .35 },
    -- Classic's tabs: a dark gradient (selected lighter) in a 1px edge, its bottom darker.
    plateTop = hex("2F2F2F"), plateBottom = hex("0D0D0D"), plateOnTop = hex("4D4D4D"),
    plateOnBottom = hex("1A1A1A"),
    frameInner = hex("222222"),
    ink = hex("FFFFFF"), danger = hex("FF4A4A"), safe = hex("1EFF00"),
    fail = hex("FF4A4A"), soldGold = hex("FFD100"), soldGreen = hex("1EFF00"),
    soldDim = hex("BDBDBD"), dealMuted = hex("BDBDBD"), rowDim = hex("BDBDBD"),
    soldSilver = hex("E6E6E6"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("FFD100"), onLoss = blizzard.onLoss,
    soldTile = hex("111111"), soldRoad = hex("111111"), soldBanner = hex("111111"), soldEmpty = hex("111111"),
    soldFaint = hex("A6A6A6"),
  },
  quality = { [3] = "2E8BFF" },
  radius = { 4, 6, 3, 3 },
  frame = "classic",
  frameWidth = 0,
  ornament = nil,
  plates = true,
  glow = false,
  fonts = { client = true },
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
    railTop = { 0, 0, 0, .28 }, railBottom = { 0, 0, 0, .28 },
    plateTop = hex("3B2918"), plateBottom = hex("22170E"), plateOnTop = hex("5C4024"), plateOnBottom = hex("37260F"),
    frameInner = blizzard.frameInner,
    ink = hex("FFFFFF"), danger = hex("F2907A"), safe = hex("A0DC8E"),
    fail = hex("F2907A"), soldGold = hex("F3D27E"), soldGreen = hex("A0DC8E"),
    soldDim = hex("B9A27D"), dealMuted = hex("B9A27D"), rowDim = hex("B9A27D"),
    soldSilver = hex("DFCDAC"), soldCopper = hex("F5C469"),
    tierHot = blizzard.tierHot, tierGood = blizzard.tierGood, tierWatch = blizzard.tierWatch,
    tierSuspect = blizzard.tierSuspect, vendor = hex("F3D27E"), onLoss = blizzard.onLoss,
    soldTile = hex("35261C"), soldRoad = hex("35261C"), soldBanner = hex("35261C"), soldEmpty = hex("35261C"),
    soldFaint = hex("A58F6B"),
  },
  quality = nil,
  radius = { 6, 4, 4, 4 },
  frame = "bevel",
  frameWidth = 3,
  ornament = "stitch",
  plates = true,
  -- Its plate ring is baked (gen_art.py PLATE_SKINS).
  plateArt = true,
  glow = true,
  fonts = { head = "OldStandard-Bold.ttf", display = true },
}

for id, def in pairs(defs) do def.id = id end

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
  -- Faces: Skins.lua loads before Fonts.lua and FontPreload.lua, so each is asked for only if it
  -- is there. {} (goldcap) puts Fira back; the preloader gets the skin's files so the first window
  -- is drawn in them.
  local fonts = defs[id].fonts
  local Theme = GC.Theme
  if Theme and Theme.ApplySkinFonts then Theme.ApplySkinFonts(fonts) end
  if Theme and Theme.PreloadFaces then
    local MEDIA = GC.Kit.MEDIA
    local paths = {}
    if fonts.head then paths[#paths + 1] = MEDIA .. fonts.head end
    for _, file in pairs(fonts.text or {}) do paths[#paths + 1] = MEDIA .. file end
    Theme.PreloadFaces(paths)
  end
  return id
end

--- The def of the skin last applied (goldcap until Apply runs).
function Skins.Current()
  return defs[current]
end
