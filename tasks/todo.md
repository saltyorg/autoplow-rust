# Autoplow task list

Aligned with the approved capability map (`docs/specs/README.md`). Each task names its **module ID** and the **spec acceptance criteria (AC)** it satisfies, e.g. `scan AC2` = `docs/specs/scan.md`, acceptance criterion 2. Sizes: S = 1–2 files, M = 3–5 files. Anything larger is split before work starts.

**Definition of done (every task):**
- `scripts/check-task.sh` passes, meaning every `CONSTRAINTS.md` gate: clippy, fmt, tests, changed-line coverage ≥ 90 %, mutation ≥ 80 %, cargo-deny, gitleaks, and the floor guard.
- The cited spec ACs are covered by tests.
- Docs are updated.
- Committed as a Conventional Commit.

## Phase 0: `core` foundation

### Task 0.1: Workspace skeleton and lint configuration
- [ ] **AC:**
  - Cargo workspace with `crates/autoplow` (binary), `crates/core`, `crates/api-types` and `crates/ui` stubs.
  - `[workspace.lints]`, `clippy.toml` and `rust-toolchain.toml` exactly as in the appendix of `docs/quality-policy.md`.
  - Every crate sets `lints.workspace = true`.
  - `autoplow --version` works.
- **V:**
  - `cargo clippy --workspace --all-targets -- -D warnings` and `cargo fmt --check` pass.
  - A planted `unwrap()` fails clippy.
- **Dep:** none.
- **Files:** `Cargo.toml`, `clippy.toml`, `rust-toolchain.toml`, `crates/*/Cargo.toml`, `crates/autoplow/src/main.rs`.
- **Size:** M.

### Task 0.1b: Gate tooling, Rust CI and release automation
- [ ] **AC:**
  - Every `CONSTRAINTS.md` tool is wired into `scripts/check-task.sh` and `.github/workflows/rust.yml`: nextest, llvm-cov + diff-cover, cargo-mutants + `scripts/check-mutants.sh`, cargo-deny + `deny.toml`, cargo-machete, gitleaks, trunk + `scripts/check-wasm-budget.sh`, Playwright + axe.
  - release-please (`release-type: rust`).
- **V:**
  - Trial run on the branch is green.
  - The floor guard catches a planted `#[allow]`, `todo!()` and `#[ignore]`.
  - The project-coverage baseline is recorded in `CONSTRAINTS.md`.
- **Dep:** 0.1.
- **Files:** `scripts/check-task.sh`, `scripts/check-mutants.sh`, `scripts/check-wasm-budget.sh`, `deny.toml`, `.github/workflows/rust.yml` (+ `release-please-config.json`).
- **Size:** M.

### Task 0.2: Paths: `FolderPath`, scoped rewrite sets
- [ ] **AC (core AC5):**
  - Component containment.
  - Overlapping sources rejected within a set.
  - Trigger, target and pair scopes, where a pair set replaces the target set.
  - Parent/child coalescing helper.
- **V:** unit tests plus proptest (`/mnt/Movies` vs `/mnt/Movies4K`, trailing slashes, `..`).
- **Dep:** 0.1b.
- **Files:** `crates/core/src/paths/*.rs`.
- **Size:** S.

### Task 0.3: Store and migrations
- [ ] **AC (core AC4):**
  - SQLite in WAL mode, one writer and a reader pool.
  - Embedded, versioned migrations.
  - Compare-and-set helper.
  - Migration fixtures.
- **V:** migration-up tests; writer-serialisation test.
- **Dep:** 0.1.
- **Files:** `crates/core/src/store/*.rs`, `crates/core/migrations/`.
- **Size:** M.

### Task 0.4: Supervisor and component lifecycle
- [ ] **AC (core AC1–AC3):**
  - Restart with backoff, including after a panic, with the component named in the log.
  - A config change rebuilds only the dependent components.
  - Shutdown within the deadline (30 s).
- **V:** fake components and a paused clock.
- **Dep:** 0.1.
- **Files:** `crates/core/src/supervisor/*.rs`.
- **Size:** M.

