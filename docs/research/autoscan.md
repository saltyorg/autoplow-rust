# Autoscan (saltydk fork): codebase report

- **Source:** github.com/saltydk/autoscan, a fork of Cloudbox/autoscan.
- **Language:** Go, about 15k lines.
- **Snapshot analysed:** commit `60dcbe8` (2026-10-25).
- **Caveat:** the clone was shallow, so statements about what the fork adds compared with upstream are inferences.

## What it does
Autoscan takes in "something changed at path X" events from webhooks, filesystem watchers or Google Drive change polling. It records them in durable per-target queues in SQLite and then asks media servers (Plex, Emby, Jellyfin, or another autoscan) to do a partial scan of just that folder.

## 1. Architecture
### Core types (autoscan.go)
- **`Scan{Folder, Priority, Time}`:** a folder only. `Time` is the time of the last event and drives the min-age check.
- **`ProcessorFunc func(...Scan) error`:** in practice this is `proc.Add`.
- **`Trigger func(ProcessorFunc)`:** the signature for daemon triggers.
- **`HTTPTrigger func(ProcessorFunc) http.Handler`:** the signature for webhook triggers.
- **`Target interface { Scan(Scan) error; Available() error }`:** what each media server implements.
- **Sentinel errors:** `ErrTargetUnavailable`, `ErrFatal`, `ErrScanRejected`, `ErrLibraryNotMatched`, `ErrNoScans`, `ErrAnchorUnavailable`.
- **Rewriter:** a list of regex rewrites. The first match wins and `$1` captures are supported.
- **Filterer:** excludes are checked first. If any includes are set, a path must match one of them. Only bernard and inotify use it.
- **Path validation:** paths must be absolute with no NUL byte. Relative file paths may not contain `..`.
- **http.go:** classifies outbound HTTP errors, enforces the response size limit and handles `Retry-After`.

### Process model (cmd/autoscan/main.go)
Startup runs in this order:
1. Parse flags (kong).
2. Set up logging: zerolog, with a lumberjack-rotated log file.
3. Open SQLite (modernc, pure Go) with `SetMaxOpenConns(1)`. No WAL and no busy timeout are set.
4. Decode the YAML config strictly.
5. Run migrations.
6. Configure the targets. This computes each target's queue ID and moves rows from the legacy shared queue into the per-target queues.
7. Start the bernard and inotify goroutines.
8. Start the chi HTTP server.
9. Start the stats goroutine.
10. Mark the process ready: `/health` starts returning 200 and systemd receives `READY=1`.
11. Start one `runTarget` worker goroutine per target.

There is no signal handling and no graceful shutdown.

### Flow of a scan
1. A trigger decodes its input, derives the folder, rewrites it and validates it.
2. The trigger calls `proc.Add`, which upserts one row per configured target in a single transaction. The webhook returns 200 only after the commit.
3. Each target's worker loop picks the best eligible row: highest priority first, then oldest time, and only rows with `time < now - minimum-age`.
4. The worker checks the anchors, calls `target.Scan` and acknowledges the row.
5. After a successful scan the worker sleeps for `scan-delay`. In other cases it backs off for 15s, or `max(15s, Retry-After)`.

## 2. Triggers
### Behaviour shared by all triggers
- **Authentication:** one global HTTP Basic Auth protects all `/triggers/*` routes, but only when both username and password are set. `/health` is open.
- **Per-trigger settings:** `priority` (higher is processed first) and `rewrite`.
- **Batch validation:** one invalid path rejects the whole batch with a 400.
- **No body limit:** request bodies have no size limit.

### Individual triggers
- **Manual:** `GET`, `POST` and `HEAD` on `/triggers/manual?dir=` (the `dir` parameter can be repeated). A GET returns an embedded HTML form.
- **A-Train:** `POST /triggers/a-train/{drive}` with body `{created:[], deleted:[]}`. Per-drive rewrites are applied before the global ones.
- **Sonarr:** `POST /triggers/{name}`.

  | Event | Folder queued |
  |---|---|
  | Download, EpisodeFileDelete | The directory of `series.path` + `episodeFile.relativePath`, i.e. the season folder |
  | SeriesDelete | The series path |
  | Rename | Both the old and the new directories |
  | Test, and any other event | Nothing (returns 200) |

