# Feature Specification: API Rate Limiting

**Feature Branch**: `feature/api-rate-limiting`

**Created**: 2026-05-28

**Status**: Draft

**Purpose**: Protect the REST API against two classes of security threats:
- **Token brute-force** — automated guessing of API tokens by sending large volumes of requests with different credentials from a single IP.
- **Bulk data extraction** — systematic scraping of all content through the API without authorisation for that volume of access.

---

## User Stories and Acceptance Testing *(required)*

### User Story 1 — Block API Token Brute-Force (Priority: P1)

An attacker attempts to discover a valid Redmine API token by sending a large number of requests with different token values from a single IP. The system detects that the threshold has been exceeded and blocks further requests from that IP for a period of time, making brute-force impractical.

**Why this priority**: Token brute-force is a direct threat of account compromise. This is the primary motivation for the feature.

**Independent testing**: Configure a limit, send a series of requests from a single IP with arbitrary tokens exceeding the limit — the server must return `429 Too Many Requests` and continue rejecting requests until the counter resets.

**Acceptance scenarios**:

1. **Given** an attacker sends requests with invalid tokens from a single IP, **When** the number of requests does not exceed the window limit, **Then** each request receives a 401 response (invalid credentials), not 429.
2. **Given** an attacker has exceeded the request limit in the current time window, **When** they send the next request (regardless of token — valid or not), **Then** the server returns HTTP 429 with a `Retry-After` header.
3. **Given** an IP is blocked by the rate limit, **When** the same IP sends a request with a valid token, **Then** the request still receives 429 — the block is not lifted by a correct token.
4. **Given** the rate limit time window has expired, **When** the IP sends the next request, **Then** the counter resets and the request is processed normally.

---

### User Story 2 — Manage Settings via Admin Interface (Priority: P1)

A Redmine administrator configures rate limiting parameters (enable/disable, request limit, time window) through the standard settings page in the admin section — in the same way as other system parameters.

**Why this priority**: Without the ability to manage settings, the feature cannot be used in production. Rate limiting is disabled by default, so configuration management is critical.

**Independent testing**: Navigate to `/admin/settings`, enable rate limiting, set parameters, save — and verify that the settings were saved and applied.

**Acceptance scenarios**:

1. **Given** an administrator opens the API settings page, **When** rate limiting is disabled (default state), **Then** the setting is displayed as disabled and the API works without restrictions.
2. **Given** an administrator enables rate limiting and sets a limit (e.g., 100 requests per minute), **When** they save the settings, **Then** the new parameters take effect immediately without a server restart.
3. **Given** an administrator enters invalid parameter values (e.g., a negative limit), **When** they attempt to save, **Then** the system displays a clear error message and does not save the invalid data.
4. **Given** an administrator disables rate limiting, **When** the settings are saved, **Then** the API stops checking limits and processes all requests without restriction.

---

### User Story 3 — Inform the Client About Limits (Priority: P2)

An API client (a developer or an automated system) receives information about the current limits and remaining allowed requests via standard HTTP headers, so it can correctly manage its request frequency.

**Why this priority**: Improves developer experience and allows clients to implement backoff logic, but does not block the basic protection.

**Independent testing**: Send a request to the API and verify the presence and correctness of rate limit headers in the response.

**Acceptance scenarios**:

1. **Given** rate limiting is enabled, **When** a client makes any API request, **Then** the response contains headers with information about the limit, remaining requests, and reset time.
2. **Given** a client has exceeded the limit, **When** they receive a 429 response, **Then** the response contains a `Retry-After` header with the number of seconds until the counter resets.
3. **Given** rate limiting is disabled, **When** a client makes an API request, **Then** rate limit headers are absent from the response.

---

### User Story 4 — Normal Operation of a Legitimate API Client (Priority: P1)

A legitimate API client (an integration script, CI/CD pipeline, or external system) works in normal mode: all its requests fit within the configured limit, and rate limiting has no effect on its operation.

**Why this priority**: This is the mandatory "golden path" — the protection feature must not interfere with normal users.

**Independent testing**: Enable rate limiting, send N requests (within the limit) from a single IP — all requests should receive normal responses with no restrictions.

**Acceptance scenarios**:

1. **Given** rate limiting is enabled with a limit of 100 requests per minute, **When** a client sends 50 requests from a single IP within a minute, **Then** all 50 requests are processed and receive normal responses (200, 201, 404, etc.), without 429.
2. **Given** a client is operating below the rate limit threshold, **When** it requests any API resource, **Then** the response contains correct `X-RateLimit-Remaining` headers with a decreasing count and `X-RateLimit-Limit` with the full limit.
3. **Given** a client has fully used the current window's limit and waited for it to reset, **When** a new window begins and the client sends a request, **Then** the request is processed normally and `X-RateLimit-Remaining` again shows the full limit minus one.
4. **Given** two different legitimate clients are working simultaneously from different IPs, **When** each sends requests within its own limit, **Then** the counters of these IPs do not affect each other and both clients receive normal responses.

