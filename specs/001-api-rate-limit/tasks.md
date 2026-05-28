---
description: "Implementation Tasks: API Rate Limiting"
---

# Tasks: API Rate Limiting

**Input**: `specs/001-api-rate-limit/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/ ✅

**Tests**: included at all three levels (unit, functional, integration) per explicit request. Tests are written **before** implementation — verify they fail first, then implement.

**Running tests**: `docker compose exec test bundle exec rake test TEST=<path>`

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: can be executed in parallel (different files, no dependencies)
- **[Story]**: which user story this task belongs to
- Exact file paths are required

---

## Phase 1: Setup

**Goal**: add configuration and localisation strings — without these, `Setting.api_rate_*` cannot be accessed and the UI cannot be rendered.

- [x] T001 Add 4 rate limiting settings to `config/settings.yml` after the `jsonp_enabled` block: keys `api_rate_limiting_enabled` (default: 0, security_notifications: 1), `api_rate_limit_max_requests` (format: int, default: 300), `api_rate_limit_period` (format: int, default: 300), `api_rate_limit_max_ips` (format: int, default: 10000)

- [x] T002 [P] Add I18n keys to `config/locales/en.yml`: `setting_api_rate_limiting_enabled: "Enable API rate limiting"`, `setting_api_rate_limit_max_requests: "Max requests per period"`, `setting_api_rate_limit_period: "Period (seconds)"`, `setting_api_rate_limit_max_ips: "Max tracked IPs"`, `error_rate_limit_exceeded: "Rate limit exceeded. Please try again later."`, `label_api_rate_limiting: "API Rate Limiting"`

**Checkpoint**: `Setting.api_rate_limiting_enabled?` returns false; `l(:error_rate_limit_exceeded)` returns a string.

---

## Phase 2: Foundation — Rate Limit Store

**Goal**: the core of rate limiting — a counter store with a sliding window approximation algorithm, thread-safe. All user stories depend on this phase.

> ⚠️ **TDD**: write T003 first, verify all tests fail, then implement T004.

### Foundation Tests ⚠️ Write First

- [x] T003 Write unit tests in `test/unit/lib/redmine/rate_limit_test.rb` for `Redmine::RateLimit` and `Redmine::RateLimit::Store`. The file inherits from `ActiveSupport::TestCase`, with `frozen_string_literal: true`, GPL header, `require_relative '../../test_helper'`. In `setup` call `Redmine::RateLimit.reset_store!` to isolate between tests. Test cases:
  - `test_check_returns_disabled_when_rate_limiting_is_off` — `Setting.api_rate_limiting_enabled` = 0; `Redmine::RateLimit.check('1.2.3.4')[:status]` == `:disabled`
  - `test_check_allows_request_within_limit` — enabled=1, max=5, period=60; 3 consecutive `check` calls — each returns `status: :allowed`; `remaining` decreases (4, 3, 2)
  - `test_check_denies_request_at_limit` — enabled=1, max=3, period=60; after 3 `check` calls the 4th returns `status: :denied`, `remaining: 0`
  - `test_remaining_never_goes_negative` — when the limit is exceeded `remaining` == 0, never negative
  - `test_window_slides_when_period_expires` — call `check` 3 times with `max=3`; advance time by `period + 1` using `travel_to`; the next `check` returns `:allowed` (window has shifted)
  - `test_sliding_window_weights_prev_count` — call check N times, advance time by period/2; the approximation should include half of prev_count in the total count (verify via `remaining`)
  - `test_overflow_evicts_stale_entries_and_allows_new_ip` — fill the store to `max_ips` with entries whose window has expired; check of a new IP returns `:allowed`
  - `test_overflow_fail_open_when_all_entries_active` — fill the store to `max_ips` with active entries; check of a new IP returns `:untracked` with `log: :overflow`
  - `test_first_block_signals_log_flag` — on limit exceeded the result has `log: :blocked` on the first denial in a window
  - `test_subsequent_denials_do_not_repeat_log_flag` — subsequent denials in the same window have `log: nil`
  - `test_clear_empties_store` — add entries, call `Redmine::RateLimit.reset_store!`, verify that subsequent checks return `:allowed`
  - `test_check_returns_reset_at_as_integer` — `reset_at` in the result is an Integer (Unix timestamp)
  - `test_check_returns_retry_after_positive` — when `:denied`, `reset_at > Time.now.to_i`

### Foundation Implementation

- [x] T004 Create `lib/redmine/rate_limit.rb` — the `Redmine::RateLimit` module with the internal class `Redmine::RateLimit::Store`. GPL header, `frozen_string_literal: true`. Store: `Hash<String, Struct(prev_count, curr_count, window_start, logged_this_window)>`, protected by `@mutex = Mutex.new`. Method `check_and_record(ip, max_requests, period)`: (1) calculate `elapsed = now - window_start`; if `elapsed >= period` — shift the window; (2) approximate `approx = prev_count * ((period - elapsed) / period.to_f) + curr_count`; (3) if `approx >= max_requests` — return `denied` with `log: :blocked` on the first denial per window, `log: nil` on subsequent denials; (4) when creating a new record: if `size >= max_ips` — evict stale entries; if still full — return `untracked` with `log: :overflow`; (5) increment `curr_count`; return `allowed` with `remaining` and `reset_at`. Public module interface: `check(ip)` → Hash, `reset_store!(max_size:)` → new Store, `enabled?` → `Setting.api_rate_limiting_enabled?`

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/unit/lib/redmine/rate_limit_test.rb` — all 14 tests pass.

