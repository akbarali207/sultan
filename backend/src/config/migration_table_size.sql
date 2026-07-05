-- Stol o'lchami (figura masshtabi): 1.0 = normal, >1 kattaroq, <1 kichikroq
ALTER TABLE tables ADD COLUMN IF NOT EXISTS table_size DOUBLE PRECISION DEFAULT 1.0;
