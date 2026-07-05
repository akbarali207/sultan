-- KUNLIK KUZAT (somsa kabi taomlar): ertalab N dona kiritiladi, sotilgan/qolgan ko'rinadi.
-- Taomga "kunlik kuzat" belgisi:
ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS daily_tracked BOOLEAN DEFAULT false;

-- Har kunlik boshlang'ich son (biz_date = biznes kun, 02:30 chegarasida)
CREATE TABLE IF NOT EXISTS daily_stock (
  id SERIAL PRIMARY KEY,
  menu_item_id INTEGER REFERENCES menu_items(id) ON DELETE CASCADE,
  biz_date DATE NOT NULL,
  opening_qty NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (menu_item_id, biz_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_stock_date ON daily_stock (biz_date);
