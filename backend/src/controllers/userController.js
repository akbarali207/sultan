const bcrypt = require('bcryptjs');
const pool = require('../config/db');

// Rol tayinlash huquqi:
//  - 'guest' (yashirin egasi) — FAQAT guest o'zi bera/tahrirlay oladi (maxfiy egani himoya).
//  - 'director' — guest YOKI director bera oladi (direktor to'liq boshqaruvga ega).
//  - boshqa rollar (admin/cashier/waiter) — panelга kirgan har qanday menejer (route allaqachon cheklaydi).
const canAssignRole = (callerRole, targetRole) => {
  if (targetRole === 'guest') return callerRole === 'guest';
  if (targetRole === 'director') return callerRole === 'guest' || callerRole === 'director';
  return true;
};

// Barcha xodimlar
const getUsers = async (req, res) => {
  try {
    // guest (yashirin egasi akkaunti) faqat guestning o'ziga ko'rinadi — boshqa hammadan yashirin
    const hideGuest = req.user && req.user.role !== 'guest';
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.phone, u.salary_type, u.salary_value,
              u.is_active, u.face_id, r.name as role_name,
              to_char(u.work_start, 'HH24:MI') as work_start,
              to_char(u.work_end, 'HH24:MI') as work_end,
              u.late_fine_per_minute, COALESCE(u.salary_day, 1) as salary_day,
              COALESCE(u.salary_period_days, 30) as salary_period_days,
              COALESCE(u.salary_tier_threshold, 0) as salary_tier_threshold,
              COALESCE(u.salary_tier_value, 0) as salary_tier_value
       FROM users u
       JOIN roles r ON u.role_id = r.id
       ${hideGuest ? "WHERE r.name <> 'guest'" : ''}
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
            work_start, work_end, late_fine_per_minute, salary_day, salary_period_days,
            salary_tier_threshold, salary_tier_value } = req.body;
    const tth = (salary_tier_threshold !== undefined && salary_tier_threshold !== null && salary_tier_threshold !== '') ? salary_tier_threshold : null;
    const ttv = (salary_tier_value !== undefined && salary_tier_value !== null && salary_tier_value !== '') ? salary_tier_value : null;

    // Rol nazorati: guest'ni faqat guest, director'ni guest yoki director tayinlaydi
    const targetRole = await pool.query(`SELECT name FROM roles WHERE id=$1`, [role_id]);
    const targetRoleName = targetRole.rows[0] && targetRole.rows[0].name;
    if (!canAssignRole(req.user && req.user.role, targetRoleName)) {
      return res.status(403).json({ message: 'Bu rolni tayinlash uchun ruxsat yo\'q!' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await pool.query(
      `INSERT INTO users (full_name, phone, password, role_id, face_id, salary_type, salary_value,
                          work_start, work_end, late_fine_per_minute, salary_day, salary_period_days,
                          salary_tier_threshold, salary_tier_value)
       VALUES ($1, $2, $3, $4, $5, $6, $7,
               COALESCE($8::time, '09:00'), COALESCE($9::time, '22:00'), COALESCE($10, 0), COALESCE($11, 1), COALESCE($12, 30),
               $13, $14) RETURNING *`,
      [full_name, phone, hashedPassword, role_id, face_id, salary_type, salary_value,
       work_start || null, work_end || null, late_fine_per_minute || null, salary_day || null, salary_period_days || null,
       tth, ttv]
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
            work_start, work_end, late_fine_per_minute, salary_day, salary_period_days,
            salary_tier_threshold, salary_tier_value } = req.body;

    const isGuestCaller = req.user && req.user.role === 'guest';

    // Tahrirlanayotgan xodimning JORIY roli — guest (egasi) akkauntini himoyalash
    const currentRole = await pool.query(
      `SELECT r.name FROM users u JOIN roles r ON u.role_id = r.id WHERE u.id=$1`, [id]
    );
    const currentRoleName = currentRole.rows[0] && currentRole.rows[0].name;
    if (currentRoleName === 'guest' && !isGuestCaller) {
      return res.status(403).json({ message: 'Bu xodimni tahrirlash uchun ruxsat yo\'q!' });
    }

    // Yangi rol tayinlanayotgan bo'lsa: guest'ni faqat guest, director'ni guest yoki director
    if (role_id !== undefined && role_id !== null) {
      const targetRole = await pool.query(`SELECT name FROM roles WHERE id=$1`, [role_id]);
      const targetRoleName = targetRole.rows[0] && targetRole.rows[0].name;
      if (!canAssignRole(req.user && req.user.role, targetRoleName)) {
        return res.status(403).json({ message: 'Bu rolni tayinlash uchun ruxsat yo\'q!' });
      }
    }

    // is_active undefined kelsa mavjud qiymat saqlanadi (COALESCE orqali)
    const activeVal = is_active !== undefined ? is_active : null;
    const ws = work_start || null;
    const we = work_end || null;
    const lfpm = late_fine_per_minute !== undefined ? late_fine_per_minute : null;
    const sday = (salary_day !== undefined && salary_day !== null && salary_day !== '') ? salary_day : null;
    const speriod = (salary_period_days !== undefined && salary_period_days !== null && salary_period_days !== '') ? salary_period_days : null;
    // Progressiv foiz: null -> eski qiymat saqlanadi (COALESCE); 0 -> o'chirish (switch >0 tekshiradi).
    const tth = (salary_tier_threshold !== undefined && salary_tier_threshold !== null && salary_tier_threshold !== '') ? salary_tier_threshold : null;
    const ttv = (salary_tier_value !== undefined && salary_tier_value !== null && salary_tier_value !== '') ? salary_tier_value : null;

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
                   salary_tier_threshold=COALESCE($15, salary_tier_threshold),
                   salary_tier_value=COALESCE($16, salary_tier_value),
                   password=$11
               WHERE id=$12 RETURNING *`;
      params = [full_name, phone, role_id, face_id, salary_type, salary_value, activeVal, ws, we, lfpm, hashedPassword, id, sday, speriod, tth, ttv];
    } else {
      query = `UPDATE users
               SET full_name=$1, phone=$2, role_id=$3, face_id=$4,
                   salary_type=$5, salary_value=$6,
                   is_active=COALESCE($7, is_active),
                   work_start=COALESCE($8::time, work_start),
                   work_end=COALESCE($9::time, work_end),
                   late_fine_per_minute=COALESCE($10, late_fine_per_minute),
                   salary_day=COALESCE($12, salary_day),
                   salary_period_days=COALESCE($13, salary_period_days),
                   salary_tier_threshold=COALESCE($14, salary_tier_threshold),
                   salary_tier_value=COALESCE($15, salary_tier_value)
               WHERE id=$11 RETURNING *`;
      params = [full_name, phone, role_id, face_id, salary_type, salary_value, activeVal, ws, we, lfpm, id, sday, speriod, tth, ttv];
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

    // guest (egasi) akkauntini o'chirishdan himoyalash — faqat guest o'zi qila oladi
    const currentRole = await pool.query(
      `SELECT r.name FROM users u JOIN roles r ON u.role_id = r.id WHERE u.id=$1`, [id]
    );
    const currentRoleName = currentRole.rows[0] && currentRole.rows[0].name;
    if (currentRoleName === 'guest' && !(req.user && req.user.role === 'guest')) {
      return res.status(403).json({ message: 'Bu xodimni o\'chirish uchun ruxsat yo\'q!' });
    }

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
       WHERE (a.check_in - INTERVAL '150 minutes')::date = $1
       ORDER BY a.check_in DESC`,
      [filterDate]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { getUsers, createUser, updateUser, deleteUser, getAttendance };