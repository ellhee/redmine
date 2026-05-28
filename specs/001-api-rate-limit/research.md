# Research: API Rate Limiting

**Date**: 2026-05-28
**Branch**: `feature/api-rate-limiting`

---

## 1. Integration Point in ApplicationController

**Decision**: `prepend_before_action :check_api_rate_limit` in `ApplicationController`.

**Rationale**: Redmine already uses a `before_action` chain of `session_expiration, user_setup, check_if_login_required, ...` (line 64 of `app/controllers/application_controller.rb`). The rate limit check must fire **before** `user_setup` — otherwise authentication would happen before blocking, which breaks token brute-force protection (FR-002). `prepend_before_action` guarantees the check runs first in the chain.

**Alternatives considered**:
- Rack Middleware — provides early checking but has no access to `Setting`, `I18n`, or Redmine helpers. Excessive complexity.
- `around_action` — runs after `before_action`, unsuitable for pre-auth blocking.

---

## 2. Identifying an API Request

**Decision**: Use the existing `api_request?` method from `ApplicationController` (line 723).

```ruby
def api_request?
  %w(xml json).include? params[:format]
end
```

**Rationale**: This method is already used for all REST API logic in Redmine (authentication, error rendering). It is the canonical way to identify an API request in the codebase. Also directly satisfies FR-008 — apply only to `.json`/`.xml` requests.

---

## 3. Settings Mechanism

**Decision**: Four new keys in `config/settings.yml`, managed through the existing "API" tab at `/admin/settings`.

Pattern from the codebase:
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

Settings are displayed via the existing `setting_check_box` / `setting_text_field` helpers in `app/views/settings/_api.html.erb`. To reset counters on save — the `SettingsController#edit` action calls `Redmine::RateLimit.reset_store!` when any `api_rate_limit_*` key is present in the submitted params.

**Default values**:
- `max_requests = 300` per `period = 300` seconds (5 minutes) — 1 request/second average rate, allows legitimate integrations and blocks automated attacks.
- `max_ips = 10_000` — covers most production installations.

---

## 4. Sliding Window — Implementation

**Decision**: Sliding window approximation via **two counters** (current + previous window).

For each IP the following structure is stored:
- `prev_count` (Integer) — number of requests in the previous completed window
- `curr_count` (Integer) — number of requests in the current window (since `window_start`)
- `window_start` (Float) — Unix timestamp of the start of the current window

**Approximation formula** (applied on every check):
```
elapsed     = now - window_start        # how much time has passed in the current window
weight_prev = (period - elapsed) / period
approx      = prev_count × weight_prev + curr_count
```

When `elapsed >= period` — a "shift" occurs: `prev_count = curr_count`, `curr_count = 0`, `window_start += period`.

**Rationale**: The approximation is accurate to within 10% of a true sliding window (proven theoretically and confirmed in practice — Nginx, Cloudflare, and Redis use this algorithm). It preserves sliding window semantics (no 2× burst at boundaries) with **O(1) memory per IP** instead of O(max_requests).

**Memory**: `{prev_count, curr_count, window_start}` ≈ **24 bytes per IP**.
With `max_ips = 10_000` → maximum **~240 KB** (vs ~24 MB when storing timestamps).

**Alternatives considered**:
- Array of timestamps (exact sliding window) — O(max_requests) memory per IP. Up to 2,400 bytes/IP at `max_requests = 300`. Excessive memory usage.
- Fixed window (one counter + window_start) — O(1), but vulnerable to 2× burst at period boundaries. Unacceptable for brute-force protection.
- Token bucket — smooth limiting, but harder to compute `X-RateLimit-Remaining` and `reset_at`. Excessive complexity.

---

## 5. Thread Safety

**Decision**: `Mutex` at the store level (`Redmine::RateLimit::Store`).

**Rationale**: Rails under Puma runs in multi-threaded mode. MRI GIL does not protect against race conditions in compound operations (read-then-write). A single `Mutex` across the entire store is simple and correct. With `max_requests = 300`, the lock is held for the duration of counter arithmetic (~microseconds) — not a bottleneck.

**Alternatives considered**:
- Per-IP mutex — reduces contention, but managing mutex lifecycle during eviction is complex.
- Concurrent::Map (concurrent-ruby gem) — more scalable, but adds a dependency. concurrent-ruby is not used in Redmine production code.

---

## 6. HTTP 429 Response

**Decision**: Explicit `respond_to` block with JSON/XML rendering + manual header setting.

```ruby
response.headers['Retry-After']           = retry_after.to_s
response.headers['X-RateLimit-Limit']     = Setting.api_rate_limit_max_requests.to_s
response.headers['X-RateLimit-Remaining'] = '0'
response.headers['X-RateLimit-Reset']     = reset_at.to_s
message = l(:error_rate_limit_exceeded)
respond_to do |format|
  format.json { render :json => {:errors => [message]}, :status => :too_many_requests }
  format.xml  { render :xml  => {:error => message}.to_xml(:root => 'errors'), :status => :too_many_requests }
end
```

`render_error` was not used because it returns `head @status` for API requests (no response body). The explicit `respond_to` block produces a proper JSON/XML error body per the contract (FR-011).

---

## 7. Logging

**Decision**: `logger.warn` (called from `ApplicationController`) on the first block trigger for an IP per window; a separate `logger.warn` on store overflow.

**Rationale**: `RateLimit::Store` returns a `log:` key in its result hash (`:blocked` or `:overflow`); the caller (`check_api_rate_limit`) is responsible for the actual log call. This keeps `lib/redmine/rate_limit.rb` free of Rails dependencies and makes it independently testable. Deduplication: the `logged_this_window` flag on the IP record in the store, reset when the counter window slides.

---

## 8. Code Location

**Decision**: `lib/redmine/rate_limit.rb` — the main store and check logic.

**Rationale**: Constitution Principle IV — cross-cutting behaviour in `lib/redmine/`. Controllers remain thin. The module does not depend on ActiveRecord. Analogues: `lib/redmine/sudo_mode.rb`, `lib/redmine/twofa.rb`.

---

## Summary of Decisions

| Question | Decision |
|----------|----------|
| Integration point | `prepend_before_action :check_api_rate_limit` in `ApplicationController` |
| API request identification | Existing `api_request?` method |
| Store | In-memory Hash, `lib/redmine/rate_limit.rb` |
| Window algorithm | Sliding window (approximation, two counters prev/curr) |
| Thread safety | Single `Mutex` per store |
| Settings | 4 keys in `settings.yml`, API tab |
| HTTP 429 | Explicit `respond_to` + manual headers |
| Logging | `logger.warn` from controller on first trigger and on overflow; `log:` flag returned by Store |
