// ============================================================
// ETAP 2-4 — MENU dublikatlarini XAVFSIZ birlashtirish (SSOT).
// Bir tool — index.js talab qilmaydi. backend/.env dan ulanadi (prodda POS-PC lokal DB).
//
// XAVFSIZLIK:
//   * DRY-RUN (default): faqat REJANI chop etadi, HECH NARSA o'zgartirmaydi.
//   * --apply: TRANZAKSIYADA bajaradi. Undan OLDIN pg_dump backup shart!
//   * Faqat ANIQ dublikatlarni oladi: bir xil (nom + kategoriya + narx + ingredient).
//     Kategoriya/narx/ingredient farq qilsa — TEGMAYDI (Маракуйя/Тархун/Бон филе himoyada).
//   * "Asosiy" = eng ko'p SOTILGAN (order_items) nusxa; qolganlar unga ko'chiriladi + ARXIVLANADI (soft).
//
// Ishga tushirish (POS-PC da):
//   node backend/merge_menu_dups.js            # DRY-RUN — rejani ko'rsatadi
//   node backend/merge_menu_dups.js --apply    # BACKUPdan keyin — bajaradi
// ============================================================
const pool = require('./src/config/db');
const APPLY = process.argv.includes('--apply');

async function main() {
  const c = await pool.connect();
  try {
    // ANIQ dublikat guruhlar: bir xil normalize-nom + kategoriya + narx + ingredient
    const groups = await c.query(`
      SELECT lower(btrim(name)) AS nkey, category_id, price, COALESCE(ingredient_id,0) AS ing,
             array_agg(id ORDER BY id) AS ids, MIN(name) AS sample
      FROM menu_items
      WHERE is_active = true
      GROUP BY lower(btrim(name)), category_id, price, COALESCE(ingredient_id,0)
      HAVING COUNT(*) > 1
      ORDER BY 1`);

    if (!groups.rows.length) { console.log('Aniq dublikat topilmadi.'); return; }
    console.log(`${APPLY ? '[APPLY]' : '[DRY-RUN]'} ${groups.rows.length} ta aniq dublikat guruh:\n`);

    if (APPLY) await c.query('BEGIN');
    let mergedRows = 0, repointedOrders = 0;

    for (const g of groups.rows) {
      const ids = g.ids;
      // Har nusxaning sotuv soni -> asosiy = eng ko'p sotilgan (teng bo'lsa eng kichik id)
      const sales = await c.query(
        `SELECT menu_item_id, COUNT(*)::int n FROM order_items WHERE menu_item_id = ANY($1) GROUP BY 1`, [ids]);
      const salesMap = {}; for (const s of sales.rows) salesMap[s.menu_item_id] = s.n;
      const main = [...ids].sort((a, b) => (salesMap[b]||0) - (salesMap[a]||0) || a - b)[0];
      const dups = ids.filter((x) => x !== main);

      console.log(`  "${g.sample.trim()}" -> ASOSIY #${main} (${salesMap[main]||0} zakaz); ko'chiriladi+arxiv: ${dups.map(d=>`#${d}(${salesMap[d]||0})`).join(', ')}`);

      if (APPLY) {
        for (const d of dups) {
          const r = await c.query(`UPDATE order_items SET menu_item_id=$1 WHERE menu_item_id=$2`, [main, d]);
          repointedOrders += r.rowCount;
          await c.query(`UPDATE recipe_items SET menu_item_id=$1 WHERE menu_item_id=$2`, [main, d]).catch(()=>{});
          await c.query(`DELETE FROM menu_item_stations WHERE menu_item_id=$1`, [d]).catch(()=>{});
          await c.query(`UPDATE menu_items SET is_active=false WHERE id=$1`, [d]);
          mergedRows++;
        }
      }
    }

    // Ortiqcha probel tozalash (barcha menu_items) — xavfsiz normalizatsiya
    const trimmed = await c.query(
      `SELECT COUNT(*)::int n FROM menu_items WHERE name <> regexp_replace(btrim(name),'\\s+',' ','g')`);
    console.log(`\nOrtiqcha probelli nomlar: ${trimmed.rows[0].n} ta`);
    if (APPLY) {
      await c.query(`UPDATE menu_items SET name = regexp_replace(btrim(name),'\\s+',' ','g')
                     WHERE name <> regexp_replace(btrim(name),'\\s+',' ','g')`);
    }

    if (APPLY) {
      await c.query('COMMIT');
      console.log(`\n✓ BAJARILDI: ${mergedRows} nusxa arxivlandi, ${repointedOrders} order_items ko'chirildi, nomlar tozalandi.`);
    } else {
      console.log('\n[DRY-RUN] Hech narsa o\'zgarmadi. Bajarish: backup -> `node backend/merge_menu_dups.js --apply`');
    }
  } catch (e) {
    if (APPLY) await c.query('ROLLBACK').catch(()=>{});
    console.error('XATO (o\'zgarish qaytarildi):', e.message);
  } finally {
    c.release(); await pool.end();
  }
}
main();
