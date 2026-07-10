-- ============================================================
-- ETAP 3.1 — Phase 1: BIRLIKLAR spravochnik (units). ADDITIVE, non-destruktiv.
-- Faqat qo'shadi: jadval + ingredients.unit_id (nullable) + backfill.
-- Matematikани O'ZGARTIRMAYDI (deductStock hali string bilan ishlaydi) — bu poydevor.
-- factor_to_base kelajakда baza-birlik hisobi uchun (hozir ishlatilmaydi).
-- ============================================================
CREATE TABLE IF NOT EXISTS units (
  id SERIAL PRIMARY KEY,
  code VARCHAR(20) NOT NULL UNIQUE,       -- kanonik: kg,l,pcs,g,ml,pack,jar,portion
  display_name VARCHAR(40) NOT NULL,
  base_code VARCHAR(20),                  -- baza birlik
  factor_to_base NUMERIC(16,6) NOT NULL DEFAULT 1
);

INSERT INTO units (code, display_name, base_code, factor_to_base) VALUES
  ('kg','кг','kg',1),
  ('g','г','kg',0.001),
  ('l','л','l',1),
  ('ml','мл','l',0.001),
  ('pcs','дона','pcs',1),
  ('pack','пакет','pack',1),
  ('jar','банка','jar',1),
  ('portion','порция','portion',1)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS unit_id INTEGER REFERENCES units(id);

-- Backfill: mavjud string yozuvларni (кг/kg, л/litr, dona/шт ...) kanonik unit_id ga bog'lash
UPDATE ingredients SET unit_id = u.id
FROM units u
WHERE ingredients.unit_id IS NULL AND u.code = (
  CASE lower(trim(ingredients.unit))
    WHEN 'кг' THEN 'kg'  WHEN 'kg' THEN 'kg'  WHEN 'kilogram' THEN 'kg'  WHEN 'килограмм' THEN 'kg'
    WHEN 'л' THEN 'l'    WHEN 'litr' THEN 'l' WHEN 'l' THEN 'l'          WHEN 'литр' THEN 'l'
    WHEN 'мл' THEN 'ml'  WHEN 'ml' THEN 'ml'
    WHEN 'dona' THEN 'pcs' WHEN 'шт' THEN 'pcs' WHEN 'pcs' THEN 'pcs'    WHEN 'штук' THEN 'pcs'
    WHEN 'gr' THEN 'g'   WHEN 'г' THEN 'g'    WHEN 'gram' THEN 'g'       WHEN 'грамм' THEN 'g'
    WHEN 'пакет' THEN 'pack' WHEN 'pachka' THEN 'pack' WHEN 'упакофка' THEN 'pack' WHEN 'упаковка' THEN 'pack'
    WHEN 'банка' THEN 'jar'
    WHEN 'порц' THEN 'portion'
    ELSE NULL END);
