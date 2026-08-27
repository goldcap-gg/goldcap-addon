local _, GC = ...

-- The English base: every key the addon looks up, mapped to itself. Lookups never need this
-- table -- an absent key already returns itself (Locale/Core.lua) -- it exists so the coverage
-- test has a canonical key list to measure every other language against, and so a translator
-- has one file to read instead of grepping the source.
--
-- Keys are the English sentence, byte for byte. Reword one and you orphan every translation of
-- it, silently, back to English: change the key here and in every locale file together.
GC.Locales.enUS = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] = " %s  %s  x%d at %s each  (%s total, %s cut)%s",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)",
  ["%d sales · %s proceeds · %s in the mail"] = "%d sales · %s proceeds · %s in the mail",
  ["Close"] = "Close",
  ["Companion sync rejected:"] = "Companion sync rejected:",
  ["DONE"] = "DONE",
  ["Duration"] = "Duration",
  ["Font scale"] = "Font scale",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap — Import realm prices"] = "GoldCap — Import realm prices",
  ["Import"] = "Import",
  ["Import failed:"] = "Import failed:",
  ["Language"] = "Language",
  ["Language changed. Type /reload to apply it everywhere."] = "Language changed. Type /reload to apply it everywhere.",
  ["Open the deals board. /gc for commands."] = "Open the deals board. /gc for commands.",
  ["Paste your realm string from goldcap.gg and press Import."] = "Paste your realm string from goldcap.gg and press Import.",
  ["REALIZED PROFIT"] = "REALIZED PROFIT",
  ["RESET WINDOW"] = "RESET WINDOW",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SAVED INSTANTLY · ESC OR DONE TO CLOSE",
  ["Settings"] = "Settings",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:",
  ["Window position & size"] = "Window position & size",
  ["auto-synced data for %s loaded (%s old)"] = "auto-synced data for %s loaded (%s old)",
  ["cost unknown"] = "cost unknown",
  ["data from goldcap.gg · synced %s ago"] = "data from goldcap.gg · synced %s ago",
  ["imported %d items for %s (%s) — prices are live now."] = "imported %d items for %s (%s) — prices are live now.",
  ["in the mail"] = "in the mail",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] = "last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices",
  ["none"] = "none",
  ["recent sales (newest first):"] = "recent sales (newest first):",
  ["region %s — bundled: %d items (%s), imported: %s"] = "region %s — bundled: %d items (%s), imported: %s",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] = "removed %d duplicate purchase record%s left by a mail-scan bug",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] = "removed %d duplicate sale record%s left by a mail-scan bug",
  ["the Companion wrote prices this addon could not read --"] = "the Companion wrote prices this addon could not read --",
  ["the import failed (%s)"] = "the import failed (%s)",
}
