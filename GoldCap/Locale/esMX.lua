local _, GC = ...

-- Spanish (Latin America). Derived from esES: at this vocabulary the two differ lexically
-- rather than grammatically -- "costo" instead of "coste" being the one that touches almost
-- every screen here. Kept as its own file rather than an alias so a future divergence has
-- somewhere to live.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.esMX = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s cada uno  (%s en total, %s de comisión)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion lo mantiene al día: /goldcap companion.",
  [" rows against the live auction house about every "] =
    " filas contra la casa de subastas en vivo, cada ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · %d hidden"] = " · %d ocultos",
  [" · below cost"] = " · por debajo del costo",
  [" · identity unresolved"] = " · identidad sin resolver",
  [" · stale %ds"] = " · %ds de antigüedad",
  [" — Check again"] = " — verifica de nuevo",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — comandos: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (o /gc para abreviar)",
  ["%d (whole lot)"] = "%d (lote completo)",
  ["%d days"] = "%d días",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d oportunidades del último escaneo -- pulsa Full Scan para actualizar",
  ["%d filtered out as hard to resell"] = "%d descartadas por ser difíciles de revender",
  ["%d held back"] = "%d retenidas",
  ["%d held back from posting"] = "%d sin publicar",
  ["%d missing"] = "faltan %d",
  ["%d partial"] = "%d parciales",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d rechazadas por la comprobación en vivo -- pulsa «HIDDEN %d» arriba para verlas",
  ["%d sales · %s proceeds · %s in the mail"] = "%d ventas · %s de ingresos · %s en el correo",
  ["%d units"] = "%d uds.",
  ["%d units · %d prices"] = "%d unidades · %d precios",
  ["%d without a price"] = "%d sin precio",
  ["%d without cost"] = "%d sin costo",
  ["%d · %d/%d covered"] = "%d · %d/%d cubiertos",
  ["%d/%d covered"] = "%d/%d cubiertos",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s por unidad    total %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d unidad%s sin costo",
  [", %d hidden as unsellable"] = ", %d ocultos por no ser vendibles",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "De 15 a 60 segundos en reinos concurridos. Sin espera -- vuelve a escanear cuando quieras.",
  ["24h trend"] = "Tendencia 24 h",
  ["A commodity lists the whole bag total at once; a normal item lists one stack, the largest GoldCap can identify exactly."] =
    "Una mercancía se publica con todo el total de la bolsa de una vez; un objeto normal publica una pila, la mayor que GoldCap pueda identificar con exactitud.",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Un guion significa que GoldCap aún no conoce el costo de cada unidad: nunca lo adivinará a partir del precio de mercado.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Una pista, no una promesa: reventa al 95% del valor de mercado importado, para la cantidad que Check aprobaría.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Si varias compras están agrupadas en una sola línea, se eliminan todas.",
  ["AH answered empty %ds ago"] = "la casa de subastas respondió vacío hace %ds",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · EN PAUSA: ",
  ["AUTO · SCANNING"] = "AUTO · ESCANEANDO",
  ["AUTOMATION & ALERTS"] = "AUTOMATIZACIÓN Y AVISOS",
  ["Auction House did not answer — press Refresh"] =
    "La casa de subastas no respondió — pulsa Refresh",
  ["Auction House is not open"] = "La casa de subastas no está abierta",
  ["Auto-scan on next AH visit"] = "Escaneo automático en la próxima visita a la CS",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Auto: mantiene Full Scan en marcha y cede al instante cuando compras, ",
  ["Avoid"] = "Evitar",
  ["Background check"] = "Comprobación en segundo plano",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "El punto de equilibrio es el precio más bajo que aún recupera tu costo tras la comisión. Vender por debajo pierde dinero.",
  ["Bundled %s data"] = "Datos %s incluidos",
  ["Bundled data"] = "Datos incluidos",
  ["Buy"] = "Comprar",
  ["Buy less"] = "Compra menos",
  ["CANCEL %d"] = "CANCELAR %d",
  ["CANCEL LOT?"] = "¿CANCELAR EL LOTE?",
  ["CANCELLING…"] = "CANCELANDO…",
  ["CONFIRM"] = "CONFIRMAR",
  ["COST"] = "COSTO",
  ["COST / UNIT"] = "COSTO / UNIDAD",
  ["Can't price this"] = "Sin precio confiable",
  ["Cancel"] = "Cancelar",
  ["Cancel lot?"] = "¿Cancelar el lote?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Cancelar este lote y perder el depósito — pulsa otra vez para confirmar",
  ["Cancel timed out"] = "La cancelación agotó el tiempo",
  ["Cancelling forfeits the deposit, so this asks for a second click to confirm."] =
    "Cancelar hace perder el depósito, por eso pide un segundo clic para confirmar.",
  ["Cancelling lot…"] = "Cancelando el lote…",
  ["Cancels this live auction. It does NOT relist it: the deposit is forfeit, and the cancelled items come back by mail, not straight into your bags."] =
    "Cancela esta subasta activa. NO la vuelve a publicar: pierdes el depósito y los objetos cancelados vuelven por correo, no directamente a tus bolsas.",
  ["Cannot post this position"] = "No se puede publicar esta posición",
  ["Cannot remove this entry"] = "No se puede borrar esta entrada",
  ["Cannot repost this lot"] = "No se puede volver a publicar este lote",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limitado por qué tan rápido se vende de verdad, no por tu bolsa.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Quedan subastas más baratas, pero al ritmo de este objeto se agotan en horas.",
  ["Check"] = "Comprobar",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check lo recalcula contra el libro de órdenes en vivo antes de que se mueva el oro, y aún puede salir más bajo — o rechazar — si el mercado ha cambiado desde tu última importación.",
  ["Checked against the live order book a moment ago."] =
    "Verificado hace un momento contra el libro de órdenes en vivo.",
  ["Checked: %d of the top %d on screen"] = "Comprobadas: %d de las %d primeras en pantalla",
  ["Checking prices…"] = "Comprobando precios…",
  ["Checking this item's price…"] = "Comprobando el precio de este objeto…",
  ["Checking..."] = "Verificando...",
  ["Clear to buy"] = "Vía libre para comprar",
  ["Click Confirm to post"] = "Pulsa Confirm para publicar",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Otro clic cancela la subasta activa. No la vuelve a publicar: pierdes el depósito y los objetos vuelven por correo en vez de directamente a tus bolsas.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Otro clic borra definitivamente este costo ingresado a mano.",
  ["Close"] = "Cerrar",
  ["Companion sync rejected:"] = "Sincronización de Companion rechazada:",
  ["Confidence"] = "Confianza",
  ["Confirm"] = "Confirmar",
  ["Confirm the cancel"] = "Confirmar la cancelación",
  ["Confirm the removal"] = "Confirmar la eliminación",
  ["Cost per unit"] = "Costo por unidad",
  ["Cost unknown for %d of %d"] = "Costo desconocido en %d de %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Cuesta más de lo que permite tu límite por compra.",
  ["Could not find the queue's next item to post — try again"] =
    "No se encontró el siguiente objeto de la cola para publicar — inténtalo otra vez",
  ["Could not find the queue's next lot to cancel — try again"] =
    "No se encontró el siguiente lote de la cola para cancelar — inténtalo otra vez",
  ["DEAL THRESHOLDS"] = "UMBRALES DE OFERTA",
  ["DISC"] = "DESC",
  ["DISPLAY"] = "PANTALLA",
  ["DONE"] = "LISTO",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Borra un costo que escribiste a mano en Fijar costo, nunca una compra que GoldCap capturó o emparejó con tu correo.",
  ["Discount"] = "Descuento",
  ["Discount vs market value from your GoldCap import"] =
    "Descuento frente al valor de mercado de tu importación de GoldCap",
  ["Dump-trend cap %"] = "Tope de tendencia a la baja %",
  ["Duration"] = "Duración",
  ["Enlarge the window to see details"] = "Agranda la ventana para ver los detalles",
  ["Enter a whole quantity"] = "Introduce una cantidad entera",
  ["Enter an exact positive cost"] = "Introduce un costo exacto y positivo",
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
  ["Full pass over them: %.1fs"] = "Pasada completa: %.1fs",
  ["Full pass over them: measuring..."] = "Pasada completa: midiendo...",
  ["GOOD = solid discount + profit"] = "GOOD = descuento sólido + beneficio",
  ["GOOD — min discount %"] = "GOOD — descuento mínimo %",
  ["GOOD — min sold/day"] = "GOOD — ventas mínimas/día",
  ["Gold tied up"] = "Oro inmovilizado",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap no puede determinar qué montón de la bolsa es este",
  ["GoldCap data age"] = "Antigüedad de los datos de GoldCap",
  ["GoldCap re-checks the top "] = "GoldCap vuelve a comprobar las ",
  ["GoldCap value"] = "Valor GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Importar precios del reino",
  ["GoldCap's"] = "de GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "La sugerencia de GoldCap para este objeto y el precio que usaría.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: comprobado en vivo -- seguro comprar",
  ["Gone"] = "Ya no está",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "En gris significa que la cotización ha envejecido; Post y Repost la actualizan antes de actuar.",
  ["HIDDEN 0"] = "OCULTAS 0",
  ["HIDE DETAILS ▾"] = "OCULTAR DETALLES ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = gran descuento + beneficio alto + ventas/día demostradas",
  ["HOT — min discount %"] = "HOT — descuento mínimo %",
  ["HOT — min sold/day"] = "HOT — ventas mínimas/día",
  ["Held back from cancelling"] = "Retenido de la cancelación",
  ["Held back from the queue"] = "Retenido de la cola",
  ["ITEM"] = "OBJETO",
  ["If it clears"] = "Si se vende",
  ["Import"] = "Importar",
  ["Import failed:"] = "Fallo al importar:",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Instala el GoldCap Companion gratuito para mantener los precios al día automáticamente (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Es el precio que debes batir para vender rápido, no lo que vale el objeto. Un vendedor con prisa puede ponerlo muy por debajo de su valor, y GoldCap no le seguirá hacia abajo: mira WHAT TO DO para ver el precio al que publicaría de verdad.",
  ["It will list stock GoldCap never saw you buy — not knowing what something cost is a reason to report the profit as unknown, not a reason to refuse to sell it."] =
    "También publicará existencias cuya compra GoldCap nunca vio: no saber lo que costó algo es motivo para dar la ganancia como desconocida, no para negarse a venderlo.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "No inventará un costo a partir del precio de mercado, así que la ganancia seguirá siendo desconocida hasta que ingreses uno.",
  ["Item"] = "Objeto",
  ["Item %d"] = "Objeto %d",
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
  ["Lists what is sitting in your bags at the price shown under WHAT TO DO."] =
    "Publica lo que tienes en las bolsas al precio que aparece bajo QUÉ HACER.",
  ["Live ask"] = "Precio en vivo",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lote cancelado; espera a que vuelva a las bolsas",
  ["MARKET"] = "MERCADO",
  ["MARKET / UNIT"] = "MERCADO / UNIDAD",
  ["MATCH"] = "IGUALAR",
  ["Market per unit"] = "Mercado por unidad",
  ["Market reference"] = "Referencia de mercado",
  ["Max wallet per buy %"] = "Máx. de tu oro por compra %",
  ["Min profit per buy (gold)"] = "Ganancia mínima por compra (oro)",
  ["Missing cost"] = "Falta el costo",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "AÚN NO ESTÁ EN GOLDCAP.GG — SE SINCRONIZA CON /RELOAD O AL SALIR",
  ["NOTHING TO CANCEL"] = "NADA QUE CANCELAR",
  ["NOTHING TO POST"] = "NADA QUE PUBLICAR",
  ["Needs a live price check before it can be bought."] =
    "Necesita una verificación de precio en vivo antes de poder comprarse.",
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
  ["Nothing listed on the AH right now"] = "Ahora mismo no hay nada publicado en la subasta",
  ["Nothing queued to cancel"] = "Nada en cola para cancelar",
  ["Nothing queued to post"] = "Nada en cola para publicar",
  ["Nothing to remove"] = "Nada que borrar",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "EN GOLDCAP.GG — ÚLTIMOS %d DÍAS",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "EN GOLDCAP.GG — ÚLTIMOS %d DÍAS, ÚLTIMAS %d DE %d",
  ["ON THE AUCTION HOUSE"] = "EN LA CASA DE SUBASTAS",
  ["Once the mail arrives, list it again yourself at the new price -- from this same row."] =
    "Cuando llegue el correo, vuelve a publicarlo tú mismo al nuevo precio, desde esta misma fila.",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Un único escaneo de toda la casa de subastas mediante consultas paginadas. Tarda unos ",
  ["Open the Auction House first."] = "Abre primero la casa de subastas.",
  ["Open the Auction House to begin scanning."] =
    "Abre la casa de subastas para empezar a escanear.",
  ["Open the deals board. /gc for commands."] = "Abre el tablero de oportunidades. /gc para los comandos.",
  ["POST %d"] = "PUBLICAR %d",
  ["POSTING"] = "PUBLICACIÓN",
  ["POSTING…"] = "PUBLICANDO…",
  ["PRICE"] = "PRECIO",
  ["PRICE ROSE %.1fx"] = "EL PRECIO SUBIÓ %.1fx",
  ["PRICING %d/%d"] = "PRECIOS %d/%d",
  ["PRICING…"] = "PRECIOS…",
  ["PROFIT"] = "GANANCIA",
  ["PROFIT / UNIT"] = "BENEFICIO / UNIDAD",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Vincula o actualiza el GoldCap Companion para ver el beneficio de goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Pega la cadena de tu reino desde goldcap.gg y pulsa Import.",
  ["Per-unit price of this auction"] = "Precio por unidad de esta subasta",
  ["Position scope changed"] = "El ámbito de la posición ha cambiado",
  ["Positions without a cost or a live price are excluded."] =
    "Se excluyen las posiciones sin costo o sin precio en vivo.",
  ["Post"] = "Publicar",
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
  ["Pricing…"] = "Consultando precios…",
  ["Profit"] = "Ganancia",
  ["Profit per unit"] = "Ganancia por unidad",
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
  ["Refused so far: %d"] = "Rechazadas hasta ahora: %d",
  ["Removal confirmation expired"] = "La confirmación de borrado ha caducado",
  ["Remove"] = "Borrar",
  ["Remove this cost"] = "Eliminar este costo",
  ["Remove?"] = "¿Borrar?",
  ["Removed"] = "Eliminado",
  ["Removed %d entries"] = "Se eliminaron %d entradas",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Borra todas las compras introducidas a mano en este grupo -- pulsa otra vez para confirmar",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Borra esta compra introducida a mano -- pulsa otra vez para confirmar",
  ["Repost"] = "Republicar",
  ["Repost confirmation expired"] = "La confirmación de republicación ha caducado",
  ["Right-click to stop watching this item"] = "Clic derecho para dejar de vigilar este objeto",
  ["Right-click to watch this item closely"] = "Clic derecho para vigilar de cerca este objeto",
  ["SAFETY"] = "SEGURIDAD",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SE GUARDA AL INSTANTE · ESC O DONE PARA CERRAR",
  ["SCAN"] = "ESCANEAR",
  ["SCANNING…"] = "ESCANEANDO…",
  ["SESSION %s%s · %d BUYS"] = "SESIÓN %s%s · %d COMPRAS",
  ["SHOW DETAILS ▸"] = "MOSTRAR DETALLES ▸",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = descuento tan extremo que seguramente sea una estafa o un mercado mal valorado",
  ["Sales are costed from your oldest units first"] =
    "Las ventas se imputan primero a tus unidades más antiguas",
  ["Sell-through"] = "Tasa de venta",
  ["Sellers"] = "Vendedores",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Se vende demasiado poco: te lo quedarías mucho tiempo.",
  ["Set cost"] = "Definir costo",
  ["Settings"] = "Ajustes",
  ["Snapshot value"] = "Valor del snapshot",
  ["Sold per day"] = "Ventas por día",
  ["Sold/day"] = "Ventas/día",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Ordena por él para decidir qué comprobar primero, no qué comprar.",
  ["Sound on HOT deal"] = "Sonido en oferta HOT",
  ["Source age"] = "Antigüedad de la fuente",
  ["Spike-trend threshold %"] = "Umbral de subida repentina %",
  ["Status"] = "Estado",
  ["Stress exit unit"] = "Precio de salida bajo presión",
  ["Stress profit"] = "Beneficio bajo presión",
  ["THE BOOK"] = "EL LIBRO DE ÓRDENES",
  ["TIER"] = "NIVEL",
  ["TOTAL"] = "TOTAL",
  ["TREND"] = "TENDENCIA",
  ["Tell GoldCap what you actually paid for these units."] =
    "Dile a GoldCap lo que pagaste realmente por estas unidades.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "La casa de subastas no dio un depósito, así que el costo es desconocido.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "El Companion está sincronizando, pero este addon no pudo leer lo que escribió:",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "El tablero lo clasificó con el snapshot importado. El libro en vivo no lo respalda.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "El botón espera un momento antes de poder presionarse, así que nunca basta con un doble clic accidental.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "El precio más barato que pide AHORA OTRA persona, según una consulta en vivo a la casa de subastas. Tus propias publicaciones quedan excluidas, así que el número nunca se persigue a sí mismo hacia abajo.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Los datos de este objeto están mal formados, así que GoldCap no va a adivinar.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "La aplicación de escritorio Companion, gratuita, mantiene tus precios al día automáticamente y sincroniza tus ventas. Copia el enlace (Ctrl+C) y ábrelo en un navegador:",
  ["The liquidity data is not reliable enough to act on."] =
    "Los datos de liquidez no son lo bastante confiables para actuar.",
  ["The market value is an estimate, not a measurement."] =
    "El valor de mercado es una estimación, no una medición.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Los datos de precios tienen más de tres horas. Sincroniza el Companion y haz /reload: el addon solo lee sus datos al cargar la interfaz.",
  ["The price is falling; buying into it is how you get stuck."] =
    "El precio está cayendo; entrar ahí es como te quedas atrapado.",
  ["The price is the last one GoldCap fetched, at most 45 seconds old — not a fresh check made at the moment you click. If it changes between arming the post and confirming it, the post is abandoned rather than sent at the old price."] =
    "El precio es el último que obtuvo GoldCap, con 45 segundos de antigüedad como máximo, no una consulta nueva hecha al hacer clic. Si cambia entre preparar la publicación y confirmarla, se abandona en lugar de enviarse al precio viejo.",
  ["The price moved and the trade is no longer safe."] =
    "El precio se movió y la operación ya no es segura.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "La ganancia no llega a tu mínimo una vez pagados el 5 % de comisión y el depósito.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "No se puede deshacer. El primer clic pide un segundo para confirmar.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Es un objeto de reino, y GoldCap solo verifica precios de mercancías.",
  ["Tier"] = "Nivel",
  ["Too few sellers to read a real price."] = "Hay muy pocos vendedores para leer un precio real.",
  ["Too little of what is listed actually sells."] = "Se vende muy poco de lo que hay publicado.",
  ["Too little price history to trust the value."] =
    "Hay muy poco historial de precios para confiar en el valor.",
  ["Total cost to buy this auction"] = "Costo total de comprar esta subasta",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Escribe un precio en oro, o vacía el campo para usar el de GoldCap",
  ["UNDERCUT"] = "REBAJAR",
  ["UNIT"] = "UNIDAD",
  ["Unit price"] = "Precio por unidad",
  ["Unknown"] = "Desconocido",
  ["Unknown item"] = "Objeto desconocido",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "Desconocido significa que falta parte del costo: complétalo con Fijar costo.",
  ["WATCH (computed SAFE)"] = "WATCH (calculado SEGURO)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = con descuento pero con liquidez no demostrada o beneficio pequeño",
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
    "Lo que te queda de una unidad si se vende al precio de mercado: precio de venta, menos el 5 % de comisión, menos tu costo.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Lo que suman tus subastas activas de este objeto a su precio actual.",
  ["Window position & size"] = "Posición y tamaño de la ventana",
  ["Won't buy"] = "No voy a comprar",
  ["Worst case back"] = "Retorno en el peor caso",
  ["Worth doing when someone has undercut you; not worth it if the price barely moved."] =
    "Vale la pena cuando alguien te bajó el precio; no si apenas se movió.",
  ["YOUR PRICE"] = "TU PRECIO",
  ["You paid"] = "Pagaste",
  ["You pay"] = "Pagas",
  ["You would get"] = "Recibirías",
  ["You would pay"] = "Pagarías",
  ["any figure here would be invented out of the very number being refused"] =
    "cualquier cifra aquí saldría inventada del mismo número que se está rechazando",
  ["auto off"] = "auto desactivado",
  ["auto-synced %dh ago"] = "sincronizado automáticamente hace %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "datos sincronizados de %s cargados (%s de antigüedad)",
  ["auto-synced data stale -- /goldcap import"] =
    "los datos sincronizados están caducados -- /goldcap import",
  ["auto: paused"] = "auto: en pausa",
  ["below the %s you paid"] = "por debajo de los %s que pagaste",
  ["big buy"] = "compra grande",
  ["blue is already yours"] = "lo azul ya es tuyo",
  ["bought %d x item %d"] = "comprados %d x objeto %d",
  ["bought %d x item %d after AH close"] =
    "comprados %d x objeto %d tras cerrar la casa de subastas",
  ["buying commodity..."] = "comprando mercancía...",
  ["cheapest not yours %s"] = "el más barato que no es tuyo %s",
  ["checking live price..."] = "comprobando el precio en vivo...",
  ["checking live safety..."] = "comprobando la seguridad en vivo...",
  ["commodity no longer available -- someone bought it out"] =
    "la mercancía ya no está disponible -- alguien la compró entera",
  ["commodity purchase failed"] = "falló la compra de la mercancía",
  ["confirmed commodity purchase failed after AH close"] =
    "la compra confirmada de mercancía falló tras cerrar la casa de subastas",
  ["confirming purchase..."] = "confirmando la compra...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "la base de costo está incompleta -- define los costos para recibir consejo de republicación",
  ["cost unknown"] = "costo desconocido",
  ["data from goldcap.gg · synced %s ago"] = "datos de goldcap.gg · sincronizados hace %s",
  ["due -- will be asked next pass"] = "pendiente -- se consultará en la próxima pasada",
  ["fair"] = "media",
  ["finish the pending buy first"] = "termina primero la compra pendiente",
  ["full scan already in progress"] = "el escaneo completo ya está en marcha",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "escaneo completo terminado: %d oportunidad%s de %d grupo%s de objetos%s",
  ["full scan interrupted -- confirm your purchase"] =
    "escaneo completo interrumpido -- confirma tu compra",
  ["full scan stalled -- press Full Scan to retry"] =
    "el escaneo completo se ha atascado -- pulsa Full Scan para reintentar",
  ["full scan stalled -- retrying shortly"] =
    "el escaneo completo se ha atascado -- se reintentará en breve",
  ["gold is where your price lands"] = "el dorado es donde cae tu precio",
  ["gold is where your price lands, blue is already yours"] =
    "el dorado es donde cae tu precio, lo azul ya es tuyo",
  ["gone / price changed"] = "desaparecido / precio cambiado",
  ["high"] = "alta",
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
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "es lo que absorbe este mercado — más allá compras existencias que se te van a quedar",
  ["item %d"] = "objeto %d",
  ["item %d: %s"] = "objeto %d: %s",
  ["item variant unresolved"] = "variante del objeto sin resolver",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "últimas 24 h — %d ventas, %s bruto, %s de comisión, %d compras, %s gastados",
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
  ["no live price yet"] = "aún sin precio en vivo",
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
  ["not ready to cancel"] = "aún no se puede cancelar",
  ["not ready to post"] = "aún no se puede publicar",
  ["nothing listed"] = "nada publicado",
  ["of %d"] = "de %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "o pega una cadena de goldcap.gg con /goldcap import.",
  ["over %d position%s"] = "en %d posiciones%s",
  ["paid sale unresolved"] = "venta cobrada sin resolver",
  ["placing bid..."] = "pujando...",
  ["price confirmed -- click Buy to purchase"] = "precio confirmado -- pulsa Buy para comprar",
  ["price rose %.1fx — still safe, confirm"] = "el precio subió %.1fx — sigue siendo seguro, confirma",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "los precios cargados son de %s (%s) pero juegas en %s — cada descuento y ganancia se mide contra otro mercado",
  ["purchase canceled"] = "compra cancelada",
  ["purchase complete"] = "compra completada",
  ["purchase identity unresolved"] = "identidad de la compra sin resolver",
  ["purchase pending exact cost"] = "compra pendiente del costo exacto",
  ["purchase total unavailable — inspect mailbox"] =
    "no se puede obtener el total de la compra — revisa el buzón",
  ["quote %s -- click Confirm to buy"] = "cotización %s -- pulsa Confirm para comprar",
  ["quote %ss ago"] = "cotización de hace %ss",
  ["quote expired -- Refresh to re-check the price"] =
    "cotización caducada -- pulsa Refresh para volver a comprobar el precio",
  ["recent sales (newest first):"] = "ventas recientes (las más nuevas primero):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "región %s — incluidos: %d objetos (%s), importados: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "región corregida en %d registros; %d ventas emparejadas de nuevo con su inventario",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "republicar ahora fijaría una pérdida o un estancamiento -- espera",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "borrados %d registro%s de compra duplicados que dejó un fallo al leer el correo",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "borrados %d registro%s de venta duplicados que dejó un fallo al leer el correo",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    " s. Las filas rechazadas se ocultan. Comprar sigue siendo siempre un clic tuyo.",
  ["sale name ambiguous"] = "nombre de la venta ambiguo",
  ["sale proceeds pending"] = "ingresos de la venta pendientes",
  ["scanned %d listings over %d passes"] = "escaneadas %d publicaciones en %d pasadas",
  ["scanning auction house..."] = "escaneando la casa de subastas...",
  ["scanning… %d results · %d deals%s"] = "escaneando… %d resultados · %d oportunidades%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "busca tú mismo en la casa de subastas, o revisa el correo. Haz clic para alternar.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "vende %s/día",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "sesión: %d capturas, %s gastados, ~%s de beneficio est.",
  ["sniped (listing changed on rescan)"] = "se lo llevaron (la publicación cambió al reescanear)",
  ["sniped for "] = "cazado por ",
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
  ["waiting for server... full scan will start automatically"] =
    "esperando al servidor... el escaneo completo empezará solo",
  ["watching %s closely -- re-checked every few seconds"] =
    "vigilando %s de cerca -- se recomprueba cada pocos segundos",
  ["worst case, selling all %d back into the price standing there now"] =
    "en el peor caso, revendiendo las %d al precio que hay ahora mismo",
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
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valor de mercado de goldcap.gg — aún sin cotización en vivo",
}
