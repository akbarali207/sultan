const pool = require('../config/db');

// Barcha bo'limlar (printerlar)
const getStations = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM print_stations WHERE is_active = true ORDER BY id`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi bo'lim
const createStation = async (req, res) => {
  try {
    const { name, printer_ip, printer_port, printer_name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Bo\'lim nomi kiritilmadi!' });
    }
    const result = await pool.query(
      `INSERT INTO print_stations (name, printer_ip, printer_port, printer_name)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [name.trim(), printer_ip || null, printer_port || 9100, printer_name || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Bo'limni tahrirlash (nomi, printer IP/port)
const updateStation = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, printer_ip, printer_port, printer_name, is_active } = req.body;
    const result = await pool.query(
      `UPDATE print_stations
       SET name = COALESCE($1, name),
           printer_ip = $2,
           printer_port = COALESCE($3, printer_port),
           printer_name = $4,
           is_active = COALESCE($5, is_active)
       WHERE id = $6 RETURNING *`,
      [name, printer_ip !== undefined ? printer_ip : null, printer_port,
       printer_name !== undefined ? printer_name : null, is_active, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Bo\'lim topilmadi' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Bo'limni o'chirish (soft delete)
const deleteStation = async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query(`UPDATE print_stations SET is_active = false WHERE id = $1`, [id]);
    res.json({ message: 'Bo\'lim o\'chirildi' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { getStations, createStation, updateStation, deleteStation };
