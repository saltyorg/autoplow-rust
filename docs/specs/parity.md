# Spec: Library parity (v1)

**Module:** `parity` · **Depends on:** core, targets, arr, scan, notifications · **Decisions:** ADR-0014 · **Status:** approved 2026-10-27

## Objective
Show and (optionally) fix where media servers disagree with the Arrs: wrong matches, items missing on either side, file differences, merged items — review-first, never modifying what it does not understand.

## Non-goals
- Editing Arr data
- Auto-fixing by default
- Supporting agents/providers it cannot interpret
- Music: Lidarr libraries are not compared in v1

This was formerly matcharr, the standalone app. It compares what the Arrs manage with what each media server actually has: wrong matches, files missing on either side, unmanaged items and file differences. It can fix some of them.

## Scope
- **Arr sources:** Sonarr and Whisparr v2 (series), and Radarr and Whisparr v3 (movies).
- **Servers:** Plex, Emby, Jellyfin and Tofa.
- **Tofa details** are pending verification against a running Tofa server. TVDB IDs are expected to be available.

## Triggers (each can be switched on or off)
- **Scheduled sweep** (cron; default daily at 02:00).
- **On demand** from the UI and API.
- **After import:**
  - Checks only the imported item.
  - Runs a configurable delay (default 10 minutes) after our scan for it was delivered.
- A full check is a long job. Two never run at once.

## What is compared
- Every Arr is compared with every server whose libraries share its folders. A pair can be excluded.
- **Finding types** can be switched off per pair *(decided 2026-11-10)*: wrong match, missing on the server, missing in the Arr, file difference, merged item. All are on by default.
- **Anchors** *(decided 2026-11-10)*: a server is not checked while one of its anchors is missing. A dropped mount would otherwise make everything look missing.
- **Arr entries without a file** are not compared; there is nothing to find on the server yet.
- **File difference** means the file the Arr has for an episode or film, after path mapping, is not among the files the server has for it. Extras, trailers and additional versions on the server are ignored. Specials and multi-episode files are compared by their episode numbers.
- **Scale:** server listings go through the target's pacing. Items are joined as they are read, not held in memory all at once.

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
- **Review by default.** Each finding can be fixed, skipped or ignored.
- **Automatic fixing** *(decided 2026-11-10)* is opt-in per server and **per finding type**. The setting warns that automatic rematching changes what viewers see if a path mapping is wrong.
- **Safety limit** *(decided 2026-11-10)*: when a run finds more new findings than a limit (default 50, or 5 % of the library, both configurable), automatic fixing is suspended for that run. The findings still appear for review, and the run's completion notice says fixing was suspended and why.
- **What each fix is:**

  | Finding | Fix |
  |---|---|
  | Wrong match | Rematch the item (calls below) |
  | Missing on the server | Queue a scan of the folder |
  | File difference | Queue a scan of the folder |
  | Merged item | Split, then verify, when the Plex target is set to auto-split (below) |
  | Missing in the Arr | None; review only |

- **Rematch calls:**

  | Server | Call |
  |---|---|
  | Plex | `PUT /library/metadata/{id}/match?guid=<agent-appropriate>&name=` |
  | Emby / Jellyfin | Update only the provider IDs, preserving all other fields (autoplow's version wiped genres and tags), then refresh |
  | Tofa | `POST /api/v1/media/{id}/match` |

- **Safety:**
  - Every fix is **verified by reading the item back**.
  - Fixes are rate-limited (one per second per server by default) and back off on 5xx responses.
  - Every action is written to an audit log, kept for 90 days (configurable).
- **The match language** is configurable. It is no longer hardcoded to `en`.

## A finding over time
- **Identity:** a finding is the same one across runs when its pair, item folder, type and, for files, episode match.
- **Skip** hides it until a later run finds it again. **Ignore** hides it until the admin un-ignores it.
- **Resolved:** a finding that was fixed, or that a later run no longer finds, is marked resolved and kept for 7 days (configurable).
- **Notifications:** `parity.mismatch.found` is raised only for findings that are new since the previous run, and many at once are summarised (see the notifications spec).

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
7. With automatic fixing on for scans only, a run queues scans for missing and stale files and leaves wrong matches for review; with rematching also ticked, those are fixed too.
8. A run that exceeds the safety limit applies no automatic fix, lists its findings for review, and its completion notice says fixing was suspended.
9. A server with a missing anchor is not checked, and no finding about it is created or resolved.
10. A finding type switched off for a pair, and an excluded pair, produce no findings.
11. A skipped finding reappears when a later run finds it again; an ignored one does not; a resolved one disappears after its retention time.
12. Only findings new since the previous run raise `parity.mismatch.found`.
13. Extras and additional versions on the server, and Arr entries without a file, produce no finding.
14. A second full check started while one runs is refused with the running job.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Enabling auto-split of merged items by default.
- **Never:** Modify items it cannot classify; Hardcode a metadata language.

## Open questions
- Tofa matching (TVDB availability) pending verification against a running Tofa server.
