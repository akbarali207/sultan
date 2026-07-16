const express = require('express');
const router = express.Router();
const auth = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin', 'director', 'guest');
const { getState, setFreeze } = require('../controllers/systemController');
const {
  getSettings, putSetting, checkConsistency, fixConsistency,
} = require('../controllers/stockIntelController');

router.get('/state', auth, getState);
router.post('/freeze', auth, setFreeze); // faqat super-admin (guest) — controller ichida tekshiriladi

// Sozlamalar (F11: FIFO/LIFO/AVG tannarx metodi va boshqalar)
router.get('/settings', auth, adminOnly, getSettings);
router.put('/settings', auth, adminOnly, putSetting);

// Konsistensiya tekshiruvi (F17) — faqat o'qish + tasdiqlangan xavfsiz tuzatish
router.get('/consistency', auth, adminOnly, checkConsistency);
router.post('/consistency/fix', auth, adminOnly, fixConsistency);

module.exports = router;
