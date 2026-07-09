-- ============================================================
-- Yangi maosh imkoniyatlari:
--   (1) 'piece'  — sdelnaya: har taom uchun dona-ga stavka (salary_piece_rates).
--   (2) percent progressiv — kunlik savdo chegaradan oshsa foiz oshadi
--       (salary_tier_threshold / salary_tier_value user'da).
-- Idempotent. Prod'da qayta ishga tushsa zararsiz.
-- ============================================================

-- 'piece' maosh turiga ruxsat (eski CHECK ni yangilaymiz)
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_salary_type_check;
ALTER TABLE users ADD CONSTRAINT users_salary_type_check
  CHECK (salary_type IN ('monthly','daily','hourly','percent','percent_total','piece'));

-- Progressiv foiz (ofitsant): kunlik savdo > threshold bo'lsa -> tier_value% (aks holda salary_value%)
ALTER TABLE users ADD COLUMN IF NOT EXISTS salary_tier_threshold NUMERIC(12,2); -- kunlik savdo chegarasi (so'm)
ALTER TABLE users ADD COLUMN IF NOT EXISTS salary_tier_value     NUMERIC(6,2);  -- oshirilgan foiz (masalan 7.00)

-- Sdelnaya stavkalar: xodim + taom -> dona uchun stavka
CREATE TABLE IF NOT EXISTS salary_piece_rates (
  id SERIAL PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id),
  menu_item_id INTEGER NOT NULL REFERENCES menu_items(id),
  rate         NUMERIC(12,2) NOT NULL DEFAULT 0, -- 1 dona uchun so'm
  created_at   TIMESTAMP DEFAULT NOW(),
  UNIQUE (user_id, menu_item_id)
);
CREATE INDEX IF NOT EXISTS idx_salary_piece_rates_user ON salary_piece_rates (user_id);
