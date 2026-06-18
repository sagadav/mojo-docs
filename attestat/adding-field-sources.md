# Добавление нового источника данных для поля аттестата

Инструкция для агентов: как добавить новый **источник** (`source`) поля шаблона аттестата —
например «Регион ученика» или вычисляемый «Средний балл».

Источник — это строка вида `student.surname`, `subject.mark`, `now.year`. Пользователь
создаёт во вкладке **«Шаблон»** текстовое поле, выбирает источник из выпадающего списка
и размещает его на бланке. Значение подставляется и в **превью** (Vue), и в **PDF** (PHP).

---

## Главное правило: ДВА пути рендера

Источник резолвится в **двух независимых местах**. Поправить нужно **оба**, иначе значение
покажется только где-то одном.

| Путь | Файл | Функция |
|------|------|---------|
| **PDF** (печать) | `app/Services/Attestat/Fields/SourceResolver.php` | `resolve()` (`match`) |
| **Превью** (Vue) | `resources/js/modules/academ/attestat/components/AttestatPreviewModal.vue` | `computeSource()` (`switch`) |

Текстовые поля в PDF рендерит `GenericTextFieldHandler` → он зовёт `SourceResolver::resolve()`.
Контекст рендера — DTO `AttestatRenderContext` (объект `student`, `sideRows`, школа и т.д.).

---

## Чеклист (минимум 3 файла)

### 1. Регистрация источника в списке
`config/attestat-print/field_sources.php` — добавить ключ. Он попадёт в выпадающий список
источников (`AttestatFieldDefinitionService::getFieldDefinitions`) и проходит валидацию
в `saveFieldDefinition()`.

```php
'student.region' => ['label' => 'Регион ученика', 'label_trans_code' => 'attestat_field_source_student_region'],
```

`label_trans_code` — код перевода (таблица `directory_translate`). Если перевода нет,
`translate()` вернёт сам код → используется `label` как фолбэк.

### 2. Резолв в PDF
`app/Services/Attestat/Fields/SourceResolver.php` → новый case в `match`:

```php
'student.region' => (string) ($ctx->student->region ?? ''),
```

Для вычисляемых значений — отдельный приватный метод (см. пример `averageMark()` ниже).

### 3. Резолв в превью
`resources/js/.../AttestatPreviewModal.vue` → `computeSource()` → новый case в `switch`:

```js
case 'student.region': return this.student?.region ?? '';
```

### 4. (Если данные из БД) протащить колонку в объект ученика
Объект `student` собирается в **трёх** запросах. Источник `student.*` требует, чтобы поле
было в SELECT всех трёх:

| Запрос | Назначение |
|--------|-----------|
| `AttestatPrintService::fetchStudent()` | PDF одного ученика |
| `AttestatPrintService::fetchStudentsForGrade()` | PDF по параллели/классу |
| `AttestatMarkDataService::fetchStudentsForGrade()` | список + превью (Vue `this.student`) |

```sql
COALESCE(s.student_region, '') AS region
```

> Алиас (`AS region`) должен совпадать с тем, что читают `SourceResolver` (`$ctx->student->region`)
> и Vue (`this.student.region`). Перед правкой проверь имя колонки:
> `Schema::hasColumn('students', 'student_region')`.

### 5. Пересобрать фронт
```bash
npm run dev
```
Vue-изменения не подхватятся без пересборки `public/js/academ/attestat.js`.

---

## Пример A — простое поле из таблицы `students` (`student.region`)

5 файлов: `field_sources.php`, `SourceResolver.php`, `AttestatPreviewModal.vue`,
`AttestatPrintService.php` (2 запроса), `AttestatMarkDataService.php` (1 запрос) + `npm run dev`.

См. коммит с `student.region` — образец для любого поля «из карточки ученика».

---

## Пример B — вычисляемое поле (`attestat.average_mark`)

Средний балл по всем оценкам аттестата, округление до сотых. Данные уже есть в контексте
(`$ctx->sideRows['all']` — строки предметов с отображаемой отметкой `mark`), поэтому **запросы
трогать не нужно** — только 3 файла.

`SourceResolver.php`:
```php
'attestat.average_mark' => $this->averageMark($ctx),
// ...
private function averageMark(AttestatRenderContext $ctx): string
{
    $rows = $ctx->sideRows['all'] ?? [];
    $sum = 0; $count = 0;
    foreach ($rows as $row) {
        if (!preg_match('/\d+/', (string) ($row['mark'] ?? ''), $m)) continue;
        $value = (int) $m[0];
        if ($value < 2 || $value > 5) continue;   // прочерк/зачёт/незачёт — мимо
        $sum += $value; $count++;
    }
    return $count === 0 ? '' : number_format($sum / $count, 2, '.', '');
}
```

`AttestatPreviewModal.vue` (тот же расчёт по `this.appendixData.all`):
```js
case 'attestat.average_mark': {
    const allRows = (this.appendixData?.all?.length
        ? this.appendixData.all
        : [...(this.appendixData?.left ?? []), ...(this.appendixData?.right ?? []), ...(this.appendixData?.title ?? [])]);
    let sum = 0, count = 0;
    for (const r of allRows) {
        const m = String(r.mark ?? '').match(/\d+/);
        if (!m) continue;
        const v = parseInt(m[0], 10);
        if (v < 2 || v > 5) continue;
        sum += v; count++;
    }
    return count ? (sum / count).toFixed(2) : '';
}
```

> Оценка хранится в строке как **отображаемая** (`mark`): в режиме `grade_only` это цифра,
> в текстовых режимах — `5 (отлично)` / `(отлично) 5`. Поэтому цифру вытаскиваем регуляркой,
> а нечисловые отметки (прочерк `—`, зачёт/незачёт) сами отсеиваются. `sideRows['all']`
> уже содержит и основные предметы, и спецкурсы (title) — отдельно их объединять не надо.

---

## Подводные камни

- **Забыл Vue** → поле пустое в превью, но печатается в PDF (или наоборот). Правь оба пути.
- **Забыл один из 3 запросов** → значение есть в превью, но пусто в PDF по параллели (или
  у одиночной печати). Проверь все три.
- **Алиасы не совпали** → тихо вернётся пустая строка. Сверь `AS <alias>` с чтением в коде.
- **Не пересобрал фронт** → правки `.vue` не видны в браузере.
- **Источник не в `field_sources.php`** → `saveFieldDefinition()` отклонит поле с
  `Unknown source` (422).
- Спец-форматы источников (`document.pole.N`, `student_integration.*`) резолвятся
  регулярками в начале `resolve()`/`computeSource()`, а не через `match`/`switch` — это
  отдельный механизм, не путать с обычными ключами.

---

## Связанные таблицы оценок (для вычисляемых полей)

| Значение | Отметка | Учитывать в среднем? |
|----------|---------|----------------------|
| `2`–`5` | цифра | да |
| `-1` | зач | нет |
| `-2` | нз | нет |
| `-3` | — (прочерк) | нет |
