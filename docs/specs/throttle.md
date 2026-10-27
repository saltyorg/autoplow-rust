# Spec: the throttle (v1)

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
