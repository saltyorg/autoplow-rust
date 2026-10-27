# Autoplow task list

**Format:**
- Each task lists its acceptance criteria (AC), how to verify it (V), its dependencies (Dep) and its size.
- Size is S or M. L means it has to be split before work starts.

**Standard verification for every task:**
- `cargo test --workspace` passes.
- `cargo build --release` succeeds.
- `cargo clippy --workspace -- -D warnings` is clean, with the panic policy lints denied.
- `cargo fmt --check` passes.

## Phase 0: Foundation

### Task 0.1: Repository skeleton, CI, panic policy
- [ ] **AC:**
  - Cargo workspace with crates matching architecture.md (`paths`, `store`, `config`, `supervisor`, `api`, `targets`, `triggers`, `uploader`, …) and a binary crate.
  - The workspace adopts `docs/quality-policy.md` exactly (configuration in its appendix): `[workspace.lints]`, `clippy.toml`, `rust-toolchain.toml` pinned to 1.99.1, release `overflow-checks`.
  - CI runs every gate in the policy (fmt, clippy `-D warnings`, `lints.workspace` check, nextest, coverage floor, cargo-mutants on core crates, cargo-deny, cargo-machete), plus musl x86_64/aarch64 builds via cargo-zigbuild.
  - The crate stack in plan.md is confirmed.
  - The binary prints its version.
- **V:** CI is green; `./autoplow --version` works.
- **Dep:** none.
- **Size:** S.

### Task 0.2: Paths package
- [ ] **AC:**
  - Component-based containment.
  - Rewrite rule sets that reject overlapping sources within a set.
  - Trigger, target and pair scopes, where a pair set replaces the target set.
  - Parent/child coalescing helper.
- **V:**
  - Table tests, including `/mnt/Movies` vs `/mnt/Movies4K`, trailing slashes, `..`.
  - Property tests (proptest) for normalisation.
- **Dep:** 0.1.
- **Size:** S.

### Task 0.3: Store and migrations
- [ ] **AC:**
  - SQLite in WAL mode with one writer and a reader pool.
  - Embedded, versioned migrations with a migration test harness.
  - A compare-and-set update helper.
- **V:**
  - Migration up tests on an empty database.
  - Concurrency test: the writer serialises, readers don't block.
- **Dep:** 0.1.
- **Size:** M.

### Task 0.4: Supervisor and component lifecycle
- [ ] **AC:**
  - `Run(ctx)` components with backoff restart.
  - Config-snapshot dependency declarations.
  - Stopping and rebuilding only the affected components.
  - Graceful shutdown with a deadline.
- **V:**
  - Unit tests with fake components and a paused tokio clock: crash and restart, a config change rebuilds only the dependents, shutdown ordering.
- **Dep:** 0.1.
- **Size:** M.

### Task 0.5: Config model, bootstrap seed-once, apply API core
- [ ] **AC:**
  - Typed config resources persisted in the store.
  - YAML bootstrap with a strict schema: unknown keys and errors are reported with line numbers.
  - Seed-once semantics: create missing resources, never modify existing ones.
  - After a full success, write `bootstrap-report.json` and delete the file. On partial failure, keep it.
  - JSON Schema is generated from the Go types.
- **V:**
  - Golden tests for the report.
  - Tests for partial failure and for a read-only file.
- **Dep:** 0.3.
- **Size:** M.

### Task 0.6: HTTP server, REST conventions, auth
- [ ] **AC:**
  - `/api/v1` router.
  - RFC 9457 errors.
  - Admin API keys stored hashed (`Bearer`), and a read-only scope.
  - Secrets are write-only (`{"set":true}`).
  - Request body limits.
  - `/health`.
  - OpenAPI document served.
- **V:**
  - API tests for auth (missing, invalid, valid key, scopes) and for secret redaction.
- **Dep:** 0.5.
- **Size:** M.

### Task 0.7: Resource CRUD and `POST /apply`
- [ ] **AC:**
  - `GET`/`PUT`/`PATCH`/`DELETE` by name for every resource kind.
  - `POST /apply?mode=seed|upsert&dry_run`, returning per-resource results and a diff.
  - Changes notify the supervisor.
