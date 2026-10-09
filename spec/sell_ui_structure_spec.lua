local helper = require("spec.spec_helper")

-- The rules the design sets for the Sell tab's view (wow-auction:
-- docs/superpowers/specs/2026-10-09-addon-ui-kit-and-sell-design.md, "Part 2: code layout"), the
-- view's half of spec/sell_services_structure_spec.lua: both games load the view's files as one
-- block where UI/SellFrame.lua used to load; no file under UI/Sell/ grows past 1000 lines or 150
-- top-level locals; and no file keeps a load-time copy of another part's function or of a
-- GC.SellUI state field, so a spec that replaces a function reaches every caller and a field the
-- code reassigns is never read stale.
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

-- The files under UI/Sell/. helper.SELL_UI_FILES also names UI/SellFrame.lua until the split
-- ends; the size rule is for the new files.
local function folderFiles()
  local out = {}
  for _, path in ipairs(helper.SELL_UI_FILES) do
    if path:match("^UI/Sell/") then out[#out + 1] = path end
  end
  return out
end

local MODULES = { "Toolbar", "List", "Row", "Inspector", "Book", "Dock", "CostDialog" }
local STATE = { "container", "content", "detailContent", "window", "rowWidth", "rowHeight", "rows", "expanded",
  "showNotOnHand", "chips" }

describe("UI/Sell", function()
  it("loads as one block in helper.SELL_UI_FILES order, between UI/SellViewModel.lua and UI/SoldFrame.lua", function()
    for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
      local entries, first, count = tocEntries(toc), nil, 0
      for i, entry in ipairs(entries) do
        if entry == helper.SELL_UI_FILES[1] then first = i end
        if entry:match("^UI/Sell/") then count = count + 1 end
      end
      assert.is_not_nil(first, toc .. " does not load " .. helper.SELL_UI_FILES[1])
      local block = {}
      for i = first, first + #helper.SELL_UI_FILES - 1 do block[#block + 1] = entries[i] end
      assert.same(helper.SELL_UI_FILES, block, toc)
      assert.equal(#folderFiles(), count, toc .. " loads a UI/Sell file helper.SELL_UI_FILES does not list")
      assert.equal("UI/SellViewModel.lua", entries[first - 1], toc)
      assert.equal("UI/SoldFrame.lua", entries[first + #helper.SELL_UI_FILES], toc)
    end
  end)

  it("keeps every file under UI/Sell/ under 1000 lines and 150 top-level locals", function()
    for _, path in ipairs(folderFiles()) do
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

  it("keeps no top-level copy of another part's function: calls go through GC.SellUI at run time", function()
    for _, path in ipairs(helper.SELL_UI_FILES) do
      for line in lines(code(read("GoldCap/" .. path))) do
        if line:match("^local%s") then
          assert.is_nil(line:match("GC%.SellUI%.%u%a*%.%u%l"), path .. ": " .. line)
          for _, name in ipairs(MODULES) do
            assert.is_nil(line:match("%f[%w_]" .. name .. "%.%u%l"), path .. ": " .. line)
          end
        end
      end
    end
  end)

  it("keeps no top-level copy of a GC.SellUI state field: a field the code reassigns would go stale", function()
    for _, path in ipairs(helper.SELL_UI_FILES) do
      for line in lines(code(read("GoldCap/" .. path))) do
        if line:match("^local%s") then
          for _, name in ipairs(STATE) do
            assert.is_nil(line:match("%f[%w_]UI%." .. name .. "%f[^%w_]"), path .. ": " .. line)
            assert.is_nil(line:match("GC%.SellUI%." .. name .. "%f[^%w_]"), path .. ": " .. line)
          end
        end
      end
    end
  end)

  it("fills GC.SellView's slots with wrappers, never with a copy of a view function", function()
    for _, path in ipairs(helper.SELL_UI_FILES) do
      for line in lines(code(read("GoldCap/" .. path))) do
        local rhs = line:match("^GC%.SellView%.%a+%s*=%s*(.-)%s*$")
        if rhs then assert.is_truthy(rhs:match("^function"), path .. ": " .. line) end
      end
    end
  end)

  it("reaches a replaced view function through the slot that names it", function()
    local GC = { Sell = {} }
    for _, path in ipairs(helper.SELL_FILES) do helper.loadModule(path, GC) end
    for _, path in ipairs(helper.SELL_UI_FILES) do helper.loadModule(path, GC) end
    local calls = {}
    GC.SellUI.List.RenderRows = function() calls[#calls + 1] = "render" end
    GC.SellUI.Dock.SetStatus = function(text) calls[#calls + 1] = "status " .. text end
    GC.SellUI.Dock.PaintQueueButton = function() calls[#calls + 1] = "queue" end
    GC.SellUI.Dock.PaintCancelButton = function() calls[#calls + 1] = "cancel" end
    GC.SellView.render(); GC.SellView.status("hi"); GC.SellView.paintQueue(); GC.SellView.paintCancel()
    assert.same({ "render", "status hi", "queue", "cancel" }, calls)
  end)

  it("makes no protected call outside UI/Sell/Dock.lua, whose click handlers are the only callers", function()
    local PROTECTED = { "PostItem", "PostCommodity", "ConfirmPostItem", "ConfirmPostCommodity", "CancelAuction",
      "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }
    for _, path in ipairs(helper.SELL_UI_FILES) do
      if path ~= "UI/Sell/Dock.lua" then
        local text = code(read("GoldCap/" .. path))
        for _, name in ipairs(PROTECTED) do
          assert.is_nil(text:find("C_AuctionHouse." .. name .. "(", 1, true), path .. " calls C_AuctionHouse." .. name)
          assert.is_nil(text:find("=%s*C_AuctionHouse%." .. name .. "%f[^%w_]"), path .. " aliases C_AuctionHouse." .. name)
        end
        assert.is_nil(text:find("C_AuctionHouse%s*%["), path .. " indexes C_AuctionHouse by key")
      end
    end
  end)
end)
