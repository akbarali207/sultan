-- Oylik to'lovi QAMROV DAVRI (period_from..period_to) — ixtiyoriy davr bo'yicha oylik berish uchun.
-- Ikki marta to'lash himoyasi to'lov QAMROVI (davri) bo'yicha overlap-tekshiruviga tayanadi
-- (created_at = to'lov sanasi, u qamrov bilan bir xil emas — shuning uchun alohida ustunlar kerak).
--   - Proporsional turlar (daily/hourly/percent/piece/shift-FaceID): qamrov = aynan tanlangan davr
--     → disjoint davrlar (1-10, keyin 11-20) ruxsat; ustma-ust (overlap) davrlar rad etiladi.
--   - Fixed-base turlar (monthly / shift+qo'lda smena): base butun OYni ifodalaydi → qamrov butun oyga
--     normallashtiriladi → o'sha oyda ikkinchi to'lov overlap bo'lib bloklanadi (oyda 1 marta).
-- Eski yozuvlarda NULL qoladi (backend created_at oynasi bilan fallback qiladi).

ALTER TABLE salary_payments ADD COLUMN IF NOT EXISTS period_from date;
ALTER TABLE salary_payments ADD COLUMN IF NOT EXISTS period_to   date;

-- Tez overlap qidiruvi uchun indeks (user + qamrov)
CREATE INDEX IF NOT EXISTS idx_salary_payments_period
  ON salary_payments (user_id, period_from, period_to)
  WHERE kind = 'salary' AND period_from IS NOT NULL;
