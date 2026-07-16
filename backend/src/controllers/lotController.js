// ============================================================
// PARTIYALAR (LOT/BATCH) API — F10 + F12.
// Har partiya mustaqil: o'z qoldig'i, narxi, to'lovi, srok godnosti.
// remaining/debt so'rovda hisoblanadi (quantity-used, total-paid).
// ============================================================
const pool = require('../config/db');
const { consumeStock, addSupplierPayment, getSetting } = require('../services/costingService');
const { logAudit } = require('../services/audit');

const LOT_SELECT = `
  SELECT l.*,
         ROUND(l.quantity - l.used_quantity, 3)              AS remaining_quantity,
         ROUND((l.quantity - l.used_quantity) * l.unit_cost, 2) AS remaining_cost,
         ROUND(l.total_cost - l.paid_amount, 2)              AS debt_amount,
         i.name AS ingredient_name, i.unit AS ingredient_unit, i.warehouse_id,
         s.name AS supplier_name
  FROM stock_lots l
  JOIN ingredients i ON l.ingredient_id = i.id
  LEFT JOIN suppliers s ON l.supplier_id = s.id`;

// Partiyalar ro'yxati: ?ingredient_id= ?supplier_id= ?status= ?warehouse_id=
// ?with_remaining=true (faqat qoldiqlilar) ?debt=true (faqat qarzlilar)
const getLots = async (req, res) => {
  try {
    const conds = [];
    const params = [];
    const add = (sql, v) => { params.push(v); conds.push(sql.replace('?', '$' + params.length)); };
    if (req.query.ingredient_id) add('l.ingredient_id = ?', parseInt(req.query.ingredient_id));
    if (req.query.supplier_id) add('l.supplier_id = ?', parseInt(req.query.supplier_id));
    if (req.query.status) add('l.status = ?', req.query.status);
    if (req.query.warehouse_id) add('i.warehouse_id = ?', parseInt(req.query.warehouse_id));
    if (req.query.with_remaining === 'true') conds.push('(l.quantity - l.used_quantity) > 0');
    if (req.query.debt === 'true') conds.push('(l.total_cost - l.paid_amount) > 0.005');
    const where = conds.length ? ' WHERE ' + conds.join(' AND ') : '';
    const limit = Math.min(500, parseInt(req.query.limit) || 200);
    const r = await pool.query(
      `${LOT_SELECT}${where} ORDER BY l.received_at DESC, l.id DESC LIMIT ${limit}`, params);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// Bitta partiya: to'lovlar tarixi + sarf tarixi bilan
const getLotDetail = async (req, res) => {
  try {
    const { id } = req.params;
    const lot = await pool.query(`${LOT_SELECT} WHERE l.id = $1`, [id]);
    if (!lot.rows.length) return res.status(404).json({ message: 'Partiya topilmadi' });
    const payments = await pool.query(
      `SELECT * FROM supplier_payments WHERE lot_id = $1 ORDER BY created_at DESC`, [id]);
    const consumptions = await pool.query(
      `SELECT * FROM lot_consumptions WHERE lot_id = $1 ORDER BY created_at DESC LIMIT 200`, [id]);
    res.json({ ...lot.rows[0], payments: payments.rows, consumptions: consumptions.rows });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// SPISANIYA (srok o'tdi / buzildi / boshqa): aynan SHU partiyadan.
// body: { quantity?, reason } — quantity berilmasa butun qoldiq.
const writeoffLot = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const reasonText = (req.body.reason || '').toString().trim();
    if (!reasonText) return res.status(400).json({ message: 'Sabab yozish shart!' });
    await client.query('BEGIN');
    const lr = await client.query(
      `SELECT * FROM stock_lots WHERE id = $1 FOR UPDATE`, [id]);
    if (!lr.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Partiya topilmadi' }); }
    const lot = lr.rows[0];
    const remaining = Math.round((parseFloat(lot.quantity) - parseFloat(lot.used_quantity)) * 1000) / 1000;
    if (remaining <= 0) { await client.query('ROLLBACK'); return res.status(400).json({ message: 'Partiyada qoldiq yo\'q' }); }
    let qty = req.body.quantity !== undefined ? parseFloat(req.body.quantity) : remaining;
    if (!(qty > 0) || qty > remaining + 0.0005) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: `Miqdor 0 dan katta va qoldiqdan (${remaining}) oshmasligi kerak` });
    }
    qty = Math.min(qty, remaining);
    const isExpired = lot.expiry_date && new Date(lot.expiry_date) < new Date();
    const fullyOff = remaining - qty <= 0.0005;
    await client.query(
      `UPDATE stock_lots SET used_quantity = used_quantity + $1,
              status = CASE WHEN $2 THEN 'written_off' ELSE status END
       WHERE id = $3`,
      [qty, fullyOff, id]);
    await client.query(
      `UPDATE ingredients SET stock_quantity = stock_quantity - $1 WHERE id = $2`,
      [qty, lot.ingredient_id]);
    await client.query(
      `INSERT INTO lot_consumptions (lot_id, ingredient_id, quantity, unit_cost, cost_method, reason, ref_type, ref_id, note)
       VALUES ($1,$2,$3,$4,NULL,$5,'lot',$1,$6)`,
      [id, lot.ingredient_id, qty, lot.unit_cost, isExpired ? 'expired' : 'writeoff', reasonText]);
    await logAudit(client, {
      req, action: 'lot.writeoff', entityType: 'stock_lot', entityId: parseInt(id),
      oldValue: { remaining }, newValue: { written_off: qty, status: fullyOff ? 'written_off' : lot.status },
      reason: reasonText,
    });
    await client.query('COMMIT');
    res.json({ ok: true, written_off: qty, loss_value: Math.round(qty * parseFloat(lot.unit_cost) * 100) / 100 });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally { client.release(); }
};

// BLOKLASH / BLOKDAN CHIQARISH: bloklangan partiyadan sarf qilinmaydi
// (consumeStock faqat status='active' dan oladi).
const setLotBlocked = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const block = req.body.blocked !== false && req.body.blocked !== 'false';
    const reasonText = (req.body.reason || '').toString().trim();
    if (block && !reasonText) return res.status(400).json({ message: 'Bloklash sababi shart!' });
    await client.query('BEGIN');
    const lr = await client.query(`SELECT status, quantity, used_quantity FROM stock_lots WHERE id = $1 FOR UPDATE`, [id]);
    if (!lr.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Partiya topilmadi' }); }
    const old = lr.rows[0];
    if (block && old.status !== 'active') {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: `Faqat aktiv partiya bloklanadi (hozir: ${old.status})` });
    }
    if (!block && old.status !== 'blocked') {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Partiya bloklanmagan' });
    }
    // blokdan chiqarilganda qoldiqqa qarab active/depleted
    const remaining = parseFloat(old.quantity) - parseFloat(old.used_quantity);
    const newStatus = block ? 'blocked' : (remaining > 0.0005 ? 'active' : 'depleted');
    await client.query(`UPDATE stock_lots SET status = $1 WHERE id = $2`, [newStatus, id]);
    await logAudit(client, {
      req, action: block ? 'lot.block' : 'lot.unblock', entityType: 'stock_lot', entityId: parseInt(id),
      oldValue: { status: old.status }, newValue: { status: newStatus }, reason: reasonText || null,
    });
    await client.query('COMMIT');
    res.json({ ok: true, status: newStatus });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally { client.release(); }
};

