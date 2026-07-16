-- ============================================================
-- PARTIYA (LOT/BATCH) TIZIMI — yadro jadvallar.
-- Har zakupka ALOHIDA partiya bo'ladi: o'z narxi, o'z qoldig'i,
-- o'z to'lov tarixi, o'z srok godnosti. Aralashtirish taqiqlanadi.
-- ingredients.stock_quantity JAMI qoldiq bo'lib qoladi (minus ATAYLAB
-- ruxsat etilgan — partiyalar esa hech qachon minusga tushmaydi).
-- ============================================================

-- DR-drift tuzatish: stock_incoming jonli bazada bor, lekin repo SQLda
-- yo'q edi — toza bazada backend yiqilardi. Endi repo ham yaratadi.
CREATE TABLE IF NOT EXISTS stock_incoming (
  id SERIAL PRIMARY KEY,
  ingredient_id INTEGER REFERENCES ingredients(id),
  quantity NUMERIC(10,3),
  price_per_unit NUMERIC(10,2),
  total_amount NUMERIC(10,2),
  note VARCHAR(250),
  method VARCHAR(10) DEFAULT 'cash',
  source VARCHAR(120) DEFAULT 'kassa',
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_stock_incoming_ing ON stock_incoming (ingredient_id, created_at DESC);

-- POSTAVSHIKLAR
CREATE TABLE IF NOT EXISTS suppliers (
  id SERIAL PRIMARY KEY,
  name VARCHAR(150) NOT NULL,
  phone VARCHAR(40),
  contact_person VARCHAR(120),
  address VARCHAR(250),
  note TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_supplier_name ON suppliers (lower(trim(name)));

-- PARTIYALAR: har kirim = yangi mustaqil yozuv.
-- remaining = quantity - used_quantity, debt = total_cost - paid_amount
-- (so'rovda hisoblanadi — eski Postgres versiyalari bilan moslik uchun
-- generated column ishlatilmaydi).
CREATE TABLE IF NOT EXISTS stock_lots (
  id SERIAL PRIMARY KEY,
  lot_code VARCHAR(40),                                  -- LOT-000123 (id dan generatsiya)
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
  supplier_id INTEGER REFERENCES suppliers(id),
  invoice_no VARCHAR(80),                                -- nakladnoy raqami
  purchase_date DATE DEFAULT CURRENT_DATE,               -- zakupka sanasi
  received_at TIMESTAMP DEFAULT NOW(),                   -- kelib tushgan vaqt
  expiry_date DATE,                                      -- srok godnosti (bo'lsa)
  quantity NUMERIC(14,3) NOT NULL CHECK (quantity > 0),  -- boshlang'ich miqdor
  unit VARCHAR(20),                                      -- birlik (snapshot)
  unit_cost NUMERIC(14,4) NOT NULL CHECK (unit_cost >= 0),
  discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  total_cost NUMERIC(14,2) NOT NULL CHECK (total_cost >= 0),  -- qty*narx - chegirma
  used_quantity NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (used_quantity >= 0),
  paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
  status VARCHAR(16) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','depleted','written_off','blocked')),
  note TEXT,
  source_incoming_id INTEGER,                            -- stock_incoming.id (legacy ko'prik)
  created_by INTEGER,
  created_by_name TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_stock_lots_ing ON stock_lots (ingredient_id, status, received_at);
CREATE INDEX IF NOT EXISTS idx_stock_lots_supplier ON stock_lots (supplier_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_lots_expiry ON stock_lots (expiry_date) WHERE expiry_date IS NOT NULL;

-- PARTIYADAN SARF: har chegirish o'sha paytdagi TANNARX bilan yoziladi —
-- tarixiy COGS keyin narx o'zgarsa ham O'ZGARMAYDI (F11 talabi).
-- lot_id NULL bo'lishi mumkin: qoldiq minusга ketganda (ataylab ruxsat)
-- partiyasiz sarf ham hisobda qoladi.
CREATE TABLE IF NOT EXISTS lot_consumptions (
  id SERIAL PRIMARY KEY,
  lot_id INTEGER REFERENCES stock_lots(id),
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
  quantity NUMERIC(14,3) NOT NULL,                       -- + sarf, - qaytarish (restore)
  unit_cost NUMERIC(14,4) NOT NULL DEFAULT 0,            -- sarf paytidagi narx (snapshot)
  cost_method VARCHAR(10),                               -- fifo|lifo|average (sarf paytida)
  reason VARCHAR(30) NOT NULL,                           -- sale|pf_production|writeoff|expired|inventory|restore|manual|return
  ref_type VARCHAR(20),                                  -- order|pf|inventory|lot|manual
  ref_id INTEGER,
  note VARCHAR(250),
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_lot_cons_ing ON lot_consumptions (ingredient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lot_cons_lot ON lot_consumptions (lot_id);
CREATE INDEX IF NOT EXISTS idx_lot_cons_ref ON lot_consumptions (ref_type, ref_id);

-- POSTAVSHIK TO'LOVLARI: partiy(a)ga va/yoki postavshikka bog'lanadi.
-- Kassadan to'lansa cash_transactions (source='supplier', ref_id=shu id) yoziladi.
CREATE TABLE IF NOT EXISTS supplier_payments (
  id SERIAL PRIMARY KEY,
  supplier_id INTEGER REFERENCES suppliers(id),
  lot_id INTEGER REFERENCES stock_lots(id),
  amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  kind VARCHAR(10) NOT NULL DEFAULT 'payment' CHECK (kind IN ('payment','refund')),
  method VARCHAR(10) NOT NULL DEFAULT 'cash' CHECK (method IN ('cash','card')),
  from_kassa BOOLEAN DEFAULT true,
  note VARCHAR(250),
  paid_by INTEGER,
  paid_by_name TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_supplier_pay_sup ON supplier_payments (supplier_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_pay_lot ON supplier_payments (lot_id);

-- SOZLAMALAR (kalit-qiymat): tannarx metodi va boshqalar.
CREATE TABLE IF NOT EXISTS app_settings (
  key VARCHAR(60) PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMP DEFAULT NOW(),
  updated_by INTEGER,
  updated_by_name TEXT
);
-- 'average' = joriy o'rtacha-vaznli xulq saqlanadi (kutilmagan o'zgarish yo'q);
-- admin keyin FIFO/LIFO ga o'tkazishi mumkin.
INSERT INTO app_settings (key, value) VALUES
  ('costing_method', 'average'),
  ('expiry_warn_days', '5'),
  ('supplier_overdue_days', '14')
ON CONFLICT (key) DO NOTHING;

-- AUDIT-JURNAL (F16): append-only, o'zgarmas. Har muhim amal:
-- kim, qachon, qaysi qurilmadan, nima o'zgardi (eski/yangi JSON), sabab.
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER,
  user_name TEXT,
  user_role VARCHAR(30),
  ip VARCHAR(60),
  device TEXT,
  branch VARCHAR(60),
  action VARCHAR(60) NOT NULL,
  entity_type VARCHAR(40),
  entity_id INTEGER,
  old_value JSONB,
  new_value JSONB,
  reason TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log (entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log (user_id, created_at DESC);

-- O'ZGARMASLIK: UPDATE/DELETE taqiqlanadi (faqat INSERT).
CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'audit_log o''zgarmas (append-only) — UPDATE/DELETE taqiqlangan';
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_audit_immutable ON audit_log;
CREATE TRIGGER trg_audit_immutable
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();
