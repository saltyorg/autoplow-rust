# Spec: notifications (v1)

**Module:** `notifications` · **Depends on:** core · **Decisions:** ADR-0008 · **Status:** approved 2026-10-27

## Objective
Tell the admin about failures, health changes, parity findings and activity on their chosen channels, without losing or flooding messages.

## Non-goals
- Per-viewer notifications
- Chat-ops commands
- User-written message templates, quiet hours and severity routing (v1 messages have one fixed format)

## Channels
- **Discord:** webhook with embeds; respects Discord's rate-limit headers.
- **Apprise:** POST to an Apprise API server (`/notify` with a stateless URL list, or a config key).
- **Generic webhook:** a JSON POST of `{events:[{type, category, timestamp, summary, details}]}` with optional headers.

## Event catalogue
Each event belongs to a category. Users subscribe at the level of individual event types. These 29 types are the v1 catalogue *(final 2026-11-10)*.

| Category | Event types |
|---|---|
| Failures & health | `target.unavailable`, `target.recovered`, `remote.unhealthy`, `remote.quota`, `remote.recovered`, `anchor.missing`, `anchor.restored`, `item.deadlettered`, `downloader.error`, `arr.connection.drift`, `arr.unavailable`, `arr.recovered`, `gdrive.account.revoked`, `gdrive.monitor.stopped`, `component.failing`, `rclone.unsupported`, `backup.failed` |
| Library parity | `parity.mismatch.found`, `parity.fix.applied`, `parity.fix.failed`, `parity.merged.manual`, `parity.run.completed` |
| Uploads | `upload.completed` (aggregated), `upload.failed`, `downloader.paused`, `downloader.resumed`, `throttle.changed` |
| Scans | `scan.delivered` (aggregated), `scan.failed` |

Notes on the health events *(added 2026-10-30)*:
- `gdrive.account.revoked`: Google revoked or expired an account's grant. Every monitor using that account stops; it is reported once, for the account, not again per monitor.
- `gdrive.monitor.stopped`: a monitor stopped for a reason of its own, such as a missing crypt remote or names that mostly fail to decrypt.
- `rclone.unsupported`: the rclone in use is older than the minimum this Autoplow release supports, so uploads and crypt name decoding are off until it is updated. Raised once per start, not repeatedly.
- `backup.failed`: a scheduled or on-demand database backup failed.
- `component.failing`: a background component restarted 3 times within 10 minutes (the default) and is still restarting with backoff. Single restarts are only logged.

## What a message contains
- **Fixed format:** a title, one or two sentences in plain words, a severity (problem, recovered or information), the time in the configured time zone, and a link to the Autoplow page where it can be acted on.
- **The link** uses a setting for Autoplow's address in a browser. Without it, messages carry no link.
- **Aggregated events** (`upload.completed`, `scan.delivered`, and any type when several are grouped) say how many, over what time span, and name up to five examples.
- **Generic webhook payload:** `{events:[{type, category, timestamp, summary, details}]}`. `details` is typed per event type and documented with the API.
- No message ever contains a secret.

## Routing
- Each channel has a list of subscribed event types, so different event types can go to different channels.
- **One optional filter per channel** narrows everything it receives by trigger, target or remote *(decided 2026-11-10; replaces the earlier per-subscription filter)*. A different filter needs another channel.
- **Test:** a channel can be sent a test message at any time; it bypasses subscriptions and filters and is not retried.

## Keeping the noise down
*(decided 2026-11-10)*
- **Only problems that last.** A problem event notifies only once the problem has lasted 2 minutes (configurable). This applies to `target.unavailable`, `arr.unavailable`, `remote.unhealthy`, `anchor.missing`, `downloader.error` and `gdrive.monitor.stopped`.
  - The matching recovery event is sent only if the problem was sent.
  - A source that keeps flipping is reported once as unstable, not on every flip.
  - The Health page always shows the current state at once, whatever was notified.
- **Storms.** When more than 20 messages of one type are waiting for one channel, they collapse into a single summary: the count, the time span, up to five examples and a link. While the storm continues, a further summary is sent at most every 15 minutes.

## Delivery
- **Queue:**
  - Each event is written to a durable `notification_outbox` table in the same transaction as the state change that caused it.
  - The dispatcher aggregates events per (channel, event type) over a window (default 10s) into one message.
- **Retries:** backoff from 30 s, doubling to at most 30 minutes, honouring `Retry-After`. After 8 attempts (configurable), about an hour and a half, the message is dead-lettered, and that is visible in the UI.
- **Permanent failures:** an answer that will not change (the webhook no longer exists, the credentials are refused) dead-letters the message at once instead of retrying. The channel is then shown as failing, on its row and on the Health page.
- **Order:** messages for one channel are sent in the order their events happened. A message about a source waits for an earlier one about the same source, so "recovered" never arrives before "unavailable".
- **What can't be notified:** a problem that stops Autoplow writing to its database can't be recorded for delivery. It shows on the Health page and in the log only.
- **Undelivered messages** *(added 2026-10-30)*:
  - The UI offers **Send again** and **Discard** for each one, and **Discard all** per channel.
  - They are pruned automatically after 30 days (configurable), so they can't pile up when nobody acts on them.
- **Disabled channels:** a channel can be switched off. While it is off, nothing is queued for it, and switching it back on doesn't send what was missed.
- **Retention:** delivered messages are pruned after 7 days (configurable).

## Acceptance criteria
1. An event recorded in the same transaction as its state change is delivered after a restart even if the process crashed before sending.
2. Events of the same type for the same target within the aggregation window produce one message.
3. Discord rate limits and `Retry-After` are honoured; after 8 failed attempts the message is dead-lettered and visible in the UI.
4. Subscriptions filter by event type per channel; unsubscribed types are never sent.
5. An undelivered message can be sent again or discarded, one at a time or all for a channel; undelivered messages older than the pruning period are removed automatically.
6. A disabled channel gets no new messages queued while it is off, and nothing is backfilled when it is switched back on.
7. A problem that clears within 2 minutes sends nothing; one that lasts sends the problem and, later, its recovery. A source flipping repeatedly produces one "unstable" message.
8. More than 20 waiting messages of one type for one channel are delivered as one summary with the count, span and examples; a continuing storm adds at most one summary per 15 minutes.
9. A permanent failure dead-letters the message on the first attempt and marks the channel failing; a temporary one is retried on the stated schedule.
10. For one source, a recovery message is never delivered before its problem message, including when the problem message needed retries.
11. A test message reaches the channel regardless of its subscriptions and filter.
12. A message includes a link to the relevant page when the browser address is set, and never includes a secret.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Adding channels; adding or renaming an event type.
- **Never:** Include secrets in notification bodies.

## Open questions
- ~~Final event catalogue~~ (**decided 2026-11-10:** the 29 types above).
