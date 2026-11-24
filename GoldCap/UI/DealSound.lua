local _, GC = ...

-- The sound a deal makes: a row turning SAFE, or a lot its Check would buy (UI/SniperFrame.lua's
-- stampVerdict; WoW: Forever's gear loop spaces those out, UI/SniperGearLoop_Camelot.lua), and a
-- new HOT deal on the board (pingNewHotDeals).
-- Players asked for a quieter one than the raid's ready check (owner, 2026-11-23), so it is the
-- player's pick in SETTINGS -> AUTOMATION & ALERTS, out of the game's own sounds, and so is whether
-- it plays at the master volume even with the game's sound effects off. The price-rise alarm in the
-- buy window stays the raid warning: it is a warning, not a find.
--
-- Settings (settings.sniper):
--   sound        on or off, as before (Core/Init.lua; off stays off)
--   dealSound    which sound, an id from CHOICES; unset or unknown is DEFAULT
--   soundMaster  false: the sound effects channel, which follows the game's effects volume;
--                anything else: the master channel, as the deal sound always played
local DS = {}
GC.DealSound = DS

-- Sounds both games have, by their SOUNDKIT name, with the kit's number where the table lacks
-- the name (each checked in Blizzard's SoundKitConstants.lua for retail and WoW: Forever).
DS.CHOICES = {
  { id = "coins", kit = "LOOT_WINDOW_COIN_SOUND", number = 120 },
  { id = "whisper", kit = "TELL_MESSAGE", number = 3081 },
  { id = "ping", kit = "MAP_PING", number = 3175 },
  { id = "readycheck", kit = "READY_CHECK", number = 8960 },
}
-- The map ping by default (owner, 2026-11-23): heard, and gentler than the ready check.
DS.DEFAULT = "ping"

local byId = {}
for _, choice in ipairs(DS.CHOICES) do byId[choice.id] = choice end

-- A choice's name in the player's language.
function DS.Name(id)
  if id == "coins" then return GC.L["Coins"] end
  if id == "whisper" then return GC.L["Whisper"] end
  if id == "ping" then return GC.L["Map ping"] end
  if id == "readycheck" then return GC.L["Ready check"] end
  return DS.Name(DS.DEFAULT)
end

-- The id in force for these settings.
function DS.Chosen(sniper)
  local id = type(sniper) == "table" and sniper.dealSound
  return byId[id] and id or DS.DEFAULT
end

function DS.Channel(sniper)
  return (type(sniper) == "table" and sniper.soundMaster == false) and "SFX" or "Master"
end

-- Plays `id` (a preview from SETTINGS), or the chosen sound; whatever the on/off switch says.
-- Answers PlaySound's first return: whether the client will play it.
function DS.Play(sniper, id)
  local choice = byId[id] or byId[DS.Chosen(sniper)]
  local kit = (type(SOUNDKIT) == "table" and SOUNDKIT[choice.kit]) or choice.number
  if type(PlaySound) ~= "function" then return false end
  return PlaySound(kit, DS.Channel(sniper)) and true or false
end

-- A deal was found: the chosen sound when the switch is on. DEALS' AUTO readout counts its deals
-- where a Check answers (Core/AutoReadout.lua), not here.
function DS.Ring(sniper)
  if not (type(sniper) == "table" and sniper.sound) then return false end
  return DS.Play(sniper)
end