- **V:**
  - Idempotency tests: applying the same document twice leaves everything unchanged.
  - A dry run makes no writes.
- **Dep:** 0.6, 0.4.
- **Size:** M.

### Task 0.8: Observability
- [ ] **AC:**
  - slog with a level per component, and token redaction.
  - Prometheus `/metrics`.
  - An SSE `/api/v1/events` broker that sends keepalives and drops slow consumers safely, without blocking producers.
- **V:**
  - Tests: the SSE broker never blocks a publisher; redaction covers tokens in URLs and headers.
- **Dep:** 0.6.
- **Size:** S.

### Task 0.9: UI shell (Leptos)
- [ ] **AC:**
  - Leptos CSR app built with trunk, with `wasm-opt -Oz` enabled. The `dist/` is embedded in the binary with rust-embed.
  - A shared API-types crate is used by both the backend and the UI.
  - Login with session cookie, CSRF protection and a rate limit.
  - Layout and navigation, a live-event client, and an API client generated from OpenAPI.
- **V:** Playwright end-to-end test: log in and see the empty dashboard. The test runs in CI.
- **Dep:** 0.6, 0.8.
- **Size:** M.

### Checkpoint: Foundation
- [ ] The tests above pass.
- [ ] A bootstrap file seeds an admin user and an API key.
- [ ] `apply` works.
- [ ] The UI logs in.
- [ ] Human review.

## Phase 1: Scan pipeline, core slice (manual → Plex)

### Task 1.1: Per-target durable scan queue
- [ ] **AC:**
  - Table keyed on (target, folder), with a generation counter.
  - A unique pending index plus upsert.
  - Child entries are absorbed into a queued parent.
  - Readiness = the trigger's minimum age plus extra wait for the event type, capped by the target's maximum wait.
  - FIFO by ready time.
  - Generation-based acknowledgement: an event arriving after dispatch always causes another scan.
- **V:**
  - Fake-clock tests covering every rule above, including "event during dispatch" and "event after a fast scan".
- **Dep:** 0.2, 0.3.
- **Size:** M.

### Task 1.2: Target worker framework
- [ ] **AC:**
  - One worker per target, isolated.
  - Error classes: retry, back off the target (honouring `Retry-After`), or per-path dead-letter.
  - A worker never dies on one path.
  - Batching hook.
  - Every queue entry exposes its wait reason.
- **V:** fake-target tests: an offline target doesn't block the others; a 400 dead-letters one path only.
- **Dep:** 1.1, 0.4.
- **Size:** M.

### Task 1.3: Library resolver
- [ ] **AC:**
  - Library list per target, refreshed periodically and whenever a lookup misses.
  - Resolution returns every library whose location contains the folder, by components.
  - Root scans rejected by default (per-target setting).
  - "Unmatched" is reported, never silently dropped.
- **V:** tests including the same location in two libraries.
- **Dep:** 0.2.
- **Size:** S.

### Task 1.4: Plex target (scan)
- [ ] **AC:**
  - `refresh?path=` per folder per library.
  - Paging headers on every request.
  - Version check and token handling.
- **V:**
  - Fake Plex tests.
  - `live` test: new episode visible in about 1 s, matching the earlier results.
- **Dep:** 1.2, 1.3.
- **Size:** S.

### Task 1.5: Manual scan API, preview and UI
- [ ] **AC:**
  - `POST /api/v1/scans`, where `dry_run` returns the rewrite, library and existence per target.
  - Queue view and retry over the API.
  - UI pages for manual add with preview, plus queues.
- **V:** API tests; UI end-to-end test of preview and queueing.
- **Dep:** 1.4, 0.9.
- **Size:** M.

### Checkpoint: Core slice
- [ ] A manual scan reaches Plex end to end, live.
- [ ] Queues survive a restart.
- [ ] A config edit to the target takes effect without a restart.
- [ ] Human review.

## Phase 2: Scan pipeline, breadth

