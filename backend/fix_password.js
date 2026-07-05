const bcrypt = require('bcryptjs');
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'sultan_db',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'CHANGE_ME'
});

async function fixPassword() {
  const hash = await bcrypt.hash('password', 10);
  console.log('Yangi hash:', hash);
  await pool.query('UPDATE users SET password = $1 WHERE phone = $2', [hash, '+998901234567']);
  console.log('Parol yangilandi!');
  pool.end();
}

fixPassword();