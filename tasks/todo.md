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
- [ ] **AC (core AC4, AC14–AC16, gdrive AC14 in part):**
  - SQLite in WAL mode, one writer and a reader pool.
  - Embedded, versioned migrations, with a copy taken first; a newer database is refused.
  - Compare-and-set helper.
  - Migration fixtures.
  - Daily and on-demand backups with a keep count, leaving out rebuildable data (the backup half of gdrive AC14; rebuilding after a restore is in 6.2).
  - Unwritable database: triggers get 503 with `Retry-After`; recovery without restart.
  - One instance per data directory.
- **V:** migration-up tests; writer-serialisation test; read-only database test; second-instance test.
- **Dep:** 0.1.
- **Files:** `crates/core/src/store/*.rs`, `crates/core/migrations/`.
- **Size:** M.

### Task 0.4: Supervisor and component lifecycle
- [ ] **AC (core AC1–AC3, AC19):**
  - Restart with backoff (1 s doubling to 60 s), including after a panic, with the component named in the log.
  - Capability checks per feature, reported on Health (core AC19).
  - A config change rebuilds only the dependent components.
  - Shutdown within the deadline (30 s).
- **V:** fake components and a paused clock.
- **Dep:** 0.1.
- **Files:** `crates/core/src/supervisor/*.rs`.
- **Size:** M.

### Task 0.5: Config model and seed-once bootstrap
- [ ] **AC (core-bootstrap-api AC1, AC6):**
  - Typed resources.
  - Strict YAML with line and column errors; unknown version refused; a file other accounts can read refused.
  - Seed once; delete the file after success, keep it on partial failure.
  - Secret-free report.
  - JSON Schema generated.
- **V:** golden tests for the report, partial failure and a read-only file.
- **Dep:** 0.3.
- **Files:** `crates/core/src/config/*.rs`.
- **Size:** M.

### Task 0.6: HTTP server, auth and secrets
- [ ] **AC (core AC6, AC7, AC10–AC13, AC17, AC22):**
  - `/api/v1`, RFC 9457 errors, body limits, open `/health`, OpenAPI.
  - API keys (admin, read-only); `/metrics` needs a key.
  - Argon2 admin user; sessions (30 days, sign out, ended on password change); sign-in can be switched off for the UI only.
  - Login lockout per client address, with trusted proxies.
  - `autoplow reset-password`.
  - `autoplow restore <file>` (core AC22).
  - Secret key from the environment only: refuse to start without it or with a wrong one; rotation with the old key supplied once.
  - Secrets never in list or resource responses; the admin-only secret endpoint.
- **V:** auth matrix tests; a seeded-secret grep over logs and responses; start-up tests for missing, wrong and rotated keys; lockout tests with and without a trusted proxy.
- **Dep:** 0.5.
- **Files:** `crates/core/src/{api,auth,secrets}/*.rs`.
- **Size:** M.

### Task 0.7: Resource CRUD and `POST /apply`
- [ ] **AC (core-bootstrap-api AC2, AC3, AC7–AC9, AC11–AC13):**
  - `PUT`/`PATCH`/`DELETE` by name; fixed IDs with rename; versions with `If-Match`; deletes refused with the list of dependents.
  - Cursor paging with stable order.
  - Long jobs: 202, progress, one at a time, interrupted on restart.
  - `apply` with `seed`/`upsert` and `dry_run`.
  - Changes notify the supervisor.
  - Route table with its authentication matrix.
- **V:** idempotency tests; a dry run makes no writes; rename, stale-version and in-use delete tests; paging under concurrent inserts; job tests; route authentication matrix.
- **Dep:** 0.6, 0.4.
- **Files:** `crates/core/src/api/resources.rs`, `crates/api-types/src/*.rs`.
- **Size:** M.

### Task 0.8: Observability
- [ ] **AC (core AC7, AC8, AC18):**
  - `tracing` with a level per component, changeable while running; output to standard output and a self-rotating log file.
  - `secrecy`-typed secrets.
  - `/metrics`.
  - An SSE broker that never blocks a publisher.
  - Idle RSS ≤ 64 MB and CPU ≤ 1 %.
