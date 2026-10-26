-- Theme.Bar: a thin progress bar, a quiet track with a fill over it, as the Disenchant window's
-- cast and Send to alts' mail count draw theirs. Its width is its anchors'; the fill follows it.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme
local K = GC.Kit.Tokens.color

local TRACK = { 1, 1, 1, 0.08 }

function T.Bar(parent, height, color)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(height)
  f.track = T.Solid(f, "ARTWORK", TRACK)
  f.track:SetAllPoints()
  local c = color or K.gold
  f.fill = T.Solid(f, "OVERLAY", c)
  f.fill:SetPoint("TOPLEFT")
  f.fill:SetPoint("BOTTOMLEFT")
  f.fill:Hide()
  local share = 0

  local function paint()
    f.fill:SetShown(share > 0)
    if share > 0 then f.fill:SetWidth(math.max(1, math.floor((f:GetWidth() or 0) * share + 0.5))) end
  end

  -- `share` of the track, 0 to 1 (outside it is clamped); nothing is drawn at 0.
  function f:SetShare(v)
    share = math.min(1, math.max(0, tonumber(v) or 0))
    paint()
  end

  function f:SetColor(col)
    f.fill:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
  end

  f:SetScript("OnSizeChanged", paint)
  return f
end
