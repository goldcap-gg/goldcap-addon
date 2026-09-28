-- Mimics one specific way WoW's Lua differs from a normal one: string.format converts a
-- %d/%i/%x/%c argument to a 32-bit integer and raises "integer overflow attempting to store N"
-- for anything outside +-2^31 (2,147,483,647 -- about 214,748g in copper). busted's own Lua has
-- no such ceiling, so a spec that exercises a real 32-bit-Lua bug still runs green -- exactly
-- how a 1.5M-gold troll listing (min=15000001200) crashed a live scan
-- (GoldCap/Core/ForeverFold.lua's Encode) with a fully green suite behind it.
--
-- Installed, `("%d"):format(n)` and friends raise the same message WoW's client does for an
-- out-of-range integer conversion; every other specifier (%s, %f, %.0f, ...) is untouched --
-- the whole point is that GC.Util.IntText's own `%.0f` stays safe under this shim, the same way
-- it is safe in the real client.
--
-- luacheck: ignore 122 -- deliberately setting string.format itself; that is this file's job.
local support = {}

-- Captured before any override, and the only thing ever called to do the real work -- calling
-- string.format or (""):format from inside this file after install() would recurse into the
-- shim it just installed.
local realFormat = string.format

local INT32_MIN, INT32_MAX = -2147483648, 2147483647
local INT_CONV = { d = true, i = true, x = true, c = true }

local function wowFormat(fmt, ...)
  if type(fmt) == "string" then
    local args, argIndex = { ... }, 0
    local i, len = 1, #fmt
    while i <= len do
      local pct = fmt:find("%", i, true) -- plain find: ONE literal "%", not the pattern escape "%%"
      if not pct then break end
      if fmt:sub(pct + 1, pct + 1) == "%" then
        i = pct + 2 -- a literal "%%": no conversion, no argument consumed
      else
        -- Flags, width and precision (e.g. the "06.2" of "%06.2f"), then the one conversion
        -- letter itself.
        local j = pct + 1
        while j <= len and fmt:sub(j, j):match("[%-%+ #0-9%.]") do j = j + 1 end
        local conv = fmt:sub(j, j)
        if conv ~= "" then
          argIndex = argIndex + 1
          if INT_CONV[conv] then
            local n = args[argIndex]
            if type(n) == "number" and (n < INT32_MIN or n > INT32_MAX) then
              error("integer overflow attempting to store " .. realFormat("%.0f", n), 0)
            end
          end
        end
        i = j + 1
      end
    end
  end
  return realFormat(fmt, ...)
end

-- Both string.format(...) and ("x"):format(...) go through this afterward: the string
-- metatable's __index IS the string table in Lua 5.1+, so overwriting the one field here is
-- enough for both call shapes.
function support.install()
  string.format = wowFormat
end

function support.uninstall()
  string.format = realFormat
end

return support
