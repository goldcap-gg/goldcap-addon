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

  local function advance()
    if not running or pending then return end
    if not driver.isReady() then return end
    -- The slot arbiter's veto. Checked HERE rather than at each call site because advance() is
    -- reached three ways -- a readiness event, the tail of a result handler, and Resume() --
    -- and the result tail is the one that would otherwise chain send after send straight past
    -- the arbiter. An absent mayScan means "no arbiter", which is what every other caller and
    -- every older spec expects.
    if driver.mayScan and not driver.mayScan() then return end
    local n = #list
    if n == 0 then return end
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
          return
        end
        waitingKey[id] = true
      end
    end
    driver.onStatus("waiting for item info")
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
    return running and pending == nil and #list > 0
  end

  function obj:OnSystemReady()
    if pending and driver.now() - pendingSince > STALE_SECONDS then
      pending = nil
    end
    advance()
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
    if not driver.mayScan then advance() end
  end

  function obj:OnCommodityResults(itemID)
    if itemID ~= pending then return end
    pending = nil
    local res = driver.commodityResult(itemID)
    local deal
    if res then
      self.scanned = self.scanned + 1
      deal = GC.DealMath.Evaluate(
        { itemID = itemID, isCommodity = true,
          unitPrice = res.unitPrice, qty = res.qty, avail = res.avail },
        driver.getValue(itemID), dealCfg)
      local lowest = alertedCommodity[itemID]
      if deal and (lowest == nil or res.unitPrice < lowest) then
        alertedCommodity[itemID] = res.unitPrice
        driver.onDeal(deal)
      end
    end
    if driver.onObservation then driver.onObservation(itemID, deal) end
    if not driver.mayScan then advance() end
  end

  return obj
end
