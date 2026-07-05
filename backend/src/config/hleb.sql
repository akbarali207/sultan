-- Хлеб. изделия - 12 ta taom
INSERT INTO menu_categories (name) VALUES ('Хлеб. изделия') ON CONFLICT DO NOTHING;

-- Теста для хачапури и боорсок (450.76 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Теста для хачапури и боорсок', 450.76 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мука', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мука%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 4.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Мука%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Молоко', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Молоко%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Молоко%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сахар', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сахар%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.1 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сахар%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Соль', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Соль%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Соль%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Дрож', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Дрож%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.012 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Дрож%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Майонез', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Майонез%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.01 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Майонез%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Оливковое масло', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Оливковое масло%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.3 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Оливковое масло%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Вода', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Вода%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хачапури и боорсок' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Вода%' LIMIT 1;

-- Хачапури по Ажарский (300 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Хачапури по Ажарский', 300 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста 250гр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста 250гр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.25 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хачапури по Ажарский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста 250гр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сыр моцарелла', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сыр моцарелла%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.2 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хачапури по Ажарский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сыр моцарелла%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Яйцо', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Яйцо%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хачапури по Ажарский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Яйцо%' LIMIT 1;

-- Хачапури по Мегрельски (300 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Хачапури по Мегрельски', 300 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста 250гр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста 250гр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.25 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хачапури по Мегрельски' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста 250гр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сыр моцарелла', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сыр моцарелла%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.2 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хачапури по Мегрельски' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сыр моцарелла%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Яйцо', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Яйцо%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хачапури по Мегрельски' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Яйцо%' LIMIT 1;

-- Боорсок с каймаком (200 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Боорсок с каймаком', 200 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста 250гр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста 250гр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.25 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Боорсок с каймаком' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста 250гр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Каймак', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Каймак%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.035 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Боорсок с каймаком' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Каймак%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Молоко', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Молоко%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.015 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Боорсок с каймаком' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Молоко%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сахарный пудра', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сахарный пудра%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.01 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Боорсок с каймаком' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сахарный пудра%' LIMIT 1;

-- Теста кутабы П/Ф (132.96 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Теста кутабы П/Ф', 132.96 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мука', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мука%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 2.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста кутабы П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Мука%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Соль', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Соль%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста кутабы П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Соль%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Яйцо', 'dona', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Яйцо%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 2.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста кутабы П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Яйцо%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Вода', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Вода%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.7 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста кутабы П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Вода%' LIMIT 1;

-- Кутабы с мясом (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Кутабы с мясом', 150 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста 60гр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста 60гр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с мясом' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста 60гр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сыр моцарелла', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сыр моцарелла%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с мясом' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сыр моцарелла%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мясо говядина', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мясо говядина%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.034 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с мясом' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Мясо говядина%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Масло сливочная', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Масло сливочная%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с мясом' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Масло сливочная%' LIMIT 1;

-- Кутабы с сыром (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Кутабы с сыром', 150 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста 60гр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста 60гр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с сыром' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста 60гр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сыр моцарелла', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сыр моцарелла%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с сыром' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сыр моцарелла%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Масло сливочная', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Масло сливочная%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с сыром' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Масло сливочная%' LIMIT 1;

-- Кутабы с зеленью (140 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Кутабы с зеленью', 140 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста 60гр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста 60гр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.06 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с зеленью' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста 60гр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сыр моцарелла', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сыр моцарелла%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с зеленью' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Сыр моцарелла%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лук зеленый', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лук зеленый%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.01 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с зеленью' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Лук зеленый%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Масло сливочная', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Масло сливочная%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Кутабы с зеленью' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Масло сливочная%' LIMIT 1;

-- Теста для хинкали П/Ф (121.25 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Теста для хинкали П/Ф', 121.25 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мука', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мука%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 2.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Мука%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Вода', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Вода%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.65 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Вода%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Соль', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Соль%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Теста для хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Соль%' LIMIT 1;

-- Фарш хинкали П/Ф (396 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Фарш хинкали П/Ф', 396 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мяса говядина', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мяса говядина%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Мяса говядина%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лук репка', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лук репка%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.625 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Лук репка%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Пурец черный молотый', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Пурец черный молотый%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.006 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Пурец черный молотый%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Кориандр', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Кориандр%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.004 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Кориандр%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Соль', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Соль%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.022 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Соль%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Вода', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Вода%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.7 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Вода%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Чеснок', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Чеснок%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Чеснок%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Зелень (Кинза)', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Зелень (Кинза)%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Фарш хинкали П/Ф' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Зелень (Кинза)%' LIMIT 1;

-- Хинкали по грузинский (0 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Хинкали по грузинский', 0 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста ТТК', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста ТТК%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.16 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хинкали по грузинский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста ТТК%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Фарш хинкали П/Ф', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Фарш хинкали П/Ф%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.2 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хинкали по грузинский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Фарш хинкали П/Ф%' LIMIT 1;

-- Хинкали по грузинский (0 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Хинкали по грузинский', 0 FROM menu_categories WHERE name = 'Хлеб. изделия';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Теста ТТК', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Теста ТТК%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хинкали по грузинский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Теста ТТК%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Фарш хинкали П/Ф', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Фарш хинкали П/Ф%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Хинкали по грузинский' AND c.name = 'Хлеб. изделия' AND i.name ILIKE '%Фарш хинкали П/Ф%' LIMIT 1;