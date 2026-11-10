# Spec: download clients (v1)

**Module:** `downloaders` · **Depends on:** core, notifications · **Decisions:** ADR-0017 · **Status:** approved 2026-11-10

## Objective
Talk to the user's download clients and be the **single owner** of what Autoplow asks of them: pausing, and download and upload speed limits. Other modules say what they want; this module makes it so and keeps it so.

## Non-goals
- Managing downloads, queues, categories or torrents
- Deciding *when* to pause or limit (that belongs to `upload` and `throttle`)
- Changing any client setting other than pause state and the global speed limits

## Clients
| Client | Pause and resume | Download limit | Upload limit |
|---|---|---|---|
| SABnzbd | yes | yes | n/a (usenet does not upload) |
| NZBGet | yes | yes | n/a |
| qBittorrent | no (v1) | yes | yes |

- Each client is added with a URL and its credentials (API key, or username and password). Credentials are stored encrypted, like every other secret.
- Adding a client checks the connection and reads its version.
- **Verification first:** each client's pause and speed-limit calls, their units, and how the client reports its current limit are verified against a pinned version and recorded in `docs/platform-notes/` before that client is implemented. This spec does not assume them.

## One owner, one desired state
- **Requests:** `upload` and `throttle` never call a client. They hand this module a request:
  - **Pause**, with a reason. `upload` uses "uploads are running" and "free space is low".
  - **Limits**: a download limit and an upload limit, or unlimited. `throttle` sets these.
- **Desired state** per client is the combination of all current requests:
  - Paused while at least one pause reason is active.
  - Otherwise running at the current limits.
- **Apply:** a change is applied to the client at once.
- **Reconcile:** runs periodically (default every minute) and compares the client's real state with the desired state. Any difference is corrected: a client restart, a manual change in the client's own UI, a missed call.
- **Pause and limits together:** resuming a client never drops its limits. They are re-applied as part of the resume.

## Autoplow owns the speed limit
*(decided 2026-11-10)*
- Once a client has limits managed by Autoplow, its global download and upload limits are whatever Autoplow last set. A limit set in the client's own UI is overwritten at the next reconcile.
- The limit with no streams active (the **idle limit**) is set in Autoplow, per client and per direction. The default is unlimited.
- The UI says this plainly where limits are switched on for a client.
- **When management ends** (the client is removed, its limits are switched off, or Autoplow shuts down cleanly), the idle limit is applied once more, so a client is never left throttled.
- **After a crash,** the first reconcile after restart corrects the client.

## Things that can override Autoplow
- A client's own scheduler or alternative-speed mode can change the effective limit behind Autoplow's back. Which of these exist, and whether they can be detected, is part of the verification above.
- **Rule:** where an override is detectable, Autoplow reports it as a `downloader.error` with a clear message and leaves the mode alone. It never switches a client's modes on or off.

## Failures
- An unreachable client, or a rejected call, is retried with backoff and raises `downloader.error`.
- A failing client never blocks uploads or the throttle's other effects.
- **Guarantees:**
  - A client paused by Autoplow is always resumed: when the last pause reason ends, on error, on shutdown, and by reconcile after a crash.
  - A client limited by Autoplow always gets its idle limit back under the same conditions.

## Acceptance criteria
1. SABnzbd, NZBGet and qBittorrent can be added, tested and removed; credentials are stored encrypted and never appear in logs.
2. With two pause reasons active, the client stays paused until both have ended.
3. Resuming a paused client re-applies its current limits in the same reconcile.
4. A limit change requested by `throttle` reaches the client within 5 s.
5. A limit changed in the client's own UI is put back to the desired value within one reconcile interval.
6. On clean shutdown, and when limit management is switched off or the client is removed, the idle limit is applied. After a simulated crash, the first reconcile corrects pause state and limits.
7. A client that is unreachable raises `downloader.error`, is retried with backoff, and does not delay uploads or other clients.
8. A detectable override (the client's alternative-speed mode or scheduler) is reported and never changed.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** supporting another client; pausing qBittorrent.
- **Never:** change client settings other than pause state and the global speed limits; let `upload` or `throttle` call a client directly.

## Open questions
- ~~Whether qBittorrent should also be pausable by the low-free-space guard~~ (**decided 2026-11-10:** no; pausing all torrents also stops seeding, so qBittorrent is rate-limited only in v1).
- The reconcile interval (**decided 2026-11-10:** 1 minute).
