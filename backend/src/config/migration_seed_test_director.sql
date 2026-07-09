-- ============================================================
-- OLIB TASHLANDI (xavfsizlik). Bu migratsiya avval internetdan ochiq test-DIREKTOR
-- akkauntini yaratardi (login 'director', parol director123) — bu ochiq backdoor edi.
-- Endi hech narsa qilmaydi (NO-OP). Toza deploy'da backdoor yaratilmaydi.
-- ESLATMA: prod bazasida bu migratsiya ALLAQACHON qo'llangan (schema_migrations),
-- shuning uchun mavjud akkauntni QO'LDA o'chiring yoki parolini almashtiring.
-- ============================================================
SELECT 1;
