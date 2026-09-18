# GoldCap

A World of Warcraft addon (retail) that puts [goldcap.gg](https://goldcap.gg)
auction-house prices where you are already looking: on item tooltips, in a
deal sniper, and in a Sell helper that prices your listings for you.

This repository is the addon itself — the Lua the game loads, unpacked and
unobfuscated, with the history of how it got here. It is here so you can read
what runs inside your client.

## Install

- **[GoldCap on CurseForge](https://www.curseforge.com/wow/addons/goldcap-gg)**
- **[GoldCap on Wago](https://addons.wago.io/addons/goldcapgg)**

Both listings are published from tagged commits of this repository by
[the release workflow](.github/workflows/addon-release.yml), so the zip your
addon manager installs is built from what you can read here.

## What it does in game

- **Tooltips** carry a market value: for commodities, what it sells for and how
  many move per day; for gear and one-off items, the price and how many are
  listed.
- **The sniper** watches the auction house for lots priced under what the item
  is worth, and lets you buy them from its own list.
- **Sell** prices what you are posting against what the market will actually
  absorb, instead of undercutting by a copper and hoping.
- **A ledger** of what you bought and sold, which the site turns into profit.

## What it does not do

- **No account.** Nothing to sign up for, nothing to log into.
- **No network access.** The addon cannot reach the internet — WoW addons have
  no way to, and this one does not try. Prices reach it in two ways: a data file
  bundled inside each release, and a per-realm string you either paste in with
  `/goldcap import` or let the optional
  [companion app](https://github.com/goldcap-gg/goldcap-companion) write for you.
- **No files but its own.** It writes its settings and your ledger into WoW's
  own saved-variables folder, and reads the price file described above. That is
  all it can do — the game gives an addon nothing else.

All four regions the site covers are supported: US, EU, KR and TW.

Missing or stale data is not an error: tooltip lines simply do not show, and
nothing throws a Lua error at you.

## Licence

Source-available: read it, audit it, run your own copy. Redistributing it — on
CurseForge, Wago or anywhere else — or reusing the code elsewhere, needs
permission. See [LICENSE](LICENSE).

World of Warcraft and Blizzard Entertainment are trademarks of Blizzard
Entertainment, Inc. This addon is not affiliated with or endorsed by Blizzard.

## Questions, bugs and ideas

Open an issue here, or post on the [GoldCap Discord](https://goldcap.gg/discord):
**#help** for questions, **#bug-reports** when something is broken,
**#feature-requests** for what you would like it to do. Both places are read.
For anything you would rather not post in public: support@goldcap.gg.
