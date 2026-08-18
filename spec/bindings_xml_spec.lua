require("spec.spec_helper")

-- GoldCap/Bindings.xml shipped to the live client malformed and the client rejected the whole
-- file on load: "Bindings.xml(3:31): error: not well-formed (invalid token)". The cause was a
-- Lua habit in an XML file -- a double hyphen inside an XML comment, which XML forbids outright.
-- The keybinding silently never registered and the player got a Lua Warning at login.
--
-- Nothing in the suite could have caught it. busted has no XML parser, and the one spec that
-- read this file read it as TEXT, to check it contained no protected call names -- a file can
-- pass that and still be unparseable. These checks are deliberately narrow and syntactic: they
-- cover the specific ways a hand-written Bindings.xml actually breaks, rather than pretending to
-- be a validator Lua cannot provide.
describe("Bindings.xml", function()
  local function source()
    local file = assert(io.open("GoldCap/Bindings.xml", "r"), "GoldCap/Bindings.xml is missing")
    local text = file:read("*a")
    file:close()
    return text
  end

  -- The one that bit. XML says a comment may not contain "--" anywhere, not even in prose.
  it("has no double hyphen inside an XML comment", function()
    local text = source()
    local from = 1
    while true do
      local open, afterOpen = text:find("<!%-%-", from)
      if not open then break end
      local close = text:find("%-%->", afterOpen + 1)
      assert.is_not_nil(close, "an XML comment is never closed")
      local body = text:sub(afterOpen + 1, close - 1)
      assert.is_nil(body:find("%-%-"),
        "an XML comment contains '--', which XML forbids: the client rejects the whole file " ..
        "and the keybinding never registers. Write it without the double hyphen.")
      from = close + 3
    end
  end)

  -- A Binding's body is character data, so a bare < or & is just as fatal as the comment was.
  it("has no unescaped < or & in a Binding body", function()
    local text = source()
    -- `<Binding%s`, not `<Binding`: the latter also matches the root `<Bindings>` element, whose
    -- "body" is every child tag and therefore always contains a `<`.
    for body in text:gmatch("<Binding%s[^>]*>(.-)</Binding>") do
      assert.is_nil(body:find("<"), "a Binding body contains a raw '<' -- escape it as &lt;")
      assert.is_nil(body:find("&[^;]"), "a Binding body contains a raw '&' -- escape it as &amp;")
    end
  end)

  it("declares at least one binding, with a name and a header", function()
    local text = source()
    local found = 0
    for attrs in text:gmatch("<Binding%s([^>]*)>") do
      assert.is_not_nil(attrs:find('name="'), "a Binding has no name attribute")
      assert.is_not_nil(attrs:find('header="'), "a Binding has no header attribute")
      found = found + 1
    end
    assert.is_true(found > 0, "Bindings.xml declares no bindings at all")
  end)

  -- The design forbids reaching the post through Button:Click(), which would carry this chunk's
  -- taint into a protected call. The binding must call the same function the button's OnClick
  -- calls, and UI/SellFrame.lua must actually publish it under that name.
  it("calls the published function, never a button's Click method", function()
    local text = source()
    -- Plain find, not a pattern: an unescaped `(` would open a capture group and error out.
    assert.is_nil(text:find(":Click(", 1, true),
      "Bindings.xml calls Click() -- see the design's keybinding section for why that is wrong")
    assert.is_not_nil(text:find("GoldCapSniperFrame.GoldCapPostNext", 1, true))

    local file = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
    local lua = file:read("*a")
    file:close()
    assert.is_not_nil(lua:find("GoldCapPostNext", 1, true),
      "Bindings.xml calls GoldCapPostNext but UI/SellFrame.lua never assigns it")
  end)
end)
