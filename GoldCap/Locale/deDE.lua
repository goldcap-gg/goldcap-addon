local _, GC = ...

-- German. Terminology follows apps/web/messages/de.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.deDE = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d zu je %s  (%s gesamt, %s Gebühr)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion hält das aktuell: /goldcap companion.",
  [" · %d hidden"] = " · %d ausgeblendet",
  [" · %d keys"] = " · %d Schlüssel",
  [" · below cost"] = " · unter Einkaufspreis",
  [" · identity unresolved"] = " · Zuordnung ungeklärt",
  [" · stale %ds"] = " · %ds alt",
  [" — Check again"] = " — erneut prüfen",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — Befehle: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (kurz /gc)",
  ["%d (whole lot)"] = "%d (ganzer Posten)",
  ["%d caps · %s"] = "%d Preisdeckel · %s",
  ["%d days"] = "%d Tage",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d Angebote aus dem letzten Scan -- Full Scan zum Aktualisieren",
  ["%d filtered out as hard to resell"] = "%d als schwer verkäuflich aussortiert",
  ["%d held back"] = "%d zurückgehalten",
  ["%d held back from posting"] = "%d nicht eingestellt",
  ["%d hidden -- the live check refused them"] = "%d ausgeblendet -- die Live-Prüfung hat sie abgelehnt",
  ["%d in %d lots"] = "%d in %d Posten",
  ["%d in 1 lot"] = "%d in 1 Posten",
  ["%d lots, %s asked"] = "%d Posten, %s verlangt",
  ["%d missing"] = "%d fehlen",
  ["%d partial"] = "%d teilweise",
  ["%d prices in one request · books still loading"] =
    "%d Preise in einer Anfrage · Orderbücher laden noch",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d von der Live-Prüfung abgelehnt -- oben auf \"HIDDEN %d\" klicken, um sie zu sehen",
  ["%d sales · %s proceeds · %s in the mail"] = "%d Verkäufe · %s Erlös · %s in der Post",
  ["%d units"] = "%d Stück",
  ["%d units · %d prices"] = "%d Stück · %d Preise",
  ["%d without a price"] = "%d ohne Preis",
  ["%d without cost"] = "%d ohne Einkaufspreis",
  ["%d · %d/%d covered"] = "%d · %d/%d abgedeckt",
  ["%d/%d covered"] = "%d/%d abgedeckt",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s pro Stück    gesamt %s -> %s",
  ["%s after the AH cut"] = "%s nach der AH-Gebühr",
  ["%s ahead"] = "%s davor",
  ["%s under you"] = "%s unter dir",
  ["%s — %d unit%s without a cost"] = "%s — %d Stück%s ohne Einkaufspreis",
  [", %d hidden as unsellable"] = ", %d als unverkäuflich ausgeblendet",
  ["1 lot, %s asked"] = "1 Posten, %s verlangt",
  ["24h trend"] = "24h-Trend",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Ein Strich heißt, GoldCap kennt noch nicht die Kosten jeder Einheit — es rät sie nie aus dem Marktpreis.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Ein Anhaltspunkt, kein Versprechen: Weiterverkauf zu 95% des importierten Marktwerts, für die Menge, die Check selbst freigeben würde.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Sind mehrere Käufe zu einer Zeile zusammengefasst, werden alle davon entfernt.",
  ["AH answered empty %ds ago"] = "Auktionshaus antwortete vor %ds leer",
  ["ASKING"] = "ANGEBOT",
  ["AT MARKET"] = "AM MARKT",
  ["AUTO"] = "AUTO",
  ["AUTO · SCANNING"] = "AUTO · SCANNT",
  ["AUTOMATION & ALERTS"] = "AUTOMATIK & HINWEISE",
  ["AVOID"] = "MEIDEN",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Über diesem 24-Stunden-Anstieg gilt der Marktwert als Ausreißer nach oben und wird gedämpft.",
  ["Above your price -- quoted %s, your price %s"] = "Über deinem Preis -- Angebot %s, dein Preis %s",
  ["Asks for a second click to confirm."] = "Verlangt einen zweiten Klick zur Bestätigung.",
  ["At your price"] = "Zu deinem Preis",
  ["Auction House did not answer — press Refresh"] = "Auktionshaus hat nicht geantwortet — Refresh drücken",
  ["Auction House is not open"] = "Auktionshaus ist nicht geöffnet",
  ["Auto-scan on next AH visit"] = "Auto-Scan beim nächsten AH-Besuch",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: lässt Full Scan durchgehend laufen und tritt sofort zurück, sobald du kaufst, durchsuche das Auktionshaus selbst oder sieh in deine Post. Klick zum Umschalten.",
  ["Avoid"] = "Meiden",
  ["BOOKS %d/%d"] = "BÜCHER %d/%d",
  ["BRAKES"] = "BREMSEN",
  ["BUY — unverified"] = "KAUFEN — ungeprüft",
  ["Background check"] = "Hintergrundprüfung",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Der Break-even ist der niedrigste Preis, der nach der Auktionshausgebühr noch deine Kosten deckt. Darunter machst du Verlust.",
  ["Bundled %s data"] = "Mitgelieferte %s-Daten",
  ["Bundled data"] = "Mitgelieferte Daten",
  ["Buy"] = "Kaufen",
  ["Buy less"] = "Weniger kaufen",
  ["CANCEL %d"] = "ABBRECHEN %d",
  ["CANCEL LOT?"] = "POSTEN ABBRECHEN?",
  ["CANCELLING…"] = "WIRD ABGEBROCHEN…",
  ["CONFIRM"] = "BESTÄTIGEN",
  ["COST"] = "EINSTAND",
  ["COST / UNIT"] = "KOSTEN / STÜCK",
  ["Can't price this"] = "Kein belastbarer Preis",
  ["Cancel"] = "Abbrechen",
  ["Cancel lot"] = "Abbrechen",
  ["Cancel lot?"] = "Abbrechen?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Diesen Posten abbrechen und die Gebühr verlieren — zum Bestätigen erneut klicken",
  ["Cancel timed out"] = "Zeitüberschreitung beim Abbrechen",
  ["Cancelling lot…"] = "Posten wird abgebrochen…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Bricht diese laufende Auktion ab — sie wird NICHT neu eingestellt. Die Gebühr ist verloren, die Gegenstände kommen per Post zurück; stelle sie aus dieser Zeile wieder ein, sobald sie da sind.",
  ["Cannot post this position"] = "Diese Position kann nicht eingestellt werden",
  ["Cannot remove this entry"] = "Dieser Eintrag kann nicht gelöscht werden",
  ["Cannot repost this lot"] = "Dieser Posten kann nicht neu eingestellt werden",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Begrenzt davon, wie schnell sich das wirklich verkauft, nicht von deinem Geldbeutel.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Es liegen noch günstigere Angebote, aber beim Tempo dieses Gegenstands sind sie in Stunden weg.",
  ["Check"] = "Prüfen",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check rechnet das am laufenden Orderbuch neu, bevor Gold fließt, und kann niedriger ausfallen — oder ablehnen — wenn sich der Markt seit dem letzten Import bewegt hat.",
  ["Checked against the live order book a moment ago."] =
    "Gerade eben gegen das laufende Orderbuch geprüft.",
  ["Checked: %d of the top %d on screen"] = "Geprüft: %d der obersten %d auf dem Bildschirm",
  ["Checking prices…"] = "Preise werden geprüft…",
  ["Checking this item's price…"] = "Preis dieses Gegenstands wird geprüft…",
  ["Checking..."] = "Prüfe ...",
  ["Clear to buy"] = "Kauf freigegeben",
  ["Click Confirm to post"] = "Confirm klicken zum Einstellen",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Ein weiterer Klick bricht die laufende Auktion ab. Sie wird nicht neu eingestellt: die Gebühr ist verloren, und die Gegenstände kommen per Post zurück statt direkt in die Taschen.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Ein weiterer Klick löscht diese handeingetragenen Kosten endgültig.",
  ["Close"] = "Schließen",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "Companion hält die Preise aktuell — /goldcap companion",
  ["Companion sync rejected:"] = "Companion-Sync abgelehnt:",
  ["Confidence"] = "Konfidenz",
  ["Confirm"] = "Bestätigen",
  ["Confirm the cancel"] = "Abbruch bestätigen",
  ["Confirm the removal"] = "Löschen bestätigen",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Kopiere den Link (Strg+C) und öffne ihn im Browser:",
  ["Cost per unit"] = "Kosten pro Stück",
  ["Cost unknown for %d of %d"] = "Einkaufspreis unbekannt für %d von %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Kostet mehr, als dein Limit pro Kauf zulässt.",
  ["Could not find the queue's next item to post — try again"] =
    "Nächster Gegenstand der Einstellwarteschlange nicht gefunden — nochmal versuchen",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Nächster Posten der Abbruchwarteschlange nicht gefunden — nochmal versuchen",
  ["DEFAULTS"] = "STANDARD",
  ["DISC"] = "RABATT",
  ["DISPLAY"] = "ANZEIGE",
  ["DONE"] = "FERTIG",
  ["Default listing length for the Sell tab."] = "Standard-Laufzeit für den Verkaufen-Tab.",
  ["Default: %s"] = "Standard: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Löscht nur handeingetragene Kosten aus „Kosten eintragen“ — nie einen Kauf, den GoldCap selbst erfasst oder deiner Post zugeordnet hat.",
  ["Discount"] = "Rabatt",
  ["Discount vs market value from your GoldCap import"] =
    "Rabatt gegenüber dem Marktwert aus deinem GoldCap-Import",
  ["Dump-trend cap %"] = "Obergrenze für Abwärtstrend %",
  ["Duration"] = "Laufzeit",
  ["Enlarge the window to see details"] = "Fenster vergrößern, um Details zu sehen",
  ["Enter a whole quantity"] = "Ganze Stückzahl eingeben",
  ["Enter an exact positive cost"] = "Genauen positiven Einkaufspreis eingeben",
  ["Entry price (avg fill)"] = "Einstiegspreis (Ø Ausführung)",
  ["Entry total"] = "Einstieg gesamt",
  ["Est. profit"] = "Gesch. Gewinn",
  ["FIFO allocations"] = "FIFO-Zuordnung",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Neuer Preis für diesen Gegenstand wird geholt — gleich nochmal Post drücken",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Neuer Preis für diesen Posten wird geholt — gleich nochmal Repost drücken",
  ["Finish the pending post first"] = "Zuerst das laufende Einstellen abschließen",
  ["Finish the pending post or repost first"] =
    "Zuerst das laufende Einstellen oder Neueinstellen abschließen",
  ["Font scale"] = "Schriftgröße",
  ["Free, sits in the tray, nothing to set up in game."] =
    "Kostenlos, sitzt im Infobereich, im Spiel ist nichts einzurichten.",
  ["Full pass over them: %.1fs"] = "Ein kompletter Durchlauf: %.1fs",
  ["Full pass over them: measuring..."] = "Ein kompletter Durchlauf: wird gemessen...",
  ["Gold tied up"] = "Gebundenes Gold",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap kann nicht bestimmen, welcher Taschenstapel das ist",
  ["GoldCap data age"] = "Alter der GoldCap-Daten",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap prüft die obersten %d Zeilen gegen das laufende Auktionshaus, etwa alle %ds. Abgelehnte Zeilen werden ausgeblendet. Kaufen bleibt immer ein Klick, den du machst.",
  ["GoldCap value"] = "GoldCap-Wert",
  ["GoldCap — Import realm prices"] = "GoldCap — Realmpreise importieren",
  ["GoldCap's"] = "GoldCaps",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "GoldCaps Vorschlag für diesen Gegenstand und der Preis, den es nehmen würde.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: live geprüft -- Kauf ist sicher",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: noch nicht gegen das laufende Auktionshaus geprüft",
  ["Gone"] = "Weg",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Ausgegraut heißt, der Kurs ist veraltet; Post und Repost aktualisieren ihn vor dem Handeln.",
  ["HIDDEN 0"] = "VERSTECKT 0",
  ["HIDE DETAILS ▾"] = "DETAILS AUSBLENDEN ▾",
  ["HOLDING %d"] = "HALTEN %d",
  ["Held back from cancelling"] = "Vom Abbrechen zurückgehalten",
  ["Held back from the queue"] = "Aus der Warteschlange zurückgehalten",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Wie viele Stunden normaler Verkäufe eine Mauer unter deinem Ausstiegspreis halten darf, bevor der Deal abgelehnt wird.",
  ["ITEM"] = "GEGENSTAND",
  ["If it clears"] = "Wenn es durchgeht",
  ["Import"] = "Importieren",
  ["Import failed:"] = "Import fehlgeschlagen:",
  ["Import from goldcap.gg to arm the sniper"] = "Importiere von goldcap.gg, um den Sniper zu aktivieren",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Installiere den kostenlosen GoldCap Companion, damit Preise automatisch aktuell bleiben (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Das ist der Preis, den du unterbieten musst, um schnell zu verkaufen — nicht der Wert des Gegenstands. Ein Verkäufer in Eile kann ihn weit unter Wert setzen, und GoldCap folgt ihm nicht nach unten: den tatsächlichen Einstellpreis zeigt WHAT TO DO.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Es erfindet keine Kosten aus dem Marktpreis, also bleibt der Gewinn unbekannt, bis du welche einträgst.",
  ["Item"] = "Gegenstand",
  ["Item %d"] = "Gegenstand %d",
  ["Item level %d, below the %d your price is for"] =
    "Gegenstandsstufe %d, unter der %d, für die dein Preis gilt",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."] =
    "Items: Ausrüstung, Haustiere und Rezepte, bepreist gegen die Regionsreferenz aus deinem Import. Das Verkaufstempo bleibt ungemessen, daher werden sie nie SICHER -- das entscheidest du, und GoldCap prüft sie nur, solange diese Liste offen ist.",
  ["LISTED"] = "EINGESTELLT",
  ["Language"] = "Sprache",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Sprache geändert. Gib /reload ein, damit sie überall greift.",
  ["Last result: %ds ago"] = "Letztes Ergebnis: vor %ds",
  ["Last result: none yet this visit"] = "Letztes Ergebnis: bei diesem Besuch noch keins",
  ["Listed"] = "Eingestellt",
  ["Listed at %s — far below market. Repost."] =
    "Eingestellt zu %s — weit unter Markt. Neu einstellen.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Zu oder unter dem Preis angeboten, den du auf goldcap.gg festgelegt hast. Ob es sich weiterverkaufen lässt, schätzt du selbst ein.",
  ["Listed value"] = "Eingestellter Wert",
  ["Listings"] = "Angebote",
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "Stellt ein, was in deinen Taschen liegt — zum Preis unter WAS ZU TUN IST: eine Handelsware als gesamter Taschenbestand, ein normaler Gegenstand als ein Stapel.",
  ["Live ask"] = "Aktueller Preis",
  ["Lot cancelled; wait for it to return to bags"] =
    "Posten abgebrochen; warte, bis er in die Taschen zurückkommt",
  ["MARKET"] = "MARKT",
  ["MARKET / UNIT"] = "MARKT / STÜCK",
  ["MATCH"] = "ANGLEICHEN",
  ["Market per unit"] = "Markt pro Stück",
  ["Market reference"] = "Marktreferenz",
  ["Max units per buy"] = "Max. Stück pro Kauf",
  ["Max wallet per buy %"] = "Max. Anteil des Guthabens pro Kauf %",
  ["Min profit per buy (gold)"] = "Mindestgewinn pro Kauf (Gold)",
  ["Min return per buy %"] = "Min. Rendite pro Kauf %",
  ["Missing cost"] = "Kosten fehlen",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "NOCH NICHT AUF GOLDCAP.GG — SYNC BEI /RELOAD ODER LOGOUT",
  ["NOT ON HAND %d"] = "NICHT ZUR HAND %d",
  ["NOTHING TO CANCEL"] = "NICHTS ABZUBRECHEN",
  ["NOTHING TO POST"] = "NICHTS EINZUSTELLEN",
  ["Needs a live price check before it can be bought."] =
    "Braucht eine Live-Preisprüfung, bevor es gekauft werden kann.",
  ["Never spend more than this share of your gold on one purchase."] =
    "Nie mehr als diesen Anteil deines Goldes für einen einzigen Kauf ausgeben.",
  ["No deals passed the safety checks right now."] =
    "Gerade hat kein Angebot die Sicherheitsprüfungen bestanden.",
  ["No deals to show -- and no realm prices yet."] =
    "Keine Angebote -- und noch keine Realmpreise.",
  ["No deals yet."] = "Noch keine Angebote.",
  ["No exact auction key"] = "Kein exakter Auktionsschlüssel",
  ["No exact bag stack"] = "Kein exakter Taschenstapel",
  ["No exact bag variant"] = "Keine exakte Taschenvariante",
  ["No live listings came back for this item."] =
    "Für diesen Gegenstand kamen keine Live-Angebote zurück.",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "Für diesen Gegenstand gibt es noch keinen Regionspreis — importiere erneut, sobald goldcap.gg einen veröffentlicht.",
  ["No safe resale price could be worked out."] =
    "Es ließ sich kein sicherer Wiederverkaufspreis ermitteln.",
  ["No sales data for this item."] = "Keine Verkaufsdaten für diesen Gegenstand.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Noch keine Verkäufe erfasst -- öffne deinen Briefkasten mit geladenem GoldCap",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Im Auktionshaus liegen nicht genug Einheiten für diese Menge.",
  ["Not in your bags or listed — mail or bank?"] =
    "Weder in den Taschen noch eingestellt — Post oder Bank?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Nicht greifbar — der Bestand liegt in der Post, der Bank oder auf einem anderen Charakter",
  ["Nothing is being held back."] = "Es wird nichts zurückgehalten.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Nach diesem Kauf bleibt nichts übrig, wogegen man verkaufen könnte — es gibt also keinen Ausstiegspreis.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Kein Angebot erreicht die Gegenstandsstufe, auf der der Referenzpreis gemessen wurde.",
  ["Nothing listed on the AH right now"] = "Derzeit nichts im Auktionshaus eingestellt",
  ["Nothing on this deck matches that search"] = "Auf diesem Reiter passt nichts zu dieser Suche",
  ["Nothing queued to cancel"] = "Nichts zum Abbrechen in der Warteschlange",
  ["Nothing queued to post"] = "Nichts zum Einstellen in der Warteschlange",
  ["Nothing to remove"] = "Nichts zu löschen",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "AUF GOLDCAP.GG — LETZTE %d TAGE",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "AUF GOLDCAP.GG — LETZTE %d TAGE, NEUESTE %d VON %d",
  ["ON THE AUCTION HOUSE"] = "IM AUKTIONSHAUS",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Einmaliger Scan des ganzen Auktionshauses über seitenweise Abfragen. Dauert etwa 15-60 Sekunden auf vollen Realms. Keine Abklingzeit -- jederzeit erneut scannen.",
  ["Open the Auction House first."] = "Öffne zuerst das Auktionshaus.",
  ["Open the Auction House to begin scanning."] = "Öffne das Auktionshaus, um zu scannen.",
  ["Open the deals board. /gc for commands."] = "Öffnet die Angebotsliste. /gc für Befehle.",
  ["POST %d"] = "EINSTELLEN %d",
  ["POSTING"] = "EINSTELLEN",
  ["POSTING…"] = "WIRD EINGESTELLT…",
  ["PRICE"] = "PREIS",
  ["PRICE ROSE %.1fx"] = "PREIS STIEG UM %.1fx",
  ["PRICED TOO LOW %d"] = "ZU BILLIG %d",
  ["PRICING %d/%d"] = "PREISE %d/%d",
  ["PRICING…"] = "PREISE…",
  ["PROFIT"] = "GEWINN",
  ["PROFIT / UNIT"] = "GEWINN / STÜCK",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Verbinde oder aktualisiere den GoldCap Companion, um Gewinne von goldcap.gg zu sehen",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Füge deine Realm-Zeichenkette von goldcap.gg ein und drücke Import.",
  ["Per-unit price of this auction"] = "Stückpreis dieser Auktion",
  ["Play a sound when a checked deal turns SAFE."] =
    "Einen Ton abspielen, wenn ein geprüfter Deal SAFE wird.",
  ["Position scope changed"] = "Positionsbereich geändert",
  ["Positions without a cost or a live price are excluded."] =
    "Positionen ohne Einkaufspreis oder Live-Preis werden nicht mitgezählt.",
  ["Post"] = "Einstellen",
  ["Post above the cheapest"] = "Über dem Günstigsten anbieten",
  ["Post confirmation expired"] = "Bestätigung zum Einstellen abgelaufen",
  ["Post the next queued item"] = "Nächsten Gegenstand aus der Warteschlange einstellen",
  ["Posting failed"] = "Einstellen fehlgeschlagen",
  ["Posting timed out"] = "Zeitüberschreitung beim Einstellen",
  ["Posting unavailable"] = "Einstellen nicht möglich",
  ["Posting…"] = "Wird eingestellt…",
  ["Press Full Scan to find deals."] = "Drücke Full Scan, um Angebote zu finden.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Drücke Scan, um das ganze Auktionshaus einmal zu durchsuchen, oder Auto für laufendes Scannen.",
  ["Previous removal selection cleared"] = "Vorherige Löschauswahl aufgehoben",
  ["Previous repost selection cleared"] = "Vorherige Auswahl zum Neueinstellen aufgehoben",
  ["Price"] = "Preis",
  ["Priced from bundled sample data, not from your realm."] =
    "Preis stammt aus mitgelieferten Beispieldaten, nicht von deinem Realm.",
  ["Prices up to date"] = "Preise aktuell",
  ["Prices up to date · %d did not answer"] = "Preise aktuell · %d ohne Antwort",
  ["Pricing %d/%d…"] = "Preisabfrage %d/%d…",
  ["Pricing paused while you use the Auction House"] = "Preisabfrage pausiert, solange du das Auktionshaus nutzt",
  ["Pricing…"] = "Preisabfrage…",
  ["Profit"] = "Gewinn",
  ["Profit per unit"] = "Gewinn pro Stück",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Gewinnverfolgung ist eine goldcap.gg-Pro-Funktion",
  ["Purchases are turned off in this build."] = "Käufe sind in dieser Version abgeschaltet.",
  ["QTY"] = "ANZ",
  ["Quantity exceeds missing units"] = "Menge übersteigt die fehlenden Stück",
  ["Quantity is capped by how fast this item actually sells."] =
    "Die Menge ist dadurch begrenzt, wie schnell sich der Gegenstand wirklich verkauft.",
  ["REALIZED PROFIT"] = "REALISIERTER GEWINN",
  ["REFRESH"] = "AKTUALISIEREN",
  ["RESET WINDOW"] = "FENSTER ZURÜCKSETZEN",
  ["Reason"] = "Grund",
  ["Refresh"] = "Aktualisieren",
  ["Refresh waiting for prior result"] = "Aktualisierung wartet auf vorheriges Ergebnis",
  ["Refreshing listings…"] = "Angebote werden aktualisiert…",
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "Kauf ablehnen, wenn der Preis in den letzten 24 Stunden stärker gefallen ist als dieser Wert — er könnte weiter fallen.",
  ["Refused so far: %d"] = "Bisher abgelehnt: %d",
  ["Removal confirmation expired"] = "Löschbestätigung abgelaufen",
  ["Remove"] = "Löschen",
  ["Remove this cost"] = "Diese Kosten entfernen",
  ["Remove?"] = "Löschen?",
  ["Removed"] = "Entfernt",
  ["Removed %d entries"] = "%d Einträge entfernt",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Löscht jeden von Hand eingetragenen Kauf in dieser Gruppe -- zum Bestätigen erneut klicken",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Löscht diesen von Hand eingetragenen Kauf -- zum Bestätigen erneut klicken",
  ["Repost confirmation expired"] = "Bestätigung zum Neueinstellen abgelaufen",
  ["Right-click to stop watching this item"] =
    "Rechtsklick, um diesen Gegenstand nicht mehr zu beobachten",
  ["Right-click to watch this item closely"] =
    "Rechtsklick, um diesen Gegenstand genau zu beobachten",
  ["SAFE +%s"] = "SICHER +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "SICHER = die Live-Prüfung hat diesen Kauf freigegeben, zum angezeigten Gewinn",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "SOFORT GESPEICHERT · ESC ODER DONE ZUM SCHLIESSEN",
  ["SCAN"] = "SCAN",
  ["SCANNING…"] = "SCANNT…",
  ["SESSION %s%s · %d BUYS"] = "SITZUNG %s%s · %d KÄUFE",
  ["SHOW DETAILS ▸"] = "DETAILS ZEIGEN ▸",
  ["Sales are costed from your oldest units first"] =
    "Verkäufe werden zuerst gegen deine ältesten Stück gerechnet",
  ["Search"] = "Suche",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "Der Verkaufen-Tab bietet eine Stufe über dem günstigsten Gebot an, wenn das Orderbuch zeigt, dass es genauso schnell verkauft.",
  ["Sell-through"] = "Abverkaufsquote",
  ["Sellers"] = "Verkäufer",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Verkauft sich zu selten — du würdest lange darauf sitzen.",
  ["Set cost"] = "Kosten",
  ["Settings"] = "Einstellungen",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Kauf überspringen, wenn er nach der AH-Gebühr nicht mindestens diesen Betrag einbringt.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Kauf überspringen, wenn der Gewinn nicht mindestens diesen Anteil des Kaufpreises beträgt.",
  ["Snapshot value"] = "Snapshot-Wert",
  ["Sold per day"] = "Verkäufe pro Tag",
  ["Sold/day"] = "Verkäufe/Tag",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Danach sortieren, um zu entscheiden, was zuerst geprüft wird — nicht, was gekauft wird.",
  ["Sound on SAFE deal"] = "Ton bei SAFE-Angebot",
  ["Source age"] = "Alter der Quelle",
  ["Spike-trend threshold %"] = "Schwelle für Kursspitze %",
  ["Start scanning as soon as the auction house opens."] =
    "Sofort mit dem Scannen beginnen, sobald das Auktionshaus öffnet.",
  ["Status"] = "Status",
  ["Stop and open the buy window on your price"] = "Bei deinem Preis stoppen und Kauffenster öffnen",
  ["Stress exit unit"] = "Stress-Ausstiegspreis",
  ["Stress profit"] = "Stress-Gewinn",
  ["THE BOOK"] = "DAS ORDERBUCH",
  ["TOTAL"] = "GESAMT",
  ["TREND"] = "TREND",
  ["Tell GoldCap what you actually paid for these units."] =
    "Sag GoldCap, was du für diese Einheiten tatsächlich bezahlt hast.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "Das Auktionshaus nannte keine Einstellgebühr, also sind die Kosten unbekannt.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Der Companion synchronisiert, aber dieses Addon konnte das Geschriebene nicht lesen:",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "Die Liste hat das aus dem importierten Snapshot eingestuft. Das laufende Orderbuch stützt es nicht.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Der Knopf wartet kurz, bevor er gedrückt werden kann — ein versehentlicher Doppelklick reicht also nie.",
  ["The cancel did not go through — the lot is still listed"] = "Der Abbruch ging nicht durch — der Posten ist noch eingestellt",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "Das günstigste Angebot liegt nicht mehr weit genug unter dem Referenzpreis.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Der günstigste Preis, den gerade JEMAND ANDERES verlangt, aus einer Live-Abfrage des Auktionshauses. Deine eigenen Angebote sind ausgenommen, damit die Zahl sich nicht selbst nach unten jagt.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Die Daten zu diesem Gegenstand sind fehlerhaft, also rät GoldCap nicht.",
  ["The liquidity data is not reliable enough to act on."] =
    "Die Liquiditätsdaten sind nicht verlässlich genug, um danach zu handeln.",
  ["The market value is an estimate, not a measurement."] =
    "Der Marktwert ist eine Schätzung, keine Messung.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Mehr nimmt ein einzelner Kauf nicht. Wie schnell sich der Gegenstand verkauft, kann es weniger machen.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Die Preisdaten sind über drei Stunden alt. Synchronisiere den Companion und mache dann /reload — das Addon liest seine Daten nur beim Laden der Oberfläche.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "Der Preis ist geprüft. Wie schnell sich das verkauft, misst niemand -- das musst du selbst einschätzen.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Der Preis fällt; da einzusteigen ist genau, wie man festsitzt.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "Der Preis ist der zuletzt geholte, höchstens 45 Sekunden alt. Ändert er sich vor dem Bestätigen, wird das Einstellen abgebrochen statt zum alten Preis abgeschickt.",
  ["The price moved -- part of this quote may be above your price"] =
    "Der Preis hat sich bewegt -- ein Teil dieses Angebots liegt womöglich über deinem Preis",
  ["The price moved and the trade is no longer safe."] =
    "Der Preis hat sich bewegt, der Handel ist nicht mehr sicher.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Der Gewinn erreicht dein Minimum nicht, sobald die 5 % Gebühr und die Einstellgebühr bezahlt sind.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Das lässt sich nicht rückgängig machen. Ein Klick verlangt einen zweiten zur Bestätigung.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Das ist ein realmgebundener Gegenstand; GoldCap prüft nur Handelswarenpreise.",
  ["Too few sellers to read a real price."] =
    "Zu wenige Verkäufer, um einen echten Preis abzulesen.",
  ["Too little of what is listed actually sells."] =
    "Zu wenig von dem, was eingestellt ist, wird tatsächlich verkauft.",
  ["Too little price history to trust the value."] =
    "Zu wenig Preisverlauf, um dem Wert zu trauen.",
  ["Total cost to buy this auction"] = "Gesamtkosten für diese Auktion",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Gib einen Preis in Gold ein, oder leere das Feld, um GoldCaps zu nehmen",
  ["UNDERCUT"] = "UNTERBIETEN",
  ["UNDERCUT %d"] = "UNTERBOTEN %d",
  ["UNIT"] = "STÜCK",
  ["Unit price"] = "Stückpreis",
  ["Unknown"] = "Unbekannt",
  ["Unknown item"] = "Unbekannter Gegenstand",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "Unbekannt heißt, die Kostenseite ist unvollständig — trage sie mit „Kosten eintragen“ nach.",
  ["VERDICT"] = "URTEIL",
  ["Verdict"] = "Urteil",
  ["WATCH"] = "BEOBACHTEN",
  ["WATCH (computed SAFE)"] = "WATCH (berechnet SICHER)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "BEOBACHTEN = die Live-Prüfung hat abgelehnt -- Grund steht am Zeilen-Tooltip",
  ["WHAT COUNTS AS A DEAL"] = "WAS ALS DEAL ZÄHLT",
  ["WHAT TO DO"] = "WAS ZU TUN IST",
  ["WHAT YOU PAID"] = "WAS DU BEZAHLT HAST",
  ["WHEN"] = "WANN",
  ["Waiting for Auction House…"] = "Warte auf das Auktionshaus…",
  ["Waiting for a live price"] = "Warte auf einen Live-Preis",
  ["Waiting for the Auction House…"] = "Warte auf das Auktionshaus…",
  ["Waiting for the purchase to finish…"] = "Warte auf den Abschluss des Kaufs…",
  ["Wall absorb window (hours)"] = "Zeitfenster für Mauerabbau (Stunden)",
  ["Watching closely: %d item%s"] = "Genau beobachtet: %d Gegenstand%s",
  ["Watching — pinned, but not a deal right now"] =
    "Beobachtet — angeheftet, aber gerade kein Angebot",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Was dich eines davon tatsächlich gekostet hat, gemittelt über die noch vorhandenen Käufe.",
  ["What to do"] = "Was zu tun ist",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Was bei einer Einheit übrig bleibt, wenn sie zum Marktpreis verkauft: Verkaufspreis minus 5 % Auktionshausgebühr minus deine Kosten.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Was deine laufenden Auktionen für diesen Gegenstand zum aktuellen Preis zusammen ergeben.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Wenn ein Angebot einen auf der Website festgelegten Preis erreicht, stoppt der Scan und das Kauffenster öffnet sich.",
  ["Window position & size"] = "Fensterposition & -größe",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "Mit ihm aktualisieren sich die Preise deines Realms von selbst, und deine Verkäufe und Gewinne landen auf goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "Ohne ihn läuft GoldCap auf einem Preisstand vom Release-Tag — Angebote werden mit alten Preisen gesucht.",
  ["Won't buy"] = "Kaufe nicht",
  ["Worst case back"] = "Rückfluss im schlimmsten Fall",
  ["YOUR LOTS"] = "DEINE POSTEN",
  ["YOUR PRICE"] = "DEIN PREIS",
  ["You paid"] = "Bezahlt",
  ["You pay"] = "Du zahlst",
  ["You would get"] = "Du bekämst",
  ["You would pay"] = "Du zahltest",
  ["Your call"] = "Deine Entscheidung",
  ["Your minimum"] = "Dein Minimum",
  ["Your price"] = "Dein Preis",
  ["a unit, at or under your price of %s"] = "pro Stück, zu oder unter deinem Preis von %s",
  ["above the cheapest, inside the cheap quarter · %d units queued below"] =
    "über dem Günstigsten, im günstigen Viertel · %d Einheiten davor in der Schlange",
  ["above the cheapest, within the day's reach · %d units queued below"] =
    "über dem Günstigsten, innerhalb der Tagesreichweite · %d Einheiten davor in der Schlange",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "gegen den Regionspreis dieses Gegenstands, nach 5% Gebühr — falls er sich verkauft",
  ["another purchase took over -- nothing was confirmed"] =
    "ein anderer Kauf hat übernommen -- nichts wurde bestätigt",
  ["any figure here would be invented out of the very number being refused"] =
    "jede Zahl hier wäre aus genau dem Wert erfunden, der gerade abgelehnt wird",
  ["at or under your price -- click Buy to purchase"] =
    "zu oder unter deinem Preis -- Buy klicken zum Kaufen",
  ["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"] =
    "zu dem Preis, den GoldCap für den Verkauf erwartet, nach 5% Gebühr — nicht dein Angebotspreis",
  ["auto off"] = "auto aus",
  ["auto-synced %dh ago"] = "vor %dh automatisch synchronisiert",
  ["auto-synced data for %s loaded (%s old)"] =
    "automatisch synchronisierte Daten für %s geladen (%s alt)",
  ["auto-synced data stale -- /goldcap import"] =
    "automatisch synchronisierte Daten veraltet -- /goldcap import",
  ["auto: paused"] = "auto: pausiert",
  ["below the %s you paid"] = "unter den %s, die du bezahlt hast",
  ["big buy"] = "großer Kauf",
  ["bought %d x item %d"] = "%d x Gegenstand %d gekauft",
  ["bought %d x item %d after AH close"] =
    "%d x Gegenstand %d nach Schließen des Auktionshauses gekauft",
  ["buying commodity..."] = "Ware wird gekauft...",
  ["cheapest not yours %s"] = "günstigster fremder %s",
  ["check the item level — buy by hand"] = "Gegenstandsstufe prüfen — von Hand kaufen",
  ["checking live price..."] = "Live-Preis wird geprüft...",
  ["checking live safety..."] = "Live-Sicherheit wird geprüft...",
  ["commodity purchase failed"] = "Warenkauf fehlgeschlagen",
  ["confirmed commodity purchase failed after AH close"] =
    "bestätigter Warenkauf nach Schließen des Auktionshauses fehlgeschlagen",
  ["confirming purchase..."] = "Kauf wird bestätigt...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "Kostenbasis unvollständig -- Kosten setzen, um einen Rat zum Neueinstellen zu bekommen",
  ["cost unknown"] = "Kosten unbekannt",
  ["crafted %s"] = "hergestellt %s",
  ["data from goldcap.gg · synced %s ago"] = "Daten von goldcap.gg · vor %s synchronisiert",
  ["due -- will be asked next pass"] = "fällig -- wird im nächsten Durchlauf abgefragt",
  ["fair"] = "mittel",
  ["far below market"] = "weit unter Markt",
  ["finish the pending buy first"] = "zuerst den laufenden Kauf abschließen",
  ["first in line"] = "als Erster dran",
  ["full scan already in progress"] = "vollständiger Scan läuft bereits",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "vollständiger Scan fertig: %d Angebot%s aus %d Gegenstandsgruppe%s%s",
  ["full scan interrupted -- confirm your purchase"] =
    "vollständiger Scan unterbrochen -- bestätige deinen Kauf",
  ["full scan stalled -- press Full Scan to retry"] =
    "vollständiger Scan hängt -- Full Scan drücken, um es erneut zu versuchen",
  ["full scan stalled -- retrying shortly"] = "vollständiger Scan hängt -- gleich neuer Versuch",
  ["full scan stopped -- press %s to run it again"] =
    "vollständiger Scan angehalten -- %s drücken, um ihn erneut zu starten",
  ["gone / price changed"] = "weg / Preis geändert",
  ["high"] = "hoch",
  ["hold"] = "halten",
  ["identity unresolved (variant item -- not priced by design)"] =
    "nicht eindeutig (Variantengegenstand -- absichtlich ohne Preis)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "wenn du alle %d kaufst und zum aktuell dort stehenden Preis wieder verkaufst",
  ["import %dh old"] = "Import %dh alt",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "Import veraltet -- /goldcap import oder /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "%d Gegenstände für %s (%s) importiert — die Preise sind jetzt aktiv.",
  ["in the mail"] = "in der Post",
  ["in the mail, the bank or on another character"] =
    "in der Post, auf der Bank oder bei einem anderen Charakter",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "nimmt dieser Markt auf — darüber hinaus kaufst du Ware, auf der du sitzen bleibst",
  ["item %d"] = "Gegenstand %d",
  ["item %d: %s"] = "Gegenstand %d: %s",
  ["item level %d+"] = "Gegenstandsstufe %d+",
  ["item variant unresolved"] = "Gegenstandsvariante ungeklärt",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "letzte 24h — %d Verkäufe, %s brutto, %s Auktionsgebühr, %d Käufe, %s ausgegeben",
  ["leave these alone"] = "diese in Ruhe lassen",
  ["listing gone -- already bought out or price changed"] =
    "Angebot weg -- bereits aufgekauft oder Preis geändert",
  ["listing gone -- bought out or repriced"] = "Angebot weg -- gekauft oder neu bepreist",
  ["live safety confirmed -- click Buy to purchase"] =
    "Live-Sicherheit bestätigt -- Buy klicken zum Kaufen",
  ["live verification required"] = "Live-Prüfung erforderlich",
  ["low"] = "niedrig",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "manueller Import -- Companion hält das aktuell: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "braucht einen neuen Preis -- Refresh drücken",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "keine Bestätigung vom Server -- der Kauf kann trotzdem durchgegangen sein, prüfe deine Post. Dieses Fenster zu schließen macht ihn nicht rückgängig.",
  ["no cost"] = "kein Einstand",
  ["no cost for %d"] = "kein Einstand für %d",
  ["no live price yet"] = "noch kein Live-Preis",
  ["no price"] = "kein Preis",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "noch keine Preise -- /goldcap companion oder /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "keine Kaufbestätigung erhalten -- Cancel und erneut versuchen",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "noch keine Verkäufe erfasst — öffne deinen Briefkasten mit geladenem GoldCap, sie werden aus den Rechnungen gelesen",
  ["no stock in bags or listed -- nothing to price for"] =
    "kein Bestand in den Taschen und nichts eingestellt -- nichts zu bepreisen",
  ["none"] = "keine",
  ["not enough gold -- total %s, you have %s"] = "nicht genug Gold -- gesamt %s, du hast %s",
  ["not enough gold for this quote -- Cancel"] = "nicht genug Gold für diesen Kurs -- Cancel",
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "nicht genug Einheiten für diese Menge übrig -- prüfe erneut, was noch da ist...",
  ["not ready to cancel"] = "noch nicht bereit zum Abbrechen",
  ["not ready to post"] = "noch nicht bereit zum Einstellen",
  ["nothing listed"] = "nichts eingestellt",
  ["of %d"] = "von %d",
  ["off"] = "aus",
  ["oldest units sell first"] = "die ältesten Einheiten verkaufen sich zuerst",
  ["on"] = "ein",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "oder füge mit /goldcap import eine Zeichenkette von goldcap.gg ein.",
  ["over %d position%s"] = "über %d Positionen%s",
  ["paid sale unresolved"] = "bezahlter Verkauf ungeklärt",
  ["placing bid..."] = "Gebot wird abgegeben...",
  ["previous commodity purchase settled -- %s to re-check the price"] =
    "vorheriger Warenkauf abgeschlossen -- %s, um den Preis erneut zu prüfen",
  ["price changed after you closed the buy window -- nothing was bought"] =
    "Preis hat sich geändert, nachdem du das Kauffenster geschlossen hast -- nichts wurde gekauft",
  ["price checked, sale speed unknown -- this one is your call"] =
    "Preis geprüft, Verkaufstempo unbekannt -- das entscheidest du",
  ["price confirmed -- click Buy to purchase"] = "Preis bestätigt -- Buy klicken zum Kaufen",
  ["price rose %.1fx — still safe, confirm"] =
    "Preis stieg um %.1fx — weiterhin sicher, bestätige",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "geladene Preise sind %s (%s), du spielst aber in %s — jeder Rabatt und Gewinn wird an einem anderen Markt gemessen",
  ["purchase canceled"] = "Kauf abgebrochen",
  ["purchase complete"] = "Kauf abgeschlossen",
  ["purchase identity unresolved"] = "Kaufzuordnung ungeklärt",
  ["purchase pending exact cost"] = "Kauf wartet auf genaue Kosten",
  ["purchase total unavailable — inspect mailbox"] =
    "Kaufsumme nicht verfügbar — sieh in deinen Briefkasten",
  ["quote %s -- click Confirm to buy"] = "Kurs %s -- Confirm klicken zum Kaufen",
  ["quote %ss ago"] = "Kurs vor %ss",
  ["quote expired -- Refresh to re-check the price"] =
    "Kurs abgelaufen -- Refresh, um den Preis erneut zu prüfen",
  ["re-checking what remains at a safe price..."] =
    "prüfe erneut, was zu einem sicheren Preis übrig ist...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "Realm-Gegenstand — Verkaufstempo ungeprüft · Regionsreferenz %s (Stufe %d)",
  ["recent sales (newest first):"] = "letzte Verkäufe (neueste zuerst):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "Region %s — mitgeliefert: %d Gegenstände (%s), importiert: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "Region bei %d Buchungen korrigiert; %d Verkäufe wieder ihrem Bestand zugeordnet",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "jetzt neu einzustellen würde einen Verlust oder Stillstand festschreiben -- halten",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "%d doppelte Kaufeinträge entfernt, die ein Fehler beim Postscan hinterlassen hat",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "%d doppelte Verkaufseinträge entfernt, die ein Fehler beim Postscan hinterlassen hat",
  ["sale name ambiguous"] = "Verkaufsname mehrdeutig",
  ["sale proceeds pending"] = "Verkaufserlös ausstehend",
  ["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"] =
    "Scan fertig: %d Angebot%s aus %d Gegenstand%s in Reagenzien, Verbrauchsgütern, Edelsteinen, Verzauberungen%s",
  ["scanned %d listings over %d passes"] = "%d Angebote in %d Durchläufen gescannt",
  ["scanning auction house..."] = "Auktionshaus wird gescannt...",
  ["scanning… %d results · %d deals%s"] = "scannt… %d Ergebnisse · %d Angebote%s",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "verkauft %s/Tag",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "Sitzung: %d Zugriffe, %s ausgegeben, ~%s gesch. Gewinn",
  ["sniped (listing changed on rescan)"] = "weggeschnappt (Angebot beim erneuten Scan geändert)",
  ["sniped for "] = "geschnappt für ",
  ["stack not identified"] = "Stapel nicht zugeordnet",
  ["starting full scan..."] = "vollständiger Scan startet...",
  ["stopped watching %s"] = "%s wird nicht mehr beobachtet",
  ["the Companion wrote prices this addon could not read --"] =
    "der Companion hat Preise geschrieben, die dieses Addon nicht lesen konnte --",
  ["the import failed (%s)"] = "der Import ist fehlgeschlagen (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "um %d Stück bei %s Verkäufen pro Tag abzustoßen, mit %s die ganze Zeit gebunden",
  ["under GoldCap's own floor of %s"] = "unter GoldCaps eigener Untergrenze von %s",
  ["unknown evidence"] = "unbekannter Nachweis",
  ["waiting for previous commodity purchase to settle"] =
    "warte, bis der vorherige Warenkauf abgeschlossen ist",
  ["waiting for previous search result to settle"] = "warte auf das vorherige Suchergebnis",
  ["waiting..."] = "warte...",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s wird genau beobachtet -- alle paar Sekunden neu geprüft",
  ["worst case, selling all %d back into the price standing there now"] =
    "im schlimmsten Fall, wenn du alle %d zum aktuell dort stehenden Preis zurückverkaufst",
  ["worth cancelling"] = "Abbruch lohnt sich",
  ["would sell at a loss"] = "würde mit Verlust verkaufen",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "du hast noch keine Realmpreise importiert -- installiere GoldCap Companion (/goldcap companion) oder füge eine Zeichenkette von goldcap.gg ein (/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "dein Spielclient hat keine Schrift für diese Sprache — der Text erscheint als leere Kästchen",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "dein Import ist %d Stunden alt -- die Preise können abweichen. Füge eine frische Zeichenkette von goldcap.gg ein (/goldcap import).",
  ["yours"] = "deiner",
  ["» needs price"] = "» braucht Preis",
  ["×%d in bags"] = "×%d in Taschen",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d in deinen Taschen · Post stellt davon %d ein, den größten Stapel",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d in deinen Taschen · kein Stapel, den GoldCap exakt bestimmen kann",
  ["×%d in your bags, ready to list"] = "×%d in deinen Taschen, bereit zum Einstellen",
  ["×%d listed"] = "×%d eingestellt",
  ["×%d listed at %s each"] = "×%d eingestellt zu je %s",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · gekauft %s · %s · %s",
  ["×%d%s · made %s · %s"] = "×%d%s · hergestellt %s · %s",
  ["— = nothing is checking this row right now"] = "— = diese Zeile wird gerade nicht geprüft",
  ["… = a live check is queued for this row"] =
    "… = für diese Zeile ist eine Live-Prüfung eingereiht",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ goldcap.gg-Marktwert — noch kein Live-Kurs",
  ["no answer %ds ago -- resting"] = "keine Antwort vor %ds -- pausiert",
  ["the last attempt is still settling -- checking the price again..."] =
    "der letzte Versuch ist noch nicht abgeschlossen -- Preis wird erneut geprüft...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "Zu oder unter dem Preis angeboten, den du auf goldcap.gg festgelegt hast (Gruppe: %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "AUTO · PAUSIERT: KAUFFENSTER",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "Pausiert, solange ein Kauffenster offen ist. Kauf oder schließ es, dann läuft Auto weiter.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "AUTO · PAUSIERT: DEINE SUCHE",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "Pausiert, während du im Suchfeld des Auktionshauses tippst. Läuft ein paar Sekunden, nachdem du es verlässt, weiter.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "AUTO · PAUSIERT: POST OFFEN",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "Pausiert, solange der Briefkasten offen ist. Schließ ihn, dann läuft Auto weiter.",
  ["AUTO · PAUSED: SELL TAB"] = "AUTO · PAUSIERT: VERKAUFEN-TAB",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "Pausiert, solange der Verkaufen-Tab offen ist: Er bepreist deine Taschen über dieselbe Suche. Geh zurück zu den Deals, dann läuft Auto weiter.",
  ["AUTO · PAUSED: ITEMS BOARD"] = "AUTO · PAUSIERT: ITEMS-LISTE",
  ["Paused while the Items board is shown: it asks the auction house through the same search. Switch to Commodities and Auto carries on."] =
    "Pausiert, solange die Items-Liste angezeigt wird: Sie fragt das Auktionshaus über dieselbe Suche. Wechsle zu Waren, dann läuft Auto weiter.",
  ["AUTO · PAUSED: BUY TAB"] = "AUTO · PAUSIERT: BUY-TAB",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "Pausiert, solange der BUY-Tab offen ist: Er schlägt Preise über dieselbe Suche nach. Geh zurück zu den Deals, dann läuft Auto weiter.",
  ["AUTO · WAITING FOR YOU"] = "AUTO · WARTET AUF DICH",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "Wartet, während du in den Fenstern des Auktionshauses einstellst, kaufst oder stöberst. Startet, sobald du aufhörst.",
  ["AUTO · WAITING: YOUR LIST"] = "AUTO · WARTET: DEINE LISTE",
  ["Waiting: your own search is on the auction house's Buy list, and a scan would replace it. Open GoldCap's auction house tab, or close the auction house, and Auto starts."] =
    "Wartet: Deine eigene Suche steht in der Kaufliste des Auktionshauses, und ein Scan würde sie ersetzen. Öffne den GoldCap-Tab im Auktionshaus oder schließ das Auktionshaus, dann startet Auto.",
  ["Market %s · unverified until a live Check"] = "Markt %s · ungeprüft bis zu einer Live-Prüfung",
}
