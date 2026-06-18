# Mobile Meetings Agent Onboarding

Короткий онбординг для агента по модулю встреч в `mobile/` и связанному backend в `school/`.

## Что это за модуль

Модуль покрывает два сценария:

- staff-планировщик встреч: список, создание, редактирование, удаление;
- invite/RSVP-поток в расписании: student / parent / staff получают карточки встречи и могут ответить на приглашение.

В мобильном приложении это не один экран, а несколько связанных точек:

- `mobile/src/page/MeetingsPage/index.tsx` - контейнер страницы планировщика встреч;
- `mobile/src/widgets/Meetings/ui/Meetings.tsx` - почти весь UI staff-модуля;
- `mobile/src/page/mySchool/MeetingInvitePage/MeetingInvitePage.tsx` - отдельный экран ответа на приглашение;
- `mobile/src/page/mySchool/SchedulePage/SchedulePage.tsx` и `mobile/src/widgets/Schedule/ui/Schedule.tsx` - отображение карточек встреч внутри расписания.

## Быстрая карта файлов

### Mobile

- `mobile/src/page/MeetingsPage/index.tsx`
- `mobile/src/widgets/Meetings/ui/Meetings.tsx`
- `mobile/src/page/mySchool/MeetingInvitePage/MeetingInvitePage.tsx`
- `mobile/src/shared/api/apiHooks/queries.ts`
- `mobile/src/shared/api/apiProvider/MeetingsProvider/MeetingsProvider.ts`
- `mobile/src/shared/api/methods/meetingsApi/meetingsApi.ts`
- `mobile/src/shared/api/methods/meetingsApi/routes.ts`
- `mobile/src/shared/api/methods/meetingsApi/types.ts`
- `mobile/src/shared/api/methods/mySchool/types.ts`

### Backend

- `school/routes/mobile/meeting.php`
- `school/app/Http/Controllers/Api/mobile/MobileMeeting.php`
- сервисы в `school/app/Services/Toolbox/Meetings/`

### Вспомогательная локальная документация

- `MOBILE_API_MEETINGS.md`
- `memory/project_mobile_meeting_invite_schedule.md`

## Как течёт данные

Для staff-планировщика:

`MeetingsPage -> Meetings widget -> React Query hooks -> MeetingsProvider -> meetingsApi -> mobile meeting endpoints`

Основные hooks:

- `useGetMeetingsInfinite`
- `useGetMeeting`
- `useMeetingFormOptions`
- `useCreateMeeting`
- `useUpdateMeeting`
- `useDeleteMeeting`
- `useMeetingInviteAnswer`

Провайдер `MeetingsProvider` нормализует envelope `{ success, data, message }` и всегда старается вернуть `errorMessage + result`, даже при ошибке.

## Основные экраны и режимы

### 1. Staff planner

`mobile/src/widgets/Meetings/ui/Meetings.tsx` работает в трёх режимах:

- `list`
- `detail`
- `form`

Переключение режимов и заголовок страницы управляются в `mobile/src/page/MeetingsPage/index.tsx`.

### 2. Invite answer

`mobile/src/page/mySchool/MeetingInvitePage/MeetingInvitePage.tsx` нужен для подтверждения/отклонения встреч из расписания.

### 3. Schedule integration

Карточки встреч приходят из `mobile_shedule` как `meeting_schedule_cards` и рендерятся в расписании рядом с уроками.

## API и backend

Подробности уже собраны в `MOBILE_API_MEETINGS.md`, но для старта важно помнить:

- список встреч: `GET meeting_list`
- карточка встречи: `GET meeting_one/{meeting_id}`
- создание: `POST meeting_create`
- редактирование: `POST meeting_update/{meeting_id}`
- удаление: `DELETE meeting_delete/{meeting_id}`
- ответ на приглашение: `POST meeting_invite_answer`

Кто имеет доступ:

- planner CRUD: только `staff`
- invite answer: `student` / `parent` / `staff`

Валидация и доступ сильно завязаны на backend-проверки здания и модульных прав.

## Что важно знать про UI формы

Текущая форма встречи находится в `Meetings.tsx` и уже содержит несколько UX-решений, которые лучше не ломать случайно:

- `Дата`, `Здание`, `Начало`, `Конец`, `Слоты` расположены по одному полю в строке;
- `Начало` и `Конец` поддерживают два способа ввода:
  - стрелки слева/справа с шагом `30 минут`;
  - ручной ввод по тапу на центральное значение;
- `Слоты` выбираются стрелками, минимум `1`;
- секция `Цель` переименована в `Назначение`;
- в `Назначении` не должно быть варианта `Без цели`;
- табы `Назначение` и `Тип сущностей` стилизованы через `SelectedList`, а не через локальные самодельные chip'ы;
- у `class/group` в дровере есть локальный поиск по названию;
- у `student/staff/parent` поиск серверный, через `MeetingsProvider.entitySearch(...)`.

## Текущие важные детали по данным

## Локализация mobile-ключей