### Task 0.5: Config model and seed-once bootstrap
- [ ] **AC (core-bootstrap-api AC1):**
  - Typed resources.
  - Strict YAML with line and column errors.
  - Seed once; delete the file after success, keep it on partial failure.
  - Secret-free report.
  - JSON Schema generated.
- **V:** golden tests for the report, partial failure and a read-only file.
- **Dep:** 0.3.
- **Files:** `crates/core/src/config/*.rs`.
- **Size:** M.

### Task 0.6: HTTP server, auth and secrets
- [ ] **AC (core AC6, AC7):**
  - `/api/v1`, RFC 9457 errors, body limits, `/health`, OpenAPI.
  - API keys (admin, read-only).
  - Argon2 admin user, login rate limit.
  - Encrypted secrets with full re-encryption on key rotation.
  - Secrets never echoed.
- **V:** auth matrix tests; a seeded-secret grep over logs and responses.
- **Dep:** 0.5.
- **Files:** `crates/core/src/{api,auth,secrets}/*.rs`.
- **Size:** M.

### Task 0.7: Resource CRUD and `POST /apply`
- [ ] **AC (core-bootstrap-api AC2, AC3):**
  - `PUT`/`PATCH`/`DELETE` by name.
  - `apply` with `seed`/`upsert` and `dry_run`.
  - Changes notify the supervisor.
- **V:** idempotency tests; a dry run makes no writes.
- **Dep:** 0.6, 0.4.
- **Files:** `crates/core/src/api/resources.rs`, `crates/api-types/src/*.rs`.
- **Size:** M.

### Task 0.8: Observability
- [ ] **AC (core AC7, AC8):**
  - `tracing` with a level per component.
  - `secrecy`-typed secrets.
  - `/metrics`.
  - An SSE broker that never blocks a publisher.
  - Idle RSS ≤ 64 MB and CPU ≤ 1 %.
- **V:** broker back-pressure test; an idle soak measured under a cap.
- **Dep:** 0.6.
- **Files:** `crates/core/src/{obs,events}/*.rs`.
- **Size:** S.

### Task 0.9: UI shell (Leptos)
- [ ] **AC (core AC9, core-bootstrap-api AC4):**
  - CSR app built with trunk and `wasm-opt -Oz`, embedded with rust-embed.
  - Login, navigation, live event client, API client from `api-types`.
- **V:** Playwright login test; zero serious or critical axe violations; WASM within budget.
- **Dep:** 0.6, 0.8.
- **Files:** `crates/ui/src/*.rs`, `crates/autoplow/src/embed.rs`, `e2e/login.spec.ts`.
- **Size:** M.

### Checkpoint: core
- [ ] Bootstrap seeds an admin user and an API key; `apply` is idempotent; the UI logs in.
- [ ] All gates pass.
- [ ] Human review.

## Phase 1: `notifications`

### Task 1.1: Outbox and dispatcher
- [ ] **AC (notifications AC1–AC3):**
  - Transactional outbox.
  - Aggregation window.
  - Backoff honouring `Retry-After` and Discord limits.
  - Dead-letter.
- **V:** crash-and-restart durability test with a paused clock.
- **Dep:** 0.3, 0.4.
- **Files:** `crates/notifications/src/{outbox,dispatch}.rs`.
- **Size:** M.

### Task 1.2: Channels, subscriptions and UI
- [ ] **AC (notifications AC4–AC6):**
  - Discord, Apprise and webhook channels.
  - Subscriptions per event type.
  - Disable a channel without backfill on re-enable.
  - Undelivered: send again, discard, discard all; 30-day pruning.
  - UI page.
- **V:** fake-endpoint tests; Playwright plus axe.
- **Dep:** 1.1, 0.9.
- **Files:** `crates/notifications/src/channels/*.rs`, `crates/ui/src/pages/notifications.rs`.
- **Size:** M.

### Checkpoint: notifications
- [ ] A failure event reaches Discord, Apprise and webhook fakes once, after a restart in between; human review.

## Phase 2: `targets`

### Task 2.1: Shared HTTP client and library resolver
- [ ] **AC (targets AC2–AC4; scan AC8, the containment part):**
  - Timeouts, 4 MB response cap, `Retry-After`, error taxonomy.
  - Token redaction in URLs.
  - Library cache refreshed periodically and on a miss.
  - Component-based containment, multi-library resolution.
