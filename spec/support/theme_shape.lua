-- Theme.Shape and Theme.SetShape (UI/Kit/Textures.lua) for a spec's Theme double: goldcap's art for
-- each role, by file name under a double's MEDIA of "" ("plaque.png"), and the role's slice margin.
-- A double's own ShapeTexture draws through its own SlicedTexture, so what it records stays as it was.
local S = {}

local ART = {
  panel = { "card.png", "ring.png", 24 },
  control = { "plaque.png", "plaque_ring.png", 12 },
  chip = { "badge.png", "badge_ring.png", 6 },
}

function S.Shape(role)
  local art = assert(ART[role], "no shape " .. tostring(role))
  return art[1], art[2], art[3]
end

function S.SetShape(tx, role, ring)
  local fill, outline, margin = S.Shape(role)
  tx:SetTexture(ring and outline or fill)
  if tx.SetTextureSliceMargins then tx:SetTextureSliceMargins(margin, margin, margin, margin) end
end

return S
