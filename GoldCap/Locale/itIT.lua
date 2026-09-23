local _, GC = ...

-- Italian. Terminology follows apps/web/messages/it.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.itIT = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s l'uno  (%s in totale, %s di commissione)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion lo tiene aggiornato: /goldcap companion.",
  [" · %d hidden"] = " · %d nascosti",
  [" · %d keys"] = " · %d chiavi",
  [" · below cost"] = " · sotto il costo",
  [" · identity unresolved"] = " · identità non risolta",
  [" · stale %ds"] = " · vecchio di %ds",
  [" — Check again"] = " — controlla di nuovo",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — comandi: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (o /gc in breve)",
  ["%d (whole lot)"] = "%d (lotto intero)",
  ["%d caps · %s"] = "%d tetti · %s",
  ["%d days"] = "%d giorni",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d occasioni dall'ultima scansione -- Full Scan per aggiornare",
  ["%d filtered out as hard to resell"] = "%d scartate perché difficili da rivendere",
  ["%d held back"] = "%d trattenute",
  ["%d held back from posting"] = "%d non messe in vendita",
  ["%d hidden -- the live check refused them"] = "%d nascoste -- la verifica dal vivo le ha rifiutate",
  ["%d in %d lots"] = "%d in %d lotti",
  ["%d in 1 lot"] = "%d in 1 lotto",
  ["%d lots, %s asked"] = "%d lotti, richiesti %s",
  ["%d missing"] = "ne mancano %d",
  ["%d partial"] = "%d parziali",
  ["%d prices in one request · books still loading"] =
    "%d prezzi in una sola richiesta · book ancora in caricamento",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d rifiutate dal controllo dal vivo -- premi \"HIDDEN %d\" sopra per vederle",
  ["%d sales · %s proceeds · %s in the mail"] = "%d vendite · %s di ricavo · %s nella posta",
  ["%d units"] = "%d unità",
  ["%d units · %d prices"] = "%d unità · %d prezzi",
  ["%d without a price"] = "%d senza prezzo",
  ["%d without cost"] = "%d senza costo",
  ["%d · %d/%d covered"] = "%d · %d/%d coperti",
  ["%d/%d covered"] = "%d/%d coperti",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s per unità    totale %s -> %s",
  ["%s after the AH cut"] = "%s dopo la commissione della CA",
  ["%s ahead"] = "%s davanti",
  ["%s under you"] = "%s sotto di te",
  ["%s — %d unit%s without a cost"] = "%s — %d unità%s senza costo",
  [", %d hidden as unsellable"] = ", %d nascosti perché invendibili",
  ["1 lot, %s asked"] = "1 lotto, richiesti %s",
  ["24h trend"] = "Andamento 24h",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Un trattino significa che GoldCap non conosce ancora il costo di ogni unità: non lo indovinerà mai dal prezzo di mercato.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Un indizio, non una promessa: rivendita al 95% del valore di mercato importato, per la quantità che Check stesso approverebbe.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Se più acquisti sono raggruppati su una riga, vengono rimossi tutti.",
  ["AH answered empty %ds ago"] = "la casa d'aste ha risposto vuota %ds fa",
  ["ASKING"] = "RICHIESTO",
  ["AT MARKET"] = "A MERCATO",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · IN PAUSA: ",
  ["AUTO · SCANNING"] = "AUTO · SCANSIONE",
  ["AUTOMATION & ALERTS"] = "AUTOMAZIONE E AVVISI",
  ["AVOID"] = "EVITA",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Oltre questo aumento in 24 ore il valore di mercato è considerato un'impennata e viene ridotto.",
  ["Above your price -- quoted %s, your price %s"] = "Sopra il tuo prezzo -- quotato %s, il tuo prezzo %s",
  ["Asks for a second click to confirm."] = "Chiede un secondo clic per confermare.",
  ["At your price"] = "Al tuo prezzo",
  ["Auction House did not answer — press Refresh"] =
    "La casa d'aste non ha risposto — premi Refresh",
  ["Auction House is not open"] = "La casa d'aste non è aperta",
  ["Auto-scan on next AH visit"] = "Scansione automatica alla prossima visita alla CA",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: tiene Full Scan sempre attivo e cede subito il passo quando compri, cerca tu stesso nella casa d'aste, o controlla la posta. Clicca per alternare.",
  ["Avoid"] = "Evita",
  ["BOOKS %d/%d"] = "BOOK %d/%d",
  ["BRAKES"] = "FRENI",
  ["BUY — unverified"] = "COMPRA — non verificato",
  ["Background check"] = "Controllo in background",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Il pareggio è il prezzo più basso che copre ancora il tuo costo dopo la commissione. Sotto quello ci rimetti.",
  ["Bundled %s data"] = "Dati %s inclusi",
  ["Bundled data"] = "Dati inclusi",
  ["Buy"] = "Compra",
  ["Buy less"] = "Compra meno",
  ["CANCEL %d"] = "ANNULLA %d",
  ["CANCEL LOT?"] = "ANNULLARE IL LOTTO?",
  ["CANCELLING…"] = "ANNULLAMENTO…",
  ["CONFIRM"] = "CONFERMA",
  ["COST"] = "COSTO",
  ["COST / UNIT"] = "COSTO / UNITÀ",
  ["Can't price this"] = "Prezzo non affidabile",
  ["Cancel"] = "Annulla",
  ["Cancel lot"] = "Annulla",
  ["Cancel lot?"] = "Annullare?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Annulla questo lotto e perdi la cauzione — clicca di nuovo per confermare",
  ["Cancel timed out"] = "Annullamento scaduto",
  ["Cancelling lot…"] = "Annullamento del lotto…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Annulla questa asta attiva — NON la ripubblica. Il deposito è perso e gli oggetti tornano per posta; rimettili in vendita da questa riga quando arrivano.",
  ["Cannot post this position"] = "Impossibile mettere in vendita questa posizione",
  ["Cannot remove this entry"] = "Impossibile eliminare questa voce",
  ["Cannot repost this lot"] = "Impossibile rimettere in vendita questo lotto",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limitato da quanto in fretta si vende davvero, non dal tuo portafoglio.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Restano aste più economiche, ma al ritmo di questo oggetto si esauriscono in poche ore.",
  ["Check"] = "Verifica",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check ricalcola sul book degli ordini dal vivo prima che l'oro si muova, e può comunque risultare più basso — o rifiutare — se il mercato si è mosso dall'ultima importazione.",
  ["Checked against the live order book a moment ago."] =
    "Verificato poco fa sul book degli ordini in tempo reale.",
  ["Checked: %d of the top %d on screen"] = "Controllate: %d delle prime %d a schermo",
  ["Checking prices…"] = "Controllo dei prezzi…",
  ["Checking this item's price…"] = "Controllo del prezzo di questo oggetto…",
  ["Checking..."] = "Verifica...",
  ["Clear to buy"] = "Via libera all'acquisto",
  ["Click Confirm to post"] = "Clicca Confirm per mettere in vendita",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Un altro clic annulla l'asta attiva. Non la ripubblica: il deposito è perso e gli oggetti tornano per posta anziché direttamente nelle borse.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Un altro clic elimina definitivamente questo costo inserito a mano.",
  ["Close"] = "Chiudi",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "Companion tiene i prezzi aggiornati — /goldcap companion",
  ["Companion sync rejected:"] = "Sincronizzazione Companion rifiutata:",
  ["Confidence"] = "Affidabilità",
  ["Confirm"] = "Conferma",
  ["Confirm the cancel"] = "Conferma l'annullamento",
  ["Confirm the removal"] = "Conferma la rimozione",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Copia il link (Ctrl+C) e aprilo in un browser:",
  ["Cost per unit"] = "Costo per unità",
  ["Cost unknown for %d of %d"] = "Costo sconosciuto per %d su %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Costa più di quanto consenta il tuo limite per acquisto.",
  ["Could not find the queue's next item to post — try again"] =
    "Non trovo il prossimo oggetto in coda da mettere in vendita — riprova",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Non trovo il prossimo lotto in coda da annullare — riprova",
  ["DEFAULTS"] = "PREDEFINITI",
  ["DISC"] = "SCONTO",
  ["DISPLAY"] = "VISUALIZZAZIONE",
  ["DONE"] = "FATTO",
  ["Default listing length for the Sell tab."] = "Durata d'inserzione predefinita per la scheda Vendi.",
  ["Default: %s"] = "Predefinito: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Elimina un costo inserito a mano in Imposta costo — mai un acquisto che GoldCap ha rilevato o abbinato alla tua posta.",
  ["Discount"] = "Sconto",
  ["Discount vs market value from your GoldCap import"] =
    "Sconto rispetto al valore di mercato del tuo import GoldCap",
  ["Dump-trend cap %"] = "Limite di tendenza al ribasso %",
  ["Duration"] = "Durata",
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
  ["Free, sits in the tray, nothing to set up in game."] =
    "Gratuito, sta nella barra di sistema, niente da configurare nel gioco.",
  ["Full pass over them: %.1fs"] = "Passaggio completo: %.1fs",
  ["Full pass over them: measuring..."] = "Passaggio completo: misurazione...",
  ["Gold tied up"] = "Oro immobilizzato",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap non riesce a stabilire quale pila della borsa sia questa",
  ["GoldCap data age"] = "Età dei dati GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap ricontrolla le prime %d righe contro la casa d'aste dal vivo, all'incirca ogni %d s. Le righe rifiutate vengono nascoste. Comprare resta sempre un clic che fai tu.",
  ["GoldCap value"] = "Valore GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Importa i prezzi del reame",
  ["GoldCap's"] = "di GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "Il suggerimento di GoldCap per questo oggetto e il prezzo che userebbe.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: controllato dal vivo -- acquisto sicuro",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: non ancora verificato sulla casa d'aste dal vivo",
  ["Gone"] = "Sparito",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "In grigio significa che la quotazione è invecchiata; Post e Repost la aggiornano prima di agire.",
  ["HIDDEN 0"] = "NASCOSTE 0",
  ["HIDE DETAILS ▾"] = "NASCONDI DETTAGLI ▾",
  ["HOLDING %d"] = "DA TENERE %d",
  ["Held back from cancelling"] = "Trattenuto dall'annullamento",
  ["Held back from the queue"] = "Trattenuto dalla coda",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Per quante ore di vendite normali un muro sotto il tuo prezzo d'uscita può reggere prima che l'affare venga rifiutato.",
  ["ITEM"] = "OGGETTO",
  ["If it clears"] = "Se si vende",
  ["Import"] = "Importa",
  ["Import failed:"] = "Importazione fallita:",
  ["Import from goldcap.gg to arm the sniper"] = "Importa da goldcap.gg per attivare lo sniper",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Installa il GoldCap Companion gratuito per tenere i prezzi aggiornati da soli (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "È il prezzo da battere per vendere in fretta, non quanto vale l'oggetto. Un venditore di fretta può metterlo molto sotto il valore, e GoldCap non lo seguirà al ribasso: guarda WHAT TO DO per il prezzo a cui metterebbe davvero in vendita.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Non inventerà un costo dal prezzo di mercato, quindi il profitto resta ignoto finché non ne inserisci uno.",
  ["Item"] = "Oggetto",
  ["Item %d"] = "Oggetto %d",
  ["Item level %d, below the %d your price is for"] =
    "Livello oggetto %d, sotto il %d per cui vale il tuo prezzo",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."] =
    "Items: equipaggiamento, mascotte e ricette valutati rispetto al riferimento regionale del tuo import. La velocità di vendita non viene mai misurata, quindi non diventano mai SICURO -- questa la decidi tu, e GoldCap li controlla solo finché questa lista è aperta.",
  ["LISTED"] = "IN VENDITA",
  ["Language"] = "Lingua",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Lingua cambiata. Digita /reload per applicarla ovunque.",
  ["Last result: %ds ago"] = "Ultimo risultato: %ds fa",
  ["Last result: none yet this visit"] = "Ultimo risultato: nessuno in questa visita",
  ["Listed"] = "In vendita",
  ["Listed at %s — far below market. Repost."] =
    "In vendita a %s — molto sotto mercato. Rimettilo in vendita.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "In vendita al prezzo che hai fissato su goldcap.gg o meno. Se si rivende, giudichi tu.",
  ["Listed value"] = "Valore in vendita",
  ["Listings"] = "Vendite",
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "Mette in vendita ciò che hai nelle borse al prezzo sotto COSA FARE: l'intera borsa per una merce, una pila per un oggetto normale.",
  ["Live ask"] = "Prezzo attuale",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lotto annullato; aspetta che torni nelle borse",
  ["MARKET"] = "MERCATO",
  ["MARKET / UNIT"] = "MERCATO / UNITÀ",
  ["MATCH"] = "PAREGGIA",
  ["Market per unit"] = "Mercato per unità",
  ["Market reference"] = "Riferimento di mercato",
  ["Max units per buy"] = "Max. unità per acquisto",
  ["Max wallet per buy %"] = "Max. del tuo oro per acquisto %",
  ["Min profit per buy (gold)"] = "Profitto min. per acquisto (oro)",
  ["Min return per buy %"] = "Rendimento min. per acquisto %",
  ["Missing cost"] = "Costo mancante",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "NON ANCORA SU GOLDCAP.GG — SI SINCRONIZZA CON /RELOAD O ALL'USCITA",
  ["NOT ON HAND %d"] = "NON A PORTATA %d",
  ["NOTHING TO CANCEL"] = "NIENTE DA ANNULLARE",
  ["NOTHING TO POST"] = "NIENTE DA METTERE IN VENDITA",
  ["Needs a live price check before it can be bought."] =
    "Serve un controllo del prezzo dal vivo prima di poterlo comprare.",
  ["Never spend more than this share of your gold on one purchase."] =
    "Non spendere mai più di questa quota del tuo oro in un solo acquisto.",
  ["No deals passed the safety checks right now."] =
    "Al momento nessuna occasione ha superato i controlli di sicurezza.",
  ["No deals to show -- and no realm prices yet."] =
    "Nessuna occasione da mostrare -- e ancora nessun prezzo del reame.",
  ["No deals yet."] = "Ancora nessuna occasione.",
  ["No exact auction key"] = "Nessuna chiave d'asta esatta",
  ["No exact bag stack"] = "Nessuna pila esatta nella borsa",
  ["No exact bag variant"] = "Nessuna variante esatta nella borsa",
  ["No live listings came back for this item."] =
    "Nessuna asta attiva è tornata per questo oggetto.",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "Nessun prezzo di riferimento regionale per questo oggetto — reimporta appena goldcap.gg ne pubblica uno.",
  ["No safe resale price could be worked out."] =
    "Non è stato possibile calcolare un prezzo di rivendita sicuro.",
  ["No sales data for this item."] = "Nessun dato di vendita per questo oggetto.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Ancora nessuna vendita registrata -- apri la cassetta postale con GoldCap caricato",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Non ci sono abbastanza unità alla casa d'aste per quella quantità.",
  ["Not in your bags or listed — mail or bank?"] =
    "Né nelle borse né in vendita — posta o banca?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Non a portata di mano — la scorta è nella posta, in banca o su un altro personaggio",
  ["Nothing is being held back."] = "Non è trattenuto nulla.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Dopo questo acquisto non resta nulla contro cui vendere, quindi non c'è prezzo di uscita.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Nessuna inserzione raggiunge il livello oggetto su cui è stato misurato il prezzo di riferimento.",
  ["Nothing listed on the AH right now"] = "Al momento non c'è nulla in vendita all'asta",
  ["Nothing on this deck matches that search"] = "Niente in questa scheda corrisponde a questa ricerca",
  ["Nothing queued to cancel"] = "Nulla in coda da annullare",
  ["Nothing queued to post"] = "Nulla in coda da mettere in vendita",
  ["Nothing to remove"] = "Nulla da eliminare",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "SU GOLDCAP.GG — ULTIMI %d GIORNI",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "SU GOLDCAP.GG — ULTIMI %d GIORNI, PIÙ RECENTI %d DI %d",
  ["ON THE AUCTION HOUSE"] = "ALLA CASA D'ASTE",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Una scansione unica di tutta la casa d'aste tramite query paginate. Richiede circa Da 15 a 60 secondi sui reami affollati. Nessuna attesa -- riscansiona quando vuoi.",
  ["Open the Auction House first."] = "Apri prima la casa d'aste.",
  ["Open the Auction House to begin scanning."] = "Apri la casa d'aste per iniziare la scansione.",
  ["Open the deals board. /gc for commands."] = "Apre la lista delle occasioni. /gc per i comandi.",
  ["POST %d"] = "VENDI %d",
  ["POSTING"] = "PUBBLICAZIONE",
  ["POSTING…"] = "MESSA IN VENDITA…",
  ["PRICE"] = "PREZZO",
  ["PRICE ROSE %.1fx"] = "IL PREZZO È SALITO DI %.1fx",
  ["PRICED TOO LOW %d"] = "TROPPO BASSO %d",
  ["PRICING %d/%d"] = "PREZZI %d/%d",
  ["PRICING…"] = "PREZZI…",
  ["PROFIT"] = "PROFITTO",
  ["PROFIT / UNIT"] = "PROFITTO / UNITÀ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Collega o aggiorna il GoldCap Companion per vedere il profitto da goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Incolla la stringa del tuo reame da goldcap.gg e premi Import.",
  ["Per-unit price of this auction"] = "Prezzo unitario di questa asta",
  ["Play a sound when a checked deal turns SAFE."] =
    "Riproduci un suono quando un affare verificato diventa SAFE.",
  ["Position scope changed"] = "L'ambito della posizione è cambiato",
  ["Positions without a cost or a live price are excluded."] =
    "Le posizioni senza costo o senza prezzo dal vivo sono escluse.",
  ["Post"] = "Vendi",
  ["Post above the cheapest"] = "Pubblica sopra il più economico",
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
  ["Price"] = "Prezzo",
  ["Priced from bundled sample data, not from your realm."] =
    "Prezzo preso dai dati di esempio inclusi, non dal tuo reame.",
  ["Prices up to date"] = "Prezzi aggiornati",
  ["Prices up to date · %d did not answer"] = "Prezzi aggiornati · %d non hanno risposto",
  ["Pricing %d/%d…"] = "Quotazione %d/%d…",
  ["Pricing paused while you use the Auction House"] = "Quotazione in pausa mentre usi la casa d'aste",
  ["Pricing…"] = "Quotazione…",
  ["Profit"] = "Profitto",
  ["Profit per unit"] = "Profitto per unità",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Il tracciamento del profitto è una funzione goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "Gli acquisti sono disattivati in questa build.",
  ["QTY"] = "QTÀ",
  ["Quantity exceeds missing units"] = "La quantità supera le unità mancanti",
  ["Quantity is capped by how fast this item actually sells."] =
    "La quantità è limitata da quanto in fretta l'oggetto si vende davvero.",
  ["REALIZED PROFIT"] = "PROFITTO REALIZZATO",
  ["REFRESH"] = "AGGIORNA",
  ["RESET WINDOW"] = "REIMPOSTA FINESTRA",
  ["Reason"] = "Motivo",
  ["Refresh"] = "Aggiorna",
  ["Refresh waiting for prior result"] = "L'aggiornamento attende il risultato precedente",
  ["Refreshing listings…"] = "Aggiornamento delle vendite…",
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "Rifiuta un acquisto se il prezzo è sceso più di questo nelle ultime 24 ore — potrebbe continuare a scendere.",
  ["Refused so far: %d"] = "Rifiutate finora: %d",
  ["Removal confirmation expired"] = "La conferma di eliminazione è scaduta",
  ["Remove"] = "Elimina",
  ["Remove this cost"] = "Rimuovi questo costo",
  ["Remove?"] = "Eliminare?",
  ["Removed"] = "Rimosso",
  ["Removed %d entries"] = "%d voci rimosse",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Elimina tutti gli acquisti inseriti a mano in questo gruppo -- clicca di nuovo per confermare",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Elimina questo acquisto inserito a mano -- clicca di nuovo per confermare",
  ["Repost confirmation expired"] = "La conferma di rimessa in vendita è scaduta",
  ["Right-click to stop watching this item"] =
    "Clic destro per smettere di sorvegliare questo oggetto",
  ["Right-click to watch this item closely"] =
    "Clic destro per sorvegliare da vicino questo oggetto",
  ["SAFE +%s"] = "SICURO +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "SICURO = il controllo dal vivo ha approvato questo acquisto, al profitto mostrato",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SALVATO SUBITO · ESC O DONE PER CHIUDERE",
  ["SCAN"] = "SCANSIONA",
  ["SCANNING…"] = "SCANSIONE…",
  ["SESSION %s%s · %d BUYS"] = "SESSIONE %s%s · %d ACQUISTI",
  ["SHOW DETAILS ▸"] = "MOSTRA DETTAGLI ▸",
  ["Sales are costed from your oldest units first"] =
    "Le vendite vengono imputate prima alle tue unità più vecchie",
  ["Search"] = "Cerca",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "La scheda Vendi pubblica un gradino sopra l'offerta più economica quando il libro ordini indica che si vende altrettanto in fretta.",
  ["Sell-through"] = "Tasso di vendita",
  ["Sellers"] = "Venditori",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Si vende troppo di rado: te lo terresti a lungo.",
  ["Set cost"] = "Costo",
  ["Settings"] = "Impostazioni",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Salta un acquisto se non frutta almeno questa cifra dopo la commissione della CA.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Salta un acquisto se il profitto non è almeno questa quota di quanto paghi.",
  ["Snapshot value"] = "Valore dello snapshot",
  ["Sold per day"] = "Vendite al giorno",
  ["Sold/day"] = "Vendite/giorno",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Ordina in base a esso per decidere cosa controllare per primo, non cosa comprare.",
  ["Sound on SAFE deal"] = "Suono su affare SAFE",
  ["Source age"] = "Età della fonte",
  ["Spike-trend threshold %"] = "Soglia di impennata %",
  ["Start scanning as soon as the auction house opens."] =
    "Inizia la scansione non appena si apre la casa d'aste.",
  ["Status"] = "Stato",
  ["Stop and open the buy window on your price"] = "Ferma e apri la finestra d'acquisto al tuo prezzo",
  ["Stress exit unit"] = "Prezzo d'uscita sotto stress",
  ["Stress profit"] = "Profitto sotto stress",
  ["THE BOOK"] = "IL BOOK",
  ["TOTAL"] = "TOTALE",
  ["TREND"] = "TENDENZA",
  ["Tell GoldCap what you actually paid for these units."] =
    "Di' a GoldCap quanto hai davvero pagato per queste unità.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "La casa d'aste non ha indicato un deposito, quindi il costo è ignoto.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Il Companion sta sincronizzando, ma questo addon non è riuscito a leggere ciò che ha scritto:",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "La lista lo ha classificato sullo snapshot importato. Il book in tempo reale non lo conferma.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Il pulsante attende un momento prima di poter essere premuto, così un doppio clic accidentale non basta mai.",
  ["The cancel did not go through — the lot is still listed"] = "L'annullamento non è andato a buon fine — il lotto è ancora in vendita",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "L'inserzione più economica non è più abbastanza sotto il prezzo di riferimento.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "È il prezzo più basso che sta chiedendo QUALCUN ALTRO adesso, da una query dal vivo alla casa d'aste. Le tue vendite sono escluse, così il numero non insegue mai se stesso verso il basso.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "I dati di questo oggetto sono malformati, quindi GoldCap si rifiuta di indovinare.",
  ["The liquidity data is not reliable enough to act on."] =
    "I dati di liquidità non sono abbastanza affidabili per agire.",
  ["The market value is an estimate, not a measurement."] =
    "Il valore di mercato è una stima, non una misura.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Il massimo che un acquisto può prendere. La velocità con cui l'oggetto si vende può ancora ridurlo.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "I dati di prezzo hanno più di tre ore. Sincronizza il Companion e poi fai /reload: l'addon legge i suoi dati solo al caricamento dell'interfaccia.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "Il prezzo è verificato. La velocità di vendita non è misurata da nessuna parte: giudichi tu.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Il prezzo sta scendendo; entrarci è il modo per restare incastrato.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "Il prezzo è l'ultima quotazione, vecchia al massimo di 45 secondi. Se cambia prima della conferma, la pubblicazione viene abbandonata anziché inviata al vecchio prezzo.",
  ["The price moved -- part of this quote may be above your price"] =
    "Il prezzo si è mosso -- parte di questa quotazione può superare il tuo prezzo",
  ["The price moved and the trade is no longer safe."] =
    "Il prezzo si è mosso e l'operazione non è più sicura.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Il profitto non raggiunge il tuo minimo una volta pagati il 5 % di commissione e il deposito.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Non si può annullare. Il primo clic ne chiede un secondo per confermare.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "È un oggetto di reame, e GoldCap verifica solo i prezzi delle merci.",
  ["Too few sellers to read a real price."] = "Troppo pochi venditori per leggere un prezzo reale.",
  ["Too little of what is listed actually sells."] =
    "Troppo poco di ciò che è in vendita viene davvero venduto.",
  ["Too little price history to trust the value."] =
    "Troppo poco storico dei prezzi per fidarsi del valore.",
  ["Total cost to buy this auction"] = "Costo totale per comprare questa asta",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Scrivi un prezzo in oro, o svuota il campo per usare quello di GoldCap",
  ["UNDERCUT"] = "RIBASSA",
  ["UNDERCUT %d"] = "SUPERATI %d",
  ["UNIT"] = "UNITÀ",
  ["Unit price"] = "Prezzo unitario",
  ["Unknown"] = "Sconosciuto",
  ["Unknown item"] = "Oggetto sconosciuto",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "Ignoto significa che il lato costi è incompleto: completalo con Imposta costo.",
  ["VERDICT"] = "VERDETTO",
  ["Verdict"] = "Verdetto",
  ["WATCH"] = "OSSERVA",
  ["WATCH (computed SAFE)"] = "WATCH (calcolato SICURO)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "OSSERVA = il controllo dal vivo lo ha rifiutato -- passa sulla riga per il motivo",
  ["WHAT COUNTS AS A DEAL"] = "COSA CONTA COME AFFARE",
  ["WHAT TO DO"] = "COSA FARE",
  ["WHAT YOU PAID"] = "QUANTO HAI PAGATO",
  ["WHEN"] = "QUANDO",
  ["Waiting for Auction House…"] = "In attesa della casa d'aste…",
  ["Waiting for a live price"] = "In attesa di un prezzo dal vivo",
  ["Waiting for the Auction House…"] = "In attesa della casa d'aste…",
  ["Waiting for the purchase to finish…"] = "In attesa che l'acquisto finisca…",
  ["Wall absorb window (hours)"] = "Finestra di assorbimento del muro (ore)",
  ["Watching closely: %d item%s"] = "Sorvegliati da vicino: %d oggetto%s",
  ["Watching — pinned, but not a deal right now"] =
    "Sorvegliato — fissato, ma al momento non è un'occasione",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Quanto ti è costata davvero una unità, in media sugli acquisti ancora in magazzino.",
  ["What to do"] = "Cosa fare",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Quanto ti resta su un'unità se si vende al prezzo di mercato: prezzo di vendita, meno il 5 % di commissione, meno il tuo costo.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Quanto fanno in totale le tue aste attive per questo oggetto al prezzo attuale.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Quando un'inserzione raggiunge un prezzo impostato sul sito, la scansione si ferma e si apre la sua finestra d'acquisto.",
  ["Window position & size"] = "Posizione e dimensione della finestra",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "Con lui i prezzi del tuo reame si aggiornano da soli e le tue vendite e il profitto arrivano su goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "Senza, GoldCap usa i prezzi fermi alla data di rilascio — le occasioni si cercano con prezzi vecchi.",
  ["Won't buy"] = "Non compro",
  ["Worst case back"] = "Rientro nel caso peggiore",
  ["YOUR LOTS"] = "I TUOI LOTTI",
  ["YOUR PRICE"] = "IL TUO PREZZO",
  ["You paid"] = "Hai pagato",
  ["You pay"] = "Paghi",
  ["You would get"] = "Riceveresti",
  ["You would pay"] = "Pagheresti",
  ["Your call"] = "Decidi tu",
  ["Your minimum"] = "Il tuo minimo",
  ["Your price"] = "Il tuo prezzo",
  ["a unit, at or under your price of %s"] = "a unità, al tuo prezzo di %s o meno",
  ["above the cheapest, inside the cheap quarter · %d units queued below"] =
    "sopra il più economico, nel quarto economico · %d unità in coda sotto",
  ["above the cheapest, within the day's reach · %d units queued below"] =
    "sopra il più economico, entro la portata del giorno · %d unità in coda sotto",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "rispetto al prezzo regionale di questo oggetto, al netto del 5% — se si vende",
  ["any figure here would be invented out of the very number being refused"] =
    "qualsiasi cifra qui sarebbe inventata proprio dal numero che viene rifiutato",
  ["at or under your price -- click Buy to purchase"] =
    "al tuo prezzo o meno -- clicca Buy per acquistare",
  ["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"] =
    "al prezzo a cui GoldCap si aspetta che questi si vendano, al netto del 5% — non il tuo prezzo richiesto",
  ["auto off"] = "auto disattivato",
  ["auto-synced %dh ago"] = "sincronizzato automaticamente %dh fa",
  ["auto-synced data for %s loaded (%s old)"] =
    "dati sincronizzati per %s caricati (vecchi di %s)",
  ["auto-synced data stale -- /goldcap import"] =
    "i dati sincronizzati sono scaduti -- /goldcap import",
  ["auto: paused"] = "auto: in pausa",
  ["below the %s you paid"] = "sotto i %s che hai pagato",
  ["big buy"] = "acquisto grosso",
  ["bought %d x item %d"] = "comprati %d x oggetto %d",
  ["bought %d x item %d after AH close"] =
    "comprati %d x oggetto %d dopo la chiusura della casa d'aste",
  ["buying commodity..."] = "acquisto della merce...",
  ["cheapest not yours %s"] = "il più basso che non è tuo %s",
  ["check the item level — buy by hand"] = "controlla il livello oggetto — compra a mano",
  ["checking live price..."] = "controllo del prezzo dal vivo...",
  ["checking live safety..."] = "controllo della sicurezza dal vivo...",
  ["commodity purchase failed"] = "acquisto della merce fallito",
  ["confirmed commodity purchase failed after AH close"] =
    "acquisto di merce confermato fallito dopo la chiusura della casa d'aste",
  ["confirming purchase..."] = "conferma dell'acquisto...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "base di costo incompleta -- imposta i costi per avere un consiglio sulla rimessa in vendita",
  ["cost unknown"] = "costo sconosciuto",
  ["crafted %s"] = "creato %s",
  ["data from goldcap.gg · synced %s ago"] = "dati da goldcap.gg · sincronizzati %s fa",
  ["due -- will be asked next pass"] = "in scadenza -- verrà richiesto al prossimo passaggio",
  ["fair"] = "media",
  ["far below market"] = "molto sotto mercato",
  ["finish the pending buy first"] = "completa prima l'acquisto in corso",
  ["first in line"] = "primo della fila",
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
  ["high"] = "alta",
  ["hold"] = "tenere",
  ["identity unresolved (variant item -- not priced by design)"] =
    "identità non risolta (oggetto con varianti -- senza prezzo per scelta)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "se compri tutte e %d e le rivendi al prezzo esposto adesso",
  ["import %dh old"] = "importazione vecchia di %dh",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "importazione scaduta -- /goldcap import o /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "importati %d oggetti per %s (%s) — i prezzi sono attivi.",
  ["in the mail"] = "nella posta",
  ["in the mail, the bank or on another character"] = "nella posta, in banca o su un altro personaggio",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "è quanto assorbe questo mercato — oltre compri merce che ti resterà in mano",
  ["item %d"] = "oggetto %d",
  ["item %d: %s"] = "oggetto %d: %s",
  ["item level %d+"] = "livello oggetto %d+",
  ["item variant unresolved"] = "variante dell'oggetto non risolta",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "ultime 24 h — %d vendite, %s lordo, %s di commissione, %d acquisti, %s spesi",
  ["leave these alone"] = "lasciali stare",
  ["listing gone -- already bought out or price changed"] =
    "vendita sparita -- già comprata o prezzo cambiato",
  ["listing gone -- bought out or repriced"] = "l'asta non c'è più: comprata o riprezzata",
  ["live safety confirmed -- click Buy to purchase"] =
    "sicurezza confermata dal vivo -- clicca Buy per comprare",
  ["live verification required"] = "serve una verifica dal vivo",
  ["low"] = "bassa",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "importazione manuale -- Companion lo tiene aggiornato: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "serve un prezzo aggiornato -- premi Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "nessuna conferma dal server -- l'acquisto potrebbe essere andato a buon fine lo stesso, controlla la posta. Chiudere questa finestra non lo annulla.",
  ["no cost"] = "nessun costo",
  ["no cost for %d"] = "nessun costo per %d",
  ["no live price yet"] = "ancora nessun prezzo dal vivo",
  ["no price"] = "nessun prezzo",
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
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "non restano abbastanza unità per quella quantità -- ricontrollo di ciò che resta...",
  ["not ready to cancel"] = "non ancora pronto per l'annullamento",
  ["not ready to post"] = "non ancora pronto per la vendita",
  ["nothing listed"] = "niente in vendita",
  ["of %d"] = "di %d",
  ["off"] = "disattivo",
  ["oldest units sell first"] = "le unità più vecchie si vendono per prime",
  ["on"] = "attivo",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "oppure incolla una stringa da goldcap.gg con /goldcap import.",
  ["over %d position%s"] = "su %d posizioni%s",
  ["paid sale unresolved"] = "vendita incassata non risolta",
  ["placing bid..."] = "invio dell'offerta...",
  ["price checked, sale speed unknown -- this one is your call"] =
    "prezzo verificato, velocità di vendita ignota -- questa la decidi tu",
  ["price confirmed -- click Buy to purchase"] = "prezzo confermato -- clicca Buy per comprare",
  ["price rose %.1fx — still safe, confirm"] = "il prezzo è salito di %.1fx — ancora sicuro, conferma",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "i prezzi caricati sono di %s (%s) ma stai giocando in %s — ogni sconto e profitto è misurato su un altro mercato",
  ["purchase canceled"] = "acquisto annullato",
  ["purchase complete"] = "acquisto completato",
  ["purchase identity unresolved"] = "identità dell'acquisto non risolta",
  ["purchase pending exact cost"] = "acquisto in attesa del costo esatto",
  ["purchase total unavailable — inspect mailbox"] =
    "totale dell'acquisto non disponibile — controlla la cassetta postale",
  ["quote %s -- click Confirm to buy"] = "quotazione %s -- clicca Confirm per comprare",
  ["quote %ss ago"] = "quotazione di %ss fa",
  ["quote expired -- Refresh to re-check the price"] =
    "quotazione scaduta -- premi Refresh per ricontrollare il prezzo",
  ["re-checking what remains at a safe price..."] =
    "ricontrollo di ciò che resta a un prezzo sicuro...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "oggetto di reame — velocità di vendita non verificata · riferimento regionale %s (livello %d)",
  ["recent sales (newest first):"] = "vendite recenti (dalla più nuova):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "regione %s — inclusi: %d oggetti (%s), importati: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "regione corretta su %d righe del registro; %d vendite riabbinate alle scorte",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "rimettere in vendita adesso fisserebbe una perdita o uno stallo -- aspetta",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "eliminati %d registri di acquisto duplicati lasciati da un errore nella lettura della posta",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "eliminati %d registri di vendita duplicati lasciati da un errore nella lettura della posta",
  ["sale name ambiguous"] = "nome della vendita ambiguo",
  ["sale proceeds pending"] = "ricavo della vendita in attesa",
  ["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"] =
    "scansione completata: %d affare%s da %d oggetto%s tra materiali, consumabili, gemme, incantesimi%s",
  ["scanned %d listings over %d passes"] = "scansionate %d vendite in %d passaggi",
  ["scanning auction house..."] = "scansione della casa d'aste...",
  ["scanning… %d results · %d deals%s"] = "scansione… %d risultati · %d occasioni%s",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "vende %s/giorno",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "sessione: %d colpi, %s spesi, ~%s di profitto stim.",
  ["sniped (listing changed on rescan)"] = "soffiato (la vendita è cambiata alla riscansione)",
  ["sniped for "] = "preso per ",
  ["stack not identified"] = "pila non identificata",
  ["starting full scan..."] = "avvio della scansione completa...",
  ["stopped watching %s"] = "ho smesso di sorvegliare %s",
  ["the Companion wrote prices this addon could not read --"] =
    "il Companion ha scritto prezzi che questo addon non è riuscito a leggere --",
  ["the import failed (%s)"] = "l'importazione è fallita (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "per smaltire %d unità a %s vendite al giorno, con %s immobilizzato per tutto il tempo",
  ["under GoldCap's own floor of %s"] = "sotto la soglia di GoldCap, %s",
  ["unknown evidence"] = "prova sconosciuta",
  ["waiting for previous commodity purchase to settle"] =
    "in attesa che si chiuda l'acquisto di merce precedente",
  ["waiting for previous search result to settle"] =
    "in attesa del risultato di ricerca precedente",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s sorvegliato da vicino -- ricontrollato ogni pochi secondi",
  ["worst case, selling all %d back into the price standing there now"] =
    "nel caso peggiore, rivendendo tutte e %d al prezzo esposto adesso",
  ["worth cancelling"] = "conviene annullare",
  ["would sell at a loss"] = "venderebbe in perdita",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "non hai ancora importato i prezzi del reame -- installa GoldCap Companion (/goldcap companion) o incolla una stringa da goldcap.gg (/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "il tuo client di gioco non ha un font per questa lingua — il testo apparirà come quadrati vuoti",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "la tua importazione ha %d ore -- i prezzi possono essere sbagliati. Incolla una stringa fresca da goldcap.gg (/goldcap import).",
  ["yours"] = "il tuo",
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
  ["×%d%s · made %s · %s"] = "×%d%s · creato %s · %s",
  ["— = nothing is checking this row right now"] =
    "— = nulla sta controllando questa riga in questo momento",
  ["… = a live check is queued for this row"] =
    "… = un controllo dal vivo è in coda per questa riga",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valore di mercato goldcap.gg — ancora nessuna quotazione dal vivo",
  ["no answer %ds ago -- resting"] = "nessuna risposta %ds fa -- in pausa",
  ["the last attempt is still settling -- checking the price again..."] =
    "l'ultimo tentativo non è ancora concluso -- ricontrollo del prezzo...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "In vendita al prezzo che hai fissato su goldcap.gg o meno (gruppo: %s)",
}
