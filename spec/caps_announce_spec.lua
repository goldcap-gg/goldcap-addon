local helper = require("spec.spec_helper")

-- Live price caps, addon task 6: dedup for the "your price" board-ring (UI/SniperFrame.lua's
-- drainCapPings, fed from evaluateLiveCommodityDeal/evaluateLiveItemDeal). Pure module state,
-- deliberately separate from the caps table itself (Adopt() rebuilds caps/order wholesale on
-- every companion sync -- announcement memory must not reset with it, or the player would hear
-- the same lot ring again on the very next sync). A realm lot is a single resolved auction: once
-- announced, that exact auctionID never rings twice, however many drills see it again -- it is
-- the SAME opportunity, not a new one. A commodity has no single lot to key on, only a book, so
-- it rings again only when the price actually IMPROVES on the last one announced for that item.
describe("Caps.Announce", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
  end)

  describe("a realm deal (isCommodity false)", function()
    it("announces the first sighting of a lot", function()
      assert.is_true(GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 }))
    end)

    it("never announces the same auctionID twice", function()
      GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 })
      assert.is_false(GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 }))
    end)

    it("announces a different auctionID on the same item, even at a higher price", function()
      GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 })
      assert.is_true(GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 222, unitPrice = 900 }))
    end)

    it("is false with no auctionID at all", function()
      assert.is_false(GC.Caps.Announce({ itemID = 1, isCommodity = false, unitPrice = 500 }))
    end)
  end)

  describe("a commodity deal (isCommodity true)", function()
    it("announces the first sighting for an item", function()
      assert.is_true(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 }))
    end)

    it("does not re-announce the same unit price again", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      assert.is_false(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 }))
    end)

    it("does not announce a WORSE (higher) unit price than the last one announced", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      assert.is_false(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 450 }))
    end)

    it("announces again once the unit price actually improves", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      assert.is_true(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 350 }))
    end)

    it("announces again after Forget, even at the same or a worse price", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      GC.Caps.Forget(2)
      assert.is_true(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 }))
    end)

    it("keeps a different item's memory untouched by Forget", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      GC.Caps.Announce({ itemID = 3, isCommodity = true, unitPrice = 400 })
      GC.Caps.Forget(2)
      assert.is_true(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 }))
      assert.is_false(GC.Caps.Announce({ itemID = 3, isCommodity = true, unitPrice = 400 }))
    end)
  end)

  it("is false for a nil deal or one with no itemID", function()
    assert.is_false(GC.Caps.Announce(nil))
    assert.is_false(GC.Caps.Announce({ isCommodity = true, unitPrice = 400 }))
  end)

  -- Caps fixes 3e: the question without the commitment. The board queues a ring when a cap row
  -- is news and commits the memory only once the ring actually plays on a row the player can
  -- see -- asked and remembered in one call, a hit that landed on a hidden board or a closed
  -- window was spent for the whole visit.
  describe("IsNews", function()
    it("answers the same as Announce would, and remembers nothing", function()
      local lot = { itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 }
      assert.is_true(GC.Caps.IsNews(lot))
      assert.is_true(GC.Caps.IsNews(lot))
      assert.is_true(GC.Caps.Announce(lot))
      assert.is_false(GC.Caps.IsNews(lot))
    end)

    it("follows a commodity's price the way Announce does", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      assert.is_false(GC.Caps.IsNews({ itemID = 2, isCommodity = true, unitPrice = 400 }))
      assert.is_false(GC.Caps.IsNews({ itemID = 2, isCommodity = true, unitPrice = 450 }))
      assert.is_true(GC.Caps.IsNews({ itemID = 2, isCommodity = true, unitPrice = 350 }))
    end)

    it("is false for what Announce refuses outright", function()
      assert.is_false(GC.Caps.IsNews(nil))
      assert.is_false(GC.Caps.IsNews({ itemID = 1, isCommodity = false, unitPrice = 500 }))
    end)
  end)

  -- Final review I4: an Auction House session is the unit this memory belongs to, exactly as
  -- seenHotDeals is (UI/SniperFrame.lua's close handler clears them side by side). Without
  -- this, a lot announced in the morning stayed silenced for the rest of the login -- a fresh
  -- AH visit is a fresh judgment of what is worth flagging, and the auction that is STILL
  -- sitting there at the player's own price is the first thing the new session should say.
  describe("ForgetAll (the AH close)", function()
    it("lets a realm lot ring again in the next session", function()
      GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 })
      GC.Caps.ForgetAll()
      assert.is_true(GC.Caps.Announce({ itemID = 1, isCommodity = false, auctionID = 111, unitPrice = 500 }))
    end)

    it("lets a commodity ring again at the same price", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      GC.Caps.ForgetAll()
      assert.is_true(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 }))
    end)

    it("clears every item, not just the last one", function()
      GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 })
      GC.Caps.Announce({ itemID = 3, isCommodity = true, unitPrice = 400 })
      GC.Caps.ForgetAll()
      assert.is_true(GC.Caps.Announce({ itemID = 2, isCommodity = true, unitPrice = 400 }))
      assert.is_true(GC.Caps.Announce({ itemID = 3, isCommodity = true, unitPrice = 400 }))
    end)
  end)
end)
