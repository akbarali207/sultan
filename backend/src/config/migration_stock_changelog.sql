-- Sklad mahsulotini tahrirlash tarixi (audit) — kim, nima, nega o'zgartirdi
CREATE TABLE IF NOT EXISTS stock_change_log (
  id SERIAL PRIMARY KEY,
  ingredient_id INTEGER,
  user_id INTEGER,
  user_name TEXT,
  changes TEXT,           -- nima o'zgardi (eski -> yangi)
  reason TEXT NOT NULL,   -- nega o'zgartirildi (majburiy)
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_change_log_ing
  ON stock_change_log (ingredient_id, created_at DESC);
