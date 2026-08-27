local _, GC = ...

-- The English base. Entries here are identity mappings and exist so the coverage test has a
-- canonical key list to measure every other language against -- lookups never need them,
-- because an absent key already returns itself.
GC.Locales.enUS = {}
