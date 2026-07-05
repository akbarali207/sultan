-- Қўшимчалар - 6 ta taom
INSERT INTO menu_categories (name) VALUES ('Қўшимчалар') ON CONFLICT DO NOTHING;

-- Каймак (50 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Каймак', 50 FROM menu_categories WHERE name = 'Қўшимчалар';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Каймак', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Каймак%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Каймак' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Каймак%' LIMIT 1;

-- Картошка Фри (100 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Картошка Фри', 100 FROM menu_categories WHERE name = 'Қўшимчалар';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Картофель фри', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Картофель фри%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.2 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Картошка Фри' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Картофель фри%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Кетчуп', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Кетчуп%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Картошка Фри' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Кетчуп%' LIMIT 1;

-- Картошка шарик (100 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Картошка шарик', 100 FROM menu_categories WHERE name = 'Қўшимчалар';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'КартофельШарик', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%КартофельШарик%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.2 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Картошка шарик' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%КартофельШарик%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Кетчуп', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Кетчуп%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Картошка шарик' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Кетчуп%' LIMIT 1;

-- Картошка Айдахо (100 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Картошка Айдахо', 100 FROM menu_categories WHERE name = 'Қўшимчалар';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Картофель по деревенсий', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Картофель по деревенсий%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.2 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Картошка Айдахо' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Картофель по деревенсий%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Кетчуп', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Кетчуп%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Картошка Айдахо' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Кетчуп%' LIMIT 1;

-- Казы 100гр (50 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Казы 100гр', 50 FROM menu_categories WHERE name = 'Қўшимчалар';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Казы', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Казы%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Казы 100гр' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Казы%' LIMIT 1;

-- Катлет Фарш П/Ф (3293.5 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Катлет Фарш П/Ф', 3293.5 FROM menu_categories WHERE name = 'Қўшимчалар';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мясо говядина', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мясо говядина%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 3.3 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Катлет Фарш П/Ф' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Мясо говядина%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Филе курица', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Филе курица%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.25 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Катлет Фарш П/Ф' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Филе курица%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Яйцо', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Яйцо%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 3.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Катлет Фарш П/Ф' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Яйцо%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лепешка', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лепешка%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.6 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Катлет Фарш П/Ф' AND c.name = 'Қўшимчалар' AND i.name ILIKE '%Лепешка%' LIMIT 1;