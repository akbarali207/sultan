// ============================================================
//  SULTAN — ESC/POS test xizmati (backend)
//  Printerni ANIQLASH uchun: berilgan printerga "sinov cheki" yuboradi.
//  Backend va printerlar bitta kompda bo'lgani uchun bu yerda to'g'ridan-to'g'ri
//  chop etamiz (print-agent'ga tegmaymiz). USB -> rawprint.ps1, IP -> TCP:9100.
// ============================================================
const net = require('net');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');

// ---- ESC/POS yordamchilari (print-agent bilan bir xil) ----
const ESC = '\x1B', GS = '\x1D', FS = '\x1C';
const CMD = {
  init: ESC + '@',
  kanjiOff: FS + '.',
  cp866: ESC + 't' + '\x11',
  alignC: ESC + 'a' + '\x01',
  alignL: ESC + 'a' + '\x00',
  boldOn: ESC + 'E' + '\x01',
  boldOff: ESC + 'E' + '\x00',
  big: GS + '!' + '\x11',
  normal: GS + '!' + '\x00',
  cut: GS + 'V' + '\x42' + '\x00',
};

function cp866Byte(c) {
  if (c < 0x80) return c;
  if (c >= 0x0410 && c <= 0x042F) return c - 0x0410 + 0x80;
  if (c >= 0x0430 && c <= 0x043F) return c - 0x0430 + 0xA0;
  if (c >= 0x0440 && c <= 0x044F) return c - 0x0440 + 0xE0;
  if (c === 0x0401) return 0xF0;
  if (c === 0x0451) return 0xF1;
  if (c === 0x2116) return 0xFC;
  if (c === 0x00B0) return 0xF8;
  if (c === 0x00B7) return 0xFA;
  if (c === 0x2014 || c === 0x2013) return 0x2D;
  if (c === 0x00AB || c === 0x00BB || c === 0x201C || c === 0x201D) return 0x22;
  if (c === 0x2018 || c === 0x2019) return 0x27;
  return 0x3F;
}
function encode(str) {
  const bytes = [];
  for (const ch of str) bytes.push(cp866Byte(ch.codePointAt(0)));
  return Buffer.from(bytes);
}

// Sinov chekini (ESC/POS) tayyorlash. title = katta sarlavha (bo'lim/printer nomi).
function buildTestSlip(title, infoLines) {
  let s = '';
  s += CMD.init + CMD.kanjiOff + CMD.cp866;
  s += CMD.alignC + CMD.boldOn + CMD.big;
  s += 'SULTAN\n';
  s += CMD.normal;
  s += 'ТЕСТ ЧЕК\n';
  s += CMD.boldOff;
  s += '--------------------------------\n';
  s += CMD.boldOn + CMD.big + (title || 'TEST') + '\n' + CMD.normal + CMD.boldOff;
  s += '--------------------------------\n';
  s += CMD.alignL;
  for (const line of (infoLines || [])) s += line + '\n';
  s += CMD.alignC + '\nBu chek shu printerdan chiqdi.\nBelgilab qo\'ying!\n';
  s += '\n\n' + CMD.cut;
  return s;
}

// USB/Windows printerga xom ESC/POS yuborish (rawprint.ps1 orqali)
function sendToUsb(printerName, escposText) {
  return new Promise((resolve, reject) => {
    const tmp = path.join(os.tmpdir(), `sultan_test_${Date.now()}.bin`);
    fs.writeFileSync(tmp, encode(escposText));
    const ps = path.join(__dirname, '..', '..', 'rawprint.ps1'); // backend/rawprint.ps1
    execFile('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps, '-PrinterName', printerName, '-FilePath', tmp],
      { timeout: 20000 },
      (err, stdout, stderr) => {
        try { fs.unlinkSync(tmp); } catch (_) {}
        if (err) return reject(new Error('USB: ' + (stderr || err.message)));
        if (!`${stdout}`.includes('OK')) return reject(new Error('USB: ' + (stdout || stderr || 'xato')));
        resolve();
      });
  });
}

// ESC/POS ni TCP (IP:9100) orqali yuborish
function sendToPrinter(ip, port, text) {
  return new Promise((resolve, reject) => {
    const sock = new net.Socket();
    let done = false;
    sock.setTimeout(5000);
    sock.connect(port, ip, () => {
      sock.write(encode(text), () => { done = true; sock.end(); });
    });
    sock.on('close', () => { if (done) resolve(); else reject(new Error('ulanish yopildi')); });
    sock.on('timeout', () => { sock.destroy(); reject(new Error('timeout — printer javob bermadi')); });
    sock.on('error', (e) => reject(e));
  });
}

// Kompdagi o'rnatilgan Windows printerlar ro'yxati (nomlari)
function listWindowsPrinters() {
  return new Promise((resolve) => {
    execFile('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'Get-Printer | Select-Object -ExpandProperty Name'],
      { timeout: 15000 },
      (err, stdout) => {
        if (err || !stdout) return resolve([]);
        const names = `${stdout}`.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
        resolve(names);
      });
  });
}

module.exports = { buildTestSlip, sendToUsb, sendToPrinter, listWindowsPrinters };
