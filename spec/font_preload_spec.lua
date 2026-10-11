local helper = require("spec.spec_helper")

-- The first time the client draws with a font file it has not loaded yet, the text laid out in
-- that frame is not drawn, and nothing draws it later. On WoW: Forever 1.60.1 the Sniper's column
-- headings came up blank on the first auction house visit after a client start: the window is
-- built in one frame and was the first thing to use GoldCap's own faces. Re-stamping the text is a
-- race with the load, which is why that fix kept coming back. UI/FontPreload.lua has the client
-- load the faces at login instead, the way ElvUI and TradeSkillMaster preload theirs.

local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

describe("GoldCap's own font files are loaded at login", function()
  local frames

  local function fakeFontString()
    return {
      SetFont = function(self, path, size, flags)
        self.font = { path = path, size = size, flags = flags }
        return true
      end,
      SetText = function(self, text) self.text = text end,
      SetAllPoints = function(self) self.allPoints = true end,
    }
  end

  local function fakeFrame()
    local f = { shown = true, strings = {} }
    function f:SetPoint(...) self.point = { ... } end
    function f:SetSize(w, h) self.size = { w, h } end
    function f:SetAllPoints() self.allPoints = true end
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:SetScript() end
    function f:CreateFontString()
      local fs = fakeFontString()
      self.strings[#self.strings + 1] = fs
      return fs
    end
    return f
  end

  before_each(function()
    frames = {}
    _G.UIParent = fakeFrame()
    _G.CreateFrame = function()
      local f = fakeFrame()
      frames[#frames + 1] = f
      return f
    end
  end)

  after_each(function()
    _G.CreateFrame, _G.UIParent = nil, nil
  end)

  -- The frame that holds strings in a given face, if any.
  local function preloaderFor(path)
    for _, f in ipairs(frames) do
      for _, fs in ipairs(f.strings) do
        if fs.font and fs.font.path == path then return f, fs end
      end
    end
  end

  it("draws text in each bundled face, in a frame that is shown, sized and anchored", function()
    local GC = helper.loadModule("UI/Theme.lua")
    helper.loadModule("UI/FontPreload.lua", GC)

    assert.equal(7, #GC.Theme.BUNDLED_FACES)
    for _, path in ipairs(GC.Theme.BUNDLED_FACES) do
      local f, fs = preloaderFor(path)
      assert.is_not_nil(f, path .. " was never put on a string")
      assert.is_true(fs.font.size > 0, path .. " has no size")
      assert.is_true(type(fs.text) == "string" and fs.text ~= "", path .. " was given no text to draw")
      -- ElvUI found the client loads nothing for a preloader that is hidden, unsized or unanchored.
      assert.is_true(f.shown, "the preloader is hidden")
      assert.is_not_nil(f.size, "the preloader has no size")
      assert.is_true(f.size[1] > 0 and f.size[2] > 0, "the preloader has no size")
      assert.is_not_nil(f.point, "the preloader is not anchored")
    end
  end)

  it("loads right after UI/Theme.lua in both TOCs, before any window is built", function()
    for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
      assert.is_truthy(read(toc):find("UI/Theme.lua\r?\nUI/FontPreload.lua\r?\n"),
        toc .. " does not load UI/FontPreload.lua right after UI/Theme.lua")
    end
  end)
end)
