const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const blockIfFrozen = require('../middleware/freezeGuard');
const adminOnly = requireRole('admin', 'director', 'guest');
const {
  getExpenseTypes,
  createExpenseType,
  updateExpenseType,
  deleteExpenseType,
  getExpenses,
  getOutflows,
  createExpense,
  deleteExpense,
  getPayables,
  createPayable,
  payPayable,
  deletePayable
} = require('../controllers/expenseController');

router.get('/types', authMiddleware, adminOnly, getExpenseTypes);
router.post('/types', authMiddleware, adminOnly, createExpenseType);
router.put('/types/:id', authMiddleware, adminOnly, updateExpenseType);
router.delete('/types/:id', authMiddleware, adminOnly, deleteExpenseType);

router.get('/outflows', authMiddleware, adminOnly, getOutflows);
router.get('/', authMiddleware, adminOnly, getExpenses);
router.post('/', authMiddleware, adminOnly, blockIfFrozen, createExpense);
router.delete('/:id', authMiddleware, adminOnly, blockIfFrozen, deleteExpense);

// Kreditorlar (qarzга olingan buyumlar)
router.get('/payables', authMiddleware, adminOnly, getPayables);
router.post('/payables', authMiddleware, adminOnly, blockIfFrozen, createPayable);
router.post('/payables/:id/pay', authMiddleware, adminOnly, blockIfFrozen, payPayable);
router.delete('/payables/:id', authMiddleware, adminOnly, blockIfFrozen, deletePayable);

module.exports = router;