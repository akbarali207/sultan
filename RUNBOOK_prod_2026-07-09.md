# RUNBOOK — выкат исправлений аудита на прод (POS-PC)

> Все правки лежат в рабочем дереве репо (не закоммичены). Прод = живой POS-PC, БД `sultan_db`.
> Выполняет **владелец/админ**. Делать в НЕрабочее время ресторана. Сначала бэкап.

---

## 0. Бэкап (обязательно, до всего)
```bash
pg_dump -U postgres -h 127.0.0.1 -d sultan_db -F c -f sultan_backup_2026-07-09.dump
```
Проверить, что файл создан и не пустой. Без бэкапа — не продолжать.

---

## 1. Сменить пароль привилегированного директора (P0 — известные креды)
На проде НЕ существует `phone='0000'`, но есть директор с известным паролем (`12` / `director123`). Заменить.

**1.1. Посмотреть директор-аккаунты:**
```sql
SELECT u.id, u.full_name, u.phone
FROM users u JOIN roles r ON r.id = u.role_id
WHERE r.name = 'director';
```
**1.2. Сгенерировать хэш нового пароля** (bcryptjs уже в зависимостях):
```bash
cd backend
node -e "console.log(require('bcryptjs').hashSync(process.argv[1],10))" "ВАШ_НОВЫЙ_СИЛЬНЫЙ_ПАРОЛЬ"
```
**1.3. Обновить пароль** (подставить хэш и нужный id/phone):
```sql
UPDATE users SET password = '<ХЭШ_ИЗ_ШАГА_1.2>' WHERE phone = '12';
```
Проверить вход новым паролем; старый `director123` больше не должен работать.

---

## 2. Выкатить обновлённый бэкенд
Изменённые файлы (скопировать/`git pull` на POS-PC):
- `backend/src/controllers/orderController.js` — цена из БД, аудит reopen, защита долгового нала
- `backend/src/controllers/menuController.js` — себестоимость П/Ф per-unit
- `backend/src/config/db.js`, `backend/src/index.js`, `backend/src/config/runMigrations.js` — обработчики ошибок + баннер миграций
- `backend/src/config/migration_repo_schema_backfill.sql` (новая)
- `backend/src/config/migration_hot_indexes.sql` (новая)
- `backend/src/config/migration_seed_test_director.sql`, `migration_director_phone_0000.sql` — нейтрализованы

**Перезапустить бэкенд.** При старте автоматически применятся 2 новые миграции — обе **идемпотентны и безопасны на проде** (колонки уже есть → NO-OP; индексы малы → мгновенно). В логах убедиться, что НЕТ баннера `[migrate] OGOHLANTIRISH`.

Опционально включить строгий режим на будущее: переменная окружения `MIGRATE_STRICT=true` (тогда битая схема не пройдёт молча).

---

## 3. Пересчитать себестоимость П/Ф (per-unit) — разово
Фикс делает НОВЫЕ расчёты верными, но 6 существующих значений `price_per_unit` у П/Ф на проде пока занижены. Исправить один раз.

**Вариант А (рекомендую, безопаснее — с каскадом):** открыть в админке каждый из 6 П/Ф (`type='pf'`) и пересохранить рецепт (любая правка триггерит `syncPfCost`).

**Вариант Б (SQL, быстрее):** выполнить **дважды** (второй прогон покрывает вложенные П/Ф):
```sql
UPDATE ingredients i
SET price_per_unit = sub.cost
FROM (
  SELECT mi.ingredient_id AS ing_id,
         COALESCE(SUM(ri.quantity * ing2.price_per_unit), 0) AS cost
  FROM menu_items mi
  JOIN recipe_items ri  ON ri.menu_item_id = mi.id
  JOIN ingredients ing2 ON ing2.id = ri.ingredient_id
  WHERE mi.type = 'pf' AND mi.ingredient_id IS NOT NULL
  GROUP BY mi.ingredient_id
) sub
WHERE i.id = sub.ing_id;
```
Проверить: `Катлет Фарш П/Ф` ~583 сум/кг (было 103), `Соус пицца П/Ф` ~140 (было 21).

---

## 4. Данные: 12 ингредиентов с `price_per_unit = 0`
Они занижают food-cost. Найти и проставить реальные закупочные цены:
```sql
SELECT id, name, unit FROM ingredients WHERE price_per_unit IS NULL OR price_per_unit = 0;
```
(Через админку → «Склад» проставить цену прихода.)

---

## 5. (Опционально) Пересобрать Flutter web
Только если нужен согласованный показ «сум/кг» в редакторе рецептов (косметика). Денежная логика в бэкенде уже верна.
```bash
flutter build web
```
⚠️ Перед деплоем web проверить сборку (историческая мина — дубликаты ключей в `lang.dart`; сейчас чисто).

---

## 6. Смоук-тест (после выката)
1. Создать заказ официантом → сумма считается из меню (пробить позицию с «изменённой» ценой в обход — цена всё равно из БД).
2. Оплатить (наличные/карта/долг/смешанно).
3. `reopen` оплаченного заказа → проверить, что появилась строка в `order_void_log` (`SELECT * FROM order_void_log ORDER BY id DESC LIMIT 3;`).
4. Попытаться `reopen`/удалить заказ с частично погашенным долгом → должен вернуть 409 (защита).
5. Закрыть день → отчёты открываются без 500.

---

## Новые функции этой сессии (payroll + analytics + offline)
Дополнительно к P0-фиксам, в рабочем дереве добавлены:
- **Аналитика по блюдам (drill-down):** `reportController.getDishDetail` + `GET /reports/dish/:id`; в `analytics_page.dart` строки блюд кликабельны → страница `DishDetailPage` (KPI + дневная/часовая динамика).
- **Сдельная зарплата ("за штуку"):** новый `salary_type='piece'`, таблица `salary_piece_rates`, эндпоинты `GET/POST /reports/piece-rates`; в админке (редактирование сотрудника) кнопка «Дона ставкалар» — выбор блюд и ставки за штуку.
- **Прогрессивный % официанта:** колонки `users.salary_tier_threshold/salary_tier_value`; в форме сотрудника (тип «Савдодан фоиз») поля «кунлик чегара» + «ошган фоиз». Расчёт в `getPayroll` — по дням.

Файлы дополнительно к списку выше: `reportController.js`, `reportRoutes.js`, `userController.js`, `analytics_page.dart`, `admin_screen.dart`, `constants.dart`, `api_service.dart`, `main.dart`, `login_screen.dart`, и миграции `migration_salary_piece_and_tier.sql`, `migration_hot_indexes.sql`, `migration_repo_schema_backfill.sql`. Все миграции применятся авто-раннером при старте (идемпотентны).

⚠️ **`flutter build web` теперь ОБЯЗАТЕЛЕН** (новый UI: drill-down, сдельная, прогрессивный %, ⚙ выбор сервера). Перед сборкой — проверить, что `flutter analyze lib/` даёт 0 ошибок (сейчас 0).

Смоук-тест новых функций: (1) Аналитика → тапнуть блюдо → открылась детальная страница; (2) сотрудник тип «piece» → задать ставки → продать это блюдо → payroll показывает базу; (3) официант «percent» + порог/7% → payroll считает по дням.

## Откат
Если что-то пошло не так — восстановить из бэкапа шага 0:
```bash
pg_restore -U postgres -h 127.0.0.1 -d sultan_db -c sultan_backup_2026-07-09.dump
```
и вернуть прежние файлы бэкенда (git). Миграции идемпотентны — повторный старт не навредит.
