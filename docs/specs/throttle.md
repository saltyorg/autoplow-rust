# Spec: the throttle (v1)

**Module:** `throttle` · **Depends on:** targets, rclone · **Decisions:** ADR-0003 · **Status:** approved 2026-10-27

## Objective
Keep uploads from degrading playback: adapt rclone's bandwidth to active streams on all media servers, robustly against bad session data.

## Non-goals
- Time-of-day bandwidth schedules (upload windows cover this)
- Per-remote bandwidth limits (rclone's limit is process-wide)

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

## Modes (the user picks one)
| Mode | Limit |
|---|---|
| Tiers | A user table mapping stream count to a limit (for example 0 → unlimited, 1 → 80M, 3 → 40M, 6+ → 10M) |
| Per stream | `max − n × reserve`, with a floor |
| By bitrate | `total upstream − Σ min(stream bitrate, cap, media bitrate) × (1 + headroom)`, with a floor |

## Bitrate sanity
- Each stream's bitrate is clamped to a configurable maximum, for example 200 Mbps.
- It is also clamped to the media file's own bitrate when the session reports it.
- An outlier reading is logged once per session.

## Effects
- The limit is applied through rclone `core/bwlimit`. Bandwidth is shared by every transfer, as with the rclone CLI.
- Optionally, no new transfers start above N streams. Transfers already running continue, throttled.
- Every change is published on the event stream and the metrics.

## Acceptance criteria
1. Each media server's sessions are counted once, whichever transport (websocket or polling) delivered them.
2. Paused sessions never count; LAN sessions are excluded only when the option is on.
3. In each mode (tiers, per-stream, by-bitrate) the computed limit matches the mode's formula for a table of session sets.
4. A session reporting an absurd bitrate (e.g. 10 Gbps) is clamped to the per-stream cap and the media bitrate and logged once.
5. A limit change reaches `core/bwlimit` within 5 s of the session change.
6. With 'no new transfers above N streams' enabled, no transfer starts above N; running transfers continue at the limit.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Adding new policy modes.
- **Never:** Count a session twice; Block on a websocket reader.

## Open questions
- Default per-stream bitrate cap (**decided 2026-10-27:** 200 Mbps).
