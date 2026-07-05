const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const { getRoles, createRole } = require('../controllers/roleController');

router.get('/', authMiddleware, getRoles);          // o'qish — login qilgan har kim
router.post('/', authMiddleware, adminOnly, createRole); // qo'shish — faqat admin

module.exports = router;