---

### User Story 5 — Operation Without Rate Limiting Enabled (Priority: P1)

An administrator has not enabled rate limiting (the default state). The system operates in a fully transparent mode: no requests are rejected due to request frequency, and no overhead is added to request processing.

**Why this priority**: Rate limiting is disabled by default. The system must work correctly in this state, without creating false blocks or affecting performance.

**Independent testing**: Verify that rate limiting is disabled (default setting), send any number of requests from a single IP — none should receive 429, and rate limit headers should be absent.

**Acceptance scenarios**:

1. **Given** rate limiting is disabled (the default state after installation), **When** a client sends any number of API requests to an existing resource with valid credentials, **Then** each request returns HTTP 200 (or another normal code: 201, 204) — none receive 429.
2. **Given** rate limiting is disabled, **When** a client sends a request and receives HTTP 200, **Then** the response does not contain `X-RateLimit-*` or `Retry-After` headers.
3. **Given** rate limiting is disabled, **When** a client sends requests continuously at a volume many times exceeding any reasonable limit, **Then** all requests to existing resources return HTTP 200 — the system imposes no restrictions.
4. **Given** rate limiting was enabled and previously blocked an IP, **When** the administrator disables rate limiting and the client retries the request, **Then** the request returns HTTP 200 (the block is lifted, counters are not checked).

---

### User Story 6 — Thread Safety Under Concurrent Requests (Priority: P2)

Multiple concurrent requests from a single IP arrive simultaneously at the moment the counter is at the limit boundary. The system correctly increments the counter without data races: no IP receives more requests than allowed due to parallel processing, and no legitimate request is lost in the count.

**Why this priority**: Without an atomic counter, an attacker can bypass the protection by sending a burst of concurrent requests at the window reset moment. At the same time, this does not block the basic implementation.

**Independent testing**: Send a burst of concurrent requests from a single IP (e.g., 20 simultaneous with a limit of 15) — the total number of processed requests must not exceed the limit.

**Acceptance scenarios**:

1. **Given** rate limiting is enabled with a limit of N, **When** N+K requests (K > 0) arrive simultaneously from a single IP, **Then** exactly N requests receive a normal response and K requests receive 429 — no more than N successful in total.
2. **Given** the IP counter is at zero, **When** several first requests arrive simultaneously, **Then** each is counted in the counter — the final value equals the number of concurrent requests, with no losses.
3. **Given** multiple threads are simultaneously updating counters for different IPs, **When** requests are processed in parallel, **Then** the counters of different IPs do not affect each other and do not corrupt each other's values.

---

### Edge Cases

- What happens with concurrent requests from a single IP (race condition during counter increment)?
- How does the system behave with a large number of unique IP addresses (memory consumption)?
- Is the limit correctly applied to IPv6 addresses?
- What happens with requests behind a reverse proxy, where the real IP comes through the `X-Forwarded-For` header?
- Does the limit apply to requests from the server itself (loopback address)?
- How is the limit applied when multiple users share a single outgoing IP (NAT, corporate network)? They all share one counter.
- Does the limit apply to requests that have already failed authentication (401)? **Yes** — precisely these requests are characteristic of token brute-force.

---

## Requirements *(required)*

### Functional Requirements

