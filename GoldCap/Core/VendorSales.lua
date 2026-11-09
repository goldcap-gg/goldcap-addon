local _, GC = ...

-- Sales to a merchant, on WoW: Forever. Until this file nothing in the addon learned that a stack
-- left the bags for a merchant, so a purchase sold to one (what DEALS' "Below vendor" buys exists
-- for, and what SELL holds back as `below_vendor`) kept its lot for good, and SELL listed it under
-- NOT ON HAND from then on. Loaded by GoldCap_Camelot.toc only, right after Core/VendorBuys.lua
-- (the purchases it mirrors); retail never has GC.VendorSales.
--
-- The evidence is the merchant's buyback list. Every way a stack is sold lands there (a right
-- click, a drag onto the window, Sell All Junk, another addon's sell button), and a hook on any one
-- of those calls would miss the others. The list holds the session's last V.PAGE sales, oldest
-- first and the newest last (Blizzard's MerchantFrame.lua shows its "last sold" button from
-- GetNumBuybackItems()), and a sale to a full page pushes its oldest off. A visit is read at the
-- door (OnShow), again on every change while the window is open (OnChanged: MERCHANT_UPDATE and
-- BAG_UPDATE_DELAYED, the two events the merchant window redraws its buyback page on), and settled
-- when it shuts (OnClosed):
--   - an entry that comes after the ones already there is a sale of this visit;
--   - an entry that goes missing was bought back, and takes the same stack's sale of this visit
--     with it (one sold in an earlier visit was settled then, and stays booked);
--   - the oldest entries leaving a page that is full again were pushed off, not bought back;
--   - a read while the merchant is shut says nothing, and is never "everything was bought back".
-- Each sale is booked once when the visit is settled: at the close, at the next door if the client
-- never said it closed, or at logout. It only reads: every sale and buyback is the player's click.
--
-- The page alone is not trusted to book anything: a sale is booked only for units that left the
-- bags during the visit (V.Corroborate). The bags are counted at the door and again on every change
-- while the window is open; what left is the count at the door less the last one, plus what this
-- merchant sold the player meanwhile (the lots Core/VendorBuys.lua booked). A page that fills only
-- after the door (the first read after a /reload can come back empty) or a stale one books nothing,
-- and a stack bought back put its units back.
--
-- Pure by construction like Core/VendorBuys.lua: the client is a driver --
--   open() -> whether the merchant window is up,
--   buyback() -> the page, oldest first, as { { itemID, link, quantity, price }, ... }, or nil when
--     some entry of it cannot be read (`price` is what the merchant paid for that stack),
--   bags() -> { [itemID] = units in the bags }, or nil when the bags cannot be read,
--   bought(itemID, since) -> units of the item this character bought from a merchant since `since`,
--   record({ itemID, link, quantity, price, at, seq }) -> books one sale.
GC.VendorSales = {}
local V = GC.VendorSales

-- BUYBACK_ITEMS_PER_PAGE in Blizzard's MerchantFrame.lua, on both games.
V.PAGE = 12

local driver, visit, lastSeen
local seq = 0

function V.SetDriver(value)
  driver = type(value) == "table" and value or nil
  visit, lastSeen = nil, nil
end

local function same(a, b)
  return a.itemID == b.itemID and a.link == b.link and a.quantity == b.quantity and a.price == b.price
end

