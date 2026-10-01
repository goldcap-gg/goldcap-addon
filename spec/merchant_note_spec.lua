local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/MerchantNote.lua: the note beside the vendor window. The bag reads are shaped like the
-- client's: C_Container.GetContainerItemInfo's ContainerItemInfo carries exactly the fields below
-- (ContainerDocumentation.lua, identical in live 12.1.0 and forever 1.60.1.70124), and
-- C_Item.GetItemInfo's eleventh answer is the vendor price.
describe("vendor note", function()
  local GC, N, restore, saved, BAGS, VALUES, VENDOR, bagReads
  local KEYS = { "C_Container", "C_Item", "MerchantFrame", "GetCoinTextureString" }

  local function stack(itemID, count, extra)
    local info = { iconFileID = 134400, stackCount = count or 1, isLocked = false, quality = 1,
      isReadable = false, hasLoot = false, hyperlink = "|Hitem:" .. itemID .. "|h", isFiltered = false,
      hasNoValue = false, itemID = itemID, isBound = false, itemName = "Item " .. itemID }
    for k, v in pairs(extra or {}) do info[k] = v end
    return info
  end

  local function commodity(mv) return { mv = mv, ts = 0, source = "import", kind = "region_commodity" } end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    BAGS, VALUES, VENDOR, bagReads = {}, {}, {}, 0
    -- Strict: the note reads the bags and nothing else -- a sale, a pickup or a use would be an
    -- error here, not a silent no-op.
    _G.C_Container = setmetatable({
      GetContainerNumSlots = function(bag) bagReads = bagReads + 1; return BAGS[bag] and 4 or 0 end,
      GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] or nil end,
    }, { __index = function(_, name) error("the vendor note must not call C_Container." .. name) end })
    _G.C_Item = { GetItemInfo = function(id)
      return "Item " .. id, "|Hitem:" .. id .. "|h", 1, 1, 1, "Trade Goods", "", 20, "", 134400, VENDOR[id] or 0
    end }
    _G.GetCoinTextureString = function(c) return c .. "c" end
    _G.MerchantFrame = W.CreateFrame("Frame")
    _G.MerchantFrame:SetSize(336, 444)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("UI/Tooltip.lua", GC)
    helper.loadModule("UI/MerchantNote.lua", GC)
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    N = GC.MerchantNote
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  describe("the sentence", function()
    local cases = {
      { "several items, and what the auction house adds", { gainItems = 3, gain = 12345 },
        "3 items in your bags fetch more on the auction house (+12345c). Keep them for the AH." },
      { "one item", { gainItems = 1, gain = 500 },
        "1 item in your bags fetches more on the auction house (+500c). Keep it for the AH." },
      { "nothing that fetches more", { gainItems = 0, gain = 0 }, nil },
      { "items but no gain", { gainItems = 2, gain = 0 }, nil },
      { "a gain with no items", { gainItems = 0, gain = 100 }, nil },
      { "no totals at all", nil, nil },
    }
    for _, c in ipairs(cases) do
      it(c[1], function() assert.equal(c[3], N.Text(c[2])) end)
    end
  end)

  -- Which stacks count: Core/ForeverValue.lua's BagTotals, the rule Road to 40 and the Sold tab
  -- already use, fed the price each item's tooltip prints. One stack per case.
  describe("which bag items count", function()
    local cases = {
      { "the auction house after its cut beats the vendor", stack(11, 4), commodity(100), 50, 1, (95 - 50) * 4 },
      { "the auction house after its cut only matches the vendor", stack(12, 1), commodity(100), 95, 0, 0 },
      { "the vendor pays more", stack(13, 1), commodity(100), 96, 0, 0 },
      { "a bound stack cannot go to the auction house", stack(14, 1, { isBound = true }), commodity(1000), 10, 0, 0 },
      { "the vendor pays nothing for it", stack(15, 1, { hasNoValue = true }), commodity(1000), 10, 0, 0 },
      { "no vendor price known", stack(16, 1), commodity(1000), nil, 0, 0 },
      { "no auction house price", stack(17, 1), nil, 10, 0, 0 },
      { "an imported realm item: its region price, not its realm median",
        stack(18, 1), { mv = 9000000, ref = 20, ts = 0, source = "import", kind = "realm_item" }, 50, 0, 0 },
      { "WoW: Forever gear: its cheapest version's price",
        stack(19, 1), { mv = 600, ts = 0, source = "scan", gear = true }, 100, 1, 570 - 100 },
    }
    for _, c in ipairs(cases) do
      it(c[1], function()
        local id = c[2].itemID
        BAGS[0] = { c[2] }
        VALUES[id], VENDOR[id] = c[3], c[4]
        local t = GC.ForeverValue.RealBagTotals(N.ValueFor)
        assert.equal(c[5], t.gainItems)
        assert.equal(c[6], t.gain)
      end)
    end

    it("counts an item in two stacks once, and adds both stacks' gain", function()
      BAGS[0] = { stack(21, 2) }
      BAGS[1] = { nil, stack(21, 3) }
      VALUES[21], VENDOR[21] = commodity(100), 50
      local t = GC.ForeverValue.RealBagTotals(N.ValueFor)
      assert.equal(1, t.gainItems)
      assert.equal((95 - 50) * 5, t.gain)
    end)
  end)

  describe("beside the vendor window", function()
    local function note() return N._frame end

    it("opens with the vendor, beside it, as one box that holds the whole sentence", function()
      BAGS[0] = { stack(31, 4), stack(32, 1) }
      VALUES[31], VENDOR[31] = commodity(100), 50
      VALUES[32], VENDOR[32] = commodity(1000), 100
      N.OnMerchantShow()
      local f = note()
      assert.is_true(f:IsShown())
      assert.same({ "TOPLEFT", _G.MerchantFrame, "TOPRIGHT", 4, 0 }, { f:GetPoint(1) })
      assert.equal(_G.MerchantFrame, f:GetParent())
      assert.equal("GoldCap", f.title:GetText())
      assert.equal("2 items in your bags fetch more on the auction house (+" .. ((95 - 50) * 4 + (950 - 100))
        .. "c). Keep them for the AH.", f.body:GetText())
      -- Wrapped inside the box, and the box as tall as the wrapped text: nothing cut, nothing over.
      assert.is_true(W.state(f.body).wordWrap)
      assert.equal(220 - 20, f.body:GetWidth())
      assert.is_true(f.body:GetHeight() > W.LINE_H)
      assert.equal(10 + f.title:GetHeight() + 4 + f.body:GetHeight() + 10, f:GetHeight())
      assert.is_false(f:IsMouseEnabled())
    end)

    it("grows with a longer sentence", function()
      BAGS[0] = { stack(31, 1) }
      VALUES[31], VENDOR[31] = commodity(100), 50
      N.OnMerchantShow()
      local short = note():GetHeight()
      GC.L = setmetatable({}, { __index = function(_, key) return key .. " " .. string.rep("lang ", 40) end })
      N.Refresh()
      assert.is_true(note():GetHeight() > short)
    end)

    it("says nothing when nothing in the bags fetches more", function()
      BAGS[0] = { stack(33, 1) }
      VALUES[33], VENDOR[33] = commodity(100), 200
      N.OnMerchantShow()
      assert.is_true(note() == nil or not note():IsShown())
    end)

    it("follows the bags while the vendor is open, and goes when the last such item is sold", function()
      BAGS[0] = { stack(34, 2) }
      VALUES[34], VENDOR[34] = commodity(1000), 10
      N.OnMerchantShow()
      assert.is_true(note():IsShown())
      BAGS[0] = { stack(34, 1) }
      N.OnBagsChanged()
      assert.equal("1 item in your bags fetches more on the auction house (+940c). Keep it for the AH.",
        note().body:GetText())
      BAGS[0] = {}
      N.OnBagsChanged()
      assert.is_false(note():IsShown())
    end)

    it("closes with the vendor, and reads no bags while no vendor is open", function()
      BAGS[0] = { stack(35, 1) }
      VALUES[35], VENDOR[35] = commodity(1000), 10
      N.OnMerchantShow()
      N.OnMerchantClosed()
      assert.is_false(note():IsShown())
      local reads = bagReads
      N.OnBagsChanged()
      assert.equal(reads, bagReads)
      assert.is_false(note():IsShown())
    end)
  end)
end)
