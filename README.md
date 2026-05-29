# Home Task · Strengthen Redmine API Authentication

## Original task

<details>
<summary>📋 API Authentication Enhancement Task</summary>

## Overview
Strengthen the authentication system for an open-source project management application built on Ruby on Rails.

## Requirements

### Three Core Pillars
1. **Token Expiration** – Implement time-based validity for API tokens
2. **Scopes** – Add permission-based access control to API tokens
3. **Rate Limiting** – Prevent abuse through request throttling

## Deliverables

### 1. Git Repository
- Fork/branch from the main codebase (tag 6.1.2)
- Repository must be cloneable, installable, with runnable migrations
- Implementation should be verifiable through tests or manual validation

### 2. AI Workflow Artifacts
- Document the problem-solving process (exported chats, transcripts, or prompt-response pairs)
- Show iterative refinement and corrections
- Demonstrate working with AI coding assistants effectively
- Include atomic, well-messaged commits telling a story of development
- Optional: Screen recording of actual working session

### 3. README
Brief documentation covering:
- Approach and rationale
- What's implemented vs. deferred
- Key assumptions
- How to run and verify the solution

## Key Constraints

- **Time guideline:** ~2 hours for implementation
- **Scope:** Pick a defensible slice of the three pillars—don't attempt the full feature set
- **Quality over completeness:** A focused, well-executed piece beats a half-finished sprawling implementation

## Evaluation Criteria

1. **Scoping judgment** – Is the slice defensible and worth shipping?
2. **AI workflow quality** – Clear direction and iteration, not just code generation
3. **Codebase fit** – Integration with existing patterns vs. bolted-on solutions
4. **Working software** – The slice runs and verification holds up
5. **Communication** – Named decisions and honest trade-offs

</details>

## Pull Request

