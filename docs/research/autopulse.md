# autopulse: codebase report

- **Source:** github.com/dan-online/autopulse, HEAD `4f0aba1` (2026-10-25), workspace v2.0.0.
- **Language:** Rust, about 16.5k lines.
- **What it is:** an alternative to autoscan. Bazarr's "external webhook" feature was built for it.

## Architecture
### Crates
| Crate | Contents |
|---|---|
| `database` | Diesel schema and migrations; supports SQLite and Postgres |
| `service` | Settings, triggers, targets, outgoing webhooks, and the manager/runner |
| `server` | REST API (actix-web) plus a UI built with Maud and htmx |
| `utils` | Regex rewrites, `RuntimePath` (path matching that respects path components), sha256 |

### Runtime
- **One runner task** ticks every second.
- Each tick runs these steps in order:
  1. **Anchor check.** If any anchor is missing, the tick does nothing.
  2. **Existence and hash check.** Only when `check_path` is enabled.
  3. **Processing.** Picks up to 100 due rows and sends them to each target **one target after another**.
  4. **Cleanup.**
- **No isolation between targets.** A slow target, or Plex's empty-trash wait (up to 300s), stalls every target.

### Data model
- **`scan_events` has one row per *file path*, not per target.**
- Main columns:
  - `process_status`: pending, complete, retry or failed.
  - `found_status`: not_found, found or hash_mismatch.
  - `failed_times`, `next_retry_at`.
  - `can_process`: the debounce deadline.
  - `targets_hit`: a comma-joined list of the targets that have already succeeded.
- **Database-enforced dedup:** a unique partial index on `file_path WHERE status IN (pending, retry)`, combined with upsert coalescing.
  - Coalescing extends the deadline to the later of the two.
  - It keeps the first `event_source`, `found_status` and `targets_hit`.
- **Optimistic compare-and-set status writes:** a concurrent manual retry or a newly arrived event is never overwritten by an in-flight dispatch.
- **Retries:**
  - Backoff is `2^(n+1)` seconds and `max_retries` defaults to 5. That is about **1 minute in total before the row is permanently `failed`**.
  - Only a manual retry from the UI brings a failed row back.
  - There is no classification of errors.
- **Cleanup:** deletes rows that are `not_found` or `failed` after 10 days. **`complete` rows are never deleted.**

### Triggers
- **Supported:** manual, autoscan, bazarr (an alias of manual), Sonarr, Radarr, Lidarr, Readarr, Sportarr, Tdarr, notify.
- **Endpoints:**
  - `POST /triggers/{name}` takes a JSON body.
  - `GET /triggers/{name}` takes `?path=&hash=` or `?dir=`.
  - All triggers use **basic auth only**, with a single user.
- **Search flag on paths:** each path is tagged with whether it must exist. Deletes and the old path of a rename skip the existence check.
- **Rewrites:**
  - A regex `{from, to}` list, configured per trigger (applied at ingest) and per target (applied at dispatch).
  - Rules are **not anchored and are applied in a chain**, so a later rule can rewrite the result of an earlier one.
- **Filters:** include and exclude regex lists, per trigger and per target.
- **Target excludes per trigger:** a trigger can list targets it must not send to. This breaks Tdarr→Tdarr loops.
- **Timers:**
  - `can_process = now + wait`, with a default of 60s.
  - Per-event-type `event_timers` add to that base wait.
- **notify:** a debounced inotify or polling backend.
- **`check_path` and `hash`:**
  - Can verify that a file exists, and optionally its sha256, before dispatching.
  - Rows with a hash mismatch are re-hashed on every tick while they stay pending.

### Targets
- **Plex:**
  - `GET library/sections` is called on every batch, so the library list is always fresh.
  - **Every** matching library is scanned, one `refresh?path=<parent dir>` per *file* with no dedup. A season pack of 20 files sends 20 identical requests.
  - Optional item refresh or analyze, which finds items through a fragile title search.
  - **`empty_trash` only after the scan has been observed to complete:** it polls `refreshing` and `scannedAt`, and skips the trash step if any scan in that library failed. This logic is well tested.
