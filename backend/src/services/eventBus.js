// ============================================================
// SSE hodisa shinasi (Faza 1) — restoran ichidagi real-time.
//
// MUHIM QOIDA: hodisalar FAQAT "invalidatsiya" — "nima o'zgardi" degan ishora
// ({entity, id}), hech qachon biznes-ma'lumot EMAS. Mijoz hodisani olgach
// haqiqiy holatni REST orqali qayta o'qiydi. Shu tufayli yo'qolgan, takror
// yoki tartibsiz kelgan hodisa pulga ta'sir qila OLMAYDI — eng yomoni
// bitta ortiqcha refetch.
//
// seq — monoton raqam: mijoz uzilib qayta ulansa Last-Event-ID orqali
// o'tkazib yuborilgan hodisalarni buferdan oladi; bufer yetmasa to'liq
// refetch qiladi (mavjud polling shunga tayyor).
// ============================================================

let seq = 0;
const subscribers = new Set(); // har biri: { res }
const recent = []; // oxirgi hodisalar buferi (qayta ulanish uchun)
const MAX_RECENT = 500;

function sseFormat(ev) {
  return `id: ${ev.seq}\nevent: change\ndata: ${JSON.stringify(ev)}\n\n`;
}

// entity: 'orders' | 'tables' | 'kassa' | 'print' | 'menu' ...
function emit(entity, id = null) {
  const ev = { seq: ++seq, entity, id, ts: new Date().toISOString() };
  recent.push(ev);
  if (recent.length > MAX_RECENT) recent.shift();
  const payload = sseFormat(ev);
  for (const sub of subscribers) {
    try { sub.res.write(payload); } catch (_) { subscribers.delete(sub); }
  }
  return ev.seq;
}

// SSE ulanishini ro'yxatga olish. lastEventId — mijozning oxirgi ko'rgan seq'i.
function subscribe(res, lastEventId = null) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.write('retry: 3000\n\n');

  // Qayta ulanish: o'tkazib yuborilganlarni buferdan yetkazamiz.
  // Bufer yetmasa (juda eski seq) — maxsus "resync" hodisasi: to'liq refetch signal.
  const lastSeq = parseInt(lastEventId, 10);
  if (!isNaN(lastSeq)) {
    if (recent.length && recent[0].seq > lastSeq + 1) {
      res.write(`event: resync\ndata: {"reason":"buffer-overflow"}\n\n`);
    } else {
      for (const ev of recent) if (ev.seq > lastSeq) res.write(sseFormat(ev));
    }
  }

  const sub = { res };
  subscribers.add(sub);

  // Keepalive — proksi/tunnel ulanishni uzib qo'ymasligi uchun
  const ka = setInterval(() => {
    try { res.write(': ping\n\n'); } catch (_) { cleanup(); }
  }, 25000);

  function cleanup() {
    clearInterval(ka);
    subscribers.delete(sub);
  }
  res.on('close', cleanup);
  res.on('error', cleanup);
}

function stats() {
  return { subscribers: subscribers.size, lastSeq: seq };
}

module.exports = { emit, subscribe, stats };