- **V:** broker back-pressure test; an idle soak measured under a cap.
- **Dep:** 0.6.
- **Files:** `crates/core/src/{obs,events}/*.rs`.
- **Size:** S.

### Task 0.9: UI shell (Leptos)
- [ ] **AC (core AC9, core-bootstrap-api AC4, AC5, ui AC1–AC9, AC11–AC18):**
  - CSR app built with trunk and `wasm-opt -Oz`, embedded with rust-embed.
  - Login, the first-start setup page, navigation, live event client, API client from `api-types`.
  - Shared building blocks from the UI spec: colour tokens, accent with the contrast rule, density, sidebar, width caps, dialog with unsaved-changes handling, secret field with eye toggle.
  - Shared behaviour from the UI spec: loading, empty and failed states; results shown where the action was; lists with More; live updates in place with the connection banner; an address per page, dialog and filter; return after sign-in; reduced motion.
- **V:** Playwright login test and UI-rule checks (sizes, widths, dialog close paths); zero serious or critical axe violations; WASM within budget.
- **Dep:** 0.6, 0.8.
- **Files:** `crates/ui/src/*.rs`, `crates/autoplow/src/embed.rs`, `e2e/login.spec.ts`, `e2e/ui-rules.spec.ts`.
- **Size:** M.

### Task 0.11: Outbound HTTP client
- [ ] **AC (core AC20):**
  - Timeouts, size cap, `Retry-After`, certificate check with a per-connection switch, error classes, token redaction.
- **V:** fake-server tests for each rule.
- **Dep:** 0.6.
- **Files:** `crates/core/src/http_client.rs`.
- **Size:** S.

### Task 0.10: Health page and core Settings sections
- [ ] **AC (core AC21; ui AC10: Health, Settings › General, API keys, Appearance, About):**
  - Health: needs attention, components, connections, recent health events. Connections and events fill in as modules land.
  - General: callback base URL, admin and Change password, sign-in switch, trusted proxies, time zone, timing defaults, retention, backups, log levels, bootstrap status.
  - API keys: list with Copy; dialog to rename, change access, show, regenerate, revoke.
  - Appearance: accent with the contrast check, density. About.
  - Update check: daily, shown on About and Health, with its switch under General.
  - Settings save as they change.
- **V:** Playwright plus axe; WASM budget.
- **Dep:** 0.9, 0.11.
- **Files:** `crates/ui/src/pages/{health,settings/*}.rs`.
- **Size:** M.

### Checkpoint: core
- [ ] Bootstrap seeds an admin user and an API key; `apply` is idempotent; the UI logs in.
- [ ] Every later module's pages are added to `e2e/ui-rules.spec.ts` (ui AC4, AC5, AC9, AC11–AC16) as they land.
- [ ] All gates pass.
- [ ] Human review.

## Phase 1: `notifications`

### Task 1.1: Outbox and dispatcher
- [ ] **AC (notifications AC1–AC3, AC7–AC10):**
  - Transactional outbox.
  - Aggregation window, and storm summaries above 20 waiting messages.
  - Problems notify only after lasting 2 minutes; recovery only if the problem was sent; flapping reported once.
  - Backoff from 30 s to 30 minutes honouring `Retry-After` and Discord limits; permanent failures dead-letter at once.
  - Per-source ordering.
  - Dead-letter after 8 attempts.
- **V:** crash-and-restart durability test with a paused clock.
- **Dep:** 0.3, 0.4.
- **Files:** `crates/notifications/src/{outbox,dispatch}.rs`.
- **Size:** M.

### Task 1.2: Channels, subscriptions and UI
- [ ] **AC (notifications AC4–AC6, AC11, AC12; ui AC10: Notifications, Channel):**
  - Discord, Apprise and webhook channels.
  - Subscriptions per event type; one filter per channel; Test; fixed message format with a link.
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
- [ ] **AC (targets AC2–AC4, AC8–AC12, AC14; scan AC8, the containment part):**
  - Uses the core outbound client; paged listings.
  - Pacing: one request at a time per target with a gap.
  - Health states, backoff to 15 minutes, status call while unhealthy, unavailable after 2 minutes.
  - Disabled targets, keeping or dropping their scans.
  - Warnings when a library disappears or its folders change.
  - Token redaction in URLs.
  - Library cache refreshed periodically and on a miss.
  - Component-based containment, multi-library resolution.
