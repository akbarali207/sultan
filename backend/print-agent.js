// ============================================================
//  SULTAN — Print Agent (lokal)
//  Yangi zakazlarni backenddan oladi, bo'limlarga bo'ladi va
//  har bo'lim chekini tegishli printerga (ESC/POS, IP:9100) yuboradi.
//  Printer IP yo'q bo'lsa — chek "tickets/" papkasiga fayl bo'lib yoziladi (test uchun).
//  Ishga tushirish:  node print-agent.js
// ============================================================
const net = require('net');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const API_URL = process.env.PRINT_API_URL || 'http://127.0.0.1:3000';
const TOKEN = process.env.PRINT_AGENT_TOKEN || '';
const POLL_SECONDS = parseInt(process.env.PRINT_POLL_SECONDS || '3', 10);
const TICKETS_DIR = path.join(__dirname, 'tickets');

if (!fs.existsSync(TICKETS_DIR)) fs.mkdirSync(TICKETS_DIR, { recursive: true });

// ---- ESC/POS yordamchilari ----
const ESC = '\x1B', GS = '\x1D', FS = '\x1C';
const CMD = {
  init: ESC + '@',
  kanjiOff: FS + '.',            // Xitoy (GBK) rejimini o'chirish — kirill to'g'ri chiqishi uchun
  cp866: ESC + 't' + '\x11',     // PC866 (kirill) kod sahifasi (17)
  alignC: ESC + 'a' + '\x01',
  alignL: ESC + 'a' + '\x00',
  boldOn: ESC + 'E' + '\x01',
  boldOff: ESC + 'E' + '\x00',
  big: GS + '!' + '\x11',        // 2x kenglik+balandlik
  normal: GS + '!' + '\x00',
  cut: GS + 'V' + '\x42' + '\x00', // qisman kesish (feed bilan)
};

// Unicode -> CP866 (kirill) bitta bayt
function cp866Byte(c) {
  if (c < 0x80) return c;
  if (c >= 0x0410 && c <= 0x042F) return c - 0x0410 + 0x80; // А-Я
  if (c >= 0x0430 && c <= 0x043F) return c - 0x0430 + 0xA0; // а-п
  if (c >= 0x0440 && c <= 0x044F) return c - 0x0440 + 0xE0; // р-я
  if (c === 0x0401) return 0xF0; // Ё
  if (c === 0x0451) return 0xF1; // ё
  if (c === 0x2116) return 0xFC; // № (CP866 da bor)
  if (c === 0x00B0) return 0xF8; // °
  if (c === 0x00B7) return 0xFA; // ·
  // Tipografik belgilarni ASCII ga keltirib '?' bo'lib qolishidan saqlaymiz
  if (c === 0x2014 || c === 0x2013) return 0x2D; // — – -> -
  if (c === 0x00AB || c === 0x00BB || c === 0x201C || c === 0x201D) return 0x22; // « » " " -> "
  if (c === 0x2018 || c === 0x2019) return 0x27; // ' ' -> '
  return 0x3F; // '?'
}
function encode(str) {
  const bytes = [];
  for (const ch of str) bytes.push(cp866Byte(ch.codePointAt(0)));
  return Buffer.from(bytes);
}

// Chek matnini (ESC/POS) tayyorlash
function buildTicket(order, station) {
  let s = '';
  s += CMD.init + CMD.kanjiOff + CMD.cp866;
  s += CMD.alignC + CMD.boldOn + CMD.big;
  s += (station.station_name || 'Oshxona') + '\n';
  s += CMD.normal + CMD.boldOff;
  s += '--------------------------------\n';
  s += CMD.alignL;
  s += CMD.boldOn + 'ЗАКАЗ №' + (order.order_id ?? order.id ?? '-') + CMD.boldOff + '\n';
  s += CMD.boldOn + 'СТОЛ: ' + (order.table_number ?? '-') + CMD.boldOff + '\n';
  s += 'Официант: ' + (order.waiter_name || '-') + '\n';
  const t = new Date(order.created_at);
  const p = (n) => String(n).padStart(2, '0');
  s += 'Время: ' + `${p(t.getHours())}:${p(t.getMinutes())}` + '\n';
  s += '--------------------------------\n';
  for (const it of station.items) {
    s += CMD.big + CMD.boldOn + `${it.quantity} x ${it.name}` + CMD.normal + CMD.boldOff + '\n';
    if (it.notes) s += '   (' + it.notes + ')\n';
  }
  if (order.notes) {
    s += '--------------------------------\n';
    s += 'Примечание: ' + order.notes + '\n';
  }
  s += '\n\n' + CMD.cut;
  return s;
}

function money(v) {
  const s = Math.round(Number(v) || 0).toString();
  let out = '';
  for (let i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 === 0) out += ' ';
    out += s[i];
  }
  return out;
}

