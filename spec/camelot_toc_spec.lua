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
  it("loads the followed groups' rules but not what steps a price down or reads the mail", function()
    local _, files = split(read("GoldCap/GoldCap_Camelot.toc"))
    local at = {}
    for i, f in ipairs(files) do at[f] = i end
    assert.is_not_nil(at["Core/GroupRules.lua"])
    assert.is_true(at["Core/Caps.lua"] < at["Core/GroupRules.lua"])
    for _, f in ipairs({ "Core/SellRounds.lua", "Core/MailReturns.lua", "Core/CancelRun.lua", "Core/Hoard.lua",
      "Core/BankGroups.lua", "Core/MailGroups.lua", "Core/Alts.lua" }) do
      assert.is_nil(at[f], f)
    end
  end)

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
  -- goldcap.gg works out where flips sell for retail realms alone. The followed groups' selling
  -- rules (Core/GroupRules.lua) load in both games; their step-down rounds (Core/SellRounds.lua)
  -- and the mail, bank and Hoard files stay retail only. The mail files
  -- (Core/Mail*.lua) and the vendor sell files are retail only in this wave:
  -- WoW: Forever must not change. Crafting in the profession window loads in both games, with
  -- Forever's differences in files of its own (FOREVER_ONLY below).
  local RETAIL_ONLY = { ["Data/MarketData.lua"] = true, ["UI/BankRoute.lua"] = true,
    ["Core/SellRounds.lua"] = true, ["Core/CancelRun.lua"] = true,
    ["Core/MailReturns.lua"] = true, ["Core/MailClassify.lua"] = true,
    ["Core/MailStock.lua"] = true,
    ["Core/VendorSelect.lua"] = true, ["Data/NoDisenchant.lua"] = true, ["Core/Disenchant.lua"] = true,
    ["Core/VendorPress.lua"] = true,
    ["Services/VendorBags.lua"] = true, ["UI/VendorSellCard.lua"] = true }
  -- The Hoard: the followed groups at a bank are retail only, and so is the bank route they move
  -- through.
  RETAIL_ONLY["Core/BankGroups.lua"] = true
  RETAIL_ONLY["Core/Alts.lua"] = true
  RETAIL_ONLY["Core/MailGroups.lua"] = true
  RETAIL_ONLY["Core/MailPress.lua"] = true
  RETAIL_ONLY["Core/Hoard.lua"] = true
  RETAIL_ONLY["UI/HoardFrame.lua"] = true
  RETAIL_ONLY["UI/HoardRow.lua"] = true
  RETAIL_ONLY["UI/HoardList.lua"] = true
  RETAIL_ONLY["UI/HoardTiles.lua"] = true
  RETAIL_ONLY["UI/HoardCarry.lua"] = true
  RETAIL_ONLY["UI/HoardFooter.lua"] = true
  -- Send to alts beside the mailbox: retail only, as the Hoard it is built from.
  RETAIL_ONLY["UI/MailAltsFrame.lua"] = true
  -- The Disenchant window beside the bags: retail only, as the Hoard it is drawn with.
  RETAIL_ONLY["UI/DisenchantFrame.lua"] = true
  RETAIL_ONLY["UI/DisenchantMarks.lua"] = true
  -- GoldCap's button on the minimap, which counts what is worth disenchanting: retail only for now.
  RETAIL_ONLY["UI/MinimapButton.lua"] = true

  -- WoW: Forever's own files, each loaded right after the file whose functions it replaces where
  -- Forever differs (or, for a pure module, beside the files that use it). Retail never loads them.
  local FOREVER_ONLY = {
    ["Core/ForeverVendorPrices.lua"] = "Core/CraftQueue.lua",
    ["Services/CraftClient_Camelot.lua"] = "Services/CraftClient.lua",
    ["UI/CraftPanel_Camelot.lua"] = "UI/CraftQueueView.lua",
    ["UI/BuyFrame_Camelot.lua"] = "UI/BuyFrame.lua",
    ["UI/SniperFrame_Camelot.lua"] = "UI/SniperFrame.lua",
    -- Sales to a merchant, read off the buyback list: beside the merchant purchases it mirrors.
    ["Core/VendorSales.lua"] = "Core/VendorBuys.lua",
  }

  it("loads the same files in the same order, minus the retail-only files, plus its own", function()
    local expected, shared = {}, {}
    for _, f in ipairs(retailF) do
      if not RETAIL_ONLY[f] then expected[#expected + 1] = f end
    end
    for _, f in ipairs(foreverF) do
      if not FOREVER_ONLY[f] then shared[#shared + 1] = f end
    end
    assert.same(expected, shared)
  end)

  it("loads each of its own files right after the file it belongs with, and retail none of them", function()
    local at = {}
    for i, f in ipairs(foreverF) do at[f] = i end
    for file, after in pairs(FOREVER_ONLY) do
      assert.is_not_nil(at[file], file)
      assert.equal(at[after] + 1, at[file], file)
    end
    for _, f in ipairs(retailF) do assert.is_nil(FOREVER_ONLY[f], f) end
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
