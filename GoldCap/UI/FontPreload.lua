-- Has the client load GoldCap's own font files at login, long before any window draws with them.
--
-- The first time the client draws with a font file it has not loaded yet, the text laid out in
-- that frame is not drawn, and nothing draws it later: setting the same text or the same font
-- again is a no-op to the client. The Sniper window is built in one frame on the first auction
-- house visit of a session and was the first thing to use these faces, so its column headings
-- came up blank until a click re-stamped them (WoW: Forever 1.60.1; a probe on 2026-10-06 drew
-- them with the same re-stamp one frame later, and not in the frame the window was built in).
-- Re-stamping is a race with the load, which is why that fix kept coming back.
--
-- ElvUI ("to prevent fonts not being ready") and TradeSkillMaster preload their bundled fonts the
-- same way: a string in each face, in a frame that is shown, sized and anchored. Off screen is
-- fine; hidden, unsized or unanchored loads nothing (ElvUI's own finding). It is never hidden.
local _, GC = ...
local T = GC.Theme

local preloader = CreateFrame("Frame")
preloader:SetPoint("TOP", UIParent, "BOTTOM", 0, -10000)
preloader:SetSize(100, 100)

local preloaded = {}

local function preload(path)
  if preloaded[path] then return end
  local fs = preloader:CreateFontString()
  fs:SetAllPoints()
  -- SetFont says whether the face was accepted; SetText on a string with no font is an error. A
  -- face the client is still loading can raise instead of answering (skin probe, WoW: Forever
  -- 2026-11-10), and is asked again on the next call.
  local ok, set = pcall(fs.SetFont, fs, path, 14, "")
  if ok and set then
    preloaded[path] = true
    fs:SetText("GoldCap 0123 Аа ґї") -- Latin, digits and Cyrillic: what these faces draw
  end
end

for _, path in ipairs(T.BUNDLED_FACES) do preload(path) end

--- The applied skin's faces, preloaded the same way (UI/Kit/Skins.lua Apply calls this). A path
-- already preloaded gets no second string.
function T.PreloadFaces(paths)
  for _, path in ipairs(paths) do preload(path) end
end
