local helper = require("spec.spec_helper")

-- The owner, in game (2026-09-23): "Jeb's Underwear isn't in Sell, and other items too -- why?"
-- A bag full of gear, none of it on TO POST. Two causes, both silent:
--   * the tab keyed a non-commodity stack from its item link and gave up on any link carrying
--     bonus IDs -- which is nearly all modern gear -- or a battle pet, rather than post under a
--     guessed item level. The client has an exact authority for this, the one the auction house
--     itself keys by: C_AuctionHouse.GetItemKeyFromItem on the stack's own bag slot.
--   * an item whose kind (commodity or not) the client had not answered yet was left out with no
--     row and no count.
describe("Sell tab, every tradeable bag item gets a row", function()
  local GC, root, render, container, bags, kinds, slotKeys, searches, results, posted, timers, created

  local function region(kind, parent)
    local v = { __frame = true, kind = kind, parent = parent, shown = true, points = {}, scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = v end
    function v:SetPoint() end
    function v:ClearAllPoints() end
    function v:SetSize() end function v:SetWidth() end function v:SetHeight() end
    function v:SetText(t) self.text = t end function v:GetText() return self.text or "" end
    function v:SetLabel(t) self.label = t end
    function v:SetVariant(name) self.variant = name end
    function v:SetBusy(on) self.busy = on and true or false end
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

  -- Links: the same item-string shape the existing specs use. Field 14 is the bonus-ID count.
  local PLAIN = "item:%d:0::0:0:0:7:0:0:0:0:0:0"
  local BONUSED = "item:%d:0::0:0:0:0:0:0:0:0:0:2:6652:1520"
  local PET = "battlepet:1234:25:3:1500:300:300:0"

  local function key(itemID, level, suffix, pet)
    return { itemID = itemID, itemLevel = level or 0, itemSuffix = suffix or 0, battlePetSpeciesID = pet or 0 }
  end

  local function keyName(k)
    return table.concat({ k.itemID, k.itemLevel or 0, k.itemSuffix or 0, k.battlePetSpeciesID or 0 }, ":")
  end

  before_each(function()
    bags, kinds, slotKeys, searches, results, posted = { [0] = {} }, {}, {}, {}, {}, {}
    timers, created = {}, {}
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.time = function() return 1000 end
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(n) return tostring(n) end
    _G.Enum = { AuctionHouseSortOrder = { Buyout = 4 } }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(bags[bag] or {}) end,
      GetContainerItemInfo = function(bag, slot) return (bags[bag] or {})[slot] end,
      GetContainerItemLink = function(bag, slot) return ((bags[bag] or {})[slot] or {}).hyperlink end,
    }
    _G.C_Item = {
      GetItemNameByID = function(id) return "Item " .. id end,
      GetDetailedItemLevelInfo = function() return 100 end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID, level, suffix, pet) return key(itemID, level, suffix, pet) end,
      -- `kinds[itemID]`: true commodity, false item, nil the client has not answered yet.
      GetItemKeyInfo = function(k)
        local kind = kinds[k.itemID]
        if kind == nil then return nil end
        return { isCommodity = kind, itemName = "Item " .. k.itemID }
      end,
      GetItemKeyFromItem = function(location) return slotKeys[location.bag .. ":" .. location.slot] end,
      IsThrottledMessageSystemReady = function() return true end,
      SendSearchQuery = function(k) searches[#searches + 1] = keyName(k) end,
      GetNumItemSearchResults = function(k) return #(results[keyName(k)] or {}) end,
      GetItemSearchResultInfo = function(k, i) return (results[keyName(k)] or {})[i] end,
      HasFullItemSearchResults = function() return true end,
      PostItem = function(location, _, quantity) posted[#posted + 1] = { slot = location.slot, quantity = quantity }; return false end,
      -- What AUCTION_HOUSE_AUCTION_CREATED's auctionID names, when the client knows it.
      GetAuctionInfoByID = function(auctionID) return created[auctionID] and { itemKey = created[auctionID] } or nil end,
    }

    GC = {
      Sell = {},
      Sniper = { IsAHOpen = function() return true end },
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
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/BagStock.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
    helper.loadModule("UI/SellFrame.lua", GC)
    GC.Acquisitions.Init({})

    root = region("Frame")
    root.HookScript = function(_, n, f) root.scripts[n] = f end
    root.status = region("FontString", root)
    GC.Sell.Attach(root, { panelLeft = 8, panelRightInset = 8, top = -10, bottom = 8,
      rowWidth = 1100, rowHeight = 24 })
    render = upvalue(GC.Sell.Attach, "renderRows")
    container = upvalue(render, "container")
    container:Show()
  end)

  after_each(function()
    _G.time, _G.CreateFrame, _G.GetCoinTextureString, _G.Enum = os.time, nil, nil, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation, _G.C_Timer = nil, nil, nil, nil, nil
  end)

  local function compose()
    upvalue(GC.Sell.SellableCount, "composePositions")()
    render()
  end

  local function positions()
    return upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "positions")
  end

  local function positionOf(positionKey)
    for _, p in ipairs(positions()) do if p.positionKey == positionKey then return p end end
    return nil
  end

  local function stack(slot, itemID, count, link, over)
    local info = { itemID = itemID, stackCount = count, itemName = "Item " .. itemID,
      hyperlink = link and link:format(itemID) or nil }
    for k, v in pairs(over or {}) do info[k] = v end
    bags[0][slot] = info
  end

  it("keys bonus-ID gear by the auction house's own ItemKey for its bag slot", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    compose()
    local p = positionOf("item:222:619:0:0")
    assert.is_truthy(p, "the bonus-ID stack has no row")
    assert.equal(1, p.bagQty)
    assert.equal("item:222:619:0:0", p.quoteKey)
  end)

  -- Everything already on the tab keeps its key byte for byte: ledgers, typed prices and
  -- listings are filed under it. Only stacks the link parse gave up on are keyed the new way.
  it("keeps a bonus-free item's key exactly as it was", function()
    kinds[42] = false
    stack(1, 42, 1, PLAIN)
    slotKeys["0:1"] = key(42, 555) -- even where the slot's ItemKey would say otherwise
    compose()
    local p = positionOf("item:42:100:7:0")
    assert.is_truthy(p)
    assert.is_nil(p.quoteKey)
    assert.is_nil(positionOf("item:42:555:0:0"))
  end)

  it("keys a caged battle pet by what its ItemKey carries, species included", function()
    kinds[82800] = false
    stack(1, 82800, 1, nil, { hyperlink = PET })
    slotKeys["0:1"] = key(82800, 25, 0, 1234)
    compose()
    assert.is_truthy(positionOf("item:82800:25:0:1234"))
  end)

  it("still leaves soulbound stock out: the auction house refuses it", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED, { isBound = true })
    slotKeys["0:1"] = key(222, 619)
    compose()
    assert.is_nil(positionOf("item:222:619:0:0"))
    for _, row in ipairs(upvalue(render, "rows")) do
      assert.is_false(row:IsShown() and row.kind == "waitItem")
    end
  end)

  -- An item the client has not classified yet is still on hand and still tradeable. It used to
  -- vanish: no row, no count, nothing to say it was there at all.
  it("shows an item it cannot key yet under its own heading, and files it once the client answers", function()
    GC.Sniper.IsAHOpen = function() return false end -- away from the auction house
    stack(1, 333, 1, PLAIN, { itemName = "Jeb's Underwear" })
    compose()
    local head, item
    for _, row in ipairs(upvalue(render, "rows")) do
      if row:IsShown() and row.kind == "waitHead" then head = row end
      if row:IsShown() and row.kind == "waitItem" then item = row end
    end
    assert.is_truthy(head, "no heading for the stock the tab cannot key yet")
    assert.matches("WAITING FOR THE AUCTION HOUSE 1", head.sectionLabel.text, 1, true)
    assert.matches("open the auction house once", head.sectionLabel.text, 1, true)
    assert.is_truthy(item)
    assert.matches("Jeb's Underwear ×1", item.sectionLabel.text, 1, true)
    assert.is_nil(positionOf("item:333:100:7:0"))
    -- The client answers (ITEM_KEY_ITEM_INFO_RECEIVED): the stack is re-scanned and filed.
    kinds[333] = false
    GC.Sell.OnItemKeyInfo(333)
    assert.is_truthy(positionOf("item:333:100:7:0"))
    for _, row in ipairs(upvalue(render, "rows")) do
      assert.is_false(row:IsShown() and (row.kind == "waitHead" or row.kind == "waitItem"))
    end
  end)

  -- Post pins the stack it proved: for gear, the slot whose own ItemKey is the position's.
  it("posts a variant from the slot whose ItemKey is that variant's", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    stack(2, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    slotKeys["0:2"] = key(222, 626)
    compose()
    local state = upvalue(upvalue(render, "onPostClick"), "liveBagState")(positionOf("item:222:626:0:0"), 1)
    assert.equal(2, state.slot)
    assert.equal("item:222:626:0:0", state.positionKey)
    state = upvalue(upvalue(render, "onPostClick"), "liveBagState")(positionOf("item:222:619:0:0"), 1)
    assert.equal(1, state.slot)
  end)

  -- The market price of a variant is its own: the search goes out with the exact ItemKey and the
  -- answer is read from that key -- never the item's cheapest variant from the bare key.
  it("prices a variant from a search for its exact ItemKey", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    results["222:0:0:0"] = { { buyoutAmount = 1000, quantity = 1 } }  -- a cheaper, lower variant
    results["222:619:0:0"] = { { buyoutAmount = 50000, quantity = 1 } }
    compose()
    GC.Sell.Refresh(true)
    assert.same({ "222:619:0:0" }, searches)
    GC.Sell.OnItemSearchResults(222, key(222, 619))
    local p = positionOf("item:222:619:0:0")
    assert.equal(50000, p.displayMarketUnit)
  end)

  it("hands the searched ItemKey on with the item search results", function()
    local f = assert(io.open("GoldCap/Core/Init.lua", "r"))
    local init = f:read("*a")
    f:close()
    local handler = assert(init:match('event == "ITEM_SEARCH_RESULTS_UPDATED" then(.-)\n  elseif'))
    assert.is_truthy(handler:find("GC.Sell.OnItemSearchResults(itemKey.itemID, itemKey)", 1, true), handler)
  end)

  -- Two variants of one item are two positions, and one can be late while the other posts. A
  -- creation the client names must go to the variant it names -- item level and suffix, not the
  -- itemID alone, which both share (review M2).
  it("tells a late variant from the one on the wire by the item level the client names", function()
    local recorded, real = {}, GC.Acquisitions.RecordPost
    GC.Acquisitions.RecordPost = function(...) recorded[#recorded + 1] = { ... }; return real(...) end
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    stack(2, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    slotKeys["0:2"] = key(222, 626)
    local quotes = upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    GC.QuoteCache.Set(quotes, "item:222:619:0:0", 50000, 1000)
    GC.QuoteCache.Set(quotes, "item:222:626:0:0", 60000, 1000)
    compose()
    local function press(positionKey)
      for _, row in ipairs(upvalue(render, "rows")) do
        if row:IsShown() and row.kind == "position" and row.position.positionKey == positionKey then
          row.action.scripts.OnClick(row.action)
          return row
        end
      end
      error("no row for " .. positionKey)
    end
    press("item:222:619:0:0")
    for i = #timers, 1, -1 do if timers[i].seconds == 8 then table.remove(timers, i).fn() end end
    local wire = press("item:222:626:0:0")
    assert.equal(2, #posted)
    -- The WIRE's variant named first: by order alone the late 619 would take it (review NM2).
    created[702] = key(222, 626)
    GC.Sell.OnAuctionCreated(702)
    assert.equal(1, #recorded)
    assert.equal("item:222:626:0:0", recorded[1][1])
    assert.is_nil(wire.postStage)
    created[701] = key(222, 619)
    GC.Sell.OnAuctionCreated(701)
    assert.equal(2, #recorded)
    assert.equal("item:222:619:0:0", recorded[2][1])
  end)

  -- For gear the client's AuctionInfo also carries the buyout, which a pin knows exactly: a
  -- named creation whose buyout is another post's is not this one's.
  it("tells two posts of one item apart by the buyout the client names", function()
    local recorded, real = {}, GC.Acquisitions.RecordPost
    GC.Acquisitions.RecordPost = function(...) recorded[#recorded + 1] = { ... }; return real(...) end
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    stack(2, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    slotKeys["0:2"] = key(222, 626)
    local quotes = upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    GC.QuoteCache.Set(quotes, "item:222:619:0:0", 50000, 1000)
    GC.QuoteCache.Set(quotes, "item:222:626:0:0", 60000, 1000)
    compose()
    local function press(positionKey)
      for _, row in ipairs(upvalue(render, "rows")) do
        if row:IsShown() and row.kind == "position" and row.position.positionKey == positionKey then
          row.action.scripts.OnClick(row.action)
          return row
        end
      end
      error("no row for " .. positionKey)
    end
    press("item:222:619:0:0")
    for i = #timers, 1, -1 do if timers[i].seconds == 8 then table.remove(timers, i).fn() end end
    press("item:222:626:0:0")
    -- Named by item alone (level 0), with 626's buyout.
    _G.C_AuctionHouse.GetAuctionInfoByID = function() return { itemKey = key(222), buyoutAmount = 60000 } end
    GC.Sell.OnAuctionCreated(703)
    assert.equal(1, #recorded)
    assert.equal("item:222:626:0:0", recorded[1][1])
  end)

  -- BagStock leaves a soulbound copy out, but the Post matcher could still pin one sharing the
  -- ItemKey -- the auction house refuses it, and the tradeable copy could never be posted (M8).
  it("never pins a soulbound copy for Post", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED, { isBound = true })
    stack(2, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    slotKeys["0:2"] = key(222, 619)
    compose()
    local state = upvalue(upvalue(render, "onPostClick"), "liveBagState")(positionOf("item:222:619:0:0"), 1)
    assert.equal(2, state.slot)
  end)

  -- Two copies of one piece at two item levels were two identical rows. The row names its level,
  -- and its tooltip is the stack itself, not the base item (M9).
  it("names a variant's item level on its row, and shows the stack itself on hover", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED, { itemName = "Foo Helm" })
    slotKeys["0:1"] = key(222, 619)
    compose()
    local row
    for _, candidate in ipairs(upvalue(render, "rows")) do
      if candidate:IsShown() and candidate.kind == "position" then row = candidate end
    end
    assert.matches("ilvl 619", row.cells.item.text, 1, true)
    local shown = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, AddLine = function() end,
      SetBagItem = function(_, bag, slot) shown.bag, shown.slot = bag, slot end,
      SetItemByID = function(_, id) shown.itemID = id end }
    GC.Theme.ItemTooltipOutside = function() end
    row.scripts.OnEnter(row)
    assert.same({ bag = 0, slot = 1 }, shown)
    -- The row owns the tooltip, and says which variant it stands for: GoldCap's own block under
    -- it (UI/Tooltip.lua) reads that off the tooltip's owner -- review N7, NI-B.
    assert.equal("level", row.goldcapVariant)
    -- Leaving closes the whole tooltip, the pet card Blizzard may have opened for a cage too
    -- (GameTooltip_Hide) -- review N5.
    local hid = false
    _G.GameTooltip_Hide = function() hid = true end
    row.scripts.OnLeave(row)
    _G.GameTooltip, _G.GameTooltip_Hide = nil, nil
    assert.is_true(hid)
    assert.is_nil(row.goldcapVariant)
  end)

  -- Escape, the auction house closing, a tab switch by keybinding, a re-render after a post: the
  -- row goes with the cursor still on it, and OnLeave never comes. The next item tooltip -- a bag
  -- slot's -- is its own, and keeps GoldCap's value (review NI-B).
  it("keeps GoldCap's value on the next item tooltip after a variant row goes without OnLeave", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED, { itemName = "Foo Helm" })
    slotKeys["0:1"] = key(222, 619)
    compose()
    local row
    for _, candidate in ipairs(upvalue(render, "rows")) do
      if candidate:IsShown() and candidate.kind == "position" then row = candidate end
    end
    local owner, lines, postCall = nil, {}, nil
    _G.GameTooltip = { SetOwner = function(_, frame) owner = frame end, GetOwner = function() return owner end,
      Show = function() end, SetBagItem = function() end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left) lines[#lines + 1] = left end }
    GC.Theme.ItemTooltipOutside = function(frame) _G.GameTooltip:SetOwner(frame) end
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
    _G.Enum.TooltipDataType = { Item = 0 }
    _G.C_Item.GetItemInfoInstant = function() return 222 end
    GC.db = { settings = { tooltip = true } }
    GC.Data.GetItemValue = function() return { mv = 9000000, sold = 50, ts = 1000 } end
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("UI/Tooltip.lua", GC)

    row.scripts.OnEnter(row)
    postCall(_G.GameTooltip, { id = 222 })
    assert.matches("no market figure for this item level", table.concat(lines, " | "), 1, true)

    container:Hide() -- Escape: gone under a stationary cursor, no OnLeave
    row.scripts.OnHide(row)
    assert.is_nil(row.goldcapVariant)
    lines = {}
    _G.GameTooltip:SetOwner({}) -- a bag slot's button
    postCall(_G.GameTooltip, { id = 222 })
    local text = table.concat(lines, " | ")
    _G.GameTooltip, _G.TooltipDataProcessor = nil, nil
    assert.matches("GoldCap value", text, 1, true)
    assert.is_nil(text:find("no market figure", 1, true))
  end)

  -- A read cut short -- more rows than the tab reads, or an answer the client does not hold in
  -- full -- says so on the levels themselves, for THE BOOK's "past the read" (M5).
  it("marks a read the client cut short", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    local rows = {}
    for i = 1, 101 do rows[i] = { buyoutAmount = 1000 + i, quantity = 1 } end
    results["222:619:0:0"] = rows
    compose()
    GC.Sell.Refresh(true)
    GC.Sell.OnItemSearchResults(222, key(222, 619))
    local quotes = upvalue(upvalue(GC.Sell.SellableCount, "composePositions"), "quotes")
    assert.is_true(quotes["item:222:619:0:0"].levels.cut)
  end)

  -- "PRICING n/m" counts the deck's own rows; a variant's walk entry is its quote id (M10).
  it("counts a variant's pricing in the deck's progress", function()
    kinds[222] = false
    stack(1, 222, 1, BONUSED)
    slotKeys["0:1"] = key(222, 619)
    compose()
    GC.Sell.Refresh(true)
    local refresh = upvalue(GC.Sell.Refresh, "refresh")
    local _, total = refresh.deckProgress()
    assert.equal(1, total)
  end)

  -- At the auction house, a stack the client has classified but will not key: when the auction
  -- house says it cannot take it, it is not tradeable stock at all; when it can, the heading
  -- says what is actually missing rather than "open the auction house" (M10).
  it("asks the auction house, while it is open, whether an unkeyable stack can ever be posted", function()
    GC.Sniper.IsAHOpen = function() return true end
    kinds[444] = false
    kinds[555] = false
    stack(1, 444, 1, BONUSED, { itemName = "Relic" })
    stack(2, 555, 1, BONUSED, { itemName = "Oddity" })
    local displayErrors = {}
    _G.C_AuctionHouse.IsSellItemValid = function(location, displayError)
      displayErrors[#displayErrors + 1] = displayError
      return location.slot == 2
    end
    compose()
    local head, items = nil, {}
    for _, row in ipairs(upvalue(render, "rows")) do
      if row:IsShown() and row.kind == "waitHead" then head = row end
      if row:IsShown() and row.kind == "waitItem" then items[#items + 1] = row.sectionLabel.text end
    end
    assert.equal(1, #items)
    assert.matches("Oddity", items[1], 1, true)
    assert.matches("the auction house has not sent details for these yet", head.sectionLabel.text, 1, true)
    -- Asked quietly: with its error display on, every compose at the auction house put the red
    -- "can't auction" error and its sound on screen, once a second through a Sell walk (N1).
    assert.is_true(#displayErrors > 0)
    for _, displayError in ipairs(displayErrors) do assert.is_false(displayError) end
  end)
end)
