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

  it("loads the same files in the same order, minus retail's price snapshot", function()
    local expected = {}
    for _, f in ipairs(retailF) do
      if f ~= "Data/MarketData.lua" then expected[#expected + 1] = f end
    end
    assert.same(expected, foreverF)
  end)
end)
