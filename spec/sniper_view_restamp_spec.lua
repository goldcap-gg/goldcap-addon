require("spec.spec_helper")

-- Leaving the Deals board hides the rows' PARENT (setView hides the scroll frame), never the
-- rows themselves: every pooled row goes on reporting IsShown(), so setRowDeal's repaint skip
-- -- there so a row whose content never moved isn't rebuilt several times a second --
-- declined to touch a single one of them on the way back. Those cells are the same one-line
-- FontStrings the column headings are, and a one-line FontString that was on screen when its
-- parent hid can come back with its text simply not drawn. The headings went blank in-game
-- exactly that way and got their own re-stamp (updateHeaderSortIndicators); the rows under
-- them, and the three toolbar buttons that cache the label they last stamped, did not.
--
-- What this can prove is the stamp, not the pixels: busted has no font engine. So for the rows
-- it blanks what the doubles recorded -- standing in for the client dropping the draw -- and
-- asserts that coming back to Deals tells the client every string again.
--
-- The headings need more than that. Blanking a double's text and checking it came back
-- passes a restamp that sets the very text the string already holds -- and that is a no-op
-- to the client, which is exactly how the headings stayed blank after the first fix. So the
-- headings record every call made on them and must see the whole cure, in order: cleared,
-- set, hidden, shown (the same sequence spec/soldframe_spec.lua pins for the Sold tab).
describe("Deals board re-stamps itself on the way back", function()
  -- A recording double that tracks its own shown flag and dispatches OnShow/OnHide, which is
  -- the whole point here: the real engine hides a child visually with its parent without
  -- flipping the child's own flag, and that is what defeats the repaint skip.
  local function stubFrame()
    local f
    f = {
      shown = false,
      scripts = {},
      RegisterEvent = function() end,
      UnregisterEvent = function() end,
      SetScript = function(self, name, fn) self.scripts[name] = fn end,
      HookScript = function(self, name, fn)
        local prev = self.scripts[name]
        self.scripts[name] = function(...)
          if prev then prev(...) end
          return fn(...)
        end
      end,
      SetSize = function() end,
      SetPoint = function() end,
      SetMovable = function() end,
      EnableMouse = function() end,
      RegisterForDrag = function() end,
      Show = function(self)
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
      end,
      Hide = function(self)
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
      end,
      IsShown = function(self) return self.shown end,
      SetText = function(self, text) self.text = text end,
      GetText = function(self) return self.text or "" end,
      SetTexture = function(self, tex) self.texture = tex end,
      SetTextColor = function() end,
      SetJustifyH = function() end,
      SetJustifyV = function() end,
      SetWidth = function() end,
      SetScrollChild = function() end,
      StartMoving = function() end,
      StopMovingOrSizing = function() end,
      CreateFontString = function() return stubFrame() end,
      CreateTexture = function() return stubFrame() end,
      TitleText = { SetText = function() end },
      EnableMouseWheel = function() end,
      SetVerticalScroll = function() end,
      GetVerticalScroll = function() return 0 end,
      GetVerticalScrollRange = function() return 0 end,
      SetWordWrap = function(self, on) self.wordWrap = on end,
      SetMaxLines = function(self, lines) self.maxLines = lines end,
      SetSpacing = function() end,
      Enable = function() end,
      Disable = function() end,
      GetFontString = function() return nil end,
      SetResizable = function() end,
      SetResizeBounds = function() end,
      StartSizing = function() end,
      ClearAllPoints = function() end,
      GetPoint = function() return nil end,
      GetHeight = function() return 0 end,
      SetHeight = function() end,
      GetFrameLevel = function() return 1 end,
      SetFrameLevel = function() end,
      SetColorTexture = function() end,
      SetBlendMode = function() end,
      SetTextureSliceMargins = function() end,
      SetVertexColor = function() end,
      SetAllPoints = function() end,
      SetFont = function() end,
      GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
      RegisterForClicks = function() end,
      SetFrameStrata = function() end,
      SetToplevel = function() end,
      GetFrameStrata = function() return "MEDIUM" end,
      GetWidth = function() return 0 end,
      IsEnabled = function() return true end,
      SetAlpha = function() end,
      GetParent = function() return nil end,
      SetParent = function() end,
      CreateAnimationGroup = function()
        return {
          CreateAnimation = function()
            return {
              SetFromAlpha = function() end,
              SetToAlpha = function() end,
              SetDuration = function() end,
              SetSmoothing = function() end,
              SetOrder = function() end,
              SetTarget = function() end,
            }
          end,
          SetLooping = function() end,
          SetScript = function() end,
          Play = function() end,
          Stop = function() end,
          IsPlaying = function() return false end,
        }
      end,
      EnableKeyboard = function() end,
      SetPropagateKeyboardInput = function() end,
      SetAutoFocus = function() end,
      SetNumeric = function() end,
      SetMaxLetters = function() end,
      ClearFocus = function() end,
      SetChecked = function() end,
      GetChecked = function() return false end,
      SetCheckedTexture = function() end,
      SetOrientation = function() end,
      SetMinMaxValues = function() end,
      SetValueStep = function() end,
      SetObeyStepOnDrag = function() end,
      SetThumbTexture = function() end,
      SetValue = function() end,
      GetValue = function() return 0 end,
    }
    return f
  end

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function setUpvalue(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function buildFrame()
    _G.CreateFrame = function(_, name)
      local f = stubFrame()
      if name and name ~= "" then _G[name] = f end
      return f
    end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.hooksecurefunc = function() end
    _G.GetTime = function() return 100 end
    _G.PlaySound = function() end
    _G.SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function(_, itemID)
      return {
        ContinueOnItemLoad = function(_, cb) cb() end,
        GetItemIcon = function() return "icon:" .. itemID end,
        GetItemQuality = function() return nil end,
        GetItemName = function() return "Item " .. itemID end,
      }
    end }

    local GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then files[#files + 1] = line end
    end
    toc:close()
    for _, rel in ipairs(files) do
      local chunk, err = loadfile("GoldCap/" .. rel:gsub("\\", "/"))
      assert(chunk, err)
      chunk("GoldCap", GC)
    end

    GC.Sniper.Toggle() -- constructs and shows the real window
    local frame = _G.GoldCapSniperFrame
    assert(frame, "GC.Sniper.Toggle() did not publish _G.GoldCapSniperFrame")

    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    local setView = upvalue(createFrame, "setView")
    local clearDeals = upvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = upvalue(clearDeals, "refreshRows")
    local renderList = upvalue(refreshRows, "renderList")
    local sortedDeals = upvalue(renderList, "sortedDeals")

    return {
      GC = GC,
      frame = frame,
      setView = setView,
      refreshRows = refreshRows,
      rows = upvalue(refreshRows, "rows"),
      deals = upvalue(sortedDeals, "deals"),
    }
  end

  after_each(function()
    for _, name in ipairs({ "CreateFrame", "GoldCapSniperFrame", "GoldCapAuctionHouseDock",
      "UISpecialFrames", "SlashCmdList", "C_AddOns", "GoldCap_MarketData", "SLASH_GOLDCAP1",
      "SLASH_GOLDCAP2", "hooksecurefunc", "GetTime", "PlaySound", "SOUNDKIT", "C_Timer",
      "GetCoinTextureString", "ITEM_QUALITY_COLORS", "Item", "GoldCapDB" }) do
      _G[name] = nil
    end
  end)

  -- One rendered row, then everything the client was told is thrown away -- which is exactly
  -- the state a blanked FontString is in: the string is still there in Lua, the pixels are not.
  local function renderOneDeal(ctx)
    ctx.deals[12345] = {
      itemID = 12345, unitPrice = 1000, qty = 5, profit = 2000, discount = 0.4,
      tier = "GOOD", action = "Check",
    }
    ctx.refreshRows()
    local row = ctx.rows[1]
    assert.is_not_nil(row, "no pooled row was built for the deal")
    assert.is_not_nil(row.nameText.text, "the row was never stamped in the first place")
    return row
  end

  local function blankEverything(row)
    row.nameText.text, row.unitText.text, row.priceText.text = nil, nil, nil
  end

  local function assertStamped(row)
    assert.is_not_nil(row.nameText.text, "the row name was never stamped again")
    assert.is_not_nil(row.unitText.text, "the unit price was never stamped again")
    assert.is_not_nil(row.priceText.text, "the total price was never stamped again")
  end

  -- Every call made on each heading label from here on, per heading: "set:<text>", "hide",
  -- "show". Wraps the doubles' own methods, so the text they hold stays real.
  local function recordHeadings(ctx)
    local header = ctx.frame.headerRow
    local seen = {}
    local function record(key, label)
      local calls = {}
      seen[key] = calls
      local set, hide, show = label.SetText, label.Hide, label.Show
      label.SetText = function(self, text) calls[#calls + 1] = "set:" .. tostring(text); return set(self, text) end
      label.Hide = function(self) calls[#calls + 1] = "hide"; return hide(self) end
      label.Show = function(self) calls[#calls + 1] = "show"; return show(self) end
    end
    for key, cell in pairs(header.cells) do record(key, cell.label) end
    record("item", header.itemCell.label)
    return seen
  end

  -- The heading's text is what the cells were built with; `sorted` (a key into header.cells)
  -- is the one heading that carries the active sort arrow.
  local function assertHeadingsRestamped(ctx, seen, sorted, arrow)
    local header = ctx.frame.headerRow
    local expected = { item = "ITEM" }
    for key, cell in pairs(header.cells) do
      expected[key] = key == sorted and (cell.baseText .. arrow) or cell.baseText
    end
    for key, text in pairs(expected) do
      assert.same({ "set:", "set:" .. text, "hide", "show" }, seen[key],
        key .. ": the heading was not cleared, stamped, hidden and shown again")
    end
  end

  it("re-stamps every pooled row and heading when the Deals view comes back", function()
    local ctx = buildFrame()
    local row = renderOneDeal(ctx)

    -- What setView does on the way out: the rows' parent goes, the rows do not -- the row is
    -- still shown as far as it and the repaint skip are concerned.
    ctx.frame.scroll:Hide()
    setUpvalue(ctx.setView, "view", "sell")
    assert.is_true(row:IsShown())
    blankEverything(row)
    local seen = recordHeadings(ctx)

    ctx.setView("deals")

    assertStamped(row)
    assertHeadingsRestamped(ctx, seen)
  end)

  it("re-stamps them when the window itself is shown again", function()
    local ctx = buildFrame()
    local row = renderOneDeal(ctx)

    ctx.frame:Hide()
    blankEverything(row)
    local seen = recordHeadings(ctx)
    ctx.frame:Show()

    assertStamped(row)
    assertHeadingsRestamped(ctx, seen)
  end)

  -- The sorted column is stamped once, with its arrow -- not first plain and then again with
  -- the arrow, and not left holding the plain text either.
  it("keeps the active sort arrow on its heading through the restamp", function()
    local ctx = buildFrame()
    local profit = ctx.frame.headerRow.cells.profit
    profit.scripts.OnMouseDown(profit) -- the player's own click: sort by profit, descending
    assert.equal(profit.baseText .. " ▼", profit.label.text)
    setUpvalue(ctx.setView, "view", "sell")
    local seen = recordHeadings(ctx)

    ctx.setView("deals")

    assertHeadingsRestamped(ctx, seen, "profit", " ▼")
  end)

  -- AUTO, SCAN and HIDDEN each skip a restamp identical to the one they last made -- right
  -- for the 0.25s ticker, wrong for a label that came back from a hide undrawn.
  it("forgets the toolbar's cached labels so the three buttons are stamped again", function()
    local ctx = buildFrame()
    ctx.frame.autoBtn.lastText = "stale"
    ctx.frame.verifyBtn.lastText = "stale"
    ctx.frame.fullScanBtn.lastBusy = "stale"
    setUpvalue(ctx.setView, "view", "sell")

    ctx.setView("deals")

    assert.equal("AUTO", ctx.frame.autoBtn.lastText)
    assert.equal("HIDDEN 0", ctx.frame.verifyBtn.lastText)
    assert.is_false(ctx.frame.fullScanBtn.lastBusy)
  end)

  -- Rides this harness because it is the only one with a real toolbar on it. That toggle's
  -- first label went through GC.L and every label after it did not, so the button read
  -- "HIDDEN 3" in English on every client the moment anything was hidden -- the initial
  -- stamp was the only translated one a player ever saw.
  it("says HIDDEN and REFUSED in the player's own language", function()
    local ctx = buildFrame()
    ctx.GC.Locales.xxTest = { ["HIDDEN %d"] = "hidden-%d", ["REFUSED %d"] = "refused-%d" }
    ctx.GC.ActivateLocale("xxTest")
    setUpvalue(ctx.setView, "view", "sell")

    ctx.setView("deals")
    assert.equal("hidden-0", ctx.frame.verifyBtn.lastText)

    -- GC.db is only built on ADDON_LOADED, which no spec fires; showRefused reads it straight.
    ctx.GC.db = { settings = { sniper = { showRefused = true } } }
    setUpvalue(ctx.setView, "view", "sell")
    ctx.setView("deals")
    assert.equal("refused-0", ctx.frame.verifyBtn.lastText)

    ctx.GC.ActivateLocale(nil)
  end)
end)
