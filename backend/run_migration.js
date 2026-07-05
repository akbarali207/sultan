// Bir martalik migration ishga tushirgich: node run_migration.js <fayl.sql>
const fs = require('fs');
const path = require('path');
const pool = require('./src/config/db');

(async () => {
  const file = process.argv[2] || 'src/config/migration_warehouses.sql';
  const sql = fs.readFileSync(path.join(__dirname, file), 'utf8');
  try {
    await pool.query(sql);
    console.log(`Migration bajarildi: ${file}`);

    const wh = await pool.query('SELECT id, name FROM warehouses ORDER BY id');
    console.log('Skladlar:', wh.rows);

    const counts = await pool.query(
      `SELECT warehouse_id, COUNT(*)::int AS cnt FROM ingredients GROUP BY warehouse_id ORDER BY warehouse_id`
    );
    console.log('Ingredient taqsimoti (warehouse_id => soni):', counts.rows);
  } catch (err) {
    console.error('Migration XATO:', err.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
