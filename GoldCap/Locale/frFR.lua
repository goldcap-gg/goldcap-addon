local _, GC = ...

-- French. Terminology follows apps/web/messages/fr.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.frFR = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d à %s pièce  (%s au total, %s de commission)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion garde ça à jour : /goldcap companion.",
  [" rows against the live auction house about every "] =
    " lignes contre l'hôtel des ventes en direct, environ toutes les ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · %d hidden"] = " · %d masqués",
  [" · below cost"] = " · sous le prix d'achat",
  [" · identity unresolved"] = " · identité non résolue",
  [" · stale %ds"] = " · %ds d'ancienneté",
  [" — Check again"] = " — vérifiez à nouveau",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — commandes : /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (ou /gc en raccourci)",
  ["%d (whole lot)"] = "%d (lot entier)",
  ["%d days"] = "%d jours",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d affaires du dernier scan -- Full Scan pour actualiser",
  ["%d filtered out as hard to resell"] = "%d écartées car difficiles à revendre",
  ["%d held back"] = "%d retenues",
  ["%d held back from posting"] = "%d non mises en vente",
  ["%d missing"] = "%d manquantes",
  ["%d partial"] = "%d partielles",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d refusées par la vérification en direct -- cliquez sur « HIDDEN %d » au-dessus pour les voir",
  ["%d sales · %s proceeds · %s in the mail"] = "%d ventes · %s de recettes · %s dans le courrier",
  ["%d units"] = "%d unités",
  ["%d units · %d prices"] = "%d unités · %d prix",
  ["%d without a price"] = "%d sans prix",
  ["%d without cost"] = "%d sans prix d'achat",
  ["%d · %d/%d covered"] = "%d · %d/%d couverts",
  ["%d/%d covered"] = "%d/%d couverts",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s l'unité    total %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d unité%s sans prix d'achat",
  [", %d hidden as unsellable"] = ", %d masqués car invendables",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "15 à 60 secondes sur les royaumes chargés. Aucun délai -- relancez quand vous voulez.",
  ["24h trend"] = "Tendance 24 h",
  ["A commodity lists the whole bag total at once; a normal item lists one stack, the largest GoldCap can identify exactly."] =
    "Une marchandise est mise en vente pour tout le total du sac d'un coup ; un objet normal met en vente une pile, la plus grande que GoldCap peut identifier exactement.",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Un tiret signifie que GoldCap ne connaît pas encore le coût de chaque unité — il ne le devinera jamais depuis le prix du marché.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Une piste, pas une promesse : revente à 95% de la valeur de marché importée, pour la quantité que Check approuverait lui-même.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Si plusieurs achats sont regroupés sur une seule ligne, tous sont supprimés.",
  ["AH answered empty %ds ago"] = "l'hôtel des ventes a répondu vide il y a %ds",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · EN PAUSE : ",
  ["AUTO · SCANNING"] = "AUTO · SCAN",
  ["AUTOMATION & ALERTS"] = "AUTOMATISATION & ALERTES",
  ["Auction House did not answer — press Refresh"] =
    "L'hôtel des ventes n'a pas répondu — appuyez sur Refresh",
  ["Auction House is not open"] = "L'hôtel des ventes n'est pas ouvert",
  ["Auto-scan on next AH visit"] = "Scan auto à la prochaine visite à l'HV",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Auto : maintient Full Scan en continu et cède la place dès que vous achetez, ",
  ["Avoid"] = "À éviter",
  ["Background check"] = "Vérification en arrière-plan",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Le seuil de rentabilité est le prix le plus bas qui couvre encore votre coût après la commission. En dessous, vous perdez de l'argent.",
  ["Bundled %s data"] = "Données %s fournies",
  ["Bundled data"] = "Données fournies",
  ["Buy"] = "Acheter",
  ["Buy less"] = "Achète moins",
  ["CANCEL %d"] = "ANNULER %d",
  ["CANCEL LOT?"] = "ANNULER LE LOT ?",
  ["CANCELLING…"] = "ANNULATION…",
  ["CONFIRM"] = "CONFIRMER",
  ["COST"] = "COÛT",
  ["COST / UNIT"] = "COÛT / UNITÉ",
  ["Can't price this"] = "Prix non fiable",
  ["Cancel"] = "Annuler",
  ["Cancel lot?"] = "Annuler le lot ?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Annuler ce lot et perdre la caution — cliquez à nouveau pour confirmer",
  ["Cancel timed out"] = "Délai dépassé pour l'annulation",
  ["Cancelling forfeits the deposit, so this asks for a second click to confirm."] =
    "Annuler fait perdre la caution : un second clic est donc demandé pour confirmer.",
  ["Cancelling lot…"] = "Annulation du lot…",
  ["Cancels this live auction. It does NOT relist it: the deposit is forfeit, and the cancelled items come back by mail, not straight into your bags."] =
    "Annule cette enchère en cours. Elle n'est PAS remise en vente : la caution est perdue et les objets annulés reviennent par courrier, pas directement dans vos sacs.",
  ["Cannot post this position"] = "Impossible de mettre cette position en vente",
  ["Cannot remove this entry"] = "Impossible de supprimer cette entrée",
  ["Cannot repost this lot"] = "Impossible de remettre ce lot en vente",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limité par la vitesse réelle de vente, pas par ta bourse.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Il reste des enchères moins chères, mais au rythme de cet objet elles partent en quelques heures.",
  ["Check"] = "Vérifier",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check recalcule à partir du carnet d'ordres en direct avant que l'or ne bouge, et peut donner moins — ou refuser — si le marché a bougé depuis votre dernier import.",
  ["Checked against the live order book a moment ago."] =
    "Vérifié à l'instant sur le carnet d'ordres en direct.",
  ["Checked: %d of the top %d on screen"] = "Vérifiées : %d sur les %d premières à l'écran",
  ["Checking prices…"] = "Vérification des prix…",
  ["Checking this item's price…"] = "Vérification du prix de cet objet…",
  ["Checking..."] = "Vérification...",
  ["Clear to buy"] = "Feu vert pour acheter",
  ["Click Confirm to post"] = "Cliquez sur Confirm pour mettre en vente",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Un nouveau clic annule l'enchère en cours. Elle n'est pas remise en vente : la caution est perdue et les objets reviennent par courrier plutôt que directement dans vos sacs.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Un nouveau clic supprime définitivement ce coût saisi à la main.",
  ["Close"] = "Fermer",
  ["Companion sync rejected:"] = "Synchronisation Companion refusée :",
  ["Confidence"] = "Confiance",
  ["Confirm"] = "Confirmer",
  ["Confirm the cancel"] = "Confirmer l'annulation",
  ["Confirm the removal"] = "Confirmer la suppression",
  ["Cost per unit"] = "Coût par unité",
  ["Cost unknown for %d of %d"] = "Prix d'achat inconnu pour %d sur %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Coûte plus que ne l'autorise votre limite par achat.",
  ["Could not find the queue's next item to post — try again"] =
    "Objet suivant de la file de mise en vente introuvable — réessayez",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Lot suivant de la file d'annulation introuvable — réessayez",
  ["DEAL THRESHOLDS"] = "SEUILS D'AFFAIRE",
  ["DISC"] = "REMISE",
  ["DISPLAY"] = "AFFICHAGE",
  ["DONE"] = "TERMINÉ",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Supprime un coût saisi à la main dans Définir le coût — jamais un achat que GoldCap a lui-même capturé ou rattaché à votre courrier.",
  ["Discount"] = "Remise",
  ["Discount vs market value from your GoldCap import"] =
    "Remise par rapport à la valeur de marché de votre import GoldCap",
  ["Dump-trend cap %"] = "Plafond de tendance baissière %",
  ["Duration"] = "Durée",
  ["Enlarge the window to see details"] = "Agrandissez la fenêtre pour voir les détails",
  ["Enter a whole quantity"] = "Saisissez une quantité entière",
  ["Enter an exact positive cost"] = "Saisissez un prix d'achat exact et positif",
  ["Entry price (avg fill)"] = "Prix d'entrée (exécution moy.)",
  ["Entry total"] = "Total à l'entrée",
  ["Est. profit"] = "Bénéfice est.",
  ["FIFO allocations"] = "Affectations FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Récupération d'un prix frais pour cet objet — réappuyez sur Post dans un instant",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Récupération d'un prix frais pour ce lot — réappuyez sur Repost dans un instant",
  ["Finish the pending post first"] = "Terminez d'abord la mise en vente en cours",
  ["Finish the pending post or repost first"] =
    "Terminez d'abord la mise en vente ou la remise en vente en cours",
  ["Font scale"] = "Taille de police",
  ["Full pass over them: %.1fs"] = "Passage complet : %.1fs",
  ["Full pass over them: measuring..."] = "Passage complet : mesure en cours...",
  ["GOOD = solid discount + profit"] = "GOOD = remise solide + bénéfice",
  ["GOOD — min discount %"] = "GOOD — remise minimale %",
  ["GOOD — min sold/day"] = "GOOD — ventes min./jour",
  ["Gold tied up"] = "Or immobilisé",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap ne peut pas déterminer de quelle pile de sac il s'agit",
  ["GoldCap data age"] = "Ancienneté des données GoldCap",
  ["GoldCap re-checks the top "] = "GoldCap revérifie les ",
  ["GoldCap value"] = "Valeur GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Importer les prix du royaume",
  ["GoldCap's"] = "de GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "La suggestion de GoldCap pour cet objet, et le prix qu'il utiliserait.",
  ["GoldCap: %s -- %s"] = "GoldCap : %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap : vérifié en direct -- achat sûr",
  ["Gone"] = "Parti",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Grisé signifie que la cotation a vieilli ; Post et Repost la rafraîchissent avant d'agir.",
  ["HIDDEN 0"] = "MASQUÉES 0",
  ["HIDE DETAILS ▾"] = "MASQUER LES DÉTAILS ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = grosse remise + fort bénéfice + ventes/jour prouvées",
  ["HOT — min discount %"] = "HOT — remise minimale %",
  ["HOT — min sold/day"] = "HOT — ventes min./jour",
  ["Held back from cancelling"] = "Retenu de l'annulation",
  ["Held back from the queue"] = "Retenu de la file",
  ["ITEM"] = "OBJET",
  ["If it clears"] = "Si ça s'écoule",
  ["Import"] = "Importer",
  ["Import failed:"] = "Échec de l'import :",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Installez le GoldCap Companion gratuit pour garder les prix à jour automatiquement (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "C'est le prix à battre pour vendre vite — pas la valeur de l'objet. Un vendeur pressé peut descendre bien en dessous de la valeur, et GoldCap refusera de le suivre : voyez WHAT TO DO pour le prix auquel il mettrait réellement en vente.",
  ["It will list stock GoldCap never saw you buy — not knowing what something cost is a reason to report the profit as unknown, not a reason to refuse to sell it."] =
    "Il mettra aussi en vente du stock dont GoldCap n'a jamais vu l'achat — ignorer ce qu'une chose a coûté est une raison d'annoncer le profit comme inconnu, pas de refuser de la vendre.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Il n'inventera pas un coût à partir du prix du marché : le profit reste inconnu tant que vous n'en saisissez pas un.",
  ["Item"] = "Objet",
  ["Item %d"] = "Objet %d",
  ["LISTED"] = "EN VENTE",
  ["Language"] = "Langue",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Langue changée. Tapez /reload pour l'appliquer partout.",
  ["Last result: %ds ago"] = "Dernier résultat : il y a %ds",
  ["Last result: none yet this visit"] = "Dernier résultat : aucun pour cette visite",
  ["Listed"] = "En vente",
  ["Listed at %s — far below market. Repost."] =
    "En vente à %s — bien sous le marché. Remettez en vente.",
  ["Listed value"] = "Valeur en vente",
  ["Listings"] = "Ventes",
  ["Lists what is sitting in your bags at the price shown under WHAT TO DO."] =
    "Met en vente ce qui est dans vos sacs, au prix indiqué sous QUE FAIRE.",
  ["Live ask"] = "Prix en direct",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lot annulé ; attendez qu'il revienne dans les sacs",
  ["MARKET"] = "MARCHÉ",
  ["MARKET / UNIT"] = "MARCHÉ / UNITÉ",
  ["MATCH"] = "ÉGALER",
  ["Market per unit"] = "Marché à l'unité",
  ["Market reference"] = "Référence de marché",
  ["Max wallet per buy %"] = "Part max. de votre or par achat %",
  ["Min profit per buy (gold)"] = "Profit min. par achat (or)",
  ["Missing cost"] = "Coût manquant",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "PAS ENCORE SUR GOLDCAP.GG — SYNCHRONISÉ AU /RELOAD OU À LA DÉCONNEXION",
  ["NOTHING TO CANCEL"] = "RIEN À ANNULER",
  ["NOTHING TO POST"] = "RIEN À METTRE EN VENTE",
  ["Needs a live price check before it can be bought."] =
    "Nécessite une vérification du prix en direct avant tout achat.",
  ["No deals passed the safety checks right now."] =
    "Aucune affaire ne passe les vérifications de sécurité pour l'instant.",
  ["No deals to show -- and no realm prices yet."] =
    "Aucune affaire à afficher -- et pas encore de prix du royaume.",
  ["No deals yet."] = "Pas encore d'affaires.",
  ["No exact auction key"] = "Pas de clé d'enchère exacte",
  ["No exact bag stack"] = "Pas de pile de sac exacte",
  ["No exact bag variant"] = "Pas de variante de sac exacte",
  ["No live listings came back for this item."] =
    "Aucune enchère active n'est revenue pour cet objet.",
  ["No safe resale price could be worked out."] = "Impossible d'établir un prix de revente sûr.",
  ["No sales data for this item."] = "Aucune donnée de vente pour cet objet.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Aucune vente enregistrée -- ouvrez votre boîte aux lettres avec GoldCap chargé",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Pas assez d'unités à l'hôtel des ventes pour cette quantité.",
  ["Not in your bags or listed — mail or bank?"] =
    "Ni dans vos sacs ni en vente — courrier ou banque ?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Pas sous la main — le stock est dans le courrier, à la banque ou sur un autre personnage",
  ["Nothing is being held back."] = "Rien n'est retenu.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Après cet achat il ne reste rien contre quoi vendre : il n'y a donc pas de prix de sortie.",
  ["Nothing listed on the AH right now"] = "Rien en vente à l'hôtel des ventes pour l'instant",
  ["Nothing queued to cancel"] = "Rien à annuler dans la file",
  ["Nothing queued to post"] = "Rien à mettre en vente dans la file",
  ["Nothing to remove"] = "Rien à supprimer",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "SUR GOLDCAP.GG — %d DERNIERS JOURS",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "SUR GOLDCAP.GG — %d DERNIERS JOURS, DERNIÈRES %d SUR %d",
  ["ON THE AUCTION HOUSE"] = "À L'HÔTEL DES VENTES",
  ["Once the mail arrives, list it again yourself at the new price -- from this same row."] =
    "Une fois le courrier arrivé, remettez-le en vente vous-même au nouveau prix — depuis cette même ligne.",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Un scan unique de tout l'hôtel des ventes via des requêtes paginées. Prend environ ",
  ["Open the Auction House first."] = "Ouvrez d'abord l'hôtel des ventes.",
  ["Open the Auction House to begin scanning."] =
    "Ouvrez l'hôtel des ventes pour lancer le scan.",
  ["Open the deals board. /gc for commands."] = "Ouvre le tableau des affaires. /gc pour les commandes.",
  ["POST %d"] = "VENDRE %d",
  ["POSTING"] = "MISE EN VENTE",
  ["POSTING…"] = "MISE EN VENTE…",
  ["PRICE"] = "PRIX",
  ["PRICE ROSE %.1fx"] = "LE PRIX A MONTÉ DE %.1fx",
  ["PRICING %d/%d"] = "PRIX %d/%d",
  ["PRICING…"] = "PRIX…",
  ["PROFIT"] = "PROFIT",
  ["PROFIT / UNIT"] = "BÉNÉFICE / UNITÉ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Associez ou mettez à jour le GoldCap Companion pour voir les bénéfices de goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Collez la chaîne de votre royaume depuis goldcap.gg et appuyez sur Import.",
  ["Per-unit price of this auction"] = "Prix unitaire de cette enchère",
  ["Position scope changed"] = "Périmètre de la position modifié",
  ["Positions without a cost or a live price are excluded."] =
    "Les positions sans prix d'achat ni prix en direct sont exclues.",
  ["Post"] = "Vendre",
  ["Post confirmation expired"] = "Confirmation de mise en vente expirée",
  ["Post the next queued item"] = "Mettre en vente l'objet suivant de la file",
  ["Posting failed"] = "Échec de la mise en vente",
  ["Posting timed out"] = "Délai dépassé pour la mise en vente",
  ["Posting unavailable"] = "Mise en vente indisponible",
  ["Posting…"] = "Mise en vente…",
  ["Press Full Scan to find deals."] = "Appuyez sur Full Scan pour trouver des affaires.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Appuyez sur Scan pour parcourir tout l'hôtel des ventes une fois, ou sur Auto pour scanner en continu.",
  ["Previous removal selection cleared"] = "Sélection de suppression précédente effacée",
  ["Previous repost selection cleared"] = "Sélection de remise en vente précédente effacée",
  ["Price"] = "Prix",
  ["Priced from bundled sample data, not from your realm."] =
    "Prix issu des données d'exemple fournies, pas de votre royaume.",
  ["Prices up to date"] = "Prix à jour",
  ["Prices up to date · %d did not answer"] = "Prix à jour · %d sans réponse",
  ["Pricing %d/%d…"] = "Cotation %d/%d…",
  ["Pricing…"] = "Cotation…",
  ["Profit"] = "Profit",
  ["Profit per unit"] = "Profit par unité",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Le suivi des bénéfices est une fonction goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "Les achats sont désactivés dans cette version.",
  ["QTY"] = "QTÉ",
  ["Quantity exceeds missing units"] = "La quantité dépasse les unités manquantes",
  ["Quantity is capped by how fast this item actually sells."] =
    "La quantité est plafonnée par la vitesse réelle de vente de cet objet.",
  ["REALIZED PROFIT"] = "BÉNÉFICE RÉALISÉ",
  ["REFRESH"] = "ACTUALISER",
  ["RESET WINDOW"] = "RÉINITIALISER LA FENÊTRE",
  ["Reason"] = "Raison",
  ["Refresh"] = "Actualiser",
  ["Refresh waiting for prior result"] = "L'actualisation attend le résultat précédent",
  ["Refreshing listings…"] = "Actualisation des ventes…",
  ["Refused so far: %d"] = "Refusées jusqu'ici : %d",
  ["Removal confirmation expired"] = "Confirmation de suppression expirée",
  ["Remove"] = "Supprimer",
  ["Remove this cost"] = "Supprimer ce coût",
  ["Remove?"] = "Supprimer ?",
  ["Removed"] = "Supprimé",
  ["Removed %d entries"] = "%d entrées supprimées",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Supprime tous les achats saisis à la main dans ce groupe -- cliquez à nouveau pour confirmer",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Supprime cet achat saisi à la main -- cliquez à nouveau pour confirmer",
  ["Repost"] = "Remettre en vente",
  ["Repost confirmation expired"] = "Confirmation de remise en vente expirée",
  ["Right-click to stop watching this item"] =
    "Clic droit pour arrêter de surveiller cet objet",
  ["Right-click to watch this item closely"] = "Clic droit pour surveiller cet objet de près",
  ["SAFETY"] = "SÉCURITÉ",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "ENREGISTRÉ AUSSITÔT · ÉCHAP OU DONE POUR FERMER",
  ["SCAN"] = "SCAN",
  ["SCANNING…"] = "SCAN EN COURS…",
  ["SESSION %s%s · %d BUYS"] = "SESSION %s%s · %d ACHATS",
  ["SHOW DETAILS ▸"] = "AFFICHER LES DÉTAILS ▸",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = remise si extrême qu'il s'agit sans doute d'une arnaque ou d'un marché mal évalué",
  ["Sales are costed from your oldest units first"] =
    "Les ventes sont imputées d'abord sur vos unités les plus anciennes",
  ["Sell-through"] = "Taux d'écoulement",
  ["Sellers"] = "Vendeurs",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Se vend trop rarement — vous le garderiez longtemps.",
  ["Set cost"] = "Définir le coût",
  ["Settings"] = "Réglages",
  ["Snapshot value"] = "Valeur de l'instantané",
  ["Sold per day"] = "Ventes par jour",
  ["Sold/day"] = "Ventes/jour",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Triez dessus pour décider quoi vérifier en premier, pas quoi acheter.",
  ["Sound on HOT deal"] = "Son sur une affaire HOT",
  ["Source age"] = "Ancienneté de la source",
  ["Spike-trend threshold %"] = "Seuil de flambée %",
  ["Status"] = "Statut",
  ["Stress exit unit"] = "Prix de sortie sous stress",
  ["Stress profit"] = "Bénéfice sous stress",
  ["THE BOOK"] = "LE CARNET D'ORDRES",
  ["TIER"] = "PALIER",
  ["TOTAL"] = "TOTAL",
  ["TREND"] = "TENDANCE",
  ["Tell GoldCap what you actually paid for these units."] =
    "Indiquez à GoldCap ce que vous avez réellement payé pour ces unités.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "L'hôtel des ventes n'a pas indiqué de caution : le coût est donc inconnu.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Le Companion synchronise, mais cet addon n'a pas pu lire ce qu'il a écrit :",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "Le tableau l'a classé d'après l'instantané importé. Le carnet en direct ne le confirme pas.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Le bouton attend un instant avant d'être cliquable : un double-clic accidental ne suffit jamais.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Le prix le plus bas demandé actuellement par QUELQU'UN D'AUTRE, d'après une requête en direct à l'hôtel des ventes. Vos propres ventes sont exclues, donc le chiffre ne se poursuit jamais lui-même vers le bas.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Les données de cet objet sont malformées : GoldCap refuse de deviner.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "Le Companion gratuit pour ordinateur garde vos prix à jour automatiquement et synchronise vos ventes. Copiez le lien (Ctrl+C) et ouvrez-le dans un navigateur :",
  ["The liquidity data is not reliable enough to act on."] =
    "Les données de liquidité ne sont pas assez fiables pour agir.",
  ["The market value is an estimate, not a measurement."] =
    "La valeur de marché est une estimation, pas une mesure.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Les données de prix ont plus de trois heures. Synchronisez le Companion puis faites /reload — l'addon ne lit ses données qu'au chargement de l'interface.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Le prix baisse ; y entrer, c'est exactement comme on se retrouve coincé.",
  ["The price is the last one GoldCap fetched, at most 45 seconds old — not a fresh check made at the moment you click. If it changes between arming the post and confirming it, the post is abandoned rather than sent at the old price."] =
    "Le prix est le dernier récupéré par GoldCap, vieux de 45 secondes au plus — pas une vérification faite au moment du clic. S'il change entre l'armement de la mise en vente et sa confirmation, celle-ci est abandonnée plutôt qu'envoyée à l'ancien prix.",
  ["The price moved and the trade is no longer safe."] =
    "Le prix a bougé et l'opération n'est plus sûre.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Le profit n'atteint pas votre minimum une fois la commission de 5 % et la caution payées.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Aucune annulation possible. Le premier clic en demande un second pour confirmer.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "C'est un objet de royaume, et GoldCap ne vérifie que les prix des marchandises.",
  ["Tier"] = "Palier",
  ["Too few sellers to read a real price."] = "Trop peu de vendeurs pour lire un vrai prix.",
  ["Too little of what is listed actually sells."] =
    "Trop peu de ce qui est mis en vente se vend réellement.",
  ["Too little price history to trust the value."] =
    "Trop peu d'historique de prix pour se fier à cette valeur.",
  ["Total cost to buy this auction"] = "Coût total pour acheter cette enchère",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Saisis un prix en or, ou vide le champ pour prendre celui de GoldCap",
  ["UNDERCUT"] = "SOUS-COTER",
  ["UNIT"] = "UNITÉ",
  ["Unit price"] = "Prix unitaire",
  ["Unknown"] = "Inconnu",
  ["Unknown item"] = "Objet inconnu",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "Inconnu signifie que le coût est incomplet — complétez-le avec Définir le coût.",
  ["WATCH (computed SAFE)"] = "WATCH (calculé SÛR)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = remisé mais liquidité non prouvée ou bénéfice faible",
  ["WHAT TO DO"] = "QUE FAIRE",
  ["WHAT YOU PAID"] = "CE QUE TU AS PAYÉ",
  ["WHEN"] = "QUAND",
  ["Waiting for Auction House…"] = "En attente de l'hôtel des ventes…",
  ["Waiting for a live price"] = "En attente d'un prix en direct",
  ["Waiting for the Auction House…"] = "En attente de l'hôtel des ventes…",
  ["Waiting for the purchase to finish…"] = "En attente de la fin de l'achat…",
  ["Wall absorb window (hours)"] = "Fenêtre d'absorption du mur (heures)",
  ["Watching closely: %d item%s"] = "Surveillés de près : %d objet%s",
  ["Watching — pinned, but not a deal right now"] =
    "Surveillé — épinglé, mais pas une affaire pour l'instant",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Ce qu'une unité vous a réellement coûté, en moyenne sur les achats encore en stock.",
  ["What to do"] = "Que faire",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Ce qui vous reste sur une unité si elle se vend au prix du marché : prix de vente, moins les 5 % de commission, moins votre coût.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Ce que totalisent vos enchères en cours pour cet objet à leur prix actuel.",
  ["Window position & size"] = "Position et taille de la fenêtre",
  ["Won't buy"] = "N'achètera pas",
  ["Worst case back"] = "Retour au pire",
  ["Worth doing when someone has undercut you; not worth it if the price barely moved."] =
    "Utile quand quelqu'un vous a sous-coté ; inutile si le prix a à peine bougé.",
  ["YOUR PRICE"] = "TON PRIX",
  ["You paid"] = "Payé",
  ["You pay"] = "Tu paies",
  ["You would get"] = "Tu recevrais",
  ["You would pay"] = "Tu paierais",
  ["any figure here would be invented out of the very number being refused"] =
    "tout chiffre ici serait inventé à partir du nombre même qui est refusé",
  ["auto off"] = "auto désactivé",
  ["auto-synced %dh ago"] = "synchronisé automatiquement il y a %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "données synchronisées pour %s chargées (%s d'ancienneté)",
  ["auto-synced data stale -- /goldcap import"] =
    "données synchronisées périmées -- /goldcap import",
  ["auto: paused"] = "auto : en pause",
  ["below the %s you paid"] = "sous les %s que tu as payés",
  ["big buy"] = "gros achat",
  ["blue is already yours"] = "le bleu est déjà à toi",
  ["bought %d x item %d"] = "acheté %d x objet %d",
  ["bought %d x item %d after AH close"] =
    "acheté %d x objet %d après la fermeture de l'hôtel des ventes",
  ["buying commodity..."] = "achat de la marchandise...",
  ["cheapest not yours %s"] = "le moins cher qui n'est pas à toi %s",
  ["checking live price..."] = "vérification du prix en direct...",
  ["checking live safety..."] = "vérification de la sécurité en direct...",
  ["commodity no longer available -- someone bought it out"] =
    "marchandise indisponible -- quelqu'un l'a rachetée",
  ["commodity purchase failed"] = "échec de l'achat de la marchandise",
  ["confirmed commodity purchase failed after AH close"] =
    "achat de marchandise confirmé échoué après la fermeture de l'hôtel des ventes",
  ["confirming purchase..."] = "confirmation de l'achat...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "prix d'achat incomplet -- renseignez-le pour obtenir un conseil de remise en vente",
  ["cost unknown"] = "coût inconnu",
  ["data from goldcap.gg · synced %s ago"] = "données de goldcap.gg · synchronisées il y a %s",
  ["due -- will be asked next pass"] = "à faire -- sera demandé au prochain passage",
  ["fair"] = "moyenne",
  ["finish the pending buy first"] = "terminez d'abord l'achat en cours",
  ["full scan already in progress"] = "scan complet déjà en cours",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "scan complet terminé : %d affaire%s issues de %d groupe%s d'objets%s",
  ["full scan interrupted -- confirm your purchase"] =
    "scan complet interrompu -- confirmez votre achat",
  ["full scan stalled -- press Full Scan to retry"] =
    "scan complet bloqué -- appuyez sur Full Scan pour réessayer",
  ["full scan stalled -- retrying shortly"] = "scan complet bloqué -- nouvelle tentative bientôt",
  ["gold is where your price lands"] = "l'or marque où ton prix se place",
  ["gold is where your price lands, blue is already yours"] =
    "l'or marque où ton prix se place, le bleu est déjà à toi",
  ["gone / price changed"] = "disparu / prix modifié",
  ["high"] = "élevée",
  ["identity unresolved (variant item -- not priced by design)"] =
    "identité non résolue (objet à variantes -- volontairement sans prix)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "si tu achètes les %d et les revends au prix affiché en ce moment",
  ["import %dh old"] = "import vieux de %dh",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "import périmé -- /goldcap import ou /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "%d objets importés pour %s (%s) — les prix sont actifs.",
  ["in the mail"] = "dans le courrier",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "c'est ce que ce marché absorbe — au-delà, tu achètes du stock qui te restera sur les bras",
  ["item %d"] = "objet %d",
  ["item %d: %s"] = "objet %d : %s",
  ["item variant unresolved"] = "variante de l'objet non résolue",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "dernières 24 h — %d ventes, %s brut, %s de commission, %d achats, %s dépensés",
  ["listing gone -- already bought out or price changed"] =
    "vente disparue -- déjà rachetée ou prix modifié",
  ["listing gone -- bought out or repriced"] = "l'enchère a disparu : achetée ou repositionnée",
  ["live safety confirmed -- click Buy to purchase"] =
    "sécurité confirmée en direct -- cliquez sur Buy pour acheter",
  ["live verification required"] = "vérification en direct requise",
  ["low"] = "faible",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "import manuel -- Companion garde ça à jour : /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "besoin d'un prix frais -- appuyez sur Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "pas de confirmation du serveur -- l'achat a pu aboutir quand même, vérifiez votre courrier. Fermer cette fenêtre ne l'annulera pas.",
  ["no live price yet"] = "pas encore de prix en direct",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "pas encore de prix -- /goldcap companion ou /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "aucune confirmation d'achat reçue -- Cancel puis réessayez",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "aucune vente enregistrée — ouvrez votre boîte aux lettres avec GoldCap chargé et elles seront lues sur les factures",
  ["no stock in bags or listed -- nothing to price for"] =
    "aucun stock en sacs ni en vente -- rien à coter",
  ["none"] = "aucun",
  ["not enough gold -- total %s, you have %s"] = "pas assez d'or -- total %s, vous avez %s",
  ["not enough gold for this quote -- Cancel"] = "pas assez d'or pour cette cotation -- Cancel",
  ["not ready to cancel"] = "pas prêt à annuler",
  ["not ready to post"] = "pas prêt à mettre en vente",
  ["nothing listed"] = "rien en vente",
  ["of %d"] = "sur %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "ou collez une chaîne depuis goldcap.gg avec /goldcap import.",
  ["over %d position%s"] = "sur %d positions%s",
  ["paid sale unresolved"] = "vente encaissée non résolue",
  ["placing bid..."] = "dépôt de l'enchère...",
  ["price confirmed -- click Buy to purchase"] = "prix confirmé -- cliquez sur Buy pour acheter",
  ["price rose %.1fx — still safe, confirm"] = "le prix a monté de %.1fx — toujours sûr, confirmez",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "les prix chargés viennent de %s (%s) mais vous jouez en %s — chaque remise et chaque profit est mesuré sur un autre marché",
  ["purchase canceled"] = "achat annulé",
  ["purchase complete"] = "achat terminé",
  ["purchase identity unresolved"] = "identité de l'achat non résolue",
  ["purchase pending exact cost"] = "achat en attente du coût exact",
  ["purchase total unavailable — inspect mailbox"] =
    "total de l'achat indisponible — regardez votre boîte aux lettres",
  ["quote %s -- click Confirm to buy"] = "cotation %s -- cliquez sur Confirm pour acheter",
  ["quote %ss ago"] = "cotation il y a %ss",
  ["quote expired -- Refresh to re-check the price"] =
    "cotation expirée -- Refresh pour revérifier le prix",
  ["recent sales (newest first):"] = "ventes récentes (les plus récentes d'abord) :",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "région %s — inclus : %d objets (%s), importés : %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "région corrigée sur %d lignes du journal ; %d ventes rattachées à leur stock",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "remettre en vente maintenant figerait une perte ou un blocage -- gardez",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "%d enregistrement%s d'achat en double supprimés, laissés par un bug d'analyse du courrier",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "%d enregistrement%s de vente en double supprimés, laissés par un bug d'analyse du courrier",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    " s. Les lignes refusées sont masquées. L'achat reste toujours un clic que vous faites.",
  ["sale name ambiguous"] = "nom de la vente ambigu",
  ["sale proceeds pending"] = "recettes de vente en attente",
  ["scanned %d listings over %d passes"] = "%d ventes scannées en %d passages",
  ["scanning auction house..."] = "scan de l'hôtel des ventes...",
  ["scanning… %d results · %d deals%s"] = "scan… %d résultats · %d affaires%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "cherchez vous-même à l'hôtel des ventes, ou regardez votre courrier. Cliquez pour basculer.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "se vend %s/jour",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "session : %d prises, %s dépensés, ~%s de bénéfice est.",
  ["sniped (listing changed on rescan)"] = "raflé (la vente a changé au rescan)",
  ["sniped for "] = "sniper pour ",
  ["starting full scan..."] = "démarrage du scan complet...",
  ["stopped watching %s"] = "surveillance de %s arrêtée",
  ["the Companion wrote prices this addon could not read --"] =
    "le Companion a écrit des prix que cet addon n'a pas pu lire --",
  ["the import failed (%s)"] = "l'import a échoué (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "pour écouler %d unités à %s ventes par jour, avec %s immobilisé pendant tout ce temps",
  ["under GoldCap's own floor of %s"] = "sous le plancher de GoldCap, %s",
  ["unknown evidence"] = "preuve inconnue",
  ["waiting for previous commodity purchase to settle"] =
    "en attente du règlement de l'achat de marchandise précédent",
  ["waiting for previous search result to settle"] =
    "en attente du résultat de recherche précédent",
  ["waiting for server... full scan will start automatically"] =
    "en attente du serveur... le scan complet démarrera tout seul",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s surveillé de près -- revérifié toutes les quelques secondes",
  ["worst case, selling all %d back into the price standing there now"] =
    "au pire, en revendant les %d au prix affiché en ce moment",
  ["would sell at a loss"] = "se vendrait à perte",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "vous n'avez pas encore importé les prix du royaume -- installez GoldCap Companion (/goldcap companion) ou collez une chaîne depuis goldcap.gg (/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "votre client de jeu n'a pas de police pour cette langue — le texte s'affichera en carrés vides",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "votre import date de %d heures -- les prix peuvent être faux. Collez une chaîne fraîche depuis goldcap.gg (/goldcap import).",
  ["yours"] = "le tien",
  ["» needs price"] = "» prix requis",
  ["×%d in bags"] = "×%d en sacs",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d dans vos sacs · Post en met %d en vente, la plus grande pile",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d dans vos sacs · aucune pile que GoldCap puisse identifier exactement",
  ["×%d in your bags, ready to list"] = "×%d dans vos sacs, prêts à être vendus",
  ["×%d listed"] = "×%d en vente",
  ["×%d listed at %s each"] = "×%d en vente à %s pièce",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · acheté %s · %s · %s",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valeur de marché goldcap.gg — pas encore de cotation en direct",
}
