# Spec: download clients (v1)

**Module:** `downloaders` · **Depends on:** core, notifications · **Decisions:** ADR-0017 · **Status:** approved 2026-11-10

## Objective
Talk to the user's download clients and be the **single owner** of what Autoplow asks of them: pausing, and download and upload speed limits. Other modules say what they want; this module makes it so and keeps it so.

## Non-goals
- Managing downloads, queues, categories or torrents
- Knowing whether uploads are running or how many streams there are (`upload` and `throttle` tell it)
- Changing any client setting other than pause state and the global speed limits

## Clients
| Client | Pause and resume | Download limit | Upload limit |
|---|---|---|---|
| SABnzbd | yes | yes | n/a (usenet does not upload) |
| NZBGet | yes | yes | n/a |
| qBittorrent | no (v1) | yes | yes |

- Each client is added with a URL and its credentials, stored encrypted like every other secret:
  - SABnzbd: the full API key. The NZB key cannot pause or set limits.
  - NZBGet: the control or restricted user. The add-only user cannot.
  - qBittorrent: username and password, or an API key from 5.2.0.
- Adding a client reads its version and then makes a call that needs those rights, so a key that is too weak is refused when it is saved. The version call alone proves nothing: SABnzbd answers it without a key.
- **Oldest versions supported:** SABnzbd 3.7.2, NZBGet 21.1, qBittorrent 4.5.0. An older client is refused with the version found.
- A client can be switched off without deleting it. Autoplow then leaves it completely alone, after putting back its idle limit and ending its own pause.
- **Baseline:** each client's pause and limit calls, their units and how the limit is read back are recorded in the [platform note](../platform-notes/download-clients.md), from the clients' documentation and source (2026-11-11). The earlier Autoplow never drove download clients, so there is no production precedent beyond cloudplow's pause and resume. The live checks listed in that note are run before each client is implemented (task 7.1).

## One owner, one desired state
- **Requests:** `upload` and `throttle` never call a client. They hand this module a request:
  - **Pause**, with a reason. `upload` uses "uploads are running" and "free space is low"; `throttle` uses "too many streams".
  - **Limits**: a download limit and an upload limit, or unlimited. `throttle` sets these.
- **Desired state** per client is the combination of all current requests:
  - Paused while at least one pause reason is active.
  - Otherwise running at the current limits.
- **Apply:** a change is applied to the client at once.
- **Reconcile:** runs periodically (default every minute) and compares the client's real state with the desired state. Any difference is corrected: a client restart, a manual change in the client's own UI, a missed call.
- **Pause and limits together:** resuming a client never drops its limits. They are re-applied as part of the resume.
- **Only Autoplow's own pauses are undone.** Autoplow remembers whether it paused a client. No client says who paused it, so a pause Autoplow did not make is shown as "paused by something else" (the admin, the client's scheduler, or the client itself, for example on a full disk) and is left alone. A client that Autoplow paused and something resumed is paused again while a pause reason is active; a client schedule that keeps resuming it is reported as an override.
- **A client that is already paused is not paused again.** When a pause reason starts and the client is paused already, Autoplow sends nothing and does not take the pause over. A pause call would cancel the admin's own timed resume, and Autoplow's later resume would end the admin's pause.
- **Free-space pause:** measured on a folder set per client (its download folder). It starts below the threshold and ends only once free space is back above the threshold plus a margin (10 % of the threshold by default), so it does not flip on and off.
- **"Uploads are running" pause** ends after the upload queue has been idle for a grace period (default 5 minutes).
- **Order:** Autoplow records that it is about to pause a client before it makes the call. If that cannot be recorded, the pause is not made.

