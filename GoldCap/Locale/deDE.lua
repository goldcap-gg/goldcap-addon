local _, GC = ...

-- German. Terminology follows apps/web/messages/de.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.deDE = {
  ["  %s · need %d · have %d · buy %d · %s"] = "  %s · Bedarf %d · vorhanden %d · kaufen %d · %s",
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d zu je %s  (%s gesamt, %s Gebühr)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion hält das aktuell: /goldcap companion.",
  [" · %d keys"] = " · %d Schlüssel",
  [" · below cost"] = " · unter Einkaufspreis",
  [" · identity unresolved"] = " · Zuordnung ungeklärt",
  [" · stale %ds"] = " · %ds alt",
  [" — Check again"] = " — erneut prüfen",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — Befehle: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (kurz /gc)",
  ["%d (whole lot)"] = "%d (ganzer Posten)",
  ["%d ahead of you"] = "%d vor dir",
  ["%d at %s"] = "%d zu %s",
  ["%d caps · %s"] = "%d Preisdeckel · %s",
  ["%d days"] = "%d Tage",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d Angebote aus dem letzten Scan -- Full Scan zum Aktualisieren",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "%d aussortiert: schwer verkäuflich oder unter deinem Mindestgewinn pro Kauf",
  ["%d held back"] = "%d zurückgehalten",
  ["%d held back from posting"] = "%d nicht eingestellt",
  ["%d hidden -- the live check refused them"] = "%d ausgeblendet -- die Live-Prüfung hat sie abgelehnt",
  ["%d hits"] = "%d Treffer",
  ["%d in %d lots"] = "%d in %d Posten",
  ["%d in 1 lot"] = "%d in 1 Posten",
  ["%d lines"] = "%d Zeilen",
  ["%d lots, %s asked"] = "%d Posten, %s verlangt",
  ["%d of %d"] = "%d von %d",
  ["%d of %d at or under your cap"] = "%d von %d zu deinem Deckel oder darunter",
  ["%d of %d done"] = "%d von %d erledigt",
  ["%d prices in one request · books still loading"] =
    "%d Preise in einer Anfrage · Orderbücher laden noch",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d von der Live-Prüfung abgelehnt -- oben auf \"HIDDEN %d\" klicken, um sie zu sehen",
  ["%d units"] = "%d Stück",
  ["%d units · %d prices"] = "%d Stück · %d Preise",
  ["%d · %d/%d covered"] = "%d · %d/%d abgedeckt",
  ["%d/%d covered"] = "%d/%d abgedeckt",
  ["%d× %s"] = "%d× %s",
  ["%d× %s · %s each · %s"] = "%d× %s · %s pro Stück · %s",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s pro Stück    gesamt %s -> %s",
  ["%s ahead"] = "%s davor",
  ["%s needs a number, for example /gc weights %s 1.5"] = "%s braucht eine Zahl, zum Beispiel /gc weights %s 1.5",
  ["%s under you"] = "%s unter dir",
  ["%s units in %d prices"] = "%s Stück · %d Preise",
  ["%s · %s under market"] = "%s · %s unter Markt",
  ["%s · at market price"] = "%s · zum Marktpreis",
  ["%s — %d unit%s without a cost"] = "%s — %d Stück%s ohne Einkaufspreis",
  ["%s → craft %d× (%d per craft)"] = "%s → %d× herstellen (%d pro Herstellung)",
  ["%s+ ahead"] = "%s+ davor",
  ["%s+, %d prices read"] = "%s+ in %d Preisen",
  ["..."] = "...",
  ["1 lot, %s asked"] = "1 Posten, %s verlangt",
  ["24h trend"] = "24h-Trend",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Ein Strich heißt, GoldCap kennt noch nicht die Kosten jeder Einheit — es rät sie nie aus dem Marktpreis.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Ein Anhaltspunkt, kein Versprechen: Weiterverkauf zu 95% des importierten Marktwerts, für die Menge, die Check selbst freigeben würde.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Sind mehrere Käufe zu einer Zeile zusammengefasst, werden alle davon entfernt.",
  ["AH answered empty %ds ago"] = "Auktionshaus antwortete vor %ds leer",
  ["AH value"] = "AH-Wert",
  ["AH, cheapest version"] = "AH, günstigste Version",
  ["AUTO"] = "AUTO",
  ["AUTO · SCANNING"] = "AUTO · SCANNT",
  ["AUTOMATION & ALERTS"] = "AUTOMATIK & HINWEISE",
  ["AVOID"] = "MEIDEN",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Über diesem 24-Stunden-Anstieg gilt der Marktwert als Ausreißer nach oben und wird gedämpft.",
  ["Above your price -- quoted %s, your price %s"] = "Über deinem Preis -- Angebot %s, dein Preis %s",
  ["Alert target"] = "Alarmziel",
  ["Alerts"] = "Alarme",
  ["All"] = "Alle",
  ["Archive this run"] = "Diese Liste archivieren",
  ["Archived"] = "Archiviert",
  ["Asks for a second click to confirm."] = "Verlangt einen zweiten Klick zur Bestätigung.",
  ["At a vendor"] = "Beim Händler",
  ["At your pace you reach it at level %d."] = "In deinem Tempo erreichst du es auf Stufe %d.",
  ["At your pace you will be %s short at level 40."] = "In deinem Tempo fehlen dir auf Stufe 40 noch %s.",
  ["At your price"] = "Zu deinem Preis",
  ["Auction House did not answer — press Refresh"] = "Auktionshaus hat nicht geantwortet — Refresh drücken",
  ["Auction House is not open"] = "Auktionshaus ist nicht geöffnet",
  ["Auto-scan on next AH visit"] = "Auto-Scan beim nächsten AH-Besuch",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: lässt Full Scan durchgehend laufen und tritt sofort zurück, sobald du kaufst, durchsuche das Auktionshaus selbst oder sieh in deine Post. Klick zum Umschalten.",
  ["Avoid"] = "Meiden",
  ["BOOKS %d/%d"] = "BÜCHER %d/%d",
  ["BRAKES"] = "BREMSEN",
  ["BUY %d"] = "KAUFEN %d",
  ["BUY — unverified"] = "KAUFEN — ungeprüft",
  ["Background check"] = "Hintergrundprüfung",
  ["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."] =
    "Blizzard hat die Reitkosten noch nicht veröffentlicht. Gib /gc mount und die erwarteten Kosten ein.",
  ["Blizzard's price: %s"] = "Preis von Blizzard: %s",
  ["Blizzard's price: %s · %d s left"] = "Preis von Blizzard: %s · noch %d s",
  ["Bought"] = "Gekauft",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Der Break-even ist der niedrigste Preis, der nach der Auktionshausgebühr noch deine Kosten deckt. Darunter machst du Verlust.",
  ["Bundled %s data"] = "Mitgelieferte %s-Daten",
  ["Bundled data"] = "Mitgelieferte Daten",
  ["Buy"] = "Kaufen",
  ["Buy it whole instead"] = "Lieber ganz kaufen",
  ["Buy less"] = "Weniger kaufen",
  ["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"] = "Kaufen: %s · %d Zeilen · %d zu kaufen · %d beim Händler · ausgegeben %s · übrig ~%s",
  ["Buy: no run selected."] = "Kaufen: keine Liste gewählt.",
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
  ["Cap for %s"] = "Deckel für %s",
  ["Cap: %d%%"] = "Deckel: %d%%",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Begrenzt davon, wie schnell sich das wirklich verkauft, nicht von deinem Geldbeutel.",
  ["Change the cap…"] = "Deckel ändern…",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Es liegen noch günstigere Angebote, aber beim Tempo dieses Gegenstands sind sie in Stunden weg.",
  ["Check"] = "Prüfen",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check rechnet das am laufenden Orderbuch neu, bevor Gold fließt, und kann niedriger ausfallen — oder ablehnen — wenn sich der Markt seit dem letzten Import bewegt hat.",
  ["Checked against the live order book a moment ago."] =
    "Gerade eben gegen das laufende Orderbuch geprüft.",
  ["Checked: %d of the top %d on screen"] = "Geprüft: %d der obersten %d auf dem Bildschirm",
  ["Checking prices…"] = "Preise werden geprüft…",
  ["Checking prices — waiting for the Auction House…"] = "Preise werden geprüft — warte auf das Auktionshaus…",
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
  ["Confirm"] = "Bestätigen",
  ["Confirm the cancel"] = "Abbruch bestätigen",
  ["Confirm the removal"] = "Löschen bestätigen",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Kopiere den Link (Strg+C) und öffne ihn im Browser:",
  ["Copy vendor list"] = "Händlerliste kopieren",
  ["Cost per unit"] = "Kosten pro Stück",
  ["Cost unknown for %d of %d"] = "Einkaufspreis unbekannt für %d von %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Kostet mehr, als dein Limit pro Kauf zulässt.",
  ["Could not read that amount. Type it like 12g 50s."] = "Dieser Betrag ist nicht lesbar. Gib ihn so ein: 12g 50s.",
  ["Don't skip"] = "Nicht überspringen",
  ["Everything here is bought"] = "Hier ist alles gekauft",
  ["From goldcap.gg — manage it there"] = "Von goldcap.gg — dort verwalten",
  ["From your scan %s ago. Counts only %s. Change with /gc weights."] =
    "Aus deinem Scan vor %s. Zählt nur %s. Ändern mit /gc weights.",
  ["Gear upgrades on the auction house"] = "Ausrüstungs-Upgrades im Auktionshaus",
  ["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."] =
    "GoldCap zählt jetzt, was bei deiner Beute fällt, ohne Namen, für Dropraten auf goldcap.gg. Der Companion teilt es, sobald dieser Teil erscheint. Tippe /gc loot off, um es zu beenden.",
  ["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."] =
    "Gegenstände in deinen Taschen, die im Auktionshaus mehr bringen als beim Händler: %d (%s mehr).",
  ["Items still loading: %d. Open this again in a moment."] =
    "Gegenstände, die noch laden: %d. Öffne dies gleich noch einmal.",
  ["Loot counting is off. Type /gc loot clear to remove what was recorded."] =
    "Beutezählung ist aus. Tippe /gc loot clear, um das Aufgezeichnete zu entfernen.",
  ["Loot counting is on."] = "Beutezählung ist an.",
  ["Loot record cleared."] = "Beuteaufzeichnung gelöscht.",
  ["Market"] = "Markt",
  ["Mount cost cleared."] = "Reitkosten gelöscht.",
  ["Mount cost set to %s."] = "Reitkosten auf %s gesetzt.",
  ["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] =
    "Noch kein Scan mit Ausrüstung. Öffne das Auktionshaus und lass GoldCap es scannen.",
  ["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] =
    "Für deine Klasse gibt es noch keine Wertgewichte. Setze sie so: /gc weights STR 1 STA 0.5",
  ["Nothing on the auction house beats what you wear at your level."] =
    "Nichts im Auktionshaus schlägt deine Ausrüstung auf deiner Stufe.",
  ["Nothing on this list matches."] = "Nichts auf dieser Liste passt.",
  ["Over cap"] = "Über dem Deckel",
  ["PRICE EACH"] = "PREIS PRO STÜCK",
  ["Play a little longer for an estimate of your pace."] =
    "Spiel noch etwas weiter, dann gibt es eine Schätzung deines Tempos.",
  ["RAISE CAP TO %s"] = "DECKEL AUF %s",
  ["ROAD TO 40"] = "WEG ZU STUFE 40",
  ["Raise cap to %s"] = "Deckel auf %s anheben",
  ["Restore %s"] = "%s wiederherstellen",
  ["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."] =
    "Weg zu Stufe 40 mit GoldCap: %s von %s für mein Reittier (%d%%).",
  ["Road to 40: %s of %s (gold %s, bags %s)."] = "Weg zu Stufe 40: %s von %s (Gold %s, Taschen %s).",
  ["Road to 40: you have %s (gold %s, bags %s)."] = "Weg zu Stufe 40: Du hast %s (Gold %s, Taschen %s).",
  ["Runs"] = "Listen",
  ["Set cap"] = "Deckel setzen",
  ["Skip"] = "Überspringen",
  ["Skip for now"] = "Vorerst überspringen",
  ["Skipped"] = "Übersprungen",
  ["Split into reagents (craft %d×)"] = "In Reagenzien aufteilen (%d× herstellen)",
  ["Stat weights: %s"] = "Wertgewichte: %s",
  ["TO BUY HERE"] = "HIER ZU KAUFEN",
  ["The rest is skipped for now"] = "Der Rest ist vorerst übersprungen",
  ["This client does not report item stats, so GoldCap cannot compare gear."] =
    "Dieser Client liefert keine Gegenstandswerte, daher kann GoldCap keine Ausrüstung vergleichen.",
  ["This lot holds more units than your Max units per buy."] =
    "Dieser Posten hat mehr Stück als dein „Max. Stück pro Kauf“.",
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
  ["Everything else checks out. With more gold on this character, this is a buy."] = "Alles andere passt. Mit mehr Gold auf diesem Charakter wäre das ein Kauf.",
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
  ["GoldCap: checked live -- a deal, but you need %s on this character"] = "GoldCap: live geprüft -- ein gutes Angebot, aber du brauchst %s auf diesem Charakter",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: live geprüft -- Kauf ist sicher",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: noch nicht gegen das laufende Auktionshaus geprüft",
  ["Gone"] = "Weg",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Ausgegraut heißt, der Kurs ist veraltet; Post und Repost aktualisieren ihn vor dem Handeln.",
  ["HIDDEN 0"] = "VERSTECKT 0",
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
  ["Last post may still go up -- wait a minute"] = "Einstellen läuft evtl. noch -- warte 1 Minute",
  ["Level 40 reached: %s to go."] = "Stufe 40 erreicht: noch %s.",
  ["Last result: %ds ago"] = "Letztes Ergebnis: vor %ds",
  ["Last result: none yet this visit"] = "Letztes Ergebnis: bei diesem Besuch noch keins",
  ["Listed"] = "Eingestellt",
  ["Listed at %s — far below market. Repost."] =
    "Eingestellt zu %s — weit unter Markt. Neu einstellen.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Zu oder unter dem Preis angeboten, den du auf goldcap.gg festgelegt hast. Ob es sich weiterverkaufen lässt, schätzt du selbst ein.",
  ["Listed value"] = "Eingestellter Wert",
  ["Listings"] = "Angebote",
  ["Lists this item at the price on its row: the whole bag for a commodity, one stack for a regular item, or the number under HOW MANY."] =
    "Stellt diesen Gegenstand zum Preis in seiner Zeile ein: eine Handelsware als gesamter Taschenbestand, ein normaler Gegenstand als ein Stapel, oder die Zahl unter ANZAHL.",
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
  ["Min profit per buy (copper)"] = "Mindestgewinn pro Kauf (Kupfer)",
  ["To buy"] = "Zu kaufen",
  ["To craft"] = "Herzustellen",
  ["Total: %s"] = "Gesamt: %s",
  ["Unknown stat %s. Use one of: %s"] = "Unbekannter Wert %s. Nutze einen von: %s",
  ["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."] =
    "Upgrades für deine Ausrüstung im Auktionshaus: %d. Tippe /gc upgrades, um sie zu sehen.",
  ["Use the default cap"] = "Standarddeckel verwenden",
  ["While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead."] = "Solange dieser Wert beim Standard von 5 % bleibt, darf ein Fund mit Händlerpreis bis zur Hälfte deines Geldes verwenden.",
  ["Min return per buy %"] = "Min. Rendite pro Kauf %",
  ["Missing cost"] = "Kosten fehlen",
  ["NO LIVE PRICE YET"] = "NOCH KEIN LIVE-PREIS",
  ["YOUR LISTS"] = "DEINE LISTEN",
  ["NOT ON HAND %d"] = "NICHT ZUR HAND %d",
  ["NOTHING TO CANCEL"] = "NICHTS ABZUBRECHEN",
  ["Needs a live price check before it can be bought."] =
    "Braucht eine Live-Preisprüfung, bevor es gekauft werden kann.",
  ["Needs gold"] = "Braucht Gold",
  ["Never spend more than this share of your gold on one purchase."] =
    "Nie mehr als diesen Anteil deines Goldes für einen einzigen Kauf ausgeben.",
  ["No answer yet -- listening for a minute"] = "Noch keine Antwort -- wir warten eine Minute",
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
  ["Not enough gold on this character to buy what GoldCap finds"] = "Zu wenig Gold auf diesem Charakter, um die Funde zu kaufen",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Im Auktionshaus liegen nicht genug Einheiten für diese Menge.",
  ["Not in your bags or listed — mail or bank?"] =
    "Weder in den Taschen noch eingestellt — Post oder Bank?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Nicht greifbar — der Bestand liegt in der Post, der Bank oder auf einem anderen Charakter",
  ["Not worth the deposit on the AH"] = "Lohnt die AH-Gebühr nicht",
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
  ["ON THE AUCTION HOUSE"] = "IM AUKTIONSHAUS",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Einmaliger Scan des ganzen Auktionshauses über seitenweise Abfragen. Dauert etwa 15-60 Sekunden auf vollen Realms. Keine Abklingzeit -- jederzeit erneut scannen.",
  ["Open the Auction House first."] = "Öffne zuerst das Auktionshaus.",
  ["Open the Auction House to begin scanning."] = "Öffne das Auktionshaus, um zu scannen.",
  ["Open the deals board. /gc for commands."] = "Öffnet die Angebotsliste. /gc für Befehle.",
  ["POSTING"] = "EINSTELLEN",
  ["POSTING…"] = "SENDEN…",
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
  ["Post"] = "Einstellen",
  ["Post above the cheapest"] = "Über dem Günstigsten anbieten",
  ["Post confirmation expired"] = "Bestätigung zum Einstellen abgelaufen",
  ["Post the next queued item"] = "Nächsten Gegenstand aus der Warteschlange einstellen",
  ["Posted"] = "Eingestellt",
  ["Posting failed"] = "Einstellen fehlgeschlagen",
  ["Posting unavailable"] = "Einstellen nicht möglich",
  ["Posting…"] = "Senden…",
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
  ["Press Buy again to buy this quantity"] = "Klicke erneut auf Kaufen, um diese Stückzahl zu kaufen",
  ["QTY"] = "ANZ",
  ["Quantity exceeds missing units"] = "Menge übersteigt die fehlenden Stück",
  ["Quantity is capped by how fast this item actually sells."] =
    "Die Menge ist dadurch begrenzt, wie schnell sich der Gegenstand wirklich verkauft.",
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
  ["Sales are costed from your oldest units first"] =
    "Verkäufe werden zuerst gegen deine ältesten Stück gerechnet",
  ["Search"] = "Suche",
  ["Sales evidence"] = "Verkaufsdaten",
  ["Sell it on the AH"] = "Beim AH verkaufen",
  ["Sell it on the AH (deposit not counted)"] = "Beim AH verkaufen (Gebühr nicht eingerechnet)",
  ["Sell it to a vendor"] = "Beim Händler verkaufen",
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
  ["Source"] = "Quelle",
  ["Source age"] = "Alter der Quelle",
  ["Spike-trend threshold %"] = "Schwelle für Kursspitze %",
  ["Start scanning as soon as the auction house opens."] =
    "Sofort mit dem Scannen beginnen, sobald das Auktionshaus öffnet.",
  ["Status"] = "Status",
  ["Stop and open the buy window on your price"] = "Bei deinem Preis stoppen und Kauffenster öffnen",
  ["Stress exit unit"] = "Stress-Ausstiegspreis",
  ["Stress profit"] = "Stress-Gewinn",
  ["THE BOOK"] = "DAS ORDERBUCH",
  ["TREND"] = "TREND",
  ["Tell GoldCap what you actually paid for these units."] =
    "Sag GoldCap, was du für diese Einheiten tatsächlich bezahlt hast.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "Das Auktionshaus nannte keine Einstellgebühr, also sind die Kosten unbekannt.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Der Companion synchronisiert, aber dieses Addon konnte das Geschriebene nicht lesen:",
  ["The auction house did not answer -- try again"] =
    "Auktionshaus hat nicht geantwortet -- nochmal versuchen",
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
  ["What this buy would make is under your minimum profit."] =
    "Was dieser Kauf einbringen würde, liegt unter deinem Mindestgewinn.",
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
  ["WAITING FOR THE AUCTION HOUSE %d"] = "WARTET AUFS AUKTIONSHAUS %d",
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
  ["You can pay for it now."] = "Du kannst es dir jetzt leisten.",
  ["You paid"] = "Bezahlt",
  ["You pay"] = "Du zahlst",
  ["You would get"] = "Du bekämst",
  ["You would pay"] = "Du zahltest",
  ["Your call"] = "Deine Entscheidung",
  ["Your cap"] = "Dein Deckel",
  ["Your gold has not grown lately, so there is no pace to estimate."] =
    "Dein Gold ist zuletzt nicht gewachsen, daher gibt es kein Tempo zu schätzen.",
  ["Your minimum"] = "Dein Minimum",
  ["Your price"] = "Dein Preis",
  ["a purchase landed that GoldCap could not attribute"] = "ein Kauf kam an, den GoldCap keiner Zeile zuordnen konnte",
  ["a purchase landed that GoldCap could not price"] = "ein Kauf kam an, dessen Preis GoldCap nicht kennt",
  ["a unit, at or under your price of %s"] = "pro Stück, zu oder unter deinem Preis von %s",
  ["a vendor sells it"] = "ein Händler verkauft es",
  ["a vendor sells it for %s each"] = "ein Händler verkauft es für %s pro Stück",
  ["a vendor sells it for %s each · the auction house asks %s"] = "ein Händler verkauft es für %s pro Stück · das Auktionshaus verlangt %s",
  ["alert group · %d hits"] = "Alarmgruppe · %d Treffer",
  ["already in your bags and bank"] = "schon in Taschen und Bank",
  ["another purchase is in flight"] = "ein anderer Kauf läuft noch",
  ["at a vendor"] = "beim Händler",
  ["at a vendor · %s each"] = "beim Händler · %s pro Stück",
  ["at level %d"] = "ab Stufe %d",
  ["bought"] = "gekauft",
  ["bought %d for %s"] = "%d gekauft für %s",
  ["buy %d of %d"] = "%d von %d kaufen",
  ["buy %d of %d, have %d in bags and bank"] = "%d von %d kaufen, %d in Taschen und Bank",
  ["buying..."] = "kaufe...",
  ["cap: alert target"] = "Deckel: Alarmziel",
  ["cheapest seen %s"] = "am günstigsten gesehen: %s",
  ["confirming..."] = "bestätige...",
  ["craft"] = "herstellen",
  ["craft it for %s each"] = "herstellen für %s pro Stück",
  ["craft it for %s each · %s here"] = "herstellen für %s pro Stück · hier %s",
  ["craft it yourself"] = "stell es selbst her",
  ["craft it · %s each"] = "herstellen · %s pro Stück",
  ["craft it: %s = %s each"] = "herstellen: %s = %s pro Stück",
  ["deals %s · items %s · filtered %s"] = "Angebote %s · Gegenstände %s · aussortiert %s",
  ["done"] = "erledigt",
  ["from %s"] = "von %s",
  ["in bags %d · in bank %d"] = "in Taschen %d · in der Bank %d",
  ["includes %d for crafting %s"] = "davon %d zum Herstellen von %s",
  ["no answer — check your mail"] = "keine Antwort — sieh in der Post nach",
  ["nothing at or under your cap of %s"] = "nichts zu deinem Deckel von %s oder darunter",
  ["nothing on offer"] = "nichts im Angebot",
  ["on %s"] = "auf %s",
  ["over your cap"] = "über deinem Deckel",
  ["over your cap · %s"] = "über deinem Deckel · %s",
  ["plan updated on goldcap.gg"] = "Plan auf goldcap.gg aktualisiert",
  ["price moved to %s"] = "Preis jetzt %s",
  ["purchase failed — try again"] = "Kauf fehlgeschlagen — versuch es noch mal",
  ["right-click to skip or change the cap"] = "Rechtsklick zum Überspringen oder Ändern des Deckels",
  ["seen %s ago"] = "vor %s gesehen",
  ["skipped for now"] = "vorerst übersprungen",
  ["skipped for this session, it stays on the list"] = "für diese Sitzung übersprungen, bleibt auf der Liste",
  ["still on the list: %d at a vendor · %d to craft"] = "noch auf der Liste: %d beim Händler · %d herzustellen",
  ["sure profit: a vendor pays %s each"] =
    "sicherer Gewinn: ein Händler zahlt %s pro Stück",
  ["resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown"] =
    "Wiederverkauf zum Scan-AH-Wert, %s/Stück, abzgl. 5%% Provision und Gebühr; Tempo unbekannt",
  ["Checked against the live auction house a moment ago."] =
    "Eben mit dem Live-Auktionshaus abgeglichen.",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "über dem Günstigsten, im günstigen Viertel · %s Einheiten vor dir",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "über dem Günstigsten, innerhalb der Tagesreichweite · %s Einheiten vor dir",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "gegen den Regionspreis dieses Gegenstands, nach 5% Gebühr — falls er sich verkauft",
  ["age %ss"] = "vor %ss",
  ["another purchase took over -- nothing was confirmed"] =
    "ein anderer Kauf hat übernommen -- nichts wurde bestätigt",
  ["any figure here would be invented out of the very number being refused"] =
    "jede Zahl hier wäre aus genau dem Wert erfunden, der gerade abgelehnt wird",
  ["at or under your price -- click Buy to purchase"] =
    "zu oder unter deinem Preis -- Buy klicken zum Kaufen",
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
  ["checking live price..."] = "Live-Preis wird geprüft...",
  ["checking live safety..."] = "Live-Sicherheit wird geprüft...",
  ["clears in ~%dd"] = "weg in ~%d Tg.",
  ["clears in ~%dh"] = "weg in ~%d Std.",
  ["commodity purchase failed"] = "Warenkauf fehlgeschlagen",
  ["confirmed commodity purchase failed after AH close"] =
    "bestätigter Warenkauf nach Schließen des Auktionshauses fehlgeschlagen",
  ["confirming purchase..."] = "Kauf wird bestätigt...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "Kostenbasis unvollständig -- Kosten setzen, um einen Rat zum Neueinstellen zu bekommen",
  ["crafted %s"] = "hergestellt %s",
  ["due -- will be asked next pass"] = "fällig -- wird im nächsten Durchlauf abgefragt",
  ["fair"] = "brauchbar",
  ["far below market"] = "weit unter Markt",
  ["finish the pending buy first"] = "zuerst den laufenden Kauf abschließen",
  ["first in line"] = "als Erster dran",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "Kostet %s. Mit deinem Limit pro Kauf von %d%% brauchst du %s auf diesem Charakter.",
  ["fresh"] = "aktuell",
  ["full scan already in progress"] = "vollständiger Scan läuft bereits",
  ["full scan interrupted -- confirm your purchase"] =
    "vollständiger Scan unterbrochen -- bestätige deinen Kauf",
  ["full scan stalled -- press Full Scan to retry"] =
    "vollständiger Scan hängt -- Full Scan drücken, um es erneut zu versuchen",
  ["full scan stalled -- retrying shortly"] = "vollständiger Scan hängt -- gleich neuer Versuch",
  ["full scan stopped -- press %s to run it again"] =
    "vollständiger Scan angehalten -- %s drücken, um ihn erneut zu starten",
  ["gone / price changed"] = "weg / Preis geändert",
  ["goldcap.gg prices for WoW: Forever are not out yet."] =
    "goldcap.gg-Preise für WoW: Forever gibt es noch nicht.",
  ["strong"] = "solide",
  ["hold"] = "halten",
  ["identity unresolved (variant item -- not priced by design)"] =
    "nicht eindeutig (Variantengegenstand -- absichtlich ohne Preis)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "wenn du alle %d kaufst und zum aktuell dort stehenden Preis wieder verkaufst",
  ["ilvl %d"] = "GS %d",
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
  ["last live price %s ago"] = "letzter Live-Preis vor %s",
  ["leave these alone"] = "diese in Ruhe lassen",
  ["level %d"] = "Stufe %d",
  ["listing gone -- already bought out or price changed"] =
    "Angebot weg -- bereits aufgekauft oder Preis geändert",
  ["listing gone -- bought out or repriced"] = "Angebot weg -- gekauft oder neu bepreist",
  ["live safety confirmed -- click Buy to purchase"] =
    "Live-Sicherheit bestätigt -- Buy klicken zum Kaufen",
  ["live verification required"] = "Live-Prüfung erforderlich",
  ["the cheapest is %s, your cap is %s"] = "am günstigsten: %s, dein Deckel: %s",
  ["the run changed — start again"] = "die Liste hat sich geändert — fang neu an",
  ["took too long — try again"] = "hat zu lange gedauert — versuch es noch mal",
  ["usually cheapest around %s · %d%%"] = "meist am günstigsten gegen %s · %d%%",
  ["vendor"] = "Händler",
  ["vs %s at the auction house · right-click to buy it whole"] = "gegenüber %s im Auktionshaus · Rechtsklick, um es ganz zu kaufen",
  ["vs %s at the auction house · right-click to split"] = "gegenüber %s im Auktionshaus · Rechtsklick zum Aufteilen",
  ["weak"] = "dünn",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "manueller Import -- Companion hält das aktuell: /goldcap companion",
  ["market %s"] = "Markt %s",
  ["needs %s"] = "%s nötig",
  ["needs a fresh price -- press Refresh"] = "braucht einen neuen Preis -- Refresh drücken",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "keine Bestätigung vom Server -- der Kauf kann trotzdem durchgegangen sein, prüfe deine Post. Dieses Fenster zu schließen macht ihn nicht rückgängig.",
  ["no cost"] = "kein Einstand",
  ["no cost for %d"] = "kein Einstand für %d",
  ["no live price yet"] = "noch kein Live-Preis",
  ["no live price"] = "kein Live-Preis",
  ["no live quote yet — pricing…"] = "noch kein Live-Kurs — Preis wird ermittelt…",
  ["no market figure for caged pets"] = "keine Marktdaten für Haustiere im Käfig",
  ["no market figure for this item level"] = "keine Marktdaten für diese Gegenstandsstufe",
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
  ["not enough gold on this character -- you need %s"] = "nicht genug Gold auf diesem Charakter -- du brauchst %s",
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "nicht genug Einheiten für diese Menge übrig -- prüfe erneut, was noch da ist...",
  ["not priced — nothing on hand to sell"] = "kein Preis — nichts zum Verkaufen vorrätig",
  ["not ready to cancel"] = "noch nicht bereit zum Abbrechen",
  ["not ready to post"] = "noch nicht bereit zum Einstellen",
  ["nothing listed"] = "nichts eingestellt",
  ["of %d"] = "von %d",
  ["off"] = "aus",
  ["oldest units sell first"] = "die ältesten Einheiten verkaufen sich zuerst",
  ["on"] = "ein",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "öffne das Auktionshaus einmal, damit GoldCap weiß, wie sich diese verkaufen",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "oder füge mit /goldcap import eine Zeichenkette von goldcap.gg ein.",
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
  ["price stands %d of %d"] = "Preis steht %d von %d",
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
  ["quote expires in %d s -- click Confirm to buy"] =
    "Kurs läuft in %d s ab -- Confirm klicken, um zu kaufen",
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
  ["scanned %d listings over %d passes"] = "%d Angebote in %d Durchläufen gescannt",
  ["scanning auction house..."] = "Auktionshaus wird gescannt...",
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
  ["the auction house has not sent details for these yet"] =
    "das Auktionshaus hat dazu noch keine Details geschickt",
  ["the import failed (%s)"] = "der Import ist fehlgeschlagen (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "um %d Stück bei %s Verkäufen pro Tag abzustoßen, mit %s die ganze Zeit gebunden",
  ["unavailable"] = "nicht verfügbar",
  ["under GoldCap's own floor of %s"] = "unter GoldCaps eigener Untergrenze von %s",
  ["unknown evidence"] = "unbekannter Nachweis",
  ["waiting for previous commodity purchase to settle"] =
    "warte, bis der vorherige Warenkauf abgeschlossen ist",
  ["waiting for previous search result to settle"] = "warte auf das vorherige Suchergebnis",
  ["waiting..."] = "warte...",
  ["wall"] = "Wand",
  ["wall %s at %s -- price under it to sell first"] =
    "Wand %s bei %s -- darunter anbieten, um zuerst zu verkaufen",
  ["wall %s at %s above you"] = "Wand %s bei %s über dir",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s wird genau beobachtet -- alle paar Sekunden neu geprüft",
  ["worst case, selling all %d back into the price standing there now"] =
    "im schlimmsten Fall, wenn du alle %d zum aktuell dort stehenden Preis zurückverkaufst",
  ["worth cancelling"] = "Abbruch lohnt sich",
  ["would sell at a loss"] = "würde mit Verlust verkaufen",
  ["you have enough gold for this now -- Check again"] = "jetzt ist genug Gold dafür da -- Check klicken zum erneuten Prüfen",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "du hast noch keine Realmpreise importiert -- installiere GoldCap Companion (/goldcap companion) oder füge eine Zeichenkette von goldcap.gg ein (/goldcap import).",
  ["you take %d"] = "du nimmst %d",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "dein Spielclient hat keine Schrift für diese Sprache — der Text erscheint als leere Kästchen",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "dein Import ist %d Stunden alt -- die Preise können abweichen. Füge eine frische Zeichenkette von goldcap.gg ein (/goldcap import).",
  ["your price is above every level shown"] = "dein Preis liegt über allen Stufen",
  ["your scan, %s ago"] = "dein Scan, vor %s",
  ["yours"] = "deiner",
  ["yours ×%s"] = "deins ×%s",
  ["~%dd to reach you"] = "~%d Tg. bis zu dir",
  ["~%dh to reach you"] = "~%d Std. bis zu dir",
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
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "Marktdaten der Region: %d Handelswaren, %d mit Verkaufsdaten, %d Realm-Gegenstände (%s alt, %d KB)",
  ["whole-market data not in use: %s"] = "Marktdaten der Region nicht in Verwendung: %s",
  ["it is %s old, and the prices you imported are newer"] = "sie sind %s alt, und deine importierten Preise sind neuer",
  ["it is for another region than the prices loaded"] = "sie gehören zu einer anderen Region als die geladenen Preise",
  ["its date cannot be right -- check this computer's clock"] =
    "ihr Datum kann nicht stimmen -- prüfe die Uhr dieses Computers",
  ["it was set aside when other prices were loaded this session -- /reload to use it again"] =
    "sie wurden zurückgestellt, als in dieser Sitzung andere Preise geladen wurden -- /reload, um sie wieder zu nutzen",
  ["On the AH now"] = "Im AH",
  ["%s listed · %d min ago"] = "%s eingestellt · vor %d Min.",
  ["%s listed · just now"] = "%s eingestellt · gerade eben",
  ["it could not be read (%s)"] = "sie ließen sich nicht lesen (%s)",
  ["it is for a region this build of GoldCap does not know -- update the addon"] =
    "sie gehören zu einer Region, die diese GoldCap-Version nicht kennt -- aktualisiere das Addon",
  ["it is in a format this build of GoldCap cannot read -- update the addon"] =
    "sie liegen in einem Format vor, das diese GoldCap-Version nicht lesen kann -- aktualisiere das Addon",
  ["it is larger than this build of GoldCap can read -- update the addon"] =
    "sie sind größer, als diese GoldCap-Version lesen kann -- aktualisiere das Addon",
  ["the Companion wrote an empty copy -- let it sync, then /reload"] =
    "der Companion hat sie ohne Inhalt gespeichert -- lass ihn synchronisieren und mache dann /reload",
  ["the Companion wrote it with no prices -- let it sync, then /reload"] =
    "der Companion hat sie ohne Preise gespeichert -- lass ihn synchronisieren und mache dann /reload",
  ["Scanning the auction house…"] = "Scanne das Auktionshaus…",
  ["%s lots scanned -- shared on your next /reload"] =
    "%s Posten gescannt -- werden bei deinem nächsten /reload geteilt",
  ["%s lots scanned and saved"] = "%s Posten gescannt und gespeichert",
  ["%s items scanned -- shared on your next /reload"] =
    "%s Gegenstände gescannt -- werden bei deinem nächsten /reload geteilt",
  ["%s items scanned and saved"] = "%s Gegenstände gescannt und gespeichert",
  ["The full scan is cooling down (%d min left) -- scanning by browsing instead"] =
    "Der vollständige Scan hat noch Abklingzeit (noch %d Min.) -- es wird stattdessen durchsucht",
  ["The auction house did not answer the full scan -- scanning by browsing instead"] =
    "Das Auktionshaus hat auf den vollständigen Scan nicht geantwortet -- es wird stattdessen durchsucht",
  ["reading the auction house: %s of %s lots"] = "durchsuche das Auktionshaus: %s von %s Posten",
  ["The scan found nothing to save"] = "Der Scan hat nichts zum Speichern gefunden",
  ["Scans the whole auction house for prices: a full list at most once every 15 minutes, browsing in between. GoldCap also scans when you open the auction house."] =
    "Durchsucht das gesamte Auktionshaus nach Preisen: eine vollständige Liste höchstens alle 15 Minuten, dazwischen wird durchsucht. GoldCap scannt auch, wenn du das Auktionshaus öffnest.",
  -- Core/ForeverValue.lua's PrintBags/BagTotals and Core/PostQueue.lua's below_vendor: the
  -- POST queue holding back what a vendor pays at least as much for.
  ["Your bags: %s at a vendor, %s on the AH after its cut"] =
    "Deine Taschen: %s beim Händler, %s auf dem AH nach Gebühr",
  ["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."] =
    "Die Schaltfläche EINSTELLEN im Verkaufen-Tab listet alles, was mehr wert ist als der Händler zahlt, ein Klick pro Posten.",
  ["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."] =
    "Deine Taschen: %s beim Händler. Scanne das Auktionshaus, um zu sehen, was sie dort bringen würden.",
  ["a vendor pays more -- sell it there"] =
    "der Händler zahlt mehr -- verkauf es dort",
  ["vendor pays more"] =
    "Händler zahlt mehr",
  ["Below vendor"] =
    "Unter NPC",
  ["Under market"] =
    "Unter Markt",
  [" · buy at %s or less, vendor pays %s"] =
    " · kaufen für %s oder weniger, Händler zahlt %s",
  [" · buy at %s or less, AH value %s"] =
    " · kaufen für %s oder weniger, AH-Wert %s",
  ["Buy at or under %s: a vendor pays %s each. This buy makes %s."] =
    "Kaufe für %s oder weniger: Ein Händler zahlt %s pro Stück. Dieser Kauf bringt %s.",
  ["Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit."] =
    "Kaufe für %s oder weniger: Der AH-Wert, den das günstigste Zehntel der gelisteten Stückzahl verlangt, liegt bei %s. Wie schnell es weiterverkauft wird, ist ungewiss, das macht diesen Kauf riskanter als ein Händlergeschäft. Nach 5%% Provision und der Gebühr bringt dieser Kauf etwa %s.",
  ["under the vendor price -- click Buy to purchase"] =
    "unter dem Händlerpreis -- Buy klicken zum Kaufen",
  ["far under the market, resale speed unknown -- click Buy to purchase"] =
    "weit unter Marktpreis, Weiterverkaufstempo unbekannt -- Buy klicken zum Kaufen",
  ["No deals in your last scan."] =
    "Keine Angebote in deinem letzten Scan.",
  ["Deals appear as soon as the scan finds them."] =
    "Angebote erscheinen, sobald der Scan sie findet.",
  ["GoldCap looks for items listed cheaper than they are worth. SCAN looks again."] =
    "GoldCap sucht nach Gegenständen, die billiger gelistet sind, als sie wert sind. SCAN scannt erneut.",
  ["No scan of this auction house yet."] =
    "Noch kein Scan dieses Auktionshauses.",
  ["GoldCap scans when you open the auction house; SCAN on this board scans again."] =
    "GoldCap scannt, wenn du das Auktionshaus öffnest; SCAN auf diesem Board scannt erneut.",
  ["In WoW: Forever, GoldCap's prices come from your own auction house scans."] =
    "In WoW: Forever kommen GoldCaps Preise aus deinen eigenen Auktionshaus-Scans.",
  ["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."] =
    "Öffne das Auktionshaus, und GoldCap scannt es für dich; SCAN im Deals-Tab scannt erneut.",
  ["%ds"] = "%d Sek.",
  ["%dm"] = "%d Min.",
  ["%dh"] = "%d Std.",
  ["%dd"] = "%d T.",
  -- WoW: Forever crowd prices (UI/Tooltip.lua, plan 3d).
  ["1 scanner, %s ago"] = "1 Scanner, vor %s",
  ["%d scanners, %s ago"] = "%d Scanner, vor %s",
  ["resale at the AH value of players' scans, %s each, after the 5%% cut and deposit; speed unknown"] = "Wiederverkauf zum AH-Wert der Spieler-Scans, %s pro Stück, abzgl. 5%% Provision und Gebühr; Tempo unbekannt",
  ["Shared with goldcap.gg on your next /reload"] = "Wird beim nächsten /reload mit goldcap.gg geteilt",
  ["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."] = "Deine Scans bleiben auf diesem Computer. Der GoldCap Companion teilt sie mit goldcap.gg und bringt die Preise aller zurück.",
  ["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."] = "Der GoldCap Companion teilt deine Scans nach jedem /reload mit goldcap.gg und bringt die Preise aller zurück.",
  ["You opened %s -- its first %s prices are yours."] =
    "Du hast %s eröffnet -- die ersten %s Preise dort stammen von dir.",
  ["Your scan updated %s prices on %s -- %s of them nobody else had in the last 24 hours."] =
    "Dein Scan hat %s Preise auf %s aktualisiert -- %s davon hatte in den letzten 24 Stunden sonst niemand.",
  ["Your scan updated %s prices on %s."] =
    "Dein Scan hat %s Preise auf %s aktualisiert.",
  -- Sold tab: tiles, period chips, search, day groups and the sale tooltip.
  ["%d DAYS"] = "%d TAGE",
  ["TODAY"] = "HEUTE",
  ["YESTERDAY"] = "GESTERN",
  ["SUN"] = "SO",
  ["MON"] = "MO",
  ["TUE"] = "DI",
  ["WED"] = "MI",
  ["THU"] = "DO",
  ["FRI"] = "FR",
  ["SAT"] = "SA",
  ["YOU GOT"] = "ERHALTEN",
  ["YOU GOT · %s"] = "ERHALTEN · %s",
  ["EACH"] = "STÜCK",
  ["%d sales · after the AH cut"] = "%d Verkäufe · nach AH-Gebühr",
  ["1 sale · after the AH cut"] = "1 Verkauf · nach AH-Gebühr",
  ["%d here · all on goldcap.gg"] = "%d hier · alle auf goldcap.gg",
  ["cost known for %d of %d"] = "Kosten bekannt bei %d von %d",
  ["%s of %s"] = "%s von %s",
  ["%s · gold %s, bags %s"] = "%s · Gold %s, Taschen %s",
  ["set the riding cost: %s"] = "Reitkosten festlegen: %s",
  ["GOLDCAP.GG · %d DAYS"] = "GOLDCAP.GG · %d TAGE",
  ["profit · synced %s ago"] = "Gewinn · Sync vor %s",
  ["after the AH cut · synced %s ago"] = "nach AH-Gebühr · Sync vor %s",
  ["BEST SALE"] = "BESTER VERKAUF",
  ["%s profit"] = "%s Gewinn",
  ["no sale with a known profit yet"] = "noch kein Verkauf mit bekanntem Gewinn",
  ["OPEN SELL"] = "SELL ÖFFNEN",
  ["Find an item"] = "Gegenstand suchen",
  ["JUST SOLD"] = "GERADE VERKAUFT",
  ["reaches goldcap.gg on /reload or logout"] = "kommt bei /reload oder Logout auf goldcap.gg an",
  ["ON GOLDCAP.GG"] = "AUF GOLDCAP.GG",
  ["latest %d of %d · the rest on goldcap.gg"] = "neueste %d von %d · der Rest auf goldcap.gg",
  ["last %d days"] = "letzte %d Tage",
  ["%d sales · %s"] = "%d Verkäufe · %s",
  ["1 sale · %s"] = "1 Verkauf · %s",
  ["sold today at %s · %d × %s"] = "heute um %s verkauft · %d × %s",
  ["sold %s at %s · %d × %s"] = "verkauft am %s um %s · %d × %s",
  ["sold, the money is in your mail · %d × %s"] = "verkauft, das Gold liegt in der Post · %d × %s",
  ["Sale price"] = "Verkaufspreis",
  ["Auction house cut"] = "AH-Gebühr",
  ["Auction house cut, 5%"] = "AH-Gebühr, 5 %",
  ["You got"] = "Erhalten",
  ["You paid (%s)"] = "Bezahlt (%s)",
  ["%s each"] = "%s pro Stück",
  ["Sniper"] = "Sniper",
  ["BUY list"] = "BUY-Liste",
  ["set by you"] = "von dir eingetragen",
  ["the auction house"] = "Auktionshaus",
  ["crafted"] = "hergestellt",
  ["The profit is worked out once the money arrives."] = "Der Gewinn wird berechnet, sobald das Gold ankommt.",
  ["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."] =
    "GoldCap hat diesen Kauf nie gesehen, daher gibt es keinen Gewinn anzuzeigen. Trag in SELL ein, was er dich gekostet hat.",
  ["Market now %s · you sold %d%% above it"] = "Markt jetzt %s · du hast %d%% darüber verkauft",
  ["Market now %s · you sold %d%% under it"] = "Markt jetzt %s · du hast %d%% darunter verkauft",
  ["Market now %s · you sold at it"] = "Markt jetzt %s · du hast genau dazu verkauft",
  ["Your sales show up here once you open a mailbox with GoldCap loaded."] =
    "Deine Verkäufe erscheinen hier, sobald du mit geladenem GoldCap einen Briefkasten öffnest.",
  ["List something in SELL first."] = "Stell zuerst etwas in SELL ein.",
  ["No sales match “%s” today."] = "Heute keine Verkäufe zu „%s“.",
  ["No sales match “%s” in these %d days."] = "Keine Verkäufe zu „%s“ in diesen %d Tagen.",
  ["No sales today."] = "Heute keine Verkäufe.",
  ["No sales in these %d days."] = "Keine Verkäufe in diesen %d Tagen.",
  ["SEARCH 30 DAYS"] = "30 TAGE DURCHSUCHEN",
  ["SHOW 30 DAYS"] = "30 TAGE ZEIGEN",
  ["▲%d%% over the alert target"] = "▲%d%% über dem Alarmziel",
  ["▲%d%% over usual"] = "▲%d%% über üblich",
  ["▲%d%% over your cap"] = "▲%d%% über deinem Deckel",
  -- The quest reward mark (UI/QuestRewardMark.lua).
  ["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."] =
    "GoldCap: Die Belohnung im goldenen Rahmen ist im Auktionshaus am meisten wert (%s).",
  -- The vendor note (UI/MerchantNote.lua).
  ["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."] =
    "1 Gegenstand in deinen Taschen bringt im Auktionshaus mehr ein (+%s). Behalte ihn fürs Auktionshaus.",
  ["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."] =
    "%d Gegenstände in deinen Taschen bringen im Auktionshaus mehr ein (+%s). Behalte sie fürs Auktionshaus.",
  -- BUY 2.0 week 2: a gear line is bought one lot per press (UI/BuyFrame.lua).
  ["BUY ONE · %s"] = "EINS KAUFEN · %s",
  ["not enough gold"] = "nicht genug Gold",
  ["set a cap first"] = "erst einen Deckel setzen",
  -- BUY 2.0 week 2: a gear line's lots on the dock (UI/BuyFrame.lua).
  ["%s · %d lots"] = "%s · %d Lose",
  ["%s · 1 lot"] = "%s · 1 Los",
  ["%s · over your cap"] = "%s · über deinem Deckel",
  ["no cap for this item — right-click the line to set one"] =
    "kein Deckel für diesen Gegenstand — Rechtsklick auf die Zeile setzt einen",
  -- BUY 2.0 week 2: the vendor panel beside the merchant (UI/BuyVendorPanel.lua).
  ["BUY %d · %s"] = "KAUFEN %d · %s",
  ["BUY · %s"] = "KAUFEN · %s",
  -- BUY 2.0: the item box and the quick list (UI/BuyFrame.lua).
  ["Could not find that item. Shift-click it, or type its item id."] =
    "Gegenstand nicht gefunden. Mit Umschalt+Klick einfügen oder die Item-ID eingeben.",
  ["Item to add"] = "Gegenstand hinzufügen",
  ["Make a list once, buy it here at or under your price."] =
    "Einmal eine Liste anlegen, hier zu deinem Preis oder darunter kaufen.",
  ["Remove from the list"] = "Von der Liste entfernen",
  ["or plan a whole profession on goldcap.gg"] = "oder plane einen ganzen Beruf auf goldcap.gg",
  -- BUY 2.0: the item box's hint, with the x count (UI/BuyFrame.lua).
  -- Glyphs every face that draws them has (spec/client_text_spec.lua's glyph inventory).
  ["HIDE DETAILS ▲"] = "DETAILS AUSBLENDEN ▲",
  ["SHOW DETAILS ▼"] = "DETAILS ZEIGEN ▼",
  ["plan updated on goldcap.gg · +%d -%d lines"] =
    "Plan auf goldcap.gg aktualisiert · +%d -%d Zeilen",
  ["~ goldcap.gg market value — no live quote yet"] =
    "~ goldcap.gg-Marktwert — noch kein Live-Kurs",
  ["• %s"] = "• %s",
  ["→ needs price"] = "→ braucht Preis",
  -- BUY 2.0: lists made in the game -- New, Import, Export, Rename, favourites, order, Delete
  ["Items the game has not loaded yet are left out: %d. Export again in a moment."] =
    "%d Gegenstände hat das Spiel noch nicht geladen, sie fehlen. Gleich noch einmal exportieren.",
  ["%s and %d more"] = "%s und %d weitere",
  ["+ New"] = "+ Neu",
  ["Add to favourites"] = "Zu Favoriten hinzufügen",
  ["Added %d items to %s."] = "%d Gegenstände zu %s hinzugefügt.",
  ["Added %d× %s to %s."] = "%d× %s zu %s hinzugefügt.",
  ["Added %d× %s to a new list, %s."] = "%d× %s zu einer neuen Liste hinzugefügt: %s.",
  ["Copy as a TSM item list"] = "Als TSM-Itemliste kopieren",
  ["Copy for Auctionator"] = "Für Auctionator kopieren",
  ["Delete"] = "Löschen",
  ["Delete %s? This cannot be undone."] = "%s löschen? Das lässt sich nicht rückgängig machen.",
  ["Delete this list…"] = "Diese Liste löschen…",
  ["Export"] = "Exportieren",
  ["From goldcap.gg — rename or remove it there"] =
    "Von goldcap.gg — dort umbenennen oder entfernen",
  ["GoldCap — Import a list"] = "GoldCap — Liste importieren",
  ["Import a list…"] = "Liste importieren…",
  ["Import into this list…"] = "In diese Liste importieren…",
  ["Imported %s with %d items."] = "%s mit %d Gegenständen importiert.",
  ["List %d"] = "Liste %d",
  ["Lists come from goldcap.gg through the companion, or make one here with + New."] =
    "Listen kommen über den Companion von goldcap.gg — oder hier mit + Neu eine anlegen.",
  ["Lists: click to switch, make, import or export one"] =
    "Listen: klicken zum Wechseln, Anlegen, Importieren oder Exportieren",
  ["Move down"] = "Nach unten",
  ["Move up"] = "Nach oben",
  ["Name this list"] = "Name der Liste",
  ["New list"] = "Neue Liste",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import."] =
    "Eine Liste von goldcap.gg, TSM oder Auctionator einfügen und Importieren drücken.",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."] =
    "Eine Liste von goldcap.gg, TSM oder Auctionator einfügen und Importieren drücken. Ihre Gegenstände kommen zu %s.",
  ["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."] =
    "Mit Strg+C kopieren, dann in Auctionator im Tab „Einkaufen“ importieren.",
  ["Press Ctrl+C to copy, then import it into a TSM group."] =
    "Mit Strg+C kopieren, dann in eine TSM-Gruppe importieren.",
  ["Remove from favourites"] = "Aus Favoriten entfernen",
  ["Rename…"] = "Umbenennen…",
  ["Save"] = "Speichern",
  ["The game could not tell which items these are: %s. Shift-click them into the item box instead."] =
    "Das Spiel konnte diese Gegenstände nicht zuordnen: %s. Stattdessen mit Umschalt+Klick ins Gegenstandsfeld einfügen.",
  ["There are no items in this list."] = "In dieser Liste sind keine Gegenstände.",
  ["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."] =
    "Das ist der gepackte Gruppenexport von TSM, den nur TSM entpacken kann. Auf goldcap.gg/list einfügen, dort „Als TSM-Gruppe kopieren“ drücken und das Ergebnis hier einfügen.",
  ["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."] =
    "Das ist keine Liste, die GoldCap lesen kann. Eine Liste von goldcap.gg, TSM oder Auctionator einfügen.",
  ["in game"] = "im Spiel",
  -- Buy runs: the import result and the vendor list, now that the BUY tab's lists use them.
  ["The run's vendor reagents. Press Ctrl+C to copy the list."] =
    "Die Händler-Reagenzien der Liste. Mit Strg+C kopieren.",
  ["Vendor list"] = "Händlerliste",
  ["run imported: %s (%d lines)"] = "Liste importiert: %s (%d Zeilen)",
  ["the run string is not valid"] = "die Listenzeichenfolge ist ungültig",
  -- BUY: a gear line's tooltip names the lot it buys next (UI/BuyFrame.lua).
  ["next to buy: %s"] = "nächster Kauf: %s",
  -- BUY: the item box at the top -- several items at once, typed names, recents (UI/BuyAddBox.lua).
  ["Add"] = "Hinzufügen",
  ["Added %d items to a new list, %s."] = "%d Gegenstände zu einer neuen Liste hinzugefügt: %s.",
  ["Clear"] = "Leeren",
  ["Could not read: %s."] = "Nicht lesbar: %s.",
  ["Items to add: %d — %s"] = "Hinzuzufügen: %d — %s",
  ["Recent:"] = "Zuletzt:",
  ["Shift-click items, type a name, or an item id with x and a count: 2589 x20."] =
    "Gegenstände mit Umschalt+Klick einfügen, einen Namen eingeben oder eine Item-ID mit x und Anzahl: 2589 x20.",
  -- BUY search: what is on sale, the results, opening one and adding it to a list (UI/BuySearch.lua).
  ["AVAILABLE"] = "VERFÜGBAR",
  ["Add to list…"] = "Zur Liste hinzufügen…",
  ["Back to %s"] = "Zurück zu %s",
  ["Click to buy it here. Right-click to add it to a list."] =
    "Klicken, um es hier zu kaufen. Rechtsklick, um es zu einer Liste hinzuzufügen.",
  ["Close search"] = "Suche schließen",
  ["How many"] = "Wie viele",
  ["How many of %s?"] = "Wie viele %s?",
  ["Loading more results…"] = "Weitere Ergebnisse werden geladen…",
  ["More results"] = "Weitere Ergebnisse",
  ["Nothing on sale for “%s”."] = "Für „%s“ wird nichts angeboten.",
  ["On sale for “%s”: %d"] = "Treffer für „%s“: %d",
  ["Open the auction house to search what's on sale."] =
    "Öffne das Auktionshaus, um das Angebot zu durchsuchen.",
  ["PRICE FROM"] = "PREIS AB",
  ["Search again"] = "Erneut suchen",
  ["Searching the auction house for “%s”…"] = "Suche im Auktionshaus nach „%s“…",
  ["The auction house did not answer. Search again."] =
    "Das Auktionshaus hat nicht geantwortet. Suche erneut.",
  ["Type a whole number."] = "Gib eine ganze Zahl ein.",
  ["Waiting for the auction house…"] = "Warte auf das Auktionshaus…",
  -- Craft costs: which reagent had no price and why, and the merchant as a source of cost
  -- (Core/CraftCapture.lua, Core/VendorBuys.lua).
  ["this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed"] =
    "dieses Rezept macht aus einer Zutat mehrere verschiedene Gegenstände (Sondieren, Zermalmen, Mahlen), darum bekommt es keine Kosten",
  ["%s ×%d: no purchase of it found, here or on your other characters"] =
    "%s ×%d: kein Kauf gefunden, weder hier noch bei deinen anderen Charakteren",
  ["%s ×%d: only %d of them were bought, the rest has no price"] =
    "%s ×%d: nur %d davon wurden gekauft, für den Rest gibt es keinen Preis",
  ["%s ×%d: made by prospecting, crushing or milling, not bought"] =
    "%s ×%d: durch Sondieren, Zermalmen oder Mahlen entstanden, nicht gekauft",
  ["%s ×%d: bought as different variants, so which one was used is unclear"] =
    "%s ×%d: als verschiedene Varianten gekauft, darum ist unklar, welche benutzt wurde",
  ["%s: %d at the vendor price, %s each"] =
    "%s: %d zum Händlerpreis von je %s",
  ["%s: priced from another character's purchases"] =
    "%s: nach den Käufen eines anderen Charakters bepreist",
  ["%s: %d at the market price, %s each"] =
    "%s: %d zum Marktpreis von je %s",
  ["Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price"] =
    "Ein Teil dieser Kosten ist eine Schätzung: Reagenzien, die du nicht gekauft hast, werden zu ihrem aktuellen Auktionshauspreis gerechnet",
  ["Vendor"] =
    "Händler",
  ["SELLING %d"] = "VERKAUFE %d",
  ["NOT SELLING %d"] = "VERKAUFE NICHT %d",
  ["POST lists these"] = "EINSTELLEN stellt diese ein",
  ["click one to post it"] = "zum Einstellen anklicken",
  ["Selling"] = "Verkaufe",
  ["Not selling"] = "Verkaufe nicht",
  ["POST lists it, and so does the key for posting the next item."] = "EINSTELLEN stellt es ein, ebenso die Taste für den nächsten Gegenstand.",
  ["POST passes it by. Click the item to post it from the bar below."] = "EINSTELLEN lässt es aus. Klicke auf den Gegenstand, um ihn unten in der Leiste einzustellen.",
  ["Marked for you: you bought it on DEALS."] = "Für dich markiert: du hast es unter DEALS gekauft.",
  ["Click to change."] = "Klicken zum Ändern.",
  ["Done for this visit"] = "Für diesen Besuch erledigt",
  ["POST passes it by until you close the auction house. Click to have POST list it again."] =
    "EINSTELLEN lässt es aus, bis du das Auktionshaus schließt. Klicke, damit EINSTELLEN es wieder einstellt.",
  ["Mark what to sell with the circle"] = "Markiere mit dem Kreis, was du verkaufen willst",
  ["PROCEEDS"] = "ERLÖS",
  ["What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut."] = "Was alles, was EINSTELLEN einstellt, zu diesen Preisen einbringt, nach der Gebühr des Auktionshauses von 5 %.",
  ["What your lots bring in if they all sell, after the auction house's 5% cut."] = "Was deine Auktionen einbringen, wenn alle verkauft werden, nach der Gebühr des Auktionshauses von 5 %.",
  ["PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it."] = "ERLÖS abzüglich dessen, was du für diese Ware bezahlt hast. Nur sichtbar, solange GoldCap weiß, was du für alles bezahlt hast.",
  ["HOW MANY"] = "ANZAHL",
  ["MAX"] = "MAX",
  ["skipped"] = "übersprungen",
  ["posted"] = "eingestellt",
  ["POST"] = "EINSTELLEN",
  ["SKIP"] = "AUSLASSEN",
  ["then %s"] = "danach %s",
}
