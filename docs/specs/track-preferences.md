# Spec: Track preferences (v1)

**Module:** `track-preferences` · **Depends on:** core, targets · **Decisions:** ADR-0014 · **Status:** approved 2026-10-27

## Objective
Each Plex user's audio and subtitle choice for a show is remembered and applied to that show's other and future episodes, per user.

## Non-goals
- Movies
- Jellyfin/Emby/Tofa (Tofa has native per-profile preferences)
- Learning preferences from what is already selected when the feature is switched on; preferences start empty
- Sharing preferences between two Plex servers

This was formerly Plex-Auto-Languages (PAL), the standalone app.

Plex only. Tofa has native per-profile language preferences, so PAL doesn't apply to it.

## Model
- **Preferences:** stored per (user, show), or per (user, show, season) when the scope level is season *(decided 2026-11-10)*, so a different choice in one season does not replace another's. Each holds the audio stream signature and the subtitle stream signature, or "off", in the shape PAL uses for matching:
  - language
  - codec
  - channel layout
  - titles
  - flags: forced, hearing-impaired (HI), visually-impaired (VI), descriptive
- **Identity:** a preference is keyed by the show's Plex GUID (and the season number, with season scope), so it survives a show being re-added or a library being rebuilt. Preferences belong to one Plex target.
- **Recording** *(decided 2026-11-10)*:
  - The first play of a show by a user records what is selected.
  - After that, a play records a new preference only when the selection differs from what the stored preference would pick for that episode **and** the preferred track was available on it.
  - A fallback, where Plex chose another track because the episode lacks the preferred one, is never recorded.
- **UI:** users can be listed, edited and cleared.
- **History:** every change Autoplow makes (user, show, episode count, from, to) is listed and kept for 30 days (configurable).

## Where it applies
- **Per Plex target:** off until switched on for that target.
- **Libraries:** every show library is covered by default; each can be unticked.
- **Shows** *(decided 2026-11-10)* can be left out two ways:
  - excluded on the Track preferences page
  - by a Plex label (default `PAL_IGNORE`, configurable), so an existing PAL setup carries over. Labels are read with the show and cached; a label change takes effect by the next sweep.
- **Files** *(decided 2026-11-10)*: episodes whose file path matches an ignore pattern are skipped.
- An excluded show keeps its stored preferences; nothing is recorded or applied for it while excluded.

## Users
- **Coverage:** the owner plus shared and managed users. Each user can be opted out.
- **Users who lose access:** their preferences are kept for 30 days, then removed. If access returns within that time, they apply again.
- **Tokens:**
  - Taken from the plex.tv `shared_servers` data.
  - Cached, and refreshed when a request fails.
  - **Never logged,** never shown in the UI or API, sent only as a request header, and kept only in memory or encrypted.
  - How a token is obtained for a home user protected by a PIN is verified before build and recorded as a platform note. A user whose token cannot be obtained is shown as such and skipped.

## Triggers (each can be switched on or off)
1. **Play or track change**
   - Source: the websocket `playing` events. The session is resolved to its user.
   - If the streams changed, the preference is updated and the change is propagated.
   - **Without playing** *(decided 2026-11-10)*: a track changed on an episode's page is picked up from Plex's activity events and treated the same way. Plex sends these from its web and desktop apps only. This has its own switch, off by default.
2. **New or upgraded episodes**
   - Detected through timeline and activity events, plus a part-key diff, as in PAL.
   - Each stored preference for that show is applied, separately for every user.
3. **Scheduled sweep**
   - Re-applies the stored preferences to catch anything missed.
   - Default daily at 04:00. It visits only shows that have a stored preference, and only episodes added or changed since the last sweep. Sweep on the page runs one now, as a long job.
- **While the event stream is down** (see the targets spec), plays are not seen and nothing is recorded; the sweep still applies what is stored.

## Scope
- Configurable `level` (show or season) and `strategy` (all, or next = only episodes after the reference).
- Global defaults, with optional per-user overrides *(decided 2026-10-27)*.

## Matching
- Ported from PAL, including its tie-break tests:
  1. Filter by language, then VI, then descriptive.
  2. Score by codec, layout and titles, with the channel heuristic.
  3. Keep PAL's forced and HI subtitle semantics.
  4. Break ties by position.
- **No match:** when an episode has no track in the preferred language, the episode is left as Plex chose it and the stored preference is unchanged.
- Known PAL bugs to fix:
  - Use the reference's commentary state, not the target's.
  - Consider every selected stream, not only the first.
  - Handle multi-part episodes correctly.

## Execution
- Websocket readers **only enqueue** work.
- Work is serialised per (user, show) with a keyed queue, so there are no races.
- Writes use `PUT /library/parts/{id}` with the user's token, and each write is **verified by reading it back**.
- Writes go through the target's pacing in their own lane, behind scans, so a long show cannot hold up scan delivery.
- An episode that already has the right tracks selected is not written.

## Events raised
This is the notification type this module raises (the catalogue is in [notifications.md](notifications.md)).
- `tracks.applied`: preferences were applied for a user; grouped, naming the user, the show and how many episodes changed. It names no other user. *(Added to the catalogue 2026-11-10.)*

## Acceptance criteria
1. When a user changes tracks during playback, a preference is stored for (user, show), or (user, show, season) with season scope, and applied to the configured scope (show/season × all/next).
2. New or upgraded episodes get every stored preference applied, per user, using that user's token; tokens never appear in logs.
3. PAL's matching test cases pass (language, VI, descriptive, forced/HI, tie-break), plus the fixed cases (reference commentary state, multiple selected streams, multi-part episodes).
4. Concurrent events for the same (user, show) are serialised; the final selection equals the last preference.
5. Writes are verified by read-back; a user opted out is never modified.
6. The first play of a show records the selection. A later play on an episode that lacks the preferred track records nothing; a later play with a different selection on an episode that has it replaces the preference.
7. An episode with no track in the preferred language is left unchanged, and an episode already correct is not written.
8. Nothing is recorded or applied for a target that is switched off, an unticked library, a show excluded on the page, or a show carrying the ignore label; excluding a show keeps its stored preferences.
9. Each trigger can be switched off on its own. The sweep visits only shows with a stored preference and episodes changed since the last sweep.
10. A per-user scope override takes precedence over the default scope.
11. A token that fails is refreshed once and the write retried; a user whose token cannot be obtained is shown and skipped.
12. A re-added show keeps its preferences; a user without access for 30 days loses theirs.
13. Applying a preference to a long show does not delay a scan queued for the same target.
14. Every change made is listed in the history with user, show, from and to, and is removed after its retention time.
15. With season scope, a different choice in season 2 leaves season 1's preference as it was.
16. With the switch on, a track changed on an episode's page without playing is recorded and applied like one changed during playback.
17. An episode whose file matches an ignore pattern is never written.
18. Applying preferences raises `tracks.applied` naming only that user.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Changing default scope; changing what records a preference.
- **Never:** Log user tokens; Act for opted-out users.

## Open questions
- Default scope (**decided 2026-10-27:** show + next, as in PAL).
- Tokens for PIN-protected home users: to be verified (task 11.0).
