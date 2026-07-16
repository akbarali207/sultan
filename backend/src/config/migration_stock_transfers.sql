-- SKLADLARARO KO'CHIRISH (перемещение между складами). Masalan go'sht 1-skladga keladi,
-- keyin Oshxona/Shashlik/Samsa skladlarига bo'linadi. Har ko'chirish tarixда saqlanadi;
-- qoldiq har sklad bo'yicha ingredients.stock_quantity da ko'rinadi (manba kamayadi, maqsad oshadi).
CREATE TABLE IF NOT EXISTS stock_transfers (
  id                 SERIAL PRIMARY KEY,
  from_ingredient_id INT,
  to_ingredient_id   INT,
  from_warehouse_id  INT,
  to_warehouse_id    INT,
  name               TEXT,
  quantity           NUMERIC NOT NULL,
  unit               TEXT,
  unit_cost          NUMERIC DEFAULT 0,
  note               TEXT,
  created_at         TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_created ON stock_transfers (created_at DESC);
