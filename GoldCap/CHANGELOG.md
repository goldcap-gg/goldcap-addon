# GoldCap

## 0.1.0 (unreleased)

- Item tooltips now show goldcap.gg market values for your realm: market
  value plus sold/day for commodities, market value plus listing count for
  one-off items, with a data-age line when the underlying data is stale.
- Import fresh market data from the website with `/goldcap import` (GCS1
  import strings, with an in-game paste dialog).
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
  real time. Buying is deliberate (two clicks for items, three for commodities
  with a red re-prompt if price rises >5% before confirm) — nothing automatic.
  A session summary prints when you leave the AH.
