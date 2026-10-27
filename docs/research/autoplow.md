# autoplow (the earlier Go attempt): codebase report

- **Repository:** github.com/saltyorg/autoplow
- **Snapshot:** `71fb9e6` (2026-01-14)
- **Size:** about 44k lines of Go plus 11k lines of HTML templates
- **README:** none

## Summary
autoplow is a single Go binary backed by a pure-Go SQLite database. All configuration happens in a web UI built with server-rendered htmx, Alpine and Tailwind, with live updates over SSE. It merges four existing tools:

| Tool | What autoplow does for it |
|---|---|
| autoscan | Receives scan triggers and sends targeted scans to Plex, Emby, Jellyfin, Tdarr or another autoplow |
| cloudplow | Uploads through a managed `rclone rcd` |
| matcharr | Detects and fixes wrong IDs and files in the media server, compared against Sonarr and Radarr |
| PAL | Propagates audio and subtitle choices, driven by the Plex websocket |

**Novel idea: Plex scan-completion gating.** A file stays local until Plex's analysis activity for that title has gone idle, and only then is it uploaded. To decide which activity belongs to which title, autoplow fuzzy-matches the websocket activity text against the title. This is fragile.

## Package map
| Package | Go LOC | Role |
|---|---|---|
| `internal/web/handlers` | 11,646 | UI pages, htmx partials, webhook API (contains business logic) |
| `internal/database` | 7,880 | Hand-written SQL, 36 migrations |
| `internal/targets` | 6,160 | Plex, Emby/Jellyfin, Tdarr and Autoplow clients; Plex scan-completion heuristics; matcharr and PAL Plex API |
| `internal/matcharr` | 3,507 | Mismatch engine |
| `internal/plexautolang` | 2,398 | PAL port |
| `internal/uploader` | 2,176 | rclone RC upload queue |
| `internal/gdrive` | 1,980 | Google Drive Changes API trigger |
| `internal/rclone` | 1,653 | `rcd` process manager, RC client, option parsing |
| `internal/processor` | 1,135 | Scan queue and batcher |
| `internal/notification` | 750 | Discord and webhook providers (**not wired to any events**) |
| `internal/auth` | 738 | bcrypt users, sessions, trigger API keys, AES-GCM secrets |
| `internal/inotify`, `internal/polling` | 682 / 418 | Local filesystem triggers |
| `internal/throttle` | 634 | Bandwidth limiting based on active sessions |
| `internal/scantracker` | 359 | Gates uploads until the Plex scan has finished |

**Tests:** about 760 lines, covering only matcharr comparison and a few Plex string helpers. The concurrent code has no tests.

## 1. Architecture
### Configuration
- **CLI flags:** only port, bind address, allowed subnet, DB path and three timeouts.
- **Everything else:** stored in the DB:
  - a key/value `settings` table
  - JSON `config` columns on `triggers` and `targets`
  - dedicated tables for the rest

### Startup order (`main.go`)
1. Open the DB, create or load the encryption key (`<db>.key`), run migrations, re-encrypt trigger passwords.
2. Create the web server, which builds the targets manager, the PlexTracker and the processor. The processor always gets `processor.DefaultConfig()`.
3. Create the rclone manager.
4. Start the processor: an intake goroutine, a 1 s batch loop, and one goroutine per scan, capped at 50.
5. Start a websocket watcher for each enabled Plex, Emby or Jellyfin target. Watchers reconnect with exponential backoff.
6. If uploads are enabled, start the upload subsystem: three uploader goroutines, `rcd` plus its monitor, and the throttle poll loop.
7. Start the remaining background work:
   - inotify, polling and Google Drive pollers
   - matcharr cron
   - PAL callbacks and worker pools
   - update checker

### Communication between components
- **Wiring:** setter injection, mostly without locks.
- **DB tables as queues:** `scans` (pending → scanning → completed/failed/skipped), and `upload_requests` → `uploads`.
- **Channels:** 100-slot buffers. The processor and SSE channels drop items when full.
- **Callbacks:** sessions → throttle; Plex notifications → PAL; PlexTracker → uploader.
- **Browser updates:** SSE with about 25 event types, mapped to htmx refreshes.

