// ============================================================
// Migratsiya runner + tracking (schema_migrations).
// Har backend start'da avtomatik ishlaydi: qo'llanmagan migratsiyalarni
// topib, TARTIB bilan (ko'p-o'tishli — bog'liqlikni o'zi hal qiladi) qo'llaydi.
// Har biri ALOHIDA tranzaksiyada + schema_migrations ga yoziladi (bir marta).
// Toza bazada: schema.sql + barcha migration_*.sql qo'llanadi.
// Mavjud bazada: baseline seed qilingan (hammasi "qo'llangan") — faqat YANGILAR yuradi.
// ============================================================
const fs = require('fs');
const path = require('path');

async function runMigrations(pool) {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS schema_migrations (
       filename TEXT PRIMARY KEY,
       applied_at TIMESTAMP DEFAULT NOW()
     )`
  );
  const dir = __dirname; // src/config
  const applied = new Set(
    (await pool.query('SELECT filename FROM schema_migrations')).rows.map((r) => r.filename)
  );
  const migFiles = fs
    .readdirSync(dir)
    .filter((f) => /^migration_.*\.sql$/.test(f))
    .sort();
  const ordered = ['schema.sql', ...migFiles].filter((f) => fs.existsSync(path.join(dir, f)));
  let remaining = ordered.filter((f) => !applied.has(f));
  if (!remaining.length) {
    console.log('[migrate] barcha migratsiyalar qo\'llangan');
    return [];
  }
  console.log(`[migrate] ${remaining.length} ta qo'llanmagan migratsiya topildi`);

  // Ko'p-o'tishli: alifbo tartibi bog'liqlikka mos kelmasa (masalan multistation
  // print_stations dan oldin), muvaffaqiyatsizni keyingi o'tishда qayta urinadi.
  let pass = 0;
  while (remaining.length) {
    pass++;
    const failed = [];
    let progress = false;
    for (const f of remaining) {
      const c = await pool.connect();
      try {
        await c.query('BEGIN');
        await c.query(fs.readFileSync(path.join(dir, f), 'utf8'));
        await c.query('INSERT INTO schema_migrations(filename) VALUES($1) ON CONFLICT DO NOTHING', [f]);
        await c.query('COMMIT');
        console.log(`[migrate] ✓ ${f}`);
        progress = true;
      } catch (e) {
        await c.query('ROLLBACK').catch(() => {});
        failed.push({ f, e: e.message });
      } finally {
        c.release();
      }
    }
    remaining = failed.map((x) => x.f);
    if (!progress) {
      console.error('[migrate] QOLGAN migratsiyalar qo\'llanmadi (bog\'liqlik/xato):');
      for (const x of failed) console.error(`   ✗ ${x.f}: ${x.e}`);
      break; // backend baribir ishga tushsin (mavjud sxema ishlayapti)
    }
  }
  return remaining; // qo'llanmagan (failed) migratsiyalar — index.js baland ogohlantiradi
}

module.exports = { runMigrations };
