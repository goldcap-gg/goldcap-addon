require("spec.spec_helper")

-- The minimap addon compartment (TOC directives, Patch 10.1.0) is the engine's own answer
-- to "give the addon a button", which is why no icon library is embedded for it. Verified
-- on warcraft.wiki.gg 2026-08-27: the compartment is present in current versions (12.1.0)
-- and Patch 11.0.0 dropped the third menuButtonFrame argument, so an automatic (TOC)
-- registration's click handler receives (addonName, buttonName) only.
describe("addon compartment", function()
  local function readFile(path)
    local f = assert(io.open(path))
    local text = f:read("*a")
    f:close()
    return text
  end

  it("registers all three handlers in the TOC", function()
    local text = readFile("GoldCap/GoldCap.toc")
    assert.is_truthy(text:find("## AddonCompartmentFunc: GoldCap_OnAddonCompartmentClick", 1, true))
    assert.is_truthy(text:find("## AddonCompartmentFuncOnEnter: GoldCap_OnAddonCompartmentEnter", 1, true))
    assert.is_truthy(text:find("## AddonCompartmentFuncOnLeave: GoldCap_OnAddonCompartmentLeave", 1, true))
  end)

  it("keeps the icon the compartment draws beside the entry", function()
    assert.is_truthy(readFile("GoldCap/GoldCap.toc"):find("## IconTexture:", 1, true))
  end)

  it("names handlers that Core/Init.lua actually defines as globals", function()
    local text = readFile("GoldCap/Core/Init.lua")
    for _, name in ipairs({ "Click", "Enter", "Leave" }) do
      assert.is_truthy(text:find("function GoldCap_OnAddonCompartment" .. name .. "(", 1, true),
        "Core/Init.lua defines no GoldCap_OnAddonCompartment" .. name)
    end
  end)
end)
