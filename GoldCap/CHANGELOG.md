# GoldCap

## 0.15.0 (unreleased)

- The sniper now watches the prices you set in your alert groups on goldcap.gg. A listing at or
  under your price shows up as a "YOUR PRICE" row, rings, and buys through the usual window.
  Your prices are watched on both Deals boards and on the Sold tab while the GoldCap window is
  open at the auction house, and wait while you use the Sell and BUY tabs; each find shows up on
  its own board. Needs the current Companion release; the group's minimum item level is
  honoured for gear. When you buy part of what is listed at your price, the rest comes back as
  a row. The row names its alert group when there is room for it; hover it for the group and
  what YOUR PRICE means. Its PROFIT is what reselling the whole buy at the market would make
  after the cut, like every other row's.
- A commodity at your price is bought cheapest first and no more than your "Max units per buy"
  and your wallet limit allow; gear at your price keeps to your wallet limit too. The sniper
  never plans a unit above your price, and warns you loudly before any quote that could include
  one. If the listing at your price has gone by the time you check it, the buy window says what
  the next one misses — your price or your item level — and holds its Buy button for a moment.
  Buys at your price count in your session and your ledger like any other sniper buy.
- New option: stop scanning and open the buy window as soon as one of your prices is met (off
  by default). It never takes over a buy window you already have open: it waits until you
  close it. The window it opens holds its Buy button for a moment, so a click meant for the
  board does not land on it, and after you close one it waits two minutes before opening the
  same item again.
- Once you search, or open your favourites, on the auction house's own Buy tab, the sniper
  leaves that list alone for as long as the tab shows it, with the GoldCap window open or closed.
- The BUY tab shows the item level an alert group's gear price is set for ("item level 625+").
  When the sniper has already seen the item at that level or higher, the auction house search it
  opens shows the cheapest such version rather than whichever one the auction house picks.
- A realm item listed in several item-level variants is now checked and bought at its cheapest
  variant, not whichever one the auction house answered first.
- The buy window's Reason line shows its whole sentence instead of cutting it off.
- Clicking Buy right after a purchase was cancelled or sent back to a Check no longer sits on
  "waiting for previous commodity purchase to settle": the click checks the price again, and
  the next Buy goes through. While a purchase you confirmed is still going through, the next
  buy window waits for it and offers Refresh as soon as it is done.
- The Auto button says what is holding it — "AUTO · PAUSED: MAILBOX OPEN", "BUY TAB", "WAITING
  FOR YOU" and so on — and its tooltip says what to do about it. A mailbox you left by walking
  straight to the auctioneer no longer keeps Auto paused.
- Rows you watch show their discount, total and estimated profit against the market when the
  addon knows a market value for the item, dimmed, until a live Check confirms them.
- A scan you started yourself that stops because you left the Deals tab, searched the auction
  house yourself or closed it now says so, instead of reading "scanning auction house..." until
  the next scan.
- Post on the Sell tab shows that it is posting — the button spins and says so, and pressing it
  again does nothing meanwhile — then says Posted, or what went wrong in the auction house's own
  words. A post the auction house answers late still counts as posted.
- The Deals tab names an auction house error in the game's own words instead of a generic one.
- THE BOOK on the Sell tab is drawn around your price: the cheapest prices, the ones just under
  yours, your price with how many units are ahead of you — the ones already at your exact price
  count, they sell first — and the ones above it. Walls, the big stacks worth pricing under, are
  marked and named, with how long the queue ahead of you takes at today's pace. A row's
  "N ahead" counts the same way.
- The Sell tab lists gear and caged battle pets from your bags, priced for their exact item level.
  An item the auction house has not told GoldCap about yet is listed under its own heading
  instead of being left out.

## 0.14.1 (unreleased)

- The sniper no longer replaces your own search results while you are on the auction house's
  Buy tab with the GoldCap window closed.
- The Deals column headings no longer go blank after you visit another tab or reopen the
  window.

## 0.14.0 (2026-09-21)

- **My lots tells you what to do with them.** The tab is split into three: lots that have
  been undercut and are worth cancelling, lots priced far under the market, and lots to leave
  alone. A row says how the stock is listed ("400 in 2 lots"), the rows worth cancelling carry
  their own Cancel lot button, and the panel opens on your lots, each with its own. The button
  that used to say Repost now says what it does: it cancels the lot, after a second click.
