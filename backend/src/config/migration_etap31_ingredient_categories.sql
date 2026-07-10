-- ============================================================
-- ETAP 3.1 — Phase 2: INGREDIENT KATEGORIYALAR spravochnik + is_pf. ADDITIVE.
-- 'П/Ф' magic-string o'rniga typed is_pf boolean (poydevor; o'qish hali stringда).
-- Faqat qo'shadi: jadval + ingredients.category_id + is_pf + backfill. Non-destruktiv.
-- ============================================================
CREATE TABLE IF NOT EXISTS ingredient_categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(80) NOT NULL UNIQUE,
  is_pf BOOLEAN DEFAULT false,
  is_retail BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Seed: mavjud DISTINCT category stringlaridan (bo'sh emas)
INSERT INTO ingredient_categories (name, is_pf)
SELECT DISTINCT trim(category), (trim(category) = 'П/Ф')
FROM ingredients
WHERE category IS NOT NULL AND trim(category) <> ''
ON CONFLICT (name) DO NOTHING;

ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES ingredient_categories(id);
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS is_pf BOOLEAN DEFAULT false;

-- Backfill: string -> category_id
UPDATE ingredients i SET category_id = ic.id
FROM ingredient_categories ic
WHERE i.category_id IS NULL AND trim(i.category) = ic.name;

-- is_pf: 'П/Ф' stringли YOKI pf menu_item ga bog'langan ingredientlar
UPDATE ingredients SET is_pf = true
WHERE is_pf = false AND category IS NOT NULL AND trim(category) = 'П/Ф';
UPDATE ingredients i SET is_pf = true
FROM menu_items m
WHERE m.ingredient_id = i.id AND m.type = 'pf' AND i.is_pf = false;
