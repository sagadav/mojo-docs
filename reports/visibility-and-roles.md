# Репорты: видимость и роли (кто что видит)

Документ про то, **почему сотрудник видит/не видит репорт и его блоки**, и где это чинить.
Связанный быстрый старт: `_docs/school/reports-start.md`.

## Главная идея: ДВА независимых слоя видимости

Путаница почти всегда в том, что «видеть репорт» и «видеть блок внутри репорта» — это
**разные механизмы**, на разных таблицах:

| Слой | Вопрос | Источник | Семантика времени |
|------|--------|----------|-------------------|
| 1. Видимость **репорта** в списке сотрудника | появится ли репорт у учителя в «Мои репорты» | `report_targets` (плоская: `report_id`, `staff_id`) | **статическая**, правится вручную |
| 2. Видимость **блока** внутри репорта | покажется ли учителю блок tutor/teacher/psy для конкретного ученика | `get_staff_student()` по `class_tutors` / `group_teachers` | **динамическая** |

Из-за разной природы слоёв они рассинхронятся. Типовые симптомы:
- «старый классрук всё ещё видит репорт» → слой 1 (`report_targets` не сняли);
- «новый классрук не видит репорт» → слой 1 (`report_targets` не добавили);
- «учителю показан блок классрука в чужом классе» → слой 2 (`get_staff_student`).

## Слой 1 — видимость репорта (`report_targets`)

Гейт: `Report_list::get_report_staff()` (`app/Models/reports/Report_list.php`):
```sql
id_list IN (SELECT report_id FROM report_targets WHERE staff_id = ? AND deleted_at IS NULL)
```
Если сотрудника нет в `report_targets` данного репорта — он его **вообще не видит**, и любые
правки слоя 2 для него не сработают (он не дойдёт до экрана).

Особенности:
- таблица **плоская** — только `report_id` + `staff_id`, **без роли и без класса**. Нельзя
  отличить «добавлен как классрук» от «добавлен как предметник». Поэтому **нельзя просто снять**
  выбывшего классрука, если он ещё и предметник — убьёшь и доступ предметника.
- наполняется/снимается **вручную**: вкладка репорта «Assignment to staff» →
  `ReportAjaxController` (тоггл: `UPDATE ... deleted_at` / `INSERT INTO report_targets`).
- автосинхронизации со сменой `class_tutors` **нет**. Сменили классрука — `report_targets`
  не обновляется сам: старый остаётся, новый не появляется.
- список «кого можно отметить» на вкладке считается динамически (`ReportController::report_stat`):
  текущие `group_teachers` + носители ролей `classroom_teacher/psy/logoped/head`.

## Слой 2 — видимость блоков (`get_staff_student`)

Экран заполнения: `StaffController` → `actions/StaffReports.php`.
- какие ученики попадают сотруднику: `Student::get_staff_student_report()` (`Student.php`);
- кем сотрудник приходится ученику (роль → какие блоки показать):
  `Staff::get_staff_student($student, $staff, $report_start)` (`Staff.php`).

`get_staff_student` возвращает роли (`teacher`, `tutor`, `psy`, `logoped`, `head`) объединением:
- **teacher** — через `group_teachers` / `group_students` (предметные группы);
- **tutor** — через `class_tutors` / `class_students` (классное руководство).

Блок показывается по флагам блока (`report_blocks`): `block_teacher`, `block_tutor`,
`block_psy`, `block_head`… (это и есть галки «Assignment to staff» в редакторе блока:
«For a teacher» = teacher, **«For a tutor» = tutor**, и т.д.).

> Не доверяй названию блока. «Homeroom teacher's comment» — это просто заголовок; реальная
> роль определяется флагом блока (`block_tutor`/`block_teacher`), а не текстом.

## Баг (тикет annual-report-stale-homeroom): классрук видит блок в чужом классе

Симптом: учитель, переставший быть классруком класса, всё ещё видит блок «Homeroom teacher's
comment» для учеников этого класса.

Причина — tutor-ветка `Staff::get_staff_student()`:
```sql
-- БЫЛО (баг):
SELECT class_id FROM class_tutors ct
WHERE staff_id = ?
  AND (ct.deleted_at >= ? OR ct.deleted_at IS NULL)   -- ? = list_start
-- нет проверки class_finish; deleted_at сверяется со стартом репорта
```
Учитель считался классруком, если тьюторство удалили **не раньше старта репорта** —
и `class_finish` не проверялся вообще. Выбывший классрук «залипал».

Эталон корректной выборки текущего тьютора уже был рядом — `Student.php`
(`get_staff_student_report`, tutor-ветка): `deleted_at IS NULL AND (class_finish IS NULL OR class_finish > NOW())`.

