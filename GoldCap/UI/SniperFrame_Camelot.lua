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
