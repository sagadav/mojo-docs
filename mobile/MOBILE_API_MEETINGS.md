# Мобильное API — Планировщик встреч (Meetings)

## Где лежит

| Что | Путь |
|---|---|
| Route-файл | `school/routes/mobile/meeting.php` |
| Подключение | `school/routes/api.php:121` → `Route::group([], __DIR__ . '/mobile/meeting.php');` |
| Контроллер | `school/app/Http/Controllers/Api/mobile/MobileMeeting.php` |
| FormRequest'ы | `school/app/Http/Requests/Api/Mobile/Meeting/` |
| Сервисы | `school/app/Services/Toolbox/Meetings/` (+ `Services/Helpers/Meetings/MeetingAccessHelper`) |
| Ответы | `App\Http\Responses\ApiSuccessResponse` / `ApiErrorResponse` |

> Важно: мобильный API встреч **не** в общем `Api/MobileController`, а в отдельном контроллере `Api\mobile\MobileMeeting`.

## Эндпоинты

Middleware: `auth:sanctum`. Модуль доступа: menu=`toolbox`, module=`meetings`.

| Метод | URI | Контроллер-метод | Кто |
|---|---|---|---|
| GET | `meeting_list` | `meeting_list` | staff |
| GET | `meeting_one/{meeting_id}` | `meeting_one` | staff |
| POST | `meeting_create` | `meeting_create` | staff |
| POST | `meeting_update/{meeting_id}` | `meeting_update` | staff |
| DELETE | `meeting_delete/{meeting_id}` | `meeting_delete` | staff |
| POST | `meeting_invite_answer` | `meeting_invite_answer` | student / parent / staff |

`{meeting_id}` — `->whereNumber(...)`.

## Соглашения по параметрам (из docblock контроллера)

- query/body — snake_case `{entity}_id`: `meeting_id`, `student_id`, `staff_id`, `candidate_id`, `meeting_user_id`, `building_id`…
- курсор пагинации списка — `last_meeting_id`.
- create/update: день слота — `meeting_start` (совместимость `meeting_date` см. `AbstractMobileMeetingBodyRequest`).
- сущности аудитории: в списке — `meeting_entity_ids`, в карточке — `meeting_entity_id`.

## meeting_list — параметры запроса

`building_id`, `staff_creator_id`, `start_date`, `finish_date`, `last_meeting_id` (курсор), `limit` (по умолч. 50).

Ответ:
```json
{
  "meetings": [
    {
      "meeting_id": 0,
      "meeting_building": 0,
      "meeting_title": "",
      "meeting_start": "", "meeting_finish": "",
      "meeting_comment": "",
      "meeting_time_start": "", "meeting_time_finish": "",
      "meeting_numbers": 0,
      "meeting_staff": null,
      "staff_display": "",
      "meeting_accepted_count": 0,
      "meeting_capacity": 0,
      "targets": [],
      "allow_edit": false
    }
  ],
  "pagination": { "limit": 50, "has_more": false, "last_meeting_id": null }
}
```

## meeting_one/{meeting_id}

Доп. поля сверх списка: `entities[]` (`meeting_entity_id`, `type`, `entity_id`), `targets` (флаги).
Проверки: `findMeetingWithStaff` → `isMeetingRowVisibleToUser` → 404/403.

## meeting_invite_answer

Body: `meeting_id`, `is_accepted` (bool), опц. `candidate_id`, `staff_id`, `student_id`.
Ветки:
- `candidate_id > 0` → только **parent** → `MeetingCandidateInviteAnswerService::handle()`.
- иначе → `MeetingInviteAnswerService::handle(student, meeting, accept, staff?)`; `staff_id > 0` допустим только для staff.

День слота берётся из `meeting_lists` в сервисах (`MeetingAccessHelper::inviteSlotCalendarDay`), **в теле не принимается**.

Коды ошибок (→ `meetingInviteAnswerError`): `invalid`, `auth`, `forbidden`, `invalid_meeting`, `invalid_date`, `no_student_user`/`no_staff_user`, `already_rejected`, `meeting_full`.

