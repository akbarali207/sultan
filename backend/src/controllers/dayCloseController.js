const pool = require('../config/db');

const isManager = (role) => ['director', 'admin', 'guest'].includes(role);
async function userName(id) {
  if (!id) return null;
  const r = await pool.query('SELECT full_name FROM users WHERE id = $1', [id]);
  return r.rows.length ? r.rows[0].full_name : null;
}

// Bitta biznes-kun uchun savdo/kassaga-tushgan/harajat snapshot
async function daySnapshot(bizDate) {
  const s = await pool.query(
    `SELECT COALESCE(SUM(COALESCE(final_amount, total_amount)), 0) AS sales,
            COALESCE(SUM(paid_card), 0) + COALESCE(SUM(paid_cash), 0)
              + COALESCE(SUM(CASE WHEN (COALESCE(paid_card,0)+COALESCE(paid_cash,0)+COALESCE(paid_debt,0)) = 0
                                  THEN COALESCE(final_amount, total_amount) ELSE 0 END), 0) AS received
     FROM orders
     WHERE status = 'paid' AND (created_at - INTERVAL '150 minutes')::date = $1`,
    [bizDate]
  );
  const e = await pool.query(
    `SELECT (SELECT COALESCE(SUM(amount),0) FROM cash_transactions
              WHERE kind='expense' AND (created_at - INTERVAL '150 minutes')::date = $1)
          + (SELECT COALESCE(SUM(amount),0) FROM expenses
              WHERE source <> 'kassa' AND (created_at - INTERVAL '150 minutes')::date = $1) AS expenses`,
    [bizDate]
  );
  const sales = parseFloat(s.rows[0].sales);
  const received = parseFloat(s.rows[0].received);
  const expenses = parseFloat(e.rows[0].expenses);
  return { sales, received, expenses, profit: sales - expenses };
}

// Kunni yopish. body: { biz_date?, note? }
const closeDay = async (req, res) => {
  try {
    const role = req.user && req.user.role;
    const reqDate = (typeof req.body.biz_date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(req.body.biz_date))
      ? req.body.biz_date : null;
    // biz_date (default = joriy biznes-kun) va kech-yopish (o'tgan kun) — SQL da
    const meta = await pool.query(
      `SELECT COALESCE($1::date, (NOW() - INTERVAL '150 minutes')::date) AS biz_date,
              COALESCE($1::date, (NOW() - INTERVAL '150 minutes')::date) < (NOW() - INTERVAL '150 minutes')::date AS is_late,
              to_char(COALESCE($1::date, (NOW() - INTERVAL '150 minutes')::date), 'YYYY-MM-DD') AS biz_date_str`,
      [reqDate]
    );
    const bizDate = meta.rows[0].biz_date;
    const isLate = meta.rows[0].is_late === true;
    const bizDateStr = meta.rows[0].biz_date_str;

    // Kelajakdagi kunni yopib bo'lmaydi (biz_date joriy biznes-kundan katta bo'lsa).
    const fut = await pool.query(`SELECT $1::date > (NOW() - INTERVAL '150 minutes')::date AS future`, [bizDate]);
    if (fut.rows[0].future === true) {
      return res.status(400).json({ message: 'Kelajakdagi kunni yopib bo\'lmaydi' });
    }

    const ex = await pool.query('SELECT id, status FROM day_close WHERE biz_date = $1', [bizDate]);
    if (ex.rows.length) {
      // RAD ETILGAN yopishni qayta yopish mumkin (aks holда kun abadiy tupikда qolardi).
      if (ex.rows[0].status === 'rejected') {
        await pool.query('DELETE FROM day_close WHERE id = $1', [ex.rows[0].id]);
      } else {
        return res.status(409).json({ message: 'Bu kun allaqachon yopilgan yoki yuborilgan', status: ex.rows[0].status });
      }
    }

    const snap = await daySnapshot(bizDate);
    const mgr = isManager(role);
    // O'z vaqtida -> closed. Kech + kassir -> pending (direktor tasdig'i). Kech + menejer -> approved.
    const status = isLate ? (mgr ? 'approved' : 'pending') : 'closed';
    const uname = await userName(req.user && req.user.id);
    // approved_at ni JS da hisoblaymiz — $2 ni SQL da ikki marta ishlatmaslik uchun
    // (aks holda PG "inconsistent types for parameter $2" 500 beradi).
    const approvedAt = (status === 'closed' || status === 'approved') ? new Date() : null;

    const ins = await pool.query(
      `INSERT INTO day_close
         (biz_date, status, sales, received, expenses, profit, is_late, closed_by, closed_by_name, note,
          approved_by, approved_by_name, approved_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       RETURNING id`,
      [bizDate, status, snap.sales, snap.received, snap.expenses, snap.profit, isLate,
       req.user && req.user.id, uname, req.body.note || null,
       (mgr && isLate) ? (req.user && req.user.id) : null, (mgr && isLate) ? uname : null,
       approvedAt]
    );
    res.json({ ok: true, id: ins.rows[0].id, biz_date: bizDateStr, status, is_late: isLate, snapshot: snap });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yopishlar ro'yxati. ?status=pending — direktor tasdig'i kutayotganlar
const listDayCloses = async (req, res) => {
  try {
    const params = [];
    let where = '';
    if (typeof req.query.status === 'string' && req.query.status) {
      params.push(req.query.status);
      where = 'WHERE status = $1';
    }
    const r = await pool.query(
      `SELECT id, to_char(biz_date,'YYYY-MM-DD') AS biz_date, status, sales, received, expenses, profit,
              is_late, closed_by_name, to_char(closed_at,'YYYY-MM-DD HH24:MI') AS closed_at,
              approved_by_name, note
       FROM day_close ${where} ORDER BY biz_date DESC LIMIT 60`,
      params
    );
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Kech yopishni tasdiqlash/rad etish — FAQAT director/admin/super-admin
const approveDayClose = async (req, res) => {
  const role = req.user && req.user.role;
  if (!isManager(role)) return res.status(403).json({ message: 'Faqat director yoki admin tasdiqlaydi' });
  try {
    const { id } = req.params;
    const approve = req.body.approve !== false && req.body.approve !== 'false';
    const uname = await userName(req.user && req.user.id);
    const r = await pool.query(
      `UPDATE day_close SET status = $1, approved_by = $2, approved_by_name = $3, approved_at = NOW()
       WHERE id = $4 AND status = 'pending' RETURNING id, status`,
      [approve ? 'approved' : 'rejected', req.user && req.user.id, uname, id]
    );
    if (!r.rows.length) return res.status(404).json({ message: 'Kutilayotgan yopish topilmadi' });
    res.json({ ok: true, status: r.rows[0].status });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

module.exports = { closeDay, listDayCloses, approveDayClose };
