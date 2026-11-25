local _, GC = ...

-- WoW: Forever's Deals Check. Loaded by GoldCap_Camelot.toc alone, right after UI/SniperFrame.lua,
-- whose functions it replaces where Forever differs. Retail never loads it.
--
-- An item that is not a commodity has its variant keys learnt by its name before it is searched
-- (GC.Sniper._SendNaming). Forever files an item with random suffixes under one key per suffix and
-- answers its bare key with no lots: every Carving Knife and Birchwood Maul deal came back "listing
-- gone" while hundreds were up (probe 08.11). A browse by the name names each suffix's key; the
-- search then asks the cheapest one's. An item the polls or a recent browse already know is not
-- asked again, and a commodity has one key and needs none of this.
function GC.Sniper._VariantsOwed(itemID)
  if GC.Sniper._IsCommodityId(itemID) then return false end
  if GC.Sniper._PolledEntry(itemID) or GC.Sniper._NamedFresh(itemID) then return false end
  return GC.Sniper._NameOf(itemID) ~= nil
end

-- Forever bids only on a lot its current item results hold (GC.Sniper._bidNeedsItsSearch): the
-- window armed on a lot keeps the search, and a lot pushed out all the same is searched again.
GC.Sniper._bidNeedsItsSearch = true

-- A gear row priced for one version of the piece (GC.ForeverDeals._LiveRow's "Under market" row:
-- `version` is the bonus key of the lots it was measured against) is named, shown and linked as
-- that version. Named for the bare item, an Aboriginal Sash row at 3s50 against a 49s median did
-- not say which of the nine versions on the browse, 3s50 to 99s99, it meant (owner, 2026-11-25).
-- The item string is the HERO tab's (GC.ForeverGear.ItemString), whose name and stats are the full
-- link's (HERO probe P2, 13.11). "0", a version with no bonus, is the bare item.
function GC.Sniper._DealItemString(deal)
  local version = type(deal) == "table" and deal.version or nil
  if type(version) ~= "string" or version == "0" or not version:find("^%d[%d%.]*$")
      or type(deal.itemID) ~= "number" or not (GC.ForeverGear and GC.ForeverGear.ItemString) then
    return nil
  end
  return GC.ForeverGear.ItemString(deal.itemID, { bonus = version })
end