### End-to-end flow
1. **Intake.** Any of these queues a scan:
   - an inotify or polling event (5 s debounce), which queues a scan of the parent dir and an upload of the file
   - a webhook
   - a Google Drive change
2. **Processor.** Runs every 1 s and applies these steps in order:
   1. Minimum age of at least 5 s.
   2. Per-target exclusions.
   3. Path mapping.
   4. A 5 s dedupe window per (target, mapped path), preferring triggers that can upload.
   5. Grouping by parent dir.
   6. Anchor check.
   7. File-size stability check.

   Targets are then scanned one after another.
3. **PlexTracker.** Waits until Plex activity is idle (at least 60 s), then releases the upload.
4. **Uploader.** Submits one global rclone `job/batch` of `operations/movefile` or `copyfile` calls (up to 100 files), monitors progress, and fails over to another remote if needed.
5. **Throttle.** Converts the session count into a `core/bwlimit` call.

## 2. Features
### Triggers (autoscan side)
- **Webhooks:**
  - `POST /api/triggers/{sonarr|radarr|lidarr|webhook|autoplow|a_train}/{id}`
  - `GET|POST /api/triggers/{autoscan|bazarr}/{id}`
  - Auth is per trigger: an API key (query string or `X-API-Key` header), or Basic auth. Basic auth passwords are AES-GCM encrypted rather than hashed.
- **Sonarr folder mapping:** file events scan the season folder; Rename scans both the old and the new folder; SeriesDelete scans the series folder. Radarr and Lidarr are handled the same way.
- **Path filters and rewrites:** per-trigger include/exclude by prefix, extension or regex, applied before or after the rewrite. Rewrites can be prefix or regex.
- **Delete events** skip the existence check.
- **inotify:** recursive fsnotify watching Create and Write events, with a 5 s debounce per path.
- **Polling:** walks the tree; only new paths are detected.
- **Google Drive:**
  - OAuth with `drive.readonly`; refresh tokens are stored encrypted.
  - A full snapshot is stored in `gdrive_snapshot_entries`, then the Changes API is used incrementally.
  - Paths are resolved through `parents`, rewritten with folder-based rules, and filtered against library roots. Redundant paths are pruned.
  - An invalid page token triggers a re-snapshot and a diff.
  - Rate limited to 10 req/s, with retries that honor `Retry-After`.
  - No service-account support.

### Processor
- **Queueing:** `QueueScan` writes to a 100-slot channel and **drops requests when it is full**. Pending duplicates are merged.
- **Timeout:** one 60 s context covers all targets, including each target's `ScanDelay`.
- **Retries:** none. The old `retry` status is converted to `failed` at startup.
- **Plex tracking:** blocks one of the 50 scan slots while waiting.
- **Retention:** scans are deleted after 7 days.

### Targets
- **Interface:** `Target{Name, Type, Scan, TestConnection, GetLibraries, GetSessions, SupportsSessionMonitoring}`, plus optional interfaces for session watching, scan-completion waiting, and matcharr fixing.
- **Plex scan:**
  - A semaphore allows 1–3 concurrent scans.
  - `GET /library/sections` is called on every scan, so new libraries are picked up.
  - The scan request is `GET /library/sections/{id}/refresh?path=`.
- **Plex sessions and websocket:** `/status/sessions`, and the websocket at `/:/websockets/notifications`. Websocket callbacks run synchronously on the reader goroutine.
- **Plex scan-completion tracking** (about 1,000 lines):
  1. Derive title, year and season patterns from the path.
  2. Run `/library/search` 3 s after the scan, plus an `allLeaves` path match.
  3. Watch these activities: `library.update.section`, `library.update.item.metadata`, and `media.generate.{chapter.thumbs,voice.activity,credits,bif,intros}`.
  4. Fuzzy-match each activity's `subtitle` to the title, gated by year and season.
  5. Treat the title as done when no activities are active and the idle threshold (at least 60 s) has passed.
