-- ETAP 3.1 — ingredients.is_active (soft-delete). ADDITIVE, non-destruktiv.
-- Bog'langan mahsulotni o'chirib bo'lmasdi (FK) -> endi ARXIVLANADI (is_active=false), skladdan ketadi.
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
