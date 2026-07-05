const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getStations,
  createStation,
  updateStation,
  deleteStation
} = require('../controllers/stationController');

// O'qish — barcha xodimlar (menyu/ofitsantga bo'lim nomi kerak bo'lishi mumkin)
router.get('/', authMiddleware, getStations);
// Yozish — faqat admin
router.post('/', authMiddleware, adminOnly, createStation);
router.put('/:id', authMiddleware, adminOnly, updateStation);
router.delete('/:id', authMiddleware, adminOnly, deleteStation);

module.exports = router;
