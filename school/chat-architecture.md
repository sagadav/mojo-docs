# Chat Module Architecture

## Таблицы

| Таблица | Назначение |
|---|---|
| `message_canals` | Каналы/чаты. Поля: `canal_type`, `canal_reference`, `canal_year`, `canal_hidden`, `canal_readonly`, `canal_deleted` |
| `message_canal_members` | Участники канала. `deleted_at` — мягкое удаление. `is_manual=1` — добавлен вручную, не трогается синхронизацией |
| `message_canal_permissions` | Справочник прав. Сейчас одно право: `send_message` (id=1) |
| `message_canal_user_permissions` | Выданные права. Нет soft delete — revoke = физическое удаление строки |
| `message_lists` | Сообщения |

## Типы каналов (`canal_type`)

| Тип | Создаётся | Участники |
|---|---|---|
| `group` | синхронизацией / вручную | учителя + ученики группы |
| `class` | синхронизацией / вручную | тьютор + ученики класса |
| `parent` | синхронизацией / вручную | тьютор + родители учеников класса |
| `flex` | администратором вручную | произвольный список |
| `individual` | при первом сообщении | двое участников |

## Права (`send_message`)

`individual`-чаты не проверяют права — всегда разрешено (`user_can()` возвращает `true`).

Для остальных типов: право есть → запись в `message_canal_user_permissions`. Право отозвано → запись **удалена** (не soft delete). Это ключевой факт: синхронизация видит отсутствие записи и может её восстановить.

## `canal_readonly`

Флаг (bool, default 0) на канале. Когда `1` — синхронизация и добавление участников не выдают `send_message` non-staff пользователям. Staff (сотрудники) получают право всегда.

Устанавливается через `canal_settings` модалку (`send_message=0` → `canal_readonly=1`).

## Код: все места выдачи `send_message`

```
grep -rn "message_canal_user_permissions" app/ --include="*.php" | grep -i "insert\|firstOrCreate\|bulkGrant\|grantPermission"
```

| Место | Когда вызывается |
|---|---|
| `ChatService::syncChannelsBatch` | ночная синхронизация `mojo:chat:sync` |
| `ChatService::firstOrCreateGroupChat` | открытие страницы чата (`CommunicationController`), ручное создание чата |
| `ChatRepository::bulkGrantPermissions` | вызывается из `syncChannelsBatch` |
| `Message_canal::grantPermission(s)` | вызывается из `firstOrCreateGroupChat`, `canal_settings` |
| `start/CommunicationAjaxController::flex_canal_user_update` | обновление участников flex-чата (start модуль) |
| `toolbox/CommunicationAjaxController::canal_user_update` | обновление участников flex-чата (toolbox модуль) |
| `toolbox/CommunicationAjaxController::canal_join_self` | администратор вступает в чат вручную — **не блокируется `canal_readonly`** |

> ⚠️ `canal_join_self` не проверяет `canal_readonly` — администратор всегда получает право. Это намеренно.

## Синхронизация

`mojo:sync` (ночной cron) → `mojo:chat:sync` → `ChatService::syncChannelsBatch`.

Обрабатывает только `group`, `class`, `parent`. Flex и individual не трогает.

## Глобальные настройки чата (`directory_properties`, group=`chat`)

| Код | Значение |
|---|---|
| `chat_parent_individual` | 1 = родители не получают `send_message` в групповых чатах |
| `chat_parent_write_teachers` | родители могут писать учителям |
| `chat_parent_contact_person` | родитель может писать назначенному сотруднику |
| `chat_staff_student` | учитель и ученик могут общаться напрямую |

Кэшируются в `Cache::get('global_properties_arr')['chat']`.