## Сервисный слой (используется контроллером)

- `MeetingService` — чтение списка/карточки: `getMobileListPage`, `findMeetingWithStaff`, `isMeetingRowVisibleToUser`, `getAcceptedInviteCountsByMeetingIds`, `getTargetsMapByMeetingIds`, `getTargetFlagsForMeeting`, `getActiveEntitiesForMeeting`, `findActiveMeetingRow`.
- `MeetingPersistService` — `create` / `update` / `delete`.
- `MeetingInviteAnswerService`, `MeetingCandidateInviteAnswerService` — ответы на приглашения.
- `MeetingAccessHelper` — `currentStaffReference`, `canEditMeetingRow`.

## Доступ

Везде: `auth()->user()->user_group === 'staff'` (кроме invite_answer — ещё student/parent),
плюс `UserControler::get_module_access('toolbox','meetings')` (`view`/`edit`/`building`/`building_staff`).
Здание защищается `ToolsController::protect_building(...)`.

## Интеграция в `mobile_shedule`

Карточки планировщика уже подмешиваются прямо в ответ мобильного расписания:

- route: `GET mobile_shedule`
- контроллер: `school/app/Http/Controllers/Api/mobile/MobileSchedule.php`
- поле ответа: `data.meeting_schedule_cards`

Источник данных по ролям:

- `staff` → `MeetingStaffPlannerScheduleService`
- `student` → `MeetingStudentInviteScheduleService`
- `parent` → объединение:
  - student-карточек в `viewOnly`
  - parent-карточек с возможностью ответа

Структура `meeting_schedule_cards`:

```json
{
  "meeting_schedule_cards": {
    "1": [
      {
        "id_meeting": 123,
        "meeting_date": "2026-06-01",
        "staff_id": 45,
        "meeting_title": "Индивидуальная встреча",
        "meeting_comment": "Обсуждение прогресса",
        "time_range": "14:00–14:20",
        "start_minutes": 840,
        "finish_minutes": 860,
        "meeting_initiator": "Иванова И.И.",
        "meeting_participants": ["Петров П.П. (student)"],
        "meeting_target_kind": "student",
        "pending_blink": true,
        "invite_response_status": "pending",
        "invite_show_accept": true,
        "invite_show_reject": true,
        "invite_accept_disabled": false,
        "invite_readonly": false
      }
    ]
  }
}
```

Поля ответа для клиента:

- `meeting_schedule_cards[day]` — массив карточек встреч по номеру дня недели.
- `id_meeting` — идентификатор встречи для `meeting_invite_answer`.
- `meeting_date` — календарная дата карточки.
- `time_range`, `start_minutes`, `finish_minutes` — данные для позиционирования карточки в сетке.
- `meeting_initiator`, `meeting_participants` — подписи для UI.
- `meeting_target_kind` — `student` или `parent`.
- `invite_response_status` — `pending` / `accepted` / `rejected`.
- `invite_show_accept` — показывать кнопку «Принять».
- `invite_show_reject` — показывать кнопку «Отклонить».
- `invite_accept_disabled` — кнопка «Принять» должна быть disabled (например, нет мест).
- `invite_readonly` — только просмотр, без действий.
- `pending_blink` — можно подсветить карточку как ожидающую ответа.

Поведение по ролям:

- `staff`: видит карточки своих встреч без `accept/reject`.
- `student`: видит приглашения и может вызывать `POST meeting_invite_answer` с `meeting_id`, `student_id`, `is_accepted`.
- `parent`: 
  - student-карточки ребёнка приходят как `invite_readonly = true`;
  - parent-карточки родителя приходят с `accept/reject` и отвечаются через `POST meeting_invite_answer` с `meeting_id`, `is_accepted`.

Примеры вызова `meeting_invite_answer` из расписания:

```json
{
  "meeting_id": 123,
  "student_id": 77,
  "is_accepted": true
}
```

```json
{
  "meeting_id": 456,
  "is_accepted": false
}
```
