// ============================================================
// AUDIT-JURNAL SERVISI (F16). Har muhim amal: kim, qachon, qaysi
// qurilma/IPdan, nima o'zgardi (eski/yangi JSON), sabab.
// Jadval append-only (trigger UPDATE/DELETE ni taqiqlaydi).
// logAudit HECH QACHON xato otmaydi — audit yozilmasa ham asosiy
// amal buzilmasligi kerak (lekin console ga yoziladi).
// ============================================================
const pool = require('../config/db');

// db — tranzaksiya 'client' yoki pool (client berilsa asosiy amal bilan
// birga COMMIT/ROLLBACK bo'ladi — rollback bo'lsa audit ham yozilmaydi, to'g'ri).
async function logAudit(db, {
  req = null, action, entityType = null, entityId = null,
  oldValue = null, newValue = null, reason = null, userName = null, branch = null,
}) {
  try {
    const d = db || pool;
    const user = req && req.user ? req.user : {};
    const ip = req
      ? ((req.headers && (req.headers['x-forwarded-for'] || '').split(',')[0].trim()) || req.ip || null)
      : null;
    const device = req && req.headers ? (req.headers['user-agent'] || '').slice(0, 300) || null : null;

    // user_name berilmagan bo'lsa users dan olamiz (bitta arzon so'rov)
    let name = userName;
    if (!name && user.id) {
      try {
        const u = await d.query('SELECT full_name FROM users WHERE id = $1', [user.id]);
        name = u.rows.length ? u.rows[0].full_name : null;
      } catch (_) { /* jim */ }
    }

    await d.query(
      `INSERT INTO audit_log
         (user_id, user_name, user_role, ip, device, branch, action,
          entity_type, entity_id, old_value, new_value, reason)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [user.id || null, name, user.role || null, ip, device, branch, action,
       entityType, entityId,
       oldValue === null ? null : JSON.stringify(oldValue),
       newValue === null ? null : JSON.stringify(newValue),
       reason]
    );
  } catch (e) {
    console.error('[audit] yozilmadi:', e.message);
  }
}

module.exports = { logAudit };
