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

## Connecting
*(decided 2026-11-10)*
- **Plex:** "Sign in with Plex" opens Plex's own approval page and stores the token it returns. That token also lets track preferences list the server's shared users. Pasting a token stays possible.
- **Jellyfin, Emby, Tofa, Tdarr:** an API key.
- **Another Autoplow:** a webhook trigger's token on the other instance.
- **Certificates:** checked by default. A target can have the check switched off, for a server with a self-signed certificate; the dialog warns that this removes protection against impersonation.
- **Versions:** each client records, in its platform note, the oldest server version it was verified against. An older server is still used, with a warning on the target.
- **Test** connects, reads the version and lists the libraries, without saving anything.

## Talking to a server
- **Pacing:** one scan request at a time per target, with a gap between them (default 1 s). Both are adjustable per target. A batched call counts as one request.
- **Timeouts and size:** as the core outbound client sets them (10 s to connect, 30 s for an answer, 4 MB per response), adjustable per target. Library and item listings are always fetched in pages.

## Health
| State | Meaning |
|---|---|
| Healthy | The last call succeeded. |
| Backing off | A call failed at the target level (no connection, 5xx, 429). Calls wait: 30 s, doubling to at most 15 minutes, or as `Retry-After` says. |
| Unavailable | It has been backing off for the problem delay (2 minutes by default; see the notifications spec). `target.unavailable` is raised now, and `target.recovered` when it is healthy again. |
| Disabled | Switched off by the admin. |

- **Recovery:** while not healthy, a light status call is tried on the backoff schedule even with nothing queued, so recovery is noticed.
- **Disabled targets:** a target can be switched off without deleting it. It receives nothing. Per target, the admin chooses what happens to scans meant for it:
  - **Keep** (default): they stay queued, shown as "target disabled", and are sent when it is switched on again.
  - **Drop:** nothing is queued for it while it is off.

## Sessions
- A websocket that drops reconnects with backoff. After three failed attempts the client polls every 10 s until the websocket is back, so the session count has no gap.

## Changes on the server
- Library lists refresh periodically and on a lookup miss.
- A library that disappears, or whose folders change, raises a warning on the target and marks the path mappings that no longer lead anywhere.

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `target.unavailable`, `target.recovered`: see the health states above.

## Acceptance criteria
1. Each client passes contract tests against recorded fixtures, covering every request it makes and every response shape it parses, including error and `Retry-After` cases.
2. **Through the core outbound client** (core AC20), every target call has:
   - Bounded timeouts.
   - A response size cap (4 MB default).
   - `Retry-After` honoured.
   - Errors classified as retry, target backoff or per-path dead-letter.
3. Library lists refresh periodically and on a lookup miss. A library added on the server is used without restarting Autoplow.
4. Tokens never appear in logs, including request URLs.
5. Live tests (feature `live`, env-configured) reproduce the platform-notes timings for Plex, Jellyfin and Emby.
6. Overlapping library locations on Jellyfin or Emby produce a target warning that names the owning library.
7. "Sign in with Plex" stores a working token without the admin copying one; a pasted token works too.
8. With certificate checking on, a self-signed server is refused with a clear error; with it switched off for that target, the same server connects, and other targets still check.
9. Queued scans for one target are sent one at a time with the configured gap, while another target proceeds independently.
10. A target moves from backing off to unavailable after 2 minutes, and back to healthy on the first success, including one found by the status call with nothing queued.
11. A disabled target receives no call. With "keep", its scans wait and are delivered after it is enabled; with "drop", nothing is queued for it.
12. A listing larger than the response cap is read completely through paging.
13. After a websocket drops, sessions are still reported through polling within 30 s, and the websocket is used again once it reconnects.
14. Removing a library on the server produces a target warning and flags the mappings that pointed into it.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; record new third-party behaviour in `docs/platform-notes/`.
- **Ask first:** adding a target type.
- **Never:** call server-wide refresh endpoints; create libraries with `refreshLibrary=true` (tests).

## Open questions
- Tofa library-roots discovery and websocket API (pending verification against a running Tofa server).
