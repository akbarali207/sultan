const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const blockIfFrozen = require('../middleware/freezeGuard');
const adminOnly = requireRole('admin', 'director', 'guest');
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
  transferStock,
  divideIntoSlices,
  getWarehouses,
  createWarehouse,
  updateWarehouse,
  deleteWarehouse,
  assignFromRecipe,
  getIngredientCategories,
  createIngredientCategory,
  updateIngredientCategory,
  deleteIngredientCategory
} = require('../controllers/stockController');

const {
  getLots, getLotDetail, writeoffLot, setLotBlocked, returnLot, payLot, getExpiry,
} = require('../controllers/lotController');
const {
  getSuppliers, createSupplier, updateSupplier, deleteSupplier, getSupplierLedger, paySupplier,
} = require('../controllers/supplierController');
const {
  getTimeline, getIngredientAnalytics, getAbcXyz,
} = require('../controllers/stockIntelController');

// ─── PARTIYALAR (F10/F12) — generik /:id dan oldin ───
router.get('/lots', authMiddleware, adminOnly, getLots);
router.get('/lots/:id', authMiddleware, adminOnly, getLotDetail);
router.post('/lots/:id/writeoff', authMiddleware, adminOnly, blockIfFrozen, writeoffLot);
router.post('/lots/:id/block', authMiddleware, adminOnly, setLotBlocked);
router.post('/lots/:id/return', authMiddleware, adminOnly, blockIfFrozen, returnLot);
router.post('/lots/:id/pay', authMiddleware, adminOnly, blockIfFrozen, payLot);
router.get('/expiry', authMiddleware, adminOnly, getExpiry);

// ─── POSTAVSHIKLAR (F13) ───
router.get('/suppliers', authMiddleware, adminOnly, getSuppliers);
router.post('/suppliers', authMiddleware, adminOnly, createSupplier);
router.put('/suppliers/:id', authMiddleware, adminOnly, updateSupplier);
router.delete('/suppliers/:id', authMiddleware, adminOnly, deleteSupplier);
router.get('/suppliers/:id/ledger', authMiddleware, adminOnly, getSupplierLedger);
router.post('/suppliers/:id/pay', authMiddleware, adminOnly, blockIfFrozen, paySupplier);

// ─── ANALITIKA (F15) ───
router.get('/analytics/abc-xyz', authMiddleware, adminOnly, getAbcXyz);

// Skladlar (warehouses) — generik /:id dan oldin turishi shart
router.get('/warehouses', authMiddleware, adminOnly, getWarehouses);
router.post('/warehouses', authMiddleware, adminOnly, createWarehouse);
router.put('/warehouses/:id', authMiddleware, adminOnly, updateWarehouse);
router.delete('/warehouses/:id', authMiddleware, adminOnly, deleteWarehouse);
router.post('/assign-from-recipe', authMiddleware, adminOnly, assignFromRecipe);

// Ingredient kategoriyalar (ETAP 3.1) — generik /:id dan oldin
router.get('/ingredient-categories', authMiddleware, adminOnly, getIngredientCategories);
router.post('/ingredient-categories', authMiddleware, adminOnly, createIngredientCategory);
router.put('/ingredient-categories/:id', authMiddleware, adminOnly, updateIngredientCategory);
router.delete('/ingredient-categories/:id', authMiddleware, adminOnly, deleteIngredientCategory);

router.get('/', authMiddleware, adminOnly, getIngredients);
router.post('/', authMiddleware, adminOnly, createIngredient);
router.post('/incoming', authMiddleware, adminOnly, blockIfFrozen, addIncoming);
router.post('/produce', authMiddleware, adminOnly, blockIfFrozen, producePf); // P/F tayyorlash
router.post('/transfer', authMiddleware, adminOnly, blockIfFrozen, transferStock); // Трансфер между складами
router.get('/transfers', authMiddleware, adminOnly, require('../controllers/stockController').getTransfers); // История перемещений
router.get('/reconcile', authMiddleware, adminOnly, require('../controllers/stockController').getStockReconcile); // Сверка склада (рецепт vs продажи)
router.post('/reconcile/fix', authMiddleware, adminOnly, blockIfFrozen, require('../controllers/stockController').fixStockReconcile);
router.post('/divide-slices', authMiddleware, adminOnly, blockIfFrozen, divideIntoSlices); // Деление торта на кусочки
router.get('/incoming', authMiddleware, adminOnly, getIncomingHistory);
router.get('/low', authMiddleware, adminOnly, getLowStock);
router.put('/:id/edit', authMiddleware, adminOnly, editIngredient);   // tahrirlash (sabab majburiy)
router.get('/:id/history', authMiddleware, adminOnly, getStockHistory); // o'zgarishlar tarixi
router.get('/:id/timeline', authMiddleware, adminOnly, getTimeline);  // to'liq tarix lentasi (F14)
router.get('/:id/analytics', authMiddleware, adminOnly, getIngredientAnalytics); // tovar analitikasi (F15)
router.post('/:id/merge', authMiddleware, adminOnly, mergeIngredient); // dublikatni target ga birlashtirish
router.put('/:id', authMiddleware, adminOnly, updateSellingPrice);
router.delete('/:id', authMiddleware, adminOnly, deleteIngredient);

module.exports = router;
