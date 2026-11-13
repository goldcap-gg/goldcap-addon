local _, GC = ...

-- WoW: Forever's crafting prices. Loaded by GoldCap_Camelot.toc alone, right after
-- Services/CraftClient.lua, whose functions it replaces where Forever differs, the way Blizzard's
-- own Forever files replace methods of a shared file ([Game]\Blizzard_ProfessionsCrafting.lua
-- [AllowLoadGameType camelot] in Blizzard_Professions.toc). Retail never loads it.
--
-- - A reagent a vendor sells: the price the player saw at a merchant (Core/ForeverVendorPrices.lua)
--   comes first, then a BUY list's vendor price as on retail, then the auction house. Forever's
--   scans rarely see thread, vials or flux on the auction house, and when they do it is a resale
--   above what the vendor asks. A reagent no merchant was seen selling and no scan priced stays
--   without a price: its recipe is counted as having none, never priced at zero or at a guess.
--   Every merchant the player opens is read for that (MERCHANT_SHOW and MERCHANT_UPDATE, this
--   file's own event frame, each registered under pcall: Core/Init.lua is not touched).
-- - No sales a day: Forever's prices are scans of what is listed (Core/Data.lua's ForeverValueFor)
--   and say nothing of what sells, so the Worth crafting list shows no pace and no "Slow seller".
-- - A scan of a thin book prices nothing: under the 20 units listed the Deals board asks for a
--   market (Core/ForeverDeals.lua's MARKET_MIN_UNITS), the cheapest units are often asks nobody
--   pays (a crowd value of 79s98 from two units, owner 2026-11-07), and the Worth crafting list,
--   sorted by profit, would put that item first. Its recipe counts as having no price.
-- - Where a merchant visit could fill a missing price, or the book was too thin, the result says
--   so (`vendorHint`, `thin`), and the panel's This recipe adds how (UI/CraftPanel_Camelot.lua).
local CC = GC.CraftClient
local retail = { VendorOf = CC.VendorOf, ProfitOf = CC.ProfitOf }

local function root()
  local F = GC.ForeverScan
  return F and F.Root and F.Root() or nil
end

--- What a vendor charges for one of an item: what a merchant asked the player, else what a BUY list
--- the player holds says (nil: neither).
function CC.VendorOf(itemID)
  if type(itemID) ~= "number" then return nil end
  return GC.ForeverVendorPrices.UnitFor(root(), itemID) or retail.VendorOf(itemID)
end

-- The scan's price for one, and whether the book it came from was too thin to give one.
local function scanned(itemID)
  local v = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(itemID) or nil
  local unit = GC.Tooltip.TrustedHeadline(v)
  if type(unit) ~= "number" then return nil, false end
  if type(v.currentQty) ~= "number" or v.currentQty < GC.ForeverDeals.C.MARKET_MIN_UNITS then return nil, true end
  return math.floor(unit), false
end

--- What one of a reagent costs: a vendor's price (VendorOf), else the auction house's from a book
--- of at least 20 units.
function CC.UnitOf(itemID)
  if type(itemID) ~= "number" then return nil end
  return CC.VendorOf(itemID) or (scanned(itemID))
end

--- What one of a crafted item sells for on Forever's auction house, from a book of at least 20
--- units and no more than it sells for now, and how many of it sell a day there: the site's sales
--- tape of this auction house (GC.Data.ForeverSales), nil while the Companion has brought none. The
--- scans say nothing of what sells.
function CC.SellOf(itemID)
  if type(itemID) ~= "number" then return nil end
  local unit = scanned(itemID)
  if not unit then return nil end
  local sales = GC.Data and GC.Data.ForeverSales and GC.Data.ForeverSales(itemID) or nil
  if type(sales) ~= "table" then return unit end
  -- Never above what it sells for now: a lot can hang at a price nobody pays. The site says that
  -- for a crafted item (`recent`: the lower of the last day's and six hours' medians that hold
  -- three sales); the tape's median, the lowest of its week, day and six hours, stood in for it
  -- before and does for an item the site leaves out. On a market that rose this week the week's
  -- median is last week's price: Draught of Water Breathing was counted at 2s 40c with its
  -- cheapest lot at 8s 36c (ClickUp 1an60dzww4h). A listing under the cap stands, the craft has
  -- to undercut it.
  local sold = type(sales.recent) == "number" and sales.recent > 0 and sales.recent or sales.median
  if type(sold) == "number" and sold > 0 and sold < unit then unit = math.floor(sold) end
  return unit, type(sales.perDay) == "number" and sales.perDay or nil
end

--- What posting one of an item takes as a deposit, which a sale returns: the client's quote for a
--- commodity (GC.ForeverValue.CommodityDepositUnit). nil where there is none to quote.
function CC.DepositOf(itemID)
  local F = GC.ForeverValue
  if type(itemID) ~= "number" or not (F and F.CommodityDepositUnit) then return nil end
  local deposit = F.CommodityDepositUnit(itemID)
  return type(deposit) == "number" and deposit > 0 and deposit or nil
end

--- Core/CraftMath.lua's Profit at these prices, as on retail. A result missing a price carries
--- `thin` when one of the missing items has a scan from a book too thin to price, and `vendorHint`
--- when one is a crafting reagent of the recipe (not the item it makes) no vendor price is known
--- for: a merchant that sells it would give it a price.
function CC.ProfitOf(recipe, open)
  local result = retail.ProfitOf(recipe, open)
  if type(result) ~= "table" or type(result.missing) ~= "table" or type(recipe) ~= "table" then return result end
  local mine = type(open) == "table" and (open.recipeID == nil or open.recipeID == recipe.recipeID)
  local output = (mine and open.output) or recipe.output
  for _, m in ipairs(result.missing) do
    if m.currencyID == nil and type(m.itemID) == "number" then
      if select(2, scanned(m.itemID)) then result.thin = true end
      if m.itemID ~= output and GC.VendorBuys.IsReagent(m.itemID) then result.vendorHint = true end
    end
  end
  return result
end

--- Reads the merchant window the player has open and keeps what it asks for each crafting reagent
--- (Core/ForeverVendorPrices.lua). Answers how many items it kept.
function CC.ReadMerchant(now)
  local where = root()
  local count = _G.GetMerchantNumItems
  if not where or type(count) ~= "function" then return 0 end
  local okN, n = pcall(count)
  if not okN or type(n) ~= "number" then return 0 end
  local rows = {}
  for index = 1, n do
    local row = GC.VendorBuys.MerchantRow(index)
    if row and type(row.itemID) == "number" then rows[#rows + 1] = row end
  end
  return GC.ForeverVendorPrices.Record(where, GC.BuyVendor.Offers(rows), GC.VendorBuys.IsReagent, now or time())
end

-- MERCHANT_UPDATE comes again and again while the window is open (stock, item data arriving): one
-- read on the next frame for all of them.
local pending = false
local function readSoon()
  if pending then return end
  pending = true
  local timer = _G.C_Timer
  local function read()
    pending = false
    pcall(CC.ReadMerchant)
  end
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, read) else read() end
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do pcall(events.RegisterEvent, events, event) end
  events:SetScript("OnEvent", readSoon)
  CC._merchantEvents = events
end
