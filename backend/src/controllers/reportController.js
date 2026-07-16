const pool = require('../config/db');

// Bir menu_item tannarxi (product: bog'langan ingredient narxi; recipe: retsept yig'indisi)
const MENU_COST_SUBQUERY = `
  SELECT mi.id AS menu_item_id,
    CASE WHEN mi.type = 'product' AND mi.ingredient_id IS NOT NULL
      THEN COALESCE((SELECT ing.price_per_unit FROM ingredients ing WHERE ing.id = mi.ingredient_id), 0)
      ELSE COALESCE((SELECT SUM(r.quantity * COALESCE(i.price_per_unit, 0))
                     FROM recipe_items r JOIN ingredients i ON r.ingredient_id = i.id
                     WHERE r.menu_item_id = mi.id), 0)
    END AS cost
  FROM menu_items mi`;

// Sotilgan taomlar TANNARXI (COGS). whereSql — orders(o)/order_items(oi) filtri.
// Valovaya foyda = savdo - COGS (foydani sun'iy oshirmaslik uchun).
async function cogsForOrders(whereSql, params = []) {
  const r = await pool.query(
    `SELECT COALESCE(SUM(oi.quantity * COALESCE(c.cost, 0)), 0) AS cogs
     FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     LEFT JOIN (${MENU_COST_SUBQUERY}) c ON c.menu_item_id = oi.menu_item_id
     WHERE ${whereSql}`,
    params
  );
  return parseFloat(r.rows[0].cogs) || 0;
}

