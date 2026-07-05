const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getExpenseTypes,
  createExpenseType,
  updateExpenseType,
  deleteExpenseType,
  getExpenses,
  getOutflows,
  createExpense,
  deleteExpense
} = require('../controllers/expenseController');

router.get('/types', authMiddleware, adminOnly, getExpenseTypes);
router.post('/types', authMiddleware, adminOnly, createExpenseType);
router.put('/types/:id', authMiddleware, adminOnly, updateExpenseType);
router.delete('/types/:id', authMiddleware, adminOnly, deleteExpenseType);

router.get('/outflows', authMiddleware, adminOnly, getOutflows);
router.get('/', authMiddleware, adminOnly, getExpenses);
router.post('/', authMiddleware, adminOnly, createExpense);
router.delete('/:id', authMiddleware, adminOnly, deleteExpense);

module.exports = router;