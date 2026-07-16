-- KREDITORLAR / QARZGA OLINGAN BUYUMLAR (payables): restoranга qarzга yoki qisman to'lab
-- olingan buyum (mebel, dekor, uskuna). "Kimga qancha qarzmiz" + tavsif + to'langan/qolgan.
-- Mijoz qarzi (debts) ga o'xshaydi, lekin bu yerда BIZ qarzdormiz. Qismlаб to'lash mumkin.
-- To'langan qism kassaга chiqim bo'ladi (cash_transactions source='payable').
CREATE TABLE IF NOT EXISTS payables (
  id           SERIAL PRIMARY KEY,
  name         TEXT NOT NULL,                 -- nima olindi (masalan "Dekor stul")
  creditor     TEXT,                          -- kimга qarzmiz
  description  TEXT,                          -- izoh
  total_amount NUMERIC NOT NULL DEFAULT 0,    -- to'liq qiymati
  paid_amount  NUMERIC NOT NULL DEFAULT 0,    -- to'langan (qolgan = total - paid)
  created_at   TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payables_open ON payables ((total_amount - paid_amount)) WHERE (total_amount - paid_amount) > 0.5;
