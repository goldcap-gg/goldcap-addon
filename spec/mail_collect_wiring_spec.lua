local helper = require("spec.spec_helper")

-- The Collect button takes gold and items out of the mailbox, so it gets the audit the auction
-- house calls have: the two take calls live in one place, nothing of Blizzard's inbox is hooked,
-- the pure modules name no client API, the press is the only way a run starts, and WoW: Forever
-- does not load any of it.
describe("mail collect wiring", function()
  local function read(path)
    local f = assert(io.open(path, "r"))
    local t = f:read("*a")
    f:close()
    return (t:gsub("%-%-[^\n]*", ""))
  end

  local function eachLua(visit)
    local listing = assert(io.popen("find GoldCap -name '*.lua'"))
    for path in listing:lines() do visit(path, read(path)) end
    listing:close()
  end

  local UI = "GoldCap/UI/MailCollect.lua"
  local PURE = { "GoldCap/Core/MailLoop.lua", "GoldCap/Core/MailClassify.lua", "GoldCap/Core/MailReturns.lua",
    "GoldCap/Core/MailStock.lua" }

  -- Core/MailLoop.lua makes the takes through the `api` it is handed (api.TakeInboxMoney(...)), the
  -- one spelling allowed outside the UI file: it names no global, and what api is can only be read
  -- in clientApi below.
  it("names the two take calls in UI/MailCollect.lua only, and there only inside clientApi", function()
    eachLua(function(path, text)
      if path ~= UI then
        local bare = text:gsub("api%.TakeInboxMoney%(", ""):gsub("api%.TakeInboxItem%(", "")
        assert.is_nil(bare:find("TakeInboxMoney", 1, true), path)
        assert.is_nil(bare:find("TakeInboxItem", 1, true), path)
        if path ~= "GoldCap/Core/MailLoop.lua" then
          assert.is_nil(text:find("TakeInbox", 1, true), path)
        end
      end
    end)
    local text = read(UI)
    local body = helper.functionBody(text, "local function clientApi()")
    local from = text:find(body, 1, true)
    local outside = text:sub(1, from - 1) .. text:sub(from + #body)
    assert.is_nil(outside:find("TakeInboxMoney", 1, true))
    assert.is_nil(outside:find("TakeInboxItem", 1, true))
    assert.is_truthy(body:find("TakeInboxMoney(index)", 1, true))
    assert.is_truthy(body:find("TakeInboxItem(index, slot)", 1, true))
  end)

  it("never calls AutoLootMailItem", function()
    eachLua(function(path, text) assert.is_nil(text:find("AutoLootMailItem", 1, true), path) end)
  end)

  it("hooks nothing of Blizzard's inbox", function()
    local paths = { UI }
    for _, path in ipairs(PURE) do paths[#paths + 1] = path end
    for _, path in ipairs(paths) do
      local text = read(path)
      for _, word in ipairs({ "hooksecurefunc", "InboxFrame", "OpenAllMail", "MailFrame_" }) do
        assert.is_nil(text:find(word, 1, true), path .. " names " .. word)
      end
    end
  end)

  it("keeps the pure modules free of client API", function()
    for _, path in ipairs(PURE) do
      local text = read(path)
      assert.is_nil(text:find("C_%u"), path)
      local stripped = text:gsub("_G%.RETRIEVING_DATA", "")
      assert.is_nil(stripped:find("%f[%w_]_G%f[^%w_]"), path)
      assert.is_nil(text:find("CreateFrame", 1, true), path)
    end
  end)

  it("starts a run only from the press", function()
    local text = read(UI)
    local body = helper.functionBody(text, "local function onCollectClick()")
    local from = text:find(body, 1, true)
    local outside = text:sub(1, from - 1) .. text:sub(from + #body)
    assert.is_nil(outside:find(":Start(", 1, true))
    assert.is_truthy(body:find(":Start(", 1, true))
    -- Nothing else in the addon starts the loop.
    eachLua(function(path, source)
      if path ~= UI and path ~= "GoldCap/Core/MailLoop.lua" then
        assert.is_nil(source:find("MailLoop.New", 1, true), path)
      end
    end)
  end)

  it("has no production code that reads a control only the mailbox double has", function()
    eachLua(function(path, text)
      for _, name in ipairs({ "setCanCheck", "openingCalls", "isOpeningAll", "checkCalls", "pendingCommand" }) do
        assert.is_nil(text:find(name, 1, true), path .. " reads " .. name)
      end
      assert.is_nil(text:find(":advance(", 1, true), path)
      assert.is_nil(text:find(":refuse(", 1, true), path)
      assert.is_nil(text:find(":refreshNow(", 1, true), path)
    end)
  end)

  it("lists the four files in the retail TOC and not in the Forever one", function()
    local function lines(toc)
      local set, order = {}, {}
      for line in io.lines(toc) do
        if line:match("%S") and not line:match("^#") then set[line] = true; order[#order + 1] = line end
      end
      return set, order
    end
    local retail, order = lines("GoldCap/GoldCap.toc")
    local forever = lines("GoldCap/GoldCap_Camelot.toc")
    for _, file in ipairs({ "Core/MailReturns.lua", "Core/MailClassify.lua", "Core/MailLoop.lua", "UI/MailCollect.lua" }) do
      assert.is_true(retail[file], file)
      assert.is_nil(forever[file], file)
    end
    local function at(file) for i, f in ipairs(order) do if f == file then return i end end end
    assert.is_true(at("Core/Ledger.lua") < at("Core/MailReturns.lua"))
    assert.is_true(at("Core/MailReturns.lua") < at("Core/MailClassify.lua"))
    assert.is_true(at("Core/MailClassify.lua") < at("Core/MailLoop.lua"))
    assert.is_true(at("UI/BankRoute.lua") < at("UI/MailCollect.lua"))
    assert.is_true(at("UI/MailCollect.lua") < at("UI/SettingsFrame.lua"))
  end)

  it("guards every forward in Core/Init.lua with a check that the file is loaded", function()
    local text = read("GoldCap/Core/Init.lua")
    local forwards, guarded = 0, 0
    for _ in text:gmatch("GC%.MailCollect%.On%w+%(") do forwards = forwards + 1 end
    for _ in text:gmatch("if GC%.MailCollect then") do guarded = guarded + 1 end
    assert.equal(3, forwards)
    assert.is_true(guarded >= 2)
    for position in text:gmatch("()GC%.MailCollect%.On%w+%(") do
      local before = text:sub(math.max(1, position - 200), position - 1)
      assert.is_truthy(before:find("if GC%.MailCollect then"), "an unguarded forward")
    end
  end)
end)
