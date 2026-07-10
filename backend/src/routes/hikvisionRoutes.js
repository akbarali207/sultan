const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin', 'director', 'guest');
const { getDeviceInfo, CFG, addDeviceUser } = require('../services/hikvision');
const { recordFaceAttendance } = require('../services/attendanceService');

// Qurilma holati / ulanish testi (ilovadan tekshirish uchun)
router.get('/status', authMiddleware, adminOnly, async (req, res) => {
  try {
    if (!CFG.pass) {
      return res.json({ connected: false, ip: CFG.ip, message: 'HIK_PASS o\'rnatilmagan' });
    }
    const info = await getDeviceInfo();
    const connected = info.status === 200;
    res.json({
      connected,
      ip: CFG.ip,
      status: info.status,
      message: connected ? 'Qurilmaga ulandi' : 'Ulanmadi — parol/aktivatsiyani tekshiring',
    });
  } catch (e) {
    res.json({ connected: false, ip: CFG.ip, message: e.message });
  }
});

// Real-time push (lokal "ko'prik" yoki qurilma yuboradi).
// JWT o'rniga maxfiy token bilan himoyalanadi (x-event-token sarlavhasi).
// FAIL-CLOSED: token sozlanmagan bo'lsa — endpoint yopiq (ochiq qolmaydi).
router.post('/event', (req, res, next) => {
  const expected = process.env.HIK_EVENT_TOKEN;
  if (!expected) {
    return res.status(503).json({ ok: false, message: 'HIK_EVENT_TOKEN sozlanmagan' });
  }
  const got = req.headers['x-event-token'];
  if (got !== expected) {
    return res.status(401).json({ ok: false, message: 'Token noto\'g\'ri' });
  }
  next();
}, async (req, res) => {
  try {
    const body = req.body || {};
    const ev = body.AccessControllerEvent || body.access_controller_event || {};
    const empNo = ev.employeeNoString || ev.employeeNo || body.employeeNoString;
    const when = body.dateTime || body.time || ev.time;
    if (empNo) {
      const r = await recordFaceAttendance(empNo, when);
      console.log(`[Hikvision push] ${r.type || '-'}: ${r.message}`);
    }
    res.json({ ok: true }); // qurilmaga doim 200 qaytaramiz
  } catch (e) {
    res.json({ ok: false, message: e.message });
  }
});

// Xodimni qurilmaga qo'shish (Employee No = Face ID raqami). Yuz keyin qurilmada olinadi.
router.post('/enroll', authMiddleware, adminOnly, async (req, res) => {
  try {
    const { employeeNo, name } = req.body;
    if (!employeeNo) {
      return res.status(400).json({ ok: false, message: 'Face ID raqami kerak' });
    }
    if (!CFG.pass) {
      return res.json({ ok: false, message: 'HIK_PASS o\'rnatilmagan' });
    }
    const r = await addDeviceUser({ employeeNo, name: name || '' });
    if (r.ok) {
      return res.json({ ok: true, message: 'Qurilmaga qo\'shildi. Endi qurilmada shu raqam ostiga yuzni qo\'shing.' });
    }
    // employeeNo allaqachon mavjud bo'lsa — bu ham yaxshi (yuzni qo'shsa bo'ladi)
    const ss = (r.json && (r.json.statusString || r.json.subStatusCode)) || (r.raw || '').slice(0, 150);
    const exists = /exist/i.test(JSON.stringify(r.json || r.raw || ''));
    res.json({
      ok: exists,
      message: exists
        ? 'Bu raqam qurilmada allaqachon bor. Yuzni shu raqam ostiga qo\'shing.'
        : 'Qurilma rad etdi: ' + ss,
    });
  } catch (e) {
    res.json({ ok: false, message: e.message });
  }
});

module.exports = router;
