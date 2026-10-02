require("spec.spec_helper")

-- A merchant purchase spends gold, so it gets the audit the auction house purchases have: the one
-- BuyMerchantItem call lives inside the vendor panel button's own click handler, reached only by
-- the engine's OnClick, and never from a timer.
describe("vendor purchase wiring", function()
  local function read(path)
    local f = assert(io.open(path, "r"))
    local t = f:read("*a")
    f:close()
    return (t:gsub("%-%-[^\n]*", ""))
  end

  it("calls BuyMerchantItem only inside onVendorBuyClick", function()
    local listing = assert(io.popen("find GoldCap -name '*.lua'"))
    for path in listing:lines() do
      local text = read(path)
      if path ~= "GoldCap/UI/BuyVendorPanel.lua" and path ~= "GoldCap/Core/VendorBuys.lua" then
        assert.is_nil(text:find("BuyMerchantItem", 1, true), path)
      end
    end
    listing:close()
    local text = read("GoldCap/UI/BuyVendorPanel.lua")
    local from = assert(text:find("local function onVendorBuyClick", 1, true))
    local to = assert(text:find("\nend\n", from, true))
    local outside = text:sub(1, from - 1) .. text:sub(to)
    assert.is_nil(outside:find("BuyMerchantItem", 1, true))
    assert.is_truthy(text:sub(from, to):find("BuyMerchantItem(", 1, true))
  end)

  -- Core/VendorBuys.lua names the call only to observe it: a post-hook cannot make a purchase.
  it("names BuyMerchantItem in Core/VendorBuys.lua only as a post-hook", function()
    local text = read("GoldCap/Core/VendorBuys.lua")
    local count = 0
    for _ in text:gmatch("BuyMerchantItem") do count = count + 1 end
    assert.equal(2, count)   -- the existence check and the hook itself
    assert.is_truthy(text:find('hooksecurefunc("BuyMerchantItem"', 1, true))
    assert.is_nil(text:find("BuyMerchantItem(", 1, true))
  end)

  it("reaches onVendorBuyClick only through the button's OnClick", function()
    local text = read("GoldCap/UI/BuyVendorPanel.lua")
    local sites = {}
    for line in text:gmatch("[^\n]*onVendorBuyClick[^\n]*") do sites[#sites + 1] = line:match("^%s*(.-)%s*$") end
    assert.same({ "local function onVendorBuyClick(button)", 'button:SetScript("OnClick", onVendorBuyClick)' }, sites)
  end)

  it("never buys from a timer", function()
    local text = read("GoldCap/UI/BuyVendorPanel.lua")
    local timers = 0
    for body in text:gmatch("C_Timer%.After%b()") do
      timers = timers + 1
      assert.is_nil(body:find("BuyMerchantItem", 1, true))
      assert.is_nil(body:find("onVendorBuyClick", 1, true))
    end
    assert.is_true(timers >= 1)
  end)

  -- The button goes busy only once the call has been made: the clicked button stays enabled until
  -- then, the order every purchase click in the addon keeps (WoW: Forever refuses a protected call
  -- from a button disabled earlier in the same click).
  it("disables the button only after the call", function()
    local text = read("GoldCap/UI/BuyVendorPanel.lua")
    local from = assert(text:find("local function onVendorBuyClick", 1, true))
    local to = assert(text:find("\nend\n", from, true))
    local body = text:sub(from, to)
    local call = assert(body:find("BuyMerchantItem(", 1, true))
    local disable = assert(body:find("button:Disable()", 1, true))
    assert.is_true(call < disable)
  end)

  it("is routed from the event frame", function()
    local init = read("GoldCap/Core/Init.lua")
    for _, name in ipairs({ "OnMerchantShow", "OnMerchantUpdate", "OnMerchantClosed", "OnBagsChanged" }) do
      assert.is_truthy(init:find("GC.BuyVendorPanel." .. name, 1, true), name)
    end
  end)
end)
