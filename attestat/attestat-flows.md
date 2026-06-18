# Attestat module — flowcharts

От простого к сложному. Каждый уровень добавляет деталей. Если нужно понять «что вообще происходит» — читай Level 1. Если ищешь конкретный баг — спускайся ниже.

**Рендер:** GitHub, VS Code (расширение *Markdown Preview Mermaid Support*), Obsidian.

---

# Level 1 — В двух словах

Что делает модуль на самом верхнем уровне.

```mermaid
flowchart LR
    User([Пользователь]) --> Print[Печать аттестата]
    Print --> Calc[Расчёт оценок]
    Calc --> Render[Рендер по шаблону]
    Render --> PDF([PDF])
```

Три блока. Всё остальное — детали внутри них.

---

# Level 2 — Главные блоки

Те же 3 шага, но видно, откуда берутся данные.

```mermaid
flowchart LR
    subgraph Input[Входные данные]
        Tpl[(Шаблон)]
        Marks[(Оценки)]
        Student[(Ученик)]
    end

    Input --> Service[AttestatPrintService]
    Service --> mPDF[mPDF движок]
    mPDF --> Out([PDF файл])
```

---

# Level 3 — Маршрут: клик → файл

Что происходит между нажатием кнопки и появлением PDF.

```mermaid
flowchart TD
    Click([Клик «Печать»]) --> Route["GET /attestat_print/{id}<br/>web_academ_attestat.php:12"]
    Route --> Ctrl[AttestatController::attestat_print<br/>:260]
    Ctrl --> Svc[AttestatPrintService::generateForStudent<br/>:271]

    Svc --> Pick[Выбрать шаблон]
    Svc --> Load[Загрузить оценки]
    Svc --> Stud[Загрузить данные ученика]

    Pick --> Render[renderPage :341]
    Load --> Render
    Stud --> Render

    Render --> Out([response stream inline<br/>:276])
```

---

# Level 4 — Расчёт оценок (упрощённо)

Откуда берётся цифра в аттестате.

```mermaid
flowchart TD
    Base[(mark_final<br/>обычный журнал)] --> Calc{Есть ручной<br/>override?}
    Manual[(attestat_subject_marks<br/>ручные правки)] --> Calc

    Calc -->|Да| UseMan[Берём ручную]
    Calc -->|Нет| Auto[Считаем по формуле]

    Auto --> Weight[Взвешенное среднее по links<br/>round HALF_UP]

    UseMan --> Result([Итоговая оценка])
    Weight --> Result
```

**Правило:** ручная правка разрешена **только** для предметов без `attestat_subject_links` (`AttestatMarkService.php:185`).

---

# Level 5 — Выбор шаблона (упрощённо)

5 уровней fallback. Берём первый найденный.

```mermaid
flowchart TD
    Start([Нужен шаблон для ученика]) --> L1{1. Override<br/>для ученика?}
    L1 -->|Есть| Use([Используем])
    L1 -->|Нет| L2{2. Default<br/>для класса?}
    L2 -->|Есть| Use
    L2 -->|Нет| L3{3. Шаблон с<br/>id_class + grade?}
    L3 -->|Есть| Use
    L3 -->|Нет| L4{4. Глобальный<br/>id_class IS NULL?}
    L4 -->|Есть| Use
    L4 -->|Нет| L5[5. Любой active по grade]
    L5 --> Use
```

Код: `AttestatTemplateAssignmentService::assignedTemplate :105-161`.

---

# Level 6 — Конвертация размеров (упрощённо)

Главная зона багов. Превью и PDF идут разными путями.

```mermaid
flowchart LR
    DB[(Шаблон<br/>x,y,w,h %, font_size pt)]

    DB --> Branch{Куда рендерим?}

    Branch -->|Превью| Vue[Vue: проценты → cqw<br/>96 DPI]
    Branch -->|PDF| PHP[PHP: проценты → mm<br/>72 DPI]

    Vue --> Screen([Браузер])
    PHP --> File([PDF])
```

**Общая константа:** `0.35278` = `25.4 / 72` (mm в одном pt). И в JS, и в PHP.

---

# Level 7 — Полный PDF-пайплайн

Маршруты, шаблоны, шрифты, handlers — всё вместе.

