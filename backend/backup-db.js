// ============================================================
// Kunlik zaxira (Faza 1):
//   1. pg_dump (custom format) -> D:\sultan\backups\sultan_db_YYYY-MM-DD.dump
//   2. 14 kundan eski zaxiralarni o'chirish
//   3. Firestore ko'zgusini yangilash (firestore-backup.js) — ofsayt nusxa
// Ishga tushirish: node backup-db.js   (yoki Windows Task Scheduler, har kuni 04:00)
// Tiklash: pg_restore -h localhost -U postgres -d sultan_db --clean <fayl>
// ============================================================
const fs = require('fs');
const path = require('path');
const { execFileSync, execSync } = require('child_process');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const BACKUP_DIR = process.env.BACKUP_DIR || 'D:\\sultan\\backups';
const KEEP_DAYS = parseInt(process.env.BACKUP_KEEP_DAYS || '14', 10);

function findPgDump() {
  if (process.env.PG_DUMP_PATH && fs.existsSync(process.env.PG_DUMP_PATH)) return process.env.PG_DUMP_PATH;
  try {
    const w = execSync('where pg_dump', { encoding: 'utf8' }).split(/\r?\n/)[0].trim();
    if (w && fs.existsSync(w)) return w;
  } catch (_) {}
  // Standart Windows o'rnatish joylari
  const base = 'C:\\Program Files\\PostgreSQL';
  if (fs.existsSync(base)) {
    const vers = fs.readdirSync(base).sort().reverse();
    for (const v of vers) {
      const p = path.join(base, v, 'bin', 'pg_dump.exe');
      if (fs.existsSync(p)) return p;
    }
  }
  throw new Error('pg_dump topilmadi — PG_DUMP_PATH ni .env ga yozing');
}

function main() {
  if (!fs.existsSync(BACKUP_DIR)) fs.mkdirSync(BACKUP_DIR, { recursive: true });

  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  const stamp = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  const outFile = path.join(BACKUP_DIR, `sultan_db_${stamp}.dump`);

  const pgDump = findPgDump();
  console.log(`[backup] pg_dump: ${pgDump}`);
  execFileSync(pgDump, [
    '-h', process.env.DB_HOST || 'localhost',
    '-p', process.env.DB_PORT || '5432',
    '-U', process.env.DB_USER || 'postgres',
    '-d', process.env.DB_NAME || 'sultan_db',
    '-Fc', '-f', outFile,
  ], { env: { ...process.env, PGPASSWORD: process.env.DB_PASSWORD || '' }, stdio: 'inherit' });
  const size = fs.statSync(outFile).size;
  if (size < 10 * 1024) throw new Error(`Zaxira shubhali kichik (${size} bayt) — tekshiring!`);
  console.log(`[backup] OK: ${outFile} (${(size / 1024 / 1024).toFixed(1)} MB)`);

  // Eski zaxiralarni tozalash
  const cutoff = Date.now() - KEEP_DAYS * 24 * 3600 * 1000;
  for (const f of fs.readdirSync(BACKUP_DIR)) {
    if (!f.startsWith('sultan_db_') || !f.endsWith('.dump')) continue;
    const full = path.join(BACKUP_DIR, f);
    if (fs.statSync(full).mtimeMs < cutoff) {
      fs.unlinkSync(full);
      console.log(`[backup] eski zaxira o'chirildi: ${f}`);
    }
  }

  // Ofsayt: Firestore ko'zgusini yangilash (internet bo'lmasa — jim o'tkazamiz,
  // lokal zaxira baribir bor)
  try {
    execFileSync(process.execPath, [path.join(__dirname, 'firestore-backup.js')], { stdio: 'inherit', timeout: 300000 });
  } catch (e) {
    console.log('[backup] Firestore ko\'zgusi yangilanmadi (internet/token?):', e.message);
  }
}

main();
