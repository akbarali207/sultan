const pool = require('../config/db');

// Date'ni mahalliy "YYYY-MM-DD HH:MM:SS" ko'rinishida formatlash (server vaqt zonasida).
// Server +06:00 (qurilma bilan bir xil) bo'lgani uchun qurilma eventi vaqti aynan saqlanadi.
function fmtLocal(date) {
  const p = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())} ` +
         `${p(date.getHours())}:${p(date.getMinutes())}:${p(date.getSeconds())}`;
}

// face_id bo'yicha xodimni topib, davomatni belgilaydi (kirish/chiqish toggle).
// Ham qo'lda face-checkin endpointi, ham Hikvision integratsiyasi shu funksiyani ishlatadi.
// when — ixtiyoriy Date (qurilma eventi vaqti); berilmasa NOW() ishlatiladi.
//
// Himoya (Faza 0):
//  1. Doimiy dedup: attendance_events jadvalida user_id+vaqt kaliti — bir event
//     ikki kanaldan (poller + push) yoki restart'dan keyin kelsa ham BIR marta yoziladi.
//     (Eski in-memory Set restart'da unutilardi: takror event kirishni darhol
//     chiqishga aylantirib yuborardi.)
//  2. Cooldown (HIK_COOLDOWN_SEC, default 180s): oxirgi harakatdan keyin shu oraliqda
//     kelgan BOSHQA vaqtli eventlar ham e'tiborsiz — qurilma bir tanishda bir necha
//     soniya oralig'ida bir nechta event yuborishi mumkin.
//  3. Tranzaksiya + FOR UPDATE: toggle (kirish/chiqish) poygasiz ishlaydi.
async function recordFaceAttendance(faceId, when = null) {
  if (faceId === undefined || faceId === null || `${faceId}`.trim() === '') {
    return { ok: false, status: 400, message: 'face_id bo\'sh' };
  }
  const fid = `${faceId}`.trim();

  const userRes = await pool.query(
    `SELECT u.*, r.name as role_name
     FROM users u JOIN roles r ON u.role_id = r.id
     WHERE u.face_id = $1 AND u.is_active = true`,
    [fid]
  );
  if (userRes.rows.length === 0) {
    return { ok: false, status: 404, message: `Xodim topilmadi (face_id=${fid})` };
  }
  const user = userRes.rows[0];

  // Event vaqti (Hikvision) yoki hozirgi vaqt — mahalliy (+06) wall-clock saqlanadi
  const ts = when ? new Date(when) : new Date();
  const tsLocal = fmtLocal(ts);
  const dateStr = tsLocal.slice(0, 10);
  const cooldownSec = parseInt(process.env.HIK_COOLDOWN_SEC || '180', 10);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Doimiy dedup: shu xodim + shu soniya eventi allaqachon ishlanganmi?
    const dedup = await client.query(
      `INSERT INTO attendance_events (event_key) VALUES ($1)
       ON CONFLICT (event_key) DO NOTHING RETURNING event_key`,
      [`${user.id}_${tsLocal}`]
    );
    if (dedup.rows.length === 0) {
      await client.query('ROLLBACK');
      return { ok: true, status: 200, type: 'duplicate', user, message: `${user.full_name}: takror event (e'tiborsiz)` };
    }

    // 2. Cooldown: oxirgi kirish/chiqishdan cooldown ichida bo'lsa — o'tkazib yuboramiz.
    //    Kalitni saqlab qolish uchun COMMIT qilamiz (takror kelsa dedup ushlaydi).
    const cool = await client.query(
      `SELECT 1 FROM attendance
       WHERE user_id = $1
         AND GREATEST(check_in, COALESCE(check_out, check_in)) > $2::timestamp - make_interval(secs => $3)
         AND GREATEST(check_in, COALESCE(check_out, check_in)) <= $2::timestamp
       LIMIT 1`,
      [user.id, tsLocal, cooldownSec]
    );
    if (cool.rows.length > 0) {
      await client.query('COMMIT');
      return { ok: true, status: 200, type: 'cooldown', user, message: `${user.full_name}: yaqinda belgilangan (cooldown)` };
    }

    // 3. Toggle: ochiq (check_out NULL) yozuv bormi? FOR UPDATE — poygasiz.
    //    Sana cheklovi YO'Q: tunda o'tuvchi smena (masalan 23:30 kirib 01:00 chiqsa)
    //    ochiq check_in oldingi sanada qoladi — sana bo'yicha filtrlansa topilmay,
    //    chiqish o'rniga yangi kirish yozilib smena mangu ochiq qolardi.
    //    Buning o'rniga oxirgi 16 soat oynasidagi eng so'nggi ochiq sessiyani topamiz.
    //    AUDIT-FIX #3: oyna 24->16 soat. Xodim CHIQISHNI unutса (masalan 1-kun kelib chiqmаsа),
    //    2-kun kelgani 23 soatlik "chiqish" bo'lib hisoblanib, soatlik ish haqi haddan tashqari
    //    oshib ketardi. 16 soat — real smena (tunги smena ham) sig'adi, lekin unutilgan sessiya
    //    (>16s) YOPILMAYDI — yangi KIRISH yoziladi (eski sessiya ochiq qoladi, 0 soat).
    const open = await client.query(
      `SELECT * FROM attendance
       WHERE user_id = $1 AND check_out IS NULL
         AND check_in > $2::timestamp - make_interval(hours => 16)
         AND check_in <= $2::timestamp
       ORDER BY check_in DESC LIMIT 1 FOR UPDATE`,
      [user.id, tsLocal]
    );

    if (open.rows.length > 0) {
      await client.query(`UPDATE attendance SET check_out = $1 WHERE id = $2`, [tsLocal, open.rows[0].id]);
      await client.query('COMMIT');
      return { ok: true, status: 200, type: 'check_out', user, message: `${user.full_name} chiqdi!` };
    } else {
      await client.query(`INSERT INTO attendance (user_id, check_in) VALUES ($1, $2)`, [user.id, tsLocal]);
      await client.query('COMMIT');
      return { ok: true, status: 200, type: 'check_in', user, message: `${user.full_name} kirdi!` };
    }
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { recordFaceAttendance };
