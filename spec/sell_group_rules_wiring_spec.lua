local helper = require("spec.spec_helper")

-- Followed groups (plan 2026-10-22): SELL wired to the groups' rules, through the real Sell
-- services. GroupRules, SellRounds and the mail returns log are each optional: WoW: Forever loads
-- none of them, and an addon without the mail branch has no returns log at all.
describe("Sell tab with followed groups' rules", function()
  local GC

  local BAGS = { [0] = { { itemID = 10, stackCount = 5, itemName = "Herb" } } }

  local function services()
    _G.time = function() return 1000 end
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
      GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Herb" end }
    GC = {
      Sell = {},
      Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
        GetEntries = function() return {} end },
      Data = { GetItemValue = function() return { sold = 7447 } end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    helper.loadModule("Core/CancelQueue.lua", GC)
    for _, path in ipairs(helper.SELL_FILES) do helper.loadModule(path, GC) end
    GC.Acquisitions.Init({})
    return GC
  end

  after_each(function()
    _G.time = os.time
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil
  end)

  -- The mail branch (GC.MailReturns) keeps the returns log; SELL counts its expired lots as
  -- unsold rounds every time it composes. Without the mail module there are no returns.
  describe("the returns log", function()
    local function expired(itemID, at) return { itemID = itemID, count = 1, reason = "expired", at = at } end

    before_each(function()
      services()
      helper.loadModule("Core/SellRounds.lua", GC)
      GC.SellRounds.Init(GC.db)
    end)

    it("counts the returns the mail module hands out", function()
      GC.MailReturns = { Entries = function() return { expired(10, 900) } end }
      GC.SellCompose.Positions()
      assert.equal(1, GC.SellRounds.Rounds(10))
    end)

    it("reads the saved log when the mail module is not loaded", function()
      GC.db.mailReturns = { expired(10, 900) }
      GC.SellCompose.Positions()
      assert.equal(1, GC.SellRounds.Rounds(10))
    end)

    it("has no returns, and no error, without the mail module or its log", function()
      assert.is_nil(GC.MailReturns)
      assert.is_nil(GC.db.mailReturns)
      GC.SellCompose.Positions()
      assert.equal(0, GC.SellRounds.Rounds(10))
      assert.is_true(#GC.SellState.positions > 0)
    end)

    it("composes as before without SellRounds", function()
      GC.SellRounds = nil
      GC.MailReturns = { Entries = function() error("must not be read") end }
      GC.SellCompose.Positions()
      assert.is_true(#GC.SellState.positions > 0)
    end)
  end)
end)
