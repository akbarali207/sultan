-- Фирменный чай - 7 ta taom
INSERT INTO menu_categories (name) VALUES ('Фирменный чай') ON CONFLICT DO NOTHING;

-- Чай мята с мёдом (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай мята с мёдом', 150 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мёд', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мёд%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай мята с мёдом' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мёд%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лимон', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лимон%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай мята с мёдом' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Лимон%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.008 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай мята с мёдом' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сахар\ Нават', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сахар\ Нават%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай мята с мёдом' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Сахар\ Нават%' LIMIT 1;

-- Чай наглый фрукт (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай наглый фрукт', 150 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Апельсин', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Апельсин%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.022 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай наглый фрукт' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Апельсин%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.008 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай наглый фрукт' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лимон', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лимон%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай наглый фрукт' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Лимон%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мёд', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мёд%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай наглый фрукт' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мёд%' LIMIT 1;

-- Чай Имбирный с лимоном (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай Имбирный с лимоном', 150 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Имбир свежый', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Имбир свежый%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Имбирный с лимоном' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Имбир свежый%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лимон', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лимон%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.025 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Имбирный с лимоном' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Лимон%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мёд', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мёд%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Имбирный с лимоном' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мёд%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Чай черный', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Чай черный%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.005 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Имбирный с лимоном' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Чай черный%' LIMIT 1;

-- Чай с облипихой (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай с облипихой', 150 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Облипиховый сироп', 'litr', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Облипиховый сироп%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.1 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай с облипихой' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Облипиховый сироп%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мёд', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мёд%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай с облипихой' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мёд%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Чай черный', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Чай черный%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай с облипихой' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Чай черный%' LIMIT 1;

-- Чай Фруктовый (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай Фруктовый', 150 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Яблоко', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Яблоко%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Фруктовый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Яблоко%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Апельсин', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Апельсин%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.022 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Фруктовый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Апельсин%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мёд', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мёд%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.04 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Фруктовый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мёд%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Чай Фруктовый пакети', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Чай Фруктовый пакети%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 1.0 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Фруктовый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Чай Фруктовый пакети%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Мята', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Мята%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.006 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Фруктовый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Мята%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лимон', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лимон%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Фруктовый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Лимон%' LIMIT 1;

-- Чай с Лимоном (100 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай с Лимоном', 100 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лимон', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лимон%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай с Лимоном' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Лимон%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сахар', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сахар%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай с Лимоном' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Сахар%' LIMIT 1;

-- Чай Малиновый (150 so'm)
INSERT INTO menu_items (category_id, name, price) SELECT id, 'Чай Малиновый', 150 FROM menu_categories WHERE name = 'Фирменный чай';
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Лимон', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Лимон%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.02 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Малиновый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Лимон%' LIMIT 1;
INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category) SELECT 'Сахар', 'kg', 0, 0, 0, 'Ингредиенты' WHERE NOT EXISTS (SELECT 1 FROM ingredients WHERE name ILIKE '%Сахар%');
INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity) SELECT m.id, i.id, 0.05 FROM menu_items m JOIN menu_categories c ON m.category_id = c.id, ingredients i WHERE m.name = 'Чай Малиновый' AND c.name = 'Фирменный чай' AND i.name ILIKE '%Сахар%' LIMIT 1;