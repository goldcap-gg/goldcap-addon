local helper = require("spec.spec_helper")

-- Followed groups on WoW: Forever's Deals board. The board is the player's own scan's rows alone,
-- so a group is not polled for there (Core/Caps.lua holds no caps on Forever): a scan row of an
-- item in a group the player follows carries the group's name, and a commodity of the group listed
-- under the group's price is a row of its own, measured against the group's usual price.
describe("ForeverDeals, followed groups", function()
  local GC, D, vendor, commodity

  -- Two levels: 30 at 10c, 20 at 20c. Two prices are under the thin-market guard's three, so
  -- "Under market" never makes a row of it; only the group can.
  local BOOK = "10,100,50,;0x30 10x20|0,10,2"

  local function ctx(over)
    local c = {
      vendorFor = function(id) return vendor[id] end,
      isCommodity = function(id) return commodity[id] end,
      depositFor = function() return 0 end,
      minimumProfit = 20,
      watchPins = {},
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
  end

  local function fold(items) return { at = 5000, items = items } end

  local function followed(name, price, usual)
    return function(itemID) if itemID == 1 then return name, price, usual end end
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("Core/GroupRules.lua", GC)
    helper.loadModule("Core/ForeverDeals.lua", GC)
    D = GC.ForeverDeals
    vendor, commodity = {}, { [1] = true }
  end)

  describe("Build", function()
    it("lists no row for a book the market guards turn away", function()
      assert.equal(0, #D.Build(fold({ [1] = BOOK }), ctx()))
    end)

    it("makes a row of a followed commodity under the group's price, measured at the usual price", function()
      local rows = D.Build(fold({ [1] = BOOK }), ctx({ groupFor = followed("Herbs", 40, 100) }))
      assert.equal(1, #rows)
      local r = rows[1]
      assert.same({ "market", "group", 100, 40, "Herbs", true, 50, 700 },
        { r.forever, r.refSource, r.refUnit, r.ceiling, r.capGroup, r.capFollowed, r.qty, r.capTotal })
      assert.equal("commodities", r.board)
      -- Resold at the usual price after the 5% cut: 50 x 100 = 5000, less 250 and the 700 it cost.
      assert.equal(4050, r.profit)
    end)

    it("holds the group's price to a resale that pays, as retail's cap rows are", function()
      -- The group asks 98c a unit but the usual price is 100c: 5% off 100 is 95, so 94 is the most.
      local rows = D.Build(fold({ [1] = "90,100,50,;0x30 4x20|0,4,2" }), ctx({ groupFor = followed("Herbs", 98, 100) }))
      assert.equal(1, #rows)
      assert.equal(94, rows[1].ceiling)
      assert.equal(0, #D.Build(fold({ [1] = "95,100,50,;0x30 4x20|0,4,2" }),
        ctx({ groupFor = followed("Herbs", 98, 100) })))
    end)

    it("lists nothing over the group's price, without a usual price, or for an item that is no commodity", function()
      assert.equal(0, #D.Build(fold({ [1] = BOOK }), ctx({ groupFor = followed("Herbs", 5, 100) })))
      assert.equal(0, #D.Build(fold({ [1] = BOOK }), ctx({ groupFor = followed("Herbs", 40, nil) })))
      commodity[1] = false
      assert.equal(0, #D.Build(fold({ [1] = BOOK }), ctx({ groupFor = followed("Herbs", 40, 100) })))
    end)

    it("marks a vendor row of a followed item, and keeps it a vendor row while a vendor pays more", function()
      -- A vendor pays 96c: 50 units make 4100c there, against 4050c resold at the group's 1s.
      vendor[1] = 96
      local rows = D.Build(fold({ [1] = BOOK }), ctx({ groupFor = followed("Herbs", 40, 100) }))
      assert.equal(1, #rows)
      assert.same({ "vendor", "Herbs", true, nil }, { rows[1].forever, rows[1].capGroup, rows[1].capFollowed,
        rows[1].refSource })
    end)

    it("is the group's row when its resale pays more than a vendor does", function()
      -- A vendor pays 50c: 1800c there, 4050c resold.
      vendor[1] = 50
      local rows = D.Build(fold({ [1] = BOOK }), ctx({ groupFor = followed("Herbs", 40, 100) }))
      assert.equal(1, #rows)
      assert.same({ "market", "Herbs", true, "group" }, { rows[1].forever, rows[1].capGroup, rows[1].capFollowed,
        rows[1].refSource })
      assert.equal(4050, rows[1].profit)
    end)

    it("marks nothing without a followed group", function()
      vendor[1] = 50
      local r = D.Build(fold({ [1] = BOOK }), ctx())[1]
      assert.is_nil(r.capGroup)
      assert.is_nil(r.capFollowed)
    end)
  end)

  describe("Rows", function()
    local saved, groupsFile

    before_each(function()
      saved = fold({ [1] = BOOK })
      GC.ForeverScan = { Enabled = function() return true end, Fold = function() return saved end }
      GC.db = { settings = { sniper = { watchPins = {} } }, commodityByItem = { [1] = true } }
      GC.ForeverValue = { VendorUnit = function() return nil end, CommodityDeposit = function() return 0 end }
      _G.C_Item = { RequestLoadItemDataByID = function() end }
      groupsFile = { v = 3, groups = { "Herbs" }, caps = { { i = 1, c = 40, g = 1, u = 100, r = 1, k = 1 } },
        rules = { { n = "Herbs", p = "gather", d = 24 } } }
    end)

    after_each(function() _G.C_Item = nil end)

    it("builds the group's row from the rules the Companion wrote", function()
      GC.GroupRules.Adopt(groupsFile)
      local rows = D.Rows(1000)
      assert.equal(1, #rows)
      assert.same({ "Herbs", "group" }, { rows[1].capGroup, rows[1].refSource })
    end)

    it("rebuilds when a group is followed or let go, though the scan did not change", function()
      assert.equal(0, #D.Rows(1000))
      assert.is_false(D.Due(1001))
      GC.GroupRules.Adopt(groupsFile)
      assert.is_true(D.Due(1001))
      assert.equal(1, #D.Rows(1001))
      assert.is_false(D.Due(1002))
      GC.GroupRules.Adopt({ v = 3, groups = {}, caps = {}, rules = {} })
      assert.is_true(D.Due(1003))
      assert.equal(0, #D.Rows(1003))
    end)
  end)
end)
