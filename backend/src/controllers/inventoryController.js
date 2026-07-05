const pool = require('../config/db');

// Barcha inventarizatsiyalar (ixtiyoriy ?warehouse_id va ?type filtri bilan)
const getInventories = async (req, res) => {
  try {
    const { warehouse_id, type } = req.query;
    const params = [];
    const conds = [];
    // type berilmasa eski xulq: faqat oziq-ovqat (ingredient) inventarizatsiyalari
    params.push(type || 'ingredient');
    conds.push(`COALESCE(i.type, 'ingredient') = $${params.length}`);
    if (warehouse_id) {
      params.push(warehouse_id);
      conds.push(`i.warehouse_id = $${params.length}`);
    }
    const where = `WHERE ${conds.join(' AND ')}`;
    const result = await pool.query(
      `SELECT i.*, u.full_name as created_by_name, w.name as warehouse_name
       FROM inventory_checks i
       LEFT JOIN users u ON i.created_by = u.id
       LEFT JOIN warehouses w ON i.warehouse_id = w.id
       ${where}
       ORDER BY i.created_at DESC`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi inventarizatsiya boshlash (sklad bo'yicha oziq-ovqat yoki idishlar)
const createInventory = async (req, res) => {
  try {
    const { created_by, warehouse_id, type } = req.body;
    const invType = type === 'tableware' ? 'tableware' : 'ingredient';
    const today = new Date().toISOString().split('T')[0];

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Idishlar restoran bo'yicha umumiy — skladga bog'lanmaydi
      const whId = invType === 'tableware' ? null : (warehouse_id || null);

      const inventory = await client.query(
        `INSERT INTO inventory_checks (check_date, created_by, warehouse_id, type)
         VALUES ($1, $2, $3, $4) RETURNING *`,
        [today, created_by, whId, invType]
      );
      const inventoryId = inventory.rows[0].id;

      if (invType === 'tableware') {
        // Idishlar katalogini snapshot qilish
        const items = await client.query(
          `SELECT * FROM tableware WHERE is_active = true ORDER BY name`
        );
        for (const tw of items.rows) {
          await client.query(
            `INSERT INTO inventory_items
             (inventory_id, tableware_id, expected_quantity, actual_quantity, difference)
             VALUES ($1, $2, $3, 0, $3)`,
            [inventoryId, tw.id, tw.quantity]
          );
        }
      } else {
        // Oziq-ovqat — sklad berilgan bo'lsa faqat o'sha skladdan
        const ingredients = warehouse_id
          ? await client.query(
              `SELECT * FROM ingredients WHERE warehouse_id = $1 ORDER BY category, name`,
              [warehouse_id]
            )
          : await client.query(`SELECT * FROM ingredients ORDER BY category, name`);

        for (const ing of ingredients.rows) {
          await client.query(
            `INSERT INTO inventory_items
             (inventory_id, ingredient_id, expected_quantity, actual_quantity, difference)
             VALUES ($1, $2, $3, 0, $3)`,
            [inventoryId, ing.id, ing.stock_quantity]
          );
        }
      }

      await client.query('COMMIT');
      res.status(201).json(inventory.rows[0]);
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Inventarizatsiya tarkibi (oziq-ovqat yoki idishlar)
const getInventoryItems = async (req, res) => {
  try {
    const { id } = req.params;

    const check = await pool.query(
      `SELECT COALESCE(type, 'ingredient') AS type FROM inventory_checks WHERE id = $1`,
      [id]
    );
    const invType = check.rows.length ? check.rows[0].type : 'ingredient';

    let result;
    if (invType === 'tableware') {
      // Idishlar — frontend kutgan maydon nomlariga moslab qaytaramiz
      result = await pool.query(
        `SELECT ii.*, t.name as ingredient_name, t.unit,
                'Idishlar'::text as category,
                t.price as price_per_unit, 0 as selling_price
         FROM inventory_items ii
         JOIN tableware t ON ii.tableware_id = t.id
         WHERE ii.inventory_id = $1
         ORDER BY t.name`,
        [id]
      );
    } else {
      result = await pool.query(
        `SELECT ii.*, i.name as ingredient_name, i.unit, i.category,
                i.price_per_unit, i.selling_price
         FROM inventory_items ii
         JOIN ingredients i ON ii.ingredient_id = i.id
         WHERE ii.inventory_id = $1
         ORDER BY i.category, i.name`,
        [id]
      );
    }
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Haqiqiy miqdorni yangilash
const updateInventoryItem = async (req, res) => {
  try {
    const { id } = req.params;
    const { actual_quantity } = req.body;

    const item = await pool.query(
      `SELECT * FROM inventory_items WHERE id = $1`,
      [id]
    );
    const expected = item.rows[0].expected_quantity;
    const difference = actual_quantity - expected;

    const result = await pool.query(
      `UPDATE inventory_items
       SET actual_quantity = $1, difference = $2
       WHERE id = $3 RETURNING *`,
      [actual_quantity, difference, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Inventarizatsiyani yakunlash
const closeInventory = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { id } = req.params;

    // Haqiqiy miqdorlarni manbaga (sklad yoki idishlar katalogi) yozish
    const items = await client.query(
      `SELECT * FROM inventory_items WHERE inventory_id = $1`,
      [id]
    );

    for (const item of items.rows) {
      if (item.tableware_id) {
        await client.query(
          `UPDATE tableware SET quantity = $1 WHERE id = $2`,
          [item.actual_quantity, item.tableware_id]
        );
      } else if (item.ingredient_id) {
        await client.query(
          `UPDATE ingredients SET stock_quantity = $1 WHERE id = $2`,
          [item.actual_quantity, item.ingredient_id]
        );
      }
    }

    await client.query(
      `UPDATE inventory_checks SET status = 'closed' WHERE id = $1`,
      [id]
    );

    await client.query('COMMIT');
    res.json({ message: 'Inventarizatsiya yakunlandi!' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

module.exports = {
  getInventories,
  createInventory,
  getInventoryItems,
  updateInventoryItem,
  closeInventory
};