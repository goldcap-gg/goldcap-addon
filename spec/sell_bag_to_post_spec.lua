local helper = require("spec.spec_helper")

-- End to end through the real modules: bags -> positions -> rendered rows -> a
-- post plan. The unit specs each prove one seam; this proves they are wired to
-- each other, which is the class of bug that survives a green unit suite and
-- then greets the player as an empty tab.
describe("Sell tab, bags to Post", function()
  local GC, root, rows, render

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
    function v:SetSpacing() end
    function v:SetAutoFocus() end function v:SetScrollChild() end
    function v:CreateTexture() return region("Texture", self) end
    function v:SetAllPoints() end function v:SetColorTexture() end
    function v:SetTexture() end function v:SetTexCoord() end
    function v:SetTextureSliceMargins() end function v:SetVertexColor() end
    function v:SetFrameStrata() end function v:SetFrameLevel() end
    function v:GetFrameLevel() return 0 end function v:EnableMouse() end
    return v
  end

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local n, val = debug.getupvalue(fn, i)
      if not n then break end
      if n == wanted then return val end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local n = debug.getupvalue(fn, i)
      if not n then break end
      if n == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  -- Slot 1: 200 Eternium Ore, a commodity, freely sellable.
  -- Slot 2: 46 more of the same, so the aggregate has to add up across stacks.
  -- Slot 3: soulbound, which the auction house refuses.
  -- Slot 4: no link, so its exact auction identity cannot be derived and classify refuses it.
  --         (It is also vendor-worthless, which is NOT why it is out -- see the regression
  --         test below and Core/BagStock.lua's own note on `hasNoValue`.)
  local BAGS = {
    [0] = {
      { itemID = 23427, stackCount = 200, itemName = "Eternium Ore" },
      { itemID = 23427, stackCount = 46, itemName = "Eternium Ore" },
      { itemID = 6948, stackCount = 1, itemName = "Hearthstone", isBound = true },
      { itemID = 1, stackCount = 1, itemName = "Junk", hasNoValue = true },
    },
  }

  before_each(function()
    _G.time = function() return 1000 end
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end,
      GetContainerItemInfo = function(bag, slot) return (BAGS[bag] or {})[slot] end,
      GetContainerItemLink = function() return nil end,
    }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function(key) return { isCommodity = key.itemID == 23427 } end,
    }
    _G.C_Item = { GetItemNameByID = function() return "Eternium Ore" end }

    GC = {
      Sell = {},
      Theme = {
        color = { fg = { 1, 1, 1 }, fgDim = { .5, .5, .5 }, fgMuted = { .72, .71, .69 }, red = { 1, 0, 0 }, green = { 0, 1, 0 },
          zebra = { 1, 1, 1, 0.04 }, hover = { 1, 1, 1, 0.08 }, border = { 1, 1, 1, 0.06 },
          gold = { 1, 1, 0 }, panel = { 0, 0, 0 }, panelHi = { 0.102, 0.114, 0.141 } },
        pad = { xs = 4, s = 8, m = 12, l = 16 },
        MEDIA = "",
        Label = function(p) return region("FontString", p) end,
        Num = function(p) return region("FontString", p) end,
        Button = function(p) return region("Button", p) end,
        Card = function(p) local card = region("Frame", p); function card:SetTint() end return card end,
        SlicedTexture = function(p, layer) local t = region("Texture", p); t.layer = layer; return t end,
      },
      Ledger = { Context = function() return { char = "Owner-Dentarg", region = "eu" } end,
        GetEntries = function() return {} end },
      Data = { GetItemValue = function() return { sold = 7447 } end },
    }
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    GC.Acquisitions.Init({})

    root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    render = upvalue(GC.Sell.Attach, "renderRows")
    -- Attach leaves the Sell container hidden (one of several tabs on the real Sniper
    -- window); renderRows now defers a rebuild while it is hidden, so this whole suite --
    -- which reads rendered rows directly -- needs it shown, the way GC.Sell.Show() (the
    -- real tab switch) would leave it.
    upvalue(render, "container"):Show()
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString = os.time, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil
  end)

  local function compose()
    upvalue(GC.Sell.SellableCount, "composePositions")()
    render()
    rows = upvalue(render, "rows")
  end

  local function positionRow()
    for _, row in ipairs(rows) do
      if row.shown and row.kind == "position" then return row end
    end
  end

  it("lists bag stock GoldCap never bought, and offers to post it", function()
    compose()
    local row = positionRow()
    assert.is_not_nil(row)
    assert.equal("commodity:23427", row.position.positionKey)
    -- 200 + 46, added across both stacks.
    assert.equal(246, row.position.bagQty)
    assert.match("×246 in bags", row.itemStock.text)
    assert.equal("Post", row.action.label)
    assert.is_true(row.action.shown)
  end)

  it("counts only what the auction house would accept", function()
    compose()
    local shown = 0
    for _, r in ipairs(rows) do if r.shown and r.kind == "position" then shown = shown + 1 end end
    assert.equal(1, shown) -- the soulbound and the unidentifiable are not positions
    assert.equal(1, GC.Sell.SellableCount())
  end)

  -- The one number on that second line that is money had exactly the weight of the word "in"
  -- next to it: one uniform size-10 run-on, no colour of its own. The owner of a live client,
  -- looking at a row that had been showing him his own cost for weeks: "I did not even see it,
  -- it just sits there." Only the AMOUNT is escaped -- a translation may put the money anywhere
  -- in its own sentence, and colouring the whole phrase would light up the words too.
  it("colours the money on the stock line, and only the money", function()
    GC.Acquisitions.Record({ source = "goldcap", itemID = 23427,
      positionKey = "commodity:23427", itemName = "Eternium Ore", quantity = 246,
      total = 242457600, acquiredAt = 1, evidenceKey = "buy:money",
      character = "Owner-Dentarg", region = "eu" })
    compose()
    local row = positionRow()
    assert.equal("COMPLETE", row.position.coverage)
    assert.equal("×246 in bags · paid |cffe8c15a98g56s|r each", row.itemStock.text)
  end)

  -- SellPositions.Build cannot reach SavedVariables and must not, so the commodity-versus-item
  -- contradiction it settles is only settleable if the CALLER hands it the client's cached
  -- answer. A capability nothing feeds is the bug: this suite has shipped exactly that before,
  -- a fix that was dead code because the call site never supplied what it needed.
  it("hands SellPositions.Build the client's cached commodity answers", function()
    GC.db = GC.db or {}
    GC.db.commodityByItem = { [23427] = true }
    local captured
    local realBuild = GC.SellPositions.Build
    GC.SellPositions.Build = function(args) captured = args; return realBuild(args) end
    compose()
    GC.SellPositions.Build = realBuild
    assert.is_table(captured.commodityKinds)
    assert.is_true(captured.commodityKinds[23427])
  end)

  -- The deck switch is painted once at construction, when `positions` is still empty, and then
  -- only by its own buttons' OnClick. Nothing repainted it when the list was rebuilt, so both
  -- counts read 0 over a full tab -- and a "TO POST 0" over thirteen bag-stock positions is
  -- exactly what made an already-fixed bag bug look like it was still there.
  it("keeps the deck counts in step with the list it is counting", function()
    compose()
    local container = upvalue(GC.Sell.Attach, "container")
    assert.equal("TO POST 1", container.deckButtons.post.label)
    assert.equal("MY LOTS 0", container.deckButtons.listed.label)
  end)

  -- Regression from a live client: `hasNoValue` means the VENDOR will not buy the item, which
  -- says nothing about the auction house. Reading it as a refusal hid a seller's whole reagent
  -- inventory -- a bag dump had 322 Venomous Combatant's Heraldry, 850 Gloom Dust and 38
  -- Greater Eternal Essence, every one of them freely tradeable -- and the Sell row said "not
  -- on hand" over a stack the Blizzard sell frame was offering to post. Pinned here, at the
  -- call site, and not only over the pure walk in spec/bag_stock_spec.lua.
  it("offers stock the vendor will not buy but the auction house will", function()
    BAGS[0][#BAGS[0] + 1] =
      { itemID = 23427, stackCount = 54, itemName = "Eternium Ore", hasNoValue = true }
    compose()
    local row = positionRow()
    local bagQty = row and row.position.bagQty
    BAGS[0][#BAGS[0]] = nil
    assert.equal(300, bagQty) -- 200 + 46 + the 54 the vendor-value test used to throw away
  end)

  -- SellableCount used to call composePositions() itself on every read -- a full six-bag
  -- scan plus every Acquisitions/Ledger walk -- even though updateSellTabLabel()'s own
  -- callers all read it right where a compose had either just run or was about to. It now
  -- reads the count composePositions() stamps as it walks positions, so a read after a real
  -- compose must not trigger a second one.
  it("[perf] does not recompose positions merely to read the sellable count", function()
    compose() -- a real composePositions() run, via the upvalue, the same way `compose()` above does
    set(GC.Sell.SellableCount, "composePositions", function()
      error("SellableCount must not recompose -- the count was already stamped")
    end)
    assert.equal(1, GC.Sell.SellableCount())
  end)

  -- The one caller that reads it without a compose immediately before it (recordPurchaseFacts,
  -- right after a GoldCap purchase) is still correct: a GoldCap purchase always lands in the
  -- mailbox, never straight into the bags, so bagQty -- what this counts -- cannot have moved
  -- at that exact instant. The cached value already answers correctly with no recompose.
  it("[perf] composes exactly once on a cold call before anything has ever composed", function()
    local composeCalls = 0
    local realCompose = upvalue(GC.Sell.SellableCount, "composePositions")
    set(GC.Sell.SellableCount, "composePositions", function() composeCalls = composeCalls + 1; realCompose() end)
    assert.equal(1, GC.Sell.SellableCount())
    assert.equal(1, composeCalls)
    assert.equal(1, GC.Sell.SellableCount()) -- second read: still cached, no second compose
    assert.equal(1, composeCalls)
  end)

  it("reports the cost as unknown rather than inventing one", function()
    compose()
    local row = positionRow()
    assert.equal("—", row.cells.cost.text)
    assert.equal("Unknown", row.cells.profit.text)
  end)

  it("advises a price once a live quote lands, and builds a post plan for it", function()
    local quotes = upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    -- The honest cheap side of the real EU book, after the ingest fix.
    GC.QuoteCache.Set(quotes, 23427, 184719, 1000)
    compose()
    local row = positionRow()
    assert.equal(184719, row.position.freshMarketUnit)
    assert.match("Post", row.cells.status.text)

    local plan, reason = GC.SellPositions.BuildPostPlan(row.position,
      { itemID = 23427, exactQty = 246, positionKey = "commodity:23427" },
      { unit = 184719, fresh = true })
    assert.is_nil(reason)
    assert.equal(246, plan.quantity)
    assert.is_false(plan.costKnown)
    -- Part 0 (silver-grid fix): 184719 carries 19 copper of remainder -- PostCommodity would
    -- have silently rejected it. BuildPostPlan now rounds up to the nearest whole silver.
    assert.equal(184800, plan.unitPrice)
  end)

  it("prices only what there is something to do with", function()
    local ready = upvalue(GC.Sell.OnOwnedAuctions, "onOwnedAuctionsReady")
    local walk = upvalue(upvalue(ready, "beginQuoteWalk"), "uniqueQuoteItemIDs")
    compose()
    assert.same({ 23427 }, walk())
  end)
  it("shows bag stock away from an auctioneer, where the server cannot be asked", function()
    -- No auction house session: requestOwnedAuctions refuses, the pricing walk
    -- never starts, and the tab used to answer with an empty list and a line of
    -- text -- while the answer to "what could I sell" sat in the player's bags.
    GC.Sniper = { IsAHOpen = function() return false end }
    GC.Sell.Refresh()
    rows = upvalue(render, "rows")
    local row = positionRow()
    assert.is_not_nil(row)
    assert.equal(246, row.position.bagQty)
    assert.equal("Auction House is not open", root.status.text)
  end)
  -- Set cost did nothing at all on bag stock: openCostDialog sized "how many
  -- units still need a cost" from exposureQty, which counts tracked purchases
  -- and live listings and knows nothing about the bags. For anything GoldCap
  -- never bought that number is zero, so the function returned before showing
  -- the dialog and the button looked dead.
  it("opens Set cost for bag stock GoldCap never bought", function()
    compose()
    local row = positionRow()
    local openCostDialog = upvalue(render, "openCostDialog")
    local dialog = upvalue(render, "container").costDialog
    dialog.shown = false
    openCostDialog(row.position)
    assert.is_true(dialog.shown)
    assert.equal(246, dialog.maximum)
  end)

  it("offers Set cost only where it would do something", function()
    compose()
    local row = positionRow()
    local canSetCost = upvalue(render, "canSetCost")
    assert.is_true(canSetCost(row.position))
    -- Nothing held, nothing to cost: the button must not be offered at all,
    -- rather than offered and silently inert.
    assert.is_false(canSetCost({ positionKey = "commodity:1", exposureQty = 0,
      knownQty = 0, bagQty = 0, listedQty = 0 }))
  end)
  it("still offers Set cost when only part of the stock is costed", function()
    -- Five bought through GoldCap, the rest farmed. Coverage used to read COMPLETE against the
    -- tracked purchase alone (blind to the other 241 units actually sitting in the bags), and
    -- gating the button on that label hid it for exactly the case that needs it most -- the
    -- cost-covers-everything-held fix (Core/SellPositions.lua) now reports this correctly as
    -- PARTIAL, but canSetCost/uncostedQty were deliberately never gated on the label (they
    -- compare held against knownQty/trackedQty directly) and still don't need to be.
    GC.Acquisitions.Record({ source = "goldcap", itemID = 23427,
      positionKey = "commodity:23427", itemName = "Eternium Ore", quantity = 5,
      total = 60000, acquiredAt = 1, evidenceKey = "buy:1",
      character = "Owner-Dentarg", region = "eu" })
    compose()
    local row = positionRow()
    assert.equal("PARTIAL", row.position.coverage)
    local openCostDialog = upvalue(render, "openCostDialog")
    local dialog = upvalue(render, "container").costDialog
    dialog.shown = false
    openCostDialog(row.position)
    assert.is_true(dialog.shown)
    assert.equal(241, dialog.maximum) -- 246 held, 5 of them costed
  end)

  -- Live incident: 24 listed capped the FIFO allocation at 24, but a recorded
  -- batch actually covered all 118 units the player was holding across bags and
  -- listings. knownQty read 24 against that same 118, so the dialog said "94
  -- units without a cost" for stock that already had one, and entering a
  -- manual cost doubled it. knownQty alone can never see past the allocation
  -- cap -- trackedQty can, and must be checked too.
  it("does not offer Set cost for stock a recorded batch already covers beyond the allocation cap", function()
    local canSetCost = upvalue(render, "canSetCost")
    assert.is_false(canSetCost({ positionKey = "commodity:1", listedQty = 24, bagQty = 94,
      exposureQty = 24, knownQty = 24, trackedQty = 118 }))
  end)

  it("still offers Set cost for stock with no batch recorded against it at all", function()
    local canSetCost = upvalue(render, "canSetCost")
    assert.is_true(canSetCost({ positionKey = "commodity:1", bagQty = 50,
      exposureQty = 50, knownQty = 0, trackedQty = 0 }))
  end)

  it("offers Set cost for the uncovered remainder, and withholds it once a batch closes the gap", function()
    -- 60 of the 100 held units are costed either way; the other 40 stay open
    -- until something -- allocation or a manual entry -- actually accounts for them.
    local canSetCost = upvalue(render, "canSetCost")
    assert.is_true(canSetCost({ positionKey = "commodity:1", bagQty = 100,
      exposureQty = 60, knownQty = 60, trackedQty = 60 }))
    assert.is_false(canSetCost({ positionKey = "commodity:1", bagQty = 100,
      exposureQty = 60, knownQty = 60, trackedQty = 100 }))
  end)
end)
