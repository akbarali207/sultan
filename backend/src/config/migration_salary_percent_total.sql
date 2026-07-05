-- percent_total maosh turiga ruxsat (jami tushumdan foiz — kassir/admin uchun).
-- Eski CHECK constraint faqat monthly/daily/hourly/percent ni ruxsat berardi,
-- shuning uchun 'percent_total' saqlanmasdan xato berardi.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_salary_type_check;
ALTER TABLE users ADD CONSTRAINT users_salary_type_check
  CHECK (salary_type IN ('monthly','daily','hourly','percent','percent_total'));
