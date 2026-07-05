const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const {
  getUsers,
  createUser,
  updateUser,
  deleteUser,
  getAttendance
} = require('../controllers/userController');

router.get('/', authMiddleware, adminOnly, getUsers);
router.post('/', authMiddleware, adminOnly, createUser);
router.put('/:id', authMiddleware, adminOnly, updateUser);
router.delete('/:id', authMiddleware, adminOnly, deleteUser);
router.get('/attendance', authMiddleware, adminOnly, getAttendance);

module.exports = router;