local helper = require("spec.spec_helper")

describe("QuoteCache", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/QuoteCache.lua")
  end)

  it("keeps a quote at ten seconds fresh and retains it for display at eleven", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)

    assert.equal(12345, GC.QuoteCache.Get(cache, 42, 110))
    assert.is_nil(GC.QuoteCache.Get(cache, 42, 111))
    assert.equal(12345, GC.QuoteCache.Latest(cache, 42).unit)
    assert.is_nil(GC.QuoteCache.Fresh(cache, 42, 111))
    assert.equal(11, GC.QuoteCache.Age(cache, 42, 111))
  end)

  it("keeps an eleven-second quote for display but not action", function()
    local cache = {}
    GC.QuoteCache.Set(cache, "commodity:42", 12345, 100)

    assert.equal(12345, GC.QuoteCache.Latest(cache, "commodity:42").unit)
    assert.is_nil(GC.QuoteCache.Fresh(cache, "commodity:42", 111))
    assert.equal(11, GC.QuoteCache.Age(cache, "commodity:42", 111))
  end)

  it("rejects a future quote age", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)

    assert.is_nil(GC.QuoteCache.Age(cache, 42, 99))
  end)

  it("fails closed without mutating malformed, future, or explicitly stale entries", function()
    local max, nan = 9007199254740991, 0 / 0
    local cases = {
      { "scalar", 12345, 100, nil },
      { "zero unit", { unit = 0, at = 100 }, 100, nil },
      { "fractional unit", { unit = 12.5, at = 100 }, 100, nil },
      { "NaN unit", { unit = nan, at = 100 }, 100, nil },
      { "unsafe unit", { unit = max + 1, at = 100 }, 100, nil },
      { "string timestamp", { unit = 12345, at = "100" }, 100, nil },
      { "fractional timestamp", { unit = 12345, at = 100.5 }, 100, nil },
      { "negative timestamp", { unit = 12345, at = -1 }, 100, nil },
      { "unsafe timestamp", { unit = 12345, at = max + 1 }, 100, nil },
      { "future timestamp", { unit = 12345, at = 101 }, 100, nil },
      { "invalid now", { unit = 12345, at = 100 }, "100", nil },
      { "fractional now", { unit = 12345, at = 100 }, 100.5, nil },
      { "negative now", { unit = 12345, at = 100 }, -1, nil },
      { "unsafe now", { unit = 12345, at = 100 }, max + 1, nil },
      { "NaN now", { unit = 12345, at = 100 }, nan, nil },
      { "stale marker", { unit = 12345, at = 100, stale = true }, 100, 0 },
      { "fresh false marker", { unit = 12345, at = 100, fresh = false }, 100, 0 },
      { "contradictory markers", { unit = 12345, at = 100, fresh = true, stale = true }, 100, 0 },
    }

    for _, case in ipairs(cases) do
      local cache = { [42] = case[2] }
      local ok, fresh = pcall(GC.QuoteCache.Fresh, cache, 42, case[3])
      assert.is_true(ok, case[1])
      assert.is_nil(fresh, case[1])
      assert.equal(case[4], GC.QuoteCache.Age(cache, 42, case[3]), case[1])
      assert.equal(case[2], GC.QuoteCache.Latest(cache, 42), case[1])
    end
  end)

  it("deletes an old quote when a result has no unit price", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)
    GC.QuoteCache.Set(cache, 42, nil, 101)

    assert.is_nil(GC.QuoteCache.Get(cache, 42, 101))
    assert.is_nil(cache[42])
  end)

  it("replaces a quote with the newest result", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)
    GC.QuoteCache.Set(cache, 42, 23456, 105)

    assert.equal(23456, GC.QuoteCache.Get(cache, 42, 115))
  end)

  it("expires one item without clearing a newer quote for another item", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)
    GC.QuoteCache.Set(cache, 99, 54321, 105)

    assert.is_nil(GC.QuoteCache.Get(cache, 42, 111))
    assert.equal(12345, GC.QuoteCache.Latest(cache, 42).unit)
    assert.equal(54321, GC.QuoteCache.Get(cache, 99, 111))
  end)

  it("clears every quote", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)
    GC.QuoteCache.Set(cache, 99, 54321, 100)
    GC.QuoteCache.Clear(cache)

    assert.is_nil(GC.QuoteCache.Get(cache, 42, 100))
    assert.is_nil(GC.QuoteCache.Get(cache, 99, 100))
  end)
end)
