local function read(path)
  local f = assert(io.open(path, "r"))
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = (line:gsub("\r$", "")) end
  f:close()
  return lines
end

local function split(lines)
  local directives, files = {}, {}
  for _, l in ipairs(lines) do
    local key, value = l:match("^##%s*([^:]+):%s*(.*)$")
    if key then directives[key] = value
    elseif l:match("%S") and not l:match("^#") then files[#files + 1] = l end
  end
  return directives, files
end

describe("GoldCap_Camelot.toc (WoW: Forever)", function()
  local retailD, retailF = split(read("GoldCap/GoldCap.toc"))
  local foreverD, foreverF = split(read("GoldCap/GoldCap_Camelot.toc"))

  it("declares the Forever interface", function()
    assert.equal("16001", foreverD["Interface"])
  end)

  it("carries every other directive of the retail TOC unchanged", function()
    for key, value in pairs(retailD) do
      if key ~= "Interface" then assert.equal(value, foreverD[key], key) end
    end
    for key in pairs(foreverD) do
      assert.is_not_nil(retailD[key], "extra directive " .. key)
    end
  end)

  -- Minus retail's price snapshot, and the carry list at the Warband Bank (UI/BankRoute.lua):
  -- goldcap.gg works out where flips sell for retail realms alone. Minus the followed groups'
  -- selling rules too: groups are retail only (plan 2026-10-22). The mail collect files
  -- (Core/Mail*.lua, UI/MailCollect.lua) and the vendor sell files are retail only in this wave:
  -- WoW: Forever must not change. Crafting in the profession window is retail's too: Forever's
  -- professions differ and have a design of their own.
  local RETAIL_ONLY = { ["Data/MarketData.lua"] = true, ["UI/BankRoute.lua"] = true,
    ["Core/GroupRules.lua"] = true, ["Core/SellRounds.lua"] = true, ["Core/CancelRun.lua"] = true,
    ["Core/MailReturns.lua"] = true, ["Core/MailClassify.lua"] = true,
    ["Core/MailLoop.lua"] = true, ["Core/MailStock.lua"] = true, ["UI/MailCollect.lua"] = true,
    ["Core/VendorSelect.lua"] = true, ["Core/VendorPress.lua"] = true,
    ["Services/VendorBags.lua"] = true, ["UI/VendorSellCard.lua"] = true }
  RETAIL_ONLY["Core/CraftMath.lua"] = true
  RETAIL_ONLY["Core/CraftQueue.lua"] = true
  RETAIL_ONLY["Services/CraftClient.lua"] = true
  RETAIL_ONLY["UI/CraftStrip.lua"] = true
  RETAIL_ONLY["UI/CraftPanel.lua"] = true
  RETAIL_ONLY["UI/CraftQueueView.lua"] = true
  -- Bank by group: the followed groups are retail only, and so is the bank route it moves through.
  RETAIL_ONLY["Core/BankGroups.lua"] = true
  RETAIL_ONLY["UI/BankGroupsCard.lua"] = true

  it("loads the same files in the same order, minus the retail-only files", function()
    local expected = {}
    for _, f in ipairs(retailF) do
      if not RETAIL_ONLY[f] then expected[#expected + 1] = f end
    end
    assert.same(expected, foreverF)
  end)
end)

-- The AddOns list groups by category: GoldCap sits under "Auctions" beside Auctionator, with
-- Auctionator's own word for it in each client language.
describe("the AddOns list category", function()
  local CATEGORY = {
    enUS = "Auctions", deDE = "Auktionen", esES = "Subastas", esMX = "Subastas", frFR = "Ventes",
    itIT = "Aste", koKR = "경매", ptBR = "Leilões", ruRU = "Лоты", zhCN = "拍卖", zhTW = "拍賣",
  }

  for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
    it("is Auctions in every language, in " .. toc, function()
      local directives = split(read(toc))
      for code, word in pairs(CATEGORY) do
        assert.equal(word, directives["Category-" .. code], code)
      end
    end)
  end
end)