---

## Phase 3: US1, US4, US5 — Applying Rate Limiting in the API

**Goal**: block token brute-force, correct operation within the limit, transparency when the feature is disabled.

**Independent testing**: send a series of requests to `/issues.json` with different tokens; after N+1 requests receive 429; disable — receive 200.

### Tests US1 / US4 / US5 ⚠️ Write First

- [x] T005 [P] Write integration tests in `test/integration/api_test/rate_limiting_test.rb`. Class `Redmine::ApiTest::RateLimitingTest < Redmine::ApiTest::Base`. GPL header, `frozen_string_literal: true`. In `setup`: `Setting.api_rate_limiting_enabled = '0'`; `Redmine::RateLimit.reset_store!`. In `teardown`: `Setting.api_rate_limiting_enabled = '0'`; `Redmine::RateLimit.reset_store!`. Use fixture user `jsmith` / password `jsmith` for authenticated requests. Test cases:

  **US5 — Disabled by default:**
  - `test_rate_limiting_disabled_by_default_returns_200` — `Setting.api_rate_limiting_enabled = '0'`; 5 `GET /issues.json` requests; all return 200
  - `test_rate_limiting_disabled_no_ratelimit_headers` — when disabled the response contains no `X-RateLimit-*` or `Retry-After` headers

  **US4 — Normal operation:**
  - `test_within_limit_returns_200_with_ratelimit_headers` — enabled=1, max=10, period=60; 3 `GET /issues.json` requests; each returns 200; response contains `X-RateLimit-Limit: 10`, `X-RateLimit-Remaining` decreases (9, 8, 7), `X-RateLimit-Reset` — positive timestamp
  - `test_xml_format_also_has_ratelimit_headers` — enabled=1; `GET /issues.xml`; 200; `X-RateLimit-*` headers present (Principle V — both formats)

  **US1 — Blocking:**
  - `test_exceeding_limit_returns_429` — enabled=1, max=3, period=60; 3 requests; the 4th returns 429
  - `test_429_response_includes_retry_after_header` — when exceeded the `Retry-After` header is present and is a positive integer
  - `test_429_body_is_neutral_does_not_reveal_token_validity` — send two requests over the limit: one with an invalid token, one with a valid token; the 429 response bodies are identical (FR-011)
  - `test_valid_token_still_gets_429_when_limit_exceeded` — exceed the limit with a valid jsmith token; the next request with the same token receives 429 (block is not lifted for a correct token — US1 scenario 3)
  - `test_non_api_html_requests_are_not_rate_limited` — enabled=1, max=1, period=60; send 5 `GET /login` requests (HTML, no format); all return 200 (FR-008 — API only)
  - `test_rate_limit_resets_after_window_expires` — enabled=1, max=3, period=60; exceed the limit; advance time by 61 seconds using `travel_to`; the next request returns 200
  - `test_rate_limit_applies_to_real_ip_from_x_forwarded_for` — enabled=1, max=2, period=60; send `GET /issues.json` with `X-Forwarded-For: 203.0.113.42`; verify 200 and `X-RateLimit-Remaining` present; repeat 2 more requests with the same `X-Forwarded-For` — the third receives 429 (FR-007: `request.remote_ip` correctly extracts the real IP from `X-Forwarded-For`)

