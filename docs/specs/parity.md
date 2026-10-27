# Spec: Library parity (v1)

**Module:** `parity` · **Depends on:** core, targets, arr, notifications · **Decisions:** ADR-0014 · **Status:** approved 2026-10-27

## Objective
Show and (optionally) fix where media servers disagree with the Arrs: wrong matches, items missing on either side, file differences, merged items — review-first, never modifying what it does not understand.

## Non-goals
- Editing Arr data
- Auto-fixing by default
- Supporting agents/providers it cannot interpret

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

## Acceptance criteria
1. For each configured Arr×server pair, a run lists ID mismatches, gaps (both directions), per-episode/movie file mismatches and merged items; items on unknown agents are reported, never modified.
2. Joins use path components through the scoped rewrite rules; a library of 500 000 items completes a run without exceeding the resource budget.
3. Fixes are applied only when the user approves (or auto-fix is enabled for that server), are rate-limited, verified by read-back, and audited.
4. Emby/Jellyfin fixes change only provider IDs; all other item fields remain unchanged (verified by read-back).
5. Ignored findings stay ignored across runs.
6. Schedule, on-demand and after-import triggers can each be disabled.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Enabling auto-split of merged items by default.
- **Never:** Modify items it cannot classify; Hardcode a metadata language.

## Open questions
- Tofa matching (TVDB availability) pending verification against a running Tofa server.
