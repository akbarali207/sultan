-- ============================================================
-- REPO ↔ PROD sxema tenglashuvi (disaster-recovery / toza deploy uchun).
-- Prod bazasi qo'lda evolyutsiya qilingan: quyidagi ustunlar kodda ISHLATILADI,
-- lekin na schema.sql, na boshqa migratsiya ularni yaratmagan. Shu sabab toza
-- deploy/restore'da login, createOrder, xarajat, day-close, retsept tannarxi
-- ishlamas edi. Hammasi IF NOT EXISTS — prod'da mavjud bo'lsa NO-OP (zararsiz).
-- ============================================================

-- users.password — login/parol (authController, userController)
ALTER TABLE users ADD COLUMN IF NOT EXISTS password VARCHAR(255);

-- orders.notes + order_items.notes / is_kitchen (createOrder, moveOrder)
ALTER TABLE orders      ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS is_kitchen BOOLEAN DEFAULT true;

-- expenses.method / source (expenseController, dayCloseController, reportlar)
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS method VARCHAR(10);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'manual';

-- ingredients.category / min_quantity / price_per_unit (sklad, menyu, retsept tannarxi)
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS category      VARCHAR(100);
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS min_quantity  NUMERIC(10,3) DEFAULT 0;
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS price_per_unit NUMERIC(12,2) DEFAULT 0;

-- Imtiyozli rollar — reopen/STOP/day-close shular bilan himoyalanadi.
-- (Test DIREKTOR FOYDALANUVCHISI bu yerda YARATILMAYDI — backdoor xavfsizlik uchun olib tashlangan.)
INSERT INTO roles (name)
SELECT v.name FROM (VALUES ('director'), ('guest')) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM roles r WHERE r.name = v.name);
