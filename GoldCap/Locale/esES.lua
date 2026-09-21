local _, GC = ...

-- Spanish (Spain). Terminology follows apps/web/messages/es.json. Note "coste", which is the
-- peninsular form -- esMX uses "costo", and that is the main difference between the two files.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.esES = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s cada uno  (%s en total, %s de comisión)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion lo mantiene al día: /goldcap companion.",
  [" · %d hidden"] = " · %d ocultos",
  [" · %d keys"] = " · %d claves",
  [" · below cost"] = " · por debajo del coste",
  [" · identity unresolved"] = " · identidad sin resolver",
  [" · stale %ds"] = " · %ds de antigüedad",
  [" — Check again"] = " — comprueba de nuevo",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — comandos: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (o /gc para abreviar)",
  ["%d (whole lot)"] = "%d (lote completo)",
  ["%d days"] = "%d días",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d oportunidades del último escaneo -- pulsa Full Scan para actualizar",
  ["%d filtered out as hard to resell"] = "%d descartadas por ser difíciles de revender",
  ["%d held back"] = "%d retenidas",
  ["%d held back from posting"] = "%d sin publicar",
  ["%d hidden -- the live check refused them"] = "%d ocultos -- la comprobación en vivo los ha rechazado",
  ["%d in %d lots"] = "%d en %d lotes",
  ["%d in 1 lot"] = "%d en 1 lote",
  ["%d lots, %s asked"] = "%d lotes, se piden %s",
  ["%d missing"] = "faltan %d",
  ["%d partial"] = "%d parciales",
  ["%d prices in one request · books still loading"] =
    "%d precios en una sola consulta · los libros siguen cargando",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d rechazadas por la comprobación en vivo -- pulsa «HIDDEN %d» arriba para verlas",
  ["%d sales · %s proceeds · %s in the mail"] = "%d ventas · %s de ingresos · %s en el correo",
  ["%d units"] = "%d uds.",
  ["%d units · %d prices"] = "%d unidades · %d precios",
  ["%d without a price"] = "%d sin precio",
  ["%d without cost"] = "%d sin coste",
  ["%d · %d/%d covered"] = "%d · %d/%d cubiertos",
  ["%d/%d covered"] = "%d/%d cubiertos",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s por unidad    total %s -> %s",
  ["%s after the AH cut"] = "%s tras la comisión de la CdS",
  ["%s ahead"] = "%s por delante",
  ["%s under you"] = "%s por debajo de ti",
  ["%s — %d unit%s without a cost"] = "%s — %d unidad%s sin coste",
  [", %d hidden as unsellable"] = ", %d ocultos por no ser vendibles",
  ["1 lot, %s asked"] = "1 lote, se piden %s",
  ["24h trend"] = "Tendencia 24 h",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Un guion significa que GoldCap aún no conoce el coste de cada unidad: nunca lo adivinará a partir del precio de mercado.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Una pista, no una promesa: reventa al 95% del valor de mercado importado, para la cantidad que Check aprobaría.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Si varias compras están agrupadas en una sola línea, se eliminan todas.",
  ["AH answered empty %ds ago"] = "la casa de subastas respondió vacío hace %ds",
  ["ASKING"] = "PEDIDO",
  ["AT MARKET"] = "A MERCADO",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · EN PAUSA: ",
  ["AUTO · SCANNING"] = "AUTO · ESCANEANDO",
  ["AUTOMATION & ALERTS"] = "AUTOMATIZACIÓN Y AVISOS",
  ["AVOID"] = "EVITAR",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Por encima de esta subida en 24 horas, el valor de mercado se trata como un pico y se reduce.",
  ["Asks for a second click to confirm."] = "Pide un segundo clic para confirmar.",
  ["Auction House did not answer — press Refresh"] =
    "La casa de subastas no respondió — pulsa Refresh",
  ["Auction House is not open"] = "La casa de subastas no está abierta",
  ["Auto-scan on next AH visit"] = "Escaneo automático en la próxima visita a la CS",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: mantiene Full Scan en marcha y cede al instante cuando compras, busca tú mismo en la casa de subastas, o revisa el correo. Haz clic para alternar.",
  ["Avoid"] = "Evitar",
  ["BOOKS %d/%d"] = "LIBROS %d/%d",
  ["BRAKES"] = "FRENOS",
  ["BUY — unverified"] = "COMPRAR — sin verificar",
  ["Background check"] = "Comprobación en segundo plano",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "El punto de equilibrio es el precio más bajo que aún recupera tu coste tras la comisión. Vender por debajo pierde dinero.",
  ["Bundled %s data"] = "Datos %s incluidos",
  ["Bundled data"] = "Datos incluidos",
  ["Buy"] = "Comprar",
  ["Buy less"] = "Compra menos",
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
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Cancelar este lote y perder el depósito — pulsa otra vez para confirmar",
  ["Cancel timed out"] = "La cancelación agotó el tiempo",
  ["Cancelling lot…"] = "Cancelando el lote…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Cancela esta subasta activa: NO la vuelve a publicar. Pierdes el depósito y los objetos vuelven por correo; publícalos de nuevo desde esta fila cuando lleguen.",
  ["Cannot post this position"] = "No se puede publicar esta posición",
  ["Cannot remove this entry"] = "No se puede borrar esta entrada",
  ["Cannot repost this lot"] = "No se puede volver a publicar este lote",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limitado por lo rápido que se vende de verdad, no por tu bolsa.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Quedan subastas más baratas, pero al ritmo de este objeto se agotan en horas.",
  ["Check"] = "Revisar",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check lo recalcula contra el libro de órdenes en vivo antes de que se mueva el oro, y aún puede salir más bajo — o rechazar — si el mercado ha cambiado desde tu última importación.",
  ["Checked against the live order book a moment ago."] =
    "Comprobado hace un momento contra el libro de órdenes en vivo.",
  ["Checked: %d of the top %d on screen"] = "Comprobadas: %d de las %d primeras en pantalla",
  ["Checking prices…"] = "Comprobando precios…",
  ["Checking this item's price…"] = "Comprobando el precio de este objeto…",
  ["Checking..."] = "Comprobando...",
  ["Clear to buy"] = "Vía libre para comprar",
  ["Click Confirm to post"] = "Pulsa Confirm para publicar",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Otro clic cancela la subasta activa. No la vuelve a publicar: pierdes el depósito y los objetos vuelven por correo en vez de directamente a tus bolsas.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Otro clic borra definitivamente este coste introducido a mano.",
  ["Close"] = "Cerrar",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "Companion mantiene los precios al día — /goldcap companion",
  ["Companion sync rejected:"] = "Sincronización de Companion rechazada:",
  ["Confidence"] = "Confianza",
  ["Confirm"] = "Confirmar",
  ["Confirm the cancel"] = "Confirmar la cancelación",
  ["Confirm the removal"] = "Confirmar la eliminación",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Copia el enlace (Ctrl+C) y ábrelo en un navegador:",
  ["Cost per unit"] = "Coste por unidad",
  ["Cost unknown for %d of %d"] = "Coste desconocido en %d de %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Cuesta más de lo que permite tu límite por compra.",
  ["Could not find the queue's next item to post — try again"] =
    "No se encontró el siguiente objeto de la cola para publicar — inténtalo otra vez",
  ["Could not find the queue's next lot to cancel — try again"] =
    "No se encontró el siguiente lote de la cola para cancelar — inténtalo otra vez",
  ["DEFAULTS"] = "PREDETERMINADO",
  ["DISC"] = "DESC",
  ["DISPLAY"] = "PANTALLA",
  ["DONE"] = "LISTO",
  ["Default listing length for the Sell tab."] =
    "Duración de publicación predeterminada para la pestaña Vender.",
  ["Default: %s"] = "Por defecto: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
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
  ["Est. profit"] = "Beneficio est.",
  ["FIFO allocations"] = "Asignaciones FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Obteniendo un precio nuevo para este objeto — vuelve a pulsar Post en un momento",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Obteniendo un precio nuevo para este lote — vuelve a pulsar Repost en un momento",
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
  ["GoldCap — Import realm prices"] = "GoldCap — Importar precios del reino",
  ["GoldCap's"] = "de GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "La sugerencia de GoldCap para este objeto y el precio que usaría.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: comprobado en vivo -- seguro comprar",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: aún sin comprobar contra la casa de subastas en vivo",
  ["Gone"] = "Ya no está",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "En gris significa que la cotización ha envejecido; Post y Repost la actualizan antes de actuar.",
  ["HIDDEN 0"] = "OCULTAS 0",
  ["HIDE DETAILS ▾"] = "OCULTAR DETALLES ▾",
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
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Es el precio que debes batir para vender rápido, no lo que vale el objeto. Un vendedor con prisa puede ponerlo muy por debajo de su valor, y GoldCap no le seguirá hacia abajo: mira WHAT TO DO para ver el precio al que publicaría de verdad.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "No inventará un coste a partir del precio de mercado, así que el beneficio seguirá siendo desconocido hasta que introduzcas uno.",
  ["Item"] = "Objeto",
  ["Item %d"] = "Objeto %d",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."] =
    "Items: equipo, mascotas y recetas valorados frente a la referencia de región de tu importación. La velocidad de venta nunca se mide, así que nunca llegan a SEGURO -- esta la decides tú, y GoldCap solo los revisa mientras este tablero está abierto.",
  ["LISTED"] = "PUBLICADO",
  ["Language"] = "Idioma",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Idioma cambiado. Escribe /reload para aplicarlo en todas partes.",
  ["Last result: %ds ago"] = "Último resultado: hace %ds",
  ["Last result: none yet this visit"] = "Último resultado: ninguno en esta visita",
  ["Listed"] = "Publicados",
  ["Listed at %s — far below market. Repost."] =
    "Publicado a %s — muy por debajo del mercado. Vuelve a publicarlo.",
  ["Listed value"] = "Valor publicado",
  ["Listings"] = "Publicaciones",
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "Publica lo que tienes en las bolsas al precio de QUÉ HACER: toda la bolsa si es una mercancía, una pila si es un objeto normal.",
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
  ["Min return per buy %"] = "Retorno mín. por compra %",
  ["Missing cost"] = "Falta el coste",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "AÚN NO ESTÁ EN GOLDCAP.GG — SE SINCRONIZA CON /RELOAD O AL SALIR",
  ["NOT ON HAND %d"] = "NO A MANO %d",
  ["NOTHING TO CANCEL"] = "NADA QUE CANCELAR",
  ["NOTHING TO POST"] = "NADA QUE PUBLICAR",
  ["Needs a live price check before it can be bought."] =
    "Necesita una comprobación de precio en vivo antes de poder comprarse.",
  ["Never spend more than this share of your gold on one purchase."] =
    "Nunca gastar más de esta parte de tu oro en una sola compra.",
  ["No deals passed the safety checks right now."] =
    "Ahora mismo ninguna oportunidad pasa las comprobaciones de seguridad.",
  ["No deals to show -- and no realm prices yet."] =
    "No hay oportunidades que mostrar -- ni precios del reino todavía.",
  ["No deals yet."] = "Aún no hay oportunidades.",
  ["No exact auction key"] = "Sin clave de subasta exacta",
  ["No exact bag stack"] = "Sin montón exacto en la bolsa",
  ["No exact bag variant"] = "Sin variante exacta en la bolsa",
  ["No live listings came back for this item."] =
    "No llegó ninguna subasta activa para este objeto.",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "Todavía no hay precio de referencia de región para este objeto — vuelve a importar cuando goldcap.gg publique uno.",
  ["No safe resale price could be worked out."] =
    "No se pudo calcular un precio de reventa seguro.",
  ["No sales data for this item."] = "No hay datos de ventas para este objeto.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Aún no hay ventas registradas -- abre el buzón con GoldCap cargado",
  ["Not enough units on the Auction House to fill that quantity."] =
    "No hay unidades suficientes en la casa de subastas para esa cantidad.",
  ["Not in your bags or listed — mail or bank?"] =
    "Ni en tus bolsas ni publicado — ¿correo o banco?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "No disponible — las existencias están en el correo, el banco u otro personaje",
  ["Nothing is being held back."] = "No se está reteniendo nada.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Tras esta compra no queda nada contra lo que vender, así que no hay precio de salida.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Ningún anuncio alcanza el nivel de objeto con el que se midió el precio de referencia.",
  ["Nothing listed on the AH right now"] = "Ahora mismo no hay nada publicado en la subasta",
  ["Nothing on this deck matches that search"] = "Nada en esta pestaña coincide con esa búsqueda",
  ["Nothing queued to cancel"] = "Nada en cola para cancelar",
  ["Nothing queued to post"] = "Nada en cola para publicar",
  ["Nothing to remove"] = "Nada que borrar",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "EN GOLDCAP.GG — ÚLTIMOS %d DÍAS",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "EN GOLDCAP.GG — ÚLTIMOS %d DÍAS, ÚLTIMAS %d DE %d",
  ["ON THE AUCTION HOUSE"] = "EN LA CASA DE SUBASTAS",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Un único escaneo de toda la casa de subastas mediante consultas paginadas. Tarda unos De 15 a 60 segundos en reinos concurridos. Sin espera -- vuelve a escanear cuando quieras.",
  ["Open the Auction House first."] = "Abre primero la casa de subastas.",
  ["Open the Auction House to begin scanning."] =
    "Abre la casa de subastas para empezar a escanear.",
  ["Open the deals board. /gc for commands."] = "Abre el tablero de oportunidades. /gc para los comandos.",
  ["POST %d"] = "PUBLICAR %d",
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
  ["Positions without a cost or a live price are excluded."] =
    "Se excluyen las posiciones sin coste o sin precio en vivo.",
  ["Post"] = "Publicar",
  ["Post above the cheapest"] = "Publicar por encima del más barato",
  ["Post confirmation expired"] = "La confirmación de publicación ha caducado",
  ["Post the next queued item"] = "Publicar el siguiente objeto de la cola",
  ["Posting failed"] = "Fallo al publicar",
  ["Posting timed out"] = "La publicación agotó el tiempo",
  ["Posting unavailable"] = "Publicación no disponible",
  ["Posting…"] = "Publicando…",
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
  ["Pricing…"] = "Consultando precios…",
  ["Profit"] = "Beneficio",
  ["Profit per unit"] = "Beneficio por unidad",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "El seguimiento de beneficios es una función de goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "Las compras están desactivadas en esta versión.",
  ["QTY"] = "CANT",
  ["Quantity exceeds missing units"] = "La cantidad supera las unidades que faltan",
  ["Quantity is capped by how fast this item actually sells."] =
    "La cantidad está limitada por lo rápido que se vende realmente este objeto.",
  ["REALIZED PROFIT"] = "BENEFICIO REALIZADO",
  ["REFRESH"] = "ACTUALIZAR",
  ["RESET WINDOW"] = "RESTABLECER VENTANA",
  ["Reason"] = "Motivo",
  ["Refresh"] = "Actualizar",
  ["Refresh waiting for prior result"] = "La actualización espera el resultado anterior",
  ["Refreshing listings…"] = "Actualizando las publicaciones…",
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "Rechazar una compra si el precio bajó más de esto en las últimas 24 horas — podría seguir bajando.",
  ["Refused so far: %d"] = "Rechazadas hasta ahora: %d",
  ["Removal confirmation expired"] = "La confirmación de borrado ha caducado",
  ["Remove"] = "Borrar",
  ["Remove this cost"] = "Eliminar este coste",
  ["Remove?"] = "¿Borrar?",
  ["Removed"] = "Eliminado",
  ["Removed %d entries"] = "Se eliminaron %d entradas",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Borra todas las compras introducidas a mano en este grupo -- pulsa otra vez para confirmar",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Borra esta compra introducida a mano -- pulsa otra vez para confirmar",
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
  ["SHOW DETAILS ▸"] = "MOSTRAR DETALLES ▸",
  ["Sales are costed from your oldest units first"] =
    "Las ventas se imputan primero a tus unidades más antiguas",
  ["Search"] = "Buscar",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "La pestaña Vender publica un escalón por encima de la oferta más barata cuando el libro indica que se vende igual de rápido.",
  ["Sell-through"] = "Tasa de venta",
  ["Sellers"] = "Vendedores",
  ["Sells too rarely -- you would be holding it for a long time."] =
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
  ["Source age"] = "Antigüedad de la fuente",
  ["Spike-trend threshold %"] = "Umbral de subida repentina %",
  ["Start scanning as soon as the auction house opens."] =
    "Empezar a escanear en cuanto se abra la Casa de Subastas.",
  ["Status"] = "Estado",
  ["Stress exit unit"] = "Precio de salida bajo presión",
  ["Stress profit"] = "Beneficio bajo presión",
  ["THE BOOK"] = "EL LIBRO DE ÓRDENES",
  ["TOTAL"] = "TOTAL",
  ["TREND"] = "TENDENCIA",
  ["Tell GoldCap what you actually paid for these units."] =
    "Dile a GoldCap lo que pagaste realmente por estas unidades.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "La casa de subastas no dio un depósito, así que el coste es desconocido.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "El Companion está sincronizando, pero este addon no pudo leer lo que escribió:",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "El tablero lo clasificó con el snapshot importado. El libro en vivo no lo respalda.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "El botón espera un momento antes de poder pulsarse, así que nunca basta con un doble clic accidental.",
  ["The cancel did not go through — the lot is still listed"] = "La cancelación no se completó — el lote sigue publicado",
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
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Los datos de precios tienen más de tres horas. Sincroniza el Companion y haz /reload: el addon solo lee sus datos al cargar la interfaz.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "El precio está comprobado. La rapidez de venta no se mide en ningún sitio, así que la valoras tú.",
  ["The price is falling; buying into it is how you get stuck."] =
    "El precio está cayendo; entrar ahí es como te quedas atrapado.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "El precio es la última cotización, de 45 segundos de antigüedad como mucho. Si cambia antes de confirmar, la publicación se abandona en lugar de enviarse al precio viejo.",
  ["The price moved and the trade is no longer safe."] =
    "El precio se movió y la operación ya no es segura.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "El beneficio no llega a tu mínimo una vez pagados el 5 % de comisión y el depósito.",
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
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "Desconocido significa que falta parte del coste: complétalo con Fijar coste.",
  ["VERDICT"] = "VEREDICTO",
  ["Verdict"] = "Veredicto",
  ["WATCH"] = "VIGILAR",
  ["WATCH (computed SAFE)"] = "WATCH (calculado SEGURO)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "VIGILAR = la comprobación en vivo lo rechazó -- pasa el ratón por la fila para ver el motivo",
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
  ["Watching — pinned, but not a deal right now"] =
    "Vigilando — fijado, pero ahora mismo no es una oportunidad",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Lo que realmente te costó una unidad, promediado sobre las compras que aún tienes.",
  ["What to do"] = "Qué hacer",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Lo que te queda de una unidad si se vende al precio de mercado: precio de venta, menos el 5 % de comisión, menos tu coste.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Lo que suman tus subastas activas de este objeto a su precio actual.",
  ["Window position & size"] = "Posición y tamaño de la ventana",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "Con él, los precios de tu reino se actualizan solos y tus ventas y beneficios llegan a goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "Sin él, GoldCap funciona con precios congelados en la fecha de lanzamiento — las oportunidades se buscan con precios viejos.",
  ["Won't buy"] = "No compraré",
  ["Worst case back"] = "Retorno en el peor caso",
  ["YOUR LOTS"] = "TUS LOTES",
  ["YOUR PRICE"] = "TU PRECIO",
  ["You paid"] = "Pagaste",
  ["You pay"] = "Pagas",
  ["You would get"] = "Recibirías",
  ["You would pay"] = "Pagarías",
  ["Your call"] = "Tú decides",
  ["Your minimum"] = "Tu mínimo",
  ["above the cheapest, inside the cheap quarter · %d units queued below"] =
    "por encima del más barato, dentro del cuarto barato · %d unidades en cola por debajo",
  ["above the cheapest, within the day's reach · %d units queued below"] =
    "por encima del más barato, dentro del alcance del día · %d unidades en cola por debajo",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "frente al precio de la región para este objeto, tras la comisión del 5% — si se vende",
  ["any figure here would be invented out of the very number being refused"] =
    "cualquier cifra aquí saldría inventada del mismo número que se está rechazando",
  ["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"] =
    "al precio al que GoldCap espera que esto se venda, tras la comisión del 5% — no tu precio pedido",
  ["auto off"] = "auto desactivado",
  ["auto-synced %dh ago"] = "sincronizado automáticamente hace %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "datos sincronizados de %s cargados (%s de antigüedad)",
  ["auto-synced data stale -- /goldcap import"] =
    "los datos sincronizados están caducados -- /goldcap import",
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
  ["commodity purchase failed"] = "falló la compra de la mercancía",
  ["confirmed commodity purchase failed after AH close"] =
    "la compra confirmada de mercancía falló tras cerrar la casa de subastas",
  ["confirming purchase..."] = "confirmando la compra...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "la base de coste está incompleta -- define los costes para recibir consejo de republicación",
  ["cost unknown"] = "coste desconocido",
  ["crafted %s"] = "fabricado %s",
  ["data from goldcap.gg · synced %s ago"] = "datos de goldcap.gg · sincronizados hace %s",
  ["due -- will be asked next pass"] = "pendiente -- se consultará en la próxima pasada",
  ["fair"] = "media",
  ["far below market"] = "muy por debajo del mercado",
  ["finish the pending buy first"] = "termina primero la compra pendiente",
  ["first in line"] = "primero en la cola",
  ["full scan already in progress"] = "el escaneo completo ya está en marcha",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "escaneo completo terminado: %d oportunidad%s de %d grupo%s de objetos%s",
  ["full scan interrupted -- confirm your purchase"] =
    "escaneo completo interrumpido -- confirma tu compra",
  ["full scan stalled -- press Full Scan to retry"] =
    "el escaneo completo se ha atascado -- pulsa Full Scan para reintentar",
  ["full scan stalled -- retrying shortly"] =
    "el escaneo completo se ha atascado -- se reintentará en breve",
  ["gone / price changed"] = "desaparecido / precio cambiado",
  ["high"] = "alta",
  ["hold"] = "mantener",
  ["identity unresolved (variant item -- not priced by design)"] =
    "identidad sin resolver (objeto con variantes -- sin precio por diseño)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "si compras las %d y las revendes al precio que hay ahora mismo",
  ["import %dh old"] = "importación de hace %dh",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "importación caducada -- /goldcap import o /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "importados %d objetos para %s (%s) — los precios ya están activos.",
  ["in the mail"] = "en el correo",
  ["in the mail, the bank or on another character"] = "en el correo, el banco o en otro personaje",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "es lo que absorbe este mercado — más allá compras existencias que se te quedarán",
  ["item %d"] = "objeto %d",
  ["item %d: %s"] = "objeto %d: %s",
  ["item variant unresolved"] = "variante del objeto sin resolver",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "últimas 24 h — %d ventas, %s bruto, %s de comisión, %d compras, %s gastados",
  ["leave these alone"] = "déjalos como están",
  ["listing gone -- already bought out or price changed"] =
    "la publicación ha desaparecido -- ya la compraron o cambió el precio",
  ["listing gone -- bought out or repriced"] = "la subasta ya no está: comprada o con otro precio",
  ["live safety confirmed -- click Buy to purchase"] =
    "seguridad confirmada en vivo -- pulsa Buy para comprar",
  ["live verification required"] = "se requiere verificación en vivo",
  ["low"] = "baja",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "importación manual -- Companion lo mantiene al día: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "necesita un precio nuevo -- pulsa Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "sin confirmación del servidor -- la compra puede haberse completado igualmente, revisa tu correo. Cerrar esto no la deshará.",
  ["no cost"] = "sin coste",
  ["no cost for %d"] = "sin coste para %d",
  ["no live price yet"] = "aún sin precio en vivo",
  ["no price"] = "sin precio",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "todavía no hay precios -- /goldcap companion o /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "no se recibió confirmación de compra -- pulsa Cancel y reinténtalo",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "aún no hay ventas registradas — abre el buzón con GoldCap cargado y se leerán de las facturas",
  ["no stock in bags or listed -- nothing to price for"] =
    "sin existencias en bolsas ni publicadas -- nada que cotizar",
  ["none"] = "ninguno",
  ["not enough gold -- total %s, you have %s"] = "no hay oro suficiente -- total %s, tienes %s",
  ["not enough gold for this quote -- Cancel"] =
    "no hay oro suficiente para esta cotización -- Cancel",
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "no quedan suficientes unidades para esa cantidad -- comprobando de nuevo lo que queda...",
  ["not ready to cancel"] = "aún no se puede cancelar",
  ["not ready to post"] = "aún no se puede publicar",
  ["nothing listed"] = "nada publicado",
  ["of %d"] = "de %d",
  ["off"] = "desactivado",
  ["oldest units sell first"] = "las unidades más antiguas se venden primero",
  ["on"] = "activado",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "o pega una cadena de goldcap.gg con /goldcap import.",
  ["over %d position%s"] = "en %d posiciones%s",
  ["paid sale unresolved"] = "venta cobrada sin resolver",
  ["placing bid..."] = "pujando...",
  ["price checked, sale speed unknown -- this one is your call"] =
    "precio comprobado, velocidad de venta desconocida -- esta la decides tú",
  ["price confirmed -- click Buy to purchase"] = "precio confirmado -- pulsa Buy para comprar",
  ["price rose %.1fx — still safe, confirm"] = "el precio subió %.1fx — sigue siendo seguro, confirma",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "los precios cargados son de %s (%s) pero juegas en %s — cada descuento y beneficio se mide contra otro mercado",
  ["purchase canceled"] = "compra cancelada",
  ["purchase complete"] = "compra completada",
  ["purchase identity unresolved"] = "identidad de la compra sin resolver",
  ["purchase pending exact cost"] = "compra pendiente del coste exacto",
  ["purchase total unavailable — inspect mailbox"] =
    "no se puede obtener el total de la compra — revisa el buzón",
  ["quote %s -- click Confirm to buy"] = "cotización %s -- pulsa Confirm para comprar",
  ["quote %ss ago"] = "cotización de hace %ss",
  ["quote expired -- Refresh to re-check the price"] =
    "cotización caducada -- pulsa Refresh para volver a comprobar el precio",
  ["re-checking what remains at a safe price..."] =
    "comprobando de nuevo lo que queda a un precio seguro...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "objeto de reino — velocidad de venta sin verificar · referencia de región %s (nivel %d)",
  ["recent sales (newest first):"] = "ventas recientes (las más nuevas primero):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "región %s — incluidos: %d objetos (%s), importados: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "región corregida en %d registros; %d ventas emparejadas de nuevo con su stock",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "republicar ahora fijaría una pérdida o un estancamiento -- espera",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "borrados %d registros de compra duplicados que dejó un fallo al leer el correo",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "borrados %d registros de venta duplicados que dejó un fallo al leer el correo",
  ["sale name ambiguous"] = "nombre de la venta ambiguo",
  ["sale proceeds pending"] = "ingresos de la venta pendientes",
  ["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"] =
    "escaneo completo: %d oferta%s de %d objeto%s en materiales, consumibles, gemas, encantamientos%s",
  ["scanned %d listings over %d passes"] = "escaneadas %d publicaciones en %d pasadas",
  ["scanning auction house..."] = "escaneando la casa de subastas...",
  ["scanning… %d results · %d deals%s"] = "escaneando… %d resultados · %d oportunidades%s",
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
  ["the Companion wrote prices this addon could not read --"] =
    "el Companion escribió precios que este addon no pudo leer --",
  ["the import failed (%s)"] = "la importación falló (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "para colocar %d unidades a %s ventas al día, con %s inmovilizado todo ese tiempo",
  ["under GoldCap's own floor of %s"] = "por debajo del mínimo de GoldCap, %s",
  ["unknown evidence"] = "evidencia desconocida",
  ["waiting for previous commodity purchase to settle"] =
    "esperando a que se liquide la compra de mercancía anterior",
  ["waiting for previous search result to settle"] =
    "esperando el resultado de la búsqueda anterior",
  ["watching %s closely -- re-checked every few seconds"] =
    "vigilando %s de cerca -- se recomprueba cada pocos segundos",
  ["worst case, selling all %d back into the price standing there now"] =
    "en el peor caso, revendiendo las %d al precio que hay ahora mismo",
  ["worth cancelling"] = "conviene cancelar",
  ["would sell at a loss"] = "se vendería con pérdidas",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "aún no has importado los precios del reino -- instala GoldCap Companion (/goldcap companion) o pega una cadena de goldcap.gg (/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "tu cliente del juego no tiene fuente para este idioma — el texto se verá como cuadros vacíos",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "tu importación tiene %d horas -- los precios pueden estar desviados. Pega una cadena nueva de goldcap.gg (/goldcap import).",
  ["yours"] = "tuyo",
  ["» needs price"] = "» falta precio",
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
  ["— = nothing is checking this row right now"] =
    "— = nada está comprobando esta fila ahora mismo",
  ["… = a live check is queued for this row"] =
    "… = hay una comprobación en vivo en cola para esta fila",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valor de mercado de goldcap.gg — aún sin cotización en vivo",
  ["no answer %ds ago -- resting"] = "sin respuesta hace %ds -- en pausa",
}
