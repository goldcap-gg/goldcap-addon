local _, GC = ...

-- Korean. Terminology follows apps/web/messages/ko.json where the site has the same concept.
-- On this locale the kit draws in one of Blizzard's own faces for the script, taken from the
-- client's data rather than from the client's active font (Theme.RefreshFonts / CJK_FACES):
-- the bundled monospace face has no CJK coverage at all.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.koKR = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d개, 개당 %s  (총 %s, 수수료 %s)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " Companion이 자동으로 갱신합니다: /goldcap companion.",
  [" · %d hidden"] = " · %d개 숨김",
  [" · %d keys"] = " · 키 %d개",
  [" · below cost"] = " · 원가 미만",
  [" · identity unresolved"] = " · 대상 미확정",
  [" · stale %ds"] = " · %d초 지남",
  [" — Check again"] = " — 다시 확인하세요",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — 명령어: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (짧게 /gc)",
  ["%d (whole lot)"] = "%d (전체 물량)",
  ["%d ahead of you"] = "내 앞에 %d개",
  ["%d caps · %s"] = "가격 상한 %d개 · %s",
  ["%d days"] = "%d일",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "지난 검색의 거래 %d건 -- 갱신하려면 Full Scan",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "재판매가 어렵거나 1회 구매 최소 수익 미만이라 %d건 제외",
  ["%d held back"] = "%d건 보류",
  ["%d held back from posting"] = "등록에서 %d건 보류",
  ["%d hidden -- the live check refused them"] = "%d개 숨김 -- 실시간 확인에서 거부됨",
  ["%d in %d lots"] = "%d개 · 물량 %d건",
  ["%d in 1 lot"] = "%d개 · 물량 1건",
  ["%d lots, %s asked"] = "물량 %d건, 요청가 %s",
  ["%d missing"] = "%d건 없음",
  ["%d partial"] = "%d건 일부",
  ["%d prices in one request · books still loading"] = "요청 한 번으로 시세 %d개 · 호가창 불러오는 중",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "실시간 확인에서 %d건 거부 -- 위의 \"HIDDEN %d\"를 눌러 확인하세요",
  ["%d sales · %s proceeds · %s in the mail"] = "판매 %d건 · 수익 %s · 우편함 %s",
  ["%d units"] = "%d개",
  ["%d units · %d prices"] = "%d개 · 가격 %d단",
  ["%d without a price"] = "가격 없음 %d건",
  ["%d without cost"] = "원가 없음 %d건",
  ["%d · %d/%d covered"] = "%d · %d/%d 확인됨",
  ["%d/%d covered"] = "%d/%d 확인됨",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s 개당    총 %s -> %s",
  ["%s after the AH cut"] = "경매장 수수료 제외 %s",
  ["%s ahead"] = "앞에 %s",
  ["%s under you"] = "내 가격보다 낮은 매물 %s",
  ["%s units in %d prices"] = "%s개 · 가격대 %d개",
  ["%s — %d unit%s without a cost"] = "%s — 원가 없는 %d개%s",
  ["%s+ ahead"] = "앞에 %s+",
  ["%s+, %d prices read"] = "%s+, 가격 %d개 읽음",
  [", %d hidden: hard to resell or under your min profit"] = ", 재판매가 어렵거나 최소 수익 미만이라 %d개 숨김",
  ["1 lot, %s asked"] = "물량 1건, 요청가 %s",
  ["24h trend"] = "24시간 추세",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "대시(—)는 아직 모든 수량의 매입가를 모른다는 뜻입니다. 시세로 추측하는 일은 없습니다.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "약속이 아니라 실마리입니다: 가져온 시세의 95%로 재판매할 때, Check가 승인할 수량 기준입니다.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "여러 건의 구매가 한 줄로 합쳐져 있으면 그 전부가 삭제됩니다.",
  ["AH answered empty %ds ago"] = "%d초 전 경매장이 빈 응답을 보냈습니다",
  ["ASKING"] = "호가",
  ["AT MARKET"] = "시장가",
  ["AUTO"] = "자동",
  ["AUTO · SCANNING"] = "자동 · 검색 중",
  ["AUTOMATION & ALERTS"] = "자동화 및 알림",
  ["AVOID"] = "회피",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "24시간 동안 이 상승폭을 넘으면 시세를 급등으로 간주해 낮춰서 반영합니다.",
  ["Above your price -- quoted %s, your price %s"] = "설정 가격 초과 -- 견적 %s, 내 가격 %s",
  ["Asks for a second click to confirm."] = "확인을 위해 한 번 더 눌러야 합니다.",
  ["At your price"] = "내 가격 도달",
  ["Auction House did not answer — press Refresh"] = "경매장이 응답하지 않았습니다 — Refresh를 누르세요",
  ["Auction House is not open"] = "경매장이 열려 있지 않습니다",
  ["Auto-scan on next AH visit"] = "다음 경매장 방문 시 자동 검색",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "자동: Full Scan을 계속 돌리고, 구매할 때는 즉시 양보합니다. 경매장을 직접 검색하거나 우편함을 확인하세요. 클릭하면 전환됩니다.",
  ["Avoid"] = "회피",
  ["BOOKS %d/%d"] = "호가창 %d/%d",
  ["BRAKES"] = "브레이크",
  ["BUY — unverified"] = "구매 — 미검증",
  ["Background check"] = "백그라운드 확인",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "손익분기점은 수수료를 내고도 매입가를 회수하는 최저 가격입니다. 그 아래로 팔면 손해입니다.",
  ["Bundled %s data"] = "내장된 %s 데이터",
  ["Bundled data"] = "내장된 데이터",
  ["Buy"] = "구매",
  ["Buy less"] = "적게 사기",
  ["CANCEL %d"] = "취소 %d",
  ["CANCEL LOT?"] = "물량 취소?",
  ["CANCELLING…"] = "취소 중…",
  ["CONFIRM"] = "확인",
  ["COST"] = "원가",
  ["COST / UNIT"] = "원가 / 개",
  ["Can't price this"] = "가격을 낼 수 없음",
  ["Cancel"] = "취소",
  ["Cancel lot"] = "물량 취소",
  ["Cancel lot?"] = "물량 취소?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "이 물량을 취소하고 등록비를 잃습니다 — 다시 클릭하면 확정됩니다",
  ["Cancel timed out"] = "취소 시간이 초과되었습니다",
  ["Cancelling lot…"] = "물량 취소 중…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "진행 중인 이 경매를 취소합니다 — 다시 등록하지는 않습니다. 등록비는 돌려받지 못하고 물품은 우편으로 돌아옵니다; 도착하면 이 줄에서 다시 등록하세요.",
  ["Cannot post this position"] = "이 항목은 등록할 수 없습니다",
  ["Cannot remove this entry"] = "이 기록은 삭제할 수 없습니다",
  ["Cannot repost this lot"] = "이 물량은 다시 등록할 수 없습니다",
  ["Capped by how fast this actually sells, not by your wallet."] = "지갑이 아니라 실제 판매 속도가 수량을 제한합니다.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "더 싼 매물이 남아 있지만, 이 아이템의 속도라면 몇 시간 안에 소진됩니다.",
  ["Check"] = "확인",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "Check는 골드가 움직이기 전에 실시간 호가로 다시 계산하며, 마지막 가져오기 이후 시장이 바뀌었다면 더 낮게 나오거나 거부할 수 있습니다.",
  ["Checked against the live order book a moment ago."] = "방금 실시간 호가창과 대조했습니다.",
  ["Checked: %d of the top %d on screen"] = "확인: %d개 (화면 상위 %d개 중)",
  ["Checking prices…"] = "가격 확인 중…",
  ["Checking this item's price…"] = "이 아이템의 가격을 확인하는 중…",
  ["Checking..."] = "확인 중...",
  ["Clear to buy"] = "구매해도 좋음",
  ["Click Confirm to post"] = "Confirm을 눌러 등록하세요",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "한 번 더 누르면 진행 중인 경매가 취소됩니다. 다시 등록되지는 않습니다: 등록비는 돌려받지 못하고, 물품은 가방이 아니라 우편으로 돌아옵니다.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "한 번 더 누르면 직접 입력한 이 매입가가 영구히 삭제됩니다.",
  ["Close"] = "닫기",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "Companion이 시세를 자동으로 갱신합니다 — /goldcap companion",
  ["Companion sync rejected:"] = "Companion 동기화가 거부됨:",
  ["Confirm"] = "확인",
  ["Confirm the cancel"] = "취소 확인",
  ["Confirm the removal"] = "삭제 확인",
  ["Copy the link (Ctrl+C) and open it in a browser:"] = "링크를 복사(Ctrl+C)해 브라우저에서 여세요:",
  ["Cost per unit"] = "개당 매입가",
  ["Cost unknown for %d of %d"] = "원가 모름: %d개 / 전체 %d개",
  ["Costs more than your per-buy wallet limit allows."] = "1회 구매 한도보다 비쌉니다.",
  ["Could not find the queue's next item to post — try again"] =
    "등록 대기열의 다음 아이템을 찾지 못했습니다 — 다시 시도하세요",
  ["Could not find the queue's next lot to cancel — try again"] =
    "취소 대기열의 다음 물량을 찾지 못했습니다 — 다시 시도하세요",
  ["DEFAULTS"] = "기본값",
  ["DISC"] = "할인",
  ["DISPLAY"] = "표시",
  ["DONE"] = "완료",
  ["Default listing length for the Sell tab."] = "매도 탭의 기본 등록 기간입니다.",
  ["Default: %s"] = "기본값: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "매입가 입력에 직접 적은 값만 삭제합니다 — GoldCap이 스스로 잡았거나 우편과 대조한 구매는 지우지 않습니다.",
  ["Discount"] = "할인",
  ["Discount vs market value from your GoldCap import"] = "GoldCap 가져오기의 시세 대비 할인율",
  ["Dump-trend cap %"] = "하락 추세 상한 %",
  ["Duration"] = "기간",
  ["Enlarge the window to see details"] = "세부 정보를 보려면 창을 키우세요",
  ["Enter a whole quantity"] = "정수 수량을 입력하세요",
  ["Enter an exact positive cost"] = "정확한 양수 원가를 입력하세요",
  ["Entry price (avg fill)"] = "진입가 (평균 체결)",
  ["Entry total"] = "진입 총액",
  ["Est. profit"] = "예상 수익",
  ["Everything else checks out. With more gold on this character, this is a buy."] = "나머지는 모두 통과했습니다. 이 캐릭터에 골드가 더 있으면 살 만한 매물입니다.",
  ["FIFO allocations"] = "선입선출 배분",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "이 아이템의 최신 가격을 가져오는 중 — 잠시 후 Post를 다시 누르세요",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "이 물량의 최신 가격을 가져오는 중 — 잠시 후 Repost를 다시 누르세요",
  ["Finish the pending post first"] = "진행 중인 등록을 먼저 끝내세요",
  ["Finish the pending post or repost first"] = "진행 중인 등록 또는 재등록을 먼저 끝내세요",
  ["Font scale"] = "글꼴 크기",
  ["Free, sits in the tray, nothing to set up in game."] = "무료이고 트레이에 상주하며, 게임 안에서 설정할 것이 없습니다.",
  ["Full pass over them: %.1fs"] = "전체 순회: %.1f초",
  ["Full pass over them: measuring..."] = "전체 순회: 측정 중...",
  ["Gold tied up"] = "묶이는 골드",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "GoldCap이 가방의 어느 묶음인지 특정하지 못했습니다",
  ["GoldCap data age"] = "GoldCap 데이터 경과",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "GoldCap이 다시 확인하는 상위 %d 줄을 실시간 경매장과 대조합니다. 주기는 약 %d초입니다. 거부된 줄은 숨겨집니다. 구매는 언제나 직접 누르는 클릭입니다.",
  ["GoldCap value"] = "GoldCap 시세",
  ["GoldCap — Import realm prices"] = "GoldCap — 서버 시세 가져오기",
  ["GoldCap's"] = "GoldCap 가격",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "이 아이템에 대한 GoldCap의 제안과, 그때 쓸 가격.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- a deal, but you need %s on this character"] = "GoldCap: 실시간 확인 완료 -- 좋은 매물이지만 이 캐릭터에 %s 필요",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: 실시간 확인 완료 -- 구매해도 안전합니다",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: 아직 실시간 경매장에서 확인하지 않음",
  ["Gone"] = "사라짐",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "회색이면 시세가 오래된 것입니다. Post와 Repost는 실행 전에 시세를 갱신합니다.",
  ["HIDDEN 0"] = "숨김 0",
  ["HIDE DETAILS ▾"] = "세부 정보 숨기기 ▾",
  ["HOLDING %d"] = "보류 %d",
  ["Held back from cancelling"] = "취소에서 보류됨",
  ["Held back from the queue"] = "대기열에서 보류됨",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "청산가 아래 매물벽이 평소 판매량으로 몇 시간 분량까지 버틸 수 있는지, 넘으면 거래를 거부합니다.",
  ["ITEM"] = "아이템",
  ["If it clears"] = "팔린다면",
  ["Import"] = "가져오기",
  ["Import failed:"] = "가져오기 실패:",
  ["Import from goldcap.gg to arm the sniper"] = "goldcap.gg에서 가져와 스나이퍼를 활성화하세요",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "무료 GoldCap Companion을 설치하면 시세가 자동으로 갱신됩니다 (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "이것은 빨리 팔려면 이겨야 할 가격이지, 아이템의 가치가 아닙니다. 급한 판매자 한 명이 가치보다 훨씬 낮게 내놓을 수 있으며 GoldCap은 그 아래로 따라가지 않습니다. 실제 등록 가격은 WHAT TO DO를 보세요.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "시세로 매입가를 지어내지 않으므로, 입력하기 전까지 수익은 알 수 없음으로 남습니다.",
  ["Item"] = "아이템",
  ["Item %d"] = "아이템 %d",
  ["Item level %d, below the %d your price is for"] = "아이템 레벨 %d -- 내 가격의 기준 %d보다 낮음",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."] =
    "아이템: 장비, 펫, 제작법을 가져온 지역 기준가와 비교해 가격을 매깁니다. 판매 속도는 절대 측정되지 않으므로 안전 판정을 받는 일이 없습니다 -- 구매는 당신 몫이며, GoldCap은 이 목록이 열려 있는 동안만 확인합니다.",
  ["LISTED"] = "등록됨",
  ["Language"] = "언어",
  ["Language changed. Type /reload to apply it everywhere."] =
    "언어를 바꿨습니다. 모든 곳에 적용하려면 /reload를 입력하세요.",
  ["Last post may still go up -- wait a minute"] = "아직 등록될 수 있습니다 -- 1분 기다리세요",
  ["Last result: %ds ago"] = "마지막 결과: %d초 전",
  ["Last result: none yet this visit"] = "마지막 결과: 이번 방문에는 아직 없음",
  ["Listed"] = "등록 수량",
  ["Listed at %s — far below market. Repost."] = "%s에 등록됨 — 시세보다 훨씬 낮습니다. 다시 등록하세요.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "goldcap.gg에서 정한 내 가격 이하로 등록되어 있습니다. 되팔 수 있을지는 직접 판단하세요.",
  ["Listed value"] = "등록 금액",
  ["Listings"] = "등록 수",
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "가방에 있는 물량을 무엇을 할지 항목의 가격으로 등록합니다: 상품은 가방 전체 수량을, 일반 아이템은 묶음 하나를.",
  ["Live ask"] = "현재 호가",
  ["Lot cancelled; wait for it to return to bags"] = "물량을 취소했습니다. 가방으로 돌아올 때까지 기다리세요",
  ["MARKET"] = "시세",
  ["MARKET / UNIT"] = "시세 / 개",
  ["MATCH"] = "맞추기",
  ["Market per unit"] = "개당 시세",
  ["Market reference"] = "시세 기준",
  ["Max units per buy"] = "1회 구매 최대 수량",
  ["Max wallet per buy %"] = "1회 구매 최대 지갑 비중 %",
  ["Min profit per buy (gold)"] = "1회 구매 최소 수익 (골드)",
  ["Min return per buy %"] = "1회 구매 최소 수익률 %",
  ["Missing cost"] = "매입가 없음",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "아직 GOLDCAP.GG에 없음 — /RELOAD 또는 접속 종료 시 동기화",
  ["NOT ON HAND %d"] = "수중에 없음 %d",
  ["NOTHING TO CANCEL"] = "취소할 것 없음",
  ["NOTHING TO POST"] = "등록할 것 없음",
  ["Needs a live price check before it can be bought."] = "구매하려면 먼저 실시간 시세 확인이 필요합니다.",
  ["Needs gold"] = "골드 필요",
  ["Never spend more than this share of your gold on one purchase."] = "한 번의 구매에 소지금의 이 비율을 넘게 쓰지 않습니다.",
  ["No answer yet -- listening for a minute"] = "아직 응답 없음 -- 1분 더 기다립니다",
  ["No deals passed the safety checks right now."] = "지금은 안전 확인을 통과한 거래가 없습니다.",
  ["No deals to show -- and no realm prices yet."] = "표시할 거래가 없습니다 -- 서버 시세도 아직 없습니다.",
  ["No deals yet."] = "아직 거래가 없습니다.",
  ["No exact auction key"] = "정확한 경매 키가 없습니다",
  ["No exact bag stack"] = "정확한 가방 묶음이 없습니다",
  ["No exact bag variant"] = "정확한 가방 변형이 없습니다",
  ["No live listings came back for this item."] = "이 아이템의 실시간 매물이 하나도 오지 않았습니다.",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "이 아이템의 지역 기준가가 아직 없습니다 — goldcap.gg에 기준가가 올라오면 다시 가져오세요.",
  ["No safe resale price could be worked out."] = "안전한 재판매 가격을 산출할 수 없었습니다.",
  ["No sales data for this item."] = "이 아이템의 판매 데이터가 없습니다.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "기록된 판매가 없습니다 -- GoldCap을 켠 채 우편함을 여세요",
  ["Not enough gold on this character to buy what GoldCap finds"] = "이 캐릭터의 골드로는 GoldCap이 찾은 매물을 살 수 없음",
  ["Not enough units on the Auction House to fill that quantity."] = "경매장에 그 수량을 채울 만큼의 물량이 없습니다.",
  ["Not in your bags or listed — mail or bank?"] = "가방에도 없고 등록도 안 됨 — 우편함이나 은행인가요?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "보유 중이 아님 — 물량이 우편함, 은행 또는 다른 캐릭터에 있습니다",
  ["Nothing is being held back."] = "보류된 것이 없습니다.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "이번 구매 뒤에는 되팔 상대 물량이 남지 않아 매도 기준가가 없습니다.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "기준 가격을 측정한 아이템 레벨에 맞는 매물이 없습니다.",
  ["Nothing listed on the AH right now"] = "지금 경매장에 등록된 것이 없습니다",
  ["Nothing on this deck matches that search"] = "이 탭에는 검색과 일치하는 항목이 없습니다",
  ["Nothing queued to cancel"] = "취소 대기열이 비었습니다",
  ["Nothing queued to post"] = "등록 대기열이 비었습니다",
  ["Nothing to remove"] = "삭제할 것이 없습니다",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "GOLDCAP.GG 기준 — 최근 %d일",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "GOLDCAP.GG 기준 — 최근 %d일, 최신 %d/%d",
  ["ON THE AUCTION HOUSE"] = "경매장에 올린 것",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "페이지 단위 조회로 경매장 전체를 한 번 검색합니다. 소요 시간은 약 붐비는 서버에서 15~60초. 대기시간 없음 -- 언제든 다시 검색하세요.",
  ["Open the Auction House first."] = "먼저 경매장을 여세요.",
  ["Open the Auction House to begin scanning."] = "검색을 시작하려면 경매장을 여세요.",
  ["Open the deals board. /gc for commands."] = "거래 목록을 엽니다. 명령어는 /gc.",
  ["POST %d"] = "등록 %d",
  ["POSTING"] = "등록",
  ["POSTING…"] = "등록 중…",
  ["PRICE"] = "가격",
  ["PRICE ROSE %.1fx"] = "가격이 %.1f배 올랐습니다",
  ["PRICED TOO LOW %d"] = "너무 낮은 가격 %d",
  ["PRICING %d/%d"] = "시세 %d/%d",
  ["PRICING…"] = "시세 확인 중…",
  ["PROFIT"] = "수익",
  ["PROFIT / UNIT"] = "수익 / 개",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "goldcap.gg의 수익을 보려면 GoldCap Companion을 연결하거나 갱신하세요",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "goldcap.gg의 서버 문자열을 붙여넣고 Import를 누르세요.",
  ["Per-unit price of this auction"] = "이 경매의 개당 가격",
  ["Play a sound when a checked deal turns SAFE."] = "검증된 거래가 SAFE가 되면 소리를 재생합니다.",
  ["Position scope changed"] = "항목 범위가 바뀌었습니다",
  ["Positions without a cost or a live price are excluded."] =
    "원가나 실시간 가격이 없는 항목은 제외됩니다.",
  ["Post"] = "등록",
  ["Post above the cheapest"] = "최저가보다 높게 등록",
  ["Post confirmation expired"] = "등록 확인이 만료되었습니다",
  ["Post the next queued item"] = "대기열의 다음 아이템 등록",
  ["Posted"] = "등록됨",
  ["Posting failed"] = "등록에 실패했습니다",
  ["Posting unavailable"] = "등록할 수 없습니다",
  ["Posting…"] = "등록 중…",
  ["Press Full Scan to find deals."] = "거래를 찾으려면 Full Scan을 누르세요.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "경매장 전체를 한 번 검색하려면 Scan을, 계속 검색하려면 Auto를 누르세요.",
  ["Previous removal selection cleared"] = "이전 삭제 선택을 해제했습니다",
  ["Previous repost selection cleared"] = "이전 재등록 선택을 해제했습니다",
  ["Price"] = "가격",
  ["Priced from bundled sample data, not from your realm."] =
    "함께 포함된 샘플 데이터 기준이며, 당신의 서버 시세가 아닙니다.",
  ["Prices up to date"] = "시세가 최신입니다",
  ["Prices up to date · %d did not answer"] = "시세가 최신입니다 · %d건은 응답 없음",
  ["Pricing %d/%d…"] = "가격 조회 %d/%d…",
  ["Pricing paused while you use the Auction House"] = "경매장을 사용하는 동안 가격 조회 일시 중지",
  ["Pricing…"] = "가격 조회 중…",
  ["Profit"] = "수익",
  ["Profit per unit"] = "개당 수익",
  ["Profit tracking is a goldcap.gg Pro feature"] = "수익 추적은 goldcap.gg Pro 기능입니다",
  ["Purchases are turned off in this build."] = "이 빌드에서는 구매가 꺼져 있습니다.",
  ["QTY"] = "수량",
  ["Quantity exceeds missing units"] = "수량이 부족분을 초과합니다",
  ["Quantity is capped by how fast this item actually sells."] = "수량은 이 아이템이 실제로 팔리는 속도에 의해 제한됩니다.",
  ["REALIZED PROFIT"] = "실현 수익",
  ["REFRESH"] = "새로고침",
  ["RESET WINDOW"] = "창 초기화",
  ["Reason"] = "이유",
  ["Refresh"] = "새로고침",
  ["Refresh waiting for prior result"] = "이전 결과를 기다리는 중입니다",
  ["Refreshing listings…"] = "등록 목록 갱신 중…",
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "최근 24시간 동안 가격이 이보다 더 떨어졌으면 구매를 거부합니다 — 계속 떨어질 수 있습니다.",
  ["Refused so far: %d"] = "지금까지 거부: %d건",
  ["Removal confirmation expired"] = "삭제 확인이 만료되었습니다",
  ["Remove"] = "삭제",
  ["Remove this cost"] = "이 매입가 삭제",
  ["Remove?"] = "삭제할까요?",
  ["Removed"] = "삭제됨",
  ["Removed %d entries"] = "%d개 항목 삭제됨",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "이 묶음에서 직접 입력한 구매를 모두 삭제합니다 -- 다시 클릭하면 확정됩니다",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "직접 입력한 이 구매를 삭제합니다 -- 다시 클릭하면 확정됩니다",
  ["Repost confirmation expired"] = "재등록 확인이 만료되었습니다",
  ["Right-click to stop watching this item"] = "이 아이템 주시를 멈추려면 우클릭",
  ["Right-click to watch this item closely"] = "이 아이템을 자세히 주시하려면 우클릭",
  ["SAFE +%s"] = "안전 +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "안전 = 실시간 확인이 이 구매를 승인했습니다, 표시된 수익 기준",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "즉시 저장됨 · ESC 또는 DONE으로 닫기",
  ["SCAN"] = "검색",
  ["SCANNING…"] = "검색 중…",
  ["SESSION %s%s · %d BUYS"] = "세션 %s%s · 구매 %d건",
  ["SHOW DETAILS ▸"] = "세부 정보 보기 ▸",
  ["Sales are costed from your oldest units first"] = "판매 원가는 가장 오래된 물량부터 차감됩니다",
  ["Search"] = "검색",
  ["Sales evidence"] = "판매 신뢰도",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "매도 탭은 주문서가 같은 속도로 팔린다고 볼 때 최저가보다 한 단계 위에 등록합니다.",
  ["Sell-through"] = "판매 소진율",
  ["Sellers"] = "판매자",
  ["Sells too rarely -- you would be holding it for a long time."] = "너무 드물게 팔립니다 — 오래 들고 있게 됩니다.",
  ["Set cost"] = "원가 입력",
  ["Settings"] = "설정",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "경매장 수수료를 뗀 후에도 이 금액 이상 남지 않으면 구매를 건너뜁니다.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "수익이 지불액의 이 비율 이상이 아니면 구매를 건너뜁니다.",
  ["Snapshot value"] = "스냅숏 가치",
  ["Sold per day"] = "일일 판매량",
  ["Sold/day"] = "일일 판매량",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "무엇을 살지가 아니라, 무엇을 먼저 확인할지 정할 때 이 기준으로 정렬하세요.",
  ["Sound on SAFE deal"] = "SAFE 매물에 소리 알림",
  ["Source age"] = "자료 경과 시간",
  ["Spike-trend threshold %"] = "급등 추세 기준 %",
  ["Start scanning as soon as the auction house opens."] = "경매장을 열자마자 바로 검색을 시작합니다.",
  ["Status"] = "상태",
  ["Stop and open the buy window on your price"] = "내 가격에 도달하면 중지 후 구매 창 열기",
  ["Stress exit unit"] = "스트레스 청산 단가",
  ["Stress profit"] = "스트레스 수익",
  ["THE BOOK"] = "호가창",
  ["TOTAL"] = "합계",
  ["TREND"] = "추세",
  ["Tell GoldCap what you actually paid for these units."] = "이 물량을 실제로 얼마에 샀는지 GoldCap에 알려 주세요.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "경매장이 등록비를 알려주지 않아 비용을 알 수 없습니다.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "Companion은 동기화 중이지만, 이 애드온이 기록된 내용을 읽지 못했습니다:",
  ["The auction house did not answer -- try again"] = "경매장이 응답하지 않았습니다 -- 다시 시도하세요",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "목록은 가져온 스냅숏으로 등급을 매겼습니다. 실시간 호가창은 이를 뒷받침하지 않습니다.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "버튼은 잠시 뒤에야 눌립니다. 실수로 두 번 클릭해도 실행되지 않습니다.",
  ["The cancel did not go through — the lot is still listed"] = "취소가 처리되지 않았습니다 — 물량이 아직 등록되어 있습니다",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "가장 싼 매물이 더 이상 기준 가격보다 충분히 낮지 않습니다.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "실시간 경매장 조회에서 다른 사람이 부르는 가장 싼 가격입니다. 본인 등록분은 제외되므로 이 숫자가 스스로를 따라 내려가지 않습니다.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "이 아이템의 데이터가 손상되어 GoldCap이 추측하지 않습니다.",
  ["The liquidity data is not reliable enough to act on."] = "유동성 데이터가 판단 근거로 삼기엔 신뢰도가 낮습니다.",
  ["The market value is an estimate, not a measurement."] = "시세는 측정값이 아니라 추정값입니다.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "한 번의 구매로 살 수 있는 최대 수량입니다. 아이템이 팔리는 속도에 따라 더 적어질 수 있습니다.",
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "시세 데이터가 세 시간이 넘었습니다. Companion을 동기화한 뒤 /reload 하세요 — 애드온은 UI를 불러올 때만 데이터를 읽습니다.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "가격은 확인했습니다. 얼마나 빨리 팔리는지는 어디에서도 측정되지 않으니 직접 판단하세요.",
  ["The price is falling; buying into it is how you get stuck."] =
    "가격이 내려가는 중입니다. 여기서 사면 물리기 딱 좋습니다.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "가격은 마지막으로 받아온 값으로, 최대 45초 전의 것입니다. 확인하기 전에 값이 바뀌면 옛 가격으로 보내지 않고 등록을 포기합니다.",
  ["The price moved -- part of this quote may be above your price"] =
    "가격이 바뀌었습니다 -- 이 견적의 일부가 내 가격보다 비쌀 수 있습니다",
  ["The price moved and the trade is no longer safe."] = "가격이 움직여 더 이상 안전한 거래가 아닙니다.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "5% 수수료와 등록비를 내고 나면 설정한 최소 수익에 미치지 못합니다.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "되돌릴 수 없습니다. 한 번 누르면 확인을 위해 한 번 더 눌러야 합니다.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "서버 전용 아이템이며, GoldCap은 상품(commodity) 시세만 검증합니다.",
  ["Too few sellers to read a real price."] = "판매자가 너무 적어 실제 시세를 읽을 수 없습니다.",
  ["Too little of what is listed actually sells."] = "등록된 물량 중 실제로 팔리는 비율이 너무 낮습니다.",
  ["Too little price history to trust the value."] = "가격 기록이 너무 적어 이 값을 믿을 수 없습니다.",
  ["Total cost to buy this auction"] = "이 경매를 사는 총 비용",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "골드 단위로 가격을 입력하거나, 칸을 비우면 GoldCap 가격을 씁니다",
  ["UNDERCUT"] = "한 단계 밑",
  ["UNDERCUT %d"] = "밀린 물량 %d",
  ["UNIT"] = "단가",
  ["Unit price"] = "단가",
  ["Unknown"] = "알 수 없음",
  ["Unknown item"] = "알 수 없는 아이템",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "알 수 없음은 매입가가 다 채워지지 않았다는 뜻입니다 — 매입가 입력으로 채우세요.",
  ["VERDICT"] = "판정",
  ["Verdict"] = "판정",
  ["WAITING FOR THE AUCTION HOUSE %d"] = "경매장 대기 중 %d",
  ["WATCH"] = "관찰",
  ["WATCH (computed SAFE)"] = "WATCH (계산상 안전)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "관찰 = 실시간 확인이 거절했습니다 -- 줄에 마우스를 올리면 이유가 나옵니다",
  ["WHAT COUNTS AS A DEAL"] = "거래로 인정되는 조건",
  ["WHAT TO DO"] = "할 일",
  ["WHAT YOU PAID"] = "내가 지불한 값",
  ["WHEN"] = "시점",
  ["Waiting for Auction House…"] = "경매장을 기다리는 중…",
  ["Waiting for a live price"] = "실시간 가격을 기다리는 중",
  ["Waiting for the Auction House…"] = "경매장을 기다리는 중…",
  ["Waiting for the purchase to finish…"] = "구매가 끝나기를 기다리는 중…",
  ["Wall absorb window (hours)"] = "물량 흡수 기간 (시간)",
  ["Watching closely: %d item%s"] = "자세히 주시 중: 아이템 %d개%s",
  ["Watching — pinned, but not a deal right now"] = "주시 중 — 고정했지만 지금은 거래가 아닙니다",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "아직 보유 중인 매입 건들을 평균해서, 한 개가 실제로 얼마였는지.",
  ["What to do"] = "무엇을 할지",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "시세에 팔렸을 때 한 개로 남는 돈: 판매가에서 경매장 수수료 5%와 매입가를 뺀 값.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "이 아이템으로 올려둔 경매들의 현재 호가 합계.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "매물이 사이트에서 설정한 가격에 도달하면 검색을 멈추고 구매 창을 엽니다.",
  ["Window position & size"] = "창 위치와 크기",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "있으면 서버 시세가 자동으로 갱신되고, 판매 기록과 수익이 goldcap.gg에 쌓입니다.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "없으면 GoldCap은 릴리스 시점의 시세 스냅샷으로 돌아갑니다 — 오래된 시세로 거래를 찾게 됩니다.",
  ["Won't buy"] = "사지 않음",
  ["Worst case back"] = "최악의 경우 회수",
  ["YOUR LOTS"] = "내 물량",
  ["YOUR PRICE"] = "내 가격",
  ["You paid"] = "구매가",
  ["You pay"] = "지불 금액",
  ["You would get"] = "받게 될 금액",
  ["You would pay"] = "지불할 금액",
  ["Your call"] = "당신의 판단",
  ["Your minimum"] = "내 최소 기준",
  ["Your price"] = "내 가격",
  ["a unit, at or under your price of %s"] = "개당 가격, 내 가격 %s 이하",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "최저가보다 높게, 저가 구간 안 · 앞에 %s개",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "최저가보다 높게, 하루 도달 범위 안 · 앞에 %s개",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "이 아이템의 지역 기준가 대비, 수수료 5% 제외 — 팔린다면",
  ["age %ss"] = "%s초 전",
  ["another purchase took over -- nothing was confirmed"] = "다른 구매가 대신 진행 중입니다 -- 아무것도 확정하지 않았습니다",
  ["any figure here would be invented out of the very number being refused"] =
    "여기 어떤 숫자든 지금 거부당한 바로 그 값에서 지어낸 것이 됩니다",
  ["at or under your price -- click Buy to purchase"] = "내 가격 이하 -- Buy를 눌러 구매하세요",
  ["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"] =
    "GoldCap이 팔릴 것으로 예상하는 가격 기준, 수수료 5% 제외 — 내 호가가 아님",
  ["auto off"] = "자동 꺼짐",
  ["auto-synced %dh ago"] = "%d시간 전 자동 동기화",
  ["auto-synced data for %s loaded (%s old)"] = "%s의 자동 동기화 자료를 불러왔습니다 (%s 경과)",
  ["auto-synced data stale -- /goldcap import"] = "자동 동기화 자료가 오래됨 -- /goldcap import",
  ["auto: paused"] = "자동: 일시중지",
  ["below the %s you paid"] = "지불한 %s보다 낮음",
  ["big buy"] = "대량 구매",
  ["bought %d x item %d"] = "%d개 구매 · 아이템 %d",
  ["bought %d x item %d after AH close"] = "경매장 종료 후 %d개 구매 · 아이템 %d",
  ["buying commodity..."] = "상품 구매 중...",
  ["cheapest not yours %s"] = "내 것이 아닌 최저가 %s",
  ["check the item level — buy by hand"] = "아이템 레벨 확인 — 직접 구매",
  ["checking live price..."] = "실시간 가격 확인 중...",
  ["checking live safety..."] = "실시간 안전성 확인 중...",
  ["clears in ~%dd"] = "~%d일 후 소진",
  ["clears in ~%dh"] = "~%d시간 후 소진",
  ["commodity purchase failed"] = "상품 구매에 실패했습니다",
  ["confirmed commodity purchase failed after AH close"] =
    "경매장 종료 후 확정된 상품 구매가 실패했습니다",
  ["confirming purchase..."] = "구매 확정 중...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "원가 정보가 불완전합니다 -- 재등록 조언을 받으려면 원가를 입력하세요",
  ["cost unknown"] = "원가 모름",
  ["crafted %s"] = "제작 %s",
  ["data from goldcap.gg · synced %s ago"] = "goldcap.gg 자료 · %s 전 동기화",
  ["due -- will be asked next pass"] = "차례 -- 다음 순회에 조회합니다",
  ["expires in %d s"] = "%d초 후 만료",
  ["fair"] = "보통",
  ["far below market"] = "시세보다 훨씬 낮음",
  ["finish the pending buy first"] = "진행 중인 구매를 먼저 끝내세요",
  ["first in line"] = "맨 앞 순서",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "가격은 %s입니다. 1회 구매 한도 %d%% 기준으로 이 캐릭터에 %s이(가) 있어야 합니다.",
  ["fresh"] = "최신",
  ["full scan already in progress"] = "전체 검색이 이미 진행 중입니다",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "전체 검색 완료: 거래 %d건%s · 아이템 그룹 %d개%s%s",
  ["full scan interrupted -- confirm your purchase"] = "전체 검색이 중단됨 -- 구매를 확정하세요",
  ["full scan stalled -- press Full Scan to retry"] =
    "전체 검색이 멈췄습니다 -- Full Scan을 눌러 다시 시도하세요",
  ["full scan stalled -- retrying shortly"] = "전체 검색이 멈췄습니다 -- 곧 다시 시도합니다",
  ["full scan stopped -- press %s to run it again"] = "전체 검색이 중단됐습니다 -- %s 버튼을 눌러 다시 실행하세요",
  ["gone / price changed"] = "사라짐 / 가격 변경",
  ["strong"] = "높음",
  ["hold"] = "보류",
  ["identity unresolved (variant item -- not priced by design)"] =
    "식별 실패 (변형 아이템 -- 의도적으로 가격을 매기지 않음)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "%d개를 모두 사서 지금 걸려 있는 가격에 되판다면",
  ["ilvl %d"] = "아이템 레벨 %d",
  ["import %dh old"] = "가져오기 %d시간 경과",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "가져온 자료가 오래됨 -- /goldcap import 또는 /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "아이템 %d개를 가져왔습니다 · %s (%s) — 이제 시세가 반영됩니다.",
  ["in the mail"] = "우편함에 있음",
  ["in the mail, the bank or on another character"] = "우편함, 은행 또는 다른 캐릭터에 있음",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "가 이 시장이 소화하는 양입니다 — 그 이상은 떠안게 될 재고입니다",
  ["item %d"] = "아이템 %d",
  ["item %d: %s"] = "아이템 %d: %s",
  ["item level %d+"] = "아이템 레벨 %d+",
  ["item variant unresolved"] = "아이템 변형 미확정",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "최근 24시간 — 판매 %d건, 총액 %s, 수수료 %s, 구매 %d건, 지출 %s",
  ["leave these alone"] = "그대로 두세요",
  ["level %d"] = "레벨 %d",
  ["listing gone -- already bought out or price changed"] =
    "등록이 사라짐 -- 이미 팔렸거나 가격이 바뀌었습니다",
  ["listing gone -- bought out or repriced"] = "매물이 사라졌습니다 — 팔렸거나 가격이 바뀜",
  ["live safety confirmed -- click Buy to purchase"] = "실시간 안전 확인 완료 -- Buy를 눌러 구매하세요",
  ["live verification required"] = "실시간 확인이 필요합니다",
  ["weak"] = "낮음",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "수동 가져오기 -- Companion이 자동 갱신합니다: /goldcap companion",
  ["market %s"] = "시세 %s",
  ["needs %s"] = "%s 필요",
  ["needs a fresh price -- press Refresh"] = "최신 가격이 필요합니다 -- Refresh를 누르세요",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "서버 확인이 없습니다 -- 구매는 성사되었을 수 있으니 우편함을 확인하세요. 이 창을 닫아도 취소되지 않습니다.",
  ["no cost"] = "원가 없음",
  ["no cost for %d"] = "%d개 원가 없음",
  ["no live price yet"] = "아직 실시간 가격 없음",
  ["no live quote yet — pricing…"] = "아직 실시간 시세가 없습니다 — 가격 확인 중…",
  ["no market figure for caged pets"] = "우리에 든 애완동물은 시장 수치 없음",
  ["no market figure for this item level"] = "이 아이템 레벨의 시장 수치 없음",
  ["no price"] = "가격 없음",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "아직 시세가 없습니다 -- /goldcap companion 또는 /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "구매 확인을 받지 못했습니다 -- Cancel 후 다시 시도하세요",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "기록된 판매가 없습니다 — GoldCap을 켠 채 우편함을 열면 청구서에서 읽어옵니다",
  ["no stock in bags or listed -- nothing to price for"] =
    "가방에도 없고 등록도 없습니다 -- 가격을 매길 대상이 없습니다",
  ["none"] = "없음",
  ["not enough gold -- total %s, you have %s"] = "골드가 부족합니다 -- 총 %s, 보유 %s",
  ["not enough gold for this quote -- Cancel"] = "이 가격에 필요한 골드가 부족합니다 -- Cancel",
  ["not enough gold on this character -- you need %s"] = "이 캐릭터의 골드가 부족합니다 -- %s 필요",
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "해당 수량만큼 남아 있지 않습니다 -- 남은 물량을 다시 확인하는 중...",
  ["not priced — nothing on hand to sell"] = "가격 없음 — 판매할 물건이 없습니다",
  ["not ready to cancel"] = "취소할 준비가 되지 않았습니다",
  ["not ready to post"] = "등록할 준비가 되지 않았습니다",
  ["nothing listed"] = "등록된 것이 없습니다",
  ["of %d"] = "/ %d",
  ["off"] = "꺼짐",
  ["oldest units sell first"] = "오래된 것부터 먼저 팔립니다",
  ["on"] = "켜짐",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "경매장을 한 번 열면 GoldCap이 판매 방식을 알 수 있습니다",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "또는 /goldcap import로 goldcap.gg의 문자열을 붙여넣으세요.",
  ["over %d position%s"] = "%d개 보유 항목 기준%s",
  ["paid sale unresolved"] = "정산된 판매 미확정",
  ["placing bid..."] = "입찰 중...",
  ["previous commodity purchase settled -- %s to re-check the price"] =
    "이전 상품 구매가 끝남 -- %s 버튼으로 가격을 다시 확인하세요",
  ["price changed after you closed the buy window -- nothing was bought"] =
    "구매 창을 닫은 뒤 가격이 바뀌었습니다 -- 아무것도 구매하지 않았습니다",
  ["price checked, sale speed unknown -- this one is your call"] =
    "가격은 확인했지만 판매 속도는 알 수 없습니다 -- 판단은 당신 몫입니다",
  ["price confirmed -- click Buy to purchase"] = "가격 확인됨 -- Buy를 눌러 구매하세요",
  ["price rose %.1fx — still safe, confirm"] = "가격이 %.1f배 올랐습니다 — 여전히 안전합니다, 확정하세요",
  ["price stands %d of %d"] = "가격 순위 %d / %d",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "불러온 시세는 %s(%s)인데 접속 지역은 %s입니다 — 모든 할인율과 수익이 다른 시장 기준으로 계산됩니다",
  ["purchase canceled"] = "구매를 취소했습니다",
  ["purchase complete"] = "구매 완료",
  ["purchase identity unresolved"] = "구매 대상 미확정",
  ["purchase pending exact cost"] = "정확한 원가를 기다리는 구매",
  ["purchase total unavailable — inspect mailbox"] = "구매 총액을 알 수 없습니다 — 우편함을 확인하세요",
  ["quote %s -- click Confirm to buy"] = "시세 %s -- Confirm을 눌러 구매하세요",
  ["quote %ss ago"] = "시세 %s초 전",
  ["quote expired -- Refresh to re-check the price"] =
    "시세가 만료됨 -- Refresh로 가격을 다시 확인하세요",
  ["quote expires in %d s -- click Confirm to buy"] = "시세가 %d초 후 만료됨 -- Confirm을 눌러 구매하세요",
  ["re-checking what remains at a safe price..."] = "안전한 가격에 남은 물량을 다시 확인하는 중...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "서버 아이템 — 판매 속도 미검증 · 지역 기준가 %s (아이템 레벨 %d)",
  ["recent sales (newest first):"] = "최근 판매 (최신순):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "지역 %s — 내장: 아이템 %d개 (%s), 가져옴: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "장부 %d줄의 지역을 바로잡고, 판매 %d건을 재고와 다시 연결했습니다",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "지금 재등록하면 손실이나 정체가 확정됩니다 -- 보류하세요",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "우편 검사 오류로 남은 중복 구매 기록 %d건을 삭제했습니다",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "우편 검사 오류로 남은 중복 판매 기록 %d건을 삭제했습니다",
  ["sale name ambiguous"] = "판매 항목 이름이 모호함",
  ["sale proceeds pending"] = "판매 대금 대기 중",
  ["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"] =
    "검색 완료: 거래 %d건%s · 아이템 %d개%s (재료, 소모품, 보석, 마법부여)%s",
  ["scanned %d listings over %d passes"] = "등록 %d건을 %d번 순회로 검색했습니다",
  ["scanning auction house..."] = "경매장 검색 중...",
  ["scanning… %d results · %d deals%s"] = "검색 중… 결과 %d건 · 거래 %d건%s",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "하루 %s개 판매",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "세션: 저격 %d건, 지출 %s, 예상 수익 약 %s",
  ["sniped (listing changed on rescan)"] = "저격됨 (재검색에서 등록이 바뀜)",
  ["sniped for "] = "낚아챈 금액 ",
  ["stack not identified"] = "묶음 식별 불가",
  ["stale"] = "오래됨",
  ["starting full scan..."] = "전체 검색을 시작합니다...",
  ["stopped watching %s"] = "%s 주시를 멈췄습니다",
  ["the Companion wrote prices this addon could not read --"] =
    "Companion이 기록한 시세를 이 애드온이 읽지 못했습니다 --",
  ["the auction house has not sent details for these yet"] = "경매장이 아직 이 아이템들의 정보를 보내지 않았습니다",
  ["the import failed (%s)"] = "가져오기에 실패했습니다 (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "%d개를 하루 %s개 속도로 파는 동안 %s이(가) 계속 묶입니다",
  ["unavailable"] = "없음",
  ["under GoldCap's own floor of %s"] = "GoldCap 자체 하한 %s보다 낮음",
  ["unknown evidence"] = "알 수 없는 근거",
  ["waiting for previous commodity purchase to settle"] = "이전 상품 구매가 끝나기를 기다리는 중",
  ["waiting for previous search result to settle"] = "이전 검색 결과를 기다리는 중",
  ["waiting..."] = "대기 중...",
  ["wall"] = "벽",
  ["wall %s at %s -- price under it to sell first"] = "%s개 벽 (%s) -- 그보다 낮게 올려야 먼저 팔립니다",
  ["wall %s at %s above you"] = "%s개 벽 (%s) -- 내 가격보다 위",
  ["watching %s closely -- re-checked every few seconds"] =
    "%s을(를) 자세히 주시 중 -- 몇 초마다 다시 확인합니다",
  ["worst case, selling all %d back into the price standing there now"] =
    "최악의 경우, %d개를 지금 걸려 있는 가격에 모두 되판다면",
  ["worth cancelling"] = "취소할 만함",
  ["would sell at a loss"] = "손해를 보고 팔게 됩니다",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "아직 서버 시세를 가져오지 않았습니다 -- GoldCap Companion을 설치하거나(/goldcap companion) goldcap.gg의 문자열을 붙여넣으세요(/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "이 게임 클라이언트에는 해당 언어의 글꼴이 없습니다 — 글자가 빈 네모로 보입니다",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "가져온 자료가 %d시간 지났습니다 -- 시세가 어긋날 수 있습니다. goldcap.gg에서 새 문자열을 붙여넣으세요 (/goldcap import).",
  ["your price is above every level shown"] = "내 가격이 표시된 모든 단계보다 높음",
  ["yours"] = "내 가격",
  ["yours ×%s"] = "내 것 ×%s",
  ["~%dd to reach you"] = "내 차례까지 ~%d일",
  ["~%dh to reach you"] = "내 차례까지 ~%d시간",
  ["» needs price"] = "» 가격 필요",
  ["×%d in bags"] = "가방에 ×%d",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "가방에 ×%d · Post는 그중 가장 큰 묶음 %d개를 등록합니다",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "가방에 ×%d · GoldCap이 정확히 식별할 수 있는 묶음이 없습니다",
  ["×%d in your bags, ready to list"] = "가방에 ×%d, 등록 준비됨",
  ["×%d listed"] = "×%d 등록됨",
  ["×%d listed at %s each"] = "×%d, 개당 %s에 등록됨",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · 구매 %s · %s · %s",
  ["×%d%s · made %s · %s"] = "×%d%s · 제작 %s · %s",
  ["— = nothing is checking this row right now"] = "— = 지금 이 줄을 확인하는 것은 없습니다",
  ["… = a live check is queued for this row"] = "… = 이 줄의 실시간 확인이 대기 중입니다",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ goldcap.gg 시세 — 아직 실시간 시세가 없습니다",
  ["no answer %ds ago -- resting"] = "%d초 전 응답 없음 -- 대기 중",
  ["the last attempt is still settling -- checking the price again..."] =
    "이전 시도가 아직 정리되는 중 -- 가격을 다시 확인하는 중...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "goldcap.gg에서 정한 내 가격 이하로 등록됨 (그룹: %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "자동 · 일시중지: 구매 창",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "구매 창이 열려 있는 동안 일시중지됩니다. 구매하거나 창을 닫으면 자동이 이어집니다.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "자동 · 일시중지: 내 검색",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "경매장 검색창에 입력하는 동안 일시중지됩니다. 검색창을 벗어나고 몇 초 뒤에 이어집니다.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "자동 · 일시중지: 우편함 열림",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "우편함이 열려 있는 동안 일시중지됩니다. 닫으면 자동이 이어집니다.",
  ["AUTO · PAUSED: SELL TAB"] = "자동 · 일시중지: 판매 탭",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "판매 탭이 열려 있는 동안 일시중지됩니다. 같은 검색으로 가방 시세를 매기기 때문입니다. 딜로 돌아가면 자동이 이어집니다.",
  ["AUTO · PAUSED: ITEMS BOARD"] = "자동 · 일시중지: 아이템 목록",
  ["Paused while the Items board is shown: it asks the auction house through the same search. Switch to Commodities and Auto carries on."] =
    "아이템 목록이 표시되는 동안 일시중지됩니다. 같은 검색으로 경매장에 묻기 때문입니다. 재료로 전환하면 자동이 이어집니다.",
  ["AUTO · PAUSED: BUY TAB"] = "자동 · 일시중지: BUY 탭",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "BUY 탭이 열려 있는 동안 일시중지됩니다. 같은 검색으로 가격을 조회하기 때문입니다. 딜로 돌아가면 자동이 이어집니다.",
  ["AUTO · WAITING FOR YOU"] = "자동 · 사용자 대기 중",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "경매장 자체 창에서 등록, 구매, 둘러보기를 하는 동안 기다립니다. 멈추는 즉시 시작합니다.",
  ["AUTO · WAITING: YOUR LIST"] = "자동 · 대기: 내 목록",
  ["Waiting: your own search is on the auction house's Buy list, and a scan would replace it. Open GoldCap's auction house tab, or close the auction house, and Auto starts."] =
    "대기 중: 경매장 구매 목록에 내 검색 결과가 있고, 검색하면 그것을 덮어씁니다. 경매장의 GoldCap 탭을 열거나 경매장을 닫으면 자동이 시작합니다.",
  ["Market %s · unverified until a live Check"] = "시세 %s · 실시간 확인 전까지는 미검증",
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "지역 전체 시세: 거래 물품 %d개, 판매 정보 %d개, 서버 아이템 %d개 (경과 %s, %d KB)",
  ["whole-market data not in use: %s"] = "지역 전체 시세 사용 안 함: %s",
  ["it is %s old, and the prices you imported are newer"] = "%s 지난 자료이며, 가져온 시세가 더 최신입니다",
  ["it is for another region than the prices loaded"] = "불러온 시세와 다른 지역의 자료입니다",
  ["its date cannot be right -- check this computer's clock"] = "날짜가 올바를 수 없습니다 -- 이 컴퓨터의 시계를 확인하세요",
  ["it was set aside when other prices were loaded this session -- /reload to use it again"] =
    "이번 세션에서 다른 시세를 불러오면서 보류되었습니다 -- 다시 쓰려면 /reload",
  ["On the AH now"] = "지금 경매장",
  ["%s listed · %d min ago"] = "%s개 등록 · %d분 전",
  ["%s listed · just now"] = "%s개 등록 · 방금",
  ["it could not be read (%s)"] = "읽을 수 없었습니다 (%s)",
  ["it is for a region this build of GoldCap does not know -- update the addon"] =
    "이 버전의 GoldCap이 지원하지 않는 지역의 자료입니다 -- 애드온을 업데이트하세요",
  ["it is in a format this build of GoldCap cannot read -- update the addon"] =
    "이 버전의 GoldCap이 읽을 수 없는 형식입니다 -- 애드온을 업데이트하세요",
  ["it is larger than this build of GoldCap can read -- update the addon"] =
    "이 버전의 GoldCap이 읽을 수 있는 크기보다 큽니다 -- 애드온을 업데이트하세요",
  ["the Companion wrote an empty copy -- let it sync, then /reload"] =
    "Companion이 빈 자료를 기록했습니다 -- 다시 동기화될 때까지 기다린 뒤 /reload 하세요",
  ["the Companion wrote it with no prices -- let it sync, then /reload"] =
    "Companion이 시세 없는 자료를 기록했습니다 -- 다시 동기화될 때까지 기다린 뒤 /reload 하세요",
}
