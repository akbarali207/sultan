-- ROLLAR
CREATE TABLE IF NOT EXISTS roles (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- XODIMLAR
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20),
  role_id INTEGER REFERENCES roles(id),
  face_id VARCHAR(255),
  salary_type VARCHAR(20) CHECK (salary_type IN ('percent', 'hourly', 'daily', 'monthly')),
  salary_value NUMERIC(10,2),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- DAVOMAT
CREATE TABLE IF NOT EXISTS attendance (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  check_in TIMESTAMP,
  check_out TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- STOLLAR
CREATE TABLE IF NOT EXISTS tables (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  is_active BOOLEAN DEFAULT true
);

-- MENYU KATEGORIYALAR
CREATE TABLE IF NOT EXISTS menu_categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- TAOMLAR
CREATE TABLE IF NOT EXISTS menu_items (
  id SERIAL PRIMARY KEY,
  category_id INTEGER REFERENCES menu_categories(id),
  name VARCHAR(100) NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- SKLADLAR (alohida omborlar)
CREATE TABLE IF NOT EXISTS warehouses (
  id SERIAL PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- INGREDIENTLAR
CREATE TABLE IF NOT EXISTS ingredients (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  unit VARCHAR(20) NOT NULL,
  stock_quantity NUMERIC(10,3) DEFAULT 0,
  warehouse_id INTEGER REFERENCES warehouses(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- TAOM RETSEPTI
CREATE TABLE IF NOT EXISTS recipe_items (
  id SERIAL PRIMARY KEY,
  menu_item_id INTEGER REFERENCES menu_items(id),
  ingredient_id INTEGER REFERENCES ingredients(id),
  quantity NUMERIC(10,3) NOT NULL
);

-- ZAKAZLAR
CREATE TABLE IF NOT EXISTS orders (
  id SERIAL PRIMARY KEY,
  table_id INTEGER REFERENCES tables(id),
  waiter_id INTEGER REFERENCES users(id),
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'preparing', 'ready', 'paid')),
  total_amount NUMERIC(10,2) DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ZAKAZ TARKIBI
CREATE TABLE IF NOT EXISTS order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER REFERENCES orders(id),
  menu_item_id INTEGER REFERENCES menu_items(id),
  quantity INTEGER NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- HARAJAT TURLARI
CREATE TABLE IF NOT EXISTS expense_types (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- HARAJATLAR
CREATE TABLE IF NOT EXISTS expenses (
  id SERIAL PRIMARY KEY,
  expense_type_id INTEGER REFERENCES expense_types(id),
  name VARCHAR(100) NOT NULL,
  amount NUMERIC(10,2) NOT NULL,
  quantity NUMERIC(10,3),
  unit VARCHAR(20),
  created_at TIMESTAMP DEFAULT NOW()
);

-- BOSHLANG'ICH ROLLAR
INSERT INTO roles (name) VALUES
  ('admin'),
  ('waiter'),
  ('chef'),
  ('cashier'),
  ('cleaner')
ON CONFLICT (name) DO NOTHING;

-- XONALAR (floor-plan) — nisbiy koordinatalar 0.0..1.0
CREATE TABLE IF NOT EXISTS rooms (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  pos_x DOUBLE PRECISION DEFAULT 0.1,
  pos_y DOUBLE PRECISION DEFAULT 0.1,
  width DOUBLE PRECISION DEFAULT 0.3,
  height DOUBLE PRECISION DEFAULT 0.3,
  created_at TIMESTAMP DEFAULT NOW()
);

-- STOLLAR uchun floor-plan ustunlari
ALTER TABLE tables ADD COLUMN IF NOT EXISTS room_id INTEGER REFERENCES rooms(id);
ALTER TABLE tables ADD COLUMN IF NOT EXISTS seats INTEGER DEFAULT 4;
ALTER TABLE tables ADD COLUMN IF NOT EXISTS pos_x DOUBLE PRECISION DEFAULT 0.5;
ALTER TABLE tables ADD COLUMN IF NOT EXISTS pos_y DOUBLE PRECISION DEFAULT 0.5;
ALTER TABLE tables ADD COLUMN IF NOT EXISTS table_size DOUBLE PRECISION DEFAULT 1.0;

-- SKLADLAR uchun (mavjud bazaga)
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS warehouse_id INTEGER REFERENCES warehouses(id);

INSERT INTO warehouses (name)
SELECT v.name FROM (VALUES
  ('Sklad 1 - Oshxona'),
  ('Sklad 2 - Shashlik'),
  ('Sklad 3 - Somsa')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM warehouses w WHERE w.name = v.name);

UPDATE ingredients
SET warehouse_id = (SELECT id FROM warehouses WHERE name = 'Sklad 1 - Oshxona')
WHERE warehouse_id IS NULL;

-- ISH HAQI AVANSLARI (oylikdan oldin berilgan to'lovlar)
CREATE TABLE IF NOT EXISTS salary_advances (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount NUMERIC(10,2) NOT NULL,
  note VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_salary_advances_user_date
  ON salary_advances (user_id, created_at);