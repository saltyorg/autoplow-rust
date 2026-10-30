# Spec: the scan pipeline (v1)

**Module:** `scan` · **Depends on:** core, targets, arr, notifications · **Decisions:** ADR-0008, ADR-0009, ADR-0010 · **Status:** approved 2026-10-27

## Objective
Turn every change signal (Arr events, legacy/Bazarr/generic webhooks, local filesystem, manual/API; Drive via `gdrive`) into the minimal, correct set of folder scans on every relevant media server, without ever losing an event, and with one slow or offline server never delaying the others.

## Non-goals
- Item metadata refresh/analyze (autopulse style; ADR-0009)
- Waiting for Plex analysis before upload
- Scanning library roots by default

This consolidates the scan decisions in the ADRs in [../decisions/](../decisions/README.md). The architecture is described in [../architecture.md](../architecture.md).

## Triggers
| Trigger | Notes |
|---|---|
| Sonarr / Whisparr v2 | Webhook connection the app manages (or set up by hand). Uses per-file `Download` events **and** Import Complete, deduplicated by `downloadId` and folder. Rename (old and new folders), EpisodeFileDelete, SeriesDelete. |
| Radarr / Whisparr v3 (eros) | Download, Rename (old and new folders), MovieFileDelete, MovieDelete. |
| Lidarr | Download (`trackFiles[]`), Rename, Retag, ArtistDelete, AlbumDelete. |
| Bazarr | Bazarr's built-in "external webhook": `GET /triggers/bazarr?path=<media parent dir>&action_type=…` with basic auth. Serve `GET /stats` → 200 so its Test button works. |
| Generic webhook | `POST {paths:[...]}` |
| Legacy | autoscan `/triggers/{sonarr,radarr,lidarr,manual}` and A-Train `/triggers/a-train/{drive}`. These are thin adapters into the same pipeline. |
| Local filesystem | Each path is watched with inotify, a walk, or both. |
| Google Drive | OAuth, snapshot plus the Changes API. Covered in its own spec. |
| Manual / API | From the UI and the REST API. |

Common to all triggers:
- **Filters:** include and exclude regexes, per trigger and per target.
- **Target excludes:** a trigger can list targets it must never feed, to prevent loops.
- **Extra wait per event type:** optional, added on top of the trigger's minimum age.
- Each trigger has its own **minimum age** and its own **rewrite rule set**.
- Auth: header token, basic auth or query token, in any combination. Each trigger uses either the global shared credentials or its own (the user chooses). Auto-configured triggers default to their own per-instance credentials. A request needs to satisfy any one of the enabled methods. There is no open mode. The managed Arr connections also carry a fingerprint header.
- A `Test` event returns 2xx and queues nothing.

## Paths
- Rewrite rule sets exist at three scopes: per trigger, per target, and per trigger→target pair. A pair's own set replaces the target's set *(decided 2026-10-27)*.
- Overlapping source prefixes within one set are rejected.
- **Paths are compared by component** (cleaned, split on `/`), so a trailing slash is irrelevant and `/mnt/Movies` can never match `/mnt/Movies4K`. Paths are Linux absolute paths.
- **Library resolution:** a folder is scanned in **exactly the set of libraries (on one or more servers) whose locations contain it by components**. That is the same set the server would index. There is no accidental multi-match, and an intended one (the same location in two libraries) is honoured.
- Mappings are chosen with a filesystem picker for each side, or suggested from evidence and then confirmed.

## Queueing
1. Each event resolves to the **file's parent folder**. Delete events skip the "path must exist" check.
2. The folder is upserted into **each target's own durable queue**, keyed on (target, folder), with a generation counter.
3. **Coalescing:** if a parent folder is already queued for that target, the child is absorbed into it.
4. **Readiness:** an entry is ready once the trigger's minimum age has passed since its last event, or once the target's maximum wait has passed since its first event.
5. **Order:** FIFO by ready time. There are no priorities.
6. **Never lost:** an event that arrives after dispatch bumps the generation, so the entry stays queued and another scan follows.

## Delivery
- **Path must exist (optional):** per trigger and per target. Add and change entries are held until the path exists at the target-side location, retried with backoff, and logged with a warning after a timeout. Deletes are exempt.
- **Anchors:**
  - Bound globally, per target, per library or per path.
  - All anchors that apply must be present. If any is missing the entry is held, and deletes are never sent while anchors are missing.
- **Library resolution:**
  - Library lists are cached per target. The cache is refreshed periodically and whenever a lookup misses.
  - A folder that matches no library is reported as *unmatched*, not silently dropped.
- **Library root scans:** rejected by default, with a per-target setting to allow them.
- **Batching:** used where the target supports it (Tofa scoped scan, Emby/Jellyfin), up to a maximum batch size. Plex gets one request per folder.
- **Errors:**
  - Target-level errors trigger exponential backoff for that target only, honouring `Retry-After`.
  - Per-path errors are retried with backoff.
  - The UI shows why each entry is waiting.
