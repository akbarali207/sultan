-- Inventarizatsiyani sklad bo'yicha qilish uchun
ALTER TABLE inventory_checks ADD COLUMN IF NOT EXISTS warehouse_id INTEGER REFERENCES warehouses(id);