[Add IP-based API rate limiting to protect against token brute-force](https://github.com/ellhee/redmine/pull/2)

[Quickstart](https://github.com/ellhee/redmine/blob/001-api-rate-limit/specs/001-api-rate-limit/quickstart.md)

## Slice selection

- Reading the ticket carefully, I can see several parts beyond the three listed in the task (e.g. 2FA bypass and logging issues). I assume the task constraints take higher priority and consider only the 3 sub-tasks listed there:
    - Token expiration
    - Scopes
    - Rate limiting
- I also reason within the constraint of the recommended 2-hour time limit.

I initially ruled out the scopes task, as it requires deep immersion in the project and a review of existing scopes. The value from an isolated implementation of scopes is also not that high — architecturally we would rather restrict scopes for multiple tokens, tailoring them for different purposes.

Next I ruled out token expiration — it has a good cost/benefit ratio and in a real project it would likely have been chosen instead. But the technical solution is fairly straightforward: adding a new field to the tokens table and enforcing it — this task would likely give less signal in the context of the assignment. The product decision is harder: how to notify the user that a token has expired and initiate the process of obtaining a new one; poor familiarity with the product would be a problem here.

In the end I chose rate limiting:
- Meaningful feature (protection against token brute-force and bulk data extraction)
- Sufficiently isolated and verifiable
- Requires integration with the Rails stack — gives more signal in the context of the assignment
- Fits within ~2 hours

To complete the task within the recommended time and avoid taking on a huge scope, I allowed the following shortcuts:
- IP-based limiting only (protects against brute-force, not just specific tokens)
- In-memory implementation without Redis

## Tools used
- Docker containers for local development and testing
- JetBrains Fleet as the code editor (no RubyMine)
- Claude Code + Claude Desktop (Sonnet 4.6 model, High Effort)
- ChatGPT / Gemini for discussing solutions, review, and knowledge lookup
- Spec-kit framework from GitHub

## Setup
I cloned a fork of the repository and created a new branch from the latest release (tag 6.1.2).
For deployment I used Docker with two containers for development and testing, plus a Postgres container, all tied together with Compose.
I used Gemini to generate the Docker configuration but simplified the result significantly, keeping only the minimum.

On first run I got `Please configure your config/database.yml first`, which persisted even after adding the file.
Gemini got stuck here, having confirmed that the file was missing at the gem installation stage. I solved it myself — I noticed that the Dockerfile only copies `Gemfile` at that stage, so I added `database.yml` there as well.

I opened the web interface (http://localhost:3000), ran migrations from the console, explored the UI and admin panel, and enabled the API.
I ran the test suite and created and prepared the test database with a separate command (the format was suggested by Gemini).

This stage took about 20 minutes.

## Main task

### Gathering project information

In a new Claude session I ran the skill for collecting fundamental codebase information.

<details>
<summary>speckit-constitution skill</summary>

**/speckit-constitution** This is a Redmine project written on Ruby on Rails. Pay attention to the coding approaches already used, what tools are included. Look separately at the test structure and contents — what is typically tested and at what level.

Starting project exploration: reading structure, constitution and tests.
Git is already initialised, continuing. Now exploring the project to fill in the constitution.
Ran 20 commands, read 5 files
Enough data. Now looking at CONTRIBUTING and a few key models.
Gathered everything needed. Writing the constitution.

Constitution authoring
Updated
constitution.md +174 -0
Constitution written. Now checking templates for compatibility.

Ran
Check plan template references to constitution
The plan template contains a Constitution Check section — will update it to reference the real principles.

Edited
plan-template.md +8 -1

Result
Redmine Constitution created

| # | Principle | Key rule |
| :--- | :--- | :--- |
| **I** | **Rails Conventions First** | MVC, frozen_string_literal, GPL header, business logic in models |
| **II** | **Multi-Level Test Coverage** | Unit → Functional → Integration → API; run via Docker |
| **III** | **Fixtures as Test Data Authority** | 53 YAML fixtures — the sole source of test data |
| **IV** | **Plugin-Based Extensibility** | Plugins in plugins/, core extensions via lib/redmine/ |
| **V** | **REST API Parity** | Every UI CRUD operation available via REST (JSON + XML) |
| **VI** | **Internationalization** | All strings via I18n; no English hardcoded in ERB |

What was updated

✅ .specify/memory/constitution.md — created from scratch (only a template existed before)

✅ .specify/templates/plan-template.md — Constitution Check replaced with concrete checklists for principles I–VI

✅ .specify/templates/spec-template.md — compatible, no changes needed

✅ .specify/templates/tasks-template.md — compatible, src//tests/ paths are replaced with app//test/ during task generation

</details>

I skimmed the output — I am not familiar with Rails or the project, so I decided not to spend time on it and rely on the quality of the skill's information gathering.

I asked it to check for a linter.

While that was running I looked in Gemini in parallel at the available implementation approaches: the classic middleware approach and using before_action.
I tentatively chose before_action, even though it is less performant due to initialising more layers.

I considered middleware less suitable because:
- Given the existing settings and the look of the admin UI, we want to manage the limit from the web interface too, which means interacting with Settings in the implementation
- In the future, per the ticket, this system may be extended with token-based limiting, which would also add work at the Token model level

Overall this looks like more than what belongs strictly in the HTTP-layer Middleware, and I consider the performance difference acceptable.

### Design

<details>
<summary>speckit-specify skill</summary>

**/speckit-specify**
We need rate limiting for the API.
In the initial version we only do IP-based limiting; in the future this feature can be extended to token-based and combined variants.
Rate limiting is disabled by default.
The limit (enabling it and its parameters) is administered via the settings web page by an administrator, in the same way as other features.

Branch already exists, script returned BRANCH_NAME: "001-api-rate-limit", FEATURE_NUM: "001". Creating the specification directory and writing spec.md.

Now running the specification quality validation and creating the checklist.

Created requirements.md +36 -0

Specification created
- Directory: specs/001-api-rate-limit/
- Spec file: specs/001-api-rate-limit/spec.md
- Checklist: specs/001-api-rate-limit/checklists/requirements.md

What is described in the specification
3 user stories:

- P1 — Protect API from abuse: block by IP with HTTP 429 + Retry-After
- P1 — Admin management: enable/configure parameters via settings page without restart
- P2 — Inform the client: X-RateLimit-* headers in responses
- 10 functional requirements (FR-001..FR-010): disabled by default, IPv4/IPv6, X-Forwarded-For, API requests only, parameter validation.

Validation checklist: ✅ all items passed, no [NEEDS CLARIFICATION] markers.

Key v1 assumptions
- IP-based only (token-based in future versions)
- In-memory counter store
- Uniform settings for the entire API (no per-endpoint differentiation)
</details>

<details>
<summary>Refined the goals</summary>

The purpose of the task is protection against token brute-force and prevention of bulk data extraction.

Important clarification of purpose — will update the specification so these goals are explicitly reflected in the context, scenarios, and requirements.

Read spec.md
This is an important clarification — it shifts the context from "protection against overload" to an explicit security threat model. Updating the specification.

Edited spec.md +24 -16
Specification updated. Key changes:

What changed:

- Purpose — two threats explicitly named: token brute-force and bulk data extraction
- Scenario 1 — reoriented to a token brute-force attack: the limit fires regardless of token validity, even if the token is correct — the IP is still blocked
- FR-002 — added: the counter is incremented before authentication is checked (otherwise the brute-force attack would work)
- FR-011 — new requirement: the 429 response body must not reveal whether an account exists or whether the token is valid
- SC-001, SC-002 — success criteria now explicitly describe protection against specific threats
- Edge cases — added: NAT/corporate networks, applying the limit to 401 responses
- Assumptions — NAT trade-off and rationale for applying the limit before authentication documented
</details>

I reviewed the specification, user stories, and requirements.

<details>

<summary>Adjusted User Stories</summary>

Add a user story for normal operation (requests stay within limits) and a user story for operating without the feature enabled — nothing is blocked.

Reading the current specification to insert the stories in the right place.

Read a file, edited a file
Stories 4 and 5 added. What each describes:

Story 4 — Normal operation (P1):

- Requests within the limit receive normal responses
- X-RateLimit-Remaining headers decrease correctly
- After the window resets the counter recovers
- Different IPs have independent counters — they don't interfere with each other

Story 5 — Rate limiting disabled (P1):

- No request ever receives 429 regardless of volume
- X-RateLimit-* headers are absent from responses
- No counter checks happen (no overhead)
- When disabled, previously blocked IPs are unblocked
</details>

<details>
<summary>Thread safety requirement</summary>

Add a user story for thread safety.

Story 6 added (P2). Three acceptance criteria cover:

- Upper bound: with N+K concurrent requests exactly N pass, K are blocked — no more
- No losses: with parallel writes to the counter no increment is lost
- Isolation: parallel processing of different IPs does not cause mutual counter corruption
</details>

The criterion from User Story 5 seemed rather vague to me — "no 429 when limiting is disabled" — whereas we want clients to receive proper responses when limiting is disabled.

<details>
<summary>Clarifying User Story 5</summary>

Update Story 5 — Rate limiting disabled — not just absence of headers and 429, but receiving a full 200 response.

Updated. All four acceptance criteria now explicitly state HTTP 200 (or other normal code) as the expected result, not merely "absence of 429". The emphasis has shifted from "what does not happen" to "what must happen".
</details>

I ran the speckit-clarify helper skill — it also searches for ambiguities in the feature specification.

<details>
<summary>speckit-clarify skill</summary>

/speckit-clarify

Running prerequisites check and loading the specification.

Ran a command, read a file

Running coverage analysis across all categories.

| Category | Status | Note |
| :--- | :--- | :--- |
| Functional coverage | ✅ Clear | Goals, roles, OOS described |
| Data model | ⚠️ Partial | Time window type not defined |
| UX flows | ✅ Clear | Admin and client scenarios present |
| Performance | ✅ Clear | SC-007 covers it |
| Scalability | ⚠️ Partial | No upper bound on tracked IPs |
| Reliability | ❌ Missing | No behaviour defined when store memory is exhausted |
| Observability (logs/metrics) | ❌ Missing | No mention of block event logging |
| Security | ✅ Clear | FR-011, pre-auth check covered |
| Integrations | ✅ Clear | In-memory, no external dependencies |
| Edge cases | ✅ Clear | Well covered |
| Constraints/trade-offs | ✅ Clear | NAT trade-off documented |
| Behaviour on settings change | ⚠️ Partial | Missing: what happens to counters when config changes |
| Terminology | ✅ Clear | Consistent |

**Question 1 of 5: Time window type**

Context: The specification mentions a "time window" but does not specify its type. This is a key architectural decision that affects boundary behaviour and brute-force protection effectiveness.

What needs clarifying: How does the counter window work — fixed or sliding?

Recommendation: Option B (sliding) — uniformly limits traffic at any point in time, no "double burst" effect at period boundaries, which is important for brute-force protection.

| Option | Description |
| :--- | :--- |
| **A** | **Fixed window** — counter resets at fixed moments (e.g., every 60 seconds by the clock). Simpler to implement. Vulnerability: at the boundary of two windows a burst of up to 2×N requests is possible. |
| **B** | **Sliding window** — always looks at the last N seconds from the current moment. Uniform protection without peaks at boundaries. Harder to store. |
| **C** | **Doesn't matter for v1** — leave to the implementation, document as a detail. |

Accepted: sliding window. Updating the specification.

**Question 2 of 5: Block event logging**

Context: The specification describes protection against brute-force and bulk extraction, but does not mention whether the system should record block events. Without logs the administrator has no way to know whether rate limiting is working or whether the system is under attack.

What needs clarifying: Should the system write limit-exceeded events to the log (IP, time, request count)?

Recommendation: Option A — block events are security events; their absence from logs makes protection "blind" and hampers incident investigation.

| Option | Description |
| :--- | :--- |
| **A** | **Log each first trigger** — on the first 429 for an IP in the current window, write to the log: IP, timestamp, request count. Subsequent 429s in the same window — do not duplicate. |
| **B** | **Log every 429** — record each rejected request as a separate log line. |
| **C** | **Do not log** — leave logging to the implementation, do not include in the specification. |

Accepted: log the first trigger per IP per window. Updating the specification.

**Question 3 of 5: Behaviour when the store runs out of memory**

Context: Counters are stored in-memory. With a large number of unique IPs (e.g., during a distributed attack) the store can grow without bound. The specification does not define what to do when the limit is reached — and that decision directly affects server reliability and security.

What needs clarifying: What does the system do when the number of tracked IPs reaches the maximum?

Recommendation: Option A — LRU eviction protects server memory while continuing to work for active IPs. A "forgotten" IP will simply start a new counter on its next request — an acceptable trade-off.

| Option | Description |
| :--- | :--- |
| **A** | **LRU eviction** — when the limit is reached, the entry with the most distant last request is evicted. The new IP gets a clean counter. Maximum number of entries is configurable (with a sensible default). |
| **B** | **Fail open** — when the entry limit is exceeded, new IPs are not tracked and are let through without restriction. Availability over security. |
| **C** | **No limit** — the store grows without bound; memory responsibility lies with the server's operational configuration. |

Let's use eviction of stale data when the maximum number of entries is reached (configurable with a default value).

Accepted: evict stale entries when the limit is reached. Updating the specification.

**Question 4 of 5: Counter behaviour when the administrator changes settings**

Context: The administrator can change parameters at any time — for example, reduce the limit from 200 to 50 or change the window length. The specification does not define what happens to already-accumulated counters at that moment.

What needs clarifying: What happens to existing IP counters when the administrator saves new settings?

Recommendation: Option A — resetting on settings change is simple, predictable, and eliminates inconsistency between old data and new window parameters.

| Option | Description |
| :--- | :--- |
| **A** | **Reset all counters** — when new settings are saved, the counter store is fully cleared. All IPs start from zero. Simple and consistent. |
| **B** | **Keep counters** — counters continue to work; new settings are applied only to checking subsequent requests. Temporary inconsistency is possible (e.g., timestamps older than the new window). |
| **C** | **Wait for natural expiry** — counters will become stale on their own via the sliding window; no restart needed. New window parameters are applied to checking immediately. |

Accepted: reset all counters on settings change. Updating the specification.

**Question 5 of 5: Behaviour on store overflow after stale eviction**

Context: FR-013 defines that when the entry limit is reached, stale entries are evicted first. But if all entries are still active (attack from a large number of unique IPs simultaneously) — there is still no space. Behaviour in this edge case is undefined.

What needs clarifying: What to do with a new IP if the store is still full after evicting stale entries?

Recommendation: Option A — prioritise protection over tracking new IPs. During a distributed attack it is more important to keep tracking already-known IPs than to add new ones without restriction.

| Option | Description |
| :--- | :--- |
| **A** | **Pass through without tracking (fail open)** — the new IP is handled without restriction, but a store-full warning is written to the log. Availability over completeness of protection. |
| **B** | **Reject the request (fail closed)** — return 429 to the new IP while the store is full. Security priority, risk of false blocks. |
| **C** | **Evict the oldest active entry (LRU)** — free a slot at the expense of the IP with the most distant last request. The store never blocks new IPs. |

Accepted: pass through without tracking, write a warning to the log. Final specification update.

5 of 5 questions asked and answered.
File: specs/001-api-rate-limit/spec.md

Sections affected:

- Functional requirements (FR-006, FR-009, FR-012, FR-013)
- Key entities (RateLimitCounter)
- "Clarifications" section (new, session 2026-05-28)

All categories resolved. The specification is ready for planning.
</details>

The skill did well in finding the memory leak issue; I adjusted the behaviour — not just evicting one entry at a time, but clearing all stale ones.

The second good suggestion was logging critical events, which I considered important for the feature to be fully usable.

<details>
<summary>speckit-plan skill</summary>

**/speckit-plan**

Running setup and loading context.

Ran a command, read a file
Now exploring the codebase for Phase 0 — looking at how similar mechanisms are implemented in Redmine.

Ran 21 commands
Enough data for the research. Writing all plan artefacts.

Phase 0: Research
Created research.md +130 -0

Phase 1: Design & Contracts
Created 3 files, ran a command

Now filling in plan.md and updating CLAUDE.md.

Planning result
- Branch: feature/api-rate-limiting
- Plan: specs/001-api-rate-limit/plan.md

Created artefacts

| File | Contents |
| :--- | :--- |
| `specs/001-api-rate-limit/research.md` | 8 decisions: integration point, algorithm, thread safety, settings, logging |
| `specs/001-api-rate-limit/data-model.md` | Settings structure (4 keys) and in-memory Store; state diagram |
| `specs/001-api-rate-limit/contracts/http-headers.md` | HTTP header contract for 200 and 429 responses |
| `specs/001-api-rate-limit/quickstart.md` | Enable, test, and read logs instructions |

Key architectural decisions
- lib/redmine/rate_limit.rb — all logic, Mutex-protected Store, public interface check(ip)
- prepend_before_action — runs before authentication, only for api_request?
- Sliding window — timestamp array, cleaned on every access
- Fail open on overflow — pass through + warn to log
- Store reset when any rate limit parameter is saved
- Constitution Check: ✅ all 6 principles passed

</details>

I was not happy with the decision to store all request timestamps in an array.

<details>
<summary>Timestamp array</summary>

Why do we need an array of all request timestamps in memory? Let's store only counts, significantly reducing memory usage.

Good observation on memory. Before updating the artefacts — an important consequence to flag.

Situation: storing only a count (count) — this is no longer a sliding window but a fixed window. A sliding window requires knowing exactly when each request arrived, to determine which ones are still "within the window" right now. Without timestamps this is impossible to do accurately.

But there is a middle-ground solution: sliding window approximation via two counters (current + previous window). This is exactly how Nginx, Cloudflare, and Redis rate limiters work:

| Option | Memory / IP | Accuracy | Note |
| :--- | :--- | :--- | :--- |
| **Timestamp array** | up to 2,400 bytes | Exact | Was chosen in Q1 |
| **Two counters** | ~24 bytes | ~99% | Recommended |
| **Single counter** | ~16 bytes | Fixed window | 2× burst at period boundary |

Updating all artefacts for the two-counter variant — preserving the sliding window semantics from Q1 and achieving a 100× reduction in memory.

Also updating the X-RateLimit-Reset formula in the contract — with approximation it is computed differently.

All artefacts updated. Summary of the change:

| Characteristic | Before (timestamp array) | After (two counters) |
| :--- | :--- | :--- |
| **Structure per IP** | `Array<Float>` (timestamps) | `{prev_count, curr_count, window_start, logged}` |
| **Memory per IP** | up to 2,400 bytes | ~24 bytes (constant) |
| **Max memory (10K IPs)** | ~24 MB | ~240 KB |
| **Check time** | O(max_requests) | O(1) |
| **Window type** | Exact sliding | Sliding approximation (≤10% error) |
| **2× burst at boundary** | No | No (unlike fixed window) |

</details>

I also reviewed the research decisions; the rest was fine.

<details>
<summary>speckit-tasks skill</summary>

**/speckit-tasks** pay extra attention to thorough test design; make sure coverage is good but not excessive.

Loading all artefacts for task generation.

Generating tasks with detailed test coverage at all levels.

Tasks generated
File: specs/001-api-rate-limit/tasks.md

| Phase | Story | Tasks | Tests |
| :--- | :--- | :--- | :--- |
| **1 — Setup** | — | — | 2 |
| **2 — Foundation** | — | — | 13 unit cases (T003) |
| **3 — Enforcement** | US1, US4, US5 | — | 10 integration cases (T005) |
| **4 — Admin Settings** | US2 | — | 4 functional cases (T007) |
| **5 — Thread Safety** | US6 | — | 1 concurrent unit test (T010) |
| **6 — Polish** | — | — | 3 |
| **Total** | — | — | **33 test cases** |

Test coverage

Unit (13 cases in T003 + 1 in T010): Store algorithm, sliding window, window shift, overflow (both variants), logging (deduplication), reset, thread safety

Functional (4 cases in T007): settings form rendering, saving valid/invalid data, store reset on save

Integration (10 cases in T005): disabled by default (US5), golden path with headers (US4), JSON and XML (Principle V), 429 on limit exceeded (US1), neutral body (FR-011), valid token still blocked, HTML requests not limited (FR-008), window reset with travel_to

MVP

Phases 1–3 (T001–T006): rate limiting works, tests are green, ready for demo

</details>

### Implementation

I kicked off the implementation, in parallel reviewing the resulting artefacts to save time — if I had comments I would ask to redo details; at this stage the task plan and descriptions looked good in principle.

<details>
<summary>speckit-implement skill</summary>

**/speckit-implement**

Overall: PASS — proceeding to implementation.


Read 2 files
Implementation
Now loading implementation context:


Ran 14 commands, read 5 files
Now let me look at existing tests to understand patterns:


Ran 16 commands, read 3 files
I have all the context I need. Starting implementation — Phase 1 (T001 + T002 in parallel):


Read 2 files, ran a command
Now I have everything. Let me apply all Phase 1 changes in parallel:


Edited 2 files
✅ T001 + T002 complete. Now Phase 2 — writing tests first (T003), then implementation (T004):


Ran a command, created a file
✅ T003 written. Now implementing the core module (T004):

Created
rate_limit.rb +174 -0
Now let me verify T003 tests work with T004 implementation. First, check whether rate_limit.rb is auto-loaded:


Ran 9 commands, read a file
✅ 14/14 tests pass (T003 × 13 + T010 concurrent test).

Now Phase 3 — writing integration tests (T005) then controller integration (T006):


Ran a command, created a file
✅ T005 written. Now T006 — add check_api_rate_limit to ApplicationController:


Read a file, ran a command, edited a file
Now add the private method near api_request?:

Edited
application_controller.rb +17 -0
Now run Phase 3 integration tests:

Ran
Run Phase 3 integration tests
✅ 11/11 integration tests pass. Phase 4 — US2 (admin settings UI):


Read a file, edited a file
✅ T007 written. Now T008 — update the API settings view:

Edited
_api.html.erb +8 -0
✅ T008 done. Now T009 — add validation + store reset in SettingsController:


Read 3 files, ran 3 commands
Now add rate limit validation to Setting.validate_all_from_params:

Edited
setting.rb +9 -0
Now add the reset_store! call in SettingsController after successful save:


Read a file, edited a file
Now run Phase 4 functional tests:


Ran 3 commands, read a file
The format: int in settings.yml only validates numericality — the value is still stored and returned as a String. Fix the test assertions:


Edited a file, ran a command
✅ 26/26 functional tests pass. T010 (thread safety) was included in Phase 2's test file. Now Phase 6 — Polish (T011, T012):

Ran
Run all three rate limit test suites
All green. Now check the authentication test for regressions:

Ran
Check authentication regression test
Zero regressions. Now mark completed tasks in tasks.md:


Read a file, edited a file

All 13 tasks complete. All tests green.

Files created

| File | Purpose |
| :--- | :--- |
| `lib/redmine/rate_limit.rb` | Core module: two-counter sliding window store, `Mutex` for thread safety, public interface |
| `test/unit/lib/redmine/rate_limit_test.rb` | 14 unit tests (13 base + 1 concurrency) |
| `test/integration/api_test/rate_limiting_test.rb` | 11 integration tests |

Files modified:

| File | Changes |
| :--- | :--- |
| `config/settings.yml` | 4 rate limit settings keys added |
| `config/locales/en.yml` | 6 I18n keys added (`setting_*`, `error_*`, `label_*`) |
| `app/controllers/application_controller.rb` | `prepend_before_action :check_api_rate_limit` added |
| `app/controllers/settings_controller.rb` | `reset_store!` call on settings save |
| `app/models/setting.rb` | Validation for `max_requests`, `period`, `max_ips > 0` |
| `app/views/settings/_api.html.erb` | Rate limit settings section with 4 fields |
| `test/functional/settings_controller_test.rb` | 6 functional tests |

Test results

| Suite | Runs | Assertions | Status |
| :--- | :--- | :--- | :--- |
| **unit** (`rate_limit_test.rb`) | 14 | 30 | ✅ all pass |
| **functional** (`settings_controller_test.rb`) | 26 | 94 | ✅ all pass |
| **integration** (`rate_limiting_test.rb`) | 11 | 44 | ✅ all pass |
| **regression** (`authentication_test.rb`) | 18 | 29 | ✅ no regressions |

</details>

Afterwards I asked to run the linter.

<details>
<summary>Linter + tests</summary>

Please run the linter and then the tests for our tasks again.

What RuboCop fixed:

- evict_stale! — Style/IdenticalConditionalBranches: method rewritten so that `approx_count < 1.0` is extracted from the if/else branches (now both branches only compute `approx_count`, and the comparison is the single return value after)
- `20.times.map` → `Array.new(20)` in the thread safety test — Performance/TimesMap
- `assert_response 429` → `assert_response :too_many_requests` in all integration tests — Rails/HttpStatus

</details>

After this I tested the feature manually and found 2 issues:
- contract mismatch: human-readable messages were not being returned in the 429 response body;
- a bug when toggling the feature on/off via the admin panel.

<details>
<summary>Fix 1</summary>

Do we have a test that checks for a message in the body of a blocked request, to match the accepted contracts?
I'm testing manually right now and only see 429.

No, there's no such test — and you're right: the body is currently empty. `render_error` for API uses `format.any { head @status }`, which returns only the status with no body. The implementation and a test need to be fixed.


Read a file, edited a file
Now adding tests for the response body to the integration test:


Edited a file, ran a command
13/13. Quickly running the linter on the changed files:


Ran 3 commands, edited a file
Linter clean, 13/13 tests green. What was done:

Problem: `render_error` for API requests calls `format.any { head @status }` — returns only the status, no body.

Fix in `check_api_rate_limit` (application_controller.rb): replaced `render_error` with an explicit `respond_to` block with a body matching the contract:

JSON: `{"errors": ["Rate limit exceeded. Please try again later."]}`
XML: `<errors><error>Rate limit exceeded. Please try again later.</error></errors>`

Two new tests added to rate_limiting_test.rb:

- `test_429_json_body_contains_error_message` — checks JSON structure via `response.parsed_body`
- `test_429_xml_body_contains_error_message` — checks XML via `assert_select 'errors error'`

</details>

<details>
<summary>Fix 2</summary>

Add a test to verify the rate limiting behaviour after changing the limit parameters.

I enabled the limit, hit the limit on my requests, disabled it — requests started returning data again — then re-enabled it and saw the error:

comparison of Integer with String failed — if @data.size >= @max_size

I see the bug. `Setting.api_rate_limit_max_ips` returns a String, and `@max_size` in Store is used in the comparison `@data.size >= @max_size` (Integer vs String). This happens when `reset_store!` is called from the settings controller without `.to_i`.

Writing the failing test first:


Read a file, edited a file
Running — the test must fail:


Ran a command
Test confirms the bug (500). Now fixing it — adding `.to_i` to `reset_store!`:

Edited
rate_limit.rb +2 -1
Verifying the test now passes:

Ran
Run all integration tests including the new toggle test
14/14. Linter:

Ran
Lint fixed files
Clean. Full run of all our tests:

Ran
Full test suite run
54 tests, 0 failures.

What was done:

Bug: `Setting.api_rate_limit_max_ips` returns a String (that's how all Redmine settings work — even with `format: int`). When `reset_store!(max_size: Setting.api_rate_limit_max_ips)` was called, the string `"10000"` would end up in Store, and then `@data.size >= @max_size` would raise `ArgumentError: comparison of Integer with String failed`.

Fix in `reset_store!` — added `.to_i` when creating the new Store. The method now explicitly coerces the argument, protecting against strings from settings regardless of how it is called.

The test `test_toggle_rate_limiting_on_off_on_does_not_raise` reproduces the full cycle you described: enable → exhaust the limit → disable → re-enable via `reset_store!` with a string value from settings → verify the request passes without error.

</details>

I reviewed the tests myself and ran them past an external model; the most important thing I decided to fix was the absence of `travel_to` (`Time.stubs(:now)` was being used).

I reviewed the changes in the code and the `RateLimit` module in particular.

I was not happy that `store_size` was publicly accessible — it was only needed by tests to verify internal state. I considered this a poor unit test pattern: testing implementation rather than behaviour — what matters is not that the number of entries increases by 1 on a block, but that requests are blocked when the limit is exceeded.

<details>
<summary>Fix 3</summary>

Can you clarify why store_size is publicly accessible in RateLimit?
Yes, let's verify behaviour instead.

Looking at all tests that use store_size and planning the replacements:


Read 2 files
The picture is clear. Making three changes simultaneously:

- `test_overflow_evicts_stale_entries_and_allows_new_ip` — remove `assert_equal 3, store_size` (redundant: 3 calls already filled the store) and `assert store_size <= 3` (already checked via `:allowed` vs `:untracked`)
- `test_clear_empties_store` — rewrite: exhaust the limit → assert denied → reset → assert allowed
- `test_save_rate_limit_settings_resets_store` — same: block an IP → save settings → assert allowed

Edited 2 files
Now removing store_size from rate_limit.rb:

Edited rate_limit.rb +0 -5
Running all three test suites:

Ran 2 commands
54 tests, 0 failures, linter clean.

Summary:

`store_size` removed from the `Redmine::RateLimit` public interface. Three tests rewritten to verify behaviour:

</details>

I then asked to move `Rails.logger.warn` out of `RateLimit`, seeing it as an unnecessary dependency of the class on Rails.

<details>
<summary>Fix 4</summary>

I see Rails.logger.warn inside RateLimit — let's move it up a level.
Let RateLimit only return a flag indicating whether logging is needed.

Now I have all the context. Let me implement the changes across all three files.

Move logging out of RateLimit
Step 1 — lib/redmine/rate_limit.rb: remove both Rails.logger.warn calls and add a log: key to the result hashes instead.

Step 2 — app/controllers/application_controller.rb: handle the :log flag and emit warnings there.

Step 3 — update the unit tests: the two log-related tests now assert on result[:log] instead of mocking Rails.logger. Also add a log: assertion to the overflow test.

Now add a log: assertion to the overflow test:

Now run the tests to verify everything is green:


Ran 3 commands
All 54 tests green across all three suites. Let me do a quick RuboCop pass on the changed files:

Ran
RuboCop on changed files
No offenses. Here's a summary of what changed:

lib/redmine/rate_limit.rb — Store no longer calls Rails.logger at all. Instead it adds a log: key to the result hash:

- :untracked → log: :overflow
- First :denied in a window → log: :blocked (deduplication via logged_this_window stays inside Store where it belongs)
- Subsequent :denied → log: nil
- :allowed, :disabled → no log: key (nil by default)

app/controllers/application_controller.rb — check_api_rate_limit checks result[:log] with a case and calls logger.warn with the appropriate message before the early-return guard. The logging now happens at the boundary where the caller has the full HTTP context (request.remote_ip, settings, Time.now).

test/unit/lib/redmine/rate_limit_test.rb — the two logging tests are renamed and rewritten to assert on result[:log] rather than mocking Rails.logger. The overflow test also gains a log: :overflow assertion.

</details>

Finally I ran the full project test suite and manually verified the feature one more time.

## Summary

The task took about 2 hours. Lack of familiarity with Rails and the Redmine project was a frequent obstacle; with more time I would have studied them more deeply.

Code generation issues arose frequently due to inaccuracies in the collected foundational information — in projects where the constitution is assembled more carefully these would not occur.

I would also have spent more time on the test suite — some tests seem redundant (for example the test for not revealing valid tokens), and I would have looked more closely at the core RateLimit code.

## Key trade-offs

- Dropped distributed storage for counter data (e.g. Redis) — no external dependency, simpler deployment, at the cost of non-persistence across restarts and per-process counters
- IP-based blocking only (token-based would not protect against token brute-force, since most attack requests are unauthenticated)
- `prepend_before_action` instead of Rack middleware — the feature needs more than the HTTP layer (Settings, I18n, controller helpers), and future token-based extension would need model-level access too
- Full counter reset on settings change — no migration logic means simpler implementation, but at the moment of change previously blocked IPs are temporarily unblocked
- Fail open when store memory is exhausted — infrastructure stability and access for legitimate users take priority over blocking unknown IPs

## Screenshots

![Blocked request](Screenshot%201.png)
![Admin settings](Screenshot%202.png)