## Autoplow owns the speed limit
*(decided 2026-11-10)*
- Once a client has limits managed by Autoplow, its global download and upload limits are whatever Autoplow last set. A limit set in the client's own UI is overwritten at the next reconcile.
- The limit with no streams active (the **idle limit**) is set in Autoplow, per client and per direction. The default is unlimited, which replaces a limit configured in the client itself; the UI says so.
- **Limits are whole KiB/s.** NZBGet takes whole KiB/s and qBittorrent stores whole KiB/s, so a limit is rounded down to that before it is sent, and the value read back must equal the value sent.
- **Each client's form** is in the platform note. Two traps it records: SABnzbd reads a bare number of 100 or less as a percentage, so a limit is always sent as a byte count above that; NZBGet takes KiB/s but reports bytes per second.
- The UI says this plainly where limits are switched on for a client.
- **When management ends** (the client is removed, its limits are switched off, or Autoplow shuts down cleanly), the idle limit is applied once more, so a client is never left throttled.
- **After a crash,** the first reconcile after restart corrects the client.

## Things that can override Autoplow
- A client's own scheduler or alternative-speed mode can change the effective limit behind Autoplow's back.
  - **qBittorrent** reports its alternative-speed mode and whether its scheduler is on.
  - **SABnzbd and NZBGet** have no such flag. A change shows only as a limit or pause state that differs from what Autoplow set.
- **Rule:** an override is reported as a `downloader.error` with a clear message, and the mode is left alone. Autoplow never switches a client's modes on or off.
- **qBittorrent's alternative mode** *(decided 2026-11-11)*: while it is on, the ordinary limit calls change the alternative limits, not the normal ones. So on every version Autoplow sends no limit while the mode is on, and reports the override. When the mode goes off, the next reconcile applies the current limit.
- **A client restart** can drop the limit: SABnzbd does not keep a limit set through its API. The next reconcile puts it back.

## Failures
- An unreachable client, or a rejected call, is retried with backoff and raises `downloader.error`.
- A failing client never blocks uploads or the throttle's other effects.
- **Guarantees:**
  - A client paused by Autoplow is always resumed: when the last pause reason ends, on error, on shutdown, and by reconcile after a crash.
  - A client limited by Autoplow always gets its idle limit back under the same conditions.

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `downloader.paused`, `downloader.resumed`: Autoplow paused or resumed a client.
- `downloader.error`: a client is unreachable, rejects a call, or an override is detected. It has no recovery event; the client's state is on the Health page.

## Acceptance criteria
1. SABnzbd, NZBGet and qBittorrent can be added, tested and removed; credentials are stored encrypted and never appear in logs.
2. With two pause reasons active, the client stays paused until both have ended.
3. Resuming a paused client re-applies its current limits in the same reconcile.
4. A limit change requested by `throttle` reaches the client within 5 s.
5. A limit changed in the client's own UI is put back to the desired value within one reconcile interval.
6. On clean shutdown, and when limit management is switched off or the client is removed, the idle limit is applied. After a simulated crash, the first reconcile corrects pause state and limits.
7. A client that is unreachable raises `downloader.error`, is retried with backoff, and does not delay uploads or other clients.
8. A detectable override (the client's alternative-speed mode or scheduler) is reported and never changed.
9. A client paused in its own UI is not resumed by Autoplow; a client Autoplow paused is resumed when its last pause reason ends.
10. The free-space pause starts below the threshold and ends only above the threshold plus its margin.
11. A client switched off receives no further calls after its idle limit is restored and Autoplow's own pause is ended.
12. If Autoplow cannot record that it is about to pause a client, it does not pause it.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** supporting another client; pausing qBittorrent.
- **Never:** change client settings other than pause state and the global speed limits; let `upload` or `throttle` call a client directly.

## Open questions
- ~~Whether qBittorrent should also be pausable by the low-free-space guard~~ (**decided 2026-11-10:** no; pausing all torrents also stops seeding and forgets which torrents the user had stopped, so qBittorrent is rate-limited only in v1. qBittorrent 5.3.0 can pause the whole session without that loss, if this is revisited).
- The reconcile interval (**decided 2026-11-10:** 1 minute).
