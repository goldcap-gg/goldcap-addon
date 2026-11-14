local _, GC = ...

-- WoW: Forever: reads a profession trainer's window and a merchant's window into
-- Core/ForeverSources.lua. Loaded by GoldCap_Camelot.toc alone, right after
-- Services/CraftClient_Camelot.lua, the other Forever file that reads every merchant the player
-- opens; retail never loads it. Passive: no window, no chat line, no protected call, and no filter
-- is touched (Blizzard's trainer window hides what the character has learned, and the store takes
-- a partial list as it comes). Every client read is guarded, and a window's rows reach the store
-- in one call, so a read that fails halfway keeps nothing.
--
-- What the client gave on Forever (probe, 2026-11-14, 10 trainer windows and 8 merchants):
-- - A trainer's rows arrive with TRAINER_UPDATE; at TRAINER_SHOW it lists none. A trainer that is
--   not a profession trainer (IsTradeskillTrainer) is not read.
-- - A row's recipe is its tooltip's spell: C_TooltipInfo.GetTrainerService gives type 1 and the
--   spell's id. The rank rows ("Journeyman Leatherworking") are spells too and are kept, with the
--   rank's cost, skill and level. The crafted item's link can still be loading (nil).
-- - A merchant's rows come from GC.VendorBuys.MerchantRow, the one place the merchant is read, and
--   each item's class and subclass from C_Item.GetItemInfoInstant.
-- - Half the probe's merchant reads, a second after MERCHANT_SHOW, listed no items and no npc: such
--   a read keeps nothing.
-- Each event asks for one read SC.DELAY seconds later, which the events before it share.
GC.SourcesClient = GC.SourcesClient or {}
local SC = GC.SourcesClient

SC.DELAY = 0.3

-- Enum.TooltipDataType.Spell.
local SPELL_TOOLTIP = 1

local ask = GC.Util.Ask

local function root()
  local F = GC.ForeverScan
  return F and F.Root and F.Root() or nil
end

-- In a restricted context the client hands secret values, which addon code may not compare.
local function plain(v)
  local secret = _G.issecretvalue
  if v == nil or type(secret) ~= "function" then return v end
  local ok, yes = pcall(secret, v)
  if ok and not yes then return v end
  return nil
end

-- The npc whose window is open, and where the player stands. nil without an npc.
local function npcHere()
  local guid = plain(ask(_G.UnitGUID, "npc"))
  if type(guid) ~= "string" then return nil end
  local map = _G.C_Map
  return { guid = guid, name = plain(ask(_G.UnitName, "npc")),
    map = plain(ask(type(map) == "table" and map.GetBestMapForUnit or nil, "player")),
    zone = plain(ask(_G.GetRealZoneText)), subzone = plain(ask(_G.GetSubZoneText)),
    faction = plain(ask(_G.UnitFactionGroup, "npc")) }
end

--- Reads the profession trainer whose window is open into the store. Answers how many services it
--- kept.
function SC.ReadTrainer(now)
  local where = root()
  if not where or ask(_G.IsTradeskillTrainer) ~= true then return 0 end
  local count = plain(ask(_G.GetNumTrainerServices))
  if type(count) ~= "number" or count < 1 then return 0 end
  local npc = npcHere()
  if not npc then return 0 end
  local tooltips = _G.C_TooltipInfo
  local tip = type(tooltips) == "table" and tooltips.GetTrainerService or nil
  local services = {}
  for index = 1, count do
    local data = ask(tip, index)
    if type(data) == "table" and data.type == SPELL_TOOLTIP then
      local ok, reqLine, reqSkill = pcall(_G.GetTrainerServiceSkillReq, index)
      if not ok then reqLine, reqSkill = nil, nil end
      local line = plain(ask(_G.GetTrainerServiceSkillLine, index))
      if type(line) ~= "string" or line == "" then line = plain(reqLine) end
      services[#services + 1] = { spellID = plain(data.id), skillLine = line, requiredSkill = plain(reqSkill),
        cost = plain(ask(_G.GetTrainerServiceCost, index)), level = plain(ask(_G.GetTrainerServiceLevelReq, index)),
        link = plain(ask(_G.GetTrainerServiceItemLink, index)) }
    end
  end
  return GC.ForeverSources.RecordTrainer(where, npc, services, now or time())
end

--- Reads the merchant whose window is open into the store. Answers how many items it kept.
function SC.ReadMerchant(now)
  local where = root()
  if not where then return 0 end
  local count = plain(ask(_G.GetMerchantNumItems))
  if type(count) ~= "number" or count < 1 then return 0 end
  local npc = npcHere()
  if not npc then return 0 end
  local instant = type(C_Item) == "table" and C_Item.GetItemInfoInstant or nil
  local items = {}
  for index = 1, count do
    local row = GC.VendorBuys.MerchantRow(index)
    if row and type(row.itemID) == "number" then
      local ok, _, _, _, _, _, classID, subclassID = pcall(instant, row.itemID)
      items[#items + 1] = { itemID = row.itemID, price = row.price, stack = row.stackCount,
        available = row.numAvailable, classID = ok and classID or nil, subclassID = ok and subclassID or nil,
        extended = row.hasExtendedCost == true }
    end
  end
  return GC.ForeverSources.RecordVendor(where, npc, items, now or time())
end

-- One read SC.DELAY seconds after the first event of a burst, for all of them.
local pending = {}
local function soon(what, read)
  if pending[what] then return end
  pending[what] = true
  local function run()
    pending[what] = nil
    pcall(read)
  end
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(SC.DELAY, run) else run() end
end

local EVENTS = { TRAINER_UPDATE = "trainer", MERCHANT_SHOW = "merchant", MERCHANT_UPDATE = "merchant" }

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "TRAINER_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    local what = EVENTS[event]
    if what == "trainer" then
      soon(what, SC.ReadTrainer)
    elseif what == "merchant" then
      soon(what, SC.ReadMerchant)
    end
  end)
  SC._events = events
end
