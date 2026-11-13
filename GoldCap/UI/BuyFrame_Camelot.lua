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

-- A browse variant's version, for a line that names its versions (GC.Buy._StepByName): the bonus
-- key of the key's sample link. The HERO probe (P3, 13.11) read GetItemKeySampleLink for every one
-- of 53 variants right after the browse, each a key made with MakeItemKey from the variant's level
-- and suffix, and its bonus ID agreed with the rows the key's own search returned; after that
-- search it was sometimes nil (Carving Knife). Then the session's own record of the key's rows
-- answers (GC.Buy._KnownVersion: every searched key held one version, 9 of 9), which keeps each
-- sample answer too: the browse is reused for a minute, and a read after a search would otherwise
-- arm every cheaper variant again to learn it is another version. The key's suffix is no fixed
-- offset from the bonus ID (14308 is 12728, 14315 is 12920), so neither is worked out.
function GC.Buy._VersionOfKey(itemID, lot)
  local ah = C_AuctionHouse
  local bonusKey = GC.ForeverGear and GC.ForeverGear.BonusKey
  if bonusKey and type(ah) == "table" and type(ah.GetItemKeySampleLink) == "function"
      and type(ah.MakeItemKey) == "function" then
    local ok, key = pcall(ah.MakeItemKey, itemID, lot.itemLevel or 0, lot.itemSuffix or 0, lot.species or 0)
    if ok and type(key) == "table" then
      local read, link = pcall(ah.GetItemKeySampleLink, key)
      local ver = read and bonusKey(link) or nil
      if ver then
        GC.Buy._keyVersions[GC.Buy._VersionKey(itemID, lot)] = ver
        return ver
      end
    end
  end
  return GC.Buy._KnownVersion(itemID, lot)
end