- **V:** unit tests and recorded fixtures.
- **Dep:** 0.2, 0.11, 1.1.
- **Files:** `crates/targets/src/{pacing,health,libraries}.rs`.
- **Size:** M.

### Task 2.2: Plex client
- [ ] **AC (targets AC1, AC5, AC7, AC13):**
  - Sign in with Plex, or a pasted token.
  - Sections with paging headers.
  - `refresh?path=`.
  - Sessions websocket, non-blocking reader, reconnect with polling fallback.
  - Section state for verified empty trash.
- **V:** fixture contract tests; `live` test reproduces the platform-notes timings.
- **Dep:** 2.1.
- **Files:** `crates/targets/src/plex/*.rs`.
- **Size:** M.

### Task 2.3: Jellyfin and Emby clients
- [ ] **AC (targets AC1, AC5, AC6):**
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
- [ ] **AC (targets AC1):**
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
- [ ] **AC (arr AC1, AC6, core-bootstrap-api AC10):**
  - Unavailable and recovered states and events.
  - An Arr is one resource carrying its trigger settings; no separate trigger entry.
  - `system/status` detection of Sonarr v4/v5, Radarr, Lidarr, Whisparr v2/v3 and urlBase.
  - Root folders.
  - Filesystem API proxy for the path picker.
- **V:** fixtures per flavour.
- **Dep:** 0.6, 0.7, 0.11, 1.1.
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
- [ ] **AC (arr AC2–AC4, AC8, AC9):**
  - Desired definition built from the Arr's own schema and version, with header token, fingerprint header and `tags: []`.
  - A failed callback test creates nothing and reports the address tried and the Arr's error.
  - Create only when the receiver is ready.
  - Detect drift and repair with a full PUT only when drift exists.
  - Never touch connections we don't own.
- **V:** fake Arr; `live` create, drift, repair and delete cycle (`docs/platform-notes/arr.md`).
- **Dep:** 3.2, 1.1.
- **Files:** `crates/arr/src/managed.rs`.
- **Size:** M.

### Task 3.4: Migration helper and evidence-based mapping suggestions
- [ ] **AC (arr AC4, AC7; scan path-mapping requirements):**
  - List autoscan-style hooks and offer removal after our connection is verified.
  - Suggest a mapping when sampled recent imports line up under exactly one visible folder, with the match count; never applied unconfirmed.
- **V:** fixtures; `live` dry run.
- **Dep:** 3.3.
- **Files:** `crates/arr/src/{migrate,suggest}.rs`.
- **Size:** M.

### Checkpoint: arr
- [ ] A real Sonarr and Radarr get a managed connection, survive simulated drift, and their Test events parse; human review.

## Phase 4: `scan`

### Task 4.1: Per-target durable queue
- [ ] **AC (scan AC2, AC3, AC5, AC15, AC17):**
  - Merging many waiting folders into their parent, never a library root.
  - Send now goes first for its target.
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
- [ ] **AC (scan AC4, AC9, AC13, AC14):**
  - A delete scans the removed path; a server that cannot do that is reported, not sent.
  - One isolated worker per target.
  - Backoff that honours `Retry-After`.
  - Per-path dead-letter, with retry, discard, discard all and 30-day pruning.
  - Batching (Jellyfin/Emby), one request per folder (Plex).
- **V:** an offline fake target doesn't block the others; a 400 dead-letters one path only.
- **Dep:** 4.1, 2.2, 2.3, 1.1.
- **Files:** `crates/scan/src/worker.rs`.
- **Size:** M.

### Task 4.3: Trigger framework and auth
- [ ] **AC (scan AC1, AC18, plus spec "Common to all triggers"):**
  - Back-pressure above 10 000 unprocessed events.
  - Per-instance or global credentials.
  - Header, basic or query auth (any one passes).
  - Filters, target excludes, extra wait per event type.
- **V:** auth matrix and filter tests.
- **Dep:** 4.1, 0.7.
- **Files:** `crates/scan/src/triggers/{mod,auth}.rs`.
- **Size:** M.

