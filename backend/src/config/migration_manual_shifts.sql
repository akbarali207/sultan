-- Смещики (salary_type='shift') uchun QO'LDA smena kiritish — Face-ID ishonchsiz bo'lganda.
-- Har xodim + oy (period_ym 'YYYY-MM') uchun nechta smena ishlagani (yarim smena -> kasr, masalan 25.5).
-- getPayroll SHIFT hisobida: yozuv bo'lsa base = shifts * salary_value (bir smena stavkasi),
-- yozuv bo'lmasa — eski yo'l (Face-ID davomat soatlaridan). ADDITIVE, idempotent.
CREATE TABLE IF NOT EXISTS manual_shifts (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  period_ym  VARCHAR(7) NOT NULL,               -- 'YYYY-MM'
  shifts     NUMERIC(6,2) NOT NULL DEFAULT 0,   -- ishlagan smenalar soni (masalan 25 yoki 25.5)
  note       VARCHAR(200),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (user_id, period_ym)
);
CREATE INDEX IF NOT EXISTS idx_manual_shifts_period ON manual_shifts (period_ym);