- **V:** unit tests and recorded fixtures.
- **Dep:** 0.2, 0.6.
- **Files:** `crates/targets/src/{http,libraries}.rs`.
- **Size:** M.

### Task 2.2: Plex client
- [ ] **AC (targets AC1):**
  - Sections with paging headers.
  - `refresh?path=`.
  - Sessions websocket, non-blocking reader.
  - Section state for verified empty trash.
- **V:** fixture contract tests; `live` test reproduces the platform-notes timings.
- **Dep:** 2.1.
- **Files:** `crates/targets/src/plex/*.rs`.
- **Size:** M.

### Task 2.3: Jellyfin and Emby clients
- [ ] **AC (targets AC1, AC6):**
  - Batched `Media/Updated` (Modified for Jellyfin, Created for Emby).
  - Library listing.
  - Sessions websocket.
  - Overlap warning.
  - Emby delete-by-Id quirk in the test helpers.
- **V:** fixtures; `live` test confirms about 60 s and 90 s.
- **Dep:** 2.1.
- **Files:** `crates/targets/src/{jellyfin,emby,mediabrowser}.rs`.
- **Size:** M.

### Task 2.4: Tdarr, Autoplow and Tofa (provisional) clients
- [ ] **AC (targets AC1, AC5):**
  - Tdarr `scan-files`.
  - Autoplow generic trigger.
  - Tofa scoped scan and session polling, behind a capability flag.
- **V:** fixtures.
- **Dep:** 2.1.
- **Files:** `crates/targets/src/{tdarr,autoplow,tofa}.rs`.
- **Size:** M.

### Checkpoint: targets
- [ ] All clients pass contract tests; `live` timings match the platform notes; human review.

## Phase 3: `arr`

### Task 3.1: Arr client and detection
- [ ] **AC (arr AC1):**
  - `system/status` detection of Sonarr v4/v5, Radarr, Lidarr, Whisparr v2/v3 and urlBase.
  - Root folders.
  - Filesystem API proxy for the path picker.
- **V:** fixtures per flavour.
- **Dep:** 0.6.
- **Files:** `crates/arr/src/{client,detect}.rs`.
- **Size:** S.

### Task 3.2: Webhook receiver and parsers
- [ ] **AC (arr AC5):**
  - Sonarr/Whisparr v2 parser: both `Download` shapes, deduplicated by `downloadId`.
  - Radarr/Whisparr v3 parser.
  - Lidarr parser, including the `albums` Test payload.
  - Unknown events return 2xx.
- **V:** golden payload tests from `docs/research/arr-connect-api.md`.
- **Dep:** 3.1.
- **Files:** `crates/arr/src/{receiver,sonarr,radarr,lidarr}.rs`.
- **Size:** M.

### Task 3.3: Managed connection reconciler
- [ ] **AC (arr AC2–AC4):**
  - Desired definition built from the Arr's own schema, with header token, fingerprint header and `tags: []`.
  - Create only when the receiver is ready.
  - Detect drift and repair with a full PUT only when drift exists.
  - Never touch connections we don't own.
- **V:** fake Arr; `live` create, drift, repair and delete cycle (`docs/platform-notes/arr.md`).
- **Dep:** 3.2, 1.1.
- **Files:** `crates/arr/src/managed.rs`.
- **Size:** M.

### Task 3.4: Migration helper and evidence-based mapping suggestions
- [ ] **AC (arr AC4; scan path-mapping requirements):**
  - List autoscan-style hooks and offer removal after our connection is verified.
  - Suggest path mappings derived from the same file seen by both sides.
- **V:** fixtures; `live` dry run.
- **Dep:** 3.3, 2.1.
- **Files:** `crates/arr/src/{migrate,suggest}.rs`.
- **Size:** M.

### Checkpoint: arr
- [ ] A real Sonarr and Radarr get a managed connection, survive simulated drift, and their Test events parse; human review.

## Phase 4: `scan`

