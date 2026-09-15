local helper = require("spec.spec_helper")

describe("AppRuns", function()
  local GC

  local function fixture()
    return {
      v = 1, generatedAt = 1787130262, plan = "pro", freeLines = 5,
      runs = {
        { code = "abcd2345", name = "Plant Protein run", updatedAt = 100,
          lines = {
            { i = 5, q = 210, v = false, n = "Plant Protein" },
            { i = 6, q = 4, v = true },
          } },
      },
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/AppRuns.lua", GC)
    GC.db = { runs = {}, runsMeta = { plan = "free", freeLines = 5, generatedAt = 0 } }
  end)

  after_each(function()
    _G.GoldCap_AppRuns = nil
  end)

  describe("Adopt", function()
    it("adopts a valid global and exposes it, plan pro means FreeLines() is nil", function()
      _G.GoldCap_AppRuns = fixture()
      assert.is_true(GC.AppRuns.Adopt())
      local run = GC.AppRuns.Get("abcd2345")
      assert.equal("Plant Protein run", run.name)
      assert.equal("app", run.origin)
      assert.equal(2, #run.lines)
      assert.equal(5, run.lines[1].i)
      assert.equal(210, run.lines[1].q)
      assert.is_false(run.lines[1].v)
      assert.equal("Plant Protein", run.lines[1].n)
      assert.is_true(run.lines[2].v)
      assert.is_nil(GC.AppRuns.FreeLines())
    end)

    it("refuses any version but 1, silently", function()
      local f = fixture(); f.v = 2
      _G.GoldCap_AppRuns = f
      assert.has_no.errors(function() assert.is_false(GC.AppRuns.Adopt()) end)
      assert.is_nil(GC.AppRuns.Get("abcd2345"))
    end)

    it("refuses a malshaped global, silently", function()
      for _, bad in ipairs({ "oops", 42,
          { v = 1, generatedAt = "later", runs = {} },
          { v = 1, generatedAt = 1, runs = "no" } }) do
        _G.GoldCap_AppRuns = bad
        assert.has_no.errors(function() assert.is_false(GC.AppRuns.Adopt()) end)
      end
    end)

    it("drops a malformed run row and keeps the valid ones", function()
      local f = fixture()
      table.insert(f.runs, { code = "", lines = { { i = 1, q = 1 } } }) -- empty code
      table.insert(f.runs, { code = "no-lines-run", lines = {} }) -- no valid lines
      table.insert(f.runs, { code = "bad-line-run", lines = { { i = "x", q = 1 } } }) -- malformed line
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      assert.equal(1, #GC.AppRuns.List())
    end)

    it("is idempotent: re-adopting the same generatedAt changes nothing and returns false", function()
      _G.GoldCap_AppRuns = fixture()
      assert.is_true(GC.AppRuns.Adopt())
      assert.is_false(GC.AppRuns.Adopt())
      assert.equal(1, #GC.AppRuns.List())
    end)

    it("only adopts a strictly newer generatedAt than what is stored", function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      local older = fixture()
      older.generatedAt = 1
      older.runs[1].name = "should not land"
      _G.GoldCap_AppRuns = older
      assert.is_false(GC.AppRuns.Adopt())
      assert.equal("Plant Protein run", GC.AppRuns.Get("abcd2345").name)
    end)

    it("replaces every app run wholesale but keeps paste runs across Adopt", function()
      GC.db.runs["paste-1"] = { code = "paste-1", updatedAt = 5, lines = { { i = 1, q = 1 } }, origin = "paste" }
      GC.db.runs["stale-app"] = { code = "stale-app", updatedAt = 5, lines = { { i = 1, q = 1 } }, origin = "app" }
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      assert.is_not_nil(GC.AppRuns.Get("paste-1"))
      assert.is_nil(GC.AppRuns.Get("stale-app"))
      assert.is_not_nil(GC.AppRuns.Get("abcd2345"))
    end)
  end)

  describe("ImportString", function()
    it("parses a GCR1 string with a vendor flag and a URI-encoded name", function()
      local run, err = GC.AppRuns.ImportString("GCR1;myrun;Plant%20Protein;5=210,6=4=v")
      assert.is_nil(err)
      assert.equal("myrun", run.code)
      assert.equal("Plant Protein", run.name)
      assert.equal("paste", run.origin)
      assert.equal(2, #run.lines)
      assert.equal(5, run.lines[1].i)
      assert.equal(210, run.lines[1].q)
      assert.is_false(run.lines[1].v)
      assert.is_nil(run.lines[1].n)
      assert.equal(6, run.lines[2].i)
      assert.is_true(run.lines[2].v)
      -- stored into db.runs as a side effect, so it survives a later Adopt()
      assert.equal(run, GC.AppRuns.Get("myrun"))
    end)

    it("makes up a code from a hash of the line body when the code is empty", function()
      local run = GC.AppRuns.ImportString("GCR1;;;5=1")
      assert.is_not_nil(run)
      assert.is_truthy(run.code:match("^paste%-%x%x%x%x%x%x%x%x$"))
    end)

    it("rejects GCR1;;; -- no lines", function()
      local run, err = GC.AppRuns.ImportString("GCR1;;;")
      assert.is_nil(run)
      assert.equal("no_lines", err)
    end)

    it("rejects a string with no GCR1 header", function()
      local run, err = GC.AppRuns.ImportString("not a run string")
      assert.is_nil(run)
      assert.equal("bad_header", err)
    end)

    it("skips a token that does not match the line grammar", function()
      local run = GC.AppRuns.ImportString("GCR1;code;;5=210,garbage,6=4=v")
      assert.equal(2, #run.lines)
    end)
  end)
end)
