local _, GC = ...

-- French. Terminology follows apps/web/messages/fr.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.frFR = {
  ["  %s · need %d · have %d · buy %d · %s"] = "  %s · besoin %d · possédé %d · à acheter %d · %s",
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d à %s pièce  (%s au total, %s de commission)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion garde ça à jour : /goldcap companion.",
  [" · %d keys"] = " · %d clés",
  [" · below cost"] = " · sous le prix d'achat",
  [" · identity unresolved"] = " · identité non résolue",
  [" · stale %ds"] = " · %ds d'ancienneté",
  [". Check again"] = ". Vérifiez à nouveau",
  [" · commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " · commandes : /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (ou /gc en raccourci)",
  ["%d (whole lot)"] = "%d (lot entier)",
  ["%d ahead of you"] = "%d devant toi",
  ["%d at %s"] = "%d à %s",
  ["%d caps · %s"] = "%d plafonds · %s",
  ["%d days"] = "%d jours",
  ["%d deals from your last scan. Full Scan to refresh"] =
    "%d affaires du dernier scan. Full Scan pour actualiser",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "%d écartées : difficiles à revendre, ou sous votre profit min. par achat",
  ["%d held back"] = "%d retenues",
  ["%d hidden: the live check refused them"] = "%d masqués : la vérification en direct les a refusés",
  ["%d hits"] = "%d trouvailles",
  ["%d in %d lots"] = "%d en %d lots",
  ["%d in 1 lot"] = "%d en 1 lot",
  ["%d lines"] = "%d lignes",
  ["%d lots, %s asked"] = "%d lots, %s demandés",
  ["%d of %d"] = "%d sur %d",
  ["%d of %d at or under your cap"] = "%d sur %d à ton plafond ou moins",
  ["%d of %d done"] = "%d sur %d faits",
  ["%d prices in one request · books still loading"] =
    "%d prix en une seule requête · carnets en cours de chargement",
  ["%d refused by live checks. Press \"HIDDEN %d\" above to review them"] =
    "%d refusées par la vérification en direct. Cliquez sur « HIDDEN %d » au-dessus pour les voir",
  ["%d units"] = "%d unités",
  ["1 unit"] = "1 unité",
  ["%d units · %d prices"] = "%d unités · %d prix",
  ["%d · %d/%d covered"] = "%d · %d/%d couverts",
  ["%d/%d covered"] = "%d/%d couverts",
  ["%d× %s"] = "%d× %s",
  ["%d× %s · %s each · %s"] = "%d× %s · %s l'unité · %s",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s l'unité    total %s -> %s",
  ["%s ahead"] = "%s devant",
  ["%s needs a number, for example /gc weights %s 1.5"] = "%s a besoin d'un nombre, par exemple /gc weights %s 1.5",
  ["%s under you"] = "%s sous ton prix",
  ["%s units in %d prices"] = "%s unités sur %d prix",
  ["%s · %s under market"] = "%s · %s sous le marché",
  ["%s · at market price"] = "%s · au prix du marché",
  ["%s: %d unit%s without a cost"] = "%s : %d unité%s sans prix d'achat",
  ["%s+ ahead"] = "%s+ devant",
  ["%s+, %d prices read"] = "%s+, %d prix lus",
  ["..."] = "...",
  ["1 lot, %s asked"] = "1 lot, %s demandés",
  ["24h trend"] = "Tendance 24 h",
  ["A dash means GoldCap does not know the cost of every unit yet. It will never guess one from the market price."] =
    "Un tiret signifie que GoldCap ne connaît pas encore le coût de chaque unité. Il ne le devinera jamais depuis le prix du marché.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Une piste, pas une promesse : revente à 95% de la valeur de marché importée, pour la quantité que Check approuverait lui-même.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Si plusieurs achats sont regroupés sur une seule ligne, tous sont supprimés.",
  ["AH answered empty %ds ago"] = "l'hôtel des ventes a répondu vide il y a %ds",
  ["AH value"] = "Valeur HV",
  ["AH, cheapest version"] = "HV, version la moins chère",
  ["AUTO"] = "AUTO",
  ["AUTO · SCANNING"] = "AUTO · SCAN",
  ["AUTOMATION & ALERTS"] = "AUTOMATISATION & ALERTES",
  ["AVOID"] = "ÉVITER",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Au-delà de cette hausse sur 24 heures, la valeur de marché est considérée comme une flambée et est atténuée.",
  ["Above your price: quoted %s, your price %s"] = "Au-dessus de ton prix : proposé %s, ton prix %s",
  ["Alert target"] = "Cible de l'alerte",
  ["Alerts"] = "Alertes",
  ["All"] = "Tout",
  ["Archive this run"] = "Archiver cette liste",
  ["Archived"] = "Archivées",
  ["Asks for a second click to confirm."] = "Demande un second clic pour confirmer.",
  ["At a vendor"] = "Chez un marchand",
  ["At your pace you reach it at level %d."] = "À votre rythme, vous l'atteignez au niveau %d.",
  ["At your pace you will be %s short at level 40."] = "À votre rythme, il vous manquera %s au niveau 40.",
  ["At your price"] = "À ton prix",
  ["Auction House did not answer. Press Refresh"] =
    "L'hôtel des ventes n'a pas répondu. Appuie sur Refresh",
  ["Auction House is not open"] = "L'hôtel des ventes n'est pas ouvert",
  ["Auto-scan on next AH visit"] = "Scan auto à la prochaine visite à l'HV",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto : maintient Full Scan en continu et cède la place dès que vous achetez, cherchez vous-même à l'hôtel des ventes, ou regardez votre courrier. Cliquez pour basculer.",
  ["Avoid"] = "À éviter",
  ["BOOKS %d/%d"] = "CARNETS %d/%d",
  ["BUY %d"] = "ACHETER %d",
  ["BUY (unverified)"] = "ACHETER (non vérifié)",
  ["Background check"] = "Vérification en arrière-plan",
  ["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."] =
    "Blizzard n'a pas encore publié le coût de la monte. Tapez /gc mount et le coût que vous prévoyez.",
  ["Blizzard's price: %s"] = "Prix de Blizzard : %s",
  ["Blizzard's price: %s · %d s left"] = "Prix de Blizzard : %s · encore %d s",
  ["Bought"] = "Acheté",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Le seuil de rentabilité est le prix le plus bas qui couvre encore votre coût après la commission. En dessous, vous perdez de l'argent.",
  ["Bundled %s data"] = "Données %s fournies",
  ["Bundled data"] = "Données fournies",
  ["Buy"] = "Acheter",
  ["Buy it whole instead"] = "L'acheter entier plutôt",
  ["Buy less"] = "Achète moins",
  ["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"] = "Achats : %s · %d lignes · %d à acheter · %d chez le marchand · dépensé %s · reste ~%s",
  ["Buy: no run selected."] = "Achats : aucune liste choisie.",
  ["CANCEL %d"] = "ANNULER %d",
  ["CANCEL LOT?"] = "ANNULER LE LOT ?",
  ["CANCELLING…"] = "ANNULATION…",
  ["CONFIRM"] = "CONFIRMER",
  ["COST"] = "COÛT",
  ["COST / UNIT"] = "COÛT / UNITÉ",
  ["Can't price this"] = "Prix non fiable",
  ["Cancel"] = "Annuler",
  ["Cancel lot"] = "Annuler",
  ["Cancel lot?"] = "Annuler ?",
  ["Cancel this lot and lose its deposit. Click again to confirm"] =
    "Annuler ce lot et perdre la caution. Clique à nouveau pour confirmer",
  ["Cancel timed out"] = "Délai dépassé pour l'annulation",
  ["Cancelling lot…"] = "Annulation du lot…",
  ["Cancels this live auction. It does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Annule cette enchère en cours. Elle n'est PAS remise en vente. La caution est perdue et les objets reviennent par courrier ; remettez-les en vente depuis cette ligne à leur arrivée.",
  ["Cannot post this position"] = "Impossible de mettre cette position en vente",
  ["Cannot remove this entry"] = "Impossible de supprimer cette entrée",
  ["Cannot repost this lot"] = "Impossible de remettre ce lot en vente",
  ["Cap for %s"] = "Plafond pour %s",
  ["Cap: %d%%"] = "Plafond : %d%%",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limité par la vitesse réelle de vente, pas par ta bourse.",
  ["Change the cap…"] = "Changer le plafond…",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Il reste des enchères moins chères, mais au rythme de cet objet elles partent en quelques heures.",
  ["Check"] = "Vérifier",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower (or refuse) if the market has moved since your last import."] =
    "Check recalcule à partir du carnet d'ordres en direct avant que l'or ne bouge, et peut donner moins (ou refuser) si le marché a bougé depuis votre dernier import.",
  ["Checked against the live order book a moment ago."] =
    "Vérifié à l'instant sur le carnet d'ordres en direct.",
  ["Checked: %d of the top %d on screen"] = "Vérifiées : %d sur les %d premières à l'écran",
  ["Checking prices…"] = "Vérification des prix…",
  ["Checking prices: waiting for the Auction House…"] = "Vérification des prix : en attente de l'hôtel des ventes…",
  ["Checking this item's price…"] = "Vérification du prix de cet objet…",
  ["Checking..."] = "Vérification...",
  ["Clear to buy"] = "Feu vert pour acheter",
  ["Click Confirm to post"] = "Clique sur Confirmer pour mettre en vente",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Un nouveau clic annule l'enchère en cours. Elle n'est pas remise en vente : la caution est perdue et les objets reviennent par courrier plutôt que directement dans vos sacs.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Un nouveau clic supprime définitivement ce coût saisi à la main.",
  ["Close"] = "Fermer",
  ["Companion keeps prices fresh: /goldcap companion"] =
    "Companion garde les prix à jour : /goldcap companion",
  ["Companion sync rejected:"] = "Synchronisation Companion refusée :",
  ["Confirm"] = "Confirmer",
  ["Confirm the cancel"] = "Confirmer l'annulation",
  ["Confirm the removal"] = "Confirmer la suppression",
  ["Copy vendor list"] = "Copier la liste du marchand",
  ["Cost per unit"] = "Coût par unité",
  ["Cost unknown for %d of %d"] = "Prix d'achat inconnu pour %d sur %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Coûte plus que ne l'autorise votre limite par achat.",
  ["Could not read that amount. Type it like 12g 50s."] = "Montant illisible. Écrivez-le comme 12g 50s.",
  ["Don't skip"] = "Ne plus ignorer",
  ["Everything here is bought"] = "Tout est acheté ici",
  ["From goldcap.gg: manage it there"] = "De goldcap.gg : gère-la là-bas",
  ["From your scan %s ago. Counts only %s. Change with /gc weights."] =
    "D'après votre scan d'il y a %s. Compte seulement %s. À modifier avec /gc weights.",
  ["Gear upgrades on the auction house"] = "Améliorations d'équipement à l'hôtel des ventes",
  ["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."] =
    "GoldCap compte désormais ce que lâchent les créatures que vous dépouillez, sans aucun nom, pour les taux de butin sur goldcap.gg. Le Companion le partagera dès que cette partie sortira. Tapez /gc loot off pour arrêter.",
  ["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."] =
    "Objets de vos sacs qui valent plus à l'hôtel des ventes que chez un marchand : %d (%s de plus).",
  ["Items still loading: %d. Open this again in a moment."] =
    "Objets encore en chargement : %d. Rouvrez ceci dans un instant.",
  ["Loot counting is off. Type /gc loot clear to remove what was recorded."] =
    "Le comptage du butin est désactivé. Tapez /gc loot clear pour supprimer ce qui a été enregistré.",
  ["Loot counting is on."] = "Le comptage du butin est activé.",
  ["Loot record cleared."] = "Journal de butin supprimé.",
  ["Market"] = "Marché",
  ["Mount cost cleared."] = "Coût de la monture effacé.",
  ["Mount cost set to %s."] = "Coût de la monture fixé à %s.",
  ["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] =
    "Aucun scan contenant de l'équipement pour l'instant. Ouvrez l'hôtel des ventes et laissez GoldCap le scanner.",
  ["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] =
    "Pas encore de pondérations pour votre classe. Définissez-les ainsi : /gc weights STR 1 STA 0.5",
  ["Nothing on the auction house beats what you wear at your level."] =
    "Rien à l'hôtel des ventes ne dépasse ce que vous portez à votre niveau.",
  ["Nothing on this list matches."] = "Rien ne correspond dans cette liste.",
  ["Over cap"] = "Au-dessus du plafond",
  ["PRICE EACH"] = "PRIX À L'UNITÉ",
  ["Play a little longer for an estimate of your pace."] =
    "Jouez encore un peu pour une estimation de votre rythme.",
  ["RAISE CAP TO %s"] = "PLAFOND À %s",
  ["RISK CHECKS"] = "CONTRÔLE DES RISQUES",
  ["ROAD TO 40"] = "EN ROUTE VERS LE NIVEAU 40",
  ["Raise cap to %s"] = "Monter le plafond à %s",
  ["Restore %s"] = "Restaurer %s",
  ["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."] =
    "En route vers le niveau 40 avec GoldCap : %s sur %s pour ma monture (%d%%).",
  ["Road to 40: %s of %s (gold %s, bags %s)."] = "En route vers le niveau 40 : %s sur %s (or %s, sacs %s).",
  ["Road to 40: you have %s (gold %s, bags %s)."] = "En route vers le niveau 40 : vous avez %s (or %s, sacs %s).",
  ["Runs"] = "Listes",
  ["Set cap"] = "Fixer le plafond",
  ["Skip"] = "Ignorer",
  ["Skip for now"] = "Ignorer pour l'instant",
  ["Skipped"] = "Ignoré",
  ["Split into reagents (craft %d×)"] = "Diviser en composants (fabriquer %d×)",
  ["Stat weights: %s"] = "Pondérations : %s",
  ["The rest is skipped for now"] = "Le reste est ignoré pour l'instant",
  ["This client does not report item stats, so GoldCap cannot compare gear."] =
    "Ce client ne fournit pas les caractéristiques des objets, GoldCap ne peut donc pas comparer l'équipement.",
  ["This lot holds more units than your Max units per buy."] =
    "Ce lot contient plus d'unités que ton « Unités max. par achat ».",
  ["Could not find the queue's next lot to cancel. Try again"] =
    "Lot suivant de la file d'annulation introuvable. Réessaie",
  ["DEFAULTS"] = "PAR DÉFAUT",
  ["DISC"] = "REMISE",
  ["DISPLAY"] = "AFFICHAGE",
  ["DONE"] = "TERMINÉ",
  ["Default listing length for the Sell tab."] = "Durée d'annonce par défaut pour l'onglet Vente.",
  ["Default: %s"] = "Par défaut : %s",
  ["Deletes a hand-entered cost you typed into Set cost, never a purchase GoldCap itself captured or matched to your mail."] =
    "Supprime un coût saisi à la main dans Définir le coût, jamais un achat que GoldCap a lui-même capturé ou rattaché à votre courrier.",
  ["Discount"] = "Remise",
  ["Discount vs market value from your GoldCap import"] =
    "Remise par rapport à la valeur de marché de votre import GoldCap",
  ["Dump-trend cap %"] = "Plafond de tendance baissière %",
  ["Duration"] = "Durée",
  ["Enlarge the window to see details"] = "Agrandissez la fenêtre pour voir les détails",
  ["Enter a whole quantity"] = "Saisis une quantité entière",
  ["Enter an exact positive cost"] = "Saisis un prix d'achat exact et positif",
  ["Entry price (avg fill)"] = "Prix d'entrée (exécution moy.)",
  ["Entry total"] = "Total à l'entrée",
  ["Everything else checks out. With more gold on this character, this is a buy."] = "Tout le reste est bon. Avec plus d'or sur ce personnage, ce serait un achat.",
  ["FIFO allocations"] = "Affectations FIFO",
  ["Fetching a fresh price for this item. Press Post again in a moment"] =
    "Récupération d'un prix frais pour cet objet. Réappuie sur Post dans un instant",
  ["Fetching a fresh price for this lot. Press Repost again in a moment"] =
    "Récupération d'un prix frais pour ce lot. Réappuie sur Repost dans un instant",
  ["Finish the pending post first"] = "Termine d'abord la mise en vente en cours",
  ["Finish the pending post or repost first"] =
    "Termine d'abord la mise en vente ou la remise en vente en cours",
  ["Font scale"] = "Taille de police",
  ["Full pass over them: %.1fs"] = "Passage complet : %.1fs",
  ["Full pass over them: measuring..."] = "Passage complet : mesure en cours...",
  ["Gold tied up"] = "Or immobilisé",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap ne peut pas déterminer de quelle pile de sac il s'agit",
  ["GoldCap data age"] = "Ancienneté des données GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap revérifie les %d lignes contre l'hôtel des ventes en direct, environ toutes les %d s. Les lignes refusées sont masquées. L'achat reste toujours un clic que vous faites.",
  ["GoldCap value"] = "Valeur GoldCap",
  ["GoldCap: Import realm prices"] = "GoldCap : Importer les prix du royaume",
  ["GoldCap's"] = "de GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "La suggestion de GoldCap pour cet objet, et le prix qu'il utiliserait.",
  ["GoldCap: %s. %s"] = "GoldCap : %s. %s",
  ["GoldCap: checked live. A deal, but you need %s on this character"] = "GoldCap : vérifié en direct. Une affaire, mais il vous faut %s sur ce personnage",
  ["GoldCap: checked live, safe to buy"] = "GoldCap : vérifié en direct, achat sûr",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap : pas encore vérifié auprès de l'hôtel des ventes en direct",
  ["Gone"] = "Parti",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Grisé signifie que la cotation a vieilli ; Post et Repost la rafraîchissent avant d'agir.",
  ["HIDDEN 0"] = "MASQUÉES 0",
  ["HOLDING %d"] = "À GARDER %d",
  ["Held back from cancelling"] = "Retenu de l'annulation",
  ["Held back from the queue"] = "Retenu de la file",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Combien d'heures de ventes normales un mur sous votre prix de sortie peut tenir avant que l'affaire ne soit refusée.",
  ["ITEM"] = "OBJET",
  ["If it clears"] = "Si ça s'écoule",
  ["Import"] = "Importer",
  ["Import failed:"] = "Échec de l'import :",
  ["Import from goldcap.gg to arm the sniper"] = "Importez depuis goldcap.gg pour armer le sniper",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Installez le GoldCap Companion gratuit pour garder les prix à jour automatiquement (/goldcap companion),",
  ["It is what you must beat to sell quickly, not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "C'est le prix à battre pour vendre vite, pas la valeur de l'objet. Un vendeur pressé peut descendre bien en dessous de la valeur, et GoldCap refusera de le suivre : voyez WHAT TO DO pour le prix auquel il mettrait réellement en vente.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Il n'inventera pas un coût à partir du prix du marché : le profit reste inconnu tant que vous n'en saisissez pas un.",
  ["Item"] = "Objet",
  ["Item %d"] = "Objet %d",
  ["Item level %d, below the %d your price is for"] =
    "Niveau d'objet %d, sous le %d visé par ton prix",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE. The buy is your call, and GoldCap only checks them while this board is open."] =
    "Items : équipement, mascottes et recettes évalués par rapport à la référence régionale de ton import. La vitesse de vente n'est jamais mesurée, donc ils ne passent jamais SÛR. L'achat, c'est à toi de décider, et GoldCap ne les vérifie que tant que ce tableau est ouvert.",
  ["LISTED"] = "EN VENTE",
  ["Language"] = "Langue",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Langue changée. Tapez /reload pour l'appliquer partout.",
  ["Last post may still go up. Wait a minute"] = "Le dépôt peut aboutir. Attends une minute",
  ["Level 40 reached: %s to go."] = "Niveau 40 atteint : il vous manque encore %s.",
  ["Last result: %ds ago"] = "Dernier résultat : il y a %ds",
  ["Last result: none yet this visit"] = "Dernier résultat : aucun pour cette visite",
  ["Listed"] = "En vente",
  ["Listed at %s, far below market. Repost."] =
    "En vente à %s, bien sous le marché. Remets en vente.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Mis en vente à ton prix fixé sur goldcap.gg ou en dessous. Sa revente, c'est à toi d'en juger.",
  ["Listings"] = "Ventes",
  ["Lists this item at the price on its row: the whole bag for a commodity, one stack for a regular item, or the number under HOW MANY."] =
    "Met cet objet en vente au prix de sa ligne : tout le sac pour une marchandise, une pile pour un objet normal, ou le nombre sous QUANTITÉ.",
  ["Live ask"] = "Prix en direct",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lot annulé ; attends qu'il revienne dans les sacs",
  ["MARKET"] = "MARCHÉ",
  ["MARKET / UNIT"] = "MARCHÉ / UNITÉ",
  ["MATCH"] = "ÉGALER",
  ["Market per unit"] = "Marché à l'unité",
  ["Market reference"] = "Référence de marché",
  ["Max units per buy"] = "Unités max. par achat",
  ["Max wallet per buy %"] = "Part max. de votre or par achat %",
  ["Min profit per buy (gold)"] = "Profit min. par achat (or)",
  ["Min profit per buy (copper)"] = "Profit min. par achat (cuivre)",
  ["To buy"] = "À acheter",
  ["To craft"] = "À fabriquer",
  ["Total: %s"] = "Total : %s",
  ["Unknown stat %s. Use one of: %s"] = "Caractéristique inconnue %s. Utilisez l'une de : %s",
  ["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."] =
    "Améliorations pour votre équipement à l'hôtel des ventes : %d. Tapez /gc upgrades pour les voir.",
  ["Use the default cap"] = "Plafond par défaut",
  ["While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead."] = "Tant que ceci reste à 5 % par défaut, une piste au prix du marchand peut utiliser jusqu'à la moitié de ta bourse.",
  ["Min return per buy %"] = "Rendement min. par achat %",
  ["Missing cost"] = "Coût manquant",
  ["NO LIVE PRICE YET"] = "PAS ENCORE DE PRIX EN DIRECT",
  ["YOUR LISTS"] = "TES LISTES",
  ["NOT ON HAND %d"] = "PAS SOUS LA MAIN %d",
  ["NOTHING TO CANCEL"] = "RIEN À ANNULER",
  ["Needs a live price check before it can be bought."] =
    "Nécessite une vérification du prix en direct avant tout achat.",
  ["Needs gold"] = "Il faut de l'or",
  ["Never spend more than this share of your gold on one purchase."] =
    "Ne jamais dépenser plus que cette part de votre or pour un seul achat.",
  ["No answer yet, listening for a minute"] = "Pas de réponse, on écoute encore une minute",
  ["No deals passed the safety checks right now."] =
    "Aucune affaire ne passe les vérifications de sécurité pour l'instant.",
  ["No deals to show, and no realm prices yet."] =
    "Aucune affaire à afficher, et pas encore de prix du royaume.",
  ["No deals yet."] = "Pas encore d'affaires.",
  ["No exact auction key"] = "Pas de clé d'enchère exacte",
  ["No exact bag stack"] = "Pas de pile de sac exacte",
  ["No exact bag variant"] = "Pas de variante de sac exacte",
  ["No live listings came back for this item."] =
    "Aucune enchère active n'est revenue pour cet objet.",
  ["No region reference for this item yet. Import again once goldcap.gg publishes one."] =
    "Pas encore de prix de référence régional pour cet objet. Réimporte dès que goldcap.gg en publie un.",
  ["No safe resale price could be worked out."] = "Impossible d'établir un prix de revente sûr.",
  ["No sales data for this item."] = "Aucune donnée de vente pour cet objet.",
  ["Not enough gold on this character to buy what GoldCap finds"] = "Pas assez d'or sur ce personnage pour acheter ces affaires",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Pas assez d'unités à l'hôtel des ventes pour cette quantité.",
  ["Not in your bags or listed. Mail or bank?"] =
    "Ni dans tes sacs ni en vente. Courrier ou banque ?",
  ["Not on hand: the stock is in the mail, the bank, or on another character"] =
    "Pas sous la main : le stock est dans le courrier, à la banque ou sur un autre personnage",
  ["Not worth the deposit on the AH"] = "Ne vaut pas la caution à l'HV",
  ["Nothing is being held back."] = "Rien n'est retenu.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Après cet achat il ne reste rien contre quoi vendre : il n'y a donc pas de prix de sortie.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Aucune vente n'atteint le niveau d'objet sur lequel le prix de référence a été mesuré.",
  ["Nothing listed on the AH right now"] = "Rien en vente à l'hôtel des ventes pour l'instant",
  ["Nothing to sell"] = "Rien à vendre",
  ["Nothing in your bags to list. Buy on the Deals tab or pick up your mail: anything you can sell shows up here with a price ready."] =
    "Rien à mettre en vente dans tes sacs. Achète dans l'onglet Deals ou récupère ton courrier : tout ce que tu peux vendre apparaît ici avec un prix prêt.",
  ["No auctions up"] = "Aucune enchère en cours",
  ["No live auctions on this character. What you post shows up here, with what to cancel and what to leave."] =
    "Aucune enchère active sur ce personnage. Ce que tu mets en vente apparaît ici, avec ce qu'il faut annuler et ce qu'il faut laisser.",
  ["No match"] = "Aucun résultat",
  ["Nothing on this deck matches that search. Clear the box to see everything."] =
    "Rien dans cet onglet ne correspond à cette recherche. Vide le champ pour tout voir.",
  ["Still pricing"] = "Prix en cours",
  ["The auction house is still answering. Items show up here as their prices arrive."] =
    "L'hôtel des ventes répond encore. Les objets apparaissent ici à mesure que leurs prix arrivent.",
  ["Every cost is known"] = "Tous les coûts sont connus",
  ["Every item in your bags already has what you paid on record. Turn off NO COST to see them all."] =
    "Pour tout ce qui est dans tes sacs, ce que tu as payé est déjà enregistré. Désactive NO COST pour tout voir.",
  ["Nothing queued to cancel"] = "Rien à annuler dans la file",
  ["Nothing queued to post"] = "Rien à mettre en vente dans la file",
  ["Nothing to remove"] = "Rien à supprimer",
  ["ON THE AUCTION HOUSE"] = "À L'HÔTEL DES VENTES",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown: rescan anytime."] =
    "Un scan unique de tout l'hôtel des ventes via des requêtes paginées. Prend environ 15 à 60 secondes sur les royaumes chargés. Aucun délai : relancez quand vous voulez.",
  ["Open the Auction House first."] = "Ouvrez d'abord l'hôtel des ventes.",
  ["Open the Auction House to begin scanning."] =
    "Ouvrez l'hôtel des ventes pour lancer le scan.",
  ["Open the deals board. /gc for commands."] = "Ouvre le tableau des affaires. /gc pour les commandes.",
  ["POSTING"] = "MISE EN VENTE",
  ["POSTING…"] = "MISE EN VENTE…",
  ["PRICE"] = "PRIX",
  ["PRICE ROSE %.1fx"] = "LE PRIX A MONTÉ DE %.1fx",
  ["PRICED TOO LOW %d"] = "TROP BAS %d",
  ["PRICING %d/%d"] = "PRIX %d/%d",
  ["PRICING…"] = "PRIX…",
  ["PROFIT"] = "PROFIT",
  ["PROFIT / UNIT"] = "BÉNÉFICE / UNITÉ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Associez ou mettez à jour le GoldCap Companion pour voir les bénéfices de goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Collez la chaîne de votre royaume depuis goldcap.gg et appuyez sur Import.",
  ["Per-unit price of this auction"] = "Prix unitaire de cette enchère",
  ["Play a sound when a checked deal turns SAFE."] = "Jouer un son quand une affaire vérifiée devient SAFE.",
  ["Position scope changed"] = "Périmètre de la position modifié",
  ["Post"] = "Vendre",
  ["Post above the cheapest"] = "Poster au-dessus du moins cher",
  ["Post confirmation expired"] = "Confirmation de mise en vente expirée",
  ["Post the next queued item"] = "Mettre en vente l'objet suivant de la file",
  ["Posted"] = "Mis en vente",
  ["Posting failed"] = "Échec de la mise en vente",
  ["Posting unavailable"] = "Mise en vente indisponible",
  ["Posting…"] = "Envoi…",
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
  ["Pricing paused while you use the Auction House"] = "Cotation en pause pendant que tu utilises l'hôtel des ventes",
  ["Pricing…"] = "Cotation…",
  ["Profit"] = "Profit",
  ["Profit per unit"] = "Profit par unité",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Le suivi des bénéfices est une fonction goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "Les achats sont désactivés dans cette version.",
  ["Press Buy again to buy this quantity"] = "Clique de nouveau sur Acheter pour acheter cette quantité",
  ["QTY"] = "QTÉ",
  ["Quantity exceeds missing units"] = "La quantité dépasse les unités manquantes",
  ["Quantity is capped by how fast this item actually sells."] =
    "La quantité est plafonnée par la vitesse réelle de vente de cet objet.",
  ["REFRESH"] = "ACTUALISER",
  ["RESET WINDOW"] = "RÉINITIALISER LA FENÊTRE",
  ["Reason"] = "Raison",
  ["Refresh"] = "Actualiser",
  ["Refresh waiting for prior result"] = "L'actualisation attend le résultat précédent",
  ["Refreshing listings…"] = "Actualisation des ventes…",
  ["Refuse a buy when the price fell more than this in the last 24 hours: it may keep falling."] =
    "Refuser un achat si le prix a baissé de plus de ce seuil au cours des dernières 24 heures : il pourrait continuer à baisser.",
  ["Refused so far: %d"] = "Refusées jusqu'ici : %d",
  ["Removal confirmation expired"] = "Confirmation de suppression expirée",
  ["Remove"] = "Supprimer",
  ["Remove this cost"] = "Supprimer ce coût",
  ["Remove?"] = "Supprimer ?",
  ["Removed"] = "Supprimé",
  ["Removed %d entries"] = "%d entrées supprimées",
  ["Removes every entered-by-hand purchase in this run. Click again to confirm"] =
    "Supprime tous les achats saisis à la main dans ce groupe. Clique à nouveau pour confirmer",
  ["Removes this entered-by-hand purchase. Click again to confirm"] =
    "Supprime cet achat saisi à la main. Clique à nouveau pour confirmer",
  ["Repost confirmation expired"] = "Confirmation de remise en vente expirée",
  ["Right-click to stop watching this item"] =
    "Clic droit pour arrêter de surveiller cet objet",
  ["Right-click to watch this item closely"] = "Clic droit pour surveiller cet objet de près",
  ["SAFE +%s"] = "SÛR +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "SÛR = la vérification en direct a validé cet achat, au profit affiché",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "ENREGISTRÉ AUSSITÔT · ÉCHAP OU DONE POUR FERMER",
  ["SCAN"] = "SCAN",
  ["SCANNING…"] = "SCAN…",
  ["SESSION %s%s · BUYS %d"] = "SESSION %s%s · ACHATS %d",
  ["Sales are costed from your oldest units first"] =
    "Les ventes sont imputées d'abord sur tes unités les plus anciennes",
  ["Search"] = "Rechercher",
  ["Sales evidence"] = "Ventes réelles",
  ["Sell it on the AH"] = "Vends-le à l'HV",
  ["Sell it on the AH (deposit not counted)"] = "Vends-le à l'HV (caution non comptée)",
  ["Sell it to a vendor"] = "Vends-le à un marchand",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "L'onglet Vente poste un palier au-dessus de l'offre la moins chère quand le carnet montre qu'elle se vend tout aussi vite.",
  ["Sell-through"] = "Taux d'écoulement",
  ["Sellers"] = "Vendeurs",
  ["Sells too rarely: you would be holding it for a long time."] =
    "Se vend trop rarement : vous le garderiez longtemps.",
  ["Set cost"] = "Coût payé",
  ["Settings"] = "Réglages",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Ignorer un achat s'il ne rapporte pas au moins ce montant après la commission de l'HV.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Ignorer un achat si le profit ne représente pas au moins cette part de ce que vous payez.",
  ["Snapshot value"] = "Valeur de l'instantané",
  ["Sold per day"] = "Ventes par jour",
  ["Sold/day"] = "Ventes/jour",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Triez dessus pour décider quoi vérifier en premier, pas quoi acheter.",
  ["Sound on SAFE deal"] = "Son sur une affaire SAFE",
  ["Source"] = "Source",
  ["Source age"] = "Ancienneté de la source",
  ["Spike-trend threshold %"] = "Seuil de flambée %",
  ["Start scanning as soon as the auction house opens."] =
    "Démarrer le scan dès l'ouverture de l'hôtel des ventes.",
  ["Status"] = "Statut",
  ["Stop and open the buy window on your price"] = "Arrêter et ouvrir la fenêtre d'achat à ton prix",
  ["Stress exit unit"] = "Prix de sortie sous stress",
  ["Stress profit"] = "Bénéfice sous stress",
  ["THE BOOK"] = "LE CARNET D'ORDRES",
  ["TREND"] = "TENDANCE",
  ["Tell GoldCap what you actually paid for these units."] =
    "Indiquez à GoldCap ce que vous avez réellement payé pour ces unités.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "L'hôtel des ventes n'a pas indiqué de caution : le coût est donc inconnu.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Le Companion synchronise, mais cet addon n'a pas pu lire ce qu'il a écrit :",
  ["The auction house did not answer. Try again"] =
    "L'hôtel des ventes n'a pas répondu. Réessaie",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "Le tableau l'a classé d'après l'instantané importé. Le carnet en direct ne le confirme pas.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Le bouton attend un instant avant d'être cliquable : un double-clic accidental ne suffit jamais.",
  ["The cancel did not go through: the lot is still listed"] = "L'annulation n'a pas abouti : le lot est toujours en vente",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "La vente la moins chère n'est plus assez en dessous du prix de référence.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Le prix le plus bas demandé actuellement par QUELQU'UN D'AUTRE, d'après une requête en direct à l'hôtel des ventes. Vos propres ventes sont exclues, donc le chiffre ne se poursuit jamais lui-même vers le bas.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Les données de cet objet sont malformées : GoldCap refuse de deviner.",
  ["The liquidity data is not reliable enough to act on."] =
    "Les données de liquidité ne sont pas assez fiables pour agir.",
  ["The market value is an estimate, not a measurement."] =
    "La valeur de marché est une estimation, pas une mesure.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Le maximum qu'un achat peut prendre. La vitesse à laquelle l'objet se vend peut encore le réduire.",
  ["The price data is over three hours old. Sync the Companion, then /reload. The addon only reads its data when the UI loads."] =
    "Les données de prix ont plus de trois heures. Synchronisez le Companion puis faites /reload. L'addon ne lit ses données qu'au chargement de l'interface.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "Le prix est vérifié. La vitesse de vente n'est mesurée nulle part : c'est à toi d'en juger.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Le prix baisse ; y entrer, c'est exactement comme on se retrouve coincé.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "Le prix est la dernière cotation, vieille de 45 secondes au plus. S'il change avant la confirmation, la mise en vente est abandonnée plutôt qu'envoyée à l'ancien prix.",
  ["The price moved: part of this quote may be above your price"] =
    "Le prix a bougé : une partie de cette offre peut dépasser ton prix",
  ["The price moved and the trade is no longer safe."] =
    "Le prix a bougé et l'opération n'est plus sûre.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Le profit n'atteint pas votre minimum une fois la commission de 5 % et la caution payées.",
  ["What this buy would make is under your minimum profit."] =
    "Ce que cet achat rapporterait est inférieur à votre profit minimum.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Aucune annulation possible. Le premier clic en demande un second pour confirmer.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "C'est un objet de royaume, et GoldCap ne vérifie que les prix des marchandises.",
  ["Too few sellers to read a real price."] = "Trop peu de vendeurs pour lire un vrai prix.",
  ["Too little of what is listed actually sells."] =
    "Trop peu de ce qui est mis en vente se vend réellement.",
  ["Too little price history to trust the value."] =
    "Trop peu d'historique de prix pour se fier à cette valeur.",
  ["Total cost to buy this auction"] = "Coût total pour acheter cette enchère",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Saisis un prix en or, ou vide le champ pour prendre celui de GoldCap",
  ["UNDERCUT"] = "SOUS-COTER",
  ["UNDERCUT %d"] = "SOUS-COTÉS %d",
  ["UNIT"] = "UNITÉ",
  ["Unit price"] = "Prix unitaire",
  ["Unknown"] = "Inconnu",
  ["Unknown item"] = "Objet inconnu",
  ["Unknown means the cost side is incomplete. Fill it in with Set cost."] =
    "Inconnu signifie que le coût est incomplet. Complétez-le avec Définir le coût.",
  ["VERDICT"] = "VERDICT",
  ["Verdict"] = "Verdict",
  ["WAITING FOR THE AUCTION HOUSE %d"] = "EN ATTENTE DE L'HÔTEL DES VENTES %d",
  ["WATCH"] = "SURVEILLER",
  ["WATCH (computed SAFE)"] = "WATCH (calculé SÛR)",
  ["WATCH = the live check refused it. Hover the row for the reason"] =
    "SURVEILLER = la vérification en direct l'a refusé. Survolez la ligne pour la raison",
  ["WHAT COUNTS AS A DEAL"] = "CE QUI COMPTE COMME AFFAIRE",
  ["WHAT TO DO"] = "QUE FAIRE",
  ["WHAT YOU PAID"] = "CE QUE TU AS PAYÉ",
  ["WHEN"] = "QUAND",
  ["Waiting for Auction House…"] = "En attente de l'hôtel des ventes…",
  ["Waiting for a live price"] = "En attente d'un prix en direct",
  ["Waiting for the Auction House…"] = "En attente de l'hôtel des ventes…",
  ["Waiting for the purchase to finish…"] = "En attente de la fin de l'achat…",
  ["Wall absorb window (hours)"] = "Fenêtre d'absorption du mur (heures)",
  ["Watching closely: %d item%s"] = "Surveillés de près : %d objet%s",
  ["Watching: pinned, but not a deal right now"] =
    "Surveillé : épinglé, mais pas une affaire pour l'instant",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Ce qu'une unité vous a réellement coûté, en moyenne sur les achats encore en stock.",
  ["What to do"] = "Que faire",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Ce qui vous reste sur une unité si elle se vend au prix du marché : prix de vente, moins les 5 % de commission, moins votre coût.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Quand une annonce atteint un prix que tu as défini sur le site, le scan s'arrête et sa fenêtre d'achat s'ouvre.",
  ["Window position & size"] = "Position et taille de la fenêtre",
  ["Won't buy"] = "N'achètera pas",
  ["Worst case back"] = "Retour au pire",
  ["YOUR LOTS"] = "VOS LOTS",
  ["YOUR PRICE"] = "TON PRIX",
  ["You can pay for it now."] = "Vous pouvez la payer dès maintenant.",
  ["You get"] = "Tu reçois",
  ["You paid"] = "Payé",
  ["You pay"] = "Tu paies",
  ["You would get"] = "Tu recevrais",
  ["You would pay"] = "Tu paierais",
  ["Your call"] = "À toi de voir",
  ["Your cap"] = "Ton plafond",
  ["Your gold has not grown lately, so there is no pace to estimate."] =
    "Votre or n'a pas augmenté récemment, donc aucun rythme à estimer.",
  ["Your minimum"] = "Ton minimum",
  ["Your price"] = "Ton prix",
  ["a purchase landed that GoldCap could not attribute"] = "un achat est arrivé que GoldCap n'a pas pu attribuer",
  ["a purchase landed that GoldCap could not price"] = "un achat est arrivé dont GoldCap ne connaît pas le prix",
  ["a unit, at or under your price of %s"] = "l'unité, à ton prix de %s ou en dessous",
  ["a vendor sells it"] = "un marchand le vend",
  ["a vendor sells it for %s each"] = "un marchand le vend %s l'unité",
  ["a vendor sells it for %s each · the auction house asks %s"] = "un marchand le vend %s l'unité · l'hôtel des ventes demande %s",
  ["alert group · %d hits"] = "groupe d'alertes · %d trouvailles",
  ["already in your bags and bank"] = "déjà dans tes sacs et ta banque",
  ["another purchase is in flight"] = "un autre achat est en cours",
  ["at a vendor"] = "chez un marchand",
  ["at a vendor · %s each"] = "chez un marchand · %s l'unité",
  ["at level %d"] = "au niveau %d",
  ["bought"] = "acheté",
  ["bought %d for %s"] = "%d achetés pour %s",
  ["buy %d of %d"] = "acheter %d sur %d",
  ["buy %d of %d, have %d in bags and bank"] = "acheter %d sur %d, tu en as %d dans tes sacs et ta banque",
  ["buying..."] = "achat...",
  ["cap: alert target"] = "plafond : cible de l'alerte",
  ["cheapest seen %s"] = "le moins cher vu : %s",
  ["confirming..."] = "confirmation...",
  ["craft"] = "fabriquer",
  ["craft it for %s each"] = "fabrique-le pour %s l'unité",
  ["craft it for %s each · %s here"] = "fabrique-le pour %s l'unité · %s ici",
  ["craft it yourself"] = "fabrique-le toi-même",
  ["craft it · %s each"] = "fabriquer · %s l'unité",
  ["craft it: %s = %s each"] = "fabriquer : %s = %s l'unité",
  ["deals %s · items %s · filtered %s"] = "affaires %s · objets %s · écartées %s",
  ["done"] = "fait",
  ["from %s"] = "de %s",
  ["in bags %d · in bank %d"] = "dans les sacs %d · en banque %d",
  ["in bags %d · in bank %d · in the mailbox %d"] = "dans les sacs %d · en banque %d · dans la boîte aux lettres %d",
  ["includes %d for crafting %s"] = "dont %d pour fabriquer %s",
  ["no answer. Check your mail"] = "pas de réponse. Regarde ton courrier",
  ["nothing at or under your cap of %s"] = "rien à ton plafond de %s ou moins",
  ["nothing on offer"] = "rien en vente",
  ["on %s"] = "sur %s",
  ["over your cap"] = "au-dessus du plafond",
  ["plan updated on goldcap.gg"] = "plan mis à jour sur goldcap.gg",
  ["price moved to %s"] = "le prix est passé à %s",
  ["purchase failed. Try again"] = "l'achat a échoué. Réessaie",
  ["right-click to skip or change the cap"] = "clic droit pour ignorer ou changer le plafond",
  ["seen %s ago"] = "vu il y a %s",
  ["skipped for now"] = "ignoré pour l'instant",
  ["skipped for this session, it stays on the list"] = "ignoré pour cette session, reste sur la liste",
  ["still on the list: %d at a vendor · %d to craft"] = "encore sur la liste : %d chez un marchand · %d à fabriquer",
  ["sure profit: a vendor pays %s each"] =
    "profit assuré : un marchand paie %s l'unité",
  ["resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown"] =
    "revente à la valeur HV du scan, %s l'unité, moins 5%% et caution ; vitesse inconnue",
  ["Checked against the live auction house a moment ago."] =
    "Vérifié à l'instant sur l'hôtel des ventes en direct.",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "au-dessus du moins cher, dans le quart bon marché · %s unités devant",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "au-dessus du moins cher, dans la portée du jour · %s unités devant",
  ["age %ss"] = "il y a %ss",
  ["another purchase took over: nothing was confirmed"] =
    "un autre achat a pris la main : rien n'a été confirmé",
  ["any figure here would be invented out of the very number being refused"] =
    "tout chiffre ici serait inventé à partir du nombre même qui est refusé",
  ["at or under your price. Click Buy to purchase"] =
    "à ton prix ou en dessous. Clique sur Buy pour acheter",
  ["auto off"] = "auto désactivé",
  ["auto-synced %dh ago"] = "synchronisé automatiquement il y a %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "données synchronisées pour %s chargées (%s d'ancienneté)",
  ["auto-synced data stale: /goldcap import"] =
    "données synchronisées périmées : /goldcap import",
  ["auto: paused"] = "auto : en pause",
  ["below the %s breakeven"] = "sous le seuil de rentabilité de %s",
  ["below the %s you paid"] = "sous les %s que tu as payés",
  ["big buy"] = "gros achat",
  ["bought %d"] = "acheté %d",
  ["bought %d x %s"] = "acheté %d x %s",
  ["bought %d after AH close"] = "acheté %d après la fermeture de l'hôtel des ventes",
  ["buying commodity..."] = "achat de la marchandise...",
  ["cheapest not yours %s"] = "le moins cher qui n'est pas à toi %s",
  ["checking live price..."] = "vérification du prix en direct...",
  ["checking live safety..."] = "vérification de la sécurité en direct...",
  ["clears in ~%dd"] = "écoulé en ~%d j",
  ["clears in ~%dh"] = "écoulé en ~%d h",
  ["commodity purchase failed"] = "échec de l'achat de la marchandise",
  ["confirmed commodity purchase failed after AH close"] =
    "achat de marchandise confirmé échoué après la fermeture de l'hôtel des ventes",
  ["confirming purchase..."] = "confirmation de l'achat...",
  ["cost basis incomplete. Set costs to get repost advice"] =
    "prix d'achat incomplet. Renseigne-le pour obtenir un conseil de remise en vente",
  ["crafted %s"] = "fabriqué %s",
  ["due, will be asked next pass"] = "à faire, sera demandé au prochain passage",
  ["fair"] = "probables",
  ["far below market"] = "bien sous le marché",
  ["finish the pending buy first"] = "terminez d'abord l'achat en cours",
  ["first in line"] = "premier de la file",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "Coûte %s. Avec votre limite par achat de %d %%, il vous faut %s sur ce personnage.",
  ["fresh"] = "à jour",
  ["full scan already in progress"] = "scan complet déjà en cours",
  ["full scan interrupted. Confirm your purchase"] =
    "scan complet interrompu. Confirmez votre achat",
  ["full scan stalled. Press Full Scan to retry"] =
    "scan complet bloqué. Appuyez sur Full Scan pour réessayer",
  ["full scan stalled, retrying shortly"] = "scan complet bloqué, nouvelle tentative bientôt",
  ["full scan stopped. Press %s to run it again"] =
    "scan complet arrêté. Appuyez sur %s pour le relancer",
  ["gone / price changed"] = "disparu / prix modifié",
  ["goldcap.gg prices for WoW: Forever are not out yet."] =
    "Les prix goldcap.gg pour WoW: Forever ne sont pas encore disponibles.",
  ["strong"] = "certaines",
  ["hold"] = "garder",
  ["identity unresolved (variant item, not priced by design)"] =
    "identité non résolue (objet à variantes, volontairement sans prix)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "si tu achètes les %d et les revends au prix affiché en ce moment",
  ["ilvl %d"] = "niv. %d",
  ["import %dh old"] = "import vieux de %dh",
  ["import stale: /goldcap import or /goldcap companion"] =
    "import périmé : /goldcap import ou /goldcap companion",
  ["imported %d items for %s (%s). Prices are live now."] =
    "%d objets importés pour %s (%s). Les prix sont actifs.",
  ["in the mail"] = "dans le courrier",
  ["in the mail, the bank or on another character"] =
    "dans le courrier, à la banque ou sur un autre personnage",
  ["is what this market absorbs. Past that you are buying stock you will sit on"] =
    "c'est ce que ce marché absorbe. Au-delà, tu achètes du stock qui te restera sur les bras",
  ["item %d"] = "objet %d",
  ["%s: %s"] = "%s : %s",
  ["item level %d+"] = "niveau d'objet %d+",
  ["item variant unresolved"] = "variante de l'objet non résolue",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h: %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "dernières 24 h : %d ventes, %s brut, %s de commission, %d achats, %s dépensés",
  ["last live price %s ago"] = "dernier prix en direct, il y a %s",
  ["leave these alone"] = "à laisser tels quels",
  ["level %d"] = "niveau %d",
  ["listing gone: already bought out or price changed"] =
    "vente disparue : déjà rachetée ou prix modifié",
  ["listing gone: bought out or repriced"] = "l'enchère a disparu : achetée ou repositionnée",
  ["live safety confirmed. Click Buy to purchase"] =
    "sécurité confirmée en direct. Cliquez sur Buy pour acheter",
  ["live verification required"] = "vérification en direct requise",
  ["the cheapest is %s, your cap is %s"] = "le moins cher : %s, ton plafond : %s",
  ["the run changed. Start again"] = "la liste a changé. Recommence",
  ["took too long. Try again"] = "trop long. Réessaie",
  ["usually cheapest around %s · %d%%"] = "souvent le moins cher vers %s · %d%%",
  ["vendor"] = "marchand",
  ["vs %s at the auction house · right-click to buy it whole"] = "contre %s à l'hôtel des ventes · clic droit pour l'acheter entier",
  ["vs %s at the auction house · right-click to split"] = "contre %s à l'hôtel des ventes · clic droit pour diviser",
  ["weak"] = "douteuses",
  ["manual import. Companion keeps this fresh: /goldcap companion"] =
    "import manuel. Companion garde ça à jour : /goldcap companion",
  ["market %s"] = "marché %s",
  ["needs %s"] = "exige %s",
  ["needs a fresh price. Press Refresh"] = "besoin d'un prix frais. Appuie sur Refresh",
  ["no confirmation from the server. The buy may still have gone through, check your mail. Closing this will not undo it."] =
    "pas de confirmation du serveur : l'achat a pu aboutir quand même, vérifiez votre courrier. Fermer cette fenêtre ne l'annulera pas.",
  ["no cost"] = "pas de coût",
  ["no cost for %d"] = "pas de coût pour %d",
  ["no live price yet"] = "pas encore de prix en direct",
  ["no live price"] = "pas de prix en direct",
  ["no live quote yet, pricing…"] = "pas encore de cotation en direct, estimation du prix…",
  ["no market figure for caged pets"] = "pas de chiffre de marché pour les mascottes en cage",
  ["no market figure for this item level"] = "pas de chiffre de marché pour ce niveau d'objet",
  ["Makes %s"] = "Fabrique %s",
  ["no prices yet: /goldcap companion or /goldcap import"] =
    "pas encore de prix : /goldcap companion ou /goldcap import",
  ["no purchase confirmation received. Cancel and retry"] =
    "aucune confirmation d'achat reçue. Cancel puis réessayez",
  ["no sales recorded yet. Open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "aucune vente enregistrée. Ouvrez votre boîte aux lettres avec GoldCap chargé et elles seront lues sur les factures",
  ["no stock in bags or listed, nothing to price for"] =
    "aucun stock en sacs ni en vente, rien à coter",
  ["none"] = "aucun",
  ["not enough gold: total %s, you have %s"] = "pas assez d'or : total %s, vous avez %s",
  ["not enough gold for this quote. Cancel"] = "pas assez d'or pour cette cotation. Cancel",
  ["not enough gold on this character: you need %s"] = "pas assez d'or sur ce personnage : il vous faut %s",
  ["not enough units left for that quantity, re-checking what remains..."] =
    "pas assez d'unités restantes pour cette quantité, nouvelle vérification de ce qui reste...",
  ["not priced: nothing on hand to sell"] = "pas de prix : rien à vendre sous la main",
  ["not ready to cancel"] = "pas prêt à annuler",
  ["not ready to post"] = "pas prêt à mettre en vente",
  ["nothing listed"] = "rien en vente",
  ["of %d"] = "sur %d",
  ["off"] = "désactivé",
  ["oldest units sell first"] = "les unités les plus anciennes se vendent d'abord",
  ["on"] = "activé",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "ouvre l'hôtel des ventes une fois pour que GoldCap sache comment ils se vendent",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "ou collez une chaîne depuis goldcap.gg avec /goldcap import.",
  ["paid sale unresolved"] = "vente encaissée non résolue",
  ["placing bid..."] = "dépôt de l'enchère...",
  ["previous commodity purchase settled. %s to re-check the price"] =
    "achat de marchandise précédent réglé. %s pour revérifier le prix",
  ["price changed after you closed the buy window: nothing was bought"] =
    "le prix a changé après la fermeture de la fenêtre d'achat : rien n'a été acheté",
  ["price confirmed. Click Buy to purchase"] = "prix confirmé. Cliquez sur Buy pour acheter",
  ["price rose %.1fx, still safe. Confirm"] = "le prix a monté de %.1fx, toujours sûr. Confirmez",
  ["price stands %d of %d"] = "ton prix : %d sur %d",
  ["prices loaded are %s (%s) but you are playing in %s, so every discount and profit figure is measured against another market"] =
    "les prix chargés viennent de %s (%s) mais vous jouez en %s : chaque remise et chaque profit est mesuré sur un autre marché",
  ["purchase canceled"] = "achat annulé",
  ["purchase complete"] = "achat terminé",
  ["purchase identity unresolved"] = "identité de l'achat non résolue",
  ["purchase pending exact cost"] = "achat en attente du coût exact",
  ["purchase total unavailable. Check your mail"] =
    "total de l'achat indisponible. Regardez votre boîte aux lettres",
  ["quote %s. Click Confirm to buy"] = "cotation %s. Cliquez sur Confirm pour acheter",
  ["quote %ss ago"] = "cotation il y a %ss",
  ["quote expired. Refresh to re-check the price"] =
    "cotation expirée. Refresh pour revérifier le prix",
  ["quote expires in %d s. Click Confirm to buy"] =
    "la cotation expire dans %d s. Cliquez sur Confirm pour acheter",
  ["re-checking what remains at a safe price..."] =
    "nouvelle vérification de ce qui reste à un prix sûr...",
  ["recent sales (newest first):"] = "ventes récentes (les plus récentes d'abord) :",
  ["region %s · bundled: %d items (%s), imported: %s"] =
    "région %s · inclus : %d objets (%s), importés : %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "région corrigée sur %d lignes du journal ; %d ventes rattachées à leur stock",
  ["relisting now would lock in a loss or a stall. Hold"] =
    "remettre en vente maintenant figerait une perte ou un blocage. Garde-le",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "%d enregistrements d'achat en double supprimés, laissés par un bug d'analyse du courrier",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "%d enregistrements de vente en double supprimés, laissés par un bug d'analyse du courrier",
  ["sale name ambiguous"] = "nom de la vente ambigu",
  ["sale proceeds pending"] = "recettes de vente en attente",
  ["scanned %d listings over %d passes"] = "%d ventes scannées en %d passages",
  ["scanning auction house..."] = "scan de l'hôtel des ventes...",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "se vend %s/jour",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "session : %d prises, %s dépensés, ~%s de bénéfice est.",
  ["sniped (listing changed on rescan)"] = "raflé (la vente a changé au rescan)",
  ["sniped for "] = "sniper pour ",
  ["stack not identified"] = "pile non identifiée",
  ["starting full scan..."] = "démarrage du scan complet...",
  ["stopped watching %s"] = "surveillance de %s arrêtée",
  ["the Companion wrote prices this addon could not read:"] =
    "le Companion a écrit des prix que cet addon n'a pas pu lire :",
  ["the auction house has not sent details for these yet"] =
    "l'hôtel des ventes n'a pas encore envoyé leurs détails",
  ["the import failed (%s)"] = "l'import a échoué (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "pour écouler %d unités à %s ventes par jour, avec %s immobilisé pendant tout ce temps",
  ["unavailable"] = "indisponible",
  ["under GoldCap's own floor of %s"] = "sous le plancher de GoldCap, %s",
  ["unknown evidence"] = "preuve inconnue",
  ["waiting for previous commodity purchase to settle"] =
    "en attente du règlement de l'achat de marchandise précédent",
  ["waiting for previous search result to settle"] =
    "en attente du résultat de recherche précédent",
  ["waiting..."] = "en attente…",
  ["wall"] = "mur",
  ["wall %s at %s: price under it to sell first"] =
    "mur de %s à %s: passe en dessous pour vendre d'abord",
  ["wall %s at %s above you"] = "mur de %s à %s au-dessus de toi",
  ["watching %s closely, re-checked every few seconds"] =
    "%s surveillé de près, revérifié toutes les quelques secondes",
  ["worst case, selling all %d back into the price standing there now"] =
    "au pire, en revendant les %d au prix affiché en ce moment",
  ["worth cancelling"] = "à annuler",
  ["would sell at a loss"] = "se vendrait à perte",
  ["you have enough gold for this now. Check again"] = "vous avez maintenant assez d'or. Cliquez sur Check pour revérifier",
  ["you haven't imported realm prices yet. Install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "vous n'avez pas encore importé les prix du royaume. Installez GoldCap Companion (/goldcap companion) ou collez une chaîne depuis goldcap.gg (/goldcap import).",
  ["you take %d"] = "tu en prends %d",
  ["your game client has no font for this language, so the text will show as empty boxes"] =
    "votre client de jeu n'a pas de police pour cette langue, le texte s'affichera en carrés vides",
  ["your import is %d hours old and prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "votre import date de %d heures, les prix peuvent être faux. Collez une chaîne fraîche depuis goldcap.gg (/goldcap import).",
  ["your price is above every level shown"] = "ton prix dépasse tous les niveaux",
  ["your scan, %s ago"] = "ton scan, il y a %s",
  ["yours"] = "le tien",
  ["yours ×%s"] = "à toi ×%s",
  ["~%dd to reach you"] = "~%d j avant ton tour",
  ["~%dh to reach you"] = "~%d h avant ton tour",
  ["×%d in bags"] = "×%d en sacs",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d dans tes sacs · Post en met %d en vente, la plus grande pile",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d dans tes sacs · aucune pile que GoldCap puisse identifier exactement",
  ["×%d in your bags, ready to list"] = "×%d dans tes sacs, prêts à être vendus",
  ["×%d listed"] = "×%d en vente",
  ["×%d listed at %s each"] = "×%d en vente à %s pièce",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · acheté %s · %s · %s",
  ["×%d%s · made %s · %s"] = "×%d%s · fabriqué %s · %s",
  ["- = nothing is checking this row right now"] =
    "- = rien ne vérifie cette ligne pour le moment",
  ["… = a live check is queued for this row"] =
    "… = une vérification en direct est en file pour cette ligne",
  ["no answer %ds ago, resting"] = "aucune réponse il y a %ds, en pause",
  ["the last attempt is still settling, checking the price again..."] =
    "la dernière tentative n'est pas encore réglée, nouvelle vérification du prix...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "Mis en vente à ton prix fixé sur goldcap.gg ou en dessous (groupe : %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "AUTO · EN PAUSE : FENÊTRE D'ACHAT",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "En pause tant qu'une fenêtre d'achat est ouverte. Achète ou ferme-la et Auto reprend.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "AUTO · EN PAUSE : TA RECHERCHE",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "En pause pendant que tu tapes dans la recherche de l'hôtel des ventes. Reprend quelques secondes après que tu l'as quittée.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "AUTO · EN PAUSE : COURRIER OUVERT",
  ["AUTO · PAUSED: OTHER TAB"] = "AUTO · EN PAUSE : AUTRE ONGLET",
  ["Paused while another auction house tab is open: Sell, Auctions, or another addon's, such as Auctionator's Selling. A scan would replace what that tab shows. Click Buy or the GoldCap tab at the bottom of the auction house and Auto carries on."] =
    "En pause tant qu'un autre onglet de l'hôtel des ventes est ouvert : Vendre, Enchères ou celui d'un autre addon, comme Selling d'Auctionator. Un scan remplacerait ce que cet onglet affiche. Clique sur Acheter ou sur l'onglet GoldCap en bas de l'hôtel des ventes et Auto reprend.",
  ["Scan starts when you leave that tab: click Buy or GoldCap"] =
    "Le scan démarre quand tu quittes cet onglet : Acheter ou GoldCap",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "En pause tant que la boîte aux lettres est ouverte. Ferme-la et Auto reprend.",
  ["AUTO · PAUSED: SELL TAB"] = "AUTO · EN PAUSE : ONGLET VENTE",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "En pause tant que l'onglet Vente est ouvert : il estime tes sacs par la même recherche. Reviens aux affaires et Auto reprend.",
  ["AUTO · PAUSED: BUY TAB"] = "AUTO · EN PAUSE : ONGLET BUY",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "En pause tant que l'onglet BUY est ouvert : il cherche les prix par la même recherche. Reviens aux affaires et Auto reprend.",
  ["AUTO · WAITING FOR YOU"] = "AUTO · T'ATTEND",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "Attend pendant que tu mets en vente, achètes ou parcours les panneaux de l'hôtel des ventes. Démarre dès que tu t'arrêtes.",
  ["AUTO · WAITING: YOUR AH SEARCH"] = "AUTO · ATTEND : TA RECHERCHE À L'HV",
  ["Waiting so that a scan does not replace the results of your own search on the auction house's Buy list. Click AUTO or SCAN and it carries on."] =
    "Attend pour qu'un scan ne remplace pas les résultats de ta propre recherche dans la liste d'achat de l'hôtel des ventes. Clique sur AUTO ou SCAN et il reprend.",
  ["Market %s · unverified until a live Check"] =
    "Marché %s · non vérifié avant une vérification en direct",
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "données du marché entier : %d marchandises, %d avec données de vente, %d objets de royaume (âge %s, %d Ko)",
  ["whole-market data not in use: %s"] = "données du marché entier non utilisées : %s",
  ["it is %s old, and the prices you imported are newer"] =
    "elles ont %s et les prix que vous avez importés sont plus récents",
  ["it is for another region than the prices loaded"] = "elles concernent une autre région que les prix chargés",
  ["its date cannot be right. Check this computer's clock"] =
    "leur date ne peut pas être juste. Vérifiez l'horloge de cet ordinateur",
  ["it was set aside when other prices were loaded this session. /reload to use it again"] =
    "elles ont été mises de côté quand d'autres prix ont été chargés pendant cette session. /reload pour les réutiliser",
  ["On the AH now"] = "À l'HV maintenant",
  ["%s listed · %d min ago"] = "%s en vente · il y a %d min",
  ["%s listed · just now"] = "%s en vente · à l'instant",
  ["it could not be read (%s)"] = "elles n'ont pas pu être lues (%s)",
  ["it is for a region this build of GoldCap does not know. Update the addon"] =
    "elles concernent une région que cette version de GoldCap ne connaît pas. Mettez à jour l'addon",
  ["it is in a format this build of GoldCap cannot read. Update the addon"] =
    "elles sont dans un format que cette version de GoldCap ne sait pas lire. Mettez à jour l'addon",
  ["it is larger than this build of GoldCap can read. Update the addon"] =
    "elles sont trop volumineuses pour cette version de GoldCap. Mettez à jour l'addon",
  ["the Companion wrote an empty copy. Let it sync, then /reload"] =
    "le Companion les a enregistrées vides. Laissez-le se synchroniser puis faites /reload",
  ["the Companion wrote it with no prices. Let it sync, then /reload"] =
    "le Companion les a enregistrées sans aucun prix. Laissez-le se synchroniser puis faites /reload",
  ["Scanning the auction house…"] = "Scan de l'hôtel des ventes…",
  ["%s lots scanned and saved"] = "%s lots scannés et enregistrés",
  ["%s items scanned and saved"] = "%s objets scannés et enregistrés",
  ["The full scan is cooling down (%d min left). Scanning by browsing instead"] =
    "Le scan complet est en recharge (%d min restantes). Scan par parcours en attendant",
  ["The auction house did not answer the full scan. Scanning by browsing instead"] =
    "L'hôtel des ventes n'a pas répondu au scan complet. Scan par parcours à la place",
  ["reading the auction house: %s of %s lots"] = "lecture de l'hôtel des ventes : %s sur %s lots",
  ["The scan found nothing to save"] = "Le scan n'a rien trouvé à enregistrer",
  ["Scans the whole auction house for prices: a full list at most once every 15 minutes, browsing in between. GoldCap also scans when you open the auction house."] =
    "Scanne tout l'hôtel des ventes pour les prix : une liste complète au plus une fois toutes les 15 minutes, avec un scan par parcours entre-temps. GoldCap scanne aussi à l'ouverture de l'hôtel des ventes.",
  -- Core/ForeverValue.lua's PrintBags/BagTotals and Core/PostQueue.lua's below_vendor: the
  -- POST queue holding back what a vendor pays at least as much for.
  ["Your bags: %s at a vendor, %s on the AH after its cut"] =
    "Vos sacs : %s chez un marchand, %s à l'HV après commission",
  ["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."] =
    "Le bouton VENDRE de l'onglet Vente liste tout ce qui vaut plus qu'un marchand ne paie, un clic à la fois.",
  ["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."] =
    "Vos sacs : %s chez un marchand. Scannez l'hôtel des ventes pour voir ce qu'ils rapporteraient là-bas.",
  ["a vendor pays more: sell it there"] =
    "un marchand paie plus : vends-le là-bas",
  ["vendor pays more"] =
    "le marchand paie plus",
  ["Below vendor"] =
    "Sous PNJ",
  ["Under market"] =
    "Sous marché",
  [" · buy at %s or less, vendor pays %s"] =
    " · achetez à %s ou moins, le marchand paie %s",
  [" · buy at %s or less, AH value %s"] =
    " · achetez à %s ou moins, valeur HV %s",
  ["Buy at or under %s: a vendor pays %s each. This buy makes %s."] =
    "Achetez à %s ou moins : un marchand paie %s l'unité. Cet achat rapporte %s.",
  ["Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit."] =
    "Achetez à %s ou moins : la valeur HV, ce que demande le dixième le moins cher des unités en vente, est de %s. La vitesse de revente est inconnue, ce qui rend cet achat plus risqué qu'une affaire chez le marchand. Cet achat rapporte environ %s après la commission de 5%% et la caution.",
  ["under the vendor price. Click Buy to purchase"] =
    "sous le prix du marchand. Clique sur Buy pour acheter",
  ["far under the market, resale speed unknown. Click Buy to purchase"] =
    "bien sous le marché, vitesse de revente inconnue. Clique sur Buy pour acheter",
  ["No deals in your last scan."] =
    "Aucune affaire dans votre dernier scan.",
  ["Deals appear as soon as the scan finds them."] =
    "Les bonnes affaires s'affichent dès que le scan les trouve.",
  ["GoldCap looks for items listed cheaper than they are worth. SCAN looks again."] =
    "GoldCap recherche les objets vendus moins cher que leur valeur. SCAN scanne à nouveau.",
  ["No scan of this auction house yet."] =
    "Aucun scan de cet hôtel des ventes pour l'instant.",
  ["GoldCap scans when you open the auction house; SCAN on this board scans again."] =
    "GoldCap scanne quand vous ouvrez l'hôtel des ventes ; SCAN sur ce tableau scanne à nouveau.",
  ["In WoW: Forever, GoldCap's prices come from your own auction house scans."] =
    "Dans WoW: Forever, les prix de GoldCap viennent de vos propres scans de l'hôtel des ventes.",
  ["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."] =
    "Ouvrez l'hôtel des ventes et GoldCap le scanne pour vous ; SCAN dans l'onglet Affaires scanne à nouveau.",
  ["%ds"] = "%d s",
  ["%dm"] = "%d min",
  ["%dh"] = "%d h",
  ["%dd"] = "%d j",
  -- WoW: Forever crowd prices (UI/Tooltip.lua, plan 3d).
  ["1 scanner, %s ago"] = "1 scanner, il y a %s",
  ["%d scanners, %s ago"] = "%d scanners, il y a %s",
  ["resale at the AH value of players' scans, %s each, after the 5%% cut and deposit; speed unknown"] = "revente à la valeur HV des scans des joueurs, %s l'unité, moins 5%% et caution ; vitesse inconnue",
  ["Shared with goldcap.gg on your next /reload"] = "Partagé avec goldcap.gg au prochain /reload",
  ["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."] = "Vos scans restent sur cet ordinateur. Le GoldCap Companion les partage avec goldcap.gg et vous rapporte les prix de tous.",
  ["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."] = "Le GoldCap Companion partage vos scans avec goldcap.gg après chaque /reload et vous rapporte les prix de tous.",
  ["You opened %s: its first %s prices are yours."] =
    "Vous avez ouvert %s : ses %s premiers prix sont les vôtres.",
  ["Your scan updated %s prices on %s. %s of them nobody else had in the last 24 hours."] =
    "Votre scan a mis à jour %s prix sur %s, dont %s que personne d'autre n'avait ces dernières 24 heures.",
  ["Your scan updated %s prices on %s."] =
    "Votre scan a mis à jour %s prix sur %s.",
  -- Sold tab: tiles, period chips, search, day groups and the sale tooltip.
  ["%d DAYS"] = "%d JOURS",
  ["TODAY"] = "AUJOURD'HUI",
  ["YESTERDAY"] = "HIER",
  ["SUN"] = "DIM",
  ["MON"] = "LUN",
  ["TUE"] = "MAR",
  ["WED"] = "MER",
  ["THU"] = "JEU",
  ["FRI"] = "VEN",
  ["SAT"] = "SAM",
  ["YOU GOT"] = "REÇU",
  ["YOU GOT · %s"] = "REÇU · %s",
  ["EACH"] = "UNITÉ",
  ["%d sales · after the AH cut"] = "%d ventes · après commission",
  ["1 sale · after the AH cut"] = "1 vente · après commission",
  ["%d here · all on goldcap.gg"] = "%d ici · toutes sur goldcap.gg",
  ["cost known for %d of %d"] = "coût connu pour %d sur %d",
  ["%s of %s"] = "%s sur %s",
  ["%s · gold %s, bags %s"] = "%s · or %s, sacs %s",
  ["set the riding cost: %s"] = "indiquez le coût de la monture : %s",
  ["GOLDCAP.GG · %d DAYS"] = "GOLDCAP.GG · %d JOURS",
  ["profit · synced %s ago"] = "profit · synchro il y a %s",
  ["after the AH cut · synced %s ago"] = "après commission · synchro il y a %s",
  ["BEST SALE"] = "MEILLEURE VENTE",
  ["%s profit"] = "%s de profit",
  ["no sale with a known profit yet"] = "aucune vente au profit connu pour l'instant",
  ["OPEN SELL"] = "OUVRIR SELL",
  ["Find an item"] = "Chercher un objet",
  ["JUST SOLD"] = "TOUT JUSTE VENDU",
  ["reaches goldcap.gg on /reload or logout"] = "arrive sur goldcap.gg au /reload ou à la déconnexion",
  ["ON GOLDCAP.GG"] = "SUR GOLDCAP.GG",
  ["latest %d of %d · the rest on goldcap.gg"] = "%d plus récentes sur %d · le reste sur goldcap.gg",
  ["last %d days"] = "%d derniers jours",
  ["%d sales · %s"] = "%d ventes · %s",
  ["1 sale · %s"] = "1 vente · %s",
  ["sold today at %s · %d × %s"] = "vendu aujourd'hui à %s · %d × %s",
  ["sold %s at %s · %d × %s"] = "vendu le %s à %s · %d × %s",
  ["sold, the money is in your mail · %d × %s"] = "vendu, l'argent est dans votre courrier · %d × %s",
  ["Sale price"] = "Prix de vente",
  ["Auction house cut"] = "Commission de l'HV",
  ["Auction house cut, 5%"] = "Commission de l'HV, 5 %",
  ["You got"] = "Reçu",
  ["You paid (%s)"] = "Payé (%s)",
  ["%s each"] = "%s l'unité",
  ["Sniper"] = "Sniper",
  ["BUY list"] = "liste BUY",
  ["set by you"] = "saisi par vous",
  ["the auction house"] = "l'hôtel des ventes",
  ["crafted"] = "fabriqué",
  ["The profit is worked out once the money arrives."] = "Le profit sera calculé à l'arrivée de l'argent.",
  ["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."] =
    "GoldCap n'a jamais vu cet achat, il n'y a donc pas de profit à afficher. Indiquez son coût dans SELL.",
  ["Market now %s · you sold %d%% above it"] = "Marché actuel %s · vendu %d%% au-dessus",
  ["Market now %s · you sold %d%% under it"] = "Marché actuel %s · vendu %d%% en dessous",
  ["Market now %s · you sold at it"] = "Marché actuel %s · vendu au même prix",
  ["Your sales show up here once you open a mailbox with GoldCap loaded."] =
    "Vos ventes s'afficheront ici dès que vous ouvrirez une boîte aux lettres avec GoldCap chargé.",
  ["List something in SELL first."] = "Mettez d'abord quelque chose en vente dans SELL.",
  ["No sales match “%s” today."] = "Aucune vente ne correspond à « %s » aujourd'hui.",
  ["No sales match “%s” in these %d days."] = "Aucune vente ne correspond à « %s » sur ces %d jours.",
  ["No sales today."] = "Aucune vente aujourd'hui.",
  ["No sales in these %d days."] = "Aucune vente sur ces %d jours.",
  ["SEARCH 30 DAYS"] = "CHERCHER SUR 30 JOURS",
  ["SHOW 30 DAYS"] = "VOIR 30 JOURS",
  ["▲%d%% over the alert target"] = "▲%d%% au-dessus de la cible de l'alerte",
  ["▲%d%% over usual"] = "▲%d%% au-dessus de l'habituel",
  ["▲%d%% over your cap"] = "▲%d%% au-dessus de ton plafond",
  -- The quest reward mark (UI/QuestRewardMark.lua).
  ["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."] =
    "GoldCap : la récompense dans le cadre doré est celle qui vaut le plus à l'hôtel des ventes (%s).",
  -- The vendor note (UI/MerchantNote.lua).
  ["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."] =
    "1 objet de tes sacs vaut plus à l'hôtel des ventes (+%s). Garde-le pour l'HV.",
  ["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."] =
    "%d objets de tes sacs valent plus à l'hôtel des ventes (+%s). Garde-les pour l'HV.",
  -- BUY 2.0 week 2: a gear line is bought one lot per press (UI/BuyFrame.lua).
  ["BUY ONE · %s"] = "ACHETER UN · %s",
  ["not enough gold"] = "pas assez d'or",
  ["set a cap first"] = "fixez d'abord un plafond",
  -- BUY 2.0 week 2: a gear line's lots on the dock (UI/BuyFrame.lua).
  ["%s · %d lots"] = "%s · %d lots",
  ["%s · 1 lot"] = "%s · 1 lot",
  ["%s · over your cap"] = "%s · au-dessus de votre plafond",
  ["no cap for this item. Right-click the line to set one"] =
    "aucun plafond pour cet objet. Clic droit sur la ligne pour en fixer un",
  -- BUY 2.0 week 2: the vendor panel beside the merchant (UI/BuyVendorPanel.lua).
  ["BUY %d · %s"] = "ACHETER %d · %s",
  ["BUY · %s"] = "ACHETER · %s",
  -- BUY 2.0: the item box and the quick list (UI/BuyFrame.lua).
  ["Could not find that item. Shift-click it, or type its item id."] =
    "Objet introuvable. Faites Maj+clic dessus, ou tapez son ID d'objet.",
  ["Item to add"] = "Objet à ajouter",
  ["Make a list once, buy it here at or under your price."] =
    "Faites une liste une fois, achetez ici à votre prix ou moins.",
  ["Remove from the list"] = "Retirer de la liste",
  ["or plan a whole profession on goldcap.gg"] = "ou planifiez tout un métier sur goldcap.gg",
  -- BUY 2.0: the item box's hint, with the x count (UI/BuyFrame.lua).
  -- Glyphs every face that draws them has (spec/client_text_spec.lua's glyph inventory).
  ["HIDE DETAILS ▲"] = "MASQUER LES DÉTAILS ▲",
  ["SHOW DETAILS ▼"] = "AFFICHER LES DÉTAILS ▼",
  ["plan updated on goldcap.gg · +%d -%d lines"] =
    "plan mis à jour sur goldcap.gg · +%d -%d lignes",
  ["~ goldcap.gg market value, no live quote yet"] =
    "~ valeur de marché goldcap.gg, pas encore de cotation en direct",
  ["→ needs price"] = "→ prix requis",
  -- BUY 2.0: lists made in the game -- New, Import, Export, Rename, favourites, order, Delete
  ["Items the game has not loaded yet are left out: %d. Export again in a moment."] =
    "Le jeu n'a pas encore chargé %d objets, ils sont laissés de côté. Exportez à nouveau dans un instant.",
  ["%s and %d more"] = "%s et %d autres",
  ["+ New"] = "+ Nouvelle",
  ["Add to favourites"] = "Ajouter aux favoris",
  ["Added %d items to %s."] = "%d objets ajoutés à %s.",
  ["Added %d× %s to %s."] = "%d× %s ajouté à %s.",
  ["Added %d× %s to a new list, %s."] = "%d× %s ajouté à une nouvelle liste, %s.",
  ["Copy as a TSM item list"] = "Copier comme liste d'objets TSM",
  ["Copy for Auctionator"] = "Copier pour Auctionator",
  ["Delete"] = "Supprimer",
  ["Delete %s? This cannot be undone."] = "Supprimer %s ? Cette action est définitive.",
  ["Delete this list…"] = "Supprimer cette liste…",
  ["Export"] = "Exporter",
  ["From goldcap.gg: rename or remove it there"] =
    "De goldcap.gg : renomme-la ou retire-la là-bas",
  ["GoldCap: Import a list"] = "GoldCap : Importer une liste",
  ["Import a list…"] = "Importer une liste…",
  ["One list per subgroup"] = "Une liste par sous-groupe",
  ["Import into this list…"] = "Importer dans cette liste…",
  ["Imported %s with %d items."] = "%s importée avec %d objets.",
  ["List %d"] = "Liste %d",
  ["Lists come from goldcap.gg through the companion, or make one here with + New."] =
    "Les listes viennent de goldcap.gg par le Companion, ou créez-en une ici avec + Nouvelle.",
  ["Lists: click to switch, make, import or export one"] =
    "Listes : clique pour changer, créer, importer ou exporter une liste",
  ["Move down"] = "Descendre",
  ["Move up"] = "Monter",
  ["Name this list"] = "Nom de la liste",
  ["New list"] = "Nouvelle liste",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import."] =
    "Collez une liste de goldcap.gg, TSM ou Auctionator et cliquez sur Importer.",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."] =
    "Collez une liste de goldcap.gg, TSM ou Auctionator et cliquez sur Importer. Ses objets sont ajoutés à %s.",
  ["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."] =
    "Appuyez sur Ctrl+C pour copier, puis importez-la dans l'onglet Achats d'Auctionator.",
  ["Press Ctrl+C to copy, then import it into a TSM group."] =
    "Appuyez sur Ctrl+C pour copier, puis importez-la dans un groupe TSM.",
  ["Remove from favourites"] = "Retirer des favoris",
  ["Rename…"] = "Renommer…",
  ["Save"] = "Enregistrer",
  ["The game could not tell which items these are: %s. Shift-click them into the item box instead."] =
    "Le jeu n'a pas pu identifier ces objets : %s. Ajoutez-les plutôt par Maj+clic dans la case d'objet.",
  ["There are no items in this list."] = "Cette liste ne contient aucun objet.",
  ["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."] =
    "C'est l'export de groupe compressé de TSM, que seul TSM sait décompresser. Collez-le sur goldcap.gg/list, cliquez là-bas sur « Copier comme groupe TSM » et collez le résultat ici.",
  ["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."] =
    "GoldCap ne sait pas lire cette liste. Collez une liste de goldcap.gg, TSM ou Auctionator.",
  ["in game"] = "en jeu",
  -- Buy runs: the import result and the vendor list, now that the BUY tab's lists use them.
  ["The run's vendor reagents. Press Ctrl+C to copy the list."] =
    "Les composants de marchand de la liste. Appuyez sur Ctrl+C pour copier la liste.",
  ["Vendor list"] = "Liste du marchand",
  ["run imported: %s (%d lines)"] = "liste importée : %s (%d lignes)",
  ["the run string is not valid"] = "la chaîne de liste n'est pas valide",
  -- BUY: a gear line's tooltip names the lot it buys next (UI/BuyFrame.lua).
  ["next to buy: %s"] = "prochain achat : %s",
  -- BUY: the item box at the top -- several items at once, typed names, recents (UI/BuyAddBox.lua).
  ["Add"] = "Ajouter",
  ["Added %d items to a new list, %s."] = "%d objets ajoutés à une nouvelle liste, %s.",
  ["Clear"] = "Effacer",
  ["Could not read: %s."] = "Illisible : %s.",
  ["Items to add: %d (%s)"] = "À ajouter : %d (%s)",
  ["Recent:"] = "Récents :",
  ["Shift-click items, type a name, or an item id with x and a count: 2589 x20."] =
    "Maj+clic sur des objets, tapez un nom, ou un ID d'objet avec x et la quantité : 2589 x20.",
  -- BUY search: what is on sale, the results, opening one and adding it to a list (UI/BuySearch.lua).
  ["AVAILABLE"] = "DISPONIBLES",
  ["Back to %s"] = "Retour à %s",
  ["Click to buy it here. Right-click to add it to a list."] =
    "Cliquez pour l'acheter ici. Clic droit pour l'ajouter à une liste.",
  ["Close search"] = "Fermer la recherche",
  ["How many"] = "Combien",
  ["Loading more results…"] = "Chargement d'autres résultats…",
  ["More results"] = "Plus de résultats",
  ["Nothing on sale for “%s”."] = "Rien en vente pour « %s ».",
  ["On sale for “%s”: %d"] = "En vente pour « %s » : %d",
  ["Open the auction house to search what's on sale."] =
    "Ouvrez l'hôtel des ventes pour chercher ce qui est en vente.",
  ["PRICE FROM"] = "À PARTIR DE",
  ["Search again"] = "Relancer la recherche",
  ["Searching the auction house for “%s”…"] = "Recherche de « %s » à l'hôtel des ventes…",
  ["The auction house did not answer. Search again."] =
    "L'hôtel des ventes n'a pas répondu. Relancez la recherche.",
  ["Waiting for the auction house…"] = "En attente de l'hôtel des ventes…",
  -- Craft costs: which reagent had no price and why, and the merchant as a source of cost
  -- (Core/CraftCapture.lua, Core/VendorBuys.lua).
  ["this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed"] =
    "cette recette transforme un composant en plusieurs objets différents (prospection, broyage, mouture), donc elle n'a pas de coût",
  ["%s ×%d: no purchase of it found, here or on your other characters"] =
    "%s ×%d : aucun achat trouvé, ni ici ni sur tes autres personnages",
  ["%s ×%d: only %d of them were bought, the rest has no price"] =
    "%s ×%d : seulement %d ont été achetés, le reste n'a pas de prix",
  ["%s ×%d: made by prospecting, crushing or milling, not bought"] =
    "%s ×%d : obtenu par prospection, broyage ou mouture, pas acheté",
  ["%s ×%d: bought as different variants, so which one was used is unclear"] =
    "%s ×%d : acheté sous des variantes différentes, on ne sait donc pas laquelle a servi",
  ["%s: %d at the vendor price, %s each"] =
    "%s : %d au prix du marchand, %s pièce",
  ["%s: priced from another character's purchases"] =
    "%s : valorisé d'après les achats d'un autre personnage",
  ["%s: %d at the market price, %s each"] =
    "%s : %d au prix du marché, %s l'unité",
  ["Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price"] =
    "Une partie de ce coût est une estimation : les composants que vous n'avez pas achetés sont comptés à leur prix actuel à l'hôtel des ventes",
  ["Vendor"] =
    "Marchand",
  ["SELLING %d"] = "EN VENTE %d",
  ["NOT SELLING %d"] = "PAS EN VENTE %d",
  ["POST lists these"] = "VENDRE les met en vente",
  ["click one to post it"] = "clique sur un objet pour le vendre",
  ["Selling"] = "En vente",
  ["Not selling"] = "Pas en vente",
  ["POST lists it, and so does the key for posting the next item."] = "VENDRE le met en vente, de même que la touche pour l'objet suivant.",
  ["POST passes it by. Click the item to post it from the bar below."] = "VENDRE le passe. Clique sur l'objet pour le vendre depuis la barre du bas.",
  ["Marked for you: you bought it on DEALS."] = "Marqué pour toi : tu l'as acheté dans DEALS.",
  ["Click to change."] = "Clique pour changer.",
  ["Done for this visit"] = "Fait pour cette visite",
  ["POST passes it by until you close the auction house. Click to have POST list it again."] =
    "VENDRE le passe jusqu'à ce que tu fermes l'hôtel des ventes. Clique pour que VENDRE le remette en vente.",
  ["Mark what to sell with the circle"] = "Marque d'un cercle ce que tu veux vendre",
  ["PROCEEDS"] = "RECETTE",
  ["What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut."] = "Ce que te rapporte tout ce que VENDRE met en vente si tout part à ces prix, après les 5 % de commission de l'hôtel des ventes.",
  ["What your lots bring in if they all sell, after the auction house's 5% cut."] = "Ce que te rapportent tes enchères si elles partent toutes, après les 5 % de commission de l'hôtel des ventes.",
  ["PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it."] = "RECETTE moins ce que tu as payé ce stock. Affiché seulement tant que GoldCap sait ce que tu l'as payé en entier.",
  ["HOW MANY"] = "QUANTITÉ",
  ["MAX"] = "MAX",
  ["skipped"] = "passé",
  ["posted"] = "en vente",
  ["POST"] = "VENDRE",
  ["SKIP"] = "PASSER",
  ["then %s"] = "puis %s",
  ["need %d"] = "besoin %d",
  ["need %d · have %d"] = "besoin %d · possédé %d",
  ["cap %s"] = "plafond %s",
  ["no cap"] = "sans plafond",
  ["%s under your cap"] = "%s sous ton plafond",
  ["at your cap"] = "pile au plafond",
  ["for %d"] = "pour %d",
  ["goes into %s"] = "pour %s",
  ["market price"] = "prix du marché",
  ["craft %d× (%d per craft)"] = "fabriquer %d× (%d par fabrication)",
  ["%s spent"] = "%s dépensé",
  ["No list yet"] = "Pas encore de liste",
  ["Add to %s"] = "Ajouter à %s",
  ["Add to a new list"] = "Ajouter à une nouvelle liste",
  ["Add %d to a list"] = "Ajouter %d à une liste",
  ["Checking %d gear, pets and recipes…"] = "Vérification de l'équipement, des mascottes et des recettes (%d)…",
  ["Deals appear here as the auction house answers."] = "Les bonnes affaires s'affichent ici à mesure que l'hôtel des ventes répond.",
  ["checking items %d of %d"] = "vérification des objets %d sur %d",
  ["deals %s · watching %d items"] = "affaires %s · %d objets surveillés",
  ["Flips"] = "Revente",
  ["Rare finds"] = "Trouvailles rares",
  ["No flips on this realm right now"] = "Rien à revendre sur ce royaume pour l'instant",
  ["No rare finds on this realm right now"] =
    "Aucune trouvaille rare sur ce royaume pour l'instant",
  ["Nothing here you lack"] = "Rien ici ne te manque",
  ["Only what I lack"] = "Seulement ce qui me manque",
  ["Shows only what your account has not collected yet: appearances, pets, toys and mounts, and recipes this character does not know."] =
    "N'affiche que ce que ton compte n'a pas encore collecté : apparences, mascottes, jouets et montures, et les recettes que ce personnage ne connaît pas.",
  ["Ctrl-click to try it on"] = "Ctrl+clic pour l'essayer",
  ["Not collected"] = "Non collecté",
  ["Not known by this character"] = "Inconnu de ce personnage",
  ["Appearance known"] = "Apparence connue",
  ["Cheapest of %d realms"] = "Le moins cher des %d royaumes",
  ["Among the cheapest 10%% of %d realms"] = "Parmi les 10%% les moins chers des %d royaumes",
  ["Cheaper than 3 in 4 of %d realms"] = "Moins cher que 3 royaumes sur 4 (sur %d)",
  ["Sold %d times in 30 days"] = "Vendu %d fois en 30 jours",
  ["Sold once in 30 days"] = "Vendu une fois en 30 jours",
  ["last for %s %s"] = "dernière vente à %s %s",
  ["%d days ago"] = "il y a %d jours",
  ["1 day ago"] = "il y a 1 jour",
  ["%d hours ago"] = "il y a %d heures",
  ["1 hour ago"] = "il y a 1 heure",
  ["less than an hour ago"] = "il y a moins d'une heure",
  ["No sale seen in 30 days"] = "Aucune vente vue en 30 jours",
  ["Sold %d times in 7 days on %d realms"] = "Vendu %d fois en 7 jours sur %d royaumes",
  ["Rare find: seldom sold, so GoldCap puts no price on it"] =
    "Trouvaille rare : rarement vendue, donc GoldCap ne lui donne aucun prix",
  -- The welcome window (UI/WelcomeFrame.lua): what GoldCap does, the state of the prices, GoldCap Companion.
  ["Welcome to GoldCap"] = "Bienvenue sur GoldCap",
  ["Your GoldCap prices"] = "Tes prix GoldCap",
  ["GoldCap puts its prices in item tooltips. At the auction house, the GoldCap tab has:"] =
    "GoldCap affiche ses prix dans les infobulles des objets. À l'hôtel des ventes, l'onglet GoldCap propose :",
  ["Finds items listed below what they usually sell for, and checks each one before you buy."] =
    "Trouve les objets en vente sous leur prix habituel et vérifie chacun avant que tu achètes.",
  ["Finds items listed below what a vendor pays, or far below their usual price."] =
    "Trouve les objets en vente sous le prix d'un marchand, ou bien sous leur prix habituel.",
  ["Prices everything in your bags. POST lists it, one item per click."] =
    "Estime tout ce qui est dans tes sacs. VENDRE le met en vente, un objet par clic.",
  ["What you sold, and the profit on each sale where GoldCap knows what you paid."] =
    "Ce que tu as vendu, et le bénéfice de chaque vente dont GoldCap connaît le prix d'achat.",
  ["Shopping lists for crafting: buys each item up to the price you set."] =
    "Listes de courses pour l'artisanat : achète chaque objet jusqu'au prix que tu fixes.",
  ["No prices for your region yet"] = "Pas encore de prix pour ta région",
  ["Only the prices GoldCap came with, from %s ago"] = "Seulement les prix livrés avec GoldCap, vieux de %s",
  ["Fresh prices from the Companion, %s ago"] = "Prix récents de Companion, il y a %s",
  ["The Companion last sent prices %s ago"] = "Companion a envoyé des prix pour la dernière fois il y a %s",
  ["You pasted these prices %s ago"] = "Tu as collé ces prix il y a %s",
  ["The Companion's prices could not be read"] = "Les prix de Companion n'ont pas pu être lus",
  ["Everyone's prices are in, from %s ago"] = "Les prix de tous les joueurs sont là, vieux de %s",
  ["No prices from other players for this auction house yet"] =
    "Pas encore de prix d'autres joueurs pour cet hôtel des ventes",
  ["No fresh prices for your realm, so DEALS finds no deals. GoldCap Companion brings them and keeps them fresh: %s"] =
    "Pas de prix récents pour ton royaume, donc DEALS ne trouve aucune affaire. GoldCap Companion les apporte et les garde à jour : %s",
  ["Your pasted prices are %s old. GoldCap Companion fetches fresh ones every 30 minutes and brings your groups from goldcap.gg: %s"] =
    "Tes prix collés datent de %s. GoldCap Companion en récupère des récents toutes les 30 minutes et apporte tes groupes de goldcap.gg : %s",
  ["GoldCap Companion has not sent prices for %s. Check that it is running, its icon sits next to the clock: %s"] =
    "GoldCap Companion n'a pas envoyé de prix depuis %s. Vérifie qu'il est lancé, son icône se trouve à côté de l'horloge : %s",
  ["Could not read what the Companion wrote. Update GoldCap and GoldCap Companion: %s"] =
    "Impossible de lire ce que le Companion a écrit. Mets à jour GoldCap et GoldCap Companion : %s",
  ["GoldCap Companion adds every GoldCap player's scans of this auction house to yours, for more items with a price and newer prices: %s"] =
    "GoldCap Companion ajoute à tes scans ceux de tous les joueurs GoldCap de cet hôtel des ventes, pour plus d'objets avec un prix et des prix plus récents : %s",
  ["No prices from other players for this auction house yet. If GoldCap Companion is not running, start it: %s"] =
    "Pas encore de prix d'autres joueurs pour cet hôtel des ventes. Si GoldCap Companion n'est pas lancé, lance-le : %s",
  ["Nobody has shared a scan of this auction house for %s"] =
    "Personne n'a partagé de scan de cet hôtel des ventes depuis %s",
  ["Prices from your own scans only"] = "Prix issus de tes propres scans uniquement",
  ["These prices came with GoldCap and change only when GoldCap itself updates. DEALS needs fresh prices from your realm to find anything, so until then it finds no deals."] =
    "Ces prix sont fournis avec GoldCap et ne changent que quand GoldCap lui-même est mis à jour. DEALS a besoin de prix récents de ton royaume pour trouver quelque chose, donc d'ici là il ne trouve aucune bonne affaire.",
  ["GoldCap came with no prices for your region, so DEALS finds no deals until GoldCap Companion brings them."] =
    "GoldCap n'est fourni avec aucun prix pour ta région, donc DEALS ne trouve aucune bonne affaire tant que GoldCap Companion ne les apporte pas.",
  ["New prices reach GoldCap every time you log in or type /reload."] =
    "Les nouveaux prix arrivent dans GoldCap à chaque connexion ou avec /reload.",
  ["DEALS and every price go by what it sent last. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."] =
    "DEALS et tous les prix se basent sur ce qu'il a envoyé en dernier. Vérifie que GoldCap Companion est lancé (son icône se trouve à côté de l'horloge), puis tape /reload.",
  ["A pasted string goes stale within a day. GoldCap Companion fetches fresh prices for you every 30 minutes."] =
    "Un texte collé est périmé en moins d'un jour. GoldCap Companion récupère des prix récents pour toi toutes les 30 minutes.",
  ["With prices this old, DEALS can show deals that are no longer there. GoldCap Companion fetches fresh prices for you every 30 minutes."] =
    "Avec des prix aussi vieux, DEALS peut montrer des affaires qui n'existent plus. GoldCap Companion récupère des prix récents pour toi toutes les 30 minutes.",
  ["GoldCap could not read what the Companion wrote (%s). Update GoldCap and GoldCap Companion, then type /reload."] =
    "GoldCap n'a pas pu lire ce que Companion a écrit (%s). Mets à jour GoldCap et GoldCap Companion, puis tape /reload.",
  ["Your own scans and every other GoldCap player's are combined: for each item, the newer price wins."] =
    "Tes propres scans et ceux de tous les autres joueurs GoldCap sont combinés : pour chaque objet, le prix le plus récent l'emporte.",
  ["Your own scans still work. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."] =
    "Tes propres scans fonctionnent toujours. Vérifie que GoldCap Companion est lancé (son icône se trouve à côté de l'horloge), puis tape /reload.",
  ["Your own scans work meanwhile. If GoldCap Companion is not running, start it and type /reload."] =
    "Tes propres scans fonctionnent en attendant. Si GoldCap Companion n'est pas lancé, démarre-le et tape /reload.",
  ["GoldCap Companion is running and brings every scan of this auction house that GoldCap players share, but none has come in lately. Your own scans still work."] =
    "GoldCap Companion est lancé et apporte chaque scan de cet hôtel des ventes que partagent les joueurs GoldCap, mais aucun n'est arrivé récemment. Tes propres scans fonctionnent toujours.",
  ["GoldCap knows only what your own scans of this auction house found. With GoldCap Companion you also get the scans of every GoldCap player here: more items with a price, and newer prices."] =
    "GoldCap ne connaît que ce que tes propres scans de cet hôtel des ventes ont trouvé. Avec GoldCap Companion, tu reçois aussi les scans de tous les joueurs GoldCap d'ici : plus d'objets avec un prix, et des prix plus récents.",
  ["Get GoldCap Companion"] = "Obtenir GoldCap Companion",
  ["A small free app for Windows, macOS and Linux. It fetches your realm's prices every 30 minutes, with no account needed. Its code is open on GitHub."] =
    "Une petite application gratuite pour Windows, macOS et Linux. Elle récupère les prix de ton royaume toutes les 30 minutes, sans compte. Son code est ouvert sur GitHub.",
  ["A small free app for Windows, macOS and Linux. Every 30 minutes it brings the prices every GoldCap player scanned on your auction house, with no account needed. Its code is open on GitHub."] =
    "Une petite application gratuite pour Windows, macOS et Linux. Toutes les 30 minutes, elle apporte les prix scannés par chaque joueur GoldCap dans ton hôtel des ventes, sans compte. Son code est ouvert sur GitHub.",
  ["1. Copy this link (%s) and open it in your browser:"] =
    "1. Copie ce lien (%s) et ouvre-le dans ton navigateur :",
  ["2. Install GoldCap Companion and start it."] = "2. Installe GoldCap Companion et lance-le.",
  ["3. Back in the game, type /reload."] = "3. De retour en jeu, tape /reload.",
  ["Not installed on this computer? It is here:"] = "Pas installé sur cet ordinateur ? Il est ici :",
  ["The latest version is here:"] = "La dernière version est ici :",
  ["/gc companion opens this window again."] = "/gc companion rouvre cette fenêtre.",
  ["Got it"] = "Compris",
  ["Don't remind me"] = "Ne plus me rappeler",
  ["sells within a day"] = "se vend en moins d'un jour",
  ["sells in about 1 day"] = "se vend en 1 jour environ",
  ["sells in about %d days"] = "se vend en %d jours environ",
  ["Sell here for %s, %s"] = "Vendez-le ici à %s, %s",
  ["Sell on %s for %s, %s"] = "Vendez-le sur %s à %s, %s",
  ["Pays more on %s, where you have no character: %s, %s"] = "Rapporte plus sur %s, où vous n'avez aucun personnage : %s, %s",
  ["Among the 5 cheapest of %d realms"] = "Parmi les 5 moins chers des %d royaumes",
  ["The price is checked against what this sold for across the region. Where it sells best is below."] = "Le prix est vérifié par rapport à ce que l'objet s'est vendu dans la région. Où il se vend le mieux, juste en dessous.",
  ["Sell on"] = "Vendre sur",
  ["Cheapest realms"] = "Moins chers",
  ["Better on"] = "Mieux sur",
  ["under a day"] = "moins d'un jour",
  ["about 1 day"] = "1 jour environ",
  ["about %d days"] = "%d jours environ",
  ["top 5 of %d"] = "top 5 sur %d",
  ["this realm"] = "ce royaume",
  ["Put in the Warband Bank"] = "Déposer à la banque de bataillon",
  ["Take out to sell here"] = "Retirer pour vendre ici",
  ["Can't be sold"] = "Invendable",
  ["Warbound until equipped: the auction house refuses it"] = "Lié au bataillon jusqu'à ce qu'il soit équipé : l'hôtel des ventes le refuse",
  ["here: %s, %s"] = "ici : %s, %s",
  ["for %s: %s, %s"] = "pour %s : %s, %s",
  ["Then log in a character on that realm and open a bank: GoldCap lists what to take out."] = "Connectez ensuite un personnage de ce royaume et ouvrez une banque : GoldCap indique quoi retirer.",
  ["Then list it from GoldCap's Sell tab at the auction house."] = "Mettez-le ensuite en vente depuis l'onglet Vendre de GoldCap à l'hôtel des ventes.",
  ["At a bank: which flips to put in the Warband Bank for another of your realms, and which to take out and sell here. /gc route lists them anywhere."] = "À une banque : quels objets à revendre déposer à la banque de bataillon pour un autre de vos royaumes, et lesquels retirer pour les vendre ici. /gc route les liste partout.",
  ["Where each flip sells comes with the Companion's region data: nothing to go on yet."] = "Où chaque objet se vend arrive avec les données de région du Companion : rien pour l'instant.",
  ["Nothing in your bags sells notably better on another of your realms."] = "Rien dans vos sacs ne se vend nettement mieux sur un autre de vos royaumes.",
  ["What to take out of the Warband Bank shows at a bank."] = "Ce qu'il faut retirer de la banque de bataillon s'affiche à une banque.",
  -- Followed groups: the DEALS chip and its tooltip.
  ["GROUP"] = "GROUPE",
  ["Listed at or under the deal price of a group you follow (%s)"] = "Mis en vente au prix de bonne affaire d'un groupe que tu suis ou en dessous (%s)",
  -- Followed groups: a group's selling rule in words (Core/GroupRules.lua).
  ["1 at a time"] = "1 à la fois",
  ["all you have"] = "tout ce que tu as",
  ["%d h"] = "%d h",
  ["not under %d%% of usual"] = "pas sous %d%% du prix habituel",
  ["not under the cost to craft"] = "pas sous le coût de fabrication",
  ["%d%% cheaper each time it comes back"] = "%d%% moins cher à chaque retour",
  -- Followed groups: SELL's row, its mark and the dock.
  ["Group you follow: %s"] = "Groupe que tu suis : %s",
  ["Marked for you: it is in a group you follow."] = "Marqué pour toi : il est dans un groupe que tu suis.",
  ["under group floor"] = "sous le plancher du groupe",
  ["the market is under your group's floor. Type a price to post anyway"] = "le marché est sous le plancher de ton groupe. Saisis un prix pour mettre en vente quand même",
  -- Followed groups: cancel by a group's floor, and the cancel threshold.
  ["Min. undercut to cancel (%)"] = "Écart min. pour annuler (%)",
  ["Cancel only when someone undercuts you by more than this percent. At 0 any undercut counts. Lots far below their value are always queued."] = "N'annule que si quelqu'un passe sous ton prix de plus de ce pourcentage. À 0, tout écart compte. Les lots très en dessous de leur valeur vont toujours dans la file.",
  ["small undercut"] = "petit écart",
  ["relisting would go under your group's floor. Hold"] = "remettre en vente passerait sous le plancher de ton groupe. Garde-le",
  ["undercut by less than your cancel setting. Hold"] = "écart plus petit que ton réglage d'annulation. Garde-le",
  -- the cancel run (groups in the addon, task 13)
  ["Cancel %d lots? You lose %s in deposits. One press per lot, CONFIRM first."] = "Annuler %d lots ? Tu perds %s de cautions. Un appui par lot, d'abord CONFIRMER.",
  ["Cancel %d lots? One press per lot, CONFIRM first."] = "Annuler %d lots ? Un appui par lot, d'abord CONFIRMER.",
  ["Cancel 1 lot? You lose its %s deposit. Press CONFIRM."] = "Annuler 1 lot ? Tu perds sa caution de %s. Appuie sur CONFIRMER.",
  ["Cancel 1 lot? Press CONFIRM."] = "Annuler 1 lot ? Appuie sur CONFIRMER.",
  ["CANCEL NEXT (%d)"] = "ANNULER LE SUIVANT (%d)",
  ["Press again to cancel the next lot"] = "Appuie à nouveau pour annuler le lot suivant",
  ["Stopped: 20 seconds without a press"] = "Arrêté : 20 secondes sans appui",
  ["Stop"] = "Arrêter",
  ["VENDOR"] = "MARCHAND",
  ["Better at vendor"] = "Mieux au marchand",
  ["Forget kept items"] = "Oublier les objets gardés",
  ["Sell to vendor lists unbound items a vendor pays as much for as the auction house would after its cut, judged only by an auction house price from the last 24 hours, never by the prices built into the addon. Grey items are left to the vendor window's own Sell All Junk button."] = "Vendre au marchand liste les objets non liés qu'un marchand paie autant que l'hôtel des ventes après sa commission, d'après un prix de l'hôtel des ventes des dernières 24 heures seulement, jamais d'après les prix fournis avec l'addon. Les objets gris restent au bouton de vente de la camelote de la fenêtre du marchand.",
  ["Sell to vendor"] = "Vendre au marchand",
  ["Sell %d for %s"] = "Vendre %d pour %s",
  ["%d more after this"] = "%d de plus après celle-ci",
  ["Right click a line to keep that item."] = "Clic droit sur une ligne pour garder cet objet.",
  ["Never sell this"] = "Ne jamais vendre",
  ["The game sells one stack per press here."] = "Le jeu ne vend ici qu'une pile par appui.",
  ["Sold %d stacks for %s. Buyback keeps the last 12 you sold."] = "%d piles vendues pour %s. Le rachat garde les 12 dernières ventes.",
  ["Sold 1 stack for %s. Buyback keeps the last 12 you sold."] = "1 pile vendue pour %s. Le rachat garde les 12 dernières ventes.",
  ["Reagents cost %s"] = "Les composants coûtent %s",
  ["One craft sells for %s after the auction house cut"] = "Une fabrication se vend %s après la commission de l'hôtel des ventes",
  ["Profit %s"] = "Profit %s",
  ["No GoldCap price for %s"] = "Pas de prix GoldCap pour %s",
  ["Worth crafting"] = "Rentable à fabriquer",
  ["Sells about %s a day"] = "Se vend environ %s fois par jour",
  ["Slow seller"] = "Se vend lentement",
  ["1 recipe has no GoldCap price for a reagent or what it makes"] = "1 recette n'a pas de prix GoldCap pour un composant ou ce qu'elle fabrique",
  ["%d recipes have no GoldCap price for a reagent or what it makes"] = "%d recettes n'ont pas de prix GoldCap pour un composant ou ce qu'elles fabriquent",
  ["Each reagent at its cheapest quality"] = "Chaque composant à sa qualité la moins chère",
  ["No recipe here has a GoldCap price yet"] = "Aucune recette ici n'a encore de prix GoldCap",
  ["1 recipe makes no profit now"] = "1 recette ne rapporte aucun profit pour l'instant",
  ["%d recipes make no profit now"] = "%d recettes ne rapportent aucun profit pour l'instant",
  ["No recipe here makes a profit now"] = "Aucune recette ici ne rapporte de profit pour l'instant",
  ["This recipe"] = "Cette recette",
  ["Add to queue"] = "Ajouter à la file",
  ["Restock to"] = "Compléter à",
  ["How many crafts of %s?"] = "Combien de fabrications de %s ?",
  ["Restock %s to how many? 0 takes it off the queue."] = "Compléter %s jusqu'à combien ? 0 le retire de la file.",
  ["Type a whole number"] = "Saisis un nombre entier",
  ["Queue"] = "File",
  ["%d to craft"] = "%d à fabriquer",
  ["Restock to %d: %d held"] = "Compléter à %d : %d en stock",
  ["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] = "Enchères pas encore comptées : ouvre l'onglet Vendre de GoldCap à l'hôtel des ventes",
  ["Remove from queue"] = "Retirer de la file",
  ["The queue is empty. Add a recipe from This recipe."] = "La file est vide. Ajoute une recette depuis « Cette recette ».",
  ["Missing"] = "Manquant",
  ["%d %s"] = "%d %s",
  ["%d %s in the mailbox"] = "%d %s dans la boîte aux lettres",
  ["%s is not sold on the auction house"] = "%s ne se vend pas à l'hôtel des ventes",
  ["Nothing is missing for the queue"] = "Rien ne manque pour la file",
  ["Make a BUY list"] = "Créer une liste BUY",
  ["Craft queue"] = "File de fabrication",
  ["BUY list %s is ready in the BUY tab at the auction house"] = "La liste BUY %s est prête dans l'onglet BUY de l'hôtel des ventes",
  ["Currency %d"] = "Monnaie %d",
  ["%d in bags, %d in the Warband Bank"] = "%d dans les sacs, %d à la banque de bataillon",
  ["Keep in bags: %d of each"] = "Garder dans les sacs : %d de chaque",
  ["How many of each item in %s to keep in your bags?"] = "Combien de chaque objet de %s garder dans tes sacs ?",
  ["Stays in bags: %s ×%d, can still be refunded"] = "Reste dans les sacs : %s ×%d, encore remboursable",
  ["Stays in bags: %s ×%d, the Warband Bank does not take it"] = "Reste dans les sacs : %s ×%d, la banque de bataillon ne le prend pas",
  ["%d in bags, %d in your bank"] = "%d dans les sacs, %d dans ta banque",
  ["Stays in bags: %s ×%d, your bank does not take it"] = "Reste dans les sacs : %s ×%d, ta banque ne le prend pas",
  ["None of your groups' items are in your bags or this bank."] = "Aucun objet de tes groupes n'est dans tes sacs ni dans cette banque.",
  ["None of your groups' items are in your bags or this bank. %s holds some of them: pick it at the top."] =
    "Aucun objet de tes groupes n'est dans tes sacs ni dans cette banque. Il y en a dans %s : choisis-la en haut.",
  ["You follow no groups yet. Follow some on goldcap.gg under Groups, and the GoldCap Companion brings them here: what each holds in your bags and this bank, to store or take out in one press."] =
    "Tu ne suis encore aucun groupe. Suis-en sur goldcap.gg, dans Groupes, et GoldCap Companion les amène ici : ce que chacun a dans tes sacs et cette banque, à déposer ou retirer en un clic.",
  -- GoldCap Hoard, the window beside the bank (UI/HoardFrame.lua, UI/HoardRow.lua).
  ["Hoard"] = "Trésor",
  ["Bags %d free"] = "Sacs : %d libres",
  ["Bank %d free"] = "Banque : %d libres",
  ["Your groups"] = "Tes groupes",
  ["bags"] = "sacs",
  ["bank"] = "banque",
  ["Store all"] = "Tout déposer",
  ["Take all out"] = "Tout retirer",
  ["Store"] = "Déposer",
  ["Take out"] = "Retirer",
  ["%s ×%d (%d left)"] = "%s ×%d (encore %d)",
  ["Nothing to move"] = "Rien à déplacer",
  ["Gather"] = "Récolte",
  ["Craft"] = "Artisanat",
  ["Flip"] = "Revente",
  ["Stock"] = "Réserve",
  ["%d groups"] = "%d groupes",
  ["%d more groups have nothing to move at this bank"] = "%d autres groupes n'ont rien à déplacer dans cette banque",
  ["1 more group has nothing to move at this bank"] = "1 autre groupe n'a rien à déplacer dans cette banque",
  -- Its search row, the selection bar and a run's cast bar (UI/HoardList.lua).
  ["To move here %d"] = "À déplacer %d",
  ["All %d"] = "Tous %d",
  ["By value"] = "Par valeur",
  ["By name"] = "Par nom",
  ["No group or item matches your search."] = "Aucun groupe ni objet ne correspond à ta recherche.",
  ["%d groups selected"] = "%d groupes sélectionnés",
  ["1 group selected"] = "1 groupe sélectionné",
  ["Clear the selection"] = "Effacer la sélection",
  ["Moving to %s"] = "Déplacement vers la %s",
  ["Moving to your bags"] = "Déplacement vers tes sacs",
  ["Tick groups to move several at once"] = "Coche des groupes pour en déplacer plusieurs à la fois",
  ["Worth about %s"] = "Valeur d'environ %s",
  ["Stop moving"] = "Arrêter le déplacement",
  ["%d stacks into %s"] = "%d piles vers la %s",
  ["1 stack into %s"] = "1 pile vers la %s",
  ["%d stacks into your bags"] = "%d piles vers tes sacs",
  ["1 stack into your bags"] = "1 pile vers tes sacs",
  -- GoldCap Hoard: its tiles (UI/HoardTiles.lua), carry cards (UI/HoardCarry.lua) and footer (UI/HoardFooter.lua).
  [", %d not shown"] = ", %d masqués",
  ["Ready now"] = "Prêt maintenant",
  ["Prices are up"] = "Les prix montent",
  ["For your crafts"] = "Pour ton artisanat",
  ["Put away"] = "Ranger",
  ["%d items sell above your usual price"] = "%d objets se vendent au-dessus de ton prix habituel",
  ["1 item sells above your usual price"] = "1 objet se vend au-dessus de ton prix habituel",
  ["Nothing sells above your usual price now"] = "Rien ne se vend au-dessus de ton prix habituel pour l'instant",
  ["Reagents for the %d crafts in your queue"] = "Composants pour les %d fabrications de ta file",
  ["Reagents for the craft in your queue"] = "Composants pour la fabrication de ta file",
  ["Your craft queue is empty"] = "Ta file de fabrication est vide",
  ["What you are not selling now, keeping what each group keeps"] = "Ce que tu ne vends pas maintenant ; ce que chaque groupe garde reste dans tes sacs",
  ["Take out %s"] = "Retirer %s",
  ["Take out %d stacks"] = "Retirer %d piles",
  ["Take out 1 stack"] = "Retirer 1 pile",
  ["Store %d stacks"] = "Déposer %d piles",
  ["Store 1 stack"] = "Déposer 1 pile",
  ["%d stacks"] = "%d piles",
  ["1 stack"] = "1 pile",
  ["and %d more"] = "et %d de plus",
  ["These sell above the usual price you set for their group."] = "Ils se vendent au-dessus du prix habituel que tu as fixé pour leur groupe.",
  ["Price per unit: now / usual"] = "Prix à l'unité : maintenant / habituel",
  ["Takes them out to your bags, ready for the Sell tab."] = "Les retire dans tes sacs, prêts pour l'onglet Vendre.",
  ["What your craft queue needs that your bags lack, from this bank."] = "Ce dont ta file de fabrication a besoin et qui manque dans tes sacs, depuis cette banque.",
  ["Per reagent: need / in bags / taken"] = "Par composant : besoin / dans les sacs / retiré",
  ["Leaves out what sells above its usual price and what your craft queue needs."] = "Laisse de côté ce qui se vend au-dessus de son prix habituel et ce dont ta file de fabrication a besoin.",
  ["Carry to another realm"] = "À emporter sur un autre royaume",
  ["Put in"] = "Déposer",
  ["Make room"] = "Faire de la place",
  ["Put back"] = "Remettre",
  ["Moves every stack in your bags that %s takes, except a hearthstone, and remembers what went for Put back."] = "Déplace vers la %s chaque pile de tes sacs qu'elle accepte, sauf la pierre de foyer, et retient ce qui est parti pour Remettre.",
  ["Takes back from %s what Make room put there. It lands wherever your bags have room, not in its old slots."] = "Reprend de la %s ce que Faire de la place y a mis. Cela arrive là où tes sacs ont de la place, pas dans les anciens emplacements.",
  ["What Make room put away is in %s: switch to it to put it back."] = "Ce que Faire de la place a rangé est dans la %s : passe sur celle-ci pour le remettre.",
  ["Make room has put nothing away to bring back."] = "Faire de la place n'a rien rangé à remettre.",
  ["Prices from the Companion, %s ago"] = "Prix de Companion, il y a %s",
  ["What Make room put away is still in %s: put it back first."] = "Ce que Faire de la place a rangé est toujours dans la %s : remets-le d'abord.",
  ["A newer version of GoldCap saved what Make room remembers: update GoldCap to use it."] = "Une version plus récente de GoldCap a enregistré ce dont Faire de la place se souvient : mets GoldCap à jour pour l'utiliser.",
  ["GoldCap does not know this character's name and realm yet, so Make room cannot remember what it puts away."] = "GoldCap ne connaît pas encore le nom et le royaume de ce personnage, donc Faire de la place ne peut pas retenir ce qu'il range.",
  ["GROUPS"] = "GROUPES",
  ["ALL %d"] = "TOUT %d",
  ["MY GROUPS %d"] = "MES GROUPES %d",
  ["MY GROUPS"] = "MES GROUPES",
  ["Post goes through your groups only"] = "VENDRE ne parcourt que tes groupes",
  ["Post goes through %s only"] = "VENDRE ne parcourt que %s",
  ["Nothing left in this group"] = "Plus rien dans ce groupe",
  ["Everything from this group in your bags is posted. Pick ALL to see the rest of your bags."] = "Tout ce que tes sacs contenaient de ce groupe est en vente. Choisis TOUT pour voir le reste de tes sacs.",
  ["Posting your groups: %d of %d done"] = "Mise en vente de tes groupes : %d sur %d faits",
  ["Posting %s: %d of %d done"] = "Mise en vente de %s : %d sur %d faits",
  ["your default from Settings"] = "ton prix par défaut des Réglages",
  ["%s never posts under %s"] = "%s n'est jamais mis en vente sous %s",
  ["Default price"] = "Prix par défaut",
  ["Every item opens at this price. A group's floor still holds, and a price under what you paid still shows in red."] = "Chaque objet démarre à ce prix. Le plancher d'un groupe tient toujours, et un prix sous ce que tu as payé reste en rouge.",
  ["Sells here within a day"] = "Se vend ici en moins d'un jour",
  ["Sells here in about 1 day"] = "Se vend ici en 1 jour environ",
  ["Sells here in about %d days"] = "Se vend ici en %d jours environ",
  ["Sells on %s within a day"] = "Se vend sur %s en moins d'un jour",
  ["Sells on %s in about 1 day"] = "Se vend sur %s en 1 jour environ",
  ["Sells on %s in about %d days"] = "Se vend sur %s en %d jours environ",
  ["Sold once in 7 days"] = "Vendu une fois en 7 jours",
  ["Sold %d times in 7 days"] = "Vendu %d fois en 7 jours",
  ["after the 5% cut, if it sells at the region's price"] = "après la commission de 5%, s'il se vend au prix de la région",
  ["a unit, at or under the group's price of %s"] = "l'unité, au prix du groupe de %s ou en dessous",
  ["From a group you follow on goldcap.gg. Whether it resells is yours to judge."] = "D'un groupe que tu suis sur goldcap.gg. À toi de juger s'il se revend.",
  ["Region price"] = "Prix de la région",
  ["Group's price"] = "Prix du groupe",
  ["at or under the group's price. Click Buy to purchase"] = "au prix du groupe ou en dessous. Clique sur Buy pour acheter",
  ["price checked a moment ago. Whether it sells is your call"] = "prix vérifié à l'instant. À toi de juger s'il se vend",
  ["GoldCap is checking prices here"] = "GoldCap vérifie les prix ici",
  ["The auction house shows GoldCap's searches in this list, so it changes on its own. To use the list yourself, search, pick a category or click the star. GoldCap then leaves it to you until you click AUTO or SCAN."] =
    "L'hôtel des ventes affiche les recherches de GoldCap dans cette liste, elle change donc toute seule. Pour t'en servir, fais une recherche, choisis une catégorie ou clique sur l'étoile. GoldCap te la laisse ensuite jusqu'à ce que tu cliques sur AUTO ou SCAN.",
  ["On the Items board, Auto keeps checking the items this board watches, round after round. Switch to Commodities and it scans the commodity market again."] =
    "Sur le tableau Objets, Auto vérifie les objets que ce tableau suit, tour après tour. Passe aux Marchandises et il scanne de nouveau le marché des marchandises.",
  ["Craft %d"] = "Fabriquer %d",
  ["Crafts %d now, one after another, with the reagents the profession window would use. Moving stops it."] =
    "Fabrique %d maintenant, l'un après l'autre, avec les composants que prendrait la fenêtre de métier. Bouger l'interrompt.",
  ["Open %s to craft it here."] = "Ouvre %s pour le fabriquer ici.",
  ["Open this recipe's profession to craft it here."] =
    "Ouvre le métier de cette recette pour la fabriquer ici.",
  ["Not enough reagents for one craft. Missing below says what to get."] =
    "Pas assez de composants pour une fabrication. Manquant, plus bas, dit quoi trouver.",
  -- Send to alts: the window beside the mailbox (UI/MailAltsFrame.lua).
  ["Send to alts"] = "Envoyer aux rerolls",
  ["Postage"] = "Frais de port",
  ["Send all"] = "Tout envoyer",
  ["1 mail to 1 of your characters"] = "1 courrier pour 1 de tes personnages",
  ["%d mails to 1 of your characters"] = "%d courriers pour 1 de tes personnages",
  ["%d mails to %d of your characters"] = "%d courriers pour %d de tes personnages",
  ["%s to %s"] = "%s pour %s",
  ["%s to %s in one mail"] = "%s pour %s en un courrier",
  ["%s, %s"] = "%s, %s",
  ["%s and %s"] = "%s et %s",
  ["%s. %d stacks."] = "%s. %d piles.",
  ["%s. 1 stack."] = "%s. 1 pile.",
  ["Sending 1 mail"] = "Envoi de 1 courrier",
  ["Sending %d mails"] = "Envoi de %d courriers",
  ["%s went to %s."] = "%s : envoyé à %s.",
  ["%s went to %s in one mail."] = "%s : envoyé à %s en un courrier.",
  ["Sending %s to %s now."] = "Envoi de %s à %s en cours.",
  ["Mail %d of %d: %s to %s"] = "Courrier %d sur %d : %s pour %s",
  ["%d sent"] = "Envoyés : %d",
  ["Nothing to send now"] = "Rien à envoyer pour l'instant",
  ["Follow groups on goldcap.gg to send them to your alts here."] =
    "Suis des groupes sur goldcap.gg pour les envoyer ici à tes rerolls.",
  ["Your groups have nothing in your bags beyond what they keep."] =
    "Tes groupes n'ont rien dans tes sacs au-delà de ce qu'ils gardent.",
  ["Your groups in your bags"] = "Tes groupes dans tes sacs",
  ["Gold is never sent, and what a group keeps stays in your bags. Soulbound items stay too. Each mail holds up to 12 stacks, so a big group goes in a few mails."] =
    "L'or n'est jamais envoyé, et ce qu'un groupe garde reste dans tes sacs. Les objets liés restent aussi. Un courrier contient jusqu'à 12 piles, donc un gros groupe part en plusieurs courriers.",
  ["Keep %d"] = "Garder %d",
  ["Who sells it?"] = "Qui le vend ?",
  ["This character"] = "Ce personnage",
  ["Send"] = "Envoyer",
  ["Send to %s? Press again"] = "Envoyer à %s ? Appuie à nouveau",
  ["Sent"] = "Envoyé",
  ["Sending"] = "Envoi",
  ["Next"] = "Ensuite",
  ["Choose who it goes to, once. GoldCap remembers."] = "Choisis une fois à qui ça va. GoldCap s'en souvient.",
  ["This character sells them, so they stay."] = "Ce personnage les vend, donc ils restent.",
  ["Nothing to send beyond what it keeps."] = "Rien à envoyer au-delà de ce qu'il garde.",
  ["Bound to you: a mail cannot take it."] = "Lié à toi : un courrier ne peut pas l'emporter.",
  ["Can still be refunded: a mail would end that, so it stays."] =
    "Encore remboursable : un courrier y mettrait fin, donc il reste.",
  ["Who sells %s?"] = "Qui vend %s ?",
  ["Your characters on this realm"] = "Tes personnages sur ce royaume",
  ["Type a name"] = "Saisir un nom",
  ["Nobody yet"] = "Personne pour l'instant",
  ["gets %s"] = "reçoit %s",
  ["seen today"] = "vu aujourd'hui",
  ["seen yesterday"] = "vu hier",
  ["seen %d days ago"] = "vu il y a %d jours",
  ["Name or Name-Realm"] = "Nom ou Nom-Royaume",
  ["A name that is not one of your characters is asked about once, before the first mail goes."] =
    "Pour un nom qui n'est pas l'un de tes personnages, GoldCap demande une fois, avant le premier courrier.",
  ["Type a character name"] = "Saisis un nom de personnage",
  ["Mail goes only to a character on this realm or a connected one."] =
    "Le courrier ne va qu'à un personnage de ce royaume ou d'un royaume connecté.",
  ["The mailbox did not answer. Check your bags and the Send Mail tab."] =
    "La boîte aux lettres n'a pas répondu. Vérifie tes sacs et l'onglet Envoyer un message.",
  ["Stopped: something is on your cursor."] = "Arrêté : tu as quelque chose sur le curseur.",
  ["Stopped: the Send Mail tab already holds items."] =
    "Arrêté : l'onglet Envoyer un message contient déjà des objets.",
  ["Stopped: %s would not go into the mail."] = "Arrêté : %s n'a pas pu être joint au courrier.",
  ["Stopped."] = "Arrêté.",
  ["The Send Mail tab was closed."] = "L'onglet Envoyer un message a été fermé.",
  ["Sent 1 mail."] = "1 courrier envoyé.",
  ["Sent %d mails."] = "%d courriers envoyés.",
  ["The mail to %s did not go."] = "Le courrier pour %s n'est pas parti.",
  ["Postage is %s and this character has %s."] = "Les frais de port sont de %s et ce personnage a %s.",
  ["Your other characters show here once each has logged in with GoldCap."] =
    "Tes autres personnages apparaissent ici dès que chacun s'est connecté avec GoldCap.",
  ["Disenchant"] = "Désenchanter",
  ["Disenchant next"] = "Désenchanter le suivant",
  ["Now"] = "En cours",
  ["Mats pay more: about %s against %s from a vendor."] =
    "Les compos rapportent plus : environ %s contre %s chez un marchand.",
  ["A vendor pays more: %s against about %s in mats."] = "Un marchand paie plus : %s contre environ %s en compos.",
  ["GoldCap learns what this gives the first time."] = "GoldCap apprend la première fois ce que cela donne.",
  ["GoldCap has no price yet for what this gives."] = "GoldCap n'a pas encore de prix pour ce que cela donne.",
  ["The auction house pays more: %s after its cut."] = "L'hôtel des ventes paie plus : %s après sa commission.",
  ["Disenchanting"] = "Désenchantement",
  ["One press, one item. A key works too: %s, GoldCap, %s."] =
    "Un clic, un objet. Une touche marche aussi : %s, GoldCap, %s.",
  ["You get about"] = "Tu obtiens environ",
  ["Got so far"] = "Obtenu jusqu'ici",
  ["GoldCap learns what these give as you disenchant."] =
    "GoldCap apprend ce qu'ils donnent au fil de tes désenchantements.",
  ["In this order"] = "Dans cet ordre",
  ["Mats"] = "Compos",
  ["Never disenchant this"] = "Ne jamais désenchanter",
  ["Left out: the auction house pays more"] = "Écartés : l'hôtel des ventes paie plus",
  ["Left out: a vendor pays more"] = "Écartés : un marchand paie plus",
  ["Mats: about %s"] = "Compos : environ %s",
  ["Vendor %s, mats about %s"] = "Marchand %s, compos environ %s",
  ["Disenchant anyway"] = "Désenchanter quand même",
  ["Mats is what your own disenchants of such items gave, at today's prices. Never on the list: items in an equipment set, items you can still return or trade, items in a group you follow, and items you keep. Click a line to disenchant it next. Right-click a line to keep an item."] =
    "Compos, c'est ce que tes propres désenchantements de tels objets ont donné, aux prix du jour. Jamais dans la liste : les objets d'un ensemble d'équipement, ceux que tu peux encore rendre ou échanger, ceux d'un groupe que tu suis et ceux que tu gardes. Clic sur une ligne pour que l'objet soit le prochain désenchanté. Clic droit sur une ligne pour garder l'objet.",
  ["Nothing in your bags to disenchant."] = "Rien à désenchanter dans tes sacs.",
  ["Worth disenchanting: %d"] = "Rentable à désenchanter : %d",
  ["The auction house pays more: %d"] = "L'hôtel des ventes paie plus : %d",
  ["A vendor pays more: %d"] = "Un marchand paie plus : %d",
  ["Nothing worth disenchanting now: a vendor pays more for everything below."] =
    "Rien de rentable à désenchanter pour l'instant : un marchand paie plus pour tout ce qui suit.",
  ["Nothing worth disenchanting now: everything below sells for more."] =
    "Rien de rentable à désenchanter pour l'instant : tout ce qui suit se vend plus cher.",
  ["This character does not know Disenchant."] = "Ce personnage ne connaît pas Désenchanter.",
  ["item level %d"] = "niveau d'objet %d",
  ["%s, next"] = "%s, ensuite",
  ["%s, AH pays more"] = "%s, l'HV paie plus",
  ["%s, vendor pays more"] = "%s, le marchand paie plus",
  ["kept"] = "gardé",
  ["cannot be disenchanted"] = "impossible à désenchanter",
  ["not learned yet"] = "pas encore appris",
  ["no price yet"] = "pas encore de prix",
  ["Kept: 1 item"] = "Conservé : 1 objet",
  ["Kept: %d items"] = "Conservés : %d objets",
  ["Show"] = "Afficher",
  ["Never disenchanted"] = "Jamais désenchantés",
  ["Disenchant it again"] = "Désenchanter de nouveau",
  ["GoldCap could not disenchant these"] = "GoldCap n'a pas pu désenchanter ceux-ci",
  ["Try again"] = "Réessayer",
}