### Task 4.1: Per-target durable queue
- [ ] **AC (scan AC2, AC3, AC5):**
  - Generation acknowledgement.
  - Unique pending index with upsert.
  - Parent absorbs children.
  - Readiness: minimum age (30 s) and maximum wait (10 min).
  - FIFO by ready time.
  - Wait reasons.
- **V:** paused-clock tests: event during dispatch, event after a fast scan, parent and child.
- **Dep:** 0.3, 0.2.
- **Files:** `crates/scan/src/queue/*.rs`.
- **Size:** M.

### Task 4.2: Target workers and delivery
- [ ] **AC (scan AC4, AC9, AC13):**
  - One isolated worker per target.
  - Backoff that honours `Retry-After`.
  - Per-path dead-letter, with retry, discard, discard all and 30-day pruning.
  - Batching (Jellyfin/Emby), one request per folder (Plex).
- **V:** an offline fake target doesn't block the others; a 400 dead-letters one path only.
- **Dep:** 4.1, 2.2, 2.3.
- **Files:** `crates/scan/src/worker.rs`.
- **Size:** M.

### Task 4.3: Trigger framework and auth
- [ ] **AC (scan AC1, plus spec "Common to all triggers"):**
  - Per-instance or global credentials.
  - Header, basic or query auth (any one passes).
  - Filters, target excludes, extra wait per event type.
- **V:** auth matrix and filter tests.
- **Dep:** 4.1, 0.7.
- **Files:** `crates/scan/src/triggers/{mod,auth}.rs`.
- **Size:** M.

### Task 4.4: Arr trigger wiring, manual scan API with preview, queue UI
- [ ] **AC (scan AC1, AC5):**
  - Arr events produce folder scans.
  - `POST /scans` with `dry_run` preview (rewrite, library, existence).
  - Queue pages with wait reasons.
- **V:** API tests; Playwright plus axe.
- **Dep:** 4.2, 4.3, 3.2.
- **Files:** `crates/scan/src/triggers/arr.rs`, `crates/scan/src/api.rs`, `crates/ui/src/pages/queues.rs`.
- **Size:** M.

### Task 4.5: Legacy, Bazarr and generic triggers
- [ ] **AC (scan AC12):**
  - autoscan `/triggers/*` and A-Train.
  - Bazarr: `/triggers/bazarr`, `/stats`, `/api/config-template`.
  - Generic `{paths:[]}`.
- **V:** recorded request fixtures from each tool.
- **Dep:** 4.3.
- **Files:** `crates/scan/src/triggers/{legacy,bazarr,generic}.rs`.
- **Size:** M.

### Task 4.6: Anchors, "path must exist", verified Plex empty trash
- [ ] **AC (scan AC6, AC7, Plex trash row):**
  - Anchors at any scope; all applicable anchors required.
  - Hold-and-retry existence check; deletes exempt.
  - Empty trash only after the scan is observed to complete.
- **V:** paused-clock tests; `live` late-visibility test on Plex passes with the check and fails without it.
- **Dep:** 4.2.
- **Files:** `crates/scan/src/{anchors,exists,trash}.rs`.
- **Size:** M.

### Task 4.7: Post-delivery verification
- [ ] **AC (scan AC11):**
  - Optional per target.
  - Server delay plus margin.
  - Warning with hints.
- **V:** fakes reproducing the Jellyfin empty-folder and Plex disrupted-scan cases.
- **Dep:** 4.2.
- **Files:** `crates/scan/src/verify.rs`.
- **Size:** S.

### Task 4.8: Local filesystem trigger
- [ ] **AC (scan triggers table):**
  - inotify, walk or both per path.
  - The walk snapshot is persisted (new, changed and deleted files).
  - Overflow handling.
  - Rebuilt on restart.
- **V:** temp-tree tests including overflow.
- **Dep:** 4.3.
- **Files:** `crates/scan/src/triggers/fs/*.rs`.
- **Size:** M.

### Task 4.9: Trigger and target UI with path picker
- [ ] **AC (scan path rules; targets AC6):**
  - CRUD pages for triggers and targets.
  - Webhook URL and credential copy.
  - Rewrite editor with a filesystem picker per side.
  - Target warnings.
