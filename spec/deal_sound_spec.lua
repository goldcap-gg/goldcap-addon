local helper = require("spec.spec_helper")

-- UI/DealSound.lua: the sound a deal makes, the player's pick in SETTINGS (owner, 2026-11-23:
-- players asked for a quieter one than the raid's ready check).
describe("GC.DealSound", function()
  local GC, played, saved

  before_each(function()
    saved = { PlaySound = _G.PlaySound, SOUNDKIT = _G.SOUNDKIT }
    played = {}
    _G.PlaySound = function(kit, channel)
      played[#played + 1] = { kit, channel }
      return true, 7
    end
    _G.SOUNDKIT = { LOOT_WINDOW_COIN_SOUND = 120, READY_CHECK = 8960, MAP_PING = 3175 }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/DealSound.lua", GC)
  end)

  after_each(function()
    _G.PlaySound, _G.SOUNDKIT = saved.PlaySound, saved.SOUNDKIT
  end)

  it("rings the map ping at the master volume when nothing was picked", function()
    assert.is_true(GC.DealSound.Ring({ sound = true }))
    assert.same({ { 3175, "Master" } }, played)
  end)

  it("rings what the player picked, through the sound effects channel when asked", function()
    GC.DealSound.Ring({ sound = true, dealSound = "readycheck", soundMaster = false })
    assert.same({ { 8960, "SFX" } }, played)
  end)

  -- A player who had turned the sound off before this setting existed hears nothing after it.
  it("stays silent while the switch is off", function()
    assert.is_false(GC.DealSound.Ring({ sound = false, dealSound = "ping" }))
    assert.is_false(GC.DealSound.Ring(nil))
    assert.same({}, played)
  end)

  it("plays a preview whatever the switch says", function()
    GC.DealSound.Play({ sound = false }, "coins")
    assert.same({ { 120, "Master" } }, played)
  end)

  it("falls back to the default for an id it does not know", function()
    assert.equal("ping", GC.DealSound.Chosen({ dealSound = "airhorn" }))
    GC.DealSound.Ring({ sound = true, dealSound = "airhorn" })
    assert.same({ { 3175, "Master" } }, played)
  end)

  it("uses the kit's number where the client's table lacks its name", function()
    GC.DealSound.Play({}, "whisper")
    assert.same({ { 3081, "Master" } }, played)
  end)

  it("names every choice in the player's language", function()
    for _, choice in ipairs(GC.DealSound.CHOICES) do
      local name = GC.DealSound.Name(choice.id)
      assert.is_string(name)
      assert.not_equal("", name)
    end
  end)
end)
