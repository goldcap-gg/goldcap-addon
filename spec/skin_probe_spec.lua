local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The dev-only skin probe (Dev/SkinProbe.lua, /gcprobe skins): what it records for each texture it
-- draws, so a round in the client tells which art the skins' fallbacks can count on.
describe("skin probe", function()
  local GC, restore, saved

  before_each(function()
    restore = W.install()
    saved = { UIParent = _G.UIParent, SlashCmdList = _G.SlashCmdList, GoldCapDB = _G.GoldCapDB }
    _G.UIParent = W.CreateFrame("Frame")
    _G.SlashCmdList = {}
    _G.GoldCapDB = nil
    GC = { Print = function() end }
    helper.loadModule("Dev/SkinProbe.lua", GC)
  end)

  after_each(function()
    restore()
    _G.UIParent, _G.SlashCmdList, _G.GoldCapDB = saved.UIParent, saved.SlashCmdList, saved.GoldCapDB
    _G.SLASH_GOLDCAPPROBE1 = nil
  end)

  it("draws a path that does not exist beside the real ones, so the client shows what SetTexture returns for it", function()
    _G.SlashCmdList.GOLDCAPPROBE("skins")
    local textures = _G.GoldCapDB.probe.skins.textures
    local missing = textures["Interface\\AddOns\\GoldCap\\Media\\does_not_exist"]
    assert.is_not_nil(missing)
    assert.is_false(missing.atlas)
    assert.is_not_nil(textures["Interface\\Tooltips\\UI-Tooltip-Border"])
    local count = 0
    for _ in pairs(textures) do count = count + 1 end
    assert.equal(12, count)  -- the 4 by 3 grid, full
  end)
end)
