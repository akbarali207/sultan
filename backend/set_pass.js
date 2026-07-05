// set_pass.js — phone='123456' bo'lgan user parolini '123456' ga o'rnatadi
// va is_active=true qiladi, so'ng bcrypt.compare bilan tekshiradi.
const bcrypt = require('bcryptjs');
const pool = require('./src/config/db');

const PHONE = '123456';
const PLAIN = '123456';

(async () => {
  try {
    // 1. Yangi hash yasaymiz
    const hash = await bcrypt.hash(PLAIN, 10);

    // 2. Parolni o'rnatamiz + is_active = true
    const updated = await pool.query(
      `UPDATE users
          SET password = $1, is_active = true
        WHERE phone = $2
      RETURNING id, full_name, phone, password, is_active`,
      [hash, PHONE]
    );

    if (updated.rowCount === 0) {
      console.log(`\n❌ phone = '${PHONE}' bo'lgan user topilmadi. Hech narsa o'zgartirilmadi.\n`);
      return;
    }

    const user = updated.rows[0];

    // 3. Bazadan yangilangan hash ni o'qib, '123456' ga mosligini tekshiramiz
    const check = await pool.query(
      `SELECT password FROM users WHERE phone = $1`,
      [PHONE]
    );
    const storedHash = check.rows[0].password;
    const ok = await bcrypt.compare(PLAIN, storedHash);

    // 4. Chiroyli natija
    console.log('\n══════════════════════════════════════');
    console.log('   PAROL YANGILANDI');
    console.log('══════════════════════════════════════');
    console.log(`  Ism      : ${user.full_name}`);
    console.log(`  Telefon  : ${user.phone}`);
    console.log(`  Parol    : ${PLAIN}`);
    console.log(`  Faol     : ${user.is_active ? 'ha' : "yo'q"}`);
    console.log(`  Tekshiruv: ${ok ? 'HA' : "YO'Q"}`);
    console.log('══════════════════════════════════════\n');
  } catch (err) {
    console.error('Xato:', err.message);
  } finally {
    await pool.end();
  }
})();
