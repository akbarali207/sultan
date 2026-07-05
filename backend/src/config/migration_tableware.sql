-- IDISH-TOVOQLAR (tableware) inventarizatsiyasi uchun

-- Idishlar katalogi: piola, tovoq, choynak, lagan, stakan, pichoq, qoshiq, vilka va h.k.
CREATE TABLE IF NOT EXISTS tableware (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  unit VARCHAR(20) DEFAULT 'dona',
  quantity NUMERIC(10,2) DEFAULT 0,   -- joriy mavjud soni
  price NUMERIC(12,2) DEFAULT 0,      -- bittasining narxi (singan/yo'qolgan zararni hisoblash uchun)
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Inventarizatsiya turi: 'ingredient' (oziq-ovqat, eski xulq) | 'tableware' (idishlar)
ALTER TABLE inventory_checks ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'ingredient';

-- inventory_items endi idishlarga ham bog'lana oladi
ALTER TABLE inventory_items ALTER COLUMN ingredient_id DROP NOT NULL;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS tableware_id INT REFERENCES tableware(id) ON DELETE CASCADE;

-- Namuna idishlar (faqat katalog bo'sh bo'lsa)
INSERT INTO tableware (name, unit, quantity, price)
SELECT v.name, 'dona', 0, 0 FROM (VALUES
  ('Piola'),
  ('Choy piola'),
  ('Katta tovoq'),
  ('Kichik tovoq'),
  ('Lagan'),
  ('Choynak'),
  ('Stakan'),
  ('Qoshiq'),
  ('Vilka'),
  ('Pichoq')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM tableware);