- **V:** Playwright plus axe; WASM budget.
- **Dep:** 4.4, 3.1, 0.9.
- **Files:** `crates/ui/src/pages/{triggers,targets,paths}.rs`.
- **Size:** M.

### Task 4.10: Scan load test
- [ ] **AC (scan AC10; project scale):**
  - 1 000 events per minute for 10 minutes: no loss, back-pressure 503s only.
  - Resource budget held.
- **V:** load-test harness under a cap; results summarised (no environment details).
- **Dep:** 4.2, 4.3.
- **Files:** `crates/scan/tests/load.rs`.
- **Size:** S.

### Checkpoint: scan
- [ ] A real Sonarr/Radarr feeds Plex, Jellyfin and Emby end to end through managed connections.
- [ ] Load test passes.
- [ ] Human review.

## Phase 5: `rclone`

### Task 5.1: Supervised `rcd` and RC client
- [ ] **AC (rclone AC1–AC8):**
  - Unix socket in a 0700 directory.
  - Minimum version 1.75.
  - Restart with "job state lost" reporting.
  - Typed client and job/group tracking.
  - Stats-group sweep.
  - Bandwidth limit applied live.
  - Host SIGTERM isolated from rclone's hook.
  - Crypt `decode` via `backend/command`, batched (rclone AC8).
- **V:** integration tests with crypt over local; `kill -9` the child; 24-hour soak (group count bounded).
- **Dep:** 0.4.
- **Files:** `crates/rclone/src/{child,client,jobs}.rs`.
- **Size:** M.

### Checkpoint: rclone
- [ ] The `rcd` child survives `kill -9` and recovers; bandwidth changes apply live; human review.

## Phase 6: `gdrive`

### Task 6.1: Google accounts (OAuth web flow)
- [ ] **AC (gdrive AC1):**
  - The user's own OAuth web client.
  - Connect and callback with state.
  - Encrypted tokens, included in rotation.
  - Health on revocation.
- **V:** fake OAuth server.
- **Dep:** 0.6.
- **Files:** `crates/gdrive/src/{oauth,accounts}.rs`.
- **Size:** M.

### Task 6.2: Drive monitors
- [ ] **AC (gdrive AC2–AC5):**
  - Snapshot plus Changes API.
  - Old and new paths.
  - Events committed before the token is saved.
  - Re-snapshot on an invalid token.
  - Rate-limit backoff.
- **V:** fake Drive API: crash replay, token loss.
- **Dep:** 6.1, 4.3.
- **Files:** `crates/gdrive/src/{snapshot,changes,trigger}.rs`.
- **Size:** M.

### Task 6.3: Crypt remotes
- [ ] **Spike first:** confirm against rclone 1.75 that `decode` through `rc` handles full paths, directory-name encryption on and off, every filename encoding, and snapshot-sized batches. Record the result in `docs/platform-notes/`.
- [ ] **AC (gdrive AC6):**
  - Snapshot stores encrypted and decrypted names; polls decode only unseen names.
  - Rewrite rules and filters match decrypted paths.
  - Undecryptable names produce no scan and a change-log entry; a missing crypt remote stops the monitor with `health`.
- **V:** fake Drive API serving names encrypted by a real crypt-over-local remote.
- **Dep:** 6.2, 5.1.
- **Files:** `crates/gdrive/src/crypt.rs`, `crates/gdrive/src/snapshot.rs`, `docs/platform-notes/`.
- **Size:** M.

### Task 6.4: Change log, manual controls and snapshot browser
- [ ] **AC (gdrive AC7–AC10):**
  - Change log with outcomes, written in the event transaction; retention pruning.
  - Poll now, persisted pause and resume, rebuild snapshot (diff only).
  - Snapshot search with paging and total count; both names for crypt remotes.
  - API endpoints and UI for all of the above.
- **V:** fake Drive API: pause across restart, rebuild diff, retention with an injected clock.
- **Dep:** 6.2.
- **Files:** `crates/gdrive/src/{changelog,controls}.rs`, `crates/api/src/gdrive.rs`, `crates/ui/src/gdrive.rs`.
- **Size:** M.

### Checkpoint: gdrive
- [ ] A real Drive account connects from the UI, and a change produces a scan for the mapped folder, including one under a crypt remote; the change log shows it; human review.

