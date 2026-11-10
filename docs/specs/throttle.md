# Spec: the throttle (v1)

**Module:** `throttle` · **Depends on:** core, targets, rclone, downloaders, upload · **Decisions:** ADR-0003, ADR-0017 · **Status:** approved 2026-10-27; download-client limits approved 2026-11-10

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
  - A session registry keeps the latest state of each session. A session with no update for 2 minutes is dropped.

## Counting
- Paused sessions are never counted.
- **What counts** *(decided 2026-11-10)*: films, episodes and live TV. Music, photos and trailers do not count by default; each kind can be switched on. In by-bitrate mode a counted stream contributes its own bitrate.
- Excluding LAN streams is optional. Whether a stream is local comes from the media server's own report for that session. The UI explains that it only helps when the NIC/LAN is faster than the WAN upstream.
- **A server that can't be read** *(decided 2026-11-10)* counts as zero streams at once: a server that is down is not streaming. The Throttle page says its count is assumed.
- **"Can't be read"** means the live connection is down **and** a poll has failed. While a websocket reconnects and polling still answers, the count is the polled one and nothing changes.
- A disabled target is not read and counts as zero.

## Units
- **Limits** are bytes per second, written the way rclone writes them: `80M` is 80 MiB/s. The UI shows them as MB/s.
- **Stream bitrates** are bits per second (Mbit/s), as media servers report them.
- By-bitrate mode converts between the two explicitly (8 bits to the byte). Every mixed calculation is covered by a test.
- The lowest limit that can be set is 100 kB/s. Stopping is done by pausing or holding, never by a limit of zero.

## Settling
- A change that **lowers** a limit is applied at once.
- A change that **raises** a limit is applied only after the stream count has stayed at the lower level for 30 seconds (configurable), so someone pausing and resuming does not cause a burst of changes.

## Manual override
*(decided 2026-11-10)*
- From the Throttle page the admin can set "no limits" or one fixed limit, for 1 hour, until the next morning, or until switched off.
- While it is on, it replaces every limiter's own result, the page shows it prominently with the time left, and it ends by itself.
- It is persisted, so it survives a restart for the time it has left.

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
| By bitrate | `total upstream − Σ min(stream bitrate, cap, media bitrate) × (1 + headroom)`, with a floor. Headroom defaults to 20 %. | rclone upload only |

- **The limit with no streams** is part of the mode: the 0 row of a tiers table, or `max` in per-stream mode. For a download client this is its idle limit (see [the downloaders spec](downloaders.md)).

## Pausing a client on streams
*(Decided 2026-11-10.)* Besides limiting, a download client that can be paused (SABnzbd and NZBGet) can be **paused above a number of streams**, set per client and off by default. It uses the same counting and settling rules as limits: paused within 5 s of reaching the number, resumed only after the count has stayed below it for the settling time. The pause is one more reason in the [downloaders spec](downloaders.md), beside the two from `upload`.

## Bitrate sanity
- Each stream's bitrate is clamped to a configurable maximum, for example 200 Mbps.
- It is also clamped to the media file's own bitrate when the session reports it.
- An outlier reading is logged once per session.

## Effects
- **rclone:** the limit is applied through rclone `core/bwlimit`. Bandwidth is shared by every transfer, as with the rclone CLI.
- **Download clients:** the limits are handed to the `downloaders` module, which applies them and keeps them applied. The throttle never calls a client itself.
- Optionally, no new uploads start above N streams. Throttle places a hold on uploads (see the upload spec) and lifts it when the count drops; transfers already running continue, throttled. The setting is with the counting options on the Throttle page.
- A limiter whose rclone or client is unavailable (rclone restarting, a client unreachable) does not hold up the others.
- Every change is published on the event stream and the metrics.

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `throttle.changed`: a limiter's limit changed; several at once are grouped.

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
11. A music stream does not change any limit by default; with music switched on, it counts.
12. When a server becomes unreadable its streams stop counting at once, and the page marks that server's count as assumed.
13. A limit is lowered within 5 s of a stream starting, and raised only after the count has stayed lower for the settling time; a pause followed by a resume within that time causes no change.
14. A manual override replaces every limiter's result for its duration, ends by itself, and is still in force after a restart within that time.
15. By-bitrate results match hand-calculated values for a table mixing Mbit/s bitrates and MiB/s limits; a limit below 100 kB/s is refused.
16. A client set to pause above N streams is paused within 5 s of reaching N and resumed only after the count has stayed below N for the settling time.
17. A websocket that drops while polling still answers changes no limit; a server whose connection and poll both fail counts as zero at once.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Adding new policy modes.
- **Never:** Count a session twice; Block on a websocket reader; Call a download client directly.

## Open questions
- Default per-stream bitrate cap (**decided 2026-10-27:** 200 Mbps).
