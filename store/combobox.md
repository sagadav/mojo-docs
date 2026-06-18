# Combobox компоненты (support-модуль)

## Файлы

| Файл | Назначение |
|------|-----------|
| `store/resources/views/_elements/combobox_single.blade.php` | Одиночный выбор с поиском |
| `store/resources/views/_elements/combobox_multi.blade.php` | Мульти-выбор с поиском и бейджами |
| `store/resources/views/support/_js.blade.php` | JS-фабрика `ctfs_make_combobox` |

## Использование

### Single
```blade
@include('_elements.combobox_single', [
    'wrap_id'            => 'my_combo',
    'hidden_id'          => 'my_hidden_id',
    'hidden_name'        => 'my_field',
    'options'            => $arr,       // ['id' => 'name', ...]
    'placeholder'        => 'Поиск...',
    'search_placeholder' => 'Поиск...'
])
```

### Multi
```blade
@include('_elements.combobox_multi', [
    'wrap_id'            => 'my_combo',
    'select_id'          => 'my_select_id',
    'select_name'        => 'my_field[]',
    'badges_id'          => 'my_badges',
    'placeholder'        => 'Выберите...',
    'search_placeholder' => 'Поиск...'
])
```

Multi-комбобокс запускается без опций — они загружаются динамически через `ctfsAdminsCombo.setOptions(arr)`.

## JS-фабрика

```js
var combo = ctfs_make_combobox({
    wrap:        '#wrap_id',       // обёртка .ctfs-combobox
    hiddenId:    '#hidden_id',     // input[hidden] или select[multiple]
    multi:       true,             // false = single, true = multi
    placeholder: 'Выберите...',
    badgesId:    '#badges_id',     // только для multi
    onSelect:    callbackFn        // только для single: callback(value)
});

// Только для multi:
combo.setOptions([{ id: 1, name: 'Иван' }, ...]);
combo.reset();
```

## Инициализация в модале

Инициализация происходит в `_js.blade.php` через:
```js
$(document).on('shown.bs.modal mojo:modal-ready', '.modal', function () {
    ctfs_init_create_ticket_for_school_form();
});
```

**Важно:** `data_in_modal` использует jQuery `.html()`, который выполняет `<script>` теги внутри загружаемого HTML. Поэтому в blade-шаблонах модалов НЕ нужно дублировать инициализацию — достаточно одного места в `_js.blade.php`. Дублирование вызывает двойные обработчики на кнопке → дропдаун мгновенно открывается и закрывается.

## Известный баг: Bootstrap `d-flex !important`

**Симптом:** поиск в multi-комбобоксе не фильтрует опции.

**Причина:** Bootstrap-утилиты генерируют правила с `!important`:
```css
.d-flex { display: flex !important; }
```
Это перебивает jQuery-шный `style="display:none"` (без `!important`).

**Фикс:**
1. Не использовать `d-flex` на динамически создаваемых опциях в `setOptions`
2. Добавить CSS-правило без `!important`:
```css
.ctfs-combo-list label.ctfs-option { display: flex; }
```

Тогда `$(el).css('display', 'none')` корректно скрывает опции.

Правило применено в `modal_create_ticket_for_school.blade.php`.
