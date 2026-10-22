require("spec.spec_helper")

-- The one call that sells is C_Container.UseContainerItem inside the card's driver, reached only
-- from the player's click (the first stack) and from the press machine's timers (the rest, once the
-- click has made the first). These audits read the source, comments stripped.
describe("vendor sell wiring", function()
  local CARD = "GoldCap/UI/VendorSellCard.lua"
  local SELL_CALLS = { "UseContainerItem", "SellAllJunkItems", "PickupContainerItem", "BuyMerchantItem" }

  local function read(path)
    local f = assert(io.open(path, "r"))
    local t = f:read("*a")
    f:close()
    return (t:gsub("%-%-[^\n]*", ""))
  end

  local function countOf(text, needle)
    local n, at = 0, 1
    while true do
      local i = text:find(needle, at, true)
      if not i then return n end
      n, at = n + 1, i + #needle
    end
  end

  -- The text of a top level `local function name` / `name = function` block up to its closing end.
  local function bodyOf(text, header)
    local from = assert(text:find(header, 1, true), header)
    local to = assert(text:find("\nend\n", from, true) or text:find("\n  end,", from, true), header)
    return text:sub(from, to)
  end

  it("UseContainerItem appears only in UI/BankRoute.lua and UI/VendorSellCard.lua", function()
    local listing = assert(io.popen("find GoldCap -name '*.lua'"))
    for path in listing:lines() do
      if path ~= "GoldCap/UI/BankRoute.lua" and path ~= CARD then
        assert.is_nil(read(path):find("UseContainerItem", 1, true), path)
      end
    end
    listing:close()
  end)

  it("it appears exactly once in the card, inside the driver's use function", function()
    local text = read(CARD)
    assert.equal(1, countOf(text, "UseContainerItem"))
    local use = assert(text:match("use = function%(bag, slot%)[^\n]*"))
    assert.is_truthy(use:find("C_Container.UseContainerItem(bag, slot)", 1, true))
  end)

  it("Core/VendorPress.lua and Core/VendorSelect.lua never name a sell, pickup or buy call", function()
    for _, path in ipairs({ "GoldCap/Core/VendorPress.lua", "GoldCap/Core/VendorSelect.lua",
        "GoldCap/Services/VendorBags.lua" }) do
      local text = read(path)
      for _, name in ipairs(SELL_CALLS) do assert.is_nil(text:find(name, 1, true), path .. " " .. name) end
    end
  end)

  it("onSellClick is reached only through the button's OnClick", function()
    local sites = {}
    for line in read(CARD):gmatch("[^\n]*onSellClick[^\n]*") do sites[#sites + 1] = line:match("^%s*(.-)%s*$") end
    assert.same({ "local function onSellClick(button)", 'frame.button:SetScript("OnClick", onSellClick)' }, sites)
  end)

  it("the machine is pressed only inside onSellClick", function()
    local text = read(CARD)
    assert.equal(1, countOf(text, ":Press("))
    local body = bodyOf(text, "local function onSellClick")
    assert.is_truthy(body:find(":Press(", 1, true))
  end)

  it("onSellClick calls Press before any Disable, Enable or SetLabel", function()
    local body = bodyOf(read(CARD), "local function onSellClick")
    local press = assert(body:find(":Press(", 1, true))
    for _, later in ipairs({ ":Disable(", ":Enable(", "SetLabel", "paintButton", "Refresh" }) do
      local at = body:find(later, 1, true)
      if at then assert.is_true(press < at, later) end
    end
  end)

  it("no C_Timer.After body in the card names Press or onSellClick", function()
    local timers = 0
    for body in read(CARD):gmatch("C_Timer%.After%b()") do
      timers = timers + 1
      assert.is_nil(body:find("Press", 1, true))
      assert.is_nil(body:find("onSellClick", 1, true))
    end
    assert.is_true(timers >= 1)
  end)

  it("the card and the new Core and Services files are in the retail TOC and absent from the Forever TOC", function()
    local retail, forever = read("GoldCap/GoldCap.toc"), read("GoldCap/GoldCap_Camelot.toc")
    for _, file in ipairs({ "Core/VendorSelect.lua", "Core/VendorPress.lua", "Services/VendorBags.lua",
        "UI/VendorSellCard.lua" }) do
      assert.is_truthy(retail:find("\n" .. file .. "\n", 1, true), file)
      assert.is_nil(forever:find(file, 1, true), file)
    end
  end)

  it("the confirm event is registered through pcall and routed to the card", function()
    local init = read("GoldCap/Core/Init.lua")
    assert.is_truthy(init:find('"MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL"', 1, true))
    assert.is_truthy(init:find("pcall(frame.RegisterEvent, frame, merchantEvent)", 1, true))
    assert.is_nil(init:find('frame:RegisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL")', 1, true))
    assert.is_truthy(init:find("GC.VendorSellCard.OnTradeTimerConfirm()", 1, true))
  end)

  it("the card does not tell the games apart", function()
    local text = read(CARD)
    for _, name in ipairs({ "IsForever", "WOW_PROJECT_ID", "GetBuildInfo" }) do
      assert.is_nil(text:find(name, 1, true), name)
    end
  end)
end)
