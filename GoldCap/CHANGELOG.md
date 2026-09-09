# GoldCap

## 0.8.1 (unreleased)

- **Reagent quality icons in the Sniper list now match the icon your own
  tooltip shows.** They used to disagree with the game on some items.

## 0.8.0 (2026-09-08)

- **Keeps goldcap.gg's My auctions page current, automatically.** Every lot the Sell tab's
  own auction-house read sees — posted, repriced, or cancelled — is now saved for the
  Companion to sync to the site, the same way ledger sales already do. Nothing changes on
  screen; requires a matching Companion update to actually upload.

## 0.7.0 (2026-09-06)

- **The Sell tab now posts one step above the cheapest listing when the book
  says that sells just as fast — and never above the cheap quarter.** Measured
  over 3.2 million commodity listings: inside the cheapest quarter the odds of
  selling within a day are the same as at the very bottom, so racing to the
  cheapest was giving gold away. The row says why and how many units sit ahead
  of you. Turn it off under Settings → "Post above the cheapest" if you prefer
  the old behaviour.

## 0.6.5 (2026-09-01)

- **The Sell tab was hiding stock you can absolutely sell.** Anything the
  vendor refuses to buy — most enchanting dust, many crafting reagents, a
  stack of Venomous Combatant's Heraldry sitting in your bags — was left out
  of the tab entirely. Those rows said "not on hand" and showed no price and
  no margin, over items the auction house was happy to take. They are now
  counted, priced and postable like everything else.
- **The Sell tab's two counters were stuck on zero.** "TO POST" and "MY LOTS"
  were filled in once, before the list existed, and never again — so they read
  0 over a screen full of rows. They now follow the list.
- **Hovering a row in Sold now shows the item, and what you paid for it.**
  The tooltip is the item's own, the same one Deals and Sell already give
  you, with a line for the per-unit cost the profit on that row was worked
  out from.
- **What you paid is now legible on a Sell row.** The cost per unit was there
  all along, in the same weight and colour as the words around it, and easy
  to look straight past. The amount now reads as money.
- **Repost works on stock you did not buy through GoldCap.** On anything with
  no purchase history — farmed, crafted, or bought before you installed the
  addon — the Repost button did nothing at all when clicked.
- **Reposting no longer feels broken.** The button used to sit greyed out for
  three seconds before a confirming click counted, then give up on you seven
  seconds later without saying so. The pause is now a second, the window to
  confirm is nineteen, and a cancel the auction house is slow to acknowledge
  is no longer reported as having timed out when it has actually gone through.
- **Sales you have already been paid for no longer sit in the Sell tab.** An
  invoice GoldCap could not match to one of your positions used to leave a row
  behind with no icon, no numbers and nothing you could do about it. Sold
  still tells you, on that sale, when it could not work out what it cost.
- **Reagent quality ranks stop confusing your sales.** The ranks of an ore or
  a herb share one item name, and a sale invoice carries the name and nothing
  else — so GoldCap could not tell which one you had sold, and left both
  uncosted. It now tells them apart by the price the sale went through at.

## 0.6.4 (2026-08-31)

- **The addon now tells you when the Companion would help.** Tooltip prices
  that come from the bundled snapshot or a stale import end with a one-line
  reminder that the free Companion keeps them fresh. Opening the GoldCap
  auction-house tab for the very first time with no prices loaded opens the
  Companion dialog once, and that dialog now explains what installing it
  actually changes instead of only handing you the link.

## 0.6.3 (2026-08-30)

- **The Post button's help no longer covers the list.** Hovering an action
  button in the Sell tab used to drop its explanation on top of the rows, the
  column headers and the button itself. It now opens beside the button, on
  whichever side of the screen has room — and Post and Repost say what they
  do in two short lines instead of four paragraphs.

## 0.6.2 (2026-08-29)

