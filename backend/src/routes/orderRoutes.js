const express = require('express');
const router = express.Router();
const auth = require('../middleware/authMiddleware');
const {
  getTables, createTable,
  createOrder, getOrders, getOrderItems,
  updateOrderStatus, deleteOrder, cancelOrderItem, printBill, moveOrder, moveOrderItems, reopenOrder
} = require('../controllers/orderController');

router.get('/tables', auth, getTables);
router.post('/tables', auth, createTable);

router.get('/', auth, getOrders);
router.post('/', auth, createOrder);
router.get('/:id/items', auth, getOrderItems);
router.put('/:id/status', auth, updateOrderStatus);
router.put('/:id/move', auth, moveOrder); // stolni ko'chirish / birlashtirish
router.put('/:id/move-items', auth, moveOrderItems); // QISMAN ko'chirish (tanlangan taomlar/miqdor)
router.put('/:id/reopen', auth, reopenOrder); // to'langan zakazni qayta ochish (to'lovni tuzatish)
router.post('/:id/bill', auth, printBill); // hisob/chek chiqarish (bill_requested)
router.delete('/:orderId/items/:itemId', auth, cancelOrderItem); // bitta taomni bekor qilish
router.delete('/:id', auth, deleteOrder); // butun zakazni o'chirish

module.exports = router;
