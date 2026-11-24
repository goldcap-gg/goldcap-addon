local helper = require("spec.spec_helper")

-- A piece of gear bought on DEALS was filed under its item level alone, "item:4562:10:0:0", while
-- SELL keys the same axe in the bags and on the player's own lot by its whole ItemKey,
-- "item:4562:10:14302:0": MY LOTS showed "Severing Axe of the Bear" with no cost and a SET COST
-- button (owner's WoW: Forever save, 2026-11-24). The purchase key now comes from the lot's own
-- search result, and a batch filed under the bare key before finds its key once.
describe("DEALS purchase key", function()
  local GC, itemKeyFromItem, level

  before_each(function()
    level = 0
    _G.C_Item = {
      GetDetailedItemLevelInfo = function() return level end,
      IsItemDataCached = function() return true end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_AuctionHouse = { GetItemKeyFromItem = function() return itemKeyFromItem end }
    GC = { Sell = {}, Theme = { color = {}, pad = {} } }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadSell(GC)
  end)

  after_each(function() _G.C_Item, _G.ItemLocation, _G.C_AuctionHouse = nil, nil, nil end)

  -- One item search result, as C_AuctionHouse.GetItemSearchResultInfo answers it, and the lot
  -- DEALS reads off it (UI/SniperFrame.lua's driver.itemLots).
  local function lotOf(info)
    return { auctionID = info.auctionID, buyout = info.buyoutAmount, quantity = 1,
      itemLevel = info.itemKey.itemLevel or 0, itemSuffix = info.itemKey.itemSuffix or 0,
      battlePetSpeciesID = info.itemKey.battlePetSpeciesID or 0 }
  end

  -- The key the batch is filed under once DEALS bought the candidate a verdict named
  -- (planDialogPrimaryClick's purchaseDeal.itemKey, then GC.Acquisitions.RecordGoldCap).
  local function purchaseKey(itemID, decision)
    return GC.Acquisitions.PositionKey(itemID, GC.Acquisitions.LotItemKey(itemID, decision.candidate), false)
  end

  local cases = {
    { name = "WoW: Forever gear with a random suffix", itemID = 4562, level = 10,
      key = { itemID = 4562, itemLevel = 10, itemSuffix = 14302, battlePetSpeciesID = 0 },
      bagLink = "|cff1eff00|Hitem:4562:0:0:0:0:0:14302:0:0:0:0:0:0|h[Severing Axe of the Bear]|h|r",
      want = "item:4562:10:14302:0" },
    { name = "retail gear with bonus IDs and no suffix", itemID = 212395, level = 0,
      key = { itemID = 212395, itemLevel = 623, itemSuffix = 0, battlePetSpeciesID = 0 },
      bagLink = "|cffa335ee|Hitem:212395::::::::80:::::2:6652:1520|h[Spellweaver's Gloves]|h|r",
      want = "item:212395:623:0:0" },
    { name = "a retail caged pet", itemID = 82800, level = 0,
      key = { itemID = 82800, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 1387 },
      bagLink = "|cff0070dd|Hbattlepet:1387:25:3:1546:276:276:0000000000000000|h[Lil' Ragnaros]|h|r",
      want = "item:82800:25:0:1387" },
  }

  for _, case in ipairs(cases) do
    it("files " .. case.name .. " under the key SELL keys it by in the bags and on its lot", function()
      level, itemKeyFromItem = case.level, case.key
      local info = { auctionID = 77, buyoutAmount = 295, quantity = 1, itemKey = case.key,
        itemLink = case.bagLink }
      local lots = { lotOf(info) }
      local bagKey = GC.Sell._SlotKey(case.itemID, case.bagLink, 0, 1)
      local ownedLots = GC.SellPositions.NormalizeOwnedLots({ { auctionID = 9, itemKey = case.key,
        itemLink = case.bagLink, quantity = 1, buyoutAmount = 500, isCommodity = false } }, 100)

      assert.equal(case.want, bagKey)
      assert.equal(case.want, ownedLots[1].positionKey)
      -- Every verdict that names a realm lot: YOUR PRICE, the region reference, a vendor ceiling.
      assert.equal(case.want, purchaseKey(case.itemID, GC.Caps.DecideRealm({ c = 1000, l = 0 }, lots)))
      assert.equal(case.want, purchaseKey(case.itemID, GC.SniperDecision.EvaluateRealm(lots, 100000, 0,
        { minimumProfitCopper = 1, minimumRoi = 0.01 })))
      assert.equal(case.want, purchaseKey(case.itemID, GC.SniperDecision.EvaluateCeilingLot({ kind = "vendor",
        ceilingUnit = 1000, exitUnit = 2000, lots = lots, minimumProfit = 1 })))
    end)
  end
end)

describe("GC.Acquisitions.RepairSuffixKeys", function()
  local GC, db
  local scope = { char = "Hitfm", region = "EU" }
  local AXE, KRIS = "Severing Axe of the Bear", "Deadly Kris of the Sorcerer"

  local function batch(id, positionKey, itemName, fields)
    local itemID = tonumber(positionKey:match("^item:(%d+)"))
    local out = { id = id, source = "goldcap", itemID = itemID, positionKey = positionKey, itemName = itemName,
      originalQty = 1, originalTotal = 295, remainingQty = 1, remainingTotal = 295, acquiredAt = 1,
      character = scope.char, region = scope.region, sniperEvidenceKey = "snipe\1" .. itemID,
      mailEvidenceKey = "mail:" .. itemID, evidenceKeys = {}, consumedEvidenceKeys = {} }
    for k, v in pairs(fields or {}) do out[k] = v end
    return out
  end

  before_each(function()
    GC = {}
    helper.loadModule("Core/Acquisitions.lua", GC)
    db = { acquisitions = {
      batch("acq:185", "item:4562:10:0:0", AXE),
      batch("acq:136", "item:15243:36:0:0", KRIS, { originalTotal = 7800, remainingTotal = 7800 }),
    } }
    assert.is_true(GC.Acquisitions.Init(db))
  end)

  local function keyOf(id)
    for _, b in ipairs(db.acquisitions) do if b.id == id then return b.positionKey end end
  end

  local cases = {
    { name = "moves the owner's axe and kris to the one held or listed key that carries their name",
      seen = { { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE },
        { itemID = 15243, positionKey = "item:15243:36:2046:0", itemName = KRIS } },
      want = { ["acq:185"] = "item:4562:10:14302:0", ["acq:136"] = "item:15243:36:2046:0" }, moved = 2 },
    { name = "leaves a batch alone when two suffixed keys carry its name",
      seen = { { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE },
        { itemID = 4562, positionKey = "item:4562:10:14303:0", itemName = AXE } },
      want = { ["acq:185"] = "item:4562:10:0:0" }, moved = 0 },
    { name = "leaves a batch alone when the suffixed piece is another one",
      seen = { { itemID = 4562, positionKey = "item:4562:10:1018:0", itemName = "Severing Axe of the Eagle" } },
      want = { ["acq:185"] = "item:4562:10:0:0" }, moved = 0 },
    { name = "never moves a batch to another item level",
      seen = { { itemID = 4562, positionKey = "item:4562:12:14302:0", itemName = AXE } },
      want = { ["acq:185"] = "item:4562:10:0:0" }, moved = 0 },
    { name = "counts the stacks of one key as one",
      seen = { { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE },
        { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE } },
      want = { ["acq:185"] = "item:4562:10:14302:0" }, moved = 1 },
  }

  for _, case in ipairs(cases) do
    it(case.name, function()
      assert.equal(case.moved, GC.Acquisitions.RepairSuffixKeys(case.seen, scope))
      for id, key in pairs(case.want) do assert.equal(key, keyOf(id)) end
    end)
  end

  it("leaves a batch that DEALS did not buy alone", function()
    db.acquisitions[1].sniperEvidenceKey = nil
    GC.Acquisitions.RepairSuffixKeys({ { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE } }, scope)
    assert.equal("item:4562:10:0:0", keyOf("acq:185"))
  end)

  it("leaves a batch of another character alone, and one already sold", function()
    db.acquisitions[2].remainingQty = 0
    local seen = { { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE },
      { itemID = 15243, positionKey = "item:15243:36:2046:0", itemName = KRIS } }
    assert.equal(0, GC.Acquisitions.RepairSuffixKeys(seen, { char = "Alt", region = "EU" }))
    assert.equal(1, GC.Acquisitions.RepairSuffixKeys(seen, scope))
    assert.equal("item:15243:36:0:0", keyOf("acq:136"))
  end)

  it("weighs a batch once: a decision made is not made again", function()
    local two = { { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE },
      { itemID = 4562, positionKey = "item:4562:10:14303:0", itemName = AXE } }
    GC.Acquisitions.RepairSuffixKeys(two, scope)
    GC.Acquisitions.RepairSuffixKeys({ two[1] }, scope)
    assert.equal("item:4562:10:0:0", keyOf("acq:185"))
  end)

  -- A piece of another name is no answer: the axe may still be in the bank, or listed and not
  -- read yet. Weighed again, it moves once the axe is in sight.
  it("does not give up on a batch when only a piece of another name is in sight", function()
    local eagle = { itemID = 4562, positionKey = "item:4562:10:1018:0", itemName = "Severing Axe of the Eagle" }
    GC.Acquisitions.RepairSuffixKeys({ eagle }, scope)
    assert.equal(1, GC.Acquisitions.RepairSuffixKeys({ eagle,
      { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE } }, scope))
    assert.equal("item:4562:10:14302:0", keyOf("acq:185"))
  end)

  -- Not decided yet, so not marked: the piece may be the one SELL cannot key or name yet, or be
  -- in the bank, out of sight.
  it("waits while the item has stock SELL cannot key, a lot with no name yet, or nothing in sight", function()
    local axe = { itemID = 4562, positionKey = "item:4562:10:14302:0", itemName = AXE }
    GC.Acquisitions.RepairSuffixKeys({ axe, { itemID = 4562 } }, scope)
    GC.Acquisitions.RepairSuffixKeys({ axe, { itemID = 4562, positionKey = "item:4562:10:14303:0" } }, scope)
    GC.Acquisitions.RepairSuffixKeys({}, scope)
    assert.equal("item:4562:10:0:0", keyOf("acq:185"))
    assert.equal(1, GC.Acquisitions.RepairSuffixKeys({ axe }, scope))
    assert.equal("item:4562:10:14302:0", keyOf("acq:185"))
  end)
end)
