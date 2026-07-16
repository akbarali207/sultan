const pool = require('../config/db');
const { emit } = require('../services/eventBus');
const { consumeStock, restoreConsumption } = require('../services/costingService');

// Zakazlar ustidan to'liq huquq — kassir/admin/nazoratchi/egasi.
// MUHIM: oldin tekshiruvlar "role === 'waiter'" (qora ro'yxat) edi — bu chef/cleaner
// (jonli bazada 5 ta parolli chef!) ga zakazlarni o'chirish/bekor/ko'chirishga
// yo'l ochardi. Endi OQ ro'yxat: faqat quyidagilar boshqaradi.
const canManageOrders = (u) => !!u && ['cashier', 'admin', 'director', 'guest'].includes(u.role);

// Barcha stollar
const getTables = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM tables WHERE is_active = true ORDER BY COALESCE(number, id)`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const createTable = async (req, res) => {
  try {
    const { name, number } = req.body;
    const result = await pool.query(
      `INSERT INTO tables (name, number, status) VALUES ($1, $2, 'free') RETURNING *`,
      [name, number || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Zakazlar ro'yxati.
//  ?status=paid  -> tugallangan (bugungi to'langanlar)
//  default       -> tugallanmagan (to'lanmaganlar)
const getOrders = async (req, res) => {
  try {
    const { status } = req.query;
    const params = [];
    let whereClause;
    if (status === 'paid') {
      // ?date=YYYY-MM-DD berilsa — o'sha kun; berilmasa bugungi.
      // Kassa kuni 02:30 da yopiladi — "biznes sana" = (vaqt - 150 daqiqa) sanasi
      const d = (req.query.date || '').toString();
      if (/^\d{4}-\d{2}-\d{2}$/.test(d)) {
        params.push(d);
        whereClause = `WHERE o.status = 'paid' AND (o.created_at - INTERVAL '150 minutes')::date = $${params.length}`;
      } else {
        whereClause = `WHERE o.status = 'paid' AND (o.created_at - INTERVAL '150 minutes')::date = (NOW() - INTERVAL '150 minutes')::date`;
      }
    } else {
      whereClause = `WHERE o.status != 'paid'`;
    }
    // Ofitsant faqat O'Z zakazlarini ko'radi (admin/kassir hammasini)
    if (req.user && req.user.role === 'waiter') {
      params.push(req.user.id);
      whereClause += ` AND o.waiter_id = $${params.length}`;
    }
    const result = await pool.query(
      `SELECT o.*, t.number as table_number, t.name as table_name, u.full_name as waiter_name,
       COALESCE(
         json_agg(
           json_build_object(
             'id', oi.id,
             'menu_item_id', oi.menu_item_id,
             'name', mi.name,
             'quantity', oi.quantity,
             'price', oi.price,
             'notes', oi.notes,
             'is_kitchen', oi.is_kitchen
           )
         ) FILTER (WHERE oi.id IS NOT NULL), '[]'
       ) as items
       FROM orders o
       LEFT JOIN tables t ON o.table_id = t.id
       LEFT JOIN users u ON o.waiter_id = u.id
       LEFT JOIN order_items oi ON o.id = oi.order_id
       LEFT JOIN menu_items mi ON oi.menu_item_id = mi.id
       ${whereClause}
       GROUP BY o.id, t.number, t.name, u.full_name
       ORDER BY o.created_at DESC`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Zakaz tarkibi (alohida endpoint)
const getOrderItems = async (req, res) => {
  try {
    const { id } = req.params;
    // Ofitsant faqat O'Z zakazi tarkibini ko'ra oladi
    if (req.user && req.user.role === 'waiter') {
      const own = await pool.query('SELECT waiter_id FROM orders WHERE id = $1', [id]);
      if (!own.rows.length || own.rows[0].waiter_id !== req.user.id) {
        return res.status(403).json({ message: 'Ruxsat yo\'q' });
      }
    }
    const result = await pool.query(
      `SELECT oi.*, mi.name as item_name
       FROM order_items oi
       JOIN menu_items mi ON oi.menu_item_id = mi.id
       WHERE oi.order_id = $1`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi zakaz yaratish
const createOrder = async (req, res) => {
  const { table_id, items, notes } = req.body;
  // Ofitsant zakazni faqat O'Z nomidan ochadi (boshqa ofitsant nomidan emas)
  let { waiter_id } = req.body;
  if (req.user && req.user.role === 'waiter') waiter_id = req.user.id;
  // items: [{menu_item_id, quantity, price, notes, is_kitchen}]
  if (!Array.isArray(items) || items.length === 0) return res.status(400).json({ message: 'Kamida bitta taom kerak' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Super-admin STOP — tizim to'xtatilgan bo'lsa yangi zakaz qabul qilinmaydi
    const fz = await client.query('SELECT frozen FROM system_state WHERE id = 1');
    if (fz.rows.length && fz.rows[0].frozen === true) {
      await client.query('ROLLBACK');
      return res.status(423).json({ message: 'Tizim to\'xtatilgan (super-admin) — zakaz qabul qilinmaydi' });
    }

    // Stol qatorini qulflash — ikki ofitsant bir vaqtda shu stolga zakaz ochsa,
    // ikkinchisi kutadi va mavjud ochiq zakazga qo'shiladi (ikkita zakaz ochilmaydi)
    if (table_id) {
      await client.query(`SELECT id FROM tables WHERE id = $1 FOR UPDATE`, [table_id]);
    }

    // STOP-LIST: "tayyor emas" (available=false) taom zakaz qilinmasin
    const itemIds = (items || []).map((it) => it.menu_item_id);
    if (itemIds.length) {
      const stop = await client.query(
        `SELECT name FROM menu_items WHERE id = ANY($1) AND available = false`,
        [itemIds]
      );
      if (stop.rows.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          message: `Stop-list: "${stop.rows.map((r) => r.name).join(', ')}" hozir tayyor emas`,
        });
      }

      // KUNLIK KUZAT: bugun son kiritilgan (daily_tracked) taom tugagan bo'lsa — rad.
      // Son kiritilmagan bo'lsa (daily_stock yo'q) — cheklov yo'q, oddiy sotiladi.
      const orderedNow = {};
      for (const it of items) {
        orderedNow[it.menu_item_id] = (orderedNow[it.menu_item_id] || 0) + (parseFloat(it.quantity) || 0);
      }
      const limited = await client.query(
        `SELECT mi.id, mi.name, ds.opening_qty,
                COALESCE((SELECT SUM(oi.quantity) FROM order_items oi JOIN orders o ON oi.order_id = o.id
                          WHERE oi.menu_item_id = mi.id
                            AND (o.created_at - INTERVAL '150 minutes')::date = (NOW() - INTERVAL '150 minutes')::date), 0) AS committed
         FROM menu_items mi
         JOIN daily_stock ds ON ds.menu_item_id = mi.id AND ds.biz_date = (NOW() - INTERVAL '150 minutes')::date
         WHERE mi.id = ANY($1) AND mi.daily_tracked = true`,
        [itemIds]
      );
      for (const row of limited.rows) {
        const remaining = parseFloat(row.opening_qty) - parseFloat(row.committed);
        if ((orderedNow[row.id] || 0) > remaining) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            message: `"${row.name}" tugadi — faqat ${Math.max(0, remaining)} ta qoldi`,
          });
        }
      }
    }

    // Bu stolda ochiq (to'lanmagan) zakaz bo'lsa — YANGI ochmay, o'shanga qo'shamiz
    // (bir stol = bitta zakaz; alohida-alohida bo'lib ketmasin)
    let orderId;
    let merged = false;
    if (table_id) {
      const ex = await client.query(
        `SELECT id FROM orders WHERE table_id = $1 AND status <> 'paid'
         ORDER BY created_at DESC LIMIT 1`,
        [table_id]
      );
      if (ex.rows.length) { orderId = ex.rows[0].id; merged = true; }
    }
    if (!orderId) {
      const orderResult = await client.query(
        `INSERT INTO orders (table_id, waiter_id, status, notes, total_amount)
         VALUES ($1, $2, 'pending', $3, 0) RETURNING id`,
        [table_id, waiter_id, notes || '']
      );
      orderId = orderResult.rows[0].id;
    } else if (notes && notes.toString().trim()) {
      // Mavjud zakazga qo'shilyapti — izoh yo'qolmasin, mavjud izohga qo'shamiz (moveOrder kabi)
      await client.query(
        `UPDATE orders SET notes = CONCAT_WS(' | ', NULLIF(notes, ''), $1) WHERE id = $2`,
        [notes.toString().trim(), orderId]
      );
    }

    // Narxni SERVERDA menu_items dan olamiz — mijoz yuborgan narxga ISHONMAYMIZ.
    // (Aks holda ofitsant narxni o'zgartirib arzon probit qilishi mumkin edi: steykni 1 so'mga.)
    const priceIds = [...new Set(items.map((it) => Number(it.menu_item_id)).filter((x) => Number.isInteger(x)))];
    const priceRes = priceIds.length
      ? await client.query(`SELECT id, price FROM menu_items WHERE id = ANY($1)`, [priceIds])
      : { rows: [] };
    const priceMap = new Map(priceRes.rows.map((r) => [Number(r.id), parseFloat(r.price) || 0]));

    for (const item of items) {
      const mid = Number(item.menu_item_id);
      if (!priceMap.has(mid)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: `Taom topilmadi (id=${item.menu_item_id})` });
      }
      const qty = parseFloat(item.quantity);
      if (!(qty > 0)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: 'Taom miqdori musbat bo\'lishi kerak' });
      }
      const price = priceMap.get(mid); // FAQAT bazadagi narx
      await client.query(
        `INSERT INTO order_items (order_id, menu_item_id, quantity, price, notes, is_kitchen)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [orderId, mid, qty, price, item.notes || '', item.is_kitchen !== false]
      );
    }

    // Jami = barcha taomlar yig'indisi (qo'shilgandan keyin qayta hisoblanadi)
    const sumRes = await client.query(
      `SELECT COALESCE(SUM(price * quantity), 0) AS total FROM order_items WHERE order_id = $1`,
      [orderId]
    );
    const totalAmount = parseFloat(sumRes.rows[0].total) || 0;
    await client.query(`UPDATE orders SET total_amount = $1 WHERE id = $2`, [totalAmount, orderId]);

    if (table_id) {
      await client.query(`UPDATE tables SET status = 'occupied' WHERE id = $1`, [table_id]);
    }

    await client.query('COMMIT');
    // Hodisalar faqat COMMIT'dan KEYIN — bekor qilingan tranzaksiya hodisa yubormaydi
    emit('orders', orderId);
    emit('tables', table_id || null);
    emit('print', orderId); // print-agent yangi oshxona cheklarini darhol oladi
    const finalOrder = await pool.query(`SELECT * FROM orders WHERE id = $1`, [orderId]);
    res.status(201).json({ ...finalOrder.rows[0], merged });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Skladdan ayirish (zakaz to'langanda) — PARTIYALAR orqali (F10/F11):
// tanlangan metod (FIFO/LIFO/AVG) bo'yicha chegiriladi, har sarf o'sha
// paytdagi TANNARX bilan lot_consumptions ga yoziladi (tarixiy COGS
// keyin narx o'zgarsa ham o'zgarmaydi).
const deductStock = async (client, orderId) => {
  const items = await client.query(
    `SELECT oi.menu_item_id, oi.quantity, mi.type, mi.ingredient_id
     FROM order_items oi JOIN menu_items mi ON oi.menu_item_id = mi.id
     WHERE oi.order_id = $1`,
    [orderId]
  );
  for (const item of items.rows) {
    if (item.type === 'product' && item.ingredient_id) {
      await consumeStock(client, {
        ingredientId: item.ingredient_id, quantity: item.quantity,
        reason: 'sale', refType: 'order', refId: orderId,
      });
    } else {
      const recipe = await client.query(
        `SELECT ingredient_id, quantity FROM recipe_items WHERE menu_item_id = $1`,
        [item.menu_item_id]
      );
      for (const r of recipe.rows) {
        await consumeStock(client, {
          ingredientId: r.ingredient_id, quantity: r.quantity * item.quantity,
          reason: 'sale', refType: 'order', refId: orderId,
        });
      }
    }
  }
};

// Skladga QAYTARISH (zakaz/taom o'chirilganda — deductStock ning teskarisi).
// Avval partiya sarflarini AYNAN teskari qaytaramiz (qaysi partiyadan
// chegirilgan bo'lsa o'shalarga). Yozuv topilmasa (partiya tizimidan
// OLDINGI zakaz) — eski retsept-matematika bilan qaytariladi.
const restoreStock = async (client, orderId, itemId = null) => {
  if (!itemId) {
    const restored = await restoreConsumption(client, { refType: 'order', refId: orderId });
    if (restored.length > 0) return;
  }
  const params = [orderId];
  let extra = '';
  if (itemId) { params.push(itemId); extra = ' AND oi.id = $2'; }
  const items = await client.query(
    `SELECT oi.menu_item_id, oi.quantity, mi.type, mi.ingredient_id
     FROM order_items oi JOIN menu_items mi ON oi.menu_item_id = mi.id
     WHERE oi.order_id = $1${extra}`,
    params
  );
  for (const item of items.rows) {
    if (item.type === 'product' && item.ingredient_id) {
      await client.query(
        `UPDATE ingredients SET stock_quantity = stock_quantity + $1 WHERE id = $2`,
        [item.quantity, item.ingredient_id]
      );
    } else {
      const recipe = await client.query(
        `SELECT ingredient_id, quantity FROM recipe_items WHERE menu_item_id = $1`,
        [item.menu_item_id]
      );
      for (const r of recipe.rows) {
        await client.query(
          `UPDATE ingredients SET stock_quantity = stock_quantity + $1 WHERE id = $2`,
          [r.quantity * item.quantity, r.ingredient_id]
        );
      }
    }
  }
};

// ATMEN chekini navbatga qo'yish — faqat OSHXONA KO'RGAN (printed=true) taomlar,
// har bo'limga (multistation: har ikkala bo'limga) alohida "ОТМЕНА" chek yoziladi.
// onlyItemId berilsa — faqat bitta taom (taom bekor qilinganda).
const queueCancelTickets = async (client, orderId, onlyItemId = null, overrideQty = null) => {
  const rows = await client.query(
    `SELECT oi.quantity, mi.name AS item_name,
            COALESCE(mis.station_id, mi.station_id) AS station_id,
            COALESCE(t.number::text, t.name, '-') AS table_no,
            u.full_name AS waiter_name
     FROM order_items oi
     JOIN orders o ON oi.order_id = o.id
     JOIN menu_items mi ON oi.menu_item_id = mi.id
     LEFT JOIN menu_item_stations mis ON mis.menu_item_id = mi.id
     LEFT JOIN tables t ON o.table_id = t.id
     LEFT JOIN users u ON o.waiter_id = u.id
     WHERE oi.order_id = $1 AND oi.printed = true` + (onlyItemId ? ` AND oi.id = $2` : ''),
    onlyItemId ? [orderId, onlyItemId] : [orderId]
  );
  if (!rows.rows.length) return;
  const byStation = {};
  for (const r of rows.rows) {
    const key = r.station_id || 0;
    if (!byStation[key]) {
      byStation[key] = { station_id: r.station_id, table_no: r.table_no, waiter: r.waiter_name, items: [] };
    }
    byStation[key].items.push({
      name: r.item_name,
      // qisman bekorда faqat bekor qilingan miqdor chekда ko'rinadi (butun taom emas)
      quantity: (overrideQty != null && onlyItemId) ? parseFloat(overrideQty) : parseFloat(r.quantity),
    });
  }
  for (const g of Object.values(byStation)) {
    await client.query(
      `INSERT INTO cancel_tickets (order_id, table_name, waiter_name, station_id, items)
       VALUES ($1, $2, $3, $4, $5)`,
      [orderId, g.table_no, g.waiter, g.station_id, JSON.stringify(g.items)]
    );
  }
};

// Zakazni butunlay O'CHIRISH (admin/kassir). To'langan bo'lsa: kassa tushumi,
// qarz va sklad ham qaytariladi — hisobot/kassa to'g'ri qolishi uchun.
const deleteOrder = async (req, res) => {
  const { id } = req.params;
  if (!canManageOrders(req.user)) {
    return res.status(403).json({ message: 'Ruxsat yo\'q' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // FOR UPDATE — bir vaqtda kelgan to'lov/o'chirish poygasini yo'q qiladi
    const cur = await client.query(`SELECT * FROM orders WHERE id = $1 FOR UPDATE`, [id]);
    if (cur.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Zakaz topilmadi' });
    }
    const order = cur.rows[0];
    if (order.status === 'paid') {
      // Qarzi qisman to'langan zakazni o'chirib bo'lmaydi — yig'ilgan naqd kassadan
      // izsiz yo'qolmasin (avval qarz to'lovini alohida tuzatish kerak).
      const repChk = await client.query(`SELECT COALESCE(SUM(paid_amount),0) AS rep FROM debts WHERE order_id = $1`, [id]);
      if (parseFloat(repChk.rows[0].rep) > 0) {
        await client.query('ROLLBACK');
        return res.status(409).json({ message: 'Bu zakaz qarzi qisman to\'langan — avval qarz to\'lovini alohida tuzating, keyin o\'chiring' });
      }
      // VOID AUDITI: to'langan zakaz o'chirilishi yozib qolinadi (kim, qancha, qaysi, sabab)
      const ures = req.user && req.user.id
        ? await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id])
        : { rows: [] };
      const uname = ures.rows.length ? ures.rows[0].full_name : null;
      const tres = order.table_id
        ? await client.query('SELECT COALESCE(number::text, name) AS l FROM tables WHERE id = $1', [order.table_id])
        : { rows: [] };
      const tlabel = tres.rows.length ? tres.rows[0].l : null;
      const reason = ((req.body && req.body.reason) || (req.query && req.query.reason) || '').toString().trim().slice(0, 300) || null;
      await client.query(
        `INSERT INTO order_void_log (order_id, table_label, final_amount, paid_card, paid_cash, paid_debt, discount_percent, user_id, user_name, reason)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
        [id, tlabel, order.final_amount, order.paid_card, order.paid_cash, order.paid_debt, order.discount_percent,
         (req.user && req.user.id) || null, uname, reason]
      );
      // Kassa tushumini qaytar (shu zakaz bo'yicha)
      await client.query(`DELETE FROM cash_transactions WHERE source = 'order' AND ref_id = $1`, [id]);
      // Qarz yozuvini o'chir — o'chirilgan qarz id larini olamiz
      const delDebts = await client.query(`DELETE FROM debts WHERE order_id = $1 RETURNING id`, [id]);
      // Shu qarzlarga qilingan QARZ TO'LOVLARINI ham qaytar (aks holda kassa tushumi ortadi)
      const debtIds = delDebts.rows.map(r => r.id);
      if (debtIds.length > 0) {
        await client.query(`DELETE FROM cash_transactions WHERE source = 'debt' AND ref_id = ANY($1)`, [debtIds]);
      }
      // Skladni qaytar (to'langanda ayirilgan edi)
      await restoreStock(client, id);
    } else {
      // AKTIV zakaz atmen — oshxona ko'rgan taomlar uchun "ОТМЕНА" cheki chiqadi
      // (to'langan eski zakazni o'chirish — bugalteriya, oshxonaga chek kerak emas)
      await queueCancelTickets(client, id);
    }
    await client.query(`DELETE FROM order_items WHERE order_id = $1`, [id]);
    await client.query(`DELETE FROM orders WHERE id = $1`, [id]);
    if (order.table_id) {
      // Stolni faqat shu stolда BOSHQA ochiq zakaz bo'lmasa bo'shatamiz.
      // (To'langan zakaz o'chirilса-yu, stolда yangi mehmonlar ochiq zakaz bilan
      //  o'tirган bo'lsa — stol qizil qolishi kerak, aks holда boshqa ofitsant
      //  ustidan zakaz ochib qo'yadi.)
      await client.query(
        `UPDATE tables SET status = 'free' WHERE id = $1
           AND NOT EXISTS (SELECT 1 FROM orders WHERE table_id = $1 AND status <> 'paid')`,
        [order.table_id]);
    }
    await client.query('COMMIT');
    emit('orders', id);
    emit('tables', order.table_id || null);
    if (order.status === 'paid') emit('kassa', null); // kassa tushumi qaytarildi
    else emit('print', id); // atmen cheki darhol chiqsin
    res.json({ ok: true });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Zakazdan bitta TAOMni bekor qilish (admin/kassir). Faqat to'lanmagan zakazda.
// Jami summa qayta hisoblanadi; oxirgi taom bo'lsa — zakaz o'chib, stol bo'shaydi.
const cancelOrderItem = async (req, res) => {
  const { orderId, itemId } = req.params;
  if (!canManageOrders(req.user)) {
    return res.status(403).json({ message: 'Ruxsat yo\'q' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const ord = await client.query(`SELECT * FROM orders WHERE id = $1 FOR UPDATE`, [orderId]);
    if (ord.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Zakaz topilmadi' });
    }
    if (ord.rows[0].status === 'paid') {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'To\'langan zakazdan taom o\'chirib bo\'lmaydi. Butun zakazni o\'chiring.' });
    }

    // QISMAN bekor: ?qty=N berilsa va N < mavjud miqdor bo'lsa — faqat N tasini bekor qilamiz
    // (masalan 5 ta somsadan 2 tasini). Qolgani zakazда qoladi, qayta probit qilish shart emas.
    const cancelQty = parseFloat(req.query.qty);
    const cur = await client.query(
      `SELECT quantity FROM order_items WHERE id = $1 AND order_id = $2`, [itemId, orderId]
    );
    if (cur.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Taom topilmadi' });
    }
    const have = parseFloat(cur.rows[0].quantity) || 0;
    if (cancelQty > 0 && cancelQty < have) {
      await queueCancelTickets(client, orderId, itemId, cancelQty); // faqat bekor qilingan miqdorga ОТМЕНА cheki
      await client.query(`UPDATE order_items SET quantity = quantity - $1 WHERE id = $2`, [cancelQty, itemId]);
      const sp = await client.query(
        `SELECT COALESCE(SUM(price * quantity), 0) AS total FROM order_items WHERE order_id = $1`, [orderId]
      );
      const nt = parseFloat(sp.rows[0].total) || 0;
      await client.query(`UPDATE orders SET total_amount = $1 WHERE id = $2`, [nt, orderId]);
      await client.query('COMMIT');
      emit('orders', orderId);
      emit('print', orderId); // qisman ОТМЕНА cheki darhol chiqsin
      return res.json({ ok: true, partial: true, remaining: have - cancelQty, total_amount: nt });
    }

    // TO'LIQ bekor — o'chirishdan OLDIN atmen chekini navbatga qo'yamiz (oshxona ko'rgan bo'lsa)
    await queueCancelTickets(client, orderId, itemId);
    const del = await client.query(
      `DELETE FROM order_items WHERE id = $1 AND order_id = $2 RETURNING *`,
      [itemId, orderId]
    );
    if (del.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Taom topilmadi' });
    }
    const cnt = await client.query(`SELECT COUNT(*)::int AS c FROM order_items WHERE order_id = $1`, [orderId]);
    if (cnt.rows[0].c === 0) {
      // Taom qolmadi — zakazni o'chir, stolni bo'shat
      await client.query(`DELETE FROM orders WHERE id = $1`, [orderId]);
      if (ord.rows[0].table_id) {
        await client.query(`UPDATE tables SET status = 'free' WHERE id = $1`, [ord.rows[0].table_id]);
      }
      await client.query('COMMIT');
      emit('orders', orderId);
      emit('tables', ord.rows[0].table_id || null);
      emit('print', orderId); // atmen cheki darhol chiqsin
      return res.json({ ok: true, orderDeleted: true });
    }
    const sumRes = await client.query(
      `SELECT COALESCE(SUM(price * quantity), 0) AS total FROM order_items WHERE order_id = $1`,
      [orderId]
    );
    const newTotal = parseFloat(sumRes.rows[0].total) || 0;
    await client.query(`UPDATE orders SET total_amount = $1 WHERE id = $2`, [newTotal, orderId]);
    await client.query('COMMIT');
    emit('orders', orderId);
    emit('print', orderId); // atmen cheki darhol chiqsin
    res.json({ ok: true, total_amount: newTotal });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Zakaz statusini yangilash. status='paid' bo'lsa to'lov ma'lumotlari ham qabul qilinadi:
//   { discount_percent, discount_reason, paid_card, paid_cash, paid_debt, debtor_name }
// To'lov maydonlari berilmasa — to'liq naqd deb hisoblanadi (eski mijozlar bilan moslik).
const updateOrderStatus = async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // FOR UPDATE — parallel ikki to'lov/o'zgartirish bir-birini kutadi (poyga yo'q)
    const cur = await client.query(`SELECT * FROM orders WHERE id = $1 FOR UPDATE`, [id]);
    if (cur.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Zakaz topilmadi' });
    }
    // Ofitsant faqat O'Z zakazini o'zgartira oladi
    if (req.user && req.user.role === 'waiter' && cur.rows[0].waiter_id !== req.user.id) {
      await client.query('ROLLBACK');
      return res.status(403).json({ message: 'Ruxsat yo\'q' });
    }
    const existing = cur.rows[0];

    // Status whitelist — noto'g'ri qiymat DB CHECK ga urilib 500 bermasin
    if (!['pending', 'preparing', 'ready', 'paid'].includes(status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Noto\'g\'ri status' });
    }

    // MUHIM: allaqachon to'langan zakazni qayta to'lash TAQIQ —
    // aks holda sklad ikki marta ayirilib, kassaga ikki marta tushum yozilardi
    if (existing.status === 'paid') {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: 'Zakaz allaqachon to\'langan' });
    }

    if (status === 'paid') {
      // To'lovni faqat KASSIR/ADMIN (yoki director/super-admin) qabul qiladi
      if (req.user && !['cashier', 'admin', 'director', 'guest'].includes(req.user.role)) {
        await client.query('ROLLBACK');
        return res.status(403).json({ message: 'To\'lovni faqat kassir yoki admin qabul qiladi' });
      }
      // Super-admin STOP — tizim to'xtatilgan bo'lsa to'lov qabul qilinmaydi
      const fzp = await client.query('SELECT frozen FROM system_state WHERE id = 1');
      if (fzp.rows.length && fzp.rows[0].frozen === true) {
        await client.query('ROLLBACK');
        return res.status(423).json({ message: 'Tizim to\'xtatilgan (super-admin) — to\'lov qabul qilinmaydi' });
      }
      // Summani serverda qayta hisoblaymiz (mijoz yuborgan/eskirgan qiymatga ishonmaymiz)
      const sumRes = await client.query(
        `SELECT COALESCE(SUM(price * quantity), 0) AS total FROM order_items WHERE order_id = $1`,
        [id]
      );
      const subtotal = parseFloat(sumRes.rows[0].total) || parseFloat(existing.total_amount) || 0;

      let discPct = parseFloat(req.body.discount_percent);
      if (!(discPct >= 0 && discPct <= 100)) discPct = 0;
      const discReason = (req.body.discount_reason || '').toString().trim().slice(0, 200) || null;
      const finalAmount = Math.round(subtotal * (100 - discPct) / 100);

      const hasSplit = ['paid_card', 'paid_cash', 'paid_debt'].some((k) => req.body[k] !== undefined);
      let card = Math.max(0, Math.round(parseFloat(req.body.paid_card) || 0));
      let cash = Math.max(0, Math.round(parseFloat(req.body.paid_cash) || 0));
      let debt = Math.max(0, Math.round(parseFloat(req.body.paid_debt) || 0));
      if (!hasSplit) { cash = finalAmount; card = 0; debt = 0; } // to'liq naqd (default)

      const sum = card + cash + debt;
      if (Math.abs(sum - finalAmount) > 1) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: `To'lov (${sum}) yakuniy summaga (${finalAmount}) teng emas` });
      }
      // ±1 yaxlitlash farqini bitta ustunga singdiramiz — kassa/qarz aniq final_amount ga teng bo'lsin
      // (aks holda savdo/kassa svergasида 1 birlik dreyf to'planadi). |farq| <= 1, har ustun >= 0.
      const diff = finalAmount - sum;
      if (diff !== 0) {
        if (cash + diff >= 0) cash += diff;
        else if (card + diff >= 0) card += diff;
        else debt += diff;
      }
      const debtorName = (req.body.debtor_name || '').toString().trim().slice(0, 120);
      if (debt > 0 && !debtorName) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: 'Qarz uchun mijoz ism-familiyasi kerak' });
      }

      // To'lovni qabul qilgan xodim (kassir) — podotchётlik uchun
      const payer = req.user && req.user.id
        ? await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id])
        : { rows: [] };
      const payerName = payer.rows.length ? payer.rows[0].full_name : null;
      await client.query(
        `UPDATE orders SET status='paid', discount_percent=$1, discount_reason=$2, final_amount=$3,
                paid_card=$4, paid_cash=$5, paid_debt=$6, debtor_name=$7, paid_by=$9, paid_by_name=$10 WHERE id=$8`,
        [discPct, discReason, finalAmount, card, cash, debt, debt > 0 ? debtorName : null, id,
         (req.user && req.user.id) || null, payerName]
      );

      await client.query(`UPDATE tables SET status='free' WHERE id=$1`, [existing.table_id]);
      await deductStock(client, id);

      // Kassa: tushum (karta/naqd alohida)
      if (card > 0) {
        await client.query(
          `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
           VALUES ('income','card',$1,'order',$2,$3)`,
          [card, id, `Zakaz #${id}`]
        );
      }
      if (cash > 0) {
        await client.query(
          `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
           VALUES ('income','cash',$1,'order',$2,$3)`,
          [cash, id, `Zakaz #${id}`]
        );
      }
      // Qarz yozuvi
      if (debt > 0) {
        await client.query(
          `INSERT INTO debts (order_id, debtor_name, amount) VALUES ($1,$2,$3)`,
          [id, debtorName, debt]
        );
      }

      await client.query('COMMIT');
      emit('orders', id);
      emit('tables', existing.table_id || null);
      emit('kassa', null); // yangi tushum yozildi
      const updated = await pool.query(`SELECT * FROM orders WHERE id=$1`, [id]);
      return res.json(updated.rows[0]);
    }

    // Boshqa status o'zgarishlari (pending/preparing/ready)
    const upd = await client.query(`UPDATE orders SET status=$1 WHERE id=$2 RETURNING *`, [status, id]);
    await client.query('COMMIT');
    emit('orders', id);
    res.json(upd.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// HISOB/CHEK chiqarish — bill_requested=true qilamiz, print-agent chop etadi.
// Aktiv zakazда = "Hisob" (счёт, to'lovsiz); tugallangan zakazда = chekni qayta chiqarish.
const printBill = async (req, res) => {
  const { id } = req.params;
  // Hisob/chek chiqarish — ofitsant yoki kassir/admin; chef/cleaner emas.
  if (!(canManageOrders(req.user) || (req.user && req.user.role === 'waiter'))) {
    return res.status(403).json({ message: 'Ruxsat yo\'q' });
  }
  try {
    const r = await pool.query(
      `UPDATE orders SET bill_requested = true WHERE id = $1 RETURNING id`,
      [id]
    );
    if (r.rows.length === 0) return res.status(404).json({ message: 'Zakaz topilmadi' });
    emit('print', id); // print-agent hisob/chekni darhol chiqaradi
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Zakazni BOSHQA STOLGA ko'chirish yoki stollarni BIRLASHTIRISH.
//  - Maqsad stol BO'SH bo'lsa: oddiy ko'chirish (zakaz shu stolga o'tadi).
//  - Maqsad stolda OCHIQ zakaz bo'lsa: BIRLASHTIRISH (taomlar o'sha zakazga
//    qo'shiladi, manba zakaz o'chadi). Ilgari bu imkonsiz edi — stolni o'chirib
//    qaytadan probit qilishga to'g'ri kelardi.
const moveOrder = async (req, res) => {
  const { id } = req.params;
  const targetTableId = parseInt(req.body.table_id);
  if (isNaN(targetTableId)) return res.status(400).json({ message: 'table_id kerak' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query(`SELECT * FROM orders WHERE id = $1 FOR UPDATE`, [id]);
    if (!cur.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Zakaz topilmadi' }); }
    const order = cur.rows[0];
    if (order.status === 'paid') { await client.query('ROLLBACK'); return res.status(400).json({ message: 'To\'langan zakazni ko\'chirib bo\'lmaydi' }); }
    // Ofitsant faqat O'Z zakazini ko'chiradi; kassir/admin — istalganini;
    // boshqa rollar (chef/cleaner) — umuman yo'q.
    if (!(canManageOrders(req.user) || (req.user && req.user.role === 'waiter' && order.waiter_id === req.user.id))) {
      await client.query('ROLLBACK'); return res.status(403).json({ message: 'Ruxsat yo\'q' });
    }
    const sourceTableId = order.table_id;
    if (sourceTableId === targetTableId) { await client.query('ROLLBACK'); return res.status(400).json({ message: 'Bir xil stol' }); }

    const tgt = await client.query(`SELECT id FROM tables WHERE id = $1 AND is_active = true FOR UPDATE`, [targetTableId]);
    if (!tgt.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Maqsad stol topilmadi' }); }

    // Maqsad stolda ochiq zakaz bormi?
    const tOpen = await client.query(
      `SELECT id FROM orders WHERE table_id = $1 AND status <> 'paid' ORDER BY created_at LIMIT 1 FOR UPDATE`,
      [targetTableId]
    );

    let merged = false;
    if (tOpen.rows.length) {
      // BIRLASHTIRISH: taomlarni maqsad zakazga ko'chiramiz, manbani o'chiramiz
      const targetOrderId = tOpen.rows[0].id;
      await client.query(`UPDATE order_items SET order_id = $1 WHERE order_id = $2`, [targetOrderId, id]);
      if (order.notes && order.notes.trim()) {
        await client.query(
          `UPDATE orders SET notes = CONCAT_WS(' | ', NULLIF(notes,''), $1) WHERE id = $2`,
          [order.notes.trim(), targetOrderId]
        );
      }
      await client.query(`DELETE FROM orders WHERE id = $1`, [id]);
      const s = await client.query(`SELECT COALESCE(SUM(price*quantity),0) AS total FROM order_items WHERE order_id = $1`, [targetOrderId]);
      await client.query(`UPDATE orders SET total_amount = $1 WHERE id = $2`, [parseFloat(s.rows[0].total) || 0, targetOrderId]);
      merged = true;
    } else {
      // KO'CHIRISH: zakazni maqsad stolga biriktiramiz
      await client.query(`UPDATE orders SET table_id = $1 WHERE id = $2`, [targetTableId, id]);
      await client.query(`UPDATE tables SET status = 'occupied' WHERE id = $1`, [targetTableId]);
    }
    // Manba stol endi bo'sh (uning ochiq zakazi ko'chdi/o'chdi)
    if (sourceTableId) {
      await client.query(`UPDATE tables SET status = 'free' WHERE id = $1`, [sourceTableId]);
    }
    await client.query('COMMIT');
    emit('orders', id);
    emit('tables', sourceTableId || null);
    emit('tables', targetTableId);
    res.json({ ok: true, merged });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Zakazni QISMAN ko'chirish: tanlangan taomlar/miqdorni boshqa stolga.
//  body: { table_id, items: [{order_item_id, quantity}] }
//  - moveQty >= satr miqdori: butun satr maqsadga o'tadi.
//  - moveQty < miqdor: SPLIT — manba kamayadi, maqsadga yangi satr (o'sha narx).
//  Maqsad stolda ochiq zakaz bo'lsa unga qo'shiladi, aks holda YANGI zakaz ochiladi.
//  Manba zakaz bo'shab qolsa — o'chadi, stol bo'shaydi.
const moveOrderItems = async (req, res) => {
  const { id } = req.params;
  const targetTableId = parseInt(req.body.table_id);
  const items = Array.isArray(req.body.items) ? req.body.items : [];
  if (isNaN(targetTableId)) return res.status(400).json({ message: 'table_id kerak' });
  if (!items.length) return res.status(400).json({ message: 'Ko\'chiriladigan taom tanlanmagan' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query(`SELECT * FROM orders WHERE id = $1 FOR UPDATE`, [id]);
    if (!cur.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Zakaz topilmadi' }); }
    const order = cur.rows[0];
    if (order.status === 'paid') { await client.query('ROLLBACK'); return res.status(400).json({ message: 'To\'langan zakazni ko\'chirib bo\'lmaydi' }); }
    if (!(canManageOrders(req.user) || (req.user && req.user.role === 'waiter' && order.waiter_id === req.user.id))) {
      await client.query('ROLLBACK'); return res.status(403).json({ message: 'Ruxsat yo\'q' });
    }
    const sourceTableId = order.table_id;
    if (sourceTableId === targetTableId) { await client.query('ROLLBACK'); return res.status(400).json({ message: 'Bir xil stol' }); }
    const tgt = await client.query(`SELECT id FROM tables WHERE id = $1 AND is_active = true FOR UPDATE`, [targetTableId]);
    if (!tgt.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Maqsad stol topilmadi' }); }

    // Maqsad zakaz: ochiq bo'lsa o'sha, aks holda YANGI
    let targetOrderId;
    const tOpen = await client.query(`SELECT id FROM orders WHERE table_id = $1 AND status <> 'paid' ORDER BY created_at LIMIT 1 FOR UPDATE`, [targetTableId]);
    if (tOpen.rows.length) {
      targetOrderId = tOpen.rows[0].id;
    } else {
      const nu = await client.query(
        `INSERT INTO orders (table_id, waiter_id, status, total_amount) VALUES ($1, $2, 'pending', 0) RETURNING id`,
        [targetTableId, order.waiter_id]);
      targetOrderId = nu.rows[0].id;
      await client.query(`UPDATE tables SET status = 'occupied' WHERE id = $1`, [targetTableId]);
    }

    for (const it of items) {
      const oiId = parseInt(it.order_item_id);
      const moveQty = parseInt(it.quantity);
      if (!oiId || !(moveQty > 0)) continue;
      const oiRes = await client.query(`SELECT * FROM order_items WHERE id = $1 AND order_id = $2 FOR UPDATE`, [oiId, id]);
      if (!oiRes.rows.length) continue;
      const oi = oiRes.rows[0];
      const have = parseInt(oi.quantity);
      const mv = Math.min(moveQty, have);
      if (mv >= have) {
        await client.query(`UPDATE order_items SET order_id = $1 WHERE id = $2`, [targetOrderId, oiId]);
      } else {
        await client.query(`UPDATE order_items SET quantity = quantity - $1 WHERE id = $2`, [mv, oiId]);
        await client.query(
          `INSERT INTO order_items (order_id, menu_item_id, quantity, price, notes, is_kitchen, printed)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [targetOrderId, oi.menu_item_id, mv, oi.price, oi.notes, oi.is_kitchen, oi.printed]);
      }
    }

    // Totallar
    for (const oid of [id, targetOrderId]) {
      const s = await client.query(`SELECT COALESCE(SUM(price*quantity),0) AS total FROM order_items WHERE order_id = $1`, [oid]);
      await client.query(`UPDATE orders SET total_amount = $1 WHERE id = $2`, [parseFloat(s.rows[0].total) || 0, oid]);
    }
    // Manba bo'shab qoldimi?
    const left = await client.query(`SELECT COUNT(*)::int AS n FROM order_items WHERE order_id = $1`, [id]);
    if (left.rows[0].n === 0) {
      await client.query(`DELETE FROM orders WHERE id = $1`, [id]);
      if (sourceTableId) await client.query(`UPDATE tables SET status = 'free' WHERE id = $1`, [sourceTableId]);
    }
    await client.query('COMMIT');
    emit('orders', id); emit('orders', targetOrderId);
    emit('tables', sourceTableId || null); emit('tables', targetTableId);
    res.json({ ok: true, target_order_id: targetOrderId });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// To'langan zakazni QAYTA OCHISH (reopen) — noto'g'ri to'lovni tuzatish uchun.
// To'lov ta'sirlarini bekor qiladi (kassa tushumi, qarz+qarz to'lovlari, sklad)
// va zakazni ochiq holatga (pending) qaytaradi — kassir qayta to'g'ri to'laydi.
// FAQAT kassir/admin. Ilgari yagona chiqish — butun zakazni o'chirib qaytadan yaratish edi.
const reopenOrder = async (req, res) => {
  const { id } = req.params;
  if (req.user && !['cashier','admin','director','guest'].includes(req.user.role)) return res.status(403).json({ message: 'Qayta ochishni faqat kassir yoki admin qiladi' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query(`SELECT * FROM orders WHERE id = $1 FOR UPDATE`, [id]);
    if (!cur.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Zakaz topilmadi' }); }
    const order = cur.rows[0];
    if (order.status !== 'paid') { await client.query('ROLLBACK'); return res.status(400).json({ message: 'Faqat to\'langan zakazni qayta ochish mumkin' }); }

    // Stolda boshqa ochiq zakaz bo'lsa — qayta ochib bo'lmaydi (bir stol = bitta ochiq zakaz)
    if (order.table_id) {
      const other = await client.query(
        `SELECT 1 FROM orders WHERE table_id = $1 AND status <> 'paid' AND id <> $2 LIMIT 1`,
        [order.table_id, id]
      );
      if (other.rows.length) {
        await client.query('ROLLBACK');
        return res.status(409).json({ message: 'Stolda yangi ochiq zakaz bor — avval uni yakunlang' });
      }
    }

    // Qarzi qisman to'langan zakazni qayta ochib bo'lmaydi (yig'ilgan naqd izsiz ketmasin)
    const repChkR = await client.query(`SELECT COALESCE(SUM(paid_amount),0) AS rep FROM debts WHERE order_id = $1`, [id]);
    if (parseFloat(repChkR.rows[0].rep) > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: 'Bu zakaz qarzi qisman to\'langan — qayta ochishdan oldin qarz to\'lovini alohida tuzating' });
    }

    // REOPEN AUDITI: to'langan zakazning qayta ochilishi ham yozib qolinadi (deleteOrder void
    // auditi kabi — aks holda reopen orqali izsiz pul qaytarib, keyin pending zakazni o'chirib
    // firibgarlik qilish mumkin edi).
    const ru = req.user && req.user.id
      ? await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id])
      : { rows: [] };
    const ruName = ru.rows.length ? ru.rows[0].full_name : null;
    const rt = order.table_id
      ? await client.query('SELECT COALESCE(number::text, name) AS l FROM tables WHERE id = $1', [order.table_id])
      : { rows: [] };
    const rtLabel = rt.rows.length ? rt.rows[0].l : null;
    const rReason = 'REOPEN: ' + (((req.body && req.body.reason) || '').toString().trim().slice(0, 290) || 'sabab ko\'rsatilmagan');
    await client.query(
      `INSERT INTO order_void_log (order_id, table_label, final_amount, paid_card, paid_cash, paid_debt, discount_percent, user_id, user_name, reason)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [id, rtLabel, order.final_amount, order.paid_card, order.paid_cash, order.paid_debt, order.discount_percent,
       (req.user && req.user.id) || null, ruName, rReason]
    );

    // To'lov ta'sirlarini bekor qilamiz (deleteOrder paid tarmog'idagi kabi)
    await client.query(`DELETE FROM cash_transactions WHERE source = 'order' AND ref_id = $1`, [id]);
    const delDebts = await client.query(`DELETE FROM debts WHERE order_id = $1 RETURNING id`, [id]);
    const debtIds = delDebts.rows.map((r) => r.id);
    if (debtIds.length) {
      await client.query(`DELETE FROM cash_transactions WHERE source = 'debt' AND ref_id = ANY($1)`, [debtIds]);
    }
    await restoreStock(client, id); // to'lovda ayirilgan sklad qaytadi

    // Zakazni ochiq holatga qaytaramiz + to'lov maydonlarini tozalaymiz
    await client.query(
      `UPDATE orders SET status = 'pending', final_amount = NULL, discount_percent = 0,
              discount_reason = NULL, paid_card = 0, paid_cash = 0, paid_debt = 0,
              debtor_name = NULL, bill_requested = false WHERE id = $1`,
      [id]
    );
    if (order.table_id) {
      await client.query(`UPDATE tables SET status = 'occupied' WHERE id = $1`, [order.table_id]);
    }
    await client.query('COMMIT');
    emit('orders', id);
    emit('tables', order.table_id || null);
    emit('kassa', null); // tushum qaytarildi
    res.json({ ok: true });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

module.exports = { getTables, createTable, createOrder, getOrders, getOrderItems, updateOrderStatus, deleteOrder, cancelOrderItem, printBill, moveOrder, moveOrderItems, reopenOrder };
