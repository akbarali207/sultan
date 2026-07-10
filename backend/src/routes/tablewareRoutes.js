const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin', 'director', 'guest');
const {
  getTableware,
  createTableware,
  updateTableware,
  deleteTableware
} = require('../controllers/tablewareController');

router.get('/', authMiddleware, adminOnly, getTableware);
router.post('/', authMiddleware, adminOnly, createTableware);
router.put('/:id', authMiddleware, adminOnly, updateTableware);
router.delete('/:id', authMiddleware, adminOnly, deleteTableware);

module.exports = router;
