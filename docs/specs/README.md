# Specifications

**Status:** capability map approved 2026-10-27. Module IDs are permanent; never rename them.

- **Project-level spec:** [project.md](project.md) (objective, users, success criteria, commands, structure, style, testing, boundaries).
- **UI rules:** [ui.md](ui.md) (look, layout, pages versus dialogs, controls; binding for every module's pages).
- **Module specs:** one per module, named by module ID. Each module's UI pages ship inside the module, on the `core` UI shell.

## Capability map
| Module ID | Spec | Responsibility | Depends on |
|---|---|---|---|
| `core` | [core.md](core.md), [core-bootstrap-api.md](core-bootstrap-api.md) | Store and migrations, supervisor, config, bootstrap, REST API, auth, path handling, observability, UI shell | none |
| `notifications` | [notifications.md](notifications.md) | Durable outbox, Discord/Apprise/webhook delivery, subscriptions | `core` |
| `targets` | [targets.md](targets.md) | Clients for Plex, Jellyfin, Emby, Tofa, Tdarr and Autoplow: libraries, scan calls, sessions | `core` |
| `arr` | [arr.md](arr.md) | Sonarr/Radarr/Lidarr/Whisparr client, webhook receiver and parsers, managed connections, migration helper | `core`, `notifications` |
| `scan` | [scan.md](scan.md) | Triggers, per-target durable queues, delivery, verification | `core`, `targets`, `arr`, `notifications` |
| `gdrive` | [gdrive.md](gdrive.md) | Google OAuth accounts, snapshot plus Changes API, Drive trigger, crypt name decoding, change log | `core`, `scan`, `rclone` |
| `rclone` | [rclone.md](rclone.md) | Supervised `rcd`, RC client, job tracking | `core` |
| `downloaders` | [downloaders.md](downloaders.md) | SABnzbd, NZBGet and qBittorrent clients; single owner of pause state and speed limits | `core`, `notifications` |
| `upload` | [upload.md](upload.md) | Destinations, per-file queue, readiness, failover, schedules, when to pause download clients | `core`, `rclone`, `scan`, `notifications`, `downloaders` |
| `throttle` | [throttle.md](throttle.md) | Session registry; limits for rclone and download clients from stream activity | `targets`, `rclone`, `downloaders` |
| `parity` | [parity.md](parity.md) | Library parity engine, fixes, review | `core`, `targets`, `arr`, `notifications` |
| `track-preferences` | [track-preferences.md](track-preferences.md) | Plex track preferences | `core`, `targets` |

**Build order:** `core` → `notifications`, `targets` → `arr` → `scan` → `rclone` → `gdrive` → `downloaders` → `upload` → `throttle` → `parity` → `track-preferences`.

**Rules:**
- Dependencies point one way.
- The contract between two modules belongs in the provider module's spec.
