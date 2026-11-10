# Spec: the scan pipeline (v1)

**Module:** `scan` · **Depends on:** core, targets, arr, notifications · **Decisions:** ADR-0008, ADR-0009, ADR-0010, ADR-0020 · **Status:** approved 2026-10-27

## Objective
Turn every change signal (Arr events, legacy/Bazarr/generic webhooks, local filesystem, manual/API; Drive via `gdrive`) into the minimal, correct set of folder scans on every relevant media server, without ever losing an event, and with one slow or offline server never delaying the others.

## Non-goals
- Item metadata refresh/analyze (autopulse style; ADR-0009)
- Waiting for Plex analysis before upload
- Scanning library roots by default
- Path mappings written as regular expressions; mappings are folder prefixes *(decided 2026-11-10)*
- Extra, custom-named trigger addresses such as `/triggers/sonarr4k`; hand-made webhooks are re-pointed once *(decided 2026-11-10)*
- A target that runs a program per path, and targets or triggers for Sonarr/Radarr refresh, FileFlows, Sportarr and Readarr
- Forwarding scans to an old autoscan
- Checking a file's hash before sending
- Priorities between triggers

This consolidates the scan decisions in the ADRs in [../decisions/](../decisions/README.md). The architecture is described in [../architecture.md](../architecture.md).

## Triggers
| Trigger | Notes |
|---|---|
| Sonarr / Whisparr v2 | Webhook connection the app manages (or set up by hand). Uses per-file `Download` events **and** Import Complete, deduplicated by `downloadId` and folder. Rename (old and new folders), EpisodeFileDelete, SeriesDelete. |
| Radarr / Whisparr v3 (eros) | Download, Rename (old and new folders), MovieFileDelete, MovieDelete. |
| Lidarr | Download (`trackFiles[]`), Rename, Retag, ArtistDelete, AlbumDelete. |
| Bazarr | Bazarr's built-in "external webhook": `GET /triggers/bazarr?path=<media parent dir>&action_type=…` with basic auth. Serve `GET /stats` → 200 so its Test button works. |
| Generic webhook | `POST {paths:[...], type}`. `type` is `add`, `change` or `delete` and defaults to `add`; a delete skips the existence check. |
| Legacy | autoscan `/triggers/{sonarr,radarr,lidarr,manual}` and A-Train `/triggers/a-train/{drive}`. These are thin adapters into the same pipeline. |
| Local filesystem | Each path is watched with inotify, a walk, or both. See "Watching local folders". |
| Google Drive | OAuth, snapshot plus the Changes API. Covered in its own spec. |
| Manual / API | From the UI and the REST API. |

Common to all triggers:
- **Filters:** include and exclude regexes, per trigger and per target, matched against the path after the trigger's rewrite rules.
- **Target excludes:** a trigger can list targets it must never feed, to prevent loops.
- **Extra wait per event type:** optional, added on top of the trigger's minimum age, and set in the trigger's dialog.
- Each trigger has its own **minimum age** and its own **rewrite rule set**.
- Auth: header token or basic auth, in any combination; a query-string token only on the legacy routes and for Bazarr, which cannot send a header (see the security rules in the core spec). Each trigger uses either the global shared credentials or its own (the user chooses). Auto-configured triggers default to their own per-instance credentials. A request needs to satisfy any one of the enabled methods. There is no open mode. The managed Arr connections also carry a fingerprint header.
- A `Test` event returns 2xx and queues nothing.
- **Back-pressure** *(decided 2026-11-10)*: a trigger request is refused with 503 and `Retry-After` when more than 10 000 received events are still waiting to be turned into queue entries, when that trigger alone holds more than half of them, or when the database can't be written. Nothing is acknowledged and then lost.

