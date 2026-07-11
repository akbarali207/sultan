// Tizim STOP (freeze) qilinган bo'lsa — pul mutatsiyalarини bloklaydi (423).
// Egasi: "STOP bosilса hech narsa ishlamasин" — zakaz+to'lov controllerда, qolган
// pul amallари (kirim/produce/kassa/qarz/oylik/xarajat) shu middleware bilan.
const { isFrozen } = require('../controllers/systemController');

module.exports = async function blockIfFrozen(req, res, next) {
  try {
    if (await isFrozen()) {
      return res.status(423).json({ message: 'Tizim to\'xtatilgan (STOP) — hozir amal bajarib bo\'lmaydi' });
    }
  } catch (_) { /* system_state yo'q bo'lsa bloklamaymiz */ }
  next();
};
