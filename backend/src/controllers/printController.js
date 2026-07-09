const pool = require('../config/db');
const escpos = require('../services/escpos');

// Chop etilmagan zakazlar — bo'limlar bo'yicha guruhlangan (print-agent uchun)
const getPending = async (req, res) => {
  try {
    const rows = await pool.query(
      `SELECT o.id as order_id, o.notes as order_notes, o.created_at,
              t.number as table_number, t.name as table_name,
              u.full_name as waiter_name,
              oi.id as item_id, oi.quantity, oi.notes as item_notes,
              mi.name as item_name,
              ps.id as station_id, ps.name as station_name,
              ps.printer_ip, ps.printer_port, ps.printer_name
       FROM orders o
       LEFT JOIN tables t ON o.table_id = t.id
       LEFT JOIN users u ON o.waiter_id = u.id
       JOIN order_items oi ON oi.order_id = o.id
       JOIN menu_items mi ON oi.menu_item_id = mi.id
       LEFT JOIN menu_item_stations mis ON mis.menu_item_id = mi.id
       LEFT JOIN print_stations ps ON COALESCE(mis.station_id, mi.station_id) = ps.id
       WHERE oi.printed = false
       ORDER BY o.created_at, ps.id`
    );

    // order_id -> { ..., stations: { station_id -> {...items} } }
    const orders = {};
    for (const r of rows.rows) {
      if (!orders[r.order_id]) {
        orders[r.order_id] = {
          order_id: r.order_id,
          table_number: r.table_number ?? r.table_name,
          waiter_name: r.waiter_name || '',
          notes: r.order_notes || '',
          created_at: r.created_at,
          item_ids: [],
          stations: {},
        };
      }
      const sid = r.station_id || 0;
      const o = orders[r.order_id];
      if (!o.stations[sid]) {
        o.stations[sid] = {
          station_id: r.station_id,
          station_name: r.station_name || 'Oshxona',
          printer_ip: r.printer_ip,
          printer_port: r.printer_port || 9100,
          printer_name: r.printer_name,
          items: [],
        };
      }
      if (r.item_id != null) o.item_ids.push(r.item_id);
      o.stations[sid].items.push({
        name: r.item_name,
        quantity: r.quantity,
        notes: r.item_notes || '',
      });
    }

    // stations obyektini massivga aylantiramiz
    const result = Object.values(orders).map((o) => ({
      ...o,
      stations: Object.values(o.stations),
    }));

    res.json(result);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Zakaz chop etildi deb belgilash
const markPrinted = async (req, res) => {
  try {
    const { id } = req.params;
    // Faqat AYNAN chop etilgan qatorlarni (agent /pending dan olgan item_ids) belgilaymiz.
    // Chop oynasida qo'shilgan yangi taom belgilamay qoladi — keyingi siklda chekiga chiqadi (jim yo'qolmaydi).
    const ids = Array.isArray(req.body && req.body.item_ids)
      ? req.body.item_ids.map((x) => parseInt(x, 10)).filter((x) => Number.isInteger(x))
      : null;
    if (ids && ids.length) {
      await pool.query(
        `UPDATE order_items SET printed = true WHERE order_id = $1 AND printed = false AND id = ANY($2::int[])`,
        [id, ids]
      );
    } else if (ids && ids.length === 0) {
      // Agent aniq "hech qanday qator chop etilmadi" dedi — hech narsani belgilamaymiz
    } else {
      // Eski agent (item_ids yubormaydi) — orqaga moslik uchun eski xatti-harakat
      await pool.query(`UPDATE order_items SET printed = true WHERE order_id = $1 AND printed = false`, [id]);
    }
    await pool.query(`UPDATE orders SET printed = true WHERE id = $1`, [id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Mijoz cheki (bill) chiqarilmagan to'langan zakazlar — narx + jami bilan
const getPendingBills = async (req, res) => {
  try {
    const rows = await pool.query(
      `SELECT o.id as order_id, o.total_amount, o.created_at, o.notes,
              o.discount_percent, o.final_amount,
              t.number as table_number, t.name as table_name,
              u.full_name as waiter_name,
              oi.quantity, oi.price, mi.name as item_name
       FROM orders o
       LEFT JOIN tables t ON o.table_id = t.id
       LEFT JOIN users u ON o.waiter_id = u.id
       JOIN order_items oi ON oi.order_id = o.id
       JOIN menu_items mi ON oi.menu_item_id = mi.id
       WHERE o.bill_requested = true
       ORDER BY o.created_at`
    );

    // Bill qaysi printerga chiqadi — birinchi sozlangan bo'lim printeri (kassa)
    const pr = await pool.query(
      `SELECT printer_ip, printer_port, printer_name FROM print_stations
       WHERE is_active = true AND (printer_ip IS NOT NULL OR printer_name IS NOT NULL)
       ORDER BY id LIMIT 1`
    );
    const printer = pr.rows[0] || {};

    const orders = {};
    for (const r of rows.rows) {
      if (!orders[r.order_id]) {
        orders[r.order_id] = {
          order_id: r.order_id,
          table_number: r.table_number ?? r.table_name,
          waiter_name: r.waiter_name || '',
          notes: r.notes || '',
          created_at: r.created_at,
          total_amount: r.total_amount,
          discount_percent: r.discount_percent,
          final_amount: r.final_amount,
          printer_ip: printer.printer_ip || null,
          printer_port: printer.printer_port || 9100,
          printer_name: printer.printer_name || null,
          items: [],
        };
      }
      orders[r.order_id].items.push({
        name: r.item_name,
        quantity: r.quantity,
        price: r.price,
      });
    }
    res.json(Object.values(orders));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const markBillPrinted = async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query(`UPDATE orders SET bill_requested = false, bill_printed = true WHERE id = $1`, [id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// ATMEN (bekor) cheklari — chop etilmaganlari, bo'lim printeri ma'lumoti bilan
const getPendingCancels = async (req, res) => {
  try {
    const rows = await pool.query(
      `SELECT ct.id, ct.order_id, ct.table_name, ct.waiter_name, ct.items, ct.created_at,
              ps.name AS station_name, ps.printer_ip, ps.printer_port, ps.printer_name
       FROM cancel_tickets ct
       LEFT JOIN print_stations ps ON ct.station_id = ps.id
       WHERE ct.printed = false
       ORDER BY ct.id`
    );
    res.json(rows.rows.map((r) => {
      let items = [];
      try { items = JSON.parse(r.items || '[]'); } catch (_) { /* buzuq JSON — bo'sh */ }
      return {
        id: r.id,
        order_id: r.order_id,
        table_number: r.table_name,
        waiter_name: r.waiter_name,
        station_name: r.station_name || 'Oshxona',
        printer_ip: r.printer_ip,
        printer_port: r.printer_port || 9100,
        printer_name: r.printer_name,
        created_at: r.created_at,
        items,
      };
    }));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

const markCancelPrinted = async (req, res) => {
  try {
    await pool.query(`UPDATE cancel_tickets SET printed = true WHERE id = $1`, [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Kompdagi o'rnatilgan Windows printerlar ro'yxati (admin UI uchun — telefondan ham ishlaydi)
const listPrinters = async (req, res) => {
  try {
    const names = await escpos.listWindowsPrinters();
    res.json(names);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
};

// Sinov cheki — berilgan printerga test chiqaradi (printerni ANIQLASH uchun)
// Body: { printer_name } yoki { printer_ip, printer_port }, ixtiyoriy { label }
const testPrint = async (req, res) => {
  try {
    const { printer_name, printer_ip, printer_port, label } = req.body || {};
    if (!printer_name && !printer_ip) {
      return res.status(400).json({ ok: false, message: 'printer_name yoki printer_ip kerak' });
    }
    const title = label || printer_name || printer_ip;
    const info = [];
    if (printer_ip) {
      info.push('Tarmoq (IP): ' + printer_ip + ' : ' + (printer_port || 9100));
    } else {
      info.push('USB printer: ' + printer_name);
    }
    const t = new Date();
    const p = (n) => String(n).padStart(2, '0');
    info.push('Vaqt: ' + `${p(t.getHours())}:${p(t.getMinutes())}:${p(t.getSeconds())}`);

    const slip = escpos.buildTestSlip(title, info);
    if (printer_ip) {
      await escpos.sendToPrinter(printer_ip, printer_port || 9100, slip);
    } else {
      await escpos.sendToUsb(printer_name, slip);
    }
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ ok: false, message: err.message });
  }
};

module.exports = { getPending, markPrinted, getPendingBills, markBillPrinted, getPendingCancels, markCancelPrinted, listPrinters, testPrint };