### Implementation US1 / US4 / US5

- [x] T006 [US1] Add to `app/controllers/application_controller.rb`: (1) `prepend_before_action :check_api_rate_limit` at the start of the chain; (2) private method `check_api_rate_limit`: return if `!api_request?`; call `result = Redmine::RateLimit.check(request.remote_ip)`; handle `result[:log]` with a `case` statement — call `logger.warn` for `:overflow` and `:blocked`; return if `:disabled` or `:untracked`; set `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers; when `:denied` — set `Retry-After`, render JSON/XML error body via `respond_to`

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/integration/api_test/rate_limiting_test.rb` — all 14 tests pass.

---

## Phase 4: US2 — Admin Settings Management

**Goal**: the administrator enables/configures rate limiting via `/admin/settings?tab=api`; changing settings resets the counters.

**Independent testing**: navigate to `/admin/settings?tab=api`; enable rate limiting; set max=50, period=60; save; verify that the fields were saved.

### Tests US2 ⚠️ Write First

- [x] T007 [P] [US2] Add test cases to `test/functional/settings_controller_test.rb` (to the existing class `SettingsControllerTest < Redmine::ControllerTest`). In test `setup`: `Redmine::RateLimit.reset_store!`. Test cases:
  - `test_api_tab_shows_rate_limiting_fields` — `get :edit, params: {tab: 'api'}`; `assert_response :success`; assert presence of `settings[api_rate_limiting_enabled]`, `settings[api_rate_limit_max_requests]`, `settings[api_rate_limit_period]`, `settings[api_rate_limit_max_ips]` inputs
  - `test_save_rate_limit_settings_updates_values` — `post :edit, params: {tab: 'api', settings: {api_rate_limiting_enabled: '1', api_rate_limit_max_requests: '50', api_rate_limit_period: '120', api_rate_limit_max_ips: '5000'}}`; assert redirect; `assert_equal '1', Setting.api_rate_limiting_enabled`; `assert_equal '50', Setting.api_rate_limit_max_requests.to_s`
  - `test_save_invalid_max_requests_shows_error` — `post :edit` with `api_rate_limit_max_requests: '0'`; `assert_response :success` (form re-rendered); response contains a validation error message
  - `test_save_invalid_period_shows_error` — `post :edit` with `api_rate_limit_period: '0'`; `assert_response :success`; response contains a validation error message (FR-010: period > 0)
  - `test_save_invalid_max_ips_shows_error` — `post :edit` with `api_rate_limit_max_ips: '0'`; `assert_response :success`; response contains a validation error message (FR-013: max_ips > 0)
  - `test_save_rate_limit_settings_resets_store` — exhaust the limit for an IP; `post :edit ...`; verify the previously blocked IP is now allowed (`:allowed` status)

### Implementation US2

- [x] T008 [US2] Add the rate limiting section to `app/views/settings/_api.html.erb`: `<p><%= setting_check_box :api_rate_limiting_enabled %></p>`; `<p><%= setting_text_field :api_rate_limit_max_requests, size: 6 %></p>`; `<p><%= setting_text_field :api_rate_limit_period, size: 6 %></p>`; `<p><%= setting_text_field :api_rate_limit_max_ips, size: 8 %></p>` — inside an existing `div.box.tabular.settings`

