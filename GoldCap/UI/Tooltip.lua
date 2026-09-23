local _, GC = ...

GC.Tooltip = {}

-- The same two boundaries the Sniper's own staleness banner uses (UI/SniperFrame.lua's
-- LIM.STALE_YELLOW_SECONDS / LIM.STALE_RED_SECONDS) and the Sold tab's red. The tooltip
-- used to keep a 48h threshold of its own, so data the rest of the addon was calling stale
-- in red still read as current here -- and a player who only ever mouses over items saw
-- nothing at all until the data was two days old.
local STALE_YELLOW_SECONDS = 6 * 3600
local STALE_RED_SECONDS = 24 * 3600

-- A count as a whole number grouped in thousands: "98,470", not "98470". The client's own
-- BreakUpLargeNumbers groups with the player's locale's separator (a German client writes
-- 98.470), so it is used wherever it exists; the plain comma grouping below is for a runtime
-- without it, which is the spec suite. The client hands a whole number under a thousand back
-- as a number, hence the tostring.
local function wholeCount(n)
  n = math.floor(n + 0.5)
  if BreakUpLargeNumbers then return tostring(BreakUpLargeNumbers(n)) end
  local text, found = tostring(n), 1
  while found > 0 do text, found = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
  return text
end

-- Sales a day. Under ten the decimal carries the decision -- 3.5 a day against 3 -- so it
-- stays; from ten up it is noise, and "29728.0" is the figure this replaced. Decided on the
-- rounded figure, so 9.96 prints "10" rather than "10.0".
local function perDay(n)
  local tenths = ("%.1f"):format(n)
  if tonumber(tenths) < 10 then return tenths end
  return wholeCount(n)
end

-- opts.live (optional): { floor, qty, age } -- what this session's own auction house browsing last
-- saw of the item (GC.Sniper.LiveFloor), inside LIM.LIVE_TOOLTIP_SECONDS. Its own line kind: the
-- floor is drawn as coins by onTooltip, which owns GetCoinTextureString, and the rest is text.
-- The age is clamped at zero: a clock that stepped back says "just now", never a negative minute.
local function liveLine(live)
  if type(live) ~= "table" or type(live.floor) ~= "number" or live.floor <= 0 then return nil end
  local qty = wholeCount(type(live.qty) == "number" and live.qty or 0)
  local minutes = math.floor(math.max(0, tonumber(live.age) or 0) / 60)
  local detail = minutes < 1 and (GC.L["%s listed · just now"]):format(qty)
    or (GC.L["%s listed · %d min ago"]):format(qty, minutes)
  return { kind = "live", left = GC.L["On the AH now"], copper = live.floor, detail = detail }
end