- **FR-001**: The system MUST support enabling/disabling rate limiting for the API via the admin interface; rate limiting is disabled by default.
- **FR-002**: The system MUST limit the number of API requests from a single IP address within a given time window — **regardless of the authentication result** (the limit is counted before token verification, so brute-force is blocked).
- **FR-003**: The system MUST return HTTP 429 (Too Many Requests) when the limit is exceeded, with a `Retry-After` header.
- **FR-004**: The system MUST include headers with rate limit information (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) in API responses when rate limiting is enabled.
- **FR-005**: An administrator MUST be able to configure the maximum number of requests and the time window length (in seconds) via the settings page.
- **FR-006**: Rate limiting settings MUST take effect without a server restart. When any setting changes are saved (limit, window, enable/disable), the counter store MUST be fully cleared — all IPs start from zero when the new settings take effect.
- **FR-007**: The system MUST correctly identify the client's IP address accounting for reverse proxies (the `X-Forwarded-For` header).
- **FR-008**: Rate limiting MUST apply only to API requests (endpoints with format `.json`, `.xml`, or `Accept: application/json/xml` header), but not to the web interface.
- **FR-009**: The implementation MUST use a **sliding window**: at any point in time the system checks the number of requests in the last N seconds from the current moment, without resetting the counter at fixed intervals. This eliminates the "double burst" effect at period boundaries.
- **FR-010**: The system MUST validate input parameters (limit > 0, window > 0) and display clear error messages.
- **FR-011**: The 429 response MUST NOT reveal information about whether an account exists or whether a token is valid — the response body must be neutral (must not differ between "invalid token" and "valid token but limit exceeded").
- **FR-012**: When a limit is first exceeded for an IP in the current sliding window, the system MUST write an event to the application log: the IP address, the time of the block, and the current number of requests in the window. Subsequent rejections of the same IP in the same window MUST NOT be duplicated in the log.
- **FR-013**: The counter store MUST have a configurable upper limit on the number of tracked IP addresses with a sensible default. When the limit is reached, the system MUST first evict entries whose timestamps have fully expired beyond the sliding window (stale entries). If space is freed after eviction, the new entry is added. If the store is still full (all entries are active), the new IP's request MUST be processed without restriction (fail open), and a warning MUST be logged with the current number of entries. The default maximum number of entries MUST be documented in the settings.

### Key Entities

- **RateLimitSetting**: Rate limit configuration — enabled/disabled (`enabled`), maximum number of requests (`max_requests`), time window length in seconds (`period`). Stored in Redmine's common settings store.
- **RateLimitCounter**: Request counter for an IP address — implemented as a sliding window approximation via two counters. Stores the structure `{prev_count, curr_count, window_start, logged_this_window}`: `prev_count` — number of requests in the previous completed window, `curr_count` — number of requests in the current window, `window_start` — Unix timestamp of the start of the current window, `logged_this_window` — deduplication flag for block log events. Stored in memory (in-memory), constant record size (~24 bytes). The total number of records is limited by a configurable parameter; when the limit is reached, fully stale records (where `approx ≈ 0`) are evicted before adding a new one.

---

## Success Criteria *(required)*

### Measurable Outcomes

- **SC-001**: An automated token brute-force attack (more than N requests per window from a single IP) is fully blocked: no request beyond the limit reaches the credential verification logic.
- **SC-002**: A bulk data extraction script via the API receives 429 after exceeding the limit and cannot continue extraction until the window expires.
- **SC-003**: A client that has exceeded the limit receives a 429 response no later than the next request after exceeding, with a correct `Retry-After`.
- **SC-004**: After the time window expires, the client can again make requests up to the full limit.
- **SC-005**: An administrator can fully configure rate limiting (enable, set parameters, save) in less than 2 minutes via the standard settings interface.
- **SC-006**: Settings changes take effect for new requests within no more than 5 seconds without restarting the application.
- **SC-007**: When rate limiting is disabled, API performance does not degrade (no overhead from checks, or negligibly small).

---

## Clarifications

### Session 2026-05-28

- Q: Time window type: fixed or sliding? → A: Sliding window — the system always looks at the last N seconds from the current moment.
- Q: Block event logging — what level of detail? → A: Log the first trigger per IP per window (IP, time, request count); subsequent 429s in the same window are not duplicated.
- Q: Behaviour of the counter store when the maximum number of entries is reached? → A: Evict stale entries (all timestamps have gone beyond the window boundary) when the limit is hit; the limit is configurable with a default value.
- Q: What happens to counters when an administrator changes settings? → A: Full store reset — all IPs start from zero when the new settings take effect.
- Q: What to do with a new IP if the store is still full after evicting stale entries? → A: Fail open — let the request through without tracking, log a warning.

---

## Assumptions

- The current version uses only the IP address as the client identifier; token-based and combined variants are for future iterations.
- Request counters are stored in process memory (in-process store); persistence across server restarts is not required in v1.
- Rate limiting parameters are uniform across the entire API (not differentiated by endpoint or user in v1).
- Settings management is available only to users with Redmine administrator rights.
- Correct identification of the real IP behind a reverse proxy is considered the responsibility of the server configuration; the system uses the standard Rails mechanism for obtaining the IP (`request.remote_ip`).
- The limit applies to all API requests without exceptions for specific endpoints or IP ranges in v1.
- Users behind a shared NAT/corporate proxy share a single counter — this is a deliberate trade-off between security and convenience for v1. In future versions, a token-based variant will resolve this.
- The limit is applied **before** authentication verification — this is an intentional decision to block token brute-force, where the majority of requests will be unauthenticated.
