# Home Task · Strengthen Redmine API Authentication

## Original task

<details>
<summary>📋 API Authentication Enhancement Task</summary>

## Overview
Strengthen the authentication system for an open-source project management application built on Ruby on Rails.

## Requirements

### Three Core Pillars
1. **Token Expiration** – Implement time-based validity for API tokens
2. **Scopes** – Add permission-based access control to API tokens
3. **Rate Limiting** – Prevent abuse through request throttling

## Deliverables

### 1. Git Repository
- Fork/branch from the main codebase (tag 6.1.2)
- Repository must be cloneable, installable, with runnable migrations
- Implementation should be verifiable through tests or manual validation

### 2. AI Workflow Artifacts
- Document the problem-solving process (exported chats, transcripts, or prompt-response pairs)
- Show iterative refinement and corrections
- Demonstrate working with AI coding assistants effectively
- Include atomic, well-messaged commits telling a story of development
- Optional: Screen recording of actual working session

### 3. README
Brief documentation covering:
- Approach and rationale
- What's implemented vs. deferred
- Key assumptions
- How to run and verify the solution

## Key Constraints

- **Time guideline:** ~2 hours for implementation
- **Scope:** Pick a defensible slice of the three pillars—don't attempt the full feature set
- **Quality over completeness:** A focused, well-executed piece beats a half-finished sprawling implementation

## Evaluation Criteria

1. **Scoping judgment** – Is the slice defensible and worth shipping?
2. **AI workflow quality** – Clear direction and iteration, not just code generation
3. **Codebase fit** – Integration with existing patterns vs. bolted-on solutions
4. **Working software** – The slice runs and verification holds up
5. **Communication** – Named decisions and honest trade-offs

</details>

