-- To'lovni QABUL QILGAN xodim (kassir) — smena/hisobot podotchётligi uchun.
-- Har to'lovda kim yopganini yozib qolamiz.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_by INTEGER;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_by_name TEXT;
