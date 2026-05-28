# Контракт: HTTP-заголовки Rate Limiting

**Область применения**: все API-запросы (`params[:format]` = `json` или `xml`) при включённом rate limiting.

---

## Заголовки в успешном ответе (лимит не превышен)

Присутствуют в каждом API-ответе при включённом rate limiting.

| Заголовок | Тип | Пример | Описание |
|---|---|---|---|
| `X-RateLimit-Limit` | Integer | `300` | Максимальное число запросов за период |
| `X-RateLimit-Remaining` | Integer | `247` | Оставшиеся запросы в текущем скользящем окне |
| `X-RateLimit-Reset` | Unix timestamp (Integer) | `1748390700` | Время (UTC), когда самый ранний запрос в окне выйдет за его пределы и счётчик уменьшится |

**Пример ответа**:
```http
HTTP/1.1 200 OK
Content-Type: application/json
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 247
X-RateLimit-Reset: 1748390700
```

---

## Заголовки в ответе 429 (лимит превышен)

| Заголовок | Тип | Пример | Описание |
|---|---|---|---|
| `X-RateLimit-Limit` | Integer | `300` | Максимальное число запросов за период |
| `X-RateLimit-Remaining` | Integer | `0` | Всегда 0 при превышении |
| `X-RateLimit-Reset` | Unix timestamp (Integer) | `1748390700` | Время сброса (когда самый старый запрос выйдет из окна) |
| `Retry-After` | Integer (секунды) | `42` | Через сколько секунд клиент может повторить запрос |

**Пример ответа**:
```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1748390700
Retry-After: 42
```

**Тело ответа (JSON)**:
```json
{"errors":["Rate limit exceeded. Please try again later."]}
```

**Тело ответа (XML)**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<errors>
  <error>Rate limit exceeded. Please try again later.</error>
</errors>
```

**Инварианты тела**:
- Тело НЕ содержит информацию о корректности токена (FR-011)
- Тело идентично для запросов с верным и неверным токеном при превышении лимита
- Тело локализовано через I18n ключ `error_rate_limit_exceeded`

---

## Поведение при выключенном rate limiting

| Заголовок | Присутствует |
|---|---|
| `X-RateLimit-*` | Нет |
| `Retry-After` | Нет |

---

## Вычисление `X-RateLimit-Reset` и `Retry-After`

При аппроксимации скользящего окна двумя счётчиками:
- `reset_at` = начало следующего окна = `window_start + period`
- `retry_after` = `reset_at - Time.now.to_i` (секунды до начала нового окна)

```
reset_at    = ceil(window_start + period)
retry_after = max(1, reset_at - now)   # не менее 1 секунды
```

---

## Формула для `X-RateLimit-Remaining`

```
elapsed     = now - window_start
weight_prev = (period - elapsed) / period
approx      = prev_count * weight_prev + curr_count
remaining   = max(0, max_requests - floor(approx))
```

При превышении `remaining = 0` (не отрицательное).
