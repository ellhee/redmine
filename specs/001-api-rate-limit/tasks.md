---
description: "Задачи реализации: API Rate Limiting"
---

# Задачи: API Rate Limiting

**Входные данные**: `specs/001-api-rate-limit/`

**Предусловия**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/ ✅

**Тесты**: включены на всех трёх уровнях (unit, functional, integration) по явному запросу. Тесты пишутся **до** реализации — проверить, что они падают, затем реализовать.

**Запуск тестов**: `docker compose exec test bundle exec rake test TEST=<path>`

## Формат: `[ID] [P?] [Story?] Описание с путём к файлу`

- **[P]**: можно выполнять параллельно (разные файлы, нет зависимостей)
- **[Story]**: к какому пользовательскому сценарию относится задача
- Точные пути к файлам обязательны

---

## Phase 1: Setup

**Цель**: добавить конфигурацию и строки локализации — без них нельзя обращаться к `Setting.api_rate_*` и выводить UI.

- [ ] T001 Добавить 4 настройки rate limiting в `config/settings.yml` после блока `jsonp_enabled`: ключи `api_rate_limiting_enabled` (default: 0, security_notifications: 1), `api_rate_limit_max_requests` (format: int, default: 300), `api_rate_limit_period` (format: int, default: 300), `api_rate_limit_max_ips` (format: int, default: 10000)

- [ ] T002 [P] Добавить I18n ключи в `config/locales/en.yml`: `setting_api_rate_limiting_enabled: "Enable API rate limiting"`, `setting_api_rate_limit_max_requests: "Max requests per period"`, `setting_api_rate_limit_period: "Period (seconds)"`, `setting_api_rate_limit_max_ips: "Max tracked IPs"`, `error_rate_limit_exceeded: "Rate limit exceeded. Please try again later."`, `label_api_rate_limiting: "API Rate Limiting"`

**Checkpoint**: `Setting.api_rate_limiting_enabled?` возвращает false; `l(:error_rate_limit_exceeded)` возвращает строку.

---

## Phase 2: Foundation — Rate Limit Store

**Цель**: ядро rate limiting — хранилище счётчиков с алгоритмом аппроксимации скользящего окна, thread-safe. Все пользовательские сценарии зависят от этой фазы.

> ⚠️ **TDD**: сначала T003, убедиться что все тесты падают, затем T004.

### Тесты Foundation ⚠️ Написать первыми

- [ ] T003 Написать unit-тесты в `test/unit/lib/redmine/rate_limit_test.rb` для `Redmine::RateLimit` и `Redmine::RateLimit::Store`. Файл наследует `ActiveSupport::TestCase`, `frozen_string_literal: true`, GPL-заголовок, `require_relative '../../test_helper'`. В `setup` вызывать `Redmine::RateLimit.reset_store!` для изоляции между тестами. Тест-кейсы:
  - `test_check_returns_disabled_when_rate_limiting_is_off` — `Setting.api_rate_limiting_enabled` = 0; `Redmine::RateLimit.check('1.2.3.4')[:status]` == `:disabled`
  - `test_check_allows_request_within_limit` — enabled=1, max=5, period=60; 3 последовательных вызова `check` — каждый возвращает `status: :allowed`; `remaining` убывает (4, 3, 2)
  - `test_check_denies_request_at_limit` — enabled=1, max=3, period=60; после 3 вызовов `check` 4-й возвращает `status: :denied`, `remaining: 0`
  - `test_remaining_never_goes_negative` — при превышении `remaining` == 0, не отрицательный
  - `test_window_slides_when_period_expires` — вызвать `check` 3 раза при `max=3`; застабить `Time.now` на `now + period + 1`; следующий `check` возвращает `:allowed` (окно сдвинулось); **важно**: `now = Time.now` захватить до `Time.stubs(:now)`
  - `test_sliding_window_weights_prev_count` — вызвать check N раз, сдвинуть время на period/2; аппроксимация должна включать половину prev_count в итоговый счёт (проверить через `remaining`)
  - `test_overflow_evicts_stale_entries_and_allows_new_ip` — заполнить store до `max_ips` записями с истёкшим window; check нового IP возвращает `:allowed`; `store.size <= max_ips`
  - `test_overflow_fail_open_when_all_entries_active` — заполнить store до `max_ips` активными записями; check нового IP возвращает `:untracked`
  - `test_first_block_logs_warn_once_per_window` — при превышении лимита `Rails.logger` получает ровно один вызов `warn` с упоминанием IP (использовать `expects(:warn).once`)
  - `test_subsequent_denials_do_not_duplicate_log` — при 5 запросах сверх лимита `logger.warn` вызывается один раз (не пять)
  - `test_clear_empties_store` — добавить записи, вызвать `Redmine::RateLimit.reset_store!`, `store.size == 0`
  - `test_check_returns_reset_at_as_integer` — `reset_at` в результате — целое число (Unix timestamp)
  - `test_check_returns_retry_after_positive` — при `:denied` `reset_at > Time.now.to_i`

