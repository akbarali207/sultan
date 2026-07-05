// Firestore backup: PostgreSQL (sultan_db) -> Firebase project sultan-1e7c0.
// PostgreSQL — yagona haqiqat manbai (source of truth); Firestore — faqat oflayn nusxa/ko'zgu.
// Ishga tushirish: node firestore-backup.js
// Auth: firebase CLI login sessiyasidan foydalanadi (firebase login qilingan bo'lishi shart).
const fs = require('fs');
const os = require('os');
const path = require('path');
const pool = require('./src/config/db');

const PROJECT = 'sultan-1e7c0';
const DOCS_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
// firebase-tools ochiq OAuth klienti (CLI ichida ochiq kodda keladi, sir emas)
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

async function getAccessToken() {
  const cfg = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  const rt = JSON.parse(fs.readFileSync(cfg, 'utf8')).tokens.refresh_token;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: CLIENT_ID, client_secret: CLIENT_SECRET, refresh_token: rt, grant_type: 'refresh_token' }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error('Firebase auth xatosi — avval `firebase login` qiling: ' + JSON.stringify(j).slice(0, 150));
  return j.access_token;
}

// PG qiymatini Firestore REST formatiga o'girish
function fsValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'bigint') return { integerValue: String(v) };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(fsValue) } };
  if (Buffer.isBuffer(v)) return { bytesValue: v.toString('base64') };
  if (typeof v === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fsValue(x)])) } };
  return { stringValue: String(v) }; // NUMERIC/DECIMAL pg'dan string bo'lib keladi — aniqlikni saqlaymiz
}

function rowToDoc(row) {
  const fields = {};
  for (const [k, v] of Object.entries(row)) {
    if (/password|parol/i.test(k)) continue; // parol xeshlari bulutga chiqmaydi
    fields[k] = fsValue(v);
  }
  return fields;
}

async function batchWrite(token, writes) {
  const res = await fetch(`${DOCS_BASE}:batchWrite`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes }),
  });
  const j = await res.json();
  if (res.status !== 200) throw new Error('batchWrite HTTP ' + res.status + ': ' + JSON.stringify(j).slice(0, 300));
  const bad = (j.status || []).filter(s => s.code && s.code !== 0);
  if (bad.length) throw new Error('batchWrite yozuv xatolari: ' + JSON.stringify(bad.slice(0, 3)));
  return writes.length;
}

async function main() {
  const token = await getAccessToken();
  const t = await pool.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename");
  const summary = {};
  let grand = 0;

  // Servis jadvallari ko'zguga kerak emas (operatsion shovqin)
  const SKIP = new Set(['idempotency_keys', 'attendance_events']);
  for (const { tablename } of t.rows) {
    if (SKIP.has(tablename)) continue;
    const { rows } = await pool.query(`SELECT * FROM "${tablename}"`);
    summary[tablename] = rows.length;
    if (!rows.length) continue;
    // doc ID: id ustuni bo'lsa — o'sha, bo'lmasa tartib raqami
    const writes = rows.map((row, i) => ({
      update: {
        name: `projects/${PROJECT}/databases/(default)/documents/${tablename}/${row.id !== undefined && row.id !== null ? row.id : 'row_' + i}`,
        fields: rowToDoc(row),
      },
    }));
    for (let i = 0; i < writes.length; i += 400) {
      grand += await batchWrite(token, writes.slice(i, i + 400));
      process.stdout.write(`\r${tablename}: ${Math.min(i + 400, writes.length)}/${writes.length}      `);
    }
    console.log(`\r${tablename}: ${rows.length} ta hujjat yozildi          `);
  }

  // _meta: eksport vaqti va hisob
  await batchWrite(token, [{
    update: {
      name: `projects/${PROJECT}/databases/(default)/documents/_backup_meta/latest`,
      fields: rowToDoc({ exported_at: new Date(), source: 'sultan_db (PostgreSQL, lokal)', note: 'Firestore = nusxa. Haqiqat manbai — PostgreSQL.', total_rows: grand, tables: JSON.stringify(summary) }),
    },
  }]);

  console.log(`\nJAMI: ${grand} ta hujjat Firestore'ga yozildi (${PROJECT}).`);
  process.exit(0);
}

main().catch(e => { console.error('XATO:', e.message); process.exit(1); });
