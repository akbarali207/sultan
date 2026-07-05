-- XODIMLAR ish jadvali va kechikish jarimasi (davomat nazorati uchun)

-- Ish boshlanish/tugash vaqti (smena)
ALTER TABLE users ADD COLUMN IF NOT EXISTS work_start TIME DEFAULT '09:00';
ALTER TABLE users ADD COLUMN IF NOT EXISTS work_end TIME DEFAULT '22:00';

-- 1 daqiqa kechikish uchun jarima (so'm)
ALTER TABLE users ADD COLUMN IF NOT EXISTS late_fine_per_minute NUMERIC(10,2) DEFAULT 0;
