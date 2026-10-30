# Spec: notifications (v1)

**Module:** `notifications` · **Depends on:** core · **Decisions:** ADR-0008 · **Status:** approved 2026-10-27

## Objective
Tell the admin about failures, health changes, parity findings and activity on their chosen channels, without losing or flooding messages.

## Non-goals
- Per-viewer notifications
- Chat-ops commands

## Channels
- **Discord:** webhook with embeds; respects Discord's rate-limit headers.
- **Apprise:** POST to an Apprise API server (`/notify` with a stateless URL list, or a config key).
- **Generic webhook:** a JSON POST of `{events:[{type, category, timestamp, summary, details}]}` with optional headers.

## Event catalogue
Each event belongs to a category. Users subscribe at the level of individual event types. *(Draft list.)*

| Category | Event types |
|---|---|
| Failures & health | `target.unavailable`, `target.recovered`, `remote.unhealthy`, `remote.quota`, `remote.recovered`, `anchor.missing`, `anchor.restored`, `item.deadlettered`, `downloader.error`, `arr.connection.drift`, `gdrive.account.revoked`, `gdrive.monitor.stopped`, `component.failing` |
| Library parity | `parity.mismatch.found`, `parity.fix.applied`, `parity.fix.failed`, `parity.merged.manual`, `parity.run.completed` |
| Uploads | `upload.completed` (aggregated), `upload.failed`, `downloader.paused`, `downloader.resumed`, `throttle.changed` |
| Scans | `scan.delivered` (aggregated), `scan.failed` |

Notes on the health events *(added 2026-10-30)*:
- `gdrive.account.revoked`: Google revoked or expired an account's grant. Every monitor using that account stops; it is reported once, for the account, not again per monitor.
- `gdrive.monitor.stopped`: a monitor stopped for a reason of its own, such as a missing crypt remote or names that mostly fail to decrypt.
- `component.failing`: a background component restarted 3 times within 10 minutes (the default) and is still restarting with backoff. Single restarts are only logged.

## Routing
- Each notification target has a list of subscribed event types, so different event types can go to different targets.
- An optional filter per subscription narrows events by trigger, target or remote *(decided 2026-10-27)*.

## Delivery
- **Queue:**
  - Each event is written to a durable `notification_outbox` table in the same transaction as the state change that caused it.
  - The dispatcher aggregates events per (notification target, event type) over a window (default 10s) into one message.
- **Retries:** exponential backoff that honours `Retry-After`. After N attempts the message is dead-lettered, and that is visible in the UI.
- **Retention:** delivered rows are pruned after a retention period.

## Acceptance criteria
1. An event recorded in the same transaction as its state change is delivered after a restart even if the process crashed before sending.
2. Events of the same type for the same target within the aggregation window produce one message.
3. Discord rate limits and `Retry-After` are honoured; after N failed attempts the message is dead-lettered and visible in the UI.
4. Subscriptions filter by event type per notification target; unsubscribed types are never sent.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Adding channels.
- **Never:** Include secrets in notification bodies.

## Open questions
- Final event catalogue (draft in this spec).
