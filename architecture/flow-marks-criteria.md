# Поток: Критериальные оценки

> Глубокая карта одного из трёх типов оценок (см. [flow-marks.md](architecture/flow-marks.md)).
> Привязана к реальному коду через методы, роуты и модели.

## TLDR

- **Что это:** оценка ученика по отдельному критерию (IB: `A/B/C/D`, шкала обычно 0..3). Таблица `mark_criteria`, модель `Mark_criterion`.
- **Ключевая развилка — `work_id`:**
  - `work_id = 0` — «прямая» критериальная оценка (выставлена руками в журнале/ученику).
  - `work_id > 0` — оценка за конкретную **форму работы** (`lesson_works.id_work`).
  - Оценка с `work_id > 0` **затмевает** прямую (`Mark_criterion::actualMarkCondition()`) — при чтении берётся она.
- **3 пути записи** (всё через AJAX-роутер `AcademAjaxController`, право `['academ','markbook']`/`['staff','markbook']`):
  1. `AcademAjaxController::save_criterion_lesson()` — пакет на всю группу за урок
  2. `AcademAjaxController::save_criterion_student()` — одна оценка одному ученику
  3. `AcademAjaxController::save_criterion_work()` — критерии за форму работы **+ автоматически считает текущую оценку** за работу через `Mark::add_mark()`
- **Удаление:** `mark = -1` → soft-delete (`deleted_at`). Физически не трётся.
- **Средний балл нигде не хранится** — считается на лету (`round(AVG(value))`).
- **Сайд-эффект-ловушка:** только `save_criterion_work` косвенно шлёт **уведомление** родителю/ученику (через `Mark::add_mark`, т.к. рождает текущую оценку). `_lesson`/`_student` — молча.
- **Главный риск:** `SELECT-then-INSERT` без транзакции/уникального индекса → дубли активных строк при гонке; плюс права проверяются только слаг-картой (потенциальный IDOR по `student_id`/`work_id`).

---

## Модель данных

Таблица **`mark_criteria`**, две модели поверх:
- `app/Models/academ/Mark_criterion.php` — запись + чтение для журнала/аналитики
- `app/Models/marks/CriteriaMarksModel.php` — только чтение для публичного API v1 (`getByFilters`)

Колонки: `id` (PK), `period_id`, `criteria_id`, `subject_id`, `student_id`, `value`, `staff_id`, `work_id`, `created_at`, `deleted_at`.
Авто-таймстемпы Eloquent отключены (`getCreatedAtColumn/getUpdatedAtColumn → null`), `created_at` пишется вручную.

**Семантика `work_id`** (важнейшая деталь домена):
- `0` — прямая оценка по критерию (period + criteria + subject + student уникальны логически)
- `>0` — за форму работы урока

**`Mark_criterion::actualMarkCondition()`** — общий SQL-фрагмент: «бери строку, если у неё `work_id > 0`, ИЛИ если для той же связки (period/criteria/subject/student) вообще нет активной строки с `work_id > 0`». Т.е. оценка за работу приоритетнее прямой. Используется во всех чтениях для журнала.

## Запись (3 пути)

### 1. `AcademAjaxController::save_criterion_lesson()` — пакет на группу за урок
- Вход: `items[student_id][criteria_id] = mark`
- `act_period`, `act_subject` — **из сессии** (не из запроса)
- Цикл по ученикам/критериям → `CriteriaMarksService::save_criteria_mark()` (всегда `work_id = 0`)
- Нет валидации диапазона оценки

### 2. `AcademAjaxController::save_criterion_student()` — одна оценка ученику
- Вход: `criteria_id`, `student_id`, `mark`; `act_period`/`act_subject` из сессии
- **Единственный путь с валидацией:** `mark` в `[-1, mark_max]` (`mark_max` из сессии, дефолт `3`); иначе `invalid_value`
- → `CriteriaMarksService::save_criteria_mark()` (`work_id = 0`)

### 3. `AcademAjaxController::save_criterion_work()` — критерии за форму работы + расчёт текущей
- Вход: `student_id`, `work_id`, `criteria_mark[criteria_id] = mark`
- Параметры урока/группы тянутся по `work_id` из `lesson_works + lessons + group_list` (`work_flex`, `lesson_period`, `id_group`, `group_assesment`, `group_subject`)
- Для каждого критерия:
  - была активная за эту работу и `value` изменился → старую `deleted_at`, новую `INSERT` (`work_id` = work)
  - была и `value` тот же → `UPDATE value, subject_id` на месте (**не** history — расходится с остальными путями внутри `save_criterion_work()`)
  - новой `INSERT`, если `mark >= 0 && mark != last_value`
- **Расчёт текущей оценки за работу:** `mark_work = round(sum / num / criteria_mark_max * current_max, 0)`; пустые критерии учитываются по `property_markbook_criteria_zero()`
- Затем `Mark::add_mark(...)` пишет в `marks` → **триггерит уведомление** (см. ниже)

