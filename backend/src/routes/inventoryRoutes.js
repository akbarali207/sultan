const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getInventories,
  createInventory,
  getInventoryItems,
  updateInventoryItem,
  closeInventory
} = require('../controllers/inventoryController');

router.get('/', authMiddleware, adminOnly, getInventories);
router.post('/', authMiddleware, adminOnly, createInventory);
router.get('/:id/items', authMiddleware, adminOnly, getInventoryItems);
router.put('/items/:id', authMiddleware, adminOnly, updateInventoryItem);
router.put('/:id/close', authMiddleware, adminOnly, closeInventory);

module.exports = router;