### Реализация Foundation

- [ ] T004 Создать `lib/redmine/rate_limit.rb` — модуль `Redmine::RateLimit` с внутренним классом `Redmine::RateLimit::Store`. GPL-заголовок, `frozen_string_literal: true`. Store: `Hash<String, Struct(prev_count, curr_count, window_start, logged_this_window)>`, защищён `@mutex = Mutex.new`. Метод `check_and_record(ip, max_requests, period)`: (1) рассчитать `elapsed = now - window_start`; если `elapsed >= period` — сдвинуть окно (`prev = curr, curr = 0, window_start += period`); (2) аппроксимировать `approx = prev_count * ((period - elapsed) / period.to_f) + curr_count`; (3) если `approx >= max_requests` — вернуть `denied`; (4) при создании новой записи: если `size >= max_ips` — очистить стейлы; если всё ещё полно — вернуть `untracked` + `Rails.logger.warn`; (5) инкрементировать `curr_count`; вернуть `allowed` с `remaining` и `reset_at`. Публичный интерфейс модуля: `check(ip)` → Hash, `reset_store!(max_size:)` → new Store, `enabled?` → `Setting.api_rate_limiting_enabled?`

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/unit/lib/redmine/rate_limit_test.rb` — все 13 тестов проходят.

---

## Phase 3: US1, US4, US5 — Применение Rate Limiting в API

**Цель**: блокировка перебора токенов, корректная работа при лимите, прозрачность при выключенном функционале.

**Независимое тестирование**: отправить серию запросов к `/issues.json` с разными токенами; после N+1 запросов получить 429; выключить — получать 200.

### Тесты US1 / US4 / US5 ⚠️ Написать первыми

- [ ] T005 [P] Написать integration-тесты в `test/integration/api_test/rate_limiting_test.rb`. Класс `Redmine::ApiTest::RateLimitingTest < Redmine::ApiTest::Base`. GPL-заголовок, `frozen_string_literal: true`. В `setup`: `Setting.api_rate_limiting_enabled = '0'`; `Redmine::RateLimit.reset_store!`. В `teardown`: `Setting.api_rate_limiting_enabled = '0'`; `Redmine::RateLimit.reset_store!`. Использовать фикстуру пользователя `jsmith` / пароль `jsmith` для аутентифицированных запросов. Тест-кейсы:

  **US5 — Выключено по умолчанию:**
  - `test_rate_limiting_disabled_by_default_returns_200` — `Setting.api_rate_limiting_enabled = '0'`; 5 запросов `GET /issues.json`; все возвращают 200
  - `test_rate_limiting_disabled_no_ratelimit_headers` — при disabled ответ не содержит заголовков `X-RateLimit-*` и `Retry-After`

  **US4 — Нормальная работа:**
  - `test_within_limit_returns_200_with_ratelimit_headers` — enabled=1, max=10, period=60; 3 запроса `GET /issues.json`; каждый возвращает 200; ответ содержит `X-RateLimit-Limit: 10`, `X-RateLimit-Remaining` убывает (9, 8, 7), `X-RateLimit-Reset` — положительный timestamp
  - `test_xml_format_also_has_ratelimit_headers` — enabled=1; `GET /issues.xml`; 200; заголовки `X-RateLimit-*` присутствуют (Принцип V — оба формата)

  **US1 — Блокировка:**
  - `test_exceeding_limit_returns_429` — enabled=1, max=3, period=60; 3 запроса; 4-й возвращает 429
  - `test_429_response_includes_retry_after_header` — при превышении заголовок `Retry-After` присутствует и является положительным целым числом
  - `test_429_body_is_neutral_does_not_reveal_token_validity` — отправить два запроса сверх лимита: один с некорректным токеном (`X-Redmine-API-Key: invalid`), один с корректным; тела ответов 429 идентичны (FR-011)
  - `test_valid_token_still_gets_429_when_limit_exceeded` — превысить лимит с корректным токеном jsmith; следующий запрос с тем же токеном получает 429 (блокировка не снимается для верного токена — US1 сценарий 3)
  - `test_non_api_html_requests_are_not_rate_limited` — enabled=1, max=1, period=60; выполнить 5 запросов `GET /login` (HTML, без формата); все возвращают 200 (FR-008 — только API)
  - `test_rate_limit_resets_after_window_expires` — enabled=1, max=3, period=60; превысить лимит; `now = Time.now`; `Time.stubs(:now).returns(now + 61)`; следующий запрос возвращает 200 (**захват `now` до стаба**)
  - `test_rate_limit_applies_to_real_ip_from_x_forwarded_for` — enabled=1, max=2, period=60; отправить запрос `GET /issues.json` с заголовком `X-Forwarded-For: 203.0.113.42`; убедиться что ответ 200 и `X-RateLimit-Remaining` присутствует; повторить ещё 2 запроса с тем же `X-Forwarded-For` — третий получает 429 (FR-007: `request.remote_ip` корректно извлекает реальный IP из `X-Forwarded-For`)

### Реализация US1 / US4 / US5

- [ ] T006 [US1] Добавить в `app/controllers/application_controller.rb`: (1) `prepend_before_action :check_api_rate_limit` в начало цепочки; (2) приватный метод `check_api_rate_limit`: вернуть если `!api_request?`; вызвать `result = Redmine::RateLimit.check(request.remote_ip)`; при `:disabled` или `:untracked` — вернуть; установить заголовки `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` в `response.headers`; при `:denied` — установить `Retry-After`, вызвать `render_error :status => 429, :message => :error_rate_limit_exceeded`

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/integration/api_test/rate_limiting_test.rb` — все 11 тестов проходят.