## Watching local folders
- **Events that count:** a file closed after writing, a file or folder moved in, moved out or deleted. A file still being written produces nothing until it is closed.
- **Ignore patterns** (for example partial downloads) are set per trigger.
- **Watch limit:** a large library can exceed the kernel's limit on watches. When that happens, the trigger keeps the watches it has, covers the rest by walking, and shows on the Health page how to raise the limit. It does not fail.
- **Walks** run on the trigger's interval and report only what changed since the last walk.
- **While an anchor is missing,** a walk does not report the files under it as deleted, and deletes already seen for that folder during the outage are discarded when the anchor returns.
- **Events that cannot be stored** (the database is unwritable, or the backlog is full): file events are kept in memory up to a limit, then dropped with a count on the Health page; the next walk finds what was missed. With walking switched off, that is said on the trigger.

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
   - **Merging up** *(decided 2026-11-10)*: when more than 10 folders waiting for one target share a parent, they are replaced by one scan of that parent. The threshold is adjustable per target and can be switched off. A merge never produces a library root.
4. **Readiness:** an entry is ready once the trigger's minimum age has passed since its last event, or once the target's maximum wait has passed since its first event.
5. **Order:** by ready time, first in first out. There are no priorities, with one exception:
   - When several triggers feed one entry, the longest minimum age among them applies.
   - **Send now** *(decided 2026-11-10)*, from a manual scan or on a waiting entry, ends that entry's wait and sends it next for its target, ahead of other waiting entries. Anchors, pacing, and a disabled or unavailable target still apply.
6. **Never lost:** an event that arrives after dispatch bumps the generation, so the entry stays queued and another scan follows.

## Delivery
- **Scans and uploads** *(decided 2026-11-10)*: for a folder under an upload destination, when a scan is sent depends on where the file is and on what the target can see (see the targets spec).
  - **File still local, target on the same system:** sent after the normal wait. The upload waits for it.
  - **Target elsewhere:** the scan waits until the file's upload has finished, then that target's propagation delay. If uploads are switched off or the folder is under no destination, it is sent after the normal wait.
  - **File already uploaded, target on the same system:** the scan waits until the file is visible again at the path the target uses, for at most the mount's propagation delay (default 5 minutes, set per destination), then is sent anyway.
  - The wait reason says which of these applies.
  - **How scan learns this without depending on `upload`:** scan defines a small question it asks before sending ("where is this folder's file: local, uploading, uploaded and when, or not something that is uploaded?") and a filter for local deletes ("was this Autoplow's own move?"). `upload`, which is built later and already depends on scan, supplies the answers. Until it does, and on installs without uploads, every file counts as local and nothing is filtered.
  - **These waits are holds, outside the minimum age and maximum wait.** The maximum wait never sends a scan to a target elsewhere before the upload is done.
  - **Which files:** an entry is for a folder; it waits for the files named by its own events.
  - **When the upload will not happen** (the file failed, was discarded or excluded, or the destination copies and keeps it local for no remote): the wait ends and the scan is sent. In any case an entry waits at most 24 hours for an upload (configurable per target).
  - **Send now** ends the wait for the mount, but not the wait for an upload to a target elsewhere, where the scan could find nothing.
  - **Autoplow's own moves are not events.** A file removed locally because Autoplow uploaded it raises no delete, from any trigger watching that folder.
- **Path must exist (optional):** per trigger and per target, for same-system targets only. Add and change entries are held until the folder exists. Deletes are exempt.
  - The check is made on the host, at the path as Autoplow sees it. Autoplow cannot look inside a media server.
  - It is retried with growing gaps for up to 1 hour (configurable). After that the entry becomes a dead letter saying the folder never appeared *(decided 2026-11-10)*.
- **Deletes** *(decided 2026-11-10)*: a deleted **folder** scans the path that was removed, not its parent, so removing a whole show or movie directly under a library root does not need a root scan. A deleted **file** scans its parent folder, like any other file event.
  - Each server's platform note records that scanning a missing path removes just that item.
  - For a server where it does not, the entry is reported on the Scans page as needing a library scan, and nothing is sent.
- **Anchors:**
  - An anchor is a file, the targets it holds, and optionally a folder that limits it to scans under that folder. *(Simplified 2026-11-10 from "globally, per target, per library or per path".)*
  - All anchors that apply must be present. If any is missing the entry is held, and deletes are never sent while anchors are missing.
