local _, GC = ...

GC.Tooltip = {}

-- opts (optional): { unitCost = <copper per unit still held>, region = <"eu"|"kr"|...> }.
-- Both come from the caller rather than from `v` because neither belongs to the market
-- value: one is the player's own ledger, the other is which bundled table answered.
function GC.Tooltip.BuildLines(v, now, opts)
  if not v or not v.mv then return nil end
  opts = opts or {}
  local lines = { { kind = "money", label = "GoldCap value", copper = v.mv } }
  -- Import-path only: MarketData.lua's bundled entries never carry a trend (see
  -- ImportString.Parse and generateAddonData.ts). A flat 0% is not worth a line.
  if type(v.trend) == "number" and v.trend ~= 0 then
    lines[#lines + 1] = { kind = "text", left = "24h trend", right = string.format("%+d%%", v.trend) }
  end
  if v.sold then
    lines[#lines + 1] = { kind = "text", left = "Sold per day", right = string.format("%.1f", v.sold) }
  elseif v.listings then
    lines[#lines + 1] = { kind = "text", left = "Listings", right = tostring(v.listings) }
  end
  if opts.unitCost then
    lines[#lines + 1] = { kind = "money", label = "You paid", copper = opts.unitCost }
  end
  local age = now - (v.ts or 0)
  if v.source == "bundled" then
    -- Bundled data is stale by construction -- it was baked into the release -- and it is
    -- region-wide, not this realm's. Saying so is not optional.
    local label = opts.region and ("Bundled " .. string.upper(opts.region) .. " data") or "Bundled data"
    lines[#lines + 1] = { kind = "text", left = label, right = GC.Util.FormatAge(age) }
  elseif age > 48 * 3600 then
    lines[#lines + 1] = { kind = "text", left = "GoldCap data age", right = GC.Util.FormatAge(age) }
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
    region = GC.Data.GetStatus and GC.Data.GetStatus().region or nil,
  })
  if not lines then return end
  for _, ln in ipairs(lines) do
    if ln.kind == "money" then
      tooltip:AddDoubleLine(ln.label, GetCoinTextureString(ln.copper), 0.65, 0.82, 1, 1, 1, 1)
    else
      tooltip:AddDoubleLine(ln.left, ln.right, 0.65, 0.82, 1, 1, 1, 1)
    end
  end
end

-- Guarded so the file also loads under busted (no WoW globals there)
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
end
