# Core architecture: draft proposal (v0, Rust)

**Status:** draft, partly decided. Decisions referenced here are recorded in [decisions/](decisions/README.md). Lessons from earlier projects are in [research/](research/README.md).

## Design goals
These come directly from the failures we saw in earlier projects.

1. **Changing config never requires a process restart.** Every component can be stopped and started again. autoplow got this wrong: its components could not restart, and edited targets went stale.
2. **Work is never silently dropped.** Every queue is durable and applies back-pressure instead of discarding items. autoplow's 100-slot channels and PAL's queue both dropped work.
3. **One failure never stops a worker.** Errors are classified and drive the retry policy. autoscan, by contrast, stopped a worker for good on a fatal error.
4. **Path handling lives in one place**, with prefix matching that respects path boundaries, so `/mnt/Movies` does not match `/mnt/Movies4K`.
5. **Nothing blocks on I/O readers.** Websocket and webhook handlers only enqueue work.
6. **Secrets never reach logs or argv.**
7. **Features are wired end-to-end before they appear in the UI.**

## Overview

```
                 ┌──────────────── Config ────────────────┐
 bootstrap.yml ─▶│ loader → validate → reconcile → store   │──▶ change notifications
 REST API/UI   ─▶│ (single source: DB, file-managed flags) │         │
                 └─────────────────────────────────────────┘         ▼
                                                              Supervisor
 Intake (triggers)                                            (restarts the affected
  ├─ Arr webhooks (managed connections)  ┐                     components)
  ├─ legacy autoscan/A-Train endpoints    │   PathEvent
  ├─ manual/API                           ├──▶ Router ──┬──▶ Scan pipeline ──▶ Targets (Plex/Emby/Jellyfin/Tofa/Tdarr/autoplow)
  ├─ local FS (inotify | walk | both)     │             ├──▶ Upload pipeline ─▶ rclone transport (supervised rclone rcd, unix socket)
  └─ Google Drive (OAuth, Changes API)    ┘             └──▶ matcharr hints (optional, per item)

 Session sources (Plex/Emby/Jellyfin websockets, Tofa polling) ─▶ Session registry ─▶ Throttle controller ─▶ core/bwlimit
 Plex notifications ─▶ PAL (one queue per show/user) ─▶ Plex parts API
 Arr connection reconciler ─▶ Arr APIs (keeps our webhook correct)
 Schedulers: matcharr sweeps, library-cache refresh, retention cleanup
 Observability: tracing logs, Prometheus /metrics, SSE event stream for the UI
```

## Building blocks

### Component lifecycle
- Every long-running part is a supervised async task: `async fn run(self, shutdown: CancellationToken) -> Result<()>`. A panic inside a task is caught by the supervisor and treated as a crash, so the component is restarted.
- A **supervisor** owns the components. It builds each one from an immutable config snapshot, restarts it with backoff if it crashes, and on a config change **stops and rebuilds only the affected components**. Components declare which config keys they depend on.
- Components hold no wiring set from outside after they start, and there are no unlocked shared maps. They are built from the snapshot plus shared services: store, transport, clock and logger.
- Shutdown is graceful: cancel the context, drain or persist in-flight state, and wait with a deadline.

### Events
- Every trigger normalises its input into **`PathEvent`**:
  - `{path, kind: created|modified|deleted|renamed(from), source, priority, hints{arr ids, downloadId, mediaType}}`
  - `path` is converted to the **canonical local path** at intake, using the trigger's path mapping.
- The **router** applies per-trigger filters, then fans each event out to the pipelines that care about it.
- The router writes to the database in a single transaction, so an intake request is acknowledged only after it is durably stored. This follows autoscan.

### Path model
- Four namespaces:
  - **Arr view:** paths inside the Arr containers.
  - **Canonical local path:** the path on the machine running Autoplow.
  - **Target view:** one per media server.
  - **Remote path:** the rclone path.
