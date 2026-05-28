# Contract: Rate Limiting HTTP Headers

**Scope**: all API requests (`params[:format]` = `json` or `xml`) when rate limiting is enabled.

---

## Headers in a Successful Response (limit not exceeded)

Present in every API response when rate limiting is enabled.

| Header | Type | Example | Description |
|---|---|---|---|
| `X-RateLimit-Limit` | Integer | `300` | Maximum number of requests per period |
| `X-RateLimit-Remaining` | Integer | `247` | Remaining requests in the current sliding window |
| `X-RateLimit-Reset` | Unix timestamp (Integer) | `1748390700` | Time (UTC) when the earliest request in the window will exit the window and the counter will decrease |

**Example response**:
```http
HTTP/1.1 200 OK
Content-Type: application/json
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 247
X-RateLimit-Reset: 1748390700
```

---

## Headers in a 429 Response (limit exceeded)

| Header | Type | Example | Description |
|---|---|---|---|
| `X-RateLimit-Limit` | Integer | `300` | Maximum number of requests per period |
| `X-RateLimit-Remaining` | Integer | `0` | Always 0 when the limit is exceeded |
| `X-RateLimit-Reset` | Unix timestamp (Integer) | `1748390700` | Reset time (when the oldest request exits the window) |
| `Retry-After` | Integer (seconds) | `42` | How many seconds until the client can retry |

**Example response**:
```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1748390700
Retry-After: 42
```

**Response body (JSON)**:
```json
{"errors":["Rate limit exceeded. Please try again later."]}
```

**Response body (XML)**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<errors>
  <error>Rate limit exceeded. Please try again later.</error>
</errors>
```

**Body invariants**:
- The body MUST NOT contain information about the validity of the token (FR-011)
- The body is identical for requests with a valid and an invalid token when the limit is exceeded
- The body is localised via the I18n key `error_rate_limit_exceeded`

---

## Behaviour When Rate Limiting Is Disabled

| Header | Present |
|---|---|
| `X-RateLimit-*` | No |
| `Retry-After` | No |

---

## Computing `X-RateLimit-Reset` and `Retry-After`

Using the two-counter sliding window approximation:
- `reset_at` = start of the next window = `window_start + period`
- `retry_after` = `reset_at - Time.now.to_i` (seconds until the new window begins)

```
reset_at    = ceil(window_start + period)
retry_after = max(1, reset_at - now)   # at least 1 second
```

---

## Formula for `X-RateLimit-Remaining`

```
elapsed     = now - window_start
weight_prev = (period - elapsed) / period
approx      = prev_count * weight_prev + curr_count
remaining   = max(0, max_requests - floor(approx))
```

When the limit is exceeded, `remaining = 0` (never negative).
