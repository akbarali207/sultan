const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

pool.connect((err) => {
  if (err) {
    console.error('Database ulanish xatosi:', err.message);
  } else {
    console.log('PostgreSQL ga muvaffaqiyatli ulandi!');
  }
});

// MUHIM: idle-mijoz xatosi (DB restart, Tailscale/tunnel uzilishi, idle-timeout)
// butun backendni YIQITMASIN. node-pg Pool 'error' hodisasini chiqaradi; listener
// bo'lmasa Node uni unhandled deb jarayonni o'ldiradi (barcha kassalar bir vaqtda tushardi).
pool.on('error', (err) => {
  console.error('[pg] idle mijoz xatosi (backend tirik qoladi):', err.message);
});

module.exports = pool;