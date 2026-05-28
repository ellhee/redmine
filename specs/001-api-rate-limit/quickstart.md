# Быстрый старт: Rate Limiting для API

## Включение через административный интерфейс

1. Войти как администратор Redmine.
2. Открыть **Administration → Settings → API**.
3. Включить чекбокс **Enable API rate limiting**.
4. Задать параметры:
   - **Max requests per period** — максимальное число запросов (дефолт: 300)
   - **Period (seconds)** — длина скользящего окна (дефолт: 300)
   - **Max tracked IPs** — размер хранилища счётчиков (дефолт: 10 000)
5. Нажать **Save**.

> ⚠️ При сохранении все существующие счётчики сбрасываются.

---

## Проверка работы

**Запрос в пределах лимита:**
```sh
curl -s -u admin:admin \
  -H "Accept: application/json" \
  https://redmine.example.com/issues.json \
  -I | grep -E "X-RateLimit|HTTP"
```

Ожидаемый результат:
```
HTTP/2 200
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 299
X-RateLimit-Reset: 1748390700
```

**Симуляция превышения лимита (bash):**
```sh
for i in $(seq 1 310); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Accept: application/json" \
    -H "X-Redmine-API-Key: invalid_key" \
    https://redmine.example.com/issues.json
done
```

После 300 запросов ответ должен измениться на `429`.

---

## Запуск тестов

```sh
# Все тесты rate limiting
docker compose exec test bundle exec rake test \
  TEST=test/unit/lib/redmine/rate_limit_test.rb

docker compose exec test bundle exec rake test \
  TEST=test/integration/api_test/rate_limiting_test.rb
```

---

## Параметры по умолчанию и рекомендации

| Сценарий | max_requests | period | Пояснение |
|---|---|---|---|
| Защита от брутфорса (строгая) | 60 | 60 | 1 запрос/сек |
| Баланс (дефолт) | 300 | 300 | 1 запрос/сек средняя |
| Легитимные интеграции | 600 | 60 | 10 запросов/сек |

---

## Просмотр событий блокировки в логах

```sh
grep "RateLimit" log/production.log
# [RateLimit] Blocked IP 1.2.3.4: 300 requests in 300s window at 2026-05-28 10:00:00
# [RateLimit] Store at capacity (10000 entries), skipping tracking for 5.6.7.8
```
