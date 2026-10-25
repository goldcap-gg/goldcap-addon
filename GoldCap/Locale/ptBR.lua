local _, GC = ...

-- Portuguese (Brazil) -- the only Portuguese locale the retail client reports. Terminology
-- follows apps/web/messages/pt.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ptBR = {
  ["  %s · need %d · have %d · buy %d · %s"] = "  %s · precisa %d · tem %d · comprar %d · %s",
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s cada  (%s no total, %s de taxa)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " O Companion mantém isso atualizado: /goldcap companion.",
  [" · %d keys"] = " · %d chaves",
  [" · below cost"] = " · abaixo do custo",
  [" · identity unresolved"] = " · identidade não resolvida",
  [" · stale %ds"] = " · %ds de idade",
  [". Check again"] = ". Verifique de novo",
  [" · commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " · comandos: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (ou /gc para encurtar)",
  ["%d (whole lot)"] = "%d (lote inteiro)",
  ["%d ahead of you"] = "%d à sua frente",
  ["%d at %s"] = "%d a %s",
  ["%d caps · %s"] = "%d tetos · %s",
  ["%d days"] = "%d dias",
  ["%d deals from your last scan. Full Scan to refresh"] =
    "%d oportunidades da última varredura. Full Scan para atualizar",
  ["%d filtered out: hard to resell, or under your Min profit per buy"] = "%d descartadas: difíceis de revender ou abaixo do seu lucro mínimo por compra",
  ["%d held back"] = "%d retidas",
  ["%d hidden: the live check refused them"] = "%d ocultos: a verificação ao vivo os recusou",
  ["%d hits"] = "%d achados",
  ["%d in %d lots"] = "%d em %d lotes",
  ["%d in 1 lot"] = "%d em 1 lote",
  ["%d lines"] = "%d linhas",
  ["%d lots, %s asked"] = "%d lotes, pedindo %s",
  ["%d of %d"] = "%d de %d",
  ["%d of %d at or under your cap"] = "%d de %d no seu teto ou abaixo",
  ["%d of %d done"] = "%d de %d feitos",
  ["%d prices in one request · books still loading"] =
    "%d preços em uma só consulta · livros ainda carregando",
  ["%d refused by live checks. Press \"HIDDEN %d\" above to review them"] =
    "%d recusadas pela verificação ao vivo. Clique em \"HIDDEN %d\" acima para vê-las",
  ["%d units"] = "%d unid.",
  ["1 unit"] = "1 unid.",
  ["%d units · %d prices"] = "%d unidades · %d preços",
  ["%d · %d/%d covered"] = "%d · %d/%d cobertos",
  ["%d/%d covered"] = "%d/%d cobertos",
  ["%d× %s"] = "%d× %s",
  ["%d× %s · %s each · %s"] = "%d× %s · %s cada · %s",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s por unidade    total %s -> %s",
  ["%s ahead"] = "%s à frente",
  ["%s needs a number, for example /gc weights %s 1.5"] = "%s precisa de um número, por exemplo /gc weights %s 1.5",
  ["%s under you"] = "%s abaixo de você",
  ["%s units in %d prices"] = "%s un. em %d preços",
  ["%s · %s under market"] = "%s · %s abaixo do mercado",
  ["%s · at market price"] = "%s · a preço de mercado",
  ["%s: %d unit%s without a cost"] = "%s: %d unidade%s sem custo",
  ["%s+ ahead"] = "%s+ à frente",
  ["%s+, %d prices read"] = "%s+, %d preços lidos",
  ["..."] = "...",
  ["1 lot, %s asked"] = "1 lote, pedindo %s",
  ["24h trend"] = "Tendência 24h",
  ["A dash means GoldCap does not know the cost of every unit yet. It will never guess one from the market price."] =
    "Um traço significa que o GoldCap ainda não sabe o custo de cada unidade. Ele nunca vai adivinhar pelo preço de mercado.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Uma pista, não uma promessa: revenda a 95% do valor de mercado importado, na quantidade que o próprio Check aprovaria.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Se várias compras estiverem agrupadas em uma linha, todas são removidas.",
  ["AH answered empty %ds ago"] = "a casa de leilões respondeu vazia há %ds",
  ["AH value"] = "Valor no leilão",
  ["AH, cheapest version"] = "Leilão, versão mais barata",
  ["AUTO"] = "AUTO",
  ["AUTO · SCANNING"] = "AUTO · ESCANEANDO",
  ["AUTOMATION & ALERTS"] = "AUTOMAÇÃO E ALERTAS",
  ["AVOID"] = "EVITAR",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Acima dessa alta em 24 horas, o valor de mercado é tratado como um pico e é reduzido.",
  ["Above your price: quoted %s, your price %s"] = "Acima do seu preço: cotado %s, seu preço %s",
  ["Alert target"] = "Alvo do alerta",
  ["Alerts"] = "Alertas",
  ["All"] = "Todos",
  ["Archive this run"] = "Arquivar esta lista",
  ["Archived"] = "Arquivadas",
  ["Asks for a second click to confirm."] = "Pede um segundo clique para confirmar.",
  ["At a vendor"] = "No vendedor",
  ["At your pace you reach it at level %d."] = "No seu ritmo você chega lá no nível %d.",
  ["At your pace you will be %s short at level 40."] = "No seu ritmo vão faltar %s no nível 40.",
  ["At your price"] = "No seu preço",
  ["Auction House did not answer. Press Refresh"] =
    "A casa de leilões não respondeu. Clique em Refresh",
  ["Auction House is not open"] = "A casa de leilões não está aberta",
  ["Auto-scan on next AH visit"] = "Escaneamento automático na próxima visita à CL",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: mantém o Full Scan rodando sem parar e cede na hora quando você compra, procure você mesmo na casa de leilões, ou confira o correio. Clique para alternar.",
  ["Avoid"] = "Evitar",
  ["BOOKS %d/%d"] = "LIVROS %d/%d",
  ["BUY %d"] = "COMPRAR %d",
  ["BUY (unverified)"] = "COMPRAR (não verificado)",
  ["Background check"] = "Verificação em segundo plano",
  ["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."] =
    "A Blizzard ainda não publicou o custo de montaria. Digite /gc mount e o custo que você espera.",
  ["Blizzard's price: %s"] = "Preço da Blizzard: %s",
  ["Blizzard's price: %s · %d s left"] = "Preço da Blizzard: %s · faltam %d s",
  ["Bought"] = "Comprados",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "O ponto de equilíbrio é o menor preço que ainda cobre o seu custo depois da comissão. Vender abaixo dá prejuízo.",
  ["Bundled %s data"] = "Dados %s inclusos",
  ["Bundled data"] = "Dados inclusos",
  ["Buy"] = "Comprar",
  ["Buy it whole instead"] = "Comprar inteiro em vez disso",
  ["Buy less"] = "Compre menos",
  ["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"] = "Compras: %s · %d linhas · %d a comprar · %d no vendedor · gasto %s · falta ~%s",
  ["Buy: no run selected."] = "Compras: nenhuma lista escolhida.",
  ["CANCEL %d"] = "CANCELAR %d",
  ["CANCEL LOT?"] = "CANCELAR O LOTE?",
  ["CANCELLING…"] = "CANCELANDO…",
  ["CONFIRM"] = "CONFIRMAR",
  ["COST"] = "CUSTO",
  ["COST / UNIT"] = "CUSTO / UNIDADE",
  ["Can't price this"] = "Sem preço confiável",
  ["Cancel"] = "Cancelar",
  ["Cancel lot"] = "Cancelar",
  ["Cancel lot?"] = "Cancelar?",
  ["Cancel this lot and lose its deposit. Click again to confirm"] =
    "Cancelar este lote e perder o depósito. Clique de novo para confirmar",
  ["Cancel timed out"] = "O cancelamento expirou",
  ["Cancelling lot…"] = "Cancelando o lote…",
  ["Cancels this live auction. It does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Cancela este leilão ativo. Ele NÃO é reanunciado. O depósito é perdido e os itens voltam pelo correio; anuncie de novo a partir desta linha quando chegarem.",
  ["Cannot post this position"] = "Não dá para anunciar esta posição",
  ["Cannot remove this entry"] = "Não dá para apagar este registro",
  ["Cannot repost this lot"] = "Não dá para reanunciar este lote",
  ["Cap for %s"] = "Teto para %s",
  ["Cap: %d%%"] = "Teto: %d%%",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limitado pela velocidade real de venda, não pela sua bolsa.",
  ["Change the cap…"] = "Mudar o teto…",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Ainda há anúncios mais baratos, mas no ritmo deste item eles somem em horas.",
  ["Check"] = "Checar",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower (or refuse) if the market has moved since your last import."] =
    "O Check recalcula pelo livro de ofertas ao vivo antes de qualquer ouro sair, e ainda pode dar menos (ou recusar) se o mercado mudou desde a sua última importação.",
  ["Checked against the live order book a moment ago."] =
    "Verificado agora mesmo contra o livro de ofertas ao vivo.",
  ["Checked: %d of the top %d on screen"] = "Verificadas: %d das %d primeiras na tela",
  ["Checking prices…"] = "Verificando preços…",
  ["Checking prices: waiting for the Auction House…"] = "Verificando preços: esperando a casa de leilões…",
  ["Checking this item's price…"] = "Verificando o preço deste item…",
  ["Checking..."] = "Verificando...",
  ["Clear to buy"] = "Liberado para comprar",
  ["Click Confirm to post"] = "Clique em Confirm para anunciar",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Clicar de novo cancela o leilão ativo. Ele não é reanunciado: o depósito é perdido e os itens voltam pelo correio em vez de direto para as bolsas.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Clicar de novo apaga de vez este custo digitado à mão.",
  ["Close"] = "Fechar",
  ["Companion keeps prices fresh: /goldcap companion"] =
    "O Companion mantém os preços atualizados: /goldcap companion",
  ["Companion sync rejected:"] = "Sincronização do Companion recusada:",
  ["Confirm"] = "Confirmar",
  ["Confirm the cancel"] = "Confirmar o cancelamento",
  ["Confirm the removal"] = "Confirmar a remoção",
  ["Copy vendor list"] = "Copiar lista do vendedor",
  ["Cost per unit"] = "Custo por unidade",
  ["Cost unknown for %d of %d"] = "Custo desconhecido em %d de %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Custa mais do que o seu limite por compra permite.",
  ["Could not read that amount. Type it like 12g 50s."] = "Não foi possível ler esse valor. Digite assim: 12g 50s.",
  ["Don't skip"] = "Não pular",
  ["Everything here is bought"] = "Tudo aqui está comprado",
  ["From goldcap.gg: manage it there"] = "Do goldcap.gg: gerencie lá",
  ["From your scan %s ago. Counts only %s. Change with /gc weights."] =
    "Do seu escaneamento de %s atrás. Conta só %s. Mude com /gc weights.",
  ["Gear upgrades on the auction house"] = "Melhorias de equipamento na casa de leilões",
  ["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."] =
    "O GoldCap agora conta o que cai das criaturas que você saqueia, sem nomes, para as taxas de saque no goldcap.gg. O Companion vai compartilhar isso quando essa parte for lançada. Digite /gc loot off para parar.",
  ["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."] =
    "Itens nas suas bolsas que valem mais na casa de leilões do que no vendedor: %d (%s a mais).",
  ["Items still loading: %d. Open this again in a moment."] =
    "Itens ainda carregando: %d. Abra de novo em um instante.",
  ["Loot counting is off. Type /gc loot clear to remove what was recorded."] =
    "A contagem de saque está desligada. Digite /gc loot clear para remover o que foi registrado.",
  ["Loot counting is on."] = "A contagem de saque está ligada.",
  ["Loot record cleared."] = "Registro de saque removido.",
  ["Market"] = "Mercado",
  ["Mount cost cleared."] = "Custo da montaria apagado.",
  ["Mount cost set to %s."] = "Custo da montaria definido em %s.",
  ["No scan with gear in it yet. Open the auction house and let GoldCap scan it."] =
    "Ainda não há escaneamento com equipamento. Abra a casa de leilões e deixe o GoldCap escaneá-la.",
  ["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"] =
    "Ainda não há pesos de atributos para sua classe. Defina assim: /gc weights STR 1 STA 0.5",
  ["Nothing on the auction house beats what you wear at your level."] =
    "Nada na casa de leilões supera o que você usa no seu nível.",
  ["Nothing on this list matches."] = "Nada nesta lista corresponde.",
  ["Over cap"] = "Acima do teto",
  ["PRICE EACH"] = "PREÇO UNITÁRIO",
  ["Play a little longer for an estimate of your pace."] = "Jogue mais um pouco para estimar o seu ritmo.",
  ["RAISE CAP TO %s"] = "TETO PARA %s",
  ["RISK CHECKS"] = "CONTROLE DE RISCO",
  ["ROAD TO 40"] = "RUMO AO NÍVEL 40",
  ["Raise cap to %s"] = "Subir o teto para %s",
  ["Restore %s"] = "Restaurar %s",
  ["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."] =
    "Rumo ao nível 40 com o GoldCap: %s de %s para minha montaria (%d%%).",
  ["Road to 40: %s of %s (gold %s, bags %s)."] = "Rumo ao nível 40: %s de %s (ouro %s, bolsas %s).",
  ["Road to 40: you have %s (gold %s, bags %s)."] = "Rumo ao nível 40: você tem %s (ouro %s, bolsas %s).",
  ["Runs"] = "Listas",
  ["Set cap"] = "Definir teto",
  ["Skip"] = "Pular",
  ["Skip for now"] = "Pular por enquanto",
  ["Skipped"] = "Pulados",
  ["Split into reagents (craft %d×)"] = "Dividir em reagentes (fabricar %d×)",
  ["Stat weights: %s"] = "Pesos de atributos: %s",
  ["The rest is skipped for now"] = "O resto está pulado por enquanto",
  ["This client does not report item stats, so GoldCap cannot compare gear."] =
    "Este cliente não informa os atributos dos itens, então o GoldCap não consegue comparar equipamentos.",
  ["This lot holds more units than your Max units per buy."] =
    "Este lote tem mais unidades que o seu \"Máx. de unidades por compra\".",
  ["Could not find the queue's next lot to cancel. Try again"] =
    "Não achei o próximo lote da fila para cancelar. Tente de novo",
  ["DEFAULTS"] = "PADRÃO",
  ["DISC"] = "DESC",
  ["DISPLAY"] = "EXIBIÇÃO",
  ["DONE"] = "PRONTO",
  ["Default listing length for the Sell tab."] = "Duração padrão do anúncio na aba Vender.",
  ["Default: %s"] = "Padrão: %s",
  ["Deletes a hand-entered cost you typed into Set cost, never a purchase GoldCap itself captured or matched to your mail."] =
    "Apaga um custo digitado à mão em Definir custo, nunca uma compra que o GoldCap capturou ou casou com o seu correio.",
  ["Discount"] = "Desconto",
  ["Discount vs market value from your GoldCap import"] =
    "Desconto em relação ao valor de mercado da sua importação do GoldCap",
  ["Dump-trend cap %"] = "Limite de tendência de queda %",
  ["Duration"] = "Duração",
  ["Enlarge the window to see details"] = "Aumente a janela para ver os detalhes",
  ["Enter a whole quantity"] = "Digite uma quantidade inteira",
  ["Enter an exact positive cost"] = "Digite um custo exato e positivo",
  ["Entry price (avg fill)"] = "Preço de entrada (execução méd.)",
  ["Entry total"] = "Total de entrada",
  ["Everything else checks out. With more gold on this character, this is a buy."] = "Todo o resto confere. Com mais ouro neste personagem, seria uma compra.",
  ["FIFO allocations"] = "Alocações FIFO",
  ["Fetching a fresh price for this item. Press Post again in a moment"] =
    "Buscando um preço novo para este item. Clique em Post de novo daqui a pouco",
  ["Fetching a fresh price for this lot. Press Repost again in a moment"] =
    "Buscando um preço novo para este lote. Clique em Repost de novo daqui a pouco",
  ["Finish the pending post first"] = "Termine primeiro o anúncio pendente",
  ["Finish the pending post or repost first"] =
    "Termine primeiro o anúncio ou reanúncio pendente",
  ["Font scale"] = "Tamanho da fonte",
  ["Full pass over them: %.1fs"] = "Passagem completa: %.1fs",
  ["Full pass over them: measuring..."] = "Passagem completa: medindo...",
  ["Gold tied up"] = "Ouro parado",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "O GoldCap não consegue identificar qual pilha da bolsa é esta",
  ["GoldCap data age"] = "Idade dos dados GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "O GoldCap reconfere os %d linhas contra a casa de leilões ao vivo, a cada %d s. As linhas recusadas ficam ocultas. Comprar continua sendo sempre um clique seu.",
  ["GoldCap value"] = "Valor GoldCap",
  ["GoldCap: Import realm prices"] = "GoldCap: Importar preços do reino",
  ["GoldCap's"] = "do GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "A sugestão do GoldCap para este item e o preço que ele usaria.",
  ["GoldCap: %s. %s"] = "GoldCap: %s. %s",
  ["GoldCap: checked live. A deal, but you need %s on this character"] = "GoldCap: verificado ao vivo. É uma oferta, mas você precisa de %s neste personagem",
  ["GoldCap: checked live, safe to buy"] = "GoldCap: verificado ao vivo, pode comprar",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: ainda não verificado na casa de leilões ao vivo",
  ["Gone"] = "Sumiu",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Cinza significa que a cotação envelheceu; Post e Repost a atualizam antes de agir.",
  ["HIDDEN 0"] = "OCULTAS 0",
  ["HOLDING %d"] = "SEGURAR %d",
  ["Held back from cancelling"] = "Retido do cancelamento",
  ["Held back from the queue"] = "Retido da fila",
  ["How many hours of normal sales a wall under your exit may hold before the deal is refused."] =
    "Quantas horas de vendas normais uma parede abaixo do seu preço de saída pode aguentar antes de a oferta ser recusada.",
  ["ITEM"] = "ITEM",
  ["If it clears"] = "Se vender",
  ["Import"] = "Importar",
  ["Import failed:"] = "Falha na importação:",
  ["Import from goldcap.gg to arm the sniper"] = "Importe do goldcap.gg para ativar o sniper",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Instale o GoldCap Companion gratuito para manter os preços atualizados sozinho (/goldcap companion),",
  ["It is what you must beat to sell quickly, not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "É o preço que você precisa bater para vender rápido, não o que o item vale. Um vendedor com pressa pode colocá-lo bem abaixo do valor, e o GoldCap não vai segui-lo para baixo: veja WHAT TO DO para o preço em que ele anunciaria de fato.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Ele não vai inventar um custo a partir do preço de mercado, então o lucro fica desconhecido até você informar um.",
  ["Item"] = "Item",
  ["Item %d"] = "Item %d",
  ["Item level %d, below the %d your price is for"] =
    "Nível de item %d, abaixo do %d para o qual vale seu preço",
  ["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE. The buy is your call, and GoldCap only checks them while this board is open."] =
    "Items: equipamento, mascotes e receitas precificados contra a referência da região da sua importação. A velocidade de venda nunca é medida, então nunca ficam SEGURO. A compra é sua decisão, e o GoldCap só os verifica enquanto este painel está aberto.",
  ["LISTED"] = "ANUNCIADO",
  ["Language"] = "Idioma",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Idioma alterado. Digite /reload para aplicá-lo em tudo.",
  ["Last post may still go up. Wait a minute"] = "Ainda pode ser anunciado. Espere um minuto",
  ["Level 40 reached: %s to go."] = "Nível 40 alcançado: ainda faltam %s.",
  ["Last result: %ds ago"] = "Último resultado: há %ds",
  ["Last result: none yet this visit"] = "Último resultado: nenhum nesta visita",
  ["Listed"] = "Anunciados",
  ["Listed at %s, far below market. Repost."] =
    "Anunciado a %s, bem abaixo do mercado. Reanuncie.",
  ["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."] =
    "Anunciado no preço que você definiu no goldcap.gg ou abaixo. Se revende ou não, o julgamento é seu.",
  ["Listings"] = "Anúncios",
  ["Lists this item at the price on its row: the whole bag for a commodity, one stack for a regular item, or the number under HOW MANY."] =
    "Anuncia este item pelo preço da sua linha: a bolsa inteira para uma mercadoria, uma pilha para um item normal, ou o número em QUANTIDADE.",
  ["Live ask"] = "Preço ao vivo",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lote cancelado; espere ele voltar para as bolsas",
  ["MARKET"] = "MERCADO",
  ["MARKET / UNIT"] = "MERCADO / UNIDADE",
  ["MATCH"] = "IGUALAR",
  ["Market per unit"] = "Mercado por unidade",
  ["Market reference"] = "Referência de mercado",
  ["Max units per buy"] = "Máx. de unidades por compra",
  ["Max wallet per buy %"] = "Máx. do seu ouro por compra %",
  ["Min profit per buy (gold)"] = "Lucro mínimo por compra (ouro)",
  ["Min profit per buy (copper)"] = "Lucro mínimo por compra (cobre)",
  ["To buy"] = "A comprar",
  ["To craft"] = "A fabricar",
  ["Total: %s"] = "Total: %s",
  ["Unknown stat %s. Use one of: %s"] = "Atributo desconhecido %s. Use um destes: %s",
  ["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."] =
    "Melhorias para seu equipamento na casa de leilões: %d. Digite /gc upgrades para vê-las.",
  ["Use the default cap"] = "Usar o teto padrão",
  ["While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead."] = "Enquanto isso ficar no padrão de 5%, uma oportunidade a preço de vendedor pode usar até metade da sua carteira.",
  ["Min return per buy %"] = "Retorno mín. por compra %",
  ["Missing cost"] = "Custo faltando",
  ["NO LIVE PRICE YET"] = "AINDA SEM PREÇO AO VIVO",
  ["YOUR LISTS"] = "SUAS LISTAS",
  ["NOT ON HAND %d"] = "FORA DE MÃO %d",
  ["NOTHING TO CANCEL"] = "NADA PARA CANCELAR",
  ["Needs a live price check before it can be bought."] =
    "Precisa de uma verificação de preço ao vivo antes de poder ser comprado.",
  ["Needs gold"] = "Precisa de ouro",
  ["Never spend more than this share of your gold on one purchase."] =
    "Nunca gastar mais que essa fração do seu ouro em uma única compra.",
  ["No answer yet, listening for a minute"] = "Sem resposta ainda. Ouvindo por um minuto",
  ["No deals passed the safety checks right now."] =
    "Agora nenhuma oportunidade passou nas verificações de segurança.",
  ["No deals to show, and no realm prices yet."] =
    "Nenhuma oportunidade para mostrar, e ainda sem preços do reino.",
  ["No deals yet."] = "Ainda sem oportunidades.",
  ["No exact auction key"] = "Sem chave de leilão exata",
  ["No exact bag stack"] = "Sem pilha exata na bolsa",
  ["No exact bag variant"] = "Sem variante exata na bolsa",
  ["No live listings came back for this item."] = "Nenhum anúncio ativo voltou para este item.",
  ["No region reference for this item yet. Import again once goldcap.gg publishes one."] =
    "Ainda não há preço de referência da região para este item. Importe de novo quando o goldcap.gg publicar um.",
  ["No safe resale price could be worked out."] =
    "Não foi possível calcular um preço de revenda seguro.",
  ["No sales data for this item."] = "Sem dados de vendas para este item.",
  ["Not enough gold on this character to buy what GoldCap finds"] = "Ouro insuficiente neste personagem para comprar as ofertas",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Não há unidades suficientes na casa de leilões para essa quantidade.",
  ["Not in your bags or listed. Mail or bank?"] =
    "Nem nas bolsas nem anunciado. Correio ou banco?",
  ["Not on hand: the stock is in the mail, the bank, or on another character"] =
    "Não está à mão: o estoque está no correio, no banco ou em outro personagem",
  ["Not worth the deposit on the AH"] = "Não vale o depósito no leilão",
  ["Nothing is being held back."] = "Nada está sendo retido.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Depois desta compra não sobra nada contra o que vender, então não há preço de saída.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Nenhum anúncio alcança o nível de item em que o preço de referência foi medido.",
  ["Nothing listed on the AH right now"] = "Nada anunciado na casa de leilões agora",
  ["Nothing to sell"] = "Nada para vender",
  ["Nothing in your bags to list. Buy on the Deals tab or pick up your mail: anything you can sell shows up here with a price ready."] =
    "Não há nada nas suas bolsas para anunciar. Compre na aba Deals ou pegue sua correspondência: tudo o que você pode vender aparece aqui com um preço pronto.",
  ["No auctions up"] = "Nenhum leilão ativo",
  ["No live auctions on this character. What you post shows up here, with what to cancel and what to leave."] =
    "Este personagem não tem leilões ativos. O que você anunciar aparece aqui, com o que cancelar e o que deixar.",
  ["No match"] = "Nenhum resultado",
  ["Nothing on this deck matches that search. Clear the box to see everything."] =
    "Nada nesta aba corresponde a essa busca. Limpe o campo para ver tudo.",
  ["Still pricing"] = "Consultando preços",
  ["The auction house is still answering. Items show up here as their prices arrive."] =
    "A casa de leilões ainda está respondendo. Os itens aparecem aqui conforme os preços chegam.",
  ["Every cost is known"] = "Todos os custos conhecidos",
  ["Every item in your bags already has what you paid on record. Turn off NO COST to see them all."] =
    "Tudo nas suas bolsas já tem registrado quanto você pagou. Desative NO COST para ver tudo.",
  ["Nothing queued to cancel"] = "Nada na fila para cancelar",
  ["Nothing queued to post"] = "Nada na fila para anunciar",
  ["Nothing to remove"] = "Nada para apagar",
  ["ON THE AUCTION HOUSE"] = "NA CASA DE LEILÕES",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown: rescan anytime."] =
    "Uma varredura única de toda a casa de leilões por consultas paginadas. Leva cerca de 15 a 60 segundos em reinos movimentados. Sem recarga: varra de novo quando quiser.",
  ["Open the Auction House first."] = "Abra a casa de leilões primeiro.",
  ["Open the Auction House to begin scanning."] =
    "Abra a casa de leilões para começar a varredura.",
  ["Open the deals board. /gc for commands."] = "Abre o painel de oportunidades. /gc para os comandos.",
  ["POSTING"] = "PUBLICAÇÃO",
  ["POSTING…"] = "ANUNCIANDO…",
  ["PRICE"] = "PREÇO",
  ["PRICE ROSE %.1fx"] = "O PREÇO SUBIU %.1fx",
  ["PRICED TOO LOW %d"] = "BARATO DEMAIS %d",
  ["PRICING %d/%d"] = "PREÇOS %d/%d",
  ["PRICING…"] = "PREÇOS…",
  ["PROFIT"] = "LUCRO",
  ["PROFIT / UNIT"] = "LUCRO / UNIDADE",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Vincule ou atualize o GoldCap Companion para ver o lucro do goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Cole a string do seu reino do goldcap.gg e clique em Import.",
  ["Per-unit price of this auction"] = "Preço por unidade deste leilão",
  ["Play a sound when a checked deal turns SAFE."] = "Tocar um som quando uma oferta verificada fica SAFE.",
  ["Position scope changed"] = "O escopo da posição mudou",
  ["Post"] = "Anunciar",
  ["Post above the cheapest"] = "Anunciar acima do mais barato",
  ["Post confirmation expired"] = "A confirmação do anúncio expirou",
  ["Post the next queued item"] = "Anunciar o próximo item da fila",
  ["Posted"] = "Anunciado",
  ["Posting failed"] = "Falha ao anunciar",
  ["Posting unavailable"] = "Anúncio indisponível",
  ["Posting…"] = "Enviando…",
  ["Press Full Scan to find deals."] = "Clique em Full Scan para achar oportunidades.",
  ["Press Scan to search the whole auction house once, or Auto to keep scanning."] =
    "Clique em Scan para varrer a casa de leilões inteira uma vez, ou em Auto para varrer sem parar.",
  ["Previous removal selection cleared"] = "Seleção anterior de remoção descartada",
  ["Previous repost selection cleared"] = "Seleção anterior de reanúncio descartada",
  ["Price"] = "Preço",
  ["Priced from bundled sample data, not from your realm."] =
    "Preço vindo dos dados de amostra embutidos, não do seu reino.",
  ["Prices up to date"] = "Preços atualizados",
  ["Prices up to date · %d did not answer"] = "Preços atualizados · %d não responderam",
  ["Pricing %d/%d…"] = "Consultando preços %d/%d…",
  ["Pricing paused while you use the Auction House"] = "Consulta de preços pausada enquanto você usa a casa de leilões",
  ["Pricing…"] = "Cotando…",
  ["Profit"] = "Lucro",
  ["Profit per unit"] = "Lucro por unidade",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "O acompanhamento de lucro é um recurso do goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "As compras estão desligadas nesta versão.",
  ["Press Buy again to buy this quantity"] = "Pressione Comprar novamente para comprar esta quantidade",
  ["QTY"] = "QTD",
  ["Quantity exceeds missing units"] = "A quantidade passa das unidades que faltam",
  ["Quantity is capped by how fast this item actually sells."] =
    "A quantidade é limitada pela rapidez com que este item realmente vende.",
  ["REFRESH"] = "ATUALIZAR",
  ["RESET WINDOW"] = "REDEFINIR JANELA",
  ["Reason"] = "Motivo",
  ["Refresh"] = "Atualizar",
  ["Refresh waiting for prior result"] = "A atualização está esperando o resultado anterior",
  ["Refreshing listings…"] = "Atualizando os anúncios…",
  ["Refuse a buy when the price fell more than this in the last 24 hours: it may keep falling."] =
    "Recusar uma compra se o preço caiu mais que isso nas últimas 24 horas: ele pode continuar caindo.",
  ["Refused so far: %d"] = "Recusadas até agora: %d",
  ["Removal confirmation expired"] = "A confirmação de remoção expirou",
  ["Remove"] = "Apagar",
  ["Remove this cost"] = "Remover este custo",
  ["Remove?"] = "Apagar?",
  ["Removed"] = "Removido",
  ["Removed %d entries"] = "%d entradas removidas",
  ["Removes every entered-by-hand purchase in this run. Click again to confirm"] =
    "Apaga todas as compras digitadas à mão neste grupo. Clique de novo para confirmar",
  ["Removes this entered-by-hand purchase. Click again to confirm"] =
    "Apaga esta compra digitada à mão. Clique de novo para confirmar",
  ["Repost confirmation expired"] = "A confirmação de reanúncio expirou",
  ["Right-click to stop watching this item"] =
    "Clique com o botão direito para parar de acompanhar este item",
  ["Right-click to watch this item closely"] =
    "Clique com o botão direito para acompanhar este item de perto",
  ["SAFE +%s"] = "SEGURO +%s",
  ["SAFE = the live check approved this buy, at the profit shown"] =
    "SEGURO = a verificação ao vivo aprovou esta compra, com o lucro mostrado",
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SALVO NA HORA · ESC OU DONE PARA FECHAR",
  ["SCAN"] = "VARRER",
  ["SCANNING…"] = "VARRENDO…",
  ["SESSION %s%s · BUYS %d"] = "SESSÃO %s%s · COMPRAS %d",
  ["Sales are costed from your oldest units first"] =
    "As vendas são custeadas a partir das suas unidades mais antigas",
  ["Search"] = "Buscar",
  ["Sales evidence"] = "Dados de venda",
  ["Sell it on the AH"] = "Venda no leilão",
  ["Sell it on the AH (deposit not counted)"] = "Venda no leilão (depósito não contado)",
  ["Sell it to a vendor"] = "Venda a um vendedor",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "A aba Vender anuncia um degrau acima da oferta mais barata quando o livro mostra que ela vende na mesma velocidade.",
  ["Sell-through"] = "Taxa de venda",
  ["Sellers"] = "Vendedores",
  ["Sells too rarely: you would be holding it for a long time."] =
    "Vende raramente demais: você ficaria com ele por muito tempo.",
  ["Set cost"] = "Custo",
  ["Settings"] = "Configurações",
  ["Skip a buy unless it clears at least this much after the AH cut."] =
    "Ignorar uma compra se ela não render pelo menos esse valor após a taxa da Casa de Leilões.",
  ["Skip a buy unless the profit is at least this share of what you pay."] =
    "Ignorar uma compra se o lucro não for pelo menos essa fração do que você paga.",
  ["Snapshot value"] = "Valor do snapshot",
  ["Sold per day"] = "Vendas por dia",
  ["Sold/day"] = "Vendas/dia",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Ordene por ele para decidir o que verificar primeiro, não o que comprar.",
  ["Sound on SAFE deal"] = "Som em oferta SAFE",
  ["Source"] = "Fonte",
  ["Source age"] = "Idade da fonte",
  ["Spike-trend threshold %"] = "Limiar de alta repentina %",
  ["Start scanning as soon as the auction house opens."] =
    "Começar a escanear assim que a Casa de Leilões abrir.",
  ["Status"] = "Estado",
  ["Stop and open the buy window on your price"] = "Parar e abrir a janela de compra no seu preço",
  ["Stress exit unit"] = "Preço de saída sob pressão",
  ["Stress profit"] = "Lucro sob pressão",
  ["THE BOOK"] = "O LIVRO DE OFERTAS",
  ["TREND"] = "TENDÊNCIA",
  ["Tell GoldCap what you actually paid for these units."] =
    "Diga ao GoldCap quanto você realmente pagou por estas unidades.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "A casa de leilões não informou o depósito, então o custo é desconhecido.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "O Companion está sincronizando, mas este addon não conseguiu ler o que ele escreveu:",
  ["The auction house did not answer. Try again"] =
    "A casa de leilões não respondeu. Tente de novo",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "O painel classificou isto pelo snapshot importado. O livro ao vivo não confirma.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "O botão espera um instante antes de poder ser pressionado, então um duplo clique acidental nunca basta.",
  ["The cancel did not go through: the lot is still listed"] = "O cancelamento não foi concluído: o lote continua anunciado",
  ["The cheapest listing is no longer far enough under the reference price."] =
    "O anúncio mais barato já não está bem abaixo do preço de referência.",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "É o menor preço que OUTRA pessoa está pedindo agora, por uma consulta ao vivo à casa de leilões. Os seus próprios anúncios ficam de fora, então o número nunca persegue a si mesmo para baixo.",
  ["The data for this item is malformed, so GoldCap refuses to guess."] =
    "Os dados deste item estão malformados, então o GoldCap se recusa a adivinhar.",
  ["The liquidity data is not reliable enough to act on."] =
    "Os dados de liquidez não são confiáveis o bastante para agir.",
  ["The market value is an estimate, not a measurement."] =
    "O valor de mercado é uma estimativa, não uma medição.",
  ["The most units one purchase may take. How fast the item sells can still make it fewer."] =
    "O máximo que uma compra pode levar. A velocidade com que o item vende ainda pode reduzir isso.",
  ["The price data is over three hours old. Sync the Companion, then /reload. The addon only reads its data when the UI loads."] =
    "Os dados de preço têm mais de três horas. Sincronize o Companion e faça /reload. O addon só lê seus dados quando a interface carrega.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "O preço está conferido. A rapidez de venda não é medida em lugar nenhum, então o julgamento é seu.",
  ["The price is falling; buying into it is how you get stuck."] =
    "O preço está caindo; entrar nisso é como você fica preso.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "O preço é a última cotação, com no máximo 45 segundos. Se ele mudar antes de confirmar, o anúncio é abandonado em vez de enviado pelo preço antigo.",
  ["The price moved: part of this quote may be above your price"] =
    "O preço mudou: parte desta cotação pode estar acima do seu preço",
  ["The price moved and the trade is no longer safe."] =
    "O preço se moveu e a operação não é mais segura.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "O lucro não alcança o seu mínimo depois de pagas a comissão de 5 % e o depósito.",
  ["What this buy would make is under your minimum profit."] =
    "O que esta compra renderia está abaixo do seu lucro mínimo.",
  ["There is no undo. Clicking asks for a second click to confirm."] =
    "Não há como desfazer. O primeiro clique pede um segundo para confirmar.",
  ["This is a realm item, and GoldCap only verifies commodity prices."] =
    "Este é um item de reino, e o GoldCap só verifica preços de mercadorias.",
  ["Too few sellers to read a real price."] = "Vendedores de menos para ler um preço real.",
  ["Too little of what is listed actually sells."] =
    "Muito pouco do que está anunciado realmente vende.",
  ["Too little price history to trust the value."] =
    "Histórico de preços insuficiente para confiar no valor.",
  ["Total cost to buy this auction"] = "Custo total para comprar este leilão",
  ["Type a price in gold, or clear the box to use GoldCap's"] =
    "Digite um preço em ouro, ou limpe o campo para usar o do GoldCap",
  ["UNDERCUT"] = "ABAIXAR",
  ["UNDERCUT %d"] = "SUPERADOS %d",
  ["UNIT"] = "UNIDADE",
  ["Unit price"] = "Preço por unidade",
  ["Unknown"] = "Desconhecido",
  ["Unknown item"] = "Item desconhecido",
  ["Unknown means the cost side is incomplete. Fill it in with Set cost."] =
    "Desconhecido significa que falta parte do custo. Complete com Definir custo.",
  ["VERDICT"] = "VEREDITO",
  ["Verdict"] = "Veredito",
  ["WAITING FOR THE AUCTION HOUSE %d"] = "AGUARDANDO A CASA DE LEILÕES %d",
  ["WATCH"] = "OBSERVAR",
  ["WATCH (computed SAFE)"] = "WATCH (calculado SEGURO)",
  ["WATCH = the live check refused it. Hover the row for the reason"] =
    "OBSERVAR = a verificação ao vivo recusou. Passe o mouse na linha para ver o motivo",
  ["WHAT COUNTS AS A DEAL"] = "O QUE CONTA COMO OFERTA",
  ["WHAT TO DO"] = "O QUE FAZER",
  ["WHAT YOU PAID"] = "O QUE VOCÊ PAGOU",
  ["WHEN"] = "QUANDO",
  ["Waiting for Auction House…"] = "Esperando a casa de leilões…",
  ["Waiting for a live price"] = "Esperando um preço ao vivo",
  ["Waiting for the Auction House…"] = "Esperando a casa de leilões…",
  ["Waiting for the purchase to finish…"] = "Esperando a compra terminar…",
  ["Wall absorb window (hours)"] = "Janela de absorção da parede (horas)",
  ["Watching closely: %d item%s"] = "Acompanhando de perto: %d item%s",
  ["Watching: pinned, but not a deal right now"] =
    "Acompanhando: fixado, mas agora não é uma oportunidade",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Quanto uma unidade realmente lhe custou, na média das compras ainda em estoque.",
  ["What to do"] = "O que fazer",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "O que sobra numa unidade se ela vender pelo preço de mercado: preço de venda, menos os 5 % de comissão, menos o seu custo.",
  ["When a listing meets a price you set on the site, stop scanning and open its buy window."] =
    "Quando um anúncio atinge um preço que você definiu no site, o escaneamento para e a janela de compra é aberta.",
  ["Window position & size"] = "Posição e tamanho da janela",
  ["Won't buy"] = "Não vou comprar",
  ["Worst case back"] = "Retorno no pior caso",
  ["YOUR LOTS"] = "SEUS LOTES",
  ["YOUR PRICE"] = "SEU PREÇO",
  ["You can pay for it now."] = "Você já pode pagar.",
  ["You get"] = "Você recebe",
  ["You paid"] = "Você pagou",
  ["You pay"] = "Você paga",
  ["You would get"] = "Você receberia",
  ["You would pay"] = "Você pagaria",
  ["Your call"] = "Você decide",
  ["Your cap"] = "Seu teto",
  ["Your gold has not grown lately, so there is no pace to estimate."] =
    "Seu ouro não cresceu ultimamente, então não há ritmo para estimar.",
  ["Your minimum"] = "Seu mínimo",
  ["Your price"] = "Seu preço",
  ["a purchase landed that GoldCap could not attribute"] = "chegou uma compra que o GoldCap não conseguiu atribuir",
  ["a purchase landed that GoldCap could not price"] = "chegou uma compra cujo preço o GoldCap não sabe",
  ["a unit, at or under your price of %s"] = "por unidade, no seu preço de %s ou abaixo",
  ["a vendor sells it"] = "um vendedor vende",
  ["a vendor sells it for %s each"] = "um vendedor vende por %s cada",
  ["a vendor sells it for %s each · the auction house asks %s"] = "um vendedor vende por %s cada · a casa de leilões pede %s",
  ["alert group · %d hits"] = "grupo de alertas · %d achados",
  ["already in your bags and bank"] = "já nas suas bolsas e no banco",
  ["another purchase is in flight"] = "há outra compra em andamento",
  ["at a vendor"] = "no vendedor",
  ["at a vendor · %s each"] = "no vendedor · %s cada",
  ["at level %d"] = "no nível %d",
  ["bought"] = "comprado",
  ["bought %d for %s"] = "%d comprados por %s",
  ["buy %d of %d"] = "comprar %d de %d",
  ["buy %d of %d, have %d in bags and bank"] = "comprar %d de %d, você tem %d nas bolsas e no banco",
  ["buying..."] = "comprando...",
  ["cap: alert target"] = "teto: alvo do alerta",
  ["cheapest seen %s"] = "mais barato visto: %s",
  ["confirming..."] = "confirmando...",
  ["craft"] = "fabricar",
  ["craft it for %s each"] = "fabrique por %s cada",
  ["craft it for %s each · %s here"] = "fabrique por %s cada · aqui %s",
  ["craft it yourself"] = "fabrique você mesmo",
  ["craft it · %s each"] = "fabricar · %s cada",
  ["craft it: %s = %s each"] = "fabricar: %s = %s cada",
  ["deals %s · items %s · filtered %s"] = "oportunidades %s · itens %s · descartadas %s",
  ["done"] = "feito",
  ["from %s"] = "de %s",
  ["in bags %d · in bank %d"] = "nas bolsas %d · no banco %d",
  ["in bags %d · in bank %d · in the mailbox %d"] = "nas bolsas %d · no banco %d · na caixa de correio %d",
  ["includes %d for crafting %s"] = "inclui %d para fabricar %s",
  ["no answer. Check your mail"] = "sem resposta. Confira o correio",
  ["nothing at or under your cap of %s"] = "nada no seu teto de %s ou abaixo",
  ["nothing on offer"] = "nada à venda",
  ["on %s"] = "em %s",
  ["over your cap"] = "acima do teto",
  ["plan updated on goldcap.gg"] = "plano atualizado no goldcap.gg",
  ["price moved to %s"] = "o preço foi para %s",
  ["purchase failed. Try again"] = "a compra falhou. Tente de novo",
  ["right-click to skip or change the cap"] = "clique direito para pular ou mudar o teto",
  ["seen %s ago"] = "visto há %s",
  ["skipped for now"] = "pulado por enquanto",
  ["skipped for this session, it stays on the list"] = "pulado nesta sessão, continua na lista",
  ["still on the list: %d at a vendor · %d to craft"] = "ainda na lista: %d no vendedor · %d a fabricar",
  ["sure profit: a vendor pays %s each"] =
    "lucro garantido: um vendedor paga %s por unidade",
  ["resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown"] =
    "revenda pelo valor no leilão do escaneamento, %s cada, menos 5%% e depósito; velocidade incerta",
  ["Checked against the live auction house a moment ago."] =
    "Verificado na casa de leilões ao vivo há um instante.",
  ["above the cheapest, inside the cheap quarter · %s units ahead of you"] =
    "acima do mais barato, dentro do quarto barato · %s unidades à frente",
  ["above the cheapest, within the day's reach · %s units ahead of you"] =
    "acima do mais barato, dentro do alcance do dia · %s unidades à frente",
  ["against the region's own price for this item, after the 5% cut, if it sells"] =
    "em relação ao preço da região para este item, após a taxa de 5%, se vender",
  ["age %ss"] = "há %ss",
  ["another purchase took over: nothing was confirmed"] =
    "outra compra assumiu: nada foi confirmado",
  ["any figure here would be invented out of the very number being refused"] =
    "qualquer valor aqui seria inventado a partir do mesmo número que está sendo recusado",
  ["at or under your price. Click Buy to purchase"] =
    "no seu preço ou abaixo. Clique em Buy para comprar",
  ["auto off"] = "auto desligado",
  ["auto-synced %dh ago"] = "sincronizado automaticamente há %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "dados sincronizados de %s carregados (%s de idade)",
  ["auto-synced data stale: /goldcap import"] =
    "os dados sincronizados estão velhos: /goldcap import",
  ["auto: paused"] = "auto: pausado",
  ["below the %s breakeven"] = "abaixo do ponto de equilíbrio de %s",
  ["below the %s you paid"] = "abaixo dos %s que você pagou",
  ["big buy"] = "compra grande",
  ["bought %d"] = "comprados %d",
  ["bought %d x %s"] = "comprados %d x %s",
  ["bought %d after AH close"] = "comprados %d depois que a casa de leilões fechou",
  ["buying commodity..."] = "comprando mercadoria...",
  ["cheapest not yours %s"] = "o mais barato que não é seu %s",
  ["checking live price..."] = "verificando o preço ao vivo...",
  ["checking live safety..."] = "verificando a segurança ao vivo...",
  ["clears in ~%dd"] = "esgota em ~%d d",
  ["clears in ~%dh"] = "esgota em ~%d h",
  ["commodity purchase failed"] = "a compra da mercadoria falhou",
  ["confirmed commodity purchase failed after AH close"] =
    "a compra confirmada de mercadoria falhou depois que a casa de leilões fechou",
  ["confirming purchase..."] = "confirmando a compra...",
  ["cost basis incomplete. Set costs to get repost advice"] =
    "base de custo incompleta. Defina os custos para receber conselho de reanúncio",
  ["crafted %s"] = "fabricado %s",
  ["due, will be asked next pass"] = "pendente, será consultado na próxima passagem",
  ["fair"] = "razoáveis",
  ["far below market"] = "bem abaixo do mercado",
  ["finish the pending buy first"] = "termine primeiro a compra pendente",
  ["first in line"] = "primeiro da fila",
  ["Costs %s. With your %d%% per-buy limit you need %s on this character."] = "Custa %s. Com o seu limite por compra de %d%% você precisa de %s neste personagem.",
  ["fresh"] = "recente",
  ["full scan already in progress"] = "a varredura completa já está em andamento",
  ["full scan interrupted. Confirm your purchase"] =
    "varredura completa interrompida. Confirme sua compra",
  ["full scan stalled. Press Full Scan to retry"] =
    "a varredura completa travou. Clique em Full Scan para tentar de novo",
  ["full scan stalled, retrying shortly"] = "a varredura completa travou, nova tentativa em breve",
  ["full scan stopped. Press %s to run it again"] =
    "varredura completa interrompida. Clique em %s para rodá-la de novo",
  ["gone / price changed"] = "sumiu / preço mudou",
  ["goldcap.gg prices for WoW: Forever are not out yet."] =
    "Os preços do goldcap.gg para WoW: Forever ainda não estão disponíveis.",
  ["strong"] = "sólidos",
  ["hold"] = "segurar",
  ["identity unresolved (variant item, not priced by design)"] =
    "identidade não resolvida (item com variantes, sem preço de propósito)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "se você comprar todas as %d e revendê-las pelo preço que está ali agora",
  ["ilvl %d"] = "nv. %d",
  ["import %dh old"] = "importação de %dh atrás",
  ["import stale: /goldcap import or /goldcap companion"] =
    "importação velha: /goldcap import ou /goldcap companion",
  ["imported %d items for %s (%s). Prices are live now."] =
    "importados %d itens para %s (%s). Os preços já estão valendo.",
  ["in the mail"] = "no correio",
  ["in the mail, the bank or on another character"] = "no correio, no banco ou em outro personagem",
  ["is what this market absorbs. Past that you are buying stock you will sit on"] =
    "é o que este mercado absorve. Além disso você compra estoque que vai ficar parado",
  ["item %d"] = "item %d",
  ["%s: %s"] = "%s: %s",
  ["item level %d+"] = "nível de item %d+",
  ["item variant unresolved"] = "variante do item não resolvida",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h: %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "últimas 24 h: %d vendas, %s bruto, %s de taxa, %d compras, %s gastos",
  ["last live price %s ago"] = "último preço ao vivo, há %s",
  ["leave these alone"] = "deixe estes como estão",
  ["level %d"] = "nível %d",
  ["listing gone: already bought out or price changed"] =
    "o anúncio sumiu: já foi comprado ou o preço mudou",
  ["listing gone: bought out or repriced"] = "o leilão sumiu: comprado ou reprecificado",
  ["live safety confirmed. Click Buy to purchase"] =
    "segurança confirmada ao vivo. Clique em Buy para comprar",
  ["live verification required"] = "é preciso verificação ao vivo",
  ["the cheapest is %s, your cap is %s"] = "o mais barato: %s, seu teto: %s",
  ["the run changed. Start again"] = "a lista mudou. Comece de novo",
  ["took too long. Try again"] = "demorou demais. Tente de novo",
  ["usually cheapest around %s · %d%%"] = "costuma ser mais barato por volta das %s · %d%%",
  ["vendor"] = "vendedor",
  ["vs %s at the auction house · right-click to buy it whole"] = "contra %s na casa de leilões · clique direito para comprar inteiro",
  ["vs %s at the auction house · right-click to split"] = "contra %s na casa de leilões · clique direito para dividir",
  ["weak"] = "fracos",
  ["manual import. Companion keeps this fresh: /goldcap companion"] =
    "importação manual. O Companion mantém isso atualizado: /goldcap companion",
  ["market %s"] = "mercado %s",
  ["needs %s"] = "exige %s",
  ["needs a fresh price. Press Refresh"] = "precisa de um preço novo. Clique em Refresh",
  ["no confirmation from the server. The buy may still have gone through, check your mail. Closing this will not undo it."] =
    "sem confirmação do servidor. A compra ainda pode ter passado, confira seu correio. Fechar isto não desfaz.",
  ["no cost"] = "sem custo",
  ["no cost for %d"] = "sem custo para %d",
  ["no live price yet"] = "ainda sem preço ao vivo",
  ["no live price"] = "sem preço ao vivo",
  ["no live quote yet, pricing…"] = "ainda sem cotação ao vivo, precificando…",
  ["no market figure for caged pets"] = "sem dado de mercado para mascotes engaioladas",
  ["no market figure for this item level"] = "sem dado de mercado para este nível de item",
  ["Makes %s"] = "Cria %s",
  ["no prices yet: /goldcap companion or /goldcap import"] =
    "ainda sem preços: /goldcap companion ou /goldcap import",
  ["no purchase confirmation received. Cancel and retry"] =
    "nenhuma confirmação de compra recebida. Clique em Cancel e tente de novo",
  ["no sales recorded yet. Open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "nenhuma venda registrada ainda. Abra sua caixa de correio com o GoldCap carregado e elas serão lidas das faturas",
  ["no stock in bags or listed, nothing to price for"] =
    "sem estoque nas bolsas e nada anunciado, nada para precificar",
  ["none"] = "nenhum",
  ["not enough gold: total %s, you have %s"] = "ouro insuficiente: total %s, você tem %s",
  ["not enough gold for this quote. Cancel"] = "ouro insuficiente para esta cotação. Cancel",
  ["not enough gold on this character: you need %s"] = "ouro insuficiente neste personagem: você precisa de %s",
  ["not enough units left for that quantity, re-checking what remains..."] =
    "não restam unidades suficientes para essa quantidade. Verificando de novo o que resta...",
  ["not priced: nothing on hand to sell"] = "sem preço: nada em mãos para vender",
  ["not ready to cancel"] = "ainda não dá para cancelar",
  ["not ready to post"] = "ainda não dá para anunciar",
  ["nothing listed"] = "nada anunciado",
  ["of %d"] = "de %d",
  ["off"] = "desativado",
  ["oldest units sell first"] = "as unidades mais antigas vendem primeiro",
  ["on"] = "ativado",
  ["open the auction house once so GoldCap can tell how these sell"] =
    "abra a casa de leilões uma vez para o GoldCap saber como estes vendem",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "ou cole uma string do goldcap.gg com /goldcap import.",
  ["paid sale unresolved"] = "venda paga não resolvida",
  ["placing bid..."] = "dando o lance...",
  ["previous commodity purchase settled. %s to re-check the price"] =
    "compra de mercadoria anterior liquidada. Clique em %s para conferir o preço de novo",
  ["price changed after you closed the buy window: nothing was bought"] =
    "o preço mudou depois que você fechou a janela de compra: nada foi comprado",
  ["price checked, sale speed unknown. This one is your call"] =
    "preço conferido, velocidade de venda desconhecida. Essa é sua decisão",
  ["price confirmed. Click Buy to purchase"] = "preço confirmado. Clique em Buy para comprar",
  ["price rose %.1fx, still safe. Confirm"] = "o preço subiu %.1fx, ainda seguro. Confirme",
  ["price stands %d of %d"] = "seu preço: %d de %d",
  ["prices loaded are %s (%s) but you are playing in %s, so every discount and profit figure is measured against another market"] =
    "os preços carregados são de %s (%s) mas você joga em %s, então todo desconto e lucro é medido contra outro mercado",
  ["purchase canceled"] = "compra cancelada",
  ["purchase complete"] = "compra concluída",
  ["purchase identity unresolved"] = "identidade da compra não resolvida",
  ["purchase pending exact cost"] = "compra esperando o custo exato",
  ["purchase total unavailable. Check your mail"] =
    "não dá para obter o total da compra. Confira a caixa de correio",
  ["quote %s. Click Confirm to buy"] = "cotação %s. Clique em Confirm para comprar",
  ["quote %ss ago"] = "cotação de %ss atrás",
  ["quote expired. Refresh to re-check the price"] =
    "cotação expirada. Clique em Refresh para conferir o preço de novo",
  ["quote expires in %d s. Click Confirm to buy"] =
    "a cotação expira em %d s. Clique em Confirm para comprar",
  ["re-checking what remains at a safe price..."] =
    "verificando de novo o que resta a um preço seguro...",
  ["realm item, sale speed unverified · region reference %s (ilvl %d)"] =
    "item de reino, velocidade de venda não verificada · referência da região %s (nível %d)",
  ["recent sales (newest first):"] = "vendas recentes (mais novas primeiro):",
  ["region %s · bundled: %d items (%s), imported: %s"] =
    "região %s · inclusos: %d itens (%s), importados: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "região corrigida em %d registros; %d vendas reassociadas ao seu estoque",
  ["relisting now would lock in a loss or a stall. Hold"] =
    "reanunciar agora travaria um prejuízo ou uma parada. Segure",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "apagados %d registros de compra duplicados deixados por uma falha na leitura do correio",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "apagados %d registros de venda duplicados deixados por uma falha na leitura do correio",
  ["sale name ambiguous"] = "nome da venda ambíguo",
  ["sale proceeds pending"] = "receita da venda pendente",
  ["scanned %d listings over %d passes"] = "varridos %d anúncios em %d passagens",
  ["scanning auction house..."] = "varrendo a casa de leilões...",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "vende %s/dia",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "sessão: %d capturas, %s gastos, ~%s de lucro est.",
  ["sniped (listing changed on rescan)"] = "levaram na frente (o anúncio mudou na nova varredura)",
  ["sniped for "] = "arrematado por ",
  ["stack not identified"] = "pilha não identificada",
  ["starting full scan..."] = "iniciando a varredura completa...",
  ["stopped watching %s"] = "parei de acompanhar %s",
  ["the Companion wrote prices this addon could not read:"] =
    "o Companion escreveu preços que este addon não conseguiu ler:",
  ["the auction house has not sent details for these yet"] =
    "a casa de leilões ainda não enviou os detalhes",
  ["the import failed (%s)"] = "a importação falhou (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "para escoar %d unidades a %s vendas por dia, com %s parado esse tempo todo",
  ["unavailable"] = "indisponível",
  ["under GoldCap's own floor of %s"] = "abaixo do piso do GoldCap, %s",
  ["unknown evidence"] = "evidência desconhecida",
  ["waiting for previous commodity purchase to settle"] =
    "esperando a compra de mercadoria anterior ser liquidada",
  ["waiting for previous search result to settle"] = "esperando o resultado da busca anterior",
  ["waiting..."] = "aguarde...",
  ["wall"] = "muro",
  ["wall %s at %s: price under it to sell first"] =
    "muro de %s a %s: anuncie abaixo dele para vender antes",
  ["wall %s at %s above you"] = "muro de %s a %s acima de você",
  ["watching %s closely, re-checked every few seconds"] =
    "acompanhando %s de perto, reconferido a cada poucos segundos",
  ["worst case, selling all %d back into the price standing there now"] =
    "no pior caso, revendendo todas as %d pelo preço que está ali agora",
  ["worth cancelling"] = "vale cancelar",
  ["would sell at a loss"] = "venderia com prejuízo",
  ["you have enough gold for this now. Check again"] = "agora você tem ouro suficiente. Clique em Check para verificar de novo",
  ["you haven't imported realm prices yet. Install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "você ainda não importou os preços do reino. Instale o GoldCap Companion (/goldcap companion) ou cole uma string do goldcap.gg (/goldcap import).",
  ["you take %d"] = "você leva %d",
  ["your game client has no font for this language, so the text will show as empty boxes"] =
    "seu cliente do jogo não tem fonte para este idioma, então o texto aparecerá como quadrados vazios",
  ["your import is %d hours old and prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "sua importação tem %d horas e os preços podem estar errados. Cole uma string nova do goldcap.gg (/goldcap import).",
  ["your price is above every level shown"] = "seu preço supera todos os níveis",
  ["your scan, %s ago"] = "sua varredura, há %s",
  ["yours"] = "seu",
  ["yours ×%s"] = "seus ×%s",
  ["~%dd to reach you"] = "~%d d até a sua vez",
  ["~%dh to reach you"] = "~%d h até a sua vez",
  ["×%d in bags"] = "×%d nas bolsas",
  ["×%d in your bags · Post lists %d of them, the largest stack"] =
    "×%d nas suas bolsas · o Post anuncia %d deles, a maior pilha",
  ["×%d in your bags · no stack GoldCap can identify exactly"] =
    "×%d nas suas bolsas · nenhuma pilha que o GoldCap consiga identificar com exatidão",
  ["×%d in your bags, ready to list"] = "×%d nas suas bolsas, prontos para anunciar",
  ["×%d listed"] = "×%d anunciados",
  ["×%d listed at %s each"] = "×%d anunciados a %s cada",
  ["×%d%s · bought %s · %s · %s"] = "×%d%s · comprado %s · %s · %s",
  ["×%d%s · made %s · %s"] = "×%d%s · fabricado %s · %s",
  ["- = nothing is checking this row right now"] = "- = nada está verificando esta linha agora",
  ["… = a live check is queued for this row"] =
    "… = há uma verificação ao vivo na fila para esta linha",
  ["no answer %ds ago, resting"] = "sem resposta há %ds, em pausa",
  ["the last attempt is still settling, checking the price again..."] =
    "a última tentativa ainda está sendo concluída. Verificando o preço de novo...",
  ["Listed at or under the price you set on goldcap.gg (group: %s)"] =
    "Anunciado no preço que você definiu no goldcap.gg ou abaixo (grupo: %s)",
  ["AUTO · PAUSED: BUY WINDOW"] = "AUTO · PAUSADO: JANELA DE COMPRA",
  ["Paused while a buy window is open. Buy or close it and Auto carries on."] =
    "Pausado enquanto uma janela de compra está aberta. Compre ou feche-a e o Auto continua.",
  ["AUTO · PAUSED: YOUR SEARCH"] = "AUTO · PAUSADO: SUA BUSCA",
  ["Paused while you type in the auction house search box. It carries on a few seconds after you leave it."] =
    "Pausado enquanto você digita na busca da casa de leilões. Continua alguns segundos depois que você sai dela.",
  ["AUTO · PAUSED: MAILBOX OPEN"] = "AUTO · PAUSADO: CORREIO ABERTO",
  ["AUTO · PAUSED: OTHER TAB"] = "AUTO · PAUSADO: OUTRA ABA",
  ["Paused while another auction house tab is open: Sell, Auctions, or another addon's, such as Auctionator's Selling. A scan would replace what that tab shows. Click Buy or the GoldCap tab at the bottom of the auction house and Auto carries on."] =
    "Pausado enquanto outra aba da casa de leilões está aberta: Vender, Leilões ou a de outro addon, como Selling do Auctionator. Uma varredura substituiria o que essa aba mostra. Clique em Comprar ou na aba GoldCap embaixo na casa de leilões e o Auto continua.",
  ["Scan starts when you leave that tab: click Buy or GoldCap"] =
    "A varredura começa quando você sai dessa aba: Comprar ou GoldCap",
  ["Paused while the mailbox is open. Close it and Auto carries on."] =
    "Pausado enquanto a caixa de correio está aberta. Feche-a e o Auto continua.",
  ["AUTO · PAUSED: SELL TAB"] = "AUTO · PAUSADO: ABA VENDER",
  ["Paused while the Sell tab is open: it prices your bags through the same search. Go back to Deals and Auto carries on."] =
    "Pausado enquanto a aba Vender está aberta: ela precifica suas bolsas pela mesma busca. Volte às ofertas e o Auto continua.",
  ["AUTO · PAUSED: ITEMS BOARD"] = "AUTO · PAUSADO: LISTA DE ITENS",
  ["Paused while the Items board is shown: it asks the auction house through the same search. Switch to Commodities and Auto carries on."] =
    "Pausado enquanto a lista de itens está à mostra: ela consulta a casa de leilões pela mesma busca. Mude para Mercadorias e o Auto continua.",
  ["AUTO · PAUSED: BUY TAB"] = "AUTO · PAUSADO: ABA BUY",
  ["Paused while the BUY tab is open: it looks up prices through the same search. Go back to Deals and Auto carries on."] =
    "Pausado enquanto a aba BUY está aberta: ela consulta preços pela mesma busca. Volte às ofertas e o Auto continua.",
  ["AUTO · WAITING FOR YOU"] = "AUTO · ESPERANDO VOCÊ",
  ["Waiting while you post, buy or browse on the auction house's own panes. It starts as soon as you stop."] =
    "Espera enquanto você anuncia, compra ou navega nos painéis da casa de leilões. Começa assim que você parar.",
  ["AUTO · WAITING: YOUR LIST"] = "AUTO · ESPERA: SUA LISTA",
  ["Waiting: your own search is on the auction house's Buy list, and a scan would replace it. Open GoldCap's auction house tab, or close the auction house, and Auto starts."] =
    "Espera: sua própria busca está na lista de compra da casa de leilões, e uma varredura a substituiria. Abra a aba do GoldCap na casa de leilões, ou feche a casa de leilões, e o Auto começa.",
  ["Market %s · unverified until a live Check"] =
    "Mercado %s · não verificado até uma checagem ao vivo",
  ["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"] =
    "dados do mercado inteiro: %d mercadorias, %d com dados de venda, %d itens do reino (idade %s, %d KB)",
  ["whole-market data not in use: %s"] = "dados do mercado inteiro fora de uso: %s",
  ["it is %s old, and the prices you imported are newer"] =
    "eles têm %s de idade e os preços que você importou são mais recentes",
  ["it is for another region than the prices loaded"] = "eles são de outra região que não a dos preços carregados",
  ["its date cannot be right. Check this computer's clock"] =
    "a data deles não pode estar certa. Confira o relógio deste computador",
  ["it was set aside when other prices were loaded this session. /reload to use it again"] =
    "eles foram deixados de lado quando outros preços foram carregados nesta sessão. /reload para usá-los de novo",
  ["On the AH now"] = "No leilão",
  ["%s listed · %d min ago"] = "%s anunciados · há %d min",
  ["%s listed · just now"] = "%s anunciados · agora mesmo",
  ["it could not be read (%s)"] = "não foi possível lê-los (%s)",
  ["it is for a region this build of GoldCap does not know. Update the addon"] =
    "eles são de uma região que esta versão do GoldCap não conhece. Atualize o addon",
  ["it is in a format this build of GoldCap cannot read. Update the addon"] =
    "eles estão num formato que esta versão do GoldCap não consegue ler. Atualize o addon",
  ["it is larger than this build of GoldCap can read. Update the addon"] =
    "eles são maiores do que esta versão do GoldCap consegue ler. Atualize o addon",
  ["the Companion wrote an empty copy. Let it sync, then /reload"] =
    "o Companion os gravou vazios. Deixe-o sincronizar e faça /reload",
  ["the Companion wrote it with no prices. Let it sync, then /reload"] =
    "o Companion os gravou sem preços. Deixe-o sincronizar e faça /reload",
  ["Scanning the auction house…"] = "Varrendo a casa de leilões…",
  ["%s lots scanned and saved"] = "%s lotes varridos e salvos",
  ["%s items scanned and saved"] = "%s itens varridos e salvos",
  ["The full scan is cooling down (%d min left). Scanning by browsing instead"] =
    "A varredura completa está em recarga (%d min restantes). Varrendo por navegação enquanto isso",
  ["The auction house did not answer the full scan. Scanning by browsing instead"] =
    "A casa de leilões não respondeu à varredura completa. Varrendo por navegação em vez disso",
  ["reading the auction house: %s of %s lots"] = "lendo a casa de leilões: %s de %s lotes",
  ["The scan found nothing to save"] = "A varredura não encontrou nada para salvar",
  ["Scans the whole auction house for prices: a full list at most once every 15 minutes, browsing in between. GoldCap also scans when you open the auction house."] =
    "Varre toda a casa de leilões em busca de preços: uma lista completa no máximo a cada 15 minutos, navegando enquanto isso. O GoldCap também varre quando você abre a casa de leilões.",
  -- Core/ForeverValue.lua's PrintBags/BagTotals and Core/PostQueue.lua's below_vendor: the
  -- POST queue holding back what a vendor pays at least as much for.
  ["Your bags: %s at a vendor, %s on the AH after its cut"] =
    "Suas bolsas: %s a um vendedor, %s na CdL após a taxa",
  ["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."] =
    "O botão ANUNCIAR da aba Vender lista tudo que vale mais do que um vendedor paga, um clique por vez.",
  ["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."] =
    "Suas bolsas: %s a um vendedor. Escaneie a casa de leilões para ver quanto renderiam lá.",
  ["a vendor pays more: sell it there"] =
    "um vendedor paga mais: venda lá",
  ["vendor pays more"] =
    "vendedor paga mais",
  ["Below vendor"] =
    "Abaixo NPC",
  ["Under market"] =
    "Sob mercado",
  [" · buy at %s or less, vendor pays %s"] =
    " · compre a %s ou menos, vendedor paga %s",
  [" · buy at %s or less, AH value %s"] =
    " · compre a %s ou menos, valor no leilão %s",
  ["Buy at or under %s: a vendor pays %s each. This buy makes %s."] =
    "Compre a %s ou menos: um vendedor paga %s cada. Esta compra rende %s.",
  ["Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit."] =
    "Compre a %s ou menos: o valor no leilão, o que pede o décimo mais barato das unidades anunciadas, é %s. A velocidade de revenda é desconhecida, o que torna isso mais arriscado que um negócio com o vendedor. Esta compra rende cerca de %s após a taxa de 5%% e o depósito.",
  ["under the vendor price. Click Buy to purchase"] =
    "abaixo do preço do vendedor. Clique em Buy para comprar",
  ["far under the market, resale speed unknown. Click Buy to purchase"] =
    "bem abaixo do mercado, velocidade de revenda desconhecida. Clique em Buy para comprar",
  ["No deals in your last scan."] =
    "Nenhuma oferta no seu último escaneamento.",
  ["Deals appear as soon as the scan finds them."] =
    "As ofertas aparecem assim que a varredura as encontrar.",
  ["GoldCap looks for items listed cheaper than they are worth. SCAN looks again."] =
    "O GoldCap procura itens anunciados mais baratos do que valem. VARRER escaneia de novo.",
  ["No scan of this auction house yet."] =
    "Ainda nenhum escaneamento desta casa de leilões.",
  ["GoldCap scans when you open the auction house; SCAN on this board scans again."] =
    "O GoldCap escaneia quando você abre a casa de leilões; VARRER neste painel escaneia de novo.",
  ["In WoW: Forever, GoldCap's prices come from your own auction house scans."] =
    "No WoW: Forever, os preços do GoldCap vêm dos seus próprios escaneamentos da casa de leilões.",
  ["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."] =
    "Abra a casa de leilões e o GoldCap escaneia para você; VARRER na aba Ofertas escaneia de novo.",
  ["%ds"] = "%d s",
  ["%dm"] = "%d min",
  ["%dh"] = "%d h",
  ["%dd"] = "%d d",
  -- WoW: Forever crowd prices (UI/Tooltip.lua, plan 3d).
  ["1 scanner, %s ago"] = "1 scanner, há %s",
  ["%d scanners, %s ago"] = "%d scanners, há %s",
  ["resale at the AH value of players' scans, %s each, after the 5%% cut and deposit; speed unknown"] = "revenda pelo valor no leilão dos escaneamentos dos jogadores, %s cada, menos 5%% e depósito; velocidade incerta",
  ["Shared with goldcap.gg on your next /reload"] = "Compartilhado com o goldcap.gg no seu próximo /reload",
  ["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."] = "Seus escaneamentos ficam neste computador. O GoldCap Companion os compartilha com o goldcap.gg e traz de volta os preços de todos.",
  ["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."] = "O GoldCap Companion compartilha seus escaneamentos com o goldcap.gg após cada /reload e traz de volta os preços de todos.",
  ["You opened %s: its first %s prices are yours."] =
    "Você abriu %s: os primeiros %s preços são seus.",
  ["Your scan updated %s prices on %s. %s of them nobody else had in the last 24 hours."] =
    "Seu escaneamento atualizou %s preços em %s. %s deles ninguém mais tinha nas últimas 24 horas.",
  ["Your scan updated %s prices on %s."] =
    "Seu escaneamento atualizou %s preços em %s.",
  -- Sold tab: tiles, period chips, search, day groups and the sale tooltip.
  ["%d DAYS"] = "%d DIAS",
  ["TODAY"] = "HOJE",
  ["YESTERDAY"] = "ONTEM",
  ["SUN"] = "DOM",
  ["MON"] = "SEG",
  ["TUE"] = "TER",
  ["WED"] = "QUA",
  ["THU"] = "QUI",
  ["FRI"] = "SEX",
  ["SAT"] = "SÁB",
  ["YOU GOT"] = "RECEBIDO",
  ["YOU GOT · %s"] = "RECEBIDO · %s",
  ["EACH"] = "UNIDADE",
  ["%d sales · after the AH cut"] = "%d vendas · após a taxa",
  ["1 sale · after the AH cut"] = "1 venda · após a taxa",
  ["%d here · all on goldcap.gg"] = "%d aqui · todas no goldcap.gg",
  ["cost known for %d of %d"] = "custo conhecido em %d de %d",
  ["%s of %s"] = "%s de %s",
  ["%s · gold %s, bags %s"] = "%s · ouro %s, bolsas %s",
  ["set the riding cost: %s"] = "defina o custo da montaria: %s",
  ["GOLDCAP.GG · %d DAYS"] = "GOLDCAP.GG · %d DIAS",
  ["profit · synced %s ago"] = "lucro · sincronizado há %s",
  ["after the AH cut · synced %s ago"] = "após a taxa · sincronizado há %s",
  ["BEST SALE"] = "MELHOR VENDA",
  ["%s profit"] = "%s de lucro",
  ["no sale with a known profit yet"] = "ainda nenhuma venda com lucro conhecido",
  ["OPEN SELL"] = "ABRIR SELL",
  ["Find an item"] = "Buscar um item",
  ["JUST SOLD"] = "RECÉM-VENDIDO",
  ["reaches goldcap.gg on /reload or logout"] = "chega ao goldcap.gg com /reload ou ao sair",
  ["ON GOLDCAP.GG"] = "NO GOLDCAP.GG",
  ["latest %d of %d · the rest on goldcap.gg"] = "últimas %d de %d · o resto no goldcap.gg",
  ["last %d days"] = "últimos %d dias",
  ["%d sales · %s"] = "%d vendas · %s",
  ["1 sale · %s"] = "1 venda · %s",
  ["sold today at %s · %d × %s"] = "vendido hoje às %s · %d × %s",
  ["sold %s at %s · %d × %s"] = "vendido em %s às %s · %d × %s",
  ["sold, the money is in your mail · %d × %s"] = "vendido, o dinheiro está no correio · %d × %s",
  ["Sale price"] = "Preço de venda",
  ["Auction house cut"] = "Taxa da CdL",
  ["Auction house cut, 5%"] = "Taxa da CdL, 5%",
  ["You got"] = "Você recebeu",
  ["You paid (%s)"] = "Você pagou (%s)",
  ["%s each"] = "%s cada",
  ["Sniper"] = "Sniper",
  ["BUY list"] = "lista do BUY",
  ["set by you"] = "informado por você",
  ["the auction house"] = "a casa de leilões",
  ["crafted"] = "fabricado",
  ["The profit is worked out once the money arrives."] = "O lucro é calculado quando o dinheiro chegar.",
  ["GoldCap never saw this bought, so there is no profit to show. Set what it cost you in SELL."] =
    "O GoldCap nunca viu esta compra, então não há lucro para mostrar. Informe quanto custou em SELL.",
  ["Market now %s · you sold %d%% above it"] = "Mercado agora %s · você vendeu %d%% acima",
  ["Market now %s · you sold %d%% under it"] = "Mercado agora %s · você vendeu %d%% abaixo",
  ["Market now %s · you sold at it"] = "Mercado agora %s · você vendeu pelo mesmo preço",
  ["Your sales show up here once you open a mailbox with GoldCap loaded."] =
    "Suas vendas aparecem aqui quando você abrir uma caixa de correio com o GoldCap carregado.",
  ["List something in SELL first."] = "Primeiro anuncie algo em SELL.",
  ["No sales match “%s” today."] = "Nenhuma venda corresponde a “%s” hoje.",
  ["No sales match “%s” in these %d days."] = "Nenhuma venda corresponde a “%s” nestes %d dias.",
  ["No sales today."] = "Nenhuma venda hoje.",
  ["No sales in these %d days."] = "Nenhuma venda nestes %d dias.",
  ["SEARCH 30 DAYS"] = "BUSCAR EM 30 DIAS",
  ["SHOW 30 DAYS"] = "VER 30 DIAS",
  ["▲%d%% over the alert target"] = "▲%d%% acima do alvo do alerta",
  ["▲%d%% over usual"] = "▲%d%% acima do normal",
  ["▲%d%% over your cap"] = "▲%d%% acima do seu teto",
  -- The quest reward mark (UI/QuestRewardMark.lua).
  ["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."] =
    "GoldCap: a recompensa na moldura dourada é a que vale mais na casa de leilões (%s).",
  -- The vendor note (UI/MerchantNote.lua).
  ["1 item in your bags fetches more on the auction house (+%s). Keep it for the AH."] =
    "1 item nas suas bolsas vale mais na casa de leilões (+%s). Guarde-o para o leilão.",
  ["%d items in your bags fetch more on the auction house (+%s). Keep them for the AH."] =
    "%d itens nas suas bolsas valem mais na casa de leilões (+%s). Guarde-os para o leilão.",
  -- BUY 2.0 week 2: a gear line is bought one lot per press (UI/BuyFrame.lua).
  ["BUY ONE · %s"] = "COMPRAR UM · %s",
  ["not enough gold"] = "ouro insuficiente",
  ["set a cap first"] = "defina um teto primeiro",
  -- BUY 2.0 week 2: a gear line's lots on the dock (UI/BuyFrame.lua).
  ["%s · %d lots"] = "%s · %d lotes",
  ["%s · 1 lot"] = "%s · 1 lote",
  ["%s · over your cap"] = "%s · acima do seu teto",
  ["no cap for this item. Right-click the line to set one"] =
    "este item não tem teto. Clique com o botão direito na linha para definir um",
  -- BUY 2.0 week 2: the vendor panel beside the merchant (UI/BuyVendorPanel.lua).
  ["BUY %d · %s"] = "COMPRAR %d · %s",
  ["BUY · %s"] = "COMPRAR · %s",
  -- BUY 2.0: the item box and the quick list (UI/BuyFrame.lua).
  ["Could not find that item. Shift-click it, or type its item id."] =
    "Item não encontrado. Shift+clique nele ou digite o ID dele.",
  ["Item to add"] = "Item a adicionar",
  ["Make a list once, buy it here at or under your price."] =
    "Monte uma lista uma vez e compre aqui pelo seu preço ou menos.",
  ["Remove from the list"] = "Tirar da lista",
  ["or plan a whole profession on goldcap.gg"] = "ou planeje uma profissão inteira no goldcap.gg",
  -- BUY 2.0: the item box's hint, with the x count (UI/BuyFrame.lua).
  -- Glyphs every face that draws them has (spec/client_text_spec.lua's glyph inventory).
  ["HIDE DETAILS ▲"] = "OCULTAR DETALHES ▲",
  ["SHOW DETAILS ▼"] = "MOSTRAR DETALHES ▼",
  ["plan updated on goldcap.gg · +%d -%d lines"] =
    "plano atualizado no goldcap.gg · +%d -%d linhas",
  ["~ goldcap.gg market value, no live quote yet"] =
    "~ valor de mercado do goldcap.gg, ainda sem cotação ao vivo",
  ["→ needs price"] = "→ falta preço",
  -- BUY 2.0: lists made in the game -- New, Import, Export, Rename, favourites, order, Delete
  ["Items the game has not loaded yet are left out: %d. Export again in a moment."] =
    "O jogo ainda não carregou %d itens, que ficaram de fora. Exporte de novo daqui a pouco.",
  ["%s and %d more"] = "%s e mais %d",
  ["+ New"] = "+ Nova",
  ["Add to favourites"] = "Adicionar aos favoritos",
  ["Added %d items to %s."] = "%d itens adicionados a %s.",
  ["Added %d× %s to %s."] = "%d× %s adicionado a %s.",
  ["Added %d× %s to a new list, %s."] = "%d× %s adicionado a uma nova lista, %s.",
  ["Copy as a TSM item list"] = "Copiar como lista de itens do TSM",
  ["Copy for Auctionator"] = "Copiar para o Auctionator",
  ["Delete"] = "Excluir",
  ["Delete %s? This cannot be undone."] = "Excluir %s? Isso não pode ser desfeito.",
  ["Delete this list…"] = "Excluir esta lista…",
  ["Export"] = "Exportar",
  ["From goldcap.gg: rename or remove it there"] = "Do goldcap.gg: renomeie ou remova lá",
  ["GoldCap: Import a list"] = "GoldCap: Importar uma lista",
  ["Import a list…"] = "Importar uma lista…",
  ["One list per subgroup"] = "Uma lista por subgrupo",
  ["Import into this list…"] = "Importar para esta lista…",
  ["Imported %s with %d items."] = "%s importada com %d itens.",
  ["List %d"] = "Lista %d",
  ["Lists come from goldcap.gg through the companion, or make one here with + New."] =
    "As listas vêm do goldcap.gg pelo Companion, ou crie uma aqui com + Nova.",
  ["Lists: click to switch, make, import or export one"] =
    "Listas: clique para trocar, criar, importar ou exportar uma",
  ["Move down"] = "Mover para baixo",
  ["Move up"] = "Mover para cima",
  ["Name this list"] = "Nome da lista",
  ["New list"] = "Nova lista",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import."] =
    "Cole uma lista do goldcap.gg, TSM ou Auctionator e clique em Importar.",
  ["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."] =
    "Cole uma lista do goldcap.gg, TSM ou Auctionator e clique em Importar. Os itens dela vão para %s.",
  ["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."] =
    "Pressione Ctrl+C para copiar e depois importe na guia Comprar do Auctionator.",
  ["Press Ctrl+C to copy, then import it into a TSM group."] =
    "Pressione Ctrl+C para copiar e depois importe em um grupo do TSM.",
  ["Remove from favourites"] = "Remover dos favoritos",
  ["Rename…"] = "Renomear…",
  ["Save"] = "Salvar",
  ["The game could not tell which items these are: %s. Shift-click them into the item box instead."] =
    "O jogo não conseguiu identificar estes itens: %s. Em vez disso, use Shift+clique para colocá-los na caixa de itens.",
  ["There are no items in this list."] = "Esta lista não tem itens.",
  ["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."] =
    "Esta é a exportação compactada de grupo do TSM, que só o TSM consegue abrir. Cole em goldcap.gg/list, clique lá em “Copiar como grupo do TSM” e cole o resultado aqui.",
  ["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."] =
    "O GoldCap não consegue ler esta lista. Cole uma lista do goldcap.gg, TSM ou Auctionator.",
  ["in game"] = "no jogo",
  -- Buy runs: the import result and the vendor list, now that the BUY tab's lists use them.
  ["The run's vendor reagents. Press Ctrl+C to copy the list."] =
    "Os reagentes de vendedor da lista. Pressione Ctrl+C para copiar a lista.",
  ["Vendor list"] = "Lista do vendedor",
  ["run imported: %s (%d lines)"] = "lista importada: %s (%d linhas)",
  ["the run string is not valid"] = "o texto da lista não é válido",
  -- BUY: a gear line's tooltip names the lot it buys next (UI/BuyFrame.lua).
  ["next to buy: %s"] = "próxima compra: %s",
  -- BUY: the item box at the top -- several items at once, typed names, recents (UI/BuyAddBox.lua).
  ["Add"] = "Adicionar",
  ["Added %d items to a new list, %s."] = "%d itens adicionados a uma nova lista, %s.",
  ["Clear"] = "Limpar",
  ["Could not read: %s."] = "Não foi possível ler: %s.",
  ["Items to add: %d (%s)"] = "A adicionar: %d (%s)",
  ["Recent:"] = "Recentes:",
  ["Shift-click items, type a name, or an item id with x and a count: 2589 x20."] =
    "Shift+clique em itens, digite um nome ou um ID de item com x e a quantidade: 2589 x20.",
  -- BUY search: what is on sale, the results, opening one and adding it to a list (UI/BuySearch.lua).
  ["AVAILABLE"] = "DISPONÍVEIS",
  ["Back to %s"] = "Voltar para %s",
  ["Click to buy it here. Right-click to add it to a list."] =
    "Clique para comprar aqui. Clique com o botão direito para adicionar a uma lista.",
  ["Close search"] = "Fechar busca",
  ["How many"] = "Quantos",
  ["Loading more results…"] = "Carregando mais resultados…",
  ["More results"] = "Mais resultados",
  ["Nothing on sale for “%s”."] = "Nada à venda para “%s”.",
  ["On sale for “%s”: %d"] = "À venda para “%s”: %d",
  ["Open the auction house to search what's on sale."] =
    "Abra a casa de leilões para buscar o que está à venda.",
  ["PRICE FROM"] = "A PARTIR DE",
  ["Search again"] = "Buscar de novo",
  ["Searching the auction house for “%s”…"] = "Buscando “%s” na casa de leilões…",
  ["The auction house did not answer. Search again."] =
    "A casa de leilões não respondeu. Busque de novo.",
  ["Waiting for the auction house…"] = "Esperando a casa de leilões…",
  -- Craft costs: which reagent had no price and why, and the merchant as a source of cost
  -- (Core/CraftCapture.lua, Core/VendorBuys.lua).
  ["this recipe turns one input into several different items (prospecting, crushing, milling), so it is not costed"] =
    "esta receita transforma um ingrediente em vários itens diferentes (prospecção, trituração, moagem), então ela não tem custo",
  ["%s ×%d: no purchase of it found, here or on your other characters"] =
    "%s ×%d: nenhuma compra encontrada, nem aqui nem nos seus outros personagens",
  ["%s ×%d: only %d of them were bought, the rest has no price"] =
    "%s ×%d: só %d deles foram comprados, o resto não tem preço",
  ["%s ×%d: made by prospecting, crushing or milling, not bought"] =
    "%s ×%d: obtido por prospecção, trituração ou moagem, não comprado",
  ["%s ×%d: bought as different variants, so which one was used is unclear"] =
    "%s ×%d: comprado em variantes diferentes, então não está claro qual foi usada",
  ["%s: %d at the vendor price, %s each"] =
    "%s: %d pelo preço do vendedor, %s cada",
  ["%s: priced from another character's purchases"] =
    "%s: avaliado pelas compras de outro personagem",
  ["%s: %d at the market price, %s each"] =
    "%s: %d ao preço de mercado, %s cada",
  ["Part of this cost is an estimate: reagents you did not buy are counted at their current auction house price"] =
    "Parte deste custo é uma estimativa: os reagentes que você não comprou são contados pelo preço atual na casa de leilões",
  ["Vendor"] =
    "Vendedor",
  ["SELLING %d"] = "VENDENDO %d",
  ["NOT SELLING %d"] = "NÃO VENDENDO %d",
  ["POST lists these"] = "ANUNCIAR anuncia estes",
  ["click one to post it"] = "clique em um para anunciar",
  ["Selling"] = "Vendendo",
  ["Not selling"] = "Não vendendo",
  ["POST lists it, and so does the key for posting the next item."] = "ANUNCIAR anuncia este item, assim como a tecla para anunciar o próximo.",
  ["POST passes it by. Click the item to post it from the bar below."] = "ANUNCIAR pula este item. Clique no item para anunciá-lo pela barra abaixo.",
  ["Marked for you: you bought it on DEALS."] = "Marcado para você: você comprou em DEALS.",
  ["Click to change."] = "Clique para mudar.",
  ["Done for this visit"] = "Feito nesta visita",
  ["POST passes it by until you close the auction house. Click to have POST list it again."] =
    "ANUNCIAR pula este item até você fechar a casa de leilões. Clique para que ANUNCIAR volte a anunciá-lo.",
  ["Mark what to sell with the circle"] = "Marque com o círculo o que quer vender",
  ["PROCEEDS"] = "RECEITA",
  ["What everything POST lists brings in if it sells at these prices, after the auction house's 5% cut."] = "Quanto rende tudo o que ANUNCIAR anuncia se vender a estes preços, depois da taxa de 5% da casa de leilões.",
  ["What your lots bring in if they all sell, after the auction house's 5% cut."] = "Quanto rendem seus leilões se todos venderem, depois da taxa de 5% da casa de leilões.",
  ["PROCEEDS less what you paid for this stock. Shown only while GoldCap knows what you paid for all of it."] = "RECEITA menos o que você pagou por este estoque. Só aparece enquanto o GoldCap sabe quanto você pagou por tudo.",
  ["HOW MANY"] = "QUANTIDADE",
  ["MAX"] = "MÁX.",
  ["skipped"] = "pulado",
  ["posted"] = "anunciado",
  ["POST"] = "ANUNCIAR",
  ["SKIP"] = "PULAR",
  ["then %s"] = "depois %s",
  ["need %d"] = "precisa %d",
  ["need %d · have %d"] = "precisa %d · tem %d",
  ["cap %s"] = "teto %s",
  ["no cap"] = "sem teto",
  ["%s under your cap"] = "%s abaixo do teto",
  ["at your cap"] = "bem no teto",
  ["for %d"] = "por %d",
  ["goes into %s"] = "para %s",
  ["market price"] = "preço de mercado",
  ["craft %d× (%d per craft)"] = "fabricar %d× (%d por fabricação)",
  ["%s spent"] = "%s gasto",
  ["No list yet"] = "Ainda sem lista",
  ["Add to %s"] = "Adicionar a %s",
  ["Add to a new list"] = "Adicionar a uma nova lista",
  ["Add %d to a list"] = "Adicionar %d a uma lista",
  ["Checking %d gear, pets and recipes…"] = "Verificando equipamentos, mascotes e receitas (%d)…",
  ["Deals appear here as the auction house answers."] = "As ofertas aparecem aqui conforme a casa de leilões responde.",
  ["checking items %d of %d"] = "verificando itens %d de %d",
  ["deals %s · watching %d items"] = "oportunidades %s · vigiando %d itens",
  ["Flips"] = "Revenda",
  ["Rare finds"] = "Achados raros",
  ["No flips on this realm right now"] = "Nada para revender neste reino agora",
  ["No rare finds on this realm right now"] = "Nenhum achado raro neste reino agora",
  ["Nothing here you lack"] = "Aqui não falta nada para você",
  ["Only what I lack"] = "Só o que me falta",
  ["Shows only what your account has not collected yet: appearances, pets, toys and mounts, and recipes this character does not know."] =
    "Mostra só o que sua conta ainda não coletou: aparências, mascotes, brinquedos e montarias, e receitas que este personagem não conhece.",
  ["Ctrl-click to try it on"] = "Ctrl+clique para provar",
  ["Not collected"] = "Não coletado",
  ["Not known by this character"] = "Este personagem não conhece",
  ["Appearance known"] = "Aparência conhecida",
  ["Cheapest of %d realms"] = "O mais barato de %d reinos",
  ["Among the cheapest 10%% of %d realms"] = "Entre os 10%% mais baratos de %d reinos",
  ["Cheaper than 3 in 4 of %d realms"] = "Mais barato que 3 de cada 4 de %d reinos",
  ["Sold %d times in 30 days"] = "Vendido %d vezes em 30 dias",
  ["Sold once in 30 days"] = "Vendido uma vez em 30 dias",
  ["last for %s %s"] = "a última por %s %s",
  ["%d days ago"] = "há %d dias",
  ["1 day ago"] = "há 1 dia",
  ["%d hours ago"] = "há %d horas",
  ["1 hour ago"] = "há 1 hora",
  ["less than an hour ago"] = "há menos de uma hora",
  ["No sale seen in 30 days"] = "Nenhuma venda vista em 30 dias",
  ["Sold %d times in 7 days on %d realms"] = "Vendido %d vezes em 7 dias em %d reinos",
  ["Rare find: seldom sold, so GoldCap puts no price on it"] =
    "Achado raro: vende pouco, então o GoldCap não dá preço a ele",
  -- The welcome window (UI/WelcomeFrame.lua): what GoldCap does, the state of the prices, GoldCap Companion.
  ["Welcome to GoldCap"] = "Boas-vindas ao GoldCap",
  ["Your GoldCap prices"] = "Seus preços do GoldCap",
  ["GoldCap puts its prices in item tooltips. At the auction house, the GoldCap tab has:"] =
    "O GoldCap mostra os preços dele no tooltip dos itens. Na casa de leilões, a aba GoldCap tem:",
  ["Finds items listed below what they usually sell for, and checks each one before you buy."] =
    "Encontra itens anunciados abaixo do que costumam vender e confere cada um antes de você comprar.",
  ["Finds items listed below what a vendor pays, or far below their usual price."] =
    "Encontra itens anunciados abaixo do que um vendedor paga, ou muito abaixo do preço habitual.",
  ["Prices everything in your bags. POST lists it, one item per click."] =
    "Dá preço a tudo que está nas suas bolsas. ANUNCIAR anuncia, um item por clique.",
  ["What you sold, and the profit on each sale where GoldCap knows what you paid."] =
    "O que você vendeu e o lucro de cada venda cujo preço de compra o GoldCap conhece.",
  ["Shopping lists for crafting: buys each item up to the price you set."] =
    "Listas de compras para profissões: compra cada item até o preço que você definir.",
  ["No prices for your region yet"] = "Ainda não há preços para a sua região",
  ["Only the prices GoldCap came with, from %s ago"] = "Só os preços que vieram com o GoldCap, de %s atrás",
  ["Fresh prices from the Companion, %s ago"] = "Preços recentes do Companion, há %s",
  ["The Companion last sent prices %s ago"] = "O Companion enviou preços pela última vez há %s",
  ["You pasted these prices %s ago"] = "Você colou estes preços há %s",
  ["The Companion's prices could not be read"] = "Não foi possível ler os preços do Companion",
  ["Everyone's prices are in, from %s ago"] = "Os preços de todos os jogadores chegaram, de %s atrás",
  ["No prices from other players for this auction house yet"] =
    "Ainda não há preços de outros jogadores para esta casa de leilões",
  ["Nobody has shared a scan of this auction house for %s"] =
    "Ninguém compartilha uma varredura desta casa de leilões há %s",
  ["Prices from your own scans only"] = "Preços só das suas próprias varreduras",
  ["These prices came with GoldCap and change only when GoldCap itself updates. DEALS needs fresh prices from your realm to find anything, so until then it finds no deals."] =
    "Estes preços vieram com o GoldCap e só mudam quando o próprio GoldCap é atualizado. O DEALS precisa de preços recentes do seu reino para achar algo, então até lá ele não encontra nenhuma oferta.",
  ["GoldCap came with no prices for your region, so DEALS finds no deals until GoldCap Companion brings them."] =
    "O GoldCap não veio com preços para a sua região, então o DEALS não encontra ofertas até o GoldCap Companion trazê-los.",
  ["New prices reach GoldCap every time you log in or type /reload."] =
    "Preços novos chegam ao GoldCap sempre que você entra no jogo ou digita /reload.",
  ["DEALS and every price go by what it sent last. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."] =
    "O DEALS e todos os preços seguem o que foi enviado por último. Confira se o GoldCap Companion está em execução (o ícone fica ao lado do relógio) e digite /reload.",
  ["A pasted string goes stale within a day. GoldCap Companion fetches fresh prices for you every 30 minutes."] =
    "Um texto colado fica desatualizado em um dia. O GoldCap Companion busca preços recentes para você a cada 30 minutos.",
  ["With prices this old, DEALS can show deals that are no longer there. GoldCap Companion fetches fresh prices for you every 30 minutes."] =
    "Com preços tão antigos, o DEALS pode mostrar ofertas que não existem mais. O GoldCap Companion busca preços recentes para você a cada 30 minutos.",
  ["GoldCap could not read what the Companion wrote (%s). Update GoldCap and GoldCap Companion, then type /reload."] =
    "O GoldCap não conseguiu ler o que o Companion gravou (%s). Atualize o GoldCap e o GoldCap Companion e digite /reload.",
  ["Your own scans and every other GoldCap player's are combined: for each item, the newer price wins."] =
    "Suas próprias varreduras e as de todos os outros jogadores do GoldCap são combinadas: para cada item, vale o preço mais recente.",
  ["Your own scans still work. Check that GoldCap Companion is running (its icon sits next to the clock), then type /reload."] =
    "Suas próprias varreduras continuam funcionando. Confira se o GoldCap Companion está em execução (o ícone fica ao lado do relógio) e digite /reload.",
  ["Your own scans work meanwhile. If GoldCap Companion is not running, start it and type /reload."] =
    "Enquanto isso, suas próprias varreduras funcionam. Se o GoldCap Companion não estiver em execução, abra-o e digite /reload.",
  ["GoldCap Companion is running and brings every scan of this auction house that GoldCap players share, but none has come in lately. Your own scans still work."] =
    "O GoldCap Companion está em execução e traz cada varredura desta casa de leilões que os jogadores do GoldCap compartilham, mas nenhuma chegou recentemente. Suas próprias varreduras continuam funcionando.",
  ["GoldCap knows only what your own scans of this auction house found. With GoldCap Companion you also get the scans of every GoldCap player here: more items with a price, and newer prices."] =
    "O GoldCap só conhece o que as suas próprias varreduras desta casa de leilões encontraram. Com o GoldCap Companion você também recebe as varreduras de todos os jogadores do GoldCap daqui: mais itens com preço e preços mais recentes.",
  ["Get GoldCap Companion"] = "Baixar o GoldCap Companion",
  ["A small free app for Windows, macOS and Linux. It fetches your realm's prices every 30 minutes, with no account needed. Its code is open on GitHub."] =
    "Um app pequeno e gratuito para Windows, macOS e Linux. Ele busca os preços do seu reino a cada 30 minutos, sem precisar de conta. O código é aberto no GitHub.",
  ["A small free app for Windows, macOS and Linux. Every 30 minutes it brings the prices every GoldCap player scanned on your auction house, with no account needed. Its code is open on GitHub."] =
    "Um app pequeno e gratuito para Windows, macOS e Linux. A cada 30 minutos ele traz os preços que cada jogador do GoldCap varreu na sua casa de leilões, sem precisar de conta. O código é aberto no GitHub.",
  ["1. Copy this link (%s) and open it in your browser:"] = "1. Copie este link (%s) e abra no navegador:",
  ["2. Install GoldCap Companion and start it."] = "2. Instale o GoldCap Companion e abra-o.",
  ["3. Back in the game, type /reload."] = "3. De volta ao jogo, digite /reload.",
  ["Not installed on this computer? It is here:"] = "Não está instalado neste computador? Ele está aqui:",
  ["The latest version is here:"] = "A versão mais recente está aqui:",
  ["/gc companion opens this window again."] = "/gc companion abre esta janela de novo.",
  ["Got it"] = "Entendi",
  ["Don't remind me"] = "Não lembrar mais",
  ["sells within a day"] = "vende em menos de um dia",
  ["sells in about 1 day"] = "vende em cerca de 1 dia",
  ["sells in about %d days"] = "vende em cerca de %d dias",
  ["Sell here for %s, %s"] = "Venda aqui por %s, %s",
  ["Sell on %s for %s, %s"] = "Venda em %s por %s, %s",
  ["Pays more on %s, where you have no character: %s, %s"] = "Paga mais em %s, onde você não tem personagem: %s, %s",
  ["Among the 5 cheapest of %d realms"] = "Entre os 5 mais baratos de %d reinos",
  ["The price is checked against what this sold for across the region. Where it sells best is below."] = "O preço foi conferido com o que isso vendeu na região. Onde vende melhor está abaixo.",
  ["Sell on"] = "Vender em",
  ["Cheapest realms"] = "Reinos baratos",
  ["Better on"] = "Melhor em",
  ["under a day"] = "menos de um dia",
  ["about 1 day"] = "cerca de 1 dia",
  ["about %d days"] = "cerca de %d dias",
  ["top 5 of %d"] = "top 5 de %d",
  ["this realm"] = "este reino",
  ["Put in the Warband Bank"] = "Guardar no banco do bando de guerra",
  ["Take out to sell here"] = "Retirar para vender aqui",
  ["Can't be sold"] = "Não pode ser vendido",
  ["Warbound until equipped: the auction house refuses it"] = "Vinculado ao bando de guerra até ser equipado: a casa de leilões recusa",
  ["here: %s, %s"] = "aqui: %s, %s",
  ["for %s: %s, %s"] = "para %s: %s, %s",
  ["Then log in a character on that realm and open a bank: GoldCap lists what to take out."] = "Depois entre com um personagem daquele reino e abra um banco: o GoldCap mostra o que retirar.",
  ["Then list it from GoldCap's Sell tab at the auction house."] = "Depois anuncie pela aba Vender do GoldCap na casa de leilões.",
  ["At a bank: which flips to put in the Warband Bank for another of your realms, and which to take out and sell here. /gc route lists them anywhere."] = "No banco: quais revendas guardar no banco do bando de guerra para outro dos seus reinos e quais retirar e vender aqui. /gc route mostra em qualquer lugar.",
  ["Where each flip sells comes with the Companion's region data: nothing to go on yet."] = "Onde cada revenda vende vem com os dados de região do Companion: ainda não há nada.",
  ["Nothing in your bags sells notably better on another of your realms."] = "Nada nas suas bolsas vende bem melhor em outro dos seus reinos.",
  ["What to take out of the Warband Bank shows at a bank."] = "O que retirar do banco do bando de guerra aparece num banco.",
  -- Followed groups: the DEALS chip and its tooltip.
  ["GROUP"] = "GRUPO",
  ["Listed at or under the deal price of a group you follow (%s)"] = "Anunciado no preço de oferta de um grupo que você segue ou abaixo (%s)",
  -- Followed groups: a group's selling rule in words (Core/GroupRules.lua).
  ["1 at a time"] = "1 por vez",
  ["all you have"] = "tudo o que você tem",
  ["%d h"] = "%d h",
  ["not under %d%% of usual"] = "não abaixo de %d%% do preço habitual",
  ["not under the cost to craft"] = "não abaixo do custo de fabricação",
  ["%d%% cheaper each time it comes back"] = "%d%% mais barato cada vez que volta",
  -- Followed groups: SELL's row, its mark and the dock.
  ["Group you follow: %s"] = "Grupo que você segue: %s",
  ["Marked for you: it is in a group you follow."] = "Marcado para você: está em um grupo que você segue.",
  ["under group floor"] = "abaixo do piso do grupo",
  ["the market is under your group's floor. Type a price to post anyway"] = "o mercado está abaixo do piso do seu grupo. Digite um preço para anunciar mesmo assim",
  -- Followed groups: cancel by a group's floor, and the cancel threshold.
  ["Min. undercut to cancel (%)"] = "Diferença mín. para cancelar (%)",
  ["Cancel only when someone undercuts you by more than this percent. At 0 any undercut counts. Lots far below their value are always queued."] = "Cancela só quando alguém anuncia abaixo de você por mais que esta porcentagem. Em 0, qualquer diferença conta. Lotes muito abaixo do valor sempre entram na fila.",
  ["small undercut"] = "diferença pequena",
  ["relisting would go under your group's floor. Hold"] = "reanunciar ficaria abaixo do piso do seu grupo. Segure",
  ["undercut by less than your cancel setting. Hold"] = "diferença menor que sua configuração de cancelamento. Segure",
  -- the cancel run (groups in the addon, task 13)
  ["Cancel %d lots? You lose %s in deposits. One press per lot, CONFIRM first."] = "Cancelar %d lotes? Você perde %s em depósitos. Um clique por lote, primeiro em CONFIRMAR.",
  ["Cancel %d lots? One press per lot, CONFIRM first."] = "Cancelar %d lotes? Um clique por lote, primeiro em CONFIRMAR.",
  ["Cancel 1 lot? You lose its %s deposit. Press CONFIRM."] = "Cancelar 1 lote? Você perde o depósito de %s. Clique em CONFIRMAR.",
  ["Cancel 1 lot? Press CONFIRM."] = "Cancelar 1 lote? Clique em CONFIRMAR.",
  ["CANCEL NEXT (%d)"] = "CANCELAR PRÓXIMO (%d)",
  ["Press again to cancel the next lot"] = "Clique de novo para cancelar o próximo lote",
  ["Stopped: 20 seconds without a press"] = "Parado: 20 segundos sem clicar",
  ["Collected %s from %d sales"] = "Coletado: %s de %d vendas",
  ["Collected %s from 1 sale"] = "Coletado: %s de 1 venda",
  ["%d lots came back"] = "%d lotes voltaram",
  ["1 lot came back"] = "1 lote voltou",
  ["%d purchases"] = "%d compras",
  ["1 purchase"] = "1 compra",
  ["%d other mails"] = "%d outros correios",
  ["1 other mail"] = "1 outro correio",
  ["%d still loading"] = "%d ainda carregando",
  ["The bags are full, the rest stays in the mailbox"] = "As bolsas estão cheias, o resto fica na caixa de correio",
  ["Nothing to collect"] = "Nada para coletar",
  ["MAIL"] = "CORREIO",
  ["Sales"] = "Vendas",
  ["Returned lots"] = "Lotes devolvidos",
  ["Purchases"] = "Compras",
  ["Player mail"] = "Correio de jogadores",
  ["Take the gold from sold auctions."] = "Coleta o ouro dos leilões vendidos.",
  ["Take back lots that expired or that you cancelled."] = "Recupera os lotes que expiraram ou que você cancelou.",
  ["Take the items of auctions you won, and the refund of an outbid bid."] = "Coleta os itens dos leilões que você ganhou e o reembolso de um lance superado.",
  ["Take gold and items other players sent you. Cash on delivery mail is never taken."] = "Coleta ouro e itens que outros jogadores enviaram. Correio com pagamento na entrega nunca é coletado.",
  ["Collect"] = "Coletar",
  ["Collect %d"] = "Coletar %d",
  ["Stop"] = "Parar",
  ["More mail in %d s"] = "Mais correio em %d s",
  ["The mailbox did not answer"] = "A caixa de correio não respondeu",
  ["VENDOR"] = "VENDEDOR",
  ["Sell junk"] = "Vender lixo",
  ["Better at vendor"] = "Melhor no vendedor",
  ["Forget kept items"] = "Esquecer itens mantidos",
  ["Sell to vendor lists poor quality items a vendor buys."] = "Vender ao vendedor lista os itens de qualidade pobre que um vendedor compra.",
  ["Sell to vendor also lists unbound items a vendor pays as much for as the auction house would after its cut, judged only by an auction house price from the last 24 hours, never by the prices built into the addon."] = "Vender ao vendedor também lista itens não vinculados pelos quais um vendedor paga tanto quanto a casa de leilões após a sua comissão, julgados apenas por um preço da casa de leilões das últimas 24 horas, nunca pelos preços que vêm com o addon.",
  ["Sell to vendor"] = "Vender ao vendedor",
  ["Sell %d for %s"] = "Vender %d por %s",
  ["%d more after this"] = "%d a mais depois desta",
  ["Right click a line to keep that item."] = "Clique com o botão direito em uma linha para manter esse item.",
  ["Never sell this"] = "Nunca vender",
  ["The game sells one stack per press here."] = "O jogo vende aqui uma pilha por clique.",
  ["Sold %d stacks for %s. Buyback keeps the last 12 you sold."] = "%d pilhas vendidas por %s. A recompra guarda as 12 últimas vendas.",
  ["Sold 1 stack for %s. Buyback keeps the last 12 you sold."] = "1 pilha vendida por %s. A recompra guarda as 12 últimas vendas.",
  ["Reagents cost %s"] = "Os reagentes custam %s",
  ["One craft sells for %s after the auction house cut"] = "Uma fabricação vende por %s após a taxa da casa de leilões",
  ["Profit %s"] = "Lucro %s",
  ["No GoldCap price for %s"] = "Sem preço do GoldCap para %s",
  ["Worth crafting"] = "Vale a pena fabricar",
  ["%s an hour"] = "%s por hora",
  ["Slow seller"] = "Vende devagar",
  ["1 recipe has no GoldCap price for a reagent or what it makes"] = "1 receita não tem preço do GoldCap para um reagente ou para o que fabrica",
  ["%d recipes have no GoldCap price for a reagent or what it makes"] = "%d receitas não têm preço do GoldCap para um reagente ou para o que fabricam",
  ["Each reagent at its cheapest quality"] = "Cada reagente na qualidade mais barata",
  ["No recipe here has a GoldCap price yet"] = "Nenhuma receita aqui tem preço do GoldCap ainda",
  ["This recipe"] = "Esta receita",
  ["Add to queue"] = "Adicionar à fila",
  ["Restock to"] = "Repor até",
  ["How many crafts of %s?"] = "Quantas vezes fabricar %s?",
  ["Restock %s to how many? 0 takes it off the queue."] = "Repor %s até quantos? 0 tira da fila.",
  ["Type a whole number"] = "Digite um número inteiro",
  ["Queue"] = "Fila",
  ["%d to craft"] = "%d a fabricar",
  ["Restock to %d: %d held"] = "Repor até %d: você tem %d",
  ["Auctions not counted yet: open GoldCap's Sell tab at the auction house"] = "Leilões ainda não contados: abra a aba Vender do GoldCap na casa de leilões",
  ["Remove from queue"] = "Tirar da fila",
  ["The queue is empty. Add a recipe from This recipe."] = "A fila está vazia. Adicione uma receita em “Esta receita”.",
  ["Missing"] = "Faltando",
  ["%d %s"] = "%d %s",
  ["%d %s in the mailbox"] = "%d %s na caixa de correio",
  ["%s is not sold on the auction house"] = "%s não é vendido na casa de leilões",
  ["Nothing is missing for the queue"] = "Não falta nada para a fila",
  ["Make a BUY list"] = "Criar lista do BUY",
  ["Craft queue"] = "Fila de fabricação",
  ["BUY list %s is ready in the BUY tab at the auction house"] = "A lista do BUY %s está pronta na aba BUY da casa de leilões",
  ["Currency %d"] = "Moeda %d",
  ["%d in bags, %d in the Warband Bank"] = "%d nas bolsas, %d no banco do bando de guerra",
  ["Keep in bags: %d of each"] = "Manter nas bolsas: %d de cada",
  ["How many of each item in %s to keep in your bags?"] = "Quantos de cada item de %s manter nas bolsas?",
  ["Stays in bags: %s ×%d, can still be refunded"] = "Fica nas bolsas: %s ×%d, ainda pode ser reembolsado",
  ["Stays in bags: %s ×%d, the Warband Bank does not take it"] = "Fica nas bolsas: %s ×%d, o banco do bando de guerra não aceita",
  ["%d in bags, %d in your bank"] = "%d nas bolsas, %d no seu banco",
  ["Stays in bags: %s ×%d, your bank does not take it"] = "Fica nas bolsas: %s ×%d, seu banco não aceita",
  ["None of your groups' items are in your bags or this bank."] = "Nenhum item dos seus grupos está nas suas bolsas ou neste banco.",
  ["You follow no groups yet. Follow some on goldcap.gg under Groups, and the GoldCap Companion brings them here: what each holds in your bags and this bank, to store or take out in one press."] =
    "Você ainda não segue nenhum grupo. Siga alguns no goldcap.gg, em Grupos, e o GoldCap Companion os traz para cá: o que cada um tem nas suas bolsas e neste banco, para guardar ou retirar com um clique.",
  -- GoldCap Hoard, the window beside the bank (UI/HoardFrame.lua, UI/HoardRow.lua).
  ["Hoard"] = "Tesouro",
  ["Bags %d free"] = "Bolsas: %d livres",
  ["Bank %d free"] = "Banco: %d livres",
  ["Your groups"] = "Seus grupos",
  ["bags"] = "bolsas",
  ["bank"] = "banco",
  ["Store all"] = "Guardar tudo",
  ["Take all out"] = "Retirar tudo",
  ["Store"] = "Guardar",
  ["Take out"] = "Retirar",
  ["%s ×%d (%d left)"] = "%s ×%d (faltam %d)",
  ["Nothing to move"] = "Nada a mover",
  ["Gather"] = "Coleta",
  ["Craft"] = "Produção",
  ["Flip"] = "Revenda",
  ["Stock"] = "Estoque",
  ["%d groups"] = "%d grupos",
  ["%d more groups have nothing to move at this bank"] = "Mais %d grupos não têm nada a mover neste banco",
  ["1 more group has nothing to move at this bank"] = "Mais 1 grupo não tem nada a mover neste banco",
  -- Its search row, the selection bar and a run's cast bar (UI/HoardList.lua).
  ["To move here %d"] = "A mover %d",
  ["All %d"] = "Todos %d",
  ["By value"] = "Por valor",
  ["By name"] = "Por nome",
  ["No group or item matches your search."] = "Nenhum grupo ou item corresponde à sua busca.",
  ["%d groups selected"] = "%d grupos selecionados",
  ["1 group selected"] = "1 grupo selecionado",
  ["Clear the selection"] = "Limpar a seleção",
  ["Moving to %s"] = "Movendo para o %s",
  ["Moving to your bags"] = "Movendo para as bolsas",
  ["Tick groups to move several at once"] = "Marque grupos para mover vários de uma vez",
  ["Worth about %s"] = "Valem cerca de %s",
  ["Stop moving"] = "Parar de mover",
  ["%d stacks into %s"] = "%d pilhas para o %s",
  ["1 stack into %s"] = "1 pilha para o %s",
  ["%d stacks into your bags"] = "%d pilhas para as bolsas",
  ["1 stack into your bags"] = "1 pilha para as bolsas",
  -- GoldCap Hoard: its tiles (UI/HoardTiles.lua), carry cards (UI/HoardCarry.lua) and footer (UI/HoardFooter.lua).
  [", %d not shown"] = ", %d ocultos",
  ["Ready now"] = "Pronto agora",
  ["Prices are up"] = "Preços em alta",
  ["For your crafts"] = "Para suas fabricações",
  ["Put away"] = "Guardar o resto",
  ["%d items sell above your usual price"] = "%d itens vendem acima do seu preço habitual",
  ["1 item sells above your usual price"] = "1 item vende acima do seu preço habitual",
  ["Nothing sells above your usual price now"] = "Nada vende acima do seu preço habitual agora",
  ["Reagents for the %d crafts in your queue"] = "Reagentes para as %d fabricações da sua fila",
  ["Reagents for the craft in your queue"] = "Reagentes para a fabricação da sua fila",
  ["Your craft queue is empty"] = "Sua fila de fabricação está vazia",
  ["What you are not selling now, keeping what each group keeps"] = "O que você não está vendendo agora; o que cada grupo mantém fica nas bolsas",
  ["Take out %s"] = "Retirar %s",
  ["Take out %d stacks"] = "Retirar %d pilhas",
  ["Take out 1 stack"] = "Retirar 1 pilha",
  ["Store %d stacks"] = "Guardar %d pilhas",
  ["Store 1 stack"] = "Guardar 1 pilha",
  ["%d stacks"] = "%d pilhas",
  ["1 stack"] = "1 pilha",
  ["and %d more"] = "e mais %d",
  ["These sell above the usual price you set for their group."] = "Estes vendem acima do preço habitual que você definiu para o grupo deles.",
  ["Price per unit: now / usual"] = "Preço por unidade: agora / habitual",
  ["Takes them out to your bags, ready for the Sell tab."] = "Retira para as suas bolsas, prontos para a aba Vender.",
  ["What your craft queue needs that your bags lack, from this bank."] = "O que sua fila de fabricação precisa e falta nas suas bolsas, deste banco.",
  ["Per reagent: need / in bags / taken"] = "Por reagente: necessário / nas bolsas / retirado",
  ["Leaves out what sells above its usual price and what your craft queue needs."] = "Deixa de fora o que vende acima do preço habitual e o que sua fila de fabricação precisa.",
  ["Carry to another realm"] = "Levar para outro reino",
  ["Put in"] = "Guardar",
  ["Make room"] = "Abrir espaço",
  ["Put back"] = "Devolver",
  ["Moves every stack in your bags that %s takes, and remembers what went for Put back."] = "Move para o %s cada pilha das suas bolsas que ele aceita e lembra o que foi para Devolver.",
  ["Takes back from %s what Make room put there. It lands wherever your bags have room, not in its old slots."] = "Pega de volta do %s o que Abrir espaço colocou lá. Vai para onde as bolsas tiverem espaço, não para os espaços antigos.",
  ["What Make room put away is in %s: switch to it to put it back."] = "O que Abrir espaço guardou está no %s: mude para ele para devolver.",
  ["Make room has put nothing away to bring back."] = "Abrir espaço não guardou nada para devolver.",
  ["Prices from the Companion, %s ago"] = "Preços do Companion, há %s",
  ["What Make room put away is still in %s: put it back first."] = "O que Abrir espaço guardou ainda está no %s: devolva primeiro.",
  ["A newer version of GoldCap saved what Make room remembers: update GoldCap to use it."] = "Uma versão mais nova do GoldCap salvou o que Abrir espaço lembra: atualize o GoldCap para usar.",
  ["GoldCap does not know this character's name and realm yet, so Make room cannot remember what it puts away."] = "O GoldCap ainda não sabe o nome e o reino deste personagem, então Abrir espaço não pode lembrar o que guarda.",
}