### `CriteriaMarksService::save_criteria_mark()` (для `work_id = 0`)
- `mark == -1` → `UPDATE ... SET deleted_at` (удаление)
- иначе: `SELECT` активной → нет: `INSERT`; есть и `value` изменился: soft-delete старой + `INSERT`; `value` тот же: ничего

## Удаление

- **Ручное:** `mark = -1` в `save_criteria_mark` → `deleted_at`
- **Отвязка критериев от урока:** `AcademAjaxController::deleteMarksForDetachedLessonCriteria()` — при изменении набора критериев урока (`lesson_thema_criteria`) метит `deleted_at` у `mark_criteria` через `JOIN lesson_works`, где `criteria_id NOT IN (новый список)`. **Только для `work_id > 0`** (JOIN по `lw.id_work = mc.work_id`); прямые (`work_id = 0`) не чистятся.

## Чтение / показ

| Кому | Точка входа | Что считает |
|------|-------------|-------------|
| Учитель (журнал, средняя по группе) | `Mark_criterion::get_criteria_mark()` | `round(AVG(value),0)` + `actualMarkCondition` |
| Ученик (детально по периодам) | `Mark_criterion::get_criteria_student()` | по периодам, комментарии, `avg` |
| Аналитика | `CriteriaController` (`web_analytics.php`): `criteria_mark`, `criteria_work`, `criteria_blum`, `criteria_mastering`, `criteria_coverage`, `criteria_svod` | сводки `get_criteria_stat / _student / _total` |
| API v1 (внешние/мобайл) | `GET /api/v1/marks/criteria` → `MarksController::criteria` → `CriteriaMarksService::getByFilters` → `CriteriaMarksModel` | JSON или CSV |
| Мобайл | `MobileMarkbook` (`mobile_markbook`), `mobile soft_skills/criteria` | — |

## Средний балл / пересчёт

- **Не материализуется** — считается на лету:
  - по группе: `round(AVG(value), 0)` (`get_criteria_mark`)
  - по периоду ученика: `round(sum/number, 1)` + общий `avg` (`get_criteria_student`)
- Округление до целого vs до `0.1` рулит `ToolsController::property_criteria_same_mark()` в расчётах `Mark_criterion::get_criteria_stat_student()` / `get_criteria_stat_total()`
- `mark_min` / `mark_max` — из сессии/настроек (`mark_max` дефолт `3`)

## Справочники и состояние

- `Cache::get('assessment_arr')` — системы оценивания: `current_max`, `current_mark_value`, `range`. Гард `isset($assessments[$group_assesment])` стоит на путях записи за работу.
- Сессия: `act_period`, `act_subject`, `current_min`/`current_max`, `current_mark_value`, `mark_max`, `act_group_program`
- Спец-значение `value = -1` = удалить / нет оценки

## Сайд-эффекты

- **Уведомление** родителю/ученику — **только** через `AcademAjaxController::save_criterion_work()` → `Mark::add_mark()`, потому что он создаёт текущую оценку в `marks`. Прямые критериальные (`_lesson`/`_student`) уведомлений **не шлют**.
- Кэш `assessment_arr` читается, при выставлении не инвалидируется (критерии в кэше не лежат).
- Каскад от урока: смена набора критериев урока → `deleteMarksForDetachedLessonCriteria` мягко гасит лишние оценки за работу.

## Риски

- **Двойной учёт `work_id` 0 vs >0** — в БД лежат обе строки; `actualMarkCondition` спасает только чтения, которые его применяют. Любой агрегат в обход условия задвоит.
- **Гонки** — `SELECT`→`INSERT` в `save_criteria_mark` и в `save_criterion_work` без транзакции/уникального индекса → два параллельных сохранения дают две активные строки.
- **Несогласованный паттерн в `AcademAjaxController::save_criterion_work()`** — при неизменном `value` делается `UPDATE` на месте, а не history-INSERT как везде. Ломает «однородную» историю изменений.
- **Валидация только в одном пути** — диапазон `mark` проверяется лишь в `save_criterion_student`; `_lesson` и `_work` принимают что угодно.
- **Молчаливый skip** — нет системы оценивания (`assessment_arr[$group_assesment]` отсутствует) → критерии за работу не пишутся и оценка за работу не ставится, без ошибки пользователю.
- **Права / IDOR** — проверяется только слаг-карта `markbook`. Нет проверки, что учитель ведёт эту группу/предмет → можно подставить чужой `student_id`/`work_id`/`criteria_id`. Проверь перед доверием.
- **Чистка отвязанных** — `deleteMarksForDetachedLessonCriteria` обрабатывает только `work_id > 0`; прямые критериальные при отвязке остаются.
- **`AcademAjaxController::previous_criterion_mark()`** — `$period_str` инициализируется `0` и конкатенируется → ведущий `0, ` в `IN(...)`. Безобидно, но грязно.
