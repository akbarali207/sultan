-- Bo'lim printeri USB orqali ulangan bo'lsa — Windows printer nomi
ALTER TABLE print_stations ADD COLUMN IF NOT EXISTS printer_name VARCHAR(120);