- Rewrite rule sets are scoped **per trigger**, **per target** and **per trigger→target pair**. If a pair has its own set, it replaces the target's set for that pair.
- Within a set, overlapping source prefixes are rejected, so each path matches at most one rule. No longest-match logic exists anywhere.
- Users pick mappings from each side's real filesystem (Arr filesystem API, Emby/Jellyfin directory listing, Tofa folders, local browser). Evidence-based suggestions use the same file seen by both sides.
- Manual entries must be absolute and end in `/`. The platform is Linux only.
- One `paths` package does the work:
  - boundary-aware prefix matching
  - normalisation (clean, no `..`, no trailing slash)
  - parent/child coalescing
- Every component uses this package. No component compares paths with its own string checks.

### Durable queues (SQLite)
- **Scan queue:** one row per (target, folder), based on autoscan's design.
  - **Generation counter on acknowledgement:** a new event for the same folder bumps the generation, so a scan that was in flight when it arrived does not delete the newer work.
  - **Timing:** a minimum age (debounce), plus a new **maximum wait** so a constantly changing folder cannot starve. Any event that arrives after a scan has been dispatched always leads to another scan.
  - **Database-enforced dedup:** a unique partial index on (target, folder) for pending entries, written with an upsert. Status updates use optimistic compare-and-set, as autopulse does, so an in-flight dispatch can never overwrite a newer event or a manual retry.
  - **Isolation:** each target has its own durable queue and worker, so one offline server never blocks the others.
  - **Coalescing:** if a parent folder is queued, child folders are absorbed into it.
  - **Batching:** for targets that accept several paths per call (Tofa scoped scan, Emby/Jellyfin `Media/Updated`), with a maximum batch size.
  - **Ordering:** minimum age is set per trigger; each queue is FIFO by ready time. There are no priorities.
  - **Library cache:** refreshed periodically and whenever a lookup misses. autoscan never refreshed its library list.
  - **Anchors** can be bound globally, per target, per library or per path. Before each delivery, *every* anchor that applies must be present. There is no longest-match resolution.
  - **Library root scans** are rejected by default, with a per-target setting to allow them.
  - **Errors:** each one is classified as retry, back-off-target or dead-letter for that row. A worker never dies because of one bad path.
- **Upload queue:** one row per local file, assigned to a destination.
  - **Readiness rules:**
    - A minimum age counted from first-seen, which restarts whenever mtime changes.
    - A stable size.
    - Not open for writing. This check is optional and needs `pid: host` and `SYS_PTRACE`: `/proc` fds and write locks matched by dev+inode.
    - Scanned first.
    - A setting for hardlinked files.
    - See [specs/upload.md](specs/upload.md).
  - **Execution:** batches are submitted as rclone jobs with **one stats group per job**. Uploads are tracked by job ID and source path, never by basename.
  - **Concurrency:** a limit per destination remote, instead of autoplow's single global batch.
  - **Failures:** each file is retried with backoff. Failover is based on **remote health**: a remote with repeated failures or a quota error gets a cooldown, and the destination's next remote takes over while it lasts.
- **Back-pressure:** intake can block briefly or return 503 with `Retry-After`. It never drops events.

### rclone
- Autoplow supervises a child **`rclone rcd`** on a private unix socket (in a 0700 directory) with `--config <user's rclone.conf>`, and talks to it over the RC JSON API. Verified behaviour: [platform-notes/rclone.md](platform-notes/rclone.md).
- **Supervision:**
  - Health check with `rc/noop`.
  - Restart with backoff if the child dies.
  - Job state does not survive a restart, so unfinished uploads are re-queued from our database.
- **Isolation:** rclone crashes, leaks and its SIGTERM/atexit hook stay in the child.
- **Jobs:** completion is polled (`job/status`), and a periodic sweep removes finished stats groups.
- **Versioning:** the rclone version is checked against a minimum. The container image ships a pinned rclone.

### Throttle
- **Session registry:** fed by push sources (Plex, Emby and Jellyfin websockets) and by pollers (Tofa). Each session source is counted exactly once.
- **Policy:** the user picks a mode: tiers by stream count, a fixed reservation per stream, or a reservation by bitrate (with bitrates clamped). Paused streams are excluded, and LAN streams optionally. There is no time schedule. See [specs/throttle.md](specs/throttle.md).
- **Effect:** the controller sets the process-wide `core/bwlimit`. It can also pause new upload batches below a set speed.

