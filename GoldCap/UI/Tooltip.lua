local _, GC = ...

GC.Tooltip = {}

function GC.Tooltip.BuildLines(v, now)
  if not v or not v.mv then return nil end
  local lines = { { kind = "money", label = "GoldCap value", copper = v.mv } }
  if v.sold then
    lines[#lines + 1] = { kind = "text", left = "Sold per day", right = string.format("%.1f", v.sold) }
  elseif v.listings then
    lines[#lines + 1] = { kind = "text", left = "Listings", right = tostring(v.listings) }
  end
  local age = now - (v.ts or 0)
  if age > 48 * 3600 then
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
  local lines = GC.Tooltip.BuildLines(GC.Data.GetItemValue(itemID), time())
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
