# Knowledge base: prior art for the new tool

These are the reports on the projects we are taking ideas from. Each project has its own file:

| Project | Language | What it does | Report |
|---|---|---|---|
| cloudplow | Python | Moves local media to cloud remotes with rclone, rotates service accounts (SAs), throttles uploads during Plex streams, cleans unionfs whiteouts, syncs remotes | [cloudplow.md](cloudplow.md) |
| Rust vs Go | n/a | Feasibility pass with measured rclone FFI spike and ecosystem survey | [rust-vs-go.md](rust-vs-go.md) |
| Upload readiness | n/a | Torrent hardlinks, import copy fallback, usenet mtimes, Plex Date Added | [upload-readiness.md](upload-readiness.md) |
| autopulse | Rust | An alternative to autoscan; Bazarr's external webhook was built for it | [autopulse.md](autopulse.md) |
| autoscan (saltydk fork) | Go | Turns webhooks, inotify and Drive changes into durable per-target scan queues, then sends partial scans to Plex, Emby and Jellyfin | [autoscan.md](autoscan.md) |
| matcharr | Python | Fixes Plex items whose matched ID disagrees with Sonarr or Radarr, pairing items by folder path | [matcharr.md](matcharr.md) |
| Plex-Auto-Languages | Python | Applies a user's audio and subtitle choice to the other episodes of a show, per user | [plex-auto-languages.md](plex-auto-languages.md) |
| autoplow | Go | Our earlier attempt to merge all four behind a web UI | [autoplow.md](autoplow.md) |
| Tofa | Rust (server) | New media server; we only use its API | [tofa.md](tofa.md) |
| Sonarr/Radarr/Lidarr | C# | Connect (webhook) management API and webhook payloads | [arr-connect-api.md](arr-connect-api.md) |

## Capability map
The same jobs come up in several projects. Ratings are relative within each row.

| Capability | cloudplow | autoscan | matcharr | PAL | autoplow |
|---|---|---|---|---|---|
| Arr webhooks to scan | – | ✔ (solid) | – | – | ✔ |
| inotify / polling triggers | – | ✔ inotify | – | – | ✔ (doesn't restart after removal) |
| Google Drive changes trigger | – | ✔ bernard (service account) | – | – | ✔ OAuth snapshot + Changes API |
| Durable scan queue | – | ✔ **per target, with generations** | – | – | ✔ (drops work on overflow) |
| Debounce / minimum age / anchors | – | ✔ | – | – | ✔ (anchors not loaded at boot) |
| Plex, Emby and Jellyfin scan APIs | – | ✔ | – | – | ✔ (+ Tdarr) |
| rclone upload / move | ✔ CLI + output scraping | – | – | – | ✔ via the RC API |
| SA rotation and quota bans | ✔ | – | – | – | ✘ |
| Plex-stream-aware throttling | ✔ tiered | – | – | – | ✔ linear |
| Waiting for Plex to finish analysing before upload | – | – | – | – | ✔ (fragile heuristics) |
| Pausing download clients | ✔ NZBGet/SAB | – | – | – | ✘ |
| Remote-to-remote mover / sync | ✔ | – | – | – | ✘ |
| Arr ↔ Plex ID mismatch fixing | – | – | ✔ (with limitations) | – | ✔ (+ file mismatches, best module) |
| Audio and subtitle propagation | – | – | – | ✔ | ✔ port |
| Notifications | ✔ Apprise / Pushover / Slack | – | – | ✔ Apprise | ✘ (configured but unwired) |
| Configuration | JSON file | YAML file | JSON file | YAML + env | DB + web UI only |
| UI | – | – | – | – | ✔ htmx |

## Patterns worth carrying forward
- **Per-target durable queues with generation acknowledgement** (autoscan). A scan's row is deleted only if no new event arrived while that scan was in flight, so delivery is at least once and nothing is lost.
- **Error classes that drive retry policy**, including `Retry-After` (autoscan). A fix to add: one fatal error must not kill a whole worker.
- **Anchor files** to protect against a dropped mount, and **refusing to scan a library root** (autoscan).
- **Driving rclone through `rcd` and RC jobs** instead of parsing CLI output (autoplow).
- **Quota and service-account semantics:** exit code 7, a pool of SAs with ban times that persist, suspending until the earliest unban, and injecting the SA through `RCLONE_CONFIG_<REMOTE>_SERVICE_ACCOUNT_FILE` after walking crypt, union and chunker remotes (cloudplow).
- **Tiered bandwidth limits by stream count**, re-applied when a new rclone job resets them (cloudplow).
- **Google Drive snapshot plus the Changes API**, handing paths off before the page token advances (autoscan bernard and autoplow).
- **matcharr core:** pair items by path, check whether the Arr ID is among Plex's GUIDs, then `PUT /library/metadata/{id}/match?guid=tmdb://X`. Add autoplow's phased fetch and file-mismatch detection.
- **PAL track matcher:** filter by language, then visually-impaired flag, then descriptive tracks; then score and break ties by position. Includes forced and hearing-impaired subtitle rules and per-user writes using shared-server tokens.

## Recurring pitfalls to design against
1. **Prefix matching without a path boundary.** `/mnt/Movies` matches `/mnt/Movies4K`. This shows up in autoscan rewrites, matcharr `map_path` and in several places in autoplow.
2. **Caches that are never refreshed.** autoscan never reloads library lists; autoplow's matcharr library cache expires after 24 h and is only rebuilt at boot.
3. **Dropping work under back-pressure.** autoplow's 100-slot channel discards requests when full; PAL's alert queue drops alerts.
4. **Lifecycles that need a process restart after a config change** (autoplow).
5. **Blocking work on websocket reader threads** (autoplow PAL, and the PAL design itself).
6. **Secrets in logs or on command lines:** Plex tokens, `rc-pass`, `--rc-no-auth`, `verify=False`.
7. **Features finished only in the UI**, and no tests on the concurrent code (autoplow).
8. **A sliding debounce with no maximum wait** (autoscan).

## Open questions for planning
- **Scope.** Which of the five capability groups go into v1: scan, upload, throttle, matcharr, PAL?
- **Configuration.** A config file (GitOps / Saltbox Ansible friendly), a DB edited through a UI, or a file with a read-only UI?
- **Plex "analysed before upload" gating.** Keep it? If so, which signal is reliable enough?
- **Sharing with existing tools.** Must it accept existing autoscan- and A-Train-compatible webhook URLs and payloads?
- **Service-account rotation.** Is it still needed, given that Google Drive quotas have changed?
- **Media servers.** Which ones are first class: Plex only, or Emby and Jellyfin too?
- **Deployment.** Is Saltbox (Linux, Docker) the only target?
