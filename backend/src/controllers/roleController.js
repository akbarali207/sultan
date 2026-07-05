const pool = require('../config/db');

// Barcha lavozimlar (rollar)
const getRoles = async (req, res) => {
  try {
    const result = await pool.query(`SELECT id, name FROM roles ORDER BY id`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi lavozim qo'shish (masalan: elektrik, oshxona yordamchisi)
const createRole = async (req, res) => {
  try {
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Lavozim nomi kiritilmadi!' });
    }
    const clean = name.trim().toLowerCase();
    // Mavjud bo'lsa o'shani qaytaramiz (takror yaratmaymiz)
    const exists = await pool.query(`SELECT id, name FROM roles WHERE name = $1`, [clean]);
    if (exists.rows.length > 0) {
      return res.status(200).json(exists.rows[0]);
    }
    const result = await pool.query(
      `INSERT INTO roles (name) VALUES ($1) RETURNING id, name`,
      [clean]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { getRoles, createRole };
