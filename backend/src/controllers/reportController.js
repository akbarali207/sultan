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
    const profit = totalSales - totalExpenses;

    res.json({
      date: filterDate,
      total_orders: salesResult.rows[0].total_orders,
      total_sales: totalSales,
      total_expenses: totalExpenses,
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

    const [sales, expenses, tables, staff, present, low, top, waiters, byDay, byHour, byStation] = await Promise.all([
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
    ]);

    const totalSales = parseFloat(sales.rows[0].sales);
    const totalReceived = parseFloat(sales.rows[0].received); // kassaga tushgan (karta+naqd, qarzsiz)
    const totalOrders = sales.rows[0].orders;
    const totalExpenses = parseFloat(expenses.rows[0].expenses);
    const cogs = await cogsForOrders(`o.status='paid' AND ${rng('o.created_at')}`);

    res.json({
      period,
      date: dateStr,
      sales: totalSales,
      received: totalReceived,
      orders: totalOrders,
      expenses: totalExpenses,
      cogs: cogs,
      gross_profit: totalSales - cogs,
      profit: totalSales - totalExpenses,
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

    const [sumCur, sumPrev, byDay, topItems, byCat, byHour, waiters, byDish, expBreak, debtRow, expCur, expPrev, salaryAgg, bonusAgg, salaryKassaAgg, debtPaidAgg] = await Promise.all([
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
      pool.query(`SELECT c.name, SUM(oi.quantity)::int qty, COALESCE(SUM(oi.price*oi.quantity),0) sales
                  FROM order_items oi JOIN orders o ON oi.order_id=o.id
                  JOIN menu_items m ON oi.menu_item_id=m.id JOIN menu_categories c ON m.category_id=c.id
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
    ]);

    const cogs = await cogsForOrders(`o.status='paid' AND o.created_at >= $1 AND o.created_at < $2`, cur);
    const cogsPrev = await cogsForOrders(`o.status='paid' AND o.created_at >= ${PREV} AND o.created_at < $1::timestamp`, cur);

    const s = sumCur.rows[0], p = sumPrev.rows[0];
    const sales = parseFloat(s.sales), orders = s.orders, expenses = parseFloat(expCur.rows[0].expenses);
    const pSales = parseFloat(p.sales), pOrders = p.orders, pExpenses = parseFloat(expPrev.rows[0].expenses);
    const received = parseFloat(s.received), pReceived = parseFloat(p.received);

    // Ish haqi: BARCHA to'lov (kassa+boshqa) profitдан ayirilishi kerak. Kassadan chiqqan qism
    // expenses'ga allaqachon kirgan — faqat qolgan (boshqa joydan) qismini qo'shimcha ayiramiz (ikki marta emas).
    const salaryPaid = parseFloat(salaryAgg.rows[0].cur), salaryPaidPrev = parseFloat(salaryAgg.rows[0].prev);
    const bonuses = parseFloat(bonusAgg.rows[0].cur), bonusesPrev = parseFloat(bonusAgg.rows[0].prev);
    const salaryKassa = parseFloat(salaryKassaAgg.rows[0].cur), salaryKassaPrev = parseFloat(salaryKassaAgg.rows[0].prev);
    const extraLabor = Math.max(0, salaryPaid - salaryKassa);
    const extraLaborPrev = Math.max(0, salaryPaidPrev - salaryKassaPrev);

    // QARZ foydaga FAQAT to'langanда kiradi: realizatsiya = kassaga tushgan (karta+naqd, qarzsiz) + undirilgan qarz.
    // Shunday qilib to'lanmagan qarz sof foydani oshirib yubormaydi (egasi shuni so'radi).
    const debtPaid = parseFloat(debtPaidAgg.rows[0].cur), debtPaidPrev = parseFloat(debtPaidAgg.rows[0].prev);
    const realized = received + debtPaid;
    const realizedPrev = pReceived + debtPaidPrev;
    const profit = realized - expenses - extraLabor;         // Sof foyda — qarz to'langanда, ish haqi ayirilgan
    const profitPrev = realizedPrev - pExpenses - extraLaborPrev;

    res.json({
      period,
      summary: {
        sales, received, discount: parseFloat(s.discount), orders,
        avg_check: orders > 0 ? Math.round(sales / orders) : 0,
        cogs, gross_profit: sales - cogs, expenses, profit,
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
       WHERE u.is_active = true
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
        const diff = (ch * 60 + cm) - (wh * 60 + wm);
        if (diff > 0) {
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
    const [emp, sales, att, adv, lastSal, fines, bonuses, overrides, pieceAgg, dailySales] = await Promise.all([
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
         WHERE u.is_active = true
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
                to_char(MIN(check_in), 'HH24:MI') AS first_in,
                CASE WHEN MAX(check_out) IS NOT NULL
                     THEN COALESCE(EXTRACT(EPOCH FROM SUM(check_out - check_in) FILTER (WHERE check_out IS NOT NULL)), 0) / 3600.0
                     ELSE 0 END AS hours
         FROM attendance
         WHERE check_in >= $1 AND check_in < $2
         GROUP BY user_id, (check_in - INTERVAL '150 minutes')::date`,
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

    // Davomat: kun soni, soat va kechikish jarimasini xodim bo'yicha yig'amiz
    const acc = {};
    for (const u of emp.rows) {
      acc[u.id] = { work_start: u.work_start, late_fine: parseFloat(u.late_fine_per_minute), days: 0, hours: 0, fine: 0, hoursList: [] };
    }
    for (const a of att.rows) {
      const e = acc[a.user_id];
      if (!e) continue;
      e.days += 1;
      e.hours += parseFloat(a.hours);
      e.hoursList.push(parseFloat(a.hours) || 0); // shift-oylik uchun HAR KUN alohida soat
      if (e.work_start && a.first_in) {
        const [wh, wm] = e.work_start.split(':').map(Number);
        const [ch, cm] = a.first_in.split(':').map(Number);
        const late = (ch * 60 + cm) - (wh * 60 + wm);
        if (late > 0) e.fine += late * e.late_fine;
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
          // STAVKA (smena) — HAR KUN alohida. sv = 1 to'liq smena stavkasi.
          //  kun >= 11:50 (710 daq) -> 1 stavka;  agar > 12:00 (720 daq) -> + (ortiqcha daq × stavka/720) bonus;
          //  kun < 11:50 -> 0.5 stavka (kam ishlagan). Bonus base ichida -> oylik tarixiga kiradi.
          base = (e.hoursList || []).reduce((acc2, h) => {
            const m = (h || 0) * 60;
            if (m >= 710) return acc2 + (m > 720 ? sv + (m - 720) * (sv / 720) : sv);
            return acc2 + sv * 0.5;
          }, 0);
          break;
        }
        case 'monthly': base = sv; break;
        case 'daily':   base = e.days * sv; break;
        case 'hourly':  base = hours * sv; break;
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
      // Oylik to'lash mumkinmi: qoldiq bor VA (hech oylik berilmagan YOKI oxirgisidan period_days kun o'tgan)
      const canPaySalary = remaining > 0 && (daysSince === null || daysSince >= periodDays);
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
        days_worked: e.days,
        hours_worked: hours,
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

    await client.query('BEGIN');
    // Xodim qatorini qulflash — parallel ikki oylik to'lovi bir-birini kutadi,
    // sikl tekshiruvi tranzaksiya ICHIDA bo'lgani uchun poyga yo'q
    await client.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [user_id]);

    // Oylik sikli: monthly xodim uchun to'lov kunidan oldin yoki shu oyda allaqachon berilgan bo'lsa rad etiladi
    if (kind === 'salary') {
      // Oylik to'lov davri (kun) bo'yicha sikl: oxirgi oylikdan period kun o'tmaguncha rad etiladi
      const u = await client.query(`SELECT COALESCE(salary_period_days,30) AS period FROM users WHERE id=$1`, [user_id]);
      const period = u.rows.length ? (parseInt(u.rows[0].period, 10) || 30) : 30;
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

    const r = await client.query(
      `INSERT INTO salary_payments (user_id, amount, method, kind, note, source, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7::timestamp, NOW()))
       RETURNING id, user_id, amount, method, kind, note, source, to_char(created_at,'YYYY-MM-DD') AS date`,
      [user_id, amt, method, kind, note || null, sourceText, isDate ? date : null]
    );
    const pay = r.rows[0];
    // Faqat Kassadan to'langanda Kassa balansidan chiqim qilamiz.
    // created_at TO'LOV sanasi bilan bir xil (backdate bo'lsa ham) — aks holда analitikada
    // salary_payments (o'tgan davr) va cash_transactions (bugun) turli davrga tushib, mehnat xarajati ikki bo'linardi.
    if (fromKassa) {
      await client.query(
        `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note, created_at)
         VALUES ('expense', $1, $2, $3, $4, $5, COALESCE($6::timestamp, NOW()))`,
        [method, amt, kind, pay.id, kind === 'salary' ? 'Oylik' : 'Avans', isDate ? date : null]
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
       VALUES ($1, $2, $3, COALESCE($4::timestamp, NOW()))
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
       VALUES ($1, $2, $3, $4, COALESCE($5::timestamp, NOW()))
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
      pool.query(`SELECT COALESCE(SUM(amount),0) AS o FROM cash_transactions
                  WHERE source = 'opening' AND created_at >= $1 AND created_at < $2`, [from_s, to_excl_s]),
    ]);

    const m = { income: { card: 0, cash: 0 }, expense: { card: 0, cash: 0 } };
    for (const r of agg.rows) {
      if (m[r.kind] && (r.method === 'card' || r.method === 'cash')) {
        m[r.kind][r.method] = parseFloat(r.total);
      }
    }
    const incomeTotal = m.income.card + m.income.cash;
    const expenseTotal = m.expense.card + m.expense.cash;
    const opening = parseFloat(openingRes.rows[0].o) || 0; // kassa ochilish qoldig'i (naqd)

    res.json({
      period, from: from_s, to: to_incl_s,
      opening,
      income:  { card: m.income.card,  cash: m.income.cash,  total: incomeTotal },
      expense: { card: m.expense.card, cash: m.expense.cash, total: expenseTotal },
      net:     { card: m.income.card - m.expense.card, cash: m.income.cash - m.expense.cash + opening, total: incomeTotal - expenseTotal + opening },
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

    const [sales, pays, exp, top, waiters, byDay, expList, debtorRows, discRows, orderRows, catDishes] = await Promise.all([
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
                et.name AS expense_type, su.full_name AS staff_name
         FROM cash_transactions ct
         LEFT JOIN expenses e ON ct.source='expense' AND ct.ref_id = e.id
         LEFT JOIN expense_types et ON e.expense_type_id = et.id
         LEFT JOIN salary_payments sp ON ct.source IN ('salary','advance') AND ct.ref_id = sp.id
         LEFT JOIN users su ON sp.user_id = su.id
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
    ]);

    const salesTotal = parseFloat(sales.rows[0].sales);
    const ordersCount = sales.rows[0].orders;
    const p = pays.rows[0];

    // Barcha harajatlarni (Kassadan + boshqa manba) birlashtirib jami + ro'yxat tuzamiz
    const CAT = { salary: 'Oylik', advance: 'Avans', stock: 'Sklad', manual: "Qo'lda" };
    let expenses = 0;
    const expensesList = [];
    for (const r of exp.rows) { // exp endi = Kassadan ketgan chiqimlar
      const amount = parseFloat(r.amount);
      expenses += amount;
      let typeName, name;
      if (r.source === 'expense') { typeName = r.expense_type || 'Boshqa'; name = r.note || ''; }
      else if (r.source === 'salary' || r.source === 'advance') { typeName = CAT[r.source]; name = r.staff_name || r.note || ''; }
      else if (r.source === 'stock') { typeName = 'Sklad'; name = r.note || ''; }
      else { typeName = "Qo'lda"; name = r.note || ''; }
      expensesList.push({ type_name: typeName, name, amount, method: r.method, source: r.source, from_kassa: true, dt: r.dt });
    }
    for (const r of expList.rows) { // expList endi = Kassadan tashqari xarajatlar
      const amount = parseFloat(r.amount);
      expenses += amount;
      expensesList.push({ type_name: r.expense_type || 'Boshqa', name: r.name || '', amount, method: r.method, source: 'expense', from_kassa: false, dt: r.dt });
    }

    const cogs = await cogsForOrders(
      `o.status='paid' AND o.created_at >= $1 AND o.created_at < $2`, [from_s, to_excl_s]);

    // Foyda = SAVDO (qarz ham daromad) - harajat. Qarz FOYDAGA kiradi (topilgan pul),
    // lekin KASSAGA tushmaydi — shuning uchun "received" (kassaga tushgan) alohida ko'rsatiladi.
    const received = parseFloat(p.card) + parseFloat(p.cash);

    res.json({
      period, from: from_s, to: to_incl_s,
      sales: salesTotal,
      received,
      orders_count: ordersCount,
      avg_check: ordersCount > 0 ? Math.round(salesTotal / ordersCount) : 0,
      expenses,
      cogs,
      gross_profit: salesTotal - cogs,
      profit: salesTotal - expenses,
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
  getDailyReport, getStockReport, getAttendanceReport, getDashboard, getPayroll,
  getDailyStock, setDailyStock,
  addSalaryPayment, listSalaryPayments, deleteSalaryPayment,
  addSalaryFine, listSalaryFines, deleteSalaryFine,
  addSalaryBonus, listSalaryBonuses, deleteSalaryBonus,
  setLateFineOverride, deleteLateFineOverride,
  getCashbox, addCashTransaction, setOpeningBalance, deleteCashTransaction, payDebt,
  getReport, getAnalytics,
  getDishDetail, getPieceRates, setPieceRates,
};