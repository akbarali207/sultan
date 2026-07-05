-- STOP-LIST: taom "tayyor emas" bo'lsa ofitsant zakaz qila olmaydi.
-- available=true (default) -> zakaz qilsa bo'ladi; false -> stop-listда (zakaz qilinmaydi).
ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS available BOOLEAN DEFAULT true;
