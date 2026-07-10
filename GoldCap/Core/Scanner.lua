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
    if res then
      self.scanned = self.scanned + 1
      local deal = GC.DealMath.Evaluate(
        { itemID = itemID, isCommodity = false, auctionID = res.auctionID,
          unitPrice = res.unitPrice, qty = res.qty },
        driver.getValue(itemID), dealCfg)
      if deal and not alertedAuctions[res.auctionID] then
        alertedAuctions[res.auctionID] = true
        driver.onDeal(deal)
      end
    end
    advance()
  end

  function obj:OnCommodityResults(itemID)
    if itemID ~= pending then return end
    pending = nil
    local res = driver.commodityResult(itemID)
    if res then
      self.scanned = self.scanned + 1
      local deal = GC.DealMath.Evaluate(
        { itemID = itemID, isCommodity = true,
          unitPrice = res.unitPrice, qty = res.qty },
        driver.getValue(itemID), dealCfg)
      local lowest = alertedCommodity[itemID]
      if deal and (lowest == nil or res.unitPrice < lowest) then
        alertedCommodity[itemID] = res.unitPrice
        driver.onDeal(deal)
      end
    end
    advance()
  end

  return obj
end
