const express = require('express');
const router = express.Router();
const auth = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const blockIfFrozen = require('../middleware/freezeGuard'); // AUDIT-FIX #4: STOP paytida pul amallarini bloklash
const {
  getTables, createTable,
  createOrder, getOrders, getOrderItems,
  updateOrderStatus, deleteOrder, cancelOrderItem, printBill, moveOrder, moveOrderItems, reopenOrder
} = require('../controllers/orderController');

router.get('/tables', auth, getTables);
// Stol yaratish — faqat admin (POST /rooms/tables bilan bir xil huquq).
// Ilgari rolsiz edi: istalgan ofitsant/chef room_id'siz "ko'rinmas" stollar yasashi mumkin edi.
router.post('/tables', auth, requireRole('admin', 'director', 'guest'), createTable);

router.get('/', auth, getOrders);
router.post('/', auth, createOrder);
router.get('/:id/items', auth, getOrderItems);
router.put('/:id/status', auth, updateOrderStatus);
router.put('/:id/move', auth, moveOrder); // stolni ko'chirish / birlashtirish
router.put('/:id/move-items', auth, moveOrderItems); // QISMAN ko'chirish (tanlangan taomlar/miqdor)
router.put('/:id/reopen', auth, blockIfFrozen, reopenOrder); // to'langan zakazni qayta ochish (to'lovni tuzatish) — STOP paytida bloklanadi
router.post('/:id/bill', auth, printBill); // hisob/chek chiqarish (bill_requested)
router.delete('/:orderId/items/:itemId', auth, cancelOrderItem); // bitta taomni bekor qilish
router.delete('/:id', auth, blockIfFrozen, deleteOrder); // butun zakazni o'chirish — STOP paytida bloklanadi

module.exports = router;
