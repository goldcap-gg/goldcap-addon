local helper = require("spec.spec_helper")

describe("SoldFrame", function()
  local GC, rowsOf, containerOf

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
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:SetTextColor(...) self.colorValue = { ... } end
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
      color = { fg = {1,1,1}, fgMuted = {1,1,1}, fgDim = {1,1,1}, gold = {1,1,1},
                red = {1,0,0}, green = {0,1,0}, panel = {0,0,0}, bg = {0,0,0} },
      tier = { SUSPECT = {1,1,0} },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      Label = function(parent, _) return region("FontString", parent) end,
      Num = function(parent, _) return region("FontString", parent) end,
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

  local function shownTexts()
    local out = {}
    for _, row in ipairs(rowsOf()) do
      if row:IsShown() then
        out[#out + 1] = (row.left:GetText() or "") .. " | " .. (row.right:GetText() or "")
          .. " | " .. (row.rightSub:GetText() or "")
      end
    end
    return table.concat(out, "\n")
  end

  -- Finds the one shown row whose left text contains `pattern` (plain find,
  -- no magic chars). Used where a test needs a specific row's own color/text
  -- rather than a blob search across every rendered row -- a blob search
  -- can't tell which row a fact came from, so it can pass even when the
  -- branch under test is broken (see the totals-row confound this replaced).
  local function rowWithLeftText(pattern)
    for _, row in ipairs(rowsOf()) do
      if row:IsShown() and (row.left:GetText() or ""):find(pattern, 1, true) then
        return row
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
    assert.truthy(shownTexts():find("Pair the GoldCap Companion", 1, true))
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
      if row:IsShown() and (row.left:GetText() or ""):find("Matched", 1, true)
         and not (row.left:GetText() or ""):find("Unmatched", 1, true) then
        matched = row.rightSub:GetText()
      end
      if row:IsShown() and (row.left:GetText() or ""):find("Unmatched", 1, true) then
        unmatched = row.rightSub:GetText()
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
    -- Read each row's own rightSub directly rather than searching the whole
    -- rendered blob: the totals row independently renders "+25c" from this
    -- fixture's totals.realized, so a blob-wide `text:find("+")` would still
    -- pass even if the Full row's own basis branch were broken.
    local full, part, none = rowWithLeftText("Full"), rowWithLeftText("Part"), rowWithLeftText("None")
    assert.truthy(full and part and none)
    assert.equal("+45c", full.rightSub:GetText())          -- Full: signed profit, no count suffix
    assert.equal("+12c  1/4", part.rightSub:GetText())     -- Part: signed profit plus honest coverage
    assert.equal("cost unknown", none.rightSub:GetText())  -- None: no invented zero
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
    local winRow, loseRow = rowWithLeftText("Winner"), rowWithLeftText("Loser")
    assert.truthy(winRow and loseRow)
    assert.truthy(colorEquals(winRow.rightSub.colorValue, GC.Theme.color.green))
    assert.truthy(colorEquals(loseRow.rightSub.colorValue, GC.Theme.color.red))
  end)

  it("colors the sync-age line with the SUSPECT tier once it is 6-24h stale", function()
    -- time() is stubbed to 2000; a generatedAt 12h earlier lands the age
    -- inside (STALE_YELLOW_SECONDS, STALE_RED_SECONDS) -- the yellow band.
    GC.AppLedger.GetSummary = function() return summary({ generatedAt = 2000 - 12 * 3600 }) end
    GC.Sold.RefreshIfShown()
    local ageRow = rowWithLeftText("synced")
    assert.truthy(ageRow)
    assert.truthy(colorEquals(ageRow.left.colorValue, GC.Theme.tier.SUSPECT))
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
end)