### Task 2.1: Trigger framework and auth
- [ ] **AC:**
  - Trigger resources with:
    - per-instance or global credentials
    - header, basic and query auth (any one passes)
    - include/exclude filters
    - target excludes
    - minimum age and extra wait per event type
  - Unknown events return 2xx.
- **V:** auth matrix tests.
- **Dep:** 1.1, 0.7.
- **Size:** M.

### Task 2.2: Sonarr and Whisparr v2 parser
- [ ] **AC:**
  - Download events, per file and the ImportComplete shape, deduplicated by `downloadId` and folder.
  - Rename: old and new folders.
  - EpisodeFileDelete and SeriesDelete skip the existence check.
  - Test events queue nothing.
- **V:** golden payload tests taken from the source shapes in `docs/research/arr-connect-api.md`.
- **Dep:** 2.1.
- **Size:** S.

### Task 2.3: Radarr and Whisparr v3 parser
- [ ] **AC:** Download, Rename, MovieFileDelete and MovieDelete (scan the folder, no existence check). Test events.
- **V:** golden tests.
- **Dep:** 2.1.
- **Size:** S.

### Task 2.4: Lidarr parser
- [ ] **AC:** Download (`trackFiles[]`), Rename, Retag, ArtistDelete, AlbumDelete. The Test payload carries `albums`.
- **V:** golden tests.
- **Dep:** 2.1.
- **Size:** S.

### Task 2.5: Legacy, Bazarr and generic triggers
- [ ] **AC:**
  - autoscan `/triggers/{sonarr,radarr,lidarr,manual}` and A-Train as adapters.
  - Bazarr `GET /triggers/bazarr?path=`.
  - `GET /stats` returns 200, and `/api/config-template` returns our snippet.
  - Generic `{paths:[]}`.
- **V:** compatibility tests against recorded autoscan, A-Train and Bazarr requests.
- **Dep:** 2.1.
- **Size:** M.

### Task 2.6: Jellyfin and Emby targets
- [ ] **AC:**
  - Batched `Media/Updated` (Modified for Jellyfin, Created for Emby).
  - Library listing.
  - Emby's library-delete-by-Id quirk handled wherever relevant.
  - The UI notes the monitor delay.
  - Warning for overlapping library locations.
- **V:** fake-server tests; `live` test confirming about 60 s and about 90 s.
- **Dep:** 1.2, 1.3.
- **Size:** M.

### Task 2.7: Tdarr and Autoplow targets
- [ ] **AC:**
  - Tdarr `scan-files`.
  - Autoplow target posts to another instance's generic trigger.
  - Target excludes prevent loops.
- **V:** fake-server tests.
- **Dep:** 1.2.
- **Size:** S.

### Task 2.8: Anchors, "path must exist", empty trash
- [ ] **AC:**
  - Anchors bound at any scope; all applicable anchors must exist; deletes are blocked when any is missing.
  - Optional existence check with retry and a timeout warning; deletes are exempt.
  - Plex verified empty trash: observe `refreshing`/`scannedAt`, skip if the scan failed, wait only in the Plex worker.
- **V:**
  - Fake-clock and fake-Plex tests.
  - `live` test of late visibility on Plex: passes with the check, fails without it.
- **Dep:** 1.4, 2.6.
- **Size:** M.

### Task 2.9: Post-delivery verification (optional per target)
- [ ] **AC:**
  - Query whether the expected path is present or absent within the server's delay plus a margin.
  - On failure, warn with a hint such as "library not registered".
- **V:** fake tests that reproduce the Jellyfin empty-folder and Plex disrupted-scan cases.
- **Dep:** 2.6.
- **Size:** S.

### Task 2.10: UI for triggers and targets
- [ ] **AC:**
  - CRUD pages for triggers and targets.
  - Credential display, with copy for webhook URLs.
  - Rewrite rule editor with a filesystem picker: Arr filesystem API, Emby/Jellyfin directory listing, local browser.
  - Health and warnings.
- **V:** UI end-to-end tests.
- **Dep:** 2.1–2.9, 0.9.
- **Size:** M. Split per page if it grows.