- **Cancelling a lot no longer freezes the tab.** After the confirming click the Sell tab could
  sit dead for half a minute — no row would open, the panel would not close. The lot now
  leaves the list at once, and the tab says when the auction house has confirmed it.
- **GoldCap's price no longer queues behind a wall for one silver.** On fast-selling goods it
  could pick a price one step above a huge stack of listings, putting tens of thousands of
  units in front of yours for half a percent more. It now weighs each price against the wait
  in front of it, and joins the front of that stack instead.
- **Buy more than 200 at a time.** A new setting, "Max units per buy" (up to 5,000; still 200
  until you raise it), lets the sniper take a whole cheap wall in one purchase. How fast the
  item sells, your wallet limit and the profit floors still decide the final amount.
- **Counts that mean what they say.** TO POST counts what you can actually post, not the stock
  sitting in your mail or bank with it; the Refresh button counts the tab you are looking at.
- **A cleaner look everywhere.** Profit, loss and cost wear calmer colours, item names are in
  their quality colour, the scrollbars lost their arrows, the row's Post button has a gold
  outline and the order book's bars have rounded ends.
- **Deals no longer pauses after a Sell refresh.** Pressing Refresh on Sell and switching
  straight to Deals could leave the board standing still for up to half a minute.
- The Sell tab's newer texts are translated in every language the addon speaks.
- **Your crafts reach goldcap.gg too.** The ledger and portfolio on the site now
  show what you made and what it cost, and the materials it used up stop being
  counted as goods you still hold. Nothing is charged twice: the gold is spent
  when you buy the materials, not again when you craft with them.
- **`/gc sniper` opens the sniper window again.**

## 0.13.0 (2026-09-20)

- **The Sell tab, redrawn.** Each row now answers before you open it: under the price, where
  it stands in the live book — five marks, one per price level, and how much stock is queued
  under it ("120 ahead", "first in line") — and under YOU GET, the margin. A row says what is
  wrong with it only when something is (`no price`, `no cost for 12`, `far below market`).
  Stock that is in the mail, the bank or on another character folds under one heading at the
  bottom.
- **A position opens beside the list, not inside it.** The detail panel has its own column on a
  wide window and lies over the list on a narrow one: a large price box with a ring that says
  whose price it is, what that price fetches beside it, five one-click fills as one strip
  (**GOLDCAP** hands the price back), the reason for the price, **Post**, and the whole
  eight-level book — your level washed in gold, levels that are already yours in blue — then
  your lots and what you paid, in columns.
- **The whole tab is priced at once.** Pressing **REFRESH** (or opening the tab) asks the
  auction house about every commodity on it in one message, so prices arrive together instead
  of a row at a time; the books and queue standings fill in behind them, the deck you are
  looking at first, top to bottom. **Post** still checks that one item's price before it lists.
- **The status is where the button is.** The bottom of the tab is a dock: the bulk action, what
  it will do next, what is happening right now, and the session's totals. A search box sits in
  the top row wherever the window has room for it.
- **The Sell tab knows what your crafts cost.** Craft with materials GoldCap saw
  you buy and the finished item carries their price, with multicraft extras and
  returned materials counted as they actually landed — so profit, breakeven and
  the repost advice work on what you make, not just on what you flip. The
  materials leave your stock at the same moment, instead of sitting there as
  goods you no longer have.
- **A craft GoldCap cannot price stays empty, not guessed.** Materials you
  gathered yourself or bought from a vendor have no price it can see, so those
  crafts keep no cost at all rather than being given a made-up one. `/gc craft`
  says what the last few crafting sessions did, and why any of them recorded
  nothing.

## 0.12.3 (2026-09-19)

- **The Sell tab leaves the auction house to you and your other addons.** It kept re-pricing
  your items every few seconds, so Auctionator's selling and shopping tabs sat on "Fetching item
  info…" waiting for their turn. It now pauses while you post, buy or search on the auction house
  — in Blizzard's own tabs or another addon's — and while the GoldCap window is closed, then
  carries on by itself. Pressing Post on a row still checks that item's price straight away.
