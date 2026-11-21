local helper = require("spec.spec_helper")
local ThemeShape = require("spec.support.theme_shape")

-- A part-sold lot, end to end: C_AuctionHouse.GetOwnedAuctions() -> GC.Sell.OnOwnedAuctions ->
-- NormalizeOwnedLots -> SellPositions.Build -> the MY LOTS count and its rows. The roster is the
-- owner's own read (WoW: Forever, 2026-11-21): after a partial sale ONE auctionID comes back as
-- TWO rows, the sold part (status Sold, its quantity, the sale's total in buyoutAmount) and the
-- rest still listed (status Active, the commodity's unit price). A player saw MY LOTS drop
-- exactly the lots that had sold a part; the live remainder must stay.
describe("MY LOTS with a part-sold lot", function()
  local GC, OWNED

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint() end
    function v:ClearAllPoints() end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
    function v:SetVariant(name) self.variant = name end
    function v:SetScript(n, f) self.scripts[n] = f end
    function v:HookScript(n, f) self.scripts[n] = f end
    function v:Show() self.shown = true end function v:Hide() self.shown = false end
    function v:IsShown() return self.shown end
    function v:Enable() self.enabled = true end function v:Disable() self.enabled = false end
    function v:SetJustifyH() end function v:SetWordWrap() end function v:SetTextColor(...) self.color = { ... } end
    function v:SetMaxLines(n) self.maxLines = n end
    function v:SetSpacing() end
    function v:SetAutoFocus() end function v:SetScrollChild() end
    function v:CreateTexture() return region("Texture", self) end
    function v:SetAllPoints() end function v:SetColorTexture(...) self.colorTexture = { ... } end
    function v:SetTexture() end function v:SetTexCoord() end
    function v:SetTextureSliceMargins() end function v:SetVertexColor() end
    function v:SetFrameStrata() end function v:SetFrameLevel() end
    function v:GetFrameLevel() return 0 end function v:EnableMouse() end
    return v
  end

  local SHELLFISH, OTHER = 13545, 2592
  local function partSold()
    return {
      { auctionID = 198344858, itemKey = { itemID = SHELLFISH }, quantity = 5, status = 1,
        buyoutAmount = 1100, timeLeftSeconds = 3591 },
      { auctionID = 198344858, itemKey = { itemID = SHELLFISH }, quantity = 10, status = 0,
        buyoutAmount = 220, timeLeftSeconds = 28776 },
    }
  end

  before_each(function()
    _G.time = function() return 100000 end
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    _G.C_Container = { GetContainerNumSlots = function() return 0 end }
    OWNED = partSold()
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      GetOwnedAuctions = function() return OWNED end,
    }
    _G.C_Item = { GetItemNameByID = function(id) return id == SHELLFISH and "Shellfish" or "Wool Cloth" end,
      GetItemIconByID = function(id) return 100 + id end }

    GC = {
      Sell = {},
      Theme = {
        color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = { .72, .71, .69 }, red = { 1, 0, 0 },
          green = { 0, 1, 0 }, zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
          gold = { 1, 1, 0 }, panel = { 0, 0, 0 }, panelHi = { 0.102, 0.114, 0.141 } },
        pad = { xs = 4, s = 8, m = 12, l = 16 },
        MEDIA = "",
        Label = function(p) return region("FontString", p) end,
        Num = function(p) return region("FontString", p) end,
        Button = function(p) return region("Button", p) end,
        Card = function(p) local card = region("Frame", p); function card:SetTint() end return card end,
        Plate = function() return nil end,
        SlicedTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
        ShapeTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
        Shape = ThemeShape.Shape, SetShape = ThemeShape.SetShape,
      },
      Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
        GetEntries = function() return {} end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/SoldLots.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
    helper.loadSell(GC)
    GC.Acquisitions.Init({})

    local root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    GC.SellUI.container:Show()
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil
  end)

  local function readRoster()
    GC.Sell.OnOwnedAuctions(true)
    GC.SellState.filterMode = "listed"
    GC.SellUI.List.RenderRows()
  end

  local function shownRows(kind)
    local found = {}
    for _, row in ipairs(GC.SellUI.rows) do
      if row.shown and row.kind == kind then found[#found + 1] = row end
    end
    return found
  end

  it("keeps the 10 live units of a part-sold lot, whichever row the client hands over first", function()
    for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
      local rows = partSold()
      OWNED = { rows[order[1]], rows[order[2]] }
      readRoster()
      local lots = GC.SellState.ownedLots
      assert.equal(1, #lots)
      assert.equal(198344858, lots[1].auctionID)
      assert.equal(10, lots[1].quantity)
      assert.equal(220, lots[1].unitPrice)
      local position
      for _, p in ipairs(GC.SellState.positions) do
        if p.itemID == SHELLFISH then position = p end
      end
      assert.equal(10, position.listedQty)
      -- The live lot counts; the sold part is the badge beside it.
      assert.equal("MY LOTS 1  1 SOLD", helper.plain(GC.SellUI.container.deckButtons.listed.label))
      local rowsShown = shownRows("position")
      assert.equal(1, #rowsShown)
      assert.equal(SHELLFISH, rowsShown[1].position.itemID)
    end
  end)

  it("counts four live lots as four when two of them sold a part (the player's report)", function()
    OWNED = partSold()
    OWNED[#OWNED + 1] = { auctionID = 7001, itemKey = { itemID = OTHER }, quantity = 20, status = 0,
      buyoutAmount = 35, timeLeftSeconds = 40000 }
    OWNED[#OWNED + 1] = { auctionID = 7002, itemKey = { itemID = 4306 }, quantity = 12, status = 1,
      buyoutAmount = 600, timeLeftSeconds = 3000 }
    OWNED[#OWNED + 1] = { auctionID = 7002, itemKey = { itemID = 4306 }, quantity = 8, status = 0,
      buyoutAmount = 50, timeLeftSeconds = 40000 }
    OWNED[#OWNED + 1] = { auctionID = 7003, itemKey = { itemID = 2589 }, quantity = 4, status = 0,
      buyoutAmount = 12, timeLeftSeconds = 40000 }
    readRoster()
    assert.equal(4, #GC.SellState.ownedLots)
    assert.equal("MY LOTS 4  2 SOLD", helper.plain(GC.SellUI.container.deckButtons.listed.label))
    assert.equal(4, #shownRows("position"))
  end)

  -- The audit's one find: the cancels on their way (GC.Sell.cancelledLots) are keyed by auctionID,
  -- and a part-sold lot's sold row keeps that ID after its remainder is cancelled. Read as the lot
  -- still listed, it set the tab saying the cancel had failed.
  it("does not take a cancelled remainder's sold row for the lot still listed", function()
    local said = {}
    GC.SellView.status = function(text) said[#said + 1] = text end
    GC.Sell.cancelledLots[198344858] = { at = 100000 - GC.Sell.CANCEL_SENT_WAIT - 5 }
    OWNED = { partSold()[1] }
    readRoster()
    assert.is_table(GC.Sell.cancelledLots[198344858])
    for _, text in ipairs(said) do
      assert.not_equal("The cancel did not go through: the lot is still listed", text)
    end
    assert.equal(0, #GC.SellState.ownedLots)
  end)

  it("still brings back a lot whose cancel did not go through", function()
    local said = {}
    GC.SellView.status = function(text) said[#said + 1] = text end
    GC.Sell.cancelledLots[198344858] = { at = 100000 - GC.Sell.CANCEL_SENT_WAIT - 5 }
    readRoster()
    assert.is_nil(GC.Sell.cancelledLots[198344858])
    assert.equal(1, #GC.SellState.ownedLots)
    assert.equal("The cancel did not go through: the lot is still listed", said[1])
  end)

  it("does not count a fully sold lot as a live one", function()
    OWNED = { partSold()[1] }
    readRoster()
    assert.equal(0, #GC.SellState.ownedLots)
    assert.equal("MY LOTS 0  1 SOLD", helper.plain(GC.SellUI.container.deckButtons.listed.label))
    assert.equal(0, #shownRows("position"))
  end)

  -- The sold side, as the owner approved it (2026-11-21): the live row says how much of it sold
  -- and what that brought; a lot sold out stays, dimmed, under SOLD OUT until its mail is taken;
  -- a banner adds up what waits in the mailbox; the deck button wears the count.
  describe("what sold", function()
    local NOW = 100000
    local function rowsOf(kind) return shownRows(kind) end
    local function net(copper) return "+" .. GC.Sell._FormatAmount(copper) end

    it("says on the live row how much sold, what it brought after the cut, and how many sales", function()
      readRoster()
      local row = rowsOf("position")[1]
      assert.matches("5 of 15 sold · 10 left", row.itemStock.text, 1, true)
      assert.equal(net(1045), row.soldChip.goldcapText) -- 1100 less 5%
      assert.is_true(row.soldChip.shown)
      assert.equal("one sale", row.soldNote.text) -- there at the first read: when is not known
      assert.is_true(row.soldNote.shown)
      -- The ring: a third of it green from the top, the rest the dim track.
      local segs, lit = row.soldRing.segments, 0
      for _, seg in ipairs(segs) do
        assert.is_true(seg.shown)
        if seg.colorTexture[2] == 1 and seg.colorTexture[4] == 1 then lit = lit + 1 end
      end
      assert.equal(math.floor(#segs / 3 + 0.5), lit)
    end)

    it("says a lot nothing of which sold has sold nothing yet", function()
      OWNED = { partSold()[2] }
      readRoster()
      local row = rowsOf("position")[1]
      assert.matches("10 listed · none sold yet", row.itemStock.text, 1, true)
      assert.equal("nothing yet", row.soldNote.text)
      assert.is_false(row.soldChip.shown)
      -- No sold rows: no banner, no SOLD OUT, no footer, and the deck button as it always was.
      assert.equal(0, #rowsOf("soldBanner"))
      assert.equal(0, #rowsOf("soldFoot"))
      assert.equal("MY LOTS 1", helper.plain(GC.SellUI.container.deckButtons.listed.label))
    end)

    it("keeps a sold-out lot under SOLD OUT, with no button, until the client stops returning it", function()
      readRoster()
      _G.time = function() return NOW + 60 end
      OWNED[#OWNED + 1] = { auctionID = 7002, itemKey = { itemID = OTHER }, quantity = 62, status = 1,
        buyoutAmount = 10000, timeLeftSeconds = 3500 }
      readRoster()
      assert.equal("MY LOTS 1", helper.plain(GC.SellUI.container.deckButtons.listed.label):match("^MY LOTS %d+"))
      assert.matches("2 SOLD", helper.plain(GC.SellUI.container.deckButtons.listed.label), 1, true)
      local out = rowsOf("soldOut")
      assert.equal(1, #out)
      assert.equal("Wool Cloth", out[1].cells.item.text)
      assert.equal("all 62 sold · money in your mailbox", out[1].itemStock.text)
      assert.equal(net(9500), out[1].soldChip.goldcapText)
      assert.is_false(out[1].action.shown)
      -- Seen first a minute after a read that did not have it: the sale is dated.
      assert.equal("one sale · 0 min ago", out[1].soldNote.text)
      _G.time = function() return NOW + 60 + 51 * 60 end
      GC.SellUI.List.RenderRows()
      assert.equal("one sale · 51 min ago", rowsOf("soldOut")[1].soldNote.text)
      -- The SOLD OUT heading stands over it, under the live lot.
      local order = {}
      for _, row in ipairs(GC.SellUI.rows) do if row.shown then order[#order + 1] = row.kind end end
      assert.same({ "soldBanner", "section", "position", "section", "soldOut", "soldFoot" }, order)
      -- The mail taken: the client returns the row no more, and it is gone.
      OWNED = partSold()
      readRoster()
      assert.equal(0, #rowsOf("soldOut"))
    end)

    it("adds up what waits in the mailbox in a banner, with the items that brought most", function()
      OWNED[#OWNED + 1] = { auctionID = 7002, itemKey = { itemID = OTHER }, quantity = 62, status = 1,
        buyoutAmount = 10000, timeLeftSeconds = 3500 }
      OWNED[#OWNED + 1] = { auctionID = 7003, itemKey = { itemID = 4306 }, quantity = 2, status = 1,
        buyoutAmount = 100, timeLeftSeconds = 3500 }
      readRoster()
      local banner = rowsOf("soldBanner")[1]
      assert.equal("SINCE YOU LAST LOOKED · 3 SALES", banner.soldBanner.title.text)
      assert.equal(net(1045 + 9500 + 95) .. " waiting in your mailbox", banner.soldBanner.big.text)
      assert.matches("Wool Cloth  " .. net(9500), banner.soldBanner.chips[1].goldcapText, 1, true)
      assert.matches("Shellfish  " .. net(1045), banner.soldBanner.chips[2].goldcapText, 1, true)
      assert.equal("+1 more", banner.soldBanner.more.text)
      local foot = rowsOf("soldFoot")[1]
      assert.equal("STILL ON THE AH " .. GC.Sell._FormatAmount(2090) .. " after the 5% cut", foot.soldFoot.left.text)
      assert.matches("Sold-out lots leave once you open the mail", foot.soldFoot.right.text, 1, true)
    end)

    it("draws no sold side on the posting deck", function()
      OWNED[#OWNED + 1] = { auctionID = 7002, itemKey = { itemID = OTHER }, quantity = 62, status = 1,
        buyoutAmount = 10000, timeLeftSeconds = 3500 }
      readRoster()
      GC.SellState.filterMode = "post"
      GC.SellUI.List.RenderRows()
      assert.equal(0, #rowsOf("soldBanner"))
      assert.equal(0, #rowsOf("soldOut"))
      for _, row in ipairs(GC.SellUI.rows) do
        if row.shown then
          assert.is_false(row.soldChip.shown)
          assert.is_false(row.soldNote.shown)
          for _, seg in ipairs(row.soldRing.segments) do assert.is_false(seg.shown) end
        end
      end
    end)
  end)
end)