### Checkpoint: Scanning complete
- [ ] Every trigger and target works against fakes.
- [ ] The `live` matrix matches the earlier results.
- [ ] Human review.

## Phase 3: Arr connection manager

### Task 3.1: Arr client and detection
- [ ] **AC:**
  - `system/status` detects app, version and urlBase, and selects the API flavour (v3, v1; v5-ready).
  - Root folders.
  - Filesystem API proxy for the picker.
- **V:** fake Arr tests per flavour.
- **Dep:** 0.7.
- **Size:** S.

### Task 3.2: Managed connection reconciler
- [ ] **AC:**
  - The desired resource is built from the Arr's own schema, named `Autoplow (Managed)`, with a header token, a fingerprint header, `tags: []` and the fixed event set.
  - Create only when the receiver is ready.
  - Detect drift and repair with a **full PUT, only when drift exists** (Lidarr re-tests on every PUT).
  - Re-create when missing.
  - Unmanage and delete from our UI.
  - Drift notifications.
- **V:**
  - Fake Arr tests.
  - `live` test of the full create, drift, repair and delete cycle (see `docs/platform-notes/arr.md`).
- **Dep:** 3.1, 2.1.
- **Size:** M.

### Task 3.3: Migration helper and evidence-based mapping suggestions
- [ ] **AC:**
  - List old autoscan, autopulse and autoplow webhooks, and offer to disable or delete them after our connection is verified.
  - Path-mapping suggestions derived from the same file seen by the Arr and by the server (several samples, checked on local disk).
- **V:** fake tests; a `live` dry run.
- **Dep:** 3.2, 1.3.
- **Size:** M.

### Checkpoint: Arr integration
- [ ] A real Sonarr or Radarr is configured end to end through the API and UI.
- [ ] Human review.

## Phase 4: Uploads

### Task 4.1: rclone transport (supervised `rcd`)
- [ ] **AC:**
  - Start `rclone rcd` on a unix socket in a 0700 directory, with an explicit `--config` pointing at the user's rclone.conf.
  - Health check (`rc/noop`) and restart with backoff.
  - After a child crash, re-queue unfinished uploads from our database: job state does not survive a restart.
  - Job and group management, completion by polling, stats-group cleanup.
  - Check the rclone version (minimum supported).
  - Cap the child's memory where possible.
- **V:**
  - Tests against local and crypt, porting the spike checks: move, batch, filters, bwlimit, cancel.
  - `kill -9` of rcd mid-transfer leads to a restart and re-queue, and the upload completes.
  - The host's graceful SIGTERM shutdown is unaffected by rclone's atexit hook.
- **Dep:** 0.4.
- **Size:** M.

### Task 4.2: Destinations and the per-file upload queue
- [ ] **AC:**
  - Destination resources.
  - Durable upload queue keyed by file identity (dev, ino) plus path.
  - Batch submission with one group per job.
  - Tracking by job and identity, never by basename.
  - Retries with backoff; the source is never removed on failure.
- **V:**
  - Duplicate-basename test.
  - Crash-recovery test.
- **Dep:** 4.1, 0.3.
- **Size:** M.

### Task 4.3: Readiness: age, stability, mtime hygiene, hardlinks
- [ ] **AC:**
  - First-seen age that restarts when mtime changes.
  - Size and stability checks.
  - Detection of future or bogus mtimes, with an opt-in fix (never on hardlinks, never when Change File Date is in use) or a warning with source-setting hints.
  - Hardlink policy per destination.
  - "Scanned first" gate.
- **V:** fake-clock and filesystem tests.
- **Dep:** 4.2, 1.1.
- **Size:** M.

### Task 4.4: Open-file detection (optional)
- [ ] **AC:**
  - Capability detection (`pid: host`, `SYS_PTRACE`).
  - `/proc` fd scan matched by dev+inode for both the local and the mergerfs identity.
  - Write-mode and lock detection.
  - Process and container identification.
  - Optional "wait while a media server has the file open".
  - Escape hatch for long-held read-write handles.
  - Degraded-mode notice when the capability is missing.
