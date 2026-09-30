local helper = require("spec.spec_helper")

-- UI/SoldFrame.lua against the real UI/Theme.lua. The widget doubles below carry only methods
-- the client's widgets have, plus a crude font model -- a character is 0.6 of the font size
-- wide, a line 1.2 of it tall -- so the tab's own measuring (GetUnboundedStringWidth,
-- GetStringHeight) has something to measure, and the fit rules can be checked: no column
-- narrower than its text, nothing laid over a neighbour.
--
-- `points`, `scripts` and `children` are bookkeeping only these doubles define (see
-- ui_widget_field_spec.lua's DOUBLE_ONLY guard); production code never reads them.
describe("SoldFrame", function()
  local GC, tooltip, host
  local NOW -- a Wednesday afternoon, local time

  local function visibleText(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  local function charCount(text)
    local _, n = visibleText(text):gsub("[^\128-\191]", "")
    return n
  end

  local function region(kind, parent)
    local r = { __frame = true, kind = kind, children = {}, visible = true, points = {}, scripts = {},
      size = 12, alpha = 1 }
    if parent then parent.children[#parent.children + 1] = r end
    r.parent = parent
    function r:IsVisible() return self.visible and (not self.parent or self.parent:IsVisible()) end
    function r:SetDrawLayer(layer, sub) self.layer, self.subLevel = layer, sub end
    function r:SetPoint(point, relative, relativePoint, x, y)
      if type(relative) == "number" then relative, relativePoint, x, y = nil, nil, relative, relativePoint end
      self.points[#self.points + 1] = { point = point, relative = relative, relativePoint = relativePoint,
        x = x or 0, y = y or 0 }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() self.points[#self.points + 1] = { point = "ALL" } end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    -- As in the client: on a texture, SetAlpha writes the same alpha SetVertexColor set.
    function r:SetAlpha(a)
      self.alpha = a
      if self.vertexColor then self.vertexColor[4] = a end
    end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:EnableMouse() end
    function r:RegisterForClicks() end
    function r:Enable() end
    function r:Disable() end
    function r:SetScrollChild() end
    function r:CreateTexture() return region("Texture", self) end
    function r:CreateFontString() return region("FontString", self) end
    -- Texture
    function r:SetTexture(f) self.texture, self.colorTexture = f, nil end
    function r:SetTexCoord() end
    function r:SetTextureSliceMargins() end
    function r:SetVertexColor(...) self.vertexColor = { ... } end
    function r:SetColorTexture(...) self.colorTexture, self.texture = { ... }, nil end
    function r:SetBlendMode() end
    -- FontString / EditBox
    function r:SetFont(path, size) self.font, self.size = path, size; return true end
    function r:GetFont() return self.font or "Fonts\\FRIZQT__.TTF", self.size, "" end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:SetTextColor(...) self.colorValue = { ... } end
    function r:SetWordWrap(on) self.wrap = on end
    function r:SetMaxLines(n) self.maxLines = n end
    function r:SetNonSpaceWrap(on) self.nonSpaceWrap = on end
    function r:GetUnboundedStringWidth() return charCount(self.textValue) * self.size * 0.6 end
    function r:GetStringHeight()
      if charCount(self.textValue) == 0 then return 0 end
      local lines = 1
      if self.wrap and self.width and self.width > 0 then
        lines = math.max(1, math.ceil(self:GetUnboundedStringWidth() / self.width))
      end
      return lines * self.size * 1.2
    end
    function r:SetAutoFocus() end
    function r:HasFocus() return false end
    function r:ClearFocus() end
    return r
  end

  local function load(locale)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/SoldView.lua", GC)
    helper.loadModule("UI/Theme.lua", GC)
    if locale then
      helper.loadModule("Locale/" .. locale .. ".lua", GC)
      GC.ActivateLocale(locale)
    end
    GC.AppLedger = { GetSummary = function() return nil end }
    GC.Ledger = { GetEntries = function() return {} end }
    GC.Acquisitions = { GetRealized = function() return {} end, SourcesOf = function() return {} end }
    helper.loadModule("UI/SoldFrame.lua", GC)
    host = region("Frame")
    GC.Sold.Attach(host, { panelLeft = 88, panelRightInset = 32, top = -36, bottom = 12,
      rowWidth = 600, rowHeight = 32 })
  end

  before_each(function()
    NOW = os.time({ year = 2026, month = 9, day = 30, hour = 15, min = 20 })
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.time = function() return NOW end
    _G.date = os.date
    tooltip = { lines = {} }
    -- As in the client, SetOwner starts a fresh tooltip.
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines, self.title = owner, anchor, {}, nil end
    function tooltip:GetOwner() return self.owner end
    function tooltip:IsShown() return self.shown end
    function tooltip:SetItemByID(id) self.itemID = id end
    function tooltip:SetText(text) self.title = text end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.shown = false end
    _G.GameTooltip = tooltip
    load()
  end)

  after_each(function()
    _G.CreateFrame, _G.date, _G.GameTooltip, _G.C_Item = nil, nil, nil, nil
    _G.time = os.time
  end)

  local function view() return GC.Sold._view end
  local function show() GC.Sold.Show() end

  local function shownRows(kind)
    local out = {}
    for _, row in ipairs(view().rows) do
      if row:IsShown() and (not kind or row.kind == kind) then out[#out + 1] = row end
    end
    return out
  end

  local function saleRow(name)
    for _, row in ipairs(shownRows("sale")) do
      if visibleText(row.name:GetText()) == name then return row end
    end
  end

  local function headRow(title)
    for _, row in ipairs(shownRows("head")) do
      if visibleText(row.title:GetText()) == title then return row end
    end
  end

  local function listText()
    local out = {}
    for _, row in ipairs(shownRows()) do
      local parts = {}
      for _, fs in ipairs({ row.name, row.title, row.note, row.wide, row.cells.when, row.cells.each,
          row.cells.got, row.cells.profit }) do
        if fs:IsShown() then parts[#parts + 1] = visibleText(fs:GetText()) end
      end
      out[#out + 1] = table.concat(parts, " | ")
    end
    return table.concat(out, "\n")
  end

  local function same(a, b)
    return a ~= nil and b ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
  end

  local function summary(over)
    local s = {
      generatedAt = NOW - 3600, pro = true, days = 30,
      totals = { proceeds = 95, spent = 50, pending = 7, salesCount = 1, realized = 25 },
      sales = { { name = "Server Ore", item = 5, qty = 2, total = 100, cut = 5, pending = false, at = NOW - 7200,
        basis = { matched = 2, unmatched = 0, cost = 50, profit = 45 } } },
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end

  local function sale(over)
    local e = { kind = "sale", itemName = "Linen Cloth", qty = 14, total = 1050, cut = 53, pending = false,
      at = NOW - 600, key = "k1" }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
  end

  local function forever() GC.Game = { IsForever = function() return true end, Passport = function() return {} end } end

  describe("the two honest sections (retail)", function()
    it("offers to pair the Companion when there is no snapshot", function()
      show()
      assert.truthy(listText():find("Pair or update the GoldCap Companion", 1, true))
    end)

    it("splits local rows at the snapshot's newest sale, not its generatedAt", function()
      GC.AppLedger.GetSummary = function() return summary() end
      GC.Ledger.GetEntries = function()
        return {
          sale({ itemName = "Covered", at = NOW - 7200, key = "k-old" }),            -- the server has it
          sale({ itemName = "In The Gap", at = NOW - 5000, key = "k-gap" }),        -- older than generatedAt
          sale({ itemName = "New Local", at = NOW - 60, key = "k-new", pending = true }),
        }
      end
      show()
      assert.truthy(headRow("JUST SOLD"))
      assert.equal("reaches goldcap.gg on /reload or logout", headRow("JUST SOLD").note:GetText())
      assert.truthy(saleRow("New Local"))
      assert.truthy(saleRow("In The Gap"))
      assert.is_nil(saleRow("Covered"))
      assert.truthy(headRow("ON GOLDCAP.GG"))
      assert.equal("last 30 days", headRow("ON GOLDCAP.GG").note:GetText())
      assert.truthy(saleRow("Server Ore"))
    end)

    it("admits the snapshot is a tail when the server holds more than it listed", function()
      GC.AppLedger.GetSummary = function()
        return summary({ totals = { proceeds = 95, spent = 0, pending = 0, salesCount = 324, realized = 25 } })
      end
      show()
      assert.equal("latest 1 of 324 · the rest on goldcap.gg", headRow("ON GOLDCAP.GG").note:GetText())
    end)

    it("shows local profit only on an exact evidence-key join, net of the sale's own cut", function()
      GC.AppLedger.GetSummary = function() return summary() end
      GC.Ledger.GetEntries = function()
        return {
          sale({ itemName = "Matched", total = 100, cut = 12, qty = 1, key = "k-match", at = NOW - 60 }),
          sale({ itemName = "Unmatched", total = 100, cut = 5, qty = 1, key = "k-none", at = NOW - 120 }),
        }
      end
      GC.Acquisitions.GetRealized = function()
        return { { evidenceKey = "k-match", profit = 40, cost = 60, quantity = 1 },
          { evidenceKey = "Unmatched", profit = 99, cost = 1, quantity = 1 } } -- a name is not a key
      end
      show()
      assert.equal("+28c", saleRow("Matched").cells.profit:GetText())    -- 40 gross - 12 cut
      assert.equal("—", saleRow("Unmatched").cells.profit:GetText())
      assert.truthy(same(saleRow("Matched").cells.profit.colorValue, GC.Theme.color.green))
    end)

    it("paints the server basis states: full, partial with its units, none, and a free account", function()
      GC.AppLedger.GetSummary = function()
        return summary({ sales = {
          { name = "Full", qty = 2, total = 100, cut = 5, at = NOW - 100, basis = { matched = 2, unmatched = 0, cost = 50, profit = 45 } },
          { name = "Part", qty = 4, total = 100, cut = 5, at = NOW - 200, basis = { matched = 1, unmatched = 3, cost = 10, profit = -12 } },
          { name = "None", qty = 1, total = 100, cut = 5, at = NOW - 300, basis = { matched = 0, unmatched = 1, cost = 0, profit = 0 } },
          { name = "Free", qty = 1, total = 100, cut = 5, at = NOW - 400 },
        } })
      end
      show()
      assert.equal("+45c", saleRow("Full").cells.profit:GetText())
      assert.equal("-12c  |cff9d9d9d1/4|r", saleRow("Part").cells.profit:GetText())
      assert.truthy(same(saleRow("Part").cells.profit.colorValue, GC.Theme.color.red))
      assert.equal("—", saleRow("None").cells.profit:GetText())
      assert.equal("", saleRow("Free").cells.profit:GetText())
    end)

    it("dates older rows and times today's, and says 'in the mail' in gold while the money is out", function()
      GC.AppLedger.GetSummary = function() return summary({ sales = {
        { name = "Last Week", qty = 1, total = 100, cut = 5, at = NOW - 5 * 86400 } } }) end
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Pending", pending = true, at = NOW - 60 }),
          sale({ itemName = "Today", at = NOW - 3600, key = "k2" }) }
      end
      show()
      assert.equal("in the mail", saleRow("Pending").cells.when:GetText())
      assert.truthy(same(saleRow("Pending").cells.when.colorValue, GC.Theme.color.goldHi))
      assert.equal(os.date("%H:%M", NOW - 3600), saleRow("Today").cells.when:GetText())
      local t = os.date("*t", NOW - 5 * 86400)
      assert.equal(("%d/%d"):format(t.month, t.day), saleRow("Last Week").cells.when:GetText())
    end)

    it("shows the free-account notice and says nothing about profit on its rows", function()
      GC.AppLedger.GetSummary = function()
        return summary({ pro = false, totals = { proceeds = 95, spent = 0, pending = 0, salesCount = 1 },
          sales = { { name = "Server Ore", qty = 2, total = 100, cut = 5, at = NOW - 60 } } })
      end
      show()
      assert.truthy(listText():find("Profit tracking is a goldcap.gg Pro feature", 1, true))
      assert.equal("", saleRow("Server Ore").cells.profit:GetText())
    end)
  end)

  describe("the tiles", function()
    it("sum what reached the mailbox and the profit GoldCap knows, over the period's rows", function()
      GC.Ledger.GetEntries = function()
        return {
          sale({ itemName = "A", total = 1000, cut = 50, qty = 1, key = "a" }),
          sale({ itemName = "B", total = 500, cut = 25, qty = 1, key = "b", at = NOW - 2 * 86400 }),
          sale({ itemName = "Old", total = 9999, cut = 0, qty = 1, key = "old", at = NOW - 12 * 86400 }),
        }
      end
      GC.Acquisitions.GetRealized = function() return { { evidenceKey = "a", profit = 300, cost = 700, quantity = 1 } } end
      show()
      local got, profit = view().tiles[1], view().tiles[2]
      assert.equal("YOU GOT · 7 DAYS", got.label:GetText())
      assert.equal("14s 25c", visibleText(got.value:GetText()))            -- 950 + 475
      assert.equal("2 sales · after the AH cut", got.sub:GetText())
      assert.equal("PROFIT", profit.label:GetText())
      assert.equal("+2s 50c", profit.value:GetText())                     -- 300 - 50 cut
      assert.equal("cost known for 1 of 2", profit.sub:GetText())
    end)

    it("say so when the snapshot's list stops short of the period", function()
      GC.AppLedger.GetSummary = function()
        return summary({ totals = { proceeds = 95, spent = 0, pending = 0, salesCount = 324, realized = 25 },
          sales = { { name = "Recent", qty = 1, total = 100, cut = 5, at = NOW - 3600 },
            { name = "Old", qty = 1, total = 100, cut = 5, at = NOW - 20 * 86400 } } })
      end
      -- Seven days start after the oldest listed sale: every sale in them is on the list.
      show()
      assert.equal("1 sale · after the AH cut", view().tiles[1].sub:GetText())
      -- Thirty reach past it, and the server holds 322 sales it did not list.
      GC.Sold._state.period = "30d"
      GC.Sold.RefreshIfShown()
      assert.equal("2 here · all on goldcap.gg", view().tiles[1].sub:GetText())
    end)

    it("dash the profit when no cost is known", function()
      GC.Ledger.GetEntries = function() return { sale() } end
      show()
      assert.equal("—", view().tiles[2].value:GetText())
      assert.equal("cost known for 0 of 1", view().tiles[2].sub:GetText())
    end)

    it("show goldcap.gg's own realized profit on retail, coloured by how stale the sync is", function()
      GC.AppLedger.GetSummary = function() return summary({ generatedAt = NOW - 12 * 3600 }) end
      show()
      local tile = view().tiles[3]
      assert.equal("GOLDCAP.GG · 30 DAYS", tile.label:GetText())
      assert.equal("+25c", tile.value:GetText())
      assert.equal("profit · synced 12h ago", tile.sub:GetText())
      assert.truthy(same(tile.sub.colorValue, GC.Theme.tier.SUSPECT))
    end)

    it("name the best sale when there is no snapshot", function()
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Small", key = "s", qty = 1 }), sale({ itemName = "Big", key = "b", qty = 1, at = NOW - 60 }) }
      end
      GC.Acquisitions.GetRealized = function()
        return { { evidenceKey = "s", profit = 100, cost = 1, quantity = 1 },
          { evidenceKey = "b", profit = 900, cost = 1, quantity = 1 } }
      end
      show()
      local tile = view().tiles[3]
      assert.equal("BEST SALE", tile.label:GetText())
      assert.equal("Big", tile.name:GetText())
      assert.equal("+8s 47c profit", tile.sub:GetText())                    -- 900 - 53 cut
    end)

    describe("on WoW: Forever", function()
      before_each(forever)

      it("head the third tile with Road to 40 and a bar when the riding cost is set", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 471800, bags = 349200, cost = 900000 } end,
          Lines = function() return { "Road to 40: ...", "At your pace you reach it at level 12." } end }
        show()
        local tile = view().tiles[3]
        assert.equal("ROAD TO 40", tile.label:GetText())
        assert.equal("82g 10s of 90g", visibleText(tile.small:GetText()))
        assert.is_true(tile.bar:IsShown())
        assert.near(0.912, tile.progress, 0.001)
        -- The forecast is on hover, as the chat sentences /gc mount prints.
        tile.frame.scripts.OnEnter(tile.frame)
        assert.same({ "Road to 40: ...", "At your pace you reach it at level 12." }, tooltip.lines)
      end)

      it("asks for the riding cost before one is set", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 4718, bags = 3492 } end }
        show()
        local tile = view().tiles[3]
        assert.equal("82s 10c · gold 47s 18c, bags 34s 92c", visibleText(tile.small:GetText()))
        assert.equal("set the riding cost: /gc mount 90g", visibleText(tile.sub:GetText()))
        assert.is_false(tile.bar:IsShown())
      end)

      it("shows the banner for bag items worth more on the auction house, with a way to SELL", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 1, bags = 1, gain = 103, gainItems = 5 } end }
        local shownView
        GC.Sniper = { ShowView = function(v) shownView = v end }
        show()
        local banner = view().banner
        assert.is_true(banner.frame:IsShown())
        assert.equal("Items in your bags that fetch more on the auction house than at a vendor: 5 (1s 3c more).",
          visibleText(banner.text:GetText()))
        assert.equal("OPEN SELL", banner.button.text:GetText())
        -- The button is as wide as its label, and the sentence wraps in what it leaves.
        assert.is_true(banner.button.width >= banner.button.text:GetUnboundedStringWidth())
        banner.button.scripts.OnClick(banner.button)
        assert.equal("sell", shownView)
        GC.Sniper = nil
      end)

      it("has no banner when nothing in the bags sells for more", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 1, bags = 1, gain = 0, gainItems = 0 } end }
        show()
        assert.is_false(view().banner.frame:IsShown())
      end)
    end)
  end)

  describe("WoW: Forever's list", function()
    before_each(forever)

    it("groups the local sales by day, with each day's count and sum, and never reads a snapshot", function()
      GC.AppLedger.GetSummary = function() error("a snapshot read on Forever") end
      GC.Ledger.GetEntries = function()
        return {
          sale({ itemName = "Linen Cloth", at = NOW - 600, key = "a", total = 1050, cut = 53 }),
          sale({ itemName = "Red Dye", at = NOW - 2 * 3600, key = "b", total = 860, cut = 43, qty = 10 }),
          sale({ itemName = "Wool Cloth", at = NOW - 86400, key = "c", total = 620, cut = 31, qty = 20 }),
          sale({ itemName = "Bleach", at = NOW - 4 * 86400, key = "d", total = 140, cut = 7, qty = 5 }),
        }
      end
      show()
      assert.is_nil(listText():find("Pair or update", 1, true))
      assert.equal("2 sales · 18s 14c", headRow("TODAY").note:GetText())      -- 997 + 817
      assert.equal("1 sale · 5s 89c", headRow("YESTERDAY").note:GetText())
      local t = os.date("*t", NOW - 4 * 86400)
      local older = ({ "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" })[t.wday] .. (", %d/%d"):format(t.month, t.day)
      assert.truthy(headRow(older))
      assert.equal(os.date("%H:%M", NOW - 600), saleRow("Linen Cloth").cells.when:GetText())
      -- Day rows sit above their own sales.
      local order = {}
      for _, row in ipairs(shownRows()) do
        order[#order + 1] = row.kind == "head" and visibleText(row.title:GetText()) or visibleText(row.name:GetText())
      end
      assert.same({ "TODAY", "Linen Cloth", "Red Dye", "YESTERDAY", "Wool Cloth", older, "Bleach" }, order)
    end)
  end)

  describe("period and search", function()
    before_each(function()
      forever()
      GC.Ledger.GetEntries = function()
        return {
          sale({ itemName = "Linen Cloth", at = NOW - 600, key = "a" }),
          sale({ itemName = "Льняная ткань", at = NOW - 3 * 86400, key = "b" }),
          sale({ itemName = "Wool Cloth", at = NOW - 20 * 86400, key = "c" }),
        }
      end
    end)

    it("opens on seven days and switches with the chips", function()
      show()
      local chips = view().controls.chips
      assert.equal("7 DAYS", chips["7d"].text:GetText())
      assert.truthy(saleRow("Льняная ткань"))
      assert.is_nil(saleRow("Wool Cloth"))
      chips.today.scripts.OnClick(chips.today)
      assert.is_nil(saleRow("Льняная ткань"))
      assert.equal("YOU GOT · TODAY", view().tiles[1].label:GetText())
      chips["30d"].scripts.OnClick(chips["30d"])
      assert.truthy(saleRow("Wool Cloth"))
    end)

    it("filters every section by name, ignoring case in any script, and the tiles follow", function()
      show()
      local search = view().controls.search
      search:SetText("ЛЬН")
      search.scripts.OnTextChanged(search, true)
      assert.truthy(saleRow("Льняная ткань"))
      assert.is_nil(saleRow("Linen Cloth"))
      assert.equal("1 sale · after the AH cut", view().tiles[1].sub:GetText())
      search:SetText("")
      search.scripts.OnEscapePressed(search)
      assert.truthy(saleRow("Linen Cloth"))
    end)

    it("says when a search finds nothing, and offers the whole 30 days", function()
      show()
      local search = view().controls.search
      search:SetText("wool")
      search.scripts.OnTextChanged(search, true)
      local empty = view().empty
      assert.is_true(empty.frame:IsShown())
      assert.equal("No sales match “wool” in these 7 days.", empty.message:GetText())
      assert.equal("SEARCH 30 DAYS", empty.button.text:GetText())
      empty.button.scripts.OnClick(empty.button)
      assert.equal("30d", GC.Sold._state.period)
      assert.truthy(saleRow("Wool Cloth"))
      assert.is_false(empty.frame:IsShown())
    end)
  end)

  it("says where sales come from before there are any", function()
    show()
    local empty = view().empty
    assert.is_true(empty.frame:IsShown())
    assert.equal("Your sales show up here once you open a mailbox with GoldCap loaded.", empty.message:GetText())
    assert.equal("List something in SELL first.", empty.sub:GetText())
    assert.is_false(empty.button:IsShown())
  end)

  describe("the item behind a row", function()
    it("shows the sale's own card: the name, the breakdown, the cost and the market", function()
      _G.C_Item = { GetItemIconByID = function() return 135 end, GetItemQualityByID = function() return 1 end }
      GC.Data = { GetItemValue = function(id) return id == 2589 and { mv = 70, source = "import" } or nil end }
      GC.Ledger.GetEntries = function() return { sale({ key = "k1" }) } end
      GC.Acquisitions.GetRealized = function()
        return { { evidenceKey = "k1", profit = 378, cost = 672, quantity = 14, positionKey = "commodity:2589" } }
      end
      GC.Acquisitions.SourcesOf = function(key) return key == "k1" and { "goldcap" } or {} end
      show()
      local row = saleRow("Linen Cloth")
      assert.equal(135, row.icon.texture)
      row.scripts.OnEnter(row)
      assert.equal(row, tooltip.owner)
      assert.is_nil(tooltip.itemID)                          -- never the item's whole tooltip
      assert.equal("Linen Cloth", tooltip.title)
      assert.same({
        " ",
        "sold today at " .. os.date("%H:%M", NOW - 600) .. ", 14 × 75c",
        "Sale price | 10s 50c",
        "Auction house cut | -53c",
        "You got | 9s 97c",
        " ",
        "You paid (Sniper) | 6s 72c",
        "48c each",
        "Profit | +3s 25c",
        "Market now 70c, you sold 7% above it",
      }, tooltip.lines)
    end)

    it("never compares a sale with a realm item's or a gear piece's one-version figure", function()
      GC.Data = { GetItemValue = function(id)
        if id == 1 then return { mv = 900, kind = "realm_item", source = "import" } end
        return { mv = 900, gear = true, source = "scan" }
      end }
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Realm", itemID = 1, key = "r" }), sale({ itemName = "Gear", itemID = 2, key = "g", at = NOW - 60 }) }
      end
      show()
      for _, name in ipairs({ "Realm", "Gear" }) do
        tooltip.lines = {}
        local row = saleRow(name)
        row.scripts.OnEnter(row)
        for _, text in ipairs(tooltip.lines) do assert.is_nil(text:find("Market now", 1, true), name) end
      end
    end)

    it("names a sale it has only a name for, and never prices it", function()
      _G.C_Item = { GetItemInfoInstant = function(name) if name == "Red Dye" then return 2604, "", "", "", 777 end end,
        GetItemInfo = function() return nil end }
      GC.Data = { GetItemValue = function() error("priced by name") end }
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Red Dye", key = "x", cut = false, total = 860, qty = 10 }) } end
      show()
      local row = saleRow("Red Dye")
      assert.equal(777, row.icon.texture)                   -- the icon may come from the name
      row.scripts.OnEnter(row)
      assert.is_nil(tooltip.itemID)                          -- the item tooltip may not
      assert.equal("Red Dye", tooltip.title)
      assert.equal("Auction house cut, 5% | -43c", tooltip.lines[4])
      assert.equal("GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL.",
        tooltip.lines[7])
      assert.equal(8, #tooltip.lines + 1)                    -- and no market line
    end)

    it("shows an empty slot, never the red question mark, for an item nothing can name", function()
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Mystery", key = "m", pending = true }) } end
      show()
      local row = saleRow("Mystery")
      assert.is_nil(row.icon.texture)
      assert.same({ 1, 1, 1, 0.05 }, row.icon.colorTexture)
      row.scripts.OnEnter(row)
      assert.equal("The profit is worked out once the money arrives.", tooltip.lines[#tooltip.lines])
      assert.equal("sold, the money is in your mail, 14 × 75c", tooltip.lines[2])
    end)

    it("finds a mail sale's item among the character's own listings, and only an unambiguous one", function()
      _G.C_Item = { GetItemIconByID = function(id) return id * 10 end, GetItemQualityByID = function() return 1 end }
      GC.Acquisitions.GetActivities = function()
        return {
          { itemName = "Linen Cloth", itemID = 2589, character = "Me-Realm", region = "us" },
          { itemName = "Linen Cloth", itemID = 2589, character = "Alt-Realm", region = "us" },
          { itemName = "Hochenblume", itemID = 191460, character = "Me-Realm", region = "us" },
          { itemName = "Hochenblume", itemID = 191461, character = "Me-Realm", region = "us" },
        }
      end
      GC.Ledger.GetEntries = function()
        return {
          sale({ itemName = "Linen Cloth", key = "a", char = "Me-Realm", region = "us" }),
          sale({ itemName = "Hochenblume", key = "b", char = "Me-Realm", region = "us", at = NOW - 60 }),
        }
      end
      show()
      local linen = saleRow("Linen Cloth")
      assert.equal(25890, linen.icon.texture)
      assert.equal(2589, linen.info.id)
      -- Two ranks under one name: no id, so no icon from it and no market line.
      local herb = saleRow("Hochenblume")
      assert.is_nil(herb.icon.texture)
      assert.is_nil(herb.info.id)
    end)

    it("draws the hover wash under the text, faint, only while a sale row is under the cursor", function()
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Linen Cloth", key = "a" }) } end
      show()
      local row = saleRow("Linen Cloth")
      assert.equal("BACKGROUND", row.highlight.layer)
      assert.is_false(row.highlight:IsShown())
      row.scripts.OnEnter(row)
      assert.is_true(row.highlight:IsShown())
      assert.equal(GC.Theme.color.hover[4], row.highlight.vertexColor[4])
      row.scripts.OnLeave(row)
      assert.is_false(row.highlight:IsShown())
      for _, head in ipairs(shownRows("head")) do
        head.scripts.OnEnter(head)
        assert.is_false(head.highlight:IsShown())
      end
    end)

    it("follows a re-render under a still cursor: the new sale's card, or no tooltip on a heading", function()
      local entries = { sale({ itemName = "Linen Cloth", key = "a" }) }
      GC.Ledger.GetEntries = function() return entries end
      show()
      local row = saleRow("Linen Cloth")
      row.scripts.OnEnter(row)
      entries = { sale({ itemName = "Wool Cloth", key = "b" }) }
      GC.Sold.RefreshIfShown()
      if row.sale then
        assert.equal(row.sale.name, tooltip.title)
      else
        assert.is_false(tooltip.shown)
      end
      assert.equal("Wool Cloth", saleRow("Wool Cloth").sale.name)
    end)

    it("colours an uncommon or better item's name and border in its quality", function()
      _G.C_Item = { GetItemIconByID = function() return 1 end, GetItemQualityByID = function() return 2 end,
        GetItemQualityColor = function() return 0.12, 1, 0 end }
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Boots", itemID = 2315, key = "q" }) } end
      show()
      local row = saleRow("Boots")
      assert.same({ 0.12, 1, 0, 1 }, row.name.colorValue)
      assert.same({ 0.12, 1, 0, 0.6 }, row.iconEdge.colorTexture)
    end)
  end)

  describe("fit", function()
    local function layoutOf(row, width)
      -- Each shown figure cell's left and right edge, from its RIGHT anchor and its width.
      local boxes = {}
      for _, key in ipairs({ "when", "each", "got", "profit" }) do
        local cell = row.cells[key]
        if cell:IsShown() then
          local right = width + cell.points[1].x
          boxes[#boxes + 1] = { key = key, left = right - cell.width, right = right, cell = cell }
        end
      end
      return boxes
    end

    local function assertFits(width)
      for _, row in ipairs(shownRows("sale")) do
        local boxes = layoutOf(row, width)
        for i, box in ipairs(boxes) do
          assert.is_true(box.cell.width >= box.cell:GetUnboundedStringWidth(),
            ("%s is cut: %q"):format(box.key, box.cell:GetText()))
          if boxes[i + 1] then assert.is_true(box.right <= boxes[i + 1].left, box.key .. " overlaps") end
        end
        -- ITEM: icon, name and count all end before the first figure column starts.
        local itemRight = 10 + 26 + 10 + row.name.width + (row.qty:IsShown() and (6 + row.qty.width) or 0)
        assert.is_true(itemRight <= boxes[1].left, "the item runs into " .. boxes[1].key)
      end
      for key, label in pairs(view().header.cells) do
        if key ~= "item" and label:IsShown() then
          assert.is_true(label.width >= label:GetUnboundedStringWidth(), key .. " heading is cut")
        end
      end
    end

    local function bigSales()
      GC.AppLedger.GetSummary = function()
        return summary({ totals = { proceeds = 4326100000, spent = 0, pending = 0, salesCount = 2, realized = 1360350000 },
          sales = {
            { name = "Dark Leather Boots", item = 2315, qty = 1, total = 94000000, cut = 4700000, at = NOW - 86400,
              basis = { matched = 1, unmatched = 0, cost = 22360000, profit = 66940000 } },
            { name = "Wool Cloth", item = 2592, qty = 400, total = 8200000, cut = 410000, at = NOW - 2 * 86400,
              basis = { matched = 400, unmatched = 0, cost = 8170000, profit = -380000 } },
          } })
      end
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Linen Cloth", total = 2400000, cut = 120000, qty = 200, pending = true }) }
      end
    end

    it("never cuts a figure or lays one over another, retail-sized values included", function()
      bigSales()
      show()
      assertFits(600)
      assert.equal("+6,694g", saleRow("Dark Leather Boots").cells.profit:GetText())
      assert.equal("-38g", saleRow("Wool Cloth").cells.profit:GetText())
    end)

    for _, locale in ipairs({ "ruRU", "ukUA", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "koKR", "zhCN", "zhTW" }) do
      it(("fits in %s at the narrowest window"):format(locale), function()
        load(locale)
        bigSales()
        view().container.width = 520
        show()
        assertFits(520)
        -- Every tile line is a wrapped box as wide as the tile's inside, never wider.
        for _, tile in ipairs(view().tiles) do
          for _, fs in ipairs({ tile.label, tile.value, tile.small, tile.sub }) do
            if fs:IsShown() then
              assert.is_true(fs.wrap, "a tile line that cannot wrap")
              assert.is_true(fs.width <= tile.frame.width - 28)
            end
          end
          assert.is_true(tile.frame.height >= 74)
        end
      end)
    end

    it("drops WHEN first and then EACH, rather than squeezing ITEM, and brings them back", function()
      bigSales()
      local container = view().container
      container.width = 330
      show()
      local row = saleRow("Dark Leather Boots")
      assert.is_false(row.cells.when:IsShown())
      container.width = 250
      GC.Sold.RefreshIfShown()
      assert.is_false(row.cells.each:IsShown())
      assert.is_true(row.cells.profit:IsShown())
      container.width = 700
      GC.Sold.RefreshIfShown()
      assert.is_true(row.cells.when:IsShown())
      assert.is_true(row.cells.each:IsShown())
      assertFits(700)
    end)

    it("steps a tile's figure down to the smaller face when the big one would not fit", function()
      GC.AppLedger.GetSummary = function()
        return summary({ totals = { proceeds = 0, spent = 0, pending = 0, salesCount = 1, realized = 12345670000 } })
      end
      GC.Theme.SetScale(1.3)
      view().container.width = 520
      show()
      local tile = view().tiles[3]
      assert.is_false(tile.value:IsShown())
      assert.is_true(tile.small:IsShown())
      assert.equal("+1,234,567g", tile.small:GetText())
      assert.is_true(tile.small.width >= tile.small:GetUnboundedStringWidth())
      assert.truthy(same(tile.small.colorValue, GC.Theme.color.green))
      GC.Theme.SetScale(1)
    end)

    it("wraps a long item name inside ITEM and grows its row, instead of cutting it", function()
      local long = "Reinforced Everbloom-Stitched Leggings of the Unyielding Tidal Serpent"
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = long, key = "l", qty = 1 }),
          sale({ itemName = "Linen Cloth", key = "s", qty = 1, at = NOW - 60 }) }
      end
      show()
      local row = saleRow(long)
      assert.is_true(row.name.wrap)
      assert.is_true(row.name.width < row.name:GetUnboundedStringWidth())
      assert.is_true(row.height >= row.name:GetStringHeight() + 10, "the row is shorter than the wrapped name")
      assert.is_true(row.height > 34)
      assertFits(600)
      -- A short name on the next row stays one line at the usual height.
      local short = saleRow("Linen Cloth")
      assert.is_false(short.name.wrap)
      assert.equal(34, short.height)
      row.scripts.OnEnter(row)
      assert.equal(long, tooltip.title)
    end)
  end)

  it("hides the window's shared status line while it is up, and hands it back drawn", function()
    local status = region("FontString", host)
    status:SetText("scanning auction house...")
    host.status = status
    GC.Sold.Attach(host, { panelLeft = 88, panelRightInset = 32, top = -36, bottom = 12, rowWidth = 600, rowHeight = 32 })
    show()
    assert.is_false(status:IsShown())
    local writes = {}
    local orig = status.SetText
    status.SetText = function(self, text) writes[#writes + 1] = text; return orig(self, text) end
    GC.Sold.Hide()
    assert.is_true(status:IsShown())
    assert.same({ "", "scanning auction house..." }, writes)
  end)

  describe("the headings", function()
    it("read ITEM / WHEN / EACH / YOU GOT / PROFIT", function()
      show()
      local cells = view().header.cells
      assert.same({ "ITEM", "WHEN", "EACH", "YOU GOT", "PROFIT" },
        { cells.item:GetText(), cells.when:GetText(), cells.each:GetText(), cells.got:GetText(), cells.profit:GetText() })
    end)

    -- A one-line string that sat under a hidden parent can come back undrawn, and SetText with
    -- the text it holds is a no-op: every string is cleared before it is written again.
    it("clears each heading before stamping it again when the tab is shown", function()
      show()
      local seen = {}
      for key, label in pairs(view().header.cells) do
        seen[key] = {}
        local orig = label.SetText
        label.SetText = function(self, text) seen[key][#seen[key] + 1] = text; return orig(self, text) end
      end
      GC.Sold.Hide()
      show()
      for key, calls in pairs(seen) do
        assert.equal("", calls[1], key .. ": not cleared before the restamp")
        assert.is_true(#calls >= 2 and calls[2] ~= "", key .. ": not stamped after the clear")
      end
    end)
  end)
end)
