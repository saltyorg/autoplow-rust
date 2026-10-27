# Spec: targets

**Module:** `targets` · **Depends on:** core · **Decisions:** ADR-0009, ADR-0010 · **Status:** approved 2026-10-27

## Objective
Narrow, typed, well-tested clients for every media-server target. Each client lists libraries and their locations, delivers scans, reports sessions, and exposes the capabilities that other modules use: `Scanner`, `SessionSource`, `Matcher` and `TrackSelector`.

## Non-goals
- General-purpose API SDKs. The clients cover only what specs require.
- Kodi, Navidrome and Audiobookshelf in v1.

## Scope
| Target | Scan | Libraries | Sessions | Parity | Tracks |
|---|---|---|---|---|---|
| Plex | `refresh?path=` per folder; verified empty trash | `/library/sections` with paging headers | websocket notifications | GUID match and fix | per-user part stream selection |
| Jellyfin | batched `Media/Updated` (`Modified`) | `/Library/VirtualFolders` | websocket `SessionsStart` | provider IDs | none |
| Emby | batched `Media/Updated` (`Created`) | `/emby/Library/SelectableMediaFolders` | websocket | provider IDs | none |
| Tofa | `POST /libraries/{id}/scan/scoped` (batched) | provisional (no library-roots endpoint yet) | websocket (required once documented), polling until then | `POST /media/{id}/match` | none |
| Tdarr | `scan-files` | n/a | n/a | n/a | n/a |
| Autoplow | generic trigger of another instance | n/a | n/a | n/a | n/a |

Behaviour each client must respect is recorded in `docs/platform-notes/`.

## Acceptance criteria
1. Each client passes contract tests against recorded fixtures, covering every request it makes and every response shape it parses, including error and `Retry-After` cases.
2. **Shared HTTP client:**
   - Bounded timeouts.
   - A response size cap (4 MB default).
   - `Retry-After` honoured.
   - Errors classified as retry, target backoff or per-path dead-letter.
3. Library lists refresh periodically and on a lookup miss. A library added on the server is used without restarting Autoplow.
4. Tokens never appear in logs, including request URLs.
5. Live tests (feature `live`, env-configured) reproduce the platform-notes timings for Plex, Jellyfin and Emby.
6. Overlapping library locations on Jellyfin or Emby produce a target warning that names the owning library.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; record new third-party behaviour in `docs/platform-notes/`.
- **Ask first:** adding a target type.
- **Never:** call server-wide refresh endpoints; create libraries with `refreshLibrary=true` (tests).

## Open questions
- Tofa library-roots discovery and websocket API (pending verification against a running Tofa server).