- **Library resolution:**
  - Library lists are cached per target. The cache is refreshed periodically and whenever a lookup misses.
  - A folder that matches no library is reported as *unmatched*, not silently dropped: it is not queued, it is counted per trigger, and the Scans page lists them with their trigger and path, 100 at a time, so a missing path mapping can be found. They are kept for 7 days and each has **Retry**, which resolves it again.
- **Library root scans:** rejected by default, with a per-target setting to allow them.
- **Batching:** used where the target supports it (Tofa scoped scan, Emby/Jellyfin), up to a maximum batch size. Plex gets one request per folder.
- **Errors:**
  - Target-level errors trigger exponential backoff for that target only, honouring `Retry-After`.
  - Per-path errors are retried with backoff.
  - The UI shows why each entry is waiting.
- **Dead letters** *(added 2026-10-30)*: an entry that keeps failing for a path-level reason (for example the server refuses the path) is dead-lettered after 5 attempts (configurable) and raises `item.deadlettered`. Target-level outages never dead-letter; those entries wait for the target.
  - The UI offers **Retry** and **Discard** for each one, and **Discard all** per target. **Edit** opens the path mapping the entry went through, so it can be corrected before a retry.
  - Dead letters are pruned automatically after 30 days (configurable).
- **History:** delivered scans are kept for 7 days (configurable) and can be shown on the Scans page.

- **Post-delivery verification (optional, per target, off by default):** after delivery, query the target for the expected path (present for adds and changes, absent for deletes) within the target's known processing delay plus a margin. If the check fails, warn (for example "library folder not registered on the server, consider re-adding the library") instead of assuming success. This is motivated by the Jellyfin empty-folder and Plex disrupted-initial-scan findings.
- **Server delays shown in the UI:** Jellyfin and Emby apply their own monitor delay before acting on `Media/Updated` (measured 60 s and 90 s).
- **Which wait wins:** an entry held for a missing anchor, or for a target that is disabled or backing off, shows that reason, and the "path must exist" hour does not run meanwhile.
- **Deletes and adds in one entry:** it is sent as a delete if every event in it was a delete, otherwise as an add. The existence check applies only to adds; Plex empty trash runs if any event in it was a delete.
- **When a path mapping or a library changes,** waiting entries are resolved again.

## Targets
| Target | Scan call | Extras |
|---|---|---|
| Plex | `GET /library/sections/{id}/refresh?path=` | **Empty trash** after delete scans: optional, off by default, guarded by anchors. The UI explains it is only useful when Plex's automatic empty-trash setting is off. The trash is emptied only after the scan is **observed to finish** (`refreshing`/`scannedAt`), and never if a scan in that library failed. The wait happens in the Plex worker only. |
| Emby / Jellyfin | `POST /Library/Media/Updated` (batched) | |
| Tofa | `POST /api/v1/libraries/{id}/scan/scoped {paths}` (batched) | Completion status is available from `/scan/status`. |
| Tdarr | `POST /api/v2/scan-files` | |
| Another autoplow | Its generic webhook, with a trigger token. Never its API, so no admin key of another install is stored. | |

