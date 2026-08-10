# GoldCap

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
  unit and the old and new total, and the confirming button changes from
  Confirm to Buy anyway. A rise past 25% additionally opens a red banner
  stating how many times the quote the new price is, and holds the button
  disabled for a second and a half.
  A session summary prints when you leave the AH. A new **Sell** tab tracks
  every purchase as a flip, shows what's already in your bags versus still
  in the mail, quotes current lowest prices on demand, and posts a recommended
  price with one click once the item is in hand.