```mermaid
flowchart TD
    R1["/attestat_print/{id}<br/>:12"] --> C1[attestat_print<br/>:260]
    R2["/attestat_print_batch/{grade}<br/>:13"] --> C2[attestat_print_batch<br/>:283<br/>mode: full/main/title/appendix]
    R3["/attestat_book<br/>:9"] --> C3[book_pdf<br/>:70]

    C1 --> Svc[generateForStudent :271]
    C2 --> SvcG[generateForGrade :305]
    C3 --> Blade[attestat_book_pdf.blade.php]

    Svc --> Honors[fetchHonorsFlags :624]
    SvcG --> Honors

    Honors --> Tpl[assignedTemplate :105]
    Tpl --> Mpdf[makeMpdf :263<br/>font=timesnewroman, margins=0]

    Mpdf --> Font[timesNewRomanFontDir :308<br/>storage/app/fonts/times-new-roman/]
    Font --> Render[renderPage :341]

    Render --> Loop[Цикл по полям]
    Loop --> Reg[FieldRegistry::get :399]

    Reg --> H1[SurnameHandler]
    Reg --> H2[BirthDateHandler]
    Reg --> H3[IssueDateHandler]
    Reg --> H4[SchoolNameHandler]
    Reg --> H5[QrCodeHandler]
    Reg --> H6[TitleRowHandler]
    Reg --> H7[AppendixRowHandler]

    H1 --> Write[mpdf->WriteFixedPosHTML]
    H2 --> Write
    H3 --> Write
    H4 --> Write
    H5 --> Img[mpdf->Image base64]
    H6 --> Write
    H7 --> Write

    Write --> Overlay[Z-overlays mpdf->Line :389-394]
    Img --> Overlay

    Overlay --> Out([Stream inline :276])
```

---

# Level 8 — Расчёт оценок (полная схема)

Все ветки, включая non-numeric, links, validation.

```mermaid
flowchart TD
    Subj[(attestat_subjects<br/>grade=9 / 11<br/>type: main / special_course)] --> SubjLoad[AttestatSubjectService::list :24]

    Links[(attestat_subject_links<br/>weight default 1.0)] --> LinkLoad[linksFor :40]

    BaseM[(mark_final<br/>criterion in F/Y/P<br/>subject_curriculum=1)] --> BaseLoad[loadBaseMarks :266]

    Manual[(attestat_subject_marks)] --> ManLoad[loadManualMarks :315]

    SubjLoad --> Calc{Для пары<br/>student × subject}
    LinkLoad --> Calc
    BaseLoad --> Calc
    ManLoad --> Calc

    Calc --> CheckMan{Есть<br/>override?}
    CheckMan -->|Да| UseMan[value = manual]
    CheckMan -->|Нет| Auto[calculateAttestatSubjectValue :332]

    Auto --> Collect[Собрать mark+weight по links]
    Collect --> Count{Сколько<br/>валидных?}

    Count -->|0| Null[return null]
    Count -->|1| Single[return единственное]
    Count -->|N >= 2| NonNum{Есть вне 2..5?<br/>-1/-2/-3}

    NonNum -->|Да| First[return первое<br/>без усреднения]
    NonNum -->|Нет| Weighted["round sum m×w / sum w<br/>HALF_UP, 0 знаков<br/>:47"]

    UseMan --> Map[value → sign<br/>5=отлично, -1=зачёт, -2=незачёт, -3=н/а]
    Single --> Map
    First --> Map
    Weighted --> Map
    Null --> Map

    Map --> Save[saveMark upsert :174]
    Save --> Persist[(attestat_subject_marks<br/>UNIQUE student+subject+year)]

    Save -. value пустой .-> Del[DELETE :192]
    Save -. has links .-> Reject[422 :185]
```

---

# Level 9 — Конвертация размеров (полная схема)

Все формулы и единицы.

**Хранение в `attestat_templates`:**
- `x, y, w, h` — проценты от размера документа
- `font_size` — pt
- `line_height` — безразмерный множитель
- `row_gap` — mm
- `doc_width_mm`, `doc_height_mm` — mm (A4 = 297×210)

