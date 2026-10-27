# Specifications

**Status:** capability map approved 2026-10-27. Module IDs are permanent; never rename them.

- **Project-level spec:** [project.md](project.md) (objective, users, success criteria, commands, structure, style, testing, boundaries).
- **Module specs:** one per module, named by module ID. Each module's UI pages ship inside the module, on the `core` UI shell.

## Capability map
| Module ID | Spec | Responsibility | Depends on |
|---|---|---|---|
| `core` | [core.md](core.md), [core-bootstrap-api.md](core-bootstrap-api.md) | Store and migrations, supervisor, config, bootstrap, REST API, auth, path handling, observability, UI shell | none |
| `notifications` | [notifications.md](notifications.md) | Durable outbox, Discord/Apprise/webhook delivery, subscriptions | `core` |
| `targets` | [targets.md](targets.md) | Clients for Plex, Jellyfin, Emby, Tofa, Tdarr and Autoplow: libraries, scan calls, sessions | `core` |
| `arr` | [arr.md](arr.md) | Sonarr/Radarr/Lidarr/Whisparr client, webhook receiver and parsers, managed connections, migration helper | `core`, `notifications` |
| `scan` | [scan.md](scan.md) | Triggers, per-target durable queues, delivery, verification | `core`, `targets`, `arr`, `notifications` |
| `gdrive` | [gdrive.md](gdrive.md) | Google OAuth accounts, snapshot plus Changes API, Drive trigger | `core`, `scan` |
| `rclone` | [rclone.md](rclone.md) | Supervised `rcd`, RC client, job tracking | `core` |
| `upload` | [upload.md](upload.md) | Destinations, per-file queue, readiness, failover, schedules, downloaders | `core`, `rclone`, `scan`, `notifications` |
| `throttle` | [throttle.md](throttle.md) | Session registry and bandwidth policy | `targets`, `rclone` |
| `parity` | [parity.md](parity.md) | Library parity engine, fixes, review | `core`, `targets`, `arr`, `notifications` |
| `track-preferences` | [track-preferences.md](track-preferences.md) | Plex track preferences | `core`, `targets` |

**Build order:** `core` → `notifications`, `targets` → `arr` → `scan` → `gdrive` → `rclone` → `upload` → `throttle` → `parity` → `track-preferences`.

**Rules:**
- Dependencies point one way.
- The contract between two modules belongs in the provider module's spec.
