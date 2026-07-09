// ============================================================================
// SULTAN — БЕЗОПАСНЫЙ ДЕДУП КАТАЛОГА (ингредиенты + строки рецептов)
// ----------------------------------------------------------------------------
// Что делает:
//   * Находит дубли ингредиентов САМ, по нормализованному имени (регистр,
//     пробелы, скобки, знаки игнорируются) В ПРЕДЕЛАХ ОДНОГО СКЛАДА.
//   * Складывает их остатки в один "главный" (минусы сохраняются — это НЕ баг).
//   * Перецепляет ВСЕ ссылки (recipe_items, menu_items, inventory_items,
//     stock_incoming, stock_change_log и любые др. с колонкой ingredient_id).
//   * Схлопывает задвоенные строки рецептов (один ингредиент 2 раза в блюде).
//   * Ставит блок на будущие дубли (уникальный индекс по складу+имени).
//
// ЧЕГО НЕ ДЕЛАЕТ (безопасность живого сервера):
//   * НЕ трогает orders / order_items / cash_transactions / debts / смены.
//   * НЕ ставит CHECK >= 0 на склад (минус разрешён — так задумано).
//   * НЕ сливает ингредиенты между разными складами (только внутри склада).
//
// ЗАПУСК на POS-компьютере (там, где стоит D:\sultan и работает backend):
//   1) Просмотр (ничего не меняет):     node dedup_catalog.js
//   2) Реально применить (с бэкапом):   APPLY=1 node dedup_catalog.js
//   3) Если pg_dump недоступен и вы    APPLY=1 SKIP_BACKUP=1 node dedup_catalog.js
//      сделали бэкап сами:
//
// ID-независим: работает на любой копии базы, не зависит от конкретных id.
// ============================================================================
const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const ROOT = __dirname;                          // D:\sultan
const BACKEND = path.join(ROOT, 'backend');
// creds из backend/.env (на POS-PC там свой пароль — берём оттуда)
try { require(path.join(BACKEND, 'node_modules', 'dotenv')).config({ path: path.join(BACKEND, '.env') }); } catch (_) {}
const { Pool } = require(path.join(BACKEND, 'node_modules', 'pg'));

