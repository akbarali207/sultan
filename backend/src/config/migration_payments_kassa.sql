-- ============================================================
-- To'lov tizimi: zakaz to'lovi + Kassa + qarz + oylik to'lash
-- ============================================================

-- ── Faza 1: zakaz to'lov maydonlari ──
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_reason VARCHAR(200);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS final_amount NUMERIC(12,2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_card NUMERIC(12,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_cash NUMERIC(12,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_debt NUMERIC(12,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS debtor_name VARCHAR(120);

-- ── Kassa ledger (barcha pul harakatlari: tushum/chiqim, karta/naqd) ──
CREATE TABLE IF NOT EXISTS cash_transactions (
  id SERIAL PRIMARY KEY,
  kind   VARCHAR(10) NOT NULL CHECK (kind   IN ('income','expense')),
  method VARCHAR(10) NOT NULL CHECK (method IN ('card','cash')),
  amount NUMERIC(12,2) NOT NULL,
  source VARCHAR(20) NOT NULL DEFAULT 'manual',  -- order/debt/salary/advance/manual
  ref_id INTEGER,
  note   VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cash_tx_date ON cash_transactions (created_at);

-- ── Qarzlar (qarzga olingan zakazlar; paid_amount — qaytarilgani) ──
CREATE TABLE IF NOT EXISTS debts (
  id SERIAL PRIMARY KEY,
  order_id INTEGER REFERENCES orders(id),
  debtor_name VARCHAR(120) NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_debts_name ON debts (debtor_name);

-- ── Oylik to'lovlari (avans + oylik, karta/naqd) ──
CREATE TABLE IF NOT EXISTS salary_payments (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount NUMERIC(12,2) NOT NULL,
  method VARCHAR(10) NOT NULL DEFAULT 'cash' CHECK (method IN ('card','cash')),
  kind   VARCHAR(10) NOT NULL DEFAULT 'advance' CHECK (kind IN ('advance','salary')),
  note   VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_salary_payments_user_date ON salary_payments (user_id, created_at);

-- Eski avanslarni (salary_advances) yangi jadvalga ko'chirish (faqat bir marta)
INSERT INTO salary_payments (user_id, amount, method, kind, note, created_at)
SELECT user_id, amount, 'cash', 'advance', note, created_at
FROM salary_advances
WHERE NOT EXISTS (SELECT 1 FROM salary_payments);

-- ── Xodimga to'lov kuni (payday: oyning kuni 1..28) ──
ALTER TABLE users ADD COLUMN IF NOT EXISTS salary_day INTEGER DEFAULT 1;