// POSTAVSHIKKA QAYTARISH (vozvrat): qoldiqdan qaytadi, qarz kamayadi
// (paid_amount oshiriladi — hisob-kitob yopilgani), pul qaytsa kassaga kirim.
// body: { quantity, refund_to_kassa? (default false), reason }
const returnLot = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const reasonText = (req.body.reason || '').toString().trim();
    if (!reasonText) return res.status(400).json({ message: 'Vozvrat sababi shart!' });
    let qty = parseFloat(req.body.quantity);
    if (!(qty > 0)) return res.status(400).json({ message: 'Miqdor musbat bo\'lishi kerak' });
    await client.query('BEGIN');
    const lr = await client.query(`SELECT * FROM stock_lots WHERE id = $1 FOR UPDATE`, [id]);
    if (!lr.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Partiya topilmadi' }); }
    const lot = lr.rows[0];
    const remaining = Math.round((parseFloat(lot.quantity) - parseFloat(lot.used_quantity)) * 1000) / 1000;
    if (qty > remaining + 0.0005) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: `Qoldiqdan (${remaining}) ortiq qaytarib bo'lmaydi` });
    }
    // Epsilon (0.0005) ichida qoldiqdan sal oshsa — qoldiqqa cheklab qo'yamiz
    // (aks holda used_quantity > quantity bo'lib, partiya qoldig'i manfiy chiqardi).
    qty = Math.min(qty, remaining);
    const value = Math.round(qty * parseFloat(lot.unit_cost) * 100) / 100;
    const debt = Math.round((parseFloat(lot.total_cost) - parseFloat(lot.paid_amount)) * 100) / 100;
    const fullyOff = remaining - qty <= 0.0005;

    await client.query(
      `UPDATE stock_lots SET used_quantity = used_quantity + $1,
              status = CASE WHEN $2 AND status = 'active' THEN 'depleted' ELSE status END
       WHERE id = $3`, [qty, fullyOff, id]);
    await client.query(
      `UPDATE ingredients SET stock_quantity = stock_quantity - $1 WHERE id = $2`,
      [qty, lot.ingredient_id]);
    await client.query(
      `INSERT INTO lot_consumptions (lot_id, ingredient_id, quantity, unit_cost, reason, ref_type, ref_id, note)
       VALUES ($1,$2,$3,$4,'return','lot',$1,$5)`,
      [id, lot.ingredient_id, qty, lot.unit_cost, reasonText]);

    // Moliya: avval qarzni yopamiz (refund yozuvi, pul harakatisiz),
    // qarzdan ortig'i pul qaytishi bo'lsa — kassaga kirim.
    const debtSettle = Math.min(value, Math.max(0, debt));
    if (debtSettle > 0.005) {
      await client.query(`UPDATE stock_lots SET paid_amount = paid_amount + $1 WHERE id = $2`, [debtSettle, id]);
      await client.query(
        `INSERT INTO supplier_payments (supplier_id, lot_id, amount, kind, method, from_kassa, note, paid_by, paid_by_name)
         VALUES ($1,$2,$3,'refund','cash',false,$4,$5,$6)`,
        [lot.supplier_id, id, debtSettle, `Vozvrat — qarz hisobiga: ${reasonText}`,
         req.user ? req.user.id : null, null]);
    }
    const cashBack = Math.round((value - debtSettle) * 100) / 100;
    if (cashBack > 0.005 && (req.body.refund_to_kassa === true || req.body.refund_to_kassa === 'true')) {
      const sp = await client.query(
        `INSERT INTO supplier_payments (supplier_id, lot_id, amount, kind, method, from_kassa, note, paid_by, paid_by_name)
         VALUES ($1,$2,$3,'refund','cash',true,$4,$5,$6) RETURNING id`,
        [lot.supplier_id, id, cashBack, `Vozvrat — pul qaytdi: ${reasonText}`,
         req.user ? req.user.id : null, null]);
      await client.query(
        `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
         VALUES ('income','cash',$1,'supplier',$2,$3)`,
        [cashBack, sp.rows[0].id, `Postavshik vozvrat (partiya ${lot.lot_code || id})`]);
    }
    await logAudit(client, {
      req, action: 'lot.return', entityType: 'stock_lot', entityId: parseInt(id),
      oldValue: { remaining, debt }, newValue: { returned: qty, value, debt_settled: debtSettle, cash_back: cashBack },
      reason: reasonText,
    });
    await client.query('COMMIT');
    res.json({ ok: true, returned: qty, value, debt_settled: debtSettle, cash_back: cashBack });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally { client.release(); }
};

