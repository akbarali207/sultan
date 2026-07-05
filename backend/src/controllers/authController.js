const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const { recordFaceAttendance } = require('../services/attendanceService');

const login = async (req, res) => {
  try {
    // DIQQAT: bu yerga req.body (parol!) hech qachon loglanmasin
    const { phone, password } = req.body;
    const result = await pool.query(
      `SELECT u.*, r.name as role_name FROM users u JOIN roles r ON u.role_id = r.id WHERE u.phone = $1 AND u.is_active = true`,
      [phone]
    );
    if (result.rows.length === 0) {
      return res.status(401).json({ message: 'Telefon raqam yoki parol xato!' });
    }
    const user = result.rows[0];
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Telefon raqam yoki parol xato!' });
    }
    const token = jwt.sign(
      { id: user.id, role: user.role_name },
      process.env.JWT_SECRET,
      { expiresIn: '24h' }
    );
    res.json({ token, user: { id: user.id, full_name: user.full_name, role: user.role_name } });
  } catch (err) {
    console.log('Login xatosi:', err.message);
    res.status(500).json({ message: err.message });
  }
};

// Joriy foydalanuvchi parolini tekshirish (Kassa kabi himoyalangan bo'limlar uchun)
const verifyPassword = async (req, res) => {
  try {
    const password = (req.body && req.body.password) || '';
    if (!password || !req.user || !req.user.id) return res.json({ ok: false });
    const r = await pool.query('SELECT password FROM users WHERE id = $1 AND is_active = true', [req.user.id]);
    if (!r.rows.length) return res.json({ ok: false });
    const ok = await bcrypt.compare(password, r.rows[0].password);
    res.json({ ok });
  } catch (err) {
    res.status(500).json({ ok: false, message: err.message });
  }
};

const faceCheckIn = async (req, res) => {
  try {
    const { face_id } = req.body;
    const r = await recordFaceAttendance(face_id);
    return res.status(r.status).json({ message: r.message, type: r.type });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { login, faceCheckIn, verifyPassword };