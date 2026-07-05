const pool = require('../config/db');

// Idishlar katalogi (faol)
const getTableware = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM tableware WHERE is_active = true ORDER BY name`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi idish qo'shish
const createTableware = async (req, res) => {
  try {
    const { name, unit, quantity, price } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Idish nomi kiritilmadi!' });
    }
    const result = await pool.query(
      `INSERT INTO tableware (name, unit, quantity, price)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [name.trim(), unit || 'dona', quantity || 0, price || 0]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Idishni tahrirlash
const updateTableware = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, unit, quantity, price } = req.body;
    const result = await pool.query(
      `UPDATE tableware
       SET name = COALESCE($1, name),
           unit = COALESCE($2, unit),
           quantity = COALESCE($3, quantity),
           price = COALESCE($4, price)
       WHERE id = $5 RETURNING *`,
      [name, unit, quantity, price, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Idish topilmadi' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Idishni o'chirish (soft delete)
const deleteTableware = async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query(`UPDATE tableware SET is_active = false WHERE id = $1`, [id]);
    res.json({ message: 'Idish o\'chirildi' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { getTableware, createTableware, updateTableware, deleteTableware };
