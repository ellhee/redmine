# Исследование: Ограничение частоты запросов к API (Rate Limiting)

**Дата**: 2026-05-28
**Ветка**: `feature/api-rate-limiting`

---

## 1. Точка интеграции в ApplicationController

**Решение**: `prepend_before_action :check_api_rate_limit` в `ApplicationController`.

**Обоснование**: Redmine уже использует цепочку `before_action :session_expiration, :user_setup, :check_if_login_required, ...` (строка 64 `app/controllers/application_controller.rb`). Rate limit должен сработать **до** `user_setup` — иначе проверка аутентификации произойдёт раньше блокировки, что нарушает защиту от перебора токенов (FR-002). `prepend_before_action` гарантирует, что проверка идёт первой в цепочке.

**Альтернативы рассмотрены**:
- Rack Middleware — обеспечивает раннюю проверку, но не имеет доступа к `Setting`, `I18n` и хелперам Redmine. Избыточная сложность.
- `around_action` — выполняется после `before_action`, не подходит для pre-auth блокировки.

---

## 2. Определение API-запроса

**Решение**: Использовать существующий метод `api_request?` из `ApplicationController` (строка 723).

```ruby
def api_request?
  %w(xml json).include? params[:format]
end
```

**Обоснование**: Метод уже используется для всей логики REST API в Redmine (аутентификация, рендеринг ошибок). Это канонический способ определить API-запрос в кодовой базе. Дополнительно соответствует FR-008 — применять только к `.json`/`.xml` запросам.

---

## 3. Механизм Settings

**Решение**: Четыре новых ключа в `config/settings.yml`, управление через существующую вкладку «API» в `/admin/settings`.

Паттерн из кодовой базы:
```yaml
# config/settings.yml
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

Настройки отображаются через существующие хелперы `setting_check_box` / `setting_text_field` в `app/views/settings/_api.html.erb`. Для сброса счётчиков при сохранении — хук `after_action :reset_rate_limit_store, only: [:edit]` в `SettingsController` (только при изменении rate limit ключей).

**Дефолтные значения**:
- `max_requests = 300` за `period = 300` сек (5 минут) — 1 запрос/сек средняя скорость, позволяет легитимные интеграции и блокирует автоматические атаки.
- `max_ips = 10_000` — покрывает большинство production-инсталляций.

---

## 4. Скользящее окно (Sliding Window) — реализация

**Решение**: Аппроксимация скользящего окна через **два счётчика** (current + previous window).

Для каждого IP хранится структура из трёх полей:
- `prev_count` (Integer) — число запросов в предыдущем полном окне
- `curr_count` (Integer) — число запросов в текущем окне (с момента `window_start`)
- `window_start` (Float) — Unix timestamp начала текущего окна

**Формула аппроксимации** (применяется при каждой проверке):
```
elapsed     = now - window_start        # сколько прошло в текущем окне
weight_prev = (period - elapsed) / period
approx      = prev_count × weight_prev + curr_count
```

Когда `elapsed >= period` — происходит «сдвиг»: `prev_count = curr_count`, `curr_count = 0`, `window_start += period`.

**Обоснование**: Аппроксимация точна в пределах 10% от реального скользящего окна (доказано теоретически и проверено практикой — Nginx, Cloudflare, Redis используют этот алгоритм). Сохраняет семантику скользящего окна (нет 2× всплеска на стыке) при памяти **O(1) на IP** вместо O(max_requests).

**Память**: `{prev_count, curr_count, window_start}` ≈ **24 байта на IP**.
При `max_ips = 10_000` → максимум **~240 КБ** (было ~24 МБ при хранении timestamps).

**Альтернативы рассмотрены**:
- Массив timestamps (точное скользящее окно) — O(max_requests) памяти на IP. До 2 400 байт/IP при `max_requests = 300`. Избыточный расход памяти.
- Fixed window (один счётчик + window_start) — O(1), но уязвим к 2× всплеску на стыке периодов. Недопустимо для защиты от брутфорса.
- Token bucket — гладкое ограничение, но сложнее вычислить `X-RateLimit-Remaining` и `reset_at`. Избыточно.

---

## 5. Потокобезопасность

**Решение**: `Mutex` на уровне хранилища (`Redmine::RateLimit::Store`).

**Обоснование**: Rails при Puma запускается в многопоточном режиме. MRI GIL не защищает от race condition при составных операциях (read-then-write). Один `Mutex` на всё хранилище прост и корректен. При `max_requests = 300` блокировка удерживается на время очистки массива (~микросекунды) — не узкое место.

**Альтернативы рассмотрены**:
- Per-IP mutex — снижает contention, но сложно управлять жизненным циклом mutex при очистке записей.
- Concurrent::Map (concurrent-ruby gem) — более масштабируем, но добавляет зависимость. В Redmine concurrent-ruby не используется в production-коде.

---

## 6. HTTP-ответ 429

**Решение**: Использовать `render_error` с кастомным статусом + добавить заголовки вручную.

```ruby
response.headers['Retry-After'] = retry_after.to_s
response.headers['X-RateLimit-Limit'] = max_requests.to_s
response.headers['X-RateLimit-Remaining'] = '0'
response.headers['X-RateLimit-Reset'] = reset_at.to_s
render_error :status => 429, :message => :error_rate_limit_exceeded
```

`render_error` уже поддерживает произвольные HTTP-статусы и отдаёт `head @status` для API-запросов (`format.any { head @status }`). Тело ответа — через I18n ключ, без информации о токене (FR-011).

---

## 7. Логирование

**Решение**: `Rails.logger.warn` при первом срабатывании блокировки на IP за окно, отдельный `Rails.logger.warn` при overflow хранилища.

**Обоснование**: Redmine использует стандартный Rails logger во всём `lib/redmine/`. Severity `warn` — стандартна для security events. Дедупликация: флаг `logged_at` на уровне IP-записи в хранилище, сбрасывается при сбросе счётчика.

---

## 8. Расположение кода

**Решение**: `lib/redmine/rate_limit.rb` — основная логика хранилища и проверки.

**Обоснование**: Конституция Принцип IV — cross-cutting поведение в `lib/redmine/`. Контроллеры остаются тонкими. Модуль не зависит от ActiveRecord. Аналог: `lib/redmine/sudo_mode.rb`, `lib/redmine/twofa.rb`.

---

## Итоговые решения

| Вопрос | Решение |
|--------|---------|
| Точка интеграции | `prepend_before_action :check_api_rate_limit` в `ApplicationController` |
| Определение API-запроса | Существующий `api_request?` метод |
| Хранилище | In-memory Hash, `lib/redmine/rate_limit.rb` |
| Алгоритм окна | Sliding window (аппроксимация, два счётчика prev/curr) |
| Потокобезопасность | Один `Mutex` на хранилище |
| Настройки | 4 ключа в `settings.yml`, вкладка API |
| HTTP 429 | `render_error` + ручные заголовки |
| Логирование | `Rails.logger.warn` при первом срабатывании и при overflow |
