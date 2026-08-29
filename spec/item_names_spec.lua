local helper = require("spec.spec_helper")

describe("Item names for the site", function()
  local GC, db

  local function info(over)
    local i = { name = "Tuskarr Jerky", quality = 1, itemLevel = 1, minLevel = 0,
      className = "Consumable", subClassName = "Food & Drink", stackCount = 20,
      iconFileID = 1387645, sellPrice = 1250, classID = 0, subclassID = 5, bindType = 0,
      expansionID = 9 }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  before_each(function()
    GC = helper.loadModule("Core/ItemNames.lua")
    db = { itemNames = {} }
  end)

  it("records a resolved item in the SavedVariables shape", function()
    assert.is_true(GC.ItemNames.Record(db, 201421, info(), "enUS", 5000))
    assert.same({ n = "Tuskarr Jerky", l = "enUS", q = 1, il = 1, ml = 0, ct = "Consumable",
      sct = "Food & Drink", st = 20, ic = 1387645, sp = 1250, c = 0, sc = 5, b = 0, e = 9,
      at = 5000 }, db.itemNames[201421])
  end)

  it("refuses an entry without a name", function()
    -- info({ name = nil }) can't express "omit name": a Lua table constructor never
    -- materializes a key whose value is nil, so the override loop above never sees it to
    -- clear the default (same pitfall live_observations_spec.lua notes for itemID). Strip
    -- it from a built table instead.
    local noName = info()
    noName.name = nil
    assert.is_nil(GC.ItemNames.Record(db, 201421, noName, "enUS", 5000))
    assert.is_nil(db.itemNames[201421])
  end)

  it("Pending lists wanted ids that are unrecorded or stale", function()
    GC.ItemNames.Record(db, 1, info(), "enUS", 5000)
    GC.ItemNames.Record(db, 2, info(), "enUS", 5000 - GC.ItemNames.REFRESH_AFTER - 1)
    assert.same({ 2, 3 }, GC.ItemNames.Pending(db, { 1, 2, 3 }, 5000))
  end)

  it("Prune drops ids that are no longer wanted", function()
    GC.ItemNames.Record(db, 1, info(), "enUS", 5000)
    GC.ItemNames.Record(db, 2, info(), "enUS", 5000)
    GC.ItemNames.Prune(db, { 2 })
    assert.is_nil(db.itemNames[1])
    assert.is_not_nil(db.itemNames[2])
  end)

  it("Sync records what the lookup can answer and reports the rest as pending", function()
    local lookup = function(id) if id == 1 then return info() end return nil end
    local recorded, unresolved = GC.ItemNames.Sync(db, { 1, 2 }, lookup, "deDE", 5000)
    assert.equal(1, recorded)
    assert.same({ 2 }, unresolved)
    assert.equal("deDE", db.itemNames[1].l)
    assert.is_nil(db.itemNames[2])
  end)

  it("caps the table at 300 entries", function()
    local wanted = {}
    for i = 1, 305 do wanted[i] = i end
    GC.ItemNames.Sync(db, wanted, function() return info() end, "enUS", 5000)
    local n = 0
    for _ in pairs(db.itemNames) do n = n + 1 end
    assert.equal(300, n)
  end)

  it("OnItemInfoReceived records a wanted id once the client has its data", function()
    GC.ItemNames.Sync(db, { 7 }, function() return nil end, "enUS", 5000)
    GC.ItemNames.OnItemInfoReceived(db, 7, true, function() return info() end, "enUS", 5001)
    assert.equal("Tuskarr Jerky", db.itemNames[7].n)
    -- an id nobody asked for is ignored
    GC.ItemNames.OnItemInfoReceived(db, 8, true, function() return info() end, "enUS", 5001)
    assert.is_nil(db.itemNames[8])
  end)

  it("an id that lost the cap race during Sync is not recorded by a stray GET_ITEM_INFO_RECEIVED, even once a cap slot frees up", function()
    local wanted = {}
    for i = 1, 305 do wanted[i] = i end
    GC.ItemNames.Sync(db, wanted, function() return info() end, "enUS", 5000)
    -- id 301 is one of the 5 that lost the cap race: the lookup answered (successfully), so
    -- nothing about it should be left "outstanding".
    assert.is_nil(db.itemNames[301])

    -- Drop id 1 from the wanted list (freeing a cap slot) while 301 stays wanted. If the cap
    -- loss had wrongly left 301 marked "outstanding", this is exactly the setup where a
    -- stray GET_ITEM_INFO_RECEIVED could sneak it in now that the cap has room again --
    -- the cap check alone no longer protects it, only a correctly-scoped `awaiting` does.
    local stillWanted = {}
    for i = 2, 305 do stillWanted[#stillWanted + 1] = i end
    GC.ItemNames.Prune(db, stillWanted)

    GC.ItemNames.OnItemInfoReceived(db, 301, true, function() return info() end, "enUS", 5001)
    assert.is_nil(db.itemNames[301])
  end)

  it("a wanted id Prune has since dropped is not resurrected by a stray GET_ITEM_INFO_RECEIVED", function()
    GC.ItemNames.Sync(db, { 7 }, function() return nil end, "enUS", 5000)
    GC.ItemNames.Prune(db, { 8 })
    GC.ItemNames.OnItemInfoReceived(db, 7, true, function() return info() end, "enUS", 5001)
    assert.is_nil(db.itemNames[7])
  end)
end)
