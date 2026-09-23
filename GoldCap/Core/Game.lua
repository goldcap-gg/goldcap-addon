local _, GC = ...

-- Which game client this is. WoW: Forever reports WOW_PROJECT_ID 1, the same as retail, so
-- the interface number is the only reliable tell: retail's are six digits (120100), every
-- other client is below (Classic Era 11508, Anniversary 20505, MoP Classic 50500, Forever
-- 16001). The passport is written into GoldCapDB.client on every load; the companion sends
-- it with every upload and keeps another game's files away from the retail routes
-- (docs/companion/AGENTS.md "Client passport").
GC.Game = GC.Game or {}
GC.Game.RETAIL_MIN_INTERFACE = 100000

local function defaultApi()
  return { GetBuildInfo = _G.GetBuildInfo, GetCurrentRegion = _G.GetCurrentRegion }
end

function GC.Game.Passport(api)
  api = api or defaultApi()
  if type(api.GetBuildInfo) ~= "function" then return nil end
  local ok, version, build, _, toc = pcall(api.GetBuildInfo)
  if not ok or type(toc) ~= "number" or type(version) ~= "string" or build == nil then return nil end
  local regionId
  if type(api.GetCurrentRegion) == "function" then
    local rok, region = pcall(api.GetCurrentRegion)
    if rok and type(region) == "number" then regionId = region end
  end
  return { interface = toc, build = version .. "." .. tostring(build), regionId = regionId }
end

function GC.Game.IsRetail(passport)
  if passport == nil then return true end
  return passport.interface >= GC.Game.RETAIL_MIN_INTERFACE
end