// Mijoz cheki (bill) — narx + jami bilan (ESC/POS)
function buildBill(order) {
  let s = '';
  s += CMD.init + CMD.kanjiOff + CMD.cp866;
  s += CMD.alignC + CMD.boldOn + CMD.big;
  s += 'SULTAN\n';
  s += CMD.normal;
  s += 'СЧЁТ\n';
  s += CMD.boldOff;
  s += '--------------------------------\n';
  s += CMD.alignL;
  s += CMD.boldOn + 'ЗАКАЗ №' + (order.order_id ?? order.id ?? '-') + CMD.boldOff + '\n';
  s += 'СТОЛ: ' + (order.table_number ?? '-') + '\n';
  s += 'Официант: ' + (order.waiter_name || '-') + '\n';
  const t = new Date(order.created_at);
  const p = (n) => String(n).padStart(2, '0');
  s += 'Время: ' + `${p(t.getDate())}.${p(t.getMonth() + 1)} ${p(t.getHours())}:${p(t.getMinutes())}` + '\n';
  s += '--------------------------------\n';
  for (const it of order.items) {
    const sum = (Number(it.price) || 0) * (Number(it.quantity) || 0);
    s += it.name + '\n';
    s += '  ' + it.quantity + ' x ' + money(it.price) + ' = ' + money(sum) + '\n';
  }
  s += '--------------------------------\n';
  const disc = Number(order.discount_percent) || 0;
  const total = Number(order.total_amount) || 0;
  const finalAmt = (order.final_amount != null && Number(order.final_amount) > 0) ? Number(order.final_amount) : total;
  if (disc > 0) {
    const discStr = (disc === Math.floor(disc)) ? disc.toFixed(0) : disc.toFixed(1);
    s += 'Сумма: ' + money(total) + ' сом\n';
    s += 'Скидка ' + discStr + '%: -' + money(total - finalAmt) + ' сом\n';
    s += CMD.boldOn + CMD.big;
    s += 'К ОПЛАТЕ: ' + money(finalAmt) + ' сом\n';
    s += CMD.normal + CMD.boldOff;
  } else {
    s += CMD.boldOn + CMD.big;
    s += 'ИТОГО: ' + money(total) + ' сом\n';
    s += CMD.normal + CMD.boldOff;
  }
  s += CMD.alignC + '\nСпасибо!\n';
  s += '\n\n' + CMD.cut;
  return s;
}

// ОТМЕНА (atmen) cheki — bo'lim printeriga, oshpaz TAYYORLAMASLIGINI bilishi uchun
function buildCancelTicket(tk) {
  let s = '';
  s += CMD.init + CMD.kanjiOff + CMD.cp866;
  s += CMD.alignC + CMD.boldOn + CMD.big;
  s += '!!! ОТМЕНА !!!\n';
  s += CMD.normal + (tk.station_name || '') + '\n' + CMD.boldOff;
  s += '--------------------------------\n';
  s += CMD.alignL;
  s += CMD.boldOn + 'ЗАКАЗ №' + (tk.order_id ?? '-') + CMD.boldOff + '\n';
  s += CMD.boldOn + 'СТОЛ: ' + (tk.table_number ?? '-') + CMD.boldOff + '\n';
  s += 'Официант: ' + (tk.waiter_name || '-') + '\n';
  const t = new Date(tk.created_at);
  const p = (n) => String(n).padStart(2, '0');
  s += 'Время: ' + `${p(t.getHours())}:${p(t.getMinutes())}` + '\n';
  s += '--------------------------------\n';
  s += CMD.boldOn + 'НЕ ГОТОВИТЬ:\n' + CMD.boldOff;
  for (const it of tk.items || []) {
    s += CMD.big + CMD.boldOn + `${it.quantity} x ${it.name}` + CMD.normal + CMD.boldOff + '\n';
  }
  s += '\n\n' + CMD.cut;
  return s;
}

async function processCancel(tk) {
  const text = buildCancelTicket(tk);
  if (tk.printer_ip) {
    await sendToPrinter(tk.printer_ip, tk.printer_port || 9100, text);
  } else if (tk.printer_name) {
    await sendToUsb(tk.printer_name, text);
  } else {
    fs.writeFileSync(path.join(TICKETS_DIR, `cancel${tk.id}_order${tk.order_id}.txt`), text);
  }
  console.log(`[cancel] ОТМЕНА zakaz #${tk.order_id} -> ${tk.station_name}`);
  const r = await fetch(`${API_URL}/api/print/cancels/${tk.id}/done`, {
    method: 'POST', headers: { 'x-print-token': TOKEN },
  });
  if (!r.ok) throw new Error('cancel done xato: ' + r.status);
}

