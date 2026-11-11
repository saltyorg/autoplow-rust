# Plex Media Server

Verified 2026-10-27 with live tests against a current Plex Media Server, using tiny test libraries with Plex's own automatic scanning turned off. Timings were polled once per second.

## Partial scans (`GET /library/sections/{id}/refresh?path=<folder>`)
- A new episode, a 10-episode season pack, an upgrade (new file name, old file removed), a file rename, a show-folder rename (both old and new folders scanned), and a new movie were all **visible at the first poll (about 1 s)**.
- A burst of 20 files in 10 folders, sent as 10 sequential folder requests, became visible in about 5 s.
- **A deleted folder that Plex already knows** (for example a removed movie folder, scanned at its old path) **is removed promptly.**
- **A path Plex doesn't know yet is ignored.** If the partial scan arrives before the file exists (mount or Drive lag), nothing is indexed and nothing retries later.
  - **Implication:** Autoplow's optional "path must exist before delivery" check (hold and retry) matters for Plex targets.
- Spaces in `path` may be encoded as `%20` or `+`; both work.
- `Job was already killed, not killing again.` in the server log is harmless debug output.

## Sections
- **Creating a section** (`POST /library/sections?...&location=`) immediately runs a full scan of that section.
- **Disrupted initial scan (observed once, cause unconfirmed):** a section whose initial scan was disrupted ignored every partial scan ("Refreshing 0 IDs") until one full refresh of that section. After that, partial scans worked normally.
  - **Implication:** post-delivery verification should detect "scan accepted but nothing indexed", and suggest a full refresh of that section.
- **Overlapping locations:** a folder inside two sections (one section's location nested inside another's) is indexed in **both** when each section receives the partial scan.

## Trash
- With Plex's automatic empty-trash setting enabled, deleted items disappeared after the partial scan without an explicit `emptyTrash`.
- Autoplow's empty-trash option only matters when that setting is off.

## API
- List endpoints log `Missing X-Plex-Container-Size header. This will fail with status code 400 in the future.` Always send `X-Plex-Container-Start` and `X-Plex-Container-Size`.

## Sessions
Baseline of 2026-11-11 from Plex's published API description (developer.plex.tv, version 1.2.3), the earlier Autoplow implementation and two widely used clients (python-plexapi 4.17.1, Tautulli 2.15.2). **Not run against a live server.**

- **List:** `GET /status/sessions` with the owner's token returns every current playback. *Documented, and used by the earlier implementation.*
- **State:** `Player.state` is `playing`, `paused`, `buffering` or `stopped`. *Documented.*
- **Bitrate:** `Session.bandwidth` is in **kbps**. *Documented.* It is what the server reserved for the session, not a measurement, and the `Session` element can be missing (per python-plexapi). The earlier implementation fell back to `Media[0].bitrate`, whose unit is not documented.
- **Local or remote:** `Session.location` is `lan` or `wan`; `Player.local` is a boolean. *Documented.*
- **User and title:** `User.id`, `User.title`, and the item's `title`, `grandparentTitle` and `type`. *Documented.*
- **Session key:** every client uses the top-level `sessionKey`, which is also what websocket events carry. The API description documents `Session.id` and does not mention `sessionKey`.
- **Websocket:** every client connects to `/:/websockets/notifications`. The API description gives `/:/websocket/notifications` and an event stream at `/:/eventsource/notifications`. The token may be a header or a query argument.
- **What a `playing` event holds:** `sessionKey`, `clientIdentifier`, `key`, `viewOffset` and `state`. No user, bitrate or location, so the session list is read after each event. The payload is not documented.
- **Keep-alive:** the earlier implementation sent no ping frames and Tautulli does; the documentation says nothing.
- **To check live:** which websocket path connects; whether an idle connection stays open; the events on start, pause, resume and stop; `Session.bandwidth` against the file's real bitrate, and when `Session` is missing; `Session.location` for a relayed client; that downloads and optimise jobs do not appear in the list.

## User tokens and track selection
Baseline of 2026-11-11 from the earlier Autoplow implementation, Plex-Auto-Languages, python-plexapi 4.18.3, Plex's published API description and statements by Plex staff on its forum. **Not run against a live server or account.**

- **Owner:** the server's own token.
- **Every other user:** `GET https://plex.tv/api/servers/{machine id}/shared_servers` with the owner's token returns, per user, a `userID` and an `accessToken` valid on that one server. Both production tools use only this route, for managed users, home users with an account and friends alike. It takes no PIN.
- **This route is not documented and Plex intends to remove it.** Tokens stopped being returned on 2026-03-25 and were restored on 2026-03-27; Plex staff wrote that removal is still planned, with notice, and that no replacement is decided.
- **The other known route** (switching to a home user, then asking plex.tv for that user's resources) yields a full account token, works only for home users, and reports conflict on whether a PIN-protected user needs their PIN. Neither production tool uses it.
- **User ids:** both tools rely on a session's user id being the plex.tv `userID`, with the owner as 1. Not documented.
- **Writing a selection:** `PUT /library/parts/{part id}` with `audioStreamID` or `subtitleStreamID` (0 for no subtitles) and the user's token. The API description says it sets the streams "selected by this user". `allParts=1` makes the server choose similar streams in the other parts; Plex-Auto-Languages sends it and the earlier Autoplow did not.
- **Reading a selection:** `GET /library/metadata/{id}` with the same user's token; `selected` on a stream marks that user's choice. Used by both tools; the per-user meaning is not stated in the documentation.
- **Invalid token:** 401. The earlier Autoplow treated 403 the same.
- **Who changed a track:** during playback, a `playing` event gives the client, and the session list gives the user. Without playing, only Plex-Auto-Languages has a method: an `activity` event of type `library.refresh.items` that has ended, which names the user and the item.
- **To check live (task 11.0):** `shared_servers` returns a token for each user kind, PIN-protected ones included; each token works on the server; a write as one user changes only that user's selection; behaviour with and without `allParts` on a two-part file; the status for a revoked token; which Plex apps send the activity event.
