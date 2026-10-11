-- Theme.Chip (a tinted pill) and Theme.TierMark (a dot and a label), moved out of UI/Theme.lua.
-- The chip's label is now in the condensed heading face; the tier mark keeps the mono face, whose
-- width spec/button_label_width_spec.lua budgets for the Forever verdict cell.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme
local MEDIA = GC.Kit.MEDIA
local K = GC.Kit.Tokens.color

-- Chip: a tinted pill, not the old solid plaque + underline. Nine-slice invariant (see
-- the slice comments in UI/Kit/Textures.lua): margins must stay BELOW half the smallest
-- widget edge, or the sliced corners overlap and notch. This pill is 20px tall -- T.SLICE.plaque
-- (12) is not below half of a 24px pill (12), so plaque.png was ruled out; T.SLICE.badge (6) IS
-- below half of 20 (10), so this uses badge.png at height 20, with no separate ring texture
-- (badge.png has none -- unlike T.Card's card.png/plaque.png, which pair with ring.png/
-- plaque_ring.png).
-- Grepped every spec and every UI source before removing the old `f.underline` texture: nothing
-- reads `.underline` off a chip (SoldFrame.lua's own header-underline is an unrelated feature
-- with its own texture), so it is dropped outright rather than kept as a hidden stand-in.
function T.Chip(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(20)

  -- File texture, recolored via SetVertexColor only (never SetColorTexture, which would strip
  -- the art) -- same rule T.Card:SetTint and Theme.Button's rounded bg follow.
  f.bg = T.SlicedTexture(f, "BACKGROUND", MEDIA .. "badge.png", { K.windowTop[1], K.windowTop[2], K.windowTop[3] }, T.SLICE.badge)
  f.bg:SetAllPoints()

  f.text = T.Heading(f, 10)
  f.text:SetJustifyH("CENTER")
  -- Bounded to the pill's own width (a bare CENTER point has no width limit at all) and
  -- non-wrapping, so a long label (e.g. "SUSPECT") truncates inside the pill instead of
  -- overflowing into whatever sits to its right.
  f.text:SetPoint("LEFT", 4, 0)
  f.text:SetPoint("RIGHT", -4, 0)
  f.text:SetWordWrap(false)

  function f:SetLabel(text, colorTable)
    f.text:SetText(text)
    local c = colorTable or K.text1
    f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    -- Fill at low alpha over the dark panel underneath -- a pill reads as a tinted surface,
    -- not a solid block of the tier color. No ring layer to tint alongside it (see above).
    f.bg:SetVertexColor(c[1], c[2], c[3], 0.12)
  end

  return f
end

-- TierMark: a 6x6 color dot + mono label, a plainer stand-in for T.Chip's tinted badge pill
-- (see T.Chip's own comment above) everywhere a tier marker sits inline in a row rather than
-- boxed on its own. `:SetLabel(text, colorTable)` is the exact call signature SniperFrame's
-- row-stamping line already uses on T.Chip, so swapping the widget that builds `row.tierChip`
-- does not touch that call site.
function T.TierMark(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(10)

  f.dot = T.Solid(f, "ARTWORK", K.text3)
  f.dot:SetSize(6, 6)
  f.dot:SetPoint("LEFT")

  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(T.FONT_UI_BOLD, 10 * T.Scale(), "")
  f.text:SetJustifyH("LEFT")
  -- Bounded to the mark's own width and non-wrapping, exactly as T.Chip's label is (see its
  -- comment): a bare LEFT point has no width limit at all, so a label longer than the cell
  -- paints straight across whatever sits to its right instead of clipping. The Sniper board's
  -- verdict cell is what found this -- a refusal sentence in that column ran over the discount
  -- and price figures beside it.
  f.text:SetPoint("LEFT", f.dot, "RIGHT", 5, 0)
  f.text:SetPoint("RIGHT")
  f.text:SetWordWrap(false)
  T.TrackFont(f.text, { role = "uiBold", path = T.FONT_UI_BOLD, size = 10 })

  function f:SetLabel(text, colorTable)
    f.text:SetText(text)
    local c = colorTable or K.text1
    f.dot:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end

  return f
end
