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
    GC.db = { runs = {}, runsArchived = {}, runSplits = {}, runNotices = {},
              runsMeta = { plan = "free", freeLines = 5, generatedAt = 0 } }
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

    it("refuses any version but 1, 2 or 3, silently", function()
      local f = fixture(); f.v = 4
      _G.GoldCap_AppRuns = f
      assert.has_no.errors(function() assert.is_false(GC.AppRuns.Adopt()) end)
      assert.is_nil(GC.AppRuns.Get("abcd2345"))
    end)

    -- v2 is the same file with prices on the lines: the site's own reference price at fetch
    -- time, the vendor's price, and the hour the item is usually cheapest.
    it("adopts a v2 file and keeps every price the lines carry", function()
      local f = fixture()
      f.v = 2
      f.runs[1].lines[1].u = 45000
      f.runs[1].lines[1].ch = 3
      f.runs[1].lines[1].cp = -18
      f.runs[1].lines[2].vu = 25
      _G.GoldCap_AppRuns = f
      assert.is_true(GC.AppRuns.Adopt())
      local run = GC.AppRuns.Get("abcd2345")
      assert.equal(45000, run.lines[1].u)
      assert.equal(3, run.lines[1].ch)
      assert.equal(-18, run.lines[1].cp)
      assert.equal(25, run.lines[2].vu)
    end)

    -- v3 is the same file again: a line may bring an absolute cap (an alert's own target
    -- price), the realm a hit was seen on, and the recipe that crafts it.
    it("adopts a v3 file and keeps the cap, the realm and the recipe a line carries", function()
      local f = fixture()
      f.v = 3
      f.runs[1].lines[1].cc = 9990000
      f.runs[1].lines[1].rl = { id = 1305, n = "Kazzak" }
      f.runs[1].lines[1].cr = { r = 900, n = 5, c = 2300, i = {
        { i = 51, q = 5, n = "Eversong Trout", u = 300 },
        { i = 52, q = 5, n = "Tavern Fixings", v = true, vu = 150 },
      } }
      _G.GoldCap_AppRuns = f
      assert.is_true(GC.AppRuns.Adopt())
      local line = GC.AppRuns.Get("abcd2345").lines[1]
      assert.equal(9990000, line.cc)
      assert.same({ id = 1305, n = "Kazzak" }, line.rl)
      assert.equal(900, line.cr.r)
      assert.equal(5, line.cr.n)
      assert.equal(2300, line.cr.c)
      assert.equal(2, #line.cr.i)
      assert.equal(51, line.cr.i[1].i)
      assert.equal("Eversong Trout", line.cr.i[1].n)
      assert.equal(300, line.cr.i[1].u)
      assert.is_false(line.cr.i[1].v)
      assert.is_true(line.cr.i[2].v)
      assert.equal(150, line.cr.i[2].vu)
    end)

    -- The companion's global is rewritten wholesale on every sync, and a run kept in
    -- SavedVariables outlives it. A reference into that table would have the stored run change
    -- under the player -- or, worse, be written back out through it.
    it("deep-copies the recipe rather than pointing at the companion's own table", function()
      local f = fixture()
      f.v = 3
      f.runs[1].lines[1].cr = { r = 900, n = 5, c = 2300, i = { { i = 51, q = 5 } } }
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      local stored = GC.AppRuns.Get("abcd2345").lines[1].cr
      assert.are_not.equal(f.runs[1].lines[1].cr, stored)
      assert.are_not.equal(f.runs[1].lines[1].cr.i[1], stored.i[1])
      f.runs[1].lines[1].cr.i[1].q = 999
      assert.equal(5, stored.i[1].q)
    end)

    -- A recipe that yields nothing, or lists no reagent, is not something the tab can act on.
    it("drops a recipe with no reagents and keeps the line", function()
      local f = fixture()
      f.v = 3
      f.runs[1].lines[1].cr = { r = 900, n = 5, c = 2300, i = {} }
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      local line = GC.AppRuns.Get("abcd2345").lines[1]
      assert.is_nil(line.cr)
      assert.equal(210, line.q)
    end)

    it("keeps the run's kind, its owner's name and its source label", function()
      local f = fixture()
      f.v = 3
      f.runs[1].k = "alert"
      f.runs[1].by = "Acromion"
      f.runs[1].src = "Cooking 1-100"
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      local run = GC.AppRuns.Get("abcd2345")
      assert.equal("alert", run.k)
      assert.equal("Acromion", run.by)
      assert.equal("Cooking 1-100", run.src)
    end)

    it("leaves a v2 run's kind, owner and source unset rather than inventing them", function()
      local f = fixture(); f.v = 2
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      local run = GC.AppRuns.Get("abcd2345")
      assert.is_nil(run.k)
      assert.is_nil(run.by)
      assert.is_nil(run.src)
    end)

    -- A companion that has not been updated writes v1, which is a v2 file with no prices on it.
    it("still adopts a v1 file, whose lines simply carry none", function()
      _G.GoldCap_AppRuns = fixture()
      assert.is_true(GC.AppRuns.Adopt())
      local run = GC.AppRuns.Get("abcd2345")
      assert.is_nil(run.lines[1].u)
      assert.is_nil(run.lines[1].vu)
      assert.is_nil(run.lines[1].ch)
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

    -- Core/BuyRun.lua keys its purchase state by item id, so two lines of the same item share one
    -- `bought`: buying the first marked the second done, and the second line's quantity could
    -- never be bought at all. Two recipes on one shopping list produce this constantly.
    it("merges duplicate item ids into one line, summing the quantity", function()
      local f = fixture()
      table.insert(f.runs[1].lines, { i = 5, q = 15, v = false })
      table.insert(f.runs[1].lines, { i = 5, q = 5, v = true }) -- a later duplicate may not vendor it
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      local run = GC.AppRuns.Get("abcd2345")
      assert.equal(2, #run.lines)
      assert.equal(5, run.lines[1].i)
      assert.equal(230, run.lines[1].q) -- 210 + 15 + 5
      assert.is_false(run.lines[1].v)
      assert.equal("Plant Protein", run.lines[1].n) -- the first line keeps name and position
      assert.equal(6, run.lines[2].i)
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

    -- A run the site deleted takes its per-run settings with it: nothing else would ever clear
    -- them, and a code the site later reuses would come back carrying somebody else's cap.
    it("forgets the cap of a run the site no longer sends", function()
      GC.db.runCaps = { ["abcd2345"] = 150, ["gone-run"] = 200 }
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      assert.equal(150, GC.db.runCaps["abcd2345"])
      assert.is_nil(GC.db.runCaps["gone-run"])
    end)

    -- The site can recompute a saved plan at today's prices, which rewrites the run's lines
    -- under a code the addon already has. The band says so for a day, so a run that changed
    -- shape while the player was not looking is not something they discover by miscounting.
    it("notices a run that comes back with different lines", function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      assert.is_nil(GC.db.runNotices["abcd2345"])

      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60
      fresher.runs[1].updatedAt = 200
      table.remove(fresher.runs[1].lines, 2)              -- the vendor line is gone
      table.insert(fresher.runs[1].lines, { i = 7, q = 3 })
      table.insert(fresher.runs[1].lines, { i = 8, q = 9 })
      _G.GoldCap_AppRuns = fresher
      assert.is_true(GC.AppRuns.Adopt())

      local notice = GC.db.runNotices["abcd2345"]
      assert.is_table(notice)
      assert.equal(2, notice.added)
      assert.equal(1, notice.removed)
      assert.is_number(notice.at)
    end)

    -- A quantity that moved is a changed plan too, and there is nothing to count: the band has
    -- a wording of its own for it (UI/BuyFrame.lua).
    it("notices a quantity that moved, with nothing added or removed", function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60
      fresher.runs[1].updatedAt = 200
      fresher.runs[1].lines[1].q = 400
      _G.GoldCap_AppRuns = fresher
      GC.AppRuns.Adopt()
      assert.same({ added = 0, removed = 0 }, { added = GC.db.runNotices["abcd2345"].added,
                                                removed = GC.db.runNotices["abcd2345"].removed })
    end)

    -- A sync that brought the same run again is not news. Both halves have to differ: a file
    -- regenerated on a timer carries a new generatedAt and the very same run.
    it("says nothing when the run came back the same", function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60
      fresher.runs[1].updatedAt = 200          -- newer stamp, identical lines
      _G.GoldCap_AppRuns = fresher
      GC.AppRuns.Adopt()
      assert.is_nil(GC.db.runNotices["abcd2345"])
    end)

    -- The other half of the same rule: `updatedAt` is the site's own stamp on the plan, and a
    -- line set cannot move without it moving too. Lines that differ under an unchanged stamp are
    -- a file the addon cannot explain -- not a recompute the band should announce as one.
    it("says nothing when the lines differ under an unchanged updatedAt", function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60    -- a newer file...
      table.insert(fresher.runs[1].lines, { i = 7, q = 3 })   -- ...carrying a changed run
      _G.GoldCap_AppRuns = fresher
      assert.is_true(GC.AppRuns.Adopt())
      assert.equal(3, #GC.AppRuns.Get("abcd2345").lines)
      assert.is_nil(GC.db.runNotices["abcd2345"])
    end)

    it("says nothing about a run it is seeing for the first time", function()
      local f = fixture()
      f.runs[1].code = "wxyz6789"
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      assert.is_nil(GC.db.runNotices["wxyz6789"])
    end)

    -- An alert run's lines ARE the alert group's live hits, so they change on essentially every
    -- sync by design -- that is not a plan that changed, it is the run doing what it is for. The
    -- band has its own wording for an alert run (hit count), so Adopt must not also write a notice.
    it("says nothing about an alert run whose hits changed shape", function()
      local f = fixture()
      f.v = 3
      f.runs[1].k = "alert"
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      local fresher = fixture()
      fresher.v = 3
      fresher.runs[1].k = "alert"
      fresher.generatedAt = fresher.generatedAt + 60
      fresher.runs[1].updatedAt = 200
      table.remove(fresher.runs[1].lines, 2)
      table.insert(fresher.runs[1].lines, { i = 7, q = 3 })
      table.insert(fresher.runs[1].lines, { i = 8, q = 9 })
      _G.GoldCap_AppRuns = fresher
      GC.AppRuns.Adopt()
      assert.is_nil(GC.db.runNotices["abcd2345"])
    end)
    -- An alert run's lines ARE the group's live hits. A hit that expired is gone, and a later
    -- hit for the same item is a different lot at a different price -- so what was bought
    -- against the old one is not a score the new one inherits. Nothing else ever prunes
    -- buyProgress: it is keyed by the run code, and an alert group's code does not change.
    it("forgets what was bought for an alert hit that has expired", function()
      local f = fixture()
      f.v = 3
      f.runs[1].k = "alert"
      _G.GoldCap_AppRuns = f
      GC.AppRuns.Adopt()
      GC.db.buyProgress = {
        ["Tester-Realm"] = { ["abcd2345"] = { [5] = { bought = 60, spent = 900 },
                                              [6] = { bought = 4, spent = 40 } } },
        ["Alt-Realm"] = { ["abcd2345"] = { [6] = { bought = 1, spent = 10 } } },
      }

      local fresher = fixture()
      fresher.v = 3
      fresher.runs[1].k = "alert"
      fresher.generatedAt = fresher.generatedAt + 60
      table.remove(fresher.runs[1].lines, 2)          -- item 6's hit is no longer on the run
      _G.GoldCap_AppRuns = fresher
      assert.is_true(GC.AppRuns.Adopt())

      local mine = GC.db.buyProgress["Tester-Realm"]["abcd2345"]
      assert.is_nil(mine[6])
      assert.equal(60, mine[5].bought)                -- the hit still on the run keeps its score
      -- The score is per character, but the hit expired for every one of them at once.
      assert.is_nil(GC.db.buyProgress["Alt-Realm"]["abcd2345"][6])
    end)

    -- A saved list is a plan, not a set of live hits: a line the site recomputed away is one the
    -- player may put back tomorrow, and the gold this run already spent on it is still spent.
    it("leaves a list run's progress alone when a line goes", function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      GC.db.buyProgress = { ["Tester-Realm"] = { ["abcd2345"] = {
        [5] = { bought = 60, spent = 900 }, [6] = { bought = 4, spent = 40 } } } }

      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60
      table.remove(fresher.runs[1].lines, 2)
      _G.GoldCap_AppRuns = fresher
      GC.AppRuns.Adopt()
      assert.equal(4, GC.db.buyProgress["Tester-Realm"]["abcd2345"][6].bought)
    end)
  end)

  describe("archiving", function()
    before_each(function()
      _G.GoldCap_AppRuns = fixture()
      GC.AppRuns.Adopt()
      GC.db.runs["paste-1"] = { code = "paste-1", updatedAt = 5,
                                lines = { { i = 1, q = 1 } }, origin = "paste" }
    end)

    it("takes an archived run out of the list and offers it under archived instead", function()
      assert.equal(2, #GC.AppRuns.List())
      assert.is_true(GC.AppRuns.SetArchived("abcd2345", true))
      assert.is_true(GC.AppRuns.IsArchived("abcd2345"))

      local live = GC.AppRuns.List()
      assert.equal(1, #live)
      assert.equal("paste-1", live[1].code)

      local archived = GC.AppRuns.List({ archived = true })
      assert.equal(1, #archived)
      assert.equal("abcd2345", archived[1].code)

      -- Restoring is the same call the other way, and the run is back where it was.
      GC.AppRuns.SetArchived("abcd2345", false)
      assert.is_false(GC.AppRuns.IsArchived("abcd2345"))
      assert.equal(2, #GC.AppRuns.List())
      assert.equal(0, #GC.AppRuns.List({ archived = true }))
    end)

    -- Adopt replaces every app run wholesale; the flag lives beside them, not on them, so a
    -- companion sync must not hand a finished run back to the picker.
    it("keeps the flag across a companion sync", function()
      GC.AppRuns.SetArchived("abcd2345", true)
      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60
      _G.GoldCap_AppRuns = fresher
      assert.is_true(GC.AppRuns.Adopt())
      assert.is_true(GC.AppRuns.IsArchived("abcd2345"))
      assert.equal(1, #GC.AppRuns.List())
    end)

    it("forgets the flag of a run the site no longer sends", function()
      GC.AppRuns.SetArchived("abcd2345", true)
      local fresher = fixture()
      fresher.generatedAt = fresher.generatedAt + 60
      fresher.runs[1].code = "wxyz6789"
      _G.GoldCap_AppRuns = fresher
      GC.AppRuns.Adopt()
      assert.is_false(GC.AppRuns.IsArchived("abcd2345"))
      assert.is_nil(GC.db.runsArchived["abcd2345"])
    end)

    -- Removal takes everything stored beside the run with it -- the archived flag and the cap
    -- alike, since nothing else would ever clear either.
    -- Pasting a run whose code was archived is the player asking for it back: it comes back
    -- live, not straight into the Archived section.
    it("un-archives a run that is pasted again", function()
      GC.AppRuns.ImportString("GCR1;abcd2345;Cooking;5=210")
      GC.AppRuns.SetArchived("abcd2345", true)
      assert.is_true(GC.AppRuns.IsArchived("abcd2345"))
      GC.AppRuns.ImportString("GCR1;abcd2345;Cooking;5=300")
      assert.is_false(GC.AppRuns.IsArchived("abcd2345"))
      assert.equal(300, GC.AppRuns.Get("abcd2345").lines[1].q)
    end)

    it("forgets the flag of a run that is removed outright", function()
      GC.AppRuns.SetArchived("paste-1", true)
      GC.db.runCaps = { ["paste-1"] = 150 }
      assert.is_true(GC.AppRuns.Remove("paste-1"))
      assert.is_nil(GC.db.runsArchived["paste-1"])
      assert.is_nil(GC.db.runCaps["paste-1"])
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

    it("skips suffixes a newer site writes after the quantity, still reading =v", function()
      local run = GC.AppRuns.ImportString("GCR1;abcd2345;Cooking;2589=20@450,159=5=v~25,7=3~9=v")
      assert.same({ { i = 2589, q = 20, v = false }, { i = 159, q = 5, v = true }, { i = 7, q = 3, v = true } },
        { { i = run.lines[1].i, q = run.lines[1].q, v = run.lines[1].v },
          { i = run.lines[2].i, q = run.lines[2].q, v = run.lines[2].v },
          { i = run.lines[3].i, q = run.lines[3].q, v = run.lines[3].v } })
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

    -- Same merge Adopt does, for the same reason: a pasted string can name one item twice too.
    it("merges duplicate item ids into one line, summing the quantity", function()
      local run = GC.AppRuns.ImportString("GCR1;code;;5=210,6=4=v,5=15")
      assert.equal(2, #run.lines)
      assert.equal(5, run.lines[1].i)
      assert.equal(225, run.lines[1].q)
      assert.equal(6, run.lines[2].i)
    end)

    -- `<id>=<qty>` then suffixes in any order: `=v` a vendor stop, `@n` the site's usual unit
    -- price, `~n` the vendor's. A paste carries prices so it is not a second-class run.
    it("reads the usual price and the vendor price off a line, in any order", function()
      local run = GC.AppRuns.ImportString("GCR1;abcd2345;Cooking%201-100;2589=20@450,159=5=v~25,77=2~30@900")
      assert.equal(3, #run.lines)
      assert.equal(450, run.lines[1].u)
      assert.is_nil(run.lines[1].vu)
      assert.is_false(run.lines[1].v)
      assert.is_true(run.lines[2].v)
      assert.equal(25, run.lines[2].vu)
      assert.equal(30, run.lines[3].vu)
      assert.equal(900, run.lines[3].u)
    end)

    it("drops a token whose suffix is neither a price nor the vendor flag", function()
      local run = GC.AppRuns.ImportString("GCR1;code;;5=210,6=4=x,7=1@,8=2@30")
      assert.equal(2, #run.lines)
      assert.equal(5, run.lines[1].i)
      assert.equal(8, run.lines[2].i)
    end)
  end)
end)

describe("AppRuns runs the site owns", function()
  local GC

  -- Three app runs of the three kinds, plus a pasted one, all live at once -- which is exactly
  -- what the picker has to order.
  local function fixture()
    return {
      v = 3, generatedAt = 1787130262, plan = "pro", freeLines = 5,
      runs = {
        { code = "own10000", name = "Mine, older", updatedAt = 100,
          lines = { { i = 5, q = 1 } } },
        { code = "own20000", name = "Mine, newer", updatedAt = 200,
          lines = { { i = 6, q = 1 } } },
        { code = "shr30000", name = "Guild flasks", updatedAt = 300, by = "Acromion",
          lines = { { i = 7, q = 1 } } },
        { code = "a0000001", name = "Cheap ore", updatedAt = 400, k = "alert",
          lines = { { i = 8, q = 1, cc = 9990000 } } },
      },
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/AppRuns.lua", GC)
    GC.db = { runs = {}, runsArchived = {}, runSplits = {}, runNotices = {},
              runsMeta = { plan = "free", freeLines = 5, generatedAt = 0 } }
    _G.GoldCap_AppRuns = fixture()
    GC.AppRuns.Adopt()
    GC.db.runs["paste-1"] = { code = "paste-1", updatedAt = 500,
                              lines = { { i = 9, q = 1 } }, origin = "paste" }
  end)

  after_each(function() _G.GoldCap_AppRuns = nil end)

  it("tells an alert run and a followed run from an ordinary one", function()
    assert.is_true(GC.AppRuns.IsAlert("a0000001"))
    assert.is_false(GC.AppRuns.IsAlert("shr30000"))
    assert.is_false(GC.AppRuns.IsAlert("nosuchrun"))
    assert.is_true(GC.AppRuns.IsShared("shr30000"))
    assert.is_false(GC.AppRuns.IsShared("own10000"))
    assert.is_false(GC.AppRuns.IsShared("a0000001"))
  end)

  -- The picker reads top to bottom as "your lists, then the ones you follow, then what you
  -- pasted, then what your alerts have found" -- and a run of somebody else's must never be
  -- what a first visit lands on (UI/BuyFrame.lua's ensureRun takes the first).
  it("orders the list own, then followed, then pasted, then alert", function()
    local codes = {}
    for _, run in ipairs(GC.AppRuns.List()) do codes[#codes + 1] = run.code end
    assert.same({ "own20000", "own10000", "shr30000", "paste-1", "a0000001" }, codes)
  end)

  it("refuses to archive an alert or a followed run, and archives an own one", function()
    assert.is_false(GC.AppRuns.SetArchived("a0000001", true))
    assert.is_false(GC.AppRuns.SetArchived("shr30000", true))
    assert.is_nil(GC.db.runsArchived["a0000001"])
    assert.is_nil(GC.db.runsArchived["shr30000"])
    assert.is_true(GC.AppRuns.SetArchived("own10000", true))
    assert.is_true(GC.AppRuns.IsArchived("own10000"))
    -- Clearing a flag is always allowed: one left in SavedVariables by an older build has to
    -- have a way out.
    GC.db.runsArchived["a0000001"] = true
    assert.is_true(GC.AppRuns.SetArchived("a0000001", false))
    assert.is_nil(GC.db.runsArchived["a0000001"])
  end)

  it("refuses to remove an alert or a followed run", function()
    assert.is_false(GC.AppRuns.Remove("a0000001"))
    assert.is_false(GC.AppRuns.Remove("shr30000"))
    assert.is_not_nil(GC.AppRuns.Get("a0000001"))
    assert.is_true(GC.AppRuns.Remove("paste-1"))
  end)

  -- Every per-run store is pruned by the same rule, or a code the site later reuses comes back
  -- carrying a split, a notice or a cap nobody chose for it.
  it("forgets the splits and the notice of a run the site no longer sends", function()
    GC.db.runSplits = { ["own10000"] = { [5] = true }, ["gone-run"] = { [1] = true } }
    GC.db.runNotices = { ["own10000"] = { at = 1, added = 1, removed = 0 },
                         ["gone-run"] = { at = 1, added = 1, removed = 0 } }
    local fresher = fixture()
    fresher.generatedAt = fresher.generatedAt + 60
    _G.GoldCap_AppRuns = fresher
    assert.is_true(GC.AppRuns.Adopt())
    assert.is_not_nil(GC.db.runSplits["own10000"])
    assert.is_nil(GC.db.runSplits["gone-run"])
    assert.is_not_nil(GC.db.runNotices["own10000"])
    assert.is_nil(GC.db.runNotices["gone-run"])
  end)

  it("takes the splits and the notice with a run that is removed outright", function()
    GC.db.runSplits["paste-1"] = { [9] = true }
    GC.db.runNotices["paste-1"] = { at = 1, added = 0, removed = 1 }
    assert.is_true(GC.AppRuns.Remove("paste-1"))
    assert.is_nil(GC.db.runSplits["paste-1"])
    assert.is_nil(GC.db.runNotices["paste-1"])
  end)
end)
