# GoldCap

## 0.3.0 (unreleased)

- **Sniper redesign, on brand.** The sniper window is rebuilt on goldcap.gg's
  own visual language — dark panels, gold accents, a bundled monospace font
  for prices and stats (item names keep rendering with the game's own font,
  including Cyrillic, so nothing turns to boxes). The window now resizes both
  its width and height (not just height), and the deal columns respond to
  that width: on a narrower window, the total-cost and trend columns tuck
  away first (still one click away, in the buy dialog) before anything
  overlaps.
- **Deals stream in as Full Scan pages, instead of waiting for it to finish.**
  The status line now reads "scanning… N results · K deals" and both numbers
  climb live; a known deal never needs the whole scan to finish before you
  can act on it.
- **Auto mode.** A new `Auto` toggle next to Full Scan runs the scan on a
  loop by itself — it yields the moment you're buying something, searching
  the Auction House yourself, or have your mailbox open, and resumes a
  breath after you're done. A brand-new HOT deal plays an alert ping (if
  `sniper.sound` is enabled) and flashes its row once, so you don't have to
  stare at the list.
- **Hovering a deal pre-warms its buy dialog.** Hover a stale Full Scan row
  for a moment before clicking Buy, and the confirmation window can open
  already armed with a fresh price instead of showing "checking live
  price..." first — the pre-warmed quote is used only if it's still fresh
  (within 10 seconds) by the time you click.
- **Sell tab rebuilt as a flips table.** Each flip now shows what you paid,
  what it's listed at (if anything), the current market price, and your
  projected profit, with a status (unlisted / listed / undercut / sale
  pending). An undercut listing gets a **Repost** flow — one click arms a
  "Cancel lot?" confirmation showing the deposit you'd spend, a second click
  cancels the old lot and reposts at the new price, so you can never cancel
  a lot by accident. The old **×** remove button is still there for
  abandoning a flip you don't want to track. A summary strip totals
  invested/projected/profit across every flip.
- **Pending-sync hint.** World of Warcraft only writes SavedVariables to
  disk on `/reload` or logout, so a purchase or sale this session doesn't
  reach goldcap.gg's ledger until then. The Sell tab now says so directly —
  "N events sync to goldcap.gg on /reload or logout" — whenever there's
  something pending.
- **In-game settings panel.** A gear icon on the sniper window's title bar
  opens a panel for the HOT/GOOD discount and sold/day thresholds, the
  dump-trend cutoff, the sound and auto-scan-by-default toggles, a font
  scale slider (0.9–1.3), and a button to reset the window back to its
  default position and size.

## 0.1.0 (unreleased)

- Item tooltips now show goldcap.gg market values for your realm: market
  value plus sold/day for commodities, market value plus listing count for
  one-off items, with a data-age line when the underlying data is stale.
- Import fresh market data from the website with `/goldcap import` (GCS1
  import strings, with an in-game paste dialog).
- Or skip manual imports entirely: the **GoldCap Companion** desktop app
  (goldcap.gg/downloads/) auto-syncs market data into an optional
  `GoldCap_AppData` addon the game picks up at login//reload; the freshest
  source wins and manual import keeps working without it.
- Check bundled/imported data freshness and realm coverage with
  `/goldcap status`.
- **Sniper**: a standalone window (auto-appears when you open the Auction
  House, or toggle with `/goldcap sniper`). The primary mode is **Full Scan**
  — press the Full Scan button to page through the entire realm's auction
  house (roughly 15-60 seconds on busy realms, no cooldown — rescan anytime)
  and rank all underpriced items by profit as tiered deals (HOT, GOOD, WATCH, SUSPECT)
  with discount and profit net of the 5% AH cut. When buying a Full Scan deal,
  the sniper issues a fresh live requote before purchase, so the deal isn't
  stale. Secondary mode: live watchlist search cycles through ~200 items in
  real time. Buying opens a confirmation window showing what the purchase will really
  cost — for commodities, the average price across every order-book level the
  purchase will fill, not just the cheapest one — alongside market value,
  discount, the lowest asking price that will still be on the market after you
  buy, estimated resale and estimated profit. The resale estimate is capped by
  that surviving asking price, because you cannot sell above what is already
  listed: a market value the live market contradicts is quietly ignored rather
  than multiplied out into a profit you could never collect, and one sitting
  three times or more above the market is named outright. If a commodity's
  price rises before you confirm, the window shows the old and new price per
  unit and the old and new total, and the confirming button reads
  Buy anyway rather than Confirm. A rise past 25% additionally opens a red banner
  stating how many times the quote the new price is, and holds the button
  disabled for a second and a half.
  A session summary prints when you leave the AH. A new **Sell** tab tracks
  every purchase as a flip, shows what's already in your bags versus still
  in the mail, quotes current lowest prices on demand, and posts a recommended
  price with one click once the item is in hand.