- **Radarr:**

  | Event | Folder queued |
  |---|---|
  | Download, MovieFileDelete | The directory of `folderPath` + `relativePath` |
  | MovieDelete, Rename | `folderPath` |

  On a Rename, Radarr does not scan the old folder.
- **Lidarr and Readarr:** only `Download` events are handled, and other events return 400. Each file path is rewritten first and then reduced to its directory. That is the reverse of the order Sonarr and Radarr use.
- **inotify:**
  - Uses fsnotify and recursively watches every directory under each root. Only Create, Rename and Remove events are handled; Write is ignored.
  - Tracks the directory lifecycle: a moved-in directory is walked and its file folders are batched, and duplicate child events are suppressed for 60s after a subtree is removed.
  - Debounces each folder in memory for 10s. That queue is lost on restart.
- **bernard:** not documented in the README.
  - Polls the Google Drive changes API on a cron schedule, using a service account and `l3uddz/bernard`.
  - Keeps its own file, folder and drive tables in the same SQLite database.
  - Rate limits are 8 requests/s per account and at most 5 concurrent syncs.
  - Changed items are reduced to their root parent folders.
  - The scans are handed to the processor before the page token is advanced, so a failure replays the changes.
  - A drive's job is disabled for good after 5 consecutive errors.

## 3. Processor and persistence
### Migrations and schema
- Migrations are embedded `N_name.sql` files, tracked per component in `schema_migration(component, version)`.
- **`scan(folder PK, priority, time)`:** the legacy shared queue.
- **`target_scan(target_id, folder, priority, time, generation, PK(target_id, folder))`:** the per-target queue added by the fork, with an index on `(target_id, priority DESC, time ASC)`.

### Upsert and acknowledgement
- An incoming event upserts its row: `priority = MAX(old, new)`, `time = new`, `generation += 1`.
- Acknowledgement deletes the row **only if its generation is unchanged**. An event that arrives while a scan is in flight therefore re-queues the folder instead of being lost. Delivery is at least once.

### Queue identity
- The queue ID is `kind:name`.
- An unnamed target uses `kind:sha256(url + rewrite)`; the token is not included, so rotating a token keeps the queue.
- Duplicate IDs get a `#n` suffix.
- A removed target's rows stay in the database, dormant.

### Debounce
- `minimum-age` (default 10m) is a sliding window: every new event resets `time`. A folder that keeps changing can therefore be delayed indefinitely, because there is no maximum wait.
- Parent and child folders are not coalesced.

### Anchors
- Anchor files are checked before every delivery. If one is missing, the scan is held and the worker retries in 15s. State changes are logged once.

### Throughput
- Each target processes one folder at a time, serially, followed by a 5s `scan-delay`.

### Error classification (http.go)
| Response | Result |
|---|---|
| Transport errors and timeouts | Retry |
| 404, 408, 429, 500, 502, 503, 504 | Retry |
| Oversized responses | Retry |
| 401 | Fatal |
| Any other non-2xx | Fatal |

- A fatal error **stops that target's worker until restart**.
- An unavailable target is probed again after `max(15s, Retry-After)`.

### Stats
- Logged every `scan-stats` (default 1h): remaining, received, processed, retried, skipped, rejected.
- The same numbers are sent to systemd as `STATUS`.

## 4. Targets
All targets share these settings:
- A per-target `rewrite`.
- A 30s client timeout.
- `response-limit`, default 10 MiB.

### Plex
- Sends `X-Plex-Token` and `Accept: application/json`.
- `GET /` checks that the server version is at least 1.20.
- `GET /library/sections` lists the sections and reads `Location[].path`.
- The scan itself is `GET /library/sections/{key}/refresh?path=<folder>`, sent for **every** section whose location is a prefix of the folder.
- Scanning a library root is rejected, and a folder that matches no section is skipped.
- The library list is cached forever, so a library added later is never matched and its scans are skipped.

