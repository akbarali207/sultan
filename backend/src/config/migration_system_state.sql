-- ============================================================
-- Tizim holati (super-admin "STOP" tugmasi uchun). frozen=true bo'lsa
-- yangi zakaz va to'lov BLOKLANADI (favqulodda to'xtatish). Faqat super-admin
-- (guest roli) o'zgartira oladi. Bitta qatorli jadval (id=1).
-- ============================================================
CREATE TABLE IF NOT EXISTS system_state (
  id INTEGER PRIMARY KEY DEFAULT 1,
  frozen BOOLEAN NOT NULL DEFAULT false,
  frozen_by INTEGER,
  frozen_by_name TEXT,
  frozen_at TIMESTAMP,
  note TEXT,
  CONSTRAINT system_state_single CHECK (id = 1)
);
INSERT INTO system_state (id, frozen) VALUES (1, false) ON CONFLICT (id) DO NOTHING;
