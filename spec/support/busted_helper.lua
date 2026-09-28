-- .busted's own `helper` entry: loaded once, before any spec file, for the whole run. Installed
-- globally rather than per-spec because it proved cheap -- every one of this suite's specs
-- still passed under it, so any future spec that exercises a real 32-bit-overflow bug fails
-- loudly instead of shipping behind a green run the way Core/ForeverFold.lua's Encode did.
-- See spec/support/wow_format.lua for what this actually changes and why.
require("spec.support.wow_format").install()
