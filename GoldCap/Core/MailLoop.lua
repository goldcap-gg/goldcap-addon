local _, GC = ...

-- The Collect button's take loop: a state machine that decides, one step at a time, which single
-- mailbox action comes next. It names no WoW global: the mailbox, the bag count, the clock and
-- the ledger arrive through `deps`, and UI/MailCollect.lua owns the only real calls (and the timer
-- that drives Step).
--
-- Pacing and order follow Blizzard's own Open All (Blizzard_MailFrame/MailFrame.lua,
-- OpenAllMailMixin): a take, then 0.15 s and until C_Mail.IsCommandPending() is false before the
-- next one; the run is wrapped in C_Mail.SetOpeningAll; money first, then the items from the last
-- slot down. Postal paces the same way.
--
-- Indices move: an emptied auction mail is deleted by the server and every later row shifts, and
-- Blizzard's MailFrame refreshes the inbox by itself in the middle of a run (MailFrame.lua,
-- InboxFrame_Update), which brings rows in at the back and new mail in at the front. So no index
-- survives between steps. Every step reads the inbox again and acts on the first takeable row it
-- finds, and a take is confirmed by the mail it was made on (Core/MailClassify.lua's Identity):
-- the take landed when fewer rows than before carry that mail's identity. One case stays open: a
-- refresh that brings in a mail identical to the one just taken, in the same step, hides the take,
-- which then counts as stuck.
--
-- deps:
--   api          GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo, GetInboxItem (read by
--                Core/MailClassify.lua), TakeInboxMoney(i), TakeInboxItem(i, slot), CheckInbox(),
--                CanCheckInbox() -> canCheck, seconds, IsCommandPending(), SetOpeningAll(flag),
--                FreeBagSlots() -> integer
--   patterns     Core/MailClassify.lua's Patterns(...)
--   enabled()    the four group switches, read fresh at every step
--   scanLedger() a synchronous ledger scan of the inbox
--   epoch()      wall clock seconds for the returns log (the `now` of Step is the pacing clock,
--                which is session time and would not survive a /reload in the log); defaults to
--                the clock of Step
--   errors       { full = ERR_INV_FULL, unique = ERR_ITEM_MAX_COUNT }

GC.MailLoop = {}

local DELAY = 0.15
local STUCK_STEPS = 3
local MAX_REFRESHES = 10
-- How long one CheckInbox may go unanswered before the run ends. The answer normally comes within
-- a second; without a limit a lost one left the button reading Stop with SetOpeningAll still on.
local REFRESH_TIMEOUT = 10

GC.MailLoop.DELAY = DELAY
GC.MailLoop.STUCK_STEPS = STUCK_STEPS
GC.MailLoop.MAX_REFRESHES = MAX_REFRESHES
GC.MailLoop.REFRESH_TIMEOUT = REFRESH_TIMEOUT

local GROUP_FIELD = { sales = "sales", returns = "returns", purchases = "purchases", players = "players" }

local function newResult()
  return { reason = nil, gold = 0, sales = 0, returns = 0, purchases = 0, players = 0, loading = 0, itemsLeft = 0 }
end

function GC.MailLoop.New(deps)
  local loop = {}
  local api = deps.api
  local errors = deps.errors or {}

  local state = "idle"
  local result = newResult()
  local skipItems, skipKeys = {}, {}
  local inflight
  -- The mails this run has taken from, by the identity each has now: a mail counts once however
  -- many takes it needs, and a take of a mail already worked on continues it.
  local letters = {}
  local nextAt = 0
  local invFull = false
  local refreshes = 0
  -- { shown, total } where the shown mail ran out. Blizzard's MailFrame asks for the rest by
  -- itself (MailFrame.lua, MailFrame_RefreshInbox), often before this loop may, so the wait ends
  -- as soon as the inbox no longer reads like this, whoever asked.
  local baseline
  local awaiting      -- { at } while this loop's own CheckInbox is out
  local waitSeconds

  local function shownAndTotal()
    local ok, shown, total = pcall(api.GetInboxNumItems)
    if not ok or type(shown) ~= "number" then return 0, 0 end
    return shown, type(total) == "number" and total or shown
  end

  local function finish(reason)
    if state == "idle" or state == "done" then return end
    state = "done"
    result.reason = reason
    inflight, awaiting, waitSeconds, baseline = nil, nil, nil, nil
    api.SetOpeningAll(false)
  end

  local function inboxMoved()
    if not baseline then return false end
    local shown, total = shownAndTotal()
    return shown ~= baseline.shown or total ~= baseline.total
  end

  local function resume()
    state, awaiting, waitSeconds, baseline = "running", nil, nil, nil
  end

  -- A take that did nothing: its lot's returns entry goes, unless another stack of that lot was
  -- taken (the lot did come back).
  local function retract(flight)
    local lot = flight and flight.slot and flight.letter.returns[flight.itemID]
    if lot and not lot.taken then
      GC.MailReturns.Retract(lot.entry)
      flight.letter.returns[flight.itemID] = nil
    end
  end

  -- How many shown rows carry this identity now.
  local function rowsLike(identity)
    local shown = shownAndTotal()
    local n = 0
    for index = 1, shown do
      if GC.MailClassify.IdentityAt(api, index) == identity then n = n + 1 end
    end
    return n
  end

  -- Did the take in flight land? The mail it was made on no longer reads as it did: its gold or
  -- that slot is gone, or the mail itself is. Where it sits now does not matter.
  local function confirmed(flight)
    return rowsLike(flight.identity) < flight.likeBefore
  end

  local function tally(flight)
    if flight.kind == "sale" and flight.amount then result.gold = result.gold + flight.amount end
    local letter = flight.letter
    if not letter.counted then
      letter.counted = true
      local field = GROUP_FIELD[flight.group]
      result[field] = result[field] + 1
    end
    local lot = flight.slot and letter.returns[flight.itemID]
    if lot then lot.taken = true end
    -- From here on the mail reads as the take left it.
    if letters[flight.identity] == letter then letters[flight.identity] = nil end
    letters[flight.after] = letter
  end

  -- One pass over the inbox. Returns the action to take, or nil plus what the pass saw.
  local function pass()
    local shown, total = shownAndTotal()
    local enabled = deps.enabled()
    local bagsOpen = not invFull and api.FreeBagSlots() > 0
    local loading, blocked = 0, 0
    local action
    for index = 1, shown do
      local mail = GC.MailClassify.Read(api, index, deps.patterns)
      if not mail then
        loading = loading + 1
      else
        local decision = GC.MailClassify.Decide(mail, enabled)
        if decision.skip == "loading" then
          loading = loading + 1
        elseif decision.take and not action then
          if mail.money > 0 and not skipKeys[mail.key] then
            action = { index = index, kind = decision.kind, group = decision.group, amount = mail.money,
              key = mail.key, mail = mail }
          else
            local pick, left = nil, 0
            for _, item in ipairs(mail.items) do
              if not skipItems[item.itemID] then
                left = left + 1
                if not pick or item.slot > pick.slot then pick = item end
              end
            end
            if pick and bagsOpen then
              action = { index = index, slot = pick.slot, kind = decision.kind, group = decision.group,
                itemID = pick.itemID, count = pick.count, key = mail.key, mail = mail }
            elseif pick then
              blocked = blocked + left
            end
          end
        elseif decision.take then
          -- Further takeable mail behind the action chosen: only blocked item mail matters.
          if not bagsOpen then
            for _, item in ipairs(mail.items) do
              if not skipItems[item.itemID] then blocked = blocked + 1 end
            end
          end
        end
      end
    end
    return action, { shown = shown, total = total, loading = loading, blocked = blocked }
  end

  local function perform(action, now)
    if action.kind == "sale" or action.kind == "purchase" then
      deps.scanLedger()
    end
    local mail = action.mail
    action.identity = mail.identity
    action.after = GC.MailClassify.IdentityAfter(mail, action.slot)
    action.likeBefore = rowsLike(action.identity)
    local letter = letters[action.identity] or { returns = {} }
    letters[action.identity] = letter
    action.letter = letter
    -- A lot that came back is one mail, in as many stacks as the auction house split it into. It is
    -- logged once, before its first stack is taken, with the count of all its stacks: SELL's unsold
    -- rounds go up by one per lot.
    if action.slot and (action.kind == "expired" or action.kind == "cancelled")
        and not letter.returns[action.itemID] then
      local count = 0
      for _, item in ipairs(mail.attachments) do
        if item.itemID == action.itemID then count = count + item.count end
      end
      local at = deps.epoch and deps.epoch() or now
      letter.returns[action.itemID] = { entry = GC.MailReturns.Record(action.itemID, count, action.kind, at) }
    end
    action.steps = 0
    inflight = action
    nextAt = now + DELAY
    if action.slot then api.TakeInboxItem(action.index, action.slot) else api.TakeInboxMoney(action.index) end
  end

  -- Nothing to take from what is shown: more mail than shown, bags, or the end.
  local function conclude(seen, now)
    result.loading = seen.loading
    if seen.blocked > 0 then
      result.itemsLeft = seen.blocked
      finish("bags")
      return "done"
    end
    if seen.total > seen.shown then
      if refreshes >= MAX_REFRESHES then finish("done"); return "done" end
      local canCheck, seconds = api.CanCheckInbox()
      state = "refresh"
      baseline = { shown = seen.shown, total = seen.total }
      if canCheck then
        refreshes = refreshes + 1
        awaiting = { at = now }
        waitSeconds = nil
        api.CheckInbox()
      else
        awaiting = nil
        waitSeconds = type(seconds) == "number" and math.ceil(seconds) or nil
      end
      return "refresh"
    end
    finish("done")
    return "done"
  end

  local function act(now)
    local action, seen = pass()
    if action then
      result.loading = seen.loading
      perform(action, now)
      return "took"
    end
    return conclude(seen, now)
  end

  function loop:Start(now)
    if state == "running" or state == "refresh" then return false end
    if api.IsCommandPending() then return false end
    local takeable = GC.MailClassify.Count(api, deps.patterns, deps.enabled())
    if takeable == 0 then return false end
    result = newResult()
    skipItems, skipKeys, inflight, letters = {}, {}, nil, {}
    invFull, refreshes, awaiting, waitSeconds, baseline, nextAt = false, 0, nil, nil, nil, 0
    state = "running"
    api.SetOpeningAll(true)
    deps.scanLedger()
    act(now)
    return true
  end

  function loop:Step(now)
    if state == "refresh" then
      if inboxMoved() then
        resume()
      elseif awaiting then
        if now - awaiting.at < REFRESH_TIMEOUT then return "refresh" end
        finish("done")
        return "done"
      else
        local canCheck, seconds = api.CanCheckInbox()
        if canCheck then
          refreshes = refreshes + 1
          awaiting = { at = now }
          waitSeconds = nil
          api.CheckInbox()
        else
          waitSeconds = type(seconds) == "number" and math.ceil(seconds) or nil
        end
        return "refresh"
      end
    end
    if state ~= "running" then return "done" end
    if now < nextAt or api.IsCommandPending() then return "wait" end
    if inflight then
      local flight = inflight
      if confirmed(flight) then
        inflight = nil
        tally(flight)
      else
        flight.steps = flight.steps + 1
        if flight.steps < STUCK_STEPS then
          nextAt = now + DELAY
          return "wait"
        end
        -- A take that did nothing: leave that item (or that gold) for this visit.
        inflight = nil
        if flight.slot then skipItems[flight.itemID] = true else skipKeys[flight.key] = true end
        retract(flight)
      end
    end
    return act(now)
  end

  function loop:Stop(reason) finish(reason or "stopped") end
  function loop:OnClosed() finish("closed") end

  -- MAIL_FAILED carries the itemID of the item the client refused.
  function loop:OnMailFailed(itemID)
    if state ~= "running" and state ~= "refresh" then return end
    if itemID ~= nil then skipItems[itemID] = true end
    if inflight and inflight.slot then
      retract(inflight)
      inflight = nil
    end
  end

  -- UI_ERROR_MESSAGE carries the client's message text.
  function loop:OnUiError(message)
    if state ~= "running" or message == nil then return end
    if message == errors.full then
      invFull = true
      if inflight and inflight.slot then
        retract(inflight)
        inflight = nil
      end
    elseif message == errors.unique and inflight and inflight.slot then
      skipItems[inflight.itemID] = true
      retract(inflight)
      inflight = nil
    end
  end

  function loop:OnInboxUpdate()
    if state ~= "refresh" then return end
    if inboxMoved() then
      resume()
    elseif awaiting then
      -- This loop's own refresh came back with nothing new.
      finish("done")
    end
  end

  function loop:State() return state end
  function loop:WaitSeconds() return waitSeconds end
  function loop:Result() return result end

  return loop
end

-- The sentence for the chat and the tooltip.
function GC.MailLoop.Summary(result)
  local parts = {}
  if result.sales > 0 then
    if result.sales == 1 then
      parts[#parts + 1] = (GC.L["Collected %s from 1 sale"]):format(GC.Util.CoinText(result.gold))
    else
      parts[#parts + 1] = (GC.L["Collected %s from %d sales"]):format(GC.Util.CoinText(result.gold), result.sales)
    end
  end
  if result.returns == 1 then parts[#parts + 1] = GC.L["1 lot came back"]
  elseif result.returns > 1 then parts[#parts + 1] = (GC.L["%d lots came back"]):format(result.returns) end
  if result.purchases == 1 then parts[#parts + 1] = GC.L["1 purchase"]
  elseif result.purchases > 1 then parts[#parts + 1] = (GC.L["%d purchases"]):format(result.purchases) end
  if result.players == 1 then parts[#parts + 1] = GC.L["1 other mail"]
  elseif result.players > 1 then parts[#parts + 1] = (GC.L["%d other mails"]):format(result.players) end

  local text = #parts > 0 and (table.concat(parts, ", ") .. ".") or nil
  local sentences = { text }
  if (result.loading or 0) > 0 then
    sentences[#sentences + 1] = (GC.L["%d still loading"]):format(result.loading) .. "."
  end
  if result.reason == "bags" then
    sentences[#sentences + 1] = GC.L["The bags are full, the rest stays in the mailbox"] .. "."
  end
  if #sentences == 0 then return GC.L["Nothing to collect"] .. "." end
  return table.concat(sentences, " ")
end