### Task 4.4: Arr trigger wiring, manual scan API with preview, queue UI
- [ ] **AC (scan AC1, AC5, AC8, AC19):**
  - Unmatched folders listed with their trigger; delivered history for 7 days.
  - Arr events produce folder scans, resolved to libraries by path components.
  - `POST /scans` with `dry_run` preview (rewrite, library, existence).
  - Scans page with wait reasons and dead letters; the Scan dialog with its live preview (ui AC10).
- **V:** API tests; Playwright plus axe.
- **Dep:** 4.2, 4.3, 3.2.
- **Files:** `crates/scan/src/triggers/arr.rs`, `crates/scan/src/api.rs`, `crates/ui/src/pages/queues.rs`.
- **Size:** M.

### Task 4.5: Legacy, Bazarr and generic triggers
- [ ] **AC (scan AC12, AC21):**
  - Generic webhook with an optional `type`.
  - autoscan `/triggers/*` and A-Train.
  - Bazarr: `/triggers/bazarr`, `/stats`, `/api/config-template`.
  - Generic `{paths:[]}`.
- **V:** recorded request fixtures from each tool.
- **Dep:** 4.3.
- **Files:** `crates/scan/src/triggers/{legacy,bazarr,generic}.rs`.
- **Size:** M.

### Task 4.6: Anchors, "path must exist", verified Plex empty trash
- [ ] **AC (scan AC6, AC7, AC16, Plex trash row):**
  - "Path must exist" checked on the host; dead-lettered after 1 hour if the folder never appears.
  - Anchors (a file, its targets and an optional folder); all applicable anchors required.
  - Hold-and-retry existence check; deletes exempt.
  - Empty trash only after the scan is observed to complete.
  - Settings › Anchors with its dialog (ui AC10).
- **V:** paused-clock tests; `live` late-visibility test on Plex passes with the check and fails without it.
- **Dep:** 4.2.
- **Files:** `crates/scan/src/{anchors,exists,trash}.rs`, `crates/ui/src/pages/settings/anchors.rs`.
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
- [ ] **AC (scan AC20, triggers table):**
  - Close-after-write events, ignore patterns, walking past the watch limit.
  - inotify, walk or both per path.
  - The walk snapshot is persisted (new, changed and deleted files).
  - Overflow handling.
  - Rebuilt on restart.
- **V:** temp-tree tests including overflow.
- **Dep:** 4.3.
- **Files:** `crates/scan/src/triggers/fs/*.rs`.
- **Size:** M.

### Task 4.9: Trigger and target UI with path picker
- [ ] **AC (scan path rules; targets AC6; core AC23; ui AC10: Triggers, Trigger, Add trigger, Add Arr instance, Targets, Target, Add target):**
  - CRUD pages for triggers and targets.
  - Webhook URL and credential copy.
  - Rewrite editor with a filesystem picker per side; the filesystem browser endpoint (names only, admin only).
  - The Add Arr instance steps, with mapping suggestions and older webhooks.
  - Target warnings.
- **V:** Playwright plus axe; WASM budget.
- **Dep:** 4.4, 3.4, 0.9.
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
- [ ] **AC (rclone AC1–AC8, AC10–AC12):**
  - Child tied to Autoplow; leftovers stopped at start; hung child detected; transfers stopped and re-queued on shutdown; output in Autoplow's log.
  - Unix socket in a 0700 directory.
  - Minimum version 1.75, no maximum; configurable binary path; `rclone.unsupported` below the minimum.
  - Restart with "job state lost" reporting.
  - Typed client and job/group tracking.
  - Stats-group sweep.
  - Bandwidth limit applied live.
  - Host SIGTERM isolated from rclone's hook.
  - Crypt `decode` via `backend/command`, batched (rclone AC8).
- **V:** integration tests with crypt over local; `kill -9` the child; 24-hour soak (group count bounded).
- **Dep:** 0.4, 1.1.
- **Files:** `crates/rclone/src/{child,client,jobs}.rs`.
- **Size:** M.

### Task 5.2: Start on demand and Settings › rclone
- [ ] **AC (rclone AC9, AC13, AC14; ui AC10: Settings › rclone):**
  - Extra options and environment, with the controlled ones refused.
  - Restart when idle after a config change; Reload.
  - The child runs only while a destination or a crypt Drive monitor needs it.
  - Settings › rclone: config path, version, state or "not needed", read-only remotes with users and health.
