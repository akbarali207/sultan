-- HAR TAOM ALOHIDA chop etiladi: stolga qo'shilgan yangi taom ham oshxona chekini
-- chiqarsin, eski (chiqqan) taomlar qayta chiqmasin.
-- Mavjud satrlar printed=true (ADD ... DEFAULT true), yangilar printed=false (keyingi ALTER).
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS printed BOOLEAN DEFAULT true;
ALTER TABLE order_items ALTER COLUMN printed SET DEFAULT false;
