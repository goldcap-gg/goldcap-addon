local _, GC = ...

-- Portuguese (Brazil) -- the only Portuguese locale the retail client reports. Terminology
-- follows apps/web/messages/pt.json where the site has the same concept.
-- Format specifiers must stay in the key's order: Lua 5.1 has no positional %1$s.
GC.Locales.ptBR = {
  [" %s  %s  x%d at %s each  (%s total, %s cut)%s"] =
    " %s  %s  x%d a %s cada  (%s no total, %s de taxa)%s",
  [" Companion keeps this fresh: /goldcap companion."] =
    " O Companion mantém isso atualizado: /goldcap companion.",
  [" rows against the live auction house about every "] =
    " linhas contra a casa de leilões ao vivo, a cada ",
  [" |cffff4040v|r"] = " |cffff4040v|r",
  [" · below cost"] = " · abaixo do custo",
  [" · stale %ds"] = " · %ds de idade",
  [" — commands: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (or /gc for short)"] =
    " — comandos: /goldcap import, /goldcap companion, /goldcap status, /goldcap sniper, /goldcap sales, /goldcap ledger (ou /gc para encurtar)",
  ["%d (whole lot)"] = "%d (lote inteiro)",
  ["%d deals from your last scan -- Full Scan to refresh"] =
    "%d oportunidades da última varredura -- Full Scan para atualizar",
  ["%d filtered out as hard to resell"] = "%d descartadas por serem difíceis de revender",
  ["%d held back"] = "%d retidas",
  ["%d held back from posting"] = "%d não anunciadas",
  ["%d missing"] = "faltam %d",
  ["%d partial"] = "%d parciais",
  ["%d refused by live checks -- press \"HIDDEN %d\" above to review them"] =
    "%d recusadas pela verificação ao vivo -- clique em \"HIDDEN %d\" acima para vê-las",
  ["%d sales · %s proceeds · %s in the mail"] = "%d vendas · %s de receita · %s no correio",
  ["%d without a price"] = "%d sem preço",
  ["%d without cost"] = "%d sem custo",
  ["%d · %d/%d covered"] = "%d · %d/%d cobertos",
  ["%d/%d covered"] = "%d/%d cobertos",
  ["%s -> %s per unit    total %s -> %s"] = "%s -> %s por unidade    total %s -> %s",
  ["%s — %d unit%s without a cost"] = "%s — %d unidade%s sem custo",
  ["15-60 seconds on busy realms. No cooldown -- rescan anytime."] =
    "De 15 a 60 segundos em reinos movimentados. Sem recarga -- varra de novo quando quiser.",
  ["24h trend"] = "Tendência 24h",
  ["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."] =
    "Uma pista, não uma promessa: revenda a 95% do valor de mercado importado, na quantidade que o próprio Check aprovaria.",
  ["AH answered empty %ds ago"] = "a casa de leilões respondeu vazia há %ds",
  ["AUTO"] = "AUTO",
  ["AUTO · PAUSED: "] = "AUTO · PAUSADO: ",
  ["Auction House did not answer — press Refresh"] =
    "A casa de leilões não respondeu — clique em Refresh",
  ["Auction House is not open"] = "A casa de leilões não está aberta",
  ["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, "] =
    "Auto: mantém o Full Scan rodando sem parar e cede na hora quando você compra, ",
  ["Avoid"] = "Evitar",
  ["Background check"] = "Verificação em segundo plano",
  ["Bundled %s data"] = "Dados %s inclusos",
  ["Bundled data"] = "Dados inclusos",
  ["Buy"] = "Comprar",
  ["Buy %d × %s for %s"] = "Comprar %d × %s por %s",
  ["CANCEL %d"] = "CANCELAR %d",
  ["CANCEL LOT?"] = "CANCELAR O LOTE?",
  ["CANCELLING…"] = "CANCELANDO…",
  ["CONFIRM"] = "CONFIRMAR",
  ["CONFIRM PURCHASE"] = "CONFIRMAR A COMPRA",
  ["COST / UNIT"] = "CUSTO / UNIDADE",
  ["Cancel"] = "Cancelar",
  ["Cancel lot?"] = "Cancelar o lote?",
  ["Cancel this lot and lose its deposit — click again to confirm"] =
    "Cancelar este lote e perder o depósito — clique de novo para confirmar",
  ["Cancel timed out"] = "O cancelamento expirou",
  ["Cancelling lot…"] = "Cancelando o lote…",
  ["Cannot post this position"] = "Não dá para anunciar esta posição",
  ["Cannot remove this entry"] = "Não dá para apagar este registro",
  ["Cannot repost this lot"] = "Não dá para reanunciar este lote",
  ["Check"] = "Verificar",
  ["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."] =
    "O Check recalcula pelo livro de ofertas ao vivo antes de qualquer ouro sair, e ainda pode dar menos — ou recusar — se o mercado mudou desde a sua última importação.",
  ["Checked: %d of the top %d on screen"] = "Verificadas: %d das %d primeiras na tela",
  ["Checking prices…"] = "Verificando preços…",
  ["Checking this item's price…"] = "Verificando o preço deste item…",
  ["Click Confirm to post"] = "Clique em Confirm para anunciar",
  ["Close"] = "Fechar",
  ["Companion sync rejected:"] = "Sincronização do Companion recusada:",
  ["Confirm"] = "Confirmar",
  ["Cost unknown for %d of %d"] = "Custo desconhecido em %d de %d",
  ["Could not find the queue's next item to post — try again"] =
    "Não achei o próximo item da fila para anunciar — tente de novo",
  ["Could not find the queue's next lot to cancel — try again"] =
    "Não achei o próximo lote da fila para cancelar — tente de novo",
  ["DONE"] = "PRONTO",
  ["Duration"] = "Duração",
  ["ENTRY AVG"] = "ENTRADA MÉD.",
  ["EST. PROFIT AFTER AH CUT"] = "LUCRO EST. APÓS A TAXA",
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
  ["Full pass over them: %.1fs"] = "Passagem completa: %.1fs",
  ["Full pass over them: measuring..."] = "Passagem completa: medindo...",
  ["GOOD = solid discount + profit"] = "GOOD = desconto sólido + lucro",
  ["GoldCap Companion"] = "GoldCap Companion",
  ["GoldCap Sniper"] = "GoldCap Sniper",
  ["GoldCap can't pin down which bag stack this is"] =
    "O GoldCap não consegue identificar qual pilha da bolsa é esta",
  ["GoldCap data age"] = "Idade dos dados GoldCap",
  ["GoldCap re-checks the top "] = "O GoldCap reconfere os ",
  ["GoldCap value"] = "Valor GoldCap",
  ["GoldCap — Import realm prices"] = "GoldCap — Importar preços do reino",
  ["GoldCap: %s -- %s"] = "GoldCap: %s -- %s",
  ["GoldCap: checked live -- safe to buy"] = "GoldCap: verificado ao vivo -- pode comprar",
  ["Greyed out means the quote has aged; Post and Repost refresh it before they act."] =
    "Cinza significa que a cotação envelheceu; Post e Repost a atualizam antes de agir.",
  ["HIDDEN 0"] = "OCULTAS 0",
  ["HIDE DETAILS ▾"] = "OCULTAR DETALHES ▾",
  ["HOT = big discount + high profit + proven sales/day"] =
    "HOT = desconto grande + lucro alto + vendas/dia comprovadas",
  ["Held back from cancelling"] = "Retido do cancelamento",
  ["Held back from the queue"] = "Retido da fila",
  ["ITEM"] = "ITEM",
  ["Import"] = "Importar",
  ["Import failed:"] = "Falha na importação:",
  ["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] =
    "Instale o GoldCap Companion gratuito para manter os preços atualizados sozinho (/goldcap companion),",
  ["It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at."] =
    "É o preço que você precisa bater para vender rápido — não o que o item vale. Um vendedor com pressa pode colocá-lo bem abaixo do valor, e o GoldCap não vai segui-lo para baixo: veja WHAT TO DO para o preço em que ele anunciaria de fato.",
  ["Item"] = "Item",
  ["Item %d"] = "Item %d",
  ["LISTED"] = "ANUNCIADO",
  ["LIVE VERDICT · CHECKING"] = "VEREDITO AO VIVO · VERIFICANDO",
  ["LIVE VERDICT · REFUSED"] = "VEREDITO AO VIVO · RECUSADO",
  ["LIVE VERDICT · SAFE"] = "VEREDITO AO VIVO · SEGURO",
  ["Language"] = "Idioma",
  ["Language changed. Type /reload to apply it everywhere."] =
    "Idioma alterado. Digite /reload para aplicá-lo em tudo.",
  ["Last result: %ds ago"] = "Último resultado: há %ds",
  ["Last result: none yet this visit"] = "Último resultado: nenhum nesta visita",
  ["Listed"] = "Anunciados",
  ["Listed at %s — far below market. Repost."] =
    "Anunciado a %s — bem abaixo do mercado. Reanuncie.",
  ["Listings"] = "Anúncios",
  ["Lot cancelled; wait for it to return to bags"] =
    "Lote cancelado; espere ele voltar para as bolsas",
  ["MARKET / UNIT"] = "MERCADO / UNIDADE",
  ["Market per unit"] = "Mercado por unidade",
  ["Market reference"] = "Referência de mercado",
  ["NOT ON GOLDCAP.GG YET — SYNCS ON /RELOAD OR LOGOUT"] =
    "AINDA NÃO ESTÁ NO GOLDCAP.GG — SINCRONIZA NO /RELOAD OU AO SAIR",
  ["NOTHING TO CANCEL"] = "NADA PARA CANCELAR",
  ["NOTHING TO POST"] = "NADA PARA ANUNCIAR",
  ["No deals passed the safety checks right now."] =
    "Agora nenhuma oportunidade passou nas verificações de segurança.",
  ["No deals to show -- and no realm prices yet."] =
    "Nenhuma oportunidade para mostrar -- e ainda sem preços do reino.",
  ["No deals yet."] = "Ainda sem oportunidades.",
  ["No exact auction key"] = "Sem chave de leilão exata",
  ["No exact bag stack"] = "Sem pilha exata na bolsa",
  ["No exact bag variant"] = "Sem variante exata na bolsa",
  ["No sales recorded yet -- open your mailbox with GoldCap loaded"] =
    "Nenhuma venda registrada ainda -- abra sua caixa de correio com o GoldCap carregado",
  ["Not in your bags or listed — mail or bank?"] =
    "Nem nas bolsas nem anunciado — correio ou banco?",
  ["Not on hand — the stock is in the mail, the bank, or on another character"] =
    "Não está à mão — o estoque está no correio, no banco ou em outro personagem",
  ["Nothing is being held back."] = "Nada está sendo retido.",
  ["Nothing listed on the AH right now"] = "Nada anunciado na casa de leilões agora",
  ["Nothing queued to cancel"] = "Nada na fila para cancelar",
  ["Nothing queued to post"] = "Nada na fila para anunciar",
  ["Nothing to remove"] = "Nada para apagar",
  ["ON GOLDCAP.GG — LAST %d DAYS"] = "NO GOLDCAP.GG — ÚLTIMOS %d DIAS",
  ["ON GOLDCAP.GG — LAST %d DAYS, LATEST %d OF %d"] =
    "NO GOLDCAP.GG — ÚLTIMOS %d DIAS, MAIS RECENTES %d DE %d",
  ["One-shot scan of the entire Auction House via paged browse queries. Takes roughly "] =
    "Uma varredura única de toda a casa de leilões por consultas paginadas. Leva cerca de ",
  ["Open the Auction House first."] = "Abra a casa de leilões primeiro.",
  ["Open the Auction House to begin scanning."] =
    "Abra a casa de leilões para começar a varredura.",
  ["Open the deals board. /gc for commands."] = "Abre o painel de oportunidades. /gc para os comandos.",
  ["POST %d"] = "ANUNCIAR %d",
  ["POSTING…"] = "ANUNCIANDO…",
  ["PRICE ROSE %.1fx"] = "O PREÇO SUBIU %.1fx",
  ["PROFIT / UNIT"] = "LUCRO / UNIDADE",
  ["Pair or update the GoldCap Companion to see profit from goldcap.gg"] =
    "Vincule ou atualize o GoldCap Companion para ver o lucro do goldcap.gg",
  ["Paste your realm string from goldcap.gg and press Import."] =
    "Cole a string do seu reino do goldcap.gg e clique em Import.",
  ["Position scope changed"] = "O escopo da posição mudou",
  ["Positions without a cost or a live price are excluded."] =
    "Posições sem custo ou sem preço ao vivo ficam de fora.",
  ["Post"] = "Anunciar",
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
  ["Prices up to date"] = "Preços atualizados",
  ["Prices up to date · %d did not answer"] = "Preços atualizados · %d não responderam",
  ["Pricing %d/%d…"] = "Consultando preços %d/%d…",
  ["Pricing…"] = "Consultando preços…",
  ["Profit tracking is a goldcap.gg Pro feature"] =
    "O acompanhamento de lucro é um recurso do goldcap.gg Pro",
  ["QTY"] = "QTD",
  ["Quantity exceeds missing units"] = "A quantidade passa das unidades que faltam",
  ["REALIZED PROFIT"] = "LUCRO REALIZADO",
  ["REFRESH"] = "ATUALIZAR",
  ["RESET WINDOW"] = "REDEFINIR JANELA",
  ["Refresh waiting for prior result"] = "A atualização está esperando o resultado anterior",
  ["Refreshing listings…"] = "Atualizando os anúncios…",
  ["Refused so far: %d"] = "Recusadas até agora: %d",
  ["Removal confirmation expired"] = "A confirmação de remoção expirou",
  ["Remove"] = "Apagar",
  ["Remove?"] = "Apagar?",
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
  ["SAVED INSTANTLY · ESC OR DONE TO CLOSE"] = "SALVO NA HORA · ESC OU DONE PARA FECHAR",
  ["SCAN"] = "VARRER",
  ["SCANNING…"] = "VARRENDO…",
  ["SESSION %s%s · %d BUYS"] = "SESSÃO %s%s · %d COMPRAS",
  ["SHOW DETAILS ▸"] = "MOSTRAR DETALHES ▸",
  ["STRESS EXIT"] = "SAÍDA SOB PRESSÃO",
  ["SUSPECT = discount so extreme it's probably a scam/mispriced-market item"] =
    "SUSPECT = desconto tão extremo que provavelmente é golpe ou mercado mal precificado",
  ["Sales are costed from your oldest units first"] =
    "As vendas são custeadas a partir das suas unidades mais antigas",
  ["Set cost"] = "Definir custo",
  ["Settings"] = "Configurações",
  ["Sold per day"] = "Vendas por dia",
  ["Sort by it to decide what to Check first, not to decide what to buy."] =
    "Ordene por ele para decidir o que verificar primeiro, não o que comprar.",
  ["Source age"] = "Idade da fonte",
  ["Stress exit unit"] = "Preço de saída sob pressão",
  ["Stress profit"] = "Lucro sob pressão",
  ["The Companion is syncing, but this addon could not read what it wrote:"] =
    "O Companion está sincronizando, mas este addon não conseguiu ler o que ele escreveu:",
  ["The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards."] =
    "É o menor preço que OUTRA pessoa está pedindo agora, por uma consulta ao vivo à casa de leilões. Os seus próprios anúncios ficam de fora, então o número nunca persegue a si mesmo para baixo.",
  ["The free desktop Companion keeps your prices fresh automatically and syncs your sales. Copy the link (Ctrl+C) and open it in a browser:"] =
    "O Companion gratuito para computador mantém seus preços atualizados sozinho e sincroniza suas vendas. Copie o link (Ctrl+C) e abra no navegador:",
  ["Unknown"] = "Desconhecido",
  ["Unknown item"] = "Item desconhecido",
  ["WATCH (computed SAFE)"] = "WATCH (calculado SEGURO)",
  ["WATCH = discounted but unproven liquidity or small profit"] =
    "WATCH = com desconto, mas liquidez não comprovada ou lucro pequeno",
  ["WHAT TO DO"] = "O QUE FAZER",
  ["Waiting for Auction House…"] = "Esperando a casa de leilões…",
  ["Waiting for a live price"] = "Esperando um preço ao vivo",
  ["Waiting for the Auction House…"] = "Esperando a casa de leilões…",
  ["Waiting for the purchase to finish…"] = "Esperando a compra terminar…",
  ["Watching closely: %d item%s"] = "Acompanhando de perto: %d item%s",
  ["Watching — pinned, but not a deal right now"] =
    "Acompanhando — fixado, mas agora não é uma oportunidade",
  ["Window position & size"] = "Posição e tamanho da janela",
  ["You paid"] = "Você pagou",
  ["a discount this extreme usually means the market value is wrong, not that this is a bargain"] =
    "um desconto tão extremo costuma significar que o valor de mercado está errado, não que seja uma pechincha",
  ["auto off"] = "auto desligado",
  ["auto-synced %dh ago"] = "sincronizado automaticamente há %dh",
  ["auto-synced data for %s loaded (%s old)"] =
    "dados sincronizados de %s carregados (%s de idade)",
  ["auto-synced data stale -- /goldcap import"] =
    "os dados sincronizados estão velhos -- /goldcap import",
  ["auto: paused"] = "auto: pausado",
  ["big buy"] = "compra grande",
  ["bought %d x item %d"] = "comprados %d x item %d",
  ["bought %d x item %d after AH close"] =
    "comprados %d x item %d depois que a casa de leilões fechou",
  ["buying commodity..."] = "comprando mercadoria...",
  ["checking live price..."] = "verificando o preço ao vivo...",
  ["checking live safety..."] = "verificando a segurança ao vivo...",
  ["commodity no longer available -- someone bought it out"] =
    "a mercadoria não está mais disponível -- alguém comprou tudo",
  ["commodity purchase failed"] = "a compra da mercadoria falhou",
  ["confirmed commodity purchase failed after AH close"] =
    "a compra confirmada de mercadoria falhou depois que a casa de leilões fechou",
  ["confirming purchase..."] = "confirmando a compra...",
  ["cost basis incomplete -- set costs to get repost advice"] =
    "base de custo incompleta -- defina os custos para receber conselho de reanúncio",
  ["cost unknown"] = "custo desconhecido",
  ["data from goldcap.gg · synced %s ago"] = "dados do goldcap.gg · sincronizados há %s",
  ["due -- will be asked next pass"] = "pendente -- será consultado na próxima passagem",
  ["finish the pending buy first"] = "termine primeiro a compra pendente",
  ["full scan already in progress"] = "a varredura completa já está em andamento",
  ["full scan complete: %d deal%s from %d item group%s%s"] =
    "varredura completa concluída: %d oportunidade%s de %d grupo%s de itens%s",
  ["full scan interrupted -- confirm your purchase"] =
    "varredura completa interrompida -- confirme sua compra",
  ["full scan stalled -- press Full Scan to retry"] =
    "a varredura completa travou -- clique em Full Scan para tentar de novo",
  ["full scan stalled -- retrying shortly"] = "a varredura completa travou -- nova tentativa em breve",
  ["gone / price changed"] = "sumiu / preço mudou",
  ["identity unresolved (variant item -- not priced by design)"] =
    "identidade não resolvida (item com variantes -- sem preço de propósito)",
  ["import %dh old"] = "importação de %dh atrás",
  ["import stale -- /goldcap import or /goldcap companion"] =
    "importação velha -- /goldcap import ou /goldcap companion",
  ["imported %d items for %s (%s) — prices are live now."] =
    "importados %d itens para %s (%s) — os preços já estão valendo.",
  ["in the mail"] = "no correio",
  ["item %d"] = "item %d",
  ["item %d: %s"] = "item %d: %s",
  ["item=%d computed=%s public=%s buyable=%s reasons=%s"] =
    "item=%d computed=%s public=%s buyable=%s reasons=%s",
  ["last 24h — %d sales, %s gross, %s AH cut, %d buys, %s spent"] =
    "últimas 24 h — %d vendas, %s bruto, %s de taxa, %d compras, %s gastos",
  ["listing gone -- already bought out or price changed"] =
    "o anúncio sumiu -- já foi comprado ou o preço mudou",
  ["live safety confirmed -- click Buy to purchase"] =
    "segurança confirmada ao vivo -- clique em Buy para comprar",
  ["live verification required"] = "é preciso verificação ao vivo",
  ["manual import -- Companion keeps this fresh: /goldcap companion"] =
    "importação manual -- o Companion mantém isso atualizado: /goldcap companion",
  ["needs a fresh price -- press Refresh"] = "precisa de um preço novo -- clique em Refresh",
  ["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."] =
    "sem confirmação do servidor -- a compra ainda pode ter passado, confira seu correio. Fechar isto não desfaz.",
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
  ["not ready to cancel"] = "ainda não dá para cancelar",
  ["not ready to post"] = "ainda não dá para anunciar",
  ["nothing listed"] = "nada anunciado",
  ["of %d"] = "de %d",
  ["or paste a string from goldcap.gg with /goldcap import."] =
    "ou cole uma string do goldcap.gg com /goldcap import.",
  ["placing bid..."] = "dando o lance...",
  ["price confirmed -- click Buy to purchase"] = "preço confirmado -- clique em Buy para comprar",
  ["price rose %.1fx — still safe, confirm"] = "o preço subiu %.1fx — ainda seguro, confirme",
  ["purchase canceled"] = "compra cancelada",
  ["purchase pending exact cost"] = "compra esperando o custo exato",
  ["purchase total unavailable — inspect mailbox"] =
    "não dá para obter o total da compra — confira a caixa de correio",
  ["quote %s -- click Confirm to buy"] = "cotação %s -- clique em Confirm para comprar",
  ["quote %ss ago"] = "cotação de %ss atrás",
  ["quote expired -- Refresh to re-check the price"] =
    "cotação expirada -- clique em Refresh para conferir o preço de novo",
  ["recent sales (newest first):"] = "vendas recentes (mais novas primeiro):",
  ["region %s — bundled: %d items (%s), imported: %s"] =
    "região %s — inclusos: %d itens (%s), importados: %s",
  ["relisting now would lock in a loss or a stall -- hold"] =
    "reanunciar agora travaria um prejuízo ou uma parada -- segure",
  ["removed %d duplicate purchase record%s left by a mail-scan bug"] =
    "apagados %d registro%s de compra duplicados deixados por uma falha na leitura do correio",
  ["removed %d duplicate sale record%s left by a mail-scan bug"] =
    "apagados %d registro%s de venda duplicados deixados por uma falha na leitura do correio",
  ["s. Rows it refuses are hidden. Buying always stays a click you make."] =
    " s. As linhas recusadas ficam ocultas. Comprar continua sendo sempre um clique seu.",
  ["sale proceeds pending"] = "receita da venda pendente",
  ["scanned %d listings over %d passes"] = "varridos %d anúncios em %d passagens",
  ["scanning auction house..."] = "varrendo a casa de leilões...",
  ["scanning… %d results · %d deals%s"] = "varrendo… %d resultados · %d oportunidades%s",
  ["search the Auction House yourself, or check your mail. Click to toggle."] =
    "procure você mesmo na casa de leilões, ou confira o correio. Clique para alternar.",
  ["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"] =
    "sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s",
  ["sells %s/day"] = "vende %s/dia",
  ["session: %d snipes, spent %s, ~%s est. profit"] =
    "sessão: %d capturas, %s gastos, ~%s de lucro est.",
  ["sniped (listing changed on rescan)"] = "levaram na frente (o anúncio mudou na nova varredura)",
  ["starting full scan..."] = "iniciando a varredura completa...",
  ["stopped watching %s"] = "parei de acompanhar %s",
  ["the Companion wrote prices this addon could not read --"] =
    "o Companion escreveu preços que este addon não conseguiu ler --",
  ["the import failed (%s)"] = "a importação falhou (%s)",
  ["throttle ready=%s · sniper busy=%s · empty answers resting=%d"] =
    "throttle ready=%s · sniper busy=%s · empty answers resting=%d",
  ["unknown evidence"] = "evidência desconhecida",
  ["waiting for previous commodity purchase to settle"] =
    "esperando a compra de mercadoria anterior ser liquidada",
  ["waiting for previous search result to settle"] = "esperando o resultado da busca anterior",
  ["waiting for server... full scan will start automatically"] =
    "esperando o servidor... a varredura completa começa sozinha",
  ["watching %s closely -- re-checked every few seconds"] =
    "acompanhando %s de perto -- reconferido a cada poucos segundos",
  ["would sell at a loss"] = "venderia com prejuízo",
  ["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."] =
    "você ainda não importou os preços do reino -- instale o GoldCap Companion (/goldcap companion) ou cole uma string do goldcap.gg (/goldcap import).",
  ["you should clear about %s"] = "você deve embolsar cerca de %s",
  ["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."] =
    "sua importação tem %d horas -- os preços podem estar errados. Cole uma string nova do goldcap.gg (/goldcap import).",
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
  ["≈ goldcap.gg market value — no live quote yet"] =
    "≈ valor de mercado do goldcap.gg — ainda sem cotação ao vivo",
}