- **V:** integration test: no child with nothing configured, started when a destination is added; Playwright plus axe.
- **Dep:** 5.1, 0.10.
- **Files:** `crates/rclone/src/demand.rs`, `crates/ui/src/pages/settings/rclone.rs`.
- **Size:** S.

### Checkpoint: rclone
- [ ] The `rcd` child survives `kill -9` and recovers; bandwidth changes apply live; human review.

## Phase 6: `gdrive`

### Task 6.1: Google accounts (OAuth web flow)
- [ ] **AC (gdrive AC1):**
  - The user's own OAuth web client.
  - Connect and callback with state.
  - Encrypted tokens, included in rotation.
  - `gdrive.account.revoked` on revocation.
  - Settings › Google Drive: redirect URI check, OAuth clients and accounts with dialogs, setup guide (ui AC10).
- **V:** fake OAuth server; Playwright plus axe.
- **Dep:** 0.6, 0.10, 1.1.
- **Files:** `crates/gdrive/src/{oauth,accounts}.rs`.
- **Size:** M.

### Task 6.2: Drive monitors
- [ ] **AC (gdrive AC2–AC5, AC11–AC13, AC14 in part (a snapshot is rebuilt after a restore), AC15, AC16):**
  - Folder-limited monitors; one snapshot per drive; first snapshot silent and resumable.
  - Shortcuts, multiple parents, restored items and Google documents.
  - Lost shared-drive access stops the monitor.
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
  - Undecryptable names produce no scan and a change-log entry; a missing crypt remote stops the monitor with `gdrive.monitor.stopped`.
- **V:** fake Drive API serving names encrypted by a real crypt-over-local remote.
- **Dep:** 6.2, 5.1.
- **Files:** `crates/gdrive/src/crypt.rs`, `crates/gdrive/src/snapshot.rs`, `docs/platform-notes/`.
- **Size:** M.

### Task 6.4: Change log, manual controls and snapshot browser
- [ ] **AC (gdrive AC7–AC10; ui AC10: Google Drive trigger, Drive trigger settings):**
  - Change log with outcomes, written in the event transaction; retention pruning.
  - Poll now, persisted pause and resume, rebuild snapshot (diff only).
  - Snapshot search with paging and total count; both names for crypt remotes.
  - API endpoints and UI for all of the above.
- **V:** fake Drive API: pause across restart, rebuild diff, retention with an injected clock.
- **Dep:** 6.2.
- **Files:** `crates/gdrive/src/{changelog,controls}.rs`, `crates/gdrive/src/api.rs`, `crates/ui/src/gdrive.rs`.
- **Size:** M.

### Checkpoint: gdrive
- [ ] A real Drive account connects from the UI, and a change produces a scan for the mapped folder, including one under a crypt remote; the change log shows it; human review.

## Phase 7: `downloaders`

### Task 7.1: Verify the client APIs
- [ ] **Spike:** against a pinned version of SABnzbd, NZBGet and qBittorrent, verify pause and resume, setting and reading the download and upload limits, their units, and whether a scheduler or alternative-speed mode can be detected. Record each as a platform note.
- **V:** the platform notes exist, with versions and method.
- **Dep:** none.
- **Files:** `docs/platform-notes/`.
- **Size:** S.

### Task 7.2: Clients and the desired-state owner
- [ ] **AC (downloaders AC1–AC3, AC5–AC11):**
  - Only Autoplow's own pauses are undone; free-space margin; switching a client off.
  - SABnzbd, NZBGet and qBittorrent clients behind one trait.
  - Desired state per client from pause reasons and limits.
  - Apply at once; reconcile every minute.
  - Idle limit applied on shutdown, removal and switching limits off.
  - Overrides reported, never changed.
- **V:** fake clients: two pause reasons, manual change put back, simulated crash, unreachable client.
- **Dep:** 7.1, 0.6, 1.1.
- **Files:** `crates/downloaders/src/{clients/*,state,reconcile}.rs`.
- **Size:** M.