- **Plex calls for matcharr:**
  - `/library/sections/{id}/all?includeGuids=1`, plus batched `/library/metadata/{k1,..}` requests
  - fixes via `PUT /library/metadata/{id}/match?guid=…&name=`
- **Plex calls for PAL:**
  - sets streams via `PUT /library/parts/{id}?audioStreamID=&subtitleStreamID=`, using the user's token
  - gets user tokens from plex.tv `api/servers/{machineID}/shared_servers` (XML); user 1 uses the owner token
- **Emby and Jellyfin:**
  - **Scan:** pages through `/Items?ParentId&Recursive&Fields=Path` to find the item. That is a full library walk on every request. It then calls `POST /Items/{id}/Refresh`, or falls back to `POST /Library/Media/Updated`.
  - **Sessions:** through a websocket.
  - **matcharr fix:** `POST /Items/{id}` with empty Genres and Tags, which likely wipes them.
- **Tdarr:** `POST /api/v2/scan-files`.
- **Autoplow:** `POST {"paths":[..]}` to another instance.

### Uploads (cloudplow side)
- **Model:**

  | Object | Fields |
  |---|---|
  | Remotes | rclone remote, plus backend `TransferOptions` |
  | Destinations | local path, move/copy, minimum file age, minimum folder size, excludes, allowed triggers |
  | Destination remotes | priority, sub-path |

- **Pipeline:**
  1. `upload_requests` is drained every 2 s.
  2. Each request is checked against the throttle skip flag, the trigger's upload flag, the destination (longest prefix match), duplicates, and readiness.
  3. Readiness works one of two ways. If Plex tracking is enabled, a matched tracked scan is required. Otherwise, the file age and the destination folder size (a full walk) are checked.
  4. Only **one global batch** runs at a time: up to 100 files sent as `job/batch` with an inline `dstFs="name,opt=val:path"` and `_group=autoplow`.
  5. Progress comes from `core/stats` and `core/transferred`, **matched by basename**.
  6. A failed upload is retried 3 times, then fails over to the next remote.
  7. In move mode, empty dirs are removed afterwards.
  8. Orphaned uploads are resumed at boot.
- **rclone manager:**
  - Managed mode runs `rclone rcd --rc-user --rc-pass` and picks a free port, health-checks the process, and restarts it if it dies.
  - Unmanaged mode connects to an existing rcd.
  - When rclone is ready, autoplow applies `options/set`.
  - The `/rclone` options explorer imports the rclone Go packages to parse option types.
- **Compared with cloudplow:**
  - Moves file by file instead of whole folders.
  - No per-remote size trigger.
  - **No service-account rotation.**