- **An item you open on the auction house keeps its prices.** With a commodity or item page open
  from Blizzard's Browse list, turning on Auto — or anything else GoldCap searches in the
  background — could send that page back to "Searching…" for good. GoldCap now waits until you
  go back.

## 0.12.2 (2026-09-16)

- **The SOLD tab's column headings draw again.** QTY, UNIT, TOTAL and PROFIT
  could come back blank after switching tabs, with only ITEM and WHEN
  showing. They are stamped again every time the tab is shown.

## 0.12.1 (2026-09-16)

- **Every line of a run is yours to buy.** The BUY tab no longer limits how many lines of a run
  you can buy — every line of every run has its BUY button, for everybody.

## 0.12.0 (2026-09-16)

- **Craft it or buy it.** Hover a run line GoldCap knows a recipe for and its tooltip prices the
  item both ways — what its reagents cost against what the auction house is asking for the
  finished thing — in green when crafting is the cheaper of the two. Right-click the line and
  **Split into reagents** turns it into a craft line with its reagents underneath, bought, capped
  and counted like any other line; a reagent the run already asked for simply grows instead of
  appearing twice. **Buy it whole instead** puts it back.
- **A plan you recomputed says so.** Recompute a saved list at today's prices on goldcap.gg and
  the run's header says what changed for the next day, while your bought counts and what you have
  spent carry over line by line.
- **Runs you follow.** Open somebody's list on goldcap.gg, follow it, and it rides into the BUY
  tab after your own, marked with whose it is. Unfollow on the site.
- **Your alerts, ready to buy.** Every alert group that has hits right now becomes a run of its
  own under **Alerts** in the run picker — one line per hit, capped at the price you set the
  alert for rather than at the usual-price cap, and marked with the realm when the hit is bound
  to one. The run goes when the hits do.
- Needs companion 1.11.

- **Every line of a run knows what it should cost.** A list saved on goldcap.gg now brings the
  site's own price for each reagent, so USUAL and the price cap work even for items GoldCap's
  market data has never carried — old-world cloth, low-level ore, anything the auction house
  rarely sees. Needs companion 1.10 (or paste the list again from goldcap.gg).
- **Vendor lines are priced.** A reagent you buy from a vendor shows what the vendor charges and
  what the whole stack will cost, and the run counts it into what is left to spend. **Copy vendor
  list** in the run header opens the list as plain text — what to buy, what each costs, what the
  trip comes to — ready for Ctrl+C.
- **When an item is usually cheap.** Where the price cap refuses a line, GoldCap says what hour of
  the day that item has usually been cheapest over the last fortnight, in your realm's time. It
  shows on the line's tooltip and in `/gc buy`.
- **Finished lines get out of the way.** Lines you have already bought drop to the bottom of the
  run, under the vendor stops, and a run with nothing left simply says so. Its menu then offers
  **Archive**, which takes it out of the picker; archived runs sit at the bottom of the same menu
  with **Restore**.
- **A cap per run.** The run menu carries its own `Cap:` setting — 100% to 300% of the reference
  price — so a run you are in a hurry to finish can pay more than one you are not. A run without
  its own cap uses the one in Settings.
- **HAVE counts your bank.** A line's HAVE is everything the character owns — bags, bank, reagent
  bank and warband bank — so a run no longer sends you shopping for stock you already have. The
  line's tooltip says how much of it is in the bags and how much is in a bank.
- **Purchases reach your ledger on goldcap.gg.** What you buy through the BUY tab is reported
  against the list you bought it for, so the site can tell you what a run really cost.

- **BUY tab.** Lists with quantities you save on goldcap.gg (a profession's shopping list, for
  one) get a BUY tab of their own at the auction house. Each line shows what you need,
  what is already in your bags and bank and what is left to buy; one click buys the missing amount
  of a commodity from the cheapest lots, and a second click confirms the total. Lines are
  never bought above your cap (130% of the usual price by default, in Settings); when only
  part fits under it, that part is bought and the rest waits. Vendor reagents are marked and
  left to the vendor. Free accounts can buy the first five lines of a run; Pro buys them all.
  A list synced by companion 1.9 reaches the game the way market data does — after a /reload or
  relog — or paste a run string from the site into Import.
