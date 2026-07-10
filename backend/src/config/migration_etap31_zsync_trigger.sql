-- ============================================================
-- ETAP 3.1 — Phase 1b/2b: DUAL-WRITE trigger (non-destruktiv, reversible).
-- Nomi 'z...' — alifboда OXIRGI: units + ingredient_categories jadvallari tayyor bo'lgach ishlaydi.
-- ingredients.unit/category YOZILGANDA -> unit_id/category_id/is_pf AVTOMATIK to'ldiriladi
-- (createIngredient, editIngredient, createPfItem, addRecipeItem, import — BARCHA yo'llar bir joyda).
-- Yangi kategoriya stringi -> spravochnikka avtomatik qo'shiladi (to'liq SSOT).
-- O'qish HALI stringda — bu faqat id-ustunlarni sinxron saqlaydi (read-switch keyingi faza).
-- ============================================================
CREATE OR REPLACE FUNCTION ingredients_sync_refs() RETURNS trigger AS $$
BEGIN
  -- birlik stringi -> kanonik unit_id
  IF NEW.unit IS NOT NULL THEN
    SELECT u.id INTO NEW.unit_id FROM units u WHERE u.code = (
      CASE lower(trim(NEW.unit))
        WHEN 'кг' THEN 'kg'  WHEN 'kg' THEN 'kg'  WHEN 'kilogram' THEN 'kg'  WHEN 'килограмм' THEN 'kg'
        WHEN 'л' THEN 'l'    WHEN 'litr' THEN 'l' WHEN 'l' THEN 'l'          WHEN 'литр' THEN 'l'
        WHEN 'мл' THEN 'ml'  WHEN 'ml' THEN 'ml'
        WHEN 'dona' THEN 'pcs' WHEN 'шт' THEN 'pcs' WHEN 'pcs' THEN 'pcs'    WHEN 'штук' THEN 'pcs'
        WHEN 'gr' THEN 'g'   WHEN 'г' THEN 'g'    WHEN 'gram' THEN 'g'       WHEN 'грамм' THEN 'g'
        WHEN 'пакет' THEN 'pack' WHEN 'pachka' THEN 'pack' WHEN 'упакофка' THEN 'pack' WHEN 'упаковка' THEN 'pack'
        WHEN 'банка' THEN 'jar'  WHEN 'порц' THEN 'portion'  ELSE NULL END);
  END IF;
  -- kategoriya stringi -> category_id (yo'q bo'lsa spravochnikka qo'shiladi) + is_pf
  IF NEW.category IS NOT NULL AND trim(NEW.category) <> '' THEN
    INSERT INTO ingredient_categories (name, is_pf)
      VALUES (trim(NEW.category), trim(NEW.category) = 'П/Ф')
      ON CONFLICT (name) DO NOTHING;
    SELECT ic.id INTO NEW.category_id FROM ingredient_categories ic WHERE ic.name = trim(NEW.category);
    IF trim(NEW.category) = 'П/Ф' THEN NEW.is_pf := true; END IF;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ingredients_sync_refs ON ingredients;
CREATE TRIGGER trg_ingredients_sync_refs
  BEFORE INSERT OR UPDATE OF unit, category ON ingredients
  FOR EACH ROW EXECUTE FUNCTION ingredients_sync_refs();
