// Sultan — katta nagruska (load) testi. Chek bosish O'CHIQ holatda ishlatiladi.
// O'qish (og'ir hisobotlar) + yozish (zakaz yaratish) yuklamasi. Stock snapshot/restore bilan toza qoldiradi.
require('dotenv').config();
const http = require('http');
const pool = require('./src/config/db');

const HOST = '127.0.0.1', PORT = 3000;
const READ_TOTAL = parseInt(process.env.LT_READS || '6000', 10);
const READ_CONC = parseInt(process.env.LT_RCONC || '50', 10);
const WRITE_TOTAL = parseInt(process.env.LT_WRITES || '400', 10);
const WRITE_CONC = parseInt(process.env.LT_WCONC || '25', 10);

function req(method, path, token, body) {
  return new Promise((resolve) => {
    const data = body ? JSON.stringify(body) : null;
    const t0 = process.hrtime.bigint();
    const r = http.request({ host: HOST, port: PORT, path, method,
      headers: { Authorization: 'Bearer ' + token, ...(data ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } : {}) } },
      (res) => { let n = 0, buf = ''; res.on('data', c => { n += c.length; if (buf.length < 2000) buf += c; }); res.on('end', () => {
        resolve({ ms: Number(process.hrtime.bigint() - t0) / 1e6, code: res.statusCode, bytes: n, body: buf, path: path.split('?')[0], method }); }); });
    r.on('error', () => resolve({ ms: Number(process.hrtime.bigint() - t0) / 1e6, code: 0, err: true, path: path.split('?')[0], method }));
    if (data) r.write(data);
    r.end();
  });
}

async function pool_run(n, conc, makeTask, onProg) {
  let i = 0, done = 0; const out = [];
  async function worker() { while (i < n) { const idx = i++; out[idx] = await makeTask(idx); if (++done % Math.max(1, Math.floor(n / 12)) === 0) onProg(done, n, out); } }
  await Promise.all(Array.from({ length: conc }, worker));
  return out;
}

function stats(arr) {
  const ms = arr.map(r => r.ms).sort((a, b) => a - b);
  const ok = arr.filter(r => r.code >= 200 && r.code < 300).length;
  const errs = arr.length - ok;
  const pct = p => ms.length ? ms[Math.min(ms.length - 1, Math.floor(p / 100 * ms.length))] : 0;
  return { n: arr.length, ok, errs, p50: pct(50), p95: pct(95), p99: pct(99), max: ms[ms.length - 1] || 0, avg: ms.reduce((a, b) => a + b, 0) / (ms.length || 1) };
}
const f = n => n.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const ms = n => n.toFixed(1) + 'ms';

