local helper = require("spec.spec_helper")

describe("SoldFrame", function()
  local GC, rowsOf

  local function region(kind, parent)
    local r = { __frame = true, kind = kind, children = {}, textValue = nil, visible = true }
    function r:SetPoint() end
    function r:SetSize() end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:SetTextColor() end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:SetScrollChild() end
    function r:SetScript() end
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

  it("clamps a future generatedAt to now so clock skew cannot hide local rows", function()
    GC.AppLedger.GetSummary = function() return summary({ generatedAt = 99999 }) end
    GC.Ledger.GetEntries = function()
      return { { kind = "sale", itemName = "Fresh", qty = 1, total = 10, cut = 0,
                 pending = false, at = 2100, key = "k" } } -- at > time() boundary
    end
    GC.Sold.RefreshIfShown()
    assert.truthy(shownTexts():find("Fresh", 1, true))
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
    local text = shownTexts()
    assert.truthy(text:find("+", 1, true))          -- Full: signed profit
    assert.truthy(text:find("1/4", 1, true))         -- Part: honest coverage
    assert.truthy(text:find("cost unknown", 1, true)) -- None: no invented zero
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
end)
