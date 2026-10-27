# Spec: Track preferences (v1)

**Module:** `track-preferences` · **Depends on:** core, targets · **Decisions:** ADR-0014 · **Status:** approved 2026-10-27

## Objective
Each Plex user's audio and subtitle choice for a show is remembered and applied to that show's other and future episodes, per user.

## Non-goals
- Movies
- Jellyfin/Emby/Tofa (Tofa has native per-profile preferences)

This was formerly Plex-Auto-Languages (PAL), the standalone app.

Plex only. Tofa has native per-profile language preferences, so PAL doesn't apply to it.

## Model
- **Preferences:** stored per (user, show). Each holds the audio stream signature and the subtitle stream signature, or "off", in the shape PAL uses for matching:
  - language
  - codec
  - channel layout
  - titles
  - flags: forced, hearing-impaired (HI), visually-impaired (VI), descriptive
- **Recording:** a preference is recorded when a user changes tracks during playback.
- **UI:** users can be listed, edited and cleared.

## Users
- **Coverage:** the owner plus shared and managed users. Each user can be opted out.
- **Tokens:**
  - Taken from the plex.tv `shared_servers` data.
  - Cached, and refreshed when a request fails.
  - **Never logged.**

## Triggers (each can be switched on or off)
1. **Play or track change**
   - Source: the websocket `playing` events. The session is resolved to its user.
   - If the streams changed, the preference is updated and the change is propagated.
2. **New or upgraded episodes**
   - Detected through timeline and activity events, plus a part-key diff, as in PAL.
   - Each stored preference for that show is applied, separately for every user.
3. **Scheduled sweep**
   - Re-applies the stored preferences to catch anything missed.

## Scope
- Configurable `level` (show or season) and `strategy` (all, or next = only episodes after the reference).
- Global defaults, with optional per-user overrides *(decided 2026-10-27)*.

## Matching
- Ported from PAL, including its tie-break tests:
  1. Filter by language, then VI, then descriptive.
  2. Score by codec, layout and titles, with the channel heuristic.
  3. Keep PAL's forced and HI subtitle semantics.
  4. Break ties by position.
- Known PAL bugs to fix:
  - Use the reference's commentary state, not the target's.
  - Consider every selected stream, not only the first.
  - Handle multi-part episodes correctly.

## Execution
- Websocket readers **only enqueue** work.
- Work is serialised per (user, show) with a keyed queue, so there are no races.
- Writes use `PUT /library/parts/{id}` with the user's token, and each write is **verified by reading it back**.

## Acceptance criteria
1. When a user changes tracks during playback, a preference is stored for (user, show) and applied to the configured scope (show/season × all/next).
2. New or upgraded episodes get every stored preference applied, per user, using that user's token; tokens never appear in logs.
3. PAL's matching test cases pass (language, VI, descriptive, forced/HI, tie-break), plus the fixed cases (reference commentary state, multiple selected streams, multi-part episodes).
4. Concurrent events for the same (user, show) are serialised; the final selection equals the last preference.
5. Writes are verified by read-back; a user opted out is never modified.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Changing default scope.
- **Never:** Log user tokens; Act for opted-out users.

## Open questions
- Default scope (**decided 2026-10-27:** show + next, as in PAL).