- **Dead letters** *(added 2026-10-30)*: an entry that keeps failing for a path-level reason (for example "no library contains this path") is dead-lettered after N attempts and raises `item.deadlettered`. Target-level outages never dead-letter; those entries wait for the target.
  - The UI offers **Retry** and **Discard** for each one, and **Discard all** per target.
  - Dead letters are pruned automatically after 30 days (configurable).

- **Post-delivery verification (optional, per target, off by default):** after delivery, query the target for the expected path (present for adds and changes, absent for deletes) within the target's known processing delay plus a margin. If the check fails, warn (for example "library folder not registered on the server, consider re-adding the library") instead of assuming success. This is motivated by the Jellyfin empty-folder and Plex disrupted-initial-scan findings.
- **Server delays shown in the UI:** Jellyfin and Emby apply their own monitor delay before acting on `Media/Updated` (measured 60 s and 90 s).

## Targets
| Target | Scan call | Extras |
|---|---|---|
| Plex | `GET /library/sections/{id}/refresh?path=` | **Empty trash** after delete scans: optional, off by default, guarded by anchors. The UI explains it is only useful when Plex's automatic empty-trash setting is off. The trash is emptied only after the scan is **observed to finish** (`refreshing`/`scannedAt`), and never if a scan in that library failed. The wait happens in the Plex worker only. |
| Emby / Jellyfin | `POST /Library/Media/Updated` (batched) | |
| Tofa | `POST /api/v1/libraries/{id}/scan/scoped {paths}` (batched) | Completion status is available from `/scan/status`. |
| Tdarr | `POST /api/v2/scan-files` | |
| Another autoplow | Our own generic webhook, or the API | |

## UI and API extras
- **Manual-add preview:** shows the rewrite per target, the library it resolves to, and whether the path exists.
- **Bazarr compatibility:** `GET /stats` and `GET /api/config-template` (Bazarr's config generator).

## Open items
- ~~The webhook mechanics for Bazarr and Whisparr~~ (resolved, see ../research/arr-connect-api.md).
- How to discover Tofa's library root paths.
- Default values for minimum age and maximum wait.
- ~~Evaluate autopulse's scan approach~~: done. Approach A stays the only mode (see [ADR-0009](../decisions/0009-folder-level-scans-only.md)).

## Acceptance criteria
1. An Arr `Download` for a file queues exactly one scan per target whose library contains the file's parent folder by path components; `Test` events queue nothing and return 2xx.
2. Two events for the same folder within the minimum age produce one delivery; an event arriving after a delivery was dispatched always produces another delivery (generation acknowledgement).
3. A queued parent folder absorbs later child folders for the same target; a child queued first is replaced when its parent arrives.
4. With a target offline, deliveries to other targets continue unaffected; the offline target's entries are retained across restart and delivered after it recovers (exponential backoff honouring `Retry-After`).
5. Every queued entry exposes a wait reason (debounce, max-wait pending, anchor missing, path missing, target backoff, ready) via the API.
6. Delete events skip the existence check; with the optional 'path must exist' check enabled, add/change entries are held until the path exists or a timeout warning is raised.
7. With any applicable anchor missing, no delivery (and never a delete) is sent for the affected scope.
8. `/mnt/Movies` never matches a library at `/mnt/Movies4K`; a folder contained by locations in two libraries is delivered to both.
9. Jellyfin/Emby deliveries for one target are batched into one `Media/Updated` call per delivery cycle (bounded batch size); Plex receives one request per folder.
10. Burst: 1 000 events/minute for 10 minutes are accepted without loss (no 5xx other than back-pressure 503 with `Retry-After`), and all resulting scans are delivered once targets accept them.
11. Optional post-delivery verification flags a target that accepted a scan but never indexed the expected path within its delay + margin.
12. Legacy autoscan `/triggers/{sonarr,radarr,lidarr,manual}`, A-Train and Bazarr (`/triggers/bazarr`, `/stats`, `/api/config-template`) requests recorded from those tools are accepted and produce the same scans.
13. An entry failing for a path-level reason is dead-lettered after N attempts and can be retried or discarded (one at a time or all for a target); dead letters older than the pruning period are removed automatically. A target outage never dead-letters entries.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Changing per-trigger auth semantics; Adding a new trigger or target type.
- **Never:** Drop an accepted event; Scan a library root unless the target explicitly allows it; Use longest-match or raw string-prefix path logic.

## Open questions
- Default minimum age and maximum wait values (**decided 2026-10-27:** min 30 s, max 10 min; per trigger/target configurable).
- **Decided 2026-10-27:** a trigger→target pair's rule set replaces the target's set for that pair.
