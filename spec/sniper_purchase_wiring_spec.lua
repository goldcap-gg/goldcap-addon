local helper = require("spec.spec_helper")

-- This protects the UI boundary around the pure SniperDecision engine. The static checks make
-- the protected WoW calls auditable; the fixture below also runs the real price-update handler
-- with a failed 4% requote, so the safety branch is not merely a source-text convention.
describe("Sniper purchase wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local function section(text, first, last)
    local from = assert(text:find(first, 1, true), first)
    local to = assert(text:find(last, from + #first, true), last)
    return text:sub(from, to - 1)
  end

  -- onDialogPrimaryClick and nothing else: from its header to its own closing `end`, the first
  -- line-start `end` after it (every line of its body is indented). The next section marker in the
  -- file sits two hundred lines further on, past the quantity helpers the dialog's Quantity row
  -- uses -- a slice that ran to it let a protected call in applyChosenQty or refreshQtyRow pass as
  -- the click handler's own (caps fixes 5, review round 1). Returns the slice, where it starts and
  -- the first position after it.
  local CLICK = "local function onDialogPrimaryClick()"
  local function clickHandler(text)
    local from = assert(text:find(CLICK, 1, true), CLICK)
    local _, stop = assert(text:find("\nend\n", from, true))
    return text:sub(from, stop), from, stop + 1
  end

  it("slices the click handler alone", function()
    local click = clickHandler(source())
    assert.is_nil(click:find("\nlocal function ", 1, true))
    assert.is_nil(click:find("\nfunction ", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.PlaceBid", 1, true)) -- and all of it
  end)

  it("keeps purchase calls in the hardware-click handler and starts exact decision quantity", function()
    local text = source()
    local click = clickHandler(text)

    assert.is_truthy(click:find("C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.PlaceBid", 1, true))
    local nonCommodityGate = assert(click:find("if not deal.isCommodity", 1, true))
    local placeBid = assert(click:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_true(nonCommodityGate < placeBid)
    assert.is_truthy(click:find("quoteSnapshot", 1, true))
    assert.is_truthy(click:find("quoteSnapshot.decision.status ~= \"SAFE\"", 1, true))
    assert.is_truthy(click:find("commodityDraining", 1, true))

    local _, from, to = clickHandler(text)
    local before, after = text:sub(1, from - 1), text:sub(to)
    assert.is_nil(before:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.PlaceBid", 1, true))
  end)

  -- Caps fixes 5e. The test above reads one file for three exact call strings, so a protected
  -- call written anywhere else passed it: in another file, under an alias
  -- (`local buy = C_AuctionHouse.PlaceBid`), or indexed by a string (`C_AuctionHouse["PlaceBid"]`).
  -- So every Lua file under GoldCap/ is read with its comments blanked out, and every mention of
  -- the three names -- a call, a field, a string, whatever -- has to be one of the allowed sites:
  -- the Sniper dialog's hardware click (all three), the BUY tab's own button handler (the two
  -- commodity calls), and Core/PurchaseCapture.lua's passive post-hooks, which observe a call and
  -- cannot make one.
  describe("across every file", function()
    local PROTECTED = { "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }

    local function read(path)
      local f = assert(io.open(path, "r"))
      local text = f:read("*a")
      f:close()
      return text
    end

    -- Comments become spaces (newlines kept), so every offset and line number still matches the
    -- file; strings are kept, because a name inside a string is exactly how an indexed call is
    -- spelled.
    local function blankComments(text)
      local out, i, n = {}, 1, #text
      while i <= n do
        local s = text:find("[%-%[\"']", i)
        if not s then out[#out + 1] = text:sub(i); break end
        out[#out + 1] = text:sub(i, s - 1)
        local c = text:sub(s, s)
        if c == "-" and text:sub(s, s + 1) == "--" then
          local eq = text:match("^%[(=*)%[", s + 2)
          local stop
          if eq then
            local _, e = text:find("]" .. eq .. "]", s + 2, true)
            stop = e or n
          else
            stop = (text:find("\n", s, true) or (n + 1)) - 1
          end
          out[#out + 1] = (text:sub(s, stop):gsub("[^\n]", " "))
          i = stop + 1
        elseif c == "[" and text:match("^%[=*%[", s) then
          local eq = text:match("^%[(=*)%[", s)
          local _, e = text:find("]" .. eq .. "]", s, true)
          e = e or n
          out[#out + 1] = text:sub(s, e)
          i = e + 1
        elseif c == "\"" or c == "'" then
          local j = s + 1
          while j <= n do
            local ch = text:sub(j, j)
            if ch == "\\" then j = j + 2
            elseif ch == c or ch == "\n" then break
            else j = j + 1 end
          end
          out[#out + 1] = text:sub(s, j)
          i = j + 1
        else
          out[#out + 1] = c
          i = s + 1
        end
      end
      return table.concat(out)
    end

    local function span(text, first, last)
      local from = assert(text:find(first, 1, true), first)
      local to = assert(text:find(last, from + #first, true), last)
      return from, to
    end

    -- path -> function(text, pos, name) -> whether this mention is an allowed site.
    local function allowedSites()
      local sniper = read("GoldCap/UI/SniperFrame.lua")
      local _, dialogFrom, dialogTo = clickHandler(sniper)
      local buy = read("GoldCap/UI/BuyFrame.lua")
      local buyFrom, buyTo = span(buy, "local function onBuyClick",
        "-- ---------------------------------------------------------------------------\n-- Rows")
      local function calledAt(text, pos, name, from, to)
        local prefix = "C_AuctionHouse."
        return pos > from and pos < to
          and text:sub(pos - #prefix, pos + #name) == prefix .. name .. "("
      end
      return {
        ["GoldCap/UI/SniperFrame.lua"] = function(text, pos, name)
          return calledAt(text, pos, name, dialogFrom, dialogTo)
        end,
        ["GoldCap/UI/BuyFrame.lua"] = function(text, pos, name)
          return name ~= "PlaceBid" and calledAt(text, pos, name, buyFrom, buyTo)
        end,
        ["GoldCap/Core/PurchaseCapture.lua"] = function(text, pos, name)
          local hook = 'hooksecurefunc(C_AuctionHouse, "'
          return text:sub(pos - #hook, pos + #name + 1) == hook .. name .. '",'
        end,
      }
    end

    local function mentions(path)
      local text = blankComments(read(path))
      local found = {}
      for _, name in ipairs(PROTECTED) do
        local from = 1
        while true do
          local s, e = text:find("%f[%w_]" .. name .. "%f[^%w_]", from)
          if not s then break end
          local _, newlines = text:sub(1, s):gsub("\n", "")
          found[#found + 1] = { pos = s, name = name, line = newlines + 1, text = text }
          from = e + 1
        end
      end
      return found
    end

    local function luaFiles()
      local files = {}
      local listing = assert(io.popen('find GoldCap -name "*.lua"'))
      for path in listing:lines() do files[#files + 1] = path end
      listing:close()
      table.sort(files)
      return files
    end

    local function audit()
      local allowed, violations, sites = allowedSites(), {}, {}
      for _, path in ipairs(luaFiles()) do
        for _, m in ipairs(mentions(path)) do
          local ok = allowed[path]
          if ok and ok(m.text, m.pos, m.name) then
            sites[#sites + 1] = path .. " " .. m.name
          else
            violations[#violations + 1] = ("%s:%d %s"):format(path, m.line, m.name)
          end
        end
      end
      table.sort(sites)
      return violations, sites
    end

    it("finds every protected name only at an allowed site", function()
      local violations, sites = audit()
      assert.same({}, violations)
      -- A scan that found nothing would pass the line above in silence.
      assert.same({
        "GoldCap/Core/PurchaseCapture.lua ConfirmCommoditiesPurchase",
        "GoldCap/Core/PurchaseCapture.lua PlaceBid",
        "GoldCap/Core/PurchaseCapture.lua StartCommoditiesPurchase",
        "GoldCap/UI/BuyFrame.lua ConfirmCommoditiesPurchase",
        "GoldCap/UI/BuyFrame.lua StartCommoditiesPurchase",
        "GoldCap/UI/SniperFrame.lua ConfirmCommoditiesPurchase",
        "GoldCap/UI/SniperFrame.lua PlaceBid",
        "GoldCap/UI/SniperFrame.lua StartCommoditiesPurchase",
      }, sites)
    end)

    it("sees an alias, a string index and a call in another file, and not a comment", function()
      local text = blankComments(table.concat({
        "-- C_AuctionHouse.PlaceBid(1, 2) is only a comment",
        "--[[ C_AuctionHouse.StartCommoditiesPurchase(1, 2) ]]",
        "local buy = C_AuctionHouse.PlaceBid",
        'local confirm = C_AuctionHouse["ConfirmCommoditiesPurchase"]',
        "local s = '-- not a comment'; C_AuctionHouse.StartCommoditiesPurchase(1, 2)",
      }, "\n"))
      local seen = {}
      for _, name in ipairs(PROTECTED) do
        for _ in text:gmatch("%f[%w_]" .. name .. "%f[^%w_]") do seen[#seen + 1] = name end
      end
      table.sort(seen)
      assert.same({ "ConfirmCommoditiesPurchase", "PlaceBid", "StartCommoditiesPurchase" }, seen)
    end)

    -- Final review m5. The audit above keeps every purchase call inside the two click handlers;
    -- this keeps the handlers themselves behind the player's own input. Each is named only where
    -- it is defined and where the engine's hardware wiring hands it the click or the key -- never
    -- called from anywhere else -- and nothing in the addon clicks a button, or runs a button's
    -- script, from code.
    -- Follow-up 3: the bracket spelling too -- `btn["Click"](btn)`, `btn['Click'](btn)`.
    local PROGRAMMATIC = { "[:%.]Click%s*%(", "%[%s*[\"']Click[\"']%s*%]",
      "GetScript%s*%(%s*[\"']OnClick", "GetScript%s*%(%s*[\"']OnKeyDown", "ExecuteFrameScript" }

    -- Every line of `text` (comments blanked) naming `name`, trimmed, with the position of the name.
    local function namedAt(text, name)
      local found, from = {}, 1
      while true do
        local s, e = text:find("%f[%w_]" .. name .. "%f[^%w_]", from)
        if not s then break end
        local lineStart = (text:sub(1, s):match(".*()\n") or 0) + 1
        local lineEnd = (text:find("\n", s, true) or (#text + 1)) - 1
        found[#found + 1] = { pos = s, line = text:sub(lineStart, lineEnd):match("^%s*(.-)%s*$") }
        from = e + 1
      end
      return found
    end

    -- What breaks the rule in `path`'s `text` (comments already blanked): a mention of a click
    -- handler that is not one of its allowed sites, or a programmatic click anywhere.
    local function handlerViolations(path, text)
      local bad = {}
      for _, pattern in ipairs(PROGRAMMATIC) do
        if text:find(pattern) then bad[#bad + 1] = path .. " " .. pattern end
      end
      if path == "GoldCap/UI/SniperFrame.lua" or path == "test/sniper" then
        for _, m in ipairs(namedAt(text, "onDialogPrimaryClick")) do
          if m.line ~= "local function onDialogPrimaryClick()"
              and m.line ~= 'primaryBtn:SetScript("OnClick", onDialogPrimaryClick)' then
            bad[#bad + 1] = path .. " " .. m.line
          end
        end
      elseif path == "GoldCap/UI/BuyFrame.lua" or path == "test/buy" then
        local function inside(pos, opener)
          local from = text:find(opener, 1, true)
          local to = from and text:find("\n  end)\n", from, true)
          return from ~= nil and to ~= nil and pos > from and pos < to
        end
        for _, m in ipairs(namedAt(text, "onBuyClick")) do
          local ok = m.line == "local function onBuyClick(line)"
            or (m.line == "onBuyClick(lineFor(row.lineItemID))"
              and inside(m.pos, 'row.action:SetScript("OnClick", function()'))
            or (m.line == "onBuyClick(line)"
              and inside(m.pos, 'container:SetScript("OnKeyDown", function(self, key)'))
          if not ok then bad[#bad + 1] = path .. " " .. m.line end
        end
      else
        for _, name in ipairs({ "onDialogPrimaryClick" }) do
          if #namedAt(text, name) > 0 then bad[#bad + 1] = path .. " " .. name end
        end
      end
      return bad
    end

    it("reaches the two purchase click handlers only through the player's own input", function()
      local violations = {}
      for _, path in ipairs(luaFiles()) do
        for _, v in ipairs(handlerViolations(path, blankComments(read(path)))) do
          violations[#violations + 1] = v
        end
      end
      assert.same({}, violations)
      -- A scan that found nothing would pass the line above in silence.
      assert.equal(2, #namedAt(blankComments(read("GoldCap/UI/SniperFrame.lua")), "onDialogPrimaryClick"))
      assert.equal(3, #namedAt(blankComments(read("GoldCap/UI/BuyFrame.lua")), "onBuyClick"))
    end)

    it("sees a direct call, a stray reference and a programmatic click, and not a comment", function()
      local sniper = blankComments(table.concat({
        "local function onDialogPrimaryClick()",
        "end",
        '  primaryBtn:SetScript("OnClick", onDialogPrimaryClick)',
        "-- onDialogPrimaryClick() in a comment",
        "C_Timer.After(1, onDialogPrimaryClick)",
        "  dialog.primaryBtn:Click()",
        "  dialog.primaryBtn['Click'](dialog.primaryBtn)",
      }, "\n"))
      assert.same({ "test/sniper [:%.]Click%s*%(", "test/sniper %[%s*[\"']Click[\"']%s*%]",
        "test/sniper C_Timer.After(1, onDialogPrimaryClick)" }, handlerViolations("test/sniper", sniper))
      assert.same({ "test/other %[%s*[\"']Click[\"']%s*%]" },
        handlerViolations("test/other", blankComments('local b = f; b["Click"](b)\n-- b["Click"](b)')))
      local buy = blankComments(table.concat({
        "local function onBuyClick(line)",
        "end",
        '  row.action:SetScript("OnClick", function()',
        "    onBuyClick(lineFor(row.lineItemID))",
        "  end)",
        "  onBuyClick(lineFor(row.lineItemID))",
        'local handler = row.action:GetScript("OnClick")',
      }, "\n"))
      assert.same({ "test/buy GetScript%s*%(%s*[\"']OnClick", "test/buy onBuyClick(lineFor(row.lineItemID))" },
        handlerViolations("test/buy", buy))
    end)
  end)

  it("the dialog claims the slot before it starts a purchase", function()
    local text = source()
    local click = clickHandler(text)

    local claim = assert(click:find("GC.PurchaseSlot.Claim(\"sniper\"", 1, true))
    local start = assert(click:find("C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)", 1, true))
    assert.is_true(claim < start)
    assert.is_truthy(click:find("not GC.PurchaseSlot.Claim(\"sniper\"", 1, true))
  end)

  it("keeps a shadowed SAFE decision on the Check path", function()
    local text = source()
    local arm = section(text, "local function armReady", "local function armCheck")
    local click = clickHandler(text)

    -- A shadow result is public WATCH/buyable=false; only that public contract can arm or
    -- reach a protected WoW call. `computedStatus` is display evidence, never an arm key.
    assert.is_truthy(arm:find("not decision.buyable or decision.status ~= \"SAFE\"", 1, true))
    assert.is_nil(arm:find("computedStatus", 1, true))
    assert.is_truthy(click:find("decision.status ~= \"SAFE\" or not decision.buyable", 1, true))
    assert.is_nil(click:find("computedStatus", 1, true))
  end)

  it("renders complete non-actionable shadow diagnostics", function()
    local text = source()
    local diagnostic = section(text, "local function stampDialogFromDecision", "local function copyReasons")

    assert.is_truthy(diagnostic:find("dialog.diagnosticText:SetText", 1, true))
    assert.is_truthy(diagnostic:find("computed=%s public=%s buyable=%s reasons=%s", 1, true))
    assert.is_truthy(diagnostic:find("table.concat(decision.reasons or {}, \", \")", 1, true))

    -- The item ID leads the diagnostic. The dialog's own header cannot carry it: setDialogHeader
    -- writes "item <id>" only until Item:ContinueOnItemLoad overwrites it with the localized
    -- name. A name is not an identity -- tiered reagents share one name across several IDs
    -- (Argentleaf is both 236776 and 236777), so a shadow observation recorded from the name
    -- alone cannot be attributed to an item after the fact.
    assert.is_truthy(diagnostic:find("item=%d computed=%s public=%s buyable=%s reasons=%s", 1, true))
  end)

  it("sizes, banners, and shrinks a stateful full-reasons diagnostic", function()
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return {} end },
      -- The diagnostic line only measures/shows with debug on (fix round N) -- this spec is
      -- specifically about that auto-sizing behaviour, which stays byte-identical to before
      -- once it is on, so it turns debug on rather than asserting the (separately covered)
      -- default-off/no-measurement case.
      db = { settings = { sniper = { debug = true } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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
    local priceUpdated = GC.Sniper.OnCommodityPriceUpdated
    local stamp = getUpvalue(priceUpdated, "stampDialogFromDecision")
    local showBanner = getUpvalue(priceUpdated, "showRequoteBanner")
    local hideBanner = getUpvalue(priceUpdated, "hideRequoteBanner")
    local diagnosticHeight, dialogHeight, statusAnchors = nil, nil, {}
    local function textSink()
      return { SetText = function() end, SetTextColor = function() end, Show = function() end, Hide = function() end }
    end
    local diagnosticText = { text = "" }
    function diagnosticText:SetText(text) self.text = text end
    function diagnosticText:GetStringHeight()
      return #self.text > 200 and 260 or 24 -- simulates wrapped 1.3x-font reason evidence
    end
    function diagnosticText:SetHeight(height) diagnosticHeight = height end
    function diagnosticText:ClearAllPoints() end
    function diagnosticText:SetPoint() end
    function diagnosticText:Show() end
    function diagnosticText:Hide() end
    local banner = {
      shown = false,
      head = textSink(),
      detail = textSink(),
    }
    function banner:IsShown() return self.shown end
    function banner:Show() self.shown = true end
    function banner:Hide() self.shown = false end
    local fakeDialog = {
      fixedHeight = 400, diagnosticGaps = 4, diagnosticMinimumHeight = 108,
      detailsOpen = false, evidenceTopOpen = -200, evidenceTopClosed = -100,
      SetHeight = function(_, height) dialogHeight = height end,
      banner = banner,
      diagnosticText = diagnosticText,
      status = {
        ClearAllPoints = function() end,
        SetPoint = function(_, ...) statusAnchors[#statusAnchors + 1] = { ... } end,
      },
      decisionStatusText = textSink(), quantityText = textSink(), unitPriceText = textSink(),
      totalCostText = textSink(), exitUnitText = textSink(), profitText = textSink(),
      mvText = textSink(), soldText = textSink(), sellThroughText = textSink(),
      sourceAgeText = textSink(), reasonText = textSink(),
      verdictHead = textSink(), verdictSub = textSink(),
      mvNote = { Hide = function() end, ClearAllPoints = function() end, SetPoint = function() end },
    }
    setUpvalue(stamp, "dialog", fakeDialog)
    setUpvalue(stamp, "marketForDecision", function() return {} end)

    local maximalReasons = {}
    for i = 1, 32 do maximalReasons[i] = ("maximum_length_reason_%02d"):format(i) end
    stamp({ itemID = 42 }, {
      computedStatus = "SAFE", status = "WATCH", buyable = false, quantity = 1,
      reasons = maximalReasons,
    })

    assert.equal(260, diagnosticHeight)
    assert.equal(664, dialogHeight) -- fixed + diagnostic + grid→diagnostic/status gaps
    assert.same({ "TOPLEFT", fakeDialog.diagnosticText, "BOTTOMLEFT", 0, -2 }, statusAnchors[1])

    showBanner("PRICE ROSE", "still safe")
    assert.equal(710, dialogHeight) -- banner height stays additive to the measured base

    stamp({ itemID = 42 }, {
      computedStatus = "WATCH", status = "WATCH", buyable = false, quantity = 1,
      reasons = { "brief" },
    })
    hideBanner()
    assert.equal(108, diagnosticHeight)
    assert.equal(512, dialogHeight) -- reused dialog resets to its short diagnostic base

    -- Behavioural counterpart to the source-text check above: the ID actually reaches the
    -- rendered evidence line, for the exact deal the dialog was stamped from.
    assert.equal("item=42 computed=WATCH public=WATCH buyable=no reasons=brief", diagnosticText.text)
  end)

  it("requires a newly evaluated safe quote, cancels a broken requote, and records one purchase fact", function()
    local text = source()
    local quote = section(text, "function GC.Sniper.OnCommodityPriceUpdated", "function GC.Sniper.OnCommodityPriceUnavailable")
    local accounting = section(text, "local function recordPurchaseFacts", "local function reportDetachedCommodity")

    assert.is_truthy(quote:find("evaluateLive", 1, true))
    assert.is_truthy(quote:find("C_AuctionHouse.CancelCommoditiesPurchase()", 1, true))
    assert.is_truthy(quote:find("requote_broke_safety", 1, true))
    assert.is_truthy(quote:find("drainCommodityPurchase(row)", 1, true))
    assert.is_truthy(accounting:find("purchase.total", 1, true))
    assert.is_truthy(accounting:find("GC.Data.RecordFlip(deal, purchase", 1, true))
    assert.is_truthy(accounting:find("GC.Ledger.RecordSniperBuy(deal, purchase", 1, true))
    assert.is_truthy(accounting:find("GC.Acquisitions.RecordGoldCap(deal, purchase", 1, true))
  end)

  it("cancels a sub-five-percent failed requote before any confirm can run", function()
    -- The integration fixture intentionally supplies a final server total that is only 4%
    -- higher, but whose stress math fails. This must cancel on economics, not rely on the old
    -- 5% visual-warning threshold; no event is permitted to confirm a protected purchase.
    local cancelCalls, confirmCalls = 0, 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true }
    local row = {
      purchaseStage = "buying", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)
    -- The cancel re-runs the live requery on its own (owner-reported 2026-09-11: a 64-unit
    -- plan with 38 left bounced to "Check again", then the tombstone refused the next Buy).
    -- The search itself is stubbed at the driver seam; the book it answers with is below.
    local sends = 0
    local startRequery = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")
    setUpvalue(startRequery, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() sends = sends + 1 end,
      commodityBook = function() return { { unitPrice = 1000000, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    })

    -- The fresh book still begins at 100g; a 104g server quote makes the 100g stress-profit
    -- boundary fail. The real handler must cancel before any button can be a Confirm path.
    _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
    _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index)
      if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
      return { unitPrice = 2105265, quantity = 1 }
    end
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)

    assert.equal(1, cancelCalls)
    assert.equal(0, confirmCalls)
    -- Not "check": the requery is already on its way, with the stale snapshots gone.
    assert.equal("requerying", row.purchaseStage)
    assert.equal(1, sends)
    assert.is_nil(row.decisionSnapshot)
    assert.is_nil(row.quoteSnapshot)
    assert.is_nil(row.purchaseDeal)

    -- The cancellation remains owned until a terminal event. A second late price must be
    -- drained too; otherwise its terminal event could be misattributed to a later Start.
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    assert.is_true(draining.fenceRow == row)
    assert.equal(row.purchaseToken, draining.fenceToken)
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == draining)

    -- A search reply for a DIFFERENT requery -- neither fenced on the tombstone nor started after
    -- it went down, so its search may predate the cancel -- is no proof: the tombstone stays.
    draining.fenceToken = draining.fenceToken + 100
    getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42].afterTombstone = nil
    -- The result is judged WATCH so the row lands on Check without a dialog to arm.
    GC.SniperDecision.Evaluate = function()
      return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
    end
    GC.Sniper.OnCommoditySearchResults(42)
    assert.equal("check", row.purchaseStage)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == draining)
    GC.Sniper.OnCommodityPurchaseFailed()
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  -- Live price caps, final review C1. A cap is the player's own price and needs no market read
  -- (Core/Caps.lua's own contract), so the items a cap exists for are exactly the ones the
  -- market engine refuses: no value, no sell-through, no velocity. Re-judging the server's
  -- quote with that engine cancelled every capped commodity purchase -- cancel, requery, the
  -- cap decides it again, quote again, cancel again -- a loop no click could break. The quote
  -- is judged by the cap that armed it, and the one thing that may never be waved through is a
  -- quote ABOVE the cap. No protected call is issued from this event either way.
  it("arms Confirm on a capped commodity the market engine would refuse", function()
    local cancelCalls, confirmCalls = 0, 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end,
      GetNumCommoditySearchResults = function() return 1 end,
      GetCommoditySearchResultInfo = function() return { unitPrice = 900000, quantity = 5 } end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end
    -- No import value at all for item 42: every market gate refuses it, which is the whole
    -- premise of the bug.
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {},
      caps = { { i = 42, c = 1000000 } } }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    GC.Caps.Adopt()

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    -- The board's own cap deal (buildCapDeal's shape) and the decision GC.Caps.DecideCommodity
    -- armed it with: five units at 9g against a 10g cap, no market figures anywhere.
    local deal = { itemID = 42, isCommodity = true, cap = 1000000, unitPrice = 900000, qty = 5 }
    local row = {
      purchaseStage = "buying", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      decisionSnapshot = { status = "SAFE", buyable = true, cap = true, quantity = 2,
        unit = 900000, stressProfit = 200000 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() end,
      commodityBook = function() return { { unitPrice = 900000, quantity = 5 } } end,
      commodityResult = function() return { avail = 5 } end,
    })

    GC.Sniper.OnCommodityPriceUpdated(900000, 1800000)

    assert.equal(0, cancelCalls)
    assert.equal(0, confirmCalls) -- the event never confirms; the player's next click does
    assert.equal("confirm", row.purchaseStage)
    assert.is_table(row.quoteSnapshot)
    assert.is_true(row.quoteSnapshot.decision.buyable)
    assert.equal("SAFE", row.quoteSnapshot.decision.status)
    assert.is_true(row.quoteSnapshot.decision.cap)

    -- And the one case that must still refuse: the same book, quoted ABOVE the player's price.
    row.purchaseStage, row.quoteSnapshot = "buying", nil
    row.decisionSnapshot = { status = "SAFE", buyable = true, cap = true, quantity = 2,
      unit = 900000, stressProfit = 200000 }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    GC.Sniper.OnCommodityPriceUpdated(1100000, 2200000)

    assert.equal(1, cancelCalls)
    assert.equal(0, confirmCalls)

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
    _G.GoldCap_AppRuns = nil
  end)

  -- Final review M2. A quote that crosses the player's own ceiling is always loud (task 7), but
  -- the banner was built from a ratio against `entryTotal` -- which a cap decision does not
  -- have, because it is the player's price and not a quote the market made. So the loud path
  -- read a nil: at best it announced "PRICE ROSE 1.0x" over a breach that was not a rise at
  -- all, at worst it divided by nothing. It now says which two numbers disagree.
  it("names the cap on a breached quote instead of a price-rise multiple", function()
    local cancelCalls, confirmCalls, status = 0, 0, {}
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end,
      GetNumCommoditySearchResults = function() return 1 end,
      GetCommoditySearchResultInfo = function() return { unitPrice = 1050000, quantity = 5 } end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {},
      caps = { { i = 42, c = 1000000 } } }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return { mv = 3000000, kind = "region_commodity" } end },
      db = { settings = { sniper = { sound = false, maxCapitalShare = 0.05,
        maxDailyDemandShare = 0.02, maxQuantity = 200, minimumProfitCopper = 1,
        minimumRoi = 0.01 } } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    GC.Caps.Adopt()
    -- The MARKET still approves this quote; only the player's own ceiling refuses it, which is
    -- the one arrangement that reaches the loud banner at all.
    GC.SniperDecision.Evaluate = function()
      return { status = "SAFE", buyable = true, quantity = 2, entryTotal = 2100000,
        stressProfit = 1, reasons = {} }
    end

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true, cap = 1000000, unitPrice = 1050000, qty = 2 }
    local row = {
      purchaseStage = "buying", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      -- Armed by the cap: no entryTotal anywhere on it, and priced a hair under the quote, so
      -- the ratio alone would have called this "none" and printed 1.0x if it printed anything.
      decisionSnapshot = { status = "SAFE", buyable = true, cap = true, quantity = 2,
        unit = 1050000, stressProfit = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "frame",
      { status = { SetText = function(_, text) status[#status + 1] = text end } })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() end,
      commodityBook = function() return { { unitPrice = 1050000, quantity = 5 } } end,
      commodityResult = function() return { avail = 5 } end,
    })

    GC.Sniper.OnCommodityPriceUpdated(1050000, 2100001)

    assert.equal(0, cancelCalls)
    assert.equal(0, confirmCalls)
    assert.equal("requote", row.purchaseStage)
    local last = status[#status]
    assert.is_truthy(last:find("Above your price", 1, true))
    assert.is_nil(last:find("PRICE ROSE", 1, true))
    assert.is_nil(last:find("still safe", 1, true))

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
    _G.GoldCap_AppRuns = nil
  end)

  it("retires the cancel's tombstone when the requery it started answers", function()
    local cancelCalls = 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() end,
      GetNumCommoditySearchResults = function() return 2 end,
      GetCommoditySearchResultInfo = function(_, index)
        if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
        return { unitPrice = 2105265, quantity = 1 }
      end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true }
    local row = {
      purchaseStage = "buying", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)
    local startRequery = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")
    setUpvalue(startRequery, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() end,
      commodityBook = function() return { { unitPrice = 1000000, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    })

    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000) -- breaks safety -> cancel + requery
    assert.equal(1, cancelCalls)
    assert.equal("requerying", row.purchaseStage)
    assert.is_table(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

    -- The reply to the search sent after the Cancel is the fence: nothing from the cancelled
    -- attempt can still be on its way, so the next Buy must not be refused for it.
    GC.SniperDecision.Evaluate = function()
      return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
    end
    GC.Sniper.OnCommoditySearchResults(42)
    assert.equal("check", row.purchaseStage)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  -- Owner-reported, reproducible on many items: BUY on a SAFE row bounced straight to "the
  -- price moved and the trade is no longer safe" with an em dash for the entry price, and a
  -- second Check came back SAFE at the SAME numbers, after which BUY worked. The client keeps
  -- ONE commodity search buffer: a dialog armed off the hover pre-warm cache opens with that
  -- buffer holding whatever the verify walk looked at last, and the final re-evaluation read
  -- it blind. What the Check "fixed" was only the buffer.
  it("re-checks against the armed book when the client's buffer holds another item", function()
    local cancelCalls, confirmCalls = 0, 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end,
      -- The buffer belongs to item 99 -- the last thing the background walk searched. Asking
      -- it about item 42 is what the real API does: nothing for the item that was not queried.
      GetNumCommoditySearchResults = function(itemID) return itemID == 99 and 2 or 0 end,
      GetCommoditySearchResultInfo = function(itemID, index)
        if itemID ~= 99 then return nil end
        if index == 1 then return { unitPrice = 7, quantity = 500 } end
        return { unitPrice = 9, quantity = 500 }
      end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    -- The book the SAFE decision was actually made on, exactly as armReady stamped it.
    local armed = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 2105265, quantity = 1 } }
    local row = {
      purchaseStage = "buying", purchaseToken = 7,
      purchaseDeal = { itemID = 42, isCommodity = true },
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1,
        entryTotal = 1000000 },
      armedLevels = armed, armedItemID = 42,
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    -- Nothing moved: the server quotes the same total the decision was made at.
    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000)
    assert.equal(0, cancelCalls)
    assert.equal(0, confirmCalls) -- only a hardware click confirms; this reaches "confirm"
    assert.equal("confirm", row.purchaseStage)
    assert.is_table(row.quoteSnapshot)
    assert.equal(1000000, row.quoteSnapshot.total)

    -- And the fallback is not a rubber stamp: a total that genuinely breaks the stress math
    -- still cancels, off the very same armed book.
    row.purchaseStage = "buying"
    row.quoteSnapshot = nil
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    local requeried
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery", function(r) requeried = r end)
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)
    assert.equal(1, cancelCalls)
    assert.equal(0, confirmCalls)
    assert.is_true(requeried == row) -- cancelled, and straight into a fresh live requery

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  -- CancelCommoditiesPurchase produces none of the three terminal events that consume a
  -- tombstone, so before this an unconfirmed cancellation blocked every later commodity buy
  -- with "waiting for previous commodity purchase to settle" until the player happened to close
  -- the Auction House. An unconfirmed attempt never called ConfirmCommoditiesPurchase, so no
  -- gold can have moved and no late event can credit a purchase to the wrong row -- retiring it
  -- on a timer is safe. A CONFIRMED tombstone still waits forever: its late success must land.
  it("retires an unconfirmed drain tombstone on its own timer, but never a confirmed one", function()
    local cancelCalls, timers = 0, {}
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() end,
      GetNumCommoditySearchResults = function() return 2 end,
      GetCommoditySearchResultInfo = function(_, index)
        if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
        return { unitPrice = 2105265, quantity = 1 }
      end,
    }
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local row = {
      purchaseStage = "buying", purchaseToken = 7,
      purchaseDeal = { itemID = 42, isCommodity = true },
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery", function() end)
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000) -- breaks safety -> cancel + drain
    assert.equal(1, cancelCalls)
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    assert.is_falsy(draining.confirmed)

    -- Other timers (arm timeouts and the like) are scheduled along the same path; each is run
    -- under pcall so an unrelated one cannot decide this example's outcome either way.
    local function runTimers()
      for _, timer in ipairs(timers) do pcall(timer.fn) end
    end
    runTimers()
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

    -- The retirement must be bound to the exact tombstone it was scheduled for: replaying those
    -- same callbacks against a later CONFIRMED tombstone must leave it completely alone.
    local confirmedTombstone = { row = {}, itemID = 42, token = 11, confirmed = true }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", confirmedTombstone)
    runTimers()
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == confirmedTombstone)

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  it("freezes a commodity success without a matching final quote instead of estimating a purchase", function()
    local flipCalls, ledgerCalls = 0, 0
    _G.C_AuctionHouse = {}
    _G.GetTime = function() return 0 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return {} end, RecordFlip = function() flipCalls = flipCalls + 1 end },
      Ledger = { RecordSniperBuy = function() ledgerCalls = ledgerCalls + 1 end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true }
    local row = { purchaseStage = "confirming", purchaseToken = 3, deal = deal, purchaseDeal = deal }
    setUpvalue(GC.Sniper.OnCommodityPurchaseSucceeded, "commodityPurchase", {
      row = row, itemID = 42, token = 3, confirmed = true, deal = row.purchaseDeal,
    })
    GC.Sniper.OnCommodityPurchaseSucceeded()

    assert.equal("frozen", row.purchaseStage)
    assert.equal(0, flipCalls)
    assert.equal(0, ledgerCalls)
    _G.C_AuctionHouse, _G.GetTime = nil, nil
  end)

  it("retains a commodity tombstone through late prices until its terminal event", function()
    local cancelCalls = 0
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local old = { row = { purchaseToken = 1 }, itemID = 42, token = 1 }
    local newerRow = { purchaseToken = 2, purchaseStage = "buying", purchaseDeal = { itemID = 42, isCommodity = true } }
    local newer = { row = newerRow, itemID = 42, token = 2 }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", old)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", newer)

    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000) -- late price for the drained old attempt

    assert.equal(1, cancelCalls)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == old)
    assert.equal("buying", newerRow.purchaseStage)

    GC.Sniper.OnCommodityPurchaseFailed() -- terminal failure belonging to the drained old attempt
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining"))
    assert.equal("buying", newerRow.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("keeps a delayed price tombstone until a terminal event", function()
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { row = {}, itemID = 42, token = 1 })
    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000)
    assert.is_table(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
    _G.C_AuctionHouse = nil
  end)

  it("records the confirmed final quote exactly once after an AH-close tombstone", function()
    local flipPurchase, ledgerPurchase, confirmCalls, cancelDisabled = nil, nil, 0, false
    _G.time = function() return 100000 end
    _G.GetTime = function() return 0 end
    _G.C_AuctionHouse = { ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = {
        GetItemValue = function() return {} end,
        RecordFlip = function(_, purchase) flipPurchase = purchase end,
      },
      Ledger = {
        Context = function() return {} end,
        RecordSniperBuy = function(_, purchase) ledgerPurchase = purchase; return { key = "snipe:42" } end,
      },
      Acquisitions = { RecordGoldCap = function(_, purchase, _, _, key)
        assert.equal("snipe:42", key)
        assert.is_true(purchase == ledgerPurchase)
      end },
      Sell = { Reset = function() end, SellableCount = function() return 0 end },
      Print = function() end,
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local row = {
      purchaseStage = "confirm", purchaseToken = 9,
      purchaseDeal = { itemID = 42, isCommodity = true },
      quoteSnapshot = {
        token = 9, itemID = 42, quantity = 3, total = 123456,
        decision = { version = 1, status = "SAFE", buyable = true, quantity = 3,
          reasons = { "safe" }, exitUnit = 60000, stressProfit = 42000 },
        market = { sourceAt = 99999 },
      },
    }
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end
    -- Follow the real row-click closure chain to the hardware-only Confirm handler and the
    -- exact OnHide abort helper; this is intentionally not a hand-written state transition.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local confirm = getUpvalue(createDialog, "onDialogPrimaryClick")
    local abortOnHide = getUpvalue(createDialog, "abortRowPurchase")
    local fakeDialog = {
      row = row,
      primaryBtn = { Disable = function() end },
      cancelBtn = { Disable = function() cancelDisabled = true end },
      status = { SetText = function() end, SetTextColor = function() end },
      banner = { Hide = function() end },
      SetHeight = function() end,
      Hide = function() end,
      baseHeight = 1,
    }
    setUpvalue(confirm, "dialog", fakeDialog)
    setUpvalue(confirm, "commodityPurchase", { row = row, itemID = 42, token = 9 })

    confirm() -- exact protected click path
    assert.equal(1, confirmCalls)
    assert.is_true(cancelDisabled)
    assert.equal("confirming", row.purchaseStage)
    fakeDialog.row = nil -- exact OnHide ordering before it invokes abortRowPurchase
    abortOnHide(row, "purchase canceled")
    assert.equal("confirming", row.purchaseStage)

    GC.Sniper.OnAuctionHouseClosed()

    -- The pool can be reused in the next AH session before the old, untagged terminal event
    -- arrives. A late success must settle frozen facts only, never clear this new Check.
    local newDeal = { itemID = 99, isCommodity = true }
    local newAttempt = { row = row, itemID = 99, token = 22, deal = newDeal, sent = true }
    local awaiting = { [99] = newAttempt }
    local active = { [99] = true }
    row.deal = newDeal
    row.purchaseStage = "requerying"
    row.purchaseToken = 22
    row.purchaseDeal = nil
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", awaiting)
    local resolve = getUpvalue(GC.Sniper.OnCommodityPurchaseSucceeded, "resolvePurchase")
    setUpvalue(resolve, "activeItemID", active)

    GC.Sniper.OnCommodityPurchaseSucceeded()
    GC.Sniper.OnCommodityPurchaseSucceeded() -- duplicate terminal is a no-op

    assert.is_table(flipPurchase)
    assert.is_true(flipPurchase == ledgerPurchase)
    assert.equal(123456, flipPurchase.total)
    assert.equal(1, GC.Sniper.session.buys)
    assert.equal(123456, GC.Sniper.session.spent)
    assert.equal("requerying", row.purchaseStage)
    assert.is_true(row.deal == newDeal)
    assert.equal(22, row.purchaseToken)
    assert.is_true(awaiting[99] == newAttempt)
    assert.is_true(active[99])
    _G.time, _G.GetTime, _G.C_AuctionHouse = nil, nil, nil
  end)

  it("ignores a stale requery result after its row token advances", function()
    _G.C_AuctionHouse = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local row = { purchaseStage = "requerying", purchaseToken = 2, deal = { itemID = 42, isCommodity = true } }
    local old = { row = row, itemID = 42, token = 1, deal = row.deal }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = old })
    GC.Sniper.OnCommoditySearchResults(42)

    assert.equal("requerying", row.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("settles detached confirmed unavailable and failure without freezing a repooled Check", function()
    local flipCalls, ledgerCalls = 0, 0
    _G.C_AuctionHouse = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = {
        GetItemValue = function() return {} end,
        RecordFlip = function() flipCalls = flipCalls + 1 end,
      },
      Ledger = {
        Context = function() return {} end,
        RecordSniperBuy = function() ledgerCalls = ledgerCalls + 1 end,
      },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local newDeal = { itemID = 99, isCommodity = true }
    local row = { deal = newDeal, purchaseStage = "requerying", purchaseToken = 22 }
    local newAttempt = { row = row, itemID = 99, token = 22, deal = newDeal, sent = true }
    local awaiting = { [99] = newAttempt }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", awaiting)
    local oldDeal = { itemID = 42, isCommodity = true }
    local old = { row = row, itemID = 42, token = 9, confirmed = true, deal = oldDeal }
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityDraining", old)

    GC.Sniper.OnCommodityPriceUnavailable()

    assert.equal("requerying", row.purchaseStage)
    assert.is_true(row.deal == newDeal)
    assert.equal(22, row.purchaseToken)
    assert.is_true(awaiting[99] == newAttempt)
    assert.equal(0, flipCalls)
    assert.equal(0, ledgerCalls)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityDraining"))
    assert.equal("purchase total unavailable — inspect mailbox", GC.Sniper.detachedCommodityStatus[42].note)

    setUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining", old)
    GC.Sniper.OnCommodityPurchaseFailed()

    assert.equal("requerying", row.purchaseStage)
    assert.is_true(row.deal == newDeal)
    assert.equal(22, row.purchaseToken)
    assert.is_true(awaiting[99] == newAttempt)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining"))
    assert.equal("confirmed commodity purchase failed after AH close", GC.Sniper.detachedCommodityStatus[42].note)
    _G.C_AuctionHouse = nil
  end)

  -- Owner-reported 2026-09-11: a 64-unit plan while 38 remained. The server answers
  -- COMMODITY_PRICE_UNAVAILABLE for a quantity it cannot fill, and the old answer was "Gone"
  -- -- for an item with 38 units still sitting there. Unavailable is terminal for the attempt,
  -- so the slot is freed with no tombstone, and the same live requery Check runs re-arms the
  -- dialog at what the book fills now. No purchase call is issued from the event.
  it("re-checks what remains when the server cannot fill the quantity, instead of Gone", function()
    local cancelCalls = 0
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end }
    _G.C_Timer = { After = function() end }
    _G.GetTime = function() return 0 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local statuses = {}
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "frame",
      { status = { SetText = function(_, text) statuses[#statuses + 1] = text end } })
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "refreshRows", function() end)
    local requeried, requeriedDeal
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "startRequery", function(r, d)
      requeried, requeriedDeal = r, d
    end)

    local deal = { itemID = 42, isCommodity = true }
    local row = {
      purchaseStage = "buying", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      decisionSnapshot = { status = "SAFE", buyable = true, quantity = 64 },
      armedLevels = {}, armedItemID = 42,
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "dialog", nil)

    GC.Sniper.OnCommodityPriceUnavailable()

    assert.equal(1, cancelCalls)
    assert.is_true(requeried == row)
    assert.is_true(requeriedDeal == deal)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityPurchase"))
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityDraining"))
    -- The 64-unit plan is gone with the book it was made on; the requery decides afresh.
    assert.is_nil(row.purchaseDeal)
    assert.is_nil(row.decisionSnapshot)
    assert.is_nil(row.armedLevels)
    assert.are_not.equal(nil, row.deal) -- the row itself is not "Gone"
    assert.equal("not enough units left for that quantity -- re-checking what remains...", statuses[#statuses])

    _G.C_AuctionHouse, _G.C_Timer, _G.GetTime = nil, nil, nil
  end)

  it("token-fences an old Check timeout from a newer Check attempt", function()
    local timers = {}
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function getUpvalue(fn, wanted)
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

    -- Reach the same private Check function the row click ultimately uses, through real
    -- closures rather than duplicating its logic in the fixture.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local abortRowPurchase = getUpvalue(createDialog, "abortRowPurchase")
    setUpvalue(startRequery, "driver", {
      isReady = function() return false end,
      getKeyInfo = function() return { isCommodity = true } end,
    })

    local deal = { itemID = 42, isCommodity = true }
    local row = { deal = deal }
    startRequery(row, deal)
    abortRowPurchase(row, nil) -- unsent Check is cancelled locally; no drain is needed
    startRequery(row, deal)

    assert.equal(2, row.purchaseToken)
    assert.equal(2, #timers)
    timers[1]() -- timer for token 1 must not alter the live token-2 Check
    assert.equal("requerying", row.purchaseStage)
    local awaiting = getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")
    assert.equal(2, awaiting[42].token)
    _G.C_Timer = nil
  end)

  it("drains an old search result before it can resolve a newer prewarm attempt", function()
    _G.C_AuctionHouse = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local old = { itemID = 42, token = 1, sent = true }
    local warm = { itemID = 42, token = 2, sent = true, deal = { itemID = 42 } }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [42] = old })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "prewarmAttempt", warm)

    GC.Sniper.OnCommoditySearchResults(42)

    assert.is_nil(getUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining")[42])
    assert.is_true(getUpvalue(GC.Sniper.OnCommoditySearchResults, "prewarmAttempt") == warm)
    _G.C_AuctionHouse = nil
  end)

  it("does not Start while a cancelled requote tombstone still owns commodity events", function()
    local starts = 0
    _G.C_AuctionHouse = { StartCommoditiesPurchase = function() starts = starts + 1 end }
    -- The tombstone's own age decides whether it still refuses (LIM.DRAIN_TIMEOUT_SECONDS);
    -- a fresh one, stamped at this same instant, does.
    _G.GetTime = function() return 0 end
    _G.C_Timer = { After = function() end } -- the Start path arms its own buy timeout
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function getUpvalue(fn, wanted)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local primary = getUpvalue(createDialog, "onDialogPrimaryClick")
    local deal = { itemID = 42, isCommodity = true }
    local row = {
      deal = deal, purchaseStage = "ready", purchaseToken = 5,
      decisionSnapshot = { status = "SAFE", buyable = true, quantity = 3 },
    }
    setUpvalue(primary, "dialog", {
      row = row,
      primaryBtn = { Disable = function() end },
      status = { SetText = function() end, SetTextColor = function() end },
    })
    setUpvalue(primary, "commodityDraining", { itemID = 42, token = 4 })
    local requeried
    setUpvalue(primary, "startRequery", function(r) requeried = r end)

    primary()

    assert.equal(0, starts)
    -- Not a dead click either (in game 2026-09-23): the click is a Check, and that Check's answer
    -- is what retires the tombstone (spec/caps_purchase_spec.lua, "after a purchase attempt was
    -- cancelled").
    assert.is_true(requeried == row)

    -- ...and stops refusing once it has outlived the answer it was waiting for. Nothing else
    -- ever consumes an unconfirmed tombstone: CancelCommoditiesPurchase fires none of the
    -- three terminal events, and neither does an auction house error.
    setUpvalue(primary, "commodityDraining", { itemID = 42, token = 4, drainingAt = 0 })
    _G.GetTime = function() return 30 end
    primary()
    assert.equal(1, starts)
    assert.equal("buying", row.purchaseStage)

    _G.C_AuctionHouse, _G.GetTime, _G.C_Timer = nil, nil, nil
  end)

  it("flushes a throttled watchlist Check exactly once before its timeout can show Gone", function()
    -- Regression target: a Live scanner used to receive the throttle-ready event first while
    -- SniperFrame returned early for `mode == "watchlist"`. The dialog's parked Check then
    -- never sent and its timeout rendered the listing falsely Gone.
    local timers, sends, ready = {}, 0, false
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
      db = { settings = { sniper = {} } },
      SniperDecision = {
        Evaluate = function()
          return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
        end,
      },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local driver = {
      isReady = function() return ready end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() sends = sends + 1 end,
      commodityBook = function() return { { unitPrice = 100, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    }
    setUpvalue(startRequery, "driver", driver)

    local deal = { itemID = 42, isCommodity = true }
    local row = { deal = deal }
    startRequery(row, deal)
    assert.equal(0, sends)

    ready = true
    GC.Sniper.OnThrottleReady()
    GC.Sniper.OnThrottleReady()
    assert.equal(1, sends)

    GC.Sniper.OnCommoditySearchResults(42)
    timers[1]()
    assert.equal("check", row.purchaseStage)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)

  it("switches Check rows without an intervening Live search or ambiguous replacement result", function()
    -- Regression target: onBuyClick used abortRowPurchase(old) as a standalone Cancel. That
    -- synchronously restarted Live before openDialog(new) could register its new Check, so a
    -- Scanner:Start implementation that sends immediately could inject an untagged search.
    local timers, authoritativeSends, liveSends = {}, 0, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 7 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = {
        Evaluate = function()
          return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
        end,
      },
    }
    helper.loadModule("Core/Scanner.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local driver = {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() authoritativeSends = authoritativeSends + 1 end,
      commodityBook = function() return { { unitPrice = 100, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    }
    setUpvalue(startRequery, "driver", driver)
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = GC.Scanner.New({
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      now = function() return 100 end,
      sendSearch = function() liveSends = liveSends + 1 end,
      onStatus = function() end,
    }, {})
    GC.Sniper.scanner:Start({ 7 })
    GC.Sniper.scanner:Stop()
    GC.Sniper._liveTargets = { 7 }
    liveSends = 0

    local oldDeal = { itemID = 42, isCommodity = true }
    local oldRow = { deal = oldDeal, purchaseStage = "requerying", purchaseToken = 1 }
    local oldAttempt = { row = oldRow, itemID = 42, token = 1, deal = oldDeal, sent = false }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = oldAttempt })
    GC.Sniper._pausedLiveRequery = oldAttempt
    setUpvalue(onBuyClick, "dialog", { row = oldRow, Hide = function() end })
    setUpvalue(onBuyClick, "openDialog", function(row, deal) startRequery(row, deal) end)

    local newDeal = { itemID = 43, isCommodity = true }
    local newRow = { deal = newDeal }
    onBuyClick(newRow)

    assert.equal(0, liveSends)
    assert.equal(1, authoritativeSends)
    -- The harness bypasses visual openDialog construction; result ownership itself has no UI
    -- dependency, so remove the old-row shell before dispatching the real event handler.
    setUpvalue(onBuyClick, "dialog", nil)
    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal("check", newRow.purchaseStage)
    assert.is_nil(oldRow.purchaseStage)
    assert.equal(1, liveSends) -- only after the replacement result resolves ownership
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)

  it("releases a transferred Live pause exactly once when B's drain fence clears", function()
    -- Regression target: A→B keeps A's pause owner, but B can be blocked behind a previous
    -- sent B result. The drain handler used to clear only the fence, leaving Live stranded.
    local timers, liveSends = {}, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 7 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = { Evaluate = function() return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } } end },
    }
    helper.loadModule("Core/Scanner.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    setUpvalue(startRequery, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() error("B must not send before its old result drains") end,
    })
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = GC.Scanner.New({
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      now = function() return 100 end,
      sendSearch = function() liveSends = liveSends + 1 end,
      onStatus = function() end,
    }, {})
    GC.Sniper.scanner:Start({ 7 })
    GC.Sniper.scanner:Stop()
    GC.Sniper._liveTargets = { 7 }
    liveSends = 0

    local aDeal = { itemID = 42, isCommodity = true }
    local aRow = { deal = aDeal, purchaseStage = "requerying", purchaseToken = 1 }
    local aAttempt = { row = aRow, itemID = 42, token = 1, deal = aDeal, sent = false }
    local oldB = { itemID = 43, token = 7, sent = true }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = aAttempt })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [43] = oldB })
    GC.Sniper._pausedLiveRequery = aAttempt
    setUpvalue(onBuyClick, "dialog", { row = aRow, Hide = function() end })
    setUpvalue(onBuyClick, "openDialog", function(row, deal)
      setUpvalue(onBuyClick, "dialog", nil) -- bypass visual construction; exercise ownership only
      startRequery(row, deal)
    end)

    local bRow = { deal = { itemID = 43, isCommodity = true } }
    onBuyClick(bRow)
    assert.equal("check", bRow.purchaseStage)
    assert.equal(0, liveSends)

    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal(1, liveSends)
    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal(1, liveSends)
    assert.equal("check", bRow.purchaseStage)

    -- A late B drain cannot resume a newer Check's owner or treat it as B's result.
    local newerOwner = { itemID = 99 }
    local staleDrain = { itemID = 43, token = 8, sent = true }
    GC.Sniper._pausedLiveRequery = newerOwner
    GC.Sniper._drainWaitRequery[43] = {
      row = bRow, itemID = 43, token = 2, deal = bRow.deal, draining = staleDrain,
    }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [43] = staleDrain })
    GC.Sniper.OnCommoditySearchResults(43)
    assert.is_true(GC.Sniper._pausedLiveRequery == newerOwner)
    assert.equal(1, liveSends)
    assert.equal("check", bRow.purchaseStage)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)

  it("releases a transferred drain-wait owner when B is cancelled before its old result", function()
    local timers, liveSends = {}, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 7 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = { Evaluate = function() return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } } end },
    }
    helper.loadModule("Core/Scanner.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local abortRowPurchase = getUpvalue(createDialog, "abortRowPurchase")
    setUpvalue(startRequery, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() error("drain fence must still block B") end,
    })
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = GC.Scanner.New({
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      now = function() return 100 end,
      sendSearch = function() liveSends = liveSends + 1 end,
      onStatus = function() end,
    }, {})
    GC.Sniper.scanner:Start({ 7 })
    GC.Sniper.scanner:Stop()
    GC.Sniper._liveTargets = { 7 }
    liveSends = 0

    local aDeal = { itemID = 42, isCommodity = true }
    local aRow = { deal = aDeal, purchaseStage = "requerying", purchaseToken = 1 }
    local aAttempt = { row = aRow, itemID = 42, token = 1, deal = aDeal, sent = false }
    local oldB = { itemID = 43, token = 7, sent = true }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = aAttempt })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [43] = oldB })
    GC.Sniper._pausedLiveRequery = aAttempt
    setUpvalue(onBuyClick, "dialog", { row = aRow, Hide = function() end })
    setUpvalue(onBuyClick, "openDialog", function(row, deal)
      setUpvalue(onBuyClick, "dialog", nil)
      startRequery(row, deal)
    end)

    local bRow = { deal = { itemID = 43, isCommodity = true } }
    onBuyClick(bRow)
    abortRowPurchase(bRow, nil)
    assert.equal(1, liveSends)
    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal(1, liveSends)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)
  -- Replaces two tests that pinned the Live pause/resume dance around a Check.
  -- Live is gone (Auto is strictly broader and the two fought each other with
  -- nothing in the interface saying so), so the scanner loop never runs and a
  -- Check has no contention to yield to. What still has to hold is that the Check
  -- sends its own search exactly once and touches the scanner not at all.
  it("checks a listing without starting or resuming the retired Live loop", function()
    local timers, sends, ready = {}, 0, false
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local scanner = { starts = 0, resumes = 0, stops = 0, scanned = 0 }
    function scanner:Start() self.starts = self.starts + 1 end
    function scanner:Resume() self.resumes = self.resumes + 1 end
    function scanner:Stop() self.stops = self.stops + 1 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 42 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = {
        Evaluate = function()
          return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
        end,
      },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local driver = {
      isReady = function() return ready end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() sends = sends + 1 end,
      commodityBook = function() return { { unitPrice = 100, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    }
    setUpvalue(startRequery, "driver", driver)
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = scanner

    local deal = { itemID = 42, isCommodity = true }
    startRequery({ deal = deal }, deal)
    ready = true
    GC.Sniper.OnThrottleReady()
    GC.Sniper.OnCommoditySearchResults(42)

    assert.equal(1, sends)
    assert.equal(0, scanner.starts)
    assert.equal(0, scanner.stops)
    assert.equal(0, scanner.resumes)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)
  -- Blizzard's own buy dialog keeps listening for COMMODITY_PRICE_UPDATED after
  -- ConfirmCommoditiesPurchase: when the price moved between the quote and the Confirm click
  -- the server re-quotes instead of buying, and the player has to confirm again. The Sniper
  -- used to drop that event in "confirming" -- and a re-quote is never followed by a terminal
  -- event, so the confirmed attempt sat forever as an owned pending, then (after an AH close)
  -- as a confirmed tombstone that refused every later commodity Buy with "waiting for previous
  -- commodity purchase to settle" until /reload.
  it("re-quotes a confirmed attempt when the server updates the price after Confirm", function()
    local cancelCalls, timers = 0, {}
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() end,
      GetNumCommoditySearchResults = function() return 2 end,
      GetCommoditySearchResultInfo = function(_, index)
        if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
        return { unitPrice = 2105265, quantity = 1 }
      end,
    }
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true }
    local quote = { token = 7, itemID = 42, quantity = 1, total = 1000000, decision = { status = "SAFE", buyable = true } }
    local row = {
      purchaseStage = "confirming", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
      quoteSnapshot = quote,
    }
    local pending = { row = row, itemID = 42, token = 7, confirmed = true, deal = deal, quote = quote }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
    -- The window that confirmed it is still open on this row: the re-quote is its to judge. With
    -- no window it would be dropped instead (GC.Sniper._DropRequotedConfirm, caps_purchase_spec).
    local written = {}
    local stub = function() end
    local window = {
      row = row, baseHeight = 400, SetHeight = stub,
      primaryBtn = { Enable = stub, Disable = stub, SetLabel = stub, IsEnabled = function() return false end,
        text = { SetTextColor = stub } },
      cancelBtn = { Enable = stub, Disable = stub },
      banner = { Hide = stub, Show = stub },
      status = { SetText = function(_, text) written[#written + 1] = text end, SetTextColor = stub },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", window)

    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery", function() end)
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000) -- server re-quote, 4% above the confirmed quote

    -- No gold moved: the server is waiting for a fresh Confirm, so the attempt is unconfirmed
    -- again and its old immutable quote is gone with it.
    assert.is_falsy(pending.confirmed)
    assert.is_nil(pending.quote)
    assert.are_not.equal("confirming", row.purchaseStage)
    -- ...and the ordinary requote path judged the new price in the open window: it broke
    -- safety, so the attempt was cancelled and drained into a tombstone that retires on its own
    -- timer, and the window stays on the row to re-check what remains.
    assert.is_true(window.row == row)
    assert.is_truthy(written[#written]:find("re-checking what remains at a safe price", 1, true))
    assert.equal(1, cancelCalls)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    assert.is_falsy(draining.confirmed)

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  -- A confirmed attempt whose terminal event never comes (dropped event, disconnect, a server
  -- that answered with nothing) must not hold the single commodity slot until /reload. Its
  -- bookkeeping is released after a generous window and the player is told to check the
  -- mailbox -- the honest statement, since the buy may or may not have gone through.
  it("releases a confirmed attempt that never hears back from the server", function()
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() end }
    _G.GetTime = function() return 0 end
    _G.time = function() return 100000 end
    local printed = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    GC.Print = function(text) printed[#printed + 1] = text end
    local stranded = { row = {}, itemID = 42, token = 5, confirmed = true, deal = { itemID = 42, isCommodity = true } }

    -- The AH-close tombstone slot...
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", stranded)
    GC.Sniper._ReleaseStrandedConfirmed(stranded)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
    assert.equal(1, #printed)
    assert.is_truthy(printed[1]:find("inspect mailbox", 1, true))

    -- ...and the live owned slot alike.
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", stranded)
    GC.Sniper._ReleaseStrandedConfirmed(stranded)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))

    -- Bound to the exact attempt it was armed for: a later attempt in either slot is untouched.
    local other = { row = {}, itemID = 43, token = 6, confirmed = true }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", other)
    GC.Sniper._ReleaseStrandedConfirmed(stranded)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == other)
    assert.equal(2, #printed)

    -- Armed by the hardware Confirm click itself, right where the attempt becomes confirmed.
    local click = clickHandler(source())
    local confirmAt = assert(click:find("pending.confirmed = true", 1, true))
    local releaseAt = assert(click:find("_ReleaseStrandedConfirmed", 1, true))
    assert.is_true(confirmAt < releaseAt)

    _G.C_AuctionHouse, _G.GetTime, _G.time = nil, nil, nil
  end)

  -- Sniper phase 2. A realm lot can never be SAFE or `buyable` -- nothing measures how fast a
  -- realm item sells -- so it reaches PlaceBid on a different key: the candidate one live check
  -- named. That is a second way into a protected call, and this pins BOTH halves of it: the bid
  -- is exactly the candidate's own auction and price, and it happens nowhere but the click.
  it("buys a realm candidate only through the dialog's own click handler, at the candidate's own price", function()
    local bids = {}
    _G.C_AuctionHouse = {
      PlaceBid = function(auctionID, amount) bids[#bids + 1] = { auctionID = auctionID, amount = amount } end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetMoney = function() return 10000000000 end
    _G.time = function() return 100000 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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

    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local primary = getUpvalue(createDialog, "onDialogPrimaryClick")

    local deal = { itemID = 42, isCommodity = false, qty = 1, unitPrice = 1 }
    local decision = {
      version = 1, status = "WATCH", buyable = false, reasons = { "realm_item_unverified" },
      quantity = 1, entryTotal = 750000, reference = 1000000, estProfit = 200000,
      candidate = { auctionID = 8801, buyout = 750000, itemLevel = 623, quantity = 1 },
    }
    local row = { deal = deal, purchaseStage = "ready", purchaseToken = 1, decisionSnapshot = decision }
    setUpvalue(primary, "dialog", {
      row = row, deal = deal,
      primaryBtn = { Disable = function() end, Enable = function() end, IsEnabled = function() return true end },
      status = { SetText = function() end, SetTextColor = function() end },
    })

    primary()

    assert.same({ { auctionID = 8801, amount = 750000 } }, bids)
    assert.equal("buying", row.purchaseStage)
    -- The PURCHASE takes the candidate's identity, or resolvePurchase could never clear the
    -- pendingAuction entry this buy just created -- on its own copy of the deal, leaving what
    -- the board is showing exactly as the scan found it. A bid can fail, and a failed bid must
    -- not repaint the row with a price nothing confirmed.
    assert.equal(8801, row.purchaseDeal.auctionID)
    assert.equal(1, row.purchaseDeal.qty)
    assert.equal(750000, row.purchaseDeal.unitPrice)
    assert.is_nil(deal.auctionID)
    assert.equal(1, deal.qty)
    assert.equal(1, deal.unitPrice)
    -- And it carries the item identity the acquisition store keys a position by: without it
    -- the batch is stored with no position, and no sale can ever be matched back to it.
    assert.same({ itemID = 42, itemLevel = 623, itemSuffix = 0, battlePetSpeciesID = 0 },
      row.purchaseDeal.itemKey)

    -- A realm decision with NO candidate is still Check-only: the same click must route to the
    -- Check path instead of a purchase. armCheck is stubbed rather than run because the real
    -- one repaints the whole panel, which is another spec's subject entirely.
    local refused = 0
    setUpvalue(primary, "armCheck", function() refused = refused + 1 end)
    row.purchaseStage = "ready"
    row.decisionSnapshot = { status = "WATCH", buyable = false, reasons = { "no_comparable_lot" } }
    primary()
    assert.equal(1, refused)
    assert.equal(1, #bids)

    -- Same for a candidate that names no auction: a partial one must never reach PlaceBid.
    row.purchaseStage = "ready"
    row.decisionSnapshot = { status = "WATCH", buyable = false, reasons = { "realm_item_unverified" },
      candidate = { buyout = 750000 } }
    primary()
    assert.equal(2, refused)
    assert.equal(1, #bids)

    -- And the bid is placed from the candidate itself, inside the click handler, nowhere else.
    local click = clickHandler(source())
    assert.is_truthy(click:find("C_AuctionHouse.PlaceBid(candidate.auctionID, candidate.buyout)", 1, true))
    local _, placeBidCount = source():gsub("C_AuctionHouse%.PlaceBid", "")
    assert.equal(1, placeBidCount)

    _G.C_AuctionHouse, _G.C_Timer, _G.GetMoney, _G.time, _G.GetTime = nil, nil, nil, nil, nil
  end)

  -- A purchase is a purchase: gold left the player's bags and the books have to say so. A realm
  -- buy has no SAFE decision behind it, so it is recorded as `unverified` rather than not at
  -- all -- end to end here, through the real ledger, flip and acquisition stores.
  it("writes one ledger row, one flip and one acquisition for a realm buy", function()
    _G.C_AuctionHouse = { PlaceBid = function() end }
    _G.C_Timer = { After = function() end }
    _G.GetMoney = function() return 10000000000 end
    _G.time = function() return 100000 end
    _G.GetTime = function() return 100 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end } end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Ledger.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    GC.Ledger.Init(GC.db)
    GC.Acquisitions.Init(GC.db)
    GC.Data.Init(GC.db)
    -- After Init, so the real store is in place but the sniper reads no market facts: a realm
    -- item carries none, which is the case under test.
    GC.Data.GetItemValue = function() return nil end
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function getUpvalue(fn, wanted)
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

    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local primary = getUpvalue(createDialog, "onDialogPrimaryClick")

    local deal = { itemID = 42, isCommodity = false, qty = 1, unitPrice = 1, mv = 1000000, discount = 0.25 }
    local decision = {
      version = 1, status = "WATCH", buyable = false, reasons = { "realm_item_unverified" },
      quantity = 1, entryTotal = 750000, entryUnitDisplay = 750000,
      reference = 1000000, estProfit = 200000,
      candidate = { auctionID = 8801, buyout = 750000, itemLevel = 623, quantity = 1 },
    }
    local row = { deal = deal, purchaseStage = "ready", purchaseToken = 1, decisionSnapshot = decision }
    setUpvalue(primary, "dialog", {
      row = row, deal = deal,
      Hide = function() end,
      primaryBtn = { Disable = function() end, Enable = function() end, IsEnabled = function() return true end },
      status = { SetText = function() end, SetTextColor = function() end },
    })

    primary()
    GC.Sniper.OnPurchaseCompleted(8801)

    local entries = GC.Ledger.GetEntries()
    assert.equal(1, #entries)
    assert.equal("buy", entries[1].kind)
    assert.equal("goldcap_sniper", entries[1].source)
    assert.equal(750000, entries[1].total)
    assert.equal("WATCH", entries[1].decisionStatus)
    assert.is_true(entries[1].unverified)
    assert.equal(1000000, entries[1].stressUnit) -- the region reference it was judged against

    local flips = GC.Data.GetFlips(100000)
    assert.equal(1, #flips)
    assert.equal(750000, flips[1].paidTotal)
    assert.equal(1000000, flips[1].targetUnit)

    assert.equal(1, #GC.db.acquisitions)
    assert.equal(750000, GC.db.acquisitions[1].originalTotal)
    assert.equal("goldcap", GC.db.acquisitions[1].source)
    -- The position this batch belongs to. A batch without one is invisible to ReconcileSale,
    -- so the sale of this very lot would never consume it and "You paid" would keep averaging
    -- over stock the player no longer owns.
    assert.equal("item:42:623:0:0", GC.db.acquisitions[1].positionKey)

    -- The session line the player reads has to agree with the books.
    assert.equal(1, GC.Sniper.session.buys)
    assert.equal(750000, GC.Sniper.session.spent)

    _G.C_AuctionHouse, _G.C_Timer, _G.GetMoney, _G.time, _G.GetTime = nil, nil, nil, nil, nil
    _G.GetCoinTextureString = nil
  end)

  -- The auction house's own error channel. Blizzard sends AUCTION_HOUSE_SHOW_ERROR and nothing
  -- else -- no commodity terminal event, no search result -- so before this every wait open at
  -- that moment waited forever: the board showed "Internal auction error." over the columns
  -- and the purchase kept the search slot for the rest of the session.
  describe("auction house errors", function()
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local function loadSniper()
      _G.time = function() return 100000 end
      _G.GetTime = function() return 100 end
      _G.GetMoney = function() return 10000000000 end
      _G.GetCoinTextureString = function(value) return tostring(value) end
      _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
      _G.C_AuctionHouse = {
        CalculateCommodityDeposit = function() return 0 end,
        CancelCommoditiesPurchase = function() end,
        MakeItemKey = function(itemID) return { itemID = itemID } end,
        HasFullBrowseResults = function() return false end,
      }
      local GC = {
        Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
          color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
            fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
            green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
        AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end } end },
        Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
        Scanner = { New = function() return {} end },
        Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
        SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
          ReasonText = function(t) return tostring(t) end },
        FullScan = { RowsFromBrowse = function() return {} end, EvaluateDelta = function() return {}, 0, 0 end,
          CollectNewHot = function() return {} end, MergeDeals = function(existing) return existing end },
        WatchSet = { Observe = function() end, Select = function() return {} end },
        Print = function() end,
        db = { settings = { sniper = { sound = false } } },
      }
      helper.loadModule("Core/BookPass.lua", GC)
      helper.loadModule("Core/DrillQueue.lua", GC)
      helper.loadModule("Core/KeyPoll.lua", GC)
      helper.loadModule("UI/SniperFrame.lua", GC)
      return GC
    end

    after_each(function()
      _G.time, _G.GetTime, _G.GetMoney, _G.C_Timer = os.time, nil, nil, nil
      _G.C_AuctionHouse, _G.GetCoinTextureString, _G.AuctionHouseUtil = nil, nil, nil
    end)

    it("is registered and routed to the Sniper", function()
      local f = assert(io.open("GoldCap/Core/Init.lua", "r"))
      local init = f:read("*a")
      f:close()
      assert.is_truthy(init:find('frame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")', 1, true))
      assert.is_truthy(init:find("GC.Sniper.OnAuctionHouseError(errorCode)", 1, true))
    end)

    it("settles an unconfirmed commodity purchase and clears the tombstones", function()
      local GC = loadSniper()
      local row = { purchaseStage = "buying", purchaseToken = 7,
        purchaseDeal = { itemID = 42, isCommodity = true } }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { itemID = 9, token = 1 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

      GC.Sniper.OnAuctionHouseError(3)

      assert.is_nil(row.purchaseStage)
      assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))
      assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
      assert.is_false(GC.Sniper.IsPurchaseQuiet()) -- and the board is free again
    end)

    -- ConfirmCommoditiesPurchase has already run: gold may have moved. Freeing the row here
    -- would offer the player a retry that buys the same lot twice.
    it("never resolves a confirmed attempt", function()
      local GC = loadSniper()
      local row = { purchaseStage = "confirming", purchaseToken = 7,
        purchaseDeal = { itemID = 42, isCommodity = true } }
      local pending = { row = row, itemID = 42, token = 7, confirmed = true }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

      GC.Sniper.OnAuctionHouseError(3)

      assert.equal("confirming", row.purchaseStage)
      assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase") == pending)
    end)

    it("fails a live Check instead of leaving it waiting for a result that never comes", function()
      local GC = loadSniper()
      local row = { purchaseStage = "requerying", purchaseToken = 3, deal = { itemID = 42 } }
      local attempt = { row = row, itemID = 42, token = 3, deal = row.deal, sent = true }
      getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42] = attempt

      GC.Sniper.OnAuctionHouseError(3)

      assert.equal("check", row.purchaseStage)
      assert.is_nil(getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42])
      -- The search WAS sent, so its late untagged result must still drain before a new
      -- authoritative Check can exist.
      assert.is_true(getUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining")[42] == attempt)
      assert.is_false(GC.Sniper.IsPurchaseQuiet())
    end)

    -- The words came from `_G.AuctionHouseErrorMessages`, a table the client does not have: the
    -- default UI's own lookup is AuctionHouseUtil.GetErrorText (Blizzard_AuctionHouseUtil.lua),
    -- so every error read "the auction house reported an error" whatever it was.
    it("says the error in the client's own words", function()
      local GC = loadSniper()
      helper.loadModule("Core/Util.lua", GC)
      _G.AuctionHouseUtil = { GetErrorText = function(code) return code == 3 and "The Auction House is busy." or "" end }
      local said
      setUpvalue(GC.Sniper.OnAuctionHouseError, "setStatus", function(text) said = text end)

      GC.Sniper.OnAuctionHouseError(3)
      assert.equal("The Auction House is busy.", said)
      GC.Sniper.OnAuctionHouseError(99)
      assert.equal("the auction house reported an error", said)
    end)
  end)

  -- What happens to a Confirm the server never answered, and to the three places a dialog could
  -- speak for a row it was not showing. Every one of these is about gold: a row handed back as
  -- "Check again" is one click from buying the same lot twice, and a purchase nothing recorded
  -- is gold that left the bags with no cost basis behind it.
  describe("stranded confirmations and dialog ownership", function()
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local printed, recorded, money

    local function loadSniper()
      printed, recorded, money = {}, { flips = 0, ledger = 0, acquisitions = 0 }, 10000000000
      _G.time = function() return 100000 end
      _G.GetTime = function() return 100 end
      _G.GetMoney = function() return money end
      _G.GetCoinTextureString = function(value) return tostring(value) end
      _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
      _G.C_AuctionHouse = {
        CalculateCommodityDeposit = function() return 0 end,
        CancelCommoditiesPurchase = function() end,
        MakeItemKey = function(itemID) return { itemID = itemID } end,
        HasFullBrowseResults = function() return false end,
        -- No search buffer unless a test fills one: the client's single commodity buffer
        -- belongs to whatever was searched last, which is nothing here.
        GetNumCommoditySearchResults = function() return 0 end,
        GetCommoditySearchResultInfo = function() return nil end,
      }
      local GC = {
        Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
          color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
            fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
            green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
        AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end } end },
        Data = {
          GetItemValue = function() return {} end,
          GetWatchlist = function() return {} end,
          RecordFlip = function() recorded.flips = recorded.flips + 1 end,
        },
        Ledger = {
          Context = function() return { char = "A-R", region = "eu" } end,
          RecordSniperBuy = function() recorded.ledger = recorded.ledger + 1; return { key = "buy:1" } end,
        },
        Acquisitions = { RecordGoldCap = function() recorded.acquisitions = recorded.acquisitions + 1 end },
        Print = function(text) printed[#printed + 1] = text end,
        db = { settings = { sniper = {} } },
      }
      helper.loadModule("Core/Util.lua", GC)
      helper.loadModule("Core/Book.lua", GC)
      helper.loadModule("Core/SniperDecision.lua", GC)
      helper.loadModule("Core/CheckVerdict.lua", GC)
      helper.loadModule("Core/DealMath.lua", GC)
      helper.loadModule("Core/AutoScan.lua", GC)
      helper.loadModule("Core/BookPass.lua", GC)
      helper.loadModule("Core/DrillQueue.lua", GC)
      helper.loadModule("Core/KeyPoll.lua", GC)
      helper.loadModule("Core/Caps.lua", GC)
      helper.loadModule("UI/SniperFrame.lua", GC)
      -- The board repaint is another spec's subject and needs the whole frame to exist.
      setUpvalue(GC.Sniper._ReleaseStrandedConfirmed, "refreshRows", function() end)
      return GC
    end

    -- A dialog double that answers everything the purchase paths ask a dialog, and records
    -- what was written so a test can assert the screen was (or was not) touched.
    local function fakeDialog(row)
      local d = { row = row, written = {}, enabled = false, height = 0, baseHeight = 400 }
      d.primaryBtn = {
        Disable = function() d.enabled = false end,
        Enable = function() d.enabled = true end,
        IsEnabled = function() return d.enabled end,
        SetLabel = function(_, text) d.label = text end,
        text = { SetTextColor = function() end },
      }
      d.cancelBtn = { Enable = function() end, Disable = function() end, SetLabel = function() end }
      d.status = {
        SetText = function(_, text) d.written[#d.written + 1] = text end,
        SetTextColor = function() end,
      }
      d.banner = { shown = false,
        Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
        IsShown = function(self) return self.shown end,
        head = { SetText = function() end }, detail = { SetText = function() end } }
      d.SetHeight = function(_, height) d.height = height end
      d.Hide = function() end
      d.IsShown = function() return true end
      -- The decision stamper writes every figure on the panel; none of them is this block's
      -- subject, so they are sinks. Geometry fields match createDialog's own.
      d.fixedHeight, d.diagnosticGaps, d.diagnosticMinimumHeight = 400, 4, 108
      d.detailsOpen, d.evidenceTopOpen, d.evidenceTopClosed = false, -200, -100
      local function sink()
        return { SetText = function() end, SetTextColor = function() end,
          Show = function() end, Hide = function() end,
          ClearAllPoints = function() end, SetPoint = function() end,
          SetHeight = function() end, GetStringHeight = function() return 24 end }
      end
      for _, field in ipairs({ "decisionStatusText", "quantityText", "unitPriceText",
        "totalCostText", "exitUnitText", "profitText", "mvText", "soldText", "sellThroughText",
        "sourceAgeText", "reasonText", "verdictHead", "verdictSub", "diagnosticText",
        "mvNote" }) do
        d[field] = sink()
      end
      d.status.ClearAllPoints = function() end
      d.status.SetPoint = function() end
      return d
    end

    local function confirmedAttempt(row, deal)
      local decision = { version = 1, status = "SAFE", buyable = true, quantity = 2,
        exitUnit = 900, stressProfit = 400, reasons = {} }
      local quote = { token = 5, itemID = deal.itemID, quantity = 2, total = 1000,
        decision = decision, market = { sourceAt = 99000 } }
      row.deal, row.purchaseDeal, row.quoteSnapshot = deal, deal, quote
      row.purchaseStage, row.purchaseToken = "confirming", 5
      return { row = row, itemID = deal.itemID, token = 5, confirmed = true, deal = deal, quote = quote }
    end

    after_each(function()
      _G.time, _G.GetTime, _G.GetMoney, _G.C_Timer = os.time, nil, nil, nil
      _G.C_AuctionHouse, _G.GetCoinTextureString = nil, nil
    end)

    -- Observed live 2026-09-15 (`/gc sniper`): a tombstone fenced on requery token 2, no requery
    -- waiting, Buy refused for 20 seconds. The requery had stopped being the row's before its
    -- result landed (the board repainted the deal under the dialog), and the drop branch threw
    -- the requery away without retiring the tombstone it was fenced on. The result still proves
    -- the cancelled attempt's late quote was delivered, so the tombstone must go with it.
    it("a requery result retires the tombstone fenced on it even when the requery is no longer current", function()
      local GC = loadSniper()
      local row = { purchaseStage = "ready", purchaseToken = 2, deal = { itemID = 42 } }
      -- `deal` is a different table from row.deal: the repaint that orphaned this requery.
      local attempt = { row = row, itemID = 42, token = 2, deal = { itemID = 42 }, sent = true }
      getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42] = attempt
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
        { itemID = 42, token = 1, drainingAt = 100, fenceRow = row, fenceToken = 2 })

      GC.Sniper.OnCommoditySearchResults(42)

      assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
      assert.is_nil(getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42])
      assert.equal("ready", row.purchaseStage) -- the orphaned requery still arms nothing
    end)

    it("a dropped requery never retires a confirmed tombstone or one fenced elsewhere", function()
      local GC = loadSniper()
      local row = { purchaseStage = "ready", purchaseToken = 2, deal = { itemID = 42 } }
      local attempt = { row = row, itemID = 42, token = 2, deal = { itemID = 42 }, sent = true }
      local confirmed = { itemID = 42, token = 1, confirmed = true, fenceRow = row, fenceToken = 2 }
      getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42] = attempt
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", confirmed)
      GC.Sniper.OnCommoditySearchResults(42)
      assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == confirmed)

      local other = { itemID = 42, token = 1, drainingAt = 100, fenceRow = row, fenceToken = 3 }
      getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")[42] = attempt
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", other)
      GC.Sniper.OnCommoditySearchResults(42)
      assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == other)
    end)

    -- A confirmed attempt that let go of the shared purchase slot -- the tombstone Esc leaves
    -- behind, or one still in flight -- is a purchase whose success is still owed to the Sniper.
    -- The BUY tab asks this before a stranded record of its own takes a terminal event; a "no"
    -- here let BUY book the Sniper's success as its own, and the tombstone then refused every
    -- later commodity Buy with "waiting for previous commodity purchase to settle" until /reload.
    it("counts a confirmed tombstone and a confirmed attempt as stranded confirms", function()
      local GC = loadSniper()
      assert.is_false(GC.Sniper.HasStrandedConfirmed())

      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { itemID = 42, token = 1, confirmed = true })
      assert.is_true(GC.Sniper.HasStrandedConfirmed())

      -- An unconfirmed tombstone paid for nothing: no success is owed, nothing to protect.
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { itemID = 42, token = 1 })
      assert.is_false(GC.Sniper.HasStrandedConfirmed())

      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", nil)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase",
        { row = {}, itemID = 42, token = 2, confirmed = true })
      assert.is_true(GC.Sniper.HasStrandedConfirmed())
    end)

    -- The release gives up the ownership so Esc can close the window. It must not also give up
    -- the ROW: for a minute afterwards the quiet-zone release saw an unowned mid-flight row and
    -- handed it back as "Check again" -- the same lot, already possibly paid for.
    it("freezes the row a released confirmation owned instead of returning it to Check", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true, itemName = "Thing" }
      local row = {}
      local pending = confirmedAttempt(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      setUpvalue(GC.Sniper._ReleaseQuietZone, "rows", { row })

      GC.Sniper._ReleaseStrandedConfirmed(pending)

      assert.equal("frozen", row.purchaseStage)
      assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))
      assert.is_truthy(printed[1]:find("inspect mailbox", 1, true))
      -- "frozen" is not a quiet stage, so nothing is holding the board hostage either.
      assert.is_false(GC.Sniper._QuietZoneOpen())

      GC.Sniper._ReleaseQuietZone()
      assert.equal("frozen", row.purchaseStage)
      assert.is_true(getUpvalue(GC.Sniper._ReleaseStrandedConfirmed, "activeItemID")[42])
    end)

    -- Confirm reached Blizzard, the release let go, and the success turned up late. Before this
    -- it was recorded nowhere at all: the sniper had let go, and Core/PurchaseCapture.lua had
    -- stood down at the Start precisely because the sniper owned the attempt.
    it("records a success that lands after the release", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true, itemName = "Thing" }
      local pending = confirmedAttempt({}, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      GC.Sniper._ReleaseStrandedConfirmed(pending)
      assert.equal(0, recorded.ledger)

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.equal(1, recorded.ledger)
      assert.equal(1, recorded.flips)
      assert.equal(1, recorded.acquisitions)
      assert.equal(1, GC.Sniper.session.buys)
      assert.equal(1000, GC.Sniper.session.spent)
      -- Consumed: a second terminal event cannot book the same purchase twice.
      GC.Sniper.OnCommodityPurchaseSucceeded()
      assert.equal(1, recorded.ledger)
    end)

    -- Two records and the attribution would be a guess: commodity events carry no attempt id.
    it("records nothing when two released confirmations are waiting at once", function()
      local GC = loadSniper()
      local first = confirmedAttempt({}, { itemID = 42, isCommodity = true })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", first)
      GC.Sniper._ReleaseStrandedConfirmed(first)
      local second = confirmedAttempt({}, { itemID = 43, isCommodity = true })
      second.itemID, second.quote.itemID = 43, 43
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", second)
      GC.Sniper._ReleaseStrandedConfirmed(second)

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.equal(0, recorded.ledger)
    end)

    -- A failure is proof no gold moved, so the record is dropped rather than left for some
    -- later, unrelated success to pick up.
    it("retires the record on a terminal failure", function()
      local GC = loadSniper()
      local pending = confirmedAttempt({}, { itemID = 42, isCommodity = true })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      GC.Sniper._ReleaseStrandedConfirmed(pending)

      GC.Sniper.OnCommodityPurchaseFailed()
      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.equal(0, recorded.ledger)
    end)

    -- A server re-quote after Confirm unconfirms the attempt (no gold moves on a re-quote). If
    -- the new price then breaks safety the attempt is cancelled and drained -- and a success
    -- arriving after THAT used to return in silence. It is not recorded (the price it was
    -- confirmed at is not the price the server would have charged), but it is never silent.
    it("speaks up for a success on an attempt that was confirmed once and re-quoted", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true }
      local tombstone = { itemID = 42, token = 5, wasConfirmed = true, lastDeal = deal }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", tombstone)

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.equal(0, recorded.ledger)
      assert.is_truthy(printed[1] and printed[1]:find("inspect mailbox", 1, true))
      assert.equal("purchase total unavailable — inspect mailbox",
        GC.Sniper.detachedCommodityStatus[42].note)
    end)

    -- A plain cancelled tombstone is not a confirmation and stays silent, exactly as before.
    it("stays silent for a success on an attempt that was never confirmed", function()
      local GC = loadSniper()
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { itemID = 42, token = 5 })

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.equal(0, #printed)
      assert.is_nil(GC.Sniper.detachedCommodityStatus[42])
    end)

    -- A requery lands for a row the dialog has since moved off. The row arms; the screen the
    -- player is looking at belongs to a different deal and must not be repainted as armed.
    it("arms the row without painting a dialog that is showing another row", function()
      local GC = loadSniper()
      local other = { deal = { itemID = 7, isCommodity = true } }
      local dialog = fakeDialog(other)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local applyRequeryResult = getUpvalue(finishRequery, "applyRequeryResult")
      local armReady = getUpvalue(applyRequeryResult, "armReady")
      setUpvalue(armReady, "dialog", dialog)

      local deal = { itemID = 42, isCommodity = true }
      local row = { deal = deal }
      armReady(row, deal, { status = "SAFE", buyable = true, quantity = 1 }, { { unitPrice = 5, quantity = 9 } })

      assert.equal("ready", row.purchaseStage) -- the row itself still arms
      assert.is_false(dialog.enabled)
      assert.equal(0, #dialog.written)
      assert.is_nil(dialog.bookLevels)
    end)

    -- Same rule for the other direction: the quiet-zone release walks every mid-flight row and
    -- used to write each one's "Check again" over whatever the dialog was showing.
    it("returns a row to Check without writing the status line of another row's dialog", function()
      local GC = loadSniper()
      local other = { deal = { itemID = 7 } }
      local dialog = fakeDialog(other)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local applyRequeryResult = getUpvalue(finishRequery, "applyRequeryResult")
      local armCheck = getUpvalue(applyRequeryResult, "armCheck")
      setUpvalue(armCheck, "dialog", dialog)

      local deal = { itemID = 42, isCommodity = true }
      local row = { deal = deal }
      armCheck(row, deal, nil, "no answer from the auction house", true)

      assert.equal("check", row.purchaseStage)
      assert.equal(0, #dialog.written)
    end)

    -- The price rose, and the quote is now past what is in the player's bags. The quiet path
    -- has refused that since Fix 2; the two requote paths used to hand it a live Confirm.
    it("never enables Confirm on a requote the player cannot pay for", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1,
          entryTotal = 1000 } }
      local dialog = fakeDialog(row)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase",
        { row = row, itemID = 42, token = 7 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", dialog)
      -- The engine's own verdict is another spec's subject: this one is about the wallet.
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive", function()
        return { version = 1, status = "SAFE", buyable = true, quantity = 1, reasons = {} }
      end)

      money = 1100 -- a 10% rise (warn) lands above the purse
      GC.Sniper.OnCommodityPriceUpdated(1200, 1200)
      assert.equal("requote", row.purchaseStage)
      assert.is_false(dialog.enabled)
      assert.equal("not enough gold for this quote -- Cancel", dialog.written[#dialog.written])

      -- And the loud tier, whose countdown must not arm at all.
      row.purchaseStage, row.quoteSnapshot = "buying", nil
      GC.Sniper.OnCommodityPriceUpdated(2000, 2000)
      assert.is_false(dialog.enabled)

      -- With the gold in hand the same rise still offers Confirm, unchanged.
      money = 10000000000
      row.purchaseStage, row.quoteSnapshot = "buying", nil
      GC.Sniper.OnCommodityPriceUpdated(1200, 1200)
      assert.is_true(dialog.enabled)
    end)

    -- Fix round 5 (m3): the countdown speaks only over a Confirm that can be clicked. A dark one
    -- says why -- not enough gold -- and "click Confirm to buy" over it would be a lie.
    it("never counts a dark Confirm down as one to click", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1,
          entryTotal = 1000 } }
      local dialog = fakeDialog(row)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase",
        { row = row, itemID = 42, token = 7 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", dialog)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive", function()
        return { version = 1, status = "SAFE", buyable = true, quantity = 1, reasons = {} }
      end)
      money = 900 -- under the quote: Confirm stays dark
      GC.Sniper.OnCommodityPriceUpdated(1000, 1000) -- quoted at 100 s, 20 s to run
      assert.equal("confirm", row.purchaseStage)
      assert.is_false(dialog.enabled)
      assert.equal("not enough gold for this quote -- Cancel", dialog.written[#dialog.written])

      _G.GetTime = function() return 111 end -- nine seconds left
      GC.Sniper._TickConfirmCountdown()

      assert.equal("not enough gold for this quote -- Cancel", dialog.written[#dialog.written])
    end)

    -- Task 7: a cap is the player's own price, not a market read. A quote that breaks it must
    -- never slip through as a quiet "confirm" just because the rise from the entry total was
    -- too small to trip RequoteSeverity on its own.
    it("forces the loud requote path when the quote breaks the player's own price cap", function()
      local GC = loadSniper()
      -- 1290 is only a 0.78% rise over the 1280 entry -- well under REQUOTE_WARN_RATIO (5%) on
      -- its own -- but 5 copper over the player's own 1285 cap.
      local deal = { itemID = 42, isCommodity = true, cap = 1285 }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1,
          entryTotal = 1280 } }
      local dialog = fakeDialog(row)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase",
        { row = row, itemID = 42, token = 7 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", dialog)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive", function()
        return { version = 1, status = "SAFE", buyable = true, quantity = 1, reasons = {} }
      end)

      GC.Sniper.OnCommodityPriceUpdated(1290, 1290)
      assert.equal("requote", row.purchaseStage) -- not "confirm": the cap breach forces the banner
      assert.is_true(dialog.banner.shown)
    end)

    -- The other side of the same guard: a quote that stays at or under the cap is judged
    -- exactly as it would be with no cap at all -- the guard narrows nothing else.
    it("leaves an ordinary requote alone when the quote stays at or under the player's cap", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true, cap = 1300 }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1,
          entryTotal = 1280 } }
      local dialog = fakeDialog(row)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase",
        { row = row, itemID = 42, token = 7 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", dialog)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive", function()
        return { version = 1, status = "SAFE", buyable = true, quantity = 1, reasons = {} }
      end)

      GC.Sniper.OnCommodityPriceUpdated(1290, 1290) -- rose, but stayed under the 1300 cap
      assert.equal("confirm", row.purchaseStage)
      assert.is_true(dialog.enabled)
    end)

    -- The tombstone is retired by the requery the cancel starts. When no requery could start --
    -- an older sent search for the item is still draining -- there is no attempt to fence on,
    -- and a fence stamped anyway was never consumed: every later Buy refused for 20 seconds.
    it("fences the cancel's tombstone on the wait that will actually settle it", function()
      local GC = loadSniper()
      local deal = { itemID = 42, isCommodity = true }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1,
          entryTotal = 1000 } }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase",
        { row = row, itemID = 42, token = 7 })
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive", function()
        return { version = 1, status = "AVOID", buyable = false, reasons = { "requote_broke_safety" } }
      end)
      getUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining")[42] =
        { row = {}, itemID = 42, token = 1, sent = true }

      GC.Sniper.OnCommodityPriceUpdated(1200, 1200)

      assert.equal("check", row.purchaseStage) -- no query went out; the player clicks Check again
      -- No requery could start (an older sent search for this item is still draining), so the
      -- fence goes on the DRAIN WAIT instead -- the thing that will be settled when that old
      -- result finally lands. It used to go on nothing at all, and an unconfirmed tombstone
      -- with no owner refuses every later Buy with "waiting for previous commodity purchase to
      -- settle" for its full 20 seconds, over a purchase that was cancelled and cost nothing.
      local wait = GC.Sniper._drainWaitRequery[42]
      assert.is_table(wait)
      local tombstone = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
      assert.is_table(tombstone)
      assert.equal(row, tombstone.fenceRow)
      assert.equal(wait.token, tombstone.fenceToken)

      -- And the old result arriving is what lifts it, well inside those 20 seconds.
      GC.Sniper.OnCommoditySearchResults(42)
      assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
    end)

    -- A commodity price level is an aggregate across every seller, the player's own stock
    -- included. Buying your own units is impossible, and anchoring the resale one copper under
    -- your own auction is undercutting yourself.
    it("leaves the player's own units out of the order book", function()
      local GC = loadSniper()
      local startRequery = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")
      local driver = getUpvalue(startRequery, "driver")
      local levels = {
        { unitPrice = 100, quantity = 10, numOwnerItems = 10 }, -- entirely the player's own
        { unitPrice = 110, quantity = 8, numOwnerItems = 3 },
        { unitPrice = 120, quantity = 5, containsOwnerItem = true }, -- no count: unsplittable
        { unitPrice = 130, quantity = 4 },
      }
      _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return #levels end
      _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index) return levels[index] end

      assert.same({ { unitPrice = 110, quantity = 5 }, { unitPrice = 130, quantity = 4 } },
        driver.commodityBook(42))
      local live = driver.commodityResult(42)
      assert.equal(9, live.avail)
      -- And the PRICE comes from the cheapest level with something left on it, not from level 1
      -- blind: level 1 is the player's own auction the moment they are the cheapest seller, so
      -- an item they own the whole book of kept coming back to the board as its own deal.
      assert.equal(110, live.unitPrice)
      assert.equal(5, live.qty)
    end)

    it("has no price to report when the whole book is the player's own", function()
      local GC = loadSniper()
      local startRequery = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")
      local driver = getUpvalue(startRequery, "driver")
      local levels = { { unitPrice = 100, quantity = 10, numOwnerItems = 10 } }
      _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return #levels end
      _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index) return levels[index] end

      assert.is_nil(driver.commodityResult(42))
      assert.is_nil(driver.commodityBook(42))
    end)

    -- The deposit is part of what the resale costs, and it scales with the listing duration the
    -- player actually posts at. It was priced at 24h for everybody.
    it("quotes the deposit for the duration the player posts at", function()
      local GC = loadSniper()
      local asked
      _G.C_AuctionHouse.CalculateCommodityDeposit = function(_, duration) asked = duration; return 0 end
      local evaluateLive = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive")
      local depositFor = getUpvalue(evaluateLive, "depositFor")

      GC.db.settings.sniper.postDuration = 3
      depositFor(42, 5)
      assert.equal(3, asked)

      GC.db.settings.sniper.postDuration = 9 -- not one of the three the API accepts
      depositFor(42, 5)
      assert.equal(2, asked)
    end)
  end)
end)