### Task 7.3: Downloaders API and UI
- [ ] **AC (downloaders AC1; ui AC10: Settings › Downloaders):**
  - `downloaders` resource: add, test, edit, remove.
  - Settings › Downloaders with a dialog per client.
- **V:** Playwright plus axe.
- **Dep:** 7.2, 0.9.
- **Files:** `crates/downloaders/src/api.rs`, `crates/ui/src/pages/settings/downloaders.rs`.
- **Size:** S.

### Checkpoint: downloaders
- [ ] A real SABnzbd and a real qBittorrent are paused, limited and put back, including after `kill -9` of Autoplow; human review.

## Phase 8: `upload`

### Task 8.1: Destinations and per-file queue
- [ ] **AC (upload AC4–AC6, AC15–AC18, AC20):**
  - Move or copy, removing empty folders; exclude patterns; first walk for files already there; failed list after 5 attempts; overlapping destinations refused.
  - Queue keyed by identity (dev, ino) plus path.
  - Tracking by job and group.
  - Source removed only after success.
  - Re-queue after a child crash.
- **V:** duplicate-basename and crash-recovery tests.
- **Dep:** 5.1, 0.3.
- **Files:** `crates/upload/src/{destinations,queue}.rs`.
- **Size:** M.

### Task 8.2: Readiness: age, stability, mtime hygiene, hardlinks, scanned-first
- [ ] **AC (upload AC1, AC9, AC14):**
  - Scanned first, with the 30-minute limit; a disabled target is not waited for.
  - First-seen age (2 min) that restarts on an mtime change.
  - Two stability checks 30 s apart.
  - Future-mtime warning, or the opt-in fix.
  - Hardlink policy.
  - Scanned-first gate.
- **V:** paused-clock and filesystem tests.
- **Dep:** 8.1, 4.1.
- **Files:** `crates/upload/src/readiness/*.rs`.
- **Size:** M.

### Task 8.3: Open-file detection (optional capability)
- [ ] **AC (upload AC2, AC3):**
  - Capability detection.
  - `/proc` fd scan by dev+inode for local and mergerfs identities.
  - Write mode and locks only.
  - Process attribution, and the container when there is one.
  - Media-server wait option.
  - Degraded-mode notice.
- **V:** helper processes holding read, write and flock handles; cgroup fixtures.
- **Dep:** 8.2.
- **Files:** `crates/upload/src/openfiles/*.rs`.
- **Size:** M.

### Task 8.4: Concurrency, failover, schedules
- [ ] **AC (upload AC7, AC8, AC12, AC13, AC19):**
  - Cooldown lengths: 24 h for a limit, growing for repeated failures.
  - Global cap plus per-remote caps.
  - Hold new uploads (persisted) and stop one or all transfers.
  - Remote-health cooldown.
  - Schedule windows that let transfers in flight finish.
- **V:** fake-transport tests.
- **Dep:** 8.1.
- **Files:** `crates/upload/src/{scheduler,health}.rs`.
- **Size:** M.

### Task 8.5: Pausing download clients
- [ ] **AC (upload AC10):**
  - Pause requests to `downloaders`: "while uploading" with grace, and the free-space guard.
  - No client calls from `upload`.
- **V:** fake `downloaders` owner: request raised and ended at the right times.
- **Dep:** 8.4, 7.2.
- **Files:** `crates/upload/src/pausing.rs`.
- **Size:** S.

### Task 8.6: Upload UI
- [ ] **AC (ui AC10: Uploads, Destination, Settings › Uploads):** destinations with their dialog, queue with readiness reasons, live transfers with Hold and Stop, remote health, global upload settings.
- **V:** Playwright plus axe; WASM budget.
- **Dep:** 8.1–8.5, 0.9.
- **Files:** `crates/ui/src/pages/uploads/*.rs`.
- **Size:** M.

### Task 8.7: Upload soak and load test
- [ ] **AC (upload AC11; project scale):** sustained throughput equivalent to 10 TB per day against a local/crypt test remote, within the resource budget.
- **V:** capped soak; results summarised.
- **Dep:** 8.4.
- **Files:** `crates/upload/tests/soak.rs`.
- **Size:** S.

### Checkpoint: upload
- [ ] Capped `live` upload to a crypt remote.
- [ ] Hardlinked and open files handled.
- [ ] Human review.

