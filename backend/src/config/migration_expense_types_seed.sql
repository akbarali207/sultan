-- Harajat turlari namunalari (faqat jadval bo'sh bo'lsa)
INSERT INTO expense_types (name)
SELECT v.name FROM (VALUES
  ('Mahsulot'),
  ('Ish haqi'),
  ('Kommunal'),
  ('Ijara'),
  ('Jihoz/ta''mir'),
  ('Boshqa')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM expense_types);
