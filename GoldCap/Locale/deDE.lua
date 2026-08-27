local _, GC = ...

-- German. Terminology follows apps/web/messages/de.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.deDE = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d zu je %s  (%s gesamt, %s Gebühr)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion hält das aktuell: /goldcap companion.",
  [" rows against the live auction house about every "] = " Zeilen gegen das laufende Auktionshaus, etwa alle ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · below cost"] = " · unter Einkaufspreis",
  [" · stale %ds"] = " · %ds alt",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — Befehle: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (kurz /gc)",
  ["%d (whole lot)"] = "%d (ganzer Posten)",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d Angebote aus dem letzten Scan -- Full Scan zum Aktualisieren",
  ["%d filtered out as hard to resell"] = "%d als schwer verkäuflich aussortiert",
  ["%d held back"] = "%d zurückgehalten",
  ["%d held back from posting"] = "%d nicht eingestellt",
  ["%d missing"] = "%d fehlen",
  ["%d partial"] = "%d teilweise",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d von der Live-Prüfung abgelehnt -- oben auf \"HIDDEN %d\" klicken, um sie zu sehen",
  ["%d sales · %s proceeds · %s in the mail"] = "%d Verkäufe · %s Erlös · %s in der Post",
  ["%d without a price"] = "%d ohne Preis",
  ["%d without cost"] = "%d ohne Einkaufspreis",
  ["%d · %d/%d covered"] = "%d · %d/%d abgedeckt",
  ["%d/%d covered"] = "%d/%d abgedeckt",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s pro Stück    gesamt %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d Stück%s ohne Einkaufspreis",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "15-60 Sekunden auf vollen Realms. Keine Abklingzeit -- jederzeit erneut scannen.",
  ["24h trend"] = "24h-Trend",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Ein Anhaltspunkt, kein Versprechen: Weiterverkauf zu 95% des importierten Marktwerts, für die Menge, die Check selbst freigeben würde.",
  ["AH answered empty %ds ago"] = "Auktionshaus antwortete vor %ds leer",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · PAUSIERT: ",
  ["Auction House did not answer — press Refresh"] = "Auktionshaus hat nicht geantwortet — Refresh drücken",
  ["Auction House is not open"] = "Auktionshaus ist nicht geöffnet",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Auto: lässt Full Scan durchgehend laufen und tritt sofort zurück, sobald du kaufst, ",
  ["Avoid"] = "Meiden",
  ["Background check"] = "Hintergrundprüfung",
  ["Bundled %s data"] = "Mitgelieferte %s-Daten",
  ["Bundled data"] = "Mitgelieferte Daten",
  ["Buy"] = "Kaufen",
  ["Buy %d × %s for %s"] = "%d × %s für %s kaufen",
  ["CANCEL %d"] = "ABBRECHEN %d",
  ["CANCEL LOT?"] = "POSTEN ABBRECHEN?",
  ["CANCELLING…"] = "WIRD ABGEBROCHEN…",
  ["CONFIRM"] = "BESTÄTIGEN",
  ["CONFIRM PURCHASE"] = "KAUF BESTÄTIGEN",
  ["COST / UNIT"] = "KOSTEN / STÜCK",
  ["Cancel"] = "Abbrechen",
  ["Cancel lot?"] = "Posten abbrechen?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Diesen Posten abbrechen und die Gebühr verlieren — zum Bestätigen erneut klicken",
  ["Cancel timed out"] = "Zeitüberschreitung beim Abbrechen",
  ["Cancelling lot…"] = "Posten wird abgebrochen…",
  ["Cannot post this position"] = "Diese Position kann nicht eingestellt werden",
  ["Cannot remove this entry"] = "Dieser Eintrag kann nicht gelöscht werden",
  ["Cannot repost this lot"] = "Dieser Posten kann nicht neu eingestellt werden",
  ["Check"] = "Prüfen",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check rechnet das am laufenden Orderbuch neu, bevor Gold fließt, und kann niedriger ausfallen — oder ablehnen — wenn sich der Markt seit dem letzten Import bewegt hat.",
  ["Checked: %d of the top %d on screen"] = "Geprüft: %d der obersten %d auf dem Bildschirm",
  ["Checking prices…"] = "Preise werden geprüft…",
  ["Checking this item's price…"] = "Preis dieses Gegenstands wird geprüft…",
  ["Click Confirm to post"] = "Confirm klicken zum Einstellen",
  ["Close"] = "Schließen",
  ["Companion sync rejected:"] = "Companion-Sync abgelehnt:",
  ["Confirm"] = "Bestätigen",
  ["Cost unknown for %d of %d"] = "Einkaufspreis unbekannt für %d von %d",
  ["Could not find the queue's next item to post — try again"] =
    "Nächster Gegenstand der Einstellwarteschlange nicht gefunden — nochmal versuchen",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Nächster Posten der Abbruchwarteschlange nicht gefunden — nochmal versuchen",
  ["DONE"] = "FERTIG",
  ["Duration"] = "Laufzeit",
  ["ENTRY AVG"] = "EINSTIEG Ø",
  ["EST. PROFIT AFTER AH CUT"] = "GESCHÄTZTER GEWINN NACH GEBÜHR",
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
  ["Full pass over them: %.1fs"] = "Ein kompletter Durchlauf: %.1fs",
  ["Full pass over them: measuring..."] = "Ein kompletter Durchlauf: wird gemessen...",
  ["GOOD = solid discount + profit"] = "GOOD = solider Rabatt + Gewinn",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap kann nicht bestimmen, welcher Taschenstapel das ist",
  ["GoldCap data age"] = "Alter der GoldCap-Daten",
  ["GoldCap re-checks the top "] = "GoldCap prüft die obersten ",
  ["GoldCap value"] = "GoldCap-Wert",
  ["GoldCap — Import realm prices"] = "GoldCap — Realmpreise importieren",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: live geprüft -- Kauf ist sicher",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Ausgegraut heißt, der Kurs ist veraltet; Post und Repost aktualisieren ihn vor dem Handeln.",
  ["HIDDEN 0"] = "VERSTECKT 0",
  ["HIDE DETAILS ▾"] = "DETAILS AUSBLENDEN ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = großer Rabatt + hoher Gewinn + belegte Verkäufe/Tag",
  ["Held back from cancelling"] = "Vom Abbrechen zurückgehalten",
  ["Held back from the queue"] = "Aus der Warteschlange zurückgehalten",
  ["ITEM"] = "GEGENSTAND",
  ["Import"] = "Importieren",
  ["Import failed:"] = "Import fehlgeschlagen:",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Installiere den kostenlosen GoldCap Companion, damit Preise automatisch aktuell bleiben (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Das ist der Preis, den du unterbieten musst, um schnell zu verkaufen — nicht der Wert des Gegenstands. Ein Verkäufer in Eile kann ihn weit unter Wert setzen, und GoldCap folgt ihm nicht nach unten: den tatsächlichen Einstellpreis zeigt WHAT TO DO.",
  ["Item"] = "Gegenstand",
  ["Item %d"] = "Gegenstand %d",
  ["LISTED"] = "EINGESTELLT",
  ["LIVE VERDICT · CHECKING"] = "LIVE-URTEIL · PRÜFUNG",
  ["LIVE VERDICT · REFUSED"] = "LIVE-URTEIL · ABGELEHNT",
  ["LIVE VERDICT · SAFE"] = "LIVE-URTEIL · SICHER",
  ["Language"] = "Sprache",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Sprache geändert. Gib /reload ein, damit sie überall greift.",
  ["Last result: %ds ago"] = "Letztes Ergebnis: vor %ds",
  ["Last result: none yet this visit"] = "Letztes Ergebnis: bei diesem Besuch noch keins",
  ["Listed"] = "Eingestellt",
  ["Listed at %s — far below market. Repost."] =
    "Eingestellt zu %s — weit unter Markt. Neu einstellen.",
  ["Listings"] = "Angebote",
  ["Lot cancelled; wait for it to return to bags"] =
    "Posten abgebrochen; warte, bis er in die Taschen zurückkommt",
  ["MARKET / UNIT"] = "MARKT / STÜCK",
  ["Market per unit"] = "Markt pro Stück",
  ["Market reference"] = "Marktreferenz",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "NOCH NICHT AUF GOLDCAP.GG — SYNC BEI /RELOAD ODER LOGOUT",
  ["NOTHING TO CANCEL"] = "NICHTS ABZUBRECHEN",
  ["NOTHING TO POST"] = "NICHTS EINZUSTELLEN",
  ["No deals passed the safety checks right now."] =
    "Gerade hat kein Angebot die Sicherheitsprüfungen bestanden.",
  ["No deals to show -- and no realm prices yet."] =
    "Keine Angebote -- und noch keine Realmpreise.",
  ["No deals yet."] = "Noch keine Angebote.",
  ["No exact auction key"] = "Kein exakter Auktionsschlüssel",
  ["No exact bag stack"] = "Kein exakter Taschenstapel",
  ["No exact bag variant"] = "Keine exakte Taschenvariante",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Noch keine Verkäufe erfasst -- öffne deinen Briefkasten mit geladenem GoldCap",
  ["Not in your bags or listed — mail or bank?"] =
    "Weder in den Taschen noch eingestellt — Post oder Bank?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Nicht greifbar — der Bestand liegt in der Post, der Bank oder auf einem anderen Charakter",
  ["Nothing is being held back."] = "Es wird nichts zurückgehalten.",
  ["Nothing listed on the AH right now"] = "Derzeit nichts im Auktionshaus eingestellt",
  ["Nothing queued to cancel"] = "Nichts zum Abbrechen in der Warteschlange",
  ["Nothing queued to post"] = "Nichts zum Einstellen in der Warteschlange",
  ["Nothing to remove"] = "Nichts zu löschen",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "AUF GOLDCAP.GG — LETZTE %d TAGE",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "AUF GOLDCAP.GG — LETZTE %d TAGE, NEUESTE %d VON %d",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Einmaliger Scan des ganzen Auktionshauses über seitenweise Abfragen. Dauert etwa ",
  ["Open the Auction House first."] = "Öffne zuerst das Auktionshaus.",
  ["Open the Auction House to begin scanning."] = "Öffne das Auktionshaus, um zu scannen.",
  ["Open the deals board. /gc for commands."] = "Öffnet die Angebotsliste. /gc für Befehle.",
  ["POST %d"] = "EINSTELLEN %d",
  ["POSTING…"] = "WIRD EINGESTELLT…",
  ["PRICE ROSE %.1fx"] = "PREIS STIEG UM %.1fx",
  ["PROFIT / UNIT"] = "GEWINN / STÜCK",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Verbinde oder aktualisiere den GoldCap Companion, um Gewinne von goldcap.gg zu sehen",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Füge deine Realm-Zeichenkette von goldcap.gg ein und drücke Import.",
  ["Position scope changed"] = "Positionsbereich geändert",
  ["Positions without a cost or a live price are excluded."] =
    "Positionen ohne Einkaufspreis oder Live-Preis werden nicht mitgezählt.",
  ["Post"] = "Einstellen",
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
  ["Prices up to date"] = "Preise aktuell",
  ["Prices up to date · %d did not answer"] = "Preise aktuell · %d ohne Antwort",
  ["Pricing %d/%d…"] = "Preisabfrage %d/%d…",
  ["Pricing…"] = "Preisabfrage…",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Gewinnverfolgung ist eine goldcap.gg-Pro-Funktion",
  ["QTY"] = "ANZ",
  ["Quantity exceeds missing units"] = "Menge übersteigt die fehlenden Stück",
  ["REALIZED PROFIT"] = "REALISIERTER GEWINN",
  ["REFRESH"] = "AKTUALISIEREN",
  ["RESET WINDOW"] = "FENSTER ZURÜCKSETZEN",
  ["Refresh waiting for prior result"] = "Aktualisierung wartet auf vorheriges Ergebnis",
  ["Refreshing listings…"] = "Angebote werden aktualisiert…",
  ["Refused so far: %d"] = "Bisher abgelehnt: %d",
  ["Removal confirmation expired"] = "Löschbestätigung abgelaufen",
  ["Remove"] = "Löschen",
  ["Remove?"] = "Löschen?",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Löscht jeden von Hand eingetragenen Kauf in dieser Gruppe -- zum Bestätigen erneut klicken",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Löscht diesen von Hand eingetragenen Kauf -- zum Bestätigen erneut klicken",
  ["Repost"] = "Neu einstellen",
  ["Repost confirmation expired"] = "Bestätigung zum Neueinstellen abgelaufen",
  ["Right-click to stop watching this item"] =
    "Rechtsklick, um diesen Gegenstand nicht mehr zu beobachten",
  ["Right-click to watch this item closely"] =
    "Rechtsklick, um diesen Gegenstand genau zu beobachten",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "SOFORT GESPEICHERT · ESC ODER DONE ZUM SCHLIESSEN",
  ["SCAN"] = "SCAN",
  ["SCANNING…"] = "SCANNT…",
  ["SESSION %s%s · %d BUYS"] = "SITZUNG %s%s · %d KÄUFE",
  ["SHOW DETAILS ▸"] = "DETAILS ZEIGEN ▸",
  ["STRESS EXIT"] = "STRESS-AUSSTIEG",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = Rabatt so extrem, dass es eher Betrug oder ein falsch bepreister Markt ist",
  ["Sales are costed from your oldest units first"] =
    "Verkäufe werden zuerst gegen deine ältesten Stück gerechnet",
  ["Set cost"] = "Kosten setzen",
  ["Settings"] = "Einstellungen",
  ["Sold per day"] = "Verkäufe pro Tag",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Danach sortieren, um zu entscheiden, was zuerst geprüft wird — nicht, was gekauft wird.",
  ["Source age"] = "Alter der Quelle",
  ["Stress exit unit"] = "Stress-Ausstiegspreis",
  ["Stress profit"] = "Stress-Gewinn",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Der Companion synchronisiert, aber dieses Addon konnte das Geschriebene nicht lesen:",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Der günstigste Preis, den gerade JEMAND ANDERES verlangt, aus einer Live-Abfrage des Auktionshauses. Deine eigenen Angebote sind ausgenommen, damit die Zahl sich nicht selbst nach unten jagt.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "Der kostenlose Desktop-Companion hält deine Preise automatisch aktuell und synchronisiert deine Verkäufe. Kopiere den Link (Strg+C) und öffne ihn im Browser:",
  ["Unknown"] = "Unbekannt",
  ["Unknown item"] = "Unbekannter Gegenstand",
  ["WATCH (computed SAFE)"] = "WATCH (berechnet SICHER)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = rabattiert, aber Liquidität unbelegt oder Gewinn klein",
  ["WHAT TO DO"] = "WAS ZU TUN IST",
  ["Waiting for Auction House…"] = "Warte auf das Auktionshaus…",
  ["Waiting for a live price"] = "Warte auf einen Live-Preis",
  ["Waiting for the Auction House…"] = "Warte auf das Auktionshaus…",
  ["Waiting for the purchase to finish…"] = "Warte auf den Abschluss des Kaufs…",
  ["Watching closely: %d item%s"] = "Genau beobachtet: %d Gegenstand%s",
  ["Watching — pinned, but not a deal right now"] =
    "Beobachtet — angeheftet, aber gerade kein Angebot",
  ["Window position & size"] = "Fensterposition & -größe",
  ["You paid"] = "Bezahlt",
  ["a discount this extreme usually means the market value is wrong, not that this is a bargain"] =
    "ein so extremer Rabatt heißt meist, dass der Marktwert falsch ist — nicht, dass es ein Schnäppchen ist",
  ["auto off"] = "auto aus",
  ["auto-synced %dh ago"] = "vor %dh automatisch synchronisiert",
  ["auto-synced data for %s loaded (%s old)"] =
    "automatisch synchronisierte Daten für %s geladen (%s alt)",
  ["auto-synced data stale -- /goldcap import"] =
    "automatisch synchronisierte Daten veraltet -- /goldcap import",
  ["auto: paused"] = "auto: pausiert",
  ["big buy"] = "großer Kauf",
  ["bought %d x item %d"] = "%d x Gegenstand %d gekauft",
  ["bought %d x item %d after AH close"] =
    "%d x Gegenstand %d nach Schließen des Auktionshauses gekauft",
  ["buying commodity..."] = "Ware wird gekauft...",
  ["checking live price..."] = "Live-Preis wird geprüft...",
  ["checking live safety..."] = "Live-Sicherheit wird geprüft...",
  ["commodity no longer available -- someone bought it out"] =
    "Ware nicht mehr verfügbar -- jemand hat sie aufgekauft",
  ["commodity purchase failed"] = "Warenkauf fehlgeschlagen",
  ["confirmed commodity purchase failed after AH close"] =
    "bestätigter Warenkauf nach Schließen des Auktionshauses fehlgeschlagen",
  ["confirming purchase..."] = "Kauf wird bestätigt...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "Kostenbasis unvollständig -- Kosten setzen, um einen Rat zum Neueinstellen zu bekommen",
  ["cost unknown"] = "Kosten unbekannt",
  ["data from goldcap.gg · synced %s ago"] = "Daten von goldcap.gg · vor %s synchronisiert",
  ["due -- will be asked next pass"] = "fällig -- wird im nächsten Durchlauf abgefragt",
  ["finish the pending buy first"] = "zuerst den laufenden Kauf abschließen",
  ["full scan already in progress"] = "vollständiger Scan läuft bereits",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "vollständiger Scan fertig: %d Angebot%s aus %d Gegenstandsgruppe%s%s",
  ["full scan interrupted -- confirm your purchase"] =
    "vollständiger Scan unterbrochen -- bestätige deinen Kauf",
  ["full scan stalled -- press Full Scan to retry"] =
    "vollständiger Scan hängt -- Full Scan drücken, um es erneut zu versuchen",
  ["full scan stalled -- retrying shortly"] = "vollständiger Scan hängt -- gleich neuer Versuch",
  ["gone / price changed"] = "weg / Preis geändert",
  ["identity unresolved (variant item -- not priced by design)"] =
    "nicht eindeutig (Variantengegenstand -- absichtlich ohne Preis)",
  ["import %dh old"] = "Import %dh alt",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "Import veraltet -- /goldcap import oder /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "%d Gegenstände für %s (%s) importiert — die Preise sind jetzt aktiv.",
  ["in the mail"] = "in der Post",
  ["item %d"] = "Gegenstand %d",
  ["item %d: %s"] = "Gegenstand %d: %s",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "letzte 24h — %d Verkäufe, %s brutto, %s Auktionsgebühr, %d Käufe, %s ausgegeben",
  ["listing gone -- already bought out or price changed"] =
    "Angebot weg -- bereits aufgekauft oder Preis geändert",
  ["live safety confirmed -- click Buy to purchase"] =
    "Live-Sicherheit bestätigt -- Buy klicken zum Kaufen",
  ["live verification required"] = "Live-Prüfung erforderlich",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "manueller Import -- Companion hält das aktuell: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "braucht einen neuen Preis -- Refresh drücken",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "keine Bestätigung vom Server -- der Kauf kann trotzdem durchgegangen sein, prüfe deine Post. Dieses Fenster zu schließen macht ihn nicht rückgängig.",
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
  ["not ready to cancel"] = "noch nicht bereit zum Abbrechen",
  ["not ready to post"] = "noch nicht bereit zum Einstellen",
  ["nothing listed"] = "nichts eingestellt",
  ["of %d"] = "von %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "oder füge mit /goldcap import eine Zeichenkette von goldcap.gg ein.",
  ["placing bid..."] = "Gebot wird abgegeben...",
  ["price confirmed -- click Buy to purchase"] = "Preis bestätigt -- Buy klicken zum Kaufen",
  ["price rose %.1fx — still safe, confirm"] =
    "Preis stieg um %.1fx — weiterhin sicher, bestätige",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "geladene Preise sind %s (%s), du spielst aber in %s — jeder Rabatt und Gewinn wird an einem anderen Markt gemessen",
  ["purchase canceled"] = "Kauf abgebrochen",
  ["purchase pending exact cost"] = "Kauf wartet auf genaue Kosten",
  ["purchase total unavailable — inspect mailbox"] =
    "Kaufsumme nicht verfügbar — sieh in deinen Briefkasten",
  ["quote %s -- click Confirm to buy"] = "Kurs %s -- Confirm klicken zum Kaufen",
  ["quote %ss ago"] = "Kurs vor %ss",
  ["quote expired -- Refresh to re-check the price"] =
    "Kurs abgelaufen -- Refresh, um den Preis erneut zu prüfen",
  ["recent sales (newest first):"] = "letzte Verkäufe (neueste zuerst):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "Region %s — mitgeliefert: %d Gegenstände (%s), importiert: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "Region bei %d Buchungen korrigiert; %d Verkäufe wieder ihrem Bestand zugeordnet",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "jetzt neu einzustellen würde einen Verlust oder Stillstand festschreiben -- halten",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "%d doppelte Kaufeinträge%s entfernt, die ein Fehler beim Postscan hinterlassen hat",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "%d doppelte Verkaufseinträge%s entfernt, die ein Fehler beim Postscan hinterlassen hat",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    "s. Abgelehnte Zeilen werden ausgeblendet. Kaufen bleibt immer ein Klick, den du machst.",
  ["sale proceeds pending"] = "Verkaufserlös ausstehend",
  ["scanned %d listings over %d passes"] = "%d Angebote in %d Durchläufen gescannt",
  ["scanning auction house..."] = "Auktionshaus wird gescannt...",
  ["scanning… %d results · %d deals%s"] = "scannt… %d Ergebnisse · %d Angebote%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "durchsuche das Auktionshaus selbst oder sieh in deine Post. Klick zum Umschalten.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "verkauft %s/Tag",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "Sitzung: %d Zugriffe, %s ausgegeben, ~%s gesch. Gewinn",
  ["sniped (listing changed on rescan)"] = "weggeschnappt (Angebot beim erneuten Scan geändert)",
  ["starting full scan..."] = "vollständiger Scan startet...",
  ["stopped watching %s"] = "%s wird nicht mehr beobachtet",
  ["the Companion wrote prices this addon could not read --"] =
    "der Companion hat Preise geschrieben, die dieses Addon nicht lesen konnte --",
  ["the import failed (%s)"] = "der Import ist fehlgeschlagen (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["unknown evidence"] = "unbekannter Nachweis",
  ["waiting for previous commodity purchase to settle"] =
    "warte, bis der vorherige Warenkauf abgeschlossen ist",
  ["waiting for previous search result to settle"] = "warte auf das vorherige Suchergebnis",
  ["waiting for server... full scan will start automatically"] =
    "warte auf den Server... der vollständige Scan startet automatisch",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s wird genau beobachtet -- alle paar Sekunden neu geprüft",
  ["would sell at a loss"] = "würde mit Verlust verkaufen",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "du hast noch keine Realmpreise importiert -- installiere GoldCap Companion (/goldcap companion) oder füge eine Zeichenkette von goldcap.gg ein (/goldcap import).",
  ["you should clear about %s"] = "du solltest etwa %s übrig behalten",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "dein Import ist %d Stunden alt -- die Preise können abweichen. Füge eine frische Zeichenkette von goldcap.gg ein (/goldcap import).",
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
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ goldcap.gg-Marktwert — noch kein Live-Kurs",
}