- **Items goldcap.gg could not name now get their names from your game.** A
  handful of auction-house items (Tuskarr Jerky, Decorated Truffle and about a
  hundred more) exist only through Blizzard hotfixes, so the site knew them as
  "Item #201421" and its search could not find them. The addon now looks them
  up in your client and the Companion sends the names to the site; nothing
  changes in-game.

## 0.6.1 (2026-08-29)

- **Buying no longer gets stuck behind an earlier buy.** If the price moved in
  the instant between the quote and your Buy click, the auction house asks for
  the price again instead of selling — and the sniper used to treat that as a
  purchase still in flight, refusing every later Buy with "waiting for previous
  commodity purchase to settle" until you reloaded. It now shows you the new
  price and lets you confirm or walk away, the same way the game's own window
  does. A buy the server never answers at all is let go after a minute, with a
  reminder to check your mail.

## 0.6.0 (2026-08-29)

- **The Sell tab is built around two decks now.** One is what you can put up
  from your bags, the other is what you already have live. They were a single
  list before, with a filter you had to remember to set, and the two jobs
  read nothing alike: posting is about stock and a price, watching your lots is
  about who has undercut you. Each deck carries its own columns — YOU GET,
  PRICE / UNIT and MARGIN on one; LISTED AS, YOUR PRICE, LOT VALUE and UNDER
  YOU on the other — and the switch at the top counts what is waiting in each.

- **Two chips narrow the posting deck**: READY hides anything you cannot post
  right now, NO COST shows the positions GoldCap has no purchase price for, so
  the bookkeeping you owe is a click away instead of a hunt.

- **Opening a position no longer buries the list.** The detail used to unfold
  as a dozen more rows and push everything else off the screen. It is one panel
  now, in place, with the price ladder and the numbers behind the
  recommendation.

- **Your prices survive closing the auction house.** Type a price, walk away,
  come back — it is still there. They used to be thrown away the moment the
  window closed, so an evening of pricing was gone by the next visit.

- **The price you type updates everything immediately.** You had to press Enter
  or wait for a refresh before the row agreed with you.

- **The list stops jumping while it refreshes.** Rows keep their place as prices
  come in, instead of resorting under the cursor mid-click — which made the
  first few seconds on the Sell tab unusable.

- **Stopping a scan looked like it deleted your deals.** It never did. GoldCap
  re-checks the deals on screen against the live auction house, and rows it
  refuses are taken off the list — but that check and the scan share one
  request slot, and a running scan took every one of them. So the check barely
  ran while you scanned, and the moment you pressed Stop it caught up all at
  once and cleared the board. The check now takes its turn while the scan pages,
  so rows are confirmed or refused as they arrive instead of in one sweep at
  the end.

- **The list is no longer allowed to get shorter without saying so.** When a
  live check takes rows off the board, the status line now says how many and
  why. The HIDDEN button on the toolbar still shows the running total and still
  brings them back for a look.

- **A deal nothing has checked yet says so.** Hovering a row that no live check
  has reached tells you that in as many words. The tier, the discount and the
  profit on an unchecked row are GoldCap's own read of the imported market data,
  not a confirmed finding, and only the word on the button used to separate the
  two.

- **Buttons wrote over the numbers next to them in every language but English.**
  "Set cost" is eight characters; the same button in Ukrainian was nineteen, and
  it drew straight across the prices to its left. Twenty-one labels across eight
  languages were over their button's width. They are shorter now, and no button
  can paint outside itself again.

## 0.5.2 (2026-08-28)

- **Korean and Chinese were empty boxes.** Choosing one of them redrew the whole
  interface in the font your client happens to be running — which on a Western
  client is a Latin face with no CJK in it at all. Blizzard ships the faces for
  those scripts inside the game's own data whatever language you installed, so
  the addon now asks for the face that belongs to the script: Korean in 2002,
  Simplified Chinese in ARKai, Traditional in its own faces, each falling
  through to the next one your client actually has. The warning that used to
  claim your client had no font for the language is gone with it — it was
  printed, ironically, in perfectly legible Korean.

