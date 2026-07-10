-- 'shift' (stavka/smena) maosh turiga ruxsat. Oshpazlar uchun: kun >=11:50 -> 1 stavka,
-- <11:50 -> 0.5, >12:00 -> stavka + daqiqa-bonus. Hisob reportController.getPayroll da.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_salary_type_check;
ALTER TABLE users ADD CONSTRAINT users_salary_type_check
  CHECK (salary_type IN ('monthly','daily','hourly','percent','percent_total','piece','shift'));
