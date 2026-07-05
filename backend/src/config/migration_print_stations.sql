-- BO'LIMLAR (print stations) — har bo'lim = bitta oshxona printeri
CREATE TABLE IF NOT EXISTS print_stations (
  id SERIAL PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  printer_ip VARCHAR(50),            -- LAN printer IP (null bo'lsa chek faylga yoziladi)
  printer_port INTEGER DEFAULT 9100,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Taom qaysi bo'lim printeriga chiqishi
ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS station_id INTEGER REFERENCES print_stations(id);

-- Zakaz chop etilganmi (print-agent uchun)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS printed BOOLEAN DEFAULT false;

-- Boshlang'ich bo'limlar (faqat jadval bo'sh bo'lsa)
INSERT INTO print_stations (name)
SELECT v.name FROM (VALUES
  ('Oshxona'),
  ('Shashlik'),
  ('Somsa'),
  ('Bar')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM print_stations);

-- Mavjud taomlarni kategoriya nomiga qarab bo'limga biriktirish
UPDATE menu_items mi SET station_id = (SELECT id FROM print_stations WHERE name='Shashlik' LIMIT 1)
FROM menu_categories c
WHERE mi.category_id = c.id AND c.name ILIKE '%шашлык%' AND mi.station_id IS NULL;

UPDATE menu_items mi SET station_id = (SELECT id FROM print_stations WHERE name='Somsa' LIMIT 1)
FROM menu_categories c
WHERE mi.category_id = c.id AND (c.name ILIKE '%сомса%' OR c.name ILIKE '%somsa%') AND mi.station_id IS NULL;

UPDATE menu_items mi SET station_id = (SELECT id FROM print_stations WHERE name='Bar' LIMIT 1)
FROM menu_categories c
WHERE mi.category_id = c.id AND (
  c.name ILIKE '%бар%' OR c.name ILIKE '%napitki%' OR c.name ILIKE '%напит%'
  OR c.name ILIKE '%десерт%' OR c.name ILIKE '%чай%'
) AND mi.station_id IS NULL;

-- Qolganlari → Oshxona
UPDATE menu_items mi SET station_id = (SELECT id FROM print_stations WHERE name='Oshxona' LIMIT 1)
WHERE mi.station_id IS NULL;
