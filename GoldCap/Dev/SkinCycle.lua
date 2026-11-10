-- Dev only (loaded inside the #@debug@ block of both TOCs, never in a release).
-- /gcskin stores the next skin of Skins.ORDER (after the last, the first) and reloads the UI,
-- because the stored skin is applied once at ADDON_LOADED. For stepping through all nine in game.
local _, GC = ...

SLASH_GOLDCAPSKIN1 = "/gcskin"
SlashCmdList.GOLDCAPSKIN = function()
  local order = GC.Kit.Skins.ORDER
  local sniper = GC.db.settings.sniper
  local at = 1
  for i, id in ipairs(order) do
    if id == sniper.skin then at = i break end
  end
  local nextId = order[at % #order + 1]
  sniper.skin = nextId
  GC.Print("skin: " .. nextId)
  ReloadUI()
end
