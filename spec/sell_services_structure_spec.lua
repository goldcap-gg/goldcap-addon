local helper = require("spec.spec_helper")

-- The rules the design sets for the Sell services (wow-auction:
-- docs/superpowers/specs/2026-10-09-addon-ui-kit-and-sell-design.md, "Part 2: code layout"): both
-- games load the same files in the same order, after Core and before any UI file; none grows past
-- 1000 lines or 150 top-level locals; none makes a protected call, which belongs to the click
-- handler in UI/SellFrame.lua; none reaches a frame, which it asks for through GC.SellView; and
-- nothing keeps a copy of a service's function, so a spec that replaces one reaches every caller.
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

local function lines(text)
  return (text .. "\n"):gmatch("([^\n]*)\n")
end

-- The services, and the view that calls into them.
local function sellFiles()
  local out = {}
  for _, path in ipairs(helper.SELL_FILES) do out[#out + 1] = path end
  out[#out + 1] = "UI/SellFrame.lua"
  return out
end

local MODULES = { "Quotes", "Bags", "Compose", "Owned", "Walk", "Post" }

describe("Services/Sell", function()
  it("loads as one block in helper.SELL_FILES order, after Core/QuoteCache.lua and before any UI file", function()
    for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
      local entries, first, cache, ui, count = tocEntries(toc), nil, nil, nil, 0
      for i, entry in ipairs(entries) do
        if entry == helper.SELL_FILES[1] then first = i end
        if entry == "Core/QuoteCache.lua" then cache = i end
        if not ui and entry:match("^UI/") then ui = i end
        if entry:match("^Services/") then count = count + 1 end
      end
      assert.is_not_nil(first, toc .. " does not load " .. helper.SELL_FILES[1])
      local block = {}
      for i = first, first + #helper.SELL_FILES - 1 do block[#block + 1] = entries[i] end
      assert.same(helper.SELL_FILES, block, toc)
      assert.equal(#helper.SELL_FILES, count, toc .. " loads a Services file helper.SELL_FILES does not list")
      assert.is_true(cache < first, toc .. ": Core/QuoteCache.lua must load before the services")
      assert.is_true(first + #helper.SELL_FILES - 1 < ui, toc .. ": the services must load before any UI file")
    end
  end)

  it("keeps every file under 1000 lines and 150 top-level locals", function()
    for _, path in ipairs(helper.SELL_FILES) do
      local count, locals = 0, 0
      for line in lines(read("GoldCap/" .. path)) do
        count = count + 1
        if line:match("^local%s+function%s") then
          locals = locals + 1
        elseif line:match("^local%s") then
          local names = line:match("^local%s+([%w_,%s]+)") or ""
          local _, commas = names:gsub(",", "")
          locals = locals + commas + 1
        end
      end
      assert.is_true(count < 1000, ("%s has %d lines"):format(path, count))
      assert.is_true(locals < 150, ("%s has %d top-level locals"):format(path, locals))
    end
  end)

  it("makes no protected call: those belong to the click handlers in UI/SellFrame.lua", function()
    local PROTECTED = { "PostItem", "PostCommodity", "ConfirmPostItem", "ConfirmPostCommodity", "CancelAuction",
      "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }
    for _, path in ipairs(helper.SELL_FILES) do
      local text = code(read("GoldCap/" .. path))
      for _, name in ipairs(PROTECTED) do
        assert.is_nil(text:find("C_AuctionHouse." .. name .. "(", 1, true), path .. " calls C_AuctionHouse." .. name)
      end
    end
  end)

  it("builds no frame and reads none: the screen is GC.SellView", function()
    for _, path in ipairs(helper.SELL_FILES) do
      local text = code(read("GoldCap/" .. path))
      for _, pattern in ipairs({ "CreateFrame", "%f[%w_]container%f[^%w_]", "statusOwner", "GC%.Theme" }) do
        assert.is_nil(text:find(pattern), path .. " reaches the frame: " .. pattern)
      end
    end
  end)

  it("keeps no copy of a service's function: calls go through the module table at run time", function()
    for _, path in ipairs(sellFiles()) do
      for line in lines(code(read("GoldCap/" .. path))) do
        if line:match("^local%s") then
          assert.is_nil(line:match("GC%.Sell%u%a+%.%u"), path .. ": " .. line)
          for _, name in ipairs(MODULES) do
            assert.is_nil(line:match("%f[%w_]" .. name .. "%.%u"), path .. ": " .. line)
          end
        end
      end
    end
  end)

  it("lets UI/SellFrame.lua fill every slot of GC.SellView", function()
    local GC = { Sell = {} }
    for _, path in ipairs(helper.SELL_FILES) do helper.loadModule(path, GC) end
    local defaults = {}
    for name, fn in pairs(GC.SellView) do defaults[name] = fn end
    assert.is_not_nil(next(defaults))
    helper.loadModule("UI/SellFrame.lua", GC)
    for name, fn in pairs(defaults) do
      assert.is_function(GC.SellView[name], name)
      assert.are_not.equal(fn, GC.SellView[name], name .. " is still the default")
    end
    assert.is_nil(GC.SellView.shown(), "shown() is nil before GC.Sell.Attach")
    assert.is_false(GC.SellView.attached())
  end)
end)
