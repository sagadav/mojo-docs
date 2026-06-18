# Поток: Оценки

> Карта домена оценок в проекте `school`. Привязана к реальному коду через методы, роуты и модели.
> Главное отличие от «обычной» CRUD-модели: **три разных типа оценок в трёх таблицах**, запись через
> AJAX-роутер по слагам, а не REST. Удаление — **soft-delete + новый INSERT**, не UPDATE строки.

## Три типа оценок

| Тип | Таблица | Модель | Soft-delete колонка | Запись |
|-----|---------|--------|---------------------|--------|
| Текущая (за работу на уроке) | `marks` | `Mark` | `mark_deleted` | `Mark::add_mark()` |
| Итоговая (за период/год) | `mark_final` | `Mark_final` | `final_deleted` | прямой `INSERT` в `mark_change()` |
| Критериальная (A/B/C/D, IB) | `mark_criteria` | `Mark_criterion` | `deleted_at` | `save_criterion_*` |

## Сценарии

- **создать / изменить** — старую активную оценку помечают удалённой, вставляют новую строку (history-style)
- **удалить** — `mark != ''` не вставляется; старая остаётся помеченной `*_deleted`
- **показать учителю** — `GET /academ/markbook`
- **показать ученику / родителю** — мобайл (`MobileMarkbook`, `MobileDiary`) и API v1
- **пересчитать средний балл** — `round(AVG(value))` на лету при чтении (`Mark_criterion::get_criteria_mark`), не хранится
- **авто-итоговая (IB/DP)** — когда проставлены все 4 критерия, считается годовая `Y` по сумме (`mark_change`)

## Entry points

Запись (POST, AJAX-роутер `AcademAjaxController::router`, право `['academ','markbook']` или `['staff','markbook']`):

- `POST /academ/ajax/mark_change` — текущая **и** итоговая (ветка по `id_lesson == 0`) — `AcademAjaxController::mark_change()`
- `POST /academ/ajax/save_criterion_lesson` — критериальная за урок — `AcademAjaxController::save_criterion_lesson()`
- `POST /academ/ajax/save_criterion_work` — за форму работы — `AcademAjaxController::save_criterion_work()`
- `POST /academ/ajax/save_criterion_student` — отдельному ученику — `AcademAjaxController::save_criterion_student()`
- `POST /academ/ajax/save_comment_current|save_comment_final` — комментарии к оценке — `AcademAjaxController::save_comment_current()`, `AcademAjaxController::save_comment_final()`
- `POST /academ/ajax/markbook_comment_create|update|delete` — `AcademAjaxController::markbook_comment_create()`, `markbook_comment_update()`, `markbook_comment_delete()`

Чтение:

- `GET /academ/markbook/{slag?}/{slag_value?}` → `AcademController::markbook()`; route name `markbook`
- `GET /api/v1/marks/current` → `MarksController::current()`; route name `v1.marks.current_list`
- `GET /api/v1/marks/final` → `MarksController::final()`; route name `v1.marks.final_list`
- `GET /api/v1/marks/criteria` → `MarksController::criteria()`; route name `v1.marks.criteria_list`
- `GET /api/.../mobile_markbook` → `MobileMarkbook::mobile_markbook()`

Слаг-карта доступа (важно!): `AcademAjaxController::get_method_list()`

## Главные файлы

- `app/Http/Controllers/academ/AcademAjaxController.php` — роутер + `mark_change()`, `save_criterion_*()`, `save_mark_content()`, комментарии
- `app/Models/academ/Mark.php` — текущая; `add_mark()` пишет + **шлёт уведомление** родителю/ученику
- `app/Models/academ/Mark_final.php` — итоговая; выборки + сводки, спец-значения `final_value` -1/-2/-3 = pass/fail/n_a в `get_final_mark_student_year()`
- `app/Models/academ/Mark_criterion.php` — критериальная; `actualMarkCondition()` — приоритет оценок с `work_id`; `get_criteria_mark()` = средний балл
- `app/Services/Marks/` — `MarksService`, `FinalMarksService`, `CriteriaMarksService`, `SumMarksService`
- `app/Services/NotificationService.php` + `MarkNotification` — пуш/уведомление о новой оценке
- мобайл: `Api/mobile/MobileMarkbook.php`, `Api/mobile/MobileDiary.php`
- view: `resources/views/academ/modal_lesson_assessment.blade.php`, `academ/markbook_pdf.blade.php`

## Таблицы

- **marks** — `mark_period, mark_student, mark_group, mark_work, mark_value, mark_created/mark_created_staff, mark_deleted/mark_deleted_staff`
- **mark_final** — `final_period, final_student, final_group, final_value, final_criterion, final_created/_user, final_deleted/_user` (PK `id_final`)
- **mark_criteria** — `period_id, criteria_id, subject_id, student_id, value, staff_id, work_id, created_at, deleted_at`
- **mark_comments / mark_final_comments** — комментарии к текущим/итоговым
- связанные: `lessons` (id_lesson, work_lesson), `lesson_works` (`id_work`, `work_lesson`, `work_flex`), `group_list` (`group_assesment`, `group_program`), `directory_subjects`, `directory_criteria`, `students`

## Сайд-эффекты

- **Уведомление** ученику + родителям при текущей оценке — `Mark::add_mark()`, через `NotificationService::send(... MarkNotification)`. Только для `marks`, **не** для final/criteria.
- **Авто-расчёт итоговой DP/IB** — внутри `AcademAjaxController::mark_change()`: при `property_markbook_final_ib_auto()==1` и последнем периоде, когда проставлены 4 критерия → годовая `Y` по сумме
- **Кэш** `Cache::get('assessment_arr')` — системы оценивания; читается на каждой записи/выборке. Кэш не инвалидируется при выставлении оценки (оценки в кэше не лежат).
- **Soft-delete** — старая строка помечается `*_deleted`, физически не удаляется; история сохраняется.
- **Средний балл** считается на лету (`AVG`), нигде не материализуется.

## Риски

- **Дубли активных строк (гонка)** — паттерн «UPDATE ... deleted + INSERT» без уникального индекса/транзакции. Два параллельных `mark_change` по одной ячейке → две активные записи. `actualMarkCondition` частично спасает критерии (приоритет `work_id`), но не `marks`/`mark_final`.
- **Авто-итоговая хрупкая** — условие `f_count == 4` внутри `AcademAjaxController::mark_change()` строго; дубли критериев или >4 ломают расчёт суммы.
- **Гард на кэш** — если `assessment_arr` пуст (`isset($assessments[$group_assesment])` ложно), текущая оценка молча **не пишется** внутри `AcademAjaxController::mark_change()`.
- **Права** — проверяется только слаг-карта (`academ/staff markbook`). Нет явной проверки, что учитель ведёт именно эту группу/предмет — проверь перед доверием (потенциальный IDOR по `group_id`/`td`).
- **Удалённый урок** — оценка привязана к `work_id`/`lesson`. При отвязке критериев от урока чистка идёт через `AcademAjaxController::deleteMarksForDetachedLessonCriteria()`; для текущих оценок такой чистки нет.
- **Спец-значения** — `final_value` -1/-2/-3 (pass/fail/n_a) надо отдельно обрабатывать в любых агрегатах, иначе портят суммы/средние.