async function pollCancels() {
  const r = await fetch(`${API_URL}/api/print/cancels/pending`, { headers: { 'x-print-token': TOKEN } });
  if (!r.ok) { console.log('[cancel] pending xato:', r.status); return; }
  const tickets = await r.json();
  for (const tk of tickets) {
    try {
      await processCancel(tk);
    } catch (e) {
      console.log(`[cancel] #${tk.id} xato:`, e.message, '— keyingi siklda qayta urinamiz');
    }
  }
}

// Plain-text (fayl uchun, o'qishga oson)
function buildPlain(order, station) {
  let s = `=== ${station.station_name || 'Кухня'} ===\n`;
  s += `ЗАКАЗ №${order.order_id ?? order.id ?? '-'}\n`;
  s += `СТОЛ: ${order.table_number ?? '-'}\n`;
  s += `Официант: ${order.waiter_name || '-'}\n`;
  const t = new Date(order.created_at);
  s += `Время: ${t.toLocaleString()}\n`;
  s += `--------------------------------\n`;
  for (const it of station.items) {
    s += `${it.quantity} x ${it.name}\n`;
    if (it.notes) s += `   (${it.notes})\n`;
  }
  if (order.notes) s += `Примечание: ${order.notes}\n`;
  s += `\n`;
  return s;
}

// USB/Windows termal printerga XOM (RAW) ESC/POS yuborish — rawprint.ps1 (WritePrinter) orqali.
// Termal printer ESC/POS ni to'g'ridan-to'g'ri tushunadi: qalin/katta shrift, avtokesish.
function sendToUsb(printerName, escposText) {
  return new Promise((resolve, reject) => {
    const tmp = path.join(os.tmpdir(), `sultan_chek_${Date.now()}.bin`);
    fs.writeFileSync(tmp, encode(escposText));
    const ps = path.join(__dirname, 'rawprint.ps1');
    execFile('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps, '-PrinterName', printerName, '-FilePath', tmp],
      { timeout: 20000 },
      (err, stdout, stderr) => {
        try { fs.unlinkSync(tmp); } catch (_) {}
        if (err) return reject(new Error('USB print: ' + (stderr || err.message)));
        if (!`${stdout}`.includes('OK')) return reject(new Error('USB print: ' + (stdout || stderr || 'xato')));
        resolve();
      });
  });
}

// ESC/POS ni TCP (IP:9100) orqali printerga yuborish
function sendToPrinter(ip, port, text) {
  return new Promise((resolve, reject) => {
    const sock = new net.Socket();
    let done = false;
    sock.setTimeout(5000);
    sock.connect(port, ip, () => {
      sock.write(encode(text), () => {
        done = true;
        sock.end();
      });
    });
    sock.on('close', () => { if (done) resolve(); else reject(new Error('ulanish yopildi')); });
    sock.on('timeout', () => { sock.destroy(); reject(new Error('timeout')); });
    sock.on('error', (e) => reject(e));
  });
}

async function processOrder(order) {
  for (const station of order.stations) {
    if (station.printer_ip) {
      // Tarmoq (LAN) printeri
      await sendToPrinter(station.printer_ip, station.printer_port || 9100, buildTicket(order, station));
      console.log(`[print] zakaz #${order.order_id} -> ${station.station_name} (IP ${station.printer_ip})`);
    } else if (station.printer_name) {
      // USB termal printer — xom ESC/POS (qalin shrift + avtokesish)
      await sendToUsb(station.printer_name, buildTicket(order, station));
      console.log(`[print] zakaz #${order.order_id} -> ${station.station_name} (USB: ${station.printer_name})`);
    } else {
      // Printer belgilanmagan — faylga yozamiz (test)
      const file = path.join(TICKETS_DIR, `order${order.order_id}_${station.station_name}.txt`);
      fs.writeFileSync(file, buildPlain(order, station));
      console.log(`[print] zakaz #${order.order_id} -> ${station.station_name} (FAYL: ${path.basename(file)})`);
    }
  }
  // Hammasi muvaffaqiyatli bo'lsa — chop etildi deb belgilaymiz
  const r = await fetch(`${API_URL}/api/print/${order.order_id}/done`, {
    method: 'POST',
    headers: { 'x-print-token': TOKEN },
  });
  if (!r.ok) throw new Error('done belgilashda xato: ' + r.status);
}

async function pollOnce() {
  const r = await fetch(`${API_URL}/api/print/pending`, { headers: { 'x-print-token': TOKEN } });
  if (!r.ok) { console.log('[print] pending xato:', r.status); return; }
  const orders = await r.json();
  for (const order of orders) {
    try {
      await processOrder(order);
    } catch (e) {
      console.log(`[print] zakaz #${order.order_id} xato:`, e.message, '— keyingi siklda qayta urinamiz');
    }
  }
}

