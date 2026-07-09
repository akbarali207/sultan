-- ============================================================
-- Ish haqi qo'shimchalari: jarima, bonus, kech-jarima override, source ustuni.
-- Bu jadval/ustunlar jonli bazada QO'LDA qo'shilgan edi, lekin migratsiyada YO'Q edi
-- (toza deployда payroll/oylik-to'lash 500 berardi). Idempotent — jonli bazada no-op.
-- ============================================================

-- Ish haqi jarimalari
CREATE TABLE IF NOT EXISTS salary_fines (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount NUMERIC(12,2) NOT NULL,
  reason VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_salary_fines_user_date ON salary_fines (user_id, created_at);

-- Ish haqi bonuslari (summa yoki foiz)
CREATE TABLE IF NOT EXISTS salary_bonuses (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount NUMERIC(12,2) NOT NULL,
  percent NUMERIC(5,2),
  reason VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_salary_bonuses_user_date ON salary_bonuses (user_id, created_at);

-- Kech kelish jarimasini oy bo'yicha override (period_ym = 'YYYY-MM')
CREATE TABLE IF NOT EXISTS late_fine_overrides (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  period_ym VARCHAR(7) NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  reason VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);
-- reportController ON CONFLICT (user_id, period_ym) ishlatadi
CREATE UNIQUE INDEX IF NOT EXISTS uniq_late_fine_override
  ON late_fine_overrides (user_id, period_ym);

-- salary_payments.source (migration_payments_kassa.sql da unutilgan)
ALTER TABLE salary_payments ADD COLUMN IF NOT EXISTS source VARCHAR(120) DEFAULT 'kassa';

-- users.salary_period_days (payroll davri kunlari)
ALTER TABLE users ADD COLUMN IF NOT EXISTS salary_period_days INTEGER DEFAULT 30;
