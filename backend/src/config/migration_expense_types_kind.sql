-- ============================================================
-- Harajat turiga 'kind' (egasi so'radi 2026-07-13):
--   'generic'       — oddiy xarajat (default, eski xulq)
--   'salary'        — «Ish haqi»: xarajat EMAS, xodimga AVANS (salary_payments)
--   'supplier_debt' — postavshik qarzini uzish (keyingi faza uchun zaxira)
-- 'salary' tanlanganda front xodim + summa so'raydi va /reports/salary-payments
-- (kind=advance) ga yuboradi — Ish haqi tarixida ko'rinadi.
-- ============================================================
ALTER TABLE expense_types ADD COLUMN IF NOT EXISTS kind VARCHAR(16) NOT NULL DEFAULT 'generic';

-- Seed qilingan «Ish haqi» turini salary deb belgilaymiz
UPDATE expense_types SET kind = 'salary' WHERE name = 'Ish haqi' AND kind = 'generic';

-- Salary turi umuman bo'lmasa — bittasini yaratamiz (funksiya doim ishlashi uchun)
INSERT INTO expense_types (name, kind)
SELECT 'Ish haqi', 'salary'
WHERE NOT EXISTS (SELECT 1 FROM expense_types WHERE kind = 'salary');
