local helper = require("spec.spec_helper")

-- The rules the design sets for UI/Kit (wow-auction:
-- docs/superpowers/specs/2026-10-09-addon-ui-kit-and-sell-design.md): both games load the same kit
-- files in the same order right before UI/Theme.lua, no kit file grows past 1000 lines or 150
-- top-level locals, and no kit widget paints its hover by hand.
local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local function tocEntries(path)
  local out = {}
  for line in read(path):gmatch("[^\r\n]+") do
    if not line:match("^##") and line:match("%S") then out[#out + 1] = (line:gsub("\\", "/")) end
  end
  return out
end

local function code(text)
  return (text:gsub("%-%-[^\n]*", ""))
end

describe("UI/Kit", function()
  it("loads in helper.KIT_FILES order right before UI/Theme.lua in both TOCs", function()
    for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
      local entries, at = tocEntries(toc), nil
      for i, entry in ipairs(entries) do
        if entry == "UI/Theme.lua" then at = i end
      end
      assert.is_not_nil(at, toc .. " has no UI/Theme.lua")
      local before = {}
      for i = at - #helper.KIT_FILES, at - 1 do before[#before + 1] = entries[i] end
      assert.same(helper.KIT_FILES, before, toc)
    end
  end)

  it("keeps every kit file under 1000 lines and 150 top-level locals", function()
    for _, path in ipairs(helper.KIT_FILES) do
      local lines, locals = 0, 0
      for line in (read("GoldCap/" .. path) .. "\n"):gmatch("([^\n]*)\n") do
        lines = lines + 1
        if line:match("^local%s+function%s") then
          locals = locals + 1
        elseif line:match("^local%s") then
          local names = line:match("^local%s+([%w_,%s]+)") or ""
          local _, commas = names:gsub(",", "")
          locals = locals + commas + 1
        end
      end
      assert.is_true(lines < 1000, ("%s has %d lines"):format(path, lines))
      assert.is_true(locals < 150, ("%s has %d top-level locals"):format(path, locals))
    end
  end)

  it("paints no hover or press by hand: no OnEnter, OnLeave or OnMouseDown in a kit file", function()
    for _, path in ipairs(helper.KIT_FILES) do
      local text = code(read("GoldCap/" .. path))
      for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
        assert.is_nil(text:find(script, 1, true), path .. " sets " .. script)
      end
    end
  end)
end)