- **The language button became unreadable the moment you used it.** Picking
  Korean wrote Hangul into a button still drawing in the Latin face, so the one
  control you had just touched turned into three empty diamonds. It now moves
  to the new script's face with its own text. The rest of the interface
  deliberately does not: it is still written in the language you came from, and
  a face has to match the text it draws — switching everything early turned
  Ukrainian into "м□н□мальна", since the Korean face has Cyrillic but no і or є.
  The /reload the picker asks for is still what changes the words.

- **The GoldCap tab was invisible with Auctionator installed.** Both addons
  anchored their tabs to the last one they could see, and neither can see the
  other's — Auctionator's live in a shared tab library, ours in Blizzard's own
  list. Ours was on the bar the whole time, drawn underneath Shopping. GoldCap
  now registers through that same library when another addon has brought it,
  which puts every tab in one row in the order they were added, and hands the
  library the job of hiding whichever panel is not in front.

- **Auctionator's panel stayed on screen behind ours.** Same root: the library
  hides its panels when the auction house switches to a mode with content in
  it, and the mode GoldCap set was deliberately empty. Registering properly
  settles it in both directions.

- **Posting through another addon could not be clicked.** With Auctionator's
  Selling tab open, Post greyed out and only flickered back now and then:
  GoldCap's background work — the verify pass and the watch loop, neither of
  which the Auto switch governs — was spending the auction house's shared
  request budget while you were trying to use it. GoldCap could not tell,
  because it asked Blizzard what was on screen and Blizzard does not know about
  another addon's sell form. It now yields to any tab that is not its own, the
  same way it already yields to Blizzard's.

- **Labels lost their outline at any font scale but the default.** The first
  move of the font-scale slider redrew every label without the flags it was
  built with.

## 0.5.1 (2026-08-28)

- **The Settings screen was see-through.** Opening it drew the whole panel over
  the deals list — and the list drew straight back through it: rows, prices and
  item names on top of the settings cards, unreadable both ways. The screen is
  an overlay on the window's own content, and it had been told to sit in a
  layer that stopped being above the window the moment 0.5.0 raised the window
  itself out from under the auction house. It now layers against whatever the
  window is in, docked or floating, so it is opaque either way.

- **The deals table lost its column headings.** ITEM, TIER, DISC, UNIT, PRICE,
  PROFIT and TREND were blank space: the line under them was drawn, hovering
  one still raised its tooltip, and the words themselves were never painted.
  Each heading sits in a 16-pixel-tall cell and was the one label in the addon
  still allowed to wrap onto a second line — which does not fit, so nothing was
  drawn at all. They are single-line now, like every other cell in the table.

## 0.5.0 (2026-08-28)

- **The addon speaks eleven languages.** German, English, Spanish (Spain and Latin
  America), French, Italian, Korean, Portuguese, Russian, Ukrainian, and Chinese in both
  Simplified and Traditional. It follows the game's own language by default, and Settings
  → Display now has a language picker — which is the only way to reach Ukrainian, since
  no Ukrainian WoW client exists. On Korean and Chinese the interface switches to the
  client's own font, because the addon's bundled one cannot draw those characters at all.
  The translations were not reviewed by native speakers; anything untranslated falls back
  to English rather than going blank.

- **Your profit stopped adding up if you ever imported another region.** A
  ledger row's region was copied from whichever price snapshot was loaded, not
  from the character it happened on — so importing, say, a Korean snapshot while
  playing in Europe stamped every sale afterwards as Korean. goldcap.gg matches
  a sale to the purchase behind it within one region, so those sales showed
  "cost unknown", the stock behind them never left your Sell list, and "earned
  through GoldCap" collapsed. Rows are now stamped from the client, rows already
  written are repaired once on login, and a snapshot from a region you are not
  playing in says so instead of quietly re-pricing your whole board.

- **Every item on the Sell tab looked truncated.** The name and the "×246 in
  bags · ×11 listed" line under it shared one label, and that label draws a
  single line — so the second line was never drawn and every name on the screen
  ended in "…", however short it was. They are two lines now, and both are
  there.