const DB = {
  host: process.env.DB_HOST || 'localhost',
  port: +(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || 'sultan_db',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'sultan123',
};
const APPLY = process.env.APPLY === '1';          // иначе DRY-RUN (откат)
const SKIP_BACKUP = process.env.SKIP_BACKUP === '1';

// нормализованный ключ имени (тот же, что в блок-индексе)
const KEY = `lower(regexp_replace(name,'[^0-9A-Za-zА-Яа-яЁё]','','g'))`;

function backup() {
  if (!APPLY || SKIP_BACKUP) return true;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const dir = path.join(ROOT, 'backups');
  try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
  const out = path.join(dir, `sultan_before_dedup_${stamp}.dump`);
  console.log(`Бэкап → ${out} ...`);
  const r = spawnSync('pg_dump',
    ['-h', DB.host, '-p', String(DB.port), '-U', DB.user, '-d', DB.database, '-Fc', '-f', out],
    { env: { ...process.env, PGPASSWORD: DB.password }, encoding: 'utf8' });
  if (r.status === 0 && fs.existsSync(out) && fs.statSync(out).size > 0) {
    console.log(`Бэкап OK (${(fs.statSync(out).size / 1024).toFixed(0)} КБ)\n`);
    return true;
  }
  console.error('!! Бэкап НЕ создан (pg_dump недоступен?). ' +
    (r.error ? r.error.message : (r.stderr || '')).trim());
  console.error('   Сделайте бэкап вручную или запустите с SKIP_BACKUP=1 (на свой риск).\n');
  return false;
}

async function main() {
  if (!backup()) { process.exitCode = 1; return; }

  const pool = new Pool(DB);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // какие таблицы ссылаются на ingredients (динамически — ничего не пропустим)
    const refTables = (await client.query(
      `SELECT table_name FROM information_schema.columns
       WHERE column_name='ingredient_id' AND table_schema='public' ORDER BY table_name`
    )).rows.map(r => r.table_name);
    console.log('Таблицы со ссылкой ingredient_id:', refTables.join(', ') || '(нет)');

    const totBefore = (await client.query(
      `SELECT COUNT(*) n, COALESCE(SUM(stock_quantity),0) s FROM ingredients`)).rows[0];
    const recBefore = (await client.query(`SELECT COUNT(*) n FROM recipe_items`)).rows[0].n;

    // группы дублей внутри склада
    const groups = (await client.query(`
      SELECT warehouse_id, ${KEY} AS k,
             array_agg(id ORDER BY id) ids, array_agg(name ORDER BY id) names, COUNT(*) n
      FROM ingredients
      GROUP BY warehouse_id, ${KEY}
      HAVING COUNT(*) > 1
      ORDER BY warehouse_id, k`)).rows;

    console.log(`\nДО: ingredients=${totBefore.n}, sum(stock)=${totBefore.s}, recipe_items=${recBefore}`);
    console.log(`Групп дублей ингредиентов (внутри склада): ${groups.length}\n`);

    let removed = 0;
    for (const g of groups) {
      const ids = g.ids;
      // главный = у кого больше ссылок в рецептах (иначе — меньший id)
      const cnt = (await client.query(
        `SELECT ingredient_id, COUNT(*) c FROM recipe_items WHERE ingredient_id = ANY($1) GROUP BY 1`, [ids])).rows;
      const cmap = Object.fromEntries(cnt.map(r => [r.ingredient_id, +r.c]));
      let canon = ids[0], best = -1;
      for (const id of ids) { const c = cmap[id] || 0; if (c > best) { best = c; canon = id; } }
      const dupes = ids.filter(id => id !== canon);

      const sum = (await client.query(
        `SELECT COALESCE(SUM(stock_quantity),0) s FROM ingredients WHERE id = ANY($1)`, [ids])).rows[0].s;
      await client.query(`UPDATE ingredients SET stock_quantity=$1 WHERE id=$2`, [sum, canon]);
      for (const t of refTables) {
        await client.query(`UPDATE ${t} SET ingredient_id=$1 WHERE ingredient_id = ANY($2)`, [canon, dupes]);
      }
      await client.query(`DELETE FROM ingredients WHERE id = ANY($1)`, [dupes]);
      removed += dupes.length;
      console.log(`  склад ${g.warehouse_id}: "${g.names.join('" + "')}" → главный #${canon}, остаток=${sum}, удалено ${dupes.length}`);
    }

    // схлопнуть задвоенные строки рецептов (один ингредиент дважды в блюде)
    const rcol = (await client.query(`
      SELECT menu_item_id, ingredient_id, array_agg(id ORDER BY id) ids, SUM(quantity) q
      FROM recipe_items GROUP BY 1,2 HAVING COUNT(*) > 1`)).rows;
    let recCollapsed = 0;
    for (const c of rcol) {
      const keep = c.ids[0], drop = c.ids.slice(1);
      await client.query(`UPDATE recipe_items SET quantity=$1 WHERE id=$2`, [c.q, keep]);
      await client.query(`DELETE FROM recipe_items WHERE id = ANY($1)`, [drop]);
      recCollapsed += drop.length;
    }
    console.log(`\nЗадвоенных строк рецептов схлопнуто: ${rcol.length} групп, удалено ${recCollapsed} строк (кол-во просуммировано)`);

    // схлопнуть задвоенные строки инвентаризации (если есть таблица)
    let invCollapsed = 0;
    if (refTables.includes('inventory_items')) {
      const icol = (await client.query(`
        SELECT inventory_id, ingredient_id, array_agg(id ORDER BY id) ids,
               SUM(expected_quantity) eq, SUM(actual_quantity) aq, SUM(difference) df
        FROM inventory_items WHERE ingredient_id IS NOT NULL
        GROUP BY 1,2 HAVING COUNT(*) > 1`)).rows;
      for (const c of icol) {
        const keep = c.ids[0], drop = c.ids.slice(1);
        await client.query(`UPDATE inventory_items SET expected_quantity=$1, actual_quantity=$2, difference=$3 WHERE id=$4`,
          [c.eq, c.aq, c.df, keep]);
        await client.query(`DELETE FROM inventory_items WHERE id = ANY($1)`, [drop]);
        invCollapsed += drop.length;
      }
      console.log(`Задвоенных строк инвентаризации схлопнуто: удалено ${invCollapsed} строк`);
    }

    // ===== ВЕРИФИКАЦИЯ =====
    const totAfter = (await client.query(
      `SELECT COUNT(*) n, COALESCE(SUM(stock_quantity),0) s FROM ingredients`)).rows[0];
    let orphans = 0;
    for (const t of refTables) {
      const o = (await client.query(
        `SELECT COUNT(*) n FROM ${t} x WHERE x.ingredient_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM ingredients i WHERE i.id = x.ingredient_id)`)).rows[0].n;
      orphans += Number(o);
    }
    const dupLeft = (await client.query(`
      SELECT COUNT(*) n FROM (SELECT 1 FROM ingredients GROUP BY warehouse_id, ${KEY} HAVING COUNT(*)>1) q`)).rows[0].n;
    const recDupLeft = (await client.query(`
      SELECT COUNT(*) n FROM (SELECT 1 FROM recipe_items GROUP BY menu_item_id, ingredient_id HAVING COUNT(*)>1) q`)).rows[0].n;

    const stockOk = Number(totBefore.s).toFixed(3) === Number(totAfter.s).toFixed(3);
    console.log(`\n=== ВЕРИФИКАЦИЯ ===`);
    console.log(`ingredients: ${totBefore.n} → ${totAfter.n} (удалено ${removed})`);
    console.log(`ИНВАРИАНТ sum(stock): ${totBefore.s} → ${totAfter.s} ${stockOk ? '✓ сохранён' : '✗✗ НАРУШЕН'}`);
    console.log(`orphan ссылок: ${orphans} (должно 0)`);
    console.log(`остаток дублей ингредиентов: ${dupLeft} (должно 0)`);
    console.log(`остаток задвоенных строк рецептов: ${recDupLeft} (должно 0)`);

    if (!stockOk || Number(orphans) !== 0 || Number(dupLeft) !== 0 || Number(recDupLeft) !== 0) {
      throw new Error('Верификация не прошла — откат, база не изменена');
    }

    if (APPLY) {
      // блок на будущие дубли: уникален по (склад, нормализованное имя)
      await client.query(`CREATE UNIQUE INDEX IF NOT EXISTS uniq_ingredient_key
        ON ingredients (warehouse_id, ${KEY})`);
      console.log(`\nБлок uniq_ingredient_key (склад+нормализованное имя) — установлен ✓`);
      await client.query('COMMIT');
      console.log('\n*** ПРИМЕНЕНО (COMMIT). Каталог почищен. ***');
    } else {
      await client.query('ROLLBACK');
      console.log('\n*** DRY-RUN: откат, база НЕ изменена. Для применения: APPLY=1 node dedup_catalog.js ***');
    }
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('\nОШИБКА → откат:', e.message);
    process.exitCode = 1;
  } finally {
    client.release(); await pool.end();
  }
}
main();
