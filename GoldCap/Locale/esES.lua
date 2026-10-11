local _, GC = ...

-- Spanish (Spain). Terminology follows apps/web/messages/es.json. Note "coste", which is the
-- peninsular form -- esMX uses "costo", and that is the main difference between the two files.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.esES = {
  ["  %s · need %d · have %d · buy %d · %s"] = "  %s · necesitas %d · tienes %d · comprar %d · %s",
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s cada uno  (%s en total, %s de comisión)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion lo mantiene al día: /goldcap companion.",
  [" · %d keys"] = " · %d claves",
  [" · below cost"] = " · por debajo del coste",
  [" · identity unresolved"] = " · identidad sin resolver",
  [" · stale %ds"] = " · %ds de antigüedad",
  [". Check again"] = ". Comprueba de nuevo",
  [" · commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " · comandos: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (o /gc para abreviar)",
  ["%d (whole lot)"] = "%d (lote completo)",
  ["%d ahead of you"] = "%d por delante de ti",
  ["%d at %s"] = "%d a %s",
  ["%d caps · %s"] = "%d topes · %s",
  ["%d days"] = "%d días",
  ["%d deals from your last scan. Full Scan to refresh"] =
    "%d oportunidades del último escaneo. Pulsa Full Scan para actualizar",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "%d descartadas: difíciles de revender o bajo tu beneficio mínimo por compra",
  ["%d held back"] = "%d retenidas",
  ["%d hidden: the live check refused them"] = "%d ocultos: la comprobación en vivo los ha rechazado",
  ["%d hits"] = "%d hallazgos",
  ["%d in %d lots"] = "%d en %d lotes",
  ["%d in 1 lot"] = "%d en 1 lote",
  ["%d lines"] = "%d líneas",
  ["%d lots, %s asked"] = "%d lotes, se piden %s",
  ["%d of %d"] = "%d de %d",
  ["%d of %d at or under your cap"] = "%d de %d a tu tope o menos",
  ["%d of %d done"] = "%d de %d hechas",
  ["%d prices in one request · books still loading"] =
    "%d precios en una sola consulta · los libros siguen cargando",
  ["%d refused by live checks. Press \"HIDDEN %d\" above to review them"] =
    "%d rechazadas por la comprobación en vivo. Pulsa «HIDDEN %d» arriba para verlas",
  ["%d units"] = "%d uds.",
  ["%d units · %d prices"] = "%d unidades · %d precios",
  ["%d · %d/%d covered"] = "%d · %d/%d cubiertos",
  ["%d/%d covered"] = "%d/%d cubiertos",
  ["%d× %s"] = "%d× %s",
  ["%d× %s · %s each · %s"] = "%d× %s · %s c/u · %s",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s por unidad    total %s -> %s",
  ["%s ahead"] = "%s por delante",
  ["%s each"] = "%s c/u",
  ["%s needs a number, for example /gc weights %s 1.5"] = "%s necesita un número, por ejemplo /gc weights %s 1.5",
  ["%s under you"] = "%s por debajo de ti",
  ["%s units in %d prices"] = "%s uds. en %d precios",
  ["%s · %s under market"] = "%s · %s bajo mercado",
  ["%s · at market price"] = "%s · a precio de mercado",
  ["%s: %d unit%s without a cost"] = "%s: %d unidad%s sin coste",
  ["%s → craft %d× (%d per craft)"] = "%s → fabricar %d× (%d por fabricación)",
  ["%s+ ahead"] = "%s+ por delante",
  ["%s+, %d prices read"] = "%s+ en %d precios",
  ["..."] = "...",
  ["1 lot, %s asked"] = "1 lote, se piden %s",
  ["24h trend"] = "Tendencia 24 h",
  ["A dash means GoldCap does not know the cost of every unit yet. It will never guess one from the market price."] =
    "Un guion significa que GoldCap aún no conoce el coste de cada unidad: nunca lo adivinará a partir del precio de mercado.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Una pista, no una promesa: reventa al 95% del valor de mercado importado, para la cantidad que Check aprobaría.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Si varias compras están agrupadas en una sola línea, se eliminan todas.",
  ["AH answered empty %ds ago"] = "la casa de subastas respondió vacío hace %ds",
  ["AH value"] = "Valor de subasta",
  ["AH, cheapest version"] = "Subasta, versión más barata",
  ["AUTO"] = "AUTO",
  ["AUTO · SCANNING"] = "AUTO · ESCANEANDO",
  ["AUTOMATION & ALERTS"] = "AUTOMATIZACIÓN Y AVISOS",
  ["AVOID"] = "EVITAR",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Por encima de esta subida en 24 horas, el valor de mercado se trata como un pico y se reduce.",
  ["Above your price: quoted %s, your price %s"] = "Por encima de tu precio: cotizado %s, tu precio %s",
  ["Alert target"] = "Objetivo de la alerta",
  ["Alerts"] = "Alertas",
  ["All"] = "Todo",
  ["Archive this run"] = "Archivar esta lista",
  ["Archived"] = "Archivadas",
  ["Asks for a second click to confirm."] = "Pide un segundo clic para confirmar.",
  ["At a vendor"] = "En vendedor",
  ["At your pace you reach it at level %d."] = "A tu ritmo lo consigues en el nivel %d.",
  ["At your pace you will be %s short at level 40."] = "A tu ritmo te faltarán %s en el nivel 40.",
  ["At your price"] = "A tu precio",
  ["Auction House did not answer. Press Refresh"] =
    "La casa de subastas no respondió. Pulsa Refresh",
  ["Auction House is not open"] = "La casa de subastas no está abierta",
  ["Auto-scan on next AH visit"] = "Escaneo automático en la próxima visita a la CS",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: mantiene Full Scan en marcha y cede al instante cuando compras, busca tú mismo en la casa de subastas, o revisa el correo. Haz clic para alternar.",
  ["Avoid"] = "Evitar",
  ["BOOKS %d/%d"] = "LIBROS %d/%d",
  ["BRAKES"] = "FRENOS",
  ["BUY %d"] = "COMPRAR %d",
  ["BUY (unverified)"] = "COMPRAR (sin verificar)",
  ["Background check"] = "Comprobación en segundo plano",
  ["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."] =
    "Blizzard aún no ha publicado el coste de equitación. Escribe /gc mount y el coste que esperas.",
  ["Blizzard's price: %s"] = "Precio de Blizzard: %s",
  ["Blizzard's price: %s · %d s left"] = "Precio de Blizzard: %s · quedan %d s",
  ["Bought"] = "Comprado",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "El punto de equilibrio es el precio más bajo que aún recupera tu coste tras la comisión. Vender por debajo pierde dinero.",
  ["Bundled %s data"] = "Datos %s incluidos",
  ["Bundled data"] = "Datos incluidos",
  ["Buy"] = "Comprar",
  ["Buy it whole instead"] = "Mejor comprarlo entero",
  ["Buy less"] = "Compra menos",
  ["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"] = "Compras: %s · %d líneas · %d por comprar · %d en vendedor · gastado %s · falta ~%s",
  ["Buy: no run selected."] = "Compras: no hay lista elegida.",
  ["CANCEL %d"] = "CANCELAR %d",
  ["CANCEL LOT?"] = "¿CANCELAR EL LOTE?",
  ["CANCELLING…"] = "CANCELANDO…",
  ["CONFIRM"] = "CONFIRMAR",
  ["COST"] = "COSTE",
  ["COST / UNIT"] = "COSTE / UNIDAD",
  ["Can't price this"] = "Sin precio fiable",
  ["Cancel"] = "Cancelar",
  ["Cancel lot"] = "Cancelar",
  ["Cancel lot?"] = "¿Cancelar?",
  ["Cancel this lot and lose its deposit. Click again to confirm"] =
    "Cancelar este lote y perder el depósito. Pulsa otra vez para confirmar",
  ["Cancel timed out"] = "La cancelación agotó el tiempo",
  ["Cancelling lot…"] = "Cancelando el lote…",
  ["Cancels this live auction. It does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Cancela esta subasta activa: NO la vuelve a publicar. Pierdes el depósito y los objetos vuelven por correo; publícalos de nuevo desde esta fila cuando lleguen.",
  ["Cannot post this position"] = "No se puede publicar esta posición",
  ["Cannot remove this entry"] = "No se puede borrar esta entrada",
  ["Cannot repost this lot"] = "No se puede volver a publicar este lote",
  ["Cap for %s"] = "Tope para %s",
  ["Cap: %d%%"] = "Tope: %d%%",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limitado por lo rápido que se vende de verdad, no por tu bolsa.",
  ["Change the cap…"] = "Cambiar el tope…",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Quedan subastas más baratas, pero al ritmo de este objeto se agotan en horas.",
  ["Check"] = "Revisar",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower (or refuse) if the market has moved since your last import."] =
    "Check lo recalcula contra el libro de órdenes en vivo antes de que se mueva el oro, y aún puede salir más bajo, o rechazar, si el mercado ha cambiado desde tu última importación.",
  ["Checked against the live order book a moment ago."] =
    "Comprobado hace un momento contra el libro de órdenes en vivo.",
  ["Checked: %d of the top %d on screen"] = "Comprobadas: %d de las %d primeras en pantalla",
  ["Checking prices…"] = "Comprobando precios…",
  ["Checking prices: waiting for the Auction House…"] = "Comprobando precios: esperando a la casa de subastas…",
  ["Checking this item's price…"] = "Comprobando el precio de este objeto…",
  ["Checking..."] = "Comprobando...",
  ["Clear to buy"] = "Vía libre para comprar",
  ["Click Confirm to post"] = "Pulsa Confirm para publicar",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Otro clic cancela la subasta activa. No la vuelve a publicar: pierdes el depósito y los objetos vuelven por correo en vez de directamente a tus bolsas.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Otro clic borra definitivamente este coste introducido a mano.",
  ["Close"] = "Cerrar",
  ["Companion keeps prices fresh: /goldcap companion"] =
    "Companion mantiene los precios al día: /goldcap companion",
  ["Companion sync rejected:"] = "Sincronización de Companion rechazada:",
  ["Confirm"] = "Confirmar",
  ["Confirm the cancel"] = "Confirmar la cancelación",
  ["Confirm the removal"] = "Confirmar la eliminación",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Copia el enlace (Ctrl+C) y ábrelo en un navegador:",
  ["Copy vendor list"] = "Copiar lista de vendedor",
  ["Cost per unit"] = "Coste por unidad",
  ["Cost unknown for %d of %d"] = "Coste desconocido en %d de %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Cuesta más de lo que permite tu límite por compra.",
  ["Could not read that amount. Type it like 12g 50s."] = "No se pudo leer esa cantidad. Escríbela así: 12g 50s.",
  ["Don't skip"] = "No omitir",
  ["Everything here is bought"] = "Aquí está todo comprado",
  ["From goldcap.gg: manage it there"] = "De goldcap.gg: gestiónala allí",
  ["From your scan %s ago. Counts only %s. Change with /gc weights."] =
    "De tu escaneo de hace %s. Solo cuenta %s. Cámbialo con /gc weights.",
  ["Gear upgrades on the auction house"] = "Mejoras de equipo en la casa de subastas",
  ["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."] =
    "GoldCap ahora cuenta lo que sueltan las criaturas que despojas, sin nombres, para las probabilidades de botín en goldcap.gg. El Companion lo compartirá cuando esa parte salga. Escribe /gc loot off para detenerlo.",
  ["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."] =
    "Objetos de tus bolsas que valen más en la casa de subastas que en un vendedor: %d (%s más).",
  ["Items still loading: %d. Open this again in a moment."] =
    "Objetos que aún se cargan: %d. Vuelve a abrir esto en un momento.",
  ["Loot counting is off. Type /gc loot clear to remove what was recorded."] =
    "El recuento de botín está desactivado. Escribe /gc loot clear para eliminar lo registrado.",
  ["Loot counting is on."] = "El recuento de botín está activado.",
  ["Loot record cleared."] = "Registro de botín eliminado.",
  ["Market"] = "Mercado",
  ["Mount cost cleared."] = "Coste de la montura borrado.",
  ["Mount cost set to %s."] = "Coste de la montura fijado en %s.",
  ["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] =
    "Aún no hay un escaneo con equipo. Abre la casa de subastas y deja que GoldCap la escanee.",
  ["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] =
    "Aún no hay pesos de estadísticas para tu clase. Defínelos así: /gc weights STR 1 STA 0.5",
  ["Nothing on the auction house beats what you wear at your level."] =
    "Nada en la casa de subastas supera lo que llevas a tu nivel.",
  ["Nothing on this list matches."] = "Nada de esta lista coincide.",
  ["Over cap"] = "Sobre el tope",
  ["PRICE EACH"] = "PRECIO UNIDAD",
  ["Play a little longer for an estimate of your pace."] = "Juega un poco más para estimar tu ritmo.",
  ["RAISE CAP TO %s"] = "SUBIR TOPE A %s",
  ["ROAD TO 40"] = "CAMINO AL NIVEL 40",
  ["Raise cap to %s"] = "Subir el tope a %s",
  ["Restore %s"] = "Restaurar %s",
  ["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."] =
    "Camino al nivel 40 con GoldCap: %s de %s para mi montura (%d%%).",
  ["Road to 40: %s of %s (gold %s, bags %s)."] = "Camino al nivel 40: %s de %s (oro %s, bolsas %s).",
  ["Road to 40: you have %s (gold %s, bags %s)."] = "Camino al nivel 40: tienes %s (oro %s, bolsas %s).",
  ["Runs"] = "Listas",
  ["Set cap"] = "Fijar tope",
  ["Skip"] = "Omitir",
  ["Skip for now"] = "Omitir por ahora",
  ["Skipped"] = "Omitido",
  ["Split into reagents (craft %d×)"] = "Dividir en componentes (fabricar %d×)",
  ["Stat weights: %s"] = "Pesos de estadísticas: %s",
  ["TO BUY HERE"] = "POR COMPRAR AQUÍ",
  ["The rest is skipped for now"] = "El resto está omitido por ahora",
  ["This client does not report item stats, so GoldCap cannot compare gear."] =
    "Este cliente no informa de las estadísticas de los objetos, así que GoldCap no puede comparar equipo.",
  ["This lot holds more units than your Max units per buy."] =
    "Este lote tiene más unidades que tu «Máx. de unidades por compra».",
  ["Could not find the queue's next lot to cancel. Try again"] =
    "No se encontró el siguiente lote de la cola para cancelar. Inténtalo otra vez",
  ["DEFAULTS"] = "PREDETERMINADO",
  ["DISC"] = "DESC",
  ["DISPLAY"] = "PANTALLA",
  ["DONE"] = "LISTO",
  ["Default listing length for the Sell tab."] =
    "Duración de publicación predeterminada para la pestaña Vender.",
  ["Default: %s"] = "Por defecto: %s",
  ["Deletes a hand-entered cost you typed into Set cost, never a purchase GoldCap itself captured or matched to your mail."] =
    "Borra un coste que escribiste a mano en Fijar coste, nunca una compra que GoldCap capturó o emparejó con tu correo.",
  ["Discount"] = "Descuento",
  ["Discount vs market value from your GoldCap import"] =
    "Descuento frente al valor de mercado de tu importación de GoldCap",
  ["Dump-trend cap %"] = "Tope de tendencia a la baja %",
  ["Duration"] = "Duración",
  ["Enlarge the window to see details"] = "Agranda la ventana para ver los detalles",
  ["Enter a whole quantity"] = "Introduce una cantidad entera",
  ["Enter an exact positive cost"] = "Introduce un coste exacto y positivo",
  ["Entry price (avg fill)"] = "Precio de entrada (ejecución media)",
  ["Entry total"] = "Total de entrada",
  ["Everything else checks out. With more gold on this character, this is a buy."] = "Todo lo demás cuadra. Con más oro en este personaje, sería una compra.",
  ["FIFO allocations"] = "Asignaciones FIFO",
  ["Fetching a fresh price for this item. Press Post again in a moment"] =
    "Obteniendo un precio nuevo para este objeto. Vuelve a pulsar Post en un momento",
  ["Fetching a fresh price for this lot. Press Repost again in a moment"] =
    "Obteniendo un precio nuevo para este lote. Vuelve a pulsar Repost en un momento",
  ["Finish the pending post first"] = "Termina antes la publicación pendiente",
  ["Finish the pending post or repost first"] =
    "Termina antes la publicación o republicación pendiente",
  ["Font scale"] = "Tamaño de fuente",
  ["Free, sits in the tray, nothing to set up in game."] =
    "Gratis, vive en la bandeja del sistema y no hay nada que configurar en el juego.",
  ["Full pass over them: %.1fs"] = "Pasada completa: %.1fs",
  ["Full pass over them: measuring..."] = "Pasada completa: midiendo...",
  ["Gold tied up"] = "Oro inmovilizado",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap no puede determinar qué montón de la bolsa es este",
  ["GoldCap data age"] = "Antigüedad de los datos de GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap vuelve a comprobar las %d filas contra la casa de subastas en vivo, cada %d s. Las filas rechazadas se ocultan. Comprar sigue siendo siempre un clic tuyo.",
  ["GoldCap value"] = "Valor GoldCap",
  ["GoldCap: Import realm prices"] = "GoldCap: Importar precios del reino",
  ["GoldCap's"] = "de GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "La sugerencia de GoldCap para este objeto y el precio que usaría.",
  ["GoldCap: %s. %s"] = "GoldCap: %s. %s",
  ["GoldCap: checked live. A deal, but you need %s on this character"] = "GoldCap: comprobado en vivo. Es una oferta, pero necesitas %s en este personaje",
  ["GoldCap: checked live, safe to buy"] = "GoldCap: comprobado en vivo, seguro comprar",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: aún sin comprobar contra la casa de subastas en vivo",
  ["Gone"] = "Ya no está",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "En gris significa que la cotización ha envejecido; Post y Repost la actualizan antes de actuar.",
  ["HIDDEN 0"] = "OCULTAS 0",
  ["HOLDING %d"] = "MANTENER %d",
  ["Held back from cancelling"] = "Retenido de la cancelación",
  ["Held back from the queue"] = "Retenido de la cola",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Cuántas horas de ventas normales puede aguantar un muro bajo tu precio de salida antes de que se rechace la oferta.",
  ["ITEM"] = "OBJETO",
  ["If it clears"] = "Si se vende",
  ["Import"] = "Importar",
  ["Import failed:"] = "Fallo al importar:",
  ["Import from goldcap.gg to arm the sniper"] = "Importa desde goldcap.gg para activar el francotirador",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Instala el GoldCap Companion gratuito para mantener los precios al día automáticamente (/goldcap companion),",
  ["It is what you must beat to sell quickly, not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Es el precio que debes batir para vender rápido, no lo que vale el objeto. Un vendedor con prisa puede ponerlo muy por debajo de su valor, y GoldCap no le seguirá hacia abajo: mira WHAT TO DO para ver el precio al que publicaría de verdad.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "No inventará un coste a partir del precio de mercado, así que el beneficio seguirá siendo desconocido hasta que introduzcas uno.",
  ["Item"] = "Objeto",
  ["Item %d"] = "Objeto %d",
  ["Item level %d, below the %d your price is for"] =
    "Nivel de objeto %d, por debajo del %d para el que es tu precio",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE. The buy is your call, and GoldCap only checks them while this board is open."] =
    "Items: equipo, mascotas y recetas valorados frente a la referencia de región de tu importación. La velocidad de venta nunca se mide, así que nunca llegan a SEGURO. Esta la decides tú, y GoldCap solo los revisa mientras este tablero está abierto.",
  ["LISTED"] = "PUBLICADO",
  ["Language"] = "Idioma",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Idioma cambiado. Escribe /reload para aplicarlo en todas partes.",
  ["Last post may still go up. Wait a minute"] = "Aún puede publicarse. Espera un minuto",
  ["Level 40 reached: %s to go."] = "Nivel 40 alcanzado: aún te faltan %s.",
  ["Last result: %ds ago"] = "Último resultado: hace %ds",
  ["Last result: none yet this visit"] = "Último resultado: ninguno en esta visita",
  ["Listed"] = "Publicados",
  ["Listed at %s, far below market. Repost."] =
    "Publicado a %s, muy por debajo del mercado. Vuelve a publicarlo.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Publicado a tu precio de goldcap.gg o por debajo. Si se revende o no, lo valoras tú.",
  ["Listed value"] = "Valor publicado",
  ["Listings"] = "Publicaciones",
  ["Lists this item at the price on its row: the whole bag for a commodity, one stack for a regular item, or the number under HOW MANY."] =
    "Publica este objeto al precio de su fila: toda la bolsa si es una mercancía, una pila si es un objeto normal, o el número de CANTIDAD.",
  ["Live ask"] = "Precio en vivo",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lote cancelado; espera a que vuelva a las bolsas",
  ["MARKET"] = "MERCADO",
  ["MARKET / UNIT"] = "MERCADO / UNIDAD",
  ["MATCH"] = "IGUALAR",
  ["Market per unit"] = "Mercado por unidad",
  ["Market reference"] = "Referencia de mercado",
  ["Max units per buy"] = "Máx. de unidades por compra",
  ["Max wallet per buy %"] = "Máx. de tu oro por compra %",
  ["Min profit per buy (gold)"] = "Beneficio mínimo por compra (oro)",
  ["Min profit per buy (copper)"] = "Beneficio mínimo por compra (cobre)",
  ["To buy"] = "Por comprar",
  ["To craft"] = "Por fabricar",
  ["Total: %s"] = "Total: %s",
  ["Unknown stat %s. Use one of: %s"] = "Estadística desconocida %s. Usa una de: %s",
  ["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."] =
    "Mejoras para tu equipo en la casa de subastas: %d. Escribe /gc upgrades para verlas.",
  ["Use the default cap"] = "Usar el tope predeterminado",
  ["While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead."] = "Mientras esto se mantenga en el 5% por defecto, una pista con precio de vendedor puede usar hasta la mitad de tu oro.",
  ["Min return per buy %"] = "Retorno mín. por compra %",
  ["Missing cost"] = "Falta el coste",
  ["NO LIVE PRICE YET"] = "AÚN SIN PRECIO EN VIVO",
  ["YOUR LISTS"] = "TUS LISTAS",
  ["NOT ON HAND %d"] = "NO A MANO %d",
  ["NOTHING TO CANCEL"] = "NADA QUE CANCELAR",
  ["Needs a live price check before it can be bought."] =
    "Necesita una comprobación de precio en vivo antes de poder comprarse.",
  ["Needs gold"] = "Necesita oro",
  ["Never spend more than this share of your gold on one purchase."] =
    "Nunca gastar más de esta parte de tu oro en una sola compra.",
  ["No answer yet, listening for a minute"] = "Aún sin respuesta, escuchando un minuto",
  ["No deals passed the safety checks right now."] =
    "Ahora mismo ninguna oportunidad pasa las comprobaciones de seguridad.",
  ["No deals to show, and no realm prices yet."] =
    "No hay oportunidades que mostrar, ni precios del reino todavía.",
  ["No deals yet."] = "Aún no hay oportunidades.",
  ["No exact auction key"] = "Sin clave de subasta exacta",
  ["No exact bag stack"] = "Sin montón exacto en la bolsa",
  ["No exact bag variant"] = "Sin variante exacta en la bolsa",
  ["No live listings came back for this item."] =
    "No llegó ninguna subasta activa para este objeto.",
  ["No region reference for this item yet. Import again once goldcap.gg publishes one."] =
    "Todavía no hay precio de referencia de región para este objeto. Vuelve a importar cuando goldcap.gg publique uno.",
  ["No safe resale price could be worked out."] =
    "No se pudo calcular un precio de reventa seguro.",
  ["No sales data for this item."] = "No hay datos de ventas para este objeto.",
  ["Not enough gold on this character to buy what GoldCap finds"] = "Falta oro en este personaje para comprar estas ofertas",
  ["Not enough units on the Auction House to fill that quantity."] =
    "No hay unidades suficientes en la casa de subastas para esa cantidad.",
  ["Not in your bags or listed. Mail or bank?"] =
    "Ni en tus bolsas ni publicado. ¿Correo o banco?",
  ["Not on hand: the stock is in the mail, the bank, or on another character"] =
    "No disponible: las existencias están en el correo, el banco u otro personaje",
  ["Not worth the deposit on the AH"] = "No compensa el depósito en la subasta",
  ["Nothing is being held back."] = "No se está reteniendo nada.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Tras esta compra no queda nada contra lo que vender, así que no hay precio de salida.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Ningún anuncio alcanza el nivel de objeto con el que se midió el precio de referencia.",
  ["Nothing listed on the AH right now"] = "Ahora mismo no hay nada publicado en la subasta",
  ["Nothing to sell"] = "Nada que vender",
  ["Nothing in your bags to list. Buy on the Deals tab or pick up your mail: anything you can sell shows up here with a price ready."] =
    "No hay nada en tus bolsas para publicar. Compra en la pestaña Deals o recoge tu correo: todo lo que puedas vender aparece aquí con un precio listo.",
  ["No auctions up"] = "Sin subastas activas",
  ["No live auctions on this character. What you post shows up here, with what to cancel and what to leave."] =
    "Este personaje no tiene subastas activas. Lo que publiques aparece aquí, con lo que conviene cancelar y lo que conviene dejar.",
  ["No match"] = "Sin resultados",
  ["Nothing on this deck matches that search. Clear the box to see everything."] =
    "Nada en esta pestaña coincide con esa búsqueda. Vacía el cuadro para verlo todo.",
  ["Still pricing"] = "Consultando precios",
  ["The auction house is still answering. Items show up here as their prices arrive."] =
    "La casa de subastas aún está respondiendo. Los objetos aparecen aquí a medida que llegan sus precios.",
  ["Every cost is known"] = "Todos los costes conocidos",
  ["Every item in your bags already has what you paid on record. Turn off NO COST to see them all."] =
    "Todo lo que hay en tus bolsas ya tiene registrado lo que pagaste. Desactiva NO COST para verlo todo.",
  ["Nothing queued to cancel"] = "Nada en cola para cancelar",
  ["Nothing queued to post"] = "Nada en cola para publicar",
  ["Nothing to remove"] = "Nada que borrar",
  ["ON THE AUCTION HOUSE"] = "EN LA CASA DE SUBASTAS",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown: rescan anytime."] =
    "Un único escaneo de toda la casa de subastas mediante consultas paginadas. Tarda de 15 a 60 segundos en reinos concurridos. Sin espera: vuelve a escanear cuando quieras.",
  ["Open the Auction House first."] = "Abre primero la casa de subastas.",
  ["Open the Auction House to begin scanning."] =
    "Abre la casa de subastas para empezar a escanear.",
  ["Open the deals board. /gc for commands."] = "Abre el tablero de oportunidades. /gc para los comandos.",
  ["POSTING"] = "PUBLICACIÓN",
  ["POSTING…"] = "PUBLICANDO…",
  ["PRICE"] = "PRECIO",
  ["PRICE ROSE %.1fx"] = "EL PRECIO SUBIÓ %.1fx",
  ["PRICED TOO LOW %d"] = "DEMASIADO BARATO %d",
  ["PRICING %d/%d"] = "PRECIOS %d/%d",
  ["PRICING…"] = "PRECIOS…",
  ["PROFIT"] = "BENEFICIO",
  ["PROFIT / UNIT"] = "BENEFICIO / UNIDAD",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Vincula o actualiza el GoldCap Companion para ver el beneficio de goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Pega la cadena de tu reino desde goldcap.gg y pulsa Import.",
  ["Per-unit price of this auction"] = "Precio por unidad de esta subasta",
  ["Play a sound when a checked deal turns SAFE."] =
    "Reproducir un sonido cuando una oferta verificada pasa a SAFE.",
  ["Position scope changed"] = "El ámbito de la posición ha cambiado",
  ["Post"] = "Publicar",
  ["Post above the cheapest"] = "Publicar por encima del más barato",
  ["Post confirmation expired"] = "La confirmación de publicación ha caducado",
  ["Post the next queued item"] = "Publicar el siguiente objeto de la cola",
  ["Posted"] = "Publicado",
  ["Posting failed"] = "Fallo al publicar",
  ["Posting unavailable"] = "Publicación no disponible",
  ["Posting…"] = "Enviando…",
  ["Press Full Scan to find deals."] = "Pulsa Full Scan para buscar oportunidades.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Pulsa Scan para recorrer toda la casa de subastas una vez, o Auto para escanear sin parar.",
  ["Previous removal selection cleared"] = "Selección de borrado anterior descartada",
  ["Previous repost selection cleared"] = "Selección de republicación anterior descartada",
  ["Price"] = "Precio",
  ["Priced from bundled sample data, not from your realm."] =
    "Precio tomado de los datos de muestra incluidos, no de tu reino.",
  ["Prices up to date"] = "Precios al día",
  ["Prices up to date · %d did not answer"] = "Precios al día · %d sin respuesta",
  ["Pricing %d/%d…"] = "Consultando precios %d/%d…",
  ["Pricing paused while you use the Auction House"] = "Consulta de precios en pausa mientras usas la casa de subastas",
  ["Pricing…"] = "Cotizando…",
  ["Profit"] = "Beneficio",
  ["Profit per unit"] = "Beneficio por unidad",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "El seguimiento de beneficios es una función de goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "Las compras están desactivadas en esta versión.",
  ["Press Buy again to buy this quantity"] = "Pulsa Comprar de nuevo para comprar esta cantidad",
  ["QTY"] = "CANT",
  ["Quantity exceeds missing units"] = "La cantidad supera las unidades que faltan",
  ["Quantity is capped by how fast this item actually sells."] =
    "La cantidad está limitada por lo rápido que se vende realmente este objeto.",
  ["REFRESH"] = "ACTUALIZAR",
  ["RESET WINDOW"] = "RESTABLECER VENTANA",
  ["Reason"] = "Motivo",
  ["Refresh"] = "Actualizar",
  ["Refresh waiting for prior result"] = "La actualización espera el resultado anterior",
  ["Refreshing listings…"] = "Actualizando las publicaciones…",
  ["Refuse a buy when the price fell more than this in the last 24 hours: it may keep falling."] =
    "Rechazar una compra si el precio bajó más de esto en las últimas 24 horas: podría seguir bajando.",
  ["Refused so far: %d"] = "Rechazadas hasta ahora: %d",
  ["Removal confirmation expired"] = "La confirmación de borrado ha caducado",
  ["Remove"] = "Borrar",
  ["Remove this cost"] = "Eliminar este coste",
  ["Remove?"] = "¿Borrar?",
  ["Removed"] = "Eliminado",
  ["Removed %d entries"] = "Se eliminaron %d entradas",
  ["Removes every entered-by-hand purchase in this run. Click again to confirm"] =
    "Borra todas las compras introducidas a mano en este grupo. Pulsa otra vez para confirmar",
  ["Removes this entered-by-hand purchase. Click again to confirm"] =
    "Borra esta compra introducida a mano. Pulsa otra vez para confirmar",
  ["Repost confirmation expired"] = "La confirmación de republicación ha caducado",
  ["Right-click to stop watching this item"] = "Clic derecho para dejar de vigilar este objeto",
  ["Right-click to watch this item closely"] = "Clic derecho para vigilar de cerca este objeto",
  ["SAFE +%s"] = "SEGURO +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "SEGURO = la comprobación en vivo aprobó esta compra, con el beneficio mostrado",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SE GUARDA AL INSTANTE · ESC O DONE PARA CERRAR",
  ["SCAN"] = "ESCANEAR",
  ["SCANNING…"] = "ESCANEANDO…",
  ["SESSION %s%s · %d BUYS"] = "SESIÓN %s%s · %d COMPRAS",
  ["Sales are costed from your oldest units first"] =
    "Las ventas se imputan primero a tus unidades más antiguas",
  ["Search"] = "Buscar",
  ["Sales evidence"] = "Datos de venta",
  ["Sell it on the AH"] = "Véndelo en la subasta",
  ["Sell it on the AH (deposit not counted)"] = "Véndelo en la subasta (depósito no incluido)",
  ["Sell it to a vendor"] = "Véndelo a un vendedor",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "La pestaña Vender publica un escalón por encima de la oferta más barata cuando el libro indica que se vende igual de rápido.",
  ["Sell-through"] = "Tasa de venta",
  ["Sellers"] = "Vendedores",
  ["Sells too rarely: you would be holding it for a long time."] =
    "Se vende demasiado poco: te lo quedarías mucho tiempo.",
  ["Set cost"] = "Coste",
  ["Settings"] = "Ajustes",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Omitir una compra si no deja al menos esta cantidad tras la comisión de la Casa de Subastas.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Omitir una compra si el beneficio no es al menos esta parte de lo que pagas.",
  ["Snapshot value"] = "Valor del snapshot",
  ["Sold per day"] = "Ventas por día",
  ["Sold/day"] = "Ventas/día",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Ordena por él para decidir qué comprobar primero, no qué comprar.",
  ["Sound on SAFE deal"] = "Sonido en oferta SAFE",
  ["Source"] = "Fuente",
  ["Source age"] = "Antigüedad de la fuente",
  ["Spike-trend threshold %"] = "Umbral de subida repentina %",
  ["Start scanning as soon as the auction house opens."] =
    "Empezar a escanear en cuanto se abra la Casa de Subastas.",
  ["Status"] = "Estado",
  ["Stop and open the buy window on your price"] = "Detener y abrir la ventana de compra a tu precio",
  ["Stress exit unit"] = "Precio de salida bajo presión",
  ["Stress profit"] = "Beneficio bajo presión",
  ["THE BOOK"] = "EL LIBRO DE ÓRDENES",
  ["TREND"] = "TENDENCIA",
  ["Tell GoldCap what you actually paid for these units."] =
    "Dile a GoldCap lo que pagaste realmente por estas unidades.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "La casa de subastas no dio un depósito, así que el coste es desconocido.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "El Companion está sincronizando, pero este addon no pudo leer lo que escribió:",
  ["The auction house did not answer. Try again"] =
    "La casa de subastas no respondió. Inténtalo otra vez",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "El tablero lo clasificó con el snapshot importado. El libro en vivo no lo respalda.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "El botón espera un momento antes de poder pulsarse, así que nunca basta con un doble clic accidental.",
  ["The cancel did not go through: the lot is still listed"] = "La cancelación no se completó: el lote sigue publicado",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "El anuncio más barato ya no está lo bastante por debajo del precio de referencia.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "El precio más barato que pide AHORA OTRA persona, según una consulta en vivo a la casa de subastas. Tus propias publicaciones quedan excluidas, así que el número nunca se persigue a sí mismo hacia abajo.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Los datos de este objeto están mal formados, así que GoldCap no va a adivinar.",
  ["The liquidity data is not reliable enough to act on."] =
    "Los datos de liquidez no son lo bastante fiables para actuar.",
  ["The market value is an estimate, not a measurement."] =
    "El valor de mercado es una estimación, no una medición.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Lo máximo que puede llevarse una compra. La velocidad a la que se vende el objeto aún puede reducirlo.",
  ["The price data is over three hours old. Sync the Companion, then /reload. The addon only reads its data when the UI loads."] =
    "Los datos de precios tienen más de tres horas. Sincroniza el Companion y haz /reload: el addon solo lee sus datos al cargar la interfaz.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "El precio está comprobado. La rapidez de venta no se mide en ningún sitio, así que la valoras tú.",
  ["The price is falling; buying into it is how you get stuck."] =
    "El precio está cayendo; entrar ahí es como te quedas atrapado.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "El precio es la última cotización, de 45 segundos de antigüedad como mucho. Si cambia antes de confirmar, la publicación se abandona en lugar de enviarse al precio viejo.",
  ["The price moved: part of this quote may be above your price"] =
    "El precio ha cambiado: parte de esta cotización puede estar por encima de tu precio",
  ["The price moved and the trade is no longer safe."] =
    "El precio se movió y la operación ya no es segura.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "El beneficio no llega a tu mínimo una vez pagados el 5 % de comisión y el depósito.",
  ["What this buy would make is under your minimum profit."] =
    "Lo que esta compra generaría está por debajo de tu beneficio mínimo.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "No se puede deshacer. El primer clic pide un segundo para confirmar.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Es un objeto de reino, y GoldCap solo verifica precios de mercancías.",
  ["Too few sellers to read a real price."] = "Hay muy pocos vendedores para leer un precio real.",
  ["Too little of what is listed actually sells."] = "Se vende muy poco de lo que hay publicado.",
  ["Too little price history to trust the value."] =
    "Hay muy poco historial de precios para fiarse del valor.",
  ["Total cost to buy this auction"] = "Coste total de comprar esta subasta",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Escribe un precio en oro, o vacía el campo para usar el de GoldCap",
  ["UNDERCUT"] = "REBAJAR",
  ["UNDERCUT %d"] = "SUPERADOS %d",
  ["UNIT"] = "UNIDAD",
  ["Unit price"] = "Precio por unidad",
  ["Unknown"] = "Desconocido",
  ["Unknown item"] = "Objeto desconocido",
  ["Unknown means the cost side is incomplete. Fill it in with Set cost."] =
    "Desconocido significa que falta parte del coste: complétalo con Fijar coste.",
  ["VERDICT"] = "VEREDICTO",
  ["Verdict"] = "Veredicto",
  ["WAITING FOR THE AUCTION HOUSE %d"] = "ESPERANDO A LA CASA DE SUBASTAS %d",
  ["WATCH"] = "VIGILAR",
  ["WATCH (computed SAFE)"] = "WATCH (calculado SEGURO)",
  ["WATCH = the live check refused it. Hover the row for the reason"] =
    "VIGILAR = la comprobación en vivo lo rechazó. Pasa el ratón por la fila para ver el motivo",
  ["WHAT COUNTS AS A DEAL"] = "QUÉ CUENTA COMO OFERTA",
  ["WHAT TO DO"] = "QUÉ HACER",
  ["WHAT YOU PAID"] = "LO QUE PAGASTE",
  ["WHEN"] = "CUÁNDO",
  ["Waiting for Auction House…"] = "Esperando a la casa de subastas…",
  ["Waiting for a live price"] = "Esperando un precio en vivo",
  ["Waiting for the Auction House…"] = "Esperando a la casa de subastas…",
  ["Waiting for the purchase to finish…"] = "Esperando a que termine la compra…",
  ["Wall absorb window (hours)"] = "Ventana de absorción del muro (horas)",
  ["Watching closely: %d item%s"] = "Vigilando de cerca: %d objeto%s",
  ["Watching: pinned, but not a deal right now"] =
    "Vigilando: fijado, pero ahora mismo no es una oportunidad",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Lo que realmente te costó una unidad, promediado sobre las compras que aún tienes.",
  ["What to do"] = "Qué hacer",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Lo que te queda de una unidad si se vende al precio de mercado: precio de venta, menos el 5 % de comisión, menos tu coste.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Lo que suman tus subastas activas de este objeto a su precio actual.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Cuando un lote alcanza un precio que fijaste en el sitio web, se detiene el escaneo y se abre su ventana de compra.",
  ["Window position & size"] = "Posición y tamaño de la ventana",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "Con él, los precios de tu reino se actualizan solos y tus ventas y beneficios llegan a goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date, so deals get hunted with old prices."] =
    "Sin él, GoldCap funciona con precios congelados en la fecha de lanzamiento. Las oportunidades se buscan con precios viejos.",
  ["Won't buy"] = "No compraré",
  ["Worst case back"] = "Retorno en el peor caso",
  ["YOUR LOTS"] = "TUS LOTES",
  ["YOUR PRICE"] = "TU PRECIO",
  ["You can pay for it now."] = "Ya puedes pagarlo.",
  ["You paid"] = "Pagaste",
  ["You pay"] = "Pagas",
  ["You would get"] = "Recibirías",
  ["You would pay"] = "Pagarías",
  ["Your call"] = "Tú decides",
  ["Your cap"] = "Tu tope",
  ["Your gold has not grown lately, so there is no pace to estimate."] =
    "Tu oro no ha crecido últimamente, así que no hay ritmo que estimar.",
  ["Your minimum"] = "Tu mínimo",
  ["Your price"] = "Tu precio",
  ["a purchase landed that GoldCap could not attribute"] = "llegó una compra que GoldCap no pudo asignar",
  ["a purchase landed that GoldCap could not price"] = "llegó una compra cuyo precio GoldCap no conoce",
  ["a unit, at or under your price of %s"] = "por unidad, a tu precio de %s o por debajo",
  ["a vendor sells it"] = "lo vende un vendedor",
  ["a vendor sells it for %s each"] = "un vendedor lo vende a %s c/u",
  ["a vendor sells it for %s each · the auction house asks %s"] = "un vendedor lo vende a %s c/u · la casa de subastas pide %s",
  ["alert group · %d hits"] = "grupo de alertas · %d hallazgos",
  ["already in your bags and bank"] = "ya en tus bolsas y el banco",
  ["another purchase is in flight"] = "hay otra compra en curso",
  ["at a vendor"] = "en vendedor",
  ["at a vendor · %s each"] = "en vendedor · %s c/u",
  ["at level %d"] = "a nivel %d",
  ["bought"] = "comprado",
  ["bought %d for %s"] = "%d comprados por %s",
  ["buy %d of %d"] = "comprar %d de %d",
  ["buy %d of %d, have %d in bags and bank"] = "comprar %d de %d, tienes %d en bolsas y banco",
  ["buying..."] = "comprando...",
  ["cap: alert target"] = "tope: objetivo de la alerta",
  ["cheapest seen %s"] = "lo más barato visto: %s",
  ["confirming..."] = "confirmando...",
  ["craft"] = "fabricar",
  ["craft it for %s each"] = "fabrícalo por %s c/u",
  ["craft it for %s each · %s here"] = "fabrícalo por %s c/u · aquí %s",
  ["craft it yourself"] = "fabrícalo tú",
  ["craft it · %s each"] = "fabricar · %s c/u",
  ["craft it: %s = %s each"] = "fabricar: %s = %s c/u",
  ["deals %s · items %s · filtered %s"] = "oportunidades %s · objetos %s · descartadas %s",
  ["done"] = "hecho",
  ["from %s"] = "de %s",
  ["in bags %d · in bank %d"] = "en bolsas %d · en banco %d",
  ["includes %d for crafting %s"] = "incluye %d para fabricar %s",
  ["no answer. Check your mail"] = "sin respuesta. Revisa el correo",
  ["nothing at or under your cap of %s"] = "nada a tu tope de %s o menos",
  ["nothing on offer"] = "nada a la venta",
  ["on %s"] = "en %s",
  ["over your cap"] = "sobre tu tope",
  ["over your cap · %s"] = "sobre tu tope · %s",
  ["plan updated on goldcap.gg"] = "plan actualizado en goldcap.gg",
  ["price moved to %s"] = "el precio pasó a %s",
  ["purchase failed. Try again"] = "la compra falló. Inténtalo de nuevo",
  ["right-click to skip or change the cap"] = "clic derecho para omitir o cambiar el tope",
  ["seen %s ago"] = "visto hace %s",
  ["skipped for now"] = "omitido por ahora",
  ["skipped for this session, it stays on the list"] = "omitido en esta sesión, sigue en la lista",
  ["still on the list: %d at a vendor · %d to craft"] = "aún en la lista: %d en vendedor · %d por fabricar",
  ["sure profit: a vendor pays %s each"] =
    "beneficio seguro: un vendedor paga %s por unidad",
  ["resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown"] =
    "reventa al valor de subasta del escaneo, %s c/u, menos 5%% y depósito; velocidad incierta",
  ["Checked against the live auction house a moment ago."] =
    "Comprobado con la casa de subastas en vivo hace un momento.",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "por encima del más barato, dentro del cuarto barato · %s unidades por delante",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "por encima del más barato, dentro del alcance del día · %s unidades por delante",
  ["against the region's own price for this item, after the 5% cut, if it sells"] =
    "frente al precio de la región para este objeto, tras la comisión del 5%, si se vende",
  ["age %ss"] = "hace %ss",
  ["another purchase took over: nothing was confirmed"] =
    "otra compra ha tomado el relevo: no se ha confirmado nada",
  ["any figure here would be invented out of the very number being refused"] =
    "cualquier cifra aquí saldría inventada del mismo número que se está rechazando",
  ["at or under your price. Click Buy to purchase"] =
    "a tu precio o por debajo. Pulsa Buy para comprar",
  ["auto off"] = "auto desactivado",
  ["auto-synced %dh ago"] = "sincronizado automáticamente hace %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "datos sincronizados de %s cargados (%s de antigüedad)",
  ["auto-synced data stale: /goldcap import"] =
    "los datos sincronizados están caducados: /goldcap import",
  ["auto: paused"] = "auto: en pausa",
  ["below the %s you paid"] = "por debajo de los %s que pagaste",
  ["big buy"] = "compra grande",
  ["bought %d x item %d"] = "comprados %d x objeto %d",
  ["bought %d x item %d after AH close"] =
    "comprados %d x objeto %d tras cerrar la casa de subastas",
  ["buying commodity..."] = "comprando mercancía...",
  ["cheapest not yours %s"] = "el más barato que no es tuyo %s",
  ["checking live price..."] = "comprobando el precio en vivo...",
  ["checking live safety..."] = "comprobando la seguridad en vivo...",
  ["clears in ~%dd"] = "se vacía en ~%d d",
  ["clears in ~%dh"] = "se vacía en ~%d h",
  ["commodity purchase failed"] = "falló la compra de la mercancía",
  ["confirmed commodity purchase failed after AH close"] =
    "la compra confirmada de mercancía falló tras cerrar la casa de subastas",
  ["confirming purchase..."] = "confirmando la compra...",
  ["cost basis incomplete. Set costs to get repost advice"] =
    "la base de coste está incompleta. Define los costes para recibir consejo de republicación",
  ["crafted %s"] = "fabricado %s",
  ["due, will be asked next pass"] = "pendiente, se consultará en la próxima pasada",
  ["fair"] = "aceptables",
  ["far below market"] = "muy por debajo del mercado",
  ["finish the pending buy first"] = "termina primero la compra pendiente",
  ["first in line"] = "primero en la cola",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "Cuesta %s. Con tu límite por compra del %d%% necesitas %s en este personaje.",
  ["fresh"] = "reciente",
  ["full scan already in progress"] = "el escaneo completo ya está en marcha",
  ["full scan interrupted. Confirm your purchase"] =
    "escaneo completo interrumpido. Confirma tu compra",
  ["full scan stalled. Press Full Scan to retry"] =
    "el escaneo completo se ha atascado. Pulsa Full Scan para reintentar",
  ["full scan stalled, retrying shortly"] =
    "el escaneo completo se ha atascado, se reintentará en breve",
  ["full scan stopped. Press %s to run it again"] =
    "escaneo completo detenido. Pulsa %s para volver a lanzarlo",
  ["gone / price changed"] = "desaparecido / precio cambiado",
  ["goldcap.gg prices for WoW: Forever are not out yet."] =
    "Los precios de goldcap.gg para WoW: Forever aún no están disponibles.",
  ["strong"] = "sólidos",
  ["hold"] = "mantener",
  ["identity unresolved (variant item, not priced by design)"] =
    "identidad sin resolver (objeto con variantes, sin precio por diseño)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "si compras las %d y las revendes al precio que hay ahora mismo",
  ["ilvl %d"] = "nv. %d",
  ["import %dh old"] = "importación de hace %dh",
  ["import stale: /goldcap import or /goldcap companion"] =
    "importación caducada: /goldcap import o /goldcap companion",
  ["imported %d items for %s (%s). Prices are live now."] =
    "importados %d objetos para %s (%s). Los precios ya están activos.",
  ["in the mail"] = "en el correo",
  ["in the mail, the bank or on another character"] = "en el correo, el banco o en otro personaje",
  ["is what this market absorbs. Past that you are buying stock you will sit on"] =
    "es lo que absorbe este mercado. Más allá compras existencias que se te quedarán",
  ["item %d"] = "objeto %d",
  ["item %d: %s"] = "objeto %d: %s",
  ["item level %d+"] = "nivel de objeto %d+",
  ["item variant unresolved"] = "variante del objeto sin resolver",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h: %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "últimas 24 h: %d ventas, %s bruto, %s de comisión, %d compras, %s gastados",
  ["last live price %s ago"] = "último precio en vivo, hace %s",
  ["leave these alone"] = "déjalos como están",
  ["level %d"] = "nivel %d",
  ["listing gone: already bought out or price changed"] =
    "la publicación ha desaparecido: ya la compraron o cambió el precio",
  ["listing gone: bought out or repriced"] = "la subasta ya no está: comprada o con otro precio",
  ["live safety confirmed. Click Buy to purchase"] =
    "seguridad confirmada en vivo. Pulsa Buy para comprar",
  ["live verification required"] = "se requiere verificación en vivo",
  ["the cheapest is %s, your cap is %s"] = "lo más barato: %s, tu tope: %s",
  ["the run changed. Start again"] = "la lista cambió. Empieza de nuevo",
  ["took too long. Try again"] = "tardó demasiado. Inténtalo de nuevo",
  ["usually cheapest around %s · %d%%"] = "suele estar más barato hacia las %s · %d%%",
  ["vendor"] = "vendedor",
  ["vs %s at the auction house · right-click to buy it whole"] = "frente a %s en la casa de subastas · clic derecho para comprarlo entero",
  ["vs %s at the auction house · right-click to split"] = "frente a %s en la casa de subastas · clic derecho para dividirlo",
  ["weak"] = "escasos",
  ["manual import. Companion keeps this fresh: /goldcap companion"] =
    "importación manual. Companion lo mantiene al día: /goldcap companion",
  ["market %s"] = "mercado %s",
  ["needs %s"] = "exige %s",
  ["needs a fresh price. Press Refresh"] = "necesita un precio nuevo. Pulsa Refresh",
  ["no confirmation from the server. The buy may still have gone through, check your mail. Closing this will not undo it."] =
    "sin confirmación del servidor. La compra puede haberse completado igualmente, revisa tu correo. Cerrar esto no la deshará.",
  ["no cost"] = "sin coste",
  ["no cost for %d"] = "sin coste para %d",
  ["no live price yet"] = "aún sin precio en vivo",
  ["no live price"] = "sin precio en vivo",
  ["no live quote yet, pricing…"] = "aún sin cotización en vivo, calculando el precio…",
  ["no market figure for caged pets"] = "sin cifra de mercado para mascotas enjauladas",
  ["no market figure for this item level"] = "sin cifra de mercado para este nivel de objeto",
  ["no prices yet: /goldcap companion or /goldcap import"] =
    "todavía no hay precios: /goldcap companion o /goldcap import",
  ["no purchase confirmation received. Cancel and retry"] =
    "no se recibió confirmación de compra. Pulsa Cancel y reinténtalo",
  ["no sales recorded yet. Open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "aún no hay ventas registradas. Abre el buzón con GoldCap cargado y se leerán de las facturas",
  ["no stock in bags or listed, nothing to price for"] =
    "sin existencias en bolsas ni publicadas, nada que cotizar",
  ["none"] = "ninguno",
  ["not enough gold: total %s, you have %s"] = "no hay oro suficiente: total %s, tienes %s",
  ["not enough gold for this quote. Cancel"] =
    "no hay oro suficiente para esta cotización. Cancel",
  ["not enough gold on this character: you need %s"] = "no hay oro suficiente en este personaje: necesitas %s",
  ["not enough units left for that quantity, re-checking what remains..."] =
    "no quedan suficientes unidades para esa cantidad, comprobando de nuevo lo que queda...",
  ["not priced: nothing on hand to sell"] = "sin precio: nada a mano para vender",
  ["not ready to cancel"] = "aún no se puede cancelar",
  ["not ready to post"] = "aún no se puede publicar",
  ["nothing listed"] = "nada publicado",
  ["of %d"] = "de %d",
  ["off"] = "desactivado",
  ["oldest units sell first"] = "las unidades más antiguas se venden primero",
  ["on"] = "activado",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "abre la casa de subastas una vez para que GoldCap sepa cómo se venden",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "o pega una cadena de goldcap.gg con /goldcap import.",
  ["paid sale unresolved"] = "venta cobrada sin resolver",
  ["placing bid..."] = "pujando...",
  ["previous commodity purchase settled. %s to re-check the price"] =
    "compra de mercancía anterior liquidada. Pulsa %s para volver a comprobar el precio",
  ["price changed after you closed the buy window: nothing was bought"] =
    "el precio cambió después de cerrar la ventana de compra: no se ha comprado nada",
  ["price checked, sale speed unknown. This one is your call"] =
    "precio comprobado, velocidad de venta desconocida. Esta la decides tú",
  ["price confirmed. Click Buy to purchase"] = "precio confirmado. Pulsa Buy para comprar",
  ["price rose %.1fx, still safe. Confirm"] = "el precio subió %.1fx, sigue siendo seguro. Confirma",
  ["price stands %d of %d"] = "tu precio: %d de %d",
  ["prices loaded are %s (%s) but you are playing in %s, so every discount and profit figure is measured against another market"] =
    "los precios cargados son de %s (%s) pero juegas en %s, cada descuento y beneficio se mide contra otro mercado",
  ["purchase canceled"] = "compra cancelada",
  ["purchase complete"] = "compra completada",
  ["purchase identity unresolved"] = "identidad de la compra sin resolver",
  ["purchase pending exact cost"] = "compra pendiente del coste exacto",
  ["purchase total unavailable. Check your mail"] =
    "no se puede obtener el total de la compra. Revisa el buzón",
  ["quote %s. Click Confirm to buy"] = "cotización %s. Pulsa Confirm para comprar",
  ["quote %ss ago"] = "cotización de hace %ss",
  ["quote expired. Refresh to re-check the price"] =
    "cotización caducada. Pulsa Refresh para volver a comprobar el precio",
  ["quote expires in %d s. Click Confirm to buy"] =
    "la cotización caduca en %d s. Pulsa Confirm para comprar",
  ["re-checking what remains at a safe price..."] =
    "comprobando de nuevo lo que queda a un precio seguro...",
  ["realm item, sale speed unverified · region reference %s (ilvl %d)"] =
    "objeto de reino, velocidad de venta sin verificar · referencia de región %s (nivel %d)",
  ["recent sales (newest first):"] = "ventas recientes (las más nuevas primero):",
  ["region %s · bundled: %d items (%s), imported: %s"] =
    "región %s · incluidos: %d objetos (%s), importados: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "región corregida en %d registros; %d ventas emparejadas de nuevo con su stock",
  ["relisting now would lock in a loss or a stall. Hold"] =
    "republicar ahora fijaría una pérdida o un estancamiento. Espera",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "borrados %d registros de compra duplicados que dejó un fallo al leer el correo",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "borrados %d registros de venta duplicados que dejó un fallo al leer el correo",
  ["sale name ambiguous"] = "nombre de la venta ambiguo",
  ["sale proceeds pending"] = "ingresos de la venta pendientes",
  ["scanned %d listings over %d passes"] = "escaneadas %d publicaciones en %d pasadas",
  ["scanning auction house..."] = "escaneando la casa de subastas...",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "vende %s/día",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "sesión: %d capturas, %s gastados, ~%s de beneficio est.",
  ["sniped (listing changed on rescan)"] = "se lo llevaron (la publicación cambió al reescanear)",
  ["sniped for "] = "cazado por ",
  ["stack not identified"] = "montón sin identificar",
  ["starting full scan..."] = "iniciando el escaneo completo...",
  ["stopped watching %s"] = "se dejó de vigilar %s",
  ["the Companion wrote prices this addon could not read:"] =
    "el Companion escribió precios que este addon no pudo leer:",
  ["the auction house has not sent details for these yet"] =
    "la casa de subastas aún no ha enviado sus detalles",
  ["the import failed (%s)"] = "la importación falló (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "para colocar %d unidades a %s ventas al día, con %s inmovilizado todo ese tiempo",
  ["unavailable"] = "no disponible",
  ["under GoldCap's own floor of %s"] = "por debajo del mínimo de GoldCap, %s",
  ["unknown evidence"] = "evidencia desconocida",
  ["waiting for previous commodity purchase to settle"] =
    "esperando a que se liquide la compra de mercancía anterior",
  ["waiting for previous search result to settle"] =
    "esperando el resultado de la búsqueda anterior",
  ["waiting..."] = "en espera…",
  ["wall"] = "muro",
  ["wall %s at %s: price under it to sell first"] =
    "muro de %s a %s: pon el precio por debajo para vender antes",
  ["wall %s at %s above you"] = "muro de %s a %s por encima de ti",
  ["watching %s closely, re-checked every few seconds"] =
    "vigilando %s de cerca, se recomprueba cada pocos segundos",
  ["worst case, selling all %d back into the price standing there now"] =
    "en el peor caso, revendiendo las %d al precio que hay ahora mismo",
  ["worth cancelling"] = "conviene cancelar",
  ["would sell at a loss"] = "se vendería con pérdidas",
  ["you have enough gold for this now. Check again"] = "ya tienes oro suficiente. Pulsa Check para comprobar de nuevo",
  ["you haven't imported realm prices yet. Install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "aún no has importado los precios del reino. Instala GoldCap Companion (/goldcap companion) o pega una cadena de goldcap.gg (/goldcap import).",
  ["you take %d"] = "te llevas %d",
  ["your game client has no font for this language, so the text will show as empty boxes"] =
    "tu cliente del juego no tiene fuente para este idioma, el texto se verá como cuadros vacíos",
  ["your import is %d hours old and prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "tu importación tiene %d horas. Los precios pueden estar desviados. Pega una cadena nueva de goldcap.gg (/goldcap import).",
  ["your price is above every level shown"] = "tu precio supera todos los niveles",
  ["your scan, %s ago"] = "tu escaneo, hace %s",
  ["yours"] = "tuyo",
  ["yours ×%s"] = "tuyo ×%s",
  ["~%dd to reach you"] = "~%d d hasta tu turno",
  ["~%dh to reach you"] = "~%d h hasta tu turno",
  ["×%d in bags"] = "×%d en bolsas",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d en tus bolsas · Post publica %d de ellos, el montón más grande",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d en tus bolsas · ningún montón que GoldCap pueda identificar con exactitud",
  ["×%d in your bags, ready to list"] = "×%d en tus bolsas, listos para publicar",
  ["×%d listed"] = "×%d publicados",
  ["×%d listed at %s each"] = "×%d publicados a %s cada uno",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · comprado %s · %s · %s",
  ["×%d%s · made %s · %s"] = "×%d%s · fabricado %s · %s",
  ["- = nothing is checking this row right now"] =
    "- = nada está comprobando esta fila ahora mismo",
  ["… = a live check is queued for this row"] =
    "… = hay una comprobación en vivo en cola para esta fila",
  ["no answer %ds ago, resting"] = "sin respuesta hace %ds, en pausa",
  ["the last attempt is still settling, checking the price again..."] =
    "el último intento aún se está cerrando, comprobando el precio de nuevo...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "Publicado a tu precio de goldcap.gg o por debajo (grupo: %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "AUTO · EN PAUSA: VENTANA DE COMPRA",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "En pausa mientras hay una ventana de compra abierta. Compra o ciérrala y Auto sigue.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "AUTO · EN PAUSA: TU BÚSQUEDA",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "En pausa mientras escribes en la búsqueda de la casa de subastas. Sigue unos segundos después de que la dejes.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "AUTO · EN PAUSA: BUZÓN ABIERTO",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "En pausa mientras el buzón está abierto. Ciérralo y Auto sigue.",
  ["AUTO · PAUSED: SELL TAB"] = "AUTO · EN PAUSA: PESTAÑA VENDER",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "En pausa mientras la pestaña Vender está abierta: pone precio a tus bolsas con la misma búsqueda. Vuelve a Ofertas y Auto sigue.",
  ["AUTO · PAUSED: ITEMS BOARD"] = "AUTO · EN PAUSA: LISTA DE OBJETOS",
  ["Paused while the Items board is shown: it asks the auction house through the same search. Switch to Commodities and Auto carries on."] =
    "En pausa mientras se muestra la lista de objetos: consulta la casa de subastas con la misma búsqueda. Cambia a Materiales y Auto sigue.",
  ["AUTO · PAUSED: BUY TAB"] = "AUTO · EN PAUSA: PESTAÑA BUY",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "En pausa mientras la pestaña BUY está abierta: consulta precios con la misma búsqueda. Vuelve a Ofertas y Auto sigue.",
  ["AUTO · WAITING FOR YOU"] = "AUTO · TE ESPERA",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "Espera mientras publicas, compras o exploras en los paneles de la casa de subastas. Empieza en cuanto paras.",
  ["AUTO · WAITING: YOUR LIST"] = "AUTO · ESPERA: TU LISTA",
  ["Waiting: your own search is on the auction house's Buy list, and a scan would replace it. Open GoldCap's auction house tab, or close the auction house, and Auto starts."] =
    "Espera: tu propia búsqueda está en la lista de compra de la casa de subastas y un escaneo la sustituiría. Abre la pestaña de GoldCap en la casa de subastas, o ciérrala, y Auto empieza.",
  ["Market %s · unverified until a live Check"] =
    "Mercado %s · sin verificar hasta una comprobación en vivo",
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "datos de todo el mercado: %d materiales, %d con datos de ventas, %d objetos del reino (antigüedad %s, %d KB)",
  ["whole-market data not in use: %s"] = "datos de todo el mercado sin usar: %s",
  ["it is %s old, and the prices you imported are newer"] =
    "tienen %s de antigüedad y los precios que importaste son más recientes",
  ["it is for another region than the prices loaded"] = "son de otra región distinta a la de los precios cargados",
  ["its date cannot be right. Check this computer's clock"] =
    "su fecha no puede ser correcta. Revisa el reloj de este ordenador",
  ["it was set aside when other prices were loaded this session. /reload to use it again"] =
    "se apartaron cuando se cargaron otros precios en esta sesión. /reload para volver a usarlos",
  ["On the AH now"] = "En subasta",
  ["%s listed · %d min ago"] = "%s publicados · hace %d min",
  ["%s listed · just now"] = "%s publicados · ahora mismo",
  ["it could not be read (%s)"] = "no se pudieron leer (%s)",
  ["it is for a region this build of GoldCap does not know. Update the addon"] =
    "son de una región que esta versión de GoldCap no conoce. Actualiza el addon",
  ["it is in a format this build of GoldCap cannot read. Update the addon"] =
    "tienen un formato que esta versión de GoldCap no puede leer. Actualiza el addon",
  ["it is larger than this build of GoldCap can read. Update the addon"] =
    "son más grandes de lo que esta versión de GoldCap puede leer. Actualiza el addon",
  ["the Companion wrote an empty copy. Let it sync, then /reload"] =
    "el Companion los guardó vacíos. Deja que sincronice y haz /reload",
  ["the Companion wrote it with no prices. Let it sync, then /reload"] =
    "el Companion los guardó sin precios. Deja que sincronice y haz /reload",
  ["Scanning the auction house…"] = "Escaneando la casa de subastas…",
  ["%s lots scanned and saved"] = "%s lotes escaneados y guardados",
  ["%s items scanned and saved"] = "%s objetos escaneados y guardados",
  ["The full scan is cooling down (%d min left). Scanning by browsing instead"] =
    "El escaneo completo está en tiempo de espera (%d min restantes). Escaneando por búsqueda mientras tanto",
  ["The auction house did not answer the full scan. Scanning by browsing instead"] =
    "La casa de subastas no respondió al escaneo completo. Escaneando por búsqueda en su lugar",
  ["reading the auction house: %s of %s lots"] = "leyendo la casa de subastas: %s de %s lotes",
  ["The scan found nothing to save"] = "El escaneo no encontró nada que guardar",
  ["Scans the whole auction house for prices: a full list at most once every 15 minutes, browsing in between. GoldCap also scans when you open the auction house."] =
    "Escanea toda la casa de subastas en busca de precios: una lista completa como máximo cada 15 minutos, buscando mientras tanto. GoldCap también escanea cuando abres la casa de subastas.",
  -- Core/ForeverValue.lua's PrintBags/BagTotals and Core/PostQueue.lua's below_vendor: the
  -- POST queue holding back what a vendor pays at least as much for.
  ["Your bags: %s at a vendor, %s on the AH after its cut"] =
    "Tus bolsas: %s al vendedor, %s en la CdS tras su comisión",
  ["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."] =
    "El botón PUBLICAR de la pestaña Vender lista todo lo que vale más de lo que paga un vendedor, un clic cada vez.",
  ["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."] =
    "Tus bolsas: %s al vendedor. Escanea la casa de subastas para ver cuánto darían allí.",
  ["a vendor pays more: sell it there"] =
    "un vendedor paga más: véndelo ahí",
  ["vendor pays more"] =
    "el vendedor paga más",
  ["Below vendor"] =
    "Bajo NPC",
  ["Under market"] =
    "Bajo mercado",
  [" · buy at %s or less, vendor pays %s"] =
    " · compra a %s o menos, el vendedor paga %s",
  [" · buy at %s or less, AH value %s"] =
    " · compra a %s o menos, valor de subasta %s",
  ["Buy at or under %s: a vendor pays %s each. This buy makes %s."] =
    "Compra a %s o menos: un vendedor paga %s por unidad. Esta compra genera %s.",
  ["Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit."] =
    "Compra a %s o menos: el valor de subasta, lo que pide la décima parte más barata de las unidades listadas, es %s. Se desconoce la velocidad de reventa, así que esto es más arriesgado que un trato con el vendedor. Esta compra genera unos %s tras la comisión del 5%% y el depósito.",
  ["under the vendor price. Click Buy to purchase"] =
    "por debajo del precio del vendedor. Pulsa Buy para comprar",
  ["far under the market, resale speed unknown. Click Buy to purchase"] =
    "muy por debajo del mercado, velocidad de reventa desconocida. Pulsa Buy para comprar",
  ["No deals in your last scan."] =
    "Sin ofertas en tu último escaneo.",
  ["Deals appear as soon as the scan finds them."] =
    "Las ofertas aparecen en cuanto el escaneo las encuentre.",
  ["GoldCap looks for items listed cheaper than they are worth. SCAN looks again."] =
    "GoldCap busca objetos listados por menos de lo que valen. ESCANEAR vuelve a escanear.",
  ["No scan of this auction house yet."] =
    "Aún no hay ningún escaneo de esta casa de subastas.",
  ["GoldCap scans when you open the auction house; SCAN on this board scans again."] =
    "GoldCap escanea cuando abres la casa de subastas; ESCANEAR en este panel escanea otra vez.",
  ["In WoW: Forever, GoldCap's prices come from your own auction house scans."] =
    "En WoW: Forever, los precios de GoldCap vienen de tus propios escaneos de la casa de subastas.",
  ["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."] =
    "Abre la casa de subastas y GoldCap la escanea por ti; ESCANEAR en la pestaña Ofertas escanea otra vez.",
  ["%ds"] = "%d s",
  ["%dm"] = "%d min",
  ["%dh"] = "%d h",
  ["%dd"] = "%d d",
  -- WoW: Forever crowd prices (UI/Tooltip.lua, plan 3d).
  ["1 scanner, %s ago"] = "1 escáner, hace %s",
  ["%d scanners, %s ago"] = "%d escáneres, hace %s",
  ["resale at the AH value of players' scans, %s each, after the 5%% cut and deposit; speed unknown"] = "reventa al valor de subasta de los escaneos de jugadores, %s c/u, menos 5%% y depósito; velocidad incierta",
  ["Shared with goldcap.gg on your next /reload"] = "Se compartirá con goldcap.gg en tu próximo /reload",
  ["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."] = "Tus escaneos se quedan en este ordenador. El GoldCap Companion los comparte con goldcap.gg y trae de vuelta los precios de todos.",
  ["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."] = "El GoldCap Companion comparte tus escaneos con goldcap.gg después de cada /reload y trae de vuelta los precios de todos.",
  ["You opened %s: its first %s prices are yours."] =
    "Has abierto %s: sus primeros %s precios son tuyos.",
  ["Your scan updated %s prices on %s. %s of them nobody else had in the last 24 hours."] =
    "Tu escaneo ha actualizado %s precios en %s. %s de ellos no los tenía nadie más en las últimas 24 horas.",
  ["Your scan updated %s prices on %s."] =
    "Tu escaneo ha actualizado %s precios en %s.",
  -- Sold tab: tiles, period chips, search, day groups and the sale tooltip.
  ["%d DAYS"] = "%d DÍAS",
  ["TODAY"] = "HOY",
  ["YESTERDAY"] = "AYER",
  ["SUN"] = "DOM",
  ["MON"] = "LUN",
  ["TUE"] = "MAR",
  ["WED"] = "MIÉ",
  ["THU"] = "JUE",
  ["FRI"] = "VIE",
  ["SAT"] = "SÁB",
  ["YOU GOT"] = "RECIBIDO",
  ["YOU GOT · %s"] = "RECIBIDO · %s",
  ["EACH"] = "UNIDAD",
  ["%d sales · after the AH cut"] = "%d ventas · tras la comisión",
  ["1 sale · after the AH cut"] = "1 venta · tras la comisión",
  ["%d here · all on goldcap.gg"] = "%d aquí · todas en goldcap.gg",
  ["cost known for %d of %d"] = "coste conocido en %d de %d",
  ["%s of %s"] = "%s de %s",
  ["%s · gold %s, bags %s"] = "%s · oro %s, bolsas %s",
  ["set the riding cost: %s"] = "define el coste de la montura: %s",
  ["GOLDCAP.GG · %d DAYS"] = "GOLDCAP.GG · %d DÍAS",
  ["profit · synced %s ago"] = "beneficio · sinc. hace %s",
  ["after the AH cut · synced %s ago"] = "tras la comisión · sinc. hace %s",
  ["BEST SALE"] = "MEJOR VENTA",
  ["%s profit"] = "%s de beneficio",
  ["no sale with a known profit yet"] = "aún no hay ventas con beneficio conocido",
  ["OPEN SELL"] = "ABRIR SELL",
  ["Find an item"] = "Buscar un objeto",
  ["JUST SOLD"] = "RECIÉN VENDIDO",
  ["reaches goldcap.gg on /reload or logout"] = "llega a goldcap.gg con /reload o al cerrar sesión",
  ["ON GOLDCAP.GG"] = "EN GOLDCAP.GG",
  ["latest %d of %d · the rest on goldcap.gg"] = "últimas %d de %d · el resto en goldcap.gg",
  ["last %d days"] = "últimos %d días",
  ["%d sales · %s"] = "%d ventas · %s",
  ["1 sale · %s"] = "1 venta · %s",
  ["sold today at %s · %d × %s"] = "vendido hoy a las %s · %d × %s",
  ["sold %s at %s · %d × %s"] = "vendido el %s a las %s · %d × %s",
  ["sold, the money is in your mail · %d × %s"] = "vendido, el dinero está en tu correo · %d × %s",
  ["Sale price"] = "Precio de venta",
  ["Auction house cut"] = "Comisión de la CdS",
  ["Auction house cut, 5%"] = "Comisión de la CdS, 5 %",
  ["You got"] = "Recibiste",
  ["You paid (%s)"] = "Pagaste (%s)",
  ["Sniper"] = "Sniper",
  ["BUY list"] = "lista de BUY",
  ["set by you"] = "indicado por ti",
  ["the auction house"] = "la casa de subastas",
  ["crafted"] = "fabricado",
  ["The profit is worked out once the money arrives."] = "El beneficio se calcula cuando llegue el dinero.",
  ["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."] =
    "GoldCap nunca vio esta compra, así que no hay beneficio que mostrar. Indica lo que te costó en SELL.",
  ["Market now %s · you sold %d%% above it"] = "Mercado ahora %s · vendiste un %d%% por encima",
  ["Market now %s · you sold %d%% under it"] = "Mercado ahora %s · vendiste un %d%% por debajo",
  ["Market now %s · you sold at it"] = "Mercado ahora %s · vendiste al mismo precio",
  ["Your sales show up here once you open a mailbox with GoldCap loaded."] =
    "Tus ventas aparecerán aquí cuando abras un buzón con GoldCap cargado.",
  ["List something in SELL first."] = "Primero publica algo en SELL.",
  ["No sales match “%s” today."] = "Hoy ninguna venta coincide con «%s».",
  ["No sales match “%s” in these %d days."] = "Ninguna venta coincide con «%s» en estos %d días.",
  ["No sales today."] = "Hoy no hay ventas.",
  ["No sales in these %d days."] = "No hay ventas en estos %d días.",
  ["SEARCH 30 DAYS"] = "BUSCAR EN 30 DÍAS",
  ["SHOW 30 DAYS"] = "VER 30 DÍAS",
  ["▲%d%% over the alert target"] = "▲%d%% sobre el objetivo de la alerta",
  ["▲%d%% over usual"] = "▲%d%% sobre lo habitual",
  ["▲%d%% over your cap"] = "▲%d%% sobre tu tope",
  -- The quest reward mark (UI/QuestRewardMark.lua).
  ["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."] =
    "GoldCap: la recompensa del marco dorado es la que más vale en la casa de subastas (%s).",
  -- The vendor note (UI/MerchantNote.lua).
  ["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."] =
    "1 objeto de tus bolsas vale más en la casa de subastas (+%s). Guárdalo para la subasta.",
  ["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."] =
    "%d objetos de tus bolsas valen más en la casa de subastas (+%s). Guárdalos para la subasta.",
  -- BUY 2.0 week 2: a gear line is bought one lot per press (UI/BuyFrame.lua).
  ["BUY ONE · %s"] = "COMPRAR UNO · %s",
  ["not enough gold"] = "no hay oro suficiente",
  ["set a cap first"] = "primero fija un tope",
  -- BUY 2.0 week 2: a gear line's lots on the dock (UI/BuyFrame.lua).
  ["%s · %d lots"] = "%s · %d lotes",
  ["%s · 1 lot"] = "%s · 1 lote",
  ["%s · over your cap"] = "%s · por encima de tu tope",
  ["no cap for this item. Right-click the line to set one"] =
    "este objeto no tiene tope. Clic derecho en la línea para fijar uno",
  -- BUY 2.0 week 2: the vendor panel beside the merchant (UI/BuyVendorPanel.lua).
  ["BUY %d · %s"] = "COMPRAR %d · %s",
  ["BUY · %s"] = "COMPRAR · %s",
  -- BUY 2.0: the item box and the quick list (UI/BuyFrame.lua).
  ["Could not find that item. Shift-click it, or type its item id."] =
    "No se encontró ese objeto. Haz Mayús+clic en él o escribe su ID de objeto.",
  ["Item to add"] = "Objeto que añadir",
  ["Make a list once, buy it here at or under your price."] =
    "Haz una lista una vez y compra aquí a tu precio o por debajo.",
  ["Remove from the list"] = "Quitar de la lista",
  ["or plan a whole profession on goldcap.gg"] = "o planifica una profesión entera en goldcap.gg",
  -- BUY 2.0: the item box's hint, with the x count (UI/BuyFrame.lua).
  -- Glyphs every face that draws them has (spec/client_text_spec.lua's glyph inventory).
  ["HIDE DETAILS ▲"] = "OCULTAR DETALLES ▲",
  ["SHOW DETAILS ▼"] = "MOSTRAR DETALLES ▼",
  ["plan updated on goldcap.gg · +%d -%d lines"] =
    "plan actualizado en goldcap.gg · +%d -%d líneas",
  ["~ goldcap.gg market value, no live quote yet"] =
    "~ valor de mercado de goldcap.gg, aún sin cotización en vivo",
  ["• %s"] = "• %s",
  ["→ needs price"] = "→ falta precio",
  -- BUY 2.0: lists made in the game -- New, Import, Export, Rename, favourites, order, Delete
  ["Items the game has not loaded yet are left out: %d. Export again in a moment."] =
    "El juego aún no ha cargado %d objetos y se han dejado fuera. Vuelve a exportar en un momento.",
  ["%s and %d more"] = "%s y %d más",
  ["+ New"] = "+ Nueva",
  ["Add to favourites"] = "Añadir a favoritos",
  ["Added %d items to %s."] = "Añadidos %d objetos a %s.",
  ["Added %d× %s to %s."] = "Añadidos %d× %s a %s.",
  ["Added %d× %s to a new list, %s."] = "Añadidos %d× %s a una lista nueva: %s.",
  ["Copy as a TSM item list"] = "Copiar como lista de objetos de TSM",
  ["Copy for Auctionator"] = "Copiar para Auctionator",
  ["Delete"] = "Eliminar",
  ["Delete %s? This cannot be undone."] = "¿Eliminar %s? No se puede deshacer.",
  ["Delete this list…"] = "Eliminar esta lista…",
  ["Export"] = "Exportar",
  ["From goldcap.gg: rename or remove it there"] =
    "De goldcap.gg: cámbiale el nombre o quítala allí",
  ["GoldCap: Import a list"] = "GoldCap: Importar una lista",
  ["Import a list…"] = "Importar una lista…",
  ["Import into this list…"] = "Importar a esta lista…",
  ["Imported %s with %d items."] = "Importada %s con %d objetos.",
  ["List %d"] = "Lista %d",
  ["Lists come from goldcap.gg through the companion, or make one here with + New."] =
    "Las listas llegan de goldcap.gg a través del Companion, o crea una aquí con + Nueva.",
  ["Lists: click to switch, make, import or export one"] =
    "Listas: haz clic para cambiar, crear, importar o exportar una",
  ["Move down"] = "Bajar",
  ["Move up"] = "Subir",
  ["Name this list"] = "Nombre de la lista",
  ["New list"] = "Nueva lista",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import."] =
    "Pega una lista de goldcap.gg, TSM o Auctionator y pulsa Importar.",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."] =
    "Pega una lista de goldcap.gg, TSM o Auctionator y pulsa Importar. Sus objetos se añaden a %s.",
  ["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."] =
    "Pulsa Ctrl+C para copiarla y luego impórtala en la pestaña Compras de Auctionator.",
  ["Press Ctrl+C to copy, then import it into a TSM group."] =
    "Pulsa Ctrl+C para copiarla y luego impórtala en un grupo de TSM.",
  ["Remove from favourites"] = "Quitar de favoritos",
  ["Rename…"] = "Cambiar nombre…",
  ["Save"] = "Guardar",
  ["The game could not tell which items these are: %s. Shift-click them into the item box instead."] =
    "El juego no pudo saber qué objetos son estos: %s. Añádelos con Mayús+clic en la casilla de objetos.",
  ["There are no items in this list."] = "Esta lista no tiene objetos.",
  ["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."] =
    "Es la exportación comprimida de grupos de TSM, que solo TSM puede descomprimir. Pégala en goldcap.gg/list, pulsa allí «Copiar como grupo de TSM» y pega aquí el resultado.",
  ["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."] =
    "GoldCap no puede leer esto como una lista. Pega una lista de goldcap.gg, TSM o Auctionator.",
  ["in game"] = "en el juego",
  -- Buy runs: the import result and the vendor list, now that the BUY tab's lists use them.
  ["The run's vendor reagents. Press Ctrl+C to copy the list."] =
    "Los componentes de vendedor de la lista. Pulsa Ctrl+C para copiarla.",
  ["Vendor list"] = "Lista de vendedor",
  ["run imported: %s (%d lines)"] = "lista importada: %s (%d líneas)",
  ["the run string is not valid"] = "la cadena de la lista no es válida",
  -- BUY: a gear line's tooltip names the lot it buys next (UI/BuyFrame.lua).
  ["next to buy: %s"] = "siguiente compra: %s",
  -- BUY: the item box at the top -- several items at once, typed names, recents (UI/BuyAddBox.lua).
  ["Add"] = "Añadir",
  ["Added %d items to a new list, %s."] = "Añadidos %d objetos a una lista nueva: %s.",
  ["Clear"] = "Borrar",
  ["Could not read: %s."] = "No se pudo leer: %s.",
  ["Items to add: %d (%s)"] = "Por añadir: %d (%s)",
  ["Recent:"] = "Recientes:",
  ["Shift-click items, type a name, or an item id with x and a count: 2589 x20."] =
    "Haz Mayús+clic en objetos, escribe un nombre o un ID de objeto con x y la cantidad: 2589 x20.",
  -- BUY search: what is on sale, the results, opening one and adding it to a list (UI/BuySearch.lua).
  ["AVAILABLE"] = "DISPONIBLES",
  ["Add to list…"] = "Añadir a una lista…",
  ["Back to %s"] = "Volver a %s",
  ["Click to buy it here. Right-click to add it to a list."] =
    "Haz clic para comprarlo aquí. Clic derecho para añadirlo a una lista.",
  ["Close search"] = "Cerrar búsqueda",
  ["How many"] = "Cuántos",
  ["How many of %s?"] = "¿Cuántos de %s?",
  ["Loading more results…"] = "Cargando más resultados…",
  ["More results"] = "Más resultados",
  ["Nothing on sale for “%s”."] = "No hay nada a la venta para «%s».",
  ["On sale for “%s”: %d"] = "A la venta para «%s»: %d",
  ["Open the auction house to search what's on sale."] =
    "Abre la casa de subastas para buscar lo que está a la venta.",
  ["PRICE FROM"] = "PRECIO DESDE",
  ["Search again"] = "Buscar de nuevo",
  ["Searching the auction house for “%s”…"] = "Buscando «%s» en la casa de subastas…",
  ["The auction house did not answer. Search again."] =
    "La casa de subastas no respondió. Busca de nuevo.",
  ["Type a whole number."] = "Escribe un número entero.",
  ["Waiting for the auction house…"] = "Esperando a la casa de subastas…",
  -- Craft costs: which reagent had no price and why, and the merchant as a source of cost
  -- (Core/CraftCapture.lua, Core/VendorBuys.lua).
  ["this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed"] =
    "esta receta convierte un ingrediente en varios objetos distintos (prospección, trituración, molienda), así que no tiene coste",
  ["%s ×%d: no purchase of it found, here or on your other characters"] =
    "%s ×%d: no se encontró ninguna compra, ni aquí ni en tus otros personajes",
  ["%s ×%d: only %d of them were bought, the rest has no price"] =
    "%s ×%d: solo se compraron %d, el resto no tiene precio",
  ["%s ×%d: made by prospecting, crushing or milling, not bought"] =
    "%s ×%d: obtenido por prospección, trituración o molienda, no comprado",
  ["%s ×%d: bought as different variants, so which one was used is unclear"] =
    "%s ×%d: comprado en variantes distintas, así que no está claro cuál se usó",
  ["%s: %d at the vendor price, %s each"] =
    "%s: %d al precio del vendedor, %s cada uno",
  ["%s: priced from another character's purchases"] =
    "%s: valorado con las compras de otro personaje",
  ["%s: %d at the market price, %s each"] =
    "%s: %d al precio de mercado, %s cada uno",
  ["Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price"] =
    "Parte de este coste es una estimación: los reactivos que no compraste se cuentan a su precio actual en la casa de subastas",
  ["Vendor"] =
    "Vendedor",
  ["SELLING %d"] = "VENDO %d",
  ["NOT SELLING %d"] = "NO VENDO %d",
  ["POST lists these"] = "PUBLICAR los publica",
  ["click one to post it"] = "haz clic en uno para publicarlo",
  ["Selling"] = "Vendo",
  ["Not selling"] = "No vendo",
  ["POST lists it, and so does the key for posting the next item."] = "PUBLICAR lo publica, y también la tecla para publicar el siguiente objeto.",
  ["POST passes it by. Click the item to post it from the bar below."] = "PUBLICAR lo salta. Haz clic en el objeto para publicarlo desde la barra de abajo.",
  ["Marked for you: you bought it on DEALS."] = "Marcado automáticamente: lo compraste en DEALS.",
  ["Click to change."] = "Haz clic para cambiar.",
  ["Done for this visit"] = "Listo por esta visita",
  ["POST passes it by until you close the auction house. Click to have POST list it again."] =
    "PUBLICAR lo salta hasta que cierres la casa de subastas. Haz clic para que PUBLICAR vuelva a publicarlo.",
  ["Mark what to sell with the circle"] = "Marca con el círculo lo que quieres vender",
  ["PROCEEDS"] = "INGRESOS",
  ["What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut."] = "Lo que te deja todo lo que PUBLICAR publica si se vende a estos precios, tras el 5 % de comisión de la casa de subastas.",
  ["What your lots bring in if they all sell, after the auction house's 5% cut."] = "Lo que te dejan tus subastas si se venden todas, tras el 5 % de comisión de la casa de subastas.",
  ["PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it."] = "INGRESOS menos lo que pagaste por esta mercancía. Solo se muestra mientras GoldCap sabe lo que pagaste por toda ella.",
  ["HOW MANY"] = "CANTIDAD",
  ["MAX"] = "MÁX.",
  ["skipped"] = "omitido",
  ["posted"] = "publicado",
  ["POST"] = "PUBLICAR",
  ["SKIP"] = "OMITIR",
  ["then %s"] = "luego %s",
}
