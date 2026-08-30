local _, GC = ...

GC.Tooltip = {}

-- opts (optional): { unitCost = <copper per unit still held>, region = <"eu"|"kr"|...> }.
-- Both come from the caller rather than from `v` because neither belongs to the market
-- value: one is the player's own ledger, the other is which bundled table answered.
function GC.Tooltip.BuildLines(v, now, opts)
  if not v or not v.mv then return nil end
  opts = opts or {}
  local lines = { { kind = "money", label = GC.L["GoldCap value"], copper = v.mv } }
  -- Import-path only: MarketData.lua's bundled entries never carry a trend (see
  -- ImportString.Parse and generateAddonData.ts). A flat 0% is not worth a line.
  if type(v.trend) == "number" and v.trend ~= 0 then
    lines[#lines + 1] = { kind = "text", left = GC.L["24h trend"], right = string.format("%+d%%", v.trend) }
  end
  if v.sold then
    lines[#lines + 1] = { kind = "text", left = GC.L["Sold per day"], right = string.format("%.1f", v.sold) }
  end
  -- Depth. `currentQty` (units on the region's shelf) and `listings` (auctions holding them)
  -- ride the import string's verification token, which the server writes for commodities
  -- only -- so this is an imported-commodity line by construction: the bundled snapshot
  -- carries no verification at all, and a realm item from an I token has no depth to report.
  -- The shelf count is the better answer to the same question the auction count was
  -- answering, so it takes that slot rather than adding a fourth number.
  if v.currentQty and v.currentQty > 0 then
    local right = tostring(v.currentQty)
    local supply = GC.Util.FormatSupplyDays(v.currentQty, v.sold)
    if supply then right = right .. " · " .. supply end
    lines[#lines + 1] = { kind = "text", left = GC.L["Listed"], right = right }
  elseif v.listings and not v.sold then
    -- `not v.sold` keeps the exclusivity these two lines had when they were one if/elseif:
    -- no item has ever shown a sales rate and an auction count together.
    lines[#lines + 1] = { kind = "text", left = GC.L["Listings"], right = tostring(v.listings) }
  end
  if opts.unitCost then
    lines[#lines + 1] = { kind = "money", label = GC.L["You paid"], copper = opts.unitCost }
  end
  local age = now - (v.ts or 0)
  if v.source == "bundled" then
    -- Bundled data is stale by construction -- it was baked into the release -- and it is
    -- region-wide, not this realm's. Saying so is not optional.
    -- A format, not concatenation: word order around the region code is the translator's
    -- to choose, and "Bundled %s data" is the only shape that lets them choose it.
    local label = opts.region and (GC.L["Bundled %s data"]):format(string.upper(opts.region))
      or GC.L["Bundled data"]
    lines[#lines + 1] = { kind = "text", left = label, right = GC.Util.FormatAge(age) }
  elseif age > 48 * 3600 then
    lines[#lines + 1] = { kind = "text", left = GC.L["GoldCap data age"], right = GC.Util.FormatAge(age) }
  end
  -- The nudge: prices that did not come from the Companion say so, once, in a muted trailing
  -- line -- the tooltip is the only GoldCap surface a player sees without ever opening the AH
  -- tab, so this is where the largest audience learns the Companion exists. `origin` is
  -- GC.Data.OriginState()'s word for the save as a whole (an "app" player never sees this,
  -- whatever table answered for this one item), passed by the caller like `region` is, and
  -- allowlisted so a caller that does not know the origin nudges nobody.
  if (opts.origin == "none" or opts.origin == "manual")
      and (v.source == "bundled" or age > 48 * 3600) then
    lines[#lines + 1] = { kind = "hint", text = GC.L["Companion keeps prices fresh — /goldcap companion"] }
  end
  return lines
end

local function onTooltip(tooltip, data)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if not (GC.db and GC.db.settings and GC.db.settings.tooltip) then return end
  local link = data and (data.hyperlink or (data.guid and C_Item.GetItemLinkByGUID(data.guid)))
  if not link then return end
  local itemID = C_Item.GetItemInfoInstant(link)
  if not itemID then return end
  local lines = GC.Tooltip.BuildLines(GC.Data.GetItemValue(itemID), time(), {
    unitCost = GC.Acquisitions and GC.Acquisitions.UnitCostFor
      and GC.Acquisitions.UnitCostFor(itemID) or nil,
    region = GC.Data.Region and GC.Data.Region() or nil,
    origin = GC.Data.OriginState and GC.Data.OriginState() or nil,
  })
  if not lines then return end
  for _, ln in ipairs(lines) do
    if ln.kind == "money" then
      tooltip:AddDoubleLine(ln.label, GetCoinTextureString(ln.copper), 0.65, 0.82, 1, 1, 1, 1)
    elseif ln.kind == "hint" then
      tooltip:AddLine(ln.text, 0.55, 0.55, 0.55, true)
    else
      tooltip:AddDoubleLine(ln.left, ln.right, 0.65, 0.82, 1, 1, 1, 1)
    end
  end
end

-- Guarded so the file also loads under busted (no WoW globals there)
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
end