- **V:**
  - Tests with helper processes holding files open in read and write modes, and a flock.
  - Container-attribution test from cgroup fixtures.
- **Dep:** 4.3.
- **Size:** M.

### Task 4.5: Concurrency, failover, schedules
- [ ] **AC:**
  - Global transfer cap plus optional per-remote caps.
  - Remote health with cooldown on repeated or quota failures; route to the next remote.
  - Schedule windows that let transfers in flight finish.
- **V:** fake-transport tests.
- **Dep:** 4.2.
- **Size:** M.

### Task 4.6: Downloader pausing
- [ ] **AC:**
  - SABnzbd and NZBGet clients.
  - "While uploading" with a grace period, and a disk-space guard.
  - Guaranteed resume on error, on shutdown and by a periodic reconcile.
- **V:** fake downloader tests, including a simulated crash.
- **Dep:** 4.5.
- **Size:** S.

### Task 4.7: Upload UI
- [ ] **AC:** destinations, queue with readiness reasons, active transfers with live speed, history, remote health.
- **V:** UI end-to-end test.
- **Dep:** 4.1–4.6.
- **Size:** M.

### Checkpoint: Uploads
- [ ] A capped `live` upload of test files to a crypt remote on the host.
- [ ] Readiness verified with a hardlinked file and an open file.
- [ ] Human review.

## Phase 5: Throttle

### Task 5.1: Session sources and registry
- [ ] **AC:**
  - Plex websocket, Jellyfin/Emby websocket, and Tofa (polling until its websocket is documented).
  - Every source counted once.
  - Stale-session expiry.
  - Websocket readers never block.
- **V:** fake websocket tests.
- **Dep:** 1.4, 2.6.
- **Size:** M.

### Task 5.2: Policy modes and effect
- [ ] **AC:**
  - Modes: tiers, per stream, and by bitrate with clamping.
  - Exclude paused sessions, and LAN sessions optionally.
  - Optional "no new transfers above N streams".
  - Apply through `core/bwlimit`.
- **V:** table tests, including the 10 Gbps Plex outlier.
- **Dep:** 5.1, 4.1.
- **Size:** S.

### Checkpoint: Throttle
- [ ] Live: a Plex stream changes the limit on a running test transfer.

## Phase 6: Notifications

### Task 6.1: Outbox and dispatcher
- [ ] **AC:**
  - Outbox written in the same transaction as the state change.
  - Aggregation per (target, event type).
  - Backoff that honours `Retry-After` and Discord limits.
  - Dead-letter and retention.
- **V:** fake-clock tests; restart durability.
- **Dep:** 0.3.
- **Size:** M.

### Task 6.2: Channels, subscriptions, UI
- [ ] **AC:**
  - Discord, Apprise and generic webhook channels.
  - Subscriptions per event type.
  - Event types from Phases 2–5 wired in.
  - UI.
- **V:** fake endpoint tests; UI end-to-end test.
- **Dep:** 6.1.
- **Size:** M.

## Phase 7: Local filesystem and Google Drive triggers

### Task 7.1: Local filesystem trigger
- [ ] **AC:**
  - inotify, walk or both per path.
  - The walk snapshot is stored in the database (new, changed and deleted files).
  - Overflow handling.
  - Rebuilt on restart.
- **V:** tests on temp trees, including an overflow simulation.
- **Dep:** 2.1.
- **Size:** M.

### Task 7.2: Google Drive OAuth and accounts
- [ ] **AC:**
  - The user's own web OAuth client.
  - Connect and callback with state.
  - Encrypted tokens, included in key rotation.
  - Health on revocation.
- **V:** fake OAuth server tests.
- **Dep:** 0.6.
- **Size:** M.

### Task 7.3: Drive monitors
- [ ] **AC:**
  - Snapshot plus the Changes API.
  - Old and new paths through the tree.
  - Events committed before the page token is saved.
  - Re-snapshot when the token is invalid.
  - Rate limits.
  - Minimum age defaults above the mount's poll interval.
- **V:** fake Drive API tests: replay after a crash, token loss.
- **Dep:** 7.2, 2.1.
- **Size:** M.

## Phase 8: Library parity