---

## Phase 4: US2 — Административное управление настройками

**Цель**: администратор включает/настраивает rate limiting через `/admin/settings?tab=api`; изменение настроек сбрасывает счётчики.

**Независимое тестирование**: зайти в `/admin/settings?tab=api`; включить rate limiting; задать max=50, period=60; сохранить; убедиться, что поля сохранились.

### Тесты US2 ⚠️ Написать первыми

- [ ] T007 [P] [US2] Добавить тест-кейсы в `test/functional/settings_controller_test.rb` (в существующий класс `SettingsControllerTest < Redmine::ControllerTest`). В `setup` тестов ниже: `Redmine::RateLimit.reset_store!`. Тест-кейсы:
  - `test_api_tab_shows_rate_limiting_fields` — `get :edit, params: {tab: 'api'}`; `assert_response :success`; `assert_select 'input[name="settings[api_rate_limiting_enabled]"]'`; `assert_select 'input[name="settings[api_rate_limit_max_requests]"]'`; `assert_select 'input[name="settings[api_rate_limit_period]"]'`; `assert_select 'input[name="settings[api_rate_limit_max_ips]"]'`
  - `test_save_rate_limit_settings_updates_values` — `post :edit, params: {tab: 'api', settings: {api_rate_limiting_enabled: '1', api_rate_limit_max_requests: '50', api_rate_limit_period: '120', api_rate_limit_max_ips: '5000'}}`; `assert_redirected_to`; `assert_equal '1', Setting.api_rate_limiting_enabled`; `assert_equal 50, Setting.api_rate_limit_max_requests`
  - `test_save_invalid_max_requests_shows_error` — `post :edit, params: {settings: {api_rate_limiting_enabled: '1', api_rate_limit_max_requests: '0', api_rate_limit_period: '60'}}`; `assert_response :success` (форма перерендерена); ответ содержит сообщение об ошибке валидации
  - `test_save_invalid_period_shows_error` — `post :edit, params: {settings: {api_rate_limiting_enabled: '1', api_rate_limit_max_requests: '100', api_rate_limit_period: '0'}}`; `assert_response :success`; ответ содержит сообщение об ошибке валидации (FR-010: period > 0)
  - `test_save_invalid_max_ips_shows_error` — `post :edit, params: {settings: {api_rate_limiting_enabled: '1', api_rate_limit_max_requests: '100', api_rate_limit_period: '60', api_rate_limit_max_ips: '0'}}`; `assert_response :success`; ответ содержит сообщение об ошибке валидации (FR-013: max_ips > 0)
  - `test_save_rate_limit_settings_resets_store` — наполнить store; `post :edit ...`; `assert_equal 0, Redmine::RateLimit.store_size`

### Реализация US2

- [ ] T008 [US2] Добавить в `app/views/settings/_api.html.erb` секцию rate limiting: `<p><%= setting_check_box :api_rate_limiting_enabled %></p>`; `<p><%= setting_text_field :api_rate_limit_max_requests, size: 6 %></p>`; `<p><%= setting_text_field :api_rate_limit_period, size: 6 %></p>`; `<p><%= setting_text_field :api_rate_limit_max_ips, size: 8 %></p>` — внутри существующего `div.box.tabular.settings`