## Phase 7: `upload`

### Task 7.1: Destinations and per-file queue
- [ ] **AC (upload AC4–AC6):**
  - Queue keyed by identity (dev, ino) plus path.
  - Tracking by job and group.
  - Source removed only after success.
  - Re-queue after a child crash.
- **V:** duplicate-basename and crash-recovery tests.
- **Dep:** 5.1, 0.3.
- **Files:** `crates/upload/src/{destinations,queue}.rs`.
- **Size:** M.

### Task 7.2: Readiness: age, stability, mtime hygiene, hardlinks, scanned-first
- [ ] **AC (upload AC1, AC9):**
  - First-seen age (2 min) that restarts on an mtime change.
  - Two stability checks 30 s apart.
  - Future-mtime warning, or the opt-in fix.
  - Hardlink policy.
  - Scanned-first gate.
- **V:** paused-clock and filesystem tests.
- **Dep:** 7.1, 4.1.
- **Files:** `crates/upload/src/readiness/*.rs`.
- **Size:** M.

### Task 7.3: Open-file detection (optional capability)
- [ ] **AC (upload AC2, AC3):**
  - Capability detection.
  - `/proc` fd scan by dev+inode for local and mergerfs identities.
  - Write mode and locks only.
  - Process and container attribution.
  - Media-server wait option.
  - Degraded-mode notice.
- **V:** helper processes holding read, write and flock handles; cgroup fixtures.
- **Dep:** 7.2.
- **Files:** `crates/upload/src/openfiles/*.rs`.
- **Size:** M.

### Task 7.4: Concurrency, failover, schedules
- [ ] **AC (upload AC7, AC8):**
  - Global cap plus per-remote caps.
  - Remote-health cooldown.
  - Schedule windows that let transfers in flight finish.
- **V:** fake-transport tests.
- **Dep:** 7.1.
- **Files:** `crates/upload/src/{scheduler,health}.rs`.
- **Size:** M.

### Task 7.5: Downloader pausing
- [ ] **AC (upload AC10):**
  - SABnzbd and NZBGet.
  - "While uploading" with grace, and a disk guard.
  - Guaranteed resume, including after a crash.
- **V:** fakes plus a simulated crash.
- **Dep:** 7.4.
- **Files:** `crates/upload/src/downloaders/*.rs`.
- **Size:** S.

### Task 7.6: Upload UI
- [ ] **AC:** destinations, queue with readiness reasons, live transfers, history, remote health.
- **V:** Playwright plus axe; WASM budget.
- **Dep:** 7.1–7.5, 0.9.
- **Files:** `crates/ui/src/pages/uploads/*.rs`.
- **Size:** M.

### Task 7.7: Upload soak and load test
- [ ] **AC (upload AC11; project scale):** sustained throughput equivalent to 10 TB per day against a local/crypt test remote, within the resource budget.
- **V:** capped soak; results summarised.
- **Dep:** 7.4.
- **Files:** `crates/upload/tests/soak.rs`.
- **Size:** S.

### Checkpoint: upload
- [ ] Capped `live` upload to a crypt remote.
- [ ] Hardlinked and open files handled.
- [ ] Human review.

## Phase 8: `throttle`

### Task 8.1: Session registry
- [ ] **AC (throttle AC1, AC2):**
  - Plex, Jellyfin and Emby websockets, plus Tofa polling.
  - Each server counted once.
  - Paused sessions excluded; LAN optional.
  - Stale expiry.
- **V:** fake websocket tests.
- **Dep:** 2.2, 2.3, 2.4.
- **Files:** `crates/throttle/src/sessions.rs`.
- **Size:** M.

### Task 8.2: Policy modes and effect
- [ ] **AC (throttle AC3–AC6):**
  - Tiers, per stream, by bitrate (cap 200 Mbps plus media bitrate).
  - Limit applied within 5 s.
  - Optional "no new transfers above N streams".
- **V:** table tests including the 10 Gbps outlier; integration test with `rcd`.
- **Dep:** 8.1, 5.1.
- **Files:** `crates/throttle/src/policy.rs`.
- **Size:** S.