- [x] T009 [US2] Add counter store reset on rate limiting settings save: in `app/controllers/settings_controller.rb` in the `edit` action (POST branch) — after `Setting.set_all_from_params`, check whether any `api_rate_limit_*` keys are present; if so — call `Redmine::RateLimit.reset_store!(max_size: Setting.api_rate_limit_max_ips)`. Add validation: `api_rate_limit_max_requests > 0`, `api_rate_limit_period > 0`, `api_rate_limit_max_ips > 0` — on violation re-render the form with an error message.

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/functional/settings_controller_test.rb` — new tests pass.

---

## Phase 5: US6 — Thread Safety

**Goal**: concurrent requests from a single IP cannot yield more than the allowed number of 200 responses.

**Independent testing**: send N+10 concurrent requests with a limit of N — exactly N receive 200, the rest receive 429.

### Test US6 ⚠️ Write First

- [x] T010 [US6] Add test `test_concurrent_requests_do_not_exceed_limit` to `test/unit/lib/redmine/rate_limit_test.rb`: `max = 10`; launch 20 threads (`Thread.new { Redmine::RateLimit.check('10.0.0.1') }`), wait for all (`threads.each(&:join)`); count `:allowed` and `:denied` results; `assert_equal max, allowed_count`; `assert_equal 10, denied_count`. The test verifies that Mutex prevents bypassing the limit through concurrency.

**Checkpoint**: `docker compose exec test bundle exec rake test TEST=test/unit/lib/redmine/rate_limit_test.rb` — all 14 tests pass (13 from T003 + 1 from T010).

---

## Phase 6: Polish & Cross-Cutting

**Goal**: final validation, documentation, verify everything builds.

- [x] T011 [P] Verify that `lib/redmine/rate_limit.rb` contains: `# frozen_string_literal: true` (first line) and a GPL header (lines 2–17) matching the pattern of any file in `lib/redmine/`

- [x] T012 Run the full three-level test suite and verify all tests pass:
  ```
  docker compose exec test bundle exec rake test TEST=test/unit/lib/redmine/rate_limit_test.rb
  docker compose exec test bundle exec rake test TEST=test/functional/settings_controller_test.rb
  docker compose exec test bundle exec rake test TEST=test/integration/api_test/rate_limiting_test.rb
  ```
  Verify no regressions in `test/integration/api_test/authentication_test.rb` (rate limiting must not break existing authentication).

- [x] T013 [P] Verify quickstart.md — run through the steps manually or via Docker: enable rate limiting in the admin UI, execute the curl commands from the quickstart, verify that headers and 429 look as expected; if discrepancies are found — update quickstart.md

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no dependencies — can start immediately
- **Phase 2 (Foundation)**: depends on Phase 1 — blocks all others
- **Phase 3 (US1/US4/US5)**: depends on Phase 2
- **Phase 4 (US2)**: depends on Phase 2; can run in parallel with Phase 3
- **Phase 5 (US6)**: depends on Phase 2; can run in parallel with Phases 3 and 4
- **Phase 6 (Polish)**: depends on Phases 3, 4, 5

### Within Each Phase

- Tests are written **before** implementation — verify they fail first
- Modules/models **before** the integration layer
- Controller **after** the module

### Parallel Opportunities

```
Phase 1:    T001 + T002 [P] — simultaneously
Phase 2:    T003 → T004 (sequential, TDD)
Phase 3,4,5: after Phase 2 is complete:
              T005 [P] + T007 [P] + T010 — simultaneously (different files)
              Then T006 | T008 + T009 (implementation under tests)
Phase 6:    T011 [P] + T013 [P] simultaneously; T012 after all
```

---

## Implementation Strategy

### MVP (Phase 1 + 2 + 3 only)

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Store + unit tests)
3. Complete Phase 3 (ApplicationController + integration tests)
4. **Stop and verify**: rate limiting works, 429 is returned, tests are green
5. Deploy/demo possible — basic protection is active

### Full Implementation

1. Phase 1 → Phase 2 → Phase 3 (MVP, ~40% of tasks)
2. Phase 4 (admin UI) → feature is fully manageable
3. Phase 5 (thread safety test) → formal confirmation of thread safety
4. Phase 6 (polish) → ready to merge

---

## Notes

- `[P]` = different files, no inter-task dependencies
- TDD: tests are written before implementation and verified as failing
- Use `travel_to` (ActiveSupport::Testing::TimeHelpers) for all time advancement in tests — it is block-scoped and auto-restores
- `Redmine::RateLimit.reset_store!` should be called in `setup` of all tests that work with the store, for isolation
- Fixtures are sufficient for tests — user `jsmith` (id=2) is present in `test/fixtures/users.yml`
- All Redmine settings return String even with `format: int`; always call `.to_i` at point of use
