# Spec: the throttle (v1)

**Module:** `throttle` · **Depends on:** targets, rclone, downloaders · **Decisions:** ADR-0003, ADR-0017 · **Status:** approved 2026-10-27; download-client limits approved 2026-11-10

## Objective
Keep other traffic from degrading playback: adapt rclone's upload bandwidth and the download clients' speed limits to active streams on all media servers, robustly against bad session data. Each of these works on its own: a user can limit download clients without using Autoplow's uploads at all.

## Non-goals
- Time-of-day bandwidth schedules (upload windows cover this)
- Per-remote bandwidth limits (rclone's limit is process-wide)
- One shared bandwidth budget split automatically between rclone and download clients (each has its own limits)
- Per-torrent or per-category limits

## Session sources
- **Push sources:**
  - Plex websocket notifications.
  - Emby and Jellyfin websocket `SessionsStart`.
  - Tofa: **websocket (required)** once the Tofa docs cover it; until then `GET /api/v1/system/playback/sessions` is a polled fallback.
- **Polled sources:**
  - Any target configured for polling.
- **Counting rules:**
  - Each target's sessions are counted **once**. autoplow counted them twice.
  - A session registry keeps the latest state of each session and expires stale ones.

## Counting
- Paused sessions are never counted.
- Excluding LAN streams is optional. The UI explains that it only helps when the NIC/LAN is faster than the WAN upstream.

## What gets limited
*(added 2026-11-10)*
- A **limiter** is one thing the throttle controls:
  - rclone's upload bandwidth.
  - A download client's download speed.
  - A download client's upload speed (torrent clients only).
- Each limiter is switched on or off on its own and has **its own limits**. There is no shared budget: rclone and a seeding torrent client use the same upstream, and the user decides how much each may take.
- The throttle works with any combination, including download clients only, with no upload destinations configured. The rclone limiter is offered only while rclone is in use (see [the rclone spec](rclone.md)).
- All limiters use the same session count and the same counting rules.

## Modes (one per limiter)
| Mode | Limit | Available for |
|---|---|---|
| Tiers | A user table mapping stream count to a limit (for example 0 → unlimited, 1 → 80M, 3 → 40M, 6+ → 10M) | every limiter |
| Per stream | `max − n × reserve`, with a floor | every limiter |
| By bitrate | `total upstream − Σ min(stream bitrate, cap, media bitrate) × (1 + headroom)`, with a floor | rclone upload only |

- **The limit with no streams** is part of the mode: the 0 row of a tiers table, or `max` in per-stream mode. For a download client this is its idle limit (see [the downloaders spec](downloaders.md)).

## Bitrate sanity
- Each stream's bitrate is clamped to a configurable maximum, for example 200 Mbps.
- It is also clamped to the media file's own bitrate when the session reports it.
- An outlier reading is logged once per session.

## Effects
- **rclone:** the limit is applied through rclone `core/bwlimit`. Bandwidth is shared by every transfer, as with the rclone CLI.
- **Download clients:** the limits are handed to the `downloaders` module, which applies them and keeps them applied. The throttle never calls a client itself.
- Optionally, no new uploads start above N streams. Transfers already running continue, throttled.
- A limiter whose target is unavailable (rclone restarting, a client unreachable) does not hold up the others.
- Every change is published on the event stream and the metrics.

## Acceptance criteria
1. Each media server's sessions are counted once, whichever transport (websocket or polling) delivered them.
2. Paused sessions never count; LAN sessions are excluded only when the option is on.
3. In each mode (tiers, per-stream, by-bitrate) the computed limit matches the mode's formula for a table of session sets.
4. A session reporting an absurd bitrate (e.g. 10 Gbps) is clamped to the per-stream cap and the media bitrate and logged once.
5. A limit change reaches `core/bwlimit` within 5 s of the session change.
6. With 'no new transfers above N streams' enabled, no transfer starts above N; running transfers continue at the limit.
7. With only download-client limiters switched on and no upload destinations, a session change produces the client limits from each limiter's own mode, and nothing is sent to rclone.
8. Two limiters with different tables produce different limits from the same session set; changing one limiter's table does not change the other's result.
9. A download client's limit request is handed to `downloaders` within 5 s of the session change, and an unreachable client does not delay the rclone limit.
10. By-bitrate cannot be selected for a download-client limiter (rejected by the API with a field error).

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Adding new policy modes.
- **Never:** Count a session twice; Block on a websocket reader; Call a download client directly.

## Open questions
- Default per-stream bitrate cap (**decided 2026-10-27:** 200 Mbps).
