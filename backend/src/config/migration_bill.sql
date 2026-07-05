-- Mijoz cheki (bill) chop etilganmi — print-agent uchun
ALTER TABLE orders ADD COLUMN IF NOT EXISTS bill_printed BOOLEAN DEFAULT false;
