const pool = require('../config/db');

// Harajat turlari
const getExpenseTypes = async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM expense_types ORDER BY name`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const createExpenseType = async (req, res) => {
  try {
    const name = (req.body.name || '').toString().trim();
    if (!name) return res.status(400).json({ message: 'Nom kerak' });
    const result = await pool.query(
      `INSERT INTO expense_types (name) VALUES ($1) RETURNING *`,
      [name]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(400).json({ message: 'Bu tur allaqachon mavjud' });
    res.status(500).json({ message: err.message });
  }
};

// Tur nomini o'zgartirish
const updateExpenseType = async (req, res) => {
  try {
    const { id } = req.params;
    const name = (req.body.name || '').toString().trim();
    if (!name) return res.status(400).json({ message: 'Nom kerak' });
    const result = await pool.query(
      `UPDATE expense_types SET name = $1 WHERE id = $2 RETURNING *`,
      [name, id]
    );
    if (!result.rows.length) return res.status(404).json({ message: 'Tur topilmadi' });
    res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(400).json({ message: 'Bu tur allaqachon mavjud' });
    res.status(500).json({ message: err.message });
  }
};

// Turni o'chirish — unga oid harajatlar bo'lsa bloklanadi
const deleteExpenseType = async (req, res) => {
  try {
    const { id } = req.params;
    const used = await pool.query(`SELECT COUNT(*)::int AS c FROM expenses WHERE expense_type_id = $1`, [id]);
    if (used.rows[0].c > 0) {
      return res.status(400).json({
        message: `Bu turga oid ${used.rows[0].c} ta harajat bor. Avval ularni o'chiring yoki boshqa turga o'tkazing.`,
      });
    }
    await pool.query(`DELETE FROM expense_types WHERE id = $1`, [id]);
    res.json({ deleted: true, message: 'Tur o\'chirildi' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Harajatlar
// ?period=today|week|month  yoki  ?date=YYYY-MM-DD (eski xulq)
const getExpenses = async (req, res) => {
  try {
    const { date, period } = req.query;
    let whereClause;
    const params = [];
    if (period === 'week') {
      whereClause = `e.created_at >= CURRENT_DATE - INTERVAL '6 days'`;
    } else if (period === 'month') {
      whereClause = `e.created_at >= date_trunc('month', CURRENT_DATE)`;
    } else {
      params.push(date || new Date().toISOString().split('T')[0]);
      whereClause = `DATE(e.created_at) = $1`;
    }
    const result = await pool.query(
      `SELECT e.*, et.name as type_name
       FROM expenses e
       JOIN expense_types et ON e.expense_type_id = et.id
       WHERE ${whereClause}
       ORDER BY e.created_at DESC`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const createExpense = async (req, res) => {
  const client = await pool.connect();
  try {
    const { expense_type_id, name, amount, quantity, unit } = req.body;
    const amt = parseFloat(amount);
    if (!expense_type_id || !name || !(amt > 0)) {
      return res.status(400).json({ message: 'Tur, nom va musbat summa kerak' });
    }
    const method = req.body.method === 'card' ? 'card' : 'cash';
    // Pul manbasi: Kassadan (default) yoki boshqa joydan. Boshqa bo'lsa Kassadan yechilmaydi.
    const fromKassa = req.body.from_kassa !== false && req.body.from_kassa !== 'false';
    const sourceText = fromKassa ? 'kassa' : ((req.body.source || '').toString().trim().slice(0, 120) || 'boshqa');

    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO expenses (expense_type_id, name, amount, quantity, unit, method, source)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [expense_type_id, name, amt, quantity, unit, method, sourceText]
    );
    const exp = result.rows[0];
    // Faqat Kassadan to'langanda Kassa balansidan chiqim qilamiz
    if (fromKassa) {
      await client.query(
        `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
         VALUES ('expense', $1, $2, 'expense', $3, $4)`,
        [method, amt, exp.id, name]
      );
    }
    await client.query('COMMIT');
    res.status(201).json(exp);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Barcha Kassadan ketgan summalar (xarajat + oylik/avans + sklad kirim + qo'lda chiqim) + Kassadan tashqari xarajatlar
const getOutflows = async (req, res) => {
  try {
    const period = req.query.period || 'today';
    const w = (col) =>
      period === 'week' ? `${col} >= CURRENT_DATE - INTERVAL '6 days'`
        : period === 'month' ? `${col} >= date_trunc('month', CURRENT_DATE)`
          : `DATE(${col}) = CURRENT_DATE`;

    const [kassa, other, kassaAgg] = await Promise.all([
      pool.query(
        `SELECT ct.id AS ct_id, ct.source, ct.method, ct.amount, ct.note, ct.created_at,
                et.name AS expense_type, e.id AS expense_id, e.quantity, e.unit,
                su.full_name AS staff_name
         FROM cash_transactions ct
         LEFT JOIN expenses e ON ct.source='expense' AND ct.ref_id = e.id
         LEFT JOIN expense_types et ON e.expense_type_id = et.id
         LEFT JOIN salary_payments sp ON ct.source IN ('salary','advance') AND ct.ref_id = sp.id
         LEFT JOIN users su ON sp.user_id = su.id
         WHERE ct.kind='expense' AND ${w('ct.created_at')}
         ORDER BY ct.created_at DESC LIMIT 300`
      ),
      pool.query(
        `SELECT e.id AS expense_id, e.name, e.amount, e.method, e.quantity, e.unit, e.created_at, et.name AS expense_type
         FROM expenses e JOIN expense_types et ON e.expense_type_id = et.id
         WHERE e.source <> 'kassa' AND ${w('e.created_at')}
         ORDER BY e.created_at DESC`
      ),
      // JAMI kassa chiqimi — AGREGAT (ro'yxat LIMIT 300 bilan kesiladi, summa to'liq bo'lsin)
      pool.query(
        `SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions
         WHERE kind='expense' AND ${w('created_at')}`
      ),
    ]);

    const CAT = { salary: 'Oylik', advance: 'Avans', stock: 'Sklad', manual: "Qo'lda" };
    const items = [];
    let totalOther = 0;
    const totalKassa = parseFloat(kassaAgg.rows[0].total); // to'liq summa (kesilmagan)

    for (const r of kassa.rows) {
      const amount = parseFloat(r.amount);
      let typeName, name;
      if (r.source === 'expense') { typeName = r.expense_type || 'Boshqa'; name = r.note || ''; }
      else if (r.source === 'salary' || r.source === 'advance') { typeName = CAT[r.source]; name = r.staff_name || r.note || ''; }
      else if (r.source === 'stock') { typeName = 'Sklad'; name = r.note || ''; }
      else { typeName = "Qo'lda"; name = r.note || ''; }
      items.push({
        type_name: typeName, name, amount, method: r.method, created_at: r.created_at,
        quantity: r.quantity, unit: r.unit, source: r.source, from_kassa: true,
        can_delete: r.source === 'expense', delete_id: r.source === 'expense' ? r.expense_id : null,
      });
    }
    for (const r of other.rows) {
      const amount = parseFloat(r.amount);
      totalOther += amount;
      items.push({
        type_name: r.expense_type || 'Boshqa', name: r.name || '', amount, method: r.method, created_at: r.created_at,
        quantity: r.quantity, unit: r.unit, source: 'expense', from_kassa: false,
        can_delete: true, delete_id: r.expense_id,
      });
    }
    items.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json({ period, items, total_kassa: totalKassa, total_other: totalOther });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const deleteExpense = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    await client.query('BEGIN');
    await client.query(`DELETE FROM cash_transactions WHERE source = 'expense' AND ref_id = $1`, [id]);
    await client.query(`DELETE FROM expenses WHERE id = $1`, [id]);
    await client.query('COMMIT');
    res.json({ message: 'Harajat o\'chirildi!' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

module.exports = { getExpenseTypes, createExpenseType, updateExpenseType, deleteExpenseType, getExpenses, getOutflows, createExpense, deleteExpense };