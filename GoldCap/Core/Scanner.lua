local _, GC = ...

GC.Scanner = {}

local STALE_SECONDS = 10

function GC.Scanner.New(driver, dealCfg)
  local obj = {
    scanned = 0,
    cycles = 0,
  }
  local list, index = {}, 0
  local running = false
  local pending, pendingSince = nil, 0
  local waitingKey = {}
  local alertedAuctions = {}   -- auctionID -> true
  local alertedCommodity = {}  -- itemID -> lowest alerted unitPrice

  -- Returns whether a search actually went out. The arbiter hands this loop a slot and then
  -- reports the slot as spent -- and every path below that sends nothing (nothing running, a
  -- query still pending, an empty set, or a whole list whose item keys the client has not
  -- cached yet) used to be reported as a send all the same, so the turn was lost and the verify
  -- walk behind it went hungry for a query that was never made.
  local function advance()
    if not running or pending then return false end
    if not driver.isReady() then return false end
    -- The slot arbiter's veto. Checked HERE rather than at each call site because advance() is
    -- reached three ways -- a readiness event, the tail of a result handler, and Resume() --
    -- and the result tail is the one that would otherwise chain send after send straight past
    -- the arbiter. An absent mayScan means "no arbiter", which is what every other caller and
    -- every older spec expects.
    if driver.mayScan and not driver.mayScan() then return false end
    local n = #list
    if n == 0 then return false end
    for _ = 1, n do
      index = index % n + 1
      if index == 1 then obj.cycles = obj.cycles + 1 end
      local id = list[index]
      if not waitingKey[id] then
        local info = driver.getKeyInfo(id)
        if info then
          pending, pendingSince = id, driver.now()
          driver.sendSearch(id)
          driver.onStatus(("scanning %d/%d"):format(index, n))
          return true
        end
        waitingKey[id] = true
      end
    end
    driver.onStatus("waiting for item info")
    return false
  end

  function obj:Start(watchlist)
    list = watchlist or {}
    index, pending = 0, nil
    waitingKey = {}
    alertedAuctions, alertedCommodity = {}, {}
    self.scanned, self.cycles = 0, 0
    running = true
    if #list == 0 then
      driver.onStatus("empty watchlist")
      running = false
      return
    end
    advance()
  end

  function obj:Stop()
    running = false
    pending = nil
    driver.onStatus("stopped")
  end

  function obj:Resume()
    if running then return end
    if #list == 0 then
      driver.onStatus("empty watchlist")
      return
    end
    running = true
    advance()
  end

  -- Whether this scanner would send if it were handed a slot right now. The arbiter needs to
  -- know that WITHOUT granting one, so an even split does not hand turns to a loop with
  -- nothing to do (and so a slot is never left idle when only one consumer is hungry).
  function obj:Wants()
    if not running or #list == 0 then return false end
    -- A pending query that has outlived STALE_SECONDS is not a query any more, it is a lost
    -- one. Reporting "not hungry" here is what made OnSystemReady's own stale-recovery
    -- unreachable: the arbiter only ever calls it when Wants() is true, so a single dropped
    -- result used to wedge the loop for the rest of the session.
    if pending and (driver.now() - pendingSince) <= STALE_SECONDS then return false end
    return true
  end

  -- Whether a search of this loop's is on the wire and still worth waiting for -- the same "not
  -- lost yet" test Wants() makes. UI/SniperFrame.lua sends no keys batch while it is: a batch
  -- sent on top of an unanswered search takes the answer with it (caps fixes 4a, round 2).
  function obj:Awaiting()
    return pending ~= nil and (driver.now() - pendingSince) <= STALE_SECONDS
  end

  -- Hands the caller advance()'s own answer: the slot arbiter grants this loop a turn through
  -- here, and a turn that produced no send belongs to whoever is next in line.
  function obj:OnSystemReady()
    if pending and driver.now() - pendingSince > STALE_SECONDS then
      pending = nil
    end
    return advance()
  end

  function obj:OnKeyInfo(itemID)
    if waitingKey[itemID] then
      waitingKey[itemID] = nil
      advance()
    end
  end

  function obj:OnItemResults(itemID)
    if itemID ~= pending then return end
    pending = nil
    local res = driver.itemResult(itemID)
    local deal
    if res then
      self.scanned = self.scanned + 1
      deal = GC.DealMath.Evaluate(
        { itemID = itemID, isCommodity = false, auctionID = res.auctionID,
          unitPrice = res.unitPrice, qty = res.qty },
        driver.getValue(itemID), dealCfg)
      if deal and not alertedAuctions[res.auctionID] then
        alertedAuctions[res.auctionID] = true
        driver.onDeal(deal)
      end
    end
    if driver.onObservation then driver.onObservation(itemID, deal) end
    advance()
  end

  function obj:OnCommodityResults(itemID)
    if itemID ~= pending then return end
    pending = nil
    local res = driver.commodityResult(itemID)
    local value = driver.getValue(itemID)
    local deal
    if res then
      -- A price back at or above market means the cheap lot that earned the last alert is
      -- gone. Forget the floor: without this the ratchet only ever descends, so after the
      -- first cheap lot is bought the next one has to beat a price nobody is asking any more,
      -- and an hour of watching one item goes completely silent. Runs whether or not this
      -- observation is itself a deal -- at market it will not be one, and that is the case
      -- that matters.
      if value and value.mv and res.unitPrice >= value.mv then
        alertedCommodity[itemID] = nil
      end
      self.scanned = self.scanned + 1
      deal = GC.DealMath.Evaluate(
        { itemID = itemID, isCommodity = true,
          unitPrice = res.unitPrice, qty = res.qty, avail = res.avail },
        value, dealCfg)
      local lowest = alertedCommodity[itemID]
      if deal and (lowest == nil or res.unitPrice < lowest) then
        alertedCommodity[itemID] = res.unitPrice
        driver.onDeal(deal)
      end
    end
    if driver.onObservation then driver.onObservation(itemID, deal) end
    advance()
  end

  return obj
end
