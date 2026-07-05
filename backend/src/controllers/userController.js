const bcrypt = require('bcryptjs');
const pool = require('../config/db');

// Barcha xodimlar
const getUsers = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.phone, u.salary_type, u.salary_value,
              u.is_active, u.face_id, r.name as role_name,
              to_char(u.work_start, 'HH24:MI') as work_start,
              to_char(u.work_end, 'HH24:MI') as work_end,
              u.late_fine_per_minute, COALESCE(u.salary_day, 1) as salary_day,
              COALESCE(u.salary_period_days, 30) as salary_period_days
       FROM users u
       JOIN roles r ON u.role_id = r.id
       ORDER BY u.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Xodim qo'shish
const createUser = async (req, res) => {
  try {
    const { full_name, phone, password, role_id, face_id, salary_type, salary_value,
            work_start, work_end, late_fine_per_minute, salary_day, salary_period_days } = req.body;
    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await pool.query(
      `INSERT INTO users (full_name, phone, password, role_id, face_id, salary_type, salary_value,
                          work_start, work_end, late_fine_per_minute, salary_day, salary_period_days)
       VALUES ($1, $2, $3, $4, $5, $6, $7,
               COALESCE($8::time, '09:00'), COALESCE($9::time, '22:00'), COALESCE($10, 0), COALESCE($11, 1), COALESCE($12, 30)) RETURNING *`,
      [full_name, phone, hashedPassword, role_id, face_id, salary_type, salary_value,
       work_start || null, work_end || null, late_fine_per_minute || null, salary_day || null, salary_period_days || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Xodim yangilash
const updateUser = async (req, res) => {
  try {
    const { id } = req.params;
    const { full_name, phone, role_id, face_id, salary_type, salary_value, is_active, password,
            work_start, work_end, late_fine_per_minute, salary_day, salary_period_days } = req.body;

    // is_active undefined kelsa mavjud qiymat saqlanadi (COALESCE orqali)
    const activeVal = is_active !== undefined ? is_active : null;
    const ws = work_start || null;
    const we = work_end || null;
    const lfpm = late_fine_per_minute !== undefined ? late_fine_per_minute : null;
    const sday = (salary_day !== undefined && salary_day !== null && salary_day !== '') ? salary_day : null;
    const speriod = (salary_period_days !== undefined && salary_period_days !== null && salary_period_days !== '') ? salary_period_days : null;

    let query, params;
    if (password && password.trim().length > 0) {
      const hashedPassword = await bcrypt.hash(password.trim(), 10);
      query = `UPDATE users
               SET full_name=$1, phone=$2, role_id=$3, face_id=$4,
                   salary_type=$5, salary_value=$6,
                   is_active=COALESCE($7, is_active),
                   work_start=COALESCE($8::time, work_start),
                   work_end=COALESCE($9::time, work_end),
                   late_fine_per_minute=COALESCE($10, late_fine_per_minute),
                   salary_day=COALESCE($13, salary_day),
                   salary_period_days=COALESCE($14, salary_period_days),
                   password=$11
               WHERE id=$12 RETURNING *`;
      params = [full_name, phone, role_id, face_id, salary_type, salary_value, activeVal, ws, we, lfpm, hashedPassword, id, sday, speriod];
    } else {
      query = `UPDATE users
               SET full_name=$1, phone=$2, role_id=$3, face_id=$4,
                   salary_type=$5, salary_value=$6,
                   is_active=COALESCE($7, is_active),
                   work_start=COALESCE($8::time, work_start),
                   work_end=COALESCE($9::time, work_end),
                   late_fine_per_minute=COALESCE($10, late_fine_per_minute),
                   salary_day=COALESCE($12, salary_day),
                   salary_period_days=COALESCE($13, salary_period_days)
               WHERE id=$11 RETURNING *`;
      params = [full_name, phone, role_id, face_id, salary_type, salary_value, activeVal, ws, we, lfpm, id, sday, speriod];
    }

    const result = await pool.query(query, params);
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Xodim o'chirish
const deleteUser = async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query(`UPDATE users SET is_active = false WHERE id = $1`, [id]);
    res.json({ message: 'Xodim o\'chirildi!' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Davomat ko'rish
const getAttendance = async (req, res) => {
  try {
    const { date } = req.query;
    const filterDate = date || new Date().toISOString().split('T')[0];
    const result = await pool.query(
      `SELECT a.*, u.full_name, r.name as role_name
       FROM attendance a
       JOIN users u ON a.user_id = u.id
       JOIN roles r ON u.role_id = r.id
       WHERE DATE(a.check_in) = $1
       ORDER BY a.check_in DESC`,
      [filterDate]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { getUsers, createUser, updateUser, deleteUser, getAttendance };