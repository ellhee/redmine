# Quickstart: API Rate Limiting

## Enabling via the Admin Interface

1. Log in as a Redmine administrator.
2. Open **Administration → Settings → API**.
3. Check the **Enable API rate limiting** checkbox.
4. Set the parameters:
   - **Max requests per period** — maximum number of requests (default: 300)
   - **Period (seconds)** — sliding window length (default: 300)
   - **Max tracked IPs** — counter store size (default: 10,000)
5. Click **Save**.

> ⚠️ All existing counters are reset on save.

---

## Verifying It Works

**Request within the limit:**
```sh
curl -s -u admin:admin \
  -H "Accept: application/json" \
  https://redmine.example.com/issues.json \
  -I | grep -E "X-RateLimit|HTTP"
```

Expected result:
```
HTTP/2 200
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 299
X-RateLimit-Reset: 1748390700
```

**Simulating limit exceeded (bash):**
```sh
for i in $(seq 1 310); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Accept: application/json" \
    -H "X-Redmine-API-Key: invalid_key" \
    https://redmine.example.com/issues.json
done
```

After 300 requests the response code changes to `429`.

---

## Running Tests

```sh
# All rate limiting tests
docker compose exec test bundle exec rake test \
  TEST=test/unit/lib/redmine/rate_limit_test.rb

docker compose exec test bundle exec rake test \
  TEST=test/integration/api_test/rate_limiting_test.rb
```

---

## Default Parameters and Recommendations

| Scenario | max_requests | period | Notes |
|---|---|---|---|
| Brute-force protection (strict) | 60 | 60 | 1 request/second |
| Balanced (default) | 300 | 300 | 1 request/second average |
| Legitimate integrations | 600 | 60 | 10 requests/second |

---

## Viewing Block Events in Logs

```sh
grep "RateLimit" log/production.log
# [RateLimit] Blocked 1.2.3.4 in 300s window at 2026-05-28 10:00:00
# [RateLimit] Store at capacity, skipping tracking for 5.6.7.8
```
