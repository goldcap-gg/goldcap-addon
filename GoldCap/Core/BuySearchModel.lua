local _, GC = ...

-- The BUY tab's search of the auction house (UI/BuySearch.lua) as data: the rows a browse answer
-- is read into, their order, and the one request the search keeps out at a time. Pure and
-- driver-injected like Core/BookPass.lua: no WoW API call lives here, and no text.
--
-- The request rules are the addon's (docs/addon/AGENTS.md, "Sharing the search slot"): one browse
-- request out at a time, sent only when the throttle lets it, never while a purchase holds the
-- search (a gear bid is armed, a purchase is in flight), never over an unanswered keys batch --
-- that one is waited for a moment and then written off, the way the Sniper's Check does it -- with
-- a timeout and one way to give a request up, after which its late answer is swallowed for a while
-- instead of being read as the next request's. An answer is taken by what it says: nothing that
-- another browse request was sent after, and not the late answer of a written-off keys batch.
GC.BuySearchModel = {}
local M = GC.BuySearchModel

-- How long a sent request may go unanswered before it is given up.
M.TIMEOUT_SECONDS = 10
-- A keys batch out when the search could go is waited for this long, then written off: the
-- Sniper's own hold for a Check over a batch (LIM.CHECK_HOLD_SECONDS).
M.HOLD_SECONDS = 2
-- After a request was given up, its answer may still come: one browse answer in this window is
-- swallowed rather than read as anybody's, and nothing new is sent into it.
M.ORPHAN_SECONDS = 5

local function fold(s) return GC.NameMatch.Fold(s) end

-- "itemID:level:suffix:species", the identity of one browse row.
function M.KeyString(key)
  if type(key) ~= "table" then return "" end
  return table.concat({ key.itemID or 0, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0 }, ":")
end

