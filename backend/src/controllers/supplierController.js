// ============================================================
// POSTAVSHIKLAR + MOLIYAVIY LEDGER (F13).
// Har postavshik uchun avtomatik hisob: zakupkalar, to'lovlar, qarz,
// vozvratlar, narx tarixi, chegirmalar, o'rtacha to'lov muddati,
// kechikkan to'lovlar, reyting — hammasi bir so'rovda.
// ============================================================
const pool = require('../config/db');
const { addSupplierPayment, getSetting } = require('../services/costingService');
const { logAudit } = require('../services/audit');

// Ro'yxat: har biriga tez jami (zakupka/to'langan/qarz)
const getSuppliers = async (req, res) => {
  try {
    const showAll = req.query.all === 'true';
    const r = await pool.query(
      `SELECT s.*,
              COALESCE(t.purchases, 0)  AS total_purchases,
              COALESCE(t.paid, 0)       AS total_paid,
              COALESCE(t.debt, 0)       AS total_debt,
              COALESCE(t.lot_count, 0)  AS lot_count
       FROM suppliers s
       LEFT JOIN (
         SELECT supplier_id,
                ROUND(SUM(total_cost), 2)               AS purchases,
                ROUND(SUM(paid_amount), 2)              AS paid,
                ROUND(SUM(total_cost - paid_amount), 2) AS debt,
                COUNT(*)                                AS lot_count
         FROM stock_lots WHERE supplier_id IS NOT NULL GROUP BY supplier_id
       ) t ON t.supplier_id = s.id
       ${showAll ? '' : 'WHERE s.is_active = true'}
       ORDER BY s.name`);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};

const createSupplier = async (req, res) => {
  try {
    const name = (req.body.name || '').toString().trim();
    if (!name) return res.status(400).json({ message: 'Postavshik nomi kerak' });
    const r = await pool.query(
      `INSERT INTO suppliers (name, phone, contact_person, address, note)
       VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [name, (req.body.phone || '').toString().trim() || null,
       (req.body.contact_person || '').toString().trim() || null,
       (req.body.address || '').toString().trim() || null,
       (req.body.note || '').toString().trim() || null]);
    await logAudit(pool, { req, action: 'supplier.create', entityType: 'supplier', entityId: r.rows[0].id, newValue: { name } });
    res.status(201).json(r.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(400).json({ message: 'Bunday nomli postavshik bor' });
    res.status(500).json({ message: err.message });
  }
};

const updateSupplier = async (req, res) => {
  try {
    const { id } = req.params;
    const cur = await pool.query('SELECT * FROM suppliers WHERE id = $1', [id]);
    if (!cur.rows.length) return res.status(404).json({ message: 'Topilmadi' });
    const old = cur.rows[0];
    const has = (v) => v !== undefined && v !== null;
    const name = has(req.body.name) && req.body.name.toString().trim() ? req.body.name.toString().trim() : old.name;
    const r = await pool.query(
      `UPDATE suppliers SET name=$1, phone=$2, contact_person=$3, address=$4, note=$5, is_active=$6
       WHERE id=$7 RETURNING *`,
      [name,
       has(req.body.phone) ? (req.body.phone.toString().trim() || null) : old.phone,
       has(req.body.contact_person) ? (req.body.contact_person.toString().trim() || null) : old.contact_person,
       has(req.body.address) ? (req.body.address.toString().trim() || null) : old.address,
       has(req.body.note) ? (req.body.note.toString().trim() || null) : old.note,
       has(req.body.is_active) ? (req.body.is_active === true || req.body.is_active === 'true') : old.is_active,
       id]);
    await logAudit(pool, {
      req, action: 'supplier.update', entityType: 'supplier', entityId: parseInt(id),
      oldValue: { name: old.name, phone: old.phone, is_active: old.is_active },
      newValue: { name: r.rows[0].name, phone: r.rows[0].phone, is_active: r.rows[0].is_active },
    });
    res.json(r.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(400).json({ message: 'Bunday nomli postavshik bor' });
    res.status(500).json({ message: err.message });
  }
};

// O'chirish: partiyalari bo'lsa arxivlanadi (tarix saqlanadi)
const deleteSupplier = async (req, res) => {
  try {
    const { id } = req.params;
    const used = await pool.query(
      `SELECT (SELECT COUNT(*) FROM stock_lots WHERE supplier_id=$1)::int
            + (SELECT COUNT(*) FROM supplier_payments WHERE supplier_id=$1)::int AS n`, [id]);
    if (used.rows[0].n > 0) {
      await pool.query(`UPDATE suppliers SET is_active = false WHERE id = $1`, [id]);
      await logAudit(pool, { req, action: 'supplier.archive', entityType: 'supplier', entityId: parseInt(id) });
      return res.json({ message: 'Postavshik arxivlandi (tarixi bor)' });
    }
    await pool.query(`DELETE FROM suppliers WHERE id = $1`, [id]);
    await logAudit(pool, { req, action: 'supplier.delete', entityType: 'supplier', entityId: parseInt(id) });
    res.json({ message: 'Postavshik o\'chirildi' });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// LEDGER — bir klikda to'liq hisob (F13).
const getSupplierLedger = async (req, res) => {
  try {
    const { id } = req.params;
    const sup = await pool.query('SELECT * FROM suppliers WHERE id = $1', [id]);
    if (!sup.rows.length) return res.status(404).json({ message: 'Postavshik topilmadi' });
    const overdueDays = parseInt(await getSetting(pool, 'supplier_overdue_days', '14'), 10) || 14;

    const totals = await pool.query(
      `SELECT COALESCE(ROUND(SUM(total_cost), 2), 0)               AS purchases,
              COALESCE(ROUND(SUM(paid_amount), 2), 0)              AS paid,
              COALESCE(ROUND(SUM(total_cost - paid_amount), 2), 0) AS debt,
              COALESCE(ROUND(SUM(discount_amount), 2), 0)          AS discounts,
              COUNT(*)::int                                        AS lot_count
       FROM stock_lots WHERE supplier_id = $1`, [id]);

    const lots = await pool.query(
      `SELECT l.*, i.name AS ingredient_name,
              ROUND(l.quantity - l.used_quantity, 3) AS remaining_quantity,
              ROUND(l.total_cost - l.paid_amount, 2) AS debt_amount
       FROM stock_lots l JOIN ingredients i ON l.ingredient_id = i.id
       WHERE l.supplier_id = $1 ORDER BY l.received_at DESC LIMIT 300`, [id]);

    const payments = await pool.query(
      `SELECT p.*, l.lot_code, l.invoice_no
       FROM supplier_payments p LEFT JOIN stock_lots l ON p.lot_id = l.id
       WHERE p.supplier_id = $1 ORDER BY p.created_at DESC LIMIT 300`, [id]);

    // Vozvrat tarixi
    const returns = await pool.query(
      `SELECT c.*, l.lot_code, i.name AS ingredient_name
       FROM lot_consumptions c
       JOIN stock_lots l ON c.lot_id = l.id
       JOIN ingredients i ON c.ingredient_id = i.id
       WHERE l.supplier_id = $1 AND c.reason = 'return' AND c.quantity > 0
       ORDER BY c.created_at DESC LIMIT 100`, [id]);

    // Narx o'zgarish tarixi: har tovar bo'yicha partiyalar narxi vaqt bo'yicha
    const priceHistory = await pool.query(
      `SELECT l.ingredient_id, i.name AS ingredient_name, l.received_at::date AS date,
              l.unit_cost, l.quantity, l.lot_code
       FROM stock_lots l JOIN ingredients i ON l.ingredient_id = i.id
       WHERE l.supplier_id = $1
       ORDER BY i.name, l.received_at`, [id]);

    // Chegirmalar tarixi
    const discounts = await pool.query(
      `SELECT l.lot_code, l.received_at::date AS date, i.name AS ingredient_name,
              l.discount_amount, l.total_cost
       FROM stock_lots l JOIN ingredients i ON l.ingredient_id = i.id
       WHERE l.supplier_id = $1 AND l.discount_amount > 0
       ORDER BY l.received_at DESC`, [id]);

    // O'rtacha to'lov muddati (kun): partiya kelishi -> to'lovlar (summaga vaznlangan)
    const avgPay = await pool.query(
      `SELECT ROUND(
                SUM(EXTRACT(EPOCH FROM (p.created_at - l.received_at)) / 86400.0 * p.amount)
                / NULLIF(SUM(p.amount), 0), 1) AS avg_days
       FROM supplier_payments p JOIN stock_lots l ON p.lot_id = l.id
       WHERE p.supplier_id = $1 AND p.kind = 'payment'`, [id]);

    // Kechikkan to'lovlar: qarzli va eski partiyalar
    const overdue = await pool.query(
      `SELECT l.id, l.lot_code, l.invoice_no, l.received_at::date AS date, i.name AS ingredient_name,
              ROUND(l.total_cost - l.paid_amount, 2) AS debt_amount,
              (CURRENT_DATE - l.received_at::date)::int AS age_days
       FROM stock_lots l JOIN ingredients i ON l.ingredient_id = i.id
       WHERE l.supplier_id = $1 AND (l.total_cost - l.paid_amount) > 0.005
         AND l.received_at < NOW() - ($2 || ' days')::interval
       ORDER BY l.received_at`, [id, overdueDays]);

    // REYTING (0-100): to'langanlik 60% + kechikmaganlik 30% + faollik 10%
    const t = totals.rows[0];
    const purchases = parseFloat(t.purchases) || 0;
    const paidShare = purchases > 0 ? parseFloat(t.paid) / purchases : 1;
    const overdueSum = overdue.rows.reduce((a, r) => a + parseFloat(r.debt_amount), 0);
    const overdueShare = purchases > 0 ? overdueSum / purchases : 0;
    const recent = await pool.query(
      `SELECT COUNT(*)::int n FROM stock_lots WHERE supplier_id = $1 AND received_at > NOW() - INTERVAL '90 days'`, [id]);
    const rating = Math.max(0, Math.min(100, Math.round(
      paidShare * 60 + (1 - Math.min(1, overdueShare * 3)) * 30 + Math.min(1, recent.rows[0].n / 5) * 10)));

    res.json({
      supplier: sup.rows[0],
      totals: { ...t, avg_payment_days: avgPay.rows[0].avg_days !== null ? parseFloat(avgPay.rows[0].avg_days) : null },
      rating,
      overdue_days_threshold: overdueDays,
      overdue: overdue.rows,
      overdue_total: Math.round(overdueSum * 100) / 100,
      lots: lots.rows,
      payments: payments.rows,
      returns: returns.rows,
      price_history: priceHistory.rows,
      discounts: discounts.rows,
    });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// Postavshikka umumiy to'lov (partiyasiz yoki eng eski qarzli partiyalarga taqsimlab)
const paySupplier = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    let amount = Math.round((parseFloat(req.body.amount) || 0) * 100) / 100;
    if (!(amount > 0)) return res.status(400).json({ message: "To'lov summasi musbat bo'lishi kerak" });
    const method = req.body.method === 'card' ? 'card' : 'cash';
    const fromKassa = req.body.from_kassa !== false && req.body.from_kassa !== 'false';
    const note = (req.body.note || '').toString().trim().slice(0, 200) || null;

    await client.query('BEGIN');
    const sup = await client.query('SELECT id, name FROM suppliers WHERE id = $1', [id]);
    if (!sup.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Postavshik topilmadi' }); }
    let payerName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      payerName = u.rows.length ? u.rows[0].full_name : null;
    }

    // FIFO bo'yicha qarzli partiyalarga taqsimlaymiz
    const debtLots = await client.query(
      `SELECT id, total_cost, paid_amount FROM stock_lots
       WHERE supplier_id = $1 AND (total_cost - paid_amount) > 0.005
       ORDER BY received_at ASC, id ASC FOR UPDATE`, [id]);
    const totalDebt = debtLots.rows.reduce(
      (a, l) => a + (parseFloat(l.total_cost) - parseFloat(l.paid_amount)), 0);
    if (amount > totalDebt + 0.01) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: `To'lov (${amount}) jami qarzdan (${Math.round(totalDebt * 100) / 100}) katta` });
    }
    let left = amount;
    const paidLots = [];
    for (const l of debtLots.rows) {
      if (left <= 0.005) break;
      const debt = Math.round((parseFloat(l.total_cost) - parseFloat(l.paid_amount)) * 100) / 100;
      const pay = Math.min(debt, left);
      left = Math.round((left - pay) * 100) / 100;
      await addSupplierPayment(client, {
        supplierId: parseInt(id), lotId: l.id, amount: pay, method,
        fromKassa, note, paidBy: req.user ? req.user.id : null, paidByName: payerName,
      });
      paidLots.push({ lot_id: l.id, amount: pay });
    }
    await logAudit(client, {
      req, action: 'supplier.pay', entityType: 'supplier', entityId: parseInt(id),
      newValue: { amount, method, from_kassa: fromKassa, lots: paidLots }, userName: payerName,
    });
    await client.query('COMMIT');
    res.status(201).json({ ok: true, amount, lots: paidLots });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally { client.release(); }
};

module.exports = { getSuppliers, createSupplier, updateSupplier, deleteSupplier, getSupplierLedger, paySupplier };
