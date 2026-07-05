const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();
const { subscribe, stats } = require('../services/eventBus');

// SSE oqimi: GET /api/events
// Auth ikki xil (ikkalasi ham FAIL-CLOSED):
//  - foydalanuvchi (ilova): JWT — Authorization sarlavhasi YOKI ?token= query
//    (brauzer EventSource sarlavha qo'ya olmaydi, shuning uchun query kerak)
//  - print-agent: x-print-token sarlavhasi
router.get('/', (req, res) => {
  const printExpected = process.env.PRINT_AGENT_TOKEN;
  const printGot = req.headers['x-print-token'];
  if (printGot) {
    if (!printExpected || printGot !== printExpected) {
      return res.status(401).json({ message: 'Token noto\'g\'ri' });
    }
  } else {
    const raw = req.headers.authorization?.split(' ')[1] || req.query.token;
    if (!raw) return res.status(401).json({ message: 'Token topilmadi' });
    try {
      jwt.verify(raw, process.env.JWT_SECRET);
    } catch (_) {
      return res.status(401).json({ message: 'Token yaroqsiz' });
    }
  }

  const lastEventId = req.headers['last-event-id'] || req.query.lastEventId || null;
  subscribe(res, lastEventId);
});

// Diagnostika: nechta ulanish bor, oxirgi seq
router.get('/stats', (req, res) => {
  res.json(stats());
});

module.exports = router;
