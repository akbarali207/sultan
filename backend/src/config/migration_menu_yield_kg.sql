-- Partiya chiqishi (ВЫХОД, kg) — ТТК da qo'lda beriladi (masalan Соус Цезарь П/Ф = 0.840 кг).
-- P/F narxi/кг = jami tannarx ÷ yield_kg (syncPfCost shuni ishlatadi). NULL = porsiyalik taom.
ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS yield_kg NUMERIC;

-- Ma'lum ТТК partiya chiqishlari — faqat bo'sh bo'lsa (foydalanuvchi tahririni buzmaslik uchun, idempotent).
UPDATE menu_items SET yield_kg = 0.840 WHERE yield_kg IS NULL AND lower(btrim(name)) = 'соус цезарь п/ф';
UPDATE menu_items SET yield_kg = 6.7   WHERE yield_kg IS NULL AND lower(btrim(name)) = 'соус пицца п/ф';
UPDATE menu_items SET yield_kg = 5.65  WHERE yield_kg IS NULL AND lower(btrim(name)) IN ('катлет фарш п/ф','котлет фарш п/ф');
UPDATE menu_items SET yield_kg = 2.3   WHERE yield_kg IS NULL AND lower(btrim(name)) = 'фарш хинкали п/ф';
UPDATE menu_items SET yield_kg = 4.0   WHERE yield_kg IS NULL AND lower(btrim(name)) IN ('зажарка для чучбара ттк','зажарка ттк');