--- Two reads of the buyback page, `before` and `after`, oldest first: the stacks sold since (in
--- the order they were sold) and the stacks bought back. `page` is how many the page holds.
function V.Diff(before, after, page)
  page = page or V.PAGE
  -- How much of the new page's head was already there, in order: new sales only ever come after it.
  local head, from = 0, 1
  for k = 1, #after do
    local found
    for m = from, #before do
      if same(before[m], after[k]) then found = m break end
    end
    if not found then break end
    head, from = k, found + 1
  end
  -- Matched from the newest end, so that of two equal stacks the one left over is the older: that
  -- is the one a full page pushes off.
  local matched, at = {}, #before
  for k = head, 1, -1 do
    while at >= 1 and not same(before[at], after[k]) do at = at - 1 end
    matched[at] = true
    at = at - 1
  end
  local sold, back = {}, {}
  for k = head + 1, #after do sold[#sold + 1] = after[k] end
  local first
  for m = 1, #before do
    if matched[m] then first = m break end
  end
  -- A page full again lost its oldest to the sales, one for each sale at most; anything else that
  -- went missing was bought back.
  local pushed = #after >= page and #sold or 0
  for m = 1, #before do
    if not matched[m] then
      if pushed > 0 and (first == nil or m < first) then pushed = pushed - 1
      else back[#back + 1] = before[m] end
    end
  end
  return sold, back
end

--- A visit's sales, as the bags bear them out: `shown` and `now` are the bag counts at the door and
--- at the last read, `bought` what a merchant sold the player meanwhile, each { [itemID] = units }.
--- The sales that may be booked, in order, each cut to the units still unaccounted for and paid its
--- share of the price; an item the bags did not lose books nothing. Pure.
function V.Corroborate(sales, shown, now, bought)
  local left, out = {}, {}
  for _, sale in ipairs(sales) do
    local id = sale.itemID
    if left[id] == nil then left[id] = math.max(0, (shown[id] or 0) - (now[id] or 0) + (bought[id] or 0)) end
    local units = math.min(sale.quantity, left[id])
    if units > 0 then
      left[id] = left[id] - units
      out[#out + 1] = { itemID = id, link = sale.link, quantity = units, at = sale.at,
        price = units == sale.quantity and sale.price or math.floor(sale.price * units / sale.quantity) }
    end
  end
  return out
end

local function settle()
  local done = visit
  visit = nil
  if not (done and driver) then return end
  local bought = {}
  for _, sale in ipairs(done.sold) do
    if bought[sale.itemID] == nil then
      local ok, units = pcall(driver.bought, sale.itemID, done.at)
      bought[sale.itemID] = ok and type(units) == "number" and units or 0
    end
  end
  -- Each on its own: a booking that fails costs the visit no other sale.
  for _, sale in ipairs(V.Corroborate(done.sold, done.shown, done.counts, bought)) do
    seq = seq + 1
    sale.seq = seq
    pcall(driver.record, sale)
  end
end

local function readBags()
  local ok, counts = pcall(driver.bags)
  return ok and type(counts) == "table" and counts or nil
end

--- MERCHANT_SHOW: the page as it stands at the door is what this visit did not sell.
function V.OnShow(now)
  settle()
  if not driver or type(now) ~= "number" then return end
  local page, bags = driver.buyback(), readBags()
  -- Without the page or the bags at the door this visit books nothing.
  if type(page) ~= "table" or not bags then return end
  -- The page cannot empty itself away from a merchant: read empty at the door after the last visit
  -- left stacks on it, the client has not handed it over yet, and the last one stands.
  if #page == 0 and lastSeen and #lastSeen > 0 then page = lastSeen end
  visit = { last = page, sold = {}, at = now, shown = bags, counts = bags }
  lastSeen = page
end

--- MERCHANT_UPDATE and BAG_UPDATE_DELAYED while the window is open: what was sold or bought back
--- since the last read.
function V.OnChanged(now)
  if not (visit and driver) or type(now) ~= "number" or not driver.open() then return end
  visit.counts = readBags() or visit.counts
  local page = driver.buyback()
  if type(page) ~= "table" then return end
  local sold, back = V.Diff(visit.last, page, V.PAGE)
  for _, entry in ipairs(back) do
    for i = #visit.sold, 1, -1 do
      if same(visit.sold[i], entry) then table.remove(visit.sold, i) break end
    end
  end
  for _, entry in ipairs(sold) do
    visit.sold[#visit.sold + 1] = { itemID = entry.itemID, link = entry.link, quantity = entry.quantity,
      price = entry.price, at = now }
  end
  visit.last, lastSeen = page, page
end

--- MERCHANT_CLOSED and PLAYER_LOGOUT: what this visit sold is booked.
function V.OnClosed()
  settle()
end

local function positiveInteger(n)
  return type(n) == "number" and n == math.floor(n) and n > 0 and n < 2 ^ 53
end

--- The merchant's buyback page, oldest first. GetNumBuybackItems, GetBuybackItemInfo and
--- GetBuybackItemLink are the calls Blizzard's own MerchantFrame.lua draws the Buyback tab with on
--- both games; C_MerchantFrame.GetBuybackItemID is documented on both. A page with any entry that
--- cannot be read whole is no page: nil, and the read says nothing.
function V.ReadBuyback()
  local ask, info = GC.Util.Ask, _G.GetBuybackItemInfo
  if type(info) ~= "function" then return nil end
  local count = ask(_G.GetNumBuybackItems)
  if type(count) ~= "number" or count < 0 then return nil end
  local page = {}
  for i = 1, count do
    local ok, _, _, price, quantity = pcall(info, i)
    local link = ask(_G.GetBuybackItemLink, i)
    local itemID = C_MerchantFrame and ask(C_MerchantFrame.GetBuybackItemID, i)
    if not positiveInteger(itemID) and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
    if not ok or not positiveInteger(itemID) or not positiveInteger(quantity) or type(price) ~= "number"
        or price < 0 or price ~= math.floor(price) then
      return nil
    end
    page[i] = { itemID = itemID, link = type(link) == "string" and link or nil, quantity = quantity, price = price }
  end
  return page
end

--- Units of each item in the bags GoldCap counts (GC.ForeverValue.BAGS: the backpack, four bags
--- and the reagent bag), through C_Container on both games; nil when the client cannot be asked.
function V.ReadBags()
  local c = _G.C_Container
  if not (c and type(c.GetContainerNumSlots) == "function" and type(c.GetContainerItemInfo) == "function") then
    return nil
  end
  local counts = {}
  for _, bag in ipairs(GC.ForeverValue and GC.ForeverValue.BAGS or { 0, 1, 2, 3, 4, 5 }) do
    local ok, slots = pcall(c.GetContainerNumSlots, bag)
    for slot = 1, ok and tonumber(slots) or 0 do
      local okInfo, info = pcall(c.GetContainerItemInfo, bag, slot)
      if okInfo and type(info) == "table" and positiveInteger(info.itemID) and positiveInteger(info.stackCount) then
        counts[info.itemID] = (counts[info.itemID] or 0) + info.stackCount
      end
    end
  end
  return counts
end

-- Wires the module to the client. Called once, when the database is ready.
function V.Install()
  V.SetDriver({
    -- The window, as the Sell to vendor card reads it (UI/VendorSellCard.lua); a visit is open
    -- only between OnShow and OnClosed besides.
    open = function()
      local frame = _G.MerchantFrame
      return not (type(frame) == "table" and frame.IsShown and not frame:IsShown())
    end,
    buyback = V.ReadBuyback,
    bags = V.ReadBags,
    -- The merchant purchases Core/VendorBuys.lua booked as lots for this character: a reagent bought
    -- and sold back in one visit left the bags as units that came in during it.
    bought = function(itemID, since)
      local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
      if not (context and GC.Acquisitions and GC.Acquisitions.GetAll) then return 0 end
      local units = 0
      for _, batch in ipairs(GC.Acquisitions.GetAll()) do
        if batch.source == "vendor" and batch.itemID == itemID and batch.character == context.char
            and batch.region == context.region and type(batch.acquiredAt) == "number" and batch.acquiredAt >= since
            and positiveInteger(batch.originalQty) then
          units = units + batch.originalQty
        end
      end
      return units
    end,
    record = function(sale)
      if not (GC.Acquisitions and GC.Acquisitions.RecordVendorSale) then return end
      local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
      if not context then return end
      -- The key SELL files a stack of this link under, read off the link alone (the stack is the
      -- merchant's now, in no bag slot); nil for a link it cannot read, and then no version is spent.
      local key
      if GC.Sell and GC.Sell._SlotKey then
        local ok, value = pcall(GC.Sell._SlotKey, sale.itemID, sale.link)
        key = ok and type(value) == "string" and value or nil
      end
      GC.Acquisitions.RecordVendorSale({ itemID = sale.itemID, quantity = sale.quantity, proceeds = sale.price,
        at = sale.at, seq = sale.seq, char = context.char, region = context.region, positionKey = key })
    end,
  })
end