- **"What you paid" was being pushed off the screen.** COST / UNIT was the first
  number the layout gave up once the window was anything but wide, which left a
  market price and a profit with nothing on screen saying what either was
  measured against. The numeric columns now shrink before anything is dropped,
  and what you paid is the last column to go rather than nearly the first.

- **You can set the price yourself now.** The one number on the Sell tab that
  spends real gold was the one number you could not touch: GoldCap picked it and
  Post sent it. An expanded row now has that price in a box, prefilled with
  exactly what Post would list at, and you can type over it — or take one click
  from the book (match the cheapest seller who is not you, undercut them by a
  silver), from the market value, or from your own break-even. Clearing the box
  hands the decision back to GoldCap. What you choose is what the profit column,
  the posting queue and the post itself all use — they were never allowed to
  disagree and they still cannot. GoldCap will not quietly raise your price to
  its own floor any more, but it says so, in red, next to the box: under the
  floor, or under what you paid, before you click rather than after.

- **The Sell tab finally shows the book it has been pricing against.** Every
  price decision on that screen already read the live order book — the
  underprice floor, the recommended price, how much stock sits ahead of your own
  lot — and you could see none of it. Expanding a row now shows the cheapest
  price that is not your own, how many units are standing on each price, how
  much stock is queued in front of it, which levels are already yours, and where
  the price GoldCap picked would put you — in its own four columns, with a bar
  for the depth at each price. Gold marks where your price would land, blue a
  price you are already standing on. The three headings in an expanded row were
  also still English in every language; they are translated now, and each one
  carries its hint inline rather than in a column a narrow window drops.

- **The buy check panel stopped being see-through.** Docked inside the auction
  house, the deals list showed straight through the panel covering it. The panel
  is an opaque sheet, but "opaque" only holds while it is layered above the rows
  it covers — and docking adopts the auction house's own layer for the window,
  which put the two level whenever the game placed the auction house where the
  panel expected to be alone. The panel now takes its layer from the window
  rather than assuming one, so no host can repeat it.

- **The buy check window rebuilt around one answer.** It used to open the same
  shape whatever it had to say: a headline that ran off the edge into "…", a
  quantity box on verdicts where nothing could be bought, ten rows of numbers of
  which half were dashes, and a 94-pixel gap where a profit figure would have
  gone if there had been one. It now leads with a single figure that changes
  unit rather than going blank — the gold you would lose, the days your gold
  would sit there, the number of units the market can actually absorb — and says
  "can't price this" in words when the value itself is what it does not trust,
  instead of inventing a loss out of the number it just refused. Under it are
  four facts chosen for that verdict, each with a bar only where a real
  threshold exists, so a short bar means "under the line" rather than "small
  number". A HOT badge next to a refusal now explains itself instead of sitting
  there contradicting the verdict. And the whole thing finally fits the drawer
  when GoldCap is docked inside the auction house — including "all numbers",
  which used to refuse to open there and tell you to enlarge a window that has
  no resize handle.

- **The window no longer hides behind everything.** The deals window sat under
  the auction house, the bags and most Blizzard panels, and clicking it did not
  bring it forward. It now floats above them and raises on a click — and still
  layers correctly with the auction house while docked inside it.

- **Text you can read in your own language.** Labels were drawn in the game
  client's own font, which only covers the language that client shipped for —
  so choosing Russian or Ukrainian on an English client turned most of the
  interface into empty boxes. Those now draw in the addon's bundled font, which
  covers the whole Cyrillic range. Picking a language your client has no font
  for at all (Korean or Chinese on a Western client) now warns you instead.

- **Your own language, everywhere it was still English.** Whole surfaces stayed
  English in all eleven languages because they never went through the string
  layer: the entire Settings screen, the Deals and Sold column headings and
  their tooltips, the Sell tab's action help, and — worst of them — every
  sentence the buy check shows when it refuses, which is the most-read prose in
  the addon. A second, quieter fault froze four more tables to English even
  though their translations existed. Both are fixed, and both now have a guard
  that fails the build rather than shipping silently.

