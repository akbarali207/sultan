-- «Ish haqi» XARAJAT TURINI OLIB TASHLAYMIZ (egasi so'rovi 2026-07-15).
-- Sabab: oylik/avans faqat «Zarplata» ekranidan beriladi va u AVTOMATIK Kassa/Rasxodlarга
-- «Oylik»/«Avans» bo'lib tushadi (cash_transactions source='salary'/'advance'). Rasxodlardagi
-- alohida «Ish haqi» turi — chalkashlik/dublikat edi.
-- Nom bo'yicha o'chiramiz (kind ustuni bo'lmasa ham ishlaydi). Avval o'sha turdаги yozuvlar
-- (odatда yo'q — createExpense salary-turini rad etadi), keyin turning o'zi.
DELETE FROM expenses WHERE expense_type_id IN (SELECT id FROM expense_types WHERE name = 'Ish haqi');
DELETE FROM expense_types WHERE name = 'Ish haqi';
