# Data Model: Rate Limiting

**Date**: 2026-05-28

---

## Stored Entities

### 1. Rate Limiting Settings

Stored in the `settings` table via Redmine's standard mechanism. No new migration required.

| Key (`name`) | Type | Default | Description |
|---|---|---|---|
| `api_rate_limiting_enabled` | boolean (0/1) | `0` | Enable/disable rate limiting |
| `api_rate_limit_max_requests` | integer | `300` | Maximum requests per period |
| `api_rate_limit_period` | integer (seconds) | `300` | Sliding window length |
| `api_rate_limit_max_ips` | integer | `10_000` | Maximum tracked IPs |

**Validation** (at `Setting.validate_all_from_params` level):
- `api_rate_limit_max_requests` > 0
- `api_rate_limit_period` > 0
- `api_rate_limit_max_ips` > 0

**Access**: `Setting.api_rate_limiting_enabled?`, `Setting.api_rate_limit_max_requests`, `Setting.api_rate_limit_period`, `Setting.api_rate_limit_max_ips`

---

### 2. Counter Store (`Redmine::RateLimit::Store`)

Exclusively in-memory, no persistence. Lives in the class-level variable `Redmine::RateLimit.store`.

**Structure**:
```
Hash<String, IPRecord>
  key   → IP address (String, e.g. "192.168.1.1", "2001:db8::1")
  value → IPRecord
```

**IPRecord** (in-memory structure):

| Field | Type | Description |
|---|---|---|
| `prev_count` | `Integer` | Number of requests in the previous completed window |
| `curr_count` | `Integer` | Number of requests in the current window (since `window_start`) |
| `window_start` | `Float` | Unix timestamp of the start of the current window |
| `logged_this_window` | `Boolean` | Flag: whether a warn event has been recorded for a block in the current window |

**Sliding window approximation algorithm** (on every request):
```
elapsed     = now - window_start
if elapsed >= period            # window shift
  windows_passed  = (elapsed / period).floor
  prev_count      = windows_passed >= 2 ? 0 : curr_count
  curr_count      = 0
  window_start   += windows_passed * period
  elapsed         = now - window_start
end
weight_prev   = (period - elapsed) / period
approx_count  = prev_count * weight_prev + curr_count
```

**Store invariants**:
- Each IPRecord contains exactly 4 fields; no growing collections
- `hash.size <= api_rate_limit_max_ips`
- Access is always protected by `Mutex`

**Lifecycle**:
- **Created**: on the first request from a new IP (`prev_count = 0`, `curr_count = 1`, `window_start = now`)
- **Updated**: on every request — shift the window if needed, then increment `curr_count`
- **Partially evicted**: stale IP records are deleted when `max_ips` is reached (a record is "stale" if its approximated `approx_count == 0`)
- **Fully reset**: when the administrator saves rate limiting settings

---

## IP Counter State Diagram

```
[No record]
     │ first request
     ▼
[Active: approx_count < max_requests]
     │ request within limit
     ▼ (stays in same state, curr_count grows)
     │ request exceeds limit
     ▼
[Blocked: approx_count >= max_requests]
     │ requests rejected (429)
     │ window expires
     ▼
[Active: window shifted, approx_count decreased]
```

```
[Any state]
     │ administrator saves settings
     ▼
[All records deleted → No record for all IPs]
```

---

## Performance Parameters

| Parameter | Value | Rationale |
|---|---|---|
| Memory per IP record | ~24 bytes (constant) | 2 Integer + 1 Float + 1 Boolean |
| Maximum memory | 24 × 10_000 = **~240 KB** | At default settings |
| Check time | O(1) | Only arithmetic, no iteration |
| Mutex contention | Minimal | Lock held < 10 µs |