||||||| 7395efeb
- **The ITEMS board keeps looking.** After a switch to ITEMS the board checked its items
  once and then stood still for the rest of the visit; it now goes round its list again every
  few seconds for as long as the board is on screen.
- **A purchase page opened by a search no longer stops the scan.** GoldCap tells your own
  click on a browse row from a page a search opened, however long the search took to answer,
  so the Deals scan and the Items poll no longer wait for you to press Back.


## 0.9.2 (2026-09-15)

- **Two boards on the Deals tab: COMMODITIES and ITEMS.** Gear, pets and recipes were sharing
  one hundred-row list with reagents and consumables, and because a piece of gear is worth far
  more per lot, their leads pushed the commodities off the board — there were fewer of them
  than before they ever appeared. Each kind now gets its own hundred rows, and you switch
  between them with the chips at the top of the board; the ITEMS chip counts what is waiting
  there while you work the other one. Gear, pets and recipes are also only checked against the
  auction house while their board is the one you are looking at, which gives the scan and the
  Sell tab the time back.
- **Commodities get checked again.** The background check that turns a row into BUY looks at
  the top 24 rows of the board, and since gear, pets and recipes joined it their large leads
  took every one of those places: no commodity was ever checked, so nothing said BUY. The
  check now covers the top 24 commodities first, then the top 24 realm lots.
- **Sell pricing no longer sits at "PRICING…" with most rows blank, and the Deals scan
  starts even when the game says the auction house is busy.** The client can report its
  auction-house request system as "not ready" for minutes on end while Blizzard's own search
  keeps working; every GoldCap request waited for that flag, so nothing was priced and no
  scan began. The flag is now trusted for five seconds at a time, then one request goes
  through anyway -- and the Deals board and the Sell tab each get their own turn at it,
  rather than whichever asked first taking every one. The pricing walk also retries from where it stopped instead of
  restarting from the first item, and the background poll of realm items no longer takes
  every request slot while the Sell tab is the one on screen. `/gc sell` prints the walk's state if it ever sticks
  again. Three more ways it could stick are gone: an item waiting on a price it had already
  asked for, an item the game never named, and a price check started by pressing Post now all
  time out and move on instead of leaving the tab on "PRICING…" until you reload. Pricing also
  stops while you are on another tab, so the Deals scan and your own searches get the request
  slot back.
- **The Sell tab says "none" only when the auction house actually answered.** A request that
  never came back was reported as "Nothing listed on the AH right now", which read as a quiet
  market when it was really no answer at all. Silence now leaves the row waiting, and the
  goldcap.gg price still stands in until a real one lands.
- **Post lists at the price the row shows.** For some items the price sent was a silver above
  the one in PRICE / UNIT.
- **YOU GET and the posting queue count the stack a click will actually list.** Gear and other
  non-stacking items post one bag stack at a time, but the figures counted everything in your
  bags — so five stacks of twenty promised a hundred units and the click listed twenty. The
  queue is ordered on the real figure too.
- **A live listing and the same item in your bags stay on one row.** Until the game had said
  whether an item sells as a commodity, its listing filed itself separately from its stock:
  two rows for one item, one reading "not on hand", and reposting the lot could answer "Lot
  cancelled; wait for it to return to bags" about a lot that was still up.
- **A slow Confirm is no longer reported as a failure.** Taking your time over the posting
  confirmation could produce "Posting timed out" over a post that had gone through — and the
  post then went unrecorded, leaving a price you had typed to carry over to the next stack.
- **CANCEL stops offering a lot it is already cancelling**, instead of re-arming the same lot
  while the auction house is still working on it.
- **The UNDERCUT price button no longer empties the box** on items selling for a silver or
  less, where there is no rung below to undercut to.
- **The READY and NO COST filters work again after using POST or CANCEL.** Pressing either
  queue button left the filters lit but doing nothing for the rest of the session.
- **Column headings on the Deals board no longer go blank after a tab switch.** PROFIT and
  TREND could disappear after visiting Sell or Sold and only come back once a heading was
  clicked; they are redrawn every time the board is shown.
- **Nor does anything else on it.** Deal rows, the AUTO/SCAN/HIDDEN buttons and the Sell and
  Sold headings could come back blank the same way. Everything is redrawn when you return to
  a tab or reopen the window, and a long message on the toolbar's status line is no longer
  dropped for being too long to fit.
