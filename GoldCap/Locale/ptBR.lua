local _, GC = ...

-- Portuguese (Brazil) -- the only Portuguese locale the retail client reports. Terminology
-- follows apps/web/messages/pt.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ptBR = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s cada  (%s no total, %s de taxa)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " O Companion mantém isso atualizado: /goldcap companion.",
  [" · %d hidden"] = " · %d ocultos",
  [" · %d keys"] = " · %d chaves",
  [" · below cost"] = " · abaixo do custo",
  [" · identity unresolved"] = " · identidade não resolvida",
  [" · stale %ds"] = " · %ds de idade",
  [" — Check again"] = " — verifique de novo",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (or /gc for short)"] =
    " — comandos: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger, /goldcap reset (ou /gc para encurtar)",
  ["%d (whole lot)"] = "%d (lote inteiro)",
  ["%d days"] = "%d dias",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d oportunidades da última varredura -- Full Scan para atualizar",
  ["%d filtered out as hard to resell"] = "%d descartadas por serem difíceis de revender",
  ["%d held back"] = "%d retidas",
  ["%d held back from posting"] = "%d não anunciadas",
  ["%d hidden -- the live check refused them"] = "%d ocultos -- a verificação ao vivo os recusou",
  ["%d missing"] = "faltam %d",
  ["%d partial"] = "%d parciais",
  ["%d prices in one request · books still loading"] =
    "%d preços em uma só consulta · livros ainda carregando",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d recusadas pela verificação ao vivo -- clique em \"HIDDEN %d\" acima para vê-las",
  ["%d sales · %s proceeds · %s in the mail"] = "%d vendas · %s de receita · %s no correio",
  ["%d units"] = "%d unid.",
  ["%d units · %d prices"] = "%d unidades · %d preços",
  ["%d without a price"] = "%d sem preço",
  ["%d without cost"] = "%d sem custo",
  ["%d · %d/%d covered"] = "%d · %d/%d cobertos",
  ["%d/%d covered"] = "%d/%d cobertos",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s por unidade    total %s -> %s",
  ["%s after the AH cut"] = "%s após a taxa da CdL",
  ["%s ahead"] = "%s à frente",
  ["%s under you"] = "%s abaixo de você",
  ["%s — %d unit%s without a cost"] = "%s — %d unidade%s sem custo",
  [", %d hidden as unsellable"] = ", %d ocultos por não serem vendáveis",
  ["24h trend"] = "Tendência 24h",
  ["A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price."] =
    "Um traço significa que o GoldCap ainda não sabe o custo de cada unidade — ele nunca vai adivinhar pelo preço de mercado.",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Uma pista, não uma promessa: revenda a 95% do valor de mercado importado, na quantidade que o próprio Check aprovaria.",
  ["A run of several purchases collapsed onto one line removes every one of them."] =
    "Se várias compras estiverem agrupadas em uma linha, todas são removidas.",
  ["AH answered empty %ds ago"] = "a casa de leilões respondeu vazia há %ds",
  ["ASKING"] = "PEDIDO",
  ["AT MARKET"] = "A MERCADO",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · PAUSADO: ",
  ["AUTO · SCANNING"] = "AUTO · ESCANEANDO",
  ["AUTOMATION & ALERTS"] = "AUTOMAÇÃO E ALERTAS",
  ["AVOID"] = "EVITAR",
  ["Above this 24-hour rise the market value is treated as a spike and deflated."] =
    "Acima dessa alta em 24 horas, o valor de mercado é tratado como um pico e é reduzido.",
  ["Asks for a second click to confirm."] = "Pede um segundo clique para confirmar.",
  ["Auction House did not answer — press Refresh"] =
    "A casa de leilões não respondeu — clique em Refresh",
  ["Auction House is not open"] = "A casa de leilões não está aberta",
  ["Auto-scan on next AH visit"] = "Escaneamento automático na próxima visita à CL",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."] =
    "Auto: mantém o Full Scan rodando sem parar e cede na hora quando você compra, procure você mesmo na casa de leilões, ou confira o correio. Clique para alternar.",
  ["Avoid"] = "Evitar",
  ["BOOKS %d/%d"] = "LIVROS %d/%d",
  ["BRAKES"] = "FREIOS",
  ["BUY — unverified"] = "COMPRAR — não verificado",
  ["Background check"] = "Verificação em segundo plano",
  ["Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money."] =
    "O ponto de equilíbrio é o menor preço que ainda cobre o seu custo depois da comissão. Vender abaixo dá prejuízo.",
  ["Bundled %s data"] = "Dados %s inclusos",
  ["Bundled data"] = "Dados inclusos",
  ["Buy"] = "Comprar",
  ["Buy less"] = "Compre menos",
  ["CANCEL %d"] = "CANCELAR %d",
  ["CANCEL LOT?"] = "CANCELAR O LOTE?",
  ["CANCELLING…"] = "CANCELANDO…",
  ["CONFIRM"] = "CONFIRMAR",
  ["COST"] = "CUSTO",
  ["COST / UNIT"] = "CUSTO / UNIDADE",
  ["Can't price this"] = "Sem preço confiável",
  ["Cancel"] = "Cancelar",
  ["Cancel lot?"] = "Cancelar?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Cancelar este lote e perder o depósito — clique de novo para confirmar",
  ["Cancel timed out"] = "O cancelamento expirou",
  ["Cancelling lot…"] = "Cancelando o lote…",
  ["Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive."] =
    "Cancela este leilão ativo — ele NÃO é reanunciado. O depósito é perdido e os itens voltam pelo correio; anuncie de novo a partir desta linha quando chegarem.",
  ["Cannot post this position"] = "Não dá para anunciar esta posição",
  ["Cannot remove this entry"] = "Não dá para apagar este registro",
  ["Cannot repost this lot"] = "Não dá para reanunciar este lote",
  ["Capped by how fast this actually sells, not by your wallet."] =
    "Limitado pela velocidade real de venda, não pela sua bolsa.",
  ["Cheaper listings remain, but at this item's pace they sell through within hours."] =
    "Ainda há anúncios mais baratos, mas no ritmo deste item eles somem em horas.",
  ["Check"] = "Checar",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "O Check recalcula pelo livro de ofertas ao vivo antes de qualquer ouro sair, e ainda pode dar menos — ou recusar — se o mercado mudou desde a sua última importação.",
  ["Checked against the live order book a moment ago."] =
    "Verificado agora mesmo contra o livro de ofertas ao vivo.",
  ["Checked: %d of the top %d on screen"] = "Verificadas: %d das %d primeiras na tela",
  ["Checking prices…"] = "Verificando preços…",
  ["Checking this item's price…"] = "Verificando o preço deste item…",
  ["Checking..."] = "Verificando...",
  ["Clear to buy"] = "Liberado para comprar",
  ["Click Confirm to post"] = "Clique em Confirm para anunciar",
  ["Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags."] =
    "Clicar de novo cancela o leilão ativo. Ele não é reanunciado: o depósito é perdido e os itens voltam pelo correio em vez de direto para as bolsas.",
  ["Clicking again deletes this hand-entered cost for good."] =
    "Clicar de novo apaga de vez este custo digitado à mão.",
  ["Close"] = "Fechar",
  ["Companion keeps prices fresh — /goldcap companion"] =
    "O Companion mantém os preços atualizados — /goldcap companion",
  ["Companion sync rejected:"] = "Sincronização do Companion recusada:",
  ["Confidence"] = "Confiança",
  ["Confirm"] = "Confirmar",
  ["Confirm the cancel"] = "Confirmar o cancelamento",
  ["Confirm the removal"] = "Confirmar a remoção",
  ["Copy the link (Ctrl+C) and open it in a browser:"] =
    "Copie o link (Ctrl+C) e abra no navegador:",
  ["Cost per unit"] = "Custo por unidade",
  ["Cost unknown for %d of %d"] = "Custo desconhecido em %d de %d",
  ["Costs more than your per-buy wallet limit allows."] =
    "Custa mais do que o seu limite por compra permite.",
  ["Could not find the queue's next item to post — try again"] =
    "Não achei o próximo item da fila para anunciar — tente de novo",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Não achei o próximo lote da fila para cancelar — tente de novo",
  ["DEFAULTS"] = "PADRÃO",
  ["DISC"] = "DESC",
  ["DISPLAY"] = "EXIBIÇÃO",
  ["DONE"] = "PRONTO",
  ["Default listing length for the Sell tab."] = "Duração padrão do anúncio na aba Vender.",
  ["Default: %s"] = "Padrão: %s",
  ["Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail."] =
    "Apaga um custo digitado à mão em Definir custo — nunca uma compra que o GoldCap capturou ou casou com o seu correio.",
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
  ["Est. profit"] = "Lucro est.",
  ["FIFO allocations"] = "Alocações FIFO",
  ["Fetching a fresh price for this item — press Post again in a moment"] =
    "Buscando um preço novo para este item — clique em Post de novo daqui a pouco",
  ["Fetching a fresh price for this lot — press Repost again in a moment"] =
    "Buscando um preço novo para este lote — clique em Repost de novo daqui a pouco",
  ["Finish the pending post first"] = "Termine primeiro o anúncio pendente",
  ["Finish the pending post or repost first"] =
    "Termine primeiro o anúncio ou reanúncio pendente",
  ["Font scale"] = "Tamanho da fonte",
  ["Free, sits in the tray, nothing to set up in game."] =
    "Gratuito, fica na bandeja do sistema e não há nada para configurar no jogo.",
  ["Full pass over them: %.1fs"] = "Passagem completa: %.1fs",
  ["Full pass over them: measuring..."] = "Passagem completa: medindo...",
  ["Gold tied up"] = "Ouro parado",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "O GoldCap não consegue identificar qual pilha da bolsa é esta",
  ["GoldCap data age"] = "Idade dos dados GoldCap",
  ["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."] =
    "O GoldCap reconfere os %d linhas contra a casa de leilões ao vivo, a cada %d s. As linhas recusadas ficam ocultas. Comprar continua sendo sempre um clique seu.",
  ["GoldCap value"] = "Valor GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Importar preços do reino",
  ["GoldCap's"] = "do GoldCap",
  ["GoldCap's suggestion for this item, and the price it would use."] =
    "A sugestão do GoldCap para este item e o preço que ele usaria.",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: verificado ao vivo -- pode comprar",
  ["GoldCap: not checked against the live auction house yet"] = "GoldCap: ainda não verificado na casa de leilões ao vivo",
  ["Gone"] = "Sumiu",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Cinza significa que a cotação envelheceu; Post e Repost a atualizam antes de agir.",
  ["HIDDEN 0"] = "OCULTAS 0",
  ["HIDE DETAILS ▾"] = "OCULTAR DETALHES ▾",
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
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "É o preço que você precisa bater para vender rápido — não o que o item vale. Um vendedor com pressa pode colocá-lo bem abaixo do valor, e o GoldCap não vai segui-lo para baixo: veja WHAT TO DO para o preço em que ele anunciaria de fato.",
  ["It will not invent a cost from the market price, so profit stays unknown until you enter one."] =
    "Ele não vai inventar um custo a partir do preço de mercado, então o lucro fica desconhecido até você informar um.",
  ["Item"] = "Item",
  ["Item %d"] = "Item %d",
  ["LISTED"] = "ANUNCIADO",
  ["Language"] = "Idioma",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Idioma alterado. Digite /reload para aplicá-lo em tudo.",
  ["Last result: %ds ago"] = "Último resultado: há %ds",
  ["Last result: none yet this visit"] = "Último resultado: nenhum nesta visita",
  ["Listed"] = "Anunciados",
  ["Listed at %s — far below market. Repost."] =
    "Anunciado a %s — bem abaixo do mercado. Reanuncie.",
  ["Listed value"] = "Valor anunciado",
  ["Listings"] = "Anúncios",
  ["Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item."] =
    "Anuncia o que está nas suas bolsas pelo preço de O QUE FAZER: a bolsa inteira para uma mercadoria, uma pilha para um item normal.",
  ["Live ask"] = "Preço ao vivo",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lote cancelado; espere ele voltar para as bolsas",
  ["MARKET"] = "MERCADO",
  ["MARKET / UNIT"] = "MERCADO / UNIDADE",
  ["MATCH"] = "IGUALAR",
  ["Market per unit"] = "Mercado por unidade",
  ["Market reference"] = "Referência de mercado",
  ["Max wallet per buy %"] = "Máx. do seu ouro por compra %",
  ["Min profit per buy (gold)"] = "Lucro mínimo por compra (ouro)",
  ["Min return per buy %"] = "Retorno mín. por compra %",
  ["Missing cost"] = "Custo faltando",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "AINDA NÃO ESTÁ NO GOLDCAP.GG — SINCRONIZA NO /RELOAD OU AO SAIR",
  ["NOT ON HAND %d"] = "FORA DE MÃO %d",
  ["NOTHING TO CANCEL"] = "NADA PARA CANCELAR",
  ["NOTHING TO POST"] = "NADA PARA ANUNCIAR",
  ["Needs a live price check before it can be bought."] =
    "Precisa de uma verificação de preço ao vivo antes de poder ser comprado.",
  ["Never spend more than this share of your gold on one purchase."] =
    "Nunca gastar mais que essa fração do seu ouro em uma única compra.",
  ["No deals passed the safety checks right now."] =
    "Agora nenhuma oportunidade passou nas verificações de segurança.",
  ["No deals to show -- and no realm prices yet."] =
    "Nenhuma oportunidade para mostrar -- e ainda sem preços do reino.",
  ["No deals yet."] = "Ainda sem oportunidades.",
  ["No exact auction key"] = "Sem chave de leilão exata",
  ["No exact bag stack"] = "Sem pilha exata na bolsa",
  ["No exact bag variant"] = "Sem variante exata na bolsa",
  ["No live listings came back for this item."] = "Nenhum anúncio ativo voltou para este item.",
  ["No region reference for this item yet — import again once goldcap.gg publishes one."] =
    "Ainda não há preço de referência da região para este item — importe de novo quando o goldcap.gg publicar um.",
  ["No safe resale price could be worked out."] =
    "Não foi possível calcular um preço de revenda seguro.",
  ["No sales data for this item."] = "Sem dados de vendas para este item.",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Nenhuma venda registrada ainda -- abra sua caixa de correio com o GoldCap carregado",
  ["Not enough units on the Auction House to fill that quantity."] =
    "Não há unidades suficientes na casa de leilões para essa quantidade.",
  ["Not in your bags or listed — mail or bank?"] =
    "Nem nas bolsas nem anunciado — correio ou banco?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Não está à mão — o estoque está no correio, no banco ou em outro personagem",
  ["Nothing is being held back."] = "Nada está sendo retido.",
  ["Nothing left to sell against after this buy, so there is no exit price."] =
    "Depois desta compra não sobra nada contra o que vender, então não há preço de saída.",
  ["Nothing listed matches the item level the reference price was measured on."] =
    "Nenhum anúncio alcança o nível de item em que o preço de referência foi medido.",
  ["Nothing listed on the AH right now"] = "Nada anunciado na casa de leilões agora",
  ["Nothing on this deck matches that search"] = "Nada nesta aba corresponde a essa busca",
  ["Nothing queued to cancel"] = "Nada na fila para cancelar",
  ["Nothing queued to post"] = "Nada na fila para anunciar",
  ["Nothing to remove"] = "Nada para apagar",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "NO GOLDCAP.GG — ÚLTIMOS %d DIAS",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "NO GOLDCAP.GG — ÚLTIMOS %d DIAS, MAIS RECENTES %d DE %d",
  ["ON THE AUCTION HOUSE"] = "NA CASA DE LEILÕES",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "Uma varredura única de toda a casa de leilões por consultas paginadas. Leva cerca de De 15 a 60 segundos em reinos movimentados. Sem recarga -- varra de novo quando quiser.",
  ["Open the Auction House first."] = "Abra a casa de leilões primeiro.",
  ["Open the Auction House to begin scanning."] =
    "Abra a casa de leilões para começar a varredura.",
  ["Open the deals board. /gc for commands."] = "Abre o painel de oportunidades. /gc para os comandos.",
  ["POST %d"] = "ANUNCIAR %d",
  ["POSTING"] = "PUBLICAÇÃO",
  ["POSTING…"] = "ANUNCIANDO…",
  ["PRICE"] = "PREÇO",
  ["PRICE ROSE %.1fx"] = "O PREÇO SUBIU %.1fx",
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
  ["Positions without a cost or a live price are excluded."] =
    "Posições sem custo ou sem preço ao vivo ficam de fora.",
  ["Post"] = "Anunciar",
  ["Post above the cheapest"] = "Anunciar acima do mais barato",
  ["Post confirmation expired"] = "A confirmação do anúncio expirou",
  ["Post the next queued item"] = "Anunciar o próximo item da fila",
  ["Posting failed"] = "Falha ao anunciar",
  ["Posting timed out"] = "O anúncio expirou",
  ["Posting unavailable"] = "Anúncio indisponível",
  ["Posting…"] = "Anunciando…",
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
  ["Pricing…"] = "Consultando preços…",
  ["Profit"] = "Lucro",
  ["Profit per unit"] = "Lucro por unidade",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "O acompanhamento de lucro é um recurso do goldcap.gg Pro",
  ["Purchases are turned off in this build."] = "As compras estão desligadas nesta versão.",
  ["QTY"] = "QTD",
  ["Quantity exceeds missing units"] = "A quantidade passa das unidades que faltam",
  ["Quantity is capped by how fast this item actually sells."] =
    "A quantidade é limitada pela rapidez com que este item realmente vende.",
  ["REALIZED PROFIT"] = "LUCRO REALIZADO",
  ["REFRESH"] = "ATUALIZAR",
  ["RESET WINDOW"] = "REDEFINIR JANELA",
  ["Reason"] = "Motivo",
  ["Refresh"] = "Atualizar",
  ["Refresh waiting for prior result"] = "A atualização está esperando o resultado anterior",
  ["Refreshing listings…"] = "Atualizando os anúncios…",
  ["Refuse a buy when the price fell more than this in the last 24 hours — it may keep falling."] =
    "Recusar uma compra se o preço caiu mais que isso nas últimas 24 horas — ele pode continuar caindo.",
  ["Refused so far: %d"] = "Recusadas até agora: %d",
  ["Removal confirmation expired"] = "A confirmação de remoção expirou",
  ["Remove"] = "Apagar",
  ["Remove this cost"] = "Remover este custo",
  ["Remove?"] = "Apagar?",
  ["Removed"] = "Removido",
  ["Removed %d entries"] = "%d entradas removidas",
  ["Removes every entered-by-hand purchase in this run -- click again to confirm"] =
    "Apaga todas as compras digitadas à mão neste grupo -- clique de novo para confirmar",
  ["Removes this entered-by-hand purchase -- click again to confirm"] =
    "Apaga esta compra digitada à mão -- clique de novo para confirmar",
  ["Repost"] = "Reanunciar",
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
  ["SESSION %s%s · %d BUYS"] = "SESSÃO %s%s · %d COMPRAS",
  ["SHOW DETAILS ▸"] = "MOSTRAR DETALHES ▸",
  ["Sales are costed from your oldest units first"] =
    "As vendas são custeadas a partir das suas unidades mais antigas",
  ["Search"] = "Buscar",
  ["Sell tab posts one rung above the cheapest ask when the book says it sells just as fast."] =
    "A aba Vender anuncia um degrau acima da oferta mais barata quando o livro mostra que ela vende na mesma velocidade.",
  ["Sell-through"] = "Taxa de venda",
  ["Sellers"] = "Vendedores",
  ["Sells too rarely -- you would be holding it for a long time."] =
    "Vende raramente demais — você ficaria com ele por muito tempo.",
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
  ["Source age"] = "Idade da fonte",
  ["Spike-trend threshold %"] = "Limiar de alta repentina %",
  ["Start scanning as soon as the auction house opens."] =
    "Começar a escanear assim que a Casa de Leilões abrir.",
  ["Status"] = "Estado",
  ["Stress exit unit"] = "Preço de saída sob pressão",
  ["Stress profit"] = "Lucro sob pressão",
  ["THE BOOK"] = "O LIVRO DE OFERTAS",
  ["TOTAL"] = "TOTAL",
  ["TREND"] = "TENDÊNCIA",
  ["Tell GoldCap what you actually paid for these units."] =
    "Diga ao GoldCap quanto você realmente pagou por estas unidades.",
  ["The Auction House would not quote a deposit, so the cost is unknown."] =
    "A casa de leilões não informou o depósito, então o custo é desconhecido.",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "O Companion está sincronizando, mas este addon não conseguiu ler o que ele escreveu:",
  ["The board tiered this off the imported snapshot. The live book does not back it."] =
    "O painel classificou isto pelo snapshot importado. O livro ao vivo não confirma.",
  ["The button waits a moment before it can be pressed, so this is never an accidental double-click."] =
    "O botão espera um instante antes de poder ser pressionado, então um duplo clique acidental nunca basta.",
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
  ["The price data is over three hours old. Sync the Companion, then /reload -- the addon only reads its data when the UI loads."] =
    "Os dados de preço têm mais de três horas. Sincronize o Companion e faça /reload — o addon só lê seus dados quando a interface carrega.",
  ["The price is checked. How fast this sells is not measured anywhere, so this one is yours to judge."] =
    "O preço está conferido. A rapidez de venda não é medida em lugar nenhum, então o julgamento é seu.",
  ["The price is falling; buying into it is how you get stuck."] =
    "O preço está caindo; entrar nisso é como você fica preso.",
  ["The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price."] =
    "O preço é a última cotação, com no máximo 45 segundos. Se ele mudar antes de confirmar, o anúncio é abandonado em vez de enviado pelo preço antigo.",
  ["The price moved and the trade is no longer safe."] =
    "O preço se moveu e a operação não é mais segura.",
  ["The profit does not clear your minimum once the 5% cut and deposit are paid."] =
    "O lucro não alcança o seu mínimo depois de pagas a comissão de 5 % e o depósito.",
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
  ["UNIT"] = "UNIDADE",
  ["Unit price"] = "Preço por unidade",
  ["Unknown"] = "Desconhecido",
  ["Unknown item"] = "Item desconhecido",
  ["Unknown means the cost side is incomplete -- fill it in with Set cost."] =
    "Desconhecido significa que falta parte do custo — complete com Definir custo.",
  ["VERDICT"] = "VEREDITO",
  ["Verdict"] = "Veredito",
  ["WATCH"] = "OBSERVAR",
  ["WATCH (computed SAFE)"] = "WATCH (calculado SEGURO)",
  ["WATCH = the live check refused it -- hover the row for the reason"] =
    "OBSERVAR = a verificação ao vivo recusou -- passe o mouse na linha para ver o motivo",
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
  ["Watching — pinned, but not a deal right now"] =
    "Acompanhando — fixado, mas agora não é uma oportunidade",
  ["What one of these actually cost you, averaged over the purchases still on hand."] =
    "Quanto uma unidade realmente lhe custou, na média das compras ainda em estoque.",
  ["What to do"] = "O que fazer",
  ["What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost."] =
    "O que sobra numa unidade se ela vender pelo preço de mercado: preço de venda, menos os 5 % de comissão, menos o seu custo.",
  ["What your live auctions for this item add up to at their current asking price."] =
    "Quanto somam seus leilões ativos deste item pelo preço atual.",
  ["Window position & size"] = "Posição e tamanho da janela",
  ["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."] =
    "Com ele, os preços do seu reino se atualizam sozinhos e suas vendas e lucro vão para o goldcap.gg.",
  ["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."] =
    "Sem ele, o GoldCap usa os preços congelados na data de lançamento — as oportunidades são buscadas com preços velhos.",
  ["Won't buy"] = "Não vou comprar",
  ["Worst case back"] = "Retorno no pior caso",
  ["YOUR PRICE"] = "SEU PREÇO",
  ["You paid"] = "Você pagou",
  ["You pay"] = "Você paga",
  ["You would get"] = "Você receberia",
  ["You would pay"] = "Você pagaria",
  ["Your call"] = "Você decide",
  ["Your minimum"] = "Seu mínimo",
  ["above the cheapest, inside the cheap quarter · %d units queued below"] =
    "acima do mais barato, dentro do quarto barato · %d unidades na fila abaixo",
  ["above the cheapest, within the day's reach · %d units queued below"] =
    "acima do mais barato, dentro do alcance do dia · %d unidades na fila abaixo",
  ["against the region's own price for this item, after the 5% cut — if it sells"] =
    "em relação ao preço da região para este item, após a taxa de 5% — se vender",
  ["any figure here would be invented out of the very number being refused"] =
    "qualquer valor aqui seria inventado a partir do mesmo número que está sendo recusado",
  ["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"] =
    "pelo preço que a GoldCap espera que isso venda, após a taxa de 5% — não o seu preço pedido",
  ["auto off"] = "auto desligado",
  ["auto-synced %dh ago"] = "sincronizado automaticamente há %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "dados sincronizados de %s carregados (%s de idade)",
  ["auto-synced data stale -- /goldcap import"] =
    "os dados sincronizados estão velhos -- /goldcap import",
  ["auto: paused"] = "auto: pausado",
  ["below the %s you paid"] = "abaixo dos %s que você pagou",
  ["big buy"] = "compra grande",
  ["bought %d x item %d"] = "comprados %d x item %d",
  ["bought %d x item %d after AH close"] =
    "comprados %d x item %d depois que a casa de leilões fechou",
  ["buying commodity..."] = "comprando mercadoria...",
  ["cheapest not yours %s"] = "o mais barato que não é seu %s",
  ["checking live price..."] = "verificando o preço ao vivo...",
  ["checking live safety..."] = "verificando a segurança ao vivo...",
  ["commodity purchase failed"] = "a compra da mercadoria falhou",
  ["confirmed commodity purchase failed after AH close"] =
    "a compra confirmada de mercadoria falhou depois que a casa de leilões fechou",
  ["confirming purchase..."] = "confirmando a compra...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "base de custo incompleta -- defina os custos para receber conselho de reanúncio",
  ["cost unknown"] = "custo desconhecido",
  ["crafted %s"] = "fabricado %s",
  ["data from goldcap.gg · synced %s ago"] = "dados do goldcap.gg · sincronizados há %s",
  ["due -- will be asked next pass"] = "pendente -- será consultado na próxima passagem",
  ["fair"] = "média",
  ["far below market"] = "bem abaixo do mercado",
  ["finish the pending buy first"] = "termine primeiro a compra pendente",
  ["first in line"] = "primeiro da fila",
  ["full scan already in progress"] = "a varredura completa já está em andamento",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "varredura completa concluída: %d oportunidade%s de %d grupo%s de itens%s",
  ["full scan interrupted -- confirm your purchase"] =
    "varredura completa interrompida -- confirme sua compra",
  ["full scan stalled -- press Full Scan to retry"] =
    "a varredura completa travou -- clique em Full Scan para tentar de novo",
  ["full scan stalled -- retrying shortly"] = "a varredura completa travou -- nova tentativa em breve",
  ["gone / price changed"] = "sumiu / preço mudou",
  ["high"] = "alta",
  ["hold"] = "segurar",
  ["identity unresolved (variant item -- not priced by design)"] =
    "identidade não resolvida (item com variantes -- sem preço de propósito)",
  ["if you buy all %d and sell them back at the price standing there now"] =
    "se você comprar todas as %d e revendê-las pelo preço que está ali agora",
  ["import %dh old"] = "importação de %dh atrás",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "importação velha -- /goldcap import ou /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "importados %d itens para %s (%s) — os preços já estão valendo.",
  ["in the mail"] = "no correio",
  ["in the mail, the bank or on another character"] = "no correio, no banco ou em outro personagem",
  ["is what this market absorbs — past that you are buying stock you will sit on"] =
    "é o que este mercado absorve — além disso você compra estoque que vai ficar parado",
  ["item %d"] = "item %d",
  ["item %d: %s"] = "item %d: %s",
  ["item variant unresolved"] = "variante do item não resolvida",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "últimas 24 h — %d vendas, %s bruto, %s de taxa, %d compras, %s gastos",
  ["listing gone -- already bought out or price changed"] =
    "o anúncio sumiu -- já foi comprado ou o preço mudou",
  ["listing gone -- bought out or repriced"] = "o leilão sumiu: comprado ou reprecificado",
  ["live safety confirmed -- click Buy to purchase"] =
    "segurança confirmada ao vivo -- clique em Buy para comprar",
  ["live verification required"] = "é preciso verificação ao vivo",
  ["low"] = "baixa",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "importação manual -- o Companion mantém isso atualizado: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "precisa de um preço novo -- clique em Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "sem confirmação do servidor -- a compra ainda pode ter passado, confira seu correio. Fechar isto não desfaz.",
  ["no cost"] = "sem custo",
  ["no cost for %d"] = "sem custo para %d",
  ["no live price yet"] = "ainda sem preço ao vivo",
  ["no price"] = "sem preço",
  ["no prices yet -- /goldcap companion or /goldcap import"] =
    "ainda sem preços -- /goldcap companion ou /goldcap import",
  ["no purchase confirmation received -- Cancel and retry"] =
    "nenhuma confirmação de compra recebida -- clique em Cancel e tente de novo",
  ["no sales recorded yet — open your mailbox with GoldCap loaded and they will be read from the invoices"] =
    "nenhuma venda registrada ainda — abra sua caixa de correio com o GoldCap carregado e elas serão lidas das faturas",
  ["no stock in bags or listed -- nothing to price for"] =
    "sem estoque nas bolsas e nada anunciado -- nada para precificar",
  ["none"] = "nenhum",
  ["not enough gold -- total %s, you have %s"] = "ouro insuficiente -- total %s, você tem %s",
  ["not enough gold for this quote -- Cancel"] = "ouro insuficiente para esta cotação -- Cancel",
  ["not enough units left for that quantity -- re-checking what remains..."] =
    "não restam unidades suficientes para essa quantidade -- verificando de novo o que resta...",
  ["not ready to cancel"] = "ainda não dá para cancelar",
  ["not ready to post"] = "ainda não dá para anunciar",
  ["nothing listed"] = "nada anunciado",
  ["of %d"] = "de %d",
  ["off"] = "desativado",
  ["oldest units sell first"] = "as unidades mais antigas vendem primeiro",
  ["on"] = "ativado",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "ou cole uma string do goldcap.gg com /goldcap import.",
  ["over %d position%s"] = "em %d posições%s",
  ["paid sale unresolved"] = "venda paga não resolvida",
  ["placing bid..."] = "dando o lance...",
  ["price checked, sale speed unknown -- this one is your call"] =
    "preço conferido, velocidade de venda desconhecida -- essa é sua decisão",
  ["price confirmed -- click Buy to purchase"] = "preço confirmado -- clique em Buy para comprar",
  ["price rose %.1fx — still safe, confirm"] = "o preço subiu %.1fx — ainda seguro, confirme",
  ["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"] =
    "os preços carregados são de %s (%s) mas você joga em %s — todo desconto e lucro é medido contra outro mercado",
  ["purchase canceled"] = "compra cancelada",
  ["purchase complete"] = "compra concluída",
  ["purchase identity unresolved"] = "identidade da compra não resolvida",
  ["purchase pending exact cost"] = "compra esperando o custo exato",
  ["purchase total unavailable — inspect mailbox"] =
    "não dá para obter o total da compra — confira a caixa de correio",
  ["quote %s -- click Confirm to buy"] = "cotação %s -- clique em Confirm para comprar",
  ["quote %ss ago"] = "cotação de %ss atrás",
  ["quote expired -- Refresh to re-check the price"] =
    "cotação expirada -- clique em Refresh para conferir o preço de novo",
  ["re-checking what remains at a safe price..."] =
    "verificando de novo o que resta a um preço seguro...",
  ["realm item — sale speed unverified · region reference %s (ilvl %d)"] =
    "item de reino — velocidade de venda não verificada · referência da região %s (nível %d)",
  ["recent sales (newest first):"] = "vendas recentes (mais novas primeiro):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "região %s — inclusos: %d itens (%s), importados: %s",
  ["region corrected on %d ledger rows; %d sales matched back to their stock"] =
    "região corrigida em %d registros; %d vendas reassociadas ao seu estoque",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "reanunciar agora travaria um prejuízo ou uma parada -- segure",
  ["removed %d duplicate purchase records left by a mail-scan bug"] =
    "apagados %d registros de compra duplicados deixados por uma falha na leitura do correio",
  ["removed %d duplicate sale records left by a mail-scan bug"] =
    "apagados %d registros de venda duplicados deixados por uma falha na leitura do correio",
  ["sale name ambiguous"] = "nome da venda ambíguo",
  ["sale proceeds pending"] = "receita da venda pendente",
  ["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"] =
    "varredura concluída: %d oferta%s de %d item%s em materiais, consumíveis, gemas, encantamentos%s",
  ["scanned %d listings over %d passes"] = "varridos %d anúncios em %d passagens",
  ["scanning auction house..."] = "varrendo a casa de leilões...",
  ["scanning… %d results · %d deals%s"] = "varrendo… %d resultados · %d oportunidades%s",
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
  ["the Companion wrote prices this addon could not read --"] =
    "o Companion escreveu preços que este addon não conseguiu ler --",
  ["the import failed (%s)"] = "a importação falhou (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["to clear %d units at %s sold a day, with %s tied up the whole time"] =
    "para escoar %d unidades a %s vendas por dia, com %s parado esse tempo todo",
  ["under GoldCap's own floor of %s"] = "abaixo do piso do GoldCap, %s",
  ["unknown evidence"] = "evidência desconhecida",
  ["waiting for previous commodity purchase to settle"] =
    "esperando a compra de mercadoria anterior ser liquidada",
  ["waiting for previous search result to settle"] = "esperando o resultado da busca anterior",
  ["watching %s closely -- re-checked every few seconds"] =
    "acompanhando %s de perto -- reconferido a cada poucos segundos",
  ["worst case, selling all %d back into the price standing there now"] =
    "no pior caso, revendendo todas as %d pelo preço que está ali agora",
  ["would sell at a loss"] = "venderia com prejuízo",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "você ainda não importou os preços do reino -- instale o GoldCap Companion (/goldcap companion) ou cole uma string do goldcap.gg (/goldcap import).",
  ["your game client has no font for this language — the text will show as empty boxes"] =
    "seu cliente do jogo não tem fonte para este idioma — o texto aparecerá como quadrados vazios",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "sua importação tem %d horas -- os preços podem estar errados. Cole uma string nova do goldcap.gg (/goldcap import).",
  ["yours"] = "seu",
  ["» needs price"] = "» falta preço",
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
  ["— = nothing is checking this row right now"] = "— = nada está verificando esta linha agora",
  ["… = a live check is queued for this row"] =
    "… = há uma verificação ao vivo na fila para esta linha",
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valor de mercado do goldcap.gg — ainda sem cotação ao vivo",
  ["no answer %ds ago -- resting"] = "sem resposta há %ds -- em pausa",
}