Когда в `mobile/src/widgets/Meetings/ui/Meetings.tsx` добавляешь новый `t('meetings_...', {defaultValue: '...'})`, не оставляй ключ только в коде.

Для mobile-переводов встреч используй миграцию:

- `store/database/migrations/2026_06_02_000001_add_meetings_mobile_translations.php`

Что сделать:

1. Добавь новый ключ в `$keys`.
2. Добавь этот же ключ в `$translations` с `ru`, `en`, `kz`.
3. Если строка использует i18next-плейсхолдеры, сохраняй их в переводах без изменений: `{{count}}`, `{{label}}`, `{{accepted}}`.
4. Если ключ относится к backend-валидации в `school/`, проверь отдельные backend-миграции переводов, но UI-ключи `meetings_*` для mobile держи в `store`.
5. После правки проверь синтаксис миграции и точечный линт mobile-файла, если менялся UI.

Команды:

```powershell
cd C:\Users\sagadavv\Desktop\mojo\store
php -l database/migrations/2026_06_02_000001_add_meetings_mobile_translations.php

cd C:\Users\sagadavv\Desktop\mojo\mobile
npx eslint src/widgets/Meetings/ui/Meetings.tsx
```

### Имена сущностей могут быть нестабильны

Для `classes`, `groups`, иногда и других option-структур имя не всегда стоит жёстко ожидать только в `name`.

В `Meetings.tsx` уже добавлен helper `getOptionLabel(...)`, который:

- сначала смотрит `name`;
- потом `title`;
- потом `label`;
- и только потом строит fallback вроде `Класс 12`.

Если снова исчезнут названия у чипов участников или в picker, первым делом смотри это место.

### selectedEntities хранят display-name на клиенте

В `form.selectedEntities` лежит массив:

- `id`
- `name`
- `type`

Это не только ids. Если при refactor потерять `name`, UI начнёт показывать пустые чипы `Участники`.

## Поиск в picker

Поведение сейчас разделено так:

- `class/group`: фильтрация локального списка `formOptions.classes/groups`;
- `student/staff/parent`: debounce + `MeetingsProvider.entitySearch`, минимальная длина запроса `2`.

Если будешь менять picker, не своди оба сценария к одному без проверки backend-контракта.

## Что часто ломают

### 1. Нормализация времени

Время в форме хранится строкой. Для сохранения оно проходит через `padTime(...)` и затем уходит в body как `meeting_time_start` / `meeting_time_finish`.

Если менять ручной ввод времени, проверь:

- формат `HH:MM`;
- поведение на blur;
- поведение при пустом вводе;
- что стрелки продолжают работать после ручного редактирования.

### 2. Создание/редактирование и инициализация формы

`Meetings.tsx` использует `formInitRef`, чтобы не переинициализировать форму лишний раз.

Если менять lifecycle режима `form`, легко случайно получить:

- перетирание пользовательского ввода;
- повторную инициализацию после загрузки `editQuery`;
- сброс `meeting_building` при создании.

### 3. Данные meeting_form_options

Форма зависит от `useMeetingFormOptions`.

Если backend начнёт отдавать другой shape, сломаются:

- отображение здания;
- выбор классов/групп;
- selected chip names.

### 4. Разъезд с расписанием

Planner CRUD и invite-flow используют один домен встреч, но разные entry points.

После изменения API или типов обязательно проверь:

- `Meetings.tsx`
- `MeetingInvitePage.tsx`
- schedule cards в `mobile_shedule`

## Что смотреть при дебаге

Если баг в staff planner:

1. `mobile/src/widgets/Meetings/ui/Meetings.tsx`
2. `mobile/src/shared/api/apiHooks/queries.ts`
3. `mobile/src/shared/api/apiProvider/MeetingsProvider/MeetingsProvider.ts`
4. `mobile/src/shared/api/methods/meetingsApi/*`
5. `school/routes/mobile/meeting.php`
6. `school/app/Http/Controllers/Api/mobile/MobileMeeting.php`

Если баг в приглашениях из расписания:

1. `mobile/src/page/mySchool/MeetingInvitePage/MeetingInvitePage.tsx`
2. `mobile/src/widgets/Schedule/ui/Schedule.tsx`
3. `mobile/src/shared/api/methods/mySchool/types.ts`
4. backend выдача `mobile_shedule`

## Полезные команды

Точечный линт файла:

```powershell
cd C:\Users\sagadavv\Desktop\mojo\mobile
npx eslint src/widgets/Meetings/ui/Meetings.tsx
```

Быстрый поиск по модулю:

```powershell
rg -n "meeting_|Meetings|MeetingInvite|meeting_schedule_cards" mobile/src school/routes school/app
```

Поиск по локальной документации:

```powershell
rg -n "meeting" _docs MOBILE_API_MEETINGS.md memory
```

## Мини-чеклист перед завершением задачи

- planner list открывается;
- create/edit форма сохраняет данные;
- имена выбранных классов/групп/участников отображаются;
- поиск в picker работает для нужного типа сущности;
- ручной ввод времени не ломает стрелки;
- invite-flow не затронут регрессией;
- `npx eslint` по изменённому файлу проходит.
