const pool = require('../config/db');

// Idempotentlik: mijoz "Idempotency-Key" sarlavhasi (UUID, tugma bosilgan paytda
// yaratiladi) bilan kelsa, so'rov faqat BIR marta bajariladi. Takror kelsa —
// birinchi javob qaytariladi. Sarlavha bo'lmasa (eski mijozlar) — oddiy davom etadi.
//
// Holatlar:
//  - kalit yangi          -> so'rov bajariladi, javob saqlanadi
//  - kalit bor, javob bor -> saqlangan javob qaytadi (dublikat oldini oladi)
//  - kalit bor, javob yo'q (hali ishlanmoqda yoki jarayon o'lib qolgan):
//      60 soniyadan yangi bo'lsa -> 409 "kuting"
//      60 soniyadan eski bo'lsa  -> o'lik deb hisoblanadi, qayta bajariladi
//  - 5xx javoblar SAQLANMAYDI (vaqtinchalik xato retry'da qayta urinishi uchun)
function idempotency(req, res, next) {
  const key = (req.headers['idempotency-key'] || '').toString().trim();
  if (!key || key.length > 64 || (req.method !== 'POST' && req.method !== 'PUT' && req.method !== 'DELETE')) {
    return next();
  }

  (async () => {
    // Eskirgan kalitlarni vaqti-vaqti bilan tozalash (48 soatdan keyin kerak emas)
    if (Math.random() < 0.02) {
      pool.query(`DELETE FROM idempotency_keys WHERE created_at < NOW() - INTERVAL '48 hours'`).catch(() => {});
    }

    let ins = await pool.query(
      `INSERT INTO idempotency_keys (key, user_id, method, path)
       VALUES ($1, $2, $3, $4) ON CONFLICT (key) DO NOTHING RETURNING key`,
      [key, null, req.method, req.originalUrl.slice(0, 200)]
    );

    if (ins.rows.length === 0) {
      // Kalit allaqachon bor
      const ex = await pool.query(
        `SELECT status_code, response, created_at < NOW() - INTERVAL '60 seconds' AS stale
         FROM idempotency_keys WHERE key = $1`, [key]
      );
      const row = ex.rows[0];
      if (row && row.status_code !== null) {
        // Tayyor javob — takror so'rovga o'shani qaytaramiz
        res.set('X-Idempotent-Replay', 'true');
        return res.status(row.status_code).json(row.response);
      }
      if (row && row.stale) {
        // Jarayon o'lib qolgan — kalitni qayta egallaymiz
        await pool.query(`DELETE FROM idempotency_keys WHERE key = $1 AND status_code IS NULL`, [key]);
        ins = await pool.query(
          `INSERT INTO idempotency_keys (key, user_id, method, path)
           VALUES ($1, $2, $3, $4) ON CONFLICT (key) DO NOTHING RETURNING key`,
          [key, null, req.method, req.originalUrl.slice(0, 200)]
        );
        if (ins.rows.length === 0) {
          return res.status(409).json({ message: "So'rov qayta ishlanmoqda — biroz kuting" });
        }
      } else {
        return res.status(409).json({ message: "So'rov qayta ishlanmoqda — biroz kuting" });
      }
    }

    // Birinchi bajarilish: javobni ushlab qolib saqlaymiz
    const origJson = res.json.bind(res);
    res.json = (body) => {
      const code = res.statusCode || 200;
      if (code >= 500) {
        // Vaqtinchalik xato — kalitni bo'shatamiz, retry qayta urinsin
        pool.query(`DELETE FROM idempotency_keys WHERE key = $1`, [key]).catch(() => {});
      } else {
        pool.query(
          `UPDATE idempotency_keys SET status_code = $1, response = $2 WHERE key = $3`,
          [code, JSON.stringify(body === undefined ? null : body), key]
        ).catch(() => {});
      }
      return origJson(body);
    };
    next();
  })().catch((e) => {
    // Idempotentlik bazasi ishlamasa — so'rovni to'xtatmaymiz (himoyasiz, lekin ishlaydi)
    console.error('[idempotency] xato:', e.message);
    next();
  });
}

module.exports = idempotency;
