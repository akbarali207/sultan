-- Ish haqi avanslari (oylikdan oldin berilgan to'lovlar)
CREATE TABLE IF NOT EXISTS salary_advances (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount NUMERIC(10,2) NOT NULL,
  note VARCHAR(200),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_salary_advances_user_date
  ON salary_advances (user_id, created_at);
