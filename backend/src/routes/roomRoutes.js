const express = require('express');
const router = express.Router();
const auth = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getRooms, createRoom, updateRoom, deleteRoom,
  getTables, createTable, updateTable, deleteTable,
} = require('../controllers/roomController');

// O'qish — barcha xodimlar (ofitsant stol/xona ko'radi). Yozish — faqat admin.
// Stollar (/:id dan oldin turishi shart, aks holda 'tables' id deb qabul qilinadi)
router.get('/tables', auth, getTables);
router.post('/tables', auth, adminOnly, createTable);
router.put('/tables/:id', auth, adminOnly, updateTable);
router.delete('/tables/:id', auth, adminOnly, deleteTable);

// Xonalar
router.get('/', auth, getRooms);
router.post('/', auth, adminOnly, createRoom);
router.put('/:id', auth, adminOnly, updateRoom);
router.delete('/:id', auth, adminOnly, deleteRoom);

module.exports = router;
