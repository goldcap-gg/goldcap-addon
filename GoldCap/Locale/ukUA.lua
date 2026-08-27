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
  [" rows against the live auction house about every "] =
    " рядків проти живого аукціону приблизно кожні ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · %d hidden"] = " · приховано %d",
  [" · below cost"] = " · нижче собівартості",
  [" · identity unresolved"] = " · позиція не впізнана",
  [" · stale %ds"] = " · застаріло %dс",
  [" — Check again"] = " — перевірте ще раз",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — команди: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (або коротко /gc)",
  ["%d (whole lot)"] = "%d (увесь лот)",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d угод з останнього сканування -- Full Scan, щоб оновити",
  ["%d filtered out as hard to resell"] = "%d відсіяно як важкі для перепродажу",
  ["%d held back"] = "%d притримано",
  ["%d held back from posting"] = "%d притримано від виставлення",
  ["%d missing"] = "%d бракує",
  ["%d partial"] = "%d частково",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d відхилено живою перевіркою -- натисніть \"HIDDEN %d\" вгорі, щоб переглянути",
  ["%d sales · %s proceeds · %s in the mail"] = "%d продажів · %s виторг · %s у пошті",
  ["%d without a price"] = "%d без ціни",
  ["%d without cost"] = "%d без собівартості",
  ["%d · %d/%d covered"] = "%d · %d/%d покрито",
  ["%d/%d covered"] = "%d/%d покрито",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s за штуку    разом %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d одиниц%s без собівартості",
  [", %d hidden as unsellable"] = ", приховано %d як непродавані",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "15-60 секунд на завантажених реалмах. Без відкату -- скануйте будь-коли.",
  ["24h trend"] = "Тренд за 24г",
  ["A commodity lists the whole bag total at once; a normal item lists one stack, the largest GoldCap can identify exactly."] =
    "Товар виставляється всім обсягом із сумок одразу; звичайний предмет — одним стеком, найбільшим, який GoldCap може розпізнати точно.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Орієнтир, а не обіцянка: перепродаж за 95% імпортованої ринкової вартості, на кількість, яку схвалить сама перевірка.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Якщо кілька покупок згорнуті в один рядок, видаляться вони всі.",
  ["AH answered empty %ds ago"] = "Аукціон відповів порожньо %dс тому",
  ["AUTO"] = "АВТО",
  ["AUTO · PAUSED: "] = "АВТО · ПАУЗА: ",
  ["AUTO · SCANNING"] = "АВТО · СКАН",
  ["AUTOMATION & ALERTS"] = "АВТОМАТИКА ТА СПОВІЩЕННЯ",
  ["Auction House did not answer — press Refresh"] = "Аукціон не відповів — натисніть Refresh",
  ["Auction House is not open"] = "Аукціон не відкрито",
  ["Auto-scan on next AH visit"] = "Автосканування при наступному візиті на АД",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Авто: тримає Full Scan увімкненим постійно й миттєво поступається, коли ви купуєте, ",
  ["Avoid"] = "Уникати",
  ["Background check"] = "Фонова перевірка",
  ["Bundled %s data"] = "Вбудовані дані %s",
  ["Bundled data"] = "Вбудовані дані",
  ["Buy"] = "Купити",
  ["Buy %d × %s for %s"] = "Купити %d × %s за %s",
  ["CANCEL %d"] = "СКАСУВАТИ %d",
  ["CANCEL LOT?"] = "СКАСУВАТИ ЛОТ?",
  ["CANCELLING…"] = "СКАСУВАННЯ…",
  ["CONFIRM"] = "ПІДТВЕРДИТИ",
  ["CONFIRM PURCHASE"] = "ПІДТВЕРДИТИ КУПІВЛЮ",
  ["COST / UNIT"] = "СОБІВАРТІСТЬ / ШТ",
  ["Cancel"] = "Скасувати",
  ["Cancel lot?"] = "Скасувати лот?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Скасувати цей лот і втратити заставу — натисніть ще раз для підтвердження",
  ["Cancel timed out"] = "Час на скасування вичерпано",
  ["Cancelling forfeits the deposit, so this asks for a second click to confirm."] =
    "Скасування позбавляє застави, тому потрібен другий клік для підтвердження.",
  ["Cancelling lot…"] = "Скасовуємо лот…",
  ["Cancels this live auction. It does NOT relist it: the deposit is forfeit, and the cancelled items come back by mail, not straight into your bags."] =
    "Скасовує цей активний лот. Заново він НЕ виставляється: застава втрачається, а зняті предмети приходять поштою, а не одразу в сумки.",
  ["Cannot post this position"] = "Не можна виставити цю позицію",
  ["Cannot remove this entry"] = "Не можна видалити цей запис",
  ["Cannot repost this lot"] = "Не можна перевиставити цей лот",
  ["Check"] = "Перевірити",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Перевірка перераховує це за живою книгою заявок, перш ніж рушить золото, і може дати менше — або відмовити — якщо ринок змінився після останнього імпорту.",
  ["Checked: %d of the top %d on screen"] = "Перевірено: %d з %d верхніх на екрані",
  ["Checking prices…"] = "Перевіряємо ціни…",
  ["Checking this item's price…"] = "Перевіряємо ціну цього предмета…",
  ["Click Confirm to post"] = "Натисніть Confirm, щоб виставити",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Ще один клік скасує активний лот. Заново він не виставляється: застава втрачається, а предмети прийдуть поштою, а не одразу в сумки.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Ще один клік видалить цю введену вручну собівартість назавжди.",
  ["Close"] = "Закрити",
  ["Companion sync rejected:"] = "Синхронізацію Companion відхилено:",
  ["Confirm"] = "Підтвердити",
  ["Confirm the cancel"] = "Підтвердити скасування",
  ["Confirm the removal"] = "Підтвердити видалення",
  ["Cost unknown for %d of %d"] = "Собівартість невідома для %d з %d",
  ["Could not find the queue's next item to post — try again"] =
    "Не вдалося знайти наступний предмет у черзі на виставлення — спробуйте ще раз",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Не вдалося знайти наступний лот у черзі на скасування — спробуйте ще раз",
  ["DEAL THRESHOLDS"] = "ПОРОГИ УГОД",
  ["DISC"] = "ЗНИЖКА",
  ["DISPLAY"] = "ВІДОБРАЖЕННЯ",
  ["DONE"] = "ГОТОВО",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Видаляє лише собівартість, введену вручну у «Вказати ціну», — але не покупку, яку GoldCap упіймав сам чи зіставив із поштою.",
  ["Discount"] = "Знижка",
  ["Discount vs market value from your GoldCap import"] =
    "Знижка від ринкової вартості з вашого імпорту GoldCap",
  ["Dump-trend cap %"] = "Поріг спадного тренду %",
  ["Duration"] = "Тривалість",
  ["ENTRY AVG"] = "СЕРЕДНІЙ ВХІД",
  ["EST. PROFIT AFTER AH CUT"] = "ОРІЄНТ. ПРИБУТОК ПІСЛЯ КОМІСІЇ",
  ["Enlarge the window to see details"] = "Збільшіть вікно, щоб побачити деталі",
  ["Enter a whole quantity"] = "Введіть цілу кількість",
  ["Enter an exact positive cost"] = "Введіть точну додатну собівартість",
  ["Entry price (avg fill)"] = "Ціна входу (середнє виконання)",
  ["Entry total"] = "Разом на вході",
  ["Est. profit"] = "Орієнт. прибуток",
  ["FIFO allocations"] = "Розподіл FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Отримуємо свіжу ціну для цього предмета — натисніть Post ще раз за мить",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Отримуємо свіжу ціну для цього лота — натисніть Repost ще раз за мить",
  ["Finish the pending post first"] = "Спершу завершіть виставлення, що триває",
  ["Finish the pending post or repost first"] =
    "Спершу завершіть виставлення або перевиставлення, що триває",
  ["Font scale"] = "Масштаб шрифту",
  ["Full pass over them: %.1fs"] = "Повний прохід по них: %.1fс",
  ["Full pass over them: measuring..."] = "Повний прохід по них: вимірюємо...",
  ["GOOD = solid discount + profit"] = "GOOD = добра знижка + прибуток",
  ["GOOD — min discount %"] = "GOOD — мінімальна знижка %",
  ["GOOD — min sold/day"] = "GOOD — мінімум продажів на день",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap не може точно визначити, який це стек у сумці",
  ["GoldCap data age"] = "Вік даних GoldCap",
  ["GoldCap re-checks the top "] = "GoldCap перевіряє верхні ",
  ["GoldCap value"] = "Оцінка GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Імпорт цін реалму",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: перевірено наживо -- безпечно купувати",
  ["Gone"] = "Зник",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Сірий колір означає, що котирування застаріло; Post і Repost оновлять його перед дією.",
  ["HIDDEN 0"] = "ПРИХОВАНО 0",
  ["HIDE DETAILS ▾"] = "СХОВАТИ ДЕТАЛІ ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = велика знижка + високий прибуток + підтверджені продажі/день",
  ["HOT — min discount %"] = "HOT — мінімальна знижка %",
  ["HOT — min sold/day"] = "HOT — мінімум продажів на день",
  ["Held back from cancelling"] = "Притримано від скасування",
  ["Held back from the queue"] = "Притримано з черги",
  ["ITEM"] = "ПРЕДМЕТ",
  ["Import"] = "Імпорт",
  ["Import failed:"] = "Імпорт не вдався:",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Встановіть безкоштовний GoldCap Companion, щоб ціни оновлювались самі (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "Це те, що треба перебити, аби продати швидко — а не те, скільки предмет вартий. Один продавець поспіхом може опустити ціну значно нижче вартості, і GoldCap не піде за ним униз: дивіться WHAT TO DO, щоб побачити ціну, за якою він справді виставить.",
  ["It will list stock GoldCap never saw you buy — not knowing what something cost is a reason to report the profit as unknown, not a reason to refuse to sell it."] =
    "Виставиться й те, покупки чого GoldCap не бачив: незнання собівартості — привід показати прибуток як невідомий, а не привід відмовитися продавати.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Собівартість не вигадується з ринкової ціни — доки ви її не введете, прибуток лишиться невідомим.",
  ["Item"] = "Предмет",
  ["Item %d"] = "Предмет %d",
  ["LISTED"] = "ВИСТАВЛЕНО",
  ["LIVE VERDICT · CHECKING"] = "ЖИВИЙ ВЕРДИКТ · ПЕРЕВІРКА",
  ["LIVE VERDICT · REFUSED"] = "ЖИВИЙ ВЕРДИКТ · ВІДМОВА",
  ["LIVE VERDICT · SAFE"] = "ЖИВИЙ ВЕРДИКТ · БЕЗПЕЧНО",
  ["Language"] = "Мова",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Мову змінено. Введіть /reload, щоб застосувати її всюди.",
  ["Last result: %ds ago"] = "Останній результат: %dс тому",
  ["Last result: none yet this visit"] = "Останній результат: ще не було цього візиту",
  ["Listed"] = "Виставлено",
  ["Listed at %s — far below market. Repost."] =
    "Виставлено за %s — значно нижче ринку. Перевиставте.",
  ["Listings"] = "Лотів",
  ["Lists what is sitting in your bags at the price shown under WHAT TO DO."] =
    "Виставляє те, що лежить у сумках, за ціною з колонки ЩО РОБИТИ.",
  ["Lot cancelled; wait for it to return to bags"] =
    "Лот скасовано; чекайте, поки він повернеться до сумок",
  ["MARKET / UNIT"] = "РИНОК / ШТ",
  ["Market per unit"] = "Ринок за штуку",
  ["Market reference"] = "Ринковий орієнтир",
  ["Max wallet per buy %"] = "Макс. частка гаманця на купівлю %",
  ["Min profit per buy (gold)"] = "Мінімальний прибуток з купівлі (золото)",
  ["Missing cost"] = "Немає собівартості",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "ЩЕ НЕ НА GOLDCAP.GG — СИНХРОНІЗУЄТЬСЯ ПІСЛЯ /RELOAD АБО ВИХОДУ",
  ["NOTHING TO CANCEL"] = "НЕМА ЩО СКАСОВУВАТИ",
  ["NOTHING TO POST"] = "НЕМА ЩО ВИСТАВЛЯТИ",
  ["No deals passed the safety checks right now."] =
    "Зараз жодна угода не пройшла перевірок безпеки.",
  ["No deals to show -- and no realm prices yet."] =
    "Немає угод -- і ще немає цін реалму.",
  ["No deals yet."] = "Поки що немає угод.",
  ["No exact auction key"] = "Немає точного ключа аукціону",
  ["No exact bag stack"] = "Немає точного стека в сумці",
  ["No exact bag variant"] = "Немає точного варіанта в сумці",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Продажів ще не записано -- відкрийте пошту з увімкненим GoldCap",
  ["Not in your bags or listed — mail or bank?"] =
    "Немає в сумках і не виставлено — пошта чи банк?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Немає під рукою — запас у пошті, банку або на іншому персонажі",
  ["Nothing is being held back."] = "Нічого не притримано.",
  ["Nothing listed on the AH right now"] = "Зараз на аукціоні нічого не виставлено",
  ["Nothing queued to cancel"] = "У черзі на скасування нічого немає",
  ["Nothing queued to post"] = "У черзі на виставлення нічого немає",
  ["Nothing to remove"] = "Нічого видаляти",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "НА GOLDCAP.GG — ОСТАННІ %d ДНІВ",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "НА GOLDCAP.GG — ОСТАННІ %d ДНІВ, НАЙНОВІШІ %d З %d",
  ["Once the mail arrives, list it again yourself at the new price -- from this same row."] =
    "Коли прийде пошта, виставте заново самі за новою ціною — із цього ж рядка.",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Одноразове сканування всього аукціону сторінковими запитами. Триває приблизно ",
  ["Open the Auction House first."] = "Спершу відкрийте аукціон.",
  ["Open the Auction House to begin scanning."] = "Відкрийте аукціон, щоб почати сканування.",
  ["Open the deals board. /gc for commands."] = "Відкрити дошку угод. /gc — команди.",
  ["POST %d"] = "ВИСТАВИТИ %d",
  ["POSTING"] = "ВИСТАВЛЕННЯ",
  ["POSTING…"] = "ВИСТАВЛЯЄМО…",
  ["PRICE"] = "ЦІНА",
  ["PRICE ROSE %.1fx"] = "ЦІНА ЗРОСЛА В %.1fx",
  ["PRICING %d/%d"] = "ЦІНИ %d/%d",
  ["PRICING…"] = "ЦІНИ…",
  ["PROFIT"] = "ПРИБУТОК",
  ["PROFIT / UNIT"] = "ПРИБУТОК / ШТ",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Прив'яжіть або оновіть GoldCap Companion, щоб бачити прибуток з goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Вставте рядок свого реалму з goldcap.gg і натисніть Import.",
  ["Per-unit price of this auction"] = "Ціна за одну штуку в цьому лоті",
  ["Position scope changed"] = "Область позиції змінилася",
  ["Positions without a cost or a live price are excluded."] =
    "Позиції без собівартості чи живої ціни не враховано.",
  ["Post"] = "Виставити",
  ["Post confirmation expired"] = "Підтвердження виставлення протерміновано",
  ["Post the next queued item"] = "Виставити наступний предмет із черги",
  ["Posting failed"] = "Виставлення не вдалося",
  ["Posting timed out"] = "Час на виставлення вичерпано",
  ["Posting unavailable"] = "Виставлення недоступне",
  ["Posting…"] = "Виставляємо…",
  ["Press Full Scan to find deals."] = "Натисніть Full Scan, щоб знайти угоди.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Натисніть Scan, щоб один раз обійти весь аукціон, або Auto, щоб сканувати постійно.",
  ["Previous removal selection cleared"] = "Попередній вибір для видалення скинуто",
  ["Previous repost selection cleared"] = "Попередній вибір для перевиставлення скинуто",
  ["Price"] = "Ціна",
  ["Prices up to date"] = "Ціни актуальні",
  ["Prices up to date · %d did not answer"] = "Ціни актуальні · %d не відповіли",
  ["Pricing %d/%d…"] = "Оцінюємо %d/%d…",
  ["Pricing…"] = "Оцінюємо…",
  ["Profit"] = "Прибуток",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "Облік прибутку — функція goldcap.gg Pro",
  ["QTY"] = "К-ТЬ",
  ["Quantity exceeds missing units"] = "Кількість перевищує відсутні одиниці",
  ["REALIZED PROFIT"] = "РЕАЛІЗОВАНИЙ ПРИБУТОК",
  ["REFRESH"] = "ОНОВИТИ",
  ["RESET WINDOW"] = "СКИНУТИ ВІКНО",
  ["Reason"] = "Причина",
  ["Refresh"] = "Оновити",
  ["Refresh waiting for prior result"] = "Оновлення чекає на попередній результат",
  ["Refreshing listings…"] = "Оновлюємо лоти…",
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
  ["Repost"] = "Перевиставити",
  ["Repost confirmation expired"] = "Підтвердження перевиставлення протерміновано",
  ["Right-click to stop watching this item"] =
    "Правий клік, щоб перестати стежити за предметом",
  ["Right-click to watch this item closely"] =
    "Правий клік, щоб пильно стежити за предметом",
  ["SAFETY"] = "БЕЗПЕКА",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] =
    "ЗБЕРІГАЄТЬСЯ ОДРАЗУ · ESC АБО DONE, ЩОБ ЗАКРИТИ",
  ["SCAN"] = "СКАН",
  ["SCANNING…"] = "СКАНУЄМО…",
  ["SESSION %s%s · %d BUYS"] = "СЕСІЯ %s%s · %d КУПІВЕЛЬ",
  ["SHOW DETAILS ▸"] = "ПОКАЗАТИ ДЕТАЛІ ▸",
  ["STRESS EXIT"] = "СТРЕС-ВИХІД",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = знижка настільки велика, що це радше шахрайство чи хибна ціна ринку",
  ["Sales are costed from your oldest units first"] =
    "Продажі списуються спершу з найстаріших одиниць",
  ["Sell-through"] = "Викуповуваність",
  ["Set cost"] = "Задати собівартість",
  ["Settings"] = "Налаштування",
  ["Sold per day"] = "Продажів на день",
  ["Sold/day"] = "Продажів на день",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Сортуйте за ним, щоб вирішити, що перевірити першим, а не що купувати.",
  ["Sound on HOT deal"] = "Звук на угоді HOT",
  ["Source age"] = "Вік джерела",
  ["Spike-trend threshold %"] = "Поріг стрибка ціни %",
  ["Status"] = "Статус",
  ["Stress exit unit"] = "Ціна стрес-виходу",
  ["Stress profit"] = "Стрес-прибуток",
  ["TIER"] = "КЛАС",
  ["TOTAL"] = "РАЗОМ",
  ["TREND"] = "ТРЕНД",
  ["Tell GoldCap what you actually paid for these units."] =
    "Вкажіть, скільки ви насправді заплатили за ці одиниці.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Companion синхронізується, але аддон не зміг прочитати те, що він записав:",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "Кнопка стає натискною не одразу, тож випадковий подвійний клік її не спрацює.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "Найдешевша ціна, яку зараз просить ХТОСЬ ІНШИЙ, за живим запитом до аукціону. Ваші власні лоти виключено, тому число ніколи не женеться саме за собою вниз.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "Безкоштовний застосунок Companion сам оновлює ваші ціни й синхронізує продажі. Скопіюйте посилання (Ctrl+C) і відкрийте його в браузері:",
  ["The price is the last one GoldCap fetched, at most 45 seconds old — not a fresh check made at the moment you click. If it changes between arming the post and confirming it, the post is abandoned rather than sent at the old price."] =
    "Ціна — остання, яку отримав GoldCap, не старша за 45 секунд, а не свіжа перевірка в момент кліку. Якщо вона зміниться між підготовкою та підтвердженням, виставлення скасовується, а не йде за старою ціною.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Скасувати не можна. Перший клік просить другий для підтвердження.",
  ["Tier"] = "Клас",
  ["Total cost to buy this auction"] = "Повна вартість купівлі цього лота",
  ["UNIT"] = "ЗА ШТ",
  ["Unit price"] = "Ціна за штуку",
  ["Unknown"] = "Невідомо",
  ["Unknown item"] = "Невідомий предмет",
  ["WATCH (computed SAFE)"] = "WATCH (розраховано БЕЗПЕЧНО)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = зі знижкою, але ліквідність не підтверджена або прибуток малий",
  ["WHAT TO DO"] = "ЩО РОБИТИ",
  ["WHEN"] = "КОЛИ",
  ["Waiting for Auction House…"] = "Чекаємо на аукціон…",
  ["Waiting for a live price"] = "Чекаємо на живу ціну",
  ["Waiting for the Auction House…"] = "Чекаємо на аукціон…",
  ["Waiting for the purchase to finish…"] = "Чекаємо завершення купівлі…",
  ["Wall absorb window (hours)"] = "Вікно поглинання стіни (години)",
  ["Watching closely: %d item%s"] = "Пильно стежимо: %d предмет%s",
  ["Watching — pinned, but not a deal right now"] =
    "Стежимо — закріплено, але зараз це не угода",
  ["Window position & size"] = "Позиція та розмір вікна",
  ["Worth doing when someone has undercut you; not worth it if the price barely moved."] =
    "Варто робити, коли вас перебили за ціною; не варто, якщо ціна майже не зрушила.",
  ["You paid"] = "Ви заплатили",
  ["a discount this extreme usually means the market value is wrong, not that this is a bargain"] =
    "така величезна знижка зазвичай означає хибну ринкову вартість, а не вигідну покупку",
  ["auto off"] = "авто вимкнено",
  ["auto-synced %dh ago"] = "автосинхронізація %dг тому",
  ["auto-synced data for %s loaded (%s old)"] =
    "автосинхронізовані дані для %s завантажено (вік %s)",
  ["auto-synced data stale -- /goldcap import"] =
    "автосинхронізовані дані застаріли -- /goldcap import",
  ["auto: paused"] = "авто: пауза",
  ["big buy"] = "велика купівля",
  ["bought %d x item %d"] = "куплено %d x предмет %d",
  ["bought %d x item %d after AH close"] = "куплено %d x предмет %d після закриття аукціону",
  ["buying commodity..."] = "купуємо товар...",
  ["checking live price..."] = "перевіряємо живу ціну...",
  ["checking live safety..."] = "перевіряємо безпеку наживо...",
  ["commodity no longer available -- someone bought it out"] =
    "товару більше немає -- його вже викупили",
  ["commodity purchase failed"] = "купівля товару не вдалася",
  ["confirmed commodity purchase failed after AH close"] =
    "підтверджена купівля товару не вдалася після закриття аукціону",
  ["confirming purchase..."] = "підтверджуємо купівлю...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "собівартість неповна -- задайте її, щоб отримати пораду з перевиставлення",
  ["cost unknown"] = "собівартість невідома",
  ["data from goldcap.gg · synced %s ago"] = "дані з goldcap.gg · синхронізовано %s тому",
  ["due -- will be asked next pass"] = "черга -- запитаємо наступним проходом",
  ["finish the pending buy first"] = "спершу завершіть купівлю, що триває",
  ["full scan already in progress"] = "повне сканування вже триває",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "повне сканування завершено: %d угод%s з %d груп предметів%s%s",
  ["full scan interrupted -- confirm your purchase"] =
    "повне сканування перервано -- підтвердіть купівлю",
  ["full scan stalled -- press Full Scan to retry"] =
    "повне сканування зупинилося -- натисніть Full Scan ще раз",
  ["full scan stalled -- retrying shortly"] = "повне сканування зупинилося -- скоро повторимо",
  ["gone / price changed"] = "зникло / ціна змінилася",
  ["identity unresolved (variant item -- not priced by design)"] =
    "не вдалося визначити (варіативний предмет -- ціна не рахується навмисно)",
  ["import %dh old"] = "імпорту %dг",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "імпорт застарів -- /goldcap import або /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "імпортовано %d предметів для %s (%s) — ціни вже живі.",
  ["in the mail"] = "у пошті",
  ["item %d"] = "предмет %d",
  ["item %d: %s"] = "предмет %d: %s",
  ["item variant unresolved"] = "варіант предмета не визначено",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "останні 24 год — %d продажів, %s валовий, %s комісія аукціону, %d купівель, %s витрачено",
  ["listing gone -- already bought out or price changed"] =
    "лот зник -- уже викуплений або ціна змінилася",
  ["listing gone -- bought out or repriced"] = "лот зник — викуплений або переставлений за ціною",
  ["live safety confirmed -- click Buy to purchase"] =
    "безпеку підтверджено наживо -- натисніть Buy, щоб купити",
  ["live verification required"] = "потрібна жива перевірка",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "ручний імпорт -- Companion оновлює це сам: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "потрібна свіжа ціна -- натисніть Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "сервер не підтвердив -- купівля все одно могла пройти, перевірте пошту. Закриття цього вікна її не скасує.",
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
  ["not ready to cancel"] = "не готово до скасування",
  ["not ready to post"] = "не готово до виставлення",
  ["nothing listed"] = "нічого не виставлено",
  ["of %d"] = "з %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "або вставте рядок з goldcap.gg через /goldcap import.",
  ["over %d position%s"] = "по %d позиціях%s",
  ["paid sale unresolved"] = "оплачений продаж не зіставлено",
  ["placing bid..."] = "робимо ставку...",
  ["price confirmed -- click Buy to purchase"] =
    "ціну підтверджено -- натисніть Buy, щоб купити",
  ["price rose %.1fx — still safe, confirm"] = "ціна зросла в %.1fx — усе ще безпечно, підтвердіть",
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
  ["recent sales (newest first):"] = "останні продажі (найновіші зверху):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "регіон %s — вбудовано: %d предметів (%s), імпортовано: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "регіон виправлено в %d записах; %d продажів зіставлено зі своїм запасом",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "перевиставлення зараз зафіксує збиток або застій -- притримайте",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "видалено %d дубльован%s записів купівлі, залишених помилкою сканування пошти",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "видалено %d дубльован%s записів продажу, залишених помилкою сканування пошти",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    "с. Відхилені рядки приховано. Купівля завжди лишається вашим кліком.",
  ["sale name ambiguous"] = "назва в продажу неоднозначна",
  ["sale proceeds pending"] = "виторг очікується",
  ["scanned %d listings over %d passes"] = "проскановано %d лотів за %d проходів",
  ["scanning auction house..."] = "скануємо аукціон...",
  ["scanning… %d results · %d deals%s"] = "скануємо… %d результатів · %d угод%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "пошукайте на аукціоні самі або перевірте пошту. Клік перемикає.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "продається %s/день",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "сесія: %d перехоплень, витрачено %s, ~%s орієнт. прибутку",
  ["sniped (listing changed on rescan)"] = "перехоплено (лот змінився при перескануванні)",
  ["sniped for "] = "снайпнуто за ",
  ["starting full scan..."] = "починаємо повне сканування...",
  ["stopped watching %s"] = "перестали стежити за %s",
  ["the Companion wrote prices this addon could not read --"] =
    "Companion записав ціни, які аддон не зміг прочитати --",
  ["the import failed (%s)"] = "імпорт не вдався (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["unknown evidence"] = "невідоме підтвердження",
  ["waiting for previous commodity purchase to settle"] =
    "чекаємо, поки завершиться попередня купівля товару",
  ["waiting for previous search result to settle"] =
    "чекаємо, поки завершиться попередній пошук",
  ["waiting for server... full scan will start automatically"] =
    "чекаємо на сервер... повне сканування почнеться саме",
  ["watching %s closely -- re-checked every few seconds"] =
    "пильно стежимо за %s -- перевірка кожні кілька секунд",
  ["would sell at a loss"] = "продалося б у збиток",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "ви ще не імпортували ціни реалму -- встановіть GoldCap Companion (/goldcap companion) або вставте рядок з goldcap.gg (/goldcap import).",
  ["you should clear about %s"] = "ви маєте отримати приблизно %s",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "у вашому клієнті гри немає шрифту для цієї мови — текст відображатиметься порожніми квадратами",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "вашому імпорту %d годин -- ціни можуть бути хибними. Вставте свіжий рядок з goldcap.gg (/goldcap import).",
  ["» needs price"] = "» потрібна ціна",
  ["×%d in bags"] = "×%d у сумках",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d у ваших сумках · Post виставить %d із них, найбільший стек",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d у ваших сумках · немає стека, який GoldCap може точно визначити",
  ["×%d in your bags, ready to list"] = "×%d у ваших сумках, готові до виставлення",
  ["×%d listed"] = "×%d виставлено",
  ["×%d listed at %s each"] = "×%d виставлено по %s за штуку",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · куплено %s · %s · %s",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ ринкова вартість goldcap.gg — живого котирування ще немає",
}
