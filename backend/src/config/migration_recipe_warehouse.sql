-- Retseptdagi ingredientlarni tegishli skladga biriktirish (bir martalik)

-- SHASHLIK: "Шашлык" kategoriyasidagi taomlar retseptidagi ingredientlar -> Sklad 2
UPDATE ingredients SET warehouse_id = (SELECT id FROM warehouses WHERE name='Sklad 2 - Shashlik')
WHERE id IN (
  SELECT DISTINCT ri.ingredient_id
  FROM recipe_items ri
  JOIN menu_items mi ON ri.menu_item_id = mi.id
  JOIN menu_categories mc ON mi.category_id = mc.id
  WHERE mc.name ILIKE '%шашлык%' OR mc.name ILIKE '%shashlik%'
);

-- SOMSA: nomida "сомса"/"somsa" bo'lgan taomlar retseptidagi ingredientlar -> Sklad 3
UPDATE ingredients SET warehouse_id = (SELECT id FROM warehouses WHERE name='Sklad 3 - Somsa')
WHERE id IN (
  SELECT DISTINCT ri.ingredient_id
  FROM recipe_items ri
  JOIN menu_items mi ON ri.menu_item_id = mi.id
  WHERE mi.name ILIKE '%сомса%' OR mi.name ILIKE '%somsa%'
);
