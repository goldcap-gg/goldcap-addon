local helper = require("spec.spec_helper")

-- The region a ledger row carries answers "where did this transaction happen", which is a
-- fact about the CHARACTER. It used to be copied from GC.Data.GetStatus().region, which
-- answers a different question -- "whose prices am I valuing against" -- and is chosen by
-- whichever import string the player last pasted.
--
-- Observed on a live account 2026-08-28: an EU character (Meolis-Tarren Mill) imported a KR
-- snapshot, and the next mailbox scan stamped six sale rows `kr` while every buy behind them
-- stayed `eu`. The server keys FIFO lots on region|item (apps/api/src/lib/ledgerFifo.ts), so
-- the sales could never pair with their own purchases: they reported "cost unknown", the
-- positions behind them never closed, and "earned via GoldCap" collapsed to a rounding error.
describe("Ledger region", function()
  local GC, db

  local function loadCore(portal)
    _G.GetCVar = function(key) if key == "portal" then return portal end end
    _G.GoldCap_MarketData = { eu = { ts = 1000, items = {} }, kr = { ts = 1000, items = {} } }
    local ctx = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", ctx)
    helper.loadModule("Core/Data.lua", ctx)
    helper.loadModule("Core/Ledger.lua", ctx)
    local store = { settings = {} }
    ctx.db = store
    ctx.Data.Init(store)
    ctx.Ledger.Init(store)
    return ctx, store
  end

  before_each(function()
    _G.UnitName = function() return "Meolis" end
    _G.GetRealmName = function() return "Tarren Mill" end
    GC, db = loadCore("EU")
  end)

  after_each(function()
    _G.GetCVar, _G.GoldCap_MarketData, _G.UnitName, _G.GetRealmName = nil, nil, nil, nil
  end)

  describe("ClientRegion", function()
    it("reads the portal, not the imported string", function()
      GC.Data.SetImported({ region = "kr", realm = "azshara", ts = 2000, items = {} })
      assert.equal("kr", GC.Data.GetStatus().region) -- pricing still follows the import
      assert.equal("eu", GC.Data.ClientRegion())
    end)

    it("is nil -- never a guess -- when the client cannot say", function()
      local other = loadCore(nil)
      assert.is_nil(other.Data.ClientRegion())
    end)

    it("reports a mismatch between the import and the client", function()
      assert.is_nil(GC.Data.RegionMismatch())
      GC.Data.SetImported({ region = "kr", realm = "azshara", ts = 2000, items = {} })
      local mismatch = GC.Data.RegionMismatch()
      assert.equal("kr", mismatch.imported)
      assert.equal("eu", mismatch.client)
      assert.equal("azshara", mismatch.realm)
    end)
  end)

  describe("Context", function()
    it("stamps the client region even while a foreign snapshot is loaded", function()
      GC.Data.SetImported({ region = "kr", realm = "azshara", ts = 2000, items = {} })
      assert.equal("eu", GC.Ledger.Context().region)
    end)

    it("falls back to the imported region only when the client cannot say", function()
      local other = loadCore(nil)
      other.Data.SetImported({ region = "kr", realm = "azshara", ts = 2000, items = {} })
      assert.equal("kr", other.Ledger.Context().region)
    end)
  end)

  describe("RepairCharacterRegions", function()
    local function row(char, region, key, extra)
      local e = { key = key, kind = "sale", source = "mail", itemName = "Frozen Orb", qty = 1,
        total = 100, cut = 0, deposit = 0, pending = false, at = 900000, char = char, region = region }
      for k, v in pairs(extra or {}) do e[k] = v end
      return e
    end

    it("moves a character's minority rows onto the region it really plays in", function()
      db.ledger = {
        row("Meolis-Tarren Mill", "eu", "a"), row("Meolis-Tarren Mill", "eu", "b"),
        row("Meolis-Tarren Mill", "eu", "c"), row("Meolis-Tarren Mill", "kr", "d", { uploaded = true }),
      }
      local repaired = GC.Ledger.RepairCharacterRegions()
      assert.equal(1, #repaired)
      assert.equal("d", repaired[1].key)
      assert.equal("eu", db.ledger[4].region)
      -- The stored copy on the server still says kr, so it has to go up again.
      assert.is_nil(db.ledger[4].uploaded)
    end)

    it("leaves a character whose rows all agree alone", function()
      db.ledger = { row("Solo-Azshara", "kr", "a"), row("Solo-Azshara", "kr", "b") }
      assert.equal(0, #GC.Ledger.RepairCharacterRegions())
      assert.equal("kr", db.ledger[1].region)
    end)

    it("judges each character on its own rows", function()
      db.ledger = {
        row("Meolis-Tarren Mill", "eu", "a"), row("Meolis-Tarren Mill", "eu", "b"),
        row("Meolis-Tarren Mill", "kr", "c"),
        row("Hana-Azshara", "kr", "d"), row("Hana-Azshara", "kr", "e"),
      }
      GC.Ledger.RepairCharacterRegions()
      assert.equal("eu", db.ledger[3].region)
      assert.equal("kr", db.ledger[4].region)
      assert.equal("kr", db.ledger[5].region)
    end)

    it("refuses to guess on a tie", function()
      db.ledger = { row("Meolis-Tarren Mill", "eu", "a"), row("Meolis-Tarren Mill", "kr", "b") }
      assert.equal(0, #GC.Ledger.RepairCharacterRegions())
      assert.equal("kr", db.ledger[2].region)
    end)

    it("breaks a tie for the character at the keyboard with the live client region", function()
      db.ledger = { row("Meolis-Tarren Mill", "eu", "a"), row("Meolis-Tarren Mill", "kr", "b") }
      local repaired = GC.Ledger.RepairCharacterRegions("Meolis-Tarren Mill", "eu")
      assert.equal(1, #repaired)
      assert.equal("eu", db.ledger[2].region)
    end)

    it("ignores rows with no character or no region -- nothing to vote on", function()
      db.ledger = { row(nil, "eu", "a"), row("Meolis-Tarren Mill", nil, "b"),
        row("Meolis-Tarren Mill", "eu", "c"), row("Meolis-Tarren Mill", "eu", "d") }
      assert.equal(0, #GC.Ledger.RepairCharacterRegions())
      assert.is_nil(db.ledger[2].region)
    end)
  end)
end)
