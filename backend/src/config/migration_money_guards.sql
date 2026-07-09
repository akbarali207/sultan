-- ============================================================
-- Pul invariantlari (DB darajasidagi oxirgi himoya). Idempotent — mavjud bo'lsa no-op.
-- Faza 0 falsafasi: kod xato qilsa ham baza manfiy/noto'g'ri pulni rad etadi.
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_cash_tx_amount_pos') THEN
    ALTER TABLE cash_transactions ADD CONSTRAINT chk_cash_tx_amount_pos CHECK (amount > 0);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_orders_discount_range') THEN
    ALTER TABLE orders ADD CONSTRAINT chk_orders_discount_range
      CHECK (discount_percent IS NULL OR (discount_percent >= 0 AND discount_percent <= 100));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_orders_final_nonneg') THEN
    ALTER TABLE orders ADD CONSTRAINT chk_orders_final_nonneg
      CHECK (final_amount IS NULL OR final_amount >= 0);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_debts_amounts') THEN
    ALTER TABLE debts ADD CONSTRAINT chk_debts_amounts CHECK (amount > 0 AND paid_amount >= 0);
  END IF;
END $$;