// Partiya to'lovi (qarzni yopish) — kassadan yoki tashqaridan.
const payLot = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    await client.query('BEGIN');
    let payerName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      payerName = u.rows.length ? u.rows[0].full_name : null;
    }
    const pay = await addSupplierPayment(client, {
      lotId: parseInt(id),
      amount: req.body.amount,
      method: req.body.method,
      fromKassa: req.body.from_kassa !== false && req.body.from_kassa !== 'false',
      note: (req.body.note || '').toString().trim().slice(0, 200) || null,
      paidBy: req.user ? req.user.id : null,
      paidByName: payerName,
    });
    await logAudit(client, {
      req, action: 'lot.pay', entityType: 'stock_lot', entityId: parseInt(id),
      newValue: { amount: pay.amount, method: pay.method, from_kassa: pay.from_kassa },
      userName: payerName,
    });
    await client.query('COMMIT');
    res.status(201).json(pay);
  } catch (err) {
    await client.query('ROLLBACK');
    const code = /katta|musbat|topilmadi/.test(err.message) ? 400 : 500;
    res.status(code).json({ message: err.message });
  } finally { client.release(); }
};

// SROK NAZORATI (F12): tugayotgan + o'tgan partiyalar, yo'qotish analitikasi.
// ?days=N (default app_settings.expiry_warn_days yoki 5)
const getExpiry = async (req, res) => {
  try {
    const warnDays = parseInt(req.query.days)
      || parseInt(await getSetting(pool, 'expiry_warn_days', '5'), 10) || 5;
    const expiring = await pool.query(
      `${LOT_SELECT}
       WHERE l.expiry_date IS NOT NULL
         AND l.status IN ('active','blocked')
         AND (l.quantity - l.used_quantity) > 0
         AND l.expiry_date >= CURRENT_DATE
         AND l.expiry_date <= CURRENT_DATE + ($1 || ' days')::interval
       ORDER BY l.expiry_date ASC`, [warnDays]);
    const expired = await pool.query(
      `${LOT_SELECT}
       WHERE l.expiry_date IS NOT NULL
         AND l.status IN ('active','blocked')
         AND (l.quantity - l.used_quantity) > 0
         AND l.expiry_date < CURRENT_DATE
       ORDER BY l.expiry_date ASC`);
    const expiredTotals = expired.rows.reduce((a, l) => {
      a.count += 1;
      a.quantity += parseFloat(l.remaining_quantity) || 0;
      a.value += parseFloat(l.remaining_cost) || 0;
      return a;
    }, { count: 0, quantity: 0, value: 0 });
    // Yo'qotishlar analitikasi: spisaniya/srok bo'yicha oylik (12 oy)
    const losses = await pool.query(
      `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS month,
              reason,
              ROUND(SUM(quantity * unit_cost), 2) AS value,
              ROUND(SUM(quantity), 3) AS quantity
       FROM lot_consumptions
       WHERE reason IN ('expired','writeoff','return') AND quantity > 0
         AND created_at >= date_trunc('month', NOW()) - INTERVAL '11 months'
       GROUP BY 1, 2 ORDER BY 1`);
    const lossTotal = await pool.query(
      `SELECT COALESCE(ROUND(SUM(quantity * unit_cost), 2), 0) AS value
       FROM lot_consumptions WHERE reason IN ('expired','writeoff') AND quantity > 0`);
    res.json({
      warn_days: warnDays,
      expiring: expiring.rows,
      expired: expired.rows,
      expired_count: expiredTotals.count,
      expired_quantity: Math.round(expiredTotals.quantity * 1000) / 1000,
      expired_value: Math.round(expiredTotals.value * 100) / 100,
      losses_by_month: losses.rows,
      losses_total: parseFloat(lossTotal.rows[0].value),
    });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

module.exports = { getLots, getLotDetail, writeoffLot, setLotBlocked, returnLot, payLot, getExpiry };
