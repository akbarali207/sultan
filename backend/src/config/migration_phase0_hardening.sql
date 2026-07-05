-- ============================================================
-- Faza 0: pul yo'lini mustahkamlash (idempotentlik + invariantlar)
-- ============================================================

-- Idempotentlik kalitlari: mijoz har pul operatsiyasiga UUID yuboradi.
-- Takror so'rov (tarmoq retry, ikki marta bosish) saqlangan javobni oladi.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key VARCHAR(64) PRIMARY KEY,
  user_id INTEGER,
  method VARCHAR(8) NOT NULL,
  path VARCHAR(200) NOT NULL,
  status_code INTEGER,
  response JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_idem_created ON idempotency_keys (created_at);

-- Davomat eventlari dedup jurnali (restart'dan keyin ham takror yozilmaydi).
-- Kalit: user_id + event vaqti.
CREATE TABLE IF NOT EXISTS attendance_events (
  event_key VARCHAR(120) PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Pul invariantlari (oxirgi himoya chegarasi — kod xato qilsa ham baza rad etadi):
-- 1) Bitta zakaz uchun har usulda (karta/naqd) faqat BITTA tushum yozuvi
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cash_tx_order_method
  ON cash_transactions (ref_id, method) WHERE source = 'order';
-- 2) Bitta zakazga faqat BITTA qarz yozuvi
CREATE UNIQUE INDEX IF NOT EXISTS uniq_debt_per_order
  ON debts (order_id) WHERE order_id IS NOT NULL;
-- 3) Bitta stolda faqat BITTA ochiq zakaz (createOrder merge invariantining baza darajasidagi kafolati)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_open_order_per_table
  ON orders (table_id) WHERE status <> 'paid' AND table_id IS NOT NULL;
