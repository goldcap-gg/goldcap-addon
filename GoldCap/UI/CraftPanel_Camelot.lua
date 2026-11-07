local _, GC = ...

-- WoW: Forever's crafting panel. Loaded by GoldCap_Camelot.toc alone, after UI/CraftStrip.lua,
-- UI/CraftPanel.lua and UI/CraftQueueView.lua, whose fields it replaces where Forever's window or
-- data differ, the way Blizzard's own Forever files replace methods of a shared file
-- (Services/CraftClient_Camelot.lua says the same). Retail never loads it. The panel is retail's
-- panel otherwise: the same header, This recipe, Worth crafting and Queue.
--
-- - Where it stands: Forever's profession window hangs its book tab and a tab for each profession
--   off its right edge (Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml:
--   ProfessionsOverviewTab at the window's TOPRIGHT, the rest under it), each as wide as the
--   "common-sidetab" art (SidePanelTabButtonMixin.CalculateTabSizeBasedOnTabArt). The panel stands
--   right of them, or the player could not switch professions.
-- - The price line: Forever's prices are scans of its auction house, the player's own and every
--   player's through the Companion (Core/Data.lua's ForeverValueFor), never retail's region data,
--   so the line says which and how old.
-- - No strip under the reagents: Forever's form is narrower and keeps its Track Recipe checkbox
--   at its bottom right (Blizzard_Professions/Camelot/Blizzard_ProfessionsCrafting.lua's
--   OverrideArt), where the strip would end. This recipe shows the same three figures.
-- - A missing reagent price that a merchant visit can fill says so in This recipe, and so does one
--   a scan saw too few listed to price (Services/CraftClient_Camelot.lua's vendorHint and thin).
local P, S = GC.CraftPanel, GC.CraftStrip

-- How long prices count as fresh, as the Hoard's footer has it for the Companion's (two hours).
P.FRESH_SECONDS = 7200

--- Past the side tabs Forever's window hangs at its right edge; at the edge when it has none.
function P.Place(f, frame)
  local tab = type(frame) == "table" and frame.ProfessionsOverviewTab or nil
  local x = 0
  if type(tab) == "table" and type(tab.GetWidth) == "function" then
    local ok, width = pcall(tab.GetWidth, tab)
    if ok and type(width) == "number" and width > 0 then x = math.ceil(width) end
  end
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", x, 0)
end

local function ago(now, at)
  return GC.Util.FormatElapsedWords(math.max(0, now - at)) or GC.Util.FormatElapsedWords(0)
end

--- Where Forever's prices come from and how old they are, and whether the newest is fresh: the
--- player's own last scan of this auction house (GC.ForeverScan.Fold), every player's scans the
--- Companion brought (GC.Data.ForeverPayload), both, or neither.
function P.PricesNow(now)
  now = now or time()
  local F, D = GC.ForeverScan, GC.Data
  local fold = F and F.Fold and F.Fold() or nil
  local own = type(fold) == "table" and type(fold.at) == "number" and fold.at or nil
  local payload = D and D.ForeverPayload and D.ForeverPayload() or nil
  local crowd = type(payload) == "table" and type(payload.ts) == "number" and payload.ts or nil
  if not (own or crowd) then return GC.L["No scan of this auction house yet."], false end
  local newest = math.max(own or 0, crowd or 0)
  local fresh = now - newest < P.FRESH_SECONDS
  if own and crowd then
    return GC.L["Prices from your scan %s ago and the Companion %s ago"]:format(ago(now, own), ago(now, crowd)), fresh
  end
  if own then return GC.L["Prices from your scan %s ago"]:format(ago(now, own)), fresh end
  return GC.L["Prices from the Companion, %s ago"]:format(ago(now, crowd)), fresh
end

-- The strip is never built on Forever: its event frame asks for S.Attach a frame after the window
-- opens, and this one builds nothing.
function S.Attach() end

local retailLines = S.Lines

--- The strip's lines, as This recipe shows the first: "No GoldCap price for ...", and on Forever how
--- a merchant gives a vendor's reagent its price and how many listed an auction house price needs.
function S.Lines(result)
  local lines = retailLines(result)
  if type(result) ~= "table" or not lines[1] then return lines end
  if result.vendorHint then
    lines[1].text = lines[1].text .. " " .. GC.L["A reagent a vendor sells gets its price once you open that vendor."]
  end
  if result.thin then
    lines[1].text = lines[1].text .. " "
      .. GC.L["An auction house price needs at least %d listed."]:format(GC.ForeverDeals.C.MARKET_MIN_UNITS)
  end
  return lines
end
