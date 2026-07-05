const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getPending, markPrinted, getPendingBills, markBillPrinted,
  getPendingCancels, markCancelPrinted,
  listPrinters, testPrint,
} = require('../controllers/printController');

// Print-agent maxfiy token bilan ulanadi (JWT emas, chunki bu xizmat foydalanuvchi emas).
// FAIL-CLOSED: token sozlanmagan bo'lsa — hech kim kirolmaydi (ochiq qolmaydi).
function printAuth(req, res, next) {
  const expected = process.env.PRINT_AGENT_TOKEN;
  if (!expected) {
    return res.status(503).json({ message: 'PRINT_AGENT_TOKEN sozlanmagan — server admini .env ni tekshirsin' });
  }
  if (req.headers['x-print-token'] !== expected) {
    return res.status(401).json({ message: 'Token noto\'g\'ri' });
  }
  next();
}

// Print-agent (token bilan)
router.get('/pending', printAuth, getPending);
router.post('/:id/done', printAuth, markPrinted);
router.get('/bills/pending', printAuth, getPendingBills);
router.post('/bills/:id/done', printAuth, markBillPrinted);
router.get('/cancels/pending', printAuth, getPendingCancels);   // atmen cheklari
router.post('/cancels/:id/done', printAuth, markCancelPrinted);

// Admin UI (JWT + admin) — printer ro'yxati va sinov cheki
router.get('/printers', authMiddleware, adminOnly, listPrinters);
router.post('/test', authMiddleware, adminOnly, testPrint);

module.exports = router;
