local helper = require("spec.spec_helper")

-- Regression lock for the audit that found ACTION_HELP's Repost/"Cancel lot?" text describing
-- something onRepostClick does not do: the confirming click calls C_AuctionHouse.CancelAuction
-- and stops there. It does not relist. GC.Sell.OnOwnedAuctions notices the lot is gone and says
-- "Lot cancelled; wait for it to return to bags" -- cancelled items come back by MAIL, and the
-- player posts them again themselves once they do. These tooltip strings never rendered before
-- the button exposed the label they were keyed on, so nobody caught the lie until now.
describe("Sell action help text", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local GC

  before_each(function()
    GC = { Sell = {} }
    helper.loadModule("UI/SellFrame.lua", GC)
  end)

  local function helpBody(label)
    local renderRows = upvalue(GC.Sell.Attach, "renderRows")
    local createRow = upvalue(renderRows, "createRow")
    local actionHelp = upvalue(createRow, "ACTION_HELP")
    return table.concat(actionHelp[label][2], " ")
  end

  it("tells the truth about Repost's confirming click: cancel only, never an automatic relist", function()
    local repost = helpBody("Repost")
    assert.matches("does NOT relist", repost, 1, true)
    assert.matches("forfeit", repost, 1, true)
    assert.matches("mail", repost, 1, true)
    assert.is_nil(repost:find("lists it again at the current market price", 1, true))
  end)

  it("tells the truth about the Cancel lot? confirming click: cancel only, never an automatic relist", function()
    local cancel = helpBody("Cancel lot?")
    assert.matches("does not relist", cancel, 1, true)
    assert.matches("forfeit", cancel, 1, true)
    assert.matches("mail", cancel, 1, true)
    assert.is_nil(cancel:find("immediately relists it at the shown price", 1, true))
  end)

  -- Every other tooltip string audited against the code it describes (onPostClick, decoratePosition's
  -- market/profit fields, the 5% AH cut in Flips.lua's breakeven math): all matched. This is not
  -- exhaustive proof, just a sentinel that the two most load-bearing numeric claims stay intact.
  it("keeps the AH cut and breakeven claims consistent with Flips.lua's own math", function()
    local headerHelp = upvalue(GC.Sell.Attach, "HEADER_HELP")
    local profit = table.concat(headerHelp.profit[2], " ")
    assert.matches("5%", profit, 1, true)
    local status = table.concat(headerHelp.status[2], " ")
    assert.matches("Breakeven", status, 1, true)
  end)
end)