- **Emby / Jellyfin:**
  - Libraries come from `Library/VirtualFolders` on every batch.
  - With `refresh_metadata`, it pages through **every item in the library** to find each path (O(library size)), then calls `Items/{id}/Refresh`.
  - Paths it can't find are batched into a single `Library/Media/Updated` call.
- **Other targets:**
  - Sonarr and Radarr: `RefreshSeries` / `RefreshMovie` commands.
  - Tdarr: `scan-files`.
  - FileFlows: reprocess, or a manual add.
  - Audiobookshelf: `watcher/update`.
  - Autopulse: chains to another autopulse instance.
  - Command: runs a command, given the path as an argument or through a shell.

### Config, API and UI
- **Config:**
  - figment, accepting TOML, YAML or JSON.
  - `AUTOPULSE__SECTION__KEY` environment overrides, plus **`…__FILE` variables that load secrets from files**.
- **Anchors:** a global list that pauses all processing.
- **Outgoing webhooks:**
  - Discord, Hookshot (Matrix), or generic JSON.
  - Aggregated in memory and flushed every 10s, so they are lost on restart.
  - The transport honours `Retry-After`.
- **API:**
  - `/stats`, `/list`, `/status/{id}`, `/login`.
  - `/api/config-template`, which generates a config for Bazarr.
- **UI:**
  - Server-rendered with live updates over SSE.
  - Event list, event detail with a pipeline view, manual retry.
  - **Manual add with a preview** of the rewritten path and whether it exists.
  - Read-only config view with secrets redacted.
  - CSRF protection and login rate limiting.
- **Auth:** a single user, `admin`/`password` by default. Credentials are not compared in constant time.

### Tests
- About 241 tests: payload parsing, filters, rewrites, path matching, upsert concurrency, Plex trash behaviour against a stub, the webhook transport, auth.
- CI runs clippy with `-D warnings`.
- Emby and the Arr targets have no tests, and neither does the runner's end-to-end state machine.

## Worth adopting
1. **Dedup enforced by the database**, using a unique partial index on pending entries plus an upsert. This fits our per-target, per-folder rows.
2. **Optimistic compare-and-set on status writes**, in addition to our generation counter.
3. **Fresh library lookups.** We planned a cache refreshed on a miss; autopulse simply fetches every batch. Either works as long as the list is never stale forever.
4. **Plex empty trash only after the scan is observed to complete** (watch `refreshing` and `scannedAt`), and never when a scan in that library failed. **Adopt for our Plex empty-trash option**, but run the wait per target so it never blocks the other targets.
5. **A "must exist" flag per path**: deletes and the old path of a rename skip the check. We already decided this.
6. **Per-event-type extra wait** on top of a trigger's minimum age.
7. **Target excludes per trigger**, to prevent loops such as Tdarr→Tdarr or autoplow→autoplow.
8. **Include and exclude filters** per trigger and per target.
9. **Loading secrets from files** with `__FILE` environment variables. Useful for Docker secrets and Ansible.
10. **Manual-add preview** in the UI, showing the rewrite and the existence check.
11. **An outgoing webhook transport that respects `Retry-After`.** Our queue would be durable rather than in memory.
12. **Bazarr compatibility:** `GET /triggers/bazarr?path=` and `GET /stats`.

## Behaviours to handle differently in Autoplow
- **Shared single runner:** one sequential runner shared by all targets, and one retry clock shared across targets.
- **Short retries:** retries that give up after about a minute, and terminal failure without classifying the error.
- **Scan granularity:** scanning per file with no folder aggregation, and scanning every matching Plex library.
- **Slow Emby lookups:** walking the entire library to find an item.
- **Rewrites:** unanchored, chained regex rewrites.
- **Unbounded data:** completed rows that are never pruned.
- **Lost notifications:** the outgoing webhook queue is held only in memory.
- **Auth:** one basic-auth user with weak defaults.
