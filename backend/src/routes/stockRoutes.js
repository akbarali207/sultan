const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getIngredients,
  createIngredient,
  addIncoming,
  getIncomingHistory,
  getLowStock,
  updateSellingPrice,
  editIngredient,
  getStockHistory,
  producePf,
  deleteIngredient,
  mergeIngredient,
  getWarehouses,
  createWarehouse,
  updateWarehouse,
  deleteWarehouse,
  assignFromRecipe
} = require('../controllers/stockController');

// Skladlar (warehouses) — generik /:id dan oldin turishi shart
router.get('/warehouses', authMiddleware, adminOnly, getWarehouses);
router.post('/warehouses', authMiddleware, adminOnly, createWarehouse);
router.put('/warehouses/:id', authMiddleware, adminOnly, updateWarehouse);
router.delete('/warehouses/:id', authMiddleware, adminOnly, deleteWarehouse);
router.post('/assign-from-recipe', authMiddleware, adminOnly, assignFromRecipe);

router.get('/', authMiddleware, adminOnly, getIngredients);
router.post('/', authMiddleware, adminOnly, createIngredient);
router.post('/incoming', authMiddleware, adminOnly, addIncoming);
router.post('/produce', authMiddleware, adminOnly, producePf); // P/F tayyorlash
router.get('/incoming', authMiddleware, adminOnly, getIncomingHistory);
router.get('/low', authMiddleware, adminOnly, getLowStock);
router.put('/:id/edit', authMiddleware, adminOnly, editIngredient);   // tahrirlash (sabab majburiy)
router.get('/:id/history', authMiddleware, adminOnly, getStockHistory); // o'zgarishlar tarixi
router.post('/:id/merge', authMiddleware, adminOnly, mergeIngredient); // dublikatni target ga birlashtirish
router.put('/:id', authMiddleware, adminOnly, updateSellingPrice);
router.delete('/:id', authMiddleware, adminOnly, deleteIngredient);

module.exports = router;
