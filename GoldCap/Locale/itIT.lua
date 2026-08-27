local _, GC = ...

-- Italian. Terminology follows apps/web/messages/it.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.itIT = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s l'uno  (%s in totale, %s di commissione)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion lo tiene aggiornato: /goldcap companion.",
  [" rows against the live auction house about every "] =
    " righe contro la casa d'aste dal vivo, all'incirca ogni ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · below cost"] = " · sotto il costo",
  [" · stale %ds"] = " · vecchio di %ds",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — comandi: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (o /gc in breve)",
  ["%d (whole lot)"] = "%d (lotto intero)",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d occasioni dall'ultima scansione -- Full Scan per aggiornare",
  ["%d filtered out as hard to resell"] = "%d scartate perché difficili da rivendere",
  ["%d held back"] = "%d trattenute",
  ["%d held back from posting"] = "%d non messe in vendita",
  ["%d missing"] = "ne mancano %d",
  ["%d partial"] = "%d parziali",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d rifiutate dal controllo dal vivo -- premi \"HIDDEN %d\" sopra per vederle",
  ["%d sales · %s proceeds · %s in the mail"] = "%d vendite · %s di ricavo · %s nella posta",
  ["%d without a price"] = "%d senza prezzo",
  ["%d without cost"] = "%d senza costo",
  ["%d · %d/%d covered"] = "%d · %d/%d coperti",
  ["%d/%d covered"] = "%d/%d coperti",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s per unità    totale %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d unità%s senza costo",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Da 15 a 60 secondi sui reami affollati. Nessuna attesa -- riscansiona quando vuoi.",
  ["24h trend"] = "Andamento 24h",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Un indizio, non una promessa: rivendita al 95% del valore di mercato importato, per la quantità che Check stesso approverebbe.",
  ["AH answered empty %ds ago"] = "la casa d'aste ha risposto vuota %ds fa",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · IN PAUSA: ",
  ["Auction House did not answer — press Refresh"] =
    "La casa d'aste non ha risposto — premi Refresh",
  ["Auction House is not open"] = "La casa d'aste non è aperta",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Auto: tiene Full Scan sempre attivo e cede subito il passo quando compri, ",
  ["Avoid"] = "Da evitare",
  ["Background check"] = "Controllo in background",
  ["Bundled %s data"] = "Dati %s inclusi",
  ["Bundled data"] = "Dati inclusi",
  ["Buy"] = "Compra",
  ["Buy %d × %s for %s"] = "Compra %d × %s per %s",
  ["CANCEL %d"] = "ANNULLA %d",
  ["CANCEL LOT?"] = "ANNULLARE IL LOTTO?",
  ["CANCELLING…"] = "ANNULLAMENTO…",
  ["CONFIRM"] = "CONFERMA",
  ["CONFIRM PURCHASE"] = "CONFERMA L'ACQUISTO",
  ["COST / UNIT"] = "COSTO / UNITÀ",
  ["Cancel"] = "Annulla",
  ["Cancel lot?"] = "Annullare il lotto?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Annulla questo lotto e perdi la cauzione — clicca di nuovo per confermare",
  ["Cancel timed out"] = "Annullamento scaduto",
  ["Cancelling lot…"] = "Annullamento del lotto…",
  ["Cannot post this position"] = "Impossibile mettere in vendita questa posizione",
  ["Cannot remove this entry"] = "Impossibile eliminare questa voce",
  ["Cannot repost this lot"] = "Impossibile rimettere in vendita questo lotto",
  ["Check"] = "Controlla",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check ricalcola sul book degli ordini dal vivo prima che l'oro si muova, e può comunque risultare più basso — o rifiutare — se il mercato si è mosso dall'ultima importazione.",
  ["Checked: %d of the top %d on screen"] = "Controllate: %d delle prime %d a schermo",
  ["Checking prices…"] = "Controllo dei prezzi…",
  ["Checking this item's price…"] = "Controllo del prezzo di questo oggetto…",
  ["Click Confirm to post"] = "Clicca Confirm per mettere in vendita",
  ["Close"] = "Chiudi",
  ["Companion sync rejected:"] = "Sincronizzazione Companion rifiutata:",
  ["Confirm"] = "Conferma",
  ["Cost unknown for %d of %d"] = "Costo sconosciuto per %d su %d",
  ["Could not find the queue's next item to post — try again"] =
    "Non trovo il prossimo oggetto in coda da mettere in vendita — riprova",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Non trovo il prossimo lotto in coda da annullare — riprova",
  ["DONE"] = "FATTO",
  ["Duration"] = "Durata",
  ["ENTRY AVG"] = "INGRESSO MEDIO",
  ["EST. PROFIT AFTER AH CUT"] = "PROFITTO STIM. DOPO LA COMMISSIONE",
  ["Enlarge the window to see details"] = "Ingrandisci la finestra per vedere i dettagli",
  ["Enter a whole quantity"] = "Inserisci una quantità intera",
  ["Enter an exact positive cost"] = "Inserisci un costo esatto e positivo",
  ["Entry price (avg fill)"] = "Prezzo d'ingresso (esecuzione media)",
  ["Entry total"] = "Totale d'ingresso",
  ["Est. profit"] = "Profitto stim.",
  ["FIFO allocations"] = "Allocazioni FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Sto recuperando un prezzo aggiornato per questo oggetto — ripremi Post tra un istante",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Sto recuperando un prezzo aggiornato per questo lotto — ripremi Repost tra un istante",
  ["Finish the pending post first"] = "Completa prima la vendita in corso",
  ["Finish the pending post or repost first"] =
    "Completa prima la vendita o la rimessa in vendita in corso",
  ["Font scale"] = "Dimensione del carattere",
  ["Full pass over them: %.1fs"] = "Passaggio completo: %.1fs",
  ["Full pass over them: measuring..."] = "Passaggio completo: misurazione...",
  ["GOOD = solid discount + profit"] = "GOOD = sconto solido + profitto",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap non riesce a stabilire quale pila della borsa sia questa",
  ["GoldCap data age"] = "Età dei dati GoldCap",
  ["GoldCap re-checks the top "] = "GoldCap ricontrolla le prime ",
  ["GoldCap value"] = "Valore GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Importa i prezzi del reame",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: controllato dal vivo -- acquisto sicuro",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "In grigio significa che la quotazione è invecchiata; Post e Repost la aggiornano prima di agire.",
  ["HIDDEN 0"] = "NASCOSTE 0",
  ["HIDE DETAILS ▾"] = "NASCONDI DETTAGLI ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = sconto forte + profitto alto + vendite/giorno dimostrate",
  ["Held back from cancelling"] = "Trattenuto dall'annullamento",
  ["Held back from the queue"] = "Trattenuto dalla coda",
  ["ITEM"] = "OGGETTO",
  ["Import"] = "Importa",
  ["Import failed:"] = "Importazione fallita:",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Installa il GoldCap Companion gratuito per tenere i prezzi aggiornati da soli (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "È il prezzo da battere per vendere in fretta, non quanto vale l'oggetto. Un venditore di fretta può metterlo molto sotto il valore, e GoldCap non lo seguirà al ribasso: guarda WHAT TO DO per il prezzo a cui metterebbe davvero in vendita.",
  ["Item"] = "Oggetto",
  ["Item %d"] = "Oggetto %d",
  ["LISTED"] = "IN VENDITA",
  ["LIVE VERDICT · CHECKING"] = "VERDETTO DAL VIVO · CONTROLLO",
  ["LIVE VERDICT · REFUSED"] = "VERDETTO DAL VIVO · RIFIUTATO",
  ["LIVE VERDICT · SAFE"] = "VERDETTO DAL VIVO · SICURO",
  ["Language"] = "Lingua",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Lingua cambiata. Digita /reload per applicarla ovunque.",
  ["Last result: %ds ago"] = "Ultimo risultato: %ds fa",
  ["Last result: none yet this visit"] = "Ultimo risultato: nessuno in questa visita",
  ["Listed at %s — far below market. Repost."] =
    "In vendita a %s — molto sotto mercato. Rimettilo in vendita.",
  ["Listings"] = "Vendite",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lotto annullato; aspetta che torni nelle borse",
  ["MARKET / UNIT"] = "MERCATO / UNITÀ",
  ["Market per unit"] = "Mercato per unità",
  ["Market reference"] = "Riferimento di mercato",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "NON ANCORA SU GOLDCAP.GG — SI SINCRONIZZA CON /RELOAD O ALL'USCITA",
  ["NOTHING TO CANCEL"] = "NIENTE DA ANNULLARE",
  ["NOTHING TO POST"] = "NIENTE DA METTERE IN VENDITA",
  ["No deals passed the safety checks right now."] =
    "Al momento nessuna occasione ha superato i controlli di sicurezza.",
  ["No deals to show -- and no realm prices yet."] =
    "Nessuna occasione da mostrare -- e ancora nessun prezzo del reame.",
  ["No deals yet."] = "Ancora nessuna occasione.",
  ["No exact auction key"] = "Nessuna chiave d'asta esatta",
  ["No exact bag stack"] = "Nessuna pila esatta nella borsa",
  ["No exact bag variant"] = "Nessuna variante esatta nella borsa",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Ancora nessuna vendita registrata -- apri la cassetta postale con GoldCap caricato",
  ["Not in your bags or listed — mail or bank?"] =
    "Né nelle borse né in vendita — posta o banca?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Non a portata di mano — la scorta è nella posta, in banca o su un altro personaggio",
  ["Nothing is being held back."] = "Non è trattenuto nulla.",
  ["Nothing listed on the AH right now"] = "Al momento non c'è nulla in vendita all'asta",
  ["Nothing queued to cancel"] = "Nulla in coda da annullare",
  ["Nothing queued to post"] = "Nulla in coda da mettere in vendita",
  ["Nothing to remove"] = "Nulla da eliminare",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "SU GOLDCAP.GG — ULTIMI %d GIORNI",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "SU GOLDCAP.GG — ULTIMI %d GIORNI, PIÙ RECENTI %d DI %d",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Una scansione unica di tutta la casa d'aste tramite query paginate. Richiede circa ",
  ["Open the Auction House first."] = "Apri prima la casa d'aste.",
  ["Open the Auction House to begin scanning."] = "Apri la casa d'aste per iniziare la scansione.",
  ["Open the deals board. /gc for commands."] = "Apre la lista delle occasioni. /gc per i comandi.",
  ["POST %d"] = "VENDI %d",
  ["POSTING…"] = "MESSA IN VENDITA…",
  ["PRICE ROSE %.1fx"] = "IL PREZZO È SALITO DI %.1fx",
  ["PROFIT / UNIT"] = "PROFITTO / UNITÀ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Collega o aggiorna il GoldCap Companion per vedere il profitto da goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Incolla la stringa del tuo reame da goldcap.gg e premi Import.",
  ["Position scope changed"] = "L'ambito della posizione è cambiato",
  ["Positions without a cost or a live price are excluded."] =
    "Le posizioni senza costo o senza prezzo dal vivo sono escluse.",
  ["Post"] = "Vendi",
  ["Post confirmation expired"] = "La conferma della vendita è scaduta",
  ["Post the next queued item"] = "Metti in vendita il prossimo oggetto in coda",
  ["Posting failed"] = "Messa in vendita fallita",
  ["Posting timed out"] = "Messa in vendita scaduta",
  ["Posting unavailable"] = "Messa in vendita non disponibile",
  ["Posting…"] = "Messa in vendita…",
  ["Press Full Scan to find deals."] = "Premi Full Scan per trovare occasioni.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Premi Scan per percorrere tutta la casa d'aste una volta, o Auto per scansionare di continuo.",
  ["Previous removal selection cleared"] = "Selezione di eliminazione precedente annullata",
  ["Previous repost selection cleared"] = "Selezione di rimessa in vendita precedente annullata",
  ["Prices up to date"] = "Prezzi aggiornati",
  ["Prices up to date · %d did not answer"] = "Prezzi aggiornati · %d non hanno risposto",
  ["Pricing %d/%d…"] = "Quotazione %d/%d…",
  ["Pricing…"] = "Quotazione…",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Il tracciamento del profitto è una funzione goldcap.gg Pro",
  ["QTY"] = "QTÀ",
  ["Quantity exceeds missing units"] = "La quantità supera le unità mancanti",
  ["REALIZED PROFIT"] = "PROFITTO REALIZZATO",
  ["REFRESH"] = "AGGIORNA",
  ["RESET WINDOW"] = "REIMPOSTA FINESTRA",
  ["Refresh waiting for prior result"] = "L'aggiornamento attende il risultato precedente",
  ["Refreshing listings…"] = "Aggiornamento delle vendite…",
  ["Refused so far: %d"] = "Rifiutate finora: %d",
  ["Removal confirmation expired"] = "La conferma di eliminazione è scaduta",
  ["Remove"] = "Elimina",
  ["Remove?"] = "Eliminare?",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Elimina tutti gli acquisti inseriti a mano in questo gruppo -- clicca di nuovo per confermare",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Elimina questo acquisto inserito a mano -- clicca di nuovo per confermare",
  ["Repost"] = "Rimetti in vendita",
  ["Repost confirmation expired"] = "La conferma di rimessa in vendita è scaduta",
  ["Right-click to stop watching this item"] =
    "Clic destro per smettere di sorvegliare questo oggetto",
  ["Right-click to watch this item closely"] =
    "Clic destro per sorvegliare da vicino questo oggetto",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SALVATO SUBITO · ESC O DONE PER CHIUDERE",
  ["SCAN"] = "SCANSIONA",
  ["SCANNING…"] = "SCANSIONE…",
  ["SESSION %s%s · %d BUYS"] = "SESSIONE %s%s · %d ACQUISTI",
  ["SHOW DETAILS ▸"] = "MOSTRA DETTAGLI ▸",
  ["STRESS EXIT"] = "USCITA SOTTO STRESS",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = sconto così estremo che con ogni probabilità è una truffa o un mercato valutato male",
  ["Sales are costed from your oldest units first"] =
    "Le vendite vengono imputate prima alle tue unità più vecchie",
  ["Set cost"] = "Imposta il costo",
  ["Settings"] = "Impostazioni",
  ["Sold per day"] = "Vendite al giorno",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Ordina in base a esso per decidere cosa controllare per primo, non cosa comprare.",
  ["Source age"] = "Età della fonte",
  ["Stress exit unit"] = "Prezzo d'uscita sotto stress",
  ["Stress profit"] = "Profitto sotto stress",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Il Companion sta sincronizzando, ma questo addon non è riuscito a leggere ciò che ha scritto:",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "È il prezzo più basso che sta chiedendo QUALCUN ALTRO adesso, da una query dal vivo alla casa d'aste. Le tue vendite sono escluse, così il numero non insegue mai se stesso verso il basso.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "Il Companion gratuito per computer tiene i prezzi aggiornati da solo e sincronizza le tue vendite. Copia il link (Ctrl+C) e aprilo in un browser:",
  ["Unknown"] = "Sconosciuto",
  ["Unknown item"] = "Oggetto sconosciuto",
  ["WATCH (computed SAFE)"] = "WATCH (calcolato SICURO)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = scontato ma con liquidità non dimostrata o profitto piccolo",
  ["WHAT TO DO"] = "COSA FARE",
  ["Waiting for Auction House…"] = "In attesa della casa d'aste…",
  ["Waiting for a live price"] = "In attesa di un prezzo dal vivo",
  ["Waiting for the Auction House…"] = "In attesa della casa d'aste…",
  ["Waiting for the purchase to finish…"] = "In attesa che l'acquisto finisca…",
  ["Watching closely: %d item%s"] = "Sorvegliati da vicino: %d oggetto%s",
  ["Watching — pinned, but not a deal right now"] =
    "Sorvegliato — fissato, ma al momento non è un'occasione",
  ["Window position & size"] = "Posizione e dimensione della finestra",
  ["You paid"] = "Hai pagato",
  ["a discount this extreme usually means the market value is wrong, not that this is a bargain"] =
    "uno sconto così estremo di solito significa che il valore di mercato è sbagliato, non che sia un affare",
  ["auto off"] = "auto disattivato",
  ["auto-synced %dh ago"] = "sincronizzato automaticamente %dh fa",
  ["auto-synced data for %s loaded (%s old)"] =
    "dati sincronizzati per %s caricati (vecchi di %s)",
  ["auto-synced data stale -- /goldcap import"] =
    "i dati sincronizzati sono scaduti -- /goldcap import",
  ["auto: paused"] = "auto: in pausa",
  ["big buy"] = "acquisto grosso",
  ["bought %d x item %d"] = "comprati %d x oggetto %d",
  ["bought %d x item %d after AH close"] =
    "comprati %d x oggetto %d dopo la chiusura della casa d'aste",
  ["buying commodity..."] = "acquisto della merce...",
  ["checking live price..."] = "controllo del prezzo dal vivo...",
  ["checking live safety..."] = "controllo della sicurezza dal vivo...",
  ["commodity no longer available -- someone bought it out"] =
    "merce non più disponibile -- qualcuno l'ha comprata tutta",
  ["commodity purchase failed"] = "acquisto della merce fallito",
  ["confirmed commodity purchase failed after AH close"] =
    "acquisto di merce confermato fallito dopo la chiusura della casa d'aste",
  ["confirming purchase..."] = "conferma dell'acquisto...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "base di costo incompleta -- imposta i costi per avere un consiglio sulla rimessa in vendita",
  ["cost unknown"] = "costo sconosciuto",
  ["data from goldcap.gg · synced %s ago"] = "dati da goldcap.gg · sincronizzati %s fa",
  ["due -- will be asked next pass"] = "in scadenza -- verrà richiesto al prossimo passaggio",
  ["finish the pending buy first"] = "completa prima l'acquisto in corso",
  ["full scan already in progress"] = "scansione completa già in corso",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "scansione completa terminata: %d occasion%s da %d grupp%s di oggetti%s",
  ["full scan interrupted -- confirm your purchase"] =
    "scansione completa interrotta -- conferma il tuo acquisto",
  ["full scan stalled -- press Full Scan to retry"] =
    "la scansione completa si è bloccata -- premi Full Scan per riprovare",
  ["full scan stalled -- retrying shortly"] =
    "la scansione completa si è bloccata -- nuovo tentativo a breve",
  ["gone / price changed"] = "sparito / prezzo cambiato",
  ["identity unresolved (variant item -- not priced by design)"] =
    "identità non risolta (oggetto con varianti -- senza prezzo per scelta)",
  ["import %dh old"] = "importazione vecchia di %dh",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "importazione scaduta -- /goldcap import o /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "importati %d oggetti per %s (%s) — i prezzi sono attivi.",
  ["in the mail"] = "nella posta",
  ["item %d"] = "oggetto %d",
  ["item %d: %s"] = "oggetto %d: %s",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "ultime 24 h — %d vendite, %s lordo, %s di commissione, %d acquisti, %s spesi",
  ["listing gone -- already bought out or price changed"] =
    "vendita sparita -- già comprata o prezzo cambiato",
  ["live safety confirmed -- click Buy to purchase"] =
    "sicurezza confermata dal vivo -- clicca Buy per comprare",
  ["live verification required"] = "serve una verifica dal vivo",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "importazione manuale -- Companion lo tiene aggiornato: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "serve un prezzo aggiornato -- premi Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "nessuna conferma dal server -- l'acquisto potrebbe essere andato a buon fine lo stesso, controlla la posta. Chiudere questa finestra non lo annulla.",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "ancora nessun prezzo -- /goldcap companion o /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "nessuna conferma d'acquisto ricevuta -- premi Cancel e riprova",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "ancora nessuna vendita registrata — apri la cassetta postale con GoldCap caricato e verranno lette dalle ricevute",
  ["no stock in bags or listed -- nothing to price for"] =
    "nessuna scorta nelle borse né in vendita -- niente da quotare",
  ["none"] = "nessuno",
  ["not enough gold -- total %s, you have %s"] = "oro insufficiente -- totale %s, tu hai %s",
  ["not enough gold for this quote -- Cancel"] = "oro insufficiente per questa quotazione -- Cancel",
  ["not ready to cancel"] = "non ancora pronto per l'annullamento",
  ["not ready to post"] = "non ancora pronto per la vendita",
  ["nothing listed"] = "niente in vendita",
  ["of %d"] = "di %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "oppure incolla una stringa da goldcap.gg con /goldcap import.",
  ["placing bid..."] = "invio dell'offerta...",
  ["price confirmed -- click Buy to purchase"] = "prezzo confermato -- clicca Buy per comprare",
  ["price rose %.1fx — still safe, confirm"] = "il prezzo è salito di %.1fx — ancora sicuro, conferma",
  ["purchase canceled"] = "acquisto annullato",
  ["purchase pending exact cost"] = "acquisto in attesa del costo esatto",
  ["purchase total unavailable — inspect mailbox"] =
    "totale dell'acquisto non disponibile — controlla la cassetta postale",
  ["quote %s -- click Confirm to buy"] = "quotazione %s -- clicca Confirm per comprare",
  ["quote %ss ago"] = "quotazione di %ss fa",
  ["quote expired -- Refresh to re-check the price"] =
    "quotazione scaduta -- premi Refresh per ricontrollare il prezzo",
  ["recent sales (newest first):"] = "vendite recenti (dalla più nuova):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "regione %s — inclusi: %d oggetti (%s), importati: %s",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "rimettere in vendita adesso fisserebbe una perdita o uno stallo -- aspetta",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "eliminati %d registr%s di acquisto duplicati lasciati da un errore nella lettura della posta",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "eliminati %d registr%s di vendita duplicati lasciati da un errore nella lettura della posta",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    " s. Le righe rifiutate vengono nascoste. Comprare resta sempre un clic che fai tu.",
  ["sale proceeds pending"] = "ricavo della vendita in attesa",
  ["scanned %d listings over %d passes"] = "scansionate %d vendite in %d passaggi",
  ["scanning auction house..."] = "scansione della casa d'aste...",
  ["scanning… %d results · %d deals%s"] = "scansione… %d risultati · %d occasioni%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "cerca tu stesso nella casa d'aste, o controlla la posta. Clicca per alternare.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "vende %s/giorno",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "sessione: %d colpi, %s spesi, ~%s di profitto stim.",
  ["sniped (listing changed on rescan)"] = "soffiato (la vendita è cambiata alla riscansione)",
  ["starting full scan..."] = "avvio della scansione completa...",
  ["stopped watching %s"] = "ho smesso di sorvegliare %s",
  ["the Companion wrote prices this addon could not read --"] =
    "il Companion ha scritto prezzi che questo addon non è riuscito a leggere --",
  ["the import failed (%s)"] = "l'importazione è fallita (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["unknown evidence"] = "prova sconosciuta",
  ["waiting for previous commodity purchase to settle"] =
    "in attesa che si chiuda l'acquisto di merce precedente",
  ["waiting for previous search result to settle"] =
    "in attesa del risultato di ricerca precedente",
  ["waiting for server... full scan will start automatically"] =
    "in attesa del server... la scansione completa partirà da sola",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s sorvegliato da vicino -- ricontrollato ogni pochi secondi",
  ["would sell at a loss"] = "venderebbe in perdita",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "non hai ancora importato i prezzi del reame -- installa GoldCap Companion (/goldcap companion) o incolla una stringa da goldcap.gg (/goldcap import).",
  ["you should clear about %s"] = "dovresti ricavarne circa %s",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "la tua importazione ha %d ore -- i prezzi possono essere sbagliati. Incolla una stringa fresca da goldcap.gg (/goldcap import).",
  ["» needs price"] = "» serve il prezzo",
  ["×%d in bags"] = "×%d nelle borse",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d nelle tue borse · Post ne mette in vendita %d, la pila più grande",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d nelle tue borse · nessuna pila che GoldCap possa identificare con esattezza",
  ["×%d in your bags, ready to list"] = "×%d nelle tue borse, pronti per la vendita",
  ["×%d listed"] = "×%d in vendita",
  ["×%d listed at %s each"] = "×%d in vendita a %s l'uno",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · comprato %s · %s · %s",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valore di mercato goldcap.gg — ancora nessuna quotazione dal vivo",
}
