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

  -- A header opens a group in the client's Keybindings list and the bindings after it stand under
  -- it until the next header, as Blizzard's own files write it (live
  -- Blizzard_Commentator/Bindings.xml:7-10: COMMENTATORMOVESPEEDINCREASE carries
  -- header="COMMENTATORCAMERA", the bindings after it none). So the first binding names GOLDCAP's
  -- header and every binding has a name.
  it("declares at least one binding, each with a name, the first under GoldCap's header", function()
    local text = source()
    local found = 0
    for attrs in text:gmatch("<Binding%s([^>]*)>") do
      assert.is_not_nil(attrs:find('name="'), "a Binding has no name attribute")
      found = found + 1
      if found == 1 then
        assert.is_not_nil(attrs:find('header="GOLDCAP"', 1, true), "the first Binding opens no GOLDCAP header")
      end
    end
    assert.is_true(found > 0, "Bindings.xml declares no bindings at all")
  end)

  -- The Disenchant window's key: a CLICK binding, which hands the key to the secure button itself
  -- (its press and release as clicks), so the cast is the button's own and no Lua of ours runs in
  -- the binding. Its body stays empty, and UI/DisenchantFrame.lua must create the button by that
  -- global name, or the binding points at nothing.
  it("binds a key to the Disenchant button by a CLICK binding with no code of its own", function()
    local text = source()
    local body = text:match('<Binding%s+name="CLICK GoldCapDisenchantNext:LeftButton"%s*>(.-)</Binding>')
    assert.is_not_nil(body, "Bindings.xml has no CLICK GoldCapDisenchantNext:LeftButton binding")
    assert.is_nil(body:find("%S"), "the CLICK binding carries code: the click is the button's own")

    local file = assert(io.open("GoldCap/UI/DisenchantFrame.lua", "r"))
    local lua = file:read("*a")
    file:close()
    assert.is_not_nil(lua:find('DF.BUTTON = "GoldCapDisenchantNext"', 1, true),
      "UI/DisenchantFrame.lua does not name its button GoldCapDisenchantNext")
    assert.is_not_nil(lua:find('CreateFrame("Button", DF.BUTTON, card, "SecureActionButtonTemplate")', 1, true),
      "UI/DisenchantFrame.lua does not create GoldCapDisenchantNext from SecureActionButtonTemplate")
  end)

  -- The design forbids reaching the post through Button:Click(), which would carry this chunk's
  -- taint into a protected call. The binding must call the same function the button's OnClick
  -- calls, and UI/Sell/Dock.lua must actually publish it under that name.
  it("calls the published function, never a button's Click method", function()
    local text = source()
    -- Plain find, not a pattern: an unescaped `(` would open a capture group and error out.
    assert.is_nil(text:find(":Click(", 1, true),
      "Bindings.xml calls Click() -- see the design's keybinding section for why that is wrong")
    assert.is_not_nil(text:find("GoldCapSniperFrame.GoldCapPostNext", 1, true))

    local file = assert(io.open("GoldCap/UI/Sell/Dock.lua", "r"))
    local lua = file:read("*a")
    file:close()
    assert.is_not_nil(lua:find("GoldCapPostNext", 1, true),
      "Bindings.xml calls GoldCapPostNext but UI/Sell/Dock.lua never assigns it")
  end)
end)

-- WoW Forever ships its own bindings file by the flavor's suffix (Forever's Blizzard_FrameXML holds
-- Bindings_Camelot.xml where retail's holds Bindings_Standard.xml), and GoldCap_Camelot.toc loads no
-- Disenchant window: there the CLICK binding would stand as a raw line in Key Bindings with nothing
-- behind it (the final review's M1). Bindings_Camelot.xml is Bindings.xml without it. Whether the
-- client reads an addon's flavor-suffixed bindings file in place of Bindings.xml is not measured.
describe("Bindings_Camelot.xml", function()
  local function read(path)
    local file = assert(io.open(path, "r"), path .. " is missing")
    local text = file:read("*a")
    file:close()
    return text
  end
  local function bindings(text)
    local out = {}
    for attrs, body in text:gmatch("<Binding%s([^>]*)>(.-)</Binding>") do
      out[#out + 1] = { attrs = attrs, body = body }
    end
    return out
  end

  it("has no double hyphen inside an XML comment", function()
    local text = read("GoldCap/Bindings_Camelot.xml")
    for body in text:gmatch("<!%-%-(.-)%-%->") do
      assert.is_nil(body:find("%-%-"), "an XML comment contains '--', which XML forbids")
    end
  end)

  it("is Bindings.xml without the Disenchant window's CLICK binding", function()
    local forever = bindings(read("GoldCap/Bindings_Camelot.xml"))
    local retail = {}
    for _, b in ipairs(bindings(read("GoldCap/Bindings.xml"))) do
      if not b.attrs:find("CLICK GoldCapDisenchantNext", 1, true) then retail[#retail + 1] = b end
    end
    assert.is_true(#forever > 0)
    assert.same(retail, forever)
    assert.is_not_nil(forever[1].attrs:find('header="GOLDCAP"', 1, true))
  end)
end)