## Phase 9: `throttle`

### Task 9.1: Session registry
- [ ] **AC (throttle AC1, AC2, AC11, AC12):**
  - Which kinds of playback count; an unreadable server counts as zero; sessions dropped after 2 minutes without an update.
  - Plex, Jellyfin and Emby websockets, plus Tofa polling.
  - Each server counted once.
  - Paused sessions excluded; LAN optional.
  - Stale expiry.
- **V:** fake websocket tests.
- **Dep:** 2.2, 2.3, 2.4.
- **Files:** `crates/throttle/src/sessions.rs`.
- **Size:** M.

### Task 9.2: Policy modes and the rclone limiter
- [ ] **AC (throttle AC3–AC6, AC13–AC15; upload AC21):**
  - Units and conversion; settling before a limit is raised; timed manual override, persisted.
  - Tiers, per stream, by bitrate (cap 200 Mbps plus media bitrate).
  - Limit applied within 5 s.
  - Optional "no new transfers above N streams".
- **V:** table tests including the 10 Gbps outlier; integration test with `rcd`.
- **Dep:** 9.1, 5.1, 8.4.
- **Files:** `crates/throttle/src/policy.rs`.
- **Size:** S.

### Task 9.3: Download-client limiters
- [ ] **AC (throttle AC7–AC10, downloaders AC4):**
  - One limiter per client and direction, each with its own mode.
  - Works with no upload destinations.
  - By-bitrate rejected for client limiters.
  - An unreachable client does not delay other limiters.
- **V:** table tests per limiter; fake clients; a run with rclone disabled.
- **Dep:** 9.2, 7.2.
- **Files:** `crates/throttle/src/limiters.rs`.
- **Size:** S.

### Task 9.4: Throttle UI
- [ ] **AC (ui AC10: Throttle, Limiter):** every limiter with its current limit and mode, and its dialog; sessions; options.
- **V:** Playwright plus axe.
- **Dep:** 9.3, 0.9.
- **Files:** `crates/ui/src/pages/throttle.rs`.
- **Size:** S.

### Checkpoint: throttle
- [ ] A live Plex stream changes the limit on a running test transfer and on a real download client within 5 s; human review.

## Phase 10: `parity`

### Task 10.1: Engine
- [ ] **AC (parity AC1, AC2, AC5, AC9–AC11, AC13, AC14):**
  - Phased, paced fetch and a streaming path-keyed join.
  - Findings: mismatches, gaps both ways, file mismatches, merged items.
  - Unknown agents reported, never modified.
  - Finding types switchable per pair; pairs excludable; a server with a missing anchor is not checked.
  - Extras, additional versions and Arr entries without a file produce no finding.
  - Finding identity across runs; skip, ignore and resolved with retention.
  - A full check is a long job; a second one is refused.
  - 500k-item run within budget.
- **V:** fixtures per server; capped performance test.
- **Dep:** 3.1, 2.2–2.4, 4.6, 0.7.
- **Files:** `crates/parity/src/{fetch,compare,findings}.rs`.
- **Size:** M.

### Task 10.2: Fixes and triggers
- [ ] **AC (parity AC3, AC4, AC6–AC8, AC12):**
  - Review-first; auto-fix opt-in per server and finding type.
  - Scans queued as the fix for missing and stale files.
  - Safety limit suspends automatic fixing for the run and says so in the completion notice.
  - Only findings new since the previous run notify.
  - Rate-limited fixes, verified by read-back, audited.
  - Emby/Jellyfin fixes change provider IDs only.
  - Merged items: off, notify or auto-split.
  - Schedule, on-demand and after-import triggers, each switchable.
- **V:** fakes; `live` dry run.
- **Dep:** 10.1, 1.2, 4.1.
- **Files:** `crates/parity/src/{fix,triggers}.rs`.
- **Size:** M.

### Task 10.3: Parity UI
- [ ] **AC (ui AC10: Library parity, Parity finding, Settings › Library parity):** findings (fix, skip, ignore) with filters, the finding page with its history, and the parity settings.
- **V:** Playwright plus axe.
- **Dep:** 10.2, 0.9.
- **Files:** `crates/ui/src/pages/parity.rs`.
- **Size:** M.

