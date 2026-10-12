local _, GC = ...

-- The Items board in two sections (owner, 2026-10-12: the board called a 98%-off Ornate Mithril
-- Breastplate a deal, priced off what realms ASK, which ran 2 to 30 times what such items sold
-- for). goldcap.gg now counts realm item sales and splits realm items in two:
--
--   Flips       items that trade, priced at the median they sold for (the payload's F section).
--               The board's realm rows, found, priced and checked exactly as before.
--   Rare finds  items many realms list and few buy (U section). No price at all, so no profit,
--               no discount and no verdict: only where this realm's cheapest listing stands
--               among the other realms' and the sales goldcap.gg saw.
--
-- Pure: no WoW call. UI/SniperFrame.lua hands in what the realm poll saw and the data layer's
-- answers, and paints what comes back. The rows it builds carry a `kind` ("header", "empty",
-- "rare"); a flip row is the board's own deal table, which has none.
GC.ItemsBoard = {}

local STANDING_RANK = { min = 1, p10 = 2, p25 = 3 }

--- Where `unit` (copper, this realm's cheapest listing) stands among the realms that list the
--- item: "min" at or under the cheapest realm's cheapest listing, "p10" at or under the 10th
--- percentile, "p25" at or under the 25th; nil above that, which keeps the item off the board.
function GC.ItemsBoard.Standing(unit, facts)
  if type(unit) ~= "number" or unit <= 0 or type(facts) ~= "table" then return nil end
  if unit <= facts.floorMin then return "min" end
  if unit <= facts.floorP10 then return "p10" end
  if unit <= facts.floorP25 then return "p25" end
  return nil
end

function GC.ItemsBoard.StandingText(standing, realms)
  if standing == "min" then return (GC.L["Cheapest of %d realms"]):format(realms) end
  if standing == "p10" then return (GC.L["Among the cheapest 10%% of %d realms"]):format(realms) end
  if standing == "p25" then return (GC.L["Cheaper than 3 in 4 of %d realms"]):format(realms) end
  return nil
end

-- "3 days ago", "1 hour ago": whole days from a day on, whole hours under it.
local function agoText(hours)
  if hours >= 48 then return (GC.L["%d days ago"]):format(math.floor(hours / 24)) end
  if hours >= 24 then return GC.L["1 day ago"] end
  if hours >= 2 then return (GC.L["%d hours ago"]):format(hours) end
  if hours >= 1 then return GC.L["1 hour ago"] end
  return GC.L["less than an hour ago"]
end

--- The sales line of a rare find, from GC.Data.RareFacts: how many sold in 30 days and the last
--- one's price and age, or that none was seen.
function GC.ItemsBoard.SalesText(facts)
  local n = type(facts) == "table" and facts.sales30d or 0
  if not n or n <= 0 then return GC.L["No sale seen in 30 days"] end
  local sold = n == 1 and GC.L["Sold once in 30 days"] or (GC.L["Sold %d times in 30 days"]):format(n)
  if not (facts.lastSaleCopper and facts.lastSoldAgeHours) then return sold end
  return sold .. ", " .. (GC.L["last for %s %s"]):format(GC.Util.FormatMoney(facts.lastSaleCopper),
    agoText(facts.lastSoldAgeHours))
end

--- How often a flip sells, from GC.Data.FlipFacts.
function GC.ItemsBoard.FlipText(flip)
  if type(flip) ~= "table" or not flip.sales7d then return nil end
  return (GC.L["Sold %d times in 7 days on %d realms"]):format(flip.sales7d, flip.realms or 0)
end

--- The collection mark for GC.Collection.State's answer, or nil for none. Only "missing" and
--- "elsewhere" are marked: "collected", "unknown" and nil draw nothing.
function GC.ItemsBoard.MarkText(state, kind)
  if state == "elsewhere" then return GC.L["Appearance known"] end
  if state ~= "missing" then return nil end
  if kind == "recipe" then return GC.L["Not known by this character"] end
  if kind == "appearance" or kind == "pet" or kind == "toy" or kind == "mount" then
    return GC.L["Not collected"]
  end
  return nil
end

--- Folds one realm poll answer into `seen` (itemID -> { unit, qty }): what this realm's cheapest
--- listing of each rare find asks per unit. `rows` are the answer's browse rows, one per item
--- (Core/KeyPoll.lua collapses variants first); `asked` the ids the batch named, or nil. An asked
--- item the answer says nothing about has no listing left and leaves `seen`, exactly as a flip
--- row leaves the board. `isRare(itemID)` says which items are rare finds.
function GC.ItemsBoard.FoldSeen(seen, rows, asked, isRare)
  local answered = {}
  for i = 1, #(rows or {}) do
    local row = rows[i]
    local itemID = row.itemKey and row.itemKey.itemID
    if itemID and type(row.minPrice) == "number" and row.minPrice > 0 then
      answered[itemID] = true
      if isRare(itemID) then
        seen[itemID] = { unit = row.minPrice, qty = row.totalQuantity }
      end
    end
  end
  for i = 1, #(asked or {}) do
    if not answered[asked[i]] then seen[asked[i]] = nil end
  end
end

--- The Rare finds rows, in board order: every item in `seen` that is a rare find
--- (`factsFor(itemID)`, GC.Data.RareFacts) and asks at or under the 25th percentile of the
--- realms' cheapest listings. opts:
---   before(a, b)  the site's rank of two rare finds (GC.Data.RareBefore)
---   sort          the board's header sort, { key, desc } or nil. Only "unit" and "price" mean
---                 anything here: a rare find has no discount, profit or verdict to sort by.
---   skip          itemID -> true: rows held on screen (under the cursor), already drawn
--- Default order: by standing, the cheapest-of-all first, then the site's rank.
function GC.ItemsBoard.RareRows(seen, factsFor, opts)
  opts = opts or {}
  local skip = opts.skip or {}
  local list = {}
  for itemID, s in pairs(seen or {}) do
    local facts = not skip[itemID] and factsFor(itemID) or nil
    local standing = facts and GC.ItemsBoard.Standing(s.unit, facts)
    if standing then
      list[#list + 1] = { kind = "rare", itemID = itemID, unitPrice = s.unit, qty = s.qty or 1,
        standing = standing, facts = facts }
    end
  end
  local before = opts.before or function(a, b) return a < b end
  local function default(a, b)
    if a.standing ~= b.standing then return STANDING_RANK[a.standing] < STANDING_RANK[b.standing] end
    return before(a.itemID, b.itemID)
  end
  local sort = opts.sort
  if sort and (sort.key == "unit" or sort.key == "price") then
    table.sort(list, function(a, b)
      if a.unitPrice == b.unitPrice then return default(a, b) end
      if sort.desc then return a.unitPrice > b.unitPrice end
      return a.unitPrice < b.unitPrice
    end)
  else
    table.sort(list, default)
  end
  return list
end

--- The two lines under a rare find's name: where it stands, and its sales.
function GC.ItemsBoard.RareLines(row)
  return GC.ItemsBoard.StandingText(row.standing, row.facts.realms), GC.ItemsBoard.SalesText(row.facts)
end

function GC.ItemsBoard.SectionTitle(section)
  if section == "rares" then return GC.L["Rare finds"] end
  return GC.L["Flips"]
end

--- The Items board's list: a header over each section with its row count, then its rows, or one
--- short line when it has none. `flips` is the board's own list of realm rows, already in board
--- order; `rares` is RareRows' answer. opts:
---   rares   the payload carries rare finds (the site has switched). Without them there is no
---           Rare finds section at all, and a board with no flip rows either is returned as it
---           came -- empty -- so the board's own empty state explains it, as before.
---   keep    function(entry) -> whether the row stays (the "Only what I lack" filter), or nil
---   cap     the most rows a section shows
---   held    { flips = n, rares = n }: rows drawn on screen already (under the cursor, or under
---           an open Check) and so left out of the lists, but counted in their section
function GC.ItemsBoard.Sections(flips, rares, opts)
  opts = opts or {}
  local held = opts.held or {}
  if not opts.rares and #flips == 0 and (held.flips or 0) == 0 then return flips end
  local out = {}
  local inFlips = {}
  for i = 1, #flips do
    if flips[i].itemID then inFlips[flips[i].itemID] = true end
  end
  local function section(name, list, emptyText, heldCount)
    local kept, filtered = {}, false
    for i = 1, #list do
      local entry = list[i]
      if not opts.keep or opts.keep(entry) then
        kept[#kept + 1] = entry
      else
        filtered = true
      end
    end
    local shown = math.min(#kept, opts.cap or #kept)
    out[#out + 1] = { kind = "header", section = name, count = shown + heldCount }
    for i = 1, shown do out[#out + 1] = kept[i] end
    if shown + heldCount == 0 then
      out[#out + 1] = { kind = "empty", section = name,
        text = filtered and GC.L["Nothing here you lack"] or emptyText }
    end
  end
  section("flips", flips, GC.L["No flips on this realm right now"], held.flips or 0)
  if opts.rares then
    -- An item already on the board as a flip row (a cap row the player's own price put there)
    -- is not drawn a second time.
    local only = {}
    for i = 1, #(rares or {}) do
      if not inFlips[rares[i].itemID] then only[#only + 1] = rares[i] end
    end
    section("rares", only, GC.L["No rare finds on this realm right now"], held.rares or 0)
  end
  return out
end
