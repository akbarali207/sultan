const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const path = require('path');
const fs = require('fs');
const pool = require('./config/db');

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Idempotentlik: "Idempotency-Key" sarlavhali so'rovlar bir marta bajariladi
// (ikki marta bosish / tarmoq retry dublikat zakaz-to'lov yaratmaydi)
app.use(require('./middleware/idempotency'));

// Vaqtinchalik so'rov logi (diagnostika)
app.use((req, res, next) => {
  const t = Date.now();
  res.on('finish', () => console.log(`[REQ] ${req.method} ${req.path} -> ${res.statusCode} (${Date.now() - t}ms)`));
  next();
});

// Static rasm papkasi
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

// Yengil "tiriklik" tekshiruvi — ilova qaysi manzil (lokal Wi-Fi yoki internet)
// ishlayotganini shu orqali aniqlaydi. Auth va DB kerak emas — tez javob beradi.
app.get('/api/health', (req, res) => res.json({ ok: true, ts: Date.now() }));

// Routes
const authRoutes = require('./routes/authRoutes');
const userRoutes = require('./routes/userRoutes');
const menuRoutes = require('./routes/menuRoutes');
const orderRoutes = require('./routes/orderRoutes');
const expenseRoutes = require('./routes/expenseRoutes');
const reportRoutes = require('./routes/reportRoutes');
const stockRoutes = require('./routes/stockRoutes');
const inventoryRoutes = require('./routes/inventoryRoutes');
const tablewareRoutes = require('./routes/tablewareRoutes');
const hikvisionRoutes = require('./routes/hikvisionRoutes');
const stationRoutes = require('./routes/stationRoutes');
const printRoutes = require('./routes/printRoutes');
const roleRoutes = require('./routes/roleRoutes');
const roomRoutes = require('./routes/roomRoutes');
const eventRoutes = require('./routes/eventRoutes');
const systemRoutes = require('./routes/systemRoutes');

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/menu', menuRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/expenses', expenseRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/stock', stockRoutes);
app.use('/api/inventory', inventoryRoutes);
app.use('/api/tableware', tablewareRoutes);
app.use('/api/hikvision', hikvisionRoutes);
app.use('/api/stations', stationRoutes);
app.use('/api/print', printRoutes);
app.use('/api/roles', roleRoutes);
app.use('/api/rooms', roomRoutes);
app.use('/api/events', eventRoutes); // SSE: real-time invalidatsiya hodisalari
app.use('/api/system', systemRoutes); // super-admin STOP / tizim holati

// Flutter WEB ilovasini xizmat qilish (build/web mavjud bo'lsa)
const webDir = path.join(__dirname, '../../build/web');
if (fs.existsSync(path.join(webDir, 'index.html'))) {
  app.use(express.static(webDir, {
    setHeaders: (res, filePath) => {
      // index.html va service worker keshlanmasin — yangi build darrov yetib borsin
      if (filePath.endsWith('index.html') || filePath.endsWith('flutter_service_worker.js') || filePath.endsWith('flutter.js')) {
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      }
    },
  }));
  // SPA fallback: /api va /uploads dan tashqari barcha GET -> index.html
  app.use((req, res, next) => {
    if (req.method !== 'GET' || req.path.startsWith('/api') || req.path.startsWith('/uploads')) return next();
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.sendFile(path.join(webDir, 'index.html'), (err) => { if (err) next(); });
  });
  console.log('[web] Flutter web ilovasi xizmat qilinmoqda: ' + webDir);
} else {
  app.get('/', (req, res) => {
    res.json({ message: 'Sultan Restoran API ishlamoqda!' });
  });
}

// Jarayon darajasidagi himoya to'ri — kutilmagan xato butun POS'ni jimgina o'ldirmasin.
process.on('unhandledRejection', (reason) => {
  console.error('[proc] unhandledRejection:', reason && reason.message ? reason.message : reason);
});
process.on('uncaughtException', (err) => {
  console.error('[proc] uncaughtException:', err && err.message ? err.message : err);
});