- **Numbers you can read.** The buy check was printing a region's daily turnover
  as "856146.0" and the age of its data as "3384s", in a column 64 pixels wide.
  They now read "856k" and "56m".

- **The addon icon is the GoldCap mark again.** The icon in the AddOns list and
  the minimap compartment was a 64px image with a black background baked in, so
  it showed as a dark tile. It is now the same transparent mark the website and
  the store listings use.

- **The addon now tells you about the Companion.** No-import and manual-import
  states point to the free GoldCap Companion first — with `/goldcap companion`
  opening a copy-the-link dialog — and the manual paste stays as the
  alternative.

- **Korea and Taiwan work.** Import strings and Companion syncs for the `kr`
  and `tw` regions were rejected outright, so the addon could never receive
  prices there — and it said nothing about it. Both regions now import, the
  addon recognises their realms, and a sync it cannot read explains itself
  in chat, in `/goldcap status` and on the deals board instead of failing
  silently.

- **Tooltips say more.** The 24-hour trend, and what you paid for stock you
  are still holding, now sit under the market value. Prices that came
  bundled with the release are labelled as such, with their age, so they are
  never mistaken for live ones.

- **Tooltips show how deep the market is.** For commodities, a `Listed` line
  gives the units standing on the region's shelf and how many days they last
  at the rate the market is clearing them — so a cheap price you are about to
  buy into, or a stack you are about to post, comes with the supply behind it.
  It needs imported data; the snapshot bundled with the release does not carry
  depth.

- **A button you can find.** GoldCap now appears in the minimap's addon
  compartment and opens the deals board from there.

- **Bundled prices are fresh at release.** The snapshot shipped inside the
  addon is rebuilt for all four regions every time a version is released,
  instead of being whatever was last generated by hand.

## 0.4.0 (2026-08-26)

- **Left navigation rail replaces the tab row.** Deals, Sell, and Sold are now
  big icon buttons running down a rail on the window's left edge — with a
  gear button for Settings — instead of the old three-word tab strip that
  was easy to miss entirely.
- **Rounded card look throughout.** The window frame, rows, chips, buttons,
  and toolbars are drawn on a new rounded-corner visual kit, replacing the
  old flat, square-edged panels.
- **Buy/check confirmation rebuilt as a right-side panel.** Buying or
  checking a deal now opens a full-height drawer on the window's right edge
  — the deals list stays visible beside it on windows wide enough (990px+),
  and the panel overlays on narrower ones. It leads with a LIVE VERDICT card
  showing the signed profit at a glance, followed by entry/exit price cards,
  a kit-styled quantity row with quick-fill buttons, a tier pill, and an
  evidence grid that's open by default now (existing saved profiles get
  switched over once, automatically).
- **Deals rows show tier dots, signed profit, and click anywhere to act.**
  Each row's tier now reads as a small colored dot plus label; profit gets
  a leading "+" when positive; a newly-HOT deal flashes on its own
  highlight instead of interfering with the row's hover glow; and clicking
  anywhere on a row — not just its Buy button — takes the row's action. A
  pinned item that's fallen out of deal range now reads "· watching" in the
  row itself instead of showing a disabled "Watching" button.
- **Settings panel redesigned.** Two columns of grouped cards (Deal
  Thresholds, Safety, Posting, Automation & Alerts, Display) replace the old
  single list, checkboxes become pill toggles, auction duration is now a
  12H/24H/48H segmented control instead of a cycling button, and the
  font-scale slider has a proper kit-styled thumb. The rail's gear icon
  itself lights up gold while Settings is open.
- **Sold tab restyled.** Mono section labels under a gold rule, rounded row
  fills, an item icon on every sale row, and a REALIZED PROFIT figure
  called out in the header band alongside the sale count and sync age.