### Task 8.1: Engine
- [ ] **AC:**
  - Phased fetch: Arr items, server items, path-keyed join.
  - Findings: ID mismatches, gaps both ways, file mismatches, merged items.
  - Items on unknown agents are reported, never modified.
  - Ignore list.
- **V:** fixture tests per server type.
- **Dep:** 3.1, 1.3.
- **Size:** M.

### Task 8.2: Fixing and triggers
- [ ] **AC:**
  - Review by default; auto-fix opt-in per server.
  - Plex match, Emby/Jellyfin provider-ID-only update, Tofa match.
  - Verified read-back and an audit log.
  - Merged items: off, notify, or auto-split.
  - Schedule, on demand and after import, each switchable on or off.
- **V:** fake-server tests; a `live` dry run against the test libraries.
- **Dep:** 8.1, 6.2.
- **Size:** M.

### Task 8.3: Parity UI
- [ ] **AC:** runs, findings (fix, skip, ignore), filters, audit log.
- **V:** UI end-to-end test.
- **Dep:** 8.2.
- **Size:** M.

## Phase 9: Track preferences (Plex)

### Task 9.1: Matching algorithm port
- [ ] **AC:** PAL's audio and subtitle scoring, forced/HI semantics and tie-break, with the known bugs fixed.
- **V:** port of PAL's tests plus new cases.
- **Dep:** none (pure).
- **Size:** S.

### Task 9.2: Users, preferences, triggers, apply
- [ ] **AC:**
  - Shared-server user tokens, never logged.
  - Preference store per (user, show).
  - Play, new-episode and sweep triggers, each switchable on or off.
  - Keyed queue per (user, show).
  - Verified writes.
  - Opt-out per user.
- **V:** fake Plex tests; a `live` test on the test library.
- **Dep:** 9.1, 5.1.
- **Size:** M.

### Task 9.3: Track preferences UI
- [ ] **AC:** users, preferences (edit and clear), scope settings, history.
- **V:** UI end-to-end test.
- **Dep:** 9.2.
- **Size:** S.

## Phase 10: Packaging

### Task 10.1: Container and release
- [ ] **AC:**
  - Static musl binary; distroless or Alpine image that includes a pinned rclone.
  - `RCLONE_CONFIG` set.
  - Documented optional `pid: host` and `SYS_PTRACE`.
  - Healthcheck.
  - Release pipeline: cargo-zigbuild, multi-arch image.
- **V:** image runs and boots from the bootstrap file on a clean volume.
- **Dep:** all phases.
- **Size:** S.

### Task 10.2: Saltbox integration notes and migration guide
- [ ] **AC:**
  - Example bootstrap templated by the role.
  - Migration from autoscan, autopulse, cloudplow and old autoplow, including the webhook migration helper.
- **V:** dry-run walkthrough on a test Saltbox install.
- **Dep:** 10.1.
- **Size:** S.

### Checkpoint: Release candidate
- [ ] Every acceptance criterion is met.
- [ ] The live matrix passes.
- [ ] Human review.

## Repository conventions (added during first-commit setup)
- [ ] **Task 0.1 addendum: constraints tooling.** Install and wire every tool in `CONSTRAINTS.md` (cargo-nextest, cargo-llvm-cov + diff-cover, cargo-mutants + `scripts/check-mutants.sh`, cargo-deny + `deny.toml`, cargo-machete, gitleaks, trunk + `scripts/check-wasm-budget.sh`, Playwright + `@axe-core/playwright`). Add a `scripts/check-task.sh` that runs the full set (no time budget), add the Rust CI workflow, and record the project-coverage baseline.
  - **V:** a trial run on the branch passes. The floor guard catches a planted `#[allow]`, `todo!()` and `#[ignore]`.
- [ ] **Task 0.1 addendum: release-please.** Add the release-please workflow (`release-type: rust`) once `Cargo.toml` exists. Releases and the CHANGELOG are generated from Conventional Commits; tags are `vX.Y.Z` (0.x until stable). Until the first release, commits go straight to `main`; switch to PRs with required checks afterwards.
