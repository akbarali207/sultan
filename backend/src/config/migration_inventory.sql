CREATE TABLE IF NOT EXISTS inventory_checks (
  id SERIAL PRIMARY KEY,
  check_date DATE NOT NULL,
  status VARCHAR(20) DEFAULT 'open',
  created_by INT REFERENCES users(id),
  warehouse_id INTEGER REFERENCES warehouses(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Mavjud bazaga ustun qo'shish
ALTER TABLE inventory_checks ADD COLUMN IF NOT EXISTS warehouse_id INTEGER REFERENCES warehouses(id);

CREATE TABLE IF NOT EXISTS inventory_items (
  id SERIAL PRIMARY KEY,
  inventory_id INT NOT NULL REFERENCES inventory_checks(id) ON DELETE CASCADE,
  ingredient_id INT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  expected_quantity NUMERIC(10,3) DEFAULT 0,
  actual_quantity NUMERIC(10,3) DEFAULT 0,
  difference NUMERIC(10,3) DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);