- **Sell tab visuals brought to the same kit.** Rounded row fills,
  badge-style action buttons, mono column headers, a visibly highlighted
  active filter chip (previously invisible), and a rounded cost-entry
  dialog, plus an honest empty state that distinguishes "nothing to sell"
  from "no items match this filter."
- **Sell tab keeps showing a price instead of going blank.** A position
  without a fresh Auction House quote now shows goldcap.gg's own imported
  market value, dimmed and marked with "≈", instead of a bare dash — so the
  tab isn't empty right after logging in and stays populated until a live
  quote arrives.
- **Est. profit adds up what it actually knows.** A position missing a cost
  or a live price no longer forces the whole summary to read "Unknown" —
  it's excluded from the total instead, with the excluded count shown in a
  tooltip. Items with nothing in your bags and nothing listed are now
  labeled "· not on hand" rather than showing a permanent dash, and sort to
  the bottom of the list.
- **Auto mode no longer fights with the Sell tab.** Switching to Sell now
  automatically pauses the Deals Auto scan (it resumes when you go back to
  Deals), and the Sell tab's own price-fetching says "Waiting for the
  Auction House…" while the search slot is busy instead of implying
  something is stuck.
- **Fixed a phantom Sell row.** A sale that settled long ago no longer
  conjures a sell position with no stock behind it.
- **Window widens to make room for the rail.** The default window width
  grew to fit the new navigation rail, and anyone who'd resized their
  window before this update gets that space handed back automatically,
  once.
- **Polish pass.** A hovered deal row no longer freezes with a stale price
  and a stuck gold highlight if you close the window mid-hover; a partial
  Est. profit total on the Sell tab now carries a trailing `*` instead of
  reading like a complete number; the buy dialog's "CHECKING" verdict no
  longer flashes green left over from an earlier check; sale/sell rows with
  no resolvable icon no longer indent the item name into empty space; and
  the Sell tab's "≈ market value" fallback comes back once a one-off empty
  Auction House answer goes stale, instead of hiding for the rest of the
  session.
- **`/gc` slash alias.** A shorter alternative to `/goldcap` for every
  command.

## 0.3.0 (2026-08-26)

- **Sniper redesign, on brand.** The sniper window is rebuilt on goldcap.gg's
  own visual language — dark panels, gold accents, a bundled monospace font
  for prices and stats (item names keep rendering with the game's own font,
  including Cyrillic, so nothing turns to boxes). The window now resizes both
  its width and height (not just height), and the deal columns respond to
  that width: on a narrower window, the total-cost and 24h-trend columns tuck
  away first (still one click away, in the buy dialog) before anything
  overlaps.
- **New Unit and Trend columns on the deals list.** Unit shows the per-auction
  unit price (sortable on its own, independent of the total-cost column, so
  it stays reachable even at widths where total is tucked away); Trend shows
  the item's signed 24h market-value momentum (▲/▼ N%) wherever import data
  has it, so a deal that's actually been sliding doesn't read the same as one
  holding steady.
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
  abandoning a flip you don't want to track. A summary strip totals invested
  across every flip and projected/profit across *priced* flips — a flip with
  no owned lot and no fresh quote yet doesn't get a guessed number folded
  into the total; it's counted instead in a "· N unpriced" indicator next to
  Profit, so the totals never read as silently contradictory.
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
- **New Sold tab.** A third tab, next to Deals and Sell, answers "what did I
  sell and at what profit" straight from goldcap.gg's own numbers — the same
  FIFO cost-basis profit as the web ledger, fed in by the GoldCap Companion
  on its regular sync tick. It's shown as two honestly separate sections:
  goldcap.gg's own synced sales, and a "not on goldcap.gg yet" section for
  today's sales and anything this session hasn't synced yet, so a sale never
  goes missing while it's waiting on a `/reload` or logout to reach the
  server. No companion paired? The tab says so instead of showing nothing.

## 0.1.0

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
