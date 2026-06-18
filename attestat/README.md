# Модуль Аттестатов — обзор

Модуль управляет печатью аттестатов об образовании (9-й и 11-й классы).
Позволяет настраивать шаблоны, предметы, рассчитывать итоговые оценки и генерировать PDF.

---

## Документация

| Файл | Что описывает |
|------|--------------|
| [database.md](database.md) | Схема БД — все таблицы, поля, связи |
| [api.md](api.md) | HTTP-маршруты и все AJAX-эндпоинты |
| [services.md](services.md) | PHP-сервисы и их ответственность |
| [frontend.md](frontend.md) | Vue-компоненты и их связи |
| [pdf-pipeline.md](pdf-pipeline.md) | Пайплайн генерации PDF |
| [adding-field-sources.md](adding-field-sources.md) | Как добавить новый источник данных для поля шаблона |
| [templates-tab-fields.md](templates-tab-fields.md) | Структура поля и список полей во вкладке «Шаблон» |
| [../attestat-flows.md](../attestat-flows.md) | Mermaid-схемы уровней 1–11 |

---

## Ключевые файлы

```
routes/
  web_academ_attestat.php            # 10 маршрутов модуля

app/Http/Controllers/academ/
  AttestatController.php             # GET-страницы + PDF-стримы
  AttestatAjaxController.php         # POST router → 37 методов
  AttestatModalController.php        # модальные окна

app/Services/Attestat/
  AttestatPrintService.php           # генерация PDF (главный)
  AttestatMarkService.php            # расчёт и сохранение оценок
  AttestatMarkCalculator.php         # взвешенное среднее / округление
  AttestatSubjectService.php         # CRUD предметов аттестата
  AttestatTemplateService.php        # CRUD шаблонов
  AttestatTemplateAssignmentService.php  # выбор шаблона для ученика
  AttestatSettingsService.php        # глобальные настройки
  AttestatFieldDefinitionService.php # кастомные поля
  AttestatGradeDisplayFormatter.php  # формат отображения оценки
  AttestatRenderContext.php          # DTO контекст рендера
  Fields/
    FieldRegistry.php                # реестр обработчиков полей
    AttestatRenderHelpers.php        # метрики мм/pt
    Handlers/
      SurnameHandler.php
      NamePatronymicHandler.php
      BirthDateHandler.php
      IssueDateHandler.php / IssueYearHandler.php
      SchoolNameHandler.php / SchoolFullNameHandler.php
      DirectorNameHandler.php
      QrCodeHandler.php
      TitleRowHandler.php            # строки спецкурсов
      AppendixRowHandler.php         # строки приложения
      GenericTextFieldHandler.php    # кастомные текстовые поля

resources/js/modules/academ/attestat/
  app.js                             # монтирование Vue
  gradeDisplay.js                    # форматирование оценки в JS
  components/
    AttestatApp.vue                  # главный компонент / таб-навигация
    StudentList.vue                  # список учеников + превью
    AttestatPreviewModal.vue         # превью шаблона
    TemplatesTab.vue                 # вкладка шаблонов
    SettingsTab.vue                  # вкладка настроек
    BookTab.vue                      # книга регистраций
    SubjectTypeFilter.vue
    BsDropdown.vue

resources/views/academ_attestat/
  attestat_list.blade.php            # одна blade под все вкладки
  attestat_one.blade.php
  attestat_book_pdf.blade.php        # blade для PDF книги регистраций

database/migrations/
  2026_04_27_*_create_attestat_templates_table.php
  2026_04_29_*_create_attestat_marks_table.php
  2026_05_05_*_create_attestat_settings_table.php
  2026_05_06_*_create_attestat_subjects_table.php
  ...и ещё ~15 миграций

config/attestat-print/
  field_formatters.php               # правила форматирования полей
  field_sources.php                  # источники данных полей
```

---

## Архитектурный поток

```
Browser
  │
  ├── GET  /academ/attestat_list  →  AttestatController::attestat_list
  │         └── blade: attestat_list.blade.php
  │               └── Vue: AttestatApp.vue (монтируется через app.js)
  │
  ├── POST /academ/attestat_ajax/{slag}  →  AttestatAjaxController::router
  │         └── диспатч в один из 37 методов-сервисов
  │
  └── GET  /academ/attestat_print/{id}  →  AttestatController::attestat_print
            └── AttestatPrintService::generateForStudent → PDF stream
```

---

## Типы шаблонов

| Код | Назначение |
|-----|-----------|
| `main` | Основной разворот аттестата |
| `title` | Страница со спецкурсами |
| `appendix` | Приложение с оценками |
| `main_honors` | Разворот для «с отличием» |
| `title_honors` | Страница спецкурсов «с отличием» |
| *custom* | Любые дополнительные, хранятся в `attestat_template_types` |

---

## Типы предметов

| Значение | Смысл |
|----------|-------|
| `main` | Обычный предмет — попадает в приложение |
| `special_course` | Спецкурс — попадает на title-страницу |

---

## Значения оценок

| Число | Обозначение | Описание |
|-------|-------------|----------|
| `5` | 5 | Отлично |
| `4` | 4 | Хорошо |
| `3` | 3 | Удовл. |
| `2` | 2 | Неудовл. |
| `-1` | зач | Зачёт |
| `-2` | нз | Незачёт |
| `-3` | — | Прочерк (предмет есть, оценки нет) |
