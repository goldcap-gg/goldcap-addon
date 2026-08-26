local helper = require("spec.spec_helper")

describe("SoldFrame", function()
  local GC, rowsOf, containerOf, bandOf

  local function region(kind, parent)
    -- `points`/`scripts` are bookkeeping the doubles alone define -- see
    -- ui_widget_field_spec.lua's DOUBLE_ONLY guard, which fails the suite
    -- if production ever reads them; only tests may.
    local r = { __frame = true, kind = kind, children = {}, textValue = nil, visible = true,
                points = {}, scripts = {} }
    function r:SetPoint(point, relative, relativePoint, x, y)
      self.points[#self.points + 1] = { point = point, relative = relative,
                                         relativePoint = relativePoint, x = x, y = y }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints() self.points[#self.points + 1] = { point = "ALL" } end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetWordWrap() end
    function r:SetTextColor(...) self.colorValue = { ... } end
    function r:SetColorTexture(...) self.colorTexture = { ... } end
    -- Sliced rounded fills (batch-5 pattern, see UI/SellFrame.lua's own
    -- doubles): rows own a real texture now instead of a flat color.
    function r:SetTexture(f) self.texture = f end
    function r:SetTexCoord() end
    function r:SetTextureSliceMargins(...) self.sliceMargins = { ... } end
    function r:SetVertexColor(...) self.vertexColor = { ... } end
    function r:SetSpacing(s) self.spacing = s end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:HookScript(name, fn) self.scripts[name] = fn end
    function r:EnableMouse() end
    function r:CreateTexture() return region("Texture", self) end
    if parent then parent.children[#parent.children + 1] = r end
    return r
  end

  before_each(function()
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.time = function() return 2000 end
    _G.date = os.date

    GC = helper.loadModule("Core/Util.lua")
    GC.Theme = {
      MEDIA = "",
      -- gold and fgDim are deliberately DISTINCT values (not both {1,1,1}
      -- like the rest of this table) -- the WHEN-column tint test below
      -- must be able to fail: a "dated" row's cells.when should read fgDim,
      -- a "pending" row's should read gold, and if those two colors were
      -- numerically identical in this fake, a broken paintSaleCells that
      -- always applied the same color to both would still pass.
      color = { fg = {1,1,1}, fgMuted = {1,1,1}, fgDim = {0.55,0.54,0.52}, gold = {0.83,0.64,0.22},
                red = {1,0,0}, green = {0,1,0}, panel = {0,0,0}, bg = {0,0,0},
                zebra = {1,1,1,0.04}, hover = {1,1,1,0.08}, border = {1,1,1,0.06} },
      tier = { SUSPECT = {1,1,0} },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      Label = function(parent, _) return region("FontString", parent) end,
      Num = function(parent, _, _) return region("FontString", parent) end,
      WithQuality = function(name) return name end,
    }
    GC.AppLedger = { GetSummary = function() return nil end }
    GC.Ledger = { GetEntries = function() return {} end }
    GC.Acquisitions = { GetRealized = function() return {} end }
    helper.loadModule("UI/SoldFrame.lua", GC)

    -- Reach the module-local row pool the way the Sell specs do.
    rowsOf = function()
      local i = 1
      while true do
        local name, value = debug.getupvalue(GC.Sold.RefreshIfShown, i)
        if not name then error("rows upvalue not found") end
        if name == "rows" then return value end
        i = i + 1
      end
    end

    -- Same trick to reach the module-local container, for the resize test.
    containerOf = function()
      local i = 1
      while true do
        local name, value = debug.getupvalue(GC.Sold.Show, i)
        if not name then error("container upvalue not found") end
        if name == "container" then return value end
        i = i + 1
      end
    end

    -- The header band (totals+profit line, age line, and -- for the header
    -- row test below -- the column header's own cells, attached at
    -- band.header purely for spec reachability).
    bandOf = function()
      local i = 1
      while true do
        local name, value = debug.getupvalue(GC.Sold.RefreshIfShown, i)
        if not name then error("band upvalue not found") end
        if name == "band" then return value end
        i = i + 1
      end
    end

    local host = region("Frame")
    GC.Sold.Attach(host, { panelLeft = 12, panelRightInset = 32, top = -100,
                           bottom = 34, rowWidth = 600, rowHeight = 28 })
    GC.Sold.Show()
  end)

  after_each(function()
    _G.CreateFrame = nil
    _G.GetCoinTextureString = nil
    _G.date = nil
  end)

  -- Concatenates every cell a shown row could possibly carry -- the plain
  -- item name, the hint's full-row text, the section row's own mono
  -- micro-label (row.sectionLabel, when shown -- section rows no longer use
  -- row.wide), and the five column cells -- so a substring search behaves
  -- like the old single-blob search used to, regardless of which cell kind
  -- actually holds the text.
  local function shownTexts()
    local out = {}
    for _, row in ipairs(rowsOf()) do
      if row:IsShown() then
        out[#out + 1] = table.concat({
          row.item:GetText() or "",
          row.wide:GetText() or "",
          row.sectionLabel:IsShown() and (row.sectionLabel:GetText() or "") or "",
          row.cells.when:GetText() or "",
          row.cells.qty:GetText() or "",
          row.cells.unit:GetText() or "",
          row.cells.total:GetText() or "",
          row.cells.profit:GetText() or "",
        }, " | ")
      end
    end
    return table.concat(out, "\n")
  end

  -- Finds the one shown row whose item/section/hint text contains `pattern`
  -- (plain find, no magic chars). Used where a test needs a specific row's
  -- own cell/color rather than a blob search across every rendered row -- a
  -- blob search can't tell which row a fact came from, so it can pass even
  -- when the branch under test is broken. A section row's text lives in
  -- row.sectionLabel now, not row.wide -- checked first, additively.
  local function rowWithText(pattern)
    for _, row in ipairs(rowsOf()) do
      if row:IsShown() then
        local text = row.sectionLabel:IsShown() and (row.sectionLabel:GetText() or "")
          or ((row.item:GetText() or "") .. (row.wide:GetText() or ""))
        if text:find(pattern, 1, true) then return row end
      end
    end
  end

  local function colorEquals(actual, expected)
    return actual ~= nil and expected ~= nil
      and actual[1] == expected[1] and actual[2] == expected[2] and actual[3] == expected[3]
  end

  local function summary(over)
    local s = {
      generatedAt = 1000, pro = true, days = 30,
      totals = { proceeds = 100, spent = 50, pending = 7, salesCount = 1, realized = 25 },
      sales = { { name = "Server Ore", item = 5, qty = 2, total = 100, cut = 5,
                  pending = false, at = 900,
                  basis = { matched = 2, unmatched = 0, cost = 50, profit = 45 } } },
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end

  it("shows the pairing hint when there is no companion data", function()
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("Pair or update the GoldCap Companion", 1, true))
  end)

  it("splits local rows around the snapshot boundary, newest first", function()
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return {
        { kind = "sale", itemName = "Old Local", qty = 1, total = 10, cut = 0,
          pending = false, at = 900, key = "k-old" },  -- covered by the snapshot
        { kind = "sale", itemName = "New Local", qty = 1, total = 10, cut = 0,
          pending = true, at = 1500, key = "k-new" },   -- not yet on the server
      }
    end
    GC.Sold.RefreshIfShown()
    local text = shownTexts()
    assert.truthy(text:find("New Local", 1, true))
    assert.is_nil(text:find("Old Local", 1, true))
    assert.truthy(text:find("Server Ore", 1, true))
  end)

  it("shows a local sale older than generatedAt but newer than every snapshot sale (C1)", function()
    -- The old rule clamped the boundary to generatedAt, but generatedAt is
    -- always newer than the sales the snapshot is missing -- SavedVariables
    -- only flushes to disk on /reload or logout, so the file the addon
    -- reads was written BEFORE that reload. This sale sits exactly in that
    -- gap: sold at 950, after the snapshot's newest sale (900) but before
    -- its generatedAt (1000). The old code hid it in neither section; the
    -- boundary must come from the snapshot's own sales, not generatedAt.
    GC.AppLedger.GetSummary = function() return summary() end -- generatedAt=1000, newest sale at=900
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "Just Synced", qty = 1, total = 10, cut = 0,
                 pending = false, at = 950, key = "k-gap" } }
    end
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("Just Synced", 1, true))
  end)

  it("keeps a local sale hidden once it is no newer than the snapshot's newest sale", function()
    GC.AppLedger.GetSummary = function() return summary() end -- newest snapshot sale at=900
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "Already Synced", qty = 1, total = 10, cut = 0,
                 pending = false, at = 900, key = "k-covered" } }
    end
    GC.Sold.RefreshIfShown()
    assert.is_nil(shownTexts():find("Already Synced", 1, true))
  end)

  it("shows local profit only on an exact evidence-key join", function()
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return {
        { kind = "sale", itemName = "Matched", qty = 1, total = 100, cut = 5,
          pending = false, at = 1500, key = "k-match" },
        { kind = "sale", itemName = "Unmatched", qty = 1, total = 100, cut = 5,
          pending = false, at = 1600, key = "k-none" },
      }
    end
    GC.Acquisitions.GetRealized = function()
      return { { evidenceKey = "k-match", profit = 40, cost = 55 } }
    end
    GC.Sold.RefreshIfShown()
    local matched, unmatched
    for _, row in ipairs(rowsOf()) do
      if row:IsShown() and (row.item:GetText() or ""):find("Matched", 1, true)
         and not (row.item:GetText() or ""):find("Unmatched", 1, true) then
        matched = row.cells.profit:GetText()
      end
      if row:IsShown() and (row.item:GetText() or ""):find("Unmatched", 1, true) then
        unmatched = row.cells.profit:GetText()
      end
    end
    assert.truthy(matched and matched:find("+", 1, true))
    assert.equal("--", unmatched)
  end)

  it("renders the three basis states on server rows", function()
    GC.AppLedger.GetSummary = function()
      return summary({ sales = {
        { name = "Full", qty = 2, total = 100, cut = 5, pending = false, at = 900,
          basis = { matched = 2, unmatched = 0, cost = 50, profit = 45 } },
        { name = "Part", qty = 4, total = 100, cut = 5, pending = false, at = 800,
          basis = { matched = 1, unmatched = 3, cost = 10, profit = 12 } },
        { name = "None", qty = 1, total = 100, cut = 5, pending = false, at = 700,
          basis = { matched = 0, unmatched = 1, cost = 0, profit = 0 } },
      } })
    end
    GC.Sold.RefreshIfShown()
    -- Read each row's own PROFIT cell directly rather than searching the
    -- whole rendered blob: the header band independently renders "+25c"
    -- from this fixture's totals.realized (now on its own line, outside
    -- the row pool entirely -- see the band tests below), but a stray
    -- blob-wide `text:find("+")` could still have passed even when the
    -- Full row's own basis branch were broken, so this stays row-specific.
    local full, part, none = rowWithText("Full"), rowWithText("Part"), rowWithText("None")
    assert.truthy(full and part and none)
    assert.equal("+45c", full.cells.profit:GetText())          -- Full: signed profit, no count suffix
    -- Part: signed profit in green/red, the N/M coverage suffix dim (M2) --
    -- an inline color escape, since the PROFIT cell is one FontString and
    -- the two halves must read in different colors.
    assert.equal("+12c  |cff9d9d9d1/4|r", part.cells.profit:GetText())
    assert.equal("cost unknown", none.cells.profit:GetText())  -- None: no invented zero
  end)

  it("free tier shows the Pro hint and no profit column", function()
    GC.AppLedger.GetSummary = function()
      return summary({ pro = false,
        totals = { proceeds = 100, spent = 50, pending = 7, salesCount = 1 },
        sales = { { name = "Server Ore", qty = 2, total = 100, cut = 5,
                    pending = false, at = 900 } } })
    end
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("Pro feature", 1, true))
    -- The design's own words for this state: "free tier (no basis) ->
    -- empty" -- never an invented "--" or "cost unknown" when the sale
    -- carries no basis field at all.
    local row = rowWithText("Server Ore")
    assert.truthy(row)
    assert.equal("", row.cells.profit:GetText())
  end)

  it("shows every local sale when there is no companion summary yet (boundary defaults to 0)", function()
    GC.AppLedger.GetSummary = function() return nil end
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "No Summary Yet", qty = 1, total = 10, cut = 0,
                 pending = false, at = 1, key = "k-early" } } -- at(1) > boundary(0) with no summary
    end
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("No Summary Yet", 1, true))
  end)

  it("shows the mailbox empty-state hint when there is nothing anywhere", function()
    GC.AppLedger.GetSummary = function() return nil end
    GC.Ledger.GetEntries = function() return {} end
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("No sales recorded yet", 1, true))
  end)

  it("admits the server section is a tail when salesCount exceeds the fetched sales (M3)", function()
    GC.AppLedger.GetSummary = function()
      return summary({ totals = { proceeds = 100, spent = 50, pending = 7,
                                   salesCount = 5, realized = 25 } })
    end
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("ON GOLDCAP.GG — LAST 30 DAYS, LATEST 1 OF 5", 1, true))
    -- The section row is the mono micro-label + gold rule (Task 3), not the
    -- old full-width row.wide label.
    local row = rowWithText("ON GOLDCAP.GG")
    assert.truthy(row)
    assert.truthy(row.sectionRule:IsShown())
    assert.truthy(colorEquals(row.sectionLabel.colorValue, GC.Theme.color.gold))
  end)

  it("leaves the server section header unchanged when it holds every sale", function()
    GC.AppLedger.GetSummary = function() return summary() end -- salesCount == #sales == 1
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("ON GOLDCAP.GG — LAST 30 DAYS", 1, true))
    assert.is_nil(shownTexts():find("latest", 1, true))
  end)

  it("shows the local section's profit net of the sale's own cut (I1)", function()
    -- entry.realized.profit (Core/Acquisitions.lua's ReconcileSale) is
    -- GROSS -- proceeds minus known cost, cut not subtracted. The server
    -- section's basis.profit is net of the AH cut, so the two sections
    -- would otherwise disagree by exactly the cut for the same sale.
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "Cut Test", qty = 1, total = 100, cut = 12,
                 pending = false, at = 1500, key = "k-cut" } }
    end
    GC.Acquisitions.GetRealized = function()
      return { { evidenceKey = "k-cut", profit = 40, cost = 60 } } -- gross: 100 - 60
    end
    GC.Sold.RefreshIfShown()
    local row = rowWithText("Cut Test")
    assert.truthy(row)
    assert.equal("+28c", row.cells.profit:GetText()) -- net: 40 - 12 cut = 28
  end)

  it("colors local profit rows red for a loss and green for a gain", function()
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return {
        { kind = "sale", itemName = "Winner", qty = 1, total = 100, cut = 5,
          pending = false, at = 1500, key = "k-win" },
        { kind = "sale", itemName = "Loser", qty = 1, total = 100, cut = 5,
          pending = false, at = 1600, key = "k-lose" },
      }
    end
    GC.Acquisitions.GetRealized = function()
      return {
        { evidenceKey = "k-win", profit = 40, cost = 55 },
        { evidenceKey = "k-lose", profit = -15, cost = 115 },
      }
    end
    GC.Sold.RefreshIfShown()
    local winRow, loseRow = rowWithText("Winner"), rowWithText("Loser")
    assert.truthy(winRow and loseRow)
    assert.truthy(colorEquals(winRow.cells.profit.colorValue, GC.Theme.color.green))
    assert.truthy(colorEquals(loseRow.cells.profit.colorValue, GC.Theme.color.red))
  end)

  -- Item 4 (addon polish batch): row.itemInset used to be set to 26 unconditionally, before
  -- paintSaleCells even attempted the icon lookup -- a sale/position with no resolvable icon
  -- (no itemID, or C_Item.GetItemIconByID returning nothing, which is every row in this spec
  -- file's default fixtures since _G.C_Item is never stubbed) showed the item name indented
  -- into a blank gap with nothing to justify it.
  it("does not indent the item name when no icon resolves", function()
    GC.AppLedger.GetSummary = function() return summary() end -- default fixture: no _G.C_Item stub
    GC.Sold.RefreshIfShown()
    local row = rowWithText("Server Ore")
    assert.truthy(row)
    assert.equal(0, row.itemInset)
  end)

  it("indents the item name for the icon's width when one resolves", function()
    _G.C_Item = { GetItemIconByID = function() return "Interface\\Icons\\INV_Misc_Ore_01" end }
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Sold.RefreshIfShown()
    local row = rowWithText("Server Ore")
    assert.truthy(row)
    assert.equal(26, row.itemInset)
    _G.C_Item = nil
  end)

  it("shows the WHEN column as a formatted date, or a dim 'in the mail' while pending", function()
    -- Same honesty the old inline "[not yet paid out]" suffix carried: the
    -- sale exists, the gold is just in transit -- now the WHEN column's own
    -- content instead of an appendix to it.
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return {
        { kind = "sale", itemName = "Posted Already", qty = 1, total = 10, cut = 0,
          pending = false, at = 1500, key = "k-posted" },
        { kind = "sale", itemName = "In Transit", qty = 1, total = 10, cut = 0,
          pending = true, at = 1600, key = "k-transit" },
      }
    end
    GC.Sold.RefreshIfShown()
    local posted, transit = rowWithText("Posted Already"), rowWithText("In Transit")
    assert.truthy(posted and transit)
    assert.truthy(posted.cells.when:GetText() ~= "in the mail")
    assert.equal("in the mail", transit.cells.when:GetText())
    -- A dated WHEN stays dim like the rest of the row; "in the mail" is the
    -- one thing in that column worth calling out, so it gets the gold tint.
    assert.truthy(colorEquals(posted.cells.when.colorValue, GC.Theme.color.fgDim))
    assert.truthy(colorEquals(transit.cells.when.colorValue, GC.Theme.color.gold))
  end)

  it("renders the row fill through a sliced texture, not a flat color", function()
    -- Batch-5 sliced-fill pattern (SellFrame's row.zebra precedent): a real
    -- texture recolored with SetVertexColor, not SetColorTexture.
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Sold.RefreshIfShown()
    assert.equal("plaque.png", rowsOf()[1].zebra.texture)
  end)

  it("shows the UNIT column as floor(total/qty)", function()
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "Unit Math", qty = 3, total = 100, cut = 0,
                 pending = false, at = 1500, key = "k-unit" } }
    end
    GC.Sold.RefreshIfShown()
    local row = rowWithText("Unit Math")
    assert.truthy(row)
    assert.equal("33c", row.cells.unit:GetText()) -- floor(100/3) = 33
    assert.equal("3", row.cells.qty:GetText())
    assert.equal("100c", row.cells.total:GetText())
  end)

  it("shows the two-line header band: totals+realized profit, then sync age", function()
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Sold.RefreshIfShown()
    local band = bandOf()
    assert.truthy(band)
    assert.truthy(band.totals:GetText():find("1 sales", 1, true))
    assert.truthy(band.totals:GetText():find("proceeds", 1, true))
    -- Mono band separator, replacing the old " -- ": every " -- " became
    -- " · " when totals/age moved onto Theme.Num alongside the rest of the
    -- mono table.
    assert.truthy(band.totals:GetText():find(" · ", 1, true))
    assert.equal("+25c", band.profit:GetText())
    assert.truthy(colorEquals(band.profit.colorValue, GC.Theme.color.green))
    assert.truthy(band.age:GetText():find("synced", 1, true))
    assert.truthy(band.age:GetText():find(" · ", 1, true))
    -- The band is not a row: neither line appears in the scrolling list.
    assert.is_nil(shownTexts():find("proceeds", 1, true))

    -- The REALIZED PROFIT caption above band.profit, and the 1px rule along
    -- the band's own bottom edge -- both new user-visible structure this
    -- batch adds, not just re-styled existing lines.
    assert.equal("REALIZED PROFIT", band.profitLabel:GetText())
    assert.truthy(colorEquals(band.profitLabel.colorValue, GC.Theme.color.fgDim))
    assert.truthy(band.rule.colorTexture)
    assert.truthy(colorEquals(band.rule.colorTexture, GC.Theme.color.border))
  end)

  it("leaves the header band blank when there is no companion summary", function()
    GC.Sold.RefreshIfShown()
    local band = bandOf()
    assert.equal("", band.totals:GetText())
    assert.equal("", band.age:GetText())
    -- REALIZED PROFIT (I2): no summary means band.profit never gets a value,
    -- so the caption above it must not stay shown captioning nothing.
    assert.is_false(band.profitLabel:IsShown())
  end)

  it("colors the sync-age line with the SUSPECT tier once it is 6-24h stale", function()
    -- time() is stubbed to 2000; a generatedAt 12h earlier lands the age
    -- inside (STALE_YELLOW_SECONDS, STALE_RED_SECONDS) -- the yellow band.
    GC.AppLedger.GetSummary = function() return summary({ generatedAt = 2000 - 12 * 3600 }) end
    GC.Sold.RefreshIfShown()
    local band = bandOf()
    assert.truthy(band)
    assert.truthy(colorEquals(band.age.colorValue, GC.Theme.tier.SUSPECT))
  end)

  it("labels the column header row like Deals': uppercase ITEM/WHEN/QTY/UNIT/TOTAL/PROFIT", function()
    local band = bandOf()
    assert.truthy(band and band.header and band.header.cells)
    -- ITEM is on the kit now too -- mono font, fgDim, same as its neighbours
    -- (previously the one native-font label in the row).
    assert.truthy(band.header.itemCell)
    assert.equal("ITEM", band.header.itemCell.label:GetText())
    assert.truthy(colorEquals(band.header.itemCell.label.colorValue, GC.Theme.color.fgDim))
    assert.equal("WHEN", band.header.cells.when.label:GetText())
    assert.equal("QTY", band.header.cells.qty.label:GetText())
    assert.equal("UNIT", band.header.cells.unit.label:GetText())
    assert.equal("TOTAL", band.header.cells.total.label:GetText())
    assert.equal("PROFIT", band.header.cells.profit.label:GetText())
    -- The underline separating the column headings from row 1, attached at
    -- header.rule purely for spec reachability (see createHeaderRow).
    assert.truthy(band.header.rule and band.header.rule.colorTexture)
    assert.truthy(colorEquals(band.header.rule.colorTexture, GC.Theme.color.border))
  end)

  it("re-anchors rows to the container's current width instead of a stale fixed size (I2)", function()
    -- The container tracks the window (TOPLEFT/BOTTOMRIGHT anchored), so a
    -- resize or a dock reparent changes its width; rows must follow rather
    -- than staying pinned to the rowWidth Attach was called with.
    local container = containerOf()
    assert.truthy(container)
    container.width = 1100
    GC.AppLedger.GetSummary = function() return summary() end
    -- A Show() after the width change must re-render without error even
    -- though nothing fired the container's OnSizeChanged in this fake.
    assert.has_no.errors(function() GC.Sold.Show() end)

    local row = rowsOf()[1]
    assert.truthy(row)
    local topLeft, topRight
    for _, p in ipairs(row.points) do
      if p.point == "TOPLEFT" then topLeft = p end
      if p.point == "TOPRIGHT" then topRight = p end
    end
    assert.truthy(topLeft)
    assert.truthy(topRight)
  end)

  it("drops WHEN first as the window narrows, then UNIT, and restores both when it widens again", function()
    GC.AppLedger.GetSummary = function() return summary() end
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "Responsive Row", qty = 1, total = 10, cut = 0,
                 pending = false, at = 1500, key = "k-resp" } }
    end
    local container = containerOf()

    -- Wide: both optional columns visible.
    container.width = 900
    GC.Sold.Show()
    local wide = rowWithText("Responsive Row")
    assert.truthy(wide.cells.when:IsShown())
    assert.truthy(wide.cells.unit:IsShown())

    -- Narrow enough to drop WHEN but not UNIT.
    container.width = 450
    GC.Sold.Show()
    local midRow = rowWithText("Responsive Row")
    assert.falsy(midRow.cells.when:IsShown())
    assert.truthy(midRow.cells.unit:IsShown())

    -- Narrower still: UNIT drops too.
    container.width = 260
    GC.Sold.Show()
    local narrowRow = rowWithText("Responsive Row")
    assert.falsy(narrowRow.cells.when:IsShown())
    assert.falsy(narrowRow.cells.unit:IsShown())

    -- Back to wide: both columns come back.
    container.width = 900
    GC.Sold.Show()
    local restored = rowWithText("Responsive Row")
    assert.truthy(restored.cells.when:IsShown())
    assert.truthy(restored.cells.unit:IsShown())
  end)
end)
