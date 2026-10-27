# Tofa: API notes for an integration target

**What Tofa is:**
- A self-hosted media server, currently in beta.
- The server is written in Rust and uses an embedded PostgreSQL database.
- Image: `ghcr.io/tofatv/tofa`. Default port: 33333.
- Saltbox ships it as `sandbox-tofa`.

**Sources:**
- OpenAPI 3.1 spec **`https://docs.tofa.tv/api-combined.json`**, `info.version` 0.12.1, 164 paths. This is what https://docs.tofa.tv/api.html renders.
- https://docs.tofa.tv/use-the-api.html
- The Saltbox docs page for the app.

The API is in beta, and the docs say "additive changes can land in any release". Each running server lists its own endpoints under Server > Settings > API.

## Auth and versioning
- **Server API base:** `https://<server>/api/v1/`.
- **API keys:**
  - Server admins create them under *Server > Settings > API keys*. They need server **0.9.34 or later**.
  - Send the key as `Authorization: Bearer <key>`. A key acts as the admin who created it.
  - Keys work **only on direct connections** (LAN, your own domain or your own tunnel), not through Tofa's relay. That suits Saltbox, which talks to the container over the docker network.
- **Device flow:** an OAuth device flow through `api.tofa.tv` also exists, for acting on behalf of a user account. It issues 30-day tokens, and the refresh tokens rotate. We probably only need API keys.
- **Version detection:** `GET /api/v1/system/info` returns `version`, a monotonic `api_version` and a `capabilities[]` list. The docs say to **check capabilities rather than version numbers**.
- **Health:** `GET /api/v1/health`.

## Mapping to our features

### Scan target (autoscan side): good fit
- `POST /api/v1/libraries/{id}/scan/scoped` with body `{"paths": ["/abs/path", ...]}`.
  - Runs a background scan limited to those paths. The paths **must be inside the library root**.
  - Admin only. Returns `{status}`.
  - **Takes a batch of paths natively**, unlike Plex, which takes one path per request.
- `POST /api/v1/libraries/{id}/scan` runs a full scan. `.../scan/cancel` cancels one.
- `GET /api/v1/libraries/{id}/scan/status` reports scan progress:
  - `phase`: `idle | discovering | scanning | fetching_metadata | fetching_ratings | completed | failed | cancelled`.
  - Counters: added, updated, unavailable, probes, metadata.
  - `trigger`: `manual | scheduled | watcher | metadata_refresh | webhook`.
  - This gives a **real completion signal**, something Plex lacks.
- **Library discovery:**
  - `GET /api/v1/libraries/health` returns `library_id`, `name` and `media_type` (`movie | tv | other`), plus counts of unmatched, unavailable and flagged items.
  - `GET /api/v1/libraries/{id}/folders?path=` browses folders and returns `path`.
  - ⚠ **No endpoint returns a library's root paths directly.** We probably need `folders` with no `path` parameter to get the root. **Verify this against a live server.**
- The `webhook` scan trigger and the `watcher` trigger suggest Tofa may accept webhooks or watch the filesystem itself. Neither is documented in the spec. Ask the Tofa devs.

### Session monitoring (throttle): workable
- `GET /api/v1/system/playback/sessions` (admin) returns, per session:
  - `session_id`, `user_id`, `media_file_id`
  - `play_method` (`DirectPlay | DirectStream | Transcode`)
  - `max_bitrate_kbps`, `device_name`, `last_access`
- **Update 2026-10-27:** Tofa *does* have websocket support. It is not in the 0.12.1 spec yet, and using it for sessions is a requirement once it is documented.
- Plan to **poll** sessions, and ask the Tofa devs whether a server event stream exists.
- The session record doesn't show a paused or playing state. We may need `last_access` and progress to tell an idle session from an active one.

### matcharr (ID mismatch fixing): good fit, keyed on TMDB
- **Media item fields:** `Media` has `tmdb_id`, `imdb_id`, `library_id`, `locked_fields`, `match_ignored`, and the `tvdb_order_source` / `absolute_numbering` fields. `tvdb_id` appears only in `DetailResponse`, from `GET /api/v1/media/{id}`.
- **File paths:** `MediaFile.file_path` provides them, so we can pair items with Arr items by path.
- **Lookups:**
  - `GET /api/v1/media/by-tmdb/{tmdb_id}?media_type=&season=&episode=` returns `media_id` and its `files[]`.
  - `POST /api/v1/media/by-tmdb/batch` does the same in bulk.
- **Fixing a match:**
  - `POST /api/v1/media/{id}/match` with `{"tmdb_id": N}` sets the match, **locks it** and refreshes metadata.
  - `POST /api/v1/media/{id}/rematch` clears the match and searches again. `/unmatch` removes the match.
  - `GET /api/v1/media/{id}/match/search?query=&type=&year=` searches for candidates.
- **Spotting problems:** `GET /api/v1/libraries/health` reports `unmatched_titles` and `match_pending_titles`, a cheap way to find trouble.
- **Implication (as of API 0.12.1):** Tofa matches **by TMDB** for both movies and TV. *Update 2026-10-26: the Tofa creator reports TVDB will be available. Revisit against a running Tofa server.* For Sonarr items we must compare on `tmdbId`, which Sonarr v4+ provides, or on imdb/tvdb from the item detail. Matching on TVDB alone won't work.
- **Change feed:** `GET /api/v1/media/changes?since_revision=` returns a cheap change feed with `requires_full_sync`. That's useful for incremental matcharr runs.

### Plex-Auto-Languages: probably not needed
- Tofa has **native per-profile language preferences**: `playback.preferred_audio_languages`, `playback.preferred_subtitle_languages` and `playback.always_enable_subtitles`, set through `PUT /api/v1/users/me/preferences`.
- Track choice is made **per playback session**: `POST /stream/s/{session_id}/audio` and `/subtitle-selection`, which use a session token.
- There is no persistent per-file "selected stream" like Plex's `PUT /library/parts/{id}`. PAL's model of rewriting each episode's selected stream **doesn't apply**.
- If anything, we could offer to set a user's language preferences. That is likely out of scope.

### Other useful endpoints
| Endpoint | Purpose |
|---|---|
| `GET /api/v1/users` (admin) | Users, roles and preferences |
| `GET /api/v1/system/tasks` | Running background tasks (scans, refreshes) |
| `GET /api/v1/system/watch-history` | Server-wide watch history |
| `GET /api/v1/lifecycle/*` | Built-in cleanup rules. Not for us, but worth knowing |

## Open questions for the Tofa devs, or to test on a live server
1. How do we get each library's root paths? Is there a library list endpoint that includes locations?
2. Is there a server event stream (SSE or WebSocket) for `StreamStarted`/`StreamUpdated`, so we don't have to poll sessions?
3. What is the `webhook` scan trigger? Does Tofa accept Arr webhooks directly?
4. What are the limits and semantics of scoped scans: maximum number of paths, whether paths are deduplicated or coalesced, and what happens with a path that doesn't exist (deletes)?
5. Does a paused session still appear in `system/playback/sessions`?
