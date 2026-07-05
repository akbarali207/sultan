const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { login, faceCheckIn, verifyPassword } = require('../controllers/authController');

router.post('/login', login);
router.post('/face-checkin', faceCheckIn);
router.post('/verify-password', authMiddleware, verifyPassword);

module.exports = router;