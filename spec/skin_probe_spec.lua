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

  describe("fonts", function()
    local G, later, recordBoot

    before_each(function()
      later = nil
      _G.C_Timer = { After = function(_, fn) later = fn end }
      _G.date = function() return "12:00:00" end
      G = helper.loadModule("UI/Theme.lua")
      G.Print = function() end
      helper.loadModule("Dev/SkinProbe.lua", G)
      recordBoot, later = later, nil -- the timer the file set as it loaded
    end)

    after_each(function()
      G.Kit.Skins.Apply("goldcap")
      _G.C_Timer, _G.date = nil, nil
    end)

    it("asks every skin face now and two seconds later, hidden and shown", function()
      _G.SlashCmdList.GOLDCAPPROBE("fonts")
      later()
      local run = _G.GoldCapDB.probe.fonts[1]
      for _, file in ipairs({ "OldStandard-Bold.ttf", "AlegreyaSC-Bold.ttf", "Alegreya-Medium.ttf",
        "RuslanDisplay-Regular.ttf", "FiraSans-Medium.ttf" }) do
        assert.same({ "true", "true" }, { tostring(run.now[file].hidden), tostring(run.now[file].shown) }, file)
        assert.is_not_nil(run.later[file], file)
      end
    end)

    it("keeps, on every load, which faces the applied skin took", function()
      G.Kit.Skins.Apply("leather")
      recordBoot()
      local record = _G.GoldCapDB.probe.fontBoots[1]
      assert.equal("leather", record.skin)
      assert.equal("OldStandard-Bold.ttf", record.wantHead)
      assert.equal("OldStandard-Bold.ttf", record.head)
    end)
  end)
end)
