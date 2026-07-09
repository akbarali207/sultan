const pool = require('./src/config/db');
(async () => {
  const out = {};
  try {
    const av = await pool.query(`SELECT column_name FROM information_schema.columns WHERE table_name='menu_items' AND column_name='available'`);
    out.available_exists = av.rows.length > 0;
    const dt = await pool.query(`SELECT column_name FROM information_schema.columns WHERE table_name='menu_items' AND column_name='daily_tracked'`);
    out.daily_tracked_exists = dt.rows.length > 0;
    const ds = await pool.query(`SELECT to_regclass('public.daily_stock') AS reg`);
    out.daily_stock_regclass = ds.rows[0].reg;
    try {
      await pool.query(`SELECT name FROM menu_items WHERE id = ANY($1) AND available = false`, [[1]]);
      out.stoplist_query = 'OK';
    } catch (e) { out.stoplist_query = 'ERROR: ' + e.message; }
    try {
      await pool.query(`SELECT mi.id, mi.name, ds.opening_qty FROM menu_items mi JOIN daily_stock ds ON ds.menu_item_id = mi.id AND ds.biz_date = (NOW() - INTERVAL '150 minutes')::date WHERE mi.id = ANY($1) AND mi.daily_tracked = true`, [[1]]);
      out.daily_query = 'OK';
    } catch (e) { out.daily_query = 'ERROR: ' + e.message; }
    console.log(JSON.stringify(out, null, 2));
  } catch (err) {
    console.log('CONNECT_OR_QUERY_FAIL: ' + err.message);
  } finally {
    await pool.end();
  }
})();