## UI and API extras
- **Manual-add preview:** shows the rewrite per target, the library it resolves to, and, for a same-system target, whether the path exists (a target elsewhere says "not checked").
- **Bazarr compatibility:** `GET /stats` and `GET /api/config-template` (Bazarr's config generator).

## Open items
- ~~The webhook mechanics for Bazarr and Whisparr~~ (resolved, see ../research/arr-connect-api.md).
- How to discover Tofa's library root paths.
- ~~Evaluate autopulse's scan approach~~: done. Approach A stays the only mode (see [ADR-0009](../decisions/0009-folder-level-scans-only.md)).

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `anchor.missing`, `anchor.restored`: an anchor file disappears or returns.
- `item.deadlettered`: an entry becomes a dead letter.
- `scan.failed`: a delivered scan fails its post-delivery verification.
- `scan.delivered`: scans were delivered; aggregated.

## Acceptance criteria
1. An Arr `Download` for a file queues exactly one scan per target whose library contains the file's parent folder by path components; `Test` events queue nothing and return 2xx.
2. Two events for the same folder within the minimum age produce one delivery; an event arriving after a delivery was dispatched always produces another delivery (generation acknowledgement).
3. A queued parent folder absorbs later child folders for the same target; a child queued first is replaced when its parent arrives.
4. With a target offline, deliveries to other targets continue unaffected; the offline target's entries are retained across restart and delivered after it recovers (exponential backoff honouring `Retry-After`).
5. Every queued entry exposes a wait reason (debounce, max-wait pending, anchor missing, path missing, waiting for the upload, waiting for the mount, target backoff, target disabled, ready) via the API.
6. Delete events skip the existence check; with the optional 'path must exist' check enabled for a same-system target, add/change entries are held until the path exists (see AC16 for one that never does).
7. With any applicable anchor missing, no delivery (and never a delete) is sent for the affected scope.
8. `/mnt/Movies` never matches a library at `/mnt/Movies4K`; a folder contained by locations in two libraries is delivered to both.
9. Jellyfin/Emby deliveries for one target are batched into one `Media/Updated` call per delivery cycle (bounded batch size); Plex receives one request per folder.
10. Burst: 1 000 events/minute for 10 minutes are accepted without loss (no 5xx other than back-pressure 503 with `Retry-After`), and all resulting scans are delivered once targets accept them.
11. Optional post-delivery verification flags a target that accepted a scan but never indexed the expected path within its delay + margin.
12. Legacy autoscan `/triggers/{sonarr,radarr,lidarr,manual}`, A-Train and Bazarr (`/triggers/bazarr`, `/stats`, `/api/config-template`) requests recorded from those tools are accepted and produce the same scans.
13. An entry failing for a path-level reason is dead-lettered after 5 attempts and can be retried or discarded (one at a time or all for a target); dead letters older than the pruning period are removed automatically. A target outage never dead-letters entries.
14. Deleting a folder directly under a library root produces a scan of the removed path and never a root scan; for a server that cannot remove an item that way, the entry is reported as needing a library scan and nothing is sent.
15. More than the threshold of waiting folders under one parent, for one target, are sent as one scan of the parent; a merge never yields a library root; with merging off each folder is sent.
16. With "path must exist" on for a same-system target, an entry whose folder never appears is dead-lettered after the configured time with that reason; one whose folder appears is sent.
17. "Send now" on a waiting entry sends it before entries that were ready earlier, and still respects anchors, pacing and a disabled target.
18. Above 10 000 unprocessed received events, a trigger request gets 503 with `Retry-After`; below it, requests are accepted again without a restart.
19. A folder that matches no library is not queued and appears in the unmatched list with its trigger.
20. When the watch limit is reached, the local trigger keeps working by walking and the Health page says so; a file still being written produces no event until it is closed.
21. A generic webhook with `type: delete` queues a delete that skips the existence check.
22. For a folder under an upload destination: a same-system target is scanned after the normal wait while the file is local; a target elsewhere is scanned only after the upload has finished and its propagation delay has passed; a same-system target whose file was already uploaded is scanned when the file is visible again or after the mount's delay, whichever is first. Each case shows its own wait reason.
23. A file removed locally by Autoplow's own move produces no delete event from any trigger.
24. While an anchor is missing, a walk reports no deletes under it, and the "path must exist" hour does not run for entries held by an anchor or by their target.
25. An entry holding a delete and an add is sent as an add, with empty trash afterwards on Plex when that is enabled.
26. A trigger body above 1 MB or naming more than 1000 paths is refused, and one trigger filling its own backlog share does not cause 503 for another.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Changing per-trigger auth semantics; Adding a new trigger or target type.
- **Never:** Drop an accepted event (one a trigger request was answered for; file events seen while nothing can be stored are covered under "Watching local folders"); Scan a library root unless the target explicitly allows it; Use longest-match or raw string-prefix path logic.

## Open questions
- Default minimum age and maximum wait values (**decided 2026-10-27:** min 30 s, max 10 min; per trigger/target configurable).
- **Decided 2026-10-27:** a trigger→target pair's rule set replaces the target's set for that pair.
