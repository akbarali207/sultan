-- ============================================================
-- Hot FK / sana ustunlariga indekslar (Article 12 — Database Optimization).
-- Live-BD forenzikasi (2026-07-09) tasdiqladi: quyidagilar YO'Q edi -> seq scan.
-- Jadvallar kichik (order_items ~3.3k) => yaratish bir zumda, lock muammosi yo'q.
-- Idempotent: IF NOT EXISTS. Yillar davomida zakazlar o'sganda tezlikni saqlaydi.
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_order_items_order_id  ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_recipe_items_menu     ON recipe_items (menu_item_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at     ON orders (created_at);
CREATE INDEX IF NOT EXISTS idx_expenses_created_at   ON expenses (created_at);
CREATE INDEX IF NOT EXISTS idx_attendance_user       ON attendance (user_id, check_in);
CREATE INDEX IF NOT EXISTS idx_cash_tx_source_ref    ON cash_transactions (source, ref_id);
