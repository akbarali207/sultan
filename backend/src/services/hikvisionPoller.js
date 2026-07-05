// Hikvision polleri — qurilmadan yuz tanish eventlarini davriy ravishda olib,
// davomatga (attendance) yozadi. HIK_ENABLED=true va HIK_PASS o'rnatilganda ishlaydi.
const { fetchAcsEvents, getDeviceInfo, CFG } = require('./hikvision');
const { recordFaceAttendance } = require('./attendanceService');

const POLL_SECONDS = parseInt(process.env.HIK_POLL_SECONDS || '5', 10);
const WINDOW_MIN = parseInt(process.env.HIK_WINDOW_MIN || '2', 10); // qancha oxirgi daqiqa eventlari so'raladi
// Bir xodim uchun shu soniya ichidagi takror eventlar e'tiborsiz qoldiriladi (burst'ni yig'ish uchun).
// Kirish va chiqish soatlar farq qiladi, shuning uchun katta cooldown xavfsiz.
const COOLDOWN_SEC = parseInt(process.env.HIK_COOLDOWN_SEC || '180', 10);

// Qayta ishlangan eventlar (serialNo) — takror yozmaslik uchun
const processed = new Set();
const MAX_PROCESSED = 5000;
// Har bir xodimning oxirgi qayta ishlangan event vaqti (ms) — debounce uchun
const lastSeen = new Map();

// Hikvision vaqt formati: ISO + timezone offset, masalan 2026-06-18T09:00:00+05:00
function isoLocal(d) {
  const off = -d.getTimezoneOffset(); // daqiqa
  const sign = off >= 0 ? '+' : '-';
  const abs = Math.abs(off);
  const hh = String(Math.floor(abs / 60)).padStart(2, '0');
  const mm = String(abs % 60).padStart(2, '0');
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}${sign}${hh}:${mm}`;
}

function remember(serial) {
  processed.add(serial);
  if (processed.size > MAX_PROCESSED) {
    // eng eski yarmini tozalash
    const arr = [...processed];
    processed.clear();
    arr.slice(arr.length / 2).forEach((s) => processed.add(s));
  }
}

async function pollOnce() {
  const now = new Date();
  const start = new Date(now.getTime() - WINDOW_MIN * 60 * 1000);
  let pos = 0;
  let total = Infinity;

  while (pos < total) {
    const { status, json } = await fetchAcsEvents(isoLocal(start), isoLocal(now), pos, 50);
    if (status !== 200 || !json || !json.AcsEvent) break;

    const ev = json.AcsEvent;
    total = ev.totalMatches ?? 0;
    const list = (ev.InfoList || []).slice().sort((a, b) => new Date(a.time) - new Date(b.time));
    if (list.length === 0) break;

    for (const item of list) {
      const serial = `${item.serialNo}_${item.time}`;
      if (processed.has(serial)) continue;
      remember(serial);

      const empNo = item.employeeNoString || item.employeeNo;
      // Faqat tanilgan xodim eventlari (yuz/karta/parol muvaffaqiyatli)
      if (empNo === undefined || empNo === null || `${empNo}`.trim() === '') continue;

      // Debounce: shu xodimning oxirgi qayta ishlangan eventidan COOLDOWN ichida bo'lsa — o'tkazib yuboramiz
      const evMs = new Date(item.time).getTime();
      const prevMs = lastSeen.get(`${empNo}`);
      if (prevMs !== undefined && Math.abs(evMs - prevMs) < COOLDOWN_SEC * 1000) {
        continue; // burst ichidagi takror
      }
      lastSeen.set(`${empNo}`, evMs);

      try {
        const r = await recordFaceAttendance(empNo, item.time);
        if (r.ok) {
          console.log(`[Hikvision] ${r.type}: ${r.message} (empNo=${empNo}, ${item.time})`);
        } else {
          console.log(`[Hikvision] e'tibor: ${r.message}`);
        }
      } catch (e) {
        console.log('[Hikvision] davomat xatosi:', e.message);
      }
    }

    pos += list.length;
    if (ev.responseStatusStrg === 'NO MATCH' || list.length < 50) break;
  }
}

let timer = null;

async function start() {
  if (process.env.HIK_ENABLED !== 'true') {
    console.log('[Hikvision] o\'chirilgan (HIK_ENABLED != true). Integratsiya kuting.');
    return;
  }
  if (!CFG.pass) {
    console.log('[Hikvision] HIK_PASS o\'rnatilmagan — qurilma aktivlashtirilgach parolni .env ga yozing.');
    return;
  }

  // Ulanishni tekshirish
  try {
    const info = await getDeviceInfo();
    if (info.status === 200) {
      console.log(`[Hikvision] qurilmaga ulandi: ${CFG.ip}`);
    } else {
      console.log(`[Hikvision] ulanish javobi: ${info.status} — parol/aktivatsiyani tekshiring.`);
    }
  } catch (e) {
    console.log('[Hikvision] ulanib bo\'lmadi:', e.message);
  }

  const loop = async () => {
    try { await pollOnce(); } catch (e) { console.log('[Hikvision] poll xatosi:', e.message); }
    timer = setTimeout(loop, POLL_SECONDS * 1000);
  };
  loop();
  console.log(`[Hikvision] poller ishga tushdi (har ${POLL_SECONDS}s).`);
}

function stop() { if (timer) clearTimeout(timer); }

module.exports = { start, stop, pollOnce };
