# Spec: the upload pipeline (v1)

**Module:** `upload` · **Depends on:** core, rclone, scan, notifications, downloaders · **Decisions:** ADR-0003, ADR-0011, ADR-0020 · **Status:** approved 2026-10-27

## Objective
Move finished local media to the user's rclone remotes, or to another local folder, per file, only once it is ready (age, stability, not being written, scanned), without stalling on seeding torrents, and without ever removing a source that was not confirmed uploaded.

## Non-goals
- Service-account rotation
- Server-side mover
- Folder-size thresholds (cloudplow model)
- Defining rclone remotes (the user's rclone.conf owns them)

This consolidates the upload decisions in the ADRs in [../decisions/](../decisions/README.md). The research behind it is in [../research/upload-readiness.md](../research/upload-readiness.md).

## Model
- **Unit of work:** uploads are **per file**. A file enters the upload queue from the local filesystem triggers (inotify, walk, or both) or from Arr import events.
- **Destinations:** a destination maps a local path to an ordered list of remotes taken from the user's `rclone.conf`, or local folders. Each can have a sub-path.
  - **A local or NFS folder** *(decided 2026-11-10)* can be used in place of a remote, given as an absolute path. rclone copies to it like any other target; health, cooldowns and failover apply the same way.
  - Two destinations may not have overlapping local paths.
  - **Exclude patterns** per destination keep files out of the queue (for example partial downloads). Symbolic links are never uploaded.
  - **Files already there:** when a destination is added, and at every start, its local folder is walked so files that arrived earlier are queued too.
  - **A file that disappears or is renamed** while queued is dropped from the queue without an error.
- **After a successful upload** *(decided 2026-11-10)*, per destination:
  - **Move** (default): the local file is removed once rclone confirms the upload.
  - **Copy:** the local file stays and is remembered as uploaded, so it is not sent again unless it changes.
  - **Empty folders:** with move, folders left empty by an upload are removed, but only below a set depth under the destination's local folder (default 2, so `Media/TV` stays and `Media/TV/Show` goes) *(depth decided 2026-11-10)*. On by default, switchable per destination.
- **A file already at the destination** is left to rclone, which skips an identical file and replaces a different one *(decided 2026-11-10)*. Autoplow adds no rule of its own.
- **Transport:** the supervised `rclone rcd` child, through the `rclone` module (ADR-0003). Each batch is its own job with its own stats group. Uploads are tracked by job and identity, never by file name.

## Readiness (all configurable per destination)
1. **Minimum age**
   - Age is counted from our first-seen time and **restarts whenever mtime changes**.
2. **Size stable**
   - Size, mtime, ctime and inode must be unchanged across two or more checks.
3. **Not open for writing**
   - Write-mode opens and write locks block the upload. Read-only opens never do.
   - A file is matched by dev+inode on both its `/mnt/local` identity and its mergerfs identity.
   - Long-stable hardlinked files held read-write by rTorrent or mergerfs are let through after a configurable window.
   - The process holding the file is identified, and its container when it runs in one.
   - Optionally, the upload **waits while Plex, Jellyfin or Emby has the file open**.
   - This check reads other processes' open files. As the Saltbox user it sees that user's processes; seeing other users' needs a capability granted in the service unit. At start the check tests what it can see (core, "Capabilities per feature"). Where it can't work, the UI says that only the age and stability checks apply.
4. **Scanned first**
   - Our scan for that folder must have been sent to every enabled **same-system** target whose libraries contain it. A folder no such target contains passes at once.
   - Targets elsewhere are not waited for: they can only see the file after it is uploaded, so for them the upload comes first and the scan follows (see the scan spec, "Scans and uploads").
   - **Which folder:** a destination's local path and the path scans use for the same folder differ (local disk against the merged view). Each destination records the scan-side path of its local folder, and the two are treated as one folder everywhere: here, in the open-file check and when ignoring Autoplow's own moves. Saltbox's bootstrap fills it in.
   - **The mount's delay:** each destination has a propagation delay (default 5 minutes): how long the rclone mount on this host takes to show a file after it is uploaded. Scan uses it for same-system targets. It is separate from a target's own delay, which is for a server elsewhere.
   - **Never scanned:** a file with no scan on record (it was there before Autoplow, or its event was missed) is not waited for.
   - **Not forever** *(decided 2026-11-10)*: the upload waits for those scans for up to 30 minutes (configurable per destination), then goes ahead, and the file's row says it was not scanned first. A disabled target is never waited for.
5. **Hardlinked files (`nlink > 1`)**
   - Per destination: upload normally (the UI shows "space not reclaimed"), or defer until the file has a single link.

## mtime hygiene
- **Detected problems:** mtimes in the future (more than 5 minutes ahead) and implausibly old ones (before 1990, or 0/1).
- **Fixing them is opt-in.** When enabled:
  - Future-dated local files are touched to the current time.
  - Hardlinked files are never touched.
  - Nothing is touched when the Arr's Change File Date is in use.
- **When fixing is not enabled:**
  - A warning is shown in the UI and logs.
  - The warning points to the SABnzbd `ignore_unrar_dates` setting, or NZBGet's `-tsm-` unrar switch.

## Execution
- **Concurrency:**
  - A global transfer cap, plus an optional cap per remote.
  - Bandwidth is always global through rclone `core/bwlimit`, the same behaviour as the rclone CLI.
  - rclone's own transfer count does not cap single-file transfers, so both caps are enforced here.
- **rclone options for a remote** (chunk size, request pacing, stopping at the upload limit) belong to the remote, not the destination, so two destinations on one remote cannot disagree. They are set in the remote's dialog under Settings › rclone, which a destination's remote row links to; see the [rclone spec](rclone.md).
- **Failover:**
  - Decided by **remote health**.
  - A remote with repeated failures, or a quota or upload-limit error, gets a cooldown. For Drive, the remote's "stop at the upload limit" option makes rclone report the limit as an error at once.
    - Upload limit or quota: 24 hours (configurable per remote).
    - Five failures in a row: 15 minutes, doubling to at most 6 hours, reset by a success.
  - When every remote of a destination is cooling down, its files wait and `remote.quota` or `remote.unhealthy` is raised.
  - During the cooldown, the destination's files go to its next remote.
- **Retries:**
  - Each file is retried with backoff. After 5 attempts (configurable) it is marked failed, raises `upload.failed`, and is listed on the Uploads page with **Retry** and **Discard**. Discard only forgets the queue entry; the local file is untouched.
- **Order:** the file that became ready first goes first.
- **History:** finished uploads are kept for 30 days (configurable).
  - The source is never removed unless rclone reports success.
- **Schedule windows:** global, with an optional set per destination that replaces the global one *(decided 2026-11-10)*.
  - New transfers start only inside a window.
  - Transfers already in flight finish when the window closes.
- **Throttle:** bandwidth tiers by stream count, plus optionally "no new transfers above N streams". Both belong to the [throttle spec](throttle.md); for the second, throttle places a hold here and lifts it again.
- **Manual controls** (rclone cannot pause a transfer, so there is no "pause"):
  - **Hold new uploads:** a toggle. While on, no new transfer starts; transfers in flight finish. The hold is persisted and survives a restart. A hold placed by throttle (too many streams) is separate from the admin's: it shows its reason, and lifting one never lifts the other.
  - **Stop:** for one transfer or all of them. Calls rclone `job/stop`; the source stays intact and the file is re-queued. A re-queued file restarts from the beginning unless the backend resumes uploads.

- **A source that changes during its transfer** (an upgrade replaces or deletes it): the transfer is stopped, anything it left on the remote is removed, and the new file is queued in the normal way.
- **When rclone itself is unavailable** (restarting, hung, or older than the minimum): files wait. Nothing counts as an attempt, and no remote's health changes.
- **Upload now** *(decided 2026-11-10)*: for one destination or all. Everything waiting is uploaded at once, ignoring the upload window, the minimum age and the wait for scans. Open-file checks, excludes and the transfer caps still apply. It ends when the queue it started with is done.
- **Stalled transfers** *(decided 2026-11-10)*: a transfer that moves no data for 10 minutes (configurable) is stopped and re-queued, and counts as a failure for its remote's health.

## Pausing download clients
The clients themselves, and the guarantee that a paused client is always resumed, belong to [the downloaders spec](downloaders.md) *(moved 2026-11-10)*. The pause conditions and their values (while uploads run, free space) are defined there too. This module only reports when its queue becomes active and when it has gone idle.

## Not in v1
- Server-side mover.
- unionfs hidden-file cleaning.
- Service-account rotation.

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `upload.completed`: files finished uploading; aggregated.
- `upload.failed`: a file is marked failed.
- `remote.unhealthy`, `remote.quota`: every remote of a destination is cooling down, for errors or for a limit.
- `remote.recovered`: a remote that was reported is usable again.

## Acceptance criteria
1. A file becomes eligible only after its readiness rules pass; any mtime change restarts its age clock.
2. A file held open for writing (or write-locked) by any process is not uploaded while the optional open-file check is active; a read-only open (e.g. a seeding torrent client, Plex) does not block.
3. When the open-file check can't see the processes it needs, it reports itself as off, the UI states that only age and stability checks apply, and uploads still work.
4. Two files with identical basenames in different folders in one batch are tracked and completed independently.
5. The source file is removed only after rclone reports the transfer successful; a cancelled or failed transfer leaves the source intact and the entry retried with backoff.
6. Killing the rclone child mid-transfer leads to restart and re-queue; the file is uploaded exactly once after recovery.
7. A remote returning quota/upload-limit errors is put on cooldown and the destination's next remote is used until the cooldown ends.
8. Outside a schedule window no new transfer starts; transfers in flight finish.
9. Hardlinked files follow the destination's policy (upload, reported as 'space not reclaimed', or defer while `nlink > 1`).
10. A pausable download client is asked to pause while uploads are active and when free space is below its threshold, and the request ends after the grace period or when space recovers. (Resume guarantees: downloaders AC2, AC6.)
11. Sustained 10 TiB/day across remotes completes without Autoplow exceeding its resource budget (project.md).
12. With "hold new uploads" on, no new transfer starts, transfers in flight complete, and the hold is still on after a daemon restart.
13. Stopping a transfer (one or all) leaves the source intact and re-queues the file; nothing is left at the destination.
14. A file whose scan cannot be sent uploads after the configured wait, marked as not scanned first; a disabled target causes no wait.
15. With move, the local file is removed only after a confirmed upload and folders left empty are removed from the configured depth down (AC25); with copy, the local file stays and is not uploaded again until it changes.
16. A file matching an exclude pattern, and a symbolic link, are never queued; a file that vanishes while queued is dropped without an error.
17. Files present in a destination's folder before it was added are queued by the first walk.
18. A file that fails 5 times is marked failed, listed with Retry and Discard, and Discard leaves the local file in place.
19. An upload-limit error cools the remote down for the configured time and five failures in a row for a growing time; with every remote cooling down, files wait and the matching event is raised.
20. A destination whose local path overlaps another's is refused.
21. A hold placed by throttle and the admin's hold are independent: each shows its reason, and lifting one leaves the other in place.
22. "Scanned first" waits only for same-system targets; a file with no scan on record is not waited for.
23. Upload now uploads everything waiting, ignoring the window, the minimum age and the wait for scans, while still skipping open files and excluded files.
24. A transfer that moves no data for the configured time is stopped, re-queued and counted against its remote.
25. With depth 2, a folder left empty two levels below the destination's local folder is removed and one at the first level is kept.
26. A destination whose target is a local folder uploads, fails over and cools down like one with a remote.
27. A destination with its own windows follows them and ignores the global ones.
28. A source replaced during its transfer leaves nothing of the old file on the remote, and the new file is uploaded.
29. While rclone is unavailable, no file gains an attempt and no remote changes health.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Touching (normalising) local file mtimes beyond the opt-in rule.
- **Never:** Delete a source without a confirmed successful transfer; Touch a hardlinked file's mtime; Write to the user's rclone.conf.

## Open questions
- Default readiness values (**decided 2026-10-27:** age 2 min, stability 2 checks 30 s apart).