// Kunlik hisobot
const getDailyReport = async (req, res) => {
  try {
    const { date } = req.query;
    const filterDate = date || new Date().toISOString().split('T')[0];

    // Jami savdo
    const salesResult = await pool.query(
      `SELECT
        COUNT(*) as total_orders,
        COALESCE(SUM(COALESCE(final_amount, total_amount)), 0) as total_sales
       FROM orders
       WHERE (created_at - INTERVAL '150 minutes')::date = $1 AND status = 'paid'`,
      [filterDate]
    );

    // Jami harajat — Kassadan ketgan chiqimlar (cash_transactions) + Kassadan tashqari xarajatlar (expenses).
    // Kassa manbali xarajatlar cash_transactions'da hisoblanadi, ikki marta sanamaslik uchun source <> 'kassa'.
    const expenseResult = await pool.query(
      `SELECT
        (SELECT COALESCE(SUM(amount), 0) FROM cash_transactions WHERE kind='expense' AND (created_at - INTERVAL '150 minutes')::date = $1)
        + (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE source <> 'kassa' AND (created_at - INTERVAL '150 minutes')::date = $1) as total_expenses`,
      [filterDate]
    );

    // Eng ko'p sotilgan taomlar
    const topItems = await pool.query(
      `SELECT m.name, SUM(oi.quantity) as total_qty, SUM(oi.price * oi.quantity) as total_amount
       FROM order_items oi
       JOIN menu_items m ON oi.menu_item_id = m.id
       JOIN orders o ON oi.order_id = o.id
       WHERE (o.created_at - INTERVAL '150 minutes')::date = $1 AND o.status = 'paid'
       GROUP BY m.name
       ORDER BY total_qty DESC
       LIMIT 5`,
      [filterDate]
    );

    // Ofitsant savdosi
    const waiterSales = await pool.query(
      `SELECT u.full_name, COUNT(o.id) as total_orders,
              COALESCE(SUM(COALESCE(o.final_amount, o.total_amount)), 0) as total_sales
       FROM orders o
       JOIN users u ON o.waiter_id = u.id
       WHERE (o.created_at - INTERVAL '150 minutes')::date = $1 AND o.status = 'paid'
       GROUP BY u.full_name
       ORDER BY total_sales DESC`,
      [filterDate]
    );

    const totalSales = parseFloat(salesResult.rows[0].total_sales);
    const totalExpenses = parseFloat(expenseResult.rows[0].total_expenses);
    const cogs = await cogsForOrders(
      `(o.created_at - INTERVAL '150 minutes')::date = $1 AND o.status = 'paid'`, [filterDate]);

    // SOF FOYDA — COGS modeli (getReport/getDashboard/getAnalytics bilan BIR XIL, egasi tasdig'i 2026-07-14):
    //   Realized − COGS − Ish haqi(to'liq) − Boshqa xarajatlar. Mahsulot xaridi COGS'da hisoblangani uchun
    //   boshqa xarajatlardan chiqariladi (ikki marta emas). Qarz faqat to'langanda kiradi.
    const df = `(created_at - INTERVAL '150 minutes')::date = $1`;
    const extra = await pool.query(
      `SELECT
        (SELECT COALESCE(SUM(paid_card),0)+COALESCE(SUM(paid_cash),0)
                + COALESCE(SUM(CASE WHEN (COALESCE(paid_card,0)+COALESCE(paid_cash,0)+COALESCE(paid_debt,0))=0
                                    THEN COALESCE(final_amount,total_amount) ELSE 0 END),0)
         FROM orders WHERE status='paid' AND ${df}) AS received,
        (SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE kind='income' AND source='debt' AND ${df}) AS debt_collected,
        (SELECT COALESCE(SUM(amount),0) FROM salary_payments WHERE ${df}) AS salary_paid,
        (SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE kind='expense' AND source IN ('salary','advance') AND ${df}) AS salary_kassa,
        (SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE kind='expense' AND source IN ('stock','supplier') AND ${df}) AS ingredient_purchases`,
      [filterDate]);
    const ex = extra.rows[0];
    const received = parseFloat(ex.received);
    const debtCollected = parseFloat(ex.debt_collected);
    const salaryPaid = parseFloat(ex.salary_paid);
    const salaryKassa = parseFloat(ex.salary_kassa);
    const ingredientPurchases = parseFloat(ex.ingredient_purchases);
    const operatingExpenses = Math.max(0, totalExpenses - ingredientPurchases - salaryKassa);
    const realized = received + debtCollected;
    const profit = realized - cogs - salaryPaid - operatingExpenses;

    res.json({
      date: filterDate,
      total_orders: salesResult.rows[0].total_orders,
      total_sales: totalSales,
      received: received,
      realized: realized,
      debt_collected: debtCollected,
      salary_paid: salaryPaid,
      total_expenses: totalExpenses,
      operating_expenses: operatingExpenses,
      cogs: cogs,
      gross_profit: totalSales - cogs,
      profit: profit,
      top_items: topItems.rows,
      waiter_sales: waiterSales.rows
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sklad holati
const getStockReport = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM ingredients ORDER BY stock_quantity ASC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Bosh sahifa (dashboard) — bitta so'rovda barcha ko'rsatkichlar
// ?period=today|week|month
const getDashboard = async (req, res) => {
  try {
    // Aniq kun tanlansa (?date=YYYY-MM-DD) — o'sha kun ko'rsatiladi
    // Kassa kuni 02:30 da yopiladi: "biznes sana" = (vaqt - 150 daqiqa) sanasi
    const dateStr = (typeof req.query.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(req.query.date)) ? req.query.date : null;
    const period = dateStr ? 'date' : (['week', 'month'].includes(req.query.period) ? req.query.period : 'today');
    const BTODAY = `((NOW() - INTERVAL '150 minutes')::date)`;
    const bd = (col) => `((${col} - INTERVAL '150 minutes')::date)`;
    const anchor = dateStr ? `'${dateStr}'::date` : BTODAY;
    const rng = (col) => period === 'week'
      ? `${bd(col)} >= ${BTODAY} - 6`
      : period === 'month'
        ? `${bd(col)} >= date_trunc('month', NOW() - INTERVAL '150 minutes')::date`
        : `${bd(col)} = ${anchor}`;

    const [sales, expenses, tables, staff, present, low, top, waiters, byDay, byHour, byStation, debtPaidAgg, salaryPaidAgg, salaryKassaAgg, ingredientPurchAgg] = await Promise.all([
      pool.query(`SELECT COUNT(*)::int AS orders, COALESCE(SUM(COALESCE(final_amount, total_amount)),0) AS sales,
                    COALESCE(SUM(paid_card),0) + COALESCE(SUM(paid_cash),0)
                    + COALESCE(SUM(CASE WHEN (COALESCE(paid_card,0)+COALESCE(paid_cash,0)+COALESCE(paid_debt,0)) = 0
                                        THEN COALESCE(final_amount, total_amount) ELSE 0 END),0) AS received
                  FROM orders WHERE status='paid' AND ${rng('created_at')}`),
      pool.query(`SELECT
                    (SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE kind='expense' AND ${rng('created_at')})
                    + (SELECT COALESCE(SUM(amount),0) FROM expenses WHERE source <> 'kassa' AND ${rng('created_at')}) AS expenses`),
      pool.query(`SELECT COUNT(*)::int AS total, COUNT(*) FILTER (WHERE status='occupied')::int AS occupied
                  FROM tables WHERE is_active=true`),
      pool.query(`SELECT COUNT(*)::int AS total FROM users WHERE is_active=true`),
      pool.query(`SELECT COUNT(DISTINCT user_id)::int AS present FROM attendance WHERE ${bd('check_in')}=${anchor}`),
      pool.query(`SELECT COUNT(*)::int AS low FROM ingredients WHERE COALESCE(min_quantity,0) > 0 AND stock_quantity <= min_quantity`),
      pool.query(`SELECT m.name, SUM(oi.quantity)::int AS qty
                  FROM order_items oi JOIN menu_items m ON oi.menu_item_id=m.id JOIN orders o ON oi.order_id=o.id
                  WHERE o.status='paid' AND ${rng('o.created_at')}
                  GROUP BY m.name ORDER BY qty DESC LIMIT 5`),
      pool.query(`SELECT u.full_name, COALESCE(SUM(COALESCE(o.final_amount, o.total_amount)),0) AS sales, COUNT(o.id)::int AS orders
                  FROM orders o JOIN users u ON o.waiter_id=u.id
                  WHERE o.status='paid' AND ${rng('o.created_at')}
                  GROUP BY u.full_name ORDER BY sales DESC LIMIT 5`),
      pool.query(`SELECT to_char(${bd('created_at')},'YYYY-MM-DD') AS d, COALESCE(SUM(COALESCE(final_amount, total_amount)),0) AS sales
                  FROM orders WHERE status='paid'
                    AND ${bd('created_at')} >= ${anchor} - 6 AND ${bd('created_at')} <= ${anchor}
                  GROUP BY ${bd('created_at')} ORDER BY ${bd('created_at')}`),
      pool.query(`SELECT EXTRACT(HOUR FROM created_at)::int AS h, COALESCE(SUM(COALESCE(final_amount, total_amount)),0) AS sales
                  FROM orders WHERE status='paid' AND ${rng('created_at')}
                  GROUP BY h ORDER BY h`),
      pool.query(`SELECT COALESCE(ps.name,'Boshqa') AS name, COALESCE(SUM(oi.price*oi.quantity),0) AS sales
                  FROM order_items oi JOIN orders o ON oi.order_id=o.id
                  JOIN menu_items m ON oi.menu_item_id=m.id
                  LEFT JOIN print_stations ps ON m.station_id=ps.id
                  WHERE o.status='paid' AND ${rng('o.created_at')}
                  GROUP BY ps.name ORDER BY sales DESC`),
      // REALIZED foyda uchun (analitika/hisobot bilan bir xil)
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions WHERE kind='income' AND source='debt' AND ${rng('created_at')}`),
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM salary_payments WHERE ${rng('created_at')}`),
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions WHERE kind='expense' AND source IN ('salary','advance') AND ${rng('created_at')}`),
      // Mahsulot xaridi (sklad+postavshik) — COGS'da hisobga olinadi, sof foydadan ikki marta ayrilmaydi
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions WHERE kind='expense' AND source IN ('stock','supplier') AND ${rng('created_at')}`),
    ]);

    const totalSales = parseFloat(sales.rows[0].sales);
    const totalReceived = parseFloat(sales.rows[0].received); // kassaga tushgan (karta+naqd, qarzsiz)
    const totalOrders = sales.rows[0].orders;
    const totalExpenses = parseFloat(expenses.rows[0].expenses);
    const cogs = await cogsForOrders(`o.status='paid' AND ${rng('o.created_at')}`);
    // SOF FOYDA = COGS asosida (egasi tasdig'i 2026-07-14):
    //   Realized − COGS − Ish haqi(to'liq) − Boshqa xarajatlar. Mahsulot xaridi COGS'da,
    //   shuning uchun boshqa xarajatlarдан chiqariladi (ikki marta emas). Qarz faqat to'langanda.
    const debtCollected = parseFloat(debtPaidAgg.rows[0].total);
    const salaryPaid = parseFloat(salaryPaidAgg.rows[0].total);
    const salaryKassa = parseFloat(salaryKassaAgg.rows[0].total);
    const ingredientPurchases = parseFloat(ingredientPurchAgg.rows[0].total);
    const operatingExpenses = Math.max(0, totalExpenses - ingredientPurchases - salaryKassa);
    const realized = totalReceived + debtCollected;
    const profit = realized - cogs - salaryPaid - operatingExpenses;

    res.json({
      period,
      date: dateStr,
      sales: totalSales,
      received: totalReceived,
      realized,
      debt_collected: debtCollected,
      salary_paid: salaryPaid,
      orders: totalOrders,
      expenses: totalExpenses,
      cogs: cogs,
      ingredient_purchases: ingredientPurchases,
      operating_expenses: operatingExpenses,
      gross_profit: totalSales - cogs,
      profit,
      avg_check: totalOrders > 0 ? Math.round(totalSales / totalOrders) : 0,
      tables: tables.rows[0],
      staff: { present: present.rows[0].present, total: staff.rows[0].total },
      low_stock: low.rows[0].low,
      top_items: top.rows,
      waiter_sales: waiters.rows,
      sales_by_day: byDay.rows,
      sales_by_hour: byHour.rows,
      sales_by_station: byStation.rows,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// KENGAYTIRILGAN ANALITIKA — davr (?period=today|week|month YOKI ?from=&to=) bo'yicha
// to'liq kesim + OLDINGI teng davr bilan taqqoslash (o'sish/pasayish %).
const getAnalytics = async (req, res) => {
  try {
    const { from_s, to_excl_s, period } = await resolveRange(req.query);
    const cur = [from_s, to_excl_s];
    const W = `status='paid' AND created_at >= $1 AND created_at < $2`;
    // oldingi teng uzunlikdagi davr: [from - (to-from), from)
    const PREV = `($1::timestamp - ($2::timestamp - $1::timestamp))`;
    const Wp = `status='paid' AND created_at >= ${PREV} AND created_at < $1::timestamp`;
    const cashExpr = `COALESCE(SUM(paid_cash),0)
      + COALESCE(SUM(CASE WHEN (COALESCE(paid_card,0)+COALESCE(paid_cash,0)+COALESCE(paid_debt,0))=0
                          THEN COALESCE(final_amount,total_amount) ELSE 0 END),0)`;
    const receivedExpr = `COALESCE(SUM(paid_card),0) + ${cashExpr}`;

    const [sumCur, sumPrev, byDay, topItems, byCat, byHour, waiters, byDish, expBreak, debtRow, expCur, expPrev, salaryAgg, bonusAgg, salaryKassaAgg, debtPaidAgg, ingredientPurchAgg] = await Promise.all([
      pool.query(`SELECT COUNT(*)::int orders, COALESCE(SUM(COALESCE(final_amount,total_amount)),0) sales,
                    ${receivedExpr} received, COALESCE(SUM(paid_card),0) card, ${cashExpr} cash,
                    COALESCE(SUM(paid_debt),0) debt,
                    COALESCE(SUM(total_amount - COALESCE(final_amount,total_amount)),0) discount
                  FROM orders WHERE ${W}`, cur),
      pool.query(`SELECT COUNT(*)::int orders, COALESCE(SUM(COALESCE(final_amount,total_amount)),0) sales,
                    ${receivedExpr} received
                  FROM orders WHERE ${Wp}`, cur),
      pool.query(`SELECT to_char((created_at - INTERVAL '150 minutes')::date,'YYYY-MM-DD') d,
                    COALESCE(SUM(COALESCE(final_amount,total_amount)),0) sales, COUNT(*)::int orders
                  FROM orders WHERE ${W}
                  GROUP BY (created_at - INTERVAL '150 minutes')::date
                  ORDER BY (created_at - INTERVAL '150 minutes')::date`, cur),
      pool.query(`SELECT m.name, SUM(oi.quantity)::int qty, COALESCE(SUM(oi.price*oi.quantity),0) amount
                  FROM order_items oi JOIN menu_items m ON oi.menu_item_id=m.id JOIN orders o ON oi.order_id=o.id
                  WHERE o.status='paid' AND o.created_at>=$1 AND o.created_at<$2
                  GROUP BY m.name ORDER BY amount DESC LIMIT 12`, cur),
      pool.query(`SELECT c.name, SUM(oi.quantity)::int qty,
                    COALESCE(SUM(oi.price*oi.quantity),0) sales,
                    COALESCE(SUM(oi.quantity * COALESCE(cc.cost,0)),0) cost
                  FROM order_items oi JOIN orders o ON oi.order_id=o.id
                  JOIN menu_items m ON oi.menu_item_id=m.id JOIN menu_categories c ON m.category_id=c.id
                  LEFT JOIN (${MENU_COST_SUBQUERY}) cc ON cc.menu_item_id = oi.menu_item_id
                  WHERE o.status='paid' AND o.created_at>=$1 AND o.created_at<$2
                  GROUP BY c.name ORDER BY sales DESC`, cur),
      pool.query(`SELECT EXTRACT(HOUR FROM created_at)::int h, COALESCE(SUM(COALESCE(final_amount,total_amount)),0) sales
                  FROM orders WHERE ${W} GROUP BY h ORDER BY h`, cur),
      pool.query(`SELECT u.full_name, COUNT(o.id)::int orders, COALESCE(SUM(COALESCE(o.final_amount,o.total_amount)),0) sales
                  FROM orders o JOIN users u ON o.waiter_id=u.id
                  WHERE o.status='paid' AND o.created_at>=$1 AND o.created_at<$2
                  GROUP BY u.full_name ORDER BY sales DESC`, cur),
      // TAOM bo'yicha iqtisod: sotildi/tushum/tannarx (COGS)/foyda/marja
      pool.query(`SELECT m.id AS menu_item_id, m.name, SUM(oi.quantity)::int qty,
                    COALESCE(SUM(oi.price*oi.quantity),0) revenue,
                    COALESCE(SUM(oi.quantity * COALESCE(c.cost,0)),0) cost
                  FROM order_items oi
                  JOIN orders o ON oi.order_id=o.id
                  JOIN menu_items m ON oi.menu_item_id=m.id
                  LEFT JOIN (${MENU_COST_SUBQUERY}) c ON c.menu_item_id = oi.menu_item_id
                  WHERE o.status='paid' AND o.created_at>=$1 AND o.created_at<$2
                  GROUP BY m.id, m.name
                  ORDER BY (COALESCE(SUM(oi.price*oi.quantity),0) - COALESCE(SUM(oi.quantity*COALESCE(c.cost,0)),0)) DESC`, cur),
      // Chiqimlar turi bo'yicha (oylik/avans/sklad/qo'lda + xarajat turlari)
      pool.query(`SELECT COALESCE(et.name,
                    CASE ct.source WHEN 'salary' THEN 'Oylik' WHEN 'advance' THEN 'Avans'
                                   WHEN 'stock' THEN 'Sklad' WHEN 'manual' THEN 'Qo''lda'
                                   WHEN 'supplier' THEN 'Postavshik' WHEN 'payable' THEN 'Kreditor'
                                   WHEN 'expense' THEN 'Boshqa'
                                   ELSE ct.source END) AS name,
                    COALESCE(SUM(ct.amount),0) AS amount
                  FROM cash_transactions ct
                  LEFT JOIN expenses e ON ct.source='expense' AND ct.ref_id=e.id
                  LEFT JOIN expense_types et ON e.expense_type_id=et.id
                  WHERE ct.kind='expense' AND ct.created_at>=$1 AND ct.created_at<$2
                  GROUP BY 1 ORDER BY amount DESC`, cur),
      // Ochiq qarzlar (davrga bog'liq emas — barcha to'lanmagan)
      pool.query(`SELECT COALESCE(SUM(amount - paid_amount),0) AS total, COUNT(*)::int AS n
                  FROM debts WHERE (amount - paid_amount) > 0.5`),
      pool.query(`SELECT (SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE kind='expense' AND created_at>=$1 AND created_at<$2)
                    + (SELECT COALESCE(SUM(amount),0) FROM expenses WHERE source<>'kassa' AND created_at>=$1 AND created_at<$2) expenses`, cur),
      pool.query(`SELECT (SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE kind='expense' AND created_at>=${PREV} AND created_at<$1::timestamp)
                    + (SELECT COALESCE(SUM(amount),0) FROM expenses WHERE source<>'kassa' AND created_at>=${PREV} AND created_at<$1::timestamp) expenses`, cur),
      // Ish haqi (oylik+avans) berildi — davr + oldingi davr (BARCHA manba: kassa va boshqa joydan)
      pool.query(`SELECT
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=$1 AND created_at<$2),0) AS cur,
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=${PREV} AND created_at<$1::timestamp),0) AS prev
                  FROM salary_payments`, cur),
      // Bonuslar berildi — davr + oldingi davr
      pool.query(`SELECT
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=$1 AND created_at<$2),0) AS cur,
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=${PREV} AND created_at<$1::timestamp),0) AS prev
                  FROM salary_bonuses`, cur),
      // Ish haqidан Kassaдан chiqqan qismi (expenses'ga ALLAQACHON kirgan — ikki marta ayirmaslik uchun)
      pool.query(`SELECT
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=$1 AND created_at<$2),0) AS cur,
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=${PREV} AND created_at<$1::timestamp),0) AS prev
                  FROM cash_transactions WHERE kind='expense' AND source IN ('salary','advance')`, cur),
      // TO'LANGAN qarzlar (davrда undirilgan) — qarz FAQAT to'langanда foydaga qo'shiladi
      pool.query(`SELECT
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=$1 AND created_at<$2),0) AS cur,
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=${PREV} AND created_at<$1::timestamp),0) AS prev
                  FROM cash_transactions WHERE kind='income' AND source='debt'`, cur),
      // Mahsulot xaridi (sklad+postavshik) — COGS'da hisobga olinadi, sof foydadan ikki marta ayrilmaydi
      pool.query(`SELECT
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=$1 AND created_at<$2),0) AS cur,
                    COALESCE(SUM(amount) FILTER (WHERE created_at>=${PREV} AND created_at<$1::timestamp),0) AS prev
                  FROM cash_transactions WHERE kind='expense' AND source IN ('stock','supplier')`, cur),
    ]);

    const cogs = await cogsForOrders(`o.status='paid' AND o.created_at >= $1 AND o.created_at < $2`, cur);
    const cogsPrev = await cogsForOrders(`o.status='paid' AND o.created_at >= ${PREV} AND o.created_at < $1::timestamp`, cur);

    // REALIZED COGS (partiya tizimi, F11): sotuv sarflari SARF PAYTIDAGI narxda —
    // narx keyin o'zgarsa ham bu raqam o'zgarmaydi (cogs esa joriy narxdan retrospektiv).
    // restore (bekor/qayta ochish) minus bo'lib kiradi — net to'g'ri.
    let cogsRealized = null;
    try {
      const cr = await pool.query(
        `SELECT COALESCE(ROUND(SUM(quantity * unit_cost), 2), 0) AS v
         FROM lot_consumptions
         WHERE reason IN ('sale','restore') AND ref_type = 'order'
           AND created_at >= $1 AND created_at < $2`, cur);
      cogsRealized = parseFloat(cr.rows[0].v);
    } catch (_) { /* partiya jadvali hali yo'q bo'lsa — null */ }

    const s = sumCur.rows[0], p = sumPrev.rows[0];
    const sales = parseFloat(s.sales), orders = s.orders, expenses = parseFloat(expCur.rows[0].expenses);
    const pSales = parseFloat(p.sales), pOrders = p.orders, pExpenses = parseFloat(expPrev.rows[0].expenses);
    const received = parseFloat(s.received), pReceived = parseFloat(p.received);

    // Ish haqi TO'LIQ (kassa+boshqa) ayiriladi (salaryPaid). Kassa qismi expenses'da edi —
    // u operatingExpenses'дан chiqariladi (pastda), shuning uchun ikki marta emas.
    const salaryPaid = parseFloat(salaryAgg.rows[0].cur), salaryPaidPrev = parseFloat(salaryAgg.rows[0].prev);
    const bonuses = parseFloat(bonusAgg.rows[0].cur), bonusesPrev = parseFloat(bonusAgg.rows[0].prev);
    const salaryKassa = parseFloat(salaryKassaAgg.rows[0].cur), salaryKassaPrev = parseFloat(salaryKassaAgg.rows[0].prev);
    // Mahsulot xaridi (sklad+postavshik) — COGS orqali hisoblanadi, "boshqa xarajatlar"дан chiqariladi.
    const ingredientPurchases = parseFloat(ingredientPurchAgg.rows[0].cur), ingredientPurchasesPrev = parseFloat(ingredientPurchAgg.rows[0].prev);
    const operatingExpenses = Math.max(0, expenses - ingredientPurchases - salaryKassa);
    const operatingExpensesPrev = Math.max(0, pExpenses - ingredientPurchasesPrev - salaryKassaPrev);

    // QARZ foydaga FAQAT to'langanда kiradi: realizatsiya = kassaga tushgan (karta+naqd, qarzsiz) + undirilgan qarz.
    // Shunday qilib to'lanmagan qarz sof foydani oshirib yubormaydi (egasi shuni so'radi).
    const debtPaid = parseFloat(debtPaidAgg.rows[0].cur), debtPaidPrev = parseFloat(debtPaidAgg.rows[0].prev);
    const realized = received + debtPaid;
    const realizedPrev = pReceived + debtPaidPrev;
    // SOF FOYDA = COGS asosida: Realized − COGS − Ish haqi(to'liq) − Boshqa xarajatlar (mahsulotsiz)
    const profit = realized - cogs - salaryPaid - operatingExpenses;
    const profitPrev = realizedPrev - cogsPrev - salaryPaidPrev - operatingExpensesPrev;

    res.json({
      period,
      summary: {
        sales, received, discount: parseFloat(s.discount), orders,
        avg_check: orders > 0 ? Math.round(sales / orders) : 0,
        cogs, gross_profit: sales - cogs, expenses, profit,
        ingredient_purchases: ingredientPurchases, // sklad+postavshik xaridi (COGS'da hisobga olingan)
        operating_expenses: operatingExpenses,     // boshqa xarajatlar (mahsulotsiz)
        cogs_realized: cogsRealized, // partiya narx-snapshotidan (tarixiy, o'zgarmas)
        salary_paid: salaryPaid, bonuses, // analitikaда ko'rsatiladi: qancha oylik/bonus berildi
        debt_collected: debtPaid,         // davrда undirilgan qarz (foydaga qo'shildi)
      },
      prev: {
        sales: pSales, orders: pOrders,
        avg_check: pOrders > 0 ? Math.round(pSales / pOrders) : 0,
        profit: profitPrev, gross_profit: pSales - cogsPrev, cogs: cogsPrev,
        salary_paid: salaryPaidPrev, bonuses: bonusesPrev,
      },
      payment: { card: parseFloat(s.card), cash: parseFloat(s.cash), debt: parseFloat(s.debt) },
      sales_by_day: byDay.rows,
      top_items: topItems.rows,
      by_category: byCat.rows,
      by_hour: byHour.rows,
      waiters: waiters.rows,
      by_dish: byDish.rows.map((r) => {
        const revenue = parseFloat(r.revenue) || 0;
        const cost = parseFloat(r.cost) || 0;
        return { menu_item_id: r.menu_item_id, name: r.name, qty: r.qty, revenue, cost, profit: revenue - cost,
                 margin: revenue > 0 ? Math.round((revenue - cost) / revenue * 100) : 0 };
      }),
      expenses_breakdown: expBreak.rows,
      debt: { total: parseFloat(debtRow.rows[0].total) || 0, count: debtRow.rows[0].n },
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Ishchilar davomati hisoboti (kun bo'yicha kelish/ketish + kechikish jarimasi)
const getAttendanceReport = async (req, res) => {
  try {
    const { date } = req.query;
    // Yashirin egasi (guest) davomat ro'yxatida faqat guest'ga ko'rinadi.
    const hideGuest = (!req.user || req.user.role !== 'guest') ? "AND r.name <> 'guest'" : '';
    // Sana berilmagan (default "bugun") -> JORIY BIZNES-KUN = oxirgi KASSA OCHILISHI kuni.
    // Shunda yarim tunда 0 ga o'tib ketmaydi: ertalab kassa ochilmaguncha oldingi (ochiq) kun ko'rinadi.
    // Kassa hech qachon ochilmagan bo'lsa -> 02:30 biznes-kun (zaxira).
    let filterDate = date;
    if (!filterDate) {
      const bd = await pool.query(
        `SELECT to_char(COALESCE(
           (SELECT (created_at - INTERVAL '150 minutes')::date FROM cash_transactions
            WHERE source = 'opening' ORDER BY created_at DESC LIMIT 1),
           (NOW() - INTERVAL '150 minutes')::date), 'YYYY-MM-DD') AS d`
      );
      filterDate = bd.rows[0].d;
    }

    // Har bir faol xodim uchun: o'sha kungi birinchi kirish va oxirgi chiqish
    const result = await pool.query(
      `SELECT u.id, u.full_name, r.name as role_name,
              to_char(u.work_start, 'HH24:MI') as work_start,
              to_char(u.work_end, 'HH24:MI') as work_end,
              COALESCE(u.late_fine_per_minute, 0) as late_fine_per_minute,
              to_char(a.first_in, 'HH24:MI') as check_in,
              to_char(a.last_out, 'HH24:MI') as check_out,
              a.first_in
       FROM users u
       JOIN roles r ON u.role_id = r.id
       LEFT JOIN (
         SELECT user_id, MIN(check_in) as first_in, MAX(check_out) as last_out
         FROM attendance
         WHERE (check_in - INTERVAL '150 minutes')::date = $1
         GROUP BY user_id
       ) a ON a.user_id = u.id
       WHERE u.is_active = true ${hideGuest}
       ORDER BY r.name, u.full_name`,
      [filterDate]
    );

    let totalFine = 0;
    const rows = result.rows.map((u) => {
      let lateMinutes = 0;
      let fine = 0;
      const came = !!u.check_in;

      if (came && u.work_start && u.check_in) {
        // HH:MM larni daqiqaga aylantirib farqni topamiz
        const [wh, wm] = u.work_start.split(':').map(Number);
        const [ch, cm] = u.check_in.split(':').map(Number);
        let diff = (ch * 60 + cm) - (wh * 60 + wm);
        // Tunda o'tuvchi smena: farqni ±12 soat oynasiga keltiramiz (yarim tundan o'tsa ham to'g'ri)
        if (diff > 720) diff -= 1440;
        else if (diff < -720) diff += 1440;
        // Faqat mantiqiy kechikish (<= 6 soat) jarimaga; kattasi — erta kelish/begona o'qish, kesamiz.
        if (diff > 0 && diff <= 360) {
          lateMinutes = diff;
          fine = lateMinutes * parseFloat(u.late_fine_per_minute);
        }
      }
      totalFine += fine;

      return {
        user_id: u.id,
        full_name: u.full_name,
        role_name: u.role_name,
        work_start: u.work_start,
        work_end: u.work_end,
        late_fine_per_minute: parseFloat(u.late_fine_per_minute),
        check_in: u.check_in,      // null bo'lsa kelmagan
        check_out: u.check_out,    // null bo'lsa hali chiqmagan
        came,
        late_minutes: lateMinutes,
        fine,
      };
    });

    res.json({
      date: filterDate,
      total_fine: totalFine,
      present_count: rows.filter((r) => r.came).length,
      absent_count: rows.filter((r) => !r.came).length,
      staff: rows,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// DAVOMAT TARIXI — davr bo'yicha, har KUN: kelish/ketish/soat/kechikish/erta ketish + jami.
//   ?from=YYYY-MM-DD&to=YYYY-MM-DD (majburiy)  &user_id= (ixtiyoriy — bitta xodim)
const getAttendanceHistory = async (req, res) => {
  try {
    const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
    const from = isDate(req.query.from) ? req.query.from : null;
    const to = isDate(req.query.to) ? req.query.to : null;
    if (!from || !to) return res.status(400).json({ message: 'from va to (YYYY-MM-DD) kerak' });
    const uid = parseInt(req.query.user_id, 10) || null;
    const hideGuest = (!req.user || req.user.role !== 'guest') ? "AND r.name <> 'guest'" : '';
    const r = await pool.query(
      `SELECT u.id, u.full_name, r.name AS role_name,
              to_char(u.work_start, 'HH24:MI') AS work_start,
              to_char(u.work_end, 'HH24:MI') AS work_end,
              to_char((a.check_in - INTERVAL '150 minutes')::date, 'YYYY-MM-DD') AS day,
              to_char(MIN(a.check_in), 'HH24:MI') AS check_in,
              to_char(MAX(a.check_out), 'HH24:MI') AS check_out,
              COALESCE(EXTRACT(EPOCH FROM SUM(a.check_out - a.check_in) FILTER (WHERE a.check_out IS NOT NULL))/3600.0, 0) AS hours
       FROM users u JOIN roles r ON u.role_id = r.id
       JOIN attendance a ON a.user_id = u.id
       WHERE (a.check_in - INTERVAL '150 minutes')::date >= $1
         AND (a.check_in - INTERVAL '150 minutes')::date <= $2
         AND u.is_active = true ${hideGuest}
         ${uid ? 'AND u.id = $3' : ''}
       GROUP BY u.id, u.full_name, r.name, u.work_start, u.work_end, (a.check_in - INTERVAL '150 minutes')::date
       ORDER BY u.full_name, day DESC`,
      uid ? [from, to, uid] : [from, to]
    );
    const toMin = (hhmm) => { if (!hhmm) return null; const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
    const byUser = {};
    for (const x of r.rows) {
      const ws = toMin(x.work_start), we = toMin(x.work_end), ci = toMin(x.check_in), co = toMin(x.check_out);
      // Tunda o'tuvchi smena uchun ±12 soat oynasiga keltiramiz (yarim tundan o'tsa ham to'g'ri)
      const norm = (d) => (d > 720 ? d - 1440 : d < -720 ? d + 1440 : d);
      const lateDiff = (ws !== null && ci !== null) ? norm(ci - ws) : 0;
      const earlyDiff = (we !== null && co !== null) ? norm(we - co) : 0;
      // Faqat mantiqiy oralig'i (<= 6 soat); kattasi — wrap artefakti (erta kelish/ketish), 0 deb olamiz.
      const late = (lateDiff > 0 && lateDiff <= 360) ? lateDiff : 0;   // kechikish (daqiqa)
      const early = (earlyDiff > 0 && earlyDiff <= 360) ? earlyDiff : 0; // erta ketish (daqiqa)
      const hours = Math.round((parseFloat(x.hours) || 0) * 100) / 100;
      const g = byUser[x.id] || (byUser[x.id] = {
        user_id: x.id, full_name: x.full_name, role_name: x.role_name,
        work_start: x.work_start, work_end: x.work_end,
        days: 0, total_hours: 0, late_days: 0, total_late_min: 0, rows: [],
      });
      g.rows.push({ day: x.day, check_in: x.check_in, check_out: x.check_out, hours, late_minutes: late, early_minutes: early });
      g.days += 1; g.total_hours += hours;
      if (late > 0) { g.late_days += 1; g.total_late_min += late; }
    }
    const staff = Object.values(byUser).map((g) => ({ ...g, total_hours: Math.round(g.total_hours * 100) / 100 }));
    res.json({ from, to, staff });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// Ish haqi (payroll) hisoboti — har bir faol xodim uchun davr bo'yicha hisoblangan maosh.
//   ?period=today|week|month   YOKI   ?from=YYYY-MM-DD&to=YYYY-MM-DD  (to — inklyuziv)
// Hisob-kitob salary_type bo'yicha:
//   percent        -> xodimning O'Z zakazlari yig'indisi * salary_value/100
//   percent_total  -> JAMI tushum (barcha paid zakaz) * salary_value/100 (kassir uchun)
//   monthly  -> salary_value (belgilangan oylik)
//   daily    -> ishlagan kun soni * salary_value
//   hourly   -> ishlagan soat * salary_value
// Kechikish jarimasi (late_fine_per_minute) har bir davomat kuni uchun ayriladi.
const getPayroll = async (req, res) => {
  try {
    // Yashirin egasi (guest super-admin) ish haqi ro'yxatida faqat guest'ning o'ziga
    // ko'rinadi (getUsers'dagi hideGuest bilan bir xil siyosat).
    const hideGuest = (!req.user || req.user.role !== 'guest') ? "AND r.name <> 'guest'" : '';
    const period = ['today', 'week', 'month'].includes(req.query.period) ? req.query.period : 'month';
    // Faqat YYYY-MM-DD formatdagi sanani qabul qilamiz, aks holda period bo'yicha hisoblanadi
    const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
    const from = isDate(req.query.from) ? req.query.from : null;
    const to = isDate(req.query.to) ? req.query.to : null;

    // Davr chegaralarini DB vaqt zonasida aniqlaymiz -> [from_s, to_excl_s)
    // Kassa kuni 02:30 da yopiladi — chegaralar 02:30 dan 02:30 gacha
    const r = await pool.query(
      `SELECT to_char(q.from_d, 'YYYY-MM-DD') || ' 02:30' AS from_s,
              to_char(q.to_d, 'YYYY-MM-DD')   || ' 02:30' AS to_excl_s,
              to_char(q.to_d - 1, 'YYYY-MM-DD')    AS to_incl_s
       FROM (
         SELECT
           CASE WHEN $1::date IS NOT NULL THEN $1::date
                WHEN $3 = 'today' THEN (NOW() - INTERVAL '150 minutes')::date
                WHEN $3 = 'week'  THEN (NOW() - INTERVAL '150 minutes')::date - 6
                ELSE date_trunc('month', NOW() - INTERVAL '150 minutes')::date END AS from_d,
           CASE WHEN $2::date IS NOT NULL THEN ($2::date + 1)
                WHEN $3 = 'today' THEN (NOW() - INTERVAL '150 minutes')::date + 1
                WHEN $3 = 'week'  THEN (NOW() - INTERVAL '150 minutes')::date + 1
                ELSE (date_trunc('month', NOW() - INTERVAL '150 minutes') + INTERVAL '1 month')::date END AS to_d
       ) q`,
      [from, to, period]
    );
    const fromS = r.rows[0].from_s;
    const toExclS = r.rows[0].to_excl_s;
    const toInclS = r.rows[0].to_incl_s;

    const periodYm = fromS.substring(0, 7); // '2026-06'
    const [emp, sales, att, adv, lastSal, fines, bonuses, overrides, pieceAgg, dailySales, manualShiftsRows, salaryMonth] = await Promise.all([
      pool.query(
        `SELECT u.id, u.full_name, r.name AS role_name,
                u.salary_type, COALESCE(u.salary_value, 0) AS salary_value,
                COALESCE(u.salary_tier_threshold, 0) AS tier_threshold,
                COALESCE(u.salary_tier_value, 0) AS tier_value,
                to_char(u.work_start, 'HH24:MI') AS work_start,
                COALESCE(u.late_fine_per_minute, 0) AS late_fine_per_minute,
                COALESCE(u.salary_day, 1) AS salary_day,
                COALESCE(u.salary_period_days, 30) AS salary_period_days
         FROM users u JOIN roles r ON u.role_id = r.id
         WHERE u.is_active = true ${hideGuest}
         ORDER BY r.name, u.full_name`
      ),
      pool.query(
        `SELECT waiter_id, COALESCE(SUM(COALESCE(final_amount, total_amount)), 0) AS sales, COUNT(*)::int AS orders
         FROM orders
         WHERE status = 'paid' AND created_at >= $1 AND created_at < $2
         GROUP BY waiter_id`,
        [fromS, toExclS]
      ),
      pool.query(
        `SELECT user_id,
                to_char((check_in - INTERVAL '150 minutes')::date, 'YYYY-MM-DD') AS day,
                to_char(MIN(check_in), 'HH24:MI') AS first_in,
                to_char(MAX(check_out), 'HH24:MI') AS last_out,
                CASE WHEN MAX(check_out) IS NOT NULL
                     THEN COALESCE(EXTRACT(EPOCH FROM SUM(LEAST(check_out - check_in, INTERVAL '16 hours')) FILTER (WHERE check_out IS NOT NULL)), 0) / 3600.0
                     ELSE 0 END AS hours,
                (MAX(check_out) IS NOT NULL) AS has_out
         FROM attendance
         WHERE check_in >= $1 AND check_in < $2
         GROUP BY user_id, (check_in - INTERVAL '150 minutes')::date
         ORDER BY 2`,
        [fromS, toExclS]
      ),
      pool.query(
        `SELECT user_id,
                COALESCE(SUM(amount), 0) AS paid,
                COALESCE(SUM(amount) FILTER (WHERE kind='advance'), 0) AS advance,
                COALESCE(SUM(amount) FILTER (WHERE kind='salary'), 0) AS salary_paid,
                COALESCE(SUM(amount) FILTER (WHERE kind='salary' AND method='card'), 0) AS salary_card,
                COALESCE(SUM(amount) FILTER (WHERE kind='salary' AND method='cash'), 0) AS salary_cash,
                BOOL_OR(kind='salary') AS salary_settled,
                to_char(MAX(created_at) FILTER (WHERE kind='salary'), 'YYYY-MM-DD') AS last_salary_date
         FROM salary_payments
         WHERE created_at >= $1 AND created_at < $2
         GROUP BY user_id`,
        [fromS, toExclS]
      ),
      // Global oxirgi oylik (sikl uchun — davrdan qat'i nazar)
      pool.query(
        `SELECT user_id,
                to_char(MAX(created_at), 'YYYY-MM-DD') AS last,
                (CURRENT_DATE - MAX(DATE(created_at)))::int AS days_since
         FROM salary_payments WHERE kind='salary'
         GROUP BY user_id`
      ),
      // Davr ichidagi qo'lda jarimalar (sabab bilan)
      pool.query(
        `SELECT user_id, COALESCE(SUM(amount), 0) AS fine
         FROM salary_fines WHERE created_at >= $1 AND created_at < $2 GROUP BY user_id`,
        [fromS, toExclS]
      ),
      // Davr ichidagi bonuslar
      pool.query(
        `SELECT user_id, COALESCE(SUM(amount), 0) AS bonus
         FROM salary_bonuses WHERE created_at >= $1 AND created_at < $2 GROUP BY user_id`,
        [fromS, toExclS]
      ),
      // Kechikish jarimasi override'lari (shu oy uchun)
      pool.query(
        `SELECT user_id, amount, reason FROM late_fine_overrides WHERE period_ym = $1`,
        [periodYm]
      ),
      // SDELNAYA (piece): har xodim uchun -> SUM(stavka * shu taom sotilgan dona)
      pool.query(
        `SELECT spr.user_id, COALESCE(SUM(spr.rate * q.qty), 0) AS piece_base
         FROM salary_piece_rates spr
         JOIN (
           SELECT oi.menu_item_id, SUM(oi.quantity) AS qty
           FROM order_items oi JOIN orders o ON o.id = oi.order_id
           WHERE o.status = 'paid' AND o.created_at >= $1 AND o.created_at < $2
           GROUP BY oi.menu_item_id
         ) q ON q.menu_item_id = spr.menu_item_id
         GROUP BY spr.user_id`,
        [fromS, toExclS]
      ),
      // Progressiv foiz uchun: har ofitsant -> KUNLIK savdo (kassa kuni 02:30)
      pool.query(
        `SELECT waiter_id,
                COALESCE(SUM(COALESCE(final_amount, total_amount)), 0) AS day_sales
         FROM orders
         WHERE status = 'paid' AND created_at >= $1 AND created_at < $2
         GROUP BY waiter_id, (created_at - INTERVAL '150 minutes')::date`,
        [fromS, toExclS]
      ),
      // Смещиклар uchun QO'LDA kiritilgan smenalar (shu oy) — Face-ID o'rniga ustun
      pool.query(
        `SELECT user_id, shifts, note FROM manual_shifts WHERE period_ym = $1`,
        [periodYm]
      ),
      // FIXED-base (monthly/shift+qo'lda) uchun: KO'RILAYOTGAN oyда (periodYm) kimga oylik berilgan.
      // Ular oyда 1 marta oylik oladi — shu oyда berilган bo'lsa "Oylik to'lash" o'chiq bo'ladi.
      pool.query(
        `SELECT DISTINCT user_id FROM salary_payments
         WHERE kind = 'salary'
           AND created_at >= date_trunc('month', ($1 || '-01')::date)
           AND created_at <  date_trunc('month', ($1 || '-01')::date) + INTERVAL '1 month'`,
        [periodYm]
      ),
    ]);

    // Oxirgi oylik xaritasi (global)
    const lastSalMap = {};
    for (const x of lastSal.rows) lastSalMap[x.user_id] = { last: x.last, daysSince: x.days_since };

    // Qo'lda jarimalar xaritasi
    const finesMap = {};
    for (const f of fines.rows) finesMap[f.user_id] = parseFloat(f.fine);

    // Bonuslar xaritasi
    const bonusMap = {};
    for (const b of bonuses.rows) bonusMap[b.user_id] = parseFloat(b.bonus);

    // Kechikish jarimasi override'lari (user_id -> {amount, reason})
    const overrideMap = {};
    for (const o of overrides.rows) overrideMap[o.user_id] = { amount: parseFloat(o.amount), reason: o.reason };

    // Ofitsant savdosi xaritasi + JAMI tushum (kassir foizi uchun)
    const salesMap = {};
    let totalSales = 0;
    for (const s of sales.rows) {
      const val = parseFloat(s.sales);
      salesMap[s.waiter_id] = { sales: val, orders: s.orders };
      totalSales += val;
    }

    // Sdelnaya (piece) bazasi: user_id -> so'm (stavka * sotilgan dona)
    const pieceMap = {};
    for (const r of pieceAgg.rows) pieceMap[r.user_id] = parseFloat(r.piece_base) || 0;

    // Progressiv foiz uchun: user_id -> [har KUNLIK savdo, ...]
    const dailySalesMap = {};
    for (const r of dailySales.rows) {
      (dailySalesMap[r.waiter_id] = dailySalesMap[r.waiter_id] || []).push(parseFloat(r.day_sales) || 0);
    }

    // QO'LDA smenalar: user_id -> {shifts, note}. Yozuv bo'lsa (0 bo'lsa ham) Face-ID o'rniga shu ishlatiladi.
    const manualShiftMap = {};
    for (const m of manualShiftsRows.rows) manualShiftMap[m.user_id] = { shifts: parseFloat(m.shifts) || 0, note: m.note };

    // Ko'rilayotgan oyда oylik berilган xodimlar (fixedBase uchun "oyда 1 marta" tekshiruvi)
    const salaryMonthSet = new Set(salaryMonth.rows.map((r) => r.user_id));

    // To'lovlar xaritasi (avans + oylik)
    const payMap = {};
    for (const a of adv.rows) {
      payMap[a.user_id] = {
        paid: parseFloat(a.paid),
        advance: parseFloat(a.advance),
        salary_paid: parseFloat(a.salary_paid),
        salary_card: parseFloat(a.salary_card),
        salary_cash: parseFloat(a.salary_cash),
        salary_settled: a.salary_settled === true,
        last_salary_date: a.last_salary_date,
      };
    }
    const todayDay = new Date().getDate();

    // Sozlама: chiqishsiz (check-out belgilanmagan) kunni oylikка qo'shamizmi? (direktor yoqadi/o'chiradi)
    // Default '1' (qo'shiladi — eski xulq). '0' bo'lsa — 0 soatli kun hisoblanmaydi/to'lanmaydi.
    let payMissingCheckout = true;
    try {
      const s = await pool.query(`SELECT value FROM app_settings WHERE key='pay_missing_checkout'`);
      if (s.rows.length && String(s.rows[0].value) === '0') payMissingCheckout = false;
    } catch (_) { /* app_settings bo'lmasa — default qo'shiladi */ }

    // Davomat: kun soni, soat va kechikish jarimasini xodim bo'yicha yig'amiz
    const acc = {};
    for (const u of emp.rows) {
      acc[u.id] = { work_start: u.work_start, late_fine: parseFloat(u.late_fine_per_minute), days: 0, hours: 0, fine: 0, hoursList: [], attList: [] };
    }
    for (const a of att.rows) {
      const e = acc[a.user_id];
      if (!e) continue;
      // Chiqishsiz kun (0 soat): sozlама o'chiq bo'lsa — kun hisoblanmaydi va to'lanmaydi (kunbay/smena
      // 0 soatga to'lamasin). Payslip'да "chiqish yo'q" bo'lib ko'rsatiladi — menejer qo'lда tuzatsin.
      if (!payMissingCheckout && a.has_out === false) {
        e.attList.push({ day: a.day, in: a.first_in, out: a.last_out, hours: 0, no_out: true });
        continue;
      }
      e.days += 1;
      e.hours += parseFloat(a.hours);
      e.hoursList.push(parseFloat(a.hours) || 0); // shift-oylik uchun HAR KUN alohida soat
      // Davomat ro'yxati (payslip'da kelish/ketish vaqti ko'rsatiladi)
      e.attList.push({ day: a.day, in: a.first_in, out: a.last_out, hours: Math.round((parseFloat(a.hours) || 0) * 100) / 100, no_out: a.has_out === false });
      if (e.work_start && a.first_in) {
        const [wh, wm] = e.work_start.split(':').map(Number);
        const [ch, cm] = a.first_in.split(':').map(Number);
        let late = (ch * 60 + cm) - (wh * 60 + wm);
        // Tunda o'tuvchi smena (masalan ish boshi 23:00, kelish 00:10): farqni ±12 soat oynasiga
        // keltiramiz, aks holda 1370 daq "kechikish" yoki manfiy chiqib jarima noto'g'ri bo'ladi.
        if (late > 720) late -= 1440;
        else if (late < -720) late += 1440;
        // Jarima faqat MANTIQIY kechikishga (<= 6 soat). Undan katta "kechikish" — aslida erta kelish
        // yoki begona Face-ID o'qishi (soat-arifmetikasi 1440 mod bilan "11 soat kech"ni "13 soat erta"dan
        // ajrata olmaydi) → xato jarima solmaslik uchun kesamiz. Kechki/kunduzgi smenaga zarar yetmasin.
        if (late > 0 && late <= 360) e.fine += late * e.late_fine;
      }
    }

    let totalBase = 0, totalFine = 0, totalNet = 0, totalAdvance = 0, totalRemaining = 0, totalPaid = 0, totalManualFine = 0, totalBonus = 0;
    const staff = emp.rows.map((u) => {
      const e = acc[u.id];
      const sv = parseFloat(u.salary_value);
      const sm = salesMap[u.id] || { sales: 0, orders: 0 };
      const hours = Math.round(e.hours * 100) / 100;
      let base = 0;
      const tierThreshold = parseFloat(u.tier_threshold) || 0;
      const tierValue = parseFloat(u.tier_value) || 0;
      switch (u.salary_type) {
        case 'percent':
          // Progressiv: chegara + oshirilgan foiz berilgan bo'lsa — HAR KUN alohida
          // (kunlik savdo > chegara ? tierValue% : salary_value%). Aks holda oddiy foiz.
          if (tierThreshold > 0 && tierValue > 0) {
            const days = dailySalesMap[u.id] || [];
            base = days.reduce((acc, d) => acc + d * ((d > tierThreshold ? tierValue : sv) / 100), 0);
          } else {
            base = sm.sales * sv / 100;
          }
          break;
        case 'percent_total': base = totalSales * sv / 100; break; // kassir: jami tushumdan foiz
        case 'piece':   base = pieceMap[u.id] || 0; break;         // sdelnaya: dona-stavka yig'indisi
        case 'shift': {
          // STAVKA (smena). sv = bir to'liq smena stavkasi (masalan 3400 so'm; 1 smena = 12 soat).
          // (1) QO'LDA smena kiritilgan bo'lsa -> base = smena_soni × stavka (Face-ID o'rniga; ishonchli).
          // (2) Aks holda Face-ID davomatдан: kun>=11:50(710daq)->1 smena; >12:00->+ortiqcha daq bonus; <11:50->0.5.
          const ms = manualShiftMap[u.id];
          if (ms) {
            base = ms.shifts * sv;
          } else {
            base = (e.hoursList || []).reduce((acc2, h) => {
              const m = (h || 0) * 60;
              if (m >= 710) return acc2 + (m > 720 ? sv + (m - 720) * (sv / 720) : sv);
              return acc2 + sv * 0.5;
            }, 0);
          }
          break;
        }
        case 'monthly': base = sv; break;
        case 'daily':   base = e.days * sv; break;
        // SOATLIK: faqat TO'LIQ soatlar hisoblanadi (egasi 2026-07-14). Chala soat (masalan 7:50)
        // to'lanmaydi → Math.floor(soat). Ish haqi = to'liq_soat × stavka.
        case 'hourly':  base = Math.floor(hours) * sv; break;
        default:        base = 0;
      }
      base = Math.round(base);
      const autoFine = Math.round(e.fine); // davomatdan hisoblangan kechikish jarimasi
      const ov = overrideMap[u.id]; // admin tahrirlagan/kechirgan bo'lsa
      const fine = ov ? Math.max(0, Math.round(ov.amount)) : autoFine;
      const net = base - fine;
      const pm = payMap[u.id] || { paid: 0, advance: 0, salary_paid: 0, salary_card: 0, salary_cash: 0, salary_settled: false, last_salary_date: null };
      const advance = Math.round(pm.advance);
      const salaryPaid = Math.round(pm.salary_paid);
      const paid = Math.round(pm.paid);
      const manualFine = Math.round(finesMap[u.id] || 0);
      const bonus = Math.round(bonusMap[u.id] || 0);
      const remaining = net + bonus - manualFine - paid; // qoldiq (bonus qo'shilib, jarima+to'lov ayrilgandan keyin)
      const salaryDay = parseInt(u.salary_day, 10) || 1;
      const periodDays = parseInt(u.salary_period_days, 10) || 30;
      const ls = lastSalMap[u.id]; // global oxirgi oylik
      const daysSince = ls ? ls.daysSince : null;
      // FIXED-base turmi? monthly — base HAR DOIM to'liq oylik (davr uzunligiga bog'liq emas);
      // shift+qo'lda smena — base = smena_soni × stavka (butun oy uchun, davrга bog'liq emas).
      // Bunday turlarda har sub-davr TO'LIQ oylikni beradi → ular OYДА 1 MARTA oylik oladi
      // (salaryMonthSet — shu oyда berilганmi). Proporsional turlar (daily/hourly/percent/piece/
      // shift-FaceID) — base davrга mos kamayadi → davr rejimида qoldiq>0 yetarli (backend overlap
      // guardi ustma-ust davrlarни to'sadi). Eski sikl faqat davr rejimi bo'lmaganда ishlaydi.
      const hasManualShift = !!manualShiftMap[u.id];
      const fixedBase = u.salary_type === 'monthly' || (u.salary_type === 'shift' && hasManualShift);
      const rangeMode = !!(from && to);
      const canPaySalary = remaining > 0 && (
        fixedBase
          ? !salaryMonthSet.has(u.id)
          : (rangeMode || daysSince === null || daysSince >= periodDays)
      );
      totalBase += base; totalFine += fine; totalNet += net;
      totalAdvance += advance; totalRemaining += remaining; totalPaid += paid; totalManualFine += manualFine; totalBonus += bonus;
      return {
        user_id: u.id,
        full_name: u.full_name,
        role_name: u.role_name,
        salary_type: u.salary_type,
        salary_value: sv,
        salary_tier_threshold: parseFloat(u.tier_threshold) || 0,
        salary_tier_value: parseFloat(u.tier_value) || 0,
        piece_base: Math.round(pieceMap[u.id] || 0),
        total_sales: sm.sales,
        total_all_sales: totalSales,
        orders_count: sm.orders,
        days_worked: e.days,      // Face-ID: davomatдан kun soni (sverka uchun)
        hours_worked: hours,      // Face-ID: davomatдан jami soat
        hours_paid: Math.floor(hours), // soatlik uchun to'langan (to'liq) soat
        attendance: e.attList,    // kunlar bo'yicha kelish/ketish vaqti (payslip'da ko'rsatiladi)
        manual_shifts: manualShiftMap[u.id] ? manualShiftMap[u.id].shifts : null, // qo'lда kiritilgan smena (null=yo'q)
        base_salary: base,
        total_fine: fine,
        auto_fine: autoFine,
        fine_overridden: !!ov,
        fine_override_reason: ov ? ov.reason : null,
        net_salary: net,
        manual_fine: manualFine,
        bonus: bonus,
        advance: advance,
        salary_paid: salaryPaid,
        salary_card: Math.round(pm.salary_card || 0),
        salary_cash: Math.round(pm.salary_cash || 0),
        paid: paid,
        remaining: remaining,
        salary_day: salaryDay,
        salary_period_days: periodDays,
        salary_settled: pm.salary_settled,
        last_salary_date: pm.last_salary_date,
        last_salary_global: ls ? ls.last : null,
        days_since_salary: daysSince,
        can_pay_salary: canPaySalary,
      };
    });

    res.json({
      period: (from && to) ? 'custom' : period,
      from: fromS,
      to: toInclS,
      total_base: totalBase,
      total_fine: totalFine,
      total_net: totalNet,
      total_advance: totalAdvance,
      total_manual_fine: totalManualFine,
      total_bonus: totalBonus,
      total_paid: totalPaid,
      total_remaining: totalRemaining,
      count: staff.length,
      staff,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Ish haqi DAVRLAR tarixi (period_days kunlik, odatda 10) — BITTA xodim uchun
// oxirgi N davr. Har davr: sana oralig'i, avans, oylik, jami to'langan, holat
// (to'langan/qisman/ochiq). "Davrlarni kuzatish + oplacheno belgisi" (egasi 2026-07-13).
//   ?user_id= (majburiy)  &count=N (default 6, max 24)
const getPayrollPeriods = async (req, res) => {
  try {
    const userId = parseInt(req.query.user_id, 10);
    if (!userId) return res.status(400).json({ message: 'user_id kerak' });
    const u = await pool.query(
      `SELECT full_name, COALESCE(salary_period_days, 10) AS p FROM users WHERE id = $1`, [userId]);
    if (!u.rows.length) return res.status(404).json({ message: 'Xodim topilmadi' });
    const p = Math.max(1, parseInt(u.rows[0].p, 10) || 10);
    const count = Math.min(24, Math.max(1, parseInt(req.query.count, 10) || 6));

    // Biznes-kun (02:30). Har to'lovni davr (bucket) ga ajratamiz: bucket 0 — joriy davr.
    const [pays, todayRow] = await Promise.all([
      pool.query(
        `SELECT id, amount, method, kind, note, source,
                to_char(created_at, 'YYYY-MM-DD') AS date,
                (((NOW() - INTERVAL '150 minutes')::date) - ((created_at - INTERVAL '150 minutes')::date))::int AS age_days
         FROM salary_payments
         WHERE user_id = $1
           AND (created_at - INTERVAL '150 minutes')::date > (NOW() - INTERVAL '150 minutes')::date - ($2::int * $3::int)
         ORDER BY created_at DESC, id DESC`,
        [userId, p, count]),
      pool.query(`SELECT to_char((NOW() - INTERVAL '150 minutes')::date, 'YYYY-MM-DD') AS today`),
    ]);
    const today = todayRow.rows[0].today;
    const addDays = (ymd, n) => {
      const d = new Date(ymd + 'T00:00:00Z');
      d.setUTCDate(d.getUTCDate() + n);
      return d.toISOString().slice(0, 10);
    };

    const periods = [];
    for (let b = 0; b < count; b++) {
      const toD = addDays(today, -b * p);
      periods.push({ index: b, from: addDays(toD, -(p - 1)), to: toD,
        advance: 0, salary: 0, paid: 0, settled: false, count: 0, payments: [] });
    }
    for (const r of pays.rows) {
      const b = Math.floor(r.age_days / p);
      if (b < 0 || b >= count) continue;
      const per = periods[b];
      const amt = parseFloat(r.amount) || 0;
      if (r.kind === 'salary') { per.salary += amt; per.settled = true; } else per.advance += amt;
      per.paid += amt;
      per.count += 1;
      per.payments.push({ id: r.id, amount: amt, method: r.method, kind: r.kind, note: r.note, date: r.date });
    }
    for (const per of periods) {
      per.advance = Math.round(per.advance);
      per.salary = Math.round(per.salary);
      per.paid = Math.round(per.paid);
    }
    res.json({ user_id: userId, full_name: u.rows[0].full_name, period_days: p, count, today, periods });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// To'lov qo'shish (avans yoki oylik) — body: { user_id, amount, method, kind, note?, date? }
//   kind: 'advance' | 'salary' (default advance);  method: 'card' | 'cash' (default cash)
// Oylik (kind='salary') monthly xodimga to'lov kunidan keyin va oyda bir marta beriladi.
// Har to'lov Kassa'ga CHIQIM bo'lib tushadi.
const addSalaryPayment = async (req, res) => {
  const client = await pool.connect();
  try {
    const { user_id, amount, note, date } = req.body;
    const amt = parseFloat(amount);
    if (!user_id || !(amt > 0)) {
      return res.status(400).json({ message: 'user_id va musbat amount kerak' });
    }
    const kind = req.body.kind === 'salary' ? 'salary' : 'advance';
    const method = req.body.method === 'card' ? 'card' : 'cash';
    const isDate = typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date);
    // Pul manbasi: Kassadan (default) yoki boshqa joydan. Boshqa bo'lsa Kassadan minus bo'lmaydi.
    const fromKassa = req.body.from_kassa !== false && req.body.from_kassa !== 'false';
    const sourceText = fromKassa ? 'kassa' : ((req.body.source || '').toString().trim().slice(0, 120) || 'boshqa');
    // DAVR REJIMI: aniq davr (period_from..period_to, masalan 1–10 iyul) tanlab to'lansa.
    const isYmd = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
    const rangeMode = isYmd(req.body.period_from) && isYmd(req.body.period_to);

    await client.query('BEGIN');
    // Xodim qatorini qulflash — parallel ikki oylik to'lovi bir-birini kutadi (poyga yo'q):
    // ikkinchi tranzaksiya birinchisi COMMIT qilgan yozuvni ko'radi va overlap/sikl guardга tushadi.
    await client.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [user_id]);

    // To'lov QAMROVI (period_from..period_to) — quyida oylik guardida to'ldiriladi, INSERTда saqlanadi.
    let covFrom = null;
    let covTo = null;

    // OYLIK IKKI MARTA TO'LASH HIMOYASI (kind='salary'). Avans (kind='advance') cheklanmaydi.
    if (kind === 'salary') {
      const u = await client.query(`SELECT salary_type, COALESCE(salary_period_days,30) AS period FROM users WHERE id=$1`, [user_id]);
      const salaryType = u.rows.length ? u.rows[0].salary_type : null;
      const period = u.rows.length ? (parseInt(u.rows[0].period, 10) || 30) : 30;

      if (rangeMode) {
        // FIXED-base turmi? monthly, yoki shift+qo'lda smena (period_from oyи uchun manual_shifts bор).
        // Bunda base butun OYni ifodalaydi (davr uzunligiga bog'liq emas).
        let fixedBase = salaryType === 'monthly';
        if (!fixedBase && salaryType === 'shift') {
          const pym = req.body.period_from.slice(0, 7);
          const ms = await client.query(`SELECT 1 FROM manual_shifts WHERE user_id=$1 AND period_ym=$2 LIMIT 1`, [user_id, pym]);
          fixedBase = ms.rows.length > 0;
        }
        // QAMROV davri: proporsional — aynan tanlangan davr; fixedBase — butun OY (o'sha oyда 1 marta).
        covFrom = req.body.period_from;
        covTo = req.body.period_to;
        if (fixedBase) {
          const mb = await client.query(
            `SELECT to_char(date_trunc('month', $1::date), 'YYYY-MM-DD') AS mfrom,
                    to_char((date_trunc('month', $1::date) + INTERVAL '1 month - 1 day')::date, 'YYYY-MM-DD') AS mto`,
            [req.body.period_from]);
          covFrom = mb.rows[0].mfrom;
          covTo = mb.rows[0].mto;
        }
        // OVERLAP guardi: shu xodimda QAMROVI kesishadigan oylik bор bo'lsa rad etamiz.
        //   proporsional: disjoint davrlar (1-10, 11-20) kesishmaydi → ruxsat; ustma-ust → rad.
        //   fixedBase: har ikki to'lov butun oy qamrovi → o'sha oyда ikkinchisi kesishadi → rad (oyда 1 marta).
        //   FOR UPDATE tufayli parallel/reopen poygalari to'g'ri serializatsiya qilinadi.
        //   Eski (period ustunsiz) yozuvlar uchun created_at oynasi bilan fallback.
        const ov = await client.query(
          `SELECT 1 FROM salary_payments
           WHERE user_id = $1 AND kind = 'salary'
             AND (
               (period_from IS NOT NULL AND period_from <= $3::date AND period_to >= $2::date)
               OR (period_from IS NULL AND created_at >= $2::date AND created_at < ($3::date + 1))
             )
           LIMIT 1`,
          [user_id, covFrom, covTo]
        );
        if (ov.rows.length) {
          await client.query('ROLLBACK');
          const msg = fixedBase
            ? `Bu oyga (${req.body.period_from.slice(0, 7)}) oylik allaqachon berilgan. Qo'shimcha kerak bo'lsa avans bering yoki oldingi to'lovni o'chiring.`
            : `Bu davr (${req.body.period_from} — ${req.body.period_to}) allaqachon to'langan davr bilan kesishadi. Kesishmaydigan davr tanlang, avans bering yoki oldingi to'lovni o'chiring.`;
          return res.status(400).json({ message: msg });
        }
      } else {
        // DAVR REJIMI EMAS (period=today/week/month): eski SIKL — oxirgi oylikdan period kun o'tsa
        const last = await client.query(
          `SELECT (CURRENT_DATE - MAX(DATE(created_at)))::int AS days_since
           FROM salary_payments WHERE user_id=$1 AND kind='salary'`, [user_id]);
        const daysSince = (last.rows[0] && last.rows[0].days_since !== null) ? last.rows[0].days_since : null;
        if (daysSince !== null && daysSince < period) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            message: `Oylik har ${period} kunda beriladi. Oxirgisidan ${daysSince} kun o'tdi — ${period - daysSince} kundan keyin mumkin. Hozir faqat avans.`,
          });
        }
      }
    }

    const r = await client.query(
      `INSERT INTO salary_payments (user_id, amount, method, kind, note, source, period_from, period_to, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $8::date, $9::date, COALESCE($7::date + INTERVAL '12 hours', NOW()))
       RETURNING id, user_id, amount, method, kind, note, source, to_char(created_at,'YYYY-MM-DD') AS date`,
      [user_id, amt, method, kind, note || null, sourceText, isDate ? date : null, covFrom, covTo]
    );
    const pay = r.rows[0];
    // Faqat Kassadan to'langanda Kassa balansidan chiqim qilamiz.
    // created_at TO'LOV sanasi bilan bir xil (backdate bo'lsa ham) — aks holда analitikada
    // salary_payments (o'tgan davr) va cash_transactions (bugun) turli davrga tushib, mehnat xarajati ikki bo'linardi.
    if (fromKassa) {
      // Kassa chiqimi HAR DOIM to'lov qilingan KUN (NOW = bugun) bilan yoziladi — pul aynan bugun
      // kassadan chiqadi, shuning uchun egasi uni Kassa/Rasxodlardа o'sha kuni ko'radi (davr uchun
      // orqага sana qo'yilса, chiqim o'tgan kunга tushib "yo'qolgandек" ko'rinardi). Analitikada
      // mehnat xarajati DAVR bo'yicha salary_payments'дан ayiriladi, cash_tx (source=salary) esa
      // operatingExpenses'да neytrallanadi — ikki marta hisob YO'Q (COGS-modeli).
      await client.query(
        `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
         VALUES ('expense', $1, $2, $3, $4, $5)`,
        [method, amt, kind, pay.id, kind === 'salary' ? 'Oylik' : 'Avans']
      );
    }
    await client.query('COMMIT');
    res.status(201).json(pay);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// To'lovlar ro'yxati — ?user_id=&from=YYYY-MM-DD&to=YYYY-MM-DD (to inklyuziv)
const listSalaryPayments = async (req, res) => {
  try {
    const { user_id, from, to } = req.query;
    const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
    const conds = [];
    const params = [];
    if (user_id) { params.push(user_id); conds.push(`user_id = $${params.length}`); }
    if (isDate(from)) { params.push(from); conds.push(`created_at >= $${params.length}::timestamp`); }
    if (isDate(to)) { params.push(to); conds.push(`created_at < ($${params.length}::date + 1)`); }
    const where = conds.length ? 'WHERE ' + conds.join(' AND ') : '';
    const r = await pool.query(
      `SELECT id, user_id, amount, method, kind, note, source, to_char(created_at, 'YYYY-MM-DD') AS date
       FROM salary_payments ${where}
       ORDER BY created_at DESC, id DESC`,
      params
    );
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// To'lovni o'chirish (+ Kassa yozuvini ham)
const deleteSalaryPayment = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`DELETE FROM cash_transactions WHERE source IN ('advance','salary') AND ref_id = $1`, [req.params.id]);
    await client.query('DELETE FROM salary_payments WHERE id = $1', [req.params.id]);
    await client.query('COMMIT');
    res.json({ message: 'deleted' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// ── QO'LDA JARIMA (manual fine) — maoshdan ayriladi, Kassa'ga tegmaydi ──
const addSalaryFine = async (req, res) => {
  try {
    const { user_id, amount, reason, date } = req.body;
    const amt = parseFloat(amount);
    if (!user_id || !(amt > 0)) {
      return res.status(400).json({ message: 'user_id va musbat amount kerak' });
    }
    const isDate = typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date);
    const r = await pool.query(
      `INSERT INTO salary_fines (user_id, amount, reason, created_at)
       VALUES ($1, $2, $3, COALESCE($4::date + INTERVAL '12 hours', NOW()))
       RETURNING id, user_id, amount, reason, to_char(created_at, 'YYYY-MM-DD') AS date`,
      [user_id, amt, (reason || '').toString().trim().slice(0, 200) || null, isDate ? date : null]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const listSalaryFines = async (req, res) => {
  try {
    const { user_id, from, to } = req.query;
    const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
    const conds = [];
    const params = [];
    if (user_id) { params.push(user_id); conds.push(`user_id = $${params.length}`); }
    if (isDate(from)) { params.push(from); conds.push(`created_at >= $${params.length}::timestamp`); }
    if (isDate(to)) { params.push(to); conds.push(`created_at < ($${params.length}::date + 1)`); }
    const where = conds.length ? 'WHERE ' + conds.join(' AND ') : '';
    const r = await pool.query(
      `SELECT id, user_id, amount, reason, to_char(created_at, 'YYYY-MM-DD') AS date
       FROM salary_fines ${where} ORDER BY created_at DESC, id DESC`,
      params
    );
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const deleteSalaryFine = async (req, res) => {
  try {
    await pool.query('DELETE FROM salary_fines WHERE id = $1', [req.params.id]);
    res.json({ message: 'deleted' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ── BONUS — maoshga QO'SHILADI (summa yoki foiz; foizni front hisoblab amount yuboradi) ──
const addSalaryBonus = async (req, res) => {
  try {
    const { user_id, amount, percent, reason, date } = req.body;
    const amt = parseFloat(amount);
    if (!user_id || !(amt > 0)) {
      return res.status(400).json({ message: 'user_id va musbat amount kerak' });
    }
    const pct = (percent !== undefined && percent !== null && percent !== '') ? parseFloat(percent) : null;
    const isDate = typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date);
    const r = await pool.query(
      `INSERT INTO salary_bonuses (user_id, amount, percent, reason, created_at)
       VALUES ($1, $2, $3, $4, COALESCE($5::date + INTERVAL '12 hours', NOW()))
       RETURNING id, user_id, amount, percent, reason, to_char(created_at, 'YYYY-MM-DD') AS date`,
      [user_id, amt, pct, (reason || '').toString().trim().slice(0, 200) || null, isDate ? date : null]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const listSalaryBonuses = async (req, res) => {
  try {
    const { user_id, from, to } = req.query;
    const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
    const conds = [];
    const params = [];
    if (user_id) { params.push(user_id); conds.push(`user_id = $${params.length}`); }
    if (isDate(from)) { params.push(from); conds.push(`created_at >= $${params.length}::timestamp`); }
    if (isDate(to)) { params.push(to); conds.push(`created_at < ($${params.length}::date + 1)`); }
    const where = conds.length ? 'WHERE ' + conds.join(' AND ') : '';
    const r = await pool.query(
      `SELECT id, user_id, amount, percent, reason, to_char(created_at, 'YYYY-MM-DD') AS date
       FROM salary_bonuses ${where} ORDER BY created_at DESC, id DESC`,
      params
    );
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const deleteSalaryBonus = async (req, res) => {
  try {
    await pool.query('DELETE FROM salary_bonuses WHERE id = $1', [req.params.id]);
    res.json({ message: 'deleted' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ── KECHIKISH JARIMASINI tahrirlash / kechirish (oy bo'yicha override) ──
const setLateFineOverride = async (req, res) => {
  try {
    const { user_id, period_ym, amount, reason } = req.body;
    if (!user_id || !/^\d{4}-\d{2}$/.test((period_ym || '').toString())) {
      return res.status(400).json({ message: 'user_id va period_ym (YYYY-MM) kerak' });
    }
    const amt = Math.max(0, parseFloat(amount) || 0);
    const r = await pool.query(
      `INSERT INTO late_fine_overrides (user_id, period_ym, amount, reason)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, period_ym)
       DO UPDATE SET amount = EXCLUDED.amount, reason = EXCLUDED.reason, created_at = NOW()
       RETURNING id, user_id, period_ym, amount, reason`,
      [user_id, period_ym, amt, (reason || '').toString().trim().slice(0, 200) || null]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Override'ni olib tashlash → kechikish jarimasi yana avtomatik hisoblanadi
const deleteLateFineOverride = async (req, res) => {
  try {
    const { user_id, period_ym } = req.query;
    if (user_id && /^\d{4}-\d{2}$/.test((period_ym || '').toString())) {
      await pool.query('DELETE FROM late_fine_overrides WHERE user_id = $1 AND period_ym = $2', [user_id, period_ym]);
    } else {
      await pool.query('DELETE FROM late_fine_overrides WHERE id = $1', [req.params.id]);
    }
    res.json({ message: 'deleted' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// QO'LDA smena (смещик) — oy bo'yicha nechta smena ishlaganini kiritish/yangilash (upsert).
// getPayroll shift-hisobi shu yozuvni Face-ID o'rniga ustun ishlatadi (Face-ID ishonchsiz bo'lganда).
const setManualShifts = async (req, res) => {
  try {
    const { user_id, period_ym, shifts, note } = req.body;
    if (!user_id || !/^\d{4}-\d{2}$/.test((period_ym || '').toString())) {
      return res.status(400).json({ message: 'user_id va period_ym (YYYY-MM) kerak' });
    }
    const sh = Math.max(0, parseFloat(shifts) || 0);
    const r = await pool.query(
      `INSERT INTO manual_shifts (user_id, period_ym, shifts, note)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, period_ym)
       DO UPDATE SET shifts = EXCLUDED.shifts, note = EXCLUDED.note, updated_at = NOW()
       RETURNING id, user_id, period_ym, shifts, note`,
      [user_id, period_ym, sh, (note || '').toString().trim().slice(0, 200) || null]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// QO'LDA smenani olib tashlash (yana Face-ID bo'yicha hisoblanadi)
const deleteManualShifts = async (req, res) => {
  try {
    const { user_id, period_ym } = req.query;
    if (user_id && /^\d{4}-\d{2}$/.test((period_ym || '').toString())) {
      await pool.query('DELETE FROM manual_shifts WHERE user_id = $1 AND period_ym = $2', [user_id, period_ym]);
    } else {
      await pool.query('DELETE FROM manual_shifts WHERE id = $1', [req.params.id]);
    }
    res.json({ message: 'deleted' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// QO'LDA smenalar ro'yxati — ?period_ym=YYYY-MM [&user_id=]
const getManualShifts = async (req, res) => {
  try {
    const { period_ym, user_id } = req.query;
    const conds = [], params = [];
    if (period_ym) { params.push(period_ym); conds.push(`period_ym = $${params.length}`); }
    if (user_id) { params.push(user_id); conds.push(`user_id = $${params.length}`); }
    const where = conds.length ? 'WHERE ' + conds.join(' AND ') : '';
    const r = await pool.query(`SELECT user_id, period_ym, shifts, note FROM manual_shifts ${where}`, params);
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ── KASSA ──
// Davr chegarasini aniqlash yordamchisi -> { from_s, to_excl_s, to_incl_s }
// KASSA KUNI 02:30 da yopiladi (00:00 emas): "biznes kun" = (hozir - 150 daqiqa) sanasi.
// Kun X chegaralari: [X 02:30, X+1 02:30). Yarim tundan keyingi (00:00-02:30)
// zakazlar o'sha KECHAGI kunga yoziladi.
const resolveRange = async (query) => {
  const period = ['today', 'week', 'month'].includes(query.period) ? query.period : 'today';
  const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
  const from = isDate(query.from) ? query.from : null;
  const to = isDate(query.to) ? query.to : null;
  const r = await pool.query(
    `SELECT to_char(q.from_d,'YYYY-MM-DD') || ' 02:30' AS from_s,
            to_char(q.to_d,'YYYY-MM-DD')   || ' 02:30' AS to_excl_s,
            to_char(q.to_d - 1,'YYYY-MM-DD') AS to_incl_s
     FROM (
       SELECT
         CASE WHEN $1::date IS NOT NULL THEN $1::date
              WHEN $3='week'  THEN (NOW() - INTERVAL '150 minutes')::date - 6
              WHEN $3='month' THEN date_trunc('month', NOW() - INTERVAL '150 minutes')::date
              ELSE (NOW() - INTERVAL '150 minutes')::date END AS from_d,
         CASE WHEN $2::date IS NOT NULL THEN ($2::date + 1)
              WHEN $3='week'  THEN (NOW() - INTERVAL '150 minutes')::date + 1
              WHEN $3='month' THEN (date_trunc('month', NOW() - INTERVAL '150 minutes') + INTERVAL '1 month')::date
              ELSE (NOW() - INTERVAL '150 minutes')::date + 1 END AS to_d
     ) q`,
    [from, to, period]
  );
  return { ...r.rows[0], period: (from && to) ? 'custom' : period };
};

// Kassa holati: davr bo'yicha tushum/chiqim (karta/naqd), qoldiq, qarzdorlar, tranzaksiyalar
const getCashbox = async (req, res) => {
  try {
    const { from_s, to_excl_s, to_incl_s, period } = await resolveRange(req.query);

    const [agg, txs, debtors, debtTotal, openingRes] = await Promise.all([
      pool.query(
        `SELECT kind, method, COALESCE(SUM(amount),0) AS total
         FROM cash_transactions WHERE created_at >= $1 AND created_at < $2 AND source <> 'opening'
         GROUP BY kind, method`, [from_s, to_excl_s]),
      pool.query(
        `SELECT id, kind, method, amount, source, ref_id, note,
                to_char(created_at,'YYYY-MM-DD HH24:MI') AS at
         FROM cash_transactions WHERE created_at >= $1 AND created_at < $2
         ORDER BY created_at DESC, id DESC LIMIT 100`, [from_s, to_excl_s]),
      pool.query(
        `SELECT id, order_id, debtor_name, amount, paid_amount, (amount - paid_amount) AS remaining,
                to_char(created_at,'YYYY-MM-DD') AS date
         FROM debts WHERE (amount - paid_amount) > 0.5
         ORDER BY created_at DESC`),
      pool.query(`SELECT COALESCE(SUM(amount - paid_amount),0) AS outstanding, COUNT(*)::int AS cnt
                  FROM debts WHERE (amount - paid_amount) > 0.5`),
      // Kassa ochilish qoldig'i — davr ichidagi OXIRGI opening (SUM emas!).
      // Hafta/oy davrida har kunning opening'i ~ o'tgan kun qoldig'i, ularni QO'SHISH
      // net.cash'ni ko'p marta shishiradi. Bir kun uchun ham bitta qiymat.
      pool.query(`SELECT COALESCE(amount,0) AS o FROM cash_transactions
                  WHERE source = 'opening' AND created_at >= $1 AND created_at < $2
                  ORDER BY created_at DESC LIMIT 1`, [from_s, to_excl_s]),
    ]);

    const m = { income: { card: 0, cash: 0 }, expense: { card: 0, cash: 0 } };
    for (const r of agg.rows) {
      if (m[r.kind] && (r.method === 'card' || r.method === 'cash')) {
        m[r.kind][r.method] = parseFloat(r.total);
      }
    }
    const incomeTotal = m.income.card + m.income.cash;
    const expenseTotal = m.expense.card + m.expense.cash;
    const opening = openingRes.rows.length ? (parseFloat(openingRes.rows[0].o) || 0) : 0; // kassa ochilish qoldig'i (naqd)
    // Ochilish qoldig'i FAQAT bitta kun uchun mantiqiy (ochilish + bugun kirim − chiqim = hozirgi kassa).
    // Hafta/oy davrida bu bir kunning ochilishi — uni butun davr oqimiga qo'shsak "soxta qoldiq" chiqadi.
    // Shuning uchun ko'p kunlik davrda net = davr sof pul oqimi (ochilishsiz), bir kunlik davrda = qoldiq.
    const singleDay = from_s.slice(0, 10) === to_incl_s;
    const openApplied = singleDay ? opening : 0;

    res.json({
      period, from: from_s, to: to_incl_s,
      opening,
      single_day: singleDay,
      income:  { card: m.income.card,  cash: m.income.cash,  total: incomeTotal },
      expense: { card: m.expense.card, cash: m.expense.cash, total: expenseTotal },
      net:     { card: m.income.card - m.expense.card, cash: m.income.cash - m.expense.cash + openApplied, total: incomeTotal - expenseTotal + openApplied },
      debt:    { outstanding: parseFloat(debtTotal.rows[0].outstanding), count: debtTotal.rows[0].cnt },
      transactions: txs.rows,
      debtors: debtors.rows,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Qo'lda kirim/chiqim qo'shish (kassa tuzatish) — body: { kind, method, amount, note }
const addCashTransaction = async (req, res) => {
  try {
    const k = req.body.kind === 'expense' ? 'expense' : 'income';
    const meth = req.body.method === 'card' ? 'card' : 'cash';
    const amt = Math.round(parseFloat(req.body.amount) || 0);
    if (!(amt > 0)) return res.status(400).json({ message: 'Musbat summa kerak' });
    const note = (req.body.note || '').toString().trim().slice(0, 200) || null;
    const r = await pool.query(
      `INSERT INTO cash_transactions (kind, method, amount, source, note)
       VALUES ($1, $2, $3, 'manual', $4) RETURNING id`,
      [k, meth, amt, note]
    );
    res.status(201).json({ id: r.rows[0].id });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Kassa ochilish qoldig'i — bugungi opening'ni o'rnatadi (mavjud bo'lsa almashtiradi)
const setOpeningBalance = async (req, res) => {
  try {
    const amt = Math.round(parseFloat(req.body.amount) || 0);
    if (!(amt >= 0)) return res.status(400).json({ message: 'Summa noto\'g\'ri' });
    const note = (req.body.note || '').toString().trim().slice(0, 200) || 'Kassa ochilishi';
    // Biznes kun 02:30 da almashadi — "bugungi" ochilish shu kun bo'yicha
    await pool.query(`DELETE FROM cash_transactions WHERE source = 'opening'
                      AND (created_at - INTERVAL '150 minutes')::date = (NOW() - INTERVAL '150 minutes')::date`);
    const r = await pool.query(
      `INSERT INTO cash_transactions (kind, method, amount, source, note)
       VALUES ('income', 'cash', $1, 'opening', $2) RETURNING id`,
      [amt, note]
    );
    res.status(201).json({ id: r.rows[0].id, amount: amt });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Tranzaksiyani o'chirish (faqat qo'lda kiritilganlar)
const deleteCashTransaction = async (req, res) => {
  try {
    await pool.query(`DELETE FROM cash_transactions WHERE id = $1 AND source = 'manual'`, [req.params.id]);
    res.json({ message: 'ok' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Qarz to'lash — body: { amount, method }
const payDebt = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const amt = Math.round(parseFloat(req.body.amount) || 0);
    const meth = req.body.method === 'card' ? 'card' : 'cash';
    if (!(amt > 0)) return res.status(400).json({ message: 'Musbat summa kerak' });
    await client.query('BEGIN');
    // FOR UPDATE — ikki parallel to'lov bir qarzni ikki marta yopa olmaydi
    const d = await client.query('SELECT * FROM debts WHERE id = $1 FOR UPDATE', [id]);
    if (d.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Qarz topilmadi' });
    }
    const debt = d.rows[0];
    const remaining = Math.round(parseFloat(debt.amount) - parseFloat(debt.paid_amount));
    const pay = Math.min(amt, remaining);
    if (pay <= 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Qarz allaqachon to\'langan' });
    }
    await client.query('UPDATE debts SET paid_amount = paid_amount + $1 WHERE id = $2', [pay, id]);
    await client.query(
      `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
       VALUES ('income', $1, $2, 'debt', $3, $4)`,
      [meth, pay, id, `Qarz: ${debt.debtor_name}`]
    );
    await client.query('COMMIT');
    res.json({ message: 'ok', paid: pay });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Moliyaviy hisobot — davr bo'yicha (kunlik/haftalik/oylik yoki from/to)
const getReport = async (req, res) => {
  try {
    const { from_s, to_excl_s, to_incl_s, period } = await resolveRange(req.query);

    const [sales, pays, exp, top, waiters, byDay, expList, debtorRows, discRows, orderRows, catDishes, expKassaAgg, expOtherAgg, debtPaidAgg, salaryPaidAgg, salaryKassaAgg, ingredientPurchAgg] = await Promise.all([
      pool.query(
        `SELECT COUNT(*)::int AS orders, COALESCE(SUM(COALESCE(final_amount, total_amount)),0) AS sales
         FROM orders WHERE status='paid' AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      pool.query(
        `SELECT COALESCE(SUM(paid_card),0) AS card,
                COALESCE(SUM(paid_cash),0)
                  + COALESCE(SUM(CASE WHEN (COALESCE(paid_card,0)+COALESCE(paid_cash,0)+COALESCE(paid_debt,0)) = 0
                                      THEN COALESCE(final_amount,total_amount) ELSE 0 END),0) AS cash,
                COALESCE(SUM(paid_debt),0) AS debt,
                COALESCE(SUM(total_amount - COALESCE(final_amount,total_amount)),0) AS discount
         FROM orders WHERE status='paid' AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      // Kassadan ketgan BARCHA chiqimlar (xarajat + oylik/avans + sklad + qo'lda) — boyitilgan
      pool.query(
        `SELECT ct.source, ct.method, ct.amount, ct.note,
                to_char(ct.created_at,'YYYY-MM-DD HH24:MI') AS dt,
                et.name AS expense_type, su.full_name AS staff_name, sup.name AS supplier_name
         FROM cash_transactions ct
         LEFT JOIN expenses e ON ct.source='expense' AND ct.ref_id = e.id
         LEFT JOIN expense_types et ON e.expense_type_id = et.id
         LEFT JOIN salary_payments sp ON ct.source IN ('salary','advance') AND ct.ref_id = sp.id
         LEFT JOIN users su ON sp.user_id = su.id
         LEFT JOIN supplier_payments spp ON ct.source='supplier' AND ct.ref_id = spp.id
         LEFT JOIN suppliers sup ON spp.supplier_id = sup.id
         WHERE ct.kind='expense' AND ct.created_at >= $1 AND ct.created_at < $2
         ORDER BY ct.created_at DESC LIMIT 300`, [from_s, to_excl_s]),
      pool.query(
        `SELECT m.name, SUM(oi.quantity)::int AS qty, COALESCE(SUM(oi.price*oi.quantity),0) AS amount
         FROM order_items oi JOIN menu_items m ON oi.menu_item_id=m.id JOIN orders o ON oi.order_id=o.id
         WHERE o.status='paid' AND o.created_at >= $1 AND o.created_at < $2
         GROUP BY m.name ORDER BY qty DESC LIMIT 10`, [from_s, to_excl_s]),
      pool.query(
        `SELECT u.full_name, COUNT(o.id)::int AS orders, COALESCE(SUM(COALESCE(o.final_amount,o.total_amount)),0) AS sales
         FROM orders o JOIN users u ON o.waiter_id=u.id
         WHERE o.status='paid' AND o.created_at >= $1 AND o.created_at < $2
         GROUP BY u.full_name ORDER BY sales DESC`, [from_s, to_excl_s]),
      pool.query(
        `SELECT to_char((created_at - INTERVAL '150 minutes')::date,'YYYY-MM-DD') AS d, COALESCE(SUM(COALESCE(final_amount,total_amount)),0) AS sales
         FROM orders WHERE status='paid' AND created_at >= $1 AND created_at < $2
         GROUP BY (created_at - INTERVAL '150 minutes')::date ORDER BY (created_at - INTERVAL '150 minutes')::date`, [from_s, to_excl_s]),
      // Kassadan TASHQARI xarajatlar (boshqa manbadan)
      pool.query(
        `SELECT e.name, et.name AS expense_type, e.amount, e.method,
                to_char(e.created_at,'YYYY-MM-DD HH24:MI') AS dt
         FROM expenses e JOIN expense_types et ON e.expense_type_id=et.id
         WHERE e.source <> 'kassa' AND e.created_at >= $1 AND e.created_at < $2
         ORDER BY e.created_at DESC`, [from_s, to_excl_s]),
      // QARZDORLAR — faqat hali TO'LANMAGAN (outstanding) qarzlar (debts jadvalidan).
      // To'langan qarzlar ko'rinmasligi kerak. Davr bo'yicha emas — barcha ochiq qarzlar.
      pool.query(
        `SELECT d.id, d.debtor_name, (d.amount - d.paid_amount) AS amount,
                to_char(d.created_at,'YYYY-MM-DD HH24:MI') AS dt
         FROM debts d WHERE (d.amount - d.paid_amount) > 0.5
         ORDER BY d.created_at DESC`),
      // Chegirma qilingan zakazlar (sabab bilan)
      pool.query(
        `SELECT id, discount_percent,
                discount_reason,
                (total_amount - COALESCE(final_amount,total_amount)) AS discount,
                COALESCE(final_amount,total_amount) AS final_amount,
                to_char(created_at,'YYYY-MM-DD HH24:MI') AS dt
         FROM orders WHERE status='paid'
           AND (total_amount - COALESCE(final_amount,total_amount)) > 0
           AND created_at >= $1 AND created_at < $2
         ORDER BY created_at DESC`, [from_s, to_excl_s]),
      // Zakazlar ro'yxati
      pool.query(
        `SELECT o.id, COALESCE(o.final_amount,o.total_amount) AS amount, o.total_amount,
                COALESCE(o.paid_card,0) AS paid_card, COALESCE(o.paid_cash,0) AS paid_cash, COALESCE(o.paid_debt,0) AS paid_debt,
                u.full_name AS waiter, to_char(o.created_at,'YYYY-MM-DD HH24:MI') AS dt
         FROM orders o LEFT JOIN users u ON o.waiter_id=u.id
         WHERE o.status='paid' AND o.created_at >= $1 AND o.created_at < $2
         ORDER BY o.created_at DESC LIMIT 200`, [from_s, to_excl_s]),
      // Barcha faol taomlar KATEGORIYA bo'yicha, davr ichida sotilgan miqdor (sotilmagan = 0)
      pool.query(
        `SELECT c.name AS category, m.name AS dish, m.price,
                COALESCE(s.qty,0)::int AS qty, COALESCE(s.amount,0) AS amount
         FROM menu_items m
         JOIN menu_categories c ON m.category_id=c.id
         LEFT JOIN (
           SELECT oi.menu_item_id, SUM(oi.quantity) AS qty, SUM(oi.price*oi.quantity) AS amount
           FROM order_items oi JOIN orders o ON oi.order_id=o.id
           WHERE o.status='paid' AND o.created_at >= $1 AND o.created_at < $2
           GROUP BY oi.menu_item_id
         ) s ON s.menu_item_id = m.id
         WHERE m.is_active=true
         ORDER BY c.name, qty DESC, m.name`, [from_s, to_excl_s]),
      // JAMI harajat — AGREGAT (ro'yxatdan MUSTAQIL). Ro'yxat LIMIT 300/∞ bilan
      // kesiladi, lekin summa TO'LIQ bo'lishi shart (oy davomida 300+ chiqim bo'lsa
      // profit shishib ketmasin).
      pool.query(
        `SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions
         WHERE kind='expense' AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      pool.query(
        `SELECT COALESCE(SUM(amount),0) AS total FROM expenses
         WHERE source <> 'kassa' AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      // REALIZED foyda uchun (analitika bilan bir xil): undirilgan qarz + ish haqi (kassadan tashqari qismi)
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions
                  WHERE kind='income' AND source='debt' AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM salary_payments
                  WHERE created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions
                  WHERE kind='expense' AND source IN ('salary','advance') AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
      // MAHSULOT XARIDI (sklad kirim + postavshik) — bu COGS orqali hisobga olinadi,
      // shuning uchun SOF FOYDADAN "prochie rasxod" sifatida IKKI MARTA ayirilmaydi.
      pool.query(`SELECT COALESCE(SUM(amount),0) AS total FROM cash_transactions
                  WHERE kind='expense' AND source IN ('stock','supplier') AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
    ]);

    const salesTotal = parseFloat(sales.rows[0].sales);
    const ordersCount = sales.rows[0].orders;
    const p = pays.rows[0];

    // Barcha harajatlarni (Kassadan + boshqa manba) birlashtirib jami + ro'yxat tuzamiz
    const CAT = { salary: 'Oylik', advance: 'Avans', stock: 'Sklad', manual: "Qo'lda" };
    // JAMI harajat — agregat so'rovlardan (LIMIT'siz), profit to'g'ri chiqishi uchun.
    const expenses = parseFloat(expKassaAgg.rows[0].total) + parseFloat(expOtherAgg.rows[0].total);
    const expensesList = []; // faqat ko'rsatish uchun (kesilgan ro'yxat)
    for (const r of exp.rows) { // exp endi = Kassadan ketgan chiqimlar
      const amount = parseFloat(r.amount);
      let typeName, name;
      if (r.source === 'expense') { typeName = r.expense_type || 'Boshqa'; name = r.note || ''; }
      else if (r.source === 'salary' || r.source === 'advance') { typeName = CAT[r.source]; name = r.staff_name || r.note || ''; }
      else if (r.source === 'stock') { typeName = 'Sklad'; name = r.note || ''; }
      else if (r.source === 'supplier') { typeName = 'Postavshik'; name = r.supplier_name || r.note || ''; }
      else if (r.source === 'payable') { typeName = 'Kreditor'; name = r.note || ''; }
      else { typeName = "Qo'lda"; name = r.note || ''; }
      expensesList.push({ type_name: typeName, name, amount, method: r.method, source: r.source, from_kassa: true, dt: r.dt });
    }
    for (const r of expList.rows) { // expList endi = Kassadan tashqari xarajatlar
      const amount = parseFloat(r.amount);
      expensesList.push({ type_name: r.expense_type || 'Boshqa', name: r.name || '', amount, method: r.method, source: 'expense', from_kassa: false, dt: r.dt });
    }

    const cogs = await cogsForOrders(
      `o.status='paid' AND o.created_at >= $1 AND o.created_at < $2`, [from_s, to_excl_s]);

    // SOF FOYDA = COGS asosida (egasi tasdig'i 2026-07-14):
    //   Sof foyda = Realized − COGS − Ish haqi(to'liq) − Boshqa xarajatlar
    //   • realized: savdo (karta+naqd) + undirilgan qarz (to'lanmagan qarz foydani oshirmaydi).
    //   • COGS: sotilgan taomlar tannarxi (retseptdan). Mahsulot XARIDI (sklad/postavshik) — COGS
    //     orqali hisobga olinadi, shuning uchun "boshqa xarajatlar"дан CHIQARILADI (ikki marta emas).
    //   • Boshqa xarajatlar = jami expenses − mahsulot xaridi − kassadan ish haqi qismi.
    //   • Ish haqi TO'LIQ ayiriladi (salaryPaid). Kassa qismi expenses'da edi — u ham chiqarildi.
    const received = parseFloat(p.card) + parseFloat(p.cash);
    const debtCollected = parseFloat(debtPaidAgg.rows[0].total);
    const salaryPaid = parseFloat(salaryPaidAgg.rows[0].total);
    const salaryKassa = parseFloat(salaryKassaAgg.rows[0].total);
    const ingredientPurchases = parseFloat(ingredientPurchAgg.rows[0].total);
    const operatingExpenses = Math.max(0, expenses - ingredientPurchases - salaryKassa);
    const realized = received + debtCollected;
    const profit = realized - cogs - salaryPaid - operatingExpenses;

    res.json({
      period, from: from_s, to: to_incl_s,
      sales: salesTotal,
      received,
      realized,
      debt_collected: debtCollected,
      salary_paid: salaryPaid,
      orders_count: ordersCount,
      avg_check: ordersCount > 0 ? Math.round(salesTotal / ordersCount) : 0,
      expenses,
      cogs,
      ingredient_purchases: ingredientPurchases, // sklad+postavshik xaridi (COGS'да hisobga olingan)
      operating_expenses: operatingExpenses,     // boshqa xarajatlar (ijara/svet/... mahsulotsiz)
      gross_profit: salesTotal - cogs,
      profit,
      payments: { card: parseFloat(p.card), cash: parseFloat(p.cash), debt: parseFloat(p.debt) },
      discount_total: parseFloat(p.discount),
      top_items: top.rows,
      waiter_sales: waiters.rows,
      sales_by_day: byDay.rows,
      expenses_list: expensesList,
      debtors: debtorRows.rows,
      discounted_orders: discRows.rows,
      orders_list: orderRows.rows,
      dishes_by_category: catDishes.rows,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// KUNLIK KUZAT: bugungi tracked taomlar — tayyorlangan / sotilgan / qolgan.
// "Sotilgan" = bugun (biznes kun) buyurtma qilingan (pending + paid) miqdor.
const getDailyStock = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT mi.id AS menu_item_id, mi.name, mi.price,
              COALESCE(ds.opening_qty, 0) AS opening,
              (ds.id IS NOT NULL) AS has_opening,
              COALESCE((
                SELECT SUM(oi.quantity) FROM order_items oi
                JOIN orders o ON oi.order_id = o.id
                WHERE oi.menu_item_id = mi.id
                  AND (o.created_at - INTERVAL '150 minutes')::date = (NOW() - INTERVAL '150 minutes')::date
              ), 0) AS sold
       FROM menu_items mi
       LEFT JOIN daily_stock ds ON ds.menu_item_id = mi.id
            AND ds.biz_date = (NOW() - INTERVAL '150 minutes')::date
       WHERE mi.is_active = true AND mi.daily_tracked = true
       ORDER BY mi.name`
    );
    res.json(result.rows.map((r) => {
      const opening = parseFloat(r.opening) || 0;
      const sold = parseFloat(r.sold) || 0;
      return {
        menu_item_id: r.menu_item_id, name: r.name,
        opening, sold, remaining: opening - sold,
        has_opening: r.has_opening === true,
      };
    }));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Ertalabki son kiritish (bugungi biznes kun uchun upsert)
const setDailyStock = async (req, res) => {
  try {
    const id = parseInt(req.body.menu_item_id);
    const qty = parseFloat(req.body.quantity);
    if (isNaN(id) || isNaN(qty) || qty < 0) {
      return res.status(400).json({ message: 'menu_item_id va musbat quantity kerak' });
    }
    await pool.query(
      `INSERT INTO daily_stock (menu_item_id, biz_date, opening_qty)
       VALUES ($1, (NOW() - INTERVAL '150 minutes')::date, $2)
       ON CONFLICT (menu_item_id, biz_date) DO UPDATE SET opening_qty = $2`,
      [id, qty]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ==== BITTA BLYUDO ANALITIKASI (drill-down): davr bo'yicha kunlik dinamika ====
const getDishDetail = async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (!id) return res.status(400).json({ message: 'Noto\'g\'ri id' });
    const { from_s, to_excl_s, period } = await resolveRange(req.query);
    const cur = [from_s, to_excl_s, id];
    const [info, totals, byDay, byHour] = await Promise.all([
      pool.query(`SELECT m.name, COALESCE(c.cost,0) AS unit_cost
                  FROM menu_items m LEFT JOIN (${MENU_COST_SUBQUERY}) c ON c.menu_item_id=m.id
                  WHERE m.id=$1`, [id]),
      pool.query(`SELECT COALESCE(SUM(oi.quantity),0)::int qty,
                    COALESCE(SUM(oi.price*oi.quantity),0) revenue,
                    COUNT(DISTINCT o.id)::int orders
                  FROM order_items oi JOIN orders o ON oi.order_id=o.id
                  WHERE oi.menu_item_id=$3 AND o.status='paid' AND o.created_at>=$1 AND o.created_at<$2`, cur),
      pool.query(`SELECT to_char((o.created_at - INTERVAL '150 minutes')::date,'YYYY-MM-DD') d,
                    COALESCE(SUM(oi.quantity),0)::int qty,
                    COALESCE(SUM(oi.price*oi.quantity),0) revenue
                  FROM order_items oi JOIN orders o ON oi.order_id=o.id
                  WHERE oi.menu_item_id=$3 AND o.status='paid' AND o.created_at>=$1 AND o.created_at<$2
                  GROUP BY (o.created_at - INTERVAL '150 minutes')::date
                  ORDER BY (o.created_at - INTERVAL '150 minutes')::date`, cur),
      pool.query(`SELECT EXTRACT(HOUR FROM o.created_at)::int h, COALESCE(SUM(oi.quantity),0)::int qty
                  FROM order_items oi JOIN orders o ON oi.order_id=o.id
                  WHERE oi.menu_item_id=$3 AND o.status='paid' AND o.created_at>=$1 AND o.created_at<$2
                  GROUP BY h ORDER BY h`, cur),
    ]);
    if (!info.rows.length) return res.status(404).json({ message: 'Taom topilmadi' });
    const unitCost = parseFloat(info.rows[0].unit_cost) || 0;
    const t = totals.rows[0];
    const qty = t.qty, revenue = parseFloat(t.revenue) || 0;
    const cost = qty * unitCost;
    res.json({
      id, name: info.rows[0].name, period,
      unit_cost: Math.round(unitCost),
      qty, revenue, orders: t.orders,
      cost: Math.round(cost), profit: Math.round(revenue - cost),
      margin: revenue > 0 ? Math.round((revenue - cost) / revenue * 100) : 0,
      avg_per_order: t.orders > 0 ? Math.round((qty / t.orders) * 10) / 10 : 0,
      by_day: byDay.rows.map((r) => ({ d: r.d, qty: r.qty, revenue: parseFloat(r.revenue) || 0 })),
      by_hour: byHour.rows,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ==== SDELNAYA STAVKALAR (piece-rate): xodim -> taom -> dona stavkasi ====
const getPieceRates = async (req, res) => {
  try {
    const userId = parseInt(req.query.user_id);
    if (!userId) return res.status(400).json({ message: 'user_id kerak' });
    const r = await pool.query(
      `SELECT spr.id, spr.menu_item_id, m.name, spr.rate
       FROM salary_piece_rates spr JOIN menu_items m ON m.id = spr.menu_item_id
       WHERE spr.user_id = $1 ORDER BY m.name`, [userId]);
    res.json(r.rows.map((x) => ({ id: x.id, menu_item_id: x.menu_item_id, name: x.name, rate: parseFloat(x.rate) || 0 })));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Xodimning barcha dona-stavkalarini ALMASHTIRADI (body: { user_id, rates:[{menu_item_id, rate}] })
const setPieceRates = async (req, res) => {
  const client = await pool.connect();
  try {
    const userId = parseInt(req.body.user_id);
    const rates = Array.isArray(req.body.rates) ? req.body.rates : [];
    if (!userId) { client.release(); return res.status(400).json({ message: 'user_id kerak' }); }
    await client.query('BEGIN');
    await client.query('DELETE FROM salary_piece_rates WHERE user_id = $1', [userId]);
    let n = 0;
    for (const it of rates) {
      const mid = parseInt(it.menu_item_id);
      const rate = Math.max(0, parseFloat(it.rate) || 0);
      if (!mid || rate <= 0) continue;
      await client.query(
        `INSERT INTO salary_piece_rates (user_id, menu_item_id, rate) VALUES ($1,$2,$3)
         ON CONFLICT (user_id, menu_item_id) DO UPDATE SET rate = EXCLUDED.rate`,
        [userId, mid, rate]);
      n++;
    }
    await client.query('COMMIT');
    res.json({ ok: true, count: n });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

module.exports = {
  getDailyReport, getStockReport, getAttendanceReport, getAttendanceHistory, getDashboard, getPayroll, getPayrollPeriods,
  getDailyStock, setDailyStock,
  addSalaryPayment, listSalaryPayments, deleteSalaryPayment,
  addSalaryFine, listSalaryFines, deleteSalaryFine,
  addSalaryBonus, listSalaryBonuses, deleteSalaryBonus,
  setLateFineOverride, deleteLateFineOverride,
  setManualShifts, deleteManualShifts, getManualShifts,
  getCashbox, addCashTransaction, setOpeningBalance, deleteCashTransaction, payDebt,
  getReport, getAnalytics,
  getDishDetail, getPieceRates, setPieceRates,
};