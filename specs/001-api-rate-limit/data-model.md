# Модель данных: Rate Limiting

**Дата**: 2026-05-28

---

## Хранимые сущности

### 1. Настройки rate limiting (Settings)

Хранятся в таблице `settings` через стандартный механизм Redmine. Не требуют новой миграции.

| Ключ (`name`) | Тип | Дефолт | Описание |
|---|---|---|---|
| `api_rate_limiting_enabled` | boolean (0/1) | `0` | Включить/выключить rate limiting |
| `api_rate_limit_max_requests` | integer | `300` | Максимум запросов за период |
| `api_rate_limit_period` | integer (секунды) | `300` | Длина скользящего окна |
| `api_rate_limit_max_ips` | integer | `10_000` | Максимум отслеживаемых IP |

**Валидация** (на уровне `SettingsController`/`Setting.validate_all_from_params`):
- `api_rate_limit_max_requests` > 0
- `api_rate_limit_period` > 0
- `api_rate_limit_max_ips` > 0

**Доступ**: `Setting.api_rate_limiting_enabled?`, `Setting.api_rate_limit_max_requests`, `Setting.api_rate_limit_period`, `Setting.api_rate_limit_max_ips`

---

### 2. Хранилище счётчиков (`Redmine::RateLimit::Store`)

Исключительно in-memory, нет персистентности. Живёт в классовой переменной `Redmine::RateLimit.store`.

**Структура**:
```
Hash<String, IPRecord>
  key   → IP-адрес (String, e.g. "192.168.1.1", "2001:db8::1")
  value → IPRecord
```

**IPRecord** (структура в памяти):

| Поле | Тип | Описание |
|---|---|---|
| `prev_count` | `Integer` | Число запросов в предыдущем завершённом окне |
| `curr_count` | `Integer` | Число запросов в текущем окне (с момента `window_start`) |
| `window_start` | `Float` | Unix timestamp начала текущего окна |
| `logged_this_window` | `Boolean` | Флаг: было ли записано warn-событие блокировки в текущем окне |

**Алгоритм аппроксимации скользящего окна** (при каждом запросе):
```
elapsed     = now - window_start
if elapsed >= period            # сдвиг окна
  prev_count  = curr_count
  curr_count  = 0
  window_start += period
  elapsed     = now - window_start
end
weight_prev   = (period - elapsed) / period
approx_count  = prev_count * weight_prev + curr_count
```

**Инварианты хранилища**:
- Каждая IPRecord содержит ровно 4 поля; нет растущих коллекций
- `hash.size <= api_rate_limit_max_ips`
- Доступ всегда защищён `Mutex`

**Жизненный цикл**:
- **Создаётся**: при первом запросе с нового IP (`prev_count = 0`, `curr_count = 1`, `window_start = now`)
- **Обновляется**: при каждом запросе — сдвиг окна если нужен, затем инкремент `curr_count`
- **Очищается частично**: устаревшие IP-записи удаляются при достижении `max_ips` (запись «устаревшая», если аппроксимированный `approx_count == 0`)
- **Сбрасывается полностью**: при сохранении настроек rate limiting администратором

---

## Диаграмма состояний счётчика IP

```
[Нет записи]
     │ первый запрос
     ▼
[Активен: timestamps.size < max_requests]
     │ запрос в пределах лимита
     ▼ (остаётся в том же состоянии, timestamps растёт)
     │ запрос превышает лимит
     ▼
[Заблокирован: timestamps.size >= max_requests]
     │ запросы отклоняются (429)
     │ время окна истекает
     ▼
[Активен: timestamps очищены, размер < max_requests]
```

```
[Любое состояние]
     │ администратор сохраняет настройки
     ▼
[Все записи удалены → Нет записи для всех IP]
```

---

## Параметры производительности

| Параметр | Значение | Обоснование |
|---|---|---|
| Память на IP-запись | ~24 байта (константа) | 2 Integer + 1 Float + 1 Boolean |
| Максимальная память | 24 × 10_000 = **~240 КБ** | При дефолтных настройках |
| Время проверки | O(1) | Только арифметика, нет итерации |
| Mutex contention | Минимальное | Удержание < 10 мкс |
