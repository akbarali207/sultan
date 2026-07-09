-- ============================================================
-- KUN YAKUNLASH (Z-hisobot) + kech yopishni DIREKTOR tasdiqlash.
-- Kassir kunni yopadi (snapshot: savdo/kassa/harajat). Agar biznes-kun (02:30)
-- chegarasidan keyin, o'tgan kunni yopsa — kech (is_late) va status='pending':
-- direktor tasdiqlashi kerak. O'z vaqtida yopsa — darhol 'closed'.
-- ============================================================
CREATE TABLE IF NOT EXISTS day_close (
  id SERIAL PRIMARY KEY,
  biz_date DATE NOT NULL UNIQUE,           -- biznes-kun (02:30 chegarasi)
  status VARCHAR(12) NOT NULL DEFAULT 'closed', -- closed | pending | approved | rejected
  sales NUMERIC(14,2) DEFAULT 0,
  received NUMERIC(14,2) DEFAULT 0,        -- kassaga tushgan (karta+naqd)
  expenses NUMERIC(14,2) DEFAULT 0,
  profit NUMERIC(14,2) DEFAULT 0,
  is_late BOOLEAN DEFAULT false,
  closed_by INTEGER, closed_by_name TEXT, closed_at TIMESTAMP DEFAULT NOW(),
  approved_by INTEGER, approved_by_name TEXT, approved_at TIMESTAMP,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_day_close_status ON day_close (status, biz_date DESC);