### Checkpoint: throttle
- [ ] A live Plex stream changes the limit on a running test transfer within 5 s; human review.

## Phase 9: `parity`

### Task 9.1: Engine
- [ ] **AC (parity AC1, AC2, AC5):**
  - Phased fetch and path-keyed join.
  - Findings: mismatches, gaps both ways, file mismatches, merged items.
  - Unknown agents reported, never modified.
  - Ignore list.
  - 500k-item run within budget.
- **V:** fixtures per server; capped performance test.
- **Dep:** 3.1, 2.1.
- **Files:** `crates/parity/src/{fetch,compare,findings}.rs`.
- **Size:** M.

### Task 9.2: Fixes and triggers
- [ ] **AC (parity AC3, AC4, AC6):**
  - Review-first; auto-fix opt-in.
  - Rate-limited fixes, verified by read-back, audited.
  - Emby/Jellyfin fixes change provider IDs only.
  - Merged items: off, notify or auto-split.
  - Schedule, on-demand and after-import triggers, each switchable.
- **V:** fakes; `live` dry run.
- **Dep:** 9.1, 1.2.
- **Files:** `crates/parity/src/{fix,triggers}.rs`.
- **Size:** M.

### Task 9.3: Parity UI
- [ ] **AC:** runs, findings (fix, skip, ignore), filters, audit log.
- **V:** Playwright plus axe.
- **Dep:** 9.2, 0.9.
- **Files:** `crates/ui/src/pages/parity.rs`.
- **Size:** M.

### Checkpoint: parity
- [ ] A live dry run against the test libraries lists findings with no writes; an approved fix verifies by read-back; human review.

## Phase 10: `track-preferences`

### Task 10.1: Matching algorithm
- [ ] **AC (track-preferences AC3):** PAL's scoring plus forced/HI/VI semantics and tie-break, with the fixed cases.
- **V:** port of PAL's tests plus new cases.
- **Dep:** none (pure).
- **Files:** `crates/track-preferences/src/matching.rs`.
- **Size:** S.

### Task 10.2: Users, preferences, triggers, apply
- [ ] **AC (track-preferences AC1, AC2, AC4, AC5):**
  - Shared-server tokens, never logged.
  - Preferences per (user, show).
  - Play, new-episode and sweep triggers.
  - Keyed serialisation.
  - Verified writes.
  - Opt-out per user.
- **V:** fake Plex; `live` test on a test library.
- **Dep:** 10.1, 2.2.
- **Files:** `crates/track-preferences/src/{users,prefs,apply}.rs`.
- **Size:** M.

### Task 10.3: Track preferences UI
- [ ] **AC:** users, preferences (edit and clear), scope settings, history.
- **V:** Playwright plus axe.
- **Dep:** 10.2, 0.9.
- **Files:** `crates/ui/src/pages/tracks.rs`.
- **Size:** S.

### Checkpoint: track-preferences
- [ ] A track change during live Plex playback propagates to the next episodes for that user only; human review.

## Phase 11: Release

### Task 11.1: Container image and release pipeline
- [ ] **AC:**
  - Static musl binaries for x86_64 and aarch64.
  - Image with a pinned rclone and `RCLONE_CONFIG` set.
  - Optional `pid: host` and `SYS_PTRACE` documented.
  - Healthcheck.
  - release-please releases.
- **V:** image boots from a bootstrap file on a clean volume.
- **Dep:** all phases.
- **Files:** `Dockerfile`, `.github/workflows/release.yml`.
- **Size:** S.

### Task 11.2: Replacement checklists and Saltbox integration notes
- [ ] **AC (project success criterion 3):**
  - A written checklist per replaced tool (autoscan/autopulse, cloudplow, matcharr, Plex-Auto-Languages), each verified by the live suite.
  - Example bootstrap for the Saltbox role.
- **V:** walkthrough on a test Saltbox install.
- **Dep:** 11.1.
- **Files:** `docs/guides/*.md`.
- **Size:** S.

### Checkpoint: release candidate
- [ ] Every module's acceptance criteria are met.
- [ ] Project scale targets are verified.
- [ ] The `CONSTRAINTS.md` gates are green.
- [ ] Human review.