// Mijoz chekini (bill) bitta printerga chiqarish
async function processBill(bill) {
  const escpos = buildBill(bill);
  if (bill.printer_ip) {
    await sendToPrinter(bill.printer_ip, bill.printer_port || 9100, escpos);
  } else if (bill.printer_name) {
    await sendToUsb(bill.printer_name, escpos);
  } else {
    const file = path.join(TICKETS_DIR, `bill_order${bill.order_id}.txt`);
    fs.writeFileSync(file, escpos);
  }
  console.log(`[bill] zakaz #${bill.order_id} cheki chiqdi (jami ${bill.total_amount})`);
  const r = await fetch(`${API_URL}/api/print/bills/${bill.order_id}/done`, {
    method: 'POST', headers: { 'x-print-token': TOKEN },
  });
  if (!r.ok) throw new Error('bill done xato: ' + r.status);
}

async function pollBills() {
  const r = await fetch(`${API_URL}/api/print/bills/pending`, { headers: { 'x-print-token': TOKEN } });
  if (!r.ok) { console.log('[bill] pending xato:', r.status); return; }
  const bills = await r.json();
  for (const bill of bills) {
    try {
      await processBill(bill);
    } catch (e) {
      console.log(`[bill] zakaz #${bill.order_id} xato:`, e.message, '— keyingi siklda qayta urinamiz');
    }
  }
}

// ============================================================
// Faza 1: SSE obuna — server "print" hodisasini yuborganda cheklar DARHOL
// chiqadi (3s poll kutmasdan). Polling saqlanadi, lekin moslashuvchan:
//   SSE ulangan  -> har 30s (faqat sug'urta — hodisa yo'qolsa ham chek chiqadi)
//   SSE uzilgan  -> har POLL_SECONDS (3s) — eski ishonchli rejim
// Hodisa faqat "signal": chekni baribir /pending dan olamiz, shuning uchun
// takror/yo'qolgan hodisa hech narsani buzmaydi.
// ============================================================
const SAFETY_POLL_SECONDS = parseInt(process.env.PRINT_SAFETY_POLL_SECONDS || '30', 10);
let sseConnected = false;
let pollScheduled = null;
let pollRunning = false;

async function runPolls() {
  if (pollRunning) return; // parallel ishga tushmasin
  pollRunning = true;
  try { await pollOnce(); } catch (e) { console.log('[print-agent] poll xato:', e.message); }
  try { await pollBills(); } catch (e) { console.log('[print-agent] bill poll xato:', e.message); }
  try { await pollCancels(); } catch (e) { console.log('[print-agent] cancel poll xato:', e.message); }
  pollRunning = false;
}

function scheduleNext() {
  clearTimeout(pollScheduled);
  const delay = (sseConnected ? SAFETY_POLL_SECONDS : POLL_SECONDS) * 1000;
  pollScheduled = setTimeout(async () => { await runPolls(); scheduleNext(); }, delay);
}

// SSE oqimiga ulanish (x-print-token bilan). Uzilsa 5s dan keyin qayta urinadi.
async function subscribeEvents() {
  try {
    const r = await fetch(`${API_URL}/api/events`, {
      headers: { 'x-print-token': TOKEN, 'Accept': 'text/event-stream' },
    });
    if (!r.ok || !r.body) throw new Error('HTTP ' + r.status);
    sseConnected = true;
    console.log('[print-agent] SSE ulandi — cheklar endi darhol chiqadi');
    scheduleNext(); // sekin (sug'urta) rejimga o'tamiz
    await runPolls(); // ulangan zahoti bir marta tekshirib olamiz

    let buf = '';
    for await (const chunk of r.body) {
      buf += Buffer.from(chunk).toString('utf8');
      let idx;
      while ((idx = buf.indexOf('\n\n')) !== -1) {
        const block = buf.slice(0, idx);
        buf = buf.slice(idx + 2);
        // faqat "print" hodisalariga e'tibor beramiz
        if (/^event: change$/m.test(block) && /"entity":"print"/.test(block)) {
          runPolls(); // darhol chop etish (kutmasdan)
        }
      }
    }
    throw new Error('oqim yopildi');
  } catch (e) {
    if (sseConnected) console.log('[print-agent] SSE uzildi:', e.message, '— tez polling rejimiga qaytdik');
    sseConnected = false;
    scheduleNext();
    setTimeout(subscribeEvents, 5000);
  }
}

console.log(`[print-agent] ishga tushdi. API: ${API_URL}, poll ${POLL_SECONDS}s (SSE bilan ${SAFETY_POLL_SECONDS}s). Tickets: ${TICKETS_DIR}`);
runPolls().then(scheduleNext);
subscribeEvents();
