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

  -- What SELL does with the mailbox's returned lots log is told in its own Sell line, never in a
  -- Mail one. And the owner's rule for every player-facing text: no long dashes.
  it("promises no Sell tab behaviour in a Mail bullet, and uses no long dash there", function()
    local mailBullets = 0
    for _, section in ipairs(sections()) do
      for _, bullet in ipairs(section.bullets) do
        if bullet:find("^%- Mail:") then
          mailBullets = mailBullets + 1
          assert.is_nil(bullet:find("Sell", 1, true), bullet)
          assert.is_nil(bullet:find("\226\128\148", 1, true), bullet)
          assert.is_nil(bullet:find("\226\128\147", 1, true), bullet)
        end
      end
    end
    assert.is_true(mailBullets > 0)
  end)

  -- WoW: Forever loads none of the files behind these (spec/camelot_toc_spec.lua's RETAIL_ONLY), and
  -- the same post goes to its players. A line about one says "in retail WoW" after its area, or
  -- follows a line of the same area that does, as the Mail lines do.
  it("says retail WoW on every line of the newest release about a feature WoW: Forever does not load", function()
    local RETAIL_ONLY = { "a group you follow are posted", "CANCEL button", "POSTING setting", "the Vendor card",
      "^%- Crafting" }
    local section = sections()[1]
    local lastArea, lastRetail
    local checked = 0
    for _, bullet in ipairs(section.bullets) do
      local head = bullet:match("^%- ([^:%.]+):")
      local retail = head ~= nil and head:find(", in retail WoW", 1, true) ~= nil
      local area = head and head:gsub(", in retail WoW$", "")
      local covered = retail or (area ~= nil and area == lastArea and lastRetail)
      for _, marker in ipairs(RETAIL_ONLY) do
        if bullet:find(marker, 1, marker:sub(1, 1) ~= "^") then
          checked = checked + 1
          assert.is_true(covered, bullet)
        end
      end
      lastArea, lastRetail = area, covered
    end
    assert.is_true(checked >= 7)
  end)

  it("does not promise the vendor price in Forever tooltips, which leave it to the game", function()
    for _, bullet in ipairs(assert(firstForever()).bullets) do
      if bullet:find("Tooltips", 1, true) then
        assert.is_nil(bullet:find("what a vendor pays", 1, true), bullet)
      end
    end
  end)
end)
