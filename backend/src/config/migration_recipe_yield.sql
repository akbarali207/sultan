-- RETSEPT (kalkulyatsiya): quantity = BRUTTO (xom vazn), yield_percent = chiqish foizi.
-- netto = quantity * yield_percent/100 (hisoblanadi). Tannarx = quantity * ingredient.price_per_unit.
-- Skladdan BRUTTO (quantity) ayriladi (yo'qotish bilan).
ALTER TABLE recipe_items ADD COLUMN IF NOT EXISTS yield_percent NUMERIC(5,2) DEFAULT 100;
