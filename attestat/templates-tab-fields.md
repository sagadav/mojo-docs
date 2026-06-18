# TemplatesTab — Field List Architecture

File: `resources/js/modules/academ/attestat/components/TemplatesTab.vue`

---

## Field Data Structure

```javascript
{
    key:            string,   // unique identifier
    label:          string,   // display name
    type:           string,   // 'text' | 'rows' | 'rows_combined' | 'multiline'
    source:         string,   // 'field.value' | 'subject.mark' | ...
    x:              number,   // position X in mm
    y:              number,   // position Y in mm
    w:              number,   // width in mm
    h:              number,   // height in mm
    font_size:      number,   // pt (default: 14)
    line_height:    number,   // multiplier (default: 1.2)
    row_gap:        number,   // gap between rows (default: 0)
    letter_spacing: number,   // (default: 0)
    text_align:     string,   // 'left' | 'center' | 'right'
    params:         object,   // e.g. { subject_id }
    value:          string,   // custom field value
    format:         string,
    padding_mm:     number,
    divider_ratio:  number,   // rows_combined only (0–1)
    show_divider:   boolean,
    hidden:         boolean,  // скрыто с холста, но сохранено (добавлено)
    _v:             number,   // version (2 = mm coords)
    id:             number,   // DB id для custom fields
}
```

---

## States of a Field in the List

| State | `isPlaced` | `isHidden` | dot color | list bg |
|-------|-----------|-----------|-----------|---------|
| Not placed | false | false | grey `#dee2e6` | white |
| Placed | true | false | blue `#0d6efd` | `#eef3ff` |
| Hidden | true | true | grey `#adb5bd` | faded (opacity 0.5) |

---

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `isPlaced(key)` | ~2470 | field in `placedFields`? |
| `isHidden(key)` | ~2473 | field.hidden === true? |
| `toggleField(field)` | ~2585 | click in list: focus if placed, place if not |
| `toggleHideField(key)` | ~2478 | toggle field.hidden (preserves position) |
| `placeField(field)` | ~2592 | push to placedFields with default coords |
| `removeField(key)` | ~2649 | remove from placedFields entirely |
| `normalizeField(field)` | ~2302 | normalize on load (coords, defaults, hidden) |

---

## Canvas Rendering

```vue
<!-- Only non-hidden placed fields rendered on canvas -->
v-for="field in placedFields.filter(f => !f.hidden)"
```

---

## Save / Load

- **Load**: `loadTemplate()` → `this.placedFields = data.template.fields.map(normalizeField)`
- **Save**: `saveTemplate()` debounced 800ms, triggered by watcher on `placedFields`
- `hidden` field is serialized automatically as part of the field object
- No localStorage — state lives in backend DB

---

## Auto-save Trigger

Watcher on `placedFields` (line ~1501) → `scheduleAutosave()` → debounced 800ms → POST to `endpoints.save_template`.

---

## CSS Classes (field list item)

```css
.field-list-item      /* base */
.field-placed         /* placed & visible */
.field-available      /* not placed */
.field-hidden         /* placed but hidden: opacity 0.5 */
.field-custom         /* user-defined field */

.field-dot            /* 8×8 circle indicator */
.dot-placed           /* blue #0d6efd */
.dot-empty            /* grey #dee2e6 */
.dot-hidden           /* grey #adb5bd */

.field-hide-btn       /* eye icon, shown on hover */
.field-actions        /* pencil+trash for custom fields, shown on hover */
```
