local _, GC = ...

-- WoW: Forever's BUY. Loaded by GoldCap_Camelot.toc alone, right after UI/BuyFrame.lua, whose
-- functions it replaces where Forever differs. Retail never loads it.
--
-- A gear line (anything the client will not sell as a commodity: recipes, book pages, gear) reads
-- its lots with a buy search on the item's key. Forever's server takes a sell search for an item
-- and answers it with nothing: no rows and no ITEM_SEARCH_RESULTS_UPDATED, so the line never got a
-- price and nothing on a list could be bought. In game, with the item's details loaded each time,
-- two sell searches for a Shredder Operating Manual page went unanswered and two buy searches for
-- it were answered at once (probe 08.11). A buy search answers for that one key's lots, so an item
-- listed in several variants (a random suffix) is read for the variant its bare key names.
function GC.Buy._SendLotRead(key, sorts)
  C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

-- A gear line whose bare key answered no rows may be gear with random suffixes ("... of the
-- Eagle"), which Forever files under one key per suffix: the bare key answers none of their lots.
-- A Carving Knife's 2140/11/0/0 answered rows=0 while 2140/11/14300/0 held 13 lots, and a browse by
-- its name listed 24 variants with lots up (probe 08.11). The read goes on by the item's name
-- (GC.Buy._StepByName, UI/BuyFrame.lua).
function GC.Buy._ReadByName()
  return GC.Sniper ~= nil and GC.Sniper._SendNaming ~= nil
end
