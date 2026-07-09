const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { login, faceCheckIn, verifyPassword } = require('../controllers/authController');

router.post('/login', login);
// Yuz orqali davomat push (lokal "ko'prik" yoki qurilma yuboradi).
// JWT o'rniga maxfiy token bilan himoyalanadi (x-event-token sarlavhasi) — Hikvision /event bilan bir xil.
// FAIL-CLOSED: token sozlanmagan bo'lsa — endpoint yopiq (ochiq qolmaydi).
router.post('/face-checkin', (req, res, next) => {
  const expected = process.env.HIK_EVENT_TOKEN;
  if (!expected) {
    return res.status(503).json({ ok: false, message: 'HIK_EVENT_TOKEN sozlanmagan' });
  }
  const got = req.headers['x-event-token'];
  if (got !== expected) {
    return res.status(401).json({ ok: false, message: 'Token noto\'g\'ri' });
  }
  next();
}, faceCheckIn);
router.post('/verify-password', authMiddleware, verifyPassword);

module.exports = router;