// ============================================================
// SKLAD INTELLEKTI: Timeline (F14), analitika (F15), sozlamalar (F11),
// audit-jurnal ko'rish (F16), konsistensiya tekshiruvi (F17).
// ============================================================
const pool = require('../config/db');
const { METHODS, getSetting } = require('../services/costingService');
const { logAudit } = require('../services/audit');

// ─── F14: TIMELINE — tovarning BUTUN tarixi bitta lentada ───
// Zakupkalar (partiyalar), sotuvlar, P/F sarfi, spisaniya, vozvrat,
// inventarizatsiya, qo'lda tahrirlar, audit yozuvlari.
// GET /stock/:id/timeline?limit=100&before=ISO
const getTimeline = async (req, res) => {
  try {
    const { id } = req.params;
    const limit = Math.min(300, parseInt(req.query.limit) || 100);
    // Kompound kursor: (ts, src, eid). Bir xil vaqt tamg'asidagi hodisalar
    // (masalan bitta zakaz bir necha partiyadan sarf qilganda — hammasi bir xil
    // created_at) sahifa chegarasida TUSHIB QOLMASligi uchun. Frontend oxirgi
    // qatorning ts/src/eid sini qaytaradi. src = manba raqami, eid = manba PK.
    const before = req.query.before || null;
    const beforeSrc = req.query.before_src != null ? parseInt(req.query.before_src) : null;
    const beforeEid = req.query.before_eid != null ? parseInt(req.query.before_eid) : null;
    const params = [parseInt(id), before, limit, beforeSrc, beforeEid];
    const r = await pool.query(
      `WITH events AS (
        -- Zakupkalar (partiyalar)
        SELECT l.received_at AS ts, 'purchase' AS kind,
               COALESCE('Partiya ' || l.lot_code, 'Kirim') AS title,
               l.quantity AS qty, l.unit_cost, l.total_cost AS amount,
               l.created_by_name AS user_name,
               s.name AS detail, l.invoice_no AS ref, l.id AS ref_id,
               1 AS src, l.id AS eid
        FROM stock_lots l LEFT JOIN suppliers s ON l.supplier_id = s.id
        WHERE l.ingredient_id = $1

        UNION ALL
        -- Sarflar: sotuv / P/F / spisaniya / vozvrat / inventar / qaytarish
        SELECT c.created_at, CASE
                 WHEN c.reason = 'sale' THEN 'sale'
                 WHEN c.reason = 'pf_production' THEN 'pf'
                 WHEN c.reason IN ('writeoff','expired') THEN 'writeoff'
                 WHEN c.reason = 'return' THEN 'return'
                 WHEN c.reason = 'inventory' THEN 'inventory'
                 WHEN c.reason = 'restore' THEN 'restore'
                 ELSE 'adjust' END,
               CASE
                 WHEN c.reason = 'sale' THEN 'Sotuv' || COALESCE(' (zakaz #' || c.ref_id || ')', '')
                 WHEN c.reason = 'pf_production' THEN 'P/F tayyorlashga sarf'
                 WHEN c.reason = 'expired' THEN 'Spisaniya (srok o''tdi)'
                 WHEN c.reason = 'writeoff' THEN 'Spisaniya'
                 WHEN c.reason = 'return' THEN 'Postavshikka vozvrat'
                 WHEN c.reason = 'inventory' THEN 'Inventarizatsiya kamomad'
                 WHEN c.reason = 'restore' THEN 'Zakaz bekor — qaytdi'
                 ELSE 'Korrektirovka' END,
               -c.quantity, c.unit_cost, ROUND(c.quantity * c.unit_cost, 2),
               NULL, c.note, l2.lot_code, c.ref_id,
               2 AS src, c.id AS eid
        FROM lot_consumptions c LEFT JOIN stock_lots l2 ON c.lot_id = l2.id
        WHERE c.ingredient_id = $1

        UNION ALL
        -- Qo'lda tahrirlar + inventar yozuvlari (stock_change_log)
        SELECT scl.created_at, 'edit', 'Tahrir: ' || scl.changes,
               NULL, NULL, NULL, scl.user_name, scl.reason, NULL, scl.id,
               3 AS src, scl.id AS eid
        FROM stock_change_log scl WHERE scl.ingredient_id = $1

        UNION ALL
        -- Legacy kirimlar (partiya tizimidan OLDINGI) — dublikatga yo'l qo'ymaslik
        -- uchun faqat partiyaga bog'lanmaganlari
        SELECT si.created_at, 'purchase_legacy', 'Kirim (eski tizim)',
               si.quantity, si.price_per_unit, si.total_amount, NULL, si.note, si.source, si.id,
               4 AS src, si.id AS eid
        FROM stock_incoming si
        WHERE si.ingredient_id = $1
          AND NOT EXISTS (SELECT 1 FROM stock_lots l3 WHERE l3.source_incoming_id = si.id)

        UNION ALL
        -- Audit yozuvlari (masalan, birlik/nom o'zgarishi)
        SELECT a.created_at, 'audit', a.action,
               NULL, NULL, NULL, a.user_name, a.reason, NULL, a.entity_id,
               5 AS src, a.id AS eid
        FROM audit_log a WHERE a.entity_type = 'ingredient' AND a.entity_id = $1
      )
      SELECT *, to_char(ts, 'YYYY-MM-DD HH24:MI:SS.US') AS cts FROM events
      WHERE ($2::timestamp IS NULL
             OR (ts, src, eid) < ($2::timestamp, $4::int, $5::bigint))
      ORDER BY ts DESC, src DESC, eid DESC
      LIMIT $3`, params);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// ─── F15: BITTA TOVAR ANALITIKASI ───
// GET /stock/:id/analytics?days=90
const getIngredientAnalytics = async (req, res) => {
  try {
    const { id } = req.params;
    const days = Math.min(365, parseInt(req.query.days) || 90);
    const ing = await pool.query(
      `SELECT id, name, unit, stock_quantity, min_quantity, price_per_unit, selling_price
       FROM ingredients WHERE id = $1`, [id]);
    if (!ing.rows.length) return res.status(404).json({ message: 'Tovar topilmadi' });
    const item = ing.rows[0];

    // Narx statistikasi partiyalardan (legacy kirimlar bilan birga)
    const price = await pool.query(
      `WITH pp AS (
         -- Faqat HAQIQIY xaridlar: sintetik partiyalar (backfill / konsistensiya-sync)
         -- narx trendini buzmasligi uchun chiqarib tashlanadi.
         SELECT received_at AS ts, unit_cost AS price FROM stock_lots
         WHERE ingredient_id = $1 AND source_incoming_id IS NOT NULL
         UNION ALL
         SELECT si.created_at, si.price_per_unit FROM stock_incoming si
         WHERE si.ingredient_id = $1 AND si.price_per_unit > 0
           AND NOT EXISTS (SELECT 1 FROM stock_lots l WHERE l.source_incoming_id = si.id)
       )
       SELECT COUNT(*)::int AS purchase_count,
              ROUND(AVG(price), 2) AS avg_price,
              ROUND(MIN(price), 2) AS min_price,
              ROUND(MAX(price), 2) AS max_price,
              (SELECT ROUND(price, 2) FROM pp ORDER BY ts ASC LIMIT 1)  AS first_price,
              (SELECT ROUND(price, 2) FROM pp ORDER BY ts DESC LIMIT 1) AS last_price
       FROM pp`, [id]);
    const p = price.rows[0];
    const priceChangePct = p.first_price && parseFloat(p.first_price) > 0
      ? Math.round((parseFloat(p.last_price) - parseFloat(p.first_price)) / parseFloat(p.first_price) * 1000) / 10
      : null;

    // Oylik o'rtacha narx (12 oy) — trend grafigi uchun
    const priceMonthly = await pool.query(
      `SELECT to_char(date_trunc('month', received_at), 'YYYY-MM') AS month,
              ROUND(AVG(unit_cost), 2) AS avg_price
       FROM stock_lots
       WHERE ingredient_id = $1 AND source_incoming_id IS NOT NULL
         AND received_at >= date_trunc('month', NOW()) - INTERVAL '11 months'
       GROUP BY 1 ORDER BY 1`, [id]);

    // Sarf: sotuv + P/F (qaytarishlar minus bo'lib kiradi — net to'g'ri)
    const usage = await pool.query(
      `SELECT COALESCE(ROUND(SUM(quantity), 3), 0) AS total_used,
              COALESCE(ROUND(SUM(quantity * unit_cost), 2), 0) AS total_cost
       FROM lot_consumptions
       WHERE ingredient_id = $1 AND reason IN ('sale','pf_production','restore')
         AND created_at >= NOW() - ($2 || ' days')::interval`, [id, days]);
    const totalUsed = Math.max(0, parseFloat(usage.rows[0].total_used));
    const dailyUsage = Math.round(totalUsed / days * 1000) / 1000;
    const stock = parseFloat(item.stock_quantity) || 0;
    const daysLeft = dailyUsage > 0 && stock > 0 ? Math.floor(stock / dailyUsage) : null;

    // Oylik sarf seriyasi (grafik)
    const usageMonthly = await pool.query(
      `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS month,
              ROUND(SUM(quantity), 3) AS used,
              ROUND(SUM(quantity * unit_cost), 2) AS cost
       FROM lot_consumptions
       WHERE ingredient_id = $1 AND reason IN ('sale','pf_production','restore')
         AND created_at >= date_trunc('month', NOW()) - INTERVAL '11 months'
       GROUP BY 1 ORDER BY 1`, [id]);

    // Yo'qotishlar (spisaniya/srok) shu tovar bo'yicha
    const losses = await pool.query(
      `SELECT COALESCE(ROUND(SUM(quantity * unit_cost), 2), 0) AS value
       FROM lot_consumptions
       WHERE ingredient_id = $1 AND reason IN ('expired','writeoff') AND quantity > 0`, [id]);

    // Food Cost ulushi: davrdagi jami sarf qiymatidagi ulush
    const totalAll = await pool.query(
      `SELECT COALESCE(SUM(quantity * unit_cost), 0) AS v
       FROM lot_consumptions
       WHERE reason IN ('sale','pf_production','restore')
         AND created_at >= NOW() - ($1 || ' days')::interval`, [days]);
    const shareOfFoodCost = parseFloat(totalAll.rows[0].v) > 0
      ? Math.round(parseFloat(usage.rows[0].total_cost) / parseFloat(totalAll.rows[0].v) * 1000) / 10
      : 0;

    // Oborachivayemost: davr sarf qiymati / joriy zaxira qiymati
    const stockValue = Math.round(stock * (parseFloat(item.price_per_unit) || 0) * 100) / 100;
    const turnover = stockValue > 0
      ? Math.round(parseFloat(usage.rows[0].total_cost) / stockValue * 100) / 100
      : null;

    // Rentabellik (faqat sotuvga chiqarilgan tovarlar uchun)
    const sell = parseFloat(item.selling_price) || 0;
    const cost = parseFloat(item.price_per_unit) || 0;
    const profitability = sell > 0
      ? { selling_price: sell, cost, margin: Math.round((sell - cost) * 100) / 100,
          margin_pct: Math.round((sell - cost) / sell * 1000) / 10 }
      : null;

    const leadDays = 7;   // tavsiya: 1 haftalik zaxira minimal
    const orderDays = 14; // tavsiya: 2 haftalik hajmda zakupka
    res.json({
      ingredient: item,
      period_days: days,
      price: {
        ...p,
        change_pct: priceChangePct,
        monthly: priceMonthly.rows,
      },
      usage: {
        total_used: totalUsed,
        total_cost: parseFloat(usage.rows[0].total_cost),
        daily_avg: dailyUsage,
        monthly: usageMonthly.rows,
      },
      forecast: {
        days_left: daysLeft,
        stockout_date: daysLeft !== null
          ? new Date(Date.now() + daysLeft * 86400000).toISOString().slice(0, 10) : null,
        next_purchase_date: daysLeft !== null
          ? new Date(Date.now() + Math.max(0, daysLeft - leadDays) * 86400000).toISOString().slice(0, 10) : null,
        recommended_min: Math.round(dailyUsage * leadDays * 1000) / 1000,
        recommended_order: Math.round(dailyUsage * orderDays * 1000) / 1000,
      },
      losses_value: parseFloat(losses.rows[0].value),
      food_cost_share_pct: shareOfFoodCost,
      stock_value: stockValue,
      turnover,
      profitability,
    });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// ─── F15: ABC / XYZ tahlili — butun sklad bo'yicha ───
// ABC: sarf qiymati bo'yicha (A: 80%, B: 95% gacha, C: qolgan).
// XYZ: haftalik sarf barqarorligi (variatsiya koeffitsienti):
//   X < 0.25 (barqaror), Y < 0.5 (o'rtacha), Z >= 0.5 yoki ma'lumot kam.
// GET /stock/analytics/abc-xyz?days=90&warehouse_id=
const getAbcXyz = async (req, res) => {
  try {
    const days = Math.min(365, parseInt(req.query.days) || 90);
    const nWeeks = Math.max(1, Math.ceil(days / 7)); // XYZ CV uchun to'liq davr haftalari (nol haftalar bilan)
    const whId = req.query.warehouse_id ? parseInt(req.query.warehouse_id) : null;
    const r = await pool.query(
      `WITH cons AS (
         SELECT c.ingredient_id,
                SUM(c.quantity * c.unit_cost) AS value,
                SUM(c.quantity) AS qty
         FROM lot_consumptions c
         WHERE c.reason IN ('sale','pf_production','restore')
           AND c.created_at >= NOW() - ($1 || ' days')::interval
         GROUP BY c.ingredient_id
       ),
       weekly AS (
         SELECT c.ingredient_id, date_trunc('week', c.created_at) AS wk, SUM(c.quantity) AS q
         FROM lot_consumptions c
         WHERE c.reason IN ('sale','pf_production','restore')
           AND c.created_at >= NOW() - ($1 || ' days')::interval
         GROUP BY 1, 2
       ),
       cv AS (
         -- XYZ o'zgaruvchanligi: NOL-sarfli haftalar ham hisobga olinadi (aks holda
         -- uzuq-yuluq tovar "barqaror" ko'rinardi). To'liq davr haftalari soni N bo'yicha:
         -- mean = sum/N, dispersiya = sumsq/N - mean^2 (nol haftalar 0^2 qo'shadi).
         SELECT ingredient_id,
                SUM(q) AS sum_q, SUM(q*q) AS sumsq_q, COUNT(*)::int AS weeks
         FROM weekly GROUP BY ingredient_id
       ),
       cvn AS (
         SELECT ingredient_id, weeks,
                CASE WHEN sum_q > 0 AND weeks >= 2
                     THEN sqrt(GREATEST(0, sumsq_q / $2::numeric - (sum_q / $2::numeric)^2))
                          / NULLIF(sum_q / $2::numeric, 0)
                     ELSE NULL END AS cv
         FROM cv
       )
       SELECT i.id, i.name, i.unit, i.stock_quantity, i.min_quantity, i.price_per_unit,
              i.warehouse_id, i.category,
              COALESCE(ROUND(cons.value, 2), 0) AS consumption_value,
              COALESCE(ROUND(cons.qty, 3), 0) AS consumption_qty,
              cvn.cv, COALESCE(cvn.weeks, 0) AS weeks,
              (SELECT MAX(c2.created_at) FROM lot_consumptions c2
                WHERE c2.ingredient_id = i.id AND c2.quantity > 0) AS last_movement
       FROM ingredients i
       LEFT JOIN cons ON cons.ingredient_id = i.id
       LEFT JOIN cvn ON cvn.ingredient_id = i.id
       WHERE COALESCE(i.is_active, true) = true
         ${whId ? 'AND i.warehouse_id = $3' : ''}
       ORDER BY COALESCE(cons.value, 0) DESC`,
      whId ? [days, nWeeks, whId] : [days, nWeeks]);

    const rows = r.rows;
    const totalValue = rows.reduce((a, x) => a + parseFloat(x.consumption_value), 0);
    let cum = 0;
    for (const x of rows) {
      const v = parseFloat(x.consumption_value);
      // klass — shu tovargacha bo'lgan kumulyativ ulush bo'yicha (80% chegarani
      // KESIB O'TGAN tovar ham A bo'ladi — klassik ABC konventsiyasi)
      const shareBefore = totalValue > 0 ? cum / totalValue : 1;
      cum += v;
      x.abc = totalValue > 0 && v > 0 ? (shareBefore < 0.8 ? 'A' : (shareBefore < 0.95 ? 'B' : 'C')) : 'C';
      const cvv = x.cv !== null ? parseFloat(x.cv) : null;
      x.xyz = cvv === null ? 'Z' : (cvv < 0.25 ? 'X' : (cvv < 0.5 ? 'Y' : 'Z'));
      // Muammoli tovarlar bayrog'i
      const stock = parseFloat(x.stock_quantity);
      const problems = [];
      if (stock < 0) problems.push('minus');
      if (stock > 0 && v === 0) problems.push('dead'); // harakatsiz zaxira
      if (parseFloat(x.min_quantity) > 0 && stock <= parseFloat(x.min_quantity)) problems.push('low');
      x.problems = problems;
    }
    const summary = { A: 0, B: 0, C: 0, X: 0, Y: 0, Z: 0, dead: 0, minus: 0, low: 0 };
    for (const x of rows) {
      summary[x.abc]++;
      summary[x.xyz]++;
      for (const pr of x.problems) summary[pr]++;
    }
    res.json({ period_days: days, total_consumption_value: Math.round(totalValue * 100) / 100, summary, items: rows });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// ─── F11: SOZLAMALAR (tannarx metodi va boshqalar) ───
const getSettings = async (req, res) => {
  try {
    const r = await pool.query('SELECT key, value, updated_at, updated_by_name FROM app_settings ORDER BY key');
    res.json({ settings: r.rows, costing_methods: METHODS });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

const ALLOWED_SETTINGS = {
  costing_method: (v) => METHODS.includes(v),
  expiry_warn_days: (v) => /^\d{1,3}$/.test(v) && parseInt(v) >= 1,
  supplier_overdue_days: (v) => /^\d{1,3}$/.test(v) && parseInt(v) >= 1,
  // Chiqishsiz (check-out yo'q) kunni oylikка qo'shamizmi? '1' — ha (default), '0' — yo'q.
  pay_missing_checkout: (v) => v === '0' || v === '1',
};

const putSetting = async (req, res) => {
  try {
    const key = (req.body.key || '').toString();
    const value = (req.body.value || '').toString();
    if (!ALLOWED_SETTINGS[key]) return res.status(400).json({ message: `Noma'lum sozlama: ${key}` });
    if (!ALLOWED_SETTINGS[key](value)) return res.status(400).json({ message: `Qiymat noto'g'ri: ${value}` });
    const old = await getSetting(pool, key, null);
    let userName = null;
    if (req.user && req.user.id) {
      const u = await pool.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      userName = u.rows.length ? u.rows[0].full_name : null;
    }
    await pool.query(
      `INSERT INTO app_settings (key, value, updated_at, updated_by, updated_by_name)
       VALUES ($1, $2, NOW(), $3, $4)
       ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = NOW(), updated_by = $3, updated_by_name = $4`,
      [key, value, req.user ? req.user.id : null, userName]);
    // Metod o'zgarishi TARIXNI o'zgartirmaydi: eski sarflar o'z narxida qoladi,
    // faqat YANGI sarflar yangi metod bilan hisoblanadi (F11 talabi).
    await logAudit(pool, {
      req, action: 'settings.update', entityType: 'setting', entityId: null,
      oldValue: { key, value: old }, newValue: { key, value }, userName,
    });
    res.json({ ok: true, key, value });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// ─── F16: AUDIT-JURNALNI KO'RISH (yozish — services/audit.js) ───
// GET /reports/audit?entity_type=&entity_id=&user_id=&action=&from=&to=&limit=
const getAuditLog = async (req, res) => {
  try {
    const conds = [];
    const params = [];
    const add = (sql, v) => { params.push(v); conds.push(sql.replace('?', '$' + params.length)); };
    if (req.query.entity_type) add('entity_type = ?', req.query.entity_type);
    if (req.query.entity_id) add('entity_id = ?', parseInt(req.query.entity_id));
    if (req.query.user_id) add('user_id = ?', parseInt(req.query.user_id));
    if (req.query.action) add('action LIKE ?', req.query.action + '%');
    if (req.query.from && /^\d{4}-\d{2}-\d{2}$/.test(req.query.from)) add('created_at >= ?::date', req.query.from);
    if (req.query.to && /^\d{4}-\d{2}-\d{2}$/.test(req.query.to)) add("created_at < ?::date + INTERVAL '1 day'", req.query.to);
    const where = conds.length ? ' WHERE ' + conds.join(' AND ') : '';
    const limit = Math.min(500, parseInt(req.query.limit) || 100);
    const r = await pool.query(
      `SELECT * FROM audit_log${where} ORDER BY created_at DESC, id DESC LIMIT ${limit}`, params);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// ─── F17: KONSISTENSIYA TEKSHIRUVI ───
// Modullararo moslikni tekshiradi va xavfsiz tuzatish taklif qiladi.
// Eslatma: yagona haqiqat manbai — Postgres (backend = shu baza;
// Firebase faqat frontend init, ma'lumot saqlamaydi).
const CHECKS = {
  // qoldiq vs partiyalar yig'indisi (musbat qoldiqlarda)
  stock_vs_lots: {
    title: 'Qoldiq ≠ partiyalar yig\'indisi',
    severity: 'high',
    fixable: true,
    fix_note: "Qoldiq > partiyalar bo'lsa 'Sync' partiya ochiladi (qo'shimcha, xavfsiz). Partiyalar > qoldiq bo'lsa avtomatik tuzatilmaydi — qo'lda (inventar/spisaniya) hal qiling (ma'lumot yo'qolmasin).",
    sql: `SELECT i.id, i.name, i.stock_quantity,
                 COALESCE(l.rem, 0) AS lots_remaining,
                 ROUND(i.stock_quantity - COALESCE(l.rem, 0), 3) AS diff
          FROM ingredients i
          LEFT JOIN (SELECT ingredient_id, SUM(quantity - used_quantity) AS rem
                     FROM stock_lots WHERE status IN ('active','blocked') GROUP BY ingredient_id) l
            ON l.ingredient_id = i.id
          WHERE COALESCE(i.is_active, true) = true
            AND i.stock_quantity > 0
            AND ABS(i.stock_quantity - COALESCE(l.rem, 0)) > 0.005`,
  },
  // partiya statusi qoldiqqa mos emas
  lot_status: {
    title: 'Partiya statusi qoldiqqa mos emas',
    severity: 'medium',
    fixable: true,
    fix_note: 'Status qoldiqdan qayta hisoblanadi (active<->depleted)',
    sql: `SELECT id, lot_code, status, ROUND(quantity - used_quantity, 3) AS remaining
          FROM stock_lots
          WHERE (status = 'active' AND (quantity - used_quantity) <= 0.0005)
             OR (status = 'depleted' AND (quantity - used_quantity) > 0.0005)`,
  },
  // to'lov jami qiymatdan katta
  lot_overpaid: {
    title: 'Partiyada to\'lov jami qiymatdan katta',
    severity: 'medium',
    fixable: false,
    fix_note: "Qo'lda tekshirish kerak — to'lov tarixini o'chirish xavfli",
    sql: `SELECT id, lot_code, total_cost, paid_amount FROM stock_lots WHERE paid_amount > total_cost + 0.01`,
  },
  // bir skladda bir xil nomli tovar (dublikat)
  dup_ingredients: {
    title: 'Dublikat tovarlar (bir sklad, bir nom)',
    severity: 'high',
    fixable: false,
    fix_note: "Skladdagi 'birlashtirish' (merge) funksiyasidan foydalaning",
    sql: `SELECT lower(trim(name)) AS name, warehouse_id, COUNT(*)::int AS n, array_agg(id) AS ids
          FROM ingredients WHERE COALESCE(is_active, true) = true
          GROUP BY 1, 2 HAVING COUNT(*) > 1`,
  },
  // menyu product/pf tovarga bog'lanmagan yoki arxivlangan tovarga bog'langan
  menu_orphan: {
    title: 'Menyu (product/P-F) sklad tovariga noto\'g\'ri bog\'langan',
    severity: 'high',
    fixable: false,
    fix_note: 'Menyu bo\'limida qayta bog\'lang yoki arxivlang',
    sql: `SELECT mi.id, mi.name, mi.type, mi.ingredient_id
          FROM menu_items mi
          WHERE mi.is_active = true AND mi.type IN ('product','pf')
            AND (mi.ingredient_id IS NULL
                 OR NOT EXISTS (SELECT 1 FROM ingredients i
                                WHERE i.id = mi.ingredient_id AND COALESCE(i.is_active, true) = true))`,
  },
  // retsept arxivlangan/yo'q tovarga tayanadi
  recipe_orphan: {
    title: 'Retsept arxivlangan tovardan foydalanadi',
    severity: 'high',
    fixable: false,
    fix_note: 'Retseptni yangi tovarga o\'tkazing (sotuv chegirishi ishlamayapti)',
    sql: `SELECT ri.id, mi.name AS dish, ri.ingredient_id, i.name AS ingredient, COALESCE(i.is_active, true) AS ing_active
          FROM recipe_items ri
          JOIN menu_items mi ON ri.menu_item_id = mi.id AND mi.is_active = true
          LEFT JOIN ingredients i ON ri.ingredient_id = i.id
          WHERE i.id IS NULL OR COALESCE(i.is_active, true) = false`,
  },
  // birlik spravochnikka bog'lanmagan
  unit_unmapped: {
    title: 'Tovar birligi spravochnikka bog\'lanmagan',
    severity: 'low',
    fixable: true,
    fix_note: 'Birlik matndan qayta aniqlanadi (trigger orqali, xavfsiz)',
    sql: `SELECT id, name, unit FROM ingredients
          WHERE COALESCE(is_active, true) = true AND unit_id IS NULL`,
  },
  // minus qoldiq (ATAYLAB ruxsat etilgan — axborot uchun)
  negative_stock: {
    title: 'Minus qoldiq (dizayn bo\'yicha ruxsat etilgan — axborot)',
    severity: 'info',
    fixable: false,
    fix_note: 'Inventarizatsiya o\'tkazib haqiqiy qoldiqni kiriting',
    sql: `SELECT id, name, unit, stock_quantity FROM ingredients
          WHERE COALESCE(is_active, true) = true AND stock_quantity < 0 ORDER BY stock_quantity`,
  },
  // yetim kassa yozuvlari (postavshik to'lovi o'chirilgan)
  cash_orphan_supplier: {
    title: 'Kassa yozuvi yetim (postavshik to\'lovi topilmadi)',
    severity: 'medium',
    fixable: false,
    fix_note: 'Qo\'lda tekshirish kerak',
    sql: `SELECT ct.id, ct.amount, ct.note, ct.created_at FROM cash_transactions ct
          WHERE ct.source = 'supplier'
            AND NOT EXISTS (SELECT 1 FROM supplier_payments sp WHERE sp.id = ct.ref_id)`,
  },
  // ochiq qolgan eski inventarizatsiyalar
  stale_inventory: {
    title: '3 kundan beri ochiq inventarizatsiya',
    severity: 'low',
    fixable: false,
    fix_note: 'Yakunlang yoki bekor qiling (yopishda qoldiq ustidan yoziladi!)',
    sql: `SELECT id, check_date, warehouse_id, created_at FROM inventory_checks
          WHERE status = 'open' AND created_at < NOW() - INTERVAL '3 days'`,
  },
};

const checkConsistency = async (req, res) => {
  try {
    const results = [];
    for (const [key, c] of Object.entries(CHECKS)) {
      try {
        const r = await pool.query(c.sql);
        results.push({
          key, title: c.title, severity: c.severity, fixable: c.fixable,
          fix_note: c.fix_note, count: r.rows.length, rows: r.rows.slice(0, 20),
        });
      } catch (e) {
        results.push({ key, title: c.title, severity: 'error', fixable: false, count: -1, error: e.message, rows: [] });
      }
    }
    const problems = results.filter((x) => x.count > 0 && x.severity !== 'info');
    // Tekshiruvning O'ZI xato bergan bo'lsa (count=-1, masalan jadval yo'q) —
    // holat NOMA'LUM, "hammasi mos" deb ko'rsatib bo'lmaydi.
    const errored = results.filter((x) => x.count === -1);
    res.json({
      ok: problems.length === 0 && errored.length === 0,
      checked_at: new Date().toISOString(),
      source_note: "Yagona haqiqat manbai — Postgres (lokal BD = backend bazasi; Firebase ma'lumot saqlamaydi)",
      results,
    });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// Xavfsiz tuzatishlar — faqat fixable=true kalitlar, tranzaksiyada,
// hech narsa O'CHIRILMAYDI (faqat status/sync yozuvlari).
const fixConsistency = async (req, res) => {
  const key = (req.body.key || '').toString();
  const c = CHECKS[key];
  if (!c) return res.status(400).json({ message: `Noma'lum tekshiruv: ${key}` });
  if (!c.fixable) return res.status(400).json({ message: 'Bu muammo avtomatik tuzatilmaydi — qo\'lda hal qiling' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    let fixed = 0;
    if (key === 'lot_status') {
      const r = await client.query(
        `UPDATE stock_lots
         SET status = CASE WHEN (quantity - used_quantity) > 0.0005 THEN 'active' ELSE 'depleted' END
         WHERE (status = 'active' AND (quantity - used_quantity) <= 0.0005)
            OR (status = 'depleted' AND (quantity - used_quantity) > 0.0005)
         RETURNING id`);
      fixed = r.rowCount;
    } else if (key === 'unit_unmapped') {
      // trigger ingredients_sync_refs unit matnidan unit_id ni tiklaydi
      const r = await client.query(
        `UPDATE ingredients SET unit = unit
         WHERE COALESCE(is_active, true) = true AND unit_id IS NULL RETURNING id`);
      fixed = r.rowCount;
    } else if (key === 'stock_vs_lots') {
      const rows = await client.query(CHECKS.stock_vs_lots.sql);
      for (const row of rows.rows) {
        const diff = parseFloat(row.diff);
        if (diff > 0.005) {
          // qoldiq partiyalardan ko'p — farqqa 'Sync' partiya (joriy o'rtacha narxda)
          const ing = await client.query('SELECT price_per_unit, unit FROM ingredients WHERE id = $1', [row.id]);
          const price = parseFloat(ing.rows[0].price_per_unit) || 0;
          const ins = await client.query(
            `INSERT INTO stock_lots (ingredient_id, quantity, unit, unit_cost, total_cost, paid_amount, status, note)
             VALUES ($1, $2, $3, $4, $5, $5, 'active', 'Konsistensiya sync (qoldiq > partiyalar)')
             RETURNING id`,
            [row.id, diff, ing.rows[0].unit, price, Math.round(diff * price * 100) / 100]);
          await client.query(
            `UPDATE stock_lots SET lot_code = 'LOT-' || LPAD(id::text, 6, '0') WHERE id = $1`, [ins.rows[0].id]);
          fixed++;
        }
        // diff < 0 (partiyalar qoldiqdan KO'P) — ATAYLAB avtomatik tuzatilmaydi.
        // Aktiv (yoki bloklangan) partiyani FIFO bilan "yopish" real sotiladigan
        // zaxirani spisan qilib, MA'LUMOT YO'QOTARDI (F17: yo'qotishsiz tuzatish).
        // Bunday farqni admin qo'lda hal qiladi (inventarizatsiya yoki spisaniya).
        // Shu sabab fixed++ ham qilinmaydi — soxta "tuzatildi" ko'rsatilmaydi.
      }
    }
    await logAudit(client, {
      req, action: 'consistency.fix', entityType: 'consistency', entityId: null,
      newValue: { key, fixed },
    });
    await client.query('COMMIT');
    res.json({ ok: true, key, fixed });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally { client.release(); }
};

module.exports = {
  getTimeline, getIngredientAnalytics, getAbcXyz,
  getSettings, putSetting, getAuditLog,
  checkConsistency, fixConsistency,
};
