-- HISOB/CHEK so'rovi: "Hisob" (счёт) yoki "Chekni qayta chiqarish" bosilganda true bo'ladi.
-- print-agent shu belgi bo'yicha chek chiqaradi (Завершить'да avtomatik EMAS).
ALTER TABLE orders ADD COLUMN IF NOT EXISTS bill_requested BOOLEAN DEFAULT false;