## Ссылка на Pull Request с решением
[Add IP-based API rate limiting to protect against token brute-force](https://github.com/ellhee/redmine/pull/2)

[Quickstart](https://github.com/ellhee/redmine/blob/001-api-rate-limit/specs/001-api-rate-limit/quickstart.md)

## Выбор слайса

- Если читать именно тикет, то в нем видны еще несколько частей, помимо указаных трех в тестовом задании (например 2FA bypass и проблемы логирования). Я предполагаю, что ограничения тестового задания имеет больший приоритет и рассматриваю только 3 подзадачи, указанные в нем:
    - время жизни токена,
    - области действия
    - ограничение количества запросов.
- Также я рассуждаю в контексте ограниченности ресурсов рекомендуемым временем выполнения в 2 часа.

Изначально я исключаю scopes-задачу, требующей большого погружения в проект, рассмотрения имеющихся scopes. Также ценность от ее изолированной реализации не так высока — архитектурно мы скорее хотим ограничивать scopes для множественных токенов, формируя их под разные задачи.

Далее я исключаю время жизни токена — у нее хорошее соотношение пользы и затрат, в реальном проекте скорее была бы выбрана она. Но техническое решение довольно понятное: расширение таблицы токенов новым полем и его контроль — возможно эта задача даст меньше возможностей именно в контексте тестового задания.
Больше сложности вызывает продуктовое решение — как сообщить пользователю об истечении срока жизни токена и инициировать процесс получения нового, здесь будет проблемой плохое знакомство с продуктом.

В итоге я выбираю ограничение количества запросов:
- Значимая функция (защита от брутфорса токенов и bulk data extraction)
- Достаточно изолированная и проверяемая
- Требует интеграции с Rails stack — даст больше сигнала в контексте тестового задания
- Укладывается в ~2 часа

Для того, чтобы за рекомендованное время выполнить задачу и в целом не брать огромный скоуп в работу я допускаю следующее:
- Ограничение по IP (защищает и от брутфорса, не только от конкретного токена)
- In-memory реализация без Redis

## Используемые инструменты
- для локальной разработки и тестирования я использую контейнеры Docker
- в качестве редактора кода Fleet от JetBrains (нет RubyMine)
- Claude code + Claude desktop (модель Sonnet 4.6, High Effort)
- ChatGPT / Gemini для обсуждения решений, ревью и получения знаний
- Spec-kit фреймворк от Github

## Подготовка
Я клонировал форк репозитория.
Для работы над задачей сделал новую ветку из последнего релиза (tag 6.1.2).
Для развертывания я использовал Docker с двумя контейнерами для разработки и тестирования, а также технический контейнер с Postgres, объединенные composer.
Для генерации конфигурации использовал Gemini, но сильно упростил итог, оставив минимум.

При первом запуске получил сообщение `Please configure your config/database.yml first`, которое сохранилось и после добавления файла.
Здесь Gemini при поиске проблем застрял, удостоверившись, что файла не существует на этапе установки гемов, решил самостоятельно — понял, что в Dockerfile для этапа копируется только `Gemfile`, добавил туда и `database.yml`.

Открыл веб-интерфейс (http://localhost:300), запустил миграции через консоль, посмотрел устройство, администрирование, включил API.
Запустил прогон тестов, отдельной командой создав и подготовив базу данных (формат команды подсказал Gemini).

Этот этап занял около 20 минут.

## Основная задача

### Сбор информации о проекте

В новой сессии Claude запустил команду сбора фундаментальной информации о кодовой базе

<details>
<summary>Скилл speckit-constitution</summary>

**/speckit-constitution** Это проект Redmine, написаный на Ruby on Rails. Удели внимание тому, какие подходы уже используются для написания кода, какие инструменты включены. Отдельно посмотри структуру тестов и их содержимое, что проверяется обычно и на каком уровне

Начинаю изучение проекта: читаю структуру, конституцию и тесты.
Git уже инициализирован, продолжаю. Теперь исследую проект для заполнения конституции.
Ran 20 commands, read 5 files
Достаточно данных. Теперь смотрю CONTRIBUTING и несколько ключевых моделей.
Собрал всё необходимое. Пишу конституцию.

Constitution authoring
Updated
constitution.md +174 -0
Конституция записана. Теперь проверяю шаблоны на совместимость.

Ran
Check plan template references to constitution
Plan-шаблон содержит Constitution Check секцию — обновлю её, чтобы она ссылалась на реальные принципы.

Edited
plan-template.md +8 -1

Итог
Конституция Redmine создана

| # | Принцип | Ключевое правило |
| :--- | :--- | :--- |
| **I** | **Rails Conventions First** | MVC, frozen_string_literal, GPL-заголовок, бизнес-логика в моделях |
| **II** | **Multi-Level Test Coverage** | Unit → Functional → Integration → API; запуск через Docker |
| **III** | **Fixtures as Test Data Authority** | 53 YAML-фикстуры — единственный источник тестовых данных |
| **IV** | **Plugin-Based Extensibility** | Плагины в plugins/, расширения ядра — через lib/redmine/ |
| **V** | **REST API Parity** | Каждая UI CRUD-операция доступна через REST (JSON + XML) |
| **VI** | **Internationalization** | Все строки через I18n; нет хардкода на английском в ERB |

Что обновлено

✅ .specify/memory/constitution.md — создан с нуля (был только шаблон)

✅ .specify/templates/plan-template.md — Constitution Check заменён конкретными чеклистами по принципам I–VI

✅ .specify/templates/spec-template.md — совместим, изменений не требует

✅ .specify/templates/tasks-template.md — совместим, пути src//tests/ заменяются на app//test/ при генерации задач


</details>

Мельком просмотрел содержимое — я не знаком с Rails и проектом, поэтому решил не тратить время и положиться на качество сбора информации скиллом.

Попросил проверить наличие линтера.

Пока шло выполнение, параллельно в Gemini посмотрел, какие есть способы реализации: классический middleware-подход и использование before_action.
Предварительно выбрал before_action, хотя он будет менее производительным из-за инициализации большего количества слоев.

Middleware посчитал менее подходящим из-за того, что:
- судя по имещюимся настройкам и внешнему виду администрирования, мы хотим управлять ограниченим тоже из веб-интерфейса, что ведет к взаимодействию с Settings в реализации
- в будущем, согласно тикету, эта система может быть дополнена token-based ограничениями, что тоже добавит работу на уровне модели Token

Суммарно это выглядит большим выходом за рамки чисто HTTP-слоя Middleware, при этом разницу в производительности я считаю допустимой.

### Проектирование

<details>
<summary>Скилл speckit-specify</summary>

**/speckit-specify**
Нам необходимо ограничение количества запросов (Rate Limit) для API.
В первоначальной версии делаем только на основе IP, в будущем этот функционал может быть доработан до token-based варианта и их комбинации.
По умолчанию ограничение выключено.
Ограничение (включение и параметры) администрируется через веб-страницу настроек администратором по аналогии с другим функционалом

Ветка уже существует, скрипт вернул BRANCH_NAME: "001-api-rate-limit", FEATURE_NUM: "001". Создаю директорию спецификации и пишу spec.md.

Теперь провожу валидацию качества спецификации и создаю чеклист.

Created requirements.md +36 -0

Спецификация создана
- Директория: specs/001-api-rate-limit/
- Файл спецификации: specs/001-api-rate-limit/spec.md
- Чеклист: specs/001-api-rate-limit/checklists/requirements.md

Что описано в спецификации
3 пользовательских сценария:

- P1 — Защита API от перегрузки: блокировка по IP с HTTP 429 + Retry-After
- P1 — Административное управление: включение/настройка параметров через страницу настроек без перезапуска
- P2 — Информирование клиента: заголовки X-RateLimit-* в ответах
- 10 функциональных требований (FR-001..FR-010): выключено по умолчанию, IPv4/IPv6, X-Forwarded-For, только API-запросы, валидация параметров.

Чеклист валидации: ✅ все пункты пройдены, маркеров [NEEDS CLARIFICATION] нет.

Ключевые допущения v1
- Только IP-based (token-based — в следующих версиях)
- In-memory хранилище счётчиков
- Единые настройки для всего API (без разграничения по эндпоинтам)
</details>

<details>
<summary>Уточнил цели</summary>

Назначение задачи - защита от перебора токенов и предотвращение bulk data extraction

Важное уточнение назначения — обновлю спецификацию, чтобы эти цели явно отражались в контексте, сценариях и требованиях.

Read spec.md
Это важное уточнение — меняет контекст с «защиты от перегрузки» на явную модель угроз безопасности. Обновляю спецификацию.

Edited spec.md +24 -16
Спецификация обновлена. Ключевые изменения:

Что изменилось:

- Назначение — явно указаны две угрозы: перебор токенов и bulk data extraction
- Сценарий 1 — переориентирован на атаку перебора токенов: лимит срабатывает независимо от корректности токена, даже если токен верный — IP всё равно блокируется
- FR-002 — добавлено: счётчик инкрементируется до проверки аутентификации (иначе атака перебора будет работать)
- FR-011 — новое требование: тело ответа 429 не должно раскрывать, существует ли аккаунт или верен ли токен
- SC-001, SC-002 — критерии успеха теперь явно описывают защиту от конкретных угроз
- Граничные случаи — добавлены: NAT/корпоративные сети, применение лимита к 401-ответам
- Допущения — зафиксирован компромисс с NAT и мотивация применения лимита до аутентификации
</details>

Сделал ревью спецификации, пользовательских сценариев и требований

<details>

<summary>Скорректировал User Stories</summary>

Добавь пользовательский сценарий корректной работы (запросы укладываются в лимиты) и пользовательский сценарий работы без включения функционала - ничего не блокируется

Читаю текущую спецификацию чтобы вставить сценарии в правильное место.

Read a file, edited a file
Сценарии 4 и 5 добавлены. Вот что описывает каждый:

Сценарий 4 — Нормальная работа (P1):

- Запросы в пределах лимита получают нормальные ответы
- Заголовки X-RateLimit-Remaining убывают корректно
- После сброса окна счётчик восстанавливается
- Разные IP имеют независимые счётчики — не мешают друг другу

Сценарий 5 — Выключенный rate limiting (P1):

- Ни один запрос не получает 429 в любом объёме
- Заголовки X-RateLimit-* отсутствуют в ответах
- Никакой проверки счётчиков не происходит (нет overhead)
- При выключении уже заблокированные IP разблокируются
</details>

<details>
<summary>Требование потокобезопасности</summary>

Добавь userstory для потокобезопасности

Сценарий 6 добавлен (P2). Три acceptance criteria покрывают:

- Верхняя граница: при N+K одновременных запросах ровно N проходят, K блокируются — не больше
- Отсутствие потерь: при параллельной записи в счётчик ни один инкремент не теряется
- Изоляция: параллельная обработка разных IP не приводит к взаимному загрязнению счётчиков
</details>

Критерий из User Story 5 показался мне довольно размытым "при выключенном ограничении не приходит 429" — в то время как мы хотим, чтобы при выключенном ограничении клиенты получали ответы.

<details>
<summary>Уточнение User Story 5</summary>

Обнови Сценарий 5 — Выключенный rate limiting - не просто отсутствие заголовков и 429, а получение полноценного ответа 200

Обновлено. Теперь во всех четырёх acceptance criteria явно указан HTTP 200 (или другой штатный код) как ожидаемый результат, а не просто «отсутствие 429». Акцент сместился с «что не происходит» на «что должно происходить».
</details>

Сделал анализ вспомогательным навыком speckit-clarify — он в том числе ищет неопределенности в спецификации задания

<details>
<summary>Скилл speckit-clarify</summary>

/speckit-clarify

Запускаю проверку prerequisites и загружаю спецификацию.

Ran a command, read a file

Выполняю анализ покрытия спецификации по всем категориям.

| Категория | Статус | Примечание |
| :--- | :--- | :--- |
| Функциональный охват | ✅ Clear | Цели, роли, OOS описаны |
| Модель данных | ⚠️ Partial | Нет определения типа временного окна |
| UX-потоки | ✅ Clear | Сценарии администратора и клиента есть |
| Производительность | ✅ Clear | SC-007 покрывает |
| Масштабируемость | ⚠️ Partial | Нет верхней границы числа отслеживаемых IP |
| Надёжность | ❌ Missing | Нет поведения при исчерпании памяти хранилища |
| Наблюдаемость (логи/метрики) | ❌ Missing | Нет упоминания логирования событий блокировки |
| Безопасность | ✅ Clear | FR-011, pre-auth check покрыты |
| Интеграции | ✅ Clear | In-memory, нет внешних зависимостей |
| Граничные случаи | ✅ Clear | Хорошо покрыты |
| Ограничения/компромиссы | ✅ Clear | NAT-компромисс задокументирован |
| Поведение при изменении настроек | ⚠️ Partial | Нет: что происходит со счётчиками при смене конфига |
| Терминология | ✅ Clear | Консистентна |

**Вопрос 1 из 5: Тип временного окна**

Контекст: Спецификация говорит о «временном окне», но не уточняет его тип. Это ключевое архитектурное решение, влияющее на поведение на границе периода и эффективность защиты от брутфорса.

Что нужно уточнить: Как работает временное окно счётчика — фиксированное или скользящее?

Рекомендация: Вариант B (скользящее) — равномерно ограничивает поток в любой момент времени, нет эффекта «двойного всплеска» на стыке периодов, что важно для защиты от брутфорса.

| Вариант | Описание |
| :--- | :--- |
| **A** | **Фиксированное окно** — счётчик сбрасывается в фиксированные моменты (например, каждые 60 секунд по часам). Проще реализовать. Уязвимость: на стыке двух окон возможен всплеск до 2×N запросов. |
| **B** | **Скользящее окно** — всегда смотрит на N секунд назад от текущего момента. Равномерная защита без пиков на стыке. Сложнее хранить. |
| **C** | **Без разницы для v1** — оставить на усмотрение реализации, задокументировать как деталь. |

Принято: скользящее окно. Обновляю спецификацию.

**Вопрос 2 из 5: Логирование событий блокировки**

Контекст: Спецификация описывает защиту от брутфорса и bulk extraction, но не упоминает, должна ли система фиксировать факты блокировки. Без логов администратор не знает, работает ли rate limiting и атакуется ли система.

Что нужно уточнить: Должна ли система записывать в лог события превышения лимита (IP, время, количество запросов)?

Рекомендация: Вариант A — события блокировки являются событиями безопасности, их отсутствие в логах делает защиту «слепой» и затрудняет расследование инцидентов.

| Вариант | Описание |
| :--- | :--- |
| **A** | **Логировать каждое срабатывание** — при первом 429 для IP в текущем окне писать в лог: IP, момент времени, число запросов. Повторные 429 в том же окне — не дублировать. |
| **B** | **Логировать каждый 429** — записывать каждый отклонённый запрос отдельной строкой. |
| **C** | **Не логировать** — логирование остаётся на усмотрение реализации, в спецификацию не включать. |

Принято: логировать первое срабатывание на IP за окно. Обновляю спецификацию.

**Вопрос 3 из 5: Поведение при исчерпании памяти хранилища**

Контекст: Счётчики хранятся in-memory. При большом числе уникальных IP (например, при распределённой атаке) хранилище может расти неограниченно. Спецификация не определяет, что делать, когда достигнут предел — а это решение прямо влияет на надёжность сервера и безопасность.

Что нужно уточнить: Что делает система, когда число отслеживаемых IP достигает максимально допустимого?

Рекомендация: Вариант A — вытеснение по LRU защищает память сервера, при этом продолжает работать для активных IP. «Забытый» IP при следующем запросе просто начнёт новый счётчик — допустимый компромисс.

| Вариант | Описание |
| :--- | :--- |
| **A** | **Вытеснение LRU** — при достижении лимита вытесняется запись с наиболее давним последним запросом. Новый IP получает чистый счётчик. Максимальное число записей настраивается (с разумным дефолтом). |
| **B** | **Отказ «открытый» (fail open)** — при превышении лимита записей новые IP не отслеживаются и пропускаются без ограничений. Приоритет доступности над безопасностью. |
| **C** | **Не ограничивать** — хранилище растёт неограниченно; ответственность за память лежит на операционной конфигурации сервера. |

Давай очистку устаревших данных при достижении максимального количества записей (настраивается и имеет дефолтное значение)

Принято: очистка устаревших записей при достижении лимита. Обновляю спецификацию.

**Вопрос 4 из 5: Поведение счётчиков при изменении настроек администратором**

Контекст: Администратор может изменить параметры в любой момент — например, уменьшить лимит с 200 до 50 или изменить длину окна. Спецификация не определяет, что происходит с уже накопленными счётчиками в этот момент.

Что нужно уточнить: Что происходит с существующими счётчиками IP, когда администратор сохраняет новые настройки?

Рекомендация: Вариант A — сброс при изменении настроек прост, предсказуем и устраняет неконсистентность между старыми данными и новыми параметрами окна.

| Вариант | Описание |
| :--- | :--- |
| **A** | **Сбросить все счётчики** — при сохранении новых настроек хранилище счётчиков полностью очищается. Все IP начинают с нуля. Просто и консистентно. |
| **B** | **Сохранить счётчики** — счётчики продолжают работать, новые настройки применяются только к проверке последующих запросов. Возможна временная неконсистентность (например, метки старше нового окна). |
| **C** | **Дождаться естественного истечения** — счётчики сами устареют по скользящему окну; перезапуск не нужен. Новые параметры окна применяются к проверке немедленно. |

Принято: сброс всех счётчиков при изменении настроек. Обновляю спецификацию.

**Вопрос 5 из 5: Поведение при переполнении хранилища после очистки устаревших**

Контекст: FR-013 определяет, что при достижении лимита записей сначала выполняется очистка устаревших. Но если все записи ещё активны (атака с большого числа уникальных IP одновременно) — места всё равно нет. Поведение в этом крайнем случае не определено.

Что нужно уточнить: Что делать с новым IP, если после очистки устаревших записей хранилище всё ещё заполнено?

Рекомендация: Вариант A — приоритет защиты над отслеживанием новых IP. При распределённой атаке важнее удерживать уже отслеживаемые IP, чем добавлять новые без ограничений.

| Вариант | Описание |
| :--- | :--- |
| **A** | **Пропустить без отслеживания (fail open)** — новый IP обрабатывается без ограничений, но в лог пишется предупреждение о заполнении хранилища. Доступность важнее полноты защиты. |
| **B** | **Отклонить запрос (fail closed)** — вернуть 429 новому IP, пока хранилище переполнено. Приоритет безопасности, риск ложных блокировок. |
| **C** | **Вытеснить самую старую активную запись (LRU)** — освободить место за счёт IP с наиболее давним последним запросом. Хранилище никогда не блокирует новых IP. |

Принято: пропустить без отслеживания, записать предупреждение в лог. Финальное обновление спецификации.

Задано и принято: 5 вопросов из 5.
Файл: specs/001-api-rate-limit/spec.md

Затронутые разделы:

- Функциональные требования (FR-006, FR-009, FR-012, FR-013)
- Ключевые сущности (RateLimitCounter)
- Раздел «Уточнения» (новый, сессия 2026-05-28)

Все категории разрешены. Спецификация готова к планированию.
</details>

Скилл хорошо нашел проблему утечки памяти, я скорректировал вариант поведения — не просто вытеснять по одной записи, а очищать все устаревшие.

Второе хорошее предложение — логирование критических событий, я посчитал это важным для полноценного использования функционала.

<details>
<summary>Скилл speckit-plan</summary>

**/speckit-plan**

Запускаю setup и загружаю контекст.

Ran a command, read a file
Теперь исследую кодовую базу для Phase 0 — изучу, как в Redmine реализованы похожие механизмы.

Ran 21 commands
Достаточно данных для исследования. Пишу все артефакты плана.

Phase 0: Research
Created research.md +130 -0

Phase 1: Design & Contracts
Created 3 files, ran a command

Теперь заполняю plan.md и обновляю CLAUDE.md.

Результат планирования
- Ветка: feature/api-rate-limiting
- Plan: specs/001-api-rate-limit/plan.md

Созданные артефакты

| Файл | Содержание |
| :--- | :--- |
| `specs/001-api-rate-limit/research.md` | 8 решений: точка интеграции, алгоритм, потокобезопасность, настройки, логирование |
| `specs/001-api-rate-limit/data-model.md` | Структура Settings (4 ключа) и in-memory Store; диаграмма состояний |
| `specs/001-api-rate-limit/contracts/http-headers.md` | Контракт HTTP-заголовков для 200 и 429 ответов |
| `specs/001-api-rate-limit/quickstart.md` | Инструкция включения, тестирования и чтения логов |

Ключевые архитектурные решения
- lib/redmine/rate_limit.rb — вся логика, Mutex-protected Store, публичный интерфейс check(ip)
- prepend_before_action — запуск до аутентификации, только для api_request?
- Скользящее окно — массив timestamps, очистка при каждом обращении
- Fail open при overflow — пропускать + warn в лог
- Сброс хранилища при сохранении любого из rate limit параметров
- Constitution Check: ✅ все 6 принципов пройдены

</details>

Здесь мне не понравилось решение хранить все временные метки в массиве

<details>
<summary>массив timestamps</summary>

А зачем нам массив timestamps всех запросов в памяти? Давай хранить только количество, значительно сократив использование памяти

Хорошее наблюдение по памяти. Прежде чем обновлять артефакты — важно обозначить последствие.

Ситуация: хранить только счётчик (count) — это уже не скользящее окно, а фиксированное (fixed window). Скользящее окно требует знать когда именно каждый запрос пришёл, чтобы понять, какие из них ещё «в окне» прямо сейчас. Без меток времени это невозможно точно.

Но есть компромиссное решение: аппроксимация скользящего окна через два счётчика (current + previous window). Именно так работают Nginx, Cloudflare, Redis rate limiters:

| Вариант | Память / IP | Точность | Примечание |
| :--- | :--- | :--- | :--- |
| **Массив timestamps** | до 2 400 байт | Точно | Был выбран в Q1 |
| **Два счётчика** | ~24 байта | ~99% | Рекомендую |
| **Один счётчик** | ~16 байт | Fixed window | 2× burst на стыке периодов |

Обновляю все артефакты под вариант два счётчика — сохраняем семантику скользящего окна из Q1 и получаем 100-кратное сокращение памяти.

Также обновляю формулу X-RateLimit-Reset в контракте — при аппроксимации она считается иначе:

Все артефакты обновлены. Итог изменения:

| Характеристика | До (Массив timestamps) | После (Два счётчика) |
| :--- | :--- | :--- |
| **Структура на IP** | `Array<Float>` (timestamps) | `{prev_count, curr_count, window_start, logged}` |
| **Память на IP** | до 2 400 байт | ~24 байта (константа) |
| **Макс. память (10K IP)** | ~24 МБ | ~240 КБ |
| **Время проверки** | $O(\text{max\_requests})$ | $O(1)$ |
| **Тип окна** | Точное скользящее | Аппроксимация скользящего (погрешность ≤ 10%) |
| **2× burst на стыке** | Нет | Нет (в отличие от fixed window) |

</details>

Также просмотрел исследования и принятые решения, остальное меня устроило.

<details>
<summary>Скилл speckit-tasks</summary>

**/speckit-tasks** удели побольше внимания качественной проработке тестов, убедись в хорошем, но не избыточном покрытии

Загружаю все артефакты для генерации задач.

Генерирую задачи с детальной проработкой тестов на всех уровнях.

Задачи сгенерированы
Файл: specs/001-api-rate-limit/tasks.md

| Фаза | История | Задач | Тестов |
| :--- | :--- | :--- | :--- |
| **1 — Setup** | — | — | 2 |
| **2 — Foundation** | — | — | 213 unit-кейсов (T003) |
| **3 — Enforcement** | US1, US4, US5 | — | 210 integration-кейсов (T005) |
| **4 — Admin Settings** | US2 | — | 34 functional-кейса (T007) |
| **5 — Thread Safety** | US6 | — | 11 concurrent unit-тест (T010) |
| **6 — Polish** | — | — | 3 |
| **Итого** | — | — | **328 тест-кейсов** |

Покрытие тестами

Unit (13 кейсов в T003 + 1 в T010): алгоритм Store, sliding window, window slide, overflow (оба варианта), логирование (дедупликация), сброс, потокобезопасность

Functional (4 кейса в T007): рендер формы настроек, сохранение валидных/невалидных данных, сброс store при сохранении

Integration (10 кейсов в T005): выкл. по умолчанию (US5), золотой путь с заголовками (US4), JSON и XML (Принцип V), 429 при превышении (US1), нейтральное тело (FR-011), верный токен всё равно блокируется, HTML-запросы не ограничиваются (FR-008), сброс окна с Mocha

MVP

Phases 1–3 (T001–T006): rate limiting работает, тесты зелёные, готово к демо

</details>

### Реализация

Запустил выполнение, параллельно с анализом получившихся артефактов для экономии времени — если будут замечания попрошу переделать детали, принципиально план задач и их описание перед стартом выглядят хорошо.

<details>
<summary>Скилл speckit-implement</summary>

**/speckit-implements**

Overall: PASS — proceeding to implementation.


Read 2 files
Implementation
Now loading implementation context:


Ran 14 commands, read 5 files
Now let me look at existing tests to understand patterns:


Ran 16 commands, read 3 files
I have all the context I need. Starting implementation — Phase 1 (T001 + T002 in parallel):


Read 2 files, ran a command
Now I have everything. Let me apply all Phase 1 changes in parallel:


Edited 2 files
✅ T001 + T002 complete. Now Phase 2 — writing tests first (T003), then implementation (T004):


Ran a command, created a file
✅ T003 written. Now implementing the core module (T004):

Created
rate_limit.rb +174 -0
Now let me verify T003 tests work with T004 implementation. First, check whether rate_limit.rb is auto-loaded:


Ran 9 commands, read a file
✅ 14/14 tests pass (T003 × 13 + T010 concurrent test).

Now Phase 3 — writing integration tests (T005) then controller integration (T006):


Ran a command, created a file
✅ T005 written. Now T006 — add check_api_rate_limit to ApplicationController:


Read a file, ran a command, edited a file
Now add the private method near api_request?:

Edited
application_controller.rb +17 -0
Now run Phase 3 integration tests:

Ran
Run Phase 3 integration tests
✅ 11/11 integration tests pass. Phase 4 — US2 (admin settings UI):


Read a file, edited a file
✅ T007 written. Now T008 — update the API settings view:

Edited
_api.html.erb +8 -0
✅ T008 done. Now T009 — add validation + store reset in SettingsController:


Read 3 files, ran 3 commands
Now add rate limit validation to Setting.validate_all_from_params:

Edited
setting.rb +9 -0
Now add the reset_store! call in SettingsController after successful save:


Read a file, edited a file
Now run Phase 4 functional tests:


Ran 3 commands, read a file
The format: int in settings.yml only validates numericality — the value is still stored and returned as a String. Fix the test assertions:


Edited a file, ran a command
✅ 26/26 functional tests pass. T010 (thread safety) was included in Phase 2's test file. Now Phase 6 — Polish (T011, T012):

Ran
Run all three rate limit test suites
All green. Now check the authentication test for regressions:

Ran
Check authentication regression test
Zero regressions. Now mark completed tasks in tasks.md:


Read a file, edited a file

All 13 tasks complete. All tests green.

Files created

| Файл | Назначение |
| :--- | :--- |
| `lib/redmine/rate_limit.rb` | Основной модуль: хранилище «два счётчика» (скользящее окно), `Mutex` для потокобезопасности, публичный интерфейс |
| `test/unit/lib/redmine/rate_limit_test.rb` | 14 unit-тестов (включая 13 базовых и 1 на конкурентность) |
| `test/integration/api_test/rate_limiting_test.rb` | 11 интеграционных тестов |

Files modified:

| Файл | Изменения |
| :--- | :--- |
| `config/settings.yml` | Добавлены 4 ключа настроек rate limit |
| `config/locales/en.yml` | Добавлены 6 ключей I18n (`setting_*`, `error_*`, `label_*`) |
| `app/controllers/application_controller.rb` | Добавлен `prepend_before_action :check_api_rate_limit` |
| `app/controllers/settings_controller.rb` | Вызов `reset_store!` при сохранении настроек |
| `app/models/setting.rb` | Валидация для `max_requests`, `period`, `max_ips > 0` |
| `app/views/settings/_api.html.erb` | Секция настроек ограничения запросов с 4 полями |
| `test/functional/settings_controller_test.rb` | 6 функциональных тестов |

Test results

| Suite | Runs | Assertions | Status |
| :--- | :--- | :--- | :--- |
| **unit** (`rate_limit_test.rb`) | 14 | 30 | ✅ all pass |
| **functional** (`settings_controller_test.rb`) | 26 | 94 | ✅ all pass |
| **integration** (`rate_limiting_test.rb`) | 11 | 44 | ✅ all pass |
| **regression** (`authentication_test.rb`) | 18 | 29 | ✅ no regressions |

</details>

После попросил запустить линтер

<details>
<summary>Линтер + тесты</summary>

Запусти линтер пожалуйста и после него снова тесты наших задач

Что исправил RuboCop:

- evict_stale! — Style/IdenticalConditionalBranches: метод переписан, чтобы approx_count < 1.0 было вынесено из ветвей if/else (теперь обе ветви только вычисляют approx_count, а сравнение — единственный return после)
- 20.times.map → Array.new(20) в тесте потокобезопасности — Performance/TimesMap
- assert_response 429 → assert_response :too_many_requests во всех integration-тестах — Rails/HttpStatus

</details>

После этого проверил функционал вручную, нашел 2 проблемы:
- несоответствие контракту: не возвращались человеко-понятные сообщения в теле 429 ответа;
- баг при включении/отключении функционала через административный раздел

<details>
<summary>Исправление 1</summary>

А у нас есть тест, который проверяет наличие сообщения в теле ответа заблокированного запроса для соответствия принятым контрактам задачи?
Я сейчас смотрю вручную и вижу только 429

Нет, такого теста нет — и ты прав: тело сейчас пустое. render_error для API использует format.any { head @status }, что возвращает только статус без тела. Нужно исправить реализацию и добавить тест.


Read a file, edited a file
Теперь добавляю тесты на тело ответа в integration-тест:


Edited a file, ran a command
13/13. Быстро прогоню линтер на изменённые файлы:


Ran 3 commands, edited a file
Линтер чист, 13/13 тестов зелёных. Вот что было сделано:

Проблема: render_error для API-запросов вызывает format.any { head @status } — возвращает только статус, без тела.

Исправление в check_api_rate_limit (application_controller.rb): заменил render_error на явный respond_to блок с телом по контракту:

JSON: {"errors": ["Rate limit exceeded. Please try again later."]}
XML: <errors><error>Rate limit exceeded. Please try again later.</error></errors>
Добавлены два новых теста в rate_limiting_test.rb:

- test_429_json_body_contains_error_message — проверяет структуру JSON через response.parsed_body
- test_429_xml_body_contains_error_message — проверяет XML через assert_select 'errors error'

</details>

<details>
<summary>Исправление 2</summary>

Добавь еще тест на проверку работы ограничения после изменения параметров ограничения.

Я включил ограничение, добился ограничения своих запросов, выключил - запросы стали возвращать данные, включил обратно и вижу ошибку

comparison of Integer with String failed — if @data.size >= @max_size

Вижу баг. Setting.api_rate_limit_max_ips возвращает String, а @max_size в Store используется в сравнении @data.size >= @max_size (Integer vs String). Это происходит при вызове reset_store! из контроллера настроек без .to_i.

Сначала напишем падающий тест:


Read a file, edited a file
Запускаем — тест должен упасть:


Ran a command
Тест подтверждает баг (500). Теперь фиксируем — добавляем .to_i в reset_store!:

Edited
rate_limit.rb +2 -1
Проверяем, что тест теперь проходит:

Ran
Run all integration tests including the new toggle test
14/14. Линтер:

Ran
Lint fixed files
Чисто. Полный прогон всех наших тестов:

Ran
Full test suite run
54 теста, 0 падений.

Что было сделано:

Баг: Setting.api_rate_limit_max_ips возвращает String (так работают все Redmine settings — даже с format: int). При вызове reset_store!(max_size: Setting.api_rate_limit_max_ips) в Store попадала строка "10000", и затем @data.size >= @max_size падало с ArgumentError: comparison of Integer with String failed.

Фикс в reset_store! — добавил .to_i при создании нового Store. Метод теперь явно коерсит аргумент, что защищает от строк из настроек независимо от того, как его вызывают.

Тест test_toggle_rate_limiting_on_off_on_does_not_raise воспроизводит весь цикл, который ты описал: включить → исчерпать лимит → выключить → включить через reset_store! со строковым значением из настроек → убедиться что запрос проходит без ошибки.

</details>

Посмотрел тесты самостоятельно и показал их внешней модели, из критичного решил исправить отсутствие travel_to (использовался Time.stubs(:now))

Просмотрел изменения в коде и Service Object RateLimit особенно.

Мне не понравилось наличие публичного доступа store_size, он был необходим только тестам для контроля содержимого. Посчитал это плохим паттерном юнит-теста: проверкой имплементации, а не поведения — нам важно, чтобы при блокировке не количество записей увеличивается на 1, а что при привышении лимита блокируются.

<details>
<summary>Исправление 3</summary>

А уточни, для чего у нас публично доступен store_size в RateLimit?
Да, давай сделаем проверку именно поведения

Смотрю все тесты с store_size и планирую замену:


Read 2 files
Картина ясна. Делаю три правки одновременно:

- test_overflow_evicts_stale_entries_and_allows_new_ip — убрать assert_equal 3, store_size (избыточно: 3 вызова уже наполнили store) и assert store_size <= 3 (уже проверяется через :allowed vs :untracked)
- test_clear_empties_store — переписать: исчерпать лимит → убедиться что denied → сбросить → убедиться что allowed
- test_save_rate_limit_settings_resets_store — то же: заблокировать IP → сохранить настройки → убедиться что allowed

Edited 2 files
Теперь удаляю store_size из rate_limit.rb:

Edited rate_limit.rb +0 -5
Запускаем все три набора тестов:

Ran 2 commands
54 теста, 0 падений, линтер чист.

Итог изменений:

store_size удалён из публичного интерфейса Redmine::RateLimit. Три теста переписаны на поведение:

</details>

Далее попросил убрать использование Rails.logger.warn прямо внутри RateLimit, посчитал это ненужной зависимостью класса от Rails

<details>
<summary>Исправление 3</summary>

Я вижу Rails.logger.warn внутри RateLimit - давай перенесем его на уровень выше.
Пусть RateLimit возвращает только флаг необходимости логирования

Now I have all the context. Let me implement the changes across all three files.

Move logging out of RateLimit
Step 1 — lib/redmine/rate_limit.rb: remove both Rails.logger.warn calls and add a log: key to the result hashes instead.

Step 2 — app/controllers/application_controller.rb: handle the :log flag and emit warnings there.

Step 3 — update the unit tests: the two log-related tests now assert on result[:log] instead of mocking Rails.logger. Also add a log: assertion to the overflow test.

Now add a log: assertion to the overflow test:

Now run the tests to verify everything is green:


Ran 3 commands
All 54 tests green across all three suites. Let me do a quick RuboCop pass on the changed files:

Ran
RuboCop on changed files
No offenses. Here's a summary of what changed:

lib/redmine/rate_limit.rb — Store no longer calls Rails.logger at all. Instead it adds a log: key to the result hash:

- :untracked → log: :overflow
- First :denied in a window → log: :blocked (deduplication via logged_this_window stays inside Store where it belongs)
- Subsequent :denied → log: nil
- :allowed, :disabled → no log: key (nil by default)

app/controllers/application_controller.rb — check_api_rate_limit checks result[:log] with a case and calls logger.warn with the appropriate message before the early-return guard. The logging now happens at the boundary where the caller has the full HTTP context (request.remote_ip, settings, Time.now).

test/unit/lib/redmine/rate_limit_test.rb — the two logging tests are renamed and rewritten to assert on result[:log] rather than mocking Rails.logger. The overflow test also gains a log: :overflow assertion.

</details>

Финально запустил всё тесты проекта и еще раз проверил вручную функционал.

## Итог
Выполнение заняло около 2 часов. Часто не хватало знания Rails и проекта Redmine, если бы было больше времени, я бы глубже изучил их.

Часто возникали проблемы кодогенерации из-за неточности собранной фундаментальной информации, в проектах, где конституция составляется более тщательно, они бы не возникали.

Также больше бы поработал с набором тестов, некоторые мне кажутся избыточными (например тест на нераскрытие валидных токенов), и лучше бы вник в основной код RateLimit

## Список основных  trade-offs

- отказ от распределенных систем для хранения информации о блокировках (например Redis)
- блокировка только на основе IP (token-based не защищала бы от перебора токенов)
- использвоание prepend_before_action вместо middleware (функционал шире, чем http-only слой, использование готовых хелперов контроллера, системы локализации)
- сброс счетчиков при изменении настроек (отсутствие миграции -> проще реализация, но в момент смены заблокированные IP снова будут активны)
- отключение блокировки при привышении лимита памяти (выбрана стабильность инфраструктуры и доступ для легитимных пользователей)

## Скриншоты

![Блокировка запроса](Screenshot%201.png)
![Администрирование](Screenshot%202.png)