Фикс — привести tutor-ветку `get_staff_student` к той же семантике текущего классрука:
```sql
-- СТАЛО:
SELECT class_id FROM class_tutors ct
WHERE staff_id = ?
  AND ct.deleted_at IS NULL
  AND (ct.class_finish IS NULL OR ct.class_finish > NOW())
```
Почему NOW(), а не якорь на `list_start`: новый классрук может быть назначен **после** старта
репорта и обязан писать. NOW() корректно обрабатывает оба конца (выбывших скрывает, новых
показывает) и совпадает со слоем выборки учеников (`Student.php`).

Альтернатива «overlap [list_start, list_finish]» (кто был классруком в период репорта) —
точнее для **закрытых** репортов, но требует прокинуть `list_finish` и согласовать со списком
учеников; это смена модели во всём модуле, а не точечный фикс. Зафиксировано как возможное
развитие, не сделано.

Важно: фикс закрывает **только слой 2** (старый не видит блок). Кейс «новый классрук не в
`report_targets` и потому не видит репорт» — это **слой 1**, отдельно (см. ниже).

## SQL-чеклист по видимости репорта (read-only)

Подставить `:report` и `:staff`. Проверено на схеме clarity.

**1. Кто назначен на репорт и кто из них сейчас реально классрук:**
```sql
SELECT rt.staff_id,
       CONCAT_WS(' ', s.staff_surname, s.staff_name) AS staff,
       (SELECT GROUP_CONCAT(cl.class_name SEPARATOR ', ')
          FROM class_tutors ct JOIN class_lists cl ON cl.id_class=ct.class_id
         WHERE ct.staff_id=rt.staff_id AND ct.deleted_at IS NULL
           AND (ct.class_finish IS NULL OR ct.class_finish > NOW())) AS current_tutor_classes
FROM report_targets rt LEFT JOIN staff s ON s.id_staff=rt.staff_id
WHERE rt.report_id=:report AND rt.deleted_at IS NULL
ORDER BY current_tutor_classes IS NULL DESC, staff;
```

**2. История классруков по классам репорта (видно подмену старый→новый + кто в targets):**
```sql
SELECT cl.class_name, ct.staff_id,
       CONCAT_WS(' ', s.staff_surname, s.staff_name) AS tutor,
       ct.created_at AS since, ct.class_finish, ct.deleted_at,
       CASE WHEN ct.deleted_at IS NULL AND (ct.class_finish IS NULL OR ct.class_finish>NOW())
            THEN 'current' ELSE 'ended' END AS status,
       CASE WHEN rt.staff_id IS NOT NULL THEN 'YES' ELSE 'no' END AS in_targets
FROM class_tutors ct
JOIN class_lists cl ON cl.id_class=ct.class_id
LEFT JOIN staff s ON s.id_staff=ct.staff_id
LEFT JOIN report_targets rt ON rt.staff_id=ct.staff_id AND rt.report_id=:report AND rt.deleted_at IS NULL
WHERE ct.class_id IN (
    SELECT DISTINCT ct2.class_id FROM class_tutors ct2
    JOIN report_targets rt2 ON rt2.staff_id=ct2.staff_id
    WHERE rt2.report_id=:report AND rt2.deleted_at IS NULL)
ORDER BY cl.class_name, status, ct.class_finish;
```

**3. Текущий классрук класса, которого НЕТ в targets (новый не видит репорт):**
```sql
SELECT DISTINCT cl.class_name, ct.staff_id,
       CONCAT_WS(' ', s.staff_surname, s.staff_name) AS current_tutor
FROM class_tutors ct
JOIN class_lists cl ON cl.id_class=ct.class_id
JOIN staff s ON s.id_staff=ct.staff_id
WHERE ct.deleted_at IS NULL AND (ct.class_finish IS NULL OR ct.class_finish > NOW())
  AND ct.class_id IN (
      SELECT DISTINCT ct2.class_id FROM class_tutors ct2
      JOIN report_targets rt2 ON rt2.staff_id=ct2.staff_id
      WHERE rt2.report_id=:report AND rt2.deleted_at IS NULL)
  AND ct.staff_id NOT IN (
      SELECT staff_id FROM report_targets WHERE report_id=:report AND deleted_at IS NULL);
```

**4. Преподаёт ли сотрудник (чтобы понять, безопасно ли снимать из targets):**
```sql
SELECT gt.staff_id, COUNT(*) AS active_groups
FROM group_teachers gt
WHERE gt.staff_id IN (:staff) AND gt.deleted_at IS NULL
  AND (gt.group_finish IS NULL OR gt.group_finish > NOW())
GROUP BY gt.staff_id;
```

## Памятка: какой слой чинить

- «видит/не видит **репорт** целиком» → слой 1, `report_targets` (вкладка Assignment to staff).
- «видит/не видит **блок** (классрука/предметника) для ученика» → слой 2, `get_staff_student`
  + флаги блока в `report_blocks`.
- `report_targets` нельзя чистить «по классруку» вслепую — сотрудник может быть ещё и
  предметником (таблица без роли). Сначала запрос №4.
- `class_tutors` не содержит type → код не различает «классный руководитель» и «наставник»;
  если задача про эту разницу — это архитектурный вопрос, не баг выборки.
