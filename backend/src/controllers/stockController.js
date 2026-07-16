const pool = require('../config/db');
const { createLot, consumeStock, addSupplierPayment } = require('../services/costingService');
const { logAudit } = require('../services/audit');

// Postavshikni topish/yaratish (kirimda nom bilan kelsa) — nom bo'yicha upsert
const resolveSupplierId = async (client, body) => {
  if (body.supplier_id) return parseInt(body.supplier_id) || null;
  const name = (body.supplier_name || '').toString().trim();
  if (!name) return null;
  const found = await client.query(
    `SELECT id FROM suppliers WHERE lower(trim(name)) = lower($1) LIMIT 1`, [name]);
  if (found.rows.length) return found.rows[0].id;
  const ins = await client.query(`INSERT INTO suppliers (name) VALUES ($1) RETURNING id`, [name]);
  return ins.rows[0].id;
};

// Barcha mahsulotlar (sklad) — sklad va kategoriya bo'yicha filtr.
// Sotuvga chiqarilgan (product) mahsulot uchun bog'langan menyu yozuvi (id/kategoriya/narx) ham qaytadi,
// shunda kirim oynasi joriy kategoriya/narxni to'g'ri ko'rsatadi (default bilan ustidan yozib yubormaydi).
const getIngredients = async (req, res) => {
  try {
    const { category, warehouse_id } = req.query;
    const conditions = ['COALESCE(i.is_active, true) = true']; // arxivlangan (soft-deleted) mahsulotlar ko'rinmaydi
    const params = [];
    if (warehouse_id) {
      params.push(warehouse_id);
      conditions.push(`i.warehouse_id = $${params.length}`);
    }
    if (category) {
      params.push(category);
      conditions.push(`i.category = $${params.length}`);
    }
    let query = `
      SELECT i.*,
             mi.id          AS menu_item_id,
             mi.category_id AS menu_category_id,
             mi.price       AS menu_price
      FROM ingredients i
      LEFT JOIN LATERAL (
        SELECT id, category_id, price
        FROM menu_items
        WHERE ingredient_id = i.id AND type = 'product' AND is_active = true
        ORDER BY id LIMIT 1
      ) mi ON true`;
    if (conditions.length > 0) {
      query += ` WHERE ` + conditions.join(' AND ');
    }
    query += ` ORDER BY i.name`;
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulot qo'shish (tanlangan skladga)
const createIngredient = async (req, res) => {
  const client = await pool.connect();
  try {
    const { name, unit, stock_quantity, min_quantity, price_per_unit, selling_price, category, warehouse_id } = req.body;
    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, selling_price, category, warehouse_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [name, unit, stock_quantity || 0, min_quantity || 0, price_per_unit || 0, selling_price || 0, category || null, warehouse_id || null]
    );
    const ing = result.rows[0];

    // BOSHLANG'ICH QOLDIQ → PARTIYA (lot). Aks holda sklad qoldig'i lot-ledger bilan farq qiladi va
    // sotilganда consumeStock faol partiya topmay COGS=0 chiqaradi (foyda oshib ketadi). Bu OCHILISH
    // qoldig'i — to'liq to'langan (paidAmount berilmaydi → createLot uni to'liq to'langan deb belgilaydi;
    // kassa chiqimi/qarz yaratilmaydi). addIncoming'даги lot yaratish bilan bir xil.
    // Miqdorni DB shkalasiga (3 kasr) yaxlitlaymiz: stock_lots.quantity NUMERIC(14,3) CHECK(>0) —
    // 0.0004 kabi mayda qiymat 0.000 ga yaxlitlanib CHECK'ni buzardi va butun createIngredient 500 berardi.
    // Ingredients.stock_quantity ham NUMERIC(*,3) — u ham 0.000 saqlaydi, shuning uchun lot ochmaymiz.
    const initQty = Math.round((parseFloat(stock_quantity) || 0) * 1000) / 1000;
    if (initQty > 0) {
      await createLot(client, {
        ingredientId: ing.id, quantity: initQty, unit: ing.unit,
        unitCost: parseFloat(price_per_unit) || 0,
        note: 'Boshlang\'ich qoldiq', createdBy: req.user ? req.user.id : null,
      });
    }

    // SOTUVGA CHIQARISH (retail): sotish narxi > 0 bo'lsa — mahsulot MENYUга ham qo'shiladi va SOTILADIGAN
    // bo'ladi. Aks holda mahsulot skladда qoladi-yu, ofitsant uni pробить qilолмайди (getMenuItems menyu
    // kategoriya bilan INNER JOIN qiladi; menyu yozuvi bo'lmasa taom umuman ko'rinmaydi). Menyu yozuvi
    // type='product' + ingredient_id bo'lgani uchun COGS tannarxni ingredient.price_per_unit'дан oladi
    // (MENU_COST_SUBQUERY) → BAR/tayyor tovarlar sotilganда sof foyda aniq chiqadi. addIncoming ko'prigi bilan bir xil.
    const sp = (selling_price !== undefined && selling_price !== null) ? parseFloat(selling_price) : 0;
    const isRetail = (req.body.is_retail === true || req.body.is_retail === 'true') || (sp > 0);
    if (isRetail && sp > 0) {
      // Menyu kategoriyasi: aniq nom → o'xshash (ILIKE) → topilmasa YARATAMIZ (INNER JOIN uchun majburiy).
      let catId = (req.body.category_id !== undefined && req.body.category_id !== null && req.body.category_id !== '')
        ? parseInt(req.body.category_id) : null;
      if (!catId) {
        const cname = (category && String(category).trim()) ? String(category).trim() : 'Bar';
        // ANIQ moslik (registr/bo'shliq farqsiz). Ilgari ILIKE '%...%' ishlatilib 'Bar' → 'Barbeque'ga
        // tushib qolardi (noto'g'ri kategoriya). Topilmasa — quyida yangi kategoriya yaratiladi.
        const found = await client.query(
          `SELECT id FROM menu_categories
           WHERE lower(trim(name)) = lower(trim($1))
           ORDER BY id LIMIT 1`, [cname]);
        if (found.rows.length) catId = found.rows[0].id;
        else {
          const nc = await client.query(`INSERT INTO menu_categories (name) VALUES ($1) RETURNING id`, [cname]);
          catId = nc.rows[0].id;
        }
      }
      // Idempotent: shu ingredientга bog'langan product bo'lsa yangilaymiz, bo'lmasa yaratamiz.
      const ex = await client.query(
        `SELECT id FROM menu_items WHERE ingredient_id = $1 AND type = 'product' ORDER BY is_active DESC, id ASC LIMIT 1`,
        [ing.id]);
      if (ex.rows.length) {
        await client.query(
          `UPDATE menu_items SET price = $1, category_id = COALESCE($2, category_id), is_active = true WHERE id = $3`,
          [sp, catId, ex.rows[0].id]);
      } else {
        await client.query(
          `INSERT INTO menu_items (category_id, name, price, type, ingredient_id, is_active)
           VALUES ($1, $2, $3, 'product', $4, true)`,
          [catId, name, sp, ing.id]);
      }
    }
    await client.query('COMMIT');
    res.status(201).json(ing);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Mahsulot keldi (kirim)
const addIncoming = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { ingredient_id, selling_price, note } = req.body;
    const quantity = parseFloat(req.body.quantity);
    const price_per_unit = parseFloat(req.body.price_per_unit);
    // KIRIM validatsiyasi: miqdor musbat, narx manfiy emas. Aks holda o'rtacha-vaznli
    // tannarx buziladi va kassa chiqimi noto'g'ri bo'ladi. (Manfiy sklad qoldig'i
    // ATAYLAB — bu haqda kirim emas, sotuv/produce javob beradi.)
    if (!(quantity > 0)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Kirim miqdori musbat bo\'lishi kerak' });
    }
    if (!(price_per_unit >= 0) || isNaN(price_per_unit)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Kirim narxi noto\'g\'ri' });
    }
    // Chegirma (partiya bo'yicha) — jami qiymatdan ayiriladi
    const discount = Math.max(0, parseFloat(req.body.discount) || 0);
    const total_amount = Math.max(0, Math.round((quantity * price_per_unit - discount) * 100) / 100);
    const method = req.body.method === 'card' ? 'card' : 'cash';
    // Pul manbasi: Kassadan (default) yoki boshqa joydan. Boshqa bo'lsa Kassadan yechilmaydi.
    const fromKassa = req.body.from_kassa !== false && req.body.from_kassa !== 'false';
    const sourceText = fromKassa ? 'kassa' : ((req.body.source || '').toString().trim().slice(0, 120) || 'boshqa');
    // To'langan summa: berilmasa TO'LIQ to'langan (eski xulq) — qolgani postavshik qarzi
    const paidAmount = (req.body.paid_amount !== undefined && req.body.paid_amount !== null && req.body.paid_amount !== '')
      ? Math.min(total_amount, Math.max(0, parseFloat(req.body.paid_amount) || 0))
      : total_amount;

    const inc = await client.query(
      `INSERT INTO stock_incoming (ingredient_id, quantity, price_per_unit, total_amount, note, method, source)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
      [ingredient_id, quantity, price_per_unit, total_amount, note, method, sourceText]
    );

    // Mahsulot nomi (kassa izohi + menyu upsert uchun bir marta o'qiymiz)
    const ingRow = await client.query(`SELECT name, unit FROM ingredients WHERE id = $1`, [ingredient_id]);
    const ingName = (ingRow.rows[0] && ingRow.rows[0].name) ? ingRow.rows[0].name : 'Mahsulot';

    // PARTIYA (F10): har kirim = alohida partiya, o'z narxi/srok/qarzi bilan.
    const supplierId = await resolveSupplierId(client, req.body);
    let payerName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      payerName = u.rows.length ? u.rows[0].full_name : null;
    }
    const lot = await createLot(client, {
      ingredientId: ingredient_id, quantity, unit: ingRow.rows[0] ? ingRow.rows[0].unit : null,
      unitCost: price_per_unit, discount, supplierId,
      invoiceNo: (req.body.invoice_no || '').toString().trim().slice(0, 80) || null,
      purchaseDate: (req.body.purchase_date && /^\d{4}-\d{2}-\d{2}$/.test(req.body.purchase_date)) ? req.body.purchase_date : null,
      expiryDate: (req.body.expiry_date && /^\d{4}-\d{2}-\d{2}$/.test(req.body.expiry_date)) ? req.body.expiry_date : null,
      paidAmount: 0, // to'lov quyida supplier_payments orqali yoziladi (tarix bilan)
      note: note || null, sourceIncomingId: inc.rows[0].id,
      createdBy: req.user ? req.user.id : null, createdByName: payerName,
    });

    // To'lov: paid_amount qismi to'lov tarixiga + (kassadan bo'lsa) kassa chiqimi.
    // Qolgani partiya qarzi bo'lib turadi (F13 ledger ko'radi).
    if (paidAmount > 0) {
      const txNote = note && note.toString().trim() ? `${ingName} — ${note}` : `${ingName} (sklad kirim)`;
      await addSupplierPayment(client, {
        supplierId, lotId: lot.id, amount: paidAmount, method,
        fromKassa, note: txNote, paidBy: req.user ? req.user.id : null, paidByName: payerName,
      });
    }

    // "Sotuvga chiqarish" (retail) — is_retail bo'lsa selling_price yoziladi; aks holda TEGILMAYDI
    // (ilgari bu yerda selling_price=0 yuborilib, sotuvdagi narx nolga tushib qolardi — endi tuzatildi).
    const spRaw = (selling_price !== undefined && selling_price !== null) ? parseFloat(selling_price) : null;
    const isRetail = (req.body.is_retail === true || req.body.is_retail === 'true')
      || (req.body.is_retail === undefined && spRaw !== null && spRaw > 0);
    const catId = (req.body.category_id !== undefined && req.body.category_id !== null && req.body.category_id !== '')
      ? parseInt(req.body.category_id) : null;

    // O'rtacha-vaznli tannarx uchun kirimning NET birlik narxi (chegirma hisobga olingan):
    // total_amount = quantity*narx - chegirma; netUnit = total_amount/quantity. Chegirma 0 bo'lsa
    // netUnit === price_per_unit (xulq o'zgarmaydi). Bu 'average' metod COGS'ini ham chegirmaga mos qiladi.
    const netUnit = quantity > 0 ? Math.round((total_amount / quantity) * 10000) / 10000 : price_per_unit;

    if (isRetail && spRaw !== null && spRaw > 0) {
      // O'RTACHA-VAZNLI (moving average) tannarx: eski qoldiq × eski narx + kirim × NET kirim narxi, bo'lingan jami qoldiqqa.
      // Eski qoldiq/narx 0 yoki manfiy bo'lsa — faqat kirim narxi (0 bilan o'rtachalab pasaytirmaymiz).
      await client.query(
        `UPDATE ingredients
         SET price_per_unit = CASE WHEN stock_quantity > 0 AND price_per_unit > 0
               THEN (stock_quantity * price_per_unit + $1::numeric * $2::numeric) / (stock_quantity + $1::numeric)
               ELSE $2::numeric END,
             stock_quantity = stock_quantity + $1,
             selling_price = $3
         WHERE id = $4`,
        [quantity, netUnit, spRaw, ingredient_id]
      );
      // Menyu UPSERT: bog'langan product menyu yozuvi bo'lsa narx+kategoriyani YANGILAYMIZ (arxivdan ham qaytaramiz),
      // bo'lmasa YANGI product yaratamiz. Shunday qilib kirim oynasidagi kategoriya/narx haqiqatan saqlanadi.
      const ex = await client.query(
        `SELECT id FROM menu_items WHERE ingredient_id = $1 AND type = 'product' ORDER BY is_active DESC, id ASC LIMIT 1`,
        [ingredient_id]
      );
      if (ex.rows.length) {
        await client.query(
          `UPDATE menu_items SET price = $1, category_id = COALESCE($2, category_id), is_active = true WHERE id = $3`,
          [spRaw, catId, ex.rows[0].id]
        );
      } else {
        // getMenuItems menyu kategoriya bilan INNER JOIN qiladi — category_id NULL bo'lsa taom
        // umuman ko'rinmaydi (sotib bo'lmaydi). Yangi retail taomga kategoriya majburiy: berilmasa
        // 'Bar' ni aniq topamiz yoki yaratamiz (createIngredient ko'prigi bilan bir xil).
        let insertCatId = catId;
        if (!insertCatId) {
          const fc = await client.query(
            `SELECT id FROM menu_categories WHERE lower(trim(name)) = lower(trim($1)) ORDER BY id LIMIT 1`, ['Bar']);
          if (fc.rows.length) insertCatId = fc.rows[0].id;
          else {
            const nc = await client.query(`INSERT INTO menu_categories (name) VALUES ($1) RETURNING id`, ['Bar']);
            insertCatId = nc.rows[0].id;
          }
        }
        await client.query(
          `INSERT INTO menu_items (category_id, name, price, type, ingredient_id, is_active)
           VALUES ($1, $2, $3, 'product', $4, true)`,
          [insertCatId, ingName, spRaw, ingredient_id]
        );
      }
    } else {
      // Oshxona ingredienti — O'RTACHA-VAZNLI tannarx (NET narx bilan), selling_price tegilmaydi.
      await client.query(
        `UPDATE ingredients
         SET price_per_unit = CASE WHEN stock_quantity > 0 AND price_per_unit > 0
               THEN (stock_quantity * price_per_unit + $1::numeric * $2::numeric) / (stock_quantity + $1::numeric)
               ELSE $2::numeric END,
             stock_quantity = stock_quantity + $1
         WHERE id = $3`,
        [quantity, netUnit, ingredient_id]
      );
    }

    await logAudit(client, {
      req, action: 'stock.incoming', entityType: 'ingredient', entityId: parseInt(ingredient_id),
      newValue: {
        lot_id: lot.id, lot_code: lot.lot_code, quantity, price_per_unit,
        total: total_amount, paid: paidAmount, debt: Math.round((total_amount - paidAmount) * 100) / 100,
        supplier_id: supplierId, invoice_no: lot.invoice_no, expiry_date: lot.expiry_date,
      },
      reason: note || null, userName: payerName,
    });
    await client.query('COMMIT');
    // Narx o'zgardi -> shu masaliqni ishlatgan P/F tannarxlarини qayta hisoblaymiz (retsept narxlari yangilanadi)
    try {
      const { syncPfCostsUsingIngredient } = require('./menuController');
      await syncPfCostsUsingIngredient(ingredient_id);
    } catch (_) {}
    res.status(201).json({ message: 'Mahsulot qabul qilindi!', total_amount, lot_id: lot.id, lot_code: lot.lot_code });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Kirim tarixi
const getIncomingHistory = async (req, res) => {
  try {
    const { ingredient_id } = req.query;
    let query = `
      SELECT si.*, i.name as ingredient_name, i.unit
      FROM stock_incoming si
      JOIN ingredients i ON si.ingredient_id = i.id
    `;
    const params = [];
    if (ingredient_id) {
      query += ` WHERE si.ingredient_id = $1`;
      params.push(ingredient_id);
    }
    query += ` ORDER BY si.created_at DESC LIMIT 50`;
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Kam qolgan mahsulotlar
const getLowStock = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM ingredients
       WHERE min_quantity > 0 AND stock_quantity <= min_quantity
       ORDER BY stock_quantity ASC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sotish narxini yangilash
const updateSellingPrice = async (req, res) => {
  try {
    const { id } = req.params;
    const { selling_price } = req.body;
    const result = await pool.query(
      `UPDATE ingredients SET selling_price = $1 WHERE id = $2 RETURNING *`,
      [selling_price, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulotni TAHRIRLASH — nom, birlik, min, kirim narxi, sotish narxi, qoldiq.
// SABAB majburiy. Har o'zgarish stock_change_log ga yoziladi (kim/nima/nega).
const editIngredient = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const reason = (req.body.reason || '').toString().trim();
    if (!reason) {
      return res.status(400).json({ message: 'Sabab yozish shart!' });
    }
    const { name, unit, min_quantity, price_per_unit, selling_price, stock_quantity } = req.body;

    await client.query('BEGIN');
    const cur = await client.query('SELECT * FROM ingredients WHERE id = $1', [id]);
    if (cur.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Mahsulot topilmadi!' });
    }
    const old = cur.rows[0];

    // Berilmagan (undefined/'') maydonlar eski qiymatda qoladi
    const has = (v) => v !== undefined && v !== null && v.toString().trim() !== '';
    const nName = has(name) ? name.toString().trim() : old.name;
    const nUnit = has(unit) ? unit.toString().trim() : old.unit;
    const nMin = has(min_quantity) ? parseFloat(min_quantity) : parseFloat(old.min_quantity || 0);
    const nPrice = has(price_per_unit) ? parseFloat(price_per_unit) : parseFloat(old.price_per_unit || 0);
    const nSell = has(selling_price) ? parseFloat(selling_price) : parseFloat(old.selling_price || 0);
    const nStock = has(stock_quantity) ? parseFloat(stock_quantity) : parseFloat(old.stock_quantity || 0);

    const num = (v) => parseFloat(v || 0);
    const diff = (a, b) => Math.abs(num(a) - num(b)) > 1e-9;
    const parts = [];
    if (nName !== old.name) parts.push(`Nomi: "${old.name}" -> "${nName}"`);
    if (nUnit !== old.unit) parts.push(`Birlik: "${old.unit}" -> "${nUnit}"`);
    if (diff(nMin, old.min_quantity)) parts.push(`Min: ${num(old.min_quantity)} -> ${nMin}`);
    if (diff(nPrice, old.price_per_unit)) parts.push(`Kirim narxi: ${num(old.price_per_unit)} -> ${nPrice}`);
    if (diff(nSell, old.selling_price)) parts.push(`Sotish narxi: ${num(old.selling_price)} -> ${nSell}`);
    if (diff(nStock, old.stock_quantity)) parts.push(`Qoldiq: ${num(old.stock_quantity)} -> ${nStock}`);

    if (parts.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Hech narsa o\'zgarmadi' });
    }

    await client.query(
      `UPDATE ingredients
       SET name = $1, unit = $2, min_quantity = $3, price_per_unit = $4,
           selling_price = $5, stock_quantity = $6
       WHERE id = $7`,
      [nName, nUnit, nMin, nPrice, nSell, nStock, id]
    );

    // AUDIT-FIX #5: retail mahsulot sotish narхi o'zgarsa — bog'langan MENYU (product) narхini
    // ham yangilaymiz. Aks holda kassa ESKI narхда pробить qilardi (undercharge). Nom o'zgarса ham moslaymiz.
    if (nSell > 0 && diff(nSell, old.selling_price)) {
      await client.query(`UPDATE menu_items SET price = $1 WHERE ingredient_id = $2 AND type = 'product'`, [nSell, id]);
    }
    if (nName !== old.name) {
      await client.query(`UPDATE menu_items SET name = $1 WHERE ingredient_id = $2 AND type = 'product'`, [nName, id]);
    }

    // PARTIYA SINXRON: qoldiq qo'lda o'zgartirilsa partiyalar ham moslashadi
    // (aks holda qoldiq ≠ partiyalar yig'indisi bo'lib qoladi).
    const stockDelta = Math.round((nStock - num(old.stock_quantity)) * 1000) / 1000;
    if (Math.abs(stockDelta) > 0.0005) {
      if (stockDelta > 0) {
        // ko'paytirildi — korrektirovka partiyasi (joriy narxda, qarzsiz)
        await createLot(client, {
          ingredientId: parseInt(id), quantity: stockDelta, unit: nUnit,
          unitCost: nPrice, note: `Qo'lda korrektirovka: ${reason}`,
          createdBy: req.user ? req.user.id : null,
        });
      } else {
        // kamaytirildi — partiyalardan chegiriladi (qoldiq allaqachon yozildi)
        await consumeStock(client, {
          ingredientId: parseInt(id), quantity: -stockDelta,
          reason: 'manual', refType: 'manual', refId: null,
          note: `Qo'lda korrektirovka: ${reason}`, adjustIngredient: false,
        });
      }
    }

    // Menyu<->sklad NOM SYNC: skladda nom o'zgarsa, bog'langan product/pf menyu nomi ham yangilanadi
    // (menyu = sklad = analitika bir xil bo'lishi uchun).
    if (nName !== old.name) {
      await client.query(
        `UPDATE menu_items SET name = $1 WHERE ingredient_id = $2 AND type IN ('product','pf')`,
        [nName, id]);
    }

    let userName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      userName = u.rows[0] ? u.rows[0].full_name : null;
    }
    await client.query(
      `INSERT INTO stock_change_log (ingredient_id, user_id, user_name, changes, reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, req.user ? req.user.id : null, userName, parts.join('; '), reason]
    );
    await logAudit(client, {
      req, action: 'ingredient.edit', entityType: 'ingredient', entityId: parseInt(id),
      oldValue: { name: old.name, unit: old.unit, min: num(old.min_quantity), price: num(old.price_per_unit), sell: num(old.selling_price), stock: num(old.stock_quantity) },
      newValue: { name: nName, unit: nUnit, min: nMin, price: nPrice, sell: nSell, stock: nStock },
      reason, userName,
    });

    await client.query('COMMIT');
    res.json({ message: 'O\'zgartirildi!', changes: parts.join('; ') });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// P/F TAYYORLASH yoki SOTIB OLISH (ishlab chiqarish).
// body: { ingredient_id, quantity, mode: 'produced'|'bought', price_per_kg?, from_kassa? }
//  mode='produced' (default): retsept komponentlari BATCH bo'yicha chegiriladi (qty/chiqish partiya),
//     P/F qoldig'i +qty, tannarx o'z retseptidan (syncPfCost). Kassaga TEGILMAYDI (ichki ishlab chiqarish).
//  mode='bought': tayyor sotib olindi -> narx/kg + vazn. Komponent chegirilmaydi; P/F +qty, narx = price_per_kg.
//     Kassaga CHIQIM (from_kassa != false bo'lsa) — bu haqiqiy xarid.
const producePf = async (req, res) => {
  const client = await pool.connect();
  try {
    const ingId = parseInt(req.body.ingredient_id);
    const qty = parseFloat(req.body.quantity);
    const mode = req.body.mode === 'bought' ? 'bought' : 'produced';
    if (isNaN(ingId) || !(qty > 0)) {
      return res.status(400).json({ message: 'ingredient_id va musbat quantity kerak' });
    }
    await client.query('BEGIN');
    const mi = await client.query(
      `SELECT id, yield_kg FROM menu_items WHERE type = 'pf' AND ingredient_id = $1 AND is_active = true LIMIT 1`,
      [ingId]
    );
    if (!mi.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Bu masaliq P/F emas' });
    }
    const yieldKg = parseFloat(mi.rows[0].yield_kg) || 0;

    if (mode === 'bought') {
      // SOTIB OLINDI: narx/kg + vazn. Komponent chegirilmaydi. P/F +qty, narx yangilanadi.
      const pricePerKg = parseFloat(req.body.price_per_kg);
      if (!(pricePerKg >= 0)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: 'Sotib olishda kg narxi (price_per_kg) kerak' });
      }
      await client.query(
        `UPDATE ingredients
         SET price_per_unit = CASE WHEN stock_quantity > 0 AND price_per_unit > 0
               THEN (stock_quantity * price_per_unit + $1::numeric * $2::numeric) / (stock_quantity + $1::numeric)
               ELSE $2::numeric END,
             stock_quantity = stock_quantity + $1
         WHERE id = $3`,
        [qty, pricePerKg, ingId]);
      const total = Math.round(qty * pricePerKg * 100) / 100;
      const fromKassa = req.body.from_kassa !== false && req.body.from_kassa !== 'false';
      const inc = await client.query(
        `INSERT INTO stock_incoming (ingredient_id, quantity, price_per_unit, total_amount, note, method, source)
         VALUES ($1, $2, $3, $4, 'P/F sotib olindi', 'cash', $5) RETURNING id`,
        [ingId, qty, pricePerKg, total, fromKassa ? 'kassa' : 'boshqa']);
      // PARTIYA: sotib olingan P/F ham alohida partiya (postavshik/srok bilan)
      const supplierId = await resolveSupplierId(client, req.body);
      const unitRow = await client.query(`SELECT unit FROM ingredients WHERE id = $1`, [ingId]);
      const lot = await createLot(client, {
        ingredientId: ingId, quantity: qty, unit: unitRow.rows[0] ? unitRow.rows[0].unit : null,
        unitCost: pricePerKg, supplierId,
        expiryDate: (req.body.expiry_date && /^\d{4}-\d{2}-\d{2}$/.test(req.body.expiry_date)) ? req.body.expiry_date : null,
        paidAmount: 0, note: 'P/F sotib olindi', sourceIncomingId: inc.rows[0].id,
        createdBy: req.user ? req.user.id : null,
      });
      if (total > 0) {
        await addSupplierPayment(client, {
          supplierId, lotId: lot.id, amount: total, method: 'cash',
          fromKassa, note: 'P/F sotib olindi', paidBy: req.user ? req.user.id : null,
        });
      }
      await logAudit(client, {
        req, action: 'stock.pf_bought', entityType: 'ingredient', entityId: ingId,
        newValue: { lot_id: lot.id, quantity: qty, price_per_kg: pricePerKg, total },
      });
      await client.query('COMMIT');
      return res.json({ ok: true, produced: qty, mode: 'bought', lot_id: lot.id });
    }

    // TAYYORLANDI: retsept komponentlarini BATCH bo'yicha chegiramiz.
    const rec = await client.query(
      `SELECT ingredient_id, quantity FROM recipe_items WHERE menu_item_id = $1`, [mi.rows[0].id]);
    if (!rec.rows.length) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'P/F retsepti bo\'sh — avval retseptini kiriting' });
    }
    // Nechta PARTIYA tayyorlandi: chiqish (yield) berilgan bo'lsa qty/yield; aks holda qty (per-birlik).
    const batches = yieldKg > 0 ? (qty / yieldKg) : qty;
    // Kirim yozuvini OLDIN ochamiz (id sarflarga ref bo'ladi), narxi keyin yoziladi
    const inc = await client.query(
      `INSERT INTO stock_incoming (ingredient_id, quantity, price_per_unit, total_amount, note, method, source)
       VALUES ($1, $2, 0, 0, 'P/F tayyorlash', 'cash', 'pf_production') RETURNING id`,
      [ingId, qty]);
    // Komponentlar PARTIYALARDAN chegiriladi (FIFO/LIFO/AVG — tanlangan metod).
    // Haqiqiy tannarx = sarflangan partiyalar qiymati / chiqqan miqdor.
    let producedCost = 0;
    for (const r of rec.rows) {
      const used = await consumeStock(client, {
        ingredientId: r.ingredient_id,
        quantity: batches * parseFloat(r.quantity),
        reason: 'pf_production', refType: 'pf', refId: inc.rows[0].id,
      });
      producedCost += used.totalCost;
    }
    const unitCost = qty > 0 ? Math.round(producedCost / qty * 10000) / 10000 : 0;
    await client.query(
      `UPDATE stock_incoming SET price_per_unit = $1, total_amount = $2 WHERE id = $3`,
      [unitCost, Math.round(producedCost * 100) / 100, inc.rows[0].id]);
    // P/F qoldig'i +qty, narxi o'rtacha-vaznli (haqiqiy ishlab chiqarish narxi bilan)
    await client.query(
      `UPDATE ingredients
       SET price_per_unit = CASE WHEN stock_quantity > 0 AND price_per_unit > 0
             THEN (stock_quantity * price_per_unit + $1::numeric * $2::numeric) / (stock_quantity + $1::numeric)
             ELSE $2::numeric END,
           stock_quantity = stock_quantity + $1
       WHERE id = $3`,
      [qty, unitCost, ingId]);
    // Tayyorlangan P/F ham PARTIYA bo'ladi (ichki, qarzsiz)
    const unitRow2 = await client.query(`SELECT unit FROM ingredients WHERE id = $1`, [ingId]);
    const pfLot = await createLot(client, {
      ingredientId: ingId, quantity: qty, unit: unitRow2.rows[0] ? unitRow2.rows[0].unit : null,
      unitCost, note: 'P/F tayyorlandi (ichki ishlab chiqarish)',
      sourceIncomingId: inc.rows[0].id, createdBy: req.user ? req.user.id : null,
    });
    await logAudit(client, {
      req, action: 'stock.pf_produced', entityType: 'ingredient', entityId: ingId,
      newValue: { lot_id: pfLot.id, quantity: qty, unit_cost: unitCost, total_cost: Math.round(producedCost * 100) / 100 },
    });
    await client.query('COMMIT');
    res.json({ ok: true, produced: qty, mode: 'produced', unit_cost: unitCost, lot_id: pfLot.id });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Mahsulot o'zgarishlar tarixi (audit)
const getStockHistory = async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT id, changes, reason, user_name, created_at
       FROM stock_change_log
       WHERE ingredient_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mahsulotni o'chirish (faqat ombor bo'sh bo'lsa)
const deleteIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const check = await pool.query(`SELECT stock_quantity FROM ingredients WHERE id = $1`, [id]);
    if (check.rows.length === 0) {
      return res.status(404).json({ message: 'Mahsulot topilmadi!' });
    }
    // Bog'liqlik bormi (retsept / menyu / kirim-inventar tarixi)?
    const deps = await pool.query(
      `SELECT
         (SELECT COUNT(*) FROM recipe_items    WHERE ingredient_id = $1) AS rc,
         (SELECT COUNT(*) FROM menu_items      WHERE ingredient_id = $1) AS mc,
         (SELECT COUNT(*) FROM inventory_items WHERE ingredient_id = $1) AS ic,
         (SELECT COUNT(*) FROM stock_incoming  WHERE ingredient_id = $1) AS sc`,
      [id]);
    const d = deps.rows[0];
    const inUse = ['rc','mc','ic','sc'].some((k) => (parseInt(d[k], 10) || 0) > 0);
    if (inUse) {
      // Bog'langan -> hard delete FK ni buzardi. Shuning uchun ARXIVLAYMIZ (skladdan ketadi, tarix saqlanadi).
      await pool.query(`UPDATE ingredients SET is_active = false WHERE id = $1`, [id]);
      // Menyu<->sklad sync: bu ingredientga bog'langan PRODUCT yoki P/F menyu yozuvini ham arxivlaymiz
      // (P/F ham — aks holda skladdan ketган P/F ishlab-chiqarish/retsept ro'yxatida "faol" bo'lib qolardi)
      await pool.query(`UPDATE menu_items SET is_active = false WHERE ingredient_id = $1 AND type IN ('product', 'pf')`, [id]);
      return res.json({ message: 'Mahsulot arxivlandi (bog\'lanishlari bor — tarix saqlanadi, skladdan olib tashlandi)' });
    }
    // Bog'lanmagan — haqiqiy o'chirish
    try {
      await pool.query(`DELETE FROM ingredients WHERE id = $1`, [id]);
    } catch (e) {
      if (e.code === '23503') { // kutilmagan FK -> arxivlaymiz
        await pool.query(`UPDATE ingredients SET is_active = false WHERE id = $1`, [id]);
        return res.json({ message: 'Mahsulot arxivlandi (bog\'liq yozuvlar bor)' });
      }
      throw e;
    }
    res.json({ message: 'Mahsulot o\'chirildi!' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// DUBLIKATNI BIRLASHTIRISH (merge): :id ni target_id ichiga qo'shadi —
// retseptlar/menyu/inventar target ga perecepilanadi, ombor qoldig'i QO'SHILADI
// (MINUS saqlanadi — ataylab), so'ng :id o'chiriladi. Ishlatilayotgan dublikatni
// shu yo'l bilan tozalash mumkin (oddiy o'chirish taqiqlangan).
const mergeIngredient = async (req, res) => {
  const client = await pool.connect();
  try {
    const id = parseInt(req.params.id);
    const targetId = parseInt(req.body ? req.body.target_id : null);
    if (!id || !targetId || id === targetId) {
      return res.status(400).json({ message: 'target_id kerak va o\'ziga qo\'shib bo\'lmaydi' });
    }
    await client.query('BEGIN');
    const rows = (await client.query(`SELECT id, name, stock_quantity FROM ingredients WHERE id = ANY($1)`, [[id, targetId]])).rows;
    if (rows.length < 2) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Mahsulot topilmadi' }); }
    const src = rows.find((r) => r.id === id);
    // ombor qoldig'ini target ga qo'shamiz (minus saqlanadi — oddiy arifmetika)
    await client.query(`UPDATE ingredients SET stock_quantity = COALESCE(stock_quantity,0) + $1 WHERE id = $2`,
      [parseFloat(src.stock_quantity) || 0, targetId]);
    // ingredient_id ustuni bor BARCHA jadvallarni dinamik perecepilaymiz
    const refTables = (await client.query(
      `SELECT table_name FROM information_schema.columns WHERE column_name='ingredient_id' AND table_schema='public'`
    )).rows.map((r) => r.table_name);
    for (const t of refTables) {
      await client.query(`UPDATE ${t} SET ingredient_id = $1 WHERE ingredient_id = $2`, [targetId, id]);
    }
    // recipe_items kolliziya: bir taomda target ikki marta bo'lsa -> quantity qo'shib bittaga
    const rcol = (await client.query(
      `SELECT menu_item_id, array_agg(id ORDER BY id) ids, SUM(quantity) q
       FROM recipe_items WHERE ingredient_id=$1 GROUP BY menu_item_id HAVING COUNT(*)>1`, [targetId])).rows;
    for (const c of rcol) {
      await client.query(`UPDATE recipe_items SET quantity=$1 WHERE id=$2`, [c.q, c.ids[0]]);
      await client.query(`DELETE FROM recipe_items WHERE id = ANY($1)`, [c.ids.slice(1)]);
    }
    // inventory_items kolliziya: bir inventarizatsiyada target ikki marta
    const icol = (await client.query(
      `SELECT inventory_id, array_agg(id ORDER BY id) ids, SUM(expected_quantity) eq, SUM(actual_quantity) aq, SUM(difference) df
       FROM inventory_items WHERE ingredient_id=$1 GROUP BY inventory_id HAVING COUNT(*)>1`, [targetId])).rows;
    for (const c of icol) {
      await client.query(`UPDATE inventory_items SET expected_quantity=$1, actual_quantity=$2, difference=$3 WHERE id=$4`,
        [c.eq, c.aq, c.df, c.ids[0]]);
      await client.query(`DELETE FROM inventory_items WHERE id = ANY($1)`, [c.ids.slice(1)]);
    }
    await client.query(`DELETE FROM ingredients WHERE id = $1`, [id]);
    await client.query('COMMIT');
    res.json({ ok: true, message: 'Dublikat birlashtirildi' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// ===== SKLADLAR (warehouses) =====

// Skladlar ro'yxati
const getWarehouses = async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM warehouses ORDER BY id`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Yangi sklad
const createWarehouse = async (req, res) => {
  try {
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Sklad nomi kiritilmadi!' });
    }
    const result = await pool.query(
      `INSERT INTO warehouses (name) VALUES ($1) RETURNING *`,
      [name.trim()]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sklad nomini tahrirlash
const updateWarehouse = async (req, res) => {
  try {
    const { id } = req.params;
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Sklad nomi kiritilmadi!' });
    }
    const result = await pool.query(
      `UPDATE warehouses SET name = $1 WHERE id = $2 RETURNING *`,
      [name.trim(), id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Sklad topilmadi!' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sklad o'chirish (faqat ichida mahsulot yo'q bo'lsa)
const deleteWarehouse = async (req, res) => {
  try {
    const { id } = req.params;
    const check = await pool.query(
      `SELECT COUNT(*)::int AS cnt FROM ingredients WHERE warehouse_id = $1`,
      [id]
    );
    if (check.rows[0].cnt > 0) {
      return res.status(400).json({ message: 'Sklad bo\'sh emas! Avval mahsulotlarni o\'chiring yoki ko\'chiring.' });
    }
    await pool.query(`DELETE FROM warehouses WHERE id = $1`, [id]);
    res.json({ message: 'Sklad o\'chirildi!' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Retsept bo'yicha ingredientlarni skladga biriktirish
// body: { warehouse_id, category_name?, name_like? }
const assignFromRecipe = async (req, res) => {
  try {
    const { warehouse_id, category_name, name_like } = req.body;
    if (!warehouse_id) {
      return res.status(400).json({ message: 'warehouse_id kerak!' });
    }
    const conditions = [];
    const params = [warehouse_id];
    if (category_name && category_name.trim()) {
      params.push(`%${category_name.trim()}%`);
      conditions.push(`mc.name ILIKE $${params.length}`);
    }
    if (name_like && name_like.trim()) {
      params.push(`%${name_like.trim()}%`);
      conditions.push(`mi.name ILIKE $${params.length}`);
    }
    if (conditions.length === 0) {
      return res.status(400).json({ message: 'Kamida kategoriya nomi yoki taom nomi kiriting!' });
    }

    const result = await pool.query(
      `UPDATE ingredients SET warehouse_id = $1
       WHERE id IN (
         SELECT DISTINCT ri.ingredient_id
         FROM recipe_items ri
         JOIN menu_items mi ON ri.menu_item_id = mi.id
         LEFT JOIN menu_categories mc ON mi.category_id = mc.id
         WHERE ${conditions.join(' OR ')}
       )
       RETURNING id`,
      params
    );

    res.json({
      message: `${result.rowCount} ta ingredient biriktirildi`,
      count: result.rowCount,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ─── INGREDIENT KATEGORIYALAR (ETAP 3.1 spravochnik — menu_categories kabi, id bo'yicha) ───
const getIngredientCategories = async (req, res) => {
  try {
    const r = await pool.query(
      `SELECT id, name, COALESCE(is_pf,false) AS is_pf, COALESCE(is_retail,false) AS is_retail
       FROM ingredient_categories ORDER BY name`);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};
const createIngredientCategory = async (req, res) => {
  try {
    const name = (req.body.name || '').toString().trim();
    if (!name) return res.status(400).json({ message: 'Nom kerak' });
    const is_pf = req.body.is_pf === true || req.body.is_pf === 'true';
    const is_retail = req.body.is_retail === true || req.body.is_retail === 'true';
    const r = await pool.query(
      `INSERT INTO ingredient_categories (name, is_pf, is_retail) VALUES ($1,$2,$3)
       ON CONFLICT (name) DO UPDATE SET is_pf=EXCLUDED.is_pf, is_retail=EXCLUDED.is_retail RETURNING *`,
      [name, is_pf, is_retail]);
    res.status(201).json(r.rows[0]);
  } catch (err) { res.status(500).json({ message: err.message }); }
};
const updateIngredientCategory = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const name = (req.body.name || '').toString().trim();
    if (!name) { client.release(); return res.status(400).json({ message: 'Nom kerak' }); }
    await client.query('BEGIN');
    const old = await client.query(`SELECT 1 FROM ingredient_categories WHERE id=$1`, [id]);
    if (!old.rows.length) { await client.query('ROLLBACK'); client.release(); return res.status(404).json({ message: 'Topilmadi' }); }
    await client.query(`UPDATE ingredient_categories SET name=$1 WHERE id=$2`, [name, id]);
    // rename propagatsiya (id bo'yicha): shu kategoriyали ingredientlarning string nomi ham yangilanadi
    await client.query(`UPDATE ingredients SET category=$1 WHERE category_id=$2`, [name, id]);
    await client.query('COMMIT');
    res.json({ ok: true, name });
  } catch (err) { await client.query('ROLLBACK').catch(()=>{}); res.status(500).json({ message: err.message }); }
  finally { client.release(); }
};
const deleteIngredientCategory = async (req, res) => {
  try {
    const { id } = req.params;
    const used = await pool.query(`SELECT COUNT(*)::int AS n FROM ingredients WHERE category_id=$1`, [id]);
    if (used.rows[0].n > 0) return res.status(400).json({ message: `Kategoriyada ${used.rows[0].n} ta mahsulot bor — avval ko'chiring.` });
    await pool.query(`DELETE FROM ingredient_categories WHERE id=$1`, [id]);
    res.json({ message: 'Kategoriya o\'chirildi' });
  } catch (err) {
    if (err.code === '23503') return res.status(400).json({ message: 'Kategoriya ishlatilmoqda.' });
    res.status(500).json({ message: err.message });
  }
};

// ===== ТРАНСФЕР: перенос товара между складами =====
// Списывает quantity с from_ingredient_id (основной склад) и добавляет на to_ingredient_id (бар).
// Оба ингредиента должны быть одним и тем же товаром, но в разных warehouse.
// body: { from_ingredient_id, to_ingredient_id, quantity, note }
const transferStock = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const fromId = parseInt(req.body.from_ingredient_id);
    let toId = parseInt(req.body.to_ingredient_id) || null;
    const toWarehouseId = (req.body.to_warehouse_id != null && req.body.to_warehouse_id !== '') ? parseInt(req.body.to_warehouse_id) : null;
    const quantity = parseFloat(req.body.quantity);
    const note = (req.body.note || '').toString().trim() || null;

    if (!fromId) { await client.query('ROLLBACK'); return res.status(400).json({ message: 'from_ingredient_id обязателен' }); }
    if (!(quantity > 0)) { await client.query('ROLLBACK'); return res.status(400).json({ message: 'Количество должно быть больше 0' }); }

    // Манба ingredient (қулфлаб)
    const fr = await client.query(`SELECT * FROM ingredients WHERE id=$1 FOR UPDATE`, [fromId]);
    if (!fr.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Мahsulot topilmadi' }); }
    const fromIng = fr.rows[0];

    // Мaqsad: to_ingredient_id berilsa — o'sha; aks holda to_warehouse_id даги SHU NOMdagi
    // ingredientни topamiz, bo'lmasa YARATAMIZ (bir xil nom/o'lchov/kategoriya, boshqa sklad, narх=manba tannarхi).
    if (!toId) {
      if (!toWarehouseId || toWarehouseId === fromIng.warehouse_id) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: 'Выберите другой склад (to_warehouse_id)' });
      }
      const ex = await client.query(
        `SELECT id FROM ingredients WHERE warehouse_id=$1 AND lower(trim(name))=lower(trim($2)) LIMIT 1`,
        [toWarehouseId, fromIng.name]);
      if (ex.rows.length) toId = ex.rows[0].id;
      else {
        const nc = await client.query(
          `INSERT INTO ingredients (name, unit, stock_quantity, min_quantity, price_per_unit, selling_price, category, warehouse_id)
           VALUES ($1,$2,0,0,$3,0,$4,$5) RETURNING id`,
          [fromIng.name, fromIng.unit, fromIng.price_per_unit || 0, fromIng.category, toWarehouseId]);
        toId = nc.rows[0].id;
      }
    }
    if (toId === fromId) { await client.query('ROLLBACK'); return res.status(400).json({ message: 'Один склад — перемещение не нужно' }); }
    const tr = await client.query(`SELECT id, name, unit, warehouse_id FROM ingredients WHERE id=$1 FOR UPDATE`, [toId]);
    if (!tr.rows.length) { await client.query('ROLLBACK'); return res.status(404).json({ message: 'Целевой товар не найден' }); }
    const toIng = tr.rows[0];

    // Списываем с исходного склада (stock_quantity может уйти в минус — намеренно, как в остальном коде)
    const { totalCost } = await consumeStock(client, {
      ingredientId: fromId,
      quantity,
      reason: 'transfer',
      refType: 'transfer',
      refId: null,
      note: note || `Трансфер → ${toIng.name}`,
    });

    // Себестоимость единицы переданного товара
    const unitCost = quantity > 0 ? Math.round((totalCost / quantity) * 10000) / 10000 : parseFloat(fromIng.price_per_unit) || 0;

    // Добавляем на целевой склад (скользящее среднее)
    await client.query(
      `UPDATE ingredients
       SET price_per_unit = CASE WHEN stock_quantity > 0 AND price_per_unit > 0
             THEN (stock_quantity * price_per_unit + $1::numeric * $2::numeric) / (stock_quantity + $1::numeric)
             ELSE $2::numeric END,
           stock_quantity = stock_quantity + $1
       WHERE id = $3`,
      [quantity, unitCost, toId]
    );

    // Записываем партию на целевом складе (для истории лотов)
    await createLot(client, {
      ingredientId: toId,
      quantity,
      unit: toIng.unit,
      unitCost,
      note: note || `Трансфер с склада: ${fromIng.name}`,
      createdBy: req.user ? req.user.id : null,
    });

    // Запись в stock_incoming для целевого склада (история)
    await client.query(
      `INSERT INTO stock_incoming (ingredient_id, quantity, price_per_unit, total_amount, note, method, source)
       VALUES ($1, $2, $3, $4, $5, 'cash', 'transfer')`,
      [toId, quantity, unitCost, Math.round(totalCost * 100) / 100,
       note || `Трансфер с: ${fromIng.name}`]
    );

    // Ko'chirish TARIXI (skladdan skladga) — alohida jadval, from→to ko'rinsin
    await client.query(
      `INSERT INTO stock_transfers (from_ingredient_id, to_ingredient_id, from_warehouse_id, to_warehouse_id, name, quantity, unit, unit_cost, note)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [fromId, toId, fromIng.warehouse_id, toIng.warehouse_id, fromIng.name, quantity, fromIng.unit, unitCost, note]);

    let userName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      userName = u.rows.length ? u.rows[0].full_name : null;
    }
    await logAudit(client, {
      req, action: 'stock.transfer', entityType: 'ingredient', entityId: fromId,
      newValue: { from_id: fromId, to_id: toId, quantity, unit_cost: unitCost, total_cost: totalCost },
      reason: note, userName,
    });

    await client.query('COMMIT');
    res.json({
      ok: true,
      message: `Перенесено ${quantity} ${fromIng.unit} → ${toIng.name}`,
      transferred: quantity,
      unit_cost: unitCost,
      total_cost: Math.round(totalCost * 100) / 100,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

// Ko'chirishlar TARIXI (skladdan skladga) — sklad nomlari bilan
const getTransfers = async (req, res) => {
  try {
    const limit = Math.min(300, Math.max(1, parseInt(req.query.limit, 10) || 100));
    const r = await pool.query(
      `SELECT t.id, t.name, t.quantity, t.unit, t.unit_cost, t.note,
              to_char(t.created_at,'YYYY-MM-DD HH24:MI') AS dt,
              wf.name AS from_warehouse, wt.name AS to_warehouse
       FROM stock_transfers t
       LEFT JOIN warehouses wf ON wf.id = t.from_warehouse_id
       LEFT JOIN warehouses wt ON wt.id = t.to_warehouse_id
       ORDER BY t.created_at DESC, t.id DESC LIMIT $1`, [limit]);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ message: err.message }); }
};

// ═══════════ SKLAD SVERKA (reconcile) ═══════════
// Retsept KECH kiritilgan bo'lsa, o'sha paytdagi sotuvlarда xom masaliq skladdan AYRILMAGAN
// (deductStock retsept bo'yicha ishlaydi, retsept bo'lmasa 0 ayiradi). Bu — «kutilgan» (retsept×sotuv)
// va «haqiqiy» (lot_consumptions reason=sale) farqini topadi va (fix) yetishmaganini minuslaydi.
// Idempotent: tuzatish reason='reconcile' bilan yoziladi va keyingi hisobда «haqiqiy»га qo'shiladi → qayta 0.
const RECONCILE_SQL = `
  WITH paid AS (SELECT id FROM orders WHERE status='paid'),
  expected AS (
    SELECT mi.ingredient_id AS ing, SUM(oi.quantity) AS qty
      FROM order_items oi JOIN paid o ON o.id=oi.order_id JOIN menu_items mi ON mi.id=oi.menu_item_id
      WHERE mi.type='product' AND mi.ingredient_id IS NOT NULL
      GROUP BY mi.ingredient_id
    UNION ALL
    SELECT ri.ingredient_id, SUM(ri.quantity*oi.quantity)
      FROM order_items oi JOIN paid o ON o.id=oi.order_id JOIN menu_items mi ON mi.id=oi.menu_item_id
      JOIN recipe_items ri ON ri.menu_item_id=mi.id
      WHERE NOT (mi.type='product' AND mi.ingredient_id IS NOT NULL)
      GROUP BY ri.ingredient_id
  ),
  exp AS (SELECT ing, SUM(qty) AS expected FROM expected GROUP BY ing),
  act AS (
    SELECT ingredient_id AS ing, SUM(quantity) AS deducted
      FROM lot_consumptions
      WHERE reason='reconcile' OR (reason='sale' AND ref_type='order' AND ref_id IN (SELECT id FROM paid))
      GROUP BY ingredient_id
  )
  SELECT i.id AS ingredient_id, i.name, i.unit, i.stock_quantity,
         ROUND(COALESCE(e.expected,0)::numeric,3) AS expected,
         ROUND(COALESCE(a.deducted,0)::numeric,3) AS deducted,
         ROUND((COALESCE(e.expected,0)-COALESCE(a.deducted,0))::numeric,3) AS gap
  FROM exp e FULL JOIN act a ON a.ing=e.ing
  JOIN ingredients i ON i.id = COALESCE(e.ing, a.ing)
`;

const getStockReconcile = async (req, res) => {
  try {
    const r = await pool.query(`SELECT * FROM (${RECONCILE_SQL}) q WHERE gap > 0.001 ORDER BY gap DESC`);
    res.json({ items: r.rows, count: r.rows.length });
  } catch (err) { res.status(500).json({ message: err.message }); }
};

const fixStockReconcile = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const r = await client.query(`SELECT * FROM (${RECONCILE_SQL}) q WHERE gap > 0.001`);
    let fixed = 0;
    for (const row of r.rows) {
      await consumeStock(client, {
        ingredientId: row.ingredient_id, quantity: parseFloat(row.gap),
        reason: 'reconcile', refType: 'reconcile', refId: null,
        note: 'Retsept kech kiritilgani uchun sverka — skladdan ayrildi',
      });
      fixed++;
    }
    if (req.user && req.user.id) {
      await logAudit(client, { req, action: 'stock.reconcile', entityType: 'ingredient', entityId: null,
        newValue: { fixed }, reason: 'Retsept kech kiritilgani uchun sverka' });
    }
    await client.query('COMMIT');
    res.json({ ok: true, fixed, message: `${fixed} mahsulot bo'yicha sklad tuzatildi` });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally { client.release(); }
};

// ===== ДЕЛЕНИЕ ТОРТА НА КУСОЧКИ =====
// Берёт ingredient (целый торт в баре) и делит его на кусочки:
//   - stock_quantity умножается на slices_count
//   - unit меняется на 'кус' (кусочек)
//   - selling_price = slice_price
//   - В меню создаётся/обновляется позиция «Торт — 1 кусочек» с ценой slice_price
// body: { ingredient_id, slices_count, slice_price, menu_category_id, note }
const divideIntoSlices = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const ingId = parseInt(req.body.ingredient_id);
    const slicesCount = parseInt(req.body.slices_count);
    const slicePrice = parseFloat(req.body.slice_price);
    const note = (req.body.note || '').toString().trim() || null;
    const catId = req.body.menu_category_id ? parseInt(req.body.menu_category_id) : null;

    if (!ingId || !(slicesCount >= 2))
      return res.status(400).json({ message: 'ingredient_id и slices_count (≥2) обязательны' });
    if (!(slicePrice > 0))
      return res.status(400).json({ message: 'Цена кусочка должна быть больше 0' });

    const ingRow = await client.query(
      `SELECT id, name, unit, stock_quantity, price_per_unit, selling_price
       FROM ingredients WHERE id = $1 FOR UPDATE`,
      [ingId]
    );
    if (!ingRow.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Ингредиент не найден' });
    }
    const ing = ingRow.rows[0];
    const wholeQty = parseFloat(ing.stock_quantity) || 0;
    if (!(wholeQty > 0)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: `На складе нет остатка (${wholeQty}). Сначала сделайте приход.` });
    }

    const newQty = Math.round(wholeQty * slicesCount * 1000) / 1000;
    // Себестоимость 1 кусочка = цена всего торта / количество кусочков
    const sliceCost = parseFloat(ing.price_per_unit) > 0
      ? Math.round((parseFloat(ing.price_per_unit) / slicesCount) * 10000) / 10000
      : 0;

    // Обновляем остаток и единицу измерения
    await client.query(
      `UPDATE ingredients
       SET stock_quantity = $1,
           unit = 'кус',
           price_per_unit = $2,
           selling_price = $3
       WHERE id = $4`,
      [newQty, sliceCost, slicePrice, ingId]
    );

    // Корректируем открытые лоты: пересчитываем их количество
    // (все активные лоты умножаем на slicesCount, unit_cost делим)
    await client.query(
      `UPDATE stock_lots
       SET quantity = quantity * $1,
           used_quantity = used_quantity * $1,
           unit = 'кус',
           unit_cost = CASE WHEN $1 > 0 THEN unit_cost / $1 ELSE unit_cost END,
           note = COALESCE(note, '') || ' [разделён на ${slicesCount} кус.]'
       WHERE ingredient_id = $2 AND status IN ('active','depleted')`,
      [slicesCount, ingId]
    );

    // Обновляем/создаём позицию в меню
    const sliceName = `${ing.name} (1 кус.)`;
    const ex = await client.query(
      `SELECT id FROM menu_items WHERE ingredient_id = $1 AND type = 'product' ORDER BY is_active DESC, id ASC LIMIT 1`,
      [ingId]
    );
    if (ex.rows.length) {
      await client.query(
        `UPDATE menu_items SET price = $1, name = $2,
              category_id = COALESCE($3, category_id), is_active = true
         WHERE id = $4`,
        [slicePrice, sliceName, catId, ex.rows[0].id]
      );
    } else {
      await client.query(
        `INSERT INTO menu_items (category_id, name, price, type, ingredient_id, is_active)
         VALUES ($1, $2, $3, 'product', $4, true)`,
        [catId, sliceName, slicePrice, ingId]
      );
    }

    // Записываем в лог
    let userName = null;
    if (req.user && req.user.id) {
      const u = await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.id]);
      userName = u.rows.length ? u.rows[0].full_name : null;
    }
    await client.query(
      `INSERT INTO stock_change_log (ingredient_id, user_id, user_name, changes, reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        ingId,
        req.user ? req.user.id : null,
        userName,
        `Разделён на кусочки: ${wholeQty} шт × ${slicesCount} кус = ${newQty} кус. Цена кус: ${slicePrice}`,
        note || 'Деление торта на кусочки',
      ]
    );
    await logAudit(client, {
      req, action: 'stock.divide_slices', entityType: 'ingredient', entityId: ingId,
      newValue: { whole_qty: wholeQty, slices_count: slicesCount, new_qty: newQty, slice_price: slicePrice, slice_cost: sliceCost },
      reason: note, userName,
    });

    await client.query('COMMIT');
    res.json({
      ok: true,
      message: `${ing.name}: ${wholeQty} шт → ${newQty} кусочков по ${slicePrice} сум`,
      whole_qty: wholeQty,
      slices_count: slicesCount,
      new_qty: newQty,
      slice_price: slicePrice,
      slice_cost: sliceCost,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ message: err.message });
  } finally {
    client.release();
  }
};

module.exports = {
  getIngredients, createIngredient, addIncoming, getIncomingHistory, getLowStock, updateSellingPrice, deleteIngredient,
  mergeIngredient,
  editIngredient, getStockHistory, producePf,
  transferStock, getTransfers, getStockReconcile, fixStockReconcile, divideIntoSlices,
  getWarehouses, createWarehouse, updateWarehouse, deleteWarehouse, assignFromRecipe,
  getIngredientCategories, createIngredientCategory, updateIngredientCategory, deleteIngredientCategory
};