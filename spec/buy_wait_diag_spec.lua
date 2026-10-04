local helper = require("spec.spec_helper")

describe("BUY wait log", function()
  local GC, now, printed

  before_each(function()
    now = 100
    printed = {}
    _G.GetTime = function() return now end
    GC = { db = {} }
    GC.Print = function(msg) printed[#printed + 1] = msg end
    helper.loadModule("Core/BuyWaitDiag.lua", GC)
  end)

  after_each(function() _G.GetTime = nil end)

  it("records nothing until it is turned on", function()
    GC.BuyWaitDiag.Note("quote", "armed", "item=1")
    assert.is_nil(GC.db.buyWaitLog)
    GC.BuyWaitDiag.Slash("on")
    GC.BuyWaitDiag.Note("quote", "armed", "item=1")
    now = 112.5
    GC.BuyWaitDiag.Note("quote", "timed out", "item=1 after 12s")
    assert.same({ "100.00 quote armed item=1", "112.50 quote timed out item=1 after 12s" }, GC.db.buyWaitLog)
  end)

  it("keeps the log after off, empties it on clear, and caps its length", function()
    GC.BuyWaitDiag.Slash("on")
    for i = 1, GC.BuyWaitDiag.CAP + 20 do GC.BuyWaitDiag.Note("keys", "armed", tostring(i)) end
    assert.equal(GC.BuyWaitDiag.CAP, #GC.db.buyWaitLog)
    GC.BuyWaitDiag.Slash("off")
    GC.BuyWaitDiag.Note("keys", "armed", "late")
    assert.equal(GC.BuyWaitDiag.CAP, #GC.db.buyWaitLog)
    GC.BuyWaitDiag.Slash("clear")
    assert.same({}, GC.db.buyWaitLog)
  end)
end)