### Local filesystem triggers
- Each watched path has a mode:
  - `inotify`: fsnotify watches every directory recursively.
  - `walk`: a periodic scan that compares (path, size, mtime) against a snapshot stored in the database, so it detects new, changed and deleted files and survives restarts. autoplow's polling only saw new files.
  - `both`: inotify for low latency, with the walk catching anything missed (queue overflow, events during a restart).
- Both modes produce `PathEvent`s.
- Watcher state is rebuilt whenever the component restarts.

### Media-server targets
- **Interfaces are split by capability:** `Scanner`, `SessionSource`, `Matcher` (Library parity) and `TrackSelector` (Track preferences, Plex only).
- **Each target declares its capabilities**, and the UI shows only what that target supports.
- **Shared HTTP client:**
  - timeouts
  - response size limits
  - honours `Retry-After`
  - an error taxonomy that drives retries
  - tokens redacted from trace logs

### Arr integration
- **Connection reconciler:** ensures that each managed webhook exists with the correct URL, header token, event flags, and `tags: []`.
- **Drift handling:** drift is detected by fingerprint and fixed with a full PUT.
- **Webhook receiver:** handles both of Sonarr's `Download` shapes, deduplicating by `downloadId`, and accepts `Test` without queuing anything.
- **Library parity** (formerly matcharr):
  - runs scheduled sweeps
  - can also run on a single item after an import
  - always supports dry-run and verifies a match after setting it

### Track preferences (Plex, formerly PAL)
- Plex websocket events are put onto a **per-(user, show) serialized queue**, a keyed work queue, so concurrent events for the same show cannot race. PAL had that race.
- Preferences are **stored per (user, show)** when tracks change, instead of being derived from a watched episode. See [specs/track-preferences.md](specs/track-preferences.md).
- The matching algorithm is ported from PAL, including its tie-break tests.

### Google Drive
- OAuth sign-in from the UI, an initial snapshot, then the Changes API.
- Paths are handed to the router **before** the page token is advanced, as bernard does.
- Details still to be designed.

## Configuration and API
- **Bootstrap file (seed once):**
  - Declarative YAML, applied at startup. It creates any resource whose name doesn't exist yet, and never overwrites an existing one.
  - Reports what was created and what was skipped.
  - Ongoing changes from Ansible go through the idempotent REST API.
- **Store:** SQLite (rusqlite, bundled) in WAL mode, with one writer connection and a pool of readers. Migrations are versioned and come with tests. There are no ad-hoc "ensure column" patches.
- **REST API:**
  - versioned at `/api/v1`, OpenAPI-first
  - resources are addressed by stable **names** (`PUT /api/v1/targets/{name}` is an idempotent upsert), which suits Ansible
  - the UI uses the same API
- **Authentication:**
  - API keys sent as `Authorization: Bearer`, scoped to admin or webhook use
  - UI sessions with CSRF protection and a login rate limit
  - webhooks use a per-trigger token in a header
- **Secrets:** encrypted at rest, with key rotation that re-encrypts **everything**. autoplow's rotation missed its Google Drive tokens.

## Observability
- Structured logs (`tracing`), with a log level per component. Secrets are wrapped in `secrecy` types so they can't be logged.
- Prometheus metrics: queue depth and age, delivery results, upload throughput, session counts.
- An SSE stream so the UI shows live state.
- Every item waiting in a queue shows *why* it is waiting: debounce, anchor missing, target down, not yet ready.

## Testing approach
- A fake clock for every timer-based behaviour (debounce, maximum wait, backoff).
- Recorded and fake HTTP servers for each target and Arr.
- Pipeline tests that run against a real SQLite database.
- The rclone transport tested against the local and crypt backends, as in the spike.

## Decided
- Bootstrap file seeds once.
- The UI is an SPA that uses only the REST API.
- Local paths can be watched with inotify, a walk, or both.
- Another instance is only a scan target.

See [decisions/](decisions/README.md).