const { runMigrations } = require('./config/runMigrations');
const startServer = () => app.listen(PORT, () => {
  console.log(`Server ${PORT} portda ishlamoqda...`);
  // Hikvision face-id davomat polleri (HIK_ENABLED=true bo'lsa)
  try {
    require('./services/hikvisionPoller').start();
  } catch (e) {
    console.log('[Hikvision] poller start xatosi:', e.message);
  }

  // SROK NAZORATI (F12): har 6 soatda tugayotgan/o'tgan partiyalarni
  // tekshirib bildirishnoma beradi (notify -> console/kelajakda FCM) va
  // frontendga 'stock' hodisasi yuboradi (ochiq sahifalar yangilanadi).
  const checkExpiry = async () => {
    try {
      const { getSetting } = require('./services/costingService');
      const warnDays = parseInt(await getSetting(pool, 'expiry_warn_days', '5'), 10) || 5;
      const r = await pool.query(
        `SELECT
           COUNT(*) FILTER (WHERE expiry_date < CURRENT_DATE)::int AS expired,
           COALESCE(ROUND(SUM((quantity - used_quantity) * unit_cost)
             FILTER (WHERE expiry_date < CURRENT_DATE), 2), 0) AS expired_value,
           COUNT(*) FILTER (WHERE expiry_date >= CURRENT_DATE
             AND expiry_date <= CURRENT_DATE + ($1 || ' days')::interval)::int AS expiring
         FROM stock_lots
         WHERE expiry_date IS NOT NULL AND status IN ('active','blocked')
           AND (quantity - used_quantity) > 0`, [warnDays]);
      const s = r.rows[0];
      if (s.expired > 0 || s.expiring > 0) {
        const { notify } = require('./services/notify');
        await notify({
          title: 'Srok nazorati',
          body: `O'tgan: ${s.expired} partiya (${s.expired_value} so'm), ${warnDays} kun ichida tugaydi: ${s.expiring}`,
          topic: 'expiry', entity: 'stock',
        });
        try { require('./services/eventBus').emit('stock', null); } catch (_) {}
      }
    } catch (e) {
      console.log('[expiry] tekshiruv xatosi:', e.message);
    }
  };
  setTimeout(checkExpiry, 60 * 1000);               // startdan 1 daqiqa keyin
  setInterval(checkExpiry, 6 * 60 * 60 * 1000);     // keyin har 6 soatda

  // Print-agent'ni backend bilan birga avtomatik ishga tushirish (lokal).
  // Bulutga chiqishda PRINT_AGENT_AUTOSTART=false qilib o'chiriladi (agent lokal ko'prikda ishlaydi).
  if (process.env.PRINT_AGENT_AUTOSTART !== 'false') {
    try {
      const { spawn } = require('child_process');
      const agentPath = path.join(__dirname, '../print-agent.js');
      const agent = spawn(process.execPath, [agentPath], { stdio: 'inherit', env: process.env });
      agent.on('error', (e) => console.log('[print-agent] xato:', e.message));
      agent.on('exit', (code) => console.log('[print-agent] to\'xtadi (kod ' + code + ')'));
      console.log('[print-agent] backend bilan birga ishga tushdi.');
    } catch (e) {
      console.log('[print-agent] ishga tushmadi:', e.message);
    }
  }
});

// Avval qo'llanmagan migratsiyalarni qo'llaymiz (schema-drift oldini olish),
// keyin serverni ishga tushiramiz. Migratsiya xato bersa ham server ochiladi.
runMigrations(pool)
  .then((failed) => {
    if (Array.isArray(failed) && failed.length) {
      const bar = '!'.repeat(64);
      console.error('\n' + bar);
      console.error(`[migrate] OGOHLANTIRISH: ${failed.length} ta migratsiya QO'LLANMADI — sxema to'liq emas!`);
      for (const f of failed) console.error('   ✗ ' + f);
      console.error("Ba'zi endpointlar 500 berishi mumkin. Sxemani tekshiring.");
      if (process.env.MIGRATE_STRICT === 'true') {
        console.error('[migrate] MIGRATE_STRICT=true — server ISHGA TUSHIRILMAYDI.');
        console.error(bar + '\n');
        process.exit(1);
      }
      console.error(bar + '\n');
    }
  })
  .catch((e) => console.error('[migrate] xato (server baribir ishga tushadi):', e.message))
  .finally(startServer);

module.exports = app;