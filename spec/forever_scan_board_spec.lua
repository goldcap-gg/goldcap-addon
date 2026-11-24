local helper = require("spec.spec_helper")

-- The seam from the Sniper's browse passes to the Deals board's live view: every pass the scanner
-- is told of reaches GC.ForeverDeals.OnBrowsePass first, whole or given up; none at Blackwater,
-- and none where there is no scanner (retail).
describe("ForeverScan browse passes to the Deals board", function()
  local GC, calls, now

  local function scanner(neutral)
    local store = {}
    local s = GC.ForeverScan.New({
      now = function() return now end,
      after = function() end,
      replicate = function() return false end,
      numRows = function() return 0 end,
      rowInfo = function() return nil end,
      isGear = function() return false end,
      startBrowse = function() return "started" end,
      store = function() return store end,
      passport = function() return { region = 90, realm = "Forever", faction = "Horde" } end,
      notify = function() end,
      neutral = function() return neutral end,
    })
    s:OnAuctionHouseShow()
    return s
  end

  before_each(function()
    now = 100000
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    calls = {}
    GC.ForeverDeals = { OnBrowsePass = function(book, whole) calls[#calls + 1] = { book, whole } end }
  end)

  local book = { [2589] = { floor = 60, qty = 5, kind = "classes" } }
  local cases = {
    { name = "a pass that ended is whole", fn = "OnBrowsePassDone", neutral = false, want = true },
    { name = "a pass given up is not", fn = "OnBrowsePassAbandoned", neutral = false, want = false },
    { name = "Blackwater's pass that ended reaches nothing", fn = "OnBrowsePassDone", neutral = true, want = nil },
    { name = "nor one given up there", fn = "OnBrowsePassAbandoned", neutral = true, want = nil },
  }
  for _, case in ipairs(cases) do
    it(case.name, function()
      GC.ForeverScan._scanner = scanner(case.neutral)
      GC.ForeverScan[case.fn](book)
      if case.want == nil then
        assert.equal(0, #calls)
      else
        assert.same({ { book, case.want } }, calls)
      end
    end)
  end

  it("reaches nothing without a scanner, as on retail", function()
    GC.ForeverScan._scanner = nil
    GC.ForeverScan.OnBrowsePassDone(book)
    GC.ForeverScan.OnBrowsePassAbandoned(book)
    assert.equal(0, #calls)
  end)
end)
