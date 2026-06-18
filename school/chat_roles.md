# Роли в чате: кто кому может писать

## Роль `chat` (`role_sys='chat'`, `module_id=225`)

Специальная роль для **сотрудников**. Управляется флагами `role_modules.is_edit` и `role_modules.is_building`.

| Флаг | Доступ к родителям |
|------|--------------------|
| `is_edit=1` | Все родители школы (без ограничений) |
| `is_edit=0, is_building=1` | Только родители, чьи дети в том же здании |
| `is_edit=0, is_building=0` | Никто (роль есть, но не даёт доступа) |

## Без роли chat (обычный учитель)

Зависит от настройки `chat_parent_write_teachers`:

- **OFF** → родители вообще не видны в поиске, писать нельзя
- **ON** → видны и доступны только родители **своих учеников** (группы + тьюторский класс)

## Сводная таблица

| Кто | Кому может писать | Условие |
|-----|-------------------|---------|
| Сотрудник с `chat` (is_edit=1) | Любой родитель школы | `chat_parent_contact_person=on` |
| Сотрудник с `chat` (is_building=1) | Родители детей из того же здания | `chat_parent_contact_person=on` |
| Обычный учитель | Родители своих учеников | `chat_parent_write_teachers=on` |
| Обычный учитель | Никто из родителей | `chat_parent_write_teachers=off` |
| Родитель | Учителя своих детей | `chat_parent_write_teachers=on` |
| Родитель | Сотрудники с ролью `chat` | `chat_parent_contact_person=on` |
| Ученик | Учителя своих групп + тьютор | `chat_staff_student=on` |
| Ученик | Сотрудники с ролью `chat` | `chat_parent_contact_person=on` |

## Ключевые файлы

- `app/Models/User.php:536` — `getChatRoleAccess()`, `chatRoleAllowsParent()`
- `app/Repositories/Communication/SearchRepository.php:255` — `searchUsersForStaff()` (логика фильтрации поиска)
- `app/Http/Controllers/start/CommunicationModalController.php:244` — `available_contacts()` (список собеседников в UI)
- `app/Http/Controllers/ToolsController.php:2393` — `property_chat_parent_contact_person()` и др. настройки