(async () => {
  console.log('=== SULTAN NAGRUSKA TEST ===');
  const login = await req('POST', '/api/auth/login', '', { phone: '123456', password: '123456' });
  const token = JSON.parse(login.body).token;
  if (!token) { console.log('Login XATO'); process.exit(1); }

  // Yozish uchun kerakli ma'lumotlar
  const tbls = await pool.query("SELECT id FROM tables WHERE is_active=true ORDER BY id LIMIT 50");
  const tableIds = tbls.rows.map(r => r.id);
  const w = await pool.query("SELECT u.id FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='waiter' AND u.is_active=true LIMIT 1");
  const waiterId = w.rows[0] ? w.rows[0].id : null;
  const mi = await pool.query("SELECT id, price FROM menu_items WHERE is_active=true AND price>0 ORDER BY id LIMIT 30");
  const items = mi.rows;
  const from = '2026-06-01', to = '2026-06-30';

  // ── PHASE A: O'QISH YUKLAMASI ──
  const READ_ENDPOINTS = [
    `/api/reports/dashboard?period=month`,
    `/api/reports/summary?period=month`,
    `/api/reports/payroll?from=${from}&to=${to}`,
    `/api/reports/cashbox?period=month`,
    `/api/expenses/outflows?period=month`,
    `/api/orders?status=paid`,
    `/api/orders`,
    `/api/menu/items`,
    `/api/orders/tables`,
  ];
  console.log(`\n[A] O'QISH: ${f(READ_TOTAL)} so'rov, parallel=${READ_CONC}, ${READ_ENDPOINTS.length} xil og'ir endpoint`);
  const tA = Date.now();
  const aRes = await pool_run(READ_TOTAL, READ_CONC,
    (i) => req('GET', READ_ENDPOINTS[i % READ_ENDPOINTS.length], token),
    (d, n) => process.stdout.write(`\r   ... ${f(d)}/${f(n)} (${Math.round(d / n * 100)}%)   `));
  const aSec = (Date.now() - tA) / 1000;
  console.log('');
  const aS = stats(aRes);
  console.log(`   tugadi: ${aSec.toFixed(1)}s | ${f(aS.n / aSec)} so'rov/sek | ok=${aS.ok} xato=${aS.errs}`);
  console.log(`   kechikish: o'rtacha=${ms(aS.avg)} p50=${ms(aS.p50)} p95=${ms(aS.p95)} p99=${ms(aS.p99)} max=${ms(aS.max)}`);
  // endpoint bo'yicha
  const byEp = {};
  for (const r of aRes) { (byEp[r.path] ||= []).push(r); }
  console.log('   endpoint bo\'yicha (p95):');
  for (const [ep, arr] of Object.entries(byEp)) { const s = stats(arr); console.log(`     ${ep.padEnd(28)} p95=${ms(s.p95).padStart(9)} avg=${ms(s.avg).padStart(8)} xato=${s.errs}`); }

  // ── PHASE B: YOZISH YUKLAMASI (zakaz yaratish) ──
  let bS = null, createdIds = [];
  if (waiterId && tableIds.length && items.length) {
    // stock snapshot
    const snap = await pool.query('SELECT id, stock_quantity FROM ingredients');
    console.log(`\n[B] YOZISH: ${f(WRITE_TOTAL)} zakaz yaratish, parallel=${WRITE_CONC} (stock himoyalangan)`);
    const tB = Date.now();
    const bRes = await pool_run(WRITE_TOTAL, WRITE_CONC, (i) => {
      const it = items[i % items.length];
      const it2 = items[(i + 7) % items.length];
      return req('POST', '/api/orders', token, {
        table_id: tableIds[i % tableIds.length], waiter_id: waiterId,
        items: [{ menu_item_id: it.id, quantity: 1, price: it.price, is_kitchen: true },
                { menu_item_id: it2.id, quantity: 2, price: it2.price, is_kitchen: false }],
        notes: 'loadtest',
      });
    }, (d, n) => process.stdout.write(`\r   ... ${f(d)}/${f(n)} (${Math.round(d / n * 100)}%)   `));
    const bSec = (Date.now() - tB) / 1000;
    console.log('');
    bS = stats(bRes);
    console.log(`   tugadi: ${bSec.toFixed(1)}s | ${f(bS.n / bSec)} zakaz/sek | ok=${bS.ok} xato=${bS.errs}`);
    console.log(`   kechikish: o'rtacha=${ms(bS.avg)} p50=${ms(bS.p50)} p95=${ms(bS.p95)} p99=${ms(bS.p99)} max=${ms(bS.max)}`);
    for (const r of bRes) { try { const j = JSON.parse(r.body || '{}'); if (j.id) createdIds.push(j.id); } catch (_) {} }

    // TOZALASH: test zakazlarini o'chir + stock'ni tikla + stollar bo'sh
    await pool.query('DELETE FROM order_items WHERE order_id = ANY($1)', [createdIds]);
    await pool.query('DELETE FROM orders WHERE id = ANY($1)', [createdIds]);
    await pool.query("UPDATE tables SET status='free'");
    // stock restore
    const client = await pool.connect();
    try { await client.query('BEGIN'); for (const r of snap.rows) await client.query('UPDATE ingredients SET stock_quantity=$1 WHERE id=$2', [r.stock_quantity, r.id]); await client.query('COMMIT'); }
    finally { client.release(); }
    console.log(`   tozalandi: ${f(createdIds.length)} test zakaz o'chirildi, stock tiklandi, stollar bo'sh ✅`);
  }

  // ── XULOSA ──
  const ords = (await pool.query('SELECT COUNT(*)::int n FROM orders')).rows[0].n;
  console.log('\n=== XULOSA ===');
  console.log(`O'qish: ${f(aS.n)} so'rov, ${aS.errs} xato, p95=${ms(aS.p95)}, ${f(aS.n / aSec)} req/s`);
  if (bS) console.log(`Yozish: ${f(bS.n)} zakaz, ${bS.errs} xato, p95=${ms(bS.p95)}`);
  console.log(`Bazada hozir zakazlar: ${ords} (toza bo'lishi kerak)`);
  console.log(`Server holati: ${aS.errs + (bS ? bS.errs : 0) === 0 ? 'BARQAROR ✅ (0 xato)' : (aS.errs + (bS ? bS.errs : 0)) + ' xato bor ⚠️'}`);
  process.exit(0);
})().catch(e => { console.log('TEST XATO:', e.message); process.exit(1); });
