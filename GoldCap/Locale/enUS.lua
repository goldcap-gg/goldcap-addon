local _, GC = ...

-- The English base: every key the addon looks up, mapped to itself. Lookups never need this
-- table -- an absent key already returns itself (Locale/Core.lua) -- it exists so the coverage
-- test has a canonical key list to measure every other language against, and so a translator
-- has one file to read instead of grepping the source.
--
-- Keys are the English sentence, byte for byte. Reword one and you orphan every translation
-- of it, silently, back to English: change the key here and in every locale file together.
GC.Locales.enUS = {
  -- Settings
  ["Language"] = "Language",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Language changed. Type /reload to apply it everywhere.",

  -- Import dialog and /goldcap status
  ["GoldCap — Import realm prices"] = "GoldCap — Import realm prices",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Paste your realm string from goldcap.gg and press Import.",
  ["Import"] = "Import",
  ["Import failed:"] = "Import failed:",
  ["imported %d items for %s (%s) — prices are live now."] =
    "imported %d items for %s (%s) — prices are live now.",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "region %s — bundled: %d items (%s), imported: %s",
  ["Companion sync rejected:"] = "Companion sync rejected:",
  ["none"] = "none",

  -- Companion dialog
  ["GoldCap Companion"] = "GoldCap Companion",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:",
  ["Close"] = "Close",

  -- Data / import errors
  ["the Companion wrote prices this addon could not read --"] =
    "the Companion wrote prices this addon could not read --",
  ["auto-synced data for %s loaded (%s old)"] = "auto-synced data for %s loaded (%s old)",
  ["this build of GoldCap does not know that region -- update the addon"] =
    "this build of GoldCap does not know that region -- update the addon",
  ["that does not look like a GoldCap import string"] =
    "that does not look like a GoldCap import string",
  ["that string is too long to import"] = "that string is too long to import",
  ["that string carried no prices"] = "that string carried no prices",
  ["there was nothing to import"] = "there was nothing to import",
  ["the import failed (%s)"] = "the import failed (%s)",
}
