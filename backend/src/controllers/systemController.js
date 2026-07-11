const pool = require('../config/db');

// Tizim to'xtatilganmi? (createOrder / to'lov shu bilan bloklanadi)
async function isFrozen(client) {
  const q = client || pool;
  try {
    const r = await q.query('SELECT frozen FROM system_state WHERE id = 1');
    return r.rows.length ? r.rows[0].frozen === true : false;
  } catch (_) {
    return false; // jadval hali yo'q bo'lsa — bloklamaymiz
  }
}

// Joriy holat (hamma ko'ra oladi — UI banner uchun)
const getState = async (req, res) => {
  try {
    const r = await pool.query('SELECT frozen, frozen_by_name, frozen_at, note FROM system_state WHERE id = 1');
    res.json(r.rows[0] || { frozen: false });
  } catch (err) {
    res.json({ frozen: false });
  }
};

// STOP / ochish — admin, director yoki super-admin (guest).
// Egasi so'radi: "admin ham bitta tugma bilan butun ilovani to'xtata olsin".
const setFreeze = async (req, res) => {
  if (!req.user || !['admin', 'director', 'guest'].includes(req.user.role)) {
    return res.status(403).json({ message: 'Faqat admin yoki super-admin' });
  }
  try {
    const frozen = req.body.frozen === true || req.body.frozen === 'true';
    const ures = req.user.id
      ? await pool.query('SELECT full_name FROM users WHERE id = $1', [req.user.id])
      : { rows: [] };
    const uname = ures.rows.length ? ures.rows[0].full_name : null;
    const note = (req.body.note || '').toString().trim().slice(0, 200) || null;
    await pool.query(
      `UPDATE system_state SET frozen = $1, frozen_by = $2, frozen_by_name = $3, frozen_at = NOW(), note = $4 WHERE id = 1`,
      [frozen, req.user.id, uname, note]
    );
    res.json({ ok: true, frozen });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { getState, setFreeze, isFrozen };
