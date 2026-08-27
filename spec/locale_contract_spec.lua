local helper = require("spec.spec_helper")

-- These two run against EVERY locale file, so they are the batch's safety net: they are what
-- stops a translation silently formatting the wrong value into the wrong slot, or a language
-- quietly going half-English after a string is reworded.
describe("locale contract", function()
  local GC

  local function specifiers(text)
    local found = {}
    for spec in text:gmatch("%%[-+ #0]*%d*%.?%d*[diouxXeEfgGqcs]") do
      found[#found + 1] = spec
    end
    return found
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Locale/Core.lua", GC)
    -- enUS is loaded by this loop too; it is the key set every other language is measured
    -- against, so a listed code with no file must fail loudly rather than skip.
    for _, code in ipairs(helper.localeCodes()) do
      helper.loadModule("Locale/" .. code .. ".lua", GC)
    end
  end)

  it("keeps every translation's format specifiers in the key's order", function()
    for code, strings in pairs(GC.Locales) do
      for key, value in pairs(strings) do
        assert.same(specifiers(key), specifiers(value),
          ("%s: %q formats differently from its key"):format(code, key))
      end
    end
  end)

  -- A pass that wraps strings in bulk can catch a frame anchor, a draw layer or a script
  -- handler name -- all of which are English words the client matches EXACTLY. Wrapped, they
  -- keep working in English (the fallback returns the key) and break the moment somebody
  -- translates them, which is the worst possible failure shape: silent until it is somebody
  -- else's language. TOPLEFT and friends were caught exactly this way.
  it("never treats a client constant as a translatable string", function()
    local TECHNICAL = {
      TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
      TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
      OVERLAY = true, ARTWORK = true, BACKGROUND = true, BORDER = true, HIGHLIGHT = true,
      DIALOG = true, TOOLTIP = true, MEDIUM = true, HIGH = true, LOW = true, WORLD = true,
      LeftButton = true, RightButton = true, AnyUp = true, AnyDown = true,
      OnClick = true, OnEnter = true, OnLeave = true, OnShow = true, OnHide = true,
      ADD = true, BLEND = true,
    }
    for key in pairs(GC.Locales.enUS) do
      assert.is_nil(TECHNICAL[key], ("%q is a client constant, not player-facing text"):format(key))
    end
  end)

  it("keeps a started language from going mostly English", function()
    local base = GC.Locales.enUS
    local total = 0
    for _ in pairs(base) do total = total + 1 end
    for code, strings in pairs(GC.Locales) do
      if code ~= "enUS" and next(strings) ~= nil then
        local missing = 0
        for key in pairs(base) do
          if strings[key] == nil then missing = missing + 1 end
        end
        -- An untranslated key degrades to English, which is legitimate mid-translation. A
        -- language that has been STARTED and is mostly empty is a merge accident, not a choice.
        assert.is_true(missing <= total * 0.5,
          ("%s covers %d of %d keys"):format(code, total - missing, total))
      end
    end
  end)
end)