-- opts (optional): { unitCost = <copper per unit still held>, region = <"eu"|"kr"|...>,
-- origin = <GC.Data.OriginState()>, live = <see liveLine> }. They come from the caller rather
-- than from `v` because none belongs to the market value: the player's own ledger, which bundled
-- table answered, where the save's prices came from, and what the auction house showed this session.
function GC.Tooltip.BuildLines(v, now, opts)
  opts = opts or {}
  local live = liveLine(opts.live)
  if not v then return live and { live } or nil end
  local lines = {}
  -- An IMPORTED realm item's `mv` is this one realm's own median, and that is not a price:
  -- a realm item can sit at two listings for days, so a median of two is whatever the odd
  -- one out happens to be. Core/DealMath.lua and Core/Trigger.lua both refuse it for exactly
  -- that reason (their comments carry the measurement: two Leather Gauntlets of the Sun at
  -- 90,000 and 5.4 million made a "median" of 2.7 million), while this tooltip printed it as
  -- "GoldCap value" on the most-seen surface in the addon. The region reference from the
  -- import's T section is the figure everything else measures against, so it is the figure
  -- shown here -- labelled as the region's, with the item level it was measured on, because
  -- a reference for ilvl 623 says little about the ilvl 606 in front of the cursor. Where the
  -- region named no reference at all, the median is still shown, under a label that says
  -- exactly what it is and nothing beside it (see the branch below).
  --
  -- Bundled realm items are NOT affected: their `m` comes from item_region_snapshots, a
  -- region-wide median already (see apps/api/src/lib/addonMarketData.ts).
  local realmImport = v.kind == "realm_item" and v.source == "import"
  if realmImport then
    local ref = GC.Trigger and GC.Trigger.RealmReference and GC.Trigger.RealmReference(v) or nil
    if ref then
      local ilvl = type(v.refIlvl) == "number" and v.refIlvl > 0 and v.refIlvl or nil
      lines[1] = {
        kind = "money",
        label = ilvl and (GC.L["GoldCap region price (ilvl %d)"]):format(ilvl)
          or GC.L["GoldCap region price"],
        copper = ref,
      }
    else
      -- No region reference: the realm median is all there is. It is still shown -- a player
      -- looking at an item wants a figure -- but under its own name, so it is never read as
      -- the price the rest of the addon would trade on. Nothing else about the item is
      -- printed below: a median of two listings has no sale speed or depth to report, and a
      -- second number beside it would lend the first one authority it has not got.
      if not v.mv then return live and { live } or nil end
      lines[1] = { kind = "money", label = GC.L["GoldCap realm median (unverified)"], copper = v.mv }
    end
  else
    if not v.mv then return live and { live } or nil end
    lines[1] = { kind = "money", label = GC.L["GoldCap value"], copper = v.mv }
  end
  -- Trend, sale speed and depth belong to a REGION-wide measurement: the trend and sold
  -- fields ride commodity tokens (a realm item's I token carries neither -- see itemToken in
  -- packages/tsm), and the depth pair rides the verification token, which the server writes
  -- for commodities only. Skipped outright on the realm-item path so nothing there can imply
  -- a sale rate that was never measured.
  if not realmImport then
    -- Import-path only: MarketData.lua's bundled entries never carry a trend (see
    -- ImportString.Parse and generateAddonData.ts). A flat 0% is not worth a line.
    if type(v.trend) == "number" and v.trend ~= 0 then
      lines[#lines + 1] = { kind = "text", left = GC.L["24h trend"], right = string.format("%+d%%", v.trend) }
    end
    if v.sold then
      lines[#lines + 1] = { kind = "text", left = GC.L["Sold per day"], right = perDay(v.sold) }
    end
    -- Depth. `currentQty` (units on the region's shelf) and `listings` (auctions holding them)
    -- ride the import string's verification token -- so this is an imported-commodity line by
    -- construction: the bundled snapshot carries no verification at all. The shelf count is
    -- the better answer to the same question the auction count was answering, so it takes
    -- that slot rather than adding a fourth number.
    if v.currentQty and v.currentQty > 0 then
      local right = wholeCount(v.currentQty)
      local supply = GC.Util.FormatSupplyDays(v.currentQty, v.sold)
      if supply then right = right .. " · " .. supply end
      lines[#lines + 1] = { kind = "text", left = GC.L["Listed"], right = right }
    elseif v.listings and not v.sold then
      -- `not v.sold` keeps the exclusivity these two lines had when they were one if/elseif:
      -- no item has ever shown a sales rate and an auction count together.
      lines[#lines + 1] = { kind = "text", left = GC.L["Listings"], right = wholeCount(v.listings) }
    end
  end
  if live then lines[#lines + 1] = live end
  if opts.unitCost then
    lines[#lines + 1] = { kind = "money", label = GC.L["You paid"], copper = opts.unitCost }
  end
  -- Clamped like the live line's: data stamped ahead of this client's clock is new, not
  -- negatively old.
  local age = math.max(0, now - (v.ts or 0))
  if v.source == "bundled" then
    -- Bundled data is stale by construction -- it was baked into the release -- and it is
    -- region-wide, not this realm's. Saying so is not optional.
    -- A format, not concatenation: word order around the region code is the translator's
    -- to choose, and "Bundled %s data" is the only shape that lets them choose it.
    local label = opts.region and (GC.L["Bundled %s data"]):format(string.upper(opts.region))
      or GC.L["Bundled data"]
    lines[#lines + 1] = { kind = "text", left = label, right = GC.Util.FormatAge(age) }
  elseif age >= STALE_YELLOW_SECONDS then
    lines[#lines + 1] = { kind = "text", left = GC.L["GoldCap data age"], right = GC.Util.FormatAge(age) }
  end
  -- The nudge: prices that did not come from the Companion say so, once, in a muted trailing
  -- line -- the tooltip is the only GoldCap surface a player sees without ever opening the AH
  -- tab, so this is where the largest audience learns the Companion exists. `origin` is
  -- GC.Data.OriginState()'s word for the save as a whole (an "app" player never sees this,
  -- whatever table answered for this one item), passed by the caller like `region` is, and
  -- allowlisted so a caller that does not know the origin nudges nobody.
  if (opts.origin == "none" or opts.origin == "manual")
      and (v.source == "bundled" or age >= STALE_RED_SECONDS) then
    lines[#lines + 1] = { kind = "hint", text = GC.L["Companion keeps prices fresh — /goldcap companion"] }
  end
  return lines
end

local function onTooltip(tooltip, data)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if not (GC.db and GC.db.settings and GC.db.settings.tooltip) then return end
  -- Three ways a tooltip names its item, tried in that order. A hyperlink (or a bag item's
  -- guid) is the usual one -- but an AUCTION HOUSE item-group row, the browse list's single
  -- "Star Belt" standing for every listing of it, has neither: it is an item KEY, and this
  -- returned empty-handed on the one screen GoldCap exists for. The payload carries `id`
  -- there, which is the itemID and the right answer, since a group row is priced per item --
  -- exactly what GetItemValue is keyed on. GetItem() is the last resort, for a frame whose
  -- payload carries none of it.
  local link = data and (data.hyperlink or (data.guid and C_Item.GetItemLinkByGUID(data.guid)))
  local itemID = link and C_Item.GetItemInfoInstant(link) or nil
  if not itemID and data and type(data.id) == "number" then itemID = data.id end
  if not itemID and tooltip.GetItem then
    local _, shownLink = tooltip:GetItem()
    if shownLink then itemID = C_Item.GetItemInfoInstant(shownLink) end
  end
  if type(itemID) ~= "number" then return end
  -- The tooltip of a Sell row standing for one item level or one pet (UI/SellFrame.lua): the
  -- figure GetItemValue has is every item level's, or every pet's, and the row's panel says there
  -- is none for this one -- so this says the same, rather than print the merged one under it.
  -- Read off the tooltip's own owner, the row, and nothing else: a flag the Sell tab kept
  -- outlived a row hidden under the cursor, and every item tooltip after it lost its value.
  local owner = tooltip == GameTooltip and tooltip.GetOwner and tooltip:GetOwner() or nil
  local variant = type(owner) == "table" and owner.goldcapVariant or nil
  if variant then
    tooltip:AddLine(variant == "pet" and GC.L["no market figure for caged pets"]
      or GC.L["no market figure for this item level"], 0.55, 0.55, 0.55, true)
    return
  end
  local now = time()
  local lines = GC.Tooltip.BuildLines(GC.Data.GetItemValue(itemID), now, {
    unitCost = GC.Acquisitions and GC.Acquisitions.UnitCostFor
      and GC.Acquisitions.UnitCostFor(itemID) or nil,
    region = GC.Data.Region and GC.Data.Region() or nil,
    origin = GC.Data.OriginState and GC.Data.OriginState() or nil,
    live = GC.Sniper and GC.Sniper.LiveFloor and GC.Sniper.LiveFloor(itemID, now) or nil,
  })
  if not lines then return end
  for _, ln in ipairs(lines) do
    if ln.kind == "money" then
      tooltip:AddDoubleLine(ln.label, GetCoinTextureString(ln.copper), 0.65, 0.82, 1, 1, 1, 1)
    elseif ln.kind == "live" then
      tooltip:AddDoubleLine(ln.left, GetCoinTextureString(ln.copper) .. " · " .. ln.detail, 0.65, 0.82, 1, 1, 1, 1)
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
