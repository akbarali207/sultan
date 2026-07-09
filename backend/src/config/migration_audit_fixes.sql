-- Audit tuzatishlari (2026-07-06)

-- 1) uniq_ingredient_key: sklad bo'yicha (avval faqat nom bo'yicha global edi -> boshqa skladda
--    bir xil nom 500 berardi). DEPLOY-XAVFSIZ: agar bir skladda hali dublikat bo'lsa, indeks
--    yaratilmaydi (crash bo'lmasin) — dedup (dedup_catalog.js) o'zi keyin yaratadi.
DO $$
BEGIN
  DROP INDEX IF EXISTS uniq_ingredient_key;
  IF NOT EXISTS (
    SELECT 1 FROM ingredients
    GROUP BY warehouse_id, lower(regexp_replace(name,'[^0-9A-Za-zА-Яа-яЁё]','','g'))
    HAVING COUNT(*) > 1
  ) THEN
    CREATE UNIQUE INDEX uniq_ingredient_key
      ON ingredients (warehouse_id, lower(regexp_replace(name,'[^0-9A-Za-zА-Яа-яЁё]','','g')));
  END IF;
END $$;

-- 2) To'lov qismlari (karta+naqd+qarz) == yakuniy summa invarianti (himoya; NOT VALID -> eski qatorlarni buzmaydi)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_orders_split_balance') THEN
    ALTER TABLE orders ADD CONSTRAINT chk_orders_split_balance CHECK (
      status <> 'paid'
      OR ABS(COALESCE(final_amount,total_amount,0) - (COALESCE(paid_card,0)+COALESCE(paid_cash,0)+COALESCE(paid_debt,0))) <= 1
    ) NOT VALID;
  END IF;
END $$;

-- 3) Ma'lumot tuzatish: "Чай черный" ingredienti bir taomda 1 kg (chashkaga 1 kg choy — xato).
--    Qardosh retsept 0.005 kg ishlatadi. INGREDIENT nomi bo'yicha (taom nomi shart emas), idempotent.
UPDATE recipe_items ri SET quantity = 0.005
FROM ingredients i
WHERE ri.ingredient_id = i.id
  AND i.name ILIKE 'Чай черный'
  AND ri.quantity = 1.0;
