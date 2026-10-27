# Spec: Library parity (v1)

This was formerly matcharr, the standalone app. It compares what the Arrs manage with what each media server actually has: wrong matches, files missing on either side, unmanaged items and file differences. It can fix some of them.

## Scope
- **Arr sources:** Sonarr and Whisparr v2 (series), and Radarr and Whisparr v3 (movies).
- **Servers:** Plex, Emby, Jellyfin and Tofa.
- **Tofa details** are pending verification against a running Tofa server. TVDB IDs are expected to be available.

## Triggers (each can be switched on or off)
- **Scheduled sweep** (cron).
- **On demand** from the UI and API.
- **After import:**
  - Checks only the imported item.
  - Runs a configurable delay after our scan for it was delivered.

## Algorithm
Based on autoplow's phased approach, with fixes.
1. Fetch Arr root folders and the server's libraries. Libraries are always current (no 24-hour cache that goes stale).
2. Choose libraries by overlap with the Arr roots, using the scoped rewrite rules (no longest-match).
3. Fetch Arr items and server items with their provider IDs. Join them through a **path-keyed hashmap** (exact normalised folder match), not nested loops.
4. **Compare IDs:**
   - Sonarr uses TVDB. Radarr uses TMDB.
   - IMDb is a fallback, with documented cross-ID fallbacks.
   - Items on agents or providers we don't understand are **reported, never modified**.
5. **Record findings:**
   - mismatches
   - gaps (missing on the server, and missing in the Arr)
   - file mismatches per SxxEyy or per movie
   - merged items
   - each finding can be added to the ignore list

## Fixing
- **Review by default.** Each finding can be fixed or skipped. Auto-fix is opt-in per server.
- **Fix calls:**

  | Server | Call |
  |---|---|
  | Plex | `PUT /library/metadata/{id}/match?guid=<agent-appropriate>&name=` |
  | Emby / Jellyfin | Update only the provider IDs, preserving all other fields (autoplow's version wiped genres and tags), then refresh |
  | Tofa | `POST /api/v1/media/{id}/match` |

- **Safety:**
  - Every fix is **verified by reading the item back**.
  - Fixes are rate-limited and back off on 5xx responses.
  - Every action is written to an audit log.
- **The match language** is configurable. It is no longer hardcoded to `en`.

## Merged items (Plex)
- These are items whose locations span different item folders.
- **Options:**
  - off
  - **notify** the user to handle it manually, via the notification system
  - **auto-split** (`PUT /library/metadata/{id}/split`) followed by verification
