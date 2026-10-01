-- The vendor note (UI/MerchantNote.lua): how it is wired, and what it must never do.

local function read(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

local function code(path)
  return (read(path):gsub("%-%-[^\n]*", ""))
end

local PATH = "GoldCap/UI/MerchantNote.lua"

describe("vendor note wiring", function()
  it("loads in both games", function()
    for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
      assert.truthy(read(toc):find("\nUI/MerchantNote.lua\n", 1, true), toc)
    end
  end)

  it("opens and closes with the vendor, and counts again when the bags change", function()
    local init = read("GoldCap/Core/Init.lua")
    local show = assert(init:find('event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"', 1, true))
    local hide = assert(init:find('event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"', 1, true))
    local after = assert(init:find('event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED"', 1, true))
    local merchant = "interactionType == Enum.PlayerInteractionType.Merchant"
    local s1 = assert(init:find(merchant, show, true))
    assert.is_true(s1 < hide)
    assert.is_true(assert(init:find("GC.MerchantNote.OnMerchantShow()", s1, true)) < hide)
    local h1 = assert(init:find(merchant, hide, true))
    assert.is_true(h1 < after)
    assert.is_true(assert(init:find("GC.MerchantNote.OnMerchantClosed()", h1, true)) < after)
    local bags = assert(init:find('event == "BAG_UPDATE_DELAYED"', 1, true))
    local world = assert(init:find('event == "PLAYER_ENTERING_WORLD"', bags, true))
    assert.is_true(assert(init:find("GC.MerchantNote.OnBagsChanged()", bags, true)) < world)
  end)

  -- Selling grey items for the player is not this note's job: whether an addon button may sell to
  -- a vendor in WoW: Forever has not been measured.
  it("never sells, buys, uses or picks up anything", function()
    local text = code(PATH)
    for _, needle in ipairs({ "UseContainerItem", "PickupContainerItem", "SellAllJunkItems", "BuyMerchantItem",
        ":Click(", ".Click(", "SetScript(" }) do
      assert.is_nil(text:find(needle, 1, true), needle)
    end
  end)

  it("never tells the games apart: both draw the same vendor window", function()
    local text = code(PATH)
    for _, needle in ipairs({ "IsForever", "WOW_PROJECT_ID", "GetBuildInfo" }) do
      assert.is_nil(text:find(needle, 1, true), needle)
    end
  end)

  it("switches nothing with SetAlpha, and writes no middle dot the client's fonts may lack", function()
    local text = code(PATH)
    assert.is_nil(text:find("SetAlpha", 1, true))
    assert.is_nil(text:find("\194\183", 1, true))
    local helper = require("spec.spec_helper")
    local GC = helper.loadModule("Locale/Core.lua")
    local KEYS = {
      "1 item in your bags fetches more on the auction house (+%s). Keep it for the AH.",
      "%d items in your bags fetch more on the auction house (+%s). Keep them for the AH.",
    }
    for _, localeCode in ipairs(helper.localeCodes()) do
      helper.loadModule("Locale/" .. localeCode .. ".lua", GC)
      for _, key in ipairs(KEYS) do
        local value = GC.Locales[localeCode][key]
        assert.is_string(value, localeCode .. " has no " .. key)
        assert.is_nil(value:find("\194\183", 1, true), localeCode .. ": " .. value)
        assert.is_nil(value:find("...", 1, true), localeCode .. ": " .. value)
        assert.is_nil(value:find("\226\128\166", 1, true), localeCode .. ": " .. value)
      end
    end
  end)
end)
