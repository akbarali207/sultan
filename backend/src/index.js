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

app.listen(PORT, () => {
  console.log(`Server ${PORT} portda ishlamoqda...`);
  // Hikvision face-id davomat polleri (HIK_ENABLED=true bo'lsa)
  try {
    require('./services/hikvisionPoller').start();
  } catch (e) {
    console.log('[Hikvision] poller start xatosi:', e.message);
  }

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

module.exports = app;