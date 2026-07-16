// ============================================================
// TANNARX DVIJOKI (FIFO / LIFO / O'RTACHA-VAZNLI) + partiya sarfi.
// BARCHA sklad chegirishlari shu yerdan o'tadi: sotuv, P/F ishlab
// chiqarish, spisaniya, inventarizatsiya. Har sarf lot_consumptions ga
// O'SHA PAYTDAGI narx bilan yoziladi — metod keyin o'zgarsa ham tarixiy
// COGS o'zgarmaydi (F11 talabi).
//
// MUHIM: ingredients.stock_quantity JAMI qoldiq SSOT bo'lib qoladi va
// MINUSGA tushishi mumkin (ataylab). Partiyalar minusga tushmaydi —
// partiyalar yetmagan sarf lot_id=NULL yozuv bilan qayd etiladi.
// ============================================================
const pool = require('../config/db');

const METHODS = ['fifo', 'lifo', 'average'];

// Sozlamani o'qish (tranzaksiya ichida ham ishlaydi — client beriladi)
async function getSetting(db, key, def = null) {
  try {
    const r = await db.query('SELECT value FROM app_settings WHERE key = $1', [key]);
    return r.rows.length ? r.rows[0].value : def;
  } catch (_) {
    return def; // jadval hali yo'q bo'lsa — default (fail-open, eski xulq)
  }
}

async function getCostingMethod(db) {
  const m = await getSetting(db, 'costing_method', 'average');
  return METHODS.includes(m) ? m : 'average';
}

// YANGI PARTIYA (har kirim = alohida partiya; aralashtirish taqiqlangan)
async function createLot(client, {
  ingredientId, quantity, unit, unitCost, discount = 0, supplierId = null,
  invoiceNo = null, purchaseDate = null, expiryDate = null, paidAmount = null,
  note = null, sourceIncomingId = null, createdBy = null, createdByName = null,
}) {
  const qty = parseFloat(quantity);
  const cost = parseFloat(unitCost) || 0;
  const disc = Math.max(0, parseFloat(discount) || 0);
  const total = Math.max(0, Math.round((qty * cost - disc) * 100) / 100);
  // paidAmount berilmasa to'liq to'langan hisoblanadi (eski xulq bilan mos)
  const paid = paidAmount === null || paidAmount === undefined
    ? total
    : Math.min(total, Math.max(0, parseFloat(paidAmount) || 0));
  const r = await client.query(
    `INSERT INTO stock_lots
       (ingredient_id, supplier_id, invoice_no, purchase_date, expiry_date,
        quantity, unit, unit_cost, discount_amount, total_cost, paid_amount,
        status, note, source_incoming_id, created_by, created_by_name)
     VALUES ($1,$2,$3,COALESCE($4::date, CURRENT_DATE),$5,$6,$7,$8,$9,$10,$11,'active',$12,$13,$14,$15)
     RETURNING *`,
    [ingredientId, supplierId, invoiceNo, purchaseDate || null, expiryDate || null,
     qty, unit || null, cost, disc, total, paid, note, sourceIncomingId, createdBy, createdByName]
  );
  const lot = r.rows[0];
  await client.query(
    `UPDATE stock_lots SET lot_code = 'LOT-' || LPAD(id::text, 6, '0') WHERE id = $1`,
    [lot.id]
  );
  lot.lot_code = 'LOT-' + String(lot.id).padStart(6, '0');
  return lot;
}

// SKLADDAN SARF — yagona chegirish yo'li.
// 1) ingredients.stock_quantity -= qty (minus ruxsat — eski xulq saqlanadi)
// 2) partiyalardan metod tartibida chegiradi (FIFO/LIFO; average ham fizik FIFO)
// 3) har chegirish lot_consumptions ga narx-snapshot bilan yoziladi
// Narx: fifo/lifo -> partiyaning o'z narxi; average -> joriy o'rtacha narx.
// Qaytadi: { totalCost, method, parts: [{lot_id, quantity, unit_cost}] }
// adjustIngredient=false: ingredients.stock_quantity ALLAQACHON yangilangan
// (masalan, qo'lda tahrir absolyut qiymat yozgan) — faqat partiyalar chegiriladi.
async function consumeStock(client, { ingredientId, quantity, reason, refType = null, refId = null, note = null, adjustIngredient = true }) {
  const need = Math.round(parseFloat(quantity) * 1000) / 1000;
  if (!(need > 0)) return { totalCost: 0, method: null, parts: [] };

  const method = await getCostingMethod(client);

  // Ingredient qatorini qulflaymiz (parallel sotuvlar partiyani ikki marta olmasin)
  const ing = adjustIngredient
    ? await client.query(
        `UPDATE ingredients SET stock_quantity = stock_quantity - $1
         WHERE id = $2 RETURNING price_per_unit`,
        [need, ingredientId])
    : await client.query(
        `SELECT price_per_unit FROM ingredients WHERE id = $1 FOR UPDATE`, [ingredientId]);
  if (!ing.rows.length) throw new Error(`Ingredient ${ingredientId} topilmadi`);
  const avgPrice = parseFloat(ing.rows[0].price_per_unit) || 0;

  const order = method === 'lifo'
    ? 'received_at DESC, id DESC'
    : 'received_at ASC, id ASC'; // fifo va average — fizik FIFO (srok nazorati uchun ham to'g'ri)
  const lots = await client.query(
    `SELECT id, quantity, used_quantity, unit_cost, total_cost
     FROM stock_lots
     WHERE ingredient_id = $1 AND status = 'active' AND (quantity - used_quantity) > 0
     ORDER BY ${order}
     FOR UPDATE`,
    [ingredientId]
  );

  let left = need;
  const parts = [];
  for (const lot of lots.rows) {
    if (left <= 0) break;
    const remaining = Math.round((parseFloat(lot.quantity) - parseFloat(lot.used_quantity)) * 1000) / 1000;
    if (remaining <= 0) continue;
    const take = Math.min(remaining, left);
    left = Math.round((left - take) * 1000) / 1000;
    const depleted = remaining - take <= 0.0005;
    await client.query(
      `UPDATE stock_lots SET used_quantity = used_quantity + $1,
              status = CASE WHEN $2 THEN 'depleted' ELSE status END
       WHERE id = $3`,
      [take, depleted, lot.id]
    );
    // fifo/lifo COGS = partiyaning HAQIQIY birlik tannarxi = total_cost/quantity
    // (chegirma hisobga olinadi — unit_cost brutto narx bo'lib, chegirma total_cost dan
    // ayirilgan; brutto narxni ishlatish COGS ni chegirma qadar oshirib yuborardi).
    const lotQty = parseFloat(lot.quantity) || 0;
    const netUnitCost = lotQty > 0
      ? Math.round((parseFloat(lot.total_cost) / lotQty) * 10000) / 10000
      : parseFloat(lot.unit_cost);
    parts.push({
      lot_id: lot.id,
      quantity: take,
      unit_cost: method === 'average' ? avgPrice : netUnitCost,
    });
  }
  // Partiyalar yetmadi — qoldiq minusga ketdi (ataylab). Sarf baribir qayd etiladi.
  if (left > 0) {
    parts.push({ lot_id: null, quantity: left, unit_cost: avgPrice });
  }

  let totalCost = 0;
  for (const p of parts) {
    totalCost += p.quantity * p.unit_cost;
    await client.query(
      `INSERT INTO lot_consumptions
         (lot_id, ingredient_id, quantity, unit_cost, cost_method, reason, ref_type, ref_id, note)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [p.lot_id, ingredientId, p.quantity, p.unit_cost, method, reason, refType, refId, note]
    );
  }
  return { totalCost: Math.round(totalCost * 100) / 100, method, parts };
}

// SARFNI QAYTARISH (zakaz o'chirildi/qayta ochildi) — aynan qaysi
// partiyalardan chegirilgan bo'lsa, o'shalarga qaytadi (net bo'yicha:
// oldin qaytarilganlar qayta qaytarilmaydi).
// Qaytadi: qaytarilgan ingredient'lar ro'yxati; bo'sh bo'lsa — bu ref
// uchun partiya yozuvi yo'q (eski, migratsiyadan oldingi zakaz) —
// chaqiruvchi legacy retsept-matematika bilan qaytarishi kerak.
async function restoreConsumption(client, { refType, refId, note = null }) {
  const rows = await client.query(
    `SELECT lot_id, ingredient_id, unit_cost, cost_method, SUM(quantity) AS net
     FROM lot_consumptions
     WHERE ref_type = $1 AND ref_id = $2
     GROUP BY lot_id, ingredient_id, unit_cost, cost_method
     HAVING SUM(quantity) > 0.0005`,
    [refType, refId]
  );
  // DEADLOCK OLDINI OLISH: consumeStock qulflash tartibi ingredient -> lot.
  // Bu yerda ham AVVAL ingredient qatorlarini (id bo'yicha tartibda) qulflaymiz,
  // keyin lotlarni — aks holda AB-BA deadlock bo'lardi (sotuv vs bekor bir vaqtda).
  const ingIds = [...new Set(rows.rows.map((r) => r.ingredient_id))].sort((a, b) => a - b);
  if (ingIds.length) {
    await client.query(
      `SELECT id FROM ingredients WHERE id = ANY($1) ORDER BY id FOR UPDATE`, [ingIds]);
  }
  const restored = [];
  for (const r of rows.rows) {
    const qty = Math.round(parseFloat(r.net) * 1000) / 1000;
    if (r.lot_id) {
      await client.query(
        `UPDATE stock_lots
         SET used_quantity = GREATEST(0, used_quantity - $1),
             status = CASE WHEN status = 'depleted' THEN 'active' ELSE status END
         WHERE id = $2`,
        [qty, r.lot_id]
      );
    }
    await client.query(
      `UPDATE ingredients SET stock_quantity = stock_quantity + $1 WHERE id = $2`,
      [qty, r.ingredient_id]
    );
    await client.query(
      `INSERT INTO lot_consumptions
         (lot_id, ingredient_id, quantity, unit_cost, cost_method, reason, ref_type, ref_id, note)
       VALUES ($1,$2,$3,$4,$5,'restore',$6,$7,$8)`,
      [r.lot_id, r.ingredient_id, -qty, r.unit_cost, r.cost_method, refType, refId, note]
    );
    restored.push({ ingredient_id: r.ingredient_id, lot_id: r.lot_id, quantity: qty });
  }
  return restored;
}

// POSTAVSHIK TO'LOVI: partiya qarzini kamaytiradi, tarixga yozadi,
// kassadan bo'lsa cash_transactions ga chiqim (source='supplier').
async function addSupplierPayment(client, {
  supplierId = null, lotId = null, amount, method = 'cash', fromKassa = true,
  note = null, paidBy = null, paidByName = null,
}) {
  const amt = Math.round((parseFloat(amount) || 0) * 100) / 100;
  if (!(amt > 0)) throw new Error("To'lov summasi musbat bo'lishi kerak");
  const m = method === 'card' ? 'card' : 'cash';

  if (lotId) {
    const lot = await client.query(
      `SELECT id, supplier_id, total_cost, paid_amount FROM stock_lots WHERE id = $1 FOR UPDATE`,
      [lotId]
    );
    if (!lot.rows.length) throw new Error('Partiya topilmadi');
    const debt = Math.round((parseFloat(lot.rows[0].total_cost) - parseFloat(lot.rows[0].paid_amount)) * 100) / 100;
    if (amt > debt + 0.01) throw new Error(`To'lov (${amt}) partiya qarzidan (${debt}) katta`);
    if (!supplierId) supplierId = lot.rows[0].supplier_id;
    await client.query(
      `UPDATE stock_lots SET paid_amount = paid_amount + $1 WHERE id = $2`,
      [amt, lotId]
    );
  }

  const pay = await client.query(
    `INSERT INTO supplier_payments (supplier_id, lot_id, amount, method, from_kassa, note, paid_by, paid_by_name)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
    [supplierId, lotId, amt, m, fromKassa !== false, note, paidBy, paidByName]
  );
  if (fromKassa !== false) {
    await client.query(
      `INSERT INTO cash_transactions (kind, method, amount, source, ref_id, note)
       VALUES ('expense', $1, $2, 'supplier', $3, $4)`,
      [m, amt, pay.rows[0].id, note || "Postavshik to'lovi"]
    );
  }
  return pay.rows[0];
}

module.exports = {
  METHODS, getSetting, getCostingMethod,
  createLot, consumeStock, restoreConsumption, addSupplierPayment,
};
