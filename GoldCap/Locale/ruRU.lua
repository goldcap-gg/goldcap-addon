local _, GC = ...

-- Russian. Terminology follows apps/web/messages/ru.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ruRU = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d по %s за штуку  (%s всего, %s комиссия)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion обновляет это сам: /goldcap companion.",
  [" · %d keys"] = " · ключей: %d",
  [" · below cost"] = " · ниже себестоимости",
  [" · identity unresolved"] = " · позиция не опознана",
  [" · stale %ds"] = " · устарело %dс",
  [". Check again"] = ". Проверьте ещё раз",
  [" · commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " · команды: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (или коротко /gc)",
  ["%d (whole lot)"] = "%d (весь лот)",
  ["%d ahead of you"] = "%d впереди вас",
  ["%d at %s"] = "%d по %s",
  ["%d caps · %s"] = "%d потолков · %s",
  ["%d days"] = "%d дн.",
  ["%d deals from your last scan. Full Scan to refresh"] =
    "%d сделок с последнего сканирования. Full Scan, чтобы обновить",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "%d отсеяно: трудно перепродать или ниже вашей минимальной прибыли с покупки",
  ["%d held back"] = "%d придержано",
  ["%d hidden: the live check refused them"] = "%d скрыто: живая проверка их отклонила",
  ["%d hits"] = "находок: %d",
  ["%d in %d lots"] = "%d в %d лотах",
  ["%d in 1 lot"] = "%d в 1 лоте",
  ["%d lots, %s asked"] = "%d лотов, просят %s",
  ["%d of %d"] = "%d из %d",
  ["%d of %d at or under your cap"] = "%d из %d по вашему потолку или дешевле",
  ["%d of %d done"] = "готово %d из %d",
  ["%d prices in one request · books still loading"] = "%d цен одним запросом · стаканы догружаются",
  ["%d refused by live checks. Press \"HIDDEN %d\" above to review them"] =
    "%d отклонено живой проверкой. Нажмите \"HIDDEN %d\" вверху, чтобы посмотреть",
  ["%d units"] = "%d шт.",
  ["1 unit"] = "1 шт.",
  ["%d units · %d prices"] = "%d шт. · %d цен",
  ["%d · %d/%d covered"] = "%d · %d/%d покрыто",
  ["%d/%d covered"] = "%d/%d покрыто",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s за штуку    всего %s -> %s",
  ["%s ahead"] = "%s впереди",
  ["%s needs a number, for example /gc weights %s 1.5"] = "%s: нужно число, например /gc weights %s 1.5",
  ["%s under you"] = "%s дешевле вас",
  ["%s units in %d prices"] = "%s шт. по %d ценам",
  ["%s · %s under market"] = "%s · на %s ниже рынка",
  ["%s · at market price"] = "%s · по рыночной цене",
  ["%s: %d unit%s without a cost"] = "%s: %d единиц%s без себестоимости",
  ["%s+ ahead"] = "%s+ впереди",
  ["%s+, %d prices read"] = "%s+, прочитано %d цен",
  ["1 lot, %s asked"] = "1 лот, просят %s",
  ["24h trend"] = "Тренд за 24ч",
  ["A dash means GoldCap does not know the cost of every unit yet. It will never guess one from the market price."] =
    "Прочерк значит, что себестоимость известна не по всем единицам. Из рыночной цены она никогда не выдумывается.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Ориентир, а не обещание: перепродажа по 95% импортированной рыночной стоимости, на количество, которое одобрит сама проверка.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Если несколько покупок свёрнуты в одну строку, удалятся они все.",
  ["AH answered empty %ds ago"] = "Аукцион ответил пусто %dс назад",
  ["AH value"] = "Оценка на аукционе",
  ["AH, cheapest version"] = "Аукцион, самая дешёвая версия",
  ["AUTO"] = "АВТО",
  ["AUTO · SCANNING"] = "АВТО · СКАН",
  ["AUTOMATION & ALERTS"] = "АВТОМАТИКА И ОПОВЕЩЕНИЯ",
  ["AVOID"] = "ИЗБЕГАТЬ",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Выше этого роста за 24 часа рыночная стоимость считается всплеском и занижается.",
  ["Above your price: quoted %s, your price %s"] = "Выше вашей цены: котировка %s, ваша цена %s",
  ["Alert target"] = "Цель оповещения",
  ["All"] = "Все",
  ["Archive this run"] = "Убрать список в архив",
  ["Archived"] = "Архив",
  ["Asks for a second click to confirm."] = "Требует второй клик для подтверждения.",
  ["At a vendor"] = "У торговца",
  ["At your pace you reach it at level %d."] = "В вашем темпе вы накопите к %d уровню.",
  ["At your pace you will be %s short at level 40."] = "В вашем темпе на 40 уровне не хватит %s.",
  ["At your price"] = "По вашей цене",
  ["Auction House did not answer. Press Refresh"] = "Аукцион не ответил. Нажмите Refresh",
  ["Auction House is not open"] = "Аукцион не открыт",
  ["Auto-scan on next AH visit"] = "Автоскан при следующем визите на АД",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Авто: держит Full Scan включённым постоянно и мгновенно уступает, когда вы покупаете, поищите на аукционе сами или проверьте почту. Клик переключает.",
  ["Avoid"] = "Избегать",
  ["BOOKS %d/%d"] = "СТАКАНЫ %d/%d",
  ["BUY (unverified)"] = "КУПИТЬ (без проверки)",
  ["Background check"] = "Фоновая проверка",
  ["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."] =
    "Blizzard ещё не опубликовала цену верховой езды. Введите /gc mount и ожидаемую цену.",
  ["Blizzard's price: %s"] = "Цена Blizzard: %s",
  ["Blizzard's price: %s · %d s left"] = "Цена Blizzard: %s · осталось %d с",
  ["Bought"] = "Куплено",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Точка безубыточности: самая низкая цена, которая после комиссии всё ещё возвращает вашу себестоимость. Ниже неё убыток.",
  ["Bundled %s data"] = "Встроенные данные %s",
  ["Bundled data"] = "Встроенные данные",
  ["Buy"] = "Купить",
  ["Buy it whole instead"] = "Лучше купить целиком",
  ["Buy less"] = "Купить меньше",
  ["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"] = "Покупки: %s · строк %d · купить %d · у торговца %d · потрачено %s · осталось ~%s",
  ["Buy: no run selected."] = "Покупки: список не выбран.",
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
  ["Cancel this lot and lose its deposit. Click again to confirm"] =
    "Отменить лот и потерять залог. Нажмите ещё раз для подтверждения",
  ["Cancel timed out"] = "Время на отмену истекло",
  ["Cancelling lot…"] = "Отменяем лот…",
  ["Cancels this live auction. It does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Отменяет этот активный лот, но заново он НЕ выставляется. Залог теряется, предметы приходят почтой; когда придут, выставьте их заново из этой же строки.",
  ["Cannot post this position"] = "Нельзя выставить эту позицию",
  ["Cannot remove this entry"] = "Нельзя удалить эту запись",
  ["Cannot repost this lot"] = "Нельзя перевыставить этот лот",
  ["Cap for %s"] = "Потолок для %s",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Ограничено скоростью продаж, а не вашим золотом.",
  ["Change the cap…"] = "Изменить потолок…",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Более дешёвые лоты ещё есть, но при этой скорости их разберут за часы.",
  ["Check"] = "Проверка",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower (or refuse) if the market has moved since your last import."] =
    "Проверка пересчитывает это по живой книге заявок, прежде чем тронется золото, и может дать меньше или вовсе отказать, если рынок сдвинулся после последнего импорта.",
  ["Checked against the live order book a moment ago."] =
    "Только что сверено с живым стаканом заявок.",
  ["Checked: %d of the top %d on screen"] = "Проверено: %d из %d верхних на экране",
  ["Checking prices…"] = "Проверяем цены…",
  ["Checking prices: waiting for the Auction House…"] = "Проверяем цены: ждём аукцион…",
  ["Checking this item's price…"] = "Проверяем цену этого предмета…",
  ["Checking..."] = "Проверяю...",
  ["Clear to buy"] = "Можно покупать",
  ["Click Confirm to post"] = "Нажмите Confirm, чтобы выставить",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Ещё один клик отменит активный лот. Заново он не выставляется: залог теряется, а предметы придут почтой, а не сразу в сумки.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Ещё один клик удалит эту введённую вручную себестоимость навсегда.",
  ["Close"] = "Закрыть",
  ["Companion keeps prices fresh: /goldcap companion"] =
    "Companion сам обновляет цены: /goldcap companion",
  ["Companion sync rejected:"] = "Синхронизация Companion отклонена:",
  ["Confirm"] = "Подтвердить",
  ["Confirm the cancel"] = "Подтвердить отмену",
  ["Confirm the removal"] = "Подтвердить удаление",
  ["Copy vendor list"] = "Скопировать список для торговца",
  ["Cost per unit"] = "Себестоимость за штуку",
  ["Cost unknown for %d of %d"] = "Себестоимость неизвестна для %d из %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Стоит больше, чем позволяет ваш лимит на одну покупку.",
  ["Could not read that amount. Type it like 12g 50s."] = "Не удалось прочитать сумму. Введите так: 12g 50s.",
  ["Don't skip"] = "Не пропускать",
  ["Everything here is bought"] = "Здесь всё куплено",
  ["From your scan %s ago. Counts only %s. Change with /gc weights."] =
    "По вашему скану %s назад. Учитывает только %s. Изменить: /gc weights.",
  ["Gear upgrades on the auction house"] = "Улучшения экипировки на аукционе",
  ["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."] =
    "GoldCap теперь считает, что выпадает из добычи, без имён, для шансов выпадения на goldcap.gg. Companion начнёт это передавать, когда эта часть выйдет. Введите /gc loot off, чтобы отключить.",
  ["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."] =
    "Предметов в сумках, которые на аукционе стоят больше, чем у торговца: %d (на %s больше).",
  ["Items still loading: %d. Open this again in a moment."] =
    "Ещё загружается предметов: %d. Откройте это снова через минуту.",
  ["Loot counting is off. Type /gc loot clear to remove what was recorded."] =
    "Подсчёт добычи выключен. Введите /gc loot clear, чтобы удалить записанное.",
  ["Loot counting is on."] = "Подсчёт добычи включён.",
  ["Loot record cleared."] = "Запись добычи удалена.",
  ["Market"] = "Рынок",
  ["Mount cost cleared."] = "Цена верховой езды сброшена.",
  ["Mount cost set to %s."] = "Цена верховой езды: %s.",
  ["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] =
    "Пока нет скана с экипировкой. Откройте аукцион, и GoldCap его просканирует.",
  ["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] =
    "Для вашего класса пока нет весов характеристик. Задайте их так: /gc weights STR 1 STA 0.5",
  ["Nothing on the auction house beats what you wear at your level."] =
    "На аукционе нет ничего лучше вашей экипировки для вашего уровня.",
  ["Nothing on this list matches."] = "В этом списке ничего не подходит.",
  ["Over cap"] = "Выше потолка",
  ["PRICE EACH"] = "ЦЕНА ЗА ШТ.",
  ["Play a little longer for an estimate of your pace."] = "Поиграйте ещё немного, чтобы оценить ваш темп.",
  ["RAISE CAP TO %s"] = "ПОДНЯТЬ ДО %s",
  ["RISK CHECKS"] = "ПРОВЕРКА РИСКА",
  ["ROAD TO 40"] = "ПУТЬ К 40 УРОВНЮ",
  ["Raise cap to %s"] = "Поднять потолок до %s",
  ["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."] =
    "Путь к 40 уровню с GoldCap: %s из %s на ездовое животное (%d%%).",
  ["Road to 40: %s of %s (gold %s, bags %s)."] = "Путь к 40 уровню: %s из %s (золото %s, сумки %s).",
  ["Road to 40: you have %s (gold %s, bags %s)."] = "Путь к 40 уровню: у вас %s (золото %s, сумки %s).",
  ["Runs"] = "Списки",
  ["Set cap"] = "Задать потолок",
  ["Skip"] = "Пропустить",
  ["Skip for now"] = "Пока пропустить",
  ["Skipped"] = "Пропущено",
  ["Split into reagents (craft %d×)"] = "Разложить на реагенты (крафт %d×)",
  ["Stat weights: %s"] = "Веса характеристик: %s",
  ["The rest is skipped for now"] = "Остальное пока пропущено",
  ["This client does not report item stats, so GoldCap cannot compare gear."] =
    "Этот клиент не сообщает характеристики предметов, поэтому GoldCap не может сравнить экипировку.",
  ["This lot holds more units than your Max units per buy."] =
    "В этом лоте больше штук, чем ваш «Макс. штук за одну покупку».",
  ["Could not find the queue's next lot to cancel. Try again"] =
    "Не нашли следующий лот в очереди на отмену. Попробуйте ещё раз",
  ["DEFAULTS"] = "ПО УМОЛЧАНИЮ",
  ["DISC"] = "СКИДКА",
  ["DISPLAY"] = "ОТОБРАЖЕНИЕ",
  ["DONE"] = "ГОТОВО",
  ["Default listing length for the Sell tab."] = "Срок выставления по умолчанию для вкладки Продажа.",
  ["Default: %s"] = "По умолчанию: %s",
  ["Deletes a hand-entered cost you typed into Set cost, never a purchase GoldCap itself captured or matched to your mail."] =
    "Удаляет только себестоимость, введённую вручную в «Указать цену», но не покупку, которую GoldCap поймал сам или сопоставил с почтой.",
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
  ["Everything else checks out. With more gold on this character, this is a buy."] = "Всё остальное в порядке. Будь на этом персонаже больше золота, это была бы покупка.",
  ["FIFO allocations"] = "Распределение FIFO",
  ["Fetching a fresh price for this item. Press Post again in a moment"] =
    "Получаем свежую цену для предмета. Нажмите Post ещё раз через мгновение",
  ["Fetching a fresh price for this lot. Press Repost again in a moment"] =
    "Получаем свежую цену для лота. Нажмите Repost ещё раз через мгновение",
  ["Finish the pending post first"] = "Сначала завершите текущее выставление",
  ["Finish the pending post or repost first"] =
    "Сначала завершите текущее выставление или перевыставление",
  ["Font scale"] = "Масштаб шрифта",
  ["Full pass over them: %.1fs"] = "Полный проход по ним: %.1fс",
  ["Full pass over them: measuring..."] = "Полный проход по ним: измеряем...",
  ["GOLDCAP"] = "GOLDCAP",
  ["Gold tied up"] = "Заморожено золота",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap не может точно определить, какой это стек в сумке",
  ["GoldCap data age"] = "Возраст данных GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap перепроверяет верхние %d строк по живому аукциону примерно каждые %dс. Отклонённые строки скрыты. Покупка всегда остаётся вашим кликом.",
  ["GoldCap value"] = "Оценка GoldCap",
  ["GoldCap: Import realm prices"] = "GoldCap: импорт цен реалма",
  ["GoldCap's"] = "от GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "Что GoldCap советует по этому предмету и по какой цене.",
  ["GoldCap: %s. %s"] = "GoldCap: %s. %s",
  ["GoldCap: checked live. A deal, but you need %s on this character"] = "GoldCap: проверено вживую. Выгодно, но на этом персонаже нужно %s",
  ["GoldCap: checked live, safe to buy"] = "GoldCap: проверено вживую, покупать безопасно",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: ещё не проверено на живом аукционе",
  ["Gone"] = "Ушёл",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Серый цвет означает, что котировка устарела; Post и Repost обновят её перед действием.",
  ["HIDDEN 0"] = "СКРЫТО 0",
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
  ["It is what you must beat to sell quickly, not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Это то, что нужно перебить, чтобы продать быстро, а не то, сколько предмет стоит. Один спешащий продавец может опустить цену намного ниже стоимости, и GoldCap не пойдёт за ним вниз. Смотрите WHAT TO DO, чтобы увидеть цену, по которой он действительно выставит.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Себестоимость не выдумывается из рыночной цены, поэтому пока вы её не введёте, прибыль останется неизвестной.",
  ["Item"] = "Предмет",
  ["Item %d"] = "Предмет %d",
  ["Item level %d, below the %d your price is for"] =
    "Ур. предмета %d, ниже %d, на который рассчитана ваша цена",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE. The buy is your call, and GoldCap only checks them while this board is open."] =
    "Предметы: снаряжение, питомцы и рецепты, оценённые по эталону региона из вашего импорта. Скорость продажи не измеряется, поэтому они никогда не получают статус БЕЗОПАСНО. Покупать или нет, решать вам, а GoldCap проверяет их только пока эта доска открыта.",
  ["LISTED"] = "ВЫСТАВЛЕНО",
  ["Language"] = "Язык",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Язык изменён. Введите /reload, чтобы применить его везде.",
  ["Last post may still go up. Wait a minute"] = "Ещё может выставиться. Подождите минуту",
  ["Level 40 reached: %s to go."] = "Уровень 40 достигнут: не хватает %s.",
  ["Last result: %ds ago"] = "Последний результат: %dс назад",
  ["Last result: none yet this visit"] = "Последний результат: пока не было в этот визит",
  ["Listed"] = "Выставлено",
  ["Listed at %s, far below market. Repost."] =
    "Выставлено за %s, намного ниже рынка. Перевыставьте.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Выставлено по цене, заданной вами на goldcap.gg, или дешевле. Перепродастся ли, судить вам.",
  ["Listings"] = "Лотов",
  ["Lists this item at the price on its row: the whole bag for a commodity, one stack for a regular item, or the number under HOW MANY."] =
    "Выставляет этот предмет по цене из его строки: товар всем объёмом, обычный предмет одним стеком, или столько, сколько указано в СКОЛЬКО.",
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
  ["Min profit per buy (copper)"] = "Минимальная прибыль с покупки (медь)",
  ["To buy"] = "К покупке",
  ["To craft"] = "Крафт",
  ["Unknown stat %s. Use one of: %s"] = "Неизвестная характеристика %s. Используйте одну из: %s",
  ["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."] =
    "Улучшений экипировки на аукционе: %d. Введите /gc upgrades, чтобы их увидеть.",
  ["Use the default cap"] = "Потолок по умолчанию",
  ["While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead."] = "Пока это значение остаётся на стандартных 5%, лот по цене торговца может использовать до половины вашего золота.",
  ["Min return per buy %"] = "Мин. доходность покупки %",
  ["Missing cost"] = "Нет себестоимости",
  ["NO LIVE PRICE YET"] = "ПОКА НЕТ ЖИВОЙ ЦЕНЫ",
  ["YOUR LISTS"] = "ВАШИ СПИСКИ",
  ["NOT ON HAND %d"] = "НЕТ НА РУКАХ %d",
  ["NOTHING TO CANCEL"] = "НЕЧЕГО ОТМЕНЯТЬ",
  ["Needs a live price check before it can be bought."] =
    "Перед покупкой нужна живая проверка цены.",
  ["Needs gold"] = "Нужно золото",
  ["Never spend more than this share of your gold on one purchase."] =
    "Никогда не тратить на одну покупку больше этой доли вашего золота.",
  ["No answer yet, listening for a minute"] = "Аукцион пока не ответил, ждём ещё минуту",
  ["No deals passed the safety checks right now."] =
    "Сейчас ни одна сделка не прошла проверок безопасности.",
  ["No deals to show, and no realm prices yet."] = "Сделок нет, и цен реалма пока тоже.",
  ["No deals yet."] = "Сделок пока нет.",
  ["No exact auction key"] = "Нет точного ключа аукциона",
  ["No exact bag stack"] = "Нет точного стека в сумке",
  ["No exact bag variant"] = "Нет точного варианта в сумке",
  ["No live listings came back for this item."] =
    "По этому предмету не пришло ни одного живого лота.",
  ["No region reference for this item yet. Import again once goldcap.gg publishes one."] =
    "Для этого предмета ещё нет эталонной цены региона. Импортируйте снова, когда goldcap.gg её опубликует.",
  ["No safe resale price could be worked out."] =
    "Безопасную цену перепродажи вычислить не удалось.",
  ["No sales data for this item."] = "Нет данных о продажах этого предмета.",
  ["Not enough gold on this character to buy what GoldCap finds"] = "Не хватает золота на этом персонаже, чтобы купить находки",
  ["Not enough units on the Auction House to fill that quantity."] =
    "На аукционе не хватает единиц, чтобы набрать это количество.",
  ["Not in your bags or listed. Mail or bank?"] =
    "Нет в сумках и не выставлено. Почта или банк?",
  ["Not on hand: the stock is in the mail, the bank, or on another character"] =
    "Нет под рукой: запас в почте, банке или на другом персонаже",
  ["Not worth the deposit on the AH"] = "Не окупает залог на аукционе",
  ["Nothing is being held back."] = "Ничего не придержано.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "После этой покупки не останется того, во что продавать, поэтому цены выхода нет.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Ни один лот не дотягивает до уровня предмета, на котором измерена эталонная цена.",
  ["Nothing listed on the AH right now"] = "Сейчас на аукционе ничего не выставлено",
  ["Nothing to sell"] = "Нечего продавать",
  ["Nothing in your bags to list. Buy on the Deals tab or pick up your mail: anything you can sell shows up here with a price ready."] =
    "В сумках нечего выставить. Купите что-нибудь на вкладке DEALS или заберите почту: всё, что можно продать, появится здесь с готовой ценой.",
  ["No auctions up"] = "Лотов нет",
  ["No live auctions on this character. What you post shows up here, with what to cancel and what to leave."] =
    "У этого персонажа нет активных лотов. То, что вы выставите, появится здесь, с подсказкой, что снять, а что оставить.",
  ["No match"] = "Ничего не найдено",
  ["Nothing on this deck matches that search. Clear the box to see everything."] =
    "На этой вкладке ничего не подходит под поиск. Очистите поле, чтобы увидеть всё.",
  ["Still pricing"] = "Цены ещё идут",
  ["The auction house is still answering. Items show up here as their prices arrive."] =
    "Аукцион ещё отвечает. Предметы появятся здесь по мере того, как придут их цены.",
  ["Every cost is known"] = "Себестоимость известна",
  ["Every item in your bags already has what you paid on record. Turn off NO COST to see them all."] =
    "Для всего в сумках уже записано, сколько вы заплатили. Выключите БЕЗ ЧЕКА, чтобы увидеть всё.",
  ["Nothing queued to cancel"] = "В очереди на отмену ничего нет",
  ["Nothing queued to post"] = "В очереди на выставление ничего нет",
  ["Nothing to remove"] = "Нечего удалять",
  ["ON THE AUCTION HOUSE"] = "НА АУКЦИОНЕ",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown: rescan anytime."] =
    "Разовое сканирование всего аукциона постраничными запросами. Занимает примерно 15-60 секунд на загруженных реалмах. Без отката: сканируйте когда угодно.",
  ["Open the Auction House first."] = "Сначала откройте аукцион.",
  ["Open the Auction House to begin scanning."] = "Откройте аукцион, чтобы начать сканирование.",
  ["Open the deals board. /gc for commands."] = "Открыть доску сделок. /gc покажет команды.",
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
  ["Post"] = "Выставить",
  ["Post above the cheapest"] = "Выставлять выше самого дешёвого",
  ["Post confirmation expired"] = "Подтверждение выставления просрочено",
  ["Post the next queued item"] = "Выставить следующий предмет из очереди",
  ["Posted"] = "Выставлено",
  ["Posting failed"] = "Выставление не удалось",
  ["Posting unavailable"] = "Выставление недоступно",
  ["Posting…"] = "Отправка…",
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
  ["Profit tracking is a goldcap.gg Pro feature"] = "Учёт прибыли: функция goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "В этой сборке покупки отключены.",
  ["Press Buy again to buy this quantity"] = "Нажмите Купить ещё раз, чтобы купить это количество",
  ["QTY"] = "КОЛ-ВО",
  ["Quantity exceeds missing units"] = "Количество превышает недостающие единицы",
  ["Quantity is capped by how fast this item actually sells."] =
    "Количество ограничено тем, как быстро предмет реально продаётся.",
  ["REFRESH"] = "ОБНОВИТЬ",
  ["RESET WINDOW"] = "СБРОСИТЬ ОКНО",
  ["Reason"] = "Причина",
  ["Refresh"] = "Обновить",
  ["Refresh waiting for prior result"] = "Обновление ждёт предыдущий результат",
  ["Refreshing listings…"] = "Обновляем лоты…",
  ["Refuse a buy when the price fell more than this in the last 24 hours: it may keep falling."] =
    "Отказать в покупке, если цена упала больше этого значения за последние 24 часа: она может падать и дальше.",
  ["Refused so far: %d"] = "Отклонено на данный момент: %d",
  ["Removal confirmation expired"] = "Подтверждение удаления просрочено",
  ["Remove"] = "Удалить",
  ["Remove this cost"] = "Удалить эту себестоимость",
  ["Remove?"] = "Удалить?",
  ["Removed"] = "Удалено",
  ["Removed %d entries"] = "Удалено записей: %d",
  ["Removes every entered-by-hand purchase in this run. Click again to confirm"] =
    "Удаляет все введённые вручную покупки в этой группе. Нажмите ещё раз для подтверждения",
  ["Removes this entered-by-hand purchase. Click again to confirm"] =
    "Удаляет эту введённую вручную покупку. Нажмите ещё раз для подтверждения",
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
  ["SESSION %s%s · BUYS %d"] = "СЕССИЯ %s%s · ПОКУПКИ %d",
  ["Sales are costed from your oldest units first"] =
    "Продажи списываются сначала со старейших единиц",
  ["Search"] = "Поиск",
  ["Sales evidence"] = "Данные продаж",
  ["Sell it on the AH"] = "Продайте на аукционе",
  ["Sell it on the AH (deposit not counted)"] = "Продайте на аукционе (залог не учтён)",
  ["Sell it to a vendor"] = "Продайте торговцу",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "Вкладка Продажа выставляет на одну ступень выше самой дешёвой заявки, если книга ордеров показывает такую же скорость продажи.",
  ["Sell-through"] = "Выкупаемость",
  ["Sellers"] = "Продавцов",
  ["Sells too rarely: you would be holding it for a long time."] =
    "Продаётся слишком редко: будете держать его долго.",
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
  ["Source"] = "Источник",
  ["Source age"] = "Возраст источника",
  ["Spike-trend threshold %"] = "Порог всплеска цены %",
  ["Start scanning as soon as the auction house opens."] =
    "Начинать сканирование сразу при открытии аукционного дома.",
  ["Status"] = "Статус",
  ["Stop and open the buy window on your price"] = "Остановить и открыть окно покупки по вашей цене",
  ["Stress exit unit"] = "Цена стресс-выхода",
  ["Stress profit"] = "Стресс-прибыль",
  ["THE BOOK"] = "СТАКАН ЗАЯВОК",
  ["TREND"] = "ТРЕНД",
  ["Tell GoldCap what you actually paid for these units."] =
    "Укажите, сколько вы на самом деле заплатили за эти единицы.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "Аукцион не назвал залог, поэтому стоимость неизвестна.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Companion синхронизируется, но аддон не смог прочитать то, что он записал:",
  ["The auction house did not answer. Try again"] = "Аукцион не ответил. Попробуйте ещё раз",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "Доска оценила лот по импортированному снимку. Живой стакан этого не подтверждает.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Кнопка становится нажимаемой не сразу, поэтому случайный двойной клик её не сработает.",
  ["The cancel did not go through: the lot is still listed"] = "Отмена не прошла: лот всё ещё выставлен",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "Самый дешёвый лот уже недостаточно ниже эталонной цены.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Самая дешёвая цена, которую сейчас просит КТО-ТО ДРУГОЙ, по живому запросу к аукциону. Ваши собственные лоты исключены, поэтому число никогда не гонится само за собой вниз.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Данные по этому предмету битые, и GoldCap отказывается гадать.",
  ["The liquidity data is not reliable enough to act on."] =
    "Данные о ликвидности недостаточно надёжны, чтобы на них действовать.",
  ["The market value is an estimate, not a measurement."] =
    "Рыночная стоимость является оценкой, а не измерением.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Больше этого количества одна покупка не возьмёт. Скорость продаж товара может сделать его меньше.",
  ["The price data is over three hours old. Sync the Companion, then /reload. The addon only reads its data when the UI loads."] =
    "Данным о ценах больше трёх часов. Синхронизируйте Companion и сделайте /reload. Аддон читает свои данные только при загрузке интерфейса.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "Цена проверена. Скорость продажи нигде не измеряется, так что судить вам.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Цена падает: купив сейчас, вы рискуете застрять с товаром.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "Цена взята из последней котировки, ей не больше 45 секунд. Если она изменится до подтверждения, выставление отменяется, а не уходит по старой цене.",
  ["The price moved: part of this quote may be above your price"] =
    "Цена сдвинулась: часть этого предложения может быть выше вашей цены",
  ["The price moved and the trade is no longer safe."] =
    "Цена сдвинулась, и сделка больше не безопасна.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Прибыль не дотягивает до вашего минимума после 5% комиссии и залога.",
  ["What this buy would make is under your minimum profit."] =
    "Прибыль от этой покупки меньше вашего минимума.",
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
  ["Unknown means the cost side is incomplete. Fill it in with Set cost."] =
    "«Неизвестно» значит, что себестоимость заполнена не вся. Допишите её через «Указать цену».",
  ["VERDICT"] = "ВЕРДИКТ",
  ["Verdict"] = "Вердикт",
  ["WAITING FOR THE AUCTION HOUSE %d"] = "ЖДЁМ АУКЦИОН %d",
  ["WATCH"] = "СЛЕДИТЬ",
  ["WATCH (computed SAFE)"] = "WATCH (расчёт БЕЗОПАСНО)",
  ["WATCH = the live check refused it. Hover the row for the reason"] =
    "СЛЕДИТЬ = живая проверка отказала. Наведите на строку, чтобы увидеть причину",
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
  ["Watching: pinned, but not a deal right now"] =
    "Следим: закреплено, но сейчас это не сделка",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Сколько на самом деле стоила одна штука, в среднем по ещё не проданным покупкам.",
  ["What to do"] = "Что делать",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Сколько остаётся с одной штуки при продаже по рынку: цена продажи минус 5% комиссии аукциона минус ваша себестоимость.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Когда лот достигает цены, заданной вами на сайте, сканирование останавливается и открывается окно покупки.",
  ["Window position & size"] = "Позиция и размер окна",
  ["Won't buy"] = "Не куплю",
  ["Worst case back"] = "Вернётся в худшем случае",
  ["YOUR LOTS"] = "ВАШИ ЛОТЫ",
  ["YOUR PRICE"] = "ВАША ЦЕНА",
  ["You can pay for it now."] = "Вы уже можете оплатить.",
  ["You get"] = "Получите",
  ["You paid"] = "Вы заплатили",
  ["You pay"] = "Вы платите",
  ["You would get"] = "Вы получите",
  ["You would pay"] = "Вы заплатите",
  ["Your call"] = "Решать вам",
  ["Your cap"] = "Ваш потолок",
  ["Your gold has not grown lately, so there is no pace to estimate."] =
    "Ваше золото в последнее время не растёт, поэтому темп оценить нельзя.",
  ["Your minimum"] = "Твой минимум",
  ["Your price"] = "Ваша цена",
  ["a purchase landed that GoldCap could not attribute"] = "прошла покупка, которую GoldCap не смог отнести к строке",
  ["a purchase landed that GoldCap could not price"] = "прошла покупка, цену которой GoldCap не знает",
  ["a unit, at or under your price of %s"] = "за штуку, по вашей цене %s или ниже",
  ["a vendor sells it"] = "продаёт торговец",
  ["a vendor sells it for %s each"] = "торговец продаёт по %s за шт.",
  ["a vendor sells it for %s each · the auction house asks %s"] = "торговец продаёт по %s за шт. · на аукционе %s",
  ["alert group · %d hits"] = "группа оповещений · находок: %d",
  ["already in your bags and bank"] = "уже есть в сумках и банке",
  ["another purchase is in flight"] = "другая покупка ещё не завершена",
  ["at a vendor"] = "у торговца",
  ["at a vendor · %s each"] = "у торговца · %s за шт.",
  ["at level %d"] = "с %d уровня",
  ["bought"] = "куплено",
  ["buy %d of %d"] = "купить %d из %d",
  ["buy %d of %d, have %d in bags and bank"] = "купить %d из %d, в сумках и банке %d",
  ["cheapest seen %s"] = "самое дешёвое: %s",
  ["confirming..."] = "подтверждение...",
  ["craft it for %s each"] = "крафт: %s за шт.",
  ["craft it for %s each · %s here"] = "крафт: %s за шт. · здесь %s",
  ["craft it yourself"] = "скрафтите сами",
  ["craft it · %s each"] = "крафт · %s за шт.",
  ["craft it: %s = %s each"] = "крафт: %s = %s за шт.",
  ["includes %d for crafting %s"] = "из них %d на крафт: %s",
  ["no answer. Check your mail"] = "нет ответа. Проверьте почту",
  ["nothing at or under your cap of %s"] = "ничего по вашему потолку %s или дешевле",
  ["nothing on offer"] = "в продаже нет",
  ["over your cap"] = "выше потолка",
  ["purchase failed. Try again"] = "покупка не прошла. Попробуйте снова",
  ["right-click to skip or change the cap"] = "ПКМ: пропустить или изменить потолок",
  ["seen %s ago"] = "видели %s назад",
  ["skipped for now"] = "пока пропущено",
  ["skipped for this session, it stays on the list"] = "пропущено до конца сеанса, в списке остаётся",
  ["still on the list: %d at a vendor · %d to craft"] = "ещё в списке: у торговца %d · скрафтить %d",
  ["sure profit: a vendor pays %s each"] =
    "верная прибыль: торговец платит %s за штуку",
  ["resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown"] =
    "перепродажа по оценке скана, %s/шт., за вычетом 5%% комиссии и залога; скорость неизвестна",
  ["Checked against the live auction house a moment ago."] =
    "Только что сверено с аукционом в реальном времени.",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "выше самого дешёвого, в дешёвой четверти · впереди %s шт.",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "выше самого дешёвого, в пределах дневного размаха · впереди %s шт.",
  ["age %ss"] = "%sс назад",
  ["another purchase took over: nothing was confirmed"] =
    "другая покупка заняла её место, ничего не подтверждено",
  ["any figure here would be invented out of the very number being refused"] =
    "любая цифра здесь была бы выдумана из того самого числа, которому не доверяют",
  ["at or under your price. Click Buy to purchase"] =
    "по вашей цене или дешевле. Нажмите Buy, чтобы купить",
  ["auto off"] = "авто выключено",
  ["auto-synced %dh ago"] = "автосинхронизация %dч назад",
  ["auto-synced data for %s loaded (%s old)"] =
    "автосинхронизированные данные для %s загружены (возраст %s)",
  ["auto-synced data stale: /goldcap import"] =
    "автосинхронизированные данные устарели: /goldcap import",
  ["auto: paused"] = "авто: пауза",
  ["below the %s breakeven"] = "ниже точки безубыточности %s",
  ["below the %s you paid"] = "ниже %s, которые вы заплатили",
  ["big buy"] = "крупная покупка",
  ["bought %d"] = "куплено %d",
  ["bought %d x %s"] = "куплено %d x %s",
  ["bought %d after AH close"] = "куплено %d после закрытия аукциона",
  ["buying commodity..."] = "покупаем товар...",
  ["cheapest not yours %s"] = "дешевле всех не ваш %s",
  ["checking live price..."] = "проверяем живую цену...",
  ["checking live safety..."] = "проверяем безопасность вживую...",
  ["clears in ~%dd"] = "разойдётся за ~%d дн.",
  ["clears in ~%dh"] = "разойдётся за ~%d ч",
  ["commodity purchase failed"] = "покупка товара не удалась",
  ["confirmed commodity purchase failed after AH close"] =
    "подтверждённая покупка товара не удалась после закрытия аукциона",
  ["confirming purchase..."] = "подтверждаем покупку...",
  ["cost basis incomplete. Set costs to get repost advice"] =
    "себестоимость неполная. Задайте её, чтобы получить совет по перевыставлению",
  ["crafted %s"] = "скрафчено %s",
  ["due, will be asked next pass"] = "очередь: спросим следующим проходом",
  ["fair"] = "приемлемые",
  ["far below market"] = "сильно ниже рынка",
  ["finish the pending buy first"] = "сначала завершите текущую покупку",
  ["first in line"] = "первый в очереди",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "Стоит %s. При вашем лимите %d%% на одну покупку на этом персонаже нужно %s.",
  ["fresh"] = "свежая",
  ["full scan already in progress"] = "полное сканирование уже идёт",
  ["full scan interrupted. Confirm your purchase"] =
    "полное сканирование прервано. Подтвердите покупку",
  ["full scan stalled. Press Full Scan to retry"] =
    "полное сканирование застряло. Нажмите Full Scan ещё раз",
  ["full scan stalled, retrying shortly"] = "полное сканирование застряло, скоро повторим",
  ["full scan stopped. Press %s to run it again"] =
    "полное сканирование остановлено. Нажмите %s, чтобы запустить его снова",
  ["gone / price changed"] = "исчезло / цена изменилась",
  ["goldcap.gg prices for WoW: Forever are not out yet."] =
    "Цены goldcap.gg для WoW: Forever пока недоступны.",
  ["strong"] = "надёжные",
  ["hold"] = "держать",
  ["identity unresolved (variant item, not priced by design)"] =
    "не удалось определить (вариативный предмет, цена не считается намеренно)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "если купить все %d и продать обратно по цене, которая стоит там сейчас",
  ["ilvl %d"] = "ур. %d",
  ["import %dh old"] = "импорту %dч",
  ["import stale: /goldcap import or /goldcap companion"] =
    "импорт устарел: /goldcap import или /goldcap companion",
  ["imported %d items for %s (%s). Prices are live now."] =
    "импортировано %d предметов для %s (%s). Цены теперь живые.",
  ["in the mail"] = "в почте",
  ["in the mail, the bank or on another character"] = "в почте, в банке или на другом персонаже",
  ["is what this market absorbs. Past that you are buying stock you will sit on"] =
    "столько этот рынок переваривает. Сверх того вы покупаете товар, который зависнет",
  ["item %d"] = "предмет %d",
  ["%s: %s"] = "%s: %s",
  ["item level %d+"] = "ур. предмета %d+",
  ["item variant unresolved"] = "вариант предмета не определён",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h: %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "за 24 ч: %d продаж, %s валовая, %s комиссия аукциона, %d покупок, %s потрачено",
  ["last live price %s ago"] = "последняя живая цена, %s назад",
  ["leave these alone"] = "эти не трогать",
  ["level %d"] = "уровень %d",
  ["listing gone: already bought out or price changed"] =
    "лот исчез: уже выкуплен или цена изменилась",
  ["listing gone: bought out or repriced"] = "лот пропал: выкуплен или переставлен по цене",
  ["live safety confirmed. Click Buy to purchase"] =
    "безопасность подтверждена вживую. Нажмите Buy, чтобы купить",
  ["live verification required"] = "требуется живая проверка",
  ["the cheapest is %s, your cap is %s"] = "самое дешёвое: %s, ваш потолок: %s",
  ["the run changed. Start again"] = "список изменился. Начните заново",
  ["took too long. Try again"] = "слишком долго. Попробуйте снова",
  ["vs %s at the auction house · right-click to split"] = "против %s на аукционе · ПКМ: разложить на реагенты",
  ["weak"] = "слабые",
  ["manual import. Companion keeps this fresh: /goldcap companion"] =
    "ручной импорт. Companion обновляет это сам: /goldcap companion",
  ["market %s"] = "рынок %s",
  ["needs %s"] = "нужно %s",
  ["needs a fresh price. Press Refresh"] = "нужна свежая цена. Нажмите Refresh",
  ["no confirmation from the server. The buy may still have gone through, check your mail. Closing this will not undo it."] =
    "сервер не подтвердил. Покупка всё равно могла пройти, проверьте почту. Закрытие этого окна её не отменит.",
  ["no cost"] = "нет закупа",
  ["no cost for %d"] = "нет себестоимости у %d",
  ["no live price yet"] = "живой цены пока нет",
  ["no live price"] = "нет живой цены",
  ["no live quote yet, pricing…"] = "живой котировки пока нет, оцениваем цену…",
  ["no market figure for caged pets"] = "нет рыночных данных для питомцев в клетке",
  ["no market figure for this item level"] = "нет рыночных данных для этого уровня предмета",
  ["Makes %s"] = "Создаёт %s",
  ["no prices yet: /goldcap companion or /goldcap import"] =
    "цен пока нет: /goldcap companion или /goldcap import",
  ["no purchase confirmation received. Cancel and retry"] =
    "подтверждение покупки не получено. Cancel и повторите",
  ["no sales recorded yet. Open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "продаж ещё не записано. Откройте почту с включённым GoldCap, и они будут прочитаны из счетов",
  ["no stock in bags or listed, nothing to price for"] =
    "нет запаса в сумках и на аукционе, нечего оценивать",
  ["none"] = "нет",
  ["not enough gold: total %s, you have %s"] = "не хватает золота: всего %s, у вас %s",
  ["not enough gold for this quote. Cancel"] = "не хватает золота по этой цене. Cancel",
  ["not enough gold on this character: you need %s"] = "не хватает золота на этом персонаже: нужно %s",
  ["not enough units left for that quantity, re-checking what remains..."] =
    "для такого количества единиц уже не хватает, перепроверяем, что осталось...",
  ["not priced: nothing on hand to sell"] = "без цены: продавать нечего",
  ["not ready to cancel"] = "не готово к отмене",
  ["not ready to post"] = "не готово к выставлению",
  ["nothing listed"] = "ничего не выставлено",
  ["of %d"] = "из %d",
  ["off"] = "выкл",
  ["oldest units sell first"] = "сначала продаются старые",
  ["on"] = "вкл",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "откройте аукцион один раз, чтобы GoldCap узнал, как они продаются",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "или вставьте строку с goldcap.gg через /goldcap import.",
  ["paid sale unresolved"] = "оплаченная продажа не сопоставлена",
  ["placing bid..."] = "делаем ставку...",
  ["previous commodity purchase settled. %s to re-check the price"] =
    "предыдущая покупка товара завершена. %s, чтобы перепроверить цену",
  ["price changed after you closed the buy window: nothing was bought"] =
    "цена изменилась после закрытия окна покупки: ничего не куплено",
  ["price confirmed. Click Buy to purchase"] = "цена подтверждена. Нажмите Buy, чтобы купить",
  ["price rose %.1fx, still safe. Confirm"] =
    "цена выросла в %.1fx, всё ещё безопасно. Подтвердите",
  ["price stands %d of %d"] = "ваша цена: %d из %d",
  ["prices loaded are %s (%s) but you are playing in %s, so every discount and profit figure is measured against another market"] =
    "загружены цены %s (%s), а играете вы в %s, поэтому все скидки и прибыль считаются по чужому рынку",
  ["purchase canceled"] = "покупка отменена",
  ["purchase complete"] = "покупка совершена",
  ["purchase identity unresolved"] = "покупка не опознана",
  ["purchase pending exact cost"] = "покупка ждёт точной себестоимости",
  ["purchase total unavailable. Check your mail"] =
    "общая сумма покупки недоступна. Проверьте почту",
  ["quote %s. Click Confirm to buy"] = "котировка %s. Нажмите Confirm, чтобы купить",
  ["quote %ss ago"] = "котировка %sс назад",
  ["quote expired. Refresh to re-check the price"] =
    "котировка просрочена. Нажмите Refresh, чтобы перепроверить цену",
  ["quote expires in %d s. Click Confirm to buy"] =
    "котировка истекает через %d с. Нажмите Confirm, чтобы купить",
  ["re-checking what remains at a safe price..."] =
    "перепроверяем, что осталось по безопасной цене...",
  ["recent sales (newest first):"] = "последние продажи (свежие сверху):",
  ["region %s · bundled: %d items (%s), imported: %s"] =
    "регион %s · встроено: %d предметов (%s), импортировано: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "регион исправлен в %d записях; %d продаж сопоставлено со своим запасом",
  ["relisting now would lock in a loss or a stall. Hold"] =
    "перевыставление сейчас зафиксирует убыток или застой. Придержите",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "удалено %d дублирующих записей покупки, оставленных ошибкой сканирования почты",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "удалено %d дублирующих записей продажи, оставленных ошибкой сканирования почты",
  ["sale name ambiguous"] = "имя в продаже неоднозначно",
  ["sale proceeds pending"] = "выручка ожидается",
  ["scanned %d listings over %d passes"] = "просканировано %d лотов за %d проходов",
  ["scanning auction house..."] = "сканируем аукцион...",
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
  ["the Companion wrote prices this addon could not read:"] =
    "Companion записал цены, которые аддон не смог прочитать:",
  ["the auction house has not sent details for these yet"] =
    "аукцион ещё не прислал сведения об этих предметах",
  ["the import failed (%s)"] = "импорт не удался (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "чтобы распродать %d шт. при %s продажах в день, и всё это время %s заморожено",
  ["unavailable"] = "недоступна",
  ["under GoldCap's own floor of %s"] = "ниже собственного порога GoldCap: %s",
  ["unknown evidence"] = "неизвестное подтверждение",
  ["waiting for previous commodity purchase to settle"] =
    "ждём завершения предыдущей покупки товара",
  ["waiting for previous search result to settle"] = "ждём завершения предыдущего поиска",
  ["waiting..."] = "ожидание...",
  ["wall"] = "стена",
  ["wall %s at %s: price under it to sell first"] =
    "стена %s шт. по %s: ставьте ниже, чтобы продать раньше",
  ["wall %s at %s above you"] = "стена %s шт. по %s выше вас",
  ["watching %s closely, re-checked every few seconds"] =
    "пристально следим за %s, перепроверка каждые несколько секунд",
  ["worst case, selling all %d back into the price standing there now"] =
    "в худшем случае, если продать все %d по цене, которая стоит там сейчас",
  ["worth cancelling"] = "стоит отменить",
  ["would sell at a loss"] = "продалось бы в убыток",
  ["you have enough gold for this now. Check again"] = "теперь золота хватает. Нажмите Check, чтобы проверить снова",
  ["you haven't imported realm prices yet. Install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "вы ещё не импортировали цены реалма. Установите GoldCap Companion (/goldcap companion) или вставьте строку с goldcap.gg (/goldcap import).",
  ["you take %d"] = "берёте %d",
  ["your game client has no font for this language, so the text will show as empty boxes"] =
    "в вашем клиенте игры нет шрифта для этого языка, текст будет отображаться пустыми квадратами",
  ["your import is %d hours old and prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "вашему импорту %d часов, цены могут быть неверными. Вставьте свежую строку с goldcap.gg (/goldcap import).",
  ["your price is above every level shown"] = "твоя цена выше всех уровней",
  ["your scan, %s ago"] = "твоё сканирование, %s назад",
  ["yours"] = "ваша",
  ["yours ×%s"] = "ваши ×%s",
  ["~%dd to reach you"] = "~%d дн. до вас",
  ["~%dh to reach you"] = "~%d ч до вас",
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
  ["- = nothing is checking this row right now"] = "- = сейчас эту строку никто не проверяет",
  ["… = a live check is queued for this row"] =
    "… = для этой строки живая проверка уже в очереди",
  ["no answer %ds ago, resting"] = "нет ответа %dс назад, пауза",
  ["the last attempt is still settling, checking the price again..."] =
    "предыдущая попытка ещё не завершилась, проверяем цену заново...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "Выставлено по цене, заданной вами на goldcap.gg, или дешевле (группа: %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "АВТО · ПАУЗА: ОКНО ПОКУПКИ",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "Пауза, пока открыто окно покупки. Купите или закройте его, и Авто продолжит.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "АВТО · ПАУЗА: ВАШ ПОИСК",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "Пауза, пока вы печатаете в поиске аукциона. Продолжит через несколько секунд после того, как вы из него выйдете.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "АВТО · ПАУЗА: ОТКРЫТА ПОЧТА",
  ["AUTO · PAUSED: OTHER TAB"] = "АВТО · ПАУЗА: ДРУГАЯ ВКЛАДКА",
  ["Paused while another auction house tab is open: Sell, Auctions, or another addon's, such as Auctionator's Selling. A scan would replace what that tab shows. Click Buy or the GoldCap tab at the bottom of the auction house and Auto carries on."] =
    "Пауза, пока открыта другая вкладка аукциона: Продать, Аукционы или вкладка другого аддона, например Selling у Auctionator. Скан заменил бы то, что она показывает. Нажмите Купить или вкладку GoldCap внизу аукциона, и Авто продолжит.",
  ["Scan starts when you leave that tab: click Buy or GoldCap"] =
    "Скан начнётся, когда уйдёте с вкладки: Купить или GoldCap",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "Пауза, пока открыт почтовый ящик. Закройте его, и Авто продолжит.",
  ["AUTO · PAUSED: SELL TAB"] = "АВТО · ПАУЗА: ВКЛАДКА ПРОДАЖА",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "Пауза, пока открыта вкладка Продажа: она оценивает ваши сумки через тот же поиск. Вернитесь к сделкам, и Авто продолжит.",
  ["AUTO · PAUSED: BUY TAB"] = "АВТО · ПАУЗА: ВКЛАДКА BUY",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "Пауза, пока открыта вкладка BUY: она узнаёт цены через тот же поиск. Вернитесь к сделкам, и Авто продолжит.",
  ["AUTO · WAITING FOR YOU"] = "АВТО · ЖДЁТ ВАС",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "Ждёт, пока вы выставляете, покупаете или смотрите в окнах самого аукциона. Начнёт, как только вы закончите.",
  ["AUTO · WAITING: YOUR AH SEARCH"] = "АВТО · ЖДЁТ: ВАШ ПОИСК НА АУКЦИОНЕ",
  ["Waiting so that a scan does not replace the results of your own search on the auction house's Buy list. Click AUTO or SCAN and it carries on."] =
    "Ждёт, чтобы скан не заменил результаты вашего поиска в списке покупки аукциона. Нажмите АВТО или СКАН, и он продолжит.",
  ["Market %s · unverified until a live Check"] = "Рынок %s · не проверено до живой проверки",
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "данные всего рынка: товаров %d, с данными о продажах %d, предметов мира %d (возраст %s, %d КБ)",
  ["whole-market data not in use: %s"] = "данные всего рынка не используются: %s",
  ["it is %s old, and the prices you imported are newer"] = "их возраст %s, а импортированные вами цены новее",
  ["it is for another region than the prices loaded"] = "они для другого региона, чем загруженные цены",
  ["its date cannot be right. Check this computer's clock"] =
    "их дата не может быть верной. Проверьте часы этого компьютера",
  ["it was set aside when other prices were loaded this session. /reload to use it again"] =
    "они были отложены, когда в этой сессии загрузили другие цены. /reload, чтобы снова их использовать",
  ["On the AH now"] = "На аукционе сейчас",
  ["%s listed · %d min ago"] = "выставлено %s · %d мин назад",
  ["%s listed · just now"] = "выставлено %s · только что",
  ["it could not be read (%s)"] = "их не удалось прочитать (%s)",
  ["it is for a region this build of GoldCap does not know. Update the addon"] =
    "они для региона, которого эта версия GoldCap не знает. Обновите аддон",
  ["it is in a format this build of GoldCap cannot read. Update the addon"] =
    "они в формате, который эта версия GoldCap не умеет читать. Обновите аддон",
  ["it is larger than this build of GoldCap can read. Update the addon"] =
    "они больше, чем может прочитать эта версия GoldCap. Обновите аддон",
  ["the Companion wrote an empty copy. Let it sync, then /reload"] =
    "Companion записал их пустыми. Дайте ему синхронизироваться и сделайте /reload",
  ["the Companion wrote it with no prices. Let it sync, then /reload"] =
    "Companion записал их без цен. Дайте ему синхронизироваться и сделайте /reload",
  ["Scanning the auction house…"] = "Сканируем аукцион…",
  ["%s lots scanned and saved"] = "%s лотов отсканировано и сохранено",
  ["%s items scanned and saved"] = "%s предметов отсканировано и сохранено",
  ["The full scan is cooling down (%d min left). Scanning by browsing instead"] =
    "Полное сканирование ещё восстанавливается (осталось %d мин). Пока сканируем через обзор",
  ["The auction house did not answer the full scan. Scanning by browsing instead"] =
    "Аукцион не ответил на полное сканирование. Вместо него сканируем через обзор",
  ["reading the auction house: %s of %s lots"] = "читаем аукцион: %s из %s лотов",
  ["The scan found nothing to save"] = "Сканирование не нашло, что сохранить",
  ["Scans the whole auction house for prices: a full list at most once every 15 minutes, browsing in between. GoldCap also scans when you open the auction house."] =
    "Сканирует весь аукцион в поисках цен: полный список не чаще раза в 15 минут, а между ними через обзор. GoldCap также сканирует при открытии аукциона.",
  -- Core/ForeverValue.lua's PrintBags/BagTotals and Core/PostQueue.lua's below_vendor: the
  -- POST queue holding back what a vendor pays at least as much for.
  ["Your bags: %s at a vendor, %s on the AH after its cut"] =
    "Ваши сумки: %s у торговца, %s на аукционе после комиссии",
  ["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."] =
    "Кнопка ВЫСТАВИТЬ на вкладке Продажа перечисляет всё, что стоит дороже, чем платит торговец, по одному клику за раз.",
  ["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."] =
    "Ваши сумки: %s у торговца. Отсканируйте аукцион, чтобы узнать, сколько бы за них дали там.",
  ["a vendor pays more: sell it there"] =
    "торговец платит больше: продайте ему",
  ["vendor pays more"] =
    "торговец платит больше",
  ["Below vendor"] =
    "Ниже НПС",
  ["Under market"] =
    "Ниже рынка",
  [" · buy at %s or less, vendor pays %s"] =
    " · купить за %s или меньше, торговец платит %s",
  [" · buy at %s or less, AH value %s"] =
    " · купить за %s или меньше, оценка на аукционе %s",
  ["Buy at or under %s: a vendor pays %s each. This buy makes %s."] =
    "Купить за %s или меньше: торговец платит %s за штуку. Эта покупка приносит %s.",
  ["Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit."] =
    "Купить за %s или меньше: оценка на аукционе (цена, которую просит самая дешёвая десятая часть выставленных единиц) составляет %s. Скорость перепродажи неизвестна, поэтому это рискованнее сделки с торговцем. Эта покупка приносит примерно %s после комиссии 5%% и залога.",
  ["under the vendor price. Click Buy to purchase"] =
    "ниже цены торговца. Нажмите Buy, чтобы купить",
  ["far under the market, resale speed unknown. Click Buy to purchase"] =
    "намного ниже рынка, скорость перепродажи неизвестна. Нажмите Buy, чтобы купить",
  ["No deals in your last scan."] =
    "Нет сделок в последнем скане.",
  ["Deals appear as soon as the scan finds them."] =
    "Сделки появятся, как только скан найдёт их.",
  ["GoldCap looks for items listed cheaper than they are worth. SCAN looks again."] =
    "GoldCap ищет предметы, выставленные дешевле, чем они стоят. СКАН сканирует снова.",
  ["No scan of this auction house yet."] =
    "Этот аукцион ещё не сканировался.",
  ["GoldCap scans when you open the auction house; SCAN on this board scans again."] =
    "GoldCap сканирует, когда вы открываете аукцион; СКАН на этой доске сканирует снова.",
  ["In WoW: Forever, GoldCap's prices come from your own auction house scans."] =
    "В WoW: Forever цены GoldCap берутся из ваших собственных сканирований аукциона.",
  ["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."] =
    "Откройте аукцион, и GoldCap отсканирует его за вас; СКАН на вкладке Сделки сканирует снова.",
  ["%ds"] = "%d с",
  ["%dm"] = "%d мин",
  ["%dh"] = "%d ч",
  ["%dd"] = "%d дн.",
  -- WoW: Forever crowd prices (UI/Tooltip.lua, plan 3d).
  ["1 scanner, %s ago"] = "1 сканер, %s назад",
  ["%d scanners, %s ago"] = "сканеров: %d, %s назад",
  ["resale at the AH value of players' scans, %s each, after the 5%% cut and deposit; speed unknown"] = "перепродажа по оценке на аукционе из сканов игроков, %s/шт., за вычетом 5%% комиссии и залога; скорость неизвестна",
  ["Shared with goldcap.gg on your next /reload"] = "Уйдёт на goldcap.gg при следующем /reload",
  ["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."] = "Ваши сканирования остаются на этом компьютере. GoldCap Companion передаёт их на goldcap.gg и приносит цены всех игроков.",
  ["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."] = "GoldCap Companion передаёт ваши сканирования на goldcap.gg после каждого /reload и приносит цены всех игроков.",
  ["You opened %s: its first %s prices are yours."] =
    "Вы открыли %s. Первые цены здесь ваши: %s.",
  ["Your scan updated %s prices on %s. %s of them nobody else had in the last 24 hours."] =
    "Ваше сканирование обновило цен: %s на %s. Из них ни у кого больше не было за последние 24 часа: %s.",
  ["Your scan updated %s prices on %s."] =
    "Ваше сканирование обновило цен: %s на %s.",
  -- Sold tab: tiles, period chips, search, day groups and the sale tooltip.
  ["%d DAYS"] = "%d ДНЕЙ",
  ["TODAY"] = "СЕГОДНЯ",
  ["YESTERDAY"] = "ВЧЕРА",
  ["SUN"] = "ВС",
  ["MON"] = "ПН",
  ["TUE"] = "ВТ",
  ["WED"] = "СР",
  ["THU"] = "ЧТ",
  ["FRI"] = "ПТ",
  ["SAT"] = "СБ",
  ["YOU GOT"] = "ПОЛУЧЕНО",
  ["YOU GOT · %s"] = "ПОЛУЧЕНО · %s",
  ["EACH"] = "ЗА ШТ",
  ["%d sales · after the AH cut"] = "продаж: %d · после комиссии",
  ["1 sale · after the AH cut"] = "1 продажа · после комиссии",
  ["%d here · all on goldcap.gg"] = "здесь %d · все на goldcap.gg",
  ["cost known for %d of %d"] = "закупка известна: %d из %d",
  ["%s of %s"] = "%s из %s",
  ["%s · gold %s, bags %s"] = "%s · золото %s, сумки %s",
  ["set the riding cost: %s"] = "укажите цену верховой езды: %s",
  ["GOLDCAP.GG · %d DAYS"] = "GOLDCAP.GG · %d ДН.",
  ["profit · synced %s ago"] = "прибыль · синхр. %s назад",
  ["after the AH cut · synced %s ago"] = "чистыми · синхр. %s назад",
  ["BEST SALE"] = "ЛУЧШАЯ ПРОДАЖА",
  ["%s profit"] = "%s прибыли",
  ["no sale with a known profit yet"] = "пока нет продаж с известной прибылью",
  ["OPEN SELL"] = "ОТКРЫТЬ SELL",
  ["Find an item"] = "Найти предмет",
  ["JUST SOLD"] = "ТОЛЬКО ЧТО ПРОДАНО",
  ["reaches goldcap.gg on /reload or logout"] = "попадёт на goldcap.gg после /reload или выхода",
  ["ON GOLDCAP.GG"] = "НА GOLDCAP.GG",
  ["latest %d of %d · the rest on goldcap.gg"] = "последние %d из %d · остальное на goldcap.gg",
  ["last %d days"] = "за %d дн.",
  ["%d sales · %s"] = "продаж: %d · %s",
  ["1 sale · %s"] = "1 продажа · %s",
  ["sold today at %s · %d × %s"] = "продано сегодня в %s · %d × %s",
  ["sold %s at %s · %d × %s"] = "продано %s в %s · %d × %s",
  ["sold, the money is in your mail · %d × %s"] = "продано, деньги ждут в почте · %d × %s",
  ["Sale price"] = "Цена продажи",
  ["Auction house cut"] = "Комиссия аукциона",
  ["Auction house cut, 5%"] = "Комиссия аукциона, 5%",
  ["You got"] = "Вы получили",
  ["You paid (%s)"] = "Вы заплатили (%s)",
  ["%s each"] = "%s за шт.",
  ["Sniper"] = "снайпер",
  ["BUY list"] = "список BUY",
  ["set by you"] = "указано вами",
  ["the auction house"] = "аукцион",
  ["crafted"] = "крафт",
  ["The profit is worked out once the money arrives."] = "Прибыль посчитается, когда придут деньги.",
  ["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."] =
    "GoldCap не видел этой покупки, поэтому прибыль показать нельзя. Укажите, во что она вам обошлась, во вкладке SELL.",
  ["Market now %s · you sold %d%% above it"] = "Рынок сейчас %s · вы продали на %d%% дороже",
  ["Market now %s · you sold %d%% under it"] = "Рынок сейчас %s · вы продали на %d%% дешевле",
  ["Market now %s · you sold at it"] = "Рынок сейчас %s · вы продали по рынку",
  ["Your sales show up here once you open a mailbox with GoldCap loaded."] =
    "Ваши продажи появятся здесь, когда вы откроете почтовый ящик с включённым GoldCap.",
  ["List something in SELL first."] = "Сначала выставьте что-нибудь во вкладке SELL.",
  ["No sales match “%s” today."] = "Сегодня нет продаж по запросу «%s».",
  ["No sales match “%s” in these %d days."] = "Нет продаж по запросу «%s» за эти %d дней.",
  ["No sales today."] = "Сегодня продаж нет.",
  ["No sales in these %d days."] = "За эти %d дней продаж нет.",
  ["SEARCH 30 DAYS"] = "ИСКАТЬ ЗА 30 ДНЕЙ",
  ["SHOW 30 DAYS"] = "ПОКАЗАТЬ 30 ДНЕЙ",
  -- Strings that had stayed English here: the BUY tab, the Sell decks and chips, the Deals boards, imports and chat lines.
  ["  %s · need %d · have %d · buy %d · %s"] = "  %s · нужно %d · есть %d · купить %d · %s",
  [" · watching"] = " · отслеживается",
  ["%d items for %s (%s, %s)"] = "предметов: %d для %s (%s, %s)",
  ["%d lines"] = "строк: %d",
  ["%d lines · %d to buy · %d at the vendor"] = "строк: %d · купить: %d · у торговца: %d",
  ["%d lines · %d to buy · %d to craft · %d at the vendor"] =
    "строк: %d · купить: %d · скрафтить: %d · у торговца: %d",
  ["%d× %s"] = "%d× %s",
  ["%d× %s · %s each · %s"] = "%d× %s · %s за шт. · %s",
  ["..."] = "...",
  ["ACTION"] = "ДЕЙСТВИЕ",
  ["Above this 24-hour rise the resale exit price is treated as spike-inflated and priced down."] =
    "Если цена за 24 часа выросла сильнее этого, цена перепродажи считается раздутой скачком и занижается.",
  ["Alerts"] = "Оповещения",
  ["BUY"] = "ВЗЯТЬ",
  ["BUY %d"] = "КУПИТЬ %d",
  ["Buy cap (% of usual price)"] = "Потолок покупки (% от обычной цены)",
  ["Buy run"] = "закупка BUY",
  ["COMMODITIES"] = "ТОВАРЫ",
  ["Cap: %d%%"] = "Потолок: %d%%",
  ["Commodities: reagents, consumables, gems and enchants the scan found under their region price. These are the rows a live check can approve for buying."] =
    "Товары: реагенты, расходники, самоцветы и чары, которые скан нашёл дешевле цены по региону. Только такие строки живая проверка может одобрить к покупке.",
  ["From goldcap.gg: manage it there"] = "С goldcap.gg: управляйте там",
  ["Gear, pets and recipes need an import that carries the region's prices for them. Paste a fresh string from goldcap.gg."] =
    "Для снаряжения, питомцев и рецептов нужен импорт с ценами региона. Вставьте свежую строку с goldcap.gg.",
  ["GoldCap could not tell which region you are playing in, so it is showing bundled US prices. /goldcap import or /goldcap companion loads your own realm's"] =
    "GoldCap не смог определить ваш регион и показывает встроенные цены US. /goldcap import или /goldcap companion загрузят цены вашего реалма",
  ["GoldCap keeps checking them while this board is open."] =
    "GoldCap продолжает их проверять, пока открыта эта доска.",
  ["GoldCap realm median (unverified)"] = "Медиана реалма GoldCap (не проверена)",
  ["GoldCap region price"] = "Цена GoldCap по региону",
  ["GoldCap region price (ilvl %d)"] = "Цена GoldCap по региону (ур. %d)",
  ["HAVE"] = "ЕСТЬ",
  ["HIDDEN %d"] = "СКРЫТО %d",
  ["IN THE LOT"] = "В ЛОТЕ",
  ["ITEMS"] = "ПРЕДМЕТЫ",
  ["ITEMS %d"] = "ПРЕДМЕТЫ %d",
  ["LISTED AS"] = "ВЫСТАВЛЕНО",
  ["MY LOTS %d"] = "МОИ ЛОТЫ %d",
  ["NEED"] = "НУЖНО",
  ["NO COST"] = "БЕЗ ЧЕКА",
  ["NOW"] = "СЕЙЧАС",
  ["No gear, pets or recipes under their region price right now."] =
    "Сейчас нет снаряжения, питомцев или рецептов дешевле цены по региону.",
  ["Nothing to watch on this board yet."] = "На этой доске пока нечего отслеживать.",
  ["PRICE / UNIT"] = "ЦЕНА / ШТ",
  ["READY"] = "ГОТОВО",
  ["REAGENT"] = "РЕАГЕНТ",
  ["REFUSED %d"] = "ОТКАЗЫ %d",
  ["Restore %s"] = "Вернуть %s",
  ["TO POST %d"] = "ВЫСТАВИТЬ %d",
  ["The BUY tab never pays more than this share of the usual price for a line; it buys what fits and leaves the rest."] =
    "Вкладка BUY никогда не платит за строку больше этой доли обычной цены: покупает то, что укладывается, а остальное оставляет.",
  ["Total: %s"] = "Итого: %s",
  ["UNDER YOU"] = "ПОД ВАМИ",
  ["USUAL"] = "ОБЫЧНО",
  ["YOU GET"] = "ПОЛУЧИТЕ",
  ["auction house error"] = "ошибка аукциона",
  ["auto-synced"] = "синхронизировано автоматически",
  ["bought %d for %s"] = "куплено %d за %s",
  ["buying..."] = "покупка...",
  ["cap: alert target"] = "потолок: цель оповещения",
  ["craft"] = "крафт",
  ["deals %s · items %s · filtered %s"] = "сделки %s · предметы %s · отсеяно %s",
  ["done"] = "готово",
  ["everything bought"] = "всё куплено",
  ["from %s"] = "от %s",
  ["in bags %d · in bank %d"] = "в сумках %d · в банке %d",
  ["in bags %d · in bank %d · in the mailbox %d"] = "в сумках %d · в банке %d · в почтовом ящике %d",
  ["in bags and bank · purchases arrive by mail"] = "в сумках и банке · покупки приходят почтой",
  ["manual import"] = "ручной импорт",
  ["no answer from the auction house"] = "аукцион не ответил",
  ["nothing in your bags to price"] = "в сумках нечего оценивать",
  ["on %s"] = "на %s",
  ["paid %s each"] = "закуп по %s",
  ["plan updated on goldcap.gg"] = "план обновлён на goldcap.gg",
  ["price moved to %s"] = "цена стала %s",
  ["removed %d duplicate purchase record left by a mail-scan bug"] =
    "удалена %d дублирующая запись покупки, оставленная ошибкой сканирования почты",
  ["removed %d duplicate sale record left by a mail-scan bug"] =
    "удалена %d дублирующая запись продажи, оставленная ошибкой сканирования почты",
  ["spent %s · left ~%s"] = "потрачено %s · осталось ~%s",
  ["that does not look like a GoldCap import string"] = "это не похоже на строку импорта GoldCap",
  ["that looks like two import strings pasted together. Paste just one"] =
    "похоже, вставлены две строки импорта подряд. Вставьте одну",
  ["that string carried no prices"] = "в этой строке нет цен",
  ["that string does not name a realm"] = "в этой строке не указан реалм",
  ["that string is too long to import"] = "эта строка слишком длинная для импорта",
  ["the Auction House has not answered for this item yet"] = "аукцион ещё не ответил по этому предмету",
  ["the auction house reported an error"] = "аукцион сообщил об ошибке",
  ["there was nothing to import"] = "импортировать нечего",
  ["this build of GoldCap does not know that region. Update the addon"] =
    "эта версия GoldCap не знает такой регион. Обновите аддон",
  ["usually cheapest around %s · %d%%"] = "обычно дешевле всего около %s · %d%%",
  ["vendor"] = "торговец",
  ["vs %s at the auction house · right-click to buy it whole"] = "против %s на аукционе · ПКМ: купить целиком",
  ["window moved back to the middle of the screen at its default size"] =
    "окно возвращено в центр экрана со стандартным размером",
  ["your saved purchase records are damaged. Cost tracking is off, the rest of GoldCap is running"] =
    "сохранённые записи о покупках повреждены: учёт себестоимости выключен, остальное в GoldCap работает",
  ["▲%d%% over the alert target"] = "▲на %d%% выше цели оповещения",
  ["▲%d%% over usual"] = "▲на %d%% выше обычного",
  ["▲%d%% over your cap"] = "▲на %d%% выше вашего потолка",
  -- The quest reward mark (UI/QuestRewardMark.lua).
  ["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."] =
    "GoldCap: награда в золотой рамке дороже всех на аукционе (%s).",
  -- The vendor note (UI/MerchantNote.lua).
  ["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."] =
    "1 предмет в ваших сумках на аукционе стоит больше (+%s). Оставьте его для аукциона.",
  ["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."] =
    "Предметов в ваших сумках, которые на аукционе стоят больше: %d (+%s). Оставьте их для аукциона.",
  -- BUY 2.0 week 2: a gear line is bought one lot per press (UI/BuyFrame.lua).
  ["BUY ONE · %s"] = "КУПИТЬ ОДИН · %s",
  ["not enough gold"] = "недостаточно золота",
  ["set a cap first"] = "сначала задайте потолок",
  -- BUY 2.0 week 2: a gear line's lots on the dock (UI/BuyFrame.lua).
  ["%s · %d lots"] = "%s · лотов: %d",
  ["%s · 1 lot"] = "%s · 1 лот",
  ["%s · over your cap"] = "%s · выше потолка",
  ["no cap for this item. Right-click the line to set one"] =
    "у этого предмета нет потолка. Задайте его правым кликом по строке",
  -- BUY 2.0 week 2: the vendor panel beside the merchant (UI/BuyVendorPanel.lua).
  ["BUY %d · %s"] = "КУПИТЬ %d · %s",
  ["BUY · %s"] = "КУПИТЬ · %s",
  -- BUY 2.0: the item box and the quick list (UI/BuyFrame.lua).
  ["Could not find that item. Shift-click it, or type its item id."] =
    "Предмет не найден. Сделайте Shift+клик по нему или введите его ID.",
  ["Item to add"] = "Добавить предмет",
  ["Make a list once, buy it here at or under your price."] =
    "Составьте список один раз и покупайте здесь по своей цене или дешевле.",
  ["Remove from the list"] = "Убрать из списка",
  ["or plan a whole profession on goldcap.gg"] = "или спланируйте всю профессию на goldcap.gg",
  -- BUY 2.0: the item box's hint, with the x count (UI/BuyFrame.lua).
  -- Glyphs every face that draws them has (spec/client_text_spec.lua's glyph inventory).
  ["HIDE DETAILS ▲"] = "СКРЫТЬ ДЕТАЛИ ▲",
  ["SHOW DETAILS ▼"] = "ПОКАЗАТЬ ДЕТАЛИ ▼",
  ["plan updated on goldcap.gg · +%d -%d lines"] = "план обновлён на goldcap.gg · строк +%d -%d",
  ["~ goldcap.gg market value, no live quote yet"] =
    "~ рыночная стоимость goldcap.gg, живой котировки пока нет",
  ["→ needs price"] = "→ нужна цена",
  -- BUY 2.0: lists made in the game -- New, Import, Export, Rename, favourites, order, Delete
  ["Items the game has not loaded yet are left out: %d. Export again in a moment."] =
    "Игра ещё не загрузила предметов: %d, они не вошли в список. Экспортируйте снова чуть позже.",
  ["%s and %d more"] = "%s и ещё %d",
  ["+ New"] = "+ Новый",
  ["Add to favourites"] = "Добавить в избранное",
  ["Added %d items to %s."] = "Добавлено предметов: %d (список «%s»).",
  ["Added %d× %s to %s."] = "Добавлено: %d× %s (список «%s»).",
  ["Added %d× %s to a new list, %s."] = "Добавлено: %d× %s (новый список «%s»).",
  ["Copy as a TSM item list"] = "Скопировать как список предметов TSM",
  ["Copy for Auctionator"] = "Скопировать для Auctionator",
  ["Delete"] = "Удалить",
  ["Delete %s? This cannot be undone."] = "Удалить «%s»? Это нельзя отменить.",
  ["Delete this list…"] = "Удалить список…",
  ["Export"] = "Экспорт",
  ["From goldcap.gg: rename or remove it there"] =
    "С goldcap.gg: переименовывайте и удаляйте там",
  ["GoldCap: Import a list"] = "GoldCap: импорт списка",
  ["Import a list…"] = "Импортировать список…",
  ["One list per subgroup"] = "Список на каждую подгруппу",
  ["Import into this list…"] = "Импортировать в этот список…",
  ["Imported %s with %d items."] = "Список «%s» импортирован, предметов: %d.",
  ["List %d"] = "Список %d",
  ["Lists come from goldcap.gg through the companion, or make one here with + New."] =
    "Списки приходят с goldcap.gg через Companion, а свой можно создать здесь кнопкой «+ Новый».",
  ["Lists: click to switch, make, import or export one"] =
    "Списки: нажмите, чтобы сменить, создать, импортировать или экспортировать список",
  ["Move down"] = "Переместить ниже",
  ["Move up"] = "Переместить выше",
  ["Name this list"] = "Название списка",
  ["New list"] = "Новый список",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import."] =
    "Вставьте список с goldcap.gg, из TSM или Auctionator и нажмите «Импорт».",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."] =
    "Вставьте список с goldcap.gg, из TSM или Auctionator и нажмите «Импорт». Предметы добавятся в «%s».",
  ["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."] =
    "Нажмите Ctrl+C, чтобы скопировать, затем импортируйте на вкладке «Покупка» в Auctionator.",
  ["Press Ctrl+C to copy, then import it into a TSM group."] =
    "Нажмите Ctrl+C, чтобы скопировать, затем импортируйте в группу TSM.",
  ["Remove from favourites"] = "Убрать из избранного",
  ["Rename…"] = "Переименовать…",
  ["Save"] = "Сохранить",
  ["The game could not tell which items these are: %s. Shift-click them into the item box instead."] =
    "Игра не смогла определить, что это за предметы: %s. Добавьте их Shift+кликом в поле предмета.",
  ["There are no items in this list."] = "В этом списке нет предметов.",
  ["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."] =
    "Это сжатый экспорт группы TSM, который распаковать может только TSM. Вставьте его на goldcap.gg/list, нажмите там «Скопировать как группу TSM» и вставьте результат сюда.",
  ["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."] =
    "GoldCap не может прочитать такой список. Вставьте список с goldcap.gg, из TSM или Auctionator.",
  ["in game"] = "в игре",
  -- Buy runs: the import result and the vendor list, now that the BUY tab's lists use them.
  ["The run's vendor reagents. Press Ctrl+C to copy the list."] =
    "Реагенты из списка, которые продаёт торговец. Нажмите Ctrl+C, чтобы скопировать список.",
  ["Vendor list"] = "Список для торговца",
  ["run imported: %s (%d lines)"] = "список импортирован: %s (строк: %d)",
  ["the run string is not valid"] = "строка списка повреждена",
  -- BUY: a gear line's tooltip names the lot it buys next (UI/BuyFrame.lua).
  ["next to buy: %s"] = "следующая покупка: %s",
  -- BUY: the item box at the top -- several items at once, typed names, recents (UI/BuyAddBox.lua).
  ["Add"] = "Добавить",
  ["Added %d items to a new list, %s."] = "Добавлено предметов: %d (новый список «%s»).",
  ["Clear"] = "Очистить",
  ["Could not read: %s."] = "Не удалось прочитать: %s.",
  ["Items to add: %d (%s)"] = "К добавлению: %d (%s)",
  ["Recent:"] = "Недавние:",
  ["Shift-click items, type a name, or an item id with x and a count: 2589 x20."] =
    "Сделайте Shift+клик по предметам, введите название или ID предмета с x и количеством: 2589 x20.",
  -- BUY search: what is on sale, the results, opening one and adding it to a list (UI/BuySearch.lua).
  ["AVAILABLE"] = "В НАЛИЧИИ",
  ["Back to %s"] = "К списку «%s»",
  ["Click to buy it here. Right-click to add it to a list."] =
    "Щелчок покупает здесь. Правый щелчок добавляет в список.",
  ["Close search"] = "Закрыть поиск",
  ["How many"] = "Сколько",
  ["Loading more results…"] = "Загружаем ещё результаты…",
  ["More results"] = "Ещё результаты",
  ["Nothing on sale for “%s”."] = "По запросу «%s» ничего не продаётся.",
  ["On sale for “%s”: %d"] = "Найдено по запросу «%s»: %d",
  ["Open the auction house to search what's on sale."] =
    "Откройте аукцион, чтобы искать среди того, что продаётся.",
  ["PRICE FROM"] = "ЦЕНА ОТ",
  ["Search again"] = "Искать снова",
  ["Searching the auction house for “%s”…"] = "Ищем «%s» на аукционе…",
  ["The auction house did not answer. Search again."] = "Аукцион не ответил. Повторите поиск.",
  ["Waiting for the auction house…"] = "Ждём аукцион…",
  -- Craft costs: which reagent had no price and why, and the merchant as a source of cost
  -- (Core/CraftCapture.lua, Core/VendorBuys.lua).
  ["this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed"] =
    "этот рецепт делает из одного материала несколько разных предметов (просеивание, дробление, помол), поэтому себестоимость не считается",
  ["%s ×%d: no purchase of it found, here or on your other characters"] =
    "%s ×%d: покупка не найдена ни у этого персонажа, ни у других твоих персонажей",
  ["%s ×%d: only %d of them were bought, the rest has no price"] =
    "%s ×%d: куплено только %d, у остального нет цены",
  ["%s ×%d: made by prospecting, crushing or milling, not bought"] =
    "%s ×%d: получено просеиванием, дроблением или помолом, не куплено",
  ["%s ×%d: bought as different variants, so which one was used is unclear"] =
    "%s ×%d: куплено в разных вариантах, поэтому неясно, какой использован",
  ["%s: %d at the vendor price, %s each"] =
    "%s: %d по цене торговца, %s за штуку",
  ["%s: priced from another character's purchases"] =
    "%s: цена взята из покупок другого персонажа",
  ["%s: %d at the market price, %s each"] =
    "%s: %d по рыночной цене, по %s за штуку",
  ["Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price"] =
    "Часть этой стоимости является оценкой: реагенты, которые вы не покупали, посчитаны по их текущей цене на аукционе",
  ["Vendor"] =
    "Торговец",
  ["SELLING %d"] = "ПРОДАЮ %d",
  ["NOT SELLING %d"] = "НЕ ПРОДАЮ %d",
  ["POST lists these"] = "их выставляет ВЫСТАВИТЬ",
  ["click one to post it"] = "щёлкните, чтобы выставить",
  ["Selling"] = "Продаю",
  ["Not selling"] = "Не продаю",
  ["POST lists it, and so does the key for posting the next item."] = "Выставляют ВЫСТАВИТЬ и клавиша для следующего предмета.",
  ["POST passes it by. Click the item to post it from the bar below."] = "ВЫСТАВИТЬ его пропускает. Щёлкните по предмету, чтобы выставить его из панели внизу.",
  ["Marked for you: you bought it on DEALS."] = "Отмечено само: вы купили это на вкладке DEALS.",
  ["Click to change."] = "Щёлкните, чтобы изменить.",
  ["Done for this visit"] = "На этот заход готово",
  ["POST passes it by until you close the auction house. Click to have POST list it again."] =
    "ВЫСТАВИТЬ пропускает его, пока вы не закроете аукцион. Щёлкните, чтобы ВЫСТАВИТЬ снова его выставлял.",
  ["Mark what to sell with the circle"] = "Отметьте кружком, что продавать",
  ["PROCEEDS"] = "ВЫРУЧКА",
  ["What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut."] = "Сколько принесёт всё, что выставит ВЫСТАВИТЬ, если продастся по этим ценам, за вычетом 5% комиссии аукциона.",
  ["What your lots bring in if they all sell, after the auction house's 5% cut."] = "Сколько принесут ваши лоты, если продадутся все, за вычетом 5% комиссии аукциона.",
  ["PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it."] = "ВЫРУЧКА минус то, что вы заплатили за этот товар. Видна, только пока GoldCap знает, сколько вы заплатили за весь товар.",
  ["HOW MANY"] = "СКОЛЬКО",
  ["MAX"] = "ВСЁ",
  ["skipped"] = "пропущено",
  ["posted"] = "выставлено",
  ["POST"] = "ВЫСТАВИТЬ",
  ["SKIP"] = "ПРОПУСТИТЬ",
  ["then %s"] = "дальше %s",
  ["need %d"] = "нужно %d",
  ["need %d · have %d"] = "нужно %d · есть %d",
  ["cap %s"] = "потолок %s",
  ["no cap"] = "без потолка",
  ["%s under your cap"] = "на %s ниже потолка",
  ["at your cap"] = "ровно потолок",
  ["for %d"] = "за %d шт.",
  ["goes into %s"] = "для %s",
  ["market price"] = "рыночная цена",
  ["craft %d× (%d per craft)"] = "крафт %d× (по %d за крафт)",
  ["%s spent"] = "потрачено %s",
  ["No list yet"] = "Списка пока нет",
  ["Add to %s"] = "В список «%s»",
  ["Add to a new list"] = "В новый список",
  ["Add %d to a list"] = "Добавить %d в список",
  ["Checking %d gear, pets and recipes…"] = "Проверяем снаряжение, питомцев и рецепты (%d)…",
  ["Deals appear here as the auction house answers."] = "Сделки появятся здесь по мере ответов аукциона.",
  ["checking items %d of %d"] = "проверка предметов: %d из %d",
  ["deals %s · watching %d items"] = "сделки %s · отслеживается предметов: %d",
  ["Flips"] = "Перепродажа",
  ["Rare finds"] = "Редкости",
  ["No flips on this realm right now"] = "Сейчас на этом реалме перепродавать нечего",
  ["No rare finds on this realm right now"] = "Сейчас на этом реалме редкостей нет",
  ["Nothing here you lack"] = "Здесь нет того, чего вам не хватает",
  ["Only what I lack"] = "Только то, чего нет",
  ["Shows only what your account has not collected yet: appearances, pets, toys and mounts, and recipes this character does not know."] =
    "Показывает только то, чего ещё нет в коллекции вашей учётной записи: облики, питомцев, игрушки и транспорт, а также рецепты, которых не знает этот персонаж.",
  ["Ctrl-click to try it on"] = "Ctrl+клик: примерить",
  ["Not collected"] = "Нет в коллекции",
  ["Not known by this character"] = "Этот персонаж не знает",
  ["Appearance known"] = "Облик уже собран",
  ["Cheapest of %d realms"] = "Дешевле всех из %d реалмов",
  ["Among the cheapest 10%% of %d realms"] = "Среди 10%% самых дешёвых из %d реалмов",
  ["Cheaper than 3 in 4 of %d realms"] = "Дешевле, чем на 3 из 4 реалмов (всего %d)",
  ["Sold %d times in 30 days"] = "Продаж за 30 дн.: %d",
  ["Sold once in 30 days"] = "Одна продажа за 30 дн.",
  ["last for %s %s"] = "последняя за %s, %s",
  ["%d days ago"] = "%d дн. назад",
  ["1 day ago"] = "день назад",
  ["%d hours ago"] = "%d ч назад",
  ["1 hour ago"] = "час назад",
  ["less than an hour ago"] = "меньше часа назад",
  ["No sale seen in 30 days"] = "За 30 дн. продаж не замечено",
  ["Sold %d times in 7 days on %d realms"] = "Продаж за 7 дн.: %d, на реалмах: %d",
  ["Rare find: seldom sold, so GoldCap puts no price on it"] =
    "Редкость: продаётся редко, поэтому GoldCap не называет ей цену",
  -- The welcome window (UI/WelcomeFrame.lua): what GoldCap does, the state of the prices, GoldCap Companion.
  ["Welcome to GoldCap"] = "Добро пожаловать в GoldCap",
  ["Your GoldCap prices"] = "Ваши цены GoldCap",
  ["GoldCap puts its prices in item tooltips. At the auction house, the GoldCap tab has:"] =
    "GoldCap показывает свои цены в подсказках к предметам. На аукционе во вкладке GoldCap:",
  ["Finds items listed below what they usually sell for, and checks each one before you buy."] =
    "Находит лоты дешевле обычной цены продажи и проверяет каждый перед покупкой.",
  ["Finds items listed below what a vendor pays, or far below their usual price."] =
    "Находит лоты дешевле, чем платит торговец, или намного дешевле обычной цены.",
  ["Prices everything in your bags. POST lists it, one item per click."] =
    "Оценивает всё в ваших сумках. ВЫСТАВИТЬ выставляет по одному предмету за клик.",
  ["What you sold, and the profit on each sale where GoldCap knows what you paid."] =
    "Что вы продали, и прибыль с каждой продажи, где GoldCap знает, за сколько вы купили.",
  ["Shopping lists for crafting: buys each item up to the price you set."] =
    "Списки покупок для ремесла: покупает каждый предмет не дороже заданной вами цены.",
  ["No prices for your region yet"] = "Для вашего региона цен пока нет",
  ["Only the prices GoldCap came with, from %s ago"] = "Только встроенные в GoldCap цены, собраны %s назад",
  ["Fresh prices from the Companion, %s ago"] = "Свежие цены от Companion, %s назад",
  ["The Companion last sent prices %s ago"] = "Companion последний раз присылал цены %s назад",
  ["You pasted these prices %s ago"] = "Вы вставили эти цены %s назад",
  ["The Companion's prices could not be read"] = "Не удалось прочитать цены от Companion",
  ["Everyone's prices are in, from %s ago"] = "Цены других игроков получены %s назад",
  ["No prices from other players for this auction house yet"] =
    "Цен от других игроков для этого аукциона пока нет",
  ["No fresh prices for your realm, so DEALS finds no deals. GoldCap Companion brings them and keeps them fresh: %s"] =
    "Нет свежих цен для вашего мира, поэтому DEALS не находит выгодных лотов. GoldCap Companion принесёт их и будет сам держать свежими: %s",
  ["Your pasted prices are %s old. GoldCap Companion fetches fresh ones every 30 minutes and brings your groups from goldcap.gg: %s"] =
    "Вставленным ценам уже %s. GoldCap Companion сам загружает свежие каждые 30 минут и приносит ваши группы с goldcap.gg: %s",
  ["GoldCap Companion has not sent prices for %s. Check that it is running, its icon sits next to the clock: %s"] =
    "GoldCap Companion не присылал цен уже %s. Проверьте, что он запущен, его значок рядом с часами: %s",
  ["Could not read what the Companion wrote. Update GoldCap and GoldCap Companion: %s"] =
    "Не удалось прочитать то, что записал Companion. Обновите GoldCap и GoldCap Companion: %s",
  ["GoldCap Companion adds every GoldCap player's scans of this auction house to yours, for more items with a price and newer prices: %s"] =
    "GoldCap Companion добавляет к вашим сканам сканы этого аукциона от всех игроков GoldCap, так у большего числа предметов есть цена и цены свежее: %s",
  ["No prices from other players for this auction house yet. If GoldCap Companion is not running, start it: %s"] =
    "Цен от других игроков для этого аукциона пока нет. Если GoldCap Companion не запущен, запустите его: %s",
  ["Nobody has shared a scan of this auction house for %s"] =
    "Никто не делился сканированием этого аукциона уже %s",
  ["Prices from your own scans only"] = "Цены только из ваших сканирований",
  ["These prices came with GoldCap and change only when GoldCap itself updates. DEALS needs fresh prices from your realm to find anything, so until then it finds no deals."] =
    "Эти цены пришли вместе с GoldCap и меняются, только когда обновляется сам GoldCap. Вкладке DEALS нужны свежие цены вашего мира, без них она не найдёт ни одной сделки.",
  ["GoldCap came with no prices for your region, so DEALS finds no deals until GoldCap Companion brings them."] =
    "В GoldCap нет встроенных цен для вашего региона, поэтому DEALS не найдёт сделок, пока их не принесёт GoldCap Companion.",
  ["New prices reach GoldCap every time you log in or type /reload."] =
    "Новые цены попадают в GoldCap при каждом входе в игру или после /reload.",
  ["DEALS and every price go by what it sent last. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."] =
    "DEALS и все цены опираются на то, что он прислал последним. Проверьте, что GoldCap Companion запущен (его значок рядом с часами), и введите /reload.",
  ["A pasted string goes stale within a day. GoldCap Companion fetches fresh prices for you every 30 minutes."] =
    "Вставленная строка устаревает за день. GoldCap Companion сам загружает свежие цены каждые 30 минут.",
  ["With prices this old, DEALS can show deals that are no longer there. GoldCap Companion fetches fresh prices for you every 30 minutes."] =
    "С такими старыми ценами DEALS может показывать сделки, которых уже нет. GoldCap Companion сам загружает свежие цены каждые 30 минут.",
  ["GoldCap could not read what the Companion wrote (%s). Update GoldCap and GoldCap Companion, then type /reload."] =
    "GoldCap не смог прочитать то, что записал Companion (%s). Обновите GoldCap и GoldCap Companion, затем введите /reload.",
  ["Your own scans and every other GoldCap player's are combined: for each item, the newer price wins."] =
    "Ваши сканирования объединяются со сканированиями других игроков GoldCap: для каждого предмета берётся более свежая цена.",
  ["Your own scans still work. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."] =
    "Ваши сканирования по-прежнему работают. Проверьте, что GoldCap Companion запущен (его значок рядом с часами), и введите /reload.",
  ["Your own scans work meanwhile. If GoldCap Companion is not running, start it and type /reload."] =
    "Пока работают ваши сканирования. Если GoldCap Companion не запущен, запустите его и введите /reload.",
  ["GoldCap Companion is running and brings every scan of this auction house that GoldCap players share, but none has come in lately. Your own scans still work."] =
    "GoldCap Companion запущен и приносит каждое сканирование этого аукциона, которым делятся игроки GoldCap, но в последнее время новых не было. Ваши сканирования по-прежнему работают.",
  ["GoldCap knows only what your own scans of this auction house found. With GoldCap Companion you also get the scans of every GoldCap player here: more items with a price, and newer prices."] =
    "GoldCap знает только то, что нашли ваши сканирования этого аукциона. С GoldCap Companion вы получаете и сканирования всех игроков GoldCap здесь: больше предметов с ценой и более свежие цены.",
  ["Get GoldCap Companion"] = "Установите GoldCap Companion",
  ["A small free app for Windows, macOS and Linux. It fetches your realm's prices every 30 minutes, with no account needed. Its code is open on GitHub."] =
    "Небольшая бесплатная программа для Windows, macOS и Linux. Загружает цены вашего мира каждые 30 минут, аккаунт не нужен. Её код открыт на GitHub.",
  ["A small free app for Windows, macOS and Linux. Every 30 minutes it brings the prices every GoldCap player scanned on your auction house, with no account needed. Its code is open on GitHub."] =
    "Небольшая бесплатная программа для Windows, macOS и Linux. Каждые 30 минут приносит цены, которые игроки GoldCap насканировали на вашем аукционе, аккаунт не нужен. Её код открыт на GitHub.",
  ["1. Copy this link (%s) and open it in your browser:"] =
    "1. Скопируйте ссылку (%s) и откройте её в браузере:",
  ["2. Install GoldCap Companion and start it."] = "2. Установите GoldCap Companion и запустите его.",
  ["3. Back in the game, type /reload."] = "3. Вернитесь в игру и введите /reload.",
  ["Not installed on this computer? It is here:"] = "Не установлен на этом компьютере? Он здесь:",
  ["The latest version is here:"] = "Последняя версия здесь:",
  ["/gc companion opens this window again."] = "/gc companion снова откроет это окно.",
  ["Got it"] = "Понятно",
  ["Don't remind me"] = "Не напоминать",
  ["sells within a day"] = "продаётся за день",
  ["sells in about 1 day"] = "продаётся примерно за 1 день",
  ["sells in about %d days"] = "продаётся примерно за %d дн.",
  ["Sell here for %s, %s"] = "Продавайте здесь за %s, %s",
  ["Sell on %s for %s, %s"] = "Продавайте на %s за %s, %s",
  ["Pays more on %s, where you have no character: %s, %s"] = "Дороже на %s, где у вас нет персонажа: %s, %s",
  ["Among the 5 cheapest of %d realms"] = "В пятёрке самых дешёвых (реалмов: %d)",
  ["The price is checked against what this sold for across the region. Where it sells best is below."] = "Цена сверена с тем, за сколько это продавалось в регионе. Где продать выгоднее всего, ниже.",
  ["Sell on"] = "Продать на",
  ["Cheapest realms"] = "Дешёвые реалмы",
  ["Better on"] = "Дороже на",
  ["under a day"] = "меньше дня",
  ["about 1 day"] = "около 1 дня",
  ["about %d days"] = "около %d дн.",
  ["top 5 of %d"] = "топ-5 из %d",
  ["this realm"] = "этот реалм",
  ["Put in the Warband Bank"] = "Положить в банк отряда",
  ["Take out to sell here"] = "Забрать и продать здесь",
  ["Can't be sold"] = "Не продаётся",
  ["Warbound until equipped: the auction house refuses it"] = "Привязано к отряду до надевания: аукцион его не примет",
  ["here: %s, %s"] = "здесь: %s, %s",
  ["for %s: %s, %s"] = "для %s: %s, %s",
  ["Then log in a character on that realm and open a bank: GoldCap lists what to take out."] = "Потом зайдите персонажем на этот реалм и откройте банк: GoldCap покажет, что забрать.",
  ["Then list it from GoldCap's Sell tab at the auction house."] = "Потом выставьте его на аукционе через вкладку «Продажа» GoldCap.",
  ["At a bank: which flips to put in the Warband Bank for another of your realms, and which to take out and sell here. /gc route lists them anywhere."] = "В банке: какие вещи на перепродажу положить в банк отряда для другого вашего реалма, а какие забрать и продать здесь. /gc route покажет список где угодно.",
  ["Where each flip sells comes with the Companion's region data: nothing to go on yet."] = "Где что продаётся, приходит с данными региона от Companion: пока данных нет.",
  ["Nothing in your bags sells notably better on another of your realms."] = "В сумках нет ничего, что заметно дороже продаётся на другом вашем реалме.",
  ["What to take out of the Warband Bank shows at a bank."] = "Что забрать из банка отряда, видно в банке.",
  -- Followed groups: the DEALS chip and its tooltip.
  ["GROUP"] = "ГРУППА",
  ["Listed at or under the deal price of a group you follow (%s)"] = "Выставлено по выгодной цене группы, на которую вы подписаны, или дешевле (%s)",
  -- Followed groups: a group's selling rule in words (Core/GroupRules.lua).
  ["1 at a time"] = "по одному",
  ["all you have"] = "всё, что есть",
  ["%d h"] = "%d ч",
  ["not under %d%% of usual"] = "не ниже %d%% от обычной цены",
  ["not under the cost to craft"] = "не ниже себестоимости крафта",
  ["%d%% cheaper each time it comes back"] = "на %d%% дешевле после каждого возврата",
  -- Followed groups: SELL's row, its mark and the dock.
  ["Group you follow: %s"] = "Группа, на которую вы подписаны: %s",
  ["Marked for you: it is in a group you follow."] = "Отмечено само: это в группе, на которую вы подписаны.",
  ["under group floor"] = "ниже порога группы",
  ["the market is under your group's floor. Type a price to post anyway"] = "рынок ниже порога вашей группы. Введите цену, чтобы всё равно выставить",
  -- Followed groups: cancel by a group's floor, and the cancel threshold.
  ["Min. undercut to cancel (%)"] = "Мин. перебив для снятия (%)",
  ["Cancel only when someone undercuts you by more than this percent. At 0 any undercut counts. Lots far below their value are always queued."] = "Снимать лот, только если вас перебили больше чем на этот процент. При 0 считается любой перебив. Лоты намного дешевле своей цены попадают в очередь всегда.",
  ["small undercut"] = "мелкий перебив",
  ["relisting would go under your group's floor. Hold"] = "перевыставление ушло бы ниже порога вашей группы. Придержите",
  ["undercut by less than your cancel setting. Hold"] = "перебили меньше, чем задано в настройке снятия. Придержите",
  -- the cancel run (groups in the addon, task 13)
  ["Cancel %d lots? You lose %s in deposits. One press per lot, CONFIRM first."] = "Лотов к отмене: %d. Вы потеряете залог: %s. По нажатию на каждый лот, первое на ПОДТВЕРДИТЬ.",
  ["Cancel %d lots? One press per lot, CONFIRM first."] = "Лотов к отмене: %d. По нажатию на каждый лот, первое на ПОДТВЕРДИТЬ.",
  ["Cancel 1 lot? You lose its %s deposit. Press CONFIRM."] = "Отменить 1 лот? Вы потеряете залог: %s. Нажмите ПОДТВЕРДИТЬ.",
  ["Cancel 1 lot? Press CONFIRM."] = "Отменить 1 лот? Нажмите ПОДТВЕРДИТЬ.",
  ["CANCEL NEXT (%d)"] = "ОТМЕНИТЬ ЕЩЁ (%d)",
  ["Press again to cancel the next lot"] = "Нажмите ещё раз, чтобы отменить следующий лот",
  ["Stopped: 20 seconds without a press"] = "Остановлено: 20 секунд без нажатия",
  ["Stop"] = "Стоп",
  ["VENDOR"] = "ТОРГОВЕЦ",
  ["Better at vendor"] = "Выгоднее торговцу",
  ["Forget kept items"] = "Забыть сохранённые предметы",
  ["Sell to vendor lists unbound items a vendor pays as much for as the auction house would after its cut, judged only by an auction house price from the last 24 hours, never by the prices built into the addon. Grey items are left to the vendor window's own Sell All Junk button."] = "Продать торговцу показывает непривязанные предметы, за которые торговец платит столько же, сколько аукцион после своей комиссии, только по цене аукциона за последние 24 часа, никогда по ценам, встроенным в аддон. Серые предметы остаются кнопке продажи хлама в окне торговца.",
  ["Sell to vendor"] = "Продать торговцу",
  ["Sell %d for %s"] = "Продать %d за %s",
  ["%d more after this"] = "Ещё %d после этой",
  ["Right click a line to keep that item."] = "Щёлкните строку правой кнопкой, чтобы оставить этот предмет.",
  ["Never sell this"] = "Никогда не продавать",
  ["The game sells one stack per press here."] = "Игра продаёт здесь по одной стопке за нажатие.",
  ["Sold %d stacks for %s. Buyback keeps the last 12 you sold."] = "Продано стопок: %d, за %s. Выкуп хранит 12 последних продаж.",
  ["Sold 1 stack for %s. Buyback keeps the last 12 you sold."] = "Продана 1 стопка за %s. Выкуп хранит 12 последних продаж.",
  ["Reagents cost %s"] = "Реагенты стоят %s",
  ["One craft sells for %s after the auction house cut"] = "Один крафт продаётся за %s за вычетом комиссии аукциона",
  ["Profit %s"] = "Прибыль %s",
  ["No GoldCap price for %s"] = "Нет цены GoldCap: %s",
  ["Worth crafting"] = "Выгодно крафтить",
  ["Sells about %s a day"] = "Продаётся примерно %s раз в день",
  ["Slow seller"] = "Продаётся медленно",
  ["1 recipe has no GoldCap price for a reagent or what it makes"] = "У 1 рецепта нет цены GoldCap на реагент или на то, что он создаёт",
  ["%d recipes have no GoldCap price for a reagent or what it makes"] = "Рецептов без цены GoldCap на реагент или результат: %d",
  ["Each reagent at its cheapest quality"] = "Каждый реагент в самом дешёвом качестве",
  ["No recipe here has a GoldCap price yet"] = "Здесь пока нет рецептов с ценой GoldCap",
  ["1 recipe makes no profit now"] = "Рецептов без прибыли сейчас: 1",
  ["%d recipes make no profit now"] = "Рецептов без прибыли сейчас: %d",
  ["No recipe here makes a profit now"] = "Здесь сейчас нет рецептов с прибылью",
  ["This recipe"] = "Этот рецепт",
  ["Add to queue"] = "В очередь",
  ["Restock to"] = "Пополнить до",
  ["How many crafts of %s?"] = "Сколько раз скрафтить %s?",
  ["Restock %s to how many? 0 takes it off the queue."] = "Пополнить %s до скольких? 0 убирает из очереди.",
  ["Type a whole number"] = "Введите целое число",
  ["Queue"] = "Очередь",
  ["%d to craft"] = "Скрафтить: %d",
  ["Restock to %d: %d held"] = "Пополнить до %d: есть %d",
  ["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] = "Лоты на аукционе ещё не учтены: откройте на аукционе вкладку «Продажа» GoldCap",
  ["Remove from queue"] = "Убрать из очереди",
  ["The queue is empty. Add a recipe from This recipe."] = "Очередь пуста. Добавьте рецепт в блоке «Этот рецепт».",
  ["Missing"] = "Не хватает",
  ["%d %s"] = "%d %s",
  ["%d %s in the mailbox"] = "%d %s в почтовом ящике",
  ["%s is not sold on the auction house"] = "%s не продаётся на аукционе",
  ["Nothing is missing for the queue"] = "Для очереди всего хватает",
  ["Make a BUY list"] = "Создать список BUY",
  ["Craft queue"] = "Очередь крафта",
  ["BUY list %s is ready in the BUY tab at the auction house"] = "Список BUY %s готов на вкладке BUY на аукционе",
  ["Currency %d"] = "Валюта %d",
  ["%d in bags, %d in the Warband Bank"] = "%d в сумках, %d в банке отряда",
  ["Keep in bags: %d of each"] = "Оставлять в сумках: по %d",
  ["How many of each item in %s to keep in your bags?"] = "Сколько каждого предмета из %s оставлять в сумках?",
  ["Stays in bags: %s ×%d, can still be refunded"] = "Остаётся в сумках: %s ×%d, его ещё можно вернуть торговцу",
  ["Stays in bags: %s ×%d, the Warband Bank does not take it"] = "Остаётся в сумках: %s ×%d, банк отряда его не принимает",
  ["%d in bags, %d in your bank"] = "%d в сумках, %d в вашем банке",
  ["Stays in bags: %s ×%d, your bank does not take it"] = "Остаётся в сумках: %s ×%d, ваш банк его не принимает",
  ["None of your groups' items are in your bags or this bank."] = "Предметов ваших групп нет ни в сумках, ни в этом банке.",
  ["None of your groups' items are in your bags or this bank. %s holds some of them: pick it at the top."] =
    "Предметов ваших групп нет ни в сумках, ни в этом банке. Часть лежит в «%s»: выберите его вверху.",
  ["You follow no groups yet. Follow some on goldcap.gg under Groups, and the GoldCap Companion brings them here: what each holds in your bags and this bank, to store or take out in one press."] =
    "Вы пока не подписаны ни на одну группу. Подпишитесь на goldcap.gg в разделе «Группы», и GoldCap Companion принесёт их сюда: что из каждой лежит в сумках и в этом банке, чтобы убрать или забрать одним нажатием.",
  -- GoldCap Hoard, the window beside the bank (UI/HoardFrame.lua, UI/HoardRow.lua).
  ["Hoard"] = "Клад",
  ["Bags %d free"] = "Сумки: свободно %d",
  ["Bank %d free"] = "Банк: свободно %d",
  ["Your groups"] = "Ваши группы",
  ["bags"] = "сумки",
  ["bank"] = "банк",
  ["Store all"] = "Положить всё",
  ["Take all out"] = "Забрать всё",
  ["Store"] = "Положить",
  ["Take out"] = "Забрать",
  ["%s ×%d (%d left)"] = "%s ×%d (осталось %d)",
  ["Nothing to move"] = "Нечего переносить",
  ["Gather"] = "Сбор",
  ["Craft"] = "Крафт",
  ["Flip"] = "Перепродажа",
  ["Stock"] = "Запас",
  ["%d groups"] = "Групп: %d",
  ["%d more groups have nothing to move at this bank"] = "Ещё групп, где в этом банке нечего переносить: %d",
  ["1 more group has nothing to move at this bank"] = "Ещё 1 группа: в этом банке нечего переносить",
  -- Its search row, the selection bar and a run's cast bar (UI/HoardList.lua).
  ["To move here %d"] = "К переносу %d",
  ["All %d"] = "Все %d",
  ["By value"] = "По цене",
  ["By name"] = "По названию",
  ["No group or item matches your search."] = "Ни одна группа и ни один предмет не подходят под поиск.",
  ["%d groups selected"] = "Выбрано групп: %d",
  ["1 group selected"] = "Выбрана 1 группа",
  ["Clear the selection"] = "Снять выбор",
  ["Moving to %s"] = "Переносим в %s",
  ["Moving to your bags"] = "Переносим в сумки",
  ["Tick groups to move several at once"] = "Отметьте группы, чтобы перенести несколько сразу",
  ["Worth about %s"] = "Стоимость около %s",
  ["Stop moving"] = "Остановить перенос",
  ["%d stacks into %s"] = "Стопок: %d, в %s",
  ["1 stack into %s"] = "1 стопка в %s",
  ["%d stacks into your bags"] = "Стопок: %d, в сумки",
  ["1 stack into your bags"] = "1 стопка в сумки",
  -- GoldCap Hoard: its tiles (UI/HoardTiles.lua), carry cards (UI/HoardCarry.lua) and footer (UI/HoardFooter.lua).
  [", %d not shown"] = ", скрыто: %d",
  ["Ready now"] = "Готово сейчас",
  ["Prices are up"] = "Цены выросли",
  ["For your crafts"] = "Для крафта",
  ["Put away"] = "Убрать",
  ["%d items sell above your usual price"] = "Продаются дороже обычной цены, предметов: %d",
  ["1 item sells above your usual price"] = "Продаётся дороже обычной цены: 1 предмет",
  ["Nothing sells above your usual price now"] = "Сейчас ничего не продаётся дороже обычной цены",
  ["Reagents for the %d crafts in your queue"] = "Реагенты для очереди крафта, крафтов: %d",
  ["Reagents for the craft in your queue"] = "Реагенты для крафта в очереди",
  ["Your craft queue is empty"] = "Очередь крафта пуста",
  ["What you are not selling now, keeping what each group keeps"] = "То, что вы сейчас не продаёте; сколько держит каждая группа, остаётся в сумках",
  ["Take out %s"] = "Забрать на %s",
  ["Take out %d stacks"] = "Забрать, стопок: %d",
  ["Take out 1 stack"] = "Забрать 1 стопку",
  ["Store %d stacks"] = "Положить, стопок: %d",
  ["Store 1 stack"] = "Положить 1 стопку",
  ["%d stacks"] = "Стопок: %d",
  ["1 stack"] = "1 стопка",
  ["and %d more"] = "и ещё: %d",
  ["These sell above the usual price you set for their group."] = "Они продаются дороже обычной цены, заданной для их группы.",
  ["Price per unit: now / usual"] = "Цена за штуку: сейчас / обычная",
  ["Takes them out to your bags, ready for the Sell tab."] = "Забирает их в сумки, к вкладке «Продажа».",
  ["What your craft queue needs that your bags lack, from this bank."] = "Чего не хватает в сумках для очереди крафта, из этого банка.",
  ["Per reagent: need / in bags / taken"] = "По реагентам: нужно / в сумках / заберём",
  ["Leaves out what sells above its usual price and what your craft queue needs."] = "Кроме того, что продаётся дороже обычной цены, и того, что нужно очереди крафта.",
  ["Carry to another realm"] = "Перевезти на другой реалм",
  ["Put in"] = "Положить",
  ["Make room"] = "Освободить место",
  ["Put back"] = "Вернуть",
  ["Moves every stack in your bags that %s takes, except a hearthstone, and remembers what went for Put back."] = "Переносит в «%s» каждую стопку из сумок, которую он принимает, кроме камня возвращения, и запоминает их для «Вернуть».",
  ["Takes back from %s what Make room put there. It lands wherever your bags have room, not in its old slots."] = "Забирает из «%s» то, что туда положило «Освободить место». Оно попадёт в свободные ячейки сумок, а не на прежние места.",
  ["What Make room put away is in %s: switch to it to put it back."] = "То, что убрало «Освободить место», лежит в «%s»: переключитесь туда, чтобы вернуть.",
  ["Make room has put nothing away to bring back."] = "«Освободить место» ничего не убирало, возвращать нечего.",
  ["Prices from the Companion, %s ago"] = "Цены от Companion, %s назад",
  ["What Make room put away is still in %s: put it back first."] = "То, что убрало «Освободить место», всё ещё лежит в «%s»: сначала верните это.",
  ["A newer version of GoldCap saved what Make room remembers: update GoldCap to use it."] = "Более новая версия GoldCap сохранила то, что помнит «Освободить место»: обновите GoldCap, чтобы пользоваться им.",
  ["GoldCap does not know this character's name and realm yet, so Make room cannot remember what it puts away."] = "GoldCap ещё не знает имя и игровой мир этого персонажа, поэтому «Освободить место» не может запомнить, что убирает.",
  ["GROUPS"] = "ГРУППЫ",
  ["ALL %d"] = "ВСЕ %d",
  ["MY GROUPS %d"] = "МОИ ГРУППЫ %d",
  ["MY GROUPS"] = "МОИ ГРУППЫ",
  ["Post goes through your groups only"] = "ВЫСТАВИТЬ идёт только по вашим группам",
  ["Post goes through %s only"] = "ВЫСТАВИТЬ идёт только по группе %s",
  ["Nothing left in this group"] = "В этой группе ничего не осталось",
  ["Everything from this group in your bags is posted. Pick ALL to see the rest of your bags."] = "Всё из этой группы в ваших сумках выставлено. Выберите ВСЕ, чтобы увидеть остальное в сумках.",
  ["Posting your groups: %d of %d done"] = "Выставляем ваши группы: готово %d из %d",
  ["Posting %s: %d of %d done"] = "Выставляем %s: готово %d из %d",
  ["your default from Settings"] = "ваша по умолчанию из настроек",
  ["%s never posts under %s"] = "%s никогда не выставляется ниже %s",
  ["Default price"] = "Цена по умолчанию",
  ["Every item opens at this price. A group's floor still holds, and a price under what you paid still shows in red."] = "Каждый предмет открывается с этой ценой. Порог группы по-прежнему действует, а цена ниже цены покупки по-прежнему горит красным.",
  ["Sells here within a day"] = "Здесь продаётся за день",
  ["Sells here in about 1 day"] = "Здесь продаётся примерно за 1 день",
  ["Sells here in about %d days"] = "Здесь продаётся примерно за %d дн.",
  ["Sells on %s within a day"] = "На %s продаётся за день",
  ["Sells on %s in about 1 day"] = "На %s продаётся примерно за 1 день",
  ["Sells on %s in about %d days"] = "На %s продаётся примерно за %d дн.",
  ["Sold once in 7 days"] = "Одна продажа за 7 дн.",
  ["Sold %d times in 7 days"] = "Продаж за 7 дн.: %d",
  ["after the 5% cut, if it sells at the region's price"] = "за вычетом 5%, если продастся по цене региона",
  ["a unit, at or under the group's price of %s"] = "за штуку, по цене группы %s или ниже",
  ["From a group you follow on goldcap.gg. Whether it resells is yours to judge."] = "Из группы, на которую вы подписаны на goldcap.gg. Перепродастся ли, решать вам.",
  ["Region price"] = "Цена региона",
  ["Group's price"] = "Цена группы",
  ["at or under the group's price. Click Buy to purchase"] = "по цене группы или дешевле. Нажмите Buy, чтобы купить",
  ["price checked a moment ago. Whether it sells is your call"] = "цена только что проверена. Продастся ли, решать вам",
  ["GoldCap is checking prices here"] = "GoldCap проверяет здесь цены",
  ["The auction house shows GoldCap's searches in this list, so it changes on its own. To use the list yourself, search, pick a category or click the star. GoldCap then leaves it to you until you click AUTO or SCAN."] =
    "Аукцион показывает в этом списке поиски GoldCap, поэтому список меняется сам. Чтобы пользоваться им самому, введите поиск, выберите категорию или нажмите звёздочку. Тогда GoldCap не тронет список, пока вы не нажмёте АВТО или СКАН.",
  ["On the Items board, Auto keeps checking the items this board watches, round after round. Switch to Commodities and it scans the commodity market again."] =
    "На доске предметов Авто раз за разом проверяет предметы, за которыми следит эта доска. Переключитесь на товары, и оно снова будет сканировать рынок товаров.",
  ["Craft %d"] = "Скрафтить %d",
  ["Crafts %d now, one after another, with the reagents the profession window would use. Moving stops it."] =
    "Скрафтит %d сейчас, одно за другим, из тех реагентов, что взяло бы окно профессии. Движение прерывает крафт.",
  ["Open %s to craft it here."] = "Откройте %s, чтобы скрафтить здесь.",
  ["Open this recipe's profession to craft it here."] =
    "Откройте профессию этого рецепта, чтобы скрафтить здесь.",
  ["Not enough reagents for one craft. Missing below says what to get."] =
    "Реагентов не хватает даже на один крафт. Что докупить, написано ниже, в «Не хватает».",
}