### Throttle
- **Bandwidth formula:** start from the maximum (or a schedule's limit), subtract 25 MB/s per session, and floor at the minimum. When the maximum is unlimited, any active session drops it straight to the minimum.
- **Upload skipping:** `SkipUploadsBelow` sets a flag the uploader reads.
- **Not implemented:** no filtering by paused, LAN or transcode state. Schedules are never loaded.

### matcharr (the most complete module, and the only one with tests)
- **Phases:**
  1. Load Arr root folders, and target libraries from the DB cache (24 h max age).
  2. Select libraries by overlap with the root folders, using path-boundary-aware matching.
  3. Fetch Arr series and movies, and library items with their provider IDs.
  4. Compare in parallel (3 workers, or 1 when auto-fixing), matching by exact normalized path.
- **Expected ID:** TVDB for Sonarr, TMDB for Radarr, IMDB as the fallback, with cross-ID fallbacks.
- **What it records:**
  - ID mismatches
  - "gaps" in both directions (items missing on one side)
  - **file mismatches**: per SxxEyy for Sonarr (`episode` + `episodefile`), and per movie for Radarr (`moviefile`), compared against the server's files, with an ignore list
- **Running it:**
  - Auto-fix waits 2 s between fixes.
  - Runs on a cron schedule with a 30 min timeout.
  - UI actions: fix, skip, fix-all, re-check, queue a scan, and view run logs.

### PAL port
- **Settings:** update level (show or season), strategy (all or next), triggers (play, scan, activity), concurrency. The ignore labels, ignore libraries and schedule settings are **stored but unused**.
- **Play and stop events:**
  1. Debounce for 1 s.
  2. Resolve which user is playing.
  3. Get that user's token.
  4. Read the live session streams.
  5. If the streams changed, store the user's preference for the show.
  6. Apply it to the show using PAL's scoring.
- **New episodes:** triggered by a timeline event, or a `library.update*` / `media.generate*` activity. autoplow then applies every stored preference for that show. Unlike PAL, which derives a reference from the user's last watched episode, autoplow keeps an explicit preference table.

### Notifications
- Discord and webhook providers can be configured and tested from the UI.
- **Nothing ever calls `Manager.Notify`**, so no notifications are sent.

## 3. Persistence
- **SQLite settings:** modernc, WAL, `busy_timeout=5000`, a single connection.
- **Migrations:** 36 in total, run by naively splitting on `;`. There is a special case for v29 and an "ensure matcharr schema" patch, both signs of schema drift.
- **Table groups:**

  | Group | Tables |
  |---|---|
  | Users and settings | users, sessions, settings |
  | Triggers and targets | triggers, targets, target_libraries |
  | Uploads | remotes, destinations, destination_remotes, upload_requests, uploads, upload_history (plus legacy upload tables) |
  | Scans and sessions | scans, scan_target_paths, active_sessions |
  | Notifications | notification_* |
  | matcharr | matcharr_arrs, matcharr_runs, matcharr_mismatches, matcharr_gaps, matcharr_file_mismatches, matcharr_file_ignores |
  | PAL | plex_auto_languages_preferences, plex_auto_languages_history, plex_auto_languages_config |
  | Google Drive | gdrive_accounts, gdrive_sync_state, gdrive_snapshot_entries |

- **Secrets:**
  - User password: bcrypt (cost 12).
  - Trigger passwords and Google tokens: AES-256-GCM, with a hardcoded legacy key as well.
  - Media server tokens, Arr keys and RC credentials: plaintext.

## 4. Web UI
- **Authentication:** single user created through a setup wizard. Session cookie with 7-day sliding expiry. No CSRF protection and no login rate limiting.
- **Pages:**
  - dashboard
  - triggers and targets (CRUD)
  - uploads: queue, active transfers, history, remotes, destinations
  - settings: general, processor anchors, logging, notifications, throttle, rclone, gdrive OAuth, about, DB maintenance, key regeneration
  - history and logs
  - Google Drive snapshot browser
  - rclone options explorer
  - matcharr (about 35 endpoints)
  - PAL
- **API:** there is no JSON management API.

## 5. Dependencies
| Library | Used for |
|---|---|
| chi | HTTP router |
| cobra | CLI |
| zerolog | Logging |
| lumberjack | Log rotation |
| modernc sqlite | Database |
| gorilla/websocket | Media-server websockets |
| fsnotify | inotify trigger |
| robfig/cron | matcharr schedule |
| x/crypto | Password hashing |
| oauth2 + google api | Google Drive |
| x/time/rate | Rate limiting |
| **rclone v1.72.1 as a library** | Only string and option helpers, but it pulls in OpenTelemetry, gRPC and cloud auth |

The build is Linux-only.

## 6. Issues found at snapshot 71fb9e6, and lessons
### Lifecycle and configuration
1. **Target edits and deletes never reach the running state.** The handlers write to the DB only. Cached targets keep their old URL and token, and websockets are not restarted. New targets get no websocket, sessions, tracking or PAL until the process restarts. The target cache map is also accessed without a lock.
2. **The processor ignores saved anchor and cleanup settings at boot.** It always uses `DefaultConfig()` (`server.go:87`), so the mount-safety anchors are off after a restart.
3. **inotify, polling, Google Drive and rclone managers cannot restart.** `Stop()` cancels a root context and `Start()` never recreates it. Removing the last trigger and then adding a new one silently does nothing.

### Filters and features configured in the UI but never applied
4. Exclude filters are never applied:
   - destination excludes (`Destination.ShouldExclude` has no callers)
   - target extension and regex excludes (`TargetConfig.ShouldExclude` has no callers)
5. Several features exist only in the UI:
   - notifications are never sent
   - throttle schedules are never loaded
   - the PAL ignore and schedule settings are unused
   - the upload retry delay is unused

### Uploader
6. **Requests skipped by the throttle are deleted** instead of deferred.
7. **Progress is matched by basename**, so two files with the same name in one batch collide.
8. **A finished batch can be handled twice.**
9. **Cancelling one upload orphans the rest of its batch** in `uploading`.

### Throttle
10. **Sessions from polling-mode targets are counted twice** (websocket plus polling).
11. **A nil context can cause a panic** if a session arrives before the throttle starts.

### Scan processing
12. **The scan queue drops requests when its 100 slots are full.**
13. **The single 60 s timeout includes each target's `ScanDelay`**, so a long delay always fails.
14. **Prefix matching has no path boundary**, so `/mnt/Movies4K` matches `/mnt/Movies`. This affects Plex and Emby library lookup, destinations, path mappings and excludes.

### matcharr
15. **The matcharr library cache expires after 24 h and is only refreshed at boot**, so a long-running instance stops finding libraries.

### Security and keys
16. **Regenerating the key does not re-encrypt Google Drive refresh tokens**, which breaks every Drive trigger.

### PAL and Plex tracking
17. **PAL can stall the Plex websocket reader:** it does a blocking send while holding a mutex.
18. **PAL logs every user's Plex token** (the `shared_servers` XML) at trace level.
19. **PlexTracker records and polling `seenFiles` grow without bound**, and tracker waits cannot be cancelled.

### Security
20. Security gaps:
   - `--rc-pass` is passed on the command line
   - a hardcoded legacy AES key
   - no CSRF protection
   - API keys accepted in the query string
   - unbounded webhook bodies
   - plaintext media-server tokens

### Structural lessons
- **Breadth over depth.** Four tools plus extras behind a bespoke UI, with many features finished only to the UI layer.
- **Startup-only wiring and components that can't restart**, so config changes need a process restart. Settings are stringly-typed and changes aren't propagated.
- **About 1,000 lines of fragile Plex heuristics** at the centre of the product.
- **Schema churn:** 36 migrations plus patches.
- **Almost no tests** on the concurrent code.
- **Very large files:** a 2.2k-line uploader struct and 11.6k lines of handlers that contain business logic.
- **The rclone library dependency** and the Linux-only build.

## 7. What to keep vs. change
### Keep
- Durable DB-backed queues with recovery on boot.
- Readiness reasons (`wait_state`) shown in the UI.
- Per-target path mapping and dedupe windows.
- Anchor files.
- The Google Drive snapshot + Changes design.
- rclone driven through RC: batches, stats groups, inline backend options.
- matcharr's phased fetch, boundary-aware mapping, ID fallbacks and file-mismatch detection.
- PAL's scoring, applied with per-user tokens.
- The token-redacting HTTP trace transport.
- A single binary with a UI.

### Change
- A typed config with change notification.
- Components that can be restarted.
- **One** boundary-aware path-prefix helper used everywhere.
- Track uploads by job or unique ID, never by basename.
- Never drop work under back-pressure.
- Non-blocking fan-out from websocket readers.
- Concurrency per remote instead of one global batch.
- Decide early whether "Plex analysed before upload" needs fuzzy activity matching, or whether a simpler signal is enough, such as per-item analysis state, or `/activities` idle plus a delay.
