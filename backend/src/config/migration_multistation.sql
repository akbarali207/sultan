-- KO'P-BO'LIMLI TAOM: bitta taom bir nechta bo'limga (sex) chek chiqarishi mumkin.
-- Misol: steak -> goryachiy sex + shashlik sexi.
CREATE TABLE IF NOT EXISTS menu_item_stations (
  id SERIAL PRIMARY KEY,
  menu_item_id INTEGER NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  station_id INTEGER NOT NULL REFERENCES print_stations(id) ON DELETE CASCADE,
  UNIQUE (menu_item_id, station_id)
);

-- Mavjud taomlarning station_id sini junction'ga ko'chir (eski moslik)
INSERT INTO menu_item_stations (menu_item_id, station_id)
SELECT id, station_id FROM menu_items WHERE station_id IS NOT NULL
ON CONFLICT (menu_item_id, station_id) DO NOTHING;