-- How close a name is to what was typed: 0 the name itself, 1 it starts with it, 2 a word of it
-- does, 3 it holds every word somewhere, 4 anything else -- and a name not known yet.
function M.Relevance(name, query)
  local n, q = fold(name), fold(query)
  if n == "" or q == "" then return 4 end
  if n == q then return 0 end
  if n:sub(1, #q) == q then return 1 end
  if (" " .. n):find(" " .. q, 1, true) then return 2 end
  for word in q:gmatch("%S+") do
    if not n:find(word, 1, true) then return 4 end
  end
  return 3
end

-- One browse row ({ itemKey, totalQuantity, minPrice } -- BrowseResultInfo) as the search draws it,
-- with what the client says about its item key (ItemKeyInfo: itemName, quality, iconFileID,
-- isCommodity, isEquipment) or, before it knows, nothing: `known` false.
function M.Row(result, info)
  if type(result) ~= "table" or type(result.itemKey) ~= "table" or type(result.itemKey.itemID) ~= "number" then
    return nil
  end
  local key = result.itemKey
  local row = {
    itemKey = key, id = M.KeyString(key), itemID = key.itemID, itemLevel = key.itemLevel or 0,
    minPrice = tonumber(result.minPrice), available = tonumber(result.totalQuantity) or 0,
    known = false,
  }
  if type(info) == "table" and type(info.itemName) == "string" and info.itemName ~= "" then
    row.known = true
    row.name, row.quality, row.icon = info.itemName, info.quality, info.iconFileID
    row.commodity, row.equipment = info.isCommodity, info.isEquipment
  end
  return row
end

--- The rows of a browse answer, one per item key, in the client's order. `infoOf(itemKey)` is
--- the client's item key info, or nil while it does not have it.
function M.Rows(results, infoOf)
  local rows, seen = {}, {}
  for _, result in ipairs(results or {}) do
    local row = M.Row(result, type(result) == "table" and infoOf and infoOf(result.itemKey) or nil)
    if row and not seen[row.id] then
      seen[row.id] = true
      rows[#rows + 1] = row
    end
  end
  return rows
end

--- `rows` in the order the search shows them: the closest names first, the cheapest first among
--- those, then by name, the higher item level first, and by item. Sorted in place; returned.
function M.Sort(rows, query)
  for _, row in ipairs(rows) do row.rel = M.Relevance(row.name, query) end
  table.sort(rows, function(a, b)
    if a.rel ~= b.rel then return a.rel < b.rel end
    local pa, pb = a.minPrice or math.huge, b.minPrice or math.huge
    if pa ~= pb then return pa < pb end
    local na, nb = fold(a.name), fold(b.name)
    if na ~= nb then return na < nb end
    if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
    return a.id < b.id
  end)
  return rows
end

--- The rows of `itemID` the client had no name for, read again now that it says it has one
--- (ITEM_KEY_ITEM_INFO_RECEIVED). Answers whether any row changed.
function M.Fill(rows, itemID, infoOf)
  local changed = false
  for i, row in ipairs(rows or {}) do
    if not row.known and row.itemID == itemID then
      local filled = M.Row({ itemKey = row.itemKey, minPrice = row.minPrice, totalQuantity = row.available },
        infoOf and infoOf(row.itemKey) or nil)
      if filled and filled.known then
        rows[i] = filled
        changed = true
      end
    end
  end
  return changed
end

--- Whether an answer reads as one to `query`: some row's name is known, and every known name holds
--- every word typed. A row whose name is not known yet says nothing either way.
function M.ReadsAs(rows, query)
  local q = fold(query)
  if q == "" then return false end
  local any = false
  for _, row in ipairs(rows or {}) do
    if row.known then
      local n = fold(row.name)
      for word in q:gmatch("%S+") do
        if not n:find(word, 1, true) then return false end
      end
      any = true
    end
  end
  return any
end

-- `old` with every row of `new` it does not already hold appended: a page of more results, whether
-- the client hands back the whole list or only the new page.
local function merged(old, new)
  local out, seen = {}, {}
  for _, row in ipairs(old or {}) do
    out[#out + 1] = row
    seen[row.id] = true
  end
  for _, row in ipairs(new or {}) do
    if not seen[row.id] then
      out[#out + 1] = row
      seen[row.id] = true
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- The request
-- ---------------------------------------------------------------------------

local Request = {}
Request.__index = Request

--- A search's one request. `driver` answers what only the client and the rest of the addon know:
---   now()            seconds
---   ahOpen()         an auction house session to ask
---   purchaseBusy()   a purchase holds the search or is in flight (nothing is sent meanwhile)
---   keysOut()        a keys batch is unanswered; writeOffKeys() gives it up
---   ready()          the throttle takes a message now, claimed for this search
---   send(text)       the browse query for `text`; more() the next page of it
---   browseSeq()      how many browse-buffer requests anybody has sent (ours included)
---   results(), full() the browse buffer and whether it holds the whole answer
---   infoOf(itemKey)  the client's item key info, or nil
---   keysOrphan(results) whether those results are a written-off keys batch's late answer
--- state: "idle", "wait" (`reason`: "purchase", "batch", "answer", "throttle"), "out" (`kind`
--- "first" or "more"), "done" (`rows`, `full`) or "failed" (`failed`: "timeout", "dropped", "lost").
function M.NewRequest(driver)
  return setmetatable({ driver = driver, state = "idle" }, Request)
end

--- A search for `text` (with `qty`, what the player asked to buy). A request still out is not
--- answered for the new one: its answer is swallowed when it lands, and the new one goes then.
function Request:Submit(text, qty)
  self.query = { text = text, qty = qty or 1 }
  self.rows, self.full, self.failed = nil, false, nil
  if self.state == "out" then
    self.superseded = true
    return
  end
  self.state, self.kind, self.reason, self.holdSince = "wait", "first", nil, nil
  self:Step()
end

--- The next page of the answer on screen. Its browse list still has to be the one the client is
--- paging: once anybody has sent another browse request, the search starts over instead. Answers
--- whether it asked.
function Request:More()
  if self.state ~= "done" or self.full or not self.query then return false end
  if self.driver.browseSeq() ~= self.ownSeq then
    self:Submit(self.query.text, self.query.qty)
    return true
  end
  self.state, self.kind, self.reason, self.holdSince = "wait", "more", nil, nil
  self:Step()
  return true
end

--- The search is put away: a request still out is given up (its late answer swallowed), one
--- waiting goes nowhere.
function Request:Cancel()
  if self.state == "out" then
    self:GiveUp("cancelled")
  end
  self.state, self.query, self.rows, self.superseded = "idle", nil, nil, nil
end

--- The one way a request is given up: its wait ran out, the client dropped a message, or another
--- browse request took the buffer. Its answer may still come and is swallowed for
--- M.ORPHAN_SECONDS -- except after "lost", where the client answers the other request instead.
function Request:GiveUp(why)
  self.state, self.failed = "failed", why
  if why ~= "lost" then self.orphanUntil = self.driver.now() + M.ORPHAN_SECONDS end
  if self.superseded then
    self.superseded = nil
    self.state, self.kind, self.reason, self.failed, self.holdSince = "wait", "first", nil, nil, nil
  end
end

--- Moves the request on: a request out that has waited too long is given up; one waiting goes
--- as soon as nothing stands in its way. Called on submit and once a second.
function Request:Step()
  local d = self.driver
  local now = d.now()
  if self.orphanUntil and now >= self.orphanUntil then self.orphanUntil = nil end
  if self.state == "out" then
    if now - (self.sentAt or now) >= M.TIMEOUT_SECONDS then self:GiveUp("timeout") end
    if self.state ~= "wait" then return end
  end
  if self.state ~= "wait" then return end
  if not d.ahOpen() then
    self.state, self.reason = "idle", nil
    return
  end
  if d.purchaseBusy() then
    self.reason = "purchase"
    return
  end
  if self.orphanUntil then
    self.reason = "answer"
    return
  end
  if d.keysOut() then
    self.holdSince = self.holdSince or now
    if now - self.holdSince < M.HOLD_SECONDS then
      self.reason = "batch"
      return
    end
    d.writeOffKeys()
  end
  self.holdSince = nil
  if not d.ready() then
    self.reason = "throttle"
    return
  end
  if self.kind == "more" then d.more() else d.send(self.query.text) end
  self.sentSeq, self.sentAt, self.sentText, self.state, self.reason = d.browseSeq(), now, self.query.text, "out", nil
end

--- A browse answer (AUCTION_HOUSE_BROWSE_RESULTS_UPDATED or _ADDED). Answers whether it was this
--- search's -- its own answer, or the late one of a request it gave up -- so nobody else reads it.
function Request:OnBrowse()
  local d = self.driver
  if self.state ~= "out" then
    if self.orphanUntil and d.now() < self.orphanUntil and not d.keysOut() then
      self.orphanUntil = nil
      return true
    end
    return false
  end
  -- A keys batch out is that batch's answer (nothing of ours sends over one).
  if d.keysOut() then return false end
  -- Another browse request went after ours: the client answers that one, not this.
  if d.browseSeq() ~= self.sentSeq then
    self:GiveUp("lost")
    return false
  end
  local results = d.results()
  local rows = M.Rows(results, d.infoOf)
  -- A written-off keys batch answering late, naming only what it asked: not this answer, which is
  -- still coming. Unless the rows read as the search's own.
  if not M.ReadsAs(rows, self.sentText) and d.keysOrphan(results) then return true end
  if self.superseded then
    self.superseded = nil
    self.rows, self.state, self.kind, self.reason, self.holdSince = nil, "wait", "first", nil, nil
    self:Step()
    return true
  end
  if self.kind == "more" then rows = merged(self.rows, rows) end
  self.rows = M.Sort(rows, self.query.text)
  self.full = d.full() and true or false
  self.state, self.ownSeq = "done", self.sentSeq
  return true
end

--- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED: it names no message, and a request out may be the one
--- the client threw away.
function Request:OnDropped()
  if self.state == "out" then self:GiveUp("dropped") end
end

--- The client has a name for `itemID` now: rows waiting for it are read again, and the order with
--- them. Answers whether anything changed.
function Request:OnItemKeyInfo(itemID)
  if not (self.rows and M.Fill(self.rows, itemID, self.driver.infoOf)) then return false end
  M.Sort(self.rows, self.query and self.query.text or "")
  return true
end

--- The auction house closed: no answer is coming to anything.
function Request:OnClosed()
  self.state, self.query, self.rows, self.full, self.failed = "idle", nil, nil, false, nil
  self.orphanUntil, self.superseded, self.holdSince = nil, nil, nil
end

--- Whether the search holds the browse buffer: a request out, a late answer still owed to one
--- given up, or one about to go. Not while it waits for a keys batch to answer -- that wait is the
--- batch's own time. Everything else that writes the buffer stands down meanwhile.
function Request:Owns()
  if self.state == "out" then return true end
  if self.orphanUntil and self.driver.now() < self.orphanUntil then return true end
  return self.state == "wait" and self.reason ~= "batch"
end

--- Whether a request is out and unanswered: a per-item search of ours waits for it too.
function Request:Pending()
  return self.state == "out"
end
