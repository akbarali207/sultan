-- ============================================================
-- PARTIYA BACKFILL: mavjud qoldiqlardan sintetik boshlang'ich partiya.
-- Har musbat qoldiqli ingredient uchun BITTA partiya ochiladi:
-- miqdor = joriy qoldiq, narx = joriy o'rtacha narx, to'liq to'langan
-- (tarixiy zaxira qarzsiz hisoblanadi). Minusdagi qoldiqlar partiyasiz
-- qoladi (minus ATAYLAB — ingredient darajasida saqlanadi).
-- Idempotent: allaqachon partiyasi bor ingredientga qayta ochilmaydi.
-- ============================================================

INSERT INTO stock_lots
  (ingredient_id, quantity, unit, unit_cost, total_cost, used_quantity,
   paid_amount, status, note, purchase_date, received_at)
SELECT
  i.id,
  i.stock_quantity,
  i.unit,
  COALESCE(i.price_per_unit, 0),
  ROUND(i.stock_quantity * COALESCE(i.price_per_unit, 0), 2),
  0,
  ROUND(i.stock_quantity * COALESCE(i.price_per_unit, 0), 2),
  'active',
  'Boshlang''ich qoldiq (partiya tizimiga o''tish)',
  CURRENT_DATE,
  NOW()
FROM ingredients i
WHERE i.stock_quantity > 0
  AND NOT EXISTS (SELECT 1 FROM stock_lots l WHERE l.ingredient_id = i.id);

-- lot_code ni id dan generatsiya qilamiz (backfill + bo'sh qolganlar)
UPDATE stock_lots
SET lot_code = 'LOT-' || LPAD(id::text, 6, '0')
WHERE lot_code IS NULL;