- [ ] T009 [US2] Добавить сброс хранилища счётчиков при сохранении настроек rate limiting: в `app/controllers/settings_controller.rb` в методе `edit` (ветка `post`) — после вызова `Setting.set_all_from_params` проверить, изменились ли ключи `api_rate_limit_*`; если да — вызвать `Redmine::RateLimit.reset_store!(max_size: Setting.api_rate_limit_max_ips)`. Добавить валидацию: `api_rate_limit_max_requests > 0`, `api_rate_limit_period > 0`, `api_rate_limit_max_ips > 0` — при нарушении перерендерить форму с `flash[:error]`.

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/functional/settings_controller_test.rb` — новые тесты проходят.

---

## Phase 5: US6 — Потокобезопасность

**Цель**: параллельные запросы с одного IP не позволяют получить больше разрешённого числа ответов 200.

**Независимое тестирование**: отправить N+10 конкурентных запросов при лимите N — ровно N получают 200, остальные 429.

### Тест US6 ⚠️ Написать первым

- [ ] T010 [US6] Добавить тест `test_concurrent_requests_do_not_exceed_limit` в `test/unit/lib/redmine/rate_limit_test.rb`: `max = 10`; запустить 20 потоков (`Thread.new { Redmine::RateLimit.check('10.0.0.1') }`), дождаться все (`threads.each(&:join)`); посчитать результаты `:allowed` и `:denied`; `assert_equal max, allowed_count`; `assert_equal 10, denied_count`. Тест проверяет, что Mutex не даёт обойти лимит через параллельность.

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/unit/lib/redmine/rate_limit_test.rb` — все 14 тестов проходят (13 из T003 + 1 из T010).

---

## Phase 6: Polish & Cross-Cutting

**Цель**: финальная проверка, документация, убедиться что всё собирается.

- [ ] T011 [P] Убедиться что в `lib/redmine/rate_limit.rb` присутствуют: `# frozen_string_literal: true` (первая строка) и GPL-заголовок (строки 2–17) по образцу любого файла из `lib/redmine/`

- [ ] T012 Запустить полный набор тестов трёх уровней и убедиться, что все проходят:
  ```
  docker compose exec test bundle exec rake test TEST=test/unit/lib/redmine/rate_limit_test.rb
  docker compose exec test bundle exec rake test TEST=test/functional/settings_controller_test.rb
  docker compose exec test bundle exec rake test TEST=test/integration/api_test/rate_limiting_test.rb
  ```
  Проверить отсутствие регрессий в `test/integration/api_test/authentication_test.rb` (rate limiting не должен ломать существующую аутентификацию).

- [ ] T013 [P] Проверить quickstart.md — выполнить шаги вручную или через Docker: включить rate limiting в admin UI, выполнить curl-команды из quickstart, убедиться что заголовки и 429 выглядят как ожидается; при обнаружении несоответствий — обновить quickstart.md

---

## Зависимости и порядок выполнения

### Зависимости фаз

- **Phase 1 (Setup)**: без зависимостей — можно начать сразу
- **Phase 2 (Foundation)**: зависит от Phase 1 — блокирует все остальные
- **Phase 3 (US1/US4/US5)**: зависит от Phase 2
- **Phase 4 (US2)**: зависит от Phase 2; можно параллельно с Phase 3
- **Phase 5 (US6)**: зависит от Phase 2; можно параллельно с Phase 3 и Phase 4
- **Phase 6 (Polish)**: зависит от Phase 3, 4, 5

### Внутри каждой фазы

- Тесты пишутся **до** реализации — убедиться что падают
- Модели/модули **до** интеграционного слоя
- Контроллер **после** модуля

### Параллельные возможности

```
Phase 1:    T001 + T002 [P] — одновременно
Phase 2:    T003 → T004 (последовательно, TDD)
Phase 3,4,5: после завершения Phase 2:
              T005 [P] + T007 [P] + T010 — одновременно (разные файлы)
              Затем T006 | T008 + T009 (реализации под тесты)
Phase 6:    T011 [P] + T013 [P] одновременно; T012 после всех
```

---

## Стратегия реализации

### MVP (только Phase 1 + 2 + 3)

1. Завершить Phase 1 (Setup)
2. Завершить Phase 2 (Store + unit tests)
3. Завершить Phase 3 (ApplicationController + integration tests)
4. **Стоп и проверка**: rate limiting работает, 429 возвращается, тесты зелёные
5. Деплой/демо возможны — базовая защита активна

### Полная реализация

1. Phase 1 → Phase 2 → Phase 3 (MVP, ~40% задач)
2. Phase 4 (admin UI) → функция полностью управляема
3. Phase 5 (thread safety test) → формальное подтверждение потокобезопасности
4. Phase 6 (polish) → готово к merge

---

## Примечания

- `[P]` = разные файлы, нет зависимостей между задачами
- TDD: тесты пишутся до реализации, проверяются как падающие
- **Важно про Mocha**: всегда захватывать `now = Time.now` **до** `Time.stubs(:now)` — стаб активируется немедленно
- `Redmine::RateLimit.reset_store!` вызывать в `setup` всех тестов, работающих со store, для изоляции
- Fixtures достаточно для тестов — пользователь `jsmith` (id=2) присутствует в `test/fixtures/users.yml`
