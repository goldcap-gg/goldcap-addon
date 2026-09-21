local _, GC = ...

-- Russian. Terminology follows apps/web/messages/ru.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ruRU = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d по %s за штуку  (%s всего, %s комиссия)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion обновляет это сам: /goldcap companion.",
  [" · %d hidden"] = " · скрыто %d",
  [" · %d keys"] = " · ключей: %d",
  [" · below cost"] = " · ниже себестоимости",
  [" · identity unresolved"] = " · позиция не опознана",
  [" · stale %ds"] = " · устарело %dс",
  [" — Check again"] = " — проверьте ещё раз",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — команды: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (или коротко /gc)",
  ["%d (whole lot)"] = "%d (весь лот)",
  ["%d days"] = "%d дн.",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d сделок с последнего сканирования -- Full Scan, чтобы обновить",
  ["%d filtered out as hard to resell"] = "%d отсеяно как трудные для перепродажи",
  ["%d held back"] = "%d придержано",
  ["%d held back from posting"] = "%d придержано от выставления",
  ["%d hidden -- the live check refused them"] = "%d скрыто -- живая проверка их отклонила",
  ["%d in %d lots"] = "%d в %d лотах",
  ["%d in 1 lot"] = "%d в 1 лоте",
  ["%d lots, %s asked"] = "%d лотов, просят %s",
  ["%d missing"] = "%d не хватает",
  ["%d partial"] = "%d частично",
  ["%d prices in one request · books still loading"] = "%d цен одним запросом · стаканы догружаются",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d отклонено живой проверкой -- нажмите \"HIDDEN %d\" вверху, чтобы посмотреть",
  ["%d sales · %s proceeds · %s in the mail"] = "%d продаж · %s выручка · %s в почте",
  ["%d units"] = "%d шт.",
  ["%d units · %d prices"] = "%d шт. · %d цен",
  ["%d without a price"] = "%d без цены",
  ["%d without cost"] = "%d без себестоимости",
  ["%d · %d/%d covered"] = "%d · %d/%d покрыто",
  ["%d/%d covered"] = "%d/%d покрыто",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s за штуку    всего %s -> %s",
  ["%s after the AH cut"] = "%s после комиссии",
  ["%s ahead"] = "%s впереди",
  ["%s under you"] = "%s дешевле вас",
  ["%s — %d unit%s without a cost"] = "%s — %d единиц%s без себестоимости",
  [", %d hidden as unsellable"] = ", скрыто %d как непродаваемые",
  ["1 lot, %s asked"] = "1 лот, просят %s",
  ["24h trend"] = "Тренд за 24ч",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Прочерк значит, что себестоимость известна не по всем единицам — из рыночной цены она никогда не выдумывается.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Ориентир, а не обещание: перепродажа по 95% импортированной рыночной стоимости, на количество, которое одобрит сама проверка.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Если несколько покупок свёрнуты в одну строку, удалятся они все.",
  ["AH answered empty %ds ago"] = "Аукцион ответил пусто %dс назад",
  ["ASKING"] = "ЗАПРОС",
  ["AT MARKET"] = "ПО РЫНКУ",
  ["AUTO"] = "АВТО",
  ["AUTO · PAUSED: "] = "АВТО · ПАУЗА: ",
  ["AUTO · SCANNING"] = "АВТО · СКАН",
  ["AUTOMATION & ALERTS"] = "АВТОМАТИКА И ОПОВЕЩЕНИЯ",
  ["AVOID"] = "ИЗБЕГАТЬ",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Выше этого роста за 24 часа рыночная стоимость считается всплеском и занижается.",
  ["Asks for a second click to confirm."] = "Требует второй клик для подтверждения.",
  ["Auction House did not answer — press Refresh"] = "Аукцион не ответил — нажмите Refresh",
  ["Auction House is not open"] = "Аукцион не открыт",
  ["Auto-scan on next AH visit"] = "Автоскан при следующем визите на АД",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Авто: держит Full Scan включённым постоянно и мгновенно уступает, когда вы покупаете, поищите на аукционе сами или проверьте почту. Клик переключает.",
  ["Avoid"] = "Избегать",
  ["BOOKS %d/%d"] = "СТАКАНЫ %d/%d",
  ["BRAKES"] = "ТОРМОЗА",
  ["BUY — unverified"] = "КУПИТЬ — без проверки",
  ["Background check"] = "Фоновая проверка",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Точка безубыточности — самая низкая цена, которая после комиссии всё ещё возвращает вашу себестоимость. Ниже — убыток.",
  ["Bundled %s data"] = "Встроенные данные %s",
  ["Bundled data"] = "Встроенные данные",
  ["Buy"] = "Купить",
  ["Buy less"] = "Купить меньше",
  ["CANCEL %d"] = "ОТМЕНИТЬ %d",
  ["CANCEL LOT?"] = "ОТМЕНИТЬ ЛОТ?",
  ["CANCELLING…"] = "ОТМЕНА…",
  ["CONFIRM"] = "ПОДТВЕРДИТЬ",
  ["COST"] = "ЗАКУП",
  ["COST / UNIT"] = "СЕБЕСТ. / ШТ",
  ["Can't price this"] = "Цену не оценить",
  ["Cancel"] = "Отмена",
  ["Cancel lot"] = "Отменить",
  ["Cancel lot?"] = "Отменить?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Отменить лот и потерять залог — нажмите ещё раз для подтверждения",
  ["Cancel timed out"] = "Время на отмену истекло",
  ["Cancelling lot…"] = "Отменяем лот…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Отменяет этот активный лот — заново он НЕ выставляется. Залог теряется, предметы приходят почтой; когда придут, выставьте их заново из этой же строки.",
  ["Cannot post this position"] = "Нельзя выставить эту позицию",
  ["Cannot remove this entry"] = "Нельзя удалить эту запись",
  ["Cannot repost this lot"] = "Нельзя перевыставить этот лот",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Ограничено скоростью продаж, а не вашим золотом.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Более дешёвые лоты ещё есть, но при этой скорости их разберут за часы.",
  ["Check"] = "Проверка",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Проверка пересчитывает это по живой книге заявок, прежде чем тронется золото, и может дать меньше — или отказать — если рынок сдвинулся после последнего импорта.",
  ["Checked against the live order book a moment ago."] =
    "Только что сверено с живым стаканом заявок.",
  ["Checked: %d of the top %d on screen"] = "Проверено: %d из %d верхних на экране",
  ["Checking prices…"] = "Проверяем цены…",
  ["Checking this item's price…"] = "Проверяем цену этого предмета…",
  ["Checking..."] = "Проверяю...",
  ["Clear to buy"] = "Можно покупать",
  ["Click Confirm to post"] = "Нажмите Confirm, чтобы выставить",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Ещё один клик отменит активный лот. Заново он не выставляется: залог теряется, а предметы придут почтой, а не сразу в сумки.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Ещё один клик удалит эту введённую вручную себестоимость навсегда.",
  ["Close"] = "Закрыть",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "Companion сам обновляет цены — /goldcap companion",
  ["Companion sync rejected:"] = "Синхронизация Companion отклонена:",
  ["Confidence"] = "Достоверность",
  ["Confirm"] = "Подтвердить",
  ["Confirm the cancel"] = "Подтвердить отмену",
  ["Confirm the removal"] = "Подтвердить удаление",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Скопируйте ссылку (Ctrl+C) и откройте её в браузере:",
  ["Cost per unit"] = "Себестоимость за штуку",
  ["Cost unknown for %d of %d"] = "Себестоимость неизвестна для %d из %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Стоит больше, чем позволяет ваш лимит на одну покупку.",
  ["Could not find the queue's next item to post — try again"] =
    "Не нашли следующий предмет в очереди на выставление — попробуйте ещё раз",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Не нашли следующий лот в очереди на отмену — попробуйте ещё раз",
  ["DEFAULTS"] = "ПО УМОЛЧАНИЮ",
  ["DISC"] = "СКИДКА",
  ["DISPLAY"] = "ОТОБРАЖЕНИЕ",
  ["DONE"] = "ГОТОВО",
  ["Default listing length for the Sell tab."] = "Срок выставления по умолчанию для вкладки Продажа.",
  ["Default: %s"] = "По умолчанию: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Удаляет только себестоимость, введённую вручную в «Указать цену», — но не покупку, которую GoldCap поймал сам или сопоставил с почтой.",
  ["Discount"] = "Скидка",
  ["Discount vs market value from your GoldCap import"] =
    "Скидка от рыночной стоимости из вашего импорта GoldCap",
  ["Dump-trend cap %"] = "Порог падающего тренда %",
  ["Duration"] = "Срок",
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
  ["Free, sits in the tray, nothing to set up in game."] =
    "Бесплатный, живёт в трее, в игре ничего настраивать не нужно.",
  ["Full pass over them: %.1fs"] = "Полный проход по ним: %.1fс",
  ["Full pass over them: measuring..."] = "Полный проход по ним: измеряем...",
  ["GOLDCAP"] = "GOLDCAP",
  ["Gold tied up"] = "Заморожено золота",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap не может точно определить, какой это стек в сумке",
  ["GoldCap data age"] = "Возраст данных GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap перепроверяет верхние %d строк по живому аукциону примерно каждые %dс. Отклонённые строки скрыты. Покупка всегда остаётся вашим кликом.",
  ["GoldCap value"] = "Оценка GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Импорт цен реалма",
  ["GoldCap's"] = "от GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "Что GoldCap советует по этому предмету и по какой цене.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: проверено вживую -- покупать безопасно",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: ещё не проверено на живом аукционе",
  ["Gone"] = "Ушёл",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Серый цвет означает, что котировка устарела; Post и Repost обновят её перед действием.",
  ["HIDDEN 0"] = "СКРЫТО 0",
  ["HIDE DETAILS ▾"] = "СКРЫТЬ ДЕТАЛИ ▾",
  ["HOLDING %d"] = "ДЕРЖИМ %d",
  ["Held back from cancelling"] = "Придержано от отмены",
  ["Held back from the queue"] = "Придержано из очереди",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Сколько часов обычных продаж может держаться стена под вашей ценой выхода, прежде чем сделка будет отклонена.",
  ["ITEM"] = "ПРЕДМЕТ",
  ["If it clears"] = "Если продастся",
  ["Import"] = "Импорт",
  ["Import failed:"] = "Импорт не удался:",
  ["Import from goldcap.gg to arm the sniper"] = "Импортируйте данные с goldcap.gg, чтобы включить снайпер",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Установите бесплатный GoldCap Companion, чтобы цены обновлялись сами (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Это то, что нужно перебить, чтобы продать быстро — а не то, сколько предмет стоит. Один спешащий продавец может опустить цену намного ниже стоимости, и GoldCap не пойдёт за ним вниз: смотрите WHAT TO DO, чтобы увидеть цену, по которой он действительно выставит.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Себестоимость не выдумывается из рыночной цены — пока вы её не введёте, прибыль останется неизвестной.",
  ["Item"] = "Предмет",
  ["Item %d"] = "Предмет %d",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."] =
    "Предметы: снаряжение, питомцы и рецепты, оценённые по эталону региона из вашего импорта. Скорость продажи никогда не измеряется, поэтому они никогда не получают статус БЕЗОПАСНО -- покупать или нет, решать вам, и GoldCap проверяет их только пока эта доска открыта.",
  ["LISTED"] = "ВЫСТАВЛЕНО",
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
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "Выставляет то, что лежит в сумках, по цене из колонки ЧТО ДЕЛАТЬ: товар — всем объёмом, обычный предмет — одним стеком.",
  ["Live ask"] = "Цена в стакане",
  ["Lot cancelled; wait for it to return to bags"] =
    "Лот отменён; дождитесь его возврата в сумки",
  ["MARKET"] = "РЫНОК",
  ["MARKET / UNIT"] = "РЫНОК / ШТ",
  ["MATCH"] = "СРАВНЯТЬ",
  ["Market per unit"] = "Рынок за штуку",
  ["Market reference"] = "Рыночный ориентир",
  ["Max units per buy"] = "Макс. штук за одну покупку",
  ["Max wallet per buy %"] = "Макс. доля кошелька на покупку %",
  ["Min profit per buy (gold)"] = "Минимальная прибыль с покупки (золото)",
  ["Min return per buy %"] = "Мин. доходность покупки %",
  ["Missing cost"] = "Нет себестоимости",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "ЕЩЁ НЕ НА GOLDCAP.GG — СИНХРОНИЗИРУЕТСЯ ПОСЛЕ /RELOAD ИЛИ ВЫХОДА",
  ["NOT ON HAND %d"] = "НЕТ НА РУКАХ %d",
  ["NOTHING TO CANCEL"] = "НЕЧЕГО ОТМЕНЯТЬ",
  ["NOTHING TO POST"] = "НЕЧЕГО ВЫСТАВЛЯТЬ",
  ["Needs a live price check before it can be bought."] =
    "Перед покупкой нужна живая проверка цены.",
  ["Never spend more than this share of your gold on one purchase."] =
    "Никогда не тратить на одну покупку больше этой доли вашего золота.",
  ["No deals passed the safety checks right now."] =
    "Сейчас ни одна сделка не прошла проверок безопасности.",
  ["No deals to show -- and no realm prices yet."] = "Сделок нет -- и цен реалма пока тоже.",
  ["No deals yet."] = "Сделок пока нет.",
  ["No exact auction key"] = "Нет точного ключа аукциона",
  ["No exact bag stack"] = "Нет точного стека в сумке",
  ["No exact bag variant"] = "Нет точного варианта в сумке",
  ["No live listings came back for this item."] =
    "По этому предмету не пришло ни одного живого лота.",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "Для этого предмета ещё нет эталонной цены региона — импортируйте снова, когда goldcap.gg её опубликует.",
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
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Ни один лот не дотягивает до уровня предмета, на котором измерена эталонная цена.",
  ["Nothing listed on the AH right now"] = "Сейчас на аукционе ничего не выставлено",
  ["Nothing on this deck matches that search"] = "На этой вкладке ничего не подходит под поиск",
  ["Nothing queued to cancel"] = "В очереди на отмену ничего нет",
  ["Nothing queued to post"] = "В очереди на выставление ничего нет",
  ["Nothing to remove"] = "Нечего удалять",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "НА GOLDCAP.GG — ПОСЛЕДНИЕ %d ДНЕЙ",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "НА GOLDCAP.GG — ПОСЛЕДНИЕ %d ДНЕЙ, СВЕЖИЕ %d ИЗ %d",
  ["ON THE AUCTION HOUSE"] = "НА АУКЦИОНЕ",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Разовое сканирование всего аукциона постраничными запросами. Занимает примерно 15-60 секунд на загруженных реалмах. Без отката -- сканируйте когда угодно.",
  ["Open the Auction House first."] = "Сначала откройте аукцион.",
  ["Open the Auction House to begin scanning."] = "Откройте аукцион, чтобы начать сканирование.",
  ["Open the deals board. /gc for commands."] = "Открыть доску сделок. /gc — команды.",
  ["POST %d"] = "ВЫСТАВИТЬ %d",
  ["POSTING"] = "ВЫСТАВЛЕНИЕ",
  ["POSTING…"] = "ВЫСТАВЛЯЕМ…",
  ["PRICE"] = "ЦЕНА",
  ["PRICE ROSE %.1fx"] = "ЦЕНА ВЫРОСЛА В %.1fx",
  ["PRICED TOO LOW %d"] = "СЛИШКОМ ДЁШЕВО %d",
  ["PRICING %d/%d"] = "ЦЕНЫ %d/%d",
  ["PRICING…"] = "ЦЕНЫ…",
  ["PROFIT"] = "ПРИБЫЛЬ",
  ["PROFIT / UNIT"] = "ПРИБЫЛЬ / ШТ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Привяжите или обновите GoldCap Companion, чтобы видеть прибыль с goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Вставьте строку своего реалма с goldcap.gg и нажмите Import.",
  ["Per-unit price of this auction"] = "Цена за одну штуку в этом лоте",
  ["Play a sound when a checked deal turns SAFE."] =
    "Проигрывать звук, когда проверенная сделка становится SAFE.",
  ["Position scope changed"] = "Область позиции изменилась",
  ["Positions without a cost or a live price are excluded."] =
    "Позиции без себестоимости или живой цены не учтены.",
  ["Post"] = "Выставить",
  ["Post above the cheapest"] = "Выставлять выше самого дешёвого",
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
  ["Pricing paused while you use the Auction House"] = "Оценка на паузе, пока вы пользуетесь аукционом",
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
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "Отказать в покупке, если цена упала больше этого значения за последние 24 часа — она может падать и дальше.",
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
  ["Repost confirmation expired"] = "Подтверждение перевыставления просрочено",
  ["Right-click to stop watching this item"] =
    "Правый клик, чтобы перестать следить за предметом",
  ["Right-click to watch this item closely"] =
    "Правый клик, чтобы пристально следить за предметом",
  ["SAFE +%s"] = "БЕЗОПАСНО +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "БЕЗОПАСНО = живая проверка одобрила эту покупку с показанной прибылью",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "СОХРАНЯЕТСЯ СРАЗУ · ESC ИЛИ DONE, ЧТОБЫ ЗАКРЫТЬ",
  ["SCAN"] = "СКАН",
  ["SCANNING…"] = "СКАНИРУЕМ…",
  ["SESSION %s%s · %d BUYS"] = "СЕССИЯ %s%s · %d ПОКУПОК",
  ["SHOW DETAILS ▸"] = "ПОКАЗАТЬ ДЕТАЛИ ▸",
  ["Sales are costed from your oldest units first"] =
    "Продажи списываются сначала со старейших единиц",
  ["Search"] = "Поиск",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "Вкладка Продажа выставляет на одну ступень выше самой дешёвой заявки, если книга ордеров показывает такую же скорость продажи.",
  ["Sell-through"] = "Выкупаемость",
  ["Sellers"] = "Продавцов",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Продаётся слишком редко — будете держать его долго.",
  ["Set cost"] = "Затраты",
  ["Settings"] = "Настройки",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Пропустить покупку, если прибыль после комиссии аукциона меньше этой суммы.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Пропустить покупку, если прибыль меньше этой доли от уплаченной суммы.",
  ["Snapshot value"] = "Значение из снимка",
  ["Sold per day"] = "Продаж в день",
  ["Sold/day"] = "Продаж в день",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Сортируйте по нему, чтобы решить, что проверить первым, а не что покупать.",
  ["Sound on SAFE deal"] = "Звук на сделке SAFE",
  ["Source age"] = "Возраст источника",
  ["Spike-trend threshold %"] = "Порог всплеска цены %",
  ["Start scanning as soon as the auction house opens."] =
    "Начинать сканирование сразу при открытии аукционного дома.",
  ["Status"] = "Статус",
  ["Stress exit unit"] = "Цена стресс-выхода",
  ["Stress profit"] = "Стресс-прибыль",
  ["THE BOOK"] = "СТАКАН ЗАЯВОК",
  ["TOTAL"] = "ИТОГО",
  ["TREND"] = "ТРЕНД",
  ["Tell GoldCap what you actually paid for these units."] =
    "Укажите, сколько вы на самом деле заплатили за эти единицы.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "Аукцион не назвал залог, поэтому стоимость неизвестна.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Companion синхронизируется, но аддон не смог прочитать то, что он записал:",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "Доска оценила лот по импортированному снимку. Живой стакан этого не подтверждает.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Кнопка становится нажимаемой не сразу, поэтому случайный двойной клик её не сработает.",
  ["The cancel did not go through — the lot is still listed"] = "Отмена не прошла — лот всё ещё выставлен",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "Самый дешёвый лот уже недостаточно ниже эталонной цены.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Самая дешёвая цена, которую сейчас просит КТО-ТО ДРУГОЙ, по живому запросу к аукциону. Ваши собственные лоты исключены, поэтому число никогда не гонится само за собой вниз.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Данные по этому предмету битые, и GoldCap отказывается гадать.",
  ["The liquidity data is not reliable enough to act on."] =
    "Данные о ликвидности недостаточно надёжны, чтобы на них действовать.",
  ["The market value is an estimate, not a measurement."] =
    "Рыночная стоимость — это оценка, а не измерение.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Больше этого количества одна покупка не возьмёт. Скорость продаж товара может сделать его меньше.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Данным о ценах больше трёх часов. Синхронизируйте Companion и сделайте /reload — аддон читает свои данные только при загрузке интерфейса.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "Цена проверена. Скорость продажи нигде не измеряется, так что судить вам.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Цена падает; заходить в неё — это и есть способ застрять.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "Цена — последняя полученная, не старше 45 секунд. Если она изменится до подтверждения, выставление отменяется, а не уходит по старой цене.",
  ["The price moved and the trade is no longer safe."] =
    "Цена сдвинулась, и сделка больше не безопасна.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Прибыль не дотягивает до вашего минимума после 5% комиссии и залога.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Отменить нельзя. Первый клик просит второй для подтверждения.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Это предмет реалма, а GoldCap проверяет только цены товаров.",
  ["Too few sellers to read a real price."] =
    "Слишком мало продавцов, чтобы прочитать настоящую цену.",
  ["Too little of what is listed actually sells."] =
    "Из выставленного реально продаётся слишком мало.",
  ["Too little price history to trust the value."] =
    "Слишком мало истории цен, чтобы верить этой стоимости.",
  ["Total cost to buy this auction"] = "Полная стоимость покупки этого лота",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Введите цену в золоте или очистите поле, чтобы взять цену GoldCap",
  ["UNDERCUT"] = "НИЖЕ",
  ["UNDERCUT %d"] = "ПЕРЕБИТЫ %d",
  ["UNIT"] = "ЗА ШТ",
  ["Unit price"] = "Цена за штуку",
  ["Unknown"] = "Неизвестно",
  ["Unknown item"] = "Неизвестный предмет",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "«Неизвестно» значит, что себестоимость заполнена не вся — допишите её через «Указать цену».",
  ["VERDICT"] = "ВЕРДИКТ",
  ["Verdict"] = "Вердикт",
  ["WATCH"] = "СЛЕДИТЬ",
  ["WATCH (computed SAFE)"] = "WATCH (расчёт БЕЗОПАСНО)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "СЛЕДИТЬ = живая проверка отказала -- наведите на строку, чтобы увидеть причину",
  ["WHAT COUNTS AS A DEAL"] = "ЧТО СЧИТАЕТСЯ СДЕЛКОЙ",
  ["WHAT TO DO"] = "ЧТО ДЕЛАТЬ",
  ["WHAT YOU PAID"] = "СКОЛЬКО ВЫ ЗАПЛАТИЛИ",
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
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "С ним цены вашего реалма обновляются сами, а продажи и прибыль попадают на goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "Без него GoldCap живёт на срезе цен с даты релиза — сделки ищутся по устаревшим ценам.",
  ["Won't buy"] = "Не куплю",
  ["Worst case back"] = "Вернётся в худшем случае",
  ["YOUR LOTS"] = "ВАШИ ЛОТЫ",
  ["YOUR PRICE"] = "ВАША ЦЕНА",
  ["You paid"] = "Вы заплатили",
  ["You pay"] = "Вы платите",
  ["You would get"] = "Вы получите",
  ["You would pay"] = "Вы заплатите",
  ["Your call"] = "Решать вам",
  ["Your minimum"] = "Твой минимум",
  ["above the cheapest, inside the cheap quarter · %d units queued below"] =
    "выше самого дешёвого, в дешёвой четверти · в очереди ниже %d шт.",
  ["above the cheapest, within the day's reach · %d units queued below"] =
    "выше самого дешёвого, в пределах дневного размаха · в очереди ниже %d шт.",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "против региональной цены этого предмета, за вычетом 5% — если он продастся",
  ["any figure here would be invented out of the very number being refused"] =
    "любая цифра здесь была бы выдумана из того самого числа, которому не доверяют",
  ["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"] =
    "по цене, по которой GoldCap ожидает продажу, за вычетом 5% — а не по вашей запрошенной цене",
  ["auto off"] = "авто выключено",
  ["auto-synced %dh ago"] = "автосинхронизация %dч назад",
  ["auto-synced data for %s loaded (%s old)"] =
    "автосинхронизированные данные для %s загружены (возраст %s)",
  ["auto-synced data stale -- /goldcap import"] =
    "автосинхронизированные данные устарели -- /goldcap import",
  ["auto: paused"] = "авто: пауза",
  ["below the %s you paid"] = "ниже %s, которые вы заплатили",
  ["big buy"] = "крупная покупка",
  ["bought %d x item %d"] = "куплено %d x предмет %d",
  ["bought %d x item %d after AH close"] = "куплено %d x предмет %d после закрытия аукциона",
  ["buying commodity..."] = "покупаем товар...",
  ["cheapest not yours %s"] = "дешевле всех не ваш %s",
  ["checking live price..."] = "проверяем живую цену...",
  ["checking live safety..."] = "проверяем безопасность вживую...",
  ["commodity purchase failed"] = "покупка товара не удалась",
  ["confirmed commodity purchase failed after AH close"] =
    "подтверждённая покупка товара не удалась после закрытия аукциона",
  ["confirming purchase..."] = "подтверждаем покупку...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "себестоимость неполная -- задайте её, чтобы получить совет по перевыставлению",
  ["cost unknown"] = "себестоимость неизвестна",
  ["crafted %s"] = "скрафчено %s",
  ["data from goldcap.gg · synced %s ago"] = "данные с goldcap.gg · синхронизировано %s назад",
  ["due -- will be asked next pass"] = "очередь -- спросим следующим проходом",
  ["fair"] = "средняя",
  ["far below market"] = "сильно ниже рынка",
  ["finish the pending buy first"] = "сначала завершите текущую покупку",
  ["first in line"] = "первый в очереди",
  ["full scan already in progress"] = "полное сканирование уже идёт",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "полное сканирование завершено: %d сделок%s из %d групп предметов%s%s",
  ["full scan interrupted -- confirm your purchase"] =
    "полное сканирование прервано -- подтвердите покупку",
  ["full scan stalled -- press Full Scan to retry"] =
    "полное сканирование застряло -- нажмите Full Scan ещё раз",
  ["full scan stalled -- retrying shortly"] = "полное сканирование застряло -- скоро повторим",
  ["gone / price changed"] = "исчезло / цена изменилась",
  ["high"] = "высокая",
  ["hold"] = "держать",
  ["identity unresolved (variant item -- not priced by design)"] =
    "не удалось определить (вариативный предмет -- цена не считается намеренно)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "если купить все %d и продать обратно по цене, которая стоит там сейчас",
  ["import %dh old"] = "импорту %dч",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "импорт устарел -- /goldcap import или /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "импортировано %d предметов для %s (%s) — цены теперь живые.",
  ["in the mail"] = "в почте",
  ["in the mail, the bank or on another character"] = "в почте, в банке или на другом персонаже",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "столько этот рынок переваривает — сверх того вы покупаете товар, который зависнет",
  ["item %d"] = "предмет %d",
  ["item %d: %s"] = "предмет %d: %s",
  ["item variant unresolved"] = "вариант предмета не определён",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "за 24 ч — %d продаж, %s валовая, %s комиссия аукциона, %d покупок, %s потрачено",
  ["leave these alone"] = "эти не трогать",
  ["listing gone -- already bought out or price changed"] =
    "лот исчез -- уже выкуплен или цена изменилась",
  ["listing gone -- bought out or repriced"] = "лот пропал — выкуплен или переставлен по цене",
  ["live safety confirmed -- click Buy to purchase"] =
    "безопасность подтверждена вживую -- нажмите Buy, чтобы купить",
  ["live verification required"] = "требуется живая проверка",
  ["low"] = "низкая",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "ручной импорт -- Companion обновляет это сам: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "нужна свежая цена -- нажмите Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "сервер не подтвердил -- покупка всё равно могла пройти, проверьте почту. Закрытие этого окна её не отменит.",
  ["no cost"] = "нет себестоимости",
  ["no cost for %d"] = "нет себестоимости у %d",
  ["no live price yet"] = "живой цены пока нет",
  ["no price"] = "нет цены",
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
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "для такого количества единиц уже не хватает -- перепроверяем, что осталось...",
  ["not ready to cancel"] = "не готово к отмене",
  ["not ready to post"] = "не готово к выставлению",
  ["nothing listed"] = "ничего не выставлено",
  ["of %d"] = "из %d",
  ["off"] = "выкл",
  ["oldest units sell first"] = "сначала продаются старые",
  ["on"] = "вкл",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "или вставьте строку с goldcap.gg через /goldcap import.",
  ["over %d position%s"] = "по %d позициям%s",
  ["paid sale unresolved"] = "оплаченная продажа не сопоставлена",
  ["placing bid..."] = "делаем ставку...",
  ["price checked, sale speed unknown -- this one is your call"] =
    "цена проверена, скорость продажи неизвестна -- решать вам",
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
  ["re-checking what remains at a safe price..."] =
    "перепроверяем, что осталось по безопасной цене...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "предмет реалма — скорость продажи не проверена · эталон региона %s (ур. предмета %d)",
  ["recent sales (newest first):"] = "последние продажи (свежие сверху):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "регион %s — встроено: %d предметов (%s), импортировано: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "регион исправлен в %d записях; %d продаж сопоставлено со своим запасом",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "перевыставление сейчас зафиксирует убыток или застой -- придержите",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "удалено %d дублирующих записей покупки, оставленных ошибкой сканирования почты",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "удалено %d дублирующих записей продажи, оставленных ошибкой сканирования почты",
  ["sale name ambiguous"] = "имя в продаже неоднозначно",
  ["sale proceeds pending"] = "выручка ожидается",
  ["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"] =
    "сканирование завершено: %d сделок%s из %d предметов%s в реагентах, расходниках, самоцветах, чарах%s",
  ["scanned %d listings over %d passes"] = "просканировано %d лотов за %d проходов",
  ["scanning auction house..."] = "сканируем аукцион...",
  ["scanning… %d results · %d deals%s"] = "сканируем… %d результатов · %d сделок%s",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "продаётся %s/день",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "сессия: %d перехватов, потрачено %s, ~%s ориент. прибыли",
  ["sniped (listing changed on rescan)"] = "перехвачено (лот изменился при пересканировании)",
  ["sniped for "] = "снайпнуто за ",
  ["stack not identified"] = "стак не опознан",
  ["starting full scan..."] = "начинаем полное сканирование...",
  ["stopped watching %s"] = "перестали следить за %s",
  ["the Companion wrote prices this addon could not read --"] =
    "Companion записал цены, которые аддон не смог прочитать --",
  ["the import failed (%s)"] = "импорт не удался (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "чтобы распродать %d шт. при %s продажах в день, и всё это время %s заморожено",
  ["under GoldCap's own floor of %s"] = "ниже собственного порога GoldCap — %s",
  ["unknown evidence"] = "неизвестное подтверждение",
  ["waiting for previous commodity purchase to settle"] =
    "ждём завершения предыдущей покупки товара",
  ["waiting for previous search result to settle"] = "ждём завершения предыдущего поиска",
  ["watching %s closely -- re-checked every few seconds"] =
    "пристально следим за %s -- перепроверка каждые несколько секунд",
  ["worst case, selling all %d back into the price standing there now"] =
    "в худшем случае, если продать все %d по цене, которая стоит там сейчас",
  ["worth cancelling"] = "стоит отменить",
  ["would sell at a loss"] = "продалось бы в убыток",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "вы ещё не импортировали цены реалма -- установите GoldCap Companion (/goldcap companion) или вставьте строку с goldcap.gg (/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "в вашем клиенте игры нет шрифта для этого языка — текст будет отображаться пустыми квадратами",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "вашему импорту %d часов -- цены могут быть неверными. Вставьте свежую строку с goldcap.gg (/goldcap import).",
  ["yours"] = "ваша",
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
  ["×%d%s · made %s · %s"] = "×%d%s · изготовлено %s · %s",
  ["— = nothing is checking this row right now"] = "— = сейчас эту строку никто не проверяет",
  ["… = a live check is queued for this row"] =
    "… = для этой строки живая проверка уже в очереди",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ рыночная стоимость goldcap.gg — живой котировки пока нет",
  ["no answer %ds ago -- resting"] = "нет ответа %dс назад -- пауза",
}
