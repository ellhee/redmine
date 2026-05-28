# Implementation Plan: API Rate Limiting

**Branch**: `feature/api-rate-limiting` | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-api-rate-limit/spec.md`

---

## Summary

Реализовать защиту REST API Redmine от перебора токенов и массового извлечения данных с помощью IP-based rate limiting на основе скользящего окна. Ограничение управляется администратором через страницу настроек API и по умолчанию выключено. Логика хранилища счётчиков вынесена в `lib/redmine/rate_limit.rb`, интеграция — через `prepend_before_action` в `ApplicationController`.

---

## Technical Context

**Language/Version**: Ruby >= 3.2.0, < 3.5.0

**Primary Dependencies**: Rails 7.2 (ActionController, ActiveSupport); Minitest + Mocha (тесты)

**Storage**: In-memory (Hash + Mutex в классовой переменной); настройки в таблице `settings` (существующая)

**Testing**: Minitest; запуск через `docker compose exec test bundle exec rake test TEST=<path>`

**Target Platform**: Rack/Puma (многопоточный), Linux server

**Project Type**: Web-service (Rails MVC)

**Performance Goals**: Накладные расходы на проверку O(1), < 1 мс на запрос; нулевые при выключенном rate limiting

**Constraints**: Нет новых gem-зависимостей; нет миграций БД; thread-safe через Mutex

**Scale/Scope**: До 10 000 уникальных IP в памяти (дефолт); ~24 байта на IP-запись (константа)

---

## Constitution Check

*GATE: Проверка перед Phase 0. Повторная проверка после Phase 1.*

- [x] **I. Rails Conventions First** — логика в `lib/redmine/` (не в контроллере); `ApplicationController` содержит только тонкий `before_action`; все файлы с `frozen_string_literal`; GPL-заголовок.
- [x] **II. Multi-Level Test Coverage** — unit-тесты для `Redmine::RateLimit::Store` (`test/unit/lib/redmine/rate_limit_test.rb`); functional-тесты настроек (`test/functional/settings_controller_test.rb`); integration-тесты API (`test/integration/api_test/rate_limiting_test.rb`).
- [x] **III. Fixtures as Test Data Authority** — существующие fixtures достаточны; rate limit store сбрасывается в `setup` тестов.
- [x] **IV. Plugin-Based Extensibility** — вся логика в `lib/redmine/rate_limit.rb`; контроллер вызывает модуль через интерфейс. Плагины могут переопределить поведение через хук.
- [x] **V. REST API Parity** — rate limiting применяется только к API-запросам; настройки управляются через UI (CRUD через `/admin/settings`); UI-форма тестируется в functional-тестах.
- [x] **VI. Internationalization** — все строки через I18n (`error_rate_limit_exceeded`, `setting_api_rate_limiting_enabled` и др.); нет hardcoded текста в ERB.

---

## Project Structure

### Документация (эта фича)

```text
specs/001-api-rate-limit/
├── plan.md              # Этот файл
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── http-headers.md  # Phase 1
└── tasks.md             # Phase 2 (создаётся /speckit-tasks)
```

### Исходный код

```text
lib/redmine/
└── rate_limit.rb                    # Модуль: Store, алгоритм, интерфейс

app/controllers/
└── application_controller.rb        # +prepend_before_action :check_api_rate_limit
                                     # +def check_api_rate_limit (приватный)

app/views/settings/
└── _api.html.erb                    # +4 поля настроек rate limiting

config/
├── settings.yml                     # +4 ключа настроек
└── locales/
    └── en.yml                       # +I18n ключи (setting_*, error_*)

test/unit/lib/redmine/
└── rate_limit_test.rb               # Unit-тесты Store и алгоритма

test/functional/
└── settings_controller_test.rb      # +тесты сохранения rate limit настроек

test/integration/api_test/
└── rate_limiting_test.rb            # Integration API-тесты (JSON + XML)
```

**Structure Decision**: Single Rails app, стандартная Rails структура. Rate limit логика в `lib/redmine/` согласно Принципу IV.

---

## Детали реализации

### `lib/redmine/rate_limit.rb`

Публичный интерфейс модуля `Redmine::RateLimit`:

```ruby
Redmine::RateLimit.check(ip)
# => { status: :allowed,   remaining: 247, reset_at: 1748390700 }
# => { status: :denied,    remaining: 0,   reset_at: 1748390700 }
# => { status: :disabled }
# => { status: :untracked, remaining: max, reset_at: now }  # overflow
```

`Redmine::RateLimit::Store` (внутренний):
- Хранит `Hash<String, IPRecord>` где `IPRecord = Struct.new(:prev_count, :curr_count, :window_start, :logged_this_window)`
- `check_and_record(ip, max_requests, period)` — аппроксимация скользящего окна, O(1), atomic через Mutex
- `clear!` — полный сброс при смене настроек
- `size` — текущее число отслеживаемых IP
- Очистка устаревших записей при overflow: удаляются IP где `approx_count == 0`

### `ApplicationController` (изменения)

```ruby
prepend_before_action :check_api_rate_limit

private

def check_api_rate_limit
  return unless api_request?
  result = Redmine::RateLimit.check(request.remote_ip)
  return if result[:status] == :disabled || result[:status] == :untracked

  response.headers['X-RateLimit-Limit']     = Setting.api_rate_limit_max_requests.to_s
  response.headers['X-RateLimit-Remaining'] = result[:remaining].to_s
  response.headers['X-RateLimit-Reset']     = result[:reset_at].to_s

  if result[:status] == :denied
    retry_after = [result[:reset_at] - Time.now.to_i, 1].max
    response.headers['Retry-After'] = retry_after.to_s
    render_error :status => 429, :message => :error_rate_limit_exceeded
  end
end
```

### Сброс хранилища при изменении настроек

`SettingsController#edit` (after_action или observer на изменение ключей rate limit):
- При изменении любого из `api_rate_limit_*` ключей → `Redmine::RateLimit.reset_store!`

### Новые Settings ключи (`config/settings.yml`)

```yaml
api_rate_limiting_enabled:
  default: 0
  security_notifications: 1
api_rate_limit_max_requests:
  format: int
  default: 300
api_rate_limit_period:
  format: int
  default: 300
api_rate_limit_max_ips:
  format: int
  default: 10000
```

### Новые I18n ключи (`config/locales/en.yml`)

```yaml
setting_api_rate_limiting_enabled: Enable API rate limiting
setting_api_rate_limit_max_requests: Max requests per period
setting_api_rate_limit_period: Period (seconds)
setting_api_rate_limit_max_ips: Max tracked IPs
error_rate_limit_exceeded: Rate limit exceeded. Please try again later.
label_api_rate_limiting: API Rate Limiting
```

---

## Complexity Tracking

> Нет нарушений Constitution Check — раздел не заполняется.