```mermaid
flowchart TD
    DB[(attestat_templates<br/>x,y,w,h %, font pt, gap mm, doc mm)]

    DB --> Fetch[fetchTemplates :720]

    Fetch --> Branch{Канал}

    Branch -->|Превью 96 DPI| Vue[AttestatPreviewModal.vue]
    Branch -->|PDF 72 DPI| MPDF[renderPage :341]

    Vue --> VFont["font-size:<br/>pt × 0.35278 / docW × 100 = cqw<br/>:322"]
    Vue --> VGap["row_gap:<br/>mm / docW × 100 = cqw<br/>:309"]
    Vue --> VPos["x,y,w,h:<br/>CSS %"]
    Vue --> VLH["line-height:<br/>безразмерный"]

    VFont --> Cont[container-type: inline-size :431]
    VGap --> Cont
    VPos --> Cont
    VLH --> Cont

    MPDF --> Handler[FieldHandler::render]
    Handler --> PPos["x,y,w,h:<br/>% × docW/100 = mm<br/>SurnameHandler:14"]
    Handler --> PFont["font-size:<br/>clamp 6..72, передаём pt<br/>Helpers:7"]
    Handler --> PLH["line-height:<br/>fs × 0.35278 × lh = mm<br/>AppendixRowHandler:28"]

    PPos --> Wr[mpdf->WriteFixedPosHTML]
    PFont --> Wr
    PLH --> Wr

    Cont --> Screen([Browser])
    Wr --> File([PDF])
```

**Gotchas:**

| # | Проблема | Где смотреть |
|---|----------|--------------|
| 1 | Превью cqw vs PDF mm — при нестандартной ширине контейнера превью врёт | `AttestatPreviewModal.vue:322` |
| 2 | line-height: CSS множитель vs mPDF mm — высота строки может расходиться | `AppendixRowHandler:28` |
| 3 | Распределение приложения left/right: превью замеряет DOM, PDF — по метрикам | `AttestatPreviewModal.vue:176` vs `AttestatPrintService:592` |
| 4 | DPI: превью 96, PDF 72. Поправки нет. PDF визуально крупнее | — |
| 5 | QR: превью 200px фикс, PDF по w/h поля. Разные якоря размера | `QrCodeHandler:14` |

---

# Level 10 — Honors («с отличием»)

```mermaid
flowchart LR
    Set[update_honors :253] --> Upd[updateOrCreate id_student+id_year]
    Upd --> Doc[(attestat_student_docs.is_honors)]

    Print[generateForStudent] --> Fetch[fetchHonorsFlags :624]
    Doc --> Fetch

    Fetch --> Decide{is_honors?}
    Decide -->|true| HType[main_honors / title_honors]
    Decide -->|false| Base[main / title]

    HType --> Lookup[assignedTemplate :105]
    Base --> Lookup

    Lookup --> Exists{Honors-шаблон<br/>есть?}
    Exists -->|Нет| FB[Fallback на base :215-221]
    Exists -->|Да| Merge[Merge: недостающие поля из base :199-211]

    FB --> Render
    Merge --> Render[renderPage]
```

---

# Level 11 — QR-код

```mermaid
flowchart TD
    H[QrCodeHandler::render :14] --> Data["Строка: FIO + region + blank_number + date"]
    Data --> Lib[chillerlan QRCode<br/>QRGdImagePNG :28]
    Lib --> PNG[PNG bytes]
    PNG --> B64["data:image/png;base64,..."<br/>:30]
    B64 --> Pos[x,y,w,h % → mm :16-19]
    Pos --> Embed[mpdf->Image :33]
```

---

# Cheat-sheet файлов

| Что | Где |
|-----|-----|
| Маршруты | `routes/web_academ_attestat.php` |
| Контроллер | `app/Http/Controllers/academ/AttestatController.php` |
| Ajax | `app/Http/Controllers/academ/AttestatAjaxController.php` |
| **PDF-сервис** (главный) | `app/Services/Attestat/AttestatPrintService.php` |
| Контекст рендера | `app/Services/Attestat/AttestatRenderContext.php` |
| Helpers (метрики) | `app/Services/Attestat/Fields/AttestatRenderHelpers.php` |
| Handlers (по полю) | `app/Services/Attestat/Fields/Handlers/*.php` |
| Выбор шаблона | `app/Services/Attestat/AttestatTemplateAssignmentService.php` |
| CRUD шаблонов | `app/Services/Attestat/AttestatTemplateService.php` |
| **Расчёт оценок** | `app/Services/Attestat/AttestatMarkService.php` |
| Округление | `app/Services/Attestat/AttestatMarkCalculator.php` |
| Предметы | `app/Services/Attestat/AttestatSubjectService.php` |
| Settings (приказ, регион) | `app/Services/Attestat/AttestatSettingsService.php` |
| **Vue превью** | `resources/js/modules/academ/attestat/components/AttestatPreviewModal.vue` |
| Vue app | `resources/js/modules/academ/attestat/components/AttestatApp.vue` |
| Книга регистраций PDF | `resources/views/academ_attestat/attestat_book_pdf.blade.php` |
