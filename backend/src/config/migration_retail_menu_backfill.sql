-- RETAIL BACKFILL: sotish narxi > 0 bo'lgan ingredientlar (bar/tayyor tovar) uchun menyu yozuvi
-- YO'Q bo'lsa — yaratamiz, toki ular SOTILADIGAN bo'lsin va sotilganда COGS (tannarx = price_per_unit)
-- to'g'ri chiqsin. Ilgari "mahsulot qo'shish" oynasi faqat sklad yozuvini yaratardi, menyu yozuvini emas
-- (shuning uchun MEDOVIK kabi tovarlarni ofitsant pробить qilолмайди edi). createIngredient endi tuzatildi;
-- bu — allaqachon qo'shilganlarни tiklaydi. Idempotent (NOT EXISTS + schema_migrations).
-- Menyu kategoriyasi: ingredient.category nomiga mos → 'Бар' → topilmasa birinchi kategoriya (INNER JOIN majburiy).

INSERT INTO menu_items (category_id, name, price, type, ingredient_id, is_active)
SELECT
  COALESCE(
    (SELECT mc.id FROM menu_categories mc
      WHERE mc.name = i.category
         OR (i.category IS NOT NULL AND mc.name ILIKE '%'||i.category||'%')
         OR (i.category IS NOT NULL AND i.category ILIKE '%'||mc.name||'%')
      ORDER BY (mc.name = i.category) DESC, mc.id LIMIT 1),
    (SELECT id FROM menu_categories WHERE name ILIKE '%бар%' ORDER BY id LIMIT 1),
    (SELECT id FROM menu_categories ORDER BY id LIMIT 1)
  ) AS category_id,
  i.name,
  i.selling_price,
  'product',
  i.id,
  true
FROM ingredients i
WHERE COALESCE(i.selling_price, 0) > 0
  AND NOT EXISTS (
    SELECT 1 FROM menu_items mi WHERE mi.ingredient_id = i.id AND mi.type = 'product'
  )
  AND EXISTS (SELECT 1 FROM menu_categories); -- kamida bitta menyu kategoriyasi bo'lishi shart
