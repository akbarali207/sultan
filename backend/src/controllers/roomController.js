const pool = require('../config/db');

// ─── XONALAR ────────────────────────────────────────────────────────────────

// Barcha xonalar
const getRooms = async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM rooms ORDER BY id`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi xona (markazga yaqin default joylashuv)
const createRoom = async (req, res) => {
  try {
    const { name, pos_x, pos_y } = req.body;
    const result = await pool.query(
      `INSERT INTO rooms (name, pos_x, pos_y)
       VALUES ($1, COALESCE($2, 0.1), COALESCE($3, 0.1)) RETURNING *`,
      [name, pos_x, pos_y]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Xonani yangilash (joyini surganda / nomini o'zgartirganda)
const updateRoom = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, pos_x, pos_y, width, height } = req.body;
    const result = await pool.query(
      `UPDATE rooms SET
         name   = COALESCE($1, name),
         pos_x  = COALESCE($2, pos_x),
         pos_y  = COALESCE($3, pos_y),
         width  = COALESCE($4, width),
         height = COALESCE($5, height)
       WHERE id = $6 RETURNING *`,
      [name, pos_x, pos_y, width, height, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Xona topilmadi' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Xonani o'chirish — zakaz tarixi bor stollar ARXIVLANADI (o'chmaydi), bo'shlari o'chadi, keyin xona.
// (Ilgari DELETE FROM tables order-history FK'ga urilib 500 berardi va butun o'chirish qaytardi.)
const deleteRoom = async (req, res) => {
  const { id } = req.params;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Xonada ochiq (to'lanmagan) zakazли stol bo'lsa — o'chirishни bloklaymiz.
    const openOrd = await client.query(
      `SELECT 1 FROM orders o JOIN tables t ON o.table_id = t.id
       WHERE t.room_id = $1 AND o.status <> 'paid' LIMIT 1`, [id]);
    if (openOrd.rows.length) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Xonada ochiq zakazли stol bor — avval yoping' });
    }
    // Zakaz tarixi bor stollar: soft-delete + xonadan uzamiz (tarix saqlanadi)
    await client.query(
      `UPDATE tables SET is_active = false, room_id = NULL
       WHERE room_id = $1 AND id IN (SELECT DISTINCT table_id FROM orders WHERE table_id IS NOT NULL)`, [id]);
    // Tarixsiz stollar: xavfsiz hard-delete
    await client.query(
      `DELETE FROM tables WHERE room_id = $1
       AND id NOT IN (SELECT DISTINCT table_id FROM orders WHERE table_id IS NOT NULL)`, [id]);
    await client.query(`DELETE FROM rooms WHERE id = $1`, [id]);
    await client.query('COMMIT');
    res.json({ message: "Xona o'chirildi" });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// ─── STOLLAR (floor-plan) ─────────────────────────────────────────────────────

// Barcha faol stollar (room_id, seats, pos_x, pos_y bilan)
const getTables = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM tables WHERE is_active = true ORDER BY COALESCE(number, id)`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi stol
const createTable = async (req, res) => {
  try {
    const { number, room_id, seats, pos_x, pos_y, table_size } = req.body;
    const name = req.body.name || `Stol ${number ?? ''}`.trim();
    const shape = req.body.shape === 'circle' ? 'circle' : 'rect';
    const result = await pool.query(
      `INSERT INTO tables (name, number, room_id, seats, pos_x, pos_y, table_size, status, shape)
       VALUES ($1, $2, $3, COALESCE($4, 4), COALESCE($5, 0.5), COALESCE($6, 0.5), COALESCE($7, 1.0), 'free', $8)
       RETURNING *`,
      [name, number || null, room_id || null, seats, pos_x, pos_y, table_size, shape]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Stolni yangilash (surganda / tahrirda) — status'ga TEGMAYDI (zakaz oqimi buzilmasin)
const updateTable = async (req, res) => {
  try {
    const { id } = req.params;
    const { number, seats, pos_x, pos_y, room_id, table_size, shape } = req.body;
    const result = await pool.query(
      `UPDATE tables SET
         number     = COALESCE($1, number),
         seats      = COALESCE($2, seats),
         pos_x      = COALESCE($3, pos_x),
         pos_y      = COALESCE($4, pos_y),
         room_id    = COALESCE($5, room_id),
         table_size = COALESCE($6, table_size),
         shape      = COALESCE($8, shape)
       WHERE id = $7 RETURNING *`,
      [number, seats, pos_x, pos_y, room_id, table_size, id, shape || null]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Stol topilmadi' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Stolni o'chirish — zakaz tarixi bo'lsa ARXIVLANADI (soft-delete), aks holda o'chadi.
// (Ilgari hard DELETE order-history FK'ga urilib 500 berardi — 9 kunlik zalda ko'p stol o'chmasdi.)
const deleteTable = async (req, res) => {
  const { id } = req.params;
  try {
    // Ochiq (to'lanmagan) zakaz bor stolni o'chirib bo'lmaydi — aks holda hisob yo'qoladi.
    const openOrd = await pool.query(`SELECT 1 FROM orders WHERE table_id = $1 AND status <> 'paid' LIMIT 1`, [id]);
    if (openOrd.rows.length) {
      return res.status(400).json({ message: 'Stolda ochiq zakaz bor — avval yoping yoki to\'lang' });
    }
    const used = await pool.query(`SELECT 1 FROM orders WHERE table_id = $1 LIMIT 1`, [id]);
    if (used.rows.length) {
      await pool.query(`UPDATE tables SET is_active = false WHERE id = $1`, [id]);
      return res.json({ message: "Stol arxivlandi (zakaz tarixi bor)" });
    }
    await pool.query(`DELETE FROM tables WHERE id = $1`, [id]);
    res.json({ message: "Stol o'chirildi" });
  } catch (err) {
    if (err.code === '23503') { // FK to'sig'i — silliq arxivlash
      try { await pool.query(`UPDATE tables SET is_active = false WHERE id = $1`, [id]); } catch (_) {}
      return res.json({ message: "Stol arxivlandi (bog'liq yozuvlar bor)" });
    }
    res.status(500).json({ message: err.message });
  }
};

module.exports = {
  getRooms, createRoom, updateRoom, deleteRoom,
  getTables, createTable, updateTable, deleteTable,
};
