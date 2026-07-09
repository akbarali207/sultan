const express = require('express');
const router = express.Router();
const auth = require('../middleware/authMiddleware');
const { getState, setFreeze } = require('../controllers/systemController');

router.get('/state', auth, getState);
router.post('/freeze', auth, setFreeze); // faqat super-admin (guest) — controller ichida tekshiriladi

module.exports = router;