- **Escape closes just the check panel.** One press used to close the panel, the GoldCap
  window behind it, and — on the auction house tab — hand the auction house back to
  Blizzard's own Browse tab.
- **Escape in a Settings number field forgets what you typed instead of saving it.** Backing
  out of a half-typed number saved it anyway. Those fields also stop glowing once you click
  away from them.
- **The window comes back where you can reach it.** A position remembered from a different
  resolution or UI scale could put the window off-screen, with the title bar you would drag
  it back by off-screen too. `/goldcap reset` (or RESET WINDOW in Settings) puts it back in
  the middle at its default size from anywhere.
- **The GoldCap tab on the auction house tries again.** If building it failed on the first
  visit of a session — usually a clash with another addon — the tab stayed missing until you
  logged out. It is now rebuilt on the next visit.
- **An item tooltip no longer hangs around** after the window or the check panel closes
  under your cursor, and a row that empties no longer hands its "new deal" gold flash to the
  next item to take its place.
- **HIDDEN, REFUSED, the "watching" tag and the AUTO/SCAN/HIDDEN hover texts are translated**
  — they were English on every client whatever your language.
- **Korean and Taiwanese realms can import their prices.** The import string your realm
  produces was refused as "not a GoldCap import string" whenever the realm's name is written
  in its own alphabet, which is every realm in those two regions. Scans made on them now
  count towards live prices as well.
- **Taiwanese players are no longer told every session that their prices come from the wrong
  market.** Taiwan connects through the Korean gateway, so the addon read a Taiwanese client
  as Korean and warned about a mismatch that was never there.
- **Prices in the auction house browse list.** Hovering a row there — the single "Star Belt"
  standing for every listing of it — showed no GoldCap lines at all.
- **Gear, pets and recipes show the region's price, not your realm's median.** A realm item
  can sit at two listings for days, and the middle of two listings is not a price: it read as
  high as 2.7 million gold on an item worth 90,000. The tooltip now shows the figure the rest
  of the addon judges these items by, with the item level it was measured at. Where there is
  no region price for an item, the realm's own median is still shown — labelled as an
  unverified realm median, and on its own, with no sale rate or stock count beside it.
- **Item tooltips say how old the prices are from six hours on**, the same point the Deals
  window starts warning you, instead of staying silent until two days.
- **"My auctions" tracks lots on hyphenated realms.** Characters on realms like Azjol-Nerub
  never had a single lot recorded, so the site's My auctions page stayed empty for them.
- **`/goldcap status` speaks your language**, tells you when the loaded snapshot is from
  another region, and stops reporting a Companion sync problem you have already fixed by
  pasting a string. A sync problem that is still there is now repeated once each time you
  log in rather than mentioned once and never again.
- **Clearer refusals when an import will not take**: a string with two strings pasted into
  it, one that names no realm, and — where GoldCap cannot work out which region you are
  playing in — a line saying so, instead of US prices shown without comment.
- **A confirmed buy the auction house never answered stays finished.** GoldCap tells you the
  purchase may or may not have gone through and to check your mail — and then used to offer
  that same lot again about a minute later, one click from paying for it twice. The row now
  stays put until you close the window yourself, and a confirmation that turns up late is
  written to your ledger and your flips instead of being lost.
- **Your own auctions are not stock you can buy.** The price levels you are selling at
  counted as depth to buy into and as the price to sell against, so a purchase could be
  planned around units nobody was going to sell you, and the resale it was judged on could be
  priced one copper under your own listing.
- **"Dump-trend cap %" does what it says.** It now refuses a buy when the price has fallen
  more than that in the last 24 hours; whatever you set, the refusal used a fixed 10%.
- **Deposits are quoted for the listing length you post at.** Every buy costed its resale at
  a 24-hour listing even when your duration is 12 or 48 hours.
- **"You paid" counts only what this character holds in this region.** It averaged in every
  character on the account, at prices from markets you were not standing in. Gear, pets and
  recipes bought from the Deals board are also matched to their sale now, so the figure stays
  right after you sell one.
- **Confirm stays greyed out when a re-quoted price is past your gold**, instead of offering
  a purchase that could only fail.
- **The check panel speaks for the item it is showing.** A check finishing for another row
  could repaint the panel you were reading — its status line, its verdict and its Buy button.
