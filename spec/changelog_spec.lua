-- GoldCap/CHANGELOG.md is read verbatim by CurseForge, Wago, the Discord release post and the
-- site's /changelog: a player reads a section as one release against the one they had. The
-- release that first ships WoW: Forever cannot describe a Forever change against an earlier
-- Forever build nobody had (final review I3, plan 3c).
describe("CHANGELOG.md", function()
  local function sections()
    local f = assert(io.open("GoldCap/CHANGELOG.md", "r"))
    local text = f:read("*a")
    f:close()
    local out, current = {}, nil
    for line in (text .. "\n"):gmatch("(.-)\n") do
      local heading = line:match("^## (.+)$")
      if heading then
        current = { heading = heading, bullets = {} }
        out[#out + 1] = current
      elseif current and line:match("^%- ") then
        current.bullets[#current.bullets + 1] = line
      elseif current and line:match("^  %S") and #current.bullets > 0 then
        current.bullets[#current.bullets] = current.bullets[#current.bullets] .. " " .. line:gsub("^%s+", "")
      end
    end
    return out
  end

  local function firstForever()
    local all = sections()
    for i = #all, 1, -1 do
      local section = all[i]
      for _, bullet in ipairs(section.bullets) do
        if bullet:find("GoldCap now runs in WoW: Forever", 1, true) then return section end
      end
    end
  end

  it("tells the first Forever release as new, never as a change to a Forever nobody had", function()
    local section = assert(firstForever(), "no section introduces WoW: Forever")
    for _, bullet in ipairs(section.bullets) do
      if bullet:find("WoW: Forever", 1, true) then
        assert.is_nil(bullet:find("no longer", 1, true), bullet)
      end
    end
  end)

  it("does not promise the vendor price in Forever tooltips, which leave it to the game", function()
    for _, bullet in ipairs(assert(firstForever()).bullets) do
      if bullet:find("Tooltips", 1, true) then
        assert.is_nil(bullet:find("what a vendor pays", 1, true), bullet)
      end
    end
  end)
end)
