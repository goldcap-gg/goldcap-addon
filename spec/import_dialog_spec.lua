local helper = require("spec.spec_helper")

-- UI/ImportDialog.lua is a router before it is a dialog: a `GCR1;` buy run goes to
-- Core/AppRuns.lua, anything else to the GCS1 price parser. The run parser is the real one; only
-- the widgets and the price parser are faked, since what is under test is which one gets the text
-- and what happens to the BUY tab afterwards.
describe("ImportDialog", function()
  local GC, frames, pricesParsed, selectedRun, refreshed

  local function region(kind)
    local f = { kind = kind, shown = false, scripts = {}, textValue = "" }
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetHeight() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:SetMultiLine() end
    function f:SetFontObject() end
    function f:SetAutoFocus() end
    function f:SetFocus() end
    function f:SetScrollChild(child) self.child = child end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetText(t) self.textValue = t end
    function f:GetText() return self.textValue end
    function f:CreateFontString() return region("FontString") end
    function f:CreateTexture() return region("Texture") end
    f.TitleText = { SetText = function() end }
    return f
  end

  -- The Import button is a local inside createDialog and is not published on the frame, so it is
  -- found the way a player finds it: the button carrying that label.
  local function importButton()
    for _, f in ipairs(frames) do
      if f.kind == "Button" and f:GetText() == "Import" then return f end
    end
    error("no Import button was built")
  end

  local function paste(text)
    GC.UI.ShowImportDialog()
    local dialog = _G.GoldCapImportDialog
    dialog.edit:SetText(text)
    importButton().scripts.OnClick()
    return dialog
  end

  before_each(function()
    frames, pricesParsed, selectedRun, refreshed = {}, nil, nil, false
    _G.CreateFrame = function(kind, name, _, _)
      local f = region(kind)
      frames[#frames + 1] = f
      if name and name ~= "" then _G[name] = f end -- real WoW auto-publishes named frames
      return f
    end
    _G.UIParent = {}
    _G.ChatFontNormal = {}

    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/AppRuns.lua", GC)
    GC.db = { runs = {} }
    GC.Print = function() end
    -- The GCS1 half of the router, stubbed: all this spec asks of it is whether it was handed
    -- text that was never its to read.
    GC.ImportString = { Parse = function(text) pricesParsed = text; return nil, "bad_header" end }
    GC.Data = { DescribeImportError = function(err) return tostring(err) end }
    GC.Buy = {
      SelectRun = function(code) selectedRun = code end,
      RefreshIfShown = function() refreshed = true end,
    }
    helper.loadModule("UI/ImportDialog.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame, _G.UIParent, _G.ChatFontNormal = nil, nil, nil
    _G.GoldCapImportDialog = nil
  end)

  it("imports a run string", function()
    local dialog = paste("GCR1;myrun;Flask%20run;5=210,6=4=v")
    assert.is_nil(pricesParsed)
    local run = GC.AppRuns.Get("myrun")
    assert.is_not_nil(run)
    assert.equal("Flask run", run.name)
    assert.is_false(dialog.shown)
  end)

  -- Core/AppRuns.lua's own parser strips whitespace before it reads anything, so a pasted string
  -- with a space in front is a perfectly good run -- but an anchored `^GCR1;` never saw it, and
  -- the GCS1 parser answered "not a GoldCap import string" about a run it was never asked to read.
  it("imports a run string pasted with leading whitespace", function()
    paste("  GCR1;spaced;;5=210")
    assert.is_nil(pricesParsed)
    assert.is_not_nil(GC.AppRuns.Get("spaced"))
  end)

  -- The BUY tab picks its run in Show(), so a run pasted while the tab was already on screen sat
  -- in the list unseen until the player left it and came back -- which reads as an import that
  -- did nothing at all.
  it("puts the imported run on the BUY tab at once", function()
    paste("GCR1;myrun;;5=210")
    assert.equal("myrun", selectedRun)
    assert.is_true(refreshed)
  end)

  it("leaves anything that is not a run string to the price parser", function()
    local dialog = paste("GCS1;something else")
    assert.equal("GCS1;something else", pricesParsed)
    assert.is_nil(next(GC.db.runs))
    -- The failure is reported in the dialog rather than closing it over the player's text.
    assert.is_true(dialog.shown)
    assert.is_truthy(dialog.status:GetText():find("Import failed:", 1, true))
  end)

  it("says so when the run string itself is malformed, and keeps the dialog open", function()
    local dialog = paste("GCR1;myrun;;")
    assert.is_nil(pricesParsed)
    assert.is_nil(GC.AppRuns.Get("myrun"))
    assert.is_nil(selectedRun)
    assert.is_true(dialog.shown)
    assert.is_truthy(dialog.status:GetText():find("the run string is not valid", 1, true))
  end)
  local function statusLines()
    local printed = {}
    GC.Print = function(line) printed[#printed + 1] = line end
    GC.slashHandlers.status()
    return printed
  end

  local function lineWith(printed, text)
    for _, line in ipairs(printed) do
      if line:find(text, 1, true) then return line end
    end
    return nil
  end

  -- The memory figure is measured when asked (RegionPayloadMemoryKB): GetStatus never carries it
  -- until something has, so the status line has to ask for it itself.
  it("says what the whole-market payload carries on /goldcap status", function()
    GC.Data.AppDataError = function() return nil end
    GC.Data.GetStatus = function()
      return { region = "eu", bundledCount = 0,
        payload = { items = 9439, facts = 5494, refs = 25000, ts = time() - 7200 } }
    end
    GC.Data.RegionPayloadMemoryKB = function() return 4096 end
    GC.Data.RegionPayloadStatus = function() return nil end
    assert.equal("whole-market data: 9439 commodities, 5494 with sale facts, 25000 realm items (2h old, 4096 KB)",
      lineWith(statusLines(), "whole-market data:"))
  end)

  it("says nothing about a payload that is not there", function()
    GC.Data.AppDataError = function() return nil end
    GC.Data.GetStatus = function() return { region = "eu", bundledCount = 0 } end
    GC.Data.RegionPayloadStatus = function() return nil end
    local printed = statusLines()
    assert.is_nil(lineWith(printed, "whole-market data"))
  end)

  -- A payload the Companion wrote and this load could not use: the one place that says why.
  describe("a whole-market payload that is not in use", function()
    local function reasonLine(status)
      GC.Data.AppDataError = function() return nil end
      GC.Data.GetStatus = function() return { region = "eu", bundledCount = 0 } end
      GC.Data.RegionPayloadStatus = function() return status end
      return lineWith(statusLines(), "whole-market data not in use:")
    end

    it("says it is older than the prices imported, and how old", function()
      assert.equal("whole-market data not in use: it is 5h old, and the prices you imported are newer",
        reasonLine({ reason = "older_than_import", ts = time() - 5 * 3600 }))
    end)

    it("says it is for another region", function()
      assert.equal("whole-market data not in use: it is for another region than the prices loaded",
        reasonLine({ reason = "other_region", ts = time() - 600 }))
    end)

    -- A refused date can be 0, far ahead of the clock, or a digit run tonumber reads as inf: none
    -- of it is formatted as an age.
    it("points at the clock for a date that cannot be right, whatever the date", function()
      for _, ts in ipairs({ 0, time() + 86400 * 365, math.huge }) do
        assert.equal("whole-market data not in use: its date cannot be right -- check this computer's clock",
          reasonLine({ reason = "bad_ts", ts = ts }))
      end
    end)

    it("says it was set aside this session, and how to get it back", function()
      assert.equal("whole-market data not in use: it was set aside when other prices were loaded this session"
        .. " -- /reload to use it again", reasonLine({ reason = "set_aside", ts = time() - 600 }))
    end)

    -- Final review M6: the manual import's sentences answer a player who pasted something ("that
    -- does not look like a GoldCap import string"). Nobody pasted this; the Companion wrote it.
    it("gives each parser refusal a sentence of its own, not the manual import's", function()
      GC.Data.DescribeImportError = function(reason) return "import sentence for " .. reason end
      local expected = {
        empty = "the Companion wrote it empty -- let it sync again",
        no_items = "the Companion wrote it with no prices -- let it sync again",
        bad_header = "it is in a form this build of GoldCap cannot read -- update the addon",
        bad_region = "it is for a region this build of GoldCap does not know -- update the addon",
        too_long = "it is larger than this build of GoldCap reads -- update the addon",
      }
      for reason, sentence in pairs(expected) do
        assert.equal("whole-market data not in use: " .. sentence, reasonLine({ reason = reason }))
      end
    end)

    it("names a refusal it has no sentence for", function()
      assert.equal("whole-market data not in use: it could not be read (bad_tail)",
        reasonLine({ reason = "bad_tail" }))
    end)

    it("clamps an age it cannot trust rather than printing a negative or endless one", function()
      assert.equal("whole-market data not in use: it is <1h old, and the prices you imported are newer",
        reasonLine({ reason = "older_than_import", ts = math.huge }))
    end)
  end)
end)