### Emby
- Sends `X-Emby-Token`.
- Availability is `GET /emby/System/Info`.
- Libraries come from `GET /emby/Library/SelectableMediaFolders`.
- The scan is `POST /Library/Media/Updated` with body `{"Updates":[{"path":...,"updateType":"Created"}]}`.

### Jellyfin
- Same code as Emby, with these differences:
  - Authorization header: `MediaBrowser Token="..."`.
  - Availability: `/System/Info`.
  - Libraries: `/Library/VirtualFolders`.
  - `updateType` is `"Modified"`.

### Autoscan (another instance)
- Availability is `HEAD /triggers/manual`.
- The scan is `POST /triggers/manual?dir=`, with optional Basic Auth.

## 5. Configuration
### Command-line flags and environment variables
| Flag | Environment variable |
|---|---|
| `--config` | `AUTOSCAN_CONFIG` |
| `--database` | `AUTOSCAN_DATABASE` |
| `--log` | `AUTOSCAN_LOG` |
| `-v` / `-vv` | `AUTOSCAN_VERBOSITY` |

Further flags with no listed environment variable are `--log-format text|json`, `--log-level` and `--http-timeout`.

### YAML keys
- Top level: `host[]`, `port` (3030), `minimum-age`, `scan-delay`, `scan-stats`, `anchors[]`, `authentication{username, password}`.
- `triggers`: `manual`, `a-train{drives[]}`, `bernard[]`, `inotify[]`, and `sonarr|radarr|lidarr|readarr[]{name, priority, rewrite}`.
- `targets`: `plex|emby|jellyfin[]{name, url, token, rewrite, verbosity, response-limit}` and `autoscan[]{name, url, username, password, rewrite}`.

### Packaging
- GoReleaser builds static binaries with CGO disabled.
- Docker images: s6-overlay Alpine, and a distroless nonroot variant.

## 6. Dependencies
| Module | Used for |
|---|---|
| kong | CLI |
| chi | Router |
| zerolog | Logging |
| lumberjack | Log rotation |
| yaml v3 | Config |
| modernc sqlite | Pure-Go SQLite |
| fsnotify | inotify trigger |
| l3uddz/bernard | Google Drive changes |
| m-rots/stubbs | Service-account OAuth |
| robfig/cron | Bernard scheduling |
| x/sync | Concurrency helpers |
| x/time | Rate limiting |

## 7. Assessment
### Worth keeping
- Small Trigger and Target interfaces.
- **Per-target durable queues with generation acknowledgement.**
- SQL upsert coalescing.
- Error classes that drive the retry policy, including `Retry-After`.
- Anchors.
- Rejecting scans of a library root.
- All-or-nothing webhook batches.
- Bernard's handoff to the processor before the page token advances.
- Static binary, strict config and a readiness probe.
- Extensive tests.

### Behaviours to improve in Autoplow
1. A fatal error stops the target's worker until restart, even when it is a single 400 or 403 on one path.
2. The library list is never refreshed, so scans for libraries added later are lost.
3. The debounce is sliding with no maximum wait.
4. Parent and child folders are not coalesced.
5. Delivery is serial with a 5s delay (about 12 folders per minute per target), and Emby/Jellyfin calls are not batched even though their API accepts several updates.
6. There is one SQLite connection with no WAL.
7. There is no graceful shutdown, and the inotify debounce queue is lost on exit.
8. Authentication is weak: one global credential, off by default.
9. There is no request body limit.
10. The *arr triggers behave inconsistently, for example on Radarr renames and in the order of rewrite and directory reduction.
11. A Plex scan across several sections is not atomic: if one fails, the retry re-sends all of them.
12. inotify ignores Write events.
13. Regex rewrites match on raw prefixes: `^/media` also matches `/media2`.
14. There are no metrics and no API for inspecting the queue.
