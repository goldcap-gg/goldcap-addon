-- Dev only (loaded inside the #@debug@ block of both TOCs, never in a release).
-- /gcprobe skins draws the client textures and font routes the skins rest on and stores what the
-- client answered under GoldCapDB.probe.skins, so the answers can be read from SavedVariables.
local _, GC = ...

local TEXTURES = {
  "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  "Interface\\DialogFrame\\UI-DialogBox-Gold-Header",
  "Interface\\Tooltips\\UI-Tooltip-Border",
  "Interface\\FrameGeneral\\UI-Background-Marble",
  "Interface\\AuctionFrame\\UI-AuctionItemNameFrame",
  "Interface\\Buttons\\UI-Quickslot2",
  "Interface\\Buttons\\CheckButtonHilight",
  "Interface\\Buttons\\UI-CheckBox-Up",
  "Interface\\Buttons\\UI-CheckBox-Check",
  "Interface\\Buttons\\UI-Panel-Button-Up",
  "atlas:QuestBG-Parchment",
}

local SEGMENTS = { "Classic", "Аа Ґґ Її", "한국어", "简体中文", "繁體中文" }
local SAMPLE = table.concat(SEGMENTS, " ")


local panel

-- Plain data only: SavedVariables must not hold a frame, a function or a table the client owns.
local function plain(v)
  local t = type(v)
  if v == nil then return "nil" end
  if t == "boolean" or t == "number" or t == "string" then return v end
  return tostring(v)
end

local function results()
  GoldCapDB = GoldCapDB or {}
  GoldCapDB.probe = GoldCapDB.probe or {}
  GoldCapDB.probe.skins = GoldCapDB.probe.skins or {}
  local r = GoldCapDB.probe.skins
  r.textures = r.textures or {}
  r.fonts = r.fonts or {}
  return r
end

local function makeFamily(name, height)
  local members = {}
  -- The members Classic's own families have (UI/Kit/Fonts.lua).
  for _, face in ipairs(GC.Theme.CLASSIC_FACES) do
    members[#members + 1] = { alphabet = face[1], file = face[2], height = height, flags = "" }
  end
  -- The brief names the members by alphabet; CreateFontFamily takes them as a list of tables.
  return CreateFontFamily(name, members)
end

local function textureCell(parent, path, x, y, r)
  local cell = CreateFrame("Frame", nil, parent)
  cell:SetSize(205, 100)
  cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local tex = cell:CreateTexture(nil, "ARTWORK")
  tex:SetSize(64, 64)
  tex:SetPoint("TOP", cell, "TOP", 0, 0)
  local atlas = path:match("^atlas:(.+)$")
  local ok, ret = pcall(function()
    if atlas then return tex:SetAtlas(atlas) end
    return tex:SetTexture(path)
  end)
  local okId, id = pcall(function() return tex:GetTextureFileID() end)
  r.textures[atlas or path] = {
    ok = ok, ret = plain(ret), fileID = okId and plain(id) or "error",
    atlas = atlas and true or false,
  }
  local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetWidth(200)
  label:SetPoint("TOP", tex, "BOTTOM", 0, -4)
  label:SetText(atlas or path)
end

local function measure(parent, setup, text)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:Hide()
  setup(fs)
  fs:SetText(text)
  return fs:GetStringWidth()
end

local function fontLine(parent, r, key, label, y, setup)
  local ok, err = pcall(function()
    local widths = {}
    for i, seg in ipairs(SEGMENTS) do widths[i] = measure(parent, setup, seg) end
    r.fonts[key] = { ok = true, segments = widths }
  end)
  if not ok then r.fonts[key] = { ok = false, err = plain(err) } end
  local tag = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tag:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
  tag:SetText(label)
  local line = parent:CreateFontString(nil, "OVERLAY")
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", 230, y)
  pcall(setup, line)
  line:SetText(SAMPLE)
end

local function build()
  local r = results()
  local f = CreateFrame("Frame", "GoldCapSkinProbe", UIParent)
  f:SetSize(900, 600)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

  for i, path in ipairs(TEXTURES) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    textureCell(f, path, 20 + col * 215, -30 - row * 105, r)
  end

  local base = -370
  fontLine(f, r, "a_setfont", "(a) SetFont FRIZQT 13", base, function(fs) fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "") end)
  fontLine(f, r, "b_fontobject", "(b) GameFontNormal", base - 30, function(fs) fs:SetFontObject(GameFontNormal) end)

  local okC, famC = pcall(makeFamily, "GoldCapProbeClassic13", 13)
  r.fonts.c_create = { ok = okC, err = okC and "" or plain(famC) }
  fontLine(f, r, "c_family13", "(c) family 13", base - 60, function(fs) fs:SetFontObject(famC) end)

  local okD, famD = pcall(makeFamily, "GoldCapProbeClassic16", 16)
  r.fonts.d_create = { ok = okD, err = okD and "" or plain(famD) }
  fontLine(f, r, "d_family16", "(d) family 16", base - 90, function(fs) fs:SetFontObject(famD) end)

  -- (e) a second family under the name of (c): does the client refuse, replace or duplicate it?
  local okE, errE = pcall(makeFamily, "GoldCapProbeClassic13", 13)
  r.fonts.e_duplicate = { ok = okE, result = plain(errE) }
  local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", f, "TOPLEFT", 20, base - 130)
  note:SetText("(e) second CreateFontFamily(GoldCapProbeClassic13): pcall ok = " .. tostring(okE) .. "  " .. tostring(plain(errE)))
  return f
end

SLASH_GOLDCAPPROBE1 = "/gcprobe"
SlashCmdList.GOLDCAPPROBE = function(msg)
  if (msg or ""):match("^%s*(%S*)") == "skins" then
    if not panel then panel = build() end
    panel:Show()
  else
    GC.Print("/gcprobe skins")
  end
end
