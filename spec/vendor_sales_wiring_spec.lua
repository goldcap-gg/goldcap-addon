require("spec.spec_helper")

-- Core/VendorSales.lua loads on WoW: Forever only (spec/camelot_toc_spec.lua's FOREVER_ONLY), so
-- every call Core/Init.lua makes into it sits behind `if GC.VendorSales then`: on retail the
-- module is absent and its event path is the one it always was. The module only reads the
-- buyback list; selling and buying back stay the player's own clicks.
describe("merchant sale wiring", function()
  local function read(path)
    local f = assert(io.open(path, "r"))
    local t = f:read("*a")
    f:close()
    return (t:gsub("%-%-[^\n]*", ""))
  end

  -- The text of Init.lua's `elseif event == "<name>" then` branch, up to the next branch.
  local function branch(init, name)
    local from = assert(init:find('event == "' .. name .. '" then', 1, true), name)
    local to = init:find("\n  elseif ", from, true) or init:find("\n  end\nend)", from, true)
    return init:sub(from, assert(to, name))
  end

  local CALLS = {
    MERCHANT_SHOW = "GC.VendorSales.OnShow(time())",
    MERCHANT_UPDATE = "GC.VendorSales.OnChanged(time())",
    BAG_UPDATE_DELAYED = "GC.VendorSales.OnChanged(time())",
    MERCHANT_CLOSED = "GC.VendorSales.OnClosed(time())",
    PLAYER_LOGOUT = "GC.VendorSales.OnClosed(time())",
  }

  it("forwards the merchant's events and logout to the module behind its presence guard", function()
    local init = read("GoldCap/Core/Init.lua")
    for event, call in pairs(CALLS) do
      assert.is_truthy(branch(init, event):find("if GC.VendorSales then " .. call .. " end", 1, true), event)
    end
  end)

  it("names the module nowhere else in Init.lua, except its install behind the same guard", function()
    local init = read("GoldCap/Core/Init.lua")
    local sites = {}
    for line in init:gmatch("[^\n]*GC%.VendorSales[^\n]*") do sites[#sites + 1] = line:match("^%s*(.-)%s*$") end
    local expected = { "if GC.VendorSales then GC.VendorSales.Install() end" }
    for _ in pairs(CALLS) do expected[#expected + 1] = true end
    assert.equal(#expected, #sites)
    for _, line in ipairs(sites) do
      assert.is_truthy(line:find("^if GC%.VendorSales then GC%.VendorSales%.%u%a+%(") , line)
    end
  end)

  it("only reads: Core/VendorSales.lua names no sell, buyback or pickup call", function()
    local text = read("GoldCap/Core/VendorSales.lua")
    for _, name in ipairs({ "UseContainerItem", "SellCursorItem", "BuybackItem(", "PickupContainerItem",
        "PickupMerchantItem", "SellAllJunkItems", "hooksecurefunc" }) do
      assert.is_nil(text:find(name, 1, true), name)
    end
  end)

  it("writes no ledger row: the ledger is auction house money the site reads", function()
    local text = read("GoldCap/Core/VendorSales.lua")
    assert.is_nil(text:find("GC.Ledger.Append", 1, true))
    assert.is_nil(text:find("ledger[", 1, true))
  end)
end)
