-- ATMEN (bekor qilish) cheklari navbati — zakaz/taom atmen qilinganda
-- tegishli bo'lim printeridan "ОТМЕНА" cheki chiqadi (print-agent oladi)
CREATE TABLE IF NOT EXISTS cancel_tickets (
  id SERIAL PRIMARY KEY,
  order_id INTEGER,
  table_name TEXT,
  waiter_name TEXT,
  station_id INTEGER,
  items TEXT,              -- JSON: [{name, quantity}]
  printed BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cancel_tickets_pending
  ON cancel_tickets (printed, id);
