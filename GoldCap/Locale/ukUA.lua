local _, GC = ...

-- Ukrainian. There is no Ukrainian WoW client and GetLocale() never returns ukUA, so this
-- language is reachable only through the picker in Settings -- which is why the picker exists.
-- Terminology follows the site's own wording where the site has it; the Cyrillic renders in the
-- addon's bundled font, which covers і, ї and ґ (checked against the font's cmap).
--
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ukUA = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d по %s за штуку  (%s разом, %s комісія)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion оновлює це сам: /goldcap companion.",
  [" · %d keys"] = " · ключів: %d",
  [" · below cost"] = " · нижче собівартості",
  [" · identity unresolved"] = " · позиція не впізнана",
  [" · stale %ds"] = " · застаріло %dс",
  [" — Check again"] = " — перевірте ще раз",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — команди: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (або коротко /gc)",
  ["%d (whole lot)"] = "%d (увесь лот)",
  ["%d ahead of you"] = "%d попереду вас",
  ["%d at %s"] = "%d по %s",
  ["%d caps · %s"] = "%d стель · %s",
  ["%d days"] = "%d дн.",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d угод з останнього сканування -- Full Scan, щоб оновити",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "%d відсіяно: важко перепродати або нижче вашого мінімального прибутку з купівлі",
  ["%d held back"] = "%d притримано",
  ["%d held back from posting"] = "%d притримано від виставлення",
  ["%d hidden -- the live check refused them"] = "%d приховано -- жива перевірка їх відхилила",
  ["%d hits"] = "знахідок: %d",
  ["%d in %d lots"] = "%d у %d лотах",
  ["%d in 1 lot"] = "%d в 1 лоті",
  ["%d lots, %s asked"] = "%d лотів, просять %s",
  ["%d of %d"] = "%d з %d",
  ["%d of %d at or under your cap"] = "%d з %d за вашою стелею або дешевше",
  ["%d of %d done"] = "готово %d з %d",
  ["%d prices in one request · books still loading"] = "%d цін одним запитом · стакани довантажуються",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d відхилено живою перевіркою -- натисніть \"HIDDEN %d\" вгорі, щоб переглянути",
  ["%d units"] = "%d шт.",
  ["%d units · %d prices"] = "%d шт. · %d цін",
  ["%d · %d/%d covered"] = "%d · %d/%d покрито",
  ["%d/%d covered"] = "%d/%d покрито",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s за штуку    разом %s -> %s",
  ["%s ahead"] = "%s попереду",
  ["%s needs a number, for example /gc weights %s 1.5"] = "%s: потрібне число, наприклад /gc weights %s 1.5",
  ["%s under you"] = "%s дешевше за вас",
  ["%s units in %d prices"] = "%s шт. за %d цінами",
  ["%s · %s under market"] = "%s · на %s нижче ринку",
  ["%s · at market price"] = "%s · за ринковою ціною",
  ["%s — %d unit%s without a cost"] = "%s — %d одиниц%s без собівартості",
  ["%s → craft %d× (%d per craft)"] = "%s → крафт %d× (по %d за крафт)",
  ["%s+ ahead"] = "%s+ попереду",
  ["%s+, %d prices read"] = "%s+, прочитано %d цін",
  ["1 lot, %s asked"] = "1 лот, просять %s",
  ["24h trend"] = "Тренд за 24г",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Прочерк означає, що собівартість відома не за всіма одиницями — з ринкової ціни вона ніколи не вигадується.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Орієнтир, а не обіцянка: перепродаж за 95% імпортованої ринкової вартості, на кількість, яку схвалить сама перевірка.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Якщо кілька покупок згорнуті в один рядок, видаляться вони всі.",
  ["AH answered empty %ds ago"] = "Аукціон відповів порожньо %dс тому",
  ["AH value"] = "Оцінка на аукціоні",
  ["AH, cheapest version"] = "Аукціон, найдешевша версія",
  ["AUTO"] = "АВТО",
  ["AUTO · SCANNING"] = "АВТО · СКАН",
  ["AUTOMATION & ALERTS"] = "АВТОМАТИКА ТА СПОВІЩЕННЯ",
  ["AVOID"] = "УНИКАТИ",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Вище цього зростання за 24 години ринкова вартість вважається стрибком і занижується.",
  ["Above your price -- quoted %s, your price %s"] = "Вище за вашу ціну -- котирування %s, ваша ціна %s",
  ["Alert target"] = "Ціль сповіщення",
  ["All"] = "Усі",
  ["Archive this run"] = "Перенести список до архіву",
  ["Archived"] = "Архів",
  ["Asks for a second click to confirm."] = "Потребує другого кліку для підтвердження.",
  ["At a vendor"] = "У торговця",
  ["At your pace you reach it at level %d."] = "У вашому темпі ви назбираєте до %d рівня.",
  ["At your pace you will be %s short at level 40."] = "У вашому темпі на 40 рівні бракуватиме %s.",
  ["At your price"] = "За вашою ціною",
  ["Auction House did not answer — press Refresh"] = "Аукціон не відповів — натисніть Refresh",
  ["Auction House is not open"] = "Аукціон не відкрито",
  ["Auto-scan on next AH visit"] = "Автосканування при наступному візиті на АД",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Авто: тримає Full Scan увімкненим постійно й миттєво поступається, коли ви купуєте, пошукайте на аукціоні самі або перевірте пошту. Клік перемикає.",
  ["Avoid"] = "Уникати",
  ["BOOKS %d/%d"] = "СТАКАНИ %d/%d",
  ["BRAKES"] = "ГАЛЬМА",
  ["BUY — unverified"] = "КУПИТИ — без перевірки",
  ["Background check"] = "Фонова перевірка",
  ["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."] =
    "Blizzard ще не оприлюднила ціну верхової їзди. Введіть /gc mount і очікувану ціну.",
  ["Blizzard's price: %s"] = "Ціна Blizzard: %s",
  ["Blizzard's price: %s · %d s left"] = "Ціна Blizzard: %s · лишилося %d с",
  ["Bought"] = "Куплено",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "Точка беззбитковості — найнижча ціна, яка після комісії ще повертає вашу собівартість. Нижче — збиток.",
  ["Bundled %s data"] = "Вбудовані дані %s",
  ["Bundled data"] = "Вбудовані дані",
  ["Buy"] = "Купити",
  ["Buy it whole instead"] = "Краще купити цілим",
  ["Buy less"] = "Купити менше",
  ["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"] = "Покупки: %s · рядків %d · купити %d · у торговця %d · витрачено %s · лишилося ~%s",
  ["Buy: no run selected."] = "Покупки: список не вибрано.",
  ["CANCEL %d"] = "СКАСУВАТИ %d",
  ["CANCEL LOT?"] = "СКАСУВАТИ ЛОТ?",
  ["CANCELLING…"] = "СКАСУВАННЯ…",
  ["CONFIRM"] = "ПІДТВЕРДИТИ",
  ["COST"] = "ЗАКУП",
  ["COST / UNIT"] = "СОБІВАРТІСТЬ / ШТ",
  ["Can't price this"] = "Ціну не оцінити",
  ["Cancel"] = "Скасувати",
  ["Cancel lot"] = "Скасувати",
  ["Cancel lot?"] = "Скасувати?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Скасувати цей лот і втратити заставу — натисніть ще раз для підтвердження",
  ["Cancel timed out"] = "Час на скасування вичерпано",
  ["Cancelling lot…"] = "Скасовуємо лот…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Скасовує цей активний лот — заново він НЕ виставляється. Застава втрачається, предмети приходять поштою; коли прийдуть, виставте їх заново із цього ж рядка.",
  ["Cannot post this position"] = "Не можна виставити цю позицію",
  ["Cannot remove this entry"] = "Не можна видалити цей запис",
  ["Cannot repost this lot"] = "Не можна перевиставити цей лот",
  ["Cap for %s"] = "Стеля для %s",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Обмежено швидкістю продажу, а не вашим золотом.",
  ["Change the cap…"] = "Змінити стелю…",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Дешевші лоти ще є, але за такої швидкості їх розберуть за години.",
  ["Check"] = "Перевір",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Перевірка перераховує це за живою книгою заявок, перш ніж рушить золото, і може дати менше — або відмовити — якщо ринок змінився після останнього імпорту.",
  ["Checked against the live order book a moment ago."] = "Щойно звірено з живим стаканом заявок.",
  ["Checked: %d of the top %d on screen"] = "Перевірено: %d з %d верхніх на екрані",
  ["Checking prices…"] = "Перевіряємо ціни…",
  ["Checking prices — waiting for the Auction House…"] = "Перевіряємо ціни — чекаємо на аукціон…",
  ["Checking this item's price…"] = "Перевіряємо ціну цього предмета…",
  ["Checking..."] = "Перевіряю...",
  ["Clear to buy"] = "Можна купувати",
  ["Click Confirm to post"] = "Натисніть Confirm, щоб виставити",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Ще один клік скасує активний лот. Заново він не виставляється: застава втрачається, а предмети прийдуть поштою, а не одразу в сумки.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Ще один клік видалить цю введену вручну собівартість назавжди.",
  ["Close"] = "Закрити",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "Companion сам оновлює ціни — /goldcap companion",
  ["Companion sync rejected:"] = "Синхронізацію Companion відхилено:",
  ["Confirm"] = "Підтвердити",
  ["Confirm the cancel"] = "Підтвердити скасування",
  ["Confirm the removal"] = "Підтвердити видалення",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Скопіюйте посилання (Ctrl+C) і відкрийте його в браузері:",
  ["Copy vendor list"] = "Скопіювати список для торговця",
  ["Cost per unit"] = "Собівартість за штуку",
  ["Cost unknown for %d of %d"] = "Собівартість невідома для %d з %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Коштує більше, ніж дозволяє ваш ліміт на одну купівлю.",
  ["Could not read that amount. Type it like 12g 50s."] = "Не вдалося прочитати суму. Введіть так: 12g 50s.",
  ["Don't skip"] = "Не пропускати",
  ["Everything here is bought"] = "Тут усе куплено",
  ["From your scan %s ago. Counts only %s. Change with /gc weights."] =
    "За вашим скануванням %s тому. Враховує лише %s. Змінити: /gc weights.",
  ["Gear upgrades on the auction house"] = "Покращення спорядження на аукціоні",
  ["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."] =
    "GoldCap тепер рахує, що випадає зі здобичі, без імен, для шансів випадіння на goldcap.gg. Companion почне це передавати, коли ця частина вийде. Введіть /gc loot off, щоб вимкнути.",
  ["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."] =
    "Предметів у сумках, що на аукціоні коштують більше, ніж у торговця: %d (на %s більше).",
  ["Items still loading: %d. Open this again in a moment."] =
    "Ще завантажується предметів: %d. Відкрийте це знову за мить.",
  ["Loot counting is off. Type /gc loot clear to remove what was recorded."] =
    "Підрахунок здобичі вимкнено. Введіть /gc loot clear, щоб видалити записане.",
  ["Loot counting is on."] = "Підрахунок здобичі увімкнено.",
  ["Loot record cleared."] = "Запис здобичі видалено.",
  ["Market"] = "Ринок",
  ["Mount cost cleared."] = "Ціну верхової їзди скинуто.",
  ["Mount cost set to %s."] = "Ціна верхової їзди: %s.",
  ["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] =
    "Ще немає сканування зі спорядженням. Відкрийте аукціон, і GoldCap його просканує.",
  ["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] =
    "Для вашого класу ще немає ваг характеристик. Задайте їх так: /gc weights STR 1 STA 0.5",
  ["Nothing on the auction house beats what you wear at your level."] =
    "На аукціоні немає нічого кращого за ваше спорядження для вашого рівня.",
  ["Nothing on this list matches."] = "У цьому списку нічого не підходить.",
  ["Over cap"] = "Вище стелі",
  ["PRICE EACH"] = "ЦІНА ЗА ШТ.",
  ["Play a little longer for an estimate of your pace."] = "Пограйте ще трохи, щоб оцінити ваш темп.",
  ["RAISE CAP TO %s"] = "ПІДНЯТИ ДО %s",
  ["ROAD TO 40"] = "ШЛЯХ ДО 40 РІВНЯ",
  ["Raise cap to %s"] = "Підняти стелю до %s",
  ["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."] =
    "Шлях до 40 рівня з GoldCap: %s з %s на скакуна (%d%%).",
  ["Road to 40: %s of %s (gold %s, bags %s)."] = "Шлях до 40 рівня: %s з %s (золото %s, сумки %s).",
  ["Road to 40: you have %s (gold %s, bags %s)."] = "Шлях до 40 рівня: у вас %s (золото %s, сумки %s).",
  ["Runs"] = "Списки",
  ["Set cap"] = "Задати стелю",
  ["Skip"] = "Пропустити",
  ["Skip for now"] = "Поки пропустити",
  ["Skipped"] = "Пропущено",
  ["Split into reagents (craft %d×)"] = "Розкласти на реагенти (крафт %d×)",
  ["Stat weights: %s"] = "Ваги характеристик: %s",
  ["TO BUY HERE"] = "ДО КУПІВЛІ ТУТ",
  ["The rest is skipped for now"] = "Решту поки пропущено",
  ["This client does not report item stats, so GoldCap cannot compare gear."] =
    "Цей клієнт не повідомляє характеристики предметів, тому GoldCap не може порівняти спорядження.",
  ["This lot holds more units than your Max units per buy."] =
    "У цьому лоті більше штук, ніж ваш «Макс. штук за одну купівлю».",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Не вдалося знайти наступний лот у черзі на скасування — спробуйте ще раз",
  ["DEFAULTS"] = "СТАНДАРТНІ",
  ["DISC"] = "ЗНИЖКА",
  ["DISPLAY"] = "ВІДОБРАЖЕННЯ",
  ["DONE"] = "ГОТОВО",
  ["Default listing length for the Sell tab."] = "Стандартна тривалість виставлення для вкладки Продаж.",
  ["Default: %s"] = "За замовчуванням: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Видаляє лише собівартість, введену вручну у «Вказати ціну», — але не покупку, яку GoldCap упіймав сам чи зіставив із поштою.",
  ["Discount"] = "Знижка",
  ["Discount vs market value from your GoldCap import"] =
    "Знижка від ринкової вартості з вашого імпорту GoldCap",
  ["Dump-trend cap %"] = "Поріг спадного тренду %",
  ["Duration"] = "Тривалість",
  ["Enlarge the window to see details"] = "Збільшіть вікно, щоб побачити деталі",
  ["Enter a whole quantity"] = "Введіть цілу кількість",
  ["Enter an exact positive cost"] = "Введіть точну додатну собівартість",
  ["Entry price (avg fill)"] = "Ціна входу (середнє виконання)",
  ["Entry total"] = "Разом на вході",
  ["Every position in your bags already has a cost on record"] = "У всього, що в сумках, собівартість уже відома",
  ["Everything else checks out. With more gold on this character, this is a buy."] = "Усе інше гаразд. Було б на цьому персонажі більше золота — це була б купівля.",
  ["FIFO allocations"] = "Розподіл FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Отримуємо свіжу ціну для цього предмета — натисніть Post ще раз за мить",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Отримуємо свіжу ціну для цього лота — натисніть Repost ще раз за мить",
  ["Finish the pending post first"] = "Спершу завершіть виставлення, що триває",
  ["Finish the pending post or repost first"] =
    "Спершу завершіть виставлення або перевиставлення, що триває",
  ["Font scale"] = "Масштаб шрифту",
  ["Free, sits in the tray, nothing to set up in game."] =
    "Безкоштовний, живе в треї, у грі нічого налаштовувати не треба.",
  ["Full pass over them: %.1fs"] = "Повний прохід по них: %.1fс",
  ["Full pass over them: measuring..."] = "Повний прохід по них: вимірюємо...",
  ["GOLDCAP"] = "GOLDCAP",
  ["Gold tied up"] = "Заморожено золота",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap не може точно визначити, який це стек у сумці",
  ["GoldCap data age"] = "Вік даних GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap перевіряє верхні %d рядків проти живого аукціону приблизно кожні %dс. Відхилені рядки приховано. Купівля завжди лишається вашим кліком.",
  ["GoldCap value"] = "Оцінка GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Імпорт цін реалму",
  ["GoldCap's"] = "від GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "Що GoldCap радить щодо цього предмета і за якою ціною.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- a deal, but you need %s on this character"] = "GoldCap: перевірено наживо -- вигідно, але на цьому персонажі потрібно %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: перевірено наживо -- безпечно купувати",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: ще не перевірено на живому аукціоні",
  ["Gone"] = "Зник",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Сірий колір означає, що котирування застаріло; Post і Repost оновлять його перед дією.",
  ["HIDDEN 0"] = "ПРИХОВАНО 0",
  ["HOLDING %d"] = "ТРИМАЄМО %d",
  ["Held back from cancelling"] = "Притримано від скасування",
  ["Held back from the queue"] = "Притримано з черги",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Скільки годин звичайних продажів може тримати стіна під вашою ціною виходу, перш ніж угоду буде відхилено.",
  ["IN THE LOT"] = "У ЛОТІ",
  ["ITEM"] = "ПРЕДМЕТ",
  ["If it clears"] = "Якщо продасться",
  ["Import"] = "Імпорт",
  ["Import failed:"] = "Імпорт не вдався:",
  ["Import from goldcap.gg to arm the sniper"] = "Імпортуйте дані з goldcap.gg, щоб увімкнути снайпер",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Встановіть безкоштовний GoldCap Companion, щоб ціни оновлювались самі (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Це те, що треба перебити, аби продати швидко — а не те, скільки предмет вартий. Один продавець поспіхом може опустити ціну значно нижче вартості, і GoldCap не піде за ним униз: дивіться WHAT TO DO, щоб побачити ціну, за якою він справді виставить.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Собівартість не вигадується з ринкової ціни — доки ви її не введете, прибуток лишиться невідомим.",
  ["Item"] = "Предмет",
  ["Item %d"] = "Предмет %d",
  ["Item level %d, below the %d your price is for"] =
    "Рів. предмета %d, нижче за %d, на який розрахована ваша ціна",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."] =
    "Items: спорядження, вихованці та рецепти, оцінені за еталоном регіону з вашого імпорту. Швидкість продажу ніколи не вимірюється, тож вони ніколи не отримують статус БЕЗПЕЧНО -- купувати чи ні, вирішувати вам, а GoldCap перевіряє їх лише поки ця дошка відкрита.",
  ["LISTED"] = "ВИСТАВЛЕНО",
  ["LISTED AS"] = "ВИСТАВЛЕНО",
  ["LOT VALUE"] = "СУМА ЛОТА",
  ["Language"] = "Мова",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Мову змінено. Введіть /reload, щоб застосувати її всюди.",
  ["Last post may still go up -- wait a minute"] = "Ще може виставитися -- зачекайте хвилину",
  ["Level 40 reached: %s to go."] = "Рівень 40 досягнуто: бракує %s.",
  ["Last result: %ds ago"] = "Останній результат: %dс тому",
  ["Last result: none yet this visit"] = "Останній результат: ще не було цього візиту",
  ["Listed"] = "Виставлено",
  ["Listed at %s — far below market. Repost."] =
    "Виставлено за %s — значно нижче ринку. Перевиставте.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Виставлено за ціною, яку ви задали на goldcap.gg, або дешевше. Чи перепродасться — судити вам.",
  ["Listed value"] = "Виставлено на суму",
  ["Listings"] = "Лотів",
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "Виставляє те, що лежить у сумках, за ціною з колонки ЩО РОБИТИ: товар — усім обсягом, звичайний предмет — одним стеком.",
  ["Live ask"] = "Ціна в стакані",
  ["Lot cancelled; wait for it to return to bags"] =
    "Лот скасовано; чекайте, поки він повернеться до сумок",
  ["MARKET"] = "РИНОК",
  ["MARKET / UNIT"] = "РИНОК / ШТ",
  ["MATCH"] = "ЗРІВНЯТИ",
  ["MY LOTS %d"] = "МОЇ ЛОТИ %d",
  ["Market per unit"] = "Ринок за штуку",
  ["Market reference"] = "Ринковий орієнтир",
  ["Max units per buy"] = "Макс. штук за одну купівлю",
  ["Max wallet per buy %"] = "Макс. частка гаманця на купівлю %",
  ["Min profit per buy (gold)"] = "Мінімальний прибуток з купівлі (золото)",
  ["Min profit per buy (copper)"] = "Мінімальний прибуток з купівлі (мідь)",
  ["To buy"] = "До купівлі",
  ["To craft"] = "Крафт",
  ["Unknown stat %s. Use one of: %s"] = "Невідома характеристика %s. Використайте одну з: %s",
  ["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."] =
    "Покращень спорядження на аукціоні: %d. Введіть /gc upgrades, щоб їх побачити.",
  ["Use the default cap"] = "Стеля за замовчуванням",
  ["While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead."] = "Поки це значення лишається стандартними 5%, лот за ціною торговця може використати до половини вашого золота.",
  ["Min return per buy %"] = "Мін. дохідність купівлі %",
  ["Missing cost"] = "Немає собівартості",
  ["NO LIVE PRICE YET"] = "ПОКИ НЕМАЄ ЖИВОЇ ЦІНИ",
  ["YOUR LISTS"] = "ВАШІ СПИСКИ",
  ["NO COST"] = "БЕЗ ЧЕКА",
  ["NOT ON HAND %d"] = "НЕМАЄ НА РУКАХ %d",
  ["NOTHING TO CANCEL"] = "НЕМА ЩО СКАСОВУВАТИ",
  ["Needs a live price check before it can be bought."] =
    "Перед покупкою потрібна жива перевірка ціни.",
  ["Needs gold"] = "Потрібне золото",
  ["Never spend more than this share of your gold on one purchase."] =
    "Ніколи не витрачати на одну покупку більше цієї частки вашого золота.",
  ["No answer yet -- listening for a minute"] = "Аукціон ще не відповів -- чекаємо ще хвилину",
  ["No deals passed the safety checks right now."] =
    "Зараз жодна угода не пройшла перевірок безпеки.",
  ["No deals to show -- and no realm prices yet."] =
    "Немає угод -- і ще немає цін реалму.",
  ["No deals yet."] = "Поки що немає угод.",
  ["No exact auction key"] = "Немає точного ключа аукціону",
  ["No exact bag stack"] = "Немає точного стека в сумці",
  ["No exact bag variant"] = "Немає точного варіанта в сумці",
  ["No live listings came back for this item."] =
    "За цим предметом не прийшло жодного живого лота.",
  ["No live auctions on this character"] = "На цьому персонажі немає активних лотів",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "Для цього предмета ще немає еталонної ціни регіону — імпортуйте знову, коли goldcap.gg її опублікує.",
  ["No safe resale price could be worked out."] = "Безпечну ціну перепродажу обчислити не вдалося.",
  ["No sales data for this item."] = "Немає даних про продажі цього предмета.",
  ["Not enough gold on this character to buy what GoldCap finds"] = "Бракує золота на цьому персонажі, щоб купити знахідки",
  ["Not enough units on the Auction House to fill that quantity."] =
    "На аукціоні не вистачає одиниць, щоб набрати цю кількість.",
  ["Not in your bags or listed — mail or bank?"] =
    "Немає в сумках і не виставлено — пошта чи банк?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Немає під рукою — запас у пошті, банку або на іншому персонажі",
  ["Not worth the deposit on the AH"] = "Не окупає заставу на аукціоні",
  ["Nothing in your bags to list"] = "У сумках немає чого виставити",
  ["Nothing is being held back."] = "Нічого не притримано.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Після цієї покупки не лишиться того, у що продавати, — ціни виходу немає.",
  ["Nothing is priced yet - the Auction House is still answering"] = "Ціни ще не отримані — аукціон досі відповідає",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Жоден лот не дотягує до рівня предмета, на якому виміряно еталонну ціну.",
  ["Nothing listed on the AH right now"] = "Зараз на аукціоні нічого не виставлено",
  ["Nothing on this deck matches that search"] = "На цій вкладці нічого не відповідає пошуку",
  ["Nothing queued to cancel"] = "У черзі на скасування нічого немає",
  ["Nothing queued to post"] = "У черзі на виставлення нічого немає",
  ["Nothing to remove"] = "Нічого видаляти",
  ["ON THE AUCTION HOUSE"] = "НА АУКЦІОНІ",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Одноразове сканування всього аукціону сторінковими запитами. Триває приблизно 15-60 секунд на завантажених реалмах. Без відкату -- скануйте будь-коли.",
  ["Open the Auction House first."] = "Спершу відкрийте аукціон.",
  ["Open the Auction House to begin scanning."] = "Відкрийте аукціон, щоб почати сканування.",
  ["Open the deals board. /gc for commands."] = "Відкрити дошку угод. /gc — команди.",
  ["POSTING"] = "ВИСТАВЛЕННЯ",
  ["POSTING…"] = "ВИСТАВЛЯЄМО…",
  ["PRICE"] = "ЦІНА",
  ["PRICE / UNIT"] = "ЦІНА / ШТ",
  ["PRICE ROSE %.1fx"] = "ЦІНА ЗРОСЛА В %.1fx",
  ["PRICED TOO LOW %d"] = "НАДТО ДЕШЕВО %d",
  ["PRICING %d/%d"] = "ЦІНИ %d/%d",
  ["PRICING…"] = "ЦІНИ…",
  ["PROFIT"] = "ПРИБУТОК",
  ["PROFIT / UNIT"] = "ПРИБУТОК / ШТ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Прив'яжіть або оновіть GoldCap Companion, щоб бачити прибуток з goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Вставте рядок свого реалму з goldcap.gg і натисніть Import.",
  ["Per-unit price of this auction"] = "Ціна за одну штуку в цьому лоті",
  ["Play a sound when a checked deal turns SAFE."] = "Відтворювати звук, коли перевірена угода стає SAFE.",
  ["Position scope changed"] = "Область позиції змінилася",
  ["Post"] = "Виставити",
  ["Post above the cheapest"] = "Виставляти вище найдешевшого",
  ["Post confirmation expired"] = "Підтвердження виставлення протерміновано",
  ["Post the next queued item"] = "Виставити наступний предмет із черги",
  ["Posted"] = "Виставлено",
  ["Posting failed"] = "Виставлення не вдалося",
  ["Posting unavailable"] = "Виставлення недоступне",
  ["Posting…"] = "Ставимо…",
  ["Press Full Scan to find deals."] = "Натисніть Full Scan, щоб знайти угоди.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Натисніть Scan, щоб один раз обійти весь аукціон, або Auto, щоб сканувати постійно.",
  ["Previous removal selection cleared"] = "Попередній вибір для видалення скинуто",
  ["Previous repost selection cleared"] = "Попередній вибір для перевиставлення скинуто",
  ["Price"] = "Ціна",
  ["Priced from bundled sample data, not from your realm."] =
    "Ціна з вкладеного зразка даних, а не з вашого реалму.",
  ["Prices up to date"] = "Ціни актуальні",
  ["Prices up to date · %d did not answer"] = "Ціни актуальні · %d не відповіли",
  ["Pricing %d/%d…"] = "Оцінюємо %d/%d…",
  ["Pricing paused while you use the Auction House"] = "Оцінювання на паузі, поки ви користуєтеся аукціоном",
  ["Pricing…"] = "Оцінюємо…",
  ["Profit"] = "Прибуток",
  ["Profit per unit"] = "Прибуток за штуку",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Облік прибутку — функція goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "У цій збірці покупки вимкнено.",
  ["Press Buy again to buy this quantity"] = "Натисніть Купити ще раз, щоб купити цю кількість",
  ["QTY"] = "К-ТЬ",
  ["Quantity exceeds missing units"] = "Кількість перевищує відсутні одиниці",
  ["Quantity is capped by how fast this item actually sells."] =
    "Кількість обмежена тим, як швидко предмет реально продається.",
  ["READY"] = "ГОТОВЕ",
  ["REFRESH"] = "ОНОВИТИ",
  ["RESET WINDOW"] = "СКИНУТИ ВІКНО",
  ["Reason"] = "Причина",
  ["Refresh"] = "Оновити",
  ["Refresh waiting for prior result"] = "Оновлення чекає на попередній результат",
  ["Refreshing listings…"] = "Оновлюємо лоти…",
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "Відхилити купівлю, якщо ціна впала більше ніж на це за останні 24 години — вона може падати й далі.",
  ["Refused so far: %d"] = "Відхилено наразі: %d",
  ["Removal confirmation expired"] = "Підтвердження видалення протерміновано",
  ["Remove"] = "Видалити",
  ["Remove this cost"] = "Видалити цю собівартість",
  ["Remove?"] = "Видалити?",
  ["Removed"] = "Видалено",
  ["Removed %d entries"] = "Видалено записів: %d",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Видаляє всі введені вручну купівлі в цій групі -- натисніть ще раз для підтвердження",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Видаляє цю введену вручну купівлю -- натисніть ще раз для підтвердження",
  ["Repost confirmation expired"] = "Підтвердження перевиставлення протерміновано",
  ["Right-click to stop watching this item"] =
    "Правий клік, щоб перестати стежити за предметом",
  ["Right-click to watch this item closely"] =
    "Правий клік, щоб пильно стежити за предметом",
  ["SAFE +%s"] = "БЕЗПЕЧНО +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "БЕЗПЕЧНО = жива перевірка схвалила цю купівлю із показаним прибутком",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "ЗБЕРІГАЄТЬСЯ ОДРАЗУ · ESC АБО DONE, ЩОБ ЗАКРИТИ",
  ["SCAN"] = "СКАН",
  ["SCANNING…"] = "СКАНУЄМО…",
  ["SESSION %s%s · %d BUYS"] = "СЕСІЯ %s%s · %d КУПІВЕЛЬ",
  ["Sales are costed from your oldest units first"] =
    "Продажі списуються спершу з найстаріших одиниць",
  ["Search"] = "Пошук",
  ["Sales evidence"] = "Дані продажів",
  ["Sell it on the AH"] = "Продайте на аукціоні",
  ["Sell it on the AH (deposit not counted)"] = "Продайте на аукціоні (застава не врахована)",
  ["Sell it to a vendor"] = "Продайте торговцю",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "Вкладка Продаж виставляє на одну сходинку вище найдешевшої пропозиції, якщо книга ордерів показує таку саму швидкість продажу.",
  ["Sell-through"] = "Викуповуваність",
  ["Sellers"] = "Продавців",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Продається надто рідко — триматимете його довго.",
  ["Set cost"] = "Витрати",
  ["Settings"] = "Налаштування",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Пропустити купівлю, якщо після комісії аукціону вона дає менше цієї суми.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Пропустити купівлю, якщо прибуток менший за цю частку від сплаченого.",
  ["Snapshot value"] = "Значення зі знімка",
  ["Sold per day"] = "Продажів на день",
  ["Sold/day"] = "Продажів на день",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Сортуйте за ним, щоб вирішити, що перевірити першим, а не що купувати.",
  ["Sound on SAFE deal"] = "Звук на угоді SAFE",
  ["Source"] = "Джерело",
  ["Source age"] = "Вік джерела",
  ["Spike-trend threshold %"] = "Поріг стрибка ціни %",
  ["Start scanning as soon as the auction house opens."] =
    "Починати сканування одразу після відкриття аукціонного дому.",
  ["Status"] = "Статус",
  ["Stop and open the buy window on your price"] = "Зупинити й відкрити вікно купівлі за вашою ціною",
  ["Stress exit unit"] = "Ціна стрес-виходу",
  ["Stress profit"] = "Стрес-прибуток",
  ["THE BOOK"] = "СТАКАН ЗАЯВОК",
  ["TO POST %d"] = "ВИСТАВИТИ %d",
  ["TREND"] = "ТРЕНД",
  ["Tell GoldCap what you actually paid for these units."] =
    "Вкажіть, скільки ви насправді заплатили за ці одиниці.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "Аукціон не назвав заставу, тому вартість невідома.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Companion синхронізується, але аддон не зміг прочитати те, що він записав:",
  ["The auction house did not answer -- try again"] = "Аукціон не відповів -- спробуйте ще раз",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "Дошка оцінила лот за імпортованим знімком. Живий стакан цього не підтверджує.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Кнопка стає натискною не одразу, тож випадковий подвійний клік її не спрацює.",
  ["The cancel did not go through — the lot is still listed"] = "Скасування не пройшло — лот досі виставлений",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "Найдешевший лот уже не настільки нижчий за еталонну ціну.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Найдешевша ціна, яку зараз просить ХТОСЬ ІНШИЙ, за живим запитом до аукціону. Ваші власні лоти виключено, тому число ніколи не женеться саме за собою вниз.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Дані щодо цього предмета пошкоджені, і GoldCap відмовляється вгадувати.",
  ["The liquidity data is not reliable enough to act on."] =
    "Дані про ліквідність недостатньо надійні, щоб на них діяти.",
  ["The market value is an estimate, not a measurement."] =
    "Ринкова вартість — це оцінка, а не вимірювання.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "Більше цієї кількості одна купівля не візьме. Швидкість продажу товару може зробити її меншою.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Даним про ціни більше трьох годин. Синхронізуйте Companion і зробіть /reload — аддон читає свої дані лише під час завантаження інтерфейсу.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "Ціну перевірено. Швидкість продажу ніде не вимірюється, тож судити вам.",
  ["The price is falling; buying into it is how you get stuck."] =
    "Ціна падає; заходити в неї — це і є спосіб застрягти.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "Ціна — остання отримана, не старша за 45 секунд. Якщо вона зміниться до підтвердження, виставлення скасовується, а не йде за старою ціною.",
  ["The price moved -- part of this quote may be above your price"] =
    "Ціна зрушила -- частина цього котирування може бути вищою за вашу ціну",
  ["The price moved and the trade is no longer safe."] =
    "Ціна зрушила, і угода більше не безпечна.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "Прибуток не дотягує до вашого мінімуму після 5% комісії та застави.",
  ["What this buy would make is under your minimum profit."] =
    "Прибуток від цієї покупки менший за ваш мінімум.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Скасувати не можна. Перший клік просить другий для підтвердження.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Це предмет реалму, а GoldCap перевіряє лише ціни товарів.",
  ["Too few sellers to read a real price."] = "Замало продавців, щоб прочитати справжню ціну.",
  ["Too little of what is listed actually sells."] =
    "Із виставленого реально продається надто мало.",
  ["Too little price history to trust the value."] = "Замало історії цін, щоб вірити цій вартості.",
  ["Total cost to buy this auction"] = "Повна вартість купівлі цього лота",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Введіть ціну в золоті або очистіть поле, щоб узяти ціну GoldCap",
  ["UNDER YOU"] = "ПІД ТОБОЮ",
  ["UNDERCUT"] = "НИЖЧЕ",
  ["UNDERCUT %d"] = "ПЕРЕБИТІ %d",
  ["UNIT"] = "ЗА ШТ",
  ["Unit price"] = "Ціна за штуку",
  ["Unknown"] = "Невідомо",
  ["Unknown item"] = "Невідомий предмет",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "«Невідомо» означає, що собівартість заповнена не вся — допишіть її через «Вказати ціну».",
  ["VERDICT"] = "ВЕРДИКТ",
  ["Verdict"] = "Вердикт",
  ["WAITING FOR THE AUCTION HOUSE %d"] = "ЧЕКАЄМО НА АУКЦІОН %d",
  ["WATCH"] = "СТЕЖИТИ",
  ["WATCH (computed SAFE)"] = "WATCH (розраховано БЕЗПЕЧНО)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "СТЕЖИТИ = жива перевірка відмовила -- наведіть на рядок, щоб побачити причину",
  ["WHAT COUNTS AS A DEAL"] = "ЩО ВВАЖАЄТЬСЯ УГОДОЮ",
  ["WHAT TO DO"] = "ЩО РОБИТИ",
  ["WHAT YOU PAID"] = "СКІЛЬКИ ВИ ЗАПЛАТИЛИ",
  ["WHEN"] = "КОЛИ",
  ["Waiting for Auction House…"] = "Чекаємо на аукціон…",
  ["Waiting for a live price"] = "Чекаємо на живу ціну",
  ["Waiting for the Auction House…"] = "Чекаємо на аукціон…",
  ["Waiting for the purchase to finish…"] = "Чекаємо завершення купівлі…",
  ["Wall absorb window (hours)"] = "Вікно поглинання стіни (години)",
  ["Watching closely: %d item%s"] = "Пильно стежимо: %d предмет%s",
  ["Watching — pinned, but not a deal right now"] =
    "Стежимо — закріплено, але зараз це не угода",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Скільки насправді коштувала одна штука, у середньому за ще не проданими покупками.",
  ["What to do"] = "Що робити",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "Скільки лишається з однієї штуки при продажу за ринком: ціна продажу мінус 5% комісії аукціону мінус ваша собівартість.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "У скільки складаються ваші активні лоти цього предмета за поточною ціною.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Коли лот досягає ціни, яку ви встановили на сайті, сканування зупиняється і відкривається вікно купівлі.",
  ["Window position & size"] = "Позиція та розмір вікна",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "З ним ціни вашого реалму оновлюються самі, а продажі та прибуток потрапляють на goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "Без нього GoldCap живе на зрізі цін з дати релізу — угоди шукаються за застарілими цінами.",
  ["Won't buy"] = "Не куплю",
  ["Worst case back"] = "Повернеться в найгіршому разі",
  ["YOU GET"] = "ОТРИМАЄШ",
  ["YOUR LOTS"] = "ВАШІ ЛОТИ",
  ["YOUR PRICE"] = "ВАША ЦІНА",
  ["You can pay for it now."] = "Ви вже можете заплатити.",
  ["You paid"] = "Ви заплатили",
  ["You pay"] = "Ви платите",
  ["You would get"] = "Ви отримаєте",
  ["You would pay"] = "Ви заплатите",
  ["Your call"] = "Вирішувати вам",
  ["Your cap"] = "Ваша стеля",
  ["Your gold has not grown lately, so there is no pace to estimate."] =
    "Ваше золото останнім часом не зростає, тож темп оцінити не можна.",
  ["Your minimum"] = "Твій мінімум",
  ["Your price"] = "Ваша ціна",
  ["a purchase landed that GoldCap could not attribute"] = "пройшла купівля, яку GoldCap не зміг віднести до рядка",
  ["a purchase landed that GoldCap could not price"] = "пройшла купівля, ціни якої GoldCap не знає",
  ["a unit, at or under your price of %s"] = "за штуку, за вашою ціною %s або нижче",
  ["a vendor sells it"] = "продає торговець",
  ["a vendor sells it for %s each"] = "торговець продає по %s за шт.",
  ["a vendor sells it for %s each · the auction house asks %s"] = "торговець продає по %s за шт. · на аукціоні %s",
  ["alert group · %d hits"] = "група сповіщень · знахідок: %d",
  ["already in your bags and bank"] = "вже є в сумках і банку",
  ["another purchase is in flight"] = "інша купівля ще не завершилася",
  ["at a vendor"] = "у торговця",
  ["at a vendor · %s each"] = "у торговця · %s за шт.",
  ["at level %d"] = "з %d рівня",
  ["bought"] = "куплено",
  ["buy %d of %d"] = "купити %d з %d",
  ["buy %d of %d, have %d in bags and bank"] = "купити %d з %d, у сумках і банку %d",
  ["cheapest seen %s"] = "найдешевше: %s",
  ["confirming..."] = "підтвердження...",
  ["craft it for %s each"] = "крафт: %s за шт.",
  ["craft it for %s each · %s here"] = "крафт: %s за шт. · тут %s",
  ["craft it yourself"] = "скрафтіть самі",
  ["craft it · %s each"] = "крафт · %s за шт.",
  ["craft it: %s = %s each"] = "крафт: %s = %s за шт.",
  ["includes %d for crafting %s"] = "з них %d на крафт: %s",
  ["no answer — check your mail"] = "немає відповіді — перевірте пошту",
  ["nothing at or under your cap of %s"] = "нічого за вашою стелею %s або дешевше",
  ["nothing on offer"] = "у продажу немає",
  ["over your cap"] = "вище стелі",
  ["over your cap · %s"] = "вище стелі · %s",
  ["purchase failed — try again"] = "купівля не вдалася — спробуйте ще раз",
  ["right-click to skip or change the cap"] = "ПКМ — пропустити або змінити стелю",
  ["seen %s ago"] = "бачили %s тому",
  ["skipped for now"] = "поки пропущено",
  ["skipped for this session, it stays on the list"] = "пропущено до кінця сеансу, у списку лишається",
  ["still on the list: %d at a vendor · %d to craft"] = "ще в списку: у торговця %d · скрафтити %d",
  ["sure profit: a vendor pays %s each"] =
    "гарантований прибуток: торговець платить %s за штуку",
  ["resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown"] =
    "перепродаж за оцінкою сканування, %s/шт., мінус 5%% комісії та застава; швидкість невідома",
  ["Checked against the live auction house a moment ago."] =
    "Щойно звірено з аукціоном у реальному часі.",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "вище найдешевшого, у дешевій чверті · попереду %s шт.",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "вище найдешевшого, у межах денного розмаху · попереду %s шт.",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "проти регіональної ціни цього предмета, за вирахуванням 5% — якщо він продасться",
  ["age %ss"] = "%sс тому",
  ["another purchase took over -- nothing was confirmed"] =
    "інша купівля зайняла її місце -- нічого не підтверджено",
  ["any figure here would be invented out of the very number being refused"] =
    "будь-яка цифра тут була б вигадана з того самого числа, якому не довіряють",
  ["at or under your price -- click Buy to purchase"] =
    "за вашою ціною або дешевше -- натисніть Buy, щоб купити",
  ["auto off"] = "авто вимкнено",
  ["auto-synced %dh ago"] = "автосинхронізація %dг тому",
  ["auto-synced data for %s loaded (%s old)"] =
    "автосинхронізовані дані для %s завантажено (вік %s)",
  ["auto-synced data stale -- /goldcap import"] =
    "автосинхронізовані дані застаріли -- /goldcap import",
  ["auto: paused"] = "авто: пауза",
  ["below the %s you paid"] = "нижче %s, які ви заплатили",
  ["big buy"] = "велика купівля",
  ["bought %d x item %d"] = "куплено %d x предмет %d",
  ["bought %d x item %d after AH close"] = "куплено %d x предмет %d після закриття аукціону",
  ["buying commodity..."] = "купуємо товар...",
  ["cheapest not yours %s"] = "найдешевший не ваш %s",
  ["checking live price..."] = "перевіряємо живу ціну...",
  ["checking live safety..."] = "перевіряємо безпеку наживо...",
  ["clears in ~%dd"] = "розійдеться за ~%d дн.",
  ["clears in ~%dh"] = "розійдеться за ~%d год",
  ["commodity purchase failed"] = "купівля товару не вдалася",
  ["confirmed commodity purchase failed after AH close"] =
    "підтверджена купівля товару не вдалася після закриття аукціону",
  ["confirming purchase..."] = "підтверджуємо купівлю...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "собівартість неповна -- задайте її, щоб отримати пораду з перевиставлення",
  ["crafted %s"] = "скрафчено %s",
  ["due -- will be asked next pass"] = "черга -- запитаємо наступним проходом",
  ["fair"] = "прийнятні",
  ["far below market"] = "значно нижче ринку",
  ["finish the pending buy first"] = "спершу завершіть купівлю, що триває",
  ["first in line"] = "перший у черзі",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "Коштує %s. З вашим лімітом %d%% на одну купівлю на цьому персонажі потрібно %s.",
  ["fresh"] = "свіже",
  ["full scan already in progress"] = "повне сканування вже триває",
  ["full scan interrupted -- confirm your purchase"] =
    "повне сканування перервано -- підтвердіть купівлю",
  ["full scan stalled -- press Full Scan to retry"] =
    "повне сканування зупинилося -- натисніть Full Scan ще раз",
  ["full scan stalled -- retrying shortly"] = "повне сканування зупинилося -- скоро повторимо",
  ["full scan stopped -- press %s to run it again"] =
    "повне сканування зупинено -- натисніть %s, щоб запустити його знову",
  ["gone / price changed"] = "зникло / ціна змінилася",
  ["goldcap.gg prices for WoW: Forever are not out yet."] =
    "Ціни goldcap.gg для WoW: Forever ще не доступні.",
  ["strong"] = "надійні",
  ["hold"] = "тримати",
  ["identity unresolved (variant item -- not priced by design)"] =
    "не вдалося визначити (варіативний предмет -- ціна не рахується навмисно)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "якщо купити всі %d і продати назад за ціною, що стоїть там зараз",
  ["ilvl %d"] = "рів. %d",
  ["import %dh old"] = "імпорту %dг",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "імпорт застарів -- /goldcap import або /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "імпортовано %d предметів для %s (%s) — ціни вже живі.",
  ["in the mail"] = "у пошті",
  ["in the mail, the bank or on another character"] = "у пошті, у банку або на іншому персонажі",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "стільки цей ринок перетравлює — понад те ви купуєте товар, що зависне",
  ["item %d"] = "предмет %d",
  ["item %d: %s"] = "предмет %d: %s",
  ["item level %d+"] = "рів. предмета %d+",
  ["item variant unresolved"] = "варіант предмета не визначено",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "останні 24 год — %d продажів, %s валовий, %s комісія аукціону, %d купівель, %s витрачено",
  ["last live price %s ago"] = "остання жива ціна, %s тому",
  ["leave these alone"] = "ці не чіпати",
  ["level %d"] = "рівень %d",
  ["listing gone -- already bought out or price changed"] =
    "лот зник -- уже викуплений або ціна змінилася",
  ["listing gone -- bought out or repriced"] = "лот зник — викуплений або переставлений за ціною",
  ["live safety confirmed -- click Buy to purchase"] =
    "безпеку підтверджено наживо -- натисніть Buy, щоб купити",
  ["live verification required"] = "потрібна жива перевірка",
  ["the cheapest is %s, your cap is %s"] = "найдешевше — %s, ваша стеля — %s",
  ["the run changed — start again"] = "список змінився — почніть знову",
  ["took too long — try again"] = "надто довго — спробуйте ще раз",
  ["vs %s at the auction house · right-click to split"] = "проти %s на аукціоні · ПКМ — розкласти на реагенти",
  ["weak"] = "слабкі",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "ручний імпорт -- Companion оновлює це сам: /goldcap companion",
  ["market %s"] = "ринок %s",
  ["needs %s"] = "треба %s",
  ["needs a fresh price -- press Refresh"] = "потрібна свіжа ціна -- натисніть Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "сервер не підтвердив -- купівля все одно могла пройти, перевірте пошту. Закриття цього вікна її не скасує.",
  ["no cost"] = "без закупу",
  ["no cost for %d"] = "немає собівартості у %d",
  ["no live price yet"] = "живої ціни ще немає",
  ["no live price"] = "немає живої ціни",
  ["no live quote yet — pricing…"] = "живого котирування ще немає — оцінюємо ціну…",
  ["no market figure for caged pets"] = "немає ринкових даних для вихованців у клітці",
  ["no market figure for this item level"] = "немає ринкових даних для цього рівня предмета",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "цін ще немає -- /goldcap companion або /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "підтвердження купівлі не отримано -- Cancel і спробуйте ще раз",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "продажів ще не записано — відкрийте пошту з увімкненим GoldCap, і їх буде зчитано з рахунків",
  ["no stock in bags or listed -- nothing to price for"] =
    "немає запасу в сумках і на аукціоні -- нема для чого рахувати ціну",
  ["none"] = "немає",
  ["not enough gold -- total %s, you have %s"] = "недостатньо золота -- разом %s, у вас %s",
  ["not enough gold for this quote -- Cancel"] = "недостатньо золота за цією ціною -- Cancel",
  ["not enough gold on this character -- you need %s"] = "недостатньо золота на цьому персонажі -- потрібно %s",
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "для такої кількості одиниць уже не вистачає -- перевіряємо ще раз, що лишилося...",
  ["not priced — nothing on hand to sell"] = "без ціни — продавати нічого",
  ["not ready to cancel"] = "не готово до скасування",
  ["not ready to post"] = "не готово до виставлення",
  ["nothing in your bags to price"] = "у сумках немає чого оцінювати",
  ["nothing listed"] = "нічого не виставлено",
  ["of %d"] = "з %d",
  ["off"] = "вимк",
  ["oldest units sell first"] = "спершу продаються старші",
  ["on"] = "увімк",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "відкрийте аукціон один раз, щоб GoldCap дізнався, як вони продаються",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "або вставте рядок з goldcap.gg через /goldcap import.",
  ["paid %s each"] = "по %s",
  ["paid sale unresolved"] = "оплачений продаж не зіставлено",
  ["placing bid..."] = "робимо ставку...",
  ["previous commodity purchase settled -- %s to re-check the price"] =
    "попередню купівлю товару завершено -- %s, щоб перевірити ціну ще раз",
  ["price changed after you closed the buy window -- nothing was bought"] =
    "ціна змінилася після закриття вікна купівлі -- нічого не куплено",
  ["price checked, sale speed unknown -- this one is your call"] =
    "ціну перевірено, швидкість продажу невідома -- вирішувати вам",
  ["price confirmed -- click Buy to purchase"] =
    "ціну підтверджено -- натисніть Buy, щоб купити",
  ["price rose %.1fx — still safe, confirm"] = "ціна зросла в %.1fx — усе ще безпечно, підтвердіть",
  ["price stands %d of %d"] = "ваша ціна: %d з %d",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "завантажено ціни %s (%s), а граєте ви в %s — усі знижки й прибуток рахуються за чужим ринком",
  ["purchase canceled"] = "купівлю скасовано",
  ["purchase complete"] = "покупку здійснено",
  ["purchase identity unresolved"] = "покупку не впізнано",
  ["purchase pending exact cost"] = "купівля очікує точної собівартості",
  ["purchase total unavailable — inspect mailbox"] =
    "загальна сума купівлі недоступна — перевірте пошту",
  ["quote %s -- click Confirm to buy"] = "котирування %s -- натисніть Confirm, щоб купити",
  ["quote %ss ago"] = "котирування %sс тому",
  ["quote expired -- Refresh to re-check the price"] =
    "котирування протерміновано -- Refresh, щоб перевірити ціну ще раз",
  ["quote expires in %d s -- click Confirm to buy"] =
    "котирування спливає за %d с -- натисніть Confirm, щоб купити",
  ["re-checking what remains at a safe price..."] =
    "перевіряємо ще раз, що лишилося за безпечною ціною...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "предмет реалму — швидкість продажу не перевірено · еталон регіону %s (рів. предмета %d)",
  ["recent sales (newest first):"] = "останні продажі (найновіші зверху):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "регіон %s — вбудовано: %d предметів (%s), імпортовано: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "регіон виправлено в %d записах; %d продажів зіставлено зі своїм запасом",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "перевиставлення зараз зафіксує збиток або застій -- притримайте",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "видалено %d дубльованих записів купівлі, залишених помилкою сканування пошти",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "видалено %d дубльованих записів продажу, залишених помилкою сканування пошти",
  ["sale name ambiguous"] = "назва в продажу неоднозначна",
  ["sale proceeds pending"] = "виторг очікується",
  ["scanned %d listings over %d passes"] = "проскановано %d лотів за %d проходів",
  ["scanning auction house..."] = "скануємо аукціон...",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "продається %s/день",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "сесія: %d перехоплень, витрачено %s, ~%s орієнт. прибутку",
  ["sniped (listing changed on rescan)"] = "перехоплено (лот змінився при перескануванні)",
  ["sniped for "] = "снайпнуто за ",
  ["stack not identified"] = "стак не розпізнано",
  ["starting full scan..."] = "починаємо повне сканування...",
  ["stopped watching %s"] = "перестали стежити за %s",
  ["the Companion wrote prices this addon could not read --"] =
    "Companion записав ціни, які аддон не зміг прочитати --",
  ["the Auction House has not answered for this item yet"] = "аукціон ще не відповів по цьому предмету",
  ["the auction house has not sent details for these yet"] =
    "аукціон ще не надіслав відомостей про ці предмети",
  ["the import failed (%s)"] = "імпорт не вдався (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "щоб розпродати %d шт. за %s продажів на день, і весь цей час %s заморожено",
  ["unavailable"] = "недоступне",
  ["under GoldCap's own floor of %s"] = "нижче власного порога GoldCap — %s",
  ["unknown evidence"] = "невідоме підтвердження",
  ["waiting for previous commodity purchase to settle"] =
    "чекаємо, поки завершиться попередня купівля товару",
  ["waiting for previous search result to settle"] =
    "чекаємо, поки завершиться попередній пошук",
  ["waiting..."] = "очікування…",
  ["wall"] = "стіна",
  ["wall %s at %s -- price under it to sell first"] =
    "стіна %s шт. по %s -- ставте нижче, щоб продати раніше",
  ["wall %s at %s above you"] = "стіна %s шт. по %s вище за вас",
  ["watching %s closely -- re-checked every few seconds"] =
    "пильно стежимо за %s -- перевірка кожні кілька секунд",
  ["worst case, selling all %d back into the price standing there now"] =
    "у найгіршому разі, якщо продати всі %d за ціною, що стоїть там зараз",
  ["worth cancelling"] = "варто скасувати",
  ["would sell at a loss"] = "продалося б у збиток",
  ["you have enough gold for this now -- Check again"] = "тепер золота вистачає -- натисніть Check, щоб перевірити знову",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "ви ще не імпортували ціни реалму -- встановіть GoldCap Companion (/goldcap companion) або вставте рядок з goldcap.gg (/goldcap import).",
  ["you take %d"] = "берете %d",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "у вашому клієнті гри немає шрифту для цієї мови — текст відображатиметься порожніми квадратами",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "вашому імпорту %d годин -- ціни можуть бути хибними. Вставте свіжий рядок з goldcap.gg (/goldcap import).",
  ["your price is above every level shown"] = "твоя ціна вища за всі показані рівні",
  ["your scan, %s ago"] = "твоє сканування, %s тому",
  ["yours"] = "ваша",
  ["yours ×%s"] = "ваші ×%s",
  ["~%dd to reach you"] = "~%d дн. до вас",
  ["~%dh to reach you"] = "~%d год до вас",
  ["×%d in bags"] = "×%d у сумках",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d у ваших сумках · Post виставить %d із них, найбільший стек",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d у ваших сумках · немає стека, який GoldCap може точно визначити",
  ["×%d in your bags, ready to list"] = "×%d у ваших сумках, готові до виставлення",
  ["×%d listed"] = "×%d виставлено",
  ["×%d listed at %s each"] = "×%d виставлено по %s за штуку",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · куплено %s · %s · %s",
  ["×%d%s · made %s · %s"] = "×%d%s · виготовлено %s · %s",
  ["— = nothing is checking this row right now"] = "— = зараз цей рядок ніхто не перевіряє",
  ["… = a live check is queued for this row"] =
    "… = для цього рядка жива перевірка вже в черзі",
  ["no answer %ds ago -- resting"] = "немає відповіді %dс тому -- пауза",
  ["the last attempt is still settling -- checking the price again..."] =
    "попередня спроба ще не завершилася -- перевіряємо ціну знову...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "Виставлено за ціною, яку ви задали на goldcap.gg, або дешевше (група: %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "АВТО · ПАУЗА: ВІКНО КУПІВЛІ",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "Пауза, поки відкрите вікно купівлі. Купіть або закрийте його — і Авто продовжить.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "АВТО · ПАУЗА: ВАШ ПОШУК",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "Пауза, поки ви друкуєте в пошуку аукціону. Продовжить за кілька секунд після того, як ви з нього вийдете.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "АВТО · ПАУЗА: ВІДКРИТА ПОШТА",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "Пауза, поки відкрита поштова скринька. Закрийте її — і Авто продовжить.",
  ["AUTO · PAUSED: SELL TAB"] = "АВТО · ПАУЗА: ВКЛАДКА ПРОДАЖ",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "Пауза, поки відкрита вкладка Продаж: вона оцінює ваші сумки через той самий пошук. Поверніться до угод — і Авто продовжить.",
  ["AUTO · PAUSED: ITEMS BOARD"] = "АВТО · ПАУЗА: ДОШКА ПРЕДМЕТІВ",
  ["Paused while the Items board is shown: it asks the auction house through the same search. Switch to Commodities and Auto carries on."] =
    "Пауза, поки показана дошка предметів: вона запитує аукціон через той самий пошук. Перемкніться на товари — і Авто продовжить.",
  ["AUTO · PAUSED: BUY TAB"] = "АВТО · ПАУЗА: ВКЛАДКА BUY",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "Пауза, поки відкрита вкладка BUY: вона дізнається ціни через той самий пошук. Поверніться до угод — і Авто продовжить.",
  ["AUTO · WAITING FOR YOU"] = "АВТО · ЧЕКАЄ НА ВАС",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "Чекає, поки ви виставляєте, купуєте чи переглядаєте у вікнах самого аукціону. Почне, щойно ви закінчите.",
  ["AUTO · WAITING: YOUR LIST"] = "АВТО · ЧЕКАЄ: ВАШ СПИСОК",
  ["Waiting: your own search is on the auction house's Buy list, and a scan would replace it. Open GoldCap's auction house tab, or close the auction house, and Auto starts."] =
    "Чекає: у списку купівлі аукціону ваш власний пошук, і скан замінив би його. Відкрийте вкладку GoldCap на аукціоні або закрийте аукціон — і Авто почне.",
  ["Market %s · unverified until a live Check"] = "Ринок %s · не перевірено до живої перевірки",
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "дані всього ринку: товарів %d, з даними про продажі %d, предметів світу %d (вік %s, %d КБ)",
  ["whole-market data not in use: %s"] = "дані всього ринку не використовуються: %s",
  ["it is %s old, and the prices you imported are newer"] = "їхній вік %s, а імпортовані вами ціни новіші",
  ["it is for another region than the prices loaded"] = "вони для іншого регіону, ніж завантажені ціни",
  ["its date cannot be right -- check this computer's clock"] =
    "їхня дата не може бути правильною -- перевірте годинник цього комп'ютера",
  ["it was set aside when other prices were loaded this session -- /reload to use it again"] =
    "їх відклали, коли в цій сесії завантажили інші ціни -- /reload, щоб знову їх використати",
  ["On the AH now"] = "На аукціоні зараз",
  ["%s listed · %d min ago"] = "виставлено %s · %d хв тому",
  ["%s listed · just now"] = "виставлено %s · щойно",
  ["it could not be read (%s)"] = "їх не вдалося прочитати (%s)",
  ["it is for a region this build of GoldCap does not know -- update the addon"] =
    "вони для регіону, якого ця версія GoldCap не знає -- оновіть аддон",
  ["it is in a format this build of GoldCap cannot read -- update the addon"] =
    "вони у форматі, який ця версія GoldCap не вміє читати -- оновіть аддон",
  ["it is larger than this build of GoldCap can read -- update the addon"] =
    "вони більші, ніж може прочитати ця версія GoldCap -- оновіть аддон",
  ["the Companion wrote an empty copy -- let it sync, then /reload"] =
    "Companion записав їх порожніми -- дайте йому синхронізуватися і зробіть /reload",
  ["the Companion wrote it with no prices -- let it sync, then /reload"] =
    "Companion записав їх без цін -- дайте йому синхронізуватися і зробіть /reload",
  ["Scanning the auction house…"] = "Скануємо аукціон…",
  ["%s lots scanned -- shared on your next /reload"] =
    "%s лотів відскановано -- буде передано під час наступного /reload",
  ["%s lots scanned and saved"] = "%s лотів відскановано і збережено",
  ["%s items scanned -- shared on your next /reload"] =
    "%s предметів відскановано -- буде передано під час наступного /reload",
  ["%s items scanned and saved"] = "%s предметів відскановано і збережено",
  ["The full scan is cooling down (%d min left) -- scanning by browsing instead"] =
    "Повне сканування ще відновлюється (лишилось %d хв) -- поки що скануємо через огляд",
  ["The auction house did not answer the full scan -- scanning by browsing instead"] =
    "Аукціон не відповів на повне сканування -- скануємо через огляд натомість",
  ["reading the auction house: %s of %s lots"] = "читаємо аукціон: %s з %s лотів",
  ["The scan found nothing to save"] = "Сканування не знайшло, що зберегти",
  ["Scans the whole auction house for prices: a full list at most once every 15 minutes, browsing in between. GoldCap also scans when you open the auction house."] =
    "Сканує весь аукціон у пошуках цін: повний список не частіше разу на 15 хвилин, а між ними -- через огляд. GoldCap також сканує, коли ви відкриваєте аукціон.",
  -- Core/ForeverValue.lua's PrintBags/BagTotals and Core/PostQueue.lua's below_vendor: the
  -- POST queue holding back what a vendor pays at least as much for.
  ["Your bags: %s at a vendor, %s on the AH after its cut"] =
    "Ваші сумки: %s у торговця, %s на аукціоні після комісії",
  ["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."] =
    "Кнопка ВИСТАВИТИ на вкладці Продаж перелічує все, що коштує дорожче, ніж платить торговець, по одному кліку за раз.",
  ["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."] =
    "Ваші сумки: %s у торговця. Відскануйте аукціон, щоб дізнатися, скільки б за них дали там.",
  ["a vendor pays more -- sell it there"] =
    "торговець платить більше -- продайте йому",
  ["vendor pays more"] =
    "торговець платить більше",
  ["Below vendor"] =
    "Нижче НПС",
  ["Under market"] =
    "Під ринком",
  [" · buy at %s or less, vendor pays %s"] =
    " · купити за %s або менше, торговець платить %s",
  [" · buy at %s or less, AH value %s"] =
    " · купити за %s або менше, оцінка на аукціоні %s",
  ["Buy at or under %s: a vendor pays %s each. This buy makes %s."] =
    "Купити за %s або менше: торговець платить %s за штуку. Ця покупка приносить %s.",
  ["Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit."] =
    "Купити за %s або менше: оцінка на аукціоні — ціна, яку просить найдешевша десята частина виставлених одиниць, — %s. Швидкість перепродажу невідома, тож це ризикованіше за угоду з торговцем. Ця покупка приносить приблизно %s після комісії 5%% і застави.",
  ["under the vendor price -- click Buy to purchase"] =
    "нижче за ціну торговця -- натисніть Buy, щоб купити",
  ["far under the market, resale speed unknown -- click Buy to purchase"] =
    "набагато нижче за ринок, швидкість перепродажу невідома -- натисніть Buy, щоб купити",
  ["No deals in your last scan."] =
    "Немає угод в останньому скані.",
  ["Deals appear as soon as the scan finds them."] =
    "Угоди з’являться, щойно скан їх знайде.",
  ["GoldCap looks for items listed cheaper than they are worth. SCAN looks again."] =
    "GoldCap шукає предмети, виставлені дешевше, ніж вони коштують. СКАН сканує знову.",
  ["No scan of this auction house yet."] =
    "Цей аукціон ще не сканувався.",
  ["GoldCap scans when you open the auction house; SCAN on this board scans again."] =
    "GoldCap сканує, коли ви відкриваєте аукціон; СКАН на цій дошці сканує знову.",
  ["In WoW: Forever, GoldCap's prices come from your own auction house scans."] =
    "У WoW: Forever ціни GoldCap беруться з твоїх власних сканувань аукціону.",
  ["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."] =
    "Відкрийте аукціон, і GoldCap відсканує його за вас; СКАН на вкладці Угоди сканує знову.",
  ["%ds"] = "%d с",
  ["%dm"] = "%d хв",
  ["%dh"] = "%d год",
  ["%dd"] = "%d дн.",
  -- WoW: Forever crowd prices (UI/Tooltip.lua, plan 3d).
  ["1 scanner, %s ago"] = "1 сканер, %s тому",
  ["%d scanners, %s ago"] = "сканерів: %d, %s тому",
  ["resale at the AH value of players' scans, %s each, after the 5%% cut and deposit; speed unknown"] = "перепродаж за оцінкою на аукціоні зі сканувань гравців, %s/шт., мінус 5%% комісії та застава; швидкість невідома",
  ["Shared with goldcap.gg on your next /reload"] = "Буде передано на goldcap.gg під час наступного /reload",
  ["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."] = "Ваші скани залишаються на цьому комп'ютері. GoldCap Companion передає їх на goldcap.gg і повертає ціни всіх гравців.",
  ["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."] = "GoldCap Companion передає ваші скани на goldcap.gg після кожного /reload і повертає ціни всіх гравців.",
  ["You opened %s -- its first %s prices are yours."] =
    "Ви відкрили %s -- перші ціни тут ваші: %s.",
  ["Your scan updated %s prices on %s -- %s of them nobody else had in the last 24 hours."] =
    "Ваш скан оновив цін: %s на %s -- з них ні в кого більше не було за останні 24 години: %s.",
  ["Your scan updated %s prices on %s."] =
    "Ваш скан оновив цін: %s на %s.",
  -- Sold tab: tiles, period chips, search, day groups and the sale tooltip.
  ["%d DAYS"] = "%d ДНІВ",
  ["TODAY"] = "СЬОГОДНІ",
  ["YESTERDAY"] = "УЧОРА",
  ["SUN"] = "НД",
  ["MON"] = "ПН",
  ["TUE"] = "ВТ",
  ["WED"] = "СР",
  ["THU"] = "ЧТ",
  ["FRI"] = "ПТ",
  ["SAT"] = "СБ",
  ["YOU GOT"] = "ОТРИМАНО",
  ["YOU GOT · %s"] = "ОТРИМАНО · %s",
  ["EACH"] = "ЗА ШТ",
  ["%d sales · after the AH cut"] = "продажів: %d · після комісії",
  ["1 sale · after the AH cut"] = "1 продаж · після комісії",
  ["%d here · all on goldcap.gg"] = "тут %d · усі на goldcap.gg",
  ["cost known for %d of %d"] = "закупівля відома: %d з %d",
  ["%s of %s"] = "%s з %s",
  ["%s · gold %s, bags %s"] = "%s · золото %s, сумки %s",
  ["set the riding cost: %s"] = "вкажіть ціну верхової їзди: %s",
  ["GOLDCAP.GG · %d DAYS"] = "GOLDCAP.GG · %d ДН.",
  ["profit · synced %s ago"] = "прибуток · синхр. %s тому",
  ["after the AH cut · synced %s ago"] = "чистими · синхр. %s тому",
  ["BEST SALE"] = "НАЙКРАЩИЙ ПРОДАЖ",
  ["%s profit"] = "%s прибутку",
  ["no sale with a known profit yet"] = "поки немає продажів із відомим прибутком",
  ["OPEN SELL"] = "ВІДКРИТИ SELL",
  ["Find an item"] = "Знайти предмет",
  ["JUST SOLD"] = "ЩОЙНО ПРОДАНО",
  ["reaches goldcap.gg on /reload or logout"] = "потрапить на goldcap.gg після /reload або виходу",
  ["ON GOLDCAP.GG"] = "НА GOLDCAP.GG",
  ["latest %d of %d · the rest on goldcap.gg"] = "останні %d з %d · решта на goldcap.gg",
  ["last %d days"] = "за %d дн.",
  ["%d sales · %s"] = "продажів: %d · %s",
  ["1 sale · %s"] = "1 продаж · %s",
  ["sold today at %s · %d × %s"] = "продано сьогодні о %s · %d × %s",
  ["sold %s at %s · %d × %s"] = "продано %s о %s · %d × %s",
  ["sold, the money is in your mail · %d × %s"] = "продано, гроші чекають у пошті · %d × %s",
  ["Sale price"] = "Ціна продажу",
  ["Auction house cut"] = "Комісія аукціону",
  ["Auction house cut, 5%"] = "Комісія аукціону, 5%",
  ["You got"] = "Ви отримали",
  ["You paid (%s)"] = "Ви заплатили (%s)",
  ["%s each"] = "%s за шт.",
  ["Sniper"] = "снайпер",
  ["BUY list"] = "список BUY",
  ["set by you"] = "вказано вами",
  ["the auction house"] = "аукціон",
  ["crafted"] = "крафт",
  ["The profit is worked out once the money arrives."] = "Прибуток порахується, коли надійдуть гроші.",
  ["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."] =
    "GoldCap не бачив цієї покупки, тому прибуток показати не можна. Вкажіть, скільки вона вам коштувала, у вкладці SELL.",
  ["Market now %s · you sold %d%% above it"] = "Ринок зараз %s · ви продали на %d%% дорожче",
  ["Market now %s · you sold %d%% under it"] = "Ринок зараз %s · ви продали на %d%% дешевше",
  ["Market now %s · you sold at it"] = "Ринок зараз %s · ви продали за ринковою ціною",
  ["Your sales show up here once you open a mailbox with GoldCap loaded."] =
    "Ваші продажі з'являться тут, коли ви відкриєте поштову скриньку з увімкненим GoldCap.",
  ["List something in SELL first."] = "Спершу виставте щось у вкладці SELL.",
  ["No sales match “%s” today."] = "Сьогодні немає продажів за запитом «%s».",
  ["No sales match “%s” in these %d days."] = "Немає продажів за запитом «%s» за ці %d днів.",
  ["No sales today."] = "Сьогодні продажів немає.",
  ["No sales in these %d days."] = "За ці %d днів продажів немає.",
  ["SEARCH 30 DAYS"] = "ШУКАТИ ЗА 30 ДНІВ",
  ["SHOW 30 DAYS"] = "ПОКАЗАТИ 30 ДНІВ",
  -- Strings that had stayed English here: the BUY tab, the Sell decks and chips, the Deals boards, imports and chat lines.
  ["  %s · need %d · have %d · buy %d · %s"] = "  %s · треба %d · є %d · купити %d · %s",
  [" · watching"] = " · відстежується",
  ["%d items for %s (%s, %s)"] = "предметів: %d для %s (%s, %s)",
  ["%d lines"] = "рядків: %d",
  ["%d lines · %d to buy · %d at the vendor"] = "рядків: %d · купити: %d · у торговця: %d",
  ["%d lines · %d to buy · %d to craft · %d at the vendor"] =
    "рядків: %d · купити: %d · скрафтити: %d · у торговця: %d",
  ["%d× %s"] = "%d× %s",
  ["%d× %s · %s each · %s"] = "%d× %s · %s за шт. · %s",
  ["..."] = "...",
  ["ACTION"] = "ДІЯ",
  ["Above this 24-hour rise the resale exit price is treated as spike-inflated and priced down."] =
    "Якщо ціна за 24 години зросла сильніше за це, ціна перепродажу вважається роздутою стрибком і занижується.",
  ["Alerts"] = "Сповіщення",
  ["BUY"] = "ВЗЯТИ",
  ["BUY %d"] = "КУПИТИ %d",
  ["Buy cap (% of usual price)"] = "Стеля покупки (% від звичайної ціни)",
  ["Buy run"] = "закупівля BUY",
  ["COMMODITIES"] = "ТОВАРИ",
  ["Cap: %d%%"] = "Стеля: %d%%",
  ["Commodities: reagents, consumables, gems and enchants the scan found under their region price. These are the rows a live check can approve for buying."] =
    "Товари: реагенти, витратні матеріали, самоцвіти й чари, які скан знайшов дешевшими за ціну по регіону. Лише такі рядки жива перевірка може схвалити до купівлі.",
  ["From goldcap.gg — manage it there"] = "З goldcap.gg — керуйте там",
  ["From goldcap.gg — remove it there"] = "З goldcap.gg — видаляйте там",
  ["Gear, pets and recipes need an import that carries the region's prices for them -- paste a fresh string from goldcap.gg."] =
    "Для спорядження, вихованців і рецептів потрібен імпорт із цінами регіону -- вставте свіжий рядок із goldcap.gg.",
  ["GoldCap could not tell which region you are playing in, so it is showing bundled US prices -- /goldcap import or /goldcap companion loads your own realm's"] =
    "GoldCap не зміг визначити ваш регіон і показує вбудовані ціни US -- /goldcap import або /goldcap companion завантажать ціни вашого реалму",
  ["GoldCap keeps checking them while this board is open."] = "GoldCap і далі їх перевіряє, поки відкрита ця дошка.",
  ["GoldCap realm median (unverified)"] = "Медіана реалму GoldCap (не перевірена)",
  ["GoldCap region price"] = "Ціна GoldCap по регіону",
  ["GoldCap region price (ilvl %d)"] = "Ціна GoldCap по регіону (рів. %d)",
  ["HAVE"] = "Є",
  ["HIDDEN %d"] = "СХОВАНО %d",
  ["ITEMS"] = "ПРЕДМЕТИ",
  ["ITEMS %d"] = "ПРЕДМЕТИ %d",
  ["NEED"] = "ТРЕБА",
  ["NOW"] = "ЗАРАЗ",
  ["No gear, pets or recipes under their region price right now."] =
    "Зараз немає спорядження, вихованців чи рецептів, дешевших за ціну по регіону.",
  ["Nothing to watch on this board yet."] = "На цій дошці поки нічого відстежувати.",
  ["REAGENT"] = "РЕАГЕНТ",
  ["REFUSED %d"] = "ВІДМОВИ %d",
  ["Restore %s"] = "Повернути %s",
  ["The BUY tab never pays more than this share of the usual price for a line; it buys what fits and leaves the rest."] =
    "Вкладка BUY ніколи не платить за рядок більше цієї частки звичайної ціни: купує те, що вкладається, а решту залишає.",
  ["Total: %s"] = "Разом: %s",
  ["USUAL"] = "ЗАЗВИЧАЙ",
  ["auction house error"] = "помилка аукціону",
  ["auto-synced"] = "синхронізовано автоматично",
  ["bought %d for %s"] = "куплено %d за %s",
  ["buying..."] = "купівля...",
  ["cap: alert target"] = "стеля: ціль сповіщення",
  ["craft"] = "крафт",
  ["deals %s · items %s · filtered %s"] = "угоди %s · предмети %s · відсіяно %s",
  ["done"] = "готово",
  ["everything bought"] = "усе куплено",
  ["from %s"] = "від %s",
  ["in bags %d · in bank %d"] = "у сумках %d · у банку %d",
  ["in bags and bank · purchases arrive by mail"] = "у сумках і банку · покупки надходять поштою",
  ["manual import"] = "ручний імпорт",
  ["no answer from the auction house"] = "аукціон не відповів",
  ["on %s"] = "на %s",
  ["pasted"] = "вставлено",
  ["plan updated on goldcap.gg"] = "план оновлено на goldcap.gg",
  ["price moved to %s"] = "ціна стала %s",
  ["removed %d duplicate purchase record left by a mail-scan bug"] =
    "видалено %d дубльований запис купівлі, залишений помилкою сканування пошти",
  ["removed %d duplicate sale record left by a mail-scan bug"] =
    "видалено %d дубльований запис продажу, залишений помилкою сканування пошти",
  ["spent %s · left ~%s"] = "витрачено %s · лишилося ~%s",
  ["that does not look like a GoldCap import string"] = "це не схоже на рядок імпорту GoldCap",
  ["that looks like two import strings pasted together -- paste just one"] =
    "схоже, вставлено два рядки імпорту поспіль -- вставте один",
  ["that string carried no prices"] = "у цьому рядку немає цін",
  ["that string does not name a realm"] = "у цьому рядку не вказано реалм",
  ["that string is too long to import"] = "цей рядок задовгий для імпорту",
  ["the auction house reported an error"] = "аукціон повідомив про помилку",
  ["there was nothing to import"] = "імпортувати нічого",
  ["this build of GoldCap does not know that region -- update the addon"] =
    "ця версія GoldCap не знає такого регіону -- оновіть аддон",
  ["usually cheapest around %s · %d%%"] = "зазвичай найдешевше близько %s · %d%%",
  ["vendor"] = "торговець",
  ["vs %s at the auction house · right-click to buy it whole"] = "проти %s на аукціоні · ПКМ — купити цілим",
  ["window moved back to the middle of the screen at its default size"] =
    "вікно повернуто в центр екрана зі стандартним розміром",
  ["your saved purchase records are damaged -- cost tracking is off, the rest of GoldCap is running"] =
    "збережені записи про покупки пошкоджено -- облік собівартості вимкнено, решта GoldCap працює",
  ["▲%d%% over the alert target"] = "▲на %d%% вище цілі сповіщення",
  ["▲%d%% over usual"] = "▲на %d%% вище звичайного",
  ["▲%d%% over your cap"] = "▲на %d%% вище вашої стелі",
  -- The quest reward mark (UI/QuestRewardMark.lua).
  ["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."] =
    "GoldCap: нагорода в золотій рамці найдорожча на аукціоні (%s).",
  -- The vendor note (UI/MerchantNote.lua).
  ["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."] =
    "1 предмет у ваших сумках на аукціоні коштує більше (+%s). Залиште його для аукціону.",
  ["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."] =
    "Предметів у ваших сумках, що на аукціоні коштують більше: %d (+%s). Залиште їх для аукціону.",
  -- BUY 2.0 week 2: a gear line is bought one lot per press (UI/BuyFrame.lua).
  ["BUY ONE · %s"] = "КУПИТИ ОДИН · %s",
  ["not enough gold"] = "недостатньо золота",
  ["set a cap first"] = "спершу задайте стелю",
  -- BUY 2.0 week 2: a gear line's lots on the dock (UI/BuyFrame.lua).
  ["%s · %d lots"] = "%s · лотів: %d",
  ["%s · 1 lot"] = "%s · 1 лот",
  ["%s · over your cap"] = "%s · вище стелі",
  ["no cap for this item — right-click the line to set one"] =
    "у цього предмета немає стелі — задайте її правим кліком по рядку",
  -- BUY 2.0 week 2: the vendor panel beside the merchant (UI/BuyVendorPanel.lua).
  ["BUY %d · %s"] = "КУПИТИ %d · %s",
  ["BUY · %s"] = "КУПИТИ · %s",
  -- BUY 2.0: the item box and the quick list (UI/BuyFrame.lua).
  ["Could not find that item. Shift-click it, or type its item id."] =
    "Предмет не знайдено. Зробіть Shift+клік по ньому або введіть його ID.",
  ["Item to add"] = "Додати предмет",
  ["Make a list once, buy it here at or under your price."] =
    "Складіть список один раз і купуйте тут за своєю ціною або дешевше.",
  ["Remove from the list"] = "Прибрати зі списку",
  ["or plan a whole profession on goldcap.gg"] = "або сплануйте всю професію на goldcap.gg",
  -- BUY 2.0: the item box's hint, with the x count (UI/BuyFrame.lua).
  -- Glyphs every face that draws them has (spec/client_text_spec.lua's glyph inventory).
  ["HIDE DETAILS ▲"] = "СХОВАТИ ДЕТАЛІ ▲",
  ["SHOW DETAILS ▼"] = "ПОКАЗАТИ ДЕТАЛІ ▼",
  ["plan updated on goldcap.gg · +%d -%d lines"] = "план оновлено на goldcap.gg · рядків +%d -%d",
  ["~ goldcap.gg market value — no live quote yet"] =
    "~ ринкова вартість goldcap.gg — живого котирування ще немає",
  ["• %s"] = "• %s",
  ["→ needs price"] = "→ потрібна ціна",
  -- BUY 2.0: lists made in the game -- New, Import, Export, Rename, favourites, order, Delete
  ["Items the game has not loaded yet are left out: %d. Export again in a moment."] =
    "Гра ще не завантажила предметів: %d — їх не додано. Експортуйте знову трохи згодом.",
  ["%s and %d more"] = "%s і ще %d",
  ["+ New"] = "+ Новий",
  ["Add to favourites"] = "Додати до обраного",
  ["Added %d items to %s."] = "Додано предметів: %d — до списку «%s».",
  ["Added %d× %s to %s."] = "Додано: %d× %s — до списку «%s».",
  ["Added %d× %s to a new list, %s."] = "Додано: %d× %s — до нового списку «%s».",
  ["Copy as a TSM item list"] = "Скопіювати як список предметів TSM",
  ["Copy for Auctionator"] = "Скопіювати для Auctionator",
  ["Delete"] = "Видалити",
  ["Delete %s? This cannot be undone."] = "Видалити «%s»? Це не можна скасувати.",
  ["Delete this list…"] = "Видалити список…",
  ["Export"] = "Експорт",
  ["From goldcap.gg — rename or remove it there"] = "З goldcap.gg — перейменовуйте й видаляйте там",
  ["GoldCap — Import a list"] = "GoldCap — Імпорт списку",
  ["Import a list…"] = "Імпортувати список…",
  ["Import into this list…"] = "Імпортувати в цей список…",
  ["Imported %s with %d items."] = "Список «%s» імпортовано, предметів: %d.",
  ["List %d"] = "Список %d",
  ["Lists come from goldcap.gg through the companion, or make one here with + New."] =
    "Списки надходять із goldcap.gg через Companion — або створіть свій тут кнопкою «+ Новий».",
  ["Lists: click to switch, make, import or export one"] =
    "Списки: натисніть, щоб змінити, створити, імпортувати або експортувати список",
  ["Move down"] = "Перемістити нижче",
  ["Move up"] = "Перемістити вище",
  ["Name this list"] = "Назва списку",
  ["New list"] = "Новий список",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import."] =
    "Вставте список із goldcap.gg, TSM або Auctionator і натисніть «Імпорт».",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."] =
    "Вставте список із goldcap.gg, TSM або Auctionator і натисніть «Імпорт». Предмети додадуться до «%s».",
  ["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."] =
    "Натисніть Ctrl+C, щоб скопіювати, потім імпортуйте на вкладці покупок в Auctionator.",
  ["Press Ctrl+C to copy, then import it into a TSM group."] =
    "Натисніть Ctrl+C, щоб скопіювати, потім імпортуйте в групу TSM.",
  ["Remove from favourites"] = "Прибрати з обраного",
  ["Rename…"] = "Перейменувати…",
  ["Save"] = "Зберегти",
  ["The game could not tell which items these are: %s. Shift-click them into the item box instead."] =
    "Гра не змогла визначити, що це за предмети: %s. Додайте їх Shift+кліком у поле предмета.",
  ["There are no items in this list."] = "У цьому списку немає предметів.",
  ["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."] =
    "Це стиснений експорт групи TSM — розпакувати його може лише TSM. Вставте його на goldcap.gg/list, натисніть там «Copy as TSM group» і вставте результат сюди.",
  ["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."] =
    "GoldCap не може прочитати такий список. Вставте список із goldcap.gg, TSM або Auctionator.",
  ["in game"] = "у грі",
  -- Buy runs: the import result and the vendor list, now that the BUY tab's lists use them.
  ["The run's vendor reagents. Press Ctrl+C to copy the list."] =
    "Реагенти зі списку, які продає торговець. Натисніть Ctrl+C, щоб скопіювати список.",
  ["Vendor list"] = "Список для торговця",
  ["run imported: %s (%d lines)"] = "список імпортовано: %s (рядків: %d)",
  ["the run string is not valid"] = "рядок списку пошкоджено",
  -- BUY: a gear line's tooltip names the lot it buys next (UI/BuyFrame.lua).
  ["next to buy: %s"] = "наступна покупка: %s",
  -- BUY: the item box at the top -- several items at once, typed names, recents (UI/BuyAddBox.lua).
  ["Add"] = "Додати",
  ["Added %d items to a new list, %s."] = "Додано предметів: %d — до нового списку «%s».",
  ["Clear"] = "Очистити",
  ["Could not read: %s."] = "Не вдалося прочитати: %s.",
  ["Items to add: %d — %s"] = "До додавання: %d — %s",
  ["Recent:"] = "Нещодавні:",
  ["Shift-click items, type a name, or an item id with x and a count: 2589 x20."] =
    "Зробіть Shift+клік по предметах, введіть назву або ID предмета з x і кількістю: 2589 x20.",
  -- BUY search: what is on sale, the results, opening one and adding it to a list (UI/BuySearch.lua).
  ["AVAILABLE"] = "У НАЯВНОСТІ",
  ["Add to list…"] = "Додати до списку…",
  ["Back to %s"] = "До списку «%s»",
  ["Click to buy it here. Right-click to add it to a list."] =
    "Клік — купити тут. Правий клік — додати до списку.",
  ["Close search"] = "Закрити пошук",
  ["How many"] = "Скільки",
  ["How many of %s?"] = "Скільки: %s?",
  ["Loading more results…"] = "Завантажуємо ще результати…",
  ["More results"] = "Ще результати",
  ["Nothing on sale for “%s”."] = "За запитом «%s» нічого не продається.",
  ["On sale for “%s”: %d"] = "Знайдено за запитом «%s»: %d",
  ["Open the auction house to search what's on sale."] =
    "Відкрийте аукціон, щоб шукати серед того, що продається.",
  ["PRICE FROM"] = "ЦІНА ВІД",
  ["Search again"] = "Шукати знову",
  ["Searching the auction house for “%s”…"] = "Шукаємо «%s» на аукціоні…",
  ["The auction house did not answer. Search again."] = "Аукціон не відповів. Повторіть пошук.",
  ["Type a whole number."] = "Введіть ціле число.",
  ["Waiting for the auction house…"] = "Чекаємо на аукціон…",
  -- Craft costs: which reagent had no price and why, and the merchant as a source of cost
  -- (Core/CraftCapture.lua, Core/VendorBuys.lua).
  ["this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed"] =
    "цей рецепт робить з одного матеріалу кілька різних предметів (просіювання, дроблення, помел), тому собівартість не рахується",
  ["%s ×%d: no purchase of it found, here or on your other characters"] =
    "%s ×%d: покупку не знайдено ні в цього персонажа, ні в інших твоїх персонажів",
  ["%s ×%d: only %d of them were bought, the rest has no price"] =
    "%s ×%d: куплено лише %d, для решти немає ціни",
  ["%s ×%d: made by prospecting, crushing or milling, not bought"] =
    "%s ×%d: отримано просіюванням, дробленням або помелом, не куплено",
  ["%s ×%d: bought as different variants, so which one was used is unclear"] =
    "%s ×%d: куплено в різних варіантах, тому незрозуміло, який використано",
  ["%s: %d at the vendor price, %s each"] =
    "%s: %d за ціною торговця, %s за штуку",
  ["%s: priced from another character's purchases"] =
    "%s: ціну взято з покупок іншого персонажа",
  ["%s: %d at the market price, %s each"] =
    "%s: %d за ринковою ціною, по %s за штуку",
  ["Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price"] =
    "Частина цієї вартості — оцінка: реагенти, яких ви не купували, пораховано за їхньою поточною ціною на аукціоні",
  ["Vendor"] =
    "Торговець",
  ["SELLING %d"] = "ПРОДАЮ %d",
  ["NOT SELLING %d"] = "НЕ ПРОДАЮ %d",
  ["POST lists these"] = "їх виставляє ВИСТАВИТИ",
  ["only their own Post lists these"] = "лише своя кнопка «Виставити»",
  ["Selling"] = "Продаю",
  ["Not selling"] = "Не продаю",
  ["POST lists it, and so does the key for posting the next item."] = "Виставляють ВИСТАВИТИ і клавіша для наступного предмета.",
  ["Only this row's own Post lists it."] = "Виставить лише кнопка «Виставити» в цьому рядку.",
  ["Marked for you: you bought it on DEALS."] = "Позначено саме: ви купили це на вкладці DEALS.",
  ["Click to change."] = "Клацніть, щоб змінити.",
  ["Mark what to sell with the circle"] = "Позначте кружком, що продавати",
  ["PROCEEDS"] = "ВИРУЧКА",
  ["What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut."] = "Скільки принесе все, що виставить ВИСТАВИТИ, якщо продасться за цими цінами, за вирахуванням 5% комісії аукціону.",
  ["What your lots bring in if they all sell, after the auction house's 5% cut."] = "Скільки принесуть ваші лоти, якщо продадуться всі, за вирахуванням 5% комісії аукціону.",
  ["PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it."] = "ВИРУЧКА мінус те, що ви заплатили за цей товар. Видно, лише поки GoldCap знає, скільки ви заплатили за весь товар.",
  ["HOW MANY"] = "СКІЛЬКИ",
  ["MAX"] = "УСЕ",
  ["skipped"] = "пропущено",
  ["posted"] = "виставлено",
  ["POST"] = "ВИСТАВИТИ",
  ["SKIP"] = "ПРОПУСТИТИ",
  ["then %s"] = "далі %s",
}
