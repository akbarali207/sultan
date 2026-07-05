-- SKLADLAR (alohida omborlar)
CREATE TABLE IF NOT EXISTS warehouses (
  id SERIAL PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Ingredientga sklad bog'lash
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS warehouse_id INTEGER REFERENCES warehouses(id);

-- Boshlang'ich skladlar (idempotent — qayta ishga tushsa dublikat bo'lmaydi)
INSERT INTO warehouses (name)
SELECT v.name FROM (VALUES
  ('Sklad 1 - Oshxona'),
  ('Sklad 2 - Shashlik'),
  ('Sklad 3 - Somsa')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM warehouses w WHERE w.name = v.name);

-- Mavjud barcha ingredientlarni Sklad 1 (Oshxona) ga biriktirish
UPDATE ingredients
SET warehouse_id = (SELECT id FROM warehouses WHERE name = 'Sklad 1 - Oshxona')
WHERE warehouse_id IS NULL;
