local helper = require("spec.spec_helper")

describe("QuoteCache", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/QuoteCache.lua")
  end)

  it("keeps a quote at ten seconds and expires it at eleven", function()
    local cache = {}
    GC.QuoteCache.Set(cache, 42, 12345, 100)

    assert.equal(12345, GC.QuoteCache.Get(cache, 42, 110))
    assert.is_nil(GC.QuoteCache.Get(cache, 42, 111))
    assert.is_nil(cache[42])
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
