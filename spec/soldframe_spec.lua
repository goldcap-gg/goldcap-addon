local helper = require("spec.spec_helper")

-- UI/SoldFrame.lua and the receipt it opens (UI/SoldReceipt.lua) against the real UI/Theme.lua. The widget doubles below carry only methods
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
    function r:SetShown(on) self.visible = on and true or false end
    -- As in the client: on a texture, SetAlpha writes the same alpha SetVertexColor set.
    function r:SetAlpha(a)
      self.alpha = a
      if self.vertexColor then self.vertexColor[4] = a end
    end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:EnableMouse() end
    function r:RegisterForClicks() end
    function r:SetPushedTexture(t) self.pushedTexture = t end
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
    helper.loadModule("Core/NameMatch.lua", GC)
    helper.loadModule("Core/SoldView.lua", GC)
    helper.loadModule("Core/SoldReceipt.lua", GC)
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("UI/Kit/Bar.lua", GC)
    if locale then
      helper.loadModule("Locale/" .. locale .. ".lua", GC)
      GC.ActivateLocale(locale)
    end
    GC.AppLedger = { GetSummary = function() return nil end }
    GC.Ledger = { GetEntries = function() return {} end }
    GC.Acquisitions = { GetRealized = function() return {} end, SourcesIndex = function() return {} end,
      GetActivities = function() return {} end, GetActive = function() return {} end }
    helper.loadModule("UI/SoldReceipt.lua", GC)
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
      for _, fs in ipairs({ row.name, row.sub, row.title, row.note, row.wide, row.cells.mkt,
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

  -- A left click on a row, as the client sends it.
  local function click(row) row.scripts.OnMouseUp(row, "LeftButton") end

  -- What the open receipt says, column by column, colour escapes stripped.
  local function receipt()
    local out = {}
    for i, col in ipairs(GC.SoldReceiptUI.Lines(view().receipt)) do
      out[i] = {}
      for j, text in ipairs(col) do out[i][j] = visibleText(text) end
    end
    return out
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
      assert.equal("-", saleRow("Unmatched").cells.profit:GetText())
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
      -- A goldcap.gg sale's cost is not this tab's to set: a dash, never "set cost".
      assert.equal("-", saleRow("None").cells.profit:GetText())
      assert.equal("", saleRow("Free").cells.profit:GetText())
    end)

    it("dates older rows and times today's under the name, and says 'in the mail' in gold while the money is out", function()
      GC.AppLedger.GetSummary = function() return summary({ sales = {
        { name = "Last Week", qty = 1, total = 100, cut = 5, at = NOW - 5 * 86400 } } }) end
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Pending", pending = true, at = NOW - 60 }),
          sale({ itemName = "Today", at = NOW - 3600, key = "k2" }) }
      end
      show()
      assert.equal("14 × 75c · in the mail", visibleText(saleRow("Pending").sub:GetText()))
      assert.truthy(saleRow("Pending").sub:GetText():find("|cffe8c15ain the mail|r", 1, true))
      assert.equal("14 × 75c · " .. os.date("%H:%M", NOW - 3600), saleRow("Today").sub:GetText())
      local t = os.date("*t", NOW - 5 * 86400)
      assert.equal(("1 × 1s · %d/%d"):format(t.month, t.day), saleRow("Last Week").sub:GetText())
    end)

    it("shows the free-account notice and says nothing about profit on its rows", function()
      GC.AppLedger.GetSummary = function()
        return summary({ pro = false, totals = { proceeds = 95, spent = 0, pending = 0, salesCount = 1 },
          sales = { { name = "Server Ore", qty = 2, total = 100, cut = 5, at = NOW - 60 } } })
      end
      show()
      assert.truthy(listText():find("Profit tracking is a goldcap.gg Pro feature", 1, true))
      assert.equal("", saleRow("Server Ore").cells.profit:GetText())
      click(saleRow("Server Ore"))
      local cols = receipt()
      assert.same({ "PROFIT", "Profit tracking is a goldcap.gg Pro feature" }, cols[#cols])
    end)
  end)

  describe("the cards", function()
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
      local got, profit = view().cards[1], view().cards[2]
      assert.equal("YOU GOT", got.label:GetText())
      assert.equal("14s 25c", visibleText(got.value:GetText()))            -- 950 + 475
      assert.equal("2 sales, after the cut", got.sub:GetText())
      assert.equal("PROFIT", profit.label:GetText())
      assert.equal("+2s 50c", profit.value:GetText())                     -- 300 - 50 cut
      assert.equal("1 of 2 have a cost", profit.sub:GetText())
    end)

    it("say so when the snapshot's list stops short of the period", function()
      GC.AppLedger.GetSummary = function()
        return summary({ totals = { proceeds = 95, spent = 0, pending = 0, salesCount = 324, realized = 25 },
          sales = { { name = "Recent", qty = 1, total = 100, cut = 5, at = NOW - 3600 },
            { name = "Old", qty = 1, total = 100, cut = 5, at = NOW - 20 * 86400 } } })
      end
      -- Seven days start after the oldest listed sale: every sale in them is on the list.
      show()
      assert.equal("1 sale, after the cut", view().cards[1].sub:GetText())
      -- Thirty reach past it, and the server holds 322 sales it did not list.
      GC.Sold._state.period = "30d"
      GC.Sold.RefreshIfShown()
      assert.equal("2 here · all on goldcap.gg", view().cards[1].sub:GetText())
    end)

    it("dash the profit when no cost is known", function()
      GC.Ledger.GetEntries = function() return { sale() } end
      show()
      assert.equal("-", view().cards[2].value:GetText())
      assert.equal("0 of 1 have a cost", view().cards[2].sub:GetText())
    end)

    it("show goldcap.gg's own realized profit on retail, fourth, coloured by how stale the sync is", function()
      GC.AppLedger.GetSummary = function() return summary({ generatedAt = NOW - 12 * 3600 }) end
      show()
      local card = view().cards[4]
      assert.is_true(card.frame:IsShown())
      assert.equal("GOLDCAP.GG · 30 DAYS", card.label:GetText())
      assert.equal("+25c", card.value:GetText())
      assert.equal("profit · synced 12h ago", card.sub:GetText())
      assert.truthy(same(card.sub.colorValue, GC.Theme.tier.SUSPECT))
    end)

    it("leave the fourth out on retail with no snapshot, the three sharing the row", function()
      show()
      assert.is_false(view().cards[4].frame:IsShown())
      assert.equal(math.floor((600 - 2 * 10) / 3), view().cards[1].frame.width)
    end)

    it("name the best sale with its icon, what it brought and its profit", function()
      _G.C_Item = { GetItemIconByID = function() return 99 end, GetItemQualityByID = function() return 1 end }
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Small", key = "s", qty = 1 }), sale({ itemName = "Big", key = "b", qty = 1, at = NOW - 60 }) }
      end
      GC.Acquisitions.GetRealized = function()
        return { { evidenceKey = "s", profit = 100, cost = 1, quantity = 1, positionKey = "commodity:7" },
          { evidenceKey = "b", profit = 900, cost = 1, quantity = 1, positionKey = "commodity:8" } }
      end
      show()
      local card = view().cards[3]
      assert.equal("BEST SALE", card.label:GetText())
      assert.equal("Big", card.name:GetText())
      assert.equal(99, card.icon.texture)
      assert.equal("9s 97c", visibleText(card.small:GetText()))             -- 1050 - 53 cut
      assert.equal("+8s 47c profit", card.sub:GetText())                    -- 900 - 53 cut
    end)

    describe("on WoW: Forever", function()
      before_each(forever)

      it("head the fourth card with Road to 40, a ring with the percent in it", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 471800, bags = 349200, cost = 900000 } end,
          Lines = function() return { "Road to 40: ...", "At your pace you reach it at level 12." } end }
        show()
        local card = view().cards[4]
        assert.equal("ROAD TO 40", card.label:GetText())
        assert.equal("82g 10s / 90g", visibleText(card.small:GetText()))
        assert.is_true(card.ring:IsShown())
        assert.near(0.912, card.progress, 0.001)
        assert.equal("91%", card.ring.pct:GetText())
        local lit = 0
        for _, dot in ipairs(card.ring.dots) do
          if same(dot.colorTexture, GC.Theme.color.gold) then lit = lit + 1 end
        end
        assert.equal(15, lit)                                              -- 0.912 of 16
        -- On hover: a label and an amount a row, then the forecast sentence.
        card.frame.scripts.OnEnter(card.frame)
        assert.equal("ROAD TO 40", tooltip.title)
        local shown = {}
        for i, text in ipairs(tooltip.lines) do
          shown[i] = text:gsub("|TInterface\\MoneyFrame\\UI%-(%a)%a+Icon[%d:]*|t", function(c) return c:lower() end)
        end
        assert.same({ "Gold you carry | 47g 18s", "Your bags | 34g 92s", "Riding cost | 90g", " ",
          "At your pace you reach it at level 12." }, shown)
      end)

      it("asks for the riding cost before one is set", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 4718, bags = 3492 } end }
        show()
        local card = view().cards[4]
        assert.equal("82s 10c · gold 47s 18c, bags 34s 92c", visibleText(card.small:GetText()))
        assert.equal("set the riding cost: /gc mount 90g", visibleText(card.sub:GetText()))
        assert.is_false(card.ring:IsShown())
      end)

      it("shows one quiet line at the bottom for bag items worth more on the auction house, with a way to SELL", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 1, bags = 1, gain = 103, gainItems = 5 } end }
        local shownView
        GC.Sniper = { ShowView = function(v) shownView = v end }
        show()
        local foot = view().foot
        assert.is_true(foot.frame:IsShown())
        assert.equal("BOTTOMLEFT", foot.frame.points[1].point)
        assert.equal("Items in your bags that fetch more on the auction house than at a vendor: 5 (1s 3c more).",
          visibleText(foot.text:GetText()))
        assert.equal("OPEN SELL", foot.button.text:GetText())
        assert.is_true(foot.caret:IsShown())
        -- The button is as wide as its label and the caret, and the sentence wraps in what it leaves.
        assert.is_true(foot.button.width >= foot.button.text:GetUnboundedStringWidth() + 12)
        -- The list stops above it.
        assert.is_true(view().scroll.points[2].y >= foot.frame.height)
        foot.button.scripts.OnClick(foot.button)
        assert.equal("sell", shownView)
        GC.Sniper = nil
      end)

      it("has no bottom line when nothing in the bags sells for more", function()
        GC.ForeverRoad = { Snapshot = function() return { money = 1, bags = 1, gain = 0, gainItems = 0 } end }
        show()
        assert.is_false(view().foot.frame:IsShown())
        assert.equal(0, view().scroll.points[2].y)
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
      local today = headRow("TODAY")
      assert.equal("2 sales · 18s 14c", today.note:GetText())      -- 997 + 817
      assert.truthy(same(today.title.colorValue, GC.Theme.color.goldHi))
      -- The hairline runs from the title to the day's sum.
      assert.is_true(today.rule:IsShown())
      assert.equal(today.title, today.rule.points[1].relative)
      assert.equal(today.note, today.rule.points[2].relative)
      assert.equal("1 sale · 5s 89c", headRow("YESTERDAY").note:GetText())
      local t = os.date("*t", NOW - 4 * 86400)
      local older = ({ "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" })[t.wday] .. (", %d/%d"):format(t.month, t.day)
      assert.truthy(headRow(older))
      assert.equal("14 × 75c · " .. os.date("%H:%M", NOW - 600), saleRow("Linen Cloth").sub:GetText())
      -- Day rows sit above their own sales.
      local order = {}
      for _, row in ipairs(shownRows()) do
        order[#order + 1] = row.kind == "head" and visibleText(row.title:GetText()) or visibleText(row.name:GetText())
      end
      assert.same({ "TODAY", "Linen Cloth", "Red Dye", "YESTERDAY", "Wool Cloth", older, "Bleach" }, order)
    end)
  end)

  describe("the header: period and search", function()
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

    local function search(text)
      local box = view().head.search
      box:SetText(text)
      box.scripts.OnTextChanged(box, true)
      return box
    end

    it("names the tab as the rail does and opens on seven days, switching with the chips", function()
      show()
      local head = view().head
      assert.equal("SOLD", head.title:GetText())
      local chips = head.chips
      assert.equal("7 DAYS", chips["7d"].text:GetText())
      -- In the header row, at its right, beside the search button.
      assert.equal("TOPRIGHT", head.group.points[1].point)
      assert.truthy(saleRow("Льняная ткань"))
      assert.is_nil(saleRow("Wool Cloth"))
      chips.today.scripts.OnClick(chips.today)
      assert.is_nil(saleRow("Льняная ткань"))
      chips["30d"].scripts.OnClick(chips["30d"])
      assert.truthy(saleRow("Wool Cloth"))
    end)

    it("keeps the search box hidden until the search button reveals it, and closing it clears it", function()
      show()
      local head = view().head
      assert.is_false(head.well:IsShown())
      head.find.scripts.OnClick(head.find)
      assert.is_true(head.well:IsShown())
      assert.equal("Find an item", head.hint:GetText())
      search("wool")
      head.close.scripts.OnClick(head.close)
      assert.is_false(head.well:IsShown())
      assert.equal("", GC.Sold._state.query)
      assert.truthy(saleRow("Linen Cloth"))
    end)

    it("reads the sources of every sale from one pass, and only for the rows the period leaves", function()
      local passes = 0
      GC.Acquisitions.GetRealized = function()
        return {
          { evidenceKey = "a", profit = 10, cost = 20, quantity = 1, positionKey = "commodity:1" },
          { evidenceKey = "b", profit = 10, cost = 20, quantity = 1, positionKey = "commodity:1" },
          { evidenceKey = "c", profit = 10, cost = 20, quantity = 1, positionKey = "commodity:1" },
        }
      end
      GC.Acquisitions.SourcesIndex = function() passes = passes + 1; return { a = { "goldcap" } } end
      show()
      assert.equal(1, passes)                       -- three sales, one pass; "c" is outside 7 days
      search("nothing matches this")
      passes = 0
      search("nothing matches this")
      assert.equal(0, passes)                       -- no row left, no pass at all
    end)

    it("filters every section by name, ignoring case in any script, and the cards follow", function()
      show()
      search("ЛЬН")
      assert.truthy(saleRow("Льняная ткань"))
      assert.is_nil(saleRow("Linen Cloth"))
      assert.equal("1 sale, after the cut", view().cards[1].sub:GetText())
      local box = view().head.search
      box:SetText("")
      box.scripts.OnEscapePressed(box)
      assert.truthy(saleRow("Linen Cloth"))
    end)

    it("says when a search finds nothing, and offers the whole 30 days", function()
      show()
      search("wool")
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

  describe("the receipt a row opens into", function()
    local function costed()
      _G.C_Item = { GetItemIconByID = function() return 135 end, GetItemQualityByID = function() return 1 end }
      GC.Data = { GetItemValue = function(id) return id == 2589 and { mv = 70, source = "import" } or nil end }
      GC.Ledger.GetEntries = function() return { sale({ key = "k1" }) } end
      GC.Acquisitions.GetRealized = function()
        return { { evidenceKey = "k1", profit = 378, cost = 672, quantity = 14, positionKey = "commodity:2589" } }
      end
      GC.Acquisitions.SourcesIndex = function() return { k1 = { "goldcap" } } end
    end

    it("opens on a click with the three columns -- never a tooltip, never the item's own", function()
      costed()
      show()
      local row = saleRow("Linen Cloth")
      assert.equal(135, row.icon.texture)
      row.scripts.OnEnter(row)
      assert.is_nil(tooltip.owner)                           -- hover only lights the row
      assert.is_true(row.highlight:IsShown())
      assert.is_false(view().receipt.frame:IsShown())
      click(row)
      row = saleRow("Linen Cloth")
      assert.is_true(row.isOpen)
      assert.is_true(view().receipt.frame:IsShown())
      assert.is_true(row.outline:IsShown())
      assert.is_nil(tooltip.itemID)
      assert.same({
        { "RECEIPT", "sold today at " .. os.date("%H:%M", NOW - 600), "14 sold at 75c | 10s 50c",
          "Auction house | -53c", "- - -", "You got | 9s 97c" },
        { "AGAINST TODAY'S MARKET", "7% above", "market 70c", "you 75c" },
        { "PROFIT", "You paid (Sniper) | 6s 72c", "48c each", "Profit | +3s 25c" },
      }, receipt())
      -- The receipt hangs under the row's own 52px, and the row grows to hold it.
      assert.equal(-52, view().receipt.frame.points[1].y)
      assert.equal(52 + view().receipt.frame.height + 4, row.height)
      -- A second click closes it.
      click(row)
      assert.is_false(view().receipt.frame:IsShown())
      assert.is_false(saleRow("Linen Cloth").outline:IsShown())
      assert.equal(52, saleRow("Linen Cloth").height)
    end)

    it("keeps one receipt open at a time, and Escape closes it", function()
      GC.Ledger.GetEntries = function() return { sale({ itemName = "A", key = "a" }), sale({ itemName = "B", key = "b", at = NOW - 60 }) } end
      show()
      click(saleRow("A"))
      click(saleRow("B"))
      assert.is_false(saleRow("A").isOpen)
      assert.is_true(saleRow("B").isOpen)
      local frame = view().receipt.frame
      frame.scripts.OnKeyDown(frame, "ENTER")                -- any other key goes on
      assert.is_true(saleRow("B").isOpen)
      frame.scripts.OnKeyDown(frame, "ESCAPE")
      assert.is_false(saleRow("B").isOpen)
      assert.is_false(frame:IsShown())
    end)

    it("writes every unit of a breakdown that has to add up", function()
      GC.Ledger.GetEntries = function() return { sale({ qty = 43, total = 10062, cut = 503, key = "z" }) } end
      show()
      click(saleRow("Linen Cloth"))
      local cols = receipt()
      assert.equal("43 sold at 2s 34c | 1g 0s 62c", cols[1][3])
      assert.equal("You got | 95s 59c", cols[1][6])
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
        local row = saleRow(name)
        assert.equal("", row.cells.mkt:GetText(), name)
        assert.is_false(row.dot:IsShown(), name)
        click(row)
        local cols = receipt()
        assert.equal(2, #cols, name)                         -- no market column
        assert.equal("RECEIPT", cols[1][1])
        click(saleRow(name))
      end
    end)

    it("names a sale it has only a name for, and never prices it or opens its tooltip", function()
      _G.C_Item = { GetItemInfoInstant = function(name) if name == "Red Dye" then return 2604, "", "", "", 777 end end,
        GetItemInfo = function() return nil end, GetItemCount = function() error("counted by name") end }
      GC.Data = { GetItemValue = function() error("priced by name") end }
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Red Dye", key = "x", cut = false, total = 860, qty = 10 }) } end
      show()
      local row = saleRow("Red Dye")
      assert.equal(777, row.icon.texture)                   -- the icon may come from the name
      assert.equal("-", row.cells.profit:GetText())          -- nothing to place a cost on
      click(row)
      assert.is_nil(tooltip.itemID)                          -- the item tooltip may not
      local cols = receipt()
      assert.equal(2, #cols)                                 -- and no market column
      assert.equal("Auction house, 5% | -43c", cols[1][4])
      assert.same({ "PROFIT",
        "GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL." }, cols[2])
    end)

    it("says the profit waits for the money while it is in the mail", function()
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Mystery", key = "m", pending = true }) } end
      show()
      local row = saleRow("Mystery")
      assert.is_nil(row.icon.texture)
      assert.same({ 1, 1, 1, 0.05 }, row.icon.colorTexture)  -- an empty slot, never the red question mark
      click(row)
      local cols = receipt()
      assert.equal("sold, the money is in your mail", cols[1][2])
      assert.same({ "PROFIT", "The profit is worked out once the money arrives." }, cols[2])
    end)

    it("says which reagents a crafted item's cost counted at the market, or could not price", function()
      _G.C_Item = { GetItemIconByID = function() return 1 end, GetItemQualityByID = function() return 1 end,
        GetItemNameByID = function(id) return id == 9 and "Thread" or nil end }
      GC.CraftCapture = {
        WhyEstimated = function(_, nameOf) return { nameOf(9) .. " counted at the market price" } end,
        WhyUncosted = function(_, nameOf) return { nameOf(9) .. " had no price" } end,
      }
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Shirt", itemID = 50, key = "s1" }), sale({ itemName = "Hat", itemID = 51, key = "s2", at = NOW - 60 }) }
      end
      GC.Acquisitions.GetRealized = function() return { { evidenceKey = "s1", profit = 500, cost = 550, quantity = 14 } } end
      show()
      click(saleRow("Shirt"))
      local cols = receipt()
      assert.equal("Thread counted at the market price", cols[2][#cols[2]])
      click(saleRow("Hat"))
      cols = receipt()
      assert.equal("Thread had no price", cols[2][#cols[2]])
      GC.CraftCapture = nil
    end)

    it("marks the sale against the market: a dot left or right of the tick, clamped, and the percent", function()
      _G.C_Item = { GetItemIconByID = function() return 1 end, GetItemQualityByID = function() return 1 end }
      GC.Data = { GetItemValue = function(id) return ({ [1] = { mv = 159 }, [2] = { mv = 266 } })[id] end }
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = "Above", itemID = 1, qty = 43, total = 10062, key = "a" }),
          sale({ itemName = "Under", itemID = 2, qty = 43, total = 10062, key = "b", at = NOW - 60 }) }
      end
      show()
      local above, under = saleRow("Above"), saleRow("Under")
      assert.equal("+47%", above.cells.mkt:GetText())
      assert.truthy(same(above.cells.mkt.colorValue, GC.Theme.color.green))
      assert.equal(GC.SoldReceipt.BarPosition(47), above.dotAt)
      assert.equal(0.97, above.dotAt)
      assert.equal("-12%", under.cells.mkt:GetText())
      assert.truthy(same(under.cells.mkt.colorValue, GC.Kit.Tokens.color.warn))
      assert.near(0.38, under.dotAt, 1e-9)
      assert.is_true(above.tick:IsShown())
      click(under)
      assert.same({ "AGAINST TODAY'S MARKET", "12% under", "market 2s 66c", "you 2s 34c" }, receipt()[2])
    end)

    it("offers the bags' units to SELL, opening it on the item and posting nothing", function()
      _G.C_Item = { GetItemIconByID = function() return 1 end, GetItemQualityByID = function() return 1 end,
        GetItemCount = function(id) return id == 2589 and 14 or 0 end }
      _G.C_AuctionHouse = setmetatable({}, { __index = function(_, k) error("auction house call: " .. k) end })
      local calls = {}
      GC.Sniper = { ShowView = function(v) calls[#calls + 1] = "view:" .. v end }
      GC.Sell = { FocusItem = function(name) calls[#calls + 1] = "focus:" .. name end }
      GC.Ledger.GetEntries = function() return { sale({ itemID = 2589, key = "k" }) } end
      show()
      click(saleRow("Linen Cloth"))
      local cols = receipt()
      assert.equal("FINISH THIS SALE", cols[2][1])
      assert.equal("14 MORE IN BAGS · SELL", cols[2][#cols[2]])
      local bags = view().receipt.bags
      assert.is_true(bags:IsShown())
      bags.scripts.OnClick(bags)
      assert.same({ "view:sell", "focus:Linen Cloth" }, calls)
      GC.Sniper, GC.Sell, _G.C_AuctionHouse = nil, nil, nil
    end)

    describe("finishing a sale with what it cost", function()
      local context
      before_each(function()
        forever()
        context = { char = "Me-Realm", region = "eu" }
        helper.loadModule("Core/Acquisitions.lua", GC)
        GC.Ledger.Context = function() return context end
        GC.Acquisitions.Init({})
        GC.Acquisitions.RecordPost("commodity:2589", 2589, "Linen Cloth", context.char, context.region, 14, NOW - 7200)
        local entry = sale({ key = "mail:1", source = "mail", char = context.char, region = context.region })
        GC.Ledger.GetEntries = function() return { entry } end
      end)

      local function typeCost(text)
        local input = view().receipt.input
        input:SetText(text)
        input.scripts.OnTextChanged(input, true)
        return input
      end

      it("says 'set cost' on the row, and SAVE books the sale so the profit appears", function()
        show()
        local row = saleRow("Linen Cloth")
        assert.equal("set cost", row.cells.profit:GetText())
        assert.truthy(same(row.cells.profit.colorValue, GC.Kit.Tokens.color.soldFaint))
        click(row)
        local cols = receipt()
        assert.same({ "FINISH THIS SALE", "Paid each", "[input] SAVE" }, cols[#cols])
        typeCost("48c")
        assert.equal("48c", view().receipt.preview:GetText())
        -- A mail scan re-renders while the player types: what was typed stays.
        GC.Sold.RefreshIfShown()
        assert.equal("48c", view().receipt.input:GetText())
        local save = view().receipt.save
        save.scripts.OnClick(save)
        assert.equal("+3s 25c", saleRow("Linen Cloth").cells.profit:GetText())   -- 1050 - 14 x 48 - 53
        cols = receipt()
        assert.same({ "PROFIT", "You paid (set by you) | 6s 72c", "48c each", "Profit | +3s 25c" }, cols[#cols])
        assert.equal("+3s 25c", view().cards[2].value:GetText())
      end)

      it("refuses what is not an exact amount, and saves nothing", function()
        show()
        click(saleRow("Linen Cloth"))
        typeCost("lots")
        assert.equal("", view().receipt.preview:GetText())
        local save = view().receipt.save
        save.scripts.OnClick(save)
        assert.equal("Enter an exact positive cost", view().receipt.error:GetText())
        assert.same({}, GC.Acquisitions.GetAll())
        assert.equal("set cost", saleRow("Linen Cloth").cells.profit:GetText())
      end)

      -- Hiding an EditBox, or a frame it sits in, takes the keyboard from it in the client: the
      -- receipt is painted again on every keystroke and every mail scan, and is only ever moved.
      it("never hides the cost box or the receipt while the player types, or when the mail arrives", function()
        show()
        click(saleRow("Linen Cloth"))
        local rc = view().receipt
        local hidden = {}
        for _, key in ipairs({ "frame", "well" }) do
          local orig = rc[key].Hide
          rc[key].Hide = function(self) hidden[#hidden + 1] = key; return orig(self) end
        end
        typeCost("4")
        typeCost("48")
        GC.Sold.RefreshIfShown()
        assert.same({}, hidden)
        assert.is_true(rc.well:IsShown())
      end)

      it("keeps the receipt open and Escape in the box closes it", function()
        show()
        click(saleRow("Linen Cloth"))
        local input = typeCost("2s")
        assert.equal("2s", view().receipt.preview:GetText())
        input.scripts.OnEscapePressed(input)
        assert.is_false(saleRow("Linen Cloth").isOpen)
        -- Another sale's receipt starts with an empty box.
        click(saleRow("Linen Cloth"))
        assert.equal("", view().receipt.input:GetText())
      end)
    end)

    it("takes an uncached name's icon from the names the Forever scan kept", function()
      _G.C_Item = { GetItemIconByID = function(id) return id == 4278 and 4444 or nil end,
        GetItemInfoInstant = function() return nil end, GetItemInfo = function() return nil end }
      GC.ForeverNames = { Each = function(add) add(4278, "Pitchblende"); add(5, "Other") end }
      GC.Ledger.GetEntries = function() return { sale({ itemName = "Pitchblende", key = "p" }) } end
      show()
      local row = saleRow("Pitchblende")
      assert.equal(4444, row.icon.texture)
      assert.is_nil(row.info.id)                             -- the icon only: the id is not exact
      GC.ForeverNames = nil
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
        head.scripts.OnMouseUp(head, "LeftButton")           -- a heading opens nothing
        assert.is_nil(GC.Sold._state.open)
      end
    end)

    it("closes a receipt whose sale leaves the list", function()
      local entries = { sale({ itemName = "Linen Cloth", key = "a" }) }
      GC.Ledger.GetEntries = function() return entries end
      show()
      click(saleRow("Linen Cloth"))
      entries = { sale({ itemName = "Wool Cloth", key = "b" }) }
      GC.Sold.RefreshIfShown()
      assert.is_nil(GC.Sold._state.open)
      assert.is_false(view().receipt.frame:IsShown())
      assert.is_false(saleRow("Wool Cloth").isOpen)
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
    -- Each shown figure's left and right edge, from its RIGHT anchor off the row's right edge.
    local function layoutOf(row, width)
      local boxes = {}
      for _, key in ipairs({ "mkt", "got", "profit" }) do
        local cell = row.cells[key]
        if cell:IsShown() and cell.points[1] then
          local right = width + cell.points[1].x
          local left = right - cell.width
          if key == "mkt" and row.track:IsShown() then left = width + row.track.points[1].x - row.track.width end
          boxes[#boxes + 1] = { key = key, left = left, right = right, cell = cell }
        end
      end
      local chev = row.chevron
      boxes[#boxes + 1] = { key = "chevron", left = width + chev.points[1].x - chev.width, right = width + chev.points[1].x }
      return boxes
    end

    local function assertFits(width)
      for _, row in ipairs(shownRows("sale")) do
        local boxes = layoutOf(row, width)
        for i, box in ipairs(boxes) do
          if box.cell then
            assert.is_true(box.cell.width >= box.cell:GetUnboundedStringWidth(),
              ("%s is cut: %q"):format(box.key, box.cell:GetText()))
          end
          if boxes[i + 1] then assert.is_true(box.right <= boxes[i + 1].left, box.key .. " overlaps") end
        end
        assert.is_true(boxes[#boxes].right <= width, "the chevron runs off the row")
        -- The item: icon, then the name and the line under it, all end before the first figure.
        local textRight = 10 + 34 + 10 + math.max(row.name.width, row.sub.width)
        assert.is_true(textRight <= boxes[1].left, "the item runs into " .. boxes[1].key)
      end
    end

    local function bigSales()
      GC.Data = { GetItemValue = function(id) return id == 2592 and { mv = 21000 } or nil end }
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
      assert.equal("-2%", saleRow("Wool Cloth").cells.mkt:GetText())
    end)

    for _, locale in ipairs({ "ruRU", "ukUA", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "koKR", "zhCN", "zhTW" }) do
      it(("fits in %s at the narrowest window"):format(locale), function()
        load(locale)
        bigSales()
        view().container.width = 520
        show()
        assertFits(520)
        -- Every card line is a wrapped box as wide as the card's inside, never wider.
        for _, card in ipairs(view().cards) do
          if card.frame:IsShown() then
            for _, fs in ipairs({ card.label, card.value, card.small, card.sub }) do
              if fs:IsShown() then
                assert.is_true(fs.wrap, "a card line that cannot wrap")
                assert.is_true(fs.width <= card.frame.width - 24)
              end
            end
            assert.is_true(card.frame.height >= 70)
          end
        end
        -- The receipt fits the narrow row too, its cost box, SAVE and the way to SELL whole.
        GC.Data = { GetItemValue = function(id) return id == 2592 and { mv = 21000 } or nil end }
        _G.C_Item = { GetItemCount = function(id) return id == 2592 and 14 or 0 end }
        GC.Acquisitions.GetActivities = function()
          return { { itemName = "Wool Cloth", itemID = 2592, positionKey = "commodity:2592", character = "Me-Realm",
            region = "eu", firstSeenAt = 0 } }
        end
        GC.AppLedger.GetSummary = function() return nil end
        GC.Ledger.GetEntries = function()
          return { sale({ itemName = "Wool Cloth", itemID = 2592, key = "w", total = 8200000, qty = 400, cut = 410000,
            source = "mail", char = "Me-Realm", region = "eu" }) }
        end
        GC.Sold.RefreshIfShown()
        click(saleRow("Wool Cloth"))
        local rc = view().receipt
        assert.is_true(rc.frame.width <= 520)
        assert.equal(3, #receipt())
        assert.is_true(rc.well:IsShown() and rc.save:IsShown() and rc.bags:IsShown())
        local wellLeft = rc.well.points[1].x
        local sp = rc.save.points[1]
        local saveLeft = sp.relative == rc.well and wellLeft + rc.well.width + sp.x or sp.x
        local inside = rc.frame.width - 12
        assert.is_true(wellLeft + rc.well.width <= inside, "the cost box runs out of the receipt")
        assert.is_true(saveLeft + rc.save.width <= inside, "SAVE runs out of the receipt")
        assert.is_true(rc.bags.points[1].x + rc.bags.width <= inside, "the way to SELL runs out of the receipt")
        assert.is_true(rc.bags.width >= rc.bags.text:GetUnboundedStringWidth(), "the way to SELL is cut")
        assert.is_true(rc.save.width >= rc.save.text:GetUnboundedStringWidth(), "SAVE is cut")
      end)
    end

    it("drops the market mark first, rather than squeezing the item, and brings it back", function()
      bigSales()
      local container = view().container
      container.width = 330
      show()
      local row = saleRow("Wool Cloth")
      assert.is_false(row.cells.mkt:IsShown())
      assert.is_true(row.cells.profit:IsShown())
      container.width = 700
      GC.Sold.RefreshIfShown()
      assert.is_true(row.cells.mkt:IsShown())
      assertFits(700)
    end)

    it("steps a card's figure down to the smaller face when the big one would not fit", function()
      GC.AppLedger.GetSummary = function()
        return summary({ totals = { proceeds = 0, spent = 0, pending = 0, salesCount = 1, realized = 12345670000 } })
      end
      GC.Theme.SetScale(1.3)
      view().container.width = 700
      show()
      local card = view().cards[4]
      assert.is_false(card.value:IsShown())
      assert.is_true(card.small:IsShown())
      assert.equal("+1,234,567g", card.small:GetText())
      assert.is_true(card.small.width >= card.small:GetUnboundedStringWidth())
      assert.truthy(same(card.small.colorValue, GC.Theme.color.green))
      -- At the narrowest window four cards in one row would be too narrow: two rows of two.
      view().container.width = 520
      GC.Sold.RefreshIfShown()
      assert.equal(view().cards[1].frame.points[1].y, view().cards[2].frame.points[1].y)
      assert.is_true(card.frame.points[1].y < view().cards[1].frame.points[1].y)
      assert.equal(math.floor((520 - 10) / 2), card.frame.width)
      GC.Theme.SetScale(1)
    end)

    it("wraps a long item name and grows its row, instead of cutting it", function()
      local long = "Reinforced Everbloom-Stitched Leggings of the Unyielding Tidal Serpent of the Deep"
      GC.Ledger.GetEntries = function()
        return { sale({ itemName = long, key = "l", qty = 1 }),
          sale({ itemName = "Linen Cloth", key = "s", qty = 1, at = NOW - 60 }) }
      end
      show()
      local row = saleRow(long)
      assert.is_true(row.name.wrap)
      assert.is_true(row.name.width < row.name:GetUnboundedStringWidth())
      assert.is_true(row.height >= row.name:GetStringHeight() + row.sub:GetStringHeight(), "the row is shorter than its text")
      assert.is_true(row.height > 52)
      assertFits(600)
      -- A short name on the next row stays one line at the usual height.
      local short = saleRow("Linen Cloth")
      assert.is_false(short.name.wrap)
      assert.equal(52, short.height)
    end)
  end)

  -- The window's status line belongs to the Sniper's setView (Deals only). Handing it back shown
  -- on the way out put it over the Sell tab's MY LOTS (seen 2026-10-09).
  it("leaves the window's status line to the window", function()
    local status = region("FontString", host)
    status:Hide()
    host.status = status
    GC.Sold.Attach(host, { panelLeft = 88, panelRightInset = 32, top = -36, bottom = 12, rowWidth = 600, rowHeight = 32 })
    show()
    GC.Sold.Hide()
    assert.is_false(status:IsShown())
  end)

  -- A one-line string that sat under a hidden parent can come back undrawn, and SetText with
  -- the text it holds is a no-op: every string is cleared before it is written again.
  it("clears each card's label before stamping it again when the tab is shown", function()
    show()
    local seen = {}
    for i, card in ipairs(view().cards) do
      seen[i] = {}
      local orig = card.label.SetText
      card.label.SetText = function(self, text) seen[i][#seen[i] + 1] = text; return orig(self, text) end
    end
    GC.Sold.Hide()
    show()
    for i = 1, 3 do
      local calls = seen[i]
      assert.equal("", calls[1], i .. ": not cleared before the restamp")
      assert.is_true(#calls >= 2 and calls[2] ~= "", i .. ": not stamped after the clear")
    end
  end)
end)
