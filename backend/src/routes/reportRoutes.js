const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const blockIfFrozen = require('../middleware/freezeGuard'); // STOP — pul amallarini bloklaydi
// director (nazorat) va guest (super-admin) ham barcha hisobot/analitikani ko'radi
const adminOnly = requireRole('admin', 'director', 'guest');
const adminOrCashier = requireRole('admin', 'cashier', 'director', 'guest');
// Analitika (foyda/qarz drill-down) — egasi 2026-07-11: admin ham to'liq ko'radi
const directorOnly = requireRole('admin', 'director', 'guest');
const { getDailyReport, getStockReport, getAttendanceReport, getDashboard, getPayroll,
        getDailyStock, setDailyStock,
        addSalaryPayment, listSalaryPayments, deleteSalaryPayment,
        addSalaryFine, listSalaryFines, deleteSalaryFine,
        addSalaryBonus, listSalaryBonuses, deleteSalaryBonus,
        setLateFineOverride, deleteLateFineOverride,
        setManualShifts, deleteManualShifts, getManualShifts,
        getCashbox, addCashTransaction, setOpeningBalance, deleteCashTransaction, payDebt,
        getReport, getAnalytics,
        getDishDetail, getPieceRates, setPieceRates } = require('../controllers/reportController');
const { closeDay, listDayCloses, approveDayClose } = require('../controllers/dayCloseController');

router.get('/dashboard', authMiddleware, adminOnly, getDashboard);
router.get('/daily-stock', authMiddleware, adminOnly, getDailyStock);   // kunlik kuzat: sotildi/qoldi
router.post('/daily-stock', authMiddleware, adminOnly, setDailyStock);  // ertalabki son
router.get('/daily', authMiddleware, adminOnly, getDailyReport);
router.get('/stock', authMiddleware, adminOnly, getStockReport);
router.get('/attendance', authMiddleware, adminOnly, getAttendanceReport);
router.get('/summary', authMiddleware, adminOnly, getReport);
router.get('/analytics', authMiddleware, directorOnly, getAnalytics); // analitika — faqat direktor/guest
router.get('/dish/:id', authMiddleware, directorOnly, getDishDetail); // bitta blyudo drill-down
router.get('/payroll', authMiddleware, adminOnly, getPayroll);
router.get('/piece-rates', authMiddleware, adminOnly, getPieceRates);  // sdelnaya stavkalar
router.post('/piece-rates', authMiddleware, adminOnly, setPieceRates);
router.get('/salary-payments', authMiddleware, adminOnly, listSalaryPayments);
router.post('/salary-payments', authMiddleware, adminOnly, blockIfFrozen, addSalaryPayment);
router.delete('/salary-payments/:id', authMiddleware, adminOnly, deleteSalaryPayment);
router.get('/salary-fines', authMiddleware, adminOnly, listSalaryFines);
router.post('/salary-fines', authMiddleware, adminOnly, addSalaryFine);
router.delete('/salary-fines/:id', authMiddleware, adminOnly, deleteSalaryFine);
router.get('/salary-bonuses', authMiddleware, adminOnly, listSalaryBonuses);
router.post('/salary-bonuses', authMiddleware, adminOnly, addSalaryBonus);
router.delete('/salary-bonuses/:id', authMiddleware, adminOnly, deleteSalaryBonus);
router.post('/late-fine-override', authMiddleware, adminOnly, setLateFineOverride);
router.delete('/late-fine-override', authMiddleware, adminOnly, deleteLateFineOverride);
router.get('/manual-shifts', authMiddleware, adminOnly, getManualShifts);      // смещик qo'lда smenalari
router.post('/manual-shifts', authMiddleware, adminOnly, setManualShifts);
router.delete('/manual-shifts', authMiddleware, adminOnly, deleteManualShifts);

// Kassa (admin + kassir)
router.get('/cashbox', authMiddleware, adminOrCashier, getCashbox);
router.post('/cashbox', authMiddleware, adminOrCashier, blockIfFrozen, addCashTransaction);
router.post('/cashbox/open', authMiddleware, adminOrCashier, blockIfFrozen, setOpeningBalance); // kassa ochilish qoldig'i
router.delete('/cashbox/:id', authMiddleware, adminOrCashier, deleteCashTransaction);
router.post('/debts/:id/pay', authMiddleware, adminOrCashier, blockIfFrozen, payDebt);

// Kun yakunlash (Z-hisobot) + kech yopishni direktor tasdiqlashi
router.post('/close-day', authMiddleware, adminOrCashier, closeDay);        // kassir kunni yopadi
router.get('/day-closes', authMiddleware, adminOnly, listDayCloses);        // ?status=pending
router.post('/day-closes/:id/approve', authMiddleware, adminOnly, approveDayClose);

module.exports = router;
