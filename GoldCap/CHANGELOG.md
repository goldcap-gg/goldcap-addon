# GoldCap

## 0.1.0 (unreleased)

- Item tooltips now show goldcap.gg market values for your realm: market
  value plus sold/day for commodities, market value plus listing count for
  one-off items, with a data-age line when the underlying data is stale.
- Import fresh market data from the website with `/goldcap import` (GCS1
  import strings, with an in-game paste dialog).
- Check bundled/imported data freshness and realm coverage with
  `/goldcap status`.
- **Sniper**: a standalone window that live-scans your watchlist against the
  Auction House while it's open (auto-appears when you open the AH, or
  toggle it yourself with `/goldcap sniper`), surfacing tiered deals — HOT,
  GOOD, WATCH, SUSPECT — with discount and profit already net of the 5%
  auction house cut. A bait shield flags implausibly steep "discounts" as
  SUSPECT instead of HOT so scam listings don't bait a snipe. Buying is a
  deliberate two-click confirm (three clicks for commodities, with a
  red re-prompt if the price rises past 5% before you confirm) — nothing is
  ever bought on a single click or automatically. A session summary (snipes,
  gold spent, estimated profit) prints when you leave the Auction House.