- **A bid that never lands no longer rewrites the price on the board**, and a buy is refused
  with "waiting for previous commodity purchase to settle" in fewer cases where there was
  nothing left to wait for.
- **Settings says what the spike threshold actually does**: above that 24-hour rise it prices
  the resale exit down, not the market value.
- **AUTO no longer says it is scanning when it is not.** While you were posting, buying or
  reading your own search, AUTO held the scan back -- but the button read "AUTO · SCANNING"
  and stayed that way, because nothing was running that could finish and move it on. It waits
  now, and starts the scan the moment you are done.
- **The board and the Sell tab keep working while a buy sits on screen.** A check that armed
  a Buy button stopped every other price check in the addon until you clicked it or the quote
  expired: rows stopped updating and the Sell tab read "Waiting for the purchase to finish…"
  over a purchase nobody had made yet. A buy the auction house never answers at all also
  frees everything else in about half the time it used to.
- **GoldCap stays out of your own Browse pane.** Background requests could replace what
  Blizzard's browse list was showing, so it jumped to an item page with a spinner on it while
  you were reading your own search. A scan you started with the Scan button also stops when
  you switch to Sell or Sold, instead of paging away behind them.
- **An item the auction house never answers about is checked again.** One unanswered request
  used to put that item out of reach for the rest of the session: the board skipped it in
  silence, and its Check button answered "waiting for previous search result to settle" for as
  long as you stayed logged in. The wait is now given up after fifteen seconds.
- **Gear, pets and recipes stop disappearing from the board moments after they appear.** A
  price check for them could land in the middle of a scan and be read as the scan's own
  results -- which deleted the rows it did not mention, and cost the scan the page it was
  waiting for.
- **An item you are the only seller of is not a deal.** The board took the cheapest listing as
  the price to buy at whether or not that listing was your own, so a market you hold outright
  kept coming back as its own bargain.
- **A damaged save file no longer leaves GoldCap dead and silent.** If the stored purchase
  records could not be read, the addon stopped loading right there: no window, no commands, no
  tooltips, and nothing on screen to say why. It now says what is wrong and runs everything
  except cost tracking.

## 0.9.1 (2026-09-11)

- **The Sell tab's footer now reads COST · ASKING · AT MARKET.** ASKING is the total of
  your own listed prices; AT MARKET is what GoldCap expects these lots to actually sell
  for, after the 5% cut. Hover AT MARKET for the explanation — the two numbers were easy
  to read as one subtracting the other, and they don't.

## 0.9.0 (2026-09-11)

- **The sniper finds a fresh dump in seconds, not half a minute, and the board tells you
  the moment it has actually checked one — "SAFE +Ng" in place of a guess, and the reason
  in full on the row you hover when the answer is no.**
- **Gear, pets and recipes listed far under their region price now reach the board within
  seconds and can be bought from the dialog, marked as unverified for sale speed.**
- **Settings is simpler and explains itself.** The old HOT/GOOD discount and sold-per-day
  fields are gone — what's left is the three numbers that decide whether a buy happens at
  all and the three that decide when to stop trusting the data. Hover any field or toggle
  for a plain-language explanation and its shipped default, and a DEFAULTS button on each
  card resets it in one click.
- **Item tooltips no longer cover the board.** Hovering a deal or a Sell position now opens
  its tooltip beside the window instead of on top of it.
- **The Sell tab now caps its posting price at what the item's floor actually reaches
  within a day, and joins the cheapest rung instead of undercutting it by a silver.**
- **A purchase that the auction house never answers no longer stalls the scanner, and a Buy
  no longer bounces to "price moved" when nothing moved.**
- **While Auto scans, checks keep landing.** Rows are judged as the scan runs instead of
  waiting for it to stop.
- **A "too little profit" refusal now shows the numbers.** The check panel prints the trade
  it came closest to approving — what you would pay, what would come back, and the minimum
  it fell short of — instead of "Can't price this" over a row of dashes.
- **Buy takes what's left.** When fewer units remain than the plan asked for by the time you
  press Buy, the Sniper re-checks the book and offers what is still there at a safe price,
  instead of stopping on "price moved" or "gone" and refusing the next Buy for a while.
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
