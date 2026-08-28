local _, GC = ...

-- Russian. Terminology follows apps/web/messages/ru.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ruRU = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d по %s за штуку  (%s всего, %s комиссия)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion обновляет это сам: /goldcap companion.",
  [" rows against the live auction house about every "] =
    " строк по живому аукциону примерно каждые ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · %d hidden"] = " · скрыто %d",
  [" · below cost"] = " · ниже себестоимости",
  [" · identity unresolved"] = " · позиция не опознана",
  [" · stale %ds"] = " · устарело %dс",
  [" — Check again"] = " — проверьте ещё раз",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — команды: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (или коротко /gc)",
  ["%d (whole lot)"] = "%d (весь лот)",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d сделок с последнего сканирования -- Full Scan, чтобы обновить",
  ["%d filtered out as hard to resell"] = "%d отсеяно как трудные для перепродажи",
  ["%d held back"] = "%d придержано",
  ["%d held back from posting"] = "%d придержано от выставления",
  ["%d missing"] = "%d не хватает",
  ["%d partial"] = "%d частично",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d отклонено живой проверкой -- нажмите \"HIDDEN %d\" вверху, чтобы посмотреть",
  ["%d sales · %s proceeds · %s in the mail"] = "%d продаж · %s выручка · %s в почте",
  ["%d without a price"] = "%d без цены",
  ["%d without cost"] = "%d без себестоимости",
  ["%d · %d/%d covered"] = "%d · %d/%d покрыто",
  ["%d/%d covered"] = "%d/%d покрыто",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s за штуку    всего %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d единиц%s без себестоимости",
  [", %d hidden as unsellable"] = ", скрыто %d как непродаваемые",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "15-60 секунд на загруженных реалмах. Без отката -- сканируйте когда угодно.",
  ["24h trend"] = "Тренд за 24ч",
  ["A commodity lists the whole bag total at once; a normal item lists one stack, the largest GoldCap can identify exactly."] =
    "Товар выставляется всем объёмом из сумок сразу; обычный предмет — одним стеком, самым большим, который GoldCap может опознать точно.",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Прочерк значит, что себестоимость известна не по всем единицам — из рыночной цены она никогда не выдумывается.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Ориентир, а не обещание: перепродажа по 95% импортированной рыночной стоимости, на количество, которое одобрит сама проверка.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Если несколько покупок свёрнуты в одну строку, удалятся они все.",
  ["AH answered empty %ds ago"] = "Аукцион ответил пусто %dс назад",
  ["AUTO"] = "АВТО",
  ["AUTO · PAUSED: "] = "АВТО · ПАУЗА: ",
  ["AUTO · SCANNING"] = "АВТО · СКАН",
  ["AUTOMATION & ALERTS"] = "АВТОМАТИКА И ОПОВЕЩЕНИЯ",
  ["Auction House did not answer — press Refresh"] = "Аукцион не ответил — нажмите Refresh",
  ["Auction House is not open"] = "Аукцион не открыт",
  ["Auto-scan on next AH visit"] = "Автоскан при следующем визите на АД",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Авто: держит Full Scan включённым постоянно и мгновенно уступает, когда вы покупаете, ",
  ["Avoid"] = "Избегать",
  ["Background check"] = "Фоновая проверка",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Точка безубыточности — самая низкая цена, которая после комиссии всё ещё возвращает вашу себестоимость. Ниже — убыток.",
  ["Bundled %s data"] = "Встроенные данные %s",
  ["Bundled data"] = "Встроенные данные",
  ["Buy"] = "Купить",
  ["Buy %d × %s for %s"] = "Купить %d × %s за %s",
  ["CANCEL %d"] = "ОТМЕНИТЬ %d",
  ["CANCEL LOT?"] = "ОТМЕНИТЬ ЛОТ?",
  ["CANCELLING…"] = "ОТМЕНА…",
  ["CONFIRM"] = "ПОДТВЕРДИТЬ",
  ["CONFIRM PURCHASE"] = "ПОДТВЕРДИТЬ ПОКУПКУ",
  ["COST / UNIT"] = "СЕБЕСТ. / ШТ",
  ["Cancel"] = "Отмена",
  ["Cancel lot?"] = "Отменить лот?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Отменить лот и потерять залог — нажмите ещё раз для подтверждения",
  ["Cancel timed out"] = "Время на отмену истекло",
  ["Cancelling forfeits the deposit, so this asks for a second click to confirm."] =
    "Отмена лишает залога, поэтому нужен второй клик для подтверждения.",
  ["Cancelling lot…"] = "Отменяем лот…",
  ["Cancels this live auction. It does NOT relist it: the deposit is forfeit, and the cancelled items come back by mail, not straight into your bags."] =
    "Отменяет этот активный лот. Заново он НЕ выставляется: залог теряется, а снятые предметы приходят почтой, а не сразу в сумки.",
  ["Cannot post this position"] = "Нельзя выставить эту позицию",
  ["Cannot remove this entry"] = "Нельзя удалить эту запись",
  ["Cannot repost this lot"] = "Нельзя перевыставить этот лот",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Более дешёвые лоты ещё есть, но при этой скорости их разберут за часы.",
  ["Check"] = "Проверить",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Проверка пересчитывает это по живой книге заявок, прежде чем тронется золото, и может дать меньше — или отказать — если рынок сдвинулся после последнего импорта.",
  ["Checked: %d of the top %d on screen"] = "Проверено: %d из %d верхних на экране",
  ["Checking prices…"] = "Проверяем цены…",
  ["Checking this item's price…"] = "Проверяем цену этого предмета…",
  ["Click Confirm to post"] = "Нажмите Confirm, чтобы выставить",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Ещё один клик отменит активный лот. Заново он не выставляется: залог теряется, а предметы придут почтой, а не сразу в сумки.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Ещё один клик удалит эту введённую вручную себестоимость навсегда.",
  ["Close"] = "Закрыть",
  ["Companion sync rejected:"] = "Синхронизация Companion отклонена:",
  ["Confirm"] = "Подтвердить",
  ["Confirm the cancel"] = "Подтвердить отмену",
  ["Confirm the removal"] = "Подтвердить удаление",
  ["Cost per unit"] = "Себестоимость за штуку",
  ["Cost unknown for %d of %d"] = "Себестоимость неизвестна для %d из %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Стоит больше, чем позволяет ваш лимит на одну покупку.",
  ["Could not find the queue's next item to post — try again"] =
    "Не нашли следующий предмет в очереди на выставление — попробуйте ещё раз",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Не нашли следующий лот в очереди на отмену — попробуйте ещё раз",
  ["DEAL THRESHOLDS"] = "ПОРОГИ СДЕЛОК",
  ["DISC"] = "СКИДКА",
  ["DISPLAY"] = "ОТОБРАЖЕНИЕ",
  ["DONE"] = "ГОТОВО",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Удаляет только себестоимость, введённую вручную в «Указать цену», — но не покупку, которую GoldCap поймал сам или сопоставил с почтой.",
  ["Discount"] = "Скидка",
  ["Discount vs market value from your GoldCap import"] =
    "Скидка от рыночной стоимости из вашего импорта GoldCap",
  ["Dump-trend cap %"] = "Порог падающего тренда %",
  ["Duration"] = "Срок",
  ["ENTRY AVG"] = "СРЕДНИЙ ВХОД",
  ["EST. PROFIT AFTER AH CUT"] = "ОРИЕНТ. ПРИБЫЛЬ ПОСЛЕ КОМИССИИ",
  ["Enlarge the window to see details"] = "Увеличьте окно, чтобы видеть детали",
  ["Enter a whole quantity"] = "Введите целое количество",
  ["Enter an exact positive cost"] = "Введите точную положительную себестоимость",
  ["Entry price (avg fill)"] = "Цена входа (среднее исполнение)",
  ["Entry total"] = "Всего на входе",
  ["Est. profit"] = "Ориент. прибыль",
  ["FIFO allocations"] = "Распределение FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Получаем свежую цену для предмета — нажмите Post ещё раз через мгновение",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Получаем свежую цену для лота — нажмите Repost ещё раз через мгновение",
  ["Finish the pending post first"] = "Сначала завершите текущее выставление",
  ["Finish the pending post or repost first"] =
    "Сначала завершите текущее выставление или перевыставление",
  ["Font scale"] = "Масштаб шрифта",
  ["Full pass over them: %.1fs"] = "Полный проход по ним: %.1fс",
  ["Full pass over them: measuring..."] = "Полный проход по ним: измеряем...",
  ["GOOD = solid discount + profit"] = "GOOD = хорошая скидка + прибыль",
  ["GOOD — min discount %"] = "GOOD — минимальная скидка %",
  ["GOOD — min sold/day"] = "GOOD — минимум продаж в день",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap не может точно определить, какой это стек в сумке",
  ["GoldCap data age"] = "Возраст данных GoldCap",
  ["GoldCap re-checks the top "] = "GoldCap перепроверяет верхние ",
  ["GoldCap value"] = "Оценка GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Импорт цен реалма",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "Что GoldCap советует по этому предмету и по какой цене.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: проверено вживую -- покупать безопасно",
  ["Gone"] = "Ушёл",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Серый цвет означает, что котировка устарела; Post и Repost обновят её перед действием.",
  ["HIDDEN 0"] = "СКРЫТО 0",
  ["HIDE DETAILS ▾"] = "СКРЫТЬ ДЕТАЛИ ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = большая скидка + высокая прибыль + подтверждённые продажи/день",
  ["HOT — min discount %"] = "HOT — минимальная скидка %",
  ["HOT — min sold/day"] = "HOT — минимум продаж в день",
  ["Held back from cancelling"] = "Придержано от отмены",
  ["Held back from the queue"] = "Придержано из очереди",
  ["ITEM"] = "ПРЕДМЕТ",
  ["Import"] = "Импорт",
  ["Import failed:"] = "Импорт не удался:",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Установите бесплатный GoldCap Companion, чтобы цены обновлялись сами (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Это то, что нужно перебить, чтобы продать быстро — а не то, сколько предмет стоит. Один спешащий продавец может опустить цену намного ниже стоимости, и GoldCap не пойдёт за ним вниз: смотрите WHAT TO DO, чтобы увидеть цену, по которой он действительно выставит.",
  ["It will list stock GoldCap never saw you buy — not knowing what something cost is a reason to report the profit as unknown, not a reason to refuse to sell it."] =
    "Выставится и то, покупки чего GoldCap не видел: незнание себестоимости — повод показать прибыль как неизвестную, а не повод отказаться продавать.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Себестоимость не выдумывается из рыночной цены — пока вы её не введёте, прибыль останется неизвестной.",
  ["Item"] = "Предмет",
  ["Item %d"] = "Предмет %d",
  ["LISTED"] = "ВЫСТАВЛЕНО",
  ["LIVE VERDICT · CHECKING"] = "ЖИВОЙ ВЕРДИКТ · ПРОВЕРКА",
  ["LIVE VERDICT · REFUSED"] = "ЖИВОЙ ВЕРДИКТ · ОТКАЗ",
  ["LIVE VERDICT · SAFE"] = "ЖИВОЙ ВЕРДИКТ · БЕЗОПАСНО",
  ["Language"] = "Язык",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Язык изменён. Введите /reload, чтобы применить его везде.",
  ["Last result: %ds ago"] = "Последний результат: %dс назад",
  ["Last result: none yet this visit"] = "Последний результат: пока не было в этот визит",
  ["Listed"] = "Выставлено",
  ["Listed at %s — far below market. Repost."] =
    "Выставлено за %s — намного ниже рынка. Перевыставьте.",
  ["Listed value"] = "Выставлено на сумму",
  ["Listings"] = "Лотов",
  ["Lists what is sitting in your bags at the price shown under WHAT TO DO."] =
    "Выставляет то, что лежит в сумках, по цене из колонки ЧТО ДЕЛАТЬ.",
  ["Lot cancelled; wait for it to return to bags"] =
    "Лот отменён; дождитесь его возврата в сумки",
  ["MARKET / UNIT"] = "РЫНОК / ШТ",
  ["Market per unit"] = "Рынок за штуку",
  ["Market reference"] = "Рыночный ориентир",
  ["Max wallet per buy %"] = "Макс. доля кошелька на покупку %",
  ["Min profit per buy (gold)"] = "Минимальная прибыль с покупки (золото)",
  ["Missing cost"] = "Нет себестоимости",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "ЕЩЁ НЕ НА GOLDCAP.GG — СИНХРОНИЗИРУЕТСЯ ПОСЛЕ /RELOAD ИЛИ ВЫХОДА",
  ["NOTHING TO CANCEL"] = "НЕЧЕГО ОТМЕНЯТЬ",
  ["NOTHING TO POST"] = "НЕЧЕГО ВЫСТАВЛЯТЬ",
  ["Needs a live price check before it can be bought."] =
    "Перед покупкой нужна живая проверка цены.",
  ["No deals passed the safety checks right now."] =
    "Сейчас ни одна сделка не прошла проверок безопасности.",
  ["No deals to show -- and no realm prices yet."] = "Сделок нет -- и цен реалма пока тоже.",
  ["No deals yet."] = "Сделок пока нет.",
  ["No exact auction key"] = "Нет точного ключа аукциона",
  ["No exact bag stack"] = "Нет точного стека в сумке",
  ["No exact bag variant"] = "Нет точного варианта в сумке",
  ["No live listings came back for this item."] =
    "По этому предмету не пришло ни одного живого лота.",
  ["No safe resale price could be worked out."] =
    "Безопасную цену перепродажи вычислить не удалось.",
  ["No sales data for this item."] = "Нет данных о продажах этого предмета.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Продаж ещё не записано -- откройте почту с включённым GoldCap",
  ["Not enough units on the Auction House to fill that quantity."] =
    "На аукционе не хватает единиц, чтобы набрать это количество.",
  ["Not in your bags or listed — mail or bank?"] =
    "Нет в сумках и не выставлено — почта или банк?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Нет под рукой — запас в почте, банке или на другом персонаже",
  ["Nothing is being held back."] = "Ничего не придержано.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "После этой покупки не останется того, во что продавать, — цены выхода нет.",
  ["Nothing listed on the AH right now"] = "Сейчас на аукционе ничего не выставлено",
  ["Nothing queued to cancel"] = "В очереди на отмену ничего нет",
  ["Nothing queued to post"] = "В очереди на выставление ничего нет",
  ["Nothing to remove"] = "Нечего удалять",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "НА GOLDCAP.GG — ПОСЛЕДНИЕ %d ДНЕЙ",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "НА GOLDCAP.GG — ПОСЛЕДНИЕ %d ДНЕЙ, СВЕЖИЕ %d ИЗ %d",
  ["Once the mail arrives, list it again yourself at the new price -- from this same row."] =
    "Когда придёт почта, выставьте заново сами по новой цене — из этой же строки.",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Разовое сканирование всего аукциона постраничными запросами. Занимает примерно ",
  ["Open the Auction House first."] = "Сначала откройте аукцион.",
  ["Open the Auction House to begin scanning."] = "Откройте аукцион, чтобы начать сканирование.",
  ["Open the deals board. /gc for commands."] = "Открыть доску сделок. /gc — команды.",
  ["POST %d"] = "ВЫСТАВИТЬ %d",
  ["POSTING"] = "ВЫСТАВЛЕНИЕ",
  ["POSTING…"] = "ВЫСТАВЛЯЕМ…",
  ["PRICE"] = "ЦЕНА",
  ["PRICE ROSE %.1fx"] = "ЦЕНА ВЫРОСЛА В %.1fx",
  ["PRICING %d/%d"] = "ЦЕНЫ %d/%d",
  ["PRICING…"] = "ЦЕНЫ…",
  ["PROFIT"] = "ПРИБЫЛЬ",
  ["PROFIT / UNIT"] = "ПРИБЫЛЬ / ШТ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Привяжите или обновите GoldCap Companion, чтобы видеть прибыль с goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Вставьте строку своего реалма с goldcap.gg и нажмите Import.",
  ["Per-unit price of this auction"] = "Цена за одну штуку в этом лоте",
  ["Position scope changed"] = "Область позиции изменилась",
  ["Positions without a cost or a live price are excluded."] =
    "Позиции без себестоимости или живой цены не учтены.",
  ["Post"] = "Выставить",
  ["Post confirmation expired"] = "Подтверждение выставления просрочено",
  ["Post the next queued item"] = "Выставить следующий предмет из очереди",
  ["Posting failed"] = "Выставление не удалось",
  ["Posting timed out"] = "Время на выставление истекло",
  ["Posting unavailable"] = "Выставление недоступно",
  ["Posting…"] = "Выставляем…",
  ["Press Full Scan to find deals."] = "Нажмите Full Scan, чтобы найти сделки.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Нажмите Scan, чтобы разово обойти весь аукцион, или Auto, чтобы сканировать постоянно.",
  ["Previous removal selection cleared"] = "Прошлый выбор для удаления сброшен",
  ["Previous repost selection cleared"] = "Прошлый выбор для перевыставления сброшен",
  ["Price"] = "Цена",
  ["Priced from bundled sample data, not from your realm."] =
    "Цена из вложенного примера данных, а не с вашего реалма.",
  ["Prices up to date"] = "Цены актуальны",
  ["Prices up to date · %d did not answer"] = "Цены актуальны · %d не ответили",
  ["Pricing %d/%d…"] = "Оцениваем %d/%d…",
  ["Pricing…"] = "Оцениваем…",
  ["Profit"] = "Прибыль",
  ["Profit per unit"] = "Прибыль за штуку",
  ["Profit tracking is a goldcap.gg Pro feature"] = "Учёт прибыли — функция goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "В этой сборке покупки отключены.",
  ["QTY"] = "КОЛ-ВО",
  ["Quantity exceeds missing units"] = "Количество превышает недостающие единицы",
  ["Quantity is capped by how fast this item actually sells."] =
    "Количество ограничено тем, как быстро предмет реально продаётся.",
  ["REALIZED PROFIT"] = "РЕАЛИЗОВАННАЯ ПРИБЫЛЬ",
  ["REFRESH"] = "ОБНОВИТЬ",
  ["RESET WINDOW"] = "СБРОСИТЬ ОКНО",
  ["Reason"] = "Причина",
  ["Refresh"] = "Обновить",
  ["Refresh waiting for prior result"] = "Обновление ждёт предыдущий результат",
  ["Refreshing listings…"] = "Обновляем лоты…",
  ["Refused so far: %d"] = "Отклонено на данный момент: %d",
  ["Removal confirmation expired"] = "Подтверждение удаления просрочено",
  ["Remove"] = "Удалить",
  ["Remove this cost"] = "Удалить эту себестоимость",
  ["Remove?"] = "Удалить?",
  ["Removed"] = "Удалено",
  ["Removed %d entries"] = "Удалено записей: %d",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Удаляет все введённые вручную покупки в этой группе -- нажмите ещё раз для подтверждения",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Удаляет эту введённую вручную покупку -- нажмите ещё раз для подтверждения",
  ["Repost"] = "Перевыставить",
  ["Repost confirmation expired"] = "Подтверждение перевыставления просрочено",
  ["Right-click to stop watching this item"] =
    "Правый клик, чтобы перестать следить за предметом",
  ["Right-click to watch this item closely"] =
    "Правый клик, чтобы пристально следить за предметом",
  ["SAFETY"] = "БЕЗОПАСНОСТЬ",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "СОХРАНЯЕТСЯ СРАЗУ · ESC ИЛИ DONE, ЧТОБЫ ЗАКРЫТЬ",
  ["SCAN"] = "СКАН",
  ["SCANNING…"] = "СКАНИРУЕМ…",
  ["SESSION %s%s · %d BUYS"] = "СЕССИЯ %s%s · %d ПОКУПОК",
  ["SHOW DETAILS ▸"] = "ПОКАЗАТЬ ДЕТАЛИ ▸",
  ["STRESS EXIT"] = "СТРЕСС-ВЫХОД",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = скидка настолько велика, что это скорее обман или ошибочная цена рынка",
  ["Sales are costed from your oldest units first"] =
    "Продажи списываются сначала со старейших единиц",
  ["Sell-through"] = "Выкупаемость",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Продаётся слишком редко — будете держать его долго.",
  ["Set cost"] = "Задать себестоимость",
  ["Settings"] = "Настройки",
  ["Sold per day"] = "Продаж в день",
  ["Sold/day"] = "Продаж в день",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Сортируйте по нему, чтобы решить, что проверить первым, а не что покупать.",
  ["Sound on HOT deal"] = "Звук на сделке HOT",
  ["Source age"] = "Возраст источника",
  ["Spike-trend threshold %"] = "Порог всплеска цены %",
  ["Status"] = "Статус",
  ["Stress exit unit"] = "Цена стресс-выхода",
  ["Stress profit"] = "Стресс-прибыль",
  ["TIER"] = "КЛАСС",
  ["TOTAL"] = "ИТОГО",
  ["TREND"] = "ТРЕНД",
  ["Tell GoldCap what you actually paid for these units."] =
    "Укажите, сколько вы на самом деле заплатили за эти единицы.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "Аукцион не назвал залог, поэтому стоимость неизвестна.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Companion синхронизируется, но аддон не смог прочитать то, что он записал:",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Кнопка становится нажимаемой не сразу, поэтому случайный двойной клик её не сработает.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Самая дешёвая цена, которую сейчас просит КТО-ТО ДРУГОЙ, по живому запросу к аукциону. Ваши собственные лоты исключены, поэтому число никогда не гонится само за собой вниз.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Данные по этому предмету битые, и GoldCap отказывается гадать.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "Бесплатное приложение Companion само обновляет ваши цены и синхронизирует продажи. Скопируйте ссылку (Ctrl+C) и откройте её в браузере:",
  ["The liquidity data is not reliable enough to act on."] =
    "Данные о ликвидности недостаточно надёжны, чтобы на них действовать.",
  ["The market value is an estimate, not a measurement."] =
    "Рыночная стоимость — это оценка, а не измерение.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Данным о ценах больше трёх часов. Синхронизируйте Companion и сделайте /reload — аддон читает свои данные только при загрузке интерфейса.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Цена падает; заходить в неё — это и есть способ застрять.",
  ["The price is the last one GoldCap fetched, at most 45 seconds old — not a fresh check made at the moment you click. If it changes between arming the post and confirming it, the post is abandoned rather than sent at the old price."] =
    "Цена — последняя, которую получил GoldCap, не старше 45 секунд, а не свежая проверка в момент клика. Если она изменится между подготовкой и подтверждением, выставление отменяется, а не уходит по старой цене.",
  ["The price moved and the trade is no longer safe."] =
    "Цена сдвинулась, и сделка больше не безопасна.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Прибыль не дотягивает до вашего минимума после 5% комиссии и залога.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Отменить нельзя. Первый клик просит второй для подтверждения.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Это предмет реалма, а GoldCap проверяет только цены товаров.",
  ["Tier"] = "Класс",
  ["Too few sellers to read a real price."] =
    "Слишком мало продавцов, чтобы прочитать настоящую цену.",
  ["Too little of what is listed actually sells."] =
    "Из выставленного реально продаётся слишком мало.",
  ["Too little price history to trust the value."] =
    "Слишком мало истории цен, чтобы верить этой стоимости.",
  ["Total cost to buy this auction"] = "Полная стоимость покупки этого лота",
  ["UNIT"] = "ЗА ШТ",
  ["Unit price"] = "Цена за штуку",
  ["Unknown"] = "Неизвестно",
  ["Unknown item"] = "Неизвестный предмет",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "«Неизвестно» значит, что себестоимость заполнена не вся — допишите её через «Указать цену».",
  ["WATCH (computed SAFE)"] = "WATCH (расчёт БЕЗОПАСНО)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = со скидкой, но ликвидность не подтверждена или прибыль мала",
  ["WHAT TO DO"] = "ЧТО ДЕЛАТЬ",
  ["WHEN"] = "КОГДА",
  ["Waiting for Auction House…"] = "Ждём аукцион…",
  ["Waiting for a live price"] = "Ждём живую цену",
  ["Waiting for the Auction House…"] = "Ждём аукцион…",
  ["Waiting for the purchase to finish…"] = "Ждём завершения покупки…",
  ["Wall absorb window (hours)"] = "Окно поглощения стены (часы)",
  ["Watching closely: %d item%s"] = "Пристально следим: %d предмет%s",
  ["Watching — pinned, but not a deal right now"] =
    "Следим — закреплено, но сейчас это не сделка",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Сколько на самом деле стоила одна штука, в среднем по ещё не проданным покупкам.",
  ["What to do"] = "Что делать",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Сколько остаётся с одной штуки при продаже по рынку: цена продажи минус 5% комиссии аукциона минус ваша себестоимость.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Во сколько складываются ваши активные лоты этого предмета по текущей цене.",
  ["Window position & size"] = "Позиция и размер окна",
  ["Worth doing when someone has undercut you; not worth it if the price barely moved."] =
    "Стоит делать, когда вас перебили по цене; не стоит, если цена почти не сдвинулась.",
  ["You paid"] = "Вы заплатили",
  ["a discount this extreme usually means the market value is wrong, not that this is a bargain"] =
    "такая огромная скидка обычно означает ошибочную рыночную стоимость, а не выгодную покупку",
  ["auto off"] = "авто выключено",
  ["auto-synced %dh ago"] = "автосинхронизация %dч назад",
  ["auto-synced data for %s loaded (%s old)"] =
    "автосинхронизированные данные для %s загружены (возраст %s)",
  ["auto-synced data stale -- /goldcap import"] =
    "автосинхронизированные данные устарели -- /goldcap import",
  ["auto: paused"] = "авто: пауза",
  ["big buy"] = "крупная покупка",
  ["bought %d x item %d"] = "куплено %d x предмет %d",
  ["bought %d x item %d after AH close"] = "куплено %d x предмет %d после закрытия аукциона",
  ["buying commodity..."] = "покупаем товар...",
  ["checking live price..."] = "проверяем живую цену...",
  ["checking live safety..."] = "проверяем безопасность вживую...",
  ["commodity no longer available -- someone bought it out"] =
    "товара больше нет -- его уже выкупили",
  ["commodity purchase failed"] = "покупка товара не удалась",
  ["confirmed commodity purchase failed after AH close"] =
    "подтверждённая покупка товара не удалась после закрытия аукциона",
  ["confirming purchase..."] = "подтверждаем покупку...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "себестоимость неполная -- задайте её, чтобы получить совет по перевыставлению",
  ["cost unknown"] = "себестоимость неизвестна",
  ["data from goldcap.gg · synced %s ago"] = "данные с goldcap.gg · синхронизировано %s назад",
  ["due -- will be asked next pass"] = "очередь -- спросим следующим проходом",
  ["finish the pending buy first"] = "сначала завершите текущую покупку",
  ["full scan already in progress"] = "полное сканирование уже идёт",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "полное сканирование завершено: %d сделок%s из %d групп предметов%s%s",
  ["full scan interrupted -- confirm your purchase"] =
    "полное сканирование прервано -- подтвердите покупку",
  ["full scan stalled -- press Full Scan to retry"] =
    "полное сканирование застряло -- нажмите Full Scan ещё раз",
  ["full scan stalled -- retrying shortly"] = "полное сканирование застряло -- скоро повторим",
  ["gone / price changed"] = "исчезло / цена изменилась",
  ["identity unresolved (variant item -- not priced by design)"] =
    "не удалось определить (вариативный предмет -- цена не считается намеренно)",
  ["import %dh old"] = "импорту %dч",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "импорт устарел -- /goldcap import или /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "импортировано %d предметов для %s (%s) — цены теперь живые.",
  ["in the mail"] = "в почте",
  ["item %d"] = "предмет %d",
  ["item %d: %s"] = "предмет %d: %s",
  ["item variant unresolved"] = "вариант предмета не определён",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "за 24 ч — %d продаж, %s валовая, %s комиссия аукциона, %d покупок, %s потрачено",
  ["listing gone -- already bought out or price changed"] =
    "лот исчез -- уже выкуплен или цена изменилась",
  ["listing gone -- bought out or repriced"] = "лот пропал — выкуплен или переставлен по цене",
  ["live safety confirmed -- click Buy to purchase"] =
    "безопасность подтверждена вживую -- нажмите Buy, чтобы купить",
  ["live verification required"] = "требуется живая проверка",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "ручной импорт -- Companion обновляет это сам: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "нужна свежая цена -- нажмите Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "сервер не подтвердил -- покупка всё равно могла пройти, проверьте почту. Закрытие этого окна её не отменит.",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "цен пока нет -- /goldcap companion или /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "подтверждение покупки не получено -- Cancel и повторите",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "продаж ещё не записано — откройте почту с включённым GoldCap, и они будут прочитаны из счетов",
  ["no stock in bags or listed -- nothing to price for"] =
    "нет запаса в сумках и на аукционе -- нечего оценивать",
  ["none"] = "нет",
  ["not enough gold -- total %s, you have %s"] = "не хватает золота -- всего %s, у вас %s",
  ["not enough gold for this quote -- Cancel"] = "не хватает золота по этой цене -- Cancel",
  ["not ready to cancel"] = "не готово к отмене",
  ["not ready to post"] = "не готово к выставлению",
  ["nothing listed"] = "ничего не выставлено",
  ["of %d"] = "из %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "или вставьте строку с goldcap.gg через /goldcap import.",
  ["over %d position%s"] = "по %d позициям%s",
  ["paid sale unresolved"] = "оплаченная продажа не сопоставлена",
  ["placing bid..."] = "делаем ставку...",
  ["price confirmed -- click Buy to purchase"] = "цена подтверждена -- нажмите Buy, чтобы купить",
  ["price rose %.1fx — still safe, confirm"] =
    "цена выросла в %.1fx — всё ещё безопасно, подтвердите",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "загружены цены %s (%s), а играете вы в %s — все скидки и прибыль считаются по чужому рынку",
  ["purchase canceled"] = "покупка отменена",
  ["purchase complete"] = "покупка совершена",
  ["purchase identity unresolved"] = "покупка не опознана",
  ["purchase pending exact cost"] = "покупка ждёт точной себестоимости",
  ["purchase total unavailable — inspect mailbox"] =
    "общая сумма покупки недоступна — проверьте почту",
  ["quote %s -- click Confirm to buy"] = "котировка %s -- нажмите Confirm, чтобы купить",
  ["quote %ss ago"] = "котировка %sс назад",
  ["quote expired -- Refresh to re-check the price"] =
    "котировка просрочена -- Refresh, чтобы перепроверить цену",
  ["recent sales (newest first):"] = "последние продажи (свежие сверху):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "регион %s — встроено: %d предметов (%s), импортировано: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "регион исправлен в %d записях; %d продаж сопоставлено со своим запасом",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "перевыставление сейчас зафиксирует убыток или застой -- придержите",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "удалено %d дублирующих%s записей покупки, оставленных ошибкой сканирования почты",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "удалено %d дублирующих%s записей продажи, оставленных ошибкой сканирования почты",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    "с. Отклонённые строки скрыты. Покупка всегда остаётся вашим кликом.",
  ["sale name ambiguous"] = "имя в продаже неоднозначно",
  ["sale proceeds pending"] = "выручка ожидается",
  ["scanned %d listings over %d passes"] = "просканировано %d лотов за %d проходов",
  ["scanning auction house..."] = "сканируем аукцион...",
  ["scanning… %d results · %d deals%s"] = "сканируем… %d результатов · %d сделок%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "поищите на аукционе сами или проверьте почту. Клик переключает.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "продаётся %s/день",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "сессия: %d перехватов, потрачено %s, ~%s ориент. прибыли",
  ["sniped (listing changed on rescan)"] = "перехвачено (лот изменился при пересканировании)",
  ["sniped for "] = "снайпнуто за ",
  ["starting full scan..."] = "начинаем полное сканирование...",
  ["stopped watching %s"] = "перестали следить за %s",
  ["the Companion wrote prices this addon could not read --"] =
    "Companion записал цены, которые аддон не смог прочитать --",
  ["the import failed (%s)"] = "импорт не удался (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["unknown evidence"] = "неизвестное подтверждение",
  ["waiting for previous commodity purchase to settle"] =
    "ждём завершения предыдущей покупки товара",
  ["waiting for previous search result to settle"] = "ждём завершения предыдущего поиска",
  ["waiting for server... full scan will start automatically"] =
    "ждём сервер... полное сканирование начнётся само",
  ["watching %s closely -- re-checked every few seconds"] =
    "пристально следим за %s -- перепроверка каждые несколько секунд",
  ["would sell at a loss"] = "продалось бы в убыток",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "вы ещё не импортировали цены реалма -- установите GoldCap Companion (/goldcap companion) или вставьте строку с goldcap.gg (/goldcap import).",
  ["you should clear about %s"] = "вы должны получить примерно %s",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "в вашем клиенте игры нет шрифта для этого языка — текст будет отображаться пустыми квадратами",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "вашему импорту %d часов -- цены могут быть неверными. Вставьте свежую строку с goldcap.gg (/goldcap import).",
  ["» needs price"] = "» нужна цена",
  ["×%d in bags"] = "×%d в сумках",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d в ваших сумках · Post выставит %d из них, самый большой стек",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d в ваших сумках · нет стека, который GoldCap может точно определить",
  ["×%d in your bags, ready to list"] = "×%d в ваших сумках, готовы к выставлению",
  ["×%d listed"] = "×%d выставлено",
  ["×%d listed at %s each"] = "×%d выставлено по %s за штуку",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · куплено %s · %s · %s",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ рыночная стоимость goldcap.gg — живой котировки пока нет",
}
