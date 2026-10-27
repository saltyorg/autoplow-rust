# Spec: notifications (v1)

## Channels
- **Discord:** webhook with embeds; respects Discord's rate-limit headers.
- **Apprise:** POST to an Apprise API server (`/notify` with a stateless URL list, or a config key).
- **Generic webhook:** a JSON POST of `{events:[{type, category, timestamp, summary, details}]}` with optional headers.

## Event catalogue
Each event belongs to a category. Users subscribe at the level of individual event types. *(Draft list.)*

| Category | Event types |
|---|---|
| Failures & health | `target.unavailable`, `target.recovered`, `remote.unhealthy`, `remote.quota`, `remote.recovered`, `anchor.missing`, `anchor.restored`, `item.deadlettered`, `downloader.error`, `arr.connection.drift` |
| Library parity | `parity.mismatch.found`, `parity.fix.applied`, `parity.fix.failed`, `parity.merged.manual`, `parity.run.completed` |
| Uploads | `upload.completed` (aggregated), `upload.failed`, `downloader.paused`, `downloader.resumed`, `throttle.changed` |
| Scans | `scan.delivered` (aggregated), `scan.failed` |

## Routing
- Each notification target has a list of subscribed event types, so different event types can go to different targets.
- An optional filter per subscription narrows events by trigger, target or remote *(proposed)*.

## Delivery
- **Queue:**
  - Each event is written to a durable `notification_outbox` table in the same transaction as the state change that caused it.
  - The dispatcher aggregates events per (notification target, event type) over a window (default 10s) into one message.
- **Retries:** exponential backoff that honours `Retry-After`. After N attempts the message is dead-lettered, and that is visible in the UI.
- **Retention:** delivered rows are pruned after a retention period.
