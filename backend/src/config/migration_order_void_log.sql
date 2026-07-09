-- ============================================================
-- To'langan zakazni O'CHIRISH (void) auditi. Ilgari paid zakaz o'chirilganda
-- iz qolmasdi (ichki firibgarlik yashirilishi mumkin edi). Endi har void
-- yozib qolinadi: kim, qachon, qaysi zakaz, qancha pul, sabab.
-- ============================================================
CREATE TABLE IF NOT EXISTS order_void_log (
  id SERIAL PRIMARY KEY,
  order_id INTEGER,
  table_label TEXT,
  final_amount NUMERIC(12,2),
  paid_card NUMERIC(12,2),
  paid_cash NUMERIC(12,2),
  paid_debt NUMERIC(12,2),
  discount_percent NUMERIC(5,2),
  user_id INTEGER,
  user_name TEXT,
  reason TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_order_void_log_date ON order_void_log (created_at DESC);