### Checkpoint: parity
- [ ] A live dry run against the test libraries lists findings with no writes; an approved fix verifies by read-back; human review.

## Phase 11: `track-preferences`

### Task 11.0: Verify user tokens
- [ ] **Spike:** against a pinned Plex version, verify how tokens are obtained for shared, managed and PIN-protected home users, and that a part write with a user's token changes only that user's selection. Record it as a platform note.
- **V:** `live` test on a test library.
- **Dep:** 2.2.
- **Files:** `docs/platform-notes/`.
- **Size:** S.

### Task 11.1: Matching algorithm
- [ ] **AC (track-preferences AC3, AC7):** PAL's scoring plus forced/HI/VI semantics and tie-break, with the fixed cases; no match leaves the episode unchanged.
- **V:** port of PAL's tests plus new cases.
- **Dep:** none (pure).
- **Files:** `crates/track-preferences/src/matching.rs`.
- **Size:** S.

### Task 11.2: Users, preferences, triggers, apply
- [ ] **AC (track-preferences AC1, AC2, AC4–AC6, AC8–AC14):**
  - Shared-server tokens, never logged; refresh on failure; users without a token skipped.
  - Preferences per (user, show GUID), per Plex target.
  - Recording: first play, then real changes only; a fallback is never recorded.
  - Scope per target, library, show exclusion and the ignore label.
  - Play, new-episode and sweep triggers, each switchable; the sweep limited to changed episodes.
  - Keyed serialisation; writes in their own lane behind scans.
  - Verified writes; correct episodes not written.
  - Opt-out and scope override per user; preferences removed 30 days after access is lost.
  - History of changes with retention.
- **V:** fake Plex; `live` test on a test library.
- **Dep:** 11.0, 11.1, 2.2, 0.7.
- **Files:** `crates/track-preferences/src/{users,prefs,apply}.rs`.
- **Size:** M.

### Task 11.3: Track preferences UI
- [ ] **AC (ui AC10: Track preferences, User):** users with their dialog, preferences (edit and clear), excluded shows, where it applies, scope settings, Sweep with progress, and the history.
- **V:** Playwright plus axe.
- **Dep:** 11.2, 0.9.
- **Files:** `crates/ui/src/pages/tracks.rs`.
- **Size:** S.

### Checkpoint: track-preferences
- [ ] A track change during live Plex playback propagates to the next episodes for that user only; human review.

## Phase 12: Release

### Task 12.1: Dashboard
- [ ] **AC (ui AC10, Dashboard row):**
  - Tiles, target states, next scans, running uploads and newest parity findings, each linking to its page.
  - Live updates from the event stream.
- **V:** Playwright plus axe; WASM budget.
- **Dep:** 4.4, 8.6, 9.4, 10.3.
- **Files:** `crates/ui/src/pages/dashboard.rs`.
- **Size:** S.

### Task 12.2: Host service packaging and release pipeline
- [ ] **AC (ADR-0018):**
  - Static musl binaries for x86_64 and aarch64.
  - An example systemd unit: Saltbox user, environment file for the secret key and listen address, the capabilities optional features need, each documented.
  - release-please releases.
- **V:** on a clean host the unit starts Autoplow from a bootstrap file; features report correctly with and without their capability.
- **Dep:** all phases.
- **Files:** `packaging/autoplow.service`, `.github/workflows/release.yml`, `docs/guides/install.md`.
- **Size:** S.

### Task 12.3: Replacement checklists and Saltbox integration notes
- [ ] **AC (project success criterion 3):**
  - A written checklist per replaced tool (autoscan/autopulse, cloudplow, matcharr, Plex-Auto-Languages), each verified by the live suite and naming what must be off before the matching feature is switched on.
  - Example bootstrap for the Saltbox role.
- **V:** walkthrough on a test Saltbox install.
- **Dep:** 12.2.
- **Files:** `docs/guides/*.md`.
- **Size:** S.

### Checkpoint: release candidate
- [ ] Every module's acceptance criteria are met.
- [ ] Project scale targets are verified.
- [ ] The `CONSTRAINTS.md` gates are green.
- [ ] Human review.
