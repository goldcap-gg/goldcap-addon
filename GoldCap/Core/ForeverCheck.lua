local _, GC = ...

-- /gc forever: what this client offers GoldCap, printed plainly so a player can paste it into a
-- bug report. Also answers the one open WoW: Forever question on the spot: at an open auction
-- house it calls the full scan once and prints the row count as it arrives. Diagnostic output,
-- English on purpose (like the beta probe), so it adds no GC.L keys.
GC.ForeverCheck = GC.ForeverCheck or {}

local DELAYS = { 2, 5, 10, 20, 40 }

local function realEnv()
  return {
    C_AuctionHouse = _G.C_AuctionHouse,
    AuctionHouseFrame = _G.AuctionHouseFrame,
    C_Timer = _G.C_Timer,
    GoldCap_MarketData = _G.GoldCap_MarketData,
    GoldCap_AppData = _G.GoldCap_AppData,
    print = function(msg) if GC.Print then GC.Print(msg) else print(msg) end end,
  }
end

local function has(t, name) return type(t) == "table" and type(t[name]) == "function" end

function GC.ForeverCheck.Report(env)
  env = env or realEnv()
  local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or nil
  local game = p and (GC.Game.IsForever(p) and "WoW: Forever" or (GC.Game.IsRetail(p) and "retail" or "another WoW client")) or "unknown client"
  local ah = env.C_AuctionHouse
  return {
    ("game: %s (interface %s, build %s, region id %s)"):format(
      game, p and tostring(p.interface) or "?", p and p.build or "?", p and tostring(p.regionId) or "?"),
    "retail price snapshot: " .. (env.GoldCap_MarketData and "loaded" or "not loaded"),
    "Companion data: " .. (env.GoldCap_AppData and "present" or "none"),
    "ReplicateItems: " .. (has(ah, "ReplicateItems") and "present" or "missing"),
    "GetNumReplicateItems: " .. (has(ah, "GetNumReplicateItems") and "present" or "missing"),
  }
end

function GC.ForeverCheck.Run(env)
  env = env or realEnv()
  local say = env.print
  for _, line in ipairs(GC.ForeverCheck.Report(env)) do say("forever check: " .. line) end
  -- The full-scan probe below calls ReplicateItems -- exactly the server-side auction-house
  -- dump GoldCap otherwise never triggers itself. /gc forever is a WoW: Forever diagnostic;
  -- run on retail it would fire that dump for no reason (final review M1).
  local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or nil
  if not (GC.Game and GC.Game.IsForever and GC.Game.IsForever(p)) then
    say("forever check: the full-scan test runs only in WoW: Forever"); return
  end
  local ah = env.C_AuctionHouse
  if not (has(ah, "ReplicateItems") and has(ah, "GetNumReplicateItems")) then
    say("forever check: ReplicateItems is missing -- no full scan in this client"); return
  end
  local frame = env.AuctionHouseFrame
  if not (frame and frame.IsShown and frame:IsShown()) then
    say("forever check: open the auction house, then run /gc forever again to test the full scan"); return
  end
  local okBefore, before = pcall(ah.GetNumReplicateItems)
  local ok, err = pcall(ah.ReplicateItems)
  if not ok then say("forever check: ReplicateItems failed: " .. tostring(err)); return end
  say(("forever check: full scan requested; rows before: %s. A second request within ~15 minutes may do nothing."):format(
    okBefore and tostring(before) or "?"))
  if not has(env.C_Timer, "After") then return end
  for _, s in ipairs(DELAYS) do
    env.C_Timer.After(s, function()
      local okN, n = pcall(ah.GetNumReplicateItems)
      say(("forever check: +%ds: %s rows"):format(s, okN and tostring(n) or "?"))
    end)
  end
end
