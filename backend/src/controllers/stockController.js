const pool = require('../config/db');

// Barcha mahsulotlar (sklad) — sklad va kategoriya bo'yicha filtr
const getIngredients = async (req, res) => {
  try {
    const { category, warehouse_id } = req.query;
    const conditions = ['COALESCE(is_active, true) = true']; // arxivlangan (soft-deleted) mahsulotlar ko'rinmaydi
    const params = [];
    if (warehouse_id) {
      params.push(warehouse_id);
      conditions.push(`warehouse_id = $${params.length}`);
    }
    if (category) {
      params.push(category);
      conditions.push(`category = $${params.length}`);
    }
    let query = `SELECT * FROM ingredients`;
    if (conditions.length > 0) {
      query += ` WHERE ` + conditions.join(' AND ');
    }
    query += ` ORDER BY name`;
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulot qo'shish (tanlangan skladga)
const createIngredient = async (req, res) => {
  try {
    const { name, unit, stock_quantity, min_quantity, price_per_unit, category, warehouse_id } = req.body;
    const result = await pool.query(
      `INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, category, warehouse_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [name, unit, stock_quantity || 0, min_quantity || 0, price_per_unit || 0, category || null, warehouse_id || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulot keldi (kirim)
const addIncoming = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { ingredient_id, quantity, price_per_unit, selling_price, note } = req.body;
    const total_amount = quantity * price_per_unit;
    const method = req.body.method === 'card' ? 'card' : 'cash';
    // Pul manbasi: Kassadan (default) yoki boshqa joydan. Boshqa bo'lsa Kassadan yechilmaydi.
    const fromKassa = req.body.from_kassa !== false && req.body.from_kassa !== 'false';
    const sourceText = fromKassa ? 'kassa' : ((req.body.source || '').toString().trim().slice(0, 120) || 'boshqa');

    const inc = await client.query(
      `INSERT INTO stock_incoming (ingredient_id, quantity, price_per_unit, total_amount, note, method, source)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
      [ingredient_id, quantity, price_per_unit, total_amount, note, method, sourceText]
    );

    // Faqat Kassadan to'langanda va summa > 0 bo'lsa Kassadan chiqim qilamiz
    if (fromKassa && total_amount > 0) {
      const ingRow = await client.query(`SELECT name FROM ingredients WHERE id = $1`, [ingredient_id]);
      const ingName = (ingRow.rows[0] && ingRow.rows[0].name) ? ingRow.rows[0].name : 'Mahsulot';
      const txNote = note && note.toString().trim() ? `${ingName} — ${note}` : `${ingName} (sklad kirim)`;
      await client.query(
        `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
         VALUES ('expense', $1, $2, 'stock', $3, $4)`,
        [method, total_amount, inc.rows[0].id, txNote]
      );
    }

    if (selling_price !== undefined && selling_price !== null) {
      await client.query(
        `UPDATE ingredients
         SET stock_quantity = stock_quantity + $1, price_per_unit = $2, selling_price = $3
         WHERE id = $4`,
        [quantity, price_per_unit, selling_price, ingredient_id]
      );
    } else {
      await client.query(
        `UPDATE ingredients
         SET stock_quantity = stock_quantity + $1, price_per_unit = $2
         WHERE id = $3`,
        [quantity, price_per_unit, ingredient_id]
      );
    }

    await client.query('COMMIT');
    res.status(201).json({ message: 'Mahsulot qabul qilindi!', total_amount });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Kirim tarixi
const getIncomingHistory = async (req, res) => {
  try {
    const { ingredient_id } = req.query;
    let query = `
      SELECT si.*, i.name as ingredient_name, i.unit
      FROM stock_incoming si
      JOIN ingredients i ON si.ingredient_id = i.id
    `;
    const params = [];
    if (ingredient_id) {
      query += ` WHERE si.ingredient_id = $1`;
      params.push(ingredient_id);
    }
    query += ` ORDER BY si.created_at DESC LIMIT 50`;
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Kam qolgan mahsulotlar
const getLowStock = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM ingredients
       WHERE min_quantity > 0 AND stock_quantity <= min_quantity
       ORDER BY stock_quantity ASC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sotish narxini yangilash
const updateSellingPrice = async (req, res) => {
  try {
    const { id } = req.params;
    const { selling_price } = req.body;
    const result = await pool.query(
      `UPDATE ingredients SET selling_price = $1 WHERE id = $2 RETURNING *`,
      [selling_price, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulotni TAHRIRLASH — nom, birlik, min, kirim narxi, sotish narxi, qoldiq.
// SABAB majburiy. Har o'zgarish stock_change_log ga yoziladi (kim/nima/nega).
const editIngredient = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const reason = (req.body.reason || '').toString().trim();
    if (!reason) {
      return res.status(400).json({ message: 'Sabab yozish shart!' });
    }
    const { name, unit, min_quantity, price_per_unit, selling_price, stock_quantity } = req.body;

    await client.query('BEGIN');
    const cur = await client.query('SELECT * FROM ingredients WHERE id = $1', [id]);
    if (cur.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Mahsulot topilmadi!' });
    }
    const old = cur.rows[0];

    // Berilmagan (undefined/'') maydonlar eski qiymatda qoladi
    const has = (v) => v !== undefined && v !== null && v.toString().trim() !== '';
    const nName = has(name) ? name.toString().trim() : old.name;
    const nUnit = has(unit) ? unit.toString().trim() : old.unit;
    const nMin = has(min_quantity) ? parseFloat(min_quantity) : parseFloat(old.min_quantity || 0);
    const nPrice = has(price_per_unit) ? parseFloat(price_per_unit) : parseFloat(old.price_per_unit || 0);
    const nSell = has(selling_price) ? parseFloat(selling_price) : parseFloat(old.selling_price || 0);
    const nStock = has(stock_quantity) ? parseFloat(stock_quantity) : parseFloat(old.stock_quantity || 0);

    const num = (v) => parseFloat(v || 0);
    const diff = (a, b) => Math.abs(num(a) - num(b)) > 1e-9;
    const parts = [];
    if (nName !== old.name) parts.push(`Nomi: "${old.name}" -> "${nName}"`);
    if (nUnit !== old.unit) parts.push(`Birlik: "${old.unit}" -> "${nUnit}"`);
    if (diff(nMin, old.min_quantity)) parts.push(`Min: ${num(old.min_quantity)} -> ${nMin}`);
    if (diff(nPrice, old.price_per_unit)) parts.push(`Kirim narxi: ${num(old.price_per_unit)} -> ${nPrice}`);
    if (diff(nSell, old.selling_price)) parts.push(`Sotish narxi: ${num(old.selling_price)} -> ${nSell}`);
    if (diff(nStock, old.stock_quantity)) parts.push(`Qoldiq: ${num(old.stock_quantity)} -> ${nStock}`);

    if (parts.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Hech narsa o\'zgarmadi' });
    }

    await client.query(
      `UPDATE ingredients
       SET name = $1, unit = $2, min_quantity = $3, price_per_unit = $4,
           selling_price = $5, stock_quantity = $6
       WHERE id = $7`,
      [nName, nUnit, nMin, nPrice, nSell, nStock, id]
    );

    let userName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      userName = u.rows[0] ? u.rows[0].full_name : null;
    }
    await client.query(
      `INSERT INTO stock_change_log (ingredient_id, user_id, user_name, changes, reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, req.user ? req.user.id : null, userName, parts.join('; '), reason]
    );

    await client.query('COMMIT');
    res.json({ message: 'O\'zgartirildi!', changes: parts.join('; ') });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// P/F TAYYORLASH (ishlab chiqarish): oshpaz "N birlik tayyorladim" deydi ->
// P/F qoldig'i +N, retseptidagi xom masaliqlar -N*brutto (Kassaga tegilmaydi).
// body: { ingredient_id (P/F sklad masaligi), quantity }
const producePf = async (req, res) => {
  const client = await pool.connect();
  try {
    const ingId = parseInt(req.body.ingredient_id);
    const qty = parseFloat(req.body.quantity);
    if (isNaN(ingId) || !(qty > 0)) {
      return res.status(400).json({ message: 'ingredient_id va musbat quantity kerak' });
    }
    await client.query('BEGIN');
    const mi = await client.query(
      `SELECT id FROM menu_items WHERE type = 'pf' AND ingredient_id = $1 AND is_active = true LIMIT 1`,
      [ingId]
    );
    if (!mi.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Bu masaliq P/F emas (retsepti yo\'q)' });
    }
    const rec = await client.query(
      `SELECT ingredient_id, quantity FROM recipe_items WHERE menu_item_id = $1`,
      [mi.rows[0].id]
    );
    if (!rec.rows.length) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'P/F retsepti bo\'sh — avval retseptini kiriting' });
    }
    // P/F +N
    await client.query(`UPDATE ingredients SET stock_quantity = stock_quantity + $1 WHERE id = $2`, [qty, ingId]);
    // Komponentlar -N*brutto
    for (const r of rec.rows) {
      await client.query(
        `UPDATE ingredients SET stock_quantity = stock_quantity - $1 WHERE id = $2`,
        [qty * parseFloat(r.quantity), r.ingredient_id]
      );
    }
    // Tarix (kirim jurnalida ko'rinadi, kassaga YOZILMAYDI)
    const c = await client.query(`SELECT COALESCE(price_per_unit,0) AS p FROM ingredients WHERE id = $1`, [ingId]);
    const unitCost = parseFloat(c.rows[0].p) || 0;
    await client.query(
      `INSERT INTO stock_incoming (ingredient_id, quantity, price_per_unit, total_amount, note, method, source)
       VALUES ($1, $2, $3, $4, 'P/F tayyorlash', 'cash', 'pf_production')`,
      [ingId, qty, unitCost, qty * unitCost]
    );
    await client.query('COMMIT');
    res.json({ ok: true, produced: qty });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Mahsulot o'zgarishlar tarixi (audit)
const getStockHistory = async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT id, changes, reason, user_name, created_at
       FROM stock_change_log
       WHERE ingredient_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulotni o'chirish (faqat ombor bo'sh bo'lsa)
const deleteIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const check = await pool.query(`SELECT stock_quantity FROM ingredients WHERE id = $1`, [id]);
    if (check.rows.length === 0) {
      return res.status(404).json({ message: 'Mahsulot topilmadi!' });
    }
    // Bog'liqlik bormi (retsept / menyu / kirim-inventar tarixi)?
    const deps = await pool.query(
      `SELECT
         (SELECT COUNT(*) FROM recipe_items    WHERE ingredient_id = $1) AS rc,
         (SELECT COUNT(*) FROM menu_items      WHERE ingredient_id = $1) AS mc,
         (SELECT COUNT(*) FROM inventory_items WHERE ingredient_id = $1) AS ic,
         (SELECT COUNT(*) FROM stock_incoming  WHERE ingredient_id = $1) AS sc`,
      [id]);
    const d = deps.rows[0];
    const inUse = ['rc','mc','ic','sc'].some((k) => (parseInt(d[k], 10) || 0) > 0);
    if (inUse) {
      // Bog'langan -> hard delete FK ni buzardi. Shuning uchun ARXIVLAYMIZ (skladdan ketadi, tarix saqlanadi).
      await pool.query(`UPDATE ingredients SET is_active = false WHERE id = $1`, [id]);
      // Menyu<->sklad sync: bu ingredientga bog'langan PRODUCT menyu mahsulotini ham arxivlaymiz
      await pool.query(`UPDATE menu_items SET is_active = false WHERE ingredient_id = $1 AND type = 'product'`, [id]);
      return res.json({ message: 'Mahsulot arxivlandi (bog\'lanishlari bor — tarix saqlanadi, skladdan olib tashlandi)' });
    }
    // Bog'lanmagan — haqiqiy o'chirish
    try {
      await pool.query(`DELETE FROM ingredients WHERE id = $1`, [id]);
    } catch (e) {
      if (e.code === '23503') { // kutilmagan FK -> arxivlaymiz
        await pool.query(`UPDATE ingredients SET is_active = false WHERE id = $1`, [id]);
        return res.json({ message: 'Mahsulot arxivlandi (bog\'liq yozuvlar bor)' });
      }
      throw e;
    }
    res.json({ message: 'Mahsulot o\'chirildi!' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// DUBLIKATNI BIRLASHTIRISH (merge): :id ni target_id ichiga qo'shadi —
// retseptlar/menyu/inventar target ga perecepilanadi, ombor qoldig'i QO'SHILADI
// (MINUS saqlanadi — ataylab), so'ng :id o'chiriladi. Ishlatilayotgan dublikatni
// shu yo'l bilan tozalash mumkin (oddiy o'chirish taqiqlangan).
const mergeIngredient = async (req, res) => {
  const client = await pool.connect();
  try {
    const id = parseInt(req.params.id);
    const targetId = parseInt(req.body ? req.body.target_id : null);
    if (!id || !targetId || id === targetId) {
      return res.status(400).json({ message: 'target_id kerak va o\'ziga qo\'shib bo\'lmaydi' });
    }
    await client.query('BEGIN');
    const rows = (await client.query(`SELECT id, name, stock_quantity FROM ingredients WHERE id = ANY($1)`, [[id, targetId]])).rows;
    if (rows.length < 2) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Mahsulot topilmadi' }); }
    const src = rows.find((r) => r.id === id);
    // ombor qoldig'ini target ga qo'shamiz (minus saqlanadi — oddiy arifmetika)
    await client.query(`UPDATE ingredients SET stock_quantity = COALESCE(stock_quantity,0) + $1 WHERE id = $2`,
      [parseFloat(src.stock_quantity) || 0, targetId]);
    // ingredient_id ustuni bor BARCHA jadvallarni dinamik perecepilaymiz
    const refTables = (await client.query(
      `SELECT table_name FROM information_schema.columns WHERE column_name='ingredient_id' AND table_schema='public'`
    )).rows.map((r) => r.table_name);
    for (const t of refTables) {
      await client.query(`UPDATE ${t} SET ingredient_id = $1 WHERE ingredient_id = $2`, [targetId, id]);
    }
    // recipe_items kolliziya: bir taomda target ikki marta bo'lsa -> quantity qo'shib bittaga
    const rcol = (await client.query(
      `SELECT menu_item_id, array_agg(id ORDER BY id) ids, SUM(quantity) q
       FROM recipe_items WHERE ingredient_id=$1 GROUP BY menu_item_id HAVING COUNT(*)>1`, [targetId])).rows;
    for (const c of rcol) {
      await client.query(`UPDATE recipe_items SET quantity=$1 WHERE id=$2`, [c.q, c.ids[0]]);
      await client.query(`DELETE FROM recipe_items WHERE id = ANY($1)`, [c.ids.slice(1)]);
    }
    // inventory_items kolliziya: bir inventarizatsiyada target ikki marta
    const icol = (await client.query(
      `SELECT inventory_id, array_agg(id ORDER BY id) ids, SUM(expected_quantity) eq, SUM(actual_quantity) aq, SUM(difference) df
       FROM inventory_items WHERE ingredient_id=$1 GROUP BY inventory_id HAVING COUNT(*)>1`, [targetId])).rows;
    for (const c of icol) {
      await client.query(`UPDATE inventory_items SET expected_quantity=$1, actual_quantity=$2, difference=$3 WHERE id=$4`,
        [c.eq, c.aq, c.df, c.ids[0]]);
      await client.query(`DELETE FROM inventory_items WHERE id = ANY($1)`, [c.ids.slice(1)]);
    }
    await client.query(`DELETE FROM ingredients WHERE id = $1`, [id]);
    await client.query('COMMIT');
    res.json({ ok: true, message: 'Dublikat birlashtirildi' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// ===== SKLADLAR (warehouses) =====

// Skladlar ro'yxati
const getWarehouses = async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM warehouses ORDER BY id`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi sklad
const createWarehouse = async (req, res) => {
  try {
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Sklad nomi kiritilmadi!' });
    }
    const result = await pool.query(
      `INSERT INTO warehouses (name) VALUES ($1) RETURNING *`,
      [name.trim()]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sklad nomini tahrirlash
const updateWarehouse = async (req, res) => {
  try {
    const { id } = req.params;
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Sklad nomi kiritilmadi!' });
    }
    const result = await pool.query(
      `UPDATE warehouses SET name = $1 WHERE id = $2 RETURNING *`,
      [name.trim(), id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Sklad topilmadi!' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sklad o'chirish (faqat ichida mahsulot yo'q bo'lsa)
const deleteWarehouse = async (req, res) => {
  try {
    const { id } = req.params;
    const check = await pool.query(
      `SELECT COUNT(*)::int AS cnt FROM ingredients WHERE warehouse_id = $1`,
      [id]
    );
    if (check.rows[0].cnt > 0) {
      return res.status(400).json({ message: 'Sklad bo\'sh emas! Avval mahsulotlarni o\'chiring yoki ko\'chiring.' });
    }
    await pool.query(`DELETE FROM warehouses WHERE id = $1`, [id]);
    res.json({ message: 'Sklad o\'chirildi!' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Retsept bo'yicha ingredientlarni skladga biriktirish
// body: { warehouse_id, category_name?, name_like? }
const assignFromRecipe = async (req, res) => {
  try {
    const { warehouse_id, category_name, name_like } = req.body;
    if (!warehouse_id) {
      return res.status(400).json({ message: 'warehouse_id kerak!' });
    }
    const conditions = [];
    const params = [warehouse_id];
    if (category_name && category_name.trim()) {
      params.push(`%${category_name.trim()}%`);
      conditions.push(`mc.name ILIKE $${params.length}`);
    }
    if (name_like && name_like.trim()) {
      params.push(`%${name_like.trim()}%`);
      conditions.push(`mi.name ILIKE $${params.length}`);
    }
    if (conditions.length === 0) {
      return res.status(400).json({ message: 'Kamida kategoriya nomi yoki taom nomi kiriting!' });
    }

    const result = await pool.query(
      `UPDATE ingredients SET warehouse_id = $1
       WHERE id IN (
         SELECT DISTINCT ri.ingredient_id
         FROM recipe_items ri
         JOIN menu_items mi ON ri.menu_item_id = mi.id
         LEFT JOIN menu_categories mc ON mi.category_id = mc.id
         WHERE ${conditions.join(' OR ')}
       )
       RETURNING id`,
      params
    );

    res.json({
      message: `${result.rowCount} ta ingredient biriktirildi`,
      count: result.rowCount,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ─── INGREDIENT KATEGORIYALAR (ETAP 3.1 spravochnik — menu_categories kabi, id bo'yicha) ───
const getIngredientCategories = async (req, res) => {
  try {
    const r = await pool.query(
      `SELECT id, name, COALESCE(is_pf,false) AS is_pf, COALESCE(is_retail,false) AS is_retail
       FROM ingredient_categories ORDER BY name`);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};
const createIngredientCategory = async (req, res) => {
  try {
    const name = (req.body.name || '').toString().trim();
    if (!name) return res.status(400).json({ message: 'Nom kerak' });
    const is_pf = req.body.is_pf === true || req.body.is_pf === 'true';
    const is_retail = req.body.is_retail === true || req.body.is_retail === 'true';
    const r = await pool.query(
      `INSERT INTO ingredient_categories (name, is_pf, is_retail) VALUES ($1,$2,$3)
       ON CONFLICT (name) DO UPDATE SET is_pf=EXCLUDED.is_pf, is_retail=EXCLUDED.is_retail RETURNING *`,
      [name, is_pf, is_retail]);
    res.status(201).json(r.rows[0]);
  } catch (err) { res.status(500).json({ message: err.message }); }
};
const updateIngredientCategory = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const name = (req.body.name || '').toString().trim();
    if (!name) { client.release(); return res.status(400).json({ message: 'Nom kerak' }); }
    await client.query('BEGIN');
    const old = await client.query(`SELECT 1 FROM ingredient_categories WHERE id=$1`, [id]);
    if (!old.rows.length) { await client.query('ROLLBACK'); client.release(); return res.status(404).json({ message: 'Topilmadi' }); }
    await client.query(`UPDATE ingredient_categories SET name=$1 WHERE id=$2`, [name, id]);
    // rename propagatsiya (id bo'yicha): shu kategoriyали ingredientlarning string nomi ham yangilanadi
    await client.query(`UPDATE ingredients SET category=$1 WHERE category_id=$2`, [name, id]);
    await client.query('COMMIT');
    res.json({ ok: true, name });
  } catch (err) { await client.query('ROLLBACK').catch(()=>{}); res.status(500).json({ message: err.message }); }
  finally { client.release(); }
};
const deleteIngredientCategory = async (req, res) => {
  try {
    const { id } = req.params;
    const used = await pool.query(`SELECT COUNT(*)::int AS n FROM ingredients WHERE category_id=$1`, [id]);
    if (used.rows[0].n > 0) return res.status(400).json({ message: `Kategoriyada ${used.rows[0].n} ta mahsulot bor — avval ko'chiring.` });
    await pool.query(`DELETE FROM ingredient_categories WHERE id=$1`, [id]);
    res.json({ message: 'Kategoriya o\'chirildi' });
  } catch (err) {
    if (err.code === '23503') return res.status(400).json({ message: 'Kategoriya ishlatilmoqda.' });
    res.status(500).json({ message: err.message });
  }
};

module.exports = {
  getIngredients, createIngredient, addIncoming, getIncomingHistory, getLowStock, updateSellingPrice, deleteIngredient,
  mergeIngredient,
  editIngredient, getStockHistory, producePf,
  getWarehouses, createWarehouse, updateWarehouse, deleteWarehouse, assignFromRecipe,
  getIngredientCategories, createIngredientCategory, updateIngredientCategory, deleteIngredientCategory
};