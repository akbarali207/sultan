-- ============================================================
-- Oylik DAVRI — egasi so'radi (2026-07-13): standart 10 kunlik davr.
-- Ish hajmiga qarab hisoblanadigan turlar (percent/percent_total/shift/piece/
-- daily/hourly) — 10 kunlik davrda to'g'ri: davr ichida ishlangani to'lanadi.
-- 'monthly' (belgilangan oylik summa) — 10 kunda to'lansa 3 barobar ortiqcha
-- bo'lardi, shuning uchun uni 10 ga o'tkazmaymiz (o'z qiymatida, odatda 30, qoladi).
-- ============================================================
ALTER TABLE users ALTER COLUMN salary_period_days SET DEFAULT 10;

UPDATE users
SET salary_period_days = 10
WHERE is_active = true
  AND COALESCE(salary_type, '') <> 'monthly';
