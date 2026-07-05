-- Десерты - 7 ta taom
INSERT INTO menu_categories (name) VALUES ('Десерты') ON CONFLICT DO NOTHING;

-- теста венской вафли (49.25 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'теста венской вафли', 49.25 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'сахар', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%сахар%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'теста венской вафли' AND c.name = 'Десерты' AND i.name ILIKE '%сахар%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'соль', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%соль%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.002 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'теста венской вафли' AND c.name = 'Десерты' AND i.name ILIKE '%соль%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'ванилин', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%ванилин%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.002 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'теста венской вафли' AND c.name = 'Десерты' AND i.name ILIKE '%ванилин%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'яйцо', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%яйцо%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 2.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'теста венской вафли' AND c.name = 'Десерты' AND i.name ILIKE '%яйцо%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'молоко', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%молоко%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.3 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'теста венской вафли' AND c.name = 'Десерты' AND i.name ILIKE '%молоко%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'разрыхлитель', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%разрыхлитель%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.009 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'теста венской вафли' AND c.name = 'Десерты' AND i.name ILIKE '%разрыхлитель%' LIMIT 1;

-- Венская вафли с фруктовым ассорти (480 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Венская вафли с фруктовым ассорти', 480 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'вафли', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%вафли%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%вафли%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'киви', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%киви%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%киви%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'банан', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%банан%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.15 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%банан%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Яблоко', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Яблоко%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%Яблоко%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'шоколад', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%шоколад%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.1 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%шоколад%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'ананас', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%ананас%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с фруктовым ассорти' AND c.name = 'Десерты' AND i.name ILIKE '%ананас%' LIMIT 1;

-- Венская вафли классический (180 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Венская вафли классический', 180 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'вафли', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%вафли%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли классический' AND c.name = 'Десерты' AND i.name ILIKE '%вафли%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'шоколад', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%шоколад%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли классический' AND c.name = 'Десерты' AND i.name ILIKE '%шоколад%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли классический' AND c.name = 'Десерты' AND i.name ILIKE '%Мята%' LIMIT 1;

-- Венская вафли банановый (200 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Венская вафли банановый', 200 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'вафли', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%вафли%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли банановый' AND c.name = 'Десерты' AND i.name ILIKE '%вафли%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'шоколад', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%шоколад%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли банановый' AND c.name = 'Десерты' AND i.name ILIKE '%шоколад%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли банановый' AND c.name = 'Десерты' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'банан', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%банан%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.15 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли банановый' AND c.name = 'Десерты' AND i.name ILIKE '%банан%' LIMIT 1;

-- Венская вафли ананасовый (200 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Венская вафли ананасовый', 200 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'вафли', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%вафли%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли ананасовый' AND c.name = 'Десерты' AND i.name ILIKE '%вафли%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'шоколад', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%шоколад%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли ананасовый' AND c.name = 'Десерты' AND i.name ILIKE '%шоколад%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли ананасовый' AND c.name = 'Десерты' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'ананас', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%ананас%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли ананасовый' AND c.name = 'Десерты' AND i.name ILIKE '%ананас%' LIMIT 1;

-- Венская вафли с киви (200 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Венская вафли с киви', 200 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'вафли', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%вафли%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с киви' AND c.name = 'Десерты' AND i.name ILIKE '%вафли%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'шоколад', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%шоколад%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с киви' AND c.name = 'Десерты' AND i.name ILIKE '%шоколад%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с киви' AND c.name = 'Десерты' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'киви', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%киви%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с киви' AND c.name = 'Десерты' AND i.name ILIKE '%киви%' LIMIT 1;

-- Венская вафли с клубникой (250 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Венская вафли с клубникой', 250 FROM menu_categories WHERE name = 'Десерты';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'вафли', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%вафли%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с клубникой' AND c.name = 'Десерты' AND i.name ILIKE '%вафли%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'шоколад', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%шоколад%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с клубникой' AND c.name = 'Десерты' AND i.name ILIKE '%шоколад%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с клубникой' AND c.name = 'Десерты' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'клубника', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%клубника%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Венская вафли с клубникой' AND c.name = 'Десерты' AND i.name ILIKE '%клубника%' LIMIT 1;