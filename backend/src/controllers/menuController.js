const pool = require('../config/db');

// Kategoriyalar
const getCategories = async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM menu_categories ORDER BY id`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const createCategory = async (req, res) => {
  try {
    const { name } = req.body;
    const result = await pool.query(
      `INSERT INTO menu_categories (name) VALUES ($1) RETURNING *`,
      [name]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const updateCategory = async (req, res) => {
  try {
    const { id } = req.params;
    const { name } = req.body;
    const result = await pool.query(
      `UPDATE menu_categories SET name=$1 WHERE id=$2 RETURNING *`,
      [name, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const deleteCategory = async (req, res) => {
  try {
    const { id } = req.params;
    // FK NO ACTION: ARXIV (is_active=false) taomlar ham bog'lanadi -> hard delete 23503 (500) berardi.
    // Shuning uchun BARCHA taomlarni sanaymiz (faol + arxiv) va silliq javob qaytaramiz.
    const check = await pool.query(
      `SELECT COUNT(*)::int AS n, COUNT(*) FILTER (WHERE is_active=true)::int AS active
       FROM menu_items WHERE category_id=$1`, [id]);
    const { n, active } = check.rows[0];
    if (active > 0) {
      return res.status(400).json({ message: 'Kategoriyada faol taomlar bor. Avval taomlarni o\'chiring yoki boshqa kategoriyaga o\'tkazing!' });
    }
    if (n > 0) {
      return res.status(400).json({ message: `Kategoriyada ${n} ta arxiv taom bor — o'chirib bo'lmaydi (tarix saqlanadi). Kerak bo'lsa nomini o'zgartiring.` });
    }
    await pool.query(`DELETE FROM menu_categories WHERE id=$1`, [id]);
    res.json({ message: 'Kategoriya o\'chirildi!' });
  } catch (err) {
    if (err.code === '23503') return res.status(400).json({ message: 'Kategoriya ishlatilmoqda — o\'chirib bo\'lmaydi.' });
    res.status(500).json({ message: err.message });
  }
};

// station_ids (vergulli ro'yxat "1,3") yoki station_id (bitta) ni massivga
const parseStationIds = (body) => {
  if (body.station_ids !== undefined && body.station_ids !== null && body.station_ids !== '') {
    return String(body.station_ids).split(',').map((s) => parseInt(s.trim())).filter((n) => !isNaN(n));
  }
  if (body.station_id) {
    const n = parseInt(body.station_id);
    return isNaN(n) ? [] : [n];
  }
  return [];
};

// Taomlar (har taomning bo'limlari station_ids massivida).
// P/F (polufabrikat, type='pf') MENYUDA KO'RINMAYDI — faqat ?include_pf=1 bilan
// (Retseptlar bo'limi shunday so'raydi).
const getMenuItems = async (req, res) => {
  try {
    const includePf = req.query.include_pf === '1' || req.query.include_pf === 'true';
    const result = await pool.query(
      `SELECT m.*, c.name as category_name, ps.name as station_name,
              COALESCE(
                (SELECT array_agg(mis.station_id ORDER BY mis.station_id)
                 FROM menu_item_stations mis WHERE mis.menu_item_id = m.id),
                CASE WHEN m.station_id IS NOT NULL THEN ARRAY[m.station_id] ELSE ARRAY[]::integer[] END
              ) AS station_ids
       FROM menu_items m
       JOIN menu_categories c ON m.category_id = c.id
       LEFT JOIN print_stations ps ON m.station_id = ps.id
       WHERE m.is_active = true ${includePf ? '' : `AND COALESCE(m.type,'recipe') <> 'pf'`}
       ORDER BY c.name, m.name`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// POLUFABRIKAT yaratish — maxsus "taom" (type='pf', menyuda ko'rinmas) +
// skladdagi masaliq (category='П/Ф'). Retsepti oddiy taom kabi kiritiladi,
// tannarxi avtomatik sklad narxiga yoziladi (syncPfCost).
const createPfItem = async (req, res) => {
  const client = await pool.connect();
  try {
    const { name, unit, warehouse_id, category_id } = req.body;
    if (!name || !name.trim() || !unit || !category_id) {
      return res.status(400).json({ message: 'name, unit, category_id majburiy' });
    }
    const whId = parseInt(warehouse_id);
    const warehouseId = isNaN(whId) ? null : whId;
    await client.query('BEGIN');

    // Shu skladda shunday nomli masaliq bo'lsa — qayta ishlatamiz (П/Ф ga o'tkazamiz)
    let ing = await client.query(
      warehouseId
        ? `SELECT id FROM ingredients WHERE name ILIKE $1 AND warehouse_id = $2 LIMIT 1`
        : `SELECT id FROM ingredients WHERE name ILIKE $1 AND warehouse_id IS NULL LIMIT 1`,
      warehouseId ? [name.trim(), warehouseId] : [name.trim()]
    );
    let ingredientId;
    if (ing.rows.length) {
      ingredientId = ing.rows[0].id;
      await client.query(`UPDATE ingredients SET category = 'П/Ф', unit = $1 WHERE id = $2`, [unit, ingredientId]);
    } else {
      const newIng = await client.query(
        `INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category, warehouse_id)
         VALUES ($1, $2, 0, 0, 0, 'П/Ф', $3) RETURNING id`,
        [name.trim(), unit, warehouseId]
      );
      ingredientId = newIng.rows[0].id;
    }

    // Shu nomli P/F allaqachon bo'lsa — o'shani qaytaramiz (dublikat ochilmasin)
    const exists = await client.query(
      `SELECT * FROM menu_items WHERE type = 'pf' AND ingredient_id = $1 AND is_active = true LIMIT 1`,
      [ingredientId]
    );
    if (exists.rows.length) {
      await client.query('COMMIT');
      return res.json(exists.rows[0]);
    }

    const item = await client.query(
      `INSERT INTO menu_items (category_id, name, price, type, ingredient_id)
       VALUES ($1, $2, 0, 'pf', $3) RETURNING *`,
      [category_id, name.trim(), ingredientId]
    );
    await client.query('COMMIT');
    res.status(201).json(item.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// P/F tannarxini sinxronlash: retsept jami -> bog'langan masaliq narxi (price_per_unit).
// Shunda P/F ishlatilgan taomlar tannarxi ham avtomatik to'g'ri chiqadi.
const syncPfCost = async (menuItemId) => {
  if (!menuItemId) return;
  const mi = await pool.query(`SELECT type, ingredient_id, yield_kg FROM menu_items WHERE id = $1`, [menuItemId]);
  if (!mi.rows.length || mi.rows[0].type !== 'pf' || !mi.rows[0].ingredient_id) return;
  const c = await pool.query(
    `SELECT COALESCE(SUM(r.quantity * i.price_per_unit), 0) AS cost
     FROM recipe_items r JOIN ingredients i ON r.ingredient_id = i.id
     WHERE r.menu_item_id = $1`,
    [menuItemId]
  );
  const cost = parseFloat(c.rows[0].cost) || 0;
  const y = parseFloat(mi.rows[0].yield_kg);
  // BATCH MODEL (ega qayta belgiladi 2026-07-09): P/F tannarx/kg = retsept JAMI tannarx ÷ CHIQISH (rashod/yield_kg).
  // Masalan 0.3kg + 0.4kg komponent -> jami tannarx; chiqish 0.7kg bo'lsa -> tannarx/kg = jami/0.7.
  // Chiqish (yield_kg) BERILISHI SHART; berilmasa jami tannarx (per-birlik) sifatida qoladi.
  const price = (y && y > 0) ? (cost / y) : cost;
  await pool.query(`UPDATE ingredients SET price_per_unit = $1 WHERE id = $2`,
    [price, mi.rows[0].ingredient_id]);
};

// Partiya chiqishini (ВЫХОД, kg) o'rnatish; keyin P/F narxini qayta hisoblaydi.
const setYield = async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const raw = req.body ? req.body.yield_kg : null;
    const y = (raw === null || raw === undefined || raw === '') ? null : parseFloat(raw);
    if (y !== null && (isNaN(y) || y < 0)) return res.status(400).json({ message: 'yield_kg noto\'g\'ri' });
    const r = await pool.query(`UPDATE menu_items SET yield_kg = $1 WHERE id = $2 RETURNING id, ingredient_id, type`, [y, id]);
    if (!r.rows.length) return res.status(404).json({ message: 'Taom topilmadi' });
    if (r.rows[0].type === 'pf') await syncPfCost(id);       // narx/кг ni yangilaydi
    if (r.rows[0].ingredient_id) await syncPfCostsUsingIngredient(r.rows[0].ingredient_id);
    res.json({ ok: true, yield_kg: y });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Masaliq narxi o'zgarganda — shu masaliqni ishlatgan P/F'lar tannarxini qayta hisoblash
const syncPfCostsUsingIngredient = async (ingredientId) => {
  if (!ingredientId) return;
  const pfs = await pool.query(
    `SELECT DISTINCT m.id FROM menu_items m
     JOIN recipe_items r ON r.menu_item_id = m.id
     WHERE m.type = 'pf' AND r.ingredient_id = $1`,
    [ingredientId]
  );
  for (const p of pfs.rows) await syncPfCost(p.id);
};

const createMenuItem = async (req, res) => {
  const client = await pool.connect();
  try {
    if (!req.body) {
      return res.status(400).json({ message: 'req.body bo\'sh — multipart/form-data yuborilmagan' });
    }
    const { category_id, name, price, type, ingredient_id } = req.body;
    const cleanName = (name || '').toString().replace(/\s+/g, ' ').trim(); // ETAP 5: ortiqcha probel tozalanadi
    if (!cleanName) { client.release(); return res.status(400).json({ message: 'Taom nomi kerak' }); }
    const image_url = req.file ? `/uploads/menu/${req.file.filename}` : null;
    const itemType = type || 'recipe';
    const ingId = ingredient_id ? parseInt(ingredient_id) : null;
    const stationIds = parseStationIds(req.body);
    const primary = stationIds.length ? stationIds[0] : null;
    const force = req.body.force === true || req.body.force === 'true'; // ataylab takror qo'shishga ruxsat

    await client.query('BEGIN');
    // ETAP 5 DUBLIKAT-HIMOYA: shu nomli FAOL taom YOKI shu ingredientli product allaqachon bormi?
    if (!force) {
      const dup = await client.query(
        `SELECT id, name FROM menu_items
         WHERE is_active = true AND (lower(btrim(name)) = lower($1) OR ($2::int IS NOT NULL AND ingredient_id = $2))
         LIMIT 1`, [cleanName, ingId]);
      if (dup.rows.length) {
        await client.query('ROLLBACK');
        return res.status(409).json({
          message: `Bunday taom allaqachon bor: "${dup.rows[0].name}" (#${dup.rows[0].id}). Mavjudini ishlating yoki takror qo'shishni tasdiqlang.`,
          existing_id: dup.rows[0].id,
        });
      }
    }
    // Menyu<->sklad sync: PRODUCT qo'shilsa lekin sklad-ingredient tanlanmagan bo'lsa -> avtomatik yaratamiz
    // (mahsulot skladda ham paydo bo'ladi; kirim narxi shu yerdan kiritiladi -> tannarx to'g'ri).
    let effIngId = ingId;
    if (itemType === 'product' && !effIngId) {
      const ni = await client.query(
        `INSERT INTO ingredients (name, unit, price_per_unit, category) VALUES ($1, 'dona', 0, 'Продукция') RETURNING id`,
        [cleanName]);
      effIngId = ni.rows[0].id;
    }
    const result = await client.query(
      `INSERT INTO menu_items (category_id, name, price, image_url, type, ingredient_id, station_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [category_id, cleanName, price, image_url, itemType, effIngId, primary]
    );
    const itemId = result.rows[0].id;
    for (const sid of stationIds) {
      await client.query(
        `INSERT INTO menu_item_stations (menu_item_id, station_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [itemId, sid]
      );
    }
    await client.query('COMMIT');
    res.status(201).json(result.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

const updateMenuItem = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const { category_id, name, price, is_active } = req.body;
    const cleanName = (name !== undefined && name !== null) ? name.toString().replace(/\s+/g, ' ').trim() : name; // ETAP 5 trim
    const image_url = req.file ? `/uploads/menu/${req.file.filename}` : null;
    const stationIds = parseStationIds(req.body);
    const primary = stationIds.length ? stationIds[0] : null;
    const stationProvided = req.body.station_ids !== undefined || req.body.station_id !== undefined;

    await client.query('BEGIN');
    // Bo'limlar berilgan bo'lsa station_id ni to'g'ridan-to'g'ri yozamiz (hammasi tozalansa $5=null);
    // berilmagan bo'lsa eskisini saqlaymiz (COALESCE).
    const stationExpr = stationProvided ? '$5' : 'COALESCE($5, station_id)';
    let query, params;
    if (image_url) {
      query = `UPDATE menu_items SET category_id=$1, name=$2, price=$3, is_active=$4,
               station_id=${stationExpr}, image_url=$6 WHERE id=$7 RETURNING *`;
      params = [category_id, cleanName, price, is_active, primary, image_url, id];
    } else {
      query = `UPDATE menu_items SET category_id=$1, name=$2, price=$3, is_active=$4,
               station_id=${stationExpr} WHERE id=$6 RETURNING *`;
      params = [category_id, cleanName, price, is_active, primary, id];
    }
    const result = await client.query(query, params);
    // Menyu<->sklad NOM sync: product/pf menyu nomi o'zgarsa, bog'langan ingredient nomi ham (bir xil qoladi)
    {
      const upd = result.rows[0];
      if (upd && upd.ingredient_id && (upd.type === 'product' || upd.type === 'pf') && cleanName && cleanName.length) {
        await client.query(`UPDATE ingredients SET name = $1 WHERE id = $2`, [cleanName, upd.ingredient_id]);
      }
    }
    // Bo'limlar berilgan bo'lsa — junction'ni qayta yozamiz
    if (stationProvided) {
      await client.query(`DELETE FROM menu_item_stations WHERE menu_item_id = $1`, [id]);
      for (const sid of stationIds) {
        await client.query(
          `INSERT INTO menu_item_stations (menu_item_id, station_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [id, sid]
        );
      }
    }
    await client.query('COMMIT');
    res.json(result.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Taomni o'chirish. Zakaz tarixi YO'Q bo'lsa — butunlay o'chiriladi (retsept +
// bo'limlar ham). Tarixi BOR bo'lsa — yashiriladi (is_active=false), aks holda
// hisobot/zakaz tarixi buziladi.
const deleteMenuItem = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    await client.query('BEGIN');
    // Menyu<->sklad sync: product/pf bo'lsa bog'langan ingredientni ham arxivlaymiz (so'rov #3)
    const info = await client.query('SELECT type, ingredient_id FROM menu_items WHERE id = $1', [id]);
    const mType = info.rows[0] && info.rows[0].type;
    const mIng = info.rows[0] && info.rows[0].ingredient_id;
    const archiveLinkedIngredient = async () => {
      if (!mIng || !(mType === 'product' || mType === 'pf')) return;
      // faqat boshqa hech narsa ishlatmasa (retsept yoki boshqa FAOL menyu)
      await client.query(
        `UPDATE ingredients SET is_active = false WHERE id = $1
           AND NOT EXISTS (SELECT 1 FROM recipe_items WHERE ingredient_id = $1)
           AND NOT EXISTS (SELECT 1 FROM menu_items WHERE ingredient_id = $1 AND is_active = true AND id <> $2)`,
        [mIng, id]);
    };
    const used = await client.query('SELECT 1 FROM order_items WHERE menu_item_id = $1 LIMIT 1', [id]);
    if (used.rows.length) {
      await client.query('UPDATE menu_items SET is_active = false WHERE id = $1', [id]);
      await archiveLinkedIngredient();
      await client.query('COMMIT');
      return res.json({ message: 'Taom yashirildi + bog\'langan sklad mahsuloti arxivlandi (zakaz tarixi bor)', removed: false });
    }
    await client.query('DELETE FROM recipe_items WHERE menu_item_id = $1', [id]);
    await client.query('DELETE FROM menu_item_stations WHERE menu_item_id = $1', [id]);
    await client.query('DELETE FROM menu_items WHERE id = $1', [id]);
    await archiveLinkedIngredient(); // qolgan ingredient yetim qolsa -> arxiv (hard-delete FK-xavfli)
    await client.query('COMMIT');
    res.json({ message: 'Taom o\'chirildi (bog\'langan sklad mahsuloti ham arxivlandi)', removed: true });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// KUNLIK KUZAT: taomga "kunlik hisob" belgisini qo'yish/olib tashlash (admin).
// Belgilangan taomga ertalab son kiritilsa — shuncha sotiladi (tugasa to'xtaydi).
const setDailyTracked = async (req, res) => {
  try {
    const { id } = req.params;
    const tracked = req.body.tracked === true || req.body.tracked === 'true';
    const result = await pool.query(
      `UPDATE menu_items SET daily_tracked = $1 WHERE id = $2 RETURNING id, name, daily_tracked`,
      [tracked, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ message: 'Taom topilmadi' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// STOP-LIST: taomning "tayyor"/"tayyor emas" holatini almashtirish (admin)
const setMenuAvailability = async (req, res) => {
  try {
    const { id } = req.params;
    const available = req.body.available === true || req.body.available === 'true';
    const result = await pool.query(
      `UPDATE menu_items SET available=$1 WHERE id=$2 RETURNING id, name, available`,
      [available, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ message: 'Taom topilmadi' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sklad (Ingredientlar)
const getIngredients = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM ingredients ORDER BY name`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const createIngredient = async (req, res) => {
  try {
    const { name, unit, stock_quantity, min_quantity } = req.body;
    const result = await pool.query(
      `INSERT INTO ingredients (name, unit, stock_quantity, min_quantity)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [name, unit, stock_quantity || 0, min_quantity || 0]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const updateIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const { stock_quantity, min_quantity } = req.body;
    const result = await pool.query(
      `UPDATE ingredients SET stock_quantity=$1, min_quantity=$2 WHERE id=$3 RETURNING *`,
      [stock_quantity, min_quantity, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Tannarx hisoblash
const getMenuItemCost = async (req, res) => {
  try {
    const { id } = req.params;
    const itemResult = await pool.query(
      `SELECT id, name, price, type, ingredient_id FROM menu_items WHERE id = $1`,
      [id]
    );
    if (itemResult.rows.length === 0) {
      return res.status(404).json({ message: 'Taom topilmadi' });
    }
    const menuItem = itemResult.rows[0];
    const price = parseFloat(menuItem.price);

    // Product type: tannarx = ingredient.price_per_unit
    if (menuItem.type === 'product' && menuItem.ingredient_id) {
      const ingResult = await pool.query(
        `SELECT price_per_unit FROM ingredients WHERE id = $1`,
        [menuItem.ingredient_id]
      );
      const ing = ingResult.rows[0];
      const cost = ing ? parseFloat(ing.price_per_unit || 0) : 0;
      const profit = price - cost;
      const profit_percent = price > 0 ? parseFloat(((profit / price) * 100).toFixed(1)) : 0;
      return res.json({
        menu_item_id: menuItem.id,
        name: menuItem.name,
        price: Math.round(price),
        cost: Math.round(cost),
        profit: Math.round(profit),
        profit_percent,
        ingredients: [],
      });
    }

    // Recipe type: tannarx = recipe_items * ingredient narxlari
    const recipeResult = await pool.query(
      `SELECT r.quantity, i.name, i.unit, i.price_per_unit,
              (r.quantity * i.price_per_unit) AS total
       FROM recipe_items r
       JOIN ingredients i ON r.ingredient_id = i.id
       WHERE r.menu_item_id = $1`,
      [id]
    );

    const ingredients = recipeResult.rows;
    const cost = ingredients.reduce((sum, ing) => sum + parseFloat(ing.total || 0), 0);
    const profit = price - cost;
    const profit_percent = price > 0 ? parseFloat(((profit / price) * 100).toFixed(1)) : 0;

    res.json({
      menu_item_id: menuItem.id,
      name: menuItem.name,
      price: Math.round(price),
      cost: Math.round(cost),
      profit: Math.round(profit),
      profit_percent,
      ingredients: ingredients.map(ing => ({
        name: ing.name,
        quantity: parseFloat(ing.quantity),
        unit: ing.unit,
        price_per_unit: parseFloat(ing.price_per_unit),
        total: Math.round(parseFloat(ing.total || 0)),
      })),
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Retsept
// Retsept satrlari: brutto (quantity), chiqish% (yield_percent), narx (price_per_unit).
// netto va tannarx frontendда hisoblanadi (netto=brutto*yield/100, tannarx=brutto*narx).
const getRecipe = async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT r.id, r.menu_item_id, r.ingredient_id, r.quantity,
              COALESCE(r.yield_percent, 100) AS yield_percent,
              i.name as ingredient_name, i.unit,
              COALESCE(i.price_per_unit, 0) AS price_per_unit,
              i.warehouse_id, w.name AS warehouse_name,
              i.category AS ingredient_category
       FROM recipe_items r
       JOIN ingredients i ON r.ingredient_id = i.id
       LEFT JOIN warehouses w ON i.warehouse_id = w.id
       WHERE r.menu_item_id = $1
       ORDER BY r.id`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const addRecipeItem = async (req, res) => {
  try {
    const { menu_item_id, ingredient_name, unit, quantity, yield_percent, price_per_unit } = req.body;
    const directId = parseInt(req.body.ingredient_id); // P/F: mavjud masaliq to'g'ridan-to'g'ri
    if (!menu_item_id || !quantity || (isNaN(directId) && (!ingredient_name || !unit))) {
      return res.status(400).json({ message: 'menu_item_id, quantity va (ingredient_id yoki ingredient_name+unit) majburiy' });
    }
    const price = parseFloat(price_per_unit) || 0;
    const whId = parseInt(req.body.warehouse_id);
    const warehouseId = isNaN(whId) ? null : whId;
    let yp = parseFloat(yield_percent);
    if (!(yp > 0 && yp <= 100)) yp = 100;

    let ingredientId;
    if (!isNaN(directId)) {
      // P/F yoki mavjud masaliq — narx/birlikka TEGMAYMIZ (P/F narxi retseptidan sync bo'ladi)
      const chk = await pool.query(`SELECT id FROM ingredients WHERE id = $1`, [directId]);
      if (!chk.rows.length) return res.status(404).json({ message: 'Masaliq topilmadi' });
      // P/F o'z retseptiga o'zini qo'sha olmasin (cheksiz aylanish)
      const self = await pool.query(
        `SELECT 1 FROM menu_items WHERE id = $1 AND type = 'pf' AND ingredient_id = $2`,
        [menu_item_id, directId]
      );
      if (self.rows.length) return res.status(400).json({ message: 'P/F o\'z retseptiga o\'zini qo\'sha olmaydi' });
      ingredientId = directId;
    } else {
      // Masaliq SHU SKLADDA bormi (har sklad o'z masaliqlariga ega — aralashmaydi).
      let ingResult = await pool.query(
        warehouseId
          ? `SELECT id FROM ingredients WHERE name ILIKE $1 AND warehouse_id = $2 LIMIT 1`
          : `SELECT id FROM ingredients WHERE name ILIKE $1 AND warehouse_id IS NULL LIMIT 1`,
        warehouseId ? [ingredient_name.trim(), warehouseId] : [ingredient_name.trim()]
      );

      if (ingResult.rows.length > 0) {
        ingredientId = ingResult.rows[0].id;
        await pool.query(
          `UPDATE ingredients SET unit = $1,
                  price_per_unit = CASE WHEN $2 > 0 THEN $2 ELSE price_per_unit END
           WHERE id = $3`,
          [unit, price, ingredientId]
        );
      } else {
        const newIng = await pool.query(
          `INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category, warehouse_id)
           VALUES ($1, $2, 0, 0, $3, 'Ингредиенты', $4) RETURNING id`,
          [ingredient_name.trim(), unit, price, warehouseId]
        );
        ingredientId = newIng.rows[0].id;
      }
    }

    const result = await pool.query(
      `INSERT INTO recipe_items (menu_item_id, ingredient_id, quantity, yield_percent)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [menu_item_id, ingredientId, quantity, yp]
    );
    // P/F tannarxlarini yangilash: shu taom P/F bo'lsa + shu masaliqni ishlatgan P/F'lar
    await syncPfCost(parseInt(menu_item_id));
    await syncPfCostsUsingIngredient(ingredientId);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Retsept satrini tahrirlash (brutto/chiqish% + ingredient narx/birlik)
const updateRecipeItem = async (req, res) => {
  try {
    const { id } = req.params;
    const { quantity, yield_percent, price_per_unit, unit } = req.body;
    let yp = parseFloat(yield_percent);
    if (!(yp > 0 && yp <= 100)) yp = null;
    const r = await pool.query(
      `UPDATE recipe_items SET quantity = COALESCE($1, quantity),
              yield_percent = COALESCE($2, yield_percent)
       WHERE id = $3 RETURNING ingredient_id, menu_item_id`,
      [quantity != null ? quantity : null, yp, id]
    );
    if (r.rows.length === 0) return res.status(404).json({ message: 'Satr topilmadi' });
    const price = parseFloat(price_per_unit);
    // П/Ф masaliq narxi qo'lda o'zgartirilmaydi — u o'z retseptidan sync bo'ladi.
    // P/F aniqlash: ISHONCHLI signal = pf menu_item ga bog'langanmi (type='pf'); 'П/Ф' string faqat fallback
    // (magic-stringга yolg'iz bog'liq emas — nom/kategoriya xato yozilsa ham himoya ishlaydi).
    const ingInfo = await pool.query(
      `SELECT i.category,
              EXISTS(SELECT 1 FROM menu_items m WHERE m.ingredient_id = i.id AND m.type = 'pf') AS pf_linked
       FROM ingredients i WHERE i.id = $1`, [r.rows[0].ingredient_id]);
    const isPfIngredient = ingInfo.rows.length &&
      (ingInfo.rows[0].pf_linked === true || ingInfo.rows[0].category === 'П/Ф');
    if ((!isNaN(price) || unit) && !isPfIngredient) {
      await pool.query(
        `UPDATE ingredients SET
                price_per_unit = CASE WHEN $1 >= 0 THEN $1 ELSE price_per_unit END,
                unit = COALESCE($2, unit)
         WHERE id = $3`,
        [isNaN(price) ? -1 : price, unit || null, r.rows[0].ingredient_id]
      );
    }
    await syncPfCost(r.rows[0].menu_item_id);
    await syncPfCostsUsingIngredient(r.rows[0].ingredient_id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const deleteRecipeItem = async (req, res) => {
  try {
    const { id } = req.params;
    const del = await pool.query(`DELETE FROM recipe_items WHERE id = $1 RETURNING menu_item_id`, [id]);
    if (del.rows.length) await syncPfCost(del.rows[0].menu_item_id); // P/F bo'lsa tannarxi yangilanadi
    res.json({ message: 'O\'chirildi!' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = {
  getCategories, createCategory, updateCategory, deleteCategory,
  getMenuItems, createMenuItem, updateMenuItem, deleteMenuItem, setMenuAvailability, setDailyTracked, getMenuItemCost,
  createPfItem, setYield,
  getIngredients, createIngredient, updateIngredient,
  getRecipe, addRecipeItem, updateRecipeItem, deleteRecipeItem